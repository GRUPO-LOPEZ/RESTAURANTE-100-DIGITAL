-- Fase 2 · Etapa 2.1 C: rendimiento de los precios (ADR-0029). El precio vigente de 500 materias primas
-- para un local, con 5.000 precios cargados (varios por producto, en los tres niveles), por debajo
-- de 300 ms, como pide la regla de lectura para tableros. Las listas y tableros usan resolve_prices,
-- que resuelve todo en una sola consulta.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(2);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

-- 500 materias primas, con un producto cada una y 10 precios por producto (grupo, marca y local).
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
select pg_temp.u(50000 + n), pg_temp.u(1), 'CARGA-ING-' || n, 'Materia prima de carga ' || n, pg_temp.u(707),
       (select id from catalog.units where code = 'g')
  from generate_series(1, 500) n;
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
select pg_temp.u(60000 + n), pg_temp.u(1), 'CARGA-PROD-' || n, pg_temp.u(50000 + n), 'Producto de carga ' || n,
       (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g')
  from generate_series(1, 500) n;
insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, restaurant_id, valid_from, package_price,
                                   document_type, vat_rate, source)
select pg_temp.u(1), pg_temp.u(60000 + n),
       case k % 3 when 0 then 'group' when 1 then 'brand' else 'restaurant' end::core.scope_type,
       case when k % 3 = 1 then pg_temp.u(101 + n % 3) end,
       case when k % 3 = 2 then pg_temp.u(201 + n % 4) end,
       current_date - k * 7, 1000 + n + k, 'invoice', 21, 'test_value'
  from generate_series(1, 500) n cross join generate_series(1, 10) k;

-- Con estadísticas al día, como las mantiene el autovacuum en la base real.
analyze catalog.ingredients;
analyze catalog.purchase_products;
analyze costing.price_records;

create temporary table timings (ms numeric);
grant select, insert on timings to authenticated;
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(407), 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
do $$
declare
  t0 timestamptz := clock_timestamp();
  v  integer;
begin
  select count(*) into v
    from costing.resolve_prices('00000000-0000-4000-8000-000000000201') r
    join catalog.ingredients i on i.id = r.ingredient_id
   where i.code like 'CARGA-ING-%' and r.status = 'ok';
  insert into timings values (extract(epoch from clock_timestamp() - t0) * 1000);
  if v <> 500 then
    raise exception 'Se esperaban 500 precios y salieron %', v;
  end if;
end
$$;
reset role;

select ok(true, 'resuelve el precio de las 500 materias primas');
select cmp_ok((select ms from timings), '<', 300::numeric,
  format('el precio de 500 materias primas tarda menos de 300 ms (tardó %s ms)', (select round(ms) from timings)));

select * from finish();
rollback;
