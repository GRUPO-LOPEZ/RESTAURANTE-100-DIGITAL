-- Fase 2 · Etapa 2.3, PR 1: motor de costos (ADR-0032).
-- 1. Al publicar una versión se congela la cantidad de cada línea en la unidad de uso: una densidad nueva ya
--    no mueve una receta publicada (riesgo de ADR-0029).
-- 2. El motor calcula en la base el costo de una receta en un local: materia prima, rendimiento aprobado,
--    subrecetas (la variante del local, si tiene) y precio con herencia. Si falta un dato, nunca da $ 0.
-- 3. costing.recipe_cost_current guarda el costo vigente; las fotos (recipe_cost_snapshots y sus líneas) son
--    la historia, solo de inserción, y guardan lo que no tiene versión.
-- 4. Publicar, aprobar un precio o un rendimiento, asignar una receta y cambiar la razón social anotan un
--    pedido en una cola, y un solo proceso recalcula cada minuto (decisión de Joaco).

create type costing.cost_reliability as enum ('verified', 'estimated', 'stale', 'incomplete');
comment on type costing.cost_reliability is
  'Confiabilidad de un costo; gana la peor línea: verified (completo y verificado), estimated (con estimaciones: algún precio heredado), stale (desactualizado: algún precio vencido) e incomplete (falta un dato).';
create type costing.cost_snapshot_reason as enum ('publish', 'price_change', 'yield_change', 'assignment', 'legal_entity_change', 'restaurant_reopened');
comment on type costing.cost_snapshot_reason is
  'Por qué se sacó una foto de costo: se publicó una versión, se aprobó un precio o un rendimiento, se asignó la receta a un local, cambió la razón social o se reabrió el local.';

-- Las tablas de historia de este módulo: nada cambia ni se borra.
create function costing.reject_changes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Esta historia no se cambia ni se borra.' using errcode = '42501';
end
$$;
comment on function costing.reject_changes() is
  'Trigger (BEFORE UPDATE OR DELETE) de las tablas solo de inserción del motor de costos.';
revoke execute on function costing.reject_changes() from public;

-- ---------------------------------------------------------------------------
-- 1. Las cantidades congeladas
-- ---------------------------------------------------------------------------
create table recipes.component_base_quantities (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  recipe_version_id    uuid not null references recipes.recipe_versions (id) on delete restrict,
  recipe_component_id  uuid not null references recipes.recipe_components (id) on delete restrict,
  base_quantity        numeric(18,6) not null check (base_quantity > 0),
  base_unit_id         uuid not null references catalog.units (id) on delete restrict,
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict
);
create unique index component_base_quantities_component_key on recipes.component_base_quantities (recipe_component_id);
create index component_base_quantities_group_idx on recipes.component_base_quantities (group_id);
create index component_base_quantities_version_idx on recipes.component_base_quantities (recipe_version_id);
create index component_base_quantities_unit_idx on recipes.component_base_quantities (base_unit_id);
comment on table recipes.component_base_quantities is
  'Cantidad de cada línea en la unidad de uso, congelada al publicar la versión: una conversión nueva no mueve una receta publicada. Solo de inserción. No es un dato económico. Solo la lee el motor de costos.';
comment on column recipes.component_base_quantities.id is 'Identificador.';
comment on column recipes.component_base_quantities.group_id is 'Grupo de la receta.';
comment on column recipes.component_base_quantities.recipe_version_id is 'Versión publicada.';
comment on column recipes.component_base_quantities.recipe_component_id is 'Línea de la fórmula. Una sola cantidad por línea.';
comment on column recipes.component_base_quantities.base_quantity is 'Cantidad de la línea en la unidad de uso de la materia prima, o en la unidad base de la preparación.';
comment on column recipes.component_base_quantities.base_unit_id is 'Unidad de esa cantidad (g, ml o unidad).';
comment on column recipes.component_base_quantities.created_at is 'Cuándo se congeló (lo pone la base).';
comment on column recipes.component_base_quantities.created_by is 'Quién publicó (lo pone la base).';
comment on column recipes.component_base_quantities.updated_at is 'Igual a created_at: la fila no cambia.';
comment on column recipes.component_base_quantities.updated_by is 'Igual a created_by: la fila no cambia.';
comment on column recipes.component_base_quantities.deleted_at is 'Siempre vacío: la fila no se da de baja.';
comment on column recipes.component_base_quantities.deleted_by is 'Siempre vacío: la fila no se da de baja.';

alter table recipes.component_base_quantities enable row level security;
revoke all on recipes.component_base_quantities from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on recipes.component_base_quantities
  for each row execute function core.set_control_columns();
create trigger reject_changes before update or delete on recipes.component_base_quantities
  for each row execute function costing.reject_changes();
create trigger log_change after insert or update or delete on recipes.component_base_quantities
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on recipes.component_base_quantities
  for each statement execute function core.reject_truncate();

create function recipes.freeze_base_quantities(p_version_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into recipes.component_base_quantities (group_id, recipe_version_id, recipe_component_id, base_quantity, base_unit_id)
  select c.group_id, c.recipe_version_id, c.id, b.base_quantity, i.recipe_unit_id
    from recipes.recipe_components c
    join catalog.ingredients i on i.id = c.ingredient_id
    cross join lateral catalog.to_base_quantity(c.ingredient_id, c.quantity, c.unit_id) b
   where c.recipe_version_id = p_version_id and c.deleted_at is null and b.status = 'ok'
     and round(b.base_quantity, 6) > 0 and b.base_quantity < 9e11
  union all
  select c.group_id, c.recipe_version_id, c.id, c.quantity * recipes.unit_to_base(c.unit_id), base.id
    from recipes.recipe_components c
    join catalog.units u on u.id = c.unit_id
    join catalog.units base on base.dimension = u.dimension and base.is_base
   where c.recipe_version_id = p_version_id and c.deleted_at is null and c.sub_recipe_id is not null
     and round(c.quantity * recipes.unit_to_base(c.unit_id), 6) > 0 and c.quantity * recipes.unit_to_base(c.unit_id) < 9e11
  on conflict (recipe_component_id) do nothing
$$;
comment on function recipes.freeze_base_quantities(uuid) is
  'Interna: congela la cantidad de cada línea de una versión en la unidad de uso, con las conversiones de ese momento.';
revoke execute on function recipes.freeze_base_quantities(uuid) from public;

-- ---------------------------------------------------------------------------
-- 2. Las tablas del costo
-- ---------------------------------------------------------------------------
create table costing.recipe_cost_current (
  id                  uuid primary key default gen_random_uuid(),
  group_id            uuid not null references org.groups (id) on delete restrict,
  restaurant_id       uuid not null references org.restaurants (id) on delete restrict,
  recipe_id           uuid not null references recipes.recipes (id) on delete restrict,
  recipe_version_id   uuid not null references recipes.recipe_versions (id) on delete restrict,
  as_of               date not null,
  total_cost          numeric(18,4),
  total_gross_cost    numeric(18,4),
  cost_per_base_unit  numeric(20,8),
  cost_per_portion    numeric(18,4),
  reliability         costing.cost_reliability not null,
  currency            text not null default 'ARS' check (currency = 'ARS'),
  method_version      integer not null default 1 check (method_version > 0),
  created_at          timestamptz not null default now(),
  created_by          uuid references core.actors (id) on delete restrict,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references core.actors (id) on delete restrict,
  deleted_at          timestamptz,
  deleted_by          uuid references core.actors (id) on delete restrict
);
create unique index recipe_cost_current_key on costing.recipe_cost_current (recipe_id, restaurant_id) where deleted_at is null;
create index recipe_cost_current_group_idx on costing.recipe_cost_current (group_id);
create index recipe_cost_current_restaurant_idx on costing.recipe_cost_current (restaurant_id, reliability) where deleted_at is null;
create index recipe_cost_current_version_idx on costing.recipe_cost_current (recipe_version_id);
comment on table costing.recipe_cost_current is
  'El costo vigente de cada receta en cada local. Dato derivado: lo escribe solo el motor y no pasa por la auditoría, para no llenarla en cada recálculo; la historia son las fotos (recipe_cost_snapshots).';
comment on column costing.recipe_cost_current.id is 'Identificador.';
comment on column costing.recipe_cost_current.group_id is 'Grupo de la receta.';
comment on column costing.recipe_cost_current.restaurant_id is 'Local: una misma receta cuesta distinto en cada uno.';
comment on column costing.recipe_cost_current.recipe_id is 'Receta.';
comment on column costing.recipe_cost_current.recipe_version_id is 'Versión publicada con la que se calculó.';
comment on column costing.recipe_cost_current.as_of is 'Fecha de los precios que se usaron.';
comment on column costing.recipe_cost_current.total_cost is 'Costo total de la receta, sin el IVA recuperable. Vacío si falta un dato: nunca $ 0.';
comment on column costing.recipe_cost_current.total_gross_cost is 'Costo total con IVA. Vacío si falta un dato.';
comment on column costing.recipe_cost_current.cost_per_base_unit is 'Costo por unidad base terminada (g, ml o unidad). Vacío si falta el rendimiento.';
comment on column costing.recipe_cost_current.cost_per_portion is 'Costo por porción. Vacío si no hay porciones.';
comment on column costing.recipe_cost_current.reliability is 'Confiabilidad: gana la peor línea.';
comment on column costing.recipe_cost_current.currency is 'Moneda. Solo ARS.';
comment on column costing.recipe_cost_current.method_version is 'Versión del método de cálculo.';
comment on column costing.recipe_cost_current.created_at is 'Cuándo se calculó por primera vez (lo pone la base).';
comment on column costing.recipe_cost_current.created_by is 'Vacío: lo escribe el proceso de la cola. Quién hizo el cambio está en la auditoría del precio, el rendimiento o la versión.';
comment on column costing.recipe_cost_current.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column costing.recipe_cost_current.updated_by is 'Vacío: lo escribe el proceso de la cola.';
comment on column costing.recipe_cost_current.deleted_at is 'Baja lógica: el local dejó de usar la receta.';
comment on column costing.recipe_cost_current.deleted_by is 'Vacío: lo da de baja el proceso de la cola.';

create table costing.recipe_cost_snapshots (
  id                  uuid primary key default gen_random_uuid(),
  group_id            uuid not null references org.groups (id) on delete restrict,
  restaurant_id       uuid not null references org.restaurants (id) on delete restrict,
  recipe_id           uuid not null references recipes.recipes (id) on delete restrict,
  recipe_version_id   uuid not null references recipes.recipe_versions (id) on delete restrict,
  as_of               date not null,
  reason              costing.cost_snapshot_reason not null,
  total_cost          numeric(18,4),
  total_gross_cost    numeric(18,4),
  cost_per_base_unit  numeric(20,8),
  cost_per_portion    numeric(18,4),
  reliability         costing.cost_reliability not null,
  currency            text not null default 'ARS' check (currency = 'ARS'),
  method_version      integer not null default 1 check (method_version > 0),
  created_at          timestamptz not null default now(),
  created_by          uuid references core.actors (id) on delete restrict,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references core.actors (id) on delete restrict,
  deleted_at          timestamptz,
  deleted_by          uuid references core.actors (id) on delete restrict
);
create index recipe_cost_snapshots_group_idx on costing.recipe_cost_snapshots (group_id);
create index recipe_cost_snapshots_recipe_idx on costing.recipe_cost_snapshots (recipe_id, restaurant_id, created_at desc);
create index recipe_cost_snapshots_restaurant_idx on costing.recipe_cost_snapshots (restaurant_id, created_at desc);
create index recipe_cost_snapshots_version_idx on costing.recipe_cost_snapshots (recipe_version_id);
comment on table costing.recipe_cost_snapshots is
  'Foto histórica del costo de una receta en un local. Solo de inserción: se saca cada vez que el costo cambia, y una foto vieja nunca cambia. Es la historia del costo, por eso no pasa por la auditoría.';
comment on column costing.recipe_cost_snapshots.id is 'Identificador.';
comment on column costing.recipe_cost_snapshots.group_id is 'Grupo de la receta.';
comment on column costing.recipe_cost_snapshots.restaurant_id is 'Local.';
comment on column costing.recipe_cost_snapshots.recipe_id is 'Receta.';
comment on column costing.recipe_cost_snapshots.recipe_version_id is 'Versión con la que se calculó.';
comment on column costing.recipe_cost_snapshots.as_of is 'Fecha de los precios que se usaron.';
comment on column costing.recipe_cost_snapshots.reason is 'Por qué se sacó la foto.';
comment on column costing.recipe_cost_snapshots.total_cost is 'Costo total, sin el IVA recuperable. Vacío si faltaba un dato.';
comment on column costing.recipe_cost_snapshots.total_gross_cost is 'Costo total con IVA. Vacío si faltaba un dato.';
comment on column costing.recipe_cost_snapshots.cost_per_base_unit is 'Costo por unidad base terminada.';
comment on column costing.recipe_cost_snapshots.cost_per_portion is 'Costo por porción.';
comment on column costing.recipe_cost_snapshots.reliability is 'Confiabilidad en ese momento.';
comment on column costing.recipe_cost_snapshots.currency is 'Moneda. Solo ARS.';
comment on column costing.recipe_cost_snapshots.method_version is 'Versión del método de cálculo.';
comment on column costing.recipe_cost_snapshots.created_at is 'Cuándo se sacó (lo pone la base).';
comment on column costing.recipe_cost_snapshots.created_by is 'Vacío: la saca el proceso de la cola. Quién hizo el cambio está en la auditoría del precio, el rendimiento o la versión.';
comment on column costing.recipe_cost_snapshots.updated_at is 'Igual a created_at: la foto no cambia.';
comment on column costing.recipe_cost_snapshots.updated_by is 'Igual a created_by: la foto no cambia.';
comment on column costing.recipe_cost_snapshots.deleted_at is 'Siempre vacío: la foto no se da de baja.';
comment on column costing.recipe_cost_snapshots.deleted_by is 'Siempre vacío: la foto no se da de baja.';

create table costing.recipe_cost_snapshot_lines (
  id                     uuid primary key default gen_random_uuid(),
  group_id               uuid not null references org.groups (id) on delete restrict,
  restaurant_id          uuid not null references org.restaurants (id) on delete restrict,
  snapshot_id            uuid not null references costing.recipe_cost_snapshots (id) on delete restrict,
  recipe_version_id      uuid not null references recipes.recipe_versions (id) on delete restrict,
  line_order             integer not null,
  item                   text not null,
  ingredient_id          uuid references catalog.ingredients (id) on delete restrict,
  sub_recipe_id          uuid references recipes.recipes (id) on delete restrict,
  sub_recipe_version_id  uuid references recipes.recipe_versions (id) on delete restrict,
  quantity               numeric(18,6) not null,
  unit_id                uuid not null references catalog.units (id) on delete restrict,
  quantity_basis         recipes.quantity_basis not null,
  base_quantity          numeric(18,6),
  purchase_quantity      numeric(18,6),
  yield_profile_id       uuid references catalog.ingredient_yield_profiles (id) on delete restrict,
  cleaning_yield         numeric(7,4),
  cooking_factor         numeric(7,4),
  price_record_id        uuid references costing.price_records (id) on delete restrict,
  price_level            core.scope_type,
  package_base_quantity  numeric(18,6),
  vat_condition          org.vat_condition,
  unit_cost              numeric(20,8),
  gross_unit_cost        numeric(20,8),
  line_cost              numeric(18,4),
  line_gross_cost        numeric(18,4),
  share_pct              numeric(7,2),
  line_status            text not null check (line_status in ('ok', 'missing_conversion', 'invalid_quantity', 'unknown_ingredient', 'missing_yield',
                                                           'missing_price', 'missing_legal_entity', 'missing_sub_recipe',
                                                           'incomplete_sub_recipe')),
  created_at             timestamptz not null default now(),
  created_by             uuid references core.actors (id) on delete restrict,
  updated_at             timestamptz not null default now(),
  updated_by             uuid references core.actors (id) on delete restrict,
  deleted_at             timestamptz,
  deleted_by             uuid references core.actors (id) on delete restrict
);
create unique index recipe_cost_snapshot_lines_key on costing.recipe_cost_snapshot_lines (snapshot_id, line_order);
create index recipe_cost_snapshot_lines_group_idx on costing.recipe_cost_snapshot_lines (group_id);
create index recipe_cost_snapshot_lines_restaurant_idx on costing.recipe_cost_snapshot_lines (restaurant_id);
create index recipe_cost_snapshot_lines_ingredient_idx on costing.recipe_cost_snapshot_lines (ingredient_id) where ingredient_id is not null;
create index recipe_cost_snapshot_lines_sub_idx on costing.recipe_cost_snapshot_lines (sub_recipe_id) where sub_recipe_id is not null;
create index recipe_cost_snapshot_lines_sub_version_idx on costing.recipe_cost_snapshot_lines (sub_recipe_version_id) where sub_recipe_version_id is not null;
create index recipe_cost_snapshot_lines_version_idx on costing.recipe_cost_snapshot_lines (recipe_version_id);
create index recipe_cost_snapshot_lines_unit_idx on costing.recipe_cost_snapshot_lines (unit_id);
create index recipe_cost_snapshot_lines_yield_idx on costing.recipe_cost_snapshot_lines (yield_profile_id) where yield_profile_id is not null;
create index recipe_cost_snapshot_lines_price_idx on costing.recipe_cost_snapshot_lines (price_record_id) where price_record_id is not null;
comment on table costing.recipe_cost_snapshot_lines is
  'Detalle de una foto: cada línea con lo que no tiene versión (cantidad, rendimiento, precio, contenido del envase, condición frente al IVA y versión de la subreceta). Solo de inserción. Quien ve costos lee el costo de la línea; el precio y su origen no se exponen por la API.';
comment on column costing.recipe_cost_snapshot_lines.id is 'Identificador.';
comment on column costing.recipe_cost_snapshot_lines.group_id is 'Grupo de la receta.';
comment on column costing.recipe_cost_snapshot_lines.restaurant_id is 'Local de la foto.';
comment on column costing.recipe_cost_snapshot_lines.snapshot_id is 'Foto a la que pertenece.';
comment on column costing.recipe_cost_snapshot_lines.recipe_version_id is 'Versión de la foto. Una línea muestra la fórmula: la ve quien ve esa versión.';
comment on column costing.recipe_cost_snapshot_lines.line_order is 'Orden de la línea en la fórmula.';
comment on column costing.recipe_cost_snapshot_lines.item is 'Nombre de la materia prima o la preparación en ese momento.';
comment on column costing.recipe_cost_snapshot_lines.ingredient_id is 'Materia prima, si la línea es una.';
comment on column costing.recipe_cost_snapshot_lines.sub_recipe_id is 'Preparación, si la línea es una. Puede ser la variante del local.';
comment on column costing.recipe_cost_snapshot_lines.sub_recipe_version_id is 'Versión de la preparación que se usó.';
comment on column costing.recipe_cost_snapshot_lines.quantity is 'Cantidad de la línea.';
comment on column costing.recipe_cost_snapshot_lines.unit_id is 'Unidad de la cantidad.';
comment on column costing.recipe_cost_snapshot_lines.quantity_basis is 'Cómo va la cantidad: como se compra, limpia, cocida o terminada.';
comment on column costing.recipe_cost_snapshot_lines.base_quantity is 'Cantidad en la unidad de uso.';
comment on column costing.recipe_cost_snapshot_lines.purchase_quantity is 'Cantidad a comprar, después del rendimiento.';
comment on column costing.recipe_cost_snapshot_lines.yield_profile_id is 'Estándar de rendimiento aprobado que se usó.';
comment on column costing.recipe_cost_snapshot_lines.cleaning_yield is 'Rendimiento de limpieza usado.';
comment on column costing.recipe_cost_snapshot_lines.cooking_factor is 'Factor de cocción usado.';
comment on column costing.recipe_cost_snapshot_lines.price_record_id is 'Precio que se usó.';
comment on column costing.recipe_cost_snapshot_lines.price_level is 'De dónde vino el precio: local, marca o grupo.';
comment on column costing.recipe_cost_snapshot_lines.package_base_quantity is 'Contenido del envase de ese precio, en la unidad de uso.';
comment on column costing.recipe_cost_snapshot_lines.vat_condition is 'Condición frente al IVA del local en ese momento.';
comment on column costing.recipe_cost_snapshot_lines.unit_cost is 'Costo por unidad de uso, sin el IVA recuperable.';
comment on column costing.recipe_cost_snapshot_lines.gross_unit_cost is 'Costo por unidad de uso, con IVA.';
comment on column costing.recipe_cost_snapshot_lines.line_cost is 'Costo de la línea, sin el IVA recuperable.';
comment on column costing.recipe_cost_snapshot_lines.line_gross_cost is 'Costo de la línea, con IVA.';
comment on column costing.recipe_cost_snapshot_lines.share_pct is 'Participación de la línea en el costo total, en %.';
comment on column costing.recipe_cost_snapshot_lines.line_status is 'Estado: ok, o qué faltó (conversión, rendimiento, precio, razón social o preparación).';
comment on column costing.recipe_cost_snapshot_lines.created_at is 'Cuándo se sacó (lo pone la base).';
comment on column costing.recipe_cost_snapshot_lines.created_by is 'Vacío: la saca el proceso de la cola.';
comment on column costing.recipe_cost_snapshot_lines.updated_at is 'Igual a created_at: la línea no cambia.';
comment on column costing.recipe_cost_snapshot_lines.updated_by is 'Igual a created_by: la línea no cambia.';
comment on column costing.recipe_cost_snapshot_lines.deleted_at is 'Siempre vacío: la línea no se da de baja.';
comment on column costing.recipe_cost_snapshot_lines.deleted_by is 'Siempre vacío: la línea no se da de baja.';

alter table costing.recipe_cost_current enable row level security;
alter table costing.recipe_cost_snapshots enable row level security;
alter table costing.recipe_cost_snapshot_lines enable row level security;
revoke all on costing.recipe_cost_current, costing.recipe_cost_snapshots, costing.recipe_cost_snapshot_lines
  from public, anon, authenticated, service_role;
grant select on costing.recipe_cost_current, costing.recipe_cost_snapshots to authenticated;
-- De las líneas, solo lo que no es precio: el Chef ve costos de receta sin ver precios (ADR-0032).
grant select (id, group_id, restaurant_id, snapshot_id, recipe_version_id, line_order, item, ingredient_id, sub_recipe_id, sub_recipe_version_id,
              quantity, unit_id, quantity_basis, base_quantity, purchase_quantity, line_cost, line_gross_cost, share_pct,
              line_status, created_at)
  on costing.recipe_cost_snapshot_lines to authenticated;

create policy recipe_cost_current_select on costing.recipe_cost_current for select to authenticated
  using (deleted_at is null and restaurant_id in (select core.permitted_restaurant_ids('recipes.view_costs')));
create policy recipe_cost_snapshots_select on costing.recipe_cost_snapshots for select to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('recipes.view_costs')));
-- El detalle muestra la fórmula: además del costo, hay que ver esa versión.
create policy recipe_cost_snapshot_lines_select on costing.recipe_cost_snapshot_lines for select to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('recipes.view_costs'))
         and recipe_version_id in (select recipes.visible_version_ids()));

do $$
declare
  t text;
begin
  foreach t in array array['recipe_cost_current', 'recipe_cost_snapshots', 'recipe_cost_snapshot_lines'] loop
    execute format('create trigger set_control_columns before insert or update on costing.%I
                      for each row execute function core.set_control_columns()', t);
    execute format('create trigger reject_truncate before truncate on costing.%I
                      for each statement execute function core.reject_truncate()', t);
  end loop;
  foreach t in array array['recipe_cost_snapshots', 'recipe_cost_snapshot_lines'] loop
    execute format('create trigger reject_changes before update or delete on costing.%I
                      for each row execute function costing.reject_changes()', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. El motor
-- ---------------------------------------------------------------------------
-- Cuánto hay que comprar para llegar a una cantidad limpia o cocida. Vacío si falta el rendimiento.
create function costing.purchase_quantity(p_base numeric, p_basis text, p_cleaning numeric, p_cooking numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_basis
           when 'purchase' then p_base
           when 'clean' then case when p_cleaning > 0 then p_base / p_cleaning end
           when 'cooked' then case when p_cleaning > 0 and p_cooking > 0 then p_base / (p_cleaning * p_cooking) end
         end
$$;
comment on function costing.purchase_quantity(numeric, text, numeric, numeric) is
  'Interna: cantidad de compra. Como se compra: la misma; limpia: dividida por el rendimiento de limpieza; cocida: dividida por limpieza × cocción. Sin rendimiento, vacío: nunca supone 100 %.';
revoke execute on function costing.purchase_quantity(numeric, text, numeric, numeric) from public;

-- La misma cuenta que usa la receta.
create or replace function costing.ingredient_line_cost(p_ingredient_id uuid, p_restaurant_id uuid, p_quantity numeric, p_unit_id uuid,
                                                        p_basis text default 'purchase', p_process_id uuid default null,
                                                        p_as_of date default (now() at time zone 'America/Argentina/Buenos_Aires')::date)
returns table (base_quantity numeric, purchase_quantity numeric, unit_cost numeric, line_cost numeric, price_level text,
               inherited boolean, price_record_id uuid, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base   record;
  v_yield  record;
  v_qty    numeric;
  v_price  record;
begin
  perform org.require(core.has_permission('prices.view', p_restaurant_id)
                      and exists (select 1 from catalog.ingredients i join org.restaurants r on r.group_id = i.group_id
                                   where i.id = p_ingredient_id and r.id = p_restaurant_id),
                      'ver costos de este local');
  if p_basis is null or p_basis not in ('purchase', 'clean', 'cooked') then
    raise exception 'La cantidad va como se compra, limpia o cocida.' using errcode = '22023';
  end if;
  select b.base_quantity, b.status into v_base from catalog.to_base_quantity(p_ingredient_id, p_quantity, p_unit_id) b;
  if v_base.status <> 'ok' then
    return query select null::numeric, null::numeric, null::numeric, null::numeric, null::text, null::boolean, null::uuid,
                        v_base.status;
    return;
  end if;
  v_qty := v_base.base_quantity;
  if p_basis <> 'purchase' then
    select y.cleaning_yield, y.cooking_factor, y.status into v_yield
      from catalog.standard_yield(p_ingredient_id, p_process_id) y;
    v_qty := case when p_process_id is not null and v_yield.status = 'approved'
                  then costing.purchase_quantity(v_base.base_quantity, p_basis, v_yield.cleaning_yield, v_yield.cooking_factor) end;
    if v_qty is null then
      return query select v_base.base_quantity, null::numeric, null::numeric, null::numeric, null::text, null::boolean,
                          null::uuid, 'missing_yield'::text;
      return;
    end if;
  end if;
  select * into v_price from costing.resolve_price_internal(p_ingredient_id, p_restaurant_id, coalesce(p_as_of, (now() at time zone 'America/Argentina/Buenos_Aires')::date));
  return query select v_base.base_quantity, v_qty, v_price.unit_cost,
                      case when v_price.unit_cost is null then null else v_qty * v_price.unit_cost end,
                      v_price.price_level, v_price.inherited, v_price.price_record_id,
                      case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity'
                           else v_price.status end;
end
$$;

create function costing.fit(p_value numeric, p_limit numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$ select case when abs(p_value) < p_limit then p_value end $$;
comment on function costing.fit(numeric, numeric) is 'Interna: el valor si entra en la columna; si no, vacío.';
revoke execute on function costing.fit(numeric, numeric) from public;

-- Una línea y los totales, tal como salen del motor. Sin redondear: las subrecetas usan estos valores y se
-- redondea solo al guardar y al mostrar.
create type costing.recipe_cost_line as (
  component_id uuid, line_order integer, item text, ingredient_id uuid, sub_recipe_id uuid, sub_recipe_version_id uuid,
  quantity numeric, unit_id uuid, quantity_basis text, base_quantity numeric, purchase_quantity numeric,
  yield_profile_id uuid, cleaning_yield numeric, cooking_factor numeric, price_record_id uuid, price_level text,
  package_base_quantity numeric, vat_condition text, unit_cost numeric, gross_unit_cost numeric, line_cost numeric,
  line_gross_cost numeric, estimated boolean, stale boolean, status text);
comment on type costing.recipe_cost_line is
  'Interna: una línea calculada. Estados: ok, missing_conversion, missing_yield, missing_price, missing_legal_entity, missing_sub_recipe, incomplete_sub_recipe.';
create type costing.recipe_cost_total as (
  total_cost numeric, total_gross_cost numeric, cost_per_base_unit numeric, cost_per_portion numeric,
  reliability costing.cost_reliability);
comment on type costing.recipe_cost_total is 'Interna: los totales de una versión en un local.';

-- Los totales de una versión a partir de sus líneas. El total queda vacío si falta un dato.
create function costing.totals_of_lines(p_version_id uuid, p_lines costing.recipe_cost_line[])
returns costing.recipe_cost_total
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lines     bigint;
  v_bad       bigint;
  v_nogross   bigint;
  v_net       numeric;
  v_gross     numeric;
  v_stale     boolean;
  v_est       boolean;
  v_yield     numeric;
  v_portions  integer;
  v_cut       boolean;
  t           costing.recipe_cost_total;
begin
  select count(*), count(*) filter (where l.status <> 'ok' or l.line_cost is null), count(*) filter (where l.line_gross_cost is null),
         sum(l.line_cost), sum(l.line_gross_cost), coalesce(bool_or(l.stale), false), coalesce(bool_or(l.estimated), false)
    into v_lines, v_bad, v_nogross, v_net, v_gross, v_stale, v_est
    from unnest(p_lines) l;
  select v.yield_quantity * recipes.unit_to_base(v.yield_unit_id), v.portions into v_yield, v_portions
    from recipes.recipe_versions v where v.id = p_version_id;

  t.total_cost := case when v_lines > 0 and v_bad = 0 then v_net end;
  t.total_gross_cost := case when v_lines > 0 and v_nogross = 0 then v_gross end;
  t.cost_per_base_unit := case when v_yield > 0 then t.total_cost / v_yield end;
  t.cost_per_portion := case when v_portions > 0 then t.total_cost / v_portions end;
  -- Un valor absurdo (por ejemplo, un rendimiento de una millonésima de gramo) no entra en la columna: queda
  -- vacío, y el costo, incompleto. Nunca rompe un recálculo.
  v_cut := costing.fit(t.total_cost, 9e13) is distinct from t.total_cost
           or costing.fit(t.total_gross_cost, 9e13) is distinct from t.total_gross_cost
           or costing.fit(t.cost_per_base_unit, 9e11) is distinct from t.cost_per_base_unit
           or costing.fit(t.cost_per_portion, 9e13) is distinct from t.cost_per_portion;
  t.total_cost := costing.fit(t.total_cost, 9e13);
  t.total_gross_cost := costing.fit(t.total_gross_cost, 9e13);
  t.cost_per_base_unit := costing.fit(t.cost_per_base_unit, 9e11);
  t.cost_per_portion := costing.fit(t.cost_per_portion, 9e13);
  t.reliability := case when v_cut or t.total_cost is null or (t.cost_per_base_unit is null and t.cost_per_portion is null) then 'incomplete'
                        when v_stale then 'stale'
                        when v_est then 'estimated'
                        else 'verified' end::costing.cost_reliability;
  return t;
end
$$;
comment on function costing.totals_of_lines(uuid, costing.recipe_cost_line[]) is
  'Interna: costo total (con y sin IVA), por unidad base, por porción y confiabilidad, a partir de las líneas. Gana la peor línea; si falta algo, el total queda vacío.';
revoke execute on function costing.totals_of_lines(uuid, costing.recipe_cost_line[]) from public;

-- Se declara acá porque las líneas y los totales se llaman entre sí; el cuerpo está más abajo.
create function costing.recipe_line_costs_internal(p_version_id uuid, p_restaurant_id uuid, p_as_of date, p_memo jsonb default null)
returns setof costing.recipe_cost_line
language plpgsql
stable
security definer
set search_path = ''
as $$ begin end $$;

-- p_memo evita repetir cuentas al recalcular muchas recetas de un local: los precios del local y las
-- preparaciones ya calculadas, con todos sus decimales. Sin memo, el resultado es el mismo.
create function costing.recipe_totals_internal(p_version_id uuid, p_restaurant_id uuid, p_as_of date, p_memo jsonb default null)
returns costing.recipe_cost_total
language sql
stable
security definer
set search_path = ''
as $$
  select costing.totals_of_lines(p_version_id,
           array(select l from costing.recipe_line_costs_internal(p_version_id, p_restaurant_id, p_as_of, p_memo) l))
$$;
comment on function costing.recipe_totals_internal(uuid, uuid, date, jsonb) is
  'Interna: los totales de una versión en un local. Sin permisos: nunca se expone directo.';
revoke execute on function costing.recipe_totals_internal(uuid, uuid, date, jsonb) from public;

-- Las líneas. Una preparación entra por su costo terminado, así su merma ya viene adentro. Si el local
-- tiene una variante publicada de esa preparación, usa la variante (ADR-0025).
create or replace function costing.recipe_line_costs_internal(p_version_id uuid, p_restaurant_id uuid, p_as_of date, p_memo jsonb default null)
returns setof costing.recipe_cost_line
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c        record;
  l        costing.recipe_cost_line;
  v_vat    text;
  v_conv   record;
  v_prof   record;
  v_price  record;
  v_sub    record;
  v_tot    costing.recipe_cost_total;
  v_memo   jsonb;
  -- Las versiones que se están calculando: un círculo a través de una variante no se recorre.
  v_path   jsonb := coalesce(p_memo -> 'path', '[]'::jsonb) || to_jsonb(p_version_id::text);
begin
  select e.vat_condition::text into v_vat
    from org.restaurants r join org.legal_entities e on e.id = r.legal_entity_id and e.deleted_at is null
   where r.id = p_restaurant_id;

  for c in
    select x.id, x.line_order, x.ingredient_id, x.sub_recipe_id, x.quantity, x.unit_id, x.quantity_basis::text as basis,
           x.yield_profile_id, q.base_quantity as frozen, q.base_unit_id as frozen_unit, i.recipe_unit_id as use_unit,
           coalesce(i.name, s.name) as item, u.dimension as line_dimension
      from recipes.recipe_components x
      join catalog.units u on u.id = x.unit_id
      left join recipes.component_base_quantities q on q.recipe_component_id = x.id
      left join catalog.ingredients i on i.id = x.ingredient_id
      left join recipes.recipes s on s.id = x.sub_recipe_id
     where x.recipe_version_id = p_version_id and x.deleted_at is null
     order by x.line_order
  loop
    l := null;
    l.component_id := c.id; l.line_order := c.line_order; l.item := c.item; l.ingredient_id := c.ingredient_id;
    l.sub_recipe_id := c.sub_recipe_id; l.quantity := c.quantity; l.unit_id := c.unit_id; l.quantity_basis := c.basis;
    l.base_quantity := c.frozen; l.vat_condition := v_vat; l.estimated := false; l.stale := false; l.status := 'ok';

    if c.ingredient_id is not null then
      -- Lo publicado usa la cantidad congelada; un borrador, la conversión de hoy. Si la materia prima cambió
      -- de unidad de uso, la cantidad congelada ya no se puede multiplicar por su precio.
      if c.frozen is not null and c.frozen_unit is distinct from c.use_unit then
        l.status := 'missing_conversion';
      elsif l.base_quantity is null then
        select b.base_quantity, b.status into v_conv from catalog.to_base_quantity(c.ingredient_id, c.quantity, c.unit_id) b;
        l.base_quantity := v_conv.base_quantity;
        if v_conv.status <> 'ok' then
          l.status := v_conv.status;
        end if;
      end if;

      if l.status = 'ok' and c.basis <> 'purchase' then
        -- Siempre el estándar aprobado hoy para ese proceso, corte y proveedor (ADR-0024, respuesta 6).
        select p.process_id, p.cut, p.supplier_id into v_prof
          from catalog.ingredient_yield_profiles p where p.id = c.yield_profile_id;
        if found then
          select a.profile_id, a.cleaning_yield, a.cooking_factor into l.yield_profile_id, l.cleaning_yield, l.cooking_factor
            from catalog.approved_yield(c.ingredient_id, v_prof.process_id, v_prof.cut, v_prof.supplier_id) a;
        end if;
        if l.yield_profile_id is null then
          l.status := 'missing_yield';
        end if;
      end if;

      if l.status = 'ok' then
        l.purchase_quantity := costing.purchase_quantity(l.base_quantity, c.basis, l.cleaning_yield, l.cooking_factor);
        if l.purchase_quantity is null then
          l.status := 'missing_yield';
        end if;
      end if;

      if l.status = 'ok' then
        v_memo := p_memo -> 'prices' -> c.ingredient_id::text;
        if v_memo is not null then
          select * into v_price
            from jsonb_to_record(v_memo) as m (price_record_id uuid, price_level text, inherited boolean, gross_unit_cost numeric,
                                               unit_cost numeric, stale boolean, status text);
        else
          select * into v_price from costing.resolve_price_internal(c.ingredient_id, p_restaurant_id, p_as_of);
        end if;
        l.price_record_id := v_price.price_record_id;
        l.price_level := v_price.price_level;
        l.unit_cost := v_price.unit_cost;
        l.gross_unit_cost := v_price.gross_unit_cost;
        l.stale := coalesce(v_price.stale, false);
        l.estimated := coalesce(v_price.inherited, false);
        l.status := case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity' else v_price.status end;
        l.line_cost := l.purchase_quantity * l.unit_cost;
        l.line_gross_cost := l.purchase_quantity * l.gross_unit_cost;
        if l.price_record_id is not null then
          select r.base_quantity into l.package_base_quantity from costing.price_records r where r.id = l.price_record_id;
        end if;
      end if;
    else
      -- La variante del local, si está publicada; si no, la preparación de la línea.
      select v.id, v.recipe_id, r.name, v.yield_quantity * recipes.unit_to_base(v.yield_unit_id) as yield_base,
             yu.dimension as yield_dimension into v_sub
        from recipes.recipe_versions v
        join recipes.recipes r on r.id = v.recipe_id
        left join catalog.units yu on yu.id = v.yield_unit_id
       where v.status = 'published' and r.deleted_at is null
         and (r.id = c.sub_recipe_id
              or (r.variant_of_recipe_id = c.sub_recipe_id and r.restaurant_id = p_restaurant_id and r.is_active))
       order by r.variant_of_recipe_id is null
       limit 1;
      if not found then
        l.status := 'missing_sub_recipe';
      else
        l.sub_recipe_id := v_sub.recipe_id;
        l.sub_recipe_version_id := v_sub.id;
        l.item := v_sub.name;
        if l.base_quantity is null then
          l.base_quantity := c.quantity * recipes.unit_to_base(c.unit_id);
        end if;
        v_memo := p_memo -> 'subs' -> v_sub.id::text;
        if v_memo is not null then
          v_tot := jsonb_populate_record(null::costing.recipe_cost_total, v_memo);
        elsif v_path ? v_sub.id::text then
          v_tot := row(null, null, null, null, 'incomplete')::costing.recipe_cost_total;
        else
          v_tot := costing.recipe_totals_internal(v_sub.id, p_restaurant_id, p_as_of,
                                                  coalesce(p_memo, '{}'::jsonb) || jsonb_build_object('path', v_path));
        end if;
        l.estimated := v_tot.reliability = 'estimated';
        l.stale := v_tot.reliability = 'stale';
        -- Una variante puede rendir en otra dimensión o en un envase: no se adivina, queda incompleto.
        if coalesce(v_sub.yield_base, 0) <= 0 or l.base_quantity is null
           or v_sub.yield_dimension is distinct from c.line_dimension then
          l.status := 'missing_yield';
        else
          l.gross_unit_cost := v_tot.total_gross_cost / v_sub.yield_base;
          l.line_gross_cost := l.base_quantity * l.gross_unit_cost;
          if v_tot.total_cost is null or v_tot.reliability = 'incomplete' then
            l.status := 'incomplete_sub_recipe';
          else
            l.unit_cost := v_tot.total_cost / v_sub.yield_base;
            l.line_cost := l.base_quantity * l.unit_cost;
          end if;
        end if;
      end if;
    end if;
    return next l;
  end loop;
end
$$;
comment on function costing.recipe_line_costs_internal(uuid, uuid, date, jsonb) is
  'Interna: cada línea de una versión en un local, con la cantidad, el rendimiento aprobado, el precio y su costo. Nunca da $ 0. Sin permisos: nunca se expone directo.';
revoke execute on function costing.recipe_line_costs_internal(uuid, uuid, date, jsonb) from public;

-- Lo que puede leer la pantalla, también de un borrador. No devuelve precios ni de dónde salen.
create function costing.require_recipe_cost(p_version_id uuid, p_restaurant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission('recipes.view_costs', p_restaurant_id)
                      and recipes.can_see_version(p_version_id)
                      and exists (select 1 from recipes.recipe_versions v
                                    join recipes.recipes x on x.id = v.recipe_id
                                    join org.restaurants r on r.group_id = v.group_id
                                   where v.id = p_version_id and r.id = p_restaurant_id
                                     and (x.scope_type = 'group' or (x.scope_type = 'brand' and x.brand_id = r.brand_id)
                                          or (x.scope_type = 'restaurant' and x.restaurant_id = r.id))),
                      'ver el costo de esta receta en este local');
end
$$;
comment on function costing.require_recipe_cost(uuid, uuid) is
  'Interna: pide recipes.view_costs en el local, ver la versión y que el local esté al alcance de la receta.';
revoke execute on function costing.require_recipe_cost(uuid, uuid) from public;

create function costing.recipe_cost(p_version_id uuid, p_restaurant_id uuid)
returns table (total_cost numeric, total_gross_cost numeric, cost_per_base_unit numeric, cost_per_portion numeric,
               reliability costing.cost_reliability)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform costing.require_recipe_cost(p_version_id, p_restaurant_id);
  return query select round(t.total_cost, 4), round(t.total_gross_cost, 4), round(t.cost_per_base_unit, 8),
                      round(t.cost_per_portion, 4), t.reliability
                 from costing.recipe_totals_internal(p_version_id, p_restaurant_id, recipes.today()) t;
end
$$;
comment on function costing.recipe_cost(uuid, uuid) is
  'El costo de una versión (también de un borrador) en un local, con los precios de hoy. Pide recipes.view_costs en el local.';

create function costing.recipe_cost_lines(p_version_id uuid, p_restaurant_id uuid)
returns table (line_order integer, item text, ingredient_id uuid, sub_recipe_id uuid, quantity numeric, unit_id uuid,
               quantity_basis text, base_quantity numeric, line_cost numeric, line_gross_cost numeric, share_pct numeric,
               status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform costing.require_recipe_cost(p_version_id, p_restaurant_id);
  return query
    select l.line_order, l.item, l.ingredient_id, l.sub_recipe_id, l.quantity, l.unit_id, l.quantity_basis, round(l.base_quantity, 6),
           round(l.line_cost, 4), round(l.line_gross_cost, 4),
           case when count(*) over () = count(l.line_cost) over ()
                then round(l.line_cost / nullif(sum(l.line_cost) over (), 0) * 100, 2) end, l.status
      from costing.recipe_line_costs_internal(p_version_id, p_restaurant_id, recipes.today()) l
     order by l.line_order;
end
$$;
comment on function costing.recipe_cost_lines(uuid, uuid) is
  'El costo de cada línea de una versión en un local, sin precio, producto, proveedor ni comprobante: el Chef ve costos sin ver precios (ADR-0032). Pide recipes.view_costs en el local.';

revoke execute on function costing.recipe_cost(uuid, uuid), costing.recipe_cost_lines(uuid, uuid) from public;
grant execute on function costing.recipe_cost(uuid, uuid), costing.recipe_cost_lines(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. El recálculo
-- ---------------------------------------------------------------------------
-- Las recetas de arriba: las que usan a estas por sus versiones publicadas, también a través de una variante.
create function costing.recipes_above(p_recipe_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive up (recipe_id) as (
    select unnest(p_recipe_ids)
    union
    select x.recipe_id
      from up
      cross join lateral (
        select v.recipe_id
          from recipes.recipe_components c
          join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status = 'published'
         where c.sub_recipe_id = up.recipe_id and c.deleted_at is null
        union
        select r.variant_of_recipe_id from recipes.recipes r
         where r.id = up.recipe_id and r.variant_of_recipe_id is not null) x)
  select recipe_id from up
$$;
comment on function costing.recipes_above(uuid[]) is
  'Interna: esas recetas y las que las usan, por sus versiones publicadas (una variante cuenta como su maestra).';
revoke execute on function costing.recipes_above(uuid[]) from public;

-- Las de abajo: esa receta y las preparaciones que usa.
create function costing.recipes_below(p_recipe_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with recursive down (recipe_id) as (
    select p_recipe_id
    union
    select c.sub_recipe_id
      from down
      join recipes.recipe_versions v on v.recipe_id = down.recipe_id and v.status = 'published'
      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null and c.sub_recipe_id is not null)
  select array_agg(recipe_id) from down
$$;
comment on function costing.recipes_below(uuid) is 'Interna: esa receta y las preparaciones que usa, por sus versiones publicadas.';
revoke execute on function costing.recipes_below(uuid) from public;

-- Qué recetas usa hoy un local: las asignadas y las preparaciones que llevan, con su variante si la tiene.
create function costing.restaurant_recipes(p_restaurant_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive used (recipe_id) as (
    select a.recipe_id
      from recipes.recipe_assignments a
     where a.restaurant_id = p_restaurant_id and a.deleted_at is null
       and a.valid_from <= recipes.today() and (a.valid_to is null or a.valid_to > recipes.today())
    union
    select coalesce((select var.id
                       from recipes.recipes var
                       join recipes.recipe_versions vv on vv.recipe_id = var.id and vv.status = 'published'
                      where var.variant_of_recipe_id = c.sub_recipe_id and var.restaurant_id = p_restaurant_id
                        and var.is_active and var.deleted_at is null
                      limit 1), c.sub_recipe_id)
      from used
      join recipes.recipe_versions v on v.recipe_id = used.recipe_id and v.status = 'published'
      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null and c.sub_recipe_id is not null)
  select recipe_id from used
$$;
comment on function costing.restaurant_recipes(uuid) is
  'Interna: las recetas que usa hoy un local: las asignadas y sus preparaciones, con la variante del local si tiene una publicada.';
revoke execute on function costing.restaurant_recipes(uuid) from public;

-- Guarda el costo de una receta en un local. Si no cambió nada, no escribe: las fotos son solo de cambios.
create function costing.store_recipe_cost(p_recipe_id uuid, p_version_id uuid, p_group_id uuid, p_restaurant_id uuid,
                                          p_reason costing.cost_snapshot_reason, p_total costing.recipe_cost_total,
                                          p_lines costing.recipe_cost_line[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today    date := recipes.today();
  v_cur      record;
  v_total    numeric(18,4) := p_total.total_cost;
  v_gross    numeric(18,4) := p_total.total_gross_cost;
  v_unit     numeric(20,8) := p_total.cost_per_base_unit;
  v_portion  numeric(18,4) := p_total.cost_per_portion;
  v_reliable costing.cost_reliability := p_total.reliability;
  v_snapshot uuid;
begin
  select * into v_cur from costing.recipe_cost_current c
   where c.recipe_id = p_recipe_id and c.restaurant_id = p_restaurant_id and c.deleted_at is null;
  if found and v_cur.recipe_version_id = p_version_id and v_cur.total_cost is not distinct from v_total
     and v_cur.total_gross_cost is not distinct from v_gross and v_cur.cost_per_base_unit is not distinct from v_unit
     and v_cur.cost_per_portion is not distinct from v_portion and v_cur.reliability = v_reliable then
    return;
  end if;

  insert into costing.recipe_cost_current (group_id, restaurant_id, recipe_id, recipe_version_id, as_of, total_cost,
                                           total_gross_cost, cost_per_base_unit, cost_per_portion, reliability)
  values (p_group_id, p_restaurant_id, p_recipe_id, p_version_id, v_today, v_total, v_gross, v_unit, v_portion, v_reliable)
  on conflict (recipe_id, restaurant_id) where deleted_at is null
  do update set recipe_version_id = excluded.recipe_version_id, as_of = excluded.as_of, total_cost = excluded.total_cost,
                total_gross_cost = excluded.total_gross_cost, cost_per_base_unit = excluded.cost_per_base_unit,
                cost_per_portion = excluded.cost_per_portion, reliability = excluded.reliability;

  insert into costing.recipe_cost_snapshots (group_id, restaurant_id, recipe_id, recipe_version_id, as_of, reason, total_cost,
                                             total_gross_cost, cost_per_base_unit, cost_per_portion, reliability)
  values (p_group_id, p_restaurant_id, p_recipe_id, p_version_id, v_today, p_reason, v_total, v_gross, v_unit, v_portion, v_reliable)
  returning id into v_snapshot;

  insert into costing.recipe_cost_snapshot_lines (group_id, restaurant_id, snapshot_id, recipe_version_id, line_order, item, ingredient_id, sub_recipe_id,
                                                  sub_recipe_version_id, quantity, unit_id, quantity_basis, base_quantity,
                                                  purchase_quantity, yield_profile_id, cleaning_yield, cooking_factor, price_record_id,
                                                  price_level, package_base_quantity, vat_condition, unit_cost, gross_unit_cost,
                                                  line_cost, line_gross_cost, share_pct, line_status)
  select p_group_id, p_restaurant_id, v_snapshot, p_version_id, l.line_order, l.item, l.ingredient_id, l.sub_recipe_id,
         l.sub_recipe_version_id, l.quantity, l.unit_id, l.quantity_basis::recipes.quantity_basis, costing.fit(l.base_quantity, 9e11),
         costing.fit(l.purchase_quantity, 9e11), l.yield_profile_id, l.cleaning_yield, l.cooking_factor, l.price_record_id,
         l.price_level::core.scope_type, l.package_base_quantity, l.vat_condition::org.vat_condition, costing.fit(l.unit_cost, 9e11),
         costing.fit(l.gross_unit_cost, 9e11), costing.fit(l.line_cost, 9e13), costing.fit(l.line_gross_cost, 9e13),
         case when p_total.total_cost > 0 then round(l.line_cost / p_total.total_cost * 100, 2) end, l.status
    from unnest(p_lines) l;
end
$$;
comment on function costing.store_recipe_cost(uuid, uuid, uuid, uuid, costing.cost_snapshot_reason, costing.recipe_cost_total, costing.recipe_cost_line[]) is
  'Interna: guarda el costo vigente de una receta en un local y saca una foto, solo si cambió.';
revoke execute on function costing.store_recipe_cost(uuid, uuid, uuid, uuid, costing.cost_snapshot_reason, costing.recipe_cost_total, costing.recipe_cost_line[]) from public;

-- Recalcula esas recetas y las de arriba, local por local y de abajo hacia arriba. Los precios del local se traen
-- una vez, y cada preparación se calcula una vez y se reutiliza. Sin p_restaurant_ids (null): todos los locales abiertos.
create function costing.refresh_recipes(p_recipe_ids uuid[], p_restaurant_ids uuid[], p_reason costing.cost_snapshot_reason)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today    date := recipes.today();
  v_affected uuid[];
  v_group    uuid;
  v_rest     uuid;
  v_memo     jsonb;
  v_subs     jsonb;
  v_lines    costing.recipe_cost_line[];
  v_total    costing.recipe_cost_total;
  r          record;
begin
  if coalesce(cardinality(p_recipe_ids), 0) = 0 then
    return;
  end if;
  v_affected := array(select costing.recipes_above(p_recipe_ids));
  select x.group_id into v_group from recipes.recipes x where x.id = p_recipe_ids[1];

  for v_rest in
    select distinct a.restaurant_id
      from recipes.recipe_assignments a
      join org.restaurants x on x.id = a.restaurant_id and x.status = 'active' and x.deleted_at is null
     where a.group_id = v_group and a.deleted_at is null and (p_restaurant_ids is null or a.restaurant_id = any (p_restaurant_ids))
     order by a.restaurant_id
  loop
    select coalesce(jsonb_object_agg(p.ingredient_id,
                                     jsonb_build_object('price_record_id', p.price_record_id, 'price_level', p.price_level,
                                                        'inherited', p.inherited, 'gross_unit_cost', p.gross_unit_cost,
                                                        'unit_cost', p.unit_cost, 'stale', p.stale, 'status', p.status)), '{}')
      into v_memo
      from costing.price_rows(v_rest, v_today, null) p;
    v_subs := '{}';

    for r in
      select u.id as recipe_id, v.id as version_id, recipes.sub_depth(u.id) as depth, u.id = any (v_affected) as affected
        from costing.restaurant_recipes(v_rest) u (id)
        join recipes.recipe_versions v on v.recipe_id = u.id and v.status = 'published'
       order by 3, 1
    loop
      -- Lo que no cambió solo se calcula si es una preparación: la puede usar un plato de arriba.
      continue when not r.affected and not exists (select 1 from recipes.recipe_components c
                                                     where c.sub_recipe_id = r.recipe_id and c.deleted_at is null);
      v_lines := array(select l from costing.recipe_line_costs_internal(r.version_id, v_rest, v_today,
                                                                        jsonb_build_object('prices', v_memo, 'subs', v_subs)) l);
      v_total := costing.totals_of_lines(r.version_id, v_lines);
      v_subs := v_subs || jsonb_build_object(r.version_id::text, to_jsonb(v_total));
      if r.affected then
        perform costing.store_recipe_cost(r.recipe_id, r.version_id, v_group, v_rest, p_reason, v_total, v_lines);
      end if;
    end loop;

    -- Lo que el local ya no usa, o ya no tiene versión publicada, deja de tener costo vigente. La historia queda.
    update costing.recipe_cost_current c set deleted_at = now()
     where c.restaurant_id = v_rest and c.deleted_at is null
       and c.recipe_id not in (select u.id from costing.restaurant_recipes(v_rest) u (id)
                                 join recipes.recipe_versions v on v.recipe_id = u.id and v.status = 'published');
  end loop;
end
$$;
comment on function costing.refresh_recipes(uuid[], uuid[], costing.cost_snapshot_reason) is
  'Interna: recalcula esas recetas y las que las usan, local por local y de abajo hacia arriba, reutilizando precios y preparaciones.';
revoke execute on function costing.refresh_recipes(uuid[], uuid[], costing.cost_snapshot_reason) from public;

-- ---------------------------------------------------------------------------
-- 5. La cola: aprobar y publicar solo anotan el pedido. Un solo proceso recalcula, cada minuto (decisión de
--    Joaco): aprobar no depende de cuántas recetas hay, y dos recálculos nunca se pisan.
-- ---------------------------------------------------------------------------
create table costing.cost_recalc_queue (
  id              uuid primary key default gen_random_uuid(),
  entry_number    bigint generated always as identity,
  group_id        uuid not null references org.groups (id) on delete restrict,
  recipe_ids      uuid[] not null check (cardinality(recipe_ids) > 0),
  restaurant_ids  uuid[],
  reason          costing.cost_snapshot_reason not null,
  attempts        integer not null default 0 check (attempts >= 0),
  processed_at    timestamptz,
  error           text check (error is null or length(error) <= 500),
  created_at      timestamptz not null default now(),
  created_by      uuid references core.actors (id) on delete restrict,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references core.actors (id) on delete restrict,
  deleted_at      timestamptz,
  deleted_by      uuid references core.actors (id) on delete restrict
);
create index cost_recalc_queue_pending_idx on costing.cost_recalc_queue (entry_number) where processed_at is null;
create index cost_recalc_queue_group_idx on costing.cost_recalc_queue (group_id);
comment on table costing.cost_recalc_queue is
  'Pedidos de recálculo de costos. Los anotan los triggers al publicar, aprobar un precio o un rendimiento, asignar una receta o cambiar la razón social; los procesa costing.process_recalc_queue cada minuto. Interna: no se expone por la API.';
comment on column costing.cost_recalc_queue.id is 'Identificador.';
comment on column costing.cost_recalc_queue.entry_number is 'Orden de llegada.';
comment on column costing.cost_recalc_queue.group_id is 'Grupo de las recetas.';
comment on column costing.cost_recalc_queue.recipe_ids is 'Recetas por recalcular. También se recalculan las que las usan.';
comment on column costing.cost_recalc_queue.restaurant_ids is 'Locales por recalcular. Vacío: todos los que las usan.';
comment on column costing.cost_recalc_queue.reason is 'Qué lo causó. Es el motivo de la foto.';
comment on column costing.cost_recalc_queue.attempts is 'Intentos fallidos. Con 3, deja de intentarse y hay que mirar el error.';
comment on column costing.cost_recalc_queue.processed_at is 'Cuándo se procesó. Vacío: pendiente.';
comment on column costing.cost_recalc_queue.error is 'El último error, si falló.';
comment on column costing.cost_recalc_queue.created_at is 'Cuándo se anotó (lo pone la base).';
comment on column costing.cost_recalc_queue.created_by is 'Quién hizo el cambio (lo pone la base).';
comment on column costing.cost_recalc_queue.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column costing.cost_recalc_queue.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column costing.cost_recalc_queue.deleted_at is 'Baja lógica. No se usa.';
comment on column costing.cost_recalc_queue.deleted_by is 'Quién la dio de baja (lo pone la base).';

alter table costing.cost_recalc_queue enable row level security;
revoke all on costing.cost_recalc_queue from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on costing.cost_recalc_queue
  for each row execute function core.set_control_columns();
create trigger reject_truncate before truncate on costing.cost_recalc_queue
  for each statement execute function core.reject_truncate();

create function costing.enqueue_recalc(p_recipe_ids uuid[], p_restaurant_ids uuid[], p_reason costing.cost_snapshot_reason)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into costing.cost_recalc_queue (group_id, recipe_ids, restaurant_ids, reason)
  select r.group_id, p_recipe_ids, p_restaurant_ids, p_reason from recipes.recipes r where r.id = p_recipe_ids[1]
$$;
comment on function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason) is
  'Interna: anota un pedido de recálculo. Sin recetas, no hace nada.';
revoke execute on function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason) from public;

-- Los pedidos pendientes se juntan por grupo y motivo: una tanda de precios recalcula una sola vez. Si una tanda
-- falla, se prueba pedido por pedido: los sanos pasan, y el que falla guarda el error y se reintenta hasta 3 veces.
create function costing.process_recalc_queue(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  b      record;
  r      record;
  v_done integer := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('costing.process_recalc_queue')) then
    return 0;
  end if;
  for b in
    with pending as (
      select q.* from costing.cost_recalc_queue q
       where q.processed_at is null and q.attempts < 3
       order by q.entry_number
       limit p_limit)
    select p.group_id, p.reason, min(p.entry_number) as first_entry, array_agg(p.id) as ids,
           (select array_agg(distinct x) from pending o cross join lateral unnest(o.recipe_ids) x
             where o.group_id = p.group_id and o.reason = p.reason) as recipe_ids,
           case when not bool_or(p.restaurant_ids is null)
                then (select coalesce(array_agg(distinct x), '{}') from pending o cross join lateral unnest(o.restaurant_ids) x
                       where o.group_id = p.group_id and o.reason = p.reason) end as restaurant_ids
      from pending p
     group by p.group_id, p.reason
     order by 3
  loop
    begin
      perform costing.refresh_recipes(b.recipe_ids, b.restaurant_ids, b.reason);
      update costing.cost_recalc_queue set processed_at = now(), error = null where id = any (b.ids);
      v_done := v_done + cardinality(b.ids);
    exception when others then
      for r in select x.id, x.recipe_ids, x.restaurant_ids, x.reason from costing.cost_recalc_queue x
                where x.id = any (b.ids) order by x.entry_number loop
        begin
          perform costing.refresh_recipes(r.recipe_ids, r.restaurant_ids, r.reason);
          update costing.cost_recalc_queue set processed_at = now(), error = null where id = r.id;
          v_done := v_done + 1;
        exception when others then
          update costing.cost_recalc_queue set attempts = attempts + 1, error = left(sqlerrm, 500) where id = r.id;
        end;
      end loop;
    end;
  end loop;
  return v_done;
end
$$;
comment on function costing.process_recalc_queue(integer) is
  'Procesa los pedidos de recálculo pendientes. La corre pg_cron cada minuto; un solo proceso a la vez. Devuelve cuántos pedidos procesó.';
revoke execute on function costing.process_recalc_queue(integer) from public;

-- Con su propio límite de tiempo: una corrida cortada no se registra como error y se reintenta entera.
select cron.schedule('grupo-lf-recalcular-costos', '* * * * *',
                     $$set statement_timeout = '10min'; select costing.process_recalc_queue()$$);

-- ---------------------------------------------------------------------------
-- 6. Qué anota un pedido
-- ---------------------------------------------------------------------------
-- Las recetas publicadas que usan una materia prima.
create function costing.recipes_using_ingredient(p_ingredient_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_agg(distinct v.recipe_id)
    from recipes.recipe_components c
    join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status = 'published'
   where c.ingredient_id = p_ingredient_id and c.deleted_at is null
$$;
comment on function costing.recipes_using_ingredient(uuid) is 'Interna: las recetas con una versión publicada que usa esa materia prima.';
revoke execute on function costing.recipes_using_ingredient(uuid) from public;

-- Se publicó una versión: se congelan las cantidades, en la misma transacción. El costo se recalcula con la cola:
-- la receta, sus preparaciones (por si un local las usa recién ahora) y los platos que la usan. Se archivó:
-- los platos que la usan quedan sin esa preparación.
create function costing.on_version_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'published' then
    perform recipes.freeze_base_quantities(new.id);
    perform costing.enqueue_recalc(costing.recipes_below(new.recipe_id), null, 'publish');
  else
    perform costing.enqueue_recalc(array[new.recipe_id], null, 'publish');
  end if;
  return null;
end
$$;
comment on function costing.on_version_status() is
  'Trigger de recipe_versions: al publicar, congela las cantidades; al publicar o archivar, anota el recálculo.';
revoke execute on function costing.on_version_status() from public;
create trigger recalculate_costs after update of status on recipes.recipe_versions
  for each row when (new.status in ('published', 'archived') and old.status is distinct from new.status)
  execute function costing.on_version_status();

-- Se aprobó un precio. Uno con fecha futura todavía no vale: no cambia nada hoy.
create function costing.on_price_recorded()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ingredient uuid;
  v_places     uuid[];
begin
  if new.valid_from > recipes.today() then
    return null;
  end if;
  select p.ingredient_id into v_ingredient from catalog.purchase_products p where p.id = new.purchase_product_id;
  v_places := case new.scope_type
                when 'restaurant' then array[new.restaurant_id]
                when 'brand' then array(select r.id from org.restaurants r where r.brand_id = new.brand_id)
              end;
  perform costing.enqueue_recalc(costing.recipes_using_ingredient(v_ingredient), v_places, 'price_change');
  return null;
end
$$;
comment on function costing.on_price_recorded() is
  'Trigger de price_records: al aprobar un precio, anota el recálculo de las recetas que usan esa materia prima en los locales de ese alcance.';
revoke execute on function costing.on_price_recorded() from public;
create trigger recalculate_costs after insert on costing.price_records
  for each row execute function costing.on_price_recorded();

-- Se aprobó un rendimiento.
create function costing.on_yield_approved()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.enqueue_recalc(costing.recipes_using_ingredient(new.ingredient_id), null, 'yield_change');
  return null;
end
$$;
comment on function costing.on_yield_approved() is
  'Trigger de ingredient_yield_profiles: al aprobar un estándar, anota el recálculo de las recetas que usan esa materia prima.';
revoke execute on function costing.on_yield_approved() from public;
create trigger recalculate_costs after insert or update of status on catalog.ingredient_yield_profiles
  for each row when (new.status = 'approved')
  execute function costing.on_yield_approved();

-- Se asignó una receta a un local, o dejó de usarse ahí.
create function costing.on_recipe_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.enqueue_recalc(costing.recipes_below(new.recipe_id), array[new.restaurant_id], 'assignment');
  return null;
end
$$;
comment on function costing.on_recipe_assignment() is
  'Trigger de recipe_assignments: anota el recálculo de la receta y sus preparaciones en ese local.';
revoke execute on function costing.on_recipe_assignment() from public;
create trigger recalculate_costs after insert or update on recipes.recipe_assignments
  for each row execute function costing.on_recipe_assignment();

-- Cambió la razón social de un local, o la condición frente al IVA de una razón social.
create function costing.enqueue_restaurant(p_restaurant_id uuid, p_reason costing.cost_snapshot_reason)
returns void
language sql
security definer
set search_path = ''
as $$
  select costing.enqueue_recalc(array(select costing.restaurant_recipes(p_restaurant_id)), array[p_restaurant_id], p_reason)
$$;
comment on function costing.enqueue_restaurant(uuid, costing.cost_snapshot_reason) is 'Interna: anota el recálculo de todo lo que usa un local, también las preparaciones.';
revoke execute on function costing.enqueue_restaurant(uuid, costing.cost_snapshot_reason) from public;

create function costing.on_restaurant_legal_entity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.enqueue_restaurant(new.id, 'legal_entity_change');
  return null;
end
$$;
comment on function costing.on_restaurant_legal_entity() is 'Trigger de org.restaurants: la razón social decide si el IVA se recupera.';
revoke execute on function costing.on_restaurant_legal_entity() from public;
create trigger recalculate_costs after update of legal_entity_id on org.restaurants
  for each row when (new.legal_entity_id is distinct from old.legal_entity_id)
  execute function costing.on_restaurant_legal_entity();

create function costing.on_legal_entity_vat()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.enqueue_restaurant(r.id, 'legal_entity_change') from org.restaurants r where r.legal_entity_id = new.id and r.deleted_at is null;
  return null;
end
$$;
comment on function costing.on_legal_entity_vat() is 'Trigger de org.legal_entities: la condición frente al IVA decide si el IVA se recupera.';
revoke execute on function costing.on_legal_entity_vat() from public;
create trigger recalculate_costs after update of vat_condition on org.legal_entities
  for each row when (new.vat_condition is distinct from old.vat_condition)
  execute function costing.on_legal_entity_vat();

-- Se reabrió un local: mientras estuvo cerrado no se recalculó.
create function costing.on_restaurant_reopened()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.enqueue_restaurant(new.id, 'restaurant_reopened');
  return null;
end
$$;
comment on function costing.on_restaurant_reopened() is 'Trigger de org.restaurants: un local cerrado no se recalcula; al reabrir, se pone al día.';
revoke execute on function costing.on_restaurant_reopened() from public;
create trigger recalculate_costs_reopened after update of status on org.restaurants
  for each row when (new.status = 'active' and old.status is distinct from 'active')
  execute function costing.on_restaurant_reopened();

-- Lo que ya estaba publicado: se congela y se anota, por grupo (en desarrollo no hay nada; el seed corre después).
do $$
declare
  v record;
begin
  perform core.set_change_context('Motor de costos: cantidades de lo ya publicado', 'maintenance');
  for v in select id from recipes.recipe_versions where status = 'published' loop
    perform recipes.freeze_base_quantities(v.id);
  end loop;
  for v in select group_id, array_agg(distinct recipe_id) as recipe_ids from recipes.recipe_versions
            where status = 'published' group by group_id loop
    perform costing.enqueue_recalc(v.recipe_ids, null, 'publish');
  end loop;
end
$$;
