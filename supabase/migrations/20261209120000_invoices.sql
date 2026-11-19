-- Fase 3, Prompt 5 (ADR-0058): facturas de compra, el control de 3 vías (OC ↔ recepción ↔ factura) y las notas de
-- crédito, débito y descuento. Esta migración crea los permisos, los tipos y las tablas; las funciones están en
-- 20261209140000_invoice_functions.sql y el cambio en costing.price_records en 20261209130000_invoice_costs.sql.
--
-- - La factura la carga Compras (purchasing.manage_invoices) desde una o más OC recibidas del mismo proveedor y local,
--   o sin OC (un flete, un servicio). Se escribe solo con funciones: nadie inserta ni cambia filas directo.
-- - Conforme (approved), liberada (released) o pagada (paid), no cambia ni sus datos fiscales ni sus líneas: se
--   corrige con una nota de crédito, débito o descuento. Cancelar una factura cargada por error es un estado, con motivo.
-- - El CUIT del emisor tiene que ser el del proveedor: si no, no se guarda. Un emisor de ejemplo (99-99999999-9) o una
--   clase fiscal sin autorización (CAE, CAI o CAEA) tampoco.
-- - Dinero en numeric(18,4) y con nombres _amount o _price: core.hide_costs los esconde en el historial a quien no ve
--   costos. El cocinero y el chef no ven facturas.

-- ---------------------------------------------------------------------------
-- 1. Permisos
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de facturas (Fase 3, ADR-0058)', 'maintenance');
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('purchasing.view_invoices', 'purchasing', 'view_invoices', 'Ver facturas', 110,
     'Ver las facturas de compra de los locales que ve, con sus líneas, sus controles, sus notas de crédito y débito y sus fotos.',
     false),
    ('purchasing.manage_invoices', 'purchasing', 'manage_invoices', 'Cargar facturas', 120,
     'Cargar una factura de compra con su foto, corregirla mientras no esté conforme, controlarla contra la OC y la lista, sumarle notas de crédito o débito y cancelarla si se cargó por error.',
     false),
    ('purchasing.approve_invoices', 'purchasing', 'approve_invoices', 'Dar facturas por conforme', 130,
     'Dar por conforme a mano una factura que no cerró sola. Nunca una que cargó la misma persona. Conforme, su precio pasa a ser el costo de la materia prima.',
     true);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values
      ('general_management', 'purchasing.view_invoices'),
      ('restaurant_manager', 'purchasing.view_invoices'),
      ('controller', 'purchasing.view_invoices'), ('controller', 'purchasing.approve_invoices'),
      ('purchasing', 'purchasing.view_invoices'), ('purchasing', 'purchasing.manage_invoices'),
      ('purchasing', 'purchasing.approve_invoices'),
      ('auditor', 'purchasing.view_invoices'),
      -- Regla G2: quien administra personas tiene los permisos de los roles que administra. El Director de Marca
      -- administra al Gerente; el superadmin, a Compras y al Gerente.
      ('brand_director', 'purchasing.view_invoices'),
      ('superadmin', 'purchasing.view_invoices'), ('superadmin', 'purchasing.manage_invoices'),
      ('superadmin', 'purchasing.approve_invoices')
    ) as v (role_code, permission_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = v.permission_code and p.deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Tipos
-- ---------------------------------------------------------------------------
create type purchasing.invoice_class as enum ('invoice_a', 'invoice_b', 'invoice_c', 'invoice_remito_a', 'non_fiscal',
                                              'handwritten_note');
comment on type purchasing.invoice_class is
  'Clase de comprobante: invoice_a, invoice_b, invoice_c (facturas A, B y C), invoice_remito_a (factura-remito A, un solo papel que es las dos cosas), non_fiscal (comprobante X, no fiscal) y handwritten_note (nota de pedido escrita a mano). Los remitos R y el remito electrónico se cargan en la recepción, no acá.';
create type purchasing.invoice_status as enum ('loaded', 'in_control', 'observed', 'approved', 'released', 'paid',
                                               'cancelled');
comment on type purchasing.invoice_status is
  'Estado de una factura: loaded (cargada, se puede corregir), in_control (reservado), observed (algún control no pasó), approved (conforme), released (liberada a pago), paid (pagada, Prompt 6) y cancelled (cancelada: se cargó por error).';
create type purchasing.authorization_kind as enum ('cae', 'cai', 'caea');
comment on type purchasing.authorization_kind is
  'Autorización fiscal del comprobante: cae (electrónico), cai (talonario preimpreso) o caea (anticipado).';
create type purchasing.due_on_source as enum ('printed', 'terms');
comment on type purchasing.due_on_source is
  'De dónde sale el vencimiento de pago: printed (impreso en la factura) o terms (la condición de pago del proveedor). El vencimiento del CAE nunca es el de pago.';
create type purchasing.invoice_line_class as enum ('product', 'freight', 'service', 'rounding', 'deposit',
                                                   'free_of_charge');
comment on type purchasing.invoice_line_class is
  'Clase de línea de factura: product (mercadería), freight (flete o envío), service (servicio), rounding (redondeo), deposit (envase retornable) y free_of_charge (bonificada en 99 % o más: un regalo). Solo product cambia costos.';
create type purchasing.invoice_tax_kind as enum ('iibb', 'vat_perception', 'municipal', 'other');
comment on type purchasing.invoice_tax_kind is
  'Percepciones y otros tributos de una factura: iibb (ingresos brutos), vat_perception (percepción de IVA), municipal y other. Nunca suman al costo (decisión 4 de Soy).';
create type purchasing.invoice_check_kind as enum ('quantity', 'price', 'mapping', 'totals', 'legal_entity',
                                                   'order', 'notes');
comment on type purchasing.invoice_check_kind is
  'Qué controla una fila del control de 3 vías: quantity (facturado contra recibido), price (contra la lista vigente), mapping (la línea tiene producto de compra), totals (las líneas cierran con el pie), legal_entity (facturada a la razón social del local), order (tiene OC y recepción) y notes (las notas de crédito y débito cubren la diferencia).';
create type purchasing.note_kind as enum ('credit', 'debit', 'discount');
comment on type purchasing.note_kind is
  'Nota que corrige una factura: credit (nota de crédito), debit (nota de débito) o discount (descuento del proveedor).';

-- ---------------------------------------------------------------------------
-- 3. Configuración: tolerancia de peso
-- ---------------------------------------------------------------------------
alter table costing.price_settings
  add column invoice_weight_tolerance_pct numeric(5,2) not null default 0.5
    check (invoice_weight_tolerance_pct >= 0 and invoice_weight_tolerance_pct <= 10);
comment on column costing.price_settings.invoice_weight_tolerance_pct is
  'Diferencia que se acepta entre los kilos facturados y los recibidos en lo que va por peso, en %. Por defecto, 0,5 %.';

-- ---------------------------------------------------------------------------
-- 4. Facturas
-- ---------------------------------------------------------------------------
create table purchasing.invoices (
  id                        uuid primary key default gen_random_uuid(),
  group_id                  uuid not null references org.groups (id) on delete restrict,
  brand_id                  uuid not null,
  restaurant_id             uuid not null,
  supplier_id               uuid not null,
  legal_entity_id           uuid references org.legal_entities (id) on delete restrict,
  legal_entity_tax_id       text check (legal_entity_tax_id is null or legal_entity_tax_id ~ '^[0-9]{11}$'),
  invoice_class             purchasing.invoice_class not null,
  point_of_sale             integer check (point_of_sale is null or point_of_sale between 1 and 99999),
  number                    bigint not null check (number between 1 and 99999999),
  authorization_kind        purchasing.authorization_kind,
  authorization_code        text check (authorization_code is null or authorization_code ~ '^[0-9]{14}$'),
  authorization_expires_on  date,
  issuer_tax_id             text check (issuer_tax_id is null or issuer_tax_id ~ '^[0-9]{11}$'),
  receiver_tax_id           text check (receiver_tax_id is null or receiver_tax_id ~ '^[0-9]{11}$'),
  issued_on                 date not null check (issued_on >= date '2000-01-01'),
  due_on                    date not null,
  due_on_source             purchasing.due_on_source not null,
  net_amount                numeric(18,4) not null default 0 check (net_amount >= 0),
  exempt_amount             numeric(18,4) not null default 0 check (exempt_amount >= 0),
  vat_amount                numeric(18,4) not null default 0 check (vat_amount >= 0),
  internal_tax_amount       numeric(18,4) not null default 0 check (internal_tax_amount >= 0),
  perception_amount         numeric(18,4) not null default 0 check (perception_amount >= 0),
  discount_amount           numeric(18,4) not null default 0 check (discount_amount >= 0),
  rounding_amount           numeric(18,4) not null default 0 check (rounding_amount between -100 and 100),
  total_amount              numeric(18,4) not null default 0 check (total_amount >= 0),
  supplier_balance_amount   numeric(18,4),
  currency                  text not null default 'ARS' check (currency = 'ARS'),
  remito_refs               text check (remito_refs is null or length(btrim(remito_refs)) between 1 and 200),
  supplier_order_ref        text check (supplier_order_ref is null or length(btrim(supplier_order_ref)) between 1 and 60),
  status                    purchasing.invoice_status not null default 'loaded',
  observed_reason           text check (observed_reason is null or length(btrim(observed_reason)) between 1 and 500),
  loaded_by                 uuid not null references core.actors (id) on delete restrict,
  approved_by               uuid references core.actors (id) on delete restrict,
  approved_at               timestamptz,
  cancelled_reason          text check (cancelled_reason is null or length(btrim(cancelled_reason)) between 3 and 500),
  notes                     text check (notes is null or length(btrim(notes)) between 1 and 1000),
  created_at                timestamptz not null default now(),
  created_by                uuid references core.actors (id) on delete restrict,
  updated_at                timestamptz not null default now(),
  updated_by                uuid references core.actors (id) on delete restrict,
  deleted_at                timestamptz,
  deleted_by                uuid references core.actors (id) on delete restrict,
  constraint invoices_id_group_key unique (id, group_id),
  constraint invoices_restaurant_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint invoices_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint invoices_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  -- Las clases fiscales llevan punto de venta, autorización y CUIT del emisor; X y la nota a mano, no.
  constraint invoices_fiscal_check check (
    invoice_class in ('non_fiscal', 'handwritten_note')
    or (point_of_sale is not null and authorization_kind is not null and authorization_code is not null
        and issuer_tax_id is not null)),
  -- Sin factura fiscal no hay IVA.
  constraint invoices_non_fiscal_vat_check check (
    invoice_class not in ('non_fiscal', 'handwritten_note') or vat_amount = 0),
  -- Las partes suman el total (tolerancia 0,01).
  constraint invoices_totals_check check (
    abs(net_amount + exempt_amount + vat_amount + internal_tax_amount + perception_amount - discount_amount
        + rounding_amount - total_amount) <= 0.01),
  constraint invoices_approval_check check (
    (status in ('approved', 'released', 'paid')) = (approved_by is not null and approved_at is not null)),
  constraint invoices_cancel_check check ((status = 'cancelled') = (cancelled_reason is not null))
);
-- Única por proveedor, clase, punto de venta y número (una cancelada no cuenta: se puede volver a cargar bien).
create unique index invoices_number_key
  on purchasing.invoices (supplier_id, invoice_class, coalesce(point_of_sale, 0), number)
  where deleted_at is null and status <> 'cancelled';
create index invoices_restaurant_idx on purchasing.invoices (restaurant_id, status, issued_on desc)
  where deleted_at is null;
create index invoices_restaurant_group_idx on purchasing.invoices (restaurant_id, group_id);
create index invoices_restaurant_brand_idx on purchasing.invoices (restaurant_id, brand_id);
create index invoices_supplier_idx on purchasing.invoices (supplier_id, group_id, issued_on desc);
create index invoices_legal_entity_idx on purchasing.invoices (legal_entity_id) where legal_entity_id is not null;
create index invoices_due_idx on purchasing.invoices (group_id, due_on) where status = 'released' and deleted_at is null;
create index invoices_loaded_by_idx on purchasing.invoices (loaded_by);
create index invoices_approved_by_idx on purchasing.invoices (approved_by) where approved_by is not null;
create index invoices_group_idx on purchasing.invoices (group_id);
comment on table purchasing.invoices is
  'Facturas de compra (y comprobantes X o notas a mano), controladas contra la OC, la recepción y la lista de precios. Conforme, su precio pasa a ser el costo de cada materia prima (decisión 1 de Soy) y no cambia más: se corrige con notas de crédito o débito.';
comment on column purchasing.invoices.group_id is 'Grupo, el mismo que el del local y el del proveedor.';
comment on column purchasing.invoices.brand_id is 'Marca del local.';
comment on column purchasing.invoices.restaurant_id is 'Local que compró (el que recibió la mercadería).';
comment on column purchasing.invoices.supplier_id is 'Proveedor que factura.';
comment on column purchasing.invoices.legal_entity_id is
  'Razón social del local al cargar la factura (copia: la base guarda solo la actual del local).';
comment on column purchasing.invoices.legal_entity_tax_id is 'CUIT de esa razón social, al cargar la factura.';
comment on column purchasing.invoices.invoice_class is 'Clase de comprobante (A, B, C, factura-remito A, X o nota a mano).';
comment on column purchasing.invoices.point_of_sale is 'Punto de venta (de 1 a 99999). Obligatorio en las clases fiscales.';
comment on column purchasing.invoices.number is 'Número del comprobante (de 1 a 99999999).';
comment on column purchasing.invoices.authorization_kind is 'Tipo de autorización fiscal: CAE, CAI o CAEA.';
comment on column purchasing.invoices.authorization_code is 'Número de la autorización (14 dígitos).';
comment on column purchasing.invoices.authorization_expires_on is
  'Vencimiento de la autorización. Nunca se usa como vencimiento de pago.';
comment on column purchasing.invoices.issuer_tax_id is 'CUIT del emisor, sin guiones. Tiene que ser el del proveedor.';
comment on column purchasing.invoices.receiver_tax_id is
  'CUIT del receptor, sin guiones. Si no es el de la razón social del local, la factura queda observada.';
comment on column purchasing.invoices.issued_on is 'Fecha de la factura. Es la vigencia del costo que deja.';
comment on column purchasing.invoices.due_on is 'Vencimiento de pago.';
comment on column purchasing.invoices.due_on_source is 'Si el vencimiento es el impreso o el calculado con la condición del proveedor.';
comment on column purchasing.invoices.net_amount is 'Neto gravado.';
comment on column purchasing.invoices.exempt_amount is 'Importe exento o no gravado.';
comment on column purchasing.invoices.vat_amount is 'IVA (todas las alícuotas).';
comment on column purchasing.invoices.internal_tax_amount is 'Impuestos internos. No suman al costo (decisión 4 de Soy).';
comment on column purchasing.invoices.perception_amount is
  'Percepciones y otros tributos (el detalle está en invoice_taxes). No suman al costo (decisión 4 de Soy).';
comment on column purchasing.invoices.discount_amount is 'Bonificación general al pie.';
comment on column purchasing.invoices.rounding_amount is 'Ajuste por redondeo (puede ser negativo).';
comment on column purchasing.invoices.total_amount is 'Total. Las partes lo suman con 0,01 de tolerancia.';
comment on column purchasing.invoices.supplier_balance_amount is
  'Saldo de la cuenta corriente que informa el proveedor en el papel, si lo trae (para compararlo en el Prompt 6).';
comment on column purchasing.invoices.currency is 'Moneda. Solo ARS.';
comment on column purchasing.invoices.remito_refs is 'Números de remito que nombra la factura.';
comment on column purchasing.invoices.supplier_order_ref is 'Número de pedido del proveedor que nombra la factura.';
comment on column purchasing.invoices.status is 'Estado de la factura.';
comment on column purchasing.invoices.observed_reason is 'Qué falló en el último control, en simple.';
comment on column purchasing.invoices.loaded_by is 'Quién la cargó. Esa persona no puede darla por conforme a mano (decisión 2 de Soy).';
comment on column purchasing.invoices.approved_by is 'Quién la dio por conforme (o quien corrió el control, si pasó sola).';
comment on column purchasing.invoices.approved_at is 'Cuándo quedó conforme.';
comment on column purchasing.invoices.cancelled_reason is 'Por qué se canceló.';
comment on column purchasing.invoices.notes is 'Notas de Compras.';

create table purchasing.invoice_orders (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null references org.groups (id) on delete restrict,
  invoice_id         uuid not null,
  purchase_order_id  uuid not null,
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint invoice_orders_invoice_fkey foreign key (invoice_id, group_id)
    references purchasing.invoices (id, group_id) on delete restrict,
  constraint invoice_orders_order_fkey foreign key (purchase_order_id, group_id)
    references purchasing.purchase_orders (id, group_id) on delete restrict
);
create unique index invoice_orders_key on purchasing.invoice_orders (invoice_id, purchase_order_id)
  where deleted_at is null;
create index invoice_orders_order_idx on purchasing.invoice_orders (purchase_order_id, group_id);
create index invoice_orders_invoice_idx on purchasing.invoice_orders (invoice_id, group_id);
create index invoice_orders_group_idx on purchasing.invoice_orders (group_id);
comment on table purchasing.invoice_orders is
  'Qué órdenes de compra cubre cada factura (una o más, del mismo proveedor y local, ya recibidas).';
comment on column purchasing.invoice_orders.group_id is 'Grupo, el mismo que el de la factura.';
comment on column purchasing.invoice_orders.invoice_id is 'Factura.';
comment on column purchasing.invoice_orders.purchase_order_id is 'Orden de compra que cubre.';

create table purchasing.invoice_lines (
  id                      uuid primary key default gen_random_uuid(),
  group_id                uuid not null references org.groups (id) on delete restrict,
  invoice_id              uuid not null,
  line_order              integer not null check (line_order between 1 and 600),
  line_class              purchasing.invoice_line_class not null default 'product',
  purchase_product_id     uuid,
  unmapped_article_id     uuid,
  purchase_order_line_id  uuid references purchasing.purchase_order_lines (id) on delete restrict,
  raw_name                text not null check (length(btrim(raw_name)) between 1 and 200),
  supplier_sku            text check (supplier_sku is null or length(btrim(supplier_sku)) between 1 and 60),
  units                   numeric(18,6) check (units is null or units > 0),
  billed_quantity         numeric(18,6) not null check (billed_quantity > 0),
  list_price              numeric(18,4) check (list_price is null or list_price >= 0),
  bonus1_pct              numeric(5,2) not null default 0 check (bonus1_pct >= 0 and bonus1_pct <= 100),
  bonus2_pct              numeric(5,2) not null default 0 check (bonus2_pct >= 0 and bonus2_pct <= 100),
  bonus_per_unit_amount   numeric(18,4) not null default 0 check (bonus_per_unit_amount >= 0),
  unit_price              numeric(18,4) not null check (unit_price >= 0),
  vat_rate                numeric(5,2) check (vat_rate is null or vat_rate in (0, 2.5, 5, 10.5, 21, 27)),
  is_exempt               boolean not null default false,
  internal_tax_amount     numeric(18,4) not null default 0 check (internal_tax_amount >= 0),
  line_amount             numeric(18,4) not null check (line_amount >= 0),
  created_at              timestamptz not null default now(),
  created_by              uuid references core.actors (id) on delete restrict,
  updated_at              timestamptz not null default now(),
  updated_by              uuid references core.actors (id) on delete restrict,
  deleted_at              timestamptz,
  deleted_by              uuid references core.actors (id) on delete restrict,
  constraint invoice_lines_invoice_fkey foreign key (invoice_id, group_id)
    references purchasing.invoices (id, group_id) on delete restrict,
  constraint invoice_lines_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict,
  constraint invoice_lines_unmapped_fkey foreign key (unmapped_article_id, group_id)
    references purchasing.unmapped_articles (id, group_id) on delete restrict,
  -- Solo la mercadería (y su regalo) lleva producto de compra o artículo sin mapear, y línea de OC.
  constraint invoice_lines_target_check check (
    (line_class in ('product', 'free_of_charge') and num_nonnulls(purchase_product_id, unmapped_article_id) <= 1)
    or (line_class not in ('product', 'free_of_charge') and purchase_product_id is null and unmapped_article_id is null
        and purchase_order_line_id is null)),
  -- Con 99 % o más de bonificación es un regalo; un regalo es eso.
  constraint invoice_lines_free_check check (
    (bonus1_pct >= 99 or bonus2_pct >= 99) = (line_class = 'free_of_charge')),
  -- El importe es cantidad × precio neto (tolerancia 0,01).
  constraint invoice_lines_amount_check check (abs(billed_quantity * unit_price - line_amount) <= 0.01),
  constraint invoice_lines_exempt_check check (not is_exempt or coalesce(vat_rate, 0) = 0)
);
create unique index invoice_lines_order_key on purchasing.invoice_lines (invoice_id, line_order) where deleted_at is null;
create index invoice_lines_invoice_idx on purchasing.invoice_lines (invoice_id, group_id);
create index invoice_lines_product_idx on purchasing.invoice_lines (purchase_product_id, group_id)
  where purchase_product_id is not null;
create index invoice_lines_unmapped_idx on purchasing.invoice_lines (unmapped_article_id, group_id)
  where unmapped_article_id is not null;
create index invoice_lines_po_line_idx on purchasing.invoice_lines (purchase_order_line_id)
  where purchase_order_line_id is not null;
create index invoice_lines_group_idx on purchasing.invoice_lines (group_id);
comment on table purchasing.invoice_lines is
  'Líneas de una factura, tal como están en el papel. Solo las de mercadería (product) cambian costos; flete, servicios y regalos, no (decisiones 4 y 5 de Soy).';
comment on column purchasing.invoice_lines.group_id is 'Grupo, el mismo que el de la factura.';
comment on column purchasing.invoice_lines.invoice_id is 'Factura.';
comment on column purchasing.invoice_lines.line_order is 'Orden de la línea.';
comment on column purchasing.invoice_lines.line_class is 'Clase de línea: mercadería, flete, servicio, redondeo, envase o regalo.';
comment on column purchasing.invoice_lines.purchase_product_id is 'El producto de compra (artículo del proveedor), si se reconoce.';
comment on column purchasing.invoice_lines.unmapped_article_id is 'Si no se reconoce: el artículo en la cola de mapeo.';
comment on column purchasing.invoice_lines.purchase_order_line_id is 'La línea de la OC a la que corresponde, si se pudo asociar.';
comment on column purchasing.invoice_lines.raw_name is 'El nombre tal como está en la factura.';
comment on column purchasing.invoice_lines.supplier_sku is 'El código de artículo del proveedor, si lo trae.';
comment on column purchasing.invoice_lines.units is 'Unidades (piezas, cajas) en lo que se cobra por peso.';
comment on column purchasing.invoice_lines.billed_quantity is
  'Cantidad facturada: envases, o kilos en lo que se cobra por peso (decisión de Joaco, 2026-11-18).';
comment on column purchasing.invoice_lines.list_price is 'Precio de lista que muestra la factura, antes de las bonificaciones.';
comment on column purchasing.invoice_lines.bonus1_pct is 'Primera bonificación, en %.';
comment on column purchasing.invoice_lines.bonus2_pct is 'Segunda bonificación, en %.';
comment on column purchasing.invoice_lines.bonus_per_unit_amount is 'Bonificación en pesos por unidad, después de los % (P6).';
comment on column purchasing.invoice_lines.unit_price is
  'Precio unitario neto: por envase, o por kilo en lo que va por peso. En A, sin IVA; en B, C, X y nota a mano, el precio final.';
comment on column purchasing.invoice_lines.vat_rate is 'Alícuota de IVA de la línea (0; 2,5; 5; 10,5; 21 o 27 %).';
comment on column purchasing.invoice_lines.is_exempt is 'Si la línea es exenta.';
comment on column purchasing.invoice_lines.internal_tax_amount is 'Impuestos internos de la línea. No suman al costo (decisión 4 de Soy).';
comment on column purchasing.invoice_lines.line_amount is 'Importe de la línea: cantidad × precio neto.';

create table purchasing.invoice_taxes (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references org.groups (id) on delete restrict,
  invoice_id    uuid not null,
  tax_kind      purchasing.invoice_tax_kind not null,
  jurisdiction  text check (jurisdiction is null or length(btrim(jurisdiction)) between 1 and 60),
  regime        text check (regime is null or length(btrim(regime)) between 1 and 60),
  rate_pct      numeric(6,3) check (rate_pct is null or (rate_pct >= 0 and rate_pct <= 100)),
  tax_amount    numeric(18,4) not null check (tax_amount > 0),
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict,
  constraint invoice_taxes_invoice_fkey foreign key (invoice_id, group_id)
    references purchasing.invoices (id, group_id) on delete restrict
);
create index invoice_taxes_invoice_idx on purchasing.invoice_taxes (invoice_id, group_id);
create index invoice_taxes_group_idx on purchasing.invoice_taxes (group_id);
comment on table purchasing.invoice_taxes is
  'Percepciones y otros tributos de una factura. Suman al total y al pago, nunca al costo (decisión 4 de Soy).';
comment on column purchasing.invoice_taxes.group_id is 'Grupo, el mismo que el de la factura.';
comment on column purchasing.invoice_taxes.invoice_id is 'Factura.';
comment on column purchasing.invoice_taxes.tax_kind is 'Tipo de tributo.';
comment on column purchasing.invoice_taxes.jurisdiction is 'Jurisdicción (por ejemplo, CABA o Provincia de Buenos Aires).';
comment on column purchasing.invoice_taxes.regime is 'Régimen (por ejemplo, RG 3337).';
comment on column purchasing.invoice_taxes.rate_pct is 'Alícuota, en %.';
comment on column purchasing.invoice_taxes.tax_amount is 'Importe.';

create table purchasing.invoice_checks (
  id               uuid primary key default gen_random_uuid(),
  entry_number     bigint generated always as identity,
  group_id         uuid not null references org.groups (id) on delete restrict,
  invoice_id       uuid not null,
  run_id           uuid not null,
  invoice_line_id  uuid references purchasing.invoice_lines (id) on delete restrict,
  check_kind       purchasing.invoice_check_kind not null,
  expected_amount  numeric(18,6),
  actual_amount    numeric(18,6),
  passed           boolean not null,
  explanation      text not null check (length(btrim(explanation)) between 1 and 300),
  run_at           timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  constraint invoice_checks_invoice_fkey foreign key (invoice_id, group_id)
    references purchasing.invoices (id, group_id) on delete restrict
);
create index invoice_checks_invoice_idx on purchasing.invoice_checks (invoice_id, entry_number desc);
create index invoice_checks_invoice_group_idx on purchasing.invoice_checks (invoice_id, group_id);
create index invoice_checks_line_idx on purchasing.invoice_checks (invoice_line_id) where invoice_line_id is not null;
create index invoice_checks_group_idx on purchasing.invoice_checks (group_id);
comment on table purchasing.invoice_checks is
  'Resultado del control de 3 vías: una fila por control (y por línea, en los de línea). Solo de inserción: cada corrida agrega las suyas con un mismo run_id y la pantalla muestra la última.';
comment on column purchasing.invoice_checks.id is 'Identificador.';
comment on column purchasing.invoice_checks.entry_number is
  'Número de entrada, creciente: la última corrida es la de la fila con el número más alto.';
comment on column purchasing.invoice_checks.group_id is 'Grupo, el mismo que el de la factura.';
comment on column purchasing.invoice_checks.invoice_id is 'Factura.';
comment on column purchasing.invoice_checks.run_id is 'Corrida del control (todas las filas de una corrida comparten este valor).';
comment on column purchasing.invoice_checks.invoice_line_id is 'Línea controlada. Vacía en los controles de la factura entera.';
comment on column purchasing.invoice_checks.check_kind is 'Qué se controló.';
comment on column purchasing.invoice_checks.expected_amount is 'Lo esperado (cantidad, precio o importe, según el control).';
comment on column purchasing.invoice_checks.actual_amount is 'Lo que dice la factura.';
comment on column purchasing.invoice_checks.passed is 'Si pasó.';
comment on column purchasing.invoice_checks.explanation is 'Qué se controló y qué dio, en simple (lo muestra el tooltip de la ficha).';
comment on column purchasing.invoice_checks.run_at is 'Cuándo se corrió.';
comment on column purchasing.invoice_checks.created_at is 'Cuándo se registró (lo pone la base).';
comment on column purchasing.invoice_checks.created_by is 'Quién corrió el control (lo pone la base).';

create table purchasing.credit_debit_notes (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references org.groups (id) on delete restrict,
  invoice_id    uuid not null,
  note_kind     purchasing.note_kind not null,
  number        text check (number is null or length(btrim(number)) between 1 and 40),
  issued_on     date not null check (issued_on >= date '2000-01-01'),
  net_amount    numeric(18,4) not null check (net_amount > 0),
  total_amount  numeric(18,4) not null check (total_amount > 0),
  reason        text not null check (length(btrim(reason)) between 3 and 500),
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict,
  constraint credit_debit_notes_invoice_fkey foreign key (invoice_id, group_id)
    references purchasing.invoices (id, group_id) on delete restrict,
  constraint credit_debit_notes_amounts_check check (total_amount >= net_amount)
);
create index credit_debit_notes_invoice_idx on purchasing.credit_debit_notes (invoice_id, group_id);
create index credit_debit_notes_group_idx on purchasing.credit_debit_notes (group_id);
comment on table purchasing.credit_debit_notes is
  'Notas de crédito, de débito y descuentos del proveedor sobre una factura. Sumar una vuelve a correr el control: si cubre la diferencia, la factura queda conforme. No se cambian ni se borran: un error se corrige con otra nota.';
comment on column purchasing.credit_debit_notes.group_id is 'Grupo, el mismo que el de la factura.';
comment on column purchasing.credit_debit_notes.invoice_id is 'Factura que corrige.';
comment on column purchasing.credit_debit_notes.note_kind is 'Crédito, débito o descuento.';
comment on column purchasing.credit_debit_notes.number is 'Número de la nota, si tiene.';
comment on column purchasing.credit_debit_notes.issued_on is 'Fecha de la nota.';
comment on column purchasing.credit_debit_notes.net_amount is
  'Importe sin IVA en una factura A; el importe final en las demás. Es lo que se compara con la diferencia del control.';
comment on column purchasing.credit_debit_notes.total_amount is 'Importe total de la nota (cuenta para el saldo y el pago, Prompt 6).';
comment on column purchasing.credit_debit_notes.reason is 'Por qué se emitió.';

-- ---------------------------------------------------------------------------
-- 5. Control, auditoría y RLS
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['invoices', 'invoice_orders', 'invoice_lines', 'invoice_taxes', 'credit_debit_notes'] loop
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

-- El control es solo de inserción: completa quién y cuándo, y rechaza cualquier cambio o borrado.
create function purchasing.invoice_checks_insert_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := core.current_actor_id();
    return new;
  end if;
  raise exception 'El resultado de un control no se cambia ni se borra: se vuelve a controlar.' using errcode = '42501';
end
$$;
comment on function purchasing.invoice_checks_insert_only() is
  'Interna: completa quién y cuándo en una fila nueva del control y rechaza cualquier cambio o borrado.';
revoke execute on function purchasing.invoice_checks_insert_only() from public;
alter table purchasing.invoice_checks enable row level security;
revoke all on purchasing.invoice_checks from public, anon, authenticated, service_role;
grant select on purchasing.invoice_checks to authenticated;
create trigger invoice_checks_insert_only before insert or update or delete on purchasing.invoice_checks
  for each row execute function purchasing.invoice_checks_insert_only();
create trigger log_change after insert on purchasing.invoice_checks
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on purchasing.invoice_checks
  for each statement execute function core.reject_truncate();

-- Cada uno ve las facturas de los locales donde tiene purchasing.view_invoices; el resto, de las facturas que ve.
create policy invoices_select on purchasing.invoices for select to authenticated
  using (deleted_at is null and restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_invoices')));
create policy invoice_orders_select on purchasing.invoice_orders for select to authenticated
  using (deleted_at is null and invoice_id in (select id from purchasing.invoices));
create policy invoice_lines_select on purchasing.invoice_lines for select to authenticated
  using (deleted_at is null and invoice_id in (select id from purchasing.invoices));
create policy invoice_taxes_select on purchasing.invoice_taxes for select to authenticated
  using (deleted_at is null and invoice_id in (select id from purchasing.invoices));
create policy invoice_checks_select on purchasing.invoice_checks for select to authenticated
  using (invoice_id in (select id from purchasing.invoices));
create policy credit_debit_notes_select on purchasing.credit_debit_notes for select to authenticated
  using (deleted_at is null and invoice_id in (select id from purchasing.invoices));

-- ---------------------------------------------------------------------------
-- 6. Reglas que la base hace cumplir
-- ---------------------------------------------------------------------------
-- La factura: el CUIT del emisor es el del proveedor (y nunca uno de ejemplo); conforme, liberada, pagada o cancelada,
-- no cambia nada más que el estado (liberada → pagada, Prompt 6).
create function purchasing.guard_invoice()
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
               or (old.status = 'released' and new.status = 'paid')) then
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
  -- El del receptor no se valida acá: el control lo compara con el de la razón social del local.
  return new;
end
$$;
comment on function purchasing.guard_invoice() is
  'Interna: el CUIT del emisor tiene que ser válido y el del proveedor (nunca el de ejemplo 99-99999999-9); una factura conforme, liberada, pagada o cancelada no cambia más que su estado; ninguna se borra.';
revoke execute on function purchasing.guard_invoice() from public;
create trigger guard_invoice before insert or update or delete on purchasing.invoices
  for each row execute function purchasing.guard_invoice();

-- Las partes de una factura (OC, líneas y tributos) cambian solo mientras está cargada u observada, y no se borran.
create function purchasing.guard_invoice_part()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_status purchasing.invoice_status;
begin
  if tg_op = 'DELETE' then
    raise exception 'Una parte de una factura no se borra: se da de baja.' using errcode = '42501';
  end if;
  select status into v_status from purchasing.invoices where id = new.invoice_id;
  if v_status is null or v_status not in ('loaded', 'observed') then
    raise exception 'Una factura conforme no cambia: corregila con una nota de crédito o débito.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.invoice_id <> old.invoice_id then
    raise exception 'Una parte no se pasa a otra factura.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function purchasing.guard_invoice_part() is
  'Interna: las OC, las líneas y los tributos de una factura cambian solo mientras está cargada u observada, nunca pasan a otra factura y no se borran (borrado lógico).';
revoke execute on function purchasing.guard_invoice_part() from public;
create trigger guard_invoice_part before insert or update or delete on purchasing.invoice_orders
  for each row execute function purchasing.guard_invoice_part();
create trigger guard_invoice_part before insert or update or delete on purchasing.invoice_lines
  for each row execute function purchasing.guard_invoice_part();
create trigger guard_invoice_part before insert or update or delete on purchasing.invoice_taxes
  for each row execute function purchasing.guard_invoice_part();

-- Las notas no se cambian ni se borran: un error se corrige con otra nota. Entran a una factura cargada, observada,
-- conforme o liberada (no a una cancelada).
create function purchasing.guard_note()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'Una nota de crédito o débito no se cambia ni se borra: se corrige con otra nota.' using errcode = '42501';
  end if;
  if (select status from purchasing.invoices where id = new.invoice_id) not in ('loaded', 'observed', 'approved',
                                                                                'released') then
    raise exception 'A esta factura no se le suman notas.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function purchasing.guard_note() is
  'Interna: una nota de crédito, débito o descuento no se cambia ni se borra, y no entra a una factura cancelada o pagada.';
revoke execute on function purchasing.guard_note() from public;
create trigger guard_note before insert or update or delete on purchasing.credit_debit_notes
  for each row execute function purchasing.guard_note();

-- ---------------------------------------------------------------------------
-- 7. Fotos: adjuntos de facturas y notas
-- ---------------------------------------------------------------------------
alter table purchasing.attachments drop constraint attachments_source_table_check;
alter table purchasing.attachments add constraint attachments_source_table_check
  check (source_table in ('price_lists', 'receipts', 'receipt_lines', 'invoices', 'credit_debit_notes'));
comment on table purchasing.attachments is
  'Archivos de compras (listas de precios, fotos de recepciones, facturas y notas de crédito o débito) guardados en el bucket purchasing-documents. Solo de inserción: un archivo subido no se cambia ni se borra; si se rehace una foto, vale la última.';
comment on column purchasing.attachments.source_table is
  'Tabla del registro de origen: price_lists, receipts, receipt_lines, invoices o credit_debit_notes.';
comment on column purchasing.attachments.source_id is 'Registro de origen (la lista, la recepción, el renglón, la factura o la nota).';

drop policy attachments_select on purchasing.attachments;
create policy attachments_select on purchasing.attachments for select to authenticated
  using ((source_table = 'price_lists'
          and group_id in (select core.visible_group_ids('purchasing.view_price_lists')))
         or (source_table = 'receipts' and source_id in (select id from purchasing.receipts))
         or (source_table = 'receipt_lines' and source_id in (select id from purchasing.receipt_lines))
         or (source_table = 'invoices' and source_id in (select id from purchasing.invoices))
         or (source_table = 'credit_debit_notes' and source_id in (select id from purchasing.credit_debit_notes)));

-- Subir: listas y recepciones, como antes; la foto (o el PDF) de una factura cargada u observada, y la de una nota de
-- una factura que todavía admite notas, con purchasing.manage_invoices en su local.
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
               exists (select 1 from purchasing.invoices i
                        where i.id = d.source_id and i.group_id = d.group_id and i.deleted_at is null
                          and i.status in ('loaded', 'observed')
                          and purchasing.can_in_restaurant('purchasing.manage_invoices', i.restaurant_id))
             when 'credit_debit_notes' then
               exists (select 1 from purchasing.credit_debit_notes n
                         join purchasing.invoices i on i.id = n.invoice_id
                        where n.id = d.source_id and n.group_id = d.group_id and n.deleted_at is null
                          and i.status in ('loaded', 'observed', 'approved', 'released')
                          and purchasing.can_in_restaurant('purchasing.manage_invoices', i.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_upload_document(text) is
  'Si la sesión puede subir ese archivo, con nombre <grupo>/<tabla>/<registro>/<uuid>.<ext>: una lista recibida del grupo (purchasing.manage_price_lists); una foto .jpg de una recepción abierta (purchasing.receive en su local); la foto o el PDF de una factura cargada u observada, o de una nota de una factura que admite notas (purchasing.manage_invoices en su local).';

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
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_read_own_document(text) is
  'Si la sesión puede leer un archivo que acaba de subir, antes de registrarlo: carga listas en el grupo de la carpeta, recibe en el local de la recepción abierta, o carga facturas en el local de la factura (o de la nota). La política de Storage exige además que lo haya subido ella.';

-- Archivos registrados que la sesión ve: los de antes y los de las facturas (y sus notas) que ve.
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
$$;
comment on function purchasing.visible_document_paths() is
  'Archivos de compras registrados que la sesión ve: los de las listas de su grupo (purchasing.view_price_lists), las fotos de las recepciones de los locales cuyas OC ve (purchasing.view_orders) y las de las facturas y notas de los locales donde ve facturas (purchasing.view_invoices). Para la política de lectura de Storage.';
