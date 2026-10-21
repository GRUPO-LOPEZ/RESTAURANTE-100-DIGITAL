-- Fase 1 · M4 — Identidad: perfiles, permisos, roles, matriz, membresías, asignaciones
-- y cuentas técnicas (docs/fases/fase-1-plan.md, docs/modulos/00-identidad.md).
-- Las tablas nacen cerradas: RLS activado, sin políticas y sin GRANT para la API.
-- has_permission y las políticas llegan en M5; assign_role (sin escalada) en M6.

-- ---------------------------------------------------------------------------
-- 1. Tipos
-- ---------------------------------------------------------------------------
create type core.account_status as enum ('active', 'disabled');
comment on type core.account_status is 'Estado de una cuenta: active (puede operar) o disabled (bloqueada; conserva toda su historia).';

create type core.scope_type as enum ('group', 'brand', 'restaurant');
comment on type core.scope_type is 'Alcance de una asignación de rol: group (todo el grupo), brand (una marca y sus locales) o restaurant (un local).';

-- Para exigir "este restaurante es de esta marca" con una FK compuesta.
alter table org.restaurants add constraint restaurants_id_brand_key unique (id, brand_id);

-- ---------------------------------------------------------------------------
-- 2. Perfiles de personas
-- ---------------------------------------------------------------------------
create table core.user_profiles (
  id               uuid primary key references core.actors (id) on delete restrict,
  first_name       text check (first_name is null or length(btrim(first_name)) between 1 and 80),
  last_name        text check (last_name is null or length(btrim(last_name)) between 1 and 80),
  email            text not null check (length(email) between 3 and 320),
  status           core.account_status not null default 'active',
  disabled_at      timestamptz,
  disabled_reason  text check (disabled_reason is null or length(disabled_reason) <= 500),
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references core.actors (id) on delete restrict,
  deleted_at       timestamptz,
  deleted_by       uuid references core.actors (id) on delete restrict,
  constraint user_profiles_disabled_consistent check ((status = 'disabled') = (disabled_at is not null))
);

comment on table core.user_profiles is 'Persona que usa el sistema. Una por cada usuario persona de Supabase Auth. Nunca se borra: se bloquea.';
comment on column core.user_profiles.id is 'Mismo id que el usuario en Auth y que su actor.';
comment on column core.user_profiles.first_name is 'Nombre.';
comment on column core.user_profiles.last_name is 'Apellido.';
comment on column core.user_profiles.email is 'Correo con el que entra (copiado de Auth al darse de alta). No se edita a mano; la sincronización con los cambios de Auth llega en M8.';
comment on column core.user_profiles.status is 'Si la cuenta puede operar o está bloqueada.';
comment on column core.user_profiles.disabled_at is 'Cuándo se bloqueó la cuenta. Vacío si está activa.';
comment on column core.user_profiles.disabled_reason is 'Por qué se bloqueó la cuenta.';
comment on column core.user_profiles.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.user_profiles.created_by is 'Quién lo creó (lo pone la base).';
comment on column core.user_profiles.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.user_profiles.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.user_profiles.deleted_at is 'Borrado lógico. Un perfil con historia no se borra: se bloquea.';
comment on column core.user_profiles.deleted_by is 'Quién lo borró (lo pone la base).';

-- Aviso: con SSO, Auth admite dos usuarios con el mismo correo; este unique haría fallar el alta.
-- Se revisa si algún día se activa SSO.
create unique index user_profiles_email_key on core.user_profiles (lower(email)) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. Permisos (módulo.acción)
-- ---------------------------------------------------------------------------
create table core.permissions (
  id            uuid primary key default gen_random_uuid(),
  code          text not null check (code ~ '^[a-z_]+\.[a-z_]+$'),
  module        text not null,
  description   text not null check (length(btrim(description)) between 1 and 300),
  is_sensitive  boolean not null default false,
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict,
  constraint permissions_module_matches_code check (module = split_part(code, '.', 1))
);

comment on table core.permissions is 'Catálogo de permisos. Un permiso es módulo + acción, por ejemplo recipes.publish. Se carga por migración.';
comment on column core.permissions.id is 'Identificador del permiso.';
comment on column core.permissions.code is 'Código módulo.acción, en minúsculas.';
comment on column core.permissions.module is 'Módulo al que pertenece (la parte antes del punto).';
comment on column core.permissions.description is 'Qué permite hacer, en español.';
comment on column core.permissions.is_sensitive is 'Si es un permiso delicado (seguridad, usuarios, auditoría).';
comment on column core.permissions.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.permissions.created_by is 'Quién lo creó (lo pone la base).';
comment on column core.permissions.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.permissions.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.permissions.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column core.permissions.deleted_by is 'Quién lo borró (lo pone la base).';

create unique index permissions_code_key on core.permissions (code) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 4. Roles
-- ---------------------------------------------------------------------------
create table core.roles (
  id            uuid primary key default gen_random_uuid(),
  code          text not null check (code ~ '^[a-z_]+$'),
  name          text not null check (length(btrim(name)) between 1 and 80),
  description   text check (description is null or length(description) <= 500),
  level         smallint check (level between 1 and 99),
  requires_mfa  boolean not null default false,
  is_system     boolean not null default false,
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict
);

comment on table core.roles is 'Roles del Módulo Maestro (por ejemplo, Gerente de Restaurante). Un rol agrupa permisos; el alcance lo da cada asignación.';
comment on column core.roles.id is 'Identificador del rol.';
comment on column core.roles.code is 'Código del rol, en minúsculas.';
comment on column core.roles.name is 'Nombre del rol, en español.';
comment on column core.roles.description is 'Qué puede y qué no puede, según el Módulo Maestro.';
comment on column core.roles.level is 'Nivel orientativo (orden del Módulo Maestro). No da permisos.';
comment on column core.roles.requires_mfa is 'Si las personas con este rol tienen que usar doble verificación (MFA).';
comment on column core.roles.is_system is 'Si es un rol del catálogo inicial.';
comment on column core.roles.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.roles.created_by is 'Quién lo creó (lo pone la base).';
comment on column core.roles.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.roles.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.roles.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column core.roles.deleted_by is 'Quién lo borró (lo pone la base).';

create unique index roles_code_key on core.roles (code) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 5. Matriz rol × permiso
-- ---------------------------------------------------------------------------
create table core.role_permissions (
  id             uuid primary key default gen_random_uuid(),
  role_id        uuid not null references core.roles (id) on delete restrict,
  permission_id  uuid not null references core.permissions (id) on delete restrict,
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict
);

comment on table core.role_permissions is 'Qué permisos tiene cada rol. Quitar un permiso es un borrado lógico, que queda en el historial.';
comment on column core.role_permissions.id is 'Identificador de la relación.';
comment on column core.role_permissions.role_id is 'Rol.';
comment on column core.role_permissions.permission_id is 'Permiso que tiene ese rol.';
comment on column core.role_permissions.created_at is 'Cuándo se otorgó (lo pone la base).';
comment on column core.role_permissions.created_by is 'Quién lo otorgó (lo pone la base).';
comment on column core.role_permissions.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.role_permissions.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.role_permissions.deleted_at is 'Cuándo se quitó (borrado lógico). Vacío si está vigente.';
comment on column core.role_permissions.deleted_by is 'Quién lo quitó (lo pone la base).';

create unique index role_permissions_key on core.role_permissions (role_id, permission_id) where deleted_at is null;
create index role_permissions_permission_idx on core.role_permissions (permission_id, role_id) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 6. Membresías: a qué grupo pertenece cada persona
-- ---------------------------------------------------------------------------
create table core.user_memberships (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references core.user_profiles (id) on delete restrict,
  group_id    uuid not null references org.groups (id) on delete restrict,
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict
);

comment on table core.user_memberships is 'A qué grupo pertenece cada persona. Hace falta ser miembro para recibir roles en ese grupo.';
comment on column core.user_memberships.id is 'Identificador de la membresía.';
comment on column core.user_memberships.user_id is 'Persona.';
comment on column core.user_memberships.group_id is 'Grupo al que pertenece.';
comment on column core.user_memberships.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.user_memberships.created_by is 'Quién la creó (lo pone la base).';
comment on column core.user_memberships.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.user_memberships.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column core.user_memberships.deleted_at is 'Cuándo terminó (borrado lógico). Vacío si está vigente.';
comment on column core.user_memberships.deleted_by is 'Quién la terminó (lo pone la base).';

create unique index user_memberships_key on core.user_memberships (user_id, group_id) where deleted_at is null;
create index user_memberships_group_idx on core.user_memberships (group_id);

-- ---------------------------------------------------------------------------
-- 7. Asignaciones: persona + rol + alcance
-- ---------------------------------------------------------------------------
create table core.user_role_assignments (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references core.user_profiles (id) on delete restrict,
  role_id        uuid not null references core.roles (id) on delete restrict,
  scope_type     core.scope_type not null,
  group_id       uuid not null references org.groups (id) on delete restrict,
  brand_id       uuid,
  restaurant_id  uuid,
  valid_from     timestamptz not null default now(),
  valid_until    timestamptz,
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint user_role_assignments_scope_consistent check (
    (scope_type = 'group' and brand_id is null and restaurant_id is null)
    or (scope_type = 'brand' and brand_id is not null and restaurant_id is null)
    or (scope_type = 'restaurant' and brand_id is not null and restaurant_id is not null)
  ),
  constraint user_role_assignments_validity check (valid_until is null or valid_until > valid_from),
  -- Alcance consistente por estructura: la marca es del grupo y el local es de esa marca y ese grupo.
  constraint user_role_assignments_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  constraint user_role_assignments_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint user_role_assignments_restaurant_brand_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict
);

comment on table core.user_role_assignments is 'Qué rol tiene cada persona y dónde: en todo el grupo, en una marca o en un local. Quitar un rol es un borrado lógico. Desde M6 solo se escribe con core.assign_role().';
comment on column core.user_role_assignments.id is 'Identificador de la asignación.';
comment on column core.user_role_assignments.user_id is 'Persona.';
comment on column core.user_role_assignments.role_id is 'Rol asignado.';
comment on column core.user_role_assignments.scope_type is 'Alcance: grupo, marca o restaurante.';
comment on column core.user_role_assignments.group_id is 'Grupo de la asignación (siempre).';
comment on column core.user_role_assignments.brand_id is 'Marca, si el alcance es marca o restaurante.';
comment on column core.user_role_assignments.restaurant_id is 'Restaurante, si el alcance es restaurante.';
comment on column core.user_role_assignments.valid_from is 'Desde cuándo vale.';
comment on column core.user_role_assignments.valid_until is 'Hasta cuándo vale. Vacío si no vence.';
comment on column core.user_role_assignments.created_at is 'Cuándo se asignó (lo pone la base).';
comment on column core.user_role_assignments.created_by is 'Quién lo asignó (lo pone la base).';
comment on column core.user_role_assignments.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.user_role_assignments.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column core.user_role_assignments.deleted_at is 'Cuándo se quitó el rol (borrado lógico). Vacío si está vigente.';
comment on column core.user_role_assignments.deleted_by is 'Quién quitó el rol (lo pone la base).';

-- Una misma asignación vigente no se repite. Empieza por user_id: sirve también para has_permission (M5).
create unique index user_role_assignments_key on core.user_role_assignments
  (user_id, role_id, group_id, brand_id, restaurant_id) nulls not distinct where deleted_at is null;
create index user_role_assignments_role_idx on core.user_role_assignments (role_id) where deleted_at is null;
create index user_role_assignments_group_idx on core.user_role_assignments (group_id);
create index user_role_assignments_brand_idx on core.user_role_assignments (brand_id, group_id) where brand_id is not null;
create index user_role_assignments_restaurant_idx on core.user_role_assignments (restaurant_id, group_id) where restaurant_id is not null;

-- ---------------------------------------------------------------------------
-- 8. Cuentas técnicas (solo estructura; agentes en la Fase 5)
-- ---------------------------------------------------------------------------
create table core.service_accounts (
  id             uuid primary key references core.actors (id) on delete restrict,
  code           text not null check (code ~ '^[a-z0-9_-]{2,60}$'),
  name           text not null check (length(btrim(name)) between 1 and 120),
  description    text check (description is null or length(description) <= 500),
  status         core.account_status not null default 'active',
  owner_user_id  uuid not null references core.user_profiles (id) on delete restrict,
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict
);

comment on table core.service_accounts is 'Cuenta técnica de un agente o integración. Es un usuario de Auth de tipo cuenta técnica, con permisos mínimos y explícitos (Fase 5). Nunca usa la clave service_role.';
comment on column core.service_accounts.id is 'Mismo id que su actor y su usuario técnico de Auth.';
comment on column core.service_accounts.code is 'Código de la cuenta (por ejemplo, agente-facturas).';
comment on column core.service_accounts.name is 'Nombre de la cuenta, en español.';
comment on column core.service_accounts.description is 'Para qué se usa.';
comment on column core.service_accounts.status is 'Si la cuenta puede operar o está bloqueada.';
comment on column core.service_accounts.owner_user_id is 'Persona responsable de la cuenta.';
comment on column core.service_accounts.created_at is 'Cuándo se creó (lo pone la base).';
comment on column core.service_accounts.created_by is 'Quién la creó (lo pone la base).';
comment on column core.service_accounts.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column core.service_accounts.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column core.service_accounts.deleted_at is 'Borrado lógico. Vacío si está vigente.';
comment on column core.service_accounts.deleted_by is 'Quién la borró (lo pone la base).';

create unique index service_accounts_code_key on core.service_accounts (code) where deleted_at is null;
create index service_accounts_owner_idx on core.service_accounts (owner_user_id);

-- ---------------------------------------------------------------------------
-- 9. Reglas que cruzan tablas
-- ---------------------------------------------------------------------------
create function core.enforce_identity_rules()
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
      perform 1 from core.user_memberships m
       where m.user_id = new.user_id and m.group_id = new.group_id and m.deleted_at is null
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
        raise exception 'No se puede asignar un rol a una cuenta bloqueada.' using errcode = '23514';
      end if;
    end if;

  elsif tg_table_name = 'user_memberships' then
    if tg_op = 'UPDATE' and (new.user_id is distinct from old.user_id or new.group_id is distinct from old.group_id) then
      raise exception 'Una membresía no cambia de persona ni de grupo.' using errcode = '42501';
    end if;
    if v_becomes_deleted and exists (
         select 1 from core.user_role_assignments a
          where a.user_id = new.user_id and a.group_id = new.group_id and a.deleted_at is null) then
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

  elsif tg_table_name = 'user_profiles' then
    if tg_op = 'UPDATE' and new.email is distinct from old.email then
      raise exception 'El correo del perfil no se edita a mano (la sincronización con Auth llega en M8).'
        using errcode = '42501';
    end if;
    if v_becomes_deleted then
      raise exception 'Un perfil no se borra: se bloquea, para conservar su historia.' using errcode = '42501';
    end if;
  end if;

  return new;
end
$$;
comment on function core.enforce_identity_rules() is
  'Trigger BEFORE INSERT OR UPDATE en las tablas de identidad: asignaciones y membresías inmutables, vigencia que solo se acorta, membresía, rol vigente y cuenta activa para tener roles, no borrar roles ni permisos en uso, perfiles que no se borran, cuentas técnicas solo de tipo cuenta técnica y con responsable activo.';

-- Perfiles: se crean solos al dar de alta un usuario persona en Auth.
create or replace function core.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type core.actor_type := case when new.raw_app_meta_data ->> 'actor_type' = 'service_account'
    then 'service_account'::core.actor_type else 'user'::core.actor_type end;
begin
  insert into core.actors (id, actor_type) values (new.id, v_type)
  on conflict (id) do nothing;

  if v_type = 'user' then
    insert into core.user_profiles (id, first_name, last_name, email)
    values (
      new.id,
      nullif(btrim(new.raw_user_meta_data ->> 'first_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'last_name'), ''),
      coalesce(new.email, new.id::text || '@sin-correo.invalid')
    )
    on conflict (id) do nothing;
  end if;

  return new;
end
$$;
comment on function core.handle_new_auth_user() is 'Trigger: al crear un usuario en auth.users crea su actor y, si es una persona, su perfil.';

-- Perfiles para personas que ya existían.
insert into core.user_profiles (id, email)
select u.id, coalesce(u.email, u.id::text || '@sin-correo.invalid')
from auth.users u
join core.actors a on a.id = u.id and a.actor_type = 'user'
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- 10. Cerradas por defecto, con control, reglas, auditoría y anti-vaciado
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['user_profiles', 'permissions', 'roles', 'role_permissions',
                           'user_memberships', 'user_role_assignments', 'service_accounts'] loop
    execute format('alter table core.%I enable row level security', t);
    execute format('revoke all on core.%I from public, anon, authenticated, service_role', t);
    execute format(
      'create trigger set_control_columns before insert or update on core.%I
         for each row execute function core.set_control_columns()', t);
    execute format(
      'create trigger validate_identity before insert or update on core.%I
         for each row execute function core.enforce_identity_rules()', t);
    execute format(
      'create trigger log_change after insert or update or delete on core.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on core.%I
         for each statement execute function core.reject_truncate()', t);
  end loop;
end
$$;

revoke execute on function core.enforce_identity_rules() from public;

-- ---------------------------------------------------------------------------
-- 11. Catálogo inicial del Módulo Maestro (docs/modulos/00-identidad.md)
--     Matriz aprobada por Joaco el 2026-10-20. Soy la ajusta después desde el panel.
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Catálogo inicial del Módulo Maestro', 'maintenance');

  insert into core.permissions (code, module, description, is_sensitive) values
    ('org.view',          'org',       'Ver la estructura (grupo, marcas, locales y áreas) dentro del alcance.', false),
    ('org.manage',        'org',       'Crear y editar marcas, locales y áreas dentro del alcance.', false),
    ('org.transfer',      'org',       'Hacer el trámite de traspaso de un local a otra marca o de una marca a otro grupo.', true),
    ('users.view',        'users',     'Ver personas y sus roles dentro del alcance.', false),
    ('users.invite',      'users',     'Invitar personas al sistema.', true),
    ('users.manage',      'users',     'Editar los datos de las personas.', true),
    ('users.deactivate',  'users',     'Bloquear y reactivar cuentas.', true),
    ('roles.assign',      'roles',     'Asignar o quitar roles, nunca más de los que uno tiene.', true),
    ('roles.manage',      'roles',     'Editar el catálogo de roles y la matriz de permisos.', true),
    ('audit.view',        'audit',     'Leer el historial de cambios dentro del alcance.', true),
    ('audit.export',      'audit',     'Exportar el historial de cambios.', true),
    ('approvals.view',    'approvals', 'Ver solicitudes de aprobación.', false),
    ('approvals.decide',  'approvals', 'Aprobar o rechazar solicitudes.', true),
    ('workflows.manage',  'workflows', 'Definir qué cambios necesitan aprobación y quién la da.', true);

  insert into core.roles (code, name, description, level, requires_mfa, is_system) values
    ('superadmin', 'Superadministrador',
     'Puede: seguridad técnica, usuarios, roles y permisos. No puede: reescribir o borrar auditoría.', 1, true, true),
    ('general_management', 'Dirección General',
     'Puede: ver todo lo consolidado y aprobar cambios críticos. No puede: administrar la seguridad técnica.', 2, true, true),
    ('brand_director', 'Director de Marca',
     'Puede: gestionar su marca y sus locales y aprobar dentro de la marca. No puede: ver otras marcas salvo permiso explícito.', 3, true, true),
    ('restaurant_manager', 'Gerente de Restaurante',
     'Puede: gestionar su local y su equipo y ver reportes. No puede: editar recetas de otros locales.', 4, true, true),
    ('executive_chef', 'Chef Ejecutivo',
     'Puede: aprobar y publicar recetas. No puede: cambiar precios de materias primas.', 5, false, true),
    ('head_chef', 'Jefe de Cocina',
     'Puede: crear borradores y pedir revisión. No puede: publicar sin aprobación.', 6, false, true),
    ('controller', 'Controller / Costos',
     'Puede: ver y modificar costos y aprobar precios. No puede: cambiar gramajes aprobados.', 7, true, true),
    ('purchasing', 'Compras',
     'Puede: cargar proveedores y precios propuestos. No puede: aprobar sus propios precios.', 8, false, true),
    ('cook', 'Cocinero / Operador',
     'Puede: ver las fichas vigentes de su local. No puede: ver precios ni costos.', 9, false, true),
    ('auditor', 'Auditor / Consulta',
     'Puede: leer historial y reportes. No puede: crear, editar ni aprobar.', 10, false, true);

  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
  from (values
    ('superadmin', 'org.view'), ('superadmin', 'org.manage'), ('superadmin', 'org.transfer'),
    ('superadmin', 'users.view'), ('superadmin', 'users.invite'), ('superadmin', 'users.manage'),
    ('superadmin', 'users.deactivate'), ('superadmin', 'roles.assign'), ('superadmin', 'roles.manage'),
    ('superadmin', 'audit.view'), ('superadmin', 'audit.export'), ('superadmin', 'workflows.manage'),
    ('superadmin', 'approvals.view'),

    ('general_management', 'org.view'), ('general_management', 'org.transfer'), ('general_management', 'users.view'),
    ('general_management', 'audit.view'), ('general_management', 'audit.export'),
    ('general_management', 'approvals.view'), ('general_management', 'approvals.decide'),

    ('brand_director', 'org.view'), ('brand_director', 'org.manage'), ('brand_director', 'users.view'),
    ('brand_director', 'users.invite'), ('brand_director', 'users.manage'), ('brand_director', 'users.deactivate'),
    ('brand_director', 'roles.assign'), ('brand_director', 'audit.view'),
    ('brand_director', 'approvals.view'), ('brand_director', 'approvals.decide'),

    ('restaurant_manager', 'org.view'), ('restaurant_manager', 'org.manage'), ('restaurant_manager', 'users.view'),
    ('restaurant_manager', 'users.invite'), ('restaurant_manager', 'users.manage'),
    ('restaurant_manager', 'users.deactivate'), ('restaurant_manager', 'roles.assign'),
    ('restaurant_manager', 'approvals.view'),

    ('executive_chef', 'org.view'), ('executive_chef', 'approvals.view'), ('executive_chef', 'approvals.decide'),

    ('head_chef', 'org.view'), ('head_chef', 'approvals.view'),

    ('controller', 'org.view'), ('controller', 'audit.view'), ('controller', 'approvals.view'),
    ('controller', 'approvals.decide'),

    ('purchasing', 'org.view'), ('purchasing', 'approvals.view'),

    ('cook', 'org.view'),

    ('auditor', 'org.view'), ('auditor', 'users.view'), ('auditor', 'audit.view'),
    ('auditor', 'audit.export'), ('auditor', 'approvals.view')
  ) as m (role_code, permission_code)
  join core.roles r on r.code = m.role_code
  join core.permissions p on p.code = m.permission_code;
end
$$;
