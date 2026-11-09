-- Fase 2 · Etapa 2.1 A: catálogo de materias primas y permisos del recetario (ADR-0020).
-- Estructura, matriz de permisos, RLS por rol y por grupo, escrituras solo por funciones,
-- auditoría, unidades sin adivinar (casos 16 y 17 del documento de Soy) y buscador.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(104);

create function pg_temp.q(p_user uuid, p_sql text, p_aal text default 'aal2')
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, true);
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
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.ing(p_n int) returns uuid language sql as $$ select pg_temp.u(800 + p_n) $$;
-- El mensaje de error que ve la persona.
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
-- Funciones internas (que la app no puede llamar): con la sesión de la persona, sin cambiar de rol.
create function pg_temp.internal(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  execute p_sql into v;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.unit(p_code text) returns uuid language sql as $$
  select id from catalog.units where code = p_code
$$;
-- Se usan dentro de las consultas que corren como authenticated.
grant execute on function pg_temp.u(int), pg_temp.ing(int), pg_temp.unit(text) to authenticated;
create function pg_temp.perms(p_role text) returns text[] language sql as $$
  select coalesce(array_agg(p.code order by p.code), '{}')
    from core.role_permissions rp
    join core.roles r on r.id = rp.role_id and r.code = p_role
    join core.permissions p on p.id = rp.permission_id
   where rp.deleted_at is null
     and p.module in ('catalog', 'prices', 'yields', 'recipes', 'scenarios', 'imports', 'reports')
$$;
create function pg_temp.sorted(p text[]) returns text[] language sql as $$
  select array_agg(c order by c) from unnest(p) as c
$$;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select is(
  (select array_agg(c.relname::text order by c.relname::text) from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relkind = 'r'),
  array['allergens', 'ingredient_aliases', 'ingredient_allergens', 'ingredient_categories', 'ingredient_unit_conversions',
        'ingredient_yield_profiles', 'ingredient_yield_tests', 'ingredients', 'purchase_products', 'suppliers',
        'unit_conversions', 'units', 'yield_processes'],
  'el catálogo tiene sus 13 tablas (10 de 2.1 A y 3 de rendimientos, 2.1 B)');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS activado en todas las tablas del catálogo');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relkind = 'r' and obj_description(c.oid, 'pg_class') is null),
  0, 'todas las tablas del catálogo tienen comentario');
select is(
  (select count(*)::int from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
      and col_description(c.oid, a.attnum) is null),
  0, 'todas las columnas del catálogo tienen comentario');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relkind = 'r'
      and (select count(*) from pg_trigger t where t.tgrelid = c.oid
            and t.tgname in ('log_change', 'reject_truncate')) <> 2),
  0, 'todas las tablas del catálogo tienen auditoría y rechazo de truncate');
-- Columnas de control en todas, salvo los ensayos de rendimiento, que son solo inserción (150_yields).
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'catalog' and c.relkind = 'r' and c.relname <> 'ingredient_yield_tests'
      and not exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname = 'set_control_columns')),
  0, 'todas las tablas modificables del catálogo tienen columnas de control');
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'catalog' and grantee in ('anon', 'authenticated', 'service_role')
      and privilege_type <> 'SELECT'),
  0, 'nadie escribe directo en el catálogo: solo se lee (ni insert, ni update, ni delete)');
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'catalog' and grantee = 'anon'),
  0, 'anon no ve nada del catálogo');
select is((select count(*)::int from catalog.units), 14, 'hay 14 unidades');
select is(
  (select array_agg(code order by code) from catalog.units where is_base), array['g', 'ml', 'unit'],
  'las unidades base son g, ml y unidad');
select is((select site_type::text from org.restaurants where id = pg_temp.u(201)), 'restaurant',
  'un local es restaurante por defecto');

-- ---------------------------------------------------------------------------
-- Matriz de permisos del recetario (sección 17 y decisión de Joaco del 2026-10-28)
-- ---------------------------------------------------------------------------
select is((select count(*)::int from core.permissions
            where module in ('catalog', 'prices', 'yields', 'recipes', 'scenarios', 'imports', 'reports')), 21,
  'hay 21 permisos del recetario (prices.configure llegó con la 2.1 C, ADR-0029; yields.alerts, con el aviso de rendimiento, ADR-0035)');
select is(pg_temp.perms('superadmin'), pg_temp.sorted(array['catalog.view', 'catalog.manage', 'prices.view', 'prices.propose',
  'imports.run', 'recipes.view', 'recipes.view_costs', 'recipes.draft', 'recipes.review', 'yields.record', 'reports.export']),
  'Superadministrador: los de quienes puede suspender (Gerente, Jefe de Cocina, Cocinero, Compras y Auditor)');
select is(pg_temp.perms('general_management'), pg_temp.sorted(array['catalog.view', 'prices.view', 'prices.approve', 'prices.configure',
  'recipes.view', 'recipes.view_costs', 'recipes.approve', 'recipes.publish', 'recipes.archive', 'recipes.assign',
  'scenarios.manage', 'imports.approve', 'reports.export', 'yields.alerts']), 'Dirección General: ver con costos, aprobar, exportar y configurar los precios');
select is(pg_temp.perms('brand_director'), pg_temp.sorted(array['catalog.view', 'prices.view', 'recipes.view',
  'recipes.view_costs', 'recipes.draft', 'recipes.review', 'recipes.approve', 'recipes.publish', 'recipes.archive',
  'recipes.assign', 'yields.record', 'yields.approve', 'yields.alerts', 'scenarios.manage', 'imports.run', 'imports.approve',
  'reports.export']), 'Director de Marca: su marca, con lo del Chef y el Gerente');
select is(pg_temp.perms('restaurant_manager'), pg_temp.sorted(array['catalog.view', 'prices.view', 'recipes.view',
  'recipes.view_costs', 'recipes.draft', 'recipes.review', 'yields.record', 'reports.export']),
  'Gerente: su local y lo del Jefe de Cocina, con los costos y precios de su local (respuesta 7 de Soy, ADR-0024)');
select is(pg_temp.perms('executive_chef'), pg_temp.sorted(array['catalog.view', 'yields.record', 'yields.approve', 'yields.alerts',
  'recipes.view', 'recipes.view_costs', 'recipes.draft', 'recipes.review', 'recipes.approve', 'recipes.publish',
  'recipes.archive', 'recipes.assign', 'imports.run', 'imports.approve', 'reports.export']),
  'Chef Ejecutivo: recetas y rendimientos, nunca precios');
select is(pg_temp.perms('head_chef'), pg_temp.sorted(array['catalog.view', 'yields.record', 'recipes.view',
  'recipes.draft', 'recipes.review']), 'Jefe de Cocina: borradores, revisión y ensayos, sin costos');
select is(pg_temp.perms('controller'), pg_temp.sorted(array['catalog.view', 'prices.view', 'prices.approve',
  'recipes.view', 'recipes.view_costs', 'scenarios.manage', 'imports.approve', 'reports.export', 'yields.alerts']),
  'Controller: costos y aprobar precios, nunca gramajes');
select is(pg_temp.perms('purchasing'), pg_temp.sorted(array['catalog.view', 'catalog.manage', 'prices.view',
  'prices.propose', 'recipes.view', 'imports.run']), 'Compras: catálogo y proponer precios, nunca aprobarlos');
select is(pg_temp.perms('cook'), array['recipes.view'], 'Cocinero: solo la vista de cocina, sin precios ni costos');
select is(pg_temp.perms('auditor'), pg_temp.sorted(array['catalog.view', 'prices.view', 'recipes.view',
  'recipes.view_costs', 'reports.export']), 'Auditor: solo lectura');
select ok(not exists (select 1 from unnest(pg_temp.perms('auditor')) p where p ~ '\.(manage|propose|approve|draft|publish|assign|run|record)$'),
  'el Auditor no crea, no edita ni aprueba');
select ok(not ('prices.approve' = any (pg_temp.perms('purchasing'))) and not ('prices.approve' = any (pg_temp.perms('executive_chef'))),
  'ni Compras ni el Chef aprueban precios');
select ok(not ('recipes.draft' = any (pg_temp.perms('controller'))), 'el Controller no cambia gramajes ni procedimientos');

-- Quien administra personas tiene los permisos de los roles que administra (regla de la Fase 1).
select is(
  (select array_agg(format('%s→%s', a, b) order by a, b) from (values
      ('brand_director', 'executive_chef'), ('brand_director', 'head_chef'), ('brand_director', 'restaurant_manager'),
      ('brand_director', 'cook'), ('restaurant_manager', 'head_chef'), ('restaurant_manager', 'cook'),
      ('superadmin', 'restaurant_manager'), ('superadmin', 'head_chef'), ('superadmin', 'cook'),
      ('superadmin', 'purchasing'), ('superadmin', 'auditor')) as x (a, b)
    where not pg_temp.perms(b) <@ pg_temp.perms(a)),
  null, 'quien administra personas tiene los permisos del recetario de los roles que administra');

-- ---------------------------------------------------------------------------
-- Lectura por rol y por grupo
-- ---------------------------------------------------------------------------
-- Las del grupo de prueba: las 50 del seed más las que hayan creado las pruebas de Playwright
-- en esta base local (en CI, pgTAP corre antes, sobre una base recién creada).
create function pg_temp.own_count() returns text language sql as $$
  select count(*)::text from catalog.ingredients
   where group_id = '00000000-0000-4000-8000-000000000001' and deleted_at is null
$$;
select ok(pg_temp.own_count()::int >= 50, 'el seed carga al menos 50 materias primas');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from catalog.ingredients'), pg_temp.own_count(), 'Compras ve todas las materias primas de su grupo');
select is(pg_temp.q(pg_temp.u(406), 'select count(*)::text from catalog.ingredients'), pg_temp.own_count(),
  'el Jefe de Cocina de un local ve el catálogo de todo el grupo');
select is(pg_temp.q(pg_temp.u(405), 'select count(*)::text from catalog.purchase_products'), '60',
  'el Chef ve los productos de compra');
select is(pg_temp.q(pg_temp.u(410), 'select count(*)::text from catalog.suppliers'), '6', 'el Auditor ve los proveedores');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from catalog.ingredients'), '0',
  'el Cocinero no ve el catálogo (sus recetas llegan por la vista de cocina)');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from catalog.purchase_products'), '0',
  'el Cocinero no ve productos de compra');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from catalog.units'), '14', 'las unidades las ve cualquiera que opere');
select is(pg_temp.q(pg_temp.u(402), 'select count(*)::text from catalog.ingredients', 'aal1'), '0',
  'Dirección sin doble verificación no ve nada');
select is(pg_temp.q(null::uuid, 'select count(*)::text from catalog.ingredients'), '0', 'sin persona no se ve nada');

-- Otro grupo, con su propio catálogo: no se ve ni se toca.
do $$
begin
  perform core.set_change_context('Prueba: otro grupo', 'maintenance');
  insert into org.groups (id, name) values ('99999999-0000-4000-8000-000000000001', 'Otro grupo de prueba');
  insert into catalog.ingredient_categories (id, group_id, name)
  values ('99999999-0000-4000-8000-000000000701', '99999999-0000-4000-8000-000000000001', 'Otra categoría');
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values ('99999999-0000-4000-8000-000000000801', '99999999-0000-4000-8000-000000000001', 'OTRO-1', 'Ingrediente ajeno',
          '99999999-0000-4000-8000-000000000701', (select id from catalog.units where code = 'g'));
end
$$;
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from catalog.ingredients'), pg_temp.own_count(),
  'Compras no ve las materias primas de otro grupo');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.update_ingredient('99999999-0000-4000-8000-000000000801',
            '{"name": "Cambiado"}', 'Prueba')::text$$), 'ERROR 42501', 'ni las puede editar');

-- ---------------------------------------------------------------------------
-- Escritura: solo por funciones, con catalog.manage y motivo
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id)
            values (pg_temp.u(1), 'X-1', 'Directo', pg_temp.u(701), pg_temp.unit('g')) returning 'ok'$$),
  'ERROR 42501', 'nadie inserta directo, ni Compras');
select is(pg_temp.q(pg_temp.u(408), $$update catalog.ingredients set name = 'x' where id = pg_temp.ing(1) returning 'ok'$$),
  'ERROR 42501', 'nadie edita directo');
select is(pg_temp.q(pg_temp.u(408), $$delete from catalog.ingredients where id = pg_temp.ing(1) returning 'ok'$$),
  'ERROR 42501', 'nadie borra: no hay borrado');

select ok(pg_temp.q(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'demo-ing-900', 'Rúcula',
            pg_temp.u(701), 'g', '{"purchase_unit": "kg"}', 'Alta de prueba')::text$$) ~ '^[0-9a-f-]{36}$',
  'Compras crea una materia prima');
select is((select code || '|' || name from catalog.ingredients where code = 'DEMO-ING-900'), 'DEMO-ING-900|Rúcula',
  'el código queda en mayúsculas');
select is(
  (select format('%s|%s|%s|%s', e.action, (e.actor_user_id = pg_temp.u(408))::text, e.reason, e.new_values ->> 'name')
     from audit.audit_events e
    where e.table_schema = 'catalog' and e.table_name = 'ingredients'
      and e.record_id = (select id from catalog.ingredients where code = 'DEMO-ING-900')),
  'insert|true|Alta de prueba|Rúcula', 'la auditoría guarda quién, qué y por qué');
select is(
  (select module from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredients' limit 1),
  'catalog', 'el historial lo muestra en el módulo catálogo');

select is(pg_temp.q(pg_temp.u(405), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-901', 'Rúcula 2',
            pg_temp.u(701), 'g', null, 'Prueba')::text$$), 'ERROR 42501', 'el Chef no edita el catálogo');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-901', 'Rúcula 2',
            pg_temp.u(701), 'g', null, 'Prueba')::text$$), 'ERROR 42501', 'el Jefe de Cocina tampoco');
select is(pg_temp.q(pg_temp.u(410), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-901', 'Rúcula 2',
            pg_temp.u(701), 'g', null, 'Prueba')::text$$), 'ERROR 42501', 'el Auditor tampoco');
select is(pg_temp.q(pg_temp.u(402), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-901', 'Rúcula 2',
            pg_temp.u(701), 'g', null, 'Prueba')::text$$), 'ERROR 42501', 'Dirección tampoco');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-901', 'Rúcula 2',
            pg_temp.u(701), 'g', null, '  ')::text$$), 'ERROR 22023', 'sin motivo no se crea');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-001', 'Otro tomate',
            pg_temp.u(701), 'g', null, 'Prueba')::text$$), 'ERROR 23505', 'un código repetido se rechaza');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-001', 'Otro tomate',
            pg_temp.u(701), 'g', null, 'Prueba')$$),
  'Ya existe una materia prima con ese código en el grupo.', 'y el mensaje sale en español, sin nombres técnicos');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_supplier(pg_temp.u(1), 'x', 'Proveedor nuevo', null, 'Prueba')$$),
  'El código va en mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).',
  'un código fuera de formato explica cómo va');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-902', 'TOMATE PERITA',
            pg_temp.u(701), 'g', null, 'Prueba')::text$$), 'ERROR 23505', 'un nombre repetido (sin importar mayúsculas) se rechaza');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-903', 'Harina integral',
            pg_temp.u(705), 'kg', null, 'Prueba')::text$$), 'ERROR 23514', 'la unidad de uso en recetas es siempre g, ml o unidad');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.update_ingredient(pg_temp.ing(1), '{"code": "OTRO"}', 'Prueba')::text$$),
  'ERROR 22023', 'el código de una materia prima no cambia');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_ingredient_active(pg_temp.ing(50), false, 'Ya no se compra')::text$$),
  '', 'Compras desactiva una materia prima');
select is((select is_active::text || '|' || (deleted_at is null)::text from catalog.ingredients where id = pg_temp.ing(50)),
  'false|true', 'desactivar no la borra');

-- Alias
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_aliases(pg_temp.ing(19), array['Muzza', 'muzzarella', 'muzza'], 'Alias')::text$$),
  '', 'se reemplazan los alias (en minúsculas y sin repetir)');
select is((select array_agg(alias order by alias) from catalog.ingredient_aliases where ingredient_id = pg_temp.ing(19) and deleted_at is null),
  array['muzza', 'muzzarella'], 'quedan los nuevos; "mozza" se borró lógicamente');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_aliases(pg_temp.ing(20), array['muzza'], 'Alias')::text$$),
  'ERROR 23505', 'un alias no puede ser de dos materias primas');

-- Conversiones propias: con fuente y fecha
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_unit_conversion(pg_temp.ing(34), 'density', 0.92, null, null, null, 'Prueba')::text$$),
  'ERROR 22023', 'una densidad sin fuente ni fecha se rechaza: nunca se supone');

-- Productos de compra
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_purchase_product(pg_temp.ing(34), 'DEMO-PROD-900', 'Girasol por kg',
            'kg', 1, 1, 'kg', null, 'Prueba')::text$$),
  'ERROR 23514', 'un producto en kg de algo que se usa en ml, sin densidad, se rechaza');
select ok(pg_temp.q(pg_temp.u(408), $$select catalog.create_purchase_product(pg_temp.ing(33), 'DEMO-PROD-901', 'Oliva por kg',
            'kg', 1, 1, 'kg', null, 'Prueba')::text$$) ~ '^[0-9a-f-]{36}$',
  'con la densidad cargada, sí (aceite de oliva por kg)');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_purchase_product(pg_temp.ing(1), 'DEMO-PROD-902', 'Tomate',
            'box', 1, 1, 'box', null, 'Prueba')::text$$),
  'ERROR 23514', 'el contenido nunca es un envase: una caja no dice cuánto trae');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.update_purchase_product((select id from catalog.purchase_products where code = 'DEMO-PROD-001'),
            '{"ingredient_id": "00000000-0000-4000-8000-000000000802"}', 'Prueba')::text$$),
  'ERROR 22023', 'un producto no cambia de ingrediente');

-- Alérgenos: sin fila = sin dato
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_allergen_status(pg_temp.ing(1), pg_temp.u(951), null, null, 'Prueba')::text$$),
  '', 'se vuelve a "sin dato"');
select is((select count(*)::int from catalog.ingredient_allergens where ingredient_id = pg_temp.ing(1) and deleted_at is null), 0,
  'y la fila queda borrada lógicamente, no física');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_allergen_status(pg_temp.ing(1), pg_temp.u(951), 'contains', null, 'Prueba')::text$$),
  'ERROR 22023', 'un estado de alérgeno necesita su fuente');

-- Los productos vigentes se tienen que poder seguir costeando (revisión de base, M2).
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.set_unit_conversion(pg_temp.ing(9), 'unit_weight', null, null, null, null, 'Prueba')$$),
  'No se puede quitar esta conversión: el producto «Limón, por kg» se compra en otra unidad y necesita su peso por unidad.',
  'no se quita el peso por unidad del limón mientras se compre por kg');
-- Con una materia prima sin precios: con precios, la unidad de uso no cambia nunca (2.1 C, ADR-0029; prueba 211).
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_ingredient(pg_temp.ing(29), '{"recipe_unit": "ml"}', 'Prueba')$$),
  'No se puede cambiar la unidad de uso: el producto «Sémola, bolsa de 5 kg» se compra en otra unidad y necesita su densidad.',
  'no se cambia la sémola a ml: sus productos están en g y no tiene densidad');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.update_purchase_product((select id from catalog.purchase_products where code = 'DEMO-PROD-009'),
            '{"is_active": false}', 'Ya no se compra')::text$$),
  '', 'desactivar un producto nunca se frena');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_unit_conversion(pg_temp.ing(9), 'unit_weight', null, null, null, null, 'Prueba')::text$$),
  '', 'con el producto desactivado, el peso por unidad se puede quitar');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.update_purchase_product((select id from catalog.purchase_products where code = 'DEMO-PROD-009'),
            '{"is_active": true}', 'Se vuelve a comprar')$$),
  'El ingrediente se usa en otra unidad: primero cargá su peso por unidad.',
  'reactivar un producto que ya no se puede costear se frena');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from catalog.search_components('%%%')$$), '0',
  'el buscador toma % como letra, no como comodín');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from catalog.search_components('a_a')$$), '0',
  'y _ también');

-- Nada nuevo apunta a algo borrado; los borrados no se ofrecen ni se convierten.
do $$
begin
  perform core.set_change_context('Prueba: borrados', 'maintenance');
  update catalog.ingredient_categories set deleted_at = now() where id = pg_temp.u(708);
  update catalog.suppliers set deleted_at = now() where id = pg_temp.u(906);
  update catalog.ingredients set deleted_at = now() where id = pg_temp.ing(48);
  update catalog.ingredient_aliases set deleted_at = now() where alias = 'calabaza';
end
$$;
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'DEMO-ING-910', 'Cúrcuma',
            pg_temp.u(708), 'g', null, 'Prueba')$$),
  'Esa categoría está borrada: elegí otra.', 'no se usa una categoría borrada');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_purchase_product(pg_temp.ing(21), 'DEMO-PROD-910', 'Ricota, balde',
            'pack', 1, 5000, 'g', format('{"supplier_id": "%s"}', pg_temp.u(906))::jsonb, 'Prueba')$$),
  'Ese proveedor está borrado: elegí otro.', 'ni un proveedor borrado');
select throws_ok($$insert into catalog.ingredient_categories (group_id, parent_id, name)
                   values (pg_temp.u(1), pg_temp.u(708), 'Pimientas')$$,
  '23514', 'La categoría madre está borrada: elegí otra.', 'ni una categoría madre borrada');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.update_purchase_product(
            (select id from catalog.purchase_products where supplier_id = pg_temp.u(906) limit 1),
            '{"notes": "Sigue en el depósito"}', 'Prueba')::text$$),
  '', 'editar un producto cuyo proveedor se borró no se frena (no cambia el proveedor)');
select is((select status from catalog.convert_quantity(pg_temp.ing(48), 1, pg_temp.unit('kg'), pg_temp.unit('g'))),
  'unknown_ingredient', 'para el motor, un ingrediente borrado no existe (aunque no pase por RLS)');
select is((select count(*)::int from catalog.search_components('aceitu') where code = 'DEMO-ING-048'), 0,
  'el buscador no ofrece un ingrediente borrado (aunque no pase por RLS)');
select is((select count(*)::int from catalog.search_components('calabaza')), 0,
  'ni encuentra por un alias borrado');

-- Una conversión universal entre dimensiones no existe.
select throws_ok($$insert into catalog.unit_conversions (from_unit_id, to_unit_id, factor)
                   values (pg_temp.unit('l'), pg_temp.unit('g'), 1000)$$,
  '23514', null, 'nunca se carga que 1 litro pesa 1 kilo');

-- ---------------------------------------------------------------------------
-- Unidades: convertir sin adivinar
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$select quantity::numeric(18,4)::text || '|' || status
            from catalog.convert_quantity(pg_temp.ing(1), 120, pg_temp.unit('g'), pg_temp.unit('kg'))$$),
  '0.1200|ok', 'caso 1: 120 g son 0,12 kg');
select is(pg_temp.q(pg_temp.u(408), $$select quantity::numeric(18,4)::text || '|' || status
            from catalog.convert_quantity(pg_temp.ing(33), 100, pg_temp.unit('ml'), pg_temp.unit('g'))$$),
  '92.0000|ok', 'caso 16: 100 ml de aceite con densidad 0,92 son 92 g');
select is(pg_temp.q(pg_temp.u(408), $$select coalesce(quantity::text, 'vacío') || '|' || status
            from catalog.convert_quantity(pg_temp.ing(34), 100, pg_temp.unit('ml'), pg_temp.unit('g'))$$),
  'vacío|missing_conversion', 'caso 17: sin densidad, conversión faltante y nunca 0');
select is(pg_temp.q(pg_temp.u(408), $$select quantity::numeric(18,4)::text || '|' || status
            from catalog.convert_quantity(pg_temp.ing(18), 3, pg_temp.unit('unit'), pg_temp.unit('kg'))$$),
  '0.3300|ok', '3 chorizos de 110 g son 0,33 kg (peso por unidad)');
select is(pg_temp.q(pg_temp.u(408), $$select base_quantity::numeric(18,4)::text || '|' || base_unit || '|' || status
            from catalog.to_base_quantity(pg_temp.ing(26), 2, pg_temp.unit('dozen'))$$),
  '24.0000|unit|ok', '2 docenas de huevos son 24 unidades');
select is(pg_temp.q(pg_temp.u(408), $$select coalesce(base_quantity::text, 'vacío') || '|' || status
            from catalog.to_base_quantity(pg_temp.ing(1), 1, pg_temp.unit('box'))$$),
  'vacío|missing_conversion', 'una caja no se convierte: no tiene contenido fijo');
select is(pg_temp.q(pg_temp.u(409), $$select status from catalog.convert_quantity(pg_temp.ing(1), 1, pg_temp.unit('kg'), pg_temp.unit('g'))$$),
  'unknown_ingredient', 'respeta RLS: para el Cocinero el ingrediente no existe');

-- ---------------------------------------------------------------------------
-- Buscador
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$select string_agg(code, ',') from catalog.search_components('muzz')$$),
  'DEMO-ING-019', 'busca por alias ("muzz" encuentra la mozzarella)');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from catalog.search_components('to')$$), '0',
  'con menos de 3 letras no busca');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from catalog.search_components('champ')$$), '0',
  'no ofrece materias primas desactivadas');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from catalog.search_components('tomate')$$), '0',
  'el Cocinero no encuentra nada');

-- ---------------------------------------------------------------------------
-- N1: el historial muestra costos con recipes.view_costs
-- ---------------------------------------------------------------------------
select is(pg_temp.internal(pg_temp.u(402), $$select core.can_see_costs(pg_temp.u(1), null, null)::text$$), 'true',
  'Dirección ve costos en el historial');
select is(pg_temp.internal(pg_temp.u(409), $$select core.can_see_costs(pg_temp.u(1), pg_temp.u(101), pg_temp.u(201))::text$$), 'false',
  'el Cocinero no ve costos en su local');
select is(pg_temp.internal(pg_temp.u(406), $$select core.can_see_costs(pg_temp.u(1), pg_temp.u(101), pg_temp.u(201))::text$$), 'false',
  'el Jefe de Cocina tampoco');
select is(pg_temp.internal(pg_temp.u(404), $$select core.can_see_costs(pg_temp.u(1), pg_temp.u(101), pg_temp.u(201))::text$$), 'true',
  'el Gerente sí, en su local (respuesta 7 de Soy, ADR-0024)');
-- El historial de verdad (no solo la función): un precio del seed.
create temporary table seed_price as
  select id, package_price from costing.price_records where scope_type = 'group' and group_id = pg_temp.u(1) order by id limit 1;
grant select on seed_price to authenticated;
select is(pg_temp.q(pg_temp.u(410), format($$select new_values ->> 'package_price' from core.audit_history(p_limit => 50, p_record_id => %L)
            where table_name = 'price_records' and action = 'insert'$$, (select id from seed_price)))::numeric,
  (select package_price from seed_price), 'el Auditor ve el precio en el historial (recipes.view_costs)');
do $$
begin
  perform core.set_change_context('Prueba: sin permiso de costos', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = 'auditor')
     and permission_id = (select id from core.permissions where code = 'recipes.view_costs');
end
$$;
select is(pg_temp.q(pg_temp.u(410), format($$select new_values ->> 'package_price' from core.audit_history(p_limit => 50, p_record_id => %L)
            where table_name = 'price_records' and action = 'insert'$$, (select id from seed_price))),
  '[oculto]', 'sin recipes.view_costs, el historial lo muestra oculto');

-- ---------------------------------------------------------------------------
-- Tipo de establecimiento
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(404), $$select org.update_restaurant(pg_temp.u(201), '{"site_type": "central_kitchen"}', 'Prueba')::text$$),
  'ERROR 42501', 'el Gerente no cambia el tipo de su local');
select is(pg_temp.q(pg_temp.u(403), $$select org.update_restaurant(pg_temp.u(202), '{"site_type": "production_unit"}', 'Prueba')::text$$),
  '', 'la Directora de Marca sí');
select is((select site_type::text from org.restaurants where id = pg_temp.u(202)), 'production_unit', 'y queda guardado');

select * from finish();
rollback;
