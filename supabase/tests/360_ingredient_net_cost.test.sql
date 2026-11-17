-- La Chef ve el costo neto de la materia prima (ADR-0054): costing.ingredient_net_cost pide recipes.view_costs, no
-- prices.view, y devuelve solo lo que muestra la ficha.
-- Personas del seed: Dirección 402, Chef de Demo Pastas 405 (marca 101), Compras 408, Cocinera 409 (local 201).
-- Locales: Demo Pastas Centro 201 (marca 101) y Demo Parrilla Centro 203 (marca 102).
-- Materias primas: Tomate perita 801 (con precio y pelado aprobado), Cebolla 802 (con precio, sin limpieza aprobada),
-- Queso provolone 825 (sin precio).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(20);

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
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.unit(p_code text) returns uuid language sql as $$
  select id from catalog.units where code = p_code and deleted_at is null
$$;
create function pg_temp.proc(p_code text) returns uuid language sql as $$
  select id from catalog.yield_processes where code = p_code and group_id = '00000000-0000-4000-8000-000000000001'
$$;
grant execute on function pg_temp.u(int), pg_temp.unit(text), pg_temp.proc(text) to authenticated;
-- Lo que la ficha le pide a la base: 1 kg de una materia prima en un local, limpio con un proceso.
create function pg_temp.net(p_user uuid, p_ingredient int, p_restaurant int, p_process text, p_column text)
returns text language sql as $$
  select pg_temp.q(p_user, format(
    'select %s::text from costing.ingredient_net_cost(pg_temp.u(%s), pg_temp.u(%s), 1000, pg_temp.unit(''g''), %s)',
    p_column, p_ingredient, p_restaurant, coalesce(format('pg_temp.proc(%L)', p_process), 'null')))
$$;
-- Lo mismo con la función de siempre (prices.view), para comparar.
create function pg_temp.line(p_user uuid, p_ingredient int, p_basis text, p_process text)
returns text language sql as $$
  select pg_temp.q(p_user, format(
    'select line_cost::text from costing.ingredient_line_cost(pg_temp.u(%s), pg_temp.u(201), 1000, pg_temp.unit(''g''), %L, %s)',
    p_ingredient, p_basis, coalesce(format('pg_temp.proc(%L)', p_process), 'null')))
$$;

-- La Chef no tiene prices.view: la función de siempre la sigue rechazando.
select is(pg_temp.line(pg_temp.u(405), 801, 'purchase', null), 'ERROR 42501',
          'la Chef sigue sin poder pedir el costo de una línea con prices.view');

-- La Chef ve el costo neto en un local de su marca, igual al que calcula el motor para Dirección.
select isnt(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'net'), null, 'la Chef recibe el costo neto en un local de su marca');
select is(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'net'), pg_temp.line(pg_temp.u(402), 801, 'clean', 'PELADO'),
          'el neto es el mismo que calcula ingredient_line_cost');
select is(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'gross'), pg_temp.line(pg_temp.u(402), 801, 'purchase', null),
          'el bruto es el mismo que calcula ingredient_line_cost');
select is(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'net_status'), 'ok', 'con precio y pelado aprobado, el neto está al día');
select is(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'gross_status'), 'ok', 'con precio, el bruto está al día');
select is(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'concat_ws(''/'', stale, inherited, valid_from)'),
          pg_temp.q(pg_temp.u(402), $$ select concat_ws('/', stale, inherited, valid_from)
                                          from costing.resolve_price(pg_temp.u(801), pg_temp.u(201)) $$),
          'vencido, heredado y desde cuándo, igual que el precio que vale');
select isnt(pg_temp.net(pg_temp.u(405), 801, 201, 'PELADO', 'valid_from'), null, 'trae desde cuándo vale el precio');
-- Sin conversión de unidad no hay bruto, pero el dato del precio se sigue viendo.
select is(pg_temp.q(pg_temp.u(405), $$ select concat_ws('/', gross_status, valid_from is not null)
                                         from costing.ingredient_net_cost(pg_temp.u(801), pg_temp.u(201), 1, pg_temp.unit('pack'), null) $$),
          'missing_conversion/t', 'sin conversión, el bruto queda vacío y la fecha del precio se ve igual');

-- Sin limpieza aprobada o sin proceso, el neto queda vacío con su motivo (nunca el bruto ni $ 0).
select is(pg_temp.net(pg_temp.u(405), 802, 201, 'LIMPIEZA', 'coalesce(net::text, net_status)'), 'missing_yield',
          'sin limpieza aprobada, el neto queda vacío: falta el rendimiento');
select is(pg_temp.net(pg_temp.u(405), 801, 201, null, 'coalesce(net::text, net_status)'), 'missing_yield',
          'sin proceso de limpieza, el neto queda vacío: falta el rendimiento');
select is(pg_temp.net(pg_temp.u(405), 825, 201, 'LIMPIEZA', 'coalesce(gross::text, gross_status)'), 'missing_price',
          'sin precio, el bruto queda vacío: falta el precio');

-- Fuera de su alcance o sin permiso de costos, nada.
select is(pg_temp.net(pg_temp.u(405), 801, 203, 'PELADO', 'net'), 'ERROR 42501', 'la Chef no lo ve en un local de otra marca');
select is(pg_temp.net(pg_temp.u(408), 801, 201, 'PELADO', 'net'), 'ERROR 42501',
          'Compras no ve costos (ve el precio en su tarjeta, no el neto)');
select is(pg_temp.net(pg_temp.u(409), 801, 201, 'PELADO', 'net'), 'ERROR 42501', 'la Cocinera no ve costos');
-- Una materia prima real de otro grupo, pedida con un local de este.
insert into org.groups (id, name) values ('99999999-0000-4000-8000-0000000000a1', 'Grupo Dos de Prueba');
insert into catalog.ingredient_categories (id, group_id, name)
values ('99999999-0000-4000-8000-0000000000b1', '99999999-0000-4000-8000-0000000000a1', 'Verduras');
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
select '99999999-0000-4000-8000-0000000000c1', '99999999-0000-4000-8000-0000000000a1', 'VER-0001', 'Tomate',
       '99999999-0000-4000-8000-0000000000b1', recipe_unit_id
  from catalog.ingredients where id = pg_temp.u(801);
select is(pg_temp.q(pg_temp.u(402), $$ select net::text from costing.ingredient_net_cost('99999999-0000-4000-8000-0000000000c1',
                                         pg_temp.u(201), 1000, pg_temp.unit('g'), null) $$),
          'ERROR 42501', 'una materia prima de otro grupo se rechaza');
select is(pg_temp.q(pg_temp.u(402), $$ select net::text from costing.ingredient_net_cost(gen_random_uuid(), pg_temp.u(201),
                                         1000, pg_temp.unit('g'), null) $$),
          'ERROR 42501', 'una materia prima que no existe se rechaza');
-- Una materia prima borrada no tiene ficha (dentro de esta transacción, que se deshace al final).
update catalog.ingredients set deleted_at = now() where id = pg_temp.u(825);
select is(pg_temp.net(pg_temp.u(405), 825, 201, null, 'net'), 'ERROR 42501', 'una materia prima borrada se rechaza');
update catalog.ingredients set deleted_at = null where id = pg_temp.u(825);

-- Solo estas columnas: nunca el producto, el proveedor ni el registro de precio (ADR-0054).
select is(pg_get_function_result('costing.ingredient_net_cost(uuid, uuid, numeric, uuid, uuid)'::regprocedure),
          'TABLE(gross numeric, net numeric, gross_status text, net_status text, stale boolean, inherited boolean, valid_from date)',
          'devuelve solo costos, estados y del precio si está vencido, si es heredado y desde cuándo');

-- La interna no se puede llamar directo.
select is(pg_temp.q(pg_temp.u(402), $$ select status from costing.ingredient_line_cost_internal(pg_temp.u(801), pg_temp.u(201),
                                         1000, pg_temp.unit('g'), 'purchase', null, null) $$),
          'ERROR 42501', 'nadie llama directo a ingredient_line_cost_internal');

select * from finish();
rollback;
