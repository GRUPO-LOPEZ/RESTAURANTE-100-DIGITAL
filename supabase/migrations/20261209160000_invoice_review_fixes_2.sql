-- Fase 3, Prompt 5 (ADR-0058): segunda pasada de la revisión de base y de seguridad.
--
-- - N1: una factura anterior al costo vigente del local no registra precio. Queda en la historia de compras, pero no
--   pisa el costo de una compra más nueva ni reescribe costos pasados (costo vigente = última compra conforme).
-- - N2: dos líneas de una factura no pueden ir contra la misma línea de la OC (índice único); lo que el chef mapea
--   después se asocia de a una línea.
-- - M4: si la factura queda cubierta por notas, no la deja conforme sola quien la cargó, la corrigió o le sumó notas.
--   Las notas de crédito y los descuentos no superan el total de la factura.
-- - Quien cambia la foto de la factura queda anotado en edited_by.

create unique index invoice_lines_po_line_key on purchasing.invoice_lines (invoice_id, purchase_order_line_id)
  where deleted_at is null and purchase_order_line_id is not null;

-- El control (N2, M4 y la explicación de lo ya facturado).
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
  v_map        record;
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
  -- Y a la línea de la OC con ese producto que todavía no tenga (como al guardar), de a una línea.
  for v_map in
    select l.id, l.purchase_product_id from purchasing.invoice_lines l
     where l.invoice_id = v_inv.id and l.deleted_at is null and l.line_class = 'product'
       and l.purchase_product_id is not null and l.purchase_order_line_id is null
     order by l.line_order
  loop
    update purchasing.invoice_lines
       set purchase_order_line_id = (
             select pol.id from purchasing.purchase_order_lines pol
               join purchasing.invoice_orders io on io.purchase_order_id = pol.purchase_order_id
              where io.invoice_id = v_inv.id and io.deleted_at is null and pol.deleted_at is null
                and pol.purchase_product_id = v_map.purchase_product_id
                and not exists (select 1 from purchasing.invoice_lines x
                                 where x.invoice_id = v_inv.id and x.deleted_at is null and x.purchase_order_line_id = pol.id)
              order by pol.line_order limit 1)
     where id = v_map.id;
  end loop;

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
                  case when v_line.other_units > 0
                       then format('Facturaron %s; se recibieron %s y ya hay %s en otras facturas de esta OC.',
                                   round(v_compare, 3), round(v_line.pol_received, 3), round(v_line.other_units, 3))
                       else format('Facturaron %s y se recibieron %s.', round(v_compare, 3), round(v_received, 3)) end);
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
      -- Cubierta por notas: no la deja conforme sola quien la cargó, la corrigió o le sumó notas (revisión de seguridad).
      if core.current_actor_id() = v_inv.loaded_by or core.current_actor_id() = any (v_inv.edited_by) then
        v_hard := v_hard + 1;
        v_reasons := v_reasons || 'las notas las sumó o la factura la corrigió quien controla'::text;
        insert into purchasing.invoice_checks (group_id, invoice_id, run_id, check_kind, passed, explanation)
        values (v_inv.group_id, v_inv.id, v_run, 'notes', false,
                'Las notas cubren la diferencia, pero la factura la cargó, corrigió o le sumó notas quien controla: la da por conforme otra persona.');
      end if;
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


-- Una factura anterior al costo vigente del local no registra precio (N1).
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
    -- Anterior al último precio del producto en el local o al que vale hoy ahí: no lo pisa ni reescribe la historia.
    -- La factura queda conforme igual (cuenta para el pago); el costo vigente es el de la compra más nueva.
    if v_inv.issued_on < coalesce(costing.valid_from_floor(v_line.purchase_product_id, 'restaurant', null,
                                                           v_inv.restaurant_id), v_inv.issued_on) then
      continue;
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

-- Las notas de crédito y los descuentos no superan el total de la factura (M4).
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
    if p_note ->> 'note_kind' in ('credit', 'discount')
       and coalesce((select sum(n.net_amount) from purchasing.credit_debit_notes n
                      where n.invoice_id = v_inv.id and n.deleted_at is null and n.note_kind in ('credit', 'discount')), 0)
           + coalesce(nullif(p_note ->> 'net_amount', '')::numeric, 0) > v_inv.total_amount then
      raise exception 'Las notas de crédito y los descuentos no pueden superar el total de la factura.' using errcode = '22023';
    end if;
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

comment on function purchasing.add_credit_debit_note(uuid, jsonb, text) is
  'Suma una nota de crédito, débito o descuento a una factura (las de crédito y los descuentos, hasta su total). Cuenta para el control recién con su foto: al registrarla, se vuelve a controlar. Quien la suma queda anotado y no da la factura por conforme. Pide purchasing.manage_invoices en el local y el motivo.';

-- Quien cambia la foto de la factura queda anotado en edited_by.
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
  if v_kind = 'invoice_original' then
    update purchasing.invoices i
       set edited_by = case when core.current_actor_id() = any (i.edited_by) then i.edited_by
                            else i.edited_by || core.current_actor_id() end
     where i.id = v_inv.id;
  end if;
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
