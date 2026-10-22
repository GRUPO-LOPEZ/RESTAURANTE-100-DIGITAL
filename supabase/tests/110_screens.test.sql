-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), paso 3:
-- lecturas de las pantallas de la sección 9 (historial con filtros y exportación, tablero de control,
-- ficha, lista con filtros, matriz de permisos, mi cuenta, bandeja con el antes y el después) y A10.
-- Personas del seed: ver 050_permissions.
begin;
create extension if not exists pgtap with schema extensions;

select plan(45);

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
create function pg_temp.j(p_user uuid, p_sql text) returns jsonb language sql as $$
  select pg_temp.q(p_user, p_sql)::jsonb
$$;

-- Un cambio conocido para leer en el historial: la directora de marca renombra un área.
do $$ begin perform pg_temp.q(pg_temp.u(403), $q$select org.update_area('00000000-0000-4000-8000-000000000311', '{"name": "Cocina caliente"}', 'Nuevo cartel')::text$q$); end $$;

-- ---------------------------------------------------------------------------
-- Un campo cambiado por fila (sección 6)
-- ---------------------------------------------------------------------------
set local role audit_owner;
create temporary table area_fields as
  select field, old_value #>> '{}' as old_value, new_value #>> '{}' as new_value, actor_user_id, reason, module
    from audit.v_field_changes where record_id = '00000000-0000-4000-8000-000000000311' and action = 'update';
reset role;
select is((select array_agg(field) from area_fields), array['name'], 'la vista muestra un campo por fila (sin las columnas de control)');
select ok((select old_value = 'Cocina' and new_value = 'Cocina caliente' and actor_user_id = pg_temp.u(403)
                  and reason = 'Nuevo cartel' and module = 'org' from area_fields),
  'cada fila dice antes, después, quién, por qué y el módulo');
select is(pg_temp.q(pg_temp.u(402), 'select count(*)::text from audit.v_field_changes'), 'ERROR 42501',
  'la vista no se lee por la API');

-- ---------------------------------------------------------------------------
-- Historial con filtros
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(402), $$select string_agg(distinct module, ',') from core.audit_history(200, p_module => 'org')$$), 'org',
  'el filtro por módulo trae solo ese módulo');
select is(pg_temp.q(pg_temp.u(402), format('select count(*)::text from core.audit_history(200, p_actor_id => %L)', pg_temp.u(403))), '1',
  'el filtro por persona trae lo que hizo esa persona');
select is(pg_temp.q(pg_temp.u(402), format('select count(*)::text from core.audit_history(200, p_restaurant_id => %L) where place_name <> %L',
            pg_temp.u(201), 'Demo Pastas Centro')), '0', 'el filtro por local trae solo ese local');
select is(pg_temp.q(pg_temp.u(402), $$select count(*)::text from core.audit_history(200, p_from => now() + interval '1 day')$$), '0',
  'el filtro por fecha deja afuera lo de antes');
select is(pg_temp.q(pg_temp.u(402), $$select count(*)::text from core.audit_history(200, p_critical_only => true)
                                       where table_name not in ('user_role_assignments', 'role_permissions', 'user_profiles', 'roles',
                                                                'permissions', 'approval_decisions', 'approval_workflows')$$), '0',
  'los cambios críticos son solo de roles, permisos, cuentas y aprobaciones');
select is(pg_temp.q(pg_temp.u(403), format('select count(*)::text from core.audit_history(200, p_brand_id => %L)', pg_temp.u(102))), '0',
  'la directora de una marca no ve el historial de otra, aunque la filtre');
select is(pg_temp.q(pg_temp.u(402), $$select count(*)::text from core.audit_history(10, p_module => 'Org; drop')$$), 'ERROR 22023',
  'un módulo con caracteres raros se rechaza');

-- ---------------------------------------------------------------------------
-- Exportar (audit.export)
-- ---------------------------------------------------------------------------
select ok(pg_temp.q(pg_temp.u(410), $$select count(*)::text from core.audit_export(p_module => 'org')$$)::int > 0,
  'el auditor exporta el historial');
set local role audit_owner;
create temporary table export_events as
  select event_type::text, detail from audit.authentication_security_events
   where operation = 'core.audit_export' order by sequence_number;
reset role;
select ok((select event_type = 'audit_exported' and (detail ->> 'rows')::int > 0 and detail ->> 'module' = 'org' from export_events limit 1),
  'la exportación queda en el registro de seguridad, con los filtros y las filas');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from core.audit_export()', 'aal1'), '0',
  'el cocinero no exporta nada');
set local role audit_owner;
create temporary table export_denied as
  select count(*)::int as n from audit.authentication_security_events
   where operation = 'core.audit_export' and event_type = 'operation_denied' and actor_id = '00000000-0000-4000-8000-000000000409';
reset role;
select is((select n from export_denied), 1, '11. y el intento queda registrado como rechazado');

-- ---------------------------------------------------------------------------
-- Tablero de control de usuarios
-- ---------------------------------------------------------------------------
do $$ begin perform core.record_failed_login('cocinero@ejemplo.test'); end $$;
create temporary table panel_dg as select pg_temp.j(pg_temp.u(402), 'select core.users_control_panel()::text') as p;
create temporary table panel_gm as select pg_temp.j(pg_temp.u(404), 'select core.users_control_panel()::text') as p;
select ok((select (p ->> 'can_view_security')::boolean and (p ->> 'rejected_7d')::int >= 1 and p ? 'rejected_prev_7d' from panel_dg),
  'Dirección (security.view) ve los accesos rechazados de 7 días y los de los 7 anteriores');
select is((select jsonb_array_length(p -> 'logins_by_day') from panel_dg), 30, 'el gráfico trae los últimos 30 días, uno por día');
select ok((select p ? 'active' and p ? 'deactivated' and p ? 'suspended' and p ? 'pending_approvals' from panel_dg),
  'trae las tarjetas: activas, desactivadas, suspendidas y aprobaciones pendientes');
select is((select jsonb_array_length(p -> 'by_restaurant') from panel_dg), 4, 'Dirección ve la tabla de personas de los 4 locales');
select ok((select jsonb_typeof(p -> 'critical_changes') = 'array' and jsonb_typeof(p -> 'by_role') = 'array' from panel_dg),
  'trae las personas por rol y los últimos cambios críticos');
select ok((select not (p ->> 'can_view_security')::boolean and p -> 'rejected_7d' = 'null'::jsonb and p -> 'logins_by_day' = 'null'::jsonb
             from panel_gm),
  'el gerente (sin security.view) no ve el registro de seguridad');
select is((select string_agg(x ->> 'restaurant_name', ',') from panel_gm, jsonb_array_elements(p -> 'by_restaurant') x), 'Demo Pastas Centro',
  'el gerente ve solo su local en la tabla por local');
select is(pg_temp.q(pg_temp.u(402), $$select core.users_control_panel('2026-01-01', '2025-01-01')::text$$), 'ERROR 22023',
  'un período al revés se rechaza');

-- ---------------------------------------------------------------------------
-- Ficha de usuario
-- ---------------------------------------------------------------------------
do $$ begin perform core.custom_access_token_hook(jsonb_build_object('user_id', pg_temp.u(409), 'authentication_method', 'password',
         'claims', jsonb_build_object('sub', pg_temp.u(409), 'role', 'authenticated'))); end $$;
create temporary table detail_gm as select pg_temp.j(pg_temp.u(404), format('select core.user_detail(%L)::text', pg_temp.u(409))) as d;
create temporary table detail_dg as select pg_temp.j(pg_temp.u(402), format('select core.user_detail(%L)::text', pg_temp.u(409))) as d;
select ok((select d ->> 'last_seen_at' is not null and jsonb_array_length(d -> 'workplaces') >= 1 from detail_gm),
  'la ficha muestra el último acceso y dónde trabaja');
select ok((select not (d ->> 'can_view_security')::boolean and d -> 'rejected_attempts' = 'null'::jsonb from detail_gm),
  'el gerente no ve los intentos rechazados (es del registro de seguridad)');
select ok((select jsonb_array_length(d -> 'rejected_attempts') >= 1 from detail_dg),
  'Dirección sí ve los intentos rechazados de la persona');
select is(pg_temp.q(pg_temp.u(404), format('select core.user_detail(%L)::text', pg_temp.u(402))), null,
  'la ficha de alguien fuera del alcance no se ve');

-- ---------------------------------------------------------------------------
-- Lista con filtros por rol y área
-- ---------------------------------------------------------------------------
update core.user_profiles set area_id = pg_temp.u(311), job_title = 'Cocinera' where id = pg_temp.u(409);
select is(pg_temp.q(pg_temp.u(402), $$select string_agg(distinct r ->> 'role_code', ',') from core.users_dashboard(p_role_code => 'cook', p_limit => 100) d,
                                       jsonb_array_elements(d.roles) r where r ->> 'role_code' = 'cook'$$), 'cook',
  'el filtro por rol trae a quienes tienen ese rol');
select is(pg_temp.q(pg_temp.u(402), $$select count(*)::text from core.users_dashboard(p_role_code => 'cook', p_limit => 100) d
                                       where not exists (select 1 from jsonb_array_elements(d.roles) r where r ->> 'role_code' = 'cook')$$), '0',
  'y a nadie más');
select is(pg_temp.q(pg_temp.u(402), format('select string_agg(email || '' / '' || job_title || '' / '' || area_name, '','') from core.users_dashboard(p_area_id => %L)',
            pg_temp.u(311))), 'jefecocina@ejemplo.test / Jefe de cocina / Cocina caliente · Demo Pastas Centro,cocinero@ejemplo.test / Cocinera / Cocina caliente · Demo Pastas Centro',
  'el filtro por área trae a quienes trabajan ahí, con su puesto');

-- ---------------------------------------------------------------------------
-- Roles y permisos
-- ---------------------------------------------------------------------------
select ok((select (p ->> 'can_manage')::boolean and jsonb_array_length(p -> 'roles') = 10 and jsonb_array_length(p -> 'grants') > 50
             from (select pg_temp.j(pg_temp.u(401), format('select core.permission_matrix(%L)::text', pg_temp.u(1))) as p) x),
  'el superadmin ve la matriz completa y puede pedir cambios');
select ok((select not (p ->> 'can_manage')::boolean and p -> 'pending' = '[]'::jsonb
             from (select pg_temp.j(pg_temp.u(402), format('select core.permission_matrix(%L)::text', pg_temp.u(1))) as p) x),
  'Dirección ve la matriz pero no pide cambios ni ve los pedidos');

-- ---------------------------------------------------------------------------
-- Mi cuenta
-- ---------------------------------------------------------------------------
create temporary table account as select pg_temp.q(pg_temp.u(404), 'select core.my_account()::text') as a;
select ok((select a::jsonb ? 'sessions' and a::jsonb ? 'mfa_factors' and a::jsonb ->> 'email' = 'gerente@ejemplo.test' from account),
  'mi cuenta trae mis datos, mis factores y mis sesiones');
select ok((select a !~* '(secret|token|JBSWY3DPEHPK3PXP)' from account), 'y nunca el secreto del factor ni tokens');
select is(pg_temp.q(pg_temp.u(409), $$select core.update_my_profile('Lucía', 'Operadora Pérez') ->> 'result'$$, 'aal1'), 'applied',
  'cada persona cambia su propio nombre');
select is((select last_name from core.user_profiles where id = pg_temp.u(409)), 'Operadora Pérez', 'el nombre quedó guardado');
select is(pg_temp.q(pg_temp.u(409), $$select core.update_my_profile('Sistema', 'Interno') ->> 'result'$$, 'aal1'), 'ERROR 22023',
  'nadie se pone un nombre que se confunda con el sistema');
select is(pg_temp.q(pg_temp.u(409), $$select core.update_my_profile('Dirección General', null) ->> 'result'$$, 'aal1'), 'ERROR 22023',
  'ni con un rol');
select is(pg_temp.q(pg_temp.u(402), 'select core.my_account()::text', 'aal1'), null,
  'sin la doble verificación que exige su rol, mi cuenta no devuelve nada');

-- La contraseña y la doble verificación las anota la base cuando pasan de verdad (triggers sobre Auth).
update auth.users set encrypted_password = extensions.crypt('Otra-Clave-2026!', extensions.gen_salt('bf')) where id = pg_temp.u(409);
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
values (gen_random_uuid(), pg_temp.u(409), 'App de prueba', 'totp', 'unverified', now(), now());
update auth.mfa_factors set status = 'verified' where user_id = pg_temp.u(409) and friendly_name = 'App de prueba';
set local role audit_owner;
create temporary table account_events as
  select event_type::text from audit.authentication_security_events
   where user_id = '00000000-0000-4000-8000-000000000409' and event_type in ('password_changed', 'mfa_enrolled');
reset role;
select is((select array_agg(event_type order by event_type) from account_events), array['mfa_enrolled', 'password_changed'],
  'el cambio de contraseña y el registro de la doble verificación quedan en el registro de seguridad');
select ok(to_regprocedure('core.log_account_event(text)') is null,
  'no hay una función que la pantalla pueda llamar para inventar esos eventos');

-- Una sesión cerrada deja de operar en la consulta siguiente, aunque su token no haya vencido.
insert into auth.sessions (id, user_id, created_at, updated_at)
values ('12121212-1212-1212-1212-121212121212', pg_temp.u(409), now(), now());
create function pg_temp.with_session(p_session uuid) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000409', 'role', 'authenticated',
                                                             'aal', 'aal1', 'session_id', p_session)::text, true);
  set local role authenticated;
  v := core.has_permission('org.view', '00000000-0000-4000-8000-000000000201')::text || '/'
       || (core.my_session() ->> 'session_active');
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
select is(pg_temp.with_session('12121212-1212-1212-1212-121212121212'), 'true/true', 'con la sesión abierta, opera');
delete from auth.sessions where id = '12121212-1212-1212-1212-121212121212';
select is(pg_temp.with_session('12121212-1212-1212-1212-121212121212'), 'false/false',
  'cerrada la sesión (desde otro dispositivo, al salir o al desactivar), el mismo token ya no opera');

-- Historial: el filtro por persona usa su propio índice y respeta el alcance.
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from core.audit_history(50, p_actor_id => %L)', pg_temp.u(403))), '0',
  'el gerente no ve lo que hizo la directora fuera de su local, aunque la filtre');

-- ---------------------------------------------------------------------------
-- Bandeja: el antes y el después, sin lo técnico
-- ---------------------------------------------------------------------------
do $$ begin perform pg_temp.q(pg_temp.u(401), format('select core.request_role_permission_change(%L, ''cook'', ''audit.view'', true, ''Que vean el historial'')::text', pg_temp.u(1))); end $$;
select ok((select (r -> 'previous_values' ->> 'grant') = 'false' and (r -> 'proposed_changes' ->> 'grant') = 'true'
                  and not (r -> 'proposed_changes') ? 'excluded_approvers'
             from (select pg_temp.j(pg_temp.u(402), $$select to_jsonb(i)::text from workflow.inbox(true, 10) i
                                                     where i.workflow_code = 'core.change_role_permission' limit 1$$) as r) x),
  'la bandeja muestra el antes y el después, sin a quiénes excluye');

-- ---------------------------------------------------------------------------
-- A10: las lecturas nuevas responden en menos de 300 ms con volumen
-- 500 personas, 100.000 eventos de auditoría y 20.000 de seguridad en 30 días.
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
set local role audit_owner;
insert into audit.audit_events (table_schema, table_name, record_id, action, new_values, module, scope_group_id, scope_brand_id, scope_restaurant_id)
select 'org', 'areas', gen_random_uuid(), 'insert', '{}'::jsonb, case when g % 3 = 0 then 'org' else 'users' end,
       '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000102',
       case when g % 10 > 0 then '00000000-0000-4000-8000-000000000203'::uuid end
  from generate_series(1, 100000) as g;
insert into audit.authentication_security_events (event_type, occurred_at, user_id, email, scope_group_id)
select (case when g % 5 = 0 then 'login_failed' else 'login_succeeded' end)::audit.security_event_type,
       now() - (g % 30) * interval '1 day', '00000000-0000-4000-8000-000000000409', 'cocinero@ejemplo.test',
       '00000000-0000-4000-8000-000000000001'
  from generate_series(1, 20000) as g;
reset role;
analyze core.user_profiles, core.user_role_assignments, core.user_memberships, audit.audit_events, audit.authentication_security_events;

create temporary table timings (what text, ms numeric);
grant insert on timings to authenticated;
set local role authenticated;
do $$
declare
  t0  timestamptz;
  who record;
begin
  for who in select * from (values ('dirección', '00000000-0000-4000-8000-000000000402'), ('directora', '00000000-0000-4000-8000-000000000403'),
                                   ('gerente', '00000000-0000-4000-8000-000000000404')) as v (label, id) loop
    perform set_config('request.jwt.claims', json_build_object('sub', who.id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    t0 := clock_timestamp();
    perform core.users_control_panel();
    insert into timings values ('tablero ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000);
    t0 := clock_timestamp();
    perform count(*) from core.audit_history(50, p_module => 'org', p_from => now() - interval '7 days');
    insert into timings values ('historial filtrado ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000);
    t0 := clock_timestamp();
    perform core.user_detail('00000000-0000-4000-8000-000000000409');
    insert into timings values ('ficha ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000);
    t0 := clock_timestamp();
    perform count(*) from core.users_dashboard(p_role_code => 'cook', p_limit => 25);
    insert into timings values ('lista por rol ' || who.label, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  perform set_config('request.jwt.claims', '', true);
end
$$;
reset role;
select ok((select bool_and(ms < 300) from timings),
  'A10. tablero de control, historial filtrado, ficha y lista responden en menos de 300 ms con 500 personas, 100.000 eventos y 20.000 ingresos: '
  || (select string_agg(what || ' ' || round(ms) || ' ms', ', ') from timings));

select * from finish();
rollback;
