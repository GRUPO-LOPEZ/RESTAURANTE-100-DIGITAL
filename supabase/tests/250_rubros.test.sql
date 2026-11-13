-- Rubros (ADR-0038): las categorías del primer nivel llevan código (MP-, SR-, PL-), clase y «activo».
-- Un plato va en un rubro de menú; una preparación o un componente, en uno de sub-recetas. La baja con usos
-- pide un destino y pasa todo en la misma transacción. Permisos para todo el grupo: compra con catalog.manage o
-- prices.configure; sub-recetas y menú con recipes.manage_categories. Todo queda en la auditoría.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(115);

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
-- Id de un rubro vigente por su código (como postgres: sin RLS).
create function pg_temp.rub(p_code text) returns uuid language sql as $$
  select id from recipes.top_categories where code = p_code and group_id = '00000000-0000-4000-8000-000000000001'
$$;
create function pg_temp.uses(p_user uuid, p_code text) returns text language sql as $$
  select pg_temp.q(p_user, format($q$select uses::text from recipes.category_overview(%L) where code = %L$q$,
                                  '00000000-0000-4000-8000-000000000001', p_code))
$$;
grant execute on function pg_temp.u(int), pg_temp.rub(text) to authenticated;

-- Compras (408) y Superadmin (401): catalog.manage de grupo. Dirección (402): prices.configure de grupo.
-- Chef del grupo (413): recipes.manage_categories de grupo.
-- Chef de marca (405): recipes.manage_categories en su marca. Cocinera de Demo Pastas (409): solo ve.

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_column('catalog', 'ingredient_categories', 'code', 'las categorías de materias primas tienen código');
select has_column('recipes', 'recipe_categories', 'kind', 'las de recetas tienen clase');
select throws_ok($$insert into recipes.recipe_categories (group_id, name) values (pg_temp.u(1), 'Sin clase')$$,
  '23514', 'Elegí la clase del rubro: sub-recetas o menú.', 'y la clase es obligatoria');
select ok((select relrowsecurity from pg_class where oid = 'catalog.ingredient_categories'::regclass)
          and (select relrowsecurity from pg_class where oid = 'recipes.recipe_categories'::regclass),
  'las dos tablas siguen con RLS');

-- ---------------------------------------------------------------------------
-- Los rubros de Soy en el seed, con las categorías viejas mapeadas
-- ---------------------------------------------------------------------------
select is((select count(*)::int from recipes.top_categories where group_id = pg_temp.u(1) and category_class = 'purchase'),
  21, 'compra: los 20 de Soy más «Almacén», que no coincide con ninguno');
select is((select count(*)::int from recipes.top_categories where group_id = pg_temp.u(1) and category_class = 'subrecipe'),
  11, 'sub-recetas: los 11 de Soy');
select is((select count(*)::int from recipes.top_categories where group_id = pg_temp.u(1) and category_class = 'menu'),
  15, 'menú: los 15 de Soy');
select is((select code from catalog.ingredient_categories where id = pg_temp.u(702)), 'MP-CAR',
  'la categoría vieja «Carnes» conserva su nombre y lleva el código de Soy');
select is((select code from catalog.ingredient_categories where id = pg_temp.u(707)), 'MP-ALM',
  '«Almacén» lleva un código propio, generado con el prefijo');
select is(recipes.install_default_categories(pg_temp.u(1)), 0, 'cargar los rubros de Soy otra vez no cambia nada');
select is((select count(*)::int from recipes.recipe_categories where parent_id is not null and code is not null), 0,
  'ninguna subcategoría tiene código');

-- ---------------------------------------------------------------------------
-- Restricciones
-- ---------------------------------------------------------------------------
select throws_ok($$insert into recipes.recipe_categories (group_id, name, kind, code) values (pg_temp.u(1), 'Mal', 'menu', 'SR-MAL')$$,
  '23514', null, 'un rubro de menú no lleva código SR');
select throws_ok($$insert into catalog.ingredient_categories (group_id, name, code) values (pg_temp.u(1), 'Mal', 'MP-malo')$$,
  '23514', null, 'el código va en mayúsculas y con 3 letras o números');
select throws_ok($$insert into catalog.ingredient_categories (group_id, parent_id, name, code)
                   values (pg_temp.u(1), pg_temp.u(702), 'Aves', 'MP-AVE')$$,
  '23514', null, 'una subcategoría no lleva código');
select throws_ok($$update catalog.ingredient_categories set code = 'MP-ZZZ' where id = pg_temp.u(702)$$,
  '42501', 'El código de un rubro no cambia.', 'el código de un rubro no cambia');
select throws_ok($$update recipes.recipe_categories set kind = 'menu' where id = pg_temp.u(1061)$$,
  '42501', 'La clase de un rubro no cambia.', 'la clase de un rubro no cambia');
select throws_ok($$insert into recipes.recipe_categories (group_id, name, kind, code) values (pg_temp.u(1), 'Otra', 'menu', 'PL-PAS')$$,
  '23505', null, 'el código no se repite en el grupo');

-- ---------------------------------------------------------------------------
-- Conteos del panel (una consulta agrupada, con los permisos de quien consulta)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(401), $$select count(*)::text from recipes.category_overview(pg_temp.u(1))$$), '47',
  'el Superadministrador ve los 47 rubros del grupo');
select is(pg_temp.uses(pg_temp.u(413), 'PL-CAR'), '4', 'el Chef del grupo cuenta las 4 recetas de Carnes');
select is(pg_temp.uses(pg_temp.u(408), 'MP-CAR'),
  (select count(*)::text from catalog.ingredients i join catalog.ingredient_categories c on c.id = i.category_id
    where coalesce(c.parent_id, c.id) = pg_temp.u(702) and i.deleted_at is null),
  'Compras cuenta las materias primas de Carnes, con las de sus subcategorías');
select is(pg_temp.uses(pg_temp.u(409), 'PL-CAR'), '0',
  'la Cocinera de Pastas no cuenta las recetas de Carnes, que son de otra marca y no ve');
select is(pg_temp.q(pg_temp.u(413), $$select sum(mismatched)::text from recipes.category_overview(pg_temp.u(1))$$), '0',
  'en el seed ninguna receta queda en un rubro de la otra clase');
select ok(not has_function_privilege('anon', 'recipes.category_overview(uuid)', 'execute'), 'anon no puede contar');
select ok(not has_table_privilege('anon', 'recipes.top_categories', 'select'), 'anon no lee la vista de rubros');
select ok(not has_function_privilege('authenticated', 'recipes.install_default_categories(uuid)', 'execute'),
  'nadie carga los rubros de Soy desde la app');
select ok((select reloptions from pg_class where oid = 'recipes.top_categories'::regclass) @> '{security_invoker=true}',
  'la vista de rubros lee con los permisos de quien consulta');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from recipes.top_categories$$), '47',
  'Compras (ve materias primas y recetas) ve los 47 rubros');
select is(pg_temp.q(pg_temp.u(409), $$select count(*) filter (where category_class = 'purchase')::text || '/' || count(*)::text
                                       from recipes.top_categories$$), '0/26',
  'la Cocinera (ve recetas, no materias primas) ve solo los 26 de sub-recetas y de menú');
select is(pg_temp.q(gen_random_uuid(), $$select count(*)::text from recipes.top_categories$$), '0',
  'alguien sin permisos en el grupo no ve ninguno');

-- ---------------------------------------------------------------------------
-- Un plato va en un rubro de menú; una preparación o un componente, en uno de sub-recetas
-- ---------------------------------------------------------------------------
select ok(pg_temp.q(pg_temp.u(413), $$select recipes.create_recipe(pg_temp.u(1), null, null, 'Plato de prueba', 'dish',
                                        pg_temp.rub('PL-PAS'), 'Prueba') ->> 'result'$$) = 'applied',
  'un plato entra en un rubro de menú');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_recipe(pg_temp.u(1), null, null, 'Plato mal', 'dish',
                                        pg_temp.rub('SR-SAL'), 'Prueba')$$),
  'Un plato va en un rubro de menú; una preparación o un componente, en un rubro de sub-recetas.',
  'un plato no entra en un rubro de sub-recetas');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_recipe(pg_temp.u(1), null, null, 'Salsa mal', 'preparation',
                                        pg_temp.rub('PL-PAS'), 'Prueba')$$),
  'Un plato va en un rubro de menú; una preparación o un componente, en un rubro de sub-recetas.',
  'una preparación no entra en un rubro de menú');
-- Desde ADR-0041 ya no se crean componentes por unidad: se simula uno cargado antes.
select core.set_change_context('Componente cargado antes de ADR-0041', 'maintenance');
select lives_ok($$insert into recipes.recipes (group_id, scope_type, code, name, recipe_type, category_id)
                  values (pg_temp.u(1), 'group', 'RUB-04', 'Medallón', 'unit_component', pg_temp.rub('SR-COC'))$$,
  'un componente unitario (cargado antes) va en un rubro de sub-recetas');
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.update_recipe(%L, '{"category_id": "%s"}', 'Cambio de rubro')$$,
                                             pg_temp.u(1107), pg_temp.rub('SR-SAL'))),
  'Un plato va en un rubro de menú; una preparación o un componente, en un rubro de sub-recetas.',
  'al cambiarle el rubro a un plato también se controla');
-- Lo cargado antes de los rubros no se toca: editar otra cosa sigue funcionando y el panel lo cuenta.
alter table recipes.recipes disable trigger enforce_recipe_category_class;
update recipes.recipes set category_id = pg_temp.u(1061) where id = pg_temp.u(1107);
alter table recipes.recipes enable trigger enforce_recipe_category_class;
select lives_ok($$update recipes.recipes set short_name = 'Spaghetti' where id = pg_temp.u(1107)$$,
  'una receta vieja en un rubro de la otra clase se puede seguir editando');
select is(pg_temp.q(pg_temp.u(413), $$select mismatched::text from recipes.category_overview(pg_temp.u(1)) where code = 'SR-SAL'$$),
  '1', 'y el panel la cuenta para corregirla');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.deactivate_top_category('subrecipe', pg_temp.rub('SR-SAL'), 'Prueba', pg_temp.rub('SR-FON'))$$),
  'Tiene 1 receta de la otra clase (un plato va en menú; una preparación o un componente, en sub-recetas): corregí su rubro antes de darlo de baja.',
  'la baja de un rubro con una receta de la otra clase pide corregirla antes');
select lives_ok($$insert into recipes.recipes (group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id,
                                               variant_of_recipe_id)
                  values (pg_temp.u(1), pg_temp.u(101), pg_temp.u(201), 'restaurant', 'RUB-VAR', 'Variante de prueba', 'dish',
                          pg_temp.u(1061), pg_temp.u(1107))$$,
  'una variante nueva copia el rubro de su maestra aunque sea de la otra clase (se corrige en la maestra)');
delete from recipes.recipes where code = 'RUB-VAR';
update recipes.recipes set category_id = pg_temp.u(1062) where id = pg_temp.u(1107);

-- ---------------------------------------------------------------------------
-- Alta
-- ---------------------------------------------------------------------------
select ok(pg_temp.q(pg_temp.u(408), $$select recipes.create_top_category(pg_temp.u(1), 'purchase', 'Panificados', 'Rubro nuevo')::text$$)
          ~ '^[0-9a-f-]{36}$', 'Compras crea un rubro de compra');
select is((select code from catalog.ingredient_categories where name = 'Panificados' and deleted_at is null), 'MP-PAN',
  'con el código armado del nombre');
select ok(pg_temp.q(pg_temp.u(408), $$select recipes.create_top_category(pg_temp.u(1), 'purchase', 'Pancetas', 'Rubro nuevo')::text$$)
          ~ '^[0-9a-f-]{36}$', 'Compras crea otro con las mismas 3 letras');
select is((select code from catalog.ingredient_categories where name = 'Pancetas' and deleted_at is null), 'MP-PA1',
  'si las 3 letras ya están tomadas, usa 2 y un número');
select ok(pg_temp.q(pg_temp.u(413), $$select recipes.create_top_category(pg_temp.u(1), 'menu', 'Tápas', 'Rubro nuevo')::text$$)
          ~ '^[0-9a-f-]{36}$', 'el Chef del grupo crea un rubro de menú');
select is((select code from recipes.recipe_categories where name = 'Tápas' and deleted_at is null), 'PL-TAP',
  'sin tildes en el código');
select ok(exists (select 1 from audit.audit_events where table_schema = 'recipes' and table_name = 'recipe_categories'
                    and action = 'insert' and actor_user_id = pg_temp.u(413) and reason = 'Rubro nuevo'),
  'el alta queda en la auditoría, con quién y por qué');
select is(pg_temp.q(pg_temp.u(408), $$select recipes.create_top_category(pg_temp.u(1), 'menu', 'Otro', 'Prueba')::text$$),
  'ERROR 42501', 'Compras no crea rubros de menú');
select is(pg_temp.q(pg_temp.u(413), $$select recipes.create_top_category(pg_temp.u(1), 'purchase', 'Otro', 'Prueba')::text$$),
  'ERROR 42501', 'el Chef no crea rubros de compra');
select is(pg_temp.q(pg_temp.u(405), $$select recipes.create_top_category(pg_temp.u(1), 'subrecipe', 'Otro', 'Prueba')::text$$),
  'ERROR 42501', 'el Chef de una marca no crea rubros (son de todo el grupo)');
select is(pg_temp.q(pg_temp.u(409), $$select recipes.create_top_category(pg_temp.u(1), 'subrecipe', 'Otro', 'Prueba')::text$$),
  'ERROR 42501', 'la Cocinera tampoco');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_top_category(pg_temp.u(1), 'menu', 'pastas', 'Repetido')$$),
  'Ya existe un rubro con ese nombre.', 'el nombre no se repite entre los rubros de recetas del grupo (sub-recetas y menú comparten la lista)');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_top_category(pg_temp.u(1), 'menu', 'Otro', '')$$),
  'El motivo del cambio es obligatorio y puede tener hasta 500 caracteres.', 'sin motivo no se crea');

-- ---------------------------------------------------------------------------
-- Cambio de nombre
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.rename_top_category('menu', pg_temp.rub('PL-TAP'), 'Tapas y pinchos', 'Cambio de nombre desde Rubros')$$),
  'sin error', 'el Chef cambia el nombre de un rubro de menú');
select is((select name from recipes.recipe_categories where code = 'PL-TAP'), 'Tapas y pinchos', 'el código sigue igual');
select ok(exists (select 1 from audit.audit_events where table_schema = 'recipes' and table_name = 'recipe_categories'
                    and action = 'update' and reason = 'Cambio de nombre desde Rubros'),
  'el cambio de nombre queda en la auditoría');
select is(pg_temp.q(pg_temp.u(413), $$select recipes.rename_top_category('purchase', pg_temp.rub('PL-TAP'), 'X', 'Prueba')::text$$),
  'ERROR 42501', 'con la clase equivocada no lo encuentra (y no revela si existe)');

-- ---------------------------------------------------------------------------
-- Baja con destino y reactivación
-- ---------------------------------------------------------------------------
select ok(pg_temp.msg(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-CAR'), 'Ya no se usa')$$)
          ~ '^Tiene \d+ materias primas: elegí a qué rubro pasarlas antes de darlo de baja\.$',
  'un rubro con materias primas no se da de baja sin destino');
select is(pg_temp.msg(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-CAR'), 'Prueba', pg_temp.rub('PL-PAS'))$$),
  'Elegí otro rubro activo de la misma clase como destino.', 'el destino tiene que ser de la misma clase');
select is(pg_temp.msg(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-CAR'), 'Prueba', pg_temp.rub('MP-CAR'))$$),
  'Elegí otro rubro activo de la misma clase como destino.', 'ni el mismo rubro');
-- Las materias primas de Carnes tienen precios. Pasarlas a otro rubro cambia cuándo un precio está desactualizado:
-- Compras lo hace también fuera de una baja, con motivo y auditoría (ADR-0044; antes lo decidía Dirección). Al dar de
-- baja el rubro, las pasa Compras o Dirección, cada uno por su cuenta (decisión de Joaco, 2026-11-10).
create temporary table moved (id uuid);
insert into moved
select i.id from catalog.ingredients i
  join catalog.purchase_products pp on pp.ingredient_id = i.id
  join costing.price_records p on p.purchase_product_id = pp.id
 where i.category_id = pg_temp.u(702) and p.deleted_at is null and i.deleted_at is null
 limit 1;
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.update_ingredient(%L, '{"category_id": "%s"}', 'Otro rubro')$$,
                                            (select id from moved), pg_temp.rub('MP-PES'))),
  'sin error', 'fuera de una baja, Compras pasa a otro rubro una materia prima con precios (ADR-0044)');
-- Vuelve a Carnes, para que la baja de abajo la mueva con el resto.
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.update_ingredient(%L, '{"category_id": "%s"}', 'Vuelve')$$,
                                            (select id from moved), pg_temp.u(702))),
  'sin error', 'y la vuelve a Carnes');
select ok(pg_temp.q(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-CAR'), 'Se junta con pescados',
                                                                              pg_temp.rub('MP-PES'))::text$$) ~ '^[1-9][0-9]*$',
  'al dar de baja Carnes, Compras pasa sus materias primas con precios a otro rubro');
select is((select count(*)::int from catalog.ingredients i join catalog.ingredient_categories c on c.id = i.category_id
            where coalesce(c.parent_id, c.id) = pg_temp.u(702) and i.deleted_at is null),
  0, 'no queda ninguna en Carnes ni en sus subcategorías');
select is((select is_active from catalog.ingredient_categories where id = pg_temp.u(702)), false, 'y Carnes queda dado de baja');
select is(pg_temp.msg(pg_temp.u(402), $$select recipes.reactivate_top_category('purchase', pg_temp.u(702), 'Vuelve Carnes')$$),
  'sin error', 'Dirección también administra los rubros de compra: reactiva Carnes');
select ok(pg_temp.q(pg_temp.u(402), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-PES'), 'Vuelven a Carnes',
                                                                              pg_temp.rub('MP-CAR'))::text$$) ~ '^[1-9][0-9]*$',
  'y Dirección, por su cuenta, da de baja un rubro con materias primas con precios');
select ok(exists (select 1 from catalog.ingredients i
                    join catalog.purchase_products pp on pp.ingredient_id = i.id
                    join costing.price_records p on p.purchase_product_id = pp.id
                   where i.category_id = pg_temp.u(702) and p.deleted_at is null),
  'las materias primas con precios volvieron a Carnes');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredients'
                    and action = 'update' and reason = 'Vuelven a Carnes' and actor_user_id = pg_temp.u(402)),
  'el pase queda en la auditoría, con quién y por qué');
-- Panificados, con una materia prima en el rubro y otra en una subcategoría (sin precios): pasan las dos.
select ok(pg_temp.q(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'Panes', 'Subcategoría', pg_temp.rub('MP-PAN'))::text$$)
          ~ '^[0-9a-f-]{36}$', 'Compras crea una subcategoría de Panificados');
insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id)
values (pg_temp.u(1), 'RUB-ING-1', 'Pan rallado de prueba', pg_temp.rub('MP-PAN'), (select id from catalog.units where code = 'g')),
       (pg_temp.u(1), 'RUB-ING-2', 'Pan de molde de prueba',
        (select id from catalog.ingredient_categories where name = 'Panes' and deleted_at is null), (select id from catalog.units where code = 'g'));
select is(pg_temp.q(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-PAN'), 'Se junta con harinas',
                                                                              pg_temp.rub('MP-HAR'))::text$$),
  '2', 'con destino, Compras lo da de baja y dice cuántas pasó');
select is((select count(*)::int from catalog.ingredients where code in ('RUB-ING-1', 'RUB-ING-2') and category_id = pg_temp.rub('MP-HAR')),
  2, 'las dos pasaron al destino, también la de la subcategoría');
select is((select is_active from catalog.ingredient_categories where name = 'Panificados' and deleted_at is null), false,
  'el rubro queda dado de baja');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_categories'
                    and action = 'update' and reason = 'Se junta con harinas' and actor_user_id = pg_temp.u(408)
                    and new_values ->> 'is_active' = 'false'),
  'la baja del rubro queda en la auditoría, con quién y por qué');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredients'
                    and action = 'update' and reason = 'Se junta con harinas'),
  'el pase de las materias primas queda en la auditoría con el motivo de la baja');
select throws_ok($$insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id)
                   values (pg_temp.u(1), 'RUB-ING-3', 'Pan de prueba', (select id from catalog.ingredient_categories where name = 'Panificados'),
                           (select id from catalog.units where code = 'g'))$$,
  '23514', 'Ese rubro está dado de baja: elegí otro.', 'un rubro dado de baja no recibe materias primas nuevas');
select throws_ok($$insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id)
                   values (pg_temp.u(1), 'RUB-ING-4', 'Pan de prueba', (select id from catalog.ingredient_categories where name = 'Panes'),
                           (select id from catalog.units where code = 'g'))$$,
  '23514', 'Ese rubro está dado de baja: elegí otro.', 'ni en una subcategoría suya');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'Facturas', 'Subcategoría',
                                                                       (select id from catalog.ingredient_categories where name = 'Panificados'))$$),
  'Ese rubro está dado de baja: elegí otro.', 'ni subcategorías nuevas');
select is(pg_temp.msg(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase',
                                          (select id from catalog.ingredient_categories where name = 'Panificados'), 'Otra vez')$$),
  'Ese rubro ya está dado de baja.', 'no se da de baja dos veces');
select is(pg_temp.q(pg_temp.u(413), $$select recipes.deactivate_top_category('subrecipe', pg_temp.rub('SR-COC'), 'Se junta',
                                                                              pg_temp.rub('SR-SAL'))::text$$),
  '2', 'el Chef da de baja un rubro de sub-recetas y pasa sus recetas (la bondiola y el medallón)');
select is((select category_id from recipes.recipes where id = pg_temp.u(1115)), pg_temp.rub('SR-SAL'),
  'la bondiola braseada quedó en Salsas');
select is(pg_temp.q(pg_temp.u(408), $$select recipes.deactivate_top_category('purchase', pg_temp.rub('MP-LIM'), 'Sin uso')::text$$),
  '0', 'un rubro sin uso se da de baja sin destino');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.deactivate_top_category('subrecipe', pg_temp.rub('SR-MAS'), 'Prueba')$$),
  'Tiene 1 receta: elegí a qué rubro pasarla antes de darlo de baja.', 'con un solo uso, el mensaje va en singular');
select is(pg_temp.msg(pg_temp.u(408), $$select recipes.reactivate_top_category('purchase',
                                          (select id from catalog.ingredient_categories where name = 'Panificados'), 'Vuelve')$$),
  'sin error', 'Compras reactiva un rubro');
select is((select is_active from catalog.ingredient_categories where name = 'Panificados' and deleted_at is null), true,
  'y queda activo otra vez');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_categories'
                    and action = 'update' and reason = 'Vuelve' and new_values ->> 'is_active' = 'true'),
  'la reactivación queda en la auditoría con su motivo');
select is(pg_temp.msg(pg_temp.u(408), $$select recipes.reactivate_top_category('purchase',
                                          (select id from catalog.ingredient_categories where name = 'Panificados'), 'Otra vez')$$),
  'Ese rubro ya está activo.', 'no se reactiva dos veces');
select is(pg_temp.q(pg_temp.u(409), $$select recipes.reactivate_top_category('subrecipe', pg_temp.rub('SR-COC'), 'Prueba')::text$$),
  'ERROR 42501', 'la Cocinera no reactiva');
select is(pg_temp.q(pg_temp.u(408), $$select recipes.deactivate_top_category('menu', pg_temp.rub('PL-SOP'), 'Prueba')::text$$),
  'ERROR 42501', 'Compras no da de baja rubros de menú');

-- Permiso propio para los rubros de sub-recetas y menú (decisión de Joaco, 2026-11-10).
select results_eq(
  $$select r.code from core.role_permissions rp join core.roles r on r.id = rp.role_id
      join core.permissions p on p.id = rp.permission_id
     where p.code = 'recipes.manage_categories' and rp.deleted_at is null order by 1$$,
  $$select r.code from core.role_permissions rp join core.roles r on r.id = rp.role_id
      join core.permissions p on p.id = rp.permission_id
     where p.code = 'recipes.draft' and rp.deleted_at is null order by 1$$,
  'recipes.manage_categories arranca en los roles que tenían recipes.draft');
select core.set_change_context('Soy le da el permiso de rubros a Compras', 'manual');
insert into core.role_permissions (role_id, permission_id)
select r.id, p.id from core.roles r, core.permissions p where r.code = 'purchasing' and p.code = 'recipes.manage_categories';
select ok(pg_temp.q(pg_temp.u(408), $$select recipes.create_top_category(pg_temp.u(1), 'menu', 'Picadas', 'Rubro nuevo')::text$$)
          ~ '^[0-9a-f-]{36}$', 'si Soy le da el permiso a otro rol (Compras, sin recipes.draft), ese rol crea rubros de menú');
-- Y si se lo saca a un rol, ese rol tampoco cambia rubros por las funciones de antes (revisión de seguridad).
select core.set_change_context('Soy le saca el permiso de rubros al Chef', 'manual');
update core.role_permissions set deleted_at = now()
 where role_id = (select id from core.roles where code = 'executive_chef')
   and permission_id = (select id from core.permissions where code = 'recipes.manage_categories');
select is(pg_temp.q(pg_temp.u(413), $$select recipes.create_top_category(pg_temp.u(1), 'menu', 'Otro', 'Prueba')::text$$),
  'ERROR 42501', 'sin el permiso, el Chef ya no crea rubros (aunque tenga recipes.draft)');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.rename_category(pg_temp.rub('PL-SOP'), 'Caldos', 'Prueba')$$),
  'No tenés permiso para editar este rubro.', 'ni los renombra con la función de antes de los rubros');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.archive_category(pg_temp.rub('PL-PIC'), 'Prueba')$$),
  'No tenés permiso para editar este rubro.', 'ni los borra con la función de antes (Picadas, vacío)');
select ok(pg_temp.q(pg_temp.u(413), $$select recipes.create_category(pg_temp.u(1), 'Rellenas', 'Subcategoría', pg_temp.rub('PL-PAS'))::text$$)
          ~ '^[0-9a-f-]{36}$', 'las subcategorías siguen con recipes.draft: el Chef crea una');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.rename_category((select id from recipes.recipe_categories
                                          where name = 'Rellenas' and deleted_at is null), 'Pastas rellenas', 'Prueba')$$),
  'sin error', 'y le cambia el nombre');
select ok(pg_temp.q(pg_temp.u(402), $$select recipes.create_top_category(pg_temp.u(1), 'purchase', 'Hielo', 'Rubro nuevo')::text$$)
          ~ '^[0-9a-f-]{36}$', 'Dirección, sin catalog.manage, crea un rubro de compra');

-- ---------------------------------------------------------------------------
-- Mapeo de las categorías ya cargadas (sección 5 de la migración)
-- ---------------------------------------------------------------------------
alter table catalog.ingredient_categories drop constraint ingredient_categories_code_level;
alter table recipes.recipe_categories drop constraint recipe_categories_code_level, drop constraint recipe_categories_kind_required;
alter table catalog.ingredient_categories disable trigger enforce_rubro_fields;
alter table recipes.recipe_categories disable trigger enforce_rubro_fields;
alter table recipes.recipes disable trigger enforce_recipe_category_class;
insert into org.groups (id, name) values (pg_temp.u(60001), 'Grupo con categorías viejas');
insert into catalog.ingredient_categories (id, group_id, name, deleted_at) values
  (pg_temp.u(60101), pg_temp.u(60001), 'Carnes', null),
  (pg_temp.u(60102), pg_temp.u(60001), 'Lácteos', null),
  (pg_temp.u(60103), pg_temp.u(60001), 'Verduras y frutas', null),
  (pg_temp.u(60104), pg_temp.u(60001), 'Frutas', null),
  (pg_temp.u(60105), pg_temp.u(60001), 'Almacén', null),
  (pg_temp.u(60106), pg_temp.u(60001), 'Almacén seco', null),
  (pg_temp.u(60107), pg_temp.u(60001), 'Pescados', null),
  (pg_temp.u(60108), pg_temp.u(60001), 'Pescados congelados', null),
  (pg_temp.u(60109), pg_temp.u(60001), 'Viejos', null);
-- Una borrada (el trigger de control pone deleted_at; al insertar no se puede).
update catalog.ingredient_categories set deleted_at = now() where id = pg_temp.u(60109);
insert into catalog.ingredient_categories (id, group_id, parent_id, name)
values (pg_temp.u(60110), pg_temp.u(60001), pg_temp.u(60102), 'Quesos');
insert into recipes.recipe_categories (id, group_id, parent_id, name) values
  (pg_temp.u(60201), pg_temp.u(60001), null, 'Salsas'),
  (pg_temp.u(60202), pg_temp.u(60001), null, 'Platos fuertes'),
  (pg_temp.u(60203), pg_temp.u(60001), null, 'Guarniciones'),
  (pg_temp.u(60204), pg_temp.u(60001), null, 'Masas');
insert into recipes.recipe_categories (id, group_id, parent_id, name)
values (pg_temp.u(60205), pg_temp.u(60001), pg_temp.u(60202), 'Rellenas');
insert into recipes.recipes (group_id, scope_type, code, name, recipe_type, category_id)
select pg_temp.u(60001), 'group', 'VIEJA-' || n, 'Receta vieja ' || n, t::recipes.recipe_type, pg_temp.u(c)
  from (values (1, 'preparation', 60201), (2, 'dish', 60202), (3, 'dish', 60205), (4, 'preparation', 60202),
               (5, 'dish', 60203), (6, 'preparation', 60203)) as v (n, t, c);
do $$ begin perform core.set_change_context('Prueba del mapeo de rubros', 'maintenance'); end $$;
select is(recipes.map_legacy_categories(pg_temp.u(60001), '{"almacen seco": "MP-CON"}'), 8,
  'el mapeo le pone el código de Soy a 8 categorías viejas');
-- Las categorías de staging (consulta de Joaco del 2026-11-10), con las equivalencias que aprobó Soy el
-- 2026-11-11. El mismo texto que el llamado de la migración: si cambia uno, cambiar el otro.
insert into org.groups (id, name) values (pg_temp.u(60002), 'Grupo como staging');
insert into catalog.ingredient_categories (id, group_id, name) values
  (pg_temp.u(60301), pg_temp.u(60002), 'Carne'),
  (pg_temp.u(60302), pg_temp.u(60002), 'QUESOS'),
  (pg_temp.u(60303), pg_temp.u(60002), 'Verdura');
insert into recipes.recipe_categories (id, group_id, name) values
  (pg_temp.u(60401), pg_temp.u(60002), 'CARNES'),
  (pg_temp.u(60402), pg_temp.u(60002), 'PASTAS'),
  (pg_temp.u(60403), pg_temp.u(60002), 'PESCADOS'),
  (pg_temp.u(60404), pg_temp.u(60002), 'POSTRES');
insert into recipes.recipes (group_id, scope_type, code, name, recipe_type, category_id)
values (pg_temp.u(60002), 'group', 'STG-1', 'Plato de carne de staging', 'dish', pg_temp.u(60401));
select is(recipes.map_legacy_categories(pg_temp.u(60002),
            '{"carne": "MP-CAR", "quesos": "MP-LAC", "verdura": "MP-VER", "carnes": "PL-CAR", "pescados": "PL-PES"}'),
  7, 'staging: las 7 categorías se emparejan con un rubro de Soy');
select is((select string_agg(code || ' ' || name, ', ' order by code) from catalog.ingredient_categories
            where id in (pg_temp.u(60301), pg_temp.u(60302), pg_temp.u(60303))),
  'MP-CAR Carnes y aves, MP-LAC Lácteos y quesos, MP-VER Verduras y hortalizas',
  'staging, compra: Carne, QUESOS y Verdura toman el código y el nombre de Soy');
select is((select string_agg(code || ' ' || name || ':' || kind, ', ' order by code) from recipes.recipe_categories
            where id in (pg_temp.u(60401), pg_temp.u(60402), pg_temp.u(60403), pg_temp.u(60404))),
  'PL-CAR Principales de carne:menu, PL-PAS Pastas:menu, PL-PES Principales de pescado:menu, PL-POS Postres:menu',
  'staging, recetas: CARNES (con un plato), PASTAS, PESCADOS y POSTRES, en menú con el código y el nombre de Soy');
select is((select count(*)::int from catalog.ingredient_categories where group_id = pg_temp.u(60002) and parent_id is null)
          || ' ' || (select count(*)::int from recipes.recipe_categories where group_id = pg_temp.u(60002) and parent_id is null),
  '20 26', 'staging: quedan exactamente los 46 rubros de Soy, sin duplicados');
alter table catalog.ingredient_categories enable trigger enforce_rubro_fields;
alter table recipes.recipe_categories enable trigger enforce_rubro_fields;
alter table recipes.recipes enable trigger enforce_recipe_category_class;
create function pg_temp.code(p_id int) returns text language sql as $$
  select coalesce((select code from catalog.ingredient_categories where id = pg_temp.u(p_id)),
                  (select code from recipes.recipe_categories where id = pg_temp.u(p_id)))
$$;
select is(pg_temp.code(60101) || ' ' || pg_temp.code(60102) || ' ' || pg_temp.code(60103) || ' ' || pg_temp.code(60104),
  'MP-CAR MP-LAC MP-VER MP-FRU',
  'por la primera palabra («Carnes» → Carnes y aves, «Verduras y frutas» → Verduras y hortalizas) o por el nombre');
select is(pg_temp.code(60106), 'MP-CON', 'por la equivalencia acordada («Almacén seco» → Conservas y enlatados)');
select is(pg_temp.code(60105), 'MP-ALM', 'lo que no se empareja lleva un código propio');
select is((select string_agg(name, ', ' order by name) from catalog.ingredient_categories
            where id in (pg_temp.u(60101), pg_temp.u(60103), pg_temp.u(60105), pg_temp.u(60106))),
  'Almacén, Carnes y aves, Conservas y enlatados, Verduras y hortalizas',
  'la emparejada toma el nombre de Soy; la que no se empareja conserva el suyo');
select ok(pg_temp.code(60107) ~ '^MP-PE[0-9]$' and pg_temp.code(60108) ~ '^MP-PE[0-9]$',
  'dos categorías viejas con la misma primera palabra no se adueñan del rubro de Soy: llevan código propio');
select is(pg_temp.code(60109), null, 'lo borrado queda como estaba (un registro borrado no se edita)');
select is((select code from catalog.ingredient_categories where id = pg_temp.u(60110)), null, 'una subcategoría no lleva código');
select is((select count(*)::int from catalog.ingredient_categories where group_id = pg_temp.u(60001) and parent_id is null and deleted_at is null),
  23, 'compra: los 20 de Soy (5 de ellos son las categorías viejas) y 3 propias, sin duplicados');
select is((select string_agg(name || ':' || kind, ', ' order by name) from recipes.recipe_categories where group_id = pg_temp.u(60001)
            and id in (pg_temp.u(60201), pg_temp.u(60202), pg_temp.u(60203), pg_temp.u(60204), pg_temp.u(60205))),
  'Guarniciones:menu, Masas:subrecipe, Platos fuertes:menu, Rellenas:menu, Salsas:subrecipe',
  'la clase sale de la mayoría de sus recetas; en empate o sin recetas, del nombre; la subcategoría hereda');
select is(pg_temp.code(60201) || ' ' || pg_temp.code(60203) || ' ' || pg_temp.code(60204), 'SR-SAL PL-GUA SR-MAS',
  'las de recetas con el mismo nombre que un rubro de su clase llevan su código');
select ok(pg_temp.code(60202) ~ '^PL-' and pg_temp.code(60202) not in (select code from recipes.default_categories()),
  '«Platos fuertes» lleva un código propio de menú');
select is((select count(*)::int from recipes.recipe_categories where group_id = pg_temp.u(60001) and parent_id is null),
  27, 'recetas: los 26 de Soy (3 de ellos son las categorías viejas) y 1 propia');
select ok(exists (select 1 from audit.audit_events where table_name = 'ingredient_categories' and record_id = pg_temp.u(60101)
                    and action = 'update' and reason = 'Prueba del mapeo de rubros' and source = 'maintenance'),
  'el mapeo queda en la auditoría como mantenimiento');
select is(recipes.map_legacy_categories(pg_temp.u(60001)), 0, 'correrlo otra vez no cambia nada');

-- ---------------------------------------------------------------------------
-- Rendimiento: los conteos del panel en menos de 300 ms
-- ---------------------------------------------------------------------------
create temporary table timing (ms numeric);
grant all on timing to authenticated;
do $$
declare
  t0 timestamptz;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000401', 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  t0 := clock_timestamp();
  perform * from recipes.category_overview('00000000-0000-4000-8000-000000000001');
  insert into timing values (extract(epoch from clock_timestamp() - t0) * 1000);
  reset role;
end
$$;
select ok((select ms from timing) < 300, 'los conteos del panel salen en menos de 300 ms');

select * from finish();
rollback;
