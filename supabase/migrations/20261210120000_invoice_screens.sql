-- Fase 3, Prompt 5B (ADR-0058): lecturas de las pantallas de facturas.
--
-- - purchasing.invoice_list: el listado (tipo C), con la RLS de quien consulta y lo que falló en el último control.
-- - purchasing.invoiceable_orders: las OC recibidas de un local que se pueden facturar («+ Nueva factura»).
-- - purchasing.invoice_access: en la ficha, quién la cargó y la dio por conforme, y qué puede hacer la sesión. La regla
--   de «otra persona» la sigue decidiendo purchasing.approve_invoice; esta función solo la anticipa para la pantalla.
-- - costing.price_origins: el origen «Factura A 0003-00012345 · Proveedor» de un precio, en la ficha de la materia prima
--   y en el impacto de un precio. Lo ve quien ve ese precio (prices.view en su local), aunque no vea facturas.

-- ---------------------------------------------------------------------------
-- 1. Listado
-- ---------------------------------------------------------------------------
create function purchasing.invoice_list(p_status text default null, p_supplier_id uuid default null,
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
  select i.id, i.invoice_class, i.point_of_sale, i.number, i.restaurant_id, r.name, i.supplier_id,
         coalesce(s.trade_name, s.name), i.issued_on, i.due_on, i.total_amount, i.status,
         -- Lo que no pasó en la última corrida del control (vacío si nunca se controló o pasó todo).
         coalesce((select array_agg(distinct c.check_kind::text order by c.check_kind::text)
                     from purchasing.invoice_checks c
                    where c.invoice_id = i.id and not c.passed
                      and c.run_id = (select c2.run_id from purchasing.invoice_checks c2
                                       where c2.invoice_id = i.id order by c2.entry_number desc limit 1)),
                  '{}'),
         count(*) over ()
    from purchasing.invoices i
    join org.restaurants r on r.id = i.restaurant_id
    join catalog.suppliers s on s.id = i.supplier_id
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
comment on function purchasing.invoice_list(text, uuid, uuid, date, date, integer, integer) is
  'Listado de facturas con los permisos de quien consulta (la RLS de purchasing.invoices: purchasing.view_invoices en el local), las más nuevas primero: clase, número, local, proveedor, fechas, total, estado y qué no pasó en el último control. Filtra por estado («released» suma las conformes; sin estado, todas menos las canceladas), proveedor, local y fecha, y pagina.';
revoke execute on function purchasing.invoice_list(text, uuid, uuid, date, date, integer, integer) from public;
grant execute on function purchasing.invoice_list(text, uuid, uuid, date, date, integer, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Las OC que se pueden facturar
-- ---------------------------------------------------------------------------
create function purchasing.invoiceable_orders(p_restaurant_id uuid, p_supplier_id uuid default null)
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
     and purchasing.can_in_restaurant('purchasing.manage_invoices', p_restaurant_id)
   order by coalesce(s.trade_name, s.name), o.number
   limit 200
$$;
comment on function purchasing.invoiceable_orders(uuid, uuid) is
  '«+ Nueva factura»: las órdenes recibidas (entera o en parte) de un local que todavía no se facturaron enteras, de proveedores activos, con la fecha de la última recepción y cuántos renglones llegaron. Vacío si la sesión no carga facturas en ese local.';
revoke execute on function purchasing.invoiceable_orders(uuid, uuid) from public;
grant execute on function purchasing.invoiceable_orders(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Quién y qué puede hacer la sesión en la ficha
-- ---------------------------------------------------------------------------
create function purchasing.invoice_access(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_inv     purchasing.invoices;
  v_actor   uuid := core.current_actor_id();
  v_manage  boolean;
  v_approve boolean;
  v_own     boolean;
begin
  select * into v_inv from purchasing.invoices where id = p_id and deleted_at is null;
  if v_inv.id is null or not purchasing.can_in_restaurant('purchasing.view_invoices', v_inv.restaurant_id) then
    return null;
  end if;
  v_manage := purchasing.can_in_restaurant('purchasing.manage_invoices', v_inv.restaurant_id);
  v_approve := purchasing.can_in_restaurant('purchasing.approve_invoices', v_inv.restaurant_id);
  -- La misma regla que purchasing.approve_invoice: quien la cargó, la corrigió o le sumó una nota no la da por conforme.
  v_own := v_inv.loaded_by = v_actor or v_actor = any (v_inv.edited_by)
           or exists (select 1 from purchasing.credit_debit_notes n
                       where n.invoice_id = v_inv.id and n.deleted_at is null and n.created_by = v_actor);
  return jsonb_build_object(
    'loaded_by_name', core.display_name(v_inv.loaded_by),
    'approved_by_name', case when v_inv.approved_by is not null then core.display_name(v_inv.approved_by) end,
    'can_edit', v_manage and v_inv.status in ('loaded', 'observed'),
    'can_add_note', v_manage and v_inv.status in ('loaded', 'observed', 'approved', 'released'),
    'can_approve', v_approve and v_inv.status = 'observed' and not v_own,
    'approve_blocked', case when v_approve and v_inv.status = 'observed' and v_own
                            then 'La cargaste, la corregiste o le sumaste una nota: la da por conforme otra persona.' end);
end
$$;
comment on function purchasing.invoice_access(uuid) is
  'Para la ficha de una factura que la sesión ve: quién la cargó y quién la dio por conforme, y si la sesión puede corregirla, sumarle notas o darla por conforme a mano (con el motivo cuando no puede por haberla cargado o corregido). Solo anticipa: cada acción la vuelve a controlar su función. Nulo si no la ve.';
revoke execute on function purchasing.invoice_access(uuid) from public;
grant execute on function purchasing.invoice_access(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. El origen de un precio que salió de una factura
-- ---------------------------------------------------------------------------
create function costing.price_origins(p_price_record_ids uuid[])
returns table (price_record_id uuid, invoice_id uuid, label text, supplier_name text, can_open boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, i.id, purchasing.invoice_label(i.invoice_class, i.point_of_sale, i.number),
         coalesce(s.trade_name, s.name),
         i.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_invoices'))
    from costing.price_records r
    join purchasing.invoice_lines l on l.id = r.invoice_line_id
    join purchasing.invoices i on i.id = l.invoice_id
    join catalog.suppliers s on s.id = i.supplier_id
   where r.id = any (coalesce(p_price_record_ids, '{}'))
     and r.deleted_at is null and r.source = 'invoice' and r.scope_type = 'restaurant'
     -- Lo ve quien ve ese precio (la misma regla que la política de costing.price_records para un precio del local).
     and r.restaurant_id in (select core.permitted_restaurant_ids('prices.view'))
   limit 500
$$;
comment on function costing.price_origins(uuid[]) is
  'De qué factura salió cada precio (para mostrar «Factura A 0003-00012345 · Proveedor»): solo los precios de factura que la sesión ve (prices.view en su local), y si puede abrir la factura (purchasing.view_invoices). Hasta 500.';
revoke execute on function costing.price_origins(uuid[]) from public;
grant execute on function costing.price_origins(uuid[]) to authenticated;
