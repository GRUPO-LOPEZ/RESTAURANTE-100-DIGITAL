-- Fase 1 · M8 + M9 — Cuentas: desactivar, reactivar (con aprobación), bloqueo temporal por
-- intentos fallidos, ingreso con hook de Auth, invitación y sellado cada hora.
-- Decisiones: ADR-0008 (reactivar pide aprobación de otra persona), ADR-0009 (rechazos
-- registrados), ADR-0010 (ingreso por función propia + Custom Access Token hook) y P18
-- (5 fallos en 10 minutos bloquean 10 minutos; un administrador puede liberarlo antes).

-- ---------------------------------------------------------------------------
-- 1. Origen "auth": cambios que hace Supabase Auth (el hook de ingreso)
-- ---------------------------------------------------------------------------
-- El valor "auth" se agrega en la migración anterior (20261020225110_change_origin_auth.sql).

create or replace function core.set_change_context(p_reason text, p_origin text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 500 then
    raise exception 'El motivo del cambio es obligatorio y puede tener hasta 500 caracteres.'
      using errcode = '22023';
  end if;
  if p_origin is null or p_origin not in ('app', 'edge_function', 'agent', 'import', 'seed', 'maintenance', 'auth') then
    raise exception 'Origen del cambio inválido. Valores posibles: app, edge_function, agent, import, seed, maintenance, auth.'
      using errcode = '22023';
  end if;

  perform set_config('app.reason', p_reason, true);
  perform set_config('app.origin', p_origin, true);
end
$$;
comment on function core.set_change_context(text, text) is
  'Guarda el motivo (1 a 500 caracteres) y el origen del cambio para la transacción en curso. La auditoría los registra. Informativo: nunca decide permisos.';

-- ---------------------------------------------------------------------------
-- 2. Quién desactivó la cuenta
-- ---------------------------------------------------------------------------
alter table core.user_profiles add column disabled_by uuid references core.actors (id) on delete restrict;
comment on column core.user_profiles.disabled_by is 'Quién desactivó la cuenta. No puede ser quien apruebe la reactivación (ADR-0008).';

-- ---------------------------------------------------------------------------
-- 3. ¿Puede la sesión actuar sobre esta persona? (bloquear, reactivar, liberar)
--    - nunca sobre uno mismo;
--    - el permiso tiene que cubrir TODAS las asignaciones vigentes de la persona
--      (o su grupo, si no tiene roles);
--    - la persona no puede tener permisos que la sesión no tiene, salvo que quien actúa
--      sea superadmin del grupo (así un gerente no bloquea a su director).
--    Devuelve el motivo del rechazo, o nulo si puede.
-- ---------------------------------------------------------------------------
create function core.cannot_act_on_user(p_user_id uuid, p_permission text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_a     record;
  v_any   boolean := false;
begin
  if v_actor is null or not core.current_session_ok() then
    return 'La sesión no puede operar.';
  end if;
  if p_user_id = v_actor then
    return 'No podés hacer esto sobre tu propia cuenta.';
  end if;
  if not exists (select 1 from core.user_profiles where id = p_user_id and deleted_at is null) then
    return 'La persona no existe o no la podés ver.';
  end if;

  for v_a in
    select a.scope_type, a.group_id, a.brand_id, a.restaurant_id, a.role_id
      from core.user_role_assignments a
     where a.user_id = p_user_id and a.deleted_at is null
       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
  loop
    v_any := true;
    if not core.has_permission_for_scope(p_permission, v_a.scope_type, v_a.group_id, v_a.brand_id, v_a.restaurant_id) then
      return 'La persona tiene roles fuera de tu alcance.';
    end if;
    -- Sin excepción para el superadmin: si no, podría bloquear a quienes lo controlan
    -- (revisión de seguridad de M6 y M7, hallazgo G2).
    if cardinality(core.missing_permissions_for_role(v_a.role_id, v_a.scope_type, v_a.group_id, v_a.brand_id, v_a.restaurant_id)) > 0 then
      return 'La persona tiene permisos que vos no tenés.';
    end if;
  end loop;

  if not v_any and not exists (
       select 1 from core.user_memberships m
        where m.user_id = p_user_id and m.deleted_at is null
          and core.has_permission_in_group(p_permission, m.group_id)) then
    return 'La persona no tiene roles en tu alcance.';
  end if;
  return null;
end
$$;
comment on function core.cannot_act_on_user(uuid, text) is
  'Interna. Motivo por el que la sesión NO puede bloquear, reactivar o liberar a una persona (nulo si puede): nunca a uno mismo, el permiso cubre todas sus asignaciones vigentes y la persona no tiene más permisos que quien actúa.';

-- Grupo de una persona (el primero vigente), para ubicar en el alcance las solicitudes y eventos.
create function core.user_group(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.group_id from core.user_memberships m
   where m.user_id = p_user_id and m.deleted_at is null
   order by m.created_at limit 1
$$;
comment on function core.user_group(uuid) is 'Interna. Grupo vigente de una persona (el primero).';

-- ---------------------------------------------------------------------------
-- 4. Desactivar (inmediato) y reactivar (con aprobación de otra persona)
-- ---------------------------------------------------------------------------
create function core.disable_user(p_user_id uuid, p_reason text)
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
    return core.deny('core.disable_user', v_why, p_user_id, null, v_group);
  end if;
  -- Nunca deja al grupo sin Superadministrador ni Dirección General activos (con bloqueo por grupo).
  perform core.lock_group_roles(v_group);
  v_why := core.group_governance_gap(v_group, null, p_user_id);
  if v_why is not null then
    return core.deny('core.disable_user', v_why, p_user_id, null, v_group);
  end if;

  perform core.set_change_context(p_reason, 'app');
  update core.user_profiles
     set status = 'disabled', disabled_at = now(), disabled_reason = btrim(p_reason), disabled_by = core.current_actor_id()
   where id = p_user_id and status = 'active';
  if not found then
    return jsonb_build_object('result', 'already_disabled', 'message', 'La cuenta ya estaba desactivada.');
  end if;

  -- Cierra todas sus sesiones ya mismo. El hook de Auth impide que entre o renueve la sesión,
  -- y has_permission le corta el acceso en la consulta siguiente aunque su token siga vigente.
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;

  perform audit.log_security_event('account_disabled', 'core.disable_user', btrim(p_reason), p_user_id, null, null, v_group);
  return jsonb_build_object('result', 'applied', 'message', 'Cuenta desactivada. Se cerraron todas sus sesiones.');
end
$$;
comment on function core.disable_user(uuid, text) is
  'Desactiva una cuenta al instante: la marca disabled, cierra sus sesiones y lo registra. Pide users.deactivate sobre todas sus asignaciones, nunca sobre uno mismo ni sobre el último superadmin. Conserva toda su historia.';

create function core.request_reactivation(p_user_id uuid, p_reason text)
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
  -- La solicitud va al lugar común de todas sus asignaciones (su local, su marca o el grupo),
  -- así la puede aprobar quien administra ese lugar, no solo alguien de todo el grupo.
  select case when count(distinct coalesce(a.brand_id::text, 'g')) = 1 and bool_and(a.brand_id is not null) then min(a.brand_id::text) end::uuid,
         case when count(distinct coalesce(a.restaurant_id::text, 'x')) = 1 and bool_and(a.restaurant_id is not null) then min(a.restaurant_id::text) end::uuid
    into v_brand, v_rest
    from core.user_role_assignments a
   where a.user_id = p_user_id and a.deleted_at is null and a.group_id = v_group
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now());
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.request_reactivation', v_why, p_user_id, null, v_group);
  end if;
  select * into v_p from core.user_profiles where id = p_user_id;
  if v_p.status <> 'disabled' then
    raise exception 'La cuenta no está desactivada.' using errcode = '23514';
  end if;
  if exists (select 1 from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'core.reactivate_user' and r.subject_user_id = p_user_id and r.status = 'pending') then
    raise exception 'Ya hay una reactivación pendiente para esta persona.' using errcode = '23505';
  end if;
  v_request := workflow.create_request('core.reactivate_user', v_group, v_brand, case when v_brand is not null then v_rest end, p_user_id,
    jsonb_build_object('user_id', p_user_id,
                       'excluded_approvers', case when v_p.disabled_by is not null then jsonb_build_array(v_p.disabled_by) else '[]'::jsonb end),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'La reactivación queda pendiente hasta que la apruebe otra persona, distinta de quien bloqueó la cuenta.');
end
$$;
comment on function core.request_reactivation(uuid, text) is
  'Pide reactivar una cuenta desactivada. Lo aprueba otra persona con users.deactivate, distinta de quien pidió y de quien la bloqueó (ADR-0008).';

create function core.apply_reactivation(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  select (payload ->> 'user_id')::uuid into v_user from workflow.approval_requests where id = p_request_id and status = 'approved';
  if v_user is null then
    raise exception 'La solicitud % no está aprobada.', p_request_id using errcode = '22023';
  end if;
  perform core.set_change_context('Cuenta reactivada (solicitud ' || p_request_id || ')', 'app');
  update core.user_profiles
     set status = 'active', disabled_at = null, disabled_reason = null, disabled_by = null,
         failed_login_count = 0, locked_until = null
   where id = v_user;
  perform audit.log_security_event('account_reactivated', 'core.apply_reactivation', 'Reactivación aprobada', v_user,
                                   null, jsonb_build_object('request_id', p_request_id), core.user_group(v_user));
end
$$;
comment on function core.apply_reactivation(uuid) is 'Interna. Reactiva una cuenta cuando se aprueba la solicitud.';

-- ---------------------------------------------------------------------------
-- 5. Bloqueo temporal por intentos fallidos (P18): 5 fallos seguidos dentro de 10 minutos
--    bloquean 10 minutos. Lo anota la función de ingreso (Edge Function auth-login, con la
--    clave de servidor); un administrador lo puede liberar antes.
-- ---------------------------------------------------------------------------
create function core.login_status(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p core.user_profiles;
begin
  select * into v_p from core.user_profiles where lower(email) = lower(btrim(p_email)) and deleted_at is null;
  return jsonb_build_object(
    'locked', coalesce(v_p.locked_until > now(), false),
    'locked_until', case when v_p.locked_until > now() then v_p.locked_until end);
end
$$;
comment on function core.login_status(text) is
  'Para la función de ingreso: si la cuenta de ese correo está bloqueada temporalmente. No dice si el correo existe. Solo la clave de servidor.';

create function core.record_failed_login(p_email text, p_ip text default null, p_user_agent text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p      core.user_profiles;
  v_count  smallint;
  v_locked timestamptz;
  v_email  text := lower(btrim(p_email));
begin
  select * into v_p from core.user_profiles where lower(email) = v_email and deleted_at is null for update;
  if not found then
    perform audit.log_security_event('login_failed', 'auth.login', 'Correo o contraseña incorrectos.', null, v_email,
                                     null, null, null, null, p_ip, p_user_agent);
    return jsonb_build_object('locked', false);
  end if;

  -- Los fallos cuentan si son seguidos y dentro de los 10 minutos.
  v_count := case when v_p.last_failed_login_at is null or v_p.last_failed_login_at < now() - interval '10 minutes'
                  then 1 else least(v_p.failed_login_count + 1, 1000) end;
  v_locked := case when v_count >= 5 then now() + interval '10 minutes' else v_p.locked_until end;

  perform core.set_change_context('Intento de ingreso fallido', 'edge_function');
  update core.user_profiles
     set failed_login_count = v_count, last_failed_login_at = now(), locked_until = v_locked
   where id = v_p.id;

  perform audit.log_security_event('login_failed', 'auth.login', 'Correo o contraseña incorrectos.', v_p.id, v_email,
                                   jsonb_build_object('failed_count', v_count), core.user_group(v_p.id), null, null, p_ip, p_user_agent);
  if v_count >= 5 and (v_p.locked_until is null or v_p.locked_until <= now()) then
    perform audit.log_security_event('account_locked', 'auth.login', '5 intentos fallidos seguidos: bloqueo de 10 minutos.',
                                     v_p.id, v_email, jsonb_build_object('locked_until', v_locked), core.user_group(v_p.id),
                                     null, null, p_ip, p_user_agent);
  end if;
  return jsonb_build_object('locked', coalesce(v_locked > now(), false), 'locked_until', case when v_locked > now() then v_locked end);
end
$$;
comment on function core.record_failed_login(text, text, text) is
  'Para la función de ingreso: anota un intento fallido y, al quinto seguido dentro de 10 minutos, bloquea la cuenta 10 minutos (P18). Solo la clave de servidor: si la pudiera llamar cualquiera, podría bloquear cuentas ajenas.';

create function core.unlock_user(p_user_id uuid, p_reason text)
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
    return core.deny('core.unlock_user', v_why, p_user_id, null, core.user_group(p_user_id));
  end if;
  perform core.set_change_context(p_reason, 'app');
  update core.user_profiles set locked_until = null, failed_login_count = 0, last_failed_login_at = null
   where id = p_user_id and locked_until > now();
  if not found then
    return jsonb_build_object('result', 'not_locked', 'message', 'La cuenta no estaba bloqueada.');
  end if;
  perform audit.log_security_event('account_unlocked', 'core.unlock_user', btrim(p_reason), p_user_id, null, null,
                                   core.user_group(p_user_id));
  return jsonb_build_object('result', 'applied', 'message', 'Bloqueo liberado.');
end
$$;
comment on function core.unlock_user(uuid, text) is
  'Libera antes de tiempo el bloqueo por intentos fallidos (P18). Pide users.deactivate sobre todas las asignaciones de la persona; no pide aprobación porque el bloqueo se iba a liberar solo. Queda registrado.';

-- ---------------------------------------------------------------------------
-- 6. Custom Access Token hook (ADR-0010): Supabase Auth lo llama antes de entregar cada
--    token, al ingresar y al renovar la sesión. Niega el token a una cuenta desactivada,
--    borrada o bloqueada temporalmente. En un ingreso con contraseña, pone en cero los fallos.
-- ---------------------------------------------------------------------------
create function core.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user   uuid := case when event ->> 'user_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                         then (event ->> 'user_id')::uuid end;
  v_method text := event ->> 'authentication_method';
  v_p      core.user_profiles;
  v_type   core.actor_type;
  v_sa     core.account_status;
begin
  select a.actor_type into v_type from core.actors a where a.id = v_user;

  if v_type = 'service_account' then
    select s.status into v_sa from core.service_accounts s where s.id = v_user and s.deleted_at is null;
    if v_sa is distinct from 'active' then
      return jsonb_build_object('error', jsonb_build_object('http_code', 403,
        'message', 'Esta cuenta técnica no puede ingresar.'));
    end if;
    return jsonb_build_object('claims', event -> 'claims');
  end if;

  select * into v_p from core.user_profiles where id = v_user;
  if not found or v_p.deleted_at is not null or v_p.status <> 'active' or v_p.locked_until > now() then
    if v_p.id is not null and v_method is distinct from 'token_refresh' then
      perform audit.log_security_event('login_failed', 'auth.custom_access_token_hook',
        case when v_p.locked_until > now() then 'Cuenta bloqueada temporalmente por intentos fallidos.'
             else 'Cuenta desactivada.' end, v_p.id, v_p.email, jsonb_build_object('method', v_method),
        core.user_group(v_p.id));
    end if;
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Tu cuenta no puede ingresar en este momento. Si creés que es un error, hablá con quien administra tu local.'));
  end if;

  if v_method = 'password' then
    if v_p.failed_login_count > 0 or v_p.last_failed_login_at is not null then
      perform core.set_change_context('Ingreso exitoso: intentos fallidos en cero', 'auth');
      update core.user_profiles set failed_login_count = 0, last_failed_login_at = null where id = v_p.id;
    end if;
    perform audit.log_security_event('login_succeeded', 'auth.login', 'Ingreso con contraseña.', v_p.id, v_p.email,
                                     null, core.user_group(v_p.id));
  elsif v_method = 'totp' or v_method = 'mfa/totp' then
    perform audit.log_security_event('login_succeeded', 'auth.mfa', 'Doble verificación correcta.', v_p.id, v_p.email,
                                     jsonb_build_object('method', v_method), core.user_group(v_p.id));
  end if;

  return jsonb_build_object('claims', event -> 'claims');
end
$$;
comment on function core.custom_access_token_hook(jsonb) is
  'Hook de Supabase Auth (Custom Access Token): niega el token a cuentas desactivadas, borradas o bloqueadas, al ingresar y al renovar la sesión; registra los ingresos y pone en cero los intentos fallidos. Solo lo ejecuta supabase_auth_admin.';

-- ---------------------------------------------------------------------------
-- 7. Invitación (ADR-0010 y plan M8). La Edge Function invite-user:
--    1) con el JWT de quien invita llama a core.can_invite (valida y registra el rechazo);
--    2) invita con la Admin API de Auth (el trigger crea el perfil);
--    3) con el JWT de quien invita llama a core.add_member y a core.assign_role.
--    Así las reglas de M6 se aplican con la identidad de quien invita, no con la clave de servidor.
-- ---------------------------------------------------------------------------
create function core.can_invite(
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_email         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform core.check_scope(p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
  if not core.has_permission_for_scope('users.invite', p_scope_type, p_group_id, p_brand_id, p_restaurant_id) then
    return core.deny('core.can_invite', 'No tenés permiso para invitar personas a ese lugar.', null,
                     jsonb_build_object('email', lower(p_email)), p_group_id, p_brand_id, p_restaurant_id);
  end if;
  return jsonb_build_object('result', 'allowed');
end
$$;
comment on function core.can_invite(core.scope_type, uuid, uuid, uuid, text) is
  'Si la sesión puede invitar personas a ese lugar (users.invite). Si no, lo registra (ADR-0009).';

create function core.add_member(p_user_id uuid, p_group_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Alcanza con poder invitar en algún lugar del grupo: los roles los limita assign_role.
  if not exists (select 1 from core.actor_grants('users.invite') g where g.group_id = p_group_id) then
    return core.deny('core.add_member', 'No tenés permiso para sumar personas a este grupo.', p_user_id, null, p_group_id);
  end if;
  if exists (select 1 from core.user_memberships where user_id = p_user_id and group_id = p_group_id and deleted_at is null) then
    return jsonb_build_object('result', 'already_member', 'message', 'La persona ya es miembro del grupo.');
  end if;
  perform core.set_change_context(p_reason, 'app');
  insert into core.user_memberships (user_id, group_id) values (p_user_id, p_group_id);
  return jsonb_build_object('result', 'applied', 'message', 'Persona sumada al grupo.');
end
$$;
comment on function core.add_member(uuid, uuid, text) is
  'Suma una persona a un grupo (paso de la invitación). Pide users.invite en algún lugar del grupo y un motivo.';

-- ---------------------------------------------------------------------------
-- 8. Reactivación en el catálogo de aprobaciones (ADR-0008)
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Aprobación de reactivación de cuentas (ADR-0008)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, approver_permission, approver_role_codes, apply_function) values
    ('core.reactivate_user', 'Reactivar una cuenta',
     'Volver a habilitar una cuenta desactivada. La aprueba otra persona con users.deactivate, distinta de quien la bloqueó.',
     'users.deactivate', null, 'core.apply_reactivation(uuid)');
end
$$;

-- ---------------------------------------------------------------------------
-- 9. Sellado de la auditoría y del registro de seguridad cada hora (pg_cron, ADR-0006)
-- ---------------------------------------------------------------------------
set role audit_owner;
create function audit.seal_all()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_audit    audit.audit_seals;
  v_security audit.security_event_seals;
begin
  v_audit := audit.seal_events();
  v_security := audit.seal_security_events();
  return jsonb_build_object('audit_events', coalesce(v_audit.event_count, 0),
                            'security_events', coalesce(v_security.event_count, 0));
end
$$;
comment on function audit.seal_all() is 'Sella la auditoría y el registro de seguridad. La llama la tarea programada cada hora.';
revoke execute on function audit.seal_all() from public;
grant execute on function audit.seal_all() to postgres;
reset role;

create extension if not exists pg_cron;
select cron.schedule('grupo-lf-sellar-auditoria', '7 * * * *', 'select audit.seal_all()');

-- ---------------------------------------------------------------------------
-- 10. Lecturas para las pantallas
-- ---------------------------------------------------------------------------
-- Estado de mi propia sesión. No depende de RLS (una sesión sin doble verificación igual
-- tiene que saber que le falta) y solo devuelve datos de la propia persona.
create function core.my_session()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_p     core.user_profiles;
begin
  if v_actor is null then
    return jsonb_build_object('signed_in', false);
  end if;
  select * into v_p from core.user_profiles where id = v_actor;
  return jsonb_build_object(
    'signed_in', true,
    'user_id', v_actor,
    'has_profile', v_p.id is not null,
    'status', v_p.status,
    'deleted', v_p.deleted_at is not null,
    'locked', coalesce(v_p.locked_until > now(), false),
    'first_name', v_p.first_name,
    'last_name', v_p.last_name,
    'email', v_p.email,
    'aal', core.current_aal(),
    'requires_mfa', exists (
      select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.user_id = v_actor and a.deleted_at is null and r.requires_mfa
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())),
    'has_roles', exists (
      select 1 from core.user_role_assignments a
       where a.user_id = v_actor and a.deleted_at is null
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())),
    'can_operate', core.current_session_ok());
end
$$;
comment on function core.my_session() is
  'Estado de la propia sesión para la interfaz: si tiene perfil, si está activa o bloqueada, si sus roles exigen doble verificación y si puede operar. Solo datos propios.';

-- Nombre visible de una persona (para listas). Interna.
create function core.display_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(nullif(btrim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), ''), p.email, 'Sistema')
    from core.user_profiles p where p.id = p_user_id
$$;
comment on function core.display_name(uuid) is 'Interna. Nombre y apellido (o correo) de una persona, para mostrar.';

-- Tablero de usuarios (adicional A10): personas visibles con sus roles vigentes, paginado por clave.
create function core.users_dashboard(
  p_search        text default null,
  p_restaurant_id uuid default null,
  p_status        text default null,
  p_after_key     text default null,
  p_after_id      uuid default null,
  p_limit         int default 25,
  p_user_id       uuid default null
)
returns table (
  id uuid, first_name text, last_name text, email text, status core.account_status,
  locked boolean, roles jsonb, sort_key text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(lower(btrim(p_search)), '');
  v_r      org.restaurants;
begin
  if p_status is not null and p_status not in ('active', 'disabled', 'locked') then
    raise exception 'Filtro de estado inválido.' using errcode = '22023';
  end if;
  if p_restaurant_id is not null then
    select * into v_r from org.restaurants where org.restaurants.id = p_restaurant_id;
  end if;

  return query
  with visible as (select v as user_id from core.visible_user_ids() as v)
  select p.id, p.first_name, p.last_name, p.email, p.status,
         coalesce(p.locked_until > now(), false),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'assignment_id', a.id, 'role_code', r.code, 'role_name', r.name, 'scope_type', a.scope_type,
                    'scope_name', coalesce(rs.name, b.name, g.name))
                  order by r.level)
             from core.user_role_assignments a
             join core.roles r on r.id = a.role_id
             join org.groups g on g.id = a.group_id
             left join org.brands b on b.id = a.brand_id
             left join org.restaurants rs on rs.id = a.restaurant_id
            where a.user_id = p.id and a.deleted_at is null
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())), '[]'::jsonb),
         lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email) as sort_key
    from core.user_profiles p
    join visible vis on vis.user_id = p.id
   where p.deleted_at is null
     and (p_user_id is null or p.id = p_user_id)
     and (v_search is null
          or position(v_search in lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.email)) > 0)
     and (p_status is null
          or (p_status = 'active' and p.status = 'active' and (p.locked_until is null or p.locked_until <= now()))
          or (p_status = 'disabled' and p.status = 'disabled')
          or (p_status = 'locked' and p.locked_until > now()))
     and (p_restaurant_id is null or exists (
           select 1 from core.user_role_assignments a
            where a.user_id = p.id and a.deleted_at is null and a.group_id = v_r.group_id
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
              and (a.scope_type = 'group'
                   or (a.scope_type = 'brand' and a.brand_id = v_r.brand_id)
                   or (a.scope_type = 'restaurant' and a.restaurant_id = v_r.id))))
     and (p_after_key is null
          or (lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email), p.id) > (p_after_key, p_after_id))
   order by 8, 1
   limit least(greatest(coalesce(p_limit, 25), 1), 100);
end
$$;
comment on function core.users_dashboard(text, uuid, text, text, uuid, int, uuid) is
  'Tablero de usuarios: personas que la sesión puede ver, con sus roles vigentes. Filtra por texto, local y estado; pagina por clave (sort_key + id), hasta 100 por página.';

create function core.users_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    return null;
  end if;
  return (
    with visible as (
      select p.* from core.user_profiles p where p.id in (select core.visible_user_ids()) and p.deleted_at is null
    ),
    current_roles as (
      select a.user_id, r.code, r.name, r.level, r.requires_mfa
        from core.user_role_assignments a join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.user_id in (select id from visible) and a.deleted_at is null
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
    )
    select jsonb_build_object(
      'as_of', now(),
      'active', (select count(*) from visible where status = 'active' and (locked_until is null or locked_until <= now())),
      'disabled', (select count(*) from visible where status = 'disabled'),
      'locked', (select count(*) from visible where locked_until > now()),
      'without_mfa', (select count(distinct cr.user_id) from current_roles cr join visible v on v.id = cr.user_id
                       where cr.requires_mfa and v.status = 'active'
                         and not exists (select 1 from auth.mfa_factors f
                                          where f.user_id = cr.user_id and f.status = 'verified')),
      'pending_approvals', (
        select count(*) from workflow.approval_requests r
         where r.status = 'pending' and r.deleted_at is null
           and (r.requested_by = v_actor or r.subject_user_id = v_actor
                or core.has_permission_for_scope('approvals.view',
                     case when r.restaurant_id is not null then 'restaurant' when r.brand_id is not null then 'brand' else 'group' end::core.scope_type,
                     r.group_id, r.brand_id, r.restaurant_id))),
      'by_role', coalesce((
        select jsonb_agg(jsonb_build_object('role_code', code, 'role_name', name, 'people', people) order by level)
          from (select code, name, level, count(distinct user_id) as people from current_roles group by code, name, level) s), '[]'::jsonb)
    )
  );
end
$$;
comment on function core.users_overview() is
  'Indicadores del tablero de usuarios, solo sobre las personas que la sesión puede ver: activas, desactivadas, bloqueadas, sin doble verificación, aprobaciones pendientes y personas por rol, con la fecha de los datos.';

-- Historial (audit.view por alcance). Los valores de costos y precios se ocultan a quien no
-- tiene costing.view_costs en ese alcance (ADR-0006). La auditoría nunca se expone directo.
create function core.audit_history(p_limit int default 50, p_before bigint default null, p_record_id uuid default null)
returns table (
  sequence_number bigint, occurred_at timestamptz, actor_name text, action text, schema_name text, table_name text,
  record_id uuid, changed_fields text[], old_values jsonb, new_values jsonb, reason text, origin text, place_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group_level boolean := exists (select 1 from core.actor_grants('audit.view') g where g.scope_type = 'group');
begin
  if not core.current_session_ok() then
    return;
  end if;
  return query
  with allowed_restaurants as (select core.permitted_restaurant_ids('audit.view') as id),
  events as (
    select e.*
      from audit.audit_events e
     where (p_before is null or e.sequence_number < p_before)
       and (p_record_id is null or e.record_id = p_record_id)
       and (
         e.scope_restaurant_id in (select id from allowed_restaurants)
         or (e.scope_restaurant_id is null and e.scope_brand_id is not null and core.has_permission_in_brand('audit.view', e.scope_brand_id))
         or (e.scope_restaurant_id is null and e.scope_brand_id is null
             and ((e.scope_group_id is not null and core.has_permission_in_group('audit.view', e.scope_group_id))
                  or (e.scope_group_id is null and v_group_level)))
       )
     order by e.sequence_number desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200)
  )
  select e.sequence_number, e.occurred_at,
         coalesce(core.display_name(e.actor_id), case when e.origin is not null then 'Sistema (' || e.origin::text || ')' else 'Sistema' end),
         e.action::text, e.schema_name, e.table_name, e.record_id, e.changed_fields,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.old_values else core.hide_costs(e.old_values) end,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.new_values else core.hide_costs(e.new_values) end,
         e.reason, e.origin::text,
         coalesce((select r.name from org.restaurants r where r.id = e.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = e.scope_brand_id),
                  (select g.name from org.groups g where g.id = e.scope_group_id))
    from events e
   order by e.sequence_number desc;
end
$$;
comment on function core.audit_history(int, bigint, uuid) is
  'Historial de cambios que la sesión puede ver (audit.view por alcance), del más nuevo al más viejo, con quién, cuándo, qué y por qué. Oculta costos y precios sin costing.view_costs.';

create function core.can_see_costs(p_group_id uuid, p_brand_id uuid, p_restaurant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return case
    when p_restaurant_id is not null then core.has_permission('costing.view_costs', p_restaurant_id)
    when p_brand_id is not null then core.has_permission_in_brand('costing.view_costs', p_brand_id)
    when p_group_id is not null then core.has_permission_in_group('costing.view_costs', p_group_id)
    else false
  end;
end
$$;
comment on function core.can_see_costs(uuid, uuid, uuid) is 'Interna. Si la sesión puede ver costos en ese alcance (costing.view_costs).';

-- Oculta claves de costos y precios en un jsonb (todos los niveles).
create function core.hide_costs(p_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
begin
  return case jsonb_typeof(p_value)
    when 'object' then (
      select coalesce(jsonb_object_agg(k, case when k ~* '(cost|price|margin|amount)' then to_jsonb('[oculto]'::text)
                                               else core.hide_costs(v) end), '{}'::jsonb)
        from jsonb_each(p_value) as e (k, v))
    when 'array' then (select coalesce(jsonb_agg(core.hide_costs(v)), '[]'::jsonb) from jsonb_array_elements(p_value) as e (v))
    else p_value
  end;
end
$$;
comment on function core.hide_costs(jsonb) is 'Interna. Reemplaza por "[oculto]" los valores de claves de costos, precios, márgenes o importes.';

-- Bandeja de aprobaciones: solicitudes que la sesión puede ver, con un resumen en español y si
-- puede decidirlas (con la misma regla que workflow.decide).
create function workflow.inbox(p_limit int default 100)
returns table (
  id uuid, workflow_code text, workflow_name text, status workflow.request_status, requested_at timestamptz,
  requested_by_name text, summary text, reason text, place_name text, can_decide boolean,
  resolved_at timestamptz, resolved_by_name text, resolution_comment text
)
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
  select r.id, w.code, w.name, r.status, r.created_at, core.display_name(r.requested_by),
         case
           when w.code in ('core.assign_sensitive_role', 'core.assign_superadmin') then
             'Dar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.payload ->> 'role_id')::uuid), r.payload ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.change_role_permission' then
             case when (r.payload ->> 'grant')::boolean then 'Dar el permiso ' else 'Quitar el permiso ' end
             || (r.payload ->> 'permission_code') || ' al rol '
             || coalesce((select ro.name from core.roles ro where ro.id = (r.payload ->> 'role_id')::uuid), r.payload ->> 'role_code')
           when w.code = 'org.transfer_restaurant' then
             'Traspasar ' || coalesce((select rs.name from org.restaurants rs where rs.id = (r.payload ->> 'restaurant_id')::uuid), 'un local')
             || ' a la marca ' || coalesce((select b.name from org.brands b where b.id = (r.payload ->> 'target_brand_id')::uuid), '')
           when w.code = 'core.reactivate_user' then
             'Reactivar la cuenta de ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           else w.name
         end,
         r.reason,
         coalesce((select rs.name from org.restaurants rs where rs.id = r.restaurant_id),
                  (select b.name from org.brands b where b.id = r.brand_id),
                  (select g.name from org.groups g where g.id = r.group_id)),
         r.status = 'pending' and workflow.decision_blocker(r.id) is null,
         r.resolved_at, core.display_name(r.resolved_by), r.resolution_comment
    from workflow.approval_requests r
    join workflow.approval_workflows w on w.id = r.workflow_id
   where r.deleted_at is null
     and (r.requested_by = v_actor or r.subject_user_id = v_actor
          or core.has_permission_for_scope('approvals.view',
               case when r.restaurant_id is not null then 'restaurant' when r.brand_id is not null then 'brand' else 'group' end::core.scope_type,
               r.group_id, r.brand_id, r.restaurant_id))
   order by (r.status = 'pending') desc, r.created_at desc
   limit least(greatest(coalesce(p_limit, 100), 1), 200);
end
$$;
comment on function workflow.inbox(int) is
  'Bandeja de aprobaciones: solicitudes visibles para la sesión (las pendientes primero), con un resumen en español y si la sesión puede decidirlas.';

-- ---------------------------------------------------------------------------
-- 11. Permisos de ejecución
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'core.cannot_act_on_user(uuid, text)', 'core.user_group(uuid)', 'core.apply_reactivation(uuid)',
    'core.login_status(text)', 'core.record_failed_login(text, text, text)', 'core.custom_access_token_hook(jsonb)',
    'core.disable_user(uuid, text)', 'core.request_reactivation(uuid, text)', 'core.unlock_user(uuid, text)',
    'core.can_invite(core.scope_type, uuid, uuid, uuid, text)', 'core.add_member(uuid, uuid, text)',
    'core.my_session()', 'core.display_name(uuid)', 'core.users_dashboard(text, uuid, text, text, uuid, int, uuid)',
    'core.users_overview()', 'core.audit_history(int, bigint, uuid)', 'core.can_see_costs(uuid, uuid, uuid)',
    'core.hide_costs(jsonb)', 'workflow.inbox(int)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated, service_role', f);
  end loop;
  foreach f in array array[
    'core.disable_user(uuid, text)', 'core.request_reactivation(uuid, text)', 'core.unlock_user(uuid, text)',
    'core.can_invite(core.scope_type, uuid, uuid, uuid, text)', 'core.add_member(uuid, uuid, text)',
    'core.my_session()', 'core.users_dashboard(text, uuid, text, text, uuid, int, uuid)', 'core.users_overview()',
    'core.audit_history(int, bigint, uuid)', 'workflow.inbox(int)'
  ] loop
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;

-- La clave de servidor (solo dentro de la Edge Function auth-login) puede SOLO consultar el
-- bloqueo y anotar fallos. Nada más: una prueba fija esta lista (ADR-0005, riesgo de service_role).
grant usage on schema core to service_role;
grant execute on function core.login_status(text) to service_role;
grant execute on function core.record_failed_login(text, text, text) to service_role;

-- Supabase Auth ejecuta el hook.
grant usage on schema core to supabase_auth_admin;
grant execute on function core.custom_access_token_hook(jsonb) to supabase_auth_admin;
