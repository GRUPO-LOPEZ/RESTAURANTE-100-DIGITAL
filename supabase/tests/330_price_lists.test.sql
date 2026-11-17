-- Artículos de proveedor, cola de mapeo y listas de precios (Fase 3, Prompt 2, ADR-0052).
-- Personas del seed: Dirección 402, Chef de marca 405, Jefe de Cocina 406 (de un local), Controller 407, Compras 408,
-- Cocinera 409, Chef del grupo 413. Mapea quien tiene catalog.map_articles en cualquier alcance (Joaco, 2026-11-16).
-- Proveedores: Verdulería 901 (semanal), Frigorífico 902 (quincenal), Lácteos 903 (mensual), Almacén 904 (mensual).
-- Listas del seed: 1301 reemplazada y 1302 vigente (Frigorífico), 1303 vigente (Lácteos), 1304 vencida (Verdulería),
-- 1305 recibida (Almacén). En la cola: 1311 y 1312 (Almacén), 1313 (Lácteos).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(81);

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
-- Hoy en la Argentina, como recipes.today(), pero lo pueden usar los roles de prueba. Con pg_temp.today_ar() (UTC), las
-- listas «llegaban mañana» entre las 21 y las 24 de la Argentina y la base las rechazaba por fecha futura.
create function pg_temp.today_ar() returns date language sql as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date
$$;
grant execute on function pg_temp.u(int), pg_temp.today_ar() to authenticated;

create temp table counts (what text primary key, n bigint);
insert into counts values ('price_records', (select count(*) from costing.price_records));
grant select on counts to authenticated;

-- ---------------------------------------------------------------------------
-- Estructura y cálculos
-- ---------------------------------------------------------------------------
select has_table('purchasing', 'price_lists', 'existe purchasing.price_lists');
select has_table('purchasing', 'price_list_items', 'existe purchasing.price_list_items');
select has_table('purchasing', 'unmapped_articles', 'existe purchasing.unmapped_articles');
select has_table('purchasing', 'article_aliases', 'existe purchasing.article_aliases');
select has_table('purchasing', 'attachments', 'existe purchasing.attachments');
select is(purchasing.net_list_price(100, 15, 10, 0), 76.5000::numeric,
          'caso 5: 100 con 15 % y 10 % de bonificación da 76,50');
select is(purchasing.net_list_price(100, 15, 10, 5), 71.5000::numeric,
          'la bonificación en pesos por unidad se resta después de los porcentajes (P6)');
select is(purchasing.normalize_name('  Harina  000 x 25 kg. '), 'HARINA 000 X 25 KG',
          'el nombre se compara en mayúsculas, sin puntos ni espacios de más');
select is(purchasing.normalize_name('Lácteos ñoquis'), 'LACTEOS NOQUIS', 'y sin acentos');

-- ---------------------------------------------------------------------------
-- Vencimiento
-- ---------------------------------------------------------------------------
select ok(purchasing.price_list_expired_internal(pg_temp.u(1304)), 'la lista semanal aceptada hace 20 días venció');
select ok(not purchasing.price_list_expired_internal(pg_temp.u(1302)), 'la quincenal aceptada hace 5 días no venció');
select ok(not purchasing.price_list_expired_internal(pg_temp.u(1301)), 'una reemplazada no vence (no es la vigente)');
select ok(not purchasing.price_list_expired_internal(pg_temp.u(1305)), 'una recibida sin aceptar no vence');
-- Caso 7: el borde exacto. Semanal vigente desde hace 6 días: no venció; desde hace 7: venció.
update purchasing.price_lists set valid_from = recipes.today() - 6 where id = pg_temp.u(1304);
select ok(not purchasing.price_list_expired_internal(pg_temp.u(1304)), 'caso 7: semanal desde hace 6 días, todavía vale');
update purchasing.price_lists set valid_from = recipes.today() - 7 where id = pg_temp.u(1304);
select ok(purchasing.price_list_expired_internal(pg_temp.u(1304)), 'caso 7: semanal desde hace 7 días, venció');

select is(purchasing.notify_expired_price_lists(), 1, 'el aviso diario encuentra la lista vencida');
select is(purchasing.notify_expired_price_lists(), 0, 'y no vuelve a avisar la misma lista');
select is((select count(*)::int from core.notifications
            where recipient_user_id = pg_temp.u(408) and kind = 'price_list_expired'), 1,
          'Compras recibe un aviso de lista vencida');
select is((select count(*)::int from core.notifications
            where recipient_user_id = pg_temp.u(409) and kind = 'price_list_expired'), 0,
          'la Cocinera no');

-- ---------------------------------------------------------------------------
-- Una sola aceptada por proveedor
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ insert into purchasing.price_lists (group_id, supplier_id, received_on, valid_from, status, accepted_at)
     values (pg_temp.u(1), pg_temp.u(902), recipes.today(), recipes.today(), 'accepted', now()) $$,
  '23505', null, 'no puede haber dos listas aceptadas del mismo proveedor');

-- ---------------------------------------------------------------------------
-- Permisos de lectura
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from purchasing.price_lists'), '0',
          'la Cocinera no ve listas de precios');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from purchasing.price_list_items'), '0',
          'ni sus precios');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from purchasing.price_lists'), '5',
          'Compras ve las 5 listas');
select is(pg_temp.q(pg_temp.u(407), 'select count(*)::text from purchasing.price_lists'), '5',
          'el Controller también');
select is(pg_temp.q(pg_temp.u(405), 'select count(*)::text from purchasing.price_lists'), '0',
          'la Chef no ve listas de precios');
select is(pg_temp.q(pg_temp.u(405), 'select count(*)::text from purchasing.unmapped_articles where status = ''pending'''),
          '3', 'pero ve los 3 artículos de la cola');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from purchasing.unmapped_articles'), '0',
          'la Cocinera no ve la cola');
select is(pg_temp.q(pg_temp.u(408),
          'select count(*)::text from purchasing.price_list_list(null, ''expired'', 15, 0)'), '1',
          'el listado filtra las vencidas');

-- ---------------------------------------------------------------------------
-- Cargar una lista
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar(), pg_temp.today_ar(),
    '[{"name": "Lo que sea", "list_price": 10, "vat_rate": 21}]', null, 'Prueba')->>'result' $$),
  'denied', 'la Cocinera no carga listas');
select is(pg_temp.q(pg_temp.u(408), $$
  select (purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar(), pg_temp.today_ar(),
    jsonb_build_array(
      jsonb_build_object('name', (select description from catalog.purchase_products
                                   where supplier_id = pg_temp.u(904) and deleted_at is null order by code limit 1),
                         'list_price', 1000, 'bonus1_pct', 15, 'bonus2_pct', 10, 'vat_rate', 21),
      jsonb_build_object('name', 'Lentejas  secas x 5 kg.', 'sku', 'alm 990', 'list_price', 7300, 'vat_rate', 10.5)),
    'Lista de prueba', 'Llegó la lista del Almacén') - 'price_list_id')::text $$),
  '{"items": 2, "queued": 1, "result": "applied", "new_unmapped": 1}',
  'Compras carga una lista: reconoce un renglón y el otro va a la cola');
select is((select supplier_sku from purchasing.unmapped_articles where raw_name = 'Lentejas  secas x 5 kg.'), 'ALM990',
          'el código del proveedor se guarda sin espacios y en mayúsculas');
select ok((select count(*) from core.notifications
            where recipient_user_id = pg_temp.u(413) and kind = 'unmapped_article') >= 1,
          'el Chef del grupo recibe el aviso de artículos para mapear');
select is((select count(*)::int from core.notifications
            where recipient_user_id = pg_temp.u(408) and kind = 'unmapped_article'), 0,
          'Compras no se avisa a sí misma');
select is(pg_temp.q(pg_temp.u(408), $$
  select (purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar(), pg_temp.today_ar(),
    '[{"name": "LENTEJAS SECAS X 5 KG", "list_price": 7400, "vat_rate": 10.5}]', null, 'Otra lista')
    ->> 'new_unmapped') $$),
  '0', 'el mismo artículo con otra escritura se suma al pendiente que ya hay');
select is(pg_temp.msg(pg_temp.u(408), $$
  select purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar(), pg_temp.today_ar(),
    '[{"name": "Algo", "list_price": 100, "bonus1_pct": 50, "bonus2_pct": 50, "bonus_per_unit_amount": 30, "vat_rate": 21}]',
    null, 'Prueba') $$),
  'Con esas bonificaciones el precio neto queda en cero o negativo: revisá el renglón.',
  'un neto negativo se rechaza con un mensaje claro');
select is(pg_temp.msg(pg_temp.u(408), $$
  select purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar(), pg_temp.today_ar(),
    '[{"name": "Algo", "list_price": 100, "vat_rate": 19}]', null, 'Prueba') $$),
  'El IVA es 0; 2,5; 5; 10,5; 21 o 27 %.', 'una alícuota que no existe se rechaza');

-- ---------------------------------------------------------------------------
-- Resolver la cola
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$
  select purchasing.resolve_article(pg_temp.u(1311), pg_temp.u(827), 'bag', 1, 5000, 'g', '{}', 'Son garbanzos')
         ->> 'result' $$),
  'denied', 'Compras no mapea artículos');
select is(pg_temp.q(pg_temp.u(413), $$
  select purchasing.resolve_article(pg_temp.u(1311), pg_temp.u(827), 'bag', 1, 5000, 'g', '{}', 'Es una bolsa de 5 kg')
         ->> 'result' $$),
  'applied', 'el Chef del grupo resuelve un artículo: crea el producto de compra');
select is((select status::text from purchasing.unmapped_articles where id = pg_temp.u(1311)), 'resolved',
          'el artículo sale de la cola');
select ok((select p.supplier_id = pg_temp.u(904) and p.supplier_sku = 'ALM-881' and p.content_per_unit = 5000
                  and p.code ~ '^DEMO-ING-027-P[0-9]{2}$'
             from catalog.purchase_products p
             join purchasing.unmapped_articles a on a.purchase_product_id = p.id
            where a.id = pg_temp.u(1311)),
          'el producto queda del proveedor, con su código, su envase y un código automático');
select is((select count(*)::int from purchasing.price_list_items
            where unmapped_article_id = pg_temp.u(1311)), 0,
          'los renglones de lista que apuntaban al pendiente pasan al producto');
select is(purchasing.match_article(pg_temp.u(904), 'alm-881', 'cualquier nombre'),
          (select purchase_product_id from purchasing.unmapped_articles where id = pg_temp.u(1311)),
          'la próxima vez se reconoce solo, por el código');
select is(pg_temp.msg(pg_temp.u(413), $$
  select purchasing.resolve_article(pg_temp.u(1311), pg_temp.u(827), 'bag', 1, 5000, 'g', '{}', 'Otra vez') $$),
  'Otra persona ya resolvió este artículo: recargá la página.', 'un artículo resuelto no se resuelve dos veces');

-- «Es el mismo que…»: Lácteos renombró un producto.
-- Decisión de Joaco (2026-11-16): también mapean los chefs de una marca o de un local.
select is(pg_temp.q(pg_temp.u(409), $$
  select purchasing.discard_article(pg_temp.u(1313), 'Prueba') ->> 'result' $$),
  'denied', 'la Cocinera no mapea');
select is(pg_temp.q(pg_temp.u(406), $$
  select purchasing.link_article(pg_temp.u(1313),
           (select id from catalog.purchase_products where supplier_id = pg_temp.u(903) and deleted_at is null
             order by code limit 1), 'Es la misma ricota con otro nombre') ->> 'result' $$),
  'applied', 'el Jefe de Cocina de un local vincula un artículo a un producto que ya existe');
select ok((select count(*) from core.notifications
            where recipient_user_id = pg_temp.u(406) and kind = 'unmapped_article') >= 1,
          'y también le llegó el aviso de la cola');
select is(purchasing.match_article(pg_temp.u(903), null, 'RICOTA ENTERA POTE 500 G'),
          (select id from catalog.purchase_products where supplier_id = pg_temp.u(903) and deleted_at is null
            order by code limit 1),
          'el nombre nuevo queda guardado y se reconoce');
select is(pg_temp.msg(pg_temp.u(413), $$
  select purchasing.link_article((select id from purchasing.unmapped_articles where raw_name = 'Lentejas  secas x 5 kg.'),
           (select id from catalog.purchase_products where supplier_id = pg_temp.u(903) and deleted_at is null
             order by code limit 1), 'Prueba') $$),
  'Elegí un producto activo de este mismo proveedor.', 'no se vincula a un producto de otro proveedor');
select is(pg_temp.q(pg_temp.u(405), $$
  select purchasing.discard_article(pg_temp.u(1312), 'Es film, no se mapea') ->> 'result' $$),
  'applied', 'la Chef de una marca descarta un artículo');
select is((select status::text from purchasing.unmapped_articles where id = pg_temp.u(1312)), 'discarded',
          'queda descartado');

-- ---------------------------------------------------------------------------
-- Aceptar
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$
  select purchasing.accept_price_list(pg_temp.u(1305), 'La revisé') ->> 'result' $$),
  'applied', 'Compras acepta la lista recibida del Almacén');
select is(pg_temp.q(pg_temp.u(408), $$
  select (purchasing.accept_price_list(
            (select id from purchasing.price_lists where supplier_id = pg_temp.u(904) and status = 'received'
              order by created_at limit 1), 'La nueva') ->> 'replaced') = pg_temp.u(1305)::text $$),
  'true', 'aceptar otra lista del mismo proveedor reemplaza a la anterior, en la misma transacción');
select is((select status::text from purchasing.price_lists where id = pg_temp.u(1305)), 'replaced',
          'la anterior queda reemplazada');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'price_lists' and record_id = pg_temp.u(1305) and reason = 'La nueva'),
          'el reemplazo queda en la auditoría con su motivo');
-- Una lista más vieja que la vigente no se acepta.
insert into purchasing.price_lists (id, group_id, supplier_id, received_on, valid_from)
values (pg_temp.u(1399), pg_temp.u(1), pg_temp.u(902), recipes.today() - 30, recipes.today() - 30);
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.accept_price_list(pg_temp.u(1399), 'Vieja') $$),
          format('La lista vigente de este proveedor es más nueva (vale desde el %s).',
                 to_char(recipes.today() - 5, 'DD/MM/YYYY')),
          'no se acepta una lista más vieja que la vigente');
select is((select count(*) from costing.price_records), (select n from counts where what = 'price_records'),
          'caso 10: cargar y aceptar listas no toca los precios de costo');

-- ---------------------------------------------------------------------------
-- Variación entre listas
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(407), $$
  select string_agg(distinct change_pct::text, ',') from purchasing.price_list_changes(pg_temp.u(1302)) c
   join purchasing.price_list_items i on i.price_list_id = pg_temp.u(1302) and i.purchase_product_id = c.purchase_product_id
   where i.bonus_per_unit_amount = 0 $$),
  '8.00', 'la lista vigente del Frigorífico sube un 8 % contra la anterior');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from purchasing.price_list_changes(pg_temp.u(1302))'), '0',
          'la Cocinera no ve la variación');

-- ---------------------------------------------------------------------------
-- No va a recetas
-- ---------------------------------------------------------------------------
select ok(not catalog.ingredient_used_in_recipes(pg_temp.u(851)), 'el detergente (Limpieza) no va a recetas');
select is((select count(*)::int from catalog.search_components('detergente')), 0,
          'el buscador de componentes no lo ofrece');
-- El trigger, sobre el borrador 1211 (receta DEMO-PAS-06).
create function pg_temp.add_line(p_order int) returns void language sql as $$
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
  values (pg_temp.u(1), pg_temp.u(1211), p_order, pg_temp.u(851), 10, (select id from catalog.units where code = 'ml'))
$$;
select throws_ok($$ select pg_temp.add_line(98) $$, '23514',
  'Esa materia prima es de un rubro que no va a recetas (por ejemplo, Limpieza o Descartables).',
  'una línea nueva con una materia prima de Limpieza se rechaza');
-- Si la receta ya la usaba (se cargó antes de marcar el rubro), una línea más de la misma sigue.
update catalog.ingredient_categories set used_in_recipes = true where code = 'MP-LIM' and group_id = pg_temp.u(1);
select lives_ok($$ select pg_temp.add_line(98) $$, 'antes de marcar el rubro, la receta la usa');
update catalog.ingredient_categories set used_in_recipes = false where code = 'MP-LIM' and group_id = pg_temp.u(1);
select lives_ok($$ select pg_temp.add_line(97) $$,
  'lo que la receta ya usaba sigue (una versión nueva o una variante copian sus líneas)');
select lives_ok($$ update recipes.recipe_components set quantity = 20
                    where recipe_version_id = pg_temp.u(1211) and line_order = 98 $$,
  'cambiar la cantidad de una línea que ya estaba no se rechaza');
select is(pg_temp.q(pg_temp.u(405), $$
  select recipes.set_category_used_in_recipes(
           (select id from catalog.ingredient_categories where code = 'MP-LIM' and group_id = pg_temp.u(1)), true,
           'Prueba') ->> 'result' $$),
  'denied', 'la Chef no cambia si un rubro va a recetas');
select is(pg_temp.q(pg_temp.u(408), $$
  select recipes.set_category_used_in_recipes(
           (select id from catalog.ingredient_categories where code = 'MP-LIM' and group_id = pg_temp.u(1)), true,
           'Usamos un desengrasante en una preparación') ->> 'result' $$),
  'applied', 'Compras sí, con motivo');

-- ---------------------------------------------------------------------------
-- Adjuntos
-- ---------------------------------------------------------------------------
-- 1399 es una lista recibida (sin aceptar) del Frigorífico; 1302 es la aceptada.
select is(pg_temp.q(pg_temp.u(408), format($$ select purchasing.can_upload_document(%L)::text $$,
          '00000000-0000-4000-8000-000000000001/price_lists/00000000-0000-4000-8000-000000001399/'
          || '00000000-0000-4000-8000-00000000abcd.pdf')),
          'true', 'Compras puede subir el archivo de una lista recibida de su grupo');
select is(pg_temp.q(pg_temp.u(409), format($$ select purchasing.can_upload_document(%L)::text $$,
          '00000000-0000-4000-8000-000000000001/price_lists/00000000-0000-4000-8000-000000001399/'
          || '00000000-0000-4000-8000-00000000abcd.pdf')),
          'false', 'la Cocinera no');
select is(pg_temp.q(pg_temp.u(408), format($$ select purchasing.can_upload_document(%L)::text $$,
          '00000000-0000-4000-8000-000000000001/price_lists/00000000-0000-4000-8000-000000001302/'
          || '00000000-0000-4000-8000-00000000abcd.pdf')),
          'false', 'a una lista ya aceptada no se le suman archivos');
select is(pg_temp.q(pg_temp.u(408), format($$ select purchasing.can_upload_document(%L)::text $$,
          '00000000-0000-4000-8000-000000000099/price_lists/00000000-0000-4000-8000-000000001399/'
          || '00000000-0000-4000-8000-00000000abcd.pdf')),
          'false', 'ni a la carpeta de otro grupo');
select is(pg_temp.msg(pg_temp.u(408), $$ select purchasing.add_price_list_attachment(pg_temp.u(1399),
          '00000000-0000-4000-8000-000000000001/price_lists/00000000-0000-4000-8000-000000001399/'
          || '00000000-0000-4000-8000-00000000abcd.pdf', 1::smallint, 'Archivo') $$),
          'El archivo no está subido en la carpeta de esta lista.',
          'no se registra un archivo que no está subido');
insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, storage_path)
values (pg_temp.u(1), 'price_lists', pg_temp.u(1399), 'price_list',
        '00000000-0000-4000-8000-000000000001/price_lists/00000000-0000-4000-8000-000000001399/'
        || '00000000-0000-4000-8000-00000000abce.pdf');
select throws_ok($$ update purchasing.attachments set page = 2 where source_id = pg_temp.u(1399) $$, '42501',
  'Un archivo adjunto no se cambia ni se borra.', 'un adjunto no se cambia');
select throws_ok($$ delete from purchasing.attachments where source_id = pg_temp.u(1399) $$, '42501',
  'Un archivo adjunto no se cambia ni se borra.', 'ni se borra');

-- ---------------------------------------------------------------------------
-- Revisiones (2026-11-16)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$
  select (purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar(), pg_temp.today_ar(),
    '[{"name": "Rollo de film 30 cm", "list_price": 4300, "vat_rate": 21}]', null, 'Otra lista') - 'price_list_id')::text $$),
  '{"items": 1, "queued": 0, "result": "applied", "new_unmapped": 0}',
  'un artículo descartado no vuelve a la cola ni avisa');
select is(pg_temp.msg(pg_temp.u(408), $$
  select purchasing.create_price_list(pg_temp.u(904), pg_temp.today_ar() + 3, pg_temp.today_ar() + 3,
    '[{"name": "Algo", "list_price": 10, "vat_rate": 21}]', null, 'Prueba') $$),
  'La fecha en que llegó la lista no puede ser futura.', 'una lista no llega en una fecha futura');
select is(pg_temp.msg(pg_temp.u(408), $$
  select purchasing.create_price_list(pg_temp.u(902), pg_temp.today_ar(), pg_temp.today_ar(),
    jsonb_build_array(jsonb_build_object('name', 'Uno', 'sku', (select supplier_sku from catalog.purchase_products where supplier_id = pg_temp.u(902) and supplier_sku is not null order by code limit 1), 'list_price', 10, 'vat_rate', 21),
                      jsonb_build_object('name', 'Otro', 'sku', (select supplier_sku from catalog.purchase_products where supplier_id = pg_temp.u(902) and supplier_sku is not null order by code limit 1), 'list_price', 11, 'vat_rate', 21)),
    null, 'Prueba') $$),
  'Dos renglones de la lista son el mismo artículo del proveedor: dejá uno solo.',
  'el mismo artículo dos veces en una lista se rechaza');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'purchase_products' and action = 'insert' and reason = 'Es una bolsa de 5 kg'),
          'el producto creado al mapear queda en la auditoría con su motivo');
select ok(exists (select 1 from audit.audit_events
                   where table_name = 'unmapped_articles' and record_id = pg_temp.u(1313)
                     and reason = 'Es la misma ricota con otro nombre'),
          'vincular queda en la auditoría con su motivo');
select is(pg_temp.q(pg_temp.u(409), $$ select purchasing.price_list_expired(pg_temp.u(1304))::text $$), 'false',
          'la Cocinera no puede preguntar si una lista venció');
-- El historial oculta las listas a quien no las ve, aunque vea costos (el Chef del grupo).
create function pg_temp.hidden_for(p_user uuid) returns text language plpgsql as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  v := core.hide_payment('purchasing', 'price_list_items', pg_temp.u(1), '{"list_price": 100, "bonus1_pct": 10}') ->> 'bonus1_pct';
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
select is(pg_temp.hidden_for(pg_temp.u(413)), '[oculto]', 'el historial le oculta las bonificaciones al Chef');
select is(pg_temp.hidden_for(pg_temp.u(408)), '10', 'a Compras, no');

select * from finish();
rollback;
