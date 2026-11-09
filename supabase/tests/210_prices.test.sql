-- Fase 2 · Etapa 2.1 C: precios (ADR-0029). Estructura, razones sociales, configuración del grupo,
-- precios solo de inserción con neto y bruto calculados por la base, quién ve qué precio y la auditoría.
-- Personas del seed: ...0401 superadmin, ...0402 Dirección, ...0403 directora de Demo Pastas (...101),
-- ...0404 gerente de ...201, ...0405 chef, ...0407 controller, ...0408 compras, ...0409 cocinera,
-- ...0410 auditor, ...0411 gerente de ...201 y ...202.
-- El seed trae 47 precios de grupo y 1 de la marca Demo Pastas.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(49);

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
grant execute on function pg_temp.u(int) to authenticated;
create function pg_temp.prices_seen(p_user int) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), 'select count(*)::text from costing.price_records')
$$;
create function pg_temp.product(p_code text) returns uuid language sql as $$
  select id from catalog.purchase_products where code = p_code
$$;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('org', 'legal_entities', 'existe org.legal_entities');
select has_table('costing', 'price_records', 'existe costing.price_records');
select has_table('costing', 'price_settings', 'existe costing.price_settings');
select is((select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where (n.nspname, c.relname) in (('org', 'legal_entities'), ('costing', 'price_records'), ('costing', 'price_settings'))),
  true, 'las tres tablas tienen RLS');
select has_column('org', 'restaurants', 'legal_entity_id', 'cada local puede tener su razón social');
select is((select string_agg(code || ':' || required_permission || ':' || coalesce(array_to_string(approver_role_codes, ','), '-')
                             || ':' || apply_function::text, ' ' order by code)
             from workflow.approval_workflows where code like 'costing.%'),
  'costing.approve_price:prices.approve:controller:costing.apply_price(uuid) costing.approve_price_direction:prices.approve:general_management:costing.apply_price_direction(uuid)',
  'dos tipos de aprobación: el del Controller y el de Dirección General');
select is((select string_agg(r.code, ',' order by r.code) from core.role_permissions rp
             join core.roles r on r.id = rp.role_id join core.permissions p on p.id = rp.permission_id
            where p.code = 'prices.configure' and rp.deleted_at is null),
  'general_management', 'solo Dirección General configura los precios');
select ok((select count(*) = 2 from core.role_permissions rp join core.roles r on r.id = rp.role_id
             join core.permissions p on p.id = rp.permission_id
            where r.code = 'restaurant_manager' and p.code in ('prices.view', 'recipes.view_costs') and rp.deleted_at is null),
  'el Gerente ve precios y costos (respuesta 7 de Soy)');

-- ---------------------------------------------------------------------------
-- Razones sociales
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(403), format($$select org.create_legal_entity(%L, 'Otra S.A.', '30-11111111-1', 'registered', 'Prueba')$$, pg_temp.u(1))),
  'No tenés permiso para crear razones sociales en este grupo.', 'la Directora de una marca no crea razones sociales del grupo');
create temporary table le (id uuid);
grant select, insert on le to authenticated;
insert into le select pg_temp.q(pg_temp.u(401), format($$select org.create_legal_entity(%L, 'Otra S.A. (ficticia)', '30-11111111-1', 'registered', 'Prueba')$$,
                                                      pg_temp.u(1)))::uuid;
select is((select tax_id from org.legal_entities where id = (select id from le)), '30111111111',
  'el superadministrador crea una razón social; el CUIT se guarda sin guiones');
select is(pg_temp.msg(pg_temp.u(401), format($$select org.create_legal_entity(%L, 'Repetida', '30111111111', 'registered', 'Prueba')$$, pg_temp.u(1))),
  'Ya hay una razón social con ese CUIT en el grupo.', 'el CUIT no se repite en el grupo');
select is(pg_temp.msg(pg_temp.u(401), format($$select org.create_legal_entity(%L, 'Mal', '123', 'registered', 'Prueba')$$, pg_temp.u(1))),
  'Revisá el nombre y el CUIT (11 números).', 'un CUIT con menos de 11 números se rechaza');
select is(pg_temp.msg(pg_temp.u(401), format($$select org.update_legal_entity(%L, '{"vat_condition": "exempt"}', 'Cambio de condición')$$,
                                            (select id from le))),
  'sin error', 'se cambia la condición frente al IVA');
select is((select vat_condition::text from org.legal_entities where id = (select id from le)), 'exempt', 'y queda guardada');
select ok(exists (select 1 from audit.audit_events where table_name = 'legal_entities' and record_id = (select id from le)
                    and action::text = 'update' and reason = 'Cambio de condición'),
  'el cambio queda en la auditoría con su motivo');
select is(pg_temp.msg(pg_temp.u(403), format('select org.set_restaurant_legal_entity(%L, %L, ''Prueba'')', pg_temp.u(201), (select id from le))),
  'No tenés permiso para elegir la razón social de este local.',
  'la Directora no elige la razón social ni de un local de su marca: cambia el IVA del costo (decisión de Joaco)');
select is(pg_temp.msg(pg_temp.u(404), format('select org.set_restaurant_legal_entity(%L, %L, ''Prueba'')', pg_temp.u(201), (select id from le))),
  'No tenés permiso para elegir la razón social de este local.', 'el Gerente tampoco');
select is(pg_temp.msg(pg_temp.u(401), format('select org.set_restaurant_legal_entity(%L, %L, ''Nueva sociedad'')', pg_temp.u(201), (select id from le))),
  'sin error', 'la elige quien administra el grupo');
select ok(exists (select 1 from audit.audit_events where table_name = 'restaurants' and record_id = pg_temp.u(201)
                    and reason = 'Nueva sociedad'),
  'el cambio de razón social del local queda en la auditoría con su motivo');
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from org.legal_entities'), '3', 'el Gerente ve las razones sociales del grupo');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.legal_entities'), '0', 'la Cocinera no');

-- ---------------------------------------------------------------------------
-- Configuración del grupo
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format('select costing.update_price_settings(%L, 10, 20, ''Prueba'')', pg_temp.u(1))),
  'No tenés permiso para cambiar la configuración de precios.', 'Compras no cambia la configuración');
select is(pg_temp.msg(pg_temp.u(407), format('select costing.update_price_settings(%L, 10, 20, ''Prueba'')', pg_temp.u(1))),
  'No tenés permiso para cambiar la configuración de precios.', 'el Controller tampoco');
select is(pg_temp.msg(pg_temp.u(402), format('select costing.update_price_settings(%L, 0, 20, ''Prueba'')', pg_temp.u(1))),
  'Los porcentajes van de más de 0 a 100, y los días de 1 a 365.', 'un porcentaje fuera de rango se rechaza');
select is(pg_temp.msg(pg_temp.u(402), format('select costing.update_price_settings(%L, 8, 45, ''Más control'')', pg_temp.u(1))),
  'sin error', 'Dirección General la cambia');
select is(pg_temp.msg(pg_temp.u(402), format('select costing.update_price_settings(%L, 10, 40, ''Otra vez'')', pg_temp.u(1))),
  'sin error', 'y la vuelve a cambiar (una fila por grupo)');
select is(pg_temp.q(pg_temp.u(407), 'select approval_variation_pct || ''/'' || stale_days from costing.price_settings'),
  '10.00/40', 'el Controller la lee');
select ok(exists (select 1 from audit.audit_events where table_name = 'price_settings' and reason = 'Otra vez'
                    and actor_user_id = pg_temp.u(402)),
  'el cambio de configuración queda en la auditoría con quién y por qué');
select is(pg_temp.msg(pg_temp.u(402), format('select catalog.set_category_stale_days(%L, 7, ''Verduras rotan rápido'')', pg_temp.u(701))),
  'sin error', 'Dirección fija los días de una categoría');
select is(pg_temp.msg(pg_temp.u(408), format('select catalog.set_category_stale_days(%L, 7, ''Prueba'')', pg_temp.u(701))),
  'No tenés permiso para cambiar los días de precio desactualizado.', 'Compras no');

-- ---------------------------------------------------------------------------
-- Precios: neto y bruto los calcula la base, y nunca se cambian
-- ---------------------------------------------------------------------------
create function pg_temp.amounts(p_price numeric, p_discount numeric, p_doc text, p_vat numeric, p_incl boolean) returns text
language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, discount_amount,
                                     document_type, vat_rate, price_includes_vat, source)
  values (pg_temp.u(1), pg_temp.product('DEMO-PROD-030'), 'group', '2026-01-01', p_price, p_discount,
          p_doc::costing.price_document, p_vat, p_incl, 'test_value')
  returning net_package_price || '/' || gross_package_price
$$;
select is(pg_temp.amounts(12100, 0, 'invoice', 21, true), '10000.0000/12100.0000', 'con IVA incluido, la base separa el neto');
select is(pg_temp.amounts(10000, 0, 'invoice', 21, false), '10000.0000/12100.0000', 'sin IVA incluido, la base suma el IVA');
select is(pg_temp.amounts(10600, 600, 'invoice', 10.5, false), '10000.0000/11050.0000', 'el descuento se resta antes del IVA');
select is(pg_temp.amounts(8000, 0, 'no_invoice', null, true), '8000.0000/8000.0000', 'sin factura, neto y bruto son el precio final');
select throws_ok($$select pg_temp.amounts(8000, 0, 'invoice', null, true)$$, '23502', null, 'con factura, la alícuota es obligatoria (sin ella no hay neto)');
select throws_ok($$select pg_temp.amounts(8000, 8000, 'no_invoice', null, true)$$, '23514', null, 'el descuento no llega al precio');
select throws_ok($$insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, valid_from, package_price,
                                                       document_type, source)
                   values (pg_temp.u(1), pg_temp.product('DEMO-PROD-030'), 'group', pg_temp.u(101), '2026-01-01', 10, 'no_invoice', 'test_value')$$,
  '23514', null, 'un precio de grupo no lleva marca');
select throws_ok($$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price,
                                                       document_type, source)
                   values (pg_temp.u(1), pg_temp.product('DEMO-PROD-030'), 'group', '2026-01-01', 10, 'no_invoice', 'manual')$$,
  '23514', null, 'un precio sin aprobación solo puede ser un valor de prueba');
select is((select base_quantity from costing.price_records where purchase_product_id = pg_temp.product('DEMO-PROD-001')),
  10000.000000, 'cada precio guarda el contenido del envase en la unidad de uso (cajón de 10 kg = 10.000 g)');
select throws_ok($$update costing.price_records set package_price = 1 where purchase_product_id = pg_temp.product('DEMO-PROD-001')$$,
  '42501', 'Un precio aprobado no se cambia ni se borra: cargá un precio nuevo.', 'un precio no se cambia, ni siquiera como dueño de la tabla');
select throws_ok($$delete from costing.price_records where purchase_product_id = pg_temp.product('DEMO-PROD-001')$$,
  '42501', 'Un precio aprobado no se cambia ni se borra: cargá un precio nuevo.', 'ni se borra');
select is(pg_temp.q(pg_temp.u(408), format($$insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from,
                                             package_price, document_type, source)
                                             values (%L, %L, 'group', '2026-01-01', 10, 'no_invoice', 'manual') returning 'x'$$,
                                           pg_temp.u(1), pg_temp.product('DEMO-PROD-001'))),
  'ERROR 42501', 'nadie inserta un precio directo: entra solo aprobado, por la función');

-- ---------------------------------------------------------------------------
-- Quién ve qué precio: los de su local, los heredados de su marca y los del grupo
-- ---------------------------------------------------------------------------
-- Uno de otra marca (Parrilla) y uno de un local (Pastas Norte). Los 4 de arriba son de grupo.
insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, valid_from, package_price, document_type, source)
values (pg_temp.u(1), pg_temp.product('DEMO-PROD-012'), 'brand', pg_temp.u(102), current_date - 2, 20000, 'no_invoice', 'test_value');
insert into costing.price_records (group_id, purchase_product_id, scope_type, restaurant_id, valid_from, package_price, document_type, source)
values (pg_temp.u(1), pg_temp.product('DEMO-PROD-012'), 'restaurant', pg_temp.u(202), current_date - 2, 21000, 'no_invoice', 'test_value');
select is(pg_temp.prices_seen(407), '54', 'el Controller ve todos (51 de grupo, 2 de marca y 1 de local)');
select is(pg_temp.prices_seen(404), '52', 'el Gerente de Pastas Centro ve los de grupo y los de su marca, no los de Parrilla ni de Pastas Norte');
select is(pg_temp.prices_seen(411), '53', 'la Gerente de los dos locales de Pastas ve también el de Pastas Norte');
select is(pg_temp.prices_seen(403), '53', 'la Directora de Pastas ve los de su marca y sus locales, no los de Parrilla');
select is(pg_temp.prices_seen(405) || '/' || pg_temp.prices_seen(409), '0/0', 'el Chef y la Cocinera no ven ningún precio');
select is(pg_temp.prices_seen(410), '54', 'el Auditor los ve todos');

-- La auditoría guarda el precio, pero el historial lo oculta a quien no ve costos.
select is((select core.hide_costs(new_values) ->> 'package_price' || '/' || (core.hide_costs(new_values) ->> 'net_package_price')
                  || '/' || (core.hide_costs(new_values) ->> 'discount_amount')
             from audit.audit_events where table_name = 'price_records' and action::text = 'insert'
            order by occurred_at desc limit 1),
  '[oculto]/[oculto]/[oculto]', 'en el historial, los importes de un precio salen ocultos para quien no ve costos');

select * from finish();
rollback;
