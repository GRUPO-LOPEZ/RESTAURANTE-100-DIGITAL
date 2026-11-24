-- La ficha de receta elige sector, partida y equipo de las listas del grupo (Tanda 2 de Soy, PR B; ADR-0064). Las funciones
-- aceptan el elemento (sector_id, station_id y equipment_id); el texto sigue valiendo para la importación y para lo que
-- quedó fuera de la lista. Con el elemento, un borrador abierto mientras la lista cambia un nombre no pierde el vínculo.
-- (Esos pasos llegan sin texto: lo pone recipes.link_lists.)

create or replace function recipes.update_recipe(p_id uuid, p_changes jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_r          recipes.recipes;
  v_constraint text;
  v_message    text;
begin
  select * into v_r from recipes.recipes where id = p_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.update_recipe', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('recipe_id', p_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  perform org.check_keys(p_changes, array['name', 'short_name', 'category_id', 'sector', 'station', 'sector_id', 'station_id',
                                         'technical_owner_id']);
  if nullif(p_changes ->> 'category_id', '') is not null
     and not exists (select 1 from recipes.recipe_categories
                      where id = (p_changes ->> 'category_id')::uuid and group_id = v_r.group_id and deleted_at is null) then
    raise exception 'Elegí una categoría de recetas del grupo.' using errcode = '22023';
  end if;
  if nullif(p_changes ->> 'technical_owner_id', '') is not null
     and not exists (select 1 from core.user_memberships m
                      where m.user_id = (p_changes ->> 'technical_owner_id')::uuid and m.group_id = v_r.group_id
                        and m.deleted_at is null) then
    raise exception 'Elegí como responsable técnico a una persona del grupo.' using errcode = '22023';
  end if;
  -- Un elemento inactivo de la lista solo sigue donde ya estaba.
  if nullif(p_changes ->> 'sector_id', '') is not null and (p_changes ->> 'sector_id')::uuid is distinct from v_r.sector_id
     and not exists (select 1 from catalog.kitchen_sectors
                      where id = (p_changes ->> 'sector_id')::uuid and group_id = v_r.group_id and deleted_at is null and is_active) then
    raise exception 'Elegí un sector activo de la lista.' using errcode = '22023';
  end if;
  if nullif(p_changes ->> 'station_id', '') is not null and (p_changes ->> 'station_id')::uuid is distinct from v_r.station_id
     and not exists (select 1 from catalog.kitchen_stations
                      where id = (p_changes ->> 'station_id')::uuid and group_id = v_r.group_id and deleted_at is null and is_active) then
    raise exception 'Elegí una partida activa de la lista.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipes
     set name               = coalesce(btrim(p_changes ->> 'name'), name),
         short_name         = case when p_changes ? 'short_name' then nullif(btrim(p_changes ->> 'short_name'), '') else short_name end,
         category_id        = case when p_changes ? 'category_id' then nullif(p_changes ->> 'category_id', '')::uuid else category_id end,
         -- El elemento manda sobre el texto: el texto es su nombre (recipes.link_lists). Vacío, saca los dos.
         sector             = case when p_changes ? 'sector_id' then case when nullif(p_changes ->> 'sector_id', '') is null then null else sector end
                                   when p_changes ? 'sector' then nullif(btrim(p_changes ->> 'sector'), '') else sector end,
         sector_id          = case when p_changes ? 'sector_id' then nullif(p_changes ->> 'sector_id', '')::uuid else sector_id end,
         station            = case when p_changes ? 'station_id' then case when nullif(p_changes ->> 'station_id', '') is null then null else station end
                                   when p_changes ? 'station' then nullif(btrim(p_changes ->> 'station'), '') else station end,
         station_id         = case when p_changes ? 'station_id' then nullif(p_changes ->> 'station_id', '')::uuid else station_id end,
         technical_owner_id = case when p_changes ? 'technical_owner_id' then nullif(p_changes ->> 'technical_owner_id', '')::uuid
                                   else technical_owner_id end
   where id = p_id;
  return jsonb_build_object('result', 'applied', 'message', 'Receta actualizada.');
exception when unique_violation or check_violation or foreign_key_violation or invalid_text_representation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if sqlstate = '22P02' then
    raise exception 'Algún dato no tiene el formato esperado.' using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;

create or replace function recipes.set_steps(p_version_id uuid, p_steps jsonb, p_reason text, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_v          recipes.recipe_versions;
  v_recipe     recipes.recipes;
  v_id         uuid;
  v_step       jsonb;
  v_dep        jsonb;
  v_n          integer := 0;
  v_ids        uuid[] := '{}';
  v_count      integer;
  v_constraint text;
  v_message    text;
begin
  perform recipes.share_measures(x.group_id) from recipes.recipe_versions x where x.id = p_version_id;
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_recipe from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_recipe.id is null or not recipes.allowed('recipes.draft', v_recipe.group_id, v_recipe.brand_id, v_recipe.restaurant_id) then
    return core.deny('recipes.set_steps', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_recipe.group_id, v_recipe.brand_id, v_recipe.restaurant_id);
  end if;
  v_v := recipes.open_draft(p_version_id, p_expected_updated_at);
  if p_steps is null or jsonb_typeof(p_steps) <> 'array' or jsonb_array_length(p_steps) > 100 then
    raise exception 'Los pasos tienen que ser una lista (hasta 100).' using errcode = '22023';
  end if;
  v_count := jsonb_array_length(p_steps);
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_step_dependencies d set deleted_at = now()
   where d.deleted_at is null
     and d.step_id in (select id from recipes.recipe_steps where recipe_version_id = p_version_id and deleted_at is null);
  update recipes.recipe_steps set deleted_at = now() where recipe_version_id = p_version_id and deleted_at is null;
  for v_step in select value from jsonb_array_elements(p_steps) loop
    v_n := v_n + 1;
    perform org.check_keys(v_step, array['kind', 'instructions', 'active_minutes', 'passive_minutes', 'workers', 'sector',
                                         'equipment', 'equipment_id', 'equipment_capacity', 'equipment_capacity_unit', 'control_point', 'depends_on']);
    -- Un equipo inactivo solo sigue donde ya estaba (los pasos de antes quedan con su baja lógica).
    if nullif(v_step ->> 'equipment_id', '') is not null
       and not exists (select 1 from catalog.kitchen_equipment e
                        where e.id = (v_step ->> 'equipment_id')::uuid and e.group_id = v_recipe.group_id and e.deleted_at is null
                          and (e.is_active or exists (select 1 from recipes.recipe_steps s
                                                       where s.recipe_version_id = p_version_id and s.equipment_id = e.id))) then
      raise exception 'Paso %: elegí un equipo activo de la lista.', v_n using errcode = '22023';
    end if;
    if nullif(btrim(v_step ->> 'equipment_capacity_unit'), '') is not null
       and not exists (select 1 from catalog.units u
                         join recipes.recipe_versions v on v.id = p_version_id
                         join catalog.units y on y.id = v.yield_unit_id
                        where u.code = v_step ->> 'equipment_capacity_unit' and u.deleted_at is null and u.dimension = y.dimension) then
      raise exception 'Paso %: la capacidad va en una unidad como la del rendimiento.', v_n using errcode = '22023';
    end if;
    insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                      passive_minutes, workers, sector, equipment, equipment_id, equipment_capacity, equipment_capacity_unit_id, control_point)
    values (v_recipe.group_id, p_version_id, v_n, coalesce(nullif(v_step ->> 'kind', ''), 'preparation')::recipes.step_kind,
            btrim(coalesce(v_step ->> 'instructions', '')), coalesce(nullif(v_step ->> 'active_minutes', '')::integer, 0),
            coalesce(nullif(v_step ->> 'passive_minutes', '')::integer, 0), nullif(v_step ->> 'workers', '')::smallint,
            nullif(btrim(v_step ->> 'sector'), ''), nullif(btrim(v_step ->> 'equipment'), ''),
            nullif(v_step ->> 'equipment_id', '')::uuid,
            nullif(replace(btrim(v_step ->> 'equipment_capacity'), ',', '.'), '')::numeric,
            -- La capacidad guarda su unidad: la que traía, o la del rendimiento de la versión.
            case when nullif(btrim(v_step ->> 'equipment_capacity'), '') is not null
                 then coalesce((select u.id from catalog.units u where u.code = v_step ->> 'equipment_capacity_unit' and u.deleted_at is null),
                               (select v.yield_unit_id from recipes.recipe_versions v where v.id = p_version_id)) end,
            nullif(btrim(v_step ->> 'control_point'), ''))
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  -- Dependencias por número de paso ("el 4 espera al 2 y al 3").
  v_n := 0;
  for v_step in select value from jsonb_array_elements(p_steps) loop
    v_n := v_n + 1;
    if v_step ? 'depends_on' and jsonb_typeof(v_step -> 'depends_on') = 'array' then
      for v_dep in select value from jsonb_array_elements(v_step -> 'depends_on') loop
        if (v_dep #>> '{}')::integer not between 1 and v_count or (v_dep #>> '{}')::integer = v_n then
          raise exception 'Paso %: solo puede esperar a otro paso de la lista.', v_n using errcode = '22023';
        end if;
        insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
        values (v_recipe.group_id, v_ids[v_n], v_ids[(v_dep #>> '{}')::integer])
        on conflict do nothing;
      end loop;
    end if;
  end loop;
  update recipes.recipe_versions set updated_at = now() where id = p_version_id;
  return jsonb_build_object('result', 'applied', 'message', format('Pasos guardados (%s).', v_count));
exception when check_violation or invalid_text_representation or numeric_value_out_of_range or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if sqlstate in ('22P02', '22003') then
    raise exception 'Paso %: algún dato no es válido.', v_n using errcode = '22023';
  end if;
  if v_constraint = 'recipe_steps_equipment_capacity_check' then
    raise exception 'Paso %: la capacidad del equipo tiene que ser un número mayor que cero y menor que mil millones.', v_n using errcode = '22023';
  elsif v_constraint = 'recipe_steps_capacity_unit_check' then
    raise exception 'Paso %: para cargar la capacidad, primero cargá el rendimiento de la receta.', v_n using errcode = '22023';
  elsif v_constraint = 'recipe_steps_capacity_equipment_check' then
    raise exception 'Paso %: para cargar la capacidad, escribí el equipo.', v_n using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
