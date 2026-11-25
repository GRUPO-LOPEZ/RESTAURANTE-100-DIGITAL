-- Ficha del rubro (pedido de Soy, Tanda 2, punto D; ADR-0066): cada rubro lleva un ícono de un set fijo y una
-- descripción, y se edita entero en una transacción, con motivo.
--
-- * catalog.category_icon: los íconos posibles. Cada rubro tiene uno (si no se elige, el de su código); las
--   subcategorías, ninguno.
-- * recipes.save_top_category: nombre, descripción, ícono y «va a recetas» juntos, con el sello del último cambio.
-- * recipes.top_category_sheet: los datos y los indicadores de la ficha, con los permisos de quien consulta.
-- * costing.category_price_summary: cuántas materias primas del rubro tienen el precio al día en un local, con el mismo
--   cálculo del motor (costing.price_rows). Pide prices.view en el local.
-- Los permisos no cambian: los de recipes.can_manage_category.

-- ---------------------------------------------------------------------------
-- 1. Ícono y descripción
-- ---------------------------------------------------------------------------
create type catalog.category_icon as enum ('vegetable', 'meat', 'fish', 'dairy', 'flour', 'oil', 'herb', 'pantry', 'drink',
                                           'cleaning', 'packaging', 'preparation', 'dish', 'dessert');
comment on type catalog.category_icon is
  'Ícono de un rubro: verdura, carne, pescado, lácteos y huevos, harinas, aceites, hierbas y especias, almacén, bebidas, limpieza, descartables, preparación, plato o postre.';

-- El ícono de entrada según el código (MP-CAR → carne). Si no lo reconoce, el genérico de su clase.
create function catalog.default_category_icon(p_code text)
returns catalog.category_icon
language sql
immutable
set search_path = ''
as $$
  select (case
    when p_code in ('MP-VER', 'MP-FRU', 'PL-ENS', 'PL-VEG') then 'vegetable'
    when p_code in ('MP-CAR', 'MP-FIA', 'PL-CAR') then 'meat'
    when p_code in ('MP-PES', 'PL-PES') then 'fish'
    when p_code in ('MP-LAC', 'MP-HUE') then 'dairy'
    when p_code in ('MP-HAR', 'MP-PAS', 'SR-MAS', 'SR-PAN', 'PL-PAS') then 'flour'
    when p_code = 'MP-ACE' then 'oil'
    when p_code in ('MP-HIE', 'MP-ESP') then 'herb'
    when p_code in ('MP-BEB', 'MP-VIN', 'MP-CAF', 'SR-BAR', 'PL-BEB', 'PL-VIN', 'PL-CAF') then 'drink'
    when p_code = 'MP-LIM' then 'cleaning'
    when p_code = 'MP-DES' then 'packaging'
    when p_code in ('MP-DUL', 'SR-PST', 'PL-POS') then 'dessert'
    when p_code like 'SR-%' then 'preparation'
    when p_code like 'PL-%' then 'dish'
    else 'pantry' end)::catalog.category_icon
$$;
comment on function catalog.default_category_icon(text) is
  'Interna: el ícono de entrada de un rubro según su código; si no lo reconoce, el genérico de su clase (almacén, preparación o plato).';
revoke execute on function catalog.default_category_icon(text) from public;

alter table catalog.ingredient_categories
  add column icon        catalog.category_icon,
  add column description text;
comment on column catalog.ingredient_categories.icon is 'Ícono del rubro, solo en el primer nivel. Si no se elige, el de su código.';
comment on column catalog.ingredient_categories.description is 'Qué entra en el rubro y cómo se controla, solo en el primer nivel (hasta 500 caracteres).';

alter table recipes.recipe_categories
  add column icon        catalog.category_icon,
  add column description text;
comment on column recipes.recipe_categories.icon is 'Ícono del rubro, solo en el primer nivel. Si no se elige, el de su código.';
comment on column recipes.recipe_categories.description is 'Qué entra en el rubro, solo en el primer nivel (hasta 500 caracteres).';

-- Los rubros que ya existen, con su auditoría. También los borrados: si no, restaurar uno completaría el ícono en el mismo
-- cambio y la regla «un registro borrado no se edita» lo rechazaría. Solo para esos se apaga, acá, ese control.
do $$
begin
  perform core.set_change_context('Ícono de los rubros según su código (ADR-0066)', 'maintenance');
  update catalog.ingredient_categories set icon = catalog.default_category_icon(code)
   where parent_id is null and deleted_at is null;
  update recipes.recipe_categories set icon = catalog.default_category_icon(code)
   where parent_id is null and deleted_at is null;
  alter table catalog.ingredient_categories disable trigger set_control_columns;
  alter table recipes.recipe_categories disable trigger set_control_columns;
  update catalog.ingredient_categories set icon = catalog.default_category_icon(code)
   where parent_id is null and deleted_at is not null and code is not null;
  update recipes.recipe_categories set icon = catalog.default_category_icon(code)
   where parent_id is null and deleted_at is not null and code is not null;
  alter table catalog.ingredient_categories enable trigger set_control_columns;
  alter table recipes.recipe_categories enable trigger set_control_columns;
end
$$;

alter table catalog.ingredient_categories
  -- Para lo vigente, como el código: lo borrado antes queda como estaba.
  add constraint ingredient_categories_icon_level check (deleted_at is not null or (parent_id is null) = (icon is not null)),
  add constraint ingredient_categories_description_check check (
    description is null or (parent_id is null and description ~ '\S' and length(description) <= 500));
alter table recipes.recipe_categories
  add constraint recipe_categories_icon_level check (deleted_at is not null or (parent_id is null) = (icon is not null)),
  add constraint recipe_categories_description_check check (
    description is null or (parent_id is null and description ~ '\S' and length(description) <= 500));

-- Los triggers de siempre (ADR-0038) completan también el ícono.
create or replace function catalog.enforce_rubro_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_active boolean;
begin
  if tg_op = 'UPDATE' and old.code is not null and new.code is distinct from old.code then
    raise exception 'El código de un rubro no cambia.' using errcode = '42501';
  end if;
  if new.parent_id is not null then
    if tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id then
      -- Con «for share»: si el rubro se está dando de baja, espera y después ve la baja.
      select is_active into v_parent_active from catalog.ingredient_categories where id = new.parent_id for share;
      if v_parent_active is false then
        raise exception 'Ese rubro está dado de baja: elegí otro.' using errcode = '23514';
      end if;
    end if;
  elsif new.code is null then
    new.code := catalog.free_category_code('MP', new.name,
      array(select code from catalog.ingredient_categories
             where group_id = new.group_id and code is not null and id <> new.id));
  end if;
  if new.parent_id is null and new.icon is null then
    new.icon := catalog.default_category_icon(new.code);
  end if;
  return new;
end
$$;
comment on function catalog.enforce_rubro_fields() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredient_categories: el código del rubro se genera solo (sin reutilizar el de uno borrado) y no cambia; si no tiene ícono, el de su código; no se cuelga una subcategoría de un rubro dado de baja.';

create or replace function recipes.enforce_rubro_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent recipes.recipe_categories;
begin
  if tg_op = 'UPDATE' and old.code is not null and new.code is distinct from old.code then
    raise exception 'El código de un rubro no cambia.' using errcode = '42501';
  end if;
  if new.parent_id is not null then
    -- Con «for share»: si el rubro se está dando de baja, espera y después ve la baja.
    select * into v_parent from recipes.recipe_categories where id = new.parent_id for share;
    new.kind := v_parent.kind;
    if (tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id) and v_parent.is_active is false then
      raise exception 'Ese rubro está dado de baja: elegí otro.' using errcode = '23514';
    end if;
  else
    if new.kind is null then
      raise exception 'Elegí la clase del rubro: sub-recetas o menú.' using errcode = '23514';
    end if;
    if new.code is null then
      new.code := catalog.free_category_code(case new.kind when 'menu' then 'PL' else 'SR' end, new.name,
        array(select code from recipes.recipe_categories
               where group_id = new.group_id and code is not null and id <> new.id));
    end if;
    if new.icon is null then
      new.icon := catalog.default_category_icon(new.code);
    end if;
  end if;
  if tg_op = 'UPDATE' and old.kind is not null and new.kind is distinct from old.kind then
    raise exception 'La clase de un rubro no cambia.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function recipes.enforce_rubro_fields() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipe_categories: la subcategoría hereda la clase de su rubro; el código se genera solo; si no tiene ícono, el de su código; código y clase no cambian; no se cuelga una subcategoría de un rubro dado de baja.';

-- ---------------------------------------------------------------------------
-- 2. Lectura
-- ---------------------------------------------------------------------------
create or replace view recipes.top_categories with (security_invoker = true) as
  select 'purchase'::recipes.category_class as category_class, c.id, c.group_id, c.code, c.name, c.is_active,
         c.created_at, c.updated_at, c.icon, c.description
    from catalog.ingredient_categories c
   where c.parent_id is null and c.deleted_at is null
  union all
  select c.kind, c.id, c.group_id, c.code, c.name, c.is_active, c.created_at, c.updated_at, c.icon, c.description
    from recipes.recipe_categories c
   where c.parent_id is null and c.deleted_at is null;
comment on column recipes.top_categories.icon is 'Ícono del rubro.';
comment on column recipes.top_categories.description is 'Descripción del rubro.';

-- El panel suma el ícono.
drop function recipes.category_overview(uuid);
create function recipes.category_overview(p_group_id uuid)
returns table (category_class recipes.category_class, id uuid, code text, name text, is_active boolean,
               uses bigint, mismatched bigint, used_in_recipes boolean, icon catalog.category_icon)
language sql
stable
security invoker
set search_path = ''
as $$
  with ing as (
    select coalesce(c.parent_id, c.id) as top_id, count(*) as uses
      from catalog.ingredients i
      join catalog.ingredient_categories c on c.id = i.category_id
     where i.group_id = p_group_id and i.deleted_at is null
     group by 1),
  rec as (
    select coalesce(c.parent_id, c.id) as top_id, count(*) as uses,
           count(*) filter (where (r.recipe_type = 'dish') <> (c.kind = 'menu')) as mismatched
      from recipes.recipes r
      join recipes.recipe_categories c on c.id = r.category_id
     where r.group_id = p_group_id and r.deleted_at is null
     group by 1)
  select 'purchase'::recipes.category_class, c.id, c.code, c.name, c.is_active, coalesce(ing.uses, 0), 0::bigint,
         c.used_in_recipes, c.icon
    from catalog.ingredient_categories c
    left join ing on ing.top_id = c.id
   where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
  union all
  select c.kind, c.id, c.code, c.name, c.is_active, coalesce(rec.uses, 0), coalesce(rec.mismatched, 0), true, c.icon
    from recipes.recipe_categories c
    left join rec on rec.top_id = c.id
   where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null
$$;
comment on function recipes.category_overview(uuid) is
  'Panel de Rubros: cada rubro del grupo con su clase, código, nombre, si está activo, cuántos usos tiene (materias primas o recetas, sumando subcategorías), cuántas recetas están en un rubro de la otra clase, si va a recetas (solo en los de compra; los demás, sí) y su ícono. Con los permisos de quien consulta.';
revoke execute on function recipes.category_overview(uuid) from public;
grant execute on function recipes.category_overview(uuid) to authenticated;

-- La ficha de un rubro. Los números son de lo que ve quien consulta (RLS). null si no lo ve.
create function recipes.top_category_sheet(p_class recipes.category_class, p_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case when p_class = 'purchase' then (
    select jsonb_build_object(
             'id', c.id, 'group_id', c.group_id, 'code', c.code, 'name', c.name, 'icon', c.icon, 'description', c.description,
             'is_active', c.is_active, 'used_in_recipes', c.used_in_recipes, 'stamp', c.updated_at,
             'subcategories', coalesce((
               select jsonb_agg(s.name order by lower(s.name)) from catalog.ingredient_categories s
                where s.parent_id = c.id and s.deleted_at is null and s.is_active), '[]'::jsonb),
             'ingredients', (
               select jsonb_build_object('total', count(*), 'active', count(*) filter (where i.is_active))
                 from catalog.ingredients i
                where i.deleted_at is null
                  and i.category_id in (select x.id from catalog.ingredient_categories x where x.id = c.id or x.parent_id = c.id)),
             'recipes', (
               select jsonb_build_object('total', count(distinct v.recipe_id),
                                         'published', count(distinct v.recipe_id) filter (where v.status = 'published'))
                 from catalog.ingredients i
                 join recipes.recipe_components l on l.ingredient_id = i.id and l.deleted_at is null
                 join recipes.recipe_versions v on v.id = l.recipe_version_id and v.status in ('published', 'draft', 'in_review')
                where i.deleted_at is null
                  and i.category_id in (select x.id from catalog.ingredient_categories x where x.id = c.id or x.parent_id = c.id)))
      from catalog.ingredient_categories c
     where c.id = p_id and c.parent_id is null and c.deleted_at is null)
  else (
    select jsonb_build_object(
             'id', c.id, 'group_id', c.group_id, 'code', c.code, 'name', c.name, 'icon', c.icon, 'description', c.description,
             'is_active', c.is_active, 'used_in_recipes', true, 'stamp', c.updated_at,
             'subcategories', coalesce((
               select jsonb_agg(s.name order by lower(s.name)) from recipes.recipe_categories s
                where s.parent_id = c.id and s.deleted_at is null and s.is_active), '[]'::jsonb),
             'recipes', (
               select jsonb_build_object(
                        'total', count(*),
                        'published', count(*) filter (where exists (
                          select 1 from recipes.recipe_versions v where v.recipe_id = r.id and v.status = 'published')),
                        'open', count(*) filter (where exists (
                          select 1 from recipes.recipe_versions v where v.recipe_id = r.id and v.status in ('draft', 'in_review'))))
                 from recipes.recipes r
                where r.deleted_at is null
                  and r.category_id in (select x.id from recipes.recipe_categories x where x.id = c.id or x.parent_id = c.id)))
      from recipes.recipe_categories c
     where c.id = p_id and c.parent_id is null and c.deleted_at is null and c.kind = p_class)
  end
$$;
comment on function recipes.top_category_sheet(recipes.category_class, uuid) is
  'La ficha de un rubro: sus datos, el sello del último cambio, sus subcategorías activas y los indicadores (compra: materias primas y recetas que las usan; sub-recetas y menú: recetas, publicadas y con una versión abierta). Con los permisos de quien consulta; null si no lo ve.';
revoke execute on function recipes.top_category_sheet(recipes.category_class, uuid) from public;
grant execute on function recipes.top_category_sheet(recipes.category_class, uuid) to authenticated;

-- «Con precio al día»: el mismo cálculo del motor, en una pasada. Solo las materias primas activas.
create function costing.category_price_summary(p_category_id uuid, p_restaurant_id uuid)
returns table (total bigint, current bigint, stale bigint, missing bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select count(*),
         count(*) filter (where r.status = 'ok' and not r.stale),
         count(*) filter (where r.status = 'ok' and r.stale),
         count(*) filter (where r.status <> 'ok')
    from catalog.ingredients i
    join catalog.ingredient_categories c on c.id = i.category_id and (c.id = p_category_id or c.parent_id = p_category_id)
    join costing.price_rows(p_restaurant_id, recipes.today(), null) r on r.ingredient_id = i.id
   where i.deleted_at is null and i.is_active
     and core.has_permission('prices.view', p_restaurant_id)
  -- Sin permiso, ninguna fila (no un cero, que se leería como «ninguna al día»).
  having core.has_permission('prices.view', p_restaurant_id)
$$;
comment on function costing.category_price_summary(uuid, uuid) is
  'De las materias primas activas de un rubro (con sus subcategorías), cuántas tienen el precio al día en un local, cuántas desactualizado y a cuántas les falta un dato. Mismo cálculo del motor. Pide prices.view en el local; si no, ninguna fila.';
revoke execute on function costing.category_price_summary(uuid, uuid) from public;
grant execute on function costing.category_price_summary(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Escritura
-- ---------------------------------------------------------------------------
-- La ficha entera en una transacción, con motivo (como las demás fichas). p_changes trae solo lo que cambió.
create function recipes.save_top_category(p_class recipes.category_class, p_id uuid, p_expected_stamp timestamptz,
                                          p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group      uuid;
  v_stamp      timestamptz;
  v_name       text;
  v_text       text;
  v_icon       catalog.category_icon;
  v_constraint text;
  v_message    text;
begin
  -- Se busca acá (y no con recipes.top_category_group, que corta con error): así el rechazo queda registrado. Dos
  -- guardados del mismo rubro van de a uno.
  if p_class = 'purchase' then
    select group_id into v_group from catalog.ingredient_categories
     where id = p_id and parent_id is null and deleted_at is null;
  else
    select group_id into v_group from recipes.recipe_categories
     where id = p_id and parent_id is null and deleted_at is null and kind = p_class;
  end if;
  if v_group is null or not recipes.can_manage_category(p_class, v_group) then
    return core.deny('recipes.save_top_category', 'No tenés permiso para editar este rubro.', null,
                     jsonb_build_object('category_id', p_id, 'class', p_class), v_group);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, case when p_class = 'purchase' then array['name', 'description', 'icon', 'used_in_recipes']
                                         else array['name', 'description', 'icon'] end);
  if p_changes = '{}'::jsonb then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  if p_class = 'purchase' then
    select updated_at into v_stamp from catalog.ingredient_categories where id = p_id and deleted_at is null for update;
  else
    select updated_at into v_stamp from recipes.recipe_categories where id = p_id and deleted_at is null for update;
  end if;
  if p_expected_stamp is null or v_stamp is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió este rubro mientras lo editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;

  if (p_changes ? 'name' and jsonb_typeof(p_changes -> 'name') <> 'string')
     or (p_changes ? 'description' and jsonb_typeof(p_changes -> 'description') not in ('string', 'null')) then
    raise exception 'El nombre y la descripción van como texto.' using errcode = '22023';
  end if;
  v_name := p_changes ->> 'name';
  if p_changes ? 'name' then
    perform catalog.require_name(v_name);
  end if;
  -- Sin espacios ni renglones de más en las puntas.
  v_text := nullif(regexp_replace(p_changes ->> 'description', '^\s+|\s+$', '', 'g'), '');
  if length(v_text) > 500 then
    raise exception 'La descripción va hasta 500 caracteres.' using errcode = '22023';
  end if;
  if p_changes ? 'icon' then
    if p_changes ->> 'icon' is null or not (p_changes ->> 'icon' = any (enum_range(null::catalog.category_icon)::text[])) then
      raise exception 'Elegí un ícono de la lista.' using errcode = '22023';
    end if;
    v_icon := (p_changes ->> 'icon')::catalog.category_icon;
  end if;
  if p_changes ? 'used_in_recipes' and jsonb_typeof(p_changes -> 'used_in_recipes') <> 'boolean' then
    raise exception 'Elegí si va a recetas.' using errcode = '22023';
  end if;

  perform core.set_change_context(p_reason, 'manual');
  if p_class = 'purchase' then
    update catalog.ingredient_categories
       set name = case when p_changes ? 'name' then btrim(v_name) else name end,
           description = case when p_changes ? 'description' then v_text else description end,
           icon = coalesce(v_icon, icon),
           used_in_recipes = coalesce((p_changes ->> 'used_in_recipes')::boolean, used_in_recipes)
     where id = p_id
    returning updated_at into v_stamp;
  else
    update recipes.recipe_categories
       set name = case when p_changes ? 'name' then btrim(v_name) else name end,
           description = case when p_changes ? 'description' then v_text else description end,
           icon = coalesce(v_icon, icon)
     where id = p_id
    returning updated_at into v_stamp;
  end if;
  return jsonb_build_object('result', 'applied', 'stamp', v_stamp, 'message', 'Rubro guardado.');
exception when unique_violation or check_violation then
  -- Solo se traducen las restricciones de la tabla; los mensajes propios (sin restricción) pasan tal cual.
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if coalesce(v_constraint, '') = '' then
    raise;
  end if;
  perform recipes.raise_category_error(p_class, sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.save_top_category(recipes.category_class, uuid, timestamptz, jsonb, text) is
  'Guarda la ficha de un rubro en una transacción, con motivo: name, description, icon y, en los de compra, used_in_recipes (solo lo que cambió). Pide el permiso de su clase (recipes.can_manage_category); si no, devuelve denied y queda registrado. Rechaza si el rubro cambió desde p_expected_stamp. El código no cambia.';
revoke execute on function recipes.save_top_category(recipes.category_class, uuid, timestamptz, jsonb, text) from public;
grant execute on function recipes.save_top_category(recipes.category_class, uuid, timestamptz, jsonb, text) to authenticated;

-- Las reemplaza la ficha: dejarlas sería otro camino para lo mismo, sin el sello (revisiones de base y de seguridad).
drop function recipes.rename_top_category(recipes.category_class, uuid, text, text);
drop function recipes.set_category_used_in_recipes(uuid, boolean, text);
