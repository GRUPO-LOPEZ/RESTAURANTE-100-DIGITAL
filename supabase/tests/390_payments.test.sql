-- Fase 3, Prompt 6 (ADR-0060): pagos, saldo de las facturas, efectivo al recibir, anular, agenda, avisos, RLS y Storage.
-- Personas del seed: ...0404 gerente (local ...201), ...0407 controller, ...0408 compras, ...0409 cocinero.
-- Local ...203 Demo Parrilla Centro; proveedores ...0901 Verdulería y ...0903 Lácteos.
-- Seed: la B 1234 de la Verdulería ($ 5.969,40) con un pago parcial de $ 2.000 (vencida); la factura-remito 4567 de
-- Lácteos con $ 5.000 pagados (vence en 3 días); la A 4600 de Lácteos pagada entera; el efectivo de la recepción de
-- Lácteos ($ 15.000) para confirmar.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(61);
-- La fecha de la Argentina (la que usa la base), para las consultas que corren con la sesión de una persona.
select set_config('test.today', recipes.today()::text, true);

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
create function pg_temp.inv(p_number bigint) returns uuid language sql as $$
  select id from purchasing.invoices where number = p_number
$$;
create function pg_temp.balance(p_number bigint) returns numeric language sql as $$
  select purchasing.invoice_balance(pg_temp.inv(p_number))
$$;
create function pg_temp.status(p_number bigint) returns text language sql as $$
  select status::text from purchasing.invoices where number = p_number
$$;
-- Registra un pago como Compras en Demo Parrilla Centro y devuelve el resultado (o el error).
create function pg_temp.pay(p_supplier int, p_method text, p_amount numeric, p_allocations jsonb,
                            p_user int default 408, p_restaurant int default 203) returns text language sql as $$
  select pg_temp.msg(pg_temp.u(p_user), format(
    'select purchasing.register_payment(%L, %L, current_setting(''test.today'')::date, %L, %L, %s, %L, %L::jsonb, %L)',
    pg_temp.u(p_restaurant), pg_temp.u(p_supplier), p_method,
    case when p_method = 'cash' then null
         else (select id from purchasing.supplier_payment_accounts
                where supplier_id = pg_temp.u(p_supplier) and method = p_method::purchasing.payment_method limit 1) end,
    p_amount, 'TRF-PRUEBA', p_allocations, 'Pago de prueba'))
$$;
create function pg_temp.alloc(p_number bigint, p_amount numeric) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('invoice_id', pg_temp.inv(p_number), 'amount', p_amount))
$$;

-- ---------------------------------------------------------------------------
-- El seed
-- ---------------------------------------------------------------------------
select is(pg_temp.balance(1234), 3969.4000::numeric, 'la B de la Verdulería, con un pago parcial de $ 2.000, tiene saldo');
select is(pg_temp.status(1234), 'released', 'un pago parcial no cambia el estado');
select is(pg_temp.status(4600), 'paid', 'la A de Lácteos, pagada entera, pasó a pagada');
select is((select count(*)::int from purchasing.payment_allocations a join purchasing.payments p on p.id = a.payment_id
            where p.reference = 'TRF-000123'), 2, 'un pago cancela dos facturas');
select is((select payment_amount from purchasing.payments where status = 'to_confirm'), 15000.0000::numeric,
          'el efectivo pagado al recibir quedó para confirmar (lo creó la recepción)');
select is((select p.status::text || ' ' || m.status::text
             from purchasing.payments p join purchasing.outbound_messages m on m.source_table = 'payments' and m.source_id = p.id
            where p.reference = 'TRF-000123'), 'receipt_queued queued',
          'el aviso del pago quedó en cola por el canal de la ficha (decisión 9: nadie lo despacha todavía)');

-- ---------------------------------------------------------------------------
-- Casos 31 y 32: parcial, total, dos facturas, no más que el saldo
-- ---------------------------------------------------------------------------
select is(pg_temp.pay(901, 'cash', 969.40, pg_temp.alloc(1234, 969.40)), 'sin error', 'caso 31: otro pago parcial');
select is(pg_temp.balance(1234), 3000.0000::numeric, 'deja $ 3.000 de saldo');
select is(pg_temp.status(1234), 'released', 'y la factura sigue liberada');
select is(pg_temp.pay(901, 'cash', 3000, pg_temp.alloc(1234, 3000)), 'sin error', 'caso 31: el pago del saldo');
select is(pg_temp.status(1234), 'paid', 'la factura pasa a pagada en la misma transacción');
select is(pg_temp.pay(903, 'transfer', 30000, pg_temp.alloc(4567, 24598.99 + 1)),
          'No se puede aplicar más que el saldo de la factura.', 'caso 32: no se aplica más que el saldo');
select is(pg_temp.pay(903, 'transfer', 100, pg_temp.alloc(4567, 200)), 'Lo aplicado no puede superar el pago.',
          'ni más que el pago');
select is(pg_temp.pay(903, 'transfer', 1000, '[]'::jsonb), 'sin error', 'lo que no se aplica queda a cuenta');
select is((select purchasing.payment_unapplied(p.id) from purchasing.payments p
            where p.payment_amount = 1000 and p.supplier_id = pg_temp.u(903)), 1000.0000::numeric, 'a cuenta: $ 1.000');

-- ---------------------------------------------------------------------------
-- Reglas: local, permiso, motivo, fecha, cuenta
-- ---------------------------------------------------------------------------
select is(pg_temp.pay(903, 'transfer', 100, pg_temp.alloc(4567, 100), 408, 202),
          'El pago y la factura tienen que ser del mismo local y proveedor.', 'un pago es de un local');
select is(pg_temp.q(pg_temp.u(407), format(
            'select purchasing.register_payment(%L, %L, current_setting(''test.today'')::date, %L, null, 10, null, %L::jsonb, %L) ->> %L',
            pg_temp.u(203), pg_temp.u(901), 'cash', '[]', 'Prueba', 'result')),
          'denied', 'el Controller no registra pagos');
select is(pg_temp.msg(pg_temp.u(408), format(
            'select purchasing.register_payment(%L, %L, current_setting(''test.today'')::date + 1, %L, null, 10, null, %L::jsonb, %L)',
            pg_temp.u(203), pg_temp.u(901), 'cash', '[]', 'Prueba')),
          'La fecha del pago no puede ser posterior a hoy.', 'sin fecha futura');
select is(pg_temp.msg(pg_temp.u(408), format(
            'select purchasing.register_payment(%L, %L, current_setting(''test.today'')::date, %L, null, 10, null, %L::jsonb, %L)',
            pg_temp.u(203), pg_temp.u(903), 'transfer', '[]', 'Prueba')),
          'Elegí una cuenta activa del proveedor para ese medio de pago.', 'una transferencia va a una cuenta del proveedor');
select is(pg_temp.msg(pg_temp.u(408), format(
            'select purchasing.register_payment(%L, %L, current_setting(''test.today'')::date, %L, null, 10, null, %L::jsonb, %L)',
            pg_temp.u(203), pg_temp.u(901), 'cash', '[]', ' ')),
          'Escribí el motivo del pago.', 'con motivo');

-- ---------------------------------------------------------------------------
-- Notas en el saldo
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.add_credit_debit_note(%L, %L::jsonb, %L)',
            pg_temp.inv(4567), jsonb_build_object('note_kind', 'debit', 'issued_on', recipes.today(), 'net_amount', 100),
            'Flete facturado aparte')), 'sin error', 'una nota de débito');
select is(pg_temp.balance(4567), 24698.9900::numeric, 'suma al saldo (y una de crédito resta: la A de Lácteos)');

-- ---------------------------------------------------------------------------
-- El efectivo al recibir: para confirmar → a cuenta → aplicado a su factura liberada
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.confirm_cash_payment(%L, %s, %L) ->> %L',
            (select id from purchasing.payments where status = 'to_confirm'), 15000, 'Lo pagó el encargado', 'unapplied')),
          '0.00', 'confirmado, se aplica a la factura-remito de esa recepción (ya liberada)');
select is(pg_temp.balance(4567), 9698.9900::numeric, 'y baja su saldo en $ 15.000');

-- ---------------------------------------------------------------------------
-- Anular
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.void_payment(%L, %L) ->> %L',
            (select p.id from purchasing.payments p join purchasing.payment_allocations a on a.payment_id = p.id
              where a.invoice_id = pg_temp.inv(1234) and a.allocated_amount = 3000), 'Se cargó dos veces', 'status')),
          'voided', 'un pago se anula, con motivo');
select is(pg_temp.status(1234) || ' ' || pg_temp.balance(1234), 'released 3000.0000',
          'la factura vuelve a liberada con su saldo');
-- Ni siquiera el dueño de la base: lo frena el trigger (las personas ni pueden escribir la tabla).
select throws_ok($$update purchasing.payments set payment_amount = 1 where reference = 'TRF-000123'$$, '42501',
                 'Un pago registrado no cambia: anulalo, con motivo, y registralo de nuevo.', 'un pago registrado no cambia');

-- ---------------------------------------------------------------------------
-- Agenda (bordes) y avisos (una sola vez)
-- ---------------------------------------------------------------------------
alter table purchasing.invoices disable trigger guard_invoice;
update purchasing.invoices set due_on = recipes.today() where number = 4567;
select is((select due_state from reporting.v_payment_schedule where invoice_id = pg_temp.inv(4567)), 'warn',
          'vence hoy: por vencer, no vencida');
update purchasing.invoices set due_on = recipes.today() - 1 where number = 4567;
select is((select due_state from reporting.v_payment_schedule where invoice_id = pg_temp.inv(4567)), 'bad',
          'venció ayer: vencida');
update purchasing.invoices set due_on = recipes.today() + 7 where number = 4567;
select is((select due_state from reporting.v_payment_schedule where invoice_id = pg_temp.inv(4567)), 'warn',
          'a 7 días exactos: por vencer');
alter table purchasing.invoices enable trigger guard_invoice;
select ok(purchasing.notify_due_payments() >= 1, 'avisa las facturas por vencer o vencidas');
select is(purchasing.notify_due_payments(), 0, 'una sola vez por factura');

-- ---------------------------------------------------------------------------
-- Revisión: la nota que llega después de pagar, aplicar lo que quedó a cuenta, renglones y estados
-- ---------------------------------------------------------------------------
-- La A de Lácteos (4600) está pagada entera: una nota de crédito tardía la deja pagada y lo de más vuelve a cuenta.
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.add_credit_debit_note(%L, %L::jsonb, %L)',
            pg_temp.inv(4600), jsonb_build_object('note_kind', 'credit', 'issued_on', current_setting('test.today'),
                                                  'net_amount', 300), 'Bonificación que llegó tarde')), 'sin error',
          'una nota de crédito entra también a una factura pagada');
select is(pg_temp.status(4600) || ' ' || pg_temp.balance(4600), 'paid 0.0000', 'queda pagada, sin saldo negativo');
select is((select purchasing.payment_unapplied(id) from purchasing.payments where reference = 'TRF-000123'),
          300.0000::numeric, 'y lo pagado de más vuelve a quedar a cuenta del pago');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.add_credit_debit_note(%L, %L::jsonb, %L)',
            pg_temp.inv(4600), jsonb_build_object('note_kind', 'debit', 'issued_on', current_setting('test.today'),
                                                  'net_amount', 50), 'Flete que faltaba')) || ' ' || pg_temp.status(4600),
          'sin error released', 'una nota de débito sobre una pagada la vuelve a liberada, con su saldo');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.apply_payment_credit(%L, %L::jsonb, %L) ->> %L',
            (select id from purchasing.payments where reference = 'TRF-000123'), pg_temp.alloc(4600, 50),
            'Lo que quedó a cuenta', 'unapplied')),
          '250.00', 'lo que quedó a cuenta se aplica a otra factura liberada');
select is(pg_temp.status(4600), 'paid', 'y la deja pagada');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.apply_payment_credit(%L, %L::jsonb, %L)',
            (select id from purchasing.payments where reference = 'TRF-000123'),
            '[{"invoice_id": "no-es-un-id", "amount": 1}]', 'Prueba')),
          'Una de las facturas a pagar no se entiende.', 'un renglón mal escrito se explica en español');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.apply_payment_credit(%L, %L::jsonb, %L)',
            (select id from purchasing.payments where reference = 'TRF-000123'),
            jsonb_build_array(jsonb_build_object('invoice_id', pg_temp.inv(4567))), 'Prueba')),
          'Escribí cuánto se paga de cada factura (mayor que cero).', 'un renglón sin monto, también');
select throws_ok($$update purchasing.invoices set status = 'released' where number = 4600$$, '42501',
                 'Una factura conforme no cambia: corregila con una nota de crédito o débito.',
                 'una pagada sin saldo no vuelve a liberada');

-- El efectivo confirmado ANTES de que se libere su factura se aplica al liberarla (trigger on_invoice_released).
alter table purchasing.invoices disable trigger guard_invoice;
update purchasing.invoices set status = 'approved' where number = 4567;
alter table purchasing.invoices enable trigger guard_invoice;
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.register_payment(%L, %L, %L, %L, null, 1000, null, null, %L) ->> %L',
            pg_temp.u(203), pg_temp.u(903), current_setting('test.today'), 'cash', 'Prueba', 'result')),
          'applied', 'un pago en efectivo a cuenta de Lácteos');
select is((select count(*)::int from purchasing.payments where status = 'to_confirm'), 0,
          'confirmar dos veces no se puede: ya no queda efectivo para confirmar');

-- ---------------------------------------------------------------------------
-- Auditoría
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from audit.audit_events e where e.table_name = 'payments' and e.action = 'insert'
                    and e.reason = 'Pago de prueba' and e.source = 'manual'),
          'cada pago queda en el historial, con su motivo y su origen');
select ok(exists (select 1 from audit.audit_events e where e.table_name = 'payment_allocations' and e.action = 'insert'),
          'y cada aplicación también');
select ok(exists (select 1 from audit.audit_events e where e.table_name = 'payments' and e.action = 'update'
                    and e.reason = 'Se cargó dos veces'),
          'anular queda con su motivo');

-- ---------------------------------------------------------------------------
-- RLS y Storage
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format('insert into purchasing.payments (group_id, brand_id, restaurant_id, supplier_id, paid_on, method, payment_amount) select group_id, brand_id, id, %L, current_date, %L, 1 from org.restaurants where id = %L',
            pg_temp.u(901), 'cash', pg_temp.u(203))),
          'permission denied for table payments', 'nadie escribe la tabla directo: solo las funciones');
select is(pg_temp.q(pg_temp.u(409), 'select count(*) from purchasing.payment_allocations'), '0',
          'el cocinero no ve las aplicaciones');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.can_upload_document(%L)',
            format('00000000-0000-4000-8000-000000000001/payments/%s/%s.jpg',
                   (select id from purchasing.payments where reference = 'TRF-000123'), gen_random_uuid()))),
          'true', 'Compras sube el comprobante de un pago');
select is(pg_temp.q(pg_temp.u(404), format('select purchasing.can_upload_document(%L)',
            format('00000000-0000-4000-8000-000000000001/payments/%s/%s.jpg',
                   (select id from purchasing.payments where reference = 'TRF-000123'), gen_random_uuid()))),
          'false', 'el gerente de otro local no');
select is(pg_temp.q(pg_temp.u(409), 'select count(*) from purchasing.payments'), '0', 'el cocinero no ve pagos');
select is(pg_temp.q(pg_temp.u(404), 'select count(*) from purchasing.payments'), '0',
          'el gerente de otro local no ve los pagos de Demo Parrilla Centro');

-- El saldo y los pagos de una factura (la ficha de la factura): la misma cuenta que invoice_balance, solo para quien ve pagos.
select is(pg_temp.q(pg_temp.u(408), format('select (purchasing.invoice_payments(%L) ->> %L)::numeric', pg_temp.inv(1234), 'balance')),
          pg_temp.balance(1234)::text, 'la ficha de la factura lee el saldo de invoice_balance');
select is(pg_temp.q(pg_temp.u(409), format('select purchasing.invoice_payments(%L) is null', pg_temp.inv(1234))), 'true',
          'el cocinero no ve el saldo ni los pagos de la factura');
select is(pg_temp.q(pg_temp.u(404), format('select purchasing.invoice_payments(%L) is null', pg_temp.inv(1234))), 'true',
          'el gerente de otro local tampoco');

-- Revisión de base (migración 170000): los pagos anulados no figuran, una sola cuenta del saldo, el saldo a favor que
-- no se puede devolver y el orden de la cuenta corriente.
-- Con la sesión de Compras: sin sesión, invoice_payments devuelve nulo.
select is(pg_temp.q(pg_temp.u(408), format('select jsonb_array_length(p -> %L) || %L || count(*) filter (where (e ->> %L)::numeric = 3000) from purchasing.invoice_payments(%L) p, jsonb_array_elements(p -> %L) e group by p',
            'payments', ' ', 'allocated', pg_temp.inv(1234), 'payments')), '2 0',
          'la ficha de la factura lista sus 2 pagos vigentes y no el anulado');
select is(pg_temp.q(pg_temp.u(408), format('select jsonb_array_length(purchasing.invoice_payments(%L) -> %L)',
            pg_temp.inv(4600), 'payments')), '1',
          'después de la nota tardía, el pago figura una vez, con lo aplicado vigente');
select is((select count(*)::int from reporting.v_invoice_balances v
            where v.balance_amount is distinct from purchasing.invoice_balance(v.invoice_id)), 0,
          'la vista de la agenda y invoice_balance dan el mismo saldo en todas las facturas');
select throws_ok(format($q$insert into purchasing.credit_debit_notes (group_id, invoice_id, note_kind, issued_on, net_amount,
                                                                     total_amount, reason)
                           select group_id, id, %L, %L::date, total_amount * 10, total_amount * 10, %L
                             from purchasing.invoices where number = 4600$q$,
                         'credit', current_setting('test.today'), 'Prueba de saldo a favor'),
                 '23514',
                 'La nota deja la factura con saldo a favor y no hay pagos para devolver a cuenta: revisá el importe.',
                 'una nota que deja saldo a favor sin pagos que devolver se rechaza');
select is(pg_temp.q(pg_temp.u(408), format('select (a -> %L -> 0 ->> %L)::numeric = (a ->> %L)::numeric from purchasing.supplier_account(%L, %L, 50) a',
            'movements', 'balance', 'balance', pg_temp.u(901), pg_temp.u(203))), 'true',
          'la cuenta corriente: el movimiento de arriba lleva el saldo final (Verdulería)');
select is(pg_temp.q(pg_temp.u(408), format('select (a -> %L -> 0 ->> %L)::numeric = (a ->> %L)::numeric from purchasing.supplier_account(%L, %L, 50) a',
            'movements', 'balance', 'balance', pg_temp.u(903), pg_temp.u(203))), 'true',
          'y también en Lácteos');

select * from finish();
rollback;
