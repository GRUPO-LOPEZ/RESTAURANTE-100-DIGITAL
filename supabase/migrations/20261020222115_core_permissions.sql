-- Fase 1 · M5 — Las funciones que deciden y la apertura de la API (ADR-0005).
-- - core.has_permission y su familia: la única lógica de permisos del sistema.
-- - Datos opcionales del local (P10) y referencia al local anterior (ADR-0007).
-- - Un registro borrado no se edita: primero se restaura (P13).
-- - La auditoría guarda los roles vigentes de quien cambia (actor_roles).
-- - La API lee core y org con RLS; las escrituras van solo por funciones (RPC),
--   que validan el permiso y registran motivo y origen en la misma transacción.

-- ---------------------------------------------------------------------------
-- 1. Bloqueo temporal por intentos fallidos (ADR-0010; la lógica llega en M8).
--    Se agrega ahora para que la función que decide los permisos ya lo tenga en cuenta.
-- ---------------------------------------------------------------------------
alter table core.user_profiles
  add column failed_login_count   smallint not null default 0 check (failed_login_count between 0 and 1000),
  add column last_failed_login_at timestamptz,
  add column locked_until         timestamptz;

comment on column core.user_profiles.failed_login_count is 'Intentos fallidos seguidos de ingreso. Vuelve a cero con un ingreso bueno o al liberarse el bloqueo.';
comment on column core.user_profiles.last_failed_login_at is 'Cuándo fue el último intento fallido de ingreso.';
comment on column core.user_profiles.locked_until is 'Hasta cuándo está bloqueada temporalmente la cuenta por intentos fallidos (10 minutos, P18). Vacío si no está bloqueada.';

-- ---------------------------------------------------------------------------
-- 2. Datos del local (P10, todos opcionales) y local anterior (ADR-0007)
-- ---------------------------------------------------------------------------
-- Zonas horarias: tabla de referencia cargada por migración (una FK es barata; consultar
-- pg_timezone_names en un CHECK costaba ~19 ms por fila y no es inmutable).
create table org.time_zones (
  code text primary key check (length(code) between 1 and 64)
);
comment on table org.time_zones is 'Zonas horarias válidas para los locales (por ejemplo, America/Argentina/Buenos_Aires). Se carga por migración.';
comment on column org.time_zones.code is 'Nombre de la zona horaria, como lo conoce Postgres.';

insert into org.time_zones (code)
select name from pg_catalog.pg_timezone_names
 where name not like 'posix/%' and name not like 'Etc/%' and name ~ '^[A-Za-z]'
on conflict do nothing;
insert into org.time_zones (code) values ('UTC') on conflict do nothing;

alter table org.time_zones enable row level security;
revoke all on org.time_zones from public, anon, authenticated, service_role;
create trigger reject_truncate before truncate on org.time_zones
  for each statement execute function core.reject_truncate();

alter table org.restaurants
  add column code           text check (code is null or code ~ '^[A-Z0-9][A-Z0-9-]{1,19}$'),
  add column address        text check (address is null or length(btrim(address)) between 1 and 200),
  add column locality       text check (locality is null or length(btrim(locality)) between 1 and 120),
  add column legal_name     text check (legal_name is null or length(btrim(legal_name)) between 1 and 200),
  add column tax_id         text check (tax_id is null or tax_id ~ '^[0-9]{11}$'),
  add column phone          text check (phone is null or phone ~ '^[0-9 +()-]{6,30}$'),
  add column opened_on      date,
  add column time_zone      text not null default 'America/Argentina/Buenos_Aires'
                            references org.time_zones (code) on delete restrict,
  add column predecessor_id uuid references org.restaurants (id) on delete restrict,
  add constraint restaurants_predecessor_not_self check (predecessor_id is distinct from id);

comment on column org.restaurants.code is 'Código corto del local (por ejemplo, RAGU-PL), en mayúsculas. Opcional. Único dentro del grupo entre los vigentes.';
comment on column org.restaurants.address is 'Dirección del local. Opcional.';
comment on column org.restaurants.locality is 'Barrio o localidad. Opcional.';
comment on column org.restaurants.legal_name is 'Razón social del local. Opcional.';
comment on column org.restaurants.tax_id is 'CUIT del local: 11 dígitos, sin guiones. Opcional.';
comment on column org.restaurants.phone is 'Teléfono de contacto. Opcional.';
comment on column org.restaurants.opened_on is 'Fecha de apertura. Opcional.';
comment on column org.restaurants.time_zone is 'Zona horaria del local, para horarios de cocina y cierres del día. Por defecto, Buenos Aires.';
comment on column org.restaurants.predecessor_id is 'Local anterior, si este local nació de un traspaso de marca (ADR-0007). Vacío si no.';

create unique index restaurants_code_key on org.restaurants (group_id, code) where deleted_at is null and code is not null;
-- Un local tiene a lo sumo un sucesor (ADR-0007: el traspaso crea uno nuevo y cierra el viejo).
create unique index restaurants_predecessor_key on org.restaurants (predecessor_id) where predecessor_id is not null;
create index restaurants_time_zone_idx on org.restaurants (time_zone);

-- ---------------------------------------------------------------------------
-- 3. P13: un registro borrado no se edita. Primero se restaura, sin cambiar nada más;
--    después se edita. Así el historial muestra dos pasos claros (restore y update).
--    Mismo cuerpo que en M1, más esa regla.
-- ---------------------------------------------------------------------------
create or replace function core.set_control_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
  v_control constant text[] := array['created_at', 'created_by', 'updated_at', 'updated_by', 'deleted_at', 'deleted_by'];
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

  v_same_data := (to_jsonb(new) - v_control) = (to_jsonb(old) - v_control);

  -- Un cambio que no cambia nada (fuera de las columnas de control) no toca la fila:
  -- así la fila nunca dice que alguien la cambió sin un evento en la auditoría.
  if v_same_data and (new.deleted_at is null) = (old.deleted_at is null) then
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
comment on function core.set_control_columns() is
  'Trigger BEFORE INSERT OR UPDATE FOR EACH ROW: completa created/updated/deleted at/by con la hora y el actor de la sesión, impide cambiar id y datos de creación, ignora los cambios que no cambian nada y no deja editar un registro borrado (P13).';

-- ---------------------------------------------------------------------------
-- 4. La sesión: nivel de autenticación y si la persona puede operar
-- ---------------------------------------------------------------------------
create function core.current_aal()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal'
$$;
comment on function core.current_aal() is 'Nivel de autenticación de la sesión según el JWT: aal1 (solo contraseña) o aal2 (con doble verificación). Nulo sin sesión.';

-- Vigencia de una asignación. Las funciones de permisos repiten esta condición dentro de su
-- consulta, a propósito, para que Postgres la use con los índices (rendimiento).
create function core.is_assignment_current(p_valid_from timestamptz, p_valid_until timestamptz)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_valid_from <= now() and (p_valid_until is null or p_valid_until > now())
$$;
comment on function core.is_assignment_current(timestamptz, timestamptz) is 'Si una asignación está dentro de su vigencia en este momento.';

-- La persona de la sesión puede operar: perfil activo, sin bloqueo temporal y,
-- si alguno de sus roles exige doble verificación, la sesión es aal2.
create function core.current_session_ok()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- El JWT se lee una sola vez por llamada (rendimiento: esto corre en cada política).
  v_actor uuid := core.current_actor_id();
  v_aal   text := core.current_aal();
begin
  if v_actor is null then
    return false;
  end if;
  return exists (
    select 1
      from core.user_profiles p
     where p.id = v_actor
       and p.deleted_at is null
       and p.status = 'active'
       and (p.locked_until is null or p.locked_until <= now())
  )
  and (
    v_aal is not distinct from 'aal2'
    or not exists (
      select 1
        from core.user_role_assignments a
        join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.user_id = v_actor
         and a.deleted_at is null
         and r.requires_mfa
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
    )
  );
end
$$;
comment on function core.current_session_ok() is
  'Si la persona de la sesión puede operar: perfil activo y no borrado, sin bloqueo temporal, y con doble verificación (aal2) si alguno de sus roles vigentes la exige. Las cuentas técnicas no tienen perfil: siempre falso hasta la Fase 5.';

-- Lo que la persona de la sesión tiene para un permiso: un alcance por asignación vigente.
-- Interna: la usan las funciones de abajo, nunca la API.
create function core.actor_grants(p_permission text)
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
    join core.user_memberships m on m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
   where p.code = p_permission
     and a.user_id = v_actor
     and a.deleted_at is null
     and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now());
end
$$;
comment on function core.actor_grants(text) is
  'Interna. Alcances (grupo, marca o restaurante) en los que la persona de la sesión tiene un permiso, por sus asignaciones vigentes. Vacío si la sesión no puede operar.';

-- ---------------------------------------------------------------------------
-- 5. LA función que decide (security.md): ¿la sesión tiene este permiso sobre este alcance?
--    Un permiso de grupo cubre todo el grupo; de marca, la marca y sus locales;
--    de restaurante, solo ese local. Todo lo demás llama a esta.
-- ---------------------------------------------------------------------------
create function core.has_permission_for_scope(
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
  if v_actor is null or p_group_id is null
     or (p_scope_type <> 'group' and p_brand_id is null)
     or (p_scope_type = 'restaurant' and p_restaurant_id is null) then
    return false;
  end if;
  -- El alcance pedido tiene que cuadrar con la estructura: si no, un permiso de marca
  -- podría "cubrir" un local de otra marca pasando ids mezclados.
  if p_scope_type <> 'group'
     and not exists (select 1 from org.brands b where b.id = p_brand_id and b.group_id = p_group_id) then
    return false;
  end if;
  if p_scope_type = 'restaurant'
     and not exists (select 1 from org.restaurants r
                      where r.id = p_restaurant_id and r.brand_id = p_brand_id and r.group_id = p_group_id) then
    return false;
  end if;
  -- Una sola consulta (sin funciones anidadas): esto corre en cada fila que filtra una política.
  return core.current_session_ok() and exists (
    select 1
      from core.user_role_assignments a
      join core.roles r on r.id = a.role_id and r.deleted_at is null
      join core.role_permissions rp on rp.role_id = r.id and rp.deleted_at is null
      join core.permissions p on p.id = rp.permission_id and p.deleted_at is null and p.code = p_permission
      join core.user_memberships m on m.user_id = a.user_id and m.group_id = a.group_id and m.deleted_at is null
     where a.user_id = v_actor
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
comment on function core.has_permission_for_scope(text, core.scope_type, uuid, uuid, uuid) is
  'Decide si la sesión tiene un permiso que cubre un alcance (grupo, marca o restaurante). Un permiso de grupo cubre todo el grupo; de marca, la marca y sus locales; de restaurante, solo ese local. Es la base de has_permission.';

create function core.has_permission(p_permission text, p_restaurant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- restaurant_id nulo da falso: una política no puede abrir una tabla entera por error.
  return coalesce((
    select core.has_permission_for_scope(p_permission, 'restaurant', r.group_id, r.brand_id, r.id)
      from org.restaurants r
     where r.id = p_restaurant_id
  ), false);
end
$$;
comment on function core.has_permission(text, uuid) is
  'La función que decide los permisos (security.md): si la sesión tiene el permiso en ese restaurante. Restaurante nulo o inexistente: falso. La usan las políticas RLS, las funciones de servidor y la interfaz.';

create function core.has_permission_in_brand(p_permission text, p_brand_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select core.has_permission_for_scope(p_permission, 'brand', b.group_id, b.id)
      from org.brands b
     where b.id = p_brand_id
  ), false);
end
$$;
comment on function core.has_permission_in_brand(text, uuid) is
  'Si la sesión tiene el permiso a nivel de toda la marca (asignación de marca o de grupo). Un permiso de un solo local no alcanza.';

create function core.has_permission_in_group(p_permission text, p_group_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return core.has_permission_for_scope(p_permission, 'group', p_group_id);
end
$$;
comment on function core.has_permission_in_group(text, uuid) is
  'Si la sesión tiene el permiso a nivel de todo el grupo (solo asignaciones de grupo).';

-- SOLO para mostrar u ocultar menús. Prohibida en políticas RLS (la prueba de catálogo lo controla).
create function core.has_permission_anywhere(p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (select 1 from core.actor_grants(p_permission));
end
$$;
comment on function core.has_permission_anywhere(text) is
  'Si la sesión tiene el permiso en algún lado. SOLO para mostrar u ocultar menús en la interfaz: nunca en políticas RLS ni para autorizar un cambio.';

-- Lectura de la estructura: un alcance se puede ver si se cruza con alguno de los propios
-- (por ejemplo, un cocinero ve el nombre de su marca y de su grupo, no los de otros).
create function core.can_view_scope(
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
  return exists (
    select 1
      from core.actor_grants(p_permission) g
     where g.group_id = p_group_id
       and (
         p_scope_type = 'group'
         or g.scope_type = 'group'
         or (g.brand_id = p_brand_id
             and (p_scope_type = 'brand' or g.scope_type = 'brand' or g.restaurant_id = p_restaurant_id))
       )
  );
end
$$;
comment on function core.can_view_scope(text, core.scope_type, uuid, uuid, uuid) is
  'Solo para lectura: si el alcance se cruza con alguno en el que la sesión tiene el permiso (por encima o por debajo). Nunca para autorizar un cambio.';

-- ---------------------------------------------------------------------------
-- 5b. Versiones "de conjunto" para las políticas (rendimiento). Misma regla de alcance que
--     has_permission_for_scope (grupo cubre el grupo; marca, la marca y sus locales;
--     restaurante, ese local), pero se calculan UNA vez por consulta: la política queda
--     `id in (select core.permitted_restaurant_ids(...))` y Postgres arma un hash, en lugar
--     de llamar a una función por cada fila (con 2.000 locales: de ~750 ms a unos pocos ms).
-- ---------------------------------------------------------------------------
create function core.permitted_restaurant_ids(p_permission text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select distinct r.id
    from core.actor_grants(p_permission) g
    join org.restaurants r
      on r.group_id = g.group_id
     and (g.scope_type = 'group'
          or (g.scope_type = 'brand' and r.brand_id = g.brand_id)
          or (g.scope_type = 'restaurant' and r.id = g.restaurant_id));
end
$$;
comment on function core.permitted_restaurant_ids(text) is
  'Locales en los que la sesión tiene el permiso. Es la versión de conjunto de has_permission, para políticas RLS: se calcula una vez por consulta.';

-- Marcas que se cruzan con algún alcance propio (solo lectura: el cocinero ve el nombre de su marca).
create function core.visible_brand_ids(p_permission text)
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
    join org.brands b
      on b.group_id = g.group_id
     and (g.scope_type = 'group' or b.id = g.brand_id);
end
$$;
comment on function core.visible_brand_ids(text) is
  'Solo para lectura: marcas que se cruzan con algún alcance en el que la sesión tiene el permiso. Nunca para autorizar un cambio.';

-- Personas que la sesión puede ver: a sí misma; con users.view, a quienes tienen una asignación
-- vigente dentro de ese alcance, y con users.view de grupo, a todos los miembros del grupo.
create function core.visible_user_ids()
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
  select m.user_id
    from core.actor_grants('users.view') g
    join core.user_memberships m on m.group_id = g.group_id and m.deleted_at is null
   where g.scope_type = 'group';
end
$$;
comment on function core.visible_user_ids() is
  'Personas que la sesión puede ver: a sí misma, y con users.view a quienes tienen una asignación vigente dentro de ese alcance (o a todo el grupo, si el permiso es de grupo).';

-- Asignaciones que la sesión puede ver: las propias y, con users.view, las que caen dentro de ese alcance.
create function core.visible_assignment_ids()
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
  select a.id from core.user_role_assignments a where a.user_id = v_actor
  union
  select a.id
    from core.actor_grants('users.view') g
    join core.user_role_assignments a
      on a.group_id = g.group_id
     and (g.scope_type = 'group'
          or (g.scope_type = 'brand' and a.scope_type in ('brand', 'restaurant') and a.brand_id = g.brand_id)
          or (g.scope_type = 'restaurant' and a.scope_type = 'restaurant' and a.restaurant_id = g.restaurant_id));
end
$$;
comment on function core.visible_assignment_ids() is
  'Asignaciones que la sesión puede ver: las propias, y con users.view las que caen dentro de ese alcance (vigentes o no, para el historial).';

-- ¿Puede la sesión ver a esta persona? (para la interfaz; las políticas usan el conjunto).
create function core.can_view_user(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return p_user_id is not null and p_user_id in (select core.visible_user_ids());
end
$$;
comment on function core.can_view_user(uuid) is
  'Si la sesión puede ver a una persona: a sí misma, o con users.view sobre alguna de sus asignaciones vigentes o sobre su grupo.';

-- Roles vigentes de un actor, para la auditoría (actor_roles).
create function core.actor_roles_snapshot(p_actor_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_agg(jsonb_build_object(
           'role', r.code, 'scope_type', a.scope_type, 'group_id', a.group_id,
           'brand_id', a.brand_id, 'restaurant_id', a.restaurant_id)
         order by r.level, a.scope_type, a.brand_id, a.restaurant_id)
    from core.user_role_assignments a
    join core.roles r on r.id = a.role_id and r.deleted_at is null
   where a.user_id = p_actor_id
     and a.deleted_at is null
     and core.is_assignment_current(a.valid_from, a.valid_until)
$$;
comment on function core.actor_roles_snapshot(uuid) is 'Roles vigentes de un actor con su alcance, en jsonb. Lo usa la auditoría para guardar con qué roles se hizo cada cambio.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'core.current_aal()', 'core.is_assignment_current(timestamptz, timestamptz)', 'core.current_session_ok()',
    'core.actor_grants(text)', 'core.has_permission_for_scope(text, core.scope_type, uuid, uuid, uuid)',
    'core.has_permission(text, uuid)', 'core.has_permission_in_brand(text, uuid)',
    'core.has_permission_in_group(text, uuid)', 'core.has_permission_anywhere(text)',
    'core.can_view_scope(text, core.scope_type, uuid, uuid, uuid)', 'core.can_view_user(uuid)',
    'core.actor_roles_snapshot(uuid)', 'core.permitted_restaurant_ids(text)', 'core.visible_brand_ids(text)',
    'core.visible_user_ids()', 'core.visible_assignment_ids()'
  ] loop
    execute format('revoke execute on function %s from public', f);
  end loop;
end
$$;

grant execute on function core.actor_roles_snapshot(uuid) to audit_owner;

-- ---------------------------------------------------------------------------
-- 6. Auditoría: guarda los roles vigentes de quien hizo el cambio (pendiente desde M2).
--    Mismo cuerpo que en M3, más actor_roles.
-- ---------------------------------------------------------------------------
set role audit_owner;

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
  v_jwt_role   text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role';
  v_origin_raw text := nullif(current_setting('app.origin', true), '');
  v_origin     audit.change_origin;
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

  if v_origin_raw is not null
     and v_origin_raw = any (enum_range(null::audit.change_origin)::text[]) then
    v_origin := v_origin_raw::audit.change_origin;
  end if;

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
    actor_id, actor_type, actor_subject, jwt_role, actor_roles,
    scope_group_id, scope_brand_id, scope_restaurant_id,
    schema_name, table_name, record_id, action,
    old_values, new_values, changed_fields,
    reason, origin
  ) values (
    v_actor_id,
    v_actor_type,
    case when v_actor_id is null then v_subject end,
    v_jwt_role,
    case when v_actor_id is not null then core.actor_roles_snapshot(v_actor_id) end,
    v_group,
    v_brand,
    v_restaurant,
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

reset role;

-- ---------------------------------------------------------------------------
-- 7. Lectura por la API (ADR-0005): solo authenticated, nunca anon. Solo SELECT:
--    toda escritura va por las funciones de la sección 8 (y de M6 a M8).
-- ---------------------------------------------------------------------------
grant usage on schema core, org to authenticated;

grant select on org.groups, org.brands, org.restaurants, org.areas, org.time_zones to authenticated;
grant select on core.user_profiles, core.user_memberships, core.user_role_assignments,
                core.roles, core.permissions, core.role_permissions to authenticated;

-- Las políticas de tablas que crecen usan las versiones "de conjunto" (sección 5b): se calculan
-- una vez por consulta. Los grupos son pocos: ahí alcanza con la función por fila.
create policy groups_select on org.groups for select to authenticated
  using (core.can_view_scope('org.view', 'group', id));
create policy brands_select on org.brands for select to authenticated
  using (id in (select core.visible_brand_ids('org.view')));
create policy restaurants_select on org.restaurants for select to authenticated
  using (id in (select core.permitted_restaurant_ids('org.view')));
create policy areas_select on org.areas for select to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('org.view')));
create policy time_zones_select on org.time_zones for select to authenticated
  using ((select core.current_session_ok()));

create policy user_profiles_select on core.user_profiles for select to authenticated
  using (id in (select core.visible_user_ids()));
create policy user_memberships_select on core.user_memberships for select to authenticated
  using (user_id in (select core.visible_user_ids()));
create policy user_role_assignments_select on core.user_role_assignments for select to authenticated
  using (id in (select core.visible_assignment_ids()));
-- El catálogo de roles y permisos lo ve cualquier persona que pueda operar.
create policy roles_select on core.roles for select to authenticated
  using ((select core.current_session_ok()));
create policy permissions_select on core.permissions for select to authenticated
  using ((select core.current_session_ok()));
create policy role_permissions_select on core.role_permissions for select to authenticated
  using ((select core.current_session_ok()));

-- Las funciones que la interfaz y las políticas necesitan.
grant execute on function core.current_aal() to authenticated;
grant execute on function core.is_assignment_current(timestamptz, timestamptz) to authenticated;
grant execute on function core.current_session_ok() to authenticated;
grant execute on function core.has_permission_for_scope(text, core.scope_type, uuid, uuid, uuid) to authenticated;
grant execute on function core.has_permission(text, uuid) to authenticated;
grant execute on function core.has_permission_in_brand(text, uuid) to authenticated;
grant execute on function core.has_permission_in_group(text, uuid) to authenticated;
grant execute on function core.has_permission_anywhere(text) to authenticated;
grant execute on function core.can_view_scope(text, core.scope_type, uuid, uuid, uuid) to authenticated;
grant execute on function core.can_view_user(uuid) to authenticated;
grant execute on function core.permitted_restaurant_ids(text) to authenticated;
grant execute on function core.visible_brand_ids(text) to authenticated;
grant execute on function core.visible_user_ids() to authenticated;
grant execute on function core.visible_assignment_ids() to authenticated;
-- Solo devuelven el sub del JWT propio: las políticas los usan (por ejemplo, "lo que pedí yo").
grant execute on function core.current_actor_subject() to authenticated;
grant execute on function core.current_actor_id() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Escrituras de la estructura, solo por funciones (RPC). Cada una:
--    valida el permiso en la base, fija motivo y origen, y deja que los triggers
--    (columnas de control, jerarquía, auditoría) hagan el resto.
--    Crear, cerrar (status), borrar y restaurar piden org.manage en el nivel de arriba;
--    editar nombre y datos, en el propio nivel.
-- ---------------------------------------------------------------------------
create function org.require(p_allowed boolean, p_action text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not coalesce(p_allowed, false) then
    raise exception 'No tenés permiso para %.', p_action using errcode = '42501';
  end if;
end
$$;
comment on function org.require(boolean, text) is 'Interna: corta con "permiso denegado" (42501) si la condición no se cumple.';
revoke execute on function org.require(boolean, text) from public;

-- Solo estas claves se pueden cambiar en cada tabla. Una clave desconocida es un error.
create function org.check_keys(p_changes jsonb, p_allowed text[])
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_unknown text[];
begin
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'Los cambios tienen que ser un objeto con los campos a cambiar.' using errcode = '22023';
  end if;
  select array_agg(k) into v_unknown from jsonb_object_keys(p_changes) as k where not k = any (p_allowed);
  if v_unknown is not null then
    raise exception 'Campos que no se pueden cambiar acá: %.', array_to_string(v_unknown, ', ') using errcode = '22023';
  end if;
end
$$;
comment on function org.check_keys(jsonb, text[]) is 'Interna: valida que los cambios pedidos solo toquen campos permitidos.';
revoke execute on function org.check_keys(jsonb, text[]) from public;

create function org.update_group(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission_in_group('org.manage', p_id), 'editar el grupo');
  perform org.check_keys(p_changes, array['name']);
  perform core.set_change_context(p_reason, 'app');
  update org.groups
     set name = coalesce(btrim(p_changes ->> 'name'), name)
   where id = p_id;
end
$$;
comment on function org.update_group(uuid, jsonb, text) is 'Edita el nombre del grupo. Pide org.manage en el grupo y un motivo.';

create function org.create_brand(p_group_id uuid, p_name text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('org.manage', p_group_id), 'crear marcas en este grupo');
  perform core.set_change_context(p_reason, 'app');
  insert into org.brands (group_id, name) values (p_group_id, btrim(p_name)) returning id into v_id;
  return v_id;
end
$$;
comment on function org.create_brand(uuid, text, text) is 'Crea una marca. Pide org.manage en el grupo y un motivo.';

create function org.update_brand(p_id uuid, p_changes jsonb, p_reason text)
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
  perform org.check_keys(p_changes, array['name', 'status']);
  if p_changes ? 'status' then
    perform org.require(core.has_permission_in_group('org.manage', v_group), 'abrir o cerrar esta marca');
  end if;
  perform core.set_change_context(p_reason, 'app');
  update org.brands
     set name   = coalesce(btrim(p_changes ->> 'name'), name),
         status = coalesce((p_changes ->> 'status')::org.unit_status, status)
   where id = p_id;
end
$$;
comment on function org.update_brand(uuid, jsonb, text) is 'Edita una marca. Nombre: org.manage en la marca. Estado (cerrar o reabrir): org.manage en el grupo.';

create function org.create_restaurant(p_brand_id uuid, p_name text, p_details jsonb, p_reason text)
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
  perform core.set_change_context(p_reason, 'app');
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
comment on function org.create_restaurant(uuid, text, jsonb, text) is
  'Crea un local en una marca, con sus datos opcionales (P10). Pide org.manage en la marca y un motivo.';

create function org.update_restaurant(p_id uuid, p_changes jsonb, p_reason text)
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
  perform core.set_change_context(p_reason, 'app');
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
comment on function org.update_restaurant(uuid, jsonb, text) is
  'Edita un local. Nombre y datos: org.manage en el local. Estado (cerrar o reabrir): org.manage en la marca. Pide un motivo.';

create function org.create_area(p_restaurant_id uuid, p_name text, p_reason text)
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
  perform core.set_change_context(p_reason, 'app');
  insert into org.areas (group_id, restaurant_id, name) values (v_group, p_restaurant_id, btrim(p_name))
  returning id into v_id;
  return v_id;
end
$$;
comment on function org.create_area(uuid, text, text) is 'Crea un área en un local. Pide org.manage en el local y un motivo.';

create function org.update_area(p_id uuid, p_changes jsonb, p_reason text)
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
  perform core.set_change_context(p_reason, 'app');
  update org.areas set name = coalesce(btrim(p_changes ->> 'name'), name) where id = p_id;
end
$$;
comment on function org.update_area(uuid, jsonb, text) is 'Edita el nombre de un área. Pide org.manage en su local y un motivo.';

-- Borrado lógico y restauración: piden org.manage en el nivel de arriba (como crear).
create function org.set_deleted(p_table text, p_id uuid, p_deleted boolean, p_reason text)
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
  perform core.set_change_context(p_reason, 'app');
  execute format('update org.%I set deleted_at = case when $1 then now() end where id = $2', p_table)
    using p_deleted, p_id;
end
$$;
comment on function org.set_deleted(text, uuid, boolean, text) is
  'Borra (lógicamente) o restaura una marca, un local o un área. Pide org.manage en el nivel de arriba y un motivo. Las reglas de la jerarquía siguen valiendo.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'org.update_group(uuid, jsonb, text)', 'org.create_brand(uuid, text, text)', 'org.update_brand(uuid, jsonb, text)',
    'org.create_restaurant(uuid, text, jsonb, text)', 'org.update_restaurant(uuid, jsonb, text)',
    'org.create_area(uuid, text, text)', 'org.update_area(uuid, jsonb, text)',
    'org.set_deleted(text, uuid, boolean, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
