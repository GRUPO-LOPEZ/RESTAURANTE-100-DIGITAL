-- Medidas, mermas y rendimientos (ADR-0040): unidades con nombre y abreviatura, catalog.create_unit, la marca «se compra
-- congelada» con su merma de descongelado en el motor de costos, catalog.propose_waste (mermas en %, con aprobación) y
-- la merma de cocción informativa. Y que el costo de lo que ya estaba cargado no cambia.
-- Personas: Compras (408) administra el catálogo; Chef de marca (405) propone; Chef del grupo (413) aprueba;
-- Controller (407) ve costos; Cocinero (409) y Auditor (410) no administran.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(68);

create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
    case when p_user is null then '{"role": "anon"}'
         else json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text end, true);
  execute case when p_user is null then 'set local role anon' else 'set local role authenticated' end;
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
create function pg_temp.unit(p_code text) returns uuid language sql as $$
  select id from catalog.units where code = p_code and deleted_at is null
$$;
create function pg_temp.proc(p_code text) returns uuid language sql as $$
  select id from catalog.yield_processes where code = p_code and group_id = '00000000-0000-4000-8000-000000000001'
$$;
grant execute on function pg_temp.u(int), pg_temp.unit(text), pg_temp.proc(text) to authenticated;
-- Cuánto hay que comprar para 1 kg limpio de esa materia prima con ese proceso, como lo calcula el motor (o el estado).
create function pg_temp.buy(p_ingredient int, p_process text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(407), format(
    'select coalesce(round(purchase_quantity, 4)::text, status) from costing.ingredient_line_cost(pg_temp.u(%s), pg_temp.u(201), 1000, pg_temp.unit(''g''), ''clean'', pg_temp.proc(%L))',
    p_ingredient, p_process))
$$;
create function pg_temp.waste(p_user uuid, p_ingredient int, p_cleaning numeric, p_thawing numeric,
                              p_no_loss boolean default false)
returns text language sql as $$
  select pg_temp.q(p_user, format('select catalog.propose_waste(p_ingredient_id => pg_temp.u(%s), p_cleaning_loss => %s, p_thawing_loss => %s, p_declared_no_loss => %L, p_method => %L, p_reason => %L)::text',
                                  p_ingredient, coalesce(p_cleaning::text, 'null'), coalesce(p_thawing::text, 'null'),
                                  p_no_loss, 'Pesado en la cocina', 'Prueba de mermas'))
$$;
-- Aprueba, como el Chef del grupo, la solicitud pendiente de ese proceso para esa materia prima.
create function pg_temp.approve(p_ingredient int, p_process text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(413), format(
    'select workflow.decide_approval(%L, ''approved'', null) ->> ''result''',
    (select p.approval_request_id from catalog.ingredient_yield_profiles p
      where p.ingredient_id = pg_temp.u(p_ingredient) and p.process_id = pg_temp.proc(p_process) and p.status = 'draft'
      order by p.created_at desc limit 1)))
$$;

-- ---------------------------------------------------------------------------
-- Unidades
-- ---------------------------------------------------------------------------
select has_column('catalog', 'units', 'long_name', 'las unidades tienen nombre largo');
select has_column('catalog', 'units', 'abbreviation', 'y abreviatura');
select is((select count(*)::int from catalog.units where deleted_at is null and (long_name is null or abbreviation is null)),
          0, 'todas las unidades vigentes tienen nombre largo y abreviatura');
select is((select long_name || ' (' || abbreviation || ')' from catalog.units where code = 'kg'), 'Kilogramo (kg)',
          'se muestran como «Kilogramo (kg)»');
select is(
  (select string_agg(f.code || '=' || trim(trailing '.' from trim(trailing '0' from c.factor::text)) || t.code, ' ' order by f.code)
     from catalog.unit_conversions c join catalog.units f on f.id = c.from_unit_id join catalog.units t on t.id = c.to_unit_id
    where f.code in ('mg', 'lb', 'oz', 'pinch', 'cc', 'cup', 'tbsp', 'tsp', 'fl_oz', 'portion') and c.deleted_at is null),
  'cc=1ml cup=240ml fl_oz=29.57353ml lb=453.59237g mg=0.001g oz=28.349523g pinch=0.5g portion=1unit tbsp=15ml tsp=5ml',
  'las medidas de recetario nuevas convierten a la base');
select is((select round(quantity, 2)::text from catalog.convert_quantity(pg_temp.u(801), 2, pg_temp.unit('lb'), pg_temp.unit('kg'))),
          '0.91', 'dos libras son 0,91 kg');
select is((select quantity::text || ' ' || status from catalog.convert_quantity(pg_temp.u(801), 1, pg_temp.unit('cup'), pg_temp.unit('g'))),
          null, 'una taza de tomate no pasa a gramos sin densidad: nunca se supone');
select is((select status from catalog.convert_quantity(pg_temp.u(801), 1, pg_temp.unit('cup'), pg_temp.unit('g'))),
          'missing_conversion', 'queda como conversión faltante');

-- Crear unidades: Compras (catalog.manage) sí; el Cocinero no.
select isnt(pg_temp.q(pg_temp.u(408),
  $$select catalog.create_unit(pg_temp.u(1), 'cucharon', 'Cucharón', 'cuch', 'volume', 'La usamos en la cocina', 60)::text$$),
  null, 'Compras crea una unidad');
select is(pg_temp.q(pg_temp.u(408),
  $$select catalog.create_unit(pg_temp.u(1), 'cucharon', 'Otro', 'otro', 'volume', 'Repetida', 50)::text$$),
  'ERROR 23505', 'el código no se repite');
select is((select factor::text from catalog.unit_conversions where from_unit_id = pg_temp.unit('cucharon') and deleted_at is null),
          '60.000000', 'con su conversión a ml');
select ok(exists (select 1 from audit.audit_events where table_name = 'units' and action = 'insert'
                   and new_values ->> 'code' = 'cucharon' and reason = 'La usamos en la cocina'),
          'el alta queda en la auditoría con el motivo');
select is(pg_temp.q(pg_temp.u(409),
  $$select catalog.create_unit(pg_temp.u(1), 'jarra', 'Jarra', 'jarra', 'volume', 'Prueba', 1000)::text$$),
  'ERROR 42501', 'el Cocinero no crea unidades');
select is(pg_temp.q(pg_temp.u(408),
  $$select catalog.create_unit(pg_temp.u(1), 'cajon', 'Cajón', 'cajón', 'package', 'Prueba', 20)::text$$),
  'ERROR 22023', 'un envase no lleva conversión fija');
select is(pg_temp.q(pg_temp.u(408),
  $$select catalog.create_unit(pg_temp.u(1), 'vaso', 'Vaso', 'vaso', 'volume', 'Prueba', null)::text$$),
  'ERROR 22023', 'una medida sin factor no se crea');
select is(pg_temp.q(null, $$select catalog.create_unit(pg_temp.u(1), 'x', 'X', 'x', 'mass', 'Prueba', 1)::text$$),
          'ERROR 42501', 'sin sesión, nada');

-- Dar de baja una unidad que nada usó (para corregir un error de carga; decisión de Joaco).
select is(pg_temp.q(pg_temp.u(409), $$select catalog.archive_unit(pg_temp.u(1), pg_temp.unit('cucharon'), 'Prueba')::text$$),
          'ERROR 42501', 'el Cocinero no da de baja unidades');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.archive_unit(pg_temp.u(1), pg_temp.unit('kg'), 'Prueba')::text$$),
          'ERROR 23514', 'una unidad que ya se usa no se da de baja');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.archive_unit(pg_temp.u(1), pg_temp.unit('g'), 'Prueba')::text$$),
          'ERROR 23514', 'una base, nunca');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.archive_unit(pg_temp.u(1), pg_temp.unit('pinch'), 'Prueba')::text$$),
          'ERROR 23514', 'una del sistema tampoco, aunque nadie la use');
create temporary table cucharon as select pg_temp.unit('cucharon') as id;
select is(pg_temp.q(pg_temp.u(408), $$select catalog.archive_unit(pg_temp.u(1), pg_temp.unit('cucharon'), 'Era de 600, no de 60')::text$$),
          '', 'Compras da de baja el cucharón mal cargado');
select ok(exists (select 1 from audit.audit_events where table_name = 'units' and action = 'soft_delete'
                   and reason = 'Era de 600, no de 60'),
          'la baja queda en la auditoría con el motivo');
select is((select count(*)::int from catalog.unit_conversions where from_unit_id = (select id from cucharon) and deleted_at is null),
          0, 'con su conversión');
select isnt(pg_temp.q(pg_temp.u(408),
  $$select catalog.create_unit(pg_temp.u(1), 'cucharon', 'Cucharón', 'cuch', 'volume', 'Ahora bien', 60)::text$$),
  null, 'y se vuelve a crear bien, con el mismo código');

-- ---------------------------------------------------------------------------
-- El costo de lo cargado no cambia
-- ---------------------------------------------------------------------------
select is((select count(*)::int from catalog.ingredients where requires_thawing), 0,
          'ninguna materia prima viene marcada como congelada');
select is(
  (select count(*)::int
     from recipes.recipe_components x
     join catalog.ingredient_yield_profiles p on p.id = x.yield_profile_id
     left join lateral catalog.approved_yield(x.ingredient_id, p.process_id, p.cut, p.supplier_id) a on true
     left join lateral catalog.costing_yield(x.ingredient_id, p.process_id, p.cut, p.supplier_id) c on true
    where x.deleted_at is null
      and (a.cleaning_yield, a.cooking_factor) is distinct from (c.cleaning_yield, c.cooking_factor)),
  0, 'sin congeladas, el motor usa los mismos rendimientos que antes en todas las líneas');
select is(pg_temp.buy(801, 'PELADO'), '1250.0000', 'tomate pelado al 80 %: 1.250 g para 1 kg limpio (como antes)');
select is(pg_temp.q(pg_temp.u(407), $$select has_function_privilege('catalog.costing_yield(uuid, uuid, text, uuid)', 'execute')::text$$),
          'false', 'el rendimiento del motor es interno');

-- ---------------------------------------------------------------------------
-- Se compra congelada
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$select catalog.set_requires_thawing(pg_temp.u(801), true, 'Prueba')::text$$),
          'ERROR 42501', 'el Cocinero no la marca');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_requires_thawing(pg_temp.u(801), true, 'Viene congelado') ->> 'result'$$),
          'applied', 'Compras la marca como congelada: marcar es directo');
select ok(exists (select 1 from audit.audit_events where table_name = 'ingredients' and action = 'update'
                   and old_values ->> 'requires_thawing' = 'false' and new_values ->> 'requires_thawing' = 'true'
                   and reason = 'Viene congelado'),
          'el cambio queda en la auditoría, con antes y después');
select is(pg_temp.buy(801, 'PELADO'), 'missing_yield',
          'congelada y sin merma de descongelado aprobada: rendimiento no definido (nunca 0 %)');

-- Marcar una que se usa en recetas anota el recálculo.
create temporary table queue_before as select count(*) as n from costing.cost_recalc_queue where reason = 'yield_change';
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_requires_thawing(pg_temp.u(802), true, 'Viene congelada') ->> 'result'$$),
          'applied', 'Compras marca la cebolla, que está en la bolognesa');
select ok((select count(*) from costing.cost_recalc_queue where reason = 'yield_change') > (select n from queue_before),
          'y se anota el recálculo de sus recetas');

-- ---------------------------------------------------------------------------
-- Mermas en %
-- ---------------------------------------------------------------------------
select is(pg_temp.waste(pg_temp.u(410), 801, null, 0.10), 'ERROR 42501', 'el Auditor no propone mermas');
select is(pg_temp.waste(pg_temp.u(405), 801, null, null), 'ERROR 22023', 'sin ninguna merma no se propone nada');
select is(pg_temp.waste(pg_temp.u(405), 801, null, 1), 'ERROR 22023', 'una merma de 100 % no existe');
select is(pg_temp.waste(pg_temp.u(405), 801, null, 0), 'ERROR 23514', 'una merma de 0 % sin declararla no se acepta');
select is(pg_temp.waste(pg_temp.u(405), 801, null, 0.10), '{"requests": 1}', 'la Chef propone 10 % de descongelado');
select is(pg_temp.buy(801, 'PELADO'), 'missing_yield', 'propuesta no es aprobada: el costo no cambia todavía');
-- Quien la propuso no la aprueba (separación de funciones, workflow.decide_approval).
select isnt(pg_temp.q(pg_temp.u(405), format(
  'select workflow.decide_approval(%L, ''approved'', null) ->> ''result''',
  (select approval_request_id from catalog.ingredient_yield_profiles
    where ingredient_id = pg_temp.u(801) and process_id = pg_temp.proc('DESCONGELADO') and status = 'draft'))),
  'approved', 'la Chef que la propuso no la puede aprobar');
select is(pg_temp.approve(801, 'DESCONGELADO'), 'approved', 'la aprueba el Chef del grupo');
select is(pg_temp.buy(801, 'PELADO'), '1388.8889', 'aprobada: 1 kg limpio pide 1.000 / (0,8 × 0,9) = 1.388,9 g');
select is(pg_temp.buy(801, 'DESCONGELADO'), '1111.1111', 'la línea del descongelado solo no lo cuenta dos veces');
select is(pg_temp.q(pg_temp.u(409),
  $$select status from costing.ingredient_line_cost(pg_temp.u(801), pg_temp.u(201), 1000, pg_temp.unit('g'), 'clean', pg_temp.proc('PELADO'))$$),
  'ERROR 42501', 'el Cocinero no ve el costo neto (no tiene prices.view)');

-- El motor de recetas (el costo oficial) y los escenarios usan el mismo descongelado. Una línea limpia de tomate en
-- el borrador del risotto, solo dentro de esta prueba.
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(413), 'role', 'authenticated', 'aal', 'aal2')::text, true);
select core.set_change_context('Línea de prueba', 'manual');
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id,
                                       quantity_basis, yield_profile_id)
select v.group_id, v.id, 99, pg_temp.u(801), 1000, pg_temp.unit('g'), 'clean',
       (select id from catalog.ingredient_yield_profiles
         where ingredient_id = pg_temp.u(801) and process_id = pg_temp.proc('PELADO') and status = 'approved')
  from recipes.recipe_versions v where v.id = pg_temp.u(1211);
select set_config('request.jwt.claims', '', true);
select is((select round(purchase_quantity, 4)::text from costing.recipe_line_costs_internal(pg_temp.u(1211), pg_temp.u(201), current_date)
            where line_order = 99),
          '1388.8889', 'en la receta, la línea limpia de un congelado suma el descongelado');
select is((select round(purchase_quantity, 4)::text
             from costing.recipe_line_costs_internal(pg_temp.u(1211), pg_temp.u(201), current_date,
                  jsonb_build_object('yields', jsonb_build_object(pg_temp.u(801)::text,
                                     jsonb_build_object('cleaning_yield', 0.8, 'cooking_factor', 1))))
            where line_order = 99),
          '1388.8889', 'un escenario que simula el pelado también suma el descongelado (nunca supone 0 %)');

-- Desmarcar baja el costo: pide la aprobación de un Chef de todo el grupo (decisión de Joaco, ADR-0040).
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_requires_thawing(pg_temp.u(801), false, 'Ahora viene fresco') ->> 'result'$$),
          'pending_approval', 'Compras pide desmarcarla: queda pendiente');
select is(pg_temp.buy(801, 'PELADO'), '1388.8889', 'mientras tanto, el costo no baja');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.thawing_change_pending(pg_temp.u(801))::text$$), 'true',
          'la ficha sabe que hay un pedido pendiente');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.set_requires_thawing(pg_temp.u(801), false, 'Otra vez') ->> 'result'$$),
          'ERROR 23505', 'no se pide dos veces');
create temporary table thaw_request as
  select r.id from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
   where w.code = 'catalog.change_requires_thawing' and r.entity_id = pg_temp.u(801) and r.status = 'pending';
grant select on thaw_request to authenticated;
select isnt(pg_temp.q(pg_temp.u(408), $$select workflow.decide_approval((select id from thaw_request), 'approved', null) ->> 'result'$$),
            'approved', 'Compras no aprueba su propio pedido');
select is(pg_temp.q(pg_temp.u(413), $$select workflow.decide_approval((select id from thaw_request), 'approved', null) ->> 'result'$$),
          'approved', 'lo aprueba el Chef del grupo');
select is(pg_temp.buy(801, 'PELADO'), '1250.0000', 'aprobado: vuelve al pelado solo');

-- Limpieza: conserva el factor de cocción que ya tenía, y todo o nada.
select is(pg_temp.q(pg_temp.u(405),
  $$select catalog.propose_yield_standard(pg_temp.u(803), pg_temp.proc('LIMPIEZA'), null, 0.9, 0.95, 'Prueba', false, 'Prueba')::text$$) is not null
  and pg_temp.approve(803, 'LIMPIEZA') = 'approved', true, 'el ajo tiene limpieza 90 % y cocción 0,95');
select is(pg_temp.waste(pg_temp.u(405), 803, 0.15, null), '{"requests": 1}', 'la Chef propone 15 % de merma de limpieza');
select is((select cleaning_yield::text || '/' || cooking_factor::text from catalog.ingredient_yield_profiles
            where ingredient_id = pg_temp.u(803) and process_id = pg_temp.proc('LIMPIEZA') and status = 'draft'),
          '0.8500/0.9500', 'la propuesta es 85 % y conserva la cocción');
select is(pg_temp.waste(pg_temp.u(405), 803, 0.2, 0.05), 'ERROR 23505',
          'con la limpieza ya pendiente, el par no se propone');
select is((select count(*)::int from catalog.ingredient_yield_profiles
            where ingredient_id = pg_temp.u(803) and process_id = pg_temp.proc('DESCONGELADO')),
          0, 'y el descongelado tampoco quedó: todo o nada');

-- 0 % solo declarado.
select is(pg_temp.waste(pg_temp.u(405), 802, null, 0, true), '{"requests": 1}', 'declarada «No tiene merma», sí');
select is((select declared_no_loss from catalog.ingredient_yield_profiles
            where ingredient_id = pg_temp.u(802) and process_id = pg_temp.proc('DESCONGELADO') and status = 'draft'),
          true, 'y la propuesta lleva la declaración');

-- ---------------------------------------------------------------------------
-- Merma de cocción informativa
-- ---------------------------------------------------------------------------
select is((select coalesce(input_grams::text, '-') || '/' || status from recipes.cooking_loss(pg_temp.u(1202))),
          '-/missing_conversion', 'la bolognesa lleva vino y aceite en ml: sin densidad no hay merma (ni una suma parcial)');
select is((select status from recipes.cooking_loss(pg_temp.u(1201))), 'yield_not_weight',
          'la salsa fileto rinde en litros: no se calcula');
select is(pg_temp.q(pg_temp.u(408), $$select string_agg(catalog.set_unit_conversion(id, 'density', d, 'manual',
            current_date, 'Compras', 'Densidad medida')::text, '') from (values ('Vino tinto para cocinar', 1.0),
            ('Aceite de girasol', 0.92)) as v (n, d) join catalog.ingredients i on i.name = v.n$$),
          '', 'Compras carga la densidad del vino y del aceite');
select is((select input_grams::numeric(10,1)::text || ' → ' || output_grams::numeric(10,1)::text || ' = ' || factor::text || ' ' || status
             from recipes.cooking_loss(pg_temp.u(1202))),
          '3868.0 → 3000.0 = 0.7756 ok', 'con las densidades: entran 3.868 g, salen 3 kg, merma de cocción 22,4 %');
select is(pg_temp.q(pg_temp.u(413), $$select factor::text || ' ' || status from recipes.cooking_loss(pg_temp.u(1202))$$),
          '0.7756 ok', 'el Chef del grupo la ve con su sesión (no usa funciones internas)');
select is(pg_temp.q(null, $$select status from recipes.cooking_loss(pg_temp.u(1202))$$), 'ERROR 42501', 'sin sesión, nada');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.cooking_loss(pg_temp.u(1211))$$), '0',
          'la Cocinera no ve el borrador del risotto: tampoco su merma de cocción');

select * from finish();
rollback;
