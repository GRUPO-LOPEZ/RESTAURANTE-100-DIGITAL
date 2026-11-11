-- Fase 2 · Etapa 2.5: reportes (ADR-0034). Cada reporte con la cuenta a mano en un local armado para eso, quién puede, y que
-- lo exportado quede registrado. Los ids se buscan afuera de la sesión, y los números están escritos a mano.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(51);

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
create function pg_temp.without(p_role text, p_permission text) returns void language plpgsql as $$
begin
  perform core.set_change_context('Prueba: rol ajustado', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = p_role)
     and permission_id = (select id from core.permissions where code = p_permission);
end
$$;
-- Un grupo chico: 50001 grupo, 50002 marca, 50003 razón social, 50004 local, 50005 categoría, 50006 categoría de recetas, 50007 proceso.
insert into org.groups (id, name) values (pg_temp.u(50001), 'Grupo de reportes');
insert into org.brands (id, group_id, name, code) values (pg_temp.u(50002), pg_temp.u(50001), 'Marca de reportes', 'REPORTES');
insert into org.legal_entities (id, group_id, name, tax_id, vat_condition)
values (pg_temp.u(50003), pg_temp.u(50001), 'Reportes S.A. (ficticia)', '30999999993', 'registered');
insert into org.restaurants (id, group_id, brand_id, name, legal_entity_id)
values (pg_temp.u(50004), pg_temp.u(50001), pg_temp.u(50002), 'Local de reportes', pg_temp.u(50003));
insert into catalog.ingredient_categories (id, group_id, name) values (pg_temp.u(50005), pg_temp.u(50001), 'Secos');
-- Un rubro de menú (ADR-0038): las recetas de esta prueba son platos.
insert into recipes.recipe_categories (id, group_id, name, kind) values (pg_temp.u(50006), pg_temp.u(50001), 'Platos', 'menu');
insert into catalog.yield_processes (id, group_id, code, name) values (pg_temp.u(50007), pg_temp.u(50001), 'LIMPIEZA', 'Limpieza');
-- El Controller alcanza a este grupo solo con una asignación.
insert into core.user_memberships (user_id, group_id) values (pg_temp.u(407), pg_temp.u(50001));
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id)
select pg_temp.u(407), id, 'group', pg_temp.u(50001) from core.roles where code = 'controller';

create function pg_temp.ing(p_n int, p_name text) returns void language sql as $$
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values (pg_temp.u(51000 + p_n), pg_temp.u(50001), 'REP-ING-' || p_n, p_name, pg_temp.u(50005), (select id from catalog.units where code = 'g'));
  insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                         content_per_unit, content_unit_id)
  values (pg_temp.u(52000 + p_n), pg_temp.u(50001), 'REP-PROD-' || p_n, pg_temp.u(51000 + p_n), 'Producto ' || p_n,
          (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g'));
$$;
create function pg_temp.price(p_n int, p_price numeric, p_days_ago int default 1) returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
  values (pg_temp.u(50001), pg_temp.u(52000 + p_n), 'group', recipes.today() - p_days_ago, p_price, 'no_invoice', 'test_value')
$$;
create function pg_temp.dish(p_n int, p_ing int, p_grams numeric) returns void language sql as $$
  insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type, category_id)
  values (pg_temp.u(53000 + p_n), pg_temp.u(50001), 'group', 'REP-REC-' || p_n, 'Plato ' || p_n, 'dish', pg_temp.u(50006));
  insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
  values (pg_temp.u(54000 + p_n), pg_temp.u(50001), pg_temp.u(53000 + p_n), 1, 1, (select id from catalog.units where code = 'unit'), 1);
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
  values (pg_temp.u(50001), pg_temp.u(54000 + p_n), 1, pg_temp.u(51000 + p_ing), p_grams, (select id from catalog.units where code = 'g'));
  update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(54000 + p_n);
  update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(54000 + p_n);
  update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(54000 + p_n);
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (pg_temp.u(50001), pg_temp.u(53000 + p_n), pg_temp.u(50004), recipes.today() - 1);
$$;
create function pg_temp.r(p_sql text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(407), format(p_sql, pg_temp.u(50004)))
$$;

-- Dos materias primas: 1 a $ 2.000 el kg, con rendimiento aprobado; 2 sin precio.
select pg_temp.ing(1, 'Harina cero');
select pg_temp.price(1, 2000);
select pg_temp.ing(2, 'Tomate perita');
insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cut, cleaning_yield, cooking_factor, status, approved_by, approved_at)
values (pg_temp.u(50001), pg_temp.u(51001), pg_temp.u(50007), 'Entera', 0.9, 1.2, 'approved', pg_temp.u(413), now()),
       (pg_temp.u(50001), pg_temp.u(51002), pg_temp.u(50007), null, 0.5, 1, 'draft', null, null);
-- Plato 1: 500 g de la 1, $ 1.000. Plato 2: 100 g de la 2, sin costo.
select pg_temp.dish(1, 1, 500);
select pg_temp.dish(2, 2, 100);
-- Plato 6 lleva el plato 4 como preparación: la harina le llega a través de ese.
select pg_temp.ing(3, 'Sal gruesa');
select pg_temp.price(3, 1000);
select pg_temp.dish(4, 1, 10);
select pg_temp.dish(5, 3, 1);
insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type, category_id)
values (pg_temp.u(53006), pg_temp.u(50001), 'group', 'REP-REC-6', 'Plato 6', 'dish', pg_temp.u(50006));
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
values (pg_temp.u(54006), pg_temp.u(50001), pg_temp.u(53006), 1, 1, (select id from catalog.units where code = 'unit'), 1);
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
values (pg_temp.u(50001), pg_temp.u(54006), 1, pg_temp.u(53004), 1, (select id from catalog.units where code = 'unit'), 'finished');
update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(54006);
update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(54006);
update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(54006);
insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
values (pg_temp.u(50001), pg_temp.u(53006), pg_temp.u(50004), recipes.today() - 1);
select costing.process_recalc_queue(1000);

-- Materias primas
select is(pg_temp.r($$select string_agg(name || '/' || category || '/' || unit || '/' || coalesce(unit_cost::numeric(18,2)::text, 'sin precio'), ', ' order by name) from costing.report_ingredients(%L)$$),
  'Harina cero/Secos/g/2.00, Sal gruesa/Secos/g/1.00, Tomate perita/Secos/g/sin precio', 'materias primas: a $ 2 y $ 1 el gramo, y la que no tiene precio');
select is(pg_temp.r($$select max(total_rows)::text from costing.report_ingredients(%L, 1)$$), '3', 'trae el total aunque la página sea de una');
select is(pg_temp.r($$select valid_from::text from costing.report_ingredients(%L) where name = 'Harina cero'$$), (recipes.today() - 1)::text, 'con la fecha del precio');

-- Rendimientos
select is(pg_temp.r($$select string_agg(ingredient || '/' || process || '/' || cut || '/' || cleaning_yield::numeric(5,2) || '/' || waste::numeric(5,2) || '/' || cooking_factor::numeric(5,2), ', ') from costing.report_yields(%L)$$),
  'Harina cero/Limpieza/Entera/0.90/0.10/1.20', 'rendimientos: solo el aprobado, con su merma');

-- Dónde se usa
select is(pg_temp.r($$select string_agg(component || '/' || recipe || '/' || version_number || '/' || quantity::int || unit, ', ' order by component, recipe) from costing.report_usage(%L) where through is null and recipe in ('Plato 1', 'Plato 2')$$),
  'Harina cero/Plato 1/1/500g, Tomate perita/Plato 2/1/100g', 'dónde se usa: cada línea, con su receta y su versión');
-- La harina llega al plato 6 a través de la preparación: el plato tiene que salir.
select is(pg_temp.r($$select count(*)::text || '/' || max(through) || '/' || coalesce(max(quantity)::text, 'sin cantidad') from costing.report_usage(%L) where component = 'Harina cero' and recipe = 'Plato 6'$$),
  '1/Plato 4/sin cantidad', 'también el plato que la usa a través de una preparación');
select is(pg_temp.r($$select max(total_rows)::text from costing.report_usage(%L, 1, 1)$$), pg_temp.r($$select count(*)::text from costing.report_usage(%L, 1000)$$), 'el total no depende de la página');
select is(pg_temp.r($$select count(*)::text from costing.report_usage(%L, 1, 1)$$), '1', 'y la segunda página trae su fila');

-- Cambios de costo: de 2 a 3 $/g, el plato 1 pasa de $ 1.000 a $ 1.500. La 2 recibe precio: el plato 2 recién tiene costo.
select is(pg_temp.r($$select count(*)::text from costing.report_cost_changes(%L, current_date - 31, current_date + 1)$$), '0', 'sin cambios, el reporte está vacío');
select pg_temp.price(1, 3000, 0);
select pg_temp.price(2, 1000, 0);
select costing.process_recalc_queue(1000);
select is(pg_temp.r($$select previous::numeric(18,2) || '/' || current_cost::numeric(18,2) || '/' || difference::numeric(18,2) || '/' || difference_pct::numeric(18,2) || '/' || reason
                        from costing.report_cost_changes(%L, current_date - 31, current_date + 1) where recipe = 'Plato 1'$$),
  '1000.00/1500.00/500.00/50.00/price_change', 'cambios de costo: de $ 1.000 a $ 1.500, 50 %');
select is(pg_temp.r($$select coalesce(previous::text, 'sin costo') || '/' || current_cost::numeric(18,2) || '/' || coalesce(difference::text, 'sin diferencia')
                        from costing.report_cost_changes(%L, current_date - 31, current_date + 1) where recipe = 'Plato 2'$$),
  'sin costo/100.00/sin diferencia', 'una receta que recién tiene costo aparece sin diferencia');
-- Los bordes del período, en hora de la Argentina: una foto de las 22:00 del día 10 son las 01:00 UTC del 11.
alter table costing.recipe_cost_snapshots disable trigger user;
update costing.recipe_cost_snapshots set created_at = '2026-03-11 01:00:00+00' where recipe_id = pg_temp.u(53001) and reason = 'price_change';
alter table costing.recipe_cost_snapshots enable trigger user;
select is(pg_temp.r($$select count(*)::text from costing.report_cost_changes(%L, '2026-03-10', '2026-03-10') where recipe = 'Plato 1'$$), '1', 'el período va en hora de la Argentina: el 10 incluye sus 22:00');
select is(pg_temp.r($$select changed_on::text from costing.report_cost_changes(%L, '2026-03-10', '2026-03-10') where recipe = 'Plato 1'$$), '2026-03-10', 'y esa es la fecha');
select is(pg_temp.r($$select count(*)::text from costing.report_cost_changes(%L, '2026-03-11', '2026-03-12') where recipe = 'Plato 1'$$), '0', 'el 11 ya no');
select is(pg_temp.r($$select count(*)::text from costing.report_cost_changes(%L, '2026-03-01', '2026-03-09') where recipe = 'Plato 1'$$), '0', 'ni antes del período');
select ok(pg_temp.r($$select count(*)::text from costing.report_cost_changes(%L, '2026-03-12', '2026-03-10')$$) like 'ERROR%período%', 'un período al revés se explica');

-- Calidad de datos
select is(pg_temp.r($$select count(*)::text from costing.report_quality(%L, 1000) where indicator = 'recipe_photo'$$), '5', 'calidad: las cinco recetas sin foto');
select ok(pg_temp.r($$select max(total_rows)::text from costing.report_quality(%L, 1)$$)::int > 5, 'y el total las incluye');
select is(pg_temp.r($$select max(total_rows)::text from costing.report_quality(%L, 1)$$), pg_temp.r($$select count(*)::text from costing.report_quality(%L, 1000)$$),
  'y coincide con la lista');

-- Una versión nueva: el plato 2 pasa a llevar 200 g. Se marca como cambio de receta, no de precio.
alter table recipes.recipe_versions disable trigger user;
update recipes.recipe_versions set status = 'archived' where id = pg_temp.u(54002);
alter table recipes.recipe_versions enable trigger user;
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
values (pg_temp.u(54502), pg_temp.u(50001), pg_temp.u(53002), 2, 1, (select id from catalog.units where code = 'unit'), 1);
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
values (pg_temp.u(50001), pg_temp.u(54502), 1, pg_temp.u(51002), 200, (select id from catalog.units where code = 'g'));
update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(54502);
update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(54502);
update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(54502);
select costing.process_recalc_queue(1000);
select is(pg_temp.r($$select reason || '/' || previous::numeric(18,2) || '/' || current_cost::numeric(18,2) || '/' || version_number from costing.report_cost_changes(%L, current_date - 1, current_date + 1) where recipe = 'Plato 2' and reason = 'recipe_changed'$$),
  'recipe_changed/100.00/200.00/2', 'una versión nueva se marca como cambio de receta');
-- Una receta archivada sigue en la historia, y se marca: el Controller no la ve hoy.
update recipes.recipes set is_active = false where id = pg_temp.u(53001);
update recipes.recipe_assignments set deleted_at = now() where recipe_id = pg_temp.u(53001);
select is(pg_temp.r($$select in_use::text from costing.report_cost_changes(%L, '2026-03-10', '2026-03-10') where recipe = 'Plato 1'$$), 'false', 'lo que ya no se usa sigue en el período, marcado');

-- Sin razón social, un precio con factura no da costo, y no es lo mismo que no tener precio.
insert into org.restaurants (id, group_id, brand_id, name) values (pg_temp.u(50009), pg_temp.u(50001), pg_temp.u(50002), 'Local sin razón social');
select pg_temp.ing(9, 'Pimienta negra');
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, vat_rate, price_includes_vat, source)
values (pg_temp.u(50001), pg_temp.u(52009), 'group', recipes.today() - 1, 1000, 'invoice', 21, true, 'test_value');
select is(pg_temp.q(pg_temp.u(407), format($$select status from costing.report_ingredients(%L) where name = 'Pimienta negra'$$, pg_temp.u(50009))), 'missing_legal_entity', 'el reporte dice por qué no hay costo');

-- Quién puede. 403 Directora de Pastas, 404 Gerente, 405 Chef, 406 Jefe de Cocina, 407 Controller, 408 Compras, 409 Cocinera, 410 Auditor.
create function pg_temp.list(p_user int, p_rest int default 201) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select coalesce(string_agg(x, '','' order by x), ''nada'') from costing.report_list(%L) x', pg_temp.u(p_rest)))
$$;
select is(pg_temp.list(407), 'cost_card,cost_changes,ingredients,quality,recipe_card,usage,yields', 'el Controller saca los siete');
select is(pg_temp.list(410), 'cost_card,cost_changes,ingredients,quality,recipe_card,usage,yields', 'el Auditor también');
select is(pg_temp.list(404), 'cost_card,cost_changes,ingredients,quality,recipe_card,usage,yields', 'y el Gerente, en su local');
select is(pg_temp.list(405), 'cost_card,cost_changes,quality,recipe_card,usage,yields', 'la Chef, sin precios');
select is(pg_temp.list(406), 'nada', 'el Jefe de Cocina no');
select is(pg_temp.list(408), 'nada', 'Compras no');
select is(pg_temp.list(409), 'nada', 'la Cocinera no');
select is(pg_temp.list(404, 203), 'nada', 'el Gerente no saca reportes de otro local');
select ok(pg_temp.q(pg_temp.u(408), format('select count(*)::text from costing.report_ingredients(%L)', pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'Compras no lo pide directo');
select ok(pg_temp.q(pg_temp.u(408), format('select count(*)::text from costing.report_yields(%L)', pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'ni los rendimientos');
select ok(pg_temp.q(pg_temp.u(408), format($q$select count(*)::text from costing.report_cost_changes(%L, '2026-01-01', '2026-12-31')$q$, pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'ni los cambios de costo');
select ok(pg_temp.q(pg_temp.u(409), format('select count(*)::text from costing.report_quality(%L)', pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'la Cocinera tampoco');
select ok(pg_temp.q(pg_temp.u(405), format('select count(*)::text from costing.report_ingredients(%L)', pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'la Chef no pide precios');
select ok(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.report_usage(%L)', pg_temp.u(203))) like 'ERROR%No tenés permiso%', 'ni nadie, en otro local');
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from costing.report_places()'), '1', 'el Gerente elige solo su local');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from costing.report_places()'), '0', 'Compras no tiene locales');

-- Lo que la sesión no ve no sale: el borrador se cuenta en la calidad de datos, pero acá no se nombra.
select ok((select id from recipes.recipes where code = 'DEMO-PAS-06') is not null, 'el borrador existe');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.report_quality(%L, 1000) where item_id = %L$$, pg_temp.u(201), (select id from recipes.recipes where code = 'DEMO-PAS-06'))), '0',
  'el Controller no recibe el nombre de un borrador');
select ok(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from costing.report_quality(%L, 1000) where item_id = %L$$, pg_temp.u(201), (select id from recipes.recipes where code = 'DEMO-PAS-06')))::int > 0,
  'la Chef, que lo trabaja, sí');

-- Lo exportado queda registrado.
select is(pg_temp.q(pg_temp.u(407), format($$select costing.log_report('ingredients', %L, 'xlsx', 2)::text$$, pg_temp.u(201))), '', 'una exportación se registra');
select ok(pg_temp.q(pg_temp.u(407), format($$select costing.log_report('ingredients', %L, 'xlsx', -1)::text$$, pg_temp.u(201))) like 'ERROR%negativa%', 'las filas no pueden ser negativas');
select is(pg_temp.q(pg_temp.u(410), $$select report || '/' || format || '/' || rows_count from costing.report_exports(1)$$), 'ingredients/xlsx/2', 'el Auditor ve quién exportó qué');
select ok(pg_temp.q(pg_temp.u(410), 'select person from costing.report_exports(1)') ~ 'Camila', 'con su nombre');
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from costing.report_exports()'), '0', 'el Gerente no');
select is((select detail ->> 'report' || '/' || (detail ->> 'format') || '/' || (detail ->> 'rows') || '/' || (scope_restaurant_id = pg_temp.u(201))
             from audit.authentication_security_events where event_type = 'report_exported' and actor_id = pg_temp.u(407) order by occurred_at desc limit 1),
  'ingredients/xlsx/2/true', 'con el reporte, el formato, las filas y el local');
select ok(pg_temp.q(pg_temp.u(407), format($$select costing.log_report('ingredients', %L, 'doc')::text$$, pg_temp.u(201))) like 'ERROR%formato%', 'un formato que no existe se rechaza');
select ok(pg_temp.q(pg_temp.u(408), format($$select costing.log_report('ingredients', %L, 'csv')::text$$, pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'y quien no puede no registra nada');

-- Un rol ajustado desde el panel.
select pg_temp.without('controller', 'prices.view');
select is(pg_temp.list(407), 'cost_card,cost_changes,quality,recipe_card,usage,yields', 'sin ver precios no sale el reporte de materias primas');
select pg_temp.without('controller', 'reports.export');
select is(pg_temp.list(407), 'nada', 'sin reports.export no sale ninguno');

select * from finish();
rollback;
