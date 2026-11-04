-- Fase 2 · Etapa 2.3, PR 3C: escenarios de costo (ADR-0032; sección 12 del documento de Soy).
-- Un escenario guarda solo los cambios (precio, rendimiento y gramaje; un proveedor se simula como un precio) y se
-- calcula al abrirlo, con funciones que solo leen: nunca toca el costo vigente, las fotos, la cola ni los eventos.

create type costing.scenario_status as enum ('active', 'archived');
comment on type costing.scenario_status is 'Estado de un escenario: activo o archivado. Nada se borra.';
create type costing.scenario_override_kind as enum ('price', 'yield', 'quantity');
comment on type costing.scenario_override_kind is
  'Qué cambia un escenario: el precio de una materia prima (también si se simula otro proveedor), su rendimiento, o el gramaje de una línea.';

create table costing.cost_scenarios (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  restaurant_id  uuid not null,
  name           text not null check (length(btrim(name)) between 1 and 120),
  status         costing.scenario_status not null default 'active',
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint cost_scenarios_restaurant_fkey foreign key (restaurant_id, group_id) references org.restaurants (id, group_id) on delete restrict,
  constraint cost_scenarios_id_place_key unique (id, restaurant_id, group_id)
);
create index cost_scenarios_group_idx on costing.cost_scenarios (group_id);
create index cost_scenarios_restaurant_idx on costing.cost_scenarios (restaurant_id, status);
comment on table costing.cost_scenarios is
  'Simulaciones de costo de un local. Guardan solo los cambios: el resultado se calcula al abrirlas y nunca toca lo oficial.';
comment on column costing.cost_scenarios.id is 'Identificador.';
comment on column costing.cost_scenarios.group_id is 'Grupo del local.';
comment on column costing.cost_scenarios.restaurant_id is 'Local: el costo depende del local.';
comment on column costing.cost_scenarios.name is 'Nombre del escenario.';
comment on column costing.cost_scenarios.status is 'Activo o archivado.';
comment on column costing.cost_scenarios.created_at is 'Cuándo se creó (lo pone la base).';
comment on column costing.cost_scenarios.created_by is 'Quién lo creó (lo pone la base).';
comment on column costing.cost_scenarios.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column costing.cost_scenarios.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column costing.cost_scenarios.deleted_at is 'Baja lógica. No se usa: un escenario se archiva.';
comment on column costing.cost_scenarios.deleted_by is 'Quién lo dio de baja (lo pone la base).';

create table costing.cost_scenario_overrides (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  restaurant_id        uuid not null,
  scenario_id          uuid not null,
  kind                 costing.scenario_override_kind not null,
  ingredient_id        uuid references catalog.ingredients (id) on delete restrict,
  recipe_component_id  uuid references recipes.recipe_components (id) on delete restrict,
  unit_cost            numeric(20,8) check (unit_cost is null or (unit_cost > 0 and unit_cost < 1000000000 and unit_cost <> 'NaN')),
  supplier_id          uuid references catalog.suppliers (id) on delete restrict,
  cleaning_yield       numeric(7,4) check (cleaning_yield is null or (cleaning_yield > 0 and cleaning_yield <= 1)),
  cooking_factor       numeric(7,4) check (cooking_factor is null or (cooking_factor > 0 and cooking_factor <= 10)),
  quantity             numeric(18,6) check (quantity is null or (quantity > 0 and quantity < 1000000000 and quantity <> 'NaN')),
  currency             text not null default 'ARS' check (currency = 'ARS'),
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict,
  constraint cost_scenario_overrides_scenario_fkey foreign key (scenario_id, restaurant_id, group_id)
    references costing.cost_scenarios (id, restaurant_id, group_id) on delete restrict,
  constraint cost_scenario_overrides_kind_check check (
    (kind = 'price' and ingredient_id is not null and unit_cost is not null and recipe_component_id is null and quantity is null
     and cleaning_yield is null and cooking_factor is null)
    or (kind = 'yield' and ingredient_id is not null and cleaning_yield is not null and cooking_factor is not null
        and recipe_component_id is null and quantity is null and unit_cost is null and supplier_id is null)
    or (kind = 'quantity' and recipe_component_id is not null and quantity is not null and ingredient_id is null
        and unit_cost is null and supplier_id is null and cleaning_yield is null and cooking_factor is null))
);
create unique index cost_scenario_overrides_ingredient_key on costing.cost_scenario_overrides (scenario_id, kind, ingredient_id)
  where deleted_at is null and ingredient_id is not null;
create unique index cost_scenario_overrides_line_key on costing.cost_scenario_overrides (scenario_id, recipe_component_id)
  where deleted_at is null and recipe_component_id is not null;
create index cost_scenario_overrides_group_idx on costing.cost_scenario_overrides (group_id);
create index cost_scenario_overrides_restaurant_idx on costing.cost_scenario_overrides (restaurant_id);
create index cost_scenario_overrides_scenario_idx on costing.cost_scenario_overrides (scenario_id);
create index cost_scenario_overrides_ingredient_idx on costing.cost_scenario_overrides (ingredient_id) where ingredient_id is not null;
create index cost_scenario_overrides_component_idx on costing.cost_scenario_overrides (recipe_component_id) where recipe_component_id is not null;
create index cost_scenario_overrides_supplier_idx on costing.cost_scenario_overrides (supplier_id) where supplier_id is not null;
comment on table costing.cost_scenario_overrides is
  'Lo que cambia un escenario. Un cambio vigente por materia prima y tipo, o por línea. Interna: sin política, se lee y se escribe por funciones.';
comment on column costing.cost_scenario_overrides.id is 'Identificador.';
comment on column costing.cost_scenario_overrides.group_id is 'Grupo del escenario.';
comment on column costing.cost_scenario_overrides.restaurant_id is 'Local del escenario: la auditoría toma de acá el alcance.';
comment on column costing.cost_scenario_overrides.scenario_id is 'Escenario.';
comment on column costing.cost_scenario_overrides.kind is 'Qué cambia: precio, rendimiento o gramaje.';
comment on column costing.cost_scenario_overrides.ingredient_id is 'Materia prima, si cambia su precio o su rendimiento.';
comment on column costing.cost_scenario_overrides.recipe_component_id is 'Línea de una receta, si cambia el gramaje.';
comment on column costing.cost_scenario_overrides.unit_cost is 'Costo simulado por unidad de uso: el que cuenta en el local (sin IVA, o con IVA si no lo descuenta).';
comment on column costing.cost_scenario_overrides.currency is 'Moneda del costo simulado.';
comment on column costing.cost_scenario_overrides.supplier_id is 'Proveedor de referencia, si se simula comprarle a otro. No calcula nada.';
comment on column costing.cost_scenario_overrides.cleaning_yield is 'Rendimiento de limpieza simulado.';
comment on column costing.cost_scenario_overrides.cooking_factor is 'Factor de cocción simulado.';
comment on column costing.cost_scenario_overrides.quantity is 'Cantidad simulada, en la unidad de la línea.';
comment on column costing.cost_scenario_overrides.created_at is 'Cuándo se cargó (lo pone la base).';
comment on column costing.cost_scenario_overrides.created_by is 'Quién lo cargó (lo pone la base).';
comment on column costing.cost_scenario_overrides.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column costing.cost_scenario_overrides.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column costing.cost_scenario_overrides.deleted_at is 'Baja lógica: el cambio se quitó del escenario.';
comment on column costing.cost_scenario_overrides.deleted_by is 'Quién lo quitó (lo pone la base).';

alter table costing.cost_scenarios enable row level security;
alter table costing.cost_scenario_overrides enable row level security;
revoke all on costing.cost_scenarios, costing.cost_scenario_overrides from public, anon, authenticated, service_role;
grant select on costing.cost_scenarios to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['cost_scenarios', 'cost_scenario_overrides'] loop
    execute format('create trigger set_control_columns before insert or update on costing.%I
                      for each row execute function core.set_control_columns()', t);
    execute format('create trigger log_change after insert or update or delete on costing.%I
                      for each row execute function audit.log_change()', t);
    execute format('create trigger reject_truncate before truncate on costing.%I
                      for each statement execute function core.reject_truncate()', t);
  end loop;
end
$$;

-- Escenarios: quien los maneja y ve costos en ese local.
create policy cost_scenarios_select on costing.cost_scenarios for select to authenticated
  using (deleted_at is null
         and restaurant_id in (select core.permitted_restaurant_ids('scenarios.manage'))
         and restaurant_id in (select core.permitted_restaurant_ids('recipes.view_costs')));

create function costing.require_scenario(p_scenario_id uuid, p_active boolean default false)
returns costing.cost_scenarios
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v costing.cost_scenarios;
begin
  select * into v from costing.cost_scenarios where id = p_scenario_id and deleted_at is null;
  perform org.require(found and core.has_permission('scenarios.manage', v.restaurant_id)
                      and core.has_permission('recipes.view_costs', v.restaurant_id), 'usar este escenario');
  if p_active and v.status <> 'active' then
    raise exception 'Este escenario está archivado.' using errcode = '22023';
  end if;
  return v;
end
$$;
comment on function costing.require_scenario(uuid, boolean) is
  'Interna: pide scenarios.manage y recipes.view_costs en el local del escenario. Con p_active, que no esté archivado.';
revoke execute on function costing.require_scenario(uuid, boolean) from public;

create function costing.create_scenario(p_restaurant_id uuid, p_name text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
  v_id    uuid;
begin
  perform org.require(core.has_permission('scenarios.manage', p_restaurant_id)
                      and core.has_permission('recipes.view_costs', p_restaurant_id), 'crear escenarios en este local');
  select r.group_id into v_group from org.restaurants r where r.id = p_restaurant_id and r.deleted_at is null;
  perform core.set_change_context(p_reason, 'manual');
  insert into costing.cost_scenarios (group_id, restaurant_id, name)
  values (v_group, p_restaurant_id, btrim(p_name))
  returning id into v_id;
  return v_id;
exception when check_violation or not_null_violation then
  raise exception 'Escribí un nombre de hasta 120 caracteres.' using errcode = '22023';
end
$$;
comment on function costing.create_scenario(uuid, text, text) is 'Crea un escenario de costo en un local. Pide scenarios.manage y recipes.view_costs.';

create function costing.archive_scenario(p_scenario_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.require_scenario(p_scenario_id, true);
  perform core.set_change_context(p_reason, 'manual');
  update costing.cost_scenarios set status = 'archived' where id = p_scenario_id;
end
$$;
comment on function costing.archive_scenario(uuid, text) is 'Archiva un escenario. Nada se borra.';

-- Un cambio por materia prima y tipo, o por línea: cargar otro reemplaza al anterior.
create function costing.set_scenario_override(p_scenario_id uuid, p_kind text, p_reason text, p_ingredient_id uuid default null,
                                              p_recipe_component_id uuid default null, p_unit_cost numeric default null,
                                              p_supplier_id uuid default null, p_cleaning_yield numeric default null,
                                              p_cooking_factor numeric default null, p_quantity numeric default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s costing.cost_scenarios;
begin
  perform costing.require_scenario(p_scenario_id);
  -- Dos cargas a la vez se ordenan, y un escenario que se está archivando no recibe cambios.
  perform 1 from costing.cost_scenarios x where x.id = p_scenario_id for update;
  s := costing.require_scenario(p_scenario_id, true);
  if p_kind is null or p_kind not in ('price', 'yield', 'quantity') then
    raise exception 'Elegí qué cambia: precio, rendimiento o gramaje.' using errcode = '22023';
  end if;
  if p_ingredient_id is not null
     and not exists (select 1 from catalog.ingredients i where i.id = p_ingredient_id and i.group_id = s.group_id and i.deleted_at is null) then
    raise exception 'Elegí una materia prima del grupo.' using errcode = '22023';
  end if;
  if p_supplier_id is not null
     and not exists (select 1 from catalog.suppliers x where x.id = p_supplier_id and x.group_id = s.group_id and x.deleted_at is null) then
    raise exception 'Elegí un proveedor del grupo.' using errcode = '22023';
  end if;
  -- Una línea de la versión vigente de una receta que este local usa y la persona ve.
  if p_recipe_component_id is not null
     and not exists (select 1 from recipes.recipe_components c
                       join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status = 'published'
                      where c.id = p_recipe_component_id and c.deleted_at is null
                        and v.recipe_id in (select costing.restaurant_recipes(s.restaurant_id))
                        and v.recipe_id in (select costing.visible_recipe_ids())) then
    raise exception 'Elegí una línea de una receta vigente de este local.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update costing.cost_scenario_overrides o set deleted_at = now()
   where o.scenario_id = p_scenario_id and o.deleted_at is null and o.kind = p_kind::costing.scenario_override_kind
     and (o.ingredient_id = p_ingredient_id or o.recipe_component_id = p_recipe_component_id);
  insert into costing.cost_scenario_overrides (group_id, restaurant_id, scenario_id, kind, ingredient_id, recipe_component_id, unit_cost,
                                               supplier_id, cleaning_yield, cooking_factor, quantity)
  values (s.group_id, s.restaurant_id, p_scenario_id, p_kind::costing.scenario_override_kind, p_ingredient_id, p_recipe_component_id, p_unit_cost,
          p_supplier_id, p_cleaning_yield, p_cooking_factor, p_quantity);
exception when check_violation or not_null_violation or numeric_value_out_of_range then
  raise exception 'Revisá los datos del cambio: el valor tiene que ser mayor que cero y menor que mil millones; la limpieza, hasta 100 %%; y el factor de cocción, hasta 10.' using errcode = '22023';
end
$$;
comment on function costing.set_scenario_override(uuid, text, text, uuid, uuid, numeric, uuid, numeric, numeric, numeric) is
  'Carga un cambio en un escenario: precio, rendimiento o gramaje. Si ya había uno igual, lo reemplaza.';

create function costing.remove_scenario_override(p_override_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scenario uuid;
begin
  select o.scenario_id into v_scenario from costing.cost_scenario_overrides o where o.id = p_override_id and o.deleted_at is null;
  perform costing.require_scenario(v_scenario, true);
  perform core.set_change_context(p_reason, 'manual');
  update costing.cost_scenario_overrides set deleted_at = now() where id = p_override_id;
end
$$;
comment on function costing.remove_scenario_override(uuid, text) is 'Quita un cambio de un escenario.';

-- ---------------------------------------------------------------------------
-- El motor: rendimientos y gramajes simulados. Sin esas claves en p_memo, da lo mismo que antes.
-- ---------------------------------------------------------------------------
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
  v_new    numeric;
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

    -- Un escenario cambia el gramaje de una línea: la cantidad congelada se ajusta en la misma proporción.
    v_new := (p_memo -> 'quantities' ->> c.id::text)::numeric;
    if v_new is not null then
      l.quantity := v_new;
      l.base_quantity := c.frozen * v_new / nullif(c.quantity, 0);
    end if;

    if c.ingredient_id is not null then
      -- Lo publicado usa la cantidad congelada; un borrador, la conversión de hoy. Si la materia prima cambió
      -- de unidad de uso, la cantidad congelada ya no se puede multiplicar por su precio.
      if c.frozen is not null and c.frozen_unit is distinct from c.use_unit then
        l.status := 'missing_conversion';
      elsif l.base_quantity is null then
        select b.base_quantity, b.status into v_conv from catalog.to_base_quantity(c.ingredient_id, l.quantity, c.unit_id) b;
        l.base_quantity := v_conv.base_quantity;
        if v_conv.status <> 'ok' then
          l.status := v_conv.status;
        end if;
      end if;

      if l.status = 'ok' and c.basis <> 'purchase' then
        v_memo := p_memo -> 'yields' -> c.ingredient_id::text;
        if v_memo is not null then
          -- Un escenario simula otro rendimiento.
          l.cleaning_yield := (v_memo ->> 'cleaning_yield')::numeric;
          l.cooking_factor := (v_memo ->> 'cooking_factor')::numeric;
        else
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
          l.base_quantity := l.quantity * recipes.unit_to_base(c.unit_id);
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

-- Los cambios de un escenario, para la pantalla. Lo que la persona no ve se tapa: el cambio queda, para poder quitarlo.
create function costing.scenario_changes(p_scenario_id uuid)
returns table (id uuid, kind text, item text, recipe text, unit text, unit_cost numeric, supplier text, cleaning_yield numeric,
               cooking_factor numeric, quantity numeric, original_quantity numeric, applies boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s         costing.cost_scenarios;
  v_catalog boolean;
begin
  s := costing.require_scenario(p_scenario_id);
  v_catalog := s.group_id in (select core.visible_group_ids('catalog.view'));
  return query
    with seen as (select costing.visible_recipe_ids() as recipe_id)
    select o.id, o.kind::text,
           case when o.recipe_component_id is not null then
                  case when seen.recipe_id is not null then coalesce(ci.name, sr.name) else 'No disponible' end
                when v_catalog then i.name
                else 'No disponible' end,
           case when o.recipe_component_id is null then null
                when seen.recipe_id is not null then r.name
                else 'Receta no disponible' end,
           coalesce(u.code, cu.name), o.unit_cost,
           case when x.id is null then null when v_catalog then x.name else 'No disponible' end,
           o.cleaning_yield, o.cooking_factor, o.quantity,
           case when seen.recipe_id is not null then c.quantity end,
           o.recipe_component_id is null or v.status = 'published'
      from costing.cost_scenario_overrides o
      left join catalog.ingredients i on i.id = o.ingredient_id
      left join catalog.units u on u.id = i.recipe_unit_id
      left join catalog.suppliers x on x.id = o.supplier_id
      left join recipes.recipe_components c on c.id = o.recipe_component_id
      left join catalog.units cu on cu.id = c.unit_id
      left join catalog.ingredients ci on ci.id = c.ingredient_id
      left join recipes.recipes sr on sr.id = c.sub_recipe_id
      left join recipes.recipe_versions v on v.id = c.recipe_version_id
      left join recipes.recipes r on r.id = v.recipe_id
      left join seen on seen.recipe_id = v.recipe_id
     where o.scenario_id = p_scenario_id and o.deleted_at is null
     order by o.created_at, o.id;
end
$$;
comment on function costing.scenario_changes(uuid) is
  'Los cambios vigentes de un escenario, con sus nombres. Tapa lo que la sesión no ve. unit es el código en un precio y el nombre en un gramaje. applies avisa si un gramaje quedó en una versión que ya no es la vigente.';

-- Las líneas de la versión vigente de una receta, para elegir cuál cambia.
create function costing.scenario_recipe_lines(p_scenario_id uuid, p_recipe_id uuid)
returns table (id uuid, line_order integer, item text, quantity numeric, unit text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s costing.cost_scenarios;
begin
  s := costing.require_scenario(p_scenario_id);
  return query
    select c.id, c.line_order, coalesce(i.name, sr.name), c.quantity, u.name
      from recipes.recipe_versions v
      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null
      join catalog.units u on u.id = c.unit_id
      left join catalog.ingredients i on i.id = c.ingredient_id
      left join recipes.recipes sr on sr.id = c.sub_recipe_id
     where v.recipe_id = p_recipe_id and v.status = 'published'
       and v.recipe_id in (select costing.restaurant_recipes(s.restaurant_id))
       and v.recipe_id in (select costing.visible_recipe_ids())
     order by c.line_order;
end
$$;
comment on function costing.scenario_recipe_lines(uuid, uuid) is 'Las líneas vigentes de una receta del local del escenario.';

-- Las materias primas que usan las recetas del local que la persona ve, con su costo de hoy, para elegir cuál cambia.
create function costing.scenario_ingredients(p_scenario_id uuid)
returns table (id uuid, name text, unit text, unit_cost numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s costing.cost_scenarios;
begin
  s := costing.require_scenario(p_scenario_id);
  return query
    select i.id, i.name, u.code, case when core.has_permission('prices.view', s.restaurant_id) then p.unit_cost end
      from catalog.ingredients i
      join catalog.units u on u.id = i.recipe_unit_id
      left join costing.price_rows(s.restaurant_id, recipes.today(), null) p on p.ingredient_id = i.id
     where i.deleted_at is null
       and i.id in (select c.ingredient_id
                      from recipes.recipe_versions v
                      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null
                     where v.status = 'published'
                       and v.recipe_id in (select costing.restaurant_recipes(s.restaurant_id))
                       and v.recipe_id in (select costing.visible_recipe_ids()))
     order by i.name;
end
$$;
comment on function costing.scenario_ingredients(uuid) is
  'Las materias primas de las recetas del local que la sesión ve, con su costo de hoy por unidad de uso si la sesión ve precios.';

-- Las recetas del local que la persona ve, para elegir la línea que cambia.
create function costing.scenario_recipes(p_scenario_id uuid)
returns table (id uuid, name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s costing.cost_scenarios;
begin
  s := costing.require_scenario(p_scenario_id);
  return query
    select r.id, r.name
      from recipes.recipes r
     where r.id in (select costing.restaurant_recipes(s.restaurant_id))
       and r.id in (select costing.visible_recipe_ids())
       and r.deleted_at is null
     order by r.name;
end
$$;
comment on function costing.scenario_recipes(uuid) is 'Las recetas del local del escenario que la sesión ve.';

-- El resultado: solo lee (es stable). Por cada receta alcanzada, el costo de hoy y el simulado. Local por local como el
-- recálculo: precios una vez, y cada preparación una vez, de abajo hacia arriba.
create function costing.scenario_result(p_scenario_id uuid, p_limit integer default 100, p_offset integer default 0)
returns table (recipe_id uuid, recipe text, cost_today numeric, cost_simulated numeric, difference numeric, difference_pct numeric,
               portion_today numeric, portion_simulated numeric, reliability costing.cost_reliability, total_rows bigint,
               changed_rows bigint, top_rise_recipe text, top_rise numeric, top_drop_recipe text, top_drop numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s          costing.cost_scenarios;
  v_today    date := recipes.today();
  v_seeds    uuid[];
  v_affected uuid[];
  v_prices   jsonb;
  v_yields   jsonb;
  v_lines    jsonb;
  v_subs     jsonb := '{}';
  v_rows     jsonb := '[]';
  v_total    costing.recipe_cost_total;
  r          record;
begin
  s := costing.require_scenario(p_scenario_id);

  select coalesce(jsonb_object_agg(p.ingredient_id,
                                   jsonb_build_object('price_record_id', p.price_record_id, 'price_level', p.price_level,
                                                      'inherited', p.inherited, 'gross_unit_cost', p.gross_unit_cost,
                                                      'unit_cost', p.unit_cost, 'stale', p.stale, 'status', p.status)), '{}')
    into v_prices
    from costing.price_rows(s.restaurant_id, v_today, null) p;
  -- Un precio simulado es el que cuenta en el local, y no es desactualizado ni heredado.
  select v_prices || coalesce(jsonb_object_agg(o.ingredient_id,
                                               jsonb_build_object('unit_cost', o.unit_cost, 'gross_unit_cost', o.unit_cost, 'inherited', false,
                                                                  'stale', false, 'status', 'ok')), '{}')
    into v_prices
    from costing.cost_scenario_overrides o
   where o.scenario_id = p_scenario_id and o.deleted_at is null and o.kind = 'price';
  select coalesce(jsonb_object_agg(o.ingredient_id,
                                   jsonb_build_object('cleaning_yield', o.cleaning_yield, 'cooking_factor', o.cooking_factor)), '{}')
    into v_yields
    from costing.cost_scenario_overrides o
   where o.scenario_id = p_scenario_id and o.deleted_at is null and o.kind = 'yield';
  select coalesce(jsonb_object_agg(o.recipe_component_id, o.quantity), '{}')
    into v_lines
    from costing.cost_scenario_overrides o
   where o.scenario_id = p_scenario_id and o.deleted_at is null and o.kind = 'quantity';

  v_seeds := array(
    select distinct v.recipe_id
      from costing.cost_scenario_overrides o
      join recipes.recipe_components c on c.deleted_at is null
           and (c.ingredient_id = o.ingredient_id or c.id = o.recipe_component_id)
      join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status = 'published'
     where o.scenario_id = p_scenario_id and o.deleted_at is null);
  if cardinality(v_seeds) = 0 then
    return;
  end if;
  v_affected := array(select costing.recipes_above(v_seeds));

  for r in
    select u.id as recipe_id, v.id as version_id, x.name, recipes.sub_depth(u.id) as depth, u.id = any (v_affected) as affected,
           u.id in (select costing.visible_recipe_ids()) as visible
      from costing.restaurant_recipes(s.restaurant_id) u (id)
      join recipes.recipe_versions v on v.recipe_id = u.id and v.status = 'published'
      join recipes.recipes x on x.id = u.id
     order by 4, 1
  loop
    -- Lo que no cambió solo se calcula si es una preparación: la puede usar un plato de arriba.
    continue when not r.affected and not exists (select 1 from recipes.recipe_components c
                                                   where c.sub_recipe_id = r.recipe_id and c.deleted_at is null);
    v_total := costing.recipe_totals_internal(r.version_id, s.restaurant_id, v_today,
                                              jsonb_build_object('prices', v_prices, 'yields', v_yields, 'quantities', v_lines, 'subs', v_subs));
    v_subs := v_subs || jsonb_build_object(r.version_id::text, to_jsonb(v_total));
    if r.affected and r.visible then
      v_rows := v_rows || jsonb_build_object('recipe_id', r.recipe_id, 'recipe', r.name, 'simulated', v_total.total_cost,
                                             'portion', v_total.cost_per_portion, 'reliability', v_total.reliability);
    end if;
  end loop;

  return query
    with rows as (
      select x.recipe_id, x.recipe, round(x.simulated, 4) as simulated, round(x.portion, 4) as portion, x.reliability
        from jsonb_to_recordset(v_rows) as x (recipe_id uuid, recipe text, simulated numeric, portion numeric,
                                              reliability costing.cost_reliability))
    select w.recipe_id, w.recipe, c.total_cost, w.simulated, w.simulated - c.total_cost,
           case when c.total_cost > 0 then round((w.simulated - c.total_cost) / c.total_cost * 100, 2) end,
           c.cost_per_portion, w.portion, w.reliability, count(*) over (),
           -- Las tarjetas miran todas las recetas, no solo las de esta página.
           count(*) filter (where w.simulated is distinct from c.total_cost) over (),
           first_value(w.recipe) over rise, max(w.simulated - c.total_cost) over (),
           first_value(w.recipe) over fall, min(w.simulated - c.total_cost) over ()
      from rows w
      left join costing.recipe_cost_current c on c.recipe_id = w.recipe_id and c.restaurant_id = s.restaurant_id and c.deleted_at is null
    window rise as (order by w.simulated - c.total_cost desc nulls last, w.recipe),
           fall as (order by w.simulated - c.total_cost asc nulls last, w.recipe)
     order by abs(w.simulated - c.total_cost) desc nulls last, w.recipe
     limit least(greatest(coalesce(p_limit, 100), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.scenario_result(uuid, integer, integer) is
  'El resultado de un escenario: por cada receta alcanzada, el costo de hoy y el simulado. Solo lee: no toca el costo vigente, las fotos, la cola ni los eventos.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'costing.create_scenario(uuid, text, text)',
    'costing.archive_scenario(uuid, text)',
    'costing.set_scenario_override(uuid, text, text, uuid, uuid, numeric, uuid, numeric, numeric, numeric)',
    'costing.remove_scenario_override(uuid, text)',
    'costing.scenario_changes(uuid)',
    'costing.scenario_ingredients(uuid)',
    'costing.scenario_recipe_lines(uuid, uuid)',
    'costing.scenario_recipes(uuid)',
    'costing.scenario_result(uuid, integer, integer)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
