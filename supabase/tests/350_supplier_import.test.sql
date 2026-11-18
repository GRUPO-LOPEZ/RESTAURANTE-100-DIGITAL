-- Importación de proveedores desde planilla (P1 de la Fase 3, ADR-0055): vista previa sin efectos, todo o nada al
-- confirmar, origen import en la auditoría, CUIT existentes que se omiten y errores por fila en castellano.
-- Personas del seed: Gerente 404, Controller 407, Compras 408, Cocinera 409.
-- Proveedores del seed: Verdulería 901 (CUIT 30-50000001-1). Rubros de compra: «Verduras y frutas», «Carnes», «Almacén».
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(41);

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
-- Un CUIT inventado con su dígito verificador, a partir de sus primeros 10 números.
create function pg_temp.cuit(p_base text) returns text language sql as $$
  select p_base || (select case when r = 11 then 0 when r = 10 then 9 else r end
                      from (select 11 - (sum(substr(p_base, i, 1)::int * (array[5, 4, 3, 2, 7, 6, 5, 4, 3, 2])[i]) % 11) as r
                              from generate_series(1, 10) as i) x)::text
$$;
grant execute on function pg_temp.u(int), pg_temp.cuit(text) to authenticated;

-- La planilla que manda la pantalla: dos proveedores nuevos y uno que ya existe.
create temporary table sheet (rows jsonb) on commit drop;
grant select on sheet to authenticated;
insert into sheet values (jsonb_build_array(
  jsonb_build_object('row', 2, 'name', 'Importado Uno S.A.', 'tax_id', pg_temp.cuit('3060000001'),
    'supplier', jsonb_build_object('trade_name', 'Uno', 'vat_condition', 'registered', 'email', 'uno@ejemplo.test',
                                   'phone', '11 4000-0001'),
    'terms', jsonb_build_object('order_days', jsonb_build_array(1, 3), 'delivery_days', jsonb_build_array(2, 4),
                                'po_channel', 'whatsapp', 'po_channel_target', '+54 9 11 4000-0001',
                                'requires_po_approval', true),
    'payment_terms', jsonb_build_object('payment_terms', 'account', 'payment_days', '30', 'minimum_order_amount', '150000'),
    'categories', jsonb_build_array('verduras Y FRUTAS', 'Carnes')),
  jsonb_build_object('row', 3, 'name', 'Importado Dos S.R.L.', 'tax_id', pg_temp.cuit('3060000002')),
  jsonb_build_object('row', 4, 'name', 'Verdulería repetida', 'tax_id', '30-50000001-1')));

create temporary table counts on commit drop as
select (select count(*) from catalog.suppliers) as suppliers,
       (select coalesce(max(last_number), 0) from catalog.code_series
         where group_id = pg_temp.u(1) and prefix = 'PROV-' and deleted_at is null) as prov_number,
       (select count(*) from audit.audit_events) as audit,
       (select count(*) from purchasing.supplier_terms) as terms;
grant select on counts to authenticated;

-- ---------------------------------------------------------------------------
-- Vista previa: dice qué va a pasar y no deja nada
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) ->> 'result' $$),
          'preview', 'Compras pide la vista previa');
select is(pg_temp.q(pg_temp.u(408), $$ select (purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) -> 'totals')::text $$),
          '{"rows": 3, "skip": 1, "error": 0, "create": 2}', 'la vista previa cuenta 2 que se crean y 1 que se omite');
select is(pg_temp.q(pg_temp.u(408), $$ select r ->> 'message' from jsonb_array_elements(
            purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) -> 'rows') r where r ->> 'row' = '4' $$),
          'Ya existe (DEMO-PROV-01): se omite.', 'un CUIT que ya está en el grupo se omite, con el código del que existe');
select is((select count(*) from catalog.suppliers), (select suppliers from counts), 'la vista previa no crea proveedores');
select is((select count(*) from audit.audit_events), (select audit from counts), 'la vista previa no deja auditoría');
select is((select coalesce(max(last_number), 0) from catalog.code_series
            where group_id = pg_temp.u(1) and prefix = 'PROV-' and deleted_at is null),
          (select prov_number from counts), 'la vista previa no gasta números PROV');
-- Si la vista previa hubiera consumido el contador, el primero de verdad no sería el siguiente al último.
create temporary table next_code on commit drop as
select 'PROV-' || lpad((coalesce(max(substr(code, 6)::int) filter (where code ~ '^PROV-[0-9]{4}$'), 0) + 1)::text, 4, '0') as code
  from catalog.suppliers where group_id = pg_temp.u(1);

-- ---------------------------------------------------------------------------
-- Confirmar: todo en una transacción, con origen import y el motivo
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), true, ' ') $$),
          'Escribí el motivo de la importación.', 'confirmar pide motivo');
select is(pg_temp.q(pg_temp.u(408), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), true, 'Carga inicial') ->> 'result' $$),
          'applied', 'Compras confirma la importación');
select is((select count(*) from catalog.suppliers), (select suppliers from counts) + 2, 'se crearon los dos nuevos');
select is((select code from catalog.suppliers where tax_id = pg_temp.cuit('3060000001')), (select code from next_code),
          'el primero lleva el código siguiente: la vista previa no gastó números');
select is((select concat_ws('/', s.name, s.trade_name, s.vat_condition, s.email, s.phone)
             from catalog.suppliers s where s.tax_id = pg_temp.cuit('3060000001')),
          'Importado Uno S.A./Uno/registered/uno@ejemplo.test/11 4000-0001', 'la ficha queda con sus datos');
select is((select concat_ws('/', t.order_days::text, t.delivery_days::text, t.po_channel, t.po_channel_target, t.requires_po_approval)
             from purchasing.supplier_terms t join catalog.suppliers s on s.id = t.supplier_id
            where s.tax_id = pg_temp.cuit('3060000001') and t.deleted_at is null),
          '{1,3}/{2,4}/whatsapp/+54 9 11 4000-0001/t', 'con sus días, su canal y la aprobación de la OC');
select is((select concat_ws('/', p.payment_terms, p.payment_days, p.minimum_order_amount::numeric(14, 0))
             from purchasing.supplier_payment_terms p join catalog.suppliers s on s.id = p.supplier_id
            where s.tax_id = pg_temp.cuit('3060000001') and p.deleted_at is null),
          'account/30/150000', 'con su condición de pago');
select is((select string_agg(c.name, ', ' order by c.name) from purchasing.supplier_categories sc
             join catalog.ingredient_categories c on c.id = sc.category_id
             join catalog.suppliers s on s.id = sc.supplier_id
            where s.tax_id = pg_temp.cuit('3060000001') and sc.deleted_at is null),
          'Carnes, Verduras y frutas', 'los rubros se reconocen sin importar mayúsculas ni tildes');
select is((select count(*) from purchasing.supplier_terms t join catalog.suppliers s on s.id = t.supplier_id
            where s.tax_id = pg_temp.cuit('3060000002') and t.deleted_at is null)::int,
          1, 'el que viene solo con razón social y CUIT también tiene su operativa');
select is((select count(*) from catalog.suppliers where tax_id = '30500000011')::int, 1,
          'el que ya existía no se duplica');
select ok(exists (select 1 from audit.audit_events e join catalog.suppliers s on s.id = e.record_id
                   where e.table_name = 'suppliers' and e.action = 'insert' and s.tax_id = pg_temp.cuit('3060000001')
                     and e.source = 'import' and e.reason = 'Carga inicial'),
          'el alta queda en la auditoría con origen import y el motivo');
select ok(exists (select 1 from audit.audit_events e
                   where e.table_name = 'supplier_payment_terms' and e.source = 'import' and e.reason = 'Carga inicial'),
          'la condición de pago también queda auditada con origen import');
select is(pg_temp.q(pg_temp.u(408), $$ select (purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) -> 'totals')::text $$),
          '{"rows": 3, "skip": 3, "error": 0, "create": 0}', 'subir la misma planilla de nuevo omite todo');

-- ---------------------------------------------------------------------------
-- Errores: una fila mala frena todo, con el motivo en castellano
-- ---------------------------------------------------------------------------
create temporary table bad (rows jsonb) on commit drop;
grant select on bad to authenticated;
insert into bad values (jsonb_build_array(
  jsonb_build_object('row', 2, 'name', 'Buena S.A.', 'tax_id', pg_temp.cuit('3060000003')),
  jsonb_build_object('row', 3, 'name', 'Rubro raro S.A.', 'tax_id', pg_temp.cuit('3060000004'),
                     'categories', jsonb_build_array('Bebidas')),
  jsonb_build_object('row', 4, 'name', 'CUIT malo S.A.', 'tax_id', '30-12345678-9'),
  jsonb_build_object('row', 5, 'name', 'Repetido A', 'tax_id', pg_temp.cuit('3060000005')),
  jsonb_build_object('row', 6, 'name', 'Repetido B', 'tax_id', pg_temp.cuit('3060000005')),
  jsonb_build_object('row', 7, 'name', 'Canal malo S.A.', 'tax_id', pg_temp.cuit('3060000006'),
                     'terms', jsonb_build_object('po_channel', 'email', 'po_channel_target', 'no-es-un-correo')),
  jsonb_build_object('row', 8, 'name', 'Enum malo S.A.', 'tax_id', pg_temp.cuit('3060000007'),
                     'supplier', jsonb_build_object('vat_condition', 'monotributista')),
  jsonb_build_object('row', 9, 'name', '', 'tax_id', pg_temp.cuit('3060000008'))));
create temporary table audit_before_bad on commit drop as select count(*) as n from audit.audit_events;
create temporary table bad_result on commit drop as
select pg_temp.q(pg_temp.u(408), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from bad), true, 'Con errores')::text $$)::jsonb as r;
create function pg_temp.bad_msg(p_row int) returns text language sql as $$
  select x ->> 'message' from bad_result, jsonb_array_elements(r -> 'rows') x where (x ->> 'row')::int = p_row
$$;

select is((select r ->> 'result' from bad_result), 'rejected', 'con una fila mala, la confirmación se rechaza');
select is((select count(*) from catalog.suppliers where name = 'Buena S.A.')::int, 0, 'y no se crea ni la fila buena');
select is((select count(*) from audit.audit_events), (select n from audit_before_bad),
          'la confirmación rechazada no deja auditoría');
select is(pg_temp.bad_msg(2), 'Se crea.', 'la fila buena dice que se crearía');
select is(pg_temp.bad_msg(3), 'Rubros: «Bebidas» no es un rubro de compra del grupo.', 'un rubro que no existe');
select is(pg_temp.bad_msg(4), 'CUIT: «30-12345678-9» no es un CUIT válido.', 'un CUIT con el dígito verificador mal');
select is(pg_temp.bad_msg(5), 'CUIT repetido en la planilla: dejá uno solo.', 'el mismo CUIT dos veces en la planilla (la primera)');
select is(pg_temp.bad_msg(6), 'CUIT repetido en la planilla: dejá uno solo.', 'el mismo CUIT dos veces en la planilla (la segunda)');
select is(pg_temp.bad_msg(7),
          'El dato no corresponde al canal: un teléfono para WhatsApp, un correo para mail o una dirección https:// para el portal.',
          'un destino que no corresponde al canal, con el mensaje de la ficha');
select is(pg_temp.bad_msg(8), 'Hay un dato con un valor que no corresponde: revisá la fila.', 'una condición de IVA que no existe, con la fila');
select is(pg_temp.bad_msg(9), 'Falta la razón social.', 'sin razón social');

select is(pg_temp.msg(pg_temp.u(408), format($$ select purchasing.import_suppliers(pg_temp.u(1), %L::jsonb, false, null) $$,
                                             (select jsonb_agg(jsonb_build_object('row', i, 'name', 'P' || i, 'tax_id', pg_temp.cuit('3070000000')))
                                                from generate_series(1, 201) as i))),
          'La planilla tiene más de 200 proveedores. Partila en dos archivos.', 'más de 200 filas se rechaza');

select is(pg_temp.msg(pg_temp.u(408), format($$ select purchasing.import_suppliers(pg_temp.u(1), %L::jsonb, false, null) $$,
                                             (select jsonb_agg(jsonb_build_object('row', i, 'name', 'P' || i, 'tax_id', pg_temp.cuit('3070000000'),
                                                                                  'supplier', jsonb_build_object('address', repeat('x', 600000))))
                                                from generate_series(1, 2) as i))),
          'La planilla pasa 1 MB.', 'una planilla de más de 1 MB se rechaza');
-- Llamando directo a la base: la razón social y el CUIT van arriba, nunca dentro de la ficha (así no se saltea el
-- control de repetidos), y las cuentas de pago no se importan.
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.import_suppliers(pg_temp.u(1), jsonb_build_array(jsonb_build_object(
            'row', 2, 'name', 'Otro S.A.', 'tax_id', pg_temp.cuit('3060000009'),
            'supplier', jsonb_build_object('tax_id', '30-50000001-1'))), false, null) $$),
          'Campos que no se pueden cambiar acá: tax_id.', 'el CUIT no se puede pisar dentro de los datos del proveedor');
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.import_suppliers(pg_temp.u(1), jsonb_build_array(jsonb_build_object(
            'row', 2, 'name', 'Otro S.A.', 'tax_id', pg_temp.cuit('3060000009'),
            'terms', jsonb_build_object('receiving_from', '08:00'))), false, null) $$),
          'Campos que no se pueden cambiar acá: receiving_from.', 'la operativa solo lleva lo que trae la planilla');

-- ---------------------------------------------------------------------------
-- Los envoltorios de la ficha siguen auditando con origen manual
-- ---------------------------------------------------------------------------
create temporary table manual on commit drop as
select pg_temp.q(pg_temp.u(408), $$ select purchasing.create_supplier(pg_temp.u(1), 'Alta manual S.A.', pg_temp.cuit('3060000010'), 'Alta a mano')::text $$)::uuid as id;
select is(pg_temp.q(pg_temp.u(408), format($$ select purchasing.save_supplier_sheet(%L, %L, '{"supplier": {"city": "Morón"}}', 'Cambio a mano') ->> 'result' $$,
                                           (select id from manual),
                                           purchasing.supplier_sheet_stamp_internal((select id from manual)))),
          'applied', 'Compras guarda la ficha a mano');
select is((select string_agg(e.action || '/' || e.source || '/' || e.reason, ', ' order by e.sequence_number)
             from audit.audit_events e where e.table_name = 'suppliers' and e.record_id = (select id from manual)),
          'insert/manual/Alta a mano, update/manual/Cambio a mano',
          'el alta y la ficha a mano quedan con origen manual y su motivo');

-- Un CUIT por proveedor en cada grupo (índice único, comparado sin guiones): en el alta y en la ficha.
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.create_supplier(pg_temp.u(1), 'Otra Verdulería', '30-50000001-1', 'Alta a mano') $$)
          || ' / ' || pg_temp.msg(pg_temp.u(408), $$ select purchasing.create_supplier(pg_temp.u(1), 'Otra Verdulería', '30500000011', 'Alta a mano') $$),
          'Ya hay un proveedor con ese CUIT en el grupo. / Ya hay un proveedor con ese CUIT en el grupo.',
          'el alta no repite un CUIT, con o sin guiones');
select is(pg_temp.msg(pg_temp.u(408), format($$ select purchasing.save_supplier_sheet(%L, %L, '{"supplier": {"tax_id": "30-50000001-1"}}', 'Cambio a mano') $$,
                                             (select id from manual),
                                             purchasing.supplier_sheet_stamp_internal((select id from manual)))),
          'Ya hay un proveedor con ese CUIT en el grupo.', 'la ficha no deja poner el CUIT de otro proveedor');

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) ->> 'result' $$)
          || '/' || pg_temp.q(pg_temp.u(404), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) ->> 'result' $$)
          || '/' || pg_temp.q(pg_temp.u(407), $$ select purchasing.import_suppliers(pg_temp.u(1), (select rows from sheet), false, null) ->> 'result' $$),
          'denied/denied/denied', 'la Cocinera, el Gerente y el Controller no importan proveedores');
select ok(exists (select 1 from audit.authentication_security_events where operation = 'purchasing.import_suppliers'),
          'el rechazo queda en los eventos de seguridad');
select is(pg_temp.q(pg_temp.u(408), $$ select purchasing.create_supplier_internal(pg_temp.u(1), 'x', null)::text $$)
          || '/' || pg_temp.q(pg_temp.u(408), $$ select purchasing.save_supplier_sheet_internal(pg_temp.u(901), '{}')::text $$),
          'ERROR 42501/ERROR 42501', 'nadie llama directo a las internas');

select * from finish();
rollback;
