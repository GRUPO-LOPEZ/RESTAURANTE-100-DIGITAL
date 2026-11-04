-- Fase 2 · Etapa 2.3, PR 3B: escalado (ADR-0032; sección 13 del documento de Soy, caso 14).
-- Escalar nunca modifica la versión: estas funciones solo leen. La capacidad del equipo de un paso permite avisar
-- que hacen falta más tandas.

alter table recipes.recipe_steps
  add column equipment_capacity numeric(18,6)
    constraint recipe_steps_equipment_capacity_check
    check (equipment_capacity is null or (equipment_capacity > 0 and equipment_capacity < 1000000000 and equipment_capacity <> 'NaN')),
  add column equipment_capacity_unit_id uuid references catalog.units (id) on delete restrict,
  add constraint recipe_steps_capacity_unit_check check ((equipment_capacity is null) = (equipment_capacity_unit_id is null)),
  add constraint recipe_steps_capacity_equipment_check check (equipment_capacity is null or equipment is not null);
create index recipe_steps_capacity_unit_idx on recipes.recipe_steps (equipment_capacity_unit_id) where equipment_capacity_unit_id is not null;
comment on column recipes.recipe_steps.equipment_capacity is
  'Cuánto entra en el equipo de este paso. Si el lote lo supera, hacen falta más tandas.';
comment on column recipes.recipe_steps.equipment_capacity_unit_id is
  'Unidad de la capacidad: la del rendimiento al cargarla. Va guardada porque el rendimiento puede cambiar de unidad.';

create or replace function recipes.set_steps(p_version_id uuid, p_steps jsonb, p_reason text, p_expected_updated_at timestamptz default null)
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
                                         'equipment', 'equipment_capacity', 'equipment_capacity_unit', 'control_point', 'depends_on']);
    if nullif(btrim(v_step ->> 'equipment_capacity_unit'), '') is not null
       and not exists (select 1 from catalog.units u
                         join recipes.recipe_versions v on v.id = p_version_id
                         join catalog.units y on y.id = v.yield_unit_id
                        where u.code = v_step ->> 'equipment_capacity_unit' and u.deleted_at is null and u.dimension = y.dimension) then
      raise exception 'Paso %: la capacidad va en una unidad como la del rendimiento.', v_n using errcode = '22023';
    end if;
    insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                      passive_minutes, workers, sector, equipment, equipment_capacity, equipment_capacity_unit_id, control_point)
    values (v_recipe.group_id, p_version_id, v_n, coalesce(nullif(v_step ->> 'kind', ''), 'preparation')::recipes.step_kind,
            btrim(coalesce(v_step ->> 'instructions', '')), coalesce(nullif(v_step ->> 'active_minutes', '')::integer, 0),
            coalesce(nullif(v_step ->> 'passive_minutes', '')::integer, 0), nullif(v_step ->> 'workers', '')::smallint,
            nullif(btrim(v_step ->> 'sector'), ''), nullif(btrim(v_step ->> 'equipment'), ''),
            nullif(replace(btrim(v_step ->> 'equipment_capacity'), ',', '.'), '')::numeric,
            -- La capacidad guarda su unidad: la que traía, o la del rendimiento de la versión.
            case when nullif(btrim(v_step ->> 'equipment_capacity'), '') is not null
                 then coalesce((select u.id from catalog.units u where u.code = v_step ->> 'equipment_capacity_unit' and u.deleted_at is null),
                               (select v.yield_unit_id from recipes.recipe_versions v where v.id = p_version_id)) end,
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
  if v_constraint = 'recipe_steps_equipment_capacity_check' then
    raise exception 'Paso %: la capacidad del equipo tiene que ser un número mayor que cero y menor que mil millones.', v_n using errcode = '22023';
  elsif v_constraint = 'recipe_steps_capacity_unit_check' then
    raise exception 'Paso %: para cargar la capacidad, primero cargá el rendimiento de la receta.', v_n using errcode = '22023';
  elsif v_constraint = 'recipe_steps_capacity_equipment_check' then
    raise exception 'Paso %: para cargar la capacidad, escribí el equipo.', v_n using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;

comment on function recipes.set_steps(uuid, jsonb, text, timestamptz) is
  'Reemplaza los pasos de un borrador, con sus dependencias por número de paso, su equipo y la capacidad del equipo.';

create or replace function recipes.copy_version_content(p_from uuid, p_to uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_to recipes.recipe_versions;
begin
  select * into v_to from recipes.recipe_versions where id = p_to;
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, sub_recipe_id, quantity,
                                         unit_id, quantity_basis, yield_profile_id, no_scale, notes)
  select v_to.group_id, p_to, line_order, ingredient_id, sub_recipe_id, quantity, unit_id, quantity_basis, yield_profile_id,
         no_scale, notes
    from recipes.recipe_components where recipe_version_id = p_from and deleted_at is null;
  insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                    passive_minutes, workers, sector, equipment, equipment_capacity, equipment_capacity_unit_id, control_point)
  select v_to.group_id, p_to, step_number, kind, instructions, active_minutes, passive_minutes, workers, sector, equipment, equipment_capacity, equipment_capacity_unit_id,
         control_point
    from recipes.recipe_steps where recipe_version_id = p_from and deleted_at is null;
  -- Las dependencias se copian por número de paso.
  insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
  select v_to.group_id, ns.id, nd.id
    from recipes.recipe_step_dependencies d
    join recipes.recipe_steps os on os.id = d.step_id
    join recipes.recipe_steps od on od.id = d.depends_on_step_id
    join recipes.recipe_steps ns on ns.recipe_version_id = p_to and ns.step_number = os.step_number and ns.deleted_at is null
    join recipes.recipe_steps nd on nd.recipe_version_id = p_to and nd.step_number = od.step_number and nd.deleted_at is null
   where os.recipe_version_id = p_from and d.deleted_at is null;
  insert into recipes.recipe_media (group_id, recipe_id, recipe_version_id, kind, storage_path, description)
  select v_to.group_id, v_to.recipe_id, p_to, kind, storage_path, description
    from recipes.recipe_media where recipe_version_id = p_from and deleted_at is null;
end
$$;

-- De un objetivo a un factor y a las cantidades nuevas. p_mode: portions (contra las porciones) o yield (contra el
-- rendimiento, con p_unit de la misma dimensión). Sin porciones o sin rendimiento no se inventa un factor.
create function recipes.scale_version(p_version_id uuid, p_target numeric, p_mode text, p_unit text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_v        recipes.recipe_versions;
  v_factor   numeric;
  v_yield_to numeric;
  v_lot_base numeric;
  v_base     numeric;
  v_to       numeric;
  v_unit     catalog.units;
  v_yield_u  catalog.units;
begin
  perform org.require(recipes.can_see_version(p_version_id), 'ver esta receta');
  select * into v_v from recipes.recipe_versions where id = p_version_id;
  if p_target is null or p_target <= 0 or p_target >= 1000000000 then
    raise exception 'Escribí cuánto querés hacer: un número mayor que cero.' using errcode = '22023';
  end if;
  select * into v_yield_u from catalog.units where id = v_v.yield_unit_id;

  if p_mode = 'portions' then
    if v_v.portions is null then
      raise exception 'Esta receta no tiene porciones cargadas.' using errcode = '22023';
    end if;
    v_factor := p_target / v_v.portions;
  elsif p_mode = 'yield' then
    if v_v.yield_quantity is null then
      raise exception 'Esta receta no tiene rendimiento cargado.' using errcode = '22023';
    end if;
    select * into v_unit from catalog.units where code = p_unit and deleted_at is null;
    if not found or v_unit.dimension is distinct from v_yield_u.dimension then
      raise exception 'Elegí una unidad como la del rendimiento de la receta.' using errcode = '22023';
    end if;
    v_base := v_v.yield_quantity * recipes.unit_to_base(v_yield_u.id);
    v_to := p_target * recipes.unit_to_base(v_unit.id);
    if coalesce(v_base, 0) <= 0 or v_to is null then
      raise exception 'Elegí una unidad como la del rendimiento de la receta.' using errcode = '22023';
    end if;
    v_factor := v_to / v_base;
  else
    raise exception 'Elegí si escalás por porciones o por rendimiento.' using errcode = '22023';
  end if;
  if v_factor is null or round(v_factor, 6) <= 0 or v_factor >= 1000000 then
    raise exception 'Ese lote es demasiado chico o demasiado grande para esta receta.' using errcode = '22023';
  end if;
  v_yield_to := v_v.yield_quantity * v_factor;
  -- En la unidad base y sin los decimales de la división: un lote que entra justo es una sola tanda.
  v_lot_base := round(v_yield_to * recipes.unit_to_base(v_yield_u.id), 6);

  return jsonb_build_object(
    'factor', round(v_factor, 6),
    'exact_factor', v_factor,
    'portions', v_v.portions,
    'target_portions', case when v_v.portions is not null then round(v_v.portions * v_factor, 2) end,
    'yield_quantity', v_v.yield_quantity,
    'target_yield', round(v_yield_to, 6),
    'yield_unit', v_yield_u.code,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order', c.line_order,
               'item', case when c.ingredient_id is not null then i.name
                            when s.deleted_at is null and s.id in (select costing.visible_recipe_ids()) then s.name
                            else 'Preparación' end,
               'unit', u.code, 'quantity', c.quantity,
               'scaled', round(case when c.no_scale then c.quantity else c.quantity * v_factor end, 6), 'no_scale', c.no_scale)
             order by c.line_order)
        from recipes.recipe_components c
        join catalog.units u on u.id = c.unit_id
        left join catalog.ingredients i on i.id = c.ingredient_id
        left join recipes.recipes s on s.id = c.sub_recipe_id
       where c.recipe_version_id = p_version_id and c.deleted_at is null), '[]'::jsonb),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
               'number', t.step_number, 'equipment', t.equipment, 'capacity', t.equipment_capacity, 'capacity_unit', cu.code,
               'batches', case when cu.dimension = v_yield_u.dimension and v_lot_base > 0
                               then ceil(v_lot_base / (t.equipment_capacity * recipes.unit_to_base(cu.id))) end)
             order by t.step_number)
        from recipes.recipe_steps t
        left join catalog.units cu on cu.id = t.equipment_capacity_unit_id
       where t.recipe_version_id = p_version_id and t.deleted_at is null and t.equipment is not null), '[]'::jsonb));
end
$$;
comment on function recipes.scale_version(uuid, numeric, text, text) is
  'Escala una versión a un objetivo, sin modificarla: factor, cantidades nuevas (las líneas "no escalar" quedan igual) y tandas por paso según la capacidad del equipo. Sin importes. Pide poder ver la versión.';

-- El costo proyectado de un lote: cada línea por el factor, salvo las "no escalar". Si falta un dato, queda vacío.
create function costing.scaled_cost(p_version_id uuid, p_restaurant_id uuid, p_factor numeric)
returns table (total_cost numeric, total_gross_cost numeric, reliability costing.cost_reliability)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform costing.require_recipe_cost(p_version_id, p_restaurant_id);
  if p_factor is null or p_factor <= 0 or p_factor >= 1000000000 then
    raise exception 'El factor tiene que ser mayor que cero.' using errcode = '22023';
  end if;
  return query
    select round(costing.fit(case when count(*) > 0 and count(*) filter (where l.status <> 'ok' or l.line_cost is null) = 0
                                  then sum(l.line_cost * case when c.no_scale then 1 else p_factor end) end, 9e13), 4),
           round(costing.fit(case when count(*) > 0 and count(*) filter (where l.line_gross_cost is null) = 0
                                  then sum(l.line_gross_cost * case when c.no_scale then 1 else p_factor end) end, 9e13), 4),
           (costing.recipe_totals_internal(p_version_id, p_restaurant_id, recipes.today())).reliability
      from costing.recipe_line_costs_internal(p_version_id, p_restaurant_id, recipes.today()) l
      join recipes.recipe_components c on c.id = l.component_id;
end
$$;
comment on function costing.scaled_cost(uuid, uuid, numeric) is
  'El costo proyectado de un lote en un local, con los precios de hoy: cada línea por el factor, salvo las "no escalar". Pide recipes.view_costs en el local.';

revoke execute on function recipes.scale_version(uuid, numeric, text, text), costing.scaled_cost(uuid, uuid, numeric) from public;
grant execute on function recipes.scale_version(uuid, numeric, text, text), costing.scaled_cost(uuid, uuid, numeric) to authenticated;
