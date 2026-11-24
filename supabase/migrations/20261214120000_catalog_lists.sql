-- Listas de la cocina (Tanda 2 de Soy, PR A; ADR-0063): sectores, partidas, equipos y medidas prácticas del grupo, que hoy
-- son texto libre en la receta. Se editan en Configuración del catálogo, con motivo. Dar de baja no borra.
--   * Las lee quien ve el catálogo o las recetas. Las edita quien administra el catálogo (catalog.manage) o las
--     categorías de recetas (recipes.manage_categories), para todo el grupo: no hay permisos nuevos.
--   * Nada se escribe directo: solo con catalog.save_settings_list.
--   * Nacen solo con lo que nombró Soy (catalog.install_default_lists).

create type catalog.settings_list as enum
  ('ingredient_categories', 'recipe_categories', 'sectors', 'stations', 'equipment', 'measures', 'units', 'processes');
comment on type catalog.settings_list is
  'Las listas de Configuración del catálogo: categorías de materias primas y de recetas, sectores, partidas, equipos, medidas prácticas, unidades de medida y procesos de rendimiento.';

-- El nombre para comparar: sin mayúsculas, tildes ni espacios de más.
create function catalog.list_key(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select catalog.category_match_name(regexp_replace(replace(p_name, chr(160), ' '), '\s+', ' ', 'g'))
$$;
comment on function catalog.list_key(text) is
  'Interna: un nombre para comparar, sin mayúsculas, tildes ni espacios de más. Dos elementos de una lista no pueden tener el mismo.';
revoke execute on function catalog.list_key(text) from public;

-- ---------------------------------------------------------------------------
-- 1. Tablas
-- ---------------------------------------------------------------------------
create table catalog.kitchen_sectors (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references org.groups (id) on delete restrict,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint kitchen_sectors_name_check check (length(btrim(name)) between 1 and 60 and name !~ '[<>]'),
  constraint kitchen_sectors_id_group_key unique (id, group_id)
);
create index kitchen_sectors_group_idx on catalog.kitchen_sectors (group_id);
create unique index kitchen_sectors_name_key on catalog.kitchen_sectors (group_id, catalog.list_key(name)) where deleted_at is null;
comment on table catalog.kitchen_sectors is
  'Sectores de la cocina del grupo (cocina caliente, cocina fría, pastelería). Se eligen en la receta.';

create table catalog.kitchen_stations (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references org.groups (id) on delete restrict,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint kitchen_stations_name_check check (length(btrim(name)) between 1 and 60 and name !~ '[<>]'),
  constraint kitchen_stations_id_group_key unique (id, group_id)
);
create index kitchen_stations_group_idx on catalog.kitchen_stations (group_id);
create unique index kitchen_stations_name_key on catalog.kitchen_stations (group_id, catalog.list_key(name)) where deleted_at is null;
comment on table catalog.kitchen_stations is
  'Partidas de la cocina del grupo (pastas, salsas, parrilla). Se eligen en la receta.';

create table catalog.kitchen_equipment (
  id                uuid primary key default gen_random_uuid(),
  group_id          uuid not null references org.groups (id) on delete restrict,
  name              text not null,
  capacity          numeric(18,6),
  capacity_unit_id  uuid references catalog.units (id) on delete restrict,
  capacity_label    text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  created_by        uuid references core.actors (id) on delete restrict,
  updated_at        timestamptz not null default now(),
  updated_by        uuid references core.actors (id) on delete restrict,
  deleted_at        timestamptz,
  deleted_by        uuid references core.actors (id) on delete restrict,
  constraint kitchen_equipment_name_check check (length(btrim(name)) between 1 and 120 and name !~ '[<>]'),
  constraint kitchen_equipment_capacity_check check (capacity > 0 and capacity < 1000000000 and capacity <> 'NaN'),
  constraint kitchen_equipment_label_check check (length(btrim(capacity_label)) between 1 and 40 and capacity_label !~ '[<>]'),
  -- Sin capacidad no hay unidad; con capacidad, una sola de las dos formas.
  constraint kitchen_equipment_capacity_form check (
    (capacity is null and capacity_unit_id is null and capacity_label is null)
    or (capacity is not null and (capacity_unit_id is null) <> (capacity_label is null))),
  constraint kitchen_equipment_id_group_key unique (id, group_id)
);
create index kitchen_equipment_group_idx on catalog.kitchen_equipment (group_id);
create index kitchen_equipment_unit_idx on catalog.kitchen_equipment (capacity_unit_id) where capacity_unit_id is not null;
create unique index kitchen_equipment_name_key on catalog.kitchen_equipment (group_id, catalog.list_key(name)) where deleted_at is null;
comment on table catalog.kitchen_equipment is
  'Equipos de la cocina del grupo (pastera, horno combi), con su capacidad. Se eligen en los pasos de la receta.';
comment on column catalog.kitchen_equipment.capacity is 'Cuánto entra en el equipo. Vacío = sin cargar.';
comment on column catalog.kitchen_equipment.capacity_unit_id is
  'Unidad del sistema de la capacidad (kg, l, porción): con ella se calculan las tandas. Vacía si la capacidad va en palabras.';
comment on column catalog.kitchen_equipment.capacity_label is
  'La capacidad en palabras, cuando no es una unidad del sistema (canastos, bandejas GN 1/1): se muestra y no entra en la cuenta de tandas.';

create table catalog.practical_measures (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references org.groups (id) on delete restrict,
  name             text not null,
  content          numeric(18,6) not null,
  content_unit_id  uuid not null references catalog.units (id) on delete restrict,
  usage_note       text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references core.actors (id) on delete restrict,
  deleted_at       timestamptz,
  deleted_by       uuid references core.actors (id) on delete restrict,
  constraint practical_measures_name_check check (length(btrim(name)) between 1 and 60 and name !~ '[<>]'),
  constraint practical_measures_content_check check (content > 0 and content < 1000000 and content <> 'NaN'),
  constraint practical_measures_note_check check (length(btrim(usage_note)) between 1 and 120 and usage_note !~ '[<>]'),
  constraint practical_measures_id_group_key unique (id, group_id)
);
create index practical_measures_group_idx on catalog.practical_measures (group_id);
create index practical_measures_unit_idx on catalog.practical_measures (content_unit_id);
create unique index practical_measures_name_key on catalog.practical_measures (group_id, catalog.list_key(name)) where deleted_at is null;
comment on table catalog.practical_measures is
  'Medidas prácticas del grupo: lo que usa el cocinero en vez de pesar (cucharón, taza, nido), con lo que contiene cada una.';
comment on column catalog.practical_measures.content is 'Cuánto contiene, en su unidad base.';
comment on column catalog.practical_measures.content_unit_id is 'Unidad base de lo que contiene: ml, g o unidad.';
comment on column catalog.practical_measures.usage_note is 'Con qué se usa (salsas, sopas, cremas). Opcional.';

-- Lo igual en las cuatro: comentarios, triggers, RLS y lectura.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['kitchen_sectors', 'kitchen_stations', 'kitchen_equipment', 'practical_measures'] loop
    execute format('comment on column catalog.%I.id is %L', v_table, 'Identificador. No cambia nunca.');
    execute format('comment on column catalog.%I.group_id is %L', v_table, 'Grupo al que pertenece.');
    execute format('comment on column catalog.%I.name is %L', v_table,
                   'Nombre. Único en el grupo, sin distinguir mayúsculas, tildes ni espacios de más.');
    execute format('comment on column catalog.%I.is_active is %L', v_table,
                   'Si se ofrece para elegir. Inactivo no se borra: lo que ya lo usa no cambia, y se puede reactivar.');
    execute format('comment on column catalog.%I.created_at is %L', v_table, 'Cuándo se creó.');
    execute format('comment on column catalog.%I.created_by is %L', v_table, 'Quién lo creó.');
    execute format('comment on column catalog.%I.updated_at is %L', v_table, 'Cuándo cambió por última vez.');
    execute format('comment on column catalog.%I.updated_by is %L', v_table, 'Quién lo cambió por última vez.');
    execute format('comment on column catalog.%I.deleted_at is %L', v_table, 'Baja lógica: cuándo.');
    execute format('comment on column catalog.%I.deleted_by is %L', v_table, 'Baja lógica: quién.');

    execute format('create trigger set_control_columns before insert or update on catalog.%I for each row execute function core.set_control_columns()', v_table);
    execute format('create trigger log_change after insert or update or delete on catalog.%I for each row execute function audit.log_change()', v_table);
    execute format('create trigger reject_truncate before truncate on catalog.%I for each statement execute function core.reject_truncate()', v_table);

    execute format('alter table catalog.%I enable row level security', v_table);
    execute format('create policy %I on catalog.%I for select to authenticated using (deleted_at is null and (group_id in (select core.visible_group_ids(%L)) or group_id in (select core.visible_group_ids(%L))))',
                   v_table || '_select', v_table, 'catalog.view', 'recipes.view');
    execute format('grant select on catalog.%I to authenticated', v_table);
  end loop;
end
$$;

-- El nombre entra limpio: sin espacios de más ni caracteres que no se ven (imitan a otro o saltean el control de repetidos).
create function catalog.clean_list_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.name := btrim(regexp_replace(replace(new.name, chr(160), ' '), '\s+', ' ', 'g'));
  if core.has_hidden_characters(new.name) then
    raise exception 'El nombre tiene caracteres que no se ven: escribilo de nuevo.' using errcode = '22023';
  end if;
  if tg_table_name = 'kitchen_equipment' then
    new.capacity_label := nullif(btrim(regexp_replace(replace(new.capacity_label, chr(160), ' '), '\s+', ' ', 'g')), '');
    if core.has_hidden_characters(new.capacity_label) then
      raise exception 'La capacidad tiene caracteres que no se ven: escribila de nuevo.' using errcode = '22023';
    end if;
    -- En una unidad del sistema: vigente y que no sea un envase (no tiene contenido fijo).
    if new.capacity_unit_id is not null
       and (tg_op = 'INSERT' or new.capacity_unit_id is distinct from old.capacity_unit_id)
       and not exists (select 1 from catalog.units
                        where id = new.capacity_unit_id and deleted_at is null and dimension <> 'package') then
      raise exception 'La capacidad del equipo va en una unidad de peso, volumen o unidades, o en palabras.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'practical_measures' then
    new.usage_note := nullif(btrim(regexp_replace(replace(new.usage_note, chr(160), ' '), '\s+', ' ', 'g')), '');
    if core.has_hidden_characters(new.usage_note) then
      raise exception '«Se usa con» tiene caracteres que no se ven: escribilo de nuevo.' using errcode = '22023';
    end if;
    -- En una unidad base: así la cuenta de la receta no pasa por conversiones.
    if (tg_op = 'INSERT' or new.content_unit_id is distinct from old.content_unit_id)
       and not exists (select 1 from catalog.units where id = new.content_unit_id and is_base and deleted_at is null) then
      raise exception 'Lo que contiene la medida va en ml, g o unidades.' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.clean_list_item() is
  'Trigger de las listas de la cocina: limpia el nombre y controla la unidad de la capacidad (equipo) y del contenido (medida práctica).';
revoke execute on function catalog.clean_list_item() from public;
create trigger clean_list_item before insert or update on catalog.kitchen_sectors
  for each row execute function catalog.clean_list_item();
create trigger clean_list_item before insert or update on catalog.kitchen_stations
  for each row execute function catalog.clean_list_item();
create trigger clean_list_item before insert or update on catalog.kitchen_equipment
  for each row execute function catalog.clean_list_item();
create trigger clean_list_item before insert or update on catalog.practical_measures
  for each row execute function catalog.clean_list_item();

-- La equivalencia de una unidad es un número de verdad: en numeric, NaN > 0 es verdadero y contaminaría los costos.
alter table catalog.unit_conversions
  add constraint unit_conversions_factor_number check (factor <> 'NaN' and factor < 1000000000);

-- ---------------------------------------------------------------------------
-- 2. Quién edita cada lista, en un solo lugar
-- ---------------------------------------------------------------------------
create function catalog.can_manage_list(p_list catalog.settings_list, p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when p_list in ('ingredient_categories', 'units') then core.has_permission_in_group('catalog.manage', p_group_id)
           when p_list = 'recipe_categories' then core.has_permission_in_group('recipes.draft', p_group_id)
           when p_list = 'processes' then core.has_permission_in_group('yields.approve', p_group_id)
           else core.has_permission_in_group('catalog.manage', p_group_id)
             or core.has_permission_in_group('recipes.manage_categories', p_group_id)
         end
$$;
comment on function catalog.can_manage_list(catalog.settings_list, uuid) is
  'Interna: si la sesión edita una lista del catálogo, para todo el grupo. Categorías de materias primas y unidades: catalog.manage. Categorías de recetas: recipes.draft. Procesos: yields.approve. Sectores, partidas, equipos y medidas prácticas: catalog.manage o recipes.manage_categories.';
revoke execute on function catalog.can_manage_list(catalog.settings_list, uuid) from public;

create function catalog.can_see_lists(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from unnest(enum_range(null::catalog.settings_list)) l where catalog.can_manage_list(l, p_group_id))
$$;
comment on function catalog.can_see_lists(uuid) is
  'Interna: si la sesión entra a Configuración del catálogo del grupo (administra al menos una lista). Las demás las ve en lectura.';
revoke execute on function catalog.can_see_lists(uuid) from public;

-- ---------------------------------------------------------------------------
-- 3. Con qué nacen: solo lo que nombró Soy (prompt de la Tanda 2). El resto lo agregan desde la pantalla.
-- ---------------------------------------------------------------------------
create function catalog.install_default_lists(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into catalog.kitchen_sectors (group_id, name)
  select p_group_id, n from unnest(array['Cocina caliente', 'Cocina fría', 'Pastelería']) n
   where not exists (select 1 from catalog.kitchen_sectors s where s.group_id = p_group_id and s.deleted_at is null
                        and catalog.list_key(s.name) = catalog.list_key(n));
  insert into catalog.kitchen_stations (group_id, name)
  select p_group_id, n from unnest(array['Pastas', 'Salsas', 'Parrilla']) n
   where not exists (select 1 from catalog.kitchen_stations s where s.group_id = p_group_id and s.deleted_at is null
                        and catalog.list_key(s.name) = catalog.list_key(n));
  insert into catalog.kitchen_equipment (group_id, name, capacity, capacity_label)
  select p_group_id, v.name, v.capacity, v.label
    from (values ('Pastera', 6, 'canastos'), ('Horno combi', 10, 'bandejas GN 1/1')) v (name, capacity, label)
   where not exists (select 1 from catalog.kitchen_equipment e where e.group_id = p_group_id and e.deleted_at is null
                        and catalog.list_key(e.name) = catalog.list_key(v.name));
  insert into catalog.practical_measures (group_id, name, content, content_unit_id)
  select p_group_id, v.name, v.content, u.id
    from (values ('Cucharón', 120, 'ml'), ('Taza', 240, 'ml'), ('Cucharada', 15, 'ml'), ('Cucharadita', 5, 'ml'),
                 ('Nido de pasta', 120, 'g')) v (name, content, unit)
    join catalog.units u on u.code = v.unit and u.deleted_at is null
   where not exists (select 1 from catalog.practical_measures m where m.group_id = p_group_id and m.deleted_at is null
                        and catalog.list_key(m.name) = catalog.list_key(v.name));
end
$$;
comment on function catalog.install_default_lists(uuid) is
  'Interna: carga en un grupo los sectores, partidas, equipos y medidas prácticas que nombró Soy, si no están. Se puede repetir. Un grupo nuevo la necesita en su alta, como recipes.install_default_categories.';
revoke execute on function catalog.install_default_lists(uuid) from public;

do $$
begin
  perform core.set_change_context('Sectores, partidas, equipos y medidas prácticas con los que nace el grupo (ADR-0063)', 'maintenance');
  perform catalog.install_default_lists(id) from org.groups where deleted_at is null;
end
$$;
