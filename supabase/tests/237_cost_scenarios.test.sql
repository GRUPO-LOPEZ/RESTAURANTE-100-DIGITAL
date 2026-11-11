-- Fase 2 · Etapa 2.3, PR 3C: escenarios de costo (ADR-0032). Precio, proveedor, rendimiento y gramaje, con la cuenta a
-- mano; que lo oficial no se toque; y quién puede.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(97);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
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
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
-- Una materia prima que se usa en gramos y se compra por kg: el precio del envase es el precio por kg.
create function pg_temp.ing(p_n int) returns void language sql as $$
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values (pg_temp.u(95000 + p_n), pg_temp.u(1), 'COSTO-ING-' || p_n, 'Materia prima ' || p_n, pg_temp.u(707),
          (select id from catalog.units where code = 'g'));
  insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                         content_per_unit, content_unit_id)
  values (pg_temp.u(96000 + p_n), pg_temp.u(1), 'COSTO-PROD-' || p_n, pg_temp.u(95000 + p_n), 'Producto ' || p_n,
          (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g'));
$$;
-- Precios sin factura (el precio es el final), salvo que se pida factura con 21 %.
create function pg_temp.price(p_n int, p_price numeric, p_scope text default 'group', p_place int default null,
                              p_days_ago int default 1, p_invoice boolean default false)
returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, restaurant_id, valid_from, package_price,
                                     document_type, vat_rate, source)
  values (pg_temp.u(1), pg_temp.u(96000 + p_n), p_scope::core.scope_type,
          case when p_scope = 'brand' then pg_temp.u(p_place) end,
          case when p_scope = 'restaurant' then pg_temp.u(p_place) end,
          current_date - p_days_ago, p_price,
          case when p_invoice then 'invoice' else 'no_invoice' end::costing.price_document,
          case when p_invoice then 21 end, 'test_value')
$$;
create function pg_temp.yield(p_n int, p_process int, p_clean numeric, p_cook numeric) returns uuid language sql as $$
  insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, status,
                                                 approved_by, approved_at)
  values (pg_temp.u(1), pg_temp.u(95000 + p_n), pg_temp.u(p_process), p_clean, p_cook, 'approved', pg_temp.u(413), now())
  returning id
$$;
create function pg_temp.recipe(p_n int, p_kind text, p_yield numeric, p_unit text, p_portions int) returns void language sql as $$
  insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type, category_id)
  values (pg_temp.u(97000 + p_n), pg_temp.u(1), 'group', 'COSTO-REC-' || p_n, 'Receta ' || p_n, p_kind::recipes.recipe_type,
          -- Rubros (ADR-0038): un plato va en uno de menú (Pastas); el resto, en uno de sub-recetas (Salsas).
          case when p_kind = 'dish' then pg_temp.u(1062) else pg_temp.u(1061) end);
  insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
  values (pg_temp.u(98000 + p_n), pg_temp.u(1), pg_temp.u(97000 + p_n), 1, p_yield,
          (select id from catalog.units where code = p_unit), p_portions);
$$;
create function pg_temp.line(p_n int, p_order int, p_ing int, p_qty numeric, p_unit text, p_basis text default 'purchase',
                             p_profile uuid default null)
returns void language sql as $$
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id, quantity_basis,
                                         yield_profile_id)
  values (pg_temp.u(1), pg_temp.u(98000 + p_n), p_order, pg_temp.u(95000 + p_ing), p_qty,
          (select id from catalog.units where code = p_unit), p_basis::recipes.quantity_basis, p_profile)
$$;
create function pg_temp.sub(p_n int, p_order int, p_sub int, p_qty numeric, p_unit text) returns void language sql as $$
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
  values (pg_temp.u(1), pg_temp.u(98000 + p_n), p_order, pg_temp.u(97000 + p_sub), p_qty,
          (select id from catalog.units where code = p_unit), 'finished')
$$;
create function pg_temp.publish(p_n int) returns void language sql as $$
  update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(98000 + p_n);
  update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(98000 + p_n);
  update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(98000 + p_n);
$$;
create function pg_temp.assign(p_n int, p_rest int) returns void language sql as $$
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (pg_temp.u(1), pg_temp.u(97000 + p_n), pg_temp.u(p_rest), current_date - 1)
$$;
create function pg_temp.cost(p_n int, p_rest int, p_column text default 'total_cost') returns text language plpgsql as $$
declare
  v text;
begin
  perform costing.process_recalc_queue(1000);
  execute format('select %I::text from costing.recipe_cost_current where recipe_id = $1 and restaurant_id = $2 and deleted_at is null', p_column)
    into v using pg_temp.u(97000 + p_n), pg_temp.u(p_rest);
  return v;
end
$$;
create function pg_temp.line_status(p_n int, p_rest int) returns text language sql as $$
  select string_agg(l.status, ',' order by l.line_order)
    from costing.recipe_line_costs_internal(pg_temp.u(98000 + p_n), pg_temp.u(p_rest), current_date) l
$$;

create function pg_temp.new_scenario(p_user int, p_rest int) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select costing.create_scenario(%L, ''Prueba'', ''Simular'')::text', pg_temp.u(p_rest)))
$$;
create temporary table sc (k text primary key, id uuid);
grant select on sc to authenticated;
create function pg_temp.s(p_k text) returns uuid language sql as $$ select id from sc where k = p_k $$;
create function pg_temp.simulated(p_user int, p_k text, p_n int) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select cost_today::numeric(18,2) || ''/'' || cost_simulated::numeric(18,2) || ''/'' || difference::numeric(18,2) || ''/'' || coalesce(difference_pct::text, ''-'')
     from costing.scenario_result(%L) where recipe_id = %L', pg_temp.s(p_k), pg_temp.u(97000 + p_n)))
$$;
create function pg_temp.set_price(p_k text, p_ing int, p_cost numeric) returns text language sql as $$
  select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, %s)::text', pg_temp.s(p_k), pg_temp.u(95000 + p_ing), p_cost))
$$;

-- Una materia prima a 1 $/g. Plato directo de 1.000 g; una preparación de 1.000 g y un plato con 100 g de ella.
select pg_temp.ing(1);
select pg_temp.price(1, 1000);
select pg_temp.ing(2);
select pg_temp.price(2, 2000);
create temporary table profiles (k text primary key, id uuid);
insert into profiles values ('limpia', pg_temp.yield(2, 961, 0.8, 1));
select pg_temp.recipe(1, 'dish', 1000, 'g', 4);
select pg_temp.line(1, 1, 1, 1000, 'g');
select pg_temp.publish(1);
select pg_temp.recipe(2, 'preparation', 1000, 'g', null);
select pg_temp.line(2, 1, 1, 1000, 'g');
select pg_temp.publish(2);
select pg_temp.recipe(3, 'dish', 1, 'unit', 1);
select pg_temp.sub(3, 1, 2, 100, 'g');
select pg_temp.publish(3);
-- 800 g limpios con rendimiento 80 %: 1.000 g comprados, a 2 $/g.
select pg_temp.recipe(4, 'dish', 1000, 'g', 1);
select pg_temp.line(4, 1, 2, 800, 'g', 'clean', (select id from profiles where k = 'limpia'));
select pg_temp.publish(4);
select pg_temp.assign(1, 201);
select pg_temp.assign(3, 201);
select pg_temp.assign(4, 201);
select is(pg_temp.cost(1, 201) || '/' || pg_temp.cost(3, 201) || '/' || pg_temp.cost(4, 201), '1000.0000/100.0000/2000.0000', 'de partida');

insert into sc select 'a', pg_temp.new_scenario(407, 201)::uuid;
select is((select name from costing.cost_scenarios where id = pg_temp.s('a')), 'Prueba', 'el Controller crea un escenario');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_result(%L)', pg_temp.s('a'))), '0', 'sin cambios, no hay resultado');

-- Lo oficial, antes de simular.
create temporary table official as
  select (select count(*) from costing.recipe_cost_snapshots) as snapshots,
         (select count(*) from costing.cost_recalc_queue) as queue,
         (select count(*) from integration.integration_outbox) as events,
         (select md5(string_agg(c::text, ',' order by c.id)) from costing.recipe_cost_current c) as current_costs;

-- Precio: de 1 a 2 $/g.
select pg_temp.set_price('a', 1, 2);
select is(pg_temp.simulated(407, 'a', 1), '1000.00/2000.00/1000.00/100.00', 'precio: de $ 1.000 a $ 2.000');
select is(pg_temp.simulated(407, 'a', 3), '100.00/200.00/100.00/100.00', 'llega al plato a través de la preparación');
select is(pg_temp.simulated(407, 'a', 4), null, 'una receta que no lo usa no aparece');
select is(pg_temp.q(pg_temp.u(407), format('select portion_simulated::numeric(18,2)::text from costing.scenario_result(%L) where recipe_id = %L', pg_temp.s('a'), pg_temp.u(97001))),
  '500.00', 'también por porción');
-- Cargar otro precio reemplaza al anterior.
select pg_temp.set_price('a', 1, 3);
select is(pg_temp.simulated(407, 'a', 1), '1000.00/3000.00/2000.00/200.00', 'el precio nuevo reemplaza al anterior');
select is((select count(*) from costing.cost_scenario_overrides where scenario_id = pg_temp.s('a') and deleted_at is null), 1::bigint, 'queda un solo cambio vigente');

-- Sin cambio real: simulado igual a hoy.
insert into sc select 'f', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.set_price('f', 1, 1);
select is(pg_temp.simulated(407, 'f', 1), '1000.00/1000.00/0.00/0.00', 'el mismo precio de hoy: simulado igual a hoy');
select is(pg_temp.q(pg_temp.u(407), format('select changed_rows::text from costing.scenario_result(%L) limit 1', pg_temp.s('f'))), '0', 'y ninguna receta cambia');

-- Las tarjetas miran todas las recetas, aunque la página traiga una sola.
insert into sc select 'g', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.set_price('g', 1, 2);
select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 1)::text', pg_temp.s('g'), pg_temp.u(95002)));
select is(pg_temp.q(pg_temp.u(407), format('select total_rows || ''/'' || changed_rows || ''/'' || top_rise::numeric(18,2) || ''/'' || top_drop::numeric(18,2) from costing.scenario_result(%L, 1)', pg_temp.s('g'))),
  '4/4/1000.00/-1000.00', 'tres platos y la preparación: mayor suba y mayor baja, con una página de una fila');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_result(%L, 1)', pg_temp.s('g'))), '1', 'la página trae una');

-- Las opciones para elegir.
select is(pg_temp.q(pg_temp.u(407), format('select unit_cost::numeric(18,2)::text from costing.scenario_ingredients(%L) where id = %L', pg_temp.s('a'), pg_temp.u(95001))), '1.00', 'la materia prima trae su costo de hoy');
select ok(pg_temp.q(pg_temp.u(407), format('select string_agg(name, '','') from costing.scenario_recipes(%L)', pg_temp.s('a'))) is not null, 'y hay recetas para elegir');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_recipe_lines(%L, %L)', pg_temp.s('a'), pg_temp.u(97001))), '1', 'con sus líneas');
select is(pg_temp.q(pg_temp.u(407), format('select unit from costing.scenario_recipe_lines(%L, %L)', pg_temp.s('a'), pg_temp.u(97001))), 'g', 'y la unidad como se muestra');
select ok(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.scenario_ingredients(%L)', pg_temp.s('a'))) like 'ERROR%No tenés permiso%', 'el Gerente no ve las materias primas del escenario');

-- Un proveedor se simula como un precio.
insert into sc select 'b', pg_temp.new_scenario(407, 201)::uuid;
select is(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Otro proveedor'', %L, null, 1.5, (select id from catalog.suppliers limit 1))::text', pg_temp.s('b'), pg_temp.u(95001))), '', 'con un proveedor de referencia');
select is(pg_temp.simulated(407, 'b', 1), '1000.00/1500.00/500.00/50.00', 'el proveedor es un precio: $ 1.500');
select ok(pg_temp.q(pg_temp.u(407), format('select supplier from costing.scenario_changes(%L)', pg_temp.s('b'))) is not null, 'y se ve cuál es');

-- Rendimiento: con 50 %, 800 g limpios son 1.600 g comprados: $ 3.200.
insert into sc select 'c', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''yield'', ''Simular'', %L, null, null, null, 0.5, 1)::text', pg_temp.s('c'), pg_temp.u(95002)));
select is(pg_temp.simulated(407, 'c', 4), '2000.00/3200.00/1200.00/60.00', 'rendimiento: 800 g / 0,5 × 2 $/g');

-- Gramaje: el plato baja de 1.000 g a 500 g.
insert into sc select 'd', pg_temp.new_scenario(407, 201)::uuid;
create function pg_temp.line_id(p_n int) returns uuid language sql as $$
  select c.id from recipes.recipe_components c where c.recipe_version_id = pg_temp.u(98000 + p_n) limit 1
$$;
select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''quantity'', ''Simular'', null, %L, null, null, null, null, 500)::text', pg_temp.s('d'), pg_temp.line_id(1)));
select is(pg_temp.simulated(407, 'd', 1), '1000.00/500.00/-500.00/-50.00', 'gramaje: de 1.000 g a 500 g');
select is(pg_temp.simulated(407, 'd', 3), null, 'otra receta con la misma materia prima no cambia');

-- Gramaje de una preparación: llega al plato, y la merma va una sola vez.
insert into sc select 'e', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''quantity'', ''Simular'', null, %L, null, null, null, null, 2000)::text', pg_temp.s('e'), pg_temp.line_id(2)));
select is(pg_temp.simulated(407, 'e', 3), '100.00/200.00/100.00/100.00', 'el gramaje de una preparación llega al plato');

-- Una preparación que no se calculó antes (por ejemplo, una que la persona no ve) también recibe el cambio.
select is((select round(total_cost, 2) from costing.recipe_totals_internal(pg_temp.u(98003), pg_temp.u(201), current_date,
            jsonb_build_object('quantities', jsonb_build_object(pg_temp.line_id(2)::text, 2000)))), 200.00, 'el cambio baja por la recursión');

-- Lo oficial no se tocó.
select is((select snapshots from official), (select count(*) from costing.recipe_cost_snapshots), 'simular no saca fotos');
select is((select queue from official) + 0, (select count(*) from costing.cost_recalc_queue), 'no anota pedidos');
select is((select events from official), (select count(*) from integration.integration_outbox), 'no emite eventos');
select is((select current_costs from official), (select md5(string_agg(c::text, ',' order by c.id)) from costing.recipe_cost_current c), 'y no cambia el costo vigente');
select is(pg_temp.cost(1, 201), '1000.0000', 'el costo oficial sigue igual');
select is((select provolatile from pg_proc where oid = 'costing.scenario_result(uuid, integer, integer)'::regprocedure), 's', 'la función del resultado solo lee (stable)');
-- El motor sin esas claves da lo mismo.
select is((select round(total_cost, 2) from costing.recipe_totals_internal(pg_temp.u(98004), pg_temp.u(201), current_date)), 2000.00, 'el motor oficial da lo mismo');

-- Quién puede. 402 Dirección, 403 Directora de Pastas, 404 Gerente, 405 Chef, 406 Jefe de Cocina, 408 Compras, 409 Cocinera.
select ok(pg_temp.new_scenario(402, 201) !~ '^ERROR', 'Dirección crea escenarios');
select ok(pg_temp.new_scenario(403, 201) !~ '^ERROR', 'la Directora, en su marca');
select ok(pg_temp.new_scenario(403, 203) like 'ERROR%No tenés permiso%', 'pero no en otra marca');
select ok(pg_temp.new_scenario(404, 201) like 'ERROR%No tenés permiso%', 'el Gerente no');
select ok(pg_temp.new_scenario(405, 201) like 'ERROR%No tenés permiso%', 'el Chef no');
select ok(pg_temp.new_scenario(406, 201) like 'ERROR%No tenés permiso%', 'el Jefe de Cocina no');
select ok(pg_temp.new_scenario(408, 201) like 'ERROR%No tenés permiso%', 'Compras no');
select ok(pg_temp.new_scenario(409, 201) like 'ERROR%No tenés permiso%', 'la Cocinera no');
-- Lo que nadie sin permiso puede hacer con un escenario: %1 escenario, %2 cambio, %3 línea, %4 materia prima, %5 receta.
create temporary table ops (n int primary key, name text, sql text);
insert into ops values
  (1, 'cargar un cambio', $q$select costing.set_scenario_override(%1$L, 'price', 'x', %4$L, null, 9)::text$q$),
  (2, 'quitar un cambio', $q$select costing.remove_scenario_override(%2$L, 'x')::text$q$),
  (3, 'archivar', $q$select costing.archive_scenario(%1$L, 'x')::text$q$),
  (4, 'ver el resultado', $q$select count(*)::text from costing.scenario_result(%1$L)$q$),
  (5, 'ver los cambios', $q$select count(*)::text from costing.scenario_changes(%1$L)$q$),
  (6, 'ver las materias primas', $q$select count(*)::text from costing.scenario_ingredients(%1$L)$q$),
  (7, 'ver las recetas', $q$select count(*)::text from costing.scenario_recipes(%1$L)$q$),
  (8, 'ver las líneas', $q$select count(*)::text from costing.scenario_recipe_lines(%1$L, %5$L)$q$);
create function pg_temp.denied(p_users int[], p_k text, p_sql text) returns boolean language sql as $$
  select bool_and(pg_temp.q(pg_temp.u(x), format(p_sql, pg_temp.s(p_k),
           (select o.id from costing.cost_scenario_overrides o where o.scenario_id = pg_temp.s(p_k) and o.deleted_at is null limit 1),
           null, pg_temp.u(95001), pg_temp.u(97001))) like 'ERROR%No tenés permiso%')
    from unnest(p_users) x
$$;
insert into sc select 'otra', pg_temp.new_scenario(402, 203)::uuid;
select pg_temp.set_price('otra', 1, 2);
select ok(pg_temp.denied(array[404, 405, 406, 408, 409], 'a', sql), 'Gerente, Chef, Jefe de Cocina, Compras y Cocinera no pueden ' || name) from ops order by n;
select ok(pg_temp.denied(array[403], 'otra', sql), 'la Directora de otra marca no puede ' || name) from ops order by n;
select ok(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.scenario_result(%L)', pg_temp.s('a'))) like 'ERROR%No tenés permiso%', 'el Gerente no ve el resultado');
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from costing.cost_scenarios'), '0', 'ni la lista');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.cost_scenarios where id = %L', pg_temp.s('a'))), '1', 'el Controller sí');
select ok(not has_table_privilege('authenticated', 'costing.cost_scenario_overrides', 'select'), 'los cambios se leen por función');
select ok(pg_temp.q(pg_temp.u(402), format('update costing.cost_scenarios set name = ''x'' where id = %L returning 1', pg_temp.s('a'))) like 'ERROR%permission denied%', 'nadie escribe directo');
select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'costing' and c.relname in ('cost_scenarios', 'cost_scenario_overrides') and c.relrowsecurity), 2::bigint, 'RLS activo');

-- Datos inválidos.
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 0)::text', pg_temp.s('a'), pg_temp.u(95001))) like 'ERROR%mayor que cero%', 'un precio de cero se rechaza');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''yield'', ''Simular'', %L, null, null, null, 2, 1)::text', pg_temp.s('a'), pg_temp.u(95001))) like 'ERROR%hasta 100%', 'un rendimiento de más de 100 % también');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 10000000000000)::text', pg_temp.s('a'), pg_temp.u(95001))) like 'ERROR%mil millones%', 'un valor gigante se explica');
select throws_ok(format($q$insert into costing.cost_scenario_overrides (group_id, restaurant_id, scenario_id, kind, ingredient_id, unit_cost, cleaning_yield)
                           values (%L, %L, %L, 'price', %L, 2, 0.5)$q$, pg_temp.u(1), pg_temp.u(201), pg_temp.s('a'), pg_temp.u(95001)), '23514', null, 'un precio no lleva rendimiento');
select throws_ok(format($q$insert into costing.cost_scenario_overrides (group_id, restaurant_id, scenario_id, kind, ingredient_id, unit_cost)
                           values (%L, %L, %L, 'price', %L, 2)$q$, pg_temp.u(1), pg_temp.u(203), pg_temp.s('a'), pg_temp.u(95002)), '23503', null, 'y un cambio es del local de su escenario');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''quantity'', ''Simular'', null, %L, null, null, null, null, 5)::text', pg_temp.s('a'), pg_temp.u(99999))) like 'ERROR%línea de una receta vigente%', 'una línea que no existe también');
-- Una línea real, de una receta que este local no usa.
select pg_temp.recipe(5, 'dish', 1000, 'g', 1);
select pg_temp.line(5, 1, 1, 100, 'g');
select pg_temp.publish(5);
select pg_temp.assign(5, 203);
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''quantity'', ''Simular'', null, %L, null, null, null, null, 5)::text', pg_temp.s('a'), pg_temp.line_id(5))) like 'ERROR%línea de una receta vigente%', 'una línea de otro local también');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_recipe_lines(%L, %L)', pg_temp.s('a'), pg_temp.u(97005))), '0', 'y sus líneas no se listan');
-- Materia prima y proveedor de otro grupo.
insert into org.groups (id, name) values (pg_temp.u(2), 'Otro Grupo');
insert into catalog.ingredient_categories (id, group_id, name) values (pg_temp.u(95901), pg_temp.u(2), 'Otra categoría');
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
values (pg_temp.u(95900), pg_temp.u(2), 'COSTO-ING-OTRO', 'Materia prima ajena', pg_temp.u(95901), (select id from catalog.units where code = 'g'));
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 5)::text', pg_temp.s('a'), pg_temp.u(95900))) like 'ERROR%materia prima del grupo%', 'una materia prima de otro grupo también');
insert into catalog.suppliers (id, group_id, code, name) values (pg_temp.u(95902), pg_temp.u(2), 'COSTO-PROV-OTRO', 'Proveedor ajeno');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 5, %L)::text', pg_temp.s('a'), pg_temp.u(95001), pg_temp.u(95902))) like 'ERROR%proveedor del grupo%', 'y un proveedor de otro grupo');

-- Auditoría y archivo.
select ok(exists (select 1 from audit.audit_events where table_name = 'cost_scenario_overrides' and action::text = 'insert'), 'los cambios quedan en la auditoría');
select is((select count(*) from audit.audit_events where table_name = 'cost_scenario_overrides' and (scope_restaurant_id is null or scope_brand_id is null)), 0::bigint, 'con su local y su marca');
select ok(exists (select 1 from audit.audit_events where table_name = 'cost_scenario_overrides' and scope_restaurant_id = pg_temp.u(203)), 'cada uno, el de su escenario');

select is((select reason || '/' || source || '/' || actor_user_id from audit.audit_events where table_name = 'cost_scenario_overrides' and action::text = 'insert' order by sequence_number limit 1),
  'Simular/manual/' || pg_temp.u(407), 'con el motivo, el origen y quién');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', '''', %L, null, 5)::text', pg_temp.s('a'), pg_temp.u(95001))) like 'ERROR%', 'sin motivo no se carga');

-- Quitar un cambio.
insert into sc select 'h', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.set_price('h', 1, 2);
create temporary table removed as select id from costing.cost_scenario_overrides where scenario_id = pg_temp.s('h');
grant select on removed to authenticated;
select is(pg_temp.q(pg_temp.u(407), format('select costing.remove_scenario_override(%L, ''Ya no'')::text', (select id from removed))), '', 'un cambio se quita');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_changes(%L)', pg_temp.s('h'))), '0', 'y deja de verse');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_result(%L)', pg_temp.s('h'))), '0', 'y de contar');
select is((select count(*) from costing.cost_scenario_overrides where id = (select id from removed) and deleted_at is not null), 1::bigint, 'pero sigue en la base');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.remove_scenario_override(%L, ''Otra vez'')::text', (select id from removed))) like 'ERROR%No tenés permiso%', 'quitarlo dos veces se rechaza');
select is(pg_temp.q(pg_temp.u(407), format('select costing.archive_scenario(%L, ''Listo'')::text', pg_temp.s('b'))), '', 'se archiva');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 2)::text', pg_temp.s('b'), pg_temp.u(95001))) like 'ERROR%archivado%', 'y ya no se cambia');
select is((select count(*) from costing.cost_scenarios where id = pg_temp.s('b')), 1::bigint, 'pero sigue ahí');
select ok(exists (select 1 from audit.audit_events e where e.table_name = 'cost_scenarios' and e.action::text = 'update' and e.record_id = pg_temp.s('b')), 'y archivar queda en la auditoría');

-- Una receta sin costo hoy que pasa a tener costo simulado también cambia.
select pg_temp.ing(3);
select pg_temp.recipe(6, 'dish', 1000, 'g', 1);
select pg_temp.line(6, 1, 3, 1000, 'g');
select pg_temp.publish(6);
select pg_temp.assign(6, 201);
select pg_temp.cost(6, 201);
insert into sc select 'j', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.set_price('j', 3, 1);
select is(pg_temp.q(pg_temp.u(407), format('select coalesce(cost_today::text, ''sin costo'') || ''/'' || cost_simulated::numeric(18,2) || ''/'' || changed_rows from costing.scenario_result(%L)', pg_temp.s('j'))),
  'sin costo/1000.00/1', 'de sin costo a con costo cuenta como cambio');

-- Una preparación que no cambia se calcula para el plato, y no se lista.
select pg_temp.recipe(7, 'dish', 1, 'unit', 1);
select pg_temp.line(7, 1, 2, 100, 'g');
select pg_temp.sub(7, 2, 2, 100, 'g');
select pg_temp.publish(7);
select pg_temp.assign(7, 201);
select pg_temp.cost(7, 201);
insert into sc select 'k', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.set_price('k', 2, 3);
select is(pg_temp.simulated(407, 'k', 7), '300.00/400.00/100.00/33.33', 'el plato cambia, con la preparación que no cambia adentro');
select is(pg_temp.simulated(407, 'k', 2), null, 'y esa preparación no aparece');

-- Un gramaje que quedó en una versión vieja se avisa y no se aplica.
alter table recipes.recipe_versions disable trigger user;
update recipes.recipe_versions set status = 'archived' where id = pg_temp.u(98001);
alter table recipes.recipe_versions enable trigger user;
select is(pg_temp.q(pg_temp.u(407), format('select applies::text from costing.scenario_changes(%L)', pg_temp.s('d'))), 'false', 'un gramaje de una versión vieja se avisa');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.scenario_result(%L)', pg_temp.s('d'))), '0', 'y no se aplica');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.remove_scenario_override(%L, ''x'')::text', (select id from costing.cost_scenario_overrides where scenario_id = pg_temp.s('b') and deleted_at is null limit 1))) like 'ERROR%archivado%', 'un escenario archivado tampoco deja quitar cambios');

-- Un rol ajustado desde el panel, sin ver precios: el costo de hoy de la materia prima no sale.
do $$
begin
  perform core.set_change_context('Prueba: rol ajustado', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = 'controller')
     and permission_id = (select id from core.permissions where code = 'prices.view');
end
$$;
select is(pg_temp.q(pg_temp.u(407), format('select coalesce(unit_cost::text, ''oculto'') from costing.scenario_ingredients(%L) where id = %L', pg_temp.s('a'), pg_temp.u(95001))), 'oculto', 'sin ver precios no ve el costo de hoy');

-- Un rol ajustado desde el panel: maneja escenarios y ve costos, pero no las recetas ni el catálogo.
insert into sc select 'i', pg_temp.new_scenario(407, 201)::uuid;
select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''quantity'', ''Simular'', null, %L, null, null, null, null, 2000)::text', pg_temp.s('i'), pg_temp.line_id(2)));
select pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''price'', ''Simular'', %L, null, 2, (select id from catalog.suppliers limit 1))::text', pg_temp.s('i'), pg_temp.u(95001)));
do $$
begin
  perform core.set_change_context('Prueba: rol ajustado', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = 'controller')
     and permission_id in (select id from core.permissions where code = 'catalog.view' or (code like 'recipes.%' and code <> 'recipes.view_costs'));
end
$$;
select is(pg_temp.q(pg_temp.u(407), format('select recipe || ''/'' || item || ''/'' || coalesce(original_quantity::text, ''-'') from costing.scenario_changes(%L) where kind = ''quantity''', pg_temp.s('i'))),
  'Receta no disponible/No disponible/-', 'un gramaje de una receta que ya no ve se tapa');
select is(pg_temp.q(pg_temp.u(407), format('select item || ''/'' || supplier from costing.scenario_changes(%L) where kind = ''price''', pg_temp.s('i'))),
  'No disponible/No disponible', 'igual que la materia prima y el proveedor sin ver el catálogo');
select ok(pg_temp.q(pg_temp.u(407), format('select costing.set_scenario_override(%L, ''quantity'', ''Simular'', null, %L, null, null, null, null, 5)::text', pg_temp.s('i'), pg_temp.line_id(4))) like 'ERROR%línea de una receta vigente%', 'y no puede simular una línea de una receta que no ve');

select * from finish();
rollback;
