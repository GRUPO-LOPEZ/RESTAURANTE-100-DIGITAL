-- Rediseño, PR 2 (ADR-0036; autorizado por Joaco el 2026-11-09): la lista de costos se ordena por columna. La lista se
-- pagina en la base, así que el orden tiene que estar acá: ordenar en la pantalla ordenaría solo la página visible.
-- Solo lectura: no cambia permisos, datos ni fórmulas. Lista cerrada de órdenes, sin SQL dinámico.
-- Un cambio chico a la vista: el orden por nombre ya no separa mayúsculas de minúsculas (lower(name)).

drop function costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid);
create function costing.restaurant_costs(p_restaurant_id uuid, p_search text default null, p_reliability costing.cost_reliability default null,
                                         p_limit integer default 50, p_offset integer default 0, p_recipe_id uuid default null,
                                         p_order text default null)
returns table (recipe_id uuid, code text, name text, recipe_type text, recipe_version_id uuid, portions integer, base_unit text,
               total_cost numeric, total_gross_cost numeric, cost_per_base_unit numeric, cost_per_portion numeric,
               reliability costing.cost_reliability, updated_at timestamptz, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- "name", "code", "total", "portion", "reliability" o "updated"; con "-" adelante, de mayor a menor.
  -- Lo que no está en la lista vuelve al orden de siempre: por nombre.
  -- Un solo guion adelante invierte; "--total" no está en la lista y usa el orden de siempre.
  v_raw  text := case when coalesce(p_order, '') like '-%' then substr(p_order, 2) else coalesce(p_order, '') end;
  v_key  text := case when v_raw in ('name', 'code', 'total', 'portion', 'reliability', 'updated') then v_raw else 'name' end;
  v_desc boolean := coalesce(p_order, '') like '-%' and v_key = v_raw;
begin
  perform org.require(core.has_permission('recipes.view_costs', p_restaurant_id), 'ver costos de este local');
  return query
    select c.recipe_id, x.code, x.name, x.recipe_type::text, c.recipe_version_id, v.portions, b.code, c.total_cost, c.total_gross_cost,
           c.cost_per_base_unit, c.cost_per_portion, c.reliability, c.updated_at, count(*) over ()
      from costing.recipe_cost_current c
      join recipes.recipes x on x.id = c.recipe_id and x.deleted_at is null
      join recipes.recipe_versions v on v.id = c.recipe_version_id
      left join catalog.units yu on yu.id = v.yield_unit_id
      left join catalog.units b on b.dimension = yu.dimension and b.is_base and b.deleted_at is null
     where c.restaurant_id = p_restaurant_id and c.deleted_at is null
       and x.id in (select costing.visible_recipe_ids())
       and (p_recipe_id is null or c.recipe_id = p_recipe_id)
       and (p_reliability is null or c.reliability = p_reliability)
       and (p_search is null or strpos(lower(x.name), lower(p_search)) > 0 or strpos(lower(x.code), lower(p_search)) > 0)
     -- Una expresión por clave y por sentido: las que no corresponden dan null y no pesan. Los vacíos van al final.
     order by
       case when v_key = 'name' and not v_desc then lower(x.name) end asc nulls last,
       case when v_key = 'name' and v_desc then lower(x.name) end desc nulls last,
       case when v_key = 'code' and not v_desc then x.code end asc nulls last,
       case when v_key = 'code' and v_desc then x.code end desc nulls last,
       case when v_key = 'total' and not v_desc then c.total_cost end asc nulls last,
       case when v_key = 'total' and v_desc then c.total_cost end desc nulls last,
       case when v_key = 'portion' and not v_desc then c.cost_per_portion end asc nulls last,
       case when v_key = 'portion' and v_desc then c.cost_per_portion end desc nulls last,
       -- La confiabilidad sigue el orden del tipo: completo, con estimaciones, desactualizado, incompleto.
       case when v_key = 'reliability' and not v_desc then c.reliability end asc nulls last,
       case when v_key = 'reliability' and v_desc then c.reliability end desc nulls last,
       case when v_key = 'updated' and not v_desc then c.updated_at end asc nulls last,
       case when v_key = 'updated' and v_desc then c.updated_at end desc nulls last,
       x.name, c.recipe_id
     limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid, text) is
  'Los costos vigentes de un local, con el nombre de cada receta que la sesión ve, paginados (hasta 200 por página) y ordenados por p_order (name, code, total, portion, reliability o updated; con "-" de mayor a menor; si no, por nombre). Pide recipes.view_costs en el local.';
revoke execute on function costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid, text) from public;
grant execute on function costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid, text) to authenticated;
