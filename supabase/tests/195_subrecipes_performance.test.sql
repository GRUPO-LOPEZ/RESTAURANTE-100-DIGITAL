-- Subrecetas con volumen (ADR-0025): 2.000 platos que usan preparaciones, y 200 preparaciones en 20
-- cadenas de 10 niveles. Lo que recorre las subrecetas (lo que ve cada rol, la ficha de cocina, los
-- alérgenos y el control de ciclos) responde en menos de 300 ms.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(2);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

do $$ begin perform core.set_change_context('Carga de prueba', 'maintenance'); end $$;
-- Preparaciones del grupo: cadena c (1 a 20), nivel l (1 a 10); el nivel l usa el l - 1 de su cadena.
create temporary table load_preps as
  select c, l, gen_random_uuid() as recipe_id, gen_random_uuid() as version_id
    from generate_series(1, 20) as c cross join generate_series(1, 10) as l;
insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type)
select recipe_id, pg_temp.u(1), 'group', 'PREP-' || c || '-' || l, 'Preparación de carga ' || c || '-' || l, 'preparation'
  from load_preps;
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id)
select version_id, pg_temp.u(1), recipe_id, 1, 1, (select id from catalog.units where code = 'kg') from load_preps;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select pg_temp.u(1), p.version_id, n, pg_temp.u(800 + n + p.l), 100, (select id from catalog.units where code = 'g')
  from load_preps p cross join generate_series(1, 5) as n;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select pg_temp.u(1), p.version_id, 6, d.recipe_id, 100, (select id from catalog.units where code = 'g'), 'finished'
  from load_preps p join load_preps d on d.c = p.c and d.l = p.l - 1;

-- Platos de las marcas: cada uno usa la preparación más alta de una cadena.
create temporary table load_dishes as
  select g, gen_random_uuid() as recipe_id, gen_random_uuid() as version_id,
         case when g % 2 = 0 then pg_temp.u(101) else pg_temp.u(102) end as brand_id
    from generate_series(1, 2000) as g;
insert into recipes.recipes (id, group_id, brand_id, scope_type, code, name, recipe_type)
select recipe_id, pg_temp.u(1), brand_id, 'brand', 'CARGA-' || g, 'Plato de carga ' || g, 'dish' from load_dishes;
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id)
select version_id, pg_temp.u(1), recipe_id, 1, 1, (select id from catalog.units where code = 'unit') from load_dishes;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select pg_temp.u(1), d.version_id, n, pg_temp.u(800 + n), 100, (select id from catalog.units where code = 'g')
  from load_dishes d cross join generate_series(1, 9) as n;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select pg_temp.u(1), d.version_id, 10, p.recipe_id, 200, (select id from catalog.units where code = 'g'), 'finished'
  from load_dishes d join load_preps p on p.c = d.g % 20 + 1 and p.l = 10;

update recipes.recipe_versions set status = 'in_review'
 where id in (select version_id from load_preps union all select version_id from load_dishes);
update recipes.recipe_versions set status = 'approved'
 where id in (select version_id from load_preps union all select version_id from load_dishes);
update recipes.recipe_versions set status = 'published', published_at = now()
 where id in (select version_id from load_preps union all select version_id from load_dishes);
-- La mitad de los platos, asignada al local de la Cocinera (las preparaciones no: las ve por los platos).
insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
select pg_temp.u(1), recipe_id, pg_temp.u(201), current_date - 1 from load_dishes where brand_id = pg_temp.u(101);
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
  if p_user is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
  end if;
  t0 := clock_timestamp();
  execute p_sql;
  insert into timings values (p_who, p_what, extract(epoch from clock_timestamp() - t0) * 1000);
  reset role;
  perform set_config('request.jwt.claims', '', true);
end
$$;

select pg_temp.measure(pg_temp.u(409), 'Cocinera', 'cuenta sus recetas (con las preparaciones)', 'select count(*) from recipes.recipes');
select pg_temp.measure(pg_temp.u(409), 'Cocinera', 'ficha de cocina de un plato',
  $$select recipes.kitchen_card((select id from recipes.recipes where code = 'CARGA-2'))$$);
select pg_temp.measure(pg_temp.u(409), 'Cocinera', 'alérgenos de un plato con 10 niveles',
  $$select count(*) from recipes.version_allergens((select v.id from recipes.recipe_versions v
                                                       join recipes.recipes r on r.id = v.recipe_id where r.code = 'CARGA-2'))$$);
select pg_temp.measure(pg_temp.u(405), 'Chef de marca', 'busca preparaciones',
  $$select count(*) from recipes.search_subrecipes('carga', (select id from recipes.recipes where code = 'CARGA-4'))$$);
select pg_temp.measure(pg_temp.u(405), 'Chef de marca', 'dónde se usa una preparación',
  $$select count(*) from recipes.recipe_usage((select id from recipes.recipes where code = 'PREP-1-10'))$$);
select pg_temp.measure(null, 'Base', 'control de ciclo por 10 niveles',
  $$select recipes.reaches((select id from recipes.recipes where code = 'PREP-1-10'),
                           (select id from recipes.recipes where code = 'CARGA-20'), false)$$);
select pg_temp.measure(null, 'Base', 'validar las líneas (círculo y niveles para los dos lados)',
  $$select * from recipes.first_invalid_line((select v.id from recipes.recipe_versions v
                                                join recipes.recipes r on r.id = v.recipe_id where r.code = 'PREP-1-5'))$$);
select pg_temp.measure(pg_temp.u(407), 'Controller', 'cuenta todas las recetas', 'select count(*) from recipes.recipes');
select pg_temp.measure(null, 'Base', 'avisos de una preparación que usan 100 platos',
  $$select recipes.notify_recipe_changed((select v.id from recipes.recipe_versions v
                                            join recipes.recipes r on r.id = v.recipe_id where r.code = 'PREP-1-10'), null)$$);

select is((select count(*)::int from timings), 9, 'se midieron las 9 operaciones');
select ok((select bool_and(ms < 300) from timings),
  'con 2.000 platos y 200 preparaciones en cadenas de 10 niveles, cada operación responde en menos de 300 ms: '
  || (select string_agg(who || ' ' || what || ' ' || round(ms) || ' ms', ', ') from timings));

select * from finish();
rollback;
