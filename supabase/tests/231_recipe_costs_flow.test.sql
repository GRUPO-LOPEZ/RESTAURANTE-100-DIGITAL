-- Fase 2 · Etapa 2.3, PR 1: el recálculo y la historia (ADR-0032). Casos 5 (cambio de precio en 3 niveles), 15
-- (integridad histórica) y 16 (densidad), cada cosa que dispara un recálculo y que las fotos no cambian.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(75);

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

create function pg_temp.snapshots(p_n int, p_rest int) returns bigint language sql as $$
  select costing.process_recalc_queue(1000);
  select count(*) from costing.recipe_cost_snapshots where recipe_id = pg_temp.u(97000 + p_n) and restaurant_id = pg_temp.u(p_rest)
$$;
create function pg_temp.has_reason(p_n int, p_rest int, p_reason text) returns boolean language sql as $$
  select costing.process_recalc_queue(1000);
  select exists (select 1 from costing.recipe_cost_snapshots where recipe_id = pg_temp.u(97000 + p_n) and restaurant_id = pg_temp.u(p_rest)
                    and reason::text = p_reason)
$$;

-- Caso 5: tres niveles. Una materia prima a 1 $/g, una preparación, otra arriba y un plato.
select pg_temp.ing(1);
select pg_temp.price(1, 1000, 'group', null, 2);
select pg_temp.recipe(1, 'preparation', 1000, 'g', null);
select pg_temp.line(1, 1, 1, 1000, 'g');
select pg_temp.publish(1);
select pg_temp.recipe(2, 'preparation', 1000, 'g', null);
select pg_temp.sub(2, 1, 1, 500, 'g');
select pg_temp.publish(2);
select pg_temp.recipe(3, 'dish', 1, 'unit', 1);
select pg_temp.sub(3, 1, 2, 100, 'g');
select pg_temp.publish(3);
select pg_temp.assign(3, 201);
select is(pg_temp.cost(1, 201) || '/' || pg_temp.cost(2, 201) || '/' || pg_temp.cost(3, 201), '1000.0000/500.0000/50.0000',
  'tres niveles: $ 1.000, $ 500 y $ 50');
create temporary table old_photo as
  select to_jsonb(s) as photo, s.id from costing.recipe_cost_snapshots s where s.recipe_id = pg_temp.u(97003);
create temporary table old_lines as
  select to_jsonb(l) as line from costing.recipe_cost_snapshot_lines l where l.snapshot_id in (select id from old_photo);
select is((select count(*) from old_photo), 1::bigint, 'el plato tiene una foto');

-- El precio se duplica: aprobar solo anota el pedido, y el proceso de la cola recalcula los tres niveles.
select pg_temp.price(1, 2000);
select is((select total_cost::text from costing.recipe_cost_current where recipe_id = pg_temp.u(97003) and restaurant_id = pg_temp.u(201)),
  '50.0000', 'al aprobar, el costo todavía no cambió');
select cmp_ok((select count(*) from costing.cost_recalc_queue where processed_at is null), '>', 0::bigint, 'queda anotado en la cola');
select is(pg_temp.cost(1, 201) || '/' || pg_temp.cost(2, 201) || '/' || pg_temp.cost(3, 201), '2000.0000/1000.0000/100.0000',
  'caso 5: un precio nuevo recalcula los tres niveles');
select ok(pg_temp.has_reason(3, 201, 'price_change'), 'la foto nueva dice que fue por el precio');
select is(pg_temp.snapshots(3, 201), 2::bigint, 'y hay una foto más');

select is((select count(*) from costing.cost_recalc_queue where processed_at is null), 0::bigint, 'y la cola queda vacía');

-- Caso 15: varios cambios después, la foto vieja sigue igual, con su detalle.
select pg_temp.price(1, 3000);
select costing.process_recalc_queue(1000);
select pg_temp.price(1, 4000);
select costing.process_recalc_queue(1000);
select is((select photo from old_photo), (select to_jsonb(s) from costing.recipe_cost_snapshots s where s.id = (select id from old_photo)),
  'caso 15: la foto vieja no cambió');
select is((select jsonb_agg(line) from old_lines),
          (select jsonb_agg(to_jsonb(l)) from costing.recipe_cost_snapshot_lines l where l.snapshot_id = (select id from old_photo)),
  'caso 15: su detalle tampoco');

-- Lo guardado sale de la cuenta con precios y preparaciones reutilizados: tiene que dar lo mismo que la directa.
select is((select round(t.total_cost, 4)::text from costing.recipe_totals_internal(pg_temp.u(98003), pg_temp.u(201), current_date) t),
  pg_temp.cost(3, 201), 'el recálculo da lo mismo que la cuenta directa');

-- Sin cambios, no hay foto.
select pg_temp.price(1, 4000);
select is(pg_temp.snapshots(3, 201), 4::bigint, 'el mismo precio otra vez no saca una foto');

-- Un precio de otro lugar no toca este local, y uno con fecha futura no cambia nada hoy.
select pg_temp.price(1, 9000, 'restaurant', 203);
select is(pg_temp.snapshots(3, 201), 4::bigint, 'un precio de otro local no recalcula este');
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(1), pg_temp.u(96001), 'group', current_date + 5, 8000, 'no_invoice', 'test_value');
select is(pg_temp.cost(3, 201), '200.0000', 'un precio con fecha futura todavía no cuenta');

-- La foto guarda lo que no tiene versión.
select is((select l.price_record_id is not null and l.package_base_quantity = 1000 and l.purchase_quantity = 1000 and l.line_status = 'ok'
             from costing.recipe_cost_snapshot_lines l join costing.recipe_cost_snapshots s on s.id = l.snapshot_id
            where s.recipe_id = pg_temp.u(97001) order by s.created_at desc, s.id limit 1), true,
  'cada línea guarda el precio, el contenido y la cantidad que usó');
select is((select l.sub_recipe_version_id
             from costing.recipe_cost_snapshot_lines l join costing.recipe_cost_snapshots s on s.id = l.snapshot_id
            where s.recipe_id = pg_temp.u(97003) order by s.created_at desc, s.id limit 1), pg_temp.u(98002),
  'y la versión de la preparación');

-- Las cantidades congeladas: 100 ml de aceite a densidad 0,92 son 92 g, a 10 $/g: $ 920 (caso 16).
select pg_temp.ing(2);
select pg_temp.price(2, 10000);
insert into catalog.ingredient_unit_conversions (group_id, ingredient_id, kind, factor, source, measured_on)
values (pg_temp.u(1), pg_temp.u(95002), 'density', 0.92, 'measured', current_date);
select pg_temp.recipe(4, 'dish', 1, 'unit', 1);
select pg_temp.line(4, 1, 2, 100, 'ml');
select pg_temp.publish(4);
select pg_temp.assign(4, 201);
select is(pg_temp.cost(4, 201), '920.0000', 'caso 16: 100 ml × 0,92 = 92 g × 10 $/g');
select is((select base_quantity from recipes.component_base_quantities where recipe_version_id = pg_temp.u(98004)), 92.000000,
  'al publicar se congela la cantidad en gramos');
update catalog.ingredient_unit_conversions set factor = 1 where ingredient_id = pg_temp.u(95002);
select pg_temp.price(2, 20000);
select is(pg_temp.cost(4, 201), '1840.0000', 'una densidad nueva no mueve lo publicado: el precio sí, con los mismos 92 g');
-- Un borrador usa la conversión de hoy.
select pg_temp.recipe(5, 'dish', 1, 'unit', 1);
select pg_temp.line(5, 1, 2, 100, 'ml');
select is((select total_cost from costing.recipe_totals_internal(pg_temp.u(98005), pg_temp.u(201), current_date)), 2000.00000000::numeric,
  'un borrador usa la conversión de hoy');

-- Un rendimiento nuevo: la línea sigue su proceso y toma el estándar aprobado hoy.
select pg_temp.ing(3);
select pg_temp.price(3, 2000);
create temporary table profiles (k text primary key, id uuid);
insert into profiles values ('viejo', pg_temp.yield(3, 961, 0.5, 1));
select pg_temp.recipe(6, 'dish', 1, 'unit', 1);
select pg_temp.line(6, 1, 3, 100, 'g', 'clean', (select id from profiles where k = 'viejo'));
select pg_temp.publish(6);
select pg_temp.assign(6, 201);
select is(pg_temp.cost(6, 201), '400.0000', 'con 50 %: 200 g comprados, $ 400');
update catalog.ingredient_yield_profiles set status = 'superseded' where id = (select id from profiles where k = 'viejo');
insert into profiles values ('nuevo', pg_temp.yield(3, 961, 0.25, 1));
select is(pg_temp.cost(6, 201), '800.0000', 'con el estándar nuevo (25 %), $ 800');
select ok(pg_temp.has_reason(6, 201, 'yield_change'), 'la foto dice que fue por el rendimiento');
-- Sin estándar aprobado, la línea queda sin rendimiento: nunca usa el reemplazado.
update catalog.ingredient_yield_profiles set status = 'superseded' where id = (select id from profiles where k = 'nuevo');
select is(pg_temp.line_status(6, 201), 'missing_yield', 'sin estándar aprobado no se usa el reemplazado');

-- Asignar y dejar de usar.
select is(pg_temp.cost(3, 202), null, 'antes de asignarlo, el otro local no tiene costo');
select pg_temp.assign(3, 202);
select is(pg_temp.cost(3, 202), '200.0000', 'al asignarlo, se calcula');
select is(pg_temp.cost(1, 202), '4000.0000', 'y sus preparaciones también');
select ok(pg_temp.has_reason(3, 202, 'assignment'), 'la foto dice por qué');
update recipes.recipe_assignments set valid_to = current_date - 1 where recipe_id = pg_temp.u(97003) and restaurant_id = pg_temp.u(202);
select is(pg_temp.cost(3, 202), null, 'al dejar de usarlo, el costo vigente se da de baja');
select is(pg_temp.cost(1, 202), null, 'también el de sus preparaciones');
select cmp_ok(pg_temp.snapshots(3, 202), '>=', 1::bigint, 'la historia queda');

-- Una versión nueva.
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, previous_version_id)
values (pg_temp.u(98101), pg_temp.u(1), pg_temp.u(97001), 2, 2000, (select id from catalog.units where code = 'g'), pg_temp.u(98001));
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
values (pg_temp.u(1), pg_temp.u(98101), 1, pg_temp.u(95001), 1000, (select id from catalog.units where code = 'g'));
update recipes.recipe_versions set status = 'archived' where id = pg_temp.u(98001);
update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(98101);
update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(98101);
update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(98101);
select is(pg_temp.cost(1, 201, 'recipe_version_id'), pg_temp.u(98101)::text, 'al publicar, el costo vigente pasa a la versión nueva');
select is(pg_temp.cost(3, 201), '100.0000', 'y los platos que la usan cambian: rinde el doble, cuesta la mitad');
select ok(pg_temp.has_reason(1, 201, 'publish'), 'la foto dice que fue por la publicación');

-- La razón social: sin ella no se sabe si el IVA se recupera; con monotributo, cuenta con IVA.
select pg_temp.ing(4);
select pg_temp.price(4, 12100, 'group', null, 1, true);
select pg_temp.recipe(7, 'dish', 1000, 'g', 1);
select pg_temp.line(7, 1, 4, 1000, 'g');
select pg_temp.publish(7);
select pg_temp.assign(7, 201);
select is(pg_temp.cost(7, 201), '10000.0000', 'responsable inscripto: sin IVA');
update org.restaurants set legal_entity_id = pg_temp.u(1502) where id = pg_temp.u(201);
select is(pg_temp.cost(7, 201), '12100.0000', 'al cambiar la razón social, se recalcula');
select ok(pg_temp.has_reason(7, 201, 'legal_entity_change'), 'y la foto dice por qué');
update org.legal_entities set vat_condition = 'registered' where id = pg_temp.u(1502);
select is(pg_temp.cost(7, 201), '10000.0000', 'al cambiar la condición frente al IVA, también');
update org.restaurants set legal_entity_id = null where id = pg_temp.u(201);
select is(pg_temp.cost(7, 201), null, 'sin razón social, el costo queda vacío');
select is(pg_temp.cost(7, 201, 'total_gross_cost'), '12100.0000', 'pero con IVA se ve');
select is(pg_temp.line_status(7, 201), 'missing_legal_entity', 'y el detalle dice qué falta');

-- Una tanda de precios se recalcula una sola vez.
update org.restaurants set legal_entity_id = pg_temp.u(1501) where id = pg_temp.u(201);
select costing.process_recalc_queue(1000);
create temporary table before_batch as select pg_temp.snapshots(3, 201) as n;
select pg_temp.price(1, 5000);
select pg_temp.price(1, 6000);
select pg_temp.price(1, 7000);
select is(pg_temp.snapshots(3, 201), (select n + 1 from before_batch), 'tres precios en cola: una sola foto, con el último');

-- La preparación de un plato también cambia con la razón social, aunque no esté asignada sola.
select pg_temp.ing(5);
select pg_temp.price(5, 12100, 'group', null, 1, true);
select pg_temp.recipe(8, 'preparation', 1000, 'g', null);
select pg_temp.line(8, 1, 5, 1000, 'g');
select pg_temp.publish(8);
select pg_temp.recipe(9, 'dish', 1, 'unit', 1);
select pg_temp.sub(9, 1, 8, 500, 'g');
select pg_temp.publish(9);
select pg_temp.assign(9, 201);
select is(pg_temp.cost(8, 201), '10000.0000', 'la preparación, sin IVA');
update org.restaurants set legal_entity_id = pg_temp.u(1502) where id = pg_temp.u(201);
update org.legal_entities set vat_condition = 'monotax' where id = pg_temp.u(1502);
select is(pg_temp.cost(8, 201) || '/' || pg_temp.cost(9, 201), '12100.0000/6050.0000',
  'con monotributo cambian el plato y su preparación');
update org.restaurants set legal_entity_id = pg_temp.u(1501) where id = pg_temp.u(201);
select costing.process_recalc_queue(1000);

-- Una variante que rinde en cajas: el plato no se puede calcular y no sale más barato.
insert into recipes.recipes (id, group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id, variant_of_recipe_id)
values (pg_temp.u(97010), pg_temp.u(1), pg_temp.u(101), pg_temp.u(201), 'restaurant', 'COSTO-REC-10', 'Variante en cajas', 'preparation',
        pg_temp.u(1061), pg_temp.u(97008));
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id)
values (pg_temp.u(98010), pg_temp.u(1), pg_temp.u(97010), 1, 1, (select id from catalog.units where code = 'box'));
select pg_temp.line(10, 1, 1, 100, 'g');
select pg_temp.publish(10);
select pg_temp.assign(10, 201);
select is(pg_temp.cost(9, 201), null, 'una variante que rinde en cajas deja el plato incompleto, nunca más barato');
select is(pg_temp.line_status(9, 201), 'missing_yield', 'y dice qué falta');

-- Un círculo a través de una variante: no se recorre.
insert into recipes.recipes (id, group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id, variant_of_recipe_id)
values (pg_temp.u(97011), pg_temp.u(1), pg_temp.u(101), pg_temp.u(202), 'restaurant', 'COSTO-REC-11', 'Variante con su maestra', 'preparation',
        pg_temp.u(1061), pg_temp.u(97008));
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id)
values (pg_temp.u(98011), pg_temp.u(1), pg_temp.u(97011), 1, 1000, (select id from catalog.units where code = 'g'));
select pg_temp.sub(11, 1, 8, 500, 'g');
select pg_temp.publish(11);
select pg_temp.assign(11, 202);
select pg_temp.assign(9, 202);
select is(pg_temp.cost(9, 202), null, 'una variante que se usa a sí misma queda incompleta, sin romper');
select is((select count(*) from costing.cost_recalc_queue where error is not null), 0::bigint, 'y la cola no registra errores');

-- Un rendimiento absurdo no rompe la aprobación de un precio.
select pg_temp.ing(6);
select pg_temp.recipe(12, 'preparation', 0.000001, 'g', null);
select pg_temp.line(12, 1, 6, 1000000, 'g');
select pg_temp.publish(12);
select pg_temp.assign(12, 201);
select pg_temp.price(6, 1000000);
select is(pg_temp.cost(12, 201, 'cost_per_base_unit'), null, 'lo que no entra en la columna queda vacío');
select is(pg_temp.cost(12, 201, 'reliability'), 'incomplete', 'y el costo, incompleto');
select is((select count(*) from costing.cost_recalc_queue where error is not null), 0::bigint, 'sin errores en la cola');
-- Un plato que usa esa preparación con una cantidad chica también queda incompleto.
select pg_temp.recipe(18, 'dish', 1, 'unit', 1);
select pg_temp.sub(18, 1, 12, 0.000001, 'g');
select pg_temp.publish(18);
select pg_temp.assign(18, 201);
select is(pg_temp.cost(18, 201), null, 'el plato de una preparación absurda no se calcula');

-- Si la materia prima cambia de unidad de uso, la cantidad congelada ya no vale.
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
values (pg_temp.u(95007), pg_temp.u(1), 'COSTO-ING-7', 'Materia prima sin productos', pg_temp.u(707), (select id from catalog.units where code = 'g'));
select pg_temp.recipe(13, 'dish', 1, 'unit', 1);
select pg_temp.line(13, 1, 7, 100, 'g');
select pg_temp.publish(13);
update catalog.ingredients set recipe_unit_id = (select id from catalog.units where code = 'ml') where id = pg_temp.u(95007);
select is(pg_temp.line_status(13, 201), 'missing_conversion', 'otra unidad de uso: no se multiplica por el precio nuevo');

-- Archivar por el flujo real (Chef del grupo): el costo se da de baja, y los platos que la usaban quedan incompletos.
select pg_temp.recipe(14, 'preparation', 1000, 'g', null);
select pg_temp.line(14, 1, 1, 1000, 'g');
select pg_temp.publish(14);
select pg_temp.recipe(15, 'dish', 1, 'unit', 1);
select pg_temp.line(15, 1, 1, 100, 'g');
select pg_temp.publish(15);
select pg_temp.assign(15, 201);
select cmp_ok(pg_temp.cost(15, 201), 'is not', null, 'antes de archivar tiene costo');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.archive_recipe(%L, ''Ya no'') ->> ''result''', pg_temp.u(97015))), 'applied', 'el Chef la archiva');
select is(pg_temp.cost(15, 201), null, 'archivada, deja de tener costo vigente');
select cmp_ok(pg_temp.snapshots(15, 201), '>=', 1::bigint, 'la historia queda');

-- Publicar por el flujo real: pedir la revisión y aprobar.
select pg_temp.recipe(16, 'dish', 1, 'unit', 1);
select pg_temp.line(16, 1, 1, 100, 'g');
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes)
values (pg_temp.u(1), pg_temp.u(98016), 1, 'preparation', 'Hacer', 10);
select is(pg_temp.q(pg_temp.u(413), format('select recipes.request_review(%L, ''Prueba'') ->> ''result''', pg_temp.u(98016))), 'pending_approval', 'se pide la revisión');
select is(pg_temp.q(pg_temp.u(402), format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''',
                                           (select approval_request_id from recipes.recipe_versions where id = pg_temp.u(98016)))), 'approved', 'y se aprueba');
select is((select count(*) from recipes.component_base_quantities where recipe_version_id = pg_temp.u(98016)), 1::bigint,
  'publicar por el flujo real congela la cantidad');
select pg_temp.assign(16, 201);
select is(pg_temp.cost(16, 201), '700.0000', 'y la receta tiene costo');

-- Dos pedidos de locales distintos en una tanda: se recalculan los dos.
select pg_temp.ing(8);
select pg_temp.price(8, 1000);
select pg_temp.recipe(17, 'dish', 1000, 'g', 1);
select pg_temp.line(17, 1, 8, 1000, 'g');
select pg_temp.publish(17);
select pg_temp.assign(17, 201);
select pg_temp.assign(17, 203);
select is(pg_temp.cost(17, 201) || '/' || pg_temp.cost(17, 203), '1000.0000/1000.0000', 'el grupo a $ 1.000 en los dos locales');
select pg_temp.price(8, 2000, 'restaurant', 201);
select pg_temp.price(8, 3000, 'restaurant', 203);
select is(pg_temp.cost(17, 201) || '/' || pg_temp.cost(17, 203), '2000.0000/3000.0000', 'una tanda con dos locales recalcula los dos');

-- Un local cerrado no se recalcula, y al reabrir se pone al día.
update org.restaurants set status = 'inactive' where id = pg_temp.u(203);
select pg_temp.price(8, 4000, 'restaurant', 203);
select is(pg_temp.cost(17, 203), '3000.0000', 'un local cerrado no se recalcula');
update org.restaurants set status = 'active' where id = pg_temp.u(203);
select is(pg_temp.cost(17, 203), '4000.0000', 'al reabrirlo, se pone al día');
select ok(pg_temp.has_reason(17, 203, 'restaurant_reopened'), 'y la foto dice por qué');

-- Un pedido que falla: guarda el error, los sanos pasan y a los 3 intentos deja de reintentarse.
create function pg_temp.boom() returns trigger language plpgsql as $f$
begin
  if new.total_cost = 5000 then
    raise exception 'Falla de prueba';
  end if;
  return new;
end
$f$;
create trigger boom before insert or update on costing.recipe_cost_current for each row execute function pg_temp.boom();
select pg_temp.price(8, 5000, 'restaurant', 201);
select pg_temp.price(1, 7500);
select pg_temp.price(8, 6000, 'restaurant', 204);
create temporary table sane as select id from costing.cost_recalc_queue where processed_at is null;
select costing.process_recalc_queue(1000);
select is((select attempts || '/' || error from costing.cost_recalc_queue where id in (select id from sane) and processed_at is null),
  '1/Falla de prueba', 'el pedido que falla guarda el intento y el error');
select is(pg_temp.cost(3, 201), '187.5000', 'y el pedido sano de la misma tanda pasa');
select costing.process_recalc_queue(1000);
select costing.process_recalc_queue(1000);
select costing.process_recalc_queue(1000);
select is((select attempts from costing.cost_recalc_queue where id in (select id from sane) and processed_at is null), 3,
  'a los 3 intentos deja de reintentarse');
drop trigger boom on costing.recipe_cost_current;
update costing.cost_recalc_queue set processed_at = now() where processed_at is null;

-- La tarea que procesa la cola está programada.
select is((select schedule from cron.job where jobname = 'grupo-lf-recalcular-costos'), '* * * * *', 'la cola se procesa cada minuto');

-- La historia no se toca.
select throws_ok(format('update costing.recipe_cost_snapshots set total_cost = 1 where id = %L', (select id from old_photo)), '42501', null,
  'una foto no se cambia');
select throws_ok(format('delete from costing.recipe_cost_snapshots where id = %L', (select id from old_photo)), '42501', null,
  'ni se borra');
select throws_ok(format('update costing.recipe_cost_snapshot_lines set line_cost = 1 where snapshot_id = %L', (select id from old_photo)), '42501', null,
  'su detalle tampoco se cambia');
select throws_ok($$update recipes.component_base_quantities set base_quantity = 1$$, '42501', null, 'una cantidad congelada no se cambia');
select ok(exists (select 1 from audit.audit_events where table_name = 'component_base_quantities' and action::text = 'insert'),
  'las cantidades congeladas quedan en la auditoría');

select * from finish();
rollback;
