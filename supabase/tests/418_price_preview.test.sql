-- Vista previa de un precio (ADR-0067): da exactamente lo que después guarda la solicitud, con los mismos controles, sin
-- escribir nada y solo para quien propone y ve precios en ese lugar. Y el código automático del producto de compra.
-- Personas del seed: ...0407 controller, ...0408 compras, ...0405 chef, ...0404 gerente, ...0402 Dirección.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(67);

create function pg_temp.q(p_user uuid, p_sql text, p_aal text default 'aal2')
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, true);
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
create function pg_temp.today_ar() returns date language sql as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date
$$;
grant execute on function pg_temp.u(int), pg_temp.today_ar() to authenticated;

-- Dos materias primas: una en gramos con su historia, y otra en ml que se compra por kg sin densidad (no convierte).
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id) values
  (pg_temp.u(9961), pg_temp.u(1), 'PRUEBA-VP-1', 'Materia prima con vista previa', pg_temp.u(707), (select id from catalog.units where code = 'g')),
  (pg_temp.u(9962), pg_temp.u(1), 'PRUEBA-VP-2', 'Materia prima que no convierte', pg_temp.u(707), (select id from catalog.units where code = 'ml'));
-- La base no deja crear un producto que no convierte; acá, como si la densidad se hubiera quitado después.
alter table catalog.purchase_products disable trigger validate_product_content;
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
values (pg_temp.u(9963), pg_temp.u(1), 'PRUEBA-VP-PROD', pg_temp.u(9961), 'Bolsa de 2 kg', (select id from catalog.units where code = 'bag'), 2, 1000,
        (select id from catalog.units where code = 'g')),
       (pg_temp.u(9964), pg_temp.u(1), 'PRUEBA-VP-NOC', pg_temp.u(9962), 'Por kg', (select id from catalog.units where code = 'kg'), 1, 1,
        (select id from catalog.units where code = 'kg'));
alter table catalog.purchase_products enable trigger validate_product_content;
create function pg_temp.price(p_price numeric, p_days_ago int, p_scope text default 'group', p_brand uuid default null, p_rest uuid default null) returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, restaurant_id, valid_from, package_price, document_type, source)
  values (pg_temp.u(1), pg_temp.u(9963), p_scope::core.scope_type, p_brand, p_rest, pg_temp.today_ar() - p_days_ago, p_price, 'no_invoice', 'test_value')
$$;
-- Los mismos datos para las dos funciones.
create function pg_temp.args(p_price numeric, p_doc text, p_vat numeric, p_incl boolean, p_disc numeric, p_scope text, p_brand uuid, p_rest uuid,
                             p_prod int, p_from date) returns text language sql as $$
  select format('%L, %L, %L, %L, %L, %L::numeric, %L, %L::numeric, %L::boolean, %L::numeric, null, ''manual''',
                pg_temp.u(p_prod), p_scope, p_brand, p_rest, p_from, p_price, p_doc, p_vat, p_incl, p_disc)
$$;
create function pg_temp.preview(p_price numeric, p_doc text default 'no_invoice', p_vat numeric default null, p_incl boolean default true,
                                p_disc numeric default 0, p_scope text default 'group', p_brand uuid default null, p_rest uuid default null,
                                p_prod int default 9963, p_user int default 408, p_from date default null, p_aal text default 'aal2') returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), 'select costing.preview_price(' || pg_temp.args(p_price, p_doc, p_vat, p_incl, p_disc, p_scope, p_brand, p_rest, p_prod,
    coalesce(p_from, pg_temp.today_ar())) || ')::text', p_aal)
$$;
create function pg_temp.propose(p_price numeric, p_doc text default 'no_invoice', p_vat numeric default null, p_incl boolean default true,
                                p_disc numeric default 0, p_scope text default 'group', p_brand uuid default null, p_rest uuid default null) returns text language sql as $$
  select pg_temp.q(pg_temp.u(408), 'select costing.propose_price(' || pg_temp.args(p_price, p_doc, p_vat, p_incl, p_disc, p_scope, p_brand, p_rest, 9963, pg_temp.today_ar())
    || ', null, ''Prueba'')::text')
$$;
-- La vista previa y, después, lo guardado: tienen que ser iguales. Se rechaza para seguir con la próxima.
create function pg_temp.same(p_price numeric, p_doc text default 'no_invoice', p_vat numeric default null, p_incl boolean default true,
                             p_disc numeric default 0, p_scope text default 'group', p_brand uuid default null, p_rest uuid default null) returns boolean language plpgsql as $$
declare
  v_preview jsonb := pg_temp.preview(p_price, p_doc, p_vat, p_incl, p_disc, p_scope, p_brand, p_rest)::jsonb;
  v_id      uuid  := pg_temp.propose(p_price, p_doc, p_vat, p_incl, p_disc, p_scope, p_brand, p_rest)::uuid;
  v_c       jsonb;
  v_same    boolean;
begin
  select proposed_changes into v_c from workflow.approval_requests where id = v_id;
  v_same := jsonb_build_array(v_preview -> 'net_package_price', v_preview -> 'gross_package_price', v_preview -> 'net_unit_cost',
                              v_preview -> 'gross_unit_cost', v_preview -> 'variation', v_preview -> 'variation_today',
                              v_preview -> 'variation_lookback', v_preview -> 'lookback_days', v_preview -> 'first')
          = jsonb_build_array(v_c -> 'net_package_price', v_c -> 'gross_package_price', v_c -> 'net_unit_cost', v_c -> 'gross_unit_cost',
                              v_c -> 'price_variation_pct', v_c -> 'price_variation_today_pct', v_c -> 'price_variation_lookback_pct',
                              v_c -> 'lookback_days', to_jsonb(v_c ->> 'reference_price_record_id' is null));
  perform pg_temp.q(pg_temp.u(407), format('select workflow.decide_approval(%L, ''rejected'', ''Prueba'') ->> ''result''', v_id));
  return v_same;
end
$$;

-- ---------------------------------------------------------------------------
-- Lo mismo que guarda la propuesta
-- ---------------------------------------------------------------------------
select ok(pg_temp.same(2000), 'el primer precio');
select is(pg_temp.preview(2000)::jsonb ->> 'first', 'true', 'dice que es el primero');
select is(pg_temp.preview(2000)::jsonb -> 'variation', 'null'::jsonb, 'sin variación');
select is(pg_temp.preview(2000)::jsonb ->> 'direction', 'false', 'y alcanza con el Controller');
select is((pg_temp.preview(2000)::jsonb ->> 'net_unit_cost')::numeric, 1::numeric, 'por gramo: 2.000 de 2 × 1.000 g');
select is(pg_temp.preview(2000)::jsonb ->> 'base_unit', 'g', 'en la unidad de uso');
select pg_temp.price(2000, 10);
select ok(pg_temp.same(2200), 'una suba');
select is((pg_temp.preview(2200)::jsonb ->> 'variation')::numeric, 10::numeric, 'de 10 %');
select is(pg_temp.preview(2200)::jsonb ->> 'direction', 'false', 'que aprueba el Controller');
select ok(pg_temp.same(1800), 'una baja');
select is((pg_temp.preview(1800)::jsonb ->> 'variation')::numeric, -10::numeric, 'de 10 %');
select ok(pg_temp.same(3000), 'una suba grande');
select is(pg_temp.preview(3000)::jsonb ->> 'direction', 'true', 'que aprueba también Dirección');
select is(pg_temp.preview(1000)::jsonb ->> 'direction', 'true', 'una baja grande, también');
select is(pg_temp.preview(2300)::jsonb ->> 'direction', 'false', 'justo en el tope (15 %), no');
select is(pg_temp.preview(2301)::jsonb ->> 'direction', 'true', 'apenas pasado (15,05 %), sí');
select ok(pg_temp.same(2420, 'invoice', 21, true), 'con factura e IVA incluido');
select ok(pg_temp.same(2000, 'invoice', 10.5, false), 'con factura e IVA aparte');
select ok(pg_temp.same(2500, 'invoice', 0, true), 'con alícuota 0');
select ok(pg_temp.same(2500, 'no_invoice', null, true, 300), 'con descuento');
select ok(pg_temp.same(2100, 'no_invoice', null, true, 0, 'brand', pg_temp.u(101)), 'para una marca');
select ok(pg_temp.same(2100, 'no_invoice', null, true, 0, 'restaurant', null, pg_temp.u(201)), 'para un local');
-- Escalones: contra hoy sube 12 %, contra hace 30 días, más.
select pg_temp.price(1500, 40);
select pg_temp.price(1900, 5);
select ok(pg_temp.same(2100), 'subas en escalones');
select ok(abs((pg_temp.preview(2100)::jsonb ->> 'variation_lookback')::numeric) > abs((pg_temp.preview(2100)::jsonb ->> 'variation_today')::numeric),
  'la de hace 30 días es más grande que la de hoy');
select is(pg_temp.preview(2100)::jsonb -> 'variation', pg_temp.preview(2100)::jsonb -> 'variation_lookback', 'y es la que vale');
-- Que el Controller decida lo mismo que anunció: una que dice Dirección, va a Dirección.
create temporary table sent as select pg_temp.propose(3000) as id;
select is(pg_temp.q(pg_temp.u(407), format('select workflow.decide_approval(%L, ''approved'', ''Prueba'') ->> ''result''', (select id from sent))), 'approved', 'el Controller aprueba');
select ok(exists (select 1 from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
                   where w.code = 'costing.approve_price_direction' and r.proposed_changes ->> 'first_request_id' = (select id from sent)), 'y pasa a Dirección, como decía');

-- Y una que dice solo Controller, alcanza con el Controller.
create temporary table small as select pg_temp.propose(2150, 'no_invoice', null, true, 0, 'restaurant', null, pg_temp.u(204)) as id;
select is(pg_temp.preview(2150, p_scope => 'restaurant', p_rest => pg_temp.u(202))::jsonb ->> 'direction',
  (select (abs((proposed_changes ->> 'price_variation_pct')::numeric) > 15)::text from workflow.approval_requests where id::text = (select id from small)),
  'lo que anuncia es lo que dice la solicitud');
insert into costing.price_settings (group_id) select pg_temp.u(1) where not exists (select 1 from costing.price_settings where group_id = pg_temp.u(1) and deleted_at is null);
update costing.price_settings set approval_variation_pct = 100 where group_id = pg_temp.u(1);
select is(pg_temp.preview(2150, p_scope => 'restaurant', p_rest => pg_temp.u(202))::jsonb ->> 'direction', 'false', 'con otro tope, alcanza con el Controller');
select is(pg_temp.q(pg_temp.u(407), format('select workflow.decide_approval(%L, ''approved'', ''Prueba'') ->> ''result''', (select id from small))), 'approved', 'lo aprueba');
select ok(exists (select 1 from costing.price_records where approval_request_id::text = (select id from small)), 'y el precio queda cargado');
update costing.price_settings set approval_variation_pct = 15 where group_id = pg_temp.u(1);

-- ---------------------------------------------------------------------------
-- Los mismos controles
-- ---------------------------------------------------------------------------
select matches(pg_temp.preview(3000), 'Ya hay un precio pendiente', 'avisa que ya hay uno pendiente');
select matches(pg_temp.preview(2000, p_from => pg_temp.today_ar() - 20), 'no puede empezar antes', 'o que empieza antes que el vigente');
select matches(pg_temp.preview(0), 'mayor que cero', 'el precio, mayor que cero');
select matches(pg_temp.preview('NaN'), 'tienen que ser números', 'NaN no es un precio');
select matches(pg_temp.propose('NaN'), 'tienen que ser números', 'tampoco al proponer');
select matches(pg_temp.preview('Infinity'), 'tienen que ser números', 'ni infinito');
select matches(pg_temp.preview(100, p_disc => 'NaN'), 'tienen que ser números', 'ni un descuento');
select throws_ok($$ select pg_temp.price('NaN', 1) $$, '23514', null, 'la tabla tampoco lo acepta');
select matches(pg_temp.preview(100, p_disc => 100), 'menor que el precio', 'el descuento, menor');
select matches(pg_temp.preview(100, 'invoice', null), 'elegí la alícuota', 'con factura, la alícuota');
select matches(pg_temp.preview(100, 'no_invoice', 21), 'sin factura no lleva IVA', 'sin factura, no');
select matches(pg_temp.preview(100, p_prod => 9964), 'cargá primero su conversión', 'dice si falta la conversión');
select matches(pg_temp.preview(100, p_scope => 'otro'), 'Elegí para quién vale', 'el lugar');
select matches(pg_temp.preview(100, p_scope => 'brand'), '^ERROR', 'una marca, con su marca');

-- ---------------------------------------------------------------------------
-- Quién la ve, y que no escriba
-- ---------------------------------------------------------------------------
select matches(pg_temp.preview(2000, p_user => 407), '^ERROR 42501', 'el Controller ve precios pero no propone');
select matches(pg_temp.preview(2000, p_user => 405), '^ERROR 42501', 'la Chef, ni una cosa ni la otra');
select matches(pg_temp.preview(2000, p_user => 404, p_scope => 'restaurant', p_rest => pg_temp.u(201)), '^ERROR 42501', 'el Gerente no propone');
select matches(pg_temp.preview(2000, p_aal => 'aal1'), '^ERROR 42501', 'Compras sin segundo factor, no');
select matches(pg_temp.q(pg_temp.u(408), 'select costing.preview_price(' || pg_temp.args(2000, 'no_invoice', null, true, 0, 'group', null, null, 1, pg_temp.today_ar()) || ')::text'),
  '^ERROR 42501', 'un producto que no existe, sin revelarlo');
-- Proponer sin ver precios: se propone, pero no se ve cómo queda (mostraría la variación contra el vigente).
create temporary table took as
  select rp.id from core.role_permissions rp join core.roles r on r.id = rp.role_id join core.permissions p on p.id = rp.permission_id
   where r.code = 'purchasing' and p.code = 'prices.view' and rp.deleted_at is null;
select core.set_change_context('Prueba: Compras sin ver precios', 'manual');
update core.role_permissions set deleted_at = now() where id in (select id from took);
select matches(pg_temp.preview(2000), '^ERROR 42501', 'quien propone y no ve precios, no la ve');
select matches(pg_temp.propose(2500, 'no_invoice', null, true, 0, 'brand', pg_temp.u(102)), '^[0-9a-f-]{36}$', 'aunque puede proponer');
update core.role_permissions set deleted_at = null where id in (select id from took);
select matches(pg_temp.preview(2000, p_scope => 'restaurant', p_rest => pg_temp.u(202), p_brand => pg_temp.u(101)), '^ERROR 22023', 'un local con otra marca, no');
select matches(pg_temp.preview(2000, p_scope => 'restaurant', p_rest => gen_random_uuid()), '^ERROR', 'un local que no existe, no');
select ok(not has_function_privilege('anon', 'costing.preview_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text)', 'execute'), 'anon no');
select ok(not has_function_privilege('authenticated', 'costing.price_proposal_amounts(catalog.purchase_products, core.scope_type, uuid, uuid, date, numeric, numeric, costing.price_document, numeric, boolean)', 'execute')
          and not has_function_privilege('authenticated', 'catalog.next_product_code(uuid)', 'execute'), 'las internas no se llaman desde la API');
select is((select provolatile from pg_proc where oid = 'costing.preview_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text)'::regprocedure), 's',
  'es de solo lectura: la base no la deja escribir');

-- ---------------------------------------------------------------------------
-- Código automático del producto de compra
-- ---------------------------------------------------------------------------
create function pg_temp.code_of(p_code text) returns text language plpgsql as $$
declare
  v_id uuid := pg_temp.q(pg_temp.u(408), format($f$select catalog.create_purchase_product(%L, %L, 'Producto de prueba', 'bag', 1, 1000, 'g', '{}', 'Prueba')::text$f$, pg_temp.u(9961), p_code))::uuid;
begin
  return (select code from catalog.purchase_products where id = v_id);
end
$$;
select is(pg_temp.code_of(null), 'PRUEBA-VP-1-P01', 'sin código, el de la materia prima y -P01');
select is(pg_temp.code_of('  '), 'PRUEBA-VP-1-P02', 'vacío, el siguiente');
select is(pg_temp.code_of('PRUEBA-VP-1-P03'), 'PRUEBA-VP-1-P03', 'a mano se sigue aceptando');
select is(pg_temp.code_of(null), 'PRUEBA-VP-1-P04', 'y el automático se lo saltea');
update catalog.purchase_products set deleted_at = now() where code = 'PRUEBA-VP-1-P02';
select is(pg_temp.code_of(null), 'PRUEBA-VP-1-P05', 'nunca reutiliza el de uno borrado');
insert into catalog.purchase_products (group_id, code, ingredient_id, description, package_unit_id, units_per_package, content_per_unit, content_unit_id)
select pg_temp.u(1), 'PRUEBA-VP-1-P' || lpad(n::text, 2, '0'), pg_temp.u(9961), 'Relleno', (select id from catalog.units where code = 'bag'), 1, 1000,
       (select id from catalog.units where code = 'g') from generate_series(6, 99) n;
select is(pg_temp.code_of(null), 'PRUEBA-VP-1-P100', 'después del 99, el 100');

-- Códigos largos: dos materias primas que empiezan igual comparten la serie, sin pasar los 30 caracteres.
insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id) values
  (pg_temp.u(9971), pg_temp.u(1), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ-001', 'Código largo 1', pg_temp.u(707), (select id from catalog.units where code = 'g')),
  (pg_temp.u(9972), pg_temp.u(1), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ-002', 'Código largo 2', pg_temp.u(707), (select id from catalog.units where code = 'g'));
create function pg_temp.long_code(p_ing int) returns text language plpgsql as $$
declare
  v_id uuid := pg_temp.q(pg_temp.u(408), format($f$select catalog.create_purchase_product(%L, null, 'Producto largo', 'bag', 1, 1000, 'g', '{}', 'Prueba')::text$f$, pg_temp.u(p_ing)))::uuid;
begin
  return (select code from catalog.purchase_products where id = v_id);
end
$$;
select is(pg_temp.long_code(9971), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ-P01', 'un código largo se recorta');
select is(pg_temp.long_code(9972), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ-P02', 'y el de otra que empieza igual no choca');
-- Al resolver un artículo, la misma función (antes, al llegar a 100, no terminaba).
select is(pg_temp.q(pg_temp.u(405), format($f$select purchasing.resolve_article(%L, %L, 'bag', 1, 5000, 'g', '{}', 'Es de prueba') ->> 'code'$f$, pg_temp.u(1311), pg_temp.u(9961))),
  'PRUEBA-VP-1-P101', 'resolver un artículo sigue la serie, también pasado el 100');
select ok(length((select max(code) from catalog.purchase_products where ingredient_id = pg_temp.u(9961))) <= 30, 'sin pasar los 30 caracteres');

select * from finish();
rollback;
