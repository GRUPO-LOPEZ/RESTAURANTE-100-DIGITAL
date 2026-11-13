-- Ficha única de materia prima (ADR-0043, Prompt 3 de Soy del 2026-11-12).
--
-- La ficha deja de tener 6 pestañas con un formulario y un motivo por cada dato: se edita donde se ve y se guarda con
-- una sola barra (ADR-0039). Las reglas no cambian: este guardado en lote llama a las funciones de siempre, dentro de una
-- transacción, así siguen valiendo catalog.manage, el trigger de precios (unidad de recetas fija y rubro con
-- prices.configure) y la aprobación para dejar de comprarla congelada.
--
-- 1. catalog.ingredient_sheet_state: el último cambio de la ficha (materia prima, otros nombres, conversiones y
--    alérgenos), para no pisar lo que guardó otra persona en el medio, y lo que la base no va a dejar cambiar.
-- 2. catalog.save_ingredient_sheet: el guardado en lote.
-- 3. costing.ingredient_product_prices: la tabla de productos de compra con su precio en el local elegido.

-- ---------------------------------------------------------------------------
-- 1. El sello de la ficha
-- ---------------------------------------------------------------------------
-- Un alérgeno o una conversión no tocan la fila de la materia prima: el sello toma el último cambio de todo lo que la
-- ficha deja editar (también lo borrado lógicamente, que es un cambio).
create function catalog.ingredient_sheet_stamp_internal(p_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    (select updated_at from catalog.ingredients where id = p_id),
    (select max(updated_at) from catalog.ingredient_aliases where ingredient_id = p_id),
    (select max(updated_at) from catalog.ingredient_unit_conversions where ingredient_id = p_id),
    (select max(updated_at) from catalog.ingredient_allergens where ingredient_id = p_id))
$$;
comment on function catalog.ingredient_sheet_stamp_internal(uuid) is
  'Interna: el último cambio de la ficha de una materia prima (la materia prima, sus otros nombres, conversiones y alérgenos, también lo borrado).';
revoke execute on function catalog.ingredient_sheet_stamp_internal(uuid) from public;

-- La regla de quién cambia el rubro de una materia prima con precios (ADR-0029 y ADR-0038), una sola vez: la usan el
-- trigger catalog.guard_priced_ingredient y la ficha (para deshabilitar lo que la base va a rechazar). Lo cambia quien
-- tiene prices.configure, o quien tiene catalog.manage si la saca de un rubro dado de baja (o de una subcategoría de
-- uno dado de baja).
create function catalog.category_locked_by_prices(p_group_id uuid, p_old_category_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not core.has_permission_in_group('prices.configure', p_group_id)
         and not (core.has_permission_in_group('catalog.manage', p_group_id)
                  and exists (select 1 from catalog.ingredient_categories c
                                left join catalog.ingredient_categories r on r.id = c.parent_id
                               where c.id = p_old_category_id and not coalesce(r.is_active, c.is_active)))
$$;
comment on function catalog.category_locked_by_prices(uuid, uuid) is
  'Interna: si a la sesión se le traba el rubro de una materia prima con precios (sin prices.configure, salvo catalog.manage para sacarla de un rubro dado de baja). La usan el trigger guard_priced_ingredient y catalog.ingredient_sheet_state.';
revoke execute on function catalog.category_locked_by_prices(uuid, uuid) from public;

-- El mismo trigger del ADR-0038, ahora con la regla en una sola función (sin cambiar lo que hace).
create or replace function catalog.guard_priced_ingredient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.recipe_unit_id is distinct from old.recipe_unit_id or new.category_id is distinct from old.category_id)
     and exists (select 1 from costing.price_records p join catalog.purchase_products pp on pp.id = p.purchase_product_id
                  where pp.ingredient_id = new.id and p.deleted_at is null) then
    if new.recipe_unit_id is distinct from old.recipe_unit_id then
      raise exception 'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).'
        using errcode = '23514';
    end if;
    if core.current_actor_id() is not null and catalog.category_locked_by_prices(new.group_id, old.category_id) then
      raise exception 'Esta materia prima ya tiene precios: cambiar su categoría cambia cuándo un precio está desactualizado, y eso lo decide Dirección General.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;

-- Lo que la ficha necesita para editar sin que la base la rechace después: el sello, si tiene precios (la unidad de
-- recetas queda fija) y si esta persona puede cambiar el rubro (con precios, pide prices.configure; la misma regla que
-- el trigger catalog.guard_priced_ingredient). Solo para quien la puede editar: si no, null.
create function catalog.ingredient_sheet_state(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'stamp', catalog.ingredient_sheet_stamp_internal(i.id),
           'has_prices', x.has_prices,
           'category_locked', x.has_prices and catalog.category_locked_by_prices(i.group_id, i.category_id))
    from catalog.ingredients i
    cross join lateral (
      select exists (select 1 from costing.price_records p join catalog.purchase_products pp on pp.id = p.purchase_product_id
                      where pp.ingredient_id = i.id and p.deleted_at is null) as has_prices) x
   where i.id = p_id and i.deleted_at is null
     and core.has_permission_in_group('catalog.manage', i.group_id)
$$;
comment on function catalog.ingredient_sheet_state(uuid) is
  'Para editar la ficha de una materia prima: el sello del último cambio (para no pisar lo de otra persona), si tiene precios (su unidad de recetas no cambia) y si a esta persona se le traba el rubro (con precios, lo cambia quien tiene prices.configure). Solo para quien la puede editar (catalog.manage); si no, null.';

-- ---------------------------------------------------------------------------
-- 2. Guardado en lote
-- ---------------------------------------------------------------------------
-- Cada bloque es opcional (null: no se toca). Si algo falla o se niega, no se guarda nada. El motivo es uno solo para
-- todo el guardado y queda en la auditoría de cada cambio.
create function catalog.save_ingredient_sheet(p_id uuid, p_expected_stamp timestamptz, p_data jsonb, p_aliases text[],
                                              p_conversions jsonb, p_allergens jsonb, p_requires_thawing boolean,
                                              p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_i     catalog.ingredients;
  v_data  jsonb := p_data;
  v_unit  text;
  v_item  jsonb;
  v_thaw  text := 'unchanged';
begin
  select * into v_i from catalog.ingredients where id = p_id and deleted_at is null;
  if v_i.id is null or not core.has_permission_in_group('catalog.manage', v_i.group_id) then
    return core.deny('catalog.save_ingredient_sheet', 'No tenés permiso para editar esta materia prima.', null,
                     jsonb_build_object('ingredient_id', p_id), v_i.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;
  -- Dos guardados de la misma ficha van de a uno; el segundo ve que el primero cambió algo.
  perform 1 from catalog.ingredients where id = p_id for update;
  if p_expected_stamp is null or catalog.ingredient_sheet_stamp_internal(p_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió esta materia prima mientras la editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;

  if v_data is not null then
    if jsonb_typeof(v_data) <> 'object' or v_data = '{}'::jsonb then
      raise exception 'Los datos generales van como un objeto con algún cambio.' using errcode = '22023';
    end if;
    -- Cualquier medida de peso, volumen o cantidad: se guarda la base de su tipo, como al crearla (ADR-0041).
    if v_data ? 'recipe_unit' then
      select b.code into v_unit
        from catalog.units u
        join catalog.units b on b.dimension = u.dimension and b.is_base and b.deleted_at is null
       where u.code = v_data ->> 'recipe_unit' and u.deleted_at is null;
      if v_unit is null then
        raise exception 'Elegí una medida de peso, de volumen o de cantidad.' using errcode = '22023';
      end if;
      v_data := jsonb_set(v_data, '{recipe_unit}', to_jsonb(v_unit));
    end if;
    -- update_ingredient controla las claves; el trigger de precios, la unidad y el rubro.
    -- Solo los datos de la ficha (update_ingredient acepta además otras unidades, que la ficha no edita).
    perform org.check_keys(v_data, array['name', 'category_id', 'recipe_unit', 'purchase_unit', 'notes']);
    perform catalog.update_ingredient(p_id, v_data, p_reason);
  end if;

  if p_aliases is not null then
    perform catalog.set_aliases(p_id, p_aliases, p_reason);
  end if;

  if p_conversions is not null then
    if jsonb_typeof(p_conversions) <> 'array' or jsonb_array_length(p_conversions) > 2 then
      raise exception 'Las conversiones van en una lista (densidad y peso por unidad).' using errcode = '22023';
    end if;
    if (select count(distinct e ->> 'kind') from jsonb_array_elements(p_conversions) e) <> jsonb_array_length(p_conversions) then
      raise exception 'Cada conversión va una sola vez.' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(p_conversions) loop
      if v_item ->> 'kind' is null or v_item ->> 'kind' not in ('density', 'unit_weight') then
        raise exception 'La conversión es la densidad o el peso por unidad.' using errcode = '22023';
      end if;
      perform catalog.set_unit_conversion(p_id, (v_item ->> 'kind')::catalog.conversion_kind,
                                          nullif(v_item ->> 'factor', '')::numeric,
                                          nullif(v_item ->> 'source', '')::catalog.data_source,
                                          nullif(v_item ->> 'measured_on', '')::date,
                                          coalesce(v_item ->> 'measured_by', ''), p_reason);
    end loop;
  end if;

  if p_allergens is not null then
    if jsonb_typeof(p_allergens) <> 'array' or jsonb_array_length(p_allergens) > 100 then
      raise exception 'Los alérgenos van en una lista.' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(p_allergens) loop
      perform catalog.set_allergen_status(p_id, (v_item ->> 'allergen_id')::uuid,
                                          nullif(v_item ->> 'status', '')::catalog.allergen_status,
                                          nullif(v_item ->> 'source', '')::catalog.data_source, p_reason);
    end loop;
  end if;

  -- Marcarla se aplica; desmarcarla baja el costo y queda pendiente de un Chef de todo el grupo (ADR-0040).
  if p_requires_thawing is not null then
    v_thaw := catalog.set_requires_thawing(p_id, p_requires_thawing, p_reason) ->> 'result';
  end if;

  return jsonb_build_object('result', 'applied', 'thawing', v_thaw,
                            'stamp', catalog.ingredient_sheet_stamp_internal(p_id));
end
$$;
comment on function catalog.save_ingredient_sheet(uuid, timestamptz, jsonb, text[], jsonb, jsonb, boolean, text) is
  'Guarda la ficha de una materia prima en una transacción, con un solo motivo (ADR-0043). Bloques opcionales: p_data (name, category_id, recipe_unit, purchase_unit, notes; la unidad de recetas se guarda en la base de su tipo), p_aliases, p_conversions [{kind, factor|null, source, measured_on, measured_by}], p_allergens [{allergen_id, status|null, source}] y p_requires_thawing. Llama a las funciones de siempre: pide catalog.manage, respeta el trigger de precios y la aprobación para dejar de comprarla congelada. Rechaza si la ficha cambió desde p_expected_stamp. Devuelve thawing: applied, pending_approval o unchanged.';

-- ---------------------------------------------------------------------------
-- 3. Productos de compra con su precio en un local
-- ---------------------------------------------------------------------------
-- Por cada producto de compra activo, el último precio aprobado que vale en el local (local → marca → grupo), con la
-- misma elección, el mismo costo (neto con factura y razón social responsable inscripta; si no, el bruto) y la misma
-- regla de desactualizado que costing.price_rows (el motor de costos, que no se toca). La prueba 300 controla que, para
-- el producto que usa el costo, den lo mismo. Sin prices.view en el local, ninguna fila.
create function costing.ingredient_product_prices(p_ingredient_id uuid, p_restaurant_id uuid)
returns table (purchase_product_id uuid, price_record_id uuid, price_level text, inherited boolean, valid_from date,
               package_cost numeric, unit_cost numeric, base_unit text, stale boolean, stale_days integer,
               days_old integer, status text, is_active boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with today as (
    select recipes.today() as d
  ), rest as (
    select r.id, r.group_id, r.brand_id, l.vat_condition
      from org.restaurants r
      left join org.legal_entities l on l.id = r.legal_entity_id and l.deleted_at is null
     where r.id = p_restaurant_id and r.deleted_at is null
       and core.has_permission('prices.view', r.id)
  ), ing as (
    select i.id, u.code as unit_code, coalesce(c.stale_price_days, s.stale_days, 30) as stale_days,
           rest.id as rest_id, rest.brand_id, rest.vat_condition
      from rest
      join catalog.ingredients i on i.group_id = rest.group_id and i.id = p_ingredient_id and i.deleted_at is null
      join catalog.units u on u.id = i.recipe_unit_id
      join catalog.ingredient_categories c on c.id = i.category_id
      left join costing.price_settings s on s.group_id = rest.group_id and s.deleted_at is null
  )
  select pp.id, x.rec_id, x.rec_scope::text, case when x.rec_id is not null then x.rec_scope <> 'restaurant' end,
         x.rec_valid_from,
         case when x.rec_id is null then null
              when x.rec_doc = 'no_invoice' then x.gross_package
              when ing.vat_condition is null then null
              when ing.vat_condition = 'registered' then x.net_package
              else x.gross_package end,
         case when x.rec_id is null then null
              when x.rec_doc = 'no_invoice' then round(x.gross_package / x.base_quantity, 8)
              when ing.vat_condition is null then null
              when ing.vat_condition = 'registered' then round(x.net_package / x.base_quantity, 8)
              else round(x.gross_package / x.base_quantity, 8) end,
         ing.unit_code,
         case when x.rec_id is not null then (select d from today) - x.rec_valid_from > ing.stale_days end,
         ing.stale_days,
         case when x.rec_id is not null then (select d from today) - x.rec_valid_from end,
         case when x.rec_id is null then 'missing_price'
              when x.rec_doc = 'invoice' and ing.vat_condition is null then 'missing_legal_entity'
              else 'ok' end,
         pp.is_active
    from ing
    join catalog.purchase_products pp on pp.ingredient_id = ing.id and pp.deleted_at is null
    left join lateral (
      select p.id as rec_id, p.scope_type as rec_scope, p.valid_from as rec_valid_from, p.document_type as rec_doc,
             p.net_package_price as net_package, p.gross_package_price as gross_package, p.base_quantity
        from costing.price_records p
       where p.purchase_product_id = pp.id and p.deleted_at is null and p.valid_from <= (select d from today)
         and ((p.scope_type = 'restaurant' and p.restaurant_id = ing.rest_id)
              or (p.scope_type = 'brand' and p.brand_id = ing.brand_id)
              or p.scope_type = 'group')
       order by case p.scope_type when 'restaurant' then 1 when 'brand' then 2 else 3 end, p.valid_from desc,
                p.entry_number desc
       limit 1) x on true
   -- Los que ya no se compran, solo si tienen precio: puede ser el que usa el costo (el último costo conocido).
   where pp.is_active or x.rec_id is not null
   order by pp.is_active desc, pp.description
$$;
comment on function costing.ingredient_product_prices(uuid, uuid) is
  'La tabla de productos de compra de la ficha de una materia prima (ADR-0043): por cada producto activo, el último precio aprobado que vale en el local (local → marca → grupo), el costo del envase y por unidad base que cuenta (misma regla que el motor), si está desactualizado y hace cuántos días. Pide prices.view en el local; si no, ninguna fila.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'catalog.ingredient_sheet_state(uuid)',
    'catalog.save_ingredient_sheet(uuid, timestamptz, jsonb, text[], jsonb, jsonb, boolean, text)',
    'costing.ingredient_product_prices(uuid, uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
