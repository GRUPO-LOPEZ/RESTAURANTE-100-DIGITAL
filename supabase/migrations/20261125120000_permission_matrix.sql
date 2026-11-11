-- Matriz de permisos con edición directa (pedido de Soy, ADR-0039).
-- La pantalla de Roles pasa a ser una matriz de roles por permisos con toggles de un clic. Los cambios se guardan
-- en lote, todo o nada. Las quitas y las altas de permisos comunes se aplican en el momento, sin la aprobación de
-- Dirección General; las altas de permisos sensibles siguen esperando su aprobación (decisiones de Joaco del
-- 2026-11-11, que cambian ADR-0008 para la matriz). Se mantienen las demás reglas:
--   * pide permissions.manage para todo el grupo (lo que el pedido llama «roles.manage»);
--   * nadie cambia un rol que tiene él mismo;
--   * la separación entre aprobar y administrar la seguridad (core.check_role_permission_change);
--   * el sistema nunca se queda sin quien cambie la matriz ni sin quien apruebe;
--   * motivo obligatorio y auditoría de cada alta o quita (audit.log_change en core.role_permissions).
-- Todo lo que muestra la matriz sale de la base: nombre corto y orden de cada permiso, y nombre y orden de cada
-- módulo (core.permission_modules).

-- ---------------------------------------------------------------------------
-- 1. Nombre corto y orden de los permisos
-- ---------------------------------------------------------------------------
alter table core.permissions
  add column name       text check (name is null or length(btrim(name)) between 1 and 60),
  add column sort_order integer not null default 0 check (sort_order >= 0);
comment on column core.permissions.name is
  'Nombre corto del permiso en la matriz (por ejemplo, «Ver personas»). La descripción va en el tooltip. Obligatorio en lo vigente.';
comment on column core.permissions.sort_order is 'Orden del permiso dentro de su módulo en la matriz.';

do $$
begin
  perform core.set_change_context('Nombres y orden de los permisos para la matriz (ADR-0039)', 'maintenance');
  update core.permissions p
     set name = v.name, sort_order = v.sort_order
    from (values
      ('org.view', 'Ver la estructura', 10), ('org.manage', 'Editar la estructura', 20),
      ('org.archive', 'Archivar estructura', 30), ('org.transfer', 'Traspasar locales y marcas', 40),
      ('users.view', 'Ver personas', 10), ('users.view_admin_details', 'Ver datos de acceso', 20),
      ('users.invite', 'Invitar personas', 30), ('users.manage', 'Editar personas', 40),
      ('users.deactivate', 'Bloquear y reactivar cuentas', 50),
      ('roles.assign', 'Asignar roles', 10), ('roles.manage', 'Editar el catálogo de roles', 20),
      ('permissions.manage', 'Cambiar la matriz de permisos', 10),
      ('approvals.view', 'Ver aprobaciones', 10), ('approvals.decide', 'Decidir aprobaciones', 20),
      ('workflows.manage', 'Configurar aprobaciones', 10),
      ('audit.view', 'Ver el historial', 10), ('audit.export', 'Exportar el historial', 20),
      ('security.view', 'Ver el registro de seguridad', 10),
      ('catalog.view', 'Ver el catálogo', 10), ('catalog.manage', 'Editar el catálogo', 20),
      ('prices.view', 'Ver precios', 10), ('prices.propose', 'Proponer precios', 20),
      ('prices.approve', 'Aprobar precios', 30), ('prices.configure', 'Configurar precios', 40),
      ('yields.record', 'Registrar rendimientos', 10), ('yields.approve', 'Aprobar rendimientos', 20),
      ('yields.alerts', 'Recibir avisos de rendimiento', 30),
      ('recipes.view', 'Ver recetas', 10), ('recipes.view_costs', 'Ver costos', 20),
      ('recipes.draft', 'Editar borradores', 30), ('recipes.review', 'Revisar recetas', 40),
      ('recipes.approve', 'Aprobar recetas', 50), ('recipes.publish', 'Publicar recetas', 60),
      ('recipes.archive', 'Archivar recetas', 70), ('recipes.assign', 'Asignar recetas a locales', 80),
      ('recipes.manage_categories', 'Administrar rubros de recetas', 90),
      ('scenarios.manage', 'Simular costos', 10),
      ('imports.run', 'Importar desde Excel', 10), ('imports.approve', 'Confirmar importaciones', 20),
      ('reports.export', 'Exportar reportes', 10)
    ) as v (code, name, sort_order)
   where p.code = v.code and p.deleted_at is null;
  -- Con la edición directa, permissions.manage ya no «pide» cambios: los hace.
  update core.permissions
     set description = 'Cambiar la matriz de permisos (qué permisos tiene cada rol). Los cambios se aplican al guardar.'
   where code = 'permissions.manage' and deleted_at is null;
end
$$;

-- Un permiso vigente sin nombre no entra en la matriz: el que se agregue después lo trae en su migración.
alter table core.permissions
  add constraint permissions_name_required check (deleted_at is not null or name is not null);

-- ---------------------------------------------------------------------------
-- 2. Módulos de la matriz
-- ---------------------------------------------------------------------------
create table core.permission_modules (
  id          uuid primary key default gen_random_uuid(),
  code        text not null check (code ~ '^[a-z_]+$'),
  name        text not null check (length(btrim(name)) between 1 and 60),
  sort_order  integer not null default 0 check (sort_order >= 0),
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict
);
create unique index permission_modules_code_key on core.permission_modules (code) where deleted_at is null;
comment on table core.permission_modules is
  'Módulos de la matriz de permisos: nombre en castellano y orden de cada grupo de filas. Catálogo global, como core.permissions y core.roles (sin group_id: la matriz es una sola para todo el sistema). Un permiso de un módulo sin fila se muestra con el código del módulo.';
comment on column core.permission_modules.code is 'Código del módulo, el mismo que core.permissions.module (por ejemplo, users).';
comment on column core.permission_modules.name is 'Nombre del módulo en la matriz (por ejemplo, «Personas»).';
comment on column core.permission_modules.sort_order is 'Orden del módulo en la matriz.';
comment on column core.permission_modules.id is 'Identificador del módulo.';
comment on column core.permission_modules.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.permission_modules.created_by is 'Quién lo creó (lo pone la base).';
comment on column core.permission_modules.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column core.permission_modules.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.permission_modules.deleted_at is 'Baja lógica. Nunca se borra.';
comment on column core.permission_modules.deleted_by is 'Quién lo dio de baja (lo pone la base).';

alter table core.permission_modules enable row level security;
revoke all on core.permission_modules from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on core.permission_modules
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on core.permission_modules
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on core.permission_modules
  for each statement execute function core.reject_truncate();
-- Igual que core.permissions: lo lee cualquier sesión válida. No es un dato sensible.
create policy permission_modules_select on core.permission_modules for select to authenticated
  using ((select core.current_session_ok()));
grant select on core.permission_modules to authenticated;

do $$
begin
  perform core.set_change_context('Módulos de la matriz de permisos (ADR-0039)', 'maintenance');
  insert into core.permission_modules (code, name, sort_order) values
    ('org', 'Estructura', 10), ('users', 'Personas', 20), ('roles', 'Roles', 30),
    ('permissions', 'Matriz de permisos', 40), ('approvals', 'Aprobaciones', 50),
    ('workflows', 'Tipos de aprobación', 60), ('audit', 'Historial', 70), ('security', 'Registro de seguridad', 80),
    ('catalog', 'Materias primas', 90), ('prices', 'Precios', 100), ('yields', 'Rendimientos', 110),
    ('recipes', 'Recetas', 120), ('scenarios', 'Escenarios de costo', 130), ('imports', 'Importaciones', 140),
    ('reports', 'Reportes', 150);
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Guardar la matriz: un lote de cambios, todo o nada
-- ---------------------------------------------------------------------------
-- Edición directa con un límite (decisiones de Joaco, 2026-11-11, después de la revisión de seguridad):
--   * se aplican al guardar las quitas y las altas de permisos comunes;
--   * las altas de permisos sensibles (is_sensitive: administrar la seguridad, aprobar, invitar, bloquear…) no se
--     aplican: cada una queda como un pedido de la matriz (core.request_role_permission_change), que aprueba
--     Dirección General y que no puede aprobar quien tiene ese rol. Así nadie da en el momento un permiso de
--     seguridad, ni a un rol que entra sin doble verificación.
-- Las reglas de siempre se controlan cambio por cambio, sobre el estado real: la matriz queda bloqueada mientras
-- se guarda y, además, el alta de roles de los grupos afectados (core.lock_group_roles), para que una asignación
-- simultánea no deje a una persona aprobando y administrando la seguridad a la vez.
-- Que el sistema no se quede sin quien cambie la matriz ni sin quien apruebe lo garantizan los bloqueos fijos de
-- core.check_role_permission_change (Superadministrador: permissions.manage y roles.manage; Dirección General:
-- approvals.decide).
-- La matriz es una sola para todo el sistema (los roles no tienen grupo, ADR-0013): hoy hay un grupo; si se suma
-- otro, hay que revisar quién la administra (ADR-0039).
create function core.apply_permission_matrix(p_group_id uuid, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_details jsonb;
  v_change  record;
  v_group   uuid;
  v_result  jsonb;
  v_applied integer := 0;
  v_pending integer := 0;
  v_message text;
begin
  -- Forma y tamaño antes que nada: el registro de un rechazo guarda solo cuántos cambios eran.
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_changes) > 1000 then
    raise exception 'Son demasiados cambios juntos: guardá de a partes.' using errcode = '22023';
  end if;
  v_details := jsonb_build_object('changes', jsonb_array_length(p_changes));
  if not core.has_permission_in_group('permissions.manage', p_group_id) then
    return core.deny('core.apply_permission_matrix', 'No tenés permiso para cambiar la matriz de permisos.',
                     null, v_details, p_group_id);
  end if;
  if exists (select 1 from jsonb_array_elements(p_changes) e
              where jsonb_typeof(e) <> 'object'
                 or jsonb_typeof(e -> 'role_id') <> 'string' or jsonb_typeof(e -> 'permission_code') <> 'string'
                 or jsonb_typeof(e -> 'granted') <> 'boolean'
                 or (e ->> 'role_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'No pudimos leer los cambios. Recargá la página.' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(p_changes))
     <> (select count(distinct ((e ->> 'role_id')::uuid, e ->> 'permission_code')) from jsonb_array_elements(p_changes) e) then
    raise exception 'El mismo permiso de un rol aparece dos veces.' using errcode = '22023';
  end if;

  perform core.set_change_context(p_reason, 'manual');
  -- Nadie más cambia la matriz ni da roles en los grupos afectados mientras tanto (siempre en el mismo orden).
  lock table core.role_permissions in share row exclusive mode;
  for v_group in
    select g from (select p_group_id as g
                   union
                   select a.group_id from core.user_role_assignments a
                    where a.deleted_at is null
                      and a.role_id in (select (e ->> 'role_id')::uuid from jsonb_array_elements(p_changes) e)) x
     order by g
  loop
    perform core.lock_group_roles(v_group);
  end loop;

  -- Que existan, y que ninguno sea un rol propio (después del bloqueo: ve las asignaciones confirmadas).
  for v_change in
    select (e ->> 'role_id')::uuid as role_id, e ->> 'permission_code' as permission_code
      from jsonb_array_elements(p_changes) e
  loop
    if not exists (select 1 from core.roles where id = v_change.role_id and deleted_at is null)
       or not exists (select 1 from core.permissions where code = v_change.permission_code and deleted_at is null) then
      raise exception 'No existe ese rol o ese permiso.' using errcode = '22023';
    end if;
    -- Nadie cambia un rol que tiene él mismo (si no, podría darse approvals.decide).
    if exists (select 1 from core.user_role_assignments a
                where a.user_id = core.current_actor_id() and a.role_id = v_change.role_id and a.deleted_at is null) then
      return core.deny('core.apply_permission_matrix', 'No podés cambiar los permisos de un rol que tenés vos.',
                       null, v_details, p_group_id);
    end if;
  end loop;

  -- Lo que se aplica ya: primero las quitas y después las altas comunes, así un lote que mueve un permiso de un
  -- rol a otro no choca con la separación de funciones a mitad de camino.
  for v_change in
    select r.id as role_id, p.id as permission_id, p.code as permission_code, (e ->> 'granted')::boolean as granted
      from jsonb_array_elements(p_changes) e
      join core.roles r on r.id = (e ->> 'role_id')::uuid and r.deleted_at is null
      join core.permissions p on p.code = e ->> 'permission_code' and p.deleted_at is null
     where not ((e ->> 'granted')::boolean and p.is_sensitive)
     order by (e ->> 'granted')::boolean, r.id, p.code
  loop
    perform core.check_role_permission_change(v_change.role_id, v_change.permission_code, v_change.granted);
    if v_change.granted then
      insert into core.role_permissions (role_id, permission_id) values (v_change.role_id, v_change.permission_id);
    else
      update core.role_permissions set deleted_at = now()
       where role_id = v_change.role_id and permission_id = v_change.permission_id and deleted_at is null;
    end if;
    v_applied := v_applied + 1;
  end loop;

  -- Las altas de permisos sensibles quedan pedidas para Dirección General, con el mismo motivo.
  for v_change in
    select r.code as role_code, p.code as permission_code
      from jsonb_array_elements(p_changes) e
      join core.roles r on r.id = (e ->> 'role_id')::uuid and r.deleted_at is null
      join core.permissions p on p.code = e ->> 'permission_code' and p.deleted_at is null
     where (e ->> 'granted')::boolean and p.is_sensitive
     order by r.code, p.code
  loop
    v_result := core.request_role_permission_change(p_group_id, v_change.role_code, v_change.permission_code, true,
                                                    p_reason);
    if v_result ->> 'result' is distinct from 'pending_approval' then
      raise exception '%', coalesce(v_result ->> 'message', 'No se pudo pedir el permiso sensible.') using errcode = '42501';
    end if;
    v_pending := v_pending + 1;
  end loop;

  v_message := concat_ws(' ',
    case when v_applied = 1 then 'Se guardó 1 cambio.'
         when v_applied > 1 then format('Se guardaron %s cambios.', v_applied) end,
    case when v_pending = 1 then '1 permiso sensible queda pendiente hasta que lo apruebe Dirección General.'
         when v_pending > 1 then format('%s permisos sensibles quedan pendientes hasta que los apruebe Dirección General.', v_pending) end);
  return jsonb_build_object('result', case when v_applied > 0 then 'applied' else 'pending_approval' end,
                            'applied', v_applied, 'pending', v_pending, 'message', v_message);
end
$$;
comment on function core.apply_permission_matrix(uuid, jsonb, text) is
  'Guarda un lote de cambios de la matriz ([{role_id, permission_code, granted}]) en una sola transacción, todo o nada (ADR-0039). Aplica en el momento las quitas y las altas comunes; las altas de permisos sensibles quedan como pedidos que aprueba Dirección General. Pide permissions.manage en el grupo y un motivo; no se puede sobre un rol propio; respeta la separación de funciones. Cada cambio queda en la auditoría.';
revoke execute on function core.apply_permission_matrix(uuid, jsonb, text) from public, anon;
grant execute on function core.apply_permission_matrix(uuid, jsonb, text) to authenticated;

-- Aplicar un pedido aprobado bloquea la matriz igual que el guardado directo (revisión de seguridad): los
-- controles se hacen sobre el estado real y no se cruzan con un lote que se está guardando.
create or replace function core.apply_role_permission_change(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_p     jsonb := v_req.proposed_changes;
  v_grant boolean := (v_req.proposed_changes ->> 'grant')::boolean;
begin
  if not core.user_has_permission_for_scope(v_req.requested_by, 'permissions.manage', 'group', v_req.group_id) then
    perform workflow.cannot_apply('quien la pidió ya no puede cambiar la matriz');
  end if;
  lock table core.role_permissions in share row exclusive mode;
  perform core.lock_group_roles(v_req.group_id);
  -- Las mismas reglas que al pedirlo: también falla si el cambio ya no tiene sentido.
  perform core.check_role_permission_change((v_p ->> 'role_id')::uuid, v_p ->> 'permission_code', v_grant);
  perform core.set_change_context('Matriz de permisos aprobada (solicitud ' || p_request_id || ')', 'manual');
  if v_grant then
    insert into core.role_permissions (role_id, permission_id)
    values ((v_p ->> 'role_id')::uuid, (v_p ->> 'permission_id')::uuid);
  else
    update core.role_permissions set deleted_at = now()
     where role_id = (v_p ->> 'role_id')::uuid and permission_id = (v_p ->> 'permission_id')::uuid and deleted_at is null;
  end if;
end
$$;


-- ---------------------------------------------------------------------------
-- 4. Leer la matriz: con nombres, orden y módulos
-- ---------------------------------------------------------------------------
create or replace function core.permission_matrix(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_manage boolean;
begin
  if not core.current_session_ok() or not core.can_view_scope('org.view', 'group', p_group_id) then
    return null;
  end if;
  v_manage := core.has_permission_in_group('permissions.manage', p_group_id);
  return jsonb_build_object(
    'can_manage', v_manage,
    'roles', (select jsonb_agg(jsonb_build_object('id', r.id, 'code', r.code, 'name', r.name, 'level', r.level,
                                                  'requires_mfa', r.requires_mfa,
                                                  -- Nadie cambia un rol que tiene él mismo.
                                                  'is_mine', exists (select 1 from core.user_role_assignments a
                                                                      where a.user_id = core.current_actor_id() and a.role_id = r.id
                                                                        and a.deleted_at is null))
                                order by r.level, r.name)
                from core.roles r where r.deleted_at is null),
    'modules', (select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'name', m.name, 'sort_order', m.sort_order)
                                          order by m.sort_order, m.code), '[]'::jsonb)
                  from core.permission_modules m where m.deleted_at is null),
    'permissions', (select jsonb_agg(jsonb_build_object('code', p.code, 'module', p.module, 'action', p.action,
                                                        'name', p.name, 'description', p.description,
                                                        'is_sensitive', p.is_sensitive, 'sort_order', p.sort_order)
                                      order by coalesce(m.sort_order, 1000000), p.module, p.sort_order, p.code)
                      from core.permissions p
                      left join core.permission_modules m on m.code = p.module and m.deleted_at is null
                     where p.deleted_at is null),
    'grants', (select coalesce(jsonb_agg(jsonb_build_object('role_code', r.code, 'permission_code', p.code)), '[]'::jsonb)
                 from core.role_permissions rp
                 join core.roles r on r.id = rp.role_id and r.deleted_at is null
                 join core.permissions p on p.id = rp.permission_id and p.deleted_at is null
                where rp.deleted_at is null),
    -- Pedidos de cambio de antes de la edición directa que todavía esperan en Aprobaciones.
    'pending', case when v_manage then (
      select coalesce(jsonb_agg(jsonb_build_object('request_id', q.id, 'role_code', q.proposed_changes ->> 'role_code',
                                                   'permission_code', q.proposed_changes ->> 'permission_code',
                                                   'grant', (q.proposed_changes ->> 'grant')::boolean,
                                                   'requested_by_name', core.display_name(q.requested_by),
                                                   'requested_at', q.requested_at, 'reason', q.reason)
                                order by q.requested_at desc), '[]'::jsonb)
        from workflow.approval_requests q
        join workflow.approval_workflows w on w.id = q.workflow_id and w.code = 'core.change_role_permission'
       where q.group_id = p_group_id and q.status = 'pending' and q.deleted_at is null) else '[]'::jsonb end
  );
end
$$;
comment on function core.permission_matrix(uuid) is
  'Matriz de roles por permiso del grupo, para la pantalla de Roles y permisos: roles por nivel, módulos y permisos con nombre y orden, y quién tiene qué. Quien tiene permissions.manage ve además los pedidos viejos que esperan aprobación.';
