-- Fase 2 · Etapa 2.3, PR 1: quién ve los costos de una receta (ADR-0032). Cada rol, por local. El Chef ve costos
-- sin ver precios; Compras ve precios sin ver costos de recetas; la Cocinera y el Jefe de Cocina, nada.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(37);

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
-- Una receta del seed publicada en Demo Parrilla, y otra en Demo Pastas Centro.
create function pg_temp.ver(p_code text) returns uuid language sql as $$
  select v.id from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id
   where r.code = p_code and v.status = 'published'
$$;
grant execute on function pg_temp.ver(text), pg_temp.u(int) to authenticated;

-- Tablas: RLS activo y nada se escribe desde la API.
select is((select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where (n.nspname, c.relname) in (('costing', 'recipe_cost_current'), ('costing', 'recipe_cost_snapshots'),
                                             ('costing', 'recipe_cost_snapshot_lines'), ('costing', 'cost_recalc_queue'), ('recipes', 'component_base_quantities'))
              and c.relrowsecurity), 5::bigint, 'RLS activo en las cinco tablas');
select is((select count(*) from information_schema.role_table_grants
            where grantee in ('authenticated', 'anon') and privilege_type <> 'SELECT'
              and ((table_schema = 'costing' and (table_name like 'recipe_cost%' or table_name = 'cost_recalc_queue')) or table_name = 'component_base_quantities')),
  0::bigint, 'nadie escribe por la API');
select ok(not has_table_privilege('anon', 'costing.recipe_cost_current', 'select'), 'anon no lee el costo vigente');
select ok(not has_table_privilege('authenticated', 'recipes.component_base_quantities', 'select'), 'las cantidades congeladas solo las lee el motor');
select ok(not has_table_privilege('authenticated', 'costing.cost_recalc_queue', 'select'), 'la cola no se expone');

-- Las funciones internas no se llaman desde afuera.
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'costing'
              and p.proname in ('recipe_totals_internal', 'recipe_line_costs_internal', 'refresh_recipes',
                                'recipes_above', 'recipes_below', 'restaurant_recipes', 'recipes_using_ingredient', 'enqueue_restaurant', 'enqueue_recalc',
                                'process_recalc_queue', 'fit',
                                'store_recipe_cost', 'totals_of_lines',
                                'purchase_quantity', 'require_recipe_cost')
              and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
  0::bigint, 'el motor interno no se expone');

-- Quién ve qué, por local. 402 Dirección, 404 Gerente de Pastas Centro, 405 Chef de Demo Pastas, 406 Jefe de
-- Cocina, 407 Controller, 408 Compras, 409 Cocinera.
select cmp_ok(pg_temp.q(pg_temp.u(402), 'select count(distinct restaurant_id)::text from costing.recipe_cost_current')::int, '=', 4,
  'Dirección ve los cuatro locales');
select cmp_ok(pg_temp.q(pg_temp.u(401), 'select count(distinct restaurant_id)::text from costing.recipe_cost_current')::int, '=', 4, 'el Superadministrador también');
select cmp_ok(pg_temp.q(pg_temp.u(410), 'select count(distinct restaurant_id)::text from costing.recipe_cost_current')::int, '>', 0, 'el Auditor ve costos');
select is(pg_temp.q(pg_temp.u(403), 'select count(*)::text from costing.recipe_cost_current c join org.restaurants r on r.id = c.restaurant_id where r.brand_id <> ''00000000-0000-4000-8000-000000000101'''),
  '0', 'la Directora ve solo los locales de su marca');
select is(pg_temp.q(pg_temp.u(404), 'select string_agg(distinct restaurant_id::text, '','') from costing.recipe_cost_current'),
  pg_temp.u(201)::text, 'el Gerente ve solo su local');
select is(pg_temp.q(pg_temp.u(405), 'select count(*)::text from costing.recipe_cost_current c join org.restaurants r on r.id = c.restaurant_id where r.brand_id <> ''00000000-0000-4000-8000-000000000101'''),
  '0', 'el Chef de la marca ve solo sus locales');
select cmp_ok(pg_temp.q(pg_temp.u(405), 'select count(*)::text from costing.recipe_cost_current')::int, '>', 0, 'y los ve');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from costing.recipe_cost_current'), '0',
  'Compras ve precios, pero no costos de recetas');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.recipe_cost_current'), '0', 'la Cocinera no ve costos');
select is(pg_temp.q(pg_temp.u(406), 'select count(*)::text from costing.recipe_cost_current'), '0', 'el Jefe de Cocina tampoco');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.recipe_cost_snapshots'), '0', 'ni sus fotos');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.recipe_cost_snapshot_lines'), '0', 'ni su detalle');

-- La función de la pantalla, también para un borrador.
select ok(pg_temp.q(pg_temp.u(405), format('select reliability::text from costing.recipe_cost(%L, %L)', pg_temp.ver('DEMO-PAS-04'), pg_temp.u(201)))
            not like 'ERROR%', 'el Chef ve el costo de una receta de su marca');
select ok(pg_temp.q(pg_temp.u(405), format('select count(*)::text from costing.recipe_cost_lines(%L, %L)', pg_temp.ver('DEMO-PAS-04'), pg_temp.u(201)))
            not like 'ERROR%', 'y el costo por línea');
select ok(pg_temp.q(pg_temp.u(405), format('select reliability::text from costing.recipe_cost(%L, %L)', pg_temp.ver('DEMO-PAS-04'), pg_temp.u(203)))
            like 'ERROR%No tenés permiso%', 'pero no en un local de otra marca');
select ok(pg_temp.q(pg_temp.u(408), format('select reliability::text from costing.recipe_cost(%L, %L)', pg_temp.ver('DEMO-PAS-04'), pg_temp.u(201)))
            like 'ERROR%No tenés permiso%', 'Compras no pide el costo de una receta');
select ok(pg_temp.q(pg_temp.u(409), format('select count(*)::text from costing.recipe_cost_lines(%L, %L)', pg_temp.ver('DEMO-PAS-04'), pg_temp.u(201)))
            like 'ERROR%No tenés permiso%', 'la Cocinera tampoco');

-- Un borrador: lo ve quien trabaja la receta, y nadie más.
create temporary table draft (id uuid);
insert into draft select (pg_temp.q(pg_temp.u(405), format('select recipes.new_version(%L, ''Prueba'') ->> ''id''',
                                                           (select id from recipes.recipes where code = 'DEMO-PAS-04'))))::uuid;
grant select on draft to authenticated;
select ok(pg_temp.q(pg_temp.u(405), format('select total_gross_cost::text from costing.recipe_cost(%L, %L)', (select id from draft), pg_temp.u(201))) = '1768.3333',
  'el Chef ve cuánto costaría su borrador');
select is(pg_temp.q(pg_temp.u(405), format('select string_agg(share_pct::text, ''/'' order by line_order) from costing.recipe_cost_lines(%L, %L)', (select id from draft), pg_temp.u(201))),
  '31.10/15.55/49.95/3.39', 'con la participación de cada línea');
select ok(pg_temp.q(pg_temp.u(404), format('select total_cost::text from costing.recipe_cost(%L, %L)', (select id from draft), pg_temp.u(201)))
            like 'ERROR%No tenés permiso%', 'el Gerente, que no la trabaja, no ve el borrador');

-- El local tiene que estar al alcance de la receta.
select ok(pg_temp.q(pg_temp.u(402), format('select total_cost::text from costing.recipe_cost(%L, %L)', pg_temp.ver('DEMO-PAR-02'), pg_temp.u(201)))
            like 'ERROR%No tenés permiso%', 'una receta de una marca no se cuesta en un local de otra');

-- Las fotos muestran la fórmula solo de lo que la persona ve.
insert into costing.recipe_cost_snapshots (id, group_id, restaurant_id, recipe_id, recipe_version_id, as_of, reason, reliability)
select pg_temp.u(99901), v.group_id, pg_temp.u(201), v.recipe_id, (select id from draft), current_date, 'publish', 'incomplete'
  from recipes.recipe_versions v where v.id = (select id from draft);
insert into costing.recipe_cost_snapshot_lines (group_id, restaurant_id, snapshot_id, recipe_version_id, line_order, item, quantity, unit_id,
                                                quantity_basis, line_status)
select pg_temp.u(1), pg_temp.u(201), pg_temp.u(99901), (select id from draft), 1, 'Línea de otra versión', 1, id, 'purchase', 'ok'
  from catalog.units where code = 'g';
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.recipe_cost_snapshot_lines where snapshot_id = %L', pg_temp.u(99901))), '0',
  'el Gerente no lee las líneas de una versión que no ve');
select is(pg_temp.q(pg_temp.u(405), format('select count(*)::text from costing.recipe_cost_snapshot_lines where snapshot_id = %L', pg_temp.u(99901))), '1',
  'el Chef, que la trabaja, sí');

-- El Chef ve costos sin ver precios (ADR-0032): ni en la función ni en la tabla.
select is((select count(*) from pg_proc p, unnest(p.proargnames) a
            where p.oid = 'costing.recipe_cost_lines(uuid, uuid)'::regprocedure
              and a in ('price_record_id', 'unit_cost', 'gross_unit_cost', 'package_base_quantity', 'price_level', 'vat_condition',
                        'purchase_product_id', 'product_description', 'supplier_id', 'document_type')),
  0::bigint, 'el detalle no devuelve precio, producto, proveedor ni comprobante');
select ok(pg_temp.q(pg_temp.u(405), 'select price_record_id::text from costing.recipe_cost_snapshot_lines limit 1') like 'ERROR%permission denied%',
  'el Chef no lee de qué precio salió una línea');
select ok(pg_temp.q(pg_temp.u(405), 'select unit_cost::text from costing.recipe_cost_snapshot_lines limit 1') like 'ERROR%permission denied%',
  'ni el costo por unidad');
select ok(pg_temp.q(pg_temp.u(405), 'select package_base_quantity::text from costing.recipe_cost_snapshot_lines limit 1') like 'ERROR%permission denied%',
  'ni el contenido del envase');
select ok(pg_temp.q(pg_temp.u(405), 'select count(line_cost)::text from costing.recipe_cost_snapshot_lines') not like 'ERROR%',
  'el costo de la línea sí');
select ok(pg_temp.q(pg_temp.u(405), format('select line_cost::text from costing.ingredient_line_cost(%L, %L, 100, (select id from catalog.units where code = ''g''))',
                                           pg_temp.u(801), pg_temp.u(201))) like 'ERROR%No tenés permiso%',
  'la línea suelta sigue pidiendo ver precios');

-- Nadie escribe.
select ok(pg_temp.q(pg_temp.u(402), format('update costing.recipe_cost_current set total_cost = 1 where restaurant_id = %L returning 1', pg_temp.u(201)))
            like 'ERROR%permission denied%', 'ni Dirección cambia un costo a mano');

-- La vista de cocina sigue sin valores económicos (caso 24, con costos reales).
select ok(pg_temp.q(pg_temp.u(409), format('select recipes.kitchen_card(%L)::text', (select id from recipes.recipes where code = 'DEMO-SAL-02'))) !~* '(total_cost|line_cost|unit_cost|price)',
  'la vista de cocina no trae costos ni precios');

select * from finish();
rollback;
