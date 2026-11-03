-- Fase 2 · Etapa 2.1 C, PR 2: subas en escalones (respuesta 8 de Soy, ADR-0030; ADR-0029). La variación
-- de un precio nuevo también se mide contra el que valía hace N días (30 por defecto) en ese lugar, y vale
-- la más grande: varias subas chicas seguidas llegan a Dirección cuando en total superan el %.
-- Personas del seed: ...0402 Dirección, ...0407 controller, ...0408 compras.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(21);

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
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.today_ar() returns date language sql as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date
$$;

-- Una materia prima de prueba, comprada por kg, con su historia de precios aprobados.
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
values (pg_temp.u(9951), pg_temp.u(1), 'PRUEBA-ESC-1', 'Materia prima en escalones', pg_temp.u(707),
        (select id from catalog.units where code = 'g'));
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
values (pg_temp.u(9952), pg_temp.u(1), 'PRUEBA-ESC-PROD', pg_temp.u(9951), 'Producto en escalones',
        (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g'));
create function pg_temp.price(p_price numeric, p_days_ago int) returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
  values (pg_temp.u(1), pg_temp.u(9952), 'group', pg_temp.today_ar() - p_days_ago, p_price, 'no_invoice', 'test_value')
$$;
create function pg_temp.propose(p_price numeric) returns text language sql as $$
  select pg_temp.q(pg_temp.u(408), format(
    $f$select costing.propose_price(%L, 'group', null, null, %L, %s, 'no_invoice', null, true, 0, null, 'manual', null, 'Prueba')::text$f$,
    pg_temp.u(9952), pg_temp.today_ar(), p_price))
$$;
create function pg_temp.changes(p_request text, p_key text) returns text language sql as $$
  select proposed_changes ->> p_key from workflow.approval_requests where id::text = p_request
$$;
create function pg_temp.goes_to_direction(p_request text) returns boolean language sql as $$
  select exists (select 1 from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
                  where w.code = 'costing.approve_price_direction' and r.proposed_changes ->> 'first_request_id' = p_request)
$$;
create temporary table reqs (k text primary key, id text);

-- Sin historia de hace 30 días: vale solo la comparación de hoy.
select pg_temp.price(1000, 10);
insert into reqs values ('sin_historia', pg_temp.propose(1100));
select is(pg_temp.changes((select id from reqs where k = 'sin_historia'), 'price_variation_pct'), '10.00',
  'sin precio de hace 30 días, la variación es la de hoy (10 %)');
select is(pg_temp.changes((select id from reqs where k = 'sin_historia'), 'price_variation_lookback_pct'), null,
  'y no hay comparación hacia atrás');
select is(pg_temp.q(pg_temp.u(407), format('select workflow.decide_approval(%L, ''rejected'', ''Prueba'') ->> ''result''',
                                           (select id from reqs where k = 'sin_historia'))), 'rejected', 'se rechaza para seguir');

-- Escalones. La historia queda: 1.000 desde hace 40 días (es el que valía hace 30), 1.120 desde hace 20,
-- 1.000 desde hace 10 (el del caso anterior) y 1.254 desde hace 5. Una suba de 12 % más (1.405).
select pg_temp.price(1000, 40);
select pg_temp.price(1120, 20);
select pg_temp.price(1254, 5);
insert into reqs values ('escalon', pg_temp.propose(1405));
select is(pg_temp.changes((select id from reqs where k = 'escalon'), 'price_variation_today_pct'), '12.04',
  'contra hoy, la suba es de 12 % (no llega al 15 %)');
select is(pg_temp.changes((select id from reqs where k = 'escalon'), 'price_variation_lookback_pct'), '40.50',
  'contra el que valía hace 30 días (1.000), es de 40,5 %');
select is(pg_temp.changes((select id from reqs where k = 'escalon'), 'price_variation_pct'), '40.50',
  'vale la más grande');
select is(pg_temp.q(pg_temp.u(407), format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''',
                                           (select id from reqs where k = 'escalon'))), 'approved', 'el Controller la aprueba');
select ok(pg_temp.goes_to_direction((select id from reqs where k = 'escalon')),
  'y pasa a Dirección: las subas chicas seguidas ya no la esquivan');

-- Los días hacia atrás los configura Dirección, y si no se mandan quedan los que estaban.
select pg_temp.q(pg_temp.u(402), format('select costing.update_price_settings(%L, 15, 30, ''Prueba'', 60)::text', pg_temp.u(1)));
select pg_temp.q(pg_temp.u(402), format('select costing.update_price_settings(%L, 20, 30, ''Prueba'')::text', pg_temp.u(1)));
select is((select approval_variation_pct || '/' || lookback_days from costing.price_settings where group_id = pg_temp.u(1)),
  '20.00/60', 'Dirección cambia los días hacia atrás; sin mandarlos, quedan los que estaban');

select ok(pg_temp.q(pg_temp.u(402), format('select costing.update_price_settings(%L, 20, 30, ''Prueba'', 0)::text', pg_temp.u(1)))
            like 'ERROR %los días de 1 a 365%', 'cero días se rechaza');
select ok(pg_temp.q(pg_temp.u(402), format('select costing.update_price_settings(%L, 20, 30, ''Prueba'', 366)::text', pg_temp.u(1)))
            like 'ERROR %los días de 1 a 365%', 'más de 365 días se rechaza');
select ok(pg_temp.q(pg_temp.u(408), format('select costing.update_price_settings(%L, 50, 30, ''Prueba'', 1)::text', pg_temp.u(1)))
            like 'ERROR %', 'Compras no cambia los días');

-- La función vieja (sin días) ya no existe; la nueva la ejecuta solo quien inició sesión.
select hasnt_function('costing', 'update_price_settings', array['uuid', 'numeric', 'integer', 'text'],
  'no queda la versión anterior de update_price_settings');
select function_privs_are('costing', 'update_price_settings', array['uuid', 'numeric', 'integer', 'text', 'integer'],
  'anon', array[]::text[], 'anon no la ejecuta');
select function_privs_are('costing', 'update_price_settings', array['uuid', 'numeric', 'integer', 'text', 'integer'],
  'authenticated', array['EXECUTE'], 'authenticated la ejecuta (la función pide el permiso)');

-- Con 3 días, hace 3 días valía el mismo precio que hoy (el de hace 5): no hay una segunda comparación.
select pg_temp.q(pg_temp.u(402), format('select costing.update_price_settings(%L, 20, 30, ''Prueba'', 3)::text', pg_temp.u(1)));
select ok(exists (select 1 from audit.audit_events where table_name = 'price_settings' and action::text = 'update'
                   and new_values ->> 'lookback_days' = '3' and old_values ->> 'lookback_days' = '60'),
  'el cambio de los días queda en la auditoría');
-- Dirección rechaza la suba en escalones, que seguía pendiente para el mismo producto y fecha.
select is(pg_temp.q(pg_temp.u(402), format('select workflow.decide_approval(%L, ''rejected'', ''Prueba'') ->> ''result''',
                                           (select r.id from workflow.approval_requests r
                                             where r.proposed_changes ->> 'first_request_id' = (select id from reqs where k = 'escalon')))),
  'rejected', 'Dirección rechaza la suba en escalones');
insert into reqs values ('mismo', pg_temp.propose(1500));
select is(pg_temp.changes((select id from reqs where k = 'mismo'), 'price_variation_lookback_pct'), null,
  'si el de hace N días es el mismo que el de hoy, no se compara dos veces');
select is(pg_temp.changes((select id from reqs where k = 'mismo'), 'price_variation_pct'), '19.62',
  'y vale la de hoy (1.254 → 1.500)');
select pg_temp.q(pg_temp.u(407), format('select workflow.decide_approval(%L, ''rejected'', ''Prueba'') ->> ''result''',
                                        (select id from reqs where k = 'mismo')));

-- Con 12 días, hace 12 valía 1.120. Una bajada a 1.000: contra hoy es -20,26 % y contra hace 12, -10,71 %.
-- Vale la más grande en valor absoluto, también si baja.
select pg_temp.q(pg_temp.u(402), format('select costing.update_price_settings(%L, 20, 30, ''Prueba'', 12)::text', pg_temp.u(1)));
insert into reqs values ('baja', pg_temp.propose(1000));
select is(pg_temp.changes((select id from reqs where k = 'baja'), 'price_variation_lookback_pct'), '-10.71',
  'contra hace 12 días, la bajada es de 10,71 %');
select is(pg_temp.changes((select id from reqs where k = 'baja'), 'price_variation_pct'), '-20.26',
  'cuando la de hoy es más grande, vale la de hoy');

select * from finish();
rollback;
