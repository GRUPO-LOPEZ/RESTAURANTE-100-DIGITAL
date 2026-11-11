-- Matriz de permisos con edición directa (ADR-0039): nombres y módulos desde la base, y el guardado en lote
-- (core.apply_permission_matrix), todo o nada, con permissions.manage, sin tocar roles propios, con la
-- separación de funciones y la auditoría. Superadmin (401) cambia la matriz; Gerente (404) no; Auditor (410)
-- se usa para probar las reglas que el Superadministrador no puede tocar (sus propios roles).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(38);

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
create function pg_temp.role(p_code text) returns uuid language sql as $$
  select id from core.roles where code = p_code and deleted_at is null
$$;
-- Guarda un lote como esa persona y devuelve el "result" (applied, denied) o "ERROR <código>".
create function pg_temp.save(p_user uuid, p_changes jsonb, p_reason text default 'Prueba de la matriz',
                             p_aal text default 'aal2')
returns text language sql as $$
  select pg_temp.q(p_user, format('select core.apply_permission_matrix(%L, %L::jsonb, %L) ->> ''result''',
                                  pg_temp.u(1), p_changes, p_reason), p_aal)
$$;
create function pg_temp.c(p_role text, p_perm text, p_granted boolean) returns jsonb language sql as $$
  select jsonb_build_object('role_id', pg_temp.role(p_role), 'permission_code', p_perm, 'granted', p_granted)
$$;
create function pg_temp.has(p_role text, p_perm text) returns boolean language sql as $$
  select exists (select 1 from core.role_permissions rp join core.permissions p on p.id = rp.permission_id
                  where rp.role_id = pg_temp.role(p_role) and p.code = p_perm and rp.deleted_at is null)
$$;

-- ---------------------------------------------------------------------------
-- Estructura: todo lo que muestra la matriz sale de la base
-- ---------------------------------------------------------------------------
select has_column('core', 'permissions', 'name', 'cada permiso tiene un nombre corto');
select has_column('core', 'permissions', 'sort_order', 'y un orden');
select has_table('core', 'permission_modules', 'los módulos tienen su tabla');
select ok((select relrowsecurity from pg_class where oid = 'core.permission_modules'::regclass), 'con RLS');
select is((select count(*)::int from core.permissions where deleted_at is null and name is null), 0,
  'todos los permisos vigentes tienen nombre');
select is((select count(*)::int from (select distinct module from core.permissions where deleted_at is null) p
            where not exists (select 1 from core.permission_modules m where m.code = p.module and m.deleted_at is null)), 0,
  'todos los módulos con permisos tienen nombre');
select throws_ok($$insert into core.permissions (code, module, description) values ('demo.view', 'demo', 'Sin nombre')$$,
  '23514', 'new row for relation "permissions" violates check constraint "permissions_name_required"',
  'un permiso vigente nuevo sin nombre no entra');
select is(pg_temp.q(pg_temp.u(410), format($$select string_agg(p ->> 'name', '|') from jsonb_array_elements(core.permission_matrix(%L) -> 'permissions') p
                                             where p ->> 'code' in ('users.view', 'permissions.manage')$$, pg_temp.u(1))),
  'Ver personas|Cambiar la matriz de permisos', 'la matriz trae el nombre de cada permiso, en el orden de su módulo');
select is(pg_temp.q(pg_temp.u(410), format($$select (core.permission_matrix(%L) -> 'modules' -> 0 ->> 'name')$$, pg_temp.u(1))),
  'Estructura', 'y los módulos con su nombre y su orden');

-- ---------------------------------------------------------------------------
-- Guardar un lote
-- ---------------------------------------------------------------------------
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'approvals.view', true),
                                                         pg_temp.c('cook', 'recipes.view', false)),
                       'Que la cocina vea sus pedidos'),
  'applied', 'el Superadministrador guarda dos cambios juntos y se aplican en el momento');
select ok(pg_temp.has('cook', 'approvals.view') and not pg_temp.has('cook', 'recipes.view'), 'los dos quedaron hechos');
select is((select count(*)::int from audit.audit_events
            where table_schema = 'core' and table_name = 'role_permissions' and actor_user_id = pg_temp.u(401)
              and reason = 'Que la cocina vea sus pedidos'),
  2, 'cada cambio queda en la auditoría, con quién y por qué');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'role_permissions' and reason = 'Que la cocina vea sus pedidos' and action = 'soft_delete'
                     and old_values ->> 'deleted_at' is null and new_values ->> 'deleted_at' is not null),
  'la quita queda como borrado lógico, con el antes y el después');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'catalog.view', true),
                                                         pg_temp.c('cook', 'org.view', true))),
  'ERROR 23505', 'si un cambio ya está hecho (la cocina ya tiene org.view), no se guarda nada');
select ok(not pg_temp.has('cook', 'catalog.view'), 'todo o nada: el otro cambio del lote tampoco quedó');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'demo.nada', true))),
  'ERROR 22023', 'un permiso que no existe no se guarda');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'catalog.view', true),
                                                         pg_temp.c('cook', 'catalog.view', false))),
  'ERROR 22023', 'la misma celda dos veces no se guarda');
select is(pg_temp.save(pg_temp.u(401), '[]'::jsonb), 'ERROR 22023', 'un lote vacío no se guarda');
select ok(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'catalog.view', true)), '') ~ '^ERROR',
  'sin motivo no se guarda');

-- ---------------------------------------------------------------------------
-- Seguridad: la base decide, también llamando a la función directo
-- ---------------------------------------------------------------------------
select is(pg_temp.save(pg_temp.u(404), jsonb_build_array(pg_temp.c('cook', 'catalog.view', true))),
  'denied', 'el Gerente, sin permissions.manage, no cambia la matriz');
select ok(exists (select 1 from audit.authentication_security_events
                   where actor_id = pg_temp.u(404) and operation = 'core.apply_permission_matrix'),
  'y el intento queda en el registro de seguridad');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'catalog.view', true)), 'Prueba', 'aal1'),
  'denied', 'el Superadministrador sin doble verificación tampoco');
select is(pg_temp.q(null, format($$select core.apply_permission_matrix(%L, '[]'::jsonb, 'x')::text$$, pg_temp.u(1))),
  'ERROR 42501', 'sin sesión, ni siquiera se puede llamar');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('superadmin', 'approvals.decide', true))),
  'denied', 'nadie cambia un rol que tiene él mismo (el Superadministrador no se da approvals.decide)');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('general_management', 'permissions.manage', true))),
  'ERROR 23514', 'un rol que aprueba cambios no recibe la administración de la matriz (separación de funciones)');
-- ---------------------------------------------------------------------------
-- Permisos sensibles: se piden, no se aplican (decisión de Joaco, 2026-11-11, por la revisión de seguridad)
-- ---------------------------------------------------------------------------
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'audit.view', true)),
                       'Que la cocina vea el historial'),
  'pending_approval', 'dar un permiso sensible no se aplica: queda pedido para Dirección General');
select ok(not pg_temp.has('cook', 'audit.view'), 'la cocina todavía no lo tiene');
select is((select count(*)::int from workflow.approval_requests q
             join workflow.approval_workflows w on w.id = q.workflow_id and w.code = 'core.change_role_permission'
            where q.status = 'pending' and q.proposed_changes ->> 'role_code' = 'cook'
              and q.proposed_changes ->> 'permission_code' = 'audit.view' and q.requested_by = pg_temp.u(401)
              and q.reason = 'Que la cocina vea el historial'),
  1, 'el pedido lleva el motivo del lote y quién lo pidió');
select is(pg_temp.q(pg_temp.u(401), format($$select core.apply_permission_matrix(%L, %L::jsonb, 'Mezcla') ->> 'message'$$,
                                           pg_temp.u(1), jsonb_build_array(pg_temp.c('cook', 'catalog.view', true),
                                                                           pg_temp.c('cook', 'audit.export', true)))),
  'Se guardó 1 cambio. 1 permiso sensible queda pendiente hasta que lo apruebe Dirección General.',
  'en un lote mixto, lo común se aplica y lo sensible queda pedido');
select ok(pg_temp.has('cook', 'catalog.view') and not pg_temp.has('cook', 'audit.export'), 'y así quedó cada uno');
select is(pg_temp.q(pg_temp.u(412), format($$select workflow.decide_approval(%L, 'approved', 'De acuerdo') ->> 'result'$$,
                                           (select q.id from workflow.approval_requests q
                                             where q.status = 'pending' and q.proposed_changes ->> 'role_code' = 'cook'
                                               and q.proposed_changes ->> 'permission_code' = 'audit.view'))),
  'approved', 'Dirección General aprueba el pedido');
select ok(pg_temp.has('cook', 'audit.view'), 'y recién ahí la cocina tiene el permiso sensible');
select is(pg_temp.save(pg_temp.u(401), jsonb_build_array(pg_temp.c('cook', 'imports.run', true),
                                                         jsonb_build_object('role_id', upper(pg_temp.role('cook')::text),
                                                                            'permission_code', 'imports.run', 'granted', false))),
  'ERROR 22023', 'la misma celda dos veces no pasa ni escribiendo el id en mayúsculas');
select ok(exists (select 1 from audit.authentication_security_events
                   where actor_id = pg_temp.u(404) and operation = 'core.apply_permission_matrix' and detail ->> 'changes' = '1'),
  'el rechazo guarda solo cuántos cambios eran, no el lote entero');
select is(pg_temp.q(null, 'select count(*)::text from core.permission_modules'), 'ERROR 42501',
  'sin sesión no se leen los módulos');
select is(pg_temp.q(pg_temp.u(401), $$insert into core.permission_modules (code, name) values ('demo', 'Demo') returning code$$),
  'ERROR 42501', 'y nadie los escribe por la API');

-- Un Auditor con permissions.manage (dado por la base para la prueba) intenta dejar el sistema sin quien
-- cambie la matriz o sin quien apruebe.
select core.set_change_context('Prueba de la matriz: el Auditor administra permisos', 'manual');
insert into core.role_permissions (role_id, permission_id)
select pg_temp.role('auditor'), id from core.permissions where code = 'permissions.manage';
select is(pg_temp.save(pg_temp.u(410), jsonb_build_array(pg_temp.c('superadmin', 'permissions.manage', false))),
  'ERROR 23514', 'nadie le saca al Superadministrador la matriz de permisos');
select is(pg_temp.save(pg_temp.u(410), jsonb_build_array(pg_temp.c('general_management', 'approvals.decide', false))),
  'ERROR 23514', 'ni a Dirección General la aprobación de cambios');

select * from finish();
rollback;
