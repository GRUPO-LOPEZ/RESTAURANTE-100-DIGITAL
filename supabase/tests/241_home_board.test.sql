-- Fase 2 · Etapa 2.5: el tablero de Inicio (ADR-0033). La cuenta a mano en un local armado para eso, y quién ve qué.
-- Los ids se buscan afuera de la sesión, y cada número se compara contra uno escrito a mano, para que la prueba pueda fallar.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(31);

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
-- Un local nuevo de una marca nueva: solo tiene lo que se le carga acá. 50011 marca, 50012 local.
insert into org.brands (id, group_id, name, code) values (pg_temp.u(50011), pg_temp.u(1), 'Marca del tablero', 'TABLERO');
insert into org.restaurants (id, group_id, brand_id, name, legal_entity_id)
select pg_temp.u(50012), pg_temp.u(1), pg_temp.u(50011), 'Local del tablero', legal_entity_id from org.restaurants where id = pg_temp.u(201);

create function pg_temp.ing(p_n int) returns void language sql as $$
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values (pg_temp.u(95000 + p_n), pg_temp.u(1), 'TAB-ING-' || p_n, 'Tablero ' || p_n, pg_temp.u(707), (select id from catalog.units where code = 'g'));
  insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                         content_per_unit, content_unit_id)
  values (pg_temp.u(96000 + p_n), pg_temp.u(1), 'TAB-PROD-' || p_n, pg_temp.u(95000 + p_n), 'Producto ' || p_n,
          (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g'));
$$;
create function pg_temp.price(p_n int, p_price numeric, p_days_ago int default 1) returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
  values (pg_temp.u(1), pg_temp.u(96000 + p_n), 'group', recipes.today() - p_days_ago, p_price, 'no_invoice', 'test_value')
$$;
create function pg_temp.version(p_n int, p_v int, p_ing int, p_grams numeric) returns void language sql as $$
  insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
  values (pg_temp.u(98000 + p_n + 500 * (p_v - 1)), pg_temp.u(1), pg_temp.u(97000 + p_n), p_v, 1, (select id from catalog.units where code = 'unit'), 1);
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
  values (pg_temp.u(1), pg_temp.u(98000 + p_n + 500 * (p_v - 1)), 1, pg_temp.u(95000 + p_ing), p_grams, (select id from catalog.units where code = 'g'));
  update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(98000 + p_n + 500 * (p_v - 1));
  update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(98000 + p_n + 500 * (p_v - 1));
  update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(98000 + p_n + 500 * (p_v - 1));
$$;
create function pg_temp.dish(p_n int, p_ing int, p_grams numeric, p_type text default 'dish') returns void language sql as $$
  insert into recipes.recipes (id, group_id, brand_id, scope_type, code, name, recipe_type, category_id)
  values (pg_temp.u(97000 + p_n), pg_temp.u(1), pg_temp.u(50011), 'brand', 'TAB-REC-' || p_n, 'Plato ' || p_n, p_type::recipes.recipe_type,
          -- Rubros (ADR-0038): un plato va en uno de menú (Pastas); el resto, en uno de sub-recetas (Salsas).
          case when p_type = 'dish' then pg_temp.u(1062) else pg_temp.u(1061) end);
  select pg_temp.version(p_n, 1, p_ing, p_grams);
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (pg_temp.u(1), pg_temp.u(97000 + p_n), pg_temp.u(50012), recipes.today() - 1);
$$;
-- Lo que ve el Controller en el local del tablero.
create function pg_temp.board(p_sql text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(407), format(p_sql, pg_temp.u(50012)))
$$;
create function pg_temp.sections(p_user int, p_rest int default 201) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select string_agg(distinct item, '','' order by item) from costing.home_board(%L) where section = ''allowed''', pg_temp.u(p_rest)))
$$;
create function pg_temp.state(p_state text) returns text language sql as $$
  select pg_temp.board(format($f$select amount::int::text from costing.home_board(%%L) where section = 'reliability' and item = %L$f$, p_state))
$$;

-- Lo que el grupo ya tiene sin publicar cuenta en todos los locales: se mide antes, y se compara contra eso.
create temporary table base as select pg_temp.state('none')::int as none,
  pg_temp.board($$select amount::int::text from costing.home_board(%L) where section = 'preparations'$$)::int as preparations;
select is(pg_temp.board($$select string_agg(item, ',' order by detail::int) from costing.home_board(%L) where section = 'reliability'$$),
  'verified,estimated,stale,incomplete,none', 'los cinco estados, siempre en el mismo orden y también en cero');
select is(pg_temp.board($$select count(*)::text from costing.home_board(%L) where section in ('top_portion', 'top_ingredient', 'price_affected', 'most_used')$$), '0',
  'un local sin recetas no trae listas');
select is(pg_temp.sections(407, 50012), 'most_used,price_affected,reliability,top_ingredient,top_portion', 'pero las secciones están, para decir que están vacías');

-- 1: 750 g a 1 $/g. 2: 250 g de otra a 1 $/g. 3: sin precio. 4: una preparación. 5: dos versiones, y solo cuenta la vigente.
select pg_temp.ing(1);
select pg_temp.price(1, 1000);
select pg_temp.ing(2);
select pg_temp.price(2, 1000);
select pg_temp.ing(3);
select pg_temp.ing(4);
select pg_temp.price(4, 1000);
select pg_temp.dish(1, 1, 750);
select pg_temp.dish(2, 2, 250);
select pg_temp.dish(3, 3, 100);
select pg_temp.dish(4, 2, 1, 'preparation');
select pg_temp.dish(5, 4, 1000);
select costing.process_recalc_queue(1000);
alter table recipes.recipe_versions disable trigger user;
update recipes.recipe_versions set status = 'archived' where id = pg_temp.u(98005);
alter table recipes.recipe_versions enable trigger user;
select pg_temp.version(5, 2, 2, 1000);
select costing.process_recalc_queue(1000);

select is(pg_temp.board($$select item || '/' || amount::numeric(18,2) from costing.home_board(%L) where section = 'top_portion' order by amount desc limit 1$$),
  'Plato 5/1000.00', 'lo más caro por porción: la versión vigente, $ 1.000');
select is(pg_temp.board($$select detail from costing.home_board(%L) where section = 'top_portion' order by amount desc limit 1$$), 'estimated', 'con su confiabilidad: sin rendimiento aprobado, va con estimaciones');
-- Sobre $ 2.001 de líneas: Tablero 2 suma 250 + 1 + 1.000 y Tablero 1, 750. Tablero 4 quedó en la versión vieja.
select is(pg_temp.board($$select string_agg(item || ' ' || amount::numeric(18,1), ', ' order by amount desc) from costing.home_board(%L) where section = 'top_ingredient'$$),
  'Tablero 2 62.5, Tablero 1 37.5', 'lo que más pesa, a mano: 1.251 y 750 sobre 2.001, sin la versión vieja');
select is(pg_temp.board($$select string_agg(item || ' ' || amount::int, ', ' order by amount desc, item) from costing.home_board(%L) where section = 'most_used'$$),
  'Tablero 2 3, Tablero 1 1, Tablero 3 1', 'lo más usado: en cuántas recetas vigentes');
select is(pg_temp.board($$select amount::int::text from costing.home_board(%L) where section = 'preparations'$$),
  ((select preparations from base) + 1)::text, 'una preparación más que antes');
select is(pg_temp.state('estimated'), '4', 'cuatro con estimaciones');
select is(pg_temp.state('incomplete'), '1', 'una incompleta, la que no tiene precio');
select is(pg_temp.state('none')::int, (select none from base), 'y las sin costo siguen siendo las de antes');
select is(pg_temp.board($$select count(*)::text from costing.home_board(%L) where section = 'price_affected'$$), '0', 'sin cambios de precio, la lista está vacía');

-- Un precio nuevo: de 1 a 2 $/g. El plato 1 sube $ 750.
select pg_temp.price(1, 2000, 0);
select costing.process_recalc_queue(1000);
select is(pg_temp.board($$select item || '/' || amount::numeric(18,2) from costing.home_board(%L) where section = 'price_affected'$$),
  'Plato 1/750.00', 'un precio nuevo: el plato subió $ 750');
-- La materia prima sin precio recibe uno: la receta pasa de no tener costo a tenerlo.
select pg_temp.price(3, 1000, 0);
select costing.process_recalc_queue(1000);
select is(pg_temp.board($$select item || '/' || detail || '/' || coalesce(amount::text, 'sin importe') from costing.home_board(%L) where section = 'price_affected' and detail is not null$$),
  'Plato 3/gained/sin importe', 'una receta que recién tiene costo también aparece');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.home_board(%L) where section = 'price_affected' and item_id = %L$$, pg_temp.u(50012), pg_temp.u(97002))), '0',
  'una receta a la que no le cambió el precio no aparece');
-- Más de 30 días: deja de contar.
alter table costing.recipe_cost_snapshots disable trigger user;
update costing.recipe_cost_snapshots set created_at = now() - interval '31 days' where recipe_id = pg_temp.u(97001) and reason = 'price_change';
alter table costing.recipe_cost_snapshots enable trigger user;
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.home_board(%L) where section = 'price_affected' and item_id = %L$$, pg_temp.u(50012), pg_temp.u(97001))), '0',
  'un cambio de hace más de 30 días ya no aparece');

-- Una receta que el local dejó de usar no se lista.
update recipes.recipe_assignments set deleted_at = now() where recipe_id = pg_temp.u(97005) and restaurant_id = pg_temp.u(50012);
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.home_board(%L) where section = 'top_portion' and item_id = %L$$, pg_temp.u(50012), pg_temp.u(97005))), '0',
  'una receta que el local dejó de usar no se lista');

-- Quién ve qué. 403 Directora de Pastas, 404 Gerente, 405 Chef, 406 Jefe de Cocina, 407 Controller, 408 Compras, 409 Cocinera.
select is(pg_temp.sections(407), 'most_used,price_affected,reliability,top_ingredient,top_portion', 'el Controller ve todo');
select is(pg_temp.sections(405), 'most_used,price_affected,reliability,top_ingredient,top_portion', 'la Chef también');
select is(pg_temp.sections(403), 'most_used,price_affected,reliability,top_ingredient,top_portion', 'y la Directora, en su marca');
select is(pg_temp.sections(404), 'most_used,price_affected,reliability,top_ingredient,top_portion', 'y el Gerente, en su local');
select is(pg_temp.sections(406), 'most_used', 'el Jefe de Cocina, sin costos');
select is(pg_temp.sections(408), 'most_used', 'Compras, sin costos de recetas');
select ok(pg_temp.sections(409) like 'ERROR%No tenés permiso%', 'la Cocinera no entra');
select ok(pg_temp.sections(403, 203) like 'ERROR%No tenés permiso%', 'la Directora no entra a otra marca');
select ok(pg_temp.sections(404, 203) like 'ERROR%No tenés permiso%', 'el Gerente no entra a otro local');
select is((select provolatile from pg_proc where oid = 'costing.home_board(uuid)'::regprocedure), 's', 'solo lee');

-- Un rol ajustado desde el panel. Sin el catálogo no salen los nombres de las materias primas.
select pg_temp.without('controller', 'catalog.view');
select is(pg_temp.sections(407), 'most_used,price_affected,reliability,top_portion', 'sin catalog.view no sale lo que más pesa');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.home_board(%L) where section = 'most_used' and kind = 'ingredient'$$, pg_temp.u(201))), '0',
  'ni las materias primas de lo más usado');
-- Sin ver recetas, ninguna receta se nombra, aunque vea costos.
select pg_temp.without('controller', 'recipes.view');
select is(pg_temp.q(pg_temp.u(407), format($$select count(*)::text from costing.home_board(%L) where section = 'top_portion'$$, pg_temp.u(201))), '0',
  'sin ver recetas, no se nombra ninguna');
select is(pg_temp.sections(407), 'price_affected,reliability,top_portion', 'y las secciones siguen, vacías');

select * from finish();
rollback;
