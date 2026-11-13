-- Ficha única de receta (ADR-0042, Prompt 2 de Soy del 2026-11-12): guardado en lote en una sola transacción, la
-- grilla que calcula líneas sin guardar con el mismo motor, las porciones automáticas del plato, el rendimiento
-- objetivo congelado de una preparación y quien revisa sin poder editar.
-- Personas del seed: Dirección 402, Gerente 404 (Demo Pastas Centro, 201), Chef de Demo Pastas 405, Jefe de Cocina 406
-- (201), Cocinera 409 (201), Chef del grupo 413.
-- Recetas: Spaghetti al fileto 1107 y Ravioles de ricota 1108 (platos de la marca), Papas rústicas 1105
-- (preparación del grupo).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(48);

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
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.ver(p_recipe int, p_status text) returns uuid language sql as $$
  select id from recipes.recipe_versions where recipe_id = pg_temp.u(p_recipe) and status::text = p_status
$$;
grant execute on function pg_temp.u(int), pg_temp.ver(int, text) to authenticated;

-- Las líneas de Ravioles de ricota, como las manda la grilla.
create temporary table lines (name text primary key, value jsonb);
grant select on lines to authenticated;
-- Las líneas guardadas de la versión vigente de Ravioles, tal cual.
insert into lines
select 'guardadas', jsonb_agg(jsonb_build_object('ingredient_id', c.ingredient_id, 'sub_recipe_id', c.sub_recipe_id,
                                                 'quantity', c.quantity, 'unit', u.code, 'basis', c.quantity_basis,
                                                 'yield_profile_id', c.yield_profile_id) order by c.line_order)
  from recipes.recipe_components c join catalog.units u on u.id = c.unit_id
 where c.recipe_version_id = pg_temp.ver(1108, 'published') and c.deleted_at is null;
insert into lines values
  ('ravioles', jsonb_build_array(
     jsonb_build_object('ingredient_id', pg_temp.u(827), 'quantity', 100, 'unit', 'g'),
     jsonb_build_object('ingredient_id', pg_temp.u(826), 'quantity', 1, 'unit', 'unit'),
     jsonb_build_object('ingredient_id', pg_temp.u(821), 'quantity', 120, 'unit', 'g'),
     jsonb_build_object('ingredient_id', pg_temp.u(820), 'quantity', 20, 'unit', 'g'),
     jsonb_build_object('ingredient_id', pg_temp.u(844), 'quantity', 0.5, 'unit', 'g'))),
  -- Leche en ml (sin densidad), aceite en ml (con densidad 0,92) y una materia prima sin precio.
  ('mezcla', jsonb_build_array(
     jsonb_build_object('ingredient_id', pg_temp.u(823), 'quantity', 100, 'unit', 'ml'),
     jsonb_build_object('ingredient_id', pg_temp.u(833), 'quantity', 100, 'unit', 'ml'))),
  ('papas', jsonb_build_array(
     jsonb_build_object('ingredient_id', pg_temp.u(805), 'quantity', 2000, 'unit', 'g', 'basis', 'purchase'),
     jsonb_build_object('ingredient_id', pg_temp.u(837), 'quantity', 15, 'unit', 'g', 'basis', 'purchase')));

-- ---------------------------------------------------------------------------
-- 1. Lo nuevo existe y solo lo usa quien tiene sesión
-- ---------------------------------------------------------------------------
select has_column('recipes', 'recipe_versions', 'target_yield_ratio', 'la versión guarda el rendimiento objetivo');
select ok(has_function_privilege('authenticated', 'recipes.save_sheet(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb, text, boolean)', 'execute')
          and not has_function_privilege('anon', 'recipes.save_sheet(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb, text, boolean)', 'execute'),
          'save_sheet: solo con sesión');
select ok(has_function_privilege('authenticated', 'costing.preview_sheet_lines(uuid, uuid, jsonb)', 'execute')
          and not has_function_privilege('anon', 'costing.preview_sheet_lines(uuid, uuid, jsonb)', 'execute'),
          'preview_sheet_lines: solo con sesión');
select ok(has_function_privilege('authenticated', 'catalog.ingredient_unit_options(uuid[])', 'execute')
          and not has_function_privilege('anon', 'catalog.ingredient_unit_options(uuid[])', 'execute'),
          'ingredient_unit_options: solo con sesión');
select ok(not has_function_privilege('authenticated', 'recipes.set_target_yield()', 'execute'), 'el trigger no se llama de afuera');

-- ---------------------------------------------------------------------------
-- 2. La grilla: el mismo motor que el costo oficial, y cada uno ve lo suyo
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(405), $$
  select round(sum(line_cost), 2)::text
    from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201), (select value from lines where name = 'guardadas'))$$),
  pg_temp.q(pg_temp.u(405), $$
  select round(sum(line_cost), 2)::text from costing.recipe_cost_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201))$$),
  'las líneas sin guardar cuestan lo mismo que las guardadas (mismo motor)');
select is(pg_temp.q(pg_temp.u(405), $$
  select count(*)::text from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))
   where line_cost is not null$$), '5', 'el Chef ve el costo de cada línea');
select is(pg_temp.q(pg_temp.u(405), $$
  select count(*)::text from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))
   where unit_cost is not null$$), '0', 'el Chef no ve precios (sin prices.view, ADR-0032)');
select is(pg_temp.q(pg_temp.u(404), $$
  select (unit_cost is not null and cost_unit = 'g')::text
    from costing.preview_sheet_lines(pg_temp.ver(1120, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))
   where line_order = 1$$), 'true', 'el Gerente ve el precio por gramo de la harina en su local');
select is(pg_temp.q(pg_temp.u(404), $$
  select (round(unit_cost * 100, 4) = round((select line_cost from costing.ingredient_line_cost(pg_temp.u(827), pg_temp.u(201), 100, (select id from catalog.units where code = 'g'))), 4))::text
    from costing.preview_sheet_lines(pg_temp.ver(1120, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))
   where line_order = 1$$), 'true', 'el precio por gramo es el mismo que usa el costo de una línea');
select is(pg_temp.q(pg_temp.u(406), $$
  select (count(*) filter (where line_cost is not null or unit_cost is not null or status is not null))::text
    from costing.preview_sheet_lines(pg_temp.ver(1120, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))$$),
  '0', 'la Jefa de Cocina ve pesos sin dinero');
select is(pg_temp.q(pg_temp.u(406), $$
  select string_agg(coalesce(grams::text, '-') || ':' || weight_status, ',' order by line_order)
    from costing.preview_sheet_lines(pg_temp.ver(1120, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))$$),
  '100.0000:ok,-:missing_conversion,120.0000:ok,20.0000:ok,0.5000:ok', 'peso por línea; el huevo sin peso por unidad no se adivina');
select is(pg_temp.q(pg_temp.u(409), $$
  select count(*)::text from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))$$),
  'ERROR 42501', 'la Cocinera no usa la grilla');
select is(pg_temp.q(pg_temp.u(405), $$
  select string_agg(coalesce(grams::text, '-') || ':' || weight_status, ',' order by line_order)
    from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201), (select value from lines where name = 'mezcla'))$$),
  '-:missing_conversion,92.0000:ok', 'ml a g: sin densidad no se supone; con densidad, sí');

-- Una materia prima nueva, sin precio en ningún lado.
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
values (pg_temp.u(899), pg_temp.u(1), 'TEST-290-SP', 'Sin precio 290', pg_temp.u(701), (select id from catalog.units where code = 'g'));
select is(pg_temp.q(pg_temp.u(405), $$
  select coalesce(line_cost::text, 'vacío') || ':' || status
    from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201),
                                     jsonb_build_array(jsonb_build_object('ingredient_id', pg_temp.u(899), 'quantity', 50, 'unit', 'g')))$$),
  'vacío:missing_price', 'sin precio, el costo queda vacío (nunca $ 0)');
select is(pg_temp.q(pg_temp.u(405), $$
  select count(*)::text
    from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201),
                                     jsonb_build_array(jsonb_build_object('ingredient_id', pg_temp.u(827), 'quantity', 0, 'unit', 'g'),
                                                       jsonb_build_object('ingredient_id', gen_random_uuid(), 'quantity', 5, 'unit', 'g'),
                                                       jsonb_build_object('quantity', 5, 'unit', 'g')))$$),
  '0', 'las filas incompletas o con cosas de otro grupo no se calculan');
-- El costo de una fila inventada equivale a un precio: solo lo obtiene quien puede editar o publicar la receta
-- (decisión de Joaco del 2026-11-12, revisión de seguridad). El Controller ve costos, pero no usa la grilla.
select is(pg_temp.q(pg_temp.u(407), $$
  select count(*)::text from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201), (select value from lines where name = 'ravioles'))$$),
  'ERROR 42501', 'quien solo ve costos no calcula filas inventadas (sería ver precios)');
select is(pg_temp.q(pg_temp.u(405), $$
  select count(*)::text
    from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201),
                                     jsonb_build_array(jsonb_build_object('sub_recipe_id', pg_temp.u(1112), 'quantity', 50, 'unit', 'ml')))$$),
  '0', 'una preparación de otra marca no se calcula (las mismas reglas que al guardar)');
update catalog.ingredients set is_active = false where id = pg_temp.u(899);
select is(pg_temp.q(pg_temp.u(405), $$
  select count(*)::text
    from costing.preview_sheet_lines(pg_temp.ver(1108, 'published'), pg_temp.u(201),
                                     jsonb_build_array(jsonb_build_object('ingredient_id', pg_temp.u(899), 'quantity', 50, 'unit', 'g')))$$),
  '0', 'una materia prima desactivada no se calcula');
select is(pg_temp.q(pg_temp.u(405), $$
  select string_agg(dimension || ':' || has_density || ':' || has_unit_weight, ',' order by ingredient_id)
    from catalog.ingredient_unit_options(array[pg_temp.u(826), pg_temp.u(833)])$$),
  'count:false:false,volume:true:false', 'las medidas que admite cada materia prima');

-- ---------------------------------------------------------------------------
-- 3. Guardado en lote
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(405), $$
  select (r ->> 'result') || ':' || (r ->> 'created')
    from recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'published'), null,
                            jsonb_build_object('short_name', 'Spaghetti'), jsonb_build_object('portion_grams', 100),
                            null, null, 'Ficha 290: porción chica') r$$),
  'applied:true', 'editar la versión vigente crea el borrador en la misma transacción');
select is((select portion_grams::text || '/' || status::text from recipes.recipe_versions where id = pg_temp.ver(1107, 'published')),
          '350.000000/published', 'la versión vigente no cambia');
select is((select round(yield_quantity, 2)::text || ' ' || (select code from catalog.units where id = yield_unit_id) || ' / ' || portions
             from recipes.recipe_versions where id = pg_temp.ver(1107, 'draft')),
          '2.96 portion / 2', 'plato: porciones = peso de las líneas ÷ peso de la porción (296,2 g ÷ 100 g)');
select is((select short_name from recipes.recipes where id = pg_temp.u(1107)), 'Spaghetti', 'los datos de la receta van en el mismo guardado');
select ok((select count(distinct table_name) >= 2 and bool_and(reason = 'Ficha 290: porción chica')
             from audit.audit_events where reason = 'Ficha 290: porción chica'),
          'un solo motivo en la auditoría de todo el lote');

select is(pg_temp.msg(pg_temp.u(405), $$
  select recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), null, jsonb_build_object('name', 'No se guarda'), null,
                            jsonb_build_array(jsonb_build_object('ingredient_id', pg_temp.u(830), 'quantity', -1, 'unit', 'g', 'basis', 'purchase')),
                            null, 'Ficha 290: lote con error')$$),
  'Línea 1 (Spaghetti secos): la cantidad tiene que ser mayor que cero.', 'una línea inválida frena todo el lote');
select is((select name from recipes.recipes where id = pg_temp.u(1107)), 'Spaghetti al fileto', 'y no se guardó nada');
select is(pg_temp.msg(pg_temp.u(405), $$
  select recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), '2000-01-01', null, jsonb_build_object('description', 'x'),
                            null, null, 'Ficha 290: viejo')$$),
  'Otra persona cambió este borrador mientras lo editabas: recargá la página para ver sus cambios.',
  'si otro guardó mientras tanto, se avisa');
select is(pg_temp.msg(pg_temp.u(405), $$
  select recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), null, null, jsonb_build_object('portion_grams', 1000),
                            null, null, 'Ficha 290: porción enorme')$$),
  'El peso de la porción es mayor que el de toda la receta.', 'una porción más pesada que la receta se rechaza');
-- Sin peso del huevo no se inventan las porciones: se guarda igual y se avisa (decisión de Joaco del 2026-11-12).
select is(pg_temp.q(pg_temp.u(405), $$
  select r ->> 'warning' from recipes.save_sheet(pg_temp.u(1108), pg_temp.ver(1108, 'published'), null, null, null,
                                                  (select value from lines where name = 'ravioles'), null, 'Ficha 290: ravioles') r$$),
  'Las porciones no se recalcularon: falta pasar algún ingrediente a gramos (densidad o peso por unidad).',
  'sin peso del huevo, se guarda y avisa que las porciones no se recalcularon');
select is((select yield_quantity::text || ' ' || (select code from catalog.units where id = yield_unit_id)
             from recipes.recipe_versions where id = pg_temp.ver(1108, 'draft')),
          '1.000000 unit', 'y las porciones quedan como estaban');
select is(pg_temp.msg(pg_temp.u(405), $$
  select recipes.save_sheet(pg_temp.u(1108), pg_temp.ver(1108, 'draft'), null, null, jsonb_build_object('portion_grams', 250),
                            null, null, 'Ficha 290: enviar sin gramos', true)$$),
  'Para enviarla a revisión, todas las líneas tienen que poder pasarse a gramos: así se calculan las porciones.',
  'para enviarla a revisión, las porciones tienen que poder calcularse');
select is(pg_temp.q(pg_temp.u(406), $$
  select r ->> 'result' from recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), null, null,
                                                 jsonb_build_object('description', 'x'), null, null, 'Ficha 290: sin permiso') r$$),
  'denied', 'la Jefa de Cocina no edita una receta de la marca');
select is(pg_temp.q(pg_temp.u(409), $$
  select r ->> 'result' from recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), null, null,
                                                 jsonb_build_object('description', 'x'), null, null, 'Ficha 290: sin permiso') r$$),
  'denied', 'la Cocinera tampoco');
select is(pg_temp.msg(pg_temp.u(405), $$
  select recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), null, null, jsonb_build_object('description', 'x'),
                            null, null, ' ')$$),
  'Escribí el motivo de los cambios.', 'sin motivo no se guarda');

-- ---------------------------------------------------------------------------
-- 4. Enviar a revisión y quien revisa
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(405), $$
  select r ->> 'result' from recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'draft'), null, null,
                                                 jsonb_build_object('description', 'Porción chica de prueba'), null, null,
                                                 'Ficha 290: guardar y enviar', true) r$$),
  'pending_approval', 'guardar y enviar a revisión, en el mismo paso');
select is((select coalesce(target_yield_ratio::text, 'vacío') from recipes.recipe_versions where id = pg_temp.ver(1107, 'in_review')),
          'vacío', 'un plato no tiene rendimiento objetivo');
select is(pg_temp.msg(pg_temp.u(413), $$
  select recipes.save_sheet(pg_temp.u(1107), pg_temp.ver(1107, 'in_review'), null, null, jsonb_build_object('description', 'Lo cambio yo'),
                            null, null, 'Ficha 290: quien revisa')$$),
  'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.',
  'quien revisa no edita con la ficha');
select is(pg_temp.msg(pg_temp.u(413), $$
  select recipes.set_components(pg_temp.ver(1107, 'in_review'), (select value from lines where name = 'mezcla'), 'Ficha 290: quien revisa')$$),
  'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.',
  'ni con las funciones de siempre');
select is((select description from recipes.recipe_versions where id = pg_temp.ver(1107, 'in_review')), 'Porción chica de prueba',
          'la versión en revisión quedó como se envió');
select is(pg_temp.q(pg_temp.u(405), $$
  select r ->> 'result' from workflow.decide_approval((select approval_request_id from recipes.recipe_versions where id = pg_temp.ver(1107, 'in_review')),
                                                      'approved', 'Me apruebo') r$$),
  'denied', 'quien pidió la revisión no la aprueba');
select is(pg_temp.q(pg_temp.u(413), $$
  select r ->> 'result' from workflow.decide_approval((select approval_request_id from recipes.recipe_versions where id = pg_temp.ver(1107, 'in_review')),
                                                      'approved', 'Bien la porción') r$$),
  'approved', 'otra persona con permiso la aprueba desde la ficha');
select is((select round(yield_quantity, 2)::text from recipes.recipe_versions where id = pg_temp.ver(1107, 'published')), '2.96',
          'y se publica con sus porciones');

-- Preparación: el rendimiento objetivo queda congelado.
select is(pg_temp.q(pg_temp.u(413), $$
  select r ->> 'result' from recipes.save_sheet(pg_temp.u(1105), pg_temp.ver(1105, 'published'), null, null,
                                                 jsonb_build_object('yield_quantity', 1.5, 'yield_unit', 'kg'),
                                                 (select value from lines where name = 'papas'), null, 'Ficha 290: papas', true) r$$),
  'pending_approval', 'una preparación se guarda y se envía');
select is((select target_yield_ratio::text from recipes.recipe_versions where id = pg_temp.ver(1105, 'in_review')), '0.744400',
          'rendimiento objetivo = 1.500 g netos ÷ 2.015 g brutos');
select is(pg_temp.q(pg_temp.u(402), $$
  select r ->> 'result' from workflow.decide_approval((select approval_request_id from recipes.recipe_versions where id = pg_temp.ver(1105, 'in_review')),
                                                      'approved', 'Ok') r$$),
  'approved', 'Dirección la aprueba');
select throws_ok($$update recipes.recipe_versions set target_yield_ratio = 0.9 where id = pg_temp.ver(1105, 'published')$$,
                 null, 'el rendimiento objetivo aprobado no cambia más');
select is((select target_yield_ratio::text from recipes.recipe_versions where id = pg_temp.ver(1105, 'published')), '0.744400',
          'el control de lotes lee el objetivo de la versión vigente');

select * from finish();
rollback;
