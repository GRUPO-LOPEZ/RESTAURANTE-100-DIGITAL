-- Fase 2 · Etapa 2.3, PR 1: rendimiento del motor de costos (ADR-0032). 300 recetas en 4 locales: 30 preparaciones
-- en 3 cadenas de 10 niveles y 270 platos de 8 materias primas y una preparación. Leer el costo de un local tiene que
-- tardar menos de 300 ms. También se mide lo peor del recálculo: un precio de grupo de la materia prima que usan todas.
-- Aprobarlo solo anota un pedido; el recálculo lo hace la cola.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(9);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

-- 21 materias primas con precio de grupo. La 1 la usan todas las recetas, y la 21 solo los platos.
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
select pg_temp.u(70000 + n), pg_temp.u(1), 'CARGA-COSTO-' || n, 'Materia prima de carga ' || n, pg_temp.u(707),
       (select id from catalog.units where code = 'g')
  from generate_series(1, 21) n;
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
select pg_temp.u(71000 + n), pg_temp.u(1), 'CARGA-COSTO-P-' || n, pg_temp.u(70000 + n), 'Producto de carga ' || n,
       (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g')
  from generate_series(1, 21) n;
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
select pg_temp.u(1), pg_temp.u(71000 + n), 'group', current_date - 5, 1000 + n, 'no_invoice', 'test_value'
  from generate_series(1, 21) n;

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

create temporary table timings (k text primary key, ms numeric);
grant select, insert on timings to authenticated;
do $$
declare
  t0 timestamptz := clock_timestamp();
begin
  perform costing.refresh_recipes(array(select pg_temp.u(72000 + n) from generate_series(1, 300) n), null, 'publish');
  insert into timings values ('todo', extract(epoch from clock_timestamp() - t0) * 1000);
end
$$;
select is((select count(*) from costing.recipe_cost_current where recipe_id in (select pg_temp.u(72000 + n) from generate_series(1, 300) n)),
  1200::bigint, 'las 300 recetas, en los 4 locales');
analyze costing.recipe_cost_current;
analyze costing.recipe_cost_snapshots;
analyze recipes.recipe_components;
analyze recipes.component_base_quantities;

-- Leer los costos de un local, como lo hace una lista.
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(407), 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
do $$
declare
  t0 timestamptz := clock_timestamp();
  v  integer;
begin
  select count(*) into v
    from (select c.recipe_id, c.total_cost, c.cost_per_portion, c.reliability, r.name
            from costing.recipe_cost_current c
            join recipes.recipes r on r.id = c.recipe_id
           where c.restaurant_id = '00000000-0000-4000-8000-000000000201'
           order by r.name
           limit 500) x;
  insert into timings values ('lectura', extract(epoch from clock_timestamp() - t0) * 1000);
  if v < 300 then
    raise exception 'Se esperaban al menos 300 costos y salieron %', v;
  end if;
end
$$;
reset role;
select set_config('request.jwt.claims', '', true);
select cmp_ok((select ms from timings where k = 'lectura'), '<', 300::numeric, 'leer los costos de un local tarda menos de 300 ms');

-- Lo peor: un precio de grupo de la materia prima que usan las 300 recetas, en los 4 locales.
do $$
declare
  t0 timestamptz := clock_timestamp();
begin
  insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
  values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000071001', 'group', recipes.today(), 3000, 'no_invoice', 'test_value');
  insert into timings values ('precio', extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  perform costing.process_recalc_queue(1000);
  insert into timings values ('cola', extract(epoch from clock_timestamp() - t0) * 1000);
end
$$;
select diag('Recálculo completo: ' || (select round(ms) from timings where k = 'todo') || ' ms. Lectura: ' ||
            (select round(ms) from timings where k = 'lectura') || ' ms. Aprobar el precio: ' || (select round(ms) from timings where k = 'precio') || ' ms. Cola: ' ||
            (select round(ms) from timings where k = 'cola') || ' ms.');
select ok((select count(*) from costing.recipe_cost_snapshots where reason = 'price_change'
            and recipe_id in (select pg_temp.u(72000 + n) from generate_series(1, 300) n)) = 1200, 'el precio recalculó las 1.200 combinaciones');
select cmp_ok((select ms from timings where k = 'cola'), '<', 20000::numeric, 'la cola lo procesó en menos de 20 s');
select cmp_ok((select ms from timings where k = 'precio'), '<', 300::numeric, 'y aprobar el precio tardó menos de 300 ms');

-- Un escenario sobre esa misma materia prima: se calcula al abrirlo, y alcanza a las 300 recetas del local.
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(407), 'role', 'authenticated', 'aal', 'aal2')::text, true);
set local role authenticated;
do $$
declare
  t0 timestamptz;
  v_scenario uuid := costing.create_scenario('00000000-0000-4000-8000-000000000201', 'Carga', 'Medir');
  v bigint;
begin
  perform costing.set_scenario_override(v_scenario, 'price', 'Medir', '00000000-0000-4000-8000-000000070001', null, 5);
  t0 := clock_timestamp();
  select max(r.total_rows) into v from costing.scenario_result(v_scenario, 50) r;
  insert into timings values ('escenario', extract(epoch from clock_timestamp() - t0) * 1000);
  insert into timings values ('escenario_recetas', v);
end
$$;
-- La materia prima de los platos: las preparaciones no cambian, pero cada una se calcula una sola vez.
do $$
declare
  t0 timestamptz;
  v_scenario uuid := costing.create_scenario('00000000-0000-4000-8000-000000000201', 'Solo platos', 'Medir');
  v bigint;
begin
  perform costing.set_scenario_override(v_scenario, 'price', 'Medir', '00000000-0000-4000-8000-000000070021', null, 5);
  t0 := clock_timestamp();
  select max(r.total_rows) into v from costing.scenario_result(v_scenario, 50) r;
  insert into timings values ('escenario_platos', extract(epoch from clock_timestamp() - t0) * 1000);
  insert into timings values ('escenario_platos_recetas', v);
end
$$;
reset role;
select set_config('request.jwt.claims', '', true);
select diag('Escenario: ' || (select round(ms) from timings where k = 'escenario') || ' ms. Solo platos: ' || (select round(ms) from timings where k = 'escenario_platos') || ' ms.');
select cmp_ok((select ms from timings where k = 'escenario_recetas'), '>=', 300::numeric, 'el escenario alcanza a las 300 recetas');
select cmp_ok((select ms from timings where k = 'escenario'), '<', 5000::numeric, 'y se calcula en menos de 5 s');
select cmp_ok((select ms from timings where k = 'escenario_platos_recetas'), '>=', 270::numeric, 'el escenario de los platos alcanza a los 270');
select cmp_ok((select ms from timings where k = 'escenario_platos'), '<', 5000::numeric, 'y las preparaciones que no cambian no lo frenan');

select * from finish();
rollback;
