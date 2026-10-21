-- Fase 1 · M3 — Estructura del grupo: grupos, marcas, restaurantes y áreas
-- (docs/fases/fase-1-plan.md, ADR-0005).
-- Las tablas nacen cerradas: RLS activado, sin políticas y sin GRANT para la API.
-- Las políticas con has_permission llegan en M5 (ADR-0005).
-- Solo los datos mínimos: dirección, CUIT, código de marca o zona horaria se suman
-- cuando Soy los confirme (P10), con una migración nueva.

-- ---------------------------------------------------------------------------
-- 1. Estado de una unidad (propuesta, a confirmar con Soy: P14).
--    inactive = cerrada pero visible en la historia. Borrar (deleted_at) es otra cosa:
--    corregir un error de carga.
-- ---------------------------------------------------------------------------
create type org.unit_status as enum ('active', 'inactive');
comment on type org.unit_status is
  'Estado de un grupo, marca o restaurante: active (operando) o inactive (cerrado, pero visible en la historia). Borrar un registro es otra cosa: corrige un error de carga.';

-- ---------------------------------------------------------------------------
-- 2. Grupos
-- ---------------------------------------------------------------------------
create table org.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(btrim(name)) between 1 and 120),
  status      org.unit_status not null default 'active',
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict
);

comment on table org.groups is 'Grupo gastronómico: el nivel más alto de la organización (por ejemplo, Grupo LF). Preparado para más de uno.';
comment on column org.groups.id is 'Identificador del grupo.';
comment on column org.groups.name is 'Nombre del grupo. Único entre los grupos vigentes, sin importar mayúsculas.';
comment on column org.groups.status is 'Si el grupo está operando o cerrado.';
comment on column org.groups.created_at is 'Cuándo se creó (lo pone la base).';
comment on column org.groups.created_by is 'Quién lo creó (lo pone la base).';
comment on column org.groups.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column org.groups.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column org.groups.deleted_at is 'Cuándo se borró (borrado lógico). Vacío si está vigente.';
comment on column org.groups.deleted_by is 'Quién lo borró (lo pone la base).';

create unique index groups_name_key on org.groups (lower(name)) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. Marcas
-- ---------------------------------------------------------------------------
create table org.brands (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references org.groups (id) on delete restrict,
  name        text not null check (length(btrim(name)) between 1 and 120),
  status      org.unit_status not null default 'active',
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  -- Permite que restaurantes y otras tablas exijan "esta marca es de este grupo".
  constraint brands_id_group_key unique (id, group_id)
);

comment on table org.brands is 'Marca del grupo (por ejemplo, RAGU). Tiene sus recetas estándar, precios y reportes.';
comment on column org.brands.id is 'Identificador de la marca.';
comment on column org.brands.group_id is 'Grupo al que pertenece la marca.';
comment on column org.brands.name is 'Nombre de la marca. Único dentro del grupo entre las vigentes, sin importar mayúsculas.';
comment on column org.brands.status is 'Si la marca está operando o cerrada.';
comment on column org.brands.created_at is 'Cuándo se creó (lo pone la base).';
comment on column org.brands.created_by is 'Quién la creó (lo pone la base).';
comment on column org.brands.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column org.brands.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column org.brands.deleted_at is 'Cuándo se borró (borrado lógico). Vacío si está vigente.';
comment on column org.brands.deleted_by is 'Quién la borró (lo pone la base).';

create index brands_group_idx on org.brands (group_id);
create unique index brands_name_key on org.brands (group_id, lower(name)) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 4. Restaurantes
-- ---------------------------------------------------------------------------
create table org.restaurants (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references org.groups (id) on delete restrict,
  brand_id    uuid not null,
  name        text not null check (length(btrim(name)) between 1 and 120),
  status      org.unit_status not null default 'active',
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  -- La marca tiene que ser del mismo grupo (alcance consistente por estructura).
  constraint restaurants_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  constraint restaurants_id_group_key unique (id, group_id)
);

comment on table org.restaurants is 'Restaurante (local) de una marca (por ejemplo, RAGU Parque Leloir). Es donde pasa la operación diaria.';
comment on column org.restaurants.id is 'Identificador del restaurante.';
comment on column org.restaurants.group_id is 'Grupo al que pertenece. Tiene que coincidir con el de su marca.';
comment on column org.restaurants.brand_id is 'Marca del restaurante.';
comment on column org.restaurants.name is 'Nombre del restaurante. Único dentro de la marca entre los vigentes, sin importar mayúsculas.';
comment on column org.restaurants.status is 'Si el restaurante está operando o cerrado.';
comment on column org.restaurants.created_at is 'Cuándo se creó (lo pone la base).';
comment on column org.restaurants.created_by is 'Quién lo creó (lo pone la base).';
comment on column org.restaurants.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column org.restaurants.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column org.restaurants.deleted_at is 'Cuándo se borró (borrado lógico). Vacío si está vigente.';
comment on column org.restaurants.deleted_by is 'Quién lo borró (lo pone la base).';

create index restaurants_group_idx on org.restaurants (group_id);
create index restaurants_brand_idx on org.restaurants (brand_id, group_id);
create unique index restaurants_name_key on org.restaurants (brand_id, lower(name)) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 5. Áreas de un restaurante (por ejemplo, cocina, salón, depósito)
-- ---------------------------------------------------------------------------
create table org.areas (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  restaurant_id  uuid not null,
  name           text not null check (length(btrim(name)) between 1 and 120),
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  -- El restaurante tiene que ser del mismo grupo.
  constraint areas_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  -- Para que tablas futuras (stock, producción) puedan exigir "esta área es de este grupo".
  constraint areas_id_group_key unique (id, group_id)
);

comment on table org.areas is 'Área de trabajo dentro de un restaurante (por ejemplo, cocina, salón o depósito).';
comment on column org.areas.id is 'Identificador del área.';
comment on column org.areas.group_id is 'Grupo al que pertenece. Tiene que coincidir con el de su restaurante.';
comment on column org.areas.restaurant_id is 'Restaurante al que pertenece el área.';
comment on column org.areas.name is 'Nombre del área. Único dentro del restaurante entre las vigentes, sin importar mayúsculas.';
comment on column org.areas.created_at is 'Cuándo se creó (lo pone la base).';
comment on column org.areas.created_by is 'Quién la creó (lo pone la base).';
comment on column org.areas.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column org.areas.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column org.areas.deleted_at is 'Cuándo se borró (borrado lógico). Vacío si está vigente.';
comment on column org.areas.deleted_by is 'Quién la borró (lo pone la base).';

create index areas_group_idx on org.areas (group_id);
create index areas_restaurant_idx on org.areas (restaurant_id, group_id);
create unique index areas_name_key on org.areas (restaurant_id, lower(name)) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 6. Reglas de la jerarquía (decididas por Joaco el 2026-10-20)
--    a) No se borra (ni se cierra el alta bajo) algo que tiene hijos vigentes:
--       - no se puede borrar un grupo, marca o restaurante con hijos vigentes;
--       - no se puede dar de alta ni restaurar algo bajo un padre borrado.
--    b) El alcance no se mueve con una edición común: el grupo de una marca y la
--       marca/grupo de un restaurante o área no cambian. Mover tendrá un trámite
--       propio (función con motivo y permiso, M5), que se habilita en una migración nueva.
-- ---------------------------------------------------------------------------
create function org.enforce_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_deleted boolean := false;
  v_has_children   boolean := false;
  v_moved          boolean := false;
  v_becomes_active boolean;
  v_becomes_deleted boolean;
begin
  if tg_when <> 'BEFORE' or tg_level <> 'ROW' or tg_op not in ('INSERT', 'UPDATE') then
    raise exception 'org.enforce_hierarchy() se conecta como BEFORE INSERT OR UPDATE ... FOR EACH ROW.';
  end if;

  -- (Cada tabla en su propio IF: plpgsql no deja nombrar columnas que la tabla no tiene.)

  -- b) El alcance es inmutable.
  if tg_op = 'UPDATE' then
    if tg_table_name = 'brands' then
      v_moved := new.group_id is distinct from old.group_id;
    elsif tg_table_name = 'restaurants' then
      v_moved := new.group_id is distinct from old.group_id or new.brand_id is distinct from old.brand_id;
    elsif tg_table_name = 'areas' then
      v_moved := new.group_id is distinct from old.group_id or new.restaurant_id is distinct from old.restaurant_id;
    end if;
    if v_moved then
      raise exception 'No se puede mover % de grupo, marca o restaurante con una edición común. Hace falta el trámite de traspaso (pendiente, M5).',
        tg_table_name
        using errcode = '42501';
    end if;
  end if;

  v_becomes_active := new.deleted_at is null and (tg_op = 'INSERT' or old.deleted_at is not null);
  v_becomes_deleted := tg_op = 'UPDATE' and old.deleted_at is null and new.deleted_at is not null;

  -- a) Alta o restauración bajo un padre borrado.
  if v_becomes_active then
    if tg_table_name = 'brands' then
      v_parent_deleted := exists (select 1 from org.groups p where p.id = new.group_id and p.deleted_at is not null);
    elsif tg_table_name = 'restaurants' then
      v_parent_deleted := exists (select 1 from org.brands p where p.id = new.brand_id and p.deleted_at is not null);
    elsif tg_table_name = 'areas' then
      v_parent_deleted := exists (select 1 from org.restaurants p where p.id = new.restaurant_id and p.deleted_at is not null);
    end if;
    if v_parent_deleted then
      raise exception 'No se puede dar de alta ni restaurar % dentro de algo que está borrado.', tg_table_name
        using errcode = '23514';
    end if;
  end if;

  -- a) Borrado con hijos vigentes.
  if v_becomes_deleted then
    if tg_table_name = 'groups' then
      v_has_children := exists (select 1 from org.brands c where c.group_id = new.id and c.deleted_at is null);
    elsif tg_table_name = 'brands' then
      v_has_children := exists (select 1 from org.restaurants c where c.brand_id = new.id and c.deleted_at is null);
    elsif tg_table_name = 'restaurants' then
      v_has_children := exists (select 1 from org.areas c where c.restaurant_id = new.id and c.deleted_at is null);
    end if;
    if v_has_children then
      raise exception 'No se puede borrar % mientras tenga elementos vigentes adentro. Primero hay que borrarlos.', tg_table_name
        using errcode = '23514';
    end if;
  end if;

  return new;
end
$$;
comment on function org.enforce_hierarchy() is
  'Trigger BEFORE INSERT OR UPDATE en org.*: impide mover el alcance con una edición común, dar de alta bajo un padre borrado y borrar un padre con hijos vigentes.';

-- TRUNCATE no pasa por los triggers de fila: en tablas de negocio se rechaza siempre.
create function core.reject_truncate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'No se permite vaciar %.% (TRUNCATE): nada se borra en bloque.', tg_table_schema, tg_table_name
    using errcode = '42501';
end
$$;
comment on function core.reject_truncate() is 'Trigger BEFORE TRUNCATE: rechaza vaciar una tabla de negocio.';

-- ---------------------------------------------------------------------------
-- 7. Cerradas por defecto, con columnas de control, jerarquía y auditoría
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['groups', 'brands', 'restaurants', 'areas'] loop
    execute format('alter table org.%I enable row level security', t);
    execute format('revoke all on org.%I from public, anon, authenticated, service_role', t);
    execute format(
      'create trigger set_control_columns before insert or update on org.%I
         for each row execute function core.set_control_columns()', t);
    execute format(
      'create trigger validate_hierarchy before insert or update on org.%I
         for each row execute function org.enforce_hierarchy()', t);
    execute format(
      'create trigger log_change after insert or update or delete on org.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on org.%I
         for each statement execute function core.reject_truncate()', t);
  end loop;
end
$$;

-- La auditoría lee marcas y restaurantes para calcular el alcance real de cada evento.
grant usage on schema org to audit_owner;
grant select on org.brands, org.restaurants to audit_owner;
create policy brands_read_for_audit on org.brands for select to audit_owner using (true);
create policy restaurants_read_for_audit on org.restaurants for select to audit_owner using (true);

-- ---------------------------------------------------------------------------
-- 8. Supabase da por defecto DELETE y TRUNCATE a los roles de la API sobre toda tabla
--    que postgres cree en public. Se corta: nada nace abierto (ADR-0005).
-- ---------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

revoke execute on function org.enforce_hierarchy() from public;
revoke execute on function core.reject_truncate() from public;

-- ---------------------------------------------------------------------------
-- 9. Auditoría: alcance real de cada evento.
--    - En org, el alcance de una fila es su propio id (un restaurante es el restaurante).
--    - Si la fila tiene restaurant_id, la marca y el grupo salen de org.restaurants,
--      no de lo que diga la fila: así no se puede falsear el alcance y los eventos de
--      tablas con solo restaurant_id (áreas, stock...) también llevan su marca.
--    - Si tiene brand_id, el grupo sale de org.brands.
--    - Un valor que no es uuid no rompe la escritura: el alcance queda vacío.
--    Mismo cuerpo que en M2, salvo el cálculo de scope_*.
-- ---------------------------------------------------------------------------
set role audit_owner;

create function audit.try_uuid(p_value text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p_value::uuid
  end
$$;
comment on function audit.try_uuid(text) is 'Convierte un texto a uuid, o devuelve nulo si no es un uuid válido.';
revoke execute on function audit.try_uuid(text) from public;

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
