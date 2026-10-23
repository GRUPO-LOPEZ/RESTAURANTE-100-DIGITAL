-- Las 6 preguntas pendientes de docs/estado.md, respondidas por Joaco (ADR-0017).
--   1. Quitarle el rol a otro Superadministrador lo aprueba Dirección General. También suspender o
--      dar de baja su cuenta (revisión de base, 2026-10-23).
--   2. Un local o una marca cerrados (inactive) o borrados dejan de dar permisos. La historia se
--      sigue viendo con los roles de marca o de grupo.
--   3. A una persona de Dirección General se la puede dar de baja o reactivar: lo pide el
--      Superadministrador u otra persona de Dirección, y lo aprueba otra persona de Dirección.
--   4. Un rol sensible lo aprueba Dirección General o el Director de Marca de ese lugar (no el
--      Controller ni la Chef); el Director, solo si tiene todos los permisos del rol.
--   5. Quien aprueba una reactivación alcanza todos los roles de la persona: ya era así (solo pruebas).
--   6. El bloqueo a propósito de una cuenta se resuelve antes de producción (ADR-0017).
-- Las funciones se recrean iguales a su última versión, más el cambio de cada pregunta.

-- ---------------------------------------------------------------------------
-- 1. Funciones de apoyo
-- ---------------------------------------------------------------------------
create function core.assignment_unit_open(p_brand_id uuid, p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (p_brand_id is null or exists (select 1 from org.brands b
                                         where b.id = p_brand_id and b.status = 'active' and b.deleted_at is null))
     and (p_restaurant_id is null or exists (select 1 from org.restaurants r
                                              where r.id = p_restaurant_id and r.status = 'active' and r.deleted_at is null))
$$;
comment on function core.assignment_unit_open(uuid, uuid) is
  'Interna. Si la marca y el local de una asignación (cuando los tiene) siguen operando: activos y sin borrar. Un rol de una unidad cerrada o borrada no da permisos (pregunta 2 de ADR-0017). Los roles de grupo no dependen de esto.';
revoke execute on function core.assignment_unit_open(uuid, uuid) from public;

create function core.holds_group_role(p_user_id uuid, p_role_code text, p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from core.user_role_assignments a
      join core.roles r on r.id = a.role_id and r.code = p_role_code and r.deleted_at is null
     where a.user_id = p_user_id and a.group_id = p_group_id and a.scope_type = 'group' and a.deleted_at is null
       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now()))
$$;
comment on function core.holds_group_role(uuid, text, uuid) is
  'Interna. Si la persona tiene ese rol vigente para todo el grupo (sin mirar el estado de su cuenta).';
revoke execute on function core.holds_group_role(uuid, text, uuid) from public;

-- ---------------------------------------------------------------------------
-- 2. Cuentas de quienes gobiernan el grupo: con aprobación de Dirección (preguntas 1 y 3)
-- ---------------------------------------------------------------------------
-- Qué camino toca, o vacío si va por el de siempre. Solo desvía cuando quien pide puede pedirlo:
-- así el resto recibe el mismo rechazo de siempre y no se entera de quién gobierna el grupo.
--   Dirección General: la da de baja o la reactiva el Superadministrador u otra persona de Dirección.
--   Superadministrador: a otro lo suspende o lo da de baja otro Superadministrador.
create function core.governance_workflow(p_user_id uuid, p_action text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_group uuid := core.user_group(p_user_id);
begin
  if v_actor is null or p_user_id is null or p_user_id = v_actor or v_group is null or not core.current_session_ok() then
    return null;
  end if;
  if p_action in ('deactivate', 'reactivate') and core.holds_group_role(p_user_id, 'general_management', v_group)
     and core.has_role_for_scope(array['superadmin', 'general_management'], 'group', v_group) then
    return 'core.change_general_management_status';
  end if;
  if p_action in ('deactivate', 'suspend') and core.holds_group_role(p_user_id, 'superadmin', v_group)
     and core.has_role_for_scope(array['superadmin'], 'group', v_group) then
    return 'core.change_superadmin_status';
  end if;
  return null;
end
$$;
comment on function core.governance_workflow(uuid, text) is
  'Interna. Si dar de baja, reactivar o suspender a esa persona necesita la aprobación de Dirección General (porque es de Dirección o Superadministrador) y quien pide lo puede pedir: devuelve el tipo de aprobación; si no, vacío.';
revoke execute on function core.governance_workflow(uuid, text) from public;

create function core.request_governance_status(p_user_id uuid, p_action text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid := core.current_actor_id();
  v_group   uuid := core.user_group(p_user_id);
  v_code    text := core.governance_workflow(p_user_id, p_action);
  v_p       core.user_profiles;
  v_gap     text;
  v_request uuid;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  if p_action is null or p_action not in ('deactivate', 'reactivate', 'suspend') then
    raise exception 'La acción tiene que ser deactivate, reactivate o suspend.' using errcode = '22023';
  end if;
  if v_code is null then
    return core.deny('core.request_governance_status', 'No podés hacer esto sobre esa cuenta.', p_user_id,
                     jsonb_build_object('action', p_action), v_group);
  end if;
  -- Por ahora, en un solo grupo: con roles o membresías vigentes en otro grupo, el control de que
  -- ningún grupo se quede sin gobierno tendría que mirar cada uno (revisión de seguridad, M1).
  if exists (select 1 from core.user_role_assignments a
              where a.user_id = p_user_id and a.group_id <> v_group and a.deleted_at is null
                and (a.valid_until is null or a.valid_until > now()))
     or exists (select 1 from core.user_memberships m
                 where m.user_id = p_user_id and m.group_id <> v_group and m.deleted_at is null
                   and (m.ends_at is null or m.ends_at > now())) then
    return core.deny('core.request_governance_status',
                     'La persona trabaja en más de un grupo: esto todavía no se puede pedir desde acá.', p_user_id,
                     jsonb_build_object('action', p_action), v_group);
  end if;
  -- Bloqueos en el mismo orden que el resto: primero el grupo, después la persona.
  perform core.lock_group_roles(v_group);
  perform pg_advisory_xact_lock(hashtext('grupo-lf:gobierno:' || p_user_id::text));
  select * into v_p from core.user_profiles where id = p_user_id and deleted_at is null;
  if not found then
    return core.deny('core.request_governance_status', 'No podés hacer esto sobre esa cuenta.', p_user_id,
                     jsonb_build_object('action', p_action), v_group);
  end if;

  if p_action = 'deactivate' and v_p.status not in ('active', 'suspended') then
    return jsonb_build_object('result', 'already_deactivated', 'message', 'La cuenta ya estaba desactivada.');
  elsif p_action = 'suspend' and v_p.status <> 'active' then
    return jsonb_build_object('result', 'not_active', 'message', 'La cuenta no está activa: no se puede suspender.');
  elsif p_action = 'reactivate' and v_p.status <> 'deactivated' then
    raise exception 'La cuenta no está desactivada.' using errcode = '23514';
  end if;
  if p_action in ('deactivate', 'suspend') then
    v_gap := core.group_governance_gap(v_group, null, p_user_id);
    if v_gap is not null then
      return core.deny('core.request_governance_status', v_gap, p_user_id, jsonb_build_object('action', p_action), v_group);
    end if;
  end if;
  -- Tiene que haber quien apruebe: otra persona de Dirección que no sea quien pide, la afectada ni
  -- (al reactivar) quien la dio de baja. Si no, la solicitud quedaría pendiente para siempre.
  if not exists (
       select 1 from core.user_role_assignments a
         join core.roles r on r.id = a.role_id and r.code = 'general_management' and r.deleted_at is null
        where a.group_id = v_group and a.scope_type = 'group' and a.deleted_at is null
          and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
          and a.user_id <> v_actor and a.user_id <> p_user_id
          and a.user_id is distinct from (case when p_action = 'reactivate' then v_p.deactivated_by end)
          and core.user_has_permission_for_scope(a.user_id, 'approvals.decide', 'group', v_group)) then
    return core.deny('core.request_governance_status',
                     'No hay otra persona de Dirección General que lo pueda aprobar (tiene que ser distinta de quien lo pide y de la persona afectada).',
                     p_user_id, jsonb_build_object('action', p_action), v_group);
  end if;

  v_request := workflow.request_approval(v_code, v_group, null, null, p_user_id, p_user_id,
    jsonb_build_object('user_id', p_user_id,
                       'status', case p_action when 'deactivate' then 'deactivated' when 'suspend' then 'suspended' else 'active' end,
                       -- Al reactivar, tampoco decide quien la dio de baja.
                       'excluded_approvers', case when p_action = 'reactivate' and v_p.deactivated_by is not null
                                                  then jsonb_build_array(v_p.deactivated_by) else '[]'::jsonb end),
    jsonb_build_object('status', v_p.status)
      || case when p_action = 'reactivate' then jsonb_build_object('deactivation_reason', v_p.deactivation_reason) else '{}'::jsonb end,
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
    'message', case when v_code = 'core.change_general_management_status'
                    then 'Queda pendiente hasta que lo apruebe otra persona de Dirección General, distinta de quien lo pidió.'
                    else 'Queda pendiente hasta que lo apruebe Dirección General.' end);
end
$$;
comment on function core.request_governance_status(uuid, text, text) is
  'Interna (la llaman disable_user, request_reactivation y suspend_user). Pide dar de baja, reactivar o suspender a alguien de Dirección General o a otro Superadministrador, según governance_workflow: sin dejar al grupo sin gobierno, en un solo grupo y solo si hay otra persona de Dirección que lo pueda aprobar.';
revoke execute on function core.request_governance_status(uuid, text, text) from public;

create function core.apply_governance_status(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req  workflow.approval_requests := workflow.approved_request(p_request_id);
  v_code text;
  v_user uuid := (v_req.proposed_changes ->> 'user_id')::uuid;
  v_to   text := v_req.proposed_changes ->> 'status';
  v_p    core.user_profiles;
  v_gap  text;
begin
  select w.code into v_code from workflow.approval_workflows w where w.id = v_req.workflow_id;
  perform core.lock_group_roles(v_req.group_id);
  -- Lo que se aprobó sigue valiendo: quien pidió todavía puede pedirlo y la persona sigue en ese rol.
  if v_code = 'core.change_general_management_status' then
    if not core.user_has_role_for_scope(v_req.requested_by, array['superadmin', 'general_management'], 'group', v_req.group_id) then
      perform workflow.cannot_apply('quien la pidió ya no es Superadministrador ni de Dirección General');
    end if;
    if not core.holds_group_role(v_user, 'general_management', v_req.group_id) then
      perform workflow.cannot_apply('la persona ya no es de Dirección General');
    end if;
  else
    if not core.user_has_role_for_scope(v_req.requested_by, array['superadmin'], 'group', v_req.group_id) then
      perform workflow.cannot_apply('quien la pidió ya no es Superadministrador');
    end if;
    if not core.holds_group_role(v_user, 'superadmin', v_req.group_id) then
      perform workflow.cannot_apply('la persona ya no es Superadministrador');
    end if;
  end if;
  select * into v_p from core.user_profiles where id = v_user and deleted_at is null for update;
  if not found then
    perform workflow.cannot_apply('la persona ya no existe');
  end if;

  if v_to in ('deactivated', 'suspended') then
    if (v_to = 'deactivated' and v_p.status not in ('active', 'suspended')) or (v_to = 'suspended' and v_p.status <> 'active') then
      perform workflow.cannot_apply('la cuenta ya no está activa');
    end if;
    v_gap := core.group_governance_gap(v_req.group_id, null, v_user);
    if v_gap is not null then
      perform workflow.cannot_apply(lower(left(v_gap, 1)) || substr(rtrim(v_gap, '.'), 2));
    end if;
    perform core.set_change_context(btrim(v_req.reason) || ' (aprobado en la solicitud ' || p_request_id || ')', 'manual');
    if v_to = 'deactivated' then
      update core.user_profiles
         set status = 'deactivated', deactivated_at = now(), deactivation_reason = btrim(v_req.reason),
             deactivated_by = v_req.requested_by,
             suspended_at = null, suspended_by = null, suspension_reason = null
       where id = v_user and deleted_at is null;
    else
      update core.user_profiles
         set status = 'suspended', suspended_at = now(), suspended_by = v_req.requested_by, suspension_reason = btrim(v_req.reason)
       where id = v_user and deleted_at is null;
    end if;
    delete from auth.refresh_tokens where user_id = v_user::text;
    delete from auth.sessions where user_id = v_user;
    if v_to = 'deactivated' then
      perform audit.log_security_event('account_disabled', 'core.apply_governance_status', btrim(v_req.reason), v_user,
                                       null, jsonb_build_object('request_id', p_request_id), v_req.group_id);
    else
      perform audit.log_security_event('account_suspended', 'core.apply_governance_status', btrim(v_req.reason), v_user,
                                       null, jsonb_build_object('request_id', p_request_id), v_req.group_id);
    end if;
  elsif v_to = 'active' then
    if v_p.status <> 'deactivated' then
      perform workflow.cannot_apply('la cuenta ya no está desactivada');
    end if;
    perform core.set_change_context('Reactivación aprobada (solicitud ' || p_request_id || ')', 'manual');
    update core.user_profiles
       set status = 'active', deactivated_at = null, deactivation_reason = null, deactivated_by = null, locked_until = null
     where id = v_user and deleted_at is null;
    delete from core.login_throttles where email = lower(v_p.email);
    perform audit.log_security_event('account_reactivated', 'core.apply_governance_status', 'Reactivación aprobada',
                                     v_user, null, jsonb_build_object('request_id', p_request_id), v_req.group_id);
  else
    perform workflow.cannot_apply('el pedido no dice si es una baja, una suspensión o una reactivación');
  end if;
end
$$;
comment on function core.apply_governance_status(uuid) is
  'Interna. Aplica la baja, la suspensión o la reactivación aprobada de alguien de Dirección General o de un Superadministrador: vuelve a mirar quién pidió, que la persona siga en ese rol y que el grupo no se quede sin gobierno; cierra las sesiones y deja el evento de seguridad.';
revoke execute on function core.apply_governance_status(uuid) from public;

-- ---------------------------------------------------------------------------
-- 3. Tipos de aprobación (preguntas 1, 3 y 4)
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Preguntas pendientes de la Fase 1 respondidas por Joaco (ADR-0017)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, approver_role_codes,
                                           apply_function, entity_table)
  values ('core.change_general_management_status', 'Dar de baja o reactivar a Dirección General',
          'Lo pide el Superadministrador u otra persona de Dirección. Lo aprueba otra persona de Dirección General, distinta de quien pidió y de la persona afectada.',
          'approvals.decide', array['general_management'], 'core.apply_governance_status(uuid)', 'core.user_profiles'),
         ('core.change_superadmin_status', 'Suspender o dar de baja a un Superadministrador',
          'Lo pide otro Superadministrador. Lo aprueba Dirección General de todo el grupo.',
          'approvals.decide', array['general_management'], 'core.apply_governance_status(uuid)', 'core.user_profiles');
  update workflow.approval_workflows
     set approver_role_codes = array['general_management', 'brand_director'],
         description = 'Dar un rol que aprueba cambios o administra la seguridad. Lo aprueba Dirección General, o el Director de Marca de ese lugar si tiene todos los permisos del rol (pregunta 4 de ADR-0017).'
   where code = 'core.assign_sensitive_role';
end
$$;


-- ---------------------------------------------------------------------------
-- 4. Un local o una marca cerrados no dan permisos (pregunta 2)
-- ---------------------------------------------------------------------------
create or replace function core.actor_grants(p_permission text)
returns table (scope_type core.scope_type, group_id uuid, brand_id uuid, restaurant_id uuid)
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
  select a.scope_type, a.group_id, a.brand_id, a.restaurant_id
    from core.user_role_assignments a
    join core.roles r on r.id = a.role_id and r.deleted_at is null
    join core.role_permissions rp on rp.role_id = r.id and rp.deleted_at is null
    join core.permissions p on p.id = rp.permission_id and p.deleted_at is null
   where p.code = p_permission
     and a.user_id = v_actor
     and a.deleted_at is null
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
       -- Un local o una marca cerrados o borrados no dan permisos (pregunta 2).
       and core.assignment_unit_open(a.brand_id, a.restaurant_id)
     and exists (select 1 from core.user_memberships m
                  where m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
                    and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now()));
end
$$;

create or replace function core.user_has_permission_for_scope(p_user_id uuid, p_permission text, p_scope_type core.scope_type,
                                                              p_group_id uuid, p_brand_id uuid default null,
                                                              p_restaurant_id uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_user_id is null or p_group_id is null
     or (p_scope_type <> 'group' and p_brand_id is null)
     or (p_scope_type = 'restaurant' and p_restaurant_id is null) then
    return false;
  end if;
  -- El alcance pedido tiene que cuadrar con la estructura.
  if p_scope_type <> 'group'
     and not exists (select 1 from org.brands b where b.id = p_brand_id and b.group_id = p_group_id) then
    return false;
  end if;
  if p_scope_type = 'restaurant'
     and not exists (select 1 from org.restaurants r
                      where r.id = p_restaurant_id and r.brand_id = p_brand_id and r.group_id = p_group_id) then
    return false;
  end if;
  return exists (
    select 1
      from core.user_profiles u
      join core.user_role_assignments a on a.user_id = u.id
      join core.roles r on r.id = a.role_id and r.deleted_at is null
      join core.role_permissions rp on rp.role_id = r.id and rp.deleted_at is null
      join core.permissions p on p.id = rp.permission_id and p.deleted_at is null and p.code = p_permission
      join core.user_memberships m on m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
                                  and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
     where u.id = p_user_id
       and u.deleted_at is null and u.status = 'active'
       and (u.locked_until is null or u.locked_until <= now())
       and a.deleted_at is null
       and a.group_id = p_group_id
       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
       -- Un local o una marca cerrados o borrados no dan permisos (pregunta 2).
       and core.assignment_unit_open(a.brand_id, a.restaurant_id)
       and (
         a.scope_type = 'group'
         or (a.scope_type = 'brand' and p_scope_type in ('brand', 'restaurant') and a.brand_id = p_brand_id)
         or (a.scope_type = 'restaurant' and p_scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id)
       )
  );
end
$$;

create or replace function core.user_has_role_for_scope(p_user_id uuid, p_role_codes text[], p_scope_type core.scope_type,
                                                        p_group_id uuid, p_brand_id uuid default null,
                                                        p_restaurant_id uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_user_id is null or p_group_id is null then
    return false;
  end if;
  return exists (
    select 1
      from core.user_profiles u
      join core.user_role_assignments a on a.user_id = u.id
      join core.roles r on r.id = a.role_id and r.deleted_at is null and r.code = any (p_role_codes)
      join core.user_memberships m on m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
                                  and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
     where u.id = p_user_id
       and u.deleted_at is null and u.status = 'active'
       and (u.locked_until is null or u.locked_until <= now())
       and a.deleted_at is null
       and a.group_id = p_group_id
       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
       -- Un local o una marca cerrados o borrados no dan permisos (pregunta 2).
       and core.assignment_unit_open(a.brand_id, a.restaurant_id)
       and (
         a.scope_type = 'group'
         or (a.scope_type = 'brand' and p_scope_type in ('brand', 'restaurant') and a.brand_id = p_brand_id)
         or (a.scope_type = 'restaurant' and p_scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id)
       )
  );
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Superadmin que quita a otro Superadmin: lo aprueba Dirección (pregunta 1)
-- ---------------------------------------------------------------------------
create or replace function core.revoke_role(p_assignment_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a       core.user_role_assignments;
  v_role    core.roles;
  v_missing text[];
  v_gap     text;
  v_details jsonb;
  v_request uuid;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  select * into v_a from core.user_role_assignments where id = p_assignment_id and deleted_at is null;
  if not found
     or not core.has_permission_for_scope('roles.assign', v_a.scope_type, v_a.group_id, v_a.brand_id, v_a.restaurant_id) then
    return core.deny('core.revoke_role', 'No podés quitar esa asignación.', v_a.user_id,
                     jsonb_build_object('assignment_id', p_assignment_id), v_a.group_id, v_a.brand_id, v_a.restaurant_id);
  end if;
  perform core.lock_group_roles(v_a.group_id);
  select * into v_a from core.user_role_assignments where id = p_assignment_id and deleted_at is null for update;
  if not found then
    return jsonb_build_object('result', 'already_resolved', 'message', 'La asignación ya fue quitada.');
  end if;
  -- Con el bloqueo tomado se vuelve a mirar el permiso: otra transacción pudo haberlo quitado.
  if not core.has_permission_for_scope('roles.assign', v_a.scope_type, v_a.group_id, v_a.brand_id, v_a.restaurant_id) then
    return core.deny('core.revoke_role', 'No podés quitar esa asignación.', v_a.user_id,
                     jsonb_build_object('assignment_id', p_assignment_id), v_a.group_id, v_a.brand_id, v_a.restaurant_id);
  end if;
  select * into v_role from core.roles where id = v_a.role_id;
  v_details := jsonb_build_object('assignment_id', v_a.id, 'role', v_role.code);

  if v_role.code in ('superadmin', 'general_management') then
    v_gap := core.group_governance_gap(v_a.group_id, v_a.id, null);
    if v_gap is not null then
      return core.deny('core.revoke_role', v_gap, v_a.user_id, v_details, v_a.group_id);
    end if;
  end if;

  -- Nadie le quita un rol a quien tiene más permisos que uno. El superadmin del grupo lo puede
  -- PEDIR, y lo aprueba Dirección General (decisión de Joaco, 2026-10-20).
  v_missing := core.missing_permissions_for_role(v_role.id, v_a.scope_type, v_a.group_id, v_a.brand_id, v_a.restaurant_id);
  -- Quitarle el rol a OTRO Superadministrador también lo aprueba Dirección General (pregunta 1).
  if cardinality(v_missing) > 0 or (v_role.code = 'superadmin' and v_a.user_id <> core.current_actor_id()) then
    if core.has_role_for_scope(array['superadmin'], 'group', v_a.group_id) and v_a.user_id <> core.current_actor_id() then
      v_request := workflow.request_approval('core.revoke_by_superadmin', v_a.group_id, null, null, v_a.user_id, v_a.id,
        jsonb_build_object('assignment_id', v_a.id, 'user_id', v_a.user_id, 'role_id', v_role.id, 'role_code', v_role.code,
                           'deleted', true),
        jsonb_build_object('role_code', v_role.code, 'scope_type', v_a.scope_type, 'deleted', false),
        p_reason);
      return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                                'message', 'Quitar este rol queda pendiente hasta que lo apruebe Dirección General.');
    end if;
    return core.deny('core.revoke_role',
                     'No podés quitar un rol con permisos que vos no tenés: ' || array_to_string(v_missing, ', ') || '.',
                     v_a.user_id, v_details, v_a.group_id, v_a.brand_id, v_a.restaurant_id);
  end if;

  perform core.set_change_context(p_reason, 'manual');
  update core.user_role_assignments set deleted_at = now() where id = v_a.id;
  return jsonb_build_object('result', 'applied', 'message', 'Rol quitado.');
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Quién aprueba, en el lugar de la solicitud (pregunta 4)
-- ---------------------------------------------------------------------------
create or replace function workflow.decision_blocker(p_request_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor    uuid := core.current_actor_id();
  v_req      workflow.approval_requests;
  v_wf       workflow.approval_workflows;
  v_scope    core.scope_type;
  v_excluded uuid[];
begin
  select * into v_req from workflow.approval_requests where id = p_request_id and deleted_at is null;
  if not found then
    return 'No podés decidir esta solicitud.';
  end if;
  select * into v_wf from workflow.approval_workflows where id = v_req.workflow_id;
  v_scope := case when v_req.restaurant_id is not null then 'restaurant'
                  when v_req.brand_id is not null then 'brand' else 'group' end::core.scope_type;

  if not core.has_permission_for_scope(v_wf.required_permission, v_scope, v_req.group_id, v_req.brand_id, v_req.restaurant_id)
     -- El rol exigido (por ejemplo, Dirección General) tiene que ser de todo el grupo, salvo en un rol
     -- sensible, que mira el lugar de la solicitud.
     or (cardinality(coalesce(v_wf.approver_role_codes, '{}')) > 0
         -- Un rol sensible lo aprueba quien tenga el rol exigido en el lugar de la solicitud (pregunta 4):
         -- Dirección cubre cualquier lugar; un Director de Marca, su marca y sus locales.
         and not core.has_role_for_scope(v_wf.approver_role_codes,
               case when v_wf.code = 'core.assign_sensitive_role' then v_scope else 'group' end::core.scope_type, v_req.group_id,
               case when v_wf.code = 'core.assign_sensitive_role' then v_req.brand_id end,
               case when v_wf.code = 'core.assign_sensitive_role' then v_req.restaurant_id end)) then
    return 'No podés decidir esta solicitud.';
  end if;

  -- Quien pidió (salvo que el tipo de aprobación lo permita), la persona afectada y las personas
  -- que la solicitud excluye (por ejemplo, quien bloqueó la cuenta o quienes tienen el rol que se
  -- cambia) no pueden decidir.
  select coalesce(array_agg(x::uuid), '{}') into v_excluded
    from jsonb_array_elements_text(coalesce(v_req.proposed_changes -> 'excluded_approvers', '[]'::jsonb)) as x;
  -- En un cambio de la matriz, tampoco decide quien tiene HOY ese rol (aunque lo haya recibido
  -- después del pedido): se beneficiaría del cambio.
  if v_wf.code = 'core.change_role_permission' and exists (
       select 1 from core.user_role_assignments a
        where a.user_id = v_actor and a.role_id = (v_req.proposed_changes ->> 'role_id')::uuid and a.deleted_at is null) then
    v_excluded := v_excluded || v_actor;
  end if;
  if (v_actor = v_req.requested_by and not v_wf.allow_self_approval)
     or v_actor = v_req.subject_user_id or v_actor = any (v_excluded) then
    return 'No podés decidir una solicitud propia o que te afecta: la tiene que decidir otra persona.';
  end if;
  -- En una reactivación, quien aprueba tiene que poder actuar sobre esa persona.
  if v_wf.code = 'core.reactivate_user' and core.cannot_act_on_user(v_req.subject_user_id, 'users.deactivate') is not null then
    return 'No podés decidir esta solicitud: la persona tiene roles o permisos fuera de los tuyos.';
  end if;
  -- Un rol sensible: quien no es de Dirección (por ejemplo, un Director de Marca) tiene que tener
  -- todos los permisos del rol en ese lugar. Si no, lo aprueba Dirección (decisión de Joaco, ADR-0017).
  if v_wf.code = 'core.assign_sensitive_role'
     and not core.has_role_for_scope(array['general_management'], 'group', v_req.group_id)
     and cardinality(core.missing_permissions_for_role((v_req.proposed_changes ->> 'role_id')::uuid,
                       (v_req.proposed_changes ->> 'scope_type')::core.scope_type, v_req.group_id,
                       (v_req.proposed_changes ->> 'brand_id')::uuid, (v_req.proposed_changes ->> 'restaurant_id')::uuid)) > 0 then
    return 'No podés aprobar un rol con permisos que vos no tenés: lo aprueba Dirección General.';
  end if;
  return null;
end
$$;

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
          or core.user_has_role_for_scope(c.user_id, v_wf.approver_role_codes,
               case when v_wf.code = 'core.assign_sensitive_role' then v_scope else 'group' end::core.scope_type, p_group_id,
               case when v_wf.code = 'core.assign_sensitive_role' then p_brand_id end,
               case when v_wf.code = 'core.assign_sensitive_role' then p_restaurant_id end))
     -- Con la misma regla de decision_blocker: a un Director de Marca solo se le avisa si tiene todos
     -- los permisos del rol sensible.
     and (v_wf.code <> 'core.assign_sensitive_role'
          or core.user_has_role_for_scope(c.user_id, array['general_management'], 'group', p_group_id)
          or cardinality(core.user_missing_permissions_for_role(c.user_id, (p_proposed_changes ->> 'role_id')::uuid,
               (p_proposed_changes ->> 'scope_type')::core.scope_type, p_group_id,
               (p_proposed_changes ->> 'brand_id')::uuid, (p_proposed_changes ->> 'restaurant_id')::uuid)) = 0);
  return v_id;
end
$$;

-- ---------------------------------------------------------------------------
-- 7. Cuentas de Dirección y Superadministradores, con aprobación (preguntas 1 y 3)
-- ---------------------------------------------------------------------------
create or replace function core.disable_user(p_user_id uuid, p_reason text)
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
  -- Dirección General o un Superadministrador: con aprobación de Dirección (preguntas 1 y 3).
  if core.governance_workflow(p_user_id, 'deactivate') is not null then
    return core.request_governance_status(p_user_id, 'deactivate', p_reason);
  end if;
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.disable_user', v_why, p_user_id, null, v_group);
  end if;
  -- Nunca deja al grupo sin Superadministrador ni Dirección General activos (con bloqueo por grupo).
  perform core.lock_group_roles(v_group);
  v_why := core.group_governance_gap(v_group, null, p_user_id);
  if v_why is not null then
    return core.deny('core.disable_user', v_why, p_user_id, null, v_group);
  end if;

  perform core.set_change_context(p_reason, 'manual');
  -- También se puede desactivar una cuenta suspendida: la suspensión se cierra.
  update core.user_profiles
     set status = 'deactivated', deactivated_at = now(), deactivation_reason = btrim(p_reason),
         deactivated_by = core.current_actor_id(),
         suspended_at = null, suspended_by = null, suspension_reason = null
   where id = p_user_id and status in ('active', 'suspended');
  if not found then
    return jsonb_build_object('result', 'already_deactivated', 'message', 'La cuenta ya estaba desactivada.');
  end if;

  -- Cierra todas sus sesiones ya mismo. El hook de Auth impide que entre o renueve la sesión,
  -- y has_permission le corta el acceso en la consulta siguiente aunque su token siga vigente.
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;

  perform audit.log_security_event('account_disabled', 'core.disable_user', btrim(p_reason), p_user_id, null, null, v_group);
  return jsonb_build_object('result', 'applied', 'message', 'Cuenta desactivada. Se cerraron todas sus sesiones.');
end
$$;

create or replace function core.request_reactivation(p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_why     text;
  v_p       core.user_profiles;
  v_group   uuid := core.user_group(p_user_id);
  v_brand   uuid;
  v_rest    uuid;
  v_request uuid;
begin
  -- Dos pedidos a la vez sobre la misma persona no se cruzan.
  perform pg_advisory_xact_lock(hashtext('grupo-lf:reactivar:' || p_user_id::text));
  select case when count(distinct coalesce(a.brand_id::text, 'g')) = 1 and bool_and(a.brand_id is not null) then min(a.brand_id::text) end::uuid,
         case when count(distinct coalesce(a.restaurant_id::text, 'x')) = 1 and bool_and(a.restaurant_id is not null) then min(a.restaurant_id::text) end::uuid
    into v_brand, v_rest
    from core.user_role_assignments a
   where a.user_id = p_user_id and a.deleted_at is null and a.group_id = v_group
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now());
  -- Dirección General o un Superadministrador: con aprobación de Dirección (preguntas 1 y 3).
  if core.governance_workflow(p_user_id, 'reactivate') is not null then
    return core.request_governance_status(p_user_id, 'reactivate', p_reason);
  end if;
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.request_reactivation', v_why, p_user_id, null, v_group);
  end if;
  select * into v_p from core.user_profiles where id = p_user_id;
  if v_p.status <> 'deactivated' then
    raise exception 'La cuenta no está desactivada.' using errcode = '23514';
  end if;
  v_request := workflow.request_approval('core.reactivate_user', v_group, v_brand, case when v_brand is not null then v_rest end,
    p_user_id, p_user_id,
    jsonb_build_object('user_id', p_user_id, 'status', 'active',
                       'excluded_approvers', case when v_p.deactivated_by is not null then jsonb_build_array(v_p.deactivated_by) else '[]'::jsonb end),
    jsonb_build_object('status', v_p.status, 'deactivation_reason', v_p.deactivation_reason),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'La reactivación queda pendiente hasta que la apruebe otra persona, distinta de quien bloqueó la cuenta.');
end
$$;

create or replace function core.suspend_user(p_user_id uuid, p_reason text)
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
  -- Dirección General o un Superadministrador: con aprobación de Dirección (preguntas 1 y 3).
  if core.governance_workflow(p_user_id, 'suspend') is not null then
    return core.request_governance_status(p_user_id, 'suspend', p_reason);
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
           when w.code in ('core.change_general_management_status', 'core.change_superadmin_status') then
             case when r.proposed_changes ->> 'status' in ('deactivated', 'suspended', 'active') then
               case r.proposed_changes ->> 'status' when 'deactivated' then 'Dar de baja a ' when 'suspended' then 'Suspender a '
                    else 'Reactivar la cuenta de ' end
               || coalesce(core.display_name(r.subject_user_id), 'una persona')
               || case when w.code = 'core.change_general_management_status' then ' (Dirección General)' else ' (Superadministrador)' end
             else w.name end
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
    -- El camino de cada acción sobre la cuenta, para esta sesión (vacío = el de siempre).
    'governance', jsonb_build_object('deactivate', core.governance_workflow(p_user_id, 'deactivate'),
                                     'reactivate', core.governance_workflow(p_user_id, 'reactivate'),
                                     'suspend', core.governance_workflow(p_user_id, 'suspend')),
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

-- ---------------------------------------------------------------------------
-- 8. Rendimiento: los cambios críticos del tablero, por tabla (A10)
-- ---------------------------------------------------------------------------
-- Índices por alcance y tabla, para leer solo ciertas tablas sin recorrer todo el alcance.
set role audit_owner;
create index audit_events_restaurant_table_seq_idx on audit.audit_events (scope_restaurant_id, table_name, sequence_number desc)
  where scope_restaurant_id is not null;
create index audit_events_brand_table_seq_idx on audit.audit_events (scope_brand_id, table_name, sequence_number desc)
  where scope_restaurant_id is null and scope_brand_id is not null;
create index audit_events_group_table_seq_idx on audit.audit_events (scope_group_id, table_name, sequence_number desc)
  where scope_brand_id is null and scope_group_id is not null;
reset role;

create or replace function core.audit_scope_events(
  p_rids          uuid[],
  p_bids          uuid[],
  p_gids          uuid[],
  p_limit         integer,
  p_before        bigint,
  p_after         bigint,
  p_record_id     uuid,
  p_from          timestamptz,
  p_to            timestamptz,
  p_actor_id      uuid,
  p_module        text,
  p_tables        text[]
)
returns setof audit.audit_events
language plpgsql
stable
security definer
set search_path = ''
set plan_cache_mode = force_custom_plan
as $$
begin
  return query
  with events as (
    select e.* from unnest(p_rids) as rid
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and p_tables is null and x.scope_restaurant_id is not null and x.scope_restaurant_id = rid
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
           and (p_tables is null or x.table_name = any (p_tables))
         order by x.sequence_number desc limit p_limit) e
    union all
    select e.* from unnest(p_bids) as bid
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and p_tables is null and x.scope_restaurant_id is null and x.scope_brand_id = bid
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
           and (p_tables is null or x.table_name = any (p_tables))
         order by x.sequence_number desc limit p_limit) e
    union all
    select e.* from unnest(p_gids) as gid
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and p_tables is null and x.scope_brand_id is null and x.scope_group_id = gid
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
           and (p_tables is null or x.table_name = any (p_tables))
         order by x.sequence_number desc limit p_limit) e
    -- Solo ciertas tablas (por ejemplo, los cambios críticos): cada tabla por su propio índice.
    union all
    select e.* from unnest(p_rids) as rid cross join unnest(p_tables) as t
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and x.scope_restaurant_id = rid and x.table_name = t
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
         order by x.sequence_number desc limit p_limit) e
    union all
    select e.* from unnest(p_bids) as bid cross join unnest(p_tables) as t
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and x.scope_restaurant_id is null and x.scope_brand_id = bid and x.table_name = t
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
         order by x.sequence_number desc limit p_limit) e
    union all
    select e.* from unnest(p_gids) as gid cross join unnest(p_tables) as t
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and x.scope_brand_id is null and x.scope_group_id = gid and x.table_name = t
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
         order by x.sequence_number desc limit p_limit) e
    union all
    -- Eventos sin alcance (por ejemplo, el catálogo de roles): solo con el permiso de todo el grupo.
    (select x.* from audit.audit_events x
      where p_actor_id is null and cardinality(p_gids) > 0 and x.scope_group_id is null
        and x.sequence_number < p_before and x.sequence_number >= p_after
        and (p_record_id is null or x.record_id = p_record_id)
        and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
        and (p_module is null or x.module = p_module)
        and (p_tables is null or x.table_name = any (p_tables))
      order by x.sequence_number desc limit p_limit)
    union all
    -- Lo que hizo una persona: por su índice, y después se mira que esté en el alcance.
    (select x.* from audit.audit_events x
      where p_actor_id is not null and x.actor_user_id = p_actor_id
        and x.sequence_number < p_before and x.sequence_number >= p_after
        and (x.scope_restaurant_id = any (p_rids)
             or (x.scope_restaurant_id is null and x.scope_brand_id = any (p_bids))
             or (x.scope_brand_id is null and x.scope_group_id = any (p_gids))
             or (x.scope_group_id is null and cardinality(p_gids) > 0))
        and (p_record_id is null or x.record_id = p_record_id)
        and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
        and (p_module is null or x.module = p_module)
        and (p_tables is null or x.table_name = any (p_tables))
      order by x.sequence_number desc limit p_limit)
  )
  select * from events order by events.sequence_number desc limit p_limit;
end
$$;

create or replace function core.audit_history(
  p_limit         integer default 50,
  p_before        bigint default null,
  p_record_id     uuid default null,
  p_from          timestamptz default null,
  p_to            timestamptz default null,
  p_actor_id      uuid default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null,
  p_critical_only boolean default false
)
returns table (sequence_number bigint, occurred_at timestamptz, actor_name text, actor_role_code text, action text,
               module text, table_schema text, table_name text, record_id uuid, changed_fields text[],
               old_values jsonb, new_values jsonb, reason text, source text, place_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit  int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_bounds record;
  v_rids   uuid[];
  v_bids   uuid[];
  v_gids   uuid[];
  v_cost_rids uuid[];
  v_cost_bids uuid[];
  v_cost_gids uuid[];
begin
  if not core.current_session_ok() then
    return;
  end if;
  if p_module is not null and (length(p_module) > 60 or p_module !~ '^[a-z_]+$') then
    raise exception 'Módulo inválido.' using errcode = '22023';
  end if;
  v_bounds := core.audit_sequence_bounds(p_from, p_to);
  -- El alcance pedido, dentro de lo que la sesión puede ver: un local, una marca (sus locales y la
  -- marca) o todo lo visible.
  v_rids := array(select r.id from org.restaurants r
                   where r.id in (select core.permitted_restaurant_ids('audit.view'))
                     and (p_restaurant_id is null or r.id = p_restaurant_id)
                     and (p_brand_id is null or r.brand_id = p_brand_id));
  v_bids := case when p_restaurant_id is null then
              array(select b from core.permitted_brand_ids('audit.view') b where p_brand_id is null or b = p_brand_id)
            else '{}' end;
  v_gids := case when p_restaurant_id is null and p_brand_id is null then array(select core.permitted_group_ids('audit.view'))
            else '{}' end;

  v_cost_rids := array(select core.permitted_restaurant_ids('costing.view_costs'));
  v_cost_bids := array(select core.permitted_brand_ids('costing.view_costs'));
  v_cost_gids := array(select core.permitted_group_ids('costing.view_costs'));

  return query
  select e.sequence_number, e.occurred_at,
         coalesce(core.display_name(coalesce(e.actor_user_id, e.actor_service_account_id)),
                  case when e.source is not null then 'Sistema (' || e.source::text || ')' else 'Sistema' end),
         e.actor_role_code, e.action::text, e.module, e.table_schema, e.table_name, e.record_id, e.changed_fields,
         case when (e.scope_restaurant_id is not null and e.scope_restaurant_id = any (v_cost_rids))
                or (e.scope_restaurant_id is null and e.scope_brand_id is not null and e.scope_brand_id = any (v_cost_bids))
                or (e.scope_brand_id is null and e.scope_group_id is not null and e.scope_group_id = any (v_cost_gids))
              then e.old_values else core.hide_costs(e.old_values) end,
         case when (e.scope_restaurant_id is not null and e.scope_restaurant_id = any (v_cost_rids))
                or (e.scope_restaurant_id is null and e.scope_brand_id is not null and e.scope_brand_id = any (v_cost_bids))
                or (e.scope_brand_id is null and e.scope_group_id is not null and e.scope_group_id = any (v_cost_gids))
              then e.new_values else core.hide_costs(e.new_values) end,
         e.reason, e.source::text,
         coalesce((select r.name from org.restaurants r where r.id = e.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = e.scope_brand_id),
                  (select g.name from org.groups g where g.id = e.scope_group_id))
    from core.audit_scope_events(v_rids, v_bids, v_gids, v_limit, least(coalesce(p_before, 9223372036854775807), v_bounds.before_seq),
                                 v_bounds.after_seq, p_record_id, p_from, p_to, p_actor_id, p_module,
                                 case when p_critical_only then array['user_role_assignments', 'role_permissions', 'user_profiles',
                                   'roles', 'permissions', 'approval_decisions', 'approval_workflows'] end) e
   order by e.sequence_number desc;
end
$$;

-- ---------------------------------------------------------------------------
-- 9. Comentarios de lo que cambió
-- ---------------------------------------------------------------------------
comment on function core.disable_user(uuid, text) is
  'Desactiva una cuenta: cierra sus sesiones y conserva su historia. Pide users.deactivate sobre todos sus roles, nunca a uno mismo ni dejar al grupo sin Superadministrador o Dirección. A alguien de Dirección General se lo da de baja con aprobación de otra persona de Dirección (request_governance_status).';
comment on function core.request_reactivation(uuid, text) is
  'Pide reactivar una cuenta desactivada. La aprueba otra persona que alcance todos sus roles, distinta de quien la desactivó. A alguien de Dirección General lo reactiva otra persona de Dirección (request_governance_status).';
comment on function core.revoke_role(uuid, text) is
  'Quita un rol. Pide roles.assign en ese lugar y tener los permisos del rol. Quitarle el rol a otro Superadministrador, o uno con permisos que uno no tiene, queda pendiente hasta que lo apruebe Dirección General. Nunca deja al grupo sin Superadministrador ni Dirección.';
comment on function core.suspend_user(uuid, text) is
  'Suspende una cuenta (pausa): corta el acceso y cierra sus sesiones. Pide users.deactivate sobre todos los roles de la persona y un motivo; nunca sobre uno mismo ni sobre el último Superadministrador o Dirección General. A otro Superadministrador se lo suspende con aprobación de Dirección (request_governance_status). Se levanta con core.lift_suspension, sin aprobación.';
comment on function workflow.decision_blocker(uuid) is
  'Interna. Por qué la sesión no puede decidir una solicitud (vacío si puede): permiso y rol exigidos (de todo el grupo, salvo un rol sensible, que mira el lugar y pide tener todos sus permisos a quien no es de Dirección), nunca quien pidió, la persona afectada ni los excluidos.';
comment on function core.actor_grants(text) is
  'Interna. Los alcances donde la sesión tiene el permiso: roles vigentes, con membresía vigente y de una marca o un local que siguen operando (ADR-0017). La base de permitted_*, visible_* y has_permission_anywhere.';
comment on function core.user_has_permission_for_scope(uuid, text, core.scope_type, uuid, uuid, uuid) is
  'Interna. Si una persona activa tiene el permiso en ese alcance: rol vigente, membresía vigente y una marca o un local que siguen operando (ADR-0017).';
comment on function core.user_has_role_for_scope(uuid, text[], core.scope_type, uuid, uuid, uuid) is
  'Interna. Si una persona activa tiene alguno de esos roles en ese alcance: rol vigente, membresía vigente y una marca o un local que siguen operando (ADR-0017).';
