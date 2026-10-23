-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), paso 2:
--   1. Permisos nuevos de la sección 8 (sin quitar los que ya hay, decisión de Joaco del 2026-10-21):
--      permissions.manage (la matriz), security.view (registro de seguridad) y org.archive (archivar).
--   2. core.my_scopes(): las marcas y los locales de la sesión.
--   3. Suspender y levantar la suspensión (pausa sin aprobación).
--   4. Selector de local: recordar el último.
--   5. Avisos dentro de la app (core.notifications): request_approval avisa a quienes pueden decidir.
--   6. Tabla de ensayo core.test_documents (sección 10): imita una receta para las pruebas 2, 3 y 7.
--      Se borra con una migración al cerrar la Fase 1, antes de la Fase 2.

-- ---------------------------------------------------------------------------
-- 1. Permisos nuevos y quién los tiene
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos del documento de la Fase 1 (ADR-0015)', 'maintenance');

  update core.permissions set description = 'Editar el catálogo de roles (crear, renombrar o archivar roles).'
   where code = 'roles.manage';

  insert into core.permissions (code, module, description, is_sensitive) values
    ('permissions.manage', 'permissions', 'Pedir cambios en la matriz de permisos (qué permisos tiene cada rol).', true),
    ('security.view',      'security',    'Ver el registro de seguridad: ingresos, intentos rechazados, bloqueos y suspensiones.', true),
    ('org.archive',        'org',         'Archivar (borrado lógico) y restaurar marcas, locales y áreas.', true),
    ('test_documents.view',       'test_documents', 'Ver los documentos de ensayo (solo Fase 1).', false),
    ('test_documents.edit',       'test_documents', 'Crear borradores de documentos de ensayo y pedir su revisión (solo Fase 1).', false),
    ('test_documents.publish',    'test_documents', 'Aprobar y publicar documentos de ensayo (solo Fase 1).', false),
    ('test_documents.view_costs', 'test_documents', 'Ver los costos de los documentos de ensayo (solo Fase 1).', true);

  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
  from (values
    ('superadmin', 'permissions.manage'), ('superadmin', 'security.view'), ('superadmin', 'org.archive'),
    ('general_management', 'security.view'),
    ('auditor', 'security.view'),
    ('brand_director', 'org.archive'),
    -- Ensayo (aprobado en el plan del 2026-10-21). La directora de marca y el gerente tienen lo
    -- mismo que los roles que asignan (Chef y Jefe de Cocina): si no, no podrían darlos (nadie da
    -- permisos que no tiene).
    -- El superadmin también: si no, no podría suspender ni desactivar a quien los tiene (G2).
    ('superadmin', 'test_documents.view'), ('superadmin', 'test_documents.edit'),
    ('cook', 'test_documents.view'),
    ('restaurant_manager', 'test_documents.view'), ('restaurant_manager', 'test_documents.edit'),
    ('brand_director', 'test_documents.view'), ('brand_director', 'test_documents.edit'),
    ('brand_director', 'test_documents.publish'),
    ('purchasing', 'test_documents.view'),
    ('auditor', 'test_documents.view'),
    ('head_chef', 'test_documents.view'), ('head_chef', 'test_documents.edit'),
    ('executive_chef', 'test_documents.view'), ('executive_chef', 'test_documents.edit'), ('executive_chef', 'test_documents.publish'),
    ('controller', 'test_documents.view'), ('controller', 'test_documents.view_costs'),
    ('general_management', 'test_documents.view'), ('general_management', 'test_documents.view_costs')
  ) as m (role_code, permission_code)
  join core.roles r on r.code = m.role_code
  join core.permissions p on p.code = m.permission_code;
end
$$;

-- La matriz de permisos pasa a permissions.manage; la separación de funciones lo cuenta como
-- "administrar la seguridad técnica", igual que roles.manage y workflows.manage.
create or replace function core.is_sensitive_role(p_role_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from core.roles r where r.id = p_role_id and r.code = 'superadmin')
      or core.role_permission_codes(p_role_id) && array['approvals.decide', 'roles.manage', 'permissions.manage', 'workflows.manage']
$$;

create or replace function core.check_person_separation(p_user_id uuid, p_role_id uuid, p_group_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perms text[];
begin
  select coalesce(array_agg(distinct p.code), '{}') into v_perms
    from (select a.role_id from core.user_role_assignments a
           where a.user_id = p_user_id and a.group_id = p_group_id and a.deleted_at is null
             and (a.valid_until is null or a.valid_until > now())
          union select p_role_id) as roles_
    join core.role_permissions rp on rp.role_id = roles_.role_id and rp.deleted_at is null
    join core.permissions p on p.id = rp.permission_id and p.deleted_at is null;
  if 'approvals.decide' = any (v_perms) and v_perms && array['roles.manage', 'permissions.manage', 'workflows.manage'] then
    raise exception 'Una misma persona no puede aprobar cambios y administrar la seguridad técnica en el mismo grupo.'
      using errcode = '23514';
  end if;
end
$$;

create or replace function core.check_role_permission_change(p_role_id uuid, p_permission_code text, p_grant boolean)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_perms text[] := core.role_permission_codes(p_role_id);
  v_code  text;
begin
  select code into v_code from core.roles where id = p_role_id;
  if p_grant and p_permission_code in ('roles.manage', 'permissions.manage', 'workflows.manage') and 'approvals.decide' = any (v_perms) then
    raise exception 'Un rol que aprueba cambios no puede administrar la seguridad técnica.' using errcode = '23514';
  end if;
  if p_grant and p_permission_code = 'approvals.decide' and v_perms && array['roles.manage', 'permissions.manage', 'workflows.manage'] then
    raise exception 'Un rol que administra la seguridad técnica no puede aprobar cambios.' using errcode = '23514';
  end if;
  if not p_grant and ((v_code = 'general_management' and p_permission_code = 'approvals.decide')
                      or (v_code = 'superadmin' and p_permission_code in ('roles.manage', 'permissions.manage'))) then
    raise exception 'Ese permiso no se puede quitar: el sistema se quedaría sin quien apruebe o sin quien administre los permisos.'
      using errcode = '23514';
  end if;
  if (p_permission_code = any (v_perms)) = p_grant then
    raise exception 'El rol % ya % ese permiso.', v_code, case when p_grant then 'tiene' else 'no tiene' end
      using errcode = '23505';
  end if;
  -- Por persona: nadie que tenga este rol puede quedar, sumando todos sus roles del grupo, con
  -- aprobar cambios y administrar la seguridad técnica a la vez (revisión de seguridad, M-C).
  if p_grant and p_permission_code in ('approvals.decide', 'roles.manage', 'permissions.manage', 'workflows.manage')
     and exists (
       select 1
         from core.user_role_assignments h
        where h.role_id = p_role_id and h.deleted_at is null and (h.valid_until is null or h.valid_until > now())
          and (
            select (p_permission_code = 'approvals.decide' or 'approvals.decide' = any (array_agg(p.code)))
               and (p_permission_code <> 'approvals.decide'
                    or array_agg(p.code) && array['roles.manage', 'permissions.manage', 'workflows.manage'])
              from core.user_role_assignments o
              join core.role_permissions rp on rp.role_id = o.role_id and rp.deleted_at is null
              join core.permissions p on p.id = rp.permission_id and p.deleted_at is null
             where o.user_id = h.user_id and o.group_id = h.group_id and o.deleted_at is null
               and (o.valid_until is null or o.valid_until > now()))) then
    raise exception 'Hay personas con este rol que también aprueban cambios (o administran la seguridad) por otro rol: no pueden juntar las dos cosas.'
      using errcode = '23514';
  end if;
end
$$;

create or replace function core.request_role_permission_change(p_group_id uuid, p_role_code text, p_permission_code text,
                                                               p_grant boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role    core.roles;
  v_perm    core.permissions;
  v_details jsonb := jsonb_build_object('role', p_role_code, 'permission', p_permission_code, 'grant', p_grant);
  v_request uuid;
  v_rp      uuid;
begin
  if not core.has_permission_in_group('permissions.manage', p_group_id) then
    return core.deny('core.request_role_permission_change', 'No tenés permiso para cambiar la matriz de permisos.',
                     null, v_details, p_group_id);
  end if;
  select * into v_role from core.roles where code = p_role_code and deleted_at is null;
  select * into v_perm from core.permissions where code = p_permission_code and deleted_at is null;
  if v_role.id is null or v_perm.id is null or p_grant is null then
    raise exception 'No existe ese rol o ese permiso.' using errcode = '22023';
  end if;
  -- Nadie cambia un rol que tiene él mismo (si no, el superadmin podría darse approvals.decide).
  if exists (select 1 from core.user_role_assignments a
              where a.user_id = core.current_actor_id() and a.role_id = v_role.id and a.deleted_at is null) then
    return core.deny('core.request_role_permission_change', 'No podés cambiar los permisos de un rol que tenés vos.',
                     null, v_details, p_group_id);
  end if;
  perform core.check_role_permission_change(v_role.id, v_perm.code, p_grant);
  select rp.id into v_rp from core.role_permissions rp
   where rp.role_id = v_role.id and rp.permission_id = v_perm.id and rp.deleted_at is null;
  v_request := workflow.request_approval('core.change_role_permission', p_group_id, null, null, null, v_rp,
    jsonb_build_object('role_id', v_role.id, 'role_code', v_role.code, 'permission_id', v_perm.id,
                       'permission_code', v_perm.code, 'grant', p_grant,
                       -- Quienes tienen ese rol no aprueban el cambio (se beneficiarían).
                       'excluded_approvers', core.role_holders(v_role.id)),
    jsonb_build_object('grant', not p_grant),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'El cambio de la matriz queda pendiente hasta que lo apruebe Dirección General.');
end
$$;

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

-- Archivar y restaurar piden org.archive en el nivel de arriba (sección 5: "*.archive").
create or replace function org.set_deleted(p_table text, p_id uuid, p_deleted boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allowed boolean;
  v_found   boolean;
begin
  if p_deleted is null then
    raise exception 'Hay que indicar si se borra (true) o se restaura (false).' using errcode = '22023';
  end if;
  if p_table = 'brands' then
    select true, core.has_permission_in_group('org.archive', b.group_id) into v_found, v_allowed
      from org.brands b where b.id = p_id;
  elsif p_table = 'restaurants' then
    select true, core.has_permission_in_brand('org.archive', r.brand_id) into v_found, v_allowed
      from org.restaurants r where r.id = p_id;
  elsif p_table = 'areas' then
    select true, core.has_permission('org.archive', a.restaurant_id) into v_found, v_allowed
      from org.areas a where a.id = p_id;
  else
    raise exception 'Solo se pueden borrar o restaurar marcas, locales y áreas.' using errcode = '22023';
  end if;

  perform org.require(v_found and v_allowed, case when p_deleted then 'archivar esto' else 'restaurar esto' end);
  perform core.set_change_context(p_reason, 'manual');
  execute format('update org.%I set deleted_at = case when $1 then now() end where id = $2', p_table)
    using p_deleted, p_id;
end
$$;
comment on function org.set_deleted(text, uuid, boolean, text) is
  'Archiva (borrado lógico) o restaura una marca, un local o un área. Pide org.archive en el nivel de arriba y un motivo. Las reglas de la jerarquía siguen valiendo.';

-- ---------------------------------------------------------------------------
-- 2. Mis marcas y locales (sección 5): para menús, selector y filtros
-- ---------------------------------------------------------------------------
create function core.my_scopes()
returns table (brand_id uuid, brand_name text, brand_code text, restaurant_id uuid, restaurant_name text, restaurant_code text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    return;
  end if;
  return query
  select distinct b.id, b.name, b.code, r.id, r.name, r.code
    from core.user_role_assignments a
    join core.roles ro on ro.id = a.role_id and ro.deleted_at is null
    join core.user_memberships m on m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
                                and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
    join org.restaurants r on r.group_id = a.group_id and r.deleted_at is null
                          and (a.scope_type = 'group'
                               or (a.scope_type = 'brand' and r.brand_id = a.brand_id)
                               or (a.scope_type = 'restaurant' and r.id = a.restaurant_id))
    join org.brands b on b.id = r.brand_id and b.deleted_at is null
   where a.user_id = v_actor and a.deleted_at is null
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
   order by b.name, r.name;
end
$$;
comment on function core.my_scopes() is
  'Las marcas y los locales donde la sesión tiene algún rol vigente (una asignación de grupo cubre todos, una de marca sus locales). Para armar menús, el selector de local y los filtros. No decide permisos: eso lo hace has_permission.';
revoke execute on function core.my_scopes() from public;
grant execute on function core.my_scopes() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Suspender y levantar la suspensión (decisión de Joaco del 2026-10-21: pausa sin aprobación)
-- ---------------------------------------------------------------------------
create function core.suspend_user(p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_why   text;
  v_group uuid := core.user_group(p_user_id);
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.suspend_user', v_why, p_user_id, null, v_group);
  end if;
  -- Nunca deja al grupo sin Superadministrador ni Dirección General activos (con bloqueo por grupo).
  perform core.lock_group_roles(v_group);
  v_why := core.group_governance_gap(v_group, null, p_user_id);
  if v_why is not null then
    return core.deny('core.suspend_user', v_why, p_user_id, null, v_group);
  end if;

  perform core.set_change_context(p_reason, 'manual');
  update core.user_profiles
     set status = 'suspended', suspended_at = now(), suspended_by = core.current_actor_id(), suspension_reason = btrim(p_reason)
   where id = p_user_id and status = 'active';
  if not found then
    return jsonb_build_object('result', 'not_active', 'message', 'La cuenta no está activa: no se puede suspender.');
  end if;

  -- Corta el acceso ya mismo, como al desactivar.
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;

  perform audit.log_security_event('account_suspended', 'core.suspend_user', btrim(p_reason), p_user_id, null, null, v_group);
  return jsonb_build_object('result', 'applied', 'message', 'Cuenta suspendida. Se cerraron todas sus sesiones.');
end
$$;
comment on function core.suspend_user(uuid, text) is
  'Suspende una cuenta (pausa): corta el acceso y cierra sus sesiones. Pide users.deactivate sobre todos los roles de la persona y un motivo; nunca sobre uno mismo ni sobre el último Superadministrador o Dirección General. Se levanta con core.lift_suspension, sin aprobación.';
revoke execute on function core.suspend_user(uuid, text) from public;
grant execute on function core.suspend_user(uuid, text) to authenticated;

create function core.lift_suspension(p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_why text;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.lift_suspension', v_why, p_user_id, null, core.user_group(p_user_id));
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update core.user_profiles
     set status = 'active', suspended_at = null, suspended_by = null, suspension_reason = null
   where id = p_user_id and status = 'suspended';
  if not found then
    return jsonb_build_object('result', 'not_suspended', 'message', 'La cuenta no estaba suspendida.');
  end if;
  perform audit.log_security_event('account_unsuspended', 'core.lift_suspension', btrim(p_reason), p_user_id, null, null,
                                   core.user_group(p_user_id));
  return jsonb_build_object('result', 'applied', 'message', 'Suspensión levantada. La persona ya puede volver a entrar.');
end
$$;
comment on function core.lift_suspension(uuid, text) is
  'Levanta la suspensión de una cuenta, sin aprobación (decisión de Joaco del 2026-10-21). Pide users.deactivate sobre todos los roles de la persona y un motivo.';
revoke execute on function core.lift_suspension(uuid, text) from public;
grant execute on function core.lift_suspension(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Selector de local: el último elegido queda en la base (no en el navegador)
-- ---------------------------------------------------------------------------
create function core.set_active_restaurant(p_restaurant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    raise exception 'La sesión no puede operar.' using errcode = '42501';
  end if;
  if p_restaurant_id is not null and not exists (select 1 from core.my_scopes() s where s.restaurant_id = p_restaurant_id) then
    raise exception 'Ese local no es uno de los tuyos.' using errcode = '42501';
  end if;
  -- Columna sin historia (audit.untracked_columns): no se audita.
  update core.user_profiles set last_restaurant_id = p_restaurant_id where id = v_actor;
  return jsonb_build_object('result', 'applied', 'restaurant_id', p_restaurant_id);
end
$$;
comment on function core.set_active_restaurant(uuid) is
  'Guarda el local elegido en el selector (o ninguno, con null). Solo uno de los locales de la sesión (core.my_scopes).';
revoke execute on function core.set_active_restaurant(uuid) from public;
grant execute on function core.set_active_restaurant(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Avisos dentro de la app (decisión de Joaco del 2026-10-21: sin correo)
-- ---------------------------------------------------------------------------
create type core.notification_kind as enum ('approval_requested');
comment on type core.notification_kind is 'Tipo de aviso: approval_requested (una solicitud que la persona puede decidir).';

create table core.notifications (
  id                uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references core.user_profiles (id) on delete restrict,
  group_id          uuid not null references org.groups (id) on delete restrict,
  kind              core.notification_kind not null,
  title             text not null check (length(btrim(title)) between 1 and 200),
  body              text check (body is null or length(body) <= 500),
  link              text check (link is null or link ~ '^/[A-Za-z][A-Za-z0-9/_?=&-]*$'),
  request_id        uuid references workflow.approval_requests (id) on delete restrict,
  read_at           timestamptz,
  created_at        timestamptz not null default now(),
  created_by        uuid references core.actors (id) on delete restrict,
  updated_at        timestamptz not null default now(),
  updated_by        uuid references core.actors (id) on delete restrict,
  deleted_at        timestamptz,
  deleted_by        uuid references core.actors (id) on delete restrict
);
comment on table core.notifications is
  'Avisos dentro de la app para cada persona (por ejemplo, "hay una solicitud que podés decidir"). Los crea la base; cada persona ve y marca como leídos solo los suyos.';
comment on column core.notifications.id is 'Identificador del aviso.';
comment on column core.notifications.recipient_user_id is 'Persona que recibe el aviso.';
comment on column core.notifications.group_id is 'Grupo del aviso.';
comment on column core.notifications.kind is 'Tipo de aviso: approval_requested (una solicitud que la persona puede decidir).';
comment on column core.notifications.title is 'Título del aviso, en español.';
comment on column core.notifications.body is 'Detalle del aviso (por ejemplo, el motivo de la solicitud).';
comment on column core.notifications.link is 'Pantalla de la app a la que lleva el aviso (ruta interna).';
comment on column core.notifications.request_id is 'Solicitud de aprobación del aviso, si corresponde.';
comment on column core.notifications.read_at is 'Cuándo lo leyó. Vacío si no lo leyó. No se audita.';
comment on column core.notifications.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.notifications.created_by is 'Quién lo generó (lo pone la base).';
comment on column core.notifications.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.notifications.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.notifications.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column core.notifications.deleted_by is 'Quién lo borró (lo pone la base).';

create index notifications_recipient_idx on core.notifications (recipient_user_id, created_at desc) where deleted_at is null;
create index notifications_unread_idx on core.notifications (recipient_user_id) where read_at is null and deleted_at is null;
create index notifications_group_idx on core.notifications (group_id);
create index notifications_request_idx on core.notifications (request_id) where request_id is not null;

alter table core.notifications enable row level security;
revoke all on core.notifications from public, anon, authenticated, service_role;
grant select on core.notifications to authenticated;
create policy notifications_select on core.notifications for select to authenticated
  using (recipient_user_id = (select core.current_actor_id()) and (select core.current_session_ok()));
create trigger set_control_columns before insert or update on core.notifications
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on core.notifications
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on core.notifications
  for each statement execute function core.reject_truncate();

-- Leer un aviso no es historia.
set role audit_owner;
create or replace function audit.untracked_columns(p_schema text, p_table text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case
    when p_schema = 'core' and p_table = 'user_profiles' then array['last_seen_at', 'last_restaurant_id']
    when p_schema = 'core' and p_table = 'notifications' then array['read_at']
    else '{}'::text[]
  end
$$;
reset role;

create function core.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_count int;
begin
  if v_actor is null or not core.current_session_ok() then
    raise exception 'La sesión no puede operar.' using errcode = '42501';
  end if;
  update core.notifications set read_at = now()
   where recipient_user_id = v_actor and read_at is null and deleted_at is null
     and (p_ids is null or id = any (p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end
$$;
comment on function core.mark_notifications_read(uuid[]) is
  'Marca como leídos los avisos propios (todos, o los indicados). Devuelve cuántos marcó.';
revoke execute on function core.mark_notifications_read(uuid[]) from public;
grant execute on function core.mark_notifications_read(uuid[]) to authenticated;

-- request_approval avisa a quienes pueden decidir (sección 7): las mismas reglas que decision_blocker,
-- calculadas con user_has_permission_for_scope (la única lógica de permisos).
create or replace function workflow.request_approval(
  p_workflow_code    text,
  p_group_id         uuid,
  p_brand_id         uuid,
  p_restaurant_id    uuid,
  p_subject_user_id  uuid,
  p_entity_id        uuid,
  p_proposed_changes jsonb,
  p_previous_values  jsonb,
  p_reason           text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_wf       workflow.approval_workflows;
  v_id       uuid;
  v_actor    uuid := core.current_actor_id();
  v_scope    core.scope_type := case when p_restaurant_id is not null then 'restaurant'
                                     when p_brand_id is not null then 'brand' else 'group' end::core.scope_type;
  v_excluded uuid[];
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  select * into v_wf
    from workflow.approval_workflows w
   where w.code = p_workflow_code and w.deleted_at is null and w.is_active;
  if not found then
    raise exception 'No existe el tipo de aprobación %.', p_workflow_code using errcode = '22023';
  end if;
  -- No dos pedidos pendientes iguales.
  if exists (select 1 from workflow.approval_requests r
              where r.workflow_id = v_wf.id and r.status = 'pending' and r.deleted_at is null
                and r.subject_user_id is not distinct from p_subject_user_id
                and (r.proposed_changes - 'excluded_approvers' - 'role_permissions')
                    = (p_proposed_changes - 'excluded_approvers' - 'role_permissions')) then
    raise exception 'Ya hay una solicitud pendiente igual.' using errcode = '23505';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into workflow.approval_requests (workflow_id, group_id, brand_id, restaurant_id, requested_by, subject_user_id,
                                          entity_table, entity_id, proposed_changes, previous_values, reason)
  values (v_wf.id, p_group_id, p_brand_id, p_restaurant_id, v_actor, p_subject_user_id,
          v_wf.entity_table, p_entity_id, p_proposed_changes, p_previous_values, btrim(p_reason))
  returning id into v_id;

  select coalesce(array_agg(x::uuid), '{}') into v_excluded
    from jsonb_array_elements_text(coalesce(p_proposed_changes -> 'excluded_approvers', '[]'::jsonb)) as x;
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link, request_id)
  select c.user_id, p_group_id, 'approval_requested', 'Solicitud para decidir: ' || v_wf.name,
         left(btrim(p_reason), 500), '/aprobaciones', v_id
    from (select distinct a.user_id
            from core.user_role_assignments a
            join core.role_permissions rp on rp.role_id = a.role_id and rp.deleted_at is null
            join core.permissions p on p.id = rp.permission_id and p.deleted_at is null and p.code = v_wf.required_permission
           where a.group_id = p_group_id and a.deleted_at is null
             and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
             and (a.scope_type = 'group'
                  or (a.scope_type = 'brand' and a.brand_id = p_brand_id)
                  or (a.scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id))) c
   where (c.user_id is distinct from v_actor or v_wf.allow_self_approval)
     and c.user_id is distinct from p_subject_user_id
     and not c.user_id = any (v_excluded)
     and core.user_has_permission_for_scope(c.user_id, v_wf.required_permission, v_scope, p_group_id, p_brand_id, p_restaurant_id)
     and core.user_has_permission_for_scope(c.user_id, 'approvals.view', v_scope, p_group_id, p_brand_id, p_restaurant_id)
     and (cardinality(coalesce(v_wf.approver_role_codes, '{}')) = 0
          or core.user_has_role_for_scope(c.user_id, v_wf.approver_role_codes, 'group', p_group_id));
  return v_id;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Tabla de ensayo (sección 10): imita una receta para las pruebas 2, 3 y 7
-- ---------------------------------------------------------------------------
create table core.test_documents (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  brand_id       uuid not null,
  restaurant_id  uuid,
  document_key   uuid not null,
  version_number integer not null check (version_number >= 1),
  title          text not null check (length(btrim(title)) between 1 and 120),
  content        text check (content is null or length(content) <= 4000),
  cost           numeric(14, 4) check (cost is null or cost >= 0),
  currency       char(3) not null default 'ARS' check (currency ~ '^[A-Z]{3}$'),
  status         core.version_status not null default 'draft',
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint test_documents_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  constraint test_documents_restaurant_brand_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict
);
comment on table core.test_documents is
  'Documentos de ensayo de la Fase 1 (sección 10 del documento de Soy): imitan una receta con versiones, borrador y costo para probar permisos y auditoría. Se borran al cerrar la Fase 1; en la Fase 2 las pruebas se repiten sobre las recetas reales.';
comment on column core.test_documents.id is 'Identificador de la versión.';
comment on column core.test_documents.group_id is 'Grupo del documento.';
comment on column core.test_documents.brand_id is 'Marca del documento (como una receta estándar de la marca).';
comment on column core.test_documents.restaurant_id is 'Local, si el documento es propio de un local. Vacío si es de toda la marca.';
comment on column core.test_documents.document_key is 'Identifica al documento: todas sus versiones comparten este valor.';
comment on column core.test_documents.version_number is 'Número de versión (1, 2, 3...). Corregir es crear una versión nueva.';
comment on column core.test_documents.title is 'Título del documento.';
comment on column core.test_documents.content is 'Contenido (por ejemplo, los pasos de una receta).';
comment on column core.test_documents.cost is 'Costo del documento. Solo lo ven quienes tienen test_documents.view_costs (el cocinero no).';
comment on column core.test_documents.currency is 'Moneda del costo (ISO 4217).';
comment on column core.test_documents.status is 'Estado de la versión: borrador, en revisión, aprobada, publicada o archivada. Desde aprobada no cambia.';
comment on column core.test_documents.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.test_documents.created_by is 'Quién la creó (lo pone la base).';
comment on column core.test_documents.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.test_documents.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column core.test_documents.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column core.test_documents.deleted_by is 'Quién la borró (lo pone la base).';

create unique index test_documents_version_key on core.test_documents (document_key, version_number);
create unique index test_documents_published_key on core.test_documents (document_key) where status = 'published';
create index test_documents_group_idx on core.test_documents (group_id);
create index test_documents_brand_idx on core.test_documents (brand_id);
create index test_documents_restaurant_idx on core.test_documents (restaurant_id) where restaurant_id is not null;

-- La tabla no se lee directo por la API: solo por la vista sin costos (security.md: el cocinero
-- ve la receta desde una vista sin precios).
alter table core.test_documents enable row level security;
revoke all on core.test_documents from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on core.test_documents
  for each row execute function core.set_control_columns();
create trigger enforce_version_rules before insert or update or delete on core.test_documents
  for each row execute function core.enforce_version_rules();
create trigger log_change after insert or update or delete on core.test_documents
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on core.test_documents
  for each statement execute function core.reject_truncate();

-- La vista filtra igual que lo haría una política: quien ve, ve las versiones publicadas de las
-- marcas y locales a su alcance; quien edita ve también los borradores; el costo solo con view_costs.
create view core.v_test_documents with (security_barrier) as
select d.id, d.group_id, d.brand_id, d.restaurant_id, d.document_key, d.version_number, d.title, d.content,
       case when (d.restaurant_id is null and d.brand_id in (select core.permitted_brand_ids('test_documents.view_costs')))
              or d.restaurant_id in (select core.permitted_restaurant_ids('test_documents.view_costs'))
            then d.cost end as cost,
       d.currency, d.status, d.created_at, d.created_by, d.updated_at, d.updated_by
  from core.test_documents d
 where d.deleted_at is null
   and d.brand_id in (select core.visible_brand_ids('test_documents.view'))
   and (d.restaurant_id is null or d.restaurant_id in (select core.permitted_restaurant_ids('test_documents.view')))
   and (d.status = 'published'
        or (d.restaurant_id is null and d.brand_id in (select core.permitted_brand_ids('test_documents.edit')))
        or d.restaurant_id in (select core.permitted_restaurant_ids('test_documents.edit')));
comment on view core.v_test_documents is
  'Documentos de ensayo que la sesión puede ver: publicados a su alcance (y borradores si puede editar). El costo sale vacío sin test_documents.view_costs.';
do $$
declare
  c record;
begin
  for c in select a.attname, col_description('core.test_documents'::regclass, a.attnum) as d
             from pg_attribute a
            where a.attrelid = 'core.v_test_documents'::regclass and a.attnum > 0 and not a.attisdropped loop
    execute format('comment on column core.v_test_documents.%I is %L', c.attname,
                   case when c.attname = 'cost' then 'Costo del documento. Vacío si la sesión no tiene test_documents.view_costs.'
                        else (select col_description('core.test_documents'::regclass, t.attnum)
                                from pg_attribute t where t.attrelid = 'core.test_documents'::regclass and t.attname = c.attname) end);
  end loop;
end
$$;
revoke all on core.v_test_documents from public, anon, authenticated, service_role;
grant select on core.v_test_documents to authenticated;

create function core.create_test_document_draft(p_brand_id uuid, p_title text, p_reason text,
                                                p_restaurant_id uuid default null, p_content text default null,
                                                p_cost numeric default null, p_document_key uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group   uuid;
  v_allowed boolean;
  v_costs   boolean;
  v_version int := 1;
  v_prev    core.test_documents;
  v_id      uuid;
begin
  select b.group_id into v_group from org.brands b where b.id = p_brand_id and b.deleted_at is null;
  v_allowed := v_group is not null and case when p_restaurant_id is null then core.has_permission_in_brand('test_documents.edit', p_brand_id)
                                            else core.has_permission('test_documents.edit', p_restaurant_id) end;
  if not coalesce(v_allowed, false) then
    return core.deny('core.create_test_document_draft', 'No tenés permiso para crear borradores en ese lugar.', null,
                     jsonb_build_object('brand_id', p_brand_id, 'restaurant_id', p_restaurant_id), v_group, p_brand_id, p_restaurant_id);
  end if;
  v_costs := case when p_restaurant_id is null then core.has_permission_in_brand('test_documents.view_costs', p_brand_id)
                  else core.has_permission('test_documents.view_costs', p_restaurant_id) end;
  -- Corregir = versión nueva del mismo documento, con el mismo lugar.
  if p_document_key is not null then
    select * into v_prev from core.test_documents
     where document_key = p_document_key order by version_number desc limit 1 for update;
    if not found or v_prev.brand_id <> p_brand_id or v_prev.restaurant_id is distinct from p_restaurant_id then
      raise exception 'Ese documento no existe en ese lugar.' using errcode = '22023';
    end if;
    v_version := v_prev.version_number + 1;
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into core.test_documents (group_id, brand_id, restaurant_id, document_key, version_number, title, content, cost)
  values (v_group, p_brand_id, p_restaurant_id, coalesce(p_document_key, gen_random_uuid()), v_version, btrim(p_title), p_content,
          -- Quien no ve costos no los carga: la versión nueva conserva el costo de la anterior.
          case when v_costs then p_cost else v_prev.cost end)
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'id', v_id, 'version_number', v_version, 'message', 'Borrador creado.');
end
$$;
comment on function core.create_test_document_draft(uuid, text, text, uuid, text, numeric, uuid) is
  'Crea un borrador de documento de ensayo (o una versión nueva de uno existente). Pide test_documents.edit en ese lugar y un motivo. El costo solo lo carga quien puede verlo.';

create function core.request_test_document_review(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d core.test_documents;
begin
  select * into v_d from core.test_documents where id = p_id and deleted_at is null for update;
  if not found or not (case when v_d.restaurant_id is null then core.has_permission_in_brand('test_documents.edit', v_d.brand_id)
                           else core.has_permission('test_documents.edit', v_d.restaurant_id) end) then
    return core.deny('core.request_test_document_review', 'No podés pedir la revisión de ese documento.', null,
                     jsonb_build_object('id', p_id), v_d.group_id, v_d.brand_id, v_d.restaurant_id);
  end if;
  if v_d.status <> 'draft' then
    raise exception 'Solo se pide revisión de un borrador.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update core.test_documents set status = 'in_review' where id = p_id;
  return jsonb_build_object('result', 'applied', 'message', 'Revisión pedida.');
end
$$;
comment on function core.request_test_document_review(uuid, text) is
  'Pasa un borrador de ensayo a revisión. Pide test_documents.edit.';

create function core.publish_test_document(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_d core.test_documents;
begin
  select * into v_d from core.test_documents where id = p_id and deleted_at is null for update;
  if not found or not (case when v_d.restaurant_id is null then core.has_permission_in_brand('test_documents.publish', v_d.brand_id)
                           else core.has_permission('test_documents.publish', v_d.restaurant_id) end) then
    return core.deny('core.publish_test_document', 'No tenés permiso para publicar ese documento.', null,
                     jsonb_build_object('id', p_id), v_d.group_id, v_d.brand_id, v_d.restaurant_id);
  end if;
  if v_d.status <> 'in_review' then
    raise exception 'Solo se publica un documento en revisión.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Una sola transacción: la versión vigente se archiva y la nueva se aprueba y publica.
  update core.test_documents set status = 'archived'
   where document_key = v_d.document_key and status = 'published';
  update core.test_documents set status = 'approved' where id = p_id;
  update core.test_documents set status = 'published' where id = p_id;
  return jsonb_build_object('result', 'applied', 'message', 'Documento publicado.');
end
$$;
comment on function core.publish_test_document(uuid, text) is
  'Aprueba y publica una versión de ensayo en revisión, y archiva la que estaba vigente. Pide test_documents.publish; sin permiso devuelve denied y queda en el registro de seguridad.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'core.create_test_document_draft(uuid, text, text, uuid, text, numeric, uuid)',
    'core.request_test_document_review(uuid, text)',
    'core.publish_test_document(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
