-- Facturas con control de 3 vías y costos desde la factura conforme (Fase 3, Prompt 5, ADR-0058).
-- Casos 19 a 30 del plan (docs/fases/fase-3-plan.md, §6), con la cuenta hecha.
-- Personas del seed: Dirección 402, Gerente 404 (Pastas Centro), Controller 407, Compras 408, Cocinera 409, Auditor 410.
-- Locales: Parrilla Centro 203 y Pastas Norte 202 (razón social RI 30000000007). Proveedores: Lácteos 903 (lista 1303
-- aceptada, vigente desde hace 3 días) y Almacén 904 (sin lista aceptada).
-- Se arma un producto propio para que la cuenta sea exacta: «Azúcar de prueba, bolsa de 50 kg» (materia prima 827,
-- unidad de uso g) con $ 50.000 neto en la lista, y un corte por kilo (materia prima 811, en g) a $ 8.000 el kg.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(98);

create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.q1(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
grant execute on function pg_temp.u(int) to authenticated;
create table pg_temp.k (name text primary key, id uuid not null);
create function pg_temp.k(p_name text) returns uuid language sql security definer as $$
  select id from pg_temp.k where name = p_name
$$;
grant execute on function pg_temp.k(text) to authenticated;
-- Una foto «subida» a la carpeta de la recepción o de la factura por esa persona y registrada con su sesión.
create function pg_temp.receipt_photo(p_receipt uuid, p_kind text) returns void language plpgsql as $$
declare
  v_path text := format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', p_receipt, gen_random_uuid());
begin
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, pg_temp.u(408)::text, '{"mimetype": "image/jpeg", "size": 120000}');
  perform pg_temp.q(pg_temp.u(408), format('select purchasing.add_receipt_attachment(%L, %L, %L, 1::smallint)::text',
                                           p_receipt, v_path, p_kind));
end
$$;
create function pg_temp.invoice_photo(p_invoice uuid) returns text language plpgsql as $$
declare
  v_path text := format('00000000-0000-4000-8000-000000000001/invoices/%s/%s.pdf', p_invoice, gen_random_uuid());
begin
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, pg_temp.u(408)::text, '{"mimetype": "application/pdf", "size": 900000}');
  return pg_temp.q(pg_temp.u(408), format('select purchasing.add_invoice_attachment(%L, %L, %L, 1::smallint) ->> %L',
                                          'invoices', p_invoice, v_path, 'result'));
end
$$;
create function pg_temp.note_photo(p_note uuid) returns text language plpgsql as $$
declare
  v_path text := format('00000000-0000-4000-8000-000000000001/credit_debit_notes/%s/%s.jpg', p_note, gen_random_uuid());
begin
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, pg_temp.u(408)::text, '{"mimetype": "image/jpeg", "size": 120000}');
  return pg_temp.q(pg_temp.u(408), format('select purchasing.add_invoice_attachment(%L, %L, %L, 1::smallint) ->> %L',
                                          'credit_debit_notes', p_note, v_path, 'status'));
end
$$;
create function pg_temp.note_photo_by(p_note uuid, p_user int) returns text language plpgsql as $$
declare
  v_path text := format('00000000-0000-4000-8000-000000000001/credit_debit_notes/%s/%s.jpg', p_note, gen_random_uuid());
begin
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, pg_temp.u(p_user)::text, '{"mimetype": "image/jpeg", "size": 120000}');
  return pg_temp.q(pg_temp.u(p_user), format('select purchasing.add_invoice_attachment(%L, %L, %L, 1::smallint) ->> %L',
                                             'credit_debit_notes', p_note, v_path, 'status'));
end
$$;
-- El pie que cierra con las líneas y las percepciones (en A, IVA por línea).
create function pg_temp.footer(p_invoice uuid) returns jsonb language sql security definer as $$
  select jsonb_build_object(
           'net_amount', x.net, 'vat_amount', x.vat, 'internal_tax_amount', x.internal,
           'perception_amount', x.perception, 'total_amount', x.net + x.vat + x.internal + x.perception)
    from (select coalesce(sum(l.line_amount), 0) as net,
                 case when purchasing.invoice_is_a(i.invoice_class)
                      then coalesce(sum(round(l.line_amount * coalesce(l.vat_rate, 0) / 100, 2)), 0) else 0 end as vat,
                 coalesce(sum(l.internal_tax_amount), 0) as internal,
                 coalesce((select sum(t.tax_amount) from purchasing.invoice_taxes t
                            where t.invoice_id = i.id and t.deleted_at is null), 0) as perception
            from purchasing.invoices i
            left join purchasing.invoice_lines l on l.invoice_id = i.id and l.deleted_at is null
           where i.id = p_invoice
           group by i.id, i.invoice_class) x
$$;
grant execute on function pg_temp.footer(uuid) to authenticated;
-- Las líneas de una factura, para cambiarlas y volver a guardarlas.
create function pg_temp.lines(p_invoice uuid) returns jsonb language sql security definer as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'line_class', l.line_class, 'purchase_product_id', l.purchase_product_id,
           'purchase_order_line_id', l.purchase_order_line_id, 'raw_name', l.raw_name, 'units', l.units,
           'billed_quantity', l.billed_quantity, 'list_price', l.list_price, 'bonus1_pct', l.bonus1_pct,
           'bonus2_pct', l.bonus2_pct, 'unit_price', l.unit_price, 'vat_rate', l.vat_rate,
           'internal_tax_amount', l.internal_tax_amount, 'line_amount', l.line_amount)) order by l.line_order), '[]')
    from purchasing.invoice_lines l where l.invoice_id = p_invoice and l.deleted_at is null
$$;
grant execute on function pg_temp.lines(uuid) to authenticated;
create function pg_temp.status(p_invoice uuid) returns text language sql security definer as $$
  select status::text from purchasing.invoices where id = p_invoice
$$;
-- El último resultado de un control de una línea (o de la factura).
create function pg_temp.check_passed(p_invoice uuid, p_kind text, p_line_name text default null)
returns boolean language sql security definer as $$
  select c.passed from purchasing.invoice_checks c
    left join purchasing.invoice_lines l on l.id = c.invoice_line_id
   where c.invoice_id = p_invoice and c.check_kind::text = p_kind
     and (p_line_name is null or l.raw_name = p_line_name)
     and c.run_id = (select run_id from purchasing.invoice_checks where invoice_id = p_invoice
                      order by entry_number desc limit 1)
   order by c.entry_number desc limit 1
$$;
create function pg_temp.header(p_class text, p_number int, p_receiver text default '30000000007') returns jsonb
language sql as $$
  select jsonb_build_object('invoice_class', p_class, 'point_of_sale', 3, 'number', p_number,
                            'authorization_kind', 'cae', 'authorization_code', '71000000000001',
                            'issuer_tax_id', '30-50000003-8', 'receiver_tax_id', p_receiver,
                            'issued_on', recipes.today() - 1)
$$;
grant execute on function pg_temp.header(text, int, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Preparación: productos propios, su lista y una OC recibida en Parrilla Centro
-- ---------------------------------------------------------------------------
insert into catalog.purchase_products (id, group_id, code, ingredient_id, supplier_id, description, package_unit_id,
                                       units_per_package, content_per_unit, content_unit_id, supplier_sku)
select v.id, pg_temp.u(1), v.code, v.ingredient, pg_temp.u(903), v.description, pu.id, 1, v.content, g.id, v.sku
  from (values (pg_temp.u(3801), 'TEST-FACT-50', 'Azúcar de prueba, bolsa de 50 kg', 'bag', 50000, 'LAT-50',
                pg_temp.u(827)),
               (pg_temp.u(3802), 'TEST-FACT-KG', 'Corte de prueba, por kg', 'kg', 1000, 'LAT-KG', pg_temp.u(811)))
         as v (id, code, description, package, content, sku, ingredient)
  join catalog.units pu on pu.code = v.package
  join catalog.units g on g.code = 'g';
update catalog.purchase_products set billed_by_weight = true, estimated_weight_per_unit = 4000
 where id = pg_temp.u(3802);
insert into purchasing.price_list_items (group_id, price_list_id, line_order, purchase_product_id, raw_name,
                                         supplier_sku, list_price, vat_rate)
values (pg_temp.u(1), pg_temp.u(1303), 901, pg_temp.u(3801), 'Azúcar de prueba x 50 kg', 'LAT-50', 50000, 21),
       (pg_temp.u(1), pg_temp.u(1303), 902, pg_temp.u(3802), 'Corte de prueba x kg', 'LAT-KG', 8000, 10.5);

-- Una OC de Lácteos en Parrilla Centro (2 bolsas y 8 piezas del corte), recibida entera con 32,80 kg del corte.
create function pg_temp.received_order() returns uuid language plpgsql as $f$
declare
  v_order   uuid;
  v_receipt uuid;
  v_result  text;
begin
  v_order := (pg_temp.q(pg_temp.u(408), format(
    'select purchasing.save_order_draft(null, %L, %L, %L::jsonb, null, null, %L) ->> %L', pg_temp.u(203), pg_temp.u(903),
    jsonb_build_array(jsonb_build_object('purchase_product_id', pg_temp.u(3801), 'quantity', 2),
                      jsonb_build_object('purchase_product_id', pg_temp.u(3802), 'quantity', 8)),
    'Pedido para probar facturas', 'purchase_order_id')))::uuid;
  perform pg_temp.q(pg_temp.u(408), format('select purchasing.submit_order(%L, %L)::text', v_order, 'Pedido'));
  v_receipt := (pg_temp.q(pg_temp.u(408), format('select purchasing.start_receipt(%L) ->> %L', v_order,
                                                 'receipt_id')))::uuid;
  perform pg_temp.receipt_photo(v_receipt, 'receipt_original');
  perform pg_temp.receipt_photo(v_receipt, 'receipt_signed');
  v_result := pg_temp.q(pg_temp.u(408), format(
    'select purchasing.close_receipt(%L, %L, null, %L::jsonb, null, null) ->> %L', v_receipt, 'invoice',
    (select jsonb_agg(case when l.purchase_product_id = pg_temp.u(3802)
                           then jsonb_build_object('purchase_order_line_id', l.id, 'ok', true, 'received_weight', 32.80)
                           else jsonb_build_object('purchase_order_line_id', l.id, 'ok', true) end order by l.line_order)
       from purchasing.purchase_order_lines l where l.purchase_order_id = v_order), 'result'));
  if v_result is distinct from 'applied' then
    raise exception 'preparación: la recepción dio %', v_result;
  end if;
  return v_order;
end
$f$;
insert into pg_temp.k select v.name, pg_temp.received_order() from (values ('oc'), ('oc2'), ('oc3'), ('oc4'), ('oc5'), ('oc6')) as v (name);
select is((select count(*)::int from purchasing.purchase_orders
            where id in (pg_temp.k('oc'), pg_temp.k('oc2'), pg_temp.k('oc3'), pg_temp.k('oc4')) and status = 'received'),
  4, 'preparación: cuatro OC llegan enteras (32,80 kg del corte)');

-- ---------------------------------------------------------------------------
-- Estructura y permisos
-- ---------------------------------------------------------------------------
select has_table('purchasing', 'invoices', 'existe purchasing.invoices');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'purchasing' and c.relrowsecurity
              and c.relname in ('invoices', 'invoice_orders', 'invoice_lines', 'invoice_taxes', 'invoice_checks',
                                'credit_debit_notes')),
          6, 'RLS activo en las seis tablas de facturas');
select is((select array_agg(r.code order by r.code) from core.role_permissions rp
             join core.roles r on r.id = rp.role_id join core.permissions p on p.id = rp.permission_id
            where p.code = 'purchasing.approve_invoices'),
          array['controller', 'purchasing', 'superadmin'], 'dan por conforme: Controller, Compras (y el superadmin, G2)');
select ok((select is_sensitive from core.permissions where code = 'purchasing.approve_invoices')
          and (select is_sensitive from core.permissions where code = 'purchasing.manage_invoices'),
          'cargar y dar por conforme son permisos sensibles');
select ok((select requires_mfa from core.roles where code = 'purchasing'),
          'Compras entra con doble verificación (carga facturas que escriben costos)');

-- ---------------------------------------------------------------------------
-- Casos 19, 21, 22, 23 y 25: A con RI, conforme sola
-- ---------------------------------------------------------------------------
insert into pg_temp.k values ('a1', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc'), pg_temp.header('invoice_a', 900001), 'Factura de prueba', 'invoice_id')))::uuid);
select is((select count(*)::int from purchasing.invoice_lines where invoice_id = pg_temp.k('a1') and deleted_at is null),
          2, 'las líneas salen de lo recibido');
select is((select unit_price from purchasing.invoice_lines
            where invoice_id = pg_temp.k('a1') and purchase_product_id = pg_temp.u(3801) and deleted_at is null),
          50000.0000::numeric, 'con el precio neto de la lista vigente a la fecha');
select is((select billed_quantity from purchasing.invoice_lines
            where invoice_id = pg_temp.k('a1') and purchase_product_id = pg_temp.u(3802) and deleted_at is null),
          32.800000::numeric, 'por peso, los kilos recibidos');
select is(pg_temp.status(pg_temp.k('a1')), 'loaded', 'queda cargada');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L)', pg_temp.k('a1'))),
          'Falta la foto de la factura.', 'sin la foto no se controla');
select is(pg_temp.invoice_photo(pg_temp.k('a1')), 'applied', 'Compras sube la foto (o el PDF) de la factura');

-- Como en el papel: 32,95 kg (+0,46 %), $ 2.000 de internos en el azúcar, un regalo, un flete y 3 % de IIBB.
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, %L::jsonb, %L)',
  pg_temp.k('a1'), '{}',
  (select jsonb_agg(case when x ->> 'purchase_product_id' = pg_temp.u(3802)::text
                         then x || '{"billed_quantity": 32.95, "line_amount": 263600}'::jsonb
                         else x || '{"internal_tax_amount": 2000}'::jsonb end)
     from jsonb_array_elements(pg_temp.lines(pg_temp.k('a1'))) x)
  || jsonb_build_array(
       jsonb_build_object('purchase_product_id', pg_temp.u(3801), 'raw_name', 'Azúcar de regalo', 'billed_quantity', 1,
                          'bonus1_pct', 100, 'unit_price', 0, 'vat_rate', 21, 'line_amount', 0,
                          'line_class', 'free_of_charge'),
       jsonb_build_object('line_class', 'freight', 'raw_name', 'Flete', 'billed_quantity', 1, 'unit_price', 3000,
                          'vat_rate', 21, 'line_amount', 3000)),
  '[{"tax_kind": "iibb", "jurisdiction": "CABA", "rate_pct": 3, "tax_amount": 10998}]', 'Como en el papel')),
  'sin error', 'Compras corrige las líneas como en el papel');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                             pg_temp.k('a1'), pg_temp.footer(pg_temp.k('a1')), 'El pie')),
          'sin error', 'y el pie');
select is(pg_temp.q1(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a1'),
                                             'result')),
          'denied', 'Compras sin doble verificación no controla');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a1'), 'status')),
          'observed', 'doble firma: quien aceptó la lista de Lácteos no la deja conforme sola');
select ok(exists (select 1 from purchasing.invoice_checks where invoice_id = pg_temp.k('a1') and not passed
                   and explanation like 'La lista de precios vigente la cargó o aceptó quien controla%'),
          'y lo dice en simple');
select is(pg_temp.q(pg_temp.u(401), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a1'), 'status')),
          'released', 'caso 19: controlada por otra persona, igual a lo recibido y a la lista → conforme y liberada');
select ok(pg_temp.check_passed(pg_temp.k('a1'), 'quantity', 'Corte de prueba, por kg'),
          'caso 25: 32,95 kg facturados contra 32,80 recibidos (+0,46 %) pasa');
select is((select net_package_price / base_quantity from costing.price_records
            where invoice_line_id = (select id from purchasing.invoice_lines where invoice_id = pg_temp.k('a1')
                                       and purchase_product_id = pg_temp.u(3801) and line_class = 'product'
                                       and deleted_at is null)),
          1.0000000000000000::numeric, 'caso 19: bolsa de 50 kg a $ 50.000 neto → $ 1.000 por kg ($ 1 por g)');
select is((select package_price from costing.price_records
            where invoice_line_id = (select id from purchasing.invoice_lines where invoice_id = pg_temp.k('a1')
                                       and purchase_product_id = pg_temp.u(3801) and line_class = 'product'
                                       and deleted_at is null)),
          50000.0000::numeric, 'caso 21: los $ 2.000 de internos no entran al costo');
select is((select (source::text, document_type::text, vat_rate, price_includes_vat, scope_type::text, restaurant_id,
                   valid_from, approved_by)::text
             from costing.price_records
            where invoice_line_id = (select id from purchasing.invoice_lines where invoice_id = pg_temp.k('a1')
                                       and purchase_product_id = pg_temp.u(3801) and line_class = 'product'
                                       and deleted_at is null)),
          (select ('invoice', 'invoice', 21.00, false, 'restaurant', pg_temp.u(203), recipes.today() - 1,
                   pg_temp.u(401))::text),
          'el precio entra con origen factura, en el local, desde la fecha de la factura, aprobado por quien controló');
select is((select net_package_price / base_quantity from costing.price_records
            where invoice_line_id = (select id from purchasing.invoice_lines where invoice_id = pg_temp.k('a1')
                                       and purchase_product_id = pg_temp.u(3802) and deleted_at is null)),
          8.0000000000000000::numeric, 'por peso: $ 8.000 el kg → $ 8 por g');
select is((select count(*)::int from costing.price_records r join purchasing.invoice_lines l on l.id = r.invoice_line_id
            where l.invoice_id = pg_temp.k('a1')),
          2, 'casos 22 y 23: el flete y el regalo no cambian ningún costo');
select is((select total_amount from purchasing.invoices where id = pg_temp.k('a1')),
          (100000 + 263600 + 3000 + 21000 + 27678 + 630 + 2000 + 10998)::numeric(18,4),
          'caso 22: el flete, los internos y la percepción suman al total');
select is((select status::text from purchasing.purchase_orders where id = pg_temp.k('oc')), 'closed',
          'la OC recibida queda cerrada (facturada)');
select ok(exists (select 1 from integration.integration_outbox o join costing.price_records r on r.id = o.aggregate_id
                   join purchasing.invoice_lines l on l.id = r.invoice_line_id
                  where o.event_type = 'price.approved' and l.invoice_id = pg_temp.k('a1')),
          'avisa a otros sistemas (price.approved)');
select ok(exists (select 1 from costing.cost_recalc_queue
                  where reason = 'price_change' and pg_temp.u(203) = any (restaurant_ids)),
          'y el precio nuevo anota el recálculo de las recetas del local (la cola, ADR-0032)');

-- Inmutable.
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                             pg_temp.k('a1'), '{"notes": "otra cosa"}', 'Cambio')),
          'Una factura conforme no cambia: corregila con una nota de crédito o débito.',
          'conforme, no se cambia desde la app');
select throws_ok(format('update purchasing.invoices set number = 900099 where id = %L', pg_temp.k('a1')), '42501',
                 'Una factura conforme no cambia: corregila con una nota de crédito o débito.',
                 'ni en la base');
select throws_ok(format('update purchasing.invoice_lines set unit_price = 1 where invoice_id = %L', pg_temp.k('a1')),
                 '42501', 'Una factura conforme no cambia: corregila con una nota de crédito o débito.',
                 'ni sus líneas');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.cancel_invoice(%L, %L)', pg_temp.k('a1'), 'Error')),
          'Una factura conforme no se cancela: se corrige con una nota de crédito.', 'ni se cancela');

-- ---------------------------------------------------------------------------
-- Casos 24 y 26: precio distinto, y la nota de crédito que lo cierra
-- ---------------------------------------------------------------------------
insert into pg_temp.k values ('a2', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc2'), pg_temp.header('invoice_a', 900002), 'Factura de prueba', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('a2'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L)',
  pg_temp.k('a2'), '{}',
  (select jsonb_agg(case when x ->> 'purchase_product_id' = pg_temp.u(3801)::text
                         then x || '{"unit_price": 50001, "line_amount": 100002}'::jsonb else x end)
     from jsonb_array_elements(pg_temp.lines(pg_temp.k('a2'))) x), 'Como en el papel'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a2'), pg_temp.footer(pg_temp.k('a2')), 'El pie'));
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a2'), 'status')),
          'observed', 'caso 24: lista $ 50.000, factura $ 50.001 → observada (tolerancia 0)');
select ok(not pg_temp.check_passed(pg_temp.k('a2'), 'price', 'Azúcar de prueba, bolsa de 50 kg'),
          'por el precio de esa línea');
select alike((select explanation from purchasing.invoice_checks
              where invoice_id = pg_temp.k('a2') and check_kind = 'price' and not passed
                and invoice_line_id is not null limit 1),
            'La lista dice $ 50.000,00 y la factura $ 50.001,00 (sin IVA).', 'con la explicación en simple');
select ok(exists (select 1 from core.notifications where kind = 'invoice_observed'
                   and link = format('/compras/facturas/%s', pg_temp.k('a2'))),
          'y avisa a Compras');
select is((select count(*)::int from costing.price_records r join purchasing.invoice_lines l on l.id = r.invoice_line_id
            where l.invoice_id = pg_temp.k('a2')),
          0, 'observada, no cambia costos');
insert into pg_temp.k values ('nc', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.add_credit_debit_note(%L, %L::jsonb, %L) ->> %L', pg_temp.k('a2'),
  jsonb_build_object('note_kind', 'credit', 'number', 'NC 0003-00000001', 'issued_on', recipes.today(),
                     'net_amount', 2, 'total_amount', 2.42), 'El proveedor reconoce el precio', 'note_id')))::uuid);
select is(pg_temp.q(pg_temp.u(401), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a2'), 'status')),
          'observed', 'una nota sin su foto no cubre la diferencia');
select is(pg_temp.note_photo(pg_temp.k('nc')), 'observed',
          'con la foto se vuelve a controlar (y quien aceptó la lista no la deja conforme sola)');
select is(pg_temp.q(pg_temp.u(401), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a2'), 'status')),
          'released', 'caso 26: la nota de crédito por los $ 2, con su foto, cubre la diferencia y queda conforme');
select is((select package_price from costing.price_records r join purchasing.invoice_lines l on l.id = r.invoice_line_id
            where l.invoice_id = pg_temp.k('a2') and l.purchase_product_id = pg_temp.u(3801)),
          50000.0000::numeric, 'el costo es el de la lista (la nota cubrió la diferencia)');

-- ---------------------------------------------------------------------------
-- Casos 27 y 28: conforme a mano, y una variación grande
-- ---------------------------------------------------------------------------
insert into pg_temp.k values ('a3', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc3'), pg_temp.header('invoice_a', 900003), 'Factura de prueba', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('a3'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L)',
  pg_temp.k('a3'), '{}',
  (select jsonb_agg(case when x ->> 'purchase_product_id' = pg_temp.u(3801)::text
                         then x || '{"unit_price": 60000, "line_amount": 120000}'::jsonb else x end)
     from jsonb_array_elements(pg_temp.lines(pg_temp.k('a3'))) x), 'Como en el papel'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a3'), pg_temp.footer(pg_temp.k('a3')), 'El pie'));
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a3'), 'status')),
          'observed', 'una factura $ 60.000 contra la lista de $ 50.000 queda observada');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('a3'),
                                           'El proveedor subió el precio', 'result')),
          'denied', 'caso 27: quien la cargó no la da por conforme');
select is(pg_temp.msg(pg_temp.u(401), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                             pg_temp.k('a3'), '{"notes": "Revisada por otra persona"}', 'Nota')),
          'sin error', 'otra persona de Compras la corrige');
select pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a3'), 'status'));
select is(pg_temp.q(pg_temp.u(401), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('a3'),
                                           'La corregí yo', 'result')),
          'denied', 'quien la corrigió tampoco la da por conforme');
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L, %L) ->> %L', pg_temp.k('a3'),
                                           'Revisada', '2000-01-01 00:00:00+00', 'result')),
          'ERROR 40001', 'si cambió desde que la miró, no se aprueba');
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('a3'),
                                           '', 'result')),
          'ERROR 22023', 'el Controller, con motivo');
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('a3'),
                                           'El proveedor avisó el aumento', 'status')),
          'released', 'caso 27: el Controller (otra persona) la da por conforme');
select is((select (approved_by, package_price)::text from costing.price_records r
             join purchasing.invoice_lines l on l.id = r.invoice_line_id
            where l.invoice_id = pg_temp.k('a3') and l.purchase_product_id = pg_temp.u(3801)),
          (select (pg_temp.u(407), 60000.0000::numeric(18,4))::text), 'su precio entra, aprobado por el Controller');
select ok(exists (select 1 from core.notifications
                   where kind = 'price_variation' and recipient_user_id = pg_temp.u(402)
                     and link = format('/compras/facturas/%s', pg_temp.k('a3')) and body like 'Antes $ 50.000,00 el envase; ahora $ 60.000,00 (20 %)%'),
          'caso 28: +20 % > 15 % → el precio entra igual y Dirección recibe el aviso con antes y ahora');
select ok(not exists (select 1 from workflow.approval_requests r
                       where r.created_at >= (select created_at from purchasing.invoices where id = pg_temp.k('a3'))
                         and r.workflow_id in (select id from workflow.approval_workflows
                                                where code like 'costing.approve_price%')),
          'y no se crea una solicitud de aprobación de precio');

-- ---------------------------------------------------------------------------
-- Caso 20 y P4: B sin OC, a mano por otra persona
-- ---------------------------------------------------------------------------
insert into pg_temp.k values ('b1', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(202),
  pg_temp.header('invoice_b', 900004), 'Factura B sin OC', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('b1'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, %L::jsonb, %L)',
  pg_temp.k('b1'), '{}',
  jsonb_build_array(jsonb_build_object('purchase_product_id', pg_temp.u(3801), 'raw_name', 'Azúcar x 50',
                                       'billed_quantity', 1, 'unit_price', 60500, 'vat_rate', 21, 'line_amount', 60500)),
  '[]', 'Como en el papel'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('b1'), pg_temp.footer(pg_temp.k('b1')), 'El pie'));
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('b1'), 'status')),
          'observed', 'P4: sin OC ni recepción no queda conforme sola');
select ok(pg_temp.check_passed(pg_temp.k('b1'), 'price', 'Azúcar x 50'), 'en B se compara el precio final ($ 50.000 + 21 % = $ 60.500)');
select ok(not pg_temp.check_passed(pg_temp.k('b1'), 'order'), 'falla el control de OC');
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('b1'),
                                           'Servicio sin OC, revisado', 'status')),
          'released', 'la da por conforme el Controller');
select is((select gross_package_price / base_quantity from costing.price_records r
             join purchasing.invoice_lines l on l.id = r.invoice_line_id where l.invoice_id = pg_temp.k('b1')),
          1.2100000000000000::numeric, 'caso 20: la misma bolsa en B → $ 1.210 por kg (sin IVA recuperable)');
select is((select unit_cost from costing.price_rows(pg_temp.u(202), recipes.today(), pg_temp.u(827))),
          1.21000000::numeric, 'y es el costo de Pastas Norte, aunque la razón social sea RI');

-- ---------------------------------------------------------------------------
-- Casos 29 y 30, única, mapeo, lista y razón social
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L)',
  pg_temp.u(903), pg_temp.u(203), pg_temp.header('invoice_a', 900005) || '{"issuer_tax_id": "99-99999999-9"}', 'X')),
  'El CUIT del emisor es de ejemplo (99-99999999-9): esa factura no vale.', 'caso 29: un emisor de ejemplo no se guarda');
-- Desde ADR-0070 el alta corta no pide el CAE: una A sin CAE se carga, pero no se controla hasta tenerlo.
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L) ->> %L',
  pg_temp.u(903), pg_temp.u(203), pg_temp.header('invoice_a', 900077) - 'authorization_code' - 'authorization_kind',
  'X', 'result')),
  'applied', 'caso 29: una A sin CAE se carga (el CAE se completa en la ficha)');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L)',
  (select id from purchasing.invoices where supplier_id = pg_temp.u(903) and number = 900077))),
  'Cargá la autorización (CAE, CAI o CAEA y su número) antes de controlar.',
  'caso 29: pero no se controla sin el CAE');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L)',
  pg_temp.u(903), pg_temp.u(203), pg_temp.header('invoice_a', 900005) || '{"issuer_tax_id": "30500000011"}', 'X')),
  'El CUIT de la factura no es el del proveedor.', 'el CUIT del emisor tiene que ser el del proveedor');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L)',
  pg_temp.u(903), pg_temp.u(203),
  pg_temp.header('invoice_a', 900005) || '{"net_amount": 1000, "vat_amount": 210, "total_amount": 1210.02}', 'X')),
  'Las partes no suman el total: neto + exento + IVA + internos + percepciones − bonificación + redondeo tiene que dar el total.',
  'caso 30: totales que no cierran por $ 0,02 → rechazado');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L)',
  pg_temp.u(903), pg_temp.u(203), pg_temp.header('invoice_a', 900001), 'X')),
  'Esa factura ya está cargada (mismo proveedor, clase, punto de venta y número).', 'única por clase, PV y número');

select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L)',
  pg_temp.u(903), pg_temp.u(203),
  pg_temp.header('invoice_a', 900008) || jsonb_build_object('issued_on', recipes.today() + 1), 'X')),
  'La fecha de la factura no puede ser posterior a hoy.', 'una factura con fecha futura no se guarda');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L)',
  pg_temp.u(903), pg_temp.u(203), pg_temp.k('oc'), pg_temp.header('invoice_a', 900008), 'X')),
  'Cada orden tiene que ser de este proveedor y este local, estar recibida y no estar facturada entera.',
  'una OC ya facturada entera no se vuelve a facturar');

-- N1: una factura más vieja que el costo vigente del local queda conforme, pero no lo pisa.
insert into pg_temp.k values ('a7', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc5'), pg_temp.header('invoice_a', 900010) || jsonb_build_object('issued_on', recipes.today() - 6),
  'Factura vieja', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('a7'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L)',
  pg_temp.k('a7'), '{}',
  (select jsonb_agg(case when x ->> 'purchase_product_id' = pg_temp.u(3801)::text
                         then x || '{"unit_price": 40000, "line_amount": 80000}'::jsonb
                         else x || '{"unit_price": 7000, "line_amount": 229600}'::jsonb end)
     from jsonb_array_elements(pg_temp.lines(pg_temp.k('a7'))) x), 'Como en el papel'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a7'), pg_temp.footer(pg_temp.k('a7')), 'El pie'));
select pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a7'), 'status'));
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('a7'),
                                           'Llegó tarde, revisada', 'status')),
          'released', 'una factura de hace 6 días, conforme después que las más nuevas');
select is((select count(*)::int from costing.price_records r join purchasing.invoice_lines l on l.id = r.invoice_line_id
            where l.invoice_id = pg_temp.k('a7')),
          0, 'N1: no registra precio: es anterior al costo vigente del local');
select is((select unit_cost from costing.price_rows(pg_temp.u(203), recipes.today(), pg_temp.u(827))),
          1.20000000::numeric, 'y el costo vigente sigue siendo el de la compra más nueva ($ 1.200 el kg)');

-- M4: quien suma la nota (y sube su foto) no deja la factura conforme sola, aunque cubra la diferencia.
insert into pg_temp.k values ('a8', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc6'), pg_temp.header('invoice_a', 900011), 'Factura con diferencia', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('a8'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L)',
  pg_temp.k('a8'), '{}',
  (select jsonb_agg(case when x ->> 'purchase_product_id' = pg_temp.u(3801)::text
                         then x || '{"unit_price": 50010, "line_amount": 100020}'::jsonb else x end)
     from jsonb_array_elements(pg_temp.lines(pg_temp.k('a8'))) x), 'Como en el papel'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a8'), pg_temp.footer(pg_temp.k('a8')), 'El pie'));
select pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a8'), 'status'));
select is(pg_temp.msg(pg_temp.u(401), format('select purchasing.add_credit_debit_note(%L, %L::jsonb, %L)',
  pg_temp.k('a8'), jsonb_build_object('note_kind', 'credit', 'issued_on', recipes.today(), 'net_amount', 99999999),
  'Una nota enorme')),
  'Las notas de crédito y los descuentos no pueden superar el total de la factura.',
  'una nota de crédito no supera el total de la factura');
insert into pg_temp.k values ('nc8', (pg_temp.q(pg_temp.u(401), format(
  'select purchasing.add_credit_debit_note(%L, %L::jsonb, %L) ->> %L', pg_temp.k('a8'),
  jsonb_build_object('note_kind', 'credit', 'issued_on', recipes.today(), 'net_amount', 20), 'Diferencia de precio',
  'note_id')))::uuid);
select is(pg_temp.note_photo_by(pg_temp.k('nc8'), 401), 'observed',
          'M4: la nota cubre la diferencia, pero quien la sumó no deja la factura conforme sola');
select ok(exists (select 1 from purchasing.invoice_checks where invoice_id = pg_temp.k('a8') and check_kind = 'notes'
                   and not passed and explanation like 'Las notas cubren la diferencia, pero%'),
          'y lo dice en simple');
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L) ->> %L', pg_temp.k('a8'),
                                           'Nota revisada', 'status')),
          'released', 'la da por conforme otra persona');

-- Un artículo que no se reconoce, otra razón social y sin lista vigente.
insert into pg_temp.k values ('a4', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc4'), pg_temp.header('invoice_a', 900006, '30500000046'), 'Factura de prueba', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('a4'));
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L) ->> %L',
  pg_temp.k('a4'), '{}',
  pg_temp.lines(pg_temp.k('a4'))
  || jsonb_build_array(jsonb_build_object('raw_name', 'Dulce de leche repostero x 10 kg', 'billed_quantity', 1,
                                          'unit_price', 30000, 'vat_rate', 21, 'line_amount', 30000)),
  'Como en el papel', 'new_unmapped')),
  '1', 'un artículo que no se reconoce va a la cola de mapeo');
select is((select found_in::text from purchasing.unmapped_articles
            where raw_name = 'Dulce de leche repostero x 10 kg' and status = 'pending'),
          'invoice', 'con origen «factura»');
select ok(exists (select 1 from core.notifications where kind = 'unmapped_article' and body like 'Llegaron en la Factura A 0003-00900006%'),
          'y avisa a quien mapea');
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a4'), pg_temp.footer(pg_temp.k('a4')), 'El pie'));
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a4'), 'status')),
          'observed', 'queda observada');
select ok(not pg_temp.check_passed(pg_temp.k('a4'), 'mapping', 'Dulce de leche repostero x 10 kg'),
          'por el artículo sin mapear');
select ok(not pg_temp.check_passed(pg_temp.k('a4'), 'legal_entity'), 'y por estar facturada a otra razón social');
select is(pg_temp.msg(pg_temp.u(407), format('select purchasing.approve_invoice(%L, %L)', pg_temp.k('a4'), 'Revisada')),
          'Primero hay que mapear «Dulce de leche repostero x 10 kg»: sin su materia prima no hay costo.',
          'sin mapear no se da por conforme');

-- La misma mercadería en una segunda factura: lo recibido ya está facturado en la a4.
insert into pg_temp.k values ('a6', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, array[%L]::uuid[], %L::jsonb, %L) ->> %L', pg_temp.u(903), pg_temp.u(203),
  pg_temp.k('oc4'), pg_temp.header('invoice_a', 900009), 'Factura repetida', 'invoice_id')))::uuid);
select is((select count(*)::int from purchasing.invoice_lines where invoice_id = pg_temp.k('a6') and deleted_at is null),
          0, 'una segunda factura de la misma OC no trae lo que ya está facturado');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L)',
  pg_temp.k('a6'), '{}',
  (select jsonb_agg(x) from jsonb_array_elements(pg_temp.lines(pg_temp.k('a4'))) x
    where x ->> 'purchase_product_id' = pg_temp.u(3801)::text)
  || (select jsonb_agg(x) from jsonb_array_elements(pg_temp.lines(pg_temp.k('a4'))) x
       where x ->> 'purchase_product_id' = pg_temp.u(3801)::text),
  'Repetida')),
  'La línea 2 repite una línea de la OC que ya está en esta factura.', 'dos líneas no van contra la misma línea de la OC');
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, null, %L)',
  pg_temp.k('a6'), '{}',
  (select jsonb_agg(x) from jsonb_array_elements(pg_temp.lines(pg_temp.k('a4'))) x
    where x ->> 'purchase_product_id' = pg_temp.u(3801)::text), 'Como la a4'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a6'), pg_temp.footer(pg_temp.k('a6')), 'El pie'));
select pg_temp.invoice_photo(pg_temp.k('a6'));
select is(pg_temp.q(pg_temp.u(401), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a6'), 'status')),
          'observed', 'facturar dos veces lo mismo no pasa');
select ok(not pg_temp.check_passed(pg_temp.k('a6'), 'quantity', 'Azúcar de prueba, bolsa de 50 kg'),
          'por la cantidad: lo recibido ya está facturado');

insert into pg_temp.k values ('a5', (pg_temp.q(pg_temp.u(408), format(
  'select purchasing.create_invoice(%L, %L, null, %L::jsonb, %L) ->> %L', pg_temp.u(904), pg_temp.u(203),
  pg_temp.header('invoice_a', 900007) || '{"issuer_tax_id": "30500000046"}', 'Factura del Almacén', 'invoice_id')))::uuid);
select pg_temp.invoice_photo(pg_temp.k('a5'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, %L::jsonb, %L::jsonb, %L)',
  pg_temp.k('a5'), '{}',
  jsonb_build_array(jsonb_build_object('purchase_product_id',
                                       (select id from catalog.purchase_products where supplier_id = pg_temp.u(904)
                                         and deleted_at is null order by code limit 1),
                                       'raw_name', 'Artículo del almacén', 'billed_quantity', 1, 'unit_price', 1000,
                                       'vat_rate', 21, 'line_amount', 1000)),
  '[]', 'Como en el papel'));
select pg_temp.msg(pg_temp.u(408), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L)',
                                          pg_temp.k('a5'), pg_temp.footer(pg_temp.k('a5')), 'El pie'));
select pg_temp.q(pg_temp.u(408), format('select purchasing.run_invoice_checks(%L) ->> %L', pg_temp.k('a5'), 'status'));
select alike((select explanation from purchasing.invoice_checks where invoice_id = pg_temp.k('a5') and check_kind = 'price'
             order by entry_number desc limit 1),
            'Sin lista de precios vigente%', 'sin lista aceptada a la fecha: «Sin lista de precios vigente»');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.cancel_invoice(%L, %L) ->> %L', pg_temp.k('a5'),
                                           'Se cargó por error', 'status')),
          'cancelled', 'una factura cargada por error se cancela con motivo');

-- ---------------------------------------------------------------------------
-- RLS y auditoría
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from purchasing.invoices'), '0',
          'la Cocinera no ve facturas');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from purchasing.invoice_lines'), '0', 'ni sus líneas');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from purchasing.invoices where restaurant_id = %L',
                                           pg_temp.u(203))),
          '0', 'el Gerente de Pastas Centro no ve las de la Parrilla');
select is(pg_temp.q(pg_temp.u(404), format('select purchasing.save_invoice(%L, %L::jsonb, null, null, %L) ->> %L',
                                           pg_temp.k('a4'), '{}', 'Cambio', 'result')),
          'denied', 'ni las cambia');
select is(pg_temp.q(pg_temp.u(410), format('select count(*)::text from purchasing.invoices where id = %L',
                                           pg_temp.k('a1'))),
          '1', 'el Auditor las ve');
select is(pg_temp.q(pg_temp.u(408), format('select count(*)::text from purchasing.invoice_checks where invoice_id = %L',
                                           pg_temp.k('a1'))) <> '0',
          true, 'Compras ve el resultado de los controles');
select is(pg_temp.q(pg_temp.u(408), format('insert into purchasing.invoices (group_id) values (%L) returning 1',
                                           pg_temp.u(1))),
          'ERROR 42501', 'nadie escribe directo: solo con las funciones');
select throws_ok(format('delete from purchasing.invoices where id = %L', pg_temp.k('a1')), '42501',
                 'Una factura no se borra: se cancela, con motivo.', 'una factura no se borra');
select throws_ok(format('update purchasing.credit_debit_notes set net_amount = 1 where id = %L', pg_temp.k('nc')), '42501',
                 'Una nota de crédito o débito no se cambia ni se borra: se corrige con otra nota.', 'ni se cambia una nota');
select throws_ok(format('update purchasing.invoice_checks set passed = true where invoice_id = %L', pg_temp.k('a6')),
                 '42501', 'El resultado de un control no se cambia ni se borra: se vuelve a controlar.',
                 'ni el resultado de un control');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.can_upload_document(%L)::text',
            format('00000000-0000-4000-8000-000000000001/invoices/%s/%s.jpg', pg_temp.k('a1'), gen_random_uuid()))),
          'false', 'a una factura conforme no se le suben fotos');
select throws_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, supplier_id, scope_type, restaurant_id, valid_from,
                                       package_price, document_type, vat_rate, price_includes_vat, source,
                                       invoice_line_id, approved_by, approved_at)
    values (%L, %L, %L, 'restaurant', %L, current_date, 1, 'invoice', 21, false, 'invoice', %L, %L, now())$$,
  pg_temp.u(1), pg_temp.u(3801), pg_temp.u(903), pg_temp.u(203),
  (select id from purchasing.invoice_lines where invoice_id = pg_temp.k('a6') and deleted_at is null limit 1),
  pg_temp.u(407)),
  '23514', 'Un precio de factura sale de una línea de una factura conforme, del mismo producto y local.',
  'un precio no entra desde una factura que no está conforme');
select ok(exists (select 1 from audit.audit_events where record_id = pg_temp.k('a3') and reason = 'El proveedor avisó el aumento'),
          'el conforme a mano queda en la historia con su motivo');

select * from finish();
rollback;
