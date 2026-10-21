-- Fase 1 · M8 y M9 — Correcciones de las revisiones de base y de seguridad (2026-10-21).
-- Va en una migración nueva porque la de M8 ya está commiteada (database.md).
--   1. Intentos de ingreso por CORREO, exista o no la cuenta: el bloqueo ya no revela qué correos
--      existen. La ventana de 10 minutos cuenta desde el PRIMER fallo, un bloqueo vigente no se
--      extiende y uno vencido se olvida (P18).
--   2. La bandeja de aprobaciones y el historial filtran por conjuntos de alcance (ADR-0012):
--      con 20.000 solicitudes o 500.000 eventos responden en milisegundos.
--   3. El tablero de usuarios solo muestra los roles que la sesión puede ver (RLS), y filtra
--      por marca.
--   4. Reactivar una cuenta vuelve a validar todo al aplicarse, y quien aprueba tiene que poder
--      actuar sobre esa persona (no puede tener menos permisos que ella).

-- ---------------------------------------------------------------------------
-- 1. Intentos de ingreso por correo
-- ---------------------------------------------------------------------------
create table core.login_throttles (
  email             text primary key check (email = lower(email) and length(email) between 3 and 320),
  failed_count      smallint not null default 0 check (failed_count between 0 and 1000),
  window_started_at timestamptz,
  last_failed_at    timestamptz,
  locked_until      timestamptz,
  updated_at        timestamptz not null default now()
);
comment on table core.login_throttles is
  'Contador de intentos fallidos de ingreso por correo (exista o no la cuenta, así el bloqueo no revela qué correos existen). Es el estado del mecanismo de P18: cada intento ya queda en audit.security_events, por eso esta tabla no lleva columnas de control ni auditoría propia.';
comment on column core.login_throttles.email is 'Correo con el que se intentó ingresar, en minúsculas.';
comment on column core.login_throttles.failed_count is 'Fallos seguidos dentro de la ventana actual.';
comment on column core.login_throttles.window_started_at is 'Cuándo fue el primer fallo de la ventana (10 minutos desde acá).';
comment on column core.login_throttles.last_failed_at is 'Cuándo fue el último fallo.';
comment on column core.login_throttles.locked_until is 'Hasta cuándo está bloqueado el ingreso con ese correo. Vacío si no lo está.';
comment on column core.login_throttles.updated_at is 'Cuándo se cambió por última vez.';

alter table core.login_throttles enable row level security;
revoke all on core.login_throttles from public, anon, authenticated, service_role;
create trigger reject_truncate before truncate on core.login_throttles
  for each statement execute function core.reject_truncate();

-- El contador ya no vive en el perfil (cada fallo generaba además un evento de auditoría).
-- En el perfil queda solo locked_until, que es lo que mira has_permission y el hook.
alter table core.user_profiles drop column failed_login_count, drop column last_failed_login_at;
comment on column core.user_profiles.locked_until is
  'Hasta cuándo está bloqueada temporalmente la cuenta por intentos fallidos (10 minutos, P18). Vacío si no lo está. El contador está en core.login_throttles.';

-- Quién desactivó: índice de la FK y coherente con el estado.
create index user_profiles_disabled_by_idx on core.user_profiles (disabled_by) where disabled_by is not null;
alter table core.user_profiles
  add constraint user_profiles_disabled_by_consistent check (status = 'disabled' or disabled_by is null);

create or replace function core.login_status(p_email text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_until timestamptz;
begin
  select t.locked_until into v_until
    from core.login_throttles t
   where t.email = lower(btrim(p_email)) and t.locked_until > now();
  return jsonb_build_object('locked', v_until is not null, 'locked_until', v_until);
end
$$;
comment on function core.login_status(text) is
  'Para la función de ingreso: si el ingreso con ese correo está bloqueado. Responde igual exista o no la cuenta. Solo la clave de servidor.';

create or replace function core.record_failed_login(p_email text, p_ip text default null, p_user_agent text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email   text := lower(btrim(p_email));
  v_t       core.login_throttles;
  v_profile uuid;
  v_group   uuid;
begin
  if v_email is null or length(v_email) < 3 or length(v_email) > 320 then
    return jsonb_build_object('locked', false);
  end if;
  select p.id into v_profile from core.user_profiles p where lower(p.email) = v_email and p.deleted_at is null;
  v_group := case when v_profile is not null then core.user_group(v_profile) end;

  insert into core.login_throttles (email) values (v_email) on conflict (email) do nothing;
  select * into v_t from core.login_throttles where email = v_email for update;

  -- Durante un bloqueo vigente el intento se registra, pero el bloqueo no se extiende.
  if v_t.locked_until > now() then
    perform audit.log_security_event('login_failed', 'auth.login', 'Intento durante un bloqueo.', v_profile, v_email,
                                     null, v_group, null, null, p_ip, p_user_agent);
    return jsonb_build_object('locked', true, 'locked_until', v_t.locked_until);
  end if;

  -- Ventana de 10 minutos desde el PRIMER fallo; un bloqueo ya vencido se olvida.
  if v_t.window_started_at is null or v_t.window_started_at < now() - interval '10 minutes'
     or v_t.locked_until is not null then
    v_t.failed_count := 1;
    v_t.window_started_at := now();
    v_t.locked_until := null;
  else
    v_t.failed_count := least(v_t.failed_count + 1, 1000);
  end if;
  if v_t.failed_count >= 5 then
    v_t.locked_until := now() + interval '10 minutes';
  end if;

  update core.login_throttles
     set failed_count = v_t.failed_count, window_started_at = v_t.window_started_at,
         last_failed_at = now(), locked_until = v_t.locked_until, updated_at = now()
   where email = v_email;

  perform audit.log_security_event('login_failed', 'auth.login', 'Correo o contraseña incorrectos.', v_profile, v_email,
                                   jsonb_build_object('failed_count', v_t.failed_count), v_group, null, null, p_ip, p_user_agent);
  if v_t.locked_until is not null then
    if v_profile is not null then
      perform core.set_change_context('Bloqueo por 5 intentos fallidos de ingreso', 'edge_function');
      update core.user_profiles set locked_until = v_t.locked_until where id = v_profile;
    end if;
    perform audit.log_security_event('account_locked', 'auth.login', '5 intentos fallidos seguidos: bloqueo de 10 minutos.',
                                     v_profile, v_email, jsonb_build_object('locked_until', v_t.locked_until), v_group,
                                     null, null, p_ip, p_user_agent);
  end if;
  return jsonb_build_object('locked', v_t.locked_until is not null, 'locked_until', v_t.locked_until);
end
$$;
comment on function core.record_failed_login(text, text, text) is
  'Para la función de ingreso: anota un intento fallido por correo (exista o no la cuenta) y, al quinto dentro de 10 minutos desde el primero, bloquea 10 minutos (P18). No extiende un bloqueo vigente. Solo la clave de servidor.';

create or replace function core.unlock_user(p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_why   text;
  v_email text;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.unlock_user', v_why, p_user_id, null, core.user_group(p_user_id));
  end if;
  select lower(email) into v_email from core.user_profiles where id = p_user_id;
  perform core.set_change_context(p_reason, 'app');
  update core.user_profiles set locked_until = null where id = p_user_id and locked_until > now();
  if not found then
    return jsonb_build_object('result', 'not_locked', 'message', 'La cuenta no estaba bloqueada.');
  end if;
  delete from core.login_throttles where email = v_email;
  perform audit.log_security_event('account_unlocked', 'core.unlock_user', btrim(p_reason), p_user_id, null, null,
                                   core.user_group(p_user_id));
  return jsonb_build_object('result', 'applied', 'message', 'Bloqueo liberado.');
end
$$;
comment on function core.unlock_user(uuid, text) is
  'Libera antes de tiempo el bloqueo por intentos fallidos (P18). Pide users.deactivate sobre todas las asignaciones de la persona; no pide aprobación porque el bloqueo se iba a liberar solo. Queda registrado.';

create or replace function core.custom_access_token_hook(event jsonb)
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
    -- Un ingreso bueno pone en cero los fallos de ese correo.
    delete from core.login_throttles where email = lower(v_p.email);
    perform audit.log_security_event('login_succeeded', 'auth.login', 'Ingreso con contraseña.', v_p.id, v_p.email,
                                     null, core.user_group(v_p.id));
  elsif v_method in ('totp', 'mfa/totp') then
    perform audit.log_security_event('login_succeeded', 'auth.mfa', 'Doble verificación correcta.', v_p.id, v_p.email,
                                     jsonb_build_object('method', v_method), core.user_group(v_p.id));
  end if;

  return jsonb_build_object('claims', event -> 'claims');
end
$$;
comment on function core.custom_access_token_hook(jsonb) is
  'Hook de Supabase Auth (Custom Access Token): niega el token a cuentas desactivadas, borradas o bloqueadas, al ingresar y al renovar la sesión; registra los ingresos y pone en cero los intentos fallidos. Solo lo ejecuta supabase_auth_admin.';

-- ---------------------------------------------------------------------------
-- 2. Reactivar: se vuelve a validar al aplicar, y quien aprueba tiene que poder actuar sobre la persona
-- ---------------------------------------------------------------------------
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
  v_why := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.request_reactivation', v_why, p_user_id, null, v_group);
  end if;
  select * into v_p from core.user_profiles where id = p_user_id;
  if v_p.status <> 'disabled' then
    raise exception 'La cuenta no está desactivada.' using errcode = '23514';
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
  'Pide reactivar una cuenta desactivada. La aprueba otra persona con users.deactivate que pueda actuar sobre esa persona, distinta de quien pidió y de quien la bloqueó (ADR-0008).';

create or replace function core.apply_reactivation(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_user  uuid := (v_req.payload ->> 'user_id')::uuid;
  v_scope core.scope_type := case when v_req.restaurant_id is not null then 'restaurant'
                                  when v_req.brand_id is not null then 'brand' else 'group' end::core.scope_type;
  v_p     core.user_profiles;
  v_why   text;
begin
  if not core.user_has_permission_for_scope(v_req.requested_by, 'users.deactivate', v_scope,
                                            v_req.group_id, v_req.brand_id, v_req.restaurant_id) then
    perform workflow.cannot_apply('quien la pidió ya no puede reactivar cuentas');
  end if;
  select * into v_p from core.user_profiles where id = v_user for update;
  if v_p.status <> 'disabled' or v_p.deleted_at is not null then
    perform workflow.cannot_apply('la cuenta ya no está desactivada');
  end if;
  -- Quien aprueba (la sesión) tiene que poder actuar sobre la persona: no puede tener menos permisos que ella.
  v_why := core.cannot_act_on_user(v_user, 'users.deactivate');
  if v_why is not null then
    perform workflow.cannot_apply(lower(left(v_why, 1)) || substr(rtrim(v_why, '.'), 2));
  end if;

  perform core.set_change_context('Cuenta reactivada (solicitud ' || p_request_id || ')', 'app');
  update core.user_profiles
     set status = 'active', disabled_at = null, disabled_reason = null, disabled_by = null, locked_until = null
   where id = v_user;
  delete from core.login_throttles where email = lower(v_p.email);
  perform audit.log_security_event('account_reactivated', 'core.apply_reactivation', 'Reactivación aprobada', v_user,
                                   null, jsonb_build_object('request_id', p_request_id), core.user_group(v_user));
end
$$;
comment on function core.apply_reactivation(uuid) is
  'Interna. Reactiva una cuenta cuando se aprueba la solicitud, después de volver a validar que quien pidió puede, que la cuenta sigue desactivada y que quien aprueba puede actuar sobre esa persona.';

-- Misma regla en la bandeja: no se ofrece "Aprobar" a quien no podría aplicarla.
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

  if not core.has_permission_for_scope(v_wf.approver_permission, v_scope, v_req.group_id, v_req.brand_id, v_req.restaurant_id)
     -- El rol exigido (por ejemplo, Dirección General) tiene que ser de TODO el grupo.
     or (cardinality(coalesce(v_wf.approver_role_codes, '{}')) > 0
         and not core.has_role_for_scope(v_wf.approver_role_codes, 'group', v_req.group_id)) then
    return 'No podés decidir esta solicitud.';
  end if;

  -- Quien pidió, la persona afectada y las personas que la solicitud excluye (por ejemplo,
  -- quien bloqueó la cuenta o quienes tienen el rol que se cambia) no pueden decidir.
  select coalesce(array_agg(x::uuid), '{}') into v_excluded
    from jsonb_array_elements_text(coalesce(v_req.payload -> 'excluded_approvers', '[]'::jsonb)) as x;
  -- En un cambio de la matriz, tampoco decide quien tiene HOY ese rol (aunque lo haya recibido
  -- después del pedido): se beneficiaría del cambio.
  if v_wf.code = 'core.change_role_permission' and exists (
       select 1 from core.user_role_assignments a
        where a.user_id = v_actor and a.role_id = (v_req.payload ->> 'role_id')::uuid and a.deleted_at is null) then
    v_excluded := v_excluded || v_actor;
  end if;
  if v_actor = v_req.requested_by or v_actor = v_req.subject_user_id or v_actor = any (v_excluded) then
    return 'No podés decidir una solicitud propia o que te afecta: la tiene que decidir otra persona.';
  end if;
  -- En una reactivación, quien aprueba tiene que poder actuar sobre esa persona.
  if v_wf.code = 'core.reactivate_user' and core.cannot_act_on_user(v_req.subject_user_id, 'users.deactivate') is not null then
    return 'No podés decidir esta solicitud: la persona tiene roles o permisos fuera de los tuyos.';
  end if;
  return null;
end
$$;

create or replace function core.add_member(p_user_id uuid, p_group_id uuid, p_reason text)
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
  if not exists (select 1 from core.user_profiles u where u.id = p_user_id and u.status = 'active' and u.deleted_at is null) then
    raise exception 'La persona no existe o tiene la cuenta bloqueada.' using errcode = '23514';
  end if;
  if exists (select 1 from core.user_memberships where user_id = p_user_id and group_id = p_group_id and deleted_at is null) then
    return jsonb_build_object('result', 'already_member', 'message', 'La persona ya es miembro del grupo.');
  end if;
  perform core.set_change_context(p_reason, 'app');
  insert into core.user_memberships (user_id, group_id) values (p_user_id, p_group_id);
  return jsonb_build_object('result', 'applied', 'message', 'Persona sumada al grupo.');
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Tablero de usuarios: solo roles visibles, filtro por marca, cursor completo
-- ---------------------------------------------------------------------------
drop function core.users_dashboard(text, uuid, text, text, uuid, int, uuid);
create function core.users_dashboard(
  p_search        text default null,
  p_brand_id      uuid default null,
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
  v_b      org.brands;
begin
  if p_status is not null and p_status not in ('active', 'disabled', 'locked') then
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
comment on function core.users_dashboard(text, uuid, uuid, text, text, uuid, int, uuid) is
  'Tablero de usuarios: personas que la sesión puede ver, con los roles vigentes que también puede ver. Filtra por texto, marca, local y estado; pagina por clave (sort_key + id), hasta 100 por página.';

drop function core.users_overview();
create function core.users_overview(p_brand_id uuid default null, p_restaurant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_r     org.restaurants;
  v_b     org.brands;
begin
  if v_actor is null or not core.current_session_ok() then
    return null;
  end if;
  if p_restaurant_id is not null then
    select * into v_r from org.restaurants where id = p_restaurant_id;
  end if;
  if p_brand_id is not null then
    select * into v_b from org.brands where id = p_brand_id;
  end if;
  return (
    with visible as (
      select p.* from core.user_profiles p
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
                  and (a.scope_type = 'group' or a.brand_id = v_b.id)))
    ),
    current_roles as (
      select a.user_id, r.code, r.name, r.level, r.requires_mfa
        from core.user_role_assignments a
        join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.id in (select core.visible_assignment_ids())
         and a.user_id in (select id from visible) and a.deleted_at is null
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
      -- Aprobaciones pendientes visibles (misma regla que la política, por conjuntos).
      'pending_approvals', (
        select count(*) from workflow.approval_requests r
         where r.status = 'pending' and r.deleted_at is null
           and (r.requested_by = v_actor or r.subject_user_id = v_actor
                or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
                or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
                or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))),
      'by_role', coalesce((
        select jsonb_agg(jsonb_build_object('role_code', code, 'role_name', name, 'people', people) order by level)
          from (select code, name, level, count(distinct user_id) as people from current_roles group by code, name, level) s), '[]'::jsonb)
    )
  );
end
$$;
comment on function core.users_overview(uuid, uuid) is
  'Indicadores del tablero de usuarios, solo sobre las personas que la sesión puede ver (y, si se pide, de una marca o un local): activas, desactivadas, bloqueadas, sin doble verificación, aprobaciones pendientes y personas por rol, con la fecha de los datos.';

-- ---------------------------------------------------------------------------
-- 4. Bandeja de aprobaciones por conjuntos, con pendientes y resueltas por separado y cursor
-- ---------------------------------------------------------------------------
create index approval_requests_status_created_idx on workflow.approval_requests (status, created_at desc, id desc)
  where deleted_at is null;

drop function workflow.inbox(int);
create function workflow.inbox(
  p_pending           boolean default true,
  p_limit             int default 50,
  p_before_created_at timestamptz default null,
  p_before_id         uuid default null
)
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
  select r.id, w.code, w.name, r.status, r.created_at, core.display_name(r.requested_by),
         case
           when w.code in ('core.assign_sensitive_role', 'core.assign_superadmin', 'core.assign_by_superadmin') then
             'Dar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.payload ->> 'role_id')::uuid), r.payload ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.revoke_by_superadmin' then
             'Quitar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.payload ->> 'role_id')::uuid), r.payload ->> 'role_code')
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
    from page r
    join workflow.approval_workflows w on w.id = r.workflow_id
   order by r.created_at desc, r.id desc;
end
$$;
comment on function workflow.inbox(boolean, int, timestamptz, uuid) is
  'Bandeja de aprobaciones: las pendientes o las resueltas que la sesión puede ver, de la más nueva a la más vieja, con un resumen en español y si la sesión puede decidirlas. Pagina por fecha e id, hasta 100 por página.';

-- ---------------------------------------------------------------------------
-- 5. Historial por alcance con índices: cada local, marca o grupo visible se lee por su índice
-- ---------------------------------------------------------------------------
set role audit_owner;
create index audit_events_restaurant_seq_idx on audit.audit_events (scope_restaurant_id, sequence_number desc)
  where scope_restaurant_id is not null;
create index audit_events_brand_seq_idx on audit.audit_events (scope_brand_id, sequence_number desc)
  where scope_restaurant_id is null and scope_brand_id is not null;
create index audit_events_group_seq_idx on audit.audit_events (scope_group_id, sequence_number desc)
  where scope_brand_id is null and scope_group_id is not null;
create index audit_events_unscoped_seq_idx on audit.audit_events (sequence_number desc)
  where scope_group_id is null;
create index audit_events_record_seq_idx on audit.audit_events (record_id, sequence_number desc);
reset role;

create or replace function core.audit_history(p_limit int default 50, p_before bigint default null, p_record_id uuid default null)
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
  v_limit       int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_before      bigint := coalesce(p_before, 9223372036854775807);
  v_group_level boolean;
begin
  if not core.current_session_ok() then
    return;
  end if;
  v_group_level := exists (select 1 from core.permitted_group_ids('audit.view'));
  return query
  -- Por cada local, marca y grupo visibles se toman los últimos eventos por su índice, y
  -- recién después se juntan. Así quien ve poco no recorre toda la auditoría.
  with events as (
    select e.* from unnest(array(select core.permitted_restaurant_ids('audit.view'))) as rid
      cross join lateral (
        select x.* from audit.audit_events x
         where x.scope_restaurant_id = rid and x.sequence_number < v_before
           and (p_record_id is null or x.record_id = p_record_id)
         order by x.sequence_number desc limit v_limit) e
    union all
    select e.* from unnest(array(select core.permitted_brand_ids('audit.view'))) as bid
      cross join lateral (
        select x.* from audit.audit_events x
         where x.scope_restaurant_id is null and x.scope_brand_id = bid and x.sequence_number < v_before
           and (p_record_id is null or x.record_id = p_record_id)
         order by x.sequence_number desc limit v_limit) e
    union all
    select e.* from unnest(array(select core.permitted_group_ids('audit.view'))) as gid
      cross join lateral (
        select x.* from audit.audit_events x
         where x.scope_brand_id is null and x.scope_group_id = gid and x.sequence_number < v_before
           and (p_record_id is null or x.record_id = p_record_id)
         order by x.sequence_number desc limit v_limit) e
    union all
    -- Eventos sin alcance (por ejemplo, el catálogo de roles): solo con audit.view de todo el grupo.
    (select x.* from audit.audit_events x
      where v_group_level and x.scope_group_id is null and x.sequence_number < v_before
        and (p_record_id is null or x.record_id = p_record_id)
      order by x.sequence_number desc limit v_limit)
  ),
  page as (select * from events order by events.sequence_number desc limit v_limit)
  select e.sequence_number, e.occurred_at,
         coalesce(core.display_name(e.actor_id), case when e.origin is not null then 'Sistema (' || e.origin::text || ')' else 'Sistema' end),
         e.action::text, e.schema_name, e.table_name, e.record_id, e.changed_fields,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.old_values else core.hide_costs(e.old_values) end,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.new_values else core.hide_costs(e.new_values) end,
         e.reason, e.origin::text,
         coalesce((select r.name from org.restaurants r where r.id = e.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = e.scope_brand_id),
                  (select g.name from org.groups g where g.id = e.scope_group_id))
    from page e
   order by e.sequence_number desc;
end
$$;
comment on function core.audit_history(int, bigint, uuid) is
  'Historial de cambios que la sesión puede ver (audit.view por alcance), del más nuevo al más viejo, con quién, cuándo, qué y por qué. Lee por índice cada alcance visible. Oculta costos y precios sin costing.view_costs.';

-- ---------------------------------------------------------------------------
-- 6. Permisos y mantenimiento
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'core.users_dashboard(text, uuid, uuid, text, text, uuid, int, uuid)', 'core.users_overview(uuid, uuid)',
    'workflow.inbox(boolean, int, timestamptz, uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon, service_role', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;

-- El historial de corridas de pg_cron no crece sin límite.
select cron.schedule('grupo-lf-limpiar-corridas', '30 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);
