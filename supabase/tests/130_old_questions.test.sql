-- Fase 1 · Las 6 preguntas pendientes de docs/estado.md, respondidas por Joaco (ADR-0017):
--   1. quitarle el rol a otro superadmin lo aprueba Dirección; 2. una unidad cerrada no da permisos;
--   3. baja y reactivación de Dirección con aprobación de otra persona de Dirección;
--   4. un rol sensible lo aprueba Dirección o el Director de Marca; 5. reactivación por alcance.
-- Personas del seed: ver 050_permissions.
begin;
create extension if not exists pgtap with schema extensions;

select plan(50);

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
create function pg_temp.r(p_user uuid, p_call text) returns text language sql as $$
  select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call))
$$;
-- La solicitud pendiente de un tipo sobre una persona.
create function pg_temp.req(p_code text, p_user uuid) returns uuid language sql as $$
  select r.id from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
   where w.code = p_code and r.subject_user_id = p_user and r.status = 'pending'
   order by r.created_at desc limit 1
$$;
-- Una persona nueva del grupo, con un rol.
create function pg_temp.person(p_id uuid, p_email text, p_role text, p_scope core.scope_type,
                               p_brand int default null, p_restaurant int default null)
returns uuid
language plpgsql
as $$
begin
  insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
  values (p_id, p_email, '{}', '{}', 'authenticated', 'authenticated');
  insert into core.user_memberships (user_id, group_id) values (p_id, pg_temp.u(1));
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
  select p_id, id, p_scope, pg_temp.u(1),
         case when p_brand is not null then pg_temp.u(p_brand) end,
         case when p_restaurant is not null then pg_temp.u(p_restaurant) end
    from core.roles where code = p_role;
  return p_id;
end
$$;
create function pg_temp.assignment(p_user uuid, p_role text) returns uuid language sql as $$
  select a.id from core.user_role_assignments a join core.roles r on r.id = a.role_id
   where a.user_id = p_user and r.code = p_role and a.deleted_at is null
$$;

-- ---------------------------------------------------------------------------
-- 1. Quitarle el rol a otro Superadministrador lo aprueba Dirección
-- ---------------------------------------------------------------------------
select pg_temp.person('99999999-0000-4000-8000-000000000001', 'super2@ejemplo.test', 'superadmin', 'group');
select pg_temp.person('99999999-0000-4000-8000-000000000002', 'super3@ejemplo.test', 'superadmin', 'group');
select is(pg_temp.r('99999999-0000-4000-8000-000000000001', format('core.revoke_role(%L, ''Dejo el puesto'')',
            pg_temp.assignment('99999999-0000-4000-8000-000000000001', 'superadmin'))),
  'applied', '1. un superadmin se quita su propio rol sin aprobación (quedan otros)');
select is(pg_temp.r(pg_temp.u(401), format('core.revoke_role(%L, ''Cambio de puesto'')',
            pg_temp.assignment('99999999-0000-4000-8000-000000000002', 'superadmin'))),
  'pending_approval', '1. quitarle el rol a otro superadmin queda pendiente');
select ok(pg_temp.assignment('99999999-0000-4000-8000-000000000002', 'superadmin') is not null,
  '1. mientras tanto, conserva el rol');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', ''De acuerdo'')',
            pg_temp.req('core.revoke_by_superadmin', '99999999-0000-4000-8000-000000000002'))),
  'approved', '1. Dirección lo aprueba');
select ok(pg_temp.assignment('99999999-0000-4000-8000-000000000002', 'superadmin') is null,
  '1. y el rol se quita');
select is(pg_temp.r(pg_temp.u(401), format('core.revoke_role(%L, ''Me voy'')', pg_temp.assignment(pg_temp.u(401), 'superadmin'))),
  'denied', '1. el último superadmin no se puede quitar el rol');
select pg_temp.person('99999999-0000-4000-8000-000000000004', 'super4@ejemplo.test', 'superadmin', 'group');
select is(pg_temp.r(pg_temp.u(401), format('core.suspend_user(%L, ''Licencia'')', '99999999-0000-4000-8000-000000000004'))
          || '/' || (select status::text from core.user_profiles where id = '99999999-0000-4000-8000-000000000004'),
  'pending_approval/active', '1. suspender a otro superadmin tampoco es al instante: queda pendiente');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.change_superadmin_status', '99999999-0000-4000-8000-000000000004'))),
  'approved', '1. Dirección lo aprueba');
-- El estado se lee en otra sentencia: la misma sentencia todavía ve el estado de antes.
select is((select status::text from core.user_profiles where id = '99999999-0000-4000-8000-000000000004')
          || '/' || pg_temp.r(pg_temp.u(401), format('core.lift_suspension(%L, ''Volvió'')', '99999999-0000-4000-8000-000000000004'))
          || '/' || pg_temp.r(pg_temp.u(401), format('core.disable_user(%L, ''Se va'')', '99999999-0000-4000-8000-000000000004')),
  'suspended/applied/pending_approval', '1. la cuenta quedó suspendida; levantarla sigue sin aprobación; dar de baja a otro superadmin queda pendiente');

-- ---------------------------------------------------------------------------
-- 2. Un local o una marca cerrados no dan permisos
-- ---------------------------------------------------------------------------
-- La gerente de dos locales (411) tiene Demo Pastas Centro (201) y Demo Pastas Norte (202).
select is(pg_temp.q(pg_temp.u(411), $$select core.has_permission('users.view', '00000000-0000-4000-8000-000000000202')::text$$),
  'true', '2. con el local abierto, el rol vale');
update org.restaurants set status = 'inactive' where id = pg_temp.u(202);
select is(pg_temp.q(pg_temp.u(411), $$select core.has_permission('users.view', '00000000-0000-4000-8000-000000000202')::text$$)
          || '/' || pg_temp.q(pg_temp.u(411), $$select core.has_permission('users.view', '00000000-0000-4000-8000-000000000201')::text$$),
  'false/true', '2. con el local cerrado, su rol de ese local deja de valer, y el del otro local sigue');
select is(pg_temp.q(pg_temp.u(411), $$select (('00000000-0000-4000-8000-000000000202')::uuid = any (array(select core.permitted_restaurant_ids('users.view'))))::text$$),
  'false', '2. el local cerrado no aparece entre sus locales');
select ok(not core.user_has_role_for_scope(pg_temp.u(411), array['restaurant_manager'], 'restaurant', pg_temp.u(1), pg_temp.u(101), pg_temp.u(202)),
  '2. ni cuenta como gerente de ese local (por ejemplo, para aprobar)');
select is(pg_temp.q(pg_temp.u(402), $$select (('00000000-0000-4000-8000-000000000202')::uuid = any (array(select core.permitted_restaurant_ids('audit.view'))))::text$$)
          || '/' || pg_temp.q(pg_temp.u(403), $$select (('00000000-0000-4000-8000-000000000202')::uuid = any (array(select core.permitted_restaurant_ids('users.view'))))::text$$),
  'true/true', '2. Dirección (rol de grupo) y la directora de la marca siguen viendo el local cerrado y su historia');
update org.restaurants set status = 'active' where id = pg_temp.u(202);
select is(pg_temp.q(pg_temp.u(411), $$select core.has_permission('users.view', '00000000-0000-4000-8000-000000000202')::text$$),
  'true', '2. si el local se reabre, el rol vuelve a valer');
-- Para borrar un local, primero se borran sus áreas.
update org.areas set deleted_at = now() where restaurant_id = pg_temp.u(202) and deleted_at is null;
update org.restaurants set deleted_at = now() where id = pg_temp.u(202);
select is(pg_temp.q(pg_temp.u(411), $$select core.has_permission('users.view', '00000000-0000-4000-8000-000000000202')::text$$),
  'false', '2. un local borrado tampoco da permisos');
update org.restaurants set deleted_at = null where id = pg_temp.u(202);
update org.areas set deleted_at = null where restaurant_id = pg_temp.u(202);
-- Una marca cerrada corta los roles de la marca y de sus locales.
update org.brands set status = 'inactive' where id = pg_temp.u(101);
select is(pg_temp.q(pg_temp.u(403), $$select core.has_permission_in_brand('users.view', '00000000-0000-4000-8000-000000000101')::text$$)
          || '/' || pg_temp.q(pg_temp.u(404), $$select core.has_permission('users.view', '00000000-0000-4000-8000-000000000201')::text$$),
  'false/false', '2. con la marca cerrada, ni la directora ni el gerente de un local de esa marca tienen permisos ahí');
update org.brands set status = 'active' where id = pg_temp.u(101);

-- ---------------------------------------------------------------------------
-- 3. Baja y reactivación de Dirección General, con aprobación de otra persona de Dirección
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(403), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(402))),
  'denied', '3. la directora de marca no da de baja a Dirección');
select is(pg_temp.r(pg_temp.u(401), format('core.disable_user(%L, ''Se retira'')', pg_temp.u(402))),
  'pending_approval', '3. el superadmin pide la baja de una persona de Dirección: queda pendiente');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402))))
          || '/' || pg_temp.r(pg_temp.u(401), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402)))),
  'denied/denied', '3. no la decide la persona afectada ni quien la pidió');
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''approved'', ''Confirmado'')',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402)))),
  'approved', '3. otra persona de Dirección la aprueba');
select ok((select status = 'deactivated' and deactivated_by = pg_temp.u(401) and deactivation_reason = 'Se retira'
             from core.user_profiles where id = pg_temp.u(402)),
  '3. la cuenta queda desactivada, con quién la pidió y el motivo');
select ok(exists (select 1 from audit.authentication_security_events
                   where event_type = 'account_disabled' and user_id = pg_temp.u(402)
                     and operation = 'core.apply_governance_status'),
  '3. y queda en el registro de seguridad');
set local role audit_owner;
create temporary table gm_audit as
  select reason from audit.audit_events
   where table_name = 'user_profiles' and record_id = '00000000-0000-4000-8000-000000000402' and status = 'deactivated';
reset role;
select ok((select bool_or(reason like 'Se retira%') from gm_audit), '3. y en el historial, con el motivo');
select is(pg_temp.r(pg_temp.u(401), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(412))),
  'denied', '3. la última persona de Dirección activa no se da de baja');
select is(pg_temp.r(pg_temp.u(401), format('core.request_reactivation(%L, ''Vuelve'')', pg_temp.u(402))),
  'pending_approval', '3. la reactivación sigue el mismo camino');
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402)))),
  'approved', '3. otra persona de Dirección la aprueba');
select is((select status::text from core.user_profiles where id = pg_temp.u(402)), 'active', '3. y la cuenta vuelve a estar activa');
select is(pg_temp.r(pg_temp.u(412), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(402))),
  'denied', '3. con dos personas en Dirección, una no le pide la baja a la otra: no quedaría quién la apruebe');
select is(pg_temp.r(pg_temp.u(402), format('core.disable_user(%L, ''Me voy'')', pg_temp.u(402))),
  'denied', '3. nadie de Dirección pide su propia baja');
select pg_temp.person('99999999-0000-4000-8000-000000000010', 'direccion3@ejemplo.test', 'general_management', 'group');
select is(pg_temp.r(pg_temp.u(412), format('core.disable_user(%L, ''Prueba'')', pg_temp.u(402))),
  'pending_approval', '3. con una tercera persona en Dirección, sí se puede pedir');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''rejected'', ''No'')',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402))))
          || '/' || pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''rejected'', ''No'')',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402))))
          || '/' || pg_temp.r('99999999-0000-4000-8000-000000000010', format('workflow.decide_approval(%L, ''rejected'', ''No corresponde'')',
            pg_temp.req('core.change_general_management_status', pg_temp.u(402)))),
  'denied/denied/rejected', '3. y la decide la tercera: no la afectada ni quien la pidió');
select is(pg_temp.r(pg_temp.u(401), format('core.suspend_user(%L, ''Prueba'')', pg_temp.u(402))),
  'denied', '3. suspender a Dirección sigue como antes: el superadmin no puede');

-- ---------------------------------------------------------------------------
-- 4. Un rol sensible lo aprueba Dirección o el Director de Marca de ese lugar
-- ---------------------------------------------------------------------------
select pg_temp.person('99999999-0000-4000-8000-000000000003', 'nueva-chef@ejemplo.test', 'cook', 'restaurant', 101, 201);
select is(pg_temp.r(pg_temp.u(403), $$core.assign_role('99999999-0000-4000-8000-000000000003', 'executive_chef', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', p_reason => 'Segunda chef de la marca')$$),
  'pending_approval', '4. dar un rol que aprueba cosas queda pendiente');
select is(pg_temp.r(pg_temp.u(407), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000003')))
          || '/' || pg_temp.r(pg_temp.u(405), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000003'))),
  'denied/denied', '4. el Controller y la Chef ya no lo aprueban');
select ok(not exists (select 1 from core.notifications n
                       where n.request_id = pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000003')
                         and n.recipient_user_id in (pg_temp.u(405), pg_temp.u(407)))
          and exists (select 1 from core.notifications n
                       where n.request_id = pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000003')
                         and n.recipient_user_id = pg_temp.u(402)),
  '4. y el aviso le llega a Dirección, no a ellos');
select is(pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000003'))),
  'approved', '4. Dirección lo aprueba');
-- Otra directora en Demo Pastas (101) y un director en Demo Parrilla (102).
select pg_temp.person('99999999-0000-4000-8000-000000000005', 'directora-b@ejemplo.test', 'brand_director', 'brand', 101);
select pg_temp.person('99999999-0000-4000-8000-000000000006', 'director-parrilla@ejemplo.test', 'brand_director', 'brand', 102);
select pg_temp.person('99999999-0000-4000-8000-000000000007', 'otra-chef@ejemplo.test', 'cook', 'restaurant', 101, 201);
select is(pg_temp.r('99999999-0000-4000-8000-000000000005', $$core.assign_role('99999999-0000-4000-8000-000000000007', 'executive_chef', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', p_reason => 'Tercera chef')$$),
  'pending_approval', '4. otra directora de la marca pide un rol sensible');
select is(pg_temp.r('99999999-0000-4000-8000-000000000006', format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000007')))
          || '/' || pg_temp.r(pg_temp.u(403), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.assign_sensitive_role', '99999999-0000-4000-8000-000000000007'))),
  'denied/approved', '4. el director de otra marca no lo aprueba; la directora de esa marca, sí');
-- Un rol con un permiso que la directora no tiene (Controller ve costos): lo aprueba Dirección.
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id)
select '99999999-0000-4000-8000-000000000005', id, 'brand', pg_temp.u(1), pg_temp.u(101) from core.roles where code = 'controller';
select is(pg_temp.r('99999999-0000-4000-8000-000000000005', $$core.assign_role('99999999-0000-4000-8000-000000000003', 'controller', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', p_reason => 'Costos')$$),
  'pending_approval', '4. se pide el rol Controller en la marca');
create temporary table controller_request as
  select r.id from workflow.approval_requests r
   where r.subject_user_id = '99999999-0000-4000-8000-000000000003' and r.status = 'pending'
     and r.proposed_changes ->> 'role_code' = 'controller';
grant select on controller_request to authenticated;
select is(pg_temp.r(pg_temp.u(403), format('workflow.decide_approval(%L, ''approved'', null)', (select id from controller_request)))
          || '/' || pg_temp.r(pg_temp.u(402), format('workflow.decide_approval(%L, ''approved'', null)', (select id from controller_request))),
  'denied/approved', '4. la directora no aprueba un rol con permisos que ella no tiene; Dirección sí');

-- ---------------------------------------------------------------------------
-- 5. Quien aprueba una reactivación alcanza todos los roles de la persona
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(403), format('core.disable_user(%L, ''Licencia larga'')', pg_temp.u(405)))
          || '/' || pg_temp.r(pg_temp.u(403), format('core.request_reactivation(%L, ''Vuelve'')', pg_temp.u(405))),
  'applied/pending_approval', '5. la directora da de baja a la Chef (rol de marca) y pide reactivarla');
select is(pg_temp.r(pg_temp.u(404), format('workflow.decide_approval(%L, ''approved'', null)',
            pg_temp.req('core.reactivate_user', pg_temp.u(405)))),
  'denied', '5. el gerente de un local no aprueba la reactivación de alguien con un rol de toda la marca');

-- ---------------------------------------------------------------------------
-- Con más de un grupo (revisión de seguridad, M1) y los costos del historial
-- ---------------------------------------------------------------------------
insert into org.groups (id, name) values ('99999999-0000-4000-8000-0000000000a1', 'Grupo Dos de Prueba');
select pg_temp.person('99999999-0000-4000-8000-000000000008', 'dos-grupos@ejemplo.test', 'general_management', 'group');
insert into core.user_memberships (user_id, group_id) values ('99999999-0000-4000-8000-000000000008', '99999999-0000-4000-8000-0000000000a1');
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
select '99999999-0000-4000-8000-000000000008', id, 'group', '99999999-0000-4000-8000-0000000000a1' from core.roles where code = 'auditor';
select is(pg_temp.r(pg_temp.u(401), format('core.disable_user(%L, ''Prueba'')', '99999999-0000-4000-8000-000000000008')),
  'denied', 'con roles en dos grupos, la baja de alguien de Dirección no se pide desde un solo grupo');
set local role audit_owner;
insert into audit.audit_events (table_schema, table_name, record_id, action, old_values, new_values, scope_group_id, scope_brand_id)
values ('org', 'areas', '99999999-0000-4000-8000-0000000000c1', 'update', '{"cost": 10}', '{"cost": 12, "name": "Cocina"}',
        '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101');
reset role;
-- Desde la Fase 2 el Director de Marca ve los costos de su marca (recipes.view_costs, sección 17
-- del documento de Soy y ADR-0020). Sin ese permiso, el historial los sigue ocultando.
select is(pg_temp.q(pg_temp.u(403), $$select (new_values ->> 'cost') || '/' || (new_values ->> 'name')
                                        from core.audit_history(5, p_record_id => '99999999-0000-4000-8000-0000000000c1')$$),
  '12/Cocina', 'la directora ve los costos de su marca en el historial');
update core.role_permissions set deleted_at = now()
 where role_id = (select id from core.roles where code = 'brand_director')
   and permission_id = (select id from core.permissions where code = 'recipes.view_costs');
select is(pg_temp.q(pg_temp.u(403), $$select (new_values ->> 'cost') || '/' || (new_values ->> 'name')
                                        from core.audit_history(5, p_record_id => '99999999-0000-4000-8000-0000000000c1')$$),
  '[oculto]/Cocina', 'el historial sigue ocultando los costos a quien no los puede ver (y muestra el resto)');

-- ---------------------------------------------------------------------------
-- El rol Director de Marca solo se da para una marca (decisión de Joaco, 2026-10-23)
-- ---------------------------------------------------------------------------
select pg_temp.person('99999999-0000-4000-8000-000000000009', 'futuro-director@ejemplo.test', 'cook', 'restaurant', 101, 201);
select is(pg_temp.r(pg_temp.u(401), $$core.assign_role('99999999-0000-4000-8000-000000000009', 'brand_director', 'group',
            '00000000-0000-4000-8000-000000000001', p_reason => 'Director de todo')$$)
          || '/' || pg_temp.r(pg_temp.u(401), $$core.assign_role('99999999-0000-4000-8000-000000000009', 'brand_director', 'restaurant',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201',
            p_reason => 'Director de un local')$$),
  'ERROR 23514/ERROR 23514', 'el Director de Marca no se da para todo el grupo ni para un local');
select is(pg_temp.r(pg_temp.u(401), $$core.assign_role('99999999-0000-4000-8000-000000000009', 'brand_director', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', p_reason => 'Directora nueva')$$),
  'pending_approval', 'para una marca, sí (y queda pendiente de Dirección)');
select throws_ok($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
                   select '99999999-0000-4000-8000-000000000009', id, 'group', '00000000-0000-4000-8000-000000000001'
                     from core.roles where code = 'brand_director'$$,
  '23514', 'El rol Director de Marca solo se da para una marca.',
  'la base lo rechaza aunque no pase por la función');
select throws_ok($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id)
                   select '99999999-0000-4000-8000-000000000009', id, 'brand', '00000000-0000-4000-8000-000000000001',
                          '00000000-0000-4000-8000-000000000101'
                     from core.roles where code = 'general_management'$$,
  '23514', 'Ese rol solo se da para todo el grupo.',
  'y Dirección General solo para todo el grupo, también en la tabla');

select * from finish();
rollback;
