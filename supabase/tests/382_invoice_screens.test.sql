-- Fase 3, Prompt 5B (ADR-0058): las lecturas de las pantallas de facturas, con las facturas del seed.
-- Personas del seed: ...0404 gerente (local ...201), ...0407 controller, ...0408 compras (las cargó todas), ...0409 cocinero,
-- ...0411 gerente de ...201 y ...202. Locales: ...202 Demo Pastas Norte (2 facturas), ...203 Demo Parrilla Centro (7).
-- Facturas del seed: 3 cargadas, 3 observadas y 3 conformes y liberadas (las da el Controller, «doble firma»).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(33);

create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  if p_user is null then
    perform set_config('request.jwt.claims', '{"role": "anon"}', true);
    set local role anon;
  else
    perform set_config('request.jwt.claims',
                       json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    set local role authenticated;
  end if;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
-- Una factura del seed por su número.
create function pg_temp.inv(p_number bigint) returns uuid language sql as $$
  select id from purchasing.invoices where number = p_number
$$;
-- Los precios de una factura, elegidos fuera de la sesión (así se prueba la función y no la RLS de la consulta).
create function pg_temp.prices(p_number bigint) returns uuid[] language sql as $$
  select array_agg(r.id) from costing.price_records r
    join purchasing.invoice_lines l on l.id = r.invoice_line_id where l.invoice_id = pg_temp.inv(p_number)
$$;
create function pg_temp.list_count(p_user int, p_args text) returns int language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select count(*) from purchasing.invoice_list(%s)', p_args))::int
$$;
create function pg_temp.access(p_user int, p_number bigint, p_key text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user),
                   format('select purchasing.invoice_access(%L) ->> %L', pg_temp.inv(p_number), p_key))
$$;

-- ---------------------------------------------------------------------------
-- Listado
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), 'select max(total) from purchasing.invoice_list()'), '9',
          'Compras ve las 9 facturas del seed (todas menos las canceladas)');
select is(pg_temp.list_count(408, 'p_limit => 50'), 9, 'y las trae en una página de 50');
select is(pg_temp.list_count(408, '''loaded'''), 3, 'pestaña cargadas: 3');
select is(pg_temp.list_count(408, '''observed'''), 3, 'pestaña observadas: 3');
select is(pg_temp.list_count(408, '''released'''), 3, 'pestaña conformes y liberadas: 3');
select is(pg_temp.list_count(408, format('p_restaurant_id => %L', pg_temp.u(202))), 2, 'filtra por local');
select is(pg_temp.list_count(408, format('p_from => %L, p_to => %L', recipes.today() + 1, recipes.today() + 2)), 0,
          'filtra por fecha');
select is(pg_temp.list_count(408, 'p_limit => 2'), 2, 'pagina');
select is(pg_temp.q(pg_temp.u(408), format('select array_length(failed, 1) > 0 from purchasing.invoice_list(%L) where id = %L',
                                           'observed', pg_temp.inv(2001))),
          'true', 'una observada dice qué no pasó en el último control');
select is(pg_temp.q(pg_temp.u(408), format('select cardinality(failed) from purchasing.invoice_list(%L) where id = %L',
                                           'loaded', pg_temp.inv(12))),
          '0', 'una cargada sin controlar no tiene fallas');
select is(pg_temp.list_count(409, 'p_limit => 50'), 0, 'el cocinero no ve facturas');
select is(pg_temp.list_count(411, 'p_limit => 50'), 2, 'el gerente de dos locales ve solo las de sus locales');
select is(pg_temp.q(null, 'select count(*) from purchasing.invoice_list()'), 'ERROR 42501',
          'sin sesión no se llama');

-- ---------------------------------------------------------------------------
-- Órdenes para facturar
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format('select count(*) from purchasing.invoiceable_orders(%L)', pg_temp.u(203))),
          (select count(*)::text from purchasing.purchase_orders o
            where o.restaurant_id = pg_temp.u(203) and o.status in ('received', 'partially_received')
              and not exists (select 1 from purchasing.invoice_orders io join purchasing.invoices i on i.id = io.invoice_id
                               where io.purchase_order_id = o.id and i.status in ('loaded', 'observed'))),
          'Compras ve las OC recibidas de Demo Parrilla Centro sin una factura en curso');
select is(pg_temp.q(pg_temp.u(408), format('select count(*) from purchasing.invoiceable_orders(%L) where number = %L',
                                           pg_temp.u(203), 'PAR-0005')),
          '0', 'una OC con su factura observada no se ofrece otra vez: se termina o se cancela esa');
select pg_temp.q(pg_temp.u(408), format('select purchasing.cancel_invoice(%L, %L) ->> %L', pg_temp.inv(2002),
                                        'Se cargó con el artículo equivocado', 'status'));
select is(pg_temp.q(pg_temp.u(408), format('select count(*) from purchasing.invoiceable_orders(%L) where number = %L',
                                           pg_temp.u(203), 'PAR-0005')),
          '1', 'cancelada la factura, la OC se puede volver a facturar');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.can_upload_document(%L)',
                                           format('00000000-0000-4000-8000-000000000001/invoices/%s/%s.html',
                                                  pg_temp.inv(12), gen_random_uuid()))),
          'false', 'la foto de una factura se sube como .jpg o .pdf, nada más');
select is(pg_temp.q(pg_temp.u(408), format('select count(*) from purchasing.invoiceable_orders(%L) where status = %L',
                                           pg_temp.u(203), 'closed')),
          '0', 'una OC facturada entera (cerrada) no se ofrece');
select is(pg_temp.q(pg_temp.u(411), format('select count(*) from purchasing.invoiceable_orders(%L)', pg_temp.u(202))),
          '0', 'el gerente no carga facturas: no se le ofrecen órdenes');

-- ---------------------------------------------------------------------------
-- Qué puede hacer cada uno en la ficha
-- ---------------------------------------------------------------------------
select is(pg_temp.access(408, 2001, 'can_edit'), 'true', 'Compras corrige una observada');
select is(pg_temp.access(408, 2001, 'can_approve'), 'false', 'pero no la da por conforme: la cargó');
select is(pg_temp.access(408, 2001, 'approve_blocked'),
          'La cargaste, la corregiste o le sumaste una nota: la da por conforme otra persona.', 'y se le dice por qué');
select is(pg_temp.access(407, 2001, 'can_approve'), 'true', 'el Controller la da por conforme');
select is(pg_temp.access(407, 2001, 'can_edit'), 'false', 'el Controller no la corrige');
select is(pg_temp.access(407, 4600, 'can_approve') || ' ' || pg_temp.access(407, 4600, 'approved_by_name'),
          'false Camila Costos', 'una conforme ya no se aprueba y dice quién la dio por conforme');
select is(pg_temp.access(409, 2001, 'can_edit'), null, 'el cocinero no ve la ficha');

-- ---------------------------------------------------------------------------
-- El origen de un precio de factura
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(407), format(
            'select string_agg(distinct label || %L || can_open, %L) from costing.price_origins(%L::uuid[])', ' ', ',',
            pg_temp.prices(4600))),
          (select purchasing.invoice_label(invoice_class, point_of_sale, number) || ' true'
             from purchasing.invoices where number = 4600),
          'el Controller ve de qué factura salió el precio y puede abrirla');
select is(pg_temp.q(pg_temp.u(404), format('select count(*) from costing.price_origins(%L::uuid[])',
                                           pg_temp.prices(4600))),
          '0', 'el gerente de otro local no ve el origen de esos precios');
select is(pg_temp.q(pg_temp.u(407), format('select count(*) from costing.price_origins(%L::uuid[])',
            (select array_agg(id) from (select id from costing.price_records where invoice_line_id is null limit 20) x))),
          '0', 'un precio cargado a mano no tiene factura de origen');

-- ---------------------------------------------------------------------------
-- Los textos del control escriben la plata y las cantidades como se leen acá
-- ---------------------------------------------------------------------------
select is(purchasing.money_text(3403) || ' | ' || purchasing.money_text(-1234567.891), '$ 3.403,00 | -$ 1.234.567,89',
          'la plata, con punto de miles y coma decimal, a centavos');
select is(purchasing.money_text(-0.004), '$ 0,00', 'lo que redondea a cero no lleva signo');
select is(purchasing.number_text(2.5) || ' | ' || purchasing.number_text(1250) || ' | ' || purchasing.number_text(0.462),
          '2,5 | 1.250 | 0,462', 'las cantidades, sin ceros de más');
select ok(not exists (select 1 from purchasing.invoice_checks where explanation ~ '\d\.\d{4}'),
          'ningún control del seed muestra un número como lo guarda la base');

select * from finish();
rollback;
