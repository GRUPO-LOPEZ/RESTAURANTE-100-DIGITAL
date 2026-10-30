-- Configuración del catálogo: categorías y procesos de rendimiento (ADR-0022).
--
-- Hasta ahora las categorías solo las cargaba el seed, que no corre en staging ni en producción, y la base
-- exige una categoría en cada materia prima: fuera de desarrollo no se podía cargar ninguna. Las listas
-- las define el grupo desde la pantalla, nunca fijas en una migración.
--
-- Sin tablas nuevas: la auditoría, las columnas de control y los dos niveles de categoría ya los hacen los
-- triggers de 20261028120100_catalog.sql y 20261029120000_catalog_review_fixes.sql.

-- ---------------------------------------------------------------------------
-- 1. Mensajes en español: la misma función, con los casos de categorías y procesos
-- ---------------------------------------------------------------------------
create or replace function catalog.raise_friendly(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'ingredients_code_key' then 'Ya existe una materia prima con ese código en el grupo.'
    when p_constraint = 'ingredients_name_key' then 'Ya existe una materia prima con ese nombre en el grupo.'
    when p_constraint = 'suppliers_code_key' then 'Ya existe un proveedor con ese código en el grupo.'
    when p_constraint = 'suppliers_name_key' then 'Ya existe un proveedor con ese nombre en el grupo.'
    when p_constraint = 'purchase_products_code_key' then 'Ya existe un producto de compra con ese código en el grupo.'
    when p_constraint = 'ingredient_categories_name_key' then 'Ya existe una categoría con ese nombre en el mismo nivel.'
    when p_constraint = 'yield_processes_code_key' then 'Ya existe un proceso con ese código en el grupo.'
    when p_constraint = 'yield_processes_name_key' then 'Ya existe un proceso con ese nombre en el grupo.'
    when p_constraint like '%\_code\_check' then
      'El código va en mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).'
    when p_constraint in ('ingredients_name_check', 'suppliers_name_check') then
      'El nombre no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint in ('ingredient_categories_name_check', 'yield_processes_name_check') then
      'El nombre no puede quedar vacío ni pasar los 80 caracteres.'
    when p_constraint = 'purchase_products_description_check' then
      'La descripción no puede quedar vacía ni pasar los 200 caracteres.'
    when p_constraint = 'suppliers_tax_id_check' then 'El CUIT va solo con números y guiones.'
    when p_constraint = 'purchase_products_units_per_package_check' then 'Las unidades por envase van de 1 a 10.000.'
    when p_constraint in ('purchase_products_content_per_unit_check', 'ingredient_unit_conversions_factor_check') then
      'El valor tiene que ser mayor que cero.'
    when p_constraint like '%\_notes\_check' then 'Las observaciones son demasiado largas.'
    when p_state = '23503' then 'La categoría, el proveedor o la unidad elegidos no existen en este grupo.'
    else p_message
  end;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Categorías: catalog.manage para todo el grupo, como el resto del catálogo
-- ---------------------------------------------------------------------------

-- Nombre vacío o nulo: el mismo mensaje que el check de la tabla (un nulo daría el error en inglés).
create function catalog.require_name(p_name text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if nullif(btrim(p_name), '') is null then
    raise exception 'El nombre no puede quedar vacío ni pasar los 80 caracteres.' using errcode = '23514';
  end if;
end
$$;
comment on function catalog.require_name(text) is 'Interna: error en español si el nombre está vacío o es nulo.';
revoke execute on function catalog.require_name(text) from public;

-- Grupo de una categoría vigente, o error "sin permiso" (no revela si existe).
create function catalog.category_group(p_category_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from catalog.ingredient_categories where id = p_category_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('catalog.manage', v_group),
                      'editar esta categoría');
  return v_group;
end
$$;
comment on function catalog.category_group(uuid) is
  'Interna: grupo de la categoría vigente si la sesión tiene catalog.manage ahí; si no, "sin permiso".';
revoke execute on function catalog.category_group(uuid) from public;

create function catalog.create_category(p_group_id uuid, p_name text, p_reason text, p_parent_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('catalog.manage', p_group_id), 'crear categorías en este grupo');
  perform catalog.require_name(p_name);
  -- La madre tiene que ser una categoría vigente del mismo grupo. Se controla antes que los triggers
  -- para responder siempre lo mismo: no revela si el id existe en otro grupo ni de qué tipo es.
  if p_parent_id is not null
     and not exists (select 1 from catalog.ingredient_categories
                      where id = p_parent_id and group_id = p_group_id and deleted_at is null) then
    raise exception 'Elegí una categoría madre de este grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Los dos niveles y que la madre esté vigente los controlan los triggers de la tabla.
  insert into catalog.ingredient_categories (group_id, parent_id, name)
  values (p_group_id, p_parent_id, btrim(p_name))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_category(uuid, text, text, uuid) is
  'Crea una categoría, o una subcategoría si se indica la madre (solo dos niveles). Pide catalog.manage en el grupo y un motivo.';

create function catalog.rename_category(p_id uuid, p_name text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
begin
  perform catalog.category_group(p_id);
  perform catalog.require_name(p_name);
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredient_categories set name = btrim(p_name) where id = p_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.rename_category(uuid, text, text) is
  'Cambia el nombre de una categoría. Pide catalog.manage y un motivo.';

create function catalog.archive_category(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ingredients integer;
  v_children    integer;
begin
  perform catalog.category_group(p_id);
  -- Se bloquea la fila: quien le asigne una materia prima o una subcategoría en este momento espera
  -- (el trigger enforce_live_references la lee con "for share") y después ve la baja.
  perform 1 from catalog.ingredient_categories where id = p_id for update;
  select count(*) into v_ingredients from catalog.ingredients where category_id = p_id and deleted_at is null;
  if v_ingredients = 1 then
    raise exception 'Tiene 1 materia prima: pasala a otra categoría antes de darla de baja.' using errcode = '23514';
  elsif v_ingredients > 1 then
    raise exception 'Tiene % materias primas: pasalas a otra categoría antes de darla de baja.', v_ingredients
      using errcode = '23514';
  end if;
  select count(*) into v_children from catalog.ingredient_categories where parent_id = p_id and deleted_at is null;
  if v_children = 1 then
    raise exception 'Tiene 1 subcategoría: dala de baja antes.' using errcode = '23514';
  elsif v_children > 1 then
    raise exception 'Tiene % subcategorías: dalas de baja antes.', v_children using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredient_categories set deleted_at = now() where id = p_id;
end
$$;
comment on function catalog.archive_category(uuid, text) is
  'Da de baja una categoría (borrado lógico). Solo si no tiene materias primas ni subcategorías vigentes. Pide catalog.manage y un motivo.';

-- ---------------------------------------------------------------------------
-- 3. Procesos de rendimiento: yields.approve para todo el grupo, como create_yield_process
-- ---------------------------------------------------------------------------

-- Grupo de un proceso vigente, o error "sin permiso" (no revela si existe).
create function catalog.yield_process_group(p_process_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from catalog.yield_processes where id = p_process_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('yields.approve', v_group),
                      'editar este proceso');
  return v_group;
end
$$;
comment on function catalog.yield_process_group(uuid) is
  'Interna: grupo del proceso vigente si la sesión tiene yields.approve para todo el grupo; si no, "sin permiso".';
revoke execute on function catalog.yield_process_group(uuid) from public;

create function catalog.rename_yield_process(p_id uuid, p_name text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
begin
  perform catalog.yield_process_group(p_id);
  perform catalog.require_name(p_name);
  perform core.set_change_context(p_reason, 'manual');
  -- El código no cambia: lo usan las importaciones.
  update catalog.yield_processes set name = btrim(p_name) where id = p_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.rename_yield_process(uuid, text, text) is
  'Cambia el nombre de un proceso. El código no cambia. Pide yields.approve para todo el grupo y un motivo.';

create function catalog.archive_yield_process(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform catalog.yield_process_group(p_id);
  perform 1 from catalog.yield_processes where id = p_id for update;
  -- Los ensayos viejos quedan: son historia. Lo que lo bloquea es un estándar en uso o por decidir.
  if exists (select 1 from catalog.ingredient_yield_profiles where process_id = p_id and status = 'approved') then
    raise exception 'Tiene rendimientos estándar vigentes: no se puede dar de baja.' using errcode = '23514';
  end if;
  if exists (select 1
               from catalog.ingredient_yield_profiles p
               join workflow.approval_requests r on r.id = p.approval_request_id and r.status = 'pending'
              where p.process_id = p_id and p.status = 'draft') then
    raise exception 'Tiene propuestas de rendimiento en revisión: esperá a que se decidan.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.yield_processes set deleted_at = now() where id = p_id;
end
$$;
comment on function catalog.archive_yield_process(uuid, text) is
  'Da de baja un proceso (borrado lógico). Solo si no tiene estándares vigentes ni propuestas en revisión. Pide yields.approve para todo el grupo y un motivo.';

-- ---------------------------------------------------------------------------
-- 4. Nada nuevo apunta a algo dado de baja, tampoco en simultáneo
-- ---------------------------------------------------------------------------
-- La versión anterior leía la categoría sin bloquearla: si alguien la daba de baja en ese mismo
-- instante, una materia prima nueva podía quedar en una categoría dada de baja. Ahora se lee con
-- "for share": espera a que termine la baja y ve el resultado. Se suman los procesos de rendimiento
-- (propuestas y ensayos), por la misma razón.
create or replace function catalog.enforce_live_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted timestamptz;
begin
  -- Solo cuando la referencia es nueva o cambia: editar otra cosa (o desactivar un producto) nunca
  -- se frena porque la categoría o el proveedor de siempre ya no esté vigente.
  -- (Una rama por tabla: cada una solo nombra columnas que esa tabla tiene.)
  if tg_table_name = 'ingredients' then
    if tg_op = 'INSERT' or new.category_id is distinct from old.category_id then
      select deleted_at into v_deleted from catalog.ingredient_categories where id = new.category_id for share;
      if v_deleted is not null then
        raise exception 'Esa categoría está borrada: elegí otra.' using errcode = '23514';
      end if;
    end if;
  elsif tg_table_name = 'purchase_products' then
    if (tg_op = 'INSERT' or new.supplier_id is distinct from old.supplier_id) and new.supplier_id is not null then
      select deleted_at into v_deleted from catalog.suppliers where id = new.supplier_id for share;
      if v_deleted is not null then
        raise exception 'Ese proveedor está borrado: elegí otro.' using errcode = '23514';
      end if;
    end if;
  elsif tg_table_name = 'ingredient_categories' then
    if (tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id) and new.parent_id is not null then
      select deleted_at into v_deleted from catalog.ingredient_categories where id = new.parent_id for share;
      if v_deleted is not null then
        raise exception 'La categoría madre está borrada: elegí otra.' using errcode = '23514';
      end if;
    end if;
  elsif tg_table_name in ('ingredient_yield_profiles', 'ingredient_yield_tests') then
    -- Solo inserción: los perfiles y los ensayos no cambian de proceso.
    if tg_op = 'INSERT' then
      select deleted_at into v_deleted from catalog.yield_processes where id = new.process_id for share;
      if v_deleted is not null then
        raise exception 'Ese proceso está dado de baja: elegí otro.' using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.enforce_live_references() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredients, purchase_products, ingredient_categories, ingredient_yield_profiles e ingredient_yield_tests: no se apunta a una categoría, categoría madre, proveedor o proceso dados de baja. Bloquea la fila referida (for share) para no cruzarse con una baja en curso.';
create trigger validate_live_process before insert on catalog.ingredient_yield_profiles
  for each row execute function catalog.enforce_live_references();
create trigger validate_live_process before insert on catalog.ingredient_yield_tests
  for each row execute function catalog.enforce_live_references();

-- ---------------------------------------------------------------------------
-- 5. Lectura para la pantalla: cuánto se usa cada categoría y cada proceso
-- ---------------------------------------------------------------------------
-- Con los permisos de quien consulta (RLS): cuenta solo lo que ve. Se cuenta en la base porque la API
-- devuelve hasta 1.000 filas por consulta.
create function catalog.category_usage()
returns table (category_id uuid, ingredients bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select i.category_id, count(*) from catalog.ingredients i where i.deleted_at is null group by i.category_id
$$;
comment on function catalog.category_usage() is
  'Cuántas materias primas vigentes tiene cada categoría, entre las que ve la sesión. Para la pantalla de configuración.';

create function catalog.process_usage()
returns table (process_id uuid, standards bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.process_id, count(*) from catalog.ingredient_yield_profiles p where p.status = 'approved' and p.deleted_at is null group by p.process_id
$$;
comment on function catalog.process_usage() is
  'Cuántos rendimientos estándar vigentes tiene cada proceso, entre los que ve la sesión. Para la pantalla de configuración.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'catalog.category_usage()',
    'catalog.process_usage()',
    'catalog.create_category(uuid, text, text, uuid)',
    'catalog.rename_category(uuid, text, text)',
    'catalog.archive_category(uuid, text)',
    'catalog.rename_yield_process(uuid, text, text)',
    'catalog.archive_yield_process(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
