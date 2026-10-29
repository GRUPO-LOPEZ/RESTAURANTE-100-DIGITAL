-- Fase 2 · Etapa 2.1 A: catálogo de materias primas (docs/fases/fase-2-recetario.md, secciones 6 a 8;
-- plan de la sesión en docs/fases/fase-2-plan.md y ADR-0020). Sin precios ni rendimientos: llegan
-- en 2.1 B y 2.1 C.
--   1. Tipos.
--   2. Unidades y conversiones universales (referencia global, cargada acá).
--   3. Tablas del grupo: categorías, ingredientes, alias, conversiones propias, proveedores,
--      productos de compra, alérgenos y su estado por ingrediente.
--   4. Columnas de control, auditoría y RLS (lectura con catalog.view en cualquier nivel del grupo).
--   5. Lectura: to_base_quantity (unidades, sin adivinar) y search_components (buscador).
--   6. Escritura solo por funciones, con motivo y catalog.manage en el grupo (ADR-0012).

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- 1. Tipos
-- ---------------------------------------------------------------------------
create type catalog.dimension as enum ('mass', 'volume', 'count', 'package');
comment on type catalog.dimension is
  'Dimensión de una unidad: mass (masa, base g), volume (volumen, base ml), count (conteo, base unidad) o package (envase sin contenido fijo: caja, bolsa, horma).';

create type catalog.data_source as enum ('manual', 'excel_import', 'measured', 'supplier', 'calculated', 'estimated', 'verified');
comment on type catalog.data_source is
  'Fuente de un dato (sección 6): manual, importado de Excel, medido en ensayo, informado por proveedor, calculado por el sistema, estimado o verificado por un responsable.';

create type catalog.conversion_kind as enum ('density', 'unit_weight');
comment on type catalog.conversion_kind is
  'Conversión propia de un ingrediente: density (gramos por mililitro) o unit_weight (gramos por unidad: 1 huevo, 1 atado).';

create type catalog.allergen_status as enum ('contains', 'may_contain', 'free_verified');
comment on type catalog.allergen_status is
  'Estado de un alérgeno en un ingrediente: contains (contiene), may_contain (puede contener, trazas) o free_verified (no contiene, verificado). Sin fila = sin dato: nunca se toma como "sin alérgenos".';

-- ---------------------------------------------------------------------------
-- 2. Unidades y conversiones universales (globales: sin grupo)
-- ---------------------------------------------------------------------------
create table catalog.units (
  id          uuid primary key default gen_random_uuid(),
  code        text not null check (code ~ '^[a-z_]{1,20}$'),
  name        text not null check (length(btrim(name)) between 1 and 40),
  dimension   catalog.dimension not null,
  is_base     boolean not null default false,
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint units_package_not_base check (not (is_base and dimension = 'package'))
);
create unique index units_code_key on catalog.units (code) where deleted_at is null;
-- Una sola unidad base por dimensión: g, ml y unidad.
create unique index units_base_key on catalog.units (dimension) where is_base and deleted_at is null;
comment on table catalog.units is
  'Unidades de medida (referencia global). Todo cálculo se hace en las unidades base: g, ml y unidad (sección 8).';
comment on column catalog.units.code is 'Código de la unidad (g, kg, ml, l, unit, dozen, box…). Único entre las vigentes.';
comment on column catalog.units.name is 'Nombre que se muestra, en español (g, kg, l, docena, caja…).';
comment on column catalog.units.dimension is 'Dimensión: masa, volumen, conteo o envase. Las de envase no tienen contenido fijo.';
comment on column catalog.units.is_base is 'Si es la unidad base de su dimensión (g, ml o unidad).';

create table catalog.unit_conversions (
  id            uuid primary key default gen_random_uuid(),
  from_unit_id  uuid not null references catalog.units (id) on delete restrict,
  to_unit_id    uuid not null references catalog.units (id) on delete restrict,
  factor        numeric(18,6) not null check (factor > 0),
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict
);
create unique index unit_conversions_from_key on catalog.unit_conversions (from_unit_id) where deleted_at is null;
create index unit_conversions_to_idx on catalog.unit_conversions (to_unit_id);
comment on table catalog.unit_conversions is
  'Conversiones universales dentro de una dimensión, siempre hacia su unidad base (1 kg = 1.000 g; 1 docena = 12 unidades). Nunca entre dimensiones ni para envases.';
comment on column catalog.unit_conversions.from_unit_id is 'Unidad de origen. Una sola conversión vigente por unidad.';
comment on column catalog.unit_conversions.to_unit_id is 'Unidad base de la misma dimensión.';
comment on column catalog.unit_conversions.factor is 'Cuántas unidades base hay en una unidad de origen.';

create function catalog.enforce_unit_conversion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from catalog.units;
  v_to   catalog.units;
begin
  select * into v_from from catalog.units where id = new.from_unit_id;
  select * into v_to from catalog.units where id = new.to_unit_id;
  if v_from.dimension = 'package' then
    raise exception 'Un envase (%) no tiene contenido fijo: su contenido va en cada producto de compra.', v_from.name
      using errcode = '23514';
  end if;
  if v_from.dimension <> v_to.dimension or not v_to.is_base or v_from.is_base then
    raise exception 'Una conversión universal va de una unidad a la base de su misma dimensión (% → %).', v_from.name, v_to.name
      using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function catalog.enforce_unit_conversion() is
  'Trigger (BEFORE INSERT OR UPDATE) de unit_conversions: solo hacia la base de la misma dimensión y nunca para envases.';
revoke execute on function catalog.enforce_unit_conversion() from public;
create trigger validate_unit_conversion before insert or update on catalog.unit_conversions
  for each row execute function catalog.enforce_unit_conversion();

-- ---------------------------------------------------------------------------
-- 3. Tablas del grupo
-- ---------------------------------------------------------------------------
create table catalog.ingredient_categories (
  id                uuid primary key default gen_random_uuid(),
  group_id          uuid not null references org.groups (id) on delete restrict,
  parent_id         uuid,
  name              text not null check (length(btrim(name)) between 1 and 80),
  stale_price_days  smallint check (stale_price_days between 1 and 365),
  created_at        timestamptz not null default now(),
  created_by        uuid references core.actors (id) on delete restrict,
  updated_at        timestamptz not null default now(),
  updated_by        uuid references core.actors (id) on delete restrict,
  deleted_at        timestamptz,
  deleted_by        uuid references core.actors (id) on delete restrict,
  constraint ingredient_categories_id_group_key unique (id, group_id),
  constraint ingredient_categories_parent_fkey foreign key (parent_id, group_id)
    references catalog.ingredient_categories (id, group_id) on delete restrict,
  constraint ingredient_categories_not_self check (parent_id is distinct from id)
);
create index ingredient_categories_group_idx on catalog.ingredient_categories (group_id);
create index ingredient_categories_parent_idx on catalog.ingredient_categories (parent_id, group_id) where parent_id is not null;
create unique index ingredient_categories_name_key on catalog.ingredient_categories
  (group_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)) where deleted_at is null;
comment on table catalog.ingredient_categories is 'Categorías y subcategorías de materias primas (dos niveles), por grupo.';
comment on column catalog.ingredient_categories.group_id is 'Grupo al que pertenece.';
comment on column catalog.ingredient_categories.parent_id is 'Categoría madre, si es una subcategoría. Solo dos niveles.';
comment on column catalog.ingredient_categories.name is 'Nombre. Único dentro de su categoría madre entre las vigentes, sin importar mayúsculas.';
comment on column catalog.ingredient_categories.stale_price_days is
  'Días sin actualizar después de los cuales un precio se marca como desactualizado. Vacío = el plazo general (decisión 7, etapa 2.1 C).';

create function catalog.enforce_category_levels()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.parent_id is not null
     and (exists (select 1 from catalog.ingredient_categories where id = new.parent_id and parent_id is not null)
          or exists (select 1 from catalog.ingredient_categories where parent_id = new.id and deleted_at is null)) then
    raise exception 'Las categorías tienen solo dos niveles: categoría y subcategoría.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function catalog.enforce_category_levels() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredient_categories: solo dos niveles.';
revoke execute on function catalog.enforce_category_levels() from public;
create trigger validate_category_levels before insert or update on catalog.ingredient_categories
  for each row execute function catalog.enforce_category_levels();

create table catalog.ingredients (
  id                uuid primary key default gen_random_uuid(),
  group_id          uuid not null references org.groups (id) on delete restrict,
  code              text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  name              text not null check (length(btrim(name)) between 1 and 120),
  category_id       uuid not null,
  recipe_unit_id    uuid not null references catalog.units (id) on delete restrict,
  purchase_unit_id  uuid references catalog.units (id) on delete restrict,
  storage_unit_id   uuid references catalog.units (id) on delete restrict,
  costing_unit_id   uuid references catalog.units (id) on delete restrict,
  is_active         boolean not null default true,
  notes             text check (notes is null or length(notes) <= 1000),
  created_at        timestamptz not null default now(),
  created_by        uuid references core.actors (id) on delete restrict,
  updated_at        timestamptz not null default now(),
  updated_by        uuid references core.actors (id) on delete restrict,
  deleted_at        timestamptz,
  deleted_by        uuid references core.actors (id) on delete restrict,
  constraint ingredients_id_group_key unique (id, group_id),
  constraint ingredients_category_fkey foreign key (category_id, group_id)
    references catalog.ingredient_categories (id, group_id) on delete restrict
);
create unique index ingredients_code_key on catalog.ingredients (group_id, code) where deleted_at is null;
create unique index ingredients_name_key on catalog.ingredients (group_id, lower(name)) where deleted_at is null;
create index ingredients_category_idx on catalog.ingredients (category_id, group_id);
create index ingredients_recipe_unit_idx on catalog.ingredients (recipe_unit_id);
create index ingredients_purchase_unit_idx on catalog.ingredients (purchase_unit_id) where purchase_unit_id is not null;
create index ingredients_storage_unit_idx on catalog.ingredients (storage_unit_id) where storage_unit_id is not null;
create index ingredients_costing_unit_idx on catalog.ingredients (costing_unit_id) where costing_unit_id is not null;
create index ingredients_active_idx on catalog.ingredients (group_id, is_active, lower(name)) where deleted_at is null;
create index ingredients_name_trgm_idx on catalog.ingredients using gin (lower(name) extensions.gin_trgm_ops);
comment on table catalog.ingredients is
  'Ingredientes gastronómicos (la mozzarella, no la horma de una marca): se cargan una sola vez para todo el grupo. Nunca se borran: se desactivan.';
comment on column catalog.ingredients.group_id is 'Grupo al que pertenece.';
comment on column catalog.ingredients.code is 'Código único dentro del grupo (en mayúsculas). No cambia nunca: sirve para importar sin duplicar.';
comment on column catalog.ingredients.name is 'Nombre gastronómico, sin marca. Único dentro del grupo entre los vigentes, sin importar mayúsculas.';
comment on column catalog.ingredients.category_id is 'Categoría o subcategoría.';
comment on column catalog.ingredients.recipe_unit_id is 'Unidad en que se usa en recetas: siempre una unidad base (g, ml o unidad).';
comment on column catalog.ingredients.purchase_unit_id is 'Unidad en que se compra normalmente (informativa).';
comment on column catalog.ingredients.storage_unit_id is 'Unidad en que se almacena (informativa).';
comment on column catalog.ingredients.costing_unit_id is 'Unidad en que se muestra su costo (informativa).';
comment on column catalog.ingredients.is_active is 'Si se puede usar en recetas nuevas. Desactivar no borra nada.';
comment on column catalog.ingredients.notes is 'Observaciones.';

create function catalog.enforce_recipe_unit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from catalog.units where id = new.recipe_unit_id and is_base) then
    raise exception 'La unidad de uso en recetas tiene que ser g, ml o unidad.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function catalog.enforce_recipe_unit() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredients: la unidad de uso en recetas es siempre una unidad base.';
revoke execute on function catalog.enforce_recipe_unit() from public;
create trigger validate_recipe_unit before insert or update of recipe_unit_id on catalog.ingredients
  for each row execute function catalog.enforce_recipe_unit();

create table catalog.ingredient_aliases (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  ingredient_id  uuid not null,
  alias          text not null check (alias = lower(btrim(alias)) and length(alias) between 1 and 120),
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint ingredient_aliases_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict
);
create unique index ingredient_aliases_alias_key on catalog.ingredient_aliases (group_id, alias) where deleted_at is null;
create index ingredient_aliases_ingredient_idx on catalog.ingredient_aliases (ingredient_id, group_id);
create index ingredient_aliases_trgm_idx on catalog.ingredient_aliases using gin (alias extensions.gin_trgm_ops);
comment on table catalog.ingredient_aliases is
  'Otros nombres de un ingrediente ("muzza" para mozzarella), para buscar e importar sin duplicar. Un alias apunta a un solo ingrediente del grupo.';
comment on column catalog.ingredient_aliases.group_id is 'Grupo al que pertenece. El mismo que el del ingrediente.';
comment on column catalog.ingredient_aliases.ingredient_id is 'Ingrediente al que se refiere.';
comment on column catalog.ingredient_aliases.alias is 'El otro nombre, en minúsculas. Único dentro del grupo entre los vigentes.';

create table catalog.ingredient_unit_conversions (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  ingredient_id  uuid not null,
  kind           catalog.conversion_kind not null,
  factor         numeric(18,6) not null check (factor > 0),
  source         catalog.data_source not null,
  measured_on    date not null,
  measured_by    text check (measured_by is null or length(btrim(measured_by)) between 1 and 120),
  notes          text check (notes is null or length(notes) <= 500),
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint ingredient_unit_conversions_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict
);
create unique index ingredient_unit_conversions_kind_key on catalog.ingredient_unit_conversions (ingredient_id, kind)
  where deleted_at is null;
create index ingredient_unit_conversions_ingredient_idx on catalog.ingredient_unit_conversions (ingredient_id, group_id);
comment on table catalog.ingredient_unit_conversions is
  'Conversiones propias de un ingrediente, medidas y con fuente: densidad (g por ml) o peso por unidad (g por unidad). Sin este dato, una línea que lo necesita queda como CONVERSIÓN FALTANTE: nunca se supone que 1 l pesa 1 kg.';
comment on column catalog.ingredient_unit_conversions.group_id is 'Grupo al que pertenece. El mismo que el del ingrediente.';
comment on column catalog.ingredient_unit_conversions.ingredient_id is 'Ingrediente.';
comment on column catalog.ingredient_unit_conversions.kind is 'density (g por ml) o unit_weight (g por unidad).';
comment on column catalog.ingredient_unit_conversions.factor is 'Gramos por mililitro (densidad) o gramos por unidad.';
comment on column catalog.ingredient_unit_conversions.source is 'De dónde sale el dato.';
comment on column catalog.ingredient_unit_conversions.measured_on is 'Fecha de la medición o del dato.';
comment on column catalog.ingredient_unit_conversions.measured_by is 'Quién lo midió o informó (puede no ser una persona del sistema).';
comment on column catalog.ingredient_unit_conversions.notes is 'Observaciones.';

create table catalog.suppliers (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references org.groups (id) on delete restrict,
  code         text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  name         text not null check (length(btrim(name)) between 1 and 120),
  tax_id       text check (tax_id is null or tax_id ~ '^[0-9-]{8,15}$'),
  is_internal  boolean not null default false,
  is_active    boolean not null default true,
  notes        text check (notes is null or length(notes) <= 1000),
  created_at   timestamptz not null default now(),
  created_by   uuid references core.actors (id) on delete restrict,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references core.actors (id) on delete restrict,
  deleted_at   timestamptz,
  deleted_by   uuid references core.actors (id) on delete restrict,
  constraint suppliers_id_group_key unique (id, group_id)
);
create unique index suppliers_code_key on catalog.suppliers (group_id, code) where deleted_at is null;
create unique index suppliers_name_key on catalog.suppliers (group_id, lower(name)) where deleted_at is null;
create index suppliers_group_idx on catalog.suppliers (group_id, is_active) where deleted_at is null;
comment on table catalog.suppliers is 'Proveedores del grupo. Nunca se borran: se desactivan.';
comment on column catalog.suppliers.group_id is 'Grupo al que pertenece.';
comment on column catalog.suppliers.code is 'Código único dentro del grupo (en mayúsculas).';
comment on column catalog.suppliers.name is 'Nombre. Único dentro del grupo entre los vigentes, sin importar mayúsculas.';
comment on column catalog.suppliers.tax_id is 'CUIT, si se conoce.';
comment on column catalog.suppliers.is_internal is 'Si es una unidad del propio grupo que provee a otras (por ejemplo, Pariggi; decisión 6).';
comment on column catalog.suppliers.is_active is 'Si se le sigue comprando. Desactivar no borra nada.';
comment on column catalog.suppliers.notes is 'Observaciones.';

create table catalog.purchase_products (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null references org.groups (id) on delete restrict,
  code               text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  ingredient_id      uuid not null,
  supplier_id        uuid,
  description        text not null check (length(btrim(description)) between 1 and 200),
  brand_name         text check (brand_name is null or length(btrim(brand_name)) between 1 and 80),
  package_unit_id    uuid not null references catalog.units (id) on delete restrict,
  units_per_package  integer not null default 1 check (units_per_package between 1 and 10000),
  content_per_unit   numeric(18,6) not null check (content_per_unit > 0),
  content_unit_id    uuid not null references catalog.units (id) on delete restrict,
  is_active          boolean not null default true,
  notes              text check (notes is null or length(notes) <= 1000),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint purchase_products_id_group_key unique (id, group_id),
  constraint purchase_products_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint purchase_products_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict
);
create unique index purchase_products_code_key on catalog.purchase_products (group_id, code) where deleted_at is null;
create index purchase_products_ingredient_idx on catalog.purchase_products (ingredient_id, group_id);
create index purchase_products_supplier_idx on catalog.purchase_products (supplier_id, group_id) where supplier_id is not null;
create index purchase_products_package_unit_idx on catalog.purchase_products (package_unit_id);
create index purchase_products_content_unit_idx on catalog.purchase_products (content_unit_id);
comment on table catalog.purchase_products is
  'Productos de compra: cómo se compra un ingrediente ("Mozzarella marca X, horma de 4 kg"). Varios productos pueden apuntar al mismo ingrediente. El precio va aparte (etapa 2.1 C).';
comment on column catalog.purchase_products.group_id is 'Grupo al que pertenece. El mismo que el del ingrediente.';
comment on column catalog.purchase_products.code is 'Código único dentro del grupo (en mayúsculas).';
comment on column catalog.purchase_products.ingredient_id is 'Ingrediente al que corresponde. No cambia: un producto de otro ingrediente es otro producto.';
comment on column catalog.purchase_products.supplier_id is 'Proveedor habitual (opcional: el precio dice a quién se compró).';
comment on column catalog.purchase_products.description is 'Descripción como la vende el proveedor.';
comment on column catalog.purchase_products.brand_name is 'Marca comercial, si corresponde.';
comment on column catalog.purchase_products.package_unit_id is 'Cómo viene: horma, caja, bolsa, botella, kg…';
comment on column catalog.purchase_products.units_per_package is 'Cuántas unidades trae el envase (caja de 12 botellas = 12).';
comment on column catalog.purchase_products.content_per_unit is 'Contenido de cada unidad (botella de 750 ml = 750). Obligatorio: nunca se supone.';
comment on column catalog.purchase_products.content_unit_id is
  'Unidad del contenido (masa, volumen o conteo; nunca un envase). Si no es de la dimensión de uso del ingrediente, el ingrediente tiene que tener la conversión cargada.';
comment on column catalog.purchase_products.is_active is 'Si se sigue comprando. Desactivar no borra nada.';
comment on column catalog.purchase_products.notes is 'Observaciones.';

create table catalog.allergens (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references org.groups (id) on delete restrict,
  code             text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  name             text not null check (length(btrim(name)) between 1 and 80),
  legal_reference  text check (legal_reference is null or length(btrim(legal_reference)) between 1 and 200),
  validated_by     uuid references core.actors (id) on delete restrict,
  validated_at     timestamptz,
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references core.actors (id) on delete restrict,
  deleted_at       timestamptz,
  deleted_by       uuid references core.actors (id) on delete restrict,
  constraint allergens_id_group_key unique (id, group_id),
  constraint allergens_validation_consistent check ((validated_by is null) = (validated_at is null))
);
create unique index allergens_code_key on catalog.allergens (group_id, code) where deleted_at is null;
create index allergens_validated_by_idx on catalog.allergens (validated_by) where validated_by is not null;
comment on table catalog.allergens is
  'Lista configurable de alérgenos (Código Alimentario Argentino). No se usa como válida hasta que un responsable la valida (pregunta N5).';
comment on column catalog.allergens.group_id is 'Grupo al que pertenece.';
comment on column catalog.allergens.code is 'Código único dentro del grupo (en mayúsculas).';
comment on column catalog.allergens.name is 'Nombre del alérgeno.';
comment on column catalog.allergens.legal_reference is 'Referencia normativa (artículo del Código Alimentario).';
comment on column catalog.allergens.validated_by is 'Quién validó el alérgeno en la lista. Vacío = sin validar.';
comment on column catalog.allergens.validated_at is 'Cuándo se validó.';

create table catalog.ingredient_allergens (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  ingredient_id  uuid not null,
  allergen_id    uuid not null,
  status         catalog.allergen_status not null,
  source         catalog.data_source not null,
  notes          text check (notes is null or length(notes) <= 500),
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint ingredient_allergens_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint ingredient_allergens_allergen_fkey foreign key (allergen_id, group_id)
    references catalog.allergens (id, group_id) on delete restrict
);
create unique index ingredient_allergens_key on catalog.ingredient_allergens (ingredient_id, allergen_id) where deleted_at is null;
create index ingredient_allergens_ingredient_idx on catalog.ingredient_allergens (ingredient_id, group_id);
create index ingredient_allergens_allergen_idx on catalog.ingredient_allergens (allergen_id, group_id);
comment on table catalog.ingredient_allergens is
  'Estado de cada alérgeno en cada ingrediente. Sin fila = sin dato: el plato que lo use muestra NO VERIFICADO, nunca "sin alérgenos".';
comment on column catalog.ingredient_allergens.group_id is 'Grupo al que pertenece.';
comment on column catalog.ingredient_allergens.ingredient_id is 'Ingrediente.';
comment on column catalog.ingredient_allergens.allergen_id is 'Alérgeno.';
comment on column catalog.ingredient_allergens.status is 'Contiene, puede contener (trazas) o no contiene (verificado). Quién lo cargó queda en la auditoría.';
comment on column catalog.ingredient_allergens.source is 'De dónde sale el dato.';
comment on column catalog.ingredient_allergens.notes is 'Observaciones.';

-- Contenido de un producto: nunca un envase; de otra dimensión, solo si el ingrediente tiene la
-- conversión (densidad o peso por unidad). Así no se carga un producto que no se puede costear.
create function catalog.enforce_product_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_content catalog.dimension;
  v_use     catalog.dimension;
  v_needs   catalog.conversion_kind[];
begin
  select dimension into v_content from catalog.units where id = new.content_unit_id;
  select u.dimension into v_use
    from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id
   where i.id = new.ingredient_id;
  if v_content = 'package' then
    raise exception 'El contenido va en g, kg, ml, l o unidades: un envase no dice cuánto trae.' using errcode = '23514';
  end if;
  if v_content <> v_use then
    v_needs := case
      when array[v_content, v_use] <@ array['mass', 'volume']::catalog.dimension[] then array['density']
      when array[v_content, v_use] <@ array['mass', 'count']::catalog.dimension[] then array['unit_weight']
      else array['density', 'unit_weight'] end::catalog.conversion_kind[];
    if (select count(distinct kind) from catalog.ingredient_unit_conversions
         where ingredient_id = new.ingredient_id and deleted_at is null and kind = any (v_needs)) < cardinality(v_needs) then
      raise exception 'El ingrediente se usa en otra unidad: primero cargá su %.',
        case when v_needs = array['density']::catalog.conversion_kind[] then 'densidad'
             when v_needs = array['unit_weight']::catalog.conversion_kind[] then 'peso por unidad'
             else 'densidad y su peso por unidad' end
        using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.enforce_product_content() is
  'Trigger (BEFORE INSERT OR UPDATE) de purchase_products: el contenido nunca es un envase y, si es de otra dimensión que la de uso, el ingrediente tiene que tener la conversión.';
revoke execute on function catalog.enforce_product_content() from public;
create trigger validate_product_content before insert or update of content_unit_id, ingredient_id on catalog.purchase_products
  for each row execute function catalog.enforce_product_content();

-- ---------------------------------------------------------------------------
-- 4. Control, auditoría y RLS
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['units', 'unit_conversions', 'ingredient_categories', 'ingredients', 'ingredient_aliases',
                           'ingredient_unit_conversions', 'suppliers', 'purchase_products', 'allergens',
                           'ingredient_allergens'] loop
    execute format('alter table catalog.%I enable row level security', t);
    execute format('revoke all on catalog.%I from public, anon, authenticated, service_role', t);
    execute format(
      'create trigger set_control_columns before insert or update on catalog.%I
         for each row execute function core.set_control_columns()', t);
    execute format(
      'create trigger log_change after insert or update or delete on catalog.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on catalog.%I
         for each statement execute function core.reject_truncate()', t);
    -- Las columnas de control, con el mismo texto en todas las tablas.
    execute format('comment on column catalog.%I.id is %L', t, 'Identificador.');
    execute format('comment on column catalog.%I.created_at is %L', t, 'Cuándo se creó (lo pone la base).');
    execute format('comment on column catalog.%I.created_by is %L', t, 'Quién lo creó (lo pone la base).');
    execute format('comment on column catalog.%I.updated_at is %L', t, 'Cuándo se cambió por última vez (lo pone la base).');
    execute format('comment on column catalog.%I.updated_by is %L', t, 'Quién lo cambió por última vez (lo pone la base).');
    execute format('comment on column catalog.%I.deleted_at is %L', t, 'Cuándo se borró (borrado lógico). Vacío si está vigente.');
    execute format('comment on column catalog.%I.deleted_by is %L', t, 'Quién lo borró (lo pone la base).');
  end loop;
end
$$;

-- Lectura (ADR-0005 y ADR-0012): solo authenticated, solo SELECT. El catálogo es de todo el
-- grupo: lo lee quien tenga catalog.view en cualquier nivel del grupo.
grant usage on schema catalog to authenticated;
grant select on catalog.units, catalog.unit_conversions, catalog.ingredient_categories, catalog.ingredients,
                catalog.ingredient_aliases, catalog.ingredient_unit_conversions, catalog.suppliers,
                catalog.purchase_products, catalog.allergens, catalog.ingredient_allergens to authenticated;

create policy units_select on catalog.units for select to authenticated
  using (deleted_at is null and (select core.current_session_ok()));
create policy unit_conversions_select on catalog.unit_conversions for select to authenticated
  using (deleted_at is null and (select core.current_session_ok()));

do $$
declare
  t text;
begin
  foreach t in array array['ingredient_categories', 'ingredients', 'ingredient_aliases', 'ingredient_unit_conversions',
                           'suppliers', 'purchase_products', 'allergens', 'ingredient_allergens'] loop
    execute format(
      'create policy %I on catalog.%I for select to authenticated
         using (deleted_at is null and group_id in (select core.visible_group_ids(''catalog.view'')))',
      t || '_select', t);
  end loop;
end
$$;

-- Unidades y conversiones universales: las carga la migración, una sola vez.
do $$
begin
  perform core.set_change_context('Unidades de medida del recetario (sección 8)', 'maintenance');
  insert into catalog.units (code, name, dimension, is_base) values
    ('g', 'g', 'mass', true), ('kg', 'kg', 'mass', false),
    ('ml', 'ml', 'volume', true), ('l', 'l', 'volume', false),
    ('unit', 'unidad', 'count', true), ('dozen', 'docena', 'count', false),
    ('pack', 'paquete', 'package', false), ('box', 'caja', 'package', false), ('bag', 'bolsa', 'package', false),
    ('bottle', 'botella', 'package', false), ('can', 'lata', 'package', false), ('bunch', 'atado', 'package', false),
    ('wheel', 'horma', 'package', false), ('jug', 'bidón', 'package', false);
  insert into catalog.unit_conversions (from_unit_id, to_unit_id, factor)
  select f.id, t.id, c.factor
    from (values ('kg', 'g', 1000), ('l', 'ml', 1000), ('dozen', 'unit', 12)) as c (from_code, to_code, factor)
    join catalog.units f on f.code = c.from_code
    join catalog.units t on t.code = c.to_code;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Lectura
-- ---------------------------------------------------------------------------
-- Convierte una cantidad de un ingrediente entre dos unidades cualesquiera (no envases), pasando
-- por las bases: dentro de una dimensión con la conversión universal; entre dimensiones con la
-- densidad o el peso por unidad medidos del ingrediente. Si falta un dato devuelve
-- status = 'missing_conversion' y la cantidad vacía: nunca un número inventado ni cero.
-- La usa el motor de costos (de ml de la receta a kg del precio, caso 16). Respeta RLS.
create function catalog.convert_quantity(p_ingredient_id uuid, p_quantity numeric, p_from_unit_id uuid,
                                         p_to_unit_id uuid)
returns table (quantity numeric, status text)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_from     catalog.units;
  v_to       catalog.units;
  v_qty      numeric;
  v_to_base  numeric;
  v_density  numeric;
  v_weight   numeric;
begin
  if not exists (select 1 from catalog.ingredients where id = p_ingredient_id) then
    return query select null::numeric, 'unknown_ingredient'::text;
    return;
  end if;
  select * into v_from from catalog.units where id = p_from_unit_id and deleted_at is null;
  select * into v_to from catalog.units where id = p_to_unit_id and deleted_at is null;
  if v_from.id is null or v_to.id is null or p_quantity is null or p_quantity < 0 then
    return query select null::numeric, 'invalid_quantity'::text;
    return;
  end if;
  if v_from.dimension = 'package' or v_to.dimension = 'package' then
    return query select null::numeric, 'missing_conversion'::text;
    return;
  end if;

  -- 1. De la unidad de origen a la base de su dimensión.
  if v_from.is_base then
    v_qty := p_quantity;
  else
    select p_quantity * c.factor into v_qty
      from catalog.unit_conversions c where c.from_unit_id = v_from.id and c.deleted_at is null;
  end if;
  -- Cuántas bases hay en una unidad de destino.
  if v_to.is_base then
    v_to_base := 1;
  else
    select c.factor into v_to_base
      from catalog.unit_conversions c where c.from_unit_id = v_to.id and c.deleted_at is null;
  end if;

  -- 2. Entre dimensiones, con las conversiones medidas del ingrediente: primero a gramos y de
  --    gramos a la base de destino.
  if v_from.dimension <> v_to.dimension then
    select factor into v_density from catalog.ingredient_unit_conversions
     where ingredient_id = p_ingredient_id and kind = 'density' and deleted_at is null;
    select factor into v_weight from catalog.ingredient_unit_conversions
     where ingredient_id = p_ingredient_id and kind = 'unit_weight' and deleted_at is null;
    v_qty := case v_from.dimension
               when 'mass' then v_qty
               when 'volume' then v_qty * v_density
               when 'count' then v_qty * v_weight
             end;
    v_qty := case v_to.dimension
               when 'mass' then v_qty
               when 'volume' then v_qty / v_density
               when 'count' then v_qty / v_weight
             end;
  end if;

  if v_qty is null or v_to_base is null then
    return query select null::numeric, 'missing_conversion'::text;
    return;
  end if;
  return query select v_qty / v_to_base, 'ok'::text;
end
$$;
comment on function catalog.convert_quantity(uuid, numeric, uuid, uuid) is
  'Convierte una cantidad de un ingrediente entre dos unidades. status: ok, missing_conversion (falta densidad, peso por unidad o hay un envase: la cantidad sale vacía, nunca 0), invalid_quantity o unknown_ingredient. Respeta RLS.';
revoke execute on function catalog.convert_quantity(uuid, numeric, uuid, uuid) from public;
grant execute on function catalog.convert_quantity(uuid, numeric, uuid, uuid) to authenticated;

-- Pasa una cantidad a la unidad base de uso del ingrediente (g, ml o unidad).
create function catalog.to_base_quantity(p_ingredient_id uuid, p_quantity numeric, p_unit_id uuid)
returns table (base_quantity numeric, base_unit text, status text)
language sql
stable
set search_path = ''
as $$
  select c.quantity, u.code, c.status
    from catalog.ingredients i
    join catalog.units u on u.id = i.recipe_unit_id
   cross join lateral catalog.convert_quantity(i.id, p_quantity, p_unit_id, i.recipe_unit_id) c
   where i.id = p_ingredient_id
  union all
  select null::numeric, null::text, 'unknown_ingredient'::text
   where not exists (select 1 from catalog.ingredients where id = p_ingredient_id)
$$;
comment on function catalog.to_base_quantity(uuid, numeric, uuid) is
  'Pasa una cantidad a la unidad base de uso del ingrediente (con convert_quantity). Mismos estados que convert_quantity. Respeta RLS.';
revoke execute on function catalog.to_base_quantity(uuid, numeric, uuid) from public;
grant execute on function catalog.to_base_quantity(uuid, numeric, uuid) to authenticated;

-- Buscador de componentes (sección 18): desde 3 letras, por nombre, alias o código, los más
-- parecidos primero. Por ahora solo ingredientes activos; las subrecetas se suman en la etapa 2.2.
create function catalog.search_components(p_query text, p_limit integer default 20)
returns table (kind text, id uuid, code text, name text, unit text, matched text, score real)
language sql
stable
set search_path = ''
as $$
  with q as (select lower(btrim(p_query)) as t)
  select 'ingredient'::text, i.id, i.code, i.name, u.name,
         coalesce(a.alias, i.name),
         greatest(extensions.similarity(lower(i.name), q.t),
                  coalesce(extensions.similarity(a.alias, q.t), 0),
                  case when lower(i.code) like q.t || '%' then 1 else 0 end)::real as score
    from q, catalog.ingredients i
    join catalog.units u on u.id = i.recipe_unit_id
    left join lateral (
      select al.alias from catalog.ingredient_aliases al
       where al.ingredient_id = i.id and al.alias like '%' || (select t from q) || '%'
       order by length(al.alias) limit 1) a on true
   where length(q.t) >= 3
     and i.is_active
     and (lower(i.name) like '%' || q.t || '%'
          or lower(i.code) like q.t || '%'
          or a.alias is not null
          or extensions.similarity(lower(i.name), q.t) > 0.3)
   order by score desc, i.name
   limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;
comment on function catalog.search_components(text, integer) is
  'Buscador de componentes: desde 3 letras, por nombre, alias o código, ordenado por parecido. Respeta RLS. Las subrecetas se suman en la etapa 2.2.';
revoke execute on function catalog.search_components(text, integer) from public;
grant execute on function catalog.search_components(text, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Escritura: solo por funciones, con catalog.manage en el grupo y motivo
-- ---------------------------------------------------------------------------
create function catalog.unit_id(p_code text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_code is null then
    return null;
  end if;
  select id into v_id from catalog.units where code = p_code and deleted_at is null;
  if v_id is null then
    raise exception 'No existe la unidad "%".', p_code using errcode = '22023';
  end if;
  return v_id;
end
$$;
comment on function catalog.unit_id(text) is 'Interna: id de una unidad por su código, o error si no existe.';
revoke execute on function catalog.unit_id(text) from public;

-- Errores de restricciones en español: Postgres los da en inglés y con el nombre técnico.
create function catalog.raise_friendly(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'ingredients_code_key' then 'Ya existe una materia prima con ese código en el grupo.'
    when p_constraint = 'ingredients_name_key' then 'Ya existe una materia prima con ese nombre en el grupo.'
    when p_constraint = 'suppliers_code_key' then 'Ya existe un proveedor con ese código en el grupo.'
    when p_constraint = 'suppliers_name_key' then 'Ya existe un proveedor con ese nombre en el grupo.'
    when p_constraint = 'purchase_products_code_key' then 'Ya existe un producto de compra con ese código en el grupo.'
    when p_constraint like '%\_code\_check' then
      'El código va en mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).'
    when p_constraint in ('ingredients_name_check', 'suppliers_name_check') then
      'El nombre no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint = 'purchase_products_description_check' then
      'La descripción no puede quedar vacía ni pasar los 200 caracteres.'
    when p_constraint = 'suppliers_tax_id_check' then 'El CUIT va solo con números y guiones.'
    when p_constraint = 'purchase_products_units_per_package_check' then 'Las unidades por envase van de 1 a 10.000.'
    when p_constraint in ('purchase_products_content_per_unit_check', 'ingredient_unit_conversions_factor_check') then
      'El valor tiene que ser mayor que cero.'
    when p_constraint like '%\_notes\_check' then 'Las observaciones son demasiado largas.'
    when p_state = '23503' then 'La categoría, el proveedor o la unidad elegidos no existen en este grupo.'
    else p_message
  end;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function catalog.raise_friendly(text, text, text) is
  'Interna: vuelve a lanzar un error de restricción con un mensaje en español para la persona.';
revoke execute on function catalog.raise_friendly(text, text, text) from public;

-- Grupo de un ingrediente visible, o error "sin permiso" (no revela si existe).
create function catalog.ingredient_group(p_ingredient_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from catalog.ingredients where id = p_ingredient_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('catalog.manage', v_group),
                      'editar esta materia prima');
  return v_group;
end
$$;
comment on function catalog.ingredient_group(uuid) is 'Interna: grupo del ingrediente si la sesión tiene catalog.manage ahí; si no, "sin permiso".';
revoke execute on function catalog.ingredient_group(uuid) from public;

create function catalog.create_ingredient(p_group_id uuid, p_code text, p_name text, p_category_id uuid,
                                          p_recipe_unit text, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('catalog.manage', p_group_id), 'crear materias primas en este grupo');
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['purchase_unit', 'storage_unit', 'costing_unit', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id, purchase_unit_id, storage_unit_id,
                                   costing_unit_id, notes)
  values (p_group_id, upper(btrim(p_code)), btrim(p_name), p_category_id, catalog.unit_id(p_recipe_unit),
          catalog.unit_id(nullif(p_details ->> 'purchase_unit', '')), catalog.unit_id(nullif(p_details ->> 'storage_unit', '')),
          catalog.unit_id(nullif(p_details ->> 'costing_unit', '')), nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_ingredient(uuid, text, text, uuid, text, jsonb, text) is
  'Crea una materia prima. Pide catalog.manage en el grupo y un motivo. p_details: purchase_unit, storage_unit, costing_unit (códigos de unidad) y notes.';

create function catalog.update_ingredient(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
begin
  perform catalog.ingredient_group(p_id);
  -- El código no cambia nunca: sirve para importar sin duplicar.
  perform org.check_keys(p_changes, array['name', 'category_id', 'recipe_unit', 'purchase_unit', 'storage_unit',
                                          'costing_unit', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredients
     set name             = coalesce(btrim(p_changes ->> 'name'), name),
         category_id      = coalesce((p_changes ->> 'category_id')::uuid, category_id),
         recipe_unit_id   = coalesce(catalog.unit_id(p_changes ->> 'recipe_unit'), recipe_unit_id),
         purchase_unit_id = case when p_changes ? 'purchase_unit' then catalog.unit_id(nullif(p_changes ->> 'purchase_unit', '')) else purchase_unit_id end,
         storage_unit_id  = case when p_changes ? 'storage_unit' then catalog.unit_id(nullif(p_changes ->> 'storage_unit', '')) else storage_unit_id end,
         costing_unit_id  = case when p_changes ? 'costing_unit' then catalog.unit_id(nullif(p_changes ->> 'costing_unit', '')) else costing_unit_id end,
         notes            = case when p_changes ? 'notes' then nullif(btrim(p_changes ->> 'notes'), '') else notes end
   where id = p_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.update_ingredient(uuid, jsonb, text) is
  'Edita una materia prima (nombre, categoría, unidades, observaciones). El código no cambia. Pide catalog.manage y un motivo.';

create function catalog.set_ingredient_active(p_id uuid, p_active boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform catalog.ingredient_group(p_id);
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredients set is_active = coalesce(p_active, is_active) where id = p_id;
end
$$;
comment on function catalog.set_ingredient_active(uuid, boolean, text) is
  'Desactiva o reactiva una materia prima. No hay borrado: una materia prima usada en recetas nunca se borra.';

create function catalog.set_aliases(p_ingredient_id uuid, p_aliases text[], p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid := catalog.ingredient_group(p_ingredient_id);
  v_new   text[];
begin
  select coalesce(array_agg(distinct lower(btrim(a))), '{}') into v_new
    from unnest(coalesce(p_aliases, '{}')) as a where length(btrim(a)) > 0;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredient_aliases set deleted_at = now()
   where ingredient_id = p_ingredient_id and deleted_at is null and not alias = any (v_new);
  insert into catalog.ingredient_aliases (group_id, ingredient_id, alias)
  select v_group, p_ingredient_id, a from unnest(v_new) as a
   where not exists (select 1 from catalog.ingredient_aliases x
                      where x.ingredient_id = p_ingredient_id and x.alias = a and x.deleted_at is null);
exception when unique_violation then
  raise exception 'Uno de los alias ya es de otra materia prima del grupo.' using errcode = '23505';
end
$$;
comment on function catalog.set_aliases(uuid, text[], text) is
  'Reemplaza los alias de una materia prima (en minúsculas, sin repetir). Los que se sacan quedan borrados lógicamente.';

create function catalog.set_unit_conversion(p_ingredient_id uuid, p_kind catalog.conversion_kind, p_factor numeric,
                                            p_source catalog.data_source, p_measured_on date, p_measured_by text,
                                            p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_group uuid := catalog.ingredient_group(p_ingredient_id);
begin
  perform core.set_change_context(p_reason, 'manual');
  if p_factor is null then
    update catalog.ingredient_unit_conversions set deleted_at = now()
     where ingredient_id = p_ingredient_id and kind = p_kind and deleted_at is null;
    return;
  end if;
  if p_source is null or p_measured_on is null then
    raise exception 'La conversión necesita la fuente y la fecha de la medición: nunca se supone.' using errcode = '22023';
  end if;
  update catalog.ingredient_unit_conversions
     set factor = p_factor, source = p_source, measured_on = p_measured_on, measured_by = nullif(btrim(p_measured_by), '')
   where ingredient_id = p_ingredient_id and kind = p_kind and deleted_at is null;
  if not found then
    insert into catalog.ingredient_unit_conversions (group_id, ingredient_id, kind, factor, source, measured_on, measured_by)
    values (v_group, p_ingredient_id, p_kind, p_factor, p_source, p_measured_on, nullif(btrim(p_measured_by), ''));
  end if;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.set_unit_conversion(uuid, catalog.conversion_kind, numeric, catalog.data_source, date, text, text) is
  'Carga o cambia la densidad o el peso por unidad de una materia prima, con fuente y fecha. Con factor vacío, la quita (borrado lógico).';

create function catalog.set_allergen_status(p_ingredient_id uuid, p_allergen_id uuid, p_status catalog.allergen_status,
                                            p_source catalog.data_source, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid := catalog.ingredient_group(p_ingredient_id);
begin
  if not exists (select 1 from catalog.allergens where id = p_allergen_id and group_id = v_group and deleted_at is null) then
    raise exception 'Ese alérgeno no es de la lista del grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  if p_status is null then
    update catalog.ingredient_allergens set deleted_at = now()
     where ingredient_id = p_ingredient_id and allergen_id = p_allergen_id and deleted_at is null;
    return;
  end if;
  if p_source is null then
    raise exception 'El estado de un alérgeno necesita su fuente.' using errcode = '22023';
  end if;
  update catalog.ingredient_allergens set status = p_status, source = p_source
   where ingredient_id = p_ingredient_id and allergen_id = p_allergen_id and deleted_at is null;
  if not found then
    insert into catalog.ingredient_allergens (group_id, ingredient_id, allergen_id, status, source)
    values (v_group, p_ingredient_id, p_allergen_id, p_status, p_source);
  end if;
end
$$;
comment on function catalog.set_allergen_status(uuid, uuid, catalog.allergen_status, catalog.data_source, text) is
  'Carga el estado de un alérgeno en una materia prima. Con estado vacío vuelve a "sin dato" (borrado lógico de la fila).';

create function catalog.create_supplier(p_group_id uuid, p_code text, p_name text, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('catalog.manage', p_group_id), 'crear proveedores en este grupo');
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['tax_id', 'is_internal', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.suppliers (group_id, code, name, tax_id, is_internal, notes)
  values (p_group_id, upper(btrim(p_code)), btrim(p_name), nullif(btrim(p_details ->> 'tax_id'), ''),
          coalesce((p_details ->> 'is_internal')::boolean, false), nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_supplier(uuid, text, text, jsonb, text) is
  'Crea un proveedor. Pide catalog.manage en el grupo y un motivo. p_details: tax_id, is_internal y notes.';

create function catalog.update_supplier(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_group uuid;
begin
  select group_id into v_group from catalog.suppliers where id = p_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('catalog.manage', v_group), 'editar este proveedor');
  perform org.check_keys(p_changes, array['name', 'tax_id', 'is_internal', 'is_active', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  update catalog.suppliers
     set name        = coalesce(btrim(p_changes ->> 'name'), name),
         tax_id      = case when p_changes ? 'tax_id' then nullif(btrim(p_changes ->> 'tax_id'), '') else tax_id end,
         is_internal = coalesce((p_changes ->> 'is_internal')::boolean, is_internal),
         is_active   = coalesce((p_changes ->> 'is_active')::boolean, is_active),
         notes       = case when p_changes ? 'notes' then nullif(btrim(p_changes ->> 'notes'), '') else notes end
   where id = p_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.update_supplier(uuid, jsonb, text) is
  'Edita un proveedor (nombre, CUIT, si es interno, si está activo, observaciones). El código no cambia. Pide catalog.manage y un motivo.';

create function catalog.create_purchase_product(p_ingredient_id uuid, p_code text, p_description text,
                                                p_package_unit text, p_units_per_package integer,
                                                p_content_per_unit numeric, p_content_unit text,
                                                p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_group uuid := catalog.ingredient_group(p_ingredient_id);
  v_id    uuid;
begin
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['supplier_id', 'brand_name', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, brand_name,
                                         package_unit_id, units_per_package, content_per_unit, content_unit_id, notes)
  values (v_group, upper(btrim(p_code)), p_ingredient_id, nullif(p_details ->> 'supplier_id', '')::uuid,
          btrim(p_description), nullif(btrim(p_details ->> 'brand_name'), ''), catalog.unit_id(p_package_unit),
          coalesce(p_units_per_package, 1), p_content_per_unit, catalog.unit_id(p_content_unit),
          nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_purchase_product(uuid, text, text, text, integer, numeric, text, jsonb, text) is
  'Crea un producto de compra de una materia prima. Pide catalog.manage y un motivo. p_details: supplier_id, brand_name y notes. La aprobación del Controller se suma con los precios (etapa 2.1 C).';

create function catalog.update_purchase_product(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_ingredient uuid;
begin
  select ingredient_id into v_ingredient from catalog.purchase_products where id = p_id and deleted_at is null;
  perform catalog.ingredient_group(v_ingredient);
  -- El ingrediente y el código no cambian: un producto de otro ingrediente es otro producto.
  perform org.check_keys(p_changes, array['description', 'brand_name', 'supplier_id', 'package_unit', 'units_per_package',
                                          'content_per_unit', 'content_unit', 'is_active', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  update catalog.purchase_products
     set description       = coalesce(btrim(p_changes ->> 'description'), description),
         brand_name        = case when p_changes ? 'brand_name' then nullif(btrim(p_changes ->> 'brand_name'), '') else brand_name end,
         supplier_id       = case when p_changes ? 'supplier_id' then nullif(p_changes ->> 'supplier_id', '')::uuid else supplier_id end,
         package_unit_id   = coalesce(catalog.unit_id(p_changes ->> 'package_unit'), package_unit_id),
         units_per_package = coalesce((p_changes ->> 'units_per_package')::integer, units_per_package),
         content_per_unit  = coalesce((p_changes ->> 'content_per_unit')::numeric, content_per_unit),
         content_unit_id   = coalesce(catalog.unit_id(p_changes ->> 'content_unit'), content_unit_id),
         is_active         = coalesce((p_changes ->> 'is_active')::boolean, is_active),
         notes             = case when p_changes ? 'notes' then nullif(btrim(p_changes ->> 'notes'), '') else notes end
   where id = p_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.update_purchase_product(uuid, jsonb, text) is
  'Edita un producto de compra. El ingrediente y el código no cambian. Pide catalog.manage y un motivo.';

-- Solo estas funciones de escritura las puede llamar la app.
do $$
declare
  f text;
begin
  foreach f in array array[
    'catalog.create_ingredient(uuid, text, text, uuid, text, jsonb, text)',
    'catalog.update_ingredient(uuid, jsonb, text)',
    'catalog.set_ingredient_active(uuid, boolean, text)',
    'catalog.set_aliases(uuid, text[], text)',
    'catalog.set_unit_conversion(uuid, catalog.conversion_kind, numeric, catalog.data_source, date, text, text)',
    'catalog.set_allergen_status(uuid, uuid, catalog.allergen_status, catalog.data_source, text)',
    'catalog.create_supplier(uuid, text, text, jsonb, text)',
    'catalog.update_supplier(uuid, jsonb, text)',
    'catalog.create_purchase_product(uuid, text, text, text, integer, numeric, text, jsonb, text)',
    'catalog.update_purchase_product(uuid, jsonb, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
