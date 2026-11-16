-- Fase 3, Prompt 3 (ADR-0053): orden de compra con numeración por local, aprobación opcional, envío en cola y
-- novedades.
--
-- - La OC se numera por local (código del local + «-» + 4 cifras, «PCE-0001») con su propio contador en
--   catalog.code_series (prefijo «OC-<código>-»): correlativa, sin saltos ni repetidos aunque dos personas pidan a la vez,
--   y sin compartir contador con recetas ni materias primas. Un local sin código no puede pedir (P3).
-- - «Mandar OC»: si el proveedor lo requiere, pasa por una aprobación (purchasing.approve_order) que da Compras en el
--   alcance del local, nunca quien la pidió (decisión 3 de Soy). Si no, se encola directo.
-- - El mensaje queda en purchasing.outbound_messages; nadie lo despacha todavía (decisión 9 de Soy).
-- - Sin precios: hoy no se cargan. unit_price y price_list_item_id quedan preparados y vacíos.

-- ---------------------------------------------------------------------------
-- 1. Permisos
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de órdenes de compra (Fase 3, ADR-0053)', 'maintenance');
  insert into core.permissions (code, module, action, name, sort_order, description, is_sensitive) values
    ('purchasing.view_orders', 'purchasing', 'view_orders', 'Ver órdenes de compra', 60,
     'Ver las órdenes de compra de los locales que ve, con sus líneas, su estado, el mensaje al proveedor y las novedades. Sin precios.',
     false),
    ('purchasing.create_orders', 'purchasing', 'create_orders', 'Hacer órdenes de compra', 70,
     'Armar una orden de compra para su local y mandarla (o enviarla a aprobación, si el proveedor lo requiere).', false),
    ('purchasing.approve_orders', 'purchasing', 'approve_orders', 'Aprobar órdenes de compra', 80,
     'Aprobar o rechazar las órdenes de compra a proveedores que requieren aprobación. Nunca la propia.', true),
    ('purchasing.record_order_news', 'purchasing', 'record_order_news', 'Registrar novedades de una orden de compra', 90,
     'Anotar una novedad en una orden de compra enviada (falta, cambio de entrega, nota). Avisa a quien la pidió.',
     false);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values
      ('cook', 'purchasing.view_orders'), ('cook', 'purchasing.create_orders'),
      ('head_chef', 'purchasing.view_orders'), ('head_chef', 'purchasing.create_orders'),
      ('executive_chef', 'purchasing.view_orders'), ('executive_chef', 'purchasing.create_orders'),
      ('restaurant_manager', 'purchasing.view_orders'), ('restaurant_manager', 'purchasing.create_orders'),
      ('restaurant_manager', 'purchasing.record_order_news'),
      ('purchasing', 'purchasing.view_orders'), ('purchasing', 'purchasing.create_orders'),
      ('purchasing', 'purchasing.approve_orders'), ('purchasing', 'purchasing.record_order_news'),
      ('controller', 'purchasing.view_orders'),
      ('general_management', 'purchasing.view_orders'),
      ('auditor', 'purchasing.view_orders'),
      -- Regla G2: quien administra personas tiene los permisos de los roles que administra. El Director de Marca
      -- administra a los chefs y al Gerente; el superadmin, a Compras, al Gerente, al Jefe de Cocina y al cocinero.
      ('brand_director', 'purchasing.view_orders'), ('brand_director', 'purchasing.create_orders'),
      ('brand_director', 'purchasing.record_order_news'),
      ('superadmin', 'purchasing.view_orders'), ('superadmin', 'purchasing.create_orders'),
      ('superadmin', 'purchasing.approve_orders'), ('superadmin', 'purchasing.record_order_news')
    ) as v (role_code, permission_code)
    join core.roles r on r.code = v.role_code and r.deleted_at is null
    join core.permissions p on p.code = v.permission_code and p.deleted_at is null;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Tipos
-- ---------------------------------------------------------------------------
create type purchasing.po_status as enum ('draft', 'pending_approval', 'sent', 'with_news', 'partially_received',
                                          'received', 'closed', 'cancelled');
comment on type purchasing.po_status is
  'Estado de una orden de compra: draft (borrador), pending_approval (espera la aprobación de Compras), sent (en cola de envío o enviada), with_news (con una novedad), partially_received y received (con la recepción, Prompt 4), closed (facturada, Prompt 5) o cancelled.';
create type purchasing.po_event_kind as enum ('news', 'shortage', 'delivery_change', 'note', 'cancelled');
comment on type purchasing.po_event_kind is
  'Tipo de novedad de una orden de compra: news (novedad), shortage (falta mercadería), delivery_change (cambia la entrega), note (nota) o cancelled (se canceló).';
create type purchasing.message_status as enum ('queued', 'sent', 'failed', 'cancelled');
comment on type purchasing.message_status is
  'Estado de un mensaje saliente: queued (en cola de envío), sent (enviado), failed (falló) o cancelled (cancelado). Hoy nadie los despacha: quedan en cola (decisión 9 de Soy).';

-- ---------------------------------------------------------------------------
-- 3. Tablas
-- ---------------------------------------------------------------------------
create table purchasing.purchase_orders (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references org.groups (id) on delete restrict,
  brand_id              uuid not null,
  restaurant_id         uuid not null,
  supplier_id           uuid not null,
  number                text not null check (number ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  status                purchasing.po_status not null default 'draft',
  requested_by          uuid not null references core.actors (id) on delete restrict,
  expected_delivery_on  date not null,
  sent_at               timestamptz,
  sent_channel          purchasing.channel,
  notes                 text check (notes is null or length(notes) <= 1000),
  approval_request_id   uuid references workflow.approval_requests (id) on delete restrict,
  created_at            timestamptz not null default now(),
  created_by            uuid references core.actors (id) on delete restrict,
  updated_at            timestamptz not null default now(),
  updated_by            uuid references core.actors (id) on delete restrict,
  deleted_at            timestamptz,
  deleted_by            uuid references core.actors (id) on delete restrict,
  constraint purchase_orders_id_group_key unique (id, group_id),
  constraint purchase_orders_restaurant_fkey foreign key (restaurant_id, brand_id)
    references org.restaurants (id, brand_id) on delete restrict,
  constraint purchase_orders_restaurant_group_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint purchase_orders_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint purchase_orders_sent_check check ((sent_at is null) = (sent_channel is null))
);
create unique index purchase_orders_number_key on purchasing.purchase_orders (group_id, number);
create index purchase_orders_restaurant_idx on purchasing.purchase_orders (restaurant_id, status, created_at desc)
  where deleted_at is null;
create index purchase_orders_restaurant_group_idx on purchasing.purchase_orders (restaurant_id, group_id);
create index purchase_orders_restaurant_brand_idx on purchasing.purchase_orders (restaurant_id, brand_id);
create index purchase_orders_supplier_idx on purchasing.purchase_orders (supplier_id, group_id);
create index purchase_orders_group_idx on purchasing.purchase_orders (group_id, status, created_at desc)
  where deleted_at is null;
create index purchase_orders_requested_by_idx on purchasing.purchase_orders (requested_by);
create index purchase_orders_request_idx on purchasing.purchase_orders (approval_request_id)
  where approval_request_id is not null;
comment on table purchasing.purchase_orders is
  'Órdenes de compra: lo que un local le pide a un proveedor. Numeradas por local («PCE-0001»), con aprobación de Compras si el proveedor la requiere y el mensaje en cola de envío. Sin precios.';
comment on column purchasing.purchase_orders.group_id is 'Grupo, el mismo que el del local y el del proveedor.';
comment on column purchasing.purchase_orders.brand_id is 'Marca del local (para el alcance de la aprobación).';
comment on column purchasing.purchase_orders.restaurant_id is 'Local que pide.';
comment on column purchasing.purchase_orders.supplier_id is 'Proveedor.';
comment on column purchasing.purchase_orders.number is
  'Número de la OC: código del local + «-» + 4 cifras, correlativo por local, sin saltos ni repetidos. Si después cambia el código del local, la OC conserva el suyo.';
comment on column purchasing.purchase_orders.status is 'Estado de la orden.';
comment on column purchasing.purchase_orders.requested_by is 'Quién la pidió (no la puede aprobar).';
comment on column purchasing.purchase_orders.expected_delivery_on is
  'Cuándo se espera la entrega: el próximo día de entrega del proveedor después del pedido, salvo que se cambie con motivo.';
comment on column purchasing.purchase_orders.sent_at is 'Cuándo se puso en la cola de envío.';
comment on column purchasing.purchase_orders.sent_channel is 'Por qué canal se manda (el de la ficha del proveedor).';
comment on column purchasing.purchase_orders.notes is 'Observaciones para el proveedor.';
comment on column purchasing.purchase_orders.approval_request_id is 'La solicitud de aprobación, si el proveedor la requiere.';

create table purchasing.purchase_order_lines (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  purchase_order_id    uuid not null,
  line_order           integer not null check (line_order between 1 and 500),
  purchase_product_id  uuid,
  ingredient_id        uuid,
  unit_id              uuid references catalog.units (id) on delete restrict,
  quantity             numeric(14,4) not null check (quantity > 0),
  received_quantity    numeric(14,4) not null default 0 check (received_quantity >= 0),
  line_note            text check (line_note is null or length(btrim(line_note)) between 1 and 300),
  unit_price           numeric(14,4) check (unit_price is null or unit_price >= 0),
  price_list_item_id   uuid,
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict,
  constraint purchase_order_lines_order_fkey foreign key (purchase_order_id, group_id)
    references purchasing.purchase_orders (id, group_id) on delete restrict,
  constraint purchase_order_lines_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict,
  constraint purchase_order_lines_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint purchase_order_lines_price_item_fkey foreign key (price_list_item_id)
    references purchasing.price_list_items (id) on delete restrict,
  constraint purchase_order_lines_target_check check (num_nonnulls(purchase_product_id, ingredient_id) = 1),
  constraint purchase_order_lines_unit_check check ((ingredient_id is null) = (unit_id is null))
);
create unique index purchase_order_lines_order_key on purchasing.purchase_order_lines (purchase_order_id, line_order)
  where deleted_at is null;
create index purchase_order_lines_order_idx on purchasing.purchase_order_lines (purchase_order_id, group_id);
create index purchase_order_lines_product_idx on purchasing.purchase_order_lines (purchase_product_id, group_id)
  where purchase_product_id is not null;
create index purchase_order_lines_ingredient_idx on purchasing.purchase_order_lines (ingredient_id, group_id)
  where ingredient_id is not null;
create index purchase_order_lines_unit_idx on purchasing.purchase_order_lines (unit_id) where unit_id is not null;
create index purchase_order_lines_price_item_idx on purchasing.purchase_order_lines (price_list_item_id)
  where price_list_item_id is not null;
create index purchase_order_lines_group_idx on purchasing.purchase_order_lines (group_id);
comment on table purchasing.purchase_order_lines is
  'Líneas de una orden de compra: un artículo del proveedor (en la unidad de su envase) o, si el proveedor no lo tiene como artículo, una materia prima «sin nombre de factura» (en su unidad de uso; al facturarla, entra a la cola de mapeo).';
comment on column purchasing.purchase_order_lines.group_id is 'Grupo, el mismo que el de la orden.';
comment on column purchasing.purchase_order_lines.purchase_order_id is 'Orden a la que pertenece.';
comment on column purchasing.purchase_order_lines.line_order is 'Orden de la línea.';
comment on column purchasing.purchase_order_lines.purchase_product_id is
  'Artículo del proveedor (producto de compra del mismo proveedor; lo controla purchasing.save_order_draft, el único camino de escritura).';
comment on column purchasing.purchase_order_lines.ingredient_id is
  'Materia prima pedida «sin nombre de factura», si el proveedor no la tiene como artículo.';
comment on column purchasing.purchase_order_lines.unit_id is 'Unidad de la cantidad, solo en una materia prima sin nombre de factura.';
comment on column purchasing.purchase_order_lines.quantity is
  'Cantidad pedida: envases del artículo, o la cantidad de la materia prima en su unidad.';
comment on column purchasing.purchase_order_lines.received_quantity is 'Cantidad recibida (0 hasta la recepción, Prompt 4).';
comment on column purchasing.purchase_order_lines.line_note is 'Nota de la línea para el proveedor.';
comment on column purchasing.purchase_order_lines.unit_price is 'Precio por envase. Vacío: hoy no se carga (preparado, pedido de Soy).';
comment on column purchasing.purchase_order_lines.price_list_item_id is
  'Renglón de la lista de precios de donde saldría el precio. Vacío: hoy no se usa (preparado).';

create table purchasing.purchase_order_events (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null references org.groups (id) on delete restrict,
  purchase_order_id  uuid not null,
  kind               purchasing.po_event_kind not null,
  message            text not null check (length(btrim(message)) between 1 and 1000),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint purchase_order_events_order_fkey foreign key (purchase_order_id, group_id)
    references purchasing.purchase_orders (id, group_id) on delete restrict
);
create index purchase_order_events_order_idx on purchasing.purchase_order_events (purchase_order_id, group_id, created_at);
create index purchase_order_events_group_idx on purchasing.purchase_order_events (group_id);
comment on table purchasing.purchase_order_events is
  'Novedades de una orden de compra (falta mercadería, cambio de entrega, nota, cancelación). Una novedad avisa a quien la pidió.';
comment on column purchasing.purchase_order_events.group_id is 'Grupo, el mismo que el de la orden.';
comment on column purchasing.purchase_order_events.purchase_order_id is 'Orden.';
comment on column purchasing.purchase_order_events.kind is 'Tipo de novedad.';
comment on column purchasing.purchase_order_events.message is 'Qué pasó.';

create table purchasing.outbound_messages (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references org.groups (id) on delete restrict,
  channel       purchasing.channel not null,
  target        text not null check (length(btrim(target)) between 3 and 200),
  subject       text not null check (length(btrim(subject)) between 1 and 200),
  body          text not null check (length(body) between 1 and 8000),
  source_table  text not null check (source_table in ('purchase_orders')),
  source_id     uuid not null,
  status        purchasing.message_status not null default 'queued',
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict
);
create index outbound_messages_source_idx on purchasing.outbound_messages (source_table, source_id);
create index outbound_messages_group_idx on purchasing.outbound_messages (group_id);
create index outbound_messages_queue_idx on purchasing.outbound_messages (group_id, status, created_at)
  where deleted_at is null;
comment on table purchasing.outbound_messages is
  'Mensajes que el sistema manda a los proveedores desde la cuenta de la empresa (por ahora, las órdenes de compra). Hoy quedan en cola: nadie los despacha (decisión 9 de Soy). Nunca se mandan desde el usuario de quien pidió.';
comment on column purchasing.outbound_messages.group_id is 'Grupo.';
comment on column purchasing.outbound_messages.channel is 'Canal: WhatsApp, correo o el portal del proveedor.';
comment on column purchasing.outbound_messages.target is 'A dónde va: el número, el correo o la dirección de la ficha del proveedor.';
comment on column purchasing.outbound_messages.subject is 'Asunto.';
comment on column purchasing.outbound_messages.body is 'Texto del mensaje.';
comment on column purchasing.outbound_messages.source_table is 'Tabla del registro que lo originó (por ahora, purchase_orders).';
comment on column purchasing.outbound_messages.source_id is 'Registro que lo originó (la orden de compra).';
comment on column purchasing.outbound_messages.status is 'En cola, enviado, falló o cancelado.';

-- Control, auditoría, RLS y comentarios comunes.
do $$
declare
  t text;
begin
  foreach t in array array['purchase_orders', 'purchase_order_lines', 'purchase_order_events', 'outbound_messages'] loop
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

-- El precio de la línea se protege por columna (security.md): hoy está vacío, y cuando se cargue se definirá quién lo ve.
revoke select on purchasing.purchase_order_lines from authenticated;
grant select (id, group_id, purchase_order_id, line_order, purchase_product_id, ingredient_id, unit_id, quantity,
              received_quantity, line_note, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by)
  on purchasing.purchase_order_lines to authenticated;

-- Cada uno ve las OC de los locales que ve (el cocinero, las de su local; Compras, las de todo el grupo). Las líneas,
-- las novedades y el mensaje, las de las OC que ve.
create policy purchase_orders_select on purchasing.purchase_orders for select to authenticated
  using (deleted_at is null
         and restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_orders')));
create policy purchase_order_lines_select on purchasing.purchase_order_lines for select to authenticated
  using (deleted_at is null and purchase_order_id in (select id from purchasing.purchase_orders));
create policy purchase_order_events_select on purchasing.purchase_order_events for select to authenticated
  using (deleted_at is null and purchase_order_id in (select id from purchasing.purchase_orders));
create policy outbound_messages_select on purchasing.outbound_messages for select to authenticated
  using (deleted_at is null and source_table = 'purchase_orders'
         and source_id in (select id from purchasing.purchase_orders));

-- ---------------------------------------------------------------------------
-- 4. Reglas y mensajes claros
-- ---------------------------------------------------------------------------
create function purchasing.raise_order_error(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'purchase_order_lines_quantity_check' then 'La cantidad tiene que ser mayor que cero.'
    when p_constraint = 'purchase_order_lines_line_note_check' then 'La nota de una línea va hasta 300 caracteres.'
    when p_constraint = 'purchase_orders_notes_check' then 'Las observaciones van hasta 1000 caracteres.'
    when p_constraint = 'purchase_order_lines_order_key' then 'Hay dos líneas con el mismo orden: recargá la página.'
    when p_constraint = 'purchase_orders_number_key' then 'Ese número de OC ya existe: probá de nuevo.'
    when p_constraint = 'purchase_order_events_message_check' then 'Escribí la novedad (hasta 1000 caracteres).'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la orden.'
    else null
  end;
  if v_message is null then
    perform purchasing.raise_friendly(p_state, p_constraint, p_message);
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function purchasing.raise_order_error(text, text, text) is
  'Interna: traduce a un mensaje en español el error de una restricción de órdenes de compra (y, si no es suya, usa la de proveedores).';
revoke execute on function purchasing.raise_order_error(text, text, text) from public;

-- Si la sesión tiene un permiso en el local.
create function purchasing.can_in_restaurant(p_permission text, p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select core.has_permission_for_scope(p_permission, 'restaurant', r.group_id, r.brand_id, r.id)
                     from org.restaurants r where r.id = p_restaurant_id and r.deleted_at is null), false)
$$;
comment on function purchasing.can_in_restaurant(text, uuid) is
  'Interna: si la sesión tiene el permiso en ese local (por una asignación del local, de su marca o de todo el grupo).';
revoke execute on function purchasing.can_in_restaurant(text, uuid) from public;

-- Fecha de entrega esperada: el próximo día de entrega del proveedor después de p_from (1 = lunes … 7 = domingo). Un
-- pedido hecho el mismo día de entrega va al próximo: lo de hoy no llega hoy.
create function purchasing.expected_delivery(p_supplier_id uuid, p_from date)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_days smallint[];
  v_day  date;
begin
  if not exists (select 1 from catalog.suppliers s
                  where s.id = p_supplier_id and s.deleted_at is null
                    and s.group_id in (select core.visible_group_ids('purchasing.view_suppliers'))) then
    raise exception 'No encontramos el proveedor.' using errcode = '22023';
  end if;
  select delivery_days into v_days from purchasing.supplier_terms
   where supplier_id = p_supplier_id and deleted_at is null;
  if v_days is null or cardinality(v_days) = 0 then
    raise exception 'Cargá los días de entrega del proveedor en su ficha: sin eso no se puede calcular cuándo llega.'
      using errcode = '22023';
  end if;
  for i in 1..7 loop
    v_day := p_from + i;
    if extract(isodow from v_day)::smallint = any (v_days) then
      return v_day;
    end if;
  end loop;
  return null;
end
$$;
comment on function purchasing.expected_delivery(uuid, date) is
  'El próximo día de entrega del proveedor después de la fecha dada (un pedido del mismo día de entrega va al próximo). Error claro si el proveedor no tiene días de entrega cargados.';
revoke execute on function purchasing.expected_delivery(uuid, date) from public;
grant execute on function purchasing.expected_delivery(uuid, date) to authenticated;

-- Los artículos del proveedor, primero los que más se pidieron en ese local (OC enviadas o más adelante); a igual
-- cantidad, por nombre. Desde la historia, sin contadores guardados.
create function purchasing.supplier_product_ranking(p_supplier_id uuid, p_restaurant_id uuid)
returns table (purchase_product_id uuid, code text, description text, supplier_sku text, package_name text,
               units_per_package integer, content_per_unit numeric, content_unit text, billed_by_weight boolean,
               estimated_weight_per_unit numeric, times_ordered bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.code, p.description, p.supplier_sku, pu.name, p.units_per_package, p.content_per_unit, cu.code,
         p.billed_by_weight, p.estimated_weight_per_unit,
         (select count(distinct l.purchase_order_id)
            from purchasing.purchase_order_lines l
            join purchasing.purchase_orders o on o.id = l.purchase_order_id
           where l.purchase_product_id = p.id and l.deleted_at is null and o.deleted_at is null
             and o.restaurant_id = p_restaurant_id
             and o.status in ('sent', 'with_news', 'partially_received', 'received', 'closed')) as times_ordered
    from catalog.purchase_products p
    join catalog.units pu on pu.id = p.package_unit_id
    join catalog.units cu on cu.id = p.content_unit_id
    join org.restaurants r on r.id = p_restaurant_id and r.group_id = p.group_id
   where p.supplier_id = p_supplier_id and p.is_active and p.deleted_at is null
     and purchasing.can_in_restaurant('purchasing.create_orders', p_restaurant_id)
   order by times_ordered desc, p.description, p.id
$$;
comment on function purchasing.supplier_product_ranking(uuid, uuid) is
  'Los artículos activos de un proveedor, con su envase, ordenados por cuántas OC enviadas (o más adelante) de ese local los incluyen; a igual cantidad, por nombre. Vacío si la sesión no puede pedir en ese local.';
revoke execute on function purchasing.supplier_product_ranking(uuid, uuid) from public;
grant execute on function purchasing.supplier_product_ranking(uuid, uuid) to authenticated;

-- El próximo número de OC de un local: «PCE-0001». El contador vive en catalog.code_series con el prefijo
-- «OC-<código>-», propio de las órdenes: no comparte números con recetas ni materias primas. El update bloquea la fila
-- hasta el commit: dos pedidos a la vez no reciben el mismo número, y si la transacción falla el número vuelve.
create function purchasing.next_order_number(p_group_id uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series text := 'OC-' || p_code || '-';
  v_number integer;
begin
  loop
    update catalog.code_series set last_number = last_number + 1
     where group_id = p_group_id and prefix = v_series
    returning last_number into v_number;
    exit when v_number is not null;
    insert into catalog.code_series (group_id, prefix, last_number)
    values (p_group_id, v_series, coalesce((select max(substr(o.number, length(p_code) + 2)::integer)
                                               from purchasing.purchase_orders o
                                              where o.group_id = p_group_id
                                                and o.number ~ ('^' || p_code || '-[0-9]{1,6}$')), 0))
    on conflict (group_id, prefix) do nothing;
  end loop;
  return p_code || '-' || lpad(v_number::text, greatest(4, length(v_number::text)), '0');
end
$$;
comment on function purchasing.next_order_number(uuid, text) is
  'Interna: el próximo número de orden de compra de un local (código + «-» + 4 cifras), con un contador propio y bloqueo (sin saltos ni repetidos).';
revoke execute on function purchasing.next_order_number(uuid, text) from public;

-- ---------------------------------------------------------------------------
-- 5. Borrador
-- ---------------------------------------------------------------------------
-- p_lines: [{purchase_product_id | ingredient_id, quantity, note}]. Crea el borrador (p_order_id vacío) o reemplaza sus
-- líneas. La fecha esperada, si no viene, se calcula.
create function purchasing.save_order_draft(p_order_id uuid, p_restaurant_id uuid, p_supplier_id uuid, p_lines jsonb,
                                            p_notes text, p_expected_on date, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r          org.restaurants;
  v_s          catalog.suppliers;
  v_o          purchasing.purchase_orders;
  v_line       jsonb;
  v_order      integer := 0;
  v_product    catalog.purchase_products;
  v_ing        catalog.ingredients;
  v_expected   date;
  v_constraint text;
  v_message    text;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.create_orders', v_r.id) then
    return core.deny('purchasing.save_order_draft', 'No tenés permiso para hacer órdenes de compra en este local.', null,
                     jsonb_build_object('restaurant_id', p_restaurant_id), v_r.group_id, v_r.brand_id, v_r.id);
  end if;
  if v_r.code is null then
    raise exception 'Falta el código del local: cargalo en el Panel de control para poder numerar las órdenes de compra.'
      using errcode = '22023';
  end if;
  select * into v_s from catalog.suppliers
   where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null and is_active;
  if v_s.id is null then
    raise exception 'Elegí un proveedor activo de este grupo.' using errcode = '22023';
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'La orden no tiene líneas.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) > 500 then
    raise exception 'Una orden va hasta 500 líneas.' using errcode = '22023';
  end if;
  v_expected := coalesce(p_expected_on, purchasing.expected_delivery(v_s.id, recipes.today()));
  if v_expected < recipes.today() then
    raise exception 'La entrega esperada no puede ser antes de hoy.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');

  if p_order_id is null then
    insert into purchasing.purchase_orders (group_id, brand_id, restaurant_id, supplier_id, number, requested_by,
                                            expected_delivery_on, notes)
    values (v_r.group_id, v_r.brand_id, v_r.id, v_s.id, purchasing.next_order_number(v_r.group_id, v_r.code),
            core.current_actor_id(), v_expected, nullif(btrim(p_notes), ''))
    returning * into v_o;
  else
    select * into v_o from purchasing.purchase_orders where id = p_order_id and deleted_at is null for update;
    if v_o.id is null or v_o.restaurant_id <> v_r.id or v_o.supplier_id <> v_s.id then
      raise exception 'Esa orden no es de este local y proveedor.' using errcode = '22023';
    end if;
    if v_o.status <> 'draft' then
      raise exception 'Solo se cambia una orden en borrador.' using errcode = '23514';
    end if;
    -- Así nadie aprueba un pedido que en la práctica armó él (revisión de seguridad, M1).
    if v_o.requested_by is distinct from core.current_actor_id() then
      raise exception 'Solo quien armó el borrador lo cambia.' using errcode = '23514';
    end if;
    update purchasing.purchase_orders
       set expected_delivery_on = v_expected, notes = nullif(btrim(p_notes), '')
     where id = v_o.id;
    update purchasing.purchase_order_lines set deleted_at = now()
     where purchase_order_id = v_o.id and deleted_at is null;
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    perform org.check_keys(v_line, array['purchase_product_id', 'ingredient_id', 'quantity', 'note']);
    v_order := v_order + 1;
    if (v_line ->> 'quantity') is null or (v_line ->> 'quantity')::numeric = 'NaN'::numeric
       or (v_line ->> 'quantity')::numeric <= 0 then
      raise exception 'La cantidad de la línea % tiene que ser mayor que cero.', v_order using errcode = '22023';
    end if;
    if (v_line ? 'purchase_product_id') = (v_line ? 'ingredient_id') then
      raise exception 'Cada línea va con un artículo del proveedor o con una materia prima.' using errcode = '22023';
    end if;
    if v_line ? 'purchase_product_id' then
      select * into v_product from catalog.purchase_products
       where id = (v_line ->> 'purchase_product_id')::uuid and deleted_at is null and is_active;
      if v_product.id is null or v_product.supplier_id is distinct from v_s.id then
        raise exception 'La línea % no es un artículo activo de este proveedor.', v_order using errcode = '22023';
      end if;
      insert into purchasing.purchase_order_lines (group_id, purchase_order_id, line_order, purchase_product_id,
                                                   quantity, line_note)
      values (v_o.group_id, v_o.id, v_order, v_product.id, (v_line ->> 'quantity')::numeric,
              nullif(btrim(v_line ->> 'note'), ''));
    else
      select * into v_ing from catalog.ingredients
       where id = (v_line ->> 'ingredient_id')::uuid and group_id = v_o.group_id and deleted_at is null and is_active;
      if v_ing.id is null then
        raise exception 'La línea % no es una materia prima activa de este grupo.', v_order using errcode = '22023';
      end if;
      insert into purchasing.purchase_order_lines (group_id, purchase_order_id, line_order, ingredient_id, unit_id,
                                                   quantity, line_note)
      values (v_o.group_id, v_o.id, v_order, v_ing.id, v_ing.recipe_unit_id, (v_line ->> 'quantity')::numeric,
              nullif(btrim(v_line ->> 'note'), ''));
    end if;
  end loop;
  return jsonb_build_object('result', 'applied', 'purchase_order_id', v_o.id, 'number', v_o.number);
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_order_error(sqlstate, v_constraint, v_message);
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá las cantidades: van con números.' using errcode = '22023';
end
$$;
comment on function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text) is
  'Crea una orden de compra en borrador (con su número del local) o reemplaza sus líneas, en una transacción y con motivo. Pide purchasing.create_orders en el local, que el local tenga código y que cada artículo sea del proveedor.';
revoke execute on function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text) from public;
grant execute on function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Mensaje y envío
-- ---------------------------------------------------------------------------
-- Una cantidad sin ceros de más, con coma: 2, 1,5.
create function purchasing.qty_text(p_value numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select replace(trim(trailing '.' from trim(trailing '0' from to_char(p_value, 'FM999999990.999'))), '.', ',')
$$;
comment on function purchasing.qty_text(numeric) is 'Interna: una cantidad con coma decimal y sin ceros de más.';
revoke execute on function purchasing.qty_text(numeric) from public;

-- El texto de la OC para el proveedor: número bien visible, local, nuestro número de cliente, entrega y líneas (con los
-- kg estimados de lo que va por peso).
create function purchasing.order_message(p_order_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_o     purchasing.purchase_orders;
  v_text  text;
  v_lines text;
begin
  select * into v_o from purchasing.purchase_orders where id = p_order_id;
  select string_agg(
           case when l.purchase_product_id is not null then
             format('- %s × %s · %s%s%s', purchasing.qty_text(l.quantity), pu.name, p.description,
                    case when p.billed_by_weight and p.estimated_weight_per_unit is not null then
                      format(' (≈ %s kg)', purchasing.qty_text(round(l.quantity * p.units_per_package
                                                                     * p.estimated_weight_per_unit
                                                                     / case when cu.code = 'g' then 1000 else 1 end, 1)))
                    else '' end,
                    case when l.line_note is not null then ' — ' || l.line_note else '' end)
           else
             format('- %s %s · %s (sin nombre de factura)%s', purchasing.qty_text(l.quantity), u.name, i.name,
                    case when l.line_note is not null then ' — ' || l.line_note else '' end)
           end, E'\n' order by l.line_order)
    into v_lines
    from purchasing.purchase_order_lines l
    left join catalog.purchase_products p on p.id = l.purchase_product_id
    left join catalog.units pu on pu.id = p.package_unit_id
    left join catalog.units cu on cu.id = p.content_unit_id
    left join catalog.ingredients i on i.id = l.ingredient_id
    left join catalog.units u on u.id = l.unit_id
   where l.purchase_order_id = v_o.id and l.deleted_at is null;
  v_text := format(E'ORDEN DE COMPRA %s\nPor favor, poné este número en «Orden de compra» de la factura y el remito.\n\n',
                   v_o.number)
         || format(E'Local: %s\n', (select r.name from org.restaurants r where r.id = v_o.restaurant_id))
         || coalesce(format(E'Nuestro número de cliente: %s\n',
                            (select c.customer_number from purchasing.supplier_customer_numbers c
                              where c.supplier_id = v_o.supplier_id and c.restaurant_id = v_o.restaurant_id
                                and c.deleted_at is null)), '')
         || format(E'Entrega esperada: %s\n\n', to_char(v_o.expected_delivery_on, 'DD/MM/YYYY'))
         || coalesce(v_lines, '')
         || coalesce(E'\n\nObservaciones: ' || v_o.notes, '');
  return v_text;
end
$$;
comment on function purchasing.order_message(uuid) is
  'Interna: el texto de una orden de compra para el proveedor (número, local, número de cliente, entrega y líneas con los kg estimados de lo que va por peso).';
revoke execute on function purchasing.order_message(uuid) from public;

-- Encola el mensaje desde la cuenta de la empresa y marca la OC enviada. Interna: la llaman submit_order y la aprobación.
create function purchasing.send_order_internal(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o purchasing.purchase_orders;
  v_t purchasing.supplier_terms;
begin
  select * into v_o from purchasing.purchase_orders where id = p_order_id for update;
  select * into v_t from purchasing.supplier_terms where supplier_id = v_o.supplier_id and deleted_at is null;
  if v_t.po_channel is null or v_t.po_channel_target is null then
    raise exception 'El proveedor no tiene canal para recibir órdenes de compra: cargalo en su ficha.'
      using errcode = '22023';
  end if;
  insert into purchasing.outbound_messages (group_id, channel, target, subject, body, source_table, source_id)
  values (v_o.group_id, v_t.po_channel, v_t.po_channel_target,
          format('Orden de compra %s', v_o.number), purchasing.order_message(v_o.id), 'purchase_orders', v_o.id);
  update purchasing.purchase_orders set status = 'sent', sent_at = now(), sent_channel = v_t.po_channel
   where id = v_o.id;
end
$$;
comment on function purchasing.send_order_internal(uuid) is
  'Interna: pone el mensaje de la OC en la cola de envío (por el canal de la ficha, desde la cuenta de la empresa) y la marca enviada.';
revoke execute on function purchasing.send_order_internal(uuid) from public;

-- «Mandar OC»: con aprobación, si el proveedor la requiere; si no, a la cola.
create function purchasing.submit_order(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o        purchasing.purchase_orders;
  v_t        purchasing.supplier_terms;
  v_request  uuid;
  v_lines    jsonb;
begin
  select * into v_o from purchasing.purchase_orders where id = p_id and deleted_at is null;
  if v_o.id is null or not purchasing.can_in_restaurant('purchasing.create_orders', v_o.restaurant_id) then
    return core.deny('purchasing.submit_order', 'No tenés permiso para mandar esta orden.', null,
                     jsonb_build_object('purchase_order_id', p_id), v_o.group_id, v_o.brand_id, v_o.restaurant_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo.' using errcode = '22023';
  end if;
  select * into v_o from purchasing.purchase_orders where id = p_id and deleted_at is null for update;
  if v_o.status <> 'draft' then
    raise exception 'Esta orden ya se mandó.' using errcode = '23514';
  end if;
  if not exists (select 1 from purchasing.purchase_order_lines where purchase_order_id = v_o.id and deleted_at is null) then
    raise exception 'La orden no tiene líneas.' using errcode = '22023';
  end if;
  select * into v_t from purchasing.supplier_terms where supplier_id = v_o.supplier_id and deleted_at is null;
  if v_t.po_channel is null or v_t.po_channel_target is null then
    raise exception 'El proveedor no tiene canal para recibir órdenes de compra: cargalo en su ficha.'
      using errcode = '22023';
  end if;
  if v_o.expected_delivery_on < recipes.today() then
    raise exception 'La entrega esperada ya pasó: cambiala en el borrador.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  if coalesce(v_t.requires_po_approval, false) then
    -- Lo que se aprueba es exactamente lo que se pidió: las líneas van en la solicitud.
    select jsonb_agg(jsonb_build_object(
             'name', coalesce(p.description, i.name || ' (sin nombre de factura)'),
             'quantity', l.quantity,
             'unit', coalesce(pu.name, u.name)) order by l.line_order)
      into v_lines
      from purchasing.purchase_order_lines l
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join catalog.units pu on pu.id = p.package_unit_id
      left join catalog.ingredients i on i.id = l.ingredient_id
      left join catalog.units u on u.id = l.unit_id
     where l.purchase_order_id = v_o.id and l.deleted_at is null;
    v_request := workflow.request_approval(
      'purchasing.approve_order', v_o.group_id, v_o.brand_id, v_o.restaurant_id, null, v_o.id,
      jsonb_build_object(
        'purchase_order_id', v_o.id, 'number', v_o.number,
        'supplier_name', (select coalesce(s.trade_name, s.name) from catalog.suppliers s where s.id = v_o.supplier_id),
        'expected_delivery_on', v_o.expected_delivery_on, 'lines', v_lines,
        'excluded_approvers', jsonb_build_array(v_o.requested_by)),
      null, p_reason);
    update purchasing.purchase_orders set status = 'pending_approval', approval_request_id = v_request
     where id = v_o.id;
    return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                              'message', 'Enviada a aprobación: la aprueba Compras.');
  end if;
  perform purchasing.send_order_internal(v_o.id);
  return jsonb_build_object('result', 'applied', 'message', 'Orden mandada: quedó en la cola de envío.');
end
$$;
comment on function purchasing.submit_order(uuid, text) is
  '«Mandar OC»: si el proveedor requiere aprobación, crea la solicitud (la aprueba Compras, nunca quien la pidió) y la OC queda pendiente; si no, pone el mensaje en la cola de envío. Pide purchasing.create_orders en el local y un motivo.';
revoke execute on function purchasing.submit_order(uuid, text) from public;
grant execute on function purchasing.submit_order(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Aprobación
-- ---------------------------------------------------------------------------
-- Las funciones que aplican aprobaciones también pueden ser de purchasing (antes: core, org, catalog, recipes y costing).
-- Es la misma regla que en 20261109120000_prices.sql, con un esquema más.
create or replace function workflow.check_apply_function()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
       select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where p.oid = new.apply_function::oid
          and n.nspname in ('core', 'org', 'catalog', 'recipes', 'costing', 'purchasing')
          and p.proname like 'apply\_%'
          and p.pronargs = 1 and p.proargtypes[0] = 'uuid'::regtype and p.prorettype = 'void'::regtype) then
    raise exception 'La función que aplica una aprobación tiene que ser una de las funciones apply_* de core, org, catalog, recipes, costing o purchasing.'
      using errcode = '42501';
  end if;
  if not exists (select 1 from core.permissions p where p.code = new.required_permission and p.deleted_at is null) then
    raise exception 'El permiso para aprobar % no existe.', new.required_permission using errcode = '23514';
  end if;
  if exists (select 1 from unnest(coalesce(new.approver_role_codes, '{}')) c
              where not exists (select 1 from core.roles r where r.code = c and r.deleted_at is null)) then
    raise exception 'Algún rol exigido para aprobar no existe.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and cardinality(coalesce(old.approver_role_codes, '{}')) > cardinality(coalesce(new.approver_role_codes, '{}')) then
    raise exception 'Los roles exigidos para aprobar no se quitan con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and new.allow_self_approval then
    raise exception 'Un tipo de aprobación nuevo no permite aprobarse lo propio: hace falta una migración documentada que cambie esta regla.'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and ((new.allow_self_approval and not old.allow_self_approval) or new.min_approvers < old.min_approvers) then
    raise exception 'Permitir la autoaprobación o pedir menos aprobaciones no se hace con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  return new;
end
$$;

-- Avisa a quien pidió la OC (si no es quien hizo el cambio).
create function purchasing.notify_requester(p_o purchasing.purchase_orders, p_title text, p_body text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_o.requested_by is distinct from core.current_actor_id() then
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    values (p_o.requested_by, p_o.group_id, 'order_news', left(p_title, 200), left(p_body, 500),
            format('/compras/ordenes/%s', p_o.id));
  end if;
end
$$;
comment on function purchasing.notify_requester(purchasing.purchase_orders, text, text) is
  'Interna: avisa a quien pidió una orden de compra (order_news), salvo que sea quien hizo el cambio.';
revoke execute on function purchasing.notify_requester(purchasing.purchase_orders, text, text) from public;

-- Al aprobarse: se vuelve a validar y se encola el mensaje (en la misma transacción que la aprobación).
create function purchasing.apply_order_approval(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests;
  v_o   purchasing.purchase_orders;
begin
  v_req := workflow.approved_request(p_request_id);
  select * into v_o from purchasing.purchase_orders
   where id = (v_req.proposed_changes ->> 'purchase_order_id')::uuid and deleted_at is null for update;
  if v_o.id is null or v_o.status <> 'pending_approval' or v_o.approval_request_id is distinct from v_req.id then
    raise exception 'Esta orden ya no espera aprobación.' using errcode = '23514';
  end if;
  perform purchasing.send_order_internal(v_o.id);
  perform purchasing.notify_requester(v_o, format('Se aprobó la orden %s', v_o.number),
                                      'Quedó en la cola de envío al proveedor.');
end
$$;
comment on function purchasing.apply_order_approval(uuid) is
  'Interna (aprobación purchasing.approve_order): Compras aprobó la OC; se pone en la cola de envío y se avisa a quien la pidió.';
revoke execute on function purchasing.apply_order_approval(uuid) from public;

-- Al rechazarse o cancelarse la solicitud: la OC vuelve a borrador (o queda cancelada) y se avisa a quien la pidió.
create function purchasing.on_order_request_resolved()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o purchasing.purchase_orders;
begin
  if old.status <> 'pending' or new.status not in ('rejected', 'cancelled') then
    return new;
  end if;
  select * into v_o from purchasing.purchase_orders
   where approval_request_id = new.id and status = 'pending_approval' and deleted_at is null for update;
  if v_o.id is null then
    return new;
  end if;
  if new.status = 'cancelled' then
    -- Quien la pidió retiró la solicitud: la OC vuelve a borrador (si no, quedaría trabada esperando).
    update purchasing.purchase_orders set status = 'draft', approval_request_id = null where id = v_o.id;
    insert into purchasing.purchase_order_events (group_id, purchase_order_id, kind, message)
    values (v_o.group_id, v_o.id, 'note', 'Se retiró el pedido de aprobación. Volvió a borrador.');
  elsif new.status = 'rejected' then
    update purchasing.purchase_orders set status = 'draft', approval_request_id = null where id = v_o.id;
    insert into purchasing.purchase_order_events (group_id, purchase_order_id, kind, message)
    values (v_o.group_id, v_o.id, 'note',
            left('Compras no la aprobó' || coalesce(': ' || rtrim(new.resolution_comment, '.'), '')
                 || '. Volvió a borrador.', 1000));
    perform purchasing.notify_requester(v_o, format('No se aprobó la orden %s', v_o.number),
                                        coalesce(new.resolution_comment, 'Volvió a borrador: revisala y mandala de nuevo.'));
  end if;
  return new;
end
$$;
comment on function purchasing.on_order_request_resolved() is
  'Interna: si Compras rechaza la aprobación de una OC, o quien la pidió la retira, la OC vuelve a borrador y queda la novedad; si la rechazó Compras, se avisa a quien la pidió.';
revoke execute on function purchasing.on_order_request_resolved() from public;
create trigger purchase_order_request_resolved after update of status on workflow.approval_requests
  for each row execute function purchasing.on_order_request_resolved();

do $$
begin
  perform core.set_change_context('Aprobación de órdenes de compra (Fase 3, ADR-0053)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, approver_role_codes, min_approvers,
                                           apply_function, entity_table)
  values ('purchasing.approve_order', 'Orden de compra',
          'Una orden de compra a un proveedor que requiere aprobación. La aprueba Compras, en el alcance del local, y nunca quien la pidió (decisión 3 de Soy). Al aprobarse, el mensaje queda en la cola de envío.',
          'purchasing.approve_orders', array['purchasing'], 1, 'purchasing.apply_order_approval(uuid)'::regprocedure,
          'purchasing.purchase_orders');
end
$$;

-- ---------------------------------------------------------------------------
-- 8. Novedades y cancelación
-- ---------------------------------------------------------------------------
create function purchasing.record_order_news(p_id uuid, p_kind purchasing.po_event_kind, p_message text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o purchasing.purchase_orders;
  v_constraint text;
  v_message    text;
begin
  select * into v_o from purchasing.purchase_orders where id = p_id and deleted_at is null;
  if v_o.id is null or not purchasing.can_in_restaurant('purchasing.record_order_news', v_o.restaurant_id) then
    return core.deny('purchasing.record_order_news', 'No tenés permiso para registrar novedades en esta orden.', null,
                     jsonb_build_object('purchase_order_id', p_id), v_o.group_id, v_o.brand_id, v_o.restaurant_id);
  end if;
  if p_kind is null or p_kind = 'cancelled' then
    raise exception 'Elegí el tipo de novedad (para cancelar, usá «Cancelar»).' using errcode = '22023';
  end if;
  select * into v_o from purchasing.purchase_orders where id = p_id for update;
  if v_o.status not in ('sent', 'with_news', 'partially_received') then
    raise exception 'Las novedades se registran en una orden ya mandada.' using errcode = '23514';
  end if;
  perform core.set_change_context(left(btrim(p_message), 500), 'manual');
  insert into purchasing.purchase_order_events (group_id, purchase_order_id, kind, message)
  values (v_o.group_id, v_o.id, p_kind, btrim(p_message));
  if v_o.status = 'sent' then
    update purchasing.purchase_orders set status = 'with_news' where id = v_o.id;
  end if;
  perform purchasing.notify_requester(v_o, format('Novedad en la orden %s', v_o.number), btrim(p_message));
  return jsonb_build_object('result', 'applied');
exception when check_violation or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_order_error(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.record_order_news(uuid, purchasing.po_event_kind, text) is
  'Registra una novedad en una OC mandada (falta mercadería, cambio de entrega, nota): la OC pasa a «con novedad» y se avisa a quien la pidió. Pide purchasing.record_order_news en el local.';
revoke execute on function purchasing.record_order_news(uuid, purchasing.po_event_kind, text) from public;
grant execute on function purchasing.record_order_news(uuid, purchasing.po_event_kind, text) to authenticated;

create function purchasing.cancel_order(p_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o purchasing.purchase_orders;
begin
  select * into v_o from purchasing.purchase_orders where id = p_id and deleted_at is null;
  if v_o.id is null
     or not ((v_o.requested_by = core.current_actor_id()
              and purchasing.can_in_restaurant('purchasing.create_orders', v_o.restaurant_id))
             or purchasing.can_in_restaurant('purchasing.approve_orders', v_o.restaurant_id)) then
    return core.deny('purchasing.cancel_order', 'No tenés permiso para cancelar esta orden.', null,
                     jsonb_build_object('purchase_order_id', p_id), v_o.group_id, v_o.brand_id, v_o.restaurant_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de la cancelación.' using errcode = '22023';
  end if;
  select * into v_o from purchasing.purchase_orders where id = p_id for update;
  if v_o.status not in ('draft', 'pending_approval', 'sent', 'with_news') then
    raise exception 'Una orden con mercadería recibida no se cancela.' using errcode = '23514';
  end if;
  perform core.set_change_context(left(btrim(p_reason), 500), 'manual');
  -- Primero la OC: así, al cancelar la solicitud, el trigger no la devuelve a borrador.
  update purchasing.purchase_orders set status = 'cancelled' where id = v_o.id;
  if v_o.approval_request_id is not null then
    update workflow.approval_requests
       set status = 'cancelled', resolved_at = now(), resolved_by = core.current_actor_id(),
           resolution_comment = left(btrim(p_reason), 500)
     where id = v_o.approval_request_id and status = 'pending';
  end if;
  update purchasing.outbound_messages set status = 'cancelled'
   where source_table = 'purchase_orders' and source_id = v_o.id and status = 'queued';
  insert into purchasing.purchase_order_events (group_id, purchase_order_id, kind, message)
  values (v_o.group_id, v_o.id, 'cancelled', left(btrim(p_reason), 1000));
  perform purchasing.notify_requester(v_o, format('Se canceló la orden %s', v_o.number), btrim(p_reason));
  return jsonb_build_object('result', 'applied');
end
$$;
comment on function purchasing.cancel_order(uuid, text) is
  'Cancela una OC antes de recibirla, con motivo: cancela su aprobación pendiente y el mensaje en cola, y avisa a quien la pidió. La cancela quien la pidió o Compras (purchasing.approve_orders en el local; decisión de Joaco, 2026-11-16).';
revoke execute on function purchasing.cancel_order(uuid, text) from public;
grant execute on function purchasing.cancel_order(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Listado
-- ---------------------------------------------------------------------------
create function purchasing.order_list(p_status text default null, p_supplier_id uuid default null,
                                      p_restaurant_id uuid default null, p_mine boolean default false,
                                      p_from date default null, p_to date default null,
                                      p_limit integer default 15, p_offset integer default 0)
returns table (id uuid, number text, restaurant_id uuid, restaurant_name text, supplier_id uuid, supplier_name text,
               created_at timestamptz, expected_delivery_on date, status purchasing.po_status, lines bigint,
               news bigint, mine boolean, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select o.id, o.number, o.restaurant_id, r.name, o.supplier_id, coalesce(s.trade_name, s.name), o.created_at,
         o.expected_delivery_on, o.status,
         (select count(*) from purchasing.purchase_order_lines l where l.purchase_order_id = o.id and l.deleted_at is null),
         (select count(*) from purchasing.purchase_order_events e
           where e.purchase_order_id = o.id and e.deleted_at is null and e.kind <> 'cancelled'),
         o.requested_by = core.current_actor_id(),
         count(*) over ()
    from purchasing.purchase_orders o
    join org.restaurants r on r.id = o.restaurant_id
    join catalog.suppliers s on s.id = o.supplier_id
   where o.deleted_at is null
     and (p_status is null or o.status::text = p_status
          or (p_status = 'open' and o.status in ('draft', 'pending_approval', 'sent', 'with_news')))
     and (p_supplier_id is null or o.supplier_id = p_supplier_id)
     and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
     and (not coalesce(p_mine, false) or o.requested_by = core.current_actor_id())
     and (p_from is null or o.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires'))
     and (p_to is null or o.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'))
   order by o.created_at desc, o.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;
comment on function purchasing.order_list(text, uuid, uuid, boolean, date, date, integer, integer) is
  'Listado de órdenes de compra, las más nuevas primero, con los permisos de quien consulta: número, local, proveedor, fechas, estado, cuántas líneas y novedades tiene y si es propia. Filtra por estado (o «open»), proveedor, local, propias y fechas, y pagina.';
revoke execute on function purchasing.order_list(text, uuid, uuid, boolean, date, date, integer, integer) from public;
grant execute on function purchasing.order_list(text, uuid, uuid, boolean, date, date, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Lectura de la ficha y búsqueda para pedir
-- ---------------------------------------------------------------------------
-- Las líneas de una OC con sus nombres. El cocinero no lee el catálogo de productos (no tiene catalog.view): la función
-- muestra solo las de una OC que la sesión ve (la misma regla que la RLS de purchase_orders).
create function purchasing.order_lines(p_order_id uuid)
returns table (line_order integer, purchase_product_id uuid, ingredient_id uuid, name text, supplier_sku text,
               package_name text, unit_name text, quantity numeric, received_quantity numeric, line_note text,
               billed_by_weight boolean, estimated_kg numeric, without_invoice_name boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select l.line_order, l.purchase_product_id, l.ingredient_id, coalesce(p.description, i.name), p.supplier_sku, pu.name,
         u.name, l.quantity, l.received_quantity, l.line_note, coalesce(p.billed_by_weight, false),
         case when p.billed_by_weight and p.estimated_weight_per_unit is not null then
           round(l.quantity * p.units_per_package * p.estimated_weight_per_unit
                 / case when cu.code = 'g' then 1000 else 1 end, 1) end,
         l.ingredient_id is not null
    from purchasing.purchase_order_lines l
    join purchasing.purchase_orders o on o.id = l.purchase_order_id
    left join catalog.purchase_products p on p.id = l.purchase_product_id
    left join catalog.units pu on pu.id = p.package_unit_id
    left join catalog.units cu on cu.id = p.content_unit_id
    left join catalog.ingredients i on i.id = l.ingredient_id
    left join catalog.units u on u.id = l.unit_id
   where l.purchase_order_id = p_order_id and l.deleted_at is null and o.deleted_at is null
     and o.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_orders'))
   order by l.line_order
$$;
comment on function purchasing.order_lines(uuid) is
  'Las líneas de una orden de compra con el nombre del artículo (o de la materia prima, «sin nombre de factura»), su envase y los kg estimados de lo que va por peso. Solo de una OC que la sesión ve. Sin precios.';
revoke execute on function purchasing.order_lines(uuid) from public;
grant execute on function purchasing.order_lines(uuid) to authenticated;

-- Buscar una materia prima para pedirla «sin nombre de factura» (quien puede pedir en ese local).
create function purchasing.order_ingredient_search(p_restaurant_id uuid, p_query text)
returns table (id uuid, code text, name text, unit_name text)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (select lower(btrim(p_query)) as t,
                    replace(replace(replace(lower(btrim(p_query)), '\', '\\'), '%', '\%'), '_', '\_') as e)
  select i.id, i.code, i.name, u.name
    from q, catalog.ingredients i
    join catalog.units u on u.id = i.recipe_unit_id
    join org.restaurants r on r.id = p_restaurant_id and r.group_id = i.group_id
   where length(q.t) >= 2 and i.is_active and i.deleted_at is null
     and (lower(i.name) like '%' || q.e || '%' or lower(i.code) like q.e || '%')
     and purchasing.can_in_restaurant('purchasing.create_orders', p_restaurant_id)
   order by i.name
   limit 12
$$;
comment on function purchasing.order_ingredient_search(uuid, text) is
  'Busca materias primas activas del grupo por nombre o código (hasta 12), para pedir una «sin nombre de factura». Vacío si la sesión no puede pedir en ese local.';
revoke execute on function purchasing.order_ingredient_search(uuid, text) from public;
grant execute on function purchasing.order_ingredient_search(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. Bajar «requiere aprobación» de un proveedor pide el OK de Dirección (revisión de seguridad, G1)
-- ---------------------------------------------------------------------------
-- Si no, Compras podría desmarcarla, mandar su propia OC sin aprobación y volver a marcarla (decisión de Joaco,
-- 2026-11-16). Marcarla sigue siendo directo.
create function purchasing.guard_po_approval_flag()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.requires_po_approval and not new.requires_po_approval
     and coalesce(current_setting('purchasing.lowering_po_approval', true), '') <> 'on' then
    raise exception 'Para que deje de requerir aprobación, lo aprueba Dirección: usá «Pedir que deje de requerir aprobación».'
      using errcode = '22023';
  end if;
  return new;
end
$$;
comment on function purchasing.guard_po_approval_flag() is
  'Interna: no deja desmarcar «requiere aprobación de OC» de un proveedor sin la aprobación de Dirección (purchasing.lower_po_approval).';
revoke execute on function purchasing.guard_po_approval_flag() from public;
create trigger guard_po_approval_flag before update of requires_po_approval on purchasing.supplier_terms
  for each row execute function purchasing.guard_po_approval_flag();

create function purchasing.request_lower_po_approval(p_supplier_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s catalog.suppliers;
  v_request uuid;
begin
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null or not core.has_permission_in_group('purchasing.manage_suppliers', v_s.group_id) then
    return core.deny('purchasing.request_lower_po_approval', 'No tenés permiso para cambiar este proveedor.', null,
                     jsonb_build_object('supplier_id', p_supplier_id), v_s.group_id);
  end if;
  if not exists (select 1 from purchasing.supplier_terms
                  where supplier_id = v_s.id and deleted_at is null and requires_po_approval) then
    raise exception 'Este proveedor ya no requiere aprobación.' using errcode = '23514';
  end if;
  v_request := workflow.request_approval(
    'purchasing.lower_po_approval', v_s.group_id, null, null, null, v_s.id,
    jsonb_build_object('supplier_id', v_s.id, 'supplier_name', coalesce(v_s.trade_name, v_s.name),
                       'excluded_approvers', jsonb_build_array(core.current_actor_id())),
    jsonb_build_object('requires_po_approval', true), p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'Pedido enviado: lo aprueba Dirección.');
end
$$;
comment on function purchasing.request_lower_po_approval(uuid, text) is
  'Pide que un proveedor deje de requerir aprobación de OC. Lo aprueba Dirección, nunca quien lo pidió. Pide purchasing.manage_suppliers en el grupo y un motivo.';
revoke execute on function purchasing.request_lower_po_approval(uuid, text) from public;
grant execute on function purchasing.request_lower_po_approval(uuid, text) to authenticated;

create function purchasing.apply_lower_po_approval(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests;
begin
  v_req := workflow.approved_request(p_request_id);
  perform set_config('purchasing.lowering_po_approval', 'on', true);
  update purchasing.supplier_terms set requires_po_approval = false
   where supplier_id = (v_req.proposed_changes ->> 'supplier_id')::uuid and deleted_at is null;
  perform set_config('purchasing.lowering_po_approval', '', true);
end
$$;
comment on function purchasing.apply_lower_po_approval(uuid) is
  'Interna (aprobación purchasing.lower_po_approval): Dirección aprobó que el proveedor deje de requerir aprobación de OC.';
revoke execute on function purchasing.apply_lower_po_approval(uuid) from public;

do $$
begin
  perform core.set_change_context('Bajar «requiere aprobación» de un proveedor (Fase 3, ADR-0053)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, approver_role_codes, min_approvers,
                                           apply_function, entity_table)
  values ('purchasing.lower_po_approval', 'Proveedor sin aprobación de OC',
          'Que un proveedor deje de requerir aprobación de sus órdenes de compra. Lo aprueba Dirección, nunca quien lo pidió: si no, Compras podría saltear la aprobación de su propia OC.',
          'purchasing.manage_suppliers', array['general_management'], 1,
          'purchasing.apply_lower_po_approval(uuid)'::regprocedure, 'catalog.suppliers');
end
$$;
