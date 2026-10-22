-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), paso 2:
-- permisos nuevos, mis lugares, suspender, selector de local, avisos y la tabla de ensayo.
-- Pruebas obligatorias que cubre sobre la tabla de ensayo core.test_documents: 2, 3 y 7.
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
create function pg_temp.hook(p_user uuid) returns jsonb language sql as $$
  select core.custom_access_token_hook(jsonb_build_object(
    'user_id', p_user, 'authentication_method', 'password', 'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated')))
$$;
create function pg_temp.security_count(p_type text, p_user uuid) returns int language plpgsql as $$
declare n int;
begin
  set local role audit_owner;
  select count(*) into n from audit.authentication_security_events where event_type::text = p_type and user_id = p_user;
  reset role;
  return n;
end
$$;
create function pg_temp.perms(p_role text) returns text[] language sql as $$
  select coalesce(array_agg(p.code order by p.code), '{}')
    from core.role_permissions rp
    join core.roles r on r.id = rp.role_id and r.code = p_role
    join core.permissions p on p.id = rp.permission_id and p.module = 'test_documents'
   where rp.deleted_at is null
$$;

-- ---------------------------------------------------------------------------
-- Permisos nuevos (sección 8)
-- ---------------------------------------------------------------------------
select is((select array_agg(code order by code) from core.permissions where code in ('permissions.manage', 'security.view', 'org.archive')),
  array['org.archive', 'permissions.manage', 'security.view'], 'existen permissions.manage, security.view y org.archive');
select ok(exists (select 1 from core.permissions where code = 'roles.assign') and exists (select 1 from core.permissions where code = 'org.transfer'),
  'roles.assign y org.transfer se quedan (decisión de Joaco: sumar sin quitar)');
select is(pg_temp.perms('cook'), array['test_documents.view'], 'ensayo: el cocinero solo ve');
select is(pg_temp.perms('head_chef'), array['test_documents.edit', 'test_documents.view'], 'ensayo: el jefe de cocina ve y edita');
select is(pg_temp.perms('executive_chef'), array['test_documents.edit', 'test_documents.publish', 'test_documents.view'],
  'ensayo: el chef ve, edita y publica');
select is(pg_temp.perms('controller'), array['test_documents.view', 'test_documents.view_costs'], 'ensayo: controller ve y ve costos');
select throws_ok($$select core.check_role_permission_change((select id from core.roles where code = 'general_management'), 'permissions.manage', true)$$,
  '23514', null, 'un rol que aprueba no puede recibir permissions.manage (separación de funciones)');
select throws_ok($$select core.check_role_permission_change((select id from core.roles where code = 'superadmin'), 'permissions.manage', false)$$,
  '23514', null, 'al superadmin no se le quita permissions.manage');

-- Archivar pide org.archive.
select is(pg_temp.q(pg_temp.u(404), $$select org.set_deleted('areas', '00000000-0000-4000-8000-000000000313', true, 'Ya no se usa')::text$$),
  'ERROR 42501', 'el gerente (org.manage, sin org.archive) no archiva un área de su local');
select is(pg_temp.q(pg_temp.u(403), $$select org.set_deleted('areas', '00000000-0000-4000-8000-000000000313', true, 'Ya no se usa')::text$$),
  '', 'la directora de marca archiva un área de un local de su marca');
select ok((select deleted_at is not null from org.areas where id = pg_temp.u(313)), 'el área quedó archivada');

-- ---------------------------------------------------------------------------
-- Mis marcas y locales (sección 5)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(402), 'select count(*)::text from core.my_scopes()'), '4', 'Dirección General: los 4 locales');
select is(pg_temp.q(pg_temp.u(403), 'select count(*)::text from core.my_scopes()'), '2', 'la directora de marca: los 2 locales de su marca');
select is(pg_temp.q(pg_temp.u(411), 'select string_agg(restaurant_name, '', '' order by restaurant_name) from core.my_scopes()'),
  'Demo Pastas Centro, Demo Pastas Norte', 'la gerente de dos locales: sus dos locales');
select is(pg_temp.q(pg_temp.u(409), 'select string_agg(restaurant_name || '' · '' || brand_code, '', '') from core.my_scopes()'),
  'Demo Pastas Centro · PASTAS', 'el cocinero: su local, con el código de la marca');
select is(pg_temp.q(null, 'select count(*)::text from core.my_scopes()'), 'ERROR 42501', 'sin sesión no se consulta');

-- ---------------------------------------------------------------------------
-- Selector de local
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(411), $$core.set_active_restaurant('00000000-0000-4000-8000-000000000202')$$), 'applied',
  'la gerente elige uno de sus locales');
select is((select last_restaurant_id from core.user_profiles where id = pg_temp.u(411)), pg_temp.u(202), 'el local elegido queda en la base');
select is(pg_temp.q(pg_temp.u(411), $$select core.set_active_restaurant('00000000-0000-4000-8000-000000000203')::text$$),
  'ERROR 42501', 'no se elige un local ajeno');

-- ---------------------------------------------------------------------------
-- Suspender y levantar la suspensión (pausa, sin aprobación)
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(404), $$core.suspend_user('00000000-0000-4000-8000-000000000404', 'Prueba')$$), 'denied',
  'nadie se suspende a sí mismo');
select is(pg_temp.r(pg_temp.u(404), $$core.suspend_user('00000000-0000-4000-8000-000000000402', 'Prueba')$$), 'denied',
  'el gerente no suspende a quien tiene roles fuera de su alcance');
select is(pg_temp.r(pg_temp.u(404), $$core.suspend_user('00000000-0000-4000-8000-000000000409', 'Licencia por una semana')$$), 'applied',
  'el gerente suspende a una persona de su local');
select ok((select status = 'suspended' and suspended_by = pg_temp.u(404) and suspension_reason = 'Licencia por una semana'
             from core.user_profiles where id = pg_temp.u(409)), 'queda suspendida, con quién y por qué');
select ok(pg_temp.hook(pg_temp.u(409)) ? 'error', 'A5. la cuenta suspendida no entra');
select is(pg_temp.q(pg_temp.u(409), $$select core.has_permission('org.view', '00000000-0000-4000-8000-000000000201')::text$$), 'false',
  'A5. y con un token vigente no tiene permisos');
select is(pg_temp.security_count('account_suspended', pg_temp.u(409)), 1, 'la suspensión queda en el registro de seguridad');
select is(pg_temp.r(pg_temp.u(411), $$core.lift_suspension('00000000-0000-4000-8000-000000000409', 'Volvió de la licencia')$$), 'applied',
  'otra persona con permiso sobre ese local levanta la suspensión, sin aprobación');
select ok(pg_temp.hook(pg_temp.u(409)) ? 'claims', 'A5. levantada la suspensión, vuelve a entrar');
select is(pg_temp.security_count('account_unsuspended', pg_temp.u(409)), 1, 'el levantamiento queda en el registro de seguridad');
select is(pg_temp.r(pg_temp.u(404), $$core.lift_suspension('00000000-0000-4000-8000-000000000409', 'Otra vez')$$), 'not_suspended',
  'levantar una suspensión que no existe no hace nada');

-- ---------------------------------------------------------------------------
-- Avisos: request_approval avisa a quienes pueden decidir
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('88888888-8888-8888-8888-888888888888', 'nueva-chef@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id) values ('88888888-8888-8888-8888-888888888888', pg_temp.u(1));
select is(pg_temp.r(pg_temp.u(403), $$core.assign_role('88888888-8888-8888-8888-888888888888', 'executive_chef', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', null, null, 'Nueva chef de la marca')$$),
  'pending_approval', 'dar un rol que aprueba queda pendiente');
create temporary table request_notes as
  select n.recipient_user_id from core.notifications n
    join workflow.approval_requests r on r.id = n.request_id
   where r.subject_user_id = '88888888-8888-8888-8888-888888888888';
select ok(exists (select 1 from request_notes where recipient_user_id = pg_temp.u(405)),
  'avisa a quien puede decidir (el chef ejecutivo de la marca)');
select ok(not exists (select 1 from request_notes where recipient_user_id in (pg_temp.u(403), '88888888-8888-8888-8888-888888888888')),
  'no le avisa a quien pidió ni a la persona afectada');
select ok(not exists (select 1 from request_notes where recipient_user_id in (pg_temp.u(404), pg_temp.u(409), pg_temp.u(401))),
  'no le avisa a quien no puede decidir');
select is(pg_temp.q(pg_temp.u(405), 'select count(*)::text from core.notifications where read_at is null'), '1',
  'el chef ve su aviso sin leer');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from core.notifications'), '0', 'cada persona ve solo sus avisos');
select is(pg_temp.q(pg_temp.u(405), 'select core.mark_notifications_read()::text'), '1', 'marca su aviso como leído');
select is(pg_temp.q(pg_temp.u(405), 'select core.mark_notifications_read()::text'), '0', 'la segunda vez no hay nada para marcar');
select is(pg_temp.q(pg_temp.u(405), $$update core.notifications set read_at = null returning 'x'$$), 'ERROR 42501',
  'nadie edita los avisos directo');

-- ---------------------------------------------------------------------------
-- Tabla de ensayo: pruebas 2, 3 y 7 (sección 10)
-- ---------------------------------------------------------------------------
-- Un documento de la marca, publicado y con costo (cargado como lo haría el seed).
do $$ begin perform core.set_change_context('Documento de ensayo de la prueba', 'seed'); end $$;
insert into core.test_documents (id, group_id, brand_id, document_key, version_number, title, content, cost)
values ('99999999-9999-9999-9999-999999999991', pg_temp.u(1), pg_temp.u(101), '99999999-9999-9999-9999-999999999990', 1,
        'Salsa de tomate', 'Sofreír, agregar tomate y cocinar 40 minutos.', 1520.50);
update core.test_documents set status = 'in_review' where id = '99999999-9999-9999-9999-999999999991';
update core.test_documents set status = 'approved' where id = '99999999-9999-9999-9999-999999999991';
update core.test_documents set status = 'published' where id = '99999999-9999-9999-9999-999999999991';

-- 2. El cocinero abre la receta vigente pero no ve costos.
select is(pg_temp.q(pg_temp.u(409), $$select title || ' / ' || coalesce(cost::text, 'sin costo') from core.v_test_documents
                                      where id = '99999999-9999-9999-9999-999999999991'$$),
  'Salsa de tomate / sin costo', '2. el cocinero abre el documento vigente de su marca, sin el costo');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from core.test_documents'), 'ERROR 42501',
  '2. y no puede leer la tabla directo (ahí está el costo)');
select is(pg_temp.q(pg_temp.u(407), $$select cost::text from core.v_test_documents where id = '99999999-9999-9999-9999-999999999991'$$),
  '1520.5000', 'Controller sí ve el costo');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from core.v_test_documents where brand_id = '00000000-0000-4000-8000-000000000102'$$),
  '0', 'el cocinero no ve documentos de otra marca');

-- 3. El jefe de cocina crea un borrador pero no publica sin permiso.
select is(pg_temp.r(pg_temp.u(406), $$core.create_test_document_draft('00000000-0000-4000-8000-000000000101', 'Ñoquis del 29', 'Receta nueva del local',
            p_restaurant_id => '00000000-0000-4000-8000-000000000201', p_content => 'Papa, harina y huevo.', p_cost => 300)$$),
  'applied', '3. el jefe de cocina crea un borrador en su local');
select is(pg_temp.q(pg_temp.u(406), $$select status::text || '/' || coalesce(cost::text, 'sin costo') from core.v_test_documents where title = 'Ñoquis del 29'$$),
  'draft/sin costo', '3. queda en borrador, y sin costo: quien no ve costos no los carga');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from core.v_test_documents where title = 'Ñoquis del 29'$$), '0',
  '3. el cocinero no ve borradores');
select is(pg_temp.r(pg_temp.u(406), format('core.request_test_document_review(%L, %L)', (select id from core.test_documents where title = 'Ñoquis del 29'), 'Lista para revisar')),
  'applied', '3. el jefe de cocina pide la revisión');
select is(pg_temp.r(pg_temp.u(406), format('core.publish_test_document(%L, %L)', (select id from core.test_documents where title = 'Ñoquis del 29'), 'La publico yo')),
  'denied', '3. pero no la puede publicar');
set local role audit_owner;
create temporary table publish_denied as
  select count(*)::int as n from audit.authentication_security_events
   where event_type = 'operation_denied' and operation = 'core.publish_test_document'
     and actor_id = '00000000-0000-4000-8000-000000000406';
reset role;
select is((select n from publish_denied), 1, '11. el intento de publicar sin permiso queda en el registro de seguridad');
select is(pg_temp.r(pg_temp.u(405), format('core.publish_test_document(%L, %L)', (select id from core.test_documents where title = 'Ñoquis del 29'), 'Aprobada por la chef')),
  'applied', '3. la chef de la marca la publica');

-- 7. Una versión aprobada conserva su historia.
select throws_ok($$update core.test_documents set content = 'Otra cosa' where id = '99999999-9999-9999-9999-999999999991'$$,
  '42501', null, '7. una versión publicada no se modifica');
select is(pg_temp.r(pg_temp.u(405), $$core.create_test_document_draft('00000000-0000-4000-8000-000000000101', 'Salsa de tomate', 'Más cocción',
            p_content => 'Sofreír, agregar tomate y cocinar 45 minutos.', p_document_key => '99999999-9999-9999-9999-999999999990')$$),
  'applied', '7. corregir es crear la versión 2 del mismo documento');
select is(pg_temp.r(pg_temp.u(405), format('core.request_test_document_review(%L, %L)', (select id from core.test_documents
            where document_key = '99999999-9999-9999-9999-999999999990' and version_number = 2), 'Revisión'))
          || '/' || pg_temp.r(pg_temp.u(405), format('core.publish_test_document(%L, %L)', (select id from core.test_documents
            where document_key = '99999999-9999-9999-9999-999999999990' and version_number = 2), 'Publicada')),
  'applied/applied', '7. la versión 2 se revisa y se publica');
select ok((select bool_and(case version_number when 1 then status = 'archived' and content like '%40 minutos%' and cost = 1520.5
                                               else status = 'published' and cost = 1520.5 end)
             from core.test_documents where document_key = '99999999-9999-9999-9999-999999999990'),
  '7. la versión 1 queda archivada con su contenido intacto, y la 2 hereda el costo');
set local role audit_owner;
create temporary table doc_history as
  select string_agg(action::text, ',' order by sequence_number) as actions from audit.audit_events
   where record_id = '99999999-9999-9999-9999-999999999991';
reset role;
select is((select actions from doc_history), 'insert,update,update,publish,update',
  '7. la historia de la versión 1 queda completa: alta, revisión, aprobación, publicación y archivo');

-- Un borrador de toda la marca solo lo ve quien edita en toda la marca (revisión de base, G1).
select is(pg_temp.r(pg_temp.u(405), $$core.create_test_document_draft('00000000-0000-4000-8000-000000000101', 'Masa madre', 'Receta nueva de la marca',
            p_content => 'Harina y agua.')$$), 'applied', 'la chef crea un borrador de la marca');
select is(pg_temp.q(pg_temp.u(405), $$select count(*)::text from core.v_test_documents where title = 'Masa madre'$$), '1',
  'la chef ve su borrador de marca');
select is(pg_temp.q(pg_temp.u(406), $$select count(*)::text from core.v_test_documents where title = 'Masa madre'$$), '0',
  'el jefe de cocina de un local no ve borradores de toda la marca');

-- Separación de funciones también por persona al cambiar la matriz (revisión de seguridad, M-C).
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('66666666-6666-6666-6666-666666666666', 'doble@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id) values ('66666666-6666-6666-6666-666666666666', pg_temp.u(1));
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
select '66666666-6666-6666-6666-666666666666', id, 'group', pg_temp.u(1) from core.roles where code in ('auditor', 'controller');
select throws_ok($$select core.check_role_permission_change((select id from core.roles where code = 'auditor'), 'permissions.manage', true)$$,
  '23514', null, 'no se le da permissions.manage a un rol si alguien que lo tiene también aprueba por otro rol');

-- Los avisos quedan en la auditoría; leerlos no (columna sin historia).
set local role audit_owner;
create temporary table note_audit as
  select count(*) filter (where action = 'insert') as inserts, count(*) filter (where action = 'update') as updates
    from audit.audit_events where table_name = 'notifications';
reset role;
select ok((select inserts >= 1 and updates = 0 from note_audit),
  'crear un aviso queda en la auditoría; marcarlo como leído no');
select ok((select count(*) = 3 from pg_trigger where tgrelid = 'core.notifications'::regclass and not tgisinternal
             and tgname in ('set_control_columns', 'log_change', 'reject_truncate'))
          and (select count(*) = 4 from pg_trigger where tgrelid = 'core.test_documents'::regclass and not tgisinternal
                 and tgname in ('set_control_columns', 'enforce_version_rules', 'log_change', 'reject_truncate')),
  'los avisos y los documentos de ensayo tienen sus triggers de control, auditoría y versiones');
select throws_ok($$insert into core.notifications (recipient_user_id, group_id, kind, title, link)
                   values ('00000000-0000-4000-8000-000000000409', '00000000-0000-4000-8000-000000000001', 'approval_requested', 'X', '//otro-sitio.test')$$,
  '23514', null, 'el enlace de un aviso es siempre interno');

-- A10: pedir una aprobación (con sus avisos) y la bandeja, con 2.000 personas y 5.000 solicitudes.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
select gen_random_uuid(), format('carga-%s@ejemplo.test', g), '{}', '{}', 'authenticated', 'authenticated'
  from generate_series(1, 2000) as g;
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('77777777-7777-7777-7777-777777777777', 'otra-chef@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id)
select id, pg_temp.u(1) from core.user_profiles
 where email like 'carga-%@ejemplo.test' or id = '77777777-7777-7777-7777-777777777777';
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
select p.id, (select id from core.roles where code = 'cook'), 'restaurant', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201)
  from core.user_profiles p where p.email like 'carga-%@ejemplo.test';
do $$ begin perform core.set_change_context('Carga de prueba', 'maintenance'); end $$;
insert into workflow.approval_requests (workflow_id, group_id, brand_id, requested_by, proposed_changes, reason)
select (select id from workflow.approval_workflows where code = 'org.transfer_restaurant'), pg_temp.u(1), pg_temp.u(101),
       pg_temp.u(401), jsonb_build_object('n', g), 'Carga de prueba'
  from generate_series(1, 5000) as g;
analyze core.user_profiles, core.user_role_assignments, core.user_memberships, workflow.approval_requests;
create temporary table timings (what text, ms numeric);
grant insert on timings to authenticated;
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(403), 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
do $$
declare
  t0 timestamptz;
begin
  t0 := clock_timestamp();
  perform core.assign_role('77777777-7777-7777-7777-777777777777', 'executive_chef', 'brand', '00000000-0000-4000-8000-000000000001',
                           '00000000-0000-4000-8000-000000000101', null, null, 'Prueba de volumen');
  insert into timings values ('pedir una aprobación con avisos', extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  perform count(*) from workflow.inbox(true, 50);
  insert into timings values ('bandeja de la directora', extract(epoch from clock_timestamp() - t0) * 1000);
end
$$;
reset role;
select set_config('request.jwt.claims', '', true);
select ok((select bool_and(ms < 300) from timings),
  'A10. pedir una aprobación y la bandeja responden en menos de 300 ms con 2.000 personas y 5.000 solicitudes: '
  || (select string_agg(what || ' ' || round(ms) || ' ms', ', ') from timings));

select * from finish();
rollback;
