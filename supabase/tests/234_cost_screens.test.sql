-- Fase 2 · Etapa 2.3, PR 2: lo que usan las pantallas de costos (ADR-0032): el estado de la cola y el impacto de un
-- precio. Quién los ve, que no salga el error de la cola ni otro local, y la cuenta del antes y el después.
-- Las fechas usan recipes.today() (hoy en la Argentina), como el motor de costos: con current_date (UTC), entre las 21 y
-- las 24 de la Argentina el precio quedaba vigente «desde mañana» y la prueba fallaba sin que nada estuviera mal.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(42);

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
          recipes.today() - p_days_ago, p_price,
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
  values (pg_temp.u(97000 + p_n), pg_temp.u(1), 'group', 'COSTO-REC-' || p_n, 'Receta ' || p_n, p_kind::recipes.recipe_type, pg_temp.u(1061));
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
  values (pg_temp.u(1), pg_temp.u(97000 + p_n), pg_temp.u(p_rest), recipes.today() - 1)
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
    from costing.recipe_line_costs_internal(pg_temp.u(98000 + p_n), pg_temp.u(p_rest), recipes.today()) l
$$;

-- El estado de la cola.
select is(pg_temp.q(pg_temp.u(407), 'select pending::text from costing.recalc_status()'), '0', 'sin cambios, nada pendiente');
select ok(pg_temp.q(pg_temp.u(408), 'select pending::text from costing.recalc_status()') like 'ERROR%No tenés permiso%', 'Compras no lo ve');
select ok(pg_temp.q(pg_temp.u(409), 'select pending::text from costing.recalc_status()') like 'ERROR%No tenés permiso%', 'la Cocinera tampoco');
select is((select count(*) from pg_proc p, unnest(p.proargnames) a
            where p.oid = 'costing.recalc_status()'::regprocedure and a ~ 'error'),
  0::bigint, 'no devuelve el texto del error');

-- Un plato con una preparación adentro, y uno con la materia prima directa. Precio de grupo: $ 1.000 el kg.
select pg_temp.ing(1);
select pg_temp.price(1, 1000, 'group', null, 2);
select pg_temp.recipe(1, 'preparation', 1000, 'g', null);
select pg_temp.line(1, 1, 1, 1000, 'g');
select pg_temp.publish(1);
select pg_temp.recipe(2, 'dish', 1, 'unit', 1);
select pg_temp.sub(2, 1, 1, 500, 'g');
select pg_temp.publish(2);
select pg_temp.recipe(3, 'dish', 1, 'unit', 1);
select pg_temp.line(3, 1, 1, 200, 'g');
select pg_temp.publish(3);
select pg_temp.assign(2, 201);
select pg_temp.assign(3, 201);
select pg_temp.assign(3, 203);
select is(pg_temp.q(pg_temp.u(407), 'select pending::text from costing.recalc_status()')::int > 0, true, 'con pedidos en cola, hay cambios por aplicar');
select is(pg_temp.cost(2, 201) || '/' || pg_temp.cost(3, 201), '500.0000/200.0000', 'el costo de partida');
select is(pg_temp.q(pg_temp.u(407), 'select pending::text from costing.recalc_status()'), '0', 'la cola quedó vacía');

-- El precio sube a $ 1.500.
insert into costing.price_records (id, group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(99100), pg_temp.u(1), pg_temp.u(96001), 'group', recipes.today(), 1500, 'no_invoice', 'test_value');
select is(pg_temp.cost(2, 201), '750.0000', 'recalculado');

create function pg_temp.impact(p_user int, p_n int, p_rest int) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select cost_before::numeric(18,2) || ''/'' || cost_after::numeric(18,2) || ''/'' || difference::numeric(18,2) || ''/'' || difference_pct
       from costing.price_impact(%L) where recipe_id = %L and restaurant_id = %L', pg_temp.u(99100), pg_temp.u(97000 + p_n), pg_temp.u(p_rest)))
$$;
select is(pg_temp.impact(407, 3, 201), '200.00/300.00/100.00/50.00', 'la materia prima directa: de $ 200 a $ 300, 50 %');
select is(pg_temp.impact(407, 2, 201), '500.00/750.00/250.00/50.00', 'también el plato que la usa a través de una preparación');
select is(pg_temp.impact(407, 3, 203), '200.00/300.00/100.00/50.00', 'en cada local');
select is(pg_temp.q(pg_temp.u(407), format('select ingredient from costing.price_impact(%L) limit 1', pg_temp.u(99100))), 'Materia prima 1', 'dice de qué materia prima es');
select is(pg_temp.q(pg_temp.u(404), format('select string_agg(distinct restaurant_id::text, '','') from costing.price_impact(%L)', pg_temp.u(99100))),
  pg_temp.u(201)::text, 'el Gerente ve solo su local');
select is(pg_temp.q(pg_temp.u(408), format('select count(*)::text from costing.price_impact(%L)', pg_temp.u(99100))), '0',
  'Compras no ve el impacto en recetas');
select is(pg_temp.q(pg_temp.u(409), format('select count(*)::text from costing.price_impact(%L)', pg_temp.u(99100))), '0', 'la Cocinera tampoco');
select is((select count(*) from pg_proc p, unnest(p.proargnames) a
            where p.oid = 'costing.price_impact(uuid, integer, integer)'::regprocedure
              and a in ('package_price', 'unit_cost', 'net_package_price', 'gross_package_price', 'supplier_id', 'product', 'document_type')),
  0::bigint, 'el impacto no devuelve el precio');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.price_impact(%L)', pg_temp.u(99199))), '0', 'un precio que no existe no devuelve nada');
select ok(pg_temp.q(pg_temp.u(407), format('select calculated_at::text from costing.price_impact(%L) limit 1', pg_temp.u(99100))) is not null, 'dice cuándo se calculó');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.price_impact(%L, 1, 0)', pg_temp.u(99100))), '1', 'pagina');
select cmp_ok(pg_temp.q(pg_temp.u(407), format('select total_rows::text from costing.price_impact(%L, 1, 0)', pg_temp.u(99100)))::int, '>', 1, 'y dice cuántas hay');
select is(pg_temp.q(pg_temp.u(406), format('select count(*)::text from costing.price_impact(%L)', pg_temp.u(99100))), '0', 'el Jefe de Cocina no lo ve');
select ok(pg_temp.q(pg_temp.u(406), 'select pending::text from costing.recalc_status()') like 'ERROR%No tenés permiso%', 'ni el estado de la cola');

-- Dos precios en la misma tanda: cada uno muestra solo las recetas que lo usan.
select pg_temp.ing(2);
select pg_temp.price(2, 1000, 'group', null, 2);
select pg_temp.recipe(4, 'dish', 1, 'unit', 1);
select pg_temp.line(4, 1, 2, 100, 'g');
select pg_temp.publish(4);
select pg_temp.assign(4, 201);
select is(pg_temp.cost(4, 201), '100.0000', 'otra receta, con otra materia prima');
insert into costing.price_records (id, group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(99101), pg_temp.u(1), pg_temp.u(96001), 'group', recipes.today(), 2000, 'no_invoice', 'test_value'),
       (pg_temp.u(99102), pg_temp.u(1), pg_temp.u(96002), 'group', recipes.today(), 3000, 'no_invoice', 'test_value');
select is(pg_temp.cost(4, 201), '300.0000', 'recalculado junto');
select is(pg_temp.q(pg_temp.u(407), format('select string_agg(distinct recipe, '','' order by recipe) from costing.price_impact(%L)', pg_temp.u(99102))),
  'Receta 4', 'el precio de una materia prima no muestra las recetas de otra de la misma tanda');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.price_impact(%L) where recipe = ''Receta 4''', pg_temp.u(99101))), '0',
  'ni al revés');

-- Un precio que no cambió nada no hereda la suba de otro.
insert into costing.price_records (id, group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(99103), pg_temp.u(1), pg_temp.u(96002), 'group', recipes.today(), 3000, 'no_invoice', 'test_value');
select costing.process_recalc_queue(1000);
update costing.cost_recalc_queue set processed_at = now() - interval '1 hour' where price_record_id = pg_temp.u(99103);
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(1), pg_temp.u(96001), 'group', recipes.today(), 2500, 'no_invoice', 'test_value');
select costing.process_recalc_queue(1000);
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.price_impact(%L)', pg_temp.u(99103))), '0',
  'un precio sin efecto no muestra impacto');

-- Una receta que el local dejó de usar: el Gerente ya no ve su nombre.
update recipes.recipe_assignments set valid_to = recipes.today() - 1 where recipe_id = pg_temp.u(97004) and restaurant_id = pg_temp.u(201);
select pg_temp.cost(4, 201);
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.price_impact(%L) where recipe = ''Receta 4''', pg_temp.u(99102))), '0',
  'el Gerente no ve el nombre de una receta que su local dejó de usar');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.restaurant_costs(%L, ''receta 4'')', pg_temp.u(201))), '0', 'ni en la lista');
select is(pg_temp.q(pg_temp.u(405), format('select count(*) filter (where restaurant_id = %L)::text from costing.price_impact(%L)', pg_temp.u(203), pg_temp.u(99100))), '0',
  'el Chef de una marca no ve el impacto en los locales de otra');

-- La lista de un local.
select is(pg_temp.q(pg_temp.u(407), format('select name || ''/'' || total_cost::numeric(18,2) from costing.restaurant_costs(%L, ''receta 3'')', pg_temp.u(201))),
  'Receta 3/500.00', 'busca por nombre, sin importar mayúsculas');
select is(pg_temp.q(pg_temp.u(407), format('select count(*)::text from costing.restaurant_costs(%L, null, null, 1, 0)', pg_temp.u(201))), '1', 'pagina');
select cmp_ok(pg_temp.q(pg_temp.u(407), format('select total_rows::text from costing.restaurant_costs(%L, null, null, 1, 0)', pg_temp.u(201)))::int, '>', 1, 'y dice cuántas hay');
select is(pg_temp.q(pg_temp.u(407), format('select name from costing.restaurant_costs(%L, null, null, 50, 0, %L)', pg_temp.u(201), pg_temp.u(97003))), 'Receta 3', 'o trae una sola');
select is(pg_temp.q(pg_temp.u(407), format('select base_unit from costing.restaurant_costs(%L, null, null, 50, 0, %L)', pg_temp.u(201), pg_temp.u(97001))), 'g', 'con su unidad base');
select is(pg_temp.q(pg_temp.u(407), format('select count(*) filter (where reliability <> ''incomplete'')::text from costing.restaurant_costs(%L, null, ''incomplete'', 200, 0)', pg_temp.u(201))), '0', 'filtra por confiabilidad');
select ok(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.restaurant_costs(%L)', pg_temp.u(203))) like 'ERROR%No tenés permiso%', 'el Gerente no pide otro local');
select ok(pg_temp.q(pg_temp.u(408), format('select count(*)::text from costing.restaurant_costs(%L)', pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'Compras no pide la lista');
select ok(pg_temp.q(pg_temp.u(409), format('select total::text from costing.restaurant_cost_summary(%L)', pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'la Cocinera no pide las tarjetas');
select is(pg_temp.q(pg_temp.u(407), format('select (complete + stale + incomplete = total)::text from costing.restaurant_cost_summary(%L)', pg_temp.u(201))), 'true', 'las tarjetas suman el total');

-- Un pedido que falló tres veces se cuenta, sin mostrar el error. Solo a quien ve costos en ese local.
insert into costing.cost_recalc_queue (group_id, recipe_ids, restaurant_ids, reason, attempts, error)
values (pg_temp.u(1), array[pg_temp.u(97001)], array[pg_temp.u(203)], 'publish', 3, 'detalle técnico');
select is(pg_temp.q(pg_temp.u(407), 'select failed::text from costing.recalc_status()'), '1', 'los fallidos se cuentan');
select is(pg_temp.q(pg_temp.u(404), 'select failed::text from costing.recalc_status()'), '0', 'el Gerente de otro local no ve los pedidos ajenos');

select * from finish();
rollback;
