-- Fase 2 · Etapa 2.3, PR 2: lo que necesitan las pantallas de costos (ADR-0032).
-- 1. costing.recalc_status: si hay cambios por aplicar o recálculos que fallaron. Nunca devuelve el error.
-- 2. costing.price_impact: a qué recetas y locales les pegó un precio, antes y después.
-- 3. costing.restaurant_costs y restaurant_cost_summary: la lista de costos de un local y sus tarjetas.

-- El orden de las fotos: las de una tanda comparten la hora.
alter table costing.recipe_cost_snapshots add column entry_number bigint generated always as identity;
comment on column costing.recipe_cost_snapshots.entry_number is 'Orden de las fotos. Las de una misma tanda comparten la hora.';
create index recipe_cost_snapshots_order_idx on costing.recipe_cost_snapshots (recipe_id, restaurant_id, entry_number desc);

-- Qué precio causó un pedido: el impacto se ancla acá, no en las fotos, que repiten todas las líneas.
alter table costing.cost_recalc_queue add column price_record_id uuid references costing.price_records (id) on delete restrict;
comment on column costing.cost_recalc_queue.price_record_id is 'El precio que causó el pedido, si fue un precio. Con processed_at dice en qué tanda entró.';
create index cost_recalc_queue_price_idx on costing.cost_recalc_queue (price_record_id) where price_record_id is not null;

drop function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason);
create function costing.enqueue_recalc(p_recipe_ids uuid[], p_restaurant_ids uuid[], p_reason costing.cost_snapshot_reason,
                                       p_price_record_id uuid default null)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into costing.cost_recalc_queue (group_id, recipe_ids, restaurant_ids, reason, price_record_id)
  select r.group_id, p_recipe_ids, p_restaurant_ids, p_reason, p_price_record_id from recipes.recipes r where r.id = p_recipe_ids[1]
$$;
comment on function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason, uuid) is
  'Interna: anota un pedido de recálculo. Sin recetas, no hace nada.';
revoke execute on function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason, uuid) from public;

create or replace function costing.on_price_recorded()
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
  perform costing.enqueue_recalc(costing.recipes_using_ingredient(v_ingredient), v_places, 'price_change', new.id);
  return null;
end
$$;

-- Lo que le toca a la sesión: los pedidos de los locales donde ve costos. Un pedido sin locales vale para todos.
create function costing.recalc_status()
returns table (pending bigint, failed bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_places uuid[];
  v_groups uuid[];
begin
  v_places := array(select core.permitted_restaurant_ids('recipes.view_costs'));
  v_groups := array(select distinct r.group_id from org.restaurants r where r.id = any (v_places));
  perform org.require(cardinality(v_groups) > 0, 'ver costos');
  return query
    select count(*) filter (where q.attempts < 3), count(*) filter (where q.attempts >= 3)
      from costing.cost_recalc_queue q
     where q.processed_at is null and q.group_id = any (v_groups)
       and (q.restaurant_ids is null or q.restaurant_ids && v_places);
end
$$;
comment on function costing.recalc_status() is
  'Para las pantallas de costos: cuántos pedidos de recálculo están pendientes y cuántos fallaron 3 veces, en los locales donde la sesión ve costos. No devuelve el texto del error. Pide recipes.view_costs.';

-- Las recetas que la sesión ve o trabaja.
create function costing.visible_recipe_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select recipes.viewable_recipe_ids()
  union
  select recipes.workable_recipe_ids()
$$;
comment on function costing.visible_recipe_ids() is 'Interna: las recetas que la sesión ve o trabaja.';
revoke execute on function costing.visible_recipe_ids() from public;

-- Antes y después de un precio. La tanda sale del pedido que ese precio anotó: un precio que no cambió nada no tiene
-- fotos propias, y las siguientes repiten sus líneas. Dentro de la tanda valen las fotos con una línea de ese precio
-- y, hacia arriba, las de los platos que usan esas preparaciones.
create function costing.price_impact(p_price_record_id uuid, p_limit integer default 200, p_offset integer default 0)
returns table (ingredient text, valid_from date, calculated_at timestamptz, recipe_id uuid, recipe text, restaurant_id uuid, restaurant text,
               cost_before numeric, cost_after numeric, difference numeric, difference_pct numeric, version_changed boolean,
               total_rows bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with recursive batch as (
    select q.processed_at as at from costing.cost_recalc_queue q
     where q.price_record_id = p_price_record_id and q.processed_at is not null
     limit 1
  ), hit (snapshot_id, recipe_id, restaurant_id) as (
    select s.id, s.recipe_id, s.restaurant_id
      from batch b
      join costing.recipe_cost_snapshots s on s.created_at = b.at
      join costing.recipe_cost_snapshot_lines l on l.snapshot_id = s.id and l.price_record_id = p_price_record_id
     where s.restaurant_id in (select core.permitted_restaurant_ids('recipes.view_costs'))
    union
    select s.id, s.recipe_id, s.restaurant_id
      from hit h
      cross join batch b
      join costing.recipe_cost_snapshot_lines l on l.sub_recipe_id = h.recipe_id and l.restaurant_id = h.restaurant_id
      join costing.recipe_cost_snapshots s on s.id = l.snapshot_id and s.created_at = b.at
  ), price as (
    select i.name, p.valid_from
      from costing.price_records p
      join catalog.purchase_products pp on pp.id = p.purchase_product_id
      join catalog.ingredients i on i.id = pp.ingredient_id
     where p.id = p_price_record_id
  )
  select price.name, price.valid_from, s.created_at, s.recipe_id, x.name, s.restaurant_id, o.name, b.total_cost, s.total_cost,
         s.total_cost - b.total_cost,
         case when b.total_cost > 0 then round((s.total_cost - b.total_cost) / b.total_cost * 100, 2) end,
         b.recipe_version_id is distinct from s.recipe_version_id and b.recipe_version_id is not null,
         count(*) over ()
    from (select distinct snapshot_id from hit) h
    cross join price
    join costing.recipe_cost_snapshots s on s.id = h.snapshot_id
    join recipes.recipes x on x.id = s.recipe_id and x.deleted_at is null
    join org.restaurants o on o.id = s.restaurant_id
    left join lateral (
      select p.total_cost, p.recipe_version_id from costing.recipe_cost_snapshots p
       where p.recipe_id = s.recipe_id and p.restaurant_id = s.restaurant_id and p.entry_number < s.entry_number
       order by p.entry_number desc
       limit 1) b on true
   where x.id in (select costing.visible_recipe_ids())
   order by o.name, abs(s.total_cost - b.total_cost) desc nulls last, x.name, s.id
   limit least(greatest(coalesce(p_limit, 200), 1), 200) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function costing.price_impact(uuid, integer, integer) is
  'Antes y después de un precio, por receta y local, paginado (hasta 200). Solo las recetas que lo usan, directo o por una preparación, en los locales donde la sesión ve costos y que la sesión ve. La diferencia incluye lo que entró en la misma tanda; version_changed avisa si cambió también la versión. Sin permiso, no devuelve filas.';

-- La lista de costos de un local, con el nombre de cada receta (está en otro esquema), paginada. Con p_recipe_id, una sola.
create function costing.restaurant_costs(p_restaurant_id uuid, p_search text default null, p_reliability costing.cost_reliability default null,
                                         p_limit integer default 50, p_offset integer default 0, p_recipe_id uuid default null)
returns table (recipe_id uuid, code text, name text, recipe_type text, recipe_version_id uuid, portions integer, base_unit text,
               total_cost numeric, total_gross_cost numeric, cost_per_base_unit numeric, cost_per_portion numeric,
               reliability costing.cost_reliability, updated_at timestamptz, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
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
     order by x.name, c.recipe_id
     limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid) is
  'Los costos vigentes de un local, con el nombre de cada receta que la sesión ve, paginados (hasta 200 por página). Pide recipes.view_costs en el local.';

-- Las tarjetas de arriba de la lista.
create function costing.restaurant_cost_summary(p_restaurant_id uuid)
returns table (total bigint, complete bigint, stale bigint, incomplete bigint, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission('recipes.view_costs', p_restaurant_id), 'ver costos de este local');
  return query
    select count(*), count(*) filter (where c.reliability in ('verified', 'estimated')),
           count(*) filter (where c.reliability = 'stale'), count(*) filter (where c.reliability = 'incomplete'), max(c.updated_at)
      from costing.recipe_cost_current c
     where c.restaurant_id = p_restaurant_id and c.deleted_at is null
       and c.recipe_id in (select costing.visible_recipe_ids());
end
$$;
comment on function costing.restaurant_cost_summary(uuid) is
  'Cuántas recetas de un local están al día, desactualizadas o incompletas, y la última actualización. Pide recipes.view_costs en el local.';

revoke execute on function costing.recalc_status(), costing.price_impact(uuid, integer, integer),
  costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid), costing.restaurant_cost_summary(uuid) from public;
grant execute on function costing.recalc_status(), costing.price_impact(uuid, integer, integer),
  costing.restaurant_costs(uuid, text, costing.cost_reliability, integer, integer, uuid), costing.restaurant_cost_summary(uuid) to authenticated;
