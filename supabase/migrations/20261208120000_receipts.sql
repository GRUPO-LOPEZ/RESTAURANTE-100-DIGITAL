-- Fase 3, Prompt 4 (ADR-0056): recepción con fotos, validación por línea y entradas de stock.
--
-- - Una recepción se abre sobre una OC enviada (o «sin OC», con un proveedor) y se cierra en una sola transacción:
--   la clase de papel, una decisión por cada renglón pendiente (OK u observado), la foto 1 (el papel como llegó) y la
--   foto 2 (firmado), y, si se pagó en efectivo, el importe para que Compras lo confirme (decisión 7 de Soy).
-- - Al cerrar: suma lo recibido a la OC (que queda recibida o recibida parcial), registra una entrada de stock por
--   renglón recibido en la unidad de uso (D8: nada descuenta todavía), manda a la cola de mapeo lo que llegó y el sistema
--   no reconoce, y avisa a quien pidió y, si hubo observaciones o efectivo, a Compras.
-- - Una recepción cerrada no se cambia. Las fotos son adjuntos solo de inserción: «Rehacer» suma otra y vale la última.
-- - La factura (Prompt 5) y el pago (Prompt 6) todavía no existen: la recepción guarda la clase de papel, sus fotos y el
--   efectivo, y esos prompts los toman de acá.

-- ---------------------------------------------------------------------------
-- 1. Permisos
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de recepción e inventario (Fase 3, ADR-0056)', 'maintenance');
  insert into core.permission_modules (code, name, sort_order) values ('inventory', 'Inventario', 170);
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('purchasing.receive', 'purchasing', 'receive', 'Recibir mercadería', 100,
     'Recibir lo que llega al local: validar cada renglón contra la OC, sacar las fotos del papel y cerrar la recepción, que suma el stock.',
     false),
    ('inventory.view', 'inventory', 'view', 'Ver inventario', 10,
     'Ver los movimientos de stock de los locales que ve (entradas por recepción, con su lote).', false);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values
      ('cook', 'purchasing.receive'), ('head_chef', 'purchasing.receive'),
      ('restaurant_manager', 'purchasing.receive'), ('purchasing', 'purchasing.receive'),
      ('general_management', 'inventory.view'), ('restaurant_manager', 'inventory.view'),
      ('executive_chef', 'inventory.view'), ('head_chef', 'inventory.view'),
      ('controller', 'inventory.view'), ('auditor', 'inventory.view'),
      -- Regla G2: quien administra personas tiene los permisos de los roles que administra.
      ('brand_director', 'purchasing.receive'), ('brand_director', 'inventory.view'),
      ('superadmin', 'purchasing.receive'), ('superadmin', 'inventory.view')
    ) as v (role_code, permission_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = v.permission_code and p.deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Tipos
-- ---------------------------------------------------------------------------
create type purchasing.paper_kind as enum ('invoice', 'invoice_remito', 'remito', 'electronic_remito', 'non_fiscal',
                                           'handwritten_note');
comment on type purchasing.paper_kind is
  'Qué papel trajo el proveedor: invoice (factura), invoice_remito (factura-remito), remito, electronic_remito (remito electrónico), non_fiscal (comprobante no fiscal) o handwritten_note (nota a mano).';
create type purchasing.receipt_status as enum ('open', 'closed');
comment on type purchasing.receipt_status is
  'Estado de una recepción: open (abierta: se están sacando las fotos y revisando los renglones) o closed (cerrada: no se cambia).';
create type purchasing.receipt_result as enum ('complete', 'partial', 'with_differences');
comment on type purchasing.receipt_result is
  'Cómo terminó una recepción: complete (llegó todo bien), partial (la OC quedó con renglones pendientes) o with_differences (llegó todo, con observaciones).';
create type purchasing.receipt_issue as enum ('missing', 'extra', 'different_product', 'quality', 'expired');
comment on type purchasing.receipt_issue is
  'Observación de un renglón recibido: missing (faltó), extra (de más, o algo que no estaba en la OC), different_product (mandaron otro producto), quality (mala calidad) o expired (vencido).';
create type inventory.movement_kind as enum ('purchase_receipt', 'sale', 'adjustment', 'count');
comment on type inventory.movement_kind is
  'Tipo de movimiento de stock: purchase_receipt (entrada por recepción). Previstos, sin uso todavía: sale (venta), adjustment (ajuste) y count (conteo).';

-- ---------------------------------------------------------------------------
-- 3. Recepciones
-- ---------------------------------------------------------------------------
create table purchasing.receipts (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null references org.groups (id) on delete restrict,
  brand_id           uuid not null,
  restaurant_id      uuid not null,
  supplier_id        uuid not null,
  purchase_order_id  uuid,
  status             purchasing.receipt_status not null default 'open',
  received_by        uuid not null references core.actors (id) on delete restrict,
  closed_at          timestamptz,
  result             purchasing.receipt_result,
  paper_kind         purchasing.paper_kind,
  paper_number       text check (paper_number is null or length(btrim(paper_number)) between 1 and 40),
  cash_paid_amount   numeric(14,4) check (cash_paid_amount is null or cash_paid_amount > 0),
  currency           text not null default 'ARS' check (currency = 'ARS'),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint receipts_id_group_key unique (id, group_id),
  constraint receipts_restaurant_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint receipts_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint receipts_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint receipts_order_fkey foreign key (purchase_order_id, group_id)
    references purchasing.purchase_orders (id, group_id) on delete restrict,
  constraint receipts_closed_check check (
    (status = 'open' and closed_at is null and result is null and paper_kind is null and cash_paid_amount is null)
    or (status = 'closed' and closed_at is not null and result is not null and paper_kind is not null))
);
create unique index receipts_open_order_key on purchasing.receipts (purchase_order_id)
  where status = 'open' and purchase_order_id is not null and deleted_at is null;
create index receipts_restaurant_idx on purchasing.receipts (restaurant_id, status, created_at desc)
  where deleted_at is null;
create index receipts_restaurant_group_idx on purchasing.receipts (restaurant_id, group_id);
create index receipts_restaurant_brand_idx on purchasing.receipts (restaurant_id, brand_id);
create index receipts_supplier_idx on purchasing.receipts (supplier_id, group_id);
create index receipts_order_idx on purchasing.receipts (purchase_order_id, group_id) where purchase_order_id is not null;
create index receipts_received_by_idx on purchasing.receipts (received_by);
create index receipts_group_idx on purchasing.receipts (group_id);
comment on table purchasing.receipts is
  'Recepciones de mercadería: lo que llegó al local, validado renglón por renglón contra la OC (o sin OC), con la foto del papel como llegó y la del papel firmado. Cerrada, no se cambia.';
comment on column purchasing.receipts.group_id is 'Grupo, el mismo que el del local y el del proveedor.';
comment on column purchasing.receipts.brand_id is 'Marca del local que recibe.';
comment on column purchasing.receipts.restaurant_id is 'Local que recibe (donde entra el stock).';
comment on column purchasing.receipts.supplier_id is 'Proveedor que entregó.';
comment on column purchasing.receipts.purchase_order_id is 'La orden de compra que se recibe. Vacía si llegó sin OC.';
comment on column purchasing.receipts.status is 'Abierta o cerrada.';
comment on column purchasing.receipts.received_by is 'Quién recibe.';
comment on column purchasing.receipts.closed_at is 'Cuándo se cerró.';
comment on column purchasing.receipts.result is 'Cómo terminó: completa, parcial o con observaciones.';
comment on column purchasing.receipts.paper_kind is
  'Qué papel trajo el proveedor. Si es una factura, en el Prompt 5 se carga desde acá, con estas fotos (D3: el remito valida lo recibido; la factura manda para los costos).';
comment on column purchasing.receipts.paper_number is 'El número del papel, si se ve.';
comment on column purchasing.receipts.cash_paid_amount is
  'Lo que se le pagó en efectivo al proveedor al recibir, para que Compras lo confirme (decisión 7 de Soy; en el Prompt 6 pasa a un pago «para confirmar»). No lo leen quienes no ven precios.';
comment on column purchasing.receipts.currency is 'Moneda del efectivo. Solo ARS.';

create table purchasing.receipt_lines (
  id                      uuid primary key default gen_random_uuid(),
  group_id                uuid not null references org.groups (id) on delete restrict,
  receipt_id              uuid not null,
  line_order              integer not null check (line_order between 1 and 600),
  purchase_order_line_id  uuid references purchasing.purchase_order_lines (id) on delete restrict,
  purchase_product_id     uuid,
  ingredient_id           uuid,
  unmapped_article_id     uuid,
  description             text check (description is null or length(btrim(description)) between 1 and 200),
  ok                      boolean not null,
  issue                   purchasing.receipt_issue,
  received_quantity       numeric(14,4) not null check (received_quantity >= 0),
  received_weight         numeric(14,4) check (received_weight is null or received_weight > 0),
  lot_code                text check (lot_code is null or length(btrim(lot_code)) between 1 and 60),
  note                    text check (note is null or length(btrim(note)) between 1 and 300),
  created_at              timestamptz not null default now(),
  created_by              uuid references core.actors (id) on delete restrict,
  updated_at              timestamptz not null default now(),
  updated_by              uuid references core.actors (id) on delete restrict,
  deleted_at              timestamptz,
  deleted_by              uuid references core.actors (id) on delete restrict,
  constraint receipt_lines_receipt_fkey foreign key (receipt_id, group_id)
    references purchasing.receipts (id, group_id) on delete restrict,
  constraint receipt_lines_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict,
  constraint receipt_lines_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint receipt_lines_unmapped_fkey foreign key (unmapped_article_id, group_id)
    references purchasing.unmapped_articles (id, group_id) on delete restrict,
  -- OK no lleva observación; observado, sí.
  constraint receipt_lines_issue_check check (ok = (issue is null)),
  -- Un renglón es de la OC o, si no estaba, un artículo reconocido o uno que fue a la cola de mapeo.
  constraint receipt_lines_target_check check (
    purchase_order_line_id is not null
    or (description is not null and num_nonnulls(purchase_product_id, unmapped_article_id) = 1)),
  -- Lo que llegó y no se reconoce no suma stock: no se sabe qué materia prima es.
  constraint receipt_lines_unmapped_check check (unmapped_article_id is null or ingredient_id is null)
);
create unique index receipt_lines_order_key on purchasing.receipt_lines (receipt_id, line_order) where deleted_at is null;
create unique index receipt_lines_po_line_key on purchasing.receipt_lines (receipt_id, purchase_order_line_id)
  where purchase_order_line_id is not null and deleted_at is null;
create index receipt_lines_receipt_idx on purchasing.receipt_lines (receipt_id, group_id);
create index receipt_lines_po_line_idx on purchasing.receipt_lines (purchase_order_line_id)
  where purchase_order_line_id is not null;
create index receipt_lines_product_idx on purchasing.receipt_lines (purchase_product_id, group_id)
  where purchase_product_id is not null;
create index receipt_lines_ingredient_idx on purchasing.receipt_lines (ingredient_id, group_id)
  where ingredient_id is not null;
create index receipt_lines_unmapped_idx on purchasing.receipt_lines (unmapped_article_id, group_id)
  where unmapped_article_id is not null;
create index receipt_lines_lot_idx on purchasing.receipt_lines (group_id, lot_code) where lot_code is not null;
create index receipt_lines_group_idx on purchasing.receipt_lines (group_id);
comment on table purchasing.receipt_lines is
  'Renglones de una recepción: la decisión sobre cada renglón de la OC (OK u observado, con lo que llegó) y lo que llegó sin estar en la OC. Se guardan al cerrar y no se cambian.';
comment on column purchasing.receipt_lines.group_id is 'Grupo, el mismo que el de la recepción.';
comment on column purchasing.receipt_lines.receipt_id is 'Recepción.';
comment on column purchasing.receipt_lines.line_order is 'Orden del renglón.';
comment on column purchasing.receipt_lines.purchase_order_line_id is 'El renglón de la OC. Vacío si llegó algo que no estaba.';
comment on column purchasing.receipt_lines.purchase_product_id is 'El producto de compra que llegó, si se conoce.';
comment on column purchasing.receipt_lines.ingredient_id is 'La materia prima que entra al stock, si se sabe cuál es.';
comment on column purchasing.receipt_lines.unmapped_article_id is
  'Si llegó algo que no estaba en la OC y el sistema no lo reconoce: el artículo en la cola de mapeo.';
comment on column purchasing.receipt_lines.description is 'Lo que llegó sin estar en la OC, tal como lo anotó quien recibió.';
comment on column purchasing.receipt_lines.ok is 'Llegó bien: lo pedido, en cantidad y estado.';
comment on column purchasing.receipt_lines.issue is 'Qué se observó (obligatorio si no está OK).';
comment on column purchasing.receipt_lines.received_quantity is
  'Cuánto se recibió: envases del producto, o la cantidad de la materia prima en su unidad («sin nombre de factura»).';
comment on column purchasing.receipt_lines.received_weight is 'Kilos recibidos, en lo que va por peso (si se pesó).';
comment on column purchasing.receipt_lines.lot_code is 'Lote, si lo trae (para seguirlo desde Inventario y Calidad).';
comment on column purchasing.receipt_lines.note is 'Nota corta de quien recibió.';

-- ---------------------------------------------------------------------------
-- 4. Movimientos de stock (esquema inventory)
-- ---------------------------------------------------------------------------
grant usage on schema inventory to authenticated;

create table inventory.stock_movements (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  brand_id             uuid not null,
  restaurant_id        uuid not null,
  ingredient_id        uuid not null,
  purchase_product_id  uuid,
  kind                 inventory.movement_kind not null,
  quantity             numeric(20,6) not null check (quantity <> 0),
  unit_id              uuid not null references catalog.units (id) on delete restrict,
  packages             numeric(14,4) check (packages is null or packages > 0),
  lot_code             text check (lot_code is null or length(btrim(lot_code)) between 1 and 60),
  occurred_at          timestamptz not null,
  source_table         text not null check (source_table in ('receipt_lines')),
  source_id            uuid not null,
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  constraint stock_movements_restaurant_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint stock_movements_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint stock_movements_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint stock_movements_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict
);
create unique index stock_movements_source_key on inventory.stock_movements (source_table, source_id);
create index stock_movements_restaurant_idx on inventory.stock_movements (restaurant_id, occurred_at desc);
create index stock_movements_restaurant_group_idx on inventory.stock_movements (restaurant_id, group_id);
create index stock_movements_restaurant_brand_idx on inventory.stock_movements (restaurant_id, brand_id);
create index stock_movements_ingredient_idx on inventory.stock_movements (ingredient_id, group_id, occurred_at desc);
create index stock_movements_product_idx on inventory.stock_movements (purchase_product_id, group_id)
  where purchase_product_id is not null;
create index stock_movements_unit_idx on inventory.stock_movements (unit_id);
create index stock_movements_lot_idx on inventory.stock_movements (group_id, lower(lot_code)) where lot_code is not null;
create index stock_movements_group_idx on inventory.stock_movements (group_id);
comment on table inventory.stock_movements is
  'Movimientos de stock por local y materia prima, en su unidad de uso. Hoy solo entradas por recepción (D8: nada descuenta todavía). Solo de inserción, y solo desde purchasing.close_receipt.';
comment on column inventory.stock_movements.id is 'Identificador.';
comment on column inventory.stock_movements.group_id is 'Grupo, el mismo que el del local.';
comment on column inventory.stock_movements.brand_id is 'Marca del local.';
comment on column inventory.stock_movements.restaurant_id is 'Local donde entra o sale el stock.';
comment on column inventory.stock_movements.ingredient_id is 'Materia prima.';
comment on column inventory.stock_movements.purchase_product_id is 'Producto de compra que entró, si se conoce.';
comment on column inventory.stock_movements.kind is 'Tipo de movimiento.';
comment on column inventory.stock_movements.quantity is 'Cantidad en la unidad de uso de la materia prima: positiva entra, negativa sale.';
comment on column inventory.stock_movements.unit_id is 'Unidad de la cantidad (la de uso de la materia prima al momento del movimiento).';
comment on column inventory.stock_movements.packages is 'Envases recibidos, si entró por producto de compra.';
comment on column inventory.stock_movements.lot_code is 'Lote, si vino.';
comment on column inventory.stock_movements.occurred_at is 'Cuándo pasó (al cerrar la recepción).';
comment on column inventory.stock_movements.source_table is 'Tabla del registro que lo originó (por ahora, receipt_lines).';
comment on column inventory.stock_movements.source_id is 'Registro que lo originó (el renglón de la recepción).';
comment on column inventory.stock_movements.created_at is 'Cuándo se registró (lo pone la base).';
comment on column inventory.stock_movements.created_by is 'Quién lo registró (lo pone la base).';

create function inventory.movements_insert_only()
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
  raise exception 'Un movimiento de stock no se cambia ni se borra: se corrige con otro movimiento.' using errcode = '42501';
end
$$;
comment on function inventory.movements_insert_only() is
  'Interna: completa quién y cuándo en un movimiento nuevo y rechaza cualquier cambio o borrado.';
revoke execute on function inventory.movements_insert_only() from public;
create trigger movements_insert_only before insert or update or delete on inventory.stock_movements
  for each row execute function inventory.movements_insert_only();
create trigger log_change after insert on inventory.stock_movements
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on inventory.stock_movements
  for each statement execute function core.reject_truncate();
alter table inventory.stock_movements enable row level security;
revoke all on inventory.stock_movements from public, anon, authenticated, service_role;
grant select on inventory.stock_movements to authenticated;
create policy stock_movements_select on inventory.stock_movements for select to authenticated
  using (restaurant_id in (select core.permitted_restaurant_ids('inventory.view')));

-- ---------------------------------------------------------------------------
-- 5. Control, auditoría y RLS de recepciones
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['receipts', 'receipt_lines'] loop
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

-- El efectivo se protege por columna (security.md): lo leen, con purchasing.receipt_detail, solo quienes ven precios.
revoke select on purchasing.receipts from authenticated;
grant select (id, group_id, brand_id, restaurant_id, supplier_id, purchase_order_id, status, received_by, closed_at,
              result, paper_kind, paper_number, currency, created_at, created_by, updated_at, updated_by, deleted_at,
              deleted_by)
  on purchasing.receipts to authenticated;

-- Cada uno ve las recepciones de los locales cuyas OC ve; los renglones, los de las recepciones que ve.
create policy receipts_select on purchasing.receipts for select to authenticated
  using (deleted_at is null and restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_orders')));
create policy receipt_lines_select on purchasing.receipt_lines for select to authenticated
  using (deleted_at is null and receipt_id in (select id from purchasing.receipts));

-- Cerrada, no se cambia: ni la recepción ni sus renglones. Los renglones entran mientras está abierta (al cerrar).
create function purchasing.guard_closed_receipt()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'receipts' then
    if tg_op = 'DELETE' or old.status = 'closed' then
      raise exception 'Una recepción cerrada no se cambia.' using errcode = '42501';
    end if;
    return new;
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'Una recepción cerrada no se cambia.' using errcode = '42501';
  end if;
  if (select status from purchasing.receipts where id = new.receipt_id) <> 'open' then
    raise exception 'Una recepción cerrada no se cambia.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function purchasing.guard_closed_receipt() is
  'Interna: una recepción cerrada no se cambia, y sus renglones no se cambian nunca (se cargan una vez, al cerrar).';
revoke execute on function purchasing.guard_closed_receipt() from public;
create trigger guard_closed_receipt before update or delete on purchasing.receipts
  for each row execute function purchasing.guard_closed_receipt();
create trigger guard_closed_receipt before insert or update or delete on purchasing.receipt_lines
  for each row execute function purchasing.guard_closed_receipt();

-- ---------------------------------------------------------------------------
-- 6. Fotos: adjuntos de recepciones y Storage
-- ---------------------------------------------------------------------------
alter table purchasing.attachments drop constraint attachments_source_table_check;
alter table purchasing.attachments add constraint attachments_source_table_check
  check (source_table in ('price_lists', 'receipts', 'receipt_lines'));
comment on table purchasing.attachments is
  'Archivos de compras (listas de precios y fotos de recepciones) guardados en el bucket purchasing-documents. Solo de inserción: un archivo subido no se cambia ni se borra; si se rehace una foto, vale la última.';
comment on column purchasing.attachments.source_table is 'Tabla del registro de origen: price_lists, receipts o receipt_lines.';
comment on column purchasing.attachments.source_id is 'Registro de origen (la lista, la recepción o el renglón observado).';

-- Lectura de los adjuntos: las listas, como antes; las fotos, de las recepciones que la sesión ve.
drop policy attachments_select on purchasing.attachments;
create policy attachments_select on purchasing.attachments for select to authenticated
  using ((source_table = 'price_lists'
          and group_id in (select core.visible_group_ids('purchasing.view_price_lists')))
         or (source_table = 'receipts' and source_id in (select id from purchasing.receipts))
         or (source_table = 'receipt_lines' and source_id in (select id from purchasing.receipt_lines)));

-- Subir: listas, como antes; fotos, a la carpeta de una recepción abierta, con purchasing.receive en su local.
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
               exists (select 1 from purchasing.receipts r
                        where r.id = d.source_id and r.group_id = d.group_id and r.deleted_at is null
                          and r.status = 'open'
                          and purchasing.can_in_restaurant('purchasing.receive', r.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_upload_document(text) is
  'Si la sesión puede subir ese archivo, con nombre <grupo>/<tabla>/<registro>/<uuid>.jpg|png|webp|pdf: una lista recibida (sin aceptar) del grupo, con purchasing.manage_price_lists; o una recepción abierta, con purchasing.receive en su local. Lo cerrado ya no suma archivos.';

-- Leer lo que acaba de subir (Storage lo vuelve a leer al guardar), antes de registrarlo.
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
                          and purchasing.can_in_restaurant('purchasing.receive', r.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_read_own_document(text) is
  'Si la sesión puede leer un archivo que acaba de subir, antes de registrarlo: carga listas en el grupo de la carpeta, o recibe en el local de la recepción de la carpeta.';

-- Archivos registrados que la sesión ve: los de las listas de su grupo y las fotos de las recepciones de sus locales.
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
$$;
comment on function purchasing.visible_document_paths() is
  'Archivos de compras registrados que la sesión ve: los de las listas de su grupo (purchasing.view_price_lists) y las fotos de las recepciones de los locales cuyas OC ve (purchasing.view_orders). Para la política de lectura de Storage.';

-- ---------------------------------------------------------------------------
-- 7. Mensajes claros
-- ---------------------------------------------------------------------------
create function purchasing.raise_receipt_error(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'receipt_lines_received_quantity_check' then 'La cantidad recibida no puede ser negativa.'
    when p_constraint = 'receipt_lines_received_weight_check' then 'El peso tiene que ser mayor que cero.'
    when p_constraint = 'receipt_lines_lot_code_check' then 'El lote va hasta 60 caracteres.'
    when p_constraint = 'receipt_lines_note_check' then 'La nota de un renglón va hasta 300 caracteres.'
    when p_constraint = 'receipt_lines_description_check' then 'Escribí qué llegó (hasta 200 caracteres).'
    when p_constraint = 'receipt_lines_issue_check' then 'Elegí qué pasó con el renglón observado.'
    when p_constraint = 'receipt_lines_po_line_key' then 'Hay un renglón de la OC repetido: recargá la página.'
    when p_constraint = 'receipts_paper_number_check' then 'El número del papel va hasta 40 caracteres.'
    when p_constraint = 'receipts_cash_paid_amount_check' then 'El importe en efectivo tiene que ser mayor que cero.'
    when p_constraint = 'receipts_open_order_key' then 'Esta OC ya tiene una recepción abierta: retomala.'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la recepción.'
    else null
  end;
  if v_message is null then
    perform purchasing.raise_order_error(p_state, p_constraint, p_message);
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function purchasing.raise_receipt_error(text, text, text) is
  'Interna: traduce a un mensaje en español el error de una restricción de recepciones (y, si no es suya, usa la de órdenes de compra).';
revoke execute on function purchasing.raise_receipt_error(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 8. Abrir una recepción
-- ---------------------------------------------------------------------------
-- Recibir una OC enviada (o con novedad, o recibida parcial). Si ya tiene una abierta, la retoma. Recibe el local que
-- la pidió, salvo que se elija otro del mismo grupo (un local puede recibir para otro); el stock entra donde se recibe.
create function purchasing.start_receipt(p_order_id uuid, p_restaurant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o  purchasing.purchase_orders;
  v_r  org.restaurants;
  v_id uuid;
begin
  select * into v_o from purchasing.purchase_orders where id = p_order_id and deleted_at is null;
  select * into v_r from org.restaurants
   where id = coalesce(p_restaurant_id, v_o.restaurant_id) and group_id = v_o.group_id and deleted_at is null;
  if v_o.id is null or v_r.id is null
     or not purchasing.can_in_restaurant('purchasing.view_orders', v_o.restaurant_id)
     or not purchasing.can_in_restaurant('purchasing.receive', v_r.id) then
    return core.deny('purchasing.start_receipt', 'No tenés permiso para recibir esta orden en este local.', null,
                     jsonb_build_object('purchase_order_id', p_order_id, 'restaurant_id', p_restaurant_id),
                     coalesce(v_r.group_id, v_o.group_id), coalesce(v_r.brand_id, v_o.brand_id),
                     coalesce(v_r.id, v_o.restaurant_id));
  end if;
  select * into v_o from purchasing.purchase_orders where id = v_o.id for update;
  if v_o.status not in ('sent', 'with_news', 'partially_received') then
    raise exception 'Esta orden no está para recibir: tiene que estar enviada o recibida parcial.' using errcode = '23514';
  end if;
  select id into v_id from purchasing.receipts
   where purchase_order_id = v_o.id and status = 'open' and deleted_at is null;
  if v_id is not null then
    return jsonb_build_object('result', 'applied', 'receipt_id', v_id, 'resumed', true);
  end if;
  perform core.set_change_context(format('Recepción de la orden %s', v_o.number), 'manual');
  insert into purchasing.receipts (group_id, brand_id, restaurant_id, supplier_id, purchase_order_id, received_by)
  values (v_r.group_id, v_r.brand_id, v_r.id, v_o.supplier_id, v_o.id, core.current_actor_id())
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'receipt_id', v_id, 'resumed', false);
end
$$;
comment on function purchasing.start_receipt(uuid, uuid) is
  'Abre la recepción de una OC enviada, con novedad o recibida parcial (o retoma la que ya está abierta). Pide ver la OC y purchasing.receive en el local que recibe (por defecto, el que la pidió).';
revoke execute on function purchasing.start_receipt(uuid, uuid) from public;
grant execute on function purchasing.start_receipt(uuid, uuid) to authenticated;

-- «Recibir sin OC»: llegó mercadería de un proveedor sin orden.
create function purchasing.start_receipt_without_order(p_supplier_id uuid, p_restaurant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r  org.restaurants;
  v_s  catalog.suppliers;
  v_id uuid;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.receive', v_r.id) then
    return core.deny('purchasing.start_receipt_without_order', 'No tenés permiso para recibir en este local.', null,
                     jsonb_build_object('restaurant_id', p_restaurant_id), v_r.group_id, v_r.brand_id, v_r.id);
  end if;
  select * into v_s from catalog.suppliers
   where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null and is_active;
  if v_s.id is null then
    raise exception 'Elegí un proveedor activo de este grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(format('Recepción sin OC de %s', coalesce(v_s.trade_name, v_s.name)), 'manual');
  insert into purchasing.receipts (group_id, brand_id, restaurant_id, supplier_id, received_by)
  values (v_r.group_id, v_r.brand_id, v_r.id, v_s.id, core.current_actor_id())
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'receipt_id', v_id, 'resumed', false);
end
$$;
comment on function purchasing.start_receipt_without_order(uuid, uuid) is
  '«Recibir sin OC»: abre una recepción de un proveedor activo del grupo, sin orden. Pide purchasing.receive en el local.';
revoke execute on function purchasing.start_receipt_without_order(uuid, uuid) from public;
grant execute on function purchasing.start_receipt_without_order(uuid, uuid) to authenticated;

-- Registrar una foto ya subida a la carpeta de la recepción: la 1 (el papel como llegó) o la 2 (firmado), con su
-- página. Rehacer suma otra: vale la última de cada foto y página.
create function purchasing.add_receipt_attachment(p_receipt_id uuid, p_storage_path text, p_kind purchasing.doc_kind,
                                                  p_page smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r  purchasing.receipts;
  v_id uuid;
begin
  select * into v_r from purchasing.receipts where id = p_receipt_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.receive', v_r.restaurant_id) then
    return core.deny('purchasing.add_receipt_attachment', 'No tenés permiso para sumar fotos a esta recepción.', null,
                     jsonb_build_object('receipt_id', p_receipt_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if v_r.status <> 'open' then
    raise exception 'Una recepción cerrada no se cambia.' using errcode = '23514';
  end if;
  if p_kind is null or p_kind not in ('receipt_original', 'receipt_signed') then
    raise exception 'La foto es la del papel como llegó o la del papel firmado.' using errcode = '22023';
  end if;
  if coalesce(p_page, 1) not between 1 and 20 then
    raise exception 'Van hasta 20 páginas por foto.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.document_parts(p_storage_path) d
                  where d.group_id = v_r.group_id and d.source_table = 'receipts' and d.source_id = v_r.id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'purchasing-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'La foto no está subida en la carpeta de esta recepción.' using errcode = '22023';
  end if;
  perform core.set_change_context(case p_kind when 'receipt_original' then 'Foto del papel como llegó'
                                              else 'Foto del papel firmado' end, 'manual');
  insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
  values (v_r.group_id, 'receipts', v_r.id, p_kind, coalesce(p_page, 1), p_storage_path)
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;
comment on function purchasing.add_receipt_attachment(uuid, text, purchasing.doc_kind, smallint) is
  'Registra una foto ya subida a la carpeta de una recepción abierta: la del papel como llegó (receipt_original) o la del papel firmado (receipt_signed), con su página. Rehacer suma otra; vale la última. Pide purchasing.receive en el local.';
revoke execute on function purchasing.add_receipt_attachment(uuid, text, purchasing.doc_kind, smallint) from public;
grant execute on function purchasing.add_receipt_attachment(uuid, text, purchasing.doc_kind, smallint) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Cerrar una recepción
-- ---------------------------------------------------------------------------
-- Cuánto entra al stock, en la unidad de uso de la materia prima. Envases de un producto: envases × unidades × contenido.
-- Por peso, si se pesó: los kilos. Una materia prima «sin nombre de factura»: la cantidad en su unidad.
create function purchasing.receipt_stock_quantity(p_ingredient_id uuid, p_product_id uuid, p_quantity numeric,
                                                  p_unit_id uuid, p_weight_kg numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p    catalog.purchase_products;
  v_base record;
begin
  if p_product_id is not null then
    select * into v_p from catalog.purchase_products where id = p_product_id;
    if v_p.billed_by_weight and p_weight_kg is not null then
      select b.base_quantity, b.status into v_base
        from catalog.to_base_quantity(p_ingredient_id, p_weight_kg,
                                      (select u.id from catalog.units u where u.code = 'kg' and u.deleted_at is null)) b;
    else
      select b.base_quantity, b.status into v_base
        from catalog.to_base_quantity(p_ingredient_id, p_quantity * v_p.units_per_package * v_p.content_per_unit,
                                      v_p.content_unit_id) b;
    end if;
  else
    select b.base_quantity, b.status into v_base from catalog.to_base_quantity(p_ingredient_id, p_quantity, p_unit_id) b;
  end if;
  if v_base.status is distinct from 'ok' then
    raise exception 'No sabemos pasar «%» a su unidad de uso: revisá el envase del producto o las conversiones de la materia prima.',
      (select name from catalog.ingredients where id = p_ingredient_id) using errcode = '22023';
  end if;
  return v_base.base_quantity;
end
$$;
comment on function purchasing.receipt_stock_quantity(uuid, uuid, numeric, uuid, numeric) is
  'Interna: cuánto entra al stock en la unidad de uso de la materia prima (envases × unidades × contenido; por peso, los kilos si se pesaron; sin producto, la cantidad en su unidad). Error claro si no se puede convertir.';
revoke execute on function purchasing.receipt_stock_quantity(uuid, uuid, numeric, uuid, numeric) from public;

-- p_lines: una decisión por cada renglón pendiente de la OC
--   {purchase_order_line_id, ok, issue, received_quantity, received_weight, lot_code, note, photo_paths}
-- y lo que llegó sin estar en la OC
--   {name, received_quantity, received_weight, lot_code, note, photo_paths}.
-- Un renglón OK recibe lo pendiente; uno observado dice cuánto llegó (0 si faltó o lo devolvió).
create function purchasing.close_receipt(p_id uuid, p_paper_kind purchasing.paper_kind, p_paper_number text,
                                         p_lines jsonb, p_cash_paid_amount numeric, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r            purchasing.receipts;
  v_o            purchasing.purchase_orders;
  v_s            catalog.suppliers;
  v_line         jsonb;
  v_pol          purchasing.purchase_order_lines;
  v_product      catalog.purchase_products;
  v_order        integer := 0;
  v_ok           boolean;
  v_issue        purchasing.receipt_issue;
  v_qty          numeric;
  v_weight       numeric;
  v_pending      numeric;
  v_ingredient   uuid;
  v_product_id   uuid;
  v_unit         uuid;
  v_unmapped     uuid;
  v_line_id      uuid;
  v_path         text;
  v_observed     integer := 0;
  v_new_unmapped integer := 0;
  v_seen         uuid[] := '{}';
  v_missing      integer;
  v_result       purchasing.receipt_result;
  v_reason       text;
  v_now          timestamptz := now();
  v_title        text;
  v_body         text;
  v_constraint   text;
  v_message      text;
begin
  select * into v_r from purchasing.receipts where id = p_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.receive', v_r.restaurant_id) then
    return core.deny('purchasing.close_receipt', 'No tenés permiso para cerrar esta recepción.', null,
                     jsonb_build_object('receipt_id', p_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  select * into v_r from purchasing.receipts where id = p_id for update;
  if v_r.status <> 'open' then
    raise exception 'Esta recepción ya se cerró.' using errcode = '23514';
  end if;
  if p_paper_kind is null then
    raise exception 'Elegí qué papel trajo el proveedor.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.attachments
                  where source_table = 'receipts' and source_id = v_r.id and doc_kind = 'receipt_original') then
    raise exception 'Falta la foto 1: el remito o la factura como llegó.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.attachments
                  where source_table = 'receipts' and source_id = v_r.id and doc_kind = 'receipt_signed') then
    raise exception 'Falta la foto 2: el papel firmado.' using errcode = '22023';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Faltan los renglones de la recepción.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) > 600 then
    raise exception 'Una recepción va hasta 600 renglones.' using errcode = '22023';
  end if;
  if p_cash_paid_amount is not null and (p_cash_paid_amount = 'NaN'::numeric or p_cash_paid_amount <= 0) then
    raise exception 'El importe en efectivo tiene que ser mayor que cero.' using errcode = '22023';
  end if;
  select * into v_s from catalog.suppliers where id = v_r.supplier_id;
  if v_r.purchase_order_id is not null then
    select * into v_o from purchasing.purchase_orders where id = v_r.purchase_order_id for update;
    if v_o.status not in ('sent', 'with_news', 'partially_received') then
      raise exception 'Esta orden ya no está para recibir.' using errcode = '23514';
    end if;
  end if;
  -- El contexto va antes de escribir; el motivo, si hubo observaciones, se controla al final.
  v_reason := nullif(btrim(p_reason), '');
  perform core.set_change_context(coalesce(left(v_reason, 500),
                                           case when v_o.id is not null then format('Recepción de la orden %s', v_o.number)
                                                else format('Recepción sin OC de %s', coalesce(v_s.trade_name, v_s.name)) end),
                                  'manual');

  for v_line in select value from jsonb_array_elements(p_lines) loop
    perform org.check_keys(v_line, array['purchase_order_line_id', 'name', 'ok', 'issue', 'received_quantity',
                                         'received_weight', 'lot_code', 'note', 'photo_paths']);
    v_order := v_order + 1;
    v_weight := (v_line ->> 'received_weight')::numeric;
    if v_weight is not null and (v_weight = 'NaN'::numeric or v_weight <= 0) then
      raise exception 'El peso del renglón % tiene que ser mayor que cero.', v_order using errcode = '22023';
    end if;
    v_ingredient := null; v_product_id := null; v_unit := null; v_unmapped := null;

    if v_line ? 'purchase_order_line_id' then
      -- Un renglón de la OC.
      if v_o.id is null then
        raise exception 'Esta recepción no tiene OC: cargá lo que llegó como «Llegó algo que no estaba».' using errcode = '22023';
      end if;
      select * into v_pol from purchasing.purchase_order_lines
       where id = (v_line ->> 'purchase_order_line_id')::uuid and purchase_order_id = v_o.id and deleted_at is null
         for update;
      if v_pol.id is null then
        raise exception 'El renglón % no es de esta orden.', v_order using errcode = '22023';
      end if;
      if v_pol.id = any (v_seen) then
        raise exception 'El renglón % está repetido.', v_order using errcode = '22023';
      end if;
      v_seen := v_seen || v_pol.id;
      v_pending := v_pol.quantity - v_pol.received_quantity;
      if v_pending <= 0 then
        raise exception 'El renglón % ya se recibió entero.', v_order using errcode = '23514';
      end if;
      v_ok := coalesce((v_line ->> 'ok')::boolean, false);
      if v_ok then
        if v_line ? 'issue' then
          raise exception 'El renglón % está OK: no lleva observación.', v_order using errcode = '22023';
        end if;
        v_issue := null;
        v_qty := v_pending;
      else
        v_issue := (v_line ->> 'issue')::purchasing.receipt_issue;
        if v_issue is null then
          raise exception 'Elegí qué pasó con el renglón %.', v_order using errcode = '22023';
        end if;
        v_qty := (v_line ->> 'received_quantity')::numeric;
        if v_qty is null or v_qty = 'NaN'::numeric or v_qty < 0 then
          raise exception 'Escribí cuánto llegó del renglón % (0 si no llegó).', v_order using errcode = '22023';
        end if;
        if v_issue = 'missing' and v_qty >= v_pending then
          raise exception 'En el renglón % marcaste que faltó: lo recibido tiene que ser menos que lo pedido.', v_order
            using errcode = '22023';
        end if;
        if v_issue = 'extra' and v_qty <= v_pending then
          raise exception 'En el renglón % marcaste que vino de más: lo recibido tiene que ser más que lo pedido.', v_order
            using errcode = '22023';
        end if;
        if v_issue = 'different_product' and v_qty <> 0 then
          raise exception 'En el renglón % mandaron otro producto: lo pedido no llegó (0). Cargá lo que vino como «Llegó algo que no estaba».',
            v_order using errcode = '22023';
        end if;
        v_observed := v_observed + 1;
      end if;
      if v_pol.purchase_product_id is not null then
        select * into v_product from catalog.purchase_products where id = v_pol.purchase_product_id;
        v_product_id := v_product.id;
        v_ingredient := v_product.ingredient_id;
      else
        v_ingredient := v_pol.ingredient_id;
        v_unit := v_pol.unit_id;
      end if;
      update purchasing.purchase_order_lines set received_quantity = received_quantity + v_qty where id = v_pol.id;
    else
      -- Llegó algo que no estaba en la OC (o, sin OC, todo lo que llegó).
      if nullif(btrim(v_line ->> 'name'), '') is null then
        raise exception 'Escribí qué llegó en el renglón %.', v_order using errcode = '22023';
      end if;
      if v_line ? 'issue' and v_o.id is null then
        raise exception 'Sin OC no hay observaciones por renglón: anotá lo que llegó.' using errcode = '22023';
      end if;
      v_qty := (v_line ->> 'received_quantity')::numeric;
      if v_qty is null or v_qty = 'NaN'::numeric or v_qty <= 0 then
        raise exception 'Escribí cuánto llegó del renglón %.', v_order using errcode = '22023';
      end if;
      -- Con OC, algo que no estaba es una observación («de más»); sin OC, es lo recibido.
      v_ok := v_o.id is null;
      v_issue := case when v_o.id is null then null else 'extra'::purchasing.receipt_issue end;
      if not v_ok then
        v_observed := v_observed + 1;
      end if;
      v_product_id := purchasing.match_article(v_s.id, null, v_line ->> 'name');
      if v_product_id is not null then
        select * into v_product from catalog.purchase_products where id = v_product_id;
        v_ingredient := v_product.ingredient_id;
      else
        -- No se reconoce: a la cola de mapeo (o al pendiente que ya hay). No suma stock: no se sabe qué es.
        select id into v_unmapped from purchasing.unmapped_articles
         where supplier_id = v_s.id and normalized_name = purchasing.normalize_name(v_line ->> 'name')
           and status in ('pending', 'discarded') and deleted_at is null
         order by status = 'pending' desc, resolved_at desc nulls first
         limit 1;
        if v_unmapped is null then
          insert into purchasing.unmapped_articles (group_id, supplier_id, raw_name, found_in, source_id)
          values (v_r.group_id, v_s.id, btrim(v_line ->> 'name'), 'receipt', v_r.id)
          returning id into v_unmapped;
          v_new_unmapped := v_new_unmapped + 1;
        end if;
      end if;
    end if;

    insert into purchasing.receipt_lines (group_id, receipt_id, line_order, purchase_order_line_id, purchase_product_id,
                                          ingredient_id, unmapped_article_id, description, ok, issue, received_quantity,
                                          received_weight, lot_code, note)
    values (v_r.group_id, v_r.id, v_order, case when v_line ? 'purchase_order_line_id' then v_pol.id end, v_product_id,
            v_ingredient, v_unmapped, nullif(btrim(v_line ->> 'name'), ''), v_ok, v_issue, v_qty, v_weight,
            nullif(btrim(v_line ->> 'lot_code'), ''), nullif(btrim(v_line ->> 'note'), ''))
    returning id into v_line_id;

    -- La foto de un producto observado: subida a la carpeta de la recepción.
    if v_line ? 'photo_paths' then
      if jsonb_typeof(v_line -> 'photo_paths') <> 'array' or jsonb_array_length(v_line -> 'photo_paths') > 5 then
        raise exception 'Van hasta 5 fotos por renglón.' using errcode = '22023';
      end if;
      for v_path in select value from jsonb_array_elements_text(v_line -> 'photo_paths') loop
        if not exists (select 1 from purchasing.document_parts(v_path) d
                        where d.group_id = v_r.group_id and d.source_table = 'receipts' and d.source_id = v_r.id)
           or not exists (select 1 from storage.objects o
                           where o.bucket_id = 'purchasing-documents' and o.name = v_path
                             and o.owner_id = (select auth.uid())::text) then
          raise exception 'La foto del renglón % no está subida en la carpeta de esta recepción.', v_order
            using errcode = '22023';
        end if;
        insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
        values (v_r.group_id, 'receipt_lines', v_line_id, 'product_issue',
                (select count(*) + 1 from purchasing.attachments a
                  where a.source_table = 'receipt_lines' and a.source_id = v_line_id), v_path);
      end loop;
    end if;

    -- La entrada de stock (D8): lo que se recibió y se sabe qué materia prima es.
    if v_qty > 0 and v_ingredient is not null then
      insert into inventory.stock_movements (group_id, brand_id, restaurant_id, ingredient_id, purchase_product_id, kind,
                                             quantity, unit_id, packages, lot_code, occurred_at, source_table, source_id)
      values (v_r.group_id, v_r.brand_id, v_r.restaurant_id, v_ingredient, v_product_id, 'purchase_receipt',
              purchasing.receipt_stock_quantity(v_ingredient, v_product_id, v_qty, v_unit, v_weight),
              (select recipe_unit_id from catalog.ingredients where id = v_ingredient),
              case when v_product_id is not null then v_qty end, nullif(btrim(v_line ->> 'lot_code'), ''), v_now,
              'receipt_lines', v_line_id);
    end if;
  end loop;

  if v_order = 0 then
    raise exception 'La recepción no tiene renglones.' using errcode = '22023';
  end if;
  if v_o.id is not null then
    -- Cada renglón pendiente de la OC lleva su decisión.
    select count(*) into v_missing from purchasing.purchase_order_lines l
     where l.purchase_order_id = v_o.id and l.deleted_at is null and not (l.id = any (v_seen))
       and l.received_quantity < l.quantity;
    if v_missing = 1 then
      raise exception 'Falta decidir 1 renglón de la orden: marcá OK u Observar.' using errcode = '22023';
    elsif v_missing > 1 then
      raise exception 'Faltan decidir % renglones de la orden: marcá OK u Observar en cada uno.', v_missing
        using errcode = '22023';
    end if;
  end if;
  if v_observed > 0 and (v_reason is null or length(v_reason) < 3) then
    raise exception 'Hubo observaciones: escribí el motivo.' using errcode = '22023';
  end if;

  if v_o.id is not null then
    v_result := case
      when exists (select 1 from purchasing.purchase_order_lines l
                    where l.purchase_order_id = v_o.id and l.deleted_at is null and l.received_quantity < l.quantity)
        then 'partial'
      when v_observed > 0 then 'with_differences'
      else 'complete' end;
    update purchasing.purchase_orders
       set status = case when v_result = 'partial' then 'partially_received'::purchasing.po_status
                         else 'received'::purchasing.po_status end
     where id = v_o.id;
  else
    v_result := 'complete';
  end if;
  update purchasing.receipts
     set status = 'closed', closed_at = v_now, result = v_result, paper_kind = p_paper_kind,
         paper_number = nullif(btrim(p_paper_number), ''), cash_paid_amount = p_cash_paid_amount
   where id = v_r.id;

  -- Avisos: a quien pidió, siempre; a Compras, si hubo observaciones o efectivo; al chef, si hay artículos nuevos.
  if v_o.id is not null then
    v_title := case v_result
                 when 'complete' then format('Llegó la orden %s', v_o.number)
                 when 'partial' then format('Llegó parte de la orden %s', v_o.number)
                 else format('Llegó la orden %s, con observaciones', v_o.number) end;
    v_body := case v_result
                when 'complete' then 'Se recibió todo bien.'
                when 'partial' then 'Quedaron renglones pendientes: se pueden recibir cuando lleguen.'
                else format('Se recibió con %s %s.', v_observed,
                            case when v_observed = 1 then 'observación' else 'observaciones' end) end;
    if v_o.requested_by is distinct from core.current_actor_id() then
      insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
      values (v_o.requested_by, v_o.group_id, 'receipt_report', left(v_title, 200), left(v_body, 500),
              format('/compras/ordenes/%s?seccion=recepcion', v_o.id));
    end if;
  end if;
  if v_observed > 0 or p_cash_paid_amount is not null then
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u, v_r.group_id, 'receipt_differences',
           left(case when v_o.id is not null then format('Recepción de la orden %s para revisar', v_o.number)
                     else format('Recepción sin OC de «%s» para revisar', coalesce(v_s.trade_name, v_s.name)) end, 200),
           left(concat_ws(' ',
                  case when v_observed = 1 then 'Tuvo 1 observación.'
                       when v_observed > 1 then format('Tuvo %s observaciones.', v_observed) end,
                  case when p_cash_paid_amount is not null
                       then 'Se pagó en efectivo: confirmá el importe.' end), 500),
           case when v_o.id is not null then format('/compras/ordenes/%s?seccion=recepcion', v_o.id) else '/compras/recepcion' end
      from purchasing.users_with_permission(v_r.group_id, 'purchasing.approve_orders') u;
  end if;
  if v_new_unmapped > 0 then
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u, v_r.group_id, 'unmapped_article',
           left(case when v_new_unmapped = 1
                     then format('Un artículo nuevo de «%s» para mapear', coalesce(v_s.trade_name, v_s.name))
                     else format('%s artículos nuevos de «%s» para mapear', v_new_unmapped, coalesce(v_s.trade_name, v_s.name))
                end, 200),
           'Llegaron en una recepción y el sistema no los reconoce. Decí a qué materia prima corresponde cada uno.',
           '/materias-primas/sin-mapear'
      from purchasing.users_who_map(v_r.group_id) u;
  end if;

  return jsonb_build_object('result', 'applied', 'receipt_result', v_result, 'observed', v_observed,
                            'order_status', (select status from purchasing.purchase_orders where id = v_o.id),
                            'requester_name', case when v_o.id is not null then core.display_name(v_o.requested_by) end,
                            'new_unmapped', v_new_unmapped);
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_receipt_error(sqlstate, v_constraint, v_message);
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los renglones: las cantidades y el peso van con números, y la observación con una de las opciones.'
      using errcode = '22023';
end
$$;
comment on function purchasing.close_receipt(uuid, purchasing.paper_kind, text, jsonb, numeric, text) is
  'Cierra una recepción en una transacción: exige las fotos 1 y 2, la clase de papel y una decisión por cada renglón pendiente de la OC (y el motivo si hubo observaciones); suma lo recibido a la OC (recibida o recibida parcial), registra las entradas de stock en la unidad de uso, manda a la cola de mapeo lo que no se reconoce y avisa a quien pidió, a Compras (observaciones o efectivo) y al chef (artículos nuevos). Pide purchasing.receive en el local.';
revoke execute on function purchasing.close_receipt(uuid, purchasing.paper_kind, text, jsonb, numeric, text) from public;
grant execute on function purchasing.close_receipt(uuid, purchasing.paper_kind, text, jsonb, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Lectura
-- ---------------------------------------------------------------------------
-- «¿Qué llegó?»: las OC para recibir de un local (enviadas, con novedad o recibidas parcial), con lo pendiente y la
-- recepción abierta si la hay. Las de entrega esperada hoy (o antes), primero.
create function purchasing.receivable_orders(p_restaurant_id uuid)
returns table (id uuid, number text, supplier_id uuid, supplier_name text, expected_delivery_on date,
               status purchasing.po_status, pending_lines bigint, open_receipt_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select o.id, o.number, o.supplier_id, coalesce(s.trade_name, s.name), o.expected_delivery_on, o.status,
         (select count(*) from purchasing.purchase_order_lines l
           where l.purchase_order_id = o.id and l.deleted_at is null and l.received_quantity < l.quantity),
         (select r.id from purchasing.receipts r
           where r.purchase_order_id = o.id and r.status = 'open' and r.deleted_at is null)
    from purchasing.purchase_orders o
    join catalog.suppliers s on s.id = o.supplier_id
   where o.restaurant_id = p_restaurant_id and o.deleted_at is null
     and o.status in ('sent', 'with_news', 'partially_received')
     and purchasing.can_in_restaurant('purchasing.receive', p_restaurant_id)
     and purchasing.can_in_restaurant('purchasing.view_orders', p_restaurant_id)
   order by o.expected_delivery_on > recipes.today(), coalesce(s.trade_name, s.name), o.expected_delivery_on, o.number
   limit 100
$$;
comment on function purchasing.receivable_orders(uuid) is
  'Las órdenes de compra para recibir en un local (enviadas, con novedad o recibidas parcial), con cuántos renglones faltan y la recepción abierta si la hay; primero las de entrega esperada hasta hoy, por proveedor. Vacío si la sesión no recibe en ese local.';
revoke execute on function purchasing.receivable_orders(uuid) from public;
grant execute on function purchasing.receivable_orders(uuid) to authenticated;

-- Una recepción entera: cabecera, fotos (la última de cada foto y página), renglones (los decididos o, si está abierta,
-- los pendientes de la OC) y el efectivo solo para quien ve precios en el local.
create function purchasing.receipt_detail(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r     purchasing.receipts;
  v_o     purchasing.purchase_orders;
  v_cash  boolean;
  v_lines jsonb;
begin
  select * into v_r from purchasing.receipts where id = p_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.view_orders', v_r.restaurant_id) then
    return null;
  end if;
  select * into v_o from purchasing.purchase_orders where id = v_r.purchase_order_id;
  v_cash := core.has_permission('prices.view', v_r.restaurant_id);
  if v_r.status = 'closed' then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', l.id, 'line_order', l.line_order, 'purchase_order_line_id', l.purchase_order_line_id,
             'name', coalesce(p.description, i.name, l.description), 'description', l.description,
             'package_name', pu.name, 'unit_name', u.name,
             'ordered', pol.quantity, 'received', l.received_quantity, 'weight', l.received_weight,
             'ok', l.ok, 'issue', l.issue, 'lot_code', l.lot_code, 'note', l.note,
             'unmapped', l.unmapped_article_id is not null,
             'photos', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'path', a.storage_path, 'page', a.page)
                                                  order by a.page), '[]'::jsonb)
                          from purchasing.attachments a where a.source_table = 'receipt_lines' and a.source_id = l.id))
             order by l.line_order), '[]'::jsonb)
      into v_lines
      from purchasing.receipt_lines l
      left join purchasing.purchase_order_lines pol on pol.id = l.purchase_order_line_id
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join catalog.units pu on pu.id = p.package_unit_id
      left join catalog.ingredients i on i.id = coalesce(l.ingredient_id, pol.ingredient_id)
      left join catalog.units u on u.id = pol.unit_id
     where l.receipt_id = v_r.id and l.deleted_at is null;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'purchase_order_line_id', l.id, 'line_order', l.line_order,
             'name', coalesce(p.description, i.name), 'package_name', pu.name, 'unit_name', u.name,
             'ordered', l.quantity, 'already_received', l.received_quantity,
             'pending', l.quantity - l.received_quantity,
             'billed_by_weight', coalesce(p.billed_by_weight, false),
             'estimated_kg', case when p.billed_by_weight and p.estimated_weight_per_unit is not null then
                               round((l.quantity - l.received_quantity) * p.units_per_package
                                     * p.estimated_weight_per_unit / case when cu.code = 'g' then 1000 else 1 end, 1) end,
             'without_invoice_name', l.ingredient_id is not null, 'note', l.line_note)
             order by l.line_order), '[]'::jsonb)
      into v_lines
      from purchasing.purchase_order_lines l
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join catalog.units pu on pu.id = p.package_unit_id
      left join catalog.units cu on cu.id = p.content_unit_id
      left join catalog.ingredients i on i.id = l.ingredient_id
      left join catalog.units u on u.id = l.unit_id
     where l.purchase_order_id = v_r.purchase_order_id and l.deleted_at is null
       and l.received_quantity < l.quantity;
  end if;
  return jsonb_build_object(
    'id', v_r.id, 'status', v_r.status, 'result', v_r.result,
    'restaurant_id', v_r.restaurant_id, 'restaurant_name', (select name from org.restaurants where id = v_r.restaurant_id),
    'supplier_id', v_r.supplier_id,
    'supplier_name', (select coalesce(s.trade_name, s.name) from catalog.suppliers s where s.id = v_r.supplier_id),
    'purchase_order_id', v_r.purchase_order_id, 'order_number', v_o.number,
    'requested_by_name', case when v_o.id is not null then core.display_name(v_o.requested_by) end,
    'received_by_name', core.display_name(v_r.received_by), 'mine', v_r.received_by = core.current_actor_id(),
    'started_at', v_r.created_at, 'closed_at', v_r.closed_at,
    'paper_kind', v_r.paper_kind, 'paper_number', v_r.paper_number,
    'can_see_cash', v_cash, 'cash_paid', v_r.cash_paid_amount is not null,
    'cash_paid_amount', case when v_cash then v_r.cash_paid_amount end,
    'can_receive', v_r.status = 'open' and purchasing.can_in_restaurant('purchasing.receive', v_r.restaurant_id),
    'photos', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.doc_kind, 'page', x.page,
                                                            'path', x.storage_path) order by x.doc_kind, x.page), '[]'::jsonb)
                 from (select distinct on (a.doc_kind, a.page) a.id, a.doc_kind, a.page, a.storage_path
                         from purchasing.attachments a
                        where a.source_table = 'receipts' and a.source_id = v_r.id
                        order by a.doc_kind, a.page, a.created_at desc, a.id) x),
    'lines', v_lines);
end
$$;
comment on function purchasing.receipt_detail(uuid) is
  'Una recepción entera (si la sesión ve las OC del local): cabecera, fotos (la última de cada foto y página), renglones (los decididos, o los pendientes de la OC si está abierta) y el efectivo solo para quien ve precios en el local. Vacío si no la ve.';
revoke execute on function purchasing.receipt_detail(uuid) from public;
grant execute on function purchasing.receipt_detail(uuid) to authenticated;

-- Las recepciones de una OC (para el informe en su ficha), la última primero.
create function purchasing.order_receipts(p_order_id uuid)
returns table (id uuid, status purchasing.receipt_status, result purchasing.receipt_result, closed_at timestamptz,
               received_by_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.status, r.result, r.closed_at, core.display_name(r.received_by)
    from purchasing.receipts r
   where r.purchase_order_id = p_order_id and r.deleted_at is null
     and purchasing.can_in_restaurant('purchasing.view_orders', r.restaurant_id)
   order by r.status = 'open' desc, r.closed_at desc nulls first, r.id
$$;
comment on function purchasing.order_receipts(uuid) is
  'Las recepciones de una orden de compra (la abierta y las cerradas, la última primero), con quién recibió. Solo las de locales cuyas OC ve la sesión.';
revoke execute on function purchasing.order_receipts(uuid) from public;
grant execute on function purchasing.order_receipts(uuid) to authenticated;

-- Los proveedores para «Recibir sin OC»: activos del grupo del local.
create function purchasing.receivable_suppliers(p_restaurant_id uuid)
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, coalesce(s.trade_name, s.name)
    from catalog.suppliers s
    join org.restaurants r on r.id = p_restaurant_id and r.group_id = s.group_id
   where s.is_active and s.deleted_at is null
     and purchasing.can_in_restaurant('purchasing.receive', p_restaurant_id)
   order by coalesce(s.trade_name, s.name)
   limit 500
$$;
comment on function purchasing.receivable_suppliers(uuid) is
  'Los proveedores activos del grupo del local, para «Recibir sin OC». Vacío si la sesión no recibe en ese local.';
revoke execute on function purchasing.receivable_suppliers(uuid) from public;
grant execute on function purchasing.receivable_suppliers(uuid) to authenticated;

-- Inventario: los movimientos de stock que la sesión ve, con filtros por local, materia prima, fechas y lote.
create function inventory.movement_list(p_restaurant_id uuid default null, p_ingredient_id uuid default null,
                                        p_from date default null, p_to date default null, p_lot text default null,
                                        p_limit integer default 15, p_offset integer default 0)
returns table (id uuid, occurred_at timestamptz, restaurant_id uuid, restaurant_name text, ingredient_id uuid,
               ingredient_name text, product_name text, kind inventory.movement_kind, quantity numeric,
               unit_name text, packages numeric, package_name text, lot_code text, supplier_name text,
               purchase_order_id uuid, order_number text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  with q as (select replace(replace(replace(lower(btrim(p_lot)), '\', '\\'), '%', '\%'), '_', '\_') as lot)
  select m.id, m.occurred_at, m.restaurant_id, r.name, m.ingredient_id, i.name, p.description, m.kind, m.quantity,
         u.name, m.packages, pu.name, m.lot_code, coalesce(s.trade_name, s.name), o.id, o.number,
         count(*) over ()
    from q, inventory.stock_movements m
    join org.restaurants r on r.id = m.restaurant_id
    join catalog.ingredients i on i.id = m.ingredient_id
    join catalog.units u on u.id = m.unit_id
    left join catalog.purchase_products p on p.id = m.purchase_product_id
    left join catalog.units pu on pu.id = p.package_unit_id
    left join purchasing.receipt_lines l on m.source_table = 'receipt_lines' and l.id = m.source_id
    left join purchasing.receipts rc on rc.id = l.receipt_id
    left join catalog.suppliers s on s.id = rc.supplier_id
    left join purchasing.purchase_orders o on o.id = rc.purchase_order_id
   where (p_restaurant_id is null or m.restaurant_id = p_restaurant_id)
     and (p_ingredient_id is null or m.ingredient_id = p_ingredient_id)
     and (p_from is null or m.occurred_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires'))
     and (p_to is null or m.occurred_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'))
     and (q.lot is null or q.lot = '' or lower(m.lot_code) like '%' || q.lot || '%')
   order by m.occurred_at desc, m.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function inventory.movement_list(uuid, uuid, date, date, text, integer, integer) is
  'Movimientos de stock, los más nuevos primero, con los permisos de quien consulta (inventory.view en el local): materia prima, producto, cantidad en la unidad de uso, envases, lote, proveedor y OC de origen. Filtra por local, materia prima, fechas y lote (contiene), y pagina.';
revoke execute on function inventory.movement_list(uuid, uuid, date, date, text, integer, integer) from public;
grant execute on function inventory.movement_list(uuid, uuid, date, date, text, integer, integer) to authenticated;
