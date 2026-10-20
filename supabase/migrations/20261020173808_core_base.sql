-- Fase 1 · M1 — Base común (docs/fases/fase-1-plan.md).
-- Privilegios cerrados por defecto, actores, columnas de control y contexto del cambio.
-- No crea roles de negocio, permisos ni acceso por la API (eso llega con el ADR-0005 y M4).
-- Revisado por db-reviewer y security-auditor el 2026-10-20 antes del primer commit.

-- ---------------------------------------------------------------------------
-- 1. Ninguna función nueva queda ejecutable por PUBLIC (regla 2 del plan).
--    Postgres da EXECUTE a PUBLIC por defecto. Los default privileges POR ESQUEMA
--    solo pueden sumar permisos, no quitar los globales: por eso el corte es global,
--    para cada rol que crea funciones (postgres acá; audit_owner más abajo).
--    Cada función que deba usarse recibe su GRANT explícito.
-- ---------------------------------------------------------------------------
alter default privileges for role postgres revoke execute on functions from public;

do $$
declare
  s text;
begin
  foreach s in array array[
    'core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
    'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting'
  ] loop
    execute format('revoke all on schema %I from public', s);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Dueño dedicado del esquema de auditoría. Sin login: nadie entra como él.
--    postgres puede "ponerse" el rol (SET) para crear objetos en migraciones,
--    pero NO lo hereda: sin un `set role audit_owner` explícito no puede alterar,
--    desactivar triggers ni escribir en la auditoría.
--    Límite que queda (ADR-0006): quien tenga la contraseña
--    de postgres puede hacer `set role audit_owner`. Contra eso: sellos (M2) y
--    exportación externa del esquema audit.
-- ---------------------------------------------------------------------------
create role audit_owner nologin;
comment on role audit_owner is 'Dueño del esquema audit y de audit.log_change(). Sin login.';
grant audit_owner to postgres with inherit false, set true;

alter schema audit owner to audit_owner;

-- ---------------------------------------------------------------------------
-- 3. Origen del cambio (lista cerrada, nunca texto libre).
--    Como audit_owner: sus funciones también nacen cerradas (postgres no lo hereda,
--    así que no puede fijar estos default privileges desde afuera).
-- ---------------------------------------------------------------------------
set role audit_owner;
alter default privileges revoke execute on functions from public;
create type audit.change_origin as enum ('app', 'edge_function', 'agent', 'import', 'seed', 'maintenance');
comment on type audit.change_origin is
  'Desde dónde se hizo un cambio: app (la aplicación), edge_function (función de servidor), agent (agente de IA), import (carga masiva), seed (datos de prueba) o maintenance (mantenimiento documentado).';
reset role;

-- ---------------------------------------------------------------------------
-- 4. Actores: "quién hizo algo". Una fila por usuario de Supabase Auth.
--    Las cuentas técnicas de los agentes también son usuarios de Auth (regla 3).
--    actor_type es descriptivo: los permisos de una cuenta técnica salen de
--    core.service_accounts (M4), nunca de esta columna ni de app_metadata.
--    on delete restrict: un usuario con historia no se borra; se bloquea (M8).
-- ---------------------------------------------------------------------------
create type core.actor_type as enum ('user', 'service_account');
comment on type core.actor_type is 'Tipo de actor: user (persona) o service_account (cuenta técnica de un agente o integración).';

create table core.actors (
  id          uuid primary key references auth.users (id) on delete restrict,
  actor_type  core.actor_type not null default 'user',
  created_at  timestamptz not null default now()
);

comment on table core.actors is
  'Quién puede hacer cambios: una fila por cada usuario de Supabase Auth, sea persona o cuenta técnica. Las columnas created_by, updated_by y deleted_by de todas las tablas apuntan acá. Un usuario con historia no se borra: se bloquea.';
comment on column core.actors.id is 'Mismo id que el usuario en auth.users.';
comment on column core.actors.actor_type is 'Persona o cuenta técnica, según app_metadata al darse de alta (solo lo escribe el servidor). Descriptivo: no decide permisos.';
comment on column core.actors.created_at is 'Cuándo se dio de alta el actor.';

alter table core.actors enable row level security;
revoke all on core.actors from public, anon, authenticated, service_role;

-- La auditoría necesita leer el tipo de actor.
create policy actors_read_for_audit on core.actors for select to audit_owner using (true);
grant usage on schema core to audit_owner;
grant select, references on core.actors to audit_owner;

-- Alta automática del actor al crear un usuario en Auth (patrón estándar de Supabase).
create function core.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into core.actors (id, actor_type)
  values (
    new.id,
    case when new.raw_app_meta_data ->> 'actor_type' = 'service_account'
      then 'service_account'::core.actor_type
      else 'user'::core.actor_type
    end
  )
  on conflict (id) do nothing;
  return new;
end
$$;
comment on function core.handle_new_auth_user() is 'Trigger: crea el actor cuando se crea un usuario en auth.users.';

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function core.handle_new_auth_user();

-- Usuarios que ya existan antes de esta migración.
insert into core.actors (id, actor_type)
select
  u.id,
  case when u.raw_app_meta_data ->> 'actor_type' = 'service_account'
    then 'service_account'::core.actor_type
    else 'user'::core.actor_type
  end
from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Actor de la sesión: sale SOLO del JWT completo (request.jwt.claims), que
--    PostgREST arma desde el token firmado. No se usa el GUC suelto
--    request.jwt.claim.sub (heredado), que una función podría pisar.
--    Un sub que no es uuid no rompe nada: el actor queda nulo y el texto va
--    a la auditoría como actor_subject.
-- ---------------------------------------------------------------------------
create function core.current_actor_subject()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')
$$;
comment on function core.current_actor_subject() is 'El sub del JWT de la sesión, tal cual viene. Nulo si no hay sesión.';

create function core.current_actor_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select case
    when s ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then s::uuid
  end
  from (select core.current_actor_subject() as s) as t
$$;
comment on function core.current_actor_id() is 'Id del actor de la sesión, tomado del JWT. Nulo si no hay sesión (migraciones, seed) o si el sub no es un uuid.';

grant execute on function core.current_actor_subject() to audit_owner;
grant execute on function core.current_actor_id() to audit_owner;

-- ---------------------------------------------------------------------------
-- 6. Columnas de control: se completan acá, nunca desde la app.
--    Toda tabla que use este trigger tiene que tener las 6 columnas de control.
--    security definer solo para poder leer el actor sin dar acceso al esquema core
--    a los roles de la API (eso se decide en el ADR-0005). No lee ni escribe tablas.
-- ---------------------------------------------------------------------------
create function core.set_control_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_control constant text[] := array['created_at', 'created_by', 'updated_at', 'updated_by', 'deleted_at', 'deleted_by'];
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

  -- Un cambio que no cambia nada (fuera de las columnas de control) no toca la fila:
  -- así la fila nunca dice que alguien la cambió sin un evento en la auditoría.
  if (to_jsonb(new) - v_control) = (to_jsonb(old) - v_control)
     and (new.deleted_at is null) = (old.deleted_at is null) then
    return old;
  end if;

  new.updated_at := now();
  new.updated_by := v_actor;

  if old.deleted_at is null and new.deleted_at is not null then
    new.deleted_at := now();
    new.deleted_by := v_actor;          -- borrado lógico
  elsif new.deleted_at is null then
    new.deleted_by := null;             -- vigente o restaurado
  else
    new.deleted_at := old.deleted_at;   -- ya borrado: se conserva quién y cuándo
    new.deleted_by := old.deleted_by;
  end if;

  return new;
end
$$;
comment on function core.set_control_columns() is
  'Trigger BEFORE INSERT OR UPDATE FOR EACH ROW: completa created/updated/deleted at/by con la hora y el actor de la sesión, impide cambiar id y datos de creación, e ignora los cambios que no cambian nada.';

-- ---------------------------------------------------------------------------
-- 7. Motivo y origen del cambio, solo para la transacción en curso.
--    Son informativos: se guardan en la auditoría y NUNCA deciden permisos.
--    El origen se recibe como texto para no exigir acceso al esquema audit.
-- ---------------------------------------------------------------------------
create function core.set_change_context(p_reason text, p_origin text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_reason is null or length(btrim(p_reason)) = 0 or length(p_reason) > 500 then
    raise exception 'El motivo del cambio es obligatorio y puede tener hasta 500 caracteres.'
      using errcode = '22023';
  end if;
  if p_origin is null or p_origin not in ('app', 'edge_function', 'agent', 'import', 'seed', 'maintenance') then
    raise exception 'Origen del cambio inválido. Valores posibles: app, edge_function, agent, import, seed, maintenance.'
      using errcode = '22023';
  end if;

  perform set_config('app.reason', p_reason, true);
  perform set_config('app.origin', p_origin, true);
end
$$;
comment on function core.set_change_context(text, text) is
  'Guarda el motivo (1 a 500 caracteres) y el origen del cambio para la transacción en curso. La auditoría los registra. Informativo: nunca decide permisos.';

-- Por las dudas, aunque los default privileges ya lo cubren.
revoke execute on function core.handle_new_auth_user() from public;
revoke execute on function core.current_actor_subject() from public;
revoke execute on function core.current_actor_id() from public;
revoke execute on function core.set_control_columns() from public;
revoke execute on function core.set_change_context(text, text) from public;
