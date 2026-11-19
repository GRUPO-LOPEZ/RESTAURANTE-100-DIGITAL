-- Fase 3, Prompt 5B (ADR-0058): correcciones de la revisión de base y de seguridad de las pantallas de facturas.
--
-- - «+ Nueva factura» no ofrece una OC que ya tiene una factura en curso (cargada u observada): se termina esa o se
--   cancela (db-reviewer, M1). El control ya frenaba el doble cobro; ahora la pantalla no lo invita.
-- - El listado no pierde filas si quien consulta no ve el proveedor o el local (left join).
-- - El origen de un precio no cuenta lo borrado y muestra el proveedor solo a quien ve proveedores (security-auditor).
-- - La foto de una factura o de una nota se sube como .jpg o .pdf, también si se sube directo a Storage.
-- - Índice para el listado sin filtro de local, y «-$ 0,00» no aparece más.

-- ---------------------------------------------------------------------------
-- 1. Las OC que se pueden facturar
-- ---------------------------------------------------------------------------
create or replace function purchasing.invoiceable_orders(p_restaurant_id uuid, p_supplier_id uuid default null)
returns table (id uuid, number text, supplier_id uuid, supplier_name text, status purchasing.po_status,
               received_on date, lines bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select o.id, o.number, o.supplier_id, coalesce(s.trade_name, s.name), o.status,
         (select max(rc.closed_at at time zone 'America/Argentina/Buenos_Aires')::date
            from purchasing.receipts rc
           where rc.purchase_order_id = o.id and rc.status = 'closed' and rc.deleted_at is null),
         (select count(*) from purchasing.purchase_order_lines l
           where l.purchase_order_id = o.id and l.deleted_at is null and l.received_quantity > 0)
    from purchasing.purchase_orders o
    join catalog.suppliers s on s.id = o.supplier_id
   where o.restaurant_id = p_restaurant_id and o.deleted_at is null
     and o.status in ('received', 'partially_received')
     and s.is_active and s.deleted_at is null
     and (p_supplier_id is null or o.supplier_id = p_supplier_id)
     -- Una factura en curso de esta OC se termina (o se cancela) antes de cargar otra.
     and not exists (select 1 from purchasing.invoice_orders io
                       join purchasing.invoices i on i.id = io.invoice_id
                      where io.purchase_order_id = o.id and io.deleted_at is null and i.deleted_at is null
                        and i.status in ('loaded', 'in_control', 'observed'))
     and purchasing.can_in_restaurant('purchasing.manage_invoices', p_restaurant_id)
   order by coalesce(s.trade_name, s.name), o.number
   limit 200
$$;
comment on function purchasing.invoiceable_orders(uuid, uuid) is
  '«+ Nueva factura»: las órdenes recibidas (entera o en parte) de un local, de proveedores activos y sin una factura en curso (cargada u observada: esa se termina o se cancela primero), con la fecha de la última recepción y cuántos renglones llegaron. Lo ya facturado de cada línea no se vuelve a prellenar (purchasing.create_invoice). Vacío si la sesión no carga facturas en ese local.';

-- ---------------------------------------------------------------------------
-- 2. El listado, sin perder filas
-- ---------------------------------------------------------------------------
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
         -- Lo que no pasó en la última corrida del control (vacío si nunca se controló o pasó todo).
         coalesce((select array_agg(distinct c.check_kind::text order by c.check_kind::text)
                     from purchasing.invoice_checks c
                    where c.invoice_id = i.id and not c.passed
                      and c.run_id = (select c2.run_id from purchasing.invoice_checks c2
                                       where c2.invoice_id = i.id order by c2.entry_number desc limit 1)),
                  '{}'),
         count(*) over ()
    from purchasing.invoices i
    -- left join: quien ve la factura pero no el proveedor o el local igual la ve (con «—»), y el total no miente.
    left join org.restaurants r on r.id = i.restaurant_id
    left join catalog.suppliers s on s.id = i.supplier_id
   where i.deleted_at is null
     and (case
            when p_status is null then i.status <> 'cancelled'
            -- Conforme y liberada a pago van juntas: el conforme libera en la misma transacción.
            when p_status = 'released' then i.status in ('approved', 'released')
            else i.status::text = p_status
          end)
     and (p_supplier_id is null or i.supplier_id = p_supplier_id)
     and (p_restaurant_id is null or i.restaurant_id = p_restaurant_id)
     and (p_from is null or i.issued_on >= p_from)
     and (p_to is null or i.issued_on <= p_to)
   order by i.issued_on desc, i.created_at desc, i.id
   limit least(greatest(coalesce(p_limit, 15), 1), 50) offset greatest(coalesce(p_offset, 0), 0)
$$;

-- El listado sin filtro de local ordena por fecha en todo el grupo.
create index invoices_group_issued_idx on purchasing.invoices (group_id, issued_on desc, created_at desc)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. El origen de un precio: sin lo borrado, y el proveedor solo para quien ve proveedores
-- ---------------------------------------------------------------------------
create or replace function costing.price_origins(p_price_record_ids uuid[])
returns table (price_record_id uuid, invoice_id uuid, label text, supplier_name text, can_open boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, i.id, purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number),
         -- La misma regla que la política de catalog.suppliers.
         case when s.group_id in (select core.visible_group_ids('catalog.view'))
                or s.group_id in (select core.visible_group_ids('purchasing.view_suppliers'))
              then coalesce(s.trade_name, s.name) end,
         i.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_invoices'))
    from costing.price_records r
    join purchasing.invoice_lines l on l.id = r.invoice_line_id and l.deleted_at is null
    join purchasing.invoices i on i.id = l.invoice_id and i.deleted_at is null
    join catalog.suppliers s on s.id = i.supplier_id
   where r.id = any (coalesce(p_price_record_ids, '{}'))
     and r.deleted_at is null and r.source = 'invoice' and r.scope_type = 'restaurant'
     -- Lo ve quien ve ese precio (la misma regla que la política de costing.price_records para un precio del local).
     and r.restaurant_id in (select core.permitted_restaurant_ids('prices.view'))
   limit 500
$$;
comment on function costing.price_origins(uuid[]) is
  'De qué factura salió cada precio (para mostrar «Factura A 0003-00012345 · Proveedor»): solo los precios de factura vigentes que la sesión ve (prices.view en su local); el proveedor, si la sesión ve proveedores (si no, nulo), y si puede abrir la factura (purchasing.view_invoices). Hasta 500.';

-- ---------------------------------------------------------------------------
-- 4. La foto de una factura o de una nota: .jpg o .pdf
-- ---------------------------------------------------------------------------
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
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_upload_document(text) is
  'Si la sesión puede subir ese archivo, con nombre <grupo>/<tabla>/<registro>/<uuid>.<ext>: una lista recibida del grupo (purchasing.manage_price_lists); una foto .jpg de una recepción abierta (purchasing.receive en su local); la foto (.jpg) o el PDF de una factura cargada u observada, o de una nota de una factura que admite notas (purchasing.manage_invoices en su local).';

-- ---------------------------------------------------------------------------
-- 5. «-$ 0,00» no aparece: el signo sale del importe ya redondeado
-- ---------------------------------------------------------------------------
create or replace function purchasing.money_text(p_value numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_value is null then '—'
              else case when round(p_value, 2) < 0 then '-' else '' end || '$ '
                   || translate(to_char(abs(round(p_value, 2)), 'FM999,999,999,999,990.00'), ',.', '.,') end
$$;
