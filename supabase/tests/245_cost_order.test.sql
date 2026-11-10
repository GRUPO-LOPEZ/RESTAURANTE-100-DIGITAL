-- Rediseño, PR 2 (ADR-0036): la lista de costos se ordena por columna en la base. Cada orden se compara con una consulta
-- independiente, hecha afuera de la sesión (el Controller ve todas las recetas del local). Lo demás no cambia.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(25);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
-- La lista del Controller en Pastas Centro con un orden: los códigos, en el orden en que vienen.
create function pg_temp.codes(p_order text, p_limit int default 200, p_offset int default 0) returns text language sql as $$
  select pg_temp.q(pg_temp.u(407), format(
    'select string_agg(code, '','' order by n) from costing.restaurant_costs(%L, null, null, %s, %s, null, %L) with ordinality t(recipe_id, code, name, recipe_type, recipe_version_id, portions, base_unit, total_cost, total_gross_cost, cost_per_base_unit, cost_per_portion, reliability, updated_at, total_rows, n)',
    pg_temp.u(201), p_limit, p_offset, p_order))
$$;
-- Lo mismo, armado afuera de la sesión con la tabla de costos vigentes.
create function pg_temp.expected(p_order_sql text) returns text language plpgsql as $$
declare
  v text;
begin
  execute format(
    'select string_agg(x.code, '','' order by %s) from costing.recipe_cost_current c join recipes.recipes x on x.id = c.recipe_id and x.deleted_at is null where c.restaurant_id = %L and c.deleted_at is null',
    p_order_sql, pg_temp.u(201)) into v;
  return v;
end
$$;

-- Los datos sirven para probar el orden: si dieran igual en cualquier sentido, una prueba podría pasar sin
-- ordenar nada. Varias recetas con costo, costos distintos, varias confiabilidades y alguna sin costo por porción.
create function pg_temp.cc(p_where text) returns int language plpgsql as $$
declare v int;
begin
  execute format('select count(*)::int from costing.recipe_cost_current c where c.restaurant_id = %L and c.deleted_at is null and %s', pg_temp.u(201), p_where) into v;
  return v;
end
$$;
select cmp_ok(pg_temp.cc('true'), '>', 3, 'Pastas Centro tiene varias recetas con costo');
select cmp_ok((select count(distinct total_cost)::int from costing.recipe_cost_current where restaurant_id = pg_temp.u(201) and deleted_at is null and total_cost is not null),
  '>', 2, 'con costos totales distintos');
select cmp_ok((select count(distinct reliability)::int from costing.recipe_cost_current where restaurant_id = pg_temp.u(201) and deleted_at is null),
  '>', 1, 'con más de una confiabilidad');
select cmp_ok(pg_temp.cc('c.cost_per_portion is null'), '>', 0, 'y alguna sin costo por porción (para ver los vacíos al final)');

-- Cada una de las 12 combinaciones, contra la consulta independiente. Los vacíos van al final; el desempate es nombre y receta.
select is(pg_temp.codes(null), pg_temp.expected('lower(x.name), x.name, c.recipe_id'), 'sin orden, por nombre');
select is(pg_temp.codes('name'), pg_temp.expected('lower(x.name), x.name, c.recipe_id'), 'por nombre');
select is(pg_temp.codes('-name'), pg_temp.expected('lower(x.name) desc, x.name, c.recipe_id'), 'por nombre, de la Z a la A');
select is(pg_temp.codes('code'), pg_temp.expected('x.code, x.name, c.recipe_id'), 'por código');
select is(pg_temp.codes('-code'), pg_temp.expected('x.code desc, x.name, c.recipe_id'), 'por código, al revés');
select is(pg_temp.codes('total'), pg_temp.expected('c.total_cost nulls last, x.name, c.recipe_id'), 'por costo total, de menor a mayor');
select is(pg_temp.codes('-total'), pg_temp.expected('c.total_cost desc nulls last, x.name, c.recipe_id'), 'por costo total, de mayor a menor, sin costo al final');
select is(pg_temp.codes('portion'), pg_temp.expected('c.cost_per_portion nulls last, x.name, c.recipe_id'), 'por costo por porción, sin dato al final');
select is(pg_temp.codes('-portion'), pg_temp.expected('c.cost_per_portion desc nulls last, x.name, c.recipe_id'), 'por costo por porción, al revés, sin dato al final');
select is(pg_temp.codes('reliability'), pg_temp.expected('c.reliability, x.name, c.recipe_id'), 'por confiabilidad, de verificada a incompleta');
select is(pg_temp.codes('-reliability'), pg_temp.expected('c.reliability desc, x.name, c.recipe_id'), 'por confiabilidad, de incompleta a verificada');
select is(pg_temp.codes('updated'), pg_temp.expected('c.updated_at nulls last, x.name, c.recipe_id'), 'por actualización, lo más viejo primero');
select is(pg_temp.codes('-updated'), pg_temp.expected('c.updated_at desc nulls last, x.name, c.recipe_id'), 'por actualización, lo último primero');

-- El sentido cambia el resultado de verdad (con estos datos, invertir no puede dar lo mismo).
select isnt(pg_temp.codes('-total'), pg_temp.codes('total'), 'invertir el costo cambia la lista');
select isnt(pg_temp.codes('-name'), pg_temp.codes('name'), 'invertir el nombre cambia la lista');

-- Un orden que no está en la lista no rompe nada: vuelve al de siempre. Dos guiones tampoco invierten.
select is(pg_temp.codes('total; drop table x'), pg_temp.expected('lower(x.name), x.name, c.recipe_id'), 'un orden desconocido usa el de siempre');
select is(pg_temp.codes('--total'), pg_temp.expected('lower(x.name), x.name, c.recipe_id'), 'dos guiones no es un orden');

-- El orden se aplica antes de paginar: la segunda página de a uno es la segunda receta de la lista completa.
select is(pg_temp.codes('-total', 1, 1), split_part(pg_temp.expected('c.total_cost desc nulls last, x.name, c.recipe_id'), ',', 2),
  'pagina sobre la lista ya ordenada');

-- Los permisos no cambian.
select ok(pg_temp.q(pg_temp.u(409), format('select count(*)::text from costing.restaurant_costs(%L, null, null, 50, 0, null, %L)', pg_temp.u(201), 'total'))
          like 'ERROR%No tenés permiso%', 'la Cocinera sigue sin ver costos');
select hasnt_function('costing', 'restaurant_costs', array['uuid', 'text', 'costing.cost_reliability', 'integer', 'integer', 'uuid'],
  'no queda la versión anterior');
select function_privs_are('costing', 'restaurant_costs', array['uuid', 'text', 'costing.cost_reliability', 'integer', 'integer', 'uuid', 'text'],
  'anon', array[]::text[], 'anon no la ejecuta');

select * from finish();
rollback;
