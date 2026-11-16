-- Fase 3, Prompt 2 (ADR-0052): artículos de proveedor, cola de mapeo y listas de precios.
--
-- 1. Un artículo de proveedor es un producto de compra (catalog.purchase_products) con su proveedor y el código del
--    proveedor. Lo que llega y el sistema no reconoce va a una cola (purchasing.unmapped_articles) que resuelve el chef,
--    una sola vez; si el proveedor le cambia el nombre, se vincula al que ya existe (purchasing.article_aliases).
-- 2. Los rubros de compra de primer nivel dicen si van a recetas (P2, decisión 6 de Soy): Limpieza y Descartables no.
-- 3. Compras carga y acepta listas de precios (purchasing.price_lists y price_list_items), con histórico y aviso
--    cuando una lista vence según la frecuencia de la ficha del proveedor. Los precios de lista nunca son costos: no se
--    escribe nada en costing.price_records.
-- 4. Los archivos (la lista escaneada) van al bucket purchasing-documents y quedan registrados en
--    purchasing.attachments, que es solo de inserción.

-- ---------------------------------------------------------------------------
-- 1. Permisos
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de listas de precios y mapeo de artículos (Fase 3, ADR-0052)',
                                  'maintenance');
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('purchasing.view_price_lists', 'purchasing', 'view_price_lists', 'Ver listas de precios', 40,
     'Ver las listas de precios de los proveedores, sus artículos, precios, bonificaciones y la variación entre listas.',
     false),
    ('purchasing.manage_price_lists', 'purchasing', 'manage_price_lists', 'Cargar y aceptar listas de precios', 50,
     'Cargar listas de precios de los proveedores, con su archivo, y aceptarlas. Una lista aceptada reemplaza a la anterior.',
     true),
    ('catalog.map_articles', 'catalog', 'map_articles', 'Mapear artículos de proveedor', 60,
     'Resolver la cola de artículos sin mapear: decir a qué materia prima corresponde un artículo nuevo de un proveedor, con su envase, o que es el mismo que otro ya cargado.',
     false);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values
      -- Superadmin: los permisos de quienes puede suspender o desactivar (regla G2, como en ADR-0050).
      ('superadmin', 'purchasing.view_price_lists'), ('superadmin', 'purchasing.manage_price_lists'),
      ('superadmin', 'catalog.map_articles'),
      ('purchasing', 'purchasing.view_price_lists'), ('purchasing', 'purchasing.manage_price_lists'),
      ('controller', 'purchasing.view_price_lists'),
      ('general_management', 'purchasing.view_price_lists'),
      ('brand_director', 'purchasing.view_price_lists'),
      ('restaurant_manager', 'purchasing.view_price_lists'),
      ('auditor', 'purchasing.view_price_lists'),
      ('executive_chef', 'catalog.map_articles'),
      ('head_chef', 'catalog.map_articles'),
      -- Regla G2: quien administra a los chefs (Director de Marca y Gerente) tiene los permisos de los roles que
      -- administra. Con eso también pueden resolver la cola (decisión de Joaco del 2026-11-16: mapea cualquier alcance).
      ('brand_director', 'catalog.map_articles'),
      ('restaurant_manager', 'catalog.map_articles')
    ) as v (role_code, permission_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = v.permission_code and p.deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Rubros que no van a recetas
-- ---------------------------------------------------------------------------
alter table catalog.ingredient_categories
  add column used_in_recipes boolean not null default true;
comment on column catalog.ingredient_categories.used_in_recipes is
  'Si las materias primas del rubro se pueden usar en recetas (Limpieza o Descartables, no). Se define en el rubro de primer nivel; las subcategorías lo heredan y su propio valor no se usa.';

update catalog.ingredient_categories
   set used_in_recipes = false
 where parent_id is null and code in ('MP-LIM', 'MP-DES') and deleted_at is null;

-- Los rubros que se crean después (un grupo nuevo, o el seed con recipes.install_default_categories) nacen igual.
create function catalog.default_used_in_recipes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.parent_id is null and new.code in ('MP-LIM', 'MP-DES') then
    new.used_in_recipes := false;
  end if;
  return new;
end
$$;
comment on function catalog.default_used_in_recipes() is
  'Interna: un rubro de compra nuevo de Limpieza (MP-LIM) o Descartables y packaging (MP-DES) nace como «no va a recetas» (decisión 6 de Soy). Después se puede cambiar desde Rubros.';
revoke execute on function catalog.default_used_in_recipes() from public;
create trigger default_used_in_recipes before insert on catalog.ingredient_categories
  for each row execute function catalog.default_used_in_recipes();

-- Si una materia prima va a recetas: lo dice su rubro de primer nivel. Sin rubro, sí.
create function catalog.ingredient_used_in_recipes(p_ingredient_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select coalesce(top.used_in_recipes, c.used_in_recipes)
      from catalog.ingredients i
      join catalog.ingredient_categories c on c.id = i.category_id
      left join catalog.ingredient_categories top on top.id = c.parent_id
     where i.id = p_ingredient_id), true)
$$;
comment on function catalog.ingredient_used_in_recipes(uuid) is
  'Interna: si la materia prima se puede usar en recetas, según su rubro de primer nivel (sin rubro, sí).';
revoke execute on function catalog.ingredient_used_in_recipes(uuid) from public;

-- Una línea nueva (o con la materia prima cambiada) no puede usar una materia prima de un rubro que no va a recetas.
-- Lo que la receta ya tenía no se toca: una versión nueva copia sus líneas y la materia prima ya estaba en la receta.
create function recipes.guard_used_in_recipes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.ingredient_id is not distinct from old.ingredient_id then
    return new;
  end if;
  if catalog.ingredient_used_in_recipes(new.ingredient_id) then
    return new;
  end if;
  -- La receta (o su maestra, si es una variante) ya la usaba en alguna versión: una versión nueva o una variante la
  -- copian y siguen.
  if exists (select 1
               from recipes.recipe_versions nv
               join recipes.recipes r on r.id = nv.recipe_id
               join recipes.recipe_versions v on v.recipe_id in (r.id, r.variant_of_recipe_id)
               join recipes.recipe_components rc on rc.recipe_version_id = v.id
              where nv.id = new.recipe_version_id
                and rc.ingredient_id = new.ingredient_id and rc.id <> new.id and rc.deleted_at is null) then
    return new;
  end if;
  raise exception 'Esa materia prima es de un rubro que no va a recetas (por ejemplo, Limpieza o Descartables).'
    using errcode = '23514', constraint = 'recipe_components_used_in_recipes';
end
$$;
comment on function recipes.guard_used_in_recipes() is
  'Rechaza una línea de receta nueva, o con la materia prima cambiada, con una materia prima de un rubro que no va a recetas. Lo que la receta (o su maestra) ya usaba sigue: sus versiones nuevas y sus variantes lo copian.';
revoke execute on function recipes.guard_used_in_recipes() from public;
create trigger guard_used_in_recipes before insert or update of ingredient_id on recipes.recipe_components
  for each row execute function recipes.guard_used_in_recipes();

-- El buscador de componentes no ofrece las materias primas que no van a recetas.
create or replace function catalog.search_components(p_query text, p_limit integer default 20)
returns table (kind text, id uuid, code text, name text, unit text, matched text, score real)
language sql
stable
set search_path = ''
as $$
  -- % y _ se buscan como letras, no como comodines.
  with q as (select lower(btrim(p_query)) as t,
                    replace(replace(replace(lower(btrim(p_query)), '\', '\\'), '%', '\%'), '_', '\_') as e)
  select 'ingredient'::text, i.id, i.code, i.name, u.name,
         coalesce(a.alias, i.name),
         greatest(extensions.similarity(lower(i.name), q.t),
                  coalesce(extensions.similarity(a.alias, q.t), 0),
                  case when lower(i.code) like q.e || '%' then 1 else 0 end)::real as score
    from q, catalog.ingredients i
    join catalog.units u on u.id = i.recipe_unit_id
    left join catalog.ingredient_categories c on c.id = i.category_id
    left join catalog.ingredient_categories top on top.id = c.parent_id
    left join lateral (
      select al.alias from catalog.ingredient_aliases al
       where al.ingredient_id = i.id and al.deleted_at is null and al.alias like '%' || (select e from q) || '%'
       order by length(al.alias) limit 1) a on true
   where length(q.t) >= 3
     and i.is_active
     and i.deleted_at is null
     and coalesce(top.used_in_recipes, c.used_in_recipes, true)
     and (lower(i.name) like '%' || q.e || '%'
          or lower(i.code) like q.e || '%'
          or a.alias is not null
          or extensions.similarity(lower(i.name), q.t) > 0.3)
   order by score desc, i.name
   limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- El panel de Rubros suma la columna «va a recetas» (solo cuenta en los de compra).
drop function recipes.category_overview(uuid);
create function recipes.category_overview(p_group_id uuid)
returns table (category_class recipes.category_class, id uuid, code text, name text, is_active boolean,
               uses bigint, mismatched bigint, used_in_recipes boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  with ing as (
    select coalesce(c.parent_id, c.id) as top_id, count(*) as uses
      from catalog.ingredients i
      join catalog.ingredient_categories c on c.id = i.category_id
     where i.group_id = p_group_id and i.deleted_at is null
     group by 1),
  rec as (
    select coalesce(c.parent_id, c.id) as top_id, count(*) as uses,
           count(*) filter (where (r.recipe_type = 'dish') <> (c.kind = 'menu')) as mismatched
      from recipes.recipes r
      join recipes.recipe_categories c on c.id = r.category_id
     where r.group_id = p_group_id and r.deleted_at is null
     group by 1)
  select 'purchase'::recipes.category_class, c.id, c.code, c.name, c.is_active, coalesce(ing.uses, 0), 0::bigint,
         c.used_in_recipes
    from catalog.ingredient_categories c
    left join ing on ing.top_id = c.id
   where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
  union all
  select c.kind, c.id, c.code, c.name, c.is_active, coalesce(rec.uses, 0), coalesce(rec.mismatched, 0), true
    from recipes.recipe_categories c
    left join rec on rec.top_id = c.id
   where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
$$;
comment on function recipes.category_overview(uuid) is
  'Panel de Rubros: cada rubro del grupo con su clase, código, nombre, si está activo, cuántos usos tiene (materias primas o recetas, sumando subcategorías), cuántas recetas están en un rubro de la otra clase y si va a recetas (solo en los de compra; los demás, sí). Con los permisos de quien consulta.';
revoke execute on function recipes.category_overview(uuid) from public;
grant execute on function recipes.category_overview(uuid) to authenticated;

-- Sí/no de un clic desde Rubros: Compras o Dirección, con motivo (los mismos que administran los rubros de compra).
create function recipes.set_category_used_in_recipes(p_id uuid, p_value boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  -- El grupo se busca acá (y no con recipes.top_category_group, que corta con error): así el rechazo queda registrado.
  select group_id into v_group from catalog.ingredient_categories
   where id = p_id and parent_id is null and deleted_at is null;
  if v_group is null or not recipes.can_manage_category('purchase', v_group) then
    return core.deny('recipes.set_category_used_in_recipes', 'No tenés permiso para cambiar este rubro.', null,
                     jsonb_build_object('category_id', p_id), v_group);
  end if;
  if p_value is null then
    raise exception 'Elegí si va a recetas.' using errcode = '22023';
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo del cambio.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredient_categories set used_in_recipes = p_value
   where id = p_id and used_in_recipes is distinct from p_value;
  return jsonb_build_object('result', 'applied');
end
$$;
comment on function recipes.set_category_used_in_recipes(uuid, boolean, text) is
  'Dice si un rubro de compra de primer nivel va a recetas. Lo cambian Compras (catalog.manage) o Dirección (prices.configure), con motivo. Las recetas que ya lo usaban no se tocan.';
revoke execute on function recipes.set_category_used_in_recipes(uuid, boolean, text) from public;
grant execute on function recipes.set_category_used_in_recipes(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Artículo de proveedor = producto de compra
-- ---------------------------------------------------------------------------
-- Nombre para comparar: mayúsculas, sin acentos, sin puntos ni espacios de más («Harina 000 x 25 kg.» y
-- «HARINA  000 X 25 KG» son el mismo).
create function purchasing.normalize_name(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(
    translate(upper(coalesce(p_name, '')), 'ÁÉÍÓÚÜÑÀÈÌÒÙÂÊÎÔÛÄËÏÖ.,;:', 'AEIOUUNAEIOUAEIOUAEIO    '),
    '\s+', ' ', 'g')), '')
$$;
comment on function purchasing.normalize_name(text) is
  'El nombre de un artículo para compararlo: mayúsculas, sin acentos, sin puntos ni comas, con un solo espacio entre palabras. Vacío si no queda nada.';
grant execute on function purchasing.normalize_name(text) to authenticated;

-- El código de un proveedor: sin espacios y en mayúsculas.
create function purchasing.normalize_sku(p_sku text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(upper(regexp_replace(coalesce(p_sku, ''), '\s+', '', 'g')), '')
$$;
comment on function purchasing.normalize_sku(text) is
  'El código de un artículo del proveedor para compararlo: sin espacios y en mayúsculas. Vacío si no hay.';
grant execute on function purchasing.normalize_sku(text) to authenticated;

alter table catalog.purchase_products
  add column supplier_sku               text,
  add column billed_by_weight           boolean not null default false,
  add column estimated_weight_per_unit  numeric(18,6),
  add constraint purchase_products_supplier_sku_check check (
    supplier_sku is null or (supplier_sku = purchasing.normalize_sku(supplier_sku) and length(supplier_sku) <= 40)),
  add constraint purchase_products_sku_needs_supplier_check check (supplier_sku is null or supplier_id is not null),
  add constraint purchase_products_weight_check check (
    (estimated_weight_per_unit is null or estimated_weight_per_unit > 0)
    and (estimated_weight_per_unit is null or billed_by_weight));
create unique index purchase_products_supplier_sku_key on catalog.purchase_products (supplier_id, supplier_sku)
  where deleted_at is null and supplier_sku is not null;
create index purchase_products_supplier_name_idx on catalog.purchase_products
  (supplier_id, purchasing.normalize_name(description)) where deleted_at is null and supplier_id is not null;
comment on column catalog.purchase_products.supplier_sku is
  'Código del artículo en el proveedor (sin espacios, en mayúsculas). Único por proveedor entre los vigentes. Es lo primero que se mira para reconocer un renglón de lista o de factura.';
comment on column catalog.purchase_products.billed_by_weight is
  'Si el proveedor lo factura por peso real (se pide por unidad y se cobra por kilo, como la carne o el queso en horma).';
comment on column catalog.purchase_products.estimated_weight_per_unit is
  'Peso estimado de cada unidad, en la unidad de contenido del producto. Solo si se factura por peso; sirve para estimar la orden de compra.';

-- Otros nombres o códigos con los que el proveedor manda un producto (lo deja «Es el mismo que…»).
create table purchasing.article_aliases (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  supplier_id          uuid not null,
  purchase_product_id  uuid not null,
  raw_name             text not null check (length(btrim(raw_name)) between 1 and 200),
  normalized_name      text not null generated always as (purchasing.normalize_name(raw_name)) stored,
  supplier_sku         text check (supplier_sku is null or (supplier_sku = purchasing.normalize_sku(supplier_sku)
                                                            and length(supplier_sku) <= 40)),
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict,
  constraint article_aliases_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint article_aliases_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict
);
create unique index article_aliases_name_key on purchasing.article_aliases (supplier_id, normalized_name)
  where deleted_at is null;
create unique index article_aliases_sku_key on purchasing.article_aliases (supplier_id, supplier_sku)
  where deleted_at is null and supplier_sku is not null;
create index article_aliases_product_idx on purchasing.article_aliases (purchase_product_id, group_id);
create index article_aliases_supplier_idx on purchasing.article_aliases (supplier_id, group_id);
create index article_aliases_group_idx on purchasing.article_aliases (group_id);
comment on table purchasing.article_aliases is
  'Otros nombres o códigos con los que un proveedor manda un producto de compra (por ejemplo, porque lo renombró). Se reconocen igual que el nombre y el código del producto, y la historia no se pierde.';
comment on column purchasing.article_aliases.group_id is 'Grupo, el mismo que el del proveedor y el del producto.';
comment on column purchasing.article_aliases.supplier_id is 'Proveedor que usa este nombre.';
comment on column purchasing.article_aliases.purchase_product_id is 'Producto de compra al que corresponde.';
comment on column purchasing.article_aliases.raw_name is 'El nombre tal como lo manda el proveedor.';
comment on column purchasing.article_aliases.normalized_name is 'El nombre para comparar (lo calcula la base).';
comment on column purchasing.article_aliases.supplier_sku is 'El código con el que lo manda, si trae.';

-- Reconocer un artículo: primero por proveedor y código; si no, por proveedor y nombre. Mira el producto y sus otros
-- nombres. Vacío si no lo reconoce (va a la cola).
create function purchasing.match_article(p_supplier_id uuid, p_sku text, p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with k as (select purchasing.normalize_sku(p_sku) as sku, purchasing.normalize_name(p_name) as name)
  select coalesce(
    (select p.id from k, catalog.purchase_products p
      where k.sku is not null and p.supplier_id = p_supplier_id and p.supplier_sku = k.sku
        and p.deleted_at is null and p.is_active limit 1),
    (select a.purchase_product_id from k, purchasing.article_aliases a
       join catalog.purchase_products p on p.id = a.purchase_product_id and p.deleted_at is null and p.is_active
      where k.sku is not null and a.supplier_id = p_supplier_id and a.supplier_sku = k.sku and a.deleted_at is null
      limit 1),
    (select p.id from k, catalog.purchase_products p
      where k.name is not null and p.supplier_id = p_supplier_id
        and purchasing.normalize_name(p.description) = k.name and p.deleted_at is null and p.is_active
      order by p.created_at limit 1),
    (select a.purchase_product_id from k, purchasing.article_aliases a
       join catalog.purchase_products p on p.id = a.purchase_product_id and p.deleted_at is null and p.is_active
      where k.name is not null and a.supplier_id = p_supplier_id and a.normalized_name = k.name
        and a.deleted_at is null limit 1))
$$;
comment on function purchasing.match_article(uuid, text, text) is
  'Interna: el producto de compra de un proveedor que corresponde a un renglón (primero por código del proveedor, después por nombre normalizado, en el producto o en sus otros nombres). Vacío si no lo reconoce.';
revoke execute on function purchasing.match_article(uuid, text, text) from public;

-- ---------------------------------------------------------------------------
-- 4. Cola de mapeo
-- ---------------------------------------------------------------------------
create type purchasing.article_source as enum ('price_list', 'invoice', 'receipt');
comment on type purchasing.article_source is
  'Dónde apareció un artículo sin mapear: price_list (lista de precios), invoice (factura) o receipt (recepción).';
create type purchasing.unmapped_status as enum ('pending', 'resolved', 'discarded');
comment on type purchasing.unmapped_status is
  'Estado de un artículo sin mapear: pending (espera al chef), resolved (ya es un producto de compra) o discarded (no se usa).';

create table purchasing.unmapped_articles (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references org.groups (id) on delete restrict,
  supplier_id           uuid not null,
  raw_name              text not null check (length(btrim(raw_name)) between 1 and 200),
  normalized_name       text not null generated always as (purchasing.normalize_name(raw_name)) stored,
  supplier_sku          text check (supplier_sku is null or (supplier_sku = purchasing.normalize_sku(supplier_sku)
                                                             and length(supplier_sku) <= 40)),
  package_hint          text check (package_hint is null or length(btrim(package_hint)) between 1 and 80),
  found_in              purchasing.article_source not null,
  source_id             uuid,
  status                purchasing.unmapped_status not null default 'pending',
  purchase_product_id   uuid,
  resolved_at           timestamptz,
  resolved_by           uuid references core.actors (id) on delete restrict,
  created_at            timestamptz not null default now(),
  created_by            uuid references core.actors (id) on delete restrict,
  updated_at            timestamptz not null default now(),
  updated_by            uuid references core.actors (id) on delete restrict,
  deleted_at            timestamptz,
  deleted_by            uuid references core.actors (id) on delete restrict,
  constraint unmapped_articles_id_group_key unique (id, group_id),
  constraint unmapped_articles_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint unmapped_articles_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict,
  constraint unmapped_articles_status_check check (
    (status = 'pending' and purchase_product_id is null and resolved_at is null)
    or (status = 'resolved' and purchase_product_id is not null and resolved_at is not null)
    or (status = 'discarded' and purchase_product_id is null and resolved_at is not null))
);
create unique index unmapped_articles_pending_key on purchasing.unmapped_articles (supplier_id, normalized_name)
  where status = 'pending' and deleted_at is null;
create index unmapped_articles_status_idx on purchasing.unmapped_articles (group_id, status, created_at)
  where deleted_at is null;
create index unmapped_articles_supplier_idx on purchasing.unmapped_articles (supplier_id, group_id);
create index unmapped_articles_source_idx on purchasing.unmapped_articles (source_id) where source_id is not null;
create index unmapped_articles_product_idx on purchasing.unmapped_articles (purchase_product_id, group_id)
  where purchase_product_id is not null;
comment on table purchasing.unmapped_articles is
  'Cola de mapeo: artículos de proveedor que llegaron en una lista, factura o recepción y el sistema no reconoce. El chef dice a qué materia prima corresponden (se crea el producto de compra), que son el mismo que otro, o los descarta. Una sola vez: después se reconocen solos.';
comment on column purchasing.unmapped_articles.group_id is 'Grupo, el mismo que el del proveedor.';
comment on column purchasing.unmapped_articles.supplier_id is 'Proveedor que lo mandó.';
comment on column purchasing.unmapped_articles.raw_name is 'El nombre tal como vino.';
comment on column purchasing.unmapped_articles.normalized_name is
  'El nombre para comparar (lo calcula la base). Un solo pendiente por proveedor y nombre.';
comment on column purchasing.unmapped_articles.supplier_sku is 'El código del proveedor, si vino.';
comment on column purchasing.unmapped_articles.package_hint is 'Pista del envase que vino con el renglón («x 25 kg», «caja x 12»).';
comment on column purchasing.unmapped_articles.found_in is 'Dónde apareció por primera vez.';
comment on column purchasing.unmapped_articles.source_id is 'El registro donde apareció (la lista, la factura o la recepción).';
comment on column purchasing.unmapped_articles.status is 'Pendiente, resuelto o descartado.';
comment on column purchasing.unmapped_articles.purchase_product_id is 'El producto de compra que quedó, si se resolvió.';
comment on column purchasing.unmapped_articles.resolved_at is 'Cuándo se resolvió o descartó.';
comment on column purchasing.unmapped_articles.resolved_by is 'Quién lo resolvió o descartó.';

-- ---------------------------------------------------------------------------
-- 5. Listas de precios
-- ---------------------------------------------------------------------------
create type purchasing.price_list_status as enum ('received', 'accepted', 'replaced');
comment on type purchasing.price_list_status is
  'Estado de una lista de precios: received (cargada, sin aceptar), accepted (la vigente del proveedor) o replaced (la reemplazó una aceptada después). «Vencida» no es un estado: se calcula con la frecuencia del proveedor.';

create table purchasing.price_lists (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  supplier_id          uuid not null,
  received_on          date not null,
  valid_from           date not null,
  status               purchasing.price_list_status not null default 'received',
  accepted_at          timestamptz,
  accepted_by          uuid references core.actors (id) on delete restrict,
  notes                text check (notes is null or length(notes) <= 1000),
  expired_notified_at  timestamptz,
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict,
  constraint price_lists_id_group_key unique (id, group_id),
  constraint price_lists_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint price_lists_accepted_check check (
    (status = 'received' and accepted_at is null and accepted_by is null)
    or (status <> 'received' and accepted_at is not null)),
  constraint price_lists_dates_check check (valid_from >= received_on - 31 and valid_from <= received_on + 92)
);
create unique index price_lists_accepted_key on purchasing.price_lists (supplier_id)
  where status = 'accepted' and deleted_at is null;
create index price_lists_supplier_idx on purchasing.price_lists (supplier_id, group_id, valid_from desc)
  where deleted_at is null;
create index price_lists_supplier_fk_idx on purchasing.price_lists (supplier_id, group_id);
create index price_lists_group_status_idx on purchasing.price_lists (group_id, status, received_on desc)
  where deleted_at is null;
comment on table purchasing.price_lists is
  'Listas de precios de los proveedores, con su histórico. Compras las carga y las acepta; una sola aceptada por proveedor. Los precios de lista nunca son costos (no tocan costing.price_records).';
comment on column purchasing.price_lists.group_id is 'Grupo, el mismo que el del proveedor.';
comment on column purchasing.price_lists.supplier_id is 'Proveedor.';
comment on column purchasing.price_lists.received_on is 'Cuándo llegó la lista.';
comment on column purchasing.price_lists.valid_from is 'Desde cuándo valen sus precios. El vencimiento se cuenta desde acá.';
comment on column purchasing.price_lists.status is 'Recibida, aceptada (la vigente) o reemplazada.';
comment on column purchasing.price_lists.accepted_at is 'Cuándo se aceptó.';
comment on column purchasing.price_lists.accepted_by is 'Quién la aceptó.';
comment on column purchasing.price_lists.notes is 'Observaciones de Compras.';
comment on column purchasing.price_lists.expired_notified_at is
  'Cuándo se avisó a Compras que venció (una sola vez por lista).';

create table purchasing.price_list_items (
  id                     uuid primary key default gen_random_uuid(),
  group_id               uuid not null references org.groups (id) on delete restrict,
  price_list_id          uuid not null,
  line_order             integer not null check (line_order between 1 and 2000),
  purchase_product_id    uuid,
  unmapped_article_id    uuid,
  raw_name               text not null check (length(btrim(raw_name)) between 1 and 200),
  supplier_sku           text check (supplier_sku is null or (supplier_sku = purchasing.normalize_sku(supplier_sku)
                                                              and length(supplier_sku) <= 40)),
  list_price             numeric(14,4) not null check (list_price > 0),
  currency               char(3) not null default 'ARS' check (currency = 'ARS'),
  bonus1_pct             numeric(7,4) not null default 0 check (bonus1_pct >= 0 and bonus1_pct < 100),
  bonus2_pct             numeric(7,4) not null default 0 check (bonus2_pct >= 0 and bonus2_pct < 100),
  bonus_per_unit_amount  numeric(14,4) not null default 0 check (bonus_per_unit_amount >= 0),
  vat_rate               numeric(5,2) not null check (vat_rate in (0, 2.5, 5, 10.5, 21, 27)),
  includes_vat           boolean not null default false,
  created_at             timestamptz not null default now(),
  created_by             uuid references core.actors (id) on delete restrict,
  updated_at             timestamptz not null default now(),
  updated_by             uuid references core.actors (id) on delete restrict,
  deleted_at             timestamptz,
  deleted_by             uuid references core.actors (id) on delete restrict,
  constraint price_list_items_list_fkey foreign key (price_list_id, group_id)
    references purchasing.price_lists (id, group_id) on delete restrict,
  constraint price_list_items_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict,
  constraint price_list_items_unmapped_fkey foreign key (unmapped_article_id, group_id)
    references purchasing.unmapped_articles (id, group_id) on delete restrict,
  constraint price_list_items_target_check check (num_nonnulls(purchase_product_id, unmapped_article_id) = 1),
  constraint price_list_items_net_check check (
    list_price * (1 - bonus1_pct / 100) * (1 - bonus2_pct / 100) - bonus_per_unit_amount > 0)
);
create unique index price_list_items_order_key on purchasing.price_list_items (price_list_id, line_order)
  where deleted_at is null;
create index price_list_items_list_idx on purchasing.price_list_items (price_list_id, group_id);
-- El mismo producto va una vez por lista: si no, la variación contra la anterior queda ambigua.
create unique index price_list_items_product_key on purchasing.price_list_items (price_list_id, purchase_product_id)
  where deleted_at is null and purchase_product_id is not null;
create index price_list_items_product_idx on purchasing.price_list_items (purchase_product_id, group_id)
  where purchase_product_id is not null;
create index price_list_items_unmapped_idx on purchasing.price_list_items (unmapped_article_id, group_id)
  where unmapped_article_id is not null;
create index price_list_items_group_idx on purchasing.price_list_items (group_id);
comment on table purchasing.price_list_items is
  'Renglones de una lista de precios: el artículo (un producto de compra o, mientras el chef no lo resuelve, un artículo sin mapear), el precio de lista, las dos bonificaciones, la bonificación en pesos por unidad (P6) y el IVA.';
comment on column purchasing.price_list_items.group_id is 'Grupo, el mismo que el de la lista.';
comment on column purchasing.price_list_items.price_list_id is 'Lista a la que pertenece.';
comment on column purchasing.price_list_items.line_order is 'Orden del renglón en la lista.';
comment on column purchasing.price_list_items.purchase_product_id is 'Producto de compra reconocido o ya mapeado.';
comment on column purchasing.price_list_items.unmapped_article_id is
  'Artículo sin mapear, mientras el chef no lo resuelva. Al resolverlo, el renglón pasa al producto.';
comment on column purchasing.price_list_items.raw_name is 'El nombre tal como vino en la lista.';
comment on column purchasing.price_list_items.supplier_sku is 'El código del proveedor, si vino.';
comment on column purchasing.price_list_items.list_price is 'Precio de lista por envase, antes de las bonificaciones.';
comment on column purchasing.price_list_items.currency is 'Moneda (por ahora, pesos).';
comment on column purchasing.price_list_items.bonus1_pct is 'Primera bonificación, en %.';
comment on column purchasing.price_list_items.bonus2_pct is 'Segunda bonificación, en %, sobre lo que queda después de la primera.';
comment on column purchasing.price_list_items.bonus_per_unit_amount is
  'Bonificación en pesos por unidad, que se resta después de los porcentajes (P6, Soy).';
comment on column purchasing.price_list_items.vat_rate is 'Alícuota de IVA: 0, 2,5, 5, 10,5, 21 o 27 % (P5, Soy).';
comment on column purchasing.price_list_items.includes_vat is 'Si el precio de lista ya trae el IVA.';

-- El neto: lista × (1 − b1) × (1 − b2) − bonificación por unidad (caso 5: 100 · 15 % · 10 % = 76,50).
create function purchasing.net_list_price(p_list_price numeric, p_bonus1_pct numeric, p_bonus2_pct numeric,
                                          p_bonus_per_unit_amount numeric)
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select round(p_list_price * (1 - coalesce(p_bonus1_pct, 0) / 100) * (1 - coalesce(p_bonus2_pct, 0) / 100)
               - coalesce(p_bonus_per_unit_amount, 0), 4)
$$;
comment on function purchasing.net_list_price(numeric, numeric, numeric, numeric) is
  'Precio neto de un renglón de lista: lista × (1 − bonificación 1) × (1 − bonificación 2) − bonificación en pesos por unidad, redondeado a 4 decimales.';
grant execute on function purchasing.net_list_price(numeric, numeric, numeric, numeric) to authenticated;

-- Días hasta que vence una lista, según la frecuencia de la ficha (sin frecuencia, no vence).
create function purchasing.list_frequency_days(p_frequency purchasing.list_frequency)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_frequency when 'weekly' then 7 when 'biweekly' then 15 when 'monthly' then 31 end
$$;
comment on function purchasing.list_frequency_days(purchasing.list_frequency) is
  'Días que vale una lista según la frecuencia del proveedor: semanal 7, quincenal 15, mensual 31. Sin frecuencia, vacío (no vence).';
grant execute on function purchasing.list_frequency_days(purchasing.list_frequency) to authenticated;

-- Vencida: es la aceptada y ya pasaron los días de su frecuencia desde la vigencia, en la fecha de la Argentina. Una
-- lista semanal vigente desde el lunes vence el lunes siguiente.
create function purchasing.price_list_expired_internal(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select l.status = 'accepted'
           and purchasing.list_frequency_days(t.price_list_frequency) is not null
           and recipes.today() >= l.valid_from + purchasing.list_frequency_days(t.price_list_frequency)
      from purchasing.price_lists l
      left join purchasing.supplier_terms t on t.supplier_id = l.supplier_id and t.deleted_at is null
     where l.id = p_id and l.deleted_at is null), false)
$$;
comment on function purchasing.price_list_expired_internal(uuid) is
  'Interna: si una lista aceptada ya venció: pasaron 7, 15 o 31 días (según la frecuencia del proveedor) desde su vigencia, en la fecha de la Argentina. Sin frecuencia, no vence. La usan el aviso diario y la versión con permisos.';
revoke execute on function purchasing.price_list_expired_internal(uuid) from public;

-- La misma, para la app: solo responde por listas que la sesión ve (si no, falso).
create function purchasing.price_list_expired(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from purchasing.price_lists l
                  where l.id = p_id and l.deleted_at is null
                    and l.group_id in (select core.visible_group_ids('purchasing.view_price_lists')))
     and purchasing.price_list_expired_internal(p_id)
$$;
comment on function purchasing.price_list_expired(uuid) is
  'Si una lista aceptada ya venció (7, 15 o 31 días desde su vigencia, según la frecuencia del proveedor). Solo responde por listas que la sesión ve; si no, falso.';
revoke execute on function purchasing.price_list_expired(uuid) from public;
grant execute on function purchasing.price_list_expired(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Adjuntos (solo de inserción)
-- ---------------------------------------------------------------------------
create type purchasing.doc_kind as enum ('price_list', 'other');
comment on type purchasing.doc_kind is
  'Tipo de documento adjunto: price_list (la lista de precios escaneada o en PDF) u other. Las facturas y remitos se suman con sus prompts.';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('purchasing-documents', 'purchasing-documents', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);

create table purchasing.attachments (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references org.groups (id) on delete restrict,
  source_table  text not null check (source_table in ('price_lists')),
  source_id     uuid not null,
  doc_kind      purchasing.doc_kind not null,
  page          smallint not null default 1 check (page between 1 and 200),
  storage_path  text not null check (
    storage_path ~ '^[0-9a-f-]{36}/[a-z_]+/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$'),
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict
);
create unique index attachments_path_key on purchasing.attachments (storage_path);
create index attachments_source_idx on purchasing.attachments (source_table, source_id);
create index attachments_group_idx on purchasing.attachments (group_id);
comment on table purchasing.attachments is
  'Archivos de compras (por ahora, listas de precios) guardados en el bucket purchasing-documents. Solo de inserción: un archivo subido no se cambia ni se borra.';
comment on column purchasing.attachments.id is 'Identificador.';
comment on column purchasing.attachments.group_id is 'Grupo, el mismo que el del registro de origen.';
comment on column purchasing.attachments.source_table is 'Tabla del registro de origen (por ahora, price_lists).';
comment on column purchasing.attachments.source_id is 'Registro de origen (la lista).';
comment on column purchasing.attachments.doc_kind is 'Tipo de documento.';
comment on column purchasing.attachments.page is 'Página, si el documento tiene varias fotos.';
comment on column purchasing.attachments.storage_path is
  'Dónde está el archivo en el bucket: <grupo>/<tabla>/<registro>/<archivo>.';
comment on column purchasing.attachments.created_at is 'Cuándo se subió (lo pone la base).';
comment on column purchasing.attachments.created_by is 'Quién lo subió (lo pone la base).';

-- Solo de inserción: quién y cuándo los pone la base, y no se cambia ni se borra nada.
create function purchasing.attachments_insert_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := core.current_actor_id();
    return new;
  end if;
  raise exception 'Un archivo adjunto no se cambia ni se borra.' using errcode = '42501';
end
$$;
comment on function purchasing.attachments_insert_only() is
  'Interna: completa quién y cuándo en un adjunto nuevo y rechaza cualquier cambio o borrado.';
revoke execute on function purchasing.attachments_insert_only() from public;
create trigger attachments_insert_only before insert or update or delete on purchasing.attachments
  for each row execute function purchasing.attachments_insert_only();
create trigger log_change after insert on purchasing.attachments
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on purchasing.attachments
  for each statement execute function core.reject_truncate();
alter table purchasing.attachments enable row level security;
revoke all on purchasing.attachments from public, anon, authenticated, service_role;
grant select on purchasing.attachments to authenticated;
create policy attachments_select on purchasing.attachments for select to authenticated
  using (source_table = 'price_lists'
         and group_id in (select core.visible_group_ids('purchasing.view_price_lists')));

-- Lo que viene en el nombre de un archivo: <grupo>/<tabla>/<registro>/<uuid>.<ext>.
create function purchasing.document_parts(p_name text)
returns table (group_id uuid, source_table text, source_id uuid)
language sql
immutable
set search_path = ''
as $$
  select split_part(p_name, '/', 1)::uuid, split_part(p_name, '/', 2), split_part(p_name, '/', 3)::uuid
   where p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[a-z_]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|pdf)$'
$$;
comment on function purchasing.document_parts(text) is
  'El grupo, la tabla y el registro de un archivo del bucket purchasing-documents, si el nombre tiene la forma <grupo>/<tabla>/<registro>/<uuid>.<ext>. Vacío si no.';

-- Subir: quien carga listas en el grupo, en la carpeta de una lista vigente de su grupo y con un nombre nuevo.
create function purchasing.can_upload_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select d.source_table = 'price_lists'
           and core.has_permission_in_group('purchasing.manage_price_lists', d.group_id)
           and exists (select 1 from purchasing.price_lists l
                        where l.id = d.source_id and l.group_id = d.group_id and l.deleted_at is null
                          and l.status = 'received')
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_upload_document(text) is
  'Si la sesión puede subir ese archivo: purchasing.manage_price_lists en el grupo, carpeta <grupo>/price_lists/<lista>/ de una lista recibida (sin aceptar) del grupo y nombre <uuid>.jpg|png|webp|pdf. Una lista aceptada ya no suma archivos.';

-- Leer: quien ve las listas del grupo, y solo archivos registrados como adjuntos.
create function purchasing.visible_document_paths()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select a.storage_path from purchasing.attachments a
   where a.source_table = 'price_lists'
     and a.group_id in (select core.visible_group_ids('purchasing.view_price_lists'))
$$;
comment on function purchasing.visible_document_paths() is
  'Archivos de compras registrados que la sesión ve (los de las listas de su grupo, con purchasing.view_price_lists). Para la política de lectura de Storage.';

-- Las políticas de Storage corren con la sesión: las tres funciones se pueden llamar.
grant execute on function purchasing.document_parts(text) to authenticated;
grant execute on function purchasing.can_upload_document(text) to authenticated;
grant execute on function purchasing.visible_document_paths() to authenticated;

-- Quien sube también lee lo que subió (Storage lo vuelve a leer al guardar), solo en la carpeta de su grupo.
create function purchasing.can_read_own_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select d.source_table = 'price_lists'
                          and core.has_permission_in_group('purchasing.manage_price_lists', d.group_id)
                     from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_read_own_document(text) is
  'Si la sesión carga listas en el grupo de la carpeta del archivo (para leer lo que acaba de subir, antes de registrarlo).';
grant execute on function purchasing.can_read_own_document(text) to authenticated;

create policy purchasing_documents_read on storage.objects for select to authenticated
  using (bucket_id = 'purchasing-documents'
         and (name in (select purchasing.visible_document_paths()) or purchasing.can_read_own_document(name)));
create policy purchasing_documents_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'purchasing-documents' and owner_id = (select auth.uid())::text
              and purchasing.can_upload_document(name));
-- Sin políticas de update ni de delete: un archivo subido no se cambia ni se borra.

-- Registrar un archivo ya subido en una lista.
create function purchasing.add_price_list_attachment(p_price_list_id uuid, p_storage_path text, p_page smallint,
                                                     p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list purchasing.price_lists;
  v_id   uuid;
begin
  select * into v_list from purchasing.price_lists where id = p_price_list_id and deleted_at is null;
  if v_list.id is null or v_list.status <> 'received'
     or not core.has_permission_in_group('purchasing.manage_price_lists', v_list.group_id) then
    return core.deny('purchasing.add_price_list_attachment', 'No tenés permiso para adjuntar archivos a esta lista.',
                     null, jsonb_build_object('price_list_id', p_price_list_id), v_list.group_id);
  end if;
  if not exists (select 1 from purchasing.document_parts(p_storage_path) d
                  where d.group_id = v_list.group_id and d.source_table = 'price_lists' and d.source_id = v_list.id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'purchasing-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'El archivo no está subido en la carpeta de esta lista.' using errcode = '22023';
  end if;
  perform core.set_change_context(coalesce(nullif(btrim(p_reason), ''), 'Archivo de la lista de precios'), 'manual');
  insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
  values (v_list.group_id, 'price_lists', v_list.id, 'price_list', coalesce(p_page, 1), p_storage_path)
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;
comment on function purchasing.add_price_list_attachment(uuid, text, smallint, text) is
  'Registra como adjunto de una lista un archivo ya subido a su carpeta del bucket purchasing-documents. Pide purchasing.manage_price_lists en el grupo.';
revoke execute on function purchasing.add_price_list_attachment(uuid, text, smallint, text) from public;
grant execute on function purchasing.add_price_list_attachment(uuid, text, smallint, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Control, auditoría y RLS de las tablas nuevas
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['article_aliases', 'unmapped_articles', 'price_lists', 'price_list_items'] loop
    execute format('alter table purchasing.%I enable row level security', t);
    execute format('revoke all on purchasing.%I from public, anon, authenticated, service_role', t);
    execute format('grant select on purchasing.%I to authenticated', t);
    execute format(
      'create trigger set_control_columns before insert or update on purchasing.%I
         for each row execute function core.set_control_columns()', t);
    execute format(
      'create trigger log_change after insert or update or delete on purchasing.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on purchasing.%I
         for each statement execute function core.reject_truncate()', t);
    execute format('comment on column purchasing.%I.id is %L', t, 'Identificador.');
    execute format('comment on column purchasing.%I.created_at is %L', t, 'Cuándo se creó (lo pone la base).');
    execute format('comment on column purchasing.%I.created_by is %L', t, 'Quién lo creó (lo pone la base).');
    execute format('comment on column purchasing.%I.updated_at is %L', t, 'Cuándo se cambió por última vez (lo pone la base).');
    execute format('comment on column purchasing.%I.updated_by is %L', t, 'Quién lo cambió por última vez (lo pone la base).');
    execute format('comment on column purchasing.%I.deleted_at is %L', t, 'Cuándo se borró (borrado lógico). Vacío si está vigente.');
    execute format('comment on column purchasing.%I.deleted_by is %L', t, 'Quién lo borró (lo pone la base).');
  end loop;
end
$$;

-- Las listas y sus precios: quien ve listas. El cocinero no (no tiene el permiso).
create policy price_lists_select on purchasing.price_lists for select to authenticated
  using (deleted_at is null and group_id in (select core.visible_group_ids('purchasing.view_price_lists')));
create policy price_list_items_select on purchasing.price_list_items for select to authenticated
  using (deleted_at is null and group_id in (select core.visible_group_ids('purchasing.view_price_lists')));
-- La cola y los otros nombres: quien mapea y quien ve listas (Compras ve qué quedó «en la cola»).
create policy unmapped_articles_select on purchasing.unmapped_articles for select to authenticated
  using (deleted_at is null
         and (group_id in (select core.visible_group_ids('catalog.map_articles'))
              or group_id in (select core.visible_group_ids('purchasing.view_price_lists'))));
create policy article_aliases_select on purchasing.article_aliases for select to authenticated
  using (deleted_at is null
         and (group_id in (select core.visible_group_ids('catalog.map_articles'))
              or group_id in (select core.visible_group_ids('purchasing.view_price_lists'))));

-- ---------------------------------------------------------------------------
-- 8. Mensajes claros
-- ---------------------------------------------------------------------------
create function purchasing.raise_price_list_error(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'price_lists_dates_check' then
      'La vigencia va desde un mes antes hasta tres meses después de la fecha en que llegó la lista.'
    when p_constraint = 'price_lists_accepted_key' then
      'Otra persona aceptó una lista de este proveedor al mismo tiempo: recargá la página.'
    when p_constraint = 'price_list_items_net_check' then
      'Con esas bonificaciones el precio neto queda en cero o negativo: revisá el renglón.'
    when p_constraint in ('price_list_items_bonus1_pct_check', 'price_list_items_bonus2_pct_check') then
      'Cada bonificación va de 0 a menos de 100 %.'
    when p_constraint = 'price_list_items_vat_rate_check' then 'El IVA es 0; 2,5; 5; 10,5; 21 o 27 %.'
    when p_constraint = 'price_list_items_list_price_check' then 'El precio de lista tiene que ser mayor que cero.'
    when p_constraint = 'price_list_items_bonus_per_unit_amount_check' then
      'La bonificación en pesos no puede ser negativa.'
    when p_constraint in ('price_list_items_supplier_sku_check', 'unmapped_articles_supplier_sku_check',
                          'article_aliases_supplier_sku_check', 'purchase_products_supplier_sku_check') then
      'El código del proveedor va sin espacios y hasta 40 caracteres.'
    when p_constraint = 'purchase_products_supplier_sku_key' then
      'Ese código del proveedor ya lo tiene otro producto suyo.'
    when p_constraint in ('article_aliases_name_key', 'article_aliases_sku_key') then
      'Ese nombre o código del proveedor ya está vinculado a otro producto.'
    when p_constraint = 'purchase_products_weight_check' then
      'El peso estimado por unidad va solo si se factura por peso, y tiene que ser mayor que cero.'
    when p_constraint = 'unmapped_articles_pending_key' then 'Ese artículo ya está en la cola de mapeo.'
    when p_constraint = 'price_list_items_product_key' then
      'Dos renglones de la lista son el mismo artículo del proveedor: dejá uno solo.'
    when p_constraint = 'purchase_products_code_key' then
      'Otra persona creó un producto de esa materia prima al mismo tiempo: probá de nuevo.'
    when p_constraint = 'purchase_products_sku_needs_supplier_check' then
      'El código del proveedor va solo en un producto con proveedor.'
    when p_constraint in ('price_list_items_raw_name_check', 'unmapped_articles_raw_name_check') then
      'El nombre del artículo no puede quedar vacío ni pasar los 200 caracteres.'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la lista.'
    else null
  end;
  if v_message is null then
    perform purchasing.raise_friendly(p_state, p_constraint, p_message);
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function purchasing.raise_price_list_error(text, text, text) is
  'Interna: traduce a un mensaje en español el error de una restricción de listas de precios y artículos (y, si no es suya, usa la de proveedores).';
revoke execute on function purchasing.raise_price_list_error(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 9. Avisos
-- ---------------------------------------------------------------------------
-- Usuarios con un permiso para todo el grupo (menos quien hizo el cambio): cargar y aceptar listas se autorizan así.
create function purchasing.users_with_permission(p_group_id uuid, p_permission text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct a.user_id
    from core.user_role_assignments a
   where a.group_id = p_group_id and a.deleted_at is null and a.scope_type = 'group'
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
     and a.user_id is distinct from core.current_actor_id()
     and core.user_has_permission_for_scope(a.user_id, p_permission, a.scope_type, a.group_id, a.brand_id,
                                            a.restaurant_id)
$$;
comment on function purchasing.users_with_permission(uuid, text) is
  'Interna: quiénes tienen un permiso para todo el grupo (sin contar a quien hace el cambio). Para los avisos: avisa solo a quien puede actuar.';
revoke execute on function purchasing.users_with_permission(uuid, text) from public;

-- Quién mapea (decisión de Joaco, 2026-11-16): también los chefs de una marca o de un local. El producto de compra que
-- se crea es de todo el grupo igual. Alcanza con tener catalog.map_articles en cualquier alcance del grupo.
create function purchasing.can_map_articles(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from core.actor_grants('catalog.map_articles') g where g.group_id = p_group_id)
$$;
comment on function purchasing.can_map_articles(uuid) is
  'Interna: si la sesión puede resolver la cola de mapeo del grupo: catalog.map_articles en cualquier alcance del grupo (grupo, marca o local; decisión de Joaco del 2026-11-16, ADR-0052).';
revoke execute on function purchasing.can_map_articles(uuid) from public;

-- Para el aviso de la cola: quien tiene catalog.map_articles en cualquier alcance del grupo.
create function purchasing.users_who_map(p_group_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct a.user_id
    from core.user_role_assignments a
   where a.group_id = p_group_id and a.deleted_at is null
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
     and a.user_id is distinct from core.current_actor_id()
     and core.user_has_permission_for_scope(a.user_id, 'catalog.map_articles', a.scope_type, a.group_id, a.brand_id,
                                            a.restaurant_id)
$$;
comment on function purchasing.users_who_map(uuid) is
  'Interna: quiénes pueden resolver la cola de mapeo del grupo, en cualquier alcance (sin contar a quien hace el cambio). Para el aviso de artículos nuevos.';
revoke execute on function purchasing.users_who_map(uuid) from public;

-- Un aviso al chef por cada carga que deja artículos en la cola (no uno por artículo).
create function purchasing.notify_unmapped(p_supplier_id uuid, p_count integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s catalog.suppliers;
begin
  if coalesce(p_count, 0) <= 0 then
    return;
  end if;
  select * into v_s from catalog.suppliers where id = p_supplier_id;
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  select u, v_s.group_id, 'unmapped_article',
         left(case when p_count = 1 then format('Un artículo nuevo de «%s» para mapear', coalesce(v_s.trade_name, v_s.name))
                   else format('%s artículos nuevos de «%s» para mapear', p_count, coalesce(v_s.trade_name, v_s.name))
              end, 200),
         'Llegaron en una lista de precios y el sistema no los reconoce. Decí a qué materia prima corresponde cada uno.',
         '/materias-primas/sin-mapear'
    from purchasing.users_who_map(v_s.group_id) u;
end
$$;
comment on function purchasing.notify_unmapped(uuid, integer) is
  'Interna: avisa a quien mapea artículos (catalog.map_articles) que un proveedor mandó artículos que el sistema no reconoce. Un aviso por carga.';
revoke execute on function purchasing.notify_unmapped(uuid, integer) from public;

-- Cada día: las listas aceptadas que vencieron y todavía no se avisaron. Un aviso por lista, a Compras.
create function purchasing.notify_expired_price_lists()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list  record;
  v_count integer := 0;
begin
  perform core.set_change_context('Aviso de lista de precios vencida', 'maintenance');
  for v_list in
    select l.id, l.group_id, l.supplier_id, l.valid_from, coalesce(s.trade_name, s.name) as supplier_name
      from purchasing.price_lists l
      join catalog.suppliers s on s.id = l.supplier_id
     where l.status = 'accepted' and l.deleted_at is null and l.expired_notified_at is null
       and purchasing.price_list_expired_internal(l.id)
     for update of l skip locked
  loop
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u, v_list.group_id, 'price_list_expired',
           left(format('Venció la lista de precios de «%s»', v_list.supplier_name), 200),
           format('Vale desde el %s. Pedile la lista nueva al proveedor.', to_char(v_list.valid_from, 'DD/MM/YYYY')),
           format('/proveedores/%s', v_list.supplier_id)
      from purchasing.users_with_permission(v_list.group_id, 'purchasing.manage_price_lists') u;
    update purchasing.price_lists set expired_notified_at = now() where id = v_list.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end
$$;
comment on function purchasing.notify_expired_price_lists() is
  'Trabajo diario: avisa a Compras (purchasing.manage_price_lists) por cada lista aceptada que venció según la frecuencia del proveedor, una sola vez por lista. Devuelve cuántas avisó.';
revoke execute on function purchasing.notify_expired_price_lists() from public;

-- Un trabajo propio, para no tocar el recálculo de costos (ADR-0032). 06:45 de la Argentina = 09:45 UTC.
select cron.schedule('grupo-lf-compras-diario', '45 9 * * *', 'select purchasing.notify_expired_price_lists()');

-- ---------------------------------------------------------------------------
-- 10. Cargar y aceptar listas
-- ---------------------------------------------------------------------------
-- p_items: [{name, sku, package_hint, list_price, bonus1_pct, bonus2_pct, bonus_per_unit_amount, vat_rate,
--            includes_vat}]. Cada renglón se reconoce; lo que no, entra a la cola (o se suma al pendiente que ya hay).
create function purchasing.create_price_list(p_supplier_id uuid, p_received_on date, p_valid_from date,
                                             p_items jsonb, p_notes text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s          catalog.suppliers;
  v_list_id    uuid;
  v_item       jsonb;
  v_order      integer := 0;
  v_product    uuid;
  v_unmapped   uuid;
  v_new        integer := 0;
  v_queued     integer := 0;
  v_constraint text;
  v_message    text;
begin
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null or not core.has_permission_in_group('purchasing.manage_price_lists', v_s.group_id) then
    return core.deny('purchasing.create_price_list', 'No tenés permiso para cargar listas de este proveedor.', null,
                     jsonb_build_object('supplier_id', p_supplier_id), v_s.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de la carga.' using errcode = '22023';
  end if;
  if p_received_on is null or p_valid_from is null then
    raise exception 'Faltan la fecha en que llegó y desde cuándo vale.' using errcode = '22023';
  end if;
  if p_received_on > recipes.today() then
    raise exception 'La fecha en que llegó la lista no puede ser futura.' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'La lista no tiene renglones.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 2000 then
    raise exception 'Una lista va hasta 2000 renglones.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into purchasing.price_lists (group_id, supplier_id, received_on, valid_from, notes)
  values (v_s.group_id, v_s.id, p_received_on, p_valid_from, nullif(btrim(p_notes), ''))
  returning id into v_list_id;

  for v_item in select value from jsonb_array_elements(p_items) loop
    perform org.check_keys(v_item, array['name', 'sku', 'package_hint', 'list_price', 'bonus1_pct', 'bonus2_pct',
                                         'bonus_per_unit_amount', 'vat_rate', 'includes_vat']);
    v_order := v_order + 1;
    if nullif(btrim(v_item ->> 'name'), '') is null then
      raise exception 'Al renglón % le falta el nombre del artículo.', v_order using errcode = '23514';
    end if;
    v_product := purchasing.match_article(v_s.id, v_item ->> 'sku', v_item ->> 'name');
    v_unmapped := null;
    if v_product is null then
      -- Primero lo pendiente; si el chef ya lo descartó, el renglón queda con ese artículo y no vuelve a la cola.
      select id into v_unmapped from purchasing.unmapped_articles
       where supplier_id = v_s.id and normalized_name = purchasing.normalize_name(v_item ->> 'name')
         and status in ('pending', 'discarded') and deleted_at is null
       order by status = 'pending' desc, resolved_at desc nulls first
       limit 1;
      if v_unmapped is null then
        insert into purchasing.unmapped_articles (group_id, supplier_id, raw_name, supplier_sku, package_hint,
                                                  found_in, source_id)
        values (v_s.group_id, v_s.id, btrim(v_item ->> 'name'), purchasing.normalize_sku(v_item ->> 'sku'),
                nullif(btrim(v_item ->> 'package_hint'), ''), 'price_list', v_list_id)
        returning id into v_unmapped;
        v_new := v_new + 1;
      end if;
      if (select status from purchasing.unmapped_articles where id = v_unmapped) = 'pending' then
        v_queued := v_queued + 1;
      end if;
    end if;
    insert into purchasing.price_list_items (group_id, price_list_id, line_order, purchase_product_id,
                                             unmapped_article_id, raw_name, supplier_sku, list_price, bonus1_pct,
                                             bonus2_pct, bonus_per_unit_amount, vat_rate, includes_vat)
    values (v_s.group_id, v_list_id, v_order, v_product, v_unmapped, btrim(v_item ->> 'name'),
            purchasing.normalize_sku(v_item ->> 'sku'), (v_item ->> 'list_price')::numeric,
            coalesce((v_item ->> 'bonus1_pct')::numeric, 0), coalesce((v_item ->> 'bonus2_pct')::numeric, 0),
            coalesce((v_item ->> 'bonus_per_unit_amount')::numeric, 0), (v_item ->> 'vat_rate')::numeric,
            coalesce((v_item ->> 'includes_vat')::boolean, false));
  end loop;
  perform purchasing.notify_unmapped(v_s.id, v_new);
  return jsonb_build_object('result', 'applied', 'price_list_id', v_list_id, 'items', v_order, 'queued', v_queued,
                            'new_unmapped', v_new);
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los números de la lista: precios, bonificaciones e IVA van con números y en su rango.'
      using errcode = '22023';
end
$$;
comment on function purchasing.create_price_list(uuid, date, date, jsonb, text, text) is
  'Carga una lista de precios (recibida, sin aceptar) en una transacción. Reconoce cada renglón por código o nombre del proveedor; lo que no reconoce entra a la cola de mapeo y se avisa al chef. Pide purchasing.manage_price_lists y un motivo. No toca los costos.';
revoke execute on function purchasing.create_price_list(uuid, date, date, jsonb, text, text) from public;
grant execute on function purchasing.create_price_list(uuid, date, date, jsonb, text, text) to authenticated;

-- Aceptar: en una transacción, la aceptada anterior del proveedor pasa a reemplazada. No se acepta una lista más vieja
-- que la vigente.
create function purchasing.accept_price_list(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list    purchasing.price_lists;
  v_current purchasing.price_lists;
  v_constraint text;
  v_message    text;
begin
  select * into v_list from purchasing.price_lists where id = p_id and deleted_at is null;
  if v_list.id is null or not core.has_permission_in_group('purchasing.manage_price_lists', v_list.group_id) then
    return core.deny('purchasing.accept_price_list', 'No tenés permiso para aceptar esta lista.', null,
                     jsonb_build_object('price_list_id', p_id), v_list.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  -- Dos aceptaciones del mismo proveedor van de a una.
  perform 1 from catalog.suppliers where id = v_list.supplier_id for update;
  select * into v_list from purchasing.price_lists where id = p_id;
  if v_list.status <> 'received' then
    raise exception 'Esta lista ya no está para aceptar (está %).',
      case v_list.status when 'accepted' then 'aceptada' else 'reemplazada' end using errcode = '23514';
  end if;
  select * into v_current from purchasing.price_lists
   where supplier_id = v_list.supplier_id and status = 'accepted' and deleted_at is null;
  if v_current.id is not null and v_current.valid_from > v_list.valid_from then
    raise exception 'La lista vigente de este proveedor es más nueva (vale desde el %).',
      to_char(v_current.valid_from, 'DD/MM/YYYY') using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  if v_current.id is not null then
    update purchasing.price_lists set status = 'replaced' where id = v_current.id;
  end if;
  update purchasing.price_lists
     set status = 'accepted', accepted_at = now(), accepted_by = core.current_actor_id()
   where id = v_list.id;
  return jsonb_build_object('result', 'applied', 'replaced', v_current.id);
exception when unique_violation or check_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.accept_price_list(uuid, text) is
  'Acepta una lista recibida: pasa a ser la vigente del proveedor y la anterior queda reemplazada, en una transacción y con motivo. No acepta una lista más vieja que la vigente. Pide purchasing.manage_price_lists.';
revoke execute on function purchasing.accept_price_list(uuid, text) from public;
grant execute on function purchasing.accept_price_list(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Resolver la cola
-- ---------------------------------------------------------------------------
-- El artículo pendiente, con permiso de mapear en su grupo, o error.
create function purchasing.pending_article(p_id uuid)
returns purchasing.unmapped_articles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a purchasing.unmapped_articles;
begin
  select * into v_a from purchasing.unmapped_articles where id = p_id and deleted_at is null;
  if v_a.id is null or not purchasing.can_map_articles(v_a.group_id) then
    return null;
  end if;
  select * into v_a from purchasing.unmapped_articles where id = p_id for update;
  if v_a.status <> 'pending' then
    raise exception 'Otra persona ya resolvió este artículo: recargá la página.' using errcode = '23514';
  end if;
  return v_a;
end
$$;
comment on function purchasing.pending_article(uuid) is
  'Interna: el artículo pendiente de la cola, bloqueado, si la sesión puede mapear en su grupo (si no, vacío: quien llama registra el rechazo). Da error si ya no está pendiente.';
revoke execute on function purchasing.pending_article(uuid) from public;

-- Al resolver: los renglones de lista que apuntaban al pendiente pasan al producto, y la cola queda resuelta.
create function purchasing.close_article(p_a purchasing.unmapped_articles, p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Si esa lista ya tiene el producto (el proveedor lo mandó dos veces con nombres distintos), el renglón queda con el
  -- artículo resuelto: el producto va una sola vez por lista.
  update purchasing.price_list_items i
     set purchase_product_id = p_product_id, unmapped_article_id = null
   where i.unmapped_article_id = p_a.id and i.deleted_at is null
     and not exists (select 1 from purchasing.price_list_items x
                      where x.price_list_id = i.price_list_id and x.purchase_product_id = p_product_id
                        and x.deleted_at is null);
  update purchasing.unmapped_articles
     set status = 'resolved', purchase_product_id = p_product_id, resolved_at = now(),
         resolved_by = core.current_actor_id()
   where id = p_a.id;
end
$$;
comment on function purchasing.close_article(purchasing.unmapped_articles, uuid) is
  'Interna: pasa al producto los renglones de lista del artículo pendiente (menos en una lista que ya tiene ese producto) y lo marca resuelto.';
revoke execute on function purchasing.close_article(purchasing.unmapped_articles, uuid) from public;

-- «Es una materia prima»: crea el producto de compra del proveedor, con el envase y el contenido que dice el chef y un
-- código automático (el de la materia prima + -P01, -P02…).
create function purchasing.resolve_article(p_id uuid, p_ingredient_id uuid, p_package_unit text,
                                           p_units_per_package integer, p_content_per_unit numeric,
                                           p_content_unit text, p_details jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a          purchasing.unmapped_articles;
  v_ing        catalog.ingredients;
  v_code       text;
  v_n          integer := 0;
  v_product    uuid;
  v_by_weight  boolean;
  v_constraint text;
  v_message    text;
begin
  v_a := purchasing.pending_article(p_id);
  if v_a.id is null then
    return core.deny('purchasing.resolve_article', 'No tenés permiso para mapear este artículo.', null,
                     jsonb_build_object('unmapped_article_id', p_id),
                     (select group_id from purchasing.unmapped_articles where id = p_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  perform org.check_keys(coalesce(p_details, '{}'::jsonb),
                         array['brand_name', 'billed_by_weight', 'estimated_weight_per_unit', 'description']);
  select * into v_ing from catalog.ingredients
   where id = p_ingredient_id and group_id = v_a.group_id and deleted_at is null and is_active;
  if v_ing.id is null then
    raise exception 'Elegí una materia prima activa de este grupo.' using errcode = '22023';
  end if;
  loop
    v_n := v_n + 1;
    v_code := left(v_ing.code, 26) || '-P' || lpad(v_n::text, 2, '0');
    exit when not exists (select 1 from catalog.purchase_products where group_id = v_a.group_id and code = v_code);
  end loop;
  v_by_weight := coalesce((p_details ->> 'billed_by_weight')::boolean, false);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, brand_name,
                                         package_unit_id, units_per_package, content_per_unit, content_unit_id,
                                         supplier_sku, billed_by_weight, estimated_weight_per_unit)
  values (v_a.group_id, v_code, v_ing.id, v_a.supplier_id,
          coalesce(nullif(btrim(p_details ->> 'description'), ''), v_a.raw_name),
          nullif(btrim(p_details ->> 'brand_name'), ''), catalog.unit_id(p_package_unit),
          coalesce(p_units_per_package, 1), p_content_per_unit, catalog.unit_id(p_content_unit), v_a.supplier_sku,
          v_by_weight, case when v_by_weight then (p_details ->> 'estimated_weight_per_unit')::numeric end)
  returning id into v_product;
  -- Si el chef le cambió la descripción, el nombre como vino queda como otro nombre para reconocerlo.
  if purchasing.normalize_name(coalesce(nullif(btrim(p_details ->> 'description'), ''), v_a.raw_name))
       is distinct from v_a.normalized_name then
    insert into purchasing.article_aliases (group_id, supplier_id, purchase_product_id, raw_name)
    values (v_a.group_id, v_a.supplier_id, v_product, v_a.raw_name);
  end if;
  perform purchasing.close_article(v_a, v_product);
  return jsonb_build_object('result', 'applied', 'purchase_product_id', v_product, 'code', v_code);
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.resolve_article(uuid, uuid, text, integer, numeric, text, jsonb, text) is
  'Resuelve un artículo de la cola: crea el producto de compra del proveedor para esa materia prima, con su envase y contenido y un código automático, pasa a él los renglones de lista y cierra la cola, en una transacción. Pide catalog.map_articles y un motivo.';
revoke execute on function purchasing.resolve_article(uuid, uuid, text, integer, numeric, text, jsonb, text) from public;
grant execute on function purchasing.resolve_article(uuid, uuid, text, integer, numeric, text, jsonb, text) to authenticated;

-- «Es el mismo que…»: el proveedor renombró un producto. Se guarda el nombre (y el código) nuevo para reconocerlo.
create function purchasing.link_article(p_id uuid, p_purchase_product_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a          purchasing.unmapped_articles;
  v_p          catalog.purchase_products;
  v_sku        text;
  v_constraint text;
  v_message    text;
begin
  v_a := purchasing.pending_article(p_id);
  if v_a.id is null then
    return core.deny('purchasing.link_article', 'No tenés permiso para mapear este artículo.', null,
                     jsonb_build_object('unmapped_article_id', p_id),
                     (select group_id from purchasing.unmapped_articles where id = p_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  select * into v_p from catalog.purchase_products
   where id = p_purchase_product_id and supplier_id = v_a.supplier_id and deleted_at is null and is_active;
  if v_p.id is null then
    raise exception 'Elegí un producto activo de este mismo proveedor.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- El código nuevo va al producto si no tenía; si tenía otro, queda en el otro nombre.
  v_sku := v_a.supplier_sku;
  if v_sku is not null and v_p.supplier_sku is null then
    update catalog.purchase_products set supplier_sku = v_sku where id = v_p.id;
    v_sku := null;
  elsif v_sku is not distinct from v_p.supplier_sku then
    v_sku := null;
  end if;
  if v_a.normalized_name is distinct from purchasing.normalize_name(v_p.description) or v_sku is not null then
    insert into purchasing.article_aliases (group_id, supplier_id, purchase_product_id, raw_name, supplier_sku)
    values (v_a.group_id, v_a.supplier_id, v_p.id, v_a.raw_name, v_sku);
  end if;
  perform purchasing.close_article(v_a, v_p.id);
  return jsonb_build_object('result', 'applied', 'purchase_product_id', v_p.id);
exception
  when unique_violation or check_violation or foreign_key_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.link_article(uuid, uuid, text) is
  'Resuelve un artículo de la cola diciendo que es el mismo que un producto que el proveedor ya tenía (lo renombró): guarda el nombre y el código nuevos para reconocerlo, pasa los renglones de lista al producto y cierra la cola. Pide catalog.map_articles y un motivo.';
revoke execute on function purchasing.link_article(uuid, uuid, text) from public;
grant execute on function purchasing.link_article(uuid, uuid, text) to authenticated;

-- Descartar: no se usa. Los renglones de lista quedan con el artículo descartado (la lista no se toca).
create function purchasing.discard_article(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a purchasing.unmapped_articles;
begin
  v_a := purchasing.pending_article(p_id);
  if v_a.id is null then
    return core.deny('purchasing.discard_article', 'No tenés permiso para mapear este artículo.', null,
                     jsonb_build_object('unmapped_article_id', p_id),
                     (select group_id from purchasing.unmapped_articles where id = p_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update purchasing.unmapped_articles
     set status = 'discarded', resolved_at = now(), resolved_by = core.current_actor_id()
   where id = v_a.id;
  return jsonb_build_object('result', 'applied');
end
$$;
comment on function purchasing.discard_article(uuid, text) is
  'Descarta un artículo de la cola (no es algo que se use). Sus renglones de lista quedan como vinieron. Pide catalog.map_articles y un motivo.';
revoke execute on function purchasing.discard_article(uuid, text) from public;
grant execute on function purchasing.discard_article(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Lectura
-- ---------------------------------------------------------------------------
-- Listado de listas, con permisos de quien consulta. Los estados: aceptada, recibida, reemplazada o vencida (calculada).
create function purchasing.price_list_list(p_supplier_id uuid default null, p_status text default null,
                                           p_limit integer default 15, p_offset integer default 0)
returns table (id uuid, supplier_id uuid, supplier_name text, received_on date, valid_from date,
               status purchasing.price_list_status, expired boolean, items bigint, queued bigint, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select l.id, l.supplier_id, coalesce(s.trade_name, s.name) as supplier_name, l.received_on, l.valid_from,
           l.status, purchasing.price_list_expired(l.id) as expired,
           (select count(*) from purchasing.price_list_items i where i.price_list_id = l.id and i.deleted_at is null)
             as items,
           (select count(*) from purchasing.price_list_items i
              join purchasing.unmapped_articles a on a.id = i.unmapped_article_id and a.status = 'pending'
             where i.price_list_id = l.id and i.deleted_at is null) as queued
      from purchasing.price_lists l
      join catalog.suppliers s on s.id = l.supplier_id
     where l.deleted_at is null
       and (p_supplier_id is null or l.supplier_id = p_supplier_id)),
  filtered as (
    select * from base
     where p_status is null
        or (p_status = 'expired' and expired)
        or (p_status = 'accepted' and status = 'accepted' and not expired)
        or (p_status in ('received', 'replaced') and status::text = p_status))
  select f.id, f.supplier_id, f.supplier_name, f.received_on, f.valid_from, f.status, f.expired, f.items, f.queued,
         count(*) over ()
    from filtered f
   order by f.received_on desc, f.supplier_name, f.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function purchasing.price_list_list(uuid, text, integer, integer) is
  'Listado de listas de precios (las más nuevas primero), con permisos de quien consulta: proveedor, fechas, estado, si venció, cuántos renglones tiene y cuántos esperan en la cola. Filtra por proveedor y estado (accepted, received, replaced o expired) y pagina.';
revoke execute on function purchasing.price_list_list(uuid, text, integer, integer) from public;
grant execute on function purchasing.price_list_list(uuid, text, integer, integer) to authenticated;

-- Variación % del neto por producto entre una lista y la anterior aceptada del mismo proveedor.
create view reporting.v_price_list_changes with (security_invoker = true) as
  with lists as (
    select l.id, l.group_id, l.supplier_id, l.valid_from, l.status,
           (select p.id from purchasing.price_lists p
             where p.supplier_id = l.supplier_id and p.deleted_at is null and p.id <> l.id
               and p.status in ('accepted', 'replaced')
               and (p.valid_from < l.valid_from or (p.valid_from = l.valid_from and p.created_at < l.created_at))
             order by p.valid_from desc, p.created_at desc limit 1) as previous_id
      from purchasing.price_lists l
     where l.deleted_at is null)
  select l.group_id, l.supplier_id, l.id as price_list_id, l.previous_id as previous_price_list_id,
         i.purchase_product_id, i.raw_name,
         purchasing.net_list_price(i.list_price, i.bonus1_pct, i.bonus2_pct, i.bonus_per_unit_amount) as net_price,
         purchasing.net_list_price(pi.list_price, pi.bonus1_pct, pi.bonus2_pct, pi.bonus_per_unit_amount)
           as previous_net_price,
         round(100 * (purchasing.net_list_price(i.list_price, i.bonus1_pct, i.bonus2_pct, i.bonus_per_unit_amount)
                      / nullif(purchasing.net_list_price(pi.list_price, pi.bonus1_pct, pi.bonus2_pct,
                                                         pi.bonus_per_unit_amount), 0) - 1), 2) as change_pct
    from lists l
    join purchasing.price_list_items i on i.price_list_id = l.id and i.deleted_at is null
    left join lateral (
      select x.* from purchasing.price_list_items x
       where x.price_list_id = l.previous_id and x.purchase_product_id = i.purchase_product_id
         and x.deleted_at is null
       order by x.line_order limit 1) pi on i.purchase_product_id is not null;
revoke all on reporting.v_price_list_changes from public, anon, authenticated, service_role;
comment on view reporting.v_price_list_changes is
  'Cada renglón de una lista con su neto, el neto del mismo producto en la lista aceptada anterior del proveedor y la variación en %. Vacío en lo anterior si es la primera lista o el artículo es nuevo. Con los permisos de quien consulta.';

-- El detalle de una lista con la variación: quien ve listas del grupo. reporting no se abre a la app; se lee por acá.
create function purchasing.price_list_changes(p_price_list_id uuid)
returns table (purchase_product_id uuid, raw_name text, net_price numeric, previous_net_price numeric,
               change_pct numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select c.purchase_product_id, c.raw_name, c.net_price, c.previous_net_price, c.change_pct
    from reporting.v_price_list_changes c
    join purchasing.price_lists l on l.id = c.price_list_id and l.deleted_at is null
   where c.price_list_id = p_price_list_id
     and l.group_id in (select core.visible_group_ids('purchasing.view_price_lists'))
$$;
comment on function purchasing.price_list_changes(uuid) is
  'Los renglones de una lista con su neto, el de la lista aceptada anterior y la variación en %, si la sesión ve las listas del grupo. Vacío si no.';
revoke execute on function purchasing.price_list_changes(uuid) from public;
grant execute on function purchasing.price_list_changes(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 13. Historial: las listas, solo para quien las ve (revisión de seguridad, M2)
-- ---------------------------------------------------------------------------
-- core.hide_payment ya se aplica a cada valor del historial y de su exportación. Ahora también oculta los precios,
-- bonificaciones, IVA y observaciones de las listas a quien no tiene purchasing.view_price_lists en ese grupo (aunque vea
-- costos, como el Chef Ejecutivo).
create or replace function core.hide_payment(p_schema text, p_table text, p_group_id uuid, p_value jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_value is null or p_schema is distinct from 'purchasing' then
    return p_value;
  end if;
  if p_table in ('supplier_payment_terms', 'supplier_payment_accounts') then
    if p_group_id is not null and purchasing.can_see_payment(p_group_id) then
      return p_value;
    end if;
  elsif p_table in ('price_lists', 'price_list_items') then
    if p_group_id is not null
       and p_group_id in (select core.visible_group_ids('purchasing.view_price_lists')) then
      return p_value;
    end if;
  else
    return p_value;
  end if;
  return (select coalesce(jsonb_object_agg(k, case when k in ('id', 'group_id', 'supplier_id', 'price_list_id',
                                                              'created_at', 'created_by', 'updated_at', 'updated_by',
                                                              'deleted_at', 'deleted_by')
                                                   then v else to_jsonb('[oculto]'::text) end), '{}'::jsonb)
            from jsonb_each(p_value) as e (k, v));
end
$$;
comment on function core.hide_payment(text, text, uuid, jsonb) is
  'Interna. En el historial, reemplaza por "[oculto]" los valores de la condición de pago y las cuentas de los proveedores a quien no ve el pago en ese grupo (purchasing.can_see_payment), y los de las listas de precios a quien no las ve (purchasing.view_price_lists, ADR-0052).';
