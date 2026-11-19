-- Fase 3, Prompt 6 (ADR-0060): cuenta corriente, agenda de vencimientos, alarmas y tablero de compras.
--
-- Vistas security_invoker en reporting, cerradas para todos (como v_price_list_changes): las leen funciones de
-- purchasing que controlan el permiso adentro y filtran por los locales que la sesión ve. Nada se guarda: todo se calcula
-- de las facturas, las notas y los pagos.

-- ---------------------------------------------------------------------------
-- 1. Vistas
-- ---------------------------------------------------------------------------
-- Cada factura conforme (o liberada o pagada) con lo que suman sus notas y sus pagos, y su saldo.
create view reporting.v_invoice_balances with (security_invoker = true) as
  select i.id as invoice_id, i.group_id, i.restaurant_id, i.supplier_id, i.status, i.invoice_class, i.point_of_sale,
         i.number, i.issued_on, i.due_on, i.total_amount, i.supplier_balance_amount,
         coalesce(n.credit_amount, 0) as credit_amount, coalesce(n.debit_amount, 0) as debit_amount,
         coalesce(p.paid_amount, 0) as paid_amount,
         round(i.total_amount - coalesce(n.credit_amount, 0) + coalesce(n.debit_amount, 0)
               - coalesce(p.paid_amount, 0), 4) as balance_amount
    from purchasing.invoices i
    left join lateral (
      select sum(x.total_amount) filter (where x.note_kind in ('credit', 'discount')) as credit_amount,
             sum(x.total_amount) filter (where x.note_kind = 'debit') as debit_amount
        from purchasing.credit_debit_notes x where x.invoice_id = i.id and x.deleted_at is null) n on true
    left join lateral (
      select sum(a.allocated_amount) as paid_amount
        from purchasing.payment_allocations a join purchasing.payments y on y.id = a.payment_id
       where a.invoice_id = i.id and a.deleted_at is null and y.deleted_at is null and y.status <> 'voided') p on true
   where i.deleted_at is null and i.status in ('approved', 'released', 'paid');
revoke all on reporting.v_invoice_balances from public, anon, authenticated, service_role;
comment on view reporting.v_invoice_balances is
  'Facturas conformes, liberadas o pagadas con sus notas, sus pagos aplicados y su saldo (total − crédito y descuentos + débito − pagos). La leen funciones de purchasing.';

-- La agenda: lo liberado con saldo, cuándo vence y su estado (siempre con palabra en la pantalla).
create view reporting.v_payment_schedule with (security_invoker = true) as
  select b.*, b.due_on - recipes.today() as days_left,
         case when b.due_on < recipes.today() then 'bad'
              when b.due_on <= recipes.today() + 7 then 'warn' else 'ok' end as due_state
    from reporting.v_invoice_balances b
   where b.status = 'released' and b.balance_amount > 0.005;
revoke all on reporting.v_payment_schedule from public, anon, authenticated, service_role;
comment on view reporting.v_payment_schedule is
  'Agenda de vencimientos: facturas liberadas con saldo, días que faltan y estado (ok: al día; warn: vence en 7 días o menos; bad: vencida).';

-- Los movimientos de la cuenta corriente de cada proveedor en cada local, con el saldo acumulado.
create view reporting.v_supplier_account_movements with (security_invoker = true) as
  with moves as (
    select i.group_id, i.restaurant_id, i.supplier_id, i.issued_on as moved_on, i.created_at, 'invoice'::text as kind,
           i.id as source_id, purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number) as label,
           i.total_amount as amount
      from purchasing.invoices i
     where i.deleted_at is null and i.status in ('approved', 'released', 'paid')
    union all
    select i.group_id, i.restaurant_id, i.supplier_id, n.issued_on, n.created_at,
           case n.note_kind when 'debit' then 'debit_note' when 'discount' then 'discount' else 'credit_note' end,
           n.id, coalesce(n.number, '') || ' · ' || purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number),
           case when n.note_kind = 'debit' then n.total_amount else -n.total_amount end
      from purchasing.credit_debit_notes n join purchasing.invoices i on i.id = n.invoice_id
     where n.deleted_at is null and i.deleted_at is null and i.status in ('approved', 'released', 'paid')
    union all
    select p.group_id, p.restaurant_id, p.supplier_id, p.paid_on, p.created_at, 'payment', p.id,
           coalesce(p.reference, ''), -p.payment_amount
      from purchasing.payments p
     where p.deleted_at is null and p.status in ('registered', 'receipt_queued'))
  select m.*, sum(m.amount) over (partition by m.supplier_id, m.restaurant_id
                                  order by m.moved_on, m.created_at, m.source_id) as balance_amount
    from moves m;
revoke all on reporting.v_supplier_account_movements from public, anon, authenticated, service_role;
comment on view reporting.v_supplier_account_movements is
  'Cada movimiento de la cuenta corriente de un proveedor en un local (factura conforme, nota de crédito, débito o descuento, pago), con fecha, importe (positivo: le debemos más) y el saldo acumulado.';

-- La cuenta corriente por proveedor y local.
create view reporting.v_supplier_account with (security_invoker = true) as
  with keys as (
    select restaurant_id, supplier_id, group_id from reporting.v_invoice_balances
    union
    select restaurant_id, supplier_id, group_id from purchasing.payments
     where deleted_at is null and status in ('registered', 'receipt_queued'))
  select k.group_id, k.restaurant_id, k.supplier_id,
         coalesce(inv.invoiced_amount, 0) as invoiced_amount, coalesce(inv.credit_amount, 0) as credit_amount,
         coalesce(inv.debit_amount, 0) as debit_amount, coalesce(pay.paid_amount, 0) as paid_amount,
         coalesce(pay.paid_amount, 0) - coalesce(inv.allocated_amount, 0) as unapplied_amount,
         round(coalesce(inv.invoiced_amount, 0) - coalesce(inv.credit_amount, 0) + coalesce(inv.debit_amount, 0)
               - coalesce(pay.paid_amount, 0), 4) as balance_amount,
         inv.last_invoice_on, pay.last_payment_on,
         sb.supplier_balance_amount, sb.issued_on as supplier_balance_on
    from keys k
    left join lateral (
      select sum(b.total_amount) as invoiced_amount, sum(b.credit_amount) as credit_amount,
             sum(b.debit_amount) as debit_amount, sum(b.paid_amount) as allocated_amount,
             max(b.issued_on) as last_invoice_on
        from reporting.v_invoice_balances b
       where b.restaurant_id = k.restaurant_id and b.supplier_id = k.supplier_id) inv on true
    left join lateral (
      select sum(p.payment_amount) as paid_amount, max(p.paid_on) as last_payment_on
        from purchasing.payments p
       where p.restaurant_id = k.restaurant_id and p.supplier_id = k.supplier_id and p.deleted_at is null
         and p.status in ('registered', 'receipt_queued')) pay on true
    -- El último saldo que informó el proveedor en una factura (para comparar con el nuestro).
    left join lateral (
      select b.supplier_balance_amount, b.issued_on
        from reporting.v_invoice_balances b
       where b.restaurant_id = k.restaurant_id and b.supplier_id = k.supplier_id
         and b.supplier_balance_amount is not null
       order by b.issued_on desc limit 1) sb on true;
revoke all on reporting.v_supplier_account from public, anon, authenticated, service_role;
comment on view reporting.v_supplier_account is
  'Cuenta corriente de cada proveedor en cada local: facturado conforme, notas, pagado (con lo que quedó a cuenta), saldo, última factura, último pago y el último saldo que informó el proveedor.';

-- Las alarmas pendientes del módulo, una fila por alarma.
create view reporting.v_purchasing_alerts with (security_invoker = true) as
  select l.group_id, null::uuid as restaurant_id, 'price_list_expired'::text as kind, 'warn'::text as severity,
         format('Venció la lista de %s', coalesce(s.trade_name, s.name)) as title,
         format('/listas-de-precios/%s', l.id) as link, l.valid_from as since
    from purchasing.price_lists l join catalog.suppliers s on s.id = l.supplier_id
   where l.deleted_at is null and l.status = 'accepted' and purchasing.price_list_expired_internal(l.id)
  union all
  select o.group_id, o.restaurant_id, 'order_news', 'warn', format('La OC %s tiene novedades', o.number),
         format('/compras/ordenes/%s', o.id), (o.updated_at at time zone 'America/Argentina/Buenos_Aires')::date
    from purchasing.purchase_orders o
   where o.deleted_at is null and o.status = 'with_news'
  union all
  select r.group_id, r.restaurant_id, 'receipt_differences', 'warn',
         format('Recepción con diferencias de %s', coalesce(s.trade_name, s.name)),
         case when r.purchase_order_id is not null then format('/compras/ordenes/%s?seccion=recepcion', r.purchase_order_id)
              else '/compras/recepcion' end,
         (r.closed_at at time zone 'America/Argentina/Buenos_Aires')::date
    from purchasing.receipts r join catalog.suppliers s on s.id = r.supplier_id
    left join purchasing.purchase_orders o on o.id = r.purchase_order_id
   where r.deleted_at is null and r.status = 'closed' and r.result = 'with_differences'
     and (o.id is null or o.status <> 'closed')
  union all
  select u.group_id, null, 'unmapped_article', 'info', format('Sin mapear: %s', u.raw_name),
         '/materias-primas/sin-mapear', (u.created_at at time zone 'America/Argentina/Buenos_Aires')::date
    from purchasing.unmapped_articles u
   where u.deleted_at is null and u.status = 'pending'
  union all
  select i.group_id, i.restaurant_id, 'invoice_observed', 'bad',
         format('Observada: %s de %s', purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number),
                coalesce(s.trade_name, s.name)),
         format('/compras/facturas/%s', i.id), i.issued_on
    from purchasing.invoices i join catalog.suppliers s on s.id = i.supplier_id
   where i.deleted_at is null and i.status = 'observed'
  union all
  select d.group_id, d.restaurant_id, case when d.due_state = 'bad' then 'payment_overdue' else 'payment_due' end,
         d.due_state,
         format('%s %s de %s', case when d.due_state = 'bad' then 'Venció la' else 'Vence la' end,
                purchasing.invoice_label(d.invoice_class, d.point_of_sale, d.number), coalesce(s.trade_name, s.name)),
         format('/compras/facturas/%s', d.invoice_id), d.due_on
    from reporting.v_payment_schedule d join catalog.suppliers s on s.id = d.supplier_id
   where d.due_state in ('bad', 'warn')
  union all
  select p.group_id, p.restaurant_id, 'cash_to_confirm', 'info',
         format('Efectivo para confirmar a %s', coalesce(s.trade_name, s.name)), '/compras/pagos?estado=para-confirmar',
         p.paid_on
    from purchasing.payments p join catalog.suppliers s on s.id = p.supplier_id
   where p.deleted_at is null and p.status = 'to_confirm';
revoke all on reporting.v_purchasing_alerts from public, anon, authenticated, service_role;
comment on view reporting.v_purchasing_alerts is
  'Alarmas pendientes de compras, una fila por alarma: lista vencida, OC con novedad, recepción con diferencias, artículo sin mapear, factura observada, pago por vencer o vencido y efectivo para confirmar. Con su gravedad (bad, warn, info), su local (nulo si es de todo el grupo) y el enlace.';

-- El gasto de las facturas conformes, por renglón: rubro de la materia prima (y si va a recetas), fletes y servicios
-- aparte. Lo que suma el tablero de compras.
create view reporting.v_purchase_spend with (security_invoker = true) as
  select i.group_id, i.restaurant_id, i.supplier_id, i.issued_on,
         case when l.line_class in ('product', 'free_of_charge') then 'product'
              when l.line_class in ('freight', 'service') then 'freight' else 'other' end as bucket,
         c.id as category_id, c.name as category_name, coalesce(c.used_in_recipes, true) as used_in_recipes,
         ing.id as ingredient_id, l.line_amount as spend_amount
    from purchasing.invoices i
    join purchasing.invoice_lines l on l.invoice_id = i.id and l.deleted_at is null
    left join catalog.purchase_products pp on pp.id = l.purchase_product_id
    left join catalog.ingredients ing on ing.id = pp.ingredient_id
    left join catalog.ingredient_categories c on c.id = ing.category_id
   where i.deleted_at is null and i.status in ('approved', 'released', 'paid')
  union all
  -- Las percepciones nunca van al costo (decisión 4 de Soy), pero son gasto de la factura.
  select i.group_id, i.restaurant_id, i.supplier_id, i.issued_on, 'perception', null, null, false, null,
         i.perception_amount
    from purchasing.invoices i
   where i.deleted_at is null and i.status in ('approved', 'released', 'paid') and i.perception_amount > 0;
revoke all on reporting.v_purchase_spend from public, anon, authenticated, service_role;
comment on view reporting.v_purchase_spend is
  'Gasto de las facturas conformes, por renglón: mercadería con su rubro (y si va a recetas), fletes y servicios, otros y percepciones (decisiones 4 y 5 de Soy: no son costo, pero sí gasto).';

-- Cómo varía el costo de cada materia prima: cada precio de un local con su costo por unidad de uso.
create view reporting.v_ingredient_cost_history with (security_invoker = true) as
  select r.group_id, r.restaurant_id, pp.ingredient_id, r.valid_from, r.entry_number, r.source,
         round(r.net_package_price / r.base_quantity, 8) as unit_cost_amount
    from costing.price_records r
    join catalog.purchase_products pp on pp.id = r.purchase_product_id
   where r.deleted_at is null and r.scope_type = 'restaurant' and r.source <> 'test_value';
revoke all on reporting.v_ingredient_cost_history from public, anon, authenticated, service_role;
comment on view reporting.v_ingredient_cost_history is
  'Evolución del costo de cada materia prima por local: cada precio con su costo sin IVA por unidad de uso, para graficar cuánto subieron los insumos.';

-- Cuánto pesó el último aumento de cada proveedor: la variación de su última lista aceptada, ponderada por lo que se le
-- compró de cada artículo en los últimos 90 días (pedido de Soy, Etapa 1).
create view reporting.v_price_list_impact with (security_invoker = true) as
  with spend as (
    select i.group_id, i.supplier_id, l.purchase_product_id, sum(l.line_amount) as spend_amount
      from purchasing.invoices i join purchasing.invoice_lines l on l.invoice_id = i.id and l.deleted_at is null
     where i.deleted_at is null and i.status in ('approved', 'released', 'paid')
       and i.issued_on >= recipes.today() - 90 and l.purchase_product_id is not null
     group by i.group_id, i.supplier_id, l.purchase_product_id)
  select c.group_id, c.supplier_id, c.price_list_id,
         round(sum(c.change_pct * s.spend_amount) / nullif(sum(s.spend_amount), 0), 2) as weighted_change_pct,
         sum(s.spend_amount) as spend_amount
    from reporting.v_price_list_changes c
    join purchasing.price_lists l on l.id = c.price_list_id and l.status = 'accepted' and l.deleted_at is null
    join spend s on s.supplier_id = c.supplier_id and s.purchase_product_id = c.purchase_product_id
   where c.change_pct is not null
   group by c.group_id, c.supplier_id, c.price_list_id;
revoke all on reporting.v_price_list_impact from public, anon, authenticated, service_role;
comment on view reporting.v_price_list_impact is
  'Incidencia de los aumentos: la variación % de la última lista aceptada de cada proveedor contra la anterior, ponderada por lo que se le compró de cada artículo en los últimos 90 días.';

-- ---------------------------------------------------------------------------
-- 2. Lecturas (controlan el permiso y filtran por los locales que la sesión ve)
-- ---------------------------------------------------------------------------
-- La agenda y los pagados (pestañas de /compras/pagos).
create function purchasing.payment_schedule_list(p_tab text default 'due', p_supplier_id uuid default null,
                                                 p_restaurant_id uuid default null, p_limit integer default 15,
                                                 p_offset integer default 0)
returns table (invoice_id uuid, invoice_class purchasing.invoice_class, point_of_sale integer, number bigint,
               restaurant_id uuid, restaurant_name text, supplier_id uuid, supplier_name text, issued_on date,
               due_on date, total_amount numeric, balance_amount numeric, days_left integer, due_state text,
               total bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select b.invoice_id, b.invoice_class, b.point_of_sale, b.number, b.restaurant_id, r.name, b.supplier_id,
         coalesce(s.trade_name, s.name), b.issued_on, b.due_on, b.total_amount, b.balance_amount,
         b.due_on - recipes.today(),
         case when b.status = 'paid' then 'none' when b.due_on < recipes.today() then 'bad'
              when b.due_on <= recipes.today() + 7 then 'warn' else 'ok' end,
         count(*) over ()
    from reporting.v_invoice_balances b
    join org.restaurants r on r.id = b.restaurant_id
    join catalog.suppliers s on s.id = b.supplier_id
   where b.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_payments'))
     and (p_restaurant_id is null or b.restaurant_id = p_restaurant_id)
     and (p_supplier_id is null or b.supplier_id = p_supplier_id)
     and case coalesce(p_tab, 'due')
           when 'overdue' then b.status = 'released' and b.balance_amount > 0.005 and b.due_on < recipes.today()
           when 'paid' then b.status = 'paid'
           else b.status = 'released' and b.balance_amount > 0.005 and b.due_on >= recipes.today()
         end
   order by case when coalesce(p_tab, 'due') = 'paid' then null else b.due_on end, b.issued_on desc, b.invoice_id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function purchasing.payment_schedule_list(text, uuid, uuid, integer, integer) is
  'Agenda de pagos de los locales donde la sesión ve pagos (purchasing.view_payments): «due» (por vencer, de la más próxima), «overdue» (vencidas) o «paid» (pagadas), con su saldo y estado. Filtra por proveedor y local, y pagina.';
revoke execute on function purchasing.payment_schedule_list(text, uuid, uuid, integer, integer) from public;
grant execute on function purchasing.payment_schedule_list(text, uuid, uuid, integer, integer) to authenticated;

-- El efectivo pagado al recibir que falta confirmar.
create function purchasing.cash_to_confirm(p_restaurant_id uuid default null)
returns table (payment_id uuid, restaurant_id uuid, restaurant_name text, supplier_id uuid, supplier_name text,
               paid_on date, payment_amount numeric, receipt_id uuid, purchase_order_id uuid, order_number text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.restaurant_id, r.name, p.supplier_id, coalesce(s.trade_name, s.name), p.paid_on, p.payment_amount,
         p.receipt_id, rc.purchase_order_id, o.number
    from purchasing.payments p
    join org.restaurants r on r.id = p.restaurant_id
    join catalog.suppliers s on s.id = p.supplier_id
    join purchasing.receipts rc on rc.id = p.receipt_id
    left join purchasing.purchase_orders o on o.id = rc.purchase_order_id
   where p.deleted_at is null and p.status = 'to_confirm'
     and p.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_payments'))
     and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
   order by p.paid_on, p.id
   limit 100
$$;
comment on function purchasing.cash_to_confirm(uuid) is
  'El efectivo pagado al recibir que Compras todavía no confirmó, de los locales donde la sesión ve pagos.';
revoke execute on function purchasing.cash_to_confirm(uuid) from public;
grant execute on function purchasing.cash_to_confirm(uuid) to authenticated;

-- Para el panel «Registrar pago»: las facturas liberadas con saldo de un proveedor en un local y lo que quedó a cuenta.
create function purchasing.payable_invoices(p_restaurant_id uuid, p_supplier_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when purchasing.can_in_restaurant('purchasing.pay', p_restaurant_id) then jsonb_build_object(
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_id', d.invoice_id,
               'label', purchasing.invoice_label(d.invoice_class, d.point_of_sale, d.number),
               'issued_on', d.issued_on, 'due_on', d.due_on, 'balance', d.balance_amount, 'due_state', d.due_state)
               order by d.due_on, d.issued_on)
        from reporting.v_payment_schedule d
       where d.restaurant_id = p_restaurant_id and d.supplier_id = p_supplier_id), '[]'::jsonb),
    'credits', coalesce((
      select jsonb_agg(jsonb_build_object('payment_id', p.id, 'paid_on', p.paid_on, 'reference', p.reference,
                                          'unapplied', purchasing.payment_unapplied(p.id)) order by p.paid_on)
        from purchasing.payments p
       where p.restaurant_id = p_restaurant_id and p.supplier_id = p_supplier_id and p.deleted_at is null
         and p.status in ('registered', 'receipt_queued') and purchasing.payment_unapplied(p.id) > 0.005), '[]'::jsonb),
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'method', a.method, 'bank', a.bank, 'alias', a.alias,
                                          'cbu_end', right(a.cbu, 4), 'electronic_code', a.electronic_code)
                       order by a.method, a.created_at)
        from purchasing.supplier_payment_accounts a
       where a.supplier_id = p_supplier_id and a.is_active and a.deleted_at is null), '[]'::jsonb)) end
$$;
comment on function purchasing.payable_invoices(uuid, uuid) is
  '«Registrar pago»: las facturas liberadas con saldo de un proveedor en un local, lo que quedó a cuenta y las cuentas de pago activas del proveedor (sin el CBU entero). Nulo si la sesión no paga en ese local.';
revoke execute on function purchasing.payable_invoices(uuid, uuid) from public;
grant execute on function purchasing.payable_invoices(uuid, uuid) to authenticated;

-- La cuenta corriente de un proveedor (en un local o en todos los que la sesión ve) y sus últimos movimientos.
create function purchasing.supplier_account(p_supplier_id uuid, p_restaurant_id uuid default null,
                                            p_movements integer default 5)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with places as (
    select x from core.permitted_restaurant_ids('purchasing.view_payments') x
     where p_restaurant_id is null or x = p_restaurant_id)
  select case when exists (select 1 from places) then jsonb_build_object(
    'invoiced', coalesce(sum(a.invoiced_amount), 0),
    'credits', coalesce(sum(a.credit_amount), 0) - coalesce(sum(a.debit_amount), 0),
    'paid', coalesce(sum(a.paid_amount), 0),
    'unapplied', coalesce(sum(a.unapplied_amount), 0),
    'balance', coalesce(sum(a.balance_amount), 0),
    'last_invoice_on', max(a.last_invoice_on),
    'last_payment_on', max(a.last_payment_on),
    -- El saldo que informó el proveedor se compara solo en un local (cada local es una cuenta).
    'supplier_balance', case when p_restaurant_id is not null then max(a.supplier_balance_amount) end,
    'supplier_balance_on', case when p_restaurant_id is not null then max(a.supplier_balance_on) end,
    'overdue', coalesce((select sum(d.balance_amount) from reporting.v_payment_schedule d
                          where d.supplier_id = p_supplier_id and d.restaurant_id in (select x from places)
                            and d.due_state = 'bad'), 0),
    'movements', coalesce((
      select jsonb_agg(jsonb_build_object('kind', m.kind, 'moved_on', m.moved_on, 'label', m.label,
                                          'amount', m.amount, 'balance', m.balance_amount, 'source_id', m.source_id,
                                          'restaurant_id', m.restaurant_id)
                       order by m.moved_on desc, m.created_at desc)
        from (select * from reporting.v_supplier_account_movements m
               where m.supplier_id = p_supplier_id and m.restaurant_id in (select x from places)
               order by m.moved_on desc, m.created_at desc
               limit least(greatest(coalesce(p_movements, 5), 1), 500)) m), '[]'::jsonb),
    'movement_count', (select count(*) from reporting.v_supplier_account_movements m
                        where m.supplier_id = p_supplier_id and m.restaurant_id in (select x from places)))
  end
    from reporting.v_supplier_account a
   where a.supplier_id = p_supplier_id and a.restaurant_id in (select x from places)
$$;
comment on function purchasing.supplier_account(uuid, uuid, integer) is
  'Cuenta corriente de un proveedor en los locales donde la sesión ve pagos (o en uno): facturado, notas, pagado, a cuenta, saldo, vencido, última factura y último pago, el saldo que informó el proveedor (en un local) y los últimos movimientos con el saldo acumulado de su local. Nulo si la sesión no ve pagos.';
revoke execute on function purchasing.supplier_account(uuid, uuid, integer) from public;
grant execute on function purchasing.supplier_account(uuid, uuid, integer) to authenticated;

-- El tablero de compras de un local (o de todos los que la sesión ve). Los importes, solo para quien ve pagos.
create function purchasing.purchasing_dashboard(p_restaurant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_places  uuid[];
  v_groups  uuid[];
  v_amounts boolean;
  v_month   date := date_trunc('month', recipes.today())::date;
  v_result  jsonb;
begin
  select array_agg(x) into v_places from core.permitted_restaurant_ids('purchasing.view_dashboard') x
   where p_restaurant_id is null or x = p_restaurant_id;
  if v_places is null then
    return null;
  end if;
  select array_agg(distinct r.group_id) into v_groups from org.restaurants r where r.id = any (v_places);
  -- Ve importes quien ve los pagos de todos esos locales (el chef ve el tablero sin importes).
  v_amounts := not exists (select 1 from unnest(v_places) x
                            where x not in (select core.permitted_restaurant_ids('purchasing.view_payments')));
  select jsonb_build_object(
    'can_see_amounts', v_amounts,
    'alerts', coalesce((
      select jsonb_agg(jsonb_build_object('kind', a.kind, 'severity', a.severity, 'title', a.title, 'link', a.link,
                                          'since', a.since)
                       order by case a.severity when 'bad' then 0 when 'warn' then 1 else 2 end, a.since)
        from reporting.v_purchasing_alerts a
       where (a.restaurant_id = any (v_places) or (a.restaurant_id is null and a.group_id = any (v_groups)))
         -- Quien no ve importes no recibe las alarmas de plata.
         and (v_amounts or a.kind not in ('payment_due', 'payment_overdue', 'cash_to_confirm'))), '[]'::jsonb),
    'observed', (select count(*) from purchasing.invoices i
                  where i.deleted_at is null and i.status = 'observed' and i.restaurant_id = any (v_places)),
    'open_orders', (select count(*) from purchasing.purchase_orders o
                     where o.deleted_at is null and o.restaurant_id = any (v_places)
                       and o.status in ('pending_approval', 'sent', 'with_news', 'partially_received')),
    'expired_lists', (select count(*) from purchasing.price_lists l
                       where l.deleted_at is null and l.status = 'accepted' and l.group_id = any (v_groups)
                         and purchasing.price_list_expired_internal(l.id)),
    'due_week', (select count(*) from reporting.v_payment_schedule d
                  where d.restaurant_id = any (v_places) and d.due_on <= recipes.today() + 7),
    'due_week_amount', case when v_amounts then (
                  select coalesce(sum(d.balance_amount), 0) from reporting.v_payment_schedule d
                   where d.restaurant_id = any (v_places) and d.due_on <= recipes.today() + 7) end,
    'unmapped', (select count(*) from purchasing.unmapped_articles u
                  where u.deleted_at is null and u.status = 'pending' and u.group_id = any (v_groups)),
    'spend', case when v_amounts then coalesce((
      select jsonb_agg(jsonb_build_object('label', x.label, 'kind', x.kind, 'amount', x.amount)
                       order by x.sort, x.amount desc)
        from (select coalesce(s.category_name, 'Sin rubro') as label,
                     case when s.used_in_recipes then 'recipes' else 'other' end as kind, sum(s.spend_amount) as amount,
                     0 as sort
                from reporting.v_purchase_spend s
               where s.restaurant_id = any (v_places) and s.issued_on >= v_month and s.bucket = 'product'
               group by coalesce(s.category_name, 'Sin rubro'), s.used_in_recipes
              union all
              select case s.bucket when 'freight' then 'Fletes y servicios' when 'perception' then 'Percepciones'
                                   else 'Otros' end,
                     s.bucket, sum(s.spend_amount), 1
                from reporting.v_purchase_spend s
               where s.restaurant_id = any (v_places) and s.issued_on >= v_month and s.bucket <> 'product'
               group by s.bucket) x), '[]'::jsonb) end,
    -- Las 4 materias primas que más pesan en la compra de los últimos 90 días, con la variación de su costo (en % desde
    -- su primer precio del período), para ver cuánto subieron los insumos.
    'cost_history', case when v_amounts then coalesce((
      select jsonb_agg(jsonb_build_object('ingredient_id', t.ingredient_id, 'name', ing.name, 'points', (
               select jsonb_agg(jsonb_build_object('on', h.valid_from, 'change_pct', h.change_pct) order by h.valid_from)
                 from (select y.valid_from,
                              round(100 * (avg(y.unit_cost_amount)
                                           / nullif(first_value(avg(y.unit_cost_amount)) over (order by y.valid_from), 0)
                                           - 1), 1) as change_pct
                         from reporting.v_ingredient_cost_history y
                        where y.ingredient_id = t.ingredient_id and y.restaurant_id = any (v_places)
                          and y.valid_from >= recipes.today() - 90 and y.valid_from <= recipes.today()
                        group by y.valid_from) h)) order by t.amount desc)
        from (select s.ingredient_id, sum(s.spend_amount) as amount
                from reporting.v_purchase_spend s
               where s.restaurant_id = any (v_places) and s.issued_on >= recipes.today() - 90
                 and s.ingredient_id is not null
               group by s.ingredient_id order by sum(s.spend_amount) desc limit 4) t
        join catalog.ingredients ing on ing.id = t.ingredient_id), '[]'::jsonb) end,
    'next_payments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_id', d.invoice_id, 'label', purchasing.invoice_label(d.invoice_class, d.point_of_sale, d.number),
               'supplier', coalesce(s.trade_name, s.name), 'due_on', d.due_on, 'due_state', d.due_state,
               'balance', case when v_amounts then d.balance_amount end) order by d.due_on)
        from (select * from reporting.v_payment_schedule d0 where d0.restaurant_id = any (v_places)
               order by d0.due_on limit 5) d
        join catalog.suppliers s on s.id = d.supplier_id), '[]'::jsonb)
  ) into v_result;
  return v_result;
end
$$;
comment on function purchasing.purchasing_dashboard(uuid) is
  'El tablero de compras de un local (o de todos los que la sesión ve con purchasing.view_dashboard): alarmas, facturas observadas, OC abiertas, listas vencidas, lo que vence esta semana, artículos sin mapear, el gasto del mes por rubro (con fletes y percepciones aparte), la variación del costo de las 4 materias primas que más pesan y los próximos pagos. Los importes solo para quien ve los pagos de esos locales. Nulo si la sesión no ve el tablero.';
revoke execute on function purchasing.purchasing_dashboard(uuid) from public;
grant execute on function purchasing.purchasing_dashboard(uuid) to authenticated;
