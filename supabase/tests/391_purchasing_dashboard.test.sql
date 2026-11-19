-- Fase 3, Prompt 6 (ADR-0060): el tablero de compras, la cuenta corriente y la agenda (lecturas), con el seed; y el caso
-- 34: con 500 facturas y 5.000 líneas, cada lectura del tablero por debajo de 300 ms.
-- Personas del seed: ...0405 chef ejecutivo (marca ...101), ...0407 controller, ...0408 compras, ...0409 cocinero.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(16);

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
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.board(p_user int, p_key text, p_local int default 203) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select purchasing.purchasing_dashboard(%L) ->> %L', pg_temp.u(p_local), p_key))
$$;
-- Cuánto tarda una lectura, en milisegundos, con la sesión de una persona.
create function pg_temp.ms(p_user int, p_sql text) returns numeric language plpgsql as $$
declare
  v_start timestamptz;
  v_end   timestamptz;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(p_user), 'role', 'authenticated',
                                                             'aal', 'aal2')::text, true);
  set local role authenticated;
  execute p_sql;  -- La primera, para que los permisos de la sesión queden calculados.
  v_start := clock_timestamp();
  execute p_sql;
  v_end := clock_timestamp();
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return extract(epoch from v_end - v_start) * 1000;
end
$$;

-- ---------------------------------------------------------------------------
-- El tablero con el seed
-- ---------------------------------------------------------------------------
select is(pg_temp.board(408, 'can_see_amounts'), 'true', 'Compras ve los importes');
select is(pg_temp.board(408, 'observed'), '2', 'facturas observadas de Demo Parrilla Centro');
select ok((pg_temp.board(408, 'due_week'))::int >= 1, 'lo que vence esta semana (la factura-remito, en 3 días)');
select ok((pg_temp.board(408, 'due_week_amount'))::numeric > 0, 'con su importe');
select ok(pg_temp.board(408, 'alerts')::jsonb @> '[{"kind": "invoice_observed"}]'::jsonb
          and pg_temp.board(408, 'alerts')::jsonb @> '[{"kind": "payment_overdue"}]'::jsonb
          and pg_temp.board(408, 'alerts')::jsonb @> '[{"kind": "cash_to_confirm"}]'::jsonb,
          'alarmas: factura observada, pago vencido y efectivo para confirmar');
select is((pg_temp.board(408, 'alerts')::jsonb -> 0 ->> 'severity'), 'bad', 'primero lo más grave');
select ok(jsonb_array_length(pg_temp.board(408, 'spend')::jsonb) >= 1, 'el gasto del mes por rubro');
select ok(pg_temp.board(408, 'next_payments')::jsonb -> 0 ->> 'balance' is not null, 'los próximos pagos, con su saldo');

-- El chef ejecutivo ve el tablero de su marca sin importes; el cocinero no lo ve.
select is(pg_temp.board(405, 'can_see_amounts', 201), 'false', 'el chef ve el tablero sin importes');
select is(pg_temp.board(405, 'spend', 201), null, 'sin el gasto en pesos');
select ok(not (coalesce(pg_temp.board(405, 'alerts', 201), '[]')::jsonb @> '[{"kind": "payment_due"}]'::jsonb),
          'ni las alarmas de plata');
select is(pg_temp.q(pg_temp.u(409), 'select purchasing.purchasing_dashboard()::text'), null, 'el cocinero no ve el tablero');

-- La cuenta corriente de Lácteos en Demo Parrilla Centro: lo facturado menos notas y pagos.
select is(pg_temp.q(pg_temp.u(408), format('select (purchasing.supplier_account(%L, %L) ->> %L)::numeric',
                                           pg_temp.u(903), pg_temp.u(203), 'balance')),
          (select (sum(b.balance_amount) - coalesce((select sum(purchasing.payment_unapplied(p.id))
                                                       from purchasing.payments p
                                                      where p.supplier_id = pg_temp.u(903)
                                                        and p.restaurant_id = pg_temp.u(203)
                                                        and p.status in ('registered', 'receipt_queued')), 0))::text
             from reporting.v_invoice_balances b
            where b.supplier_id = pg_temp.u(903) and b.restaurant_id = pg_temp.u(203)),
          'la cuenta corriente: saldo de las facturas menos lo que quedó a cuenta');
select is(pg_temp.q(pg_temp.u(409), format('select purchasing.supplier_account(%L)::text', pg_temp.u(903))), null,
          'el cocinero no ve la cuenta corriente');

-- ---------------------------------------------------------------------------
-- Caso 34: 500 facturas y 5.000 líneas, cada lectura por debajo de 300 ms
-- ---------------------------------------------------------------------------
alter table purchasing.invoices disable trigger guard_invoice;
insert into purchasing.invoices (id, group_id, brand_id, restaurant_id, supplier_id, invoice_class, number, issued_on,
                                 due_on, due_on_source, net_amount, total_amount, status, loaded_by, approved_by,
                                 approved_at)
select gen_random_uuid(), r.group_id, r.brand_id, r.id, pg_temp.u(906), 'non_fiscal', 500000 + n,
       recipes.today() - (n % 120), recipes.today() - (n % 120) + 15, 'terms', 10000, 10000,
       (array['released', 'released', 'paid', 'observed'])[1 + n % 4]::purchasing.invoice_status,
       pg_temp.u(408), case when n % 4 <> 3 then pg_temp.u(407) end, case when n % 4 <> 3 then now() end
  from generate_series(1, 500) n
  join org.restaurants r on r.id = pg_temp.u(203);
alter table purchasing.invoices enable trigger guard_invoice;
alter table purchasing.invoice_lines disable trigger guard_invoice_part;
insert into purchasing.invoice_lines (group_id, invoice_id, line_order, purchase_product_id, raw_name, billed_quantity,
                                      unit_price, line_amount)
select i.group_id, i.id, k, (select id from catalog.purchase_products where supplier_id = pg_temp.u(906) limit 1),
       'Línea de rendimiento', 1, 1000, 1000
  from purchasing.invoices i cross join generate_series(1, 10) k
 where i.number > 500000;
alter table purchasing.invoice_lines enable trigger guard_invoice_part;

select ok(pg_temp.ms(408, format('select purchasing.purchasing_dashboard(%L)', pg_temp.u(203))) < 300,
          'caso 34: el tablero de un local, por debajo de 300 ms');
select ok(pg_temp.ms(408, format('select * from purchasing.payment_schedule_list(%L)', 'due')) < 300,
          'caso 34: la agenda, por debajo de 300 ms');

select * from finish();
rollback;
