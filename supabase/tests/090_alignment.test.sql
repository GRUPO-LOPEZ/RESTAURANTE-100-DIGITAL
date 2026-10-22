-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), paso 1:
-- nombres y columnas de las secciones 4 a 7, estados de cuenta, membresías con lugar y fechas,
-- columnas sin historia, auditoría ampliada y ai.integration_permissions.
-- Personas del seed: ver 050_permissions.
begin;
create extension if not exists pgtap with schema extensions;

select plan(63);

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
-- La auditoría solo la lee su dueño: los conteos se hacen con ese rol.
create function pg_temp.audit_count(p_record uuid) returns int language plpgsql as $$
declare n int;
begin
  set local role audit_owner;
  select count(*) into n from audit.audit_events where record_id = p_record;
  reset role;
  return n;
end
$$;

-- ---------------------------------------------------------------------------
-- Nombres del documento (secciones 4, 6 y 7)
-- ---------------------------------------------------------------------------
select has_table('audit', 'authentication_security_events', 'el registro de seguridad se llama como en el documento');
select hasnt_table('audit', 'security_events', 'el nombre viejo ya no existe');
select has_table('audit', 'authentication_security_event_seals', 'sus sellos también');
select columns_are('audit', 'authentication_security_events', array[
  'id', 'sequence_number', 'occurred_at', 'event_type', 'actor_id', 'actor_subject', 'jwt_role', 'db_user', 'user_id',
  'email', 'operation', 'reason', 'detail', 'scope_group_id', 'scope_brand_id', 'scope_restaurant_id', 'ip_address', 'user_agent'],
  'el registro de seguridad tiene occurred_at, user_id, event_type, ip_address, user_agent y detail');
select ok((select bool_and(c is not null) from unnest(array['actor_user_id', 'actor_service_account_id', 'actor_role_code',
             'scope_brand_id', 'scope_restaurant_id', 'module', 'table_schema', 'table_name', 'record_id', 'action',
             'changed_fields', 'old_values', 'new_values', 'reason', 'source', 'operation_id', 'status']) as c
             join information_schema.columns ic on ic.table_schema = 'audit' and ic.table_name = 'audit_events' and ic.column_name = c),
  'audit_events tiene todas las columnas de la sección 6');
select ok(exists (select 1 from information_schema.columns where table_schema = 'workflow' and table_name = 'approval_workflows'
                    and column_name = 'allow_self_approval')
          and exists (select 1 from information_schema.columns where table_schema = 'workflow' and table_name = 'approval_workflows'
                        and column_name = 'min_approvers')
          and exists (select 1 from information_schema.columns where table_schema = 'workflow' and table_name = 'approval_workflows'
                        and column_name = 'required_permission'),
  'approval_workflows usa required_permission, allow_self_approval y min_approvers');
select ok(to_regprocedure('workflow.request_approval(text, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, text)') is not null
          and to_regprocedure('workflow.decide_approval(uuid, text, text)') is not null
          and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'workflow' and p.proname in ('create_request', 'decide')),
  'las funciones se llaman request_approval y decide_approval (las viejas no existen)');
select is((select count(*)::int from workflow.approval_workflows where allow_self_approval or entity_table is null), 0,
  'ningún tipo de aprobación permite aprobarse lo propio, y todos dicen qué tabla cambian');
select is((select array_agg(e::text order by e::text) from unnest(enum_range(null::core.account_status)) as e),
  array['active', 'deactivated', 'suspended'], 'los estados de cuenta son activo, suspendido y desactivado');

-- ---------------------------------------------------------------------------
-- org: razón social y CUIT del grupo, código de marca
-- ---------------------------------------------------------------------------
select is((select array_agg(code order by code) from org.brands), array['CAFE', 'PARRILLA', 'PASTAS'], 'cada marca tiene su código');
select throws_ok($$insert into org.brands (group_id, name, code) values ('00000000-0000-4000-8000-000000000001', 'Otra Pasta', 'PASTAS')$$,
  '23505', null, 'el código de marca es único dentro del grupo');
select throws_ok($$insert into org.brands (group_id, name, code) values ('00000000-0000-4000-8000-000000000001', 'Minúsculas', 'ragu')$$,
  '23514', null, 'el código de marca va en mayúsculas');
select throws_ok($$insert into org.brands (group_id, name) values ('00000000-0000-4000-8000-000000000001', 'Sin código')$$,
  '23502', null, 'una marca sin código se rechaza');
select is(pg_temp.q(pg_temp.u(401), $$select org.update_group('00000000-0000-4000-8000-000000000001',
            '{"legal_name": "Grupo Demo Dos S.A.", "tax_id": "11111111111"}', 'Datos fiscales')::text$$), '',
  'org.manage del grupo cambia la razón social y el CUIT');
select is((select legal_name || '/' || tax_id from org.groups where id = pg_temp.u(1)), 'Grupo Demo Dos S.A./11111111111',
  'la razón social y el CUIT quedaron guardados');
select throws_ok($$update org.groups set tax_id = '20-1' where id = '00000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'el CUIT del grupo son 11 dígitos');
select is(pg_temp.q(pg_temp.u(404), $$select org.update_brand('00000000-0000-4000-8000-000000000101', '{"code": "PASTA"}', 'Cambio')::text$$),
  'ERROR 42501', 'el gerente no cambia el código de la marca');

-- ---------------------------------------------------------------------------
-- Permisos: la acción separada del módulo
-- ---------------------------------------------------------------------------
select is((select count(*)::int from core.permissions where code <> module || '.' || action), 0,
  'cada permiso tiene su acción, que coincide con el código');
select throws_ok($$insert into core.permissions (code, module, action, description) values ('x.y', 'x', 'z', 'Mal')$$,
  '23514', null, 'una acción que no coincide con el código se rechaza');

-- ---------------------------------------------------------------------------
-- Perfiles: estados y datos de la sección 4
-- ---------------------------------------------------------------------------
select throws_ok($$update core.user_profiles set status = 'suspended' where id = '00000000-0000-4000-8000-000000000409'$$,
  '23514', null, 'una cuenta suspendida tiene que tener la fecha de suspensión');
select throws_ok($$update core.user_profiles set username = 'Con Espacios' where id = '00000000-0000-4000-8000-000000000409'$$,
  '23514', null, 'el nombre de usuario va en minúsculas y sin espacios');
update core.user_profiles set username = 'lucia.op' where id = pg_temp.u(409);
select throws_ok($$update core.user_profiles set username = 'lucia.op' where id = '00000000-0000-4000-8000-000000000406'$$,
  '23505', null, 'el nombre de usuario es único');
select lives_ok($$update core.user_profiles set area_id = '00000000-0000-4000-8000-000000000311', job_title = 'Cocinera'
                   where id = '00000000-0000-4000-8000-000000000409'$$,
  'el área de la persona puede ser de un local de su grupo');
insert into org.groups (id, name) values (pg_temp.u(2), 'Otro Grupo');
insert into org.brands (id, group_id, name, code) values (pg_temp.u(199), pg_temp.u(2), 'Marca ajena', 'AJENA');
insert into org.restaurants (id, group_id, brand_id, name) values (pg_temp.u(299), pg_temp.u(2), pg_temp.u(199), 'Local ajeno');
insert into org.areas (id, group_id, restaurant_id, name) values (pg_temp.u(399), pg_temp.u(2), pg_temp.u(299), 'Cocina ajena');
select throws_ok($$update core.user_profiles set area_id = '00000000-0000-4000-8000-000000000399' where id = '00000000-0000-4000-8000-000000000409'$$,
  '23514', null, 'el área no puede ser de un grupo donde la persona no trabaja');

-- Columnas sin historia: el último acceso y el local elegido no se auditan ni marcan la fila.
select is((select array_agg(c order by c) from unnest(audit.untracked_columns('core', 'user_profiles')) as c),
  array['last_restaurant_id', 'last_seen_at'], 'solo el último acceso y el local elegido son columnas sin historia');
create temporary table before_seen as
  select updated_at, pg_temp.audit_count(id) as events from core.user_profiles where id = pg_temp.u(409);
update core.user_profiles set last_seen_at = now() - interval '1 hour', last_restaurant_id = pg_temp.u(201) where id = pg_temp.u(409);
select ok((select p.last_seen_at is not null and p.updated_at = b.updated_at and pg_temp.audit_count(p.id) = b.events
             from core.user_profiles p, before_seen b where p.id = pg_temp.u(409)),
  'cambiar solo el último acceso se guarda, sin evento en la auditoría y sin marcar la fila como editada');
update core.user_profiles set job_title = 'Cocinera de pastas' where id = pg_temp.u(409);
select ok((select pg_temp.audit_count(p.id) = b.events + 1 from core.user_profiles p, before_seen b where p.id = pg_temp.u(409)),
  'cambiar el puesto sí queda en la auditoría');

-- ---------------------------------------------------------------------------
-- Auditoría ampliada: módulo, número de operación, estado, rol y origen
-- ---------------------------------------------------------------------------
do $$ begin perform core.set_change_context('Prueba de operación', 'manual'); end $$;
update org.areas set name = 'Cocina caliente' where id = pg_temp.u(311);
update org.areas set name = 'Salón principal' where id = pg_temp.u(312);
set local role audit_owner;
create temporary table area_events as
  select * from audit.audit_events where record_id in ('00000000-0000-4000-8000-000000000311', '00000000-0000-4000-8000-000000000312')
     and action = 'update' and reason = 'Prueba de operación';
reset role;
select is((select count(distinct operation_id)::int from area_events where operation_id is not null), 1,
  'los cambios de una misma transacción comparten el número de operación');
select ok((select bool_and(module = 'org' and source = 'manual' and table_schema = 'org') from area_events),
  'cada evento guarda el módulo, el origen y el esquema');
select is(current_setting('app.operation_id', true)::uuid, (select min(operation_id::text)::uuid from area_events),
  'el número de operación es el que fijó core.set_change_context');
select is(audit.module_for('core', 'user_role_assignments') || '/' || audit.module_for('core', 'user_profiles')
          || '/' || audit.module_for('workflow', 'approval_requests'), 'roles/users/approvals',
  'el mapa de módulos agrupa las tablas como el permiso que las maneja');

-- Un cambio hecho por una persona guarda su rol principal; el estado nuevo del registro también.
select is(pg_temp.q(pg_temp.u(404), $$select org.update_restaurant('00000000-0000-4000-8000-000000000201', '{"status": "inactive"}', 'Cierre temporal')::text$$),
  'ERROR 42501', 'el gerente no cierra su local (abrir y cerrar es de la marca)');
select is(pg_temp.q(pg_temp.u(403), $$select org.update_restaurant('00000000-0000-4000-8000-000000000202', '{"status": "inactive"}', 'Cierre temporal')::text$$),
  '', 'la directora de marca cierra un local de su marca');
set local role audit_owner;
create temporary table close_event as
  select * from audit.audit_events where record_id = '00000000-0000-4000-8000-000000000202' and reason = 'Cierre temporal';
reset role;
select ok((select actor_user_id = pg_temp.u(403) and actor_service_account_id is null and actor_role_code = 'brand_director'
                  and status = 'inactive' and action = 'update' from close_event),
  'el evento guarda la persona, su rol principal y el estado nuevo del registro');

-- Aprobar y rechazar quedan como tales.
insert into workflow.approval_requests (workflow_id, group_id, requested_by, subject_user_id, proposed_changes, reason)
values ((select id from workflow.approval_workflows where code = 'core.reactivate_user'), pg_temp.u(1), pg_temp.u(404),
        pg_temp.u(409), '{"user_id": "00000000-0000-4000-8000-000000000409"}', 'Prueba de acción');
insert into workflow.approval_decisions (request_id, decided_by, decision)
select id, pg_temp.u(411), 'rejected' from workflow.approval_requests where reason = 'Prueba de acción';
select set_config('test.decision_id', (select d.id::text from workflow.approval_decisions d
                                          join workflow.approval_requests r on r.id = d.request_id
                                         where r.reason = 'Prueba de acción'), true);
set local role audit_owner;
create temporary table decision_event as
  select e.action::text from audit.audit_events e
   where e.table_name = 'approval_decisions' and e.record_id = current_setting('test.decision_id')::uuid;
reset role;
select is((select array_agg(action) from decision_event), array['reject'], 'una decisión de rechazo queda como reject');

-- La huella del sello ignora las columnas vacías (sumar una columna que nace vacía no invalida los
-- sellos), pero no los nulos de adentro: agregar o quitar uno sí se nota.
set local role audit_owner;
create temporary table digest_check as
  select audit.row_digest('{"a": 1, "b": null}') = audit.row_digest('{"a": 1}') as top_ignored,
         audit.row_digest('{"a": {"x": null}}') <> audit.row_digest('{"a": {}}') as nested_counts;
reset role;
select ok((select top_ignored from digest_check), 'la huella no cuenta las columnas vacías');
select ok((select nested_counts from digest_check), 'la huella sí cuenta un nulo dentro de los valores (no se puede agregar ni quitar sin que se note)');

-- ---------------------------------------------------------------------------
-- Membresías: dónde trabaja cada persona y desde / hasta cuándo
-- ---------------------------------------------------------------------------
select throws_ok($$insert into core.user_memberships (user_id, group_id, restaurant_id)
                   values ('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000202')$$,
  '23514', null, 'una membresía de local tiene que decir la marca');
select throws_ok($$insert into core.user_memberships (user_id, group_id, brand_id)
                   values ('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000199')$$,
  '23503', null, 'la marca de la membresía es del mismo grupo');
select is(pg_temp.r(pg_temp.u(404), $$core.add_member('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001',
            'Trabaja en el local', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201')$$),
  'already_member', 'sumar a alguien a un local donde ya trabaja no duplica la membresía (el seed ya la cargó)');
select is(pg_temp.r(pg_temp.u(404), $$core.add_member('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001',
            'Otro local', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000202')$$),
  'denied', 'el gerente no suma personas a un local que no es suyo');
select is((select count(*)::int from core.user_memberships where user_id = pg_temp.u(409) and deleted_at is null), 2,
  'la persona trabaja en el grupo y en su local (dos membresías)');
select lives_ok($$update core.user_memberships set deleted_at = now()
                   where user_id = '00000000-0000-4000-8000-000000000409' and restaurant_id is not null$$,
  'se puede terminar la membresía de un local si queda la del grupo');
select throws_ok($$update core.user_memberships set deleted_at = now()
                   where user_id = '00000000-0000-4000-8000-000000000409' and restaurant_id is null$$,
  '23514', null, 'no se termina la última membresía de alguien con roles vigentes');
select throws_ok($$update core.user_memberships set ends_at = now() - interval '1 day'
                   where user_id = '00000000-0000-4000-8000-000000000409' and restaurant_id is null$$,
  '23514', null, 'una membresía no termina en el pasado');
select throws_ok($$update core.user_memberships set brand_id = '00000000-0000-4000-8000-000000000102'
                   where user_id = '00000000-0000-4000-8000-000000000409' and restaurant_id is null$$,
  '42501', null, 'una membresía no cambia de lugar');
-- Quien deja de trabajar en un local y vuelve recibe otra membresía.
select is(pg_temp.r(pg_temp.u(404), $$core.add_member('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001',
            'Vuelve al local', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201')$$),
  'applied', 'el gerente vuelve a sumar a su local a alguien que había dejado de trabajar ahí');
update core.user_memberships set ends_at = now() + interval '1 hour'
 where user_id = pg_temp.u(409) and restaurant_id = pg_temp.u(201) and deleted_at is null;
select is(pg_temp.r(pg_temp.u(404), $$core.add_member('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001',
            'Sigue en el local', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201')$$),
  'applied', 'una membresía con fecha de fin no impide sumar una nueva en el mismo lugar');
-- A quien tiene roles fuera de su alcance, el gerente no lo suma (ni queda como quien lo invitó).
select is(pg_temp.r(pg_temp.u(404), $$core.add_member('00000000-0000-4000-8000-000000000402', '00000000-0000-4000-8000-000000000001',
            'Intento', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201')$$),
  'denied', 'el gerente no suma a su local a alguien con roles fuera de su alcance');
select is(pg_temp.r(pg_temp.u(404), $$core.add_member('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001',
            'Sin lugar')$$),
  'denied', 'sumar a todo el grupo pide users.invite de grupo');

-- Una persona sin membresía vigente no tiene permisos, aunque conserve la asignación.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('77777777-7777-7777-7777-777777777777', 'futura@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id) values ('77777777-7777-7777-7777-777777777777', pg_temp.u(1));
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
select '77777777-7777-7777-7777-777777777777', id, 'group', pg_temp.u(1) from core.roles where code = 'auditor';
select ok(core.user_has_permission_for_scope('77777777-7777-7777-7777-777777777777', 'audit.view', 'group', pg_temp.u(1)),
  'con membresía vigente, el rol vale');
alter table core.user_memberships disable trigger validate_identity;
update core.user_memberships set ends_at = now() + interval '1 millisecond' where user_id = '77777777-7777-7777-7777-777777777777';
update core.user_memberships set starts_at = now() + interval '1 day', ends_at = null where user_id = '77777777-7777-7777-7777-777777777777';
alter table core.user_memberships enable trigger validate_identity;
select ok(not core.user_has_permission_for_scope('77777777-7777-7777-7777-777777777777', 'audit.view', 'group', pg_temp.u(1)),
  'con la membresía todavía sin empezar, el rol no vale');
select is(pg_temp.q('77777777-7777-7777-7777-777777777777',
            $$select core.has_permission_in_group('audit.view', '00000000-0000-4000-8000-000000000001')::text$$), 'false',
  'la función de permisos de la sesión (la que usa la RLS) tampoco le da el permiso');
select is(pg_temp.q('77777777-7777-7777-7777-777777777777',
            $$select core.has_permission_anywhere('audit.view')::text$$), 'false',
  'y no aparece en sus permisos vigentes');

-- ---------------------------------------------------------------------------
-- Aprobaciones: lo que no se cambia con una edición
-- ---------------------------------------------------------------------------
select throws_ok($$update workflow.approval_workflows set allow_self_approval = true where code = 'core.reactivate_user'$$,
  '42501', null, 'permitir aprobarse lo propio no se hace con una edición');
select throws_ok($$insert into workflow.approval_workflows (code, name, required_permission, apply_function, allow_self_approval)
                   values ('core.prueba_propia', 'Prueba', 'approvals.decide', 'core.apply_reactivation(uuid)', true)$$,
  '42501', null, 'un tipo de aprobación nuevo tampoco nace permitiendo aprobarse lo propio');
select throws_ok($$update workflow.approval_requests set previous_values = '{"status": "active"}' where reason = 'Prueba de acción'$$,
  '42501', null, 'el antes de una solicitud no cambia');
select throws_ok($$select workflow.request_approval('core.reactivate_user', '00000000-0000-4000-8000-000000000001', null, null,
                     null, null, '{}', null, '   ')$$,
  '22023', null, 'una solicitud sin motivo se rechaza');

-- ---------------------------------------------------------------------------
-- Ingreso: primer y último acceso; una cuenta suspendida no entra
-- ---------------------------------------------------------------------------
select ok(pg_temp.hook(pg_temp.u(406)) ? 'claims', 'el jefe de cocina entra');
select ok((select activated_at is not null and last_seen_at > now() - interval '1 minute' from core.user_profiles where id = pg_temp.u(406)),
  'el ingreso anota el primer acceso y el último');
update core.user_profiles set status = 'suspended', suspended_at = now(), suspension_reason = 'Licencia' where id = pg_temp.u(406);
select ok(pg_temp.hook(pg_temp.u(406)) ? 'error', 'A5. una cuenta suspendida no entra');
select is(pg_temp.q(pg_temp.u(406), $$select core.has_permission('org.view', '00000000-0000-4000-8000-000000000201')::text$$), 'false',
  'A5. y aunque tenga un token vigente, no tiene permisos');

-- ---------------------------------------------------------------------------
-- ai.integration_permissions: solo estructura
-- ---------------------------------------------------------------------------
select ok((select relrowsecurity from pg_class where oid = 'ai.integration_permissions'::regclass)
          and not has_table_privilege('authenticated', 'ai.integration_permissions', 'select,insert,update,delete')
          and not has_table_privilege('service_role', 'ai.integration_permissions', 'select,insert,update,delete')
          and (select count(*) from ai.integration_permissions) = 0,
  '10. los permisos de integración tienen RLS, nadie los toca por la API y no hay ninguno');

select * from finish();
rollback;
