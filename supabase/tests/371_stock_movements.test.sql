-- Entradas de stock por recepción e inventario (Fase 3, Prompt 4, ADR-0056; D8: nada descuenta todavía).
-- Personas del seed: Gerente 404, Jefe de Cocina 406 (Pastas Centro), Controller 407, Compras 408, Cocinera 409
-- (Pastas Centro), Auditor 410. Locales: Pastas Centro 201, Parrilla Centro 203 (con las recepciones del seed).
-- Materias primas: Limón 809 (unidad, 120 g c/u), Carne picada 811 (g), Mozzarella 819 (g), Huevo 826 (unidad, sin peso
-- por unidad), Harina 000 827 (g). Proveedor: Verdulería 901.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(30);

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
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
grant execute on function pg_temp.u(int) to authenticated;
create table pg_temp.k (name text primary key, id uuid not null);
create function pg_temp.k(p_name text) returns uuid language sql security definer as $$
  select id from pg_temp.k where name = p_name
$$;
grant execute on function pg_temp.k(text) to authenticated;
create function pg_temp.product(p_code text) returns uuid language sql security definer as $$
  select id from catalog.purchase_products where code = p_code and deleted_at is null
$$;
grant execute on function pg_temp.product(text) to authenticated;
-- El renglón de la OC con ese producto (o, sin producto, con esa materia prima).
create function pg_temp.line(p_order uuid, p_code text) returns uuid language sql security definer as $$
  select l.id from purchasing.purchase_order_lines l
    left join catalog.purchase_products p on p.id = l.purchase_product_id
   where l.purchase_order_id = p_order and l.deleted_at is null
     and (p.code = p_code or (p_code is null and l.purchase_product_id is null))
$$;
grant execute on function pg_temp.line(uuid, text) to authenticated;
create function pg_temp.photos(p_receipt uuid, p_user int) returns void language plpgsql as $$
declare
  v_path text;
  v_kind text;
begin
  foreach v_kind in array array['receipt_original', 'receipt_signed'] loop
    v_path := format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', p_receipt, gen_random_uuid());
    insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, pg_temp.u(p_user)::text, '{"mimetype": "image/jpeg", "size": 120000}');
    perform pg_temp.q(pg_temp.u(p_user), format(
      'select purchasing.add_receipt_attachment(%L, %L, %L) ->> ''result''', p_receipt, v_path, v_kind));
  end loop;
end
$$;
-- La cantidad que entró por un renglón de la OC.
create function pg_temp.stock(p_order uuid, p_code text) returns numeric language sql as $$
  select m.quantity from inventory.stock_movements m
    join purchasing.receipt_lines l on l.id = m.source_id
   where l.purchase_order_line_id = pg_temp.line(p_order, p_code)
$$;

-- Productos de prueba de la Verdulería: harina en bolsa de 50 kg (caso 16 del plan), carne al peso (pieza de ≈ 2 kg) y
-- huevo en bandeja de 1 kg. El huevo se usa por unidad: el catálogo pide su peso por unidad para crear el producto, y
-- después la prueba lo da de baja (una conversión que se borra más tarde: ya no se puede convertir).
insert into catalog.ingredient_unit_conversions (group_id, ingredient_id, kind, factor, source, measured_on, measured_by)
values (pg_temp.u(1), pg_temp.u(826), 'unit_weight', 55, 'estimated', '2026-11-01', 'Dato de prueba (371)');
insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, package_unit_id,
                                       units_per_package, content_per_unit, content_unit_id, billed_by_weight,
                                       estimated_weight_per_unit)
select pg_temp.u(1), v.code, pg_temp.u(v.ing), pg_temp.u(901), v.descr, (select id from catalog.units where code = v.pkg),
       1, v.content, (select id from catalog.units where code = v.cu), v.by_weight, v.est
  from (values ('T371-HAR', 827, 'Harina 000, bolsa de 50 kg', 'bag', 50, 'kg', false, null::numeric),
               ('T371-CAR', 811, 'Carne picada, pieza al peso', 'pack', 2000, 'g', true, 2000),
               ('T371-HUE', 826, 'Huevo, bandeja de 1 kg', 'pack', 1000, 'g', false, null)) as v (code, ing, descr, pkg, content, cu, by_weight, est);

-- La OC: harina ×2, limón por kg ×2, maple de huevos ×2, carne al peso ×3 y mozzarella «sin nombre de factura» 500 g.
insert into pg_temp.k
select 'oc', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), jsonb_build_array(
           jsonb_build_object('purchase_product_id', pg_temp.product('T371-HAR'), 'quantity', 2),
           jsonb_build_object('purchase_product_id', pg_temp.product('DEMO-PROD-009'), 'quantity', 2),
           jsonb_build_object('purchase_product_id', pg_temp.product('DEMO-PROD-026'), 'quantity', 2),
           jsonb_build_object('purchase_product_id', pg_temp.product('T371-CAR'), 'quantity', 3),
           jsonb_build_object('ingredient_id', pg_temp.u(819), 'quantity', 500)),
           null, null, 'Prueba de stock') ->> 'purchase_order_id' $$))::uuid;
select pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.k('oc'), 'Prueba de stock') ->> 'result' $$);
insert into pg_temp.k
select 'r', (pg_temp.q(pg_temp.u(406), $$ select purchasing.start_receipt(pg_temp.k('oc')) ->> 'receipt_id' $$))::uuid;
select pg_temp.photos(pg_temp.k('r'), 406);
select pg_temp.q(pg_temp.u(406), $$
  select purchasing.close_receipt(pg_temp.k('r'), 'remito', null, jsonb_build_array(
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 'T371-HAR'), 'ok', true,
                              'lot_code', 'LOTE-371'),
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 'DEMO-PROD-009'), 'ok', true),
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 'DEMO-PROD-026'), 'ok', true),
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 'T371-CAR'), 'ok', true,
                              'received_weight', 6.3),
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), null), 'ok', true)),
           null, null) ->> 'receipt_result' $$);

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('inventory', 'stock_movements', 'existe inventory.stock_movements');
select ok((select relrowsecurity from pg_class where oid = 'inventory.stock_movements'::regclass), 'con RLS');
select ok((select bool_and(col_description(a.attrelid, a.attnum) is not null) from pg_attribute a
            where a.attrelid = 'inventory.stock_movements'::regclass and a.attnum > 0 and not a.attisdropped),
          'cada columna tiene su comentario');
select ok(obj_description('inventory.stock_movements'::regclass, 'pg_class') is not null, 'y la tabla también');
select ok(not has_table_privilege('authenticated', 'inventory.stock_movements', 'insert')
          and not has_table_privilege('authenticated', 'inventory.stock_movements', 'update'),
          'la API no escribe movimientos');
select is((select array_agg(r.code order by r.code) from core.role_permissions rp join core.roles r on r.id = rp.role_id
             join core.permissions p on p.id = rp.permission_id
            where p.code = 'inventory.view' and rp.deleted_at is null),
          array['auditor', 'brand_director', 'controller', 'executive_chef', 'general_management', 'head_chef',
                'restaurant_manager', 'superadmin'],
          'ven el inventario: Dirección, Dir. de Marca, Gerente, Chef, Jefe de Cocina, Controller, Auditor (y el superadmin, G2)');

-- ---------------------------------------------------------------------------
-- Cuánto entra, en la unidad de uso
-- ---------------------------------------------------------------------------
select is((select status::text from purchasing.purchase_orders where id = pg_temp.k('oc')), 'received', 'la OC quedó recibida');
select is(pg_temp.stock(pg_temp.k('oc'), 'T371-HAR'), 100000::numeric,
          'caso 16: 2 bolsas de 50 kg de harina (unidad de uso g) entran como 100.000 g');
select is(round(pg_temp.stock(pg_temp.k('oc'), 'DEMO-PROD-009'), 4), 16.6667::numeric,
          '2 kg de limón (se usa por unidad, 120 g c/u) entran como 16,67 limones');
select is(pg_temp.stock(pg_temp.k('oc'), 'DEMO-PROD-026'), 60::numeric, '2 maples de 30 huevos entran como 60 huevos');
select is(pg_temp.stock(pg_temp.k('oc'), 'T371-CAR'), 6300::numeric,
          'lo que va por peso entra con los kilos pesados (6,3 kg = 6300 g), no con lo estimado');
select is(pg_temp.stock(pg_temp.k('oc'), null), 500::numeric,
          'la mozzarella «sin nombre de factura» entra en su unidad: 500 g');
select is((select array_agg(coalesce(m.packages::int::text, '—') order by l.line_order)
             from inventory.stock_movements m join purchasing.receipt_lines l on l.id = m.source_id
            where l.receipt_id = pg_temp.k('r')),
          array['2', '2', '2', '3', '—'], 'cada movimiento guarda los envases (sin producto, no hay envase)');
select ok((select bool_and(m.unit_id = i.recipe_unit_id) from inventory.stock_movements m
             join catalog.ingredients i on i.id = m.ingredient_id
             join purchasing.receipt_lines l on l.id = m.source_id
            where l.receipt_id = pg_temp.k('r')),
          'en la unidad de uso de cada materia prima');
select is((select m.lot_code from inventory.stock_movements m join purchasing.receipt_lines l on l.id = m.source_id
            where l.purchase_order_line_id = pg_temp.line(pg_temp.k('oc'), 'T371-HAR')),
          'LOTE-371', 'con el lote del renglón');
select ok(exists (select 1 from audit.audit_events where table_name = 'stock_movements' and action = 'insert'
                     and source = 'manual'),
          'cada entrada queda en la auditoría');

-- Si no se puede convertir, no se cierra.
insert into pg_temp.k
select 'oc2', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), jsonb_build_array(
           jsonb_build_object('purchase_product_id', pg_temp.product('T371-HUE'), 'quantity', 1)),
           null, null, 'Huevos en bandeja') ->> 'purchase_order_id' $$))::uuid;
select pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.k('oc2'), 'Huevos en bandeja') ->> 'result' $$);
insert into pg_temp.k
select 'r2', (pg_temp.q(pg_temp.u(406), $$ select purchasing.start_receipt(pg_temp.k('oc2')) ->> 'receipt_id' $$))::uuid;
select pg_temp.photos(pg_temp.k('r2'), 406);
-- El catálogo no deja quitar esa conversión: para probar la defensa de la recepción se apaga ese control dentro de esta
-- transacción de prueba (que se deshace al final), como si el dato se hubiera roto.
alter table catalog.ingredient_unit_conversions disable trigger validate_products_after_conversion_change;
update catalog.ingredient_unit_conversions set deleted_at = now()
 where ingredient_id = pg_temp.u(826) and kind = 'unit_weight' and deleted_at is null;
alter table catalog.ingredient_unit_conversions enable trigger validate_products_after_conversion_change;
select is(pg_temp.msg(pg_temp.u(406), $$
  select purchasing.close_receipt(pg_temp.k('r2'), 'remito', null, jsonb_build_array(
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc2'), 'T371-HUE'), 'ok', true)),
           null, null) $$),
  'No sabemos pasar «Huevo» a su unidad de uso: revisá el envase del producto o las conversiones de la materia prima.',
  'si no se puede pasar a la unidad de uso, la recepción no se cierra y lo dice');
select is((select status::text from purchasing.receipts where id = pg_temp.k('r2')), 'open', 'y queda abierta, sin stock a medias');

-- Un renglón OK que pesa más de un 20 % distinto de lo estimado se tiene que observar (Joaco, 2026-11-17).
insert into pg_temp.k
select 'oc3', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), jsonb_build_array(
           jsonb_build_object('purchase_product_id', pg_temp.product('T371-CAR'), 'quantity', 1)),
           null, null, 'Carne al peso') ->> 'purchase_order_id' $$))::uuid;
select pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.k('oc3'), 'Carne al peso') ->> 'result' $$);
insert into pg_temp.k
select 'r3', (pg_temp.q(pg_temp.u(406), $$ select purchasing.start_receipt(pg_temp.k('oc3')) ->> 'receipt_id' $$))::uuid;
select pg_temp.photos(pg_temp.k('r3'), 406);
select is(pg_temp.msg(pg_temp.u(406), $$
  select purchasing.close_receipt(pg_temp.k('r3'), 'remito', null, jsonb_build_array(
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc3'), 'T371-CAR'), 'ok', true,
                              'received_weight', 5)), null, null) $$),
  'El peso del renglón 1 (5 kg) se aleja más de un 20 % de lo estimado (≈ 2.0 kg): marcalo como observado, con el motivo.',
  'una pieza de ≈ 2 kg que pesa 5 kg no pasa como OK');

-- ---------------------------------------------------------------------------
-- Nadie cambia un movimiento
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(406), $$
  insert into inventory.stock_movements (group_id, brand_id, restaurant_id, ingredient_id, kind, quantity, unit_id,
                                         occurred_at, source_table, source_id)
  select group_id, brand_id, restaurant_id, ingredient_id, kind, 1, unit_id, now(), source_table, gen_random_uuid()
    from inventory.stock_movements limit 1
  returning id::text $$),
  'ERROR 42501', 'nadie inserta movimientos directo: solo al cerrar una recepción');
select throws_ok($$ update inventory.stock_movements set quantity = 1 $$, '42501',
                 'Un movimiento de stock no se cambia ni se borra: se corrige con otro movimiento.',
                 'un movimiento no se cambia');
select throws_ok($$ delete from inventory.stock_movements $$, '42501',
                 'Un movimiento de stock no se cambia ni se borra: se corrige con otro movimiento.',
                 'ni se borra');

-- ---------------------------------------------------------------------------
-- Quién ve el inventario
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from inventory.stock_movements $$), '0',
          'la Cocinera no ve el inventario');
select is(pg_temp.q(pg_temp.u(408), $$ select count(*)::text from inventory.stock_movements $$), '0',
          'Compras tampoco (recibe, pero no ve el inventario)');
select ok(pg_temp.q(pg_temp.u(406), $$ select count(*)::text from inventory.stock_movements where restaurant_id = pg_temp.u(201) $$)::int >= 5,
          'el Jefe de Cocina ve los de su local');
select is(pg_temp.q(pg_temp.u(406), $$ select count(*)::text from inventory.stock_movements where restaurant_id <> pg_temp.u(201) $$),
          '0', 'y no los de otro local');
select ok(pg_temp.q(pg_temp.u(407), $$ select count(*)::text from inventory.stock_movements where restaurant_id = pg_temp.u(203) $$)::int >= 5,
          'el Controller ve los de todo el grupo (los del seed, en la Parrilla)');
select ok(pg_temp.q(pg_temp.u(410), $$ select count(*)::text from inventory.stock_movements $$)::int >= 10,
          'el Auditor también');

-- ---------------------------------------------------------------------------
-- El listado, con el filtro por lote (P9: el lote se sigue desde Inventario)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(406), $$
  select concat_ws('|', ingredient_name, lot_code, order_number = (select number from purchasing.purchase_orders where id = pg_temp.k('oc')), total)
    from inventory.movement_list(p_lot => 'lote-371') $$),
  'Harina 000|LOTE-371|t|1', 'buscar un lote (sin importar mayúsculas) encuentra su entrada, con la OC de origen');
select is(pg_temp.q(pg_temp.u(406), $$ select count(*)::text from inventory.movement_list(p_restaurant_id => pg_temp.u(203)) $$),
          '0', 'el listado respeta lo que ve cada uno');

select * from finish();
rollback;
