-- Fase 2, agregados chicos: aviso de rendimiento (ADR-0035). Un ensayo que se desvía del estándar más que el umbral avisa a
-- quien tiene yields.alerts en ese local (el Chef y el Controller), menos a quien lo cargó. Cada caso usa una fecha distinta,
-- que va en el texto del aviso: así se sabe qué aviso es de qué ensayo. Los números están hechos a mano.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(40);

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
-- Registra un ensayo como esa persona. 801 = materia prima con estándar de Pelado (961): limpieza 80 %.
-- 830 = materia prima con estándar de Hervido (965): factor de cocción 2,5.
create function pg_temp.test(p_user int, p_ingredient int, p_process int, p_rest int, p_on date, p_measures jsonb,
                             p_details jsonb default '{}')
returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select catalog.record_yield_test(%L, %L, %L, %L, %L, %L, ''Prueba: ensayo'')::text',
    pg_temp.u(p_ingredient), pg_temp.u(p_process), pg_temp.u(p_rest), p_on, p_measures, p_details))
$$;
-- Un estándar aprobado más, cargado directo para la prueba (con corte o con proveedor).
create function pg_temp.standard(p_cut text, p_supplier int, p_cleaning numeric) returns void language plpgsql as $$
begin
  perform core.set_change_context('Prueba: estándar', 'maintenance');
  insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cut, supplier_id, cleaning_yield, cooking_factor,
                                                 status, approved_by, approved_at)
  values (pg_temp.u(1), pg_temp.u(801), pg_temp.u(961), p_cut, case when p_supplier is null then null else pg_temp.u(p_supplier) end,
          p_cleaning, 1, 'approved', pg_temp.u(413), now());
end
$$;
-- A quién le llegó el aviso del ensayo de esa fecha: los tres últimos números del id, en orden.
create function pg_temp.who(p_on date) returns text language sql as $$
  select coalesce(string_agg(right(recipient_user_id::text, 3), ',' order by recipient_user_id), 'nadie')
    from core.notifications
   where kind = 'yield_deviation' and deleted_at is null and body like '%' || to_char(p_on, 'DD/MM/YYYY') || '%'
$$;
create function pg_temp.body(p_on date) returns text language sql as $$
  select body from core.notifications
   where kind = 'yield_deviation' and body like '%' || to_char(p_on, 'DD/MM/YYYY') || '%' limit 1
$$;

-- El permiso: el Chef y el Controller, y quienes dan y aprueban esos roles (Director de marca y Dirección General).
select is((select string_agg(r.code, ',' order by r.code) from core.role_permissions rp
             join core.roles r on r.id = rp.role_id join core.permissions p on p.id = rp.permission_id
            where p.code = 'yields.alerts' and rp.deleted_at is null),
  'brand_director,controller,executive_chef,general_management', 'yields.alerts lo tienen el Chef, el Controller, el Director y Dirección');

-- 1. Limpieza de 68 % contra 80 %: 0,68 / 0,80 = 0,85, un desvío de −15 %. Lo carga el Jefe de Cocina en Centro.
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-01', '{"gross_weight": 1000, "clean_weight": 680}') ~ '^[0-9a-f-]{36}$',
  'el Jefe de Cocina registra un ensayo desviado');
-- 402 y 412 Dirección, 403 Directora de la marca, 405 Chef de la marca, 407 Controller, 413 Chef del grupo.
-- Nadie más: ni el Gerente, ni Compras, ni la Cocinera, ni el Auditor, ni el Superadministrador.
select is(pg_temp.who('2026-01-01'), '402,403,405,407,412,413', 'avisa al Chef, al Controller, a la Directora y a Dirección');
select is(pg_temp.body('2026-01-01'),
  'Limpieza: 68 % contra 80 % del estándar (15 % menos). En Demo Pastas Centro, el 01/01/2026. Avisa con un desvío de más de 10 %.',
  'el aviso dice cuánto midió, contra qué y el umbral');
select is((select title from core.notifications where kind = 'yield_deviation' and body like '%01/01/2026%' limit 1),
  'Rendimiento desviado: ' || (select name from catalog.ingredients where id = pg_temp.u(801)), 'el título nombra la materia prima');
select is((select link from core.notifications where kind = 'yield_deviation' and body like '%01/01/2026%' limit 1),
  '/materias-primas/' || pg_temp.u(801), 'y lleva a su ficha');
select is(pg_temp.q(pg_temp.u(405), $$select count(*)::text from core.notifications where kind = 'yield_deviation'$$), '1',
  'la Chef ve su aviso');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from core.notifications where kind = 'yield_deviation'$$), '0',
  'la Cocinera no ve ninguno');

-- 2. Limpieza de 76 %: 0,76 / 0,80 = 0,95, −5 %. Dentro del umbral: no avisa.
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-02', '{"gross_weight": 1000, "clean_weight": 760}') ~ '^[0-9a-f-]{36}$',
  'un ensayo dentro del umbral se registra');
select is(pg_temp.who('2026-01-02'), 'nadie', 'y no avisa');

-- 3. Justo en el umbral: 720 / 1000 = 0,72 = 0,80 × 0,90, −10 %. "Más que el umbral" no incluye el umbral.
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-03', '{"gross_weight": 1000, "clean_weight": 720}') ~ '^[0-9a-f-]{36}$',
  'un ensayo justo en el umbral se registra');
select is(pg_temp.who('2026-01-03'), 'nadie', 'y no avisa');

-- 4. Sin estándar: la misma materia prima con Limpieza (962), que no tiene uno aprobado.
select ok(pg_temp.test(406, 801, 962, 201, '2026-01-04', '{"gross_weight": 1000, "clean_weight": 300}') ~ '^[0-9a-f-]{36}$',
  'un ensayo sin estándar se registra');
select is(pg_temp.who('2026-01-04'), 'nadie', 'y no avisa: no hay contra qué comparar');

-- 5. Cocción: 100 g crudos dan 300 g, factor 3 contra 2,5 = 1,2, +20 %.
select ok(pg_temp.test(406, 830, 965, 201, '2026-01-05', '{"before_cooking_weight": 100, "after_cooking_weight": 300}') ~ '^[0-9a-f-]{36}$',
  'un ensayo de cocción desviado se registra');
select is(pg_temp.body('2026-01-05'),
  'Cocción: rinde ×3 contra ×2,5 del estándar (20 % más). En Demo Pastas Centro, el 05/01/2026. Avisa con un desvío de más de 10 %.',
  'avisa también por la cocción');

-- 6. Quien lo carga no se avisa a sí mismo: la Chef registra el mismo desvío de −15 %.
select ok(pg_temp.test(405, 801, 961, 201, '2026-01-06', '{"gross_weight": 1000, "clean_weight": 680}') ~ '^[0-9a-f-]{36}$',
  'la Chef registra un ensayo desviado');
select is(pg_temp.who('2026-01-06'), '402,403,407,412,413', 'avisa a los demás, no a ella');

-- 7. En un local de otra marca (Parrilla, 203): la Chef de la marca de pastas no se entera.
select ok(pg_temp.test(401, 801, 961, 203, '2026-01-07', '{"gross_weight": 1000, "clean_weight": 680}') ~ '^[0-9a-f-]{36}$',
  'un ensayo desviado en la Parrilla se registra');
select is(pg_temp.who('2026-01-07'), '402,407,412,413', 'avisa al grupo, no a la Chef ni a la Directora de otra marca');

-- 9. El corte: un ensayo "en cubos" no se compara con el estándar sin corte; con uno "En cubos" de 50 %, sí (sin
-- importar mayúsculas). 0,68 / 0,50 = 1,36: 36 % más.
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-09', '{"gross_weight": 1000, "clean_weight": 680}', '{"cut": "en cubos"}') ~ '^[0-9a-f-]{36}$'
          and pg_temp.who('2026-01-09') = 'nadie', 'un corte sin estándar propio no avisa');
select pg_temp.standard('En cubos', null, 0.5);
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-10', '{"gross_weight": 1000, "clean_weight": 680}', '{"cut": "EN CUBOS"}') ~ '^[0-9a-f-]{36}$',
  'un ensayo "EN CUBOS" se registra');
select ok(pg_temp.body('2026-01-10') like 'Limpieza: 68 % contra 50 % del estándar (36 % más).%', 'y se compara con el estándar "En cubos"');
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-11', '{"gross_weight": 1000, "clean_weight": 680}', '{"cut": "en tiras"}') ~ '^[0-9a-f-]{36}$'
          and pg_temp.who('2026-01-11') = 'nadie', 'otro corte no avisa');

-- 10. El proveedor: sin estándar propio, se compara con el general, como el costo (decisión de Joaco, 2026-11-09).
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-12', '{"gross_weight": 1000, "clean_weight": 680}',
                       format('{"supplier_id": "%s"}', pg_temp.u(901))::jsonb) ~ '^[0-9a-f-]{36}$',
  'un ensayo de la Verdulería se registra');
select ok(pg_temp.body('2026-01-12') like 'Limpieza: 68 % contra 80 % del estándar (15 % menos).%', 'sin estándar propio, se compara con el general');
-- Con un estándar propio de 70 %, ese manda: 0,68 / 0,70 es menos de 3 %, no avisa.
select pg_temp.standard(null, 901, 0.7);
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-13', '{"gross_weight": 1000, "clean_weight": 680}',
                       format('{"supplier_id": "%s"}', pg_temp.u(901))::jsonb) ~ '^[0-9a-f-]{36}$'
          and pg_temp.who('2026-01-13') = 'nadie', 'con estándar propio del proveedor, se compara con ese');
-- Un ensayo sin proveedor sigue yendo contra el general.
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-14', '{"gross_weight": 1000, "clean_weight": 680}') ~ '^[0-9a-f-]{36}$'
          and pg_temp.who('2026-01-14') <> 'nadie', 'sin proveedor, sigue el estándar general');

-- 8. El umbral: lo cambia solo quien tiene prices.configure.
select ok(pg_temp.q(pg_temp.u(405), format($$select costing.update_price_settings(%L, 15, 30, 'Prueba', null, 20)::text$$, pg_temp.u(1)))
  like 'ERROR%No tenés permiso%', 'la Chef no cambia el umbral');
select ok(pg_temp.q(pg_temp.u(402), format($$select costing.update_price_settings(%L, 15, 30, 'Prueba', null, 150)::text$$, pg_temp.u(1)))
  like 'ERROR%de más de 0 a 100%', 'un umbral fuera de rango se rechaza');
select is(pg_temp.q(pg_temp.u(402), format($$select costing.update_price_settings(%L, 15, 30, 'Prueba: inflación del mes', null, 20)::text$$, pg_temp.u(1))),
  '', 'Dirección lo pone en 20 %');
select is((select new_values ->> 'yield_alert_pct' from audit.audit_events
            where table_name = 'price_settings' and reason = 'Prueba: inflación del mes' order by sequence_number desc limit 1),
  '20.00', 'el cambio queda en la auditoría, con su motivo');
select is(pg_temp.q(pg_temp.u(405), format('select catalog.yield_alert_threshold(%L)::text', pg_temp.u(801))), '20.00',
  'la ficha de la Chef lee el umbral nuevo');
-- Con 20 %, el mismo desvío de −15 % ya no avisa.
select ok(pg_temp.test(406, 801, 961, 201, '2026-01-08', '{"gross_weight": 1000, "clean_weight": 680}') ~ '^[0-9a-f-]{36}$'
          and pg_temp.who('2026-01-08') = 'nadie', 'con 20 %, el mismo ensayo ya no avisa');

-- Cambiar solo el umbral no toca el resto de la configuración (así no pisa lo que guardó otra persona).
select is(pg_temp.q(pg_temp.u(402), format($$select costing.update_price_settings(%L, 25, 40, 'Prueba: precios', 45)::text$$, pg_temp.u(1))),
  '', 'Dirección cambia la configuración de precios');
select is(pg_temp.q(pg_temp.u(412), format($$select costing.update_yield_alert(%L, 7.5, 'Prueba: solo el umbral')::text$$, pg_temp.u(1))),
  '', 'otra persona de Dirección cambia solo el umbral');
select is((select concat_ws('/', approval_variation_pct, stale_days, lookback_days, yield_alert_pct) from costing.price_settings
            where group_id = pg_temp.u(1) and deleted_at is null),
  '25.00/40/45/7.50', 'el porcentaje y los días quedan como estaban');
select hasnt_function('costing', 'update_price_settings', array['uuid', 'numeric', 'integer', 'text', 'integer'],
  'no queda la versión anterior de update_price_settings');
select ok(pg_temp.q(pg_temp.u(405), format($$select costing.update_yield_alert(%L, 5, 'Prueba')::text$$, pg_temp.u(1))) like 'ERROR%No tenés permiso%',
  'la Chef tampoco cambia el umbral por la función propia');
select hasnt_function('costing', 'update_price_settings', array['uuid', 'numeric', 'integer', 'text'],
  'ni la primera');

select * from finish();
rollback;
