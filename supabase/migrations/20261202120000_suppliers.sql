-- Fase 3, Prompt 1 (ADR-0050): ficha completa de proveedor.
--
-- catalog.suppliers se completa (contacto y datos fiscales). La operativa, el pago, los rubros y los números de
-- cliente van en el esquema nuevo purchasing, cada uno en su tabla: la RLS es por fila, así el pago (condición y
-- cuentas) lo lee solo quien lo administra o el Controller, nunca el cocinero.
-- Toda escritura va por funciones con motivo; la API solo lee (ADR-0005).

-- ---------------------------------------------------------------------------
-- 1. CUIT: once números con dígito verificador
-- ---------------------------------------------------------------------------
-- Pesos 5 4 3 2 7 6 5 4 3 2 sobre los diez primeros números; el verificador es 11 − (suma mod 11),
-- con 11 → 0 y 10 → 9 (como lo resuelven los validadores de uso común).
create function core.valid_cuit(p_tax_id text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_tax_id is null or p_tax_id !~ '^[0-9]{11}$' then false
    else (select (case 11 - (x.s % 11) when 11 then 0 when 10 then 9 else 11 - (x.s % 11) end)
                 = substr(p_tax_id, 11, 1)::integer
            from (select sum(substr(p_tax_id, i, 1)::integer * (array[5, 4, 3, 2, 7, 6, 5, 4, 3, 2])[i]) as s
                    from generate_series(1, 10) as i) as x)
  end
$$;
comment on function core.valid_cuit(text) is
  'Si el texto es un CUIT de 11 números con su dígito verificador correcto (sin guiones). La misma regla está en lib/suppliers.ts (validCuit).';

-- Saca espacios, puntos y guiones. Vacío → nulo. Las letras quedan, para que el check las rechace.
create function core.normalize_cuit(p_tax_id text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(regexp_replace(coalesce(p_tax_id, ''), '[[:space:].-]', '', 'g'), '')
$$;
comment on function core.normalize_cuit(text) is 'Interna: el CUIT sin espacios, puntos ni guiones (vacío = nulo).';

-- ---------------------------------------------------------------------------
-- 2. catalog.suppliers se completa
-- ---------------------------------------------------------------------------
alter table catalog.suppliers
  add column trade_name    text,
  add column vat_condition org.vat_condition,
  add column address       text,
  add column city          text,
  add column phone         text,
  add column whatsapp      text,
  add column email         text,
  add column sales_contact text,
  add column admin_contact text,
  add constraint suppliers_trade_name_check check (trade_name is null or length(btrim(trade_name)) between 1 and 120),
  add constraint suppliers_address_check check (address is null or length(btrim(address)) between 1 and 200),
  add constraint suppliers_city_check check (city is null or length(btrim(city)) between 1 and 120),
  add constraint suppliers_phone_check check (phone is null or phone ~ '^[0-9 +()-]{6,30}$'),
  add constraint suppliers_whatsapp_check check (whatsapp is null or whatsapp ~ '^[0-9 +()-]{6,30}$'),
  add constraint suppliers_email_check check (
    email is null or (length(email) <= 320 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  add constraint suppliers_sales_contact_check check (
    sales_contact is null or length(btrim(sales_contact)) between 1 and 120),
  add constraint suppliers_admin_contact_check check (
    admin_contact is null or length(btrim(admin_contact)) between 1 and 120);
-- El CUIT se controla cuando se carga o se cambia (trigger), no con un check: un check se evalúa en cada update y un
-- proveedor viejo con el CUIT mal cargado no se podría ni desactivar. El check viejo («números y guiones») sale.
alter table catalog.suppliers drop constraint suppliers_tax_id_check;
create function catalog.guard_supplier_tax_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.tax_id is not null and (tg_op = 'INSERT' or new.tax_id is distinct from old.tax_id)
     and not core.valid_cuit(new.tax_id) then
    raise exception 'El CUIT no es válido: revisá los números.'
      using errcode = '23514', constraint = 'suppliers_tax_id_valid';
  end if;
  return new;
end
$$;
comment on function catalog.guard_supplier_tax_id() is
  'Interna: un CUIT nuevo o cambiado tiene 11 números y su dígito verificador válido. Los cargados antes de la Fase 3 no se controlan hasta que alguien los cambia.';
create trigger guard_supplier_tax_id before insert or update of tax_id on catalog.suppliers
  for each row execute function catalog.guard_supplier_tax_id();
-- Los de antes que quedan válidos sin los guiones, se normalizan ahora. Los inválidos quedan como estaban y la ficha
-- avisa.
do $$
begin
  perform core.set_change_context('CUIT de proveedores sin guiones (ADR-0050)', 'maintenance');
  update catalog.suppliers
     set tax_id = core.normalize_cuit(tax_id)
   where tax_id is not null and tax_id <> core.normalize_cuit(tax_id) and core.valid_cuit(core.normalize_cuit(tax_id));
end
$$;

comment on column catalog.suppliers.name is
  'Razón social (como figura en el CUIT). Única dentro del grupo entre los vigentes, sin importar mayúsculas.';
comment on column catalog.suppliers.tax_id is
  'CUIT: 11 números sin guiones y con dígito verificador válido (trigger guard_supplier_tax_id). Opcional (un puesto del mercado no tiene). Uno cargado antes de la Fase 3 con el verificador mal queda hasta que alguien lo corrige.';
comment on column catalog.suppliers.trade_name is 'Nombre de fantasía, como lo conoce el local.';
comment on column catalog.suppliers.vat_condition is 'Condición frente al IVA del proveedor: responsable inscripto, monotributo o exento.';
comment on column catalog.suppliers.address is 'Domicilio.';
comment on column catalog.suppliers.city is 'Localidad.';
comment on column catalog.suppliers.phone is 'Teléfono.';
comment on column catalog.suppliers.whatsapp is 'WhatsApp de contacto (el de envío de pedidos va en purchasing.supplier_terms).';
comment on column catalog.suppliers.email is 'Correo de contacto.';
comment on column catalog.suppliers.sales_contact is 'Contacto de ventas (nombre y, si hace falta, teléfono).';
comment on column catalog.suppliers.admin_contact is 'Contacto de administración (cobranzas).';

-- ---------------------------------------------------------------------------
-- 3. Permisos del módulo
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de proveedores (Fase 3, ADR-0050)', 'maintenance');
  insert into core.permission_modules (code, name, sort_order) values ('purchasing', 'Compras', 160);
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('purchasing.view_suppliers', 'purchasing', 'view_suppliers', 'Ver proveedores', 10,
     'Ver la ficha de los proveedores: datos, contacto, días de pedido y entrega, canal de envío y rubros.', false),
    ('purchasing.manage_suppliers', 'purchasing', 'manage_suppliers', 'Administrar proveedores', 20,
     'Dar de alta, editar, desactivar y reactivar proveedores, con su condición de pago y sus cuentas bancarias.', true),
    ('purchasing.view_payment_terms', 'purchasing', 'view_payment_terms', 'Ver pago a proveedores', 30,
     'Ver la condición de pago, el pedido mínimo y las cuentas bancarias de los proveedores, sin editarlos.', true);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values
      -- Superadmin: los permisos de quienes puede suspender o desactivar (Compras y el resto), como en la Fase 1 (G2) y
      -- la Fase 2: nadie administra a alguien con un permiso que no tiene. Con manage_suppliers ve el pago (excepción
      -- aceptada por Joaco el 2026-11-15, ADR-0050; tiene doble verificación obligatoria).
      ('superadmin', 'purchasing.view_suppliers'), ('superadmin', 'purchasing.manage_suppliers'),
      ('general_management', 'purchasing.view_suppliers'), ('general_management', 'purchasing.manage_suppliers'),
      ('general_management', 'purchasing.view_payment_terms'),
      ('brand_director', 'purchasing.view_suppliers'),
      ('restaurant_manager', 'purchasing.view_suppliers'),
      ('executive_chef', 'purchasing.view_suppliers'),
      ('head_chef', 'purchasing.view_suppliers'),
      ('controller', 'purchasing.view_suppliers'), ('controller', 'purchasing.view_payment_terms'),
      ('purchasing', 'purchasing.view_suppliers'), ('purchasing', 'purchasing.manage_suppliers'),
      ('cook', 'purchasing.view_suppliers'),
      ('auditor', 'purchasing.view_suppliers')
    ) as v (role_code, permission_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = v.permission_code and p.deleted_at is null;
end
$$;

-- El cocinero (purchasing.view_suppliers sin catalog.view) también lee los proveedores. Esta tabla no tiene datos
-- sensibles: el pago va aparte.
drop policy suppliers_select on catalog.suppliers;
create policy suppliers_select on catalog.suppliers for select to authenticated
  using (deleted_at is null
         and (group_id in (select core.visible_group_ids('catalog.view'))
              or group_id in (select core.visible_group_ids('purchasing.view_suppliers'))));

-- ---------------------------------------------------------------------------
-- 4. Esquema purchasing y sus tipos
-- ---------------------------------------------------------------------------
create schema if not exists purchasing;
comment on schema purchasing is
  'Compras (Fase 3, ADR-0049): proveedores ampliados y, en los próximos prompts, listas de precios, órdenes de compra, recepciones, facturas y pagos.';
grant usage on schema purchasing to authenticated;

create type purchasing.channel as enum ('whatsapp', 'email', 'supplier_portal');
comment on type purchasing.channel is
  'Por dónde se le manda la orden de compra al proveedor: WhatsApp, correo o el sistema propio del proveedor (una dirección web).';
create type purchasing.billing_mode as enum (
  'a', 'b', 'c', 'invoice_remito', 'remito_then_invoice', 'non_fiscal', 'handwritten_note');
comment on type purchasing.billing_mode is
  'Cómo factura un proveedor: factura A, B o C; factura/remito en un solo papel; remito y la factura después; comprobante no fiscal (X); nota de pedido escrita a mano.';
create type purchasing.list_frequency as enum ('weekly', 'biweekly', 'monthly');
comment on type purchasing.list_frequency is
  'Cada cuánto manda su lista de precios: semanal (7 días), quincenal (15) o mensual (31).';
create type purchasing.payment_terms as enum ('cash', 'cash_on_delivery', 'same_day_transfer', 'account');
comment on type purchasing.payment_terms is
  'Condición de pago: contado, contado contra entrega, transferencia en el día o cuenta corriente a N días (desde la fecha de la factura).';
create type purchasing.payment_method as enum ('cash', 'transfer', 'check', 'echeq', 'card', 'electronic_code');
comment on type purchasing.payment_method is
  'Medio de pago: efectivo, transferencia, cheque, eCheq, tarjeta o pago electrónico con código (Rapipago, PagoMisCuentas).';

-- Días de la semana: 1 = lunes … 7 = domingo, sin repetir.
create function purchasing.valid_days(p_days smallint[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_days is not null
     and p_days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
     and cardinality(p_days) = (select count(distinct d) from unnest(p_days) as d)
$$;
comment on function purchasing.valid_days(smallint[]) is 'Interna: días de 1 (lunes) a 7 (domingo), sin repetir.';

create function purchasing.distinct_billing_modes(p_modes purchasing.billing_mode[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_modes is not null and cardinality(p_modes) = (select count(distinct m) from unnest(p_modes) as m)
$$;
comment on function purchasing.distinct_billing_modes(purchasing.billing_mode[]) is
  'Interna: cada forma de facturar va una sola vez.';

-- El dato del canal: un teléfono para WhatsApp, un correo para mail, una dirección https:// para el portal.
create function purchasing.valid_channel_target(p_channel purchasing.channel, p_target text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_channel
    when 'whatsapp' then p_target ~ '^\+?[0-9 ()-]{6,30}$'
    when 'email' then length(p_target) <= 320 and p_target ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    when 'supplier_portal' then p_target ~ '^https://[^[:space:]]{3,250}$'
    else false
  end
$$;
comment on function purchasing.valid_channel_target(purchasing.channel, text) is
  'Interna: si el dato corresponde al canal (teléfono, correo o dirección https://).';

-- ---------------------------------------------------------------------------
-- 5. Tablas
-- ---------------------------------------------------------------------------
create table purchasing.supplier_terms (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references org.groups (id) on delete restrict,
  supplier_id           uuid not null,
  order_days            smallint[] not null default '{}',
  delivery_days         smallint[] not null default '{}',
  receiving_from        time,
  receiving_to          time,
  po_channel            purchasing.channel,
  po_channel_target     text,
  billing_modes         purchasing.billing_mode[] not null default '{}',
  price_list_frequency  purchasing.list_frequency,
  requires_po_approval  boolean not null default false,
  created_at            timestamptz not null default now(),
  created_by            uuid references core.actors (id) on delete restrict,
  updated_at            timestamptz not null default now(),
  updated_by            uuid references core.actors (id) on delete restrict,
  deleted_at            timestamptz,
  deleted_by            uuid references core.actors (id) on delete restrict,
  constraint supplier_terms_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint supplier_terms_order_days_check check (purchasing.valid_days(order_days)),
  constraint supplier_terms_delivery_days_check check (purchasing.valid_days(delivery_days)),
  constraint supplier_terms_receiving_check check (
    (receiving_from is null) = (receiving_to is null) and (receiving_from is null or receiving_from < receiving_to)),
  constraint supplier_terms_channel_check check (
    (po_channel is null) = (po_channel_target is null)
    and (po_channel is null or purchasing.valid_channel_target(po_channel, po_channel_target))),
  constraint supplier_terms_billing_check check (purchasing.distinct_billing_modes(billing_modes))
);
create unique index supplier_terms_supplier_key on purchasing.supplier_terms (supplier_id) where deleted_at is null;
create index supplier_terms_supplier_idx on purchasing.supplier_terms (supplier_id, group_id);
create index supplier_terms_group_idx on purchasing.supplier_terms (group_id);
comment on table purchasing.supplier_terms is
  'Operativa de cada proveedor (una fila por proveedor): días de pedido y entrega, horario de recepción, canal de envío de la orden de compra, cómo factura, cada cuánto manda la lista y si la OC necesita aprobación. Lo ve quien ve proveedores.';
comment on column purchasing.supplier_terms.group_id is 'Grupo, el mismo que el del proveedor.';
comment on column purchasing.supplier_terms.supplier_id is 'Proveedor.';
comment on column purchasing.supplier_terms.order_days is 'Días en que se le puede pedir: 1 = lunes … 7 = domingo.';
comment on column purchasing.supplier_terms.delivery_days is 'Días en que entrega: 1 = lunes … 7 = domingo. La fecha de entrega esperada de una OC sale de acá.';
comment on column purchasing.supplier_terms.receiving_from is 'Desde qué hora se le recibe.';
comment on column purchasing.supplier_terms.receiving_to is 'Hasta qué hora se le recibe (después de «desde»).';
comment on column purchasing.supplier_terms.po_channel is 'Canal por el que se le manda la orden de compra, siempre desde la cuenta de la empresa.';
comment on column purchasing.supplier_terms.po_channel_target is 'El dato del canal: número de WhatsApp, correo o dirección del portal.';
comment on column purchasing.supplier_terms.billing_modes is 'Cómo factura (puede ser más de una forma).';
comment on column purchasing.supplier_terms.price_list_frequency is 'Cada cuánto manda su lista de precios. Sin dato, la lista no vence.';
comment on column purchasing.supplier_terms.requires_po_approval is
  'Si una orden de compra a este proveedor la aprueba Compras antes de enviarse (nunca quien la pidió).';

create table purchasing.supplier_payment_terms (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references org.groups (id) on delete restrict,
  supplier_id           uuid not null,
  payment_terms         purchasing.payment_terms not null,
  payment_days          smallint not null default 0,
  minimum_order_amount  numeric(14,4),
  currency              text not null default 'ARS' check (currency = 'ARS'),
  created_at            timestamptz not null default now(),
  created_by            uuid references core.actors (id) on delete restrict,
  updated_at            timestamptz not null default now(),
  updated_by            uuid references core.actors (id) on delete restrict,
  deleted_at            timestamptz,
  deleted_by            uuid references core.actors (id) on delete restrict,
  constraint supplier_payment_terms_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint supplier_payment_terms_days_check check (
    (payment_terms = 'account' and payment_days between 1 and 180)
    or (payment_terms <> 'account' and payment_days = 0)),
  constraint supplier_payment_terms_minimum_check check (minimum_order_amount is null or minimum_order_amount > 0)
);
create unique index supplier_payment_terms_supplier_key on purchasing.supplier_payment_terms (supplier_id)
  where deleted_at is null;
create index supplier_payment_terms_supplier_idx on purchasing.supplier_payment_terms (supplier_id, group_id);
create index supplier_payment_terms_group_idx on purchasing.supplier_payment_terms (group_id);
comment on table purchasing.supplier_payment_terms is
  'Condición de pago y pedido mínimo de cada proveedor (una fila por proveedor). Solo lo ven quien administra proveedores y quien ve el pago (Controller): el cocinero no.';
comment on column purchasing.supplier_payment_terms.group_id is 'Grupo, el mismo que el del proveedor.';
comment on column purchasing.supplier_payment_terms.supplier_id is 'Proveedor.';
comment on column purchasing.supplier_payment_terms.payment_terms is 'Condición de pago.';
comment on column purchasing.supplier_payment_terms.payment_days is
  'Días desde la fecha de la factura: de 1 a 180 en cuenta corriente, 0 en el resto.';
comment on column purchasing.supplier_payment_terms.minimum_order_amount is 'Pedido mínimo, si tiene, en la moneda de currency.';
comment on column purchasing.supplier_payment_terms.currency is 'Moneda del pedido mínimo: por ahora, solo pesos (ARS).';

create table purchasing.supplier_payment_accounts (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references org.groups (id) on delete restrict,
  supplier_id      uuid not null,
  method           purchasing.payment_method not null,
  cbu              text,
  alias            text,
  bank             text,
  holder_name      text,
  holder_tax_id    text,
  electronic_code  text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references core.actors (id) on delete restrict,
  deleted_at       timestamptz,
  deleted_by       uuid references core.actors (id) on delete restrict,
  constraint supplier_payment_accounts_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint supplier_payment_accounts_cbu_check check (cbu is null or cbu ~ '^[0-9]{22}$'),
  constraint supplier_payment_accounts_alias_check check (alias is null or alias ~ '^[A-Za-z0-9.-]{6,20}$'),
  constraint supplier_payment_accounts_bank_check check (bank is null or length(btrim(bank)) between 1 and 80),
  constraint supplier_payment_accounts_holder_name_check check (
    holder_name is null or length(btrim(holder_name)) between 1 and 120),
  constraint supplier_payment_accounts_holder_tax_id_check check (holder_tax_id is null or core.valid_cuit(holder_tax_id)),
  constraint supplier_payment_accounts_code_check check (
    electronic_code is null or electronic_code ~ '^[0-9A-Za-z-]{4,40}$'),
  constraint supplier_payment_accounts_method_check check (
    (method <> 'transfer' or cbu is not null or alias is not null)
    and (method <> 'electronic_code' or electronic_code is not null))
);
create index supplier_payment_accounts_supplier_idx on purchasing.supplier_payment_accounts (supplier_id, group_id);
create index supplier_payment_accounts_group_idx on purchasing.supplier_payment_accounts (group_id);
comment on table purchasing.supplier_payment_accounts is
  'Cómo se le paga a cada proveedor: medios y cuentas (puede tener varias). Solo lo ven quien administra proveedores y quien ve el pago (Controller): el cocinero no.';
comment on column purchasing.supplier_payment_accounts.group_id is 'Grupo, el mismo que el del proveedor.';
comment on column purchasing.supplier_payment_accounts.supplier_id is 'Proveedor.';
comment on column purchasing.supplier_payment_accounts.method is 'Medio de pago.';
comment on column purchasing.supplier_payment_accounts.cbu is 'CBU o CVU: 22 números. La transferencia pide CBU o alias.';
comment on column purchasing.supplier_payment_accounts.alias is 'Alias de la cuenta (6 a 20 letras, números, puntos o guiones).';
comment on column purchasing.supplier_payment_accounts.bank is 'Banco o billetera.';
comment on column purchasing.supplier_payment_accounts.holder_name is 'A nombre de quién está la cuenta.';
comment on column purchasing.supplier_payment_accounts.holder_tax_id is 'CUIT del titular (11 números, dígito verificador válido).';
comment on column purchasing.supplier_payment_accounts.electronic_code is
  'Código de pago electrónico (Rapipago, PagoMisCuentas). Obligatorio en ese medio.';
comment on column purchasing.supplier_payment_accounts.is_active is 'Si se sigue usando. Una cuenta vieja se desactiva, no se borra.';

create table purchasing.supplier_categories (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references org.groups (id) on delete restrict,
  supplier_id  uuid not null,
  category_id  uuid not null,
  created_at   timestamptz not null default now(),
  created_by   uuid references core.actors (id) on delete restrict,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references core.actors (id) on delete restrict,
  deleted_at   timestamptz,
  deleted_by   uuid references core.actors (id) on delete restrict,
  constraint supplier_categories_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint supplier_categories_category_fkey foreign key (category_id, group_id)
    references catalog.ingredient_categories (id, group_id) on delete restrict
);
create unique index supplier_categories_key on purchasing.supplier_categories (supplier_id, category_id)
  where deleted_at is null;
create index supplier_categories_category_idx on purchasing.supplier_categories (category_id, group_id);
create index supplier_categories_supplier_idx on purchasing.supplier_categories (supplier_id, group_id);
create index supplier_categories_group_idx on purchasing.supplier_categories (group_id);
comment on table purchasing.supplier_categories is 'Rubros de compra (primer nivel) que provee cada proveedor.';
comment on column purchasing.supplier_categories.group_id is 'Grupo, el mismo que el del proveedor y el del rubro.';
comment on column purchasing.supplier_categories.supplier_id is 'Proveedor.';
comment on column purchasing.supplier_categories.category_id is 'Rubro de compra de primer nivel (MP-XXX).';

create table purchasing.supplier_customer_numbers (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references org.groups (id) on delete restrict,
  supplier_id      uuid not null,
  restaurant_id    uuid not null,
  customer_number  text not null,
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references core.actors (id) on delete restrict,
  deleted_at       timestamptz,
  deleted_by       uuid references core.actors (id) on delete restrict,
  constraint supplier_customer_numbers_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint supplier_customer_numbers_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint supplier_customer_numbers_number_check check (length(btrim(customer_number)) between 1 and 30)
);
create unique index supplier_customer_numbers_key on purchasing.supplier_customer_numbers (supplier_id, restaurant_id)
  where deleted_at is null;
create index supplier_customer_numbers_restaurant_idx on purchasing.supplier_customer_numbers (restaurant_id, group_id);
create index supplier_customer_numbers_supplier_idx on purchasing.supplier_customer_numbers (supplier_id, group_id);
create index supplier_customer_numbers_group_idx on purchasing.supplier_customer_numbers (group_id);
comment on table purchasing.supplier_customer_numbers is
  'Con qué número de cliente nos tiene cada proveedor en cada local (cada uno nos tiene con su propio número). Va en el mensaje de la OC.';
comment on column purchasing.supplier_customer_numbers.group_id is 'Grupo, el mismo que el del proveedor y el del local.';
comment on column purchasing.supplier_customer_numbers.supplier_id is 'Proveedor.';
comment on column purchasing.supplier_customer_numbers.restaurant_id is 'Local.';
comment on column purchasing.supplier_customer_numbers.customer_number is 'Nuestro número de cliente en ese proveedor, para ese local.';

-- Control, auditoría, RLS y comentarios comunes.
do $$
declare
  t text;
begin
  foreach t in array array['supplier_terms', 'supplier_payment_terms', 'supplier_payment_accounts',
                           'supplier_categories', 'supplier_customer_numbers'] loop
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

  -- Lo que ve quien ve proveedores.
  foreach t in array array['supplier_terms', 'supplier_categories'] loop
    execute format(
      'create policy %I on purchasing.%I for select to authenticated
         using (deleted_at is null and group_id in (select core.visible_group_ids(''purchasing.view_suppliers'')))',
      t || '_select', t);
  end loop;
  -- El pago: solo quien administra proveedores o quien ve el pago, y para todo el grupo (decisión de Joaco,
  -- 2026-11-15): un Controller de un local no ve las cuentas de todos los proveedores.
  foreach t in array array['supplier_payment_terms', 'supplier_payment_accounts'] loop
    execute format(
      'create policy %I on purchasing.%I for select to authenticated
         using (deleted_at is null
                and (group_id in (select core.permitted_group_ids(''purchasing.manage_suppliers''))
                     or group_id in (select core.permitted_group_ids(''purchasing.view_payment_terms''))))',
      t || '_select', t);
  end loop;
  -- Los números de cliente, por local: cada uno ve los de los locales que ve.
  create policy supplier_customer_numbers_select on purchasing.supplier_customer_numbers for select to authenticated
    using (deleted_at is null
           and restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_suppliers')));
end
$$;

-- ---------------------------------------------------------------------------
-- 6. Mensajes claros
-- ---------------------------------------------------------------------------
create function purchasing.raise_friendly(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'suppliers_tax_id_valid' then 'El CUIT no es válido: revisá los números.'
    when p_constraint = 'suppliers_email_check' then 'Revisá el correo.'
    when p_constraint in ('suppliers_phone_check', 'suppliers_whatsapp_check') then
      'El teléfono va con números, espacios, +, guiones o paréntesis (de 6 a 30).'
    when p_constraint in ('suppliers_trade_name_check', 'suppliers_city_check', 'suppliers_sales_contact_check',
                          'suppliers_admin_contact_check') then
      'El texto no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint = 'suppliers_address_check' then 'El domicilio no puede quedar vacío ni pasar los 200 caracteres.'
    when p_constraint in ('supplier_terms_order_days_check', 'supplier_terms_delivery_days_check') then
      'Los días van de lunes a domingo, sin repetir.'
    when p_constraint = 'supplier_terms_receiving_check' then
      'El horario de recepción va con «desde» y «hasta», y «desde» es antes que «hasta».'
    when p_constraint = 'supplier_terms_channel_check' then
      'El dato no corresponde al canal: un teléfono para WhatsApp, un correo para mail o una dirección https:// para el portal.'
    when p_constraint = 'supplier_terms_billing_check' then 'Cada forma de facturar va una sola vez.'
    when p_constraint = 'supplier_payment_terms_days_check' then
      'En cuenta corriente, los días van de 1 a 180. En el resto de las condiciones no van días.'
    when p_constraint = 'supplier_payment_terms_minimum_check' then 'El pedido mínimo tiene que ser mayor que cero.'
    when p_constraint = 'supplier_payment_accounts_cbu_check' then 'El CBU tiene 22 números.'
    when p_constraint = 'supplier_payment_accounts_alias_check' then
      'El alias va de 6 a 20 caracteres: letras, números, puntos o guiones.'
    when p_constraint = 'supplier_payment_accounts_holder_tax_id_check' then 'El CUIT del titular no es válido.'
    when p_constraint = 'supplier_payment_accounts_code_check' then
      'El código de pago electrónico va de 4 a 40 letras, números o guiones.'
    when p_constraint = 'supplier_payment_accounts_method_check' then
      'La transferencia necesita CBU o alias, y el pago electrónico, su código.'
    when p_constraint in ('supplier_payment_accounts_bank_check', 'supplier_payment_accounts_holder_name_check') then
      'El banco o el titular no pueden quedar vacíos ni ser tan largos.'
    when p_constraint = 'supplier_categories_key' then 'Ese rubro ya está cargado.'
    when p_constraint = 'supplier_customer_numbers_key' then 'Ese local ya tiene un número de cliente con este proveedor.'
    when p_constraint = 'supplier_customer_numbers_number_check' then 'El número de cliente va de 1 a 30 caracteres.'
    when p_constraint = 'supplier_customer_numbers_restaurant_fkey' then 'El local elegido no es de este grupo.'
    when p_constraint = 'supplier_categories_category_fkey' then 'El rubro elegido no es de este grupo.'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la ficha.'
    else null
  end;
  if v_message is null then
    perform catalog.raise_friendly(p_state, p_constraint, p_message);
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function purchasing.raise_friendly(text, text, text) is
  'Interna: traduce a un mensaje en español el error de una restricción de proveedores (y, si no es suya, usa la del catálogo).';
revoke execute on function purchasing.raise_friendly(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 7. Alta, ficha y estado
-- ---------------------------------------------------------------------------
-- El último cambio de la ficha (proveedor y todo lo que cuelga de él, también lo borrado).
create function purchasing.supplier_sheet_stamp_internal(p_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    (select updated_at from catalog.suppliers where id = p_id),
    (select max(updated_at) from purchasing.supplier_terms where supplier_id = p_id),
    (select max(updated_at) from purchasing.supplier_payment_terms where supplier_id = p_id),
    (select max(updated_at) from purchasing.supplier_payment_accounts where supplier_id = p_id),
    (select max(updated_at) from purchasing.supplier_categories where supplier_id = p_id),
    (select max(updated_at) from purchasing.supplier_customer_numbers where supplier_id = p_id))
$$;
comment on function purchasing.supplier_sheet_stamp_internal(uuid) is
  'Interna: el último cambio de la ficha de un proveedor (el proveedor, su operativa, su pago, sus cuentas, rubros y números de cliente).';
revoke execute on function purchasing.supplier_sheet_stamp_internal(uuid) from public;

-- Quién ve el pago de los proveedores de un grupo: quien los administra o quien ve el pago, para todo el grupo. La misma
-- regla que las políticas de supplier_payment_terms y supplier_payment_accounts.
create function purchasing.can_see_payment(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select core.has_permission_in_group('purchasing.manage_suppliers', p_group_id)
      or core.has_permission_in_group('purchasing.view_payment_terms', p_group_id)
$$;
comment on function purchasing.can_see_payment(uuid) is
  'Interna: si la sesión ve el pago de los proveedores del grupo (condición y cuentas), con el permiso para todo el grupo.';
revoke execute on function purchasing.can_see_payment(uuid) from public;

-- Lo que la pantalla necesita además de lo que lee por RLS: el sello para guardar y qué puede hacer la sesión.
create function purchasing.supplier_sheet_state(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from catalog.suppliers where id = p_id and deleted_at is null;
  if v_group is null
     or not (v_group in (select core.visible_group_ids('purchasing.view_suppliers'))
             or v_group in (select core.visible_group_ids('catalog.view'))) then
    return null;
  end if;
  return jsonb_build_object(
    'stamp', purchasing.supplier_sheet_stamp_internal(p_id),
    'can_manage', core.has_permission_in_group('purchasing.manage_suppliers', v_group),
    'can_see_payment', purchasing.can_see_payment(v_group),
    -- Un CUIT cargado antes de la Fase 3 con el verificador mal: la ficha lo avisa.
    'tax_id_invalid', (select tax_id is not null and not core.valid_cuit(tax_id) from catalog.suppliers where id = p_id));
end
$$;
comment on function purchasing.supplier_sheet_state(uuid) is
  'Sello de la ficha de un proveedor y qué puede hacer la sesión (editar, ver el pago). Vacío si no lo ve. La base vuelve a controlar todo al guardar.';
revoke execute on function purchasing.supplier_sheet_state(uuid) from public;
grant execute on function purchasing.supplier_sheet_state(uuid) to authenticated;

create function purchasing.create_supplier(p_group_id uuid, p_name text, p_tax_id text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_id         uuid;
begin
  perform org.require(core.has_permission_in_group('purchasing.manage_suppliers', p_group_id),
                      'dar de alta proveedores en este grupo');
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo del alta.' using errcode = '22023';
  end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'Escribí la razón social.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.suppliers (group_id, code, name, tax_id)
  values (p_group_id, catalog.next_code(p_group_id, 'PROV-', 4), btrim(p_name), core.normalize_cuit(p_tax_id))
  returning id into v_id;
  insert into purchasing.supplier_terms (group_id, supplier_id) values (p_group_id, v_id);
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.create_supplier(uuid, text, text, text) is
  'Da de alta un proveedor con código automático (PROV-0001) y su operativa vacía. Pide purchasing.manage_suppliers en el grupo y un motivo.';
revoke execute on function purchasing.create_supplier(uuid, text, text, text) from public;
grant execute on function purchasing.create_supplier(uuid, text, text, text) to authenticated;

-- Texto de un jsonb: vacío → nulo; si la clave no viene, el valor de antes.
create function purchasing.text_or(p_obj jsonb, p_key text, p_old text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_obj ? p_key then nullif(btrim(p_obj ->> p_key), '') else p_old end
$$;
comment on function purchasing.text_or(jsonb, text, text) is 'Interna: el texto de la clave (vacío = nulo) o, si no viene, el de antes.';
revoke execute on function purchasing.text_or(jsonb, text, text) from public;

create function purchasing.days_from(p_value jsonb)
returns smallint[]
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return '{}';
  end if;
  if jsonb_typeof(p_value) <> 'array' then
    raise exception 'Los días van en una lista.' using errcode = '22023';
  end if;
  return array(select (e #>> '{}')::smallint from jsonb_array_elements(p_value) as e);
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'Los días van de lunes a domingo, sin repetir.' using errcode = '23514';
end
$$;
comment on function purchasing.days_from(jsonb) is 'Interna: una lista JSON de días (1 a 7) como arreglo.';
revoke execute on function purchasing.days_from(jsonb) from public;

-- Una cuenta en pocas palabras, para el aviso: medio, alias, los últimos 4 del CBU y el código.
create function purchasing.account_label(p_acc purchasing.supplier_payment_accounts)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_acc.id is null then null else concat_ws(' · ',
    case p_acc.method when 'cash' then 'Efectivo' when 'transfer' then 'Transferencia' when 'check' then 'Cheque'
      when 'echeq' then 'eCheq' when 'card' then 'Tarjeta' else 'Pago electrónico' end,
    'alias ' || p_acc.alias,
    'CBU …' || right(p_acc.cbu, 4),
    'código ' || p_acc.electronic_code,
    p_acc.bank,
    case when not p_acc.is_active then 'no se usa' end) end
$$;
comment on function purchasing.account_label(purchasing.supplier_payment_accounts) is
  'Interna: una cuenta de pago en una línea (medio, alias, últimos 4 del CBU, código, banco).';
revoke execute on function purchasing.account_label(purchasing.supplier_payment_accounts) from public;

-- Aviso de un cambio en las cuentas de pago (decisión de Joaco, 2026-11-15): a quien ve el pago para todo el grupo
-- (Controller y Dirección), menos a quien lo hizo, con lo de antes y lo de ahora. Es el control del fraude de cambio de
-- cuenta hasta que los pagos pidan aprobación (Prompt 6).
create function purchasing.notify_account_change(p_supplier catalog.suppliers, p_notes text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  select u.user_id, p_supplier.group_id, 'supplier_account_changed',
         left(format('Cambiaron las cuentas de pago de «%s»', coalesce(p_supplier.trade_name, p_supplier.name)), 200),
         left(format('%s. Lo hizo %s. Revisalo antes de pagar.', array_to_string(p_notes, '; '),
                     coalesce(core.display_name(core.current_actor_id()), 'alguien de Compras')), 500),
         format('/proveedores/%s', p_supplier.id)
    from (select distinct a.user_id from core.user_role_assignments a
           where a.group_id = p_supplier.group_id and a.deleted_at is null and a.scope_type = 'group'
             and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())) u
   where u.user_id is distinct from core.current_actor_id()
     and core.user_has_permission_for_scope(u.user_id, 'purchasing.view_payment_terms', 'group', p_supplier.group_id,
                                            null, null);
end
$$;
comment on function purchasing.notify_account_change(catalog.suppliers, text[]) is
  'Interna: avisa a quien ve el pago para todo el grupo (purchasing.view_payment_terms) que cambiaron las cuentas de un proveedor, con lo de antes y lo de ahora. No avisa a quien hizo el cambio.';
revoke execute on function purchasing.notify_account_change(catalog.suppliers, text[]) from public;

-- La ficha entera en una transacción, con motivo (como catalog.save_ingredient_sheet). p_changes trae solo lo que
-- cambió: supplier, terms, payment_terms, accounts, categories, customer_numbers.
create function purchasing.save_supplier_sheet(p_supplier_id uuid, p_expected_stamp timestamptz, p_changes jsonb,
                                               p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s          catalog.suppliers;
  v_c          jsonb;
  v_item       jsonb;
  v_terms      purchasing.supplier_terms;
  v_pay        purchasing.supplier_payment_terms;
  v_ids        uuid[];
  v_id         uuid;
  v_acc        purchasing.supplier_payment_accounts;
  v_new        purchasing.supplier_payment_accounts;
  v_notes      text[] := '{}';
  v_constraint text;
  v_message    text;
begin
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null or not core.has_permission_in_group('purchasing.manage_suppliers', v_s.group_id) then
    return core.deny('purchasing.save_supplier_sheet', 'No tenés permiso para editar este proveedor.', null,
                     jsonb_build_object('supplier_id', p_supplier_id), v_s.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, array['supplier', 'terms', 'payment_terms', 'accounts', 'categories',
                                          'customer_numbers']);
  if p_changes = '{}'::jsonb then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  -- Dos guardados de la misma ficha van de a uno; el segundo ve que el primero cambió algo.
  perform 1 from catalog.suppliers where id = p_supplier_id for update;
  if p_expected_stamp is null
     or purchasing.supplier_sheet_stamp_internal(p_supplier_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió este proveedor mientras lo editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');

  -- Datos del proveedor.
  v_c := p_changes -> 'supplier';
  if v_c is not null then
    perform org.check_keys(v_c, array['name', 'trade_name', 'tax_id', 'vat_condition', 'address', 'city', 'phone',
                                      'whatsapp', 'email', 'sales_contact', 'admin_contact', 'notes']);
    if v_c ? 'name' and nullif(btrim(v_c ->> 'name'), '') is null then
      raise exception 'La razón social no puede quedar vacía.' using errcode = '23514';
    end if;
    update catalog.suppliers
       set name          = coalesce(purchasing.text_or(v_c, 'name', name), name),
           trade_name    = purchasing.text_or(v_c, 'trade_name', trade_name),
           tax_id        = case when v_c ? 'tax_id' then core.normalize_cuit(v_c ->> 'tax_id') else tax_id end,
           vat_condition = case when v_c ? 'vat_condition'
                                then nullif(v_c ->> 'vat_condition', '')::org.vat_condition else vat_condition end,
           address       = purchasing.text_or(v_c, 'address', address),
           city          = purchasing.text_or(v_c, 'city', city),
           phone         = purchasing.text_or(v_c, 'phone', phone),
           whatsapp      = purchasing.text_or(v_c, 'whatsapp', whatsapp),
           email         = lower(purchasing.text_or(v_c, 'email', email)),
           sales_contact = purchasing.text_or(v_c, 'sales_contact', sales_contact),
           admin_contact = purchasing.text_or(v_c, 'admin_contact', admin_contact),
           notes         = purchasing.text_or(v_c, 'notes', notes)
     where id = p_supplier_id;
  end if;

  -- Operativa.
  v_c := p_changes -> 'terms';
  if v_c is not null then
    perform org.check_keys(v_c, array['order_days', 'delivery_days', 'receiving_from', 'receiving_to', 'po_channel',
                                      'po_channel_target', 'billing_modes', 'price_list_frequency',
                                      'requires_po_approval']);
    select * into v_terms from purchasing.supplier_terms where supplier_id = p_supplier_id and deleted_at is null;
    if v_terms.id is null then
      insert into purchasing.supplier_terms (group_id, supplier_id) values (v_s.group_id, p_supplier_id)
      returning * into v_terms;
    end if;
    if v_c ? 'billing_modes' and jsonb_typeof(v_c -> 'billing_modes') <> 'array' then
      raise exception 'Las formas de facturar van en una lista.' using errcode = '22023';
    end if;
    update purchasing.supplier_terms
       set order_days           = case when v_c ? 'order_days' then purchasing.days_from(v_c -> 'order_days')
                                       else order_days end,
           delivery_days        = case when v_c ? 'delivery_days' then purchasing.days_from(v_c -> 'delivery_days')
                                       else delivery_days end,
           receiving_from       = case when v_c ? 'receiving_from' then nullif(v_c ->> 'receiving_from', '')::time
                                       else receiving_from end,
           receiving_to         = case when v_c ? 'receiving_to' then nullif(v_c ->> 'receiving_to', '')::time
                                       else receiving_to end,
           po_channel           = case when v_c ? 'po_channel'
                                       then nullif(v_c ->> 'po_channel', '')::purchasing.channel else po_channel end,
           po_channel_target    = purchasing.text_or(v_c, 'po_channel_target', po_channel_target),
           billing_modes        = case when v_c ? 'billing_modes'
                                       then array(select e::purchasing.billing_mode
                                                    from jsonb_array_elements_text(v_c -> 'billing_modes') as e)
                                       else billing_modes end,
           price_list_frequency = case when v_c ? 'price_list_frequency'
                                       then nullif(v_c ->> 'price_list_frequency', '')::purchasing.list_frequency
                                       else price_list_frequency end,
           requires_po_approval = case when v_c ? 'requires_po_approval'
                                       then (v_c ->> 'requires_po_approval')::boolean else requires_po_approval end
     where id = v_terms.id;
  end if;

  -- Condición de pago.
  v_c := p_changes -> 'payment_terms';
  if v_c is not null then
    perform org.check_keys(v_c, array['payment_terms', 'payment_days', 'minimum_order_amount']);
    select * into v_pay from purchasing.supplier_payment_terms where supplier_id = p_supplier_id and deleted_at is null;
    if v_pay.id is null then
      if nullif(v_c ->> 'payment_terms', '') is null then
        raise exception 'Elegí la condición de pago.' using errcode = '23514';
      end if;
      insert into purchasing.supplier_payment_terms (group_id, supplier_id, payment_terms, payment_days,
                                                     minimum_order_amount)
      values (v_s.group_id, p_supplier_id, (v_c ->> 'payment_terms')::purchasing.payment_terms,
              coalesce(nullif(v_c ->> 'payment_days', '')::smallint, 0),
              nullif(v_c ->> 'minimum_order_amount', '')::numeric);
    else
      update purchasing.supplier_payment_terms
         set payment_terms        = coalesce(nullif(v_c ->> 'payment_terms', '')::purchasing.payment_terms, payment_terms),
             payment_days         = case when v_c ? 'payment_days'
                                         then coalesce(nullif(v_c ->> 'payment_days', '')::smallint, 0)
                                         else payment_days end,
             minimum_order_amount = case when v_c ? 'minimum_order_amount'
                                         then nullif(v_c ->> 'minimum_order_amount', '')::numeric
                                         else minimum_order_amount end
       where id = v_pay.id;
    end if;
  end if;

  -- Cuentas: cada una con id (cambia o se quita con remove) o sin id (nueva).
  v_c := p_changes -> 'accounts';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 20 then
      raise exception 'Las cuentas van en una lista (hasta 20).' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(v_c) loop
      perform org.check_keys(v_item, array['id', 'remove', 'method', 'cbu', 'alias', 'bank', 'holder_name',
                                           'holder_tax_id', 'electronic_code', 'is_active']);
      if v_item ? 'id' then
        v_id := (v_item ->> 'id')::uuid;
        perform 1 from purchasing.supplier_payment_accounts
         where id = v_id and supplier_id = p_supplier_id and deleted_at is null;
        if not found then
          raise exception 'Esa cuenta no es de este proveedor.' using errcode = '22023';
        end if;
        select * into v_acc from purchasing.supplier_payment_accounts where id = v_id;
        if coalesce((v_item ->> 'remove')::boolean, false) then
          update purchasing.supplier_payment_accounts set deleted_at = now() where id = v_id;
          v_notes := v_notes || ('Se quitó: ' || purchasing.account_label(v_acc));
        else
          update purchasing.supplier_payment_accounts
             set method          = coalesce(nullif(v_item ->> 'method', '')::purchasing.payment_method, method),
                 cbu             = case when v_item ? 'cbu' then core.normalize_cuit(v_item ->> 'cbu') else cbu end,
                 alias           = purchasing.text_or(v_item, 'alias', alias),
                 bank            = purchasing.text_or(v_item, 'bank', bank),
                 holder_name     = purchasing.text_or(v_item, 'holder_name', holder_name),
                 holder_tax_id   = case when v_item ? 'holder_tax_id'
                                        then core.normalize_cuit(v_item ->> 'holder_tax_id') else holder_tax_id end,
                 electronic_code = purchasing.text_or(v_item, 'electronic_code', electronic_code),
                 is_active       = coalesce((v_item ->> 'is_active')::boolean, is_active)
           where id = v_id
          returning * into v_new;
          if purchasing.account_label(v_new) is distinct from purchasing.account_label(v_acc)
             or v_new.holder_tax_id is distinct from v_acc.holder_tax_id then
            v_notes := v_notes || ('Cambió: ' || purchasing.account_label(v_acc) || ' → ' || purchasing.account_label(v_new));
          end if;
        end if;
      else
        if nullif(v_item ->> 'method', '') is null then
          raise exception 'Elegí el medio de pago de la cuenta.' using errcode = '23514';
        end if;
        insert into purchasing.supplier_payment_accounts (group_id, supplier_id, method, cbu, alias, bank, holder_name,
                                                          holder_tax_id, electronic_code, is_active)
        values (v_s.group_id, p_supplier_id, (v_item ->> 'method')::purchasing.payment_method,
                core.normalize_cuit(v_item ->> 'cbu'), nullif(btrim(v_item ->> 'alias'), ''),
                nullif(btrim(v_item ->> 'bank'), ''), nullif(btrim(v_item ->> 'holder_name'), ''),
                core.normalize_cuit(v_item ->> 'holder_tax_id'), nullif(btrim(v_item ->> 'electronic_code'), ''),
                coalesce((v_item ->> 'is_active')::boolean, true))
        returning * into v_new;
        v_notes := v_notes || ('Nueva: ' || purchasing.account_label(v_new));
      end if;
    end loop;
    if cardinality(v_notes) > 0 then
      perform purchasing.notify_account_change(v_s, v_notes);
    end if;
  end if;

  -- Rubros: la lista entera de lo que provee.
  v_c := p_changes -> 'categories';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 60 then
      raise exception 'Los rubros van en una lista.' using errcode = '22023';
    end if;
    v_ids := array(select distinct (e #>> '{}')::uuid from jsonb_array_elements(v_c) as e);
    if exists (select 1 from unnest(v_ids) as x (id)
                where not exists (select 1 from catalog.ingredient_categories c
                                   where c.id = x.id and c.group_id = v_s.group_id and c.parent_id is null
                                     and c.deleted_at is null and c.is_active)) then
      raise exception 'Elegí rubros de compra vigentes (del primer nivel).' using errcode = '23514';
    end if;
    update purchasing.supplier_categories set deleted_at = now()
     where supplier_id = p_supplier_id and deleted_at is null and not (category_id = any (v_ids));
    insert into purchasing.supplier_categories (group_id, supplier_id, category_id)
    select v_s.group_id, p_supplier_id, x.id
      from unnest(v_ids) as x (id)
     where not exists (select 1 from purchasing.supplier_categories sc
                        where sc.supplier_id = p_supplier_id and sc.category_id = x.id and sc.deleted_at is null);
  end if;

  -- Números de cliente: la lista entera (local → número). Un local que no viene se quita.
  v_c := p_changes -> 'customer_numbers';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 200 then
      raise exception 'Los números de cliente van en una lista.' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(v_c) loop
      perform org.check_keys(v_item, array['restaurant_id', 'customer_number']);
      if not exists (select 1 from org.restaurants r
                      where r.id = (v_item ->> 'restaurant_id')::uuid and r.group_id = v_s.group_id
                        and r.deleted_at is null and r.status = 'active') then
        raise exception 'El número de cliente va en un local vigente del grupo.' using errcode = '23514';
      end if;
    end loop;
    update purchasing.supplier_customer_numbers n set deleted_at = now()
     where n.supplier_id = p_supplier_id and n.deleted_at is null
       and not exists (select 1 from jsonb_array_elements(v_c) as e
                        where (e ->> 'restaurant_id')::uuid = n.restaurant_id
                          and btrim(e ->> 'customer_number') = n.customer_number);
    insert into purchasing.supplier_customer_numbers (group_id, supplier_id, restaurant_id, customer_number)
    select v_s.group_id, p_supplier_id, (e ->> 'restaurant_id')::uuid, btrim(e ->> 'customer_number')
      from jsonb_array_elements(v_c) as e
     where not exists (select 1 from purchasing.supplier_customer_numbers n
                        where n.supplier_id = p_supplier_id and n.deleted_at is null
                          and n.restaurant_id = (e ->> 'restaurant_id')::uuid);
  end if;

  return jsonb_build_object('result', 'applied', 'stamp', purchasing.supplier_sheet_stamp_internal(p_supplier_id));
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
       or numeric_value_out_of_range then
    raise exception 'Hay un dato con un valor que no corresponde: revisá la ficha.' using errcode = '22023';
end
$$;
comment on function purchasing.save_supplier_sheet(uuid, timestamptz, jsonb, text) is
  'Guarda la ficha de un proveedor en una sola transacción, con motivo y control de cambios simultáneos (sello). Pide purchasing.manage_suppliers en el grupo.';
revoke execute on function purchasing.save_supplier_sheet(uuid, timestamptz, jsonb, text) from public;
grant execute on function purchasing.save_supplier_sheet(uuid, timestamptz, jsonb, text) to authenticated;

create function purchasing.set_supplier_active(p_id uuid, p_active boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s catalog.suppliers;
  v_constraint text;
  v_message    text;
begin
  select * into v_s from catalog.suppliers where id = p_id and deleted_at is null;
  if v_s.id is null or not core.has_permission_in_group('purchasing.manage_suppliers', v_s.group_id) then
    return core.deny('purchasing.set_supplier_active', 'No tenés permiso para cambiar este proveedor.', null,
                     jsonb_build_object('supplier_id', p_id), v_s.group_id);
  end if;
  if p_active is null then
    raise exception 'Decí si el proveedor queda activo o no.' using errcode = '22023';
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.suppliers set is_active = p_active where id = p_id;
  return jsonb_build_object('result', 'applied');
exception when check_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.set_supplier_active(uuid, boolean, text) is
  'Desactiva o reactiva un proveedor, con motivo. Desactivar conserva todo: la ficha, la historia y sus productos.';
revoke execute on function purchasing.set_supplier_active(uuid, boolean, text) from public;
grant execute on function purchasing.set_supplier_active(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Un solo camino de escritura: las funciones del catálogo piden el permiso de proveedores
-- ---------------------------------------------------------------------------
create or replace function catalog.create_supplier(p_group_id uuid, p_code text, p_name text, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('purchasing.manage_suppliers', p_group_id),
                      'crear proveedores en este grupo');
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['tax_id', 'is_internal', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.suppliers (group_id, code, name, tax_id, is_internal, notes)
  values (p_group_id, upper(btrim(p_code)), btrim(p_name), core.normalize_cuit(p_details ->> 'tax_id'),
          coalesce((p_details ->> 'is_internal')::boolean, false), nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  insert into purchasing.supplier_terms (group_id, supplier_id) values (p_group_id, v_id);
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_supplier(uuid, text, text, jsonb, text) is
  'Crea un proveedor con un código elegido. Pide purchasing.manage_suppliers en el grupo (ADR-0050) y un motivo. p_details: tax_id, is_internal y notes. La pantalla usa purchasing.create_supplier (código automático).';

create or replace function catalog.update_supplier(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
  v_group uuid;
begin
  select group_id into v_group from catalog.suppliers where id = p_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('purchasing.manage_suppliers', v_group),
                      'editar este proveedor');
  perform org.check_keys(p_changes, array['name', 'tax_id', 'is_internal', 'is_active', 'notes']);
  perform core.set_change_context(p_reason, 'manual');
  update catalog.suppliers
     set name        = coalesce(btrim(p_changes ->> 'name'), name),
         tax_id      = case when p_changes ? 'tax_id' then core.normalize_cuit(p_changes ->> 'tax_id') else tax_id end,
         is_internal = coalesce((p_changes ->> 'is_internal')::boolean, is_internal),
         is_active   = coalesce((p_changes ->> 'is_active')::boolean, is_active),
         notes       = case when p_changes ? 'notes' then nullif(btrim(p_changes ->> 'notes'), '') else notes end
   where id = p_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.update_supplier(uuid, jsonb, text) is
  'Edita un proveedor (nombre, CUIT, si es interno, si está activo, observaciones). El código no cambia. Pide purchasing.manage_suppliers (ADR-0050) y un motivo.';

-- ---------------------------------------------------------------------------
-- 9. Listado (tipo C): filtros, orden y página en una sola consulta
-- ---------------------------------------------------------------------------
-- security invoker: cada fila y cada dato sale de lo que la RLS deja ver a la sesión. La condición de pago viene vacía
-- para quien no la ve (el cocinero), sin que esta función decida nada.
create function purchasing.supplier_list(p_search text default null, p_active boolean default true,
                                         p_category_id uuid default null, p_channel purchasing.channel default null,
                                         p_sort text default 'name', p_desc boolean default false,
                                         p_limit integer default 15, p_offset integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select s.id, s.code, s.name, s.trade_name, s.tax_id, s.is_active, t.delivery_days, t.po_channel,
           t.requires_po_approval, pt.payment_terms, pt.payment_days,
           (select coalesce(jsonb_agg(c.name order by c.name), '[]'::jsonb)
              from purchasing.supplier_categories sc
              join catalog.ingredient_categories c on c.id = sc.category_id
             where sc.supplier_id = s.id and sc.deleted_at is null) as categories
      from catalog.suppliers s
      left join purchasing.supplier_terms t on t.supplier_id = s.id and t.deleted_at is null
      left join purchasing.supplier_payment_terms pt on pt.supplier_id = s.id and pt.deleted_at is null
     where s.deleted_at is null
       and (p_active is null or s.is_active = p_active)
       and (p_channel is null or t.po_channel = p_channel)
       and (p_category_id is null
            or exists (select 1 from purchasing.supplier_categories sc
                        where sc.supplier_id = s.id and sc.category_id = p_category_id and sc.deleted_at is null))
       and (nullif(btrim(p_search), '') is null
            or strpos(lower(s.name), lower(btrim(p_search))) > 0
            or strpos(lower(coalesce(s.trade_name, '')), lower(btrim(p_search))) > 0
            or strpos(lower(s.code), lower(btrim(p_search))) > 0
            or (regexp_replace(btrim(p_search), '[^0-9]', '', 'g') <> ''
                and strpos(coalesce(s.tax_id, ''), regexp_replace(btrim(p_search), '[^0-9]', '', 'g')) > 0))
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'rows', coalesce((select jsonb_agg(to_jsonb(p) - 'rn' order by p.rn)
                        from (select b.*,
                                     row_number() over (
                                       order by case when not p_desc then
                                                       case when p_sort = 'code' then b.code
                                                            else lower(coalesce(b.trade_name, b.name)) end end asc,
                                                case when p_desc then
                                                       case when p_sort = 'code' then b.code
                                                            else lower(coalesce(b.trade_name, b.name)) end end desc,
                                                b.id) as rn
                                from base b) as p
                       where p.rn > greatest(coalesce(p_offset, 0), 0)
                         and p.rn <= greatest(coalesce(p_offset, 0), 0) + least(greatest(coalesce(p_limit, 15), 1), 100)),
                     '[]'::jsonb))
$$;
comment on function purchasing.supplier_list(text, boolean, uuid, purchasing.channel, text, boolean, integer, integer) is
  'Listado de proveedores con filtros (búsqueda por nombre, fantasía, código o CUIT; activos o inactivos; rubro; canal), orden y página. Corre con los permisos de la sesión: la condición de pago viene vacía para quien no la ve.';
revoke execute on function purchasing.supplier_list(text, boolean, uuid, purchasing.channel, text, boolean, integer, integer) from public;
grant execute on function purchasing.supplier_list(text, boolean, uuid, purchasing.channel, text, boolean, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. El historial oculta el pago a quien no lo ve (decisión de Joaco, 2026-11-15; revisiones de base y de seguridad)
-- ---------------------------------------------------------------------------
-- Las tablas de pago tienen su propia RLS, pero el historial guarda sus valores: sin esto, quien lee el historial
-- (el Auditor, un Director de Marca) veía CBU, alias y CUIT del titular. Como los costos (core.hide_costs).
create function core.hide_payment(p_schema text, p_table text, p_group_id uuid, p_value jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_value is null or p_schema is distinct from 'purchasing'
     or p_table not in ('supplier_payment_terms', 'supplier_payment_accounts')
     or (p_group_id is not null and purchasing.can_see_payment(p_group_id)) then
    return p_value;
  end if;
  return (select coalesce(jsonb_object_agg(k, case when k in ('id', 'group_id', 'supplier_id', 'created_at', 'created_by',
                                                              'updated_at', 'updated_by', 'deleted_at', 'deleted_by')
                                                   then v else to_jsonb('[oculto]'::text) end), '{}'::jsonb)
            from jsonb_each(p_value) as e (k, v));
end
$$;
comment on function core.hide_payment(text, text, uuid, jsonb) is
  'Interna. En el historial, reemplaza por "[oculto]" los valores de la condición de pago y las cuentas de los proveedores a quien no ve el pago en ese grupo (purchasing.can_see_payment).';
revoke execute on function core.hide_payment(text, text, uuid, jsonb) from public;

-- Igual que la versión de 20261028120000, con el pago oculto.
create or replace function core.audit_history(
  p_limit         integer default 50,
  p_before        bigint default null,
  p_record_id     uuid default null,
  p_from          timestamptz default null,
  p_to            timestamptz default null,
  p_actor_id      uuid default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null,
  p_critical_only boolean default false
)
returns table (sequence_number bigint, occurred_at timestamptz, actor_name text, actor_role_code text, action text,
               module text, table_schema text, table_name text, record_id uuid, changed_fields text[],
               old_values jsonb, new_values jsonb, reason text, source text, place_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit  int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_bounds record;
  v_rids   uuid[];
  v_bids   uuid[];
  v_gids   uuid[];
  v_cost_rids uuid[];
  v_cost_bids uuid[];
  v_cost_gids uuid[];
begin
  if not core.current_session_ok() then
    return;
  end if;
  if p_module is not null and (length(p_module) > 60 or p_module !~ '^[a-z_]+$') then
    raise exception 'Módulo inválido.' using errcode = '22023';
  end if;
  v_bounds := core.audit_sequence_bounds(p_from, p_to);
  -- El alcance pedido, dentro de lo que la sesión puede ver: un local, una marca (sus locales y la
  -- marca) o todo lo visible.
  v_rids := array(select r.id from org.restaurants r
                   where r.id in (select core.permitted_restaurant_ids('audit.view'))
                     and (p_restaurant_id is null or r.id = p_restaurant_id)
                     and (p_brand_id is null or r.brand_id = p_brand_id));
  v_bids := case when p_restaurant_id is null then
              array(select b from core.permitted_brand_ids('audit.view') b where p_brand_id is null or b = p_brand_id)
            else '{}' end;
  v_gids := case when p_restaurant_id is null and p_brand_id is null then array(select core.permitted_group_ids('audit.view'))
            else '{}' end;

  v_cost_rids := array(select core.permitted_restaurant_ids('recipes.view_costs'));
  v_cost_bids := array(select core.permitted_brand_ids('recipes.view_costs'));
  v_cost_gids := array(select core.permitted_group_ids('recipes.view_costs'));

  return query
  select e.sequence_number, e.occurred_at,
         coalesce(core.display_name(coalesce(e.actor_user_id, e.actor_service_account_id)),
                  case when e.source is not null then 'Sistema (' || e.source::text || ')' else 'Sistema' end),
         e.actor_role_code, e.action::text, e.module, e.table_schema, e.table_name, e.record_id, e.changed_fields,
         core.hide_payment(e.table_schema, e.table_name, e.scope_group_id,
           case when (e.scope_restaurant_id is not null and e.scope_restaurant_id = any (v_cost_rids))
                  or (e.scope_restaurant_id is null and e.scope_brand_id is not null and e.scope_brand_id = any (v_cost_bids))
                  or (e.scope_brand_id is null and e.scope_group_id is not null and e.scope_group_id = any (v_cost_gids))
                then e.old_values else core.hide_costs(e.old_values) end),
         core.hide_payment(e.table_schema, e.table_name, e.scope_group_id,
           case when (e.scope_restaurant_id is not null and e.scope_restaurant_id = any (v_cost_rids))
                  or (e.scope_restaurant_id is null and e.scope_brand_id is not null and e.scope_brand_id = any (v_cost_bids))
                  or (e.scope_brand_id is null and e.scope_group_id is not null and e.scope_group_id = any (v_cost_gids))
                then e.new_values else core.hide_costs(e.new_values) end),
         e.reason, e.source::text,
         coalesce((select r.name from org.restaurants r where r.id = e.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = e.scope_brand_id),
                  (select g.name from org.groups g where g.id = e.scope_group_id))
    from core.audit_scope_events(v_rids, v_bids, v_gids, v_limit, least(coalesce(p_before, 9223372036854775807), v_bounds.before_seq),
                                 v_bounds.after_seq, p_record_id, p_from, p_to, p_actor_id, p_module,
                                 case when p_critical_only then array['user_role_assignments', 'role_permissions', 'user_profiles',
                                   'roles', 'permissions', 'approval_decisions', 'approval_workflows'] end) e
   order by e.sequence_number desc;
end
$$;
comment on function core.audit_history(integer, bigint, uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, boolean) is
  'Historial de cambios que la sesión puede ver (audit.view por alcance), del más nuevo al más viejo, con quién, cuándo, qué y por qué. Lee por índice cada alcance visible. Oculta costos y precios sin recipes.view_costs (ADR-0020) y el pago de los proveedores sin purchasing.can_see_payment (ADR-0050).';

-- Igual que la versión de 20261021200000, con el pago oculto.
create or replace function core.audit_export(
  p_from          timestamptz default null,
  p_to            timestamptz default null,
  p_actor_id      uuid default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null,
  p_record_id     uuid default null,
  p_limit         integer default 2000
)
returns table (occurred_at timestamptz, actor_name text, actor_role_code text, action text, module text, table_name text,
               record_id uuid, field text, old_value text, new_value text, reason text, source text, place_name text,
               operation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit  int := least(greatest(coalesce(p_limit, 2000), 1), 5000);
  v_bounds record;
  v_rids   uuid[];
  v_bids   uuid[];
  v_gids   uuid[];
  v_count  int;
begin
  if not core.current_session_ok() then
    return;
  end if;
  if p_module is not null and (length(p_module) > 60 or p_module !~ '^[a-z_]+$') then
    raise exception 'Módulo inválido.' using errcode = '22023';
  end if;
  -- Se exporta solo donde la sesión puede exportar (audit.export por alcance).
  v_rids := array(select r.id from org.restaurants r
                   where r.id in (select core.permitted_restaurant_ids('audit.export'))
                     and (p_restaurant_id is null or r.id = p_restaurant_id)
                     and (p_brand_id is null or r.brand_id = p_brand_id));
  v_bids := case when p_restaurant_id is null then
              array(select b from core.permitted_brand_ids('audit.export') b where p_brand_id is null or b = p_brand_id)
            else '{}' end;
  v_gids := case when p_restaurant_id is null and p_brand_id is null then array(select core.permitted_group_ids('audit.export'))
            else '{}' end;
  if cardinality(v_rids) + cardinality(v_bids) + cardinality(v_gids) = 0 then
    perform core.deny('core.audit_export', 'No tenés permiso para exportar el historial de ese lugar.', null,
                      jsonb_strip_nulls(jsonb_build_object('brand_id', p_brand_id, 'restaurant_id', p_restaurant_id)));
    return;
  end if;
  v_bounds := core.audit_sequence_bounds(p_from, p_to);

  -- Primero los eventos (hasta p_limit, leídos por índice); después, un campo por fila.
  return query
  with events as (
    select * from core.audit_scope_events(v_rids, v_bids, v_gids, v_limit, v_bounds.before_seq, v_bounds.after_seq,
                                          p_record_id, p_from, p_to, p_actor_id, p_module, null)
  ),
  fields as (
    select e.*, f.field, core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) as costs
      from events e
      cross join lateral unnest(case
          when e.action in ('insert', 'approve', 'reject') then array(select jsonb_object_keys(e.new_values))
          when e.action = 'delete' then array(select jsonb_object_keys(e.old_values))
          else e.changed_fields end) as f (field)
     where f.field not in ('id', 'created_at', 'created_by', 'updated_at', 'updated_by')
  )
  select f.occurred_at,
         coalesce(core.display_name(coalesce(f.actor_user_id, f.actor_service_account_id)),
                  case when f.source is not null then 'Sistema (' || f.source::text || ')' else 'Sistema' end),
         f.actor_role_code, f.action::text, f.module, f.table_schema || '.' || f.table_name, f.record_id, f.field,
         -- Los costos salen ocultos para quien no los puede ver, también adentro de los valores
         -- compuestos (revisión de base M4 y de seguridad M-B), igual que en la pantalla.
         core.hide_payment(f.table_schema, f.table_name, f.scope_group_id,
           case when f.costs then f.old_values else core.hide_costs(f.old_values) end) ->> f.field,
         core.hide_payment(f.table_schema, f.table_name, f.scope_group_id,
           case when f.costs then f.new_values else core.hide_costs(f.new_values) end) ->> f.field,
         f.reason, f.source::text,
         coalesce((select r.name from org.restaurants r where r.id = f.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = f.scope_brand_id),
                  (select g.name from org.groups g where g.id = f.scope_group_id)),
         f.operation_id
    from fields f
   order by f.sequence_number desc, f.field;

  get diagnostics v_count = row_count;
  -- Toda exportación queda en el registro de seguridad: quién, cuándo, con qué filtros y cuántas filas.
  perform audit.log_security_event('audit_exported', 'core.audit_export', 'Exportación del historial',
    core.current_actor_id(), null,
    jsonb_strip_nulls(jsonb_build_object('rows', v_count, 'from', p_from, 'to', p_to, 'actor_id', p_actor_id,
                                         'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id, 'module', p_module,
                                         'record_id', p_record_id)),
    core.user_group(core.current_actor_id()), p_brand_id, p_restaurant_id);
end
$$;
comment on function core.audit_export(timestamptz, timestamptz, uuid, uuid, uuid, text, uuid, integer) is
  'Exporta el historial, un campo cambiado por fila, con los mismos filtros que la pantalla: hasta 5.000 eventos por pedido, leídos por índice. Pide audit.export en el alcance; oculta los costos a quien no los puede ver y el pago de los proveedores a quien no lo ve (ADR-0050); cada exportación (o el intento sin permiso) queda en el registro de seguridad.';
