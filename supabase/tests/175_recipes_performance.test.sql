-- Recetas con volumen (revisión de base, G1): con 2.000 recetas y 20.000 líneas, lo que lee cada rol
-- responde en menos de 300 ms. Las políticas usan conjuntos que se calculan una vez por consulta.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(2);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

do $$ begin perform core.set_change_context('Carga de prueba', 'maintenance'); end $$;
create temporary table load_recipes as
  select g, gen_random_uuid() as recipe_id, gen_random_uuid() as version_id,
         case when g % 2 = 0 then pg_temp.u(101) else pg_temp.u(102) end as brand_id
    from generate_series(1, 2000) as g;
insert into recipes.recipes (id, group_id, brand_id, scope_type, code, name, recipe_type)
select recipe_id, pg_temp.u(1), brand_id, 'brand', 'CARGA-' || g, 'Receta de carga ' || g, 'dish' from load_recipes;
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id)
select version_id, pg_temp.u(1), recipe_id, 1, 1, (select id from catalog.units where code = 'unit') from load_recipes;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select pg_temp.u(1), l.version_id, n, pg_temp.u(800 + n), 100, (select id from catalog.units where code = 'g')
  from load_recipes l cross join generate_series(1, 10) as n;
update recipes.recipe_versions set status = 'in_review' where id in (select version_id from load_recipes);
update recipes.recipe_versions set status = 'approved' where id in (select version_id from load_recipes);
update recipes.recipe_versions set status = 'published', published_at = now() where id in (select version_id from load_recipes);
-- La mitad, asignada al local de la Cocinera.
insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
select pg_temp.u(1), recipe_id, pg_temp.u(201), current_date - 1 from load_recipes where brand_id = pg_temp.u(101);
analyze recipes.recipes, recipes.recipe_versions, recipes.recipe_components, recipes.recipe_assignments;

create temporary table timings (who text, what text, ms numeric);
grant insert on timings to authenticated;
create function pg_temp.measure(p_user uuid, p_who text, p_what text, p_sql text)
returns void
language plpgsql
as $$
declare
  t0 timestamptz;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  t0 := clock_timestamp();
  execute p_sql;
  insert into timings values (p_who, p_what, extract(epoch from clock_timestamp() - t0) * 1000);
  reset role;
  perform set_config('request.jwt.claims', '', true);
end
$$;

select pg_temp.measure(pg_temp.u(409), 'Cocinera', 'cuenta sus recetas', 'select count(*) from recipes.recipes');
select pg_temp.measure(pg_temp.u(409), 'Cocinera', 'primera página por nombre',
  'select id from recipes.recipes order by name limit 20');
select pg_temp.measure(pg_temp.u(409), 'Cocinera', 'ficha de cocina',
  $$select recipes.kitchen_card((select id from recipes.recipes where code = 'CARGA-2'))$$);
select pg_temp.measure(pg_temp.u(405), 'Chef de marca', 'versiones', 'select count(*) from recipes.recipe_versions');
select pg_temp.measure(pg_temp.u(405), 'Chef de marca', 'líneas de una receta',
  $$select count(*) from recipes.recipe_components
     where recipe_version_id = (select v.id from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id
                                 where r.code = 'CARGA-4')$$);
select pg_temp.measure(pg_temp.u(407), 'Controller', 'cuenta las recetas', 'select count(*) from recipes.recipes');

select is((select count(*)::int from timings), 6, 'se midieron las 6 lecturas');
select ok((select bool_and(ms < 300) from timings),
  'con 2.000 recetas y 20.000 líneas, cada lectura responde en menos de 300 ms: '
  || (select string_agg(who || ' ' || what || ' ' || round(ms) || ' ms', ', ') from timings));

select * from finish();
rollback;
