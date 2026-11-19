-- Fase 3, Prompt 6 (ADR-0060): correcciones de la revisión de base y de seguridad de los pagos.
--
-- - Un pago no se aplica por más de lo que vale, ni con dos operaciones a la vez: la aplicación bloquea el pago y la
--   factura (y la liberación de una factura bloquea primero los pagos de efectivo de su OC, en el mismo orden).
-- - Una nota de crédito que llega después de pagar (decisión de Joaco, 2026-11-18): se acepta también en una factura
--   pagada; si deja la factura pagada de más, lo de más vuelve a quedar a cuenta del pago y la factura queda pagada.
--   Una nota de débito sobre una pagada la vuelve a liberada, con su saldo.
-- - Una factura pagada vuelve a liberada solo si tiene saldo (lo valida la base).
-- - Sin tolerancia en los centavos: no se aplica ni un centavo de más.
-- - Los renglones de un pago se validan antes (factura y monto), con errores en español.
-- - La moneda del pago; las notas del pago no cambian.
-- - «Registrar pago» trae el proveedor del grupo del local y hasta 50 facturas; el tablero, hasta 20 alarmas (con el
--   total por tipo), y las de todo el grupo solo para quien ve listas o mapea artículos.
-- - Índice para los avisos de vencimiento.

alter table purchasing.payments add column currency text not null default 'ARS' check (currency = 'ARS');
comment on column purchasing.payments.currency is 'Moneda del pago (por ahora, solo pesos).';

create index notifications_payment_due_idx on core.notifications (link) where kind = 'payment_due';

-- La aplicación bloquea el pago y la factura, sin tolerancia; el ajuste interno da de baja lo pagado de más.
create or replace function purchasing.guard_payment_allocation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_p purchasing.payments;
  v_i purchasing.invoices;
begin
  -- Solo el ajuste interno de una nota tardía (purchasing.release_overpayment) da de baja una aplicación.
  if tg_op = 'UPDATE' and current_setting('purchasing.adjusting', true) = 'on'
     and (to_jsonb(new) - array['deleted_at', 'deleted_by', 'updated_at', 'updated_by'])
         = (to_jsonb(old) - array['deleted_at', 'deleted_by', 'updated_at', 'updated_by'])
     and old.deleted_at is null and new.deleted_at is not null then
    return new;
  end if;
  if tg_op <> 'INSERT' then
    raise exception 'Una aplicación de un pago no se cambia ni se borra: se anula el pago.' using errcode = '42501';
  end if;
  -- Dos operaciones a la vez sobre el mismo pago o la misma factura: la segunda espera y ve lo que hizo la primera.
  select * into v_p from purchasing.payments where id = new.payment_id for update;
  select * into v_i from purchasing.invoices where id = new.invoice_id for update;
  if v_p.status not in ('registered', 'receipt_queued') then
    raise exception 'Solo se aplica un pago registrado.' using errcode = '23514';
  end if;
  if v_i.restaurant_id <> v_p.restaurant_id or v_i.supplier_id <> v_p.supplier_id then
    raise exception 'El pago y la factura tienen que ser del mismo local y proveedor.' using errcode = '23514';
  end if;
  if v_i.status <> 'released' and not (v_i.status = 'paid' and current_setting('purchasing.adjusting', true) = 'on') then
    raise exception 'Solo se paga una factura liberada.' using errcode = '23514';
  end if;
  if coalesce((select sum(a.allocated_amount) from purchasing.payment_allocations a
                where a.payment_id = new.payment_id and a.deleted_at is null), 0) + new.allocated_amount
       > v_p.payment_amount then
    raise exception 'Lo aplicado no puede superar el pago.' using errcode = '23514';
  end if;
  if purchasing.invoice_balance(new.invoice_id) - new.allocated_amount < 0 then
    raise exception 'No se puede aplicar más que el saldo de la factura.' using errcode = '23514';
  end if;
  return new;
end
$$;

comment on function purchasing.guard_payment_allocation() is
  'Interna: una aplicación es de un pago registrado y de una factura liberada del mismo local y proveedor; bloquea el pago y la factura, y no supera el saldo de la factura ni lo que queda del pago (sin tolerancia). No se cambia ni se borra, salvo el ajuste interno de una nota tardía.';

-- Las notas de un pago tampoco cambian.
create or replace function purchasing.guard_payment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un pago no se borra: se anula, con motivo.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' then
    if old.status = 'voided' then
      raise exception 'Un pago anulado no cambia.' using errcode = '42501';
    end if;
    -- Solo cambia el estado (para confirmar → registrado → con aviso en cola, o anulado) y, al confirmar el efectivo,
    -- su importe y su fecha.
    if (to_jsonb(new) - array['status', 'voided_reason', 'voided_at', 'voided_by', 'updated_at', 'updated_by',
                             'payment_amount', 'paid_on'])
         is distinct from (to_jsonb(old) - array['status', 'voided_reason', 'voided_at', 'voided_by', 'updated_at',
                                                 'updated_by', 'payment_amount', 'paid_on'])
       or ((new.payment_amount, new.paid_on) is distinct from (old.payment_amount, old.paid_on)
           and old.status <> 'to_confirm')
       or not (new.status = old.status
               or (old.status = 'to_confirm' and new.status in ('registered', 'voided'))
               or (old.status = 'registered' and new.status in ('receipt_queued', 'voided'))
               or (old.status = 'receipt_queued' and new.status = 'voided')) then
      raise exception 'Un pago registrado no cambia: anulalo, con motivo, y registralo de nuevo.' using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;

-- Lo pagado de más (una nota de crédito que llegó después de pagar) vuelve a quedar a cuenta: se achican las
-- aplicaciones más nuevas de esa factura hasta que su saldo quede en cero (decisión de Joaco, 2026-11-18).
create function purchasing.release_overpayment(p_invoice_id uuid)
returns numeric
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_excess numeric := -purchasing.invoice_balance(p_invoice_id);
  v_back   numeric := 0;
  v_a      record;
  v_cut    numeric;
begin
  if v_excess <= 0 then
    return 0;
  end if;
  perform set_config('purchasing.adjusting', 'on', true);
  for v_a in
    select a.* from purchasing.payment_allocations a join purchasing.payments p on p.id = a.payment_id
     where a.invoice_id = p_invoice_id and a.deleted_at is null and p.status in ('registered', 'receipt_queued')
     order by a.created_at desc, a.id desc
       for update of a, p
  loop
    exit when v_excess <= 0;
    v_cut := least(v_excess, v_a.allocated_amount);
    update purchasing.payment_allocations set deleted_at = now(), deleted_by = core.current_actor_id() where id = v_a.id;
    if v_a.allocated_amount - v_cut > 0 then
      insert into purchasing.payment_allocations (group_id, payment_id, invoice_id, allocated_amount)
      values (v_a.group_id, v_a.payment_id, v_a.invoice_id, v_a.allocated_amount - v_cut);
    end if;
    v_excess := v_excess - v_cut;
    v_back := v_back + v_cut;
  end loop;
  perform set_config('purchasing.adjusting', 'off', true);
  return v_back;
end
$$;
comment on function purchasing.release_overpayment(uuid) is
  'Interna: si una factura quedó pagada de más (una nota de crédito llegó después de pagar), achica sus aplicaciones más nuevas hasta dejar su saldo en cero; lo de más vuelve a cuenta de esos pagos. Devuelve cuánto volvió a cuenta.';
revoke execute on function purchasing.release_overpayment(uuid) from public;

-- Una nota sobre una factura liberada o pagada ajusta su estado y su saldo en la misma transacción.
create function purchasing.on_note_added()
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
  if v_inv.status = 'released' and v_balance <= 0 then
    update purchasing.invoices set status = 'paid' where id = v_inv.id;
  elsif v_inv.status = 'paid' and v_balance > 0 then
    update purchasing.invoices set status = 'released' where id = v_inv.id;
  end if;
  return new;
end
$$;
comment on function purchasing.on_note_added() is
  'Interna: una nota sobre una factura liberada o pagada ajusta su estado: si la deja pagada de más, lo de más vuelve a cuenta y queda pagada; si queda sin saldo, pasa a pagada; si una nota de débito le suma saldo a una pagada, vuelve a liberada.';
revoke execute on function purchasing.on_note_added() from public;
create trigger on_note_added after insert on purchasing.credit_debit_notes
  for each row execute function purchasing.on_note_added();

-- Una nota también entra a una factura pagada (la que llega después de pagar).
create or replace function purchasing.guard_note()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'Una nota de crédito o débito no se cambia ni se borra: se corrige con otra nota.' using errcode = '42501';
  end if;
  if (select status from purchasing.invoices where id = new.invoice_id) not in ('loaded', 'observed', 'approved',
                                                                                'released', 'paid') then
    raise exception 'A esta factura no se le suman notas.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function purchasing.guard_note() is
  'Interna: una nota de crédito, débito o descuento no se cambia ni se borra, y no entra a una factura cancelada. Entra también a una pagada (la nota que llega después de pagar, ADR-0060).';

-- La foto de una nota sobre una factura pagada.
create or replace function purchasing.add_invoice_attachment(p_source_table text, p_source_id uuid, p_storage_path text,
                                                  p_page smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv  purchasing.invoices;
  v_kind purchasing.doc_kind;
  v_id   uuid;
begin
  if p_source_table = 'invoices' then
    select * into v_inv from purchasing.invoices where id = p_source_id and deleted_at is null;
    v_kind := 'invoice_original';
  elsif p_source_table = 'credit_debit_notes' then
    select i.* into v_inv from purchasing.invoices i
      join purchasing.credit_debit_notes n on n.invoice_id = i.id
     where n.id = p_source_id and n.deleted_at is null and i.deleted_at is null;
    v_kind := 'credit_note';
  end if;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.add_invoice_attachment', 'No tenés permiso para sumar archivos a esta factura.', null,
                     jsonb_build_object('source_table', p_source_table, 'source_id', p_source_id),
                     v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if (p_source_table = 'invoices' and v_inv.status not in ('loaded', 'observed'))
     or (p_source_table = 'credit_debit_notes' and v_inv.status not in ('loaded', 'observed', 'approved', 'released', 'paid')) then
    raise exception 'Una factura conforme no cambia: corregila con una nota de crédito o débito.' using errcode = '23514';
  end if;
  if coalesce(p_page, 1) not between 1 and 20 then
    raise exception 'Van hasta 20 páginas por archivo.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.document_parts(p_storage_path) d
                  where d.group_id = v_inv.group_id and d.source_table = p_source_table and d.source_id = p_source_id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'purchasing-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'El archivo no está subido en la carpeta de esta factura.' using errcode = '22023';
  end if;
  perform core.set_change_context(case v_kind when 'invoice_original' then 'Foto de la factura'
                                              else 'Foto de la nota de crédito o débito' end, 'manual');
  insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
  values (v_inv.group_id, p_source_table, p_source_id, v_kind, coalesce(p_page, 1), p_storage_path)
  returning id into v_id;
  if v_kind = 'invoice_original' then
    update purchasing.invoices i
       set edited_by = case when core.current_actor_id() = any (i.edited_by) then i.edited_by
                            else i.edited_by || core.current_actor_id() end
     where i.id = v_inv.id;
  end if;
  if v_kind = 'credit_note' and v_inv.status in ('loaded', 'observed') then
    return jsonb_build_object('result', 'applied', 'attachment_id', v_id, 'status', purchasing.check_invoice(v_inv.id));
  end if;
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;

-- Storage: la foto de una nota sobre una factura pagada.
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
                              and i.status in ('loaded', 'observed', 'approved', 'released', 'paid')
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

-- Una factura pagada vuelve a liberada solo si tiene saldo.
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
               or (old.status = 'paid' and new.status = 'released' and purchasing.invoice_balance(new.id) > 0)) then
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

-- Al liberar una factura, primero se bloquean los pagos de efectivo de su OC (también los «para confirmar»): el
-- mismo orden que confirmar o aplicar, sin cruces.
create or replace function purchasing.on_invoice_released()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment uuid;
begin
  if new.status = 'released' and old.status <> 'released' and old.status <> 'paid' then
    perform 1 from purchasing.payments p
      join purchasing.receipts r on r.id = p.receipt_id
      join purchasing.invoice_orders io on io.purchase_order_id = r.purchase_order_id and io.deleted_at is null
     where io.invoice_id = new.id and p.deleted_at is null and p.status in ('to_confirm', 'registered', 'receipt_queued')
       for update of p;
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

-- Interna: valida los renglones de un pago ([{invoice_id, amount}]) antes de aplicarlos.
create function purchasing.check_payment_lines(p_lines jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_item jsonb;
begin
  if p_lines is null then
    return;
  end if;
  if jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Las facturas a pagar no se entienden.' using errcode = '22023';
  end if;
  for v_item in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_item) <> 'object'
       or coalesce(v_item ->> 'invoice_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'Una de las facturas a pagar no se entiende.' using errcode = '22023';
    end if;
    if coalesce(jsonb_typeof(v_item -> 'amount'), '') <> 'number' or (v_item ->> 'amount')::numeric <= 0
       or (v_item ->> 'amount')::numeric >= 10000000000 then
      raise exception 'Escribí cuánto se paga de cada factura (mayor que cero).' using errcode = '22023';
    end if;
  end loop;
  if (select count(*) <> count(distinct x ->> 'invoice_id') from jsonb_array_elements(p_lines) x) then
    raise exception 'Una factura va una sola vez en el mismo pago.' using errcode = '22023';
  end if;
end
$$;
comment on function purchasing.check_payment_lines(jsonb) is
  'Interna: cada renglón de un pago lleva una factura (uuid, una sola vez) y un monto mayor que cero; si no, un error en español.';
revoke execute on function purchasing.check_payment_lines(jsonb) from public;

-- Aplicar de nuevo un pago a una factura que ya tiene parte de ese pago: se suma a esa aplicación.
create or replace function purchasing.allocate_payment(p_payment_id uuid, p_invoice_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
  v_prior purchasing.payment_allocations;
begin
  if p_amount is null or p_amount <= 0 then
    return;
  end if;
  select group_id into v_group from purchasing.payments where id = p_payment_id;
  select * into v_prior from purchasing.payment_allocations
   where payment_id = p_payment_id and invoice_id = p_invoice_id and deleted_at is null
     for update;
  if v_prior.id is not null then
    -- La aplicación anterior se da de baja y entra una con la suma (el trigger controla el saldo y el pago).
    perform set_config('purchasing.adjusting', 'on', true);
    update purchasing.payment_allocations set deleted_at = now(), deleted_by = core.current_actor_id()
     where id = v_prior.id;
    perform set_config('purchasing.adjusting', 'off', true);
    p_amount := p_amount + v_prior.allocated_amount;
  end if;
  -- El trigger guard_payment_allocation controla local, proveedor, estado y que no pase el saldo ni el pago.
  insert into purchasing.payment_allocations (group_id, payment_id, invoice_id, allocated_amount)
  values (v_group, p_payment_id, p_invoice_id, round(p_amount, 4));
  if purchasing.invoice_balance(p_invoice_id) <= 0.005 then
    update purchasing.invoices set status = 'paid' where id = p_invoice_id and status = 'released';
  end if;
end
$$;

-- Registrar: los renglones y el importe se validan antes, con errores en español.
create or replace function purchasing.register_payment(p_restaurant_id uuid, p_supplier_id uuid, p_paid_on date,
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
  if p_amount >= 10000000000 then
    raise exception 'El importe es demasiado grande: revisalo.' using errcode = '22023';
  end if;
  if p_method <> 'cash' and not exists (
       select 1 from purchasing.supplier_payment_accounts a
        where a.id = p_account_id and a.supplier_id = v_s.id and a.method = p_method and a.is_active
          and a.deleted_at is null) then
    raise exception 'Elegí una cuenta activa del proveedor para ese medio de pago.' using errcode = '22023';
  end if;
  perform purchasing.check_payment_lines(p_allocations);
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

-- Aplicar lo que quedó a cuenta: los renglones se validan antes y el error sale en español.
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
    -- Los mensajes de las guardas ya están en español; una restricción sin traducir no se muestra cruda.
    if sqlerrm ~ 'violates' then
      raise exception 'Revisá lo que se aplica a cada factura.' using errcode = '23514';
    end if;
    raise exception '%', sqlerrm using errcode = '23514';
end
$$;

-- «Registrar pago»: el proveedor tiene que ser del grupo del local, y van hasta 50 facturas (con el total).
create or replace function purchasing.payable_invoices(p_restaurant_id uuid, p_supplier_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when purchasing.can_in_restaurant('purchasing.pay', p_restaurant_id)
                   and exists (select 1 from catalog.suppliers s join org.restaurants r on r.group_id = s.group_id
                                where s.id = p_supplier_id and r.id = p_restaurant_id) then jsonb_build_object(
    'invoice_count', (select count(*) from reporting.v_payment_schedule d
                       where d.restaurant_id = p_restaurant_id and d.supplier_id = p_supplier_id),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_id', d.invoice_id,
               'label', purchasing.invoice_label(d.invoice_class, d.point_of_sale, d.number),
               'issued_on', d.issued_on, 'due_on', d.due_on, 'balance', d.balance_amount, 'due_state', d.due_state)
               order by d.due_on, d.issued_on)
        from (select * from reporting.v_payment_schedule d0
               where d0.restaurant_id = p_restaurant_id and d0.supplier_id = p_supplier_id
               order by d0.due_on, d0.issued_on limit 50) d), '[]'::jsonb),
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

-- El tablero: hasta 20 alarmas (lo más grave primero) y el total por tipo; las alarmas de todo el grupo (lista
-- vencida, artículo sin mapear) solo para quien ve listas o mapea artículos.
create or replace function purchasing.purchasing_dashboard(p_restaurant_id uuid default null)
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
  v_all     jsonb;
  v_lists   boolean;
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
  -- La lista vencida es de todo el grupo: solo para quien ve listas (el chef no).
  v_lists := exists (select 1 from core.visible_group_ids('purchasing.view_price_lists') g where g = any (v_groups));
  select coalesce(jsonb_agg(jsonb_build_object('kind', a.kind, 'severity', a.severity, 'title', a.title,
                                               'link', a.link, 'since', a.since)
                            order by case a.severity when 'bad' then 0 when 'warn' then 1 else 2 end, a.since), '[]')
    into v_all
    from reporting.v_purchasing_alerts a
   where (a.restaurant_id = any (v_places) or (a.restaurant_id is null and a.group_id = any (v_groups)))
     -- Quien no ve importes no recibe las alarmas de plata.
     and (v_amounts or a.kind not in ('payment_due', 'payment_overdue', 'cash_to_confirm'))
     and (v_lists or a.kind <> 'price_list_expired');
  select jsonb_build_object(
    'can_see_amounts', v_amounts,
    'alerts', coalesce((select jsonb_agg(t.e order by t.i)
                          from jsonb_array_elements(v_all) with ordinality as t (e, i) where t.i <= 20), '[]'::jsonb),
    'alert_count', jsonb_array_length(v_all),
    'alert_kinds', coalesce((select jsonb_object_agg(k.kind, k.n)
                               from (select e ->> 'kind' as kind, count(*) as n from jsonb_array_elements(v_all) e
                                      group by 1) k), '{}'::jsonb),
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

-- Lo que dice el permiso del tablero es lo que hace: los importes, para quien ve pagos (decisión de Joaco, 2026-11-18).
do $$
begin
  perform core.set_change_context('El tablero muestra importes a quien ve pagos (ADR-0060)', 'maintenance');
  update core.permissions
     set description = 'Ver el tablero de compras: alarmas, facturas observadas, vencimientos, órdenes abiertas, gasto por rubro y cómo subieron los insumos. Los importes, solo si además ve los pagos de esos locales.'
   where code = 'purchasing.view_dashboard';
end
$$;
