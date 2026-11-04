-- Fase 2 · Etapa 2.1 C: precios (ADR-0029). Casos 1, 2, 16, 17, 20 y 21 del documento de Soy con la
-- función de una línea (la misma que va a usar el motor de la 2.3), qué precio vale (local → marca →
-- grupo, el último aprobado), IVA según la razón social, desactualizado, y el flujo de aprobación:
-- Compras propone, el Controller aprueba y, si la variación supera el % del grupo, aprueba también
-- Dirección General.
-- Personas del seed: ...0402 y ...0412 Dirección, ...0404 gerente (local ...201), ...0405 chef (marca ...101),
-- ...0407 controller, ...0408 compras. Locales: ...201 y ...202 (Pastas), ...203 (Parrilla), ...204 (Café,
-- monotributo).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(72);

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
create function pg_temp.unit(p_code text) returns uuid language sql as $$ select id from catalog.units where code = p_code $$;
create function pg_temp.today_ar() returns date language sql as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date
$$;
grant execute on function pg_temp.u(int), pg_temp.unit(text), pg_temp.today_ar() to authenticated;

-- Materias primas de prueba (todas en gramos, compradas por kg) con ids ...0099NN y sus productos ...0098NN.
create function pg_temp.ingredient(p_n int, p_unit text default 'g') returns uuid language plpgsql as $$
begin
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values (pg_temp.u(9900 + p_n), pg_temp.u(1), 'PRUEBA-PRE-' || p_n, 'Materia prima de prueba ' || p_n, pg_temp.u(707),
          pg_temp.unit(p_unit));
  insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                         content_per_unit, content_unit_id)
  values (pg_temp.u(9800 + p_n), pg_temp.u(1), 'PRUEBA-PROD-' || p_n, pg_temp.u(9900 + p_n), 'Producto de prueba ' || p_n,
          pg_temp.unit('kg'), 1, 1000, pg_temp.unit('g'));
  return pg_temp.u(9900 + p_n);
end
$$;
-- Un precio aprobado cargado directo (como el seed), de grupo salvo que se diga otra cosa.
create function pg_temp.price(p_n int, p_price numeric, p_days_ago int, p_doc text default 'no_invoice',
                              p_scope text default 'group', p_brand int default null, p_restaurant int default null,
                              p_product uuid default null) returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, restaurant_id, valid_from,
                                     package_price, document_type, vat_rate, source)
  values (pg_temp.u(1), coalesce(p_product, pg_temp.u(9800 + p_n)), p_scope::core.scope_type,
          case when p_brand is not null then pg_temp.u(p_brand) end,
          case when p_restaurant is not null then pg_temp.u(p_restaurant) end,
          pg_temp.today_ar() - p_days_ago, p_price, p_doc::costing.price_document,
          case when p_doc = 'invoice' then 21 end, 'test_value')
$$;
create function pg_temp.line(p_user int, p_n int, p_qty numeric, p_unit text, p_restaurant int default 201,
                             p_basis text default 'purchase', p_process uuid default null) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    $f$select coalesce(round(line_cost, 2)::text, '-') || ' ' || status
         from costing.ingredient_line_cost(%L, %L, %s, %L, %L, %L)$f$,
    pg_temp.u(9900 + p_n), pg_temp.u(p_restaurant), p_qty, pg_temp.unit(p_unit), p_basis, p_process))
$$;
create function pg_temp.resolve(p_user int, p_n int, p_restaurant int, p_what text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select (%s)::text from costing.resolve_price(%L, %L)', p_what,
                                             pg_temp.u(9900 + p_n), pg_temp.u(p_restaurant)))
$$;

-- ---------------------------------------------------------------------------
-- Casos del documento de Soy (con la función de una línea)
-- ---------------------------------------------------------------------------
select pg_temp.ingredient(1);
select pg_temp.price(1, 8000, 1);
select is(pg_temp.line(407, 1, 120, 'g'), '960.00 ok', 'caso 1: 8.000 $/kg son 8 $/g; 120 g cuestan $ 960,00');

select pg_temp.ingredient(2);
select pg_temp.price(2, 5000, 1);
insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, status,
                                               approved_by, approved_at)
values (pg_temp.u(1), pg_temp.u(9902), pg_temp.u(962), 0.80, 1, 'approved', pg_temp.u(413), now());
select is(pg_temp.line(407, 2, 800, 'g', 201, 'clean', pg_temp.u(962)), '5000.00 ok',
  'caso 2: 800 g limpios con 80 % de rendimiento son 1.000 g comprados: $ 5.000,00');
select is(pg_temp.line(407, 2, 800, 'g', 201, 'clean', null), '- missing_yield',
  'limpia sin un rendimiento estándar: incompleto, nunca supone 100 %');

select pg_temp.ingredient(3);
insert into catalog.ingredient_unit_conversions (group_id, ingredient_id, kind, factor, source, measured_on, measured_by)
values (pg_temp.u(1), pg_temp.u(9903), 'density', 0.92, 'measured', pg_temp.today_ar(), 'Prueba');
select pg_temp.price(3, 10000, 1);
select is(pg_temp.line(407, 3, 100, 'ml', 201), '920.00 ok', 'caso 16: 100 ml con densidad 0,92 son 92 g a 10 $/g: $ 920,00');

select pg_temp.ingredient(4);
select pg_temp.price(4, 10000, 1);
select is(pg_temp.line(407, 4, 100, 'ml', 201), '- missing_conversion', 'caso 17: ml sin densidad, incompleto (nunca $ 0)');

-- Caso 20: factura de 12.100 con 21 % incluido = 10.000 netos por kg.
select pg_temp.ingredient(5);
select pg_temp.price(5, 12100, 1, 'invoice');
select is(pg_temp.resolve(407, 5, 201, 'round(net_unit_cost * 1000, 2)'), '10000.00', 'caso 20: 12.100 / 1,21 = $ 10.000,00 por kg neto');
select is(pg_temp.resolve(407, 5, 201, 'round(unit_cost * 1000, 2) || '' '' || round(gross_unit_cost * 1000, 2)'), '10000.00 12100.00',
  'un responsable inscripto costea sin IVA, y se ven las dos cifras');
select is(pg_temp.resolve(407, 5, 204, 'round(unit_cost * 1000, 2)'), '12100.00', 'un monotributista no recupera el IVA: costea con IVA');
update org.restaurants set legal_entity_id = null where id = pg_temp.u(202);
select is(pg_temp.resolve(407, 5, 202, 'coalesce(unit_cost::text, ''-'') || '' '' || round(gross_unit_cost * 1000, 2) || '' '' || status'),
  '- 12100.00 missing_legal_entity', 'un local sin razón social: el costo queda incompleto, el precio con IVA se ve igual');
select is(pg_temp.line(407, 5, 100, 'g', 202), '- missing_legal_entity', 'y la línea también queda incompleta');
select is(pg_temp.resolve(407, 1, 202, 'status'), 'ok', 'un precio sin factura no depende de la razón social');

-- Caso 21: local → marca → grupo.
select pg_temp.ingredient(6);
select pg_temp.price(6, 1000, 3);
select pg_temp.price(6, 2000, 3, 'no_invoice', 'brand', 101);
select is(pg_temp.resolve(404, 6, 201, 'price_level || '' '' || inherited || '' '' || round(unit_cost * 1000, 2)'), 'brand true 2000.00',
  'caso 21: el local sin precio propio usa el de su marca, marcado como heredado');
select is(pg_temp.resolve(407, 6, 203, 'price_level || '' '' || round(unit_cost * 1000, 2)'), 'group 1000.00',
  'otra marca, sin precio de marca, usa el del grupo');
select pg_temp.price(6, 3000, 3, 'no_invoice', 'restaurant', null, 201);
select is(pg_temp.resolve(404, 6, 201, 'price_level || '' '' || inherited || '' '' || round(unit_cost * 1000, 2)'), 'restaurant false 3000.00',
  'con precio propio, el local usa el suyo');

-- Varios productos con precio: el último aprobado (decisión 1 de Joaco).
select pg_temp.ingredient(7);
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
values (pg_temp.u(9871), pg_temp.u(1), 'PRUEBA-PROD-7B', pg_temp.u(9907), 'Producto de prueba 7, otra marca',
        pg_temp.unit('kg'), 1, 1000, pg_temp.unit('g'));
select pg_temp.price(7, 4000, 2);
select pg_temp.price(7, 4500, 9, 'no_invoice', 'group', null, null, pg_temp.u(9871));
select is(pg_temp.resolve(407, 7, 201, 'product_description || '' '' || round(unit_cost * 1000, 2)'), 'Producto de prueba 7 4000.00',
  'con dos productos con precio, vale el último aprobado, y dice de qué producto viene');

-- Sin precio: incompleto, nunca $ 0.
select pg_temp.ingredient(8);
select is(pg_temp.line(407, 8, 100, 'g'), '- missing_price', 'falta precio: incompleto, nunca $ 0');

-- Desactualizado: 30 días del grupo, salvo que la categoría diga otro plazo.
select pg_temp.ingredient(9);
select pg_temp.price(9, 1000, 40);
select is(pg_temp.resolve(407, 9, 201, 'stale'), 'true', 'un precio de hace 40 días está desactualizado (plazo del grupo: 30)');
update catalog.ingredient_categories set stale_price_days = 60 where id = pg_temp.u(707);
select is(pg_temp.resolve(407, 9, 201, 'stale'), 'false', 'con 60 días en su categoría, todavía no');
update catalog.ingredient_categories set stale_price_days = null where id = pg_temp.u(707);

-- Quién ve.
select is(pg_temp.msg(pg_temp.u(405), format('select * from costing.resolve_price(%L, %L)', pg_temp.u(9901), pg_temp.u(201))),
  'No tenés permiso para ver precios de este local.', 'el Chef no ve precios');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.resolve_price(%L, %L)', pg_temp.u(9901), pg_temp.u(203))),
  'ERROR 42501', 'el Gerente no ve los precios de otro local');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.ingredient_line_cost(%L, %L, 1, %L)',
                                           pg_temp.u(9901), pg_temp.u(201), pg_temp.unit('g'))), '1',
  'el Gerente sí los de su local');

-- ---------------------------------------------------------------------------
-- Proponer y aprobar
-- ---------------------------------------------------------------------------
create function pg_temp.propose(p_user int, p_n int, p_price numeric, p_days_ago int, p_scope text default 'group',
                                p_brand int default null, p_doc text default 'no_invoice', p_vat numeric default null,
                                p_restaurant int default null)
returns text language plpgsql as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(p_user), 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute format($f$select costing.propose_price(%L, %L, %L, %L, %L, %s, %L, %L, true, 0, null, 'manual', null, 'Precio de prueba')::text$f$,
                   pg_temp.u(9800 + p_n), p_scope, case when p_brand is not null then pg_temp.u(p_brand) end,
                   case when p_restaurant is not null then pg_temp.u(p_restaurant) end,
                   pg_temp.today_ar() - p_days_ago, p_price, p_doc, p_vat) into v;
  exception when others then
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.decide(p_user int, p_request text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''', p_request))
$$;
create function pg_temp.current_price(p_n int) returns numeric language sql as $$
  select package_price from costing.price_records where purchase_product_id = pg_temp.u(9800 + p_n) and scope_type = 'group'
   order by valid_from desc, entry_number desc limit 1
$$;
create function pg_temp.direction_request(p_first text) returns text language sql as $$
  select r.id::text from workflow.approval_requests r join workflow.approval_workflows w on w.id = r.workflow_id
   where w.code = 'costing.approve_price_direction' and r.proposed_changes ->> 'first_request_id' = p_first
$$;
create temporary table reqs (k text primary key, id text);

-- Variación chica (8.000 → 8.400, 5 %): Compras propone y el Controller aprueba.
insert into reqs values ('chica', pg_temp.propose(408, 1, 8400, 0));
select ok((select id from reqs where k = 'chica') ~ '^[0-9a-f-]{36}$', 'Compras propone un precio');
select is((select (proposed_changes ->> 'price_variation_pct') from workflow.approval_requests where id::text = (select id from reqs where k = 'chica')),
  '5.00', 'la solicitud trae la variación contra el precio vigente');
select is(pg_temp.decide(408, (select id from reqs where k = 'chica')), 'denied', 'Compras no aprueba lo propio');
select is(pg_temp.decide(405, (select id from reqs where k = 'chica')), 'denied', 'el Chef tampoco: no tiene prices.approve');
select is(pg_temp.decide(402, (select id from reqs where k = 'chica')), 'denied',
  'el primer paso lo da solo el Controller, no Dirección (decisión de Joaco)');
-- La bandeja: los importes de un precio, solo para quien ve precios (el Chef ve la solicitud, no el precio).
select is(pg_temp.q(pg_temp.u(413), format('select proposed_changes ->> ''net_package_price'' from workflow.inbox(true, 100) where id = %L',
                                           (select id from reqs where k = 'chica'))),
  '[oculto]', 'el Chef del grupo (ve costos, no precios) ve la solicitud en la bandeja, con el precio oculto');
select is(pg_temp.q(pg_temp.u(407), format('select proposed_changes ->> ''net_package_price'' from workflow.inbox(true, 100) where id = %L',
                                           (select id from reqs where k = 'chica'))),
  '8400', 'el Controller ve el precio');
select is(pg_temp.q(pg_temp.u(408), format('select proposed_changes ->> ''net_package_price'' from workflow.inbox(true, 100) where id = %L',
                                           (select id from reqs where k = 'chica'))),
  '8400', 'Compras ve el precio que propuso');
select is(pg_temp.q(pg_temp.u(405), 'select count(proposed_changes)::text from workflow.approval_requests'), 'ERROR 42501',
  'nadie lee lo propuesto directo de la tabla: sale solo por la bandeja');
select is(pg_temp.decide(407, (select id from reqs where k = 'chica')), 'approved', 'el Controller la aprueba');
select is(pg_temp.current_price(1), 8400.0000, 'y el precio nuevo queda vigente');
select is((select approved_by from costing.price_records where approval_request_id::text = (select id from reqs where k = 'chica')),
  pg_temp.u(407), 'con quién lo aprobó');

select ok(pg_temp.propose(405, 1, 9000, 0) like 'ERROR No tenés permiso para proponer precios%', 'el Chef no propone precios');
select is(pg_temp.propose(408, 1, 9000, 0, 'group', null, 'invoice', null),
  'ERROR Con factura, elegí la alícuota de IVA (0, 10,5, 21 o 27); sin factura no lleva IVA.', 'con factura, la alícuota es obligatoria');

-- Variación grande (8.400 → 12.000, 42,86 %): el Controller aprueba y pasa a Dirección.
insert into reqs values ('grande', pg_temp.propose(408, 1, 12000, 0));
select is(pg_temp.propose(408, 1, 12500, 0),
  'ERROR Ya hay un precio pendiente para ese producto, lugar y fecha: esperá a que se decida o pedí que lo retiren.',
  'una sola propuesta pendiente por producto, lugar y fecha');
select is(pg_temp.decide(407, (select id from reqs where k = 'grande')), 'approved', 'el Controller aprueba la suba grande');
select is(pg_temp.current_price(1), 8400.0000, 'pero el precio todavía no entra');
select ok(pg_temp.direction_request((select id from reqs where k = 'grande')) is not null, 'pasa a Dirección General');
select is(pg_temp.decide(407, pg_temp.direction_request((select id from reqs where k = 'grande'))), 'denied',
  'el Controller no aprueba el paso de Dirección');
select is(pg_temp.decide(408, pg_temp.direction_request((select id from reqs where k = 'grande'))), 'denied',
  'quien propuso tampoco');
select is(pg_temp.decide(402, pg_temp.direction_request((select id from reqs where k = 'grande'))), 'approved',
  'Dirección General lo aprueba');
select is(pg_temp.current_price(1), 12000.0000, 'y recién ahí entra el precio');
select ok(exists (select 1 from audit.audit_events where table_name = 'price_records' and action::text = 'insert'
                    and actor_user_id = pg_temp.u(402)),
  'el precio aprobado queda en la auditoría con quién lo aprobó');

-- Una baja grande también pasa a Dirección (se mide para los dos lados).
insert into reqs values ('baja', pg_temp.propose(408, 2, 2000, 0));
select is(pg_temp.decide(407, (select id from reqs where k = 'baja')), 'approved', 'el Controller aprueba una baja del 60 %');
select ok(pg_temp.direction_request((select id from reqs where k = 'baja')) is not null, 'una baja grande también pasa a Dirección');
select is(pg_temp.q(pg_temp.u(402), format('select workflow.decide_approval(%L, ''rejected'', ''Muy barato'') ->> ''result''',
                                           pg_temp.direction_request((select id from reqs where k = 'baja')))),
  'rejected', 'Dirección la rechaza');
select is(pg_temp.current_price(2), 5000.0000, 'y el precio no entra');

-- La variación es contra el costo que se usa hoy (decisión de Joaco): no se saltea con otra
-- presentación, con un local sin precio propio ni cambiando el comprobante.
insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                       content_per_unit, content_unit_id)
values (pg_temp.u(9881), pg_temp.u(1), 'PRUEBA-PROD-1B', pg_temp.u(9901), 'Producto de prueba 1, otra presentación',
        pg_temp.unit('kg'), 1, 1000, pg_temp.unit('g'));
insert into reqs values ('otra_presentacion', pg_temp.propose(408, 81, 30000, 0));
select is(pg_temp.decide(407, (select id from reqs where k = 'otra_presentacion')), 'approved', 'el Controller aprueba otra presentación al 250 %');
select ok(pg_temp.direction_request((select id from reqs where k = 'otra_presentacion')) is not null,
  'pasa a Dirección: se compara con el costo de la materia prima, no solo del mismo producto');
insert into reqs values ('local', pg_temp.propose(408, 1, 20000, 0, 'restaurant', null, 'no_invoice', null, 201));
select is(pg_temp.decide(407, (select id from reqs where k = 'local')), 'approved', 'un precio propio para un local que heredaba');
select ok(pg_temp.direction_request((select id from reqs where k = 'local')) is not null,
  'pasa a Dirección: se compara con el precio heredado');
insert into reqs values ('comprobante', pg_temp.propose(408, 9, 1270, 0, 'group', null, 'invoice', 27));
select is((select proposed_changes ->> 'price_variation_pct' from workflow.approval_requests
            where id::text = (select id from reqs where k = 'comprobante')),
  '27.00', 'pasar de sin factura a factura con 27 % incluido: el neto no cambia, el bruto sube 27 %');
select is(pg_temp.decide(407, (select id from reqs where k = 'comprobante')), 'approved', 'el Controller lo aprueba');
select ok(pg_temp.direction_request((select id from reqs where k = 'comprobante')) is not null, 'y pasa a Dirección');
-- Si el precio vigente cambia entre los dos pasos, Dirección no lo puede aplicar.
select pg_temp.price(1, 13000, 0);
select is(pg_temp.msg(pg_temp.u(402), format('select workflow.decide_approval(%L, ''approved'', null)',
                                            pg_temp.direction_request((select id from reqs where k = 'otra_presentacion')))),
  'La solicitud ya no se puede aplicar: el precio vigente cambió desde que se propuso; proponé de nuevo con el valor actual. Hay que pedirla de nuevo.',
  'si el precio cambió entre el Controller y Dirección, no se aplica');

-- Si Dirección sube el %, la misma variación ya no necesita su aprobación.
select is(pg_temp.msg(pg_temp.u(402), format('select costing.update_price_settings(%L, 70, 30, ''Más margen'')', pg_temp.u(1))),
  'sin error', 'Dirección cambia el % a 70');
insert into reqs values ('con70', pg_temp.propose(408, 3, 15000, 0));
select is(pg_temp.decide(407, (select id from reqs where k = 'con70')), 'approved', 'una suba del 50 % con el umbral en 70 %');
select ok(pg_temp.direction_request((select id from reqs where k = 'con70')) is null, 'ya no pasa a Dirección');

-- Si el precio vigente cambió entre la propuesta y la aprobación, no se aplica.
insert into reqs values ('vieja', pg_temp.propose(408, 4, 10500, 0));
select pg_temp.price(4, 10200, 0);
select is(pg_temp.msg(pg_temp.u(407), format('select workflow.decide_approval(%L, ''approved'', null)', (select id from reqs where k = 'vieja'))),
  'La solicitud ya no se puede aplicar: el precio vigente cambió desde que se propuso; proponé de nuevo con el valor actual. Hay que pedirla de nuevo.',
  'si el precio vigente cambió, la aprobación no se aplica');

-- Un precio de marca.
insert into reqs values ('marca', pg_temp.propose(408, 8, 3000, 0, 'brand', 101));
select is(pg_temp.decide(407, (select id from reqs where k = 'marca')), 'approved', 'Compras propone para una marca y el Controller aprueba');
select is(pg_temp.resolve(404, 8, 201, 'price_level || '' '' || round(unit_cost * 1000, 2)'), 'brand 3000.00',
  'el local de esa marca lo hereda');

-- El contenido del envase queda congelado en cada precio: cambiar el producto no mueve el costo
-- (decisión de Joaco; revisión de seguridad).
create temporary table before_change (unit_cost numeric);
insert into before_change
select pg_temp.resolve(407, 1, 203, 'unit_cost')::numeric;
update catalog.purchase_products set content_per_unit = 500 where id = pg_temp.u(9801);
select is(pg_temp.resolve(407, 1, 203, 'unit_cost')::numeric, (select unit_cost from before_change),
  'cambiar el contenido del producto no cambia el costo de un precio aprobado');
-- Un producto desactivado sigue siendo el último costo conocido: no deja la materia prima "sin precio".
update catalog.purchase_products set is_active = false where id = pg_temp.u(9801);
select is(pg_temp.resolve(407, 1, 203, 'unit_cost')::numeric, (select unit_cost from before_change),
  'desactivar el producto no cambia el costo');
insert into reqs values ('tras_desactivar', pg_temp.propose(408, 81, 40000, -1));
select is(pg_temp.decide(407, (select id from reqs where k = 'tras_desactivar')), 'approved',
  'otra presentación, con el producto anterior desactivado');
select ok(pg_temp.direction_request((select id from reqs where k = 'tras_desactivar')) is not null,
  'no es un "primer precio": se compara con el del producto desactivado y pasa a Dirección');

-- La historia no se reescribe: un precio no empieza antes que el último del mismo producto y lugar.
select ok(pg_temp.propose(408, 3, 15000, 30) like 'ERROR Un precio nuevo no puede empezar antes que el que vale hoy en ese lugar%',
  'un precio con fecha anterior al último del mismo producto y lugar se rechaza');
select ok(pg_temp.propose(408, 6, 2500, 5, 'restaurant', null, 'no_invoice', null, 202)
            like 'ERROR Un precio nuevo no puede empezar antes que el que vale hoy en ese lugar%',
  'tampoco un precio propio de local con fecha anterior al que hereda hoy (cambiaría su costo pasado)');

-- El contenido no cambia entre proponer y aprobar (revisión de seguridad, tercera pasada).
select pg_temp.ingredient(11);
select pg_temp.price(11, 1000, 1);
insert into reqs values ('contenido', pg_temp.propose(408, 11, 1050, 0));
update catalog.purchase_products set content_per_unit = 100 where id = pg_temp.u(9811);
select is(pg_temp.msg(pg_temp.u(407), format('select workflow.decide_approval(%L, ''approved'', null)', (select id from reqs where k = 'contenido'))),
  'La solicitud ya no se puede aplicar: el contenido del producto cambió desde que se propuso; proponé de nuevo. Hay que pedirla de nuevo.',
  'si el contenido del producto cambió entre proponer y aprobar, no se aplica');

-- Una materia prima con precios no cambia su unidad de uso, y su categoría la cambia quien configura precios.
select throws_ok(format('update catalog.ingredients set recipe_unit_id = %L where id = %L', pg_temp.unit('ml'), pg_temp.u(9901)),
  '23514', 'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).',
  'una materia prima con precios no cambia su unidad de uso');
select is(pg_temp.msg(pg_temp.u(408), format($$select catalog.update_ingredient(%L, '{"category_id": "%s"}', 'Otra categoría')$$,
                                            pg_temp.u(9901), pg_temp.u(708))),
  'Esta materia prima ya tiene precios: cambiar su categoría cambia cuándo un precio está desactualizado, y eso lo decide Dirección General.',
  'Compras no cambia la categoría de una materia prima con precios');

-- Un producto cuyo contenido no se pasa a la unidad de uso ni siquiera se puede cargar: lo frena el catálogo
-- (catalog.enforce_product_content, etapa 2.1 A). propose_price y el trigger de precios lo vuelven a controlar.

-- Un precio aprobado es un evento para otros sistemas, sin importes.
select ok(exists (select 1 from integration.integration_outbox o
                   where o.event_type = 'price.approved' and o.payload ? 'purchase_product_id'
                     and o.payload::text !~* '(price\"|amount|cost)'),
  'aprobar un precio registra el evento, sin importes');

select * from finish();
rollback;
