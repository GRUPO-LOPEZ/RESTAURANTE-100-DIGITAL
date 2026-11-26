-- Orden de compra en una pantalla (PR B de las correcciones de Compras, ADR-0069; decisiones 1 a 3 de Soy).
--
-- 1. El catálogo para pedir: los artículos del proveedor, primero los pedidos en los últimos 60 días en ese local, con
--    el precio neto de la lista vigente (solo para quien ve listas de precios, decisión de Joaco).
-- 2. Los datos de la orden: canal, si requiere aprobación, la próxima entrega y el pedido mínimo (que ya vive en la
--    condición de pago y se ve con su misma regla: purchasing.can_see_payment).
-- 3. Solo artículos del proveedor: ya no se pide una materia prima «sin nombre de factura». save_order_draft pasa a
--    ser interna y la nueva, con el mismo nombre y firma, rechaza esas líneas antes de llamarla. Las OC que ya tienen
--    líneas con materia prima no se tocan: se siguen leyendo, recibiendo y facturando.

-- ---------------------------------------------------------------------------
-- 1. Catálogo para pedir
-- ---------------------------------------------------------------------------
create function purchasing.order_catalog(p_supplier_id uuid, p_restaurant_id uuid)
returns table (purchase_product_id uuid, code text, description text, supplier_sku text, package_name text,
               units_per_package integer, content_per_unit numeric, content_unit text, billed_by_weight boolean,
               estimated_weight_per_unit numeric, recent boolean, times_ordered bigint, last_ordered_on date,
               list_price numeric, list_includes_vat boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with session as (
    -- Quién puede pedir en el local (lo mismo que supplier_product_ranking) y si ve los precios de lista del grupo.
    select r.group_id,
           purchasing.can_in_restaurant('purchasing.create_orders', r.id) as can_order,
           r.group_id in (select core.visible_group_ids('purchasing.view_price_lists')) as can_see_prices
      from org.restaurants r
     where r.id = p_restaurant_id and r.deleted_at is null),
  list as (
    select purchasing.price_list_at(p_supplier_id, recipes.today()) as id),
  recent as (
    -- Lo pedido en los últimos 60 días en este local, en OC que salieron (enviadas o más adelante).
    select l.purchase_product_id as product_id, count(distinct o.id) as times,
           max((coalesce(o.sent_at, o.created_at) at time zone 'America/Argentina/Buenos_Aires')::date) as last_on
      from purchasing.purchase_order_lines l
      join purchasing.purchase_orders o on o.id = l.purchase_order_id
     where o.restaurant_id = p_restaurant_id and o.supplier_id = p_supplier_id
       and l.deleted_at is null and o.deleted_at is null and l.purchase_product_id is not null
       and o.status in ('sent', 'with_news', 'partially_received', 'received', 'closed')
       and coalesce(o.sent_at, o.created_at)
           -- Los últimos 60 días: hoy y los 59 anteriores, en hora de la Argentina.
           >= ((recipes.today() - 59)::timestamp at time zone 'America/Argentina/Buenos_Aires')
     group by l.purchase_product_id)
  select p.id, p.code, p.description, p.supplier_sku, pu.name, p.units_per_package, p.content_per_unit, cu.code,
         p.billed_by_weight, p.estimated_weight_per_unit,
         h.product_id is not null, coalesce(h.times, 0), h.last_on,
         case when s.can_see_prices then i.net end,
         case when s.can_see_prices then i.includes_vat end
    from session s
    join catalog.purchase_products p on p.group_id = s.group_id
    join catalog.units pu on pu.id = p.package_unit_id
    join catalog.units cu on cu.id = p.content_unit_id
    left join recent h on h.product_id = p.id
    left join lateral (
      select purchasing.net_list_price(x.list_price, x.bonus1_pct, x.bonus2_pct, x.bonus_per_unit_amount) as net,
             x.includes_vat
        from purchasing.price_list_items x
       where x.price_list_id = (select id from list) and x.purchase_product_id = p.id and x.deleted_at is null
       order by x.line_order
       limit 1) i on true
   where s.can_order and p.supplier_id = p_supplier_id and p.is_active and p.deleted_at is null
     -- El proveedor, activo y del grupo del local (como order_supplier_info y save_order_draft).
     and exists (select 1 from catalog.suppliers sp
                  where sp.id = p_supplier_id and sp.group_id = s.group_id and sp.deleted_at is null and sp.is_active)
   order by (h.product_id is null), h.times desc nulls last, p.description, p.id
$$;
comment on function purchasing.order_catalog(uuid, uuid) is
  'Los artículos activos de un proveedor para pedir en un local: primero los pedidos ahí en los últimos 60 días (con cuántas veces y la última), después el resto por nombre. Con el precio neto por envase de la lista vigente hoy y si incluye IVA, solo si la sesión ve listas de precios (si no, vacío). Vacío si la sesión no puede pedir en ese local.';
revoke execute on function purchasing.order_catalog(uuid, uuid) from public, anon;
grant execute on function purchasing.order_catalog(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Los datos de la orden
-- ---------------------------------------------------------------------------
create function purchasing.order_supplier_info(p_supplier_id uuid, p_restaurant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r     org.restaurants;
  v_terms purchasing.supplier_terms;
  v_min   numeric;
  v_next  date;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.create_orders', v_r.id) then
    return null;
  end if;
  perform 1 from catalog.suppliers
   where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null and is_active;
  if not found then
    return null;
  end if;
  select * into v_terms from purchasing.supplier_terms where supplier_id = p_supplier_id and deleted_at is null;
  -- El pedido mínimo es parte de la condición de pago: se ve con su misma regla (la ficha del proveedor).
  if purchasing.can_see_payment(v_r.group_id) then
    select minimum_order_amount into v_min
      from purchasing.supplier_payment_terms where supplier_id = p_supplier_id and deleted_at is null;
  end if;
  -- Sin días de entrega cargados (o sin poder leerlos) la próxima entrega queda vacía: la persona la elige en la orden
  -- (revisión de base, G1). Antes, la pantalla seguía andando igual.
  begin
    v_next := purchasing.expected_delivery(p_supplier_id, recipes.today());
  exception when sqlstate '22023' or insufficient_privilege then
    v_next := null;
  end;
  return jsonb_build_object(
    'channel', v_terms.po_channel,
    'requires_approval', coalesce(v_terms.requires_po_approval, false),
    'next_delivery', v_next,
    'can_see_prices', v_r.group_id in (select core.visible_group_ids('purchasing.view_price_lists')),
    'minimum_order_amount', v_min);
end
$$;
comment on function purchasing.order_supplier_info(uuid, uuid) is
  'Lo que la orden muestra del proveedor en un local: canal de envío, si requiere aprobación, la próxima entrega, si la sesión ve precios de lista y el pedido mínimo (solo si ve la condición de pago). Vacío si la sesión no puede pedir en ese local.';
revoke execute on function purchasing.order_supplier_info(uuid, uuid) from public, anon;
grant execute on function purchasing.order_supplier_info(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Solo artículos del proveedor (decisión 3 de Soy)
-- ---------------------------------------------------------------------------
-- La de antes pasa a interna, sin cambios: la nueva rechaza las líneas con materia prima y le delega el resto (el
-- permiso, el número, la auditoría y los errores). La app no escribe purchase_order_lines (solo la lee): esta es la
-- única entrada.
alter function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text)
  rename to save_order_draft_internal;
revoke execute on function purchasing.save_order_draft_internal(uuid, uuid, uuid, jsonb, text, date, text)
  from public, anon, authenticated;
comment on function purchasing.save_order_draft_internal(uuid, uuid, uuid, jsonb, text, date, text) is
  'Interna: crea o reemplaza el borrador de una OC (la versión de ADR-0053). Solo la llama purchasing.save_order_draft, que antes rechaza las líneas que no son un artículo del proveedor.';

create function purchasing.save_order_draft(p_order_id uuid, p_restaurant_id uuid, p_supplier_id uuid, p_lines jsonb,
                                            p_notes text, p_expected_on date, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Sin permiso en el local, primero la interna: rechaza y deja el registro (core.deny) como siempre.
  if not purchasing.can_in_restaurant('purchasing.create_orders', p_restaurant_id) then
    return purchasing.save_order_draft_internal(p_order_id, p_restaurant_id, p_supplier_id, p_lines, p_notes,
                                                p_expected_on, p_reason);
  end if;
  if jsonb_typeof(p_lines) = 'array'
     and exists (select 1 from jsonb_array_elements(p_lines) as e (line)
                  where jsonb_typeof(e.line) <> 'object' or e.line ? 'ingredient_id'
                     or not e.line ? 'purchase_product_id') then
    raise exception 'Pedí artículos del proveedor: si no está, sumalo primero a su catálogo.' using errcode = '22023';
  end if;
  return purchasing.save_order_draft_internal(p_order_id, p_restaurant_id, p_supplier_id, p_lines, p_notes,
                                              p_expected_on, p_reason);
end
$$;
comment on function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text) is
  'Crea una orden de compra en borrador (con su número del local) o reemplaza sus líneas, en una transacción y con motivo. Solo artículos del proveedor (decisión 3 de Soy, ADR-0069): una materia prima suelta se rechaza. Pide purchasing.create_orders en el local y que el local tenga código.';
revoke execute on function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text) from public, anon;
grant execute on function purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Lo que la app ya no usa, cerrado (revisión de seguridad)
-- ---------------------------------------------------------------------------
-- La búsqueda de materias primas para pedirlas «sin nombre de factura» y el ranking de antes quedan en la base (con su
-- historia), pero sin permiso para la sesión: menos superficie expuesta. Se borran cuando no los use nada.
revoke execute on function purchasing.order_ingredient_search(uuid, text) from authenticated;
revoke execute on function purchasing.supplier_product_ranking(uuid, uuid) from authenticated;

-- ---------------------------------------------------------------------------
-- 5. Lo «reciente» del catálogo, con índice (revisión de base, M1)
-- ---------------------------------------------------------------------------
-- order_catalog busca las OC de un local y un proveedor por la fecha en que salieron: sin esto, recorre toda la historia
-- del local.
create index purchase_orders_recent_idx
  on purchasing.purchase_orders (restaurant_id, supplier_id, (coalesce(sent_at, created_at)))
  where deleted_at is null;
