-- Hacer varias recetas y fichas técnicas (Tanda 2 de Soy, PR C; ADR-0065).
--   * recipes.kitchen_card suma sector, partida y quién aprobó (nombre y apellido), y el código de la unidad de cada línea.
--   * recipes.scale_version suma el modo «recipes» (cuántas recetas) y la medida práctica de cada línea, multiplicada.
--   * Cada línea sigue en su unidad: nunca se usa la densidad. La puerta de las dos funciones no cambia.

create or replace function recipes.kitchen_card(p_recipe_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
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
    'yield_unit_code', (select u.code from catalog.units u where u.id = v_v.yield_unit_id),
    'portions', v_v.portions, 'portion_grams', v_v.portion_grams, 'description', v_v.description,
    'storage_notes', v_v.storage_notes, 'presentation_notes', v_v.presentation_notes,
    'total_minutes', v_total, 'active_minutes', v_act,
    'sector', v_r.sector, 'station', v_r.station,
    -- Solo nombre y apellido, para todo el que ve la ficha (decisión de Joaco, 2026-11-24): ni id ni correo.
    'approved_by_name', (select nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), '')
                           from core.user_profiles p where p.id = v_v.approved_by),
    -- La maestra, solo para quien la ve (revisión de seguridad, m1).
    'variant_of', (select jsonb_build_object('recipe_id', m.id, 'name', m.name) from recipes.recipes m
                    where m.id = v_r.variant_of_recipe_id
                      and (recipes.can_view_recipe(m.id) or recipes.can_work_recipe(m.id))),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object('line', c.line_order, 'ingredient', coalesce(i.name, s.name),
                                          'sub_recipe_id', c.sub_recipe_id, 'quantity', c.quantity, 'unit', u.name, 'unit_code', u.code,
                                          'basis', c.quantity_basis, 'notes', c.notes,
                                          'measure_count', c.measure_count, 'measure_name', c.measure_name,
                                          'measure_content', c.measure_content, 'measure_unit', mu.code) order by c.line_order)
        from recipes.recipe_components c
        left join catalog.ingredients i on i.id = c.ingredient_id
        left join recipes.recipes s on s.id = c.sub_recipe_id
        join catalog.units u on u.id = c.unit_id
        left join catalog.units mu on mu.id = c.measure_unit_id
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
  'La versión vigente para las fichas técnicas, sin ningún valor económico. Con sector, partida y el nombre de quien aprobó. Vacía si la sesión no ve la receta o no tiene versión vigente.';

create or replace function recipes.scale_version(p_version_id uuid, p_target numeric, p_mode text, p_unit text default null)
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

  if p_mode = 'recipes' then
    v_factor := p_target;
  elsif p_mode = 'portions' then
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
    raise exception 'Elegí si escalás por recetas, por porciones o por rendimiento.' using errcode = '22023';
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
               'scaled', round(case when c.no_scale then c.quantity else c.quantity * v_factor end, 6), 'no_scale', c.no_scale,
               -- La medida práctica, con el nombre y el contenido congelados en la versión (ADR-0064).
               'measure_name', c.measure_name, 'measure_content', c.measure_content, 'measure_unit', mu.code,
               'measure_count', c.measure_count,
               'measure_scaled', case
                 when c.measure_count is null then null
                 when c.no_scale then c.measure_count
                 -- De la misma clase, se cuenta de nuevo: 12 veces «0,33 tazas» arrastraría el redondeo.
                 -- Sobre la cantidad ya redondeada (la que se muestra): un factor periódico no corre el redondeo.
                 when not c.measure_manual and mu.dimension = u.dimension
                   then coalesce(recipes.measure_count_for(null, round(c.quantity * v_factor, 6), c.unit_id, c.measure_content, c.measure_unit_id),
                                 greatest(round(round(c.measure_count * v_factor, 6), 2), 0.01))
                 -- Corregida a mano o con el peso por unidad (que pudo cambiar): se multiplica lo guardado.
                 else greatest(round(round(c.measure_count * v_factor, 6), 2), 0.01) end)
             order by c.line_order)
        from recipes.recipe_components c
        join catalog.units u on u.id = c.unit_id
        left join catalog.units mu on mu.id = c.measure_unit_id
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
  'Multiplica una versión por un objetivo (recetas, porciones o rendimiento), sin modificarla: factor, cantidades en su unidad (las líneas "no escalar" quedan igual), medidas prácticas y tandas por paso según la capacidad del equipo. Sin importes ni densidad. Pide poder ver la versión.';
