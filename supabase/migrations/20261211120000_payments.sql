-- Fase 3, Prompt 6 (ADR-0060): pagos a proveedores y qué factura cancela cada uno. Esta migración crea los permisos, los
-- tipos, las tablas y el saldo de una factura; las funciones están en 20261211130000_payment_functions.sql y las vistas
-- de la cuenta corriente, la agenda, las alarmas y el tablero en 20261211140000_purchasing_reporting.sql.
--
-- - Un pago es de un local y un proveedor (decisión de Joaco, 2026-11-18): una transferencia por dos locales son dos
--   pagos con la misma referencia. Se aplica a una o más facturas liberadas del mismo local y proveedor; lo que no se
--   aplica queda a cuenta.
-- - El efectivo que se pagó al recibir (Prompt 4, decisión 7 de Soy) entra como pago «para confirmar». Compras lo
--   confirma y queda a cuenta; cuando la factura de esa recepción queda conforme, se aplica solo (decisión de Joaco).
-- - El saldo de una factura se calcula siempre: total − notas de crédito y descuentos + notas de débito − pagos
--   aplicados. Cuando llega a cero, la factura pasa a pagada en la misma transacción.
-- - Un pago no se cambia ni se borra: se anula, con motivo, y sus aplicaciones dejan de contar.
-- - Dinero en numeric(18,4) con nombres _amount: core.hide_costs los esconde a quien no ve costos.

-- ---------------------------------------------------------------------------
-- 1. Permisos
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de pagos y tablero de compras (Fase 3, ADR-0060)', 'maintenance');
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('purchasing.view_payments', 'purchasing', 'view_payments', 'Ver pagos', 140,
     'Ver los pagos a proveedores, la agenda de vencimientos y la cuenta corriente de cada proveedor en los locales que ve.',
     false),
    ('purchasing.pay', 'purchasing', 'pay', 'Registrar pagos', 150,
     'Registrar un pago a un proveedor y a qué facturas se aplica, confirmar el efectivo pagado al recibir y anular un pago con motivo.',
     true),
    ('purchasing.view_dashboard', 'purchasing', 'view_dashboard', 'Ver el tablero de compras', 160,
     'Ver el tablero de compras: alarmas, facturas observadas, vencimientos, órdenes abiertas, gasto por rubro y cómo subieron los insumos. Los importes, solo si además ve costos.',
     false);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values
      ('general_management', 'purchasing.view_payments'), ('general_management', 'purchasing.view_dashboard'),
      ('brand_director', 'purchasing.view_payments'), ('brand_director', 'purchasing.view_dashboard'),
      ('restaurant_manager', 'purchasing.view_payments'), ('restaurant_manager', 'purchasing.view_dashboard'),
      ('executive_chef', 'purchasing.view_dashboard'),
      ('controller', 'purchasing.view_payments'), ('controller', 'purchasing.view_dashboard'),
      ('purchasing', 'purchasing.view_payments'), ('purchasing', 'purchasing.pay'),
      ('purchasing', 'purchasing.view_dashboard'),
      ('auditor', 'purchasing.view_payments'), ('auditor', 'purchasing.view_dashboard'),
      -- Regla G2: quien administra personas tiene los permisos de los roles que administra (el superadmin, a Compras).
      ('superadmin', 'purchasing.view_payments'), ('superadmin', 'purchasing.pay'),
      ('superadmin', 'purchasing.view_dashboard')
    ) as v (role_code, permission_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = v.permission_code and p.deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Tipos
-- ---------------------------------------------------------------------------
create type purchasing.payment_status as enum ('to_confirm', 'registered', 'receipt_queued', 'voided');
comment on type purchasing.payment_status is
  'Estado de un pago: to_confirm (efectivo pagado al recibir, falta que Compras lo confirme), registered (registrado), receipt_queued (registrado y con el aviso al proveedor en cola de envío) y voided (anulado, con motivo: sus aplicaciones dejan de contar).';

-- ---------------------------------------------------------------------------
-- 3. Tablas
-- ---------------------------------------------------------------------------
create table purchasing.payments (
  id                  uuid primary key default gen_random_uuid(),
  group_id            uuid not null references org.groups (id) on delete restrict,
  brand_id            uuid not null,
  restaurant_id       uuid not null,
  supplier_id         uuid not null,
  paid_on             date not null check (paid_on >= date '2000-01-01'),
  method              purchasing.payment_method not null,
  payment_account_id  uuid references purchasing.supplier_payment_accounts (id) on delete restrict,
  reference           text check (reference is null or length(btrim(reference)) between 1 and 80),
  payment_amount      numeric(18,4) not null check (payment_amount > 0 and payment_amount < 10000000000),
  withholding_amount  numeric(18,4) check (withholding_amount is null or withholding_amount >= 0),
  receipt_id          uuid references purchasing.receipts (id) on delete restrict,
  status              purchasing.payment_status not null default 'registered',
  notes               text check (notes is null or length(btrim(notes)) between 1 and 500),
  voided_reason       text check (voided_reason is null or length(btrim(voided_reason)) between 3 and 500),
  voided_at           timestamptz,
  voided_by           uuid references core.actors (id) on delete restrict,
  created_at          timestamptz not null default now(),
  created_by          uuid references core.actors (id) on delete restrict,
  updated_at          timestamptz not null default now(),
  updated_by          uuid references core.actors (id) on delete restrict,
  deleted_at          timestamptz,
  deleted_by          uuid references core.actors (id) on delete restrict,
  constraint payments_id_group_key unique (id, group_id),
  constraint payments_restaurant_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint payments_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint payments_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  -- En efectivo no hay cuenta; con cualquier otro medio, sí (una de las cuentas de la ficha del proveedor).
  constraint payments_account_check check ((method = 'cash') = (payment_account_id is null)),
  -- «Para confirmar» es solo el efectivo de una recepción.
  constraint payments_to_confirm_check check (status <> 'to_confirm' or (receipt_id is not null and method = 'cash')),
  constraint payments_void_check check ((status = 'voided') = (voided_reason is not null and voided_at is not null))
);
create unique index payments_receipt_key on purchasing.payments (receipt_id)
  where receipt_id is not null and deleted_at is null;
create index payments_restaurant_idx on purchasing.payments (restaurant_id, supplier_id, paid_on desc)
  where deleted_at is null;
create index payments_restaurant_group_idx on purchasing.payments (restaurant_id, group_id);
create index payments_restaurant_brand_idx on purchasing.payments (restaurant_id, brand_id);
create index payments_supplier_idx on purchasing.payments (supplier_id, group_id);
create index payments_account_idx on purchasing.payments (payment_account_id) where payment_account_id is not null;
create index payments_status_idx on purchasing.payments (group_id, status) where deleted_at is null;
create index payments_group_idx on purchasing.payments (group_id);
create index payments_voided_by_idx on purchasing.payments (voided_by) where voided_by is not null;

comment on table purchasing.payments is
  'Pagos a proveedores, de un local (decisión de Joaco, 2026-11-18). Se aplican a facturas liberadas del mismo local y proveedor (purchasing.payment_allocations); lo que no se aplica queda a cuenta. El efectivo pagado al recibir entra «para confirmar». No se cambia ni se borra: se anula, con motivo. Se escribe solo con funciones.';
comment on column purchasing.payments.group_id is 'Grupo.';
comment on column purchasing.payments.brand_id is 'Marca del local.';
comment on column purchasing.payments.restaurant_id is 'Local que paga (el de las facturas que cancela).';
comment on column purchasing.payments.supplier_id is 'Proveedor al que se le paga.';
comment on column purchasing.payments.paid_on is 'Fecha del pago.';
comment on column purchasing.payments.method is 'Medio de pago.';
comment on column purchasing.payments.payment_account_id is
  'Cuenta del proveedor a la que se pagó (una de su ficha). Vacía en efectivo.';
comment on column purchasing.payments.reference is 'Número de transferencia, de cheque o de operación.';
comment on column purchasing.payments.payment_amount is 'Importe pagado.';
comment on column purchasing.payments.withholding_amount is
  'Retenciones del pago. Preparada: hoy no se calculan (pregunta P8, fuera de esta fase).';
comment on column purchasing.payments.receipt_id is
  'La recepción donde se pagó en efectivo al recibir, si el pago viene de ahí (decisión 7 de Soy).';
comment on column purchasing.payments.status is 'Para confirmar, registrado, con el aviso en cola o anulado.';
comment on column purchasing.payments.notes is 'Observaciones.';
comment on column purchasing.payments.voided_reason is 'Por qué se anuló.';
comment on column purchasing.payments.voided_at is 'Cuándo se anuló.';
comment on column purchasing.payments.voided_by is 'Quién lo anuló.';

create table purchasing.payment_allocations (
  id                uuid primary key default gen_random_uuid(),
  group_id          uuid not null references org.groups (id) on delete restrict,
  payment_id        uuid not null,
  invoice_id        uuid not null,
  allocated_amount  numeric(18,4) not null check (allocated_amount > 0),
  created_at        timestamptz not null default now(),
  created_by        uuid references core.actors (id) on delete restrict,
  updated_at        timestamptz not null default now(),
  updated_by        uuid references core.actors (id) on delete restrict,
  deleted_at        timestamptz,
  deleted_by        uuid references core.actors (id) on delete restrict,
  constraint payment_allocations_payment_fkey foreign key (payment_id, group_id)
    references purchasing.payments (id, group_id) on delete restrict,
  constraint payment_allocations_invoice_fkey foreign key (invoice_id, group_id)
    references purchasing.invoices (id, group_id) on delete restrict
);
create unique index payment_allocations_key on purchasing.payment_allocations (payment_id, invoice_id)
  where deleted_at is null;
create index payment_allocations_invoice_idx on purchasing.payment_allocations (invoice_id, group_id)
  where deleted_at is null;
create index payment_allocations_payment_idx on purchasing.payment_allocations (payment_id, group_id);
create index payment_allocations_group_idx on purchasing.payment_allocations (group_id);

comment on table purchasing.payment_allocations is
  'Qué parte de un pago cancela cada factura. La factura es del mismo local y proveedor que el pago; la suma por factura no supera su saldo y la suma por pago no supera el pago. Las de un pago anulado no cuentan.';
comment on column purchasing.payment_allocations.group_id is 'Grupo, el mismo que el del pago y la factura.';
comment on column purchasing.payment_allocations.payment_id is 'Pago.';
comment on column purchasing.payment_allocations.invoice_id is 'Factura que cancela (en todo o en parte).';
comment on column purchasing.payment_allocations.allocated_amount is 'Cuánto del pago se aplica a esta factura.';

do $$
declare
  t text;
begin
  foreach t in array array['payments', 'payment_allocations'] loop
    execute format('alter table purchasing.%I enable row level security', t);
    execute format('revoke all on purchasing.%I from public, anon, authenticated, service_role', t);
    execute format('grant select on purchasing.%I to authenticated', t);
    execute format(
      'create trigger set_control_columns before insert or update on purchasing.%I
         for each row execute function core.set_control_columns()', t);
    execute format(
      'create trigger log_change after insert or update or delete on purchasing.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on purchasing.%I
         for each statement execute function core.reject_truncate()', t);
    execute format('comment on column purchasing.%I.id is %L', t, 'Identificador.');
    execute format('comment on column purchasing.%I.created_at is %L', t, 'Cuándo se creó (lo pone la base).');
    execute format('comment on column purchasing.%I.created_by is %L', t, 'Quién lo creó (lo pone la base).');
    execute format('comment on column purchasing.%I.updated_at is %L', t, 'Cuándo se cambió por última vez (lo pone la base).');
    execute format('comment on column purchasing.%I.updated_by is %L', t, 'Quién lo cambió por última vez (lo pone la base).');
    execute format('comment on column purchasing.%I.deleted_at is %L', t, 'Cuándo se borró (borrado lógico). Vacío si está vigente.');
    execute format('comment on column purchasing.%I.deleted_by is %L', t, 'Quién lo borró (lo pone la base).');
  end loop;
end
$$;

-- Cada uno ve los pagos de los locales donde tiene purchasing.view_payments; las aplicaciones, de los pagos que ve.
create policy payments_select on purchasing.payments for select to authenticated
  using (deleted_at is null and restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_payments')));
create policy payment_allocations_select on purchasing.payment_allocations for select to authenticated
  using (deleted_at is null and payment_id in (select id from purchasing.payments));

-- ---------------------------------------------------------------------------
-- 4. El saldo de una factura
-- ---------------------------------------------------------------------------
create function purchasing.invoice_balance(p_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round(i.total_amount
               - coalesce((select sum(n.total_amount) from purchasing.credit_debit_notes n
                            where n.invoice_id = i.id and n.deleted_at is null
                              and n.note_kind in ('credit', 'discount')), 0)
               + coalesce((select sum(n.total_amount) from purchasing.credit_debit_notes n
                            where n.invoice_id = i.id and n.deleted_at is null and n.note_kind = 'debit'), 0)
               - coalesce((select sum(a.allocated_amount) from purchasing.payment_allocations a
                             join purchasing.payments p on p.id = a.payment_id
                            where a.invoice_id = i.id and a.deleted_at is null and p.deleted_at is null
                              and p.status <> 'voided'), 0), 4)
    from purchasing.invoices i
   where i.id = p_id
$$;
comment on function purchasing.invoice_balance(uuid) is
  'Interna: el saldo de una factura = total − notas de crédito y descuentos + notas de débito − pagos aplicados (sin los anulados). Se calcula siempre, no se guarda.';
revoke execute on function purchasing.invoice_balance(uuid) from public;

-- ---------------------------------------------------------------------------
-- 5. Un pago no se cambia ni se borra; una aplicación cuida el saldo
-- ---------------------------------------------------------------------------
create function purchasing.guard_payment()
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
                             'payment_amount', 'paid_on', 'notes'])
         is distinct from (to_jsonb(old) - array['status', 'voided_reason', 'voided_at', 'voided_by', 'updated_at',
                                                 'updated_by', 'payment_amount', 'paid_on', 'notes'])
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
comment on function purchasing.guard_payment() is
  'Interna: un pago no se borra ni cambia sus datos; solo pasa de «para confirmar» a registrado (con su importe corregido), a «con aviso en cola» o a anulado. Uno anulado no cambia más.';
revoke execute on function purchasing.guard_payment() from public;
create trigger guard_payment before update or delete on purchasing.payments
  for each row execute function purchasing.guard_payment();

create function purchasing.guard_payment_allocation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_p purchasing.payments;
  v_i purchasing.invoices;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Una aplicación de un pago no se cambia ni se borra: se anula el pago.' using errcode = '42501';
  end if;
  select * into v_p from purchasing.payments where id = new.payment_id;
  select * into v_i from purchasing.invoices where id = new.invoice_id;
  if v_p.status not in ('registered', 'receipt_queued') then
    raise exception 'Solo se aplica un pago registrado.' using errcode = '23514';
  end if;
  if v_i.restaurant_id <> v_p.restaurant_id or v_i.supplier_id <> v_p.supplier_id then
    raise exception 'El pago y la factura tienen que ser del mismo local y proveedor.' using errcode = '23514';
  end if;
  if v_i.status not in ('released', 'paid') then
    raise exception 'Solo se paga una factura liberada.' using errcode = '23514';
  end if;
  if coalesce((select sum(a.allocated_amount) from purchasing.payment_allocations a
                where a.payment_id = new.payment_id and a.deleted_at is null), 0) + new.allocated_amount
       > v_p.payment_amount + 0.005 then
    raise exception 'Lo aplicado no puede superar el pago.' using errcode = '23514';
  end if;
  if purchasing.invoice_balance(new.invoice_id) - new.allocated_amount < -0.005 then
    raise exception 'No se puede aplicar más que el saldo de la factura.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function purchasing.guard_payment_allocation() is
  'Interna: una aplicación es de un pago registrado y de una factura liberada del mismo local y proveedor; no supera el saldo de la factura ni lo que queda del pago. No se cambia ni se borra (se anula el pago).';
revoke execute on function purchasing.guard_payment_allocation() from public;
create trigger guard_payment_allocation before insert or update or delete on purchasing.payment_allocations
  for each row execute function purchasing.guard_payment_allocation();

-- ---------------------------------------------------------------------------
-- 6. El comprobante (Storage) y el aviso al proveedor (cola)
-- ---------------------------------------------------------------------------
alter table purchasing.attachments drop constraint attachments_source_table_check;
alter table purchasing.attachments add constraint attachments_source_table_check
  check (source_table in ('price_lists', 'receipts', 'receipt_lines', 'invoices', 'credit_debit_notes', 'payments'));

alter table purchasing.outbound_messages drop constraint outbound_messages_source_table_check;
alter table purchasing.outbound_messages add constraint outbound_messages_source_table_check
  check (source_table in ('purchase_orders', 'payments'));
comment on table purchasing.outbound_messages is
  'Mensajes que el sistema manda a los proveedores desde la cuenta de la empresa: las órdenes de compra y el aviso de un pago con su comprobante. Hoy quedan en cola: nadie los despacha (decisión 9 de Soy). Nunca se mandan desde el usuario de quien pidió o pagó.';
