-- Recepción con fotos y validación por línea (Fase 3, Prompt 4, ADR-0056).
-- Personas del seed: Dirección 402, Gerente 404 (Pastas Centro), Chef de marca 405, Jefe de Cocina 406 (Pastas Centro),
-- Controller 407, Compras 408, Cocinera 409 (Pastas Centro), Auditor 410, Gerente de dos locales 411 (Centro y Norte).
-- Locales: Pastas Centro 201, Parrilla Centro 203 (con las dos recepciones del seed). Proveedores: Verdulería 901,
-- Lácteos 903. Materia prima 819: mozzarella (unidad de uso g).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(82);

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

-- Ids que se van creando, para usarlos desde la sesión de cada persona.
create table pg_temp.k (name text primary key, id uuid not null);
create function pg_temp.k(p_name text) returns uuid language sql security definer as $$
  select id from pg_temp.k where name = p_name
$$;
grant execute on function pg_temp.k(text) to authenticated;
-- El renglón n de una OC.
create function pg_temp.line(p_order uuid, p_n int) returns uuid language sql security definer as $$
  select id from purchasing.purchase_order_lines where purchase_order_id = p_order and line_order = p_n and deleted_at is null
$$;
grant execute on function pg_temp.line(uuid, int) to authenticated;
-- n artículos activos del proveedor, con la cantidad dada (la Cocinera no lee el catálogo de productos).
create function pg_temp.products(p_supplier int, p_n int, p_qty numeric) returns jsonb language sql security definer as $$
  select jsonb_agg(jsonb_build_object('purchase_product_id', p.id, 'quantity', p_qty))
    from (select id from catalog.purchase_products
           where supplier_id = pg_temp.u(p_supplier) and deleted_at is null and is_active order by code limit p_n) p
$$;
grant execute on function pg_temp.products(int, int, numeric) to authenticated;
-- Una foto «subida» a la carpeta de la recepción por esa persona (la fila de Storage) y registrada con su sesión.
create function pg_temp.photo(p_receipt uuid, p_user int, p_kind text) returns text language plpgsql as $$
declare
  v_path text := format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', p_receipt, gen_random_uuid());
begin
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, pg_temp.u(p_user)::text, '{"mimetype": "image/jpeg", "size": 120000}');
  return pg_temp.q(pg_temp.u(p_user), format(
    'select purchasing.add_receipt_attachment(%L, %L, %L) ->> ''result''', p_receipt, v_path, p_kind));
end
$$;

-- La OC de prueba: la Cocinera le pide a la Verdulería dos artículos (2 envases cada uno) y una mozzarella «sin nombre
-- de factura» (500 g). Desde ADR-0069 ya no se pide una materia prima suelta, pero las OC de antes la tienen y se
-- siguen recibiendo: esa línea se agrega como estaba guardada (como postgres), antes de mandarla.
insert into pg_temp.k
select 'oc', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), pg_temp.products(901, 2, 2),
           null, null, 'Prueba de recepción') ->> 'purchase_order_id' $$))::uuid;
insert into purchasing.purchase_order_lines (group_id, purchase_order_id, line_order, ingredient_id, unit_id, quantity)
select o.group_id, o.id, 3, i.id, i.recipe_unit_id, 500
  from purchasing.purchase_orders o, catalog.ingredients i
 where o.id = pg_temp.k('oc') and i.id = pg_temp.u(819);
select pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.k('oc'), 'Prueba de recepción') ->> 'result' $$);

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('purchasing', 'receipts', 'existe purchasing.receipts');
select has_table('purchasing', 'receipt_lines', 'existe purchasing.receipt_lines');
select ok(not has_table_privilege('authenticated', 'purchasing.receipts', 'insert')
          and not has_table_privilege('authenticated', 'purchasing.receipt_lines', 'insert')
          and not has_table_privilege('authenticated', 'purchasing.receipts', 'update'),
          'la API no escribe directo: solo las funciones');
select ok(not has_column_privilege('authenticated', 'purchasing.receipts', 'cash_paid_amount', 'select'),
          'el efectivo no se lee por la API (protegido por columna)');
select ok((select bool_and(col_description(a.attrelid, a.attnum) is not null)
             from pg_attribute a
            where a.attrelid in ('purchasing.receipts'::regclass, 'purchasing.receipt_lines'::regclass)
              and a.attnum > 0 and not a.attisdropped), 'cada columna tiene su comentario');
select is((select array_agg(r.code || '=' || p.code order by r.code, p.code)
             from core.role_permissions rp join core.roles r on r.id = rp.role_id
             join core.permissions p on p.id = rp.permission_id
            where p.code = 'purchasing.receive' and rp.deleted_at is null),
          array['brand_director=purchasing.receive', 'cook=purchasing.receive', 'head_chef=purchasing.receive',
                'purchasing=purchasing.receive', 'restaurant_manager=purchasing.receive',
                'superadmin=purchasing.receive'],
          'reciben el Gerente, el Jefe de Cocina, el Cocinero y Compras (y quien los administra, G2)');

-- ---------------------------------------------------------------------------
-- Abrir
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(407), $$ select purchasing.start_receipt(pg_temp.k('oc')) ->> 'result' $$), 'denied',
          'el Controller no recibe');
select is(pg_temp.q(pg_temp.u(410), $$ select purchasing.start_receipt(pg_temp.k('oc')) ->> 'result' $$), 'denied',
          'el Auditor tampoco');
select ok(exists (select 1 from audit.authentication_security_events where operation = 'purchasing.start_receipt'),
          'el rechazo queda en los eventos de seguridad');
insert into pg_temp.k
select 'r1', (pg_temp.q(pg_temp.u(404), $$ select purchasing.start_receipt(pg_temp.k('oc')) ->> 'receipt_id' $$))::uuid;
select ok(pg_temp.k('r1') is not null, 'el Gerente abre la recepción de la OC de su local');
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.start_receipt(pg_temp.k('oc')) ->> 'receipt_id' $$),
          pg_temp.k('r1')::text, 'la Cocinera la retoma: una sola recepción abierta por OC');
select is(pg_temp.q(pg_temp.u(411), $$ select purchasing.start_receipt(pg_temp.k('oc'), pg_temp.u(203)) ->> 'result' $$),
          'denied', 'no se recibe en un local donde no se recibe');

-- ---------------------------------------------------------------------------
-- Fotos
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(404), $$
  insert into storage.objects (bucket_id, name, owner_id)
  values ('purchasing-documents', format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r1'),
                                         gen_random_uuid()), (select auth.uid())::text) $$),
  'sin error', 'el Gerente sube una foto a la carpeta de la recepción abierta');
select isnt(pg_temp.msg(pg_temp.u(407), $$
  insert into storage.objects (bucket_id, name, owner_id)
  values ('purchasing-documents', format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r1'),
                                         gen_random_uuid()), (select auth.uid())::text) $$),
  'sin error', 'el Controller no sube fotos');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true)),
           null, null) $$),
  'Falta la foto 1: el remito o la factura como llegó.', 'sin la foto 1 no se cierra');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.add_receipt_attachment(pg_temp.k('r1'),
           format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r1'), gen_random_uuid()),
           'receipt_original') $$),
  'La foto no está subida en la carpeta de esta recepción.', 'no se registra una foto que no se subió');
select is(pg_temp.photo(pg_temp.k('r1'), 404, 'receipt_original'), 'applied', 'se registra la foto 1');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true)),
           null, null) $$),
  'Falta la foto 2: el papel firmado.', 'sin la foto 2 (firmado) no se cierra');
select is(pg_temp.photo(pg_temp.k('r1'), 404, 'receipt_signed'), 'applied', 'se registra la foto 2');
select is(pg_temp.photo(pg_temp.k('r1'), 404, 'receipt_original'), 'applied', '«Rehacer» la foto 1 suma otra');
select is(pg_temp.q(pg_temp.u(404), $$
  select jsonb_array_length(purchasing.receipt_detail(pg_temp.k('r1')) -> 'photos')::text $$),
  '2', 'y la ficha muestra la última de cada foto');

-- ---------------------------------------------------------------------------
-- Cerrar: cada renglón pendiente lleva su decisión
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 2), 'ok', true)),
           null, null) $$),
  'Falta decidir 1 renglón de la orden: marcá OK u Observar.', 'un renglón sin decidir: error claro');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), null, null, '[]', null, null) $$),
  'Elegí qué papel trajo el proveedor.', 'sin la clase de papel no se cierra');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 2), 'ok', false,
                                                'issue', 'missing', 'received_quantity', 1),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 3), 'ok', true)),
           null, null) $$),
  'Hubo observaciones: escribí el motivo.', 'con observaciones, el motivo es obligatorio');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 2), 'ok', false,
                                                'issue', 'missing', 'received_quantity', 2),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 3), 'ok', true)),
           null, 'Faltó') $$),
  'En el renglón 2 marcaste que faltó: lo recibido tiene que ser menos que lo pedido.',
  '«faltó» con todo lo pedido no tiene sentido');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', false,
                                                'issue', 'different_product', 'received_quantity', 2)),
           null, 'Otro producto') $$),
  'En el renglón 1 mandaron otro producto: lo pedido no llegó (0). Cargá lo que vino como «Llegó algo que no estaba».',
  '«otro producto» no recibe lo pedido');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', false,
                                                'issue', 'extra', 'received_quantity', 2)),
           null, 'De más') $$),
  'En el renglón 1 marcaste que vino de más: lo recibido tiene que ser más que lo pedido.',
  '«de más» tiene que traer más que lo pedido');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true)),
           -5, null) $$),
  'El importe en efectivo tiene que ser mayor que cero.', 'el efectivo va en positivo');
-- Faltante: el renglón 2 llega 1 de 2; el 3 trae lote; se pagó en efectivo.
select is(pg_temp.q(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'invoice_remito', 'A 0001-00000370',
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 2), 'ok', false,
                                                'issue', 'missing', 'received_quantity', 1, 'note', 'Mandaron uno'),
                             jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 3), 'ok', true,
                                                'lot_code', 'LOTE-370')),
           5000, 'Faltó un cajón') ->> 'receipt_result' $$),
  'partial', 'con un faltante, la recepción queda parcial');
select is((select status::text from purchasing.purchase_orders where id = pg_temp.k('oc')), 'partially_received',
          'y la OC, recibida parcial');
select is((select array_agg(received_quantity::int order by line_order) from purchasing.purchase_order_lines
            where purchase_order_id = pg_temp.k('oc') and deleted_at is null),
          array[2, 1, 500], 'lo recibido de cada renglón de la OC');
select is((select status::text from purchasing.receipts where id = pg_temp.k('r1')), 'closed', 'la recepción queda cerrada');
select throws_ok($$ update purchasing.receipts set paper_number = 'otro' where id = pg_temp.k('r1') $$, '42501',
                 'Una recepción cerrada no se cambia.', 'una recepción cerrada no se cambia');
select throws_ok($$ update purchasing.receipt_lines set note = 'otra' where receipt_id = pg_temp.k('r1') $$, '42501',
                 'Una recepción cerrada no se cambia.', 'ni sus renglones');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r1'), 'remito', null, '[]', null, null) $$),
  'Esta recepción ya se cerró.', 'no se cierra dos veces');

-- ---------------------------------------------------------------------------
-- Avisos y auditoría
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from core.notifications n join purchasing.purchase_orders o on o.id = pg_temp.k('oc')
                   where n.recipient_user_id = pg_temp.u(409) and n.kind = 'receipt_report'
                     and n.title = format('Llegó parte de la orden %s', o.number)
                     and n.link = format('/compras/ordenes/%s?seccion=recepcion', o.id)),
          'a la Cocinera, que pidió, le llega el informe');
select ok(exists (select 1 from core.notifications
                   where recipient_user_id = pg_temp.u(408) and kind = 'receipt_differences'
                     and body = 'Tuvo 1 observación. Se pagó en efectivo: confirmá el importe.'),
          'a Compras le llega el aviso de la observación y del efectivo');
select ok(not exists (select 1 from core.notifications where recipient_user_id = pg_temp.u(404)
                        and kind in ('receipt_report', 'receipt_differences')),
          'a quien recibió no le llega su propio aviso');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'receipts' and record_id = pg_temp.k('r1') and reason = 'Faltó un cajón'
                     and source = 'manual'),
          'el cierre queda en la auditoría con su motivo y origen manual');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'receipt_lines' and action = 'insert' and reason = 'Faltó un cajón'),
          'y cada renglón');

-- ---------------------------------------------------------------------------
-- Efectivo: solo quien ve precios
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(404), $$ select (purchasing.receipt_detail(pg_temp.k('r1')) ->> 'cash_paid_amount')::numeric::text $$),
          '5000.0000', 'el Gerente ve el importe en efectivo');
select is(pg_temp.q(pg_temp.u(409), $$
  select concat_ws('|', d ->> 'cash_paid', coalesce(d ->> 'cash_paid_amount', 'oculto'))
    from purchasing.receipt_detail(pg_temp.k('r1')) d $$),
  'true|oculto', 'la Cocinera sabe que se pagó en efectivo, pero no ve el importe');
select is(pg_temp.q(pg_temp.u(409), $$ select cash_paid_amount::text from purchasing.receipts where id = pg_temp.k('r1') $$),
          'ERROR 42501', 'ni lo lee directo');

-- ---------------------------------------------------------------------------
-- Volver a recibir lo que faltó
-- ---------------------------------------------------------------------------
insert into pg_temp.k
select 'r2', (pg_temp.q(pg_temp.u(409), $$ select purchasing.start_receipt(pg_temp.k('oc')) ->> 'receipt_id' $$))::uuid;
select isnt(pg_temp.k('r2'), pg_temp.k('r1'), 'una OC recibida parcial se vuelve a recibir, con otra recepción');
select is(pg_temp.q(pg_temp.u(409), $$
  select string_agg((l ->> 'pending')::numeric::int::text, ',')
    from jsonb_array_elements(purchasing.receipt_detail(pg_temp.k('r2')) -> 'lines') l $$),
  '1', 'que pide decidir solo lo pendiente: el renglón 2, con 1 envase');
select pg_temp.photo(pg_temp.k('r2'), 409, 'receipt_original');
select pg_temp.photo(pg_temp.k('r2'), 409, 'receipt_signed');
select is(pg_temp.msg(pg_temp.u(409), $$
  select purchasing.close_receipt(pg_temp.k('r2'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 1), 'ok', true)),
           null, null) $$),
  'El renglón 1 ya se recibió entero.', 'lo ya recibido no se vuelve a recibir');
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.close_receipt(pg_temp.k('r2'), 'remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc'), 2), 'ok', true)),
           null, null) ->> 'receipt_result' $$),
  'complete', 'llega lo que faltaba: la segunda recepción, completa');
select is((select status::text from purchasing.purchase_orders where id = pg_temp.k('oc')), 'received',
          'y la OC queda recibida');
select is(pg_temp.msg(pg_temp.u(409), $$ select purchasing.start_receipt(pg_temp.k('oc')) $$),
          'Esta orden no está para recibir: tiene que estar enviada o recibida parcial.',
          'una OC recibida ya no se abre');
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from purchasing.order_receipts(pg_temp.k('oc')) $$), '2',
          'la ficha de la OC muestra sus dos recepciones');

-- ---------------------------------------------------------------------------
-- Con observaciones, todo recibido
-- ---------------------------------------------------------------------------
insert into pg_temp.k
select 'oc2', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(903),
           pg_temp.products(903, 1, 3), null, null, 'Lácteos') ->> 'purchase_order_id' $$))::uuid;
select pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.k('oc2'), 'Lácteos') ->> 'result' $$);
insert into pg_temp.k
select 'r3', (pg_temp.q(pg_temp.u(406), $$ select purchasing.start_receipt(pg_temp.k('oc2')) ->> 'receipt_id' $$))::uuid;
select pg_temp.photo(pg_temp.k('r3'), 406, 'receipt_original');
select pg_temp.photo(pg_temp.k('r3'), 406, 'receipt_signed');
select is(pg_temp.q(pg_temp.u(406), $$
  select purchasing.close_receipt(pg_temp.k('r3'), 'electronic_remito', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc2'), 1), 'ok', false,
                                                'issue', 'quality', 'received_quantity', 3, 'note', 'Golpeado')),
           null, 'Uno llegó golpeado') ->> 'receipt_result' $$),
  'with_differences', 'el Jefe de Cocina recibe todo, con una observación de calidad');
select is((select status::text from purchasing.purchase_orders where id = pg_temp.k('oc2')), 'received',
          'la OC queda recibida');

-- ---------------------------------------------------------------------------
-- Recibir sin OC y lo que no estaba
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(407), $$
  select purchasing.start_receipt_without_order(pg_temp.u(903), pg_temp.u(201)) ->> 'result' $$),
  'denied', 'el Controller no recibe sin OC');
insert into pg_temp.k
select 'r4', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.start_receipt_without_order(pg_temp.u(903), pg_temp.u(201)) ->> 'receipt_id' $$))::uuid;
select ok(pg_temp.k('r4') is not null, 'la Cocinera abre una recepción sin OC');
select pg_temp.photo(pg_temp.k('r4'), 409, 'receipt_original');
select pg_temp.photo(pg_temp.k('r4'), 409, 'receipt_signed');
select is(pg_temp.msg(pg_temp.u(409), $$
  select purchasing.close_receipt(pg_temp.k('r4'), 'non_fiscal', null,
           jsonb_build_array(jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc2'), 1), 'ok', true)),
           null, null) $$),
  'Esta recepción no tiene OC: cargá lo que llegó como «Llegó algo que no estaba».',
  'sin OC no hay renglones de una OC');
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.close_receipt(pg_temp.k('r4'), 'non_fiscal', null,
           jsonb_build_array(jsonb_build_object('name', 'Producto misterioso 370', 'received_quantity', 3),
                             jsonb_build_object('name', 'Manteca, pan de 5 kg', 'received_quantity', 1,
                                                'lot_code', 'MAN-370')),
           null, null) ->> 'new_unmapped' $$),
  '1', 'se cierra: lo que no se reconoce va a la cola de mapeo');
select ok(exists (select 1 from purchasing.unmapped_articles
                   where raw_name = 'Producto misterioso 370' and found_in = 'receipt' and source_id = pg_temp.k('r4')
                     and status = 'pending'),
          'el artículo queda pendiente, con la recepción de origen');
select ok(exists (select 1 from core.notifications
                   where recipient_user_id = pg_temp.u(405) and kind = 'unmapped_article'
                     and body like 'Llegaron en una recepción%'),
          'y le avisa a la Chef, que mapea');
select is((select count(*)::int from purchasing.receipt_lines l
             join inventory.stock_movements m on m.source_id = l.id
            where l.receipt_id = pg_temp.k('r4')), 1,
          'solo suma stock lo que se reconoce (la manteca), no lo que está en la cola');

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from purchasing.receipts where restaurant_id <> pg_temp.u(201) $$),
          '0', 'la Cocinera ve solo las recepciones de su local');
select ok(pg_temp.q(pg_temp.u(408), $$ select count(*)::text from purchasing.receipts where restaurant_id = pg_temp.u(203) $$)::int >= 2,
          'Compras ve las de todo el grupo (las del seed, en la Parrilla)');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.receipt_lines l join purchasing.receipts r on r.id = l.receipt_id
   where r.restaurant_id = pg_temp.u(203) $$),
  '0', 'ni los renglones de otro local');
select is(pg_temp.q(pg_temp.u(409), $$
  select (purchasing.receipt_detail(r.id) is null)::text from purchasing.receipts r
   where r.restaurant_id = pg_temp.u(203) limit 1 $$),
  null, 'ni su ficha (no la encuentra)');
select ok(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.attachments where source_table = 'receipts' and source_id = pg_temp.k('r1') $$)::int = 3,
  'la Cocinera ve las fotos de la recepción de su local (las 3 que se subieron)');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.attachments a join purchasing.receipts r on r.id = a.source_id
   where r.restaurant_id = pg_temp.u(203) $$),
  '0', 'y no las de otro local');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.receivable_orders(pg_temp.u(203)) $$),
  '0', 'no ve qué recibir en otro local');
select ok(pg_temp.q(pg_temp.u(404), $$
  select count(*)::text from purchasing.receivable_orders(pg_temp.u(201)) $$)::int >= 2,
  'el Gerente ve las OC para recibir de su local');

-- ---------------------------------------------------------------------------
-- Revisiones de base y seguridad, y decisiones de Joaco (2026-11-17)
-- ---------------------------------------------------------------------------
select is((select closed_by from purchasing.receipts where id = pg_temp.k('r2')), pg_temp.u(409),
          'queda quién cerró (la Cocinera retomó y cerró la segunda)');
select ok((select closed_by from purchasing.receipts where id = pg_temp.k('r1')) = pg_temp.u(404),
          'y en la primera, el Gerente');
select throws_ok($$ insert into purchasing.receipt_lines (group_id, receipt_id, line_order, purchase_product_id,
                                                          description, ok, received_quantity)
                    select group_id, id, 99, null, 'De prueba', true, 1 from purchasing.receipts where id = pg_temp.k('r1') $$,
                 '42501', 'Una recepción cerrada no se cambia.', 'no se suma un renglón a una recepción cerrada');
select throws_ok($$ delete from purchasing.receipts where id = pg_temp.k('r1') $$, '42501',
                 'Una recepción cerrada no se cambia.', 'ni se borra');
select ok(exists (select 1 from core.notifications
                   where recipient_user_id = pg_temp.u(408) and kind = 'receipt_differences'
                     and body = 'Llegó sin orden de compra.'),
          'toda recepción sin OC le avisa a Compras');
-- Una OC nueva de Lácteos, de dos renglones, para los casos que siguen.
insert into pg_temp.k
select 'oc3', (pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(903), pg_temp.products(903, 2, 2), null, null,
                                     'Revisiones') ->> 'purchase_order_id' $$))::uuid;
select pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.k('oc3'), 'Revisiones') ->> 'result' $$);
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.start_receipt(pg_temp.k('oc3'), pg_temp.u(202)) $$),
          'Se recibe en el local que pidió la orden.', 'se recibe en el local que pidió la orden');
insert into pg_temp.k
select 'r5', (pg_temp.q(pg_temp.u(404), $$ select purchasing.start_receipt(pg_temp.k('oc3')) ->> 'receipt_id' $$))::uuid;
-- Un PDF con nombre .jpg no pasa como foto.
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('purchasing-documents', format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r5'),
                                      '11111111-1111-4111-8111-111111111111'),
        pg_temp.u(404)::text, '{"mimetype": "application/pdf", "size": 1000}');
select is(pg_temp.msg(pg_temp.u(404), format(
  'select purchasing.add_receipt_attachment(%L, %L, ''receipt_original'')', pg_temp.k('r5'),
  format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r5'), '11111111-1111-4111-8111-111111111111'))),
  'La foto tiene que ser una imagen JPEG de hasta 4 MB.', 'la base controla que la foto sea JPEG, no solo la pantalla');
select is(pg_temp.q(pg_temp.u(409), format(
  'select count(*)::text from storage.objects where name = %L',
  format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r5'), '11111111-1111-4111-8111-111111111111'))),
  '0', 'lo subido y sin registrar lo lee solo quien lo subió');
select is(pg_temp.msg(pg_temp.u(404), $$
  insert into storage.objects (bucket_id, name, owner_id)
  values ('purchasing-documents', format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.pdf', pg_temp.k('r5'),
                                         gen_random_uuid()), (select auth.uid())::text) $$),
  'new row violates row-level security policy for table "objects"', 'a una recepción solo se suben fotos .jpg');
select pg_temp.photo(pg_temp.k('r5'), 404, 'receipt_original');
select pg_temp.photo(pg_temp.k('r5'), 404, 'receipt_signed');
select is(pg_temp.msg(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r5'), 'remito', null, jsonb_build_array(
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc3'), 1), 'ok', false,
                              'issue', 'quality', 'received_quantity', 3),
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc3'), 2), 'ok', true)),
           null, 'Calidad') $$),
  'En el renglón 1 llegó más de lo pedido: marcalo como «De más».', 'una observación que no es «de más» no trae más de lo pedido');
-- La foto de un producto observado, con su renglón.
insert into storage.objects (bucket_id, name, owner_id, metadata)
values ('purchasing-documents', format('00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r5'),
                                      '22222222-2222-4222-8222-222222222222'),
        pg_temp.u(404)::text, '{"mimetype": "image/jpeg", "size": 1000}');
select is(pg_temp.q(pg_temp.u(404), $$
  select purchasing.close_receipt(pg_temp.k('r5'), 'remito', null, jsonb_build_array(
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc3'), 1), 'ok', false,
                              'issue', 'expired', 'received_quantity', 2, 'note', 'Vencido ayer',
                              'photo_paths', jsonb_build_array(format(
                                '00000000-0000-4000-8000-000000000001/receipts/%s/%s.jpg', pg_temp.k('r5'),
                                '22222222-2222-4222-8222-222222222222'))),
           jsonb_build_object('purchase_order_line_id', pg_temp.line(pg_temp.k('oc3'), 2), 'ok', true)),
           null, 'Llegó vencido') ->> 'receipt_result' $$),
  'with_differences', 'se cierra con un renglón vencido');
select is((select count(*)::int from purchasing.receipt_lines l join inventory.stock_movements m on m.source_id = l.id
            where l.receipt_id = pg_temp.k('r5')), 1, 'lo vencido no suma stock; el renglón OK, sí');
select ok(exists (select 1 from purchasing.attachments a join purchasing.receipt_lines l on l.id = a.source_id
                   where a.source_table = 'receipt_lines' and a.doc_kind = 'product_issue' and l.receipt_id = pg_temp.k('r5')),
          'la foto del producto queda con su renglón');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.attachments a join purchasing.receipt_lines l on l.id = a.source_id
   where a.source_table = 'receipt_lines' and l.receipt_id = pg_temp.k('r5') $$),
  '1', 'y la ve la Cocinera, del mismo local');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.visible_document_paths() p where p like '%/receipts/%'
     and split_part(p, '/', 3)::uuid in (select id from purchasing.receipts where restaurant_id = pg_temp.u(203)) $$),
  '0', 'pero no las fotos de la Parrilla');

select * from finish();
rollback;
