-- Fase 3, Prompt 6 (ADR-0060): registrar pagos, el comprobante, el efectivo pagado al recibir, anular y los avisos de
-- vencimiento. Todo con security definer, search_path fijo y el permiso controlado adentro; el motivo y el origen viajan
-- con core.set_change_context.
--
-- El efectivo se engancha con dos triggers chicos (en vez de copiar close_receipt y release_invoice, que ya están
-- revisados): al cerrar una recepción con efectivo nace el pago «para confirmar»; cuando una factura queda liberada, se
-- le aplica el efectivo confirmado de la recepción de su OC.

-- ---------------------------------------------------------------------------
-- 1. Ayudantes internos
-- ---------------------------------------------------------------------------
-- Lo que queda de un pago sin aplicar (a cuenta).
create function purchasing.payment_unapplied(p_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round(p.payment_amount - coalesce((select sum(a.allocated_amount) from purchasing.payment_allocations a
                                              where a.payment_id = p.id and a.deleted_at is null), 0), 4)
    from purchasing.payments p
   where p.id = p_id and p.status in ('registered', 'receipt_queued')
$$;
comment on function purchasing.payment_unapplied(uuid) is
  'Interna: lo que queda de un pago registrado sin aplicar a facturas (a cuenta). Nulo si el pago no está registrado.';
revoke execute on function purchasing.payment_unapplied(uuid) from public;

-- Aplica parte de un pago a una factura y, si su saldo llega a cero, la pasa a pagada (en la misma transacción).
create function purchasing.allocate_payment(p_payment_id uuid, p_invoice_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  if p_amount is null or p_amount <= 0 then
    return;
  end if;
  select group_id into v_group from purchasing.payments where id = p_payment_id;
  -- El trigger guard_payment_allocation controla local, proveedor, estado y que no pase el saldo ni el pago.
  insert into purchasing.payment_allocations (group_id, payment_id, invoice_id, allocated_amount)
  values (v_group, p_payment_id, p_invoice_id, round(p_amount, 4));
  if purchasing.invoice_balance(p_invoice_id) <= 0.005 then
    update purchasing.invoices set status = 'paid' where id = p_invoice_id and status = 'released';
  end if;
end
$$;
comment on function purchasing.allocate_payment(uuid, uuid, numeric) is
  'Interna: aplica parte de un pago a una factura y la pasa a pagada si su saldo llega a cero, en la misma transacción.';
revoke execute on function purchasing.allocate_payment(uuid, uuid, numeric) from public;

-- El efectivo confirmado de una recepción se aplica a las facturas liberadas de su OC, hasta su saldo (decisión de
-- Joaco, 2026-11-18). Lo que sobra queda a cuenta.
create function purchasing.apply_receipt_cash(p_payment_id uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left    numeric := coalesce(purchasing.payment_unapplied(p_payment_id), 0);
  v_balance numeric;
  v_inv     record;
begin
  for v_inv in
    select i.id from purchasing.payments p
      join purchasing.receipts r on r.id = p.receipt_id
      join purchasing.invoice_orders io on io.purchase_order_id = r.purchase_order_id and io.deleted_at is null
      join purchasing.invoices i on i.id = io.invoice_id
     where p.id = p_payment_id and i.deleted_at is null and i.status = 'released'
       and i.restaurant_id = p.restaurant_id and i.supplier_id = p.supplier_id
     order by i.issued_on, i.number
       for update of i
  loop
    exit when v_left <= 0.005;
    v_balance := purchasing.invoice_balance(v_inv.id);
    if v_balance > 0.005 then
      perform purchasing.allocate_payment(p_payment_id, v_inv.id, least(v_left, v_balance));
      v_left := v_left - least(v_left, v_balance);
    end if;
  end loop;
  return v_left;
end
$$;
comment on function purchasing.apply_receipt_cash(uuid) is
  'Interna: aplica el efectivo confirmado de una recepción a las facturas liberadas de su OC, de la más vieja a la más nueva, hasta su saldo. Devuelve lo que queda a cuenta.';
revoke execute on function purchasing.apply_receipt_cash(uuid) from public;

-- El mensaje al proveedor con el pago (lo despacha quien se defina después, decisión 9 de Soy).
create function purchasing.payment_message(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select format(E'Hola, %s. Te informamos un pago de %s del %s (%s%s), por:\n%s\nGracias.',
                coalesce(s.trade_name, s.name), purchasing.money_text(p.payment_amount),
                to_char(p.paid_on, 'DD/MM/YYYY'),
                case p.method when 'cash' then 'efectivo' when 'transfer' then 'transferencia' when 'check' then 'cheque'
                              when 'echeq' then 'eCheq' when 'card' then 'tarjeta' else 'pago electrónico' end,
                case when p.reference is not null then ', referencia ' || p.reference else '' end,
                coalesce((select string_agg(format('- %s: %s', purchasing.invoice_label(i.invoice_class, i.point_of_sale,
                                                                                         i.number),
                                                  purchasing.money_text(a.allocated_amount)), E'\n' order by i.issued_on)
                            from purchasing.payment_allocations a join purchasing.invoices i on i.id = a.invoice_id
                           where a.payment_id = p.id and a.deleted_at is null), '- A cuenta'))
    from purchasing.payments p
    join catalog.suppliers s on s.id = p.supplier_id
   where p.id = p_id
$$;
comment on function purchasing.payment_message(uuid) is
  'Interna: el texto del aviso de un pago al proveedor (importe, fecha, medio, referencia y qué facturas cancela).';
revoke execute on function purchasing.payment_message(uuid) from public;

-- Errores de las tablas de pagos, en español.
create function purchasing.raise_payment_error(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception '%', case
    when p_constraint = 'payments_account_check' then 'Elegí la cuenta del proveedor (en efectivo no va cuenta).'
    when p_constraint = 'payments_reference_check' then 'La referencia va de 1 a 80 caracteres.'
    when p_constraint = 'payments_payment_amount_check' then 'El importe tiene que ser mayor que cero.'
    when p_constraint = 'payment_allocations_key' then 'Una factura va una sola vez en el mismo pago.'
    when p_constraint = 'payment_allocations_allocated_amount_check' then 'Lo aplicado a cada factura tiene que ser mayor que cero.'
    when p_state = '23514' and p_message is not null and p_message !~ 'violates' then p_message
    else 'Revisá los datos del pago.'
  end using errcode = coalesce(nullif(p_state, ''), '23514');
end
$$;
comment on function purchasing.raise_payment_error(text, text, text) is
  'Interna: traduce el error de una restricción de pagos a un mensaje en español.';
revoke execute on function purchasing.raise_payment_error(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 2. Registrar un pago
-- ---------------------------------------------------------------------------
-- p_allocations: [{invoice_id, amount}]. Lo que no se aplica queda a cuenta.
create function purchasing.register_payment(p_restaurant_id uuid, p_supplier_id uuid, p_paid_on date,
                                            p_method purchasing.payment_method, p_account_id uuid, p_amount numeric,
                                            p_reference text, p_allocations jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r          org.restaurants;
  v_s          catalog.suppliers;
  v_t          purchasing.supplier_terms;
  v_id         uuid;
  v_item       jsonb;
  v_invoice    uuid;
  v_amount     numeric;
  v_total      numeric := 0;
  v_reason     text := nullif(btrim(p_reason), '');
  v_constraint text;
  v_message    text;
  v_state      text;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_r.id) then
    return core.deny('purchasing.register_payment', 'No tenés permiso para registrar pagos en este local.', null,
                     jsonb_build_object('restaurant_id', p_restaurant_id, 'supplier_id', p_supplier_id),
                     v_r.group_id, v_r.brand_id, v_r.id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí el motivo del pago.' using errcode = '22023';
  end if;
  select * into v_s from catalog.suppliers where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null;
  if v_s.id is null then
    raise exception 'Elegí un proveedor de este grupo.' using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > recipes.today() then
    raise exception 'La fecha del pago no puede ser posterior a hoy.' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount = 'NaN'::numeric then
    raise exception 'El importe tiene que ser mayor que cero.' using errcode = '22023';
  end if;
  if p_method <> 'cash' and not exists (
       select 1 from purchasing.supplier_payment_accounts a
        where a.id = p_account_id and a.supplier_id = v_s.id and a.method = p_method and a.is_active
          and a.deleted_at is null) then
    raise exception 'Elegí una cuenta activa del proveedor para ese medio de pago.' using errcode = '22023';
  end if;
  if p_allocations is not null and jsonb_typeof(p_allocations) <> 'array' then
    raise exception 'Las facturas a pagar no se entienden.' using errcode = '22023';
  end if;
  -- Dos pagos a la vez sobre las mismas facturas: el segundo espera al primero.
  perform 1 from purchasing.invoices
   where id in (select (x ->> 'invoice_id')::uuid from jsonb_array_elements(coalesce(p_allocations, '[]')) x)
     for update;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  begin
    insert into purchasing.payments (group_id, brand_id, restaurant_id, supplier_id, paid_on, method,
                                     payment_account_id, reference, payment_amount, status)
    values (v_r.group_id, v_r.brand_id, v_r.id, v_s.id, p_paid_on, p_method,
            case when p_method = 'cash' then null else p_account_id end, nullif(btrim(p_reference), ''),
            round(p_amount, 4), 'registered')
    returning id into v_id;
    for v_item in select value from jsonb_array_elements(coalesce(p_allocations, '[]')) loop
      v_invoice := (v_item ->> 'invoice_id')::uuid;
      v_amount := (v_item ->> 'amount')::numeric;
      if v_amount is null or v_amount <= 0 then
        raise exception 'Escribí cuánto se paga de cada factura (mayor que cero).' using errcode = '22023';
      end if;
      v_total := v_total + v_amount;
      perform purchasing.allocate_payment(v_id, v_invoice, v_amount);
    end loop;
  exception
    when check_violation or unique_violation or not_null_violation or foreign_key_violation
         or invalid_text_representation then
      get stacked diagnostics v_constraint = constraint_name, v_message = message_text, v_state = returned_sqlstate;
      if v_state = '22P02' then
        raise exception 'Hay un dato que no se entiende (una factura o un importe): revisá el pago.' using errcode = '22023';
      end if;
      perform purchasing.raise_payment_error(v_state, v_constraint, v_message);
  end;
  -- El aviso al proveedor, en cola, por el canal de su ficha (decisión 9 de Soy). Sin canal, queda registrado.
  select * into v_t from purchasing.supplier_terms where supplier_id = v_s.id and deleted_at is null;
  if v_t.po_channel is not null and v_t.po_channel_target is not null then
    insert into purchasing.outbound_messages (group_id, channel, target, subject, body, source_table, source_id)
    values (v_r.group_id, v_t.po_channel, v_t.po_channel_target,
            format('Pago de %s', coalesce(v_r.name, 'Grupo')), purchasing.payment_message(v_id), 'payments', v_id);
    update purchasing.payments set status = 'receipt_queued' where id = v_id;
  end if;
  return jsonb_build_object('result', 'applied', 'payment_id', v_id,
                            'unapplied', round(p_amount - v_total, 2), 'channel', v_t.po_channel);
end
$$;
comment on function purchasing.register_payment(uuid, uuid, date, purchasing.payment_method, uuid, numeric, text, jsonb, text) is
  'Registra un pago de un local a un proveedor y lo aplica a sus facturas liberadas ([{invoice_id, amount}]); lo que no se aplica queda a cuenta. Una factura que llega a saldo cero pasa a pagada en la misma transacción. Encola el aviso al proveedor por el canal de su ficha. Pide purchasing.pay en el local y un motivo.';
revoke execute on function purchasing.register_payment(uuid, uuid, date, purchasing.payment_method, uuid, numeric, text, jsonb, text) from public;
grant execute on function purchasing.register_payment(uuid, uuid, date, purchasing.payment_method, uuid, numeric, text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Aplicar lo que quedó a cuenta
-- ---------------------------------------------------------------------------
create function purchasing.apply_payment_credit(p_payment_id uuid, p_allocations jsonb, p_reason text)
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
  select * into v_p from purchasing.payments where id = p_payment_id for update;
  perform 1 from purchasing.invoices
   where id in (select (x ->> 'invoice_id')::uuid from jsonb_array_elements(p_allocations) x)
     for update;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  for v_item in select value from jsonb_array_elements(p_allocations) loop
    perform purchasing.allocate_payment(v_p.id, (v_item ->> 'invoice_id')::uuid, (v_item ->> 'amount')::numeric);
  end loop;
  return jsonb_build_object('result', 'applied', 'payment_id', v_p.id,
                            'unapplied', round(purchasing.payment_unapplied(v_p.id), 2));
exception
  when check_violation then
    raise exception '%', sqlerrm using errcode = '23514';
end
$$;
comment on function purchasing.apply_payment_credit(uuid, jsonb, text) is
  'Aplica lo que quedó a cuenta de un pago a facturas liberadas del mismo local y proveedor ([{invoice_id, amount}]). Pide purchasing.pay en el local y un motivo.';
revoke execute on function purchasing.apply_payment_credit(uuid, jsonb, text) from public;
grant execute on function purchasing.apply_payment_credit(uuid, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. El efectivo pagado al recibir
-- ---------------------------------------------------------------------------
-- Al cerrar una recepción con efectivo, nace el pago «para confirmar» (decisión 7 de Soy).
create function purchasing.on_receipt_closed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'closed' and old.status = 'open' and new.cash_paid_amount is not null then
    insert into purchasing.payments (group_id, brand_id, restaurant_id, supplier_id, paid_on, method, payment_amount,
                                     receipt_id, status)
    values (new.group_id, new.brand_id, new.restaurant_id, new.supplier_id,
            (new.closed_at at time zone 'America/Argentina/Buenos_Aires')::date, 'cash', new.cash_paid_amount,
            new.id, 'to_confirm');
  end if;
  return new;
end
$$;
comment on function purchasing.on_receipt_closed() is
  'Interna: al cerrar una recepción donde se pagó en efectivo, crea el pago «para confirmar» de ese local y proveedor.';
revoke execute on function purchasing.on_receipt_closed() from public;
create trigger on_receipt_closed after update of status on purchasing.receipts
  for each row execute function purchasing.on_receipt_closed();

-- Compras confirma el efectivo (con el importe corregido, si hace falta) y queda a cuenta; si la factura de esa
-- recepción ya está liberada, se aplica.
create function purchasing.confirm_cash_payment(p_id uuid, p_amount numeric, p_reason text)
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
comment on function purchasing.confirm_cash_payment(uuid, numeric, text) is
  'Confirma el efectivo pagado al recibir (con el importe corregido, si hace falta): queda registrado a cuenta y, si la factura de esa recepción ya está liberada, se le aplica (decisión de Joaco, 2026-11-18). Pide purchasing.pay en el local y un motivo.';
revoke execute on function purchasing.confirm_cash_payment(uuid, numeric, text) from public;
grant execute on function purchasing.confirm_cash_payment(uuid, numeric, text) to authenticated;

-- Cuando una factura queda liberada, se le aplica el efectivo confirmado de la recepción de su OC.
create function purchasing.on_invoice_released()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment uuid;
begin
  if new.status = 'released' and old.status <> 'released' and old.status <> 'paid' then
    for v_payment in
      select p.id from purchasing.payments p
        join purchasing.receipts r on r.id = p.receipt_id
        join purchasing.invoice_orders io on io.purchase_order_id = r.purchase_order_id and io.deleted_at is null
       where io.invoice_id = new.id and p.deleted_at is null and p.status in ('registered', 'receipt_queued')
         and p.restaurant_id = new.restaurant_id and p.supplier_id = new.supplier_id
       order by p.paid_on
    loop
      perform purchasing.apply_receipt_cash(v_payment);
    end loop;
  end if;
  return new;
end
$$;
comment on function purchasing.on_invoice_released() is
  'Interna: cuando una factura queda liberada, le aplica el efectivo confirmado de la recepción de su OC, hasta su saldo (decisión de Joaco, 2026-11-18).';
revoke execute on function purchasing.on_invoice_released() from public;
create trigger on_invoice_released after update of status on purchasing.invoices
  for each row execute function purchasing.on_invoice_released();

-- ---------------------------------------------------------------------------
-- 5. Anular un pago
-- ---------------------------------------------------------------------------
-- Una factura pagada vuelve a liberada si al anular un pago le queda saldo. Se suma esa vuelta a guard_invoice.
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
               or (old.status = 'paid' and new.status = 'released')) then
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
comment on function purchasing.guard_invoice() is
  'Interna: el CUIT del emisor tiene que ser válido y el del proveedor (nunca el de ejemplo 99-99999999-9); una factura conforme, liberada, pagada o cancelada no cambia más que su estado (y una pagada vuelve a liberada solo si al anular un pago le queda saldo); ninguna se borra.';

create function purchasing.void_payment(p_id uuid, p_reason text)
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
  select * into v_p from purchasing.payments where id = p_id for update;
  if v_p.status = 'voided' then
    raise exception 'Este pago ya está anulado.' using errcode = '23514';
  end if;
  perform 1 from purchasing.invoices i
   where i.id in (select a.invoice_id from purchasing.payment_allocations a where a.payment_id = v_p.id)
     for update;
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
comment on function purchasing.void_payment(uuid, text) is
  'Anula un pago, con motivo: sus aplicaciones dejan de contar, las facturas que quedan con saldo vuelven a liberadas y el aviso en cola se cancela. Pide purchasing.pay en el local.';
revoke execute on function purchasing.void_payment(uuid, text) from public;
grant execute on function purchasing.void_payment(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. El comprobante del pago
-- ---------------------------------------------------------------------------
create function purchasing.add_payment_attachment(p_payment_id uuid, p_storage_path text, p_page smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p  purchasing.payments;
  v_id uuid;
begin
  select * into v_p from purchasing.payments where id = p_payment_id and deleted_at is null;
  if v_p.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_p.restaurant_id) then
    return core.deny('purchasing.add_payment_attachment', 'No tenés permiso para sumar el comprobante de este pago.',
                     null, jsonb_build_object('payment_id', p_payment_id), v_p.group_id, v_p.brand_id, v_p.restaurant_id);
  end if;
  if v_p.status = 'voided' then
    raise exception 'Un pago anulado no lleva comprobante.' using errcode = '23514';
  end if;
  if coalesce(p_page, 1) not between 1 and 20 then
    raise exception 'Van hasta 20 páginas por archivo.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.document_parts(p_storage_path) d
                  where d.group_id = v_p.group_id and d.source_table = 'payments' and d.source_id = v_p.id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'purchasing-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'El archivo no está subido en la carpeta de este pago.' using errcode = '22023';
  end if;
  perform core.set_change_context('Comprobante del pago', 'manual');
  insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
  values (v_p.group_id, 'payments', v_p.id, 'payment_receipt', coalesce(p_page, 1), p_storage_path)
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;
comment on function purchasing.add_payment_attachment(uuid, text, smallint) is
  'Registra el comprobante ya subido (foto o PDF) de un pago no anulado. Pide purchasing.pay en el local.';
revoke execute on function purchasing.add_payment_attachment(uuid, text, smallint) from public;
grant execute on function purchasing.add_payment_attachment(uuid, text, smallint) to authenticated;

create or replace function purchasing.can_upload_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case d.source_table
             when 'price_lists' then
               core.has_permission_in_group('purchasing.manage_price_lists', d.group_id)
               and exists (select 1 from purchasing.price_lists l
                            where l.id = d.source_id and l.group_id = d.group_id and l.deleted_at is null
                              and l.status = 'received')
             when 'receipts' then
               p_name ~ '\.jpg$'
               and exists (select 1 from purchasing.receipts r
                            where r.id = d.source_id and r.group_id = d.group_id and r.deleted_at is null
                              and r.status = 'open'
                              and purchasing.can_in_restaurant('purchasing.receive', r.restaurant_id))
             when 'invoices' then
               p_name ~ '\.(jpg|pdf)$'
               and exists (select 1 from purchasing.invoices i
                            where i.id = d.source_id and i.group_id = d.group_id and i.deleted_at is null
                              and i.status in ('loaded', 'observed')
                              and purchasing.can_in_restaurant('purchasing.manage_invoices', i.restaurant_id))
             when 'credit_debit_notes' then
               p_name ~ '\.(jpg|pdf)$'
               and exists (select 1 from purchasing.credit_debit_notes n
                             join purchasing.invoices i on i.id = n.invoice_id
                            where n.id = d.source_id and n.group_id = d.group_id and n.deleted_at is null
                              and i.status in ('loaded', 'observed', 'approved', 'released')
                              and purchasing.can_in_restaurant('purchasing.manage_invoices', i.restaurant_id))
             when 'payments' then
               p_name ~ '\.(jpg|pdf)$'
               and exists (select 1 from purchasing.payments p
                            where p.id = d.source_id and p.group_id = d.group_id and p.deleted_at is null
                              and p.status <> 'voided'
                              and purchasing.can_in_restaurant('purchasing.pay', p.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_upload_document(text) is
  'Si la sesión puede subir ese archivo, con nombre <grupo>/<tabla>/<registro>/<uuid>.<ext>: una lista recibida del grupo (purchasing.manage_price_lists); una foto .jpg de una recepción abierta (purchasing.receive en su local); la foto (.jpg) o el PDF de una factura cargada u observada, o de una nota de una factura que admite notas (purchasing.manage_invoices en su local); el comprobante (.jpg o .pdf) de un pago no anulado (purchasing.pay en su local).';

create or replace function purchasing.can_read_own_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case d.source_table
             when 'price_lists' then core.has_permission_in_group('purchasing.manage_price_lists', d.group_id)
             when 'receipts' then
               exists (select 1 from purchasing.receipts r
                        where r.id = d.source_id and r.group_id = d.group_id and r.deleted_at is null
                          and r.status = 'open'
                          and purchasing.can_in_restaurant('purchasing.receive', r.restaurant_id))
             when 'invoices' then
               exists (select 1 from purchasing.invoices i
                        where i.id = d.source_id and i.group_id = d.group_id and i.deleted_at is null
                          and purchasing.can_in_restaurant('purchasing.manage_invoices', i.restaurant_id))
             when 'credit_debit_notes' then
               exists (select 1 from purchasing.credit_debit_notes n
                         join purchasing.invoices i on i.id = n.invoice_id
                        where n.id = d.source_id and n.group_id = d.group_id and n.deleted_at is null
                          and purchasing.can_in_restaurant('purchasing.manage_invoices', i.restaurant_id))
             when 'payments' then
               exists (select 1 from purchasing.payments p
                        where p.id = d.source_id and p.group_id = d.group_id and p.deleted_at is null
                          and purchasing.can_in_restaurant('purchasing.pay', p.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_read_own_document(text) is
  'Si la sesión puede leer un archivo que acaba de subir, antes de registrarlo: carga listas en el grupo de la carpeta, recibe en el local de la recepción abierta, carga facturas en el local de la factura (o de la nota) o paga en el local del pago. La política de Storage exige además que lo haya subido ella.';

create or replace function purchasing.visible_document_paths()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select a.storage_path from purchasing.attachments a
   where a.source_table = 'price_lists'
     and a.group_id in (select core.visible_group_ids('purchasing.view_price_lists'))
  union all
  select a.storage_path from purchasing.attachments a
    join purchasing.receipts r on r.id = a.source_id
   where a.source_table = 'receipts' and r.deleted_at is null
     and r.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_orders'))
  union all
  select a.storage_path from purchasing.attachments a
    join purchasing.receipt_lines l on l.id = a.source_id
    join purchasing.receipts r on r.id = l.receipt_id
   where a.source_table = 'receipt_lines' and r.deleted_at is null and l.deleted_at is null
     and r.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_orders'))
  union all
  select a.storage_path from purchasing.attachments a
    join purchasing.invoices i on i.id = a.source_id
   where a.source_table = 'invoices' and i.deleted_at is null
     and i.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_invoices'))
  union all
  select a.storage_path from purchasing.attachments a
    join purchasing.credit_debit_notes n on n.id = a.source_id
    join purchasing.invoices i on i.id = n.invoice_id
   where a.source_table = 'credit_debit_notes' and i.deleted_at is null and n.deleted_at is null
     and i.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_invoices'))
  union all
  select a.storage_path from purchasing.attachments a
    join purchasing.payments p on p.id = a.source_id
   where a.source_table = 'payments' and p.deleted_at is null
     and p.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_payments'))
$$;
comment on function purchasing.visible_document_paths() is
  'Archivos de compras registrados que la sesión ve: los de las listas de su grupo (purchasing.view_price_lists), las fotos de las recepciones de los locales cuyas OC ve (purchasing.view_orders), las de las facturas y notas de los locales donde ve facturas (purchasing.view_invoices) y los comprobantes de pago de los locales donde ve pagos (purchasing.view_payments). Para la política de lectura de Storage.';

drop policy attachments_select on purchasing.attachments;
create policy attachments_select on purchasing.attachments for select to authenticated
  using ((source_table = 'price_lists'
          and group_id in (select core.visible_group_ids('purchasing.view_price_lists')))
         or (source_table = 'receipts' and source_id in (select id from purchasing.receipts))
         or (source_table = 'receipt_lines' and source_id in (select id from purchasing.receipt_lines))
         or (source_table = 'invoices' and source_id in (select id from purchasing.invoices))
         or (source_table = 'credit_debit_notes' and source_id in (select id from purchasing.credit_debit_notes))
         or (source_table = 'payments' and source_id in (select id from purchasing.payments)));

-- ---------------------------------------------------------------------------
-- 7. Avisos de vencimiento (una vez por factura a 7 días y una vez al vencer)
-- ---------------------------------------------------------------------------
create function purchasing.notify_due_payments(p_day date default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day   date := coalesce(p_day, recipes.today());
  v_inv   record;
  v_count integer := 0;
  v_title text;
begin
  for v_inv in
    select i.id, i.group_id, i.due_on, purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number) as label,
           coalesce(s.trade_name, s.name) as supplier, purchasing.invoice_balance(i.id) as balance
      from purchasing.invoices i
      join catalog.suppliers s on s.id = i.supplier_id
     where i.deleted_at is null and i.status = 'released' and i.due_on <= v_day + 7
  loop
    continue when v_inv.balance <= 0.005;
    v_title := left(case when v_inv.due_on < v_day then format('Venció la %s de %s', v_inv.label, v_inv.supplier)
                         else format('Vence la %s de %s', v_inv.label, v_inv.supplier) end, 200);
    -- Una vez «por vencer» y una vez «venció» por factura.
    continue when exists (select 1 from core.notifications n
                           where n.kind = 'payment_due' and n.link = format('/compras/facturas/%s', v_inv.id)
                             and (n.title like 'Venció%') = (v_inv.due_on < v_day));
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u, v_inv.group_id, 'payment_due', v_title,
           left(format('Saldo %s. Vence el %s.', purchasing.money_text(v_inv.balance), to_char(v_inv.due_on, 'DD/MM/YYYY')),
                500),
           format('/compras/facturas/%s', v_inv.id)
      from purchasing.users_with_permission(v_inv.group_id, 'purchasing.pay') u;
    v_count := v_count + 1;
  end loop;
  return v_count;
end
$$;
comment on function purchasing.notify_due_payments(date) is
  'Avisa a quien paga (purchasing.pay) las facturas liberadas con saldo que vencen en 7 días o menos y las que vencieron: una vez «vence» y una vez «venció» por factura. La corre el trabajo diario de compras. Devuelve cuántas facturas avisó.';
revoke execute on function purchasing.notify_due_payments(date) from public;

select cron.schedule('grupo-lf-compras-diario', '45 9 * * *',
                     'select purchasing.notify_expired_price_lists(); select purchasing.notify_due_payments()');
