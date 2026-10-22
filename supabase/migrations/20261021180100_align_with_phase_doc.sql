-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), parte 2: modelo.
-- Joaco decidió el 2026-10-21 que el documento manda y que se usan sus nombres.
--   - org: razón social y CUIT del grupo, código de marca.
--   - core.user_profiles: estados activo / suspendido / desactivado y los datos de la sección 4.
--   - core.user_memberships: dónde trabaja cada persona (marca o local) y desde / hasta cuándo.
--   - core.permissions: la acción, separada del módulo.
--   - audit: columnas de la sección 6 y registro de seguridad con el nombre del documento.
--   - workflow: nombres de la sección 7, el "antes y después" y request_approval / decide_approval.
--   - ai.integration_permissions: solo estructura.
-- Las funciones que usaban los nombres viejos se recrean acá con los nuevos, sin cambiar su lógica
-- salvo donde se indica.

-- ---------------------------------------------------------------------------
-- 0. Solo antes del primer sello: la huella de cada evento incluye los nombres de sus columnas
-- ---------------------------------------------------------------------------
set role audit_owner;
do $$
begin
  if exists (select 1 from audit.audit_seals) or exists (select 1 from audit.security_event_seals) then
    raise exception 'Esta migración renombra columnas de la auditoría: solo se aplica antes del primer sello (ADR-0015).';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 1. Auditoría (sección 6)
-- ---------------------------------------------------------------------------
alter table audit.audit_events rename column actor_id to actor_user_id;
alter table audit.audit_events rename column schema_name to table_schema;
alter table audit.audit_events rename column origin to source;
alter table audit.audit_events
  add column actor_service_account_id uuid references core.actors (id) on delete restrict,
  add column actor_role_code text check (actor_role_code is null or length(actor_role_code) <= 60),
  add column module text check (module is null or length(module) <= 60),
  add column operation_id uuid,
  add column status text check (status is null or length(status) <= 60),
  add constraint audit_events_one_actor check (actor_user_id is null or actor_service_account_id is null);
-- Las acciones nuevas: aprobar o rechazar es un alta (la decisión); publicar es un cambio.
alter table audit.audit_events drop constraint audit_events_values_match_action;
alter table audit.audit_events add constraint audit_events_values_match_action check (
  (action in ('insert', 'approve', 'reject') and old_values is null and new_values is not null)
  or (action = 'delete' and old_values is not null and new_values is null)
  or (action in ('update', 'soft_delete', 'restore', 'publish') and old_values is not null and new_values is not null)
);

comment on column audit.audit_events.actor_user_id is 'Persona que hizo el cambio. Nulo si lo hizo una cuenta técnica, una migración, el seed o la clave de servidor.';
comment on column audit.audit_events.actor_service_account_id is 'Cuenta técnica (agente o integración) que hizo el cambio, si fue una.';
comment on column audit.audit_events.actor_role_code is 'Rol vigente de mayor nivel de quien hizo el cambio, en ese momento. El detalle de todos sus roles está en actor_roles.';
comment on column audit.audit_events.module is 'Módulo del cambio (org, users, roles, approvals...), para filtrar el historial.';
comment on column audit.audit_events.table_schema is 'Esquema de la tabla cambiada.';
comment on column audit.audit_events.source is 'Desde dónde se hizo el cambio. Nulo si no se informó o si el valor no era válido. Informativo.';
comment on column audit.audit_events.operation_id is 'Número de operación: agrupa todos los cambios de una misma acción (una transacción).';
comment on column audit.audit_events.status is 'Estado del registro después del cambio (por ejemplo, deactivated), si la tabla tiene estado. Para filtrar.';
comment on column audit.audit_events.action is 'Qué pasó: alta, cambio, borrado lógico, restauración, borrado físico, aprobación, rechazo o publicación.';

create index audit_events_table_record_idx on audit.audit_events (table_name, record_id, occurred_at desc);
create index audit_events_service_account_idx on audit.audit_events (actor_service_account_id, occurred_at desc)
  where actor_service_account_id is not null;
create index audit_events_operation_idx on audit.audit_events (operation_id) where operation_id is not null;

-- Registro de seguridad: el nombre de la sección 4.
alter table audit.security_events rename to authentication_security_events;
alter table audit.security_event_seals rename to authentication_security_event_seals;
alter table audit.authentication_security_events rename column target_user_id to user_id;
alter table audit.authentication_security_events rename column ip to ip_address;
alter table audit.authentication_security_events rename column details to detail;
alter index audit.security_events_sequence_idx rename to authentication_security_events_sequence_idx;
alter index audit.security_events_target_idx rename to authentication_security_events_user_idx;
alter index audit.security_events_actor_idx rename to authentication_security_events_actor_idx;
alter index audit.security_events_email_idx rename to authentication_security_events_email_idx;
alter index audit.security_events_type_idx rename to authentication_security_events_type_idx;
alter index audit.security_events_occurred_at_idx rename to authentication_security_events_occurred_at_idx;
alter trigger security_events_no_update_delete on audit.authentication_security_events
  rename to authentication_security_events_no_update_delete;
alter trigger security_events_no_truncate on audit.authentication_security_events
  rename to authentication_security_events_no_truncate;
alter trigger security_event_seals_no_update_delete on audit.authentication_security_event_seals
  rename to authentication_security_event_seals_no_update_delete;
alter trigger security_event_seals_no_truncate on audit.authentication_security_event_seals
  rename to authentication_security_event_seals_no_truncate;

comment on table audit.authentication_security_events is
  'Registro de seguridad inalterable: ingresos, intentos fallidos, bloqueos, suspensiones, cambios de contraseña y operaciones rechazadas por falta de permiso (ADR-0009, ADR-0010, ADR-0015). Solo se inserta desde audit.log_security_event(); los sellos detectan alteraciones.';
comment on table audit.authentication_security_event_seals is
  'Sellos del registro de seguridad: cada uno cubre un tramo de eventos y encadena su huella con el anterior.';
comment on column audit.authentication_security_events.user_id is 'Persona afectada (por ejemplo, la cuenta que se intentó usar o a quien se le quiso dar un rol).';
comment on column audit.authentication_security_events.ip_address is 'Dirección IP informada por el servidor que atendió el pedido. Informativa: se puede falsear.';
comment on column audit.authentication_security_events.detail is 'Datos de contexto, sin secretos.';

-- La huella ignora las COLUMNAS vacías (solo el primer nivel): así, sumar una columna nueva que nace
-- vacía no invalida los sellos que ya existan. Los nulos de adentro (por ejemplo en old_values) sí
-- cuentan, para que nadie pueda agregarlos o quitarlos sin que se note (revisión de seguridad, m2).
-- (Renombrar una columna sí invalida los sellos: por eso el chequeo del punto 0.)
create function audit.row_digest(p_row jsonb)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select sha256(convert_to(coalesce((select jsonb_object_agg(e.key, e.value) from jsonb_each(p_row) as e
                                      where e.value <> 'null'::jsonb), '{}'::jsonb)::text, 'UTF8'))
$$;
comment on function audit.row_digest(jsonb) is 'Huella de una fila para los sellos, sin las columnas vacías (solo del primer nivel).';
revoke execute on function audit.row_digest(jsonb) from public;

create or replace function audit.event_digest(p_event audit.audit_events)
returns bytea
language sql
immutable
set search_path = ''
as $$ select audit.row_digest(to_jsonb(p_event)) $$;

create or replace function audit.security_event_digest(p_event audit.authentication_security_events)
returns bytea
language sql
immutable
set search_path = ''
as $$ select audit.row_digest(to_jsonb(p_event)) $$;

create function audit.module_for(p_schema text, p_table text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_schema = 'org' then 'org'
    when p_schema = 'workflow' then 'approvals'
    when p_schema = 'ai' then 'ai'
    when p_schema = 'core' and p_table in ('user_profiles', 'user_memberships', 'service_accounts') then 'users'
    when p_schema = 'core' and p_table in ('roles', 'permissions', 'role_permissions', 'user_role_assignments') then 'roles'
    when p_schema = 'core' and p_table = 'notifications' then 'notifications'
    when p_schema = 'core' and p_table = 'test_documents' then 'test_documents'
    else p_schema
  end
$$;
comment on function audit.module_for(text, text) is
  'Módulo al que pertenece una tabla, para la columna module de la auditoría y los filtros del historial.';
revoke execute on function audit.module_for(text, text) from public;
grant execute on function audit.module_for(text, text) to postgres;

create function audit.untracked_columns(p_schema text, p_table text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case
    when p_schema = 'core' and p_table = 'user_profiles' then array['last_seen_at', 'last_restaurant_id']
    else '{}'::text[]
  end
$$;
comment on function audit.untracked_columns(text, text) is
  'Columnas que cambian todo el tiempo y no son historia (el último acceso, el local elegido). Si un cambio solo toca estas columnas, no se audita ni marca la fila como editada. Lista explícita, probada en pgTAP.';
revoke execute on function audit.untracked_columns(text, text) from public;
grant execute on function audit.untracked_columns(text, text) to postgres;

create or replace function audit.log_change()
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
  v_roles      jsonb;
  v_jwt_role   text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  v_source_raw text := nullif(current_setting('app.change_source', true), '');
  v_source     audit.change_origin;
  v_operation  uuid := audit.try_uuid(nullif(current_setting('app.operation_id', true), ''));
  v_excluded   text[] := coalesce(tg_argv, '{}'::text[]);
  v_column     text;
  v_is_org     boolean := tg_table_schema = 'org';
  v_group      uuid;
  v_brand      uuid;
  v_restaurant uuid;
  v_found_group uuid;
  v_found_brand uuid;
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

  foreach v_column in array v_excluded loop
    if not v_row ? v_column then
      raise exception 'audit.log_change(): la columna "%" a ocultar no existe en %.%.',
        v_column, tg_table_schema, tg_table_name;
    end if;
  end loop;

  if v_source_raw is not null
     and v_source_raw = any (enum_range(null::audit.change_origin)::text[]) then
    v_source := v_source_raw::audit.change_origin;
  end if;

  if v_jwt_role = 'service_role' and v_source is null then
    raise exception 'Los cambios hechos con la clave de servidor tienen que declarar motivo y origen (core.set_change_context).'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    v_action := 'insert';
    -- Una decisión de aprobación se registra como lo que es: aprobar o rechazar.
    if tg_table_schema = 'workflow' and tg_table_name = 'approval_decisions' then
      v_action := case v_new ->> 'decision' when 'approved' then 'approve' when 'rejected' then 'reject' else 'insert' end;
    end if;
  elsif tg_op = 'DELETE' then
    v_action := 'delete';
  else
    select array_agg(n.key order by n.key)
      into v_changed
      from jsonb_each(v_new) as n (key, value)
     where n.value is distinct from v_old -> n.key;

    -- Nada que contar: solo cambiaron columnas de control o columnas sin historia.
    if v_changed is null
       or v_changed <@ (array['updated_at', 'updated_by'] || audit.untracked_columns(tg_table_schema, tg_table_name)) then
      return null;
    end if;

    if v_old ->> 'deleted_at' is null and v_new ->> 'deleted_at' is not null then
      v_action := 'soft_delete';
    elsif v_old ->> 'deleted_at' is not null and v_new ->> 'deleted_at' is null then
      v_action := 'restore';
    elsif 'status' = any (v_changed) and v_new ->> 'status' = 'published' then
      v_action := 'publish';
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
  if v_actor_id is not null and v_actor_type = 'user' then
    v_roles := core.actor_roles_snapshot(v_actor_id);
  end if;

  -- Un número de operación por transacción: todos los cambios de una misma acción lo comparten.
  if v_operation is null then
    v_operation := gen_random_uuid();
    perform set_config('app.operation_id', v_operation::text, true);
  end if;

  -- Alcance: primero lo que dice la fila (o su propio id en org)...
  v_group := case when v_is_org and tg_table_name = 'groups' then audit.try_uuid(v_row ->> 'id')
                  else audit.try_uuid(v_row ->> 'group_id') end;
  v_brand := case when v_is_org and tg_table_name = 'brands' then audit.try_uuid(v_row ->> 'id')
                  else audit.try_uuid(v_row ->> 'brand_id') end;
  v_restaurant := case when v_is_org and tg_table_name = 'restaurants' then audit.try_uuid(v_row ->> 'id')
                       else audit.try_uuid(v_row ->> 'restaurant_id') end;

  -- ...y después lo que dice la estructura, que manda.
  if v_restaurant is not null then
    select r.brand_id, r.group_id into v_found_brand, v_found_group
      from org.restaurants as r where r.id = v_restaurant;
    if found then
      v_brand := v_found_brand;
      v_group := v_found_group;
    end if;
  elsif v_brand is not null then
    select b.group_id into v_found_group from org.brands as b where b.id = v_brand;
    if found then
      v_group := v_found_group;
    end if;
  end if;

  insert into audit.audit_events (
    actor_user_id, actor_service_account_id, actor_type, actor_subject, jwt_role, actor_roles, actor_role_code,
    scope_group_id, scope_brand_id, scope_restaurant_id,
    module, table_schema, table_name, record_id, action,
    old_values, new_values, changed_fields,
    reason, source, operation_id, status
  ) values (
    case when v_actor_type = 'user' then v_actor_id end,
    case when v_actor_type = 'service_account' then v_actor_id end,
    v_actor_type,
    case when v_actor_id is null then v_subject end,
    v_jwt_role,
    v_roles,
    v_roles -> 0 ->> 'role',
    v_group,
    v_brand,
    v_restaurant,
    audit.module_for(tg_table_schema, tg_table_name),
    tg_table_schema,
    tg_table_name,
    (v_row ->> 'id')::uuid,
    v_action,
    audit.redact(v_old, v_excluded),
    audit.redact(v_new, v_excluded),
    v_changed,
    left(nullif(current_setting('app.change_reason', true), ''), 500),
    v_source,
    v_operation,
    left(v_row ->> 'status', 60)
  );

  return null;
end
$$;

create or replace function audit.log_security_event(
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

  insert into audit.authentication_security_events (
    event_type, actor_id, actor_subject, jwt_role, user_id, email, operation, reason, detail,
    scope_group_id, scope_brand_id, scope_restaurant_id, ip_address, user_agent
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

create or replace function audit.seal_all()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_audit    audit.audit_seals;
  v_security audit.authentication_security_event_seals;
begin
  v_audit := audit.seal_events();
  v_security := audit.seal_security_events();
  return jsonb_build_object('audit_events', coalesce(v_audit.event_count, 0),
                            'authentication_security_events', coalesce(v_security.event_count, 0));
end
$$;

-- Devuelve otro tipo de fila (la tabla cambió de nombre): se recrea con sus mismos permisos.
drop function audit.seal_security_events(interval);
create function audit.seal_security_events(p_min_age interval default '00:10:00'::interval)
returns audit.authentication_security_event_seals
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_last    audit.authentication_security_event_seals;
  v_hash    bytea;
  v_prev    bytea;
  v_first   bigint;
  v_lastseq bigint;
  v_count   int := 0;
  v_event   audit.authentication_security_events;
  v_seal    audit.authentication_security_event_seals;
begin
  lock table audit.authentication_security_event_seals in exclusive mode;

  select * into v_last from audit.authentication_security_event_seals order by id desc limit 1;
  v_prev := coalesce(v_last.chain_hash, audit.security_genesis_hash());
  v_hash := v_prev;

  for v_event in
    select * from audit.authentication_security_events
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

  insert into audit.authentication_security_event_seals (first_sequence, last_sequence, event_count, previous_hash, chain_hash)
  values (v_first, v_lastseq, v_count, v_prev, v_hash)
  returning * into v_seal;
  return v_seal;
end
$$;
comment on function audit.seal_security_events(interval) is
  'Sella los eventos de seguridad que todavía no tienen sello y tienen al menos p_min_age de antigüedad.';
revoke execute on function audit.seal_security_events(interval) from public;

create or replace function audit.verify_security_seals()
returns table (seal_id bigint, is_valid boolean, expected_events integer, found_events integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seal      audit.authentication_security_event_seals;
  v_hash      bytea := audit.security_genesis_hash();
  v_count     int;
  v_event     audit.authentication_security_events;
  v_prev_last bigint := 0;
begin
  for v_seal in select * from audit.authentication_security_event_seals order by id loop
    v_count := 0;
    if v_seal.previous_hash <> v_hash then
      seal_id := v_seal.id; is_valid := false; expected_events := v_seal.event_count; found_events := null;
      return next;
      v_hash := v_seal.chain_hash;
      v_prev_last := v_seal.last_sequence;
      continue;
    end if;

    for v_event in
      select * from audit.authentication_security_events
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

reset role;

-- ---------------------------------------------------------------------------
-- 2. Contexto del cambio (sección 6): motivo, origen y número de operación
-- ---------------------------------------------------------------------------
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
  if p_origin is null or p_origin not in ('manual', 'edge_function', 'agent', 'import', 'integration', 'seed', 'maintenance', 'auth') then
    raise exception 'Origen del cambio inválido. Valores posibles: manual, edge_function, agent, import, integration, seed, maintenance, auth.'
      using errcode = '22023';
  end if;

  perform set_config('app.change_reason', p_reason, true);
  perform set_config('app.change_source', p_origin, true);
  -- Toda la transacción es una misma operación: el número se fija la primera vez.
  if nullif(current_setting('app.operation_id', true), '') is null then
    perform set_config('app.operation_id', gen_random_uuid()::text, true);
  end if;
end
$$;
comment on function core.set_change_context(text, text) is
  'Fija el motivo (app.change_reason), el origen (app.change_source) y el número de operación (app.operation_id) del cambio, para la auditoría. Solo dura la transacción. Informativo: nunca decide permisos.';

-- Las columnas sin historia (audit.untracked_columns) se guardan sin marcar la fila como editada.
create or replace function core.set_control_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_control constant text[] := array['created_at', 'created_by', 'updated_at', 'updated_by', 'deleted_at', 'deleted_by'];
  v_untracked text[] := audit.untracked_columns(tg_table_schema, tg_table_name);
  v_same_data boolean;
begin
  if tg_when <> 'BEFORE' or tg_level <> 'ROW' or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'core.set_control_columns() se conecta como BEFORE INSERT OR UPDATE ... FOR EACH ROW (%.%).',
      tg_table_schema, tg_table_name;
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := v_actor;
    new.updated_at := now();
    new.updated_by := v_actor;
    new.deleted_at := null;
    new.deleted_by := null;
    return new;
  end if;

  if new.id is distinct from old.id
     or new.created_at is distinct from old.created_at
     or new.created_by is distinct from old.created_by then
    raise exception 'No se puede cambiar el id ni los datos de creación de un registro (%.%).',
      tg_table_schema, tg_table_name
      using errcode = '42501';
  end if;

  v_same_data := (to_jsonb(new) - v_control - v_untracked) = (to_jsonb(old) - v_control - v_untracked);

  -- Un cambio que no cambia nada (fuera de las columnas de control) no toca la fila:
  -- así la fila nunca dice que alguien la cambió sin un evento en la auditoría.
  if v_same_data and (new.deleted_at is null) = (old.deleted_at is null) then
    if (to_jsonb(new) - v_control) is distinct from (to_jsonb(old) - v_control) then
      -- Solo cambiaron columnas sin historia: se guardan, pero la fila no figura como editada.
      new.updated_at := old.updated_at;
      new.updated_by := old.updated_by;
      new.deleted_at := old.deleted_at;
      new.deleted_by := old.deleted_by;
      return new;
    end if;
    return old;
  end if;

  -- P13: sobre un registro borrado solo se acepta restaurarlo, sin cambiar nada más.
  if old.deleted_at is not null and not v_same_data then
    raise exception 'Un registro borrado no se edita: primero hay que restaurarlo (%.%).',
      tg_table_schema, tg_table_name
      using errcode = '42501';
  end if;
  -- Y al revés: borrar es un paso propio, sin cambiar nada más a la vez.
  if old.deleted_at is null and new.deleted_at is not null and not v_same_data then
    raise exception 'Borrar un registro es un paso aparte: no se puede editar y borrar a la vez (%.%).',
      tg_table_schema, tg_table_name
      using errcode = '42501';
  end if;

  new.updated_at := now();
  new.updated_by := v_actor;

  if old.deleted_at is null and new.deleted_at is not null then
    new.deleted_at := now();
    new.deleted_by := v_actor;          -- borrado lógico
  elsif new.deleted_at is null then
    new.deleted_by := null;             -- vigente o restaurado
  end if;

  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. org (sección 4): razón social y CUIT del grupo; código de marca
-- ---------------------------------------------------------------------------
alter table org.groups
  add column legal_name text check (legal_name is null or length(btrim(legal_name)) between 1 and 200),
  add column tax_id     text check (tax_id is null or tax_id ~ '^[0-9]{11}$');
comment on column org.groups.legal_name is 'Razón social del grupo. Opcional.';
comment on column org.groups.tax_id is 'CUIT del grupo: 11 dígitos, sin guiones. Opcional.';

alter table org.brands add column code text;
-- Las marcas que ya existan reciben un código a partir del nombre (en una base nueva no hay ninguna).
do $$
begin
  if exists (select 1 from org.brands) then
    perform core.set_change_context('Código de marca inicial (ADR-0015)', 'maintenance');
    update org.brands set code = left('M' || upper(regexp_replace(name, '[^A-Za-z0-9]', '', 'g')), 12) || '-' || upper(left(id::text, 4));
  end if;
end
$$;
alter table org.brands
  alter column code set not null,
  add constraint brands_code_check check (code ~ '^[A-Z0-9][A-Z0-9-]{1,19}$');
create unique index brands_code_key on org.brands (group_id, code) where deleted_at is null;
comment on column org.brands.code is 'Código corto de la marca (por ejemplo, RAGU), en mayúsculas. Único dentro del grupo entre las vigentes.';

drop function org.create_brand(uuid, text, text);
create function org.create_brand(p_group_id uuid, p_name text, p_code text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('org.manage', p_group_id), 'crear marcas en este grupo');
  perform core.set_change_context(p_reason, 'manual');
  insert into org.brands (group_id, name, code) values (p_group_id, btrim(p_name), upper(btrim(p_code))) returning id into v_id;
  return v_id;
end
$$;
comment on function org.create_brand(uuid, text, text, text) is
  'Crea una marca con su código. Pide org.manage en el grupo y un motivo.';
revoke execute on function org.create_brand(uuid, text, text, text) from public;
grant execute on function org.create_brand(uuid, text, text, text) to authenticated;

create or replace function org.update_brand(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from org.brands where id = p_id;
  perform org.require(core.has_permission_in_brand('org.manage', p_id), 'editar esta marca');
  perform org.check_keys(p_changes, array['name', 'code', 'status']);
  if p_changes ? 'status' or p_changes ? 'code' then
    perform org.require(core.has_permission_in_group('org.manage', v_group), 'cambiar el código o abrir o cerrar esta marca');
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.brands
     set name   = coalesce(btrim(p_changes ->> 'name'), name),
         code   = coalesce(upper(btrim(p_changes ->> 'code')), code),
         status = coalesce((p_changes ->> 'status')::org.unit_status, status)
   where id = p_id;
end
$$;

create or replace function org.update_group(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission_in_group('org.manage', p_id), 'editar el grupo');
  perform org.check_keys(p_changes, array['name', 'legal_name', 'tax_id']);
  perform core.set_change_context(p_reason, 'manual');
  -- Para los datos opcionales, una clave presente con texto vacío o null los borra.
  update org.groups
     set name       = coalesce(btrim(p_changes ->> 'name'), name),
         legal_name = case when p_changes ? 'legal_name' then nullif(btrim(p_changes ->> 'legal_name'), '') else legal_name end,
         tax_id     = case when p_changes ? 'tax_id' then nullif(btrim(p_changes ->> 'tax_id'), '') else tax_id end
   where id = p_id;
end
$$;

create or replace function org.create_area(p_restaurant_id uuid, p_name text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
  v_id    uuid;
begin
  perform org.require(core.has_permission('org.manage', p_restaurant_id), 'crear áreas en este local');
  select group_id into v_group from org.restaurants where id = p_restaurant_id;
  perform core.set_change_context(p_reason, 'manual');
  insert into org.areas (group_id, restaurant_id, name) values (v_group, p_restaurant_id, btrim(p_name))
  returning id into v_id;
  return v_id;
end
$$;

create or replace function org.create_restaurant(p_brand_id uuid, p_name text, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
  v_id    uuid;
  v_d     jsonb := coalesce(p_details, '{}'::jsonb);
begin
  perform org.require(core.has_permission_in_brand('org.manage', p_brand_id), 'crear locales en esta marca');
  perform org.check_keys(v_d, array['code', 'address', 'locality', 'legal_name', 'tax_id', 'phone', 'opened_on', 'time_zone']);
  select group_id into v_group from org.brands where id = p_brand_id;
  perform core.set_change_context(p_reason, 'manual');
  insert into org.restaurants (group_id, brand_id, name, code, address, locality, legal_name, tax_id, phone, opened_on, time_zone)
  values (v_group, p_brand_id, btrim(p_name),
          upper(nullif(btrim(v_d ->> 'code'), '')), nullif(btrim(v_d ->> 'address'), ''),
          nullif(btrim(v_d ->> 'locality'), ''), nullif(btrim(v_d ->> 'legal_name'), ''),
          nullif(btrim(v_d ->> 'tax_id'), ''), nullif(btrim(v_d ->> 'phone'), ''),
          (v_d ->> 'opened_on')::date,
          coalesce(nullif(btrim(v_d ->> 'time_zone'), ''), 'America/Argentina/Buenos_Aires'))
  returning id into v_id;
  return v_id;
end
$$;

create or replace function org.update_area(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_restaurant uuid;
begin
  select restaurant_id into v_restaurant from org.areas where id = p_id;
  perform org.require(core.has_permission('org.manage', v_restaurant), 'editar esta área');
  perform org.check_keys(p_changes, array['name']);
  perform core.set_change_context(p_reason, 'manual');
  update org.areas set name = coalesce(btrim(p_changes ->> 'name'), name) where id = p_id;
end
$$;

create or replace function org.update_restaurant(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_brand uuid;
begin
  select brand_id into v_brand from org.restaurants where id = p_id;
  perform org.require(core.has_permission('org.manage', p_id), 'editar este local');
  perform org.check_keys(p_changes, array['name', 'status', 'code', 'address', 'locality', 'legal_name', 'tax_id', 'phone', 'opened_on', 'time_zone']);
  if p_changes ? 'status' then
    perform org.require(core.has_permission_in_brand('org.manage', v_brand), 'abrir o cerrar este local');
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Para los datos opcionales, una clave presente con texto vacío o null los borra.
  update org.restaurants
     set name       = coalesce(btrim(p_changes ->> 'name'), name),
         status     = coalesce((p_changes ->> 'status')::org.unit_status, status),
         code       = case when p_changes ? 'code' then upper(nullif(btrim(p_changes ->> 'code'), '')) else code end,
         address    = case when p_changes ? 'address' then nullif(btrim(p_changes ->> 'address'), '') else address end,
         locality   = case when p_changes ? 'locality' then nullif(btrim(p_changes ->> 'locality'), '') else locality end,
         legal_name = case when p_changes ? 'legal_name' then nullif(btrim(p_changes ->> 'legal_name'), '') else legal_name end,
         tax_id     = case when p_changes ? 'tax_id' then nullif(btrim(p_changes ->> 'tax_id'), '') else tax_id end,
         phone      = case when p_changes ? 'phone' then nullif(btrim(p_changes ->> 'phone'), '') else phone end,
         opened_on  = case when p_changes ? 'opened_on' then (nullif(p_changes ->> 'opened_on', ''))::date else opened_on end,
         time_zone  = case when p_changes ? 'time_zone'
                           then coalesce(nullif(btrim(p_changes ->> 'time_zone'), ''), 'America/Argentina/Buenos_Aires')
                           else time_zone end
   where id = p_id;
end
$$;

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
    select true, core.has_permission_in_group('org.manage', b.group_id) into v_found, v_allowed
      from org.brands b where b.id = p_id;
  elsif p_table = 'restaurants' then
    select true, core.has_permission_in_brand('org.manage', r.brand_id) into v_found, v_allowed
      from org.restaurants r where r.id = p_id;
  elsif p_table = 'areas' then
    select true, core.has_permission('org.manage', a.restaurant_id) into v_found, v_allowed
      from org.areas a where a.id = p_id;
  else
    raise exception 'Solo se pueden borrar o restaurar marcas, locales y áreas.' using errcode = '22023';
  end if;

  perform org.require(v_found and v_allowed, case when p_deleted then 'borrar esto' else 'restaurar esto' end);
  perform core.set_change_context(p_reason, 'manual');
  execute format('update org.%I set deleted_at = case when $1 then now() end where id = $2', p_table)
    using p_deleted, p_id;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Perfiles (sección 4): tres estados y los datos de cada persona
-- ---------------------------------------------------------------------------
alter table core.user_profiles rename column disabled_at to deactivated_at;
alter table core.user_profiles rename column disabled_reason to deactivation_reason;
alter table core.user_profiles rename column disabled_by to deactivated_by;
alter table core.user_profiles rename constraint user_profiles_disabled_reason_check to user_profiles_deactivation_reason_check;
alter table core.user_profiles rename constraint user_profiles_disabled_consistent to user_profiles_deactivated_consistent;
alter table core.user_profiles rename constraint user_profiles_disabled_by_consistent to user_profiles_deactivated_by_consistent;
alter table core.user_profiles rename constraint user_profiles_disabled_by_fkey to user_profiles_deactivated_by_fkey;
alter index core.user_profiles_disabled_by_idx rename to user_profiles_deactivated_by_idx;

alter table core.user_profiles
  add column suspended_at       timestamptz,
  add column suspended_by       uuid references core.actors (id) on delete restrict,
  add column suspension_reason  text check (suspension_reason is null or length(suspension_reason) <= 500),
  add column username           text check (username is null or username ~ '^[a-z0-9][a-z0-9._-]{2,39}$'),
  add column job_title          text check (job_title is null or length(btrim(job_title)) between 1 and 80),
  add column area_id            uuid references org.areas (id) on delete restrict,
  add column activated_at       timestamptz,
  add column last_seen_at       timestamptz,
  add column invited_by         uuid references core.actors (id) on delete restrict,
  add column last_restaurant_id uuid references org.restaurants (id) on delete restrict,
  add constraint user_profiles_suspended_consistent check ((status = 'suspended') = (suspended_at is not null)),
  add constraint user_profiles_suspended_by_consistent check (status = 'suspended' or suspended_by is null);

create unique index user_profiles_username_key on core.user_profiles (username) where deleted_at is null and username is not null;
create index user_profiles_suspended_by_idx on core.user_profiles (suspended_by) where suspended_by is not null;
create index user_profiles_area_idx on core.user_profiles (area_id) where area_id is not null;
create index user_profiles_invited_by_idx on core.user_profiles (invited_by) where invited_by is not null;
create index user_profiles_last_restaurant_idx on core.user_profiles (last_restaurant_id) where last_restaurant_id is not null;

comment on table core.user_profiles is 'Persona que usa el sistema. Una por cada usuario persona de Supabase Auth. Nunca se borra: se suspende o se desactiva.';
comment on column core.user_profiles.status is 'Estado de la cuenta: activa, suspendida (pausa) o desactivada (se fue).';
comment on column core.user_profiles.deactivated_at is 'Cuándo se desactivó la cuenta. Vacío si no está desactivada.';
comment on column core.user_profiles.deactivation_reason is 'Por qué se desactivó la cuenta.';
comment on column core.user_profiles.deactivated_by is 'Quién desactivó la cuenta. No puede ser quien apruebe la reactivación (ADR-0008).';
comment on column core.user_profiles.suspended_at is 'Cuándo se suspendió la cuenta. Vacío si no está suspendida.';
comment on column core.user_profiles.suspended_by is 'Quién suspendió la cuenta.';
comment on column core.user_profiles.suspension_reason is 'Por qué se suspendió la cuenta.';
comment on column core.user_profiles.username is 'Nombre de usuario opcional, en minúsculas. Único entre los perfiles vigentes. No se usa para ingresar (se ingresa con el correo).';
comment on column core.user_profiles.job_title is 'Puesto de trabajo (por ejemplo, Jefa de cocina). Descriptivo: no da permisos.';
comment on column core.user_profiles.area_id is 'Área donde trabaja, de un local de su grupo. Descriptivo: no da permisos.';
comment on column core.user_profiles.activated_at is 'Cuándo entró por primera vez (lo pone el ingreso).';
comment on column core.user_profiles.last_seen_at is 'Último acceso: el último ingreso o renovación de la sesión (lo pone el ingreso). No se audita.';
comment on column core.user_profiles.invited_by is 'Quién la invitó (lo pone la invitación).';
comment on column core.user_profiles.last_restaurant_id is 'Último local que eligió en el selector de local. No se audita.';

-- ---------------------------------------------------------------------------
-- 5. Membresías (sección 4): dónde trabaja cada persona y desde / hasta cuándo
-- ---------------------------------------------------------------------------
alter table core.user_memberships
  add column brand_id      uuid,
  add column restaurant_id uuid,
  add column starts_at     timestamptz not null default now(),
  add column ends_at       timestamptz,
  add constraint user_memberships_scope_consistent check (restaurant_id is null or brand_id is not null),
  add constraint user_memberships_validity check (ends_at is null or ends_at > starts_at),
  add constraint user_memberships_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  add constraint user_memberships_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  add constraint user_memberships_restaurant_brand_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict;

drop index core.user_memberships_key;
-- Única entre las abiertas (sin fecha de fin): quien vuelve a trabajar en un lugar recibe otra membresía.
create unique index user_memberships_key on core.user_memberships (user_id, group_id, brand_id, restaurant_id)
  nulls not distinct where deleted_at is null and ends_at is null;
create index user_memberships_user_idx on core.user_memberships (user_id, group_id) where deleted_at is null;
create index user_memberships_brand_idx on core.user_memberships (brand_id) where brand_id is not null;
create index user_memberships_restaurant_idx on core.user_memberships (restaurant_id) where restaurant_id is not null;

do $$
begin
  if exists (select 1 from core.user_memberships) then
    perform core.set_change_context('Fecha de inicio de las membresías existentes (ADR-0015)', 'maintenance');
    update core.user_memberships set starts_at = created_at where starts_at <> created_at;
  end if;
end
$$;
comment on table core.user_memberships is 'Dónde trabaja cada persona: en el grupo, en una marca o en un local, desde y hasta cuándo. Hace falta una membresía vigente en el grupo para que sus roles valgan.';
comment on column core.user_memberships.group_id is 'Grupo al que pertenece.';
comment on column core.user_memberships.brand_id is 'Marca donde trabaja, si es de una marca o de un local. Vacío si trabaja para todo el grupo.';
comment on column core.user_memberships.restaurant_id is 'Local donde trabaja, si es de un local.';
comment on column core.user_memberships.starts_at is 'Desde cuándo trabaja ahí.';
comment on column core.user_memberships.ends_at is 'Hasta cuándo trabaja ahí. Vacío si sigue. Terminada la última membresía del grupo, sus roles dejan de valer.';

-- ---------------------------------------------------------------------------
-- 6. Permisos (sección 4): la acción, separada del módulo
-- ---------------------------------------------------------------------------
-- Columna común (no calculada): las calculadas se llenan después de los triggers BEFORE, y el
-- control de cambios las vería vacías. El check garantiza que siempre coincida con el código.
alter table core.permissions add column action text;
do $$
begin
  perform core.set_change_context('Acción de cada permiso (ADR-0015)', 'maintenance');
  update core.permissions set action = split_part(code, '.', 2);
end
$$;
alter table core.permissions
  alter column action set not null,
  add constraint permissions_action_matches_code check (code = module || '.' || action);
comment on column core.permissions.action is 'Acción del permiso (la parte después del punto). Tiene que coincidir con el código.';

-- ---------------------------------------------------------------------------
-- 7. Aprobaciones (sección 7): nombres del documento y el "antes y después"
-- ---------------------------------------------------------------------------
alter table workflow.approval_workflows rename column approver_permission to required_permission;
alter table workflow.approval_workflows rename column required_approvals to min_approvers;
alter table workflow.approval_workflows rename constraint approval_workflows_required_approvals_check to approval_workflows_min_approvers_check;
-- Hasta hoy nadie se podía aprobar lo propio (era un check fijo): allow_self_approval nace en falso.
alter table workflow.approval_workflows drop column requires_different_approver;
alter table workflow.approval_workflows
  add column allow_self_approval boolean not null default false,
  add column entity_table text check (entity_table is null or entity_table ~ '^[a-z_]+\.[a-z_]+$');
comment on column workflow.approval_workflows.required_permission is 'Permiso que tiene que tener quien aprueba, en el alcance de la solicitud.';
comment on column workflow.approval_workflows.min_approvers is 'Cuántas aprobaciones hacen falta (hoy, una).';
comment on column workflow.approval_workflows.allow_self_approval is 'Si quien pidió puede aprobar lo suyo. Falso en todos: activarlo pide una migración documentada. La persona afectada nunca aprueba.';
comment on column workflow.approval_workflows.entity_table is 'Tabla que cambia cuando se aprueba (por ejemplo, core.user_role_assignments).';

do $$
begin
  perform core.set_change_context('Tabla afectada de cada tipo de aprobación (ADR-0015)', 'maintenance');
  update workflow.approval_workflows set entity_table = case code
      when 'core.assign_sensitive_role' then 'core.user_role_assignments'
      when 'core.assign_superadmin' then 'core.user_role_assignments'
      when 'core.assign_by_superadmin' then 'core.user_role_assignments'
      when 'core.revoke_by_superadmin' then 'core.user_role_assignments'
      when 'core.change_role_permission' then 'core.role_permissions'
      when 'org.transfer_restaurant' then 'org.restaurants'
      when 'core.reactivate_user' then 'core.user_profiles'
    end;
end
$$;

alter table workflow.approval_requests rename column payload to proposed_changes;
alter table workflow.approval_requests rename constraint approval_requests_payload_check to approval_requests_proposed_changes_check;
alter table workflow.approval_requests
  add column entity_table    text check (entity_table is null or entity_table ~ '^[a-z_]+\.[a-z_]+$'),
  add column entity_id       uuid,
  add column previous_values jsonb check (previous_values is null or jsonb_typeof(previous_values) = 'object'),
  add column requested_at    timestamptz not null default now();
do $$
begin
  if exists (select 1 from workflow.approval_requests) then
    perform core.set_change_context('Fecha de pedido de las solicitudes existentes (ADR-0015)', 'maintenance');
    update workflow.approval_requests set requested_at = created_at where requested_at <> created_at;
  end if;
end
$$;
create index approval_requests_entity_idx on workflow.approval_requests (entity_table, entity_id) where entity_id is not null;
comment on column workflow.approval_requests.proposed_changes is 'Qué se va a aplicar si se aprueba. No cambia nunca.';
comment on column workflow.approval_requests.previous_values is 'Cómo estaba lo que se quiere cambiar al momento de pedirlo, para mostrar el antes y el después. No cambia nunca.';
comment on column workflow.approval_requests.entity_table is 'Tabla del registro que cambia.';
comment on column workflow.approval_requests.entity_id is 'Registro que cambia. Vacío si el cambio crea uno nuevo.';
comment on column workflow.approval_requests.requested_at is 'Cuándo se pidió.';

create or replace function workflow.enforce_rules()
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
         or new.proposed_changes is distinct from old.proposed_changes or new.reason is distinct from old.reason
         or new.previous_values is distinct from old.previous_values or new.entity_table is distinct from old.entity_table
         or new.entity_id is distinct from old.entity_id or new.requested_at is distinct from old.requested_at
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

create or replace function workflow.check_apply_function()
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
  if not exists (select 1 from core.permissions p where p.code = new.required_permission and p.deleted_at is null) then
    raise exception 'El permiso para aprobar % no existe.', new.required_permission using errcode = '23514';
  end if;
  if exists (select 1 from unnest(coalesce(new.approver_role_codes, '{}')) c
              where not exists (select 1 from core.roles r where r.code = c and r.deleted_at is null)) then
    raise exception 'Algún rol exigido para aprobar no existe.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and cardinality(coalesce(old.approver_role_codes, '{}')) > cardinality(coalesce(new.approver_role_codes, '{}')) then
    raise exception 'Los roles exigidos para aprobar no se quitan con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  -- Dejar que alguien se apruebe lo propio, o pedir menos aprobaciones, tampoco se hace con una edición.
  -- Un tipo nuevo nace sin autoaprobación (revisión de seguridad, m1): habilitarla pide cambiar esta regla.
  if tg_op = 'INSERT' and new.allow_self_approval then
    raise exception 'Un tipo de aprobación nuevo no permite aprobarse lo propio: hace falta una migración documentada que cambie esta regla.'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and ((new.allow_self_approval and not old.allow_self_approval) or new.min_approvers < old.min_approvers) then
    raise exception 'Permitir la autoaprobación o pedir menos aprobaciones no se hace con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  return new;
end
$$;

-- El control también mira la autoaprobación y la cantidad de aprobaciones.
drop trigger check_apply_function on workflow.approval_workflows;
create trigger check_apply_function
  before insert or update of apply_function, required_permission, approver_role_codes, allow_self_approval, min_approvers
  on workflow.approval_workflows
  for each row execute function workflow.check_apply_function();

drop function workflow.create_request(text, uuid, uuid, uuid, uuid, jsonb, text);
create function workflow.request_approval(
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
  v_wf workflow.approval_workflows;
  v_id uuid;
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
  values (v_wf.id, p_group_id, p_brand_id, p_restaurant_id, core.current_actor_id(), p_subject_user_id,
          v_wf.entity_table, p_entity_id, p_proposed_changes, p_previous_values, btrim(p_reason))
  returning id into v_id;
  return v_id;
end
$$;
comment on function workflow.request_approval(text, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, text) is
  'Crea una solicitud de aprobación con motivo obligatorio, lo que se propone y cómo estaba antes. La usan las funciones de cada módulo, nunca la app directamente.';
revoke execute on function workflow.request_approval(text, uuid, uuid, uuid, uuid, uuid, jsonb, jsonb, text) from public;

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
     -- El rol exigido (por ejemplo, Dirección General) tiene que ser de TODO el grupo.
     or (cardinality(coalesce(v_wf.approver_role_codes, '{}')) > 0
         and not core.has_role_for_scope(v_wf.approver_role_codes, 'group', v_req.group_id)) then
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
  return null;
end
$$;

alter function workflow.decide(uuid, text, text) rename to decide_approval;
create or replace function workflow.decide_approval(p_request_id uuid, p_decision text, p_comment text default null)
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
    return core.deny('workflow.decide_approval', v_block, v_req.subject_user_id,
                     jsonb_build_object('request_id', p_request_id), v_req.group_id, v_req.brand_id, v_req.restaurant_id);
  end if;
  select * into v_wf from workflow.approval_workflows where id = v_req.workflow_id;

  if v_req.status <> 'pending' then
    return jsonb_build_object('result', 'already_resolved', 'request_status', v_req.status,
                              'message', 'La solicitud ya estaba resuelta.');
  end if;

  perform core.set_change_context(coalesce(nullif(btrim(p_comment), ''), 'Decisión sobre una solicitud de aprobación'), 'manual');
  insert into workflow.approval_decisions (request_id, decided_by, decision, comment)
  values (v_req.id, v_actor, v_decision, nullif(btrim(p_comment), ''));

  if v_decision = 'rejected' then
    update workflow.approval_requests
       set status = 'rejected', resolved_at = now(), resolved_by = v_actor, resolution_comment = nullif(btrim(p_comment), '')
     where id = v_req.id;
    return jsonb_build_object('result', 'rejected', 'request_status', 'rejected', 'message', 'Solicitud rechazada.');
  end if;

  select count(*) into v_count from workflow.approval_decisions where request_id = v_req.id and decision = 'approved';
  if v_count < v_wf.min_approvers then
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
comment on function workflow.decide_approval(uuid, text, text) is
  'Aprueba o rechaza una solicitud. Valida permiso, alcance y que no decida quien la pidió ni la persona afectada; si se aprueba, aplica el cambio en la misma transacción. Un intento sin permiso devuelve denied y queda en el registro de seguridad.';

create or replace function workflow.cancel_request(p_request_id uuid, p_reason text)
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
  perform core.set_change_context(p_reason, 'manual');
  update workflow.approval_requests
     set status = 'cancelled', resolved_at = now(), resolved_by = core.current_actor_id(), resolution_comment = btrim(p_reason)
   where id = p_request_id;
  return jsonb_build_object('result', 'cancelled', 'request_status', 'cancelled', 'message', 'Solicitud retirada.');
end
$$;

create or replace function workflow.inbox(p_pending boolean default true, p_limit integer default 50,
                                          p_before_created_at timestamptz default null, p_before_id uuid default null)
returns table (id uuid, workflow_code text, workflow_name text, status workflow.request_status, requested_at timestamptz,
               requested_by_name text, summary text, reason text, place_name text, can_decide boolean,
               resolved_at timestamptz, resolved_by_name text, resolution_comment text)
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
         r.resolved_at, core.display_name(r.resolved_by), r.resolution_comment
    from page r
    join workflow.approval_workflows w on w.id = r.workflow_id
   order by r.created_at desc, r.id desc;
end
$$;

-- ---------------------------------------------------------------------------
-- 8. Reglas de identidad: membresías con lugar y fechas, área del perfil
-- ---------------------------------------------------------------------------
create or replace function core.enforce_identity_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_becomes_active  boolean;
  v_becomes_deleted boolean;
begin
  if tg_when <> 'BEFORE' or tg_level <> 'ROW' or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'core.enforce_identity_rules() se conecta como BEFORE INSERT OR UPDATE ... FOR EACH ROW.';
  end if;

  v_becomes_active := new.deleted_at is null and (tg_op = 'INSERT' or old.deleted_at is not null);
  v_becomes_deleted := tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null;

  if tg_table_name = 'user_role_assignments' then
    -- La persona, la asignación y su alcance no cambian: para otro rol o lugar se crea otra asignación.
    if tg_op = 'UPDATE' and (
         new.user_id is distinct from old.user_id or new.role_id is distinct from old.role_id
         or new.scope_type is distinct from old.scope_type or new.group_id is distinct from old.group_id
         or new.brand_id is distinct from old.brand_id or new.restaurant_id is distinct from old.restaurant_id) then
      raise exception 'Una asignación no cambia de persona, rol ni alcance: hay que quitarla y crear otra.'
        using errcode = '42501';
    end if;
    -- La vigencia no se extiende ni se retrotrae: solo se puede acortar el final.
    if tg_op = 'UPDATE' and (
         new.valid_from is distinct from old.valid_from
         or (new.valid_until is distinct from old.valid_until
             and (new.valid_until is null or (old.valid_until is not null and new.valid_until > old.valid_until)))) then
      raise exception 'La vigencia de una asignación solo se puede acortar: para extenderla hay que crear otra.'
        using errcode = '42501';
    end if;
    if v_becomes_active then
      -- "for share" bloquea la membresía, el rol y el perfil hasta el commit: así no se cruzan con
      -- otra transacción que los esté borrando o bloqueando al mismo tiempo.
      -- Una membresía vigente y sin fecha de fin: si no, el rol podría dejar de valer al vencer la
      -- membresía y "revivir" cuando se sume otra (revisión de seguridad, M1).
      perform 1 from core.user_memberships m
       where m.user_id = new.user_id and m.group_id = new.group_id and m.deleted_at is null
         and m.starts_at <= now() and m.ends_at is null
       for share;
      if not found then
        raise exception 'La persona no es miembro de ese grupo: primero hay que sumarla al grupo.'
          using errcode = '23514';
      end if;
      perform 1 from core.roles r where r.id = new.role_id and r.deleted_at is null for share;
      if not found then
        raise exception 'No se puede asignar un rol borrado.' using errcode = '23514';
      end if;
      perform 1 from core.user_profiles u
       where u.id = new.user_id and u.status = 'active' and u.deleted_at is null
       for share;
      if not found then
        raise exception 'No se puede asignar un rol a una cuenta que no está activa.' using errcode = '23514';
      end if;
    end if;

  elsif tg_table_name = 'user_memberships' then
    if tg_op = 'UPDATE' and (new.user_id is distinct from old.user_id or new.group_id is distinct from old.group_id
                             or new.brand_id is distinct from old.brand_id or new.restaurant_id is distinct from old.restaurant_id
                             or new.starts_at is distinct from old.starts_at) then
      raise exception 'Una membresía no cambia de persona, de lugar ni de fecha de inicio: hay que terminarla y crear otra.'
        using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and new.ends_at is distinct from old.ends_at and new.ends_at is not null and new.ends_at < now() then
      raise exception 'Una membresía no termina en el pasado.' using errcode = '23514';
    end if;
    -- Terminar la última membresía del grupo con roles vigentes los dejaría sin efecto en silencio.
    if (v_becomes_deleted or (tg_op = 'UPDATE' and new.ends_at is distinct from old.ends_at and new.ends_at is not null))
       and not exists (
         select 1 from core.user_memberships o
          where o.user_id = new.user_id and o.group_id = new.group_id and o.id <> new.id and o.deleted_at is null
            and o.starts_at <= now() and o.ends_at is null)
       and exists (
         select 1 from core.user_role_assignments a
          where a.user_id = new.user_id and a.group_id = new.group_id and a.deleted_at is null
            and (a.valid_until is null or a.valid_until > now())) then
      raise exception 'No se puede sacar a una persona del grupo mientras tenga roles vigentes en él.'
        using errcode = '23514';
    end if;

  elsif tg_table_name = 'role_permissions' then
    if tg_op = 'UPDATE' and (new.role_id is distinct from old.role_id or new.permission_id is distinct from old.permission_id) then
      raise exception 'Una relación rol-permiso no cambia: hay que quitarla y crear otra.' using errcode = '42501';
    end if;
    if v_becomes_active then
      perform 1 from core.roles r where r.id = new.role_id and r.deleted_at is null for share;
      if not found then
        raise exception 'No se puede dar un permiso a un rol borrado.' using errcode = '23514';
      end if;
      perform 1 from core.permissions p where p.id = new.permission_id and p.deleted_at is null for share;
      if not found then
        raise exception 'No se puede dar un permiso borrado.' using errcode = '23514';
      end if;
    end if;

  elsif tg_table_name = 'roles' then
    -- Renombrar un código cambiaría en silencio lo que reciben todos los que tienen ese rol.
    if tg_op = 'UPDATE' and new.code is distinct from old.code then
      raise exception 'El código de un rol no cambia: hay que crear otro rol.' using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and old.is_system and old.requires_mfa and not new.requires_mfa then
      raise exception 'A un rol del catálogo inicial no se le puede sacar la doble verificación (MFA).'
        using errcode = '42501';
    end if;
    if tg_op = 'UPDATE' and old.is_system and not new.is_system then
      raise exception 'Un rol del catálogo inicial no deja de serlo.' using errcode = '42501';
    end if;
    if v_becomes_deleted and exists (
         select 1 from core.user_role_assignments a where a.role_id = new.id and a.deleted_at is null) then
      raise exception 'No se puede borrar un rol mientras haya personas con ese rol.' using errcode = '23514';
    end if;

  elsif tg_table_name = 'permissions' then
    -- La acción sale del código (el check permissions_action_matches_code la controla igual).
    if new.action is null then
      new.action := split_part(new.code, '.', 2);
    end if;
    -- Renombrar org.view a roles.manage le daría roles.manage a todos los roles: el código no cambia.
    if tg_op = 'UPDATE' and (new.code is distinct from old.code or new.module is distinct from old.module) then
      raise exception 'El código de un permiso no cambia: hay que crear otro permiso.' using errcode = '42501';
    end if;
    if v_becomes_deleted and exists (
         select 1 from core.role_permissions rp where rp.permission_id = new.id and rp.deleted_at is null) then
      raise exception 'No se puede borrar un permiso mientras algún rol lo tenga: primero hay que quitarlo de los roles.'
        using errcode = '23514';
    end if;

  elsif tg_table_name = 'service_accounts' then
    if not exists (select 1 from core.actors a where a.id = new.id and a.actor_type = 'service_account') then
      raise exception 'Una cuenta técnica tiene que ser un usuario de Auth de tipo cuenta técnica.'
        using errcode = '23514';
    end if;
    if new.deleted_at is null and (tg_op = 'INSERT' or new.owner_user_id is distinct from old.owner_user_id
                                   or old.deleted_at is not null) then
      perform 1 from core.user_profiles u
       where u.id = new.owner_user_id and u.status = 'active' and u.deleted_at is null
       for share;
      if not found then
        raise exception 'La persona responsable de una cuenta técnica tiene que tener la cuenta activa.'
          using errcode = '23514';
      end if;
    end if;

  elsif tg_table_name = 'integration_permissions' then
    if tg_op = 'UPDATE' and (
         new.service_account_id is distinct from old.service_account_id or new.permission_id is distinct from old.permission_id
         or new.scope_type is distinct from old.scope_type or new.group_id is distinct from old.group_id
         or new.brand_id is distinct from old.brand_id or new.restaurant_id is distinct from old.restaurant_id
         or new.valid_from is distinct from old.valid_from) then
      raise exception 'Un permiso de integración no cambia de cuenta, permiso ni alcance: hay que quitarlo y crear otro.'
        using errcode = '42501';
    end if;
    -- Como las asignaciones: la vigencia solo se acorta.
    if tg_op = 'UPDATE' and new.valid_until is distinct from old.valid_until
       and (new.valid_until is null or (old.valid_until is not null and new.valid_until > old.valid_until)) then
      raise exception 'La vigencia de un permiso de integración solo se puede acortar: para extenderla hay que crear otro.'
        using errcode = '42501';
    end if;
    if v_becomes_active then
      perform 1 from core.permissions p where p.id = new.permission_id and p.deleted_at is null for share;
      if not found then
        raise exception 'No se puede dar un permiso borrado.' using errcode = '23514';
      end if;
      perform 1 from core.service_accounts s where s.id = new.service_account_id and s.deleted_at is null for share;
      if not found then
        raise exception 'No se le da un permiso a una cuenta técnica borrada.' using errcode = '23514';
      end if;
    end if;

  elsif tg_table_name = 'user_profiles' then
    if tg_op = 'UPDATE' and new.email is distinct from old.email then
      raise exception 'El correo del perfil no se edita a mano (la sincronización con Auth llega en M8).'
        using errcode = '42501';
    end if;
    if v_becomes_deleted then
      raise exception 'Un perfil no se borra: se suspende o se desactiva, para conservar su historia.' using errcode = '42501';
    end if;
    -- El área tiene que ser de un local de un grupo donde la persona trabaja.
    if new.area_id is not null and (tg_op = 'INSERT' or new.area_id is distinct from old.area_id) then
      perform 1 from org.areas ar
        join core.user_memberships m on m.group_id = ar.group_id and m.user_id = new.id and m.deleted_at is null
                                    and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
       where ar.id = new.area_id and ar.deleted_at is null;
      if not found then
        raise exception 'El área tiene que ser de un local del grupo de la persona.' using errcode = '23514';
      end if;
    end if;
  end if;

  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 9. Las funciones de permisos cuentan solo las membresías vigentes (con fechas)
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
       and (
         a.scope_type = 'group'
         or (a.scope_type = 'brand' and p_scope_type in ('brand', 'restaurant') and a.brand_id = p_brand_id)
         or (a.scope_type = 'restaurant' and p_scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id)
       )
  );
end
$$;

create or replace function core.group_governance_gap(p_group_id uuid, p_without_assignment uuid, p_without_user uuid)
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
                                       and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
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

create or replace function core.visible_user_ids()
returns setof uuid
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
  select v_actor
  union
  select a.user_id
    from core.actor_grants('users.view') g
    join core.user_role_assignments a
      on a.group_id = g.group_id
     and a.deleted_at is null
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
     and (g.scope_type = 'group'
          or (g.scope_type = 'brand' and a.scope_type in ('brand', 'restaurant') and a.brand_id = g.brand_id)
          or (g.scope_type = 'restaurant' and a.scope_type = 'restaurant' and a.restaurant_id = g.restaurant_id))
  union
  -- Quien ve el grupo entero ve también a quienes trabajan en él sin roles (incluidas las que ya terminaron).
  select m.user_id
    from core.actor_grants('users.view') g
    join core.user_memberships m on m.group_id = g.group_id and m.deleted_at is null
   where g.scope_type = 'group';
end
$$;

create or replace function core.cannot_act_on_user(p_user_id uuid, p_permission text)
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
          and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
          and core.has_permission_in_group(p_permission, m.group_id)) then
    return 'La persona no tiene roles en tu alcance.';
  end if;
  return null;
end
$$;

-- Ahora una persona puede tener varias membresías: se toma la vigente más antigua.
create or replace function core.user_group(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.group_id from core.user_memberships m
   where m.user_id = p_user_id and m.deleted_at is null
   -- Primero las vigentes (revisión de seguridad, m4); si no hay, la más reciente (para la historia).
   order by (m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())) desc, m.starts_at, m.created_at limit 1
$$;

-- Sumar a una persona al grupo, opcionalmente a una marca o un local (dónde trabaja).
drop function core.add_member(uuid, uuid, text);
create function core.add_member(p_user_id uuid, p_group_id uuid, p_reason text,
                                p_brand_id uuid default null, p_restaurant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_scope core.scope_type := case when p_restaurant_id is not null then 'restaurant'
                                  when p_brand_id is not null then 'brand' else 'group' end::core.scope_type;
  v_where uuid := coalesce(p_restaurant_id, p_brand_id);
  v_why   text;
  v_first boolean;
begin
  -- Hay que poder invitar en ese lugar: sin lugar, en todo el grupo (revisión de seguridad, M1).
  if not core.has_permission_for_scope('users.invite', v_scope, p_group_id, p_brand_id, p_restaurant_id) then
    return core.deny('core.add_member', 'No tenés permiso para sumar personas a este lugar.', p_user_id, null,
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;
  -- A quien ya tiene roles solo lo suma quien puede actuar sobre todos ellos.
  if exists (select 1 from core.user_role_assignments a where a.user_id = p_user_id and a.deleted_at is null) then
    v_why := core.cannot_act_on_user(p_user_id, 'users.invite');
    if v_why is not null then
      return core.deny('core.add_member', v_why, p_user_id, null, p_group_id, p_brand_id, p_restaurant_id);
    end if;
  end if;
  v_first := not exists (select 1 from core.user_memberships m where m.user_id = p_user_id);
  if v_where is not null then
    perform core.check_scope(v_scope, p_group_id, p_brand_id, p_restaurant_id);
  end if;
  if not exists (select 1 from core.user_profiles u where u.id = p_user_id and u.status = 'active' and u.deleted_at is null) then
    raise exception 'La persona no existe o su cuenta no está activa.' using errcode = '23514';
  end if;
  if exists (select 1 from core.user_memberships
              where user_id = p_user_id and group_id = p_group_id and deleted_at is null
                and brand_id is not distinct from p_brand_id and restaurant_id is not distinct from p_restaurant_id
                and ends_at is null) then
    return jsonb_build_object('result', 'already_member', 'message', 'La persona ya trabaja en ese lugar.');
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
  values (p_user_id, p_group_id, p_brand_id, p_restaurant_id);
  -- Quién la invitó: solo en el alta (su primera membresía), no en las que se suman después.
  if v_first then
    update core.user_profiles set invited_by = core.current_actor_id()
     where id = p_user_id and invited_by is null and core.current_actor_id() is not null;
  end if;
  return jsonb_build_object('result', 'applied', 'message', 'Persona sumada.');
end
$$;
comment on function core.add_member(uuid, uuid, text, uuid, uuid) is
  'Suma a una persona a un grupo y, si se indica, a una marca o un local donde trabaja. Pide users.invite en ese lugar y un motivo. La primera vez anota quién la invitó.';
revoke execute on function core.add_member(uuid, uuid, text, uuid, uuid) from public;
grant execute on function core.add_member(uuid, uuid, text, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Roles y aprobaciones con los nombres nuevos
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
  if cardinality(v_missing) > 0 then
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

create or replace function org.request_transfer(p_restaurant_id uuid, p_target_brand_id uuid, p_new_name text, p_reason text)
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
  v_request := workflow.request_approval('org.transfer_restaurant', v_r.group_id, v_r.brand_id, v_r.id, null, v_r.id,
    jsonb_build_object('restaurant_id', v_r.id, 'target_brand_id', p_target_brand_id,
                       'new_name', coalesce(nullif(btrim(p_new_name), ''), v_r.name)),
    jsonb_build_object('brand_id', v_r.brand_id, 'name', v_r.name),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'El traspaso queda pendiente hasta que lo apruebe Dirección General.');
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

  perform core.set_change_context('Rol aprobado (solicitud ' || p_request_id || ')', 'manual');
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_until)
  values ((v_p ->> 'user_id')::uuid, v_role, v_scope, v_req.group_id, v_brand, v_rest, (v_p ->> 'valid_until')::timestamptz);
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
  if not core.user_has_permission_for_scope(v_req.requested_by, 'roles.manage', 'group', v_req.group_id) then
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

create or replace function core.apply_role_revocation(p_request_id uuid)
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
   where id = (v_req.proposed_changes ->> 'assignment_id')::uuid and deleted_at is null for update;
  if not found then
    perform workflow.cannot_apply('esa asignación ya no está vigente');
  end if;
  if v_req.proposed_changes ->> 'role_code' in ('superadmin', 'general_management') then
    v_gap := core.group_governance_gap(v_a.group_id, v_a.id, null);
    if v_gap is not null then
      perform workflow.cannot_apply(lower(left(v_gap, 1)) || substr(rtrim(v_gap, '.'), 2));
    end if;
  end if;
  perform core.set_change_context('Rol quitado con aprobación (solicitud ' || p_request_id || ')', 'manual');
  update core.user_role_assignments set deleted_at = now() where id = v_a.id;
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

-- ---------------------------------------------------------------------------
-- 11. Cuentas: desactivar, reactivar, desbloquear y el ingreso, con los estados nuevos
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

create or replace function core.apply_reactivation(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_user  uuid := (v_req.proposed_changes ->> 'user_id')::uuid;
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
  if v_p.status <> 'deactivated' or v_p.deleted_at is not null then
    perform workflow.cannot_apply('la cuenta ya no está desactivada');
  end if;
  -- Quien aprueba (la sesión) tiene que poder actuar sobre la persona: no puede tener menos permisos que ella.
  v_why := core.cannot_act_on_user(v_user, 'users.deactivate');
  if v_why is not null then
    perform workflow.cannot_apply(lower(left(v_why, 1)) || substr(rtrim(v_why, '.'), 2));
  end if;

  perform core.set_change_context('Cuenta reactivada (solicitud ' || p_request_id || ')', 'manual');
  update core.user_profiles
     set status = 'active', deactivated_at = null, deactivation_reason = null, deactivated_by = null, locked_until = null
   where id = v_user;
  delete from core.login_throttles where email = lower(v_p.email);
  perform audit.log_security_event('account_reactivated', 'core.apply_reactivation', 'Reactivación aprobada', v_user,
                                   null, jsonb_build_object('request_id', p_request_id), core.user_group(v_user));
end
$$;

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
  perform core.set_change_context(p_reason, 'manual');
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

-- El ingreso anota el primer acceso y el último (este sin auditoría: es una columna sin historia).
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
             when v_p.status = 'suspended' then 'Cuenta suspendida.'
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

  -- Solo escribe si es el primer ingreso o pasaron unos minutos: así una renovación de sesión no
  -- espera por una fila que otra transacción tenga tomada.
  if v_p.activated_at is null or v_p.last_seen_at is null or v_p.last_seen_at < now() - interval '5 minutes' then
    perform core.set_change_context(case when v_p.activated_at is null then 'Primer ingreso' else 'Ingreso' end, 'auth');
    update core.user_profiles
       set last_seen_at = now(), activated_at = coalesce(activated_at, now())
     where id = v_p.id;
  end if;

  return jsonb_build_object('claims', event -> 'claims');
end
$$;

-- ---------------------------------------------------------------------------
-- 12. Tablero e historial con los nombres nuevos (las pantallas nuevas llegan en otra migración)
-- ---------------------------------------------------------------------------
create or replace function core.users_dashboard(p_search text default null, p_brand_id uuid default null,
                                                p_restaurant_id uuid default null, p_status text default null,
                                                p_after_key text default null, p_after_id uuid default null,
                                                p_limit integer default 25, p_user_id uuid default null)
returns table (id uuid, first_name text, last_name text, email text, status core.account_status, locked boolean,
               roles jsonb, sort_key text)
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
         lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email) as sort_key
    from core.user_profiles p
    join visible vis on vis.user_id = p.id
   where p.deleted_at is null
     and (p_user_id is null or p.id = p_user_id)
     and (v_search is null
          or position(v_search in lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.email)) > 0)
     and (p_status is null
          or (p_status = 'active' and p.status = 'active' and (p.locked_until is null or p.locked_until <= now()))
          or (p_status = 'suspended' and p.status = 'suspended')
          or (p_status = 'deactivated' and p.status = 'deactivated')
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

create or replace function core.users_overview(p_brand_id uuid default null, p_restaurant_id uuid default null)
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
      'suspended', (select count(*) from visible where status = 'suspended'),
      'deactivated', (select count(*) from visible where status = 'deactivated'),
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

create or replace function core.audit_history(p_limit integer default 50, p_before bigint default null, p_record_id uuid default null)
returns table (sequence_number bigint, occurred_at timestamptz, actor_name text, action text, schema_name text, table_name text,
               record_id uuid, changed_fields text[], old_values jsonb, new_values jsonb, reason text, origin text, place_name text)
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
         coalesce(core.display_name(coalesce(e.actor_user_id, e.actor_service_account_id)),
                  case when e.source is not null then 'Sistema (' || e.source::text || ')' else 'Sistema' end),
         e.action::text, e.table_schema, e.table_name, e.record_id, e.changed_fields,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.old_values else core.hide_costs(e.old_values) end,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.new_values else core.hide_costs(e.new_values) end,
         e.reason, e.source::text,
         coalesce((select r.name from org.restaurants r where r.id = e.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = e.scope_brand_id),
                  (select g.name from org.groups g where g.id = e.scope_group_id))
    from page e
   order by e.sequence_number desc;
end
$$;

-- ---------------------------------------------------------------------------
-- 13. ai.integration_permissions (sección 3, migración 10): solo estructura
-- ---------------------------------------------------------------------------
create table ai.integration_permissions (
  id                 uuid primary key default gen_random_uuid(),
  service_account_id uuid not null references core.service_accounts (id) on delete restrict,
  permission_id      uuid not null references core.permissions (id) on delete restrict,
  scope_type         core.scope_type not null,
  group_id           uuid not null references org.groups (id) on delete restrict,
  brand_id           uuid,
  restaurant_id      uuid,
  valid_from         timestamptz not null default now(),
  valid_until        timestamptz,
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint integration_permissions_scope_consistent check (
    (scope_type = 'group' and brand_id is null and restaurant_id is null)
    or (scope_type = 'brand' and brand_id is not null and restaurant_id is null)
    or (scope_type = 'restaurant' and brand_id is not null and restaurant_id is not null)
  ),
  constraint integration_permissions_validity check (valid_until is null or valid_until > valid_from),
  constraint integration_permissions_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  constraint integration_permissions_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint integration_permissions_restaurant_brand_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict
);
comment on table ai.integration_permissions is
  'Permisos explícitos de cada cuenta técnica (agente o integración), con su alcance. Solo estructura en la Fase 1: no hay filas ni acceso por la API. En la Fase 5 los usará la función de permisos de las cuentas técnicas.';
comment on column ai.integration_permissions.id is 'Identificador del permiso de integración.';
comment on column ai.integration_permissions.service_account_id is 'Cuenta técnica que recibe el permiso.';
comment on column ai.integration_permissions.permission_id is 'Permiso que recibe.';
comment on column ai.integration_permissions.scope_type is 'Alcance: grupo, marca o restaurante.';
comment on column ai.integration_permissions.group_id is 'Grupo del permiso (siempre).';
comment on column ai.integration_permissions.brand_id is 'Marca, si el alcance es marca o restaurante.';
comment on column ai.integration_permissions.restaurant_id is 'Restaurante, si el alcance es restaurante.';
comment on column ai.integration_permissions.valid_from is 'Desde cuándo vale.';
comment on column ai.integration_permissions.valid_until is 'Hasta cuándo vale. Vacío si no vence.';
comment on column ai.integration_permissions.created_at is 'Cuándo se otorgó (lo pone la base).';
comment on column ai.integration_permissions.created_by is 'Quién lo otorgó (lo pone la base).';
comment on column ai.integration_permissions.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column ai.integration_permissions.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column ai.integration_permissions.deleted_at is 'Cuándo se quitó (borrado lógico). Vacío si está vigente.';
comment on column ai.integration_permissions.deleted_by is 'Quién lo quitó (lo pone la base).';

create unique index integration_permissions_key on ai.integration_permissions
  (service_account_id, permission_id, group_id, brand_id, restaurant_id) nulls not distinct where deleted_at is null;
create index integration_permissions_permission_idx on ai.integration_permissions (permission_id);
create index integration_permissions_group_idx on ai.integration_permissions (group_id);
create index integration_permissions_brand_idx on ai.integration_permissions (brand_id) where brand_id is not null;
create index integration_permissions_restaurant_idx on ai.integration_permissions (restaurant_id) where restaurant_id is not null;

alter table ai.integration_permissions enable row level security;
revoke all on ai.integration_permissions from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on ai.integration_permissions
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on ai.integration_permissions
  for each row execute function audit.log_change();
create trigger validate_identity before insert or update on ai.integration_permissions
  for each row execute function core.enforce_identity_rules();
create trigger reject_truncate before truncate on ai.integration_permissions
  for each statement execute function core.reject_truncate();
