-- Fase 1 · M8 + M9: desactivar y reactivar cuentas, bloqueo por intentos fallidos, hook de Auth,
-- invitación, lecturas de las pantallas y rendimiento del tablero de usuarios.
-- Pruebas que cubre: 8 (base), A5 (base), A7 (base) y A10. Personas del seed: ver 050_permissions.
begin;
create extension if not exists pgtap with schema extensions;

select plan(62);

create function pg_temp.q(p_user uuid, p_sql text, p_aal text default 'aal2')
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
    case when p_user is null then '{"role": "anon"}'
         else json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text end, true);
  execute case when p_user is null then 'set local role anon' else 'set local role authenticated' end;
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
create function pg_temp.r(p_user uuid, p_call text, p_aal text default 'aal2')
returns text
language sql
as $$ select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call), p_aal) $$;
create function pg_temp.hook(p_user uuid, p_method text default 'password') returns jsonb language sql as $$
  select core.custom_access_token_hook(jsonb_build_object(
    'user_id', p_user, 'authentication_method', p_method, 'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')))
$$;

-- ---------------------------------------------------------------------------
-- Quién ejecuta qué (ADR-0005): la clave de servidor y Auth tienen lo mínimo
-- ---------------------------------------------------------------------------
select is(
  (select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname collate "C")
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('core', 'org', 'audit', 'workflow') and has_function_privilege('service_role', p.oid, 'execute')),
  array['core.login_status', 'core.record_failed_login'],
  'la clave de servidor solo consulta el bloqueo y anota los fallos de ingreso'
);
select ok(has_function_privilege('supabase_auth_admin', 'core.custom_access_token_hook(jsonb)', 'execute')
          and not has_function_privilege('authenticated', 'core.custom_access_token_hook(jsonb)', 'execute')
          and not has_function_privilege('anon', 'core.custom_access_token_hook(jsonb)', 'execute'),
  'el hook de ingreso solo lo ejecuta Supabase Auth');
select is(pg_temp.q(pg_temp.u(404), $$select core.record_failed_login('gerente@ejemplo.test')::text$$), 'ERROR 42501',
  'una sesión común no puede anotar fallos de ingreso (si pudiera, bloquearía cuentas ajenas)');

-- ---------------------------------------------------------------------------
-- Mi sesión (para la interfaz)
-- ---------------------------------------------------------------------------
select ok(
  (select (s ->> 'requires_mfa')::boolean and not (s ->> 'can_operate')::boolean
     from (select pg_temp.q(pg_temp.u(404), 'select core.my_session()::text', 'aal1')::jsonb as s) t),
  'my_session: al gerente sin doble verificación le falta el segundo paso'
);
select ok(
  (select (s ->> 'can_operate')::boolean and not (s ->> 'requires_mfa')::boolean
     from (select pg_temp.q(pg_temp.u(409), 'select core.my_session()::text', 'aal1')::jsonb as s) t),
  'my_session: el cocinero opera con contraseña sola'
);

-- ---------------------------------------------------------------------------
-- Prueba 8: una cuenta desactivada pierde el acceso
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(404), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(404))), 'denied', 'nadie se desactiva a sí mismo');
select is(pg_temp.r(pg_temp.u(404), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(403))), 'denied', 'el gerente no desactiva a su director');
select is(pg_temp.r(pg_temp.u(401), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(402))), 'pending_approval',
  'el superadmin no desactiva a Dirección General por su cuenta: queda pendiente de otra persona de Dirección (ADR-0017, pregunta 3)');
select is(pg_temp.r(pg_temp.u(409), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(406))), 'denied', 'el cocinero no desactiva cuentas');

insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (gen_random_uuid(), pg_temp.u(409), now(), now(), 'aal1');
select is(pg_temp.r(pg_temp.u(404), format('core.disable_user(%L, ''Dejó de trabajar en el local'')', pg_temp.u(409))), 'applied',
  '8. el gerente desactiva al cocinero de su local');
select ok((select status = 'deactivated' and deactivated_by = pg_temp.u(404) and deactivation_reason = 'Dejó de trabajar en el local'
             from core.user_profiles where id = pg_temp.u(409)), '8. queda desactivada, con quién y por qué');
select is((select count(*)::int from auth.sessions where user_id = pg_temp.u(409)), 0, '8. se cerraron todas sus sesiones');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.restaurants', 'aal1'), '0', '8. con un token que siga vigente, ya no ve nada');
select ok(pg_temp.hook(pg_temp.u(409)) ? 'error', '8. Supabase Auth no le da un token nuevo al ingresar');
select ok(pg_temp.hook(pg_temp.u(409), 'token_refresh') ? 'error', '8. ni al renovar la sesión');
select ok(exists (select 1 from audit.authentication_security_events where event_type = 'account_disabled' and user_id = pg_temp.u(409)),
  '8. la baja quedó en el registro de seguridad');
select ok(exists (select 1 from core.user_role_assignments where user_id = pg_temp.u(409) and deleted_at is null),
  'desactivar no borra su historia ni sus roles');

-- ---------------------------------------------------------------------------
-- A5: reactivar pide la aprobación de otra persona, distinta de quien bloqueó
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(404), format('core.request_reactivation(%L, ''Vuelve al local'')', pg_temp.u(409))), 'pending_approval',
  'A5. el gerente pide reactivarla: queda pendiente');
select ok((select restaurant_id = pg_temp.u(201) from workflow.approval_requests where subject_user_id = pg_temp.u(409) and status = 'pending'),
  'A5. la solicitud queda en el local de la persona (la puede aprobar quien administra ese local)');
select is(pg_temp.r(pg_temp.u(404), format('workflow.decide_approval(%L, ''approved'', null)',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(409) and status = 'pending'))),
  'denied', 'A5. quien la bloqueó (y pidió) no la aprueba');
select is(pg_temp.q(pg_temp.u(411), format('select can_decide::text from workflow.inbox() where id = %L',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(409) and status = 'pending'))),
  'true', 'la bandeja le muestra a la otra gerente que puede decidirla');
select is(pg_temp.r(pg_temp.u(411), format('workflow.decide_approval(%L, ''approved'', ''Confirmado'')',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(409) and status = 'pending'))),
  'approved', 'A5. la otra gerente del local la aprueba');
select ok((select status = 'active' and deactivated_at is null from core.user_profiles where id = pg_temp.u(409)), 'A5. la cuenta vuelve a estar activa');
select ok(pg_temp.hook(pg_temp.u(409)) ? 'claims', 'A5. reactivada, vuelve a recibir su token');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.restaurants', 'aal1'), '1', 'A5. y vuelve a ver su local');

-- ---------------------------------------------------------------------------
-- A7: 5 fallos seguidos en 10 minutos bloquean 10 minutos (P18)
-- ---------------------------------------------------------------------------
select is((select string_agg((core.record_failed_login('compras@ejemplo.test', '10.0.0.1', 'prueba') ->> 'locked'), ',')
             from generate_series(1, 5)),
  'false,false,false,false,true', 'A7. al quinto fallo seguido la cuenta se bloquea');
select ok((select locked_until between now() + interval '9 minutes' and now() + interval '11 minutes'
             from core.user_profiles where id = pg_temp.u(408)), 'A7. el bloqueo dura 10 minutos');
select is((select count(*)::int from audit.authentication_security_events where event_type = 'login_failed' and user_id = pg_temp.u(408)), 5,
  'A7. cada fallo quedó registrado');
select is((select count(*)::int from audit.authentication_security_events where event_type = 'account_locked' and user_id = pg_temp.u(408)), 1,
  'A7. el bloqueo quedó registrado');
select ok((core.login_status('Compras@Ejemplo.test') ->> 'locked')::boolean, 'A7. la función de ingreso ve el bloqueo (sin importar mayúsculas)');
select ok(pg_temp.hook(pg_temp.u(408)) ? 'error', 'A7. bloqueada, no recibe token aunque la contraseña sea correcta');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from org.restaurants', 'aal1'), '0', 'A7. bloqueada, no ve nada');
select is((select string_agg((core.record_failed_login('nadie@ejemplo.test') ->> 'locked'), ',') from generate_series(1, 5)),
  'false,false,false,false,true', 'un correo que no existe se bloquea igual: el bloqueo no revela qué correos existen');
select ok(exists (select 1 from audit.authentication_security_events where event_type = 'login_failed' and email = 'nadie@ejemplo.test' and user_id is null),
  'el intento con un correo que no existe queda registrado');
select is(
  (select (core.record_failed_login('compras@ejemplo.test') ->> 'locked_until')::timestamptz = (select locked_until from core.login_throttles where email = 'compras@ejemplo.test')
          and (select locked_until from core.login_throttles where email = 'compras@ejemplo.test') <= now() + interval '10 minutes'),
  true, 'P18. un fallo durante el bloqueo no lo extiende');

select is(pg_temp.r(pg_temp.u(404), format('core.unlock_user(%L, ''Prueba'')', pg_temp.u(408))), 'denied',
  'el gerente no libera a alguien fuera de su alcance');
select is(pg_temp.r(pg_temp.u(401), format('core.unlock_user(%L, ''Se olvidó la contraseña y ya la recuperó'')', pg_temp.u(408))), 'applied',
  'P18. un administrador lo libera antes de tiempo');
select ok(not (core.login_status('compras@ejemplo.test') ->> 'locked')::boolean
          and exists (select 1 from audit.authentication_security_events where event_type = 'account_unlocked' and user_id = pg_temp.u(408)),
  'P18. queda liberada, y la liberación queda registrada');

insert into core.login_throttles (email, failed_count, window_started_at, last_failed_at)
values ('auditor@ejemplo.test', 4, now() - interval '11 minutes', now() - interval '1 minute');
select is(core.record_failed_login('auditor@ejemplo.test') ->> 'locked', 'false', 'P18. la ventana cuenta desde el PRIMER fallo: pasados 10 minutos, empieza de nuevo');
insert into core.login_throttles (email, failed_count, window_started_at, last_failed_at)
values ('controller@ejemplo.test', 4, now() - interval '9 minutes', now() - interval '1 minute');
select is(core.record_failed_login('controller@ejemplo.test') ->> 'locked', 'true', 'P18. 5 fallos dentro de 10 minutos desde el primero bloquean');
insert into core.login_throttles (email, failed_count, window_started_at, last_failed_at)
values ('jefecocina@ejemplo.test', 3, now(), now());
select ok(pg_temp.hook(pg_temp.u(406)) ? 'claims', 'un ingreso bueno recibe su token');
select ok(not exists (select 1 from core.login_throttles where email = 'jefecocina@ejemplo.test')
          and exists (select 1 from audit.authentication_security_events where event_type = 'login_succeeded' and user_id = pg_temp.u(406)),
  'un ingreso bueno pone el contador en cero y queda registrado');

-- Revisión de M8: el tablero solo muestra los roles que la sesión puede ver.
select is(pg_temp.q(pg_temp.u(404), format('select jsonb_array_length(roles)::text from core.users_dashboard(p_user_id => %L)', pg_temp.u(411))),
  '1', 'el gerente ve solo el rol de su local de la gerente de dos locales (el otro local no es suyo)');

-- Revisión de M8: reactivar. Quien bloqueó no aprueba, quien tiene menos permisos que la persona
-- tampoco, y si quien pidió pierde el permiso, la aprobación no se aplica.
select is(pg_temp.r(pg_temp.u(403), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(504))), 'applied', 'el director desactiva a una persona');
select is(pg_temp.r(pg_temp.u(404), format('core.request_reactivation(%L, ''Vuelve'')', pg_temp.u(504))), 'pending_approval', 'el gerente pide reactivarla');
select is(pg_temp.r(pg_temp.u(403), format('workflow.decide_approval(%L, ''approved'', null)',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(504) and status = 'pending'))),
  'denied', 'quien bloqueó la cuenta no aprueba la reactivación');
update core.user_role_assignments set deleted_at = now() where user_id = pg_temp.u(404);
select is(pg_temp.q(pg_temp.u(411), format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(504) and status = 'pending'))),
  'ERROR 23514', 'si quien pidió ya no tiene permiso, la reactivación no se aplica');
select ok((select status = 'deactivated' from core.user_profiles where id = pg_temp.u(504)), 'la cuenta sigue desactivada');
update core.user_role_assignments set deleted_at = null where user_id = pg_temp.u(404);

insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
select pg_temp.u(503), r.id, 'restaurant', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201) from core.roles r where r.code = 'auditor';
select is(pg_temp.r(pg_temp.u(401), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(503))), 'applied', 'el superadmin desactiva a alguien con un rol de auditoría');
select is(pg_temp.r(pg_temp.u(401), format('core.request_reactivation(%L, ''Vuelve'')', pg_temp.u(503))), 'pending_approval', 'el superadmin pide reactivarla');
select is(pg_temp.r(pg_temp.u(411), format('workflow.decide_approval(%L, ''approved'', null)',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(503) and status = 'pending'))),
  'denied', 'un gerente con menos permisos que la persona no aprueba su reactivación');
select is(pg_temp.q(pg_temp.u(411), format('select can_decide::text from workflow.inbox() where id = %L',
            (select id from workflow.approval_requests where subject_user_id = pg_temp.u(503) and status = 'pending'))),
  'false', 'y la bandeja no le ofrece aprobarla');

-- ---------------------------------------------------------------------------
-- Invitación: los pasos de la base
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(404), format('core.can_invite(''restaurant'', %L, %L, %L)', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201))),
  'allowed', 'el gerente puede invitar a su local');
select is(pg_temp.r(pg_temp.u(404), format('core.can_invite(''restaurant'', %L, %L, %L)', pg_temp.u(1), pg_temp.u(102), pg_temp.u(203))),
  'denied', 'el gerente no puede invitar a otro local (y queda registrado)');
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role) values
  ('55555555-5555-5555-5555-555555555555', 'invitada@ejemplo.test', '{}', '{"first_name": "Invitada", "last_name": "Nueva"}', 'authenticated', 'authenticated');
-- Como en la invitación: al grupo y al local donde va a trabajar (sin lugar, pide invitar en todo el grupo).
select is(pg_temp.r(pg_temp.u(404), format('core.add_member(%L, %L, ''Invitación'', %L, %L)', '55555555-5555-5555-5555-555555555555', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201))),
  'applied', 'quien puede invitar suma a la persona al grupo, en su local');
select is(pg_temp.r(pg_temp.u(409), format('core.add_member(%L, %L, ''Invitación'')', '55555555-5555-5555-5555-555555555555', pg_temp.u(1))),
  'denied', 'el cocinero no suma personas');

-- ---------------------------------------------------------------------------
-- Historial y tarea programada
-- ---------------------------------------------------------------------------
select ok(pg_temp.q(pg_temp.u(402), 'select count(*)::text from core.audit_history(50)')::int > 0, 'Dirección General lee el historial');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from core.audit_history(50)', 'aal1'), '0', 'el cocinero no lee el historial');
select is(core.hide_costs('{"name": "Ñoquis", "food_cost": 12.5, "lines": [{"unit_price": 3}]}'::jsonb),
  '{"name": "Ñoquis", "food_cost": "[oculto]", "lines": [{"unit_price": "[oculto]"}]}'::jsonb,
  'sin recipes.view_costs, el historial oculta costos y precios');
select is((select count(*)::int from cron.job where jobname = 'grupo-lf-sellar-auditoria' and schedule = '7 * * * *'), 1,
  'la auditoría y el registro de seguridad se sellan cada hora');

-- ---------------------------------------------------------------------------
-- A10: el tablero de usuarios responde en menos de 300 ms con 500 personas
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
select gen_random_uuid(), format('carga-%s@ejemplo.test', g), '{}', jsonb_build_object('first_name', 'Carga', 'last_name', g::text),
       'authenticated', 'authenticated'
  from generate_series(1, 500) as g;
insert into core.user_memberships (user_id, group_id)
select id, pg_temp.u(1) from core.user_profiles where email like 'carga-%@ejemplo.test';
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
select p.id, (select id from core.roles where code = 'cook'), 'restaurant', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201)
  from core.user_profiles p where p.email like 'carga-%@ejemplo.test';
analyze core.user_profiles, core.user_role_assignments, core.user_memberships;

create temporary table timings (what text, ms numeric, rows int);
grant insert on timings to authenticated;
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(402), 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
do $$
declare
  t0 timestamptz;
  n  int;
begin
  t0 := clock_timestamp();
  select count(*) into n from core.users_dashboard(p_limit => 25);
  insert into timings values ('primera página', extract(epoch from clock_timestamp() - t0) * 1000, n);
  t0 := clock_timestamp();
  select count(*) into n from core.users_dashboard(p_search => 'carga-49', p_limit => 25);
  insert into timings values ('búsqueda', extract(epoch from clock_timestamp() - t0) * 1000, n);
  t0 := clock_timestamp();
  perform core.users_overview();
  insert into timings values ('indicadores', extract(epoch from clock_timestamp() - t0) * 1000, 1);
end
$$;
reset role;

-- Con volumen en la bandeja y en el historial, para alcances chicos (director de marca y gerente),
-- que son los que antes recorrían todo: 5.000 solicitudes y 100.000 eventos de otro local y otra marca.
do $$
begin
  perform core.set_change_context('Carga de prueba', 'maintenance');
end
$$;
insert into workflow.approval_requests (workflow_id, group_id, brand_id, restaurant_id, requested_by, proposed_changes, reason)
select (select id from workflow.approval_workflows where code = 'org.transfer_restaurant'), pg_temp.u(1),
       case when g % 2 = 0 then pg_temp.u(102) end, case when g % 4 = 0 then pg_temp.u(203) end,
       pg_temp.u(401), jsonb_build_object('n', g), 'Carga de prueba'
  from generate_series(1, 5000) as g;
set local role audit_owner;
insert into audit.audit_events (table_schema, table_name, record_id, action, new_values, scope_group_id, scope_brand_id, scope_restaurant_id)
select 'org', 'areas', gen_random_uuid(), 'insert', '{}'::jsonb, '00000000-0000-4000-8000-000000000001',
       '00000000-0000-4000-8000-000000000102', case when g % 10 > 0 then '00000000-0000-4000-8000-000000000203'::uuid end
  from generate_series(1, 100000) as g;
reset role;
analyze workflow.approval_requests, audit.audit_events;

do $$
declare
  t0 timestamptz;
  n  int;
  who record;
begin
  for who in select * from (values ('director', '00000000-0000-4000-8000-000000000403'), ('gerente', '00000000-0000-4000-8000-000000000404')) as v (label, id) loop
    perform set_config('request.jwt.claims', json_build_object('sub', who.id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    t0 := clock_timestamp();
    select count(*) into n from core.audit_history(50);
    insert into timings values ('historial ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000, n);
    t0 := clock_timestamp();
    select count(*) into n from workflow.inbox(true, 50);
    insert into timings values ('pendientes ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000, n);
    t0 := clock_timestamp();
    select count(*) into n from workflow.inbox(false, 50);
    insert into timings values ('resueltas ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000, n);
  end loop;
  perform set_config('request.jwt.claims', '', true);
end
$$;

select is((select rows from timings where what = 'primera página'), 25, 'A10. la primera página trae 25 personas');
select ok((select bool_and(ms < 300) from timings),
  'A10. tablero, bandeja e historial responden en menos de 300 ms con 500 personas, 5.000 solicitudes y 100.000 eventos: '
  || (select string_agg(what || ' ' || round(ms) || ' ms', ', ') from timings));

select * from finish();
rollback;
