-- «+ Nueva materia prima» desde la receta (Tanda 2 de Soy, PR B; ADR-0064).
--   * Permiso nuevo catalog.create_ingredients, para todo el grupo: Compras, Superadministrador y Chef Ejecutivo (decisión de
--     Joaco, 2026-11-24). La Directora de Marca lo tiene por la regla G2, pero con rol de marca no crea.
--     Crea solo nombre, rubro y unidad de uso, sin precio. Lo demás sigue pidiendo catalog.manage.
--   * Si la crea alguien que no administra el catálogo, quienes lo administran reciben un aviso para completarla.
--   * Antes de crear se muestran las parecidas (catalog.similar_ingredients): menos repetidas.

do $$
begin
  perform core.set_change_context('Permiso para crear una materia prima desde la receta (ADR-0064)', 'maintenance');
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('catalog.create_ingredients', 'catalog', 'create_ingredients', 'Crear materias primas', 30,
     'Crear una materia prima desde una receta, para todo el grupo: nombre, rubro y unidad de uso, sin precio. Completarla y editarla pide Editar el catálogo.',
     false);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values ('purchasing'), ('executive_chef'),
                 -- Regla G2: quien administra personas tiene los permisos de los roles que administra. La Directora de
                 -- Marca administra al Chef Ejecutivo (decisión de Joaco, 2026-11-24); con rol de marca no crea: se
                 -- pide para todo el grupo.
                 ('superadmin'), ('brand_director')) as v (role_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = 'catalog.create_ingredients' and p.deleted_at is null;
end
$$;

-- Si una categoría (o su rubro) va a recetas. La misma regla que catalog.ingredient_used_in_recipes.
create function catalog.category_used_in_recipes(p_category_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(top.used_in_recipes, c.used_in_recipes)
    from catalog.ingredient_categories c
    left join catalog.ingredient_categories top on top.id = c.parent_id
   where c.id = p_category_id
$$;
comment on function catalog.category_used_in_recipes(uuid) is 'Interna: si una categoría de materias primas (o su rubro) va a recetas.';
revoke execute on function catalog.category_used_in_recipes(uuid) from public;

create or replace function catalog.create_ingredient(p_group_id uuid, p_name text, p_category_id uuid, p_recipe_unit text,
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
  v_manage     boolean := core.has_permission_in_group('catalog.manage', p_group_id);
  v_name       text := btrim(regexp_replace(replace(p_name, chr(160), ' '), '\s+', ' ', 'g'));
begin
  -- Desde la receta alcanza con catalog.create_ingredients: sin datos extra y en un rubro que va a recetas.
  perform org.require(v_manage
                      or (core.has_permission_in_group('catalog.create_ingredients', p_group_id)
                          and coalesce(p_details, '{}'::jsonb) = '{}'::jsonb
                          and coalesce(catalog.category_used_in_recipes(p_category_id), true)),
                      'crear materias primas en este grupo');
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['purchase_unit', 'storage_unit', 'costing_unit', 'notes']);
  -- El nombre entra limpio (viaja en avisos e imita a otros si lleva lo que no se ve): acá, para todas las altas.
  if v_name ~ '[<>]' or core.has_hidden_characters(v_name) then
    raise exception 'El nombre lleva < o > o caracteres que no se ven: escribilo de nuevo.' using errcode = '22023';
  end if;
  if not v_manage then
    if p_reason is null or length(btrim(p_reason)) not between 3 and 500 then
      raise exception 'Escribí el motivo (de 3 a 500 caracteres).' using errcode = '22023';
    end if;
    -- Cada una avisa a Compras: hasta 30 por hora por persona (de a una, para que pedidos simultáneos no lo salteen).
    perform pg_advisory_xact_lock(hashtextextended('catalog.create_ingredient:' || core.current_actor_id(), 0));
    if (select count(*) from catalog.ingredients where created_by = core.current_actor_id() and created_at > now() - interval '1 hour') >= 30 then
      raise exception 'Creaste muchas materias primas en la última hora: probá más tarde o pedíselas a Compras.' using errcode = '23514';
    end if;
  end if;
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
  values (p_group_id, v_code, v_name, p_category_id, v_unit,
          catalog.unit_id(nullif(p_details ->> 'purchase_unit', '')), catalog.unit_id(nullif(p_details ->> 'storage_unit', '')),
          catalog.unit_id(nullif(p_details ->> 'costing_unit', '')), nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  -- La cocina no la puede completar: le avisa a quien administra el catálogo de todo el grupo.
  if not v_manage then
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u.user_id, p_group_id, 'ingredient_created', left(format('Materia prima nueva: «%s»', v_name), 200),
           left(format('La creó %s desde una receta (%s). Falta completarla: proveedor, producto de compra y precio.',
                       coalesce(core.display_name(core.current_actor_id()), 'alguien de la cocina'), v_code), 500),
           format('/materias-primas/%s', v_id)
      from (select distinct a.user_id from core.user_role_assignments a
             where a.group_id = p_group_id and a.deleted_at is null and a.scope_type = 'group'
               and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())) u
     where u.user_id is distinct from core.current_actor_id()
       and core.user_has_permission_for_scope(u.user_id, 'catalog.manage', 'group', p_group_id, null, null);
  end if;
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
  'Crea una materia prima con su código automático. Pide catalog.manage para todo el grupo, o catalog.create_ingredients si no lleva datos extra y va en un rubro de recetas (desde la ficha de receta): en ese caso les avisa a quienes administran el catálogo.';

-- Desde la receta: deja registrado el rechazo.
create function catalog.quick_ingredient(p_group_id uuid, p_name text, p_category_id uuid, p_recipe_unit text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(regexp_replace(replace(p_name, chr(160), ' '), '\s+', ' ', 'g'));
begin
  if not core.current_session_ok()
     or not (core.has_permission_in_group('catalog.create_ingredients', p_group_id)
             or core.has_permission_in_group('catalog.manage', p_group_id)) then
    return core.deny('catalog.quick_ingredient', 'No tenés permiso para crear materias primas.', null, null,
                     (select g from core.visible_group_ids('catalog.view') g where g = p_group_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 3 and 500 then
    raise exception 'Escribí el motivo (de 3 a 500 caracteres).' using errcode = '22023';
  end if;
  if v_name is null or v_name = '' then
    raise exception 'Escribí el nombre de la materia prima.' using errcode = '22023';
  end if;
  if not exists (select 1 from catalog.ingredient_categories
                  where id = p_category_id and group_id = p_group_id and deleted_at is null)
     or not catalog.category_used_in_recipes(p_category_id) then
    raise exception 'Elegí un rubro que vaya a recetas.' using errcode = '22023';
  end if;
  return catalog.create_ingredient(p_group_id, v_name, p_category_id, p_recipe_unit, '{}'::jsonb, p_reason, null);
end
$$;
comment on function catalog.quick_ingredient(uuid, text, uuid, text, text) is
  'Crea una materia prima desde la ficha de receta: nombre, rubro que va a recetas y unidad de uso, sin precio. Pide catalog.create_ingredients o catalog.manage para todo el grupo; el rechazo queda registrado.';
revoke execute on function catalog.quick_ingredient(uuid, text, uuid, text, text) from public, anon;
grant execute on function catalog.quick_ingredient(uuid, text, uuid, text, text) to authenticated;

-- «¿Es esta?»: las activas con un nombre o un alias parecido. Solo para quien ve el catálogo del grupo.
create function catalog.similar_ingredients(p_group_id uuid, p_name text)
returns table (id uuid, code text, name text, unit text, dimension catalog.dimension)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  -- Antes de consultar: un texto enorme no llega a compararse con cada materia prima.
  if p_name is null or length(p_name) > 120 or length(btrim(p_name)) < 3
     or not exists (select 1 from core.visible_group_ids('catalog.view') g where g = p_group_id) then
    return;
  end if;
  v_key := catalog.list_key(p_name);
  return query
    with named as materialized (
      select i.id, i.code, i.name, i.recipe_unit_id, catalog.list_key(i.name) as key
        from catalog.ingredients i
        join catalog.ingredient_categories c on c.id = i.category_id
        left join catalog.ingredient_categories top on top.id = c.parent_id
       where i.group_id = p_group_id and i.is_active and i.deleted_at is null and coalesce(top.used_in_recipes, c.used_in_recipes, true)),
    aliased as materialized (
      select distinct a.ingredient_id from catalog.ingredient_aliases a
       where a.group_id = p_group_id and a.deleted_at is null and catalog.list_key(a.alias) = v_key),
    scored as materialized (
      select n.*, extensions.similarity(n.key, v_key) as score from named n)
    select s.id, s.code, s.name, u.code, u.dimension
      from scored s join catalog.units u on u.id = s.recipe_unit_id
     where s.key = v_key or s.score > 0.45 or s.id in (select ingredient_id from aliased)
     order by s.score desc, s.name
     limit 3;
end
$$;
comment on function catalog.similar_ingredients(uuid, text) is
  'Hasta 3 materias primas activas del grupo con un nombre o un alias parecido, para no crear una repetida. Solo para quien ve el catálogo del grupo.';
revoke execute on function catalog.similar_ingredients(uuid, text) from public, anon;
grant execute on function catalog.similar_ingredients(uuid, text) to authenticated;
