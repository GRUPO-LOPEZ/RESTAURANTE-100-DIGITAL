-- Fase 3, Prompt 5 (ADR-0058): correcciones de la revisión de base (db-reviewer) y de seguridad (security-auditor) del
-- PR 5A, antes de fusionarlo. Ninguna migración anterior se edita.
--
-- - No se factura dos veces la misma mercadería: una OC facturada entera no se vuelve a facturar, el control descuenta
--   lo ya facturado en otras facturas vigentes y dos líneas de la factura no van contra la misma línea de la OC.
-- - Separación de funciones (decisión 2 de Soy): no da por conforme a mano quien cargó la factura, ni quien la corrigió,
--   ni quien le sumó una nota (edited_by); y aprueba la versión que vio (p_version).
-- - Doble firma (Joaco, 2026-11-18): el conforme automático no vale si quien controla cargó o aceptó la lista de precios
--   vigente de ese proveedor; la factura queda observada y la da otra persona.
-- - Doble verificación (Joaco, 2026-11-18): Compras carga facturas que escriben costos, así que su rol la exige, como el
--   Controller; «Cargar facturas» pasa a ser sensible.
-- - Sin fecha futura, y un precio de factura no reescribe costos pasados (el mismo piso que el precio cargado a mano).
-- - Una nota de crédito cuenta para cubrir la diferencia recién con su foto.
-- - Defensa en profundidad: un precio de factura entra solo desde una línea de una factura conforme, del mismo producto
--   y local, y aprobado por quien la dio por conforme.

-- ---------------------------------------------------------------------------
-- 1. Doble verificación para Compras, y «Cargar facturas» sensible
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Compras carga facturas que escriben costos: doble verificación (ADR-0058)',
                                  'maintenance');
  update core.roles set requires_mfa = true where code = 'purchasing' and deleted_at is null;
  update core.permissions set is_sensitive = true where code = 'purchasing.manage_invoices' and deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Quién la corrigió
-- ---------------------------------------------------------------------------
alter table purchasing.invoices add column edited_by uuid[] not null default '{}';
comment on column purchasing.invoices.edited_by is
  'Quiénes guardaron cambios o sumaron notas mientras estaba cargada u observada. Ninguno puede darla por conforme a mano (decisión 2 de Soy).';

-- Sin fecha futura (revisión de base y de seguridad).
create or replace function purchasing.apply_invoice_header(p_inv purchasing.invoices, p_header jsonb)
returns purchasing.invoices
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_bad    text;
  v_header jsonb := coalesce(p_header, '{}'::jsonb);
  v_inv    purchasing.invoices;
  v_terms  purchasing.supplier_payment_terms;
begin
  if jsonb_typeof(v_header) <> 'object' then
    raise exception 'Faltan los datos de la factura.' using errcode = '22023';
  end if;
  select k into v_bad from jsonb_object_keys(v_header) k
   where k <> all (array['invoice_class', 'point_of_sale', 'number', 'authorization_kind', 'authorization_code',
                         'authorization_expires_on', 'issuer_tax_id', 'receiver_tax_id', 'issued_on', 'due_on',
                         'net_amount', 'exempt_amount', 'vat_amount', 'internal_tax_amount', 'perception_amount',
                         'discount_amount', 'rounding_amount', 'total_amount', 'supplier_balance_amount', 'remito_refs',
                         'supplier_order_ref', 'notes'])
   limit 1;
  if v_bad is not null then
    raise exception 'La factura no lleva el dato «%».', v_bad using errcode = '22023';
  end if;
  foreach v_bad in array array['issuer_tax_id', 'receiver_tax_id'] loop
    if v_header ? v_bad and jsonb_typeof(v_header -> v_bad) = 'string' then
      v_header := jsonb_set(v_header, array[v_bad], to_jsonb(nullif(core.normalize_cuit(v_header ->> v_bad), '')));
    end if;
  end loop;
  -- Un vencimiento escrito es el impreso; sin él, sale de la condición de pago del proveedor.
  v_inv := jsonb_populate_record(p_inv, v_header - 'due_on');
  if v_header ? 'due_on' and nullif(v_header ->> 'due_on', '') is not null then
    v_inv.due_on := (v_header ->> 'due_on')::date;
    v_inv.due_on_source := 'printed';
  elsif v_header ? 'due_on' or v_inv.due_on is null or v_inv.due_on_source = 'terms' then
    select * into v_terms from purchasing.supplier_payment_terms
     where supplier_id = v_inv.supplier_id and deleted_at is null;
    v_inv.due_on := v_inv.issued_on + case when v_terms.payment_terms = 'account' then v_terms.payment_days else 0 end;
    v_inv.due_on_source := 'terms';
  end if;
  if v_inv.issued_on > recipes.today() then
    raise exception 'La fecha de la factura no puede ser posterior a hoy.' using errcode = '22023';
  end if;
  if v_inv.due_on < v_inv.issued_on then
    raise exception 'El vencimiento no puede ser anterior a la fecha de la factura.' using errcode = '22023';
  end if;
  return v_inv;
end
$$;
comment on function purchasing.apply_invoice_header(purchasing.invoices, jsonb) is
  'Interna: aplica a una factura los datos de cabecera permitidos (CUIT sin guiones). El vencimiento escrito es el impreso; si no hay, sale de la condición de pago del proveedor (contado, el mismo día; cuenta corriente, la fecha + los días).';
revoke execute on function purchasing.apply_invoice_header(purchasing.invoices, jsonb) from public;


-- Dos líneas de la factura no van contra la misma línea de la OC (revisión de base).
create or replace function purchasing.write_invoice_lines(p_inv purchasing.invoices, p_lines jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line     jsonb;
  v_order    integer := 0;
  v_class    purchasing.invoice_line_class;
  v_product  uuid;
  v_unmapped uuid;
  v_new      boolean;
  v_pol      uuid;
  v_qty      numeric;
  v_price    numeric;
  v_count    integer := 0;
  v_bad      text;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Faltan las líneas de la factura.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) > 600 then
    raise exception 'Una factura va hasta 600 líneas.' using errcode = '22023';
  end if;
  update purchasing.invoice_lines set deleted_at = now() where invoice_id = p_inv.id and deleted_at is null;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_order := v_order + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'La línea % no se entiende.', v_order using errcode = '22023';
    end if;
    select k into v_bad from jsonb_object_keys(v_line) k
     where k <> all (array['line_class', 'purchase_product_id', 'purchase_order_line_id', 'raw_name', 'supplier_sku',
                           'units', 'billed_quantity', 'list_price', 'bonus1_pct', 'bonus2_pct',
                           'bonus_per_unit_amount', 'unit_price', 'vat_rate', 'is_exempt', 'internal_tax_amount',
                           'line_amount'])
     limit 1;
    if v_bad is not null then
      raise exception 'La línea % no lleva el dato «%».', v_order, v_bad using errcode = '22023';
    end if;
    v_class := coalesce(nullif(v_line ->> 'line_class', ''), 'product')::purchasing.invoice_line_class;
    v_product := nullif(v_line ->> 'purchase_product_id', '')::uuid;
    v_pol := nullif(v_line ->> 'purchase_order_line_id', '')::uuid;
    v_unmapped := null;
    v_new := false;
    v_qty := (v_line ->> 'billed_quantity')::numeric;
    v_price := (v_line ->> 'unit_price')::numeric;
    if v_qty is null or v_qty = 'NaN'::numeric or v_price is null or v_price = 'NaN'::numeric then
      raise exception 'Escribí la cantidad y el precio de la línea %.', v_order using errcode = '22023';
    end if;
    if v_class in ('product', 'free_of_charge') then
      if v_product is not null then
        if not exists (select 1 from catalog.purchase_products p
                        where p.id = v_product and p.supplier_id = p_inv.supplier_id and p.deleted_at is null) then
          raise exception 'El producto de la línea % no es de este proveedor.', v_order using errcode = '22023';
        end if;
      else
        select m.purchase_product_id, m.unmapped_article_id, m.is_new into v_product, v_unmapped, v_new
          from purchasing.match_invoice_article(p_inv, v_line ->> 'supplier_sku', v_line ->> 'raw_name') m;
        if v_new then
          v_count := v_count + 1;
        end if;
      end if;
      if v_pol is not null then
        if not exists (select 1 from purchasing.purchase_order_lines l
                         join purchasing.invoice_orders io on io.purchase_order_id = l.purchase_order_id
                        where l.id = v_pol and io.invoice_id = p_inv.id and io.deleted_at is null
                          and l.deleted_at is null
                          and (v_product is null or l.purchase_product_id = v_product)) then
          raise exception 'La línea % no corresponde a una línea de las órdenes de esta factura.', v_order
            using errcode = '22023';
        end if;
        if exists (select 1 from purchasing.invoice_lines x
                    where x.invoice_id = p_inv.id and x.deleted_at is null and x.purchase_order_line_id = v_pol) then
          raise exception 'La línea % repite una línea de la OC que ya está en esta factura.', v_order using errcode = '22023';
        end if;
      elsif v_product is not null and v_class = 'product' then
        -- Se asocia sola a la línea de la OC con ese producto (la primera que todavía no tiene).
        select l.id into v_pol
          from purchasing.purchase_order_lines l
          join purchasing.invoice_orders io on io.purchase_order_id = l.purchase_order_id
         where io.invoice_id = p_inv.id and io.deleted_at is null and l.deleted_at is null
           and l.purchase_product_id = v_product
           and not exists (select 1 from purchasing.invoice_lines x
                            where x.invoice_id = p_inv.id and x.deleted_at is null and x.purchase_order_line_id = l.id)
         order by l.line_order
         limit 1;
      end if;
    end if;
    insert into purchasing.invoice_lines (group_id, invoice_id, line_order, line_class, purchase_product_id,
                                          unmapped_article_id, purchase_order_line_id, raw_name, supplier_sku, units,
                                          billed_quantity, list_price, bonus1_pct, bonus2_pct, bonus_per_unit_amount,
                                          unit_price, vat_rate, is_exempt, internal_tax_amount, line_amount)
    values (p_inv.group_id, p_inv.id, v_order, v_class, v_product, v_unmapped,
            case when v_class in ('product', 'free_of_charge') then v_pol end,
            btrim(v_line ->> 'raw_name'), nullif(btrim(v_line ->> 'supplier_sku'), ''),
            nullif(v_line ->> 'units', '')::numeric, v_qty, nullif(v_line ->> 'list_price', '')::numeric,
            coalesce(nullif(v_line ->> 'bonus1_pct', '')::numeric, 0),
            coalesce(nullif(v_line ->> 'bonus2_pct', '')::numeric, 0),
            coalesce(nullif(v_line ->> 'bonus_per_unit_amount', '')::numeric, 0), v_price,
            case when purchasing.invoice_is_a(p_inv.invoice_class) or p_inv.invoice_class in ('invoice_b', 'invoice_c')
                 then nullif(v_line ->> 'vat_rate', '')::numeric end,
            coalesce((v_line ->> 'is_exempt')::boolean, false),
            coalesce(nullif(v_line ->> 'internal_tax_amount', '')::numeric, 0),
            coalesce(nullif(v_line ->> 'line_amount', '')::numeric, round(v_qty * v_price, 2)));
  end loop;
  return v_count;
end
$$;
comment on function purchasing.write_invoice_lines(purchasing.invoices, jsonb) is
  'Interna: reemplaza las líneas de una factura cargada u observada (las anteriores quedan dadas de baja). Reconoce cada artículo o lo manda a la cola de mapeo, y asocia cada línea a la de la OC con su producto. Devuelve cuántos artículos nuevos fueron a la cola.';
revoke execute on function purchasing.write_invoice_lines(purchasing.invoices, jsonb) from public;


-- Las claves de cada percepción se validan (revisión de seguridad).
create or replace function purchasing.write_invoice_taxes(p_inv purchasing.invoices, p_taxes jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tax jsonb;
  v_bad text;
begin
  if p_taxes is null or jsonb_typeof(p_taxes) <> 'array' then
    raise exception 'Faltan las percepciones de la factura (una lista, aunque esté vacía).' using errcode = '22023';
  end if;
  update purchasing.invoice_taxes set deleted_at = now() where invoice_id = p_inv.id and deleted_at is null;
  for v_tax in select value from jsonb_array_elements(p_taxes) loop
    if jsonb_typeof(v_tax) <> 'object' then
      raise exception 'Una percepción no se entiende.' using errcode = '22023';
    end if;
    select k into v_bad from jsonb_object_keys(v_tax) k
     where k <> all (array['tax_kind', 'jurisdiction', 'regime', 'rate_pct', 'tax_amount']) limit 1;
    if v_bad is not null then
      raise exception 'Una percepción no lleva el dato «%».', v_bad using errcode = '22023';
    end if;
    insert into purchasing.invoice_taxes (group_id, invoice_id, tax_kind, jurisdiction, regime, rate_pct, tax_amount)
    values (p_inv.group_id, p_inv.id, (v_tax ->> 'tax_kind')::purchasing.invoice_tax_kind,
            nullif(btrim(v_tax ->> 'jurisdiction'), ''), nullif(btrim(v_tax ->> 'regime'), ''),
            nullif(v_tax ->> 'rate_pct', '')::numeric, (v_tax ->> 'tax_amount')::numeric);
  end loop;
end
$$;
comment on function purchasing.write_invoice_taxes(purchasing.invoices, jsonb) is
  'Interna: reemplaza las percepciones y otros tributos de una factura cargada u observada.';
revoke execute on function purchasing.write_invoice_taxes(purchasing.invoices, jsonb) from public;

-- Quien guarda cambios queda anotado: no puede darla por conforme a mano (revisión de base y de seguridad).
create or replace function purchasing.save_invoice(p_id uuid, p_header jsonb, p_lines jsonb, p_taxes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv        purchasing.invoices;
  v_new        integer := 0;
  v_reason     text := nullif(btrim(p_reason), '');
  v_constraint text;
  v_message    text;
  v_state      text;
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.save_invoice', 'No tenés permiso para cambiar esta factura.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí el motivo del cambio.' using errcode = '22023';
  end if;
  select * into v_inv from purchasing.invoices where id = p_id for update;
  if v_inv.status not in ('loaded', 'observed') then
    raise exception 'Una factura conforme no cambia: corregila con una nota de crédito o débito.' using errcode = '23514';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  begin
    v_inv := purchasing.apply_invoice_header(v_inv, p_header);
    v_inv.status := 'loaded';
    v_inv.observed_reason := null;
    update purchasing.invoices i
       set invoice_class = v_inv.invoice_class, point_of_sale = v_inv.point_of_sale, number = v_inv.number,
           authorization_kind = v_inv.authorization_kind, authorization_code = v_inv.authorization_code,
           authorization_expires_on = v_inv.authorization_expires_on, issuer_tax_id = v_inv.issuer_tax_id,
           receiver_tax_id = v_inv.receiver_tax_id, issued_on = v_inv.issued_on, due_on = v_inv.due_on,
           due_on_source = v_inv.due_on_source, net_amount = v_inv.net_amount, exempt_amount = v_inv.exempt_amount,
           vat_amount = v_inv.vat_amount, internal_tax_amount = v_inv.internal_tax_amount,
           perception_amount = v_inv.perception_amount, discount_amount = v_inv.discount_amount,
           rounding_amount = v_inv.rounding_amount, total_amount = v_inv.total_amount,
           supplier_balance_amount = v_inv.supplier_balance_amount, remito_refs = v_inv.remito_refs,
           supplier_order_ref = v_inv.supplier_order_ref, notes = v_inv.notes, status = 'loaded',
           observed_reason = null,
           edited_by = case when core.current_actor_id() = any (i.edited_by) then i.edited_by
                            else i.edited_by || core.current_actor_id() end
     where i.id = v_inv.id;
    if p_lines is not null then
      v_new := purchasing.write_invoice_lines(v_inv, p_lines);
    end if;
    if p_taxes is not null then
      perform purchasing.write_invoice_taxes(v_inv, p_taxes);
    end if;
  exception
    when check_violation or unique_violation or not_null_violation or foreign_key_violation
         or invalid_text_representation then
      get stacked diagnostics v_constraint = constraint_name, v_message = message_text, v_state = returned_sqlstate;
      if v_state = '22P02' then
        raise exception 'Hay un dato que no se entiende (un número, una fecha o una opción): revisá la factura.'
          using errcode = '22023';
      end if;
      perform purchasing.raise_invoice_error(v_state, v_constraint, v_message);
  end;
  perform purchasing.notify_unmapped_invoice(v_inv, v_new);
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id, 'new_unmapped', v_new);
end
$$;
comment on function purchasing.save_invoice(uuid, jsonb, jsonb, jsonb, text) is
  'Guarda en lote los cambios de una factura cargada u observada: la cabecera y, si vienen, las líneas y las percepciones (cada lista se reemplaza entera). Vuelve a «cargada». Pide purchasing.manage_invoices en el local y un motivo.';
revoke execute on function purchasing.save_invoice(uuid, jsonb, jsonb, jsonb, text) from public;
grant execute on function purchasing.save_invoice(uuid, jsonb, jsonb, jsonb, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Un precio de factura viene de una factura conforme (defensa en profundidad)
-- ---------------------------------------------------------------------------
create function costing.check_invoice_price()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.invoice_line_id is null then
    return new;
  end if;
  if not exists (
    select 1
      from purchasing.invoice_lines l
      join purchasing.invoices i on i.id = l.invoice_id
     where l.id = new.invoice_line_id and l.deleted_at is null and l.line_class = 'product'
       and l.purchase_product_id = new.purchase_product_id
       and i.status = 'approved' and i.approved_by = new.approved_by and i.group_id = new.group_id
       and new.scope_type = 'restaurant' and new.restaurant_id = i.restaurant_id and new.source = 'invoice') then
    raise exception 'Un precio de factura sale de una línea de una factura conforme, del mismo producto y local.'
      using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function costing.check_invoice_price() is
  'Trigger de costing.price_records: un precio con línea de factura tiene que venir de una factura conforme, del mismo producto y local, con origen «invoice» y aprobado por quien la dio por conforme.';
revoke execute on function costing.check_invoice_price() from public;
create trigger check_invoice_price before insert on costing.price_records
  for each row execute function costing.check_invoice_price();


-- Proveedor activo, OC no facturadas enteras, líneas bloqueadas, lo ya facturado se descuenta y errores en español.
create or replace function purchasing.create_invoice(p_supplier_id uuid, p_restaurant_id uuid, p_order_ids uuid[], p_header jsonb,
                                          p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r          org.restaurants;
  v_s          catalog.suppliers;
  v_le         org.legal_entities;
  v_inv        purchasing.invoices;
  v_order_id   uuid;
  v_list       uuid;
  v_lines      jsonb := '[]'::jsonb;
  v_new        integer;
  v_reason     text := nullif(btrim(p_reason), '');
  v_constraint text;
  v_message    text;
  v_state      text;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_r.id) then
    return core.deny('purchasing.create_invoice', 'No tenés permiso para cargar facturas en este local.', null,
                     jsonb_build_object('restaurant_id', p_restaurant_id, 'supplier_id', p_supplier_id),
                     v_r.group_id, v_r.brand_id, v_r.id);
  end if;
  select * into v_s from catalog.suppliers
   where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null and is_active;
  if v_s.id is null then
    raise exception 'Elegí un proveedor activo de este grupo.' using errcode = '22023';
  end if;
  foreach v_order_id in array coalesce(p_order_ids, '{}') loop
    if not exists (select 1 from purchasing.purchase_orders o
                    where o.id = v_order_id and o.deleted_at is null and o.supplier_id = v_s.id
                      and o.restaurant_id = v_r.id and o.status in ('received', 'partially_received')) then
      raise exception 'Cada orden tiene que ser de este proveedor y este local, estar recibida y no estar facturada entera.'
        using errcode = '22023';
    end if;
  end loop;
  -- Dos facturas a la vez sobre la misma OC: la segunda espera a la primera.
  perform 1 from purchasing.purchase_order_lines where purchase_order_id = any (coalesce(p_order_ids, '{}')) for update;
  perform core.set_change_context(coalesce(left(v_reason, 500), 'Factura cargada'), 'manual');

  select * into v_le from org.legal_entities where id = v_r.legal_entity_id;
  v_inv.group_id := v_r.group_id;
  v_inv.brand_id := v_r.brand_id;
  v_inv.restaurant_id := v_r.id;
  v_inv.supplier_id := v_s.id;
  v_inv.legal_entity_id := v_le.id;
  v_inv.legal_entity_tax_id := v_le.tax_id;
  v_inv.loaded_by := core.current_actor_id();
  v_inv.status := 'loaded';
  begin
    v_inv := purchasing.apply_invoice_header(v_inv, p_header);
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'Hay un dato que no se entiende (un número, una fecha o una opción): revisá la factura.' using errcode = '22023';
  end;
  if v_inv.invoice_class is null or v_inv.number is null or v_inv.issued_on is null then
    raise exception 'Elegí la clase de comprobante y escribí el número y la fecha.' using errcode = '22023';
  end if;
  v_inv.id := gen_random_uuid();
  v_inv.net_amount := coalesce(v_inv.net_amount, 0);
  v_inv.exempt_amount := coalesce(v_inv.exempt_amount, 0);
  v_inv.vat_amount := coalesce(v_inv.vat_amount, 0);
  v_inv.internal_tax_amount := coalesce(v_inv.internal_tax_amount, 0);
  v_inv.perception_amount := coalesce(v_inv.perception_amount, 0);
  v_inv.discount_amount := coalesce(v_inv.discount_amount, 0);
  v_inv.rounding_amount := coalesce(v_inv.rounding_amount, 0);
  v_inv.total_amount := coalesce(v_inv.total_amount, 0);
  v_inv.currency := 'ARS';
  v_inv.edited_by := '{}';
  begin
    insert into purchasing.invoices select v_inv.*;
    insert into purchasing.invoice_orders (group_id, invoice_id, purchase_order_id)
    select v_inv.group_id, v_inv.id, o from (select distinct unnest(coalesce(p_order_ids, '{}')) as o) x;

    -- Las líneas, desde lo recibido de cada OC, con el precio de la lista a la fecha.
    v_list := purchasing.price_list_at(v_s.id, v_inv.issued_on);
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'line_class', 'product', 'purchase_product_id', x.product_id, 'purchase_order_line_id', x.pol_id,
             'raw_name', x.description, 'supplier_sku', x.supplier_sku,
             'units', case when x.by_weight then x.received end,
             'billed_quantity', x.billed,
             'list_price', e.list_price, 'bonus1_pct', e.bonus1_pct, 'bonus2_pct', e.bonus2_pct,
             'bonus_per_unit_amount', e.bonus_per_unit_amount,
             'unit_price', coalesce(e.expected_price, 0), 'vat_rate', e.vat_rate,
             'line_amount', round(x.billed * coalesce(e.expected_price, 0), 2)))
             order by x.order_number, x.line_order), '[]'::jsonb)
      into v_lines
      from (select l.id as pol_id, l.line_order, o.number as order_number, p.id as product_id, p.description,
                   p.supplier_sku, p.billed_by_weight as by_weight, l.received_quantity as received,
                   case when p.billed_by_weight then
                          coalesce(nullif((select sum(rl.received_weight) from purchasing.receipt_lines rl
                                             join purchasing.receipts rc on rc.id = rl.receipt_id
                                            where rl.purchase_order_line_id = l.id and rl.deleted_at is null
                                              and rc.status = 'closed' and rc.deleted_at is null), 0),
                                   l.received_quantity * p.estimated_weight_per_unit, l.received_quantity)
                        else l.received_quantity end
                   -- Lo que ya está en otras facturas vigentes de esa línea no se vuelve a facturar.
                   - coalesce((select sum(x2.billed_quantity) from purchasing.invoice_lines x2
                                 join purchasing.invoices i2 on i2.id = x2.invoice_id
                                where x2.purchase_order_line_id = l.id and x2.deleted_at is null
                                  and i2.deleted_at is null and i2.status <> 'cancelled'), 0) as billed
              from purchasing.purchase_order_lines l
              join purchasing.purchase_orders o on o.id = l.purchase_order_id
              join catalog.purchase_products p on p.id = l.purchase_product_id
             where l.purchase_order_id = any (coalesce(p_order_ids, '{}')) and l.deleted_at is null
               and l.received_quantity > 0) x
      left join lateral purchasing.expected_invoice_price(v_list, x.product_id,
                                                          purchasing.invoice_is_a(v_inv.invoice_class)) e on true
     where x.billed > 0;
    v_new := purchasing.write_invoice_lines(v_inv, v_lines);
  exception
    when check_violation or unique_violation or not_null_violation or foreign_key_violation then
      get stacked diagnostics v_constraint = constraint_name, v_message = message_text, v_state = returned_sqlstate;
      perform purchasing.raise_invoice_error(v_state, v_constraint, v_message);
  end;
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id);
end
$$;
comment on function purchasing.create_invoice(uuid, uuid, uuid[], jsonb, text) is
  '«+ Nueva factura»: crea una factura cargada de un proveedor en un local, con las OC recibidas que cubre (o ninguna, P4). Las líneas salen de lo recibido, con el precio de la lista vigente a la fecha. Pide purchasing.manage_invoices en el local. El CUIT del emisor tiene que ser el del proveedor.';
revoke execute on function purchasing.create_invoice(uuid, uuid, uuid[], jsonb, text) from public;
grant execute on function purchasing.create_invoice(uuid, uuid, uuid[], jsonb, text) to authenticated;


-- El control: lo ya facturado se descuenta, lo mapeado después se asocia a su OC, las notas cuentan con su foto y no
-- vale el conforme automático de quien cargó o aceptó la lista vigente (decisión de Joaco, 2026-11-18).
create or replace function purchasing.check_invoice(p_id uuid)
returns purchasing.invoice_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv        purchasing.invoices;
  v_run        uuid := gen_random_uuid();
  v_is_a       boolean;
  v_list       uuid;
  v_tolerance  numeric;
  v_has_orders boolean;
  v_line       record;
  v_expected   record;
  v_received   numeric;
  v_kg         numeric;
  v_compare    numeric;
  v_diff       numeric := 0;
  v_hard       integer := 0;
  v_soft       integer := 0;
  v_notes      numeric;
  v_sum        numeric;
  v_reasons    text[] := '{}';
  v_status     purchasing.invoice_status;
  v_previous   purchasing.invoice_status;
begin
  select * into v_inv from purchasing.invoices where id = p_id for update;
  v_previous := v_inv.status;
  if v_inv.status not in ('loaded', 'observed') then
    raise exception 'Esta factura ya no está para controlar.' using errcode = '23514';
  end if;
  if not exists (select 1 from purchasing.attachments a
                  where a.source_table = 'invoices' and a.source_id = v_inv.id and a.doc_kind = 'invoice_original') then
    raise exception 'Falta la foto de la factura.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.invoice_lines where invoice_id = v_inv.id and deleted_at is null) then
    raise exception 'La factura no tiene líneas.' using errcode = '22023';
  end if;
  v_is_a := purchasing.invoice_is_a(v_inv.invoice_class);
  v_list := purchasing.price_list_at(v_inv.supplier_id, v_inv.issued_on);
  select coalesce((select invoice_weight_tolerance_pct from costing.price_settings
                    where group_id = v_inv.group_id and deleted_at is null), 0.5) into v_tolerance;
  v_has_orders := exists (select 1 from purchasing.invoice_orders where invoice_id = v_inv.id and deleted_at is null);

  -- Un artículo que el chef ya mapeó pasa a la línea.
  update purchasing.invoice_lines l
     set purchase_product_id = u.purchase_product_id, unmapped_article_id = null
    from purchasing.unmapped_articles u
   where l.invoice_id = v_inv.id and l.deleted_at is null and l.unmapped_article_id = u.id
     and u.status = 'resolved' and u.purchase_product_id is not null
     and exists (select 1 from catalog.purchase_products p
                  where p.id = u.purchase_product_id and p.supplier_id = v_inv.supplier_id);
  -- Y a la línea de la OC con ese producto que todavía no tenga (como al guardar).
  update purchasing.invoice_lines l
     set purchase_order_line_id = (
           select pol.id from purchasing.purchase_order_lines pol
             join purchasing.invoice_orders io on io.purchase_order_id = pol.purchase_order_id
            where io.invoice_id = v_inv.id and io.deleted_at is null and pol.deleted_at is null
              and pol.purchase_product_id = l.purchase_product_id
              and not exists (select 1 from purchasing.invoice_lines x
                               where x.invoice_id = v_inv.id and x.deleted_at is null and x.purchase_order_line_id = pol.id)
            order by pol.line_order limit 1)
   where l.invoice_id = v_inv.id and l.deleted_at is null and l.line_class = 'product'
     and l.purchase_product_id is not null and l.purchase_order_line_id is null
     and exists (select 1 from purchasing.invoice_orders io where io.invoice_id = v_inv.id and io.deleted_at is null);

  for v_line in
    select l.*, p.billed_by_weight, pol.received_quantity as pol_received,
           coalesce(o.billed, 0) as other_billed, coalesce(o.units, 0) as other_units
      from purchasing.invoice_lines l
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join purchasing.purchase_order_lines pol on pol.id = l.purchase_order_line_id
      -- Lo que ya está facturado de esa línea de la OC en otras facturas vigentes.
      left join lateral (select sum(x.billed_quantity) as billed, sum(coalesce(x.units, x.billed_quantity)) as units
                           from purchasing.invoice_lines x
                           join purchasing.invoices i on i.id = x.invoice_id
                          where x.purchase_order_line_id = l.purchase_order_line_id and x.invoice_id <> l.invoice_id
                            and x.deleted_at is null and i.deleted_at is null and i.status <> 'cancelled') o on true
     where l.invoice_id = v_inv.id and l.deleted_at is null and l.line_class in ('product', 'free_of_charge')
     order by l.line_order
  loop
    -- Mapeo.
    if v_line.purchase_product_id is null then
      v_hard := v_hard + 1;
      v_reasons := v_reasons || format('«%s» no está mapeado', v_line.raw_name);
      insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind, passed, explanation)
      values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'mapping', false,
              format('«%s» no está mapeado: el chef tiene que decir qué materia prima es.', left(v_line.raw_name, 120)));
      continue;
    end if;
    insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind, passed, explanation)
    values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'mapping', true, 'Reconocido: tiene su producto de compra.');

    -- Cantidad: contra lo recibido en su línea de la OC (los regalos no se controlan).
    if v_line.line_class <> 'product' then
      null;
    elsif v_line.purchase_order_line_id is not null then
      v_received := v_line.pol_received - v_line.other_units;
      v_kg := null;
      if v_line.billed_by_weight then
        select nullif(sum(rl.received_weight), 0) into v_kg
          from purchasing.receipt_lines rl
          join purchasing.receipts rc on rc.id = rl.receipt_id
         where rl.purchase_order_line_id = v_line.purchase_order_line_id and rl.deleted_at is null
           and rc.status = 'closed' and rc.deleted_at is null;
        v_kg := v_kg - v_line.other_billed;
      end if;
      if v_kg is not null then
        if abs(v_line.billed_quantity - v_kg) <= v_kg * v_tolerance / 100 then
          insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                                 expected_amount, actual_amount, passed, explanation)
          values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'quantity', v_kg, v_line.billed_quantity, true,
                  format('Facturaron %s kg y se recibieron %s kg (dentro del %s %%).',
                         round(v_line.billed_quantity, 3), round(v_kg, 3), v_tolerance));
        else
          v_soft := v_soft + 1;
          v_diff := v_diff + greatest(v_line.billed_quantity - v_kg, 0) * v_line.unit_price;
          v_reasons := v_reasons || format('cantidad de «%s»', v_line.raw_name);
          insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                                 expected_amount, actual_amount, passed, explanation)
          values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'quantity', v_kg, v_line.billed_quantity, false,
                  format('Facturaron %s kg y se recibieron %s kg: la diferencia pasa el %s %%.',
                         round(v_line.billed_quantity, 3), round(v_kg, 3), v_tolerance));
        end if;
      else
        -- Por peso sin pesar: se controlan las unidades.
        v_compare := case when v_line.billed_by_weight then coalesce(v_line.units, v_line.billed_quantity)
                          else v_line.billed_quantity end;
        if v_compare = v_received then
          insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                                 expected_amount, actual_amount, passed, explanation)
          values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'quantity', v_received, v_compare, true,
                  case when v_line.billed_by_weight
                       then format('Sin peso en la recepción: se controlaron las unidades (%s).', round(v_compare, 3))
                       else format('Facturaron lo mismo que se recibió (%s).', round(v_compare, 3)) end);
        else
          v_soft := v_soft + 1;
          v_diff := v_diff + case when v_compare > 0
                                  then greatest(v_compare - v_received, 0) / v_compare * v_line.line_amount else 0 end;
          v_reasons := v_reasons || format('cantidad de «%s»', v_line.raw_name);
          insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                                 expected_amount, actual_amount, passed, explanation)
          values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'quantity', v_received, v_compare, false,
                  format('Facturaron %s y se recibieron %s.', round(v_compare, 3), round(v_received, 3)));
        end if;
      end if;
    elsif v_has_orders then
      -- Facturado sin estar en las OC: todo su importe es diferencia.
      v_soft := v_soft + 1;
      v_diff := v_diff + v_line.line_amount;
      v_reasons := v_reasons || format('«%s» no está en la OC', v_line.raw_name);
      insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                             expected_amount, actual_amount, passed, explanation)
      values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'quantity', 0, v_line.billed_quantity, false,
              format('«%s» no está en las órdenes de esta factura.', left(v_line.raw_name, 120)));
    end if;

    -- Precio: contra la lista vigente a la fecha de la factura (los regalos no se controlan).
    if v_line.line_class = 'product' then
      select * into v_expected from purchasing.expected_invoice_price(v_list, v_line.purchase_product_id, v_is_a);
      if v_expected.expected_price is null then
        v_hard := v_hard + 1;
        v_reasons := v_reasons || format('«%s» sin lista de precios vigente', v_line.raw_name);
        insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                               actual_amount, passed, explanation)
        values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'price', v_line.unit_price, false,
                'Sin lista de precios vigente: no hay una lista aceptada a la fecha de la factura con este artículo.');
      elsif (case when v_is_a then v_line.unit_price else round(v_line.unit_price, 2) end) = v_expected.expected_price then
        insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                               expected_amount, actual_amount, passed, explanation)
        values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'price', v_expected.expected_price, v_line.unit_price, true,
                case when v_is_a then 'El precio neto es el de la lista.' else 'El precio final es el de la lista.' end);
      else
        v_soft := v_soft + 1;
        v_diff := v_diff + greatest(v_line.unit_price - v_expected.expected_price, 0) * v_line.billed_quantity;
        v_reasons := v_reasons || format('precio de «%s»', v_line.raw_name);
        insert into purchasing.invoice_checks (group_id, invoice_id, run_id, invoice_line_id, check_kind,
                                               expected_amount, actual_amount, passed, explanation)
        values (v_inv.group_id, v_inv.id, v_run, v_line.id, 'price', v_expected.expected_price, v_line.unit_price, false,
                format('La lista dice $ %s y la factura $ %s%s.', v_expected.expected_price, v_line.unit_price,
                       case when v_is_a then ' (sin IVA)' else '' end));
      end if;
    end if;
  end loop;

  -- Totales: las líneas, los internos y las percepciones cierran con el pie (tolerancia 0,01).
  select coalesce(sum(l.line_amount + l.internal_tax_amount), 0)
    into v_sum from purchasing.invoice_lines l where l.invoice_id = v_inv.id and l.deleted_at is null;
  v_sum := v_sum + coalesce((select sum(t.tax_amount) from purchasing.invoice_taxes t
                              where t.invoice_id = v_inv.id and t.deleted_at is null), 0)
           + case when v_is_a then v_inv.vat_amount else 0 end - v_inv.discount_amount + v_inv.rounding_amount;
  if abs(v_sum - v_inv.total_amount) <= 0.01 then
    insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, expected_amount, actual_amount,
                                           passed, explanation)
    values (v_inv.group_id, v_inv.id, v_run, 'totals', v_sum, v_inv.total_amount, true,
            'Las líneas, el IVA, los internos y las percepciones suman el total.');
  else
    v_hard := v_hard + 1;
    v_reasons := v_reasons || 'los totales no cierran'::text;
    insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, expected_amount, actual_amount,
                                           passed, explanation)
    values (v_inv.group_id, v_inv.id, v_run, 'totals', v_sum, v_inv.total_amount, false,
            format('Las líneas y los impuestos suman $ %s y el total dice $ %s.', round(v_sum, 2),
                   round(v_inv.total_amount, 2)));
  end if;

  -- Razón social: la del local que compró (solo en las fiscales).
  if v_inv.invoice_class not in ('non_fiscal', 'handwritten_note') then
    if v_inv.legal_entity_tax_id is null or v_inv.receiver_tax_id is null
       or v_inv.receiver_tax_id <> v_inv.legal_entity_tax_id then
      v_hard := v_hard + 1;
      v_reasons := v_reasons || 'facturada a otra razón social'::text;
      insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, passed, explanation)
      values (v_inv.group_id, v_inv.id, v_run, 'legal_entity', false,
              case when v_inv.legal_entity_tax_id is null then 'El local no tiene razón social cargada.'
                   when v_inv.receiver_tax_id is null then 'Falta el CUIT del receptor.'
                   else 'Facturada a otra razón social: el CUIT del receptor no es el del local.' end);
    else
      insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, passed, explanation)
      values (v_inv.group_id, v_inv.id, v_run, 'legal_entity', true, 'Facturada a la razón social del local.');
    end if;
  end if;

  -- Sin OC ni recepción (un flete, un servicio): la da por conforme otra persona (P4).
  if not v_has_orders then
    v_hard := v_hard + 1;
    v_reasons := v_reasons || 'sin OC ni recepción'::text;
    insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, passed, explanation)
    values (v_inv.group_id, v_inv.id, v_run, 'order', false,
            'Sin orden de compra ni recepción: la da por conforme otra persona, distinta de quien la cargó.');
  end if;

  -- Notas: si solo fallaron cantidad o precio, las de crédito y descuento (menos las de débito) cubren la diferencia.
  if v_soft > 0 then
    select coalesce(sum(case when n.note_kind = 'debit' then -n.net_amount else n.net_amount end), 0)
      into v_notes from purchasing.credit_debit_notes n
     where n.invoice_id = v_inv.id and n.deleted_at is null
       -- Una nota cuenta con su foto registrada (revisión de seguridad).
       and exists (select 1 from purchasing.attachments a
                    where a.source_table = 'credit_debit_notes' and a.source_id = n.id and a.doc_kind = 'credit_note');
    if v_diff > 0 and v_notes >= v_diff - 0.01 then
      insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, expected_amount, actual_amount,
                                             passed, explanation)
      values (v_inv.group_id, v_inv.id, v_run, 'notes', round(v_diff, 4), v_notes, true,
              format('La diferencia de $ %s la cubren las notas ($ %s).', round(v_diff, 2), round(v_notes, 2)));
      v_soft := 0;
    else
      insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, expected_amount, actual_amount,
                                             passed, explanation)
      values (v_inv.group_id, v_inv.id, v_run, 'notes', round(v_diff, 4), v_notes, false,
              format('Diferencia de $ %s; las notas cubren $ %s.', round(v_diff, 2), round(v_notes, 2)));
    end if;
  end if;

  -- Doble firma (Joaco, 2026-11-18): quien cargó o aceptó la lista vigente de este proveedor no deja la factura conforme
  -- sola; la da otra persona.
  if v_list is not null and exists (select 1 from purchasing.price_lists l
                                     where l.id = v_list
                                       and core.current_actor_id() in (l.created_by, l.accepted_by)) then
    v_hard := v_hard + 1;
    v_reasons := v_reasons || 'la lista vigente la cargó o aceptó quien controla'::text;
    insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, passed, explanation)
    values (v_inv.group_id, v_inv.id, v_run, 'price', false,
            'La lista de precios vigente la cargó o aceptó quien controla: la da por conforme otra persona.');
  end if;

  if v_hard = 0 and v_soft = 0 then
    perform purchasing.release_invoice(v_inv.id, core.current_actor_id(), v_run);
    v_status := 'released';
  else
    update purchasing.invoices
       set status = 'observed',
           observed_reason = left('Observada: ' || array_to_string(v_reasons[1:5], '; ')
                                  || case when cardinality(v_reasons) > 5 then '…' else '.' end, 500)
     where id = v_inv.id;
    v_status := 'observed';
    if v_previous <> 'observed' then
      insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
      select u, v_inv.group_id, 'invoice_observed',
             left(format('%s observada', purchasing.invoice_label(v_inv.invoice_class, v_inv.point_of_sale,
                                                                  v_inv.number)), 200),
             left('Observada: ' || array_to_string(v_reasons[1:5], '; ') || '.', 500),
             format('/compras/facturas/%s', v_inv.id)
        from purchasing.users_with_permission(v_inv.group_id, 'purchasing.manage_invoices') u;
    end if;
  end if;
  return v_status;
end
$$;
comment on function purchasing.check_invoice(uuid) is
  'Interna: el control de 3 vías de una factura cargada u observada (cantidad, precio, mapeo, totales, razón social, OC y notas). Guarda una fila por control con su explicación y la deja conforme y liberada (registra los costos) u observada (avisa a Compras).';
revoke execute on function purchasing.check_invoice(uuid) from public;


-- Conforme primero (el trigger de precios lo exige), sin reescribir costos pasados y la cobertura calculada una vez.
create or replace function purchasing.release_invoice(p_id uuid, p_approver uuid, p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv        purchasing.invoices;
  v_label      text;
  v_line       record;
  v_price      numeric;
  v_package    numeric;
  v_kg_base    numeric;
  v_pkg_base   numeric;
  v_ref        record;
  v_rec        costing.price_records;
  v_threshold  numeric;
  v_variation  numeric;
  v_supplier   text;
  v_notes_ok   boolean;
begin
  select * into v_inv from purchasing.invoices where id = p_id for update;
  if v_inv.status not in ('loaded', 'observed') then
    raise exception 'Esta factura ya no está para dar por conforme.' using errcode = '23514';
  end if;
  v_label := purchasing.invoice_label(v_inv.invoice_class, v_inv.point_of_sale, v_inv.number);
  select coalesce(trade_name, name) into v_supplier from catalog.suppliers where id = v_inv.supplier_id;
  select coalesce((select approval_variation_pct from costing.price_settings
                    where group_id = v_inv.group_id and deleted_at is null), 15) into v_threshold;

  v_notes_ok := p_run_id is not null
                and exists (select 1 from purchasing.invoice_checks n
                             where n.invoice_id = v_inv.id and n.run_id = p_run_id and n.check_kind = 'notes' and n.passed);
  update purchasing.invoices
     set status = 'approved', approved_by = p_approver, approved_at = now(), observed_reason = null
   where id = v_inv.id;

  for v_line in
    select l.*, p.ingredient_id, p.billed_by_weight, p.units_per_package, p.content_per_unit, p.content_unit_id,
           -- Si el precio de la línea no pasó y una nota cubrió la diferencia, el costo es el de la lista.
           (select c.expected_amount from purchasing.invoice_checks c
             where c.invoice_line_id = l.id and c.check_kind = 'price' and not c.passed
               and c.run_id = p_run_id and v_notes_ok
             limit 1) as covered_price
      from purchasing.invoice_lines l
      join catalog.purchase_products p on p.id = l.purchase_product_id
     where l.invoice_id = v_inv.id and l.deleted_at is null and l.line_class = 'product'
     order by l.line_order
  loop
    v_price := coalesce(v_line.covered_price, v_line.unit_price);
    if v_price is null or v_price <= 0 then
      raise exception 'La línea «%» no tiene precio: corregila antes de darla por conforme.', v_line.raw_name
        using errcode = '23514';
    end if;
    if v_line.billed_by_weight then
      -- Por peso, el precio es por kilo: el del envase es el precio por kilo × los kilos del envase.
      select b.base_quantity into v_kg_base
        from catalog.to_base_quantity(v_line.ingredient_id, 1,
                                      (select u.id from catalog.units u where u.code = 'kg' and u.deleted_at is null)) b
       where b.status = 'ok';
      select b.base_quantity into v_pkg_base
        from catalog.to_base_quantity(v_line.ingredient_id, v_line.content_per_unit * v_line.units_per_package,
                                      v_line.content_unit_id) b
       where b.status = 'ok';
      if coalesce(v_kg_base, 0) <= 0 or coalesce(v_pkg_base, 0) <= 0 then
        raise exception '«%» va por peso, pero su materia prima no se pasa a kilos: revisá su envase o sus conversiones.',
          v_line.raw_name using errcode = '23514';
      end if;
      v_package := round(v_price * v_pkg_base / v_kg_base, 4);
    else
      v_package := v_price;
    end if;
    select * into v_ref from costing.reference_price(v_line.ingredient_id, 'restaurant', v_inv.group_id, v_inv.brand_id,
                                                     v_inv.restaurant_id, v_inv.issued_on);
    insert into costing.price_records (group_id, purchase_product_id, supplier_id, scope_type, brand_id, restaurant_id,
                                       valid_from, package_price, document_type, vat_rate, price_includes_vat,
                                       discount_amount, source, invoice_line_id, approved_by, approved_at, notes)
    values (v_inv.group_id, v_line.purchase_product_id, v_inv.supplier_id, 'restaurant', null, v_inv.restaurant_id,
            -- La historia no se reescribe: no antes del último precio del producto en el local ni del que vale hoy.
            greatest(v_inv.issued_on, coalesce(costing.valid_from_floor(v_line.purchase_product_id, 'restaurant', null,
                                                                        v_inv.restaurant_id), v_inv.issued_on)),
            v_package,
            case when purchasing.invoice_is_a(v_inv.invoice_class) then 'invoice' else 'no_invoice' end::costing.price_document,
            case when purchasing.invoice_is_a(v_inv.invoice_class) then coalesce(v_line.vat_rate, 0) end,
            case when purchasing.invoice_is_a(v_inv.invoice_class) then false else true end,
            0, 'invoice', v_line.id, p_approver, now(), left(format('%s · %s', v_label, v_supplier), 1000))
    returning * into v_rec;
    -- Variación contra el costo que se usaba: la más grande entre neto y bruto (como al proponer a mano).
    if v_ref.price_record_id is not null and v_ref.net_unit_cost > 0 and v_ref.gross_unit_cost > 0 then
      v_variation := greatest(abs(v_rec.net_package_price / v_rec.base_quantity - v_ref.net_unit_cost) / v_ref.net_unit_cost,
                              abs(v_rec.gross_package_price / v_rec.base_quantity - v_ref.gross_unit_cost)
                                / v_ref.gross_unit_cost) * 100;
      if v_variation > v_threshold then
        insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
        select u, v_inv.group_id, 'price_variation',
               left(format('«%s» varió %s %% en una factura', v_line.raw_name, round(v_variation, 1)), 200),
               left(format('Antes $ %s por unidad de uso; ahora $ %s (%s %%). Entró igual: la %s de %s quedó conforme.',
                           round(v_ref.net_unit_cost, 4), round(v_rec.net_package_price / v_rec.base_quantity, 4),
                           round(v_variation, 1), v_label, v_supplier), 500),
               format('/compras/facturas/%s', v_inv.id)
          from purchasing.users_with_permission(v_inv.group_id, 'prices.configure') u;
      end if;
    end if;
  end loop;

  update purchasing.invoices set status = 'released' where id = v_inv.id;
  -- Las OC recibidas que cubre quedan cerradas (facturadas).
  update purchasing.purchase_orders o
     set status = 'closed'
    from purchasing.invoice_orders io
   where io.invoice_id = v_inv.id and io.deleted_at is null and o.id = io.purchase_order_id and o.status = 'received';
end
$$;
comment on function purchasing.release_invoice(uuid, uuid, uuid) is
  'Interna: deja una factura conforme y liberada a pago. Registra el precio de cada línea de mercadería en costing.price_records (origen invoice, alcance del local, vigente desde la fecha de la factura; en A, neto; en las demás, el final; por peso, por kilo), avisa a Dirección si alguno varió más que el % del grupo y cierra las OC recibidas que cubre.';
revoke execute on function purchasing.release_invoice(uuid, uuid, uuid) from public;

-- Una nota ya no vuelve a controlar al cargarse (cuenta con su foto) y quien la suma queda anotado.
create or replace function purchasing.add_credit_debit_note(p_invoice_id uuid, p_note jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv        purchasing.invoices;
  v_id         uuid;
  v_status     purchasing.invoice_status;
  v_reason     text := nullif(btrim(p_reason), '');
  v_constraint text;
  v_message    text;
  v_state      text;
begin
  select * into v_inv from purchasing.invoices where id = p_invoice_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.add_credit_debit_note', 'No tenés permiso para sumar notas a esta factura.', null,
                     jsonb_build_object('invoice_id', p_invoice_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí por qué se emitió la nota.' using errcode = '22023';
  end if;
  if p_note is null or jsonb_typeof(p_note) <> 'object' then
    raise exception 'Faltan los datos de la nota.' using errcode = '22023';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  begin
    insert into purchasing.credit_debit_notes (group_id, invoice_id, note_kind, number, issued_on, net_amount,
                                               total_amount, reason)
    values (v_inv.group_id, v_inv.id, (p_note ->> 'note_kind')::purchasing.note_kind,
            nullif(btrim(p_note ->> 'number'), ''), (p_note ->> 'issued_on')::date,
            (p_note ->> 'net_amount')::numeric,
            coalesce(nullif(p_note ->> 'total_amount', '')::numeric, (p_note ->> 'net_amount')::numeric), v_reason)
    returning id into v_id;
  exception
    when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format then
      get stacked diagnostics v_constraint = constraint_name, v_message = message_text, v_state = returned_sqlstate;
      if v_state in ('22P02', '22007', '22008') then
        raise exception 'Revisá la nota: tipo, fecha e importes.' using errcode = '22023';
      end if;
      perform purchasing.raise_invoice_error(v_state, v_constraint, v_message);
  end;
  update purchasing.invoices i
     set edited_by = case when core.current_actor_id() = any (i.edited_by) then i.edited_by
                          else i.edited_by || core.current_actor_id() end
   where i.id = v_inv.id and i.status in ('loaded', 'observed');
  v_status := v_inv.status;
  return jsonb_build_object('result', 'applied', 'note_id', v_id, 'status', v_status);
end
$$;
comment on function purchasing.add_credit_debit_note(uuid, jsonb, text) is
  'Suma una nota de crédito, débito o descuento a una factura y, si está cargada u observada, la vuelve a controlar: si la nota cubre la diferencia, queda conforme. Pide purchasing.manage_invoices en el local y el motivo.';
revoke execute on function purchasing.add_credit_debit_note(uuid, jsonb, text) from public;
grant execute on function purchasing.add_credit_debit_note(uuid, jsonb, text) to authenticated;


-- La foto de una nota la hace contar: con ella, se vuelve a controlar (revisión de base y de seguridad).
create or replace function purchasing.add_invoice_attachment(p_source_table text, p_source_id uuid, p_storage_path text,
                                                  p_page smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv  purchasing.invoices;
  v_kind purchasing.doc_kind;
  v_id   uuid;
begin
  if p_source_table = 'invoices' then
    select * into v_inv from purchasing.invoices where id = p_source_id and deleted_at is null;
    v_kind := 'invoice_original';
  elsif p_source_table = 'credit_debit_notes' then
    select i.* into v_inv from purchasing.invoices i
      join purchasing.credit_debit_notes n on n.invoice_id = i.id
     where n.id = p_source_id and n.deleted_at is null and i.deleted_at is null;
    v_kind := 'credit_note';
  end if;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.add_invoice_attachment', 'No tenés permiso para sumar archivos a esta factura.', null,
                     jsonb_build_object('source_table', p_source_table, 'source_id', p_source_id),
                     v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if (p_source_table = 'invoices' and v_inv.status not in ('loaded', 'observed'))
     or (p_source_table = 'credit_debit_notes' and v_inv.status not in ('loaded', 'observed', 'approved', 'released')) then
    raise exception 'Una factura conforme no cambia: corregila con una nota de crédito o débito.' using errcode = '23514';
  end if;
  if coalesce(p_page, 1) not between 1 and 20 then
    raise exception 'Van hasta 20 páginas por archivo.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.document_parts(p_storage_path) d
                  where d.group_id = v_inv.group_id and d.source_table = p_source_table and d.source_id = p_source_id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'purchasing-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'El archivo no está subido en la carpeta de esta factura.' using errcode = '22023';
  end if;
  perform core.set_change_context(case v_kind when 'invoice_original' then 'Foto de la factura'
                                              else 'Foto de la nota de crédito o débito' end, 'manual');
  insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
  values (v_inv.group_id, p_source_table, p_source_id, v_kind, coalesce(p_page, 1), p_storage_path)
  returning id into v_id;
  if v_kind = 'credit_note' and v_inv.status in ('loaded', 'observed') then
    return jsonb_build_object('result', 'applied', 'attachment_id', v_id, 'status', purchasing.check_invoice(v_inv.id));
  end if;
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;
comment on function purchasing.add_invoice_attachment(text, uuid, text, smallint) is
  'Registra la foto o el PDF ya subido de una factura cargada u observada (invoice_original) o de una nota (credit_note), con su página. Rehacer suma otro; vale el último. Pide purchasing.manage_invoices en el local.';
revoke execute on function purchasing.add_invoice_attachment(text, uuid, text, smallint) from public;
grant execute on function purchasing.add_invoice_attachment(text, uuid, text, smallint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. «Dar por conforme» a mano: otra persona, la versión que vio
-- ---------------------------------------------------------------------------
drop function purchasing.approve_invoice(uuid, text);

-- p_version: el updated_at de la factura que vio quien aprueba. Si cambió mientras la miraba, no se aprueba.
create function purchasing.approve_invoice(p_id uuid, p_reason text, p_version timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv    purchasing.invoices;
  v_reason text := nullif(btrim(p_reason), '');
  v_name   text;
  v_actor  uuid := core.current_actor_id();
  v_run    uuid;
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.approve_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.approve_invoice', 'No tenés permiso para dar por conforme esta factura.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  select * into v_inv from purchasing.invoices where id = p_id for update;
  if v_inv.loaded_by = v_actor or v_actor = any (v_inv.edited_by)
     or exists (select 1 from purchasing.credit_debit_notes n
                 where n.invoice_id = v_inv.id and n.deleted_at is null and n.created_by = v_actor) then
    return core.deny('purchasing.approve_invoice',
                     'No podés dar por conforme una factura que cargaste o corregiste vos: la tiene que dar otra persona.',
                     null, jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí por qué la das por conforme.' using errcode = '22023';
  end if;
  if v_inv.status <> 'observed' then
    raise exception 'Solo se da por conforme a mano una factura observada: controlala primero.' using errcode = '23514';
  end if;
  if p_version is not null and p_version is distinct from v_inv.updated_at then
    raise exception 'La factura cambió mientras la mirabas: volvé a abrirla.' using errcode = '40001';
  end if;
  select l.raw_name into v_name from purchasing.invoice_lines l
   where l.invoice_id = v_inv.id and l.deleted_at is null and l.line_class in ('product', 'free_of_charge')
     and l.purchase_product_id is null
   order by l.line_order limit 1;
  if v_name is not null then
    raise exception 'Primero hay que mapear «%»: sin su materia prima no hay costo.', v_name using errcode = '23514';
  end if;
  -- La última corrida del control: si una nota con su foto cubrió la diferencia, el costo es el de la lista.
  select c.run_id into v_run from purchasing.invoice_checks c
   where c.invoice_id = v_inv.id order by c.entry_number desc limit 1;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  perform purchasing.release_invoice(v_inv.id, v_actor, v_run);
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id, 'status', 'released');
end
$$;
comment on function purchasing.approve_invoice(uuid, text, timestamptz) is
  '«Dar por conforme» a mano una factura observada: pide purchasing.approve_invoices en el local, que no la haya cargado, corregido ni sumado notas la misma persona (decisión 2 de Soy), un motivo y, si viene, que no haya cambiado desde que se miró (p_version). Deja la factura conforme y liberada, y su precio pasa a ser el costo.';
revoke execute on function purchasing.approve_invoice(uuid, text, timestamptz) from public;
grant execute on function purchasing.approve_invoice(uuid, text, timestamptz) to authenticated;
