-- Fase 1 · M6 + M7 — Registro de seguridad, aprobaciones, dar roles sin escalada,
-- cambio de matriz, traspaso de locales y reglas de versiones.
-- Decisiones: ADR-0007 (traspaso), ADR-0008 (qué pide aprobación), ADR-0009 (operaciones
-- rechazadas), y la de Joaco del 2026-10-20: el Superadministrador puede pedir cualquier rol,
-- y si aprueba cosas o es superadmin lo tiene que aprobar Dirección General.
--
-- Patrón de las funciones críticas (ADR-0009): validan el permiso ANTES de cambiar nada; si
-- falta, anotan el intento en audit.security_events y terminan SIN error, devolviendo
-- {"result": "denied", ...}. Así el intento queda guardado. Los errores de datos (alcance
-- incoherente, persona inexistente) siguen siendo errores comunes.

-- ---------------------------------------------------------------------------
-- 1. Registro de seguridad (ADR-0009 y ADR-0010): solo inserción, sellado como la auditoría
-- ---------------------------------------------------------------------------
set role audit_owner;

create type audit.security_event_type as enum (
  'login_succeeded', 'login_failed', 'account_locked', 'account_unlocked',
  'operation_denied', 'account_disabled', 'account_reactivated'
);
comment on type audit.security_event_type is
  'Tipo de evento de seguridad: ingreso bueno o fallido, cuenta bloqueada o liberada (intentos fallidos), operación rechazada por falta de permiso, cuenta desactivada o reactivada.';

create table audit.security_events (
  id                   uuid primary key default gen_random_uuid(),
  sequence_number      bigint generated always as identity,
  occurred_at          timestamptz not null default now(),
  event_type           audit.security_event_type not null,
  actor_id             uuid references core.actors (id) on delete restrict,
  actor_subject        text,
  jwt_role             text,
  db_user              text not null default session_user,
  target_user_id       uuid references core.actors (id) on delete restrict,
  email                text check (email is null or length(email) <= 320),
  operation            text check (operation is null or length(operation) <= 100),
  reason               text check (reason is null or length(reason) <= 500),
  details              jsonb,
  scope_group_id       uuid,
  scope_brand_id       uuid,
  scope_restaurant_id  uuid,
  ip                   text check (ip is null or length(ip) <= 64),
  user_agent           text check (user_agent is null or length(user_agent) <= 300)
);

comment on table audit.security_events is
  'Registro de seguridad inalterable: ingresos, intentos fallidos, bloqueos y operaciones rechazadas por falta de permiso (ADR-0009, ADR-0010). Solo se inserta desde audit.log_security_event(); los sellos detectan alteraciones.';
comment on column audit.security_events.id is 'Identificador del evento.';
comment on column audit.security_events.sequence_number is 'Orden exacto de los eventos. Base de los sellos.';
comment on column audit.security_events.occurred_at is 'Cuándo ocurrió.';
comment on column audit.security_events.event_type is 'Qué pasó.';
comment on column audit.security_events.actor_id is 'Quién lo intentó o lo hizo, según el JWT. Nulo si no había sesión (por ejemplo, un ingreso).';
comment on column audit.security_events.actor_subject is 'El sub del JWT cuando no corresponde a ningún actor registrado.';
comment on column audit.security_events.jwt_role is 'Rol del JWT de la sesión (authenticated, service_role...).';
comment on column audit.security_events.db_user is 'Usuario de Postgres de la conexión.';
comment on column audit.security_events.target_user_id is 'Persona afectada (por ejemplo, la cuenta que se intentó usar o a quien se le quiso dar un rol).';
comment on column audit.security_events.email is 'Correo con el que se intentó ingresar, en minúsculas. Puede no existir.';
comment on column audit.security_events.operation is 'Función o acción que se intentó (por ejemplo, core.assign_role).';
comment on column audit.security_events.reason is 'Por qué se rechazó o qué pasó, en español.';
comment on column audit.security_events.details is 'Datos de contexto, sin secretos.';
comment on column audit.security_events.scope_group_id is 'Grupo afectado, si corresponde.';
comment on column audit.security_events.scope_brand_id is 'Marca afectada, si corresponde.';
comment on column audit.security_events.scope_restaurant_id is 'Restaurante afectado, si corresponde.';
comment on column audit.security_events.ip is 'Dirección IP informada por el servidor que atendió el pedido. Informativa: se puede falsear.';
comment on column audit.security_events.user_agent is 'Navegador o cliente informado. Informativo.';

create unique index security_events_sequence_idx on audit.security_events (sequence_number);
create index security_events_target_idx on audit.security_events (target_user_id, occurred_at desc) where target_user_id is not null;
create index security_events_actor_idx on audit.security_events (actor_id, occurred_at desc) where actor_id is not null;
create index security_events_email_idx on audit.security_events (email, occurred_at desc) where email is not null;
create index security_events_type_idx on audit.security_events (event_type, occurred_at desc);
create index security_events_occurred_at_idx on audit.security_events (occurred_at);

alter table audit.security_events enable row level security;
revoke all on audit.security_events from public, anon, authenticated, service_role;

create trigger security_events_no_update_delete
  before update or delete on audit.security_events
  for each row execute function audit.reject_change();
create trigger security_events_no_truncate
  before truncate on audit.security_events
  for each statement execute function audit.reject_change();

create function audit.log_security_event(
  p_event_type     audit.security_event_type,
  p_operation      text,
  p_reason         text,
  p_target_user_id uuid default null,
  p_email          text default null,
  p_details        jsonb default null,
  p_group_id       uuid default null,
  p_brand_id       uuid default null,
  p_restaurant_id  uuid default null,
  p_ip             text default null,
  p_user_agent     text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject   text := core.current_actor_subject();
  v_actor     uuid := core.current_actor_id();
  v_actor_id  uuid;
  v_target_id uuid;
  v_group     uuid := p_group_id;
  v_brand     uuid := p_brand_id;
  v_id        uuid;
begin
  if v_actor is not null then
    select a.id into v_actor_id from core.actors a where a.id = v_actor;
  end if;
  if p_target_user_id is not null then
    select a.id into v_target_id from core.actors a where a.id = p_target_user_id;
  end if;
  -- El alcance sale de la estructura, como en la auditoría.
  if p_restaurant_id is not null then
    select r.brand_id, r.group_id into v_brand, v_group from org.restaurants r where r.id = p_restaurant_id;
  elsif p_brand_id is not null then
    select b.group_id into v_group from org.brands b where b.id = p_brand_id;
  end if;

  insert into audit.security_events (
    event_type, actor_id, actor_subject, jwt_role, target_user_id, email, operation, reason, details,
    scope_group_id, scope_brand_id, scope_restaurant_id, ip, user_agent
  ) values (
    p_event_type, v_actor_id, case when v_actor_id is null then v_subject end,
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    v_target_id, lower(left(p_email, 320)), left(p_operation, 100), left(p_reason, 500), audit.redact(p_details),
    v_group, v_brand, p_restaurant_id, left(p_ip, 64), left(p_user_agent, 300)
  )
  returning id into v_id;
  return v_id;
end
$$;
comment on function audit.log_security_event(audit.security_event_type, text, text, uuid, text, jsonb, uuid, uuid, uuid, text, text) is
  'Anota un evento de seguridad. Quién lo hizo sale del JWT; el alcance, de la estructura. Los detalles pasan por audit.redact (sin secretos). Solo la llaman funciones de servidor.';

-- Sellos del registro de seguridad: misma idea que audit.audit_seals, con su propia cadena.
create table audit.security_event_seals (
  id              bigint generated always as identity primary key,
  sealed_at       timestamptz not null default now(),
  first_sequence  bigint not null,
  last_sequence   bigint not null,
  event_count     int not null check (event_count > 0),
  previous_hash   bytea not null,
  chain_hash      bytea not null,
  check (first_sequence <= last_sequence)
);
comment on table audit.security_event_seals is 'Sellos del registro de seguridad: cada uno cubre un tramo de eventos y encadena su huella con el anterior.';
comment on column audit.security_event_seals.id is 'Número de sello, en orden.';
comment on column audit.security_event_seals.sealed_at is 'Cuándo se selló el tramo.';
comment on column audit.security_event_seals.first_sequence is 'Primer sequence_number del tramo sellado.';
comment on column audit.security_event_seals.last_sequence is 'Último sequence_number del tramo sellado.';
comment on column audit.security_event_seals.event_count is 'Cantidad de eventos del tramo al sellarlo.';
comment on column audit.security_event_seals.previous_hash is 'Huella del sello anterior (o la inicial, en el primero).';
comment on column audit.security_event_seals.chain_hash is 'Huella acumulada hasta el último evento del tramo.';

alter table audit.security_event_seals enable row level security;
revoke all on audit.security_event_seals from public, anon, authenticated, service_role;
create trigger security_event_seals_no_update_delete
  before update or delete on audit.security_event_seals
  for each row execute function audit.reject_change();
create trigger security_event_seals_no_truncate
  before truncate on audit.security_event_seals
  for each statement execute function audit.reject_change();

create function audit.security_genesis_hash()
returns bytea
language sql
immutable
set search_path = ''
as $$ select sha256(convert_to('grupo-lf:security:genesis', 'UTF8')) $$;
comment on function audit.security_genesis_hash() is 'Huella inicial de la cadena de sellos del registro de seguridad.';

create function audit.security_event_digest(p_event audit.security_events)
returns bytea
language sql
immutable
set search_path = ''
as $$ select sha256(convert_to(to_jsonb(p_event)::text, 'UTF8')) $$;
comment on function audit.security_event_digest(audit.security_events) is 'Huella de un evento de seguridad completo.';

create function audit.seal_security_events(p_min_age interval default interval '10 minutes')
returns audit.security_event_seals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last    audit.security_event_seals;
  v_hash    bytea;
  v_prev    bytea;
  v_first   bigint;
  v_lastseq bigint;
  v_count   int := 0;
  v_event   audit.security_events;
  v_seal    audit.security_event_seals;
begin
  lock table audit.security_event_seals in exclusive mode;

  select * into v_last from audit.security_event_seals order by id desc limit 1;
  v_prev := coalesce(v_last.chain_hash, audit.security_genesis_hash());
  v_hash := v_prev;

  for v_event in
    select * from audit.security_events
     where sequence_number > coalesce(v_last.last_sequence, 0)
       and occurred_at < now() - p_min_age
     order by sequence_number
  loop
    v_hash := sha256(v_hash || audit.security_event_digest(v_event));
    v_first := coalesce(v_first, v_event.sequence_number);
    v_lastseq := v_event.sequence_number;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    return null;
  end if;

  insert into audit.security_event_seals (first_sequence, last_sequence, event_count, previous_hash, chain_hash)
  values (v_first, v_lastseq, v_count, v_prev, v_hash)
  returning * into v_seal;
  return v_seal;
end
$$;
comment on function audit.seal_security_events(interval) is
  'Sella los eventos de seguridad todavía no sellados con más de p_min_age de antigüedad. Devuelve el sello nuevo, o nulo si no había nada.';

create function audit.verify_security_seals()
returns table (seal_id bigint, is_valid boolean, expected_events int, found_events int)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seal      audit.security_event_seals;
  v_hash      bytea := audit.security_genesis_hash();
  v_count     int;
  v_event     audit.security_events;
  v_prev_last bigint := 0;
begin
  for v_seal in select * from audit.security_event_seals order by id loop
    v_count := 0;
    if v_seal.previous_hash <> v_hash then
      seal_id := v_seal.id; is_valid := false; expected_events := v_seal.event_count; found_events := null;
      return next;
      v_hash := v_seal.chain_hash;
      v_prev_last := v_seal.last_sequence;
      continue;
    end if;

    for v_event in
      select * from audit.security_events
       where sequence_number > v_prev_last and sequence_number <= v_seal.last_sequence
       order by sequence_number
    loop
      v_hash := sha256(v_hash || audit.security_event_digest(v_event));
      v_count := v_count + 1;
    end loop;

    seal_id := v_seal.id;
    is_valid := (v_hash = v_seal.chain_hash and v_count = v_seal.event_count);
    expected_events := v_seal.event_count;
    found_events := v_count;
    return next;

    v_hash := v_seal.chain_hash;
    v_prev_last := v_seal.last_sequence;
  end loop;
end
$$;
comment on function audit.verify_security_seals() is
  'Recalcula la cadena de sellos del registro de seguridad y devuelve, para cada sello, si sus eventos siguen intactos.';

revoke execute on all functions in schema audit from public;
grant execute on function audit.log_security_event(audit.security_event_type, text, text, uuid, text, jsonb, uuid, uuid, uuid, text, text) to postgres;
grant select on audit.security_events, audit.security_event_seals to postgres;

reset role;

-- ---------------------------------------------------------------------------
-- 2. Aprobaciones (workflow)
-- ---------------------------------------------------------------------------
create type workflow.request_status as enum ('pending', 'approved', 'rejected', 'cancelled');
comment on type workflow.request_status is
  'Estado de una solicitud de aprobación: pending (esperando), approved (aprobada y aplicada), rejected (rechazada) o cancelled (retirada por quien la pidió).';

create type workflow.decision as enum ('approved', 'rejected');
comment on type workflow.decision is 'Decisión de una persona sobre una solicitud: approved (aprueba) o rejected (rechaza).';

create table workflow.approval_workflows (
  id                          uuid primary key default gen_random_uuid(),
  code                        text not null check (code ~ '^[a-z_]+\.[a-z_]+$'),
  name                        text not null check (length(btrim(name)) between 1 and 120),
  description                 text check (description is null or length(description) <= 500),
  approver_permission         text not null default 'approvals.decide',
  approver_role_codes         text[],
  required_approvals          smallint not null default 1 check (required_approvals between 1 and 5),
  requires_different_approver boolean not null default true,
  apply_function              regprocedure not null,
  is_active                   boolean not null default true,
  created_at                  timestamptz not null default now(),
  created_by                  uuid references core.actors (id) on delete restrict,
  updated_at                  timestamptz not null default now(),
  updated_by                  uuid references core.actors (id) on delete restrict,
  deleted_at                  timestamptz,
  deleted_by                  uuid references core.actors (id) on delete restrict
);

comment on table workflow.approval_workflows is 'Qué tipos de cambio necesitan aprobación y quién la da (ADR-0008). Se ajusta desde el panel con workflows.manage.';
comment on column workflow.approval_workflows.id is 'Identificador del tipo de aprobación.';
comment on column workflow.approval_workflows.code is 'Código del tipo de cambio (por ejemplo, core.assign_sensitive_role).';
comment on column workflow.approval_workflows.name is 'Nombre en español.';
comment on column workflow.approval_workflows.description is 'Qué cambio aprueba.';
comment on column workflow.approval_workflows.approver_permission is 'Permiso que tiene que tener quien aprueba, en el alcance de la solicitud.';
comment on column workflow.approval_workflows.approver_role_codes is 'Si no está vacío, quien aprueba además tiene que tener uno de estos roles en ese alcance (por ejemplo, general_management).';
comment on column workflow.approval_workflows.required_approvals is 'Cuántas aprobaciones hacen falta (hoy, una).';
comment on column workflow.approval_workflows.requires_different_approver is 'Si quien aprueba tiene que ser una persona distinta de quien pidió (y de la persona afectada).';
comment on column workflow.approval_workflows.apply_function is 'Función que aplica el cambio cuando se aprueba. Recibe el id de la solicitud.';
comment on column workflow.approval_workflows.is_active is 'Si este tipo de aprobación está en uso.';
comment on column workflow.approval_workflows.created_at is 'Cuándo se creó (lo pone la base).';
comment on column workflow.approval_workflows.created_by is 'Quién lo creó (lo pone la base).';
comment on column workflow.approval_workflows.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column workflow.approval_workflows.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column workflow.approval_workflows.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column workflow.approval_workflows.deleted_by is 'Quién lo borró (lo pone la base).';

create unique index approval_workflows_code_key on workflow.approval_workflows (code) where deleted_at is null;

create table workflow.approval_requests (
  id                 uuid primary key default gen_random_uuid(),
  workflow_id        uuid not null references workflow.approval_workflows (id) on delete restrict,
  group_id           uuid not null references org.groups (id) on delete restrict,
  brand_id           uuid,
  restaurant_id      uuid,
  requested_by       uuid not null references core.actors (id) on delete restrict,
  subject_user_id    uuid references core.actors (id) on delete restrict,
  payload            jsonb not null check (jsonb_typeof(payload) = 'object'),
  reason             text not null check (length(btrim(reason)) between 1 and 500),
  status             workflow.request_status not null default 'pending',
  resolved_at        timestamptz,
  resolved_by        uuid references core.actors (id) on delete restrict,
  resolution_comment text check (resolution_comment is null or length(resolution_comment) <= 500),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint approval_requests_scope_consistent check (restaurant_id is null or brand_id is not null),
  constraint approval_requests_resolution_consistent check ((status = 'pending') = (resolved_at is null)),
  constraint approval_requests_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  constraint approval_requests_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint approval_requests_restaurant_brand_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict
);

comment on table workflow.approval_requests is
  'Solicitud de aprobación de un cambio. Lo que se pide (payload) no cambia después de creada: lo que se aprueba es exactamente lo que se aplica.';
comment on column workflow.approval_requests.id is 'Identificador de la solicitud.';
comment on column workflow.approval_requests.workflow_id is 'Tipo de aprobación.';
comment on column workflow.approval_requests.group_id is 'Grupo del cambio.';
comment on column workflow.approval_requests.brand_id is 'Marca del cambio, si corresponde.';
comment on column workflow.approval_requests.restaurant_id is 'Restaurante del cambio, si corresponde.';
comment on column workflow.approval_requests.requested_by is 'Quién pidió el cambio.';
comment on column workflow.approval_requests.subject_user_id is 'Persona afectada por el cambio, si hay una (no puede aprobarlo).';
comment on column workflow.approval_requests.payload is 'Qué se va a aplicar si se aprueba. No cambia nunca.';
comment on column workflow.approval_requests.reason is 'Por qué se pide.';
comment on column workflow.approval_requests.status is 'Estado de la solicitud.';
comment on column workflow.approval_requests.resolved_at is 'Cuándo se resolvió. Vacío mientras está pendiente.';
comment on column workflow.approval_requests.resolved_by is 'Quién la resolvió (aprobó, rechazó o retiró).';
comment on column workflow.approval_requests.resolution_comment is 'Comentario de la resolución.';
comment on column workflow.approval_requests.created_at is 'Cuándo se pidió (lo pone la base).';
comment on column workflow.approval_requests.created_by is 'Quién la creó (lo pone la base).';
comment on column workflow.approval_requests.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column workflow.approval_requests.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column workflow.approval_requests.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column workflow.approval_requests.deleted_by is 'Quién la borró (lo pone la base).';

create index approval_requests_workflow_idx on workflow.approval_requests (workflow_id);
create index approval_requests_group_idx on workflow.approval_requests (group_id, status, created_at desc);
create index approval_requests_brand_idx on workflow.approval_requests (brand_id, group_id) where brand_id is not null;
create index approval_requests_restaurant_idx on workflow.approval_requests (restaurant_id, group_id) where restaurant_id is not null;
create index approval_requests_pending_idx on workflow.approval_requests (created_at desc) where status = 'pending';
create index approval_requests_requested_by_idx on workflow.approval_requests (requested_by, created_at desc);
create index approval_requests_subject_idx on workflow.approval_requests (subject_user_id) where subject_user_id is not null;
create index approval_requests_restaurant_brand_idx on workflow.approval_requests (restaurant_id, brand_id) where restaurant_id is not null;
create index approval_requests_resolved_by_idx on workflow.approval_requests (resolved_by) where resolved_by is not null;

create table workflow.approval_decisions (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references workflow.approval_requests (id) on delete restrict,
  decided_by  uuid not null references core.actors (id) on delete restrict,
  decision    workflow.decision not null,
  comment     text check (comment is null or length(comment) <= 500),
  decided_at  timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint approval_decisions_once unique (request_id, decided_by)
);
create index approval_decisions_decided_by_idx on workflow.approval_decisions (decided_by, decided_at desc);

comment on table workflow.approval_decisions is 'Decisiones sobre las solicitudes: quién, cuándo y qué decidió. Solo de inserción: una decisión no se cambia ni se borra.';
comment on column workflow.approval_decisions.id is 'Identificador de la decisión.';
comment on column workflow.approval_decisions.request_id is 'Solicitud decidida.';
comment on column workflow.approval_decisions.decided_by is 'Quién decidió.';
comment on column workflow.approval_decisions.decision is 'Aprobó o rechazó.';
comment on column workflow.approval_decisions.comment is 'Comentario de quien decidió.';
comment on column workflow.approval_decisions.decided_at is 'Cuándo decidió.';
comment on column workflow.approval_decisions.created_at is 'Cuándo se registró (lo pone la base).';
comment on column workflow.approval_decisions.created_by is 'Quién lo registró (lo pone la base).';
comment on column workflow.approval_decisions.updated_at is 'No cambia: la decisión es inalterable.';
comment on column workflow.approval_decisions.updated_by is 'No cambia: la decisión es inalterable.';
comment on column workflow.approval_decisions.deleted_at is 'Nunca se usa: la decisión no se borra.';
comment on column workflow.approval_decisions.deleted_by is 'Nunca se usa: la decisión no se borra.';

-- Reglas de las solicitudes y decisiones.
create function workflow.enforce_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_when <> 'BEFORE' or tg_level <> 'ROW' then
    raise exception 'workflow.enforce_rules() se conecta como BEFORE ... FOR EACH ROW.';
  end if;

  if tg_table_name = 'approval_decisions' then
    if tg_op <> 'INSERT' then
      raise exception 'Una decisión de aprobación no se cambia ni se borra.' using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_table_name = 'approval_requests' then
    if tg_op = 'DELETE' then
      raise exception 'Una solicitud de aprobación no se borra.' using errcode = '42501';
    end if;
    if tg_op = 'INSERT' and new.status <> 'pending' then
      raise exception 'Una solicitud nace pendiente.' using errcode = '23514';
    end if;
    if tg_op = 'UPDATE' then
      if new.workflow_id is distinct from old.workflow_id or new.group_id is distinct from old.group_id
         or new.brand_id is distinct from old.brand_id or new.restaurant_id is distinct from old.restaurant_id
         or new.requested_by is distinct from old.requested_by or new.subject_user_id is distinct from old.subject_user_id
         or new.payload is distinct from old.payload or new.reason is distinct from old.reason
         or new.deleted_at is distinct from old.deleted_at then
        raise exception 'Lo que pide una solicitud no cambia: lo que se aprueba es exactamente lo que se aplica.'
          using errcode = '42501';
      end if;
      if old.status <> 'pending' and (new.status is distinct from old.status
           or new.resolved_at is distinct from old.resolved_at or new.resolved_by is distinct from old.resolved_by
           or new.resolution_comment is distinct from old.resolution_comment) then
        raise exception 'Una solicitud ya resuelta no cambia: ni su estado ni quién, cuándo o por qué la resolvió.' using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end
$$;
comment on function workflow.enforce_rules() is
  'Trigger: las decisiones son solo de inserción; una solicitud nace pendiente, lo que pide no cambia y una vez resuelta no vuelve atrás.';

do $$
declare
  t text;
begin
  foreach t in array array['approval_workflows', 'approval_requests', 'approval_decisions'] loop
    execute format('alter table workflow.%I enable row level security', t);
    execute format('revoke all on workflow.%I from public, anon, authenticated, service_role', t);
    execute format(
      'create trigger set_control_columns before insert or update on workflow.%I
         for each row execute function core.set_control_columns()', t);
    execute format(
      'create trigger log_change after insert or update or delete on workflow.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on workflow.%I
         for each statement execute function core.reject_truncate()', t);
  end loop;
  foreach t in array array['approval_requests', 'approval_decisions'] loop
    execute format(
      'create trigger validate_workflow before insert or update or delete on workflow.%I
         for each row execute function workflow.enforce_rules()', t);
  end loop;
end
$$;
revoke execute on function workflow.enforce_rules() from public;

-- ---------------------------------------------------------------------------
-- 3. Ayudas internas de permisos (nunca para la API)
-- ---------------------------------------------------------------------------
-- La regla de alcance, para CUALQUIER persona (sin mirar la sesión). Sirve para volver a
-- validar, al aplicar una aprobación, que quien la pidió todavía tiene permiso.
-- has_permission_for_scope (la de la sesión) pasa a usar esta: una sola lógica (ADR-0012).
create function core.user_has_permission_for_scope(
  p_user_id       uuid,
  p_permission    text,
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null
)
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
     where u.id = p_user_id
       and u.deleted_at is null and u.status = 'active'
       and (u.locked_until is null or u.locked_until <= now())
       and a.deleted_at is null
       and a.group_id = p_group_id
       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
       and (
         a.scope_type = 'group'
         or (a.scope_type = 'brand' and p_scope_type in ('brand', 'restaurant') and a.brand_id = p_brand_id)
         or (a.scope_type = 'restaurant' and p_scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id)
       )
  );
end
$$;
comment on function core.user_has_permission_for_scope(uuid, text, core.scope_type, uuid, uuid, uuid) is
  'Interna. La regla de alcance para una persona cualquiera (cuenta activa, sin bloqueo, asignación y membresía vigentes). La de la sesión (has_permission_for_scope) le suma la doble verificación.';

create or replace function core.has_permission_for_scope(
  p_permission    text,
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  return v_actor is not null
     and core.current_session_ok()
     and core.user_has_permission_for_scope(v_actor, p_permission, p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
end
$$;
comment on function core.has_permission_for_scope(text, core.scope_type, uuid, uuid, uuid) is
  'Decide si la sesión tiene un permiso que cubre un alcance (grupo, marca o restaurante): la sesión puede operar (incluida la doble verificación) y la persona tiene el permiso según core.user_has_permission_for_scope. Es la base de has_permission.';

-- ¿Una persona tiene alguno de estos roles, vigente, con un alcance que cubra éste?
create function core.user_has_role_for_scope(
  p_user_id       uuid,
  p_role_codes    text[],
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null
)
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
     where u.id = p_user_id
       and u.deleted_at is null and u.status = 'active'
       and (u.locked_until is null or u.locked_until <= now())
       and a.deleted_at is null
       and a.group_id = p_group_id
       and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
       and (
         a.scope_type = 'group'
         or (a.scope_type = 'brand' and p_scope_type in ('brand', 'restaurant') and a.brand_id = p_brand_id)
         or (a.scope_type = 'restaurant' and p_scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id)
       )
  );
end
$$;
comment on function core.user_has_role_for_scope(uuid, text[], core.scope_type, uuid, uuid, uuid) is
  'Interna. Si una persona tiene alguno de esos roles, vigente, en un alcance que cubra el pedido. Con alcance group, solo cuentan asignaciones de todo el grupo.';

create function core.has_role_for_scope(
  p_role_codes    text[],
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  return v_actor is not null and core.current_session_ok()
     and core.user_has_role_for_scope(v_actor, p_role_codes, p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
end
$$;
comment on function core.has_role_for_scope(text[], core.scope_type, uuid, uuid, uuid) is
  'Interna. Si la sesión tiene alguno de esos roles, vigente, en un alcance que cubra el pedido.';

-- Permisos de un rol que una persona NO tiene en ese alcance (vacío = el rol es un subconjunto).
create function core.user_missing_permissions_for_role(
  p_user_id       uuid,
  p_role_id       uuid,
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid,
  p_restaurant_id uuid
)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select array_agg(p.code order by p.code)
      from core.role_permissions rp
      join core.permissions p on p.id = rp.permission_id and p.deleted_at is null
     where rp.role_id = p_role_id
       and rp.deleted_at is null
       and not core.user_has_permission_for_scope(p_user_id, p.code, p_scope_type, p_group_id, p_brand_id, p_restaurant_id)
  ), '{}');
end
$$;
comment on function core.user_missing_permissions_for_role(uuid, uuid, core.scope_type, uuid, uuid, uuid) is
  'Interna. Permisos del rol que esa persona no tiene en ese alcance. Se comparan permisos, nunca niveles.';

create function core.missing_permissions_for_role(
  p_role_id       uuid,
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid,
  p_restaurant_id uuid
)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not core.current_session_ok() then
    return array['(la sesión no puede operar)'];
  end if;
  return core.user_missing_permissions_for_role(core.current_actor_id(), p_role_id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
end
$$;
comment on function core.missing_permissions_for_role(uuid, core.scope_type, uuid, uuid, uuid) is
  'Interna. Permisos del rol que la sesión no tiene en ese alcance. Se comparan permisos, nunca niveles.';

-- Permisos vigentes de un rol, ordenados (para comparar al aplicar una aprobación).
create function core.role_permission_codes(p_role_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(p.code order by p.code), '{}')
    from core.role_permissions rp
    join core.permissions p on p.id = rp.permission_id and p.deleted_at is null
   where rp.role_id = p_role_id and rp.deleted_at is null
$$;
comment on function core.role_permission_codes(uuid) is 'Interna. Permisos vigentes de un rol, ordenados.';

-- Rol sensible: lo da otra persona con aprobación (ADR-0008). Además de approvals.decide y
-- superadmin, los permisos de administrar la seguridad (roles.manage, workflows.manage).
create function core.is_sensitive_role(p_role_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from core.roles r where r.id = p_role_id and r.code = 'superadmin')
      or core.role_permission_codes(p_role_id) && array['approvals.decide', 'roles.manage', 'workflows.manage']
$$;
comment on function core.is_sensitive_role(uuid) is
  'Interna. Si dar este rol pide aprobación: es superadmin, aprueba cosas (approvals.decide) o administra la seguridad (roles.manage, workflows.manage).';

-- Serializa los cambios de roles de un grupo (evita que dos quiten al último superadmin a la vez).
create function core.lock_group_roles(p_group_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$ select pg_advisory_xact_lock(hashtext('grupo-lf:roles:' || p_group_id::text)) $$;
comment on function core.lock_group_roles(uuid) is 'Interna. Bloqueo por grupo hasta el fin de la transacción para cambios de roles y cuentas.';

-- El grupo nunca se queda sin un Superadministrador ni una Dirección General activos de grupo.
-- Devuelve el motivo si el cambio lo dejaría así (sacando esa asignación o a esa persona).
create function core.group_governance_gap(p_group_id uuid, p_without_assignment uuid, p_without_user uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_code  text;
begin
  foreach v_code in array array['superadmin', 'general_management'] loop
    if not exists (
         select 1
           from core.user_role_assignments a
           join core.roles r on r.id = a.role_id and r.code = v_code and r.deleted_at is null
           join core.user_profiles u on u.id = a.user_id and u.status = 'active' and u.deleted_at is null
           join core.user_memberships m on m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
          where a.group_id = p_group_id and a.scope_type = 'group' and a.deleted_at is null
            and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
            and a.id is distinct from p_without_assignment
            and a.user_id is distinct from p_without_user) then
      return case v_code
        when 'superadmin' then 'El grupo no se puede quedar sin un Superadministrador activo.'
        else 'El grupo no se puede quedar sin una persona de Dirección General activa: no habría quien apruebe.'
      end;
    end if;
  end loop;
  return null;
end
$$;
comment on function core.group_governance_gap(uuid, uuid, uuid) is
  'Interna. Motivo si, sin esa asignación o esa persona, el grupo quedaría sin Superadministrador o sin Dirección General activos de grupo; nulo si no.';

-- Anota el rechazo y arma la respuesta "denied" (ADR-0009).
create function core.deny(
  p_operation      text,
  p_reason         text,
  p_target_user_id uuid default null,
  p_details        jsonb default null,
  p_group_id       uuid default null,
  p_brand_id       uuid default null,
  p_restaurant_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event uuid;
begin
  v_event := audit.log_security_event('operation_denied', p_operation, p_reason, p_target_user_id, null, p_details,
                                      p_group_id, p_brand_id, p_restaurant_id);
  return jsonb_build_object('result', 'denied', 'message', p_reason, 'security_event_id', v_event);
end
$$;
comment on function core.deny(text, text, uuid, jsonb, uuid, uuid, uuid) is
  'Interna. Registra una operación rechazada por falta de permiso en audit.security_events y devuelve {"result": "denied"}.';

-- Valida que un alcance sea coherente con la estructura vigente (si no, es un error de datos).
create function core.check_scope(
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid,
  p_restaurant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_group_id is null
     or (p_scope_type = 'group' and (p_brand_id is not null or p_restaurant_id is not null))
     or (p_scope_type = 'brand' and (p_brand_id is null or p_restaurant_id is not null))
     or (p_scope_type = 'restaurant' and (p_brand_id is null or p_restaurant_id is null))
     or (p_brand_id is not null and not exists (
           select 1 from org.brands b where b.id = p_brand_id and b.group_id = p_group_id and b.deleted_at is null))
     or (p_restaurant_id is not null and not exists (
           select 1 from org.restaurants r
            where r.id = p_restaurant_id and r.brand_id = p_brand_id and r.group_id = p_group_id and r.deleted_at is null)) then
    raise exception 'El alcance no es coherente con la estructura del grupo.' using errcode = '23514';
  end if;
  -- No se dan roles en una marca o un local cerrados.
  if (p_brand_id is not null and exists (select 1 from org.brands b where b.id = p_brand_id and b.status <> 'active'))
     or (p_restaurant_id is not null and exists (select 1 from org.restaurants r where r.id = p_restaurant_id and r.status <> 'active')) then
    raise exception 'Ese lugar está cerrado: no se dan roles ahí.' using errcode = '23514';
  end if;
end
$$;
comment on function core.check_scope(core.scope_type, uuid, uuid, uuid) is 'Interna. Error 23514 si el alcance no coincide con la estructura vigente o si la marca o el local están cerrados.';

-- Separación de funciones por persona (Módulo Maestro): nadie junta en un grupo un rol que
-- aprueba cambios con uno que administra la seguridad técnica. Error si el rol nuevo lo haría.
create function core.check_person_separation(p_user_id uuid, p_role_id uuid, p_group_id uuid)
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
  if 'approvals.decide' = any (v_perms) and v_perms && array['roles.manage', 'workflows.manage'] then
    raise exception 'Una misma persona no puede aprobar cambios y administrar la seguridad técnica en el mismo grupo.'
      using errcode = '23514';
  end if;
end
$$;
comment on function core.check_person_separation(uuid, uuid, uuid) is
  'Interna. Error 23514 si, con ese rol, la persona juntaría en el grupo aprobar cambios (approvals.decide) con administrar la seguridad (roles.manage o workflows.manage).';

-- Personas que hoy tienen un rol (para excluirlas como aprobadoras de cambios sobre ese rol).
create function core.role_holders(p_role_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(distinct a.user_id), '[]'::jsonb)
    from core.user_role_assignments a
   where a.role_id = p_role_id and a.deleted_at is null
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
$$;
comment on function core.role_holders(uuid) is 'Interna. Personas con ese rol vigente, en jsonb.';

-- ---------------------------------------------------------------------------
-- 4. Crear y decidir solicitudes
-- ---------------------------------------------------------------------------
create function workflow.create_request(
  p_workflow_code   text,
  p_group_id        uuid,
  p_brand_id        uuid,
  p_restaurant_id   uuid,
  p_subject_user_id uuid,
  p_payload         jsonb,
  p_reason          text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workflow uuid;
  v_id       uuid;
begin
  select w.id into v_workflow
    from workflow.approval_workflows w
   where w.code = p_workflow_code and w.deleted_at is null and w.is_active;
  if v_workflow is null then
    raise exception 'No existe el tipo de aprobación %.', p_workflow_code using errcode = '22023';
  end if;
  -- No dos pedidos pendientes iguales.
  if exists (select 1 from workflow.approval_requests r
              where r.workflow_id = v_workflow and r.status = 'pending' and r.deleted_at is null
                and r.subject_user_id is not distinct from p_subject_user_id
                and (r.payload - 'excluded_approvers' - 'role_permissions') = (p_payload - 'excluded_approvers' - 'role_permissions')) then
    raise exception 'Ya hay una solicitud pendiente igual.' using errcode = '23505';
  end if;
  perform core.set_change_context(p_reason, 'app');
  insert into workflow.approval_requests (workflow_id, group_id, brand_id, restaurant_id, requested_by, subject_user_id, payload, reason)
  values (v_workflow, p_group_id, p_brand_id, p_restaurant_id, core.current_actor_id(), p_subject_user_id, p_payload, btrim(p_reason))
  returning id into v_id;
  return v_id;
end
$$;
comment on function workflow.create_request(text, uuid, uuid, uuid, uuid, jsonb, text) is
  'Interna. Crea una solicitud de aprobación pendiente, pedida por la persona de la sesión. No admite dos pendientes iguales.';

-- Por qué la sesión NO puede decidir esta solicitud (nulo si puede). Misma regla para
-- workflow.decide y para la bandeja de aprobaciones.
create function workflow.decision_blocker(p_request_id uuid)
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
  return null;
end
$$;
comment on function workflow.decision_blocker(uuid) is
  'Interna. Motivo por el que la sesión no puede decidir una solicitud (nulo si puede): permiso del alcance, rol exigido de todo el grupo y que no sea quien pidió, la persona afectada ni alguien excluido.';

create function workflow.decide(p_request_id uuid, p_decision text, p_comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor    uuid := core.current_actor_id();
  v_req      workflow.approval_requests;
  v_wf       workflow.approval_workflows;
  v_decision workflow.decision;
  v_block    text;
  v_count    int;
begin
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'La decisión tiene que ser approved o rejected.' using errcode = '22023';
  end if;
  v_decision := p_decision::workflow.decision;

  select * into v_req from workflow.approval_requests where id = p_request_id and deleted_at is null for update;
  v_block := workflow.decision_blocker(p_request_id);
  if v_block is not null then
    return core.deny('workflow.decide', v_block, v_req.subject_user_id,
                     jsonb_build_object('request_id', p_request_id), v_req.group_id, v_req.brand_id, v_req.restaurant_id);
  end if;
  select * into v_wf from workflow.approval_workflows where id = v_req.workflow_id;

  if v_req.status <> 'pending' then
    return jsonb_build_object('result', 'already_resolved', 'request_status', v_req.status,
                              'message', 'La solicitud ya estaba resuelta.');
  end if;

  perform core.set_change_context(coalesce(nullif(btrim(p_comment), ''), 'Decisión sobre una solicitud de aprobación'), 'app');
  insert into workflow.approval_decisions (request_id, decided_by, decision, comment)
  values (v_req.id, v_actor, v_decision, nullif(btrim(p_comment), ''));

  if v_decision = 'rejected' then
    update workflow.approval_requests
       set status = 'rejected', resolved_at = now(), resolved_by = v_actor, resolution_comment = nullif(btrim(p_comment), '')
     where id = v_req.id;
    return jsonb_build_object('result', 'rejected', 'request_status', 'rejected', 'message', 'Solicitud rechazada.');
  end if;

  select count(*) into v_count from workflow.approval_decisions where request_id = v_req.id and decision = 'approved';
  if v_count < v_wf.required_approvals then
    return jsonb_build_object('result', 'pending', 'request_status', 'pending',
                              'message', 'Aprobación registrada. Faltan más aprobaciones.');
  end if;

  update workflow.approval_requests
     set status = 'approved', resolved_at = now(), resolved_by = v_actor, resolution_comment = nullif(btrim(p_comment), '')
   where id = v_req.id;
  -- Se aplica en la misma transacción. Cada función de aplicar vuelve a validar que el cambio
  -- sigue siendo válido; si no, falla y la aprobación tampoco queda.
  execute format('select %s($1)', v_wf.apply_function::regproc) using v_req.id;
  return jsonb_build_object('result', 'approved', 'request_status', 'approved', 'message', 'Solicitud aprobada y aplicada.');
end
$$;
comment on function workflow.decide(uuid, text, text) is
  'Aprueba o rechaza una solicitud. Valida en la base el permiso, el rol exigido (de todo el grupo) y que decida otra persona; si aprueba, aplica el cambio en la misma transacción. Un intento sin permiso queda en audit.security_events.';

create function workflow.cancel_request(p_request_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests;
begin
  select * into v_req from workflow.approval_requests where id = p_request_id and deleted_at is null for update;
  if not found or v_req.requested_by is distinct from core.current_actor_id() or not core.current_session_ok() then
    return core.deny('workflow.cancel_request', 'Solo quien pidió una solicitud la puede retirar.', null,
                     jsonb_build_object('request_id', p_request_id));
  end if;
  if v_req.status <> 'pending' then
    return jsonb_build_object('result', 'already_resolved', 'request_status', v_req.status, 'message', 'La solicitud ya estaba resuelta.');
  end if;
  perform core.set_change_context(p_reason, 'app');
  update workflow.approval_requests
     set status = 'cancelled', resolved_at = now(), resolved_by = core.current_actor_id(), resolution_comment = btrim(p_reason)
   where id = p_request_id;
  return jsonb_build_object('result', 'cancelled', 'request_status', 'cancelled', 'message', 'Solicitud retirada.');
end
$$;
comment on function workflow.cancel_request(uuid, text) is 'Retira una solicitud pendiente. Solo quien la pidió.';

-- Al aplicar: la solicitud aprobada, con su tipo. Error si no está aprobada.
create function workflow.approved_request(p_request_id uuid)
returns workflow.approval_requests
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests;
begin
  select * into v_req from workflow.approval_requests where id = p_request_id and status = 'approved';
  if not found then
    raise exception 'La solicitud % no está aprobada.', p_request_id using errcode = '22023';
  end if;
  return v_req;
end
$$;
comment on function workflow.approved_request(uuid) is 'Interna. Devuelve la solicitud aprobada, o error si no lo está.';

create function workflow.cannot_apply(p_why text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'La solicitud ya no se puede aplicar: %. Hay que pedirla de nuevo.', p_why using errcode = '23514';
end
$$;
comment on function workflow.cannot_apply(text) is 'Interna. Corta la aplicación de una aprobación que dejó de ser válida.';

-- ---------------------------------------------------------------------------
-- 5. Dar y quitar roles (M6): la única vía. Reglas:
--    1) quien asigna tiene roles.assign en ese alcance; 2) el rol es un subconjunto de sus
--    permisos en ese alcance (se comparan permisos, nunca niveles), salvo el Superadministrador
--    del grupo, que puede PEDIR cualquier rol y siempre lo aprueba Dirección General;
--    3) el alcance queda dentro del suyo (lo garantiza la 1); 4) nunca a uno mismo;
--    5) si el rol es sensible (aprueba cosas, administra la seguridad o es superadmin), se crea
--    una solicitud (ADR-0008); 6) Superadministrador y Dirección General solo para todo el grupo.
-- ---------------------------------------------------------------------------
create function core.assign_role(
  p_user_id       uuid,
  p_role_code     text,
  p_scope_type    core.scope_type,
  p_group_id      uuid,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_valid_until   timestamptz default null,
  p_reason        text default null
)
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
    raise exception 'La persona no existe o tiene la cuenta bloqueada.' using errcode = '23514';
  end if;
  if not exists (select 1 from core.user_memberships m where m.user_id = p_user_id and m.group_id = p_group_id and m.deleted_at is null) then
    raise exception 'La persona no es miembro de ese grupo: primero hay que sumarla al grupo.' using errcode = '23514';
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
    v_request := workflow.create_request(v_workflow, p_group_id, p_brand_id, p_restaurant_id, p_user_id,
      jsonb_build_object('user_id', p_user_id, 'role_id', v_role.id, 'role_code', v_role.code, 'scope_type', p_scope_type,
                         'group_id', p_group_id, 'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id,
                         'valid_until', p_valid_until, 'role_permissions', to_jsonb(core.role_permission_codes(v_role.id))),
      p_reason);
    return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                              'message', 'Queda pendiente hasta que otra persona lo apruebe.');
  end if;

  perform core.set_change_context(p_reason, 'app');
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_until)
  values (p_user_id, v_role.id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id, p_valid_until)
  returning id into v_assignment;
  return jsonb_build_object('result', 'applied', 'assignment_id', v_assignment, 'message', 'Rol asignado.');
end
$$;
comment on function core.assign_role(uuid, text, core.scope_type, uuid, uuid, uuid, timestamptz, text) is
  'Da un rol a una persona en un alcance. Única vía (M6): valida roles.assign, que el rol no tenga más permisos que los propios (salvo el superadmin del grupo, que solo puede pedirlo), que no sea para uno mismo y, si el rol es sensible, crea una solicitud de aprobación. Devuelve result = applied, pending_approval o denied.';

-- Aplica una asignación aprobada (la llama workflow.decide), volviendo a validar todo.
create function core.apply_role_assignment(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req  workflow.approval_requests := workflow.approved_request(p_request_id);
  v_code text;
  v_p    jsonb := v_req.payload;
  v_role uuid := (v_req.payload ->> 'role_id')::uuid;
  v_scope core.scope_type := (v_req.payload ->> 'scope_type')::core.scope_type;
  v_brand uuid := (v_req.payload ->> 'brand_id')::uuid;
  v_rest  uuid := (v_req.payload ->> 'restaurant_id')::uuid;
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

  perform core.set_change_context('Rol aprobado (solicitud ' || p_request_id || ')', 'app');
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_until)
  values ((v_p ->> 'user_id')::uuid, v_role, v_scope, v_req.group_id, v_brand, v_rest, (v_p ->> 'valid_until')::timestamptz);
end
$$;
comment on function core.apply_role_assignment(uuid) is
  'Interna. Aplica una asignación de rol aprobada, después de volver a validar que quien la pidió puede, que el rol no cambió y que la persona sigue activa.';

create function core.revoke_role(p_assignment_id uuid, p_reason text)
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
  if cardinality(v_missing) > 0 then
    if core.has_role_for_scope(array['superadmin'], 'group', v_a.group_id) and v_a.user_id <> core.current_actor_id() then
      v_request := workflow.create_request('core.revoke_by_superadmin', v_a.group_id, null, null, v_a.user_id,
        jsonb_build_object('assignment_id', v_a.id, 'user_id', v_a.user_id, 'role_id', v_role.id, 'role_code', v_role.code),
        p_reason);
      return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                                'message', 'Quitar este rol queda pendiente hasta que lo apruebe Dirección General.');
    end if;
    return core.deny('core.revoke_role',
                     'No podés quitar un rol con permisos que vos no tenés: ' || array_to_string(v_missing, ', ') || '.',
                     v_a.user_id, v_details, v_a.group_id, v_a.brand_id, v_a.restaurant_id);
  end if;

  perform core.set_change_context(p_reason, 'app');
  update core.user_role_assignments set deleted_at = now() where id = v_a.id;
  return jsonb_build_object('result', 'applied', 'message', 'Rol quitado.');
end
$$;
comment on function core.revoke_role(uuid, text) is
  'Quita un rol. Pide roles.assign en ese alcance y que el rol no tenga más permisos que los propios; el superadmin del grupo puede pedirlo y lo aprueba Dirección General. Nunca deja al grupo sin Superadministrador ni Dirección General activos. Devuelve result = applied, pending_approval o denied.';

create function core.apply_role_revocation(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests := workflow.approved_request(p_request_id);
  v_a   core.user_role_assignments;
  v_gap text;
begin
  perform core.lock_group_roles(v_req.group_id);
  if not core.user_has_role_for_scope(v_req.requested_by, array['superadmin'], 'group', v_req.group_id) then
    perform workflow.cannot_apply('quien la pidió ya no es Superadministrador');
  end if;
  select * into v_a from core.user_role_assignments
   where id = (v_req.payload ->> 'assignment_id')::uuid and deleted_at is null for update;
  if not found then
    perform workflow.cannot_apply('esa asignación ya no está vigente');
  end if;
  if v_req.payload ->> 'role_code' in ('superadmin', 'general_management') then
    v_gap := core.group_governance_gap(v_a.group_id, v_a.id, null);
    if v_gap is not null then
      perform workflow.cannot_apply(lower(left(v_gap, 1)) || substr(rtrim(v_gap, '.'), 2));
    end if;
  end if;
  perform core.set_change_context('Rol quitado con aprobación (solicitud ' || p_request_id || ')', 'app');
  update core.user_role_assignments set deleted_at = now() where id = v_a.id;
end
$$;
comment on function core.apply_role_revocation(uuid) is 'Interna. Quita un rol cuando se aprueba la solicitud, volviendo a validar todo.';

-- ---------------------------------------------------------------------------
-- 6. Cambio de la matriz de permisos: siempre con aprobación de Dirección General (ADR-0008).
--    Separación de funciones (Módulo Maestro: Dirección General "no administra la seguridad
--    técnica"; el Superadministrador no aprueba cambios de negocio): un rol que aprueba no puede
--    administrar la seguridad, y viceversa. Quien tiene el rol que se cambia no lo aprueba.
-- ---------------------------------------------------------------------------
create function core.check_role_permission_change(p_role_id uuid, p_permission_code text, p_grant boolean)
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
  if p_grant and p_permission_code in ('roles.manage', 'workflows.manage') and 'approvals.decide' = any (v_perms) then
    raise exception 'Un rol que aprueba cambios no puede administrar la seguridad técnica.' using errcode = '23514';
  end if;
  if p_grant and p_permission_code = 'approvals.decide' and v_perms && array['roles.manage', 'workflows.manage'] then
    raise exception 'Un rol que administra la seguridad técnica no puede aprobar cambios.' using errcode = '23514';
  end if;
  if not p_grant and ((v_code = 'general_management' and p_permission_code = 'approvals.decide')
                      or (v_code = 'superadmin' and p_permission_code = 'roles.manage')) then
    raise exception 'Ese permiso no se puede quitar: el sistema se quedaría sin quien apruebe o sin quien administre los permisos.'
      using errcode = '23514';
  end if;
  if (p_permission_code = any (v_perms)) = p_grant then
    raise exception 'El rol % ya % ese permiso.', v_code, case when p_grant then 'tiene' else 'no tiene' end
      using errcode = '23505';
  end if;
end
$$;
comment on function core.check_role_permission_change(uuid, text, boolean) is
  'Interna. Reglas de un cambio de la matriz: separación entre aprobar y administrar la seguridad, permisos que no se pueden quitar y que el cambio no esté ya hecho.';

create function core.request_role_permission_change(
  p_group_id        uuid,
  p_role_code       text,
  p_permission_code text,
  p_grant           boolean,
  p_reason          text
)
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
begin
  if not core.has_permission_in_group('roles.manage', p_group_id) then
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
  v_request := workflow.create_request('core.change_role_permission', p_group_id, null, null, null,
    jsonb_build_object('role_id', v_role.id, 'role_code', v_role.code, 'permission_id', v_perm.id,
                       'permission_code', v_perm.code, 'grant', p_grant,
                       -- Quienes tienen ese rol no aprueban el cambio (se beneficiarían).
                       'excluded_approvers', core.role_holders(v_role.id)),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'El cambio de la matriz queda pendiente hasta que lo apruebe Dirección General.');
end
$$;
comment on function core.request_role_permission_change(uuid, text, text, boolean, text) is
  'Pide dar o quitar un permiso a un rol. Pide roles.manage en el grupo, no se puede sobre un rol propio, respeta la separación de funciones y siempre lo aprueba Dirección General (que no tenga ese rol).';

create function core.apply_role_permission_change(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_p     jsonb := v_req.payload;
  v_grant boolean := (v_req.payload ->> 'grant')::boolean;
begin
  if not core.user_has_permission_for_scope(v_req.requested_by, 'roles.manage', 'group', v_req.group_id) then
    perform workflow.cannot_apply('quien la pidió ya no puede cambiar la matriz');
  end if;
  -- Las mismas reglas que al pedirlo: también falla si el cambio ya no tiene sentido.
  perform core.check_role_permission_change((v_p ->> 'role_id')::uuid, v_p ->> 'permission_code', v_grant);
  perform core.set_change_context('Matriz de permisos aprobada (solicitud ' || p_request_id || ')', 'app');
  if v_grant then
    insert into core.role_permissions (role_id, permission_id)
    values ((v_p ->> 'role_id')::uuid, (v_p ->> 'permission_id')::uuid);
  else
    update core.role_permissions set deleted_at = now()
     where role_id = (v_p ->> 'role_id')::uuid and permission_id = (v_p ->> 'permission_id')::uuid and deleted_at is null;
  end if;
end
$$;
comment on function core.apply_role_permission_change(uuid) is 'Interna. Aplica un cambio aprobado de la matriz de permisos, volviendo a validar sus reglas.';

-- ---------------------------------------------------------------------------
-- 7. Traspaso de un local a otra marca (ADR-0007): se crea uno nuevo y se cierra el viejo
-- ---------------------------------------------------------------------------
create function org.request_transfer(p_restaurant_id uuid, p_target_brand_id uuid, p_new_name text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r       org.restaurants;
  v_request uuid;
  v_details jsonb := jsonb_build_object('restaurant_id', p_restaurant_id, 'target_brand_id', p_target_brand_id);
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if not found or not core.has_permission_in_group('org.transfer', v_r.group_id) then
    return core.deny('org.request_transfer', 'No podés traspasar ese local.', null, v_details,
                     v_r.group_id, v_r.brand_id, v_r.id);
  end if;
  if v_r.status <> 'active' then
    raise exception 'Solo se traspasa un local que está operando.' using errcode = '23514';
  end if;
  if not exists (select 1 from org.brands b
                  where b.id = p_target_brand_id and b.group_id = v_r.group_id and b.deleted_at is null and b.status = 'active')
     or p_target_brand_id = v_r.brand_id then
    raise exception 'La marca de destino tiene que ser otra marca vigente del mismo grupo.' using errcode = '23514';
  end if;
  if length(btrim(coalesce(nullif(btrim(p_new_name), ''), v_r.name))) > 120 then
    raise exception 'El nombre del local nuevo puede tener hasta 120 caracteres.' using errcode = '23514';
  end if;
  if exists (select 1 from org.restaurants x
              where x.brand_id = p_target_brand_id and x.deleted_at is null
                and lower(x.name) = lower(btrim(coalesce(nullif(btrim(p_new_name), ''), v_r.name)))) then
    raise exception 'Ya hay un local con ese nombre en la marca de destino.' using errcode = '23505';
  end if;
  v_request := workflow.create_request('org.transfer_restaurant', v_r.group_id, v_r.brand_id, v_r.id, null,
    jsonb_build_object('restaurant_id', v_r.id, 'target_brand_id', p_target_brand_id,
                       'new_name', coalesce(nullif(btrim(p_new_name), ''), v_r.name)),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'El traspaso queda pendiente hasta que lo apruebe Dirección General.');
end
$$;
comment on function org.request_transfer(uuid, uuid, text, text) is
  'Pide traspasar un local a otra marca del grupo. Pide org.transfer en el grupo y siempre lo aprueba Dirección General.';

create function org.apply_transfer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_p     jsonb := v_req.payload;
  v_old   org.restaurants;
  v_new   uuid;
  v_brand uuid := (v_req.payload ->> 'target_brand_id')::uuid;
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
  perform core.set_change_context('Traspaso de local aprobado (solicitud ' || p_request_id || ')', 'app');

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

  -- Los roles del local viejo pasan al nuevo (los vigentes y los que empiezan más adelante, con
  -- sus mismas fechas); los de personas bloqueadas y los ya vencidos solo se quitan.
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_from, valid_until)
  select a.user_id, a.role_id, 'restaurant', a.group_id, v_brand, v_new, greatest(a.valid_from, now()), a.valid_until
    from core.user_role_assignments a
    join core.user_profiles u on u.id = a.user_id and u.status = 'active' and u.deleted_at is null
   where a.restaurant_id = v_old.id and a.deleted_at is null
     and (a.valid_until is null or a.valid_until > now());
  update core.user_role_assignments set deleted_at = now() where restaurant_id = v_old.id and deleted_at is null;

  update org.restaurants set status = 'inactive' where id = v_old.id;
end
$$;
comment on function org.apply_transfer(uuid) is
  'Interna. Aplica un traspaso aprobado (después de volver a validar): crea el local nuevo en la marca de destino (con referencia al anterior), copia sus áreas, pasa los roles y cierra el local viejo, que conserva su historia.';

-- ---------------------------------------------------------------------------
-- 8. Catálogo inicial de aprobaciones (ADR-0008) y sus reglas
-- ---------------------------------------------------------------------------
-- Siempre otra persona aprueba, y la función que aplica es una de las funciones apply_* de
-- core u org (que reciben el id de la solicitud). Nadie puede apuntarla a otra cosa.
alter table workflow.approval_workflows
  add constraint approval_workflows_different_approver check (requires_different_approver);

create function workflow.check_apply_function()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
       select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where p.oid = new.apply_function::oid and n.nspname in ('core', 'org') and p.proname like 'apply\_%'
          and p.pronargs = 1 and p.proargtypes[0] = 'uuid'::regtype and p.prorettype = 'void'::regtype) then
    raise exception 'La función que aplica una aprobación tiene que ser una de las funciones apply_* de core u org.'
      using errcode = '42501';
  end if;
  -- Quién aprueba: un permiso y roles que existen (un error de tipeo dejaría todo sin aprobar,
  -- y vaciar los roles exigidos abriría la aprobación a cualquiera con el permiso).
  if not exists (select 1 from core.permissions p where p.code = new.approver_permission and p.deleted_at is null) then
    raise exception 'El permiso para aprobar % no existe.', new.approver_permission using errcode = '23514';
  end if;
  if exists (select 1 from unnest(coalesce(new.approver_role_codes, '{}')) c
              where not exists (select 1 from core.roles r where r.code = c and r.deleted_at is null)) then
    raise exception 'Algún rol exigido para aprobar no existe.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and cardinality(coalesce(old.approver_role_codes, '{}')) > cardinality(coalesce(new.approver_role_codes, '{}')) then
    raise exception 'Los roles exigidos para aprobar no se quitan con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function workflow.check_apply_function() is
  'Trigger: la función que aplica una aprobación solo puede ser una apply_*(uuid) de core u org; el permiso y los roles aprobadores tienen que existir, y los roles exigidos no se quitan con una edición.';
create trigger check_apply_function before insert or update of apply_function, approver_permission, approver_role_codes
  on workflow.approval_workflows
  for each row execute function workflow.check_apply_function();

do $$
begin
  perform core.set_change_context('Catálogo inicial de aprobaciones (ADR-0008)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, approver_permission, approver_role_codes, apply_function) values
    ('core.assign_sensitive_role', 'Dar un rol sensible',
     'Dar un rol que aprueba cambios o administra la seguridad. Lo aprueba otra persona con approvals.decide en ese lugar.',
     'approvals.decide', null, 'core.apply_role_assignment(uuid)'),
    ('core.assign_by_superadmin', 'Rol pedido por el Superadministrador',
     'El Superadministrador pide un rol con permisos que él no tiene. Lo aprueba Dirección General de todo el grupo.',
     'approvals.decide', array['general_management'], 'core.apply_role_assignment(uuid)'),
    ('core.assign_superadmin', 'Dar el rol de Superadministrador',
     'Dar el rol Superadministrador. Lo aprueba Dirección General de todo el grupo.',
     'approvals.decide', array['general_management'], 'core.apply_role_assignment(uuid)'),
    ('core.revoke_by_superadmin', 'Quitar un rol (pedido por el Superadministrador)',
     'El Superadministrador pide quitar un rol con permisos que él no tiene. Lo aprueba Dirección General de todo el grupo.',
     'approvals.decide', array['general_management'], 'core.apply_role_revocation(uuid)'),
    ('core.change_role_permission', 'Cambiar la matriz de permisos',
     'Dar o quitar un permiso a un rol. Lo aprueba Dirección General que no tenga ese rol.',
     'approvals.decide', array['general_management'], 'core.apply_role_permission_change(uuid)'),
    ('org.transfer_restaurant', 'Traspasar un local a otra marca',
     'Crea el local nuevo en la otra marca y cierra el viejo (ADR-0007). Lo aprueba Dirección General de todo el grupo.',
     'approvals.decide', array['general_management'], 'org.apply_transfer(uuid)');
end
$$;

-- ---------------------------------------------------------------------------
-- 9. Versiones (para recetas y fichas desde la Fase 2): lo aprobado no cambia
-- ---------------------------------------------------------------------------
create type core.version_status as enum ('draft', 'in_review', 'approved', 'published', 'archived');
comment on type core.version_status is
  'Estado de una versión: draft (borrador), in_review (en revisión), approved (aprobada), published (publicada) o archived (archivada). Desde approved el contenido no cambia: corregir es crear una versión nueva.';

-- Trigger reutilizable: en una tabla con columna status (core.version_status),
-- desde approved el contenido no cambia, nada se borra y el estado solo avanza.
-- Los argumentos del trigger son columnas que pueden cambiar junto con el estado
-- (por ejemplo, published_at).
create function core.enforce_version_rules()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_control constant text[] := array['created_at', 'created_by', 'updated_at', 'updated_by', 'deleted_at', 'deleted_by', 'status'];
  v_allowed text[] := v_control || coalesce(tg_argv, '{}'::text[]);
  v_old core.version_status;
  v_new core.version_status;
begin
  if tg_when <> 'BEFORE' or tg_level <> 'ROW' then
    raise exception 'core.enforce_version_rules() se conecta como BEFORE INSERT OR UPDATE OR DELETE ... FOR EACH ROW.';
  end if;
  if not (to_jsonb(coalesce(new, old)) ? 'status') then
    raise exception 'core.enforce_version_rules() necesita una columna status (%.%).', tg_table_schema, tg_table_name;
  end if;
  -- Una versión nace como borrador: no se crea ya aprobada ni publicada.
  if tg_op = 'INSERT' then
    if (to_jsonb(new) ->> 'status')::core.version_status is distinct from 'draft' then
      raise exception 'Una versión nueva nace como borrador.' using errcode = '42501';
    end if;
    return new;
  end if;
  v_old := (to_jsonb(old) ->> 'status')::core.version_status;

  if tg_op = 'DELETE' then
    raise exception 'Una versión no se borra.' using errcode = '42501';
  end if;
  v_new := (to_jsonb(new) ->> 'status')::core.version_status;
  -- Las columnas que acompañan al estado (argumentos del trigger) solo cambian junto con él.
  if v_new is not distinct from v_old then
    v_allowed := v_control;
  end if;

  if v_old in ('approved', 'published', 'archived') then
    if (to_jsonb(new) - v_allowed) is distinct from (to_jsonb(old) - v_allowed)
       or (new.deleted_at is distinct from old.deleted_at) then
      raise exception 'Una versión % no se modifica: para corregirla hay que crear una versión nueva.', v_old
        using errcode = '42501';
    end if;
  end if;

  if v_new is distinct from v_old and not (
       (v_old = 'draft' and v_new = 'in_review')
    or (v_old = 'in_review' and v_new in ('draft', 'approved'))
    or (v_old = 'approved' and v_new = 'published')
    or (v_old = 'published' and v_new = 'archived')) then
    raise exception 'Una versión no puede pasar de % a %.', v_old, v_new using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function core.enforce_version_rules() is
  'Trigger reutilizable de versiones (BEFORE INSERT OR UPDATE OR DELETE): una versión nace como borrador, desde approved el contenido no cambia, nada se borra y el estado solo avanza (borrador → revisión → aprobada → publicada → archivada; revisión puede volver a borrador).';

-- ---------------------------------------------------------------------------
-- 10. Permisos de ejecución y lectura (ADR-0005)
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  foreach f in array array[
    'core.has_role_for_scope(text[], core.scope_type, uuid, uuid, uuid)',
    'core.missing_permissions_for_role(uuid, core.scope_type, uuid, uuid, uuid)',
    'core.deny(text, text, uuid, jsonb, uuid, uuid, uuid)', 'core.check_scope(core.scope_type, uuid, uuid, uuid)',
    'workflow.create_request(text, uuid, uuid, uuid, uuid, jsonb, text)',
    'core.apply_role_assignment(uuid)', 'core.apply_role_permission_change(uuid)', 'org.apply_transfer(uuid)',
    'core.enforce_version_rules()',
    'core.user_has_permission_for_scope(uuid, text, core.scope_type, uuid, uuid, uuid)',
    'core.user_has_role_for_scope(uuid, text[], core.scope_type, uuid, uuid, uuid)',
    'core.user_missing_permissions_for_role(uuid, uuid, core.scope_type, uuid, uuid, uuid)',
    'core.role_permission_codes(uuid)', 'core.is_sensitive_role(uuid)', 'core.lock_group_roles(uuid)',
    'core.group_governance_gap(uuid, uuid, uuid)', 'core.role_holders(uuid)',
    'workflow.decision_blocker(uuid)', 'workflow.approved_request(uuid)', 'workflow.cannot_apply(text)',
    'core.apply_role_revocation(uuid)', 'core.check_role_permission_change(uuid, text, boolean)',
    'workflow.check_apply_function()', 'core.check_person_separation(uuid, uuid, uuid)'
  ] loop
    execute format('revoke execute on function %s from public', f);
  end loop;
  foreach f in array array[
    'workflow.decide(uuid, text, text)', 'workflow.cancel_request(uuid, text)',
    'core.assign_role(uuid, text, core.scope_type, uuid, uuid, uuid, timestamptz, text)',
    'core.revoke_role(uuid, text)', 'core.request_role_permission_change(uuid, text, text, boolean, text)',
    'org.request_transfer(uuid, uuid, text, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;

grant usage on schema workflow to authenticated;
grant select on workflow.approval_workflows, workflow.approval_requests, workflow.approval_decisions to authenticated;

create policy approval_workflows_select on workflow.approval_workflows for select to authenticated
  using ((select core.current_session_ok()));
-- Conjuntos para las políticas (ADR-0012): misma regla de alcance, calculada una vez por consulta.
-- Grupos donde la sesión tiene el permiso para TODO el grupo.
create function core.permitted_group_ids(p_permission text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select distinct g.group_id from core.actor_grants(p_permission) g where g.scope_type = 'group';
end
$$;
comment on function core.permitted_group_ids(text) is
  'Grupos en los que la sesión tiene el permiso para todo el grupo. Versión de conjunto de has_permission_in_group, para políticas.';

-- Marcas donde la sesión tiene el permiso para TODA la marca (por un rol de grupo o de esa marca).
create function core.permitted_brand_ids(p_permission text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select distinct b.id
    from core.actor_grants(p_permission) g
    join org.brands b on b.group_id = g.group_id and (g.scope_type = 'group' or (g.scope_type = 'brand' and b.id = g.brand_id));
end
$$;
comment on function core.permitted_brand_ids(text) is
  'Marcas en las que la sesión tiene el permiso para toda la marca. Versión de conjunto de has_permission_in_brand, para políticas.';

-- Una solicitud la ve quien la pidió, la persona afectada y quien tiene approvals.view en su
-- alcance: de grupo, solo con el permiso en todo el grupo; de marca, en toda la marca; de local, en ese local.
create policy approval_requests_select on workflow.approval_requests for select to authenticated
  using (
    ((requested_by = (select core.current_actor_id()) or subject_user_id = (select core.current_actor_id()))
      and (select core.current_session_ok()))
    or (brand_id is null and group_id in (select core.permitted_group_ids('approvals.view')))
    or (brand_id is not null and restaurant_id is null and brand_id in (select core.permitted_brand_ids('approvals.view')))
    or (restaurant_id in (select core.permitted_restaurant_ids('approvals.view')))
  );
-- Las decisiones se ven si se ve la solicitud (la subconsulta respeta la política de arriba).
create policy approval_decisions_select on workflow.approval_decisions for select to authenticated
  using (request_id in (select r.id from workflow.approval_requests r));

do $$
declare
  f text;
begin
  foreach f in array array['core.permitted_group_ids(text)', 'core.permitted_brand_ids(text)'] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
