-- Fase 1 · Respuestas de Joaco a las preguntas abiertas (ADR-0015, 2026-10-22):
--   1. quien mandó a revisión no publica; 2. los datos de administración, solo para quien administra;
--   5. KPI comparados con hace 7 días; 9. el lugar de la membresía limita los roles.
-- Personas del seed: ver 050_permissions.
begin;
create extension if not exists pgtap with schema extensions;

select plan(36);

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
create function pg_temp.j(p_user uuid, p_sql text) returns jsonb language sql as $$
  select pg_temp.q(p_user, p_sql)::jsonb
$$;
-- El mensaje del error (para distinguir la regla nueva de otras validaciones con el mismo código).
create function pg_temp.e(p_user uuid, p_sql text)
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

-- ---------------------------------------------------------------------------
-- 9. El lugar de la membresía limita los roles
-- ---------------------------------------------------------------------------
-- Una persona nueva que trabaja en los dos locales de Demo Pastas (no en toda la marca ni el grupo).
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('88888888-8888-8888-8888-888888888881', 'dos-locales@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated'),
       ('88888888-8888-8888-8888-888888888882', 'marca@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id) values
  ('88888888-8888-8888-8888-888888888881', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201)),
  ('88888888-8888-8888-8888-888888888881', pg_temp.u(1), pg_temp.u(101), pg_temp.u(202)),
  ('88888888-8888-8888-8888-888888888882', pg_temp.u(1), pg_temp.u(101), null);

select is(pg_temp.r(pg_temp.u(404), $$core.assign_role('88888888-8888-8888-8888-888888888881', 'cook', 'restaurant',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201',
            p_reason => 'Entra a la cocina')$$),
  'applied', '9. con membresía de un local, se le da un rol de ese local');
select is(pg_temp.r(pg_temp.u(403), $$core.assign_role('88888888-8888-8888-8888-888888888881', 'cook', 'restaurant',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000203',
            p_reason => 'Otra marca')$$),
  'denied', '9. un rol en otra marca: sin permiso ahí, ni se mira la membresía');
-- Con un rol que la directora sí puede dar (Compras tiene permisos del catálogo que ella no
-- tiene, y eso se frena antes, por otra regla).
select is(pg_temp.e(pg_temp.u(403), $$select core.assign_role('88888888-8888-8888-8888-888888888881', 'head_chef', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101',
            p_reason => 'Jefe de cocina de la marca')$$),
  'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.', '9. con membresías de locales, no se le da un rol de toda la marca');
select is(pg_temp.e(pg_temp.u(401), $$select core.assign_role('88888888-8888-8888-8888-888888888881', 'auditor', 'group',
            '00000000-0000-4000-8000-000000000001', p_reason => 'Auditoría')$$),
  'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.', '9. ni un rol de todo el grupo');
select is(pg_temp.r(pg_temp.u(403), $$core.assign_role('88888888-8888-8888-8888-888888888882', 'cook', 'restaurant',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000202',
            p_reason => 'Cubre en Norte')$$),
  'applied', '9. con membresía de la marca, se le da un rol de un local de esa marca');
select is(pg_temp.e(pg_temp.u(401), $$select core.assign_role('88888888-8888-8888-8888-888888888882', 'auditor', 'group',
            '00000000-0000-4000-8000-000000000001', p_reason => 'Auditoría')$$),
  'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.', '9. con membresía de la marca, no se le da un rol de todo el grupo');

-- La regla vale también para cualquier escritura directa (trigger).
select throws_ok($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
                   select '88888888-8888-8888-8888-888888888881', id, 'restaurant', '00000000-0000-4000-8000-000000000001',
                          '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000203'
                     from core.roles where code = 'cook'$$,
  '23514', 'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.',
  '9. la base rechaza un rol fuera de sus membresías aunque no pase por la función');

-- Terminar una membresía que deja un rol sin cubrir.
select throws_ok($$update core.user_memberships set ends_at = now() + interval '1 hour'
                    where user_id = '88888888-8888-8888-8888-888888888881' and restaurant_id = '00000000-0000-4000-8000-000000000201'$$,
  '23514', 'No se puede terminar esta membresía: la persona tiene roles en ese lugar que quedarían sin membresía. Primero hay que quitarle esos roles.',
  '9. no se termina la membresía de un local donde la persona tiene un rol, aunque tenga otra membresía');
select lives_ok($$update core.user_memberships set ends_at = now() + interval '1 hour'
                   where user_id = '88888888-8888-8888-8888-888888888881' and restaurant_id = '00000000-0000-4000-8000-000000000202'$$,
  '9. sí se termina la de un local donde no tiene roles');
select lives_ok($$insert into core.user_memberships (user_id, group_id) values ('88888888-8888-8888-8888-888888888882', '00000000-0000-4000-8000-000000000001');
                  update core.user_memberships set ends_at = now() + interval '1 hour'
                   where user_id = '88888888-8888-8888-8888-888888888882' and brand_id = '00000000-0000-4000-8000-000000000101'$$,
  '9. y la de la marca, si una de todo el grupo cubre sus roles');

-- Una solicitud aprobada después de que la persona dejó de trabajar en ese lugar no se aplica.
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('88888888-8888-8888-8888-888888888883', 'se-va@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id, brand_id) values ('88888888-8888-8888-8888-888888888883', pg_temp.u(1), pg_temp.u(101));
select is(pg_temp.r(pg_temp.u(401), $$core.assign_role('88888888-8888-8888-8888-888888888883', 'executive_chef', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', p_reason => 'Nueva chef')$$),
  'pending_approval', '9. el rol sensible queda pendiente');
-- Mientras espera, pasa a trabajar solo en un local: sigue en el grupo, pero ya no en toda la marca.
insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
values ('88888888-8888-8888-8888-888888888883', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201));
update core.user_memberships set ends_at = now() + interval '1 minute'
 where user_id = '88888888-8888-8888-8888-888888888883' and restaurant_id is null;
select is(pg_temp.e(pg_temp.u(402), format('select workflow.decide_approval(%L, ''approved'', ''Ok'')',
            (select id from workflow.approval_requests where subject_user_id = '88888888-8888-8888-8888-888888888883'))),
  'La solicitud ya no se puede aplicar: la persona ya no trabaja en ese lugar. Hay que pedirla de nuevo.',
  '9. si mientras tanto dejó de trabajar en ese lugar, la aprobación no se aplica');

-- Borrar (lógicamente) la membresía que cubre un rol, tampoco (aunque tenga otra membresía vigente).
insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
values ('88888888-8888-8888-8888-888888888881', pg_temp.u(1), pg_temp.u(102), pg_temp.u(203));
select throws_ok($$update core.user_memberships set deleted_at = now()
                    where user_id = '88888888-8888-8888-8888-888888888881' and restaurant_id = '00000000-0000-4000-8000-000000000201'$$,
  '23514', 'No se puede terminar esta membresía: la persona tiene roles en ese lugar que quedarían sin membresía. Primero hay que quitarle esos roles.',
  '9. ni se borra la membresía que cubre un rol');

-- Un traspaso de local lleva la membresía al local nuevo (si no, el rol no podría pasar).
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role)
values ('88888888-8888-8888-8888-888888888884', 'norte@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
values ('88888888-8888-8888-8888-888888888884', pg_temp.u(1), pg_temp.u(101), pg_temp.u(202));
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
select '88888888-8888-8888-8888-888888888884', id, 'restaurant', pg_temp.u(1), pg_temp.u(101), pg_temp.u(202)
  from core.roles where code = 'cook';
select is(pg_temp.r(pg_temp.u(401), format('org.request_transfer(%L, %L, ''Demo Parrilla Norte'', ''Cambio de concepto'')', pg_temp.u(202), pg_temp.u(102))),
  'pending_approval', '9. se pide traspasar un local donde trabaja alguien solo con membresía de ese local');
select is(pg_temp.r(pg_temp.u(412), format('workflow.decide_approval(%L, ''approved'', null)',
            (select r.id from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'org.transfer_restaurant' and r.status = 'pending'))),
  'approved', '9. y Dirección lo aprueba: el traspaso se aplica');
select ok((select bool_and(m.ends_at is null) and count(*) = 1
             from core.user_memberships m join org.restaurants n on n.id = m.restaurant_id and n.predecessor_id = pg_temp.u(202)
            where m.user_id = '88888888-8888-8888-8888-888888888884' and m.deleted_at is null)
          and exists (select 1 from core.user_role_assignments a join org.restaurants n on n.id = a.restaurant_id
                       where n.predecessor_id = pg_temp.u(202) and a.user_id = '88888888-8888-8888-8888-888888888884' and a.deleted_at is null)
          and not exists (select 1 from core.user_memberships
                           where user_id = '88888888-8888-8888-8888-888888888884' and restaurant_id = pg_temp.u(202)
                             and ends_at is null and deleted_at is null),
  '9. la persona pasa al local nuevo con su rol y su membresía, y la del local viejo termina');

-- ---------------------------------------------------------------------------
-- 2. El último acceso, quién invitó y los motivos: solo quien administra
-- ---------------------------------------------------------------------------
update core.user_profiles set last_seen_at = now() - interval '1 hour', invited_by = pg_temp.u(404) where id = pg_temp.u(409);
select is((select string_agg(n::text || '=' || coalesce(pg_temp.j(pg_temp.u(n), format('select core.user_detail(%L)::text', pg_temp.u(409)))
                                                ->> 'last_seen_at' is not null, false)::text, ',' order by n)
             from unnest(array[401, 402, 403, 404, 409, 411]) as n),
  '401=true,402=true,403=true,404=true,409=true,411=true',
  '2. superadmin, Dirección, directora de marca, los gerentes de su local y la propia persona ven el último acceso');
update core.user_profiles set last_seen_at = now() - interval '2 hours' where id in (pg_temp.u(411), pg_temp.u(403));
select is(pg_temp.j(pg_temp.u(404), format('select core.user_detail(%L)::text', pg_temp.u(411))) ->> 'last_seen_at', null,
  '2. el gerente de un local no ve el último acceso de otra gerente que además tiene otro local (tiene que alcanzar todos sus roles)');
select is(pg_temp.j(pg_temp.u(404), format('select core.user_detail(%L)::text', pg_temp.u(403))) ->> 'last_seen_at', null,
  '2. ni el de su directora de marca');
-- Por la API, la tabla de personas no entrega esas columnas.
select is(pg_temp.q(pg_temp.u(410), 'select last_seen_at::text from core.user_profiles limit 1'), 'ERROR 42501',
  '2. el auditor no lee el último acceso directo de la tabla');
select is(pg_temp.q(pg_temp.u(410), format('select first_name from core.user_profiles where id = %L', pg_temp.u(409))), 'Lucía',
  '2. pero sí el nombre');
update core.user_profiles set last_restaurant_id = pg_temp.u(202) where id = pg_temp.u(411);
select is(pg_temp.q(pg_temp.u(411), 'select core.my_active_restaurant()::text'), pg_temp.u(202)::text,
  '2. el local elegido en el selector se lee con una función, solo el propio');
select is((select (d ->> 'last_seen_at') is null and (d ->> 'invited_by_name') is null and (d ->> 'activated_at') is null
                  and (d ->> 'can_view_admin_details')::boolean = false and d ->> 'status' = 'active'
             from pg_temp.j(pg_temp.u(410), format('select core.user_detail(%L)::text', pg_temp.u(409))) as d),
  true, '2. el auditor ve la ficha, pero sin último acceso, sin quién invitó y sin primer acceso');
select is(pg_temp.j(pg_temp.u(404), format('select core.user_detail(%L)::text', pg_temp.u(409))) ->> 'invited_by_name',
  'Gonzalo Gerente', '2. el gerente ve quién la invitó');
select is(pg_temp.q(pg_temp.u(410), format('select (last_seen_at is null)::text from core.users_dashboard(p_user_id => %L)', pg_temp.u(409)))
          || '/' || pg_temp.q(pg_temp.u(404), format('select (last_seen_at is null)::text from core.users_dashboard(p_user_id => %L)', pg_temp.u(409))),
  'true/false', '2. en la lista, el último acceso sale vacío para el auditor y lleno para el gerente');

-- ---------------------------------------------------------------------------
-- 5. KPI comparados con hace 7 días
-- ---------------------------------------------------------------------------
-- Historia armada: hace 10 días la cocinera estaba suspendida y el de compras, activo; y había una
-- solicitud pendiente que se pidió hace 10 días y sigue pendiente.
select is(pg_temp.r(pg_temp.u(403), $$core.assign_role('00000000-0000-4000-8000-000000000409', 'executive_chef', 'brand',
            '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', p_reason => 'Ascenso')$$),
  'pending_approval', '5. hay una solicitud pendiente');
alter table workflow.approval_requests disable trigger user;
update workflow.approval_requests set requested_at = now() - interval '10 days'
 where subject_user_id = pg_temp.u(409) and status = 'pending';
alter table workflow.approval_requests enable trigger user;
-- audit_owner no lee workflow: el id pasa por una tabla temporal.
create temporary table old_request as
  select id from workflow.approval_requests where subject_user_id = pg_temp.u(409) and status = 'pending';
grant select on old_request to audit_owner;
set local role audit_owner;
insert into audit.audit_events (occurred_at, table_schema, table_name, record_id, action, old_values, new_values, status)
values (now() - interval '10 days', 'core', 'user_profiles', '00000000-0000-4000-8000-000000000409', 'update',
        '{"status": "active"}', '{"status": "suspended"}', 'suspended'),
       (now() - interval '10 days', 'core', 'user_profiles', '00000000-0000-4000-8000-000000000408', 'update',
        '{"status": "suspended"}', '{"status": "active"}', 'active');
insert into audit.audit_events (occurred_at, table_schema, table_name, record_id, action, new_values, status)
select now() - interval '10 days', 'workflow', 'approval_requests', id, 'insert', '{"status": "pending"}', 'pending'
  from old_request;
reset role;
select is((select format('%s/%s/%s/%s', d ->> 'active_prev', d ->> 'suspended_prev', d ->> 'deactivated_prev', d ->> 'pending_prev')
             from pg_temp.j(pg_temp.u(402), 'select core.users_control_panel()::text') as d),
  '1/1/0/1', '5. el tablero trae el estado de hace 7 días según la auditoría (quien no existía no cuenta)');
select ok((select (d ->> 'active')::int > (d ->> 'active_prev')::int and (d ->> 'prev_as_of')::timestamptz <= now() - interval '7 days'
             from pg_temp.j(pg_temp.u(402), 'select core.users_control_panel()::text') as d),
  '5. y la fecha de comparación es de hace 7 días');

-- ---------------------------------------------------------------------------
-- 2. Los motivos de una suspensión o una baja
-- ---------------------------------------------------------------------------
select is(pg_temp.r(pg_temp.u(404), format('core.suspend_user(%L, ''Licencia por examen'')', pg_temp.u(409))), 'applied',
  '2. el gerente suspende a la cocinera');
select ok((select (d ->> 'suspension_reason') is null and (d ->> 'suspended_by_name') is null and d ->> 'status' = 'suspended'
             from pg_temp.j(pg_temp.u(410), format('select core.user_detail(%L)::text', pg_temp.u(409))) as d),
  '2. el auditor ve que está suspendida, pero no el motivo ni quién la suspendió');
select is(pg_temp.j(pg_temp.u(404), format('select core.user_detail(%L)::text', pg_temp.u(409))) ->> 'suspension_reason',
  'Licencia por examen', '2. el gerente ve el motivo');
select is(pg_temp.r(pg_temp.u(404), format('core.lift_suspension(%L, ''Volvió'')', pg_temp.u(409))), 'applied',
  '2. y levanta la suspensión');
select is(pg_temp.r(pg_temp.u(404), format('core.disable_user(%L, ''Dejó el local'')', pg_temp.u(409)))
          || '/' || pg_temp.r(pg_temp.u(404), format('core.request_reactivation(%L, ''Vuelve'')', pg_temp.u(409))),
  'applied/pending_approval', '2. el gerente la da de baja y después pide reactivarla');
select is(pg_temp.q(pg_temp.u(406), $$select coalesce((previous_values ? 'deactivation_reason')::text, 'sin antes')
                                        from workflow.inbox() where workflow_code = 'core.reactivate_user'$$),
  'false', '2. en la bandeja, el jefe de cocina (no administra ni decide) ve el pedido sin el motivo de la baja');
select is(pg_temp.q(pg_temp.u(402), $$select (previous_values ->> 'deactivation_reason')
                                        from workflow.inbox() where workflow_code = 'core.reactivate_user'$$),
  'Dejó el local', '2. Dirección, que la administra, ve el motivo');
select is(pg_temp.q(pg_temp.u(406), 'select count(previous_values)::text from workflow.approval_requests'), 'ERROR 42501',
  '2. y el antes de una solicitud no se lee directo de la tabla');

select * from finish();
rollback;
