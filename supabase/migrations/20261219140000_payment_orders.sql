-- Facturas y orden de pago (PR C de las correcciones de Compras, ADR-0070; decisiones 4 a 11 de Soy).
--
-- 1. Cajas y cuentas de cada razón social (de dónde sale la plata). Las carga Dirección (org.manage) en la ficha de la
--    razón social; las elige quien paga.
-- 2. La orden de pago: una cabecera numerada por razón social (OP-0001), que agrupa de 1 a 5 medios. Cada medio es un
--    pago de los de siempre (purchasing.payments): las aplicaciones, el saldo, las notas y el anticipo no cambian.
--    Retenciones de Ganancias, IVA e IIBB con su lugar, en 0 por ahora (P8).
-- 3. Cheques (propio, de terceros, e-cheq): solo los datos en el pago, sin cartera (decisión de Joaco).
-- 4. Facturas: el CAE se pide al controlar, no al cargar (el alta corta no lo pide); filtros «Para dar conforme» y
--    «Vencidas» en el listado y en su conteo por proveedor.

-- ---------------------------------------------------------------------------
-- 1. Cajas y cuentas de la razón social
-- ---------------------------------------------------------------------------
create type org.account_kind as enum ('cash', 'bank', 'card');
comment on type org.account_kind is
  'Tipo de caja o cuenta propia de una razón social: cash (caja, efectivo), bank (cuenta bancaria: transferencias, cheques propios, e-cheq) y card (tarjeta).';

create table org.legal_entity_accounts (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null references org.groups (id) on delete restrict,
  legal_entity_id uuid not null,
  kind            org.account_kind not null,
  name            text not null,
  bank            text,
  account_number  text,
  cbu             text,
  alias           text,
  card_last4      text,
  currency        char(3) not null default 'ARS',
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  created_by      uuid references core.actors (id) on delete restrict,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references core.actors (id) on delete restrict,
  deleted_at      timestamptz,
  deleted_by      uuid references core.actors (id) on delete restrict,
  -- La razón social, del mismo grupo.
  constraint legal_entity_accounts_entity_fkey foreign key (legal_entity_id, group_id)
    references org.legal_entities (id, group_id) on delete restrict,
  constraint legal_entity_accounts_name_check check (length(btrim(name)) between 1 and 80),
  constraint legal_entity_accounts_bank_check check (bank is null or length(btrim(bank)) between 1 and 80),
  constraint legal_entity_accounts_number_check check (account_number is null
                                                       or length(btrim(account_number)) between 1 and 40),
  constraint legal_entity_accounts_cbu_check check (cbu is null or cbu ~ '^[0-9]{22}$'),
  constraint legal_entity_accounts_alias_check check (alias is null or alias ~ '^[A-Za-z0-9.-]{6,20}$'),
  constraint legal_entity_accounts_card_check check (card_last4 is null or card_last4 ~ '^[0-9]{4}$'),
  constraint legal_entity_accounts_currency_check check (currency = 'ARS'),
  -- Lo que pide cada tipo: el banco, su nombre y el CBU o el número; la tarjeta, sus últimos 4; la caja, nada más.
  constraint legal_entity_accounts_kind_check check (
    (kind = 'bank' and bank is not null and (cbu is not null or account_number is not null) and card_last4 is null)
    or (kind = 'card' and card_last4 is not null and cbu is null and alias is null)
    or (kind = 'cash' and bank is null and cbu is null and alias is null and account_number is null
        and card_last4 is null)),
  unique (id, group_id)
);
create index legal_entity_accounts_entity_idx on org.legal_entity_accounts (legal_entity_id) where deleted_at is null;
create index legal_entity_accounts_group_idx on org.legal_entity_accounts (group_id);
create unique index legal_entity_accounts_name_key on org.legal_entity_accounts (legal_entity_id, lower(btrim(name)))
  where deleted_at is null;
comment on table org.legal_entity_accounts is
  'Cajas y cuentas propias de una razón social: de dónde sale la plata de una orden de pago. Las carga Dirección (org.manage) en la ficha de la razón social; se dan de baja, no se borran.';
comment on column org.legal_entity_accounts.kind is 'Caja (efectivo), cuenta bancaria o tarjeta.';
comment on column org.legal_entity_accounts.name is 'Cómo se la llama: «Caja Centro», «Galicia CC 1234».';
comment on column org.legal_entity_accounts.bank is 'Banco de la cuenta (solo cuentas bancarias).';
comment on column org.legal_entity_accounts.account_number is 'Número de la cuenta bancaria.';
comment on column org.legal_entity_accounts.cbu is 'CBU de la cuenta bancaria (22 números).';
comment on column org.legal_entity_accounts.alias is 'Alias de la cuenta bancaria.';
comment on column org.legal_entity_accounts.card_last4 is 'Últimos 4 números de la tarjeta (nunca el número entero).';
comment on column org.legal_entity_accounts.is_active is 'Si se puede elegir al pagar. Una cuenta cerrada se desactiva o se da de baja.';

alter table org.legal_entity_accounts enable row level security;
revoke all on org.legal_entity_accounts from public, anon, authenticated;
grant select on org.legal_entity_accounts to authenticated;
-- La ven quien administra el grupo y quien paga o ve pagos en un local que factura con esa razón social.
create policy legal_entity_accounts_select on org.legal_entity_accounts for select to authenticated
  using (deleted_at is null
         and (group_id in (select core.permitted_group_ids('org.manage'))
              or exists (select 1 from org.restaurants r
                          where r.legal_entity_id = legal_entity_accounts.legal_entity_id and r.deleted_at is null
                            and (r.id in (select core.permitted_restaurant_ids('purchasing.pay'))
                                 or r.id in (select core.permitted_restaurant_ids('purchasing.view_payments'))))));
create trigger set_control_columns before insert or update on org.legal_entity_accounts
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on org.legal_entity_accounts
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on org.legal_entity_accounts
  for each statement execute function core.reject_truncate();

-- Guardar las cajas y cuentas de una razón social en lote, con motivo: [{id?, remove?, kind, name, bank, account_number,
-- cbu, alias, card_last4, is_active}]. Sin id, una nueva; con remove, la baja (lógica).
create function org.save_legal_entity_accounts(p_legal_entity_id uuid, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_le         org.legal_entities;
  v_item       jsonb;
  v_id         uuid;
  v_reason     text := nullif(btrim(p_reason), '');
  v_constraint text;
  v_message    text;
begin
  select * into v_le from org.legal_entities where id = p_legal_entity_id and deleted_at is null;
  if v_le.id is null or not core.has_permission_in_group('org.manage', v_le.group_id) then
    return core.deny('org.save_legal_entity_accounts', 'No tenés permiso para cargar las cajas y cuentas.', null,
                     jsonb_build_object('legal_entity_id', p_legal_entity_id), v_le.group_id, null, null);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0
     or jsonb_array_length(p_changes) > 30 then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  for v_item in select value from jsonb_array_elements(p_changes) loop
    perform org.check_keys(v_item, array['id', 'remove', 'kind', 'name', 'bank', 'account_number', 'cbu', 'alias',
                                         'card_last4', 'is_active']);
    if coalesce((v_item ->> 'remove')::boolean, false) and not v_item ? 'id' then
      raise exception 'Para dar de baja, elegí cuál.' using errcode = '22023';
    end if;
    if v_item ? 'id' then
      v_id := (v_item ->> 'id')::uuid;
      perform 1 from org.legal_entity_accounts
       where id = v_id and legal_entity_id = v_le.id and deleted_at is null for update;
      if not found then
        raise exception 'Esa cuenta no es de esta razón social.' using errcode = '22023';
      end if;
      if coalesce((v_item ->> 'remove')::boolean, false) then
        update org.legal_entity_accounts set deleted_at = now(), deleted_by = core.current_actor_id() where id = v_id;
      else
        update org.legal_entity_accounts
           set kind           = coalesce(nullif(v_item ->> 'kind', '')::org.account_kind, kind),
               name           = coalesce(nullif(btrim(v_item ->> 'name'), ''), name),
               bank           = case when v_item ? 'bank' then nullif(btrim(v_item ->> 'bank'), '') else bank end,
               account_number = case when v_item ? 'account_number'
                                     then nullif(btrim(v_item ->> 'account_number'), '') else account_number end,
               cbu            = case when v_item ? 'cbu' then nullif(regexp_replace(v_item ->> 'cbu', '\D', '', 'g'), '')
                                     else cbu end,
               alias          = case when v_item ? 'alias' then nullif(btrim(v_item ->> 'alias'), '') else alias end,
               card_last4     = case when v_item ? 'card_last4' then nullif(btrim(v_item ->> 'card_last4'), '')
                                     else card_last4 end,
               is_active      = coalesce((v_item ->> 'is_active')::boolean, is_active)
         where id = v_id;
      end if;
    else
      insert into org.legal_entity_accounts (group_id, legal_entity_id, kind, name, bank, account_number, cbu, alias,
                                             card_last4, is_active)
      values (v_le.group_id, v_le.id, (v_item ->> 'kind')::org.account_kind, btrim(v_item ->> 'name'),
              nullif(btrim(v_item ->> 'bank'), ''), nullif(btrim(v_item ->> 'account_number'), ''),
              nullif(regexp_replace(coalesce(v_item ->> 'cbu', ''), '\D', '', 'g'), ''),
              nullif(btrim(v_item ->> 'alias'), ''), nullif(btrim(v_item ->> 'card_last4'), ''),
              coalesce((v_item ->> 'is_active')::boolean, true));
    end if;
  end loop;
  return jsonb_build_object('result', 'applied', 'legal_entity_id', v_le.id);
exception
  when check_violation or unique_violation or not_null_violation or invalid_text_representation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    raise exception '%', case
      when v_constraint = 'legal_entity_accounts_kind_check' then
        'Una cuenta bancaria lleva el banco y el CBU o el número; una tarjeta, sus últimos 4 números; una caja, solo el nombre.'
      when v_constraint = 'legal_entity_accounts_name_key' then 'Ya hay una caja o cuenta con ese nombre.'
      when v_constraint = 'legal_entity_accounts_name_check' then 'El nombre va de 1 a 80 caracteres.'
      when v_constraint = 'legal_entity_accounts_cbu_check' then 'El CBU tiene 22 números.'
      when v_constraint = 'legal_entity_accounts_alias_check' then
        'El alias va de 6 a 20 letras, números, puntos o guiones.'
      when v_constraint = 'legal_entity_accounts_card_check' then 'De la tarjeta van solo los últimos 4 números.'
      when v_constraint is null and v_message ~ 'account_kind' then 'Elegí si es caja, cuenta bancaria o tarjeta.'
      else 'Revisá los datos de la caja o la cuenta.'
    end using errcode = '22023';
end
$$;
comment on function org.save_legal_entity_accounts(uuid, jsonb, text) is
  'Alta, cambio y baja (lógica) de las cajas y cuentas de una razón social, en lote y con motivo. Pide org.manage en el grupo.';
revoke execute on function org.save_legal_entity_accounts(uuid, jsonb, text) from public, anon;
grant execute on function org.save_legal_entity_accounts(uuid, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. La orden de pago
-- ---------------------------------------------------------------------------
create type purchasing.payment_order_status as enum ('registered', 'voided');
comment on type purchasing.payment_order_status is
  'Estado de una orden de pago: registered (registrada) o voided (anulada, con motivo; no se borra).';

create table purchasing.payment_orders (
  id                       uuid primary key default gen_random_uuid(),
  group_id                 uuid not null,
  brand_id                 uuid not null,
  restaurant_id            uuid not null,
  supplier_id              uuid not null,
  legal_entity_id          uuid not null,
  number                   text not null,
  paid_on                  date not null,
  withholding_income_tax   numeric(18,4) not null default 0,
  withholding_vat          numeric(18,4) not null default 0,
  withholding_gross_income numeric(18,4) not null default 0,
  total_amount             numeric(18,4) not null,
  currency                 char(3) not null default 'ARS',
  notes                    text,
  status                   purchasing.payment_order_status not null default 'registered',
  version                  integer not null default 1,
  voided_reason            text,
  voided_at                timestamptz,
  voided_by                uuid references core.actors (id) on delete restrict,
  created_at               timestamptz not null default now(),
  created_by               uuid references core.actors (id) on delete restrict,
  updated_at               timestamptz not null default now(),
  updated_by               uuid references core.actors (id) on delete restrict,
  deleted_at               timestamptz,
  deleted_by               uuid references core.actors (id) on delete restrict,
  constraint payment_orders_legal_entity_fkey foreign key (legal_entity_id, group_id)
    references org.legal_entities (id, group_id) on delete restrict,
  constraint payment_orders_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint payment_orders_brand_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint payment_orders_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint payment_orders_number_check check (number ~ '^OP-[0-9]{4,}$'),
  constraint payment_orders_paid_on_check check (paid_on >= date '2000-01-01'),
  -- Retenciones: el lugar está; hasta definir P8, en cero.
  constraint payment_orders_withholdings_check check (withholding_income_tax = 0 and withholding_vat = 0
                                                      and withholding_gross_income = 0),
  constraint payment_orders_total_check check (total_amount > 0 and total_amount < 10000000000),
  constraint payment_orders_currency_check check (currency = 'ARS'),
  constraint payment_orders_notes_check check (notes is null or length(btrim(notes)) between 1 and 500),
  constraint payment_orders_void_check check ((status = 'voided')
                                              = (voided_reason is not null and voided_at is not null)),
  constraint payment_orders_version_check check (version >= 1),
  unique (id, group_id)
);
create unique index payment_orders_number_key on purchasing.payment_orders (legal_entity_id, number);
create index payment_orders_restaurant_idx on purchasing.payment_orders (restaurant_id, paid_on desc)
  where deleted_at is null;
-- Completos, para controlar las claves foráneas compuestas (también sobre filas borradas).
create index payment_orders_restaurant_group_idx on purchasing.payment_orders (restaurant_id, group_id);
create index payment_orders_restaurant_brand_idx on purchasing.payment_orders (restaurant_id, brand_id);
create index payment_orders_voided_by_idx on purchasing.payment_orders (voided_by) where voided_by is not null;
create index payment_orders_supplier_idx on purchasing.payment_orders (supplier_id, group_id);
create index payment_orders_group_idx on purchasing.payment_orders (group_id);
create index payment_orders_entity_idx on purchasing.payment_orders (legal_entity_id);
comment on table purchasing.payment_orders is
  'Orden de pago a un proveedor (decisiones 5 a 11 de Soy, ADR-0070): número correlativo por razón social (OP-0001), quién paga, de 1 a 5 medios (purchasing.payments con payment_order_id), retenciones (en 0 por ahora) y el total. Imprimible. No se borra: se anula con motivo.';
comment on column purchasing.payment_orders.legal_entity_id is 'La razón social que paga (la de las cajas y cuentas de donde sale la plata).';
comment on column purchasing.payment_orders.number is 'Número correlativo de la razón social: OP-0001.';
comment on column purchasing.payment_orders.withholding_income_tax is 'Retención de Ganancias. En 0 hasta definir el cálculo (P8).';
comment on column purchasing.payment_orders.withholding_vat is 'Retención de IVA. En 0 hasta definir el cálculo (P8).';
comment on column purchasing.payment_orders.withholding_gross_income is 'Retención de Ingresos Brutos. En 0 hasta definir el cálculo (P8).';
comment on column purchasing.payment_orders.total_amount is 'Total de la orden: los medios más las retenciones.';
comment on column purchasing.payment_orders.version is 'Versión de la orden impresa (criterio 14 de Soy). Una orden registrada no cambia: se anula y se hace otra.';

alter table purchasing.payment_orders enable row level security;
revoke all on purchasing.payment_orders from public, anon, authenticated;
grant select on purchasing.payment_orders to authenticated;
create policy payment_orders_select on purchasing.payment_orders for select to authenticated
  using (deleted_at is null and restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_payments')));
create trigger set_control_columns before insert or update on purchasing.payment_orders
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on purchasing.payment_orders
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on purchasing.payment_orders
  for each statement execute function core.reject_truncate();

-- Una orden registrada no cambia: solo se anula (con motivo). Nunca se borra.
create function purchasing.guard_payment_order()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una orden de pago no se borra: se anula con motivo.' using errcode = '23514';
  end if;
  if old.status = 'voided' then
    raise exception 'Esta orden de pago ya está anulada.' using errcode = '23514';
  end if;
  if new.status <> 'voided' or (to_jsonb(new) - array['status', 'voided_reason', 'voided_at', 'voided_by', 'updated_at',
                                                      'updated_by'])
                               <> (to_jsonb(old) - array['status', 'voided_reason', 'voided_at', 'voided_by',
                                                         'updated_at', 'updated_by']) then
    raise exception 'Una orden de pago registrada no cambia: se anula y se hace otra.' using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger guard_payment_order before update or delete on purchasing.payment_orders
  for each row execute function purchasing.guard_payment_order();

-- El próximo número de orden de pago de una razón social: «OP-0001». El contador vive en catalog.code_series con un
-- prefijo propio de esa razón social; el update bloquea la fila hasta el commit (dos pagos a la vez no repiten número).
create function purchasing.next_payment_order_number(p_group_id uuid, p_legal_entity_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series text := 'OP-' || upper(left(replace(p_legal_entity_id::text, '-', ''), 12)) || '-';
  v_number integer;
begin
  loop
    update catalog.code_series set last_number = last_number + 1
     where group_id = p_group_id and prefix = v_series
    returning last_number into v_number;
    exit when v_number is not null;
    insert into catalog.code_series (group_id, prefix, last_number)
    values (p_group_id, v_series, coalesce((select max(substr(o.number, 4)::integer) from purchasing.payment_orders o
                                             where o.legal_entity_id = p_legal_entity_id), 0))
    on conflict (group_id, prefix) do nothing;
  end loop;
  return 'OP-' || lpad(v_number::text, greatest(4, length(v_number::text)), '0');
end
$$;
comment on function purchasing.next_payment_order_number(uuid, uuid) is
  'Interna: el próximo número de orden de pago de una razón social (OP-0001), correlativo y sin repetir.';
revoke execute on function purchasing.next_payment_order_number(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Los medios: los pagos de siempre, con su orden, su caja o cuenta y los datos del cheque
-- ---------------------------------------------------------------------------
alter table purchasing.payments
  add column payment_order_id    uuid,
  add column company_account_id  uuid,
  add column check_number        text,
  add column check_bank          text,
  add column check_due_on        date,
  add column check_third_party   boolean not null default false,
  add column check_drawer_name   text,
  add column check_drawer_tax_id text;
alter table purchasing.payments
  add constraint payments_order_fkey foreign key (payment_order_id, group_id)
    references purchasing.payment_orders (id, group_id) on delete restrict,
  add constraint payments_check_number_check check (check_number is null or length(btrim(check_number)) between 1 and 30),
  add constraint payments_check_bank_check check (check_bank is null or length(btrim(check_bank)) between 1 and 80),
  add constraint payments_check_drawer_check check (check_drawer_name is null
                                                    or length(btrim(check_drawer_name)) between 1 and 120),
  add constraint payments_check_drawer_tax_id_check check (check_drawer_tax_id is null
                                                           or core.valid_cuit(check_drawer_tax_id)),
  -- Un cheque (o e-cheq) lleva número, banco y fecha de cobro; uno de terceros, además, quién lo libró.
  add constraint payments_check_data_check check (
    payment_order_id is null
    or ((method not in ('check', 'echeq'))
          = (check_number is null and check_bank is null and check_due_on is null)
        and (check_third_party = false or (method = 'check' and check_drawer_name is not null))
        and (check_third_party or check_drawer_name is null and check_drawer_tax_id is null)));
-- Antes: todo pago que no fuera en efectivo iba a una cuenta del proveedor. En una orden de pago, la cuenta del
-- proveedor la pide solo la transferencia (o el código de pago electrónico); un cheque o una tarjeta pueden no tenerla.
alter table purchasing.payments drop constraint payments_account_check;
alter table purchasing.payments add constraint payments_account_check check (
  (payment_order_id is null and (method = 'cash') = (payment_account_id is null))
  or (payment_order_id is not null and (method <> 'cash' or payment_account_id is null)
      and (method not in ('transfer', 'electronic_code') or payment_account_id is not null)));
create index payments_order_idx on purchasing.payments (payment_order_id) where payment_order_id is not null;
-- La caja o cuenta propia, del mismo grupo que el pago (no solo que exista).
alter table purchasing.payments
  add constraint payments_company_account_fkey foreign key (company_account_id, group_id)
    references org.legal_entity_accounts (id, group_id) on delete restrict;
alter table purchasing.payments
  add constraint payments_third_party_account_check check (not check_third_party or company_account_id is null),
  add constraint payments_check_due_on_check check (check_due_on is null or check_due_on >= date '2000-01-01');
create index payments_company_account_idx on purchasing.payments (company_account_id)
  where company_account_id is not null;
comment on column purchasing.payments.payment_order_id is 'La orden de pago de la que es un medio (vacía en los pagos de antes y en el efectivo pagado al recibir).';
comment on column purchasing.payments.company_account_id is 'De dónde sale la plata: la caja o cuenta propia de la razón social.';
comment on column purchasing.payments.check_number is 'Número del cheque o e-cheq.';
comment on column purchasing.payments.check_bank is 'Banco del cheque o e-cheq.';
comment on column purchasing.payments.check_due_on is 'Fecha de cobro del cheque o e-cheq.';
comment on column purchasing.payments.check_third_party is 'Si el cheque es de terceros (lo dio otro y se endosa al proveedor).';
comment on column purchasing.payments.check_drawer_name is 'Quién libró el cheque de terceros.';
comment on column purchasing.payments.check_drawer_tax_id is 'CUIT de quien libró el cheque de terceros.';

-- El aviso al proveedor puede ser de una orden de pago.
alter table purchasing.outbound_messages drop constraint outbound_messages_source_table_check;
alter table purchasing.outbound_messages add constraint outbound_messages_source_table_check
  check (source_table = any (array['purchase_orders', 'payments', 'payment_orders']));

-- ---------------------------------------------------------------------------
-- 4. Registrar la orden de pago
-- ---------------------------------------------------------------------------
-- El texto que se le manda al proveedor (y el que se imprime arriba de la orden).
create function purchasing.payment_order_message(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select format(E'ORDEN DE PAGO %s\n%s (CUIT %s) le paga a %s el %s.\nTotal: $ %s\n%s',
                o.number, le.name, coalesce(le.tax_id, '—'), coalesce(s.trade_name, s.name),
                to_char(o.paid_on, 'DD/MM/YYYY'), to_char(o.total_amount, 'FM999G999G999G990D00'),
                coalesce((select string_agg(purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number)
                                            || ': $ ' || to_char(sum_a, 'FM999G999G999G990D00'), E'\n')
                            from (select a.invoice_id, sum(a.allocated_amount) as sum_a
                                    from purchasing.payment_allocations a
                                    join purchasing.payments p on p.id = a.payment_id
                                   where p.payment_order_id = o.id and a.deleted_at is null
                                   group by a.invoice_id) x
                            join purchasing.invoices i on i.id = x.invoice_id), 'A cuenta.'))
    from purchasing.payment_orders o
    join org.legal_entities le on le.id = o.legal_entity_id
    join catalog.suppliers s on s.id = o.supplier_id
   where o.id = p_id
$$;
comment on function purchasing.payment_order_message(uuid) is
  'Interna: el texto de una orden de pago para el proveedor (número, quién paga, total y qué facturas cancela).';
revoke execute on function purchasing.payment_order_message(uuid) from public, anon, authenticated;

-- p_lines: de 1 a 5 medios [{method, company_account_id, supplier_account_id, amount, reference, check_number,
-- check_bank, check_due_on, check_third_party, check_drawer_name, check_drawer_tax_id}].
-- p_allocations: [{invoice_id, amount}] (lo que se cancela de cada factura; lo que sobra queda a cuenta).
create function purchasing.register_payment_order(p_restaurant_id uuid, p_supplier_id uuid, p_paid_on date,
                                                  p_legal_entity_id uuid, p_lines jsonb, p_allocations jsonb,
                                                  p_notes text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r          org.restaurants;
  v_s          catalog.suppliers;
  v_le         org.legal_entities;
  v_t          purchasing.supplier_terms;
  v_order      purchasing.payment_orders;
  v_line       jsonb;
  v_method     purchasing.payment_method;
  v_account    org.legal_entity_accounts;
  v_amount     numeric;
  v_total      numeric := 0;
  v_applied    numeric := 0;
  v_payments   uuid[] := '{}';
  v_left       numeric[] := '{}';
  v_pid        uuid;
  v_item       jsonb;
  v_need       numeric;
  v_take       numeric;
  v_i          integer;
  v_reason     text := nullif(btrim(p_reason), '');
  v_constraint text;
  v_message    text;
  v_state      text;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_r.id) then
    return core.deny('purchasing.register_payment_order', 'No tenés permiso para registrar pagos en este local.', null,
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
  -- Paga la razón social del local, y solo ella: no se puede emitir una orden (ni gastar su número) a nombre de otra.
  select * into v_le from org.legal_entities
   where id = v_r.legal_entity_id and group_id = v_r.group_id and deleted_at is null;
  if v_le.id is null then
    raise exception 'El local no tiene razón social: cargala en el Panel de control para poder pagar.' using errcode = '22023';
  end if;
  if p_legal_entity_id is not null and p_legal_entity_id <> v_le.id then
    raise exception 'Se paga con la razón social del local (%).', v_le.name using errcode = '22023';
  end if;
  if p_paid_on is null or p_paid_on > recipes.today() then
    raise exception 'La fecha del pago no puede ser posterior a hoy.' using errcode = '22023';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Elegí cómo se paga (al menos un medio).' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) > 5 then
    raise exception 'Una orden de pago va hasta con 5 medios.' using errcode = '22023';
  end if;
  perform purchasing.check_payment_lines(p_allocations);

  -- Los medios, antes de escribir nada: importe, caja o cuenta propia del tipo que corresponde y de esta razón social,
  -- cuenta del proveedor (la transferencia la pide).
  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Uno de los medios de pago no se entiende.' using errcode = '22023';
    end if;
    perform org.check_keys(v_line, array['method', 'company_account_id', 'supplier_account_id', 'amount', 'reference',
                                         'check_number', 'check_bank', 'check_due_on', 'check_third_party',
                                         'check_drawer_name', 'check_drawer_tax_id']);
    v_method := (v_line ->> 'method')::purchasing.payment_method;
    if coalesce(jsonb_typeof(v_line -> 'amount'), '') <> 'number' or (v_line ->> 'amount')::numeric <= 0
       or (v_line ->> 'amount')::numeric >= 10000000000 then
      raise exception 'Escribí el importe de cada medio (mayor que cero).' using errcode = '22023';
    end if;
    v_total := v_total + round((v_line ->> 'amount')::numeric, 4);
    -- Un cheque de terceros no sale de una cuenta propia; todo lo demás, sí.
    if v_method = 'check' and coalesce((v_line ->> 'check_third_party')::boolean, false) then
      if nullif(v_line ->> 'company_account_id', '') is not null then
        raise exception 'Un cheque de terceros no sale de una caja ni de una cuenta propia.' using errcode = '22023';
      end if;
    else
      select * into v_account from org.legal_entity_accounts
       where id = nullif(v_line ->> 'company_account_id', '')::uuid and legal_entity_id = v_le.id
         and is_active and deleted_at is null;
      if v_account.id is null then
        raise exception 'Elegí de qué caja o cuenta de % sale el pago.', v_le.name using errcode = '22023';
      end if;
      if (v_method = 'cash' and v_account.kind <> 'cash')
         or (v_method in ('transfer', 'check', 'echeq', 'electronic_code') and v_account.kind <> 'bank')
         or (v_method = 'card' and v_account.kind <> 'card') then
        raise exception 'El efectivo sale de una caja; la transferencia, el cheque y el e-cheq, de una cuenta bancaria; la tarjeta, de una tarjeta.'
          using errcode = '22023';
      end if;
    end if;
    if v_method in ('transfer', 'electronic_code') and not exists (
         select 1 from purchasing.supplier_payment_accounts a
          where a.id = nullif(v_line ->> 'supplier_account_id', '')::uuid and a.supplier_id = v_s.id
            and a.method = v_method and a.is_active and a.deleted_at is null) then
      raise exception 'Elegí la cuenta del proveedor a la que va la transferencia.' using errcode = '22023';
    end if;
    if nullif(v_line ->> 'supplier_account_id', '') is not null and not exists (
         select 1 from purchasing.supplier_payment_accounts a
          where a.id = (v_line ->> 'supplier_account_id')::uuid and a.supplier_id = v_s.id and a.deleted_at is null) then
      raise exception 'Esa cuenta no es del proveedor.' using errcode = '22023';
    end if;
  end loop;
  if v_total >= 10000000000 then
    raise exception 'El importe es demasiado grande: revisalo.' using errcode = '22023';
  end if;
  if (select coalesce(sum((x ->> 'amount')::numeric), 0) from jsonb_array_elements(coalesce(p_allocations, '[]')) x)
     > v_total + 0.005 then
    raise exception 'Lo que se cancela de las facturas no puede pasar lo que se paga.' using errcode = '22023';
  end if;

  -- Mismo orden en todo pagos: primero las facturas (por id), después lo demás.
  perform 1 from purchasing.invoices
   where id in (select (x ->> 'invoice_id')::uuid from jsonb_array_elements(coalesce(p_allocations, '[]')) x)
     and restaurant_id = v_r.id and supplier_id = v_s.id
   order by id
     for update;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  begin
    insert into purchasing.payment_orders (group_id, brand_id, restaurant_id, supplier_id, legal_entity_id, number,
                                           paid_on, total_amount, notes)
    values (v_r.group_id, v_r.brand_id, v_r.id, v_s.id, v_le.id,
            purchasing.next_payment_order_number(v_r.group_id, v_le.id), p_paid_on, round(v_total, 4),
            nullif(btrim(p_notes), ''))
    returning * into v_order;

    for v_line in select value from jsonb_array_elements(p_lines) loop
      v_method := (v_line ->> 'method')::purchasing.payment_method;
      insert into purchasing.payments (group_id, brand_id, restaurant_id, supplier_id, paid_on, method,
                                       payment_account_id, reference, payment_amount, status, payment_order_id,
                                       company_account_id, check_number, check_bank, check_due_on, check_third_party,
                                       check_drawer_name, check_drawer_tax_id)
      values (v_r.group_id, v_r.brand_id, v_r.id, v_s.id, p_paid_on, v_method,
              case when v_method = 'cash' then null else nullif(v_line ->> 'supplier_account_id', '')::uuid end,
              nullif(btrim(v_line ->> 'reference'), ''), round((v_line ->> 'amount')::numeric, 4), 'registered',
              v_order.id, nullif(v_line ->> 'company_account_id', '')::uuid,
              nullif(btrim(v_line ->> 'check_number'), ''), nullif(btrim(v_line ->> 'check_bank'), ''),
              nullif(v_line ->> 'check_due_on', '')::date,
              coalesce((v_line ->> 'check_third_party')::boolean, false),
              nullif(btrim(v_line ->> 'check_drawer_name'), ''),
              nullif(regexp_replace(coalesce(v_line ->> 'check_drawer_tax_id', ''), '\D', '', 'g'), ''))
      returning id into v_pid;
      v_payments := v_payments || v_pid;
      v_left := v_left || round((v_line ->> 'amount')::numeric, 4);
    end loop;

    -- Lo que se cancela de cada factura se reparte entre los medios, en orden: cada medio se usa hasta su importe.
    for v_item in select value from jsonb_array_elements(coalesce(p_allocations, '[]')) loop
      v_need := round((v_item ->> 'amount')::numeric, 4);
      v_applied := v_applied + v_need;
      v_i := 1;
      while v_need > 0 and v_i <= cardinality(v_payments) loop
        v_take := least(v_need, v_left[v_i]);
        if v_take > 0 then
          perform purchasing.allocate_payment(v_payments[v_i], (v_item ->> 'invoice_id')::uuid, v_take);
          v_left[v_i] := v_left[v_i] - v_take;
          v_need := v_need - v_take;
        end if;
        v_i := v_i + 1;
      end loop;
    end loop;
  exception
    when check_violation or unique_violation or not_null_violation or foreign_key_violation
         or invalid_text_representation or invalid_datetime_format then
      get stacked diagnostics v_constraint = constraint_name, v_message = message_text, v_state = returned_sqlstate;
      if v_state in ('22P02', '22007', '22008') then
        raise exception 'Hay un dato que no se entiende (un medio, una fecha o un importe): revisá el pago.'
          using errcode = '22023';
      end if;
      if v_constraint = 'payments_check_data_check' then
        raise exception 'Un cheque lleva número, banco y fecha de cobro; uno de terceros, además, quién lo libró.'
          using errcode = '22023';
      end if;
      if v_constraint = 'payments_check_drawer_tax_id_check' then
        raise exception 'El CUIT de quien libró el cheque no es válido.' using errcode = '22023';
      end if;
      perform purchasing.raise_payment_error(v_state, v_constraint, v_message);
  end;

  -- Un aviso al proveedor por orden de pago, por el canal de su ficha (decisión 9 de Soy).
  select * into v_t from purchasing.supplier_terms where supplier_id = v_s.id and deleted_at is null;
  if v_t.po_channel is not null and v_t.po_channel_target is not null then
    insert into purchasing.outbound_messages (group_id, channel, target, subject, body, source_table, source_id)
    values (v_r.group_id, v_t.po_channel, v_t.po_channel_target,
            format('Orden de pago %s de %s', v_order.number, v_le.name),
            purchasing.payment_order_message(v_order.id), 'payment_orders', v_order.id);
    update purchasing.payments set status = 'receipt_queued' where payment_order_id = v_order.id;
  end if;
  return jsonb_build_object('result', 'applied', 'payment_order_id', v_order.id, 'number', v_order.number,
                            'unapplied', round(v_total - v_applied, 2), 'channel', v_t.po_channel);
end
$$;
comment on function purchasing.register_payment_order(uuid, uuid, date, uuid, jsonb, jsonb, text, text) is
  'Registra una orden de pago en una transacción: número correlativo de la razón social, de 1 a 5 medios (cada uno de su caja o cuenta propia; la transferencia, a una cuenta del proveedor; los cheques con sus datos), lo que cancela de cada factura repartido entre los medios y lo que sobra a cuenta. Encola un aviso al proveedor. Pide purchasing.pay en el local y motivo.';
revoke execute on function purchasing.register_payment_order(uuid, uuid, date, uuid, jsonb, jsonb, text, text)
  from public, anon;
grant execute on function purchasing.register_payment_order(uuid, uuid, date, uuid, jsonb, jsonb, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Anular la orden de pago
-- ---------------------------------------------------------------------------
create function purchasing.void_payment_order(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o      purchasing.payment_orders;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select * into v_o from purchasing.payment_orders where id = p_id and deleted_at is null;
  if v_o.id is null or not purchasing.can_in_restaurant('purchasing.pay', v_o.restaurant_id) then
    return core.deny('purchasing.void_payment_order', 'No tenés permiso para anular esta orden de pago.', null,
                     jsonb_build_object('payment_order_id', p_id), v_o.group_id, v_o.brand_id, v_o.restaurant_id);
  end if;
  if v_reason is null or length(v_reason) < 3 then
    raise exception 'Escribí por qué se anula.' using errcode = '22023';
  end if;
  -- Mismo orden en todo pagos: primero las facturas (por id), después los pagos y la orden.
  perform 1 from purchasing.invoices i
   where i.id in (select a.invoice_id from purchasing.payment_allocations a
                   join purchasing.payments p on p.id = a.payment_id
                  where p.payment_order_id = v_o.id)
   order by i.id
     for update;
  perform 1 from purchasing.payments where payment_order_id = v_o.id order by id for update;
  select * into v_o from purchasing.payment_orders where id = p_id for update;
  if v_o.status = 'voided' then
    raise exception 'Esta orden de pago ya está anulada.' using errcode = '23514';
  end if;
  perform core.set_change_context(left(v_reason, 500), 'manual');
  update purchasing.payments
     set status = 'voided', voided_reason = left(v_reason, 500), voided_at = now(), voided_by = core.current_actor_id()
   where payment_order_id = v_o.id and status <> 'voided';
  update purchasing.payment_orders
     set status = 'voided', voided_reason = left(v_reason, 500), voided_at = now(), voided_by = core.current_actor_id()
   where id = v_o.id;
  -- Las facturas que cancelaba y ahora tienen saldo vuelven a liberadas.
  update purchasing.invoices i set status = 'released'
   where i.status = 'paid'
     and i.id in (select a.invoice_id from purchasing.payment_allocations a
                   join purchasing.payments p on p.id = a.payment_id
                  where p.payment_order_id = v_o.id and a.deleted_at is null)
     and purchasing.invoice_balance(i.id) > 0.005;
  update purchasing.outbound_messages set status = 'cancelled'
   where source_table = 'payment_orders' and source_id = v_o.id and status = 'queued';
  return jsonb_build_object('result', 'applied', 'payment_order_id', v_o.id, 'status', 'voided');
end
$$;
comment on function purchasing.void_payment_order(uuid, text) is
  'Anula una orden de pago y sus medios, con motivo: las facturas que cancelaba vuelven a tener saldo y el aviso en cola no sale. No borra nada. Pide purchasing.pay en el local.';
revoke execute on function purchasing.void_payment_order(uuid, text) from public, anon;
grant execute on function purchasing.void_payment_order(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Lecturas
-- ---------------------------------------------------------------------------
-- La ficha (y la impresión) de una orden de pago. La cuenta del proveedor completa (CBU, CUIT del titular) solo para
-- quien paga o ve la condición de pago; los demás, los últimos 4.
create function purchasing.payment_order_detail(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_o    purchasing.payment_orders;
  v_full boolean;
begin
  select * into v_o from purchasing.payment_orders where id = p_id and deleted_at is null;
  if v_o.id is null or not purchasing.can_in_restaurant('purchasing.view_payments', v_o.restaurant_id) then
    return null;
  end if;
  v_full := purchasing.can_in_restaurant('purchasing.pay', v_o.restaurant_id) or purchasing.can_see_payment(v_o.group_id);
  return jsonb_build_object(
    'id', v_o.id, 'number', v_o.number, 'status', v_o.status, 'version', v_o.version, 'paid_on', v_o.paid_on,
    'total', v_o.total_amount, 'notes', v_o.notes, 'voided_reason', v_o.voided_reason, 'voided_at', v_o.voided_at,
    'withholdings', jsonb_build_object('income_tax', v_o.withholding_income_tax, 'vat', v_o.withholding_vat,
                                       'gross_income', v_o.withholding_gross_income),
    'can_void', v_o.status = 'registered' and purchasing.can_in_restaurant('purchasing.pay', v_o.restaurant_id),
    'restaurant', (select jsonb_build_object('id', r.id, 'name', r.name) from org.restaurants r where r.id = v_o.restaurant_id),
    'payer', (select jsonb_build_object('name', le.name, 'tax_id', le.tax_id) from org.legal_entities le
               where le.id = v_o.legal_entity_id),
    'supplier', (select jsonb_build_object('id', s.id, 'name', coalesce(s.trade_name, s.name), 'legal_name', s.name,
                                           'tax_id', s.tax_id)
                   from catalog.suppliers s where s.id = v_o.supplier_id),
    'registered_by', (select coalesce(nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''), 'Una persona')
                        from core.user_profiles u where u.id = v_o.created_by),
    'registered_at', v_o.created_at,
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'method', p.method, 'amount', p.payment_amount, 'reference', p.reference,
               'from', (select jsonb_build_object('name', a.name, 'kind', a.kind) from org.legal_entity_accounts a
                         where a.id = p.company_account_id),
               'to', (select jsonb_build_object('bank', sa.bank, 'holder_name', sa.holder_name,
                                                'holder_tax_id', case when v_full then sa.holder_tax_id end,
                                                'cbu', case when v_full then sa.cbu end,
                                                'cbu_end', right(sa.cbu, 4), 'alias', case when v_full then sa.alias end)
                        from purchasing.supplier_payment_accounts sa where sa.id = p.payment_account_id),
               'check', case when p.method in ('check', 'echeq') then jsonb_build_object(
                          'number', p.check_number, 'bank', p.check_bank, 'due_on', p.check_due_on,
                          'third_party', p.check_third_party, 'drawer_name', p.check_drawer_name,
                          'drawer_tax_id', p.check_drawer_tax_id) end)
               order by p.created_at, p.id)
        from purchasing.payments p where p.payment_order_id = v_o.id), '[]'::jsonb),
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_id', i.id, 'label', purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number),
               'issued_on', i.issued_on, 'total', i.total_amount, 'applied', x.applied,
               'notes', (select coalesce(sum(case when n.note_kind = 'debit' then -n.total_amount else n.total_amount end),
                                         0)
                           from purchasing.credit_debit_notes n where n.invoice_id = i.id and n.deleted_at is null))
               order by i.issued_on, i.id)
        from (select a.invoice_id, sum(a.allocated_amount) as applied
                from purchasing.payment_allocations a
                join purchasing.payments p on p.id = a.payment_id
               where p.payment_order_id = v_o.id and a.deleted_at is null
               group by a.invoice_id) x
        join purchasing.invoices i on i.id = x.invoice_id), '[]'::jsonb),
    'unapplied', (select coalesce(sum(purchasing.payment_unapplied(p.id)), 0)
                    from purchasing.payments p where p.payment_order_id = v_o.id and p.status <> 'voided'));
end
$$;
comment on function purchasing.payment_order_detail(uuid) is
  'La ficha imprimible de una orden de pago: quién paga, el proveedor y su cuenta (completa solo para quien paga o ve la condición de pago), los medios con sus cajas o cuentas y cheques, las facturas que cancela con sus notas, lo que quedó a cuenta, las retenciones, quién la registró y la versión. Pide purchasing.view_payments en el local.';
revoke execute on function purchasing.payment_order_detail(uuid) from public, anon;
grant execute on function purchasing.payment_order_detail(uuid) to authenticated;

-- El listado de órdenes de pago (con los permisos de quien consulta) y su conteo por proveedor (mismo where).
create function purchasing.payment_order_list(p_supplier_id uuid default null, p_restaurant_id uuid default null,
                                              p_limit integer default 15, p_offset integer default 0)
returns table (id uuid, number text, restaurant_id uuid, restaurant_name text, supplier_id uuid, supplier_name text,
               payer_name text, paid_on date, total_amount numeric, methods text[], status purchasing.payment_order_status,
               total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select o.id, o.number, o.restaurant_id, r.name, o.supplier_id, coalesce(s.trade_name, s.name), le.name, o.paid_on,
         o.total_amount,
         array(select distinct p.method::text from purchasing.payments p where p.payment_order_id = o.id order by 1),
         o.status, count(*) over ()
    from purchasing.payment_orders o
    join org.restaurants r on r.id = o.restaurant_id
    join catalog.suppliers s on s.id = o.supplier_id
    left join org.legal_entities le on le.id = o.legal_entity_id
   where o.deleted_at is null
     and (p_supplier_id is null or o.supplier_id = p_supplier_id)
     and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
   order by o.paid_on desc, o.created_at desc, o.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function purchasing.payment_order_list(uuid, uuid, integer, integer) is
  'Listado de órdenes de pago (las más nuevas primero), con los permisos de quien consulta: número, local, proveedor, quién paga, fecha, total, medios y estado. Filtra por proveedor y local, y pagina.';
revoke execute on function purchasing.payment_order_list(uuid, uuid, integer, integer) from public, anon;
grant execute on function purchasing.payment_order_list(uuid, uuid, integer, integer) to authenticated;

create function purchasing.payment_order_supplier_counts(p_restaurant_id uuid default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  -- No se lee nada de r: el join está porque la lista lo tiene (la RLS de org.restaurants deja afuera las mismas filas).
  select o.supplier_id, coalesce(s.trade_name, s.name), count(*)
    from purchasing.payment_orders o
    join org.restaurants r on r.id = o.restaurant_id
    join catalog.suppliers s on s.id = o.supplier_id
   where o.deleted_at is null
     and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
   group by o.supplier_id, coalesce(s.trade_name, s.name)
   order by lower(coalesce(s.trade_name, s.name)), o.supplier_id
$$;
comment on function purchasing.payment_order_supplier_counts(uuid) is
  'Cuántas órdenes de pago hay por proveedor, con los mismos filtros y permisos que purchasing.payment_order_list (sin el del proveedor). Para el panel izquierdo de Pagos.';
revoke execute on function purchasing.payment_order_supplier_counts(uuid) from public, anon;
grant execute on function purchasing.payment_order_supplier_counts(uuid) to authenticated;

-- «Registrar pago»: además de lo de antes, la razón social del local y sus cajas y cuentas activas.
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
      -- La cuenta completa (para transferir sin equivocarse, ADR-0070), solo de un proveedor que trabaja con este local
      -- (tiene facturas acá) o para quien ya ve la condición de pago. Si no, los últimos 4 números, como antes.
      select jsonb_agg(jsonb_build_object('id', a.id, 'method', a.method, 'bank', a.bank, 'alias', a.alias,
                                          'cbu', case when full_account.ok then a.cbu end,
                                          'cbu_end', right(a.cbu, 4), 'holder_name', a.holder_name,
                                          'holder_tax_id', case when full_account.ok then a.holder_tax_id end,
                                          'electronic_code', a.electronic_code)
                       order by a.method, a.created_at)
        from purchasing.supplier_payment_accounts a
        cross join lateral (select purchasing.can_see_payment(a.group_id)
                                   or exists (select 1 from purchasing.invoices i
                                               where i.restaurant_id = p_restaurant_id and i.supplier_id = p_supplier_id
                                                 and i.status <> 'cancelled' and i.deleted_at is null) as ok) full_account
       where a.supplier_id = p_supplier_id and a.is_active and a.deleted_at is null), '[]'::jsonb),
    'payer', (select jsonb_build_object('id', le.id, 'name', le.name, 'tax_id', le.tax_id)
                from org.restaurants r join org.legal_entities le on le.id = r.legal_entity_id
               where r.id = p_restaurant_id and le.deleted_at is null),
    'company_accounts', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'name', a.name) order by a.kind, a.name)
        from org.restaurants r
        join org.legal_entity_accounts a on a.legal_entity_id = r.legal_entity_id
       where r.id = p_restaurant_id and a.is_active and a.deleted_at is null), '[]'::jsonb)) end
$$;
comment on function purchasing.payable_invoices(uuid, uuid) is
  'Para «Registrar pago»: las facturas con saldo de un proveedor en un local, lo que tiene a cuenta, sus cuentas (el CBU y el CUIT del titular completos solo si trabaja con ese local o la sesión ve la condición de pago; si no, los últimos 4 números), la razón social que paga y sus cajas y cuentas activas. Pide purchasing.pay en el local.';

-- ---------------------------------------------------------------------------
-- 7. Facturas: el CAE al controlar, y los filtros nuevos del listado
-- ---------------------------------------------------------------------------
-- El alta corta (decisión de Soy) no pide el CAE: una factura fiscal cargada puede no tenerlo todavía. Punto de venta y
-- CUIT del emisor, siempre; la autorización, en cuanto deja de estar cargada (o cancelada).
alter table purchasing.invoices drop constraint invoices_fiscal_check;
alter table purchasing.invoices add constraint invoices_fiscal_check check (
  invoice_class in ('non_fiscal', 'handwritten_note')
  or (point_of_sale is not null and issuer_tax_id is not null));
alter table purchasing.invoices add constraint invoices_authorization_required_check check (
  invoice_class in ('non_fiscal', 'handwritten_note') or status in ('loaded', 'cancelled')
  or (authorization_kind is not null and authorization_code is not null));

-- «Controlar» pide el CAE antes (con el mensaje en castellano; la restricción queda de respaldo).
create or replace function purchasing.run_invoice_checks(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv    purchasing.invoices;
  v_status purchasing.invoice_status;
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id) then
    return core.deny('purchasing.run_invoice_checks', 'No tenés permiso para controlar esta factura.', null,
                     jsonb_build_object('invoice_id', p_id), v_inv.group_id, v_inv.brand_id, v_inv.restaurant_id);
  end if;
  if v_inv.invoice_class not in ('non_fiscal', 'handwritten_note')
     and (v_inv.authorization_kind is null or v_inv.authorization_code is null) then
    raise exception 'Cargá la autorización (CAE, CAI o CAEA y su número) antes de controlar.' using errcode = '22023';
  end if;
  perform core.set_change_context(format('Control de la %s',
                                         purchasing.invoice_label(v_inv.invoice_class, v_inv.point_of_sale, v_inv.number)),
                                  'manual');
  v_status := purchasing.check_invoice(v_inv.id);
  return jsonb_build_object('result', 'applied', 'invoice_id', v_inv.id, 'status', v_status);
end
$$;

-- El filtro de estado del listado, en un solo lugar (lo usan la lista y su conteo por proveedor).
create function purchasing.invoice_status_matches(p_id uuid, p_status purchasing.invoice_status,
                                                  p_restaurant_id uuid, p_created_by uuid, p_due_on date,
                                                  p_filter text)
returns boolean
language sql
stable
-- Definer: usa can_in_restaurant e invoice_balance (internas). La sesión sigue siendo la de quien consulta.
security definer
set search_path = ''
as $$
  select case
    when p_filter is null then p_status <> 'cancelled'
    -- Conforme y liberada a pago van juntas: el conforme libera en la misma transacción.
    when p_filter = 'released' then p_status in ('approved', 'released')
    -- «Para dar conforme»: observadas que esta sesión puede decidir y no cargó (doble firma).
    -- La misma regla que purchasing.approve_invoice: ni quien la cargó, ni quien la corrigió, ni quien le sumó una nota.
    when p_filter = 'to_approve' then p_status = 'observed'
                                     and purchasing.can_in_restaurant('purchasing.approve_invoices', p_restaurant_id)
                                     and not exists (
                                       select 1 from purchasing.invoices i
                                        where i.id = p_id
                                          and (i.loaded_by = core.current_actor_id()
                                               or core.current_actor_id() = any (i.edited_by)
                                               or exists (select 1 from purchasing.credit_debit_notes n
                                                           where n.invoice_id = i.id and n.deleted_at is null
                                                             and n.created_by = core.current_actor_id())))
    -- «Vencidas»: liberadas que todavía tienen saldo y ya vencieron.
    -- El saldo, solo de una factura que la sesión ve (la función es definer y recibe un id cualquiera).
    when p_filter = 'overdue' then p_status = 'released' and p_due_on < recipes.today()
                                  and exists (select 1 from purchasing.invoices i
                                               where i.id = p_id
                                                 and purchasing.can_in_restaurant('purchasing.view_invoices',
                                                                                  i.restaurant_id))
                                  and purchasing.invoice_balance(p_id) > 0.005
    else p_status::text = p_filter
  end
$$;
comment on function purchasing.invoice_status_matches(uuid, purchasing.invoice_status, uuid, uuid, date, text) is
  'El filtro de estado del listado de facturas (lo usan invoice_list e invoice_supplier_counts): sin filtro, todas menos las canceladas; released, conformes y liberadas; to_approve, las observadas que la sesión puede dar por conforme y no cargó; overdue, las liberadas con saldo y vencidas; si no, ese estado.';
revoke execute on function purchasing.invoice_status_matches(uuid, purchasing.invoice_status, uuid, uuid, date, text)
  from public, anon;
grant execute on function purchasing.invoice_status_matches(uuid, purchasing.invoice_status, uuid, uuid, date, text)
  to authenticated;

-- El listado de facturas con los estados de Soy: además de los de antes, «to_approve» (las observadas que la sesión
-- puede dar por conforme y no cargó ella: doble firma) y «overdue» (liberadas con saldo y vencidas).
create or replace function purchasing.invoice_list(p_status text default null, p_supplier_id uuid default null,
                                                   p_restaurant_id uuid default null, p_from date default null,
                                                   p_to date default null, p_limit integer default 15,
                                                   p_offset integer default 0)
returns table (id uuid, invoice_class purchasing.invoice_class, point_of_sale integer, number bigint,
               restaurant_id uuid, restaurant_name text, supplier_id uuid, supplier_name text, issued_on date,
               due_on date, total_amount numeric, status purchasing.invoice_status, failed text[], total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select i.id, i.invoice_class, i.point_of_sale, i.number, i.restaurant_id, coalesce(r.name, '—'), i.supplier_id,
         coalesce(s.trade_name, s.name, '—'), i.issued_on, i.due_on, i.total_amount, i.status,
         coalesce((select array_agg(distinct c.check_kind::text order by c.check_kind::text)
                     from purchasing.invoice_checks c
                    where c.invoice_id = i.id and not c.passed
                      and c.run_id = (select c2.run_id from purchasing.invoice_checks c2
                                       where c2.invoice_id = i.id order by c2.entry_number desc limit 1)),
                  '{}'),
         count(*) over ()
    from purchasing.invoices i
    left join org.restaurants r on r.id = i.restaurant_id
    left join catalog.suppliers s on s.id = i.supplier_id
   where i.deleted_at is null
     -- Los casos simples, en línea; la función, solo para los dos que la necesitan.
     and case when p_status is null then i.status <> 'cancelled'
              when p_status = 'released' then i.status in ('approved', 'released')
              when p_status in ('to_approve', 'overdue') then
                purchasing.invoice_status_matches(i.id, i.status, i.restaurant_id, i.created_by, i.due_on, p_status)
              else i.status::text = p_status end
     and (p_supplier_id is null or i.supplier_id = p_supplier_id)
     and (p_restaurant_id is null or i.restaurant_id = p_restaurant_id)
     and (p_from is null or i.issued_on >= p_from)
     and (p_to is null or i.issued_on <= p_to)
   order by i.issued_on desc, i.created_at desc, i.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;

create or replace function purchasing.invoice_supplier_counts(p_status text default null,
                                                              p_restaurant_id uuid default null,
                                                              p_from date default null, p_to date default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select i.supplier_id, coalesce(s.trade_name, s.name, '—'), count(*)
    from purchasing.invoices i
    left join catalog.suppliers s on s.id = i.supplier_id
   where i.deleted_at is null
     -- Los casos simples, en línea; la función, solo para los dos que la necesitan.
     and case when p_status is null then i.status <> 'cancelled'
              when p_status = 'released' then i.status in ('approved', 'released')
              when p_status in ('to_approve', 'overdue') then
                purchasing.invoice_status_matches(i.id, i.status, i.restaurant_id, i.created_by, i.due_on, p_status)
              else i.status::text = p_status end
     and (p_restaurant_id is null or i.restaurant_id = p_restaurant_id)
     and (p_from is null or i.issued_on >= p_from)
     and (p_to is null or i.issued_on <= p_to)
   group by i.supplier_id, coalesce(s.trade_name, s.name, '—')
   order by lower(coalesce(s.trade_name, s.name, '—')), i.supplier_id
$$;

-- ---------------------------------------------------------------------------
-- 8. Revisiones (2026-11-26)
-- ---------------------------------------------------------------------------
-- Un medio de una orden de pago no se anula suelto: la orden registrada no cambia (se anula entera). La anulación de
-- antes queda igual, como interna; la nueva, con el mismo nombre y firma, primero controla eso.
alter function purchasing.void_payment(uuid, text) rename to void_payment_internal;
revoke execute on function purchasing.void_payment_internal(uuid, text) from public, anon, authenticated;
comment on function purchasing.void_payment_internal(uuid, text) is
  'Interna: la anulación de un pago suelto (ADR-0060). La app usa purchasing.void_payment, que rechaza los medios de una orden de pago.';

create function purchasing.void_payment(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number text;
begin
  select o.number into v_number
    from purchasing.payments p join purchasing.payment_orders o on o.id = p.payment_order_id
   where p.id = p_id and p.deleted_at is null
     and purchasing.can_in_restaurant('purchasing.pay', p.restaurant_id);
  if v_number is not null then
    raise exception 'Este pago es parte de la orden %: anulá la orden entera.', v_number using errcode = '23514';
  end if;
  return purchasing.void_payment_internal(p_id, p_reason);
end
$$;
comment on function purchasing.void_payment(uuid, text) is
  'Anula un pago suelto, con motivo (ADR-0060). Un medio de una orden de pago no se anula solo: se anula la orden (purchasing.void_payment_order).';
revoke execute on function purchasing.void_payment(uuid, text) from public, anon;
grant execute on function purchasing.void_payment(uuid, text) to authenticated;

-- El control de una factura fiscal sin CAE no corre (queda cargada): lo pide «Controlar» con su mensaje. Así subir la
-- foto de una nota de crédito a una factura cargada sin CAE no choca con invoices_authorization_required_check.
alter function purchasing.check_invoice(uuid) rename to check_invoice_internal;
revoke execute on function purchasing.check_invoice_internal(uuid) from public, anon, authenticated;
comment on function purchasing.check_invoice_internal(uuid) is
  'Interna: el control de 3 vías de una factura (ADR-0058). Se llama desde purchasing.check_invoice.';

create function purchasing.check_invoice(p_id uuid)
returns purchasing.invoice_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv purchasing.invoices;
begin
  select * into v_inv from purchasing.invoices where id = p_id;
  if v_inv.status = 'loaded' and v_inv.invoice_class not in ('non_fiscal', 'handwritten_note')
     and (v_inv.authorization_kind is null or v_inv.authorization_code is null) then
    return v_inv.status;
  end if;
  return purchasing.check_invoice_internal(p_id);
end
$$;
comment on function purchasing.check_invoice(uuid) is
  'Interna: controla una factura (purchasing.check_invoice_internal), salvo una fiscal cargada sin su autorización, que queda cargada hasta tenerla (ADR-0070).';
revoke execute on function purchasing.check_invoice(uuid) from public, anon, authenticated;

-- Comentarios de las columnas que faltaban.
comment on column org.legal_entity_accounts.id is 'Identificador de la caja o cuenta.';
comment on column org.legal_entity_accounts.group_id is 'Grupo al que pertenece.';
comment on column org.legal_entity_accounts.legal_entity_id is 'Razón social dueña de la caja o cuenta.';
comment on column org.legal_entity_accounts.currency is 'Moneda (por ahora, solo pesos).';
comment on column org.legal_entity_accounts.created_at is 'Cuándo se cargó.';
comment on column org.legal_entity_accounts.created_by is 'Quién la cargó (lo completa un trigger).';
comment on column org.legal_entity_accounts.updated_at is 'Último cambio.';
comment on column org.legal_entity_accounts.updated_by is 'Quién la cambió por última vez (lo completa un trigger).';
comment on column org.legal_entity_accounts.deleted_at is 'Baja lógica: desde cuándo no se usa.';
comment on column org.legal_entity_accounts.deleted_by is 'Quién la dio de baja.';
comment on column purchasing.payment_orders.id is 'Identificador de la orden de pago.';
comment on column purchasing.payment_orders.group_id is 'Grupo al que pertenece.';
comment on column purchasing.payment_orders.brand_id is 'Marca del local que paga.';
comment on column purchasing.payment_orders.restaurant_id is 'Local que paga.';
comment on column purchasing.payment_orders.supplier_id is 'Proveedor al que se le paga.';
comment on column purchasing.payment_orders.paid_on is 'Fecha del pago.';
comment on column purchasing.payment_orders.currency is 'Moneda (por ahora, solo pesos).';
comment on column purchasing.payment_orders.notes is 'Observaciones que van en la orden impresa.';
comment on column purchasing.payment_orders.status is 'Registrada o anulada.';
comment on column purchasing.payment_orders.voided_reason is 'Por qué se anuló.';
comment on column purchasing.payment_orders.voided_at is 'Cuándo se anuló.';
comment on column purchasing.payment_orders.voided_by is 'Quién la anuló.';
comment on column purchasing.payment_orders.created_at is 'Cuándo se registró.';
comment on column purchasing.payment_orders.created_by is 'Quién la registró (lo completa un trigger).';
comment on column purchasing.payment_orders.updated_at is 'Último cambio (solo la anulación).';
comment on column purchasing.payment_orders.updated_by is 'Quién la cambió por última vez (lo completa un trigger).';
comment on column purchasing.payment_orders.deleted_at is 'Baja lógica (no se usa: una orden se anula, no se borra).';
comment on column purchasing.payment_orders.deleted_by is 'Quién la dio de baja.';
