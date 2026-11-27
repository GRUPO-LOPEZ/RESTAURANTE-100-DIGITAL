-- Orden de pago y cajas y cuentas (PR C de las correcciones de Compras, ADR-0070). Con el seed: en Demo Parrilla Centro
-- (...203, razón social ...1501) hay una factura-remito de Lácteos (...903) con saldo de $ 24.598,99 y una B de la
-- Verdulería (...901) con $ 3.969,40. Cajas y cuentas de ...1501: caja ...1601, banco ...1602, tarjeta ...1603; la caja
-- ...1604 es de otra razón social (...1502). Personas: ...0401 superadmin (org.manage), ...0404 gerente (...201),
-- ...0407 controller, ...0408 compras (paga), ...0409 cocinero, ...0410 auditor.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(46);

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
    v := 'ERROR ' || sqlstate || ' ' || sqlerrm;
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
create temp table k (name text primary key, id uuid);
grant all on k to authenticated;
create function pg_temp.k(p_name text) returns uuid language sql as $$ select id from k where name = p_name $$;

insert into k
select 'lacteos_inv', b.invoice_id from reporting.v_invoice_balances b
 where b.restaurant_id = pg_temp.u(203) and b.supplier_id = pg_temp.u(903) and b.status = 'released';
insert into k
select 'verdu_inv', b.invoice_id from reporting.v_invoice_balances b
 where b.restaurant_id = pg_temp.u(203) and b.supplier_id = pg_temp.u(901) and b.status = 'released';
insert into k
select 'lacteos_cta', a.id from purchasing.supplier_payment_accounts a
 where a.supplier_id = pg_temp.u(903) and a.method = 'transfer' and a.is_active and a.deleted_at is null;

-- Una orden de pago con la sesión de una persona: medios y aplicaciones en JSON.
create function pg_temp.op(p_user int, p_supplier int, p_lines jsonb, p_alloc jsonb, p_key text default 'result')
returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select purchasing.register_payment_order(%L, %L, %L, null, %L::jsonb, %L::jsonb, %L, %L) ->> %L',
    pg_temp.u(203), pg_temp.u(p_supplier), recipes.today(), p_lines, p_alloc, 'Pago de prueba', 'Pago de prueba',
    p_key))
$$;
create function pg_temp.op_msg(p_user int, p_supplier int, p_lines jsonb, p_alloc jsonb)
returns text language sql as $$
  select pg_temp.msg(pg_temp.u(p_user), format(
    'select purchasing.register_payment_order(%L, %L, %L, null, %L::jsonb, %L::jsonb, null, %L)',
    pg_temp.u(203), pg_temp.u(p_supplier), recipes.today(), p_lines, p_alloc, 'Pago de prueba'))
$$;

-- ---------------------------------------------------------------------------
-- Cajas y cuentas
-- ---------------------------------------------------------------------------
select ok(to_regclass('org.legal_entity_accounts') is not null
          and not has_table_privilege('authenticated', 'org.legal_entity_accounts', 'insert'),
          'la tabla existe y la app no escribe directo');
select is(pg_temp.q(pg_temp.u(408), format('select count(*) from org.legal_entity_accounts where legal_entity_id = %L',
                                           pg_temp.u(1501))), '3', 'quien paga ve las cajas y cuentas de su razón social');
select is(pg_temp.q(pg_temp.u(409), 'select count(*) from org.legal_entity_accounts'), '0', 'el cocinero no ve ninguna');
select is(pg_temp.q(pg_temp.u(401), 'select count(*) from org.legal_entity_accounts'), '4',
          'quien administra el grupo (org.manage) ve todas');
select is(pg_temp.q(pg_temp.u(408), format($s$select org.save_legal_entity_accounts(%L,
            '[{"kind":"cash","name":"Caja nueva"}]'::jsonb, 'Prueba') ->> 'result'$s$, pg_temp.u(1501))),
          'denied', 'Compras no carga cajas ni cuentas: las carga quien administra el grupo');
select is(pg_temp.q(pg_temp.u(401), format($s$select org.save_legal_entity_accounts(%L,
            '[{"kind":"bank","name":"Banco Dos","bank":"Banco Dos (ficticio)","cbu":"0000003100099999999999"}]'::jsonb,
            'Cuenta nueva del grupo') ->> 'result'$s$, pg_temp.u(1501))),
          'applied', 'el Superadministrador (org.manage) agrega una cuenta bancaria');
select ok(exists (select 1 from audit.audit_events e
                   where e.table_name = 'legal_entity_accounts' and e.action = 'insert' and e.reason = 'Cuenta nueva del grupo'),
          'y queda en la auditoría con su motivo');
select is(pg_temp.msg(pg_temp.u(401), format($s$select org.save_legal_entity_accounts(%L,
            '[{"kind":"bank","name":"Banco Tres"}]'::jsonb, 'Prueba')$s$, pg_temp.u(1501))),
          'Una cuenta bancaria lleva el banco y el CBU o el número; una tarjeta, sus últimos 4 números; una caja, solo el nombre.',
          'una cuenta bancaria sin banco ni CBU no se guarda');

-- ---------------------------------------------------------------------------
-- La orden de pago
-- ---------------------------------------------------------------------------
-- Lácteos: transferencia de $ 20.000 + cheque propio de $ 10.000, que cancelan la factura-remito ($ 24.598,99) y dejan
-- $ 5.401,01 a cuenta.
insert into k
select 'op1', (pg_temp.op(408, 903, jsonb_build_array(
    jsonb_build_object('method', 'transfer', 'company_account_id', pg_temp.u(1602),
                       'supplier_account_id', pg_temp.k('lacteos_cta'), 'amount', 20000, 'reference', 'TR-1'),
    jsonb_build_object('method', 'check', 'company_account_id', pg_temp.u(1602), 'amount', 10000,
                       'check_number', '00012345', 'check_bank', 'Banco Demo (ficticio)',
                       'check_due_on', (recipes.today() + 30)::text)),
  jsonb_build_array(jsonb_build_object('invoice_id', pg_temp.k('lacteos_inv'), 'amount', 24598.99)),
  'payment_order_id'))::uuid;
select ok(pg_temp.k('op1') is not null, 'Compras registra una orden de pago con transferencia y cheque');
select is((select number from purchasing.payment_orders where id = pg_temp.k('op1')), 'OP-0001',
          'con el primer número de su razón social');
select is((select total_amount from purchasing.payment_orders where id = pg_temp.k('op1')), 30000.0000,
          'el total es la suma de los medios');
select is((select count(*)::int from purchasing.payments where payment_order_id = pg_temp.k('op1')), 2,
          'cada medio es un pago de la orden');
select is((select status::text from purchasing.invoices where id = pg_temp.k('lacteos_inv')), 'paid',
          'la factura queda pagada');
select is((select round(sum(purchasing.payment_unapplied(p.id)), 2) from purchasing.payments p
            where p.payment_order_id = pg_temp.k('op1')), 5401.01, 'y lo que sobra queda a cuenta');
select is((select (check_number, check_bank, check_due_on is not null)::text from purchasing.payments
            where payment_order_id = pg_temp.k('op1') and method = 'check'),
          '(00012345,"Banco Demo (ficticio)",t)', 'el cheque guarda número, banco y fecha de cobro');

-- La Verdulería, en efectivo de la caja: el número siguiente de la misma razón social.
insert into k
select 'op2', (pg_temp.op(408, 901, jsonb_build_array(
    jsonb_build_object('method', 'cash', 'company_account_id', pg_temp.u(1601), 'amount', 3969.40)),
  jsonb_build_array(jsonb_build_object('invoice_id', pg_temp.k('verdu_inv'), 'amount', 3969.40)),
  'payment_order_id'))::uuid;
select is((select number from purchasing.payment_orders where id = pg_temp.k('op2')), 'OP-0002',
          'la siguiente de la misma razón social, sin saltos');

-- Lo que no se puede.
select is(pg_temp.op_msg(408, 903, jsonb_build_array(jsonb_build_object('method', 'check',
            'company_account_id', pg_temp.u(1602), 'amount', 100)), '[]'::jsonb),
          'Un cheque lleva número, banco y fecha de cobro; uno de terceros, además, quién lo libró.',
          'un cheque sin sus datos no se registra');
select is(pg_temp.op_msg(408, 903, jsonb_build_array(jsonb_build_object('method', 'check', 'check_third_party', true,
            'amount', 100, 'check_number', '1', 'check_bank', 'Banco X', 'check_due_on', recipes.today()::text)),
            '[]'::jsonb),
          'Un cheque lleva número, banco y fecha de cobro; uno de terceros, además, quién lo libró.',
          'uno de terceros sin quién lo libró, tampoco');
select is(pg_temp.op(408, 903, jsonb_build_array(jsonb_build_object('method', 'check', 'check_third_party', true,
            'amount', 100, 'check_number', '777', 'check_bank', 'Banco X', 'check_due_on', recipes.today()::text,
            'check_drawer_name', 'Cliente Demo', 'check_drawer_tax_id', '30500000011')), '[]'::jsonb),
          'applied', 'un cheque de terceros completo, sin caja propia (no sale de una cuenta nuestra), sí');
select is(pg_temp.op_msg(408, 903, jsonb_build_array(jsonb_build_object('method', 'cash',
            'company_account_id', pg_temp.u(1604), 'amount', 100)), '[]'::jsonb),
          'Elegí de qué caja o cuenta de Demo Gastronomía S.R.L. (ficticia) sale el pago.',
          'una caja de otra razón social no sirve');
select is(pg_temp.op_msg(408, 903, jsonb_build_array(jsonb_build_object('method', 'transfer',
            'company_account_id', pg_temp.u(1601), 'supplier_account_id', pg_temp.k('lacteos_cta'), 'amount', 100)),
            '[]'::jsonb),
          'El efectivo sale de una caja; la transferencia, el cheque y el e-cheq, de una cuenta bancaria; la tarjeta, de una tarjeta.',
          'una transferencia no sale de una caja');
select is(pg_temp.op_msg(408, 903, jsonb_build_array(jsonb_build_object('method', 'transfer',
            'company_account_id', pg_temp.u(1602), 'amount', 100)), '[]'::jsonb),
          'Elegí la cuenta del proveedor a la que va la transferencia.', 'una transferencia sin la cuenta del proveedor, no');
-- Revisión de seguridad: paga la razón social del local y nadie más; el cheque de terceros no lleva caja propia.
select is(pg_temp.msg(pg_temp.u(408), format(
            'select purchasing.register_payment_order(%L, %L, %L, %L, %L::jsonb, %L::jsonb, null, %L)',
            pg_temp.u(203), pg_temp.u(903), recipes.today(), pg_temp.u(1502),
            jsonb_build_array(jsonb_build_object('method', 'check', 'check_third_party', true, 'amount', 100,
              'check_number', '9', 'check_bank', 'Banco X', 'check_due_on', recipes.today()::text,
              'check_drawer_name', 'Cliente Demo')), '[]', 'Pago de prueba')),
          'Se paga con la razón social del local (Demo Gastronomía S.R.L. (ficticia)).',
          'no se puede emitir una orden a nombre de otra razón social del grupo');
select is(pg_temp.op_msg(408, 903, jsonb_build_array(jsonb_build_object('method', 'check', 'check_third_party', true,
            'company_account_id', pg_temp.u(1604), 'amount', 100, 'check_number', '9', 'check_bank', 'Banco X',
            'check_due_on', recipes.today()::text, 'check_drawer_name', 'Cliente Demo')), '[]'::jsonb),
          'Un cheque de terceros no sale de una caja ni de una cuenta propia.',
          'un cheque de terceros no guarda una caja (y menos de otra razón social)');
select ok(exists (select 1 from pg_constraint where conname = 'payments_company_account_fkey'
                   and conrelid = 'purchasing.payments'::regclass and array_length(conkey, 1) = 2),
          'la caja o cuenta del pago es del mismo grupo (clave foránea por grupo)');
select is(pg_temp.q(pg_temp.u(409), format(
            'select purchasing.invoice_status_matches(%L, %L, null, null, %L, %L)::text',
            pg_temp.k('verdu_inv'), 'released', '2000-01-01', 'overdue')),
          'false', '«vencidas» no deja saber el saldo de una factura que la sesión no ve');
select is(pg_temp.op(409, 903, jsonb_build_array(jsonb_build_object('method', 'cash',
            'company_account_id', pg_temp.u(1601), 'amount', 100)), '[]'::jsonb),
          'denied', 'el cocinero no paga');
select throws_ok(format('update purchasing.payment_orders set withholding_vat = 10 where id = %L', pg_temp.k('op1')),
                 '23514', 'Una orden de pago registrada no cambia: se anula y se hace otra.',
                 'una orden registrada no cambia (tampoco las retenciones)');
select is((select (withholding_income_tax + withholding_vat + withholding_gross_income)::text
             from purchasing.payment_orders where id = pg_temp.k('op1')), '0.0000',
          'las retenciones tienen su lugar, en 0');

-- ---------------------------------------------------------------------------
-- La ficha y el listado
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(407), format($s$select jsonb_path_query_first(purchasing.payment_order_detail(%L), '$.lines[*] ? (@.method == "transfer").to.alias') #>> '{}'$s$,
                                           pg_temp.k('op1'))),
          'lacteos.demo', 'quien ve la condición de pago ve la cuenta del proveedor completa');
select is(pg_temp.q(pg_temp.u(410), format($s$select jsonb_path_query_first(purchasing.payment_order_detail(%L), '$.lines[*] ? (@.method == "transfer").to.alias') #>> '{}'$s$,
                                           pg_temp.k('op1'))),
          null, 'el auditor ve la orden, pero no el alias ni el CBU del proveedor');
select is(pg_temp.q(pg_temp.u(408), format($s$select purchasing.payment_order_detail(%L) ->> 'payer'$s$, pg_temp.k('op1'))),
          '{"name": "Demo Gastronomía S.R.L. (ficticia)", "tax_id": "30000000007"}', 'con quién paga y su CUIT');
select is(pg_temp.q(pg_temp.u(404), format('select purchasing.payment_order_detail(%L)::text', pg_temp.k('op1'))),
          null, 'el gerente de otro local no la ve');
select is(pg_temp.q(pg_temp.u(408), 'select sum(total) from purchasing.payment_order_supplier_counts()'),
          pg_temp.q(pg_temp.u(408), 'select max(total)::text from purchasing.payment_order_list(p_limit => 1)'),
          'el conteo por proveedor coincide con el listado');

-- La tabla, por rol (RLS): quien ve pagos en el local, sí; el cocinero y el gerente de otro local, no.
select ok(pg_temp.q(pg_temp.u(410), 'select count(*) from purchasing.payment_orders')::int >= 2,
          'el auditor ve las órdenes de pago');
select is(pg_temp.q(pg_temp.u(409), 'select count(*) from purchasing.payment_orders'), '0',
          'el cocinero no ve ninguna');
select is(pg_temp.q(pg_temp.u(404), format('select count(*) from purchasing.payment_orders where restaurant_id = %L',
                                           pg_temp.u(203))), '0',
          'el gerente de otro local no ve las de Parrilla Centro');
select ok(exists (select 1 from audit.audit_events e
                   where e.table_name = 'payment_orders' and e.record_id = pg_temp.k('op1')
                     and e.action = 'insert' and e.reason = 'Pago de prueba'),
          'la orden queda en la auditoría, con su motivo');

-- ---------------------------------------------------------------------------
-- Anular
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.void_payment(%L, %L)',
            (select id from purchasing.payments where payment_order_id = pg_temp.k('op2') limit 1), 'Un medio solo')),
          'Este pago es parte de la orden OP-0002: anulá la orden entera.',
          'un medio de una orden no se anula suelto');
select is(pg_temp.q(pg_temp.u(409), format('select purchasing.void_payment_order(%L, %L) ->> %L', pg_temp.k('op2'),
                                           'Sin permiso', 'result')),
          'denied', 'el cocinero no anula una orden');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.void_payment_order(%L, %L) ->> %L', pg_temp.k('op1'),
                                           'Se cargó con el importe equivocado', 'status')),
          'voided', 'Compras anula la orden con motivo');
select ok((select status::text from purchasing.invoices where id = pg_temp.k('lacteos_inv')) = 'released'
          and purchasing.invoice_balance(pg_temp.k('lacteos_inv')) > 24000,
          'la factura vuelve a tener su saldo');
select is((select count(*)::int from purchasing.payments where payment_order_id = pg_temp.k('op1') and status = 'voided'),
          2, 'y sus medios quedan anulados (no se borran)');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.void_payment_order(%L, %L)', pg_temp.k('op1'), 'Otra vez')),
          'Esta orden de pago ya está anulada.', 'no se anula dos veces');

select is(pg_temp.msg(pg_temp.u(401), format($s$select org.save_legal_entity_accounts(%L, '[{"remove": true}]', 'Baja')$s$,
                                             pg_temp.u(1501))),
          'Para dar de baja, elegí cuál.', 'una baja sin decir cuál no crea nada');
select ok(not has_function_privilege('anon', 'purchasing.register_payment_order(uuid, uuid, date, uuid, jsonb, jsonb, text, text)', 'execute')
          and not has_function_privilege('anon', 'purchasing.payment_order_detail(uuid)', 'execute')
          and not has_function_privilege('anon', 'org.save_legal_entity_accounts(uuid, jsonb, text)', 'execute')
          and not has_function_privilege('authenticated', 'purchasing.next_payment_order_number(uuid, uuid)', 'execute'),
          'anon no paga ni lee, y el número no se pide desde la app');

select * from finish();
rollback;
