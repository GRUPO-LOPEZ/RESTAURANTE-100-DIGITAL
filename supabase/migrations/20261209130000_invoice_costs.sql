-- Fase 3, Prompt 5 (ADR-0058): el costo sale de la factura conforme. Cambia la única fuente de costos
-- (costing.price_records), con revisión de seguridad obligatoria.
--
-- - Un precio puede entrar sin solicitud de aprobación si viene de una línea de factura conforme (decisión 1 de Soy:
--   dar por conforme la factura es aprobar el precio). Queda la referencia a la línea y quién la dio por conforme.
--   El camino de hoy (proponer y aprobar a mano) sigue igual para los precios sin factura.
-- - Las alícuotas de 2,5 % y 5 % (P5) valen también en los precios.
-- - Un precio de factura avisa a otros sistemas igual que uno aprobado (price.approved) y dispara el recálculo como
--   cualquier precio.

-- ---------------------------------------------------------------------------
-- 1. La línea de factura de origen
-- ---------------------------------------------------------------------------
alter table costing.price_records
  add column invoice_line_id uuid references purchasing.invoice_lines (id) on delete restrict;
create unique index price_records_invoice_line_key on costing.price_records (invoice_line_id)
  where invoice_line_id is not null;
comment on column costing.price_records.invoice_line_id is
  'La línea de la factura conforme de la que sale este precio (origen «invoice»). Vacía en los precios aprobados a mano y en los valores de prueba.';
comment on column costing.price_records.approval_request_id is
  'La solicitud que lo aprobó (la de Dirección, si hizo falta). Vacía en los valores de prueba y en los precios de factura (los aprueba quien da la factura por conforme).';
comment on column costing.price_records.approved_by is
  'Quién dio la última aprobación: quien aprobó la solicitud o quien dio la factura por conforme.';

-- Una de tres: solicitud aprobada, línea de factura conforme o valor de prueba.
alter table costing.price_records drop constraint price_records_approval_check;
alter table costing.price_records add constraint price_records_approval_check check (
  (approved_by is null) = (approved_at is null)
  and (approval_request_id is null or approved_by is not null)
  and (invoice_line_id is null or (source = 'invoice' and approval_request_id is null and approved_by is not null))
  and (approval_request_id is not null or invoice_line_id is not null
       or (source = 'test_value' and approved_by is null)));

-- ---------------------------------------------------------------------------
-- 2. Alícuotas de 2,5 % y 5 % (P5)
-- ---------------------------------------------------------------------------
alter table costing.price_records drop constraint price_records_vat_rate_check;
alter table costing.price_records add constraint price_records_vat_rate_check
  check (vat_rate is null or vat_rate in (0, 2.5, 5, 10.5, 21, 27));
comment on column costing.price_records.vat_rate is 'Alícuota de IVA: 0; 2,5; 5; 10,5; 21 o 27 %. Solo con factura.';

comment on type costing.price_source is
  'De dónde viene un precio: manual (propuesto y aprobado a mano), test_value (valor de prueba), excel_import (importación) o invoice (línea de una factura conforme, Fase 3).';

-- ---------------------------------------------------------------------------
-- 3. Aviso a otros sistemas: también los precios de factura
-- ---------------------------------------------------------------------------
create or replace function costing.on_price_recorded()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.approval_request_id is not null or new.invoice_line_id is not null then
    perform integration.emit(new.group_id, 'price.approved', 'costing.price_records', new.id,
                             jsonb_build_object('purchase_product_id', new.purchase_product_id, 'scope_type', new.scope_type,
                                                'valid_from', new.valid_from, 'source', new.source));
  end if;
  -- Uno con fecha futura todavía no vale: lo anota la tarea diaria el día que empieza.
  if new.valid_from <= recipes.today() then
    perform costing.enqueue_price(new.id);
  end if;
  return null;
end
$$;
comment on function costing.on_price_recorded() is
  'Trigger de costing.price_records: avisa a otros sistemas (price.approved) los precios aprobados y los de factura, y anota el recálculo de las recetas que usan ese precio si ya está vigente.';

-- ---------------------------------------------------------------------------
-- 4. Proponer un precio a mano: también 2,5 % y 5 %
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
  v_product  catalog.purchase_products;
  v_ing      catalog.ingredients;
  v_scope    core.scope_type;
  v_doc      costing.price_document;
  v_net      numeric;
  v_gross    numeric;
  v_ref      record;
  v_ref_date date;
  v_floor    date;
  v_base     record;
  v_net_unit numeric;
  v_gross_unit numeric;
  v_var_net  numeric;
  v_var_gross numeric;
  v_variation numeric;
  v_var_today numeric;
  v_back     record;
  v_back_date date;
  v_back_days integer;
  v_var_back numeric;
  v_request  uuid;
begin
  select * into v_product from catalog.purchase_products where id = p_purchase_product_id and deleted_at is null;
  if p_scope_type is null or p_scope_type not in ('group', 'brand', 'restaurant') then
    raise exception 'Elegí para quién vale el precio: el grupo, una marca o un local.' using errcode = '22023';
  end if;
  v_scope := p_scope_type::core.scope_type;
  perform org.require(v_product.id is not null
                      and costing.has_scope_permission('prices.propose', v_scope, v_product.group_id, p_brand_id, p_restaurant_id),
                      'proponer precios en ese lugar');
  if not v_product.is_active then
    raise exception 'Ese producto de compra está desactivado.' using errcode = '23514';
  end if;
  -- El alcance es del grupo del producto y coherente (una marca o un local, nunca los dos).
  if (v_scope = 'group' and (p_brand_id is not null or p_restaurant_id is not null))
     or (v_scope = 'brand' and (p_restaurant_id is not null
         or not exists (select 1 from org.brands where id = p_brand_id and group_id = v_product.group_id and deleted_at is null)))
     or (v_scope = 'restaurant' and (p_brand_id is not null
         or not exists (select 1 from org.restaurants where id = p_restaurant_id and group_id = v_product.group_id
                                                         and deleted_at is null))) then
    raise exception 'Elegí una marca o un local del grupo.' using errcode = '22023';
  end if;
  if p_supplier_id is not null
     and not exists (select 1 from catalog.suppliers where id = p_supplier_id and group_id = v_product.group_id
                                                     and is_active and deleted_at is null) then
    raise exception 'Elegí un proveedor vigente del grupo.' using errcode = '22023';
  end if;
  if length(p_notes) > 1000 then
    raise exception 'Las observaciones tienen hasta 1.000 caracteres.' using errcode = '22023';
  end if;
  if p_valid_from is null or p_valid_from < date '2000-01-01' or p_valid_from > (now() at time zone 'America/Argentina/Buenos_Aires')::date + 366 then
    raise exception 'Revisá la fecha desde la que vale el precio.' using errcode = '22023';
  end if;
  if p_package_price is null or p_package_price <= 0 or coalesce(p_discount_amount, 0) < 0
     or coalesce(p_discount_amount, 0) >= p_package_price then
    raise exception 'El precio tiene que ser mayor que cero y el descuento, menor que el precio.' using errcode = '22023';
  end if;
  if p_document_type is null or p_document_type not in ('invoice', 'no_invoice') then
    raise exception 'Elegí el comprobante: factura o precio ingresado.' using errcode = '22023';
  end if;
  v_doc := p_document_type::costing.price_document;
  if (v_doc = 'invoice' and (p_vat_rate is null or p_vat_rate not in (0, 2.5, 5, 10.5, 21, 27)))
     or (v_doc = 'no_invoice' and p_vat_rate is not null) then
    raise exception 'Con factura, elegí la alícuota de IVA (0; 2,5; 5; 10,5; 21 o 27); sin factura no lleva IVA.' using errcode = '22023';
  end if;
  -- Por ahora se cargan a mano o como valores de prueba (los de factura entran al dar la factura por conforme, Fase 3).
  if p_source is null or p_source not in ('manual', 'test_value') then
    raise exception 'El origen del precio es una carga manual o un valor de prueba.' using errcode = '22023';
  end if;

  -- Las propuestas de la misma materia prima, de a una por vez.
  select * into v_ing from catalog.ingredients where id = v_product.ingredient_id for update;
  v_floor := costing.valid_from_floor(p_purchase_product_id, v_scope, p_brand_id, p_restaurant_id);
  if v_floor is not null and p_valid_from < v_floor then
    raise exception 'Un precio nuevo no puede empezar antes que el que vale hoy en ese lugar (%). Cargalo desde esa fecha o después.',
      to_char(v_floor, 'DD/MM/YYYY') using errcode = '23514';
  end if;
  if exists (select 1 from workflow.approval_requests r
               join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code in ('costing.approve_price', 'costing.approve_price_direction') and r.status = 'pending'
                and r.deleted_at is null and r.entity_id = p_purchase_product_id
                and r.proposed_changes ->> 'scope_type' = p_scope_type
                and (r.proposed_changes ->> 'brand_id') is not distinct from p_brand_id::text
                and (r.proposed_changes ->> 'restaurant_id') is not distinct from p_restaurant_id::text
                and (r.proposed_changes ->> 'valid_from')::date = p_valid_from) then
    raise exception 'Ya hay un precio pendiente para ese producto, lugar y fecha: esperá a que se decida o pedí que lo retiren.'
      using errcode = '23505';
  end if;

  select a.net_amount, a.gross_amount into v_net, v_gross
    from costing.package_amounts(p_package_price, coalesce(p_discount_amount, 0), v_doc, p_vat_rate,
                                 coalesce(p_price_includes_vat, true)) a;
  -- El precio por unidad de uso (g, ml o unidad): así se compara con otro producto de otro tamaño.
  select b.base_quantity, b.status into v_base
    from catalog.to_base_quantity(v_product.ingredient_id, v_product.content_per_unit * v_product.units_per_package,
                                  v_product.content_unit_id) b;
  if v_base.status <> 'ok' or coalesce(v_base.base_quantity, 0) <= 0 then
    raise exception 'El contenido de ese producto no se pasa a la unidad de uso de la materia prima: cargá primero su conversión.'
      using errcode = '23514';
  end if;
  v_net_unit := v_net / v_base.base_quantity;
  v_gross_unit := v_gross / v_base.base_quantity;
  -- La variación es contra el costo que se usa hoy en ese lugar (con herencia y cualquier producto), con y
  -- sin IVA: la más grande de las dos. Sin referencia (el primer precio) alcanza con el Controller.
  v_ref_date := greatest(p_valid_from, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  select * into v_ref
    from costing.reference_price(v_product.ingredient_id, v_scope, v_product.group_id, p_brand_id, p_restaurant_id, v_ref_date);
  if v_ref.price_record_id is not null then
    v_var_net := round((v_net_unit - v_ref.net_unit_cost) / v_ref.net_unit_cost * 100, 2);
    v_var_gross := round((v_gross_unit - v_ref.gross_unit_cost) / v_ref.gross_unit_cost * 100, 2);
    v_var_today := case when abs(v_var_gross) > abs(v_var_net) then v_var_gross else v_var_net end;
  end if;
  -- Subas en escalones (respuesta 8 de Soy, ADR-0030): también contra el precio de hace N días en ese
  -- lugar. Vale la variación más grande: varias subas chicas seguidas llegan a Dirección.
  select coalesce(s.lookback_days, 30) into v_back_days
    from (select 1) x left join costing.price_settings s on s.group_id = v_product.group_id and s.deleted_at is null;
  v_back_date := v_ref_date - v_back_days;
  select * into v_back
    from costing.reference_price(v_product.ingredient_id, v_scope, v_product.group_id, p_brand_id, p_restaurant_id, v_back_date);
  if v_back.price_record_id is not null and v_back.price_record_id is distinct from v_ref.price_record_id then
    v_var_net := round((v_net_unit - v_back.net_unit_cost) / v_back.net_unit_cost * 100, 2);
    v_var_gross := round((v_gross_unit - v_back.gross_unit_cost) / v_back.gross_unit_cost * 100, 2);
    v_var_back := case when abs(v_var_gross) > abs(v_var_net) then v_var_gross else v_var_net end;
  end if;
  v_variation := case when v_var_back is not null and (v_var_today is null or abs(v_var_back) > abs(v_var_today))
                      then v_var_back else v_var_today end;

  v_request := workflow.request_approval(
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
                       'net_package_price', v_net, 'gross_package_price', v_gross,
                       'net_unit_cost', round(v_net_unit, 8), 'gross_unit_cost', round(v_gross_unit, 8),
                       'base_quantity', v_base.base_quantity, 'recipe_unit_id', v_ing.recipe_unit_id,
                       'price_variation_pct', v_variation, 'price_variation_today_pct', v_var_today,
                       'price_variation_lookback_pct', v_var_back, 'lookback_days', v_back_days,
                       'lookback_price_record_id', v_back.price_record_id,
                       'reference_price_record_id', v_ref.price_record_id, 'reference_as_of', v_ref_date),
    case when v_ref.price_record_id is null then jsonb_build_object('net_unit_cost', null)
         else jsonb_build_object('net_unit_cost', round(v_ref.net_unit_cost, 8),
                                 'gross_unit_cost', round(v_ref.gross_unit_cost, 8)) end,
    p_reason);
  return v_request;
end
$$;
comment on function costing.propose_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text, text, text) is
  'Propone un precio para un producto de compra en el grupo, una marca o un local: crea la solicitud costing.approve_price con el antes, el después y la variación: la más grande entre la del costo que se usa hoy en ese lugar y la del que valía hace N días (lookback_days). Pide prices.propose en ese lugar y un motivo. Devuelve el id de la solicitud.';
