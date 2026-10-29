-- Fase 2 · Etapa 2.1 A: correcciones de la revisión de base (db-reviewer, 2026-10-29). ADR-0020.
--   1. M2: un producto de compra en otra dimensión que la de uso necesita la conversión del
--      ingrediente. Hasta ahora solo se controlaba al cargar el producto: también se controla al
--      quitar la conversión y al cambiar la unidad de uso del ingrediente.
--   2. m3: no se usa una categoría ni un proveedor borrados.
--   3. m1: índices completos en las claves foráneas (los parciales no sirven para el control de la
--      clave foránea).
--   4. m2: el buscador escapa % y _ y no ofrece borrados aunque lo llame una función que no pasa
--      por RLS; convert_quantity ignora ingredientes borrados.

-- ---------------------------------------------------------------------------
-- 1. Conversión que necesita un producto: una sola regla para los tres caminos
-- ---------------------------------------------------------------------------
-- Qué conversión le falta al ingrediente para que el contenido (en esa unidad) se pueda pasar a
-- su unidad de uso. Vacío si no le falta nada.
create function catalog.missing_conversion(p_ingredient_id uuid, p_content_unit_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_content catalog.dimension;
  v_use     catalog.dimension;
  v_needs   catalog.conversion_kind[];
begin
  select dimension into v_content from catalog.units where id = p_content_unit_id;
  select u.dimension into v_use
    from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id
   where i.id = p_ingredient_id;
  if v_content = v_use then
    return null;
  end if;
  v_needs := case
    when array[v_content, v_use] <@ array['mass', 'volume']::catalog.dimension[] then array['density']
    when array[v_content, v_use] <@ array['mass', 'count']::catalog.dimension[] then array['unit_weight']
    else array['density', 'unit_weight'] end::catalog.conversion_kind[];
  if (select count(distinct kind) from catalog.ingredient_unit_conversions
       where ingredient_id = p_ingredient_id and deleted_at is null and kind = any (v_needs)) = cardinality(v_needs) then
    return null;
  end if;
  return case when v_needs = array['density']::catalog.conversion_kind[] then 'densidad'
              when v_needs = array['unit_weight']::catalog.conversion_kind[] then 'peso por unidad'
              else 'densidad y su peso por unidad' end;
end
$$;
comment on function catalog.missing_conversion(uuid, uuid) is
  'Interna: qué conversión le falta al ingrediente para pasar un contenido en esa unidad a su unidad de uso (densidad, peso por unidad o las dos). Vacío si no falta nada.';
revoke execute on function catalog.missing_conversion(uuid, uuid) from public;

-- El producto, al cargarlo o cambiarlo (misma regla que antes, con la función común).
create or replace function catalog.enforce_product_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_missing text;
begin
  if (select dimension from catalog.units where id = new.content_unit_id) = 'package' then
    raise exception 'El contenido va en g, kg, ml, l o unidades: un envase no dice cuánto trae.' using errcode = '23514';
  end if;
  -- Un producto que ya no se compra no se costea: desactivarlo nunca se frena.
  if not new.is_active then
    return new;
  end if;
  v_missing := catalog.missing_conversion(new.ingredient_id, new.content_unit_id);
  if v_missing is not null then
    raise exception 'El ingrediente se usa en otra unidad: primero cargá su %.', v_missing using errcode = '23514';
  end if;
  return new;
end
$$;

-- Los productos vigentes de un ingrediente se tienen que poder seguir costeando.
create function catalog.check_ingredient_products(p_ingredient_id uuid, p_action text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_product text;
  v_missing text;
begin
  select p.description, catalog.missing_conversion(p.ingredient_id, p.content_unit_id)
    into v_product, v_missing
    from catalog.purchase_products p
   where p.ingredient_id = p_ingredient_id and p.deleted_at is null and p.is_active
     and catalog.missing_conversion(p.ingredient_id, p.content_unit_id) is not null
   order by p.description
   limit 1;
  if v_product is not null then
    raise exception 'No se puede %: el producto «%» se compra en otra unidad y necesita su %.', p_action, v_product, v_missing
      using errcode = '23514';
  end if;
end
$$;
comment on function catalog.check_ingredient_products(uuid, text) is
  'Interna: corta si algún producto de compra vigente del ingrediente quedaría sin la conversión que necesita para costearse.';
revoke execute on function catalog.check_ingredient_products(uuid, text) from public;

-- Al cambiar la unidad de uso del ingrediente.
create function catalog.enforce_ingredient_unit_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform catalog.check_ingredient_products(new.id, 'cambiar la unidad de uso');
  return new;
end
$$;
comment on function catalog.enforce_ingredient_unit_change() is
  'Trigger (AFTER UPDATE OF recipe_unit_id) de ingredients: sus productos vigentes se tienen que poder seguir costeando.';
revoke execute on function catalog.enforce_ingredient_unit_change() from public;
create trigger validate_products_after_unit_change after update of recipe_unit_id on catalog.ingredients
  for each row when (new.recipe_unit_id is distinct from old.recipe_unit_id)
  execute function catalog.enforce_ingredient_unit_change();

-- Al quitar una conversión (o cambiarle el tipo).
create function catalog.enforce_conversion_removal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform catalog.check_ingredient_products(new.ingredient_id, 'quitar esta conversión');
  return new;
end
$$;
comment on function catalog.enforce_conversion_removal() is
  'Trigger (AFTER UPDATE) de ingredient_unit_conversions: al quitarla o cambiarle el tipo, los productos vigentes del ingrediente se tienen que poder seguir costeando.';
revoke execute on function catalog.enforce_conversion_removal() from public;
create trigger validate_products_after_conversion_change after update of deleted_at, kind on catalog.ingredient_unit_conversions
  for each row when ((new.deleted_at is not null and old.deleted_at is null) or new.kind is distinct from old.kind)
  execute function catalog.enforce_conversion_removal();

-- Reactivar un producto también tiene que poder costearse.
drop trigger validate_product_content on catalog.purchase_products;
create trigger validate_product_content before insert or update of content_unit_id, ingredient_id, is_active
  on catalog.purchase_products
  for each row execute function catalog.enforce_product_content();

-- ---------------------------------------------------------------------------
-- 2. Nada nuevo apunta a una categoría o a un proveedor borrados
-- ---------------------------------------------------------------------------
create function catalog.enforce_live_references()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Solo cuando la referencia es nueva o cambia: editar otra cosa (o desactivar un producto) nunca
  -- se frena porque la categoría o el proveedor de siempre ya no esté vigente.
  -- (Una rama por tabla: cada una solo nombra columnas que esa tabla tiene.)
  if tg_table_name = 'ingredients' then
    if (tg_op = 'INSERT' or new.category_id is distinct from old.category_id)
       and exists (select 1 from catalog.ingredient_categories where id = new.category_id and deleted_at is not null) then
      raise exception 'Esa categoría está borrada: elegí otra.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'purchase_products' then
    if (tg_op = 'INSERT' or new.supplier_id is distinct from old.supplier_id)
       and new.supplier_id is not null
       and exists (select 1 from catalog.suppliers where id = new.supplier_id and deleted_at is not null) then
      raise exception 'Ese proveedor está borrado: elegí otro.' using errcode = '23514';
    end if;
  elsif tg_table_name = 'ingredient_categories' then
    if (tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id)
       and new.parent_id is not null
       and exists (select 1 from catalog.ingredient_categories where id = new.parent_id and deleted_at is not null) then
      raise exception 'La categoría madre está borrada: elegí otra.' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.enforce_live_references() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredients, purchase_products e ingredient_categories: no se apunta a una categoría, categoría madre o proveedor borrados.';
revoke execute on function catalog.enforce_live_references() from public;
create trigger validate_live_category before insert or update of category_id on catalog.ingredients
  for each row execute function catalog.enforce_live_references();
create trigger validate_live_supplier before insert or update of supplier_id on catalog.purchase_products
  for each row execute function catalog.enforce_live_references();
create trigger validate_live_parent before insert or update of parent_id on catalog.ingredient_categories
  for each row execute function catalog.enforce_live_references();

-- ---------------------------------------------------------------------------
-- 3. Índices completos en las claves foráneas
-- ---------------------------------------------------------------------------
create index ingredients_group_idx on catalog.ingredients (group_id);
create index ingredient_aliases_group_idx on catalog.ingredient_aliases (group_id);
create index ingredient_unit_conversions_group_idx on catalog.ingredient_unit_conversions (group_id);
create index suppliers_group_fk_idx on catalog.suppliers (group_id);
create index purchase_products_group_idx on catalog.purchase_products (group_id);
create index allergens_group_idx on catalog.allergens (group_id);
create index ingredient_allergens_group_idx on catalog.ingredient_allergens (group_id);
create index unit_conversions_from_idx on catalog.unit_conversions (from_unit_id);

-- ---------------------------------------------------------------------------
-- 4. Buscador y conversiones: sin comodines del usuario ni borrados
-- ---------------------------------------------------------------------------
create or replace function catalog.search_components(p_query text, p_limit integer default 20)
returns table (kind text, id uuid, code text, name text, unit text, matched text, score real)
language sql
stable
set search_path = ''
as $$
  -- % y _ se buscan como letras, no como comodines.
  with q as (select lower(btrim(p_query)) as t,
                    replace(replace(replace(lower(btrim(p_query)), '\', '\\'), '%', '\%'), '_', '\_') as e)
  select 'ingredient'::text, i.id, i.code, i.name, u.name,
         coalesce(a.alias, i.name),
         greatest(extensions.similarity(lower(i.name), q.t),
                  coalesce(extensions.similarity(a.alias, q.t), 0),
                  case when lower(i.code) like q.e || '%' then 1 else 0 end)::real as score
    from q, catalog.ingredients i
    join catalog.units u on u.id = i.recipe_unit_id
    left join lateral (
      select al.alias from catalog.ingredient_aliases al
       where al.ingredient_id = i.id and al.deleted_at is null and al.alias like '%' || (select e from q) || '%'
       order by length(al.alias) limit 1) a on true
   where length(q.t) >= 3
     and i.is_active
     and i.deleted_at is null
     and (lower(i.name) like '%' || q.e || '%'
          or lower(i.code) like q.e || '%'
          or a.alias is not null
          or extensions.similarity(lower(i.name), q.t) > 0.3)
   order by score desc, i.name
   limit least(greatest(coalesce(p_limit, 20), 1), 50)
$$;

-- convert_quantity: un ingrediente borrado no existe para el motor.
create or replace function catalog.convert_quantity(p_ingredient_id uuid, p_quantity numeric, p_from_unit_id uuid,
                                                    p_to_unit_id uuid)
returns table (quantity numeric, status text)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_from     catalog.units;
  v_to       catalog.units;
  v_qty      numeric;
  v_to_base  numeric;
  v_density  numeric;
  v_weight   numeric;
begin
  if not exists (select 1 from catalog.ingredients where id = p_ingredient_id and deleted_at is null) then
    return query select null::numeric, 'unknown_ingredient'::text;
    return;
  end if;
  select * into v_from from catalog.units where id = p_from_unit_id and deleted_at is null;
  select * into v_to from catalog.units where id = p_to_unit_id and deleted_at is null;
  if v_from.id is null or v_to.id is null or p_quantity is null or p_quantity < 0 then
    return query select null::numeric, 'invalid_quantity'::text;
    return;
  end if;
  if v_from.dimension = 'package' or v_to.dimension = 'package' then
    return query select null::numeric, 'missing_conversion'::text;
    return;
  end if;

  if v_from.is_base then
    v_qty := p_quantity;
  else
    select p_quantity * c.factor into v_qty
      from catalog.unit_conversions c where c.from_unit_id = v_from.id and c.deleted_at is null;
  end if;
  if v_to.is_base then
    v_to_base := 1;
  else
    select c.factor into v_to_base
      from catalog.unit_conversions c where c.from_unit_id = v_to.id and c.deleted_at is null;
  end if;

  if v_from.dimension <> v_to.dimension then
    select factor into v_density from catalog.ingredient_unit_conversions
     where ingredient_id = p_ingredient_id and kind = 'density' and deleted_at is null;
    select factor into v_weight from catalog.ingredient_unit_conversions
     where ingredient_id = p_ingredient_id and kind = 'unit_weight' and deleted_at is null;
    v_qty := case v_from.dimension
               when 'mass' then v_qty
               when 'volume' then v_qty * v_density
               when 'count' then v_qty * v_weight
             end;
    v_qty := case v_to.dimension
               when 'mass' then v_qty
               when 'volume' then v_qty / v_density
               when 'count' then v_qty / v_weight
             end;
  end if;

  if v_qty is null or v_to_base is null then
    return query select null::numeric, 'missing_conversion'::text;
    return;
  end if;
  return query select v_qty / v_to_base, 'ok'::text;
end
$$;

comment on function catalog.enforce_product_content() is
  'Trigger (BEFORE INSERT OR UPDATE OF content_unit_id, ingredient_id, is_active) de purchase_products: el contenido nunca es un envase y, si el producto está activo y su contenido es de otra dimensión que la de uso, el ingrediente tiene que tener la conversión (catalog.missing_conversion). Un producto desactivado no se controla.';

-- Los datos que ya existen tienen que cumplir la regla (en una base con datos, la primera edición
-- de un producto así fallaría sin explicación).
do $$
begin
  if exists (select 1 from catalog.purchase_products p
              where p.deleted_at is null and p.is_active
                and catalog.missing_conversion(p.ingredient_id, p.content_unit_id) is not null) then
    raise exception 'Hay productos de compra activos que no se pueden costear por falta de una conversión: hay que cargarla o desactivarlos antes de aplicar esta migración.';
  end if;
end
$$;
