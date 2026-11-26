-- «Proponer precio» simple (pedido de Soy, Tanda 2; ADR-0067): el resultado antes de proponer, y el código del producto de
-- compra automático.
--
-- * Una sola cuenta: los controles y los importes de costing.propose_price pasan a funciones internas que usa también la
--   vista previa. Lo que guarda la propuesta no cambia.
-- * costing.preview_price: de solo lectura; pide prices.propose y prices.view en el lugar.
-- * catalog.create_purchase_product: sin código, lo arma con el formato de purchasing.resolve_article.
-- Sin tablas, permisos ni políticas nuevas.

-- ---------------------------------------------------------------------------
-- 1. Los controles de una propuesta
-- ---------------------------------------------------------------------------
-- En el mismo orden y con los mismos mensajes de siempre.
create function costing.check_price_proposal(p_product catalog.purchase_products, p_scope core.scope_type, p_brand_id uuid,
                                             p_restaurant_id uuid, p_valid_from date, p_package_price numeric,
                                             p_document_type text, p_vat_rate numeric, p_discount_amount numeric,
                                             p_supplier_id uuid, p_source text, p_notes text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not p_product.is_active then
    raise exception 'Ese producto de compra está desactivado.' using errcode = '23514';
  end if;
  -- El alcance es del grupo del producto y coherente (una marca o un local, nunca los dos).
  if (p_scope = 'group' and (p_brand_id is not null or p_restaurant_id is not null))
     or (p_scope = 'brand' and (p_restaurant_id is not null
         or not exists (select 1 from org.brands where id = p_brand_id and group_id = p_product.group_id and deleted_at is null)))
     or (p_scope = 'restaurant' and (p_brand_id is not null
         or not exists (select 1 from org.restaurants where id = p_restaurant_id and group_id = p_product.group_id
                                                         and deleted_at is null))) then
    raise exception 'Elegí una marca o un local del grupo.' using errcode = '22023';
  end if;
  if p_supplier_id is not null
     and not exists (select 1 from catalog.suppliers where id = p_supplier_id and group_id = p_product.group_id
                                                     and is_active and deleted_at is null) then
    raise exception 'Elegí un proveedor vigente del grupo.' using errcode = '22023';
  end if;
  if length(p_notes) > 1000 then
    raise exception 'Las observaciones tienen hasta 1.000 caracteres.' using errcode = '22023';
  end if;
  if p_valid_from is null or p_valid_from < date '2000-01-01' or p_valid_from > (now() at time zone 'America/Argentina/Buenos_Aires')::date + 366 then
    raise exception 'Revisá la fecha desde la que vale el precio.' using errcode = '22023';
  end if;
  -- NaN e infinito pasarían las comparaciones (para PostgreSQL, NaN es mayor que todo).
  if p_package_price in ('NaN', 'Infinity', '-Infinity') or p_discount_amount in ('NaN', 'Infinity', '-Infinity') then
    raise exception 'El precio y el descuento tienen que ser números.' using errcode = '22023';
  end if;
  if p_package_price is null or p_package_price <= 0 or coalesce(p_discount_amount, 0) < 0
     or coalesce(p_discount_amount, 0) >= p_package_price then
    raise exception 'El precio tiene que ser mayor que cero y el descuento, menor que el precio.' using errcode = '22023';
  end if;
  if p_document_type is null or p_document_type not in ('invoice', 'no_invoice') then
    raise exception 'Elegí el comprobante: factura o precio ingresado.' using errcode = '22023';
  end if;
  if (p_document_type = 'invoice' and (p_vat_rate is null or p_vat_rate not in (0, 2.5, 5, 10.5, 21, 27)))
     or (p_document_type = 'no_invoice' and p_vat_rate is not null) then
    raise exception 'Con factura, elegí la alícuota de IVA (0; 2,5; 5; 10,5; 21 o 27); sin factura no lleva IVA.' using errcode = '22023';
  end if;
  -- Por ahora se cargan a mano o como valores de prueba (los de factura entran al dar la factura por conforme, Fase 3).
  if p_source is null or p_source not in ('manual', 'test_value') then
    raise exception 'El origen del precio es una carga manual o un valor de prueba.' using errcode = '22023';
  end if;
end
$$;
comment on function costing.check_price_proposal(catalog.purchase_products, core.scope_type, uuid, uuid, date, numeric, text, numeric, numeric, uuid, text, text) is
  'Interna: los controles de una propuesta de precio (producto, lugar, proveedor, fecha, importes, comprobante, alícuota y origen). La usan costing.propose_price y costing.preview_price.';
revoke execute on function costing.check_price_proposal(catalog.purchase_products, core.scope_type, uuid, uuid, date, numeric, text, numeric, numeric, uuid, text, text) from public;

-- Desde cuándo puede valer y si ya hay una pendiente igual.
create function costing.check_price_dates(p_product_id uuid, p_scope core.scope_type, p_brand_id uuid, p_restaurant_id uuid,
                                          p_valid_from date)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_floor date := costing.valid_from_floor(p_product_id, p_scope, p_brand_id, p_restaurant_id);
begin
  if v_floor is not null and p_valid_from < v_floor then
    raise exception 'Un precio nuevo no puede empezar antes que el que vale hoy en ese lugar (%). Cargalo desde esa fecha o después.',
      to_char(v_floor, 'DD/MM/YYYY') using errcode = '23514';
  end if;
  if exists (select 1 from workflow.approval_requests r
               join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code in ('costing.approve_price', 'costing.approve_price_direction') and r.status = 'pending'
                and r.deleted_at is null and r.entity_id = p_product_id
                and r.proposed_changes ->> 'scope_type' = p_scope::text
                and (r.proposed_changes ->> 'brand_id') is not distinct from p_brand_id::text
                and (r.proposed_changes ->> 'restaurant_id') is not distinct from p_restaurant_id::text
                and (r.proposed_changes ->> 'valid_from')::date = p_valid_from) then
    raise exception 'Ya hay un precio pendiente para ese producto, lugar y fecha: esperá a que se decida o pedí que lo retiren.'
      using errcode = '23505';
  end if;
end
$$;
comment on function costing.check_price_dates(uuid, core.scope_type, uuid, uuid, date) is
  'Interna: corta una propuesta de precio que empieza antes que el vigente en ese lugar o que ya está pendiente. La usan costing.propose_price y costing.preview_price.';
revoke execute on function costing.check_price_dates(uuid, core.scope_type, uuid, uuid, date) from public;

-- ---------------------------------------------------------------------------
-- 2. Los importes y la variación
-- ---------------------------------------------------------------------------
create function costing.price_proposal_amounts(p_product catalog.purchase_products, p_scope core.scope_type, p_brand_id uuid,
                                               p_restaurant_id uuid, p_valid_from date, p_package_price numeric,
                                               p_discount_amount numeric, p_document costing.price_document, p_vat_rate numeric,
                                               p_price_includes_vat boolean)
returns table (net_package_price numeric, gross_package_price numeric, base_quantity numeric, net_unit_cost numeric,
               gross_unit_cost numeric, reference_id uuid, reference_net numeric, reference_gross numeric, reference_as_of date,
               lookback_id uuid, lookback_days integer, variation_today numeric, variation_lookback numeric, variation numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base      record;
  v_ref       record;
  v_back      record;
  v_var_net   numeric;
  v_var_gross numeric;
begin
  select a.net_amount, a.gross_amount into net_package_price, gross_package_price
    from costing.package_amounts(p_package_price, coalesce(p_discount_amount, 0), p_document, p_vat_rate,
                                 coalesce(p_price_includes_vat, true)) a;
  -- El precio por unidad de uso (g, ml o unidad): así se compara con otro producto de otro tamaño.
  select b.base_quantity as quantity, b.status into v_base
    from catalog.to_base_quantity(p_product.ingredient_id, p_product.content_per_unit * p_product.units_per_package,
                                  p_product.content_unit_id) b;
  if v_base.status <> 'ok' or coalesce(v_base.quantity, 0) <= 0 then
    raise exception 'El contenido de ese producto no se pasa a la unidad de uso de la materia prima: cargá primero su conversión.'
      using errcode = '23514';
  end if;
  base_quantity := v_base.quantity;
  net_unit_cost := net_package_price / base_quantity;
  gross_unit_cost := gross_package_price / base_quantity;
  -- La variación es contra el costo que se usa hoy en ese lugar (con herencia y cualquier producto), con y
  -- sin IVA: la más grande de las dos. Sin referencia (el primer precio) alcanza con el Controller.
  reference_as_of := greatest(p_valid_from, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  select r.price_record_id as id, r.net_unit_cost as net, r.gross_unit_cost as gross into v_ref
    from costing.reference_price(p_product.ingredient_id, p_scope, p_product.group_id, p_brand_id, p_restaurant_id, reference_as_of) r;
  if v_ref.id is not null then
    reference_id := v_ref.id;
    reference_net := v_ref.net;
    reference_gross := v_ref.gross;
    v_var_net := round((net_unit_cost - v_ref.net) / v_ref.net * 100, 2);
    v_var_gross := round((gross_unit_cost - v_ref.gross) / v_ref.gross * 100, 2);
    variation_today := case when abs(v_var_gross) > abs(v_var_net) then v_var_gross else v_var_net end;
  end if;
  -- Subas en escalones (respuesta 8 de Soy, ADR-0030): también contra el precio de hace N días en ese
  -- lugar. Vale la variación más grande: varias subas chicas seguidas llegan a Dirección.
  select coalesce(s.lookback_days, 30) into lookback_days
    from (select 1) x left join costing.price_settings s on s.group_id = p_product.group_id and s.deleted_at is null;
  select r.price_record_id as id, r.net_unit_cost as net, r.gross_unit_cost as gross into v_back
    from costing.reference_price(p_product.ingredient_id, p_scope, p_product.group_id, p_brand_id, p_restaurant_id,
                                 reference_as_of - lookback_days) r;
  lookback_id := v_back.id;
  if v_back.id is not null and v_back.id is distinct from v_ref.id then
    v_var_net := round((net_unit_cost - v_back.net) / v_back.net * 100, 2);
    v_var_gross := round((gross_unit_cost - v_back.gross) / v_back.gross * 100, 2);
    variation_lookback := case when abs(v_var_gross) > abs(v_var_net) then v_var_gross else v_var_net end;
  end if;
  variation := case when variation_lookback is not null
                         and (variation_today is null or abs(variation_lookback) > abs(variation_today))
                    then variation_lookback else variation_today end;
  return next;
end
$$;
comment on function costing.price_proposal_amounts(catalog.purchase_products, core.scope_type, uuid, uuid, date, numeric, numeric, costing.price_document, numeric, boolean) is
  'Interna: los importes de una propuesta de precio (envase y unidad de uso, con y sin IVA) y su variación contra el precio de hoy y el de hace N días en ese lugar. Una sola cuenta para costing.propose_price y costing.preview_price.';
revoke execute on function costing.price_proposal_amounts(catalog.purchase_products, core.scope_type, uuid, uuid, date, numeric, numeric, costing.price_document, numeric, boolean) from public;

-- ---------------------------------------------------------------------------
-- 3. La propuesta: guarda lo mismo que antes
-- ---------------------------------------------------------------------------
create or replace function costing.propose_price(p_purchase_product_id uuid, p_scope_type text, p_brand_id uuid, p_restaurant_id uuid,
                                                 p_valid_from date, p_package_price numeric, p_document_type text, p_vat_rate numeric,
                                                 p_price_includes_vat boolean, p_discount_amount numeric, p_supplier_id uuid,
                                                 p_source text, p_notes text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product catalog.purchase_products;
  v_ing     catalog.ingredients;
  v_scope   core.scope_type;
  v_a       record;
begin
  select * into v_product from catalog.purchase_products where id = p_purchase_product_id and deleted_at is null;
  if p_scope_type is null or p_scope_type not in ('group', 'brand', 'restaurant') then
    raise exception 'Elegí para quién vale el precio: el grupo, una marca o un local.' using errcode = '22023';
  end if;
  v_scope := p_scope_type::core.scope_type;
  perform org.require(v_product.id is not null
                      and costing.has_scope_permission('prices.propose', v_scope, v_product.group_id, p_brand_id, p_restaurant_id),
                      'proponer precios en ese lugar');
  perform costing.check_price_proposal(v_product, v_scope, p_brand_id, p_restaurant_id, p_valid_from, p_package_price,
                                       p_document_type, p_vat_rate, p_discount_amount, p_supplier_id, p_source, p_notes);

  -- Las propuestas de la misma materia prima, de a una por vez.
  select * into v_ing from catalog.ingredients where id = v_product.ingredient_id for update;
  perform costing.check_price_dates(p_purchase_product_id, v_scope, p_brand_id, p_restaurant_id, p_valid_from);
  select * into v_a
    from costing.price_proposal_amounts(v_product, v_scope, p_brand_id, p_restaurant_id, p_valid_from, p_package_price,
                                        p_discount_amount, p_document_type::costing.price_document, p_vat_rate,
                                        p_price_includes_vat);

  return workflow.request_approval(
    'costing.approve_price', v_product.group_id,
    case when v_scope = 'brand' then p_brand_id
         when v_scope = 'restaurant' then (select brand_id from org.restaurants where id = p_restaurant_id) end,
    p_restaurant_id, null, p_purchase_product_id,
    jsonb_build_object('ingredient', v_ing.name, 'ingredient_id', v_ing.id, 'product', v_product.description,
                       'purchase_product_id', p_purchase_product_id, 'scope_type', p_scope_type,
                       'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id, 'valid_from', p_valid_from,
                       'package_price', p_package_price, 'discount_amount', coalesce(p_discount_amount, 0),
                       'document_type', p_document_type, 'vat_rate', p_vat_rate,
                       'price_includes_vat', coalesce(p_price_includes_vat, true), 'supplier_id', p_supplier_id,
                       'source', p_source, 'notes', nullif(btrim(p_notes), ''),
                       'net_package_price', v_a.net_package_price, 'gross_package_price', v_a.gross_package_price,
                       'net_unit_cost', round(v_a.net_unit_cost, 8), 'gross_unit_cost', round(v_a.gross_unit_cost, 8),
                       'base_quantity', v_a.base_quantity, 'recipe_unit_id', v_ing.recipe_unit_id,
                       'price_variation_pct', v_a.variation, 'price_variation_today_pct', v_a.variation_today,
                       'price_variation_lookback_pct', v_a.variation_lookback, 'lookback_days', v_a.lookback_days,
                       'lookback_price_record_id', v_a.lookback_id,
                       'reference_price_record_id', v_a.reference_id, 'reference_as_of', v_a.reference_as_of),
    case when v_a.reference_id is null then jsonb_build_object('net_unit_cost', null)
         else jsonb_build_object('net_unit_cost', round(v_a.reference_net, 8),
                                 'gross_unit_cost', round(v_a.reference_gross, 8)) end,
    p_reason);
end
$$;

-- ---------------------------------------------------------------------------
-- 4. La vista previa
-- ---------------------------------------------------------------------------
-- De solo lectura: ni solicitudes, ni bloqueos, ni registro de rechazos (se llama mientras se escribe).
create function costing.preview_price(p_purchase_product_id uuid, p_scope_type text, p_brand_id uuid, p_restaurant_id uuid,
                                      p_valid_from date, p_package_price numeric, p_document_type text, p_vat_rate numeric,
                                      p_price_includes_vat boolean, p_discount_amount numeric, p_supplier_id uuid, p_source text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_product   catalog.purchase_products;
  v_scope     core.scope_type;
  v_a         record;
  v_threshold numeric;
begin
  select * into v_product from catalog.purchase_products where id = p_purchase_product_id and deleted_at is null;
  if p_scope_type is null or p_scope_type not in ('group', 'brand', 'restaurant') then
    raise exception 'Elegí para quién vale el precio: el grupo, una marca o un local.' using errcode = '22023';
  end if;
  v_scope := p_scope_type::core.scope_type;
  -- Muestra la variación contra el precio vigente: hace falta proponer y también ver precios en ese lugar.
  perform org.require(v_product.id is not null
                      and costing.has_scope_permission('prices.propose', v_scope, v_product.group_id, p_brand_id, p_restaurant_id)
                      and costing.has_scope_permission('prices.view', v_scope, v_product.group_id, p_brand_id, p_restaurant_id),
                      'ver cómo queda un precio en ese lugar');
  perform costing.check_price_proposal(v_product, v_scope, p_brand_id, p_restaurant_id, p_valid_from, p_package_price,
                                       p_document_type, p_vat_rate, p_discount_amount, p_supplier_id, p_source, null);
  perform costing.check_price_dates(p_purchase_product_id, v_scope, p_brand_id, p_restaurant_id, p_valid_from);
  select * into v_a
    from costing.price_proposal_amounts(v_product, v_scope, p_brand_id, p_restaurant_id, p_valid_from, p_package_price,
                                        p_discount_amount, p_document_type::costing.price_document, p_vat_rate,
                                        p_price_includes_vat);
  select approval_variation_pct into v_threshold from costing.price_settings
   where group_id = v_product.group_id and deleted_at is null;
  v_threshold := coalesce(v_threshold, 15);
  return jsonb_build_object(
    'net_package_price', v_a.net_package_price, 'gross_package_price', v_a.gross_package_price,
    'net_unit_cost', round(v_a.net_unit_cost, 8), 'gross_unit_cost', round(v_a.gross_unit_cost, 8),
    'base_unit', (select u.code from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id
                   where i.id = v_product.ingredient_id),
    'variation', v_a.variation, 'variation_today', v_a.variation_today, 'variation_lookback', v_a.variation_lookback,
    'lookback_days', v_a.lookback_days, 'first', v_a.reference_id is null,
    -- La misma regla de costing.apply_price.
    'direction', coalesce(abs(v_a.variation) > v_threshold, false));
end
$$;
comment on function costing.preview_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text) is
  'Cómo quedaría un precio antes de proponerlo: importes por envase y por unidad de uso, variación contra hoy y contra hace N días, y si además de Controller lo aprueba Dirección. Misma cuenta y mismos controles que costing.propose_price (salvo las observaciones y el motivo, que no cuentan); de solo lectura. Pide prices.propose y prices.view en el lugar.';
revoke execute on function costing.preview_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text) from public;
grant execute on function costing.preview_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Código automático del producto de compra
-- ---------------------------------------------------------------------------
-- El de la materia prima y «-P01», «-P02»… (el formato de purchasing.resolve_article). Las altas del grupo van de a una, así
-- no eligen el mismo (el código es único en el grupo, y dos materias primas pueden empezar igual).
create function catalog.next_product_code(p_ingredient_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ing  catalog.ingredients;
  v_n    integer := 0;
  v_num  text;
  v_code text;
begin
  select * into v_ing from catalog.ingredients where id = p_ingredient_id;
  perform pg_advisory_xact_lock(hashtextextended('catalog.next_product_code:' || v_ing.group_id, 0));
  loop
    v_n := v_n + 1;
    v_num := case when v_n < 100 then lpad(v_n::text, 2, '0') else v_n::text end;
    v_code := left(v_ing.code, 28 - length(v_num)) || '-P' || v_num;
    exit when not exists (select 1 from catalog.purchase_products where group_id = v_ing.group_id and code = v_code);
  end loop;
  return v_code;
end
$$;
comment on function catalog.next_product_code(uuid) is
  'Interna: el próximo código libre de un producto de compra de una materia prima (su código y -P01, -P02…). Las altas con código automático del grupo van de a una hasta el final de la transacción. El permiso lo controla quien la llama.';
revoke execute on function catalog.next_product_code(uuid) from public;

create or replace function catalog.create_purchase_product(p_ingredient_id uuid, p_code text, p_description text, p_package_unit text,
                                                           p_units_per_package integer, p_content_per_unit numeric,
                                                           p_content_unit text, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_group uuid := catalog.ingredient_group(p_ingredient_id);
  v_id    uuid;
begin
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['supplier_id', 'brand_name', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, brand_name,
                                         package_unit_id, units_per_package, content_per_unit, content_unit_id, notes)
  values (v_group, coalesce(nullif(upper(btrim(p_code)), ''), catalog.next_product_code(p_ingredient_id)), p_ingredient_id,
          nullif(p_details ->> 'supplier_id', '')::uuid,
          btrim(p_description), nullif(btrim(p_details ->> 'brand_name'), ''), catalog.unit_id(p_package_unit),
          coalesce(p_units_per_package, 1), p_content_per_unit, catalog.unit_id(p_content_unit),
          nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_purchase_product(uuid, text, text, text, integer, numeric, text, jsonb, text) is
  'Crea un producto de compra de una materia prima. Pide catalog.manage y un motivo. Sin código (nulo o vacío), lo arma solo (catalog.next_product_code). p_details: supplier_id, brand_name y notes. La aprobación del Controller se suma con los precios (etapa 2.1 C).';

create or replace function purchasing.resolve_article(p_id uuid, p_ingredient_id uuid, p_package_unit text, p_units_per_package integer,
                                                      p_content_per_unit numeric, p_content_unit text, p_details jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_a          purchasing.unmapped_articles;
  v_ing        catalog.ingredients;
  v_code       text;
  v_product    uuid;
  v_by_weight  boolean;
  v_constraint text;
  v_message    text;
begin
  v_a := purchasing.pending_article(p_id);
  if v_a.id is null then
    return core.deny('purchasing.resolve_article', 'No tenés permiso para mapear este artículo.', null,
                     jsonb_build_object('unmapped_article_id', p_id),
                     (select group_id from purchasing.unmapped_articles where id = p_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  perform org.check_keys(coalesce(p_details, '{}'::jsonb),
                         array['brand_name', 'billed_by_weight', 'estimated_weight_per_unit', 'description']);
  select * into v_ing from catalog.ingredients
   where id = p_ingredient_id and group_id = v_a.group_id and deleted_at is null and is_active;
  if v_ing.id is null then
    raise exception 'Elegí una materia prima activa de este grupo.' using errcode = '22023';
  end if;
  v_code := catalog.next_product_code(v_ing.id);
  v_by_weight := coalesce((p_details ->> 'billed_by_weight')::boolean, false);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, brand_name,
                                         package_unit_id, units_per_package, content_per_unit, content_unit_id,
                                         supplier_sku, billed_by_weight, estimated_weight_per_unit)
  values (v_a.group_id, v_code, v_ing.id, v_a.supplier_id,
          coalesce(nullif(btrim(p_details ->> 'description'), ''), v_a.raw_name),
          nullif(btrim(p_details ->> 'brand_name'), ''), catalog.unit_id(p_package_unit),
          coalesce(p_units_per_package, 1), p_content_per_unit, catalog.unit_id(p_content_unit), v_a.supplier_sku,
          v_by_weight, case when v_by_weight then (p_details ->> 'estimated_weight_per_unit')::numeric end)
  returning id into v_product;
  -- Si el chef le cambió la descripción, el nombre como vino queda como otro nombre para reconocerlo.
  if purchasing.normalize_name(coalesce(nullif(btrim(p_details ->> 'description'), ''), v_a.raw_name))
       is distinct from v_a.normalized_name then
    insert into purchasing.article_aliases (group_id, supplier_id, purchase_product_id, raw_name)
    values (v_a.group_id, v_a.supplier_id, v_product, v_a.raw_name);
  end if;
  perform purchasing.close_article(v_a, v_product);
  return jsonb_build_object('result', 'applied', 'purchase_product_id', v_product, 'code', v_code);
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_price_list_error(sqlstate, v_constraint, v_message);
end
$$;
