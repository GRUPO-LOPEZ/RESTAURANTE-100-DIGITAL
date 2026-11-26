-- Orden de compra en una pantalla (PR B de las correcciones de Compras, ADR-0069). Con el seed: Lácteos Demo (...903)
-- tiene lista de precios vigente, 7 artículos, órdenes enviadas en Demo Pastas Centro (...201) y un pedido mínimo de
-- $ 50.000. Personas: ...0404 gerente (...201; ve listas, no la condición de pago), ...0408 compras (grupo; ve todo),
-- ...0409 cocinero (...201; pide, sin precios).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(34);

create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
-- El catálogo de Lácteos en un local, con la sesión de una persona.
create function pg_temp.cat(p_user int, p_sql text, p_local int default 201) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select %s from purchasing.order_catalog(%L, %L) c', p_sql, pg_temp.u(903), pg_temp.u(p_local)))
$$;
create function pg_temp.info(p_user int, p_key text, p_local int default 201) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select purchasing.order_supplier_info(%L, %L) ->> %L', pg_temp.u(903), pg_temp.u(p_local), p_key))
$$;

-- Lo que el seed pidió a Lácteos en Demo Pastas Centro y salió (enviada o más adelante): lo «reciente».
create temp table recent_products as
select distinct l.purchase_product_id as id
  from purchasing.purchase_order_lines l
  join purchasing.purchase_orders o on o.id = l.purchase_order_id
 where o.restaurant_id = pg_temp.u(201) and o.supplier_id = pg_temp.u(903) and l.deleted_at is null
   and o.status in ('sent', 'with_news', 'partially_received', 'received', 'closed');
grant select on recent_products to authenticated;

-- ---------------------------------------------------------------------------
-- El catálogo para pedir
-- ---------------------------------------------------------------------------
select ok((select count(*) from recent_products) >= 1, 'el seed tiene artículos de Lácteos pedidos en el local');
select is(pg_temp.cat(408, 'count(*)'),
          (select count(*)::text from catalog.purchase_products
            where supplier_id = pg_temp.u(903) and is_active and deleted_at is null),
          'trae todos los artículos activos del proveedor');
select is(pg_temp.cat(408, 'count(*) filter (where c.recent)'), (select count(*)::text from recent_products),
          'marca como recientes los pedidos en los últimos 60 días en este local');
select is(pg_temp.cat(408, 'bool_and(c.purchase_product_id in (select id from recent_products)) filter (where c.recent)'),
          'true', 'y son justo esos');
-- Primero los recientes: ninguno queda después de uno que no lo es.
select is(pg_temp.q(pg_temp.u(408), format($s$
  select bool_and(not (not prev and recent))
    from (select c.recent, lag(c.recent, 1, true) over (order by c.n) as prev
            from purchasing.order_catalog(%L, %L) with ordinality as c (purchase_product_id, code, description,
                 supplier_sku, package_name, units_per_package, content_per_unit, content_unit, billed_by_weight,
                 estimated_weight_per_unit, recent, times_ordered, last_ordered_on, list_price, list_includes_vat, n)) x $s$, pg_temp.u(903), pg_temp.u(201))),
  'true', 'los recientes van primero');
select ok(pg_temp.cat(408, 'min(c.times_ordered) filter (where c.recent)')::int >= 1
          and pg_temp.cat(408, 'max(c.last_ordered_on) filter (where c.recent)')::date = recipes.today(),
          'con cuántas veces y la última vez');
select is(pg_temp.cat(408, 'count(*) filter (where c.recent)', 202), '0',
          'en otro local no hay recientes: lo pedido es de cada local');

-- El precio: el neto por envase de la lista vigente hoy.
select is(pg_temp.q(pg_temp.u(408), format(
            'select c.list_price::text from purchasing.order_catalog(%L, %L) c where c.list_price is not null order by c.description limit 1',
            pg_temp.u(903), pg_temp.u(201))),
          (select purchasing.net_list_price(i.list_price, i.bonus1_pct, i.bonus2_pct, i.bonus_per_unit_amount)::text
             from purchasing.price_list_items i
             join catalog.purchase_products p on p.id = i.purchase_product_id
            where i.price_list_id = purchasing.price_list_at(pg_temp.u(903), recipes.today()) and i.deleted_at is null
            order by p.description limit 1),
          'el precio es el neto por envase de la lista vigente');
select ok(pg_temp.cat(408, 'count(*) filter (where c.list_price is not null)')::int >= 1,
          'Compras ve precios');
select ok(pg_temp.cat(404, 'count(*) filter (where c.list_price is not null)')::int >= 1,
          'el gerente (ve listas de precios) también');
select is(pg_temp.cat(409, 'count(*) filter (where c.list_price is not null or c.list_includes_vat is not null)'), '0',
          'el cocinero arma la orden sin precios');
select is(pg_temp.cat(409, 'count(*)'), pg_temp.cat(408, 'count(*)'), 'pero con los mismos artículos');
select is(pg_temp.cat(409, 'count(*)', 202), '0', 'quien no pide en el local no ve nada');

-- Un borrador no cuenta como pedido (solo las OC que salieron): un artículo que solo está en un borrador no es reciente.
select is(pg_temp.q(pg_temp.u(409), format($s$
  select purchasing.save_order_draft(null, %L, %L, jsonb_build_array(jsonb_build_object('purchase_product_id', %L,
           'quantity', 1)), null, current_date + 7, 'Borrador de prueba') ->> 'result' $s$,
  pg_temp.u(201), pg_temp.u(903),
  (select id from catalog.purchase_products where supplier_id = pg_temp.u(903) and is_active and deleted_at is null
      and id not in (select id from recent_products) order by code limit 1))),
  'applied', 'la cocinera guarda un borrador con un artículo que no se pidió');
select is(pg_temp.cat(408, 'count(*) filter (where c.recent)'), (select count(*)::text from recent_products),
          'un borrador no lo vuelve reciente');

-- Hace 61 días ya no es reciente (cuenta cuándo salió: la fecha de creación no se puede cambiar).
select is((select count(*)::text from purchasing.purchase_orders
            where restaurant_id = pg_temp.u(201) and supplier_id = pg_temp.u(903) and status <> 'draft'
              and sent_at is null), '0',
          'las de Lácteos en el local que no son borrador ya salieron (tienen fecha de envío)');
update purchasing.purchase_orders
   set sent_at = now() - interval '61 days'
 where restaurant_id = pg_temp.u(201) and supplier_id = pg_temp.u(903) and status <> 'draft';
select is(pg_temp.cat(408, 'count(*) filter (where c.recent)'), '0', 'lo pedido hace 61 días ya no es reciente');
update purchasing.purchase_orders
   set sent_at = now() - interval '59 days'
 where restaurant_id = pg_temp.u(201) and supplier_id = pg_temp.u(903) and sent_at is not null;
select is(pg_temp.cat(408, 'count(*) filter (where c.recent)'), (select count(*)::text from recent_products),
          'lo pedido hace 59 días sí: los últimos 60 días son hoy y los 59 anteriores');
select is(pg_temp.cat(408, 'count(*)'),
          (select count(*)::text from catalog.purchase_products
            where supplier_id = pg_temp.u(903) and is_active and deleted_at is null),
          'pero sigue en el catálogo, con el resto');

-- ---------------------------------------------------------------------------
-- Los datos de la orden
-- ---------------------------------------------------------------------------
select is(pg_temp.info(408, 'minimum_order_amount')::numeric, 50000::numeric, 'Compras ve el pedido mínimo');
select is(pg_temp.info(408, 'can_see_prices'), 'true', 'y los precios');
select is(pg_temp.info(404, 'minimum_order_amount'), null,
          'el gerente no ve el mínimo: es de la condición de pago, que no ve');
select is(pg_temp.info(404, 'can_see_prices'), 'true', 'pero sí los precios de lista');
select is(pg_temp.info(409, 'minimum_order_amount'), null, 'el cocinero no ve el mínimo');
select is(pg_temp.info(409, 'can_see_prices'), 'false', 'ni los precios');
select ok(pg_temp.info(409, 'next_delivery') is not null and pg_temp.info(409, 'requires_approval') is not null,
          'con la próxima entrega y si requiere aprobación');
select is(pg_temp.q(pg_temp.u(409), format('select purchasing.order_supplier_info(%L, %L)::text', pg_temp.u(903), pg_temp.u(202))),
          null, 'nada en un local donde no pide');
-- Un proveedor sin días de entrega: los datos llegan igual, sin próxima entrega (la persona la elige en la orden).
create temp table saved_days as
select delivery_days from purchasing.supplier_terms where supplier_id = pg_temp.u(903) and deleted_at is null;
update purchasing.supplier_terms set delivery_days = '{}' where supplier_id = pg_temp.u(903) and deleted_at is null;
select is(pg_temp.info(408, 'can_see_prices'), 'true', 'sin días de entrega, los datos de la orden llegan igual');
select is(pg_temp.info(408, 'next_delivery'), null, 'y la próxima entrega queda vacía');
update purchasing.supplier_terms set delivery_days = (select delivery_days from saved_days)
 where supplier_id = pg_temp.u(903) and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Solo artículos del proveedor (decisión 3 de Soy)
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(409), format($s$
  select purchasing.save_order_draft(null, %L, %L,
           jsonb_build_array(jsonb_build_object('ingredient_id', %L, 'quantity', 500)), null, null, 'Prueba') $s$,
  pg_temp.u(201), pg_temp.u(903), pg_temp.u(819))),
  'Pedí artículos del proveedor: si no está, sumalo primero a su catálogo.', 'una materia prima suelta se rechaza');
select is(pg_temp.msg(pg_temp.u(409), format($s$
  select purchasing.save_order_draft(null, %L, %L,
           jsonb_build_array(jsonb_build_object('purchase_product_id', %L,
                                                'quantity', 2),
                             jsonb_build_object('ingredient_id', %L, 'quantity', 500)), null, null, 'Prueba') $s$,
  pg_temp.u(201), pg_temp.u(903), (select id from catalog.purchase_products where supplier_id = pg_temp.u(903) and is_active and deleted_at is null order by code limit 1), pg_temp.u(819))),
  'Pedí artículos del proveedor: si no está, sumalo primero a su catálogo.',
  'aunque venga junto a un artículo del proveedor');
select is(pg_temp.q(pg_temp.u(409), format($s$
  select purchasing.save_order_draft(null, %L, %L,
           jsonb_build_array(jsonb_build_object('purchase_product_id', %L,
                                                'quantity', 2)), null, null, 'Prueba') ->> 'result' $s$,
  pg_temp.u(201), pg_temp.u(903), (select id from catalog.purchase_products where supplier_id = pg_temp.u(903) and is_active and deleted_at is null order by code limit 1))),
  'applied', 'un artículo del proveedor se pide como siempre');
-- Sin permiso en el local, el rechazo es el de siempre (y queda registrado), aunque la línea sea una materia prima.
select is(pg_temp.q(pg_temp.u(409), format($s$
  select purchasing.save_order_draft(null, %L, %L,
           jsonb_build_array(jsonb_build_object('ingredient_id', %L, 'quantity', 500)), null, null, 'Prueba') ->> 'result' $s$,
  pg_temp.u(202), pg_temp.u(903), pg_temp.u(819))),
  'denied', 'sin permiso en el local, primero se rechaza por permiso');
select ok(not has_function_privilege('authenticated', 'purchasing.save_order_draft_internal(uuid, uuid, uuid, jsonb, text, date, text)', 'execute')
          and not has_function_privilege('anon', 'purchasing.order_catalog(uuid, uuid)', 'execute')
          and not has_function_privilege('anon', 'purchasing.order_supplier_info(uuid, uuid)', 'execute')
          and not has_function_privilege('anon', 'purchasing.save_order_draft(uuid, uuid, uuid, jsonb, text, date, text)', 'execute'),
          'la versión interna no se llama desde la app, y anon no lee el catálogo ni los datos');

select * from finish();
rollback;
