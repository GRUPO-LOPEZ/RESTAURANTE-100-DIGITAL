-- Ficha completa de proveedor (Fase 3, Prompt 1, ADR-0050).
-- Personas del seed: Dirección 402, Gerente 404, Controller 407, Compras 408, Cocinera 409.
-- Proveedores del seed: Frigorífico 902 (cuenta corriente, con cuentas), Molino 905 (inactivo).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(77);

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

-- El sello de la ficha del Frigorífico, para guardar (lo pide cada guardado).
create function pg_temp.stamp(p_id uuid) returns text language sql as $$
  select purchasing.supplier_sheet_stamp_internal(p_id)::text
$$;
grant execute on function pg_temp.stamp(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_schema('purchasing', 'existe el esquema purchasing');
-- Las 5 del proveedor, las 5 de artículos y listas (Prompt 2, ADR-0052) y las 4 de órdenes de compra (Prompt 3, ADR-0053).
select tables_are('purchasing', array['supplier_terms', 'supplier_payment_terms', 'supplier_payment_accounts',
                                      'supplier_categories', 'supplier_customer_numbers', 'unmapped_articles',
                                      'article_aliases', 'price_lists', 'price_list_items', 'attachments',
                                      'purchase_orders', 'purchase_order_lines', 'purchase_order_events',
                                      'outbound_messages'],
                  'purchasing tiene las tablas del proveedor, de listas de precios y de órdenes de compra');
select ok((select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'purchasing' and c.relkind = 'r'), 'RLS activo en todas las tablas de purchasing');
select ok((select bool_and(obj_description(c.oid, 'pg_class') is not null)
             from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'purchasing' and c.relkind = 'r'), 'cada tabla tiene su comentario');
select ok((select bool_and(col_description(a.attrelid, a.attnum) is not null)
             from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'purchasing' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped),
          'cada columna tiene su comentario');
select ok((select count(*) = 14 from pg_trigger t join pg_class c on c.oid = t.tgrelid
             join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'purchasing' and t.tgname = 'log_change'), 'las 14 tablas se auditan');
select ok(not has_table_privilege('authenticated', 'purchasing.supplier_terms', 'insert')
          and not has_table_privilege('authenticated', 'purchasing.supplier_payment_accounts', 'update'),
          'la API no escribe directo');

-- ---------------------------------------------------------------------------
-- CUIT (casos 1 y 2 del plan de la Fase 3)
-- ---------------------------------------------------------------------------
select ok(core.valid_cuit('20123456786'), 'caso 1: 20-12345678-6 es válido');
select ok(not core.valid_cuit('20123456787'), 'caso 2: el mismo con otro verificador no');
select ok(not core.valid_cuit('20-12345678-6'), 'con guiones no: se normaliza antes');
select is(core.normalize_cuit(' 20-12345678-6 '), '20123456786', 'normalizar saca guiones y espacios');
select ok((select bool_and(core.valid_cuit(tax_id)) from catalog.suppliers where code like 'DEMO-PROV-%'),
          'los CUIT del seed son válidos');

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select ok((select count(*) = 9 from core.permissions where module = 'purchasing' and deleted_at is null),
          '9 permisos de compras (3 de proveedores, 2 de listas de precios y 4 de órdenes de compra)');
select ok((select is_sensitive from core.permissions where code = 'purchasing.manage_suppliers')
          and (select is_sensitive from core.permissions where code = 'purchasing.view_payment_terms'),
          'administrar y ver el pago son sensibles');
select is((select array_agg(p.code order by p.code) from core.role_permissions rp join core.roles r on r.id = rp.role_id
             join core.permissions p on p.id = rp.permission_id
            where r.code = 'superadmin' and p.module = 'purchasing' and rp.deleted_at is null),
          array['purchasing.approve_orders', 'purchasing.create_orders', 'purchasing.manage_price_lists',
                'purchasing.manage_suppliers', 'purchasing.record_order_news', 'purchasing.view_orders',
                'purchasing.view_price_lists', 'purchasing.view_suppliers'],
          'el superadmin tiene los de Compras, a quien puede suspender (G2)');
-- La matriz entera de compras, rol por rol (como la 140 con el catálogo).
select is((select array_agg(r.code || '=' || p.code order by r.code, p.code)
             from core.role_permissions rp join core.roles r on r.id = rp.role_id
             join core.permissions p on p.id = rp.permission_id
            where p.module = 'purchasing' and rp.deleted_at is null),
          array['auditor=purchasing.view_orders', 'auditor=purchasing.view_price_lists',
                'auditor=purchasing.view_suppliers', 'brand_director=purchasing.create_orders',
                'brand_director=purchasing.record_order_news', 'brand_director=purchasing.view_orders',
                'brand_director=purchasing.view_price_lists', 'brand_director=purchasing.view_suppliers',
                'controller=purchasing.view_orders', 'controller=purchasing.view_payment_terms',
                'controller=purchasing.view_price_lists', 'controller=purchasing.view_suppliers',
                'cook=purchasing.create_orders', 'cook=purchasing.view_orders',
                'cook=purchasing.view_suppliers', 'executive_chef=purchasing.create_orders',
                'executive_chef=purchasing.view_orders', 'executive_chef=purchasing.view_suppliers',
                'general_management=purchasing.manage_suppliers', 'general_management=purchasing.view_orders',
                'general_management=purchasing.view_payment_terms', 'general_management=purchasing.view_price_lists',
                'general_management=purchasing.view_suppliers', 'head_chef=purchasing.create_orders',
                'head_chef=purchasing.view_orders', 'head_chef=purchasing.view_suppliers',
                'purchasing=purchasing.approve_orders', 'purchasing=purchasing.create_orders',
                'purchasing=purchasing.manage_price_lists', 'purchasing=purchasing.manage_suppliers',
                'purchasing=purchasing.record_order_news', 'purchasing=purchasing.view_orders',
                'purchasing=purchasing.view_price_lists', 'purchasing=purchasing.view_suppliers',
                'restaurant_manager=purchasing.create_orders', 'restaurant_manager=purchasing.record_order_news',
                'restaurant_manager=purchasing.view_orders', 'restaurant_manager=purchasing.view_price_lists',
                'restaurant_manager=purchasing.view_suppliers', 'superadmin=purchasing.approve_orders',
                'superadmin=purchasing.create_orders', 'superadmin=purchasing.manage_price_lists',
                'superadmin=purchasing.manage_suppliers', 'superadmin=purchasing.record_order_news',
                'superadmin=purchasing.view_orders', 'superadmin=purchasing.view_price_lists',
                'superadmin=purchasing.view_suppliers'],
          'la matriz de compras, rol por rol');

-- ---------------------------------------------------------------------------
-- RLS por rol
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from catalog.suppliers$$), '6',
          'la cocinera ve los proveedores (purchasing.view_suppliers)');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from purchasing.supplier_terms$$), '6',
          'y sus días y canal');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from purchasing.supplier_payment_terms$$), '0',
          'pero no la condición de pago');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from purchasing.supplier_payment_accounts$$), '0',
          'ni las cuentas');
select is(pg_temp.q(pg_temp.u(404), $$select count(*)::text from purchasing.supplier_payment_accounts$$), '0',
          'el gerente tampoco ve las cuentas');
select is(pg_temp.q(pg_temp.u(407), $$select count(*)::text from purchasing.supplier_payment_accounts$$), '7',
          'el Controller ve las cuentas');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from purchasing.supplier_payment_terms$$), '6',
          'Compras ve la condición de pago');
select is(pg_temp.q(pg_temp.u(401), $$select count(*)::text from purchasing.supplier_payment_accounts$$), '7',
          'el superadmin ve las cuentas (excepción aceptada por Joaco, ADR-0050)');
select is(pg_temp.q(pg_temp.u(410), $$select count(*)::text from purchasing.supplier_payment_accounts$$), '0',
          'el Auditor no ve las cuentas');
select is(pg_temp.q(pg_temp.u(403), $$select count(*)::text from purchasing.supplier_payment_terms$$), '0',
          'el Director de Marca no ve el pago');
-- Números de cliente, por local: el gerente del local 201 ve solo el de su local, no el del 203.
select is(pg_temp.q(pg_temp.u(404), $$select string_agg(customer_number, ',' order by customer_number)
                                       from purchasing.supplier_customer_numbers$$), '4410,CLI-0101',
          'el gerente ve los números de cliente de su local, no los de otro');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from purchasing.supplier_customer_numbers$$), '3',
          'Compras ve los de todos los locales');
select is((pg_temp.q(pg_temp.u(409), format('select purchasing.supplier_sheet_state(%L)::text', pg_temp.u(902)))::jsonb
           ->> 'can_see_payment'), 'false', 'la ficha le dice a la cocinera que no ve el pago');
select is((pg_temp.q(pg_temp.u(407), format('select purchasing.supplier_sheet_state(%L)::text', pg_temp.u(902)))::jsonb
           ->> 'can_manage'), 'false', 'y al Controller que no edita');

-- El listado corre con los permisos de cada uno: a la cocinera la condición de pago le llega vacía.
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from jsonb_array_elements(purchasing.supplier_list()->'rows') r
                                       where r ? 'payment_terms' and (r->>'payment_terms' is not null
                                                                       or r->>'payment_days' is not null)$$), '0',
          'el listado no le muestra la condición de pago a la cocinera en ninguna fila');
select is(pg_temp.q(pg_temp.u(408), $$select r->>'payment_terms' from jsonb_array_elements(purchasing.supplier_list(p_search => 'frigor')->'rows') r$$),
          'account', 'a Compras sí');
select is(pg_temp.q(pg_temp.u(408), $$select (purchasing.supplier_list(p_search => '30-50000003')->>'total')$$), '1',
          'se busca por CUIT con guiones');
select is(pg_temp.q(pg_temp.u(408), $$select (purchasing.supplier_list(p_active => false)->'rows'->0->>'code')$$), 'DEMO-PROV-05',
          'la pestaña Inactivos trae al Molino');

-- Otro grupo: nadie del grupo demo lo ve.
insert into org.groups (id, name, legal_name, tax_id)
values ('00000000-0000-4000-8000-000000000002', 'Otro grupo', 'Otro grupo S.A. (ficticia)', '00000000000');
insert into catalog.suppliers (id, group_id, code, name)
values ('00000000-0000-4000-8000-000000009999', '00000000-0000-4000-8000-000000000002', 'OTRO-01', 'Proveedor de otro grupo');
insert into purchasing.supplier_payment_terms (group_id, supplier_id, payment_terms)
values ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000009999', 'cash');
select is(pg_temp.q(pg_temp.u(408), $$select count(*)::text from catalog.suppliers where code = 'OTRO-01'$$), '0',
          'Compras no ve proveedores de otro grupo');
select is(pg_temp.q(pg_temp.u(402), $$select count(*)::text from purchasing.supplier_payment_terms
                                       where supplier_id = '00000000-0000-4000-8000-000000009999'$$), '0',
          'ni Dirección su pago');
select is(pg_temp.q(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, now(), '{"supplier": {"city": "X"}}', 'Prueba')->>'result'$$,
                                          '00000000-0000-4000-8000-000000009999')),
          'denied', 'ni lo puede editar');

-- ---------------------------------------------------------------------------
-- Guardar la ficha: una transacción, con motivo, auditoría y sello
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(407), format($$select purchasing.save_supplier_sheet(%L, %L, '{"supplier": {"city": "X"}}', 'Prueba')->>'result'$$,
                                          pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'denied', 'el Controller no edita');
select is(pg_temp.q(pg_temp.u(409), format($$select purchasing.save_supplier_sheet(%L, %L, '{"supplier": {"city": "X"}}', 'Prueba')->>'result'$$,
                                          pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'denied', 'la cocinera tampoco');
select ok(exists (select 1 from audit.authentication_security_events where operation = 'purchasing.save_supplier_sheet'),
          'el rechazo queda en el registro de seguridad');

select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L,
            '{"supplier": {"city": "Ciudad Nueva"}, "terms": {"delivery_days": [1, 3, 5], "requires_po_approval": true},
              "payment_terms": {"payment_terms": "account", "payment_days": 45},
              "accounts": [{"method": "transfer", "alias": "frigo.nuevo"}],
              "customer_numbers": [{"restaurant_id": "00000000-0000-4000-8000-000000000201", "customer_number": "CLI-0101"}]}',
            'Ajuste de condiciones con el proveedor')$$, pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'sin error', 'Compras guarda la ficha entera');
select is((select city from catalog.suppliers where id = pg_temp.u(902)), 'Ciudad Nueva', 'el dato del proveedor');
select is((select delivery_days::text from purchasing.supplier_terms where supplier_id = pg_temp.u(902) and deleted_at is null),
          '{1,3,5}', 'los días de entrega');
select is((select payment_days from purchasing.supplier_payment_terms where supplier_id = pg_temp.u(902) and deleted_at is null),
          45::smallint, 'los días de pago');
select is((select count(*)::int from purchasing.supplier_payment_accounts where supplier_id = pg_temp.u(902) and deleted_at is null),
          3, 'la cuenta nueva');
select is((select count(*)::int from purchasing.supplier_customer_numbers where supplier_id = pg_temp.u(902) and deleted_at is null),
          1, 'el local que no vino en la lista se quita (borrado lógico)');
select ok(exists (select 1 from audit.audit_events where table_name = 'supplier_payment_terms'
                     and reason = 'Ajuste de condiciones con el proveedor'),
          'la auditoría guarda el motivo');
-- El cambio de cuentas avisa a quien ve el pago para todo el grupo (Controller y Dirección), no a Compras.
select is((select count(*)::int from core.notifications where kind = 'supplier_account_changed'
             and recipient_user_id = pg_temp.u(407) and body like 'Nueva: Transferencia · alias frigo.nuevo%'), 1,
          'el Controller recibe el aviso de la cuenta nueva, con su dato');
select is((select count(*)::int from core.notifications where kind = 'supplier_account_changed'
             and recipient_user_id = pg_temp.u(408)), 0, 'quien hizo el cambio no se avisa a sí mismo');
-- El historial oculta el pago a quien no lo ve: el Auditor ve el evento sin el alias; el Controller lo ve entero.
select is(pg_temp.q(pg_temp.u(410), $$select new_values->>'alias' from core.audit_history(p_module => 'purchasing', p_limit => 200)
                                       where table_name = 'supplier_payment_accounts' and new_values->>'alias' is not null
                                       order by sequence_number desc limit 1$$), '[oculto]',
          'el Auditor ve el cambio de cuenta en el historial, con los datos ocultos');
select is(pg_temp.q(pg_temp.u(407), $$select new_values->>'alias' from core.audit_history(p_module => 'purchasing', p_limit => 200)
                                       where table_name = 'supplier_payment_accounts' and new_values->>'alias' = 'frigo.nuevo'
                                       limit 1$$), 'frigo.nuevo',
          'el Controller lo ve entero');

-- Todo o nada: una cuenta inválida no deja guardado el cambio de la ciudad.
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L,
            '{"supplier": {"city": "No tiene que quedar"}, "accounts": [{"method": "transfer"}]}', 'Prueba de todo o nada')$$,
            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'La transferencia necesita CBU o alias, y el pago electrónico, su código.', 'transferencia sin CBU ni alias: rechazada');
select is((select city from catalog.suppliers where id = pg_temp.u(902)), 'Ciudad Nueva', 'y no quedó nada a medias');

select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, '2000-01-01', '{"supplier": {"city": "X"}}', 'Prueba')$$,
                                            pg_temp.u(902))),
          'Otra persona cambió este proveedor mientras lo editabas: recargá la página para ver sus cambios.',
          'un sello viejo se rechaza');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"supplier": {"city": "X"}}', '')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'Escribí el motivo de los cambios.', 'sin motivo no se guarda');

-- ---------------------------------------------------------------------------
-- Validaciones (casos 3 y 4 del plan)
-- ---------------------------------------------------------------------------
-- Un subrubro de prueba (el seed no tiene).
insert into catalog.ingredient_categories (id, group_id, parent_id, name)
values (pg_temp.u(7099), pg_temp.u(1), pg_temp.u(701), 'Hojas verdes de prueba');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"supplier": {"tax_id": "20-12345678-7"}}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'El CUIT no es válido: revisá los números.', 'un CUIT inválido no se guarda');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"terms": {"order_days": [0, 8]}}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'Los días van de lunes a domingo, sin repetir.', 'días fuera de 1 a 7');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"terms": {"order_days": [2, 2]}}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'Los días van de lunes a domingo, sin repetir.', 'días repetidos');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"terms": {"receiving_from": "10:00", "receiving_to": "08:00"}}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'El horario de recepción va con «desde» y «hasta», y «desde» es antes que «hasta».', 'caso 3: horario invertido');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"terms": {"po_channel": "supplier_portal", "po_channel_target": "no es una URL"}}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'El dato no corresponde al canal: un teléfono para WhatsApp, un correo para mail o una dirección https:// para el portal.',
          'caso 4: un canal con un dato que no le corresponde');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"payment_terms": {"payment_terms": "cash", "payment_days": 10}}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)))),
          'En cuenta corriente, los días van de 1 a 180. En el resto de las condiciones no van días.', 'contado con días');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"categories": ["%s"]}', 'Prueba')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)),
                                            pg_temp.u(7099))),
          'Elegí rubros de compra vigentes (del primer nivel).', 'un subrubro no va como rubro que provee');

select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"categories": ["%s", "%s"]}', 'Rubros que provee')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)), pg_temp.u(702), pg_temp.u(706))),
          'sin error', 'Compras guarda los rubros que provee');
select is((select string_agg(category_id::text, ',' order by category_id) from purchasing.supplier_categories
            where supplier_id = pg_temp.u(902) and deleted_at is null),
          pg_temp.u(702)::text || ',' || pg_temp.u(706)::text, 'quedan los dos rubros');
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.save_supplier_sheet(%L, %L, '{"accounts": [{"id": "%s", "remove": true}]}', 'Ya no usa eCheq')$$,
                                            pg_temp.u(902), pg_temp.stamp(pg_temp.u(902)),
                                            (select id from purchasing.supplier_payment_accounts where supplier_id = pg_temp.u(902)
                                                and method = 'echeq' and deleted_at is null))),
          'sin error', 'quitar una cuenta');
select ok(exists (select 1 from purchasing.supplier_payment_accounts where supplier_id = pg_temp.u(902)
                    and method = 'echeq' and deleted_at is not null),
          'la cuenta queda borrada lógicamente, con su historia');
select is(pg_temp.q(pg_temp.u(409), format($$select catalog.update_supplier(%L, '{"name": "X"}', 'Prueba')::text$$, pg_temp.u(902))),
          'ERROR 42501', 'la cocinera no edita por el camino viejo');
select is(pg_temp.q(pg_temp.u(409), format($$select purchasing.set_supplier_active(%L, false, 'Prueba')->>'result'$$, pg_temp.u(901))),
          'denied', 'ni desactiva');
-- Un proveedor cargado antes de la Fase 3 con el CUIT mal se puede desactivar igual (el control es al cambiar el CUIT).
alter table catalog.suppliers disable trigger guard_supplier_tax_id;
update catalog.suppliers set tax_id = '30-12345678-0' where id = pg_temp.u(906);
alter table catalog.suppliers enable trigger guard_supplier_tax_id;
select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.set_supplier_active(%L, false, 'Prueba con CUIT viejo')$$, pg_temp.u(906))),
          'sin error', 'un proveedor viejo con el CUIT mal se desactiva');
select is((pg_temp.q(pg_temp.u(408), format('select purchasing.supplier_sheet_state(%L)::text', pg_temp.u(906)))::jsonb
           ->> 'tax_id_invalid'), 'true', 'y la ficha avisa que su CUIT no es válido');

-- ---------------------------------------------------------------------------
-- Alta con código automático y desactivar
-- ---------------------------------------------------------------------------
create temporary table created (n int, id text);
insert into created
values (1, pg_temp.q(pg_temp.u(408), $$select purchasing.create_supplier('00000000-0000-4000-8000-000000000001',
                                         'Proveedor Nuevo Uno S.A.', '30-50000009-7', 'Alta de prueba')::text$$)),
       (2, pg_temp.q(pg_temp.u(408), $$select purchasing.create_supplier('00000000-0000-4000-8000-000000000001',
                                         'Proveedor Nuevo Dos S.A.', '', 'Alta de prueba')::text$$));
select is((select s.code from catalog.suppliers s join created c on c.id = s.id::text where c.n = 1), 'PROV-0001',
          'el alta da el código PROV-0001');
select is((select s.code from catalog.suppliers s join created c on c.id = s.id::text where c.n = 2), 'PROV-0002',
          'y el siguiente, PROV-0002 (sin CUIT: el puesto del mercado no tiene)');
select is((select tax_id from catalog.suppliers where code = 'PROV-0001'), '30500000097', 'el CUIT queda sin guiones');
select is(pg_temp.q(pg_temp.u(409), $$select purchasing.create_supplier('00000000-0000-4000-8000-000000000001', 'X S.A.', null, 'Prueba')::text$$),
          'ERROR 42501', 'la cocinera no da de alta');

select is(pg_temp.msg(pg_temp.u(408), format($$select purchasing.set_supplier_active(%L, false, 'Ya no le compramos')$$, pg_temp.u(902))),
          'sin error', 'desactivar');
select ok((select not is_active from catalog.suppliers where id = pg_temp.u(902))
          and exists (select 1 from purchasing.supplier_payment_accounts where supplier_id = pg_temp.u(902) and deleted_at is null),
          'desactivar conserva la ficha entera');

-- Un solo camino de escritura: la función vieja del catálogo pide el permiso de proveedores.
select is(pg_temp.q(pg_temp.u(405), $$select catalog.create_supplier('00000000-0000-4000-8000-000000000001', 'VIEJO-01', 'Viejo', '{}', 'Prueba')::text$$),
          'ERROR 42501', 'catalog.create_supplier ya no anda sin purchasing.manage_suppliers');

select * from finish();
rollback;
