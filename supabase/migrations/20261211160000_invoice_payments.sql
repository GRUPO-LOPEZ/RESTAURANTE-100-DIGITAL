-- El saldo de una factura y los pagos que la cancelan, para la ficha de la factura (Fase 3, Prompt 6, ADR-0060).
-- El saldo sale de purchasing.invoice_balance (la única cuenta: total − NC − descuentos + ND − pagos aplicados), no se
-- vuelve a calcular en la pantalla. Solo para quien ve pagos en el local de la factura; si no, nulo.

create function purchasing.invoice_payments(p_invoice_id uuid)
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
     and i.restaurant_id in (select x from core.permitted_restaurant_ids('purchasing.view_payments') x)
$$;
comment on function purchasing.invoice_payments(uuid) is
  'Saldo de una factura (purchasing.invoice_balance) y los pagos vigentes que la cancelan: fecha, medio, referencia y lo aplicado. Nulo si la sesión no ve pagos en su local.';
revoke execute on function purchasing.invoice_payments(uuid) from public;
grant execute on function purchasing.invoice_payments(uuid) to authenticated;
