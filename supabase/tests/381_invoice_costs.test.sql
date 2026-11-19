-- El cambio en la única fuente de costos (Fase 3, Prompt 5, ADR-0058): un precio entra con una solicitud aprobada, con
-- una línea de factura conforme o como valor de prueba; nunca sin ninguna. Y las alícuotas de 2,5 % y 5 % (P5).
-- Personas del seed: Controller 407, Compras 408. Producto DEMO-PROD-001 (de la Verdulería).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(8);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.product() returns uuid language sql as $$
  select id from catalog.purchase_products where code = 'DEMO-PROD-001'
$$;

select has_column('costing', 'price_records', 'invoice_line_id', 'price_records tiene la línea de factura de origen');

-- Sin solicitud, sin línea de factura y sin ser valor de prueba: no entra.
select throws_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                       document_type, vat_rate, source, approved_by, approved_at)
    values (%L, %L, 'group', current_date, 1000, 'invoice', 21, 'invoice', %L, now())$$,
  pg_temp.u(1), pg_temp.product(), pg_temp.u(407)),
  '23514', null, 'un precio «de factura» sin la línea de la factura no entra');
select throws_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                       document_type, vat_rate, source)
    values (%L, %L, 'group', current_date, 1000, 'invoice', 21, 'manual')$$,
  pg_temp.u(1), pg_temp.product()),
  '23514', null, 'uno manual sin solicitud aprobada, tampoco');
select throws_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                       document_type, vat_rate, source, invoice_line_id)
    select %L, %L, 'group', current_date, 1000, 'invoice', 21, 'invoice', id
      from purchasing.invoice_lines limit 1$$,
  pg_temp.u(1), pg_temp.product()),
  '23514', null, 'con línea de factura, pero sin quién la dio por conforme, tampoco');
select lives_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                       document_type, vat_rate, source)
    values (%L, %L, 'group', current_date, 1000, 'invoice', 21, 'test_value')$$,
  pg_temp.u(1), pg_temp.product()),
  'un valor de prueba sigue entrando como antes');

-- P5: 2,5 % y 5 %.
select lives_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                       document_type, vat_rate, price_includes_vat, source)
    values (%L, %L, 'group', current_date, 1025, 'invoice', 2.5, true, 'test_value')$$,
  pg_temp.u(1), pg_temp.product()),
  'P5: un precio con IVA de 2,5 % entra');
select is((select net_package_price from costing.price_records
            where purchase_product_id = pg_temp.product() and vat_rate = 2.5),
          1000.0000::numeric, 'y su neto es $ 1.025 / 1,025 = $ 1.000');
select throws_ok(format(
  $$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                       document_type, vat_rate, source)
    values (%L, %L, 'group', current_date, 1000, 'invoice', 3, 'test_value')$$,
  pg_temp.u(1), pg_temp.product()),
  '23514', null, 'una alícuota que no existe (3 %) no entra');

select * from finish();
rollback;
