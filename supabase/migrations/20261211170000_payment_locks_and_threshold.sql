-- Correcciones de la revisión de base del Prompt 6 (ADR-0060, 2026-11-19):
-- 1. Un solo orden de bloqueo en todo pagos: primero las facturas (por id), después el pago. Liberar una factura y
--    agregar una nota ya lo hacían así (el trigger corre con la factura bloqueada); confirmar el efectivo, aplicar lo que
--    está a cuenta y anular iban al revés, y dos personas a la vez podían trabarse (deadlock).
-- 2. Un solo umbral para «saldada»: el saldo hasta medio centavo (0,005). guard_invoice y las notas usaban 0.
-- 3. Una nota de crédito que deja el saldo negativo sin pagos que devolver a cuenta se rechaza (si no, la factura
--    quedaba pagada con saldo negativo y la cuenta corriente mostraba un número sin explicación).
-- 4. invoice_payments decide el permiso con purchasing.can_in_restaurant, como el resto de compras (descarta locales
--    dados de baja).
-- 5. La cuenta corriente: en el mismo día, primero la factura, después las notas y al final el pago; la ficha muestra
--    los movimientos en el orden inverso exacto del saldo acumulado.

create or replace function purchasing.confirm_cash_payment(p_id uuid, p_amount numeric, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p      purchasing.payments;
  v_reason text := nullif(btrim(p_reason), '');
  v_left   numeric;
begin
  select * into v_p from purchasing.payments where id = p_id and deleted_at is null;
  if v_p.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_p.restaurant_id) then
    return core.deny('purchasing.confirm_cash_payment', 'No tenés permiso para confirmar este pago.', null,
                     jsonb_build_object('payment_id', p_id), v_p.group_id, v_p.brand_id, v_p.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  -- Mismo orden que liberar una factura: primero las facturas de la OC de su recepción, después el pago.
  perform 1 from purchasing.invoices i
   where i.id in (select io.invoice_id from purchasing.receipts r
                    join purchasing.invoice_orders io on io.purchase_order_id = r.purchase_order_id
                                                      and io.deleted_at is null
                   where r.id = v_p.receipt_id)
   order by i.id
     for update;
  select * into v_p from purchasing.payments where id = p_id for update;
  if v_p.status <> 'to_confirm' then
    raise exception 'Este pago ya está confirmado.' using errcode = '23514';
  end if;
  if p_amount is not null and (p_amount <= 0 or p_amount = 'NaN'::numeric or p_amount >= 10000000000) then
    raise exception 'El importe tiene que ser mayor que cero.' using errcode = '22023';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  update purchasing.payments set status = 'registered', payment_amount = coalesce(round(p_amount, 4), payment_amount)
   where id = v_p.id;
  v_left := purchasing.apply_receipt_cash(v_p.id);
  return jsonb_build_object('result', 'applied', 'payment_id', v_p.id, 'unapplied', round(v_left, 2));
end
$$;

create or replace function purchasing.apply_payment_credit(p_payment_id uuid, p_allocations jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p      purchasing.payments;
  v_item   jsonb;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select * into v_p from purchasing.payments where id = p_payment_id and deleted_at is null;
  if v_p.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_p.restaurant_id) then
    return core.deny('purchasing.apply_payment_credit', 'No tenés permiso para aplicar este pago.', null,
                     jsonb_build_object('payment_id', p_payment_id), v_p.group_id, v_p.brand_id, v_p.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  if p_allocations is null or jsonb_typeof(p_allocations) <> 'array' or jsonb_array_length(p_allocations) = 0 then
    raise exception 'Elegí a qué facturas se aplica.' using errcode = '22023';
  end if;
  perform purchasing.check_payment_lines(p_allocations);
  if v_p.status not in ('registered', 'receipt_queued') then
    raise exception 'Solo se aplica un pago registrado.' using errcode = '23514';
  end if;
  -- Mismo orden en todo pagos: primero las facturas (por id), después el pago.
  perform 1 from purchasing.invoices
   where id in (select (x ->> 'invoice_id')::uuid from jsonb_array_elements(p_allocations) x)
   order by id
     for update;
  select * into v_p from purchasing.payments where id = p_payment_id for update;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  for v_item in select value from jsonb_array_elements(p_allocations) loop
    perform purchasing.allocate_payment(v_p.id, (v_item ->> 'invoice_id')::uuid, (v_item ->> 'amount')::numeric);
  end loop;
  return jsonb_build_object('result', 'applied', 'payment_id', v_p.id,
                            'unapplied', round(purchasing.payment_unapplied(v_p.id), 2));
exception
  when check_violation then
    -- Los mensajes de las guardas ya están en español; una restricción sin traducir no se muestra cruda.
    if sqlerrm ~ 'violates' then
      raise exception 'Revisá lo que se aplica a cada factura.' using errcode = '23514';
    end if;
    raise exception '%', sqlerrm using errcode = '23514';
end
$$;

create or replace function purchasing.void_payment(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p      purchasing.payments;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select * into v_p from purchasing.payments where id = p_id and deleted_at is null;
  if v_p.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_p.restaurant_id) then
    return core.deny('purchasing.void_payment', 'No tenés permiso para anular este pago.', null,
                     jsonb_build_object('payment_id', p_id), v_p.group_id, v_p.brand_id, v_p.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí por qué se anula.' using errcode = '22023';
  end if;
  -- Mismo orden en todo pagos: primero las facturas (por id), después el pago.
  perform 1 from purchasing.invoices i
   where i.id in (select a.invoice_id from purchasing.payment_allocations a where a.payment_id = v_p.id)
   order by i.id
     for update;
  select * into v_p from purchasing.payments where id = p_id for update;
  if v_p.status = 'voided' then
    raise exception 'Este pago ya está anulado.' using errcode = '23514';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  update purchasing.payments
     set status = 'voided', voided_reason = left(v_reason, 500), voided_at = now(), voided_by = core.current_actor_id()
   where id = v_p.id;
  -- Las facturas que cancelaba y ahora tienen saldo vuelven a liberadas.
  update purchasing.invoices i set status = 'released'
   where i.status = 'paid'
     and i.id in (select a.invoice_id from purchasing.payment_allocations a
                   where a.payment_id = v_p.id and a.deleted_at is null)
     and purchasing.invoice_balance(i.id) > 0.005;
  update purchasing.outbound_messages set status = 'cancelled'
   where source_table = 'payments' and source_id = v_p.id and status = 'queued';
  return jsonb_build_object('result', 'applied', 'payment_id', v_p.id, 'status', 'voided');
end
$$;

create or replace function purchasing.guard_invoice()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_supplier_tax text;
begin
  if tg_op = 'DELETE' then
    raise exception 'Una factura no se borra: se cancela, con motivo.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.status in ('approved', 'released', 'paid', 'cancelled') then
    if (to_jsonb(new) - array['status', 'updated_at', 'updated_by'])
         is distinct from (to_jsonb(old) - array['status', 'updated_at', 'updated_by'])
       or not (new.status = old.status
               or (old.status = 'approved' and new.status = 'released')
               or (old.status = 'released' and new.status = 'paid')
               -- Al anular un pago, una factura pagada con saldo vuelve a liberada (ADR-0060).
               or (old.status = 'paid' and new.status = 'released' and purchasing.invoice_balance(new.id) > 0.005)) then
      raise exception 'Una factura conforme no cambia: corregila con una nota de crédito o débito.' using errcode = '42501';
    end if;
    return new;
  end if;
  if new.issuer_tax_id = '99999999999' then
    raise exception 'El CUIT del emisor es de ejemplo (99-99999999-9): esa factura no vale.' using errcode = '23514';
  end if;
  if new.issuer_tax_id is not null and not core.valid_cuit(new.issuer_tax_id) then
    raise exception 'El CUIT del emisor no es válido.' using errcode = '23514';
  end if;
  select s.tax_id into v_supplier_tax from catalog.suppliers s where s.id = new.supplier_id;
  if new.issuer_tax_id is not null and new.issuer_tax_id is distinct from v_supplier_tax then
    raise exception 'El CUIT de la factura no es el del proveedor.' using errcode = '23514';
  end if;
  return new;
end
$$;

create or replace function purchasing.on_note_added()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv     purchasing.invoices;
  v_balance numeric;
begin
  select * into v_inv from purchasing.invoices where id = new.invoice_id for update;
  if v_inv.status not in ('released', 'paid') then
    return new;
  end if;
  if purchasing.invoice_balance(v_inv.id) < 0 then
    perform purchasing.release_overpayment(v_inv.id);
  end if;
  v_balance := purchasing.invoice_balance(v_inv.id);
  if v_balance < -0.005 then
    raise exception 'La nota deja la factura con saldo a favor y no hay pagos para devolver a cuenta: revisá el importe.'
      using errcode = '23514';
  end if;
  if v_inv.status = 'released' and v_balance <= 0.005 then
    update purchasing.invoices set status = 'paid' where id = v_inv.id;
  elsif v_inv.status = 'paid' and v_balance > 0.005 then
    update purchasing.invoices set status = 'released' where id = v_inv.id;
  end if;
  return new;
end
$$;

create or replace function purchasing.invoice_payments(p_invoice_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'balance', purchasing.invoice_balance(i.id),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
               'payment_id', p.id,
               'paid_on', p.paid_on,
               'method', p.method,
               'reference', p.reference,
               'allocated', a.allocated_amount,
               'payment_amount', p.payment_amount)
             order by p.paid_on, p.created_at)
        from purchasing.payment_allocations a
        join purchasing.payments p on p.id = a.payment_id and p.group_id = a.group_id
       where a.invoice_id = i.id and a.group_id = i.group_id
         and a.deleted_at is null and p.deleted_at is null
         and p.status <> 'voided'), '[]'::jsonb))
    from purchasing.invoices i
   where i.id = p_invoice_id
     and i.deleted_at is null
     and purchasing.can_in_restaurant('purchasing.view_payments', i.restaurant_id)
$$;

-- El orden de un movimiento dentro del día: la factura, sus notas y al final el pago.
create function purchasing.movement_rank(p_kind text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_kind when 'invoice' then 0 when 'debit_note' then 1 when 'credit_note' then 2
                     when 'discount' then 2 else 3 end
$$;
comment on function purchasing.movement_rank(text) is
  'Interna: el orden de un movimiento de la cuenta corriente dentro del mismo día (factura, notas, pago), para el saldo acumulado.';
revoke execute on function purchasing.movement_rank(text) from public;

create or replace view reporting.v_supplier_account_movements with (security_invoker = true) as
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
                                  order by m.moved_on, purchasing.movement_rank(m.kind), m.created_at, m.source_id)
           as balance_amount
    from moves m;
revoke all on reporting.v_supplier_account_movements from public, anon, authenticated, service_role;

create or replace function purchasing.supplier_account(p_supplier_id uuid, p_restaurant_id uuid default null,
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
                       order by m.moved_on desc, purchasing.movement_rank(m.kind) desc, m.created_at desc,
                                m.source_id desc)
        from (select * from reporting.v_supplier_account_movements m
               where m.supplier_id = p_supplier_id and m.restaurant_id in (select x from places)
               order by m.moved_on desc, purchasing.movement_rank(m.kind) desc, m.created_at desc, m.source_id desc
               limit least(greatest(coalesce(p_movements, 5), 1), 500)) m), '[]'::jsonb),
    'movement_count', (select count(*) from reporting.v_supplier_account_movements m
                        where m.supplier_id = p_supplier_id and m.restaurant_id in (select x from places)))
  end
    from reporting.v_supplier_account a
   where a.supplier_id = p_supplier_id and a.restaurant_id in (select x from places)
$$;
