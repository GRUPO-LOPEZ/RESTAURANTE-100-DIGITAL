-- Órdenes de compra (Fase 3, Prompt 3, ADR-0053).
-- Personas del seed: Gerente 404 (Pastas Centro), Chef de marca 405, Controller 407, Compras 408, Cocinera 409
-- (Pastas Centro), Gerente de dos locales 411 (Centro y Norte).
-- Locales: Pastas Centro 201 (PCE), Pastas Norte 202 (PNO), Café Centro 204 (sin código).
-- Proveedores: Verdulería 901, Frigorífico 902 (requiere aprobación; entrega martes, jueves y sábado), Lácteos 903.
-- OC del seed: PCE-0001 borrador, PCE-0002 pendiente (Frigorífico), PCE-0003 enviada, PCE-0004 con novedad (del Gerente).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(57);

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
-- Las líneas de prueba: n artículos activos del proveedor.
create function pg_temp.lines(p_supplier int, p_n int) returns jsonb language sql security definer as $$
  select jsonb_agg(jsonb_build_object('purchase_product_id', p.id, 'quantity', 2))
    from (select id from catalog.purchase_products
           where supplier_id = pg_temp.u(p_supplier) and deleted_at is null and is_active order by code limit p_n) p
$$;
grant execute on function pg_temp.lines(int, int) to authenticated;
create function pg_temp.order_id(p_number text) returns uuid language sql security definer as $$
  select id from purchasing.purchase_orders where number = p_number
$$;
grant execute on function pg_temp.order_id(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('purchasing', 'purchase_orders', 'existe purchasing.purchase_orders');
select has_table('purchasing', 'purchase_order_lines', 'existe purchasing.purchase_order_lines');
select has_table('purchasing', 'purchase_order_events', 'existe purchasing.purchase_order_events');
select has_table('purchasing', 'outbound_messages', 'existe purchasing.outbound_messages');
select ok(not has_table_privilege('authenticated', 'purchasing.purchase_orders', 'insert')
          and not has_table_privilege('authenticated', 'purchasing.outbound_messages', 'update'),
          'la API no escribe directo');

-- ---------------------------------------------------------------------------
-- Numeración por local
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), pg_temp.lines(901, 2), null, null,
                                     'Prueba') ->> 'number' $$),
  'PCE-0005', 'la próxima OC de Pastas Centro sigue la numeración del local');
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), pg_temp.lines(901, 1), null, null,
                                     'Prueba') ->> 'number' $$),
  'PCE-0006', 'y la siguiente, correlativa, sin saltos');
select is(pg_temp.q(pg_temp.u(411), $$
  select purchasing.save_order_draft(null, pg_temp.u(202), pg_temp.u(901), pg_temp.lines(901, 1), null, null,
                                     'Prueba') ->> 'number' $$),
  'PNO-0001', 'cada local tiene su propia numeración');
select is(pg_temp.msg(pg_temp.u(408), $$
  select purchasing.save_order_draft(null, pg_temp.u(204), pg_temp.u(901), pg_temp.lines(901, 1), null, null,
                                     'Prueba') $$),
  'Falta el código del local: cargalo en el Panel de control para poder numerar las órdenes de compra.',
  'P3: un local sin código no puede pedir');
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(202), pg_temp.u(901), pg_temp.lines(901, 1), null, null,
                                     'Prueba') ->> 'result' $$),
  'denied', 'la Cocinera no pide para otro local');

-- ---------------------------------------------------------------------------
-- Fecha de entrega esperada (Frigorífico: martes, jueves y sábado)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.expected_delivery(pg_temp.u(902), '2026-11-17')::text $$), '2026-11-19',
          'pedido el mismo día de entrega (martes): va al próximo, el jueves');
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.expected_delivery(pg_temp.u(902), '2026-11-16')::text $$), '2026-11-17',
          'pedido el lunes: llega el martes');
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.expected_delivery(pg_temp.u(902), '2026-11-21')::text $$), '2026-11-24',
          'pedido el sábado: pasa el fin de semana y llega el martes');
update purchasing.supplier_terms set delivery_days = '{}' where supplier_id = pg_temp.u(905);
select is(pg_temp.msg(pg_temp.u(409), $$ select purchasing.expected_delivery(pg_temp.u(905), current_date) $$),
  'Cargá los días de entrega del proveedor en su ficha: sin eso no se puede calcular cuándo llega.',
  'un proveedor sin días de entrega da un error claro');

-- ---------------------------------------------------------------------------
-- Ranking
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$
  select times_ordered::text from purchasing.supplier_product_ranking(pg_temp.u(903), pg_temp.u(201)) limit 1 $$),
  '2', 'el artículo de Lácteos que está en las dos OC enviadas va primero');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from purchasing.supplier_product_ranking(pg_temp.u(903), pg_temp.u(202)) $$),
  '0', 'la Cocinera no ve el ranking de otro local');

-- ---------------------------------------------------------------------------
-- No se pide lo que no es del proveedor
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901), pg_temp.lines(902, 1), null, null,
                                     'Prueba') $$),
  'La línea 1 no es un artículo activo de este proveedor.', 'no se pide un artículo de otro proveedor');
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(901),
           jsonb_build_array(jsonb_build_object('ingredient_id', pg_temp.u(819), 'quantity', 500)), null, null,
           'Mozzarella sin nombre de factura') ->> 'result' $$),
  'applied', 'una materia prima que el proveedor no tiene se pide «sin nombre de factura»');

-- ---------------------------------------------------------------------------
-- Aprobación (Frigorífico la requiere)
-- ---------------------------------------------------------------------------
select is((select status::text from purchasing.purchase_orders where number = 'PCE-0002'), 'pending_approval',
          'la OC al Frigorífico espera aprobación');
select ok(exists (select 1 from core.notifications n
                   where n.recipient_user_id = pg_temp.u(408) and n.kind = 'approval_requested'
                     and n.request_id = (select approval_request_id from purchasing.purchase_orders where number = 'PCE-0002')),
          'Compras recibió el aviso para decidirla');
select is(pg_temp.q(pg_temp.u(409), $$
  select workflow.decide_approval((select approval_request_id from purchasing.purchase_orders where number = 'PCE-0002'),
                                  'approved', 'Me la apruebo') ->> 'result' $$),
  'denied', 'quien la pidió no la puede aprobar');
select is(pg_temp.q(pg_temp.u(404), $$
  select workflow.decide_approval((select approval_request_id from purchasing.purchase_orders where number = 'PCE-0002'),
                                  'approved', 'Dale') ->> 'result' $$),
  'denied', 'el Gerente tampoco: la aprueba Compras');
select is(pg_temp.q(pg_temp.u(408), $$
  select workflow.decide_approval((select approval_request_id from purchasing.purchase_orders where number = 'PCE-0002'),
                                  'approved', 'Está bien') ->> 'result' $$),
  'approved', 'Compras la aprueba');
select is((select status::text from purchasing.purchase_orders where number = 'PCE-0002'), 'sent',
          'aprobada, la OC queda enviada');
select ok(exists (select 1 from purchasing.outbound_messages
                   where source_id = pg_temp.order_id('PCE-0002') and status = 'queued' and channel = 'email'),
          'y su mensaje en la cola de envío, por el canal de la ficha');
select ok(exists (select 1 from core.notifications
                   where recipient_user_id = pg_temp.u(409) and kind = 'order_news' and title = 'Se aprobó la orden PCE-0002'),
          'a quien la pidió le llega el aviso');

-- Rechazo: vuelve a borrador.
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.submit_order(pg_temp.order_id('PCE-0001'), 'Mandar') ->> 'result' $$),
  'applied', 'sin aprobación requerida (Verdulería), «Mandar OC» la encola directo');
select is(pg_temp.q(pg_temp.u(409), $$
  select (purchasing.submit_order(
            (purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(902), pg_temp.lines(902, 1), null, null,
                                         'Otra de carne') ->> 'purchase_order_id')::uuid, 'Otra de carne')) ->> 'result' $$),
  'pending_approval', 'otra OC al Frigorífico va a aprobación');
select is(pg_temp.q(pg_temp.u(408), $$
  select workflow.decide_approval((select approval_request_id from purchasing.purchase_orders
                                    where supplier_id = pg_temp.u(902) and status = 'pending_approval'),
                                  'rejected', 'Ya pedimos carne ayer') ->> 'result' $$),
  'rejected', 'Compras la rechaza');
select ok(exists (select 1 from purchasing.purchase_orders o
                   join purchasing.purchase_order_events e on e.purchase_order_id = o.id
                  where o.supplier_id = pg_temp.u(902) and o.status = 'draft' and o.approval_request_id is null
                    and e.message like 'Compras no la aprobó: Ya pedimos carne ayer.%'),
          'rechazada, vuelve a borrador con la novedad');

-- ---------------------------------------------------------------------------
-- Novedades
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from core.notifications
                   where recipient_user_id = pg_temp.u(404) and kind = 'order_news'
                     and title = 'Novedad en la orden PCE-0004'),
          'la novedad del seed le avisó al Gerente, que la pidió');
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.record_order_news(pg_temp.order_id('PCE-0003'), 'note', 'Probando') ->> 'result' $$),
  'denied', 'la Cocinera no registra novedades');
select is(pg_temp.q(pg_temp.u(408), $$
  select purchasing.record_order_news(pg_temp.order_id('PCE-0003'), 'delivery_change', 'Llega el viernes') ->> 'result' $$),
  'applied', 'Compras sí');
select is((select status::text from purchasing.purchase_orders where number = 'PCE-0003'), 'with_news',
          'la OC pasa a «con novedad»');

-- ---------------------------------------------------------------------------
-- Cancelación
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.submit_order(pg_temp.order_id('PCE-0005'), 'Mandar') ->> 'result' $$),
  'applied', 'la Cocinera manda otra');
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.cancel_order(pg_temp.order_id('PCE-0005'), 'Me equivoqué') ->> 'result' $$),
  'applied', 'y la cancela con motivo');
select ok((select status = 'cancelled' from purchasing.outbound_messages where source_id = pg_temp.order_id('PCE-0005')),
          'su mensaje en cola queda cancelado');

-- ---------------------------------------------------------------------------
-- RLS y auditoría
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from purchasing.purchase_orders where restaurant_id <> pg_temp.u(201) $$),
  '0', 'la Cocinera ve solo las OC de su local');
select ok(pg_temp.q(pg_temp.u(408), $$ select count(*)::text from purchasing.purchase_orders where restaurant_id = pg_temp.u(202) $$)::int >= 1,
  'Compras ve las de todo el grupo');
-- El mensaje de una OC enviada de otro local (Pastas Norte).
select is(pg_temp.q(pg_temp.u(411), $$ select purchasing.submit_order(pg_temp.order_id('PNO-0001'), 'Mandar') ->> 'result' $$),
  'applied', 'la Gerente de dos locales manda la OC de Pastas Norte');
select ok(exists (select 1 from purchasing.outbound_messages where source_id = pg_temp.order_id('PNO-0001')),
          'tiene su mensaje en cola');
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from purchasing.outbound_messages where source_id = pg_temp.order_id('PNO-0001') $$),
  '0', 'la Cocinera no ve el mensaje de otro local');
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from purchasing.order_lines(pg_temp.order_id('PNO-0001')) $$),
  '0', 'ni sus líneas');
select is(pg_temp.q(pg_temp.u(409), $$ select count(*)::text from purchasing.order_ingredient_search(pg_temp.u(202), 'muzza') $$),
  '0', 'ni busca materias primas para pedir en otro local');
select ok(not has_column_privilege('authenticated', 'purchasing.purchase_order_lines', 'unit_price', 'select'),
          'el precio de la línea no se lee por la API (protegido por columna)');

-- ---------------------------------------------------------------------------
-- Revisiones (2026-11-16)
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), $$
  select purchasing.save_order_draft(pg_temp.order_id('PCE-0006'), pg_temp.u(201), pg_temp.u(901), pg_temp.lines(901, 1),
                                     null, null, 'Le cambio las líneas') $$),
  'Solo quien armó el borrador lo cambia.', 'nadie cambia el borrador de otra persona');
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.cancel_order(pg_temp.order_id('PCE-0004'), 'No la quiero') ->> 'result' $$),
  'denied', 'la Cocinera no cancela la OC que pidió el Gerente');
-- Retirar la solicitud: la OC vuelve a borrador (no queda trabada).
select is(pg_temp.q(pg_temp.u(409), $$
  select (purchasing.submit_order(
            (purchasing.save_order_draft(null, pg_temp.u(201), pg_temp.u(902), pg_temp.lines(902, 1), null, null,
                                         'Para retirar') ->> 'purchase_order_id')::uuid, 'Para retirar')) ->> 'result' $$),
  'pending_approval', 'una OC más al Frigorífico va a aprobación');
select is(pg_temp.q(pg_temp.u(409), $$
  select workflow.cancel_request((select approval_request_id from purchasing.purchase_orders
                                   where supplier_id = pg_temp.u(902) and status = 'pending_approval'
                                   order by created_at desc limit 1), 'Me arrepentí') ->> 'result' $$),
  'cancelled', 'quien la pidió retira la solicitud');
select ok(exists (select 1 from purchasing.purchase_orders o
                   join purchasing.purchase_order_events e on e.purchase_order_id = o.id
                  where o.supplier_id = pg_temp.u(902) and o.status = 'draft' and o.approval_request_id is null
                    and e.message = 'Se retiró el pedido de aprobación. Volvió a borrador.'),
          'y la OC vuelve a borrador');
-- «Requiere aprobación» no se baja sin Dirección (decisión de Joaco, 2026-11-16).
select throws_ok($$ update purchasing.supplier_terms set requires_po_approval = false where supplier_id = pg_temp.u(902) $$,
  '22023', 'Para que deje de requerir aprobación, lo aprueba Dirección: usá «Pedir que deje de requerir aprobación».',
  'Compras no desmarca «requiere aprobación» directo');
select is(pg_temp.q(pg_temp.u(408), $$
  select purchasing.request_lower_po_approval(pg_temp.u(902), 'Ya no hace falta') ->> 'result' $$),
  'pending_approval', 'pide que deje de requerir aprobación');
select is(pg_temp.q(pg_temp.u(408), $$
  select workflow.decide_approval((select r.id from workflow.approval_requests r
                                     join workflow.approval_workflows w on w.id = r.workflow_id
                                    where w.code = 'purchasing.lower_po_approval' and r.status = 'pending'),
                                  'approved', 'Me lo apruebo') ->> 'result' $$),
  'denied', 'Compras no se lo aprueba');
select is(pg_temp.q(pg_temp.u(402), $$
  select workflow.decide_approval((select r.id from workflow.approval_requests r
                                     join workflow.approval_workflows w on w.id = r.workflow_id
                                    where w.code = 'purchasing.lower_po_approval' and r.status = 'pending'),
                                  'approved', 'Está bien') ->> 'result' $$),
  'approved', 'Dirección lo aprueba');
select ok(not (select requires_po_approval from purchasing.supplier_terms where supplier_id = pg_temp.u(902)),
          'y el proveedor deja de requerir aprobación');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'purchase_orders' and record_id = pg_temp.order_id('PCE-0005') and reason = 'Me equivoqué'),
          'la cancelación queda en la auditoría con su motivo');
select ok((select count(*) = 8 from core.permissions where module = 'purchasing'
             and code in ('purchasing.view_orders', 'purchasing.create_orders', 'purchasing.approve_orders',
                          'purchasing.record_order_news', 'purchasing.view_suppliers', 'purchasing.manage_suppliers',
                          'purchasing.view_price_lists', 'purchasing.manage_price_lists')),
          'los permisos de órdenes de compra existen');

select * from finish();
rollback;
