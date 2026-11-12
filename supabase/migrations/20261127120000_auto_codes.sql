-- Códigos automáticos de recetas y materias primas (pedido de Soy, 2026-11-12; ADR-0041).
--
-- El código lo arma la base al crear: <TIPO>-<RUBRO>-<NNNN>.
--   TIPO:  PLA (plato), PRE (preparación) o MPR (materia prima).
--   RUBRO: las 3 letras del código del rubro del primer nivel (PL-CAF → CAF). Una subcategoría usa el de su rubro.
--   NNNN:  el siguiente número de ese tipo y rubro en el grupo; pasado 9999 sigue con 5 dígitos (decisión de Joaco).
-- Las variantes por local llevan el código de su maestra y -V01, -V02… (decisión de Joaco).
-- La importación del recetario no cambia: conserva el prefijo de la marca y el código del Excel (decisión de Joaco).
--
-- Solo aditiva sobre los datos: los códigos que ya existen no se tocan. Cambian las firmas de las tres funciones de
-- alta (ya no reciben el código) y desde ahora el código de una receta o de una materia prima no cambia nunca.

-- ---------------------------------------------------------------------------
-- 1. Contadores
-- ---------------------------------------------------------------------------
create table catalog.code_series (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references org.groups (id) on delete restrict,
  prefix       text not null check (prefix ~ '^[A-Z0-9][A-Z0-9-]{1,27}$'),
  last_number  integer not null default 0 check (last_number >= 0),
  created_at   timestamptz not null default now(),
  created_by   uuid references core.actors (id) on delete restrict,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references core.actors (id) on delete restrict,
  deleted_at   timestamptz,
  deleted_by   uuid references core.actors (id) on delete restrict,
  constraint code_series_prefix_key unique (group_id, prefix)
);
comment on table catalog.code_series is
  'Contadores de los códigos automáticos (ADR-0041): el último número usado por grupo y prefijo (PLA-CAF-, MPR-CAR-, PLA-PAS-0001-V). Nunca baja: un número de un registro borrado no se reutiliza. Solo la usan las funciones de alta.';
comment on column catalog.code_series.id is 'Identificador del contador.';
comment on column catalog.code_series.group_id is 'Grupo dueño de la numeración.';
comment on column catalog.code_series.prefix is 'Todo lo que va antes del número: «PLA-CAF-», «MPR-CAR-» o, en las variantes, «PLA-PAS-0001-V».';
comment on column catalog.code_series.last_number is 'Último número entregado con ese prefijo.';
comment on column catalog.code_series.created_at is 'Cuándo se entregó el primer número del prefijo (lo pone la base).';
comment on column catalog.code_series.created_by is 'Quién hizo el alta que abrió el contador (lo pone la base).';
comment on column catalog.code_series.updated_at is 'Cuándo se entregó el último número (lo pone la base).';
comment on column catalog.code_series.updated_by is 'Quién hizo el alta que tomó el último número (lo pone la base).';
comment on column catalog.code_series.deleted_at is 'Baja lógica. Un contador no se da de baja: los números nunca se reutilizan.';
comment on column catalog.code_series.deleted_by is 'Quién lo dio de baja (lo pone la base).';

alter table catalog.code_series enable row level security;
-- Sin políticas: nadie la lee ni la escribe directo; solo las funciones de alta (security definer).
revoke all on catalog.code_series from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on catalog.code_series
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on catalog.code_series
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on catalog.code_series
  for each statement execute function core.reject_truncate();

-- ---------------------------------------------------------------------------
-- 2. Generación
-- ---------------------------------------------------------------------------
-- Si un código ya está tomado (en recetas o materias primas del grupo, vigentes o borradas).
create function catalog.code_taken(p_group_id uuid, p_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from recipes.recipes where group_id = p_group_id and code = p_code)
      or exists (select 1 from catalog.ingredients where group_id = p_group_id and code = p_code)
$$;
comment on function catalog.code_taken(uuid, text) is
  'Interna: si un código ya lo usa una receta o una materia prima del grupo (vigente o borrada).';
revoke execute on function catalog.code_taken(uuid, text) from public;

-- El mayor número que ya existe con un prefijo (lo cargado a mano o antes de los contadores, también lo borrado).
create function catalog.code_highest(p_group_id uuid, p_prefix text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(substr(x.code, length(p_prefix) + 1)::integer), 0)
    from (select code from recipes.recipes where group_id = p_group_id
          union all
          select code from catalog.ingredients where group_id = p_group_id) x
   where starts_with(x.code, p_prefix)
     -- Hasta 5 dígitos: un código raro (por ejemplo, uno importado como PLA-CAF-999999999) no hace saltar la
     -- numeración; si choca, next_code lo saltea.
     and substr(x.code, length(p_prefix) + 1) ~ '^[0-9]{1,5}$'
$$;
comment on function catalog.code_highest(uuid, text) is
  'Interna: el mayor número (de hasta 5 dígitos) que ya usa un prefijo en recetas o materias primas del grupo (0 si ninguno).';
revoke execute on function catalog.code_highest(uuid, text) from public;

-- Arma el código: prefijo + número con el ancho pedido (más ancho si el número no entra: 9999 → 10000).
create function catalog.code_format(p_prefix text, p_number integer, p_width integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_prefix || lpad(p_number::text, greatest(p_width, length(p_number::text)), '0')
$$;
comment on function catalog.code_format(text, integer, integer) is
  'Interna: prefijo + número con ceros a la izquierda; si el número es más largo que el ancho, se escribe entero.';
revoke execute on function catalog.code_format(text, integer, integer) from public;

-- Entrega el siguiente código de un prefijo. El update toma un bloqueo de la fila del contador: dos altas
-- simultáneas esperan una a la otra y nunca reciben el mismo número. Si el alta falla, la transacción se deshace
-- y el número vuelve (no se perdió ninguno); si el registro se borra después, el número no se reutiliza.
create function catalog.next_code(p_group_id uuid, p_prefix text, p_width integer)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number integer;
  v_code   text;
begin
  loop
    update catalog.code_series set last_number = last_number + 1
     where group_id = p_group_id and prefix = p_prefix
    returning last_number into v_number;
    -- La primera vez del prefijo: se abre el contador desde lo que ya exista y se vuelve a intentar. Solo entonces
    -- se recorre lo cargado (code_highest); en las altas siguientes basta el update.
    if v_number is null then
      insert into catalog.code_series (group_id, prefix, last_number)
      values (p_group_id, p_prefix, catalog.code_highest(p_group_id, p_prefix))
      on conflict (group_id, prefix) do nothing;
      continue;
    end if;
    v_code := catalog.code_format(p_prefix, v_number, p_width);
    -- Salta un código ya usado (por ejemplo, uno cargado a mano con ese mismo formato).
    exit when not catalog.code_taken(p_group_id, v_code);
  end loop;
  if length(v_code) > 30 then
    raise exception 'El código % pasa los 30 caracteres.', v_code using errcode = '23514';
  end if;
  return v_code;
end
$$;
comment on function catalog.next_code(uuid, text, integer) is
  'Interna: entrega el siguiente código de un prefijo en el grupo, con bloqueo (sin repetidos) y sin reutilizar números.';
revoke execute on function catalog.next_code(uuid, text, integer) from public;

-- El código que saldría ahora, sin entregarlo (vista previa del alta).
create function catalog.peek_code(p_group_id uuid, p_prefix text, p_width integer)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_number integer;
  v_code   text;
begin
  select last_number into v_number from catalog.code_series where group_id = p_group_id and prefix = p_prefix;
  v_number := coalesce(v_number, catalog.code_highest(p_group_id, p_prefix));
  loop
    v_number := v_number + 1;
    v_code := catalog.code_format(p_prefix, v_number, p_width);
    exit when not catalog.code_taken(p_group_id, v_code);
  end loop;
  return v_code;
end
$$;
comment on function catalog.peek_code(uuid, text, integer) is
  'Interna: el código que entregaría next_code ahora, sin consumir el número.';
revoke execute on function catalog.peek_code(uuid, text, integer) from public;

-- Prefijo de una receta: PLA o PRE y las 3 letras de su rubro del primer nivel. Vacío sin rubro con código.
create function recipes.code_prefix(p_category_id uuid, p_type recipes.recipe_type)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_type = 'dish' then 'PLA-' else 'PRE-' end || split_part(t.code, '-', 2) || '-'
    from recipes.recipe_categories c
    join recipes.recipe_categories t on t.id = coalesce(c.parent_id, c.id)
   where c.id = p_category_id and t.code is not null
$$;
comment on function recipes.code_prefix(uuid, recipes.recipe_type) is
  'Interna: prefijo del código de una receta (PLA-CAF- o PRE-SAL-), con el rubro madre si la categoría es una subcategoría.';
revoke execute on function recipes.code_prefix(uuid, recipes.recipe_type) from public;

create function catalog.ingredient_code_prefix(p_category_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select 'MPR-' || split_part(t.code, '-', 2) || '-'
    from catalog.ingredient_categories c
    join catalog.ingredient_categories t on t.id = coalesce(c.parent_id, c.id)
   where c.id = p_category_id and t.code is not null
$$;
comment on function catalog.ingredient_code_prefix(uuid) is
  'Interna: prefijo del código de una materia prima (MPR-CAR-), con el rubro madre si la categoría es una subcategoría.';
revoke execute on function catalog.ingredient_code_prefix(uuid) from public;

-- ---------------------------------------------------------------------------
-- 3. Vista previa para el alta (no entrega el número)
-- ---------------------------------------------------------------------------
create function recipes.preview_code(p_category_id uuid, p_type recipes.recipe_type)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group  uuid;
  v_prefix text;
begin
  select group_id into v_group from recipes.recipe_categories where id = p_category_id and deleted_at is null;
  if v_group is null or p_type is null or p_type = 'unit_component'
     or not core.has_permission_in_group_any_scope('recipes.draft', v_group) then
    return null;
  end if;
  v_prefix := recipes.code_prefix(p_category_id, p_type);
  return case when v_prefix is null then null else catalog.peek_code(v_group, v_prefix, 4) end;
end
$$;
comment on function recipes.preview_code(uuid, recipes.recipe_type) is
  'Vista previa del código de una receta nueva para un rubro y un tipo (plato o preparación). No entrega el número: se confirma al crear. Sin recipes.draft en el grupo devuelve vacío.';
revoke execute on function recipes.preview_code(uuid, recipes.recipe_type) from public;
grant execute on function recipes.preview_code(uuid, recipes.recipe_type) to authenticated;

create function catalog.preview_ingredient_code(p_category_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group  uuid;
  v_prefix text;
begin
  select group_id into v_group from catalog.ingredient_categories where id = p_category_id and deleted_at is null;
  if v_group is null or not core.has_permission_in_group('catalog.manage', v_group) then
    return null;
  end if;
  v_prefix := catalog.ingredient_code_prefix(p_category_id);
  return case when v_prefix is null then null else catalog.peek_code(v_group, v_prefix, 4) end;
end
$$;
comment on function catalog.preview_ingredient_code(uuid) is
  'Vista previa del código de una materia prima nueva para un rubro. No entrega el número: se confirma al crear. Sin catalog.manage en el grupo devuelve vacío.';
revoke execute on function catalog.preview_ingredient_code(uuid) from public;
grant execute on function catalog.preview_ingredient_code(uuid) to authenticated;

-- Mensaje cuando el código que se mostró ya lo tomó otra alta.
create function catalog.code_message(p_what text, p_code text, p_expected text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_expected is not null and btrim(p_expected) <> '' and upper(btrim(p_expected)) <> p_code then
      format('%s creada con el código %s: el %s lo tomó otra alta mientras cargabas.', p_what, p_code,
             upper(btrim(p_expected)))
    else format('%s creada con el código %s.', p_what, p_code)
  end
$$;
comment on function catalog.code_message(text, text, text) is
  'Interna: mensaje del alta, que avisa si el código asignado no es el que se mostró en la vista previa.';
revoke execute on function catalog.code_message(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 4. Altas con código automático
-- ---------------------------------------------------------------------------
drop function recipes.create_recipe(uuid, uuid, uuid, text, text, recipes.recipe_type, uuid, text);

create function recipes.create_recipe(p_group_id uuid, p_brand_id uuid, p_restaurant_id uuid, p_name text,
                                      p_type recipes.recipe_type, p_category_id uuid, p_reason text,
                                      p_expected_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group      uuid := p_group_id;
  v_brand      uuid := p_brand_id;
  v_scope      recipes.recipe_scope;
  v_prefix     text;
  v_code       text;
  v_recipe     uuid;
  v_version    uuid;
  v_constraint text;
  v_message    text;
begin
  -- El alcance sale del lugar más chico indicado; marca y grupo se completan desde el local.
  if p_restaurant_id is not null then
    select r.brand_id, r.group_id into v_brand, v_group from org.restaurants r
     where r.id = p_restaurant_id and r.deleted_at is null;
    v_scope := 'restaurant';
  elsif p_brand_id is not null then
    select b.group_id into v_group from org.brands b where b.id = p_brand_id and b.deleted_at is null;
    v_scope := 'brand';
  else
    v_scope := 'group';
  end if;
  if v_group is null or (p_group_id is not null and v_group <> p_group_id)
     or not recipes.allowed('recipes.draft', v_group, v_brand, p_restaurant_id) then
    return core.deny('recipes.create_recipe', 'No tenés permiso para crear recetas en ese lugar.', null,
                     jsonb_build_object('group_id', p_group_id, 'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id),
                     v_group, v_brand, p_restaurant_id);
  end if;
  -- Solo platos y preparaciones (pedido de Soy): «componente por unidad» ya no se crea.
  if p_type is null or p_type = 'unit_component' then
    raise exception 'Elegí el tipo: plato o preparación.' using errcode = '22023';
  end if;
  if p_category_id is null
     or not exists (select 1 from recipes.recipe_categories where id = p_category_id and group_id = v_group and deleted_at is null) then
    raise exception 'Elegí el rubro de la receta.' using errcode = '22023';
  end if;
  v_prefix := recipes.code_prefix(p_category_id, p_type);
  if v_prefix is null then
    raise exception 'Ese rubro no tiene código: elegí otro.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  v_code := catalog.next_code(v_group, v_prefix, 4);
  insert into recipes.recipes (group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id)
  values (v_group, v_brand, p_restaurant_id, v_scope, v_code, btrim(p_name), p_type, p_category_id)
  returning id into v_recipe;
  insert into recipes.recipe_versions (group_id, recipe_id, version_number) values (v_group, v_recipe, 1)
  returning id into v_version;
  -- Una receta de local la usa su local desde hoy.
  if p_restaurant_id is not null then
    insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
    values (v_group, v_recipe, p_restaurant_id, recipes.today());
  end if;
  return jsonb_build_object('result', 'applied', 'id', v_recipe, 'version_id', v_version, 'code', v_code,
                            'code_changed', p_expected_code is not null and btrim(p_expected_code) <> ''
                                            and upper(btrim(p_expected_code)) <> v_code,
                            'message', catalog.code_message('Receta', v_code, p_expected_code));
exception when unique_violation or check_violation or foreign_key_violation or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint is null and sqlstate = '23502' then
    raise exception 'Falta el nombre.' using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.create_recipe(uuid, uuid, uuid, text, recipes.recipe_type, uuid, text, text) is
  'Crea una receta (plato o preparación, con rubro) y su versión 1 en borrador. El código lo arma la base (PLA-CAF-0001, ADR-0041); p_expected_code es el de la vista previa, para avisar si salió otro. El alcance es el lugar más chico indicado. Pide recipes.draft ahí y un motivo; sin permiso devuelve denied y queda registrado.';
revoke execute on function recipes.create_recipe(uuid, uuid, uuid, text, recipes.recipe_type, uuid, text, text) from public;
grant execute on function recipes.create_recipe(uuid, uuid, uuid, text, recipes.recipe_type, uuid, text, text) to authenticated;

drop function catalog.create_ingredient(uuid, text, text, uuid, text, jsonb, text);

create function catalog.create_ingredient(p_group_id uuid, p_name text, p_category_id uuid, p_recipe_unit text,
                                          p_details jsonb, p_reason text, p_expected_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_prefix     text;
  v_code       text;
  v_unit       uuid;
  v_id         uuid;
begin
  perform org.require(core.has_permission_in_group('catalog.manage', p_group_id), 'crear materias primas en este grupo');
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['purchase_unit', 'storage_unit', 'costing_unit', 'notes']);
  -- Una categoría borrada la frena el trigger de siempre, con su mensaje («Esa categoría está borrada»).
  if p_category_id is null
     or not exists (select 1 from catalog.ingredient_categories where id = p_category_id and group_id = p_group_id) then
    raise exception 'Elegí el rubro de la materia prima.' using errcode = '22023';
  end if;
  -- Se puede elegir cualquier medida (Kilogramo, Litro, Docena…): se guarda la base de su tipo (g, ml o unidad),
  -- que es en la que calcula el motor de costos (decisión de Joaco, ADR-0041). Los envases no tienen base.
  select b.id into v_unit
    from catalog.units u
    join catalog.units b on b.dimension = u.dimension and b.is_base and b.deleted_at is null
   where u.code = p_recipe_unit and u.deleted_at is null;
  if v_unit is null then
    raise exception 'Elegí una medida de peso, de volumen o de cantidad.' using errcode = '22023';
  end if;
  v_prefix := catalog.ingredient_code_prefix(p_category_id);
  if v_prefix is null then
    raise exception 'Ese rubro no tiene código: elegí otro.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  v_code := catalog.next_code(p_group_id, v_prefix, 4);
  insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id, purchase_unit_id, storage_unit_id,
                                   costing_unit_id, notes)
  values (p_group_id, v_code, btrim(p_name), p_category_id, v_unit,
          catalog.unit_id(nullif(p_details ->> 'purchase_unit', '')), catalog.unit_id(nullif(p_details ->> 'storage_unit', '')),
          catalog.unit_id(nullif(p_details ->> 'costing_unit', '')), nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'id', v_id, 'code', v_code,
                            'code_changed', p_expected_code is not null and btrim(p_expected_code) <> ''
                                            and upper(btrim(p_expected_code)) <> v_code,
                            'message', catalog.code_message('Materia prima', v_code, p_expected_code));
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_ingredient(uuid, text, uuid, text, jsonb, text, text) is
  'Crea una materia prima. El código lo arma la base (MPR-CAR-0001, ADR-0041); p_expected_code es el de la vista previa, para avisar si salió otro. p_recipe_unit: cualquier medida de peso, volumen o cantidad; se guarda la base de su tipo (g, ml o unidad). Pide catalog.manage en el grupo y un motivo. p_details: purchase_unit, storage_unit, costing_unit (códigos de unidad) y notes.';
revoke execute on function catalog.create_ingredient(uuid, text, uuid, text, jsonb, text, text) from public;
grant execute on function catalog.create_ingredient(uuid, text, uuid, text, jsonb, text, text) to authenticated;

drop function recipes.create_variant(uuid, uuid, text, text, text);

create function recipes.create_variant(p_master_id uuid, p_restaurant_id uuid, p_name text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m          recipes.recipes;
  v_mv         recipes.recipe_versions;
  v_rest       org.restaurants;
  v_code       text;
  v_recipe     uuid;
  v_version    uuid;
  v_constraint text;
  v_message    text;
begin
  select * into v_m from recipes.recipes where id = p_master_id and deleted_at is null;
  select * into v_rest from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_m.id is null or v_rest.id is null or not core.has_permission('recipes.approve', p_restaurant_id)
     or not (recipes.can_view_recipe(v_m.id) or recipes.can_work_recipe(v_m.id)) then
    return core.deny('recipes.create_variant', 'No tenés permiso para crear variantes en ese local.', null,
                     jsonb_build_object('recipe_id', p_master_id, 'restaurant_id', p_restaurant_id),
                     coalesce(v_m.group_id, v_rest.group_id), v_rest.brand_id, p_restaurant_id);
  end if;
  -- Recién con permiso se bloquea la maestra (para que no se archive mientras tanto).
  select * into v_m from recipes.recipes where id = v_m.id for share;
  if not v_m.is_active or v_m.scope_type = 'restaurant' or v_m.variant_of_recipe_id is not null then
    raise exception 'Solo se hacen variantes de una receta maestra del grupo o de una marca, activa.' using errcode = '23514';
  end if;
  if v_rest.group_id <> v_m.group_id or (v_m.scope_type = 'brand' and v_rest.brand_id <> v_m.brand_id) then
    raise exception 'Ese local no usa esa receta: está fuera de su alcance.' using errcode = '23514';
  end if;
  select * into v_mv from recipes.recipe_versions where recipe_id = v_m.id and status = 'published';
  if v_mv.id is null then
    raise exception 'La receta maestra no tiene una versión vigente.' using errcode = '23514';
  end if;
  -- El código de la maestra y -V01, -V02… (decisión de Joaco, ADR-0041).
  if length(v_m.code) + 4 > 30 then
    raise exception 'El código de la maestra es demasiado largo para sumarle -V01.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  v_code := catalog.next_code(v_m.group_id, v_m.code || '-V', 2);
  insert into recipes.recipes (group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id,
                               sector, station, variant_of_recipe_id)
  values (v_m.group_id, v_rest.brand_id, v_rest.id, 'restaurant', v_code, btrim(p_name), v_m.recipe_type,
          v_m.category_id, v_m.sector, v_m.station, v_m.id)
  returning id into v_recipe;
  insert into recipes.recipe_versions (group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions,
                                       portion_grams, description, storage_notes, presentation_notes, change_summary)
  values (v_m.group_id, v_recipe, 1, v_mv.yield_quantity, v_mv.yield_unit_id, v_mv.portions, v_mv.portion_grams,
          v_mv.description, v_mv.storage_notes, v_mv.presentation_notes,
          format('Variante de «%s» (v%s) para %s.', v_m.name, v_mv.version_number, v_rest.name))
  returning id into v_version;
  perform recipes.copy_version_content(v_mv.id, v_version);
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (v_m.group_id, v_recipe, v_rest.id, recipes.today());
  return jsonb_build_object('result', 'applied', 'id', v_recipe, 'version_id', v_version, 'code', v_code,
                            'message', format('Variante %s creada en borrador. Cuando se publique, el local deja de usar la maestra.', v_code));
exception when unique_violation or check_violation or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'recipes_variant_key' then
    raise exception 'Ese local ya tiene una variante de esta receta.' using errcode = '23505';
  elsif v_constraint is null and sqlstate = '23502' then
    raise exception 'Falta el nombre.' using errcode = '22023';
  elsif v_constraint is null then
    raise;
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.create_variant(uuid, uuid, text, text) is
  'Crea una variante local de una receta maestra (del grupo o de una marca): copia su vigente en un borrador y la asigna al local. El código es el de la maestra con -V01, -V02… (ADR-0041). Pide recipes.approve en ese local y un motivo; sin permiso devuelve denied y queda registrado.';
revoke execute on function recipes.create_variant(uuid, uuid, text, text) from public;
grant execute on function recipes.create_variant(uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. El código no cambia nunca
-- ---------------------------------------------------------------------------
-- En las recetas ya lo controla recipes.enforce_recipe_rules (ADR-0025). Faltaba en las materias primas.
create function catalog.guard_code()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.code is distinct from old.code then
    raise exception 'El código no cambia nunca.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function catalog.guard_code() is
  'Trigger (BEFORE UPDATE OF code) de ingredients: el código de una materia prima no cambia, ni siquiera si cambia el rubro (ADR-0041).';
revoke execute on function catalog.guard_code() from public;

create trigger guard_code before update of code on catalog.ingredients
  for each row execute function catalog.guard_code();
