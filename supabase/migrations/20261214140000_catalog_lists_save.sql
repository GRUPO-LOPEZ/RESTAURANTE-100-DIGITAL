-- Configuración del catálogo en una pantalla (ADR-0063): las 8 listas se leen y se guardan igual.
--   * catalog.settings_lists: las listas, cuántos elementos tienen y si la sesión las edita.
--   * catalog.settings_list: las filas de una lista, cuántas cosas la usan, qué se puede desactivar y por qué no.
--   * catalog.save_settings_list: todos los cambios de una lista en una transacción, con motivo y sello. Cada lista sigue
--     con su permiso (catalog.can_manage_list) y, donde ya había funciones, usa esas: las reglas no se repiten.
--   * Desactivar: sectores, partidas, equipos y medidas, siempre (lo que los usa no cambia). Subcategorías, procesos y
--     unidades, con la regla de siempre (nada en uso), y ahora se pueden reactivar.

create function catalog.settings_list_stamp(p_list catalog.settings_list, p_group_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(case p_list
           when 'ingredient_categories' then (select max(updated_at) from catalog.ingredient_categories where group_id = p_group_id)
           when 'recipe_categories' then (select max(updated_at) from recipes.recipe_categories where group_id = p_group_id)
           when 'sectors' then (select max(updated_at) from catalog.kitchen_sectors where group_id = p_group_id)
           when 'stations' then (select max(updated_at) from catalog.kitchen_stations where group_id = p_group_id)
           when 'equipment' then (select max(updated_at) from catalog.kitchen_equipment where group_id = p_group_id)
           when 'measures' then (select max(updated_at) from catalog.practical_measures where group_id = p_group_id)
           when 'units' then (select max(updated_at) from catalog.units)
           when 'processes' then (select max(updated_at) from catalog.yield_processes where group_id = p_group_id)
         end, 'epoch'::timestamptz)
$$;
comment on function catalog.settings_list_stamp(catalog.settings_list, uuid) is
  'Interna: el sello de una lista del catálogo (su último cambio). Sirve para no pisar lo de otra persona.';
revoke execute on function catalog.settings_list_stamp(catalog.settings_list, uuid) from public;

-- Por qué no se puede dar de baja (nulo = se puede). La regla la vuelven a controlar las funciones de baja.
create function catalog.cannot_archive_item(p_list catalog.settings_list, p_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_n      integer;
  v_unit   catalog.units;
begin
  if p_list = 'ingredient_categories' then
    if exists (select 1 from catalog.ingredient_categories where id = p_id and parent_id is null) then
      return 'Es un rubro: se da de baja en Rubros.';
    end if;
    select count(*) into v_n from catalog.ingredients where category_id = p_id and deleted_at is null;
    if v_n > 0 then
      return case when v_n = 1 then 'Tiene 1 materia prima.' else format('Tiene %s materias primas.', v_n) end;
    end if;
  elsif p_list = 'recipe_categories' then
    if exists (select 1 from recipes.recipe_categories where id = p_id and parent_id is null) then
      return 'Es un rubro: se da de baja en Rubros.';
    end if;
    select count(*) into v_n from recipes.recipes where category_id = p_id and deleted_at is null;
    if v_n > 0 then
      return case when v_n = 1 then 'Tiene 1 receta.' else format('Tiene %s recetas.', v_n) end;
    end if;
  elsif p_list = 'processes' then
    if exists (select 1 from catalog.ingredient_yield_profiles where process_id = p_id and status = 'approved') then
      return 'Tiene rendimientos estándar vigentes.';
    end if;
    if exists (select 1 from catalog.ingredient_yield_profiles p
                 join workflow.approval_requests r on r.id = p.approval_request_id and r.status = 'pending'
                where p.process_id = p_id and p.status = 'draft') then
      return 'Tiene propuestas de rendimiento en revisión.';
    end if;
  elsif p_list = 'units' then
    select * into v_unit from catalog.units where id = p_id;
    if v_unit.is_base then
      return 'Es una unidad base.';
    elsif v_unit.created_by is null then
      return 'Es una unidad del sistema.';
    elsif v_unit.deleted_at is null and catalog.unit_in_use(p_id) then
      return 'Ya se usa.';
    end if;
  end if;
  return null;
end
$$;
comment on function catalog.cannot_archive_item(catalog.settings_list, uuid) is
  'Interna: por qué un elemento de una lista no se puede dar de baja (nulo = se puede). Lo muestra la pantalla.';
revoke execute on function catalog.cannot_archive_item(catalog.settings_list, uuid) from public;

create function catalog.settings_lists(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(core.current_session_ok() and catalog.can_see_lists(p_group_id), 'ver la configuración del catálogo');
  return (
    select jsonb_agg(jsonb_build_object(
             'list', l.list,
             'can_edit', catalog.can_manage_list(l.list, p_group_id),
             'active', case l.list
               when 'ingredient_categories' then (select count(*) from catalog.ingredient_categories where group_id = p_group_id and deleted_at is null and is_active)
               when 'recipe_categories' then (select count(*) from recipes.recipe_categories where group_id = p_group_id and deleted_at is null and is_active)
               when 'sectors' then (select count(*) from catalog.kitchen_sectors where group_id = p_group_id and deleted_at is null and is_active)
               when 'stations' then (select count(*) from catalog.kitchen_stations where group_id = p_group_id and deleted_at is null and is_active)
               when 'equipment' then (select count(*) from catalog.kitchen_equipment where group_id = p_group_id and deleted_at is null and is_active)
               when 'measures' then (select count(*) from catalog.practical_measures where group_id = p_group_id and deleted_at is null and is_active)
               when 'units' then (select count(*) from catalog.units where deleted_at is null)
               else (select count(*) from catalog.yield_processes where group_id = p_group_id and deleted_at is null)
             end) order by l.n)
      from unnest(enum_range(null::catalog.settings_list)) with ordinality as l (list, n));
end
$$;
comment on function catalog.settings_lists(uuid) is
  'Las 8 listas de Configuración del catálogo: cuántos elementos activos tiene cada una y si la sesión la edita. Pide administrar al menos una.';
revoke execute on function catalog.settings_lists(uuid) from public, anon;
grant execute on function catalog.settings_lists(uuid) to authenticated;

create function catalog.settings_list(p_group_id uuid, p_list catalog.settings_list)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  perform org.require(core.current_session_ok() and catalog.can_see_lists(p_group_id), 'ver la configuración del catálogo');
  if p_list = 'ingredient_categories' then
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'code', c.code, 'parent_id', c.parent_id,
             'active', c.deleted_at is null and c.is_active, 'editable', true,
             'uses', (select count(*) from catalog.ingredients i where i.category_id = c.id and i.deleted_at is null),
             'why', catalog.cannot_archive_item(p_list, c.id)) order by lower(c.name))
      into v_rows
      from catalog.ingredient_categories c
      left join catalog.ingredient_categories m on m.id = c.parent_id
     where c.group_id = p_group_id and ((c.deleted_at is null and (c.parent_id is not null or c.is_active))
                                        or (c.parent_id is not null and m.deleted_at is null and m.is_active));
  elsif p_list = 'recipe_categories' then
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'code', c.code, 'parent_id', c.parent_id,
             'active', c.deleted_at is null and c.is_active, 'editable', true,
             'uses', (select count(*) from recipes.recipes r where r.category_id = c.id and r.deleted_at is null),
             'why', catalog.cannot_archive_item(p_list, c.id)) order by lower(c.name))
      into v_rows
      from recipes.recipe_categories c
      left join recipes.recipe_categories m on m.id = c.parent_id
     where c.group_id = p_group_id and ((c.deleted_at is null and (c.parent_id is not null or c.is_active))
                                        or (c.parent_id is not null and m.deleted_at is null and m.is_active));
  elsif p_list = 'sectors' then
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active, 'editable', true,
             -- Por la receta o por alguno de sus pasos.
             'uses', (select count(*) from recipes.recipes r
                       where r.group_id = p_group_id and r.deleted_at is null
                         and (r.sector_id = s.id
                              or exists (select 1 from recipes.recipe_versions v
                                           join recipes.recipe_steps t on t.recipe_version_id = v.id and t.deleted_at is null
                                          where v.recipe_id = r.id and v.deleted_at is null and v.status <> 'archived'
                                            and (t.sector_id = s.id
                                                 or (t.sector_id is null and t.sector is not null
                                                     and catalog.list_key(t.sector) = catalog.list_key(s.name))))))) order by lower(s.name))
      into v_rows from catalog.kitchen_sectors s where s.group_id = p_group_id and s.deleted_at is null;
  elsif p_list = 'stations' then
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active, 'editable', true,
             'uses', (select count(*) from recipes.recipes r where r.station_id = s.id and r.deleted_at is null)) order by lower(s.name))
      into v_rows from catalog.kitchen_stations s where s.group_id = p_group_id and s.deleted_at is null;
  elsif p_list = 'equipment' then
    -- Una versión anterior a las listas guarda el equipo como texto: cuenta por el nombre.
    with used as (
      select coalesce(s.equipment_id::text, catalog.list_key(s.equipment)) as key, count(distinct v.recipe_id) as recipes,
             array_agg(distinct v.recipe_id) as ids
        from recipes.recipe_steps s
        join recipes.recipe_versions v on v.id = s.recipe_version_id and v.deleted_at is null and v.status <> 'archived'
        join recipes.recipes r on r.id = v.recipe_id and r.deleted_at is null
       where s.group_id = p_group_id and s.deleted_at is null and s.equipment is not null
       group by 1
    )
    select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'capacity', e.capacity, 'capacity_unit', u.code,
             'capacity_label', e.capacity_label, 'active', e.is_active, 'editable', true,
             'uses', (select count(distinct x) from used, unnest(used.ids) x
                       where used.key in (e.id::text, catalog.list_key(e.name)))) order by lower(e.name))
      into v_rows
      from catalog.kitchen_equipment e left join catalog.units u on u.id = e.capacity_unit_id
     where e.group_id = p_group_id and e.deleted_at is null;
  elsif p_list = 'measures' then
    select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'content', m.content, 'content_unit', u.code,
             'usage_note', m.usage_note, 'active', m.is_active, 'editable', true) order by lower(m.name))
      into v_rows
      from catalog.practical_measures m join catalog.units u on u.id = m.content_unit_id
     where m.group_id = p_group_id and m.deleted_at is null;
  elsif p_list = 'units' then
    select jsonb_agg(jsonb_build_object('id', u.id, 'code', u.code, 'name', u.long_name, 'abbreviation', u.abbreviation,
             'dimension', u.dimension, 'is_base', u.is_base, 'factor', c.factor, 'base_unit', b.abbreviation,
             'active', u.deleted_at is null, 'editable', false,
             'why', catalog.cannot_archive_item(p_list, u.id)) order by u.dimension, u.is_base desc, lower(u.long_name))
      into v_rows
      from catalog.units u
      left join lateral (select c.factor, c.to_unit_id from catalog.unit_conversions c
                          where c.from_unit_id = u.id order by c.deleted_at is null desc, c.deleted_at desc limit 1) c on true
      left join catalog.units b on b.id = c.to_unit_id
     where u.deleted_at is null or u.created_by is not null;
  else
    select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'active', p.deleted_at is null, 'editable', true,
             'uses', (select count(distinct y.ingredient_id) from catalog.ingredient_yield_profiles y
                       where y.process_id = p.id and y.status = 'approved'),
             'why', catalog.cannot_archive_item(p_list, p.id)) order by lower(p.name))
      into v_rows from catalog.yield_processes p where p.group_id = p_group_id;
  end if;
  return jsonb_build_object('list', p_list, 'can_edit', catalog.can_manage_list(p_list, p_group_id),
                            'stamp', catalog.settings_list_stamp(p_list, p_group_id), 'rows', coalesce(v_rows, '[]'::jsonb));
end
$$;
comment on function catalog.settings_list(uuid, catalog.settings_list) is
  'Una lista de Configuración del catálogo: sus elementos (también los inactivos), cuántas cosas usan cada uno, por qué no se puede dar de baja, si la sesión la edita y el sello. Pide administrar al menos una lista.';
revoke execute on function catalog.settings_list(uuid, catalog.settings_list) from public, anon;
grant execute on function catalog.settings_list(uuid, catalog.settings_list) to authenticated;

-- ---------------------------------------------------------------------------
-- Guardar
-- ---------------------------------------------------------------------------
create function catalog.item_is_live(p_list catalog.settings_list, p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_list
           when 'ingredient_categories' then exists (select 1 from catalog.ingredient_categories where id = p_id and deleted_at is null)
           when 'recipe_categories' then exists (select 1 from recipes.recipe_categories where id = p_id and deleted_at is null)
           when 'processes' then exists (select 1 from catalog.yield_processes where id = p_id and deleted_at is null)
           else exists (select 1 from catalog.units where id = p_id and deleted_at is null)
         end
$$;
comment on function catalog.item_is_live(catalog.settings_list, uuid) is
  'Interna: si una subcategoría, un proceso o una unidad está vigente (no está dada de baja).';
revoke execute on function catalog.item_is_live(catalog.settings_list, uuid) from public;

-- Vuelve a activar lo que se dio de baja (borrado lógico): subcategorías, procesos y unidades.
create function catalog.restore_item(p_list catalog.settings_list, p_group_id uuid, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  if p_list = 'ingredient_categories' then
    select parent_id into v_parent from catalog.ingredient_categories where id = p_id and group_id = p_group_id and deleted_at is not null;
    if v_parent is null
       or not exists (select 1 from catalog.ingredient_categories where id = v_parent and deleted_at is null and is_active for share) then
      raise exception 'Su rubro está dado de baja: reactivalo antes en Rubros.' using errcode = '23514';
    end if;
    update catalog.ingredient_categories set deleted_at = null where id = p_id;
  elsif p_list = 'recipe_categories' then
    select parent_id into v_parent from recipes.recipe_categories where id = p_id and group_id = p_group_id and deleted_at is not null;
    if v_parent is null
       or not exists (select 1 from recipes.recipe_categories where id = v_parent and deleted_at is null and is_active for share) then
      raise exception 'Su rubro está dado de baja: reactivalo antes en Rubros.' using errcode = '23514';
    end if;
    update recipes.recipe_categories set deleted_at = null where id = p_id;
  elsif p_list = 'processes' then
    update catalog.yield_processes set deleted_at = null where id = p_id and group_id = p_group_id and deleted_at is not null;
  elsif p_list = 'units' then
    update catalog.units set deleted_at = null where id = p_id and deleted_at is not null and created_by is not null;
    -- Con la conversión que tenía al darla de baja (la última).
    update catalog.unit_conversions set deleted_at = null
     where id = (select id from catalog.unit_conversions where from_unit_id = p_id and deleted_at is not null
                  order by deleted_at desc limit 1)
       and not exists (select 1 from catalog.unit_conversions where from_unit_id = p_id and deleted_at is null);
  end if;
end
$$;
comment on function catalog.restore_item(catalog.settings_list, uuid, uuid) is
  'Interna: reactiva una subcategoría, un proceso o una unidad dados de baja. El permiso y el motivo los controla catalog.save_settings_list.';
revoke execute on function catalog.restore_item(catalog.settings_list, uuid, uuid) from public;

create function catalog.save_settings_list(p_group_id uuid, p_list catalog.settings_list, p_expected_stamp timestamptz,
                                           p_items jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_keys   text[];
  v_item   jsonb;
  v_key    text;
  v_value  jsonb;
  v_id     uuid;
  v_active boolean;
  v_name   text;
  v_hit    boolean;
  v_new    boolean;
  v_unit   uuid;
  v_cap    numeric;
  v_constraint text;
  v_uuid   constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_soft   boolean := p_list in ('ingredient_categories', 'recipe_categories', 'processes', 'units');
begin
  if not core.current_session_ok() or p_list is null or not catalog.can_manage_list(p_list, p_group_id) then
    return core.deny('catalog.save_settings_list', 'No tenés permiso para editar esta lista.', null,
                     jsonb_build_object('list', p_list),
                     (select g from core.visible_group_ids('catalog.view') g where g = p_group_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 3 and 500 then
    raise exception 'Escribí el motivo de los cambios (de 3 a 500 caracteres).' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'Son demasiados cambios juntos: guardá hasta 100 por vez.' using errcode = '22023';
  end if;
  v_keys := array['id', 'name', 'active'] || case p_list
    when 'ingredient_categories' then array['parent_id']
    when 'recipe_categories' then array['parent_id']
    when 'equipment' then array['capacity', 'capacity_unit', 'capacity_label']
    when 'measures' then array['content', 'content_unit', 'usage_note']
    when 'processes' then array['code']
    when 'units' then array['code', 'abbreviation', 'dimension', 'factor']
    else array[]::text[] end;
  for v_item in select value from jsonb_array_elements(p_items) loop
    perform org.check_keys(v_item, v_keys);
    if v_item ? 'id' and coalesce(v_item ->> 'id', '') !~ v_uuid then
      raise exception 'Algún elemento no es válido: recargá la página.' using errcode = '22023';
    end if;
    if v_item ? 'id' and v_item ?| array['parent_id', 'code', 'dimension', 'factor'] then
      raise exception 'El rubro, el código, el tipo y la equivalencia no cambian.' using errcode = '22023';
    end if;
    -- El nombre de una unidad lo leen las recetas publicadas y los pedidos: cambiarlo reescribiría lo ya publicado
    -- (revisión de seguridad y de base, G1). Para corregirla, se da de baja y se crea otra.
    if v_item ? 'id' and p_list = 'units' and v_item ?| array['name', 'abbreviation'] then
      raise exception 'Una unidad no cambia de nombre: dala de baja y creá otra.' using errcode = '23514';
    end if;
    -- Solo textos (y active), limpios: lo que no se ve o un < imitan a otro elemento. También en las listas de antes.
    for v_key, v_value in select key, value from jsonb_each(v_item) loop
      if v_key <> 'active' and jsonb_typeof(v_value) <> 'string' then
        raise exception 'Algún elemento no es válido: recargá la página.' using errcode = '22023';
      end if;
      if v_key <> 'active' and (core.has_hidden_characters(replace(v_value #>> '{}', chr(160), ' ')) or v_value #>> '{}' ~ '[<>]') then
        raise exception 'Algún texto lleva < o > o caracteres que no se ven: escribilo de nuevo.' using errcode = '22023';
      end if;
      if v_key in ('capacity', 'content', 'factor') and btrim(v_value #>> '{}') !~ '^$|^-?[0-9]{1,9}([.,][0-9]{1,6})?$' then
        raise exception 'Revisá los números: alguno no tiene el formato esperado.' using errcode = '22023';
      end if;
    end loop;
    if v_item ? 'active' and jsonb_typeof(v_item -> 'active') <> 'boolean' then
      raise exception 'Algún elemento no es válido: recargá la página.' using errcode = '22023';
    end if;
    if not v_item ? 'id' and nullif(btrim(v_item ->> 'name'), '') is null then
      raise exception 'Escribí el nombre de lo que agregaste.' using errcode = '22023';
    end if;
  end loop;

  -- Dos guardados de la misma lista van de a uno; el segundo ve que el primero cambió algo.
  perform pg_advisory_xact_lock(hashtextextended('catalog.settings_list:' || p_list || ':' || case when p_list = 'units' then '' else p_group_id::text end, 0));
  if p_expected_stamp is null or catalog.settings_list_stamp(p_list, p_group_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió esta lista mientras la editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');

  -- Primero las bajas (liberan el nombre), después los cambios, las reactivaciones y lo nuevo.
  for v_item, v_new in
    select value, not value ? 'id' from jsonb_array_elements(p_items) with ordinality t (value, n)
     order by (not value ? 'id'), case when value -> 'active' = 'false'::jsonb then 0 else 1 end, n
  loop
    v_id := (v_item ->> 'id')::uuid;
    v_name := v_item ->> 'name';
    v_active := (v_item ->> 'active')::boolean;

    -- El elemento es de esta lista y de este grupo (las unidades son de todo el sistema).
    if not v_new then
      v_hit := case p_list
        when 'ingredient_categories' then exists (select 1 from catalog.ingredient_categories where id = v_id and group_id = p_group_id)
        when 'recipe_categories' then exists (select 1 from recipes.recipe_categories where id = v_id and group_id = p_group_id)
        when 'sectors' then exists (select 1 from catalog.kitchen_sectors where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'stations' then exists (select 1 from catalog.kitchen_stations where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'equipment' then exists (select 1 from catalog.kitchen_equipment where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'measures' then exists (select 1 from catalog.practical_measures where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'units' then exists (select 1 from catalog.units where id = v_id)
        else exists (select 1 from catalog.yield_processes where id = v_id and group_id = p_group_id) end;
      if not v_hit then
        raise exception 'Algún elemento ya no está en la lista: recargá la página.' using errcode = '22023';
      end if;
    end if;

    if v_soft then
      -- Las que ya existían: con sus funciones de siempre. Reactivar va antes de cambiar el nombre, y la baja después
      -- (un registro borrado no se edita).
      if not v_new and v_active and not catalog.item_is_live(p_list, v_id) then
        perform catalog.restore_item(p_list, p_group_id, v_id);
      end if;
      if p_list = 'ingredient_categories' then
        if v_new then
          if nullif(v_item ->> 'parent_id', '') is null then
            raise exception 'Elegí el rubro de la subcategoría nueva.' using errcode = '22023';
          end if;
          perform catalog.create_category(p_group_id, v_name, p_reason, (v_item ->> 'parent_id')::uuid);
        elsif v_item ? 'name' then
          perform catalog.rename_category(v_id, v_name, p_reason);
        end if;
        if not v_new and v_active is false then
          if exists (select 1 from catalog.ingredient_categories where id = v_id and parent_id is null) then
            raise exception 'Un rubro se da de baja en Rubros.' using errcode = '23514';
          end if;
          perform catalog.archive_category(v_id, p_reason);
        end if;
      elsif p_list = 'recipe_categories' then
        if v_new then
          if nullif(v_item ->> 'parent_id', '') is null then
            raise exception 'Elegí el rubro de la subcategoría nueva.' using errcode = '22023';
          end if;
          perform recipes.create_category(p_group_id, v_name, p_reason, (v_item ->> 'parent_id')::uuid);
        elsif v_item ? 'name' then
          perform recipes.rename_category(v_id, v_name, p_reason);
        end if;
        if not v_new and v_active is false then
          if exists (select 1 from recipes.recipe_categories where id = v_id and parent_id is null) then
            raise exception 'Un rubro se da de baja en Rubros.' using errcode = '23514';
          end if;
          perform recipes.archive_category(v_id, p_reason);
        end if;
      elsif p_list = 'processes' then
        if v_new then
          perform catalog.create_yield_process(p_group_id, v_item ->> 'code', v_name, p_reason);
        elsif v_item ? 'name' then
          perform catalog.rename_yield_process(v_id, v_name, p_reason);
        end if;
        if not v_new and v_active is false then
          perform catalog.archive_yield_process(v_id, p_reason);
        end if;
      else
        if v_new then
          if not coalesce(v_item ->> 'dimension', '') = any (enum_range(null::catalog.dimension)::text[]) then
            raise exception 'Elegí si la unidad es de peso, volumen, unidades o un envase.' using errcode = '22023';
          end if;
          perform catalog.create_unit(p_group_id, v_item ->> 'code', v_name, v_item ->> 'abbreviation',
                                      (v_item ->> 'dimension')::catalog.dimension, p_reason,
                                      nullif(replace(btrim(v_item ->> 'factor'), ',', '.'), '')::numeric);
        end if;
        if not v_new and v_active is false then
          perform catalog.archive_unit(p_group_id, v_id, p_reason);
        end if;
      end if;
      continue;
    end if;

    -- Las listas de la cocina.
    if v_item ? 'name' and nullif(btrim(v_name), '') is null then
      raise exception 'El nombre no puede quedar vacío.' using errcode = '22023';
    end if;
    if p_list = 'sectors' then
      if v_new then
        insert into catalog.kitchen_sectors (group_id, name, is_active) values (p_group_id, v_name, coalesce(v_active, true));
      else
        update catalog.kitchen_sectors set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active) where id = v_id;
      end if;
    elsif p_list = 'stations' then
      if v_new then
        insert into catalog.kitchen_stations (group_id, name, is_active) values (p_group_id, v_name, coalesce(v_active, true));
      else
        update catalog.kitchen_stations set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active) where id = v_id;
      end if;
    elsif p_list = 'equipment' then
      -- La capacidad viaja entera: número y, o bien una unidad del sistema, o bien una palabra.
      v_cap := nullif(replace(btrim(v_item ->> 'capacity'), ',', '.'), '')::numeric;
      v_unit := null;
      if nullif(v_item ->> 'capacity_unit', '') is not null then
        select id into v_unit from catalog.units where code = v_item ->> 'capacity_unit' and deleted_at is null;
        if v_unit is null then
          raise exception 'Elegí la unidad de la capacidad.' using errcode = '22023';
        end if;
      end if;
      if v_item ?| array['capacity', 'capacity_unit', 'capacity_label']
         and not v_item ?& array['capacity', 'capacity_unit', 'capacity_label'] then
        raise exception 'La capacidad va completa: cuánto y en qué.' using errcode = '22023';
      end if;
      if v_new then
        insert into catalog.kitchen_equipment (group_id, name, capacity, capacity_unit_id, capacity_label, is_active)
        values (p_group_id, v_name, v_cap, v_unit, nullif(btrim(v_item ->> 'capacity_label'), ''), coalesce(v_active, true));
      else
        update catalog.kitchen_equipment
           set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active),
               capacity = case when v_item ? 'capacity' then v_cap else capacity end,
               capacity_unit_id = case when v_item ? 'capacity' then v_unit else capacity_unit_id end,
               capacity_label = case when v_item ? 'capacity' then nullif(btrim(v_item ->> 'capacity_label'), '') else capacity_label end
         where id = v_id;
      end if;
    else
      v_cap := nullif(replace(btrim(v_item ->> 'content'), ',', '.'), '')::numeric;
      v_unit := null;
      if v_item ? 'content_unit' then
        select id into v_unit from catalog.units where code = v_item ->> 'content_unit' and is_base and deleted_at is null;
        if v_unit is null then
          raise exception 'Lo que contiene la medida va en ml, g o unidades.' using errcode = '22023';
        end if;
      end if;
      if v_new then
        if v_cap is null or v_unit is null then
          raise exception 'Escribí cuánto contiene «%» y en qué unidad.', btrim(v_name) using errcode = '22023';
        end if;
        insert into catalog.practical_measures (group_id, name, content, content_unit_id, usage_note, is_active)
        values (p_group_id, v_name, v_cap, v_unit, nullif(btrim(v_item ->> 'usage_note'), ''), coalesce(v_active, true));
      else
        if v_item ? 'content' and v_cap is null then
          raise exception 'Escribí cuánto contiene la medida.' using errcode = '22023';
        end if;
        update catalog.practical_measures
           set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active),
               content = coalesce(v_cap, content), content_unit_id = coalesce(v_unit, content_unit_id),
               usage_note = case when v_item ? 'usage_note' then nullif(btrim(v_item ->> 'usage_note'), '') else usage_note end
         where id = v_id;
      end if;
    end if;
  end loop;

  return jsonb_build_object('result', 'applied', 'message', 'Cambios guardados.',
                            'stamp', catalog.settings_list_stamp(p_list, p_group_id));
exception
  when unique_violation or check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    -- Los mensajes propios de la base y de las funciones de siempre pasan tal cual.
    if coalesce(v_constraint, '') = '' then
      raise;
    elsif v_constraint like '%\_name\_key' then
      raise exception 'Ya hay un elemento con ese nombre en la lista (puede estar inactivo).' using errcode = '23505';
    elsif v_constraint in ('yield_processes_code_key', 'units_code_key') then
      raise exception 'Ya hay un elemento con ese código.' using errcode = '23505';
    elsif v_constraint like '%\_name\_check' then
      raise exception 'El nombre no puede quedar vacío, ser demasiado largo ni llevar < o >.' using errcode = '23514';
    elsif v_constraint = 'kitchen_equipment_capacity_form' then
      raise exception 'La capacidad va completa: cuánto y en qué.' using errcode = '23514';
    elsif v_constraint = 'kitchen_equipment_label_check' then
      raise exception 'La capacidad en palabras va hasta 40 caracteres, sin < ni >.' using errcode = '23514';
    elsif v_constraint = 'practical_measures_note_check' then
      raise exception '«Se usa con» va hasta 120 caracteres, sin < ni >.' using errcode = '23514';
    elsif v_constraint in ('kitchen_equipment_capacity_check', 'practical_measures_content_check') then
      raise exception 'El número tiene que ser mayor que cero y no tan grande.' using errcode = '23514';
    elsif v_constraint in ('unit_conversions_factor_check', 'unit_conversions_factor_number') then
      raise exception 'La equivalencia tiene que ser un número mayor que cero y no tan grande.' using errcode = '23514';
    elsif v_constraint in ('units_abbreviation_check', 'units_long_name_check') then
      raise exception 'La unidad lleva un nombre (hasta 40 caracteres) y una abreviatura (hasta 12).' using errcode = '23514';
    end if;
    raise;
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los números: alguno no tiene el formato esperado o es demasiado grande.' using errcode = '22023';
end
$$;
comment on function catalog.save_settings_list(uuid, catalog.settings_list, timestamptz, jsonb, text) is
  'Guarda los cambios de una lista de Configuración del catálogo en una transacción, con motivo y sello. Cada elemento, con id (cambia de nombre o de datos; active lo da de baja o lo reactiva) o sin id (nuevo). El permiso es el de cada lista (catalog.can_manage_list); el rechazo queda registrado.';
revoke execute on function catalog.save_settings_list(uuid, catalog.settings_list, timestamptz, jsonb, text) from public, anon;
grant execute on function catalog.save_settings_list(uuid, catalog.settings_list, timestamptz, jsonb, text) to authenticated;
