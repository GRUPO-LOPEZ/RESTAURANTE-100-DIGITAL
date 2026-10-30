-- Fase 2 · Etapa 2.1 B: rendimientos (ADR-0021). Prueba 25 del documento de Soy: un ensayo
-- distinto al estándar no lo cambia sin aprobación. Propone cualquiera con yields.record en el
-- grupo; aprueba otra persona con yields.approve para todo el grupo. El estándar es inmutable y
-- sin él el motor recibe "no definido", nunca 100 %.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(61);

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
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
-- Como dueño de las tablas, pero con una persona en la sesión: el error, si lo hay.
create function pg_temp.as_owner_with(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text := 'sin error';
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  begin
    execute p_sql;
  exception when others then
    v := 'ERROR ' || sqlstate;
  end;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.ing(p_n int) returns uuid language sql as $$ select pg_temp.u(800 + p_n) $$;
create function pg_temp.proc(p_code text) returns uuid language sql as $$
  select id from catalog.yield_processes where code = p_code
$$;
-- Hoy en la Argentina, como controla la base: después de las 21 h, en UTC ya es mañana.
create function pg_temp.today_ar() returns date language sql as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date
$$;
grant execute on function pg_temp.u(int), pg_temp.ing(int), pg_temp.proc(text), pg_temp.today_ar() to authenticated;

-- Propone, como una persona, y devuelve el id de la solicitud (o el error).
create function pg_temp.propose(p_user uuid, p_ingredient int, p_process text, p_cleaning numeric, p_cooking numeric,
                                p_no_loss boolean default false, p_supplier uuid default null)
returns text language sql as $$
  select pg_temp.q(p_user, format(
    'select catalog.propose_yield_standard(pg_temp.ing(%s), pg_temp.proc(%L), null, %s, %s, %L, %L, %L, %L::uuid)::text',
    p_ingredient, p_process, p_cleaning, p_cooking, 'Prueba', p_no_loss, 'Propuesta de prueba', p_supplier))
$$;
create function pg_temp.decide(p_user uuid, p_request text) returns text language sql as $$
  select pg_temp.q(p_user, format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''', p_request))
$$;
create function pg_temp.std(p_ingredient int, p_process text) returns text language sql as $$
  select coalesce(cleaning_yield::text, '-') || '/' || coalesce(cooking_factor::text, '-') || '/' || status
    from catalog.standard_yield(pg_temp.ing(p_ingredient), pg_temp.proc(p_process))
$$;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relname in ('yield_processes', 'ingredient_yield_profiles', 'ingredient_yield_tests')
      and c.relrowsecurity),
  3, 'las tablas de rendimientos tienen RLS');
select ok(exists (select 1 from pg_trigger where tgrelid = 'catalog.ingredient_yield_tests'::regclass and tgname = 'reject_yield_test_change'),
  'los ensayos tienen el trigger de solo inserción');
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'catalog' and table_name in ('yield_processes', 'ingredient_yield_profiles', 'ingredient_yield_tests')
      and grantee in ('anon', 'authenticated', 'service_role') and privilege_type <> 'SELECT'),
  0, 'nadie escribe directo en los rendimientos');
select is(
  (select required_permission || '/' || allow_self_approval::text || '/' || (apply_function::text)
     from workflow.approval_workflows where code = 'catalog.approve_yield_profile'),
  'yields.approve/false/catalog.apply_yield_profile(uuid)', 'la aprobación pide yields.approve y nadie se aprueba lo propio');

-- La función que aplica una aprobación: core, org o catalog, y siempre apply_* (uuid) returns void.
create function public.apply_trampa(uuid) returns void language sql as $$ select $$;
select throws_ok($$insert into workflow.approval_workflows (code, name, required_permission, apply_function)
                   values ('prueba.trampa', 'Trampa', 'yields.approve', 'public.apply_trampa(uuid)'::regprocedure)$$,
  '42501', null, 'una aprobación no aplica funciones de otros esquemas');
select throws_ok($$insert into workflow.approval_workflows (code, name, required_permission, apply_function)
                   values ('prueba.trampa', 'Trampa', 'yields.approve', 'catalog.create_yield_process(uuid, text, text, text)'::regprocedure)$$,
  '42501', null, 'ni funciones de catalog que no son apply_*');

-- ---------------------------------------------------------------------------
-- Datos de prueba y lectura
-- ---------------------------------------------------------------------------
select is(pg_temp.std(1, 'PELADO'), '0.8000/1.0000/approved', 'el tomate pelado rinde 80 % (estándar aprobado, caso 2)');
select is(pg_temp.std(30, 'HERVIDO'), '1.0000/2.5000/approved', 'la pasta hervida se expande ×2,5 (caso 18)');
select is(pg_temp.std(2, 'PELADO'), '-/-/undefined', 'sin estándar: "no definido", nunca 100 %');
select is(pg_temp.q(pg_temp.u(406), $$select count(*)::text from catalog.ingredient_yield_profiles$$), '2',
  'el Jefe de Cocina ve los estándares');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from catalog.ingredient_yield_profiles$$), '0',
  'el Cocinero no ve el catálogo, tampoco los rendimientos');
select is(pg_temp.q(pg_temp.u(406), $$select tests::text || '/' || round(measured_cleaning, 4)::text || '/' || standard_cleaning::text
            from catalog.yield_summary(pg_temp.ing(1))$$),
  '1/0.7700/0.8000', 'la ficha muestra el estándar (80 %) y el promedio de los ensayos (77 %)');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from catalog.yield_summary(pg_temp.ing(1))$$), '0',
  'el resumen no le devuelve nada a quien no ve el catálogo (corre con permisos propios)');

-- ---------------------------------------------------------------------------
-- Ensayos: los registra quien tiene yields.record en ese local
-- ---------------------------------------------------------------------------
select ok(pg_temp.q(pg_temp.u(406), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(201),
            pg_temp.today_ar(), '{"gross_weight": 5000, "clean_weight": 3700}', '{"samples": 2}', 'Ensayo de la semana')::text$$)
          ~ '^[0-9a-f-]{36}$', 'el Jefe de Cocina registra un ensayo en su local');
select is(pg_temp.std(1, 'PELADO'), '0.8000/1.0000/approved', 'prueba 25: un ensayo distinto (74 %) no cambia el estándar');
select is(pg_temp.q(pg_temp.u(406), $$select tests::text from catalog.yield_summary(pg_temp.ing(1))$$), '2',
  'y queda sumado a los ensayos de la ficha');
-- Promedio ponderado por muestras (decisión de Joaco): 77 % con 3 muestras y 74 % con 2 dan
-- (0,77 × 3 + 0,74 × 2) / 5 = 75,8 %, no el 75,5 % del promedio simple.
select is(pg_temp.q(pg_temp.u(406), $$select round(measured_cleaning, 4)::text from catalog.yield_summary(pg_temp.ing(1))$$),
  '0.7580', 'el promedio de los ensayos pesa más los que tienen más muestras');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(203),
            pg_temp.today_ar(), '{"gross_weight": 5000, "clean_weight": 3700}', null, 'Prueba')::text$$),
  'ERROR 42501', 'no registra en otro local');
select is(pg_temp.q(pg_temp.u(409), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(201),
            pg_temp.today_ar(), '{"gross_weight": 5000, "clean_weight": 3700}', null, 'Prueba')::text$$),
  'ERROR 42501', 'el Cocinero no registra ensayos');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(201),
            pg_temp.today_ar(), '{"gross_weight": 5000, "clean_weight": 3700}', null, 'Prueba')::text$$),
  'ERROR 42501', 'Compras tampoco');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(201),
            pg_temp.today_ar(), '{"gross_weight": 5000, "clean_weight": 6000}', null, 'Prueba')::text$$),
  'ERROR 23514', 'el peso limpio no puede ser mayor que el bruto');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(201),
            pg_temp.today_ar(), '{"gross_weight": 5000}', null, 'Prueba')::text$$),
  'ERROR 23514', 'hace falta un par completo de pesos');
select throws_ok($$update catalog.ingredient_yield_tests set clean_weight = 4000$$, '42501', null,
  'un ensayo no se cambia (ni siquiera con permisos de dueño)');
select throws_ok($$delete from catalog.ingredient_yield_tests$$, '42501', null, 'ni se borra');

-- ---------------------------------------------------------------------------
-- Propuesta y aprobación
-- ---------------------------------------------------------------------------
create temporary table req (id text) on commit drop;
grant all on req to authenticated;
insert into req select pg_temp.propose(pg_temp.u(405), 1, 'PELADO', 0.76, 1);
select ok((select id from req) ~ '^[0-9a-f-]{36}$', 'la Chef de marca propone un estándar nuevo para el tomate');
select is(pg_temp.std(1, 'PELADO'), '0.8000/1.0000/approved', 'mientras está pendiente, el motor sigue usando el aprobado');
select is(pg_temp.q(pg_temp.u(406), $$select pending_proposals::text from catalog.yield_summary(pg_temp.ing(1))$$), '1',
  'la ficha muestra que hay una propuesta en revisión');
select is(pg_temp.decide(pg_temp.u(405), (select id from req)), 'denied', 'quien la propuso no la aprueba');
select is(pg_temp.decide(pg_temp.u(403), (select id from req)), 'denied',
  'la Directora de Marca tampoco: el estándar es de todo el grupo y su permiso es de una marca');
select is(pg_temp.decide(pg_temp.u(402), (select id from req)), 'denied', 'Dirección tampoco: no tiene yields.approve');
select is(pg_temp.decide(pg_temp.u(413), (select id from req)), 'approved', 'el Chef del grupo la aprueba');
select is(pg_temp.std(1, 'PELADO'), '0.7600/1.0000/approved', 'el motor ya usa el estándar nuevo');
select is(
  (select string_agg(status::text || ':' || cleaning_yield::text, ',' order by created_at)
     from catalog.ingredient_yield_profiles where ingredient_id = pg_temp.ing(1)),
  'superseded:0.8000,approved:0.7600', 'el anterior queda reemplazado, con su valor intacto');
select is(
  (select (approved_by = pg_temp.u(413))::text from catalog.ingredient_yield_profiles
    where ingredient_id = pg_temp.ing(1) and status = 'approved'),
  'true', 'queda quién lo aprobó');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_yield_profiles'
                    and action = 'update' and new_values ->> 'status' = 'approved'),
  'la aprobación queda en la auditoría');

select ok(pg_temp.propose(pg_temp.u(406), 3, 'PELADO', 0.9, 1) ~ '^[0-9a-f-]{36}$',
  'el Jefe de Cocina también puede proponer (tiene yields.record en su local)');
select is(pg_temp.propose(pg_temp.u(409), 4, 'PELADO', 0.9, 1), 'ERROR 42501', 'el Cocinero no propone');
select is(pg_temp.msg(pg_temp.u(405), $$select catalog.propose_yield_standard(pg_temp.ing(5), pg_temp.proc('PELADO'),
            null, 1, 1, null, false, 'Prueba')$$),
  'Un rendimiento de 100 % sin merma se tiene que declarar "sin merma".',
  '100 % sin merma solo si se declara "sin merma"');
select ok(pg_temp.propose(pg_temp.u(405), 5, 'PELADO', 1, 1, true) ~ '^[0-9a-f-]{36}$',
  'declarado "sin merma", se puede proponer (y pasa por aprobación)');

-- El estándar del proveedor manda sobre el general.
select ok(pg_temp.propose(pg_temp.u(405), 1, 'PELADO', 0.85, 1, false, pg_temp.u(901)) ~ '^[0-9a-f-]{36}$',
  'se propone un estándar propio de un proveedor');
select is(pg_temp.decide(pg_temp.u(413),
            (select r.id::text from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'catalog.approve_yield_profile' and r.status = 'pending'
                and r.proposed_changes ->> 'cleaning_yield' = '0.85')),
  'approved', 'y se aprueba');
select is((select cleaning_yield::text from catalog.standard_yield(pg_temp.ing(1), pg_temp.proc('PELADO'), null, pg_temp.u(901))),
  '0.8500', 'con ese proveedor, el motor usa su estándar');
select is((select cleaning_yield::text from catalog.standard_yield(pg_temp.ing(1), pg_temp.proc('PELADO'), null, pg_temp.u(902))),
  '0.7600', 'con otro proveedor, el general');

-- Inmutable.
select throws_ok($$update catalog.ingredient_yield_profiles set cleaning_yield = 0.5 where status = 'approved'$$, '42501', null,
  'un estándar no se edita, ni siquiera con permisos de dueño');
select throws_ok($$update catalog.ingredient_yield_profiles set status = 'approved' where status = 'superseded'$$, '42501', null,
  'un estándar reemplazado no vuelve a estar vigente');
select throws_ok($$update catalog.ingredient_yield_profiles set status = 'superseded'
                    where status = 'draft'$$, '42501', null, 'una propuesta no pasa directo a reemplazada');
select throws_ok($$update catalog.ingredient_yield_profiles set approved_by = '00000000-0000-4000-8000-000000000402'
                    where status = 'approved'$$, '42501', null, 'quién aprobó no cambia');
select throws_ok($$update catalog.ingredient_yield_profiles set deleted_at = now() where status = 'approved'$$, '42501', null,
  'un estándar no se borra');
-- Con una persona en la sesión, nada nace aprobado (ni siquiera con permisos de dueño).
select is(pg_temp.as_owner_with(pg_temp.u(413), $$insert into catalog.ingredient_yield_profiles
            (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, status, approved_by, approved_at)
            values (pg_temp.u(1), pg_temp.ing(6), pg_temp.proc('PELADO'), 0.9, 1, 'approved', pg_temp.u(413), now())$$),
  'ERROR 42501', 'un estándar nace como propuesta: con una persona en la sesión no se inserta aprobado');

-- Una sola propuesta pendiente por clave: nadie aprueba sobre un "antes" que ya cambió.
create temporary table req2 (id text) on commit drop;
insert into req2 select pg_temp.propose(pg_temp.u(405), 7, 'PELADO', 0.7, 1);
select is(pg_temp.msg(pg_temp.u(406), $$select catalog.propose_yield_standard(pg_temp.ing(7), pg_temp.proc('PELADO'),
            null, 0.75, 1, null, false, 'Otra')$$),
  'Ya hay una propuesta pendiente para ese proceso: esperá a que se decida o pedí que la retiren.',
  'no se puede proponer otra mientras hay una pendiente para lo mismo');
-- Si el estándar cambia por otro camino antes de aprobar, la aprobación no se aplica.
do $$
begin
  perform core.set_change_context('Prueba: el estándar cambió', 'maintenance');
  insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, status,
                                                 approved_by, approved_at)
  values (pg_temp.u(1), pg_temp.ing(7), pg_temp.proc('PELADO'), 0.72, 1, 'approved', pg_temp.u(413), now());
end
$$;
select is(pg_temp.decide(pg_temp.u(413), (select id from req2)), 'ERROR 23514',
  'si el estándar cambió desde que se propuso, la aprobación no se aplica');
select is(pg_temp.std(7, 'PELADO'), '0.7200/1.0000/approved', 'y el estándar vigente queda como estaba');

-- Una propuesta rechazada no deja rastro en la ficha ni en el estándar.
create temporary table req3 (id text) on commit drop;
insert into req3 select pg_temp.propose(pg_temp.u(405), 10, 'LIMPIEZA', 0.88, 1);
select is(pg_temp.q(pg_temp.u(413), format($$select workflow.decide_approval(%L, 'rejected', 'No coincide') ->> 'result'$$,
            (select id from req3))), 'rejected', 'el Chef del grupo rechaza una propuesta');
select is(pg_temp.q(pg_temp.u(406), $$select count(*)::text from catalog.yield_summary(pg_temp.ing(10))$$), '0',
  'la propuesta rechazada no aparece en la ficha');
select is(pg_temp.std(10, 'LIMPIEZA'), '-/-/undefined', 'y no hay estándar');

-- Auditoría de ensayos y procesos; quién crea procesos.
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_yield_tests'
                    and action = 'insert' and actor_user_id = pg_temp.u(406) and reason = 'Ensayo de la semana'),
  'el registro de un ensayo queda en la auditoría, con quién y por qué');
select ok(pg_temp.q(pg_temp.u(413), $$select catalog.create_yield_process(pg_temp.u(1), 'blanqueado', 'Blanqueado', 'Proceso nuevo')::text$$)
          ~ '^[0-9a-f-]{36}$', 'el Chef del grupo crea un proceso');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'yield_processes'
                    and action = 'insert' and new_values ->> 'code' = 'BLANQUEADO'),
  'y queda en la auditoría');
select is(pg_temp.q(pg_temp.u(405), $$select catalog.create_yield_process(pg_temp.u(1), 'BRASEADO', 'Braseado', 'Prueba')::text$$),
  'ERROR 42501', 'la Chef de marca no crea procesos (es de todo el grupo)');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.record_yield_test(pg_temp.ing(1), pg_temp.proc('PELADO'), pg_temp.u(201),
            pg_temp.today_ar() + 10, '{"gross_weight": 5000, "clean_weight": 3700}', null, 'Prueba')::text$$),
  'ERROR 22023', 'un ensayo no tiene fecha futura');
select ok(not exists (select 1 from pg_policies where (coalesce(qual, '') || coalesce(with_check, '')) like '%has_permission_in_group_any_scope%'),
  'ninguna política usa has_permission_in_group_any_scope (solo sirve para proponer)');

select * from finish();
rollback;
