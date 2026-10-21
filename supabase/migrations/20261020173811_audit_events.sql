-- Fase 1 · M2 — Historial inalterable (docs/fases/fase-1-plan.md, ADR-0006).
-- Todo lo de este archivo pertenece a audit_owner (sin login).
-- La única forma de escribir en audit.audit_events es el trigger audit.log_change().
-- Revisado por db-reviewer y security-auditor el 2026-10-20 antes del primer commit.

set role audit_owner;

-- ---------------------------------------------------------------------------
-- 1. Tipo de acción registrada.
-- ---------------------------------------------------------------------------
create type audit.action as enum ('insert', 'update', 'soft_delete', 'restore', 'delete');
comment on type audit.action is
  'Qué pasó con el registro: insert (alta), update (cambio), soft_delete (borrado lógico), restore (restauración) o delete (borrado físico, solo mantenimiento).';

-- ---------------------------------------------------------------------------
-- 2. Eventos de auditoría.
--    Tabla común por ahora; la partición mensual queda para cuando crezca (P3).
--    Los ids de alcance no tienen FK a propósito: la historia sobrevive a la estructura.
-- ---------------------------------------------------------------------------
create table audit.audit_events (
  id                   uuid primary key default gen_random_uuid(),
  sequence_number      bigint generated always as identity,
  occurred_at          timestamptz not null default now(),
  actor_id             uuid references core.actors (id) on delete restrict,
  actor_type           core.actor_type,
  actor_subject        text,
  jwt_role             text,
  db_user              text not null default session_user,
  actor_roles          jsonb,
  scope_group_id       uuid,
  scope_brand_id       uuid,
  scope_restaurant_id  uuid,
  schema_name          text not null,
  table_name           text not null,
  record_id            uuid not null,
  action               audit.action not null,
  old_values           jsonb,
  new_values           jsonb,
  changed_fields       text[],
  reason               text check (reason is null or length(reason) <= 500),
  origin               audit.change_origin,
  transaction_id       bigint not null default (pg_current_xact_id()::text::bigint),
  constraint audit_events_values_match_action check (
    (action = 'insert' and old_values is null and new_values is not null)
    or (action = 'delete' and old_values is not null and new_values is null)
    or (action in ('update', 'soft_delete', 'restore') and old_values is not null and new_values is not null)
  )
);

comment on table audit.audit_events is
  'Historia inalterable de todos los cambios: quién, cuándo, qué (antes y después) y por qué. Solo se inserta desde audit.log_change(); nadie puede modificar ni borrar, y los sellos (audit_seals) detectan cualquier alteración.';
comment on column audit.audit_events.id is 'Identificador del evento.';
comment on column audit.audit_events.sequence_number is 'Orden exacto de los eventos, incluso dentro de una misma transacción. Base de los sellos.';
comment on column audit.audit_events.occurred_at is 'Cuándo ocurrió el cambio (hora de la transacción).';
comment on column audit.audit_events.actor_id is 'Quién hizo el cambio. Nulo en migraciones, seed, clave de servidor o si el actor no estaba registrado.';
comment on column audit.audit_events.actor_type is 'Persona o cuenta técnica, en el momento del cambio.';
comment on column audit.audit_events.actor_subject is 'El sub del JWT cuando no corresponde a ningún actor registrado (para no perder el rastro).';
comment on column audit.audit_events.jwt_role is 'Rol del JWT de la sesión (authenticated, service_role...). Nulo sin JWT, por ejemplo en una conexión directa.';
comment on column audit.audit_events.db_user is 'Usuario de Postgres de la conexión (authenticator para la API, postgres para migraciones o el editor SQL).';
comment on column audit.audit_events.actor_roles is 'Roles vigentes del actor en el momento del cambio. Se completa desde que existan los roles (M4).';
comment on column audit.audit_events.scope_group_id is 'Grupo al que pertenece el registro cambiado, si tiene.';
comment on column audit.audit_events.scope_brand_id is 'Marca a la que pertenece el registro cambiado, si tiene.';
comment on column audit.audit_events.scope_restaurant_id is 'Restaurante al que pertenece el registro cambiado, si tiene.';
comment on column audit.audit_events.schema_name is 'Esquema de la tabla cambiada.';
comment on column audit.audit_events.table_name is 'Tabla cambiada.';
comment on column audit.audit_events.record_id is 'Id del registro cambiado.';
comment on column audit.audit_events.action is 'Qué pasó: alta, cambio, borrado lógico, restauración o borrado físico.';
comment on column audit.audit_events.old_values is 'Valores anteriores, sin secretos. Nulo en un alta. OJO al exponer: incluye todas las columnas (por ejemplo costos).';
comment on column audit.audit_events.new_values is 'Valores nuevos, sin secretos. Nulo en un borrado físico. OJO al exponer: incluye todas las columnas.';
comment on column audit.audit_events.changed_fields is 'Columnas que cambiaron (solo en cambios, borrados lógicos y restauraciones).';
comment on column audit.audit_events.reason is 'Motivo del cambio (hasta 500 caracteres), informado por la función que lo hizo. Informativo.';
comment on column audit.audit_events.origin is 'Desde dónde se hizo el cambio. Nulo si no se informó o si el valor no era válido. Informativo.';
comment on column audit.audit_events.transaction_id is 'Transacción de Postgres: agrupa los eventos de una misma operación.';

create unique index audit_events_sequence_idx on audit.audit_events (sequence_number);
create index audit_events_record_idx on audit.audit_events (schema_name, table_name, record_id, occurred_at desc);
create index audit_events_actor_idx on audit.audit_events (actor_id, occurred_at desc) where actor_id is not null;
create index audit_events_restaurant_idx on audit.audit_events (scope_restaurant_id, occurred_at desc) where scope_restaurant_id is not null;
create index audit_events_transaction_idx on audit.audit_events (transaction_id);
create index audit_events_occurred_at_idx on audit.audit_events (occurred_at);

-- ---------------------------------------------------------------------------
-- 3. Inalterable: ningún rol de la API la toca, y los triggers rechazan todo cambio.
-- ---------------------------------------------------------------------------
alter table audit.audit_events enable row level security;
revoke all on audit.audit_events from public, anon, authenticated, service_role;

create function audit.reject_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'La auditoría es inalterable: no se permite % sobre %.%.',
    tg_op, tg_table_schema, tg_table_name
    using errcode = '42501';
end
$$;
comment on function audit.reject_change() is 'Trigger: rechaza siempre cualquier cambio sobre la auditoría.';

create trigger audit_events_no_update_delete
  before update or delete on audit.audit_events
  for each row execute function audit.reject_change();

create trigger audit_events_no_truncate
  before truncate on audit.audit_events
  for each statement execute function audit.reject_change();

-- ---------------------------------------------------------------------------
-- 4. Ocultar secretos, en cualquier nivel del jsonb:
--    - claves con nombre sensible (contraseñas, tokens, claves, tarjetas, códigos);
--    - columnas que cada tabla excluye (argumentos del trigger, solo primer nivel);
--    - valores que parecen credenciales (JWT, claves de Supabase u otras API, llaves PEM).
--    Se reemplazan por "[oculto]": se sabe que cambió, nunca qué valor tenía.
--    Los nombres de columna van en inglés (convención), así que palabras como
--    "salt" o "hash" no se ocultan: en una cocina son datos, no secretos.
-- ---------------------------------------------------------------------------
create function audit.is_sensitive_key(p_key text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_key ~* '(password|passwd|contrasen|token|secret|api_?key|private_?key|credential|bearer|jwt|cvv|cvc|card_?number|auth_?code)'
      or p_key ~* '(^|_)(pin|otp|clave)(_|$)'
$$;
comment on function audit.is_sensitive_key(text) is 'Indica si un nombre de columna o clave jsonb guarda un secreto.';

create function audit.redact(p_value jsonb, p_excluded text[] default null)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  case jsonb_typeof(p_value)
    when 'object' then
      select coalesce(
        jsonb_object_agg(
          e.key,
          case
            when audit.is_sensitive_key(e.key) or e.key = any (coalesce(p_excluded, '{}'::text[]))
              then to_jsonb('[oculto]'::text)
            else audit.redact(e.value)
          end
        ),
        '{}'::jsonb
      )
      into v_result
      from jsonb_each(p_value) as e (key, value);
      return v_result;
    when 'array' then
      select coalesce(jsonb_agg(audit.redact(a.value) order by a.ordinality), '[]'::jsonb)
        into v_result
        from jsonb_array_elements(p_value) with ordinality as a (value, ordinality);
      return v_result;
    when 'string' then
      if (p_value #>> '{}') ~ '^(eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.|sb_secret_|sb_publishable_|sk-|sk_live_|rk_live_|-----BEGIN)' then
        return to_jsonb('[oculto]'::text);
      end if;
      return p_value;
    else
      return p_value;
  end case;
end
$$;
comment on function audit.redact(jsonb, text[]) is
  'Reemplaza por "[oculto]" los secretos de un jsonb, en cualquier nivel: claves sensibles, columnas excluidas por la tabla y valores con forma de credencial.';

-- ---------------------------------------------------------------------------
-- 5. Trigger genérico de auditoría. Se conecta a cada tabla de negocio:
--      create trigger log_change after insert or update or delete on <tabla>
--        for each row execute function audit.log_change('columna_a_ocultar', ...);
-- ---------------------------------------------------------------------------
create function audit.log_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old        jsonb;
  v_new        jsonb;
  v_row        jsonb;
  v_action     audit.action;
  v_changed    text[];
  v_subject    text := core.current_actor_subject();
  v_actor      uuid := core.current_actor_id();
  v_actor_id   uuid;
  v_actor_type core.actor_type;
  v_jwt_role   text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  v_origin_raw text := nullif(current_setting('app.origin', true), '');
  v_origin     audit.change_origin;
  v_excluded   text[] := coalesce(tg_argv, '{}'::text[]);
  v_column     text;
begin
  if tg_when <> 'AFTER' or tg_level <> 'ROW' then
    raise exception 'audit.log_change() se conecta como AFTER INSERT OR UPDATE OR DELETE ... FOR EACH ROW (%.%).',
      tg_table_schema, tg_table_name;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    v_old := to_jsonb(old);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := to_jsonb(new);
  end if;
  v_row := coalesce(v_new, v_old);

  -- Una columna a ocultar mal escrita dejaría un secreto para siempre: se rechaza.
  foreach v_column in array v_excluded loop
    if not v_row ? v_column then
      raise exception 'audit.log_change(): la columna "%" a ocultar no existe en %.%.',
        v_column, tg_table_schema, tg_table_name;
    end if;
  end loop;

  if v_origin_raw is not null
     and v_origin_raw = any (enum_range(null::audit.change_origin)::text[]) then
    v_origin := v_origin_raw::audit.change_origin;
  end if;

  -- Con la clave de servidor no hay persona en el JWT: el origen es obligatorio.
  if v_jwt_role = 'service_role' and v_origin is null then
    raise exception 'Los cambios hechos con la clave de servidor tienen que declarar motivo y origen (core.set_change_context).'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'insert';
  elsif tg_op = 'DELETE' then
    v_action := 'delete';
  else
    select array_agg(n.key order by n.key)
      into v_changed
      from jsonb_each(v_new) as n (key, value)
     where n.value is distinct from v_old -> n.key;

    -- Un cambio que solo toca las columnas de control no es un cambio real.
    if v_changed is null or v_changed <@ array['updated_at', 'updated_by'] then
      return null;
    end if;

    if v_old ->> 'deleted_at' is null and v_new ->> 'deleted_at' is not null then
      v_action := 'soft_delete';
    elsif v_old ->> 'deleted_at' is not null and v_new ->> 'deleted_at' is null then
      v_action := 'restore';
    else
      v_action := 'update';
    end if;
  end if;

  if v_actor is not null then
    select a.id, a.actor_type
      into v_actor_id, v_actor_type
      from core.actors as a
     where a.id = v_actor;
  end if;

  insert into audit.audit_events (
    actor_id, actor_type, actor_subject, jwt_role,
    scope_group_id, scope_brand_id, scope_restaurant_id,
    schema_name, table_name, record_id, action,
    old_values, new_values, changed_fields,
    reason, origin
  ) values (
    v_actor_id,
    v_actor_type,
    case when v_actor_id is null then v_subject end,
    v_jwt_role,
    (v_row ->> 'group_id')::uuid,
    (v_row ->> 'brand_id')::uuid,
    (v_row ->> 'restaurant_id')::uuid,
    tg_table_schema,
    tg_table_name,
    (v_row ->> 'id')::uuid,
    v_action,
    audit.redact(v_old, v_excluded),
    audit.redact(v_new, v_excluded),
    v_changed,
    left(nullif(current_setting('app.reason', true), ''), 500),
    v_origin
  );

  return null;
end
$$;
comment on function audit.log_change() is
  'Trigger AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW: registra el cambio en audit.audit_events, con el actor, el rol del JWT, el alcance, los valores sin secretos, el motivo y el origen. Los argumentos del trigger son columnas extra a ocultar (tienen que existir).';

-- ---------------------------------------------------------------------------
-- 6. Sellos: una cadena de huellas (sha256) sobre los eventos, en orden.
--    Cada sello encadena con el anterior. Si alguien borra, edita o inventa un evento
--    ya sellado (por ejemplo, con la contraseña de postgres), audit.verify_seals() lo detecta.
--    La última huella se guarda además FUERA de la base, con la exportación (ADR-0006).
--    Solo se sellan eventos con más de p_min_age de antigüedad, para no dejar afuera
--    transacciones que todavía no terminaron.
-- ---------------------------------------------------------------------------
create table audit.audit_seals (
  id              bigint generated always as identity primary key,
  sealed_at       timestamptz not null default now(),
  first_sequence  bigint not null,
  last_sequence   bigint not null,
  event_count     int not null check (event_count > 0),
  previous_hash   bytea not null,
  chain_hash      bytea not null,
  check (first_sequence <= last_sequence)
);
comment on table audit.audit_seals is
  'Sellos de la auditoría: cada uno cubre un tramo de eventos y encadena su huella con la del sello anterior. Permite detectar cualquier alteración de eventos ya sellados.';
comment on column audit.audit_seals.id is 'Número de sello, en orden.';
comment on column audit.audit_seals.sealed_at is 'Cuándo se selló el tramo.';
comment on column audit.audit_seals.first_sequence is 'Primer sequence_number del tramo sellado.';
comment on column audit.audit_seals.last_sequence is 'Último sequence_number del tramo sellado.';
comment on column audit.audit_seals.event_count is 'Cantidad de eventos que había en el tramo al sellarlo.';
comment on column audit.audit_seals.previous_hash is 'Huella del sello anterior (o la huella inicial, en el primero).';
comment on column audit.audit_seals.chain_hash is 'Huella acumulada hasta el último evento del tramo.';

alter table audit.audit_seals enable row level security;
revoke all on audit.audit_seals from public, anon, authenticated, service_role;

create trigger audit_seals_no_update_delete
  before update or delete on audit.audit_seals
  for each row execute function audit.reject_change();
create trigger audit_seals_no_truncate
  before truncate on audit.audit_seals
  for each statement execute function audit.reject_change();

create function audit.genesis_hash()
returns bytea
language sql
immutable
set search_path = ''
as $$ select sha256(convert_to('grupo-lf:audit:genesis', 'UTF8')) $$;
comment on function audit.genesis_hash() is 'Huella inicial de la cadena de sellos.';

create function audit.event_digest(p_event audit.audit_events)
returns bytea
language sql
immutable
set search_path = ''
as $$ select sha256(convert_to(to_jsonb(p_event)::text, 'UTF8')) $$;
comment on function audit.event_digest(audit.audit_events) is 'Huella de un evento completo.';

create function audit.seal_events(p_min_age interval default interval '10 minutes')
returns audit.audit_seals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last   audit.audit_seals;
  v_hash   bytea;
  v_prev   bytea;
  v_first  bigint;
  v_lastseq bigint;
  v_count  int := 0;
  v_event  audit.audit_events;
  v_seal   audit.audit_seals;
begin
  lock table audit.audit_seals in exclusive mode;

  select * into v_last from audit.audit_seals order by id desc limit 1;
  v_prev := coalesce(v_last.chain_hash, audit.genesis_hash());
  v_hash := v_prev;

  for v_event in
    select * from audit.audit_events
     where sequence_number > coalesce(v_last.last_sequence, 0)
       and occurred_at < now() - p_min_age
     order by sequence_number
  loop
    v_hash := sha256(v_hash || audit.event_digest(v_event));
    v_first := coalesce(v_first, v_event.sequence_number);
    v_lastseq := v_event.sequence_number;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then
    return null;
  end if;

  insert into audit.audit_seals (first_sequence, last_sequence, event_count, previous_hash, chain_hash)
  values (v_first, v_lastseq, v_count, v_prev, v_hash)
  returning * into v_seal;

  return v_seal;
end
$$;
comment on function audit.seal_events(interval) is
  'Sella los eventos todavía no sellados con más de p_min_age de antigüedad. Devuelve el sello nuevo, o nulo si no había nada para sellar.';

create function audit.verify_seals()
returns table (seal_id bigint, is_valid boolean, expected_events int, found_events int)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seal  audit.audit_seals;
  v_hash  bytea := audit.genesis_hash();
  v_count int;
  v_event audit.audit_events;
  v_prev_last bigint := 0;
begin
  for v_seal in select * from audit.audit_seals order by id loop
    v_count := 0;
    -- El sello encadena con el anterior: si no, alguien tocó los sellos.
    if v_seal.previous_hash <> v_hash then
      seal_id := v_seal.id; is_valid := false; expected_events := v_seal.event_count; found_events := null;
      return next;
      v_hash := v_seal.chain_hash;
      v_prev_last := v_seal.last_sequence;
      continue;
    end if;

    for v_event in
      select * from audit.audit_events
       where sequence_number > v_prev_last and sequence_number <= v_seal.last_sequence
       order by sequence_number
    loop
      v_hash := sha256(v_hash || audit.event_digest(v_event));
      v_count := v_count + 1;
    end loop;

    seal_id := v_seal.id;
    is_valid := (v_hash = v_seal.chain_hash and v_count = v_seal.event_count);
    expected_events := v_seal.event_count;
    found_events := v_count;
    return next;

    v_hash := v_seal.chain_hash;   -- se sigue desde la huella sellada
    v_prev_last := v_seal.last_sequence;
  end loop;
end
$$;
comment on function audit.verify_seals() is
  'Recalcula la cadena de sellos y devuelve, para cada sello, si los eventos que cubre siguen intactos.';

revoke execute on all functions in schema audit from public;

-- postgres (migraciones) necesita conectar log_change a cada tabla de negocio y poder
-- leer la auditoría para exportarla. Nada más: no puede escribir, modificar ni sellar.
-- Una función trigger no se puede llamar directamente, así que EXECUTE no le da otro poder.
grant usage on schema audit to postgres;
grant execute on function audit.log_change() to postgres;
grant select on audit.audit_events, audit.audit_seals to postgres;

reset role;
