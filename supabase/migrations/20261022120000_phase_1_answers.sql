-- Respuestas de Joaco a las preguntas abiertas de la Fase 1 (ADR-0015, 2026-10-22).
--   1. Quien mandó un documento de ensayo a revisión no lo publica: lo hace otra persona.
--   2. El primer y el último acceso, quién invitó y los motivos de suspensión o baja los ve solo
--      quien administra a la persona: permiso nuevo users.view_admin_details (Superadmin, Dirección
--      General, Director de Marca y Gerente) sobre TODOS sus roles. La tabla deja de entregar esas
--      columnas por la API, y la bandeja oculta el motivo de la baja a quien no administra ni decide.
--      El historial (audit.view) los sigue mostrando: es para auditar (excepción decidida por Joaco).
--   5. Los KPI de estado del tablero se comparan con hace 7 días.
--   9. El lugar de la membresía limita los roles: de todo el grupo, cualquier rol; de una marca,
--      roles de esa marca o de sus locales; de un local, solo roles de ese local.
-- Las funciones se recrean iguales a su última versión, más el cambio de cada respuesta.

-- ---------------------------------------------------------------------------
-- 1. Permiso para ver los datos de administración de una persona (respuesta 2)
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Respuesta 2 de Joaco: quién ve los datos de administración (ADR-0015)', 'maintenance');
  insert into core.permissions (code, module, description, is_sensitive) values
    ('users.view_admin_details', 'users',
     'Ver el primer y el último acceso de una persona, quién la invitó y los motivos de su suspensión o baja.', false);
  -- Los que administran personas (users.manage) y Dirección General.
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values ('superadmin'), ('general_management'), ('brand_director'), ('restaurant_manager')) as m (role_code)
    join core.roles r on r.code = m.role_code
    join core.permissions p on p.code = 'users.view_admin_details';
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Funciones de apoyo
-- ---------------------------------------------------------------------------
create function core.membership_covers(p_user_id uuid, p_scope_type core.scope_type, p_group_id uuid,
                                       p_brand_id uuid default null, p_restaurant_id uuid default null,
                                       p_except_membership_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- Una membresía vigente y sin fecha de fin cuyo lugar contiene el del rol.
  select exists (
    select 1 from core.user_memberships m
     where m.user_id = p_user_id and m.group_id = p_group_id and m.deleted_at is null
       and m.starts_at <= now() and m.ends_at is null
       and (p_except_membership_id is null or m.id <> p_except_membership_id)
       and (m.brand_id is null
            or (p_scope_type <> 'group' and m.brand_id = p_brand_id
                and (m.restaurant_id is null or (p_scope_type = 'restaurant' and m.restaurant_id = p_restaurant_id)))))
$$;
comment on function core.membership_covers(uuid, core.scope_type, uuid, uuid, uuid, uuid) is
  'Interna. Si la persona tiene una membresía vigente, sin fecha de fin, cuyo lugar contiene el del rol: de todo el grupo (cualquier rol), de la marca (roles de esa marca o de sus locales) o del local (solo ese local). p_except_membership_id deja afuera una membresía (la que se está terminando).';

create function core.can_administer_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select core.current_actor_id() is not null and core.current_session_ok() and (
    p_user_id = core.current_actor_id()
    -- Con roles: users.view_admin_details sobre TODOS sus roles vigentes (como cannot_act_on_user).
    or (exists (select 1 from core.user_role_assignments a
                 where a.user_id = p_user_id and a.deleted_at is null
                   and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now()))
        and not exists (select 1 from core.user_role_assignments a
                         where a.user_id = p_user_id and a.deleted_at is null
                           and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
                           and not core.has_permission_for_scope('users.view_admin_details', a.scope_type, a.group_id,
                                                                 a.brand_id, a.restaurant_id)))
    -- Sin roles: el permiso sobre el lugar donde trabaja.
    or (not exists (select 1 from core.user_role_assignments a
                     where a.user_id = p_user_id and a.deleted_at is null
                       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now()))
        and exists (select 1 from core.user_memberships m
                     where m.user_id = p_user_id and m.deleted_at is null
                       and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
                       and core.has_permission_for_scope('users.view_admin_details',
                             case when m.restaurant_id is not null then 'restaurant'
                                  when m.brand_id is not null then 'brand' else 'group' end::core.scope_type,
                             m.group_id, m.brand_id, m.restaurant_id))))
$$;
comment on function core.can_administer_user(uuid) is
  'Interna. Si la sesión administra a la persona: users.view_admin_details sobre todos sus roles vigentes (o, si no tiene roles, sobre el lugar donde trabaja). Cada uno se ve a sí mismo. Decide quién ve el primer y el último acceso, quién la invitó y los motivos de suspensión o baja.';

revoke execute on function core.membership_covers(uuid, core.scope_type, uuid, uuid, uuid, uuid) from public;
revoke execute on function core.can_administer_user(uuid) from public;

-- El local elegido en el selector: ahora por función (la columna deja de leerse por la API).
create function core.my_active_restaurant()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.last_restaurant_id from core.user_profiles p
   where p.id = core.current_actor_id() and core.current_session_ok()
$$;
comment on function core.my_active_restaurant() is
  'El último local que eligió la sesión en el selector (vacío si no eligió o si la sesión no puede operar).';
revoke execute on function core.my_active_restaurant() from public;
grant execute on function core.my_active_restaurant() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Lo que la API deja de entregar (respuesta 2)
-- ---------------------------------------------------------------------------
-- Personas: sin el primer y el último acceso, quién invitó, el local elegido ni los motivos.
revoke select on core.user_profiles from authenticated;
grant select (id, first_name, last_name, email, status, deactivated_at, suspended_at, locked_until, username,
              job_title, area_id, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by)
  on core.user_profiles to authenticated;
-- Solicitudes: el "antes" (que puede traer el motivo de una baja) sale solo por workflow.inbox.
revoke select on workflow.approval_requests from authenticated;
grant select (id, workflow_id, group_id, brand_id, restaurant_id, requested_by, subject_user_id, proposed_changes,
              reason, status, resolved_at, resolved_by, resolution_comment, entity_table, entity_id, requested_at,
              created_at, created_by, updated_at, updated_by, deleted_at, deleted_by)
  on workflow.approval_requests to authenticated;

-- ---------------------------------------------------------------------------
-- 4. La regla de la membresía, también en la base (para cualquier camino de escritura)
-- ---------------------------------------------------------------------------
create function core.enforce_membership_place()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'user_role_assignments' then
    -- Un rol que empieza a valer necesita una membresía que cubra su lugar. "for share" la bloquea
    -- hasta el commit, para que no se cruce con otra transacción que la esté terminando.
    if new.deleted_at is null and (new.valid_until is null or new.valid_until > now())
       and (tg_op = 'INSERT' or old.deleted_at is not null) then
      perform 1 from core.user_memberships m
       where m.user_id = new.user_id and m.group_id = new.group_id and m.deleted_at is null
         and m.starts_at <= now() and m.ends_at is null
         and (m.brand_id is null
              or (new.scope_type <> 'group' and m.brand_id = new.brand_id
                  and (m.restaurant_id is null or (new.scope_type = 'restaurant' and m.restaurant_id = new.restaurant_id))))
       for share;
      if not found then
        raise exception 'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.'
          using errcode = '23514';
      end if;
    end if;
  elsif tg_table_name = 'user_memberships' then
    -- Terminar o borrar una membresía no puede dejar roles vigentes sin una membresía que los cubra.
    if old.deleted_at is null and old.ends_at is null and (new.deleted_at is not null or new.ends_at is not null) then
      -- Todas las membresías de la persona en el grupo, bloqueadas hasta el commit: así dos
      -- transacciones no terminan a la vez las dos membresías que cubren un mismo rol.
      perform 1 from core.user_memberships m
       where m.user_id = new.user_id and m.group_id = new.group_id and m.id <> new.id
       for update;
      if exists (
           select 1 from core.user_role_assignments a
            where a.user_id = new.user_id and a.group_id = new.group_id and a.deleted_at is null
              and (a.valid_until is null or a.valid_until > now())
              and not core.membership_covers(a.user_id, a.scope_type, a.group_id, a.brand_id, a.restaurant_id, new.id)) then
        raise exception 'No se puede terminar esta membresía: la persona tiene roles en ese lugar que quedarían sin membresía. Primero hay que quitarle esos roles.'
          using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end
$$;
comment on function core.enforce_membership_place() is
  'Trigger (BEFORE INSERT OR UPDATE) de user_role_assignments y user_memberships: un rol vigente siempre tiene una membresía que cubre su lugar (respuesta 9 de Joaco, ADR-0015).';
revoke execute on function core.enforce_membership_place() from public;

-- Corre después de validate_identity (orden alfabético), que ya exige ser miembro del grupo y
-- vuelve inmutables el lugar de una membresía y el alcance de una asignación.
create trigger validate_membership_place before insert or update on core.user_role_assignments
  for each row execute function core.enforce_membership_place();
create trigger validate_membership_place before update on core.user_memberships
  for each row execute function core.enforce_membership_place();

-- Los datos que ya existen tienen que cumplir la regla.
do $$
begin
  if exists (
    select 1 from core.user_role_assignments a
     where a.deleted_at is null and (a.valid_until is null or a.valid_until > now())
       and not core.membership_covers(a.user_id, a.scope_type, a.group_id, a.brand_id, a.restaurant_id)) then
    raise exception 'Hay roles vigentes sin una membresía que cubra su lugar: hay que corregirlos antes de aplicar esta migración.';
  end if;
end
$$;

-- La columna para la respuesta 1.
alter table core.test_documents add column review_requested_by uuid references core.user_profiles (id) on delete restrict;
comment on column core.test_documents.review_requested_by is
  'Quién mandó la versión a revisión (lo pone la base). Esa persona no la puede publicar. Vacía en las versiones que estaban en revisión antes del 2026-10-22.';
create index test_documents_review_requested_by_idx on core.test_documents (review_requested_by)
  where review_requested_by is not null;


-- ---------------------------------------------------------------------------
-- 5. El lugar de la membresía limita los roles (respuesta 9)
-- ---------------------------------------------------------------------------
create or replace function core.assign_role(p_user_id uuid, p_role_code text, p_scope_type core.scope_type, p_group_id uuid,
                                            p_brand_id uuid default null, p_restaurant_id uuid default null,
                                            p_valid_until timestamptz default null, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor      uuid := core.current_actor_id();
  v_role       core.roles;
  v_missing    text[];
  v_superadmin boolean;
  v_workflow   text;
  v_details    jsonb;
  v_request    uuid;
  v_assignment uuid;
begin
  v_details := jsonb_build_object('role', p_role_code, 'scope_type', p_scope_type, 'group_id', p_group_id,
                                  'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id);
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  select * into v_role from core.roles where code = p_role_code and deleted_at is null;
  if not found then
    raise exception 'No existe el rol %.', p_role_code using errcode = '22023';
  end if;

  -- Permisos primero: no se revela nada de la persona ni de la estructura sin permiso.
  -- (Un alcance que no cuadra con la estructura también da "sin permiso".)
  if not core.has_permission_for_scope('roles.assign', p_scope_type, p_group_id, p_brand_id, p_restaurant_id) then
    return core.deny('core.assign_role', 'No tenés permiso para dar roles en ese lugar.', p_user_id, v_details,
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;
  if p_user_id = v_actor then
    return core.deny('core.assign_role', 'Nadie se puede dar roles a sí mismo.', p_user_id, v_details,
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;
  v_superadmin := core.has_role_for_scope(array['superadmin'], 'group', p_group_id);
  v_missing := core.missing_permissions_for_role(v_role.id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
  if cardinality(v_missing) > 0 and not v_superadmin then
    return core.deny('core.assign_role',
                     'No podés dar un rol con permisos que vos no tenés en ese lugar: ' || array_to_string(v_missing, ', ') || '.',
                     p_user_id, v_details || jsonb_build_object('missing_permissions', v_missing),
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;

  -- Errores de datos.
  if v_role.code in ('superadmin', 'general_management') and p_scope_type <> 'group' then
    raise exception 'El rol % solo se da para todo el grupo.', v_role.name using errcode = '23514';
  end if;
  -- Sin vencimiento: si no, el grupo podría quedarse sin ellos de un día para el otro.
  if v_role.code in ('superadmin', 'general_management') and p_valid_until is not null then
    raise exception 'El rol % no lleva fecha de vencimiento.', v_role.name using errcode = '23514';
  end if;
  perform core.check_scope(p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
  if not exists (select 1 from core.user_profiles u where u.id = p_user_id and u.status = 'active' and u.deleted_at is null) then
    raise exception 'La persona no existe o su cuenta no está activa.' using errcode = '23514';
  end if;
  if not exists (select 1 from core.user_memberships m
                  where m.user_id = p_user_id and m.group_id = p_group_id and m.deleted_at is null
                    and m.starts_at <= now() and m.ends_at is null) then
    raise exception 'La persona no es miembro de ese grupo: primero hay que sumarla al grupo.' using errcode = '23514';
  end if;
  -- El lugar de la membresía limita los roles (respuesta 9 de Joaco).
  if not core.membership_covers(p_user_id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id) then
    raise exception 'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.'
      using errcode = '23514';
  end if;
  if exists (select 1 from core.user_role_assignments a
              where a.user_id = p_user_id and a.role_id = v_role.id and a.group_id = p_group_id
                and a.brand_id is not distinct from p_brand_id and a.restaurant_id is not distinct from p_restaurant_id
                and a.deleted_at is null) then
    raise exception 'La persona ya tiene ese rol en ese lugar.' using errcode = '23505';
  end if;
  perform core.check_person_separation(p_user_id, v_role.id, p_group_id);

  v_workflow := case
    when v_role.code = 'superadmin' then 'core.assign_superadmin'
    when cardinality(v_missing) > 0 then 'core.assign_by_superadmin'   -- excepción del superadmin
    when core.is_sensitive_role(v_role.id) then 'core.assign_sensitive_role'
  end;

  if v_workflow is not null then
    v_request := workflow.request_approval(v_workflow, p_group_id, p_brand_id, p_restaurant_id, p_user_id, null,
      jsonb_build_object('user_id', p_user_id, 'role_id', v_role.id, 'role_code', v_role.code, 'scope_type', p_scope_type,
                         'group_id', p_group_id, 'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id,
                         'valid_until', p_valid_until, 'role_permissions', to_jsonb(core.role_permission_codes(v_role.id))),
      -- Antes: los roles vigentes de la persona en el lugar del pedido (no los de otras marcas o
      -- locales, que quien ve la solicitud quizás no puede ver; revisión de seguridad, m3).
      jsonb_build_object('roles', coalesce((
        select jsonb_agg(r.code order by r.level)
          from core.user_role_assignments a join core.roles r on r.id = a.role_id
         where a.user_id = p_user_id and a.group_id = p_group_id and a.deleted_at is null
           and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
           and (p_scope_type = 'group' or a.brand_id = p_brand_id)
           and (p_scope_type <> 'restaurant' or a.restaurant_id = p_restaurant_id)), '[]'::jsonb)),
      p_reason);
    return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                              'message', 'Queda pendiente hasta que otra persona lo apruebe.');
  end if;

  perform core.set_change_context(p_reason, 'manual');
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_until)
  values (p_user_id, v_role.id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id, p_valid_until)
  returning id into v_assignment;
  return jsonb_build_object('result', 'applied', 'assignment_id', v_assignment, 'message', 'Rol asignado.');
end
$$;

create or replace function core.apply_role_assignment(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req  workflow.approval_requests := workflow.approved_request(p_request_id);
  v_code text;
  v_p    jsonb := v_req.proposed_changes;
  v_role uuid := (v_req.proposed_changes ->> 'role_id')::uuid;
  v_scope core.scope_type := (v_req.proposed_changes ->> 'scope_type')::core.scope_type;
  v_brand uuid := (v_req.proposed_changes ->> 'brand_id')::uuid;
  v_rest  uuid := (v_req.proposed_changes ->> 'restaurant_id')::uuid;
begin
  select w.code into v_code from workflow.approval_workflows w where w.id = v_req.workflow_id;

  -- Quien pidió todavía puede pedirlo.
  if v_code in ('core.assign_superadmin', 'core.assign_by_superadmin') then
    if not core.user_has_role_for_scope(v_req.requested_by, array['superadmin'], 'group', v_req.group_id) then
      perform workflow.cannot_apply('quien la pidió ya no es Superadministrador');
    end if;
  elsif not core.user_has_permission_for_scope(v_req.requested_by, 'roles.assign', v_scope, v_req.group_id, v_brand, v_rest)
     or cardinality(core.user_missing_permissions_for_role(v_req.requested_by, v_role, v_scope, v_req.group_id, v_brand, v_rest)) > 0 then
    perform workflow.cannot_apply('quien la pidió ya no tiene permiso para dar ese rol');
  end if;

  -- Lo que se aprobó es lo que se aplica: el rol no cambió de permisos desde el pedido.
  if to_jsonb(core.role_permission_codes(v_role)) is distinct from v_p -> 'role_permissions' then
    perform workflow.cannot_apply('los permisos del rol cambiaron desde que se pidió');
  end if;
  if not exists (select 1 from core.user_profiles u
                  where u.id = (v_p ->> 'user_id')::uuid and u.status = 'active' and u.deleted_at is null) then
    perform workflow.cannot_apply('la persona ya no tiene la cuenta activa');
  end if;
  -- El lugar sigue vigente y abierto, y la persona no junta aprobar con administrar la seguridad.
  perform core.check_scope(v_scope, v_req.group_id, v_brand, v_rest);
  perform core.check_person_separation((v_p ->> 'user_id')::uuid, v_role, v_req.group_id);

  -- La membresía pudo terminar mientras la solicitud esperaba.
  if not core.membership_covers((v_p ->> 'user_id')::uuid, v_scope, v_req.group_id, v_brand, v_rest) then
    perform workflow.cannot_apply('la persona ya no trabaja en ese lugar');
  end if;

  perform core.set_change_context('Rol aprobado (solicitud ' || p_request_id || ')', 'manual');
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_until)
  values ((v_p ->> 'user_id')::uuid, v_role, v_scope, v_req.group_id, v_brand, v_rest, (v_p ->> 'valid_until')::timestamptz);
end
$$;

create or replace function org.apply_transfer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_p     jsonb := v_req.proposed_changes;
  v_old   org.restaurants;
  v_new   uuid;
  v_brand uuid := (v_req.proposed_changes ->> 'target_brand_id')::uuid;
  v_code  text;
begin
  if not core.user_has_permission_for_scope(v_req.requested_by, 'org.transfer', 'group', v_req.group_id) then
    perform workflow.cannot_apply('quien lo pidió ya no puede traspasar locales');
  end if;
  select * into v_old from org.restaurants where id = (v_p ->> 'restaurant_id')::uuid for update;
  if v_old.deleted_at is not null or v_old.status <> 'active' then
    perform workflow.cannot_apply('el local ya no está operando');
  end if;
  if not exists (select 1 from org.brands b
                  where b.id = v_brand and b.group_id = v_old.group_id and b.deleted_at is null and b.status = 'active') then
    perform workflow.cannot_apply('la marca de destino ya no está vigente');
  end if;
  if exists (select 1 from org.restaurants x
              where x.brand_id = v_brand and x.deleted_at is null and lower(x.name) = lower(v_p ->> 'new_name')) then
    perform workflow.cannot_apply('ya hay un local con ese nombre en la marca de destino');
  end if;
  perform core.lock_group_roles(v_old.group_id);
  perform core.set_change_context('Traspaso de local aprobado (solicitud ' || p_request_id || ')', 'manual');

  -- El código corto pasa al local nuevo.
  v_code := v_old.code;
  if v_code is not null then
    update org.restaurants set code = null where id = v_old.id;
  end if;

  insert into org.restaurants (group_id, brand_id, name, code, address, locality, legal_name, tax_id, phone,
                               opened_on, time_zone, predecessor_id)
  values (v_old.group_id, v_brand, v_p ->> 'new_name', v_code, v_old.address, v_old.locality, v_old.legal_name,
          v_old.tax_id, v_old.phone, v_old.opened_on, v_old.time_zone, v_old.id)
  returning id into v_new;

  insert into org.areas (group_id, restaurant_id, name)
  select a.group_id, v_new, a.name from org.areas a where a.restaurant_id = v_old.id and a.deleted_at is null;

  -- Quienes pasan con su rol trabajan en el local nuevo (respuesta 9): si su membresía era del
  -- local viejo o de la marca vieja, se les suma una del local nuevo.
  insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
  select distinct a.user_id, a.group_id, v_brand, v_new
    from core.user_role_assignments a
    join core.user_profiles u on u.id = a.user_id and u.status = 'active' and u.deleted_at is null
   where a.restaurant_id = v_old.id and a.deleted_at is null
     and (a.valid_until is null or a.valid_until > now())
     and not core.membership_covers(a.user_id, 'restaurant', a.group_id, v_brand, v_new);

  -- Los roles del local viejo pasan al nuevo (los vigentes y los que empiezan más adelante, con
  -- sus mismas fechas); los de personas bloqueadas y los ya vencidos solo se quitan.
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_from, valid_until)
  select a.user_id, a.role_id, 'restaurant', a.group_id, v_brand, v_new, greatest(a.valid_from, now()), a.valid_until
    from core.user_role_assignments a
    join core.user_profiles u on u.id = a.user_id and u.status = 'active' and u.deleted_at is null
   where a.restaurant_id = v_old.id and a.deleted_at is null
     and (a.valid_until is null or a.valid_until > now());
  update core.user_role_assignments set deleted_at = now() where restaurant_id = v_old.id and deleted_at is null;
  -- Las membresías del local viejo terminan con él (una que empezó en esta misma operación no
  -- puede terminar en el mismo instante: se borra).
  update core.user_memberships set deleted_at = now()
   where restaurant_id = v_old.id and deleted_at is null and ends_at is null and starts_at >= now();
  update core.user_memberships set ends_at = now()
   where restaurant_id = v_old.id and deleted_at is null and ends_at is null;

  update org.restaurants set status = 'inactive' where id = v_old.id;
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Quien mandó a revisión no publica (respuesta 1)
-- ---------------------------------------------------------------------------
create or replace view core.v_test_documents with (security_barrier) as
select d.id, d.group_id, d.brand_id, d.restaurant_id, d.document_key, d.version_number, d.title, d.content,
       case when (d.restaurant_id is null and d.brand_id in (select core.permitted_brand_ids('test_documents.view_costs')))
              or d.restaurant_id in (select core.permitted_restaurant_ids('test_documents.view_costs'))
            then d.cost end as cost,
       d.currency, d.status, d.created_at, d.created_by, d.updated_at, d.updated_by,
       d.review_requested_by
  from core.test_documents d
 where d.deleted_at is null
   and d.brand_id in (select core.visible_brand_ids('test_documents.view'))
   and (d.restaurant_id is null or d.restaurant_id in (select core.permitted_restaurant_ids('test_documents.view')))
   and (d.status = 'published'
        or (d.restaurant_id is null and d.brand_id in (select core.permitted_brand_ids('test_documents.edit')))
        or d.restaurant_id in (select core.permitted_restaurant_ids('test_documents.edit')));

create or replace function core.request_test_document_review(p_id uuid, p_reason text)
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
  update core.test_documents set status = 'in_review', review_requested_by = core.current_actor_id() where id = p_id;
  return jsonb_build_object('result', 'applied', 'message', 'Revisión pedida.');
end
$$;

create or replace function core.publish_test_document(p_id uuid, p_reason text)
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
  -- Quien lo mandó a revisión no lo publica: lo hace otra persona (respuesta 1 de Joaco).
  if v_d.review_requested_by = core.current_actor_id() then
    return core.deny('core.publish_test_document', 'Lo mandaste vos a revisión: lo tiene que publicar otra persona.', null,
                     jsonb_build_object('id', p_id), v_d.group_id, v_d.brand_id, v_d.restaurant_id);
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

-- ---------------------------------------------------------------------------
-- 7. Ficha, lista y bandeja: los datos de administración, solo para quien administra (respuesta 2)
-- ---------------------------------------------------------------------------
create or replace function core.user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p     core.user_profiles;
  v_group uuid;
  v_admin boolean;
begin
  if not core.current_session_ok() or not core.can_view_user(p_user_id) then
    return null;
  end if;
  select * into v_p from core.user_profiles where id = p_user_id and deleted_at is null;
  if not found then
    return null;
  end if;
  v_group := core.user_group(p_user_id);
  -- El último acceso, quién invitó y los motivos los ve solo quien administra a la persona
  -- (respuesta 2 de Joaco).
  v_admin := core.can_administer_user(p_user_id);
  return jsonb_build_object(
    'id', v_p.id,
    'username', v_p.username,
    'job_title', v_p.job_title,
    'area_id', v_p.area_id,
    'area_name', (select ar.name || ' · ' || r.name from org.areas ar join org.restaurants r on r.id = ar.restaurant_id where ar.id = v_p.area_id),
    'can_view_admin_details', v_admin,
    'activated_at', case when v_admin then v_p.activated_at end,
    'last_seen_at', case when v_admin then v_p.last_seen_at end,
    'invited_by_name', case when v_admin then core.display_name(v_p.invited_by) end,
    'status', v_p.status,
    'suspended_at', v_p.suspended_at,
    'suspension_reason', case when v_admin then v_p.suspension_reason end,
    'suspended_by_name', case when v_admin then core.display_name(v_p.suspended_by) end,
    'deactivated_at', v_p.deactivated_at,
    'deactivation_reason', case when v_admin then v_p.deactivation_reason end,
    'deactivated_by_name', case when v_admin then core.display_name(v_p.deactivated_by) end,
    'workplaces', coalesce((
      select jsonb_agg(jsonb_build_object('group_name', g.name, 'brand_name', b.name, 'restaurant_name', r.name,
                                          'starts_at', m.starts_at, 'ends_at', m.ends_at) order by m.starts_at)
        from core.user_memberships m
        join org.groups g on g.id = m.group_id
        left join org.brands b on b.id = m.brand_id
        left join org.restaurants r on r.id = m.restaurant_id
       where m.user_id = p_user_id and m.deleted_at is null and (m.ends_at is null or m.ends_at > now())), '[]'::jsonb),
    -- Lo que hizo la persona, dentro de lo que la sesión puede ver del historial.
    'can_view_activity', exists (select 1 from core.actor_grants('audit.view')),
    'recent_activity', coalesce((
      select jsonb_agg(jsonb_build_object('occurred_at', h.occurred_at, 'action', h.action, 'table_name', h.table_schema || '.' || h.table_name,
                                          'reason', h.reason, 'place_name', h.place_name) order by h.sequence_number desc)
        from core.audit_history(20, null, null, null, null, p_user_id) h), '[]'::jsonb),
    -- Intentos rechazados: solo con security.view del grupo de la persona.
    'can_view_security', coalesce(core.has_permission_in_group('security.view', v_group), false),
    'rejected_attempts', case when coalesce(core.has_permission_in_group('security.view', v_group), false) then coalesce((
      select jsonb_agg(jsonb_build_object('occurred_at', s.occurred_at, 'event_type', s.event_type, 'operation', s.operation,
                                          'reason', s.reason) order by s.occurred_at desc)
        from (select * from audit.authentication_security_events s
               where (s.user_id = p_user_id or s.actor_id = p_user_id)
                 and s.event_type in ('login_failed', 'operation_denied', 'account_locked')
               order by s.occurred_at desc limit 20) s), '[]'::jsonb) end
  );
end
$$;

create or replace function core.users_dashboard(p_search text default null, p_brand_id uuid default null,
                                     p_restaurant_id uuid default null, p_status text default null,
                                     p_after_key text default null, p_after_id uuid default null,
                                     p_limit integer default 25, p_user_id uuid default null,
                                     p_role_code text default null, p_area_id uuid default null)
returns table (id uuid, first_name text, last_name text, email text, status core.account_status, locked boolean,
               roles jsonb, sort_key text, job_title text, area_name text, last_seen_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(lower(btrim(p_search)), '');
  v_r      org.restaurants;
  v_b      org.brands;
begin
  if p_status is not null and p_status not in ('active', 'suspended', 'deactivated', 'locked') then
    raise exception 'Filtro de estado inválido.' using errcode = '22023';
  end if;
  if (p_after_key is null) <> (p_after_id is null) then
    raise exception 'La página siguiente necesita la clave y el id.' using errcode = '22023';
  end if;
  if p_restaurant_id is not null then
    select * into v_r from org.restaurants where org.restaurants.id = p_restaurant_id;
  end if;
  if p_brand_id is not null then
    select * into v_b from org.brands where org.brands.id = p_brand_id;
  end if;

  return query
  with visible as (select v as user_id from core.visible_user_ids() as v),
       visible_assignments as (select v as assignment_id from core.visible_assignment_ids() as v)
  select p.id, p.first_name, p.last_name, p.email, p.status,
         coalesce(p.locked_until > now(), false),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'assignment_id', a.id, 'role_code', r.code, 'role_name', r.name, 'scope_type', a.scope_type,
                    'scope_name', coalesce(rs.name, b.name, g.name))
                  order by r.level)
             from core.user_role_assignments a
             -- Solo los roles que la sesión puede ver (la misma regla que la RLS).
             join visible_assignments va on va.assignment_id = a.id
             join core.roles r on r.id = a.role_id
             join org.groups g on g.id = a.group_id
             left join org.brands b on b.id = a.brand_id
             left join org.restaurants rs on rs.id = a.restaurant_id
            where a.user_id = p.id and a.deleted_at is null
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())), '[]'::jsonb),
         lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email) as sort_key,
         p.job_title,
         (select ar.name || ' · ' || rs.name from org.areas ar join org.restaurants rs on rs.id = ar.restaurant_id where ar.id = p.area_id),
         -- El último acceso solo para quien administra a la persona (respuesta 2 de Joaco).
         case when core.can_administer_user(p.id) then p.last_seen_at end
    from core.user_profiles p
    join visible vis on vis.user_id = p.id
   where p.deleted_at is null
     and (p_user_id is null or p.id = p_user_id)
     and (v_search is null
          or position(v_search in lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.email
                                        || ' ' || coalesce(p.username, '') || ' ' || coalesce(p.job_title, ''))) > 0)
     and (p_status is null
          or (p_status = 'active' and p.status = 'active' and (p.locked_until is null or p.locked_until <= now()))
          or (p_status = 'suspended' and p.status = 'suspended')
          or (p_status = 'deactivated' and p.status = 'deactivated')
          or (p_status = 'locked' and p.locked_until > now()))
     and (p_area_id is null or p.area_id = p_area_id)
     -- Por rol: solo entre los roles que la sesión puede ver.
     and (p_role_code is null or exists (
           select 1 from core.user_role_assignments a
             join visible_assignments va on va.assignment_id = a.id
             join core.roles r on r.id = a.role_id and r.code = p_role_code
            where a.user_id = p.id and a.deleted_at is null
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())))
     -- Quienes tienen acceso a ese local o a esa marca (incluidos los roles de grupo).
     and (p_restaurant_id is null or exists (
           select 1 from core.user_role_assignments a
            where a.user_id = p.id and a.deleted_at is null and a.group_id = v_r.group_id
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
              and (a.scope_type = 'group'
                   or (a.scope_type = 'brand' and a.brand_id = v_r.brand_id)
                   or (a.scope_type = 'restaurant' and a.restaurant_id = v_r.id))))
     and (p_brand_id is null or exists (
           select 1 from core.user_role_assignments a
            where a.user_id = p.id and a.deleted_at is null and a.group_id = v_b.group_id
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
              and (a.scope_type = 'group' or a.brand_id = v_b.id)))
     and (p_after_key is null
          or (lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email), p.id) > (p_after_key, p_after_id))
   order by 8, 1
   limit least(greatest(coalesce(p_limit, 25), 1), 100);
end
$$;

create or replace function workflow.inbox(p_pending boolean default true, p_limit integer default 50,
                               p_before_created_at timestamptz default null, p_before_id uuid default null)
returns table (id uuid, workflow_code text, workflow_name text, status workflow.request_status, requested_at timestamptz,
               requested_by_name text, summary text, reason text, place_name text, can_decide boolean,
               resolved_at timestamptz, resolved_by_name text, resolution_comment text,
               entity_table text, previous_values jsonb, proposed_changes jsonb)
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
  if (p_before_created_at is null) <> (p_before_id is null) then
    raise exception 'La página siguiente necesita la fecha y el id.' using errcode = '22023';
  end if;
  return query
  -- Primero se filtra, ordena y limita (por conjuntos, una vez por consulta); recién después se
  -- arma el resumen de las pocas filas que quedan.
  with page as (
    select r.*
      from workflow.approval_requests r
     where r.deleted_at is null
       and ((p_pending and r.status = 'pending') or (not p_pending and r.status <> 'pending'))
       and (p_before_created_at is null or (r.created_at, r.id) < (p_before_created_at, p_before_id))
       and (r.requested_by = v_actor or r.subject_user_id = v_actor
            or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
            or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
            or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))
     order by r.created_at desc, r.id desc
     limit least(greatest(coalesce(p_limit, 50), 1), 100)
  )
  select r.id, w.code, w.name, r.status, r.requested_at, core.display_name(r.requested_by),
         case
           when w.code in ('core.assign_sensitive_role', 'core.assign_superadmin', 'core.assign_by_superadmin') then
             'Dar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.revoke_by_superadmin' then
             'Quitar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.change_role_permission' then
             case when (r.proposed_changes ->> 'grant')::boolean then 'Dar el permiso ' else 'Quitar el permiso ' end
             || (r.proposed_changes ->> 'permission_code') || ' al rol '
             || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
           when w.code = 'org.transfer_restaurant' then
             'Traspasar ' || coalesce((select rs.name from org.restaurants rs where rs.id = (r.proposed_changes ->> 'restaurant_id')::uuid), 'un local')
             || ' a la marca ' || coalesce((select b.name from org.brands b where b.id = (r.proposed_changes ->> 'target_brand_id')::uuid), '')
           when w.code = 'core.reactivate_user' then
             'Reactivar la cuenta de ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           else w.name
         end,
         r.reason,
         coalesce((select rs.name from org.restaurants rs where rs.id = r.restaurant_id),
                  (select b.name from org.brands b where b.id = r.brand_id),
                  (select g.name from org.groups g where g.id = r.group_id)),
         r.status = 'pending' and workflow.decision_blocker(r.id) is null,
         r.resolved_at, core.display_name(r.resolved_by), r.resolution_comment,
         r.entity_table,
         (case when core.can_see_costs(r.group_id, r.brand_id, r.restaurant_id) then r.previous_values
               else core.hide_costs(r.previous_values) end)
           -- El motivo de una baja, solo para quien administra a la persona o puede decidir (respuesta 2).
           - case when r.subject_user_id is null or core.can_administer_user(r.subject_user_id)
                       or (r.status = 'pending' and workflow.decision_blocker(r.id) is null)
                  then '' else 'deactivation_reason' end,
         -- Lo técnico del pedido (a quiénes excluye, la foto de permisos) no se muestra.
         case when core.can_see_costs(r.group_id, r.brand_id, r.restaurant_id)
              then r.proposed_changes - 'excluded_approvers' - 'role_permissions'
              else core.hide_costs(r.proposed_changes - 'excluded_approvers' - 'role_permissions') end
    from page r
    join workflow.approval_workflows w on w.id = r.workflow_id
   order by r.created_at desc, r.id desc;
end
$$;

-- ---------------------------------------------------------------------------
-- 8. KPI comparados con hace 7 días (respuesta 5)
-- ---------------------------------------------------------------------------
create or replace function core.users_control_panel(
  p_from          date default null,
  p_to            date default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor    uuid := core.current_actor_id();
  v_tz       text := 'America/Argentina/Buenos_Aires';
  v_to       date := coalesce(p_to, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  v_from     date := coalesce(p_from, coalesce(p_to, (now() at time zone 'America/Argentina/Buenos_Aires')::date) - 29);
  v_security boolean;
  v_groups   uuid[];
  v_r        org.restaurants;
  v_b        org.brands;
  v_users    uuid[];
  -- Los KPI de estado se comparan con hace 7 días (regla de tableros 2, respuesta 5 de Joaco).
  v_prev     timestamptz := now() - interval '7 days';
begin
  if v_actor is null or not core.current_session_ok() then
    return null;
  end if;
  if v_from > v_to or v_to - v_from > 366 then
    raise exception 'El período tiene que ir de una fecha a otra posterior, hasta un año.' using errcode = '22023';
  end if;
  if p_restaurant_id is not null then
    select * into v_r from org.restaurants where id = p_restaurant_id;
  end if;
  if p_brand_id is not null then
    select * into v_b from org.brands where id = p_brand_id;
  end if;
  -- El registro de seguridad solo con security.view (de grupo: los ingresos no tienen marca ni local).
  v_groups := array(select core.permitted_group_ids('security.view'));
  v_security := cardinality(v_groups) > 0;

  -- Las personas del tablero: las que la sesión ve, con acceso al local o la marca del filtro.
  v_users := array(
    select p.id from core.user_profiles p
     where p.id in (select core.visible_user_ids()) and p.deleted_at is null
       and (p_restaurant_id is null or exists (
             select 1 from core.user_role_assignments a
              where a.user_id = p.id and a.deleted_at is null and a.group_id = v_r.group_id
                and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
                and (a.scope_type = 'group' or (a.scope_type = 'brand' and a.brand_id = v_r.brand_id)
                     or (a.scope_type = 'restaurant' and a.restaurant_id = v_r.id))))
       and (p_brand_id is null or exists (
             select 1 from core.user_role_assignments a
              where a.user_id = p.id and a.deleted_at is null and a.group_id = v_b.group_id
                and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
                and (a.scope_type = 'group' or a.brand_id = v_b.id))));

  return (
    with people as (select p.* from core.user_profiles p where p.id = any (v_users)),
    sec as (
      select s.event_type, s.occurred_at, s.user_id
        from audit.authentication_security_events s
       where v_security and s.scope_group_id = any (v_groups)
         and s.occurred_at >= least(v_from, v_to - 13)::timestamp at time zone v_tz
         and s.occurred_at < (v_to + 1)::timestamp at time zone v_tz
         and s.event_type in ('login_succeeded', 'login_failed', 'operation_denied')
         -- Con filtro de lugar, solo los de las personas de ese lugar.
         and (p_restaurant_id is null and p_brand_id is null or s.user_id = any (v_users))
    ),
    -- El estado de cada persona hace 7 días: el de su último cambio auditado antes de esa fecha.
    -- Quien todavía no existía no cuenta.
    prev_people as (
      select e.status, coalesce((e.new_values ->> 'locked_until')::timestamptz > v_prev, false) as locked
        from people p
        cross join lateral (
          select a.status, a.new_values from audit.audit_events a
           where a.table_name = 'user_profiles' and a.record_id = p.id and a.table_schema = 'core'
             and a.occurred_at < v_prev
           order by a.occurred_at desc limit 1) e
    ),
    current_roles as (
      select a.user_id, a.scope_type, a.brand_id, a.restaurant_id, r.code, r.name, r.level
        from core.user_role_assignments a
        join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.id in (select core.visible_assignment_ids())
         and a.user_id = any (v_users) and a.deleted_at is null
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
    )
    select jsonb_build_object(
      'as_of', now(),
      'from', v_from,
      'to', v_to,
      'can_view_security', v_security,
      'active', (select count(*) from people where status = 'active' and (locked_until is null or locked_until <= now())),
      'suspended', (select count(*) from people where status = 'suspended'),
      'deactivated', (select count(*) from people where status = 'deactivated'),
      'prev_as_of', v_prev,
      'active_prev', (select count(*) from prev_people where status = 'active' and not locked),
      'suspended_prev', (select count(*) from prev_people where status = 'suspended'),
      'deactivated_prev', (select count(*) from prev_people where status = 'deactivated'),
      -- Pendientes hace 7 días: pedidas antes y todavía pendientes en ese momento (según la auditoría).
      'pending_prev', (
        select count(*) from workflow.approval_requests r
         cross join lateral (
           select a.status from audit.audit_events a
            where a.table_name = 'approval_requests' and a.record_id = r.id and a.table_schema = 'workflow'
              and a.occurred_at < v_prev
            order by a.occurred_at desc limit 1) e
         where r.deleted_at is null and r.requested_at < v_prev and e.status = 'pending'
           and (r.status = 'pending' or r.updated_at >= v_prev)
           and (p_restaurant_id is null or r.restaurant_id = p_restaurant_id)
           and (p_brand_id is null or r.brand_id = p_brand_id)
           and (r.requested_by = v_actor or r.subject_user_id = v_actor
                or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
                or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
                or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))),
      'locked', (select count(*) from people where locked_until > now()),
      'pending_approvals', (
        select count(*) from workflow.approval_requests r
         where r.status = 'pending' and r.deleted_at is null
           and (p_restaurant_id is null or r.restaurant_id = p_restaurant_id)
           and (p_brand_id is null or r.brand_id = p_brand_id)
           and (r.requested_by = v_actor or r.subject_user_id = v_actor
                or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
                or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
                or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))),
      -- Accesos rechazados: ingresos fallidos y operaciones rechazadas, 7 días contra los 7 anteriores.
      'rejected_7d', case when v_security then (
        select count(*) from sec where event_type in ('login_failed', 'operation_denied')
           and occurred_at >= (v_to - 6)::timestamp at time zone v_tz) end,
      'rejected_prev_7d', case when v_security then (
        select count(*) from sec where event_type in ('login_failed', 'operation_denied')
           and occurred_at >= (v_to - 13)::timestamp at time zone v_tz
           and occurred_at < (v_to - 6)::timestamp at time zone v_tz) end,
      'logins_by_day', case when v_security then (
        select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'succeeded', coalesce(c.ok, 0), 'failed', coalesce(c.bad, 0))
                                  order by d.day), '[]'::jsonb)
          from generate_series(v_from, v_to, interval '1 day') as d (day)
          left join (
            select (occurred_at at time zone v_tz)::date as day,
                   count(*) filter (where event_type = 'login_succeeded') as ok,
                   count(*) filter (where event_type = 'login_failed') as bad
              from sec where occurred_at >= v_from::timestamp at time zone v_tz
             group by 1) c on c.day = d.day::date) end,
      'by_role', coalesce((
        select jsonb_agg(jsonb_build_object('role_code', code, 'role_name', name, 'people', people) order by level)
          from (select code, name, level, count(distinct user_id) as people from current_roles group by code, name, level) s), '[]'::jsonb),
      -- Por local: quienes tienen un rol de ese local o de su marca (los de todo el grupo van aparte).
      'by_restaurant', coalesce((
        select jsonb_agg(jsonb_build_object('restaurant_id', r.id, 'restaurant_name', r.name, 'brand_name', b.name,
                                            'people', (select count(distinct cr.user_id) from current_roles cr
                                                        where cr.restaurant_id = r.id
                                                           or (cr.scope_type = 'brand' and cr.brand_id = r.brand_id)))
                         order by b.name, r.name)
          from org.restaurants r join org.brands b on b.id = r.brand_id
         where r.deleted_at is null and r.id in (select core.permitted_restaurant_ids('users.view'))
           and (p_restaurant_id is null or r.id = p_restaurant_id)
           and (p_brand_id is null or r.brand_id = p_brand_id)), '[]'::jsonb),
      'group_wide_people', (select count(distinct user_id) from current_roles where scope_type = 'group'),
      'critical_changes', coalesce((
        select jsonb_agg(to_jsonb(h) order by h.sequence_number desc)
          from core.audit_history(10, null, null, v_from::timestamp at time zone v_tz, (v_to + 1)::timestamp at time zone v_tz,
                                  null, p_brand_id, p_restaurant_id, p_module, true) h), '[]'::jsonb)
    )
  );
end
$$;

-- ---------------------------------------------------------------------------
-- 9. Comentarios de lo que cambió
-- ---------------------------------------------------------------------------
comment on column core.v_test_documents.review_requested_by is
  'Quién mandó la versión a revisión. Esa persona no la puede publicar.';
comment on function core.publish_test_document(uuid, text) is
  'Aprueba y publica una versión de ensayo en revisión, y archiva la que estaba vigente. Pide test_documents.publish y que la publique alguien distinto de quien la mandó a revisión; si no, devuelve denied y queda en el registro de seguridad.';
comment on function core.request_test_document_review(uuid, text) is
  'Pasa un borrador de ensayo a revisión y anota quién lo pidió. Pide test_documents.edit.';
comment on function core.user_detail(uuid) is
  'Datos de la ficha de una persona que la sesión puede ver: puesto, área, dónde trabaja, su actividad reciente (con audit.view) y sus intentos rechazados (con security.view). El primer y el último acceso, quién la invitó y los motivos de suspensión o baja, solo para quien la administra (can_administer_user).';
comment on function core.users_dashboard(text, uuid, uuid, text, text, uuid, integer, uuid, text, uuid) is
  'Lista paginada de las personas que la sesión puede ver, con sus roles visibles, puesto y área. El último acceso, solo de quienes la sesión administra. Filtros: búsqueda, marca, local, estado (active, suspended, deactivated, locked), rol y área. Pagina por clave.';
comment on function core.users_control_panel(date, date, uuid, uuid, text) is
  'Tablero de control de usuarios (sección 9): personas activas, suspendidas y desactivadas y aprobaciones pendientes, cada una con su valor de hace 7 días (el estado de las personas de hoy según su último cambio auditado: quien se sumó después no cuenta); accesos rechazados en 7 días (contra los 7 anteriores), accesos por día, personas por rol y por local, y los últimos cambios críticos. Filtros: período (30 días por defecto), marca, local y módulo. Los datos de seguridad salen solo con security.view.';
comment on function core.assign_role(uuid, text, core.scope_type, uuid, uuid, uuid, timestamptz, text) is
  'Da un rol a una persona en un lugar. Pide roles.assign ahí, no darse roles a uno mismo, tener los permisos del rol y que la persona trabaje en ese lugar (una membresía de todo el grupo, de la marca o del local). Los roles sensibles quedan pendientes de aprobación.';
comment on function workflow.inbox(boolean, int, timestamptz, uuid) is
  'Bandeja de aprobaciones: las pendientes o las resueltas que la sesión puede ver, de la más nueva a la más vieja, con un resumen en español, el antes y el después, y si la sesión puede decidirlas. El motivo de una baja sale solo para quien administra a la persona o puede decidir. Pagina por fecha e id, hasta 100 por página.';
comment on function org.apply_transfer(uuid) is
  'Interna. Aplica un traspaso de local aprobado: crea el local nuevo en la marca de destino con sus áreas, pasa los roles vigentes (sumando la membresía del local nuevo a quien la necesite), termina las membresías del local viejo y lo deja inactivo.';
