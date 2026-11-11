-- Fase 1 · M6 + M7: dar y quitar roles sin escalada, aprobaciones, cambio de matriz, traspaso
-- de locales, versiones (con una tabla de prueba de recetas) y la prueba de catálogo.
-- Pruebas obligatorias que cubre: 2, 3, 7, 11 y 12. Adicionales: A1, A2, A6 (por función) y A9.
-- Personas del seed: ver 050_permissions. ...0412 es la segunda persona de Dirección General.
begin;
create extension if not exists pgtap with schema extensions;

select plan(101);

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
-- Llama a una función que devuelve jsonb y devuelve su "result" (applied, pending_approval, denied...).
create function pg_temp.r(p_user uuid, p_call text, p_aal text default 'aal2')
returns text
language sql
as $$ select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call), p_aal) $$;
create function pg_temp.assign(p_user uuid, p_target uuid, p_role text, p_scope text, p_brand int, p_restaurant int)
returns text
language sql
as $$
  select pg_temp.r(p_user, format(
    'core.assign_role(%L, %L, %L, %L, %L, %L, null, ''Prueba de asignación'')',
    p_target, p_role, p_scope, pg_temp.u(1),
    case when p_brand is not null then pg_temp.u(p_brand) end,
    case when p_restaurant is not null then pg_temp.u(p_restaurant) end))
$$;
create function pg_temp.req(p_role text, p_user uuid) returns uuid language sql as $$
  select r.id from workflow.approval_requests r
   where r.proposed_changes ->> 'role_code' = p_role and r.subject_user_id = p_user and r.status = 'pending'
$$;

-- Personas nuevas, miembros del grupo, sin roles.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'nueva1@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'nueva2@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated'),
  ('33333333-3333-3333-3333-333333333333', 'sin-grupo@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id) values
  ('11111111-1111-1111-1111-111111111111', pg_temp.u(1)),
  ('22222222-2222-2222-2222-222222222222', pg_temp.u(1));

-- ---------------------------------------------------------------------------
-- A1: nadie se da roles a sí mismo (y el intento queda registrado)
-- ---------------------------------------------------------------------------
select is(pg_temp.assign(pg_temp.u(401), pg_temp.u(401), 'cook', 'restaurant', 101, 201), 'denied', 'A1. el superadmin no se da roles a sí mismo');
select is(pg_temp.assign(pg_temp.u(404), pg_temp.u(404), 'cook', 'restaurant', 101, 201), 'denied', 'A1. el gerente no se da roles a sí mismo');
select is((select count(*)::int from core.user_role_assignments a join core.roles r on r.id = a.role_id
            where a.user_id in (pg_temp.u(401), pg_temp.u(404)) and r.code = 'cook'), 0, 'A1. no se creó ninguna asignación');
select is((select count(*)::int from audit.authentication_security_events
            where event_type = 'operation_denied' and operation = 'core.assign_role'
              and actor_id = user_id and actor_id in (pg_temp.u(401), pg_temp.u(404))), 2,
  'A1. los dos intentos quedaron en el registro de seguridad');

-- ---------------------------------------------------------------------------
-- M6: dar roles sin escalada
-- ---------------------------------------------------------------------------
select is(pg_temp.assign(pg_temp.u(409), '11111111-1111-1111-1111-111111111111', 'cook', 'restaurant', 101, 201), 'denied',
  'el cocinero no puede dar roles');
select ok(exists (select 1 from audit.authentication_security_events
                   where event_type = 'operation_denied' and actor_id = pg_temp.u(409) and operation = 'core.assign_role'
                     and user_id = '11111111-1111-1111-1111-111111111111' and scope_restaurant_id = pg_temp.u(201)),
  '11. la operación rechazada del cocinero quedó registrada, con quién, a quién y dónde');
select is(pg_temp.assign(pg_temp.u(404), '11111111-1111-1111-1111-111111111111', 'cook', 'restaurant', 101, 201), 'applied',
  'el gerente da el rol de cocinero en su local');
select ok(exists (select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id
                   where a.user_id = '11111111-1111-1111-1111-111111111111' and r.code = 'cook'
                     and a.restaurant_id = pg_temp.u(201) and a.created_by = pg_temp.u(404) and a.deleted_at is null),
  'la asignación quedó con quién la dio');
select is(pg_temp.assign(pg_temp.u(404), '11111111-1111-1111-1111-111111111111', 'cook', 'restaurant', 101, 202), 'denied',
  'el gerente no da roles en otro local');
select is(pg_temp.assign(pg_temp.u(404), '11111111-1111-1111-1111-111111111111', 'executive_chef', 'restaurant', 101, 201), 'denied',
  'el gerente (nivel 4) no da Chef Ejecutivo (nivel 5): se comparan permisos, no niveles');
select ok(exists (select 1 from audit.authentication_security_events where actor_id = pg_temp.u(404) and detail -> 'missing_permissions' ? 'approvals.decide'),
  'el rechazo explica qué permisos le faltan');
select is(pg_temp.assign(pg_temp.u(404), '11111111-1111-1111-1111-111111111111', 'restaurant_manager', 'restaurant', 101, 201), 'applied',
  'el gerente puede dar un rol igual al suyo, que no aprueba nada');
select is(pg_temp.assign(pg_temp.u(403), '22222222-2222-2222-2222-222222222222', 'executive_chef', 'brand', 101, null), 'pending_approval',
  'cuenta títere: el director da un rol que aprueba y queda pendiente de otra persona');
select ok(not exists (select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id
                       where a.user_id = '22222222-2222-2222-2222-222222222222' and r.code = 'executive_chef'),
  'mientras está pendiente, el rol no tiene efecto');
select is(pg_temp.assign(pg_temp.u(401), '11111111-1111-1111-1111-111111111111', 'general_management', 'group', null, null), 'pending_approval',
  'el superadmin pide Dirección General (que tiene permisos que él no tiene): queda pendiente');
select is(pg_temp.assign(pg_temp.u(401), '11111111-1111-1111-1111-111111111111', 'superadmin', 'group', null, null), 'pending_approval',
  'dar Superadministrador siempre queda pendiente');
select is((select w.code from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
            where r.id = pg_temp.req('superadmin', '11111111-1111-1111-1111-111111111111')),
  'core.assign_superadmin', 'el pedido de superadmin usa la aprobación de Dirección General');
select is(pg_temp.assign(pg_temp.u(403), '11111111-1111-1111-1111-111111111111', 'brand_director', 'brand', 102, null), 'denied',
  'el director no da roles en otra marca');
select is(pg_temp.assign(pg_temp.u(404), '11111111-1111-1111-1111-111111111111', 'cook', 'restaurant', 101, 201), 'ERROR 23505',
  'la misma asignación vigente no se repite');
select is(pg_temp.assign(pg_temp.u(404), '33333333-3333-3333-3333-333333333333', 'cook', 'restaurant', 101, 201), 'ERROR 23514',
  'no se dan roles a quien no es miembro del grupo');
select is(pg_temp.assign(pg_temp.u(401), '11111111-1111-1111-1111-111111111111', 'cook', 'restaurant', 101, 203), 'denied',
  'A6. un alcance incoherente (local de otra marca) no da permiso: la función lo rechaza');
select is(pg_temp.q(pg_temp.u(401), format('insert into core.user_role_assignments (user_id, role_id, scope_type, group_id) values (%L, (select id from core.roles where code = ''cook''), ''group'', %L) returning ''ok''',
                                           '11111111-1111-1111-1111-111111111111', pg_temp.u(1))),
  'ERROR 42501', 'nadie escribe directo en las asignaciones: solo con assign_role');

-- Quitar roles
select is(pg_temp.r(pg_temp.u(404), format('core.revoke_role(%L, ''Cambio de puesto'')',
            (select a.id from core.user_role_assignments a join core.roles r on r.id = a.role_id
              where a.user_id = '11111111-1111-1111-1111-111111111111' and r.code = 'cook' and a.deleted_at is null))),
  'applied', 'el gerente quita un rol de su local');
select is(pg_temp.r(pg_temp.u(404), format('core.revoke_role(%L, ''Prueba'')',
            (select id from core.user_role_assignments where user_id = pg_temp.u(403) and deleted_at is null))),
  'denied', 'el gerente no le quita el rol al director de su marca');
select is(pg_temp.r(pg_temp.u(406), format('core.revoke_role(%L, ''Prueba'')',
            (select id from core.user_role_assignments where user_id = pg_temp.u(409) and deleted_at is null))),
  'denied', 'el jefe de cocina no quita roles');
select is(pg_temp.r(pg_temp.u(401), format('core.revoke_role(%L, ''Prueba'')',
            (select id from core.user_role_assignments where user_id = pg_temp.u(401) and deleted_at is null))),
  'denied', 'no se puede quitar al último Superadministrador activo');

-- Cambio de la matriz
select is(pg_temp.r(pg_temp.u(401), format('core.request_role_permission_change(%L, ''cook'', ''approvals.view'', true, ''Que vean sus pedidos'')', pg_temp.u(1))),
  'pending_approval', 'el superadmin pide cambiar la matriz: queda pendiente');
select is(pg_temp.r(pg_temp.u(401), format('core.request_role_permission_change(%L, ''superadmin'', ''approvals.decide'', true, ''Prueba'')', pg_temp.u(1))),
  'denied', 'nadie cambia los permisos de un rol que tiene él mismo');
select is(pg_temp.r(pg_temp.u(404), format('core.request_role_permission_change(%L, ''cook'', ''org.manage'', true, ''Prueba'')', pg_temp.u(1))),
  'denied', 'el gerente no cambia la matriz');

-- ---------------------------------------------------------------------------
-- M7: aprobaciones
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from workflow.approval_requests'), '0', 'el cocinero no ve solicitudes ajenas');
-- Solo las solicitudes de esta prueba (created_at = hora de esta transacción): la base local puede traer otras.
select is(pg_temp.q(pg_temp.u(402), 'select count(*)::text from workflow.approval_requests where created_at = now()'), '4', 'Dirección General ve todas las solicitudes del grupo');
select is(pg_temp.q(pg_temp.u(403), 'select count(*)::text from workflow.approval_requests where created_at = now()'), '1', 'el director ve las solicitudes de su marca');

-- A2: no se aprueba la propia solicitud
select is(pg_temp.r(pg_temp.u(403), format('workflow.decide_approval(%L, ''approved'', ''La apruebo yo'')', pg_temp.req('executive_chef', '22222222-2222-2222-2222-222222222222'))),
  'denied', 'A2. el director no aprueba su propia solicitud');
select ok(exists (select 1 from audit.authentication_security_events where actor_id = pg_temp.u(403) and operation = 'workflow.decide_approval'),
  'A2. el intento de autoaprobación quedó registrado');
select is(pg_temp.r(pg_temp.u(409), format('workflow.decide_approval(%L, ''approved'', null)', pg_temp.req('executive_chef', '22222222-2222-2222-2222-222222222222'))),
  'denied', 'el cocinero no decide aprobaciones');
-- Un rol sensible lo aprueba Dirección o el Director de Marca de ese lugar, no la Chef (ADR-0017, pregunta 4).
select is(pg_temp.r(pg_temp.u(405), format('workflow.decide_approval(%L, ''approved'', ''Conozco a la persona'')', pg_temp.req('executive_chef', '22222222-2222-2222-2222-222222222222')))
          || '/' || pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', ''Conozco a la persona'')', pg_temp.req('executive_chef', '22222222-2222-2222-2222-222222222222'))),
  'denied/approved', 'la chef ya no aprueba un rol sensible; otra persona que puede decidir (Dirección) sí');
select ok(exists (select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id
                   where a.user_id = '22222222-2222-2222-2222-222222222222' and r.code = 'executive_chef'
                     and a.brand_id = pg_temp.u(101) and a.deleted_at is null and a.created_by = pg_temp.u(402)),
  'al aprobarse, el rol se aplicó en la misma transacción');
select ok(
  (select d.decided_by = pg_temp.u(402) and d.decision = 'approved' and d.decided_at is not null and d.comment = 'Conozco a la persona'
          and r.status = 'approved' and r.resolved_by = pg_temp.u(402) and r.resolved_at is not null
     from workflow.approval_decisions d join workflow.approval_requests r on r.id = d.request_id
    where r.subject_user_id = '22222222-2222-2222-2222-222222222222'),
  '12. la aprobación guarda identidad, fecha, decisión y comentario');
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''approved'', null)',
            (select id from workflow.approval_requests where subject_user_id = '22222222-2222-2222-2222-222222222222'))),
  'already_resolved', 'una solicitud resuelta no se vuelve a decidir');

select is(pg_temp.r(pg_temp.u(407), format('workflow.decide_approval(%L, ''approved'', null)', pg_temp.req('superadmin', '11111111-1111-1111-1111-111111111111'))),
  'denied', 'Controller (aprueba precios) no aprueba un superadmin: hace falta Dirección General');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', ''Reemplazo de vacaciones'')', pg_temp.req('superadmin', '11111111-1111-1111-1111-111111111111'))),
  'approved', 'Dirección General aprueba el nuevo superadmin');
select ok(exists (select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id
                   where a.user_id = '11111111-1111-1111-1111-111111111111' and r.code = 'superadmin' and a.deleted_at is null),
  'el nuevo superadmin quedó asignado');

-- 11: un rechazo queda registrado
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''rejected'', ''No corresponde'')', pg_temp.req('general_management', '11111111-1111-1111-1111-111111111111'))),
  'rejected', 'la segunda persona de Dirección rechaza el pedido');
select ok(
  (select r.status = 'rejected' and d.decision = 'rejected' and d.decided_by = pg_temp.u(412) and d.comment = 'No corresponde'
     from workflow.approval_requests r join workflow.approval_decisions d on d.request_id = r.id
    where r.subject_user_id = '11111111-1111-1111-1111-111111111111' and r.proposed_changes ->> 'role_code' = 'general_management'),
  '11. la solicitud rechazada queda registrada con quién, cuándo y por qué');
select ok(not exists (select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id
                       where a.user_id = '11111111-1111-1111-1111-111111111111' and r.code = 'general_management'),
  'lo rechazado no se aplica');

-- Matriz aprobada
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)',
            (select id from workflow.approval_requests where proposed_changes ->> 'permission_code' = 'approvals.view'))),
  'approved', 'Dirección General aprueba el cambio de la matriz');
select ok(exists (select 1 from core.role_permissions rp join core.roles r on r.id = rp.role_id join core.permissions p on p.id = rp.permission_id
                   where r.code = 'cook' and p.code = 'approvals.view' and rp.deleted_at is null),
  'el cambio de la matriz quedó aplicado');

-- Traspaso de local (ADR-0007)
select is(pg_temp.r(pg_temp.u(404), format('org.request_transfer(%L, %L, null, ''Prueba'')', pg_temp.u(202), pg_temp.u(102))),
  'denied', 'el gerente no pide traspasos');
select is(pg_temp.r(pg_temp.u(401), format('org.request_transfer(%L, %L, ''Demo Parrilla Norte'', ''Cambio de concepto'')', pg_temp.u(202), pg_temp.u(102))),
  'pending_approval', 'el superadmin pide traspasar un local: queda pendiente');
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''approved'', null)',
            (select r.id from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'org.transfer_restaurant'))),
  'approved', 'Dirección General aprueba el traspaso');
select ok(
  (select n.brand_id = pg_temp.u(102) and n.name = 'Demo Parrilla Norte' and o.status = 'inactive' and o.deleted_at is null
     from org.restaurants n join org.restaurants o on o.id = n.predecessor_id
    where n.predecessor_id = pg_temp.u(202)),
  'el traspaso creó el local nuevo en la otra marca y cerró el viejo, que sigue en la historia');
select is((select count(*)::int from org.areas a join org.restaurants n on n.id = a.restaurant_id where n.predecessor_id = pg_temp.u(202)),
  3, 'el local nuevo tiene las mismas áreas');
select ok(
  exists (select 1 from core.user_role_assignments a join org.restaurants n on n.id = a.restaurant_id
           where n.predecessor_id = pg_temp.u(202) and a.user_id = pg_temp.u(411) and a.deleted_at is null)
  and not exists (select 1 from core.user_role_assignments where restaurant_id = pg_temp.u(202) and deleted_at is null),
  'los roles pasaron al local nuevo y se quitaron del viejo');

-- Lo que se aprueba es lo que se aplica: solicitudes y decisiones no se tocan
select throws_ok($$update workflow.approval_requests set proposed_changes = '{"user_id": "x"}' where status = 'pending'$$
                 || ' or status = ''approved''', '42501', null, 'lo que pide una solicitud no cambia');
select throws_ok($$update workflow.approval_requests set status = 'pending', resolved_at = null where status = 'approved'$$,
  '42501', null, 'una solicitud resuelta no vuelve a pendiente');
select throws_ok($$update workflow.approval_decisions set decision = 'rejected'$$, '42501', null, 'una decisión no se cambia');
select throws_ok($$delete from workflow.approval_decisions$$, '42501', null, 'una decisión no se borra');

-- Retirar una solicitud
select is(pg_temp.assign(pg_temp.u(401), '22222222-2222-2222-2222-222222222222', 'controller', 'group', null, null), 'pending_approval',
  'el superadmin pide Controller para otra persona');
select is(pg_temp.r(pg_temp.u(409), format('workflow.cancel_request(%L, ''Prueba'')', pg_temp.req('controller', '22222222-2222-2222-2222-222222222222'))),
  'denied', 'solo quien pidió puede retirar la solicitud');
select is(pg_temp.r(pg_temp.u(401), format('workflow.cancel_request(%L, ''Me equivoqué de persona'')', pg_temp.req('controller', '22222222-2222-2222-2222-222222222222'))),
  'cancelled', 'quien pidió la retira');

-- ---------------------------------------------------------------------------
-- Revisión de seguridad de M6 y M7 (hallazgos G1, G2, M1, M2 y M4)
-- ---------------------------------------------------------------------------
-- G1: lo que pide el superadmin con su excepción lo aprueba SOLO Dirección General.
select is(pg_temp.assign(pg_temp.u(401), '22222222-2222-2222-2222-222222222222', 'brand_director', 'brand', 101, null), 'pending_approval',
  'G1. el superadmin pide Director de Marca (tiene permisos que él no tiene): queda pendiente');
select is((select w.code from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
            where r.id = pg_temp.req('brand_director', '22222222-2222-2222-2222-222222222222')),
  'core.assign_by_superadmin', 'G1. usa la aprobación de Dirección General');
select is(pg_temp.r(pg_temp.u(405), format('workflow.decide_approval(%L, ''approved'', null)', pg_temp.req('brand_director', '22222222-2222-2222-2222-222222222222')))
          || '/' || pg_temp.r(pg_temp.u(407), format('workflow.decide_approval(%L, ''approved'', null)', pg_temp.req('brand_director', '22222222-2222-2222-2222-222222222222')))
          || '/' || pg_temp.r(pg_temp.u(403), format('workflow.decide_approval(%L, ''approved'', null)', pg_temp.req('brand_director', '22222222-2222-2222-2222-222222222222'))),
  'denied/denied/denied', 'G1. ni el chef ejecutivo, ni Controller, ni el director de marca lo aprueban');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)', pg_temp.req('brand_director', '22222222-2222-2222-2222-222222222222'))),
  'approved', 'G1. Dirección General sí lo aprueba');

-- Separación de funciones por persona: quien administra la seguridad no suma un rol que aprueba.
select is(pg_temp.assign(pg_temp.u(401), '11111111-1111-1111-1111-111111111111', 'controller', 'group', null, null), 'ERROR 23514',
  'una persona superadmin no puede sumar un rol que aprueba cambios (separación de funciones)');

-- M1: Superadministrador y Dirección General solo para todo el grupo.
select is(pg_temp.assign(pg_temp.u(401), '22222222-2222-2222-2222-222222222222', 'general_management', 'restaurant', 101, 201), 'ERROR 23514',
  'M1. Dirección General no se da para un solo local');
select is(pg_temp.assign(pg_temp.u(401), '22222222-2222-2222-2222-222222222222', 'superadmin', 'brand', 101, null), 'ERROR 23514',
  'M1. Superadministrador no se da para una sola marca');

-- M2: separación de funciones en la matriz y quien tiene el rol no aprueba el cambio.
select is(pg_temp.r(pg_temp.u(401), format('core.request_role_permission_change(%L, ''general_management'', ''roles.manage'', true, ''Prueba'')', pg_temp.u(1))),
  'ERROR 23514', 'M2. un rol que aprueba no puede administrar la seguridad técnica');
select is(pg_temp.r(pg_temp.u(401), format('core.request_role_permission_change(%L, ''general_management'', ''approvals.decide'', false, ''Prueba'')', pg_temp.u(1))),
  'ERROR 23514', 'M2. no se le puede quitar approvals.decide a Dirección General');
select ok((select r.proposed_changes -> 'excluded_approvers' @> to_jsonb(pg_temp.u(409)::text)
             from workflow.approval_requests r where r.proposed_changes ->> 'permission_code' = 'approvals.view'),
  'M2. quienes tienen el rol que se cambia quedan excluidos de aprobarlo');

-- M4: al aplicar se vuelve a validar (quien pidió perdió el permiso).
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role) values
  ('44444444-4444-4444-4444-444444444444', 'nueva4@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id) values ('44444444-4444-4444-4444-444444444444', pg_temp.u(1));
select is(pg_temp.assign(pg_temp.u(403), '44444444-4444-4444-4444-444444444444', 'executive_chef', 'brand', 101, null), 'pending_approval',
  'M4. el director pide Chef Ejecutivo');
update core.user_role_assignments set deleted_at = now() where user_id = pg_temp.u(403);
select is(pg_temp.q(pg_temp.u(402), format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''', pg_temp.req('executive_chef', '44444444-4444-4444-4444-444444444444'))),
  'ERROR 23514', 'M4. si quien pidió ya no tiene permiso, la aprobación no se aplica');
select is((select status::text from workflow.approval_requests where id = pg_temp.req('executive_chef', '44444444-4444-4444-4444-444444444444')),
  'pending', 'M4. la solicitud sigue pendiente (no quedó aprobada a medias)');

-- G2: el superadmin no le quita roles a Dirección General sin aprobación, y nunca deja al grupo sin ella.
select is(pg_temp.r(pg_temp.u(401), format('core.revoke_role(%L, ''Cambio de puesto'')',
            (select id from core.user_role_assignments where user_id = pg_temp.u(402) and deleted_at is null))),
  'pending_approval', 'G2. el superadmin pide quitar Dirección General: queda pendiente');
select ok(exists (select 1 from core.user_role_assignments where user_id = pg_temp.u(402) and deleted_at is null),
  'G2. mientras tanto, la persona conserva su rol');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)',
            (select r.id from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'core.revoke_by_superadmin' and r.status = 'pending'))),
  'denied', 'G2. la persona afectada no aprueba que le quiten el rol');
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''approved'', null)',
            (select r.id from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'core.revoke_by_superadmin' and r.status = 'pending'))),
  'approved', 'G2. otra persona de Dirección General lo aprueba');
select is(pg_temp.r(pg_temp.u(401), format('core.revoke_role(%L, ''Prueba'')',
            (select id from core.user_role_assignments where user_id = pg_temp.u(412) and deleted_at is null))),
  'denied', 'G2. no se puede quitar a la última persona de Dirección General del grupo');

-- ---------------------------------------------------------------------------
-- Versiones con una tabla de prueba de recetas (pruebas 2, 3 y 7)
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de prueba de recetas', 'maintenance');
  insert into core.permissions (code, module, name, description) values
    ('test_recipes.view', 'test_recipes', 'Prueba: ver', 'Prueba: ver recetas vigentes.'),
    ('test_recipes.edit', 'test_recipes', 'Prueba: editar', 'Prueba: crear borradores y pedir revisión.'),
    ('test_recipes.publish', 'test_recipes', 'Prueba: publicar', 'Prueba: aprobar y publicar recetas.'),
    ('test_recipes.view_costs', 'test_recipes', 'Prueba: costos', 'Prueba: ver costos.');
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id from (values
      ('cook', 'test_recipes.view'), ('head_chef', 'test_recipes.view'), ('head_chef', 'test_recipes.edit'),
      ('executive_chef', 'test_recipes.view'), ('executive_chef', 'test_recipes.edit'), ('executive_chef', 'test_recipes.publish'),
      ('executive_chef', 'test_recipes.view_costs')) as m (rc, pc)
    join core.roles r on r.code = m.rc join core.permissions p on p.code = m.pc;
end
$$;

create table public.test_recipes (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null,
  restaurant_id uuid not null,
  name          text not null,
  status        core.version_status not null default 'draft',
  created_at timestamptz not null default now(), created_by uuid, updated_at timestamptz not null default now(),
  updated_by uuid, deleted_at timestamptz, deleted_by uuid
);
create trigger set_control_columns before insert or update on public.test_recipes
  for each row execute function core.set_control_columns();
create trigger enforce_version_rules before insert or update or delete on public.test_recipes
  for each row execute function core.enforce_version_rules();
create trigger log_change after insert or update or delete on public.test_recipes
  for each row execute function audit.log_change();
alter table public.test_recipes enable row level security;
grant select, insert, update on public.test_recipes to authenticated;
create policy test_recipes_select on public.test_recipes for select to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('test_recipes.view'))
         and (status = 'published' or restaurant_id in (select core.permitted_restaurant_ids('test_recipes.edit'))));
create policy test_recipes_insert on public.test_recipes for insert to authenticated
  with check (status = 'draft' and restaurant_id in (select core.permitted_restaurant_ids('test_recipes.edit')));
create policy test_recipes_update on public.test_recipes for update to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('test_recipes.edit')))
  with check (status in ('draft', 'in_review') or restaurant_id in (select core.permitted_restaurant_ids('test_recipes.publish')));

create table public.test_recipe_costs (
  recipe_id uuid not null, restaurant_id uuid not null, food_cost numeric(14, 4) not null, currency text not null default 'ARS'
);
alter table public.test_recipe_costs enable row level security;
grant select on public.test_recipe_costs to authenticated;
create policy test_recipe_costs_select on public.test_recipe_costs for select to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('test_recipes.view_costs')));

-- 3: el jefe de cocina crea un borrador, pide revisión, pero no publica
select is(pg_temp.q(pg_temp.u(406), format($$insert into public.test_recipes (id, group_id, restaurant_id, name) values ('aaaaaaaa-0000-4000-8000-000000000001', %L, %L, 'Ñoquis') returning 'ok'$$, pg_temp.u(1), pg_temp.u(201))),
  'ok', '3. el jefe de cocina crea un borrador');
select is(pg_temp.q(pg_temp.u(406), $$update public.test_recipes set status = 'in_review' where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$),
  'ok', '3. el jefe de cocina pide revisión');
select is(pg_temp.q(pg_temp.u(406), $$update public.test_recipes set status = 'approved' where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$),
  'ERROR 42501', '3. el jefe de cocina no aprueba ni publica sin permiso');
select is(pg_temp.q(pg_temp.u(406), $$insert into public.test_recipes (group_id, restaurant_id, name, status) values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000201', 'Atajo', 'published') returning 'ok'$$),
  'ERROR 42501', '3. el jefe de cocina no crea una receta ya publicada');
select is(pg_temp.q(pg_temp.u(405), $$update public.test_recipes set status = 'approved' where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$)
          || '/' || pg_temp.q(pg_temp.u(405), $$update public.test_recipes set status = 'published' where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$),
  'ok/ok', 'el chef ejecutivo aprueba y publica');

-- 7: una versión aprobada conserva su historia
select is(pg_temp.q(pg_temp.u(405), $$update public.test_recipes set name = 'Ñoquis de papa' where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$),
  'ERROR 42501', '7. una versión publicada no se modifica: se crea otra');
select is(pg_temp.q(pg_temp.u(405), $$update public.test_recipes set status = 'draft' where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$),
  'ERROR 42501', '7. una versión publicada no vuelve a borrador');
select is(pg_temp.q(pg_temp.u(405), $$delete from public.test_recipes where id = 'aaaaaaaa-0000-4000-8000-000000000001' returning 'ok'$$),
  'ERROR 42501', '7. una versión no se borra');
select is(
  (select array_agg(coalesce(new_values ->> 'status', '') order by sequence_number)
     from audit.audit_events where table_name = 'test_recipes' and record_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  array['draft', 'in_review', 'approved', 'published'],
  '7. el historial guarda cada paso de la versión, con quién lo hizo'
);

-- 2: el cocinero abre la receta vigente pero no ve costos
insert into public.test_recipes (group_id, restaurant_id, name) values (pg_temp.u(1), pg_temp.u(201), 'Borrador secreto');
insert into public.test_recipe_costs (recipe_id, restaurant_id, food_cost) values ('aaaaaaaa-0000-4000-8000-000000000001', pg_temp.u(201), 1234.5600);
select is(pg_temp.q(pg_temp.u(409), 'select string_agg(name, '','') from public.test_recipes'), 'Ñoquis',
  '2. el cocinero ve solo la receta publicada de su local');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from public.test_recipe_costs'), '0', '2. el cocinero no ve costos');
select is(pg_temp.q(pg_temp.u(405), 'select count(*)::text from public.test_recipe_costs'), '1', 'el chef ejecutivo sí ve los costos');

-- ---------------------------------------------------------------------------
-- Registro de seguridad: inalterable y fuera de la API
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(401), 'select count(*)::text from audit.authentication_security_events'), 'ERROR 42501', 'el registro de seguridad no se lee por la API');
select throws_ok($$update audit.authentication_security_events set reason = 'x'$$, '42501', null, 'el registro de seguridad no se modifica');
select throws_ok($$delete from audit.authentication_security_events$$, '42501', null, 'el registro de seguridad no se borra');
-- Sellar y verificar solo lo puede hacer audit_owner, que no ve pgTAP: el resultado pasa por una tabla temporal.
create temporary table seal_check (sealed int, valid boolean);
grant insert, update on seal_check to audit_owner;
set local role audit_owner;
insert into seal_check (sealed) select (audit.seal_security_events(interval '-1 minute')).event_count;
update seal_check set valid = (select bool_and(is_valid) from audit.verify_security_seals());
reset role;
select ok((select sealed > 0 from seal_check), 'el registro de seguridad se sella');
select ok((select valid from seal_check), 'los sellos del registro de seguridad verifican');

-- ---------------------------------------------------------------------------
-- A9: prueba de catálogo (recorre la base)
-- ---------------------------------------------------------------------------
create function pg_temp.business_schemas() returns text[] language sql as $$
  select array['core', 'org', 'audit', 'workflow', 'catalog', 'recipes', 'costing', 'purchasing',
               'inventory', 'production', 'ai', 'reporting', 'imports', 'integration']
$$;
select is(
  (select array_agg(n.nspname || '.' || c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = any (pg_temp.business_schemas()) and c.relkind in ('r', 'p') and not c.relrowsecurity),
  null, 'A9. todas las tablas de los 12 esquemas tienen RLS activo'
);
select is(
  (select array_agg(n.nspname || '.' || c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = any (pg_temp.business_schemas()) and c.relkind in ('r', 'p')
      and has_table_privilege('authenticated', c.oid, 'select')
      and not exists (select 1 from pg_policies p where p.schemaname = n.nspname and p.tablename = c.relname
                        and p.cmd in ('SELECT', 'ALL') and ('authenticated' = any (p.roles) or 'public' = any (p.roles)))),
  null, 'A9. toda tabla que authenticated puede leer tiene su política de lectura'
);
select is(
  (select array_agg(n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = any (pg_temp.business_schemas()) and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) as c where c like 'search_path=%')),
  null, 'A9. toda función security definer fija su search_path'
);
select is(
  (select array_agg(n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = any (pg_temp.business_schemas()) and has_function_privilege('public', p.oid, 'execute')),
  null, 'A9. ninguna función de negocio es ejecutable por cualquiera (PUBLIC)'
);
select is(
  (select array_agg(schemaname || '.' || policyname) from pg_policies
    where (coalesce(qual, '') || coalesce(with_check, '')) like '%has_permission_anywhere%'),
  null, 'A9. ninguna política usa has_permission_anywhere'
);
select is(
  (select array_agg(n.nspname || '.' || c.relname || coalesce('.' || a.attname, ''))
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
     left join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    where n.nspname = any (pg_temp.business_schemas()) and c.relkind in ('r', 'p')
      and (obj_description(c.oid, 'pg_class') is null or (a.attnum is not null and col_description(c.oid, a.attnum) is null))),
  null, 'A9. todas las tablas y columnas de negocio tienen comentario en español'
);

select * from finish();
rollback;
