-- Fase 2 · Etapa 2.3, PR 3B: escalado (ADR-0032). Caso 14: 25 / 10 = 2,5 con la versión intacta. Líneas "no escalar",
-- más tandas, costo proyectado y permisos.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(48);

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

create function pg_temp.scale(p_user int, p_n int, p_target numeric, p_mode text, p_unit text default null) returns jsonb language plpgsql as $$
declare
  v text;
begin
  v := pg_temp.q(pg_temp.u(p_user), format('select recipes.scale_version(%L, %s, %L, %L)::text', pg_temp.u(98000 + p_n), p_target, p_mode, p_unit));
  if v like 'ERROR %' then
    return to_jsonb(v);
  end if;
  return v::jsonb;
end
$$;

-- Una receta de 10 porciones y 2 kg, con una línea "no escalar", en un horno de 3 kg.
select pg_temp.ing(1);
select pg_temp.price(1, 1000);
select pg_temp.ing(2);
select pg_temp.price(2, 2000);
select pg_temp.recipe(1, 'dish', 2, 'kg', 10);
select pg_temp.line(1, 1, 1, 1000, 'g');
select pg_temp.line(1, 2, 2, 100, 'g');
update recipes.recipe_components set no_scale = true where recipe_version_id = pg_temp.u(98001) and line_order = 2;
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, equipment, equipment_capacity, equipment_capacity_unit_id)
values (pg_temp.u(1), pg_temp.u(98001), 1, 'preparation', 'Hornear', 'Horno', 3, (select id from catalog.units where code = 'kg')),
       (pg_temp.u(1), pg_temp.u(98001), 2, 'preparation', 'Batir', 'Batidora', null, null),
       (pg_temp.u(1), pg_temp.u(98001), 3, 'preparation', 'Servir', null, null, null);
select pg_temp.publish(1);
select pg_temp.assign(1, 201);
create temporary table before_scale as select to_jsonb(v) as version from recipes.recipe_versions v where v.id = pg_temp.u(98001);

-- Caso 14: de 10 a 25 porciones.
select is(pg_temp.scale(413, 1, 25, 'portions') ->> 'factor', '2.500000', 'caso 14: 25 / 10 = 2,5');
select is(pg_temp.scale(413, 1, 25, 'portions') -> 'lines' -> 0 ->> 'scaled', '2500.000000', 'la cantidad se multiplica por el factor');
select is(pg_temp.scale(413, 1, 25, 'portions') -> 'lines' -> 1 ->> 'scaled', '100.000000', 'una línea "no escalar" queda igual');
select is(pg_temp.scale(413, 1, 25, 'portions') ->> 'target_yield', '5.000000', 'el rendimiento también escala');
select is((select to_jsonb(v) from recipes.recipe_versions v where v.id = pg_temp.u(98001)), (select version from before_scale), 'caso 14: la versión queda intacta');

-- Por rendimiento, con otra unidad de la misma dimensión.
select is(pg_temp.scale(413, 1, 4000, 'yield', 'g') ->> 'factor', '2.000000', '4.000 g de una receta de 2 kg: factor 2');
select is(pg_temp.scale(413, 1, 4, 'yield', 'kg') ->> 'factor', '2.000000', 'lo mismo en kg');
select ok(pg_temp.scale(413, 1, 4, 'yield', 'l') #>> '{}' like 'ERROR %unidad como la del rendimiento%', 'otra dimensión se rechaza');

-- Más tandas.
select is(pg_temp.scale(413, 1, 25, 'portions') -> 'steps' -> 0 ->> 'batches', '2', '5 kg en un horno de 3 kg: 2 tandas');
select is(pg_temp.scale(413, 1, 15, 'portions') -> 'steps' -> 0 ->> 'batches', '1', '3 kg justos: una tanda');
select is(pg_temp.scale(413, 1, 40, 'portions') -> 'steps' -> 0 ->> 'batches', '3', '8 kg: 3 tandas');
select is(pg_temp.scale(413, 1, 25, 'portions') -> 'steps' -> 1 ->> 'batches', null, 'sin capacidad, no hay aviso');
select is(jsonb_array_length(pg_temp.scale(413, 1, 25, 'portions') -> 'steps'), 2, 'los pasos sin equipo no aparecen');

-- Un lote que entra justo, con un factor periódico: 2 porciones de 3 son 1 kg de 1,5 kg, en un horno de 1 kg.
select pg_temp.recipe(4, 'dish', 1.5, 'kg', 3);
select pg_temp.line(4, 1, 1, 300, 'g');
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, equipment, equipment_capacity, equipment_capacity_unit_id)
values (pg_temp.u(1), pg_temp.u(98004), 1, 'preparation', 'Hornear', 'Horno', 1, (select id from catalog.units where code = 'kg'));
select pg_temp.publish(4);
select is(pg_temp.scale(413, 4, 2, 'portions') -> 'steps' -> 0 ->> 'batches', '1', 'un lote que entra justo es una sola tanda, aunque el factor sea periódico');
-- La capacidad tiene su unidad: en otra unidad de la misma dimensión da lo mismo.
select is(pg_temp.scale(413, 4, 6, 'portions') -> 'steps' -> 0 ->> 'capacity_unit', 'kg', 'la capacidad dice su unidad');
select pg_temp.recipe(8, 'dish', 2000, 'g', 10);
select pg_temp.line(8, 1, 1, 300, 'g');
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, equipment, equipment_capacity, equipment_capacity_unit_id)
values (pg_temp.u(1), pg_temp.u(98008), 1, 'preparation', 'Hornear', 'Horno', 3, (select id from catalog.units where code = 'kg'));
select pg_temp.publish(8);
select is(pg_temp.scale(413, 8, 25, 'portions') -> 'steps' -> 0 ->> 'batches', '2', 'rendimiento en g y capacidad en kg: 5.000 g en un horno de 3 kg, 2 tandas');

-- Lotes absurdos.
select ok(pg_temp.scale(413, 1, 0.000001, 'portions') #>> '{}' like 'ERROR %demasiado chico o demasiado grande%', 'un lote mínimo se explica');
select ok(pg_temp.scale(413, 1, 999999999, 'portions') #>> '{}' like 'ERROR %demasiado chico o demasiado grande%', 'uno enorme también');

-- Sin dato no se inventa un factor.
select pg_temp.recipe(2, 'dish', null, null, null);
select pg_temp.line(2, 1, 1, 100, 'g');
select pg_temp.publish(2);
select ok(pg_temp.scale(413, 2, 25, 'portions') #>> '{}' like 'ERROR %no tiene porciones%', 'sin porciones, no escala por porciones');
select ok(pg_temp.scale(413, 2, 4, 'yield', 'kg') #>> '{}' like 'ERROR %no tiene rendimiento%', 'sin rendimiento, tampoco por rendimiento');
select ok(pg_temp.scale(413, 1, 0, 'portions') #>> '{}' like 'ERROR %mayor que cero%', 'cero no');
select ok(pg_temp.scale(413, 1, -1, 'portions') #>> '{}' like 'ERROR %mayor que cero%', 'un negativo tampoco');
select ok(pg_temp.scale(413, 1, 5, 'otra') #>> '{}' like 'ERROR %Elegí si escalás%', 'un modo que no existe tampoco');

-- El costo proyectado: 1.000 g a 1 $/g por 2,5 + 100 g a 2 $/g una sola vez = $ 2.700.
create function pg_temp.scaled(p_user int, p_factor numeric) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select total_cost::numeric(18,2)::text from costing.scaled_cost(%L, %L, %s)', pg_temp.u(98001), pg_temp.u(201), p_factor))
$$;
select is(pg_temp.scaled(407, 2.5), '2700.00', 'el costo proyectado cuenta la línea "no escalar" una sola vez');
select is(pg_temp.scaled(413, 1), '1200.00', 'con factor 1, el costo de la receta');
select is(pg_temp.q(pg_temp.u(407), format('select reliability::text from costing.scaled_cost(%L, %L, 2)', pg_temp.u(98001), pg_temp.u(201))), 'estimated', 'con su confiabilidad');
-- Una preparación adentro: entra por su costo, por el factor.
select pg_temp.recipe(5, 'preparation', 1000, 'g', null);
select pg_temp.line(5, 1, 1, 1000, 'g');
select pg_temp.publish(5);
select pg_temp.recipe(6, 'dish', 1, 'unit', 2);
select pg_temp.sub(6, 1, 5, 100, 'g');
select pg_temp.publish(6);
select pg_temp.assign(6, 201);
select is(pg_temp.q(pg_temp.u(407), format('select total_cost::numeric(18,2)::text from costing.scaled_cost(%L, %L, 3)', pg_temp.u(98006), pg_temp.u(201))), '300.00', 'una preparación escala por su costo terminado');
select ok(pg_temp.q(pg_temp.u(404), format('select total_cost::text from costing.scaled_cost(%L, %L, 2)', pg_temp.u(98001), pg_temp.u(203))) like 'ERROR%No tenés permiso%', 'el Gerente no pide otro local');
select ok(pg_temp.scaled(409, 2.5) like 'ERROR%No tenés permiso%', 'la Cocinera no ve el costo proyectado');
select ok(pg_temp.scaled(408, 2.5) like 'ERROR%No tenés permiso%', 'Compras tampoco');
select ok(pg_temp.scaled(407, 0) like 'ERROR%mayor que cero%', 'un factor cero se rechaza');
-- Sin precio queda vacío, nunca $ 0.
select pg_temp.ing(3);
select pg_temp.recipe(3, 'dish', 1, 'kg', 1);
select pg_temp.line(3, 1, 3, 100, 'g');
select pg_temp.publish(3);
select pg_temp.assign(3, 201);
select is(pg_temp.q(pg_temp.u(407), format('select coalesce(total_cost::text, ''vacío'') from costing.scaled_cost(%L, %L, 2)', pg_temp.u(98003), pg_temp.u(201))), 'vacío', 'sin precio, vacío');

-- Permisos de la lectura: la Cocinera escala lo que ve, sin importes.
select ok(pg_temp.q(pg_temp.u(409), format('select recipes.scale_version(%L, 20, ''portions'')::text', pg_temp.u(98001))) !~* '(ERROR|cost|price|\$)', 'la Cocinera escala lo de su local, sin importes');
select ok(pg_temp.q(pg_temp.u(409), format('select recipes.scale_version(%L, 25, ''portions'')::text', pg_temp.u(98002))) like 'ERROR%No tenés permiso%' , 'quien no ve la versión no la escala');

-- Un borrador lo escala quien trabaja la receta, y nadie más.
select pg_temp.recipe(7, 'dish', 1, 'kg', 4);
select pg_temp.line(7, 1, 1, 100, 'g');
select is((pg_temp.scale(413, 7, 8, 'portions') ->> 'factor'), '2.000000', 'el Chef escala su borrador');
select ok(pg_temp.scale(409, 7, 8, 'portions') #>> '{}' like 'ERROR %No tenés permiso%', 'la Cocinera no');
select ok(not has_function_privilege('anon', 'recipes.scale_version(uuid, numeric, text, text)', 'execute')
           and not has_function_privilege('anon', 'costing.scaled_cost(uuid, uuid, numeric)', 'execute'), 'anon no las llama');

-- La capacidad se guarda y se copia.
select is(pg_temp.q(pg_temp.u(413), format('select recipes.new_version(%L, ''Prueba'') ->> ''result''', pg_temp.u(97001))), 'applied', 'una versión nueva');
select is((select equipment_capacity from recipes.recipe_steps s join recipes.recipe_versions v on v.id = s.recipe_version_id
            where v.recipe_id = pg_temp.u(97001) and v.status = 'draft' and s.step_number = 1), 3.000000, 'copia la capacidad');
select ok(pg_temp.q(pg_temp.u(413), format($f$select recipes.set_steps((select id from recipes.recipe_versions where recipe_id = %L and status = 'draft'),
            '[{"instructions": "Hornear", "equipment": "Horno", "equipment_capacity": "4,5"}]', 'Prueba')::text$f$, pg_temp.u(97001))) not like 'ERROR%', 'guardar los pasos acepta la capacidad');
select is((select equipment_capacity from recipes.recipe_steps s join recipes.recipe_versions v on v.id = s.recipe_version_id
            where v.recipe_id = pg_temp.u(97001) and v.status = 'draft' and s.step_number = 1 and s.deleted_at is null), 4.500000, 'con coma decimal');
select is((select u.code from recipes.recipe_steps s join recipes.recipe_versions v on v.id = s.recipe_version_id join catalog.units u on u.id = s.equipment_capacity_unit_id
            where v.recipe_id = pg_temp.u(97001) and v.status = 'draft' and s.step_number = 1 and s.deleted_at is null), 'kg', 'con la unidad del rendimiento');

-- Lo que no es una capacidad se explica.
create function pg_temp.steps(p_capacity text, p_equipment text default 'Horno') returns text language sql as $f$
  select pg_temp.q(pg_temp.u(413), format($s$select recipes.set_steps((select id from recipes.recipe_versions where recipe_id = %L and status = 'draft'),
           %L, 'Prueba')::text$s$, pg_temp.u(97001),
           json_build_array(json_build_object('instructions', 'Hornear', 'equipment', p_equipment, 'equipment_capacity', p_capacity))::text))
$f$;
select ok(pg_temp.steps('0') like 'ERROR%Paso 1: la capacidad del equipo%', 'cero se rechaza con un mensaje claro');
select ok(pg_temp.steps('-1') like 'ERROR%Paso 1: la capacidad del equipo%', 'un negativo también');
select ok(pg_temp.steps('NaN') like 'ERROR%Paso 1: la capacidad del equipo%', 'NaN también');
select ok(pg_temp.steps('abc') like 'ERROR%Paso 1: algún dato no es válido%', 'un texto también');
select ok(pg_temp.steps('3', '') like 'ERROR%escribí el equipo%', 'sin equipo no hay capacidad');
select ok(pg_temp.q(pg_temp.u(413), format($s$select recipes.set_steps((select id from recipes.recipe_versions where recipe_id = %L and status = 'draft'),
           '[{"instructions": "Hornear", "equipment": "Horno", "equipment_capacity": "3", "equipment_capacity_unit": "l"}]', 'Prueba')::text$s$, pg_temp.u(97001)))
            like 'ERROR%unidad como la del rendimiento%', 'la unidad de la capacidad es de la dimensión del rendimiento');

select * from finish();
rollback;
