-- Fase 2 · Etapa 2.5, PR 1: calidad de datos (ADR-0033; sección 16 del documento de Soy). Se cuentan hechos, sin ningún
-- índice inventado, y cada indicador abre la lista exacta de lo que hay que corregir. Solo lee: sin tablas nuevas.
-- Una sola función arma los registros de cada indicador: los números y las listas salen de ahí, y no pueden diferir.

-- Las materias primas con otra del grupo muy parecida, por nombre o alias. Es del grupo y no del local, y comparar nombres
-- es caro: se calcula una vez por noche y no cada vez que se abre la pantalla.
create materialized view reporting.mv_ingredient_twins as
  with terms as (
    select i.id, i.group_id, lower(i.name) as term
      from catalog.ingredients i
     where i.deleted_at is null and i.is_active
    union
    select i.id, i.group_id, a.alias
      from catalog.ingredients i
      join catalog.ingredient_aliases a on a.ingredient_id = i.id and a.deleted_at is null
     where i.deleted_at is null and i.is_active
  )
  select distinct on (a.id) a.id as ingredient_id, a.group_id, b.id as twin_id
    from terms a
    join terms b on b.group_id = a.group_id and b.id <> a.id and extensions.similarity(a.term, b.term) >= 0.6
   order by a.id, b.id;
create unique index mv_ingredient_twins_key on reporting.mv_ingredient_twins (ingredient_id);
revoke all on reporting.mv_ingredient_twins from public, anon, authenticated, service_role;
comment on materialized view reporting.mv_ingredient_twins is
  'Materias primas con otra del grupo muy parecida, por nombre o alias (parecido de 0,6 o más). Se recalcula cada noche.';
comment on column reporting.mv_ingredient_twins.ingredient_id is 'Materia prima.';
comment on column reporting.mv_ingredient_twins.group_id is 'Grupo.';
comment on column reporting.mv_ingredient_twins.twin_id is 'La materia prima a la que se parece. El nombre se lee en el momento.';

-- pg_cron usa UTC: 7:00 son las 4:00 de la Argentina, después de la tarea diaria de costos.
select cron.schedule('grupo-lf-calidad-parecidos', '0 7 * * *', 'refresh materialized view concurrently reporting.mv_ingredient_twins');

-- Todos los registros de todos los indicadores de un local, sin mirar la sesión.
create function costing.quality_items(p_restaurant_id uuid)
returns table (indicator text, kind text, item_id uuid, item text, detail text, ok boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with place as materialized (
    select r.id, r.group_id, r.brand_id from org.restaurants r where r.id = p_restaurant_id and r.deleted_at is null
  ), ing as materialized (
    select i.id, i.name
      from catalog.ingredients i join place on place.group_id = i.group_id
     where i.deleted_at is null and i.is_active
  ), prices as materialized (
    select p.ingredient_id, p.stale, p.status from costing.price_rows(p_restaurant_id, recipes.today(), null) p
  ), twins as materialized (
    -- El nombre se lee ahora: una materia prima que se dio de baja deja de contar sin esperar a la noche.
    select t.ingredient_id, min(b.name) as twin
      from reporting.mv_ingredient_twins t
      join place on place.group_id = t.group_id
      join catalog.ingredients b on b.id = t.twin_id and b.deleted_at is null and b.is_active
     group by t.ingredient_id
  ), universe as materialized (
    -- Lo que el local usa, y lo que todavía no se publicó en su marca o en el grupo: una receta importada se ve como
    -- pendiente aunque nadie la haya asignado. Como los locales no se suman, no se cuenta dos veces.
    select u.id from costing.restaurant_recipes(p_restaurant_id) u (id)
    union
    select r.id
      from recipes.recipes r join place on place.group_id = r.group_id
     where (r.brand_id is null or r.brand_id = place.brand_id) and (r.restaurant_id is null or r.restaurant_id = place.id)
       and not exists (select 1 from recipes.recipe_versions v where v.recipe_id = r.id and v.status = 'published')
  ), rec as materialized (
    -- La versión que cuenta: la vigente, o la última si todavía no hay ninguna publicada.
    select r.id, r.name, v.id as version_id, v.status, v.yield_quantity, v.yield_unit_id
      from universe u
      join recipes.recipes r on r.id = u.id and r.deleted_at is null and r.is_active
      join place on place.group_id = r.group_id
      left join lateral (select x.id, x.status, x.yield_quantity, x.yield_unit_id
                           from recipes.recipe_versions x
                          where x.recipe_id = r.id and x.status <> 'archived'
                          order by (x.status = 'published') desc, x.version_number desc
                          limit 1) v on true
  ), costs as materialized (
    select c.recipe_id, c.reliability
      from costing.recipe_cost_current c
     where c.restaurant_id = p_restaurant_id and c.deleted_at is null
  ), inactive as materialized (
    -- Las versiones que usan una materia prima o una preparación que ya no está activa.
    select distinct c.recipe_version_id
      from recipes.recipe_components c
      left join catalog.ingredients i on i.id = c.ingredient_id
      left join recipes.recipes s on s.id = c.sub_recipe_id
     where c.recipe_version_id in (select r.version_id from rec r) and c.deleted_at is null
       and (i.deleted_at is not null or i.is_active is false or s.deleted_at is not null or s.is_active is false)
  )
  select 'ingredient_price', 'ingredient', i.id, i.name,
         case when p.status = 'missing_legal_entity' then 'Falta la razón social del local' end, coalesce(p.status = 'ok', false)
    from ing i left join prices p on p.ingredient_id = i.id
  union all
  -- Solo los que tienen precio: uno sin precio ya cuenta en el indicador anterior.
  select 'price_stale', 'ingredient', i.id, i.name, null, not p.stale
    from ing i join prices p on p.ingredient_id = i.id and p.stale is not null
  union all
  select 'ingredient_unit', 'ingredient', i.id, i.name, null,
         exists (select 1 from catalog.purchase_products pp
                  where pp.ingredient_id = i.id and pp.deleted_at is null and pp.is_active
                    and catalog.missing_conversion(i.id, pp.content_unit_id) is null)
    from ing i
  union all
  select 'ingredient_yield', 'ingredient', i.id, i.name, null,
         exists (select 1 from catalog.ingredient_yield_profiles y
                  where y.ingredient_id = i.id and y.deleted_at is null and y.status = 'approved')
    from ing i
  union all
  select 'ingredient_duplicate', 'ingredient', i.id, i.name, 'Se parece a ' || t.twin, t.ingredient_id is null
    from ing i left join twins t on t.ingredient_id = i.id
  union all
  select 'recipe_cost', 'recipe', r.id, r.name, null, coalesce(c.reliability in ('verified', 'estimated'), false)
    from rec r left join costs c on c.recipe_id = r.id
  union all
  select 'recipe_approved', 'recipe', r.id, r.name, null, coalesce(r.status = 'published', false)
    from rec r
  union all
  select 'recipe_review', 'recipe', r.id, r.name, null,
         not exists (select 1 from recipes.recipe_versions x where x.recipe_id = r.id and x.status = 'in_review')
    from rec r
  union all
  select 'recipe_photo', 'recipe', r.id, r.name, null,
         exists (select 1 from recipes.recipe_media m where m.recipe_version_id = r.version_id and m.deleted_at is null)
    from rec r
  union all
  select 'recipe_yield', 'recipe', r.id, r.name, null, r.yield_quantity is not null and r.yield_unit_id is not null
    from rec r
  union all
  select 'recipe_components', 'recipe', r.id, r.name, null, x.recipe_version_id is null
    from rec r left join inactive x on x.recipe_version_id = r.version_id
$$;
comment on function costing.quality_items(uuid) is
  'Interna: los registros de cada indicador de calidad de un local, con si cumplen. No mira la sesión: de acá salen los números y las listas.';
revoke execute on function costing.quality_items(uuid) from public;

-- Se entra con lo que permite corregir o controlar el recetario. El cocinero, que solo ve la cocina, no.
create function costing.quality_allowed(p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select core.has_permission('recipes.draft', p_restaurant_id)
      or core.has_permission('recipes.view_costs', p_restaurant_id)
      or core.has_permission('prices.view', p_restaurant_id)
$$;
comment on function costing.quality_allowed(uuid) is 'Interna: si la sesión entra a la calidad de datos de un local.';
revoke execute on function costing.quality_allowed(uuid) from public;

-- Los indicadores que la sesión puede ver en un local: cada uno pide el permiso de su dato. Un precio lleva el nombre de
-- la materia prima, así que también pide ver el catálogo.
create function costing.quality_indicators(p_restaurant_id uuid)
returns setof text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_recipes boolean := core.has_permission('recipes.view', p_restaurant_id);
  v_catalog boolean := core.has_permission('catalog.view', p_restaurant_id);
begin
  perform org.require(costing.quality_allowed(p_restaurant_id), 'ver la calidad de datos de este local');
  if v_recipes then
    return query select unnest(array['recipe_approved', 'recipe_review', 'recipe_yield', 'recipe_photo', 'recipe_components']);
  end if;
  if core.has_permission('recipes.view_costs', p_restaurant_id) then
    return next 'recipe_cost';
  end if;
  if v_catalog then
    return query select unnest(array['ingredient_unit', 'ingredient_yield', 'ingredient_duplicate']);
    if core.has_permission('prices.view', p_restaurant_id) then
      return query select unnest(array['ingredient_price', 'price_stale']);
    end if;
  end if;
end
$$;
comment on function costing.quality_indicators(uuid) is 'Interna: los indicadores de calidad que la sesión puede ver en un local.';
revoke execute on function costing.quality_indicators(uuid) from public;

-- Cuentan todos los registros, también los que la sesión no ve: el número tiene que ser real. Lo que no se ve solo suma
-- en hidden, sin nombres.
create function costing.data_quality(p_restaurant_id uuid)
returns table (indicator text, done bigint, total bigint, hidden bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seen uuid[];
begin
  perform org.require(costing.quality_allowed(p_restaurant_id), 'ver la calidad de datos de este local');
  v_seen := array(select costing.visible_recipe_ids());
  return query
    select k.indicator, count(q.item_id) filter (where q.ok), count(q.item_id),
           count(q.item_id) filter (where not q.ok and q.kind = 'recipe' and not q.item_id = any (v_seen))
      from costing.quality_indicators(p_restaurant_id) k (indicator)
      left join costing.quality_items(p_restaurant_id) q on q.indicator = k.indicator
     group by k.indicator;
end
$$;
comment on function costing.data_quality(uuid) is
  'Por indicador, cuántos registros de un local cumplen, sobre cuántos, y cuántos de los que faltan la sesión no puede ver. Trae también los que están en cero.';

create function costing.data_quality_items(p_restaurant_id uuid, p_indicator text, p_limit integer default 50, p_offset integer default 0)
returns table (kind text, item_id uuid, item text, detail text, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seen uuid[];
begin
  perform org.require(p_indicator in (select costing.quality_indicators(p_restaurant_id)), 'ver este indicador');
  v_seen := array(select costing.visible_recipe_ids());
  return query
    select q.kind, q.item_id, q.item, q.detail, count(*) over ()
      from costing.quality_items(p_restaurant_id) q
     where q.indicator = p_indicator and not q.ok and (q.kind <> 'recipe' or q.item_id = any (v_seen))
     order by q.item, q.item_id
     limit least(greatest(coalesce(p_limit, 50), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.data_quality_items(uuid, text, integer, integer) is
  'La lista de lo que hay que corregir en un indicador de un local, paginada. Solo trae lo que la sesión puede ver.';

-- Los locales donde se entra: una consulta liviana, para elegir.
create function costing.quality_places()
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.name
    from org.restaurants r
   where r.deleted_at is null and r.status = 'active'
     and r.id in (select core.permitted_restaurant_ids('recipes.draft')
                  union select core.permitted_restaurant_ids('recipes.view_costs')
                  union select core.permitted_restaurant_ids('prices.view'))
   order by r.name, r.id
$$;
comment on function costing.quality_places() is 'Los locales donde la sesión entra a la calidad de datos.';

-- Quien ve más de un local los compara. No se suman: el costo y el precio dependen del local. Cada local tarda: van de a pocos.
create function costing.data_quality_places(p_limit integer default 20, p_offset integer default 0)
returns table (restaurant_id uuid, restaurant text, indicator text, done bigint, total bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with places as (
    select p.id, p.name
      from costing.quality_places() p
     limit least(greatest(coalesce(p_limit, 20), 1), 20) offset greatest(coalesce(p_offset, 0), 0)
  )
  select p.id, p.name, q.indicator, q.done, q.total
    from places p
   cross join lateral costing.data_quality(p.id) q
   order by p.name, p.id, q.indicator
$$;
comment on function costing.data_quality_places(integer, integer) is 'Los indicadores de cada local donde la sesión entra a la calidad de datos, de a 20.';

revoke execute on function costing.data_quality(uuid), costing.data_quality_items(uuid, text, integer, integer),
  costing.quality_places(), costing.data_quality_places(integer, integer) from public;
grant execute on function costing.data_quality(uuid), costing.data_quality_items(uuid, text, integer, integer),
  costing.quality_places(), costing.data_quality_places(integer, integer) to authenticated;

-- Para lo que se lea desde reporting. No tiene permisos: por pantalla se lee con la sesión. Cruza todos los grupos, así
-- que antes de abrírsela a una cuenta técnica (Fase 5) hay que filtrarla por su alcance.
create view reporting.v_data_quality as
  select r.id as restaurant_id, r.brand_id, r.group_id, q.indicator, count(*) filter (where q.ok) as done, count(*) as total
    from org.restaurants r
   cross join lateral costing.quality_items(r.id) q
   where r.deleted_at is null and r.status = 'active'
   group by r.id, r.brand_id, r.group_id, q.indicator;
revoke all on reporting.v_data_quality from public, anon, authenticated, service_role;
comment on view reporting.v_data_quality is
  'Calidad de datos por local e indicador: cuántos registros cumplen y sobre cuántos. Sin sumar locales: el precio y el costo dependen del local.';
comment on column reporting.v_data_quality.restaurant_id is 'Local.';
comment on column reporting.v_data_quality.brand_id is 'Marca del local.';
comment on column reporting.v_data_quality.group_id is 'Grupo del local.';
comment on column reporting.v_data_quality.indicator is 'Indicador: por ejemplo ingredient_price o recipe_cost.';
comment on column reporting.v_data_quality.done is 'Cuántos registros cumplen.';
comment on column reporting.v_data_quality.total is 'Sobre cuántos registros se mide.';
