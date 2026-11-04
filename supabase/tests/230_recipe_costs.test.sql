-- Fase 2 · Etapa 2.3, PR 1: el cálculo del motor de costos (ADR-0032), con las cuentas hechas a mano.
-- Casos del plan de la Fase 2: 3 (subreceta), 4 (porción), 7 (multiestablecimiento), 9 (falta precio),
-- 18 (hidratación), 19 (doble merma) y 27 (sin rendimiento). Más IVA, confiabilidad y variantes.
-- Locales del seed: 201 y 202 Demo Pastas (marca 101), 203 Demo Parrilla (102), 204 Demo Café (103, monotributo).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(38);

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

-- Caso 3: una preparación de 1.000 g cuesta $ 4.000, o sea 4 $/g. 150 g en un plato: 4 × 150 = $ 600.
select pg_temp.ing(1);
select pg_temp.price(1, 4000);
select pg_temp.recipe(1, 'preparation', 1000, 'g', null);
select pg_temp.line(1, 1, 1, 1000, 'g');
select pg_temp.publish(1);
select pg_temp.recipe(2, 'dish', 1, 'unit', 1);
select pg_temp.sub(2, 1, 1, 150, 'g');
select pg_temp.publish(2);
select pg_temp.assign(2, 201);
select is(pg_temp.cost(2, 201), '600.0000', 'caso 3: 4 $/g × 150 g = $ 600');
select is(pg_temp.cost(1, 201), '4000.0000', 'la preparación también tiene su costo en el local del plato');
select is(pg_temp.cost(1, 201, 'cost_per_base_unit'), '4.00000000', 'y su costo por gramo terminado');

-- Una línea en kg de una preparación en gramos: 0,15 kg son los mismos 150 g.
select pg_temp.recipe(3, 'dish', 1, 'unit', 1);
select pg_temp.sub(3, 1, 1, 0.15, 'kg');
select pg_temp.publish(3);
select pg_temp.assign(3, 201);
select is(pg_temp.cost(3, 201), '600.0000', 'la unidad de la línea se pasa a la de la preparación');

-- Caso 4: 3.000 g a 4 $/g son $ 12.000, en 10 porciones: $ 1.200.
select pg_temp.recipe(4, 'dish', 3000, 'g', 10);
select pg_temp.line(4, 1, 1, 3000, 'g');
select pg_temp.publish(4);
select pg_temp.assign(4, 201);
select is(pg_temp.cost(4, 201), '12000.0000', 'caso 4: el total');
select is(pg_temp.cost(4, 201, 'cost_per_portion'), '1200.0000', 'caso 4: 12.000 / 10 = $ 1.200 por porción');

-- Caso 7: la misma receta, con la carne a $ 10.000 en una marca y $ 11.000 en otra.
select pg_temp.ing(2);
select pg_temp.price(2, 10000, 'brand', 101);
select pg_temp.price(2, 11000, 'brand', 102);
select pg_temp.recipe(5, 'dish', 1000, 'g', 1);
select pg_temp.line(5, 1, 2, 1000, 'g');
select pg_temp.publish(5);
select pg_temp.assign(5, 201);
select pg_temp.assign(5, 203);
select is(pg_temp.cost(5, 201), '10000.0000', 'caso 7: en una marca, $ 10.000');
select is(pg_temp.cost(5, 203), '11000.0000', 'caso 7: en la otra, $ 11.000: dos costos, una receta');

-- Caso 9: sin precio, incompleto, nunca $ 0.
select pg_temp.ing(3);
select pg_temp.recipe(6, 'dish', 1000, 'g', 1);
select pg_temp.line(6, 1, 1, 1000, 'g');
select pg_temp.line(6, 2, 3, 500, 'g');
select pg_temp.publish(6);
select pg_temp.assign(6, 201);
select is(pg_temp.cost(6, 201), null, 'caso 9: falta un precio: el total queda vacío, nunca $ 0');
select is(pg_temp.cost(6, 201, 'reliability'), 'incomplete', 'caso 9: y es incompleto');
select is(pg_temp.line_status(6, 201), 'ok,missing_price', 'el detalle dice qué línea falta');
-- Un plato que usa esa preparación incompleta también lo es.
select pg_temp.recipe(7, 'preparation', 1000, 'g', null);
select pg_temp.line(7, 1, 3, 1000, 'g');
select pg_temp.publish(7);
select pg_temp.recipe(8, 'dish', 1, 'unit', 1);
select pg_temp.sub(8, 1, 7, 100, 'g');
select pg_temp.publish(8);
select pg_temp.assign(8, 201);
select is(pg_temp.line_status(8, 201), 'incomplete_sub_recipe', 'una preparación incompleta deja incompleto al plato');
select is(pg_temp.cost(8, 201), null, 'y su total queda vacío');

-- Caso 18: 250 g cocidos de una pasta que se expande ×2,5 son 100 g secos, a 3 $/g: $ 300.
select pg_temp.ing(4);
select pg_temp.price(4, 3000);
create temporary table profiles (k text primary key, id uuid);
insert into profiles values ('pasta', pg_temp.yield(4, 965, 1, 2.5));
select pg_temp.recipe(9, 'dish', 1, 'unit', 1);
select pg_temp.line(9, 1, 4, 250, 'g', 'cooked', (select id from profiles where k = 'pasta'));
select pg_temp.publish(9);
select pg_temp.assign(9, 201);
select is(pg_temp.cost(9, 201), '300.0000', 'caso 18: 250 g / (1 × 2,5) = 100 g × 3 $/g = $ 300');
-- La misma cuenta que la línea suelta.
select is(pg_temp.q(pg_temp.u(407), format(
  'select line_cost::numeric(18,4)::text from costing.ingredient_line_cost(%L, %L, 250, (select id from catalog.units where code = ''g''), ''cooked'', %L)',
  pg_temp.u(95004), pg_temp.u(201), pg_temp.u(965))), '300.0000', 'ingredient_line_cost da lo mismo');

-- Caso 19: 500 g limpios de un tomate que rinde 50 % son 1.000 g comprados, a 2 $/g: $ 2.000. La salsa rinde
-- 500 g, 4 $/g. En un plato, 100 g cuestan $ 400: la merma se cuenta una sola vez.
select pg_temp.ing(5);
select pg_temp.price(5, 2000);
insert into profiles values ('tomate', pg_temp.yield(5, 961, 0.5, 1));
select pg_temp.recipe(10, 'preparation', 500, 'g', null);
select pg_temp.line(10, 1, 5, 500, 'g', 'clean', (select id from profiles where k = 'tomate'));
select pg_temp.publish(10);
select pg_temp.recipe(11, 'dish', 1, 'unit', 1);
select pg_temp.sub(11, 1, 10, 100, 'g');
select pg_temp.publish(11);
select pg_temp.assign(11, 201);
select is(pg_temp.cost(10, 201), '2000.0000', 'caso 19: la salsa cuesta $ 2.000');
select is(pg_temp.cost(11, 201), '400.0000', 'caso 19: el plato, $ 400: la merma del tomate va una sola vez');

-- Línea limpia sin rendimiento: nunca se supone 100 %.
select pg_temp.recipe(12, 'dish', 1, 'unit', 1);
select pg_temp.line(12, 1, 5, 500, 'g', 'clean');
select pg_temp.publish(12);
select pg_temp.assign(12, 201);
select is(pg_temp.line_status(12, 201), 'missing_yield', 'limpia y sin rendimiento: no se supone 100 %');
select is(pg_temp.cost(12, 201), null, 'y el total queda vacío');

-- Caso 27: sin rendimiento ni porciones, no se divide.
select pg_temp.recipe(13, 'dish', null, null, null);
select pg_temp.line(13, 1, 1, 100, 'g');
select pg_temp.publish(13);
select pg_temp.assign(13, 201);
select is(pg_temp.cost(13, 201), '400.0000', 'caso 27: el total se calcula');
select is(pg_temp.cost(13, 201, 'cost_per_base_unit'), null, 'caso 27: sin rendimiento, no se divide');
select is(pg_temp.cost(13, 201, 'reliability'), 'incomplete', 'caso 27: el costo unitario queda incompleto');
-- Con porciones y sin rendimiento: hay costo por porción.
select pg_temp.recipe(14, 'dish', null, null, 4);
select pg_temp.line(14, 1, 1, 100, 'g');
select pg_temp.publish(14);
select pg_temp.assign(14, 201);
select is(pg_temp.cost(14, 201, 'cost_per_portion'), '100.0000', 'con porciones, el costo por porción sale igual');

-- IVA (ADR-0024): $ 12.100 con 21 % son $ 10.000 sin IVA. Un responsable inscripto lo recupera; el monotributo, no.
select pg_temp.ing(6);
select pg_temp.price(6, 12100, 'group', null, 1, true);
select pg_temp.recipe(15, 'dish', 1000, 'g', 1);
select pg_temp.line(15, 1, 6, 1000, 'g');
select pg_temp.publish(15);
select pg_temp.assign(15, 201);
select pg_temp.assign(15, 204);
select is(pg_temp.cost(15, 201), '10000.0000', 'responsable inscripto: el costo es sin IVA');
select is(pg_temp.cost(15, 201, 'total_gross_cost'), '12100.0000', 'y se guarda también con IVA');
select is(pg_temp.cost(15, 204), '12100.0000', 'monotributo: el IVA no se recupera, el costo es con IVA');

-- Confiabilidad: gana la peor línea.
select pg_temp.ing(7);
select pg_temp.price(7, 1000, 'restaurant', 201);
select pg_temp.ing(8);
select pg_temp.price(8, 1000, 'restaurant', 201, 60);
select pg_temp.recipe(16, 'dish', 1000, 'g', 1);
select pg_temp.line(16, 1, 7, 1000, 'g');
select pg_temp.publish(16);
select pg_temp.assign(16, 201);
select is(pg_temp.cost(16, 201, 'reliability'), 'verified', 'precio propio del local: completo y verificado');
select is(pg_temp.cost(4, 201, 'reliability'), 'estimated', 'precio heredado del grupo: con estimaciones');
select pg_temp.recipe(17, 'dish', 1000, 'g', 1);
select pg_temp.line(17, 1, 7, 1000, 'g');
select pg_temp.line(17, 2, 8, 1000, 'g');
select pg_temp.line(17, 3, 1, 1000, 'g');
select pg_temp.publish(17);
select pg_temp.assign(17, 201);
select is(pg_temp.cost(17, 201, 'reliability'), 'stale', 'un precio vencido gana a un heredado: desactualizado');
-- Una preparación con estimaciones pasa la marca al plato.
select is(pg_temp.cost(2, 201, 'reliability'), 'estimated', 'el plato hereda la confiabilidad de su preparación');

-- Variante: Demo Pastas Norte tiene su propia versión de la preparación, a la mitad de costo.
insert into recipes.recipes (id, group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id, variant_of_recipe_id)
values (pg_temp.u(97018), pg_temp.u(1), pg_temp.u(101), pg_temp.u(202), 'restaurant', 'COSTO-REC-18', 'Variante', 'preparation',
        pg_temp.u(1061), pg_temp.u(97001));
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id)
values (pg_temp.u(98018), pg_temp.u(1), pg_temp.u(97018), 1, 1000, (select id from catalog.units where code = 'g'));
select pg_temp.line(18, 1, 1, 500, 'g');
select pg_temp.publish(18);
select pg_temp.assign(2, 202);
select is(pg_temp.cost(2, 202), '300.0000', 'en el local con variante, el plato usa la variante: 2 $/g × 150 g');
select is(pg_temp.cost(2, 201), '600.0000', 'en el otro, la maestra');

-- La planilla a mano de las recetas DEMO (docs/guias/costos-demo.md, compuerta de la etapa 2.3).
create function pg_temp.demo(p_code text, p_rest int, p_column text default 'total_cost') returns text language plpgsql as $$
declare
  v text;
begin
  execute format('select c.%I::text from costing.recipe_cost_current c join recipes.recipes r on r.id = c.recipe_id
                   where r.code = $1 and c.restaurant_id = $2 and c.deleted_at is null', p_column)
    into v using p_code, pg_temp.u(p_rest);
  return v;
end
$$;
select is(pg_temp.demo('DEMO-PAR-02', 203, 'total_gross_cost'), '7045.0000', 'planilla: Vacío a la parrilla, con IVA');
select is(pg_temp.demo('DEMO-PAR-02', 203), '5822.3140', 'planilla: Vacío a la parrilla, sin IVA');
select is(pg_temp.demo('DEMO-SAL-02', 201, 'total_gross_cost'), '73695.0000', 'planilla: Salsa bolognesa, con IVA');
select is(pg_temp.demo('DEMO-PAS-03', 201, 'total_gross_cost'), '5452.5833', 'planilla: Ravioles con la bolognesa adentro, con IVA');
select is(pg_temp.demo('DEMO-PAS-04', 201, 'cost_per_portion'), '365.3581', 'planilla: Ñoquis por porción, sin IVA');
select is(pg_temp.demo('DEMO-PAS-05', 201), null, 'planilla: la Lasaña queda incompleta (la harina 0000 no tiene precio)');

select * from finish();
rollback;
