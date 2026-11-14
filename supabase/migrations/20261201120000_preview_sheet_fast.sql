-- La grilla de la ficha (ADR-0047): costing.preview_sheet_lines tardaba 4,3 s con 25 filas. El join de la preparación
-- evaluaba los permisos (can_view_recipe, can_work_recipe y sub_in_scope) para todas las recetas del grupo, por cada
-- fila, aunque la fila fuera una materia prima. Ahora la preparación se busca por su id (lateral): los permisos se
-- evalúan solo para la que la fila usa. Las reglas no cambian; el resto del cuerpo es el mismo de 20261128120000.
create or replace function costing.preview_sheet_lines(p_version_id uuid, p_restaurant_id uuid, p_lines jsonb)
returns table (line_order integer, grams numeric, weight_status text, line_cost numeric, unit_cost numeric,
               cost_unit text, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_r      recipes.recipes;
  v_costs  boolean := false;
  v_prices boolean := false;
  v_gram   uuid;
  v_lines  jsonb;
begin
  select r.* into v_r from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id where v.id = p_version_id;
  perform org.require(v_r.id is not null and recipes.can_see_version(p_version_id)
                      and (recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id)
                           or recipes.allowed('recipes.publish', v_r.group_id, v_r.brand_id, v_r.restaurant_id)),
                      'ver la ficha de esta receta');
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) > 200 then
    raise exception 'Las líneas van en una lista de hasta 200.' using errcode = '22023';
  end if;
  -- El local tiene que estar al alcance de la receta; si no, solo pesos.
  if p_restaurant_id is not null and exists (
       select 1 from org.restaurants r
        where r.id = p_restaurant_id and r.group_id = v_r.group_id and r.deleted_at is null
          and (v_r.scope_type = 'group' or (v_r.scope_type = 'brand' and v_r.brand_id = r.brand_id)
               or (v_r.scope_type = 'restaurant' and v_r.restaurant_id = r.id))) then
    v_costs := core.has_permission('recipes.view_costs', p_restaurant_id);
    v_prices := v_costs and core.has_permission('prices.view', p_restaurant_id);
  end if;
  select u.id into v_gram from catalog.units u where u.code = 'g' and u.is_base and u.deleted_at is null;

  -- Solo líneas completas, con las mismas reglas que set_components: materias primas activas del grupo, preparaciones
  -- activas que la persona ve o trabaja y que se pueden usar en esta receta (no otra marca u otro local, ni ella misma),
  -- y el perfil de merma aprobado de esa materia prima. Cada una conserva su posición en la grilla. La preparación se
  -- busca por su id: los permisos se evalúan solo para la que la fila usa. El «offset 0» impide que el planificador
  -- aplane la subconsulta en un join (así evaluaba los permisos de todas las recetas antes de comparar el id).
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_order', t.ord, 'ingredient_id', i.id, 'sub_recipe_id', s.id, 'quantity', x.quantity, 'unit', x.unit,
           'basis', case when s.id is not null then 'finished'
                         when x.basis in ('clean', 'cooked') then x.basis else 'purchase' end,
           'yield_profile_id', (select p.id from catalog.ingredient_yield_profiles p
                                 where p.id = x.yield_profile_id and p.ingredient_id = i.id and p.status = 'approved'
                                   and p.deleted_at is null))
           order by t.ord), '[]'::jsonb)
    into v_lines
    from jsonb_array_elements(p_lines) with ordinality as t (item, ord)
    cross join lateral jsonb_to_record(t.item) as x (ingredient_id uuid, sub_recipe_id uuid, quantity numeric, unit text,
                                                     basis text, yield_profile_id uuid)
    left join catalog.ingredients i on i.id = x.ingredient_id and i.group_id = v_r.group_id and i.deleted_at is null
                                    and i.is_active
    left join lateral (
      select s.id from recipes.recipes s
       where s.id = x.sub_recipe_id and s.group_id = v_r.group_id and s.deleted_at is null
         and s.is_active and s.id <> v_r.id
         and (recipes.can_view_recipe(s.id) or recipes.can_work_recipe(s.id))
         and recipes.sub_in_scope(v_r.id, s.id)
      offset 0) s on true
   where jsonb_typeof(t.item) = 'object' and x.quantity > 0 and x.quantity < 1e9
     and (i.id is null) <> (s.id is null)
     and exists (select 1 from catalog.units u where u.code = x.unit and u.deleted_at is null and u.dimension <> 'package');

  return query
  with l as (
    select x.line_order as ord, x.ingredient_id, x.sub_recipe_id, x.quantity, u.id as unit_id, u.dimension, u.is_base,
           (select k.factor from catalog.unit_conversions k where k.from_unit_id = u.id and k.deleted_at is null) as factor
      from jsonb_to_recordset(v_lines) as x (line_order integer, ingredient_id uuid, sub_recipe_id uuid, quantity numeric,
                                            unit text)
      join catalog.units u on u.code = x.unit and u.deleted_at is null),
  w as (
    select l.ord,
           case when l.ingredient_id is not null then cq.quantity
                when l.dimension = 'mass' then l.quantity * case when l.is_base then 1 else l.factor end
           end as grams,
           case when l.ingredient_id is not null then cq.status
                when l.dimension = 'mass' then 'ok'
                else 'not_weight'
           end as weight_status,
           l.ingredient_id, l.sub_recipe_id, l.dimension
      from l
      left join lateral catalog.convert_quantity(l.ingredient_id, l.quantity, l.unit_id, v_gram) cq
        on l.ingredient_id is not null),
  c as (
    select k.line_order, k.line_cost, k.unit_cost, k.status
      from costing.recipe_line_costs_internal(
             p_version_id, p_restaurant_id, recipes.today(), jsonb_build_object('lines', v_lines)) k
     where v_costs)
  select w.ord, round(w.grams, 4), w.weight_status,
         case when v_costs then round(c.line_cost, 4) end,
         case when v_prices then round(c.unit_cost, 8) end,
         case when w.ingredient_id is not null
                then (select bu.code from catalog.ingredients i join catalog.units iu on iu.id = i.recipe_unit_id
                        join catalog.units bu on bu.dimension = iu.dimension and bu.is_base and bu.deleted_at is null
                       where i.id = w.ingredient_id limit 1)
              else (select bu.code from catalog.units bu where bu.dimension = w.dimension and bu.is_base and bu.deleted_at is null limit 1)
         end,
         case when v_costs then c.status end
    from w left join c on c.line_order = w.ord
   order by w.ord;
end
$$;
comment on function costing.preview_sheet_lines(uuid, uuid, jsonb) is
  'La grilla de la ficha mientras se escribe: por cada línea (en el orden recibido) su peso en gramos y, con recipes.view_costs en el local, su costo con el mismo motor que el costo oficial; su costo por unidad base (g, ml o unidad), solo con prices.view. Nunca supone una conversión ni un precio: lo que falta va vacío con su estado. Pide poder editar o publicar la receta. Los permisos de una preparación se evalúan solo para la que la fila usa (ADR-0047).';
revoke execute on function costing.preview_sheet_lines(uuid, uuid, jsonb) from public, anon;
grant execute on function costing.preview_sheet_lines(uuid, uuid, jsonb) to authenticated;
