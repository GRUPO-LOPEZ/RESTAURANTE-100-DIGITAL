-- Criterios de Soy en Compras (PR A, ADR-0068): el panel izquierdo de los listados (criterio 7) muestra cada proveedor
-- (o rubro) con su cantidad. Estas lecturas cuentan con los mismos filtros de su lista, menos el del proveedor (o del
-- rubro): el número del panel coincide con el total de la tabla al elegirlo. Cada una copia el «where» de su lista y
-- corre con la misma regla de permisos (invoker, o definer con el mismo filtro de locales, como la agenda de pagos);
-- la prueba 419 compara las dos lecturas. Si una lista cambia de filtro, su conteo cambia en la misma migración.

-- ---------------------------------------------------------------------------
-- 1. Órdenes de compra (purchasing.order_list)
-- ---------------------------------------------------------------------------
create function purchasing.order_supplier_counts(p_status text default null, p_restaurant_id uuid default null,
                                                 p_mine boolean default false, p_from date default null,
                                                 p_to date default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select o.supplier_id, coalesce(s.trade_name, s.name), count(*)
    from purchasing.purchase_orders o
    -- No se lee nada de r: el join está porque la lista lo tiene, y la RLS de org.restaurants deja afuera las mismas filas.
    join org.restaurants r on r.id = o.restaurant_id
    join catalog.suppliers s on s.id = o.supplier_id
   where o.deleted_at is null
     and (p_status is null or o.status::text = p_status
          or (p_status = 'open' and o.status in ('draft', 'pending_approval', 'sent', 'with_news')))
     and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
     and (not coalesce(p_mine, false) or o.requested_by = core.current_actor_id())
     and (p_from is null or o.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires'))
     and (p_to is null or o.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'))
   group by o.supplier_id, coalesce(s.trade_name, s.name)
   order by lower(coalesce(s.trade_name, s.name)), o.supplier_id
$$;
comment on function purchasing.order_supplier_counts(text, uuid, boolean, date, date) is
  'Cuántas órdenes de compra hay por proveedor, con los mismos filtros y permisos que purchasing.order_list (sin el del proveedor). Para el panel izquierdo del listado.';
revoke execute on function purchasing.order_supplier_counts(text, uuid, boolean, date, date) from public, anon;
grant execute on function purchasing.order_supplier_counts(text, uuid, boolean, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Facturas (purchasing.invoice_list, versión de 20261210140000)
-- ---------------------------------------------------------------------------
create function purchasing.invoice_supplier_counts(p_status text default null, p_restaurant_id uuid default null,
                                                   p_from date default null, p_to date default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  -- left join, como la lista: quien ve la factura pero no el proveedor la cuenta igual (con «—»).
  select i.supplier_id, coalesce(s.trade_name, s.name, '—'), count(*)
    from purchasing.invoices i
    left join catalog.suppliers s on s.id = i.supplier_id
   where i.deleted_at is null
     and (case
            when p_status is null then i.status <> 'cancelled'
            when p_status = 'released' then i.status in ('approved', 'released')
            else i.status::text = p_status
          end)
     and (p_restaurant_id is null or i.restaurant_id = p_restaurant_id)
     and (p_from is null or i.issued_on >= p_from)
     and (p_to is null or i.issued_on <= p_to)
   group by i.supplier_id, coalesce(s.trade_name, s.name, '—')
   order by lower(coalesce(s.trade_name, s.name, '—')), i.supplier_id
$$;
comment on function purchasing.invoice_supplier_counts(text, uuid, date, date) is
  'Cuántas facturas hay por proveedor, con los mismos filtros y permisos que purchasing.invoice_list (sin el del proveedor). Para el panel izquierdo del listado.';
revoke execute on function purchasing.invoice_supplier_counts(text, uuid, date, date) from public, anon;
grant execute on function purchasing.invoice_supplier_counts(text, uuid, date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Agenda de pagos (purchasing.payment_schedule_list)
-- ---------------------------------------------------------------------------
-- Definer, como la agenda: lee reporting.v_invoice_balances, que no se abre a la app, y filtra por los locales donde la
-- sesión ve pagos (purchasing.view_payments). El chef y el cocinero no cuentan nada.
create function purchasing.payment_supplier_counts(p_tab text default 'due', p_restaurant_id uuid default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select b.supplier_id, coalesce(s.trade_name, s.name), count(*)
    from reporting.v_invoice_balances b
    -- No se lee nada de r: el join está porque la agenda lo tiene (un local dado de baja queda afuera igual).
    join org.restaurants r on r.id = b.restaurant_id
    join catalog.suppliers s on s.id = b.supplier_id
   where b.restaurant_id in (select core.permitted_restaurant_ids('purchasing.view_payments'))
     and (p_restaurant_id is null or b.restaurant_id = p_restaurant_id)
     and case coalesce(p_tab, 'due')
           when 'overdue' then b.status = 'released' and b.balance_amount > 0.005 and b.due_on < recipes.today()
           when 'paid' then b.status = 'paid'
           else b.status = 'released' and b.balance_amount > 0.005 and b.due_on >= recipes.today()
         end
   group by b.supplier_id, coalesce(s.trade_name, s.name)
   order by lower(coalesce(s.trade_name, s.name)), b.supplier_id
$$;
comment on function purchasing.payment_supplier_counts(text, uuid) is
  'Cuántas facturas de la agenda de pagos hay por proveedor, con las mismas pestañas («due», «overdue», «paid») y permisos que purchasing.payment_schedule_list (sin el filtro del proveedor). Para el panel izquierdo de Pagos.';
revoke execute on function purchasing.payment_supplier_counts(text, uuid) from public, anon;
grant execute on function purchasing.payment_supplier_counts(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Listas de precios (purchasing.price_list_list)
-- ---------------------------------------------------------------------------
create function purchasing.price_list_supplier_counts(p_status text default null)
returns table (supplier_id uuid, supplier_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  with base as (
    select l.supplier_id, coalesce(s.trade_name, s.name) as supplier_name, l.status,
           purchasing.price_list_expired(l.id) as expired
      from purchasing.price_lists l
      join catalog.suppliers s on s.id = l.supplier_id
     where l.deleted_at is null)
  select b.supplier_id, b.supplier_name, count(*)
    from base b
   where p_status is null
      or (p_status = 'expired' and b.expired)
      or (p_status = 'accepted' and b.status = 'accepted' and not b.expired)
      or (p_status in ('received', 'replaced') and b.status::text = p_status)
   group by b.supplier_id, b.supplier_name
   order by lower(b.supplier_name), b.supplier_id
$$;
comment on function purchasing.price_list_supplier_counts(text) is
  'Cuántas listas de precios hay por proveedor, con el mismo filtro de estado y los permisos de purchasing.price_list_list. Para el panel izquierdo del listado.';
revoke execute on function purchasing.price_list_supplier_counts(text) from public, anon;
grant execute on function purchasing.price_list_supplier_counts(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Proveedores por rubro (purchasing.supplier_list)
-- ---------------------------------------------------------------------------
-- Un proveedor puede estar en varios rubros: la suma del panel puede pasar el total; «Todos» sale de la lista.
create function purchasing.supplier_rubro_counts(p_search text default null, p_active boolean default true,
                                                 p_channel purchasing.channel default null)
returns table (category_id uuid, category_name text, total bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, c.name, count(distinct s.id)
    from catalog.suppliers s
    left join purchasing.supplier_terms t on t.supplier_id = s.id and t.deleted_at is null
    join purchasing.supplier_categories sc on sc.supplier_id = s.id and sc.deleted_at is null
    join catalog.ingredient_categories c on c.id = sc.category_id
   where s.deleted_at is null
     and (p_active is null or s.is_active = p_active)
     and (p_channel is null or t.po_channel = p_channel)
     and (nullif(btrim(p_search), '') is null
          or strpos(lower(s.name), lower(btrim(p_search))) > 0
          or strpos(lower(coalesce(s.trade_name, '')), lower(btrim(p_search))) > 0
          or strpos(lower(s.code), lower(btrim(p_search))) > 0
          or (regexp_replace(btrim(p_search), '[^0-9]', '', 'g') <> ''
              and strpos(coalesce(s.tax_id, ''), regexp_replace(btrim(p_search), '[^0-9]', '', 'g')) > 0))
   group by c.id, c.name
   order by lower(c.name), c.id
$$;
comment on function purchasing.supplier_rubro_counts(text, boolean, purchasing.channel) is
  'Cuántos proveedores hay por rubro, con los mismos filtros y permisos que purchasing.supplier_list (sin el del rubro). Un proveedor con varios rubros cuenta en cada uno. Para el panel izquierdo del listado.';
revoke execute on function purchasing.supplier_rubro_counts(text, boolean, purchasing.channel) from public, anon;
grant execute on function purchasing.supplier_rubro_counts(text, boolean, purchasing.channel) to authenticated;
