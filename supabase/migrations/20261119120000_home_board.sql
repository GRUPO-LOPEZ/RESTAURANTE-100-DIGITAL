-- Fase 2 · Etapa 2.5, PR 2: el tablero de Inicio (ADR-0033; sección 18 del documento de Soy). Solo lee: las tarjetas salen de
-- costing.data_quality, y esto suma lo que no es un indicador. Cada sección pide el permiso de su dato.

create function costing.home_board(p_restaurant_id uuid)
returns table (section text, kind text, item_id uuid, item text, amount numeric, detail text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seen    uuid[];
  v_recipes uuid[];
  v_view    boolean := core.has_permission('recipes.view', p_restaurant_id);
  v_costs   boolean := core.has_permission('recipes.view_costs', p_restaurant_id);
  v_catalog boolean := core.has_permission('catalog.view', p_restaurant_id);
begin
  perform org.require(costing.quality_allowed(p_restaurant_id), 'ver el tablero de este local');
  v_seen := array(select costing.visible_recipe_ids());
  -- Las mismas recetas que cuenta la calidad de datos. Se leen una vez: es lo más caro del tablero.
  v_recipes := array(select q.item_id from costing.quality_items(p_restaurant_id) q where q.indicator = 'recipe_cost');

  if v_view then
    -- Una fila por sección permitida: una lista vacía no es lo mismo que no poder verla.
    return query select 'allowed', 'section', null::uuid, 'most_used', null::numeric, null::text;
    -- Cuántas de las recetas del local son preparaciones.
    return query
      select 'preparations', 'recipe', null::uuid, 'Preparaciones', count(*)::numeric, null::text
        from recipes.recipes r
       where r.id = any (v_recipes) and r.recipe_type = 'preparation';
    -- Lo que más se usa en las recetas vigentes del local que la sesión ve. Una materia prima lleva su nombre: pide el catálogo.
    return query
      select 'most_used', case when c.ingredient_id is not null then 'ingredient' else 'recipe' end,
             coalesce(c.ingredient_id, c.sub_recipe_id), coalesce(i.name, s.name), count(distinct v.recipe_id)::numeric, null::text
        from recipes.recipe_versions v
        join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null
        left join catalog.ingredients i on i.id = c.ingredient_id
        left join recipes.recipes s on s.id = c.sub_recipe_id
       where v.status = 'published' and v.recipe_id = any (v_seen)
         and v.recipe_id in (select costing.restaurant_recipes(p_restaurant_id))
         and (c.ingredient_id is null or v_catalog)
       group by 2, 3, 4
       order by 5 desc, 4
       limit 5;
  end if;

  if v_costs then
    return query select 'allowed', 'section', null::uuid, x, null::numeric, null::text
                   from unnest(array['reliability', 'top_portion', 'price_affected']) x;
    -- Cuántas recetas hay en cada estado del costo, también los que están en cero, siempre en el mismo orden.
    return query
      select 'reliability', 'state', null::uuid, st.state, coalesce(n.total, 0)::numeric, st.position::text
        from unnest(array['verified', 'estimated', 'stale', 'incomplete', 'none']) with ordinality st (state, position)
        left join (select coalesce(c.reliability::text, 'none') as state, count(*) as total
                     from unnest(v_recipes) q (id)
                     left join costing.recipe_cost_current c
                       on c.recipe_id = q.id and c.restaurant_id = p_restaurant_id and c.deleted_at is null
                    group by 1) n on n.state = st.state
       order by st.position;
    return query
      select 'top_portion', 'recipe', c.recipe_id, r.name, c.cost_per_portion, c.reliability::text
        from costing.recipe_cost_current c
        join recipes.recipes r on r.id = c.recipe_id
       where c.restaurant_id = p_restaurant_id and c.deleted_at is null and c.cost_per_portion is not null
         and c.recipe_id = any (v_seen) and c.recipe_id = any (v_recipes)
       order by c.cost_per_portion desc, r.name
       limit 5;
    -- Lo que cambió por un precio en los últimos 30 días, contra la foto anterior de la misma versión: un cambio de fórmula no
    -- se lee como un precio. Primero se compara cada foto, y después se elige: una foto sin cambio no tapa a la que cambió.
    return query
      with changed as (
        select distinct on (s.recipe_id) s.recipe_id, s.total_cost, p.total_cost as previous
          from costing.recipe_cost_snapshots s
          cross join lateral (select y.total_cost
                                from costing.recipe_cost_snapshots y
                               where y.recipe_id = s.recipe_id and y.restaurant_id = s.restaurant_id
                                 and y.recipe_version_id = s.recipe_version_id and y.entry_number < s.entry_number
                               order by y.entry_number desc
                               limit 1) p
         where s.restaurant_id = p_restaurant_id and s.reason = 'price_change' and s.created_at >= now() - interval '30 days'
           and s.recipe_id = any (v_seen) and s.recipe_id = any (v_recipes)
           and s.total_cost is distinct from p.total_cost
         order by s.recipe_id, s.entry_number desc
      )
      select 'price_affected', 'recipe', x.recipe_id, r.name, x.total_cost - x.previous,
             case when x.previous is null then 'gained' when x.total_cost is null then 'lost' end
        from changed x
        join recipes.recipes r on r.id = x.recipe_id
       order by abs(x.total_cost - x.previous) desc nulls first, r.name
       limit 5;
  end if;

  if v_costs and v_catalog then
    return query select 'allowed', 'section', null::uuid, 'top_ingredient', null::numeric, null::text;
    -- Cuánto pesa cada materia prima en lo que cuestan las recetas, por línea directa y sobre las recetas con costo. No sabe de
    -- ventas: es sobre las recetas, no sobre lo que se vende.
    return query
      with lines as (
        select l.ingredient_id, l.line_cost
          from costing.recipe_cost_current c
          cross join lateral (select x.id
                                from costing.recipe_cost_snapshots x
                               where x.recipe_id = c.recipe_id and x.restaurant_id = c.restaurant_id
                                 and x.recipe_version_id = c.recipe_version_id
                               order by x.entry_number desc
                               limit 1) s
          join costing.recipe_cost_snapshot_lines l on l.snapshot_id = s.id and l.line_cost is not null and l.ingredient_id is not null
         where c.restaurant_id = p_restaurant_id and c.deleted_at is null and c.total_cost is not null
           and c.recipe_id = any (v_seen) and c.recipe_id = any (v_recipes)
      )
      select 'top_ingredient', 'ingredient', l.ingredient_id, i.name,
             round(sum(l.line_cost) * 100 / nullif((select sum(x.line_cost) from lines x), 0), 1), null::text
        from lines l
        join catalog.ingredients i on i.id = l.ingredient_id
       group by l.ingredient_id, i.name
       order by 5 desc nulls last, 4
       limit 5;
  end if;
end
$$;
comment on function costing.home_board(uuid) is
  'El tablero de Inicio de un local: lo más usado, la confiabilidad del costo, lo más caro, lo que más pesa y lo que cambió por un precio. Cada sección pide el permiso de su dato.';
revoke execute on function costing.home_board(uuid) from public;
grant execute on function costing.home_board(uuid) to authenticated;
