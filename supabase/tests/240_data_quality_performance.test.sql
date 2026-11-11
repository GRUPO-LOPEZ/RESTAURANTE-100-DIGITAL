-- Fase 2 · Etapa 2.5: rendimiento de la calidad de datos (ADR-0033). El volumen de 233 (300 recetas en 4 locales), con 500
-- materias primas en familias de 10 nombres parecidos: leer los indicadores de un local tiene que tardar menos de 300 ms.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(11);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

-- 500 materias primas con precio de grupo; las recetas usan las primeras 21.
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
select pg_temp.u(70000 + n), pg_temp.u(1), 'CARGA-COSTO-' || n, 'Familia ' || substr(md5((n / 10)::text), 1, 8) || ' variante ' || n % 10, pg_temp.u(707),
       (select id from catalog.units where code = 'g')
  from generate_series(1, 500) n;
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
select pg_temp.u(71000 + n), pg_temp.u(1), 'CARGA-COSTO-P-' || n, pg_temp.u(70000 + n), 'Producto de carga ' || n,
       (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g')
  from generate_series(1, 500) n;
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
select pg_temp.u(1), pg_temp.u(71000 + n), 'group', current_date - 5, 1000 + n, 'no_invoice', 'test_value'
  from generate_series(1, 500) n;

-- Las recetas se cargan sin recalcular, y después se calculan todas juntas.
alter table recipes.recipe_versions disable trigger recalculate_costs;
alter table recipes.recipe_assignments disable trigger recalculate_costs;

insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type, category_id)
select pg_temp.u(72000 + n), pg_temp.u(1), 'group', 'CARGA-REC-' || n, 'Receta de carga ' || n,
       case when n <= 30 then 'preparation' else 'dish' end::recipes.recipe_type,
       -- Rubros (ADR-0038): las preparaciones en Salsas (sub-recetas) y los platos en Pastas (menú).
       case when n <= 30 then pg_temp.u(1061) else pg_temp.u(1062) end
  from generate_series(1, 300) n;
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
select pg_temp.u(73000 + n), pg_temp.u(1), pg_temp.u(72000 + n), 1, 1000, (select id from catalog.units where code = 'g'),
       case when n > 30 then 4 end
  from generate_series(1, 300) n;
-- Materias primas: las preparaciones llevan 2, los platos 8. Siempre la 1.
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select pg_temp.u(1), pg_temp.u(73000 + n), k, pg_temp.u(70000 + case when k = 1 then 1 else 1 + (n + k) % 19 + 1 end), 100,
       (select id from catalog.units where code = 'g')
  from generate_series(1, 300) n
  cross join generate_series(1, 8) k
 where k <= case when n <= 30 then 2 else 8 end;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select pg_temp.u(1), pg_temp.u(73000 + n), 9, pg_temp.u(70021), 100, (select id from catalog.units where code = 'g')
  from generate_series(31, 300) n;
-- Cadenas: cada preparación usa la anterior de su cadena (10 niveles); cada plato, la de arriba de una cadena.
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select pg_temp.u(1), pg_temp.u(73000 + n), 20, pg_temp.u(72000 + n - 1), 100, (select id from catalog.units where code = 'g'), 'finished'
  from generate_series(1, 30) n where (n - 1) % 10 <> 0;
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select pg_temp.u(1), pg_temp.u(73000 + n), 20, pg_temp.u(72000 + 10 * (1 + n % 3)), 100, (select id from catalog.units where code = 'g'), 'finished'
  from generate_series(31, 300) n;
update recipes.recipe_versions set status = 'in_review' where id in (select pg_temp.u(73000 + n) from generate_series(1, 300) n);
update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id in (select pg_temp.u(73000 + n) from generate_series(1, 300) n);
update recipes.recipe_versions set status = 'published', published_at = now() where id in (select pg_temp.u(73000 + n) from generate_series(1, 300) n);
select recipes.freeze_base_quantities(pg_temp.u(73000 + n)) from generate_series(1, 300) n;
insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
select pg_temp.u(1), pg_temp.u(72000 + n), pg_temp.u(200 + r), current_date - 1
  from generate_series(31, 300) n cross join generate_series(1, 4) r;

alter table recipes.recipe_versions enable trigger recalculate_costs;
alter table recipes.recipe_assignments enable trigger recalculate_costs;


analyze catalog.ingredients;
create temporary table timings (k text primary key, ms numeric);
grant select, insert on timings to authenticated;
do $$
begin
  perform costing.refresh_recipes(array(select pg_temp.u(72000 + n) from generate_series(1, 300) n), null, 'publish');
end
$$;
-- Un precio nuevo de la materia prima que usan todas: el tablero compara contra la foto anterior.
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(1), pg_temp.u(71001), 'group', recipes.today(), 5000, 'no_invoice', 'test_value');
select costing.process_recalc_queue(5000);
analyze costing.recipe_cost_snapshots;
create temporary table twin_start as select clock_timestamp() as t0;
refresh materialized view reporting.mv_ingredient_twins;
insert into timings select 'parecidos', extract(epoch from clock_timestamp() - t0) * 1000 from twin_start;
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(407), 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
do $$
declare
  t0 timestamptz;
  v bigint;
  best numeric;
begin
  -- La primera lectura calienta el plan, y se toma la mejor de tres: se mide la consulta, no la carga de la máquina.
  perform count(*) from costing.data_quality('00000000-0000-4000-8000-000000000201');
  best := null;
  for i in 1..3 loop
    t0 := clock_timestamp();
    select max(total) into v from costing.data_quality('00000000-0000-4000-8000-000000000201');
    best := least(best, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  insert into timings values ('local', best), ('materias', v);
  select total into v from costing.data_quality('00000000-0000-4000-8000-000000000201') where indicator = 'recipe_approved';
  insert into timings values ('recetas', v);
  best := null;
  for i in 1..3 loop
    t0 := clock_timestamp();
    perform count(*) from costing.home_board('00000000-0000-4000-8000-000000000201');
    best := least(best, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  insert into timings values ('tablero', best);
  select count(*) into v from costing.home_board('00000000-0000-4000-8000-000000000201') where section = 'price_affected';
  insert into timings values ('afectadas', v);
  best := null;
  for i in 1..3 loop
    t0 := clock_timestamp();
    select count(*) into v from costing.report_usage('00000000-0000-4000-8000-000000000201', 50);
    best := least(best, extract(epoch from clock_timestamp() - t0) * 1000);
  end loop;
  insert into timings values ('reporte', best), ('reporte_filas', v);
  t0 := clock_timestamp();
  perform count(*) from costing.data_quality_items('00000000-0000-4000-8000-000000000201', 'recipe_photo', 50);
  insert into timings values ('lista', extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  select count(distinct restaurant_id) into v from costing.data_quality_places();
  insert into timings values ('locales', extract(epoch from clock_timestamp() - t0) * 1000), ('cuantos', v);
end
$$;
reset role;
select set_config('request.jwt.claims', '', true);
select diag('Tablero: ' || (select round(ms) from timings where k = 'tablero') || ' ms. Reporte: ' || (select round(ms) from timings where k = 'reporte') || ' ms.');
select diag('Un local: ' || (select round(ms) from timings where k = 'local') || ' ms. Lista: ' || (select round(ms) from timings where k = 'lista')
            || ' ms. Todos los locales: ' || (select round(ms) from timings where k = 'locales') || ' ms. Parecidos, de noche: ' || (select round(ms) from timings where k = 'parecidos') || ' ms.');
select cmp_ok((select ms from timings where k = 'materias'), '>=', 500::numeric, 'se mide con las 500 materias primas');
select cmp_ok((select ms from timings where k = 'recetas'), '>=', 270::numeric, 'y con las recetas del local');
select cmp_ok((select ms from timings where k = 'cuantos'), '>=', 4::numeric, 'y los 4 locales');
select cmp_ok((select ms from timings where k = 'local'), '<', 300::numeric, 'los indicadores de un local, en menos de 300 ms');
select cmp_ok((select ms from timings where k = 'afectadas'), '>=', 5::numeric, 'el tablero se mide con recetas afectadas por un precio');
select cmp_ok((select ms from timings where k = 'reporte_filas'), '=', 50::numeric, 'un reporte trae su página');
select cmp_ok((select ms from timings where k = 'reporte'), '<', 300::numeric, 'en menos de 300 ms');
select cmp_ok((select ms from timings where k = 'tablero'), '<', 300::numeric, 'el tablero de Inicio, en menos de 300 ms');
select cmp_ok((select ms from timings where k = 'lista'), '<', 300::numeric, 'una lista, en menos de 300 ms');
select cmp_ok((select ms from timings where k = 'locales'), '<', 1200::numeric, 'y los 4 locales, en menos de 1,2 s');

select cmp_ok((select ms from timings where k = 'parecidos'), '<', 30000::numeric, 'y los parecidos de la noche, en menos de 30 s');

select * from finish();
rollback;
