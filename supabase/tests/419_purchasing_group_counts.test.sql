-- Criterios de Soy en Compras (PR A, ADR-0068): los conteos del panel izquierdo coinciden con su lista, con la sesión de
-- cada persona y con cada filtro. Cada proveedor (o rubro) cuenta lo mismo que el total de la lista filtrada por él, y la
-- suma de todos es el total de la lista sin filtro. Ninguna comparación pasa sin datos: cada una exige un mínimo.
-- Personas del seed: ...0404 gerente (local ...201), ...0405 chef ejecutivo (marca), ...0408 compras (grupo),
-- ...0409 cocinero, ...0411 gerente de dos locales (...201 y ...202). Las facturas y pagos del seed están en ...203 (y dos
-- facturas en ...202): para que la gerente de dos locales tenga también un pago, acá se libera a pago la factura cargada
-- de ...202 (todo se deshace al final).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(36);

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
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

-- Compara un conteo con su lista, con la sesión de una persona. p_list es la consulta del total de la lista, con %s donde
-- va el proveedor (o el rubro) filtrado. Devuelve «ok», o qué no coincidió. Con p_sum, la suma del panel tiene que ser
-- el total de la lista sin filtro (no vale para los rubros: un proveedor está en varios). Con menos de p_min registros
-- contados, «sin datos»: la comparación no probaría nada.
create function pg_temp.match(p_user int, p_counts text, p_list text, p_min int default 1, p_sum boolean default true)
returns text
language sql
as $$
  select pg_temp.q(pg_temp.u(p_user), format($q$
    select case
             when coalesce(sum(c.total), 0) < %3$s then 'sin datos (' || coalesce(sum(c.total), 0) || ')'
             when %4$L and coalesce(sum(c.total), 0) <> coalesce((%2$s), 0)
               then 'la suma ' || sum(c.total) || ' no es el total ' || coalesce((%2$s), 0)
             when not coalesce(bool_and(c.total = coalesce((%5$s), 0)), true) then 'un grupo no coincide'
             else 'ok'
           end
      from (%1$s) c$q$,
    p_counts, format(p_list, 'null'), p_min, p_sum, format(p_list, 'c.id')))
$$;

-- Las consultas de cada lista (el total de la primera página trae el total de todo).
create function pg_temp.orders(p_args text) returns text language sql as $$
  select format('select max(l.total) from purchasing.order_list(p_supplier_id => %%s, p_limit => 1%s) l', p_args)
$$;
create function pg_temp.invoices(p_args text) returns text language sql as $$
  select format('select max(l.total) from purchasing.invoice_list(p_supplier_id => %%s, p_limit => 1%s) l', p_args)
$$;
create function pg_temp.payments(p_tab text, p_args text default '') returns text language sql as $$
  select format('select max(l.total) from purchasing.payment_schedule_list(%L, %%s, p_limit => 1%s) l', p_tab, p_args)
$$;
create function pg_temp.lists(p_args text) returns text language sql as $$
  select format('select max(l.total) from purchasing.price_list_list(%%s, p_limit => 1%s) l', p_args)
$$;
create function pg_temp.suppliers(p_args text) returns text language sql as $$
  select format('select (purchasing.supplier_list(p_category_id => %%s%s) ->> %L)::bigint', p_args, 'total')
$$;

-- Una factura de ...202 en la agenda de pagos: la gerente de dos locales tiene un pago que ver, y Compras uno más.
update purchasing.invoices
   set status = 'released', approved_by = pg_temp.u(407), approved_at = now()
 where restaurant_id = pg_temp.u(202) and status = 'loaded' and deleted_at is null;

-- ---------------------------------------------------------------------------
-- Órdenes de compra
-- ---------------------------------------------------------------------------
select is(pg_temp.match(408, 'select supplier_id as id, total from purchasing.order_supplier_counts()', pg_temp.orders(''), 5),
          'ok', 'órdenes: Compras, todas');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.order_supplier_counts('open')$s$,
                        pg_temp.orders(', p_status => ''open'''), 2),
          'ok', 'órdenes: Compras, abiertas');
select is(pg_temp.match(404, 'select supplier_id as id, total from purchasing.order_supplier_counts()', pg_temp.orders(''), 2),
          'ok', 'órdenes: el gerente de un local');
select is(pg_temp.match(404, 'select supplier_id as id, total from purchasing.order_supplier_counts(p_mine => true)',
                        pg_temp.orders(', p_mine => true'), 1),
          'ok', 'órdenes: «Mías» del gerente');
select is(pg_temp.match(408, format('select supplier_id as id, total from purchasing.order_supplier_counts(p_restaurant_id => %L)', pg_temp.u(201)),
                        pg_temp.orders(format(', p_restaurant_id => %L', pg_temp.u(201))), 1),
          'ok', 'órdenes: Compras, un local');
select is(pg_temp.match(408, format('select supplier_id as id, total from purchasing.order_supplier_counts(p_from => %L, p_to => %L)',
                                    (select min(created_at)::date from purchasing.purchase_orders), (select max(created_at)::date from purchasing.purchase_orders)),
                        pg_temp.orders(format(', p_from => %L, p_to => %L',
                                              (select min(created_at)::date from purchasing.purchase_orders), (select max(created_at)::date from purchasing.purchase_orders))), 5),
          'ok', 'órdenes: Compras, entre fechas');
select is(pg_temp.q(pg_temp.u(408), format('select count(*) from purchasing.order_supplier_counts(p_to => %L)',
                                           (select min(created_at)::date - 1 from purchasing.purchase_orders))),
          '0', 'órdenes: antes de la primera, ninguna');
select is(pg_temp.q(pg_temp.u(404), 'select sum(total) from purchasing.order_supplier_counts()'),
          (select count(*)::text from purchasing.purchase_orders where deleted_at is null and restaurant_id = pg_temp.u(201)),
          'órdenes: el gerente cuenta exactamente las de su local');

-- ---------------------------------------------------------------------------
-- Facturas
-- ---------------------------------------------------------------------------
select is(pg_temp.match(408, 'select supplier_id as id, total from purchasing.invoice_supplier_counts()', pg_temp.invoices(''), 5),
          'ok', 'facturas: Compras, todas');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.invoice_supplier_counts('observed')$s$,
                        pg_temp.invoices(', p_status => ''observed'''), 2),
          'ok', 'facturas: Compras, observadas');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.invoice_supplier_counts('released')$s$,
                        pg_temp.invoices(', p_status => ''released'''), 2),
          'ok', 'facturas: Compras, conformes (aprobadas y liberadas juntas)');
select is(pg_temp.match(411, 'select supplier_id as id, total from purchasing.invoice_supplier_counts()', pg_temp.invoices(''), 2),
          'ok', 'facturas: la gerente de dos locales');
select is(pg_temp.q(pg_temp.u(411), 'select sum(total) from purchasing.invoice_supplier_counts()'),
          (select count(*)::text from purchasing.invoices
            where deleted_at is null and status <> 'cancelled' and restaurant_id in (pg_temp.u(201), pg_temp.u(202))),
          'facturas: la gerente cuenta exactamente las de sus locales (ninguna de ...203)');
select is(pg_temp.match(408, format('select supplier_id as id, total from purchasing.invoice_supplier_counts(p_restaurant_id => %L)', pg_temp.u(203)),
                        pg_temp.invoices(format(', p_restaurant_id => %L', pg_temp.u(203))), 5),
          'ok', 'facturas: Compras, un local');
select is(pg_temp.match(408, format('select supplier_id as id, total from purchasing.invoice_supplier_counts(p_from => %L, p_to => %L)',
                                    (select max(issued_on) from purchasing.invoices), (select max(issued_on) from purchasing.invoices)),
                        pg_temp.invoices(format(', p_from => %L, p_to => %L',
                                                (select max(issued_on) from purchasing.invoices), (select max(issued_on) from purchasing.invoices))), 1),
          'ok', 'facturas: Compras, un día');
select ok(pg_temp.q(pg_temp.u(408), format('select sum(total) from purchasing.invoice_supplier_counts(p_from => %L, p_to => %L)',
                                           (select max(issued_on) from purchasing.invoices), (select max(issued_on) from purchasing.invoices)))::bigint
            < pg_temp.q(pg_temp.u(408), 'select sum(total) from purchasing.invoice_supplier_counts()')::bigint,
          'facturas: las fechas achican el conteo');

-- ---------------------------------------------------------------------------
-- Agenda de pagos (definer, como la agenda)
-- ---------------------------------------------------------------------------
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.payment_supplier_counts('due')$s$, pg_temp.payments('due'), 2),
          'ok', 'pagos por vencer: Compras');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.payment_supplier_counts('overdue')$s$, pg_temp.payments('overdue'), 1),
          'ok', 'pagos vencidos: Compras');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.payment_supplier_counts('paid')$s$, pg_temp.payments('paid'), 1),
          'ok', 'pagados: Compras');
select is(pg_temp.match(408, format($s$select supplier_id as id, total from purchasing.payment_supplier_counts('due', %L)$s$, pg_temp.u(202)),
                        pg_temp.payments('due', format(', p_restaurant_id => %L', pg_temp.u(202))), 1),
          'ok', 'pagos por vencer: Compras, un local');
select is(pg_temp.match(411, $s$select supplier_id as id, total from purchasing.payment_supplier_counts('due')$s$, pg_temp.payments('due'), 1),
          'ok', 'pagos por vencer: la gerente de dos locales');
select is(pg_temp.q(pg_temp.u(411), $s$select sum(total) from purchasing.payment_supplier_counts('due')$s$),
          (select count(*)::text from reporting.v_invoice_balances b
            where b.restaurant_id in (pg_temp.u(201), pg_temp.u(202)) and b.status = 'released'
              and b.balance_amount > 0.005 and b.due_on >= recipes.today()),
          'pagos: la gerente cuenta exactamente los de sus locales (ninguno de ...203)');

-- ---------------------------------------------------------------------------
-- Listas de precios
-- ---------------------------------------------------------------------------
select is(pg_temp.match(408, 'select supplier_id as id, total from purchasing.price_list_supplier_counts()', pg_temp.lists(''), 3),
          'ok', 'listas: Compras, todas');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.price_list_supplier_counts('accepted')$s$,
                        pg_temp.lists(', p_status => ''accepted'''), 1),
          'ok', 'listas: Compras, vigentes');
select is(pg_temp.match(408, $s$select supplier_id as id, total from purchasing.price_list_supplier_counts('expired')$s$,
                        pg_temp.lists(', p_status => ''expired'''), 1),
          'ok', 'listas: Compras, vencidas');
select is(pg_temp.match(404, 'select supplier_id as id, total from purchasing.price_list_supplier_counts()', pg_temp.lists(''), 3),
          'ok', 'listas: el gerente');

-- ---------------------------------------------------------------------------
-- Proveedores por rubro (un proveedor cuenta en cada rubro suyo: sin la suma)
-- ---------------------------------------------------------------------------
select is(pg_temp.match(408, 'select category_id as id, total from purchasing.supplier_rubro_counts()', pg_temp.suppliers(''), 5, false),
          'ok', 'proveedores por rubro: Compras, activos');
select is(pg_temp.match(408, 'select category_id as id, total from purchasing.supplier_rubro_counts(p_active => false)',
                        pg_temp.suppliers(', p_active => false'), 1, false),
          'ok', 'proveedores por rubro: Compras, inactivos');
select is(pg_temp.match(408, $s$select category_id as id, total from purchasing.supplier_rubro_counts(p_channel => 'email')$s$,
                        pg_temp.suppliers(', p_channel => ''email'''), 1, false),
          'ok', 'proveedores por rubro: Compras, pedidos por mail');
select is(pg_temp.match(408, $s$select category_id as id, total from purchasing.supplier_rubro_counts(p_search => '30-5000000-3')$s$,
                        pg_temp.suppliers(', p_search => ''30-5000000-3'''), 1, false),
          'ok', 'proveedores por rubro: Compras, buscando parte del CUIT');
select is(pg_temp.match(408, $s$select category_id as id, total from purchasing.supplier_rubro_counts(p_search => 'lácteos')$s$,
                        pg_temp.suppliers(', p_search => ''lácteos'''), 1, false),
          'ok', 'proveedores por rubro: Compras, buscando el nombre');
select is(pg_temp.match(405, 'select category_id as id, total from purchasing.supplier_rubro_counts()', pg_temp.suppliers(''), 1, false),
          'ok', 'proveedores por rubro: el chef');

-- ---------------------------------------------------------------------------
-- Nadie cuenta lo que no ve
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), 'select count(*) from purchasing.payment_supplier_counts()'), '0',
          'el cocinero no cuenta pagos');
select is(pg_temp.q(pg_temp.u(405), $s$select count(*) from purchasing.payment_supplier_counts('due')$s$), '0',
          'el chef no cuenta pagos');
select is(pg_temp.q(pg_temp.u(409), 'select count(*) from purchasing.price_list_supplier_counts()'), '0',
          'el cocinero no cuenta listas de precios');

-- Solo para sesiones: anon no las ejecuta (ninguna de las cinco).
select ok(not has_function_privilege('anon', 'purchasing.order_supplier_counts(text, uuid, boolean, date, date)', 'execute')
          and not has_function_privilege('anon', 'purchasing.invoice_supplier_counts(text, uuid, date, date)', 'execute')
          and not has_function_privilege('anon', 'purchasing.payment_supplier_counts(text, uuid)', 'execute')
          and not has_function_privilege('anon', 'purchasing.price_list_supplier_counts(text)', 'execute')
          and not has_function_privilege('anon', 'purchasing.supplier_rubro_counts(text, boolean, purchasing.channel)', 'execute'),
          'anon no ejecuta ninguna de las cinco');

select * from finish();
rollback;
