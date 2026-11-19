-- Fase 3, Prompt 5 (ADR-0058): las funciones de las facturas. Cargar, corregir, controlar (3 vías), sumar notas, dar por
-- conforme y cancelar. Al quedar conforme, cada línea de mercadería deja su precio en costing.price_records (decisión 1
-- de Soy) y, si varió más que el % del grupo, avisa a Dirección.
--
-- Reglas del control (docs/fases/fase-3-plan.md, §6):
-- - Cantidad: lo facturado contra lo recibido en esa línea de la OC. Por peso, kilos facturados contra kilos recibidos,
--   con la tolerancia del grupo (0,5 % por defecto).
-- - Precio: contra la lista aceptada vigente a la fecha de la factura, con tolerancia 0. En A se compara el neto; en B,
--   C, X y nota a mano, el precio final (neto de lista con IVA, a centavos). Por peso, el precio por kilo (decisión de
--   Joaco, 2026-11-18).
-- - Mapeo, totales, razón social y OC (P4).
-- - Si solo fallaron cantidad o precio, y las notas de crédito o descuento cubren la diferencia, la factura queda
--   conforme; el costo es el de la lista en las líneas cubiertas.

-- ---------------------------------------------------------------------------
-- 1. Auxiliares
-- ---------------------------------------------------------------------------
-- La lista de precios vigente de un proveedor en una fecha: la aceptada (o reemplazada después) con la vigencia más
-- reciente que no pasa esa fecha.
create function purchasing.price_list_at(p_supplier_id uuid, p_date date)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select l.id
    from purchasing.price_lists l
   where l.supplier_id = p_supplier_id and l.deleted_at is null and l.status in ('accepted', 'replaced')
     and l.valid_from <= p_date
   order by l.valid_from desc, l.accepted_at desc nulls last
   limit 1
$$;
comment on function purchasing.price_list_at(uuid, date) is
  'Interna: la lista de precios vigente de un proveedor en una fecha (la aceptada o reemplazada con la vigencia más reciente que no pasa esa fecha). Vacía si no hay.';
revoke execute on function purchasing.price_list_at(uuid, date) from public;

-- Si la clase de comprobante discrimina IVA (el costo va neto con razón social responsable inscripta).
create function purchasing.invoice_is_a(p_class purchasing.invoice_class)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_class in ('invoice_a', 'invoice_remito_a')
$$;
comment on function purchasing.invoice_is_a(purchasing.invoice_class) is
  'Interna: si la clase de comprobante discrimina IVA (A o factura-remito A).';
revoke execute on function purchasing.invoice_is_a(purchasing.invoice_class) from public;

-- Cómo se escribe una factura para la gente: «A 0003-00012345», «X 00012345», «Nota a mano 12».
create function purchasing.invoice_label(p_class purchasing.invoice_class, p_point_of_sale integer, p_number bigint)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_class
           when 'invoice_a' then 'Factura A'
           when 'invoice_b' then 'Factura B'
           when 'invoice_c' then 'Factura C'
           when 'invoice_remito_a' then 'Factura-remito A'
           when 'non_fiscal' then 'Comprobante X'
           else 'Nota a mano'
         end
         || ' '
         || case when p_point_of_sale is not null then lpad(p_point_of_sale::text, 4, '0') || '-' else '' end
         || lpad(p_number::text, 8, '0')
$$;
comment on function purchasing.invoice_label(purchasing.invoice_class, integer, bigint) is
  'Cómo se lee una factura: clase, punto de venta y número (por ejemplo, «Factura A 0003-00012345»).';
grant execute on function purchasing.invoice_label(purchasing.invoice_class, integer, bigint) to authenticated;

-- El precio esperado de un producto en una lista: neto (A) o final (las demás, a centavos), por envase o por kilo.
create function purchasing.expected_invoice_price(p_list_id uuid, p_product_id uuid, p_is_a boolean)
returns table (expected_price numeric, vat_rate numeric, list_price numeric, bonus1_pct numeric, bonus2_pct numeric,
               bonus_per_unit_amount numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_is_a then
                case when i.includes_vat then round(n.net / (1 + coalesce(i.vat_rate, 0) / 100), 4) else n.net end
              else
                round(case when i.includes_vat then n.net else n.net * (1 + coalesce(i.vat_rate, 0) / 100) end, 2)
         end,
         i.vat_rate, i.list_price, i.bonus1_pct, i.bonus2_pct, i.bonus_per_unit_amount
    from purchasing.price_list_items i
   cross join lateral (select purchasing.net_list_price(i.list_price, i.bonus1_pct, i.bonus2_pct,
                                                        i.bonus_per_unit_amount) as net) n
   where i.price_list_id = p_list_id and i.purchase_product_id = p_product_id and i.deleted_at is null
   order by i.line_order
   limit 1
$$;
comment on function purchasing.expected_invoice_price(uuid, uuid, boolean) is
  'Interna: el precio que tendría que tener un producto en una factura según la lista: el neto si es A; si no, el final (neto con IVA, a centavos). Por envase, o por kilo en lo que va por peso. Vacío si la lista no lo tiene.';
revoke execute on function purchasing.expected_invoice_price(uuid, uuid, boolean) from public;

-- Mensajes en español para las restricciones de facturas.
create function purchasing.raise_invoice_error(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'invoices_number_key' then 'Esa factura ya está cargada (mismo proveedor, clase, punto de venta y número).'
    when p_constraint = 'invoices_fiscal_check' then
      'Una factura fiscal lleva punto de venta, autorización (CAE, CAI o CAEA) y CUIT del emisor.'
    when p_constraint = 'invoices_non_fiscal_vat_check' then 'Un comprobante X o una nota a mano no llevan IVA.'
    when p_constraint = 'invoices_totals_check' then
      'Las partes no suman el total: neto + exento + IVA + internos + percepciones − bonificación + redondeo tiene que dar el total.'
    when p_constraint = 'invoices_point_of_sale_check' then 'El punto de venta va de 1 a 99999.'
    when p_constraint = 'invoices_number_check' then 'El número va de 1 a 99999999.'
    when p_constraint = 'invoices_authorization_code_check' then 'La autorización (CAE, CAI o CAEA) tiene 14 números.'
    when p_constraint in ('invoices_issuer_tax_id_check', 'invoices_receiver_tax_id_check') then
      'El CUIT tiene 11 números.'
    when p_constraint like 'invoices_%_amount_check' then 'Los importes no pueden ser negativos.'
    when p_constraint = 'invoice_lines_amount_check' then 'El importe de una línea tiene que ser cantidad × precio.'
    when p_constraint = 'invoice_lines_free_check' then
      'Una línea con 99 % o más de bonificación es un regalo, y un regalo lleva esa bonificación.'
    when p_constraint = 'invoice_lines_target_check' then
      'Solo una línea de mercadería lleva producto de compra o línea de la OC.'
    when p_constraint = 'invoice_lines_billed_quantity_check' then 'La cantidad de cada línea tiene que ser mayor que cero.'
    when p_constraint = 'invoice_lines_vat_rate_check' then 'La alícuota de IVA es 0; 2,5; 5; 10,5; 21 o 27 %.'
    when p_constraint = 'invoice_lines_raw_name_check' then 'Escribí el nombre de cada línea (hasta 200 caracteres).'
    when p_constraint = 'invoice_lines_order_key' then 'Hay dos líneas con el mismo orden: recargá la página.'
    when p_constraint = 'invoice_lines_exempt_check' then 'Una línea exenta no lleva IVA.'
    when p_constraint = 'invoice_taxes_tax_amount_check' then 'El importe de cada percepción tiene que ser mayor que cero.'
    when p_constraint = 'credit_debit_notes_amounts_check' then 'El total de la nota no puede ser menor que su neto.'
    when p_constraint like 'credit_debit_notes_%' then 'Revisá la nota: fecha, importes mayores que cero y motivo.'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la factura.'
    when p_state in ('23514', '42501', '22023', 'P0001') then p_message
    else null
  end;
  if v_message is null then
    raise exception '%', p_message using errcode = p_state;
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function purchasing.raise_invoice_error(text, text, text) is
  'Interna: traduce a un mensaje en español el error de una restricción de facturas.';
revoke execute on function purchasing.raise_invoice_error(text, text, text) from public;

-- Los datos de la cabecera que se pueden escribir: se validan las claves y el CUIT se guarda sin guiones.
create function purchasing.apply_invoice_header(p_inv purchasing.invoices, p_header jsonb)
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
  if v_inv.due_on < v_inv.issued_on then
    raise exception 'El vencimiento no puede ser anterior a la fecha de la factura.' using errcode = '22023';
  end if;
  return v_inv;
end
$$;
comment on function purchasing.apply_invoice_header(purchasing.invoices, jsonb) is
  'Interna: aplica a una factura los datos de cabecera permitidos (CUIT sin guiones). El vencimiento escrito es el impreso; si no hay, sale de la condición de pago del proveedor (contado, el mismo día; cuenta corriente, la fecha + los días).';
revoke execute on function purchasing.apply_invoice_header(purchasing.invoices, jsonb) from public;

-- Reconocer un artículo de la factura o mandarlo a la cola de mapeo (reusa el pendiente que ya haya).
-- Devuelve (producto, artículo sin mapear, si es nuevo en la cola).
create function purchasing.match_invoice_article(p_inv purchasing.invoices, p_sku text, p_name text)
returns table (purchase_product_id uuid, unmapped_article_id uuid, is_new boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product  uuid;
  v_unmapped uuid;
begin
  v_product := purchasing.match_article(p_inv.supplier_id, p_sku, p_name);
  if v_product is not null then
    return query select v_product, null::uuid, false;
    return;
  end if;
  select u.id into v_unmapped from purchasing.unmapped_articles u
   where u.supplier_id = p_inv.supplier_id and u.normalized_name = purchasing.normalize_name(p_name)
     and u.status in ('pending', 'discarded') and u.deleted_at is null
   order by u.status = 'pending' desc, u.resolved_at desc nulls first
   limit 1;
  if v_unmapped is not null then
    return query select null::uuid, v_unmapped, false;
    return;
  end if;
  insert into purchasing.unmapped_articles (group_id, supplier_id, raw_name, supplier_sku, found_in, source_id)
  values (p_inv.group_id, p_inv.supplier_id, btrim(p_name), nullif(btrim(p_sku), ''), 'invoice', p_inv.id)
  returning id into v_unmapped;
  return query select null::uuid, v_unmapped, true;
end
$$;
comment on function purchasing.match_invoice_article(purchasing.invoices, text, text) is
  'Interna: reconoce un artículo de factura (por código del proveedor o por nombre) o lo manda a la cola de mapeo con origen «invoice» (reusa el pendiente que ya haya).';
revoke execute on function purchasing.match_invoice_article(purchasing.invoices, text, text) from public;

-- Aviso al chef: artículos nuevos de una factura para mapear.
create function purchasing.notify_unmapped_invoice(p_inv purchasing.invoices, p_count integer)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  select u, p_inv.group_id, 'unmapped_article',
         left(case when p_count = 1
                   then format('Un artículo nuevo de «%s» para mapear', coalesce(s.trade_name, s.name))
                   else format('%s artículos nuevos de «%s» para mapear', p_count, coalesce(s.trade_name, s.name)) end, 200),
         left(format('Llegaron en la %s. Decí qué materia prima es cada uno para que la factura se pueda controlar.',
                     purchasing.invoice_label(p_inv.invoice_class, p_inv.point_of_sale, p_inv.number)), 500),
         '/materias-primas/sin-mapear'
    from catalog.suppliers s
   cross join purchasing.users_who_map(p_inv.group_id) u
   where s.id = p_inv.supplier_id and p_count > 0
$$;
comment on function purchasing.notify_unmapped_invoice(purchasing.invoices, integer) is
  'Interna: avisa a quienes mapean artículos que una factura trajo artículos nuevos para la cola de mapeo.';
revoke execute on function purchasing.notify_unmapped_invoice(purchasing.invoices, integer) from public;

-- Las líneas: se reemplazan enteras (las de antes quedan dadas de baja). Devuelve cuántos artículos nuevos fueron a la
-- cola de mapeo. Cada línea:
--   {line_class, purchase_product_id, purchase_order_line_id, raw_name, supplier_sku, units, billed_quantity,
--    list_price, bonus1_pct, bonus2_pct, bonus_per_unit_amount, unit_price, vat_rate, is_exempt, internal_tax_amount,
--    line_amount}
create function purchasing.write_invoice_lines(p_inv purchasing.invoices, p_lines jsonb)
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

-- Las percepciones y otros tributos: se reemplazan enteros. Cada uno: {tax_kind, jurisdiction, regime, rate_pct, tax_amount}.
create function purchasing.write_invoice_taxes(p_inv purchasing.invoices, p_taxes jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tax jsonb;
begin
  if p_taxes is null or jsonb_typeof(p_taxes) <> 'array' then
    raise exception 'Faltan las percepciones de la factura (una lista, aunque esté vacía).' using errcode = '22023';
  end if;
  update purchasing.invoice_taxes set deleted_at = now() where invoice_id = p_inv.id and deleted_at is null;
  for v_tax in select value from jsonb_array_elements(p_taxes) loop
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

-- ---------------------------------------------------------------------------
-- 2. Cargar y corregir
-- ---------------------------------------------------------------------------
-- «+ Nueva factura»: proveedor, local y las OC recibidas que cubre (puede no tener: un flete o un servicio, P4). Las
-- líneas salen de lo recibido de esas OC, con el precio de la lista vigente a la fecha; Compras las ajusta al papel.
create function purchasing.create_invoice(p_supplier_id uuid, p_restaurant_id uuid, p_order_ids uuid[], p_header jsonb,
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
  select * into v_s from catalog.suppliers where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null;
  if v_s.id is null then
    raise exception 'Elegí un proveedor de este grupo.' using errcode = '22023';
  end if;
  foreach v_order_id in array coalesce(p_order_ids, '{}') loop
    if not exists (select 1 from purchasing.purchase_orders o
                    where o.id = v_order_id and o.deleted_at is null and o.supplier_id = v_s.id
                      and o.restaurant_id = v_r.id and o.status in ('received', 'partially_received', 'closed')) then
      raise exception 'Cada orden tiene que ser de este proveedor y este local, y estar recibida.' using errcode = '22023';
    end if;
  end loop;
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
  v_inv := purchasing.apply_invoice_header(v_inv, p_header);
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
                        else l.received_quantity end as billed
              from purchasing.purchase_order_lines l
              join purchasing.purchase_orders o on o.id = l.purchase_order_id
              join catalog.purchase_products p on p.id = l.purchase_product_id
             where l.purchase_order_id = any (coalesce(p_order_ids, '{}')) and l.deleted_at is null
               and l.received_quantity > 0) x
      left join lateral purchasing.expected_invoice_price(v_list, x.product_id,
                                                          purchasing.invoice_is_a(v_inv.invoice_class)) e on true;
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

-- Guardar los cambios de una factura cargada u observada, en lote: la cabecera, y si vienen, las líneas y las
-- percepciones (cada una se reemplaza entera). Vuelve a «cargada»: hay que controlarla de nuevo.
create function purchasing.save_invoice(p_id uuid, p_header jsonb, p_lines jsonb, p_taxes jsonb, p_reason text)
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
           observed_reason = null
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

-- Registrar la foto (o el PDF) ya subido de una factura o de una nota, con su página. Rehacer suma otra: vale la última.
create function purchasing.add_invoice_attachment(p_source_table text, p_source_id uuid, p_storage_path text,
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
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;
comment on function purchasing.add_invoice_attachment(text, uuid, text, smallint) is
  'Registra la foto o el PDF ya subido de una factura cargada u observada (invoice_original) o de una nota (credit_note), con su página. Rehacer suma otro; vale el último. Pide purchasing.manage_invoices en el local.';
revoke execute on function purchasing.add_invoice_attachment(text, uuid, text, smallint) from public;
grant execute on function purchasing.add_invoice_attachment(text, uuid, text, smallint) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Conforme: el costo sale de la factura
-- ---------------------------------------------------------------------------
-- Registra un precio por cada línea de mercadería (no los regalos), avisa a Dirección si alguno varió más que el % del
-- grupo, deja la factura conforme y liberada, y cierra las OC recibidas que cubre. Una sola vez por factura.
-- p_run_id: la corrida del control que la dejó conforme (si una nota cubrió la diferencia de precio, el costo es el de
-- la lista). Vacía en el conforme a mano: el costo es el de la factura.
create function purchasing.release_invoice(p_id uuid, p_approver uuid, p_run_id uuid)
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
begin
  select * into v_inv from purchasing.invoices where id = p_id for update;
  if v_inv.status not in ('loaded', 'observed') then
    raise exception 'Esta factura ya no está para dar por conforme.' using errcode = '23514';
  end if;
  v_label := purchasing.invoice_label(v_inv.invoice_class, v_inv.point_of_sale, v_inv.number);
  select coalesce(trade_name, name) into v_supplier from catalog.suppliers where id = v_inv.supplier_id;
  select coalesce((select approval_variation_pct from costing.price_settings
                    where group_id = v_inv.group_id and deleted_at is null), 15) into v_threshold;

  for v_line in
    select l.*, p.ingredient_id, p.billed_by_weight, p.units_per_package, p.content_per_unit, p.content_unit_id,
           -- Si el precio de la línea no pasó y una nota cubrió la diferencia, el costo es el de la lista.
           (select c.expected_amount from purchasing.invoice_checks c
             where c.invoice_line_id = l.id and c.check_kind = 'price' and not c.passed
               and c.run_id = p_run_id
               and exists (select 1 from purchasing.invoice_checks n
                            where n.run_id = c.run_id and n.check_kind = 'notes' and n.passed)
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
            v_inv.issued_on, v_package,
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

  update purchasing.invoices
     set status = 'approved', approved_by = p_approver, approved_at = now(), observed_reason = null
   where id = v_inv.id;
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

-- ---------------------------------------------------------------------------
-- 4. El control de 3 vías
-- ---------------------------------------------------------------------------
-- Corre todos los controles, guarda una fila por control (y por línea) con su explicación, y deja la factura conforme y
-- liberada (si todo pasa, o si las notas cubren la diferencia) u observada. Devuelve el estado.
create function purchasing.check_invoice(p_id uuid)
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

  for v_line in
    select l.*, p.billed_by_weight, pol.received_quantity as pol_received
      from purchasing.invoice_lines l
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join purchasing.purchase_order_lines pol on pol.id = l.purchase_order_line_id
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
      v_received := v_line.pol_received;
      v_kg := null;
      if v_line.billed_by_weight then
        select nullif(sum(rl.received_weight), 0) into v_kg
          from purchasing.receipt_lines rl
          join purchasing.receipts rc on rc.id = rl.receipt_id
         where rl.purchase_order_line_id = v_line.purchase_order_line_id and rl.deleted_at is null
           and rc.status = 'closed' and rc.deleted_at is null;
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
      into v_notes from purchasing.credit_debit_notes n where n.invoice_id = v_inv.id and n.deleted_at is null;
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

-- «Controlar».
create function purchasing.run_invoice_checks(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv    purchasing.invoices;
  v_status purchasing.invoice_status;
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.run_invoice_checks', 'No tenés permiso para controlar esta factura.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  perform core.set_change_context(format('Control de la %s',
                                         purchasing.invoice_label(v_inv.invoice_class, v_inv.point_of_sale, v_inv.number)),
                                  'manual');
  v_status := purchasing.check_invoice(v_inv.id);
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id, 'status', v_status);
end
$$;
comment on function purchasing.run_invoice_checks(uuid) is
  '«Controlar»: corre el control de 3 vías de una factura cargada u observada. Si todo pasa, queda conforme y liberada y su precio pasa a ser el costo; si no, observada. Pide purchasing.manage_invoices en el local.';
revoke execute on function purchasing.run_invoice_checks(uuid) from public;
grant execute on function purchasing.run_invoice_checks(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Notas, conforme a mano y cancelar
-- ---------------------------------------------------------------------------
-- Una nota de crédito, débito o descuento: {note_kind, number, issued_on, net_amount, total_amount}. Si la factura está
-- cargada u observada, se vuelve a controlar.
create function purchasing.add_credit_debit_note(p_invoice_id uuid, p_note jsonb, p_reason text)
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
  v_status := v_inv.status;
  if v_inv.status in ('loaded', 'observed') then
    v_status := purchasing.check_invoice(v_inv.id);
  end if;
  return jsonb_build_object('result', 'applied', 'note_id', v_id, 'status', v_status);
end
$$;
comment on function purchasing.add_credit_debit_note(uuid, jsonb, text) is
  'Suma una nota de crédito, débito o descuento a una factura y, si está cargada u observada, la vuelve a controlar: si la nota cubre la diferencia, queda conforme. Pide purchasing.manage_invoices en el local y el motivo.';
revoke execute on function purchasing.add_credit_debit_note(uuid, jsonb, text) from public;
grant execute on function purchasing.add_credit_debit_note(uuid, jsonb, text) to authenticated;

-- «Dar por conforme» a mano una factura observada (decisión 2 de Soy): otra persona, distinta de quien la cargó, con
-- purchasing.approve_invoices y un motivo. La base lo valida.
create function purchasing.approve_invoice(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv    purchasing.invoices;
  v_reason text := nullif(btrim(p_reason), '');
  v_name   text;
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.approve_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.approve_invoice', 'No tenés permiso para dar por conforme esta factura.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_inv.loaded_by = core.current_actor_id() then
    return core.deny('purchasing.approve_invoice',
                     'No podés dar por conforme una factura que cargaste vos: la tiene que dar otra persona.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí por qué la das por conforme.' using errcode = '22023';
  end if;
  if v_inv.status <> 'observed' then
    raise exception 'Solo se da por conforme a mano una factura observada: controlala primero.' using errcode = '23514';
  end if;
  select l.raw_name into v_name from purchasing.invoice_lines l
   where l.invoice_id = v_inv.id and l.deleted_at is null and l.line_class in ('product', 'free_of_charge')
     and l.purchase_product_id is null
   order by l.line_order limit 1;
  if v_name is not null then
    raise exception 'Primero hay que mapear «%»: sin su materia prima no hay costo.', v_name using errcode = '23514';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  perform purchasing.release_invoice(v_inv.id, core.current_actor_id(), null);
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id, 'status', 'released');
end
$$;
comment on function purchasing.approve_invoice(uuid, text) is
  '«Dar por conforme» a mano una factura observada: pide purchasing.approve_invoices en el local, que no la haya cargado la misma persona (decisión 2 de Soy) y un motivo. Deja la factura conforme y liberada, y su precio pasa a ser el costo.';
revoke execute on function purchasing.approve_invoice(uuid, text) from public;
grant execute on function purchasing.approve_invoice(uuid, text) to authenticated;

-- Cancelar una factura cargada por error (cargada u observada), con motivo. No se borra.
create function purchasing.cancel_invoice(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv    purchasing.invoices;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.cancel_invoice', 'No tenés permiso para cancelar esta factura.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí por qué se cancela.' using errcode = '22023';
  end if;
  select * into v_inv from purchasing.invoices where id = p_id for update;
  if v_inv.status not in ('loaded', 'observed') then
    raise exception 'Una factura conforme no se cancela: se corrige con una nota de crédito.' using errcode = '23514';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  update purchasing.invoices set status = 'cancelled', cancelled_reason = left(v_reason, 500) where id = v_inv.id;
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id, 'status', 'cancelled');
end
$$;
comment on function purchasing.cancel_invoice(uuid, text) is
  'Cancela una factura cargada u observada que se cargó por error, con motivo. Queda en la historia; el mismo número se puede volver a cargar. Pide purchasing.manage_invoices en el local.';
revoke execute on function purchasing.cancel_invoice(uuid, text) from public;
grant execute on function purchasing.cancel_invoice(uuid, text) to authenticated;
