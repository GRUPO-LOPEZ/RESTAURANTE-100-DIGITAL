-- Fase 2 · Etapa 2.5: calidad de datos (ADR-0033). Cada indicador con la cuenta a mano, en un grupo chico armado para eso;
-- que la lista coincida con el número; y quién ve qué. Los ids se buscan afuera de la sesión, para que la prueba pueda fallar.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(45);

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
create function pg_temp.rec(p_code text) returns uuid language sql as $$
  select id from recipes.recipes where code = p_code
$$;
-- Qué indicadores ve una persona en un local.
create function pg_temp.seen(p_user int, p_rest int) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select string_agg(indicator, '','' order by indicator) from costing.data_quality(%L)', pg_temp.u(p_rest)))
$$;
create function pg_temp.without(p_role text, p_permission text) returns void language plpgsql as $$
begin
  perform core.set_change_context('Prueba: rol ajustado', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = p_role)
     and permission_id = (select id from core.permissions where code = p_permission);
end
$$;

-- Un grupo chico. 50001 grupo, 50002 marca, 50003 razón social, 50004 local, 50005 categoría, 50006 categoría de recetas, 50007 proceso.
insert into org.groups (id, name) values (pg_temp.u(50001), 'Grupo de calidad');
insert into org.brands (id, group_id, name, code) values (pg_temp.u(50002), pg_temp.u(50001), 'Marca de calidad', 'CALIDAD');
insert into org.legal_entities (id, group_id, name, tax_id, vat_condition)
values (pg_temp.u(50003), pg_temp.u(50001), 'Calidad S.A. (ficticia)', '30999999992', 'registered');
insert into org.restaurants (id, group_id, brand_id, name, legal_entity_id)
values (pg_temp.u(50004), pg_temp.u(50001), pg_temp.u(50002), 'Local de calidad', pg_temp.u(50003));
insert into catalog.ingredient_categories (id, group_id, name) values (pg_temp.u(50005), pg_temp.u(50001), 'Secos');
-- Un rubro de menú (ADR-0038): las recetas de esta prueba son platos.
insert into recipes.recipe_categories (id, group_id, name, kind) values (pg_temp.u(50006), pg_temp.u(50001), 'Platos', 'menu');
insert into catalog.yield_processes (id, group_id, code, name) values (pg_temp.u(50007), pg_temp.u(50001), 'LIMPIEZA', 'Limpieza');
-- Otra marca del grupo, y un local sin razón social.
insert into org.brands (id, group_id, name, code) values (pg_temp.u(50008), pg_temp.u(50001), 'Otra marca de calidad', 'CALIDAD2');
insert into org.restaurants (id, group_id, brand_id, name)
values (pg_temp.u(50009), pg_temp.u(50001), pg_temp.u(50002), 'Local sin razón social');

create function pg_temp.ing(p_n int, p_name text) returns void language sql as $$
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values (pg_temp.u(51000 + p_n), pg_temp.u(50001), 'CAL-ING-' || p_n, p_name, pg_temp.u(50005), (select id from catalog.units where code = 'g'))
$$;
create function pg_temp.product(p_n int) returns void language sql as $$
  insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                         content_per_unit, content_unit_id)
  values (pg_temp.u(52000 + p_n), pg_temp.u(50001), 'CAL-PROD-' || p_n, pg_temp.u(51000 + p_n), 'Producto ' || p_n,
          (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g'))
$$;
create function pg_temp.price(p_n int, p_days_ago int) returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
  values (pg_temp.u(50001), pg_temp.u(52000 + p_n), 'group', current_date - p_days_ago, 1000, 'no_invoice', 'test_value')
$$;
create function pg_temp.recipe(p_n int, p_yield numeric) returns void language sql as $$
  insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type, category_id)
  values (pg_temp.u(53000 + p_n), pg_temp.u(50001), 'group', 'CAL-REC-' || p_n, 'Receta ' || p_n, 'dish', pg_temp.u(50006));
  insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
  values (pg_temp.u(54000 + p_n), pg_temp.u(50001), pg_temp.u(53000 + p_n), 1, p_yield,
          case when p_yield is not null then (select id from catalog.units where code = 'g') end, 1);
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (pg_temp.u(50001), pg_temp.u(53000 + p_n), pg_temp.u(50004), current_date - 1);
$$;
create function pg_temp.line(p_n int, p_ing int) returns void language sql as $$
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
  values (pg_temp.u(50001), pg_temp.u(54000 + p_n), 1, pg_temp.u(51000 + p_ing), 100, (select id from catalog.units where code = 'g'))
$$;
create function pg_temp.publish(p_n int) returns void language sql as $$
  update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(54000 + p_n);
  update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(54000 + p_n);
  update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(54000 + p_n);
$$;

-- Materias primas. 1: todo bien. 2: precio viejo, sin rendimiento. 3 y 4: se parecen, sin producto ni precio.
-- 5: la usa una receta y está desactivada, así que no se cuenta.
select pg_temp.ing(1, 'Harina cero');
select pg_temp.ing(2, 'Aceite de girasol');
select pg_temp.ing(3, 'Tomate perita');
select pg_temp.ing(4, 'Tomate peritas');
select pg_temp.ing(5, 'Sal gruesa');
-- 7 y 8 solo se parecen por el alias.
select pg_temp.ing(7, 'Queso de pasta hilada');
select pg_temp.ing(8, 'Mozzarella');
insert into catalog.ingredient_aliases (group_id, ingredient_id, alias) values (pg_temp.u(50001), pg_temp.u(51007), 'mozzarella');
select pg_temp.product(1);
select pg_temp.product(2);
select pg_temp.price(1, 1);
select pg_temp.price(2, 200);
insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, status, approved_by, approved_at)
values (pg_temp.u(50001), pg_temp.u(51001), pg_temp.u(50007), 0.9, 1, 'approved', pg_temp.u(413), now());

-- Recetas. 1: vigente, con costo y foto. 2: vigente, sin precio. 3: borrador sin rendimiento. 4: vigente, con un componente
-- desactivado. 5: en revisión. 6: maestra sin asignar y sin publicar, como una importada.
-- No cuentan: 7, publicada y sin asignar (el local no la usa), y 8, sin publicar de otra marca.
select pg_temp.recipe(1, 1000);
select pg_temp.line(1, 1);
insert into recipes.recipe_media (group_id, recipe_id, recipe_version_id, kind, storage_path)
values (pg_temp.u(50001), pg_temp.u(53001), pg_temp.u(54001), 'plating',
        pg_temp.u(50001) || '/' || pg_temp.u(53001) || '/' || pg_temp.u(55001) || '.jpg');
select pg_temp.publish(1);
select pg_temp.recipe(2, 1000);
select pg_temp.line(2, 3);
select pg_temp.publish(2);
select pg_temp.recipe(3, null);
select pg_temp.line(3, 1);
select pg_temp.recipe(4, 1000);
select pg_temp.line(4, 5);
select pg_temp.publish(4);
select pg_temp.recipe(5, 1000);
select pg_temp.line(5, 1);
update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(54005);
select pg_temp.recipe(6, 1000);
select pg_temp.line(6, 1);
select pg_temp.recipe(7, 1000);
select pg_temp.line(7, 1);
select pg_temp.publish(7);
insert into recipes.recipes (id, group_id, brand_id, scope_type, code, name, recipe_type, category_id)
values (pg_temp.u(53008), pg_temp.u(50001), pg_temp.u(50008), 'brand', 'CAL-REC-8', 'Receta 8', 'dish', pg_temp.u(50006));
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
values (pg_temp.u(54008), pg_temp.u(50001), pg_temp.u(53008), 1, 1000, (select id from catalog.units where code = 'g'), 1);
update recipes.recipe_assignments set deleted_at = now() where recipe_id in (pg_temp.u(53006), pg_temp.u(53007));
-- La receta 1 tiene una versión nueva en borrador: sigue contando la vigente, que tiene foto.
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
values (pg_temp.u(54101), pg_temp.u(50001), pg_temp.u(53001), 2, 1000, (select id from catalog.units where code = 'g'), 1);
update catalog.ingredients set is_active = false where id = pg_temp.u(51005);
select costing.process_recalc_queue(1000);
refresh materialized view reporting.mv_ingredient_twins;

-- ---------------------------------------------------------------------------
-- La cuenta a mano
-- ---------------------------------------------------------------------------
create function pg_temp.count(p_indicator text) returns text language sql as $$
  select done || '/' || total from reporting.v_data_quality where restaurant_id = pg_temp.u(50004) and indicator = p_indicator
$$;
select is(pg_temp.count('ingredient_price'), '2/6', 'con precio: 2 de 6 (la desactivada no cuenta)');
select is(pg_temp.count('price_stale'), '1/2', 'al día: 1 de los 2 que tienen precio');
select is(pg_temp.count('ingredient_unit'), '2/6', 'con unidad normalizada: 2 de 6');
select is(pg_temp.count('ingredient_yield'), '1/6', 'con rendimiento aprobado: 1 de 6');
select is(pg_temp.count('ingredient_duplicate'), '2/6', 'sin parecidos: 2 de 6, también por alias');
select is(pg_temp.count('recipe_approved'), '3/6', 'aprobadas: 3 de 6, con la maestra sin asignar');
select is(pg_temp.count('recipe_review'), '5/6', 'sin revisión pendiente: 5 de 6');
select is(pg_temp.count('recipe_photo'), '1/6', 'con foto: 1 de 6, la de la versión vigente');
select is(pg_temp.count('recipe_yield'), '5/6', 'con rendimiento: 5 de 6');
select is(pg_temp.count('recipe_components'), '5/6', 'sin componentes inactivos: 5 de 6');
select is(pg_temp.count('recipe_cost'), '1/6', 'con costo completo: 1 de 6');
select is((select detail from costing.quality_items(pg_temp.u(50004)) where indicator = 'ingredient_duplicate' and item_id = pg_temp.u(51003)),
  'Se parece a Tomate peritas', 'y dice a cuál se parece');
select is((select count(*) from costing.quality_items(pg_temp.u(50004)) where item_id = pg_temp.u(51005)), 0::bigint, 'la desactivada no aparece en ninguna lista');
select is((select count(*) from costing.quality_items(pg_temp.u(50004)) where item_id in (pg_temp.u(53007), pg_temp.u(53008))), 0::bigint,
  'ni lo publicado sin asignar, ni lo de otra marca');
select is((select detail from costing.quality_items(pg_temp.u(50004)) where indicator = 'ingredient_duplicate' and item_id = pg_temp.u(51007)),
  'Se parece a Mozzarella', 'el alias de una contra el nombre de otra');
-- Con factura, un local sin razón social no tiene costo.
select pg_temp.ing(9, 'Pimienta negra');
select pg_temp.product(9);
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, vat_rate, price_includes_vat, source)
values (pg_temp.u(50001), pg_temp.u(52009), 'group', current_date - 1, 1000, 'invoice', 21, true, 'test_value');
select is((select detail || '/' || ok from costing.quality_items(pg_temp.u(50009)) where indicator = 'ingredient_price' and item_id = pg_temp.u(51009)),
  'Falta la razón social del local/false', 'sin razón social, un precio con factura no cuenta, y dice por qué');
-- Una materia prima que se dio de baja deja de contar como parecida sin esperar a la noche.
update catalog.ingredients set is_active = false where id = pg_temp.u(51004);
select is((select ok from costing.quality_items(pg_temp.u(50004)) where indicator = 'ingredient_duplicate' and item_id = pg_temp.u(51003)), true,
  'un parecido dado de baja deja de contar enseguida');

-- ---------------------------------------------------------------------------
-- La lista coincide con el número (la Chef, en el seed)
-- ---------------------------------------------------------------------------
create function pg_temp.list_matches() returns boolean language plpgsql as $$
declare
  r record;
  v bigint;
  n integer := 0;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(405), 'role', 'authenticated', 'aal', 'aal2')::text, true);
  for r in select * from costing.data_quality(pg_temp.u(201)) loop
    select coalesce(max(i.total_rows), 0) into v from costing.data_quality_items(pg_temp.u(201), r.indicator, 1) i;
    if v <> r.total - r.done - r.hidden then
      perform set_config('request.jwt.claims', '', true);
      return false;
    end if;
    n := n + 1;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  return n > 0;
end
$$;
select ok(pg_temp.list_matches(), 'en cada indicador, la lista tiene lo que le falta al número');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.data_quality_items(%L, 'recipe_photo', 1)$$, pg_temp.u(201))), '1', 'la lista va por páginas');
select ok(pg_temp.q(pg_temp.u(407), format($$select max(total_rows)::text from costing.data_quality_items(%L, 'recipe_photo', 1)$$, pg_temp.u(201)))::int > 1, 'y trae el total');
select ok(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.data_quality_items(%L, 'no_existe')$$, pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'un indicador que no existe se rechaza');

-- ---------------------------------------------------------------------------
-- Quién ve qué. 403 Directora de Pastas, 404 Gerente, 406 Jefe de Cocina, 407 Controller, 408 Compras, 409 Cocinera.
-- ---------------------------------------------------------------------------
select is(pg_temp.seen(407, 201),
  'ingredient_duplicate,ingredient_price,ingredient_unit,ingredient_yield,price_stale,recipe_approved,recipe_components,recipe_cost,recipe_photo,recipe_review,recipe_yield',
  'el Controller ve los 11');
select ok(pg_temp.seen(409, 201) like 'ERROR%No tenés permiso%', 'la Cocinera no entra');
select ok(pg_temp.q(pg_temp.u(409), format($$select count(*)::text from costing.data_quality_items(%L, 'recipe_photo')$$, pg_temp.u(201))) like 'ERROR%No tenés permiso%', 'ni a las listas');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.data_quality_places()'), '0', 'ni a la comparación');
select is(pg_temp.seen(406, 201), 'ingredient_duplicate,ingredient_unit,ingredient_yield,recipe_approved,recipe_components,recipe_photo,recipe_review,recipe_yield',
  'el Jefe de Cocina ve lo técnico, sin costos ni precios');
select ok(pg_temp.q(pg_temp.u(406), format($$select count(*)::text from costing.data_quality_items(%L, 'ingredient_price')$$, pg_temp.u(201))) like 'ERROR%No tenés permiso%',
  'y no abre la lista de un indicador que no ve');
select is(pg_temp.seen(408, 201), 'ingredient_duplicate,ingredient_price,ingredient_unit,ingredient_yield,price_stale,recipe_approved,recipe_components,recipe_photo,recipe_review,recipe_yield',
  'Compras ve precios y no costos');
select ok(pg_temp.seen(403, 203) like 'ERROR%No tenés permiso%', 'la Directora no entra a otra marca');
select ok(pg_temp.seen(404, 203) like 'ERROR%No tenés permiso%', 'el Gerente no entra a otro local');
select is(pg_temp.q(pg_temp.u(404), 'select count(distinct restaurant_id)::text from costing.data_quality_places()'), '1', 'el Gerente compara solo el suyo');
select ok(pg_temp.q(pg_temp.u(407), 'select count(distinct restaurant_id)::text from costing.data_quality_places()')::int > 1, 'el Controller compara varios');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.data_quality_items(%L, 'recipe_photo') where item_id = %L$$, pg_temp.u(201), pg_temp.rec('DEMO-PAR-02'))), '0',
  'una receta de otra marca no se cuenta en este local');
-- Un borrador: el Controller no lo ve, pero el número tiene que ser real.
select ok(pg_temp.rec('DEMO-PAS-06') is not null, 'el borrador existe');
select ok(pg_temp.q(pg_temp.u(407), format($$select (total - done)::text from costing.data_quality(%L) where indicator = 'recipe_approved'$$, pg_temp.u(201)))::int >= 1,
  'el Controller cuenta las recetas sin aprobar, aunque no las vea');
select ok(pg_temp.q(pg_temp.u(407), format($$select hidden::text from costing.data_quality(%L) where indicator = 'recipe_approved'$$, pg_temp.u(201)))::int >= 1, 'y sabe cuántas no ve');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.data_quality_items(%L, 'recipe_approved') where item_id = %L$$, pg_temp.u(201), pg_temp.rec('DEMO-PAS-06'))), '0',
  'pero su nombre no se lista');
select is(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from costing.data_quality_items(%L, 'recipe_approved') where item_id = %L$$, pg_temp.u(201), pg_temp.rec('DEMO-PAS-06'))), '1',
  'la Chef, que lo trabaja, sí lo ve');
-- Un local recién abierto: los indicadores salen igual, en cero, y no desaparecen.
insert into org.restaurants (id, group_id, brand_id, name) values (pg_temp.u(50010), pg_temp.u(1), pg_temp.u(101), 'Local recién abierto');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.data_quality(%L)$$, pg_temp.u(50010))), '11', 'un local nuevo muestra los 11');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.quality_places() where id = %L$$, pg_temp.u(50010))), '1', 'y se puede elegir');
-- La tarea de la noche, tal como corre.
do $$ begin execute (select command from cron.job where jobname = 'grupo-lf-calidad-parecidos'); end $$;
select ok(exists (select 1 from pg_indexes where schemaname = 'reporting' and indexname = 'mv_ingredient_twins_key'), 'la tarea de la noche corre, con su índice único');
select is((select schedule from cron.job where jobname = 'grupo-lf-calidad-parecidos'), '0 7 * * *', 'los parecidos se recalculan cada noche');
select ok(not has_table_privilege('authenticated', 'reporting.v_data_quality', 'select')
          and not has_table_privilege('authenticated', 'reporting.mv_ingredient_twins', 'select')
          and not has_function_privilege('authenticated', 'costing.quality_items(uuid)', 'execute'), 'lo que no mira la sesión no se puede leer');

-- Un rol ajustado desde el panel: sin ver el catálogo, esos indicadores desaparecen.
select pg_temp.without('controller', 'catalog.view');
select is(pg_temp.seen(407, 201),
  'recipe_approved,recipe_components,recipe_cost,recipe_photo,recipe_review,recipe_yield',
  'sin catalog.view no salen los del catálogo ni los de precios, que llevan su nombre');
select pg_temp.without('controller', 'recipes.view');
select is(pg_temp.seen(407, 201), 'recipe_cost', 'sin recipes.view no salen los de recetas');

select * from finish();
rollback;
