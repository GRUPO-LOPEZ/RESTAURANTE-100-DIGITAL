-- El sector, la partida y el equipo de las recetas pasan del texto libre a las listas del grupo (ADR-0063).
--   * La receta (sector y partida) y los pasos (sector y equipo) guardan además el elemento de la lista.
--   * El texto queda: es el nombre congelado de cada versión. Una versión en revisión, aprobada, publicada o archivada no se
--     toca nunca. La receta y los borradores siguen el nombre de la lista si cambia.
--   * Mientras la ficha mande texto (hasta el PR B), la base lo vincula si coincide con la lista; si no, queda como texto.

-- ---------------------------------------------------------------------------
-- 1. Columnas
-- ---------------------------------------------------------------------------
alter table recipes.recipes
  add column sector_id  uuid,
  add column station_id uuid,
  add constraint recipes_sector_fkey foreign key (sector_id, group_id)
    references catalog.kitchen_sectors (id, group_id) on delete restrict,
  add constraint recipes_station_fkey foreign key (station_id, group_id)
    references catalog.kitchen_stations (id, group_id) on delete restrict;
create index recipes_sector_idx on recipes.recipes (sector_id, group_id) where sector_id is not null;
create index recipes_station_idx on recipes.recipes (station_id, group_id) where station_id is not null;
comment on column recipes.recipes.sector_id is 'Sector de la lista del grupo. Vacío si el texto no está en la lista.';
comment on column recipes.recipes.station_id is 'Partida de la lista del grupo. Vacía si el texto no está en la lista.';
comment on column recipes.recipes.sector is
  'Sector de la cocina donde se prepara, en palabras. Si está en la lista (sector_id), sigue su nombre.';
comment on column recipes.recipes.station is
  'Partida o estación, en palabras. Si está en la lista (station_id), sigue su nombre.';

alter table recipes.recipe_steps
  add column sector_id    uuid,
  add column equipment_id uuid,
  add constraint recipe_steps_sector_fkey foreign key (sector_id, group_id)
    references catalog.kitchen_sectors (id, group_id) on delete restrict,
  add constraint recipe_steps_equipment_fkey foreign key (equipment_id, group_id)
    references catalog.kitchen_equipment (id, group_id) on delete restrict;
create index recipe_steps_sector_idx on recipes.recipe_steps (sector_id, group_id) where sector_id is not null;
create index recipe_steps_equipment_idx on recipes.recipe_steps (equipment_id, group_id) where equipment_id is not null;
comment on column recipes.recipe_steps.sector_id is
  'Sector de la lista del grupo. Vacío si el texto no está en la lista, o en las versiones anteriores a las listas.';
comment on column recipes.recipe_steps.equipment_id is
  'Equipo de la lista del grupo. Vacío si el texto no está en la lista, o en las versiones anteriores a las listas.';
comment on column recipes.recipe_steps.sector is
  'Sector de la cocina, en palabras. Queda congelado con la versión aunque la lista cambie.';
comment on column recipes.recipe_steps.equipment is
  'Equipo que se usa, en palabras. Queda congelado con la versión aunque la lista cambie.';

-- ---------------------------------------------------------------------------
-- 2. Del texto al elemento de la lista, y al revés
-- ---------------------------------------------------------------------------
create function catalog.list_item_id(p_list catalog.settings_list, p_group_id uuid, p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case p_list
           when 'sectors' then (select id from catalog.kitchen_sectors
                                 where group_id = p_group_id and deleted_at is null and catalog.list_key(name) = catalog.list_key(p_name))
           when 'stations' then (select id from catalog.kitchen_stations
                                  where group_id = p_group_id and deleted_at is null and catalog.list_key(name) = catalog.list_key(p_name))
           when 'equipment' then (select id from catalog.kitchen_equipment
                                   where group_id = p_group_id and deleted_at is null and catalog.list_key(name) = catalog.list_key(p_name))
         end
$$;
comment on function catalog.list_item_id(catalog.settings_list, uuid, text) is
  'Interna: el sector, la partida o el equipo del grupo con ese nombre (activo o no), sin distinguir mayúsculas, tildes ni espacios. Nulo si no está.';
revoke execute on function catalog.list_item_id(catalog.settings_list, uuid, text) from public;

create function catalog.list_item_name(p_list catalog.settings_list, p_group_id uuid, p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case p_list
           when 'sectors' then (select name from catalog.kitchen_sectors where id = p_id and group_id = p_group_id and deleted_at is null)
           when 'stations' then (select name from catalog.kitchen_stations where id = p_id and group_id = p_group_id and deleted_at is null)
           when 'equipment' then (select name from catalog.kitchen_equipment where id = p_id and group_id = p_group_id and deleted_at is null)
         end
$$;
comment on function catalog.list_item_name(catalog.settings_list, uuid, uuid) is
  'Interna: el nombre de un sector, partida o equipo del grupo. Nulo si no existe o es de otro grupo.';
revoke execute on function catalog.list_item_name(catalog.settings_list, uuid, uuid) from public;

-- Un par texto + elemento: si viene el elemento, el texto es su nombre; si cambia el texto, se busca el elemento.
create function recipes.link_list_pair(p_list catalog.settings_list, p_group_id uuid, p_insert boolean,
                                       p_old_text text, p_old_id uuid, inout p_text text, inout p_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_id is not null and (p_insert or p_id is distinct from p_old_id) then
    p_text := catalog.list_item_name(p_list, p_group_id, p_id);
    if p_text is null then
      raise exception 'Elegí un elemento de la lista del grupo.' using errcode = '22023';
    end if;
  elsif p_insert or p_text is distinct from p_old_text then
    p_id := case when p_text is null then null else catalog.list_item_id(p_list, p_group_id, p_text) end;
  elsif p_id is null and p_old_id is not null then
    p_text := null;
  end if;
end
$$;
comment on function recipes.link_list_pair(catalog.settings_list, uuid, boolean, text, uuid, text, uuid) is
  'Interna: mantiene juntos el texto y el elemento de la lista. Si viene un elemento nuevo, el texto es su nombre; si cambia el texto, busca el elemento; si se saca el elemento, se saca el texto.';
revoke execute on function recipes.link_list_pair(catalog.settings_list, uuid, boolean, text, uuid, text, uuid) from public;

create function recipes.link_lists()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_insert boolean := tg_op = 'INSERT';
  v_old    jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) else '{}'::jsonb end;
begin
  select p.p_text, p.p_id into new.sector, new.sector_id
    from recipes.link_list_pair('sectors', new.group_id, v_insert, v_old ->> 'sector', (v_old ->> 'sector_id')::uuid,
                                new.sector, new.sector_id) p;
  if tg_table_name = 'recipes' then
    select p.p_text, p.p_id into new.station, new.station_id
      from recipes.link_list_pair('stations', new.group_id, v_insert, v_old ->> 'station', (v_old ->> 'station_id')::uuid,
                                  new.station, new.station_id) p;
  else
    select p.p_text, p.p_id into new.equipment, new.equipment_id
      from recipes.link_list_pair('equipment', new.group_id, v_insert, v_old ->> 'equipment', (v_old ->> 'equipment_id')::uuid,
                                  new.equipment, new.equipment_id) p;
  end if;
  return new;
end
$$;
comment on function recipes.link_lists() is
  'Trigger de recetas y pasos: vincula el sector, la partida y el equipo con las listas del grupo.';
revoke execute on function recipes.link_lists() from public;
create trigger link_lists before insert or update of sector, sector_id, station, station_id on recipes.recipes
  for each row execute function recipes.link_lists();
create trigger link_lists before insert or update of sector, sector_id, equipment, equipment_id on recipes.recipe_steps
  for each row execute function recipes.link_lists();

-- Si la lista cambia el nombre, lo siguen la receta y los borradores. Lo que ya no es borrador conserva el suyo.
create function recipes.follow_list_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- En orden: dos cambios de nombre a la vez sobre las mismas recetas no se traban entre sí.
  perform 1 from recipes.recipes
   where deleted_at is null and (sector_id = new.id or station_id = new.id) order by id for update;
  if tg_table_name = 'kitchen_stations' then
    update recipes.recipes set station = new.name where station_id = new.id and deleted_at is null;
    return null;
  end if;
  if tg_table_name = 'kitchen_sectors' then
    update recipes.recipes set sector = new.name where sector_id = new.id and deleted_at is null;
    update recipes.recipe_steps s set sector = new.name
      from recipes.recipe_versions v
     where s.sector_id = new.id and s.deleted_at is null
       and v.id = s.recipe_version_id and v.status = 'draft' and v.deleted_at is null;
  else
    update recipes.recipe_steps s set equipment = new.name
      from recipes.recipe_versions v
     where s.equipment_id = new.id and s.deleted_at is null
       and v.id = s.recipe_version_id and v.status = 'draft' and v.deleted_at is null;
  end if;
  return null;
end
$$;
comment on function recipes.follow_list_name() is
  'Trigger de las listas: al cambiar el nombre de un sector, partida o equipo, lo siguen las recetas y los pasos en borrador. Las versiones que ya no son borrador conservan el texto.';
revoke execute on function recipes.follow_list_name() from public;
create trigger follow_list_name after update of name on catalog.kitchen_sectors
  for each row when (old.name is distinct from new.name) execute function recipes.follow_list_name();
create trigger follow_list_name after update of name on catalog.kitchen_stations
  for each row when (old.name is distinct from new.name) execute function recipes.follow_list_name();
create trigger follow_list_name after update of name on catalog.kitchen_equipment
  for each row when (old.name is distinct from new.name) execute function recipes.follow_list_name();

-- Una versión que vuelve a borrador (la devolvieron o la retiraron de revisión) toma los nombres de hoy.
create function recipes.refresh_list_names()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update recipes.recipe_steps s
     set sector = coalesce(k.name, s.sector), equipment = coalesce(e.name, s.equipment)
    from recipes.recipe_steps x
    left join catalog.kitchen_sectors k on k.id = x.sector_id
    left join catalog.kitchen_equipment e on e.id = x.equipment_id
   where x.id = s.id and s.recipe_version_id = new.id and s.deleted_at is null
     and ((k.name is not null and k.name is distinct from s.sector)
          or (e.name is not null and e.name is distinct from s.equipment));
  return null;
end
$$;
comment on function recipes.refresh_list_names() is
  'Trigger de las versiones: al volver a borrador, los pasos toman el nombre actual del sector y del equipo de la lista.';
revoke execute on function recipes.refresh_list_names() from public;
create trigger refresh_list_names after update of status on recipes.recipe_versions
  for each row when (new.status = 'draft' and old.status is distinct from 'draft') execute function recipes.refresh_list_names();

-- ---------------------------------------------------------------------------
-- 3. La copia de una versión lleva el elemento (si el nombre de la lista cambió, la copia lo actualiza). La variante copia
--    el sector y la partida de la maestra por el nombre, que siempre es el de la lista
-- ---------------------------------------------------------------------------
create or replace function recipes.copy_version_content(p_from uuid, p_to uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_to recipes.recipe_versions;
begin
  select * into v_to from recipes.recipe_versions where id = p_to;
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, sub_recipe_id, quantity,
                                         unit_id, quantity_basis, yield_profile_id, no_scale, notes)
  select v_to.group_id, p_to, line_order, ingredient_id, sub_recipe_id, quantity, unit_id, quantity_basis, yield_profile_id,
         no_scale, notes
    from recipes.recipe_components where recipe_version_id = p_from and deleted_at is null;
  insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                    passive_minutes, workers, sector, sector_id, equipment, equipment_id, equipment_capacity,
                                    equipment_capacity_unit_id, control_point)
  select v_to.group_id, p_to, step_number, kind, instructions, active_minutes, passive_minutes, workers, sector, sector_id,
         equipment, equipment_id, equipment_capacity, equipment_capacity_unit_id, control_point
    from recipes.recipe_steps where recipe_version_id = p_from and deleted_at is null;
  -- Las dependencias se copian por número de paso.
  insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
  select v_to.group_id, ns.id, nd.id
    from recipes.recipe_step_dependencies d
    join recipes.recipe_steps os on os.id = d.step_id
    join recipes.recipe_steps od on od.id = d.depends_on_step_id
    join recipes.recipe_steps ns on ns.recipe_version_id = p_to and ns.step_number = os.step_number and ns.deleted_at is null
    join recipes.recipe_steps nd on nd.recipe_version_id = p_to and nd.step_number = od.step_number and nd.deleted_at is null
   where os.recipe_version_id = p_from and d.deleted_at is null;
  insert into recipes.recipe_media (group_id, recipe_id, recipe_version_id, kind, storage_path, description)
  select v_to.group_id, v_to.recipe_id, p_to, kind, storage_path, description
    from recipes.recipe_media where recipe_version_id = p_from and deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Lo cargado pasa a las listas
-- ---------------------------------------------------------------------------
-- Un elemento por cada texto distinto (se usa el que ya está); de varias escrituras, la más usada. Los textos con < o > o
-- con caracteres que no se ven quedan como texto. Las versiones archivadas no suman elementos.
create function recipes.link_lists_from_text(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  with texts as (
    select r.sector as name from recipes.recipes r where r.group_id = p_group_id and r.deleted_at is null
    union all
    select s.sector from recipes.recipe_steps s join recipes.recipe_versions v on v.id = s.recipe_version_id
     where s.group_id = p_group_id and s.deleted_at is null and v.deleted_at is null and v.status <> 'archived'
  ), picked as (
    select distinct on (catalog.list_key(name)) name
      from (select name, count(*) as n from texts where name is not null group by name) t
     where name !~ '[<>]' and catalog.list_key(name) <> '' and not core.has_hidden_characters(replace(name, chr(160), ' '))
     order by catalog.list_key(name), n desc, name
  )
  insert into catalog.kitchen_sectors (group_id, name)
  select p_group_id, p.name from picked p where catalog.list_item_id('sectors', p_group_id, p.name) is null;

  with picked as (
    select distinct on (catalog.list_key(name)) name
      from (select r.station as name, count(*) as n from recipes.recipes r
             where r.group_id = p_group_id and r.deleted_at is null and r.station is not null group by r.station) t
     where name !~ '[<>]' and catalog.list_key(name) <> '' and not core.has_hidden_characters(replace(name, chr(160), ' '))
     order by catalog.list_key(name), n desc, name
  )
  insert into catalog.kitchen_stations (group_id, name)
  select p_group_id, p.name from picked p where catalog.list_item_id('stations', p_group_id, p.name) is null;

  with picked as (
    select distinct on (catalog.list_key(name)) name
      from (select s.equipment as name, count(*) as n
              from recipes.recipe_steps s join recipes.recipe_versions v on v.id = s.recipe_version_id
             where s.group_id = p_group_id and s.deleted_at is null and s.equipment is not null
               and v.deleted_at is null and v.status <> 'archived'
             group by s.equipment) t
     where name !~ '[<>]' and catalog.list_key(name) <> '' and not core.has_hidden_characters(replace(name, chr(160), ' '))
     order by catalog.list_key(name), n desc, name
  )
  insert into catalog.kitchen_equipment (group_id, name)
  select p_group_id, p.name from picked p where catalog.list_item_id('equipment', p_group_id, p.name) is null;

  -- La receta y los pasos en borrador quedan vinculados. Lo que ya no es borrador no se toca.
  update recipes.recipes r
     set sector_id = coalesce(r.sector_id, catalog.list_item_id('sectors', r.group_id, r.sector)),
         station_id = coalesce(r.station_id, catalog.list_item_id('stations', r.group_id, r.station))
   where r.group_id = p_group_id and r.deleted_at is null
     and ((r.sector is not null and r.sector_id is null) or (r.station is not null and r.station_id is null));
  update recipes.recipe_steps s
     set sector_id = coalesce(s.sector_id, catalog.list_item_id('sectors', s.group_id, s.sector)),
         equipment_id = coalesce(s.equipment_id, catalog.list_item_id('equipment', s.group_id, s.equipment))
    from recipes.recipe_versions v
   where v.id = s.recipe_version_id and v.status = 'draft' and v.deleted_at is null
     and s.group_id = p_group_id and s.deleted_at is null
     and ((s.sector is not null and s.sector_id is null) or (s.equipment is not null and s.equipment_id is null));
end
$$;
comment on function recipes.link_lists_from_text(uuid) is
  'Interna: pasa a las listas del grupo los sectores, partidas y equipos que las recetas tienen como texto, y vincula las recetas y los pasos en borrador. No toca las versiones que ya no son borrador. Se puede repetir.';
revoke execute on function recipes.link_lists_from_text(uuid) from public;

do $$
begin
  perform core.set_change_context('Sectores, partidas y equipos de las recetas pasan a las listas del grupo (ADR-0063)', 'maintenance');
  perform recipes.link_lists_from_text(id) from org.groups where deleted_at is null;
end
$$;
