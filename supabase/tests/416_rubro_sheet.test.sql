-- Ficha del rubro (ADR-0066): ícono y descripción solo en el primer nivel, guardado en lote con sello y motivo, con el
-- permiso de cada clase; los indicadores con los permisos de quien consulta, y «con precio al día» solo para quien ve
-- precios en el local.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(66);

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
    v := 'ERROR ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.rub(p_code text) returns uuid language sql as $$
  select id from recipes.top_categories where code = p_code and group_id = pg_temp.u(1)
$$;
create function pg_temp.cls(p_code text) returns text language sql as $$
  select category_class::text from recipes.top_categories where code = p_code and group_id = pg_temp.u(1)
$$;
create function pg_temp.sheet(p_user int, p_code text) returns jsonb language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select recipes.top_category_sheet(%L, %L)::text', pg_temp.cls(p_code), pg_temp.rub(p_code)))::jsonb
$$;
-- Guarda con el sello vigente.
create function pg_temp.save(p_user int, p_code text, p_changes jsonb, p_reason text default 'Prueba del rubro') returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select recipes.save_top_category(%L, %L, %L, %L, %L) ->> ''result''',
    pg_temp.cls(p_code), pg_temp.rub(p_code),
    (select updated_at from recipes.top_categories where id = pg_temp.rub(p_code)), p_changes, p_reason))
$$;

-- Compras 408 y Dirección 402 (compra), Chef del grupo 413 (sub-recetas y menú), Chef de marca 405, Cocinera 409.

-- ---------------------------------------------------------------------------
-- Ícono y descripción
-- ---------------------------------------------------------------------------
select is((select count(*)::int from recipes.top_categories where icon is null), 0, 'todos los rubros tienen ícono');
select is((select icon::text from recipes.top_categories where id = pg_temp.rub('MP-CAR')), 'meat', 'el de su código');
select is((select icon::text from recipes.top_categories where id = pg_temp.rub('SR-SAL')), 'preparation', 'si no, el genérico de su clase');
select is(array_length(enum_range(null::catalog.category_icon), 1), 14, 'el set es fijo: 14 íconos');
insert into catalog.ingredient_categories (group_id, name, parent_id) values (pg_temp.u(1), 'Cortes de prueba', pg_temp.rub('MP-CAR'));
select is((select icon from catalog.ingredient_categories where name = 'Cortes de prueba'), null, 'una subcategoría no tiene ícono');
select throws_ok($$ update catalog.ingredient_categories set icon = 'meat' where name = 'Cortes de prueba' $$, '23514', null, 'ni se le pone');
select throws_ok($$ update catalog.ingredient_categories set description = 'x' where name = 'Cortes de prueba' $$, '23514', null, 'ni descripción');
select throws_ok(format($$ update catalog.ingredient_categories set description = repeat('a', 501) where id = %L $$, pg_temp.rub('MP-CAR')),
  '23514', null, 'la descripción va hasta 500 caracteres');
select throws_ok(format($$ insert into recipes.recipe_categories (group_id, name, parent_id, icon) values (%L, 'Sub de prueba', %L, 'dish') $$,
  pg_temp.u(1), pg_temp.rub('PL-PAS')), '23514', null, 'lo mismo en los de recetas');
insert into recipes.recipe_categories (group_id, name, kind) values (pg_temp.u(1), 'Rubro nuevo de prueba', 'menu');
select is((select icon::text from recipes.recipe_categories where name = 'Rubro nuevo de prueba'), 'dish', 'un rubro nuevo nace con su ícono');

-- ---------------------------------------------------------------------------
-- Guardar
-- ---------------------------------------------------------------------------
select is(pg_temp.save(408, 'MP-CAR', '{"description":"  Carnes rojas y blancas.  ","icon":"fish","used_in_recipes":false}'), 'applied',
  'Compras guarda un rubro de compra en lote');
select is((select description || '/' || icon || '/' || used_in_recipes from catalog.ingredient_categories where id = pg_temp.rub('MP-CAR')),
  'Carnes rojas y blancas./fish/false', 'todo junto, sin espacios de más');
select ok(exists (select 1 from audit.audit_events where table_name = 'ingredient_categories' and record_id = pg_temp.rub('MP-CAR')
                    and action = 'update' and reason = 'Prueba del rubro' and new_values ->> 'icon' = 'fish'
                    and old_values ->> 'icon' = 'meat'),
  'con el antes, el después y el motivo en la auditoría');
select is(pg_temp.save(402, 'MP-CAR', '{"name":"Carnes y aves","description":null}'), 'applied', 'Dirección también');
select is((select name || '/' || coalesce(description, 'sin') || '/' || icon from catalog.ingredient_categories where id = pg_temp.rub('MP-CAR')),
  'Carnes y aves/sin/fish', 'lo que no viene no se toca; la descripción se puede sacar');
select is((select code from recipes.top_categories where id = pg_temp.rub('MP-CAR')), 'MP-CAR', 'el código no cambia');
select is(pg_temp.save(413, 'PL-PAS', '{"description":"Pastas de la carta."}'), 'applied', 'el Chef del grupo, los de menú');
select is(pg_temp.save(413, 'SR-SAL', '{"icon":"oil"}'), 'applied', 'y los de sub-recetas');
select is(pg_temp.save(413, 'MP-CAR', '{"icon":"meat"}'), 'denied', 'pero no los de compra');
select is(pg_temp.save(408, 'PL-PAS', '{"icon":"meat"}'), 'denied', 'ni Compras los de menú');
select is(pg_temp.save(405, 'PL-PAS', '{"icon":"meat"}'), 'denied', 'ni la Chef de una marca (es de todo el grupo)');
select is(pg_temp.save(409, 'SR-SAL', '{"icon":"meat"}'), 'denied', 'ni la Cocinera');
select ok(exists (select 1 from audit.authentication_security_events where operation = 'recipes.save_top_category'), 'y los rechazos quedan registrados');
select is(pg_temp.q(null, format('select recipes.save_top_category(''menu'', %L, now(), ''{"icon":"dish"}'', ''Prueba'') ->> ''result''', pg_temp.rub('PL-PAS'))),
  'denied', 'sin persona, no');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.save_top_category(''subrecipe'', %L, now(), ''{"icon":"dish"}'', ''Prueba'') ->> ''result''', pg_temp.rub('PL-PAS'))),
  'denied', 'con la clase equivocada, no');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.save_top_category(null, %L, now(), ''{"icon":"dish"}'', ''Prueba'') ->> ''result''', pg_temp.rub('PL-PAS'))),
  'denied', 'sin clase, no');
select is(pg_temp.q(pg_temp.u(408), format('select recipes.save_top_category(''purchase'', %L, now(), ''{"name":"X1"}'', ''Prueba'') ->> ''result''',
    (select id from catalog.ingredient_categories where name = 'Cortes de prueba'))), 'denied', 'una subcategoría no se edita desde acá');

-- Errores, en español.
select matches(pg_temp.save(408, 'MP-CAR', '{"icon":"rocket"}'), 'Elegí un ícono de la lista', 'un ícono que no existe');
select matches(pg_temp.save(408, 'MP-CAR', '{"icon":null}'), 'Elegí un ícono de la lista', 'ni vacío');
select matches(pg_temp.save(408, 'MP-CAR', '{"code":"MP-XXX"}'), 'Campos que no se pueden cambiar', 'el código no se manda');
select matches(pg_temp.save(413, 'PL-PAS', '{"used_in_recipes":false}'), 'Campos que no se pueden cambiar', '«va a recetas» es de los de compra');
select matches(pg_temp.save(408, 'MP-CAR', '{"used_in_recipes":"no"}'), 'Elegí si va a recetas', 'y es sí o no');
select matches(pg_temp.save(408, 'MP-CAR', '{"used_in_recipes":null}'), 'Elegí si va a recetas', 'nunca vacío');
select matches(pg_temp.save(408, 'MP-CAR', '{}'), 'No hay cambios', 'sin cambios no guarda');
select matches(pg_temp.save(408, 'MP-CAR', '{"icon":"meat"}', ' '), 'Escribí el motivo', 'ni sin motivo');
select matches(pg_temp.save(408, 'MP-CAR', jsonb_build_object('description', repeat('a', 501))), 'hasta 500', 'ni una descripción larga');
select matches(pg_temp.save(408, 'MP-CAR', '{"name":{"a":1}}'), 'van como texto', 'el nombre es texto');
select matches(pg_temp.save(408, 'MP-CAR', '{"name":123}'), 'van como texto', 'no un número');
select matches(pg_temp.save(408, 'MP-CAR', '{"description":["x"]}'), 'van como texto', 'la descripción también');
select is(pg_temp.save(408, 'MP-CAR', jsonb_build_object('description', E' \n\t ')), 'applied', 'una descripción de renglones vacíos');
select is((select description from catalog.ingredient_categories where id = pg_temp.rub('MP-CAR')), null, 'queda sin descripción');
select matches(pg_temp.save(408, 'MP-CAR', '{"name":" "}'), '^ERROR 2', 'ni un nombre vacío');
select matches(pg_temp.save(408, 'MP-CAR', '{"name":"huevos"}'), 'Ya existe un rubro con ese nombre', 'ni un nombre repetido');
select matches(pg_temp.q(pg_temp.u(408), format('select recipes.save_top_category(''purchase'', %L, %L, ''{"icon":"meat"}'', ''Prueba'')::text',
    pg_temp.rub('MP-CAR'), now() - interval '1 day')), 'Otra persona cambió este rubro', 'con un sello viejo no pisa');
select matches(pg_temp.q(pg_temp.u(408), format('select recipes.save_top_category(''purchase'', %L, null, ''{"icon":"meat"}'', ''Prueba'')::text',
    pg_temp.rub('MP-CAR'))), 'Otra persona cambió este rubro', 'ni sin sello');

-- Sin el segundo factor, quien lo necesita no edita.
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(408), 'role', 'authenticated', 'aal', 'aal1')::text, true);
select is(recipes.save_top_category('purchase', pg_temp.rub('MP-CAR'), now(), '{"icon":"meat"}', 'Prueba') ->> 'result', 'denied', 'Compras sin segundo factor, no');
select set_config('request.jwt.claims', '', true);
-- Un rubro borrado se restaura (su ícono ya está completo).
insert into catalog.ingredient_categories (group_id, name) values (pg_temp.u(1), 'Rubro para borrar');
update catalog.ingredient_categories set deleted_at = now() where name = 'Rubro para borrar';
select lives_ok($$ update catalog.ingredient_categories set deleted_at = null where name = 'Rubro para borrar' $$, 'un rubro borrado se restaura');
insert into recipes.recipe_categories (group_id, name, kind) values (pg_temp.u(1), 'Rubro para borrar', 'menu');
update recipes.recipe_categories set deleted_at = now() where name = 'Rubro para borrar';
select lives_ok($$ update recipes.recipe_categories set deleted_at = null where name = 'Rubro para borrar' $$, 'también los de recetas');
select is((select count(*)::int from catalog.ingredient_categories where name = 'Rubro para borrar' and icon = 'pantry' and deleted_at is null), 1, 'con su ícono');

-- ---------------------------------------------------------------------------
-- La ficha
-- ---------------------------------------------------------------------------
select is(pg_temp.sheet(408, 'MP-VER') ->> 'name', 'Verduras y frutas', 'la ficha trae sus datos');
select ok((pg_temp.sheet(408, 'MP-CAR') -> 'subcategories') ? 'Cortes de prueba', 'y sus subcategorías');
select is((pg_temp.sheet(408, 'MP-VER') -> 'ingredients' ->> 'total')::int,
  (select count(*)::int from catalog.ingredients i join catalog.ingredient_categories c on c.id = i.category_id
    where i.deleted_at is null and (c.id = pg_temp.rub('MP-VER') or c.parent_id = pg_temp.rub('MP-VER'))), 'cuántas materias primas');
select is((pg_temp.sheet(408, 'MP-VER') -> 'ingredients' ->> 'total')::int,
  (select uses::int from recipes.category_overview(pg_temp.u(1)) where code = 'MP-VER'), 'lo mismo que dice el panel');
select ok((pg_temp.sheet(405, 'MP-VER') -> 'recipes' ->> 'total')::int > 0, 'las recetas que las usan, entre las que ve');
select ok((pg_temp.sheet(405, 'MP-VER') -> 'recipes' ->> 'total')::int
          <= (pg_temp.sheet(413, 'MP-VER') -> 'recipes' ->> 'total')::int, 'quien ve una marca no cuenta más que quien ve el grupo');
select is((pg_temp.sheet(413, 'PL-PAS') -> 'recipes' ->> 'total')::int,
  (select uses::int from recipes.category_overview(pg_temp.u(1)) where code = 'PL-PAS'), 'en los de menú, sus recetas');
select ok(pg_temp.sheet(413, 'PL-PAS') -> 'recipes' ? 'open', 'y cuántas tienen una versión abierta');
select is(pg_temp.sheet(409, 'MP-VER'), null, 'la Cocinera no ve los rubros de compra');
select is(pg_temp.sheet(409, 'SR-SAL') ->> 'code', 'SR-SAL', 'los de sub-recetas, sí');
select is(pg_temp.q(gen_random_uuid(), format('select recipes.top_category_sheet(''purchase'', %L)::text', pg_temp.rub('MP-VER'))), null, 'un desconocido, ninguno');

-- ---------------------------------------------------------------------------
-- Con precio al día
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format('select (current + stale + missing = total)::text from costing.category_price_summary(%L, %L)',
  pg_temp.rub('MP-VER'), pg_temp.u(201))), 'true', 'quien ve precios ve cuántas están al día, desactualizadas o sin dato');
select is(pg_temp.q(pg_temp.u(408), format('select current::text from costing.category_price_summary(%L, %L)', pg_temp.rub('MP-VER'), pg_temp.u(201))),
  (select count(*)::text from costing.price_rows(pg_temp.u(201), recipes.today(), null) r
     join catalog.ingredients i on i.id = r.ingredient_id and i.is_active
     join catalog.ingredient_categories c on c.id = i.category_id and (c.id = pg_temp.rub('MP-VER') or c.parent_id = pg_temp.rub('MP-VER'))
    where r.status = 'ok' and not r.stale), 'con el mismo cálculo del motor');
select is(pg_temp.q(pg_temp.u(405), format('select count(*)::text from costing.category_price_summary(%L, %L)', pg_temp.rub('MP-VER'), pg_temp.u(201))),
  '0', 'la Chef no ve precios: ninguna fila, no un cero');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.category_price_summary(%L, %L)', pg_temp.rub('MP-VER'), pg_temp.u(203))),
  '0', 'el Gerente, solo en su local');
select ok(not has_function_privilege('anon', 'costing.category_price_summary(uuid, uuid)', 'execute')
          and not has_function_privilege('anon', 'recipes.save_top_category(recipes.category_class, uuid, timestamptz, jsonb, text)', 'execute')
          and not has_function_privilege('anon', 'recipes.top_category_sheet(recipes.category_class, uuid)', 'execute'), 'anon no llama a nada de esto');
select ok(not has_function_privilege('authenticated', 'catalog.default_category_icon(text)', 'execute'), 'la interna no se llama desde la API');

select * from finish();
rollback;
