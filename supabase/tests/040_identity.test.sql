-- Fase 1 · M4: perfiles, permisos, roles, matriz, membresías, asignaciones y cuentas técnicas.
-- Personas del seed: ...0401 superadmin … ...0410 auditor, ...0411 gerente de dos locales,
-- ...0499 cuenta técnica. Grupo ...001, marca Demo Pastas ...101, locales ...201 y ...202.
begin;
create extension if not exists pgtap with schema extensions;

select plan(78);

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('core', t, format('existe core.%s', t))
from unnest(array['user_profiles', 'permissions', 'roles', 'role_permissions',
                  'user_memberships', 'user_role_assignments', 'service_accounts']) as t;

select is(
  (select count(*)::int from unnest(array['user_profiles', 'permissions', 'roles', 'role_permissions',
          'user_memberships', 'user_role_assignments', 'service_accounts']) as t
    where not (select relrowsecurity from pg_class where oid = format('core.%I', t)::regclass)),
  0, 'las 7 tablas de identidad tienen RLS activado'
);
select is(
  (select count(*)::int
     from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'core' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
      and col_description(c.oid, a.attnum) is null),
  0, 'todas las columnas de core tienen comentario en español'
);
select is(
  (select count(*)::int from unnest(array['user_profiles', 'permissions', 'roles', 'role_permissions',
          'user_memberships', 'user_role_assignments', 'service_accounts']) as t
    where (select count(*) from pg_trigger g where g.tgrelid = format('core.%I', t)::regclass
            and g.tgname in ('set_control_columns', 'validate_identity', 'log_change', 'reject_truncate')
            and g.tgenabled = 'O') <> 4),
  0, 'las 7 tablas tienen sus 4 triggers activos'
);
select is(
  (select count(*)::int
     from unnest(array['user_profiles', 'permissions', 'roles', 'role_permissions',
                       'user_memberships', 'user_role_assignments', 'service_accounts']) as t
     cross join unnest(array['anon', 'authenticated', 'service_role']) as r
    where has_table_privilege(r, format('core.%I', t), 'insert,update,delete,truncate,references,trigger')
       or (has_table_privilege(r, format('core.%I', t), 'select')
           and not (r = 'authenticated' and t <> 'service_accounts'))),
  0, 'tablas de identidad: nadie escribe directo, solo authenticated lee y las cuentas técnicas siguen cerradas (M5)'
);

-- ---------------------------------------------------------------------------
-- Catálogo del Módulo Maestro
-- ---------------------------------------------------------------------------
select is((select count(*)::int from core.roles where deleted_at is null), 10, 'hay 10 roles');
-- Los del recetario (Fase 2) se fijan, uno por uno y rol por rol, en 140_catalog.
select is((select count(*)::int from core.permissions where deleted_at is null
             and module not in ('catalog', 'prices', 'yields', 'recipes', 'scenarios', 'imports', 'reports')), 18,
  'hay 18 permisos de la Fase 1 (los 14 de M4 más permissions.manage, security.view, org.archive y users.view_admin_details, ADR-0015)');
select is(
  (select array_agg(code order by level) from core.roles where requires_mfa),
  array['superadmin', 'general_management', 'brand_director', 'restaurant_manager', 'controller'],
  'llevan MFA los niveles 1 a 4 y Controller'
);
select is((select array_agg(level order by level)::int[] from core.roles), array[1,2,3,4,5,6,7,8,9,10],
  'los niveles siguen el orden del Módulo Maestro');

create function pg_temp.perms(p_role text) returns text[] language sql as $$
  select coalesce(array_agg(p.code order by p.code), '{}')
  from core.role_permissions rp
  join core.roles r on r.id = rp.role_id and r.code = p_role
  join core.permissions p on p.id = rp.permission_id
  -- Los del recetario (Fase 2) se prueban aparte, en 140_catalog.
  where rp.deleted_at is null
    and p.module not in ('catalog', 'prices', 'yields', 'recipes', 'scenarios', 'imports', 'reports')
$$;
create function pg_temp.has(p_role text, p_perm text) returns boolean language sql as $$
  select p_perm = any (pg_temp.perms(p_role))
$$;

select ok(not pg_temp.has('superadmin', 'approvals.decide'), 'Superadministrador no aprueba cambios de negocio');
select ok(pg_temp.has('superadmin', 'roles.manage'), 'Superadministrador maneja roles y permisos');
select ok(not pg_temp.has('general_management', 'roles.manage') and not pg_temp.has('general_management', 'users.invite'),
  'Dirección General no administra la seguridad técnica');
select ok(pg_temp.has('general_management', 'approvals.decide'), 'Dirección General aprueba cambios críticos');
select ok(pg_temp.has('brand_director', 'org.manage') and pg_temp.has('brand_director', 'approvals.decide'),
  'Director de Marca gestiona y aprueba');
select ok(pg_temp.has('restaurant_manager', 'users.invite') and not pg_temp.has('restaurant_manager', 'approvals.decide'),
  'Gerente gestiona su equipo pero no aprueba');
select ok(pg_temp.has('executive_chef', 'approvals.decide') and not pg_temp.has('executive_chef', 'org.manage'),
  'Chef Ejecutivo aprueba pero no gestiona la estructura');
select is(pg_temp.perms('head_chef'), array['approvals.view', 'org.view'], 'Jefe de Cocina: solo ver y pedir revisión');
select ok(pg_temp.has('controller', 'audit.view') and pg_temp.has('controller', 'approvals.decide'),
  'Controller ve el historial y aprueba');
select is(pg_temp.perms('purchasing'), array['approvals.view', 'org.view'], 'Compras: no aprueba');
select is(pg_temp.perms('cook'), array['org.view'], 'Cocinero / Operador: solo ver su local');
select ok(
  not exists (select 1 from unnest(pg_temp.perms('auditor')) as p where p ~ '\.(manage|invite|deactivate|assign|decide|transfer)$'),
  'Auditor / Consulta: solo lectura'
);

-- Matriz completa, fila por fila (la aprobada por Joaco el 2026-10-20, con los permisos del 2026-10-21).
create function pg_temp.sorted(p text[]) returns text[] language sql as $$
  select array_agg(c order by c) from unnest(p) as c
$$;
select is(pg_temp.perms('superadmin'), pg_temp.sorted(array['org.view', 'org.manage', 'org.transfer', 'users.view',
  'users.invite', 'users.manage', 'users.deactivate', 'roles.assign', 'roles.manage', 'audit.view', 'audit.export',
  'workflows.manage', 'approvals.view', 'permissions.manage', 'security.view', 'org.archive',
  'users.view_admin_details']), 'matriz completa de Superadministrador');
select is(pg_temp.perms('general_management'), pg_temp.sorted(array['org.view', 'org.transfer', 'users.view',
  'audit.view', 'audit.export', 'approvals.view', 'approvals.decide', 'security.view', 'users.view_admin_details']),
  'matriz completa de Dirección General');
select is(pg_temp.perms('brand_director'), pg_temp.sorted(array['org.view', 'org.manage', 'users.view', 'users.invite',
  'users.manage', 'users.deactivate', 'roles.assign', 'audit.view', 'approvals.view', 'approvals.decide', 'org.archive',
  'users.view_admin_details']),
  'matriz completa de Director de Marca');
select is(pg_temp.perms('restaurant_manager'), pg_temp.sorted(array['org.view', 'org.manage', 'users.view',
  'users.invite', 'users.manage', 'users.deactivate', 'roles.assign', 'approvals.view', 'users.view_admin_details']),
  'matriz completa de Gerente de Restaurante');
select is(pg_temp.perms('executive_chef'), pg_temp.sorted(array['org.view', 'approvals.view', 'approvals.decide']),
  'matriz completa de Chef Ejecutivo');
select is(pg_temp.perms('controller'), pg_temp.sorted(array['org.view', 'audit.view', 'approvals.view',
  'approvals.decide']), 'matriz completa de Controller');
select is(pg_temp.perms('auditor'), pg_temp.sorted(array['org.view', 'users.view', 'audit.view', 'audit.export',
  'approvals.view', 'security.view']), 'matriz completa de Auditor');

select throws_ok($$insert into core.permissions (code, module, description) values ('Org.View', 'org', 'x')$$,
  '23514', null, 'un código de permiso fuera de formato se rechaza');
select throws_ok($$insert into core.permissions (code, module, description) values ('org.other', 'users', 'x')$$,
  '23514', null, 'el módulo tiene que coincidir con el código');
select throws_ok(
  $$insert into core.role_permissions (role_id, permission_id)
    select r.id, p.id from core.roles r, core.permissions p where r.code = 'cook' and p.code = 'org.view'$$,
  '23505', null, 'un permiso no se repite en el mismo rol'
);
select throws_ok($$update core.permissions set code = 'roles.manage', module = 'roles' where code = 'org.view'$$,
  '42501', null, 'el código de un permiso no cambia (si no, todos los roles recibirían otro permiso)');
select throws_ok($$update core.roles set code = 'superadmin_bis' where code = 'cook'$$,
  '42501', null, 'el código de un rol no cambia');
select throws_ok($$update core.roles set requires_mfa = false where code = 'superadmin'$$,
  '42501', null, 'a un rol del catálogo inicial no se le saca el MFA');
select throws_ok($$update core.permissions set deleted_at = now() where code = 'org.view'$$,
  '23514', null, 'no se borra un permiso que algún rol tiene');
insert into core.permissions (code, module, description) values ('tmp.unused', 'tmp', 'Permiso de prueba');
update core.permissions set deleted_at = now() where code = 'tmp.unused';
select throws_ok(
  $$insert into core.role_permissions (role_id, permission_id)
    select r.id, p.id from core.roles r, core.permissions p where r.code = 'cook' and p.code = 'tmp.unused'$$,
  '23514', null, 'no se da un permiso borrado'
);
select ok(
  exists (select 1 from pg_constraint where conname = 'restaurants_id_brand_key' and conrelid = 'org.restaurants'::regclass),
  'org.restaurants tiene unique (id, brand_id) para las asignaciones de restaurante'
);
select is(
  (select count(*)::int from audit.audit_events
    where table_schema = 'core' and table_name in ('roles', 'permissions', 'role_permissions')
      and source = 'maintenance' and reason = 'Catálogo inicial del Módulo Maestro'),
  10 + 14 + 55,
  'el catálogo inicial quedó auditado (10 roles, 14 permisos, 55 relaciones)'
);

-- ---------------------------------------------------------------------------
-- Perfiles y cuentas técnicas
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'nueva@ejemplo.test', '{}', '{"first_name": "Nueva", "last_name": "Persona"}', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'bot@ejemplo.test', '{"actor_type": "service_account"}', '{}', 'authenticated', 'authenticated');

select ok(
  (select status = 'active' and first_name = 'Nueva' and email = 'nueva@ejemplo.test'
     from core.user_profiles where id = '11111111-1111-1111-1111-111111111111'),
  'una persona nueva en Auth tiene su perfil activo'
);
select ok(not exists (select 1 from core.user_profiles where id = '22222222-2222-2222-2222-222222222222'),
  'una cuenta técnica no tiene perfil de persona');
select throws_ok(
  $$update core.user_profiles set email = 'otra@ejemplo.test' where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'el correo del perfil no se cambia desde el perfil'
);
select throws_ok(
  $$update core.user_profiles set status = 'deactivated' where id = '11111111-1111-1111-1111-111111111111'$$,
  '23514', null, 'bloquear sin fecha de bloqueo se rechaza'
);
select throws_ok(
  $$insert into core.service_accounts (id, code, name, owner_user_id)
    values ('11111111-1111-1111-1111-111111111111', 'falsa', 'Falsa', '00000000-0000-4000-8000-000000000401')$$,
  '23514', null, 'una persona no puede ser cuenta técnica'
);
select throws_ok(
  $$insert into core.service_accounts (id, code, name, owner_user_id)
    values ('22222222-2222-2222-2222-222222222222', 'agente-prueba', 'Repetida', '00000000-0000-4000-8000-000000000401')$$,
  '23505', null, 'el código de una cuenta técnica es único'
);
select throws_ok(
  $$update core.user_profiles set deleted_at = now() where id = '11111111-1111-1111-1111-111111111111'$$,
  '42501', null, 'un perfil no se borra: se bloquea'
);

insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role) values
  ('44444444-4444-4444-4444-444444444444', 'bloqueada@ejemplo.test', '{}', '{}', 'authenticated', 'authenticated');
update core.user_profiles set status = 'deactivated', deactivated_at = now(), deactivation_reason = 'Prueba'
 where id = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$insert into core.service_accounts (id, code, name, owner_user_id)
    values ('22222222-2222-2222-2222-222222222222', 'bot-nuevo', 'Bot', '44444444-4444-4444-4444-444444444444')$$,
  '23514', null, 'el responsable de una cuenta técnica tiene que tener la cuenta activa'
);

-- ---------------------------------------------------------------------------
-- Asignaciones
-- ---------------------------------------------------------------------------
create function pg_temp.role_id(p_code text) returns uuid language sql as $$ select id from core.roles where code = p_code $$;

select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
    values ('11111111-1111-1111-1111-111111111111', %L, 'group', '00000000-0000-4000-8000-000000000001')$$, pg_temp.role_id('cook')),
  '23514', null, 'no se asigna un rol a quien no es miembro del grupo'
);

insert into core.user_memberships (user_id, group_id) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-4000-8000-000000000001');

select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id)
    values ('11111111-1111-1111-1111-111111111111', %L, 'group', '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000101')$$, pg_temp.role_id('cook')),
  '23514', null, 'una asignación de grupo con marca se rechaza'
);
select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id)
    values ('11111111-1111-1111-1111-111111111111', %L, 'restaurant', '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000101')$$, pg_temp.role_id('cook')),
  '23514', null, 'una asignación de restaurante sin restaurante se rechaza'
);
select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
    values ('11111111-1111-1111-1111-111111111111', %L, 'restaurant', '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000201')$$, pg_temp.role_id('cook')),
  '23503', null, 'un restaurante que no es de esa marca se rechaza'
);
insert into org.groups (id, name) values ('00000000-0000-4000-8000-000000000002', 'Otro Grupo');
insert into core.user_memberships (user_id, group_id) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-4000-8000-000000000002');
select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id)
    values ('11111111-1111-1111-1111-111111111111', %L, 'brand', '00000000-0000-4000-8000-000000000002',
            '00000000-0000-4000-8000-000000000101')$$, pg_temp.role_id('brand_director')),
  '23503', null, 'una marca de otro grupo se rechaza'
);
select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, valid_from, valid_until)
    values ('11111111-1111-1111-1111-111111111111', %L, 'group', '00000000-0000-4000-8000-000000000001',
            '2026-10-20', '2026-10-01')$$, pg_temp.role_id('auditor')),
  '23514', null, 'una vigencia que termina antes de empezar se rechaza'
);

insert into core.user_memberships (user_id, group_id) values
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-4000-8000-000000000001');
select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
    values ('44444444-4444-4444-4444-444444444444', %L, 'group', '00000000-0000-4000-8000-000000000001')$$,
    pg_temp.role_id('superadmin')),
  '23514', null, 'no se asigna un rol a una cuenta bloqueada'
);
select throws_ok(
  $$update core.user_memberships set group_id = '00000000-0000-4000-8000-000000000002'
     where user_id = '11111111-1111-1111-1111-111111111111' and group_id = '00000000-0000-4000-8000-000000000001'$$,
  '42501', null, 'una membresía no cambia de grupo'
);
select throws_ok(
  $$update core.role_permissions set permission_id = (select id from core.permissions where code = 'audit.view')
     where role_id = (select id from core.roles where code = 'cook')$$,
  '42501', null, 'una relación rol-permiso no cambia de permiso'
);
select throws_ok(
  format($$insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
    values ('00000000-0000-4000-8000-000000000401', %L, 'group', '00000000-0000-4000-8000-000000000001')$$,
    pg_temp.role_id('superadmin')),
  '23505', null, 'la misma asignación vigente no se repite'
);

insert into core.user_role_assignments (id, user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', pg_temp.role_id('cook'),
        'restaurant', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000201');

select throws_ok(
  $$update core.user_role_assignments set restaurant_id = '00000000-0000-4000-8000-000000000202'
     where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null, 'una asignación no cambia de lugar: se quita y se crea otra'
);
select throws_ok(
  $$update core.user_role_assignments set valid_from = '2000-01-01' where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null, 'el inicio de la vigencia no se retrotrae'
);
select lives_ok(
  $$update core.user_role_assignments set valid_until = now() + interval '30 days'
     where id = '33333333-3333-3333-3333-333333333333'$$,
  'la vigencia se puede acortar'
);
select throws_ok(
  $$update core.user_role_assignments set valid_until = now() + interval '60 days'
     where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null, 'la vigencia no se extiende'
);
select throws_ok(
  $$update core.user_role_assignments set valid_until = null where id = '33333333-3333-3333-3333-333333333333'$$,
  '42501', null, 'una vigencia con final no pasa a ser sin final'
);
select throws_ok(
  $$update core.user_memberships set deleted_at = now()
     where user_id = '11111111-1111-1111-1111-111111111111' and group_id = '00000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'no se saca a alguien del grupo mientras tenga roles ahí'
);
select throws_ok(
  $$update core.roles set deleted_at = now() where code = 'cook'$$,
  '23514', null, 'no se borra un rol que alguien tiene'
);

set local request.jwt.claims to '{"sub": "00000000-0000-4000-8000-000000000401", "role": "authenticated"}';
do $$ begin perform core.set_change_context('Cambio de puesto', 'manual'); end $$;
update core.user_role_assignments set deleted_at = now() where id = '33333333-3333-3333-3333-333333333333';
select ok(
  (select deleted_by = '00000000-0000-4000-8000-000000000401' from core.user_role_assignments
    where id = '33333333-3333-3333-3333-333333333333'),
  'quitar un rol deja quién lo quitó'
);
select ok(
  (select action = 'soft_delete' and reason = 'Cambio de puesto'
      and scope_restaurant_id = '00000000-0000-4000-8000-000000000201'
      and scope_brand_id = '00000000-0000-4000-8000-000000000101'
     from audit.audit_events where record_id = '33333333-3333-3333-3333-333333333333'
    order by sequence_number desc limit 1),
  'quitar un rol queda en el historial, con motivo y alcance'
);

update core.user_memberships set deleted_at = now()
 where user_id = '11111111-1111-1111-1111-111111111111' and group_id = '00000000-0000-4000-8000-000000000001';
select throws_ok(
  $$update core.user_role_assignments set deleted_at = null where id = '33333333-3333-3333-3333-333333333333'$$,
  '23514', null, 'no se restaura un rol a quien ya no es miembro del grupo'
);

insert into core.roles (code, name) values ('tmp_role', 'Rol de prueba');
insert into core.user_role_assignments (id, user_id, role_id, scope_type, group_id)
values ('55555555-5555-5555-5555-555555555555', '00000000-0000-4000-8000-000000000401', pg_temp.role_id('tmp_role'),
        'group', '00000000-0000-4000-8000-000000000001');
select ok(
  (select action = 'insert' and actor_user_id = '00000000-0000-4000-8000-000000000401'
      and scope_group_id = '00000000-0000-4000-8000-000000000001'
      and scope_brand_id is null and scope_restaurant_id is null
     from audit.audit_events where record_id = '55555555-5555-5555-5555-555555555555'),
  'dar un rol de grupo queda en el historial, con quién y el alcance de grupo'
);
update core.user_role_assignments set deleted_at = now() where id = '55555555-5555-5555-5555-555555555555';
update core.roles set deleted_at = now() where code = 'tmp_role';
select throws_ok(
  $$update core.user_role_assignments set deleted_at = null where id = '55555555-5555-5555-5555-555555555555'$$,
  '23514', null, 'no se restaura una asignación de un rol borrado'
);

-- ---------------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int from core.user_profiles where email like '%@ejemplo.test' and id::text like '00000000-0000-4000-8000-0000000004%'),
  13, 'el seed tiene 13 personas de prueba (con el Chef del grupo, ADR-0021)'
);
select is(
  (select count(distinct r.code)::int from core.user_role_assignments a join core.roles r on r.id = a.role_id
    where a.user_id::text like '00000000-0000-4000-8000-0000000004%' and a.deleted_at is null),
  10, 'en el seed hay al menos una persona por cada uno de los 10 roles'
);
select is(
  (select count(*)::int from core.user_role_assignments
    where user_id = '00000000-0000-4000-8000-000000000411' and deleted_at is null),
  2, 'el gerente de dos locales tiene dos asignaciones'
);
select ok(
  exists (select 1 from core.service_accounts where code = 'agente-prueba' and status = 'active')
  and not exists (select 1 from core.user_role_assignments where user_id = '00000000-0000-4000-8000-000000000499'),
  'el seed tiene una cuenta técnica sin roles'
);

select * from finish();
rollback;
