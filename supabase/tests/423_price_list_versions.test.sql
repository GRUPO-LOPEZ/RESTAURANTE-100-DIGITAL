-- Listas de precios, parte D (ADR-0071): controles antes de cargar (variación, umbral de Dirección, «Revisar» a 10
-- veces y precio por unidad de uso), el artículo elegido a mano y recordado, versiones, anulación y archivos de Excel.
-- Personas del seed: Controller 407, Compras 408, Cocinera 409. Frigorífico 902 con la lista 1302 vigente (albahaca FR007
-- a $ 1.899,72 por kg, perejil FR008); Almacén 904 con la 1305 recibida. Umbral de Dirección: 15 %.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(50);

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
create temporary table ids (k text primary key, id uuid);
create function pg_temp.k(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant select on ids to authenticated;
grant execute on function pg_temp.u(int), pg_temp.k(text) to authenticated;

insert into ids
select 'albahaca', purchase_product_id from purchasing.price_list_items
 where price_list_id = pg_temp.u(1302) and supplier_sku = 'FR007';
insert into ids
select 'perejil', purchase_product_id from purchasing.price_list_items
 where price_list_id = pg_temp.u(1302) and supplier_sku = 'FR008';
-- Un producto de otro proveedor (Lácteos).
insert into ids
select 'ajeno', purchase_product_id from purchasing.price_list_items
 where price_list_id = pg_temp.u(1303) and purchase_product_id is not null order by line_order limit 1;

-- Lo que había en costos al empezar: las listas nunca lo tocan (ADR-0052, caso 10).
create temporary table base_costs as select count(*) as n from costing.price_records;

-- Los renglones de una vista previa, como texto (la línea n).
create function pg_temp.preview(p_user int, p_items jsonb, p_n int, p_key text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select purchasing.price_list_preview(%L, %L::jsonb) -> %s ->> %L', pg_temp.u(902), p_items, p_n - 1, p_key))
$$;

-- ---------------------------------------------------------------------------
-- 1. Lo nuevo de la tabla
-- ---------------------------------------------------------------------------
select is((select string_agg(distinct version::text, ',') from purchasing.price_lists), '1',
          'las listas de antes son la versión 1');
select ok(not has_function_privilege('anon', 'purchasing.price_list_preview(uuid, jsonb)', 'execute')
          and not has_function_privilege('anon', 'purchasing.correct_price_list(uuid, jsonb, text, boolean)', 'execute')
          and not has_function_privilege('anon', 'purchasing.void_price_list(uuid, text)', 'execute')
          and not has_function_privilege('authenticated', 'purchasing.add_price_list_items(purchasing.price_lists, jsonb)', 'execute')
          and not has_function_privilege('authenticated', 'purchasing.remember_list_aliases(uuid)', 'execute'),
          'anon no lee ni cambia listas; las internas no se piden desde la app');

-- ---------------------------------------------------------------------------
-- 2. La vista previa: los controles antes de cargar
-- ---------------------------------------------------------------------------
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2100, "vat_rate": 10.5}]', 1,
                          'purchase_product_id'),
          pg_temp.k('albahaca')::text, 'reconoce el artículo por su código');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2100, "vat_rate": 10.5}]', 1,
                          'change_pct'),
          '10.54', 'la variación contra la lista vigente');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2100, "vat_rate": 10.5}]', 1,
                          'over_threshold'),
          'false', 'una suba del 10 % no pasa el umbral de Dirección (15 %)');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2500, "vat_rate": 10.5}]', 1,
                          'over_threshold'),
          'true', 'una del 31 %, sí');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 19000, "vat_rate": 10.5}]', 1,
                          'review'),
          'true', '10 veces más: «Revisar»');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 180, "vat_rate": 10.5}]', 1,
                          'review'),
          'true', '10 veces menos, también');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2500, "vat_rate": 10.5}]', 1,
                          'review'),
          'false', 'una suba común no es «Revisar»');
select is(pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2100, "vat_rate": 10.5}]', 1,
                          'per_use_price') || ' por ' ||
          pg_temp.preview(408, '[{"name": "Albahaca", "sku": "FR007", "list_price": 2100, "vat_rate": 10.5}]', 1,
                          'per_use_unit'),
          '2100.00 por kg', 'el precio por unidad de uso (el envase de 1.000 g, por kg)');
select is(pg_temp.preview(408, '[{"name": "Algo que no existe", "list_price": 100, "vat_rate": 21}]', 1,
                          'purchase_product_id'),
          null, 'lo que no reconoce queda sin producto');
select is(pg_temp.preview(408, format('[{"name": "Perejil crespo atado", "list_price": 2100, "vat_rate": 21, "purchase_product_id": "%s"}]',
                                      pg_temp.k('perejil'))::jsonb, 1, 'purchase_product_id'),
          pg_temp.k('perejil')::text, 'el artículo elegido a mano («Es…»), si es del proveedor');
select is(pg_temp.preview(408, format('[{"name": "Otro", "list_price": 100, "vat_rate": 21, "purchase_product_id": "%s"}]',
                                      pg_temp.k('ajeno'))::jsonb, 1, 'purchase_product_id'),
          null, 'uno de otro proveedor no se toma');
select is(pg_temp.q(pg_temp.u(409), format('select purchasing.price_list_preview(%L, %L)::text', pg_temp.u(902),
                                           '[{"name": "Albahaca", "list_price": 1, "vat_rate": 21}]')),
          null, 'la cocinera no ve listas: nada');

-- ---------------------------------------------------------------------------
-- 3. Cargar con un artículo elegido a mano y aceptar con un precio en «Revisar»
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(408), format($s$select purchasing.create_price_list(%L, current_date, current_date,
            '[{"name": "Otro", "list_price": 100, "vat_rate": 21, "purchase_product_id": "%s"}]', null, 'Prueba')$s$,
            pg_temp.u(902), pg_temp.k('ajeno'))),
          'Ese artículo no es de este proveedor.', 'la carga rechaza un artículo de otro proveedor');
insert into ids
select 'nueva', (pg_temp.q(pg_temp.u(408), format($s$select purchasing.create_price_list(%L,
    (now() at time zone 'America/Argentina/Buenos_Aires')::date, (now() at time zone 'America/Argentina/Buenos_Aires')::date,
    '[{"name": "Albahaca", "sku": "FR007", "list_price": 19000, "vat_rate": 10.5},
      {"name": "Perejil crespo atado", "sku": "PX99", "list_price": 2100, "vat_rate": 21, "purchase_product_id": "%s"}]',
    null, 'Lista nueva de prueba') ->> 'price_list_id'$s$, pg_temp.u(902), pg_temp.k('perejil'))))::uuid;
select ok(pg_temp.k('nueva') is not null, 'Compras carga la lista');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.accept_price_list(%L, %L)', pg_temp.k('nueva'),
                                             'La revisé')),
          'Hay 1 precio para revisar (10 veces más o menos que en la lista anterior): confirmalo antes de aceptar.',
          'aceptar con un precio en «Revisar» pide confirmarlo');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.accept_price_list(%L, %L, true) ->> %L',
                                           pg_temp.k('nueva'), 'Confirmado con el proveedor', 'remembered')),
          '1', 'confirmado, se acepta y el artículo elegido a mano va a la cola con la sugerencia');
select is((select status::text from purchasing.price_lists where id = pg_temp.u(1302)), 'replaced',
          'la que estaba vigente queda reemplazada');
-- Lo que eligió Compras no se recuerda solo (decisión de Joaco, 2026-11-27): espera que el chef lo confirme.
insert into ids
select 'sugerido', id from purchasing.unmapped_articles
 where supplier_id = pg_temp.u(902) and raw_name = 'Perejil crespo atado' and status = 'pending'
   and suggested_product_id = pg_temp.k('perejil');
select ok(pg_temp.k('sugerido') is not null, 'en la cola, con el producto que sugirió Compras');
select is(purchasing.match_article(pg_temp.u(902), 'PX99', 'Perejil crespo atado'), null,
          'mientras el chef no lo confirma, la próxima lista no lo reconoce sola');
select is(pg_temp.q(pg_temp.u(413), format('select purchasing.link_article(%L, %L, %L) ->> %L', pg_temp.k('sugerido'),
                                           pg_temp.k('perejil'), 'Es el perejil de siempre', 'result')),
          'applied', 'el chef confirma la sugerencia');
select is(purchasing.match_article(pg_temp.u(902), 'PX99', 'Perejil crespo atado'), pg_temp.k('perejil'),
          'confirmado, la próxima lista reconoce el artículo sola, por su código y su nombre');
select is(pg_temp.q(pg_temp.u(408), format(
            'select review::text || %L || per_use_unit from purchasing.price_list_changes(%L) where purchase_product_id = %L',
            ' ', pg_temp.k('nueva'), pg_temp.k('albahaca'))),
          'true kg', 'la ficha muestra los mismos controles');

-- ---------------------------------------------------------------------------
-- 4. Corregir la vigente: versión nueva
-- ---------------------------------------------------------------------------
insert into ids
select 'v2', (pg_temp.q(pg_temp.u(408), format($s$select purchasing.correct_price_list(%L,
    '[{"name": "Albahaca", "sku": "FR007", "list_price": 1950, "vat_rate": 10.5},
      {"name": "Perejil crespo atado", "sku": "PX99", "list_price": 2100, "vat_rate": 21}]',
    'Corrección de prueba: la albahaca estaba mal tipeada') ->> 'price_list_id'$s$, pg_temp.k('nueva'))))::uuid;
select is((select version || ' ' || status || ' ' || (previous_version_id = pg_temp.k('nueva'))
             from purchasing.price_lists where id = pg_temp.k('v2')),
          '2 accepted true', 'la corrección es la versión 2, vigente y apunta a la que corrige');
select is((select status::text from purchasing.price_lists where id = pg_temp.k('nueva')), 'replaced',
          'la versión 1 queda reemplazada (en la historia)');
select is((select count(*)::int from purchasing.price_lists where supplier_id = pg_temp.u(902) and status = 'accepted'),
          1, 'una sola vigente por proveedor');
select ok(exists (select 1 from audit.audit_events e
                   where e.table_name = 'price_lists' and e.record_id = pg_temp.k('v2') and e.action = 'insert'
                     and e.reason = 'Corrección de prueba: la albahaca estaba mal tipeada'),
          'la versión nueva queda en la auditoría, con su motivo');
select is(pg_temp.msg(pg_temp.u(408), format($s$select purchasing.correct_price_list(%L,
            '[{"name": "Albahaca", "list_price": 1, "vat_rate": 21}]', 'Otra')$s$, pg_temp.k('nueva'))),
          'Solo se corrige la lista vigente: una recibida se corrige cargándola de nuevo.',
          'una reemplazada no se corrige');
select is(pg_temp.q(pg_temp.u(407), format($s$select purchasing.correct_price_list(%L,
            '[{"name": "Albahaca", "list_price": 1, "vat_rate": 21}]', 'Sin permiso') ->> 'result'$s$, pg_temp.k('v2'))),
          'denied', 'el Controller ve listas pero no las corrige');

-- ---------------------------------------------------------------------------
-- 5. Anular
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.void_price_list(%L, %L) ->> %L', pg_temp.k('v2'),
                                           'Se cargó por error', 'restored')),
          pg_temp.k('nueva')::text, 'anular la vigente devuelve la versión que corregía');
select is((select status || ' ' || voided_reason || ' ' || (deleted_at is null)
             from purchasing.price_lists where id = pg_temp.k('v2')),
          'voided Se cargó por error true', 'la anulada queda con su motivo y no se borra');
select is(pg_temp.msg(pg_temp.u(408), format('select purchasing.void_price_list(%L, %L)', pg_temp.k('v2'), 'Otra vez')),
          'Solo se anula una lista recibida o la vigente (esta está anulada).', 'no se anula dos veces');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.void_price_list(%L, %L) ->> %L', pg_temp.u(1305),
                                           'La cargamos dos veces', 'status')),
          'voided', 'una recibida también se anula');
select is(pg_temp.q(pg_temp.u(407), format('select purchasing.void_price_list(%L, %L) ->> %L', pg_temp.u(1303),
                                           'Sin permiso', 'result')),
          'denied', 'el Controller no anula');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from purchasing.price_list_list(p_status => ''voided'')'),
          '2', '«Anuladas» lista las dos');
select is(pg_temp.q(pg_temp.u(408), 'select coalesce(sum(total), 0)::text from purchasing.price_list_supplier_counts(''voided'')'),
          '2', 'y el panel cuenta lo mismo');
select ok(not exists (select 1 from purchasing.price_list_list(p_limit => 50) l where l.status = 'voided'),
          '«Todas» no muestra las anuladas');

-- Revisión de base: la cocinera no toca listas; anular la vigente (sin corrección) devuelve la anterior; una sola
-- vigente; la auditoría; costos intactos; corregir con «Revisar» sin confirmar.
select is(pg_temp.q(pg_temp.u(409), format('select purchasing.void_price_list(%L, %L) ->> %L', pg_temp.k('nueva'),
                                           'Sin permiso', 'result')),
          'denied', 'la cocinera no anula');
select is(pg_temp.q(pg_temp.u(409), format($s$select purchasing.correct_price_list(%L,
            '[{"name": "Albahaca", "list_price": 1, "vat_rate": 21}]', 'Sin permiso') ->> 'result'$s$, pg_temp.k('nueva'))),
          'denied', 'ni corrige');
select is(pg_temp.q(pg_temp.u(409), format('select count(*)::text from purchasing.price_list_changes(%L)',
                                           pg_temp.k('nueva'))),
          '0', 'ni ve los renglones');
select is(pg_temp.q(pg_temp.u(408), format('select purchasing.void_price_list(%L, %L) ->> %L', pg_temp.k('nueva'),
                                           'Esta también era de prueba', 'restored')),
          pg_temp.u(1302)::text, 'anular la vigente que no es una corrección devuelve la lista anterior');
select is((select count(*)::int from purchasing.price_lists where supplier_id = pg_temp.u(902) and status = 'accepted'),
          1, 'después de anular y restaurar, una sola vigente');
select is(purchasing.match_article(pg_temp.u(902), 'PX99', 'Perejil crespo atado'), pg_temp.k('perejil'),
          'lo que confirmó el chef sigue valiendo aunque se anule la lista');
select ok(exists (select 1 from audit.audit_events e
                   where e.table_name = 'price_lists' and e.record_id = pg_temp.k('nueva') and e.action = 'update'
                     and e.reason = 'Esta también era de prueba' and e.new_values ->> 'status' = 'voided'),
          'la anulación queda en la auditoría, con su motivo');
select is(pg_temp.msg(pg_temp.u(408), format($s$select purchasing.correct_price_list(%L,
            '[{"name": "Albahaca", "sku": "FR007", "list_price": 19000, "vat_rate": 10.5}]', 'Sin confirmar')$s$,
            pg_temp.u(1302))),
          'Hay 1 precio para revisar (10 veces más o menos que en la versión anterior): confirmalo antes de guardar.',
          'corregir con un precio en «Revisar» sin confirmarlo se rechaza');
select is((select count(*)::int from purchasing.price_lists where previous_version_id = pg_temp.u(1302)), 0,
          'y no deja la versión nueva a medias');
select is((select count(*) from costing.price_records), (select n from base_costs),
          'cargar, aceptar, corregir y anular listas no toca los costos');

-- ---------------------------------------------------------------------------
-- 6. Archivos de Excel y CSV
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from purchasing.document_parts(pg_temp.u(1)::text || '/price_lists/' || pg_temp.u(1305)
                                                          || '/' || gen_random_uuid() || '.xlsx'))
          and (select 'text/csv' = any (allowed_mime_types) from storage.buckets where id = 'purchasing-documents'),
          'el original en Excel o CSV se puede guardar con la lista');
select ok((select pg_get_constraintdef(oid) ~ 'xlsx\|csv' from pg_constraint
            where conname = 'attachments_storage_path_check'),
          'y la tabla de adjuntos acepta su ruta');

select * from finish();
rollback;
