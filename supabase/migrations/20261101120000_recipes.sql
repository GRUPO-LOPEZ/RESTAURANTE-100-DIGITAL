-- Fase 2, etapa 2.2 A: recetas versionadas (ADR-0023). Documento de Soy, secciones 11, 13, 14 y 17.
--
-- - Una receta es la identidad (código, nombre, alcance); cada versión es su fórmula. Una versión
--   publicada no cambia nunca: corregir es crear otra (trigger core.enforce_version_rules de la Fase 1).
-- - Alcances de esta etapa: maestra del grupo, de marca y de local. Variantes, cocina central,
--   subrecetas y Pariggi llegan en la 2.2 B (decisiones 1 y 6 de Soy).
-- - Aprobar = publicar (decisión de Joaco): se pide revisión, se aprueba en /aprobaciones y queda
--   vigente en el acto. Quien la mandó a revisión nunca la aprueba (workflow.decision_blocker).
-- - Sin valores económicos en este esquema: los costos viven en costing (2.3). Así la vista de cocina
--   no tiene nada que esconder (caso 24) y lo controla una prueba.
-- - Las escrituras devuelven {"result": ...}: un rechazo por permiso queda registrado (core.deny,
--   caso 11). Si cortaran con un error, el registro se desharía con la transacción.

-- ---------------------------------------------------------------------------
-- 1. Tipos
-- ---------------------------------------------------------------------------
create type recipes.recipe_type as enum ('preparation', 'dish', 'unit_component');
comment on type recipes.recipe_type is
  'Tipo de receta: preparation (salsa, masa, caldo), dish (plato terminado, por porción) o unit_component (medallón, bollo, empanada armada).';
create type recipes.recipe_scope as enum ('group', 'brand', 'restaurant');
comment on type recipes.recipe_scope is
  'Alcance: group (maestra del grupo), brand (de marca) o restaurant (de local). Variante y cocina central llegan en la 2.2 B.';
create type recipes.quantity_basis as enum ('purchase', 'clean', 'cooked');
comment on type recipes.quantity_basis is
  'Qué representa la cantidad de una línea: peso de compra (purchase), limpio (clean) o cocido (cooked).';
create type recipes.step_kind as enum ('preparation', 'cooking', 'resting', 'fermentation', 'cooling', 'regeneration',
                                       'plating', 'other');
comment on type recipes.step_kind is
  'Tipo de paso: preparación, cocción, reposo, fermentación, enfriamiento, regeneración, emplatado u otro.';

-- ---------------------------------------------------------------------------
-- 2. Tablas
-- ---------------------------------------------------------------------------
create table recipes.recipe_categories (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references org.groups (id) on delete restrict,
  parent_id   uuid,
  name        text not null check (length(btrim(name)) between 1 and 80),
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint recipe_categories_id_group_key unique (id, group_id),
  constraint recipe_categories_parent_fkey foreign key (parent_id, group_id)
    references recipes.recipe_categories (id, group_id) on delete restrict,
  constraint recipe_categories_not_self check (parent_id is distinct from id)
);
create index recipe_categories_group_idx on recipes.recipe_categories (group_id);
create index recipe_categories_parent_idx on recipes.recipe_categories (parent_id, group_id) where parent_id is not null;
create unique index recipe_categories_name_key on recipes.recipe_categories
  (group_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)) where deleted_at is null;
comment on table recipes.recipe_categories is 'Categorías y subcategorías de recetas (dos niveles), por grupo.';
comment on column recipes.recipe_categories.id is 'Identificador de la categoría.';
comment on column recipes.recipe_categories.group_id is 'Grupo al que pertenece.';
comment on column recipes.recipe_categories.parent_id is 'Categoría madre, si es una subcategoría. Solo dos niveles.';
comment on column recipes.recipe_categories.name is 'Nombre. Único dentro de su categoría madre entre las vigentes, sin importar mayúsculas.';
comment on column recipes.recipe_categories.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipe_categories.created_by is 'Quién la creó (lo pone la base).';
comment on column recipes.recipe_categories.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_categories.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipe_categories.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column recipes.recipe_categories.deleted_by is 'Quién la borró (lo pone la base).';

create table recipes.recipes (
  id                  uuid primary key default gen_random_uuid(),
  group_id            uuid not null references org.groups (id) on delete restrict,
  brand_id            uuid,
  restaurant_id       uuid,
  scope_type          recipes.recipe_scope not null,
  code                text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  name                text not null check (length(btrim(name)) between 1 and 120),
  short_name          text check (short_name is null or length(btrim(short_name)) between 1 and 40),
  recipe_type         recipes.recipe_type not null,
  category_id         uuid,
  sector              text check (sector is null or length(btrim(sector)) between 1 and 60),
  station             text check (station is null or length(btrim(station)) between 1 and 60),
  technical_owner_id  uuid references core.actors (id) on delete restrict,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  created_by          uuid references core.actors (id) on delete restrict,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references core.actors (id) on delete restrict,
  deleted_at          timestamptz,
  deleted_by          uuid references core.actors (id) on delete restrict,
  constraint recipes_id_group_key unique (id, group_id),
  constraint recipes_brand_fkey foreign key (brand_id, group_id) references org.brands (id, group_id) on delete restrict,
  constraint recipes_restaurant_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint recipes_category_fkey foreign key (category_id, group_id)
    references recipes.recipe_categories (id, group_id) on delete restrict,
  -- Alcance coherente: grupo sin marca ni local; marca con marca y sin local; local con los dos.
  constraint recipes_scope_check check (
    (scope_type = 'group' and brand_id is null and restaurant_id is null)
    or (scope_type = 'brand' and brand_id is not null and restaurant_id is null)
    or (scope_type = 'restaurant' and brand_id is not null and restaurant_id is not null))
);
create unique index recipes_code_key on recipes.recipes (group_id, code) where deleted_at is null;
create index recipes_group_idx on recipes.recipes (group_id);
create index recipes_brand_idx on recipes.recipes (brand_id, group_id) where brand_id is not null;
create index recipes_restaurant_idx on recipes.recipes (restaurant_id, brand_id) where restaurant_id is not null;
create index recipes_category_idx on recipes.recipes (category_id, group_id) where category_id is not null;
create index recipes_owner_idx on recipes.recipes (technical_owner_id) where technical_owner_id is not null;
create index recipes_name_trgm_idx on recipes.recipes using gin (name extensions.gin_trgm_ops);
comment on table recipes.recipes is
  'Recetas: la identidad (código, nombre, alcance, tipo). La fórmula vive en recipe_versions. Sin valores económicos: los costos van en costing.';
comment on column recipes.recipes.id is 'Identificador de la receta.';
comment on column recipes.recipes.group_id is 'Grupo de la receta.';
comment on column recipes.recipes.brand_id is 'Marca, si la receta es de marca o de local. Vacío en una maestra del grupo.';
comment on column recipes.recipes.restaurant_id is 'Local, si la receta es de un local. Vacío si es de marca o del grupo.';
comment on column recipes.recipes.scope_type is 'Alcance: maestra del grupo, de marca o de local.';
comment on column recipes.recipes.code is 'Código de la receta. Único en el grupo y no cambia nunca: sirve para importar sin duplicar.';
comment on column recipes.recipes.name is 'Nombre de la receta.';
comment on column recipes.recipes.short_name is 'Nombre corto para la cocina y las comandas.';
comment on column recipes.recipes.recipe_type is 'Tipo: preparación, plato terminado o componente unitario.';
comment on column recipes.recipes.category_id is 'Categoría o subcategoría de la receta.';
comment on column recipes.recipes.sector is 'Sector de la cocina donde se prepara (por ejemplo, caliente o pastelería).';
comment on column recipes.recipes.station is 'Partida o estación (por ejemplo, plancha o pastas).';
comment on column recipes.recipes.technical_owner_id is 'Responsable técnico de la receta.';
comment on column recipes.recipes.is_active is 'Si la receta se usa. Una receta archivada conserva toda su historia.';
comment on column recipes.recipes.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipes.created_by is 'Quién la creó (lo pone la base).';
comment on column recipes.recipes.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipes.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipes.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column recipes.recipes.deleted_by is 'Quién la borró (lo pone la base).';

create table recipes.recipe_versions (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null,
  brand_id             uuid,
  restaurant_id        uuid,
  recipe_id            uuid not null,
  version_number       integer not null check (version_number >= 1),
  status               core.version_status not null default 'draft',
  previous_version_id  uuid,
  yield_quantity       numeric(18, 6) check (yield_quantity is null or yield_quantity > 0),
  yield_unit_id        uuid references catalog.units (id) on delete restrict,
  portions             integer check (portions is null or portions between 1 and 100000),
  portion_grams        numeric(18, 6) check (portion_grams is null or portion_grams > 0),
  description          text check (description is null or length(description) <= 2000),
  storage_notes        text check (storage_notes is null or length(storage_notes) <= 2000),
  presentation_notes   text check (presentation_notes is null or length(presentation_notes) <= 2000),
  change_summary       text check (change_summary is null or length(change_summary) <= 1000),
  review_requested_by  uuid references core.actors (id) on delete restrict,
  approval_request_id  uuid references workflow.approval_requests (id) on delete restrict,
  approved_by          uuid references core.actors (id) on delete restrict,
  published_at         timestamptz,
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict,
  constraint recipe_versions_id_group_key unique (id, group_id),
  constraint recipe_versions_id_recipe_key unique (id, recipe_id),
  constraint recipe_versions_previous_fkey foreign key (previous_version_id, recipe_id)
    references recipes.recipe_versions (id, recipe_id) on delete restrict,
  constraint recipe_versions_request_check check (approval_request_id is null or status <> 'draft'),
  constraint recipe_versions_recipe_fkey foreign key (recipe_id, group_id)
    references recipes.recipes (id, group_id) on delete restrict,
  constraint recipe_versions_yield_unit_check check ((yield_quantity is null) = (yield_unit_id is null)),
  constraint recipe_versions_published_check check (case status when 'published' then published_at is not null
                                                                 when 'archived' then true
                                                                 else published_at is null end)
);
create unique index recipe_versions_number_key on recipes.recipe_versions (recipe_id, version_number);
-- Una sola vigente y una sola abierta (borrador o en revisión) por receta.
create unique index recipe_versions_published_key on recipes.recipe_versions (recipe_id) where status = 'published';
create unique index recipe_versions_open_key on recipes.recipe_versions (recipe_id) where status in ('draft', 'in_review');
create index recipe_versions_group_idx on recipes.recipe_versions (group_id);
create index recipe_versions_recipe_idx on recipes.recipe_versions (recipe_id, group_id);
create index recipe_versions_previous_idx on recipes.recipe_versions (previous_version_id) where previous_version_id is not null;
create index recipe_versions_yield_unit_idx on recipes.recipe_versions (yield_unit_id) where yield_unit_id is not null;
create index recipe_versions_request_idx on recipes.recipe_versions (approval_request_id) where approval_request_id is not null;
create index recipe_versions_requested_by_idx on recipes.recipe_versions (review_requested_by) where review_requested_by is not null;
create index recipe_versions_approved_by_idx on recipes.recipe_versions (approved_by) where approved_by is not null;
comment on table recipes.recipe_versions is
  'Cada versión de la fórmula de una receta. Nace en borrador; desde aprobada no cambia. Una sola publicada (vigente) por receta.';
comment on column recipes.recipe_versions.id is 'Identificador de la versión.';
comment on column recipes.recipe_versions.group_id is 'Grupo de la receta.';
comment on column recipes.recipe_versions.brand_id is 'Marca de la receta (la copia la base): sirve para la auditoría por alcance.';
comment on column recipes.recipe_versions.restaurant_id is 'Local de la receta, si es de un local (lo copia la base).';
comment on column recipes.recipe_versions.recipe_id is 'Receta a la que pertenece.';
comment on column recipes.recipe_versions.version_number is 'Número de versión (1, 2, 3…).';
comment on column recipes.recipe_versions.status is
  'Estado: borrador, en revisión, aprobada, publicada (vigente) o archivada. Desde aprobada no cambia.';
comment on column recipes.recipe_versions.previous_version_id is 'Versión de la que salió esta, de la misma receta (para ver las diferencias).';
comment on column recipes.recipe_versions.yield_quantity is 'Cuánto rinde la receta, en yield_unit_id.';
comment on column recipes.recipe_versions.yield_unit_id is 'Unidad del rendimiento (kg, l, unidad…).';
comment on column recipes.recipe_versions.portions is 'Porciones que salen, si es un plato o se porciona.';
comment on column recipes.recipe_versions.portion_grams is 'Peso de una porción, en gramos.';
comment on column recipes.recipe_versions.description is 'Descripción gastronómica.';
comment on column recipes.recipe_versions.storage_notes is
  'Conservación (método, temperatura, vida útil), solo desde procedimientos validados y con su referencia. El sistema nunca la propone.';
comment on column recipes.recipe_versions.presentation_notes is 'Presentación: montaje, vajilla, guarnición, terminación.';
comment on column recipes.recipe_versions.change_summary is 'Qué cambió respecto de la versión anterior y por qué.';
comment on column recipes.recipe_versions.review_requested_by is 'Quién pidió la revisión. Nunca es quien la aprueba.';
comment on column recipes.recipe_versions.approval_request_id is 'Solicitud de aprobación (recipes.publish_version) de esta versión.';
comment on column recipes.recipe_versions.approved_by is 'Quién la aprobó y publicó.';
comment on column recipes.recipe_versions.published_at is 'Cuándo quedó vigente.';
comment on column recipes.recipe_versions.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipe_versions.created_by is 'Quién la creó (lo pone la base).';
comment on column recipes.recipe_versions.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_versions.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipe_versions.deleted_at is 'Borrado lógico. Una versión no se borra (trigger): siempre vacío.';
comment on column recipes.recipe_versions.deleted_by is 'Quién la borró. Siempre vacío.';

create table recipes.recipe_components (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null,
  brand_id           uuid,
  restaurant_id      uuid,
  recipe_version_id  uuid not null,
  line_order         integer not null check (line_order between 1 and 500),
  ingredient_id      uuid not null,
  quantity           numeric(18, 6) not null check (quantity > 0),
  unit_id            uuid not null references catalog.units (id) on delete restrict,
  quantity_basis     recipes.quantity_basis not null default 'purchase',
  yield_profile_id   uuid references catalog.ingredient_yield_profiles (id) on delete restrict,
  no_scale           boolean not null default false,
  notes              text check (notes is null or length(notes) <= 500),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint recipe_components_version_fkey foreign key (recipe_version_id, group_id)
    references recipes.recipe_versions (id, group_id) on delete restrict,
  constraint recipe_components_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict
);
create unique index recipe_components_order_key on recipes.recipe_components (recipe_version_id, line_order)
  where deleted_at is null;
create index recipe_components_group_idx on recipes.recipe_components (group_id);
create index recipe_components_version_idx on recipes.recipe_components (recipe_version_id, group_id);
create index recipe_components_ingredient_idx on recipes.recipe_components (ingredient_id, group_id);
create index recipe_components_unit_idx on recipes.recipe_components (unit_id);
create index recipe_components_yield_idx on recipes.recipe_components (yield_profile_id) where yield_profile_id is not null;
comment on table recipes.recipe_components is
  'Líneas de la fórmula de una versión: qué materia prima, cuánto y en qué base. Solo cambian mientras la versión es borrador. Las subrecetas llegan en la 2.2 B.';
comment on column recipes.recipe_components.id is 'Identificador de la línea.';
comment on column recipes.recipe_components.group_id is 'Grupo de la receta.';
comment on column recipes.recipe_components.brand_id is 'Marca de la receta (la copia la base): sirve para la auditoría por alcance.';
comment on column recipes.recipe_components.restaurant_id is 'Local de la receta, si es de un local (lo copia la base).';
comment on column recipes.recipe_components.recipe_version_id is 'Versión a la que pertenece.';
comment on column recipes.recipe_components.line_order is 'Orden de la línea en la receta.';
comment on column recipes.recipe_components.ingredient_id is 'Materia prima.';
comment on column recipes.recipe_components.quantity is 'Cantidad, en unit_id.';
comment on column recipes.recipe_components.unit_id is 'Unidad de la cantidad. Tiene que poder pasarse a la unidad de la materia prima.';
comment on column recipes.recipe_components.quantity_basis is 'Qué representa la cantidad: peso de compra, limpio o cocido.';
comment on column recipes.recipe_components.yield_profile_id is 'Rendimiento estándar a aplicar (de esta materia prima), si corresponde.';
comment on column recipes.recipe_components.no_scale is 'Si la línea no se escala (terminaciones, redondeos): se ajusta a mano.';
comment on column recipes.recipe_components.notes is 'Observaciones de la línea.';
comment on column recipes.recipe_components.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipe_components.created_by is 'Quién la creó (lo pone la base).';
comment on column recipes.recipe_components.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_components.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipe_components.deleted_at is 'Borrado lógico: al guardar las líneas de un borrador, las anteriores quedan borradas.';
comment on column recipes.recipe_components.deleted_by is 'Quién la borró (lo pone la base).';

create table recipes.recipe_steps (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null,
  brand_id           uuid,
  restaurant_id      uuid,
  recipe_version_id  uuid not null,
  step_number        integer not null check (step_number between 1 and 200),
  kind               recipes.step_kind not null default 'preparation',
  instructions       text not null check (length(btrim(instructions)) between 1 and 2000),
  active_minutes     integer not null default 0 check (active_minutes between 0 and 10080),
  passive_minutes    integer not null default 0 check (passive_minutes between 0 and 10080),
  workers            smallint check (workers is null or workers between 1 and 50),
  sector             text check (sector is null or length(btrim(sector)) between 1 and 60),
  equipment          text check (equipment is null or length(btrim(equipment)) between 1 and 120),
  control_point      text check (control_point is null or length(btrim(control_point)) between 1 and 500),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint recipe_steps_id_group_key unique (id, group_id),
  constraint recipe_steps_version_fkey foreign key (recipe_version_id, group_id)
    references recipes.recipe_versions (id, group_id) on delete restrict
);
create unique index recipe_steps_number_key on recipes.recipe_steps (recipe_version_id, step_number) where deleted_at is null;
create index recipe_steps_group_idx on recipes.recipe_steps (group_id);
create index recipe_steps_version_idx on recipes.recipe_steps (recipe_version_id, group_id);
comment on table recipes.recipe_steps is
  'Procedimiento de una versión: pasos con sus tiempos. Solo cambian mientras la versión es borrador.';
comment on column recipes.recipe_steps.id is 'Identificador del paso.';
comment on column recipes.recipe_steps.group_id is 'Grupo de la receta.';
comment on column recipes.recipe_steps.brand_id is 'Marca de la receta (la copia la base): sirve para la auditoría por alcance.';
comment on column recipes.recipe_steps.restaurant_id is 'Local de la receta, si es de un local (lo copia la base).';
comment on column recipes.recipe_steps.recipe_version_id is 'Versión a la que pertenece.';
comment on column recipes.recipe_steps.step_number is 'Número del paso (1, 2, 3…).';
comment on column recipes.recipe_steps.kind is 'Tipo de paso: preparación, cocción, reposo, fermentación, enfriamiento, regeneración, emplatado u otro.';
comment on column recipes.recipe_steps.instructions is 'Qué se hace en el paso.';
comment on column recipes.recipe_steps.active_minutes is 'Minutos con una persona trabajando.';
comment on column recipes.recipe_steps.passive_minutes is 'Minutos de espera (cocción, reposo, fermentación) sin una persona encima.';
comment on column recipes.recipe_steps.workers is 'Cuántas personas hacen falta.';
comment on column recipes.recipe_steps.sector is 'Sector de la cocina.';
comment on column recipes.recipe_steps.equipment is 'Equipo que se usa.';
comment on column recipes.recipe_steps.control_point is 'Punto de control o criterio de calidad del paso.';
comment on column recipes.recipe_steps.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipe_steps.created_by is 'Quién lo creó (lo pone la base).';
comment on column recipes.recipe_steps.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_steps.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column recipes.recipe_steps.deleted_at is 'Borrado lógico: al guardar los pasos de un borrador, los anteriores quedan borrados.';
comment on column recipes.recipe_steps.deleted_by is 'Quién lo borró (lo pone la base).';

create table recipes.recipe_step_dependencies (
  id                  uuid primary key default gen_random_uuid(),
  group_id            uuid not null,
  brand_id            uuid,
  restaurant_id       uuid,
  step_id             uuid not null,
  depends_on_step_id  uuid not null,
  created_at          timestamptz not null default now(),
  created_by          uuid references core.actors (id) on delete restrict,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references core.actors (id) on delete restrict,
  deleted_at          timestamptz,
  deleted_by          uuid references core.actors (id) on delete restrict,
  constraint recipe_step_dependencies_step_fkey foreign key (step_id, group_id)
    references recipes.recipe_steps (id, group_id) on delete restrict,
  constraint recipe_step_dependencies_depends_fkey foreign key (depends_on_step_id, group_id)
    references recipes.recipe_steps (id, group_id) on delete restrict,
  constraint recipe_step_dependencies_not_self check (step_id <> depends_on_step_id)
);
create unique index recipe_step_dependencies_key on recipes.recipe_step_dependencies (step_id, depends_on_step_id)
  where deleted_at is null;
create index recipe_step_dependencies_group_idx on recipes.recipe_step_dependencies (group_id);
create index recipe_step_dependencies_step_idx on recipes.recipe_step_dependencies (step_id, group_id);
create index recipe_step_dependencies_depends_idx on recipes.recipe_step_dependencies (depends_on_step_id, group_id);
comment on table recipes.recipe_step_dependencies is
  'Qué paso espera a cuál, para calcular el camino crítico. Misma versión y sin ciclos (trigger).';
comment on column recipes.recipe_step_dependencies.id is 'Identificador de la dependencia.';
comment on column recipes.recipe_step_dependencies.group_id is 'Grupo de la receta.';
comment on column recipes.recipe_step_dependencies.brand_id is 'Marca de la receta (la copia la base): sirve para la auditoría por alcance.';
comment on column recipes.recipe_step_dependencies.restaurant_id is 'Local de la receta, si es de un local (lo copia la base).';
comment on column recipes.recipe_step_dependencies.step_id is 'El paso que espera.';
comment on column recipes.recipe_step_dependencies.depends_on_step_id is 'El paso que tiene que terminar antes.';
comment on column recipes.recipe_step_dependencies.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipe_step_dependencies.created_by is 'Quién la creó (lo pone la base).';
comment on column recipes.recipe_step_dependencies.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_step_dependencies.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipe_step_dependencies.deleted_at is 'Borrado lógico, junto con su paso.';
comment on column recipes.recipe_step_dependencies.deleted_by is 'Quién la borró (lo pone la base).';

create table recipes.recipe_assignments (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null,
  recipe_id      uuid not null,
  restaurant_id  uuid not null,
  valid_from     date not null,
  valid_to       date,
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint recipe_assignments_recipe_fkey foreign key (recipe_id, group_id)
    references recipes.recipes (id, group_id) on delete restrict,
  constraint recipe_assignments_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint recipe_assignments_dates_check check (valid_to is null or valid_to >= valid_from)
);
-- Una sola asignación abierta por receta y local.
create unique index recipe_assignments_open_key on recipes.recipe_assignments (recipe_id, restaurant_id)
  where valid_to is null and deleted_at is null;
create index recipe_assignments_group_idx on recipes.recipe_assignments (group_id);
create index recipe_assignments_recipe_idx on recipes.recipe_assignments (recipe_id, group_id);
create index recipe_assignments_restaurant_idx on recipes.recipe_assignments (restaurant_id, group_id);
comment on table recipes.recipe_assignments is
  'Qué receta usa cada local y desde cuándo, sin copiarla. Una receta de local queda asignada a su local sola.';
comment on column recipes.recipe_assignments.id is 'Identificador de la asignación.';
comment on column recipes.recipe_assignments.group_id is 'Grupo de la receta.';
comment on column recipes.recipe_assignments.recipe_id is 'Receta asignada.';
comment on column recipes.recipe_assignments.restaurant_id is 'Local que la usa.';
comment on column recipes.recipe_assignments.valid_from is 'Desde qué día la usa (fecha de la Argentina).';
comment on column recipes.recipe_assignments.valid_to is 'Hasta qué día (sin incluirlo). Vacío si sigue vigente.';
comment on column recipes.recipe_assignments.created_at is 'Cuándo se creó (lo pone la base).';
comment on column recipes.recipe_assignments.created_by is 'Quién la creó (lo pone la base).';
comment on column recipes.recipe_assignments.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_assignments.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipe_assignments.deleted_at is 'Borrado lógico.';
comment on column recipes.recipe_assignments.deleted_by is 'Quién la borró (lo pone la base).';

-- ---------------------------------------------------------------------------
-- 3. Reglas (triggers)
-- ---------------------------------------------------------------------------
-- Categorías: dos niveles y madre vigente, como las de materias primas.
create function recipes.enforce_category_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted timestamptz;
begin
  if new.parent_id is not null and (tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id) then
    select deleted_at into v_deleted from recipes.recipe_categories where id = new.parent_id for share;
    if v_deleted is not null then
      raise exception 'La categoría madre está borrada: elegí otra.' using errcode = '23514';
    end if;
  end if;
  if new.parent_id is not null
     and (exists (select 1 from recipes.recipe_categories where id = new.parent_id and parent_id is not null)
          or exists (select 1 from recipes.recipe_categories where parent_id = new.id and deleted_at is null)) then
    raise exception 'Las categorías tienen solo dos niveles: categoría y subcategoría.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function recipes.enforce_category_rules() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipe_categories: solo dos niveles y la madre vigente.';
revoke execute on function recipes.enforce_category_rules() from public;
create trigger enforce_category_rules before insert or update on recipes.recipe_categories
  for each row execute function recipes.enforce_category_rules();

-- Recetas: la categoría tiene que estar vigente (con "for share", para no cruzarse con una baja).
create function recipes.enforce_recipe_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted timestamptz;
begin
  if tg_op = 'UPDATE' and (new.code is distinct from old.code or new.scope_type is distinct from old.scope_type
                           or new.brand_id is distinct from old.brand_id
                           or new.restaurant_id is distinct from old.restaurant_id) then
    raise exception 'El código y el alcance de una receta no cambian.' using errcode = '42501';
  end if;
  if new.category_id is not null and (tg_op = 'INSERT' or new.category_id is distinct from old.category_id) then
    select deleted_at into v_deleted from recipes.recipe_categories where id = new.category_id for share;
    if v_deleted is not null then
      raise exception 'Esa categoría está borrada: elegí otra.' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function recipes.enforce_recipe_rules() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipes: el código y el alcance no cambian; la categoría tiene que estar vigente.';
revoke execute on function recipes.enforce_recipe_rules() from public;
create trigger enforce_recipe_rules before insert or update on recipes.recipes
  for each row execute function recipes.enforce_recipe_rules();

-- Versiones, líneas, pasos y dependencias llevan la marca y el local de su receta: los copia la base
-- (nunca los manda la app). Así la auditoría queda con el alcance de la receta (database.md).
create function recipes.inherit_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'recipe_versions' then
    select r.brand_id, r.restaurant_id into new.brand_id, new.restaurant_id from recipes.recipes r where r.id = new.recipe_id;
  elsif tg_table_name in ('recipe_components', 'recipe_steps') then
    select v.brand_id, v.restaurant_id into new.brand_id, new.restaurant_id
      from recipes.recipe_versions v where v.id = new.recipe_version_id;
  else
    select s.brand_id, s.restaurant_id into new.brand_id, new.restaurant_id from recipes.recipe_steps s where s.id = new.step_id;
  end if;
  return new;
end
$$;
comment on function recipes.inherit_scope() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipe_versions, recipe_components, recipe_steps y recipe_step_dependencies: copia la marca y el local de la receta.';
revoke execute on function recipes.inherit_scope() from public;
create trigger inherit_scope before insert or update on recipes.recipe_versions
  for each row execute function recipes.inherit_scope();
create trigger inherit_scope before insert or update on recipes.recipe_components
  for each row execute function recipes.inherit_scope();
create trigger inherit_scope before insert or update on recipes.recipe_steps
  for each row execute function recipes.inherit_scope();
create trigger inherit_scope before insert or update on recipes.recipe_step_dependencies
  for each row execute function recipes.inherit_scope();

-- Versiones: la regla general de la Fase 1, más que el grupo sea el de la receta.
create trigger enforce_version_rules before insert or update or delete on recipes.recipe_versions
  for each row execute function core.enforce_version_rules('approved_by', 'published_at');

-- Líneas, pasos y dependencias: solo se cambian mientras su versión es borrador, y nunca se borran.
create function recipes.enforce_draft_lines()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version uuid;
  v_status  core.version_status;
begin
  if tg_op = 'DELETE' then
    raise exception 'Las líneas de una receta no se borran: se reemplazan en un borrador.' using errcode = '42501';
  end if;
  if tg_table_name = 'recipe_step_dependencies' then
    select recipe_version_id into v_version from recipes.recipe_steps where id = new.step_id;
  else
    v_version := new.recipe_version_id;
  end if;
  select status into v_status from recipes.recipe_versions where id = v_version;
  if v_status is distinct from 'draft' then
    raise exception 'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and to_jsonb(new) ? 'recipe_version_id'
     and (to_jsonb(new) ->> 'recipe_version_id') is distinct from (to_jsonb(old) ->> 'recipe_version_id') then
    raise exception 'Una línea no cambia de versión.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function recipes.enforce_draft_lines() is
  'Trigger (BEFORE INSERT OR UPDATE OR DELETE) de recipe_components, recipe_steps y recipe_step_dependencies: solo cambian en un borrador y nunca se borran físicamente.';
revoke execute on function recipes.enforce_draft_lines() from public;
create trigger enforce_draft_lines before insert or update or delete on recipes.recipe_components
  for each row execute function recipes.enforce_draft_lines();
create trigger enforce_draft_lines before insert or update or delete on recipes.recipe_steps
  for each row execute function recipes.enforce_draft_lines();
create trigger enforce_draft_lines before insert or update or delete on recipes.recipe_step_dependencies
  for each row execute function recipes.enforce_draft_lines();

-- Dependencias: los dos pasos de la misma versión y sin ciclos.
create function recipes.enforce_step_dependency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null then
    return new;
  end if;
  if (select recipe_version_id from recipes.recipe_steps where id = new.step_id)
     is distinct from (select recipe_version_id from recipes.recipe_steps where id = new.depends_on_step_id) then
    raise exception 'Un paso solo puede esperar a otro paso de la misma receta.' using errcode = '23514';
  end if;
  -- Si desde el paso del que depende se llega (por sus propias dependencias) a este, hay un ciclo.
  if exists (
       with recursive up (id) as (
         select d.depends_on_step_id from recipes.recipe_step_dependencies d
          where d.step_id = new.depends_on_step_id and d.deleted_at is null
         union
         select d.depends_on_step_id from recipes.recipe_step_dependencies d join up on d.step_id = up.id
          where d.deleted_at is null)
       select 1 from up where id = new.step_id) then
    raise exception 'Los pasos no pueden esperarse en círculo.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function recipes.enforce_step_dependency() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipe_step_dependencies: los dos pasos de la misma versión y sin ciclos.';
revoke execute on function recipes.enforce_step_dependency() from public;
create trigger enforce_step_dependency before insert or update on recipes.recipe_step_dependencies
  for each row execute function recipes.enforce_step_dependency();

-- Columnas de control, auditoría y truncate en todas las tablas.
do $$
declare
  t text;
begin
  foreach t in array array['recipe_categories', 'recipes', 'recipe_versions', 'recipe_components', 'recipe_steps',
                           'recipe_step_dependencies', 'recipe_assignments'] loop
    execute format('alter table recipes.%I enable row level security', t);
    execute format('revoke all on recipes.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger set_control_columns before insert or update on recipes.%I
                      for each row execute function core.set_control_columns()', t);
    execute format('create trigger log_change after insert or update or delete on recipes.%I
                      for each row execute function audit.log_change()', t);
    execute format('create trigger reject_truncate before truncate on recipes.%I
                      for each statement execute function core.reject_truncate()', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Quién puede qué (las políticas y las funciones usan estas, sin repetir la lógica)
-- ---------------------------------------------------------------------------
-- Las políticas usan conjuntos (core.permitted_*_ids), que se calculan una vez por consulta. Una
-- función por fila no escala: con 2.000 recetas tardaba casi 3 segundos (revisión de base, G1).

create function recipes.today()
returns date
language sql
stable
set search_path = ''
as $$ select (now() at time zone 'America/Argentina/Buenos_Aires')::date $$;
comment on function recipes.today() is 'Interna: hoy en la Argentina.';
revoke execute on function recipes.today() from public;

-- El permiso en el alcance de una receta: en ese local, en toda la marca o en todo el grupo. Para las
-- escrituras, donde se pregunta por un solo lugar.
create function recipes.allowed(p_permission text, p_group_id uuid, p_brand_id uuid, p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(case when p_restaurant_id is not null then core.has_permission(p_permission, p_restaurant_id)
                       when p_brand_id is not null then core.has_permission_in_brand(p_permission, p_brand_id)
                       else core.has_permission_in_group(p_permission, p_group_id) end, false)
$$;
comment on function recipes.allowed(text, uuid, uuid, uuid) is
  'Interna: si la sesión tiene el permiso en el alcance de una receta (core.has_permission*). Para las escrituras.';
revoke execute on function recipes.allowed(text, uuid, uuid, uuid) from public;

-- Recetas cuya versión vigente ve la sesión: con recipes.view en su alcance; las maestras del grupo,
-- también quien ve toda una marca del grupo (para asignarlas); y cualquiera con recipes.view en un
-- local al que está asignada. Sin versión vigente no hay nada que ver (ni el nombre).
create function recipes.viewable_recipe_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select r.id
    from recipes.recipes r
   where r.deleted_at is null
     and exists (select 1 from recipes.recipe_versions v where v.recipe_id = r.id and v.status = 'published')
     and (r.restaurant_id in (select core.permitted_restaurant_ids('recipes.view'))
          or (r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('recipes.view')))
          or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('recipes.view')))
          or (r.brand_id is null
              and r.group_id in (select b.group_id from org.brands b
                                  where b.id in (select core.permitted_brand_ids('recipes.view'))))
          or r.id in (select a.recipe_id from recipes.recipe_assignments a
                       where a.deleted_at is null and a.valid_from <= recipes.today()
                         and (a.valid_to is null or a.valid_to > recipes.today())
                         and a.restaurant_id in (select core.permitted_restaurant_ids('recipes.view'))))
$$;
comment on function recipes.viewable_recipe_ids() is
  'Recetas cuya versión vigente ve la sesión: por su alcance, por ver toda una marca (maestras del grupo) o porque está asignada a un local suyo. Para las políticas.';

-- Recetas que la sesión trabaja (ve borradores, revisiones e historia): con recipes.draft, review o
-- publish en su alcance.
create function recipes.workable_recipe_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with p (perm) as (values ('recipes.draft'), ('recipes.review'), ('recipes.publish')),
  rs as (select core.permitted_restaurant_ids(p.perm) as id from p),
  bs as (select core.permitted_brand_ids(p.perm) as id from p),
  gs as (select core.permitted_group_ids(p.perm) as id from p)
  select r.id
    from recipes.recipes r
   where r.deleted_at is null
     and (r.restaurant_id in (select id from rs)
          or (r.restaurant_id is null and r.brand_id in (select id from bs))
          or (r.brand_id is null and r.group_id in (select id from gs)))
$$;
comment on function recipes.workable_recipe_ids() is
  'Recetas que la sesión trabaja (recipes.draft, review o publish en su alcance): ve borradores, revisiones e historia. Para las políticas.';

-- Versiones que ve la sesión: la vigente de las que ve; todas las de las que trabaja.
create function recipes.visible_version_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select v.id
    from recipes.recipe_versions v
   where v.deleted_at is null
     and (v.recipe_id in (select recipes.workable_recipe_ids())
          or (v.status = 'published' and v.recipe_id in (select recipes.viewable_recipe_ids())))
$$;
comment on function recipes.visible_version_ids() is
  'Versiones que ve la sesión: la vigente de las recetas que ve y todas las de las recetas que trabaja. Para las políticas.';

-- Para una sola receta o versión (las funciones con permisos propios), los mismos conjuntos.
create function recipes.can_view_recipe(p_recipe_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from recipes.viewable_recipe_ids() x where x = p_recipe_id) $$;
comment on function recipes.can_view_recipe(uuid) is 'Interna: si la sesión ve la versión vigente de esa receta.';
revoke execute on function recipes.can_view_recipe(uuid) from public;

create function recipes.can_work_recipe(p_recipe_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from recipes.workable_recipe_ids() x where x = p_recipe_id) $$;
comment on function recipes.can_work_recipe(uuid) is 'Interna: si la sesión trabaja esa receta (ve borradores e historia).';
revoke execute on function recipes.can_work_recipe(uuid) from public;

create function recipes.can_see_version(p_version_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$ select exists (select 1 from recipes.visible_version_ids() x where x = p_version_id) $$;
comment on function recipes.can_see_version(uuid) is
  'Interna: si la sesión ve esa versión (la vigente con recipes.view; cualquiera si trabaja la receta).';
revoke execute on function recipes.can_see_version(uuid) from public;

-- ---------------------------------------------------------------------------
-- 5. Lectura (RLS)
-- ---------------------------------------------------------------------------
grant usage on schema recipes to authenticated;
create policy recipe_categories_select on recipes.recipe_categories for select to authenticated
  using (deleted_at is null and group_id in (select core.visible_group_ids('recipes.view')));
create policy recipes_select on recipes.recipes for select to authenticated
  using (deleted_at is null
         and (id in (select recipes.viewable_recipe_ids()) or id in (select recipes.workable_recipe_ids())));
-- Quien solo ve, ve la vigente; quien trabaja la receta, todas.
create policy recipe_versions_select on recipes.recipe_versions for select to authenticated
  using (id in (select recipes.visible_version_ids()));
create policy recipe_components_select on recipes.recipe_components for select to authenticated
  using (deleted_at is null and recipe_version_id in (select recipes.visible_version_ids()));
create policy recipe_steps_select on recipes.recipe_steps for select to authenticated
  using (deleted_at is null and recipe_version_id in (select recipes.visible_version_ids()));
create policy recipe_step_dependencies_select on recipes.recipe_step_dependencies for select to authenticated
  using (deleted_at is null and step_id in (select s.id from recipes.recipe_steps s));
-- Las asignaciones, solo de los locales que la sesión ve.
create policy recipe_assignments_select on recipes.recipe_assignments for select to authenticated
  using (deleted_at is null
         and restaurant_id in (select core.permitted_restaurant_ids('recipes.view'))
         and (recipe_id in (select recipes.viewable_recipe_ids()) or recipe_id in (select recipes.workable_recipe_ids())));
grant select on recipes.recipe_categories, recipes.recipes, recipes.recipe_versions, recipes.recipe_components,
  recipes.recipe_steps, recipes.recipe_step_dependencies, recipes.recipe_assignments to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Ayudantes internos de escritura
-- ---------------------------------------------------------------------------
create function recipes.raise_friendly(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'recipes_code_key' then 'Ya existe una receta con ese código en el grupo.'
    when p_constraint = 'recipes_code_check' then
      'El código va en mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, REC-0001).'
    when p_constraint = 'recipes_name_check' then 'El nombre no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint = 'recipes_short_name_check' then 'El nombre corto va hasta 40 caracteres.'
    when p_constraint = 'recipe_categories_name_key' then 'Ya existe una categoría con ese nombre en el mismo nivel.'
    when p_constraint = 'recipe_categories_name_check' then 'El nombre no puede quedar vacío ni pasar los 80 caracteres.'
    when p_constraint = 'recipe_versions_open_key' then 'Ya hay una versión en borrador o en revisión: seguí con esa.'
    when p_constraint = 'recipe_assignments_open_key' then 'La receta ya está asignada a ese local.'
    when p_constraint = 'recipe_steps_instructions_check' then 'Cada paso necesita sus instrucciones (hasta 2.000 caracteres).'
    when p_constraint like 'recipe_steps_%_minutes_check' then 'Los minutos van de 0 a 10.080 (una semana).'
    when p_constraint = 'recipe_components_quantity_check' then 'La cantidad tiene que ser mayor que cero.'
    when p_constraint like '%\_notes\_check' or p_constraint like 'recipe_versions_%_check' then
      'Algún texto es demasiado largo o algún número no es válido.'
    when p_state = '23503' then 'Algo de lo elegido (local, categoría, materia prima o unidad) no existe en este grupo.'
    else p_message
  end;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function recipes.raise_friendly(text, text, text) is
  'Interna: vuelve a lanzar un error de restricción con un mensaje en español para la persona.';
revoke execute on function recipes.raise_friendly(text, text, text) from public;

-- Una versión en revisión cuya solicitud se rechazó o se retiró vuelve a borrador para corregirla.
create function recipes.reopen_returned(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update recipes.recipe_versions v set status = 'draft', approval_request_id = null, review_requested_by = null
   where v.id = p_version_id and v.status = 'in_review'
     and exists (select 1 from workflow.approval_requests q
                  where q.id = v.approval_request_id and q.status in ('rejected', 'cancelled'));
end
$$;
comment on function recipes.reopen_returned(uuid) is
  'Interna: si la revisión de esa versión se rechazó o se retiró, la versión vuelve a borrador.';
revoke execute on function recipes.reopen_returned(uuid) from public;


-- Un borrador listo para editar, una vez controlado el permiso: si su revisión se rechazó o se retiró,
-- vuelve a borrador; tiene que ser borrador, de una receta activa (bloqueada con "for share", para no
-- cruzarse con un archivo) y, si se indica, nadie lo cambió desde que la pantalla lo leyó (base, M2).
create function recipes.open_draft(p_version_id uuid, p_expected_updated_at timestamptz)
returns recipes.recipe_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v recipes.recipe_versions;
begin
  perform recipes.reopen_returned(p_version_id);
  select * into v from recipes.recipe_versions where id = p_version_id for update;
  if v.status <> 'draft' then
    raise exception 'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.' using errcode = '23514';
  end if;
  perform 1 from recipes.recipes where id = v.recipe_id and is_active for share;
  if not found then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  if p_expected_updated_at is not null and v.updated_at is distinct from p_expected_updated_at then
    raise exception 'Otra persona cambió este borrador mientras lo editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  return v;
end
$$;
comment on function recipes.open_draft(uuid, timestamptz) is
  'Interna: deja listo un borrador para editarlo (reabre si se rechazó, controla que sea borrador de una receta activa y que nadie lo haya cambiado desde p_expected_updated_at).';
revoke execute on function recipes.open_draft(uuid, timestamptz) from public;

-- ---------------------------------------------------------------------------
-- 7. Escritura
-- ---------------------------------------------------------------------------
create function recipes.create_recipe(p_group_id uuid, p_brand_id uuid, p_restaurant_id uuid, p_code text, p_name text,
                                      p_type recipes.recipe_type, p_category_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group      uuid := p_group_id;
  v_brand      uuid := p_brand_id;
  v_scope      recipes.recipe_scope;
  v_recipe     uuid;
  v_version    uuid;
  v_constraint text;
  v_message    text;
begin
  -- El alcance sale del lugar más chico indicado; marca y grupo se completan desde el local.
  if p_restaurant_id is not null then
    select r.brand_id, r.group_id into v_brand, v_group from org.restaurants r
     where r.id = p_restaurant_id and r.deleted_at is null;
    v_scope := 'restaurant';
  elsif p_brand_id is not null then
    select b.group_id into v_group from org.brands b where b.id = p_brand_id and b.deleted_at is null;
    v_scope := 'brand';
  else
    v_scope := 'group';
  end if;
  if v_group is null or (p_group_id is not null and v_group <> p_group_id)
     or not recipes.allowed('recipes.draft', v_group, v_brand, p_restaurant_id) then
    return core.deny('recipes.create_recipe', 'No tenés permiso para crear recetas en ese lugar.', null,
                     jsonb_build_object('group_id', p_group_id, 'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id),
                     v_group, v_brand, p_restaurant_id);
  end if;
  if p_type is null then
    raise exception 'Elegí el tipo de receta.' using errcode = '22023';
  end if;
  if p_category_id is not null
     and not exists (select 1 from recipes.recipe_categories where id = p_category_id and group_id = v_group and deleted_at is null) then
    raise exception 'Elegí una categoría de recetas del grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipes (group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id)
  values (v_group, v_brand, p_restaurant_id, v_scope, upper(btrim(p_code)), btrim(p_name), p_type, p_category_id)
  returning id into v_recipe;
  insert into recipes.recipe_versions (group_id, recipe_id, version_number) values (v_group, v_recipe, 1)
  returning id into v_version;
  -- Una receta de local la usa su local desde hoy.
  if p_restaurant_id is not null then
    insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
    values (v_group, v_recipe, p_restaurant_id, recipes.today());
  end if;
  return jsonb_build_object('result', 'applied', 'id', v_recipe, 'version_id', v_version,
                            'message', 'Receta creada. Ahora cargá sus componentes y sus pasos.');
exception when unique_violation or check_violation or foreign_key_violation or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint is null and sqlstate = '23502' then
    raise exception 'Faltan el código o el nombre.' using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.create_recipe(uuid, uuid, uuid, text, text, recipes.recipe_type, uuid, text) is
  'Crea una receta y su versión 1 en borrador. El alcance es el lugar más chico indicado (local, marca o grupo). Pide recipes.draft ahí y un motivo; sin permiso devuelve denied y queda registrado.';

create function recipes.update_recipe(p_id uuid, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r          recipes.recipes;
  v_constraint text;
  v_message    text;
begin
  select * into v_r from recipes.recipes where id = p_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.update_recipe', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('recipe_id', p_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  perform org.check_keys(p_changes, array['name', 'short_name', 'category_id', 'sector', 'station', 'technical_owner_id']);
  if nullif(p_changes ->> 'category_id', '') is not null
     and not exists (select 1 from recipes.recipe_categories
                      where id = (p_changes ->> 'category_id')::uuid and group_id = v_r.group_id and deleted_at is null) then
    raise exception 'Elegí una categoría de recetas del grupo.' using errcode = '22023';
  end if;
  if nullif(p_changes ->> 'technical_owner_id', '') is not null
     and not exists (select 1 from core.user_memberships m
                      where m.user_id = (p_changes ->> 'technical_owner_id')::uuid and m.group_id = v_r.group_id
                        and m.deleted_at is null) then
    raise exception 'Elegí como responsable técnico a una persona del grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipes
     set name               = coalesce(btrim(p_changes ->> 'name'), name),
         short_name         = case when p_changes ? 'short_name' then nullif(btrim(p_changes ->> 'short_name'), '') else short_name end,
         category_id        = case when p_changes ? 'category_id' then nullif(p_changes ->> 'category_id', '')::uuid else category_id end,
         sector             = case when p_changes ? 'sector' then nullif(btrim(p_changes ->> 'sector'), '') else sector end,
         station            = case when p_changes ? 'station' then nullif(btrim(p_changes ->> 'station'), '') else station end,
         technical_owner_id = case when p_changes ? 'technical_owner_id' then nullif(p_changes ->> 'technical_owner_id', '')::uuid
                                   else technical_owner_id end
   where id = p_id;
  return jsonb_build_object('result', 'applied', 'message', 'Receta actualizada.');
exception when unique_violation or check_violation or foreign_key_violation or invalid_text_representation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if sqlstate = '22P02' then
    raise exception 'Algún dato no tiene el formato esperado.' using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.update_recipe(uuid, jsonb, text) is
  'Edita los datos de una receta (nombre, nombre corto, categoría, sector, partida, responsable). El código y el alcance no cambian. Pide recipes.draft y un motivo.';

create function recipes.new_version(p_recipe_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r      recipes.recipes;
  v_base   recipes.recipe_versions;
  v_id     uuid;
  v_open   uuid;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.new_version', 'No tenés permiso para crear versiones de esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if not v_r.is_active then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  select id into v_open from recipes.recipe_versions where recipe_id = p_recipe_id and status in ('draft', 'in_review');
  if v_open is not null then
    raise exception 'Ya hay una versión en borrador o en revisión: seguí con esa.' using errcode = '23505';
  end if;
  -- La base es la vigente; si no hay, la última.
  select * into v_base from recipes.recipe_versions
   where recipe_id = p_recipe_id order by (status = 'published') desc, version_number desc limit 1;
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipe_versions (group_id, recipe_id, version_number, previous_version_id, yield_quantity,
                                       yield_unit_id, portions, portion_grams, description, storage_notes,
                                       presentation_notes)
  select v_r.group_id, p_recipe_id, (select max(version_number) + 1 from recipes.recipe_versions where recipe_id = p_recipe_id),
         v_base.id, v_base.yield_quantity, v_base.yield_unit_id, v_base.portions, v_base.portion_grams, v_base.description,
         v_base.storage_notes, v_base.presentation_notes
  returning id into v_id;
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id,
                                         quantity_basis, yield_profile_id, no_scale, notes)
  select group_id, v_id, line_order, ingredient_id, quantity, unit_id, quantity_basis, yield_profile_id, no_scale, notes
    from recipes.recipe_components where recipe_version_id = v_base.id and deleted_at is null;
  insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                    passive_minutes, workers, sector, equipment, control_point)
  select group_id, v_id, step_number, kind, instructions, active_minutes, passive_minutes, workers, sector, equipment,
         control_point
    from recipes.recipe_steps where recipe_version_id = v_base.id and deleted_at is null;
  -- Las dependencias se copian por número de paso.
  insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
  select v_r.group_id, ns.id, nd.id
    from recipes.recipe_step_dependencies d
    join recipes.recipe_steps os on os.id = d.step_id
    join recipes.recipe_steps od on od.id = d.depends_on_step_id
    join recipes.recipe_steps ns on ns.recipe_version_id = v_id and ns.step_number = os.step_number and ns.deleted_at is null
    join recipes.recipe_steps nd on nd.recipe_version_id = v_id and nd.step_number = od.step_number and nd.deleted_at is null
   where os.recipe_version_id = v_base.id and d.deleted_at is null;
  return jsonb_build_object('result', 'applied', 'id', v_id,
                            'message', 'Versión nueva en borrador. La vigente sigue igual hasta que se publique esta.');
end
$$;
comment on function recipes.new_version(uuid, text) is
  'Crea una versión nueva en borrador copiando la vigente (o la última), con sus líneas, pasos y dependencias. La vigente no cambia (caso 6). Pide recipes.draft y un motivo.';

create function recipes.save_draft(p_version_id uuid, p_data jsonb, p_reason text, p_expected_updated_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_v          recipes.recipe_versions;
  v_r          recipes.recipes;
  v_unit       uuid;
  v_constraint text;
  v_message    text;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.save_draft', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  v_v := recipes.open_draft(p_version_id, p_expected_updated_at);
  perform org.check_keys(p_data, array['yield_quantity', 'yield_unit', 'portions', 'portion_grams', 'description',
                                       'storage_notes', 'presentation_notes', 'change_summary']);
  if p_data ? 'yield_unit' and nullif(p_data ->> 'yield_unit', '') is not null then
    select id into v_unit from catalog.units where code = p_data ->> 'yield_unit';
    if v_unit is null then
      raise exception 'Elegí la unidad del rendimiento.' using errcode = '22023';
    end if;
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_versions
     set yield_quantity     = case when p_data ? 'yield_quantity' then nullif(p_data ->> 'yield_quantity', '')::numeric else yield_quantity end,
         yield_unit_id      = case when p_data ? 'yield_unit' then v_unit else yield_unit_id end,
         portions           = case when p_data ? 'portions' then nullif(p_data ->> 'portions', '')::integer else portions end,
         portion_grams      = case when p_data ? 'portion_grams' then nullif(p_data ->> 'portion_grams', '')::numeric else portion_grams end,
         description        = case when p_data ? 'description' then nullif(btrim(p_data ->> 'description'), '') else description end,
         storage_notes      = case when p_data ? 'storage_notes' then nullif(btrim(p_data ->> 'storage_notes'), '') else storage_notes end,
         presentation_notes = case when p_data ? 'presentation_notes' then nullif(btrim(p_data ->> 'presentation_notes'), '')
                                   else presentation_notes end,
         change_summary     = case when p_data ? 'change_summary' then nullif(btrim(p_data ->> 'change_summary'), '') else change_summary end
   where id = p_version_id;
  return jsonb_build_object('result', 'applied', 'message', 'Borrador guardado.');
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'recipe_versions_yield_unit_check' then
    raise exception 'El rendimiento necesita la cantidad y la unidad.' using errcode = '23514';
  elsif sqlstate in ('22P02', '22003') then
    raise exception 'Algún número no es válido.' using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.save_draft(uuid, jsonb, text, timestamptz) is
  'Guarda los datos de un borrador: rendimiento (cantidad y código de unidad), porciones, peso por porción, descripción, conservación, presentación y resumen del cambio. Con p_expected_updated_at, rechaza si otra persona lo cambió. Pide recipes.draft y un motivo.';

create function recipes.set_components(p_version_id uuid, p_lines jsonb, p_reason text,
                                       p_expected_updated_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_v          recipes.recipe_versions;
  v_r          recipes.recipes;
  v_line       jsonb;
  v_n          integer := 0;
  v_ing        catalog.ingredients;
  v_unit       catalog.units;
  v_status     text;
  v_qty        numeric;
  v_basis      recipes.quantity_basis;
  v_profile    uuid;
  v_constraint text;
  v_message    text;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.set_components', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  v_v := recipes.open_draft(p_version_id, p_expected_updated_at);
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then
    raise exception 'Las líneas tienen que ser una lista (hasta 200).' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_components set deleted_at = now() where recipe_version_id = p_version_id and deleted_at is null;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_n := v_n + 1;
    perform org.check_keys(v_line, array['ingredient_id', 'quantity', 'unit', 'basis', 'yield_profile_id', 'no_scale', 'notes']);
    select * into v_ing from catalog.ingredients
     where id = nullif(v_line ->> 'ingredient_id', '')::uuid and group_id = v_r.group_id and deleted_at is null;
    if v_ing.id is null then
      raise exception 'Línea %: elegí una materia prima vigente del grupo.', v_n using errcode = '22023';
    end if;
    v_qty := nullif(v_line ->> 'quantity', '')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Línea % (%): la cantidad tiene que ser mayor que cero.', v_n, v_ing.name using errcode = '22023';
    end if;
    select * into v_unit from catalog.units where code = v_line ->> 'unit';
    if v_unit.id is null then
      raise exception 'Línea % (%): elegí la unidad.', v_n, v_ing.name using errcode = '22023';
    end if;
    -- La cantidad se tiene que poder pasar a la unidad de la materia prima: si no, el costo no se podría calcular.
    select b.status into v_status from catalog.to_base_quantity(v_ing.id, v_qty, v_unit.id) b;
    if v_status is distinct from 'ok' then
      raise exception 'Línea % (%): no se puede pasar de % a la unidad de la materia prima. Cargá la conversión en su ficha o usá otra unidad.',
        v_n, v_ing.name, v_unit.name using errcode = '22023';
    end if;
    v_basis := coalesce(nullif(v_line ->> 'basis', ''), 'purchase')::recipes.quantity_basis;
    v_profile := nullif(v_line ->> 'yield_profile_id', '')::uuid;
    if v_profile is not null and not exists (select 1 from catalog.ingredient_yield_profiles
                                               where id = v_profile and ingredient_id = v_ing.id and status = 'approved'
                                                 and deleted_at is null) then
      raise exception 'Línea % (%): el rendimiento elegido no es un estándar vigente de esa materia prima.', v_n, v_ing.name
        using errcode = '22023';
    end if;
    insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id,
                                           quantity_basis, yield_profile_id, no_scale, notes)
    values (v_r.group_id, p_version_id, v_n, v_ing.id, v_qty, v_unit.id, v_basis, v_profile,
            coalesce((v_line ->> 'no_scale')::boolean, false), nullif(btrim(v_line ->> 'notes'), ''));
  end loop;
  update recipes.recipe_versions set updated_at = now() where id = p_version_id;
  return jsonb_build_object('result', 'applied', 'message', format('Componentes guardados (%s).', v_n));
exception when check_violation or invalid_text_representation or numeric_value_out_of_range or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if sqlstate in ('22P02', '22003') then
    raise exception 'Línea %: algún dato no es válido.', v_n using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.set_components(uuid, jsonb, text, timestamptz) is
  'Reemplaza las líneas de un borrador (las anteriores quedan con borrado lógico). Cada línea: ingredient_id, quantity, unit (código), basis (purchase, clean o cooked), yield_profile_id, no_scale, notes. Pide recipes.draft y un motivo.';

create function recipes.set_steps(p_version_id uuid, p_steps jsonb, p_reason text, p_expected_updated_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_v          recipes.recipe_versions;
  v_recipe     recipes.recipes;
  v_id         uuid;
  v_step       jsonb;
  v_dep        jsonb;
  v_n          integer := 0;
  v_ids        uuid[] := '{}';
  v_count      integer;
  v_constraint text;
  v_message    text;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_recipe from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_recipe.id is null or not recipes.allowed('recipes.draft', v_recipe.group_id, v_recipe.brand_id, v_recipe.restaurant_id) then
    return core.deny('recipes.set_steps', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_recipe.group_id, v_recipe.brand_id, v_recipe.restaurant_id);
  end if;
  v_v := recipes.open_draft(p_version_id, p_expected_updated_at);
  if p_steps is null or jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) > 100 then
    raise exception 'Los pasos tienen que ser una lista (hasta 100).' using errcode = '22023';
  end if;
  v_count := jsonb_array_length(p_steps);
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_step_dependencies d set deleted_at = now()
   where d.deleted_at is null
     and d.step_id in (select id from recipes.recipe_steps where recipe_version_id = p_version_id and deleted_at is null);
  update recipes.recipe_steps set deleted_at = now() where recipe_version_id = p_version_id and deleted_at is null;
  for v_step in select value from jsonb_array_elements(p_steps) loop
    v_n := v_n + 1;
    perform org.check_keys(v_step, array['kind', 'instructions', 'active_minutes', 'passive_minutes', 'workers', 'sector',
                                         'equipment', 'control_point', 'depends_on']);
    insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                      passive_minutes, workers, sector, equipment, control_point)
    values (v_recipe.group_id, p_version_id, v_n, coalesce(nullif(v_step ->> 'kind', ''), 'preparation')::recipes.step_kind,
            btrim(coalesce(v_step ->> 'instructions', '')), coalesce(nullif(v_step ->> 'active_minutes', '')::integer, 0),
            coalesce(nullif(v_step ->> 'passive_minutes', '')::integer, 0), nullif(v_step ->> 'workers', '')::smallint,
            nullif(btrim(v_step ->> 'sector'), ''), nullif(btrim(v_step ->> 'equipment'), ''),
            nullif(btrim(v_step ->> 'control_point'), ''))
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  -- Dependencias por número de paso ("el 4 espera al 2 y al 3").
  v_n := 0;
  for v_step in select value from jsonb_array_elements(p_steps) loop
    v_n := v_n + 1;
    if v_step ? 'depends_on' and jsonb_typeof(v_step -> 'depends_on') = 'array' then
      for v_dep in select value from jsonb_array_elements(v_step -> 'depends_on') loop
        if (v_dep #>> '{}')::integer not between 1 and v_count or (v_dep #>> '{}')::integer = v_n then
          raise exception 'Paso %: solo puede esperar a otro paso de la lista.', v_n using errcode = '22023';
        end if;
        insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
        values (v_recipe.group_id, v_ids[v_n], v_ids[(v_dep #>> '{}')::integer])
        on conflict do nothing;
      end loop;
    end if;
  end loop;
  update recipes.recipe_versions set updated_at = now() where id = p_version_id;
  return jsonb_build_object('result', 'applied', 'message', format('Pasos guardados (%s).', v_count));
exception when check_violation or invalid_text_representation or numeric_value_out_of_range or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if sqlstate in ('22P02', '22003') then
    raise exception 'Paso %: algún dato no es válido.', v_n using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.set_steps(uuid, jsonb, text, timestamptz) is
  'Reemplaza los pasos de un borrador y sus dependencias. Cada paso: kind, instructions, active_minutes, passive_minutes, workers, sector, equipment, control_point y depends_on (lista de números de paso). Pide recipes.draft y un motivo.';

-- Diferencias de las líneas contra la versión anterior, para la bandeja y el editor.
create function recipes.version_diff(p_version_id uuid)
returns table (change text, ingredient text, unit text, basis recipes.quantity_basis, old_quantity numeric,
               new_quantity numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_prev uuid;
begin
  -- Compara con la versión anterior, que es historia: solo para quien trabaja la receta.
  select v.previous_version_id into v_prev from recipes.recipe_versions v
   where v.id = p_version_id and v.deleted_at is null and recipes.can_work_recipe(v.recipe_id);
  if not found then
    return;
  end if;
  return query
  with n as (select c.ingredient_id, c.unit_id, c.quantity_basis, sum(c.quantity) as q from recipes.recipe_components c
              where c.recipe_version_id = p_version_id and c.deleted_at is null group by 1, 2, 3),
       o as (select c.ingredient_id, c.unit_id, c.quantity_basis, sum(c.quantity) as q from recipes.recipe_components c
              where c.recipe_version_id = v_prev and c.deleted_at is null group by 1, 2, 3)
  select case when o.q is null then 'added' when n.q is null then 'removed' else 'changed' end,
         i.name, u.name, coalesce(n.quantity_basis, o.quantity_basis), o.q, n.q
    from n full join o using (ingredient_id, unit_id, quantity_basis)
    join catalog.ingredients i on i.id = coalesce(n.ingredient_id, o.ingredient_id)
    join catalog.units u on u.id = coalesce(n.unit_id, o.unit_id)
   where n.q is distinct from o.q
   order by i.name;
end
$$;
comment on function recipes.version_diff(uuid) is
  'Qué líneas se agregaron, quitaron o cambiaron de cantidad respecto de la versión anterior. Solo para quien trabaja la receta; si no, vacío.';

create function recipes.request_review(p_version_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_v        recipes.recipe_versions;
  v_r        recipes.recipes;
  v_current  recipes.recipe_versions;
  v_lines    integer;
  v_steps    integer;
  v_changes  jsonb;
  v_request  uuid;
  v_bad_line integer;
  v_bad_name text;
  v_bad_why  text;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.allowed('recipes.review', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.request_review', 'No tenés permiso para pedir la revisión de esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  perform recipes.reopen_returned(p_version_id);
  select * into v_v from recipes.recipe_versions where id = p_version_id;
  perform 1 from recipes.recipes where id = v_r.id and is_active for share;
  if not found then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  if v_v.status <> 'draft' then
    raise exception 'Solo se pide la revisión de un borrador.' using errcode = '23514';
  end if;
  -- Las líneas copiadas de una versión anterior se vuelven a validar con las reglas de set_components.
  select c.line_order, i.name,
         case when i.id is null or i.deleted_at is not null or not i.is_active then 'la materia prima ya no está vigente'
              when b.status is distinct from 'ok' then 'no se puede pasar a la unidad de la materia prima'
              when c.yield_profile_id is not null
                   and not exists (select 1 from catalog.ingredient_yield_profiles p
                                    where p.id = c.yield_profile_id and p.status = 'approved' and p.deleted_at is null)
                then 'el rendimiento elegido ya no es el estándar vigente' end
    into v_bad_line, v_bad_name, v_bad_why
    from recipes.recipe_components c
    left join catalog.ingredients i on i.id = c.ingredient_id
    left join lateral catalog.to_base_quantity(c.ingredient_id, c.quantity, c.unit_id) b on true
   where c.recipe_version_id = p_version_id and c.deleted_at is null
     and (i.id is null or i.deleted_at is not null or not i.is_active or b.status is distinct from 'ok'
          or (c.yield_profile_id is not null
              and not exists (select 1 from catalog.ingredient_yield_profiles p
                               where p.id = c.yield_profile_id and p.status = 'approved' and p.deleted_at is null)))
   order by c.line_order
   limit 1;
  if v_bad_line is not null then
    raise exception 'Línea % (%): %. Corregila antes de pedir la revisión.', v_bad_line, v_bad_name, v_bad_why
      using errcode = '23514';
  end if;
  select count(*) into v_lines from recipes.recipe_components where recipe_version_id = p_version_id and deleted_at is null;
  select count(*) into v_steps from recipes.recipe_steps where recipe_version_id = p_version_id and deleted_at is null;
  if v_lines = 0 or v_steps = 0 or v_v.yield_quantity is null then
    raise exception 'Para pedir la revisión, la receta necesita al menos un componente, un paso y su rendimiento.'
      using errcode = '23514';
  end if;
  select * into v_current from recipes.recipe_versions where recipe_id = v_r.id and status = 'published';
  -- La solicitud la ve cualquiera con approvals.view: lleva solo cuántas líneas cambian, sin la fórmula.
  -- El detalle lo lee quien trabaja la receta, con version_diff (revisión de seguridad, M3).
  select jsonb_build_object('added', count(*) filter (where d.change = 'added'),
                            'removed', count(*) filter (where d.change = 'removed'),
                            'changed', count(*) filter (where d.change = 'changed'))
    into v_changes from recipes.version_diff(p_version_id) d;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_versions set status = 'in_review', review_requested_by = core.current_actor_id()
   where id = p_version_id;
  v_request := workflow.request_approval(
    'recipes.publish_version', v_r.group_id, v_r.brand_id, v_r.restaurant_id, null, p_version_id,
    jsonb_build_object('recipe', v_r.name, 'code', v_r.code, 'version_number', v_v.version_number,
                       'lines', v_lines, 'steps', v_steps, 'line_changes', v_changes, 'recipe_id', v_r.id,
                       'version_id', p_version_id),
    case when v_current.id is null then jsonb_build_object('version_number', null)
         else jsonb_build_object('version_number', v_current.version_number,
                                 'lines', (select count(*) from recipes.recipe_components
                                            where recipe_version_id = v_current.id and deleted_at is null)) end,
    p_reason);
  update recipes.recipe_versions set approval_request_id = v_request where id = p_version_id;
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'Queda en revisión: la tiene que aprobar otra persona con permiso de publicar.');
end
$$;
comment on function recipes.request_review(uuid, text) is
  'Pasa un borrador a revisión y crea la solicitud recipes.publish_version en el alcance de la receta, con las diferencias contra la vigente. Pide recipes.review y un motivo.';

create function recipes.withdraw_review(p_version_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_v      recipes.recipe_versions;
  v_r      recipes.recipes;
  v_result jsonb;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.can_work_recipe(v_r.id) then
    return core.deny('recipes.withdraw_review', 'No tenés permiso sobre esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if v_v.status <> 'in_review' then
    raise exception 'Esa versión no está en revisión.' using errcode = '23514';
  end if;
  -- Solo quien pidió la revisión la retira (regla de workflow.cancel_request).
  v_result := workflow.cancel_request(v_v.approval_request_id, p_reason);
  if v_result ->> 'result' not in ('cancelled', 'already_resolved') then
    return v_result;
  end if;
  perform recipes.reopen_returned(p_version_id);
  return jsonb_build_object('result', 'applied', 'message', 'Volvió a borrador: corregila y pedí la revisión de nuevo.');
end
$$;
comment on function recipes.withdraw_review(uuid, text) is
  'Retira de revisión una versión (solo quien la pidió, como cualquier solicitud) y la vuelve a borrador.';

-- Aplica la aprobación: archiva la vigente y publica la nueva, en la transacción de workflow.decide_approval.
create function recipes.apply_publish_version(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests := workflow.approved_request(p_request_id);
  v_v   recipes.recipe_versions;
begin
  select * into v_v from recipes.recipe_versions
   where id = v_req.entity_id and approval_request_id = p_request_id and deleted_at is null
   for update;
  if not found or v_v.status <> 'in_review' then
    perform workflow.cannot_apply('la versión ya no está en revisión');
  end if;
  if not exists (select 1 from recipes.recipes where id = v_v.recipe_id and is_active and deleted_at is null) then
    perform workflow.cannot_apply('la receta está archivada');
  end if;
  update recipes.recipe_versions set status = 'archived' where recipe_id = v_v.recipe_id and status = 'published';
  update recipes.recipe_versions set status = 'approved', approved_by = v_req.resolved_by where id = v_v.id;
  update recipes.recipe_versions set status = 'published', published_at = now() where id = v_v.id;
end
$$;
comment on function recipes.apply_publish_version(uuid) is
  'Interna (aprobación recipes.publish_version): la versión vigente pasa a archivada y la aprobada queda publicada, con quién y cuándo.';
revoke execute on function recipes.apply_publish_version(uuid) from public;

create function recipes.set_assignment(p_recipe_id uuid, p_restaurant_id uuid, p_assigned boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r     recipes.recipes;
  v_rest  org.restaurants;
  v_open  uuid;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  select * into v_rest from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or v_rest.id is null or not core.has_permission('recipes.assign', p_restaurant_id)
     or not (recipes.can_view_recipe(v_r.id) or recipes.can_work_recipe(v_r.id)) then
    return core.deny('recipes.set_assignment', 'No tenés permiso para asignar recetas en ese local.', null,
                     jsonb_build_object('recipe_id', p_recipe_id, 'restaurant_id', p_restaurant_id),
                     coalesce(v_r.group_id, v_rest.group_id), v_rest.brand_id, p_restaurant_id);
  end if;
  -- El local tiene que estar dentro del alcance de la receta.
  if v_rest.group_id <> v_r.group_id
     or (v_r.scope_type = 'brand' and v_rest.brand_id <> v_r.brand_id)
     or (v_r.scope_type = 'restaurant' and v_rest.id <> v_r.restaurant_id) then
    raise exception 'Esa receta no se puede usar en ese local: está fuera de su alcance.' using errcode = '23514';
  end if;
  if not v_r.is_active and coalesce(p_assigned, true) then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  select id into v_open from recipes.recipe_assignments
   where recipe_id = p_recipe_id and restaurant_id = p_restaurant_id and valid_to is null and deleted_at is null;
  perform core.set_change_context(p_reason, 'manual');
  if coalesce(p_assigned, true) then
    if v_open is not null then
      return jsonb_build_object('result', 'applied', 'message', 'Ya estaba asignada a ese local.');
    end if;
    insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
    values (v_r.group_id, p_recipe_id, p_restaurant_id, recipes.today());
    return jsonb_build_object('result', 'applied', 'message', 'Receta asignada al local.');
  end if;
  if v_open is null then
    return jsonb_build_object('result', 'applied', 'message', 'No estaba asignada a ese local.');
  end if;
  update recipes.recipe_assignments set valid_to = greatest(valid_from, recipes.today()) where id = v_open;
  return jsonb_build_object('result', 'applied', 'message', 'El local deja de usar la receta.');
end
$$;
comment on function recipes.set_assignment(uuid, uuid, boolean, text) is
  'Asigna una receta a un local (o deja de asignarla), dentro del alcance de la receta. Pide recipes.assign en ese local y un motivo.';

create function recipes.archive_recipe(p_recipe_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r recipes.recipes;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.archive', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.archive_recipe', 'No tenés permiso para archivar esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if exists (select 1 from recipes.recipe_versions where recipe_id = p_recipe_id and status = 'in_review'
               and approval_request_id in (select id from workflow.approval_requests where status = 'pending')) then
    raise exception 'Tiene una versión en revisión: que se decida o se retire antes de archivar.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipes set is_active = false where id = p_recipe_id;
  update recipes.recipe_versions set status = 'archived' where recipe_id = p_recipe_id and status = 'published';
  update recipes.recipe_assignments set valid_to = greatest(valid_from, recipes.today())
   where recipe_id = p_recipe_id and valid_to is null and deleted_at is null;
  return jsonb_build_object('result', 'applied', 'message', 'Receta archivada. Su historia se conserva.');
end
$$;
comment on function recipes.archive_recipe(uuid, text) is
  'Archiva una receta: deja de usarse en las cocinas y conserva toda su historia. Pide recipes.archive y un motivo.';

-- Categorías de recetas: las administra quien escribe recetas para todo el grupo.
create function recipes.create_category(p_group_id uuid, p_name text, p_reason text, p_parent_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id         uuid;
  v_constraint text;
  v_message    text;
begin
  perform org.require(core.has_permission_in_group('recipes.draft', p_group_id), 'crear categorías de recetas en este grupo');
  if nullif(btrim(p_name), '') is null then
    raise exception 'El nombre no puede quedar vacío ni pasar los 80 caracteres.' using errcode = '23514';
  end if;
  if p_parent_id is not null
     and not exists (select 1 from recipes.recipe_categories
                      where id = p_parent_id and group_id = p_group_id and deleted_at is null) then
    raise exception 'Elegí una categoría madre de este grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipe_categories (group_id, parent_id, name) values (p_group_id, p_parent_id, btrim(p_name))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.create_category(uuid, text, text, uuid) is
  'Crea una categoría de recetas, o una subcategoría si se indica la madre. Pide recipes.draft para todo el grupo y un motivo.';

create function recipes.rename_category(p_id uuid, p_name text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group      uuid;
  v_constraint text;
  v_message    text;
begin
  select group_id into v_group from recipes.recipe_categories where id = p_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('recipes.draft', v_group), 'editar esta categoría');
  if nullif(btrim(p_name), '') is null then
    raise exception 'El nombre no puede quedar vacío ni pasar los 80 caracteres.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_categories set name = btrim(p_name) where id = p_id;
exception when unique_violation or check_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.rename_category(uuid, text, text) is
  'Cambia el nombre de una categoría de recetas. Pide recipes.draft para todo el grupo y un motivo.';

create function recipes.archive_category(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group    uuid;
  v_recipes  integer;
  v_children integer;
begin
  select group_id into v_group from recipes.recipe_categories where id = p_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('recipes.draft', v_group), 'editar esta categoría');
  perform 1 from recipes.recipe_categories where id = p_id for update;
  select count(*) into v_recipes from recipes.recipes where category_id = p_id and deleted_at is null;
  if v_recipes = 1 then
    raise exception 'Tiene 1 receta: pasala a otra categoría antes de darla de baja.' using errcode = '23514';
  elsif v_recipes > 1 then
    raise exception 'Tiene % recetas: pasalas a otra categoría antes de darla de baja.', v_recipes using errcode = '23514';
  end if;
  select count(*) into v_children from recipes.recipe_categories where parent_id = p_id and deleted_at is null;
  if v_children = 1 then
    raise exception 'Tiene 1 subcategoría: dala de baja antes.' using errcode = '23514';
  elsif v_children > 1 then
    raise exception 'Tiene % subcategorías: dalas de baja antes.', v_children using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_categories set deleted_at = now() where id = p_id;
end
$$;
comment on function recipes.archive_category(uuid, text) is
  'Da de baja una categoría de recetas (borrado lógico), solo si no tiene recetas ni subcategorías. Pide recipes.draft para todo el grupo y un motivo.';

-- ---------------------------------------------------------------------------
-- 8. Lectura
-- ---------------------------------------------------------------------------
-- Camino crítico: el tiempo total no es la suma de los pasos, sino el camino más largo entre pasos que
-- se esperan. Duración de un paso = minutos activos + pasivos. Caso 22: 20 + máx(60, 30) + 10 = 90.
create function recipes.critical_path(p_version_id uuid)
returns table (total_minutes integer, active_minutes integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_ids     uuid[];
  v_dur     integer[];
  v_finish  integer[];
  v_active  integer;
  v_from    integer[];
  v_to      integer[];
  v_changed boolean := true;
  v_rounds  integer := 0;
  k         integer;
begin
  select array_agg(st.id order by st.step_number), array_agg(st.active_minutes + st.passive_minutes order by st.step_number),
         sum(st.active_minutes)
    into v_ids, v_dur, v_active
    from recipes.recipe_steps st
   where st.recipe_version_id = p_version_id and st.deleted_at is null;
  if v_ids is null then
    return query select 0, 0;
    return;
  end if;
  select array_agg(array_position(v_ids, d.step_id)), array_agg(array_position(v_ids, d.depends_on_step_id))
    into v_from, v_to
    from recipes.recipe_step_dependencies d
   where d.deleted_at is null and d.step_id = any (v_ids) and d.depends_on_step_id = any (v_ids);
  v_finish := v_dur;
  -- El fin de un paso es su duración más el mayor fin de los pasos que espera. Sin ciclos (trigger), se
  -- estabiliza en a lo sumo tantas vueltas como pasos: pasos × dependencias, nunca exponencial.
  while v_changed and v_from is not null and v_rounds <= array_length(v_ids, 1) loop
    v_changed := false;
    v_rounds := v_rounds + 1;
    for k in 1 .. array_length(v_from, 1) loop
      if v_finish[v_from[k]] < v_dur[v_from[k]] + v_finish[v_to[k]] then
        v_finish[v_from[k]] := v_dur[v_from[k]] + v_finish[v_to[k]];
        v_changed := true;
      end if;
    end loop;
  end loop;
  return query select (select max(x) from unnest(v_finish) x)::integer, coalesce(v_active, 0)::integer;
end
$$;
comment on function recipes.critical_path(uuid) is
  'Tiempo total de una versión por camino crítico (los pasos en paralelo no se suman) y la suma de los minutos activos. Respeta RLS.';

-- Alérgenos de una versión: por cada alérgeno del grupo, el peor estado entre sus materias primas.
-- Si alguna no tiene dato, "no verificado": nunca "sin alérgenos" por falta de datos.
create function recipes.version_allergens(p_version_id uuid)
returns table (allergen_id uuid, code text, name text, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not recipes.can_see_version(p_version_id) then
    return;
  end if;
  return query
  select a.id, a.code, a.name,
         case when bool_or(ia.status = 'contains') then 'contains'
              when bool_or(ia.status = 'may_contain') then 'may_contain'
              when count(c.id) > 0 and count(c.id) = count(*) filter (where ia.status = 'free_verified') then 'free_verified'
              else 'not_verified' end
    from recipes.recipe_versions v
    join catalog.allergens a on a.group_id = v.group_id and a.deleted_at is null
    left join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null
    left join catalog.ingredient_allergens ia
      on ia.ingredient_id = c.ingredient_id and ia.allergen_id = a.id and ia.deleted_at is null
   where v.id = p_version_id
   group by a.id, a.code, a.name
   order by a.name;
end
$$;
comment on function recipes.version_allergens(uuid) is
  'Alérgenos de una versión: contains, may_contain, free_verified (todas sus materias primas verificadas) o not_verified (alguna sin dato). Vacío si la sesión no ve la versión.';

-- La ficha de cocina: la versión vigente, sin ningún valor económico (caso 24). Con permisos propios
-- porque el cocinero no ve el catálogo, pero controla ella misma que la sesión vea la receta.
create function recipes.kitchen_card(p_recipe_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r     recipes.recipes;
  v_v     recipes.recipe_versions;
  v_total integer;
  v_act   integer;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null;
  if v_r.id is null or not recipes.can_view_recipe(v_r.id) then
    return null;
  end if;
  select * into v_v from recipes.recipe_versions where recipe_id = p_recipe_id and status = 'published';
  if v_v.id is null then
    return null;
  end if;
  select c.total_minutes, c.active_minutes into v_total, v_act from recipes.critical_path(v_v.id) c;
  return jsonb_build_object(
    'recipe_id', v_r.id, 'code', v_r.code, 'name', v_r.name, 'short_name', v_r.short_name,
    'recipe_type', v_r.recipe_type, 'version_number', v_v.version_number, 'published_at', v_v.published_at,
    'yield_quantity', v_v.yield_quantity, 'yield_unit', (select u.name from catalog.units u where u.id = v_v.yield_unit_id),
    'portions', v_v.portions, 'portion_grams', v_v.portion_grams, 'description', v_v.description,
    'storage_notes', v_v.storage_notes, 'presentation_notes', v_v.presentation_notes,
    'total_minutes', v_total, 'active_minutes', v_act,
    'components', coalesce((
      select jsonb_agg(jsonb_build_object('line', c.line_order, 'ingredient', i.name, 'quantity', c.quantity, 'unit', u.name,
                                          'basis', c.quantity_basis, 'notes', c.notes) order by c.line_order)
        from recipes.recipe_components c
        join catalog.ingredients i on i.id = c.ingredient_id
        join catalog.units u on u.id = c.unit_id
       where c.recipe_version_id = v_v.id and c.deleted_at is null), '[]'),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
               'number', s.step_number, 'kind', s.kind, 'instructions', s.instructions,
               'active_minutes', s.active_minutes, 'passive_minutes', s.passive_minutes, 'equipment', s.equipment,
               'control_point', s.control_point,
               'depends_on', coalesce((select jsonb_agg(o.step_number order by o.step_number)
                                         from recipes.recipe_step_dependencies d
                                         join recipes.recipe_steps o on o.id = d.depends_on_step_id
                                        where d.step_id = s.id and d.deleted_at is null), '[]'))
             order by s.step_number)
        from recipes.recipe_steps s
       where s.recipe_version_id = v_v.id and s.deleted_at is null), '[]'),
    'allergens', coalesce((select jsonb_agg(jsonb_build_object('name', a.name, 'status', a.status))
                             from recipes.version_allergens(v_v.id) a), '[]'));
end
$$;
comment on function recipes.kitchen_card(uuid) is
  'Ficha de cocina de la versión vigente: componentes, pasos, tiempos y alérgenos, sin ningún valor económico. Vacío si la sesión no ve la receta o no hay versión vigente.';

-- Dónde se usa una materia prima: recetas vigentes o en preparación que la tienen.
create function catalog.ingredient_usage(p_ingredient_id uuid)
returns table (recipe_id uuid, code text, name text, version_number integer, status core.version_status)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct on (r.id) r.id, r.code, r.name, v.version_number, v.status
    from recipes.recipe_components c
    join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status in ('published', 'draft', 'in_review')
    join recipes.recipes r on r.id = v.recipe_id
   where c.ingredient_id = p_ingredient_id and c.deleted_at is null
   order by r.id, (v.status = 'published') desc, v.version_number desc
$$;
comment on function catalog.ingredient_usage(uuid) is
  'Recetas (vigentes o en preparación) que usan una materia prima, entre las que ve la sesión.';

-- ---------------------------------------------------------------------------
-- 9. Aprobación: las aprobaciones pueden aplicar cambios en recipes
-- ---------------------------------------------------------------------------
-- Misma regla que la versión de 20261030120000_catalog_yields.sql, con recipes en la lista de esquemas.
create or replace function workflow.check_apply_function()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
       select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where p.oid = new.apply_function::oid and n.nspname in ('core', 'org', 'catalog', 'recipes') and p.proname like 'apply\_%'
          and p.pronargs = 1 and p.proargtypes[0] = 'uuid'::regtype and p.prorettype = 'void'::regtype) then
    raise exception 'La función que aplica una aprobación tiene que ser una de las funciones apply_* de core, org, catalog o recipes.'
      using errcode = '42501';
  end if;
  -- Quién aprueba: un permiso y roles que existen (un error de tipeo dejaría todo sin aprobar,
  -- y vaciar los roles exigidos abriría la aprobación a cualquiera con el permiso).
  if not exists (select 1 from core.permissions p where p.code = new.required_permission and p.deleted_at is null) then
    raise exception 'El permiso para aprobar % no existe.', new.required_permission using errcode = '23514';
  end if;
  if exists (select 1 from unnest(coalesce(new.approver_role_codes, '{}')) c
              where not exists (select 1 from core.roles r where r.code = c and r.deleted_at is null)) then
    raise exception 'Algún rol exigido para aprobar no existe.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and cardinality(coalesce(old.approver_role_codes, '{}')) > cardinality(coalesce(new.approver_role_codes, '{}')) then
    raise exception 'Los roles exigidos para aprobar no se quitan con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  -- Dejar que alguien se apruebe lo propio, o pedir menos aprobaciones, tampoco se hace con una edición.
  -- Un tipo nuevo nace sin autoaprobación (revisión de seguridad, m1): habilitarla pide cambiar esta regla.
  if tg_op = 'INSERT' and new.allow_self_approval then
    raise exception 'Un tipo de aprobación nuevo no permite aprobarse lo propio: hace falta una migración documentada que cambie esta regla.'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and ((new.allow_self_approval and not old.allow_self_approval) or new.min_approvers < old.min_approvers) then
    raise exception 'Permitir la autoaprobación o pedir menos aprobaciones no se hace con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  return new;
end
$$;

do $$
begin
  perform core.set_change_context('Aprobación de versiones de receta (Fase 2, etapa 2.2 A)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, min_approvers, apply_function,
                                           entity_table)
  values ('recipes.publish_version', 'Versión de receta',
          'Publicar una versión de receta: al aprobarla queda vigente en las cocinas y la anterior pasa a archivada. La aprueba alguien con recipes.publish en el alcance de la receta, distinto de quien pidió la revisión.',
          'recipes.publish', 1, 'recipes.apply_publish_version(uuid)'::regprocedure, 'recipes.recipe_versions');
end
$$;

-- ---------------------------------------------------------------------------
-- 10. Permisos de ejecución
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'recipes.viewable_recipe_ids()',
    'recipes.workable_recipe_ids()',
    'recipes.visible_version_ids()',
    'recipes.create_recipe(uuid, uuid, uuid, text, text, recipes.recipe_type, uuid, text)',
    'recipes.update_recipe(uuid, jsonb, text)',
    'recipes.new_version(uuid, text)',
    'recipes.save_draft(uuid, jsonb, text, timestamptz)',
    'recipes.set_components(uuid, jsonb, text, timestamptz)',
    'recipes.set_steps(uuid, jsonb, text, timestamptz)',
    'recipes.version_diff(uuid)',
    'recipes.request_review(uuid, text)',
    'recipes.withdraw_review(uuid, text)',
    'recipes.set_assignment(uuid, uuid, boolean, text)',
    'recipes.archive_recipe(uuid, text)',
    'recipes.create_category(uuid, text, text, uuid)',
    'recipes.rename_category(uuid, text, text)',
    'recipes.archive_category(uuid, text)',
    'recipes.critical_path(uuid)',
    'recipes.version_allergens(uuid)',
    'recipes.kitchen_card(uuid)',
    'catalog.ingredient_usage(uuid)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
