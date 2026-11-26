-- Prueba de la Fase 3 para Soy en staging: listas de precios, órdenes de compra, recepciones, facturas y pagos.
-- SOLO DATOS INVENTADOS: CUIT ficticios, números, CAE e importes de prueba. Nunca una factura real.
-- Lo corre el flujo "Publicar en staging" de GitHub Actions, a pedido, con psql 15 o más, DESPUÉS de
-- demo-recipes.sql (usa sus 3 proveedores ficticios y sus materias primas, en Demo Pastas Centro):
--   FILES_OUT=/tmp/fotos.txt psql -X --no-password -f supabase/staging/demo-purchasing.sql "$STAGING_DB_URL"
--
-- Todo se carga con las MISMAS funciones que usa la app y con la sesión de cada persona de prueba: Compras carga las
-- listas, las facturas y los pagos; la cocinera pide; el Gerente recibe; la Controller da las facturas por conformes
-- (otra persona que la que aceptó la lista, como pide el circuito). Así cada paso pasa por el control de permisos de
-- esas funciones (un «sin permiso» corta todo), los controles de la factura, la doble firma y la auditoría. No pasa por
-- las políticas RLS de las tablas: el script corre como postgres. Cada motivo lleva la marca de la prueba.
-- Las órdenes y las recepciones quedan con la fecha de hoy y las facturas con fechas de hasta 20 días atrás (para que
-- haya vencidas y precios que cambian): algunas facturas quedan antes que su recepción. Es de la prueba, no un error.
--
-- Quedan tres tareas para Soy (los pasos de la compuerta de la Fase 3, docs/guias/prueba-fase-3-soy.md):
--   1. pagar en dos partes la factura del Frigorífico que vence en 5 días;
--   2. confirmar el efectivo que se pagó al recibir la verdura (está «para confirmar»);
--   3. dar por conforme la factura de esa verdura: el efectivo confirmado se le aplica solo.
--
-- Fotos: cada comprobante queda registrado en Storage (storage.objects) con la ruta que pide la app, todavía sin
-- archivo (la app exige que la foto esté antes de adjuntarla). El flujo después borra ese registro vacío y sube en su
-- lugar la imagen «FACTURA DE PRUEBA» (supabase/staging/factura-de-prueba.jpg), con la CLI y la lista de rutas que este
-- script escribe en el archivo de la variable de entorno FILES_OUT. Sin FILES_OUT, no escribe la lista.
--
-- Se puede correr más de una vez: si ya se cargó, no cambia nada y la lista trae solo las fotos que todavía no tienen
-- archivo (por si la subida se cortó). Si falta la prueba de la Fase 2 o choca con algo, frena sin tocar nada y dice qué.
-- Con DRY_RUN definida (con cualquier valor, también 0) hace todo y al final lo deshace (rollback).

\set ON_ERROR_STOP on

\getenv run_id GITHUB_RUN_ID
\getenv dry_run DRY_RUN
\getenv files_out FILES_OUT
\if :{?run_id}
  \set change_reason 'Prueba de la Fase 3 para Soy (corrida ' :run_id ' de GitHub Actions)'
\else
  \set change_reason 'Prueba de la Fase 3 para Soy (a mano)'
\endif

-- Las rutas de las fotos de la prueba, para subir los archivos (también si ya estaba cargada).
create temporary table pru_files (path text primary key);

select exists (select 1 from purchasing.price_lists
                where group_id = '00000000-0000-4000-8000-000000000001' and deleted_at is null
                  and notes = 'Prueba de la Fase 3 para Soy') as purchasing_loaded \gset
\if :purchasing_loaded
  \echo 'La prueba de la Fase 3 ya estaba cargada: no se cambia nada.'
  -- Solo las fotos de los comprobantes de los 3 proveedores de la prueba que todavía no tienen archivo: nunca las que
  -- alguien cargó a mano en el Grupo Demo.
  insert into pru_files
  select a.storage_path
    from purchasing.attachments a
    join catalog.suppliers s
      on s.group_id = a.group_id and s.tax_id in ('30500000119', '30500000127', '30500000135')
     and s.id = case a.source_table
                  when 'receipts' then (select supplier_id from purchasing.receipts where id = a.source_id)
                  when 'invoices' then (select supplier_id from purchasing.invoices where id = a.source_id)
                  when 'credit_debit_notes' then (select i.supplier_id from purchasing.credit_debit_notes n
                                                    join purchasing.invoices i on i.id = n.invoice_id
                                                   where n.id = a.source_id)
                  when 'payments' then (select supplier_id from purchasing.payments where id = a.source_id)
                end
   where a.group_id = '00000000-0000-4000-8000-000000000001'
     and not exists (select 1 from storage.objects o
                      where o.bucket_id = 'purchasing-documents' and o.name = a.storage_path
                        and o.metadata ->> 'size' is not null);
\else

begin;

select set_config('pru.reason', :'change_reason', true);

create function pg_temp.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true)
$$;

-- Las funciones de la app no dan error cuando falta un permiso: devuelven {"result": "denied"}. Acá eso corta todo.
create function pg_temp.ok(p_res jsonb, p_step text) returns jsonb language plpgsql as $$
begin
  if p_res is null or p_res ->> 'result' = 'denied' then
    raise exception 'No se pudo %: %. No se cargó nada.', p_step, coalesce(p_res ->> 'message', 'sin respuesta');
  end if;
  return p_res;
end
$$;

-- El motivo de cada paso, siempre con la marca de la prueba (para separarlo en la historia de lo que haga una persona).
create function pg_temp.why(p_text text) returns text language sql as $$
  select current_setting('pru.reason') || ': ' || p_text
$$;

-- Una foto de prueba: el registro en Storage con la ruta que pide la app (<grupo>/<tabla>/<registro>/<uuid>.jpg), a
-- nombre de la sesión de ese momento (la app exige que sea de quien la adjunta). El archivo lo sube el flujo después:
-- borra este registro y sube la imagen, así que el archivo final queda sin dueño y sin la marca 'pru' (la lectura va
-- por el permiso sobre el comprobante, no por el dueño).
create function pg_temp.photo(p_table text, p_id uuid) returns text language plpgsql as $$
declare
  v_path text := format('00000000-0000-4000-8000-000000000001/%s/%s/%s.jpg', p_table, p_id, gen_random_uuid());
begin
  insert into storage.objects (bucket_id, name, owner_id, metadata)
  values ('purchasing-documents', v_path, (select auth.uid())::text,
          '{"mimetype": "image/jpeg", "pru": "fase-3"}');
  insert into pru_files values (v_path);
  return v_path;
end
$$;

-- Los productos de compra de la Fase 2 (PRU-001 a PRU-028), por número.
create function pg_temp.product(p_n int) returns uuid language sql as $$
  select id from catalog.purchase_products
   where group_id = '00000000-0000-4000-8000-000000000001' and code = format('PRU-%s', lpad(p_n::text, 3, '0'))
     and deleted_at is null
$$;

-- Los renglones de una OC: producto y cantidad (en envases).
create function pg_temp.lines(p_items int[][]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('purchase_product_id', pg_temp.product(p_items[i][1]), 'quantity', p_items[i][2])
                   order by i)
    from generate_subscripts(p_items, 1) i
$$;

-- Recibir una OC entera (o con un faltante en el primer renglón), con las dos fotos que pide la recepción.
create function pg_temp.receive(p_order uuid, p_short boolean, p_paper purchasing.paper_kind, p_number text,
                                p_cash numeric) returns uuid language plpgsql as $$
declare
  v_receipt uuid := (pg_temp.ok(purchasing.start_receipt(p_order), 'empezar una recepción') ->> 'receipt_id')::uuid;
  v_lines   jsonb;
begin
  perform pg_temp.ok(purchasing.add_receipt_attachment(v_receipt, pg_temp.photo('receipts', v_receipt),
                                                       'receipt_original', 1::smallint), 'adjuntar la foto de una recepción');
  perform pg_temp.ok(purchasing.add_receipt_attachment(v_receipt, pg_temp.photo('receipts', v_receipt),
                                                       'receipt_signed', 1::smallint), 'adjuntar la foto de una recepción');
  select jsonb_agg(case when p_short and l.line_order = 1
                        then jsonb_build_object('purchase_order_line_id', l.id, 'ok', false, 'issue', 'missing',
                                                'received_quantity', l.quantity - 1, 'note', 'Faltó un envase')
                        else jsonb_build_object('purchase_order_line_id', l.id, 'ok', true) end
                   order by l.line_order) into v_lines
    from purchasing.purchase_order_lines l where l.purchase_order_id = p_order and l.deleted_at is null;
  perform pg_temp.ok(purchasing.close_receipt(v_receipt, p_paper, p_number, v_lines, p_cash,
                                              pg_temp.why(case when p_short then 'faltó un envase del primer renglón'
                                                               else 'llegó todo' end)), 'cerrar una recepción');
  return v_receipt;
end
$$;

-- Las líneas de una factura, tal como están, para cambiarlas y volver a guardarlas.
create function pg_temp.invoice_lines(p_invoice uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'line_class', l.line_class, 'purchase_product_id', l.purchase_product_id,
           'purchase_order_line_id', l.purchase_order_line_id, 'raw_name', l.raw_name, 'supplier_sku', l.supplier_sku,
           'units', l.units, 'billed_quantity', l.billed_quantity, 'list_price', l.list_price,
           'bonus1_pct', l.bonus1_pct, 'bonus2_pct', l.bonus2_pct, 'bonus_per_unit_amount', l.bonus_per_unit_amount,
           'unit_price', l.unit_price, 'vat_rate', l.vat_rate, 'is_exempt', l.is_exempt,
           'internal_tax_amount', l.internal_tax_amount, 'line_amount', l.line_amount)) order by l.line_order), '[]')
    from purchasing.invoice_lines l where l.invoice_id = p_invoice and l.deleted_at is null
$$;

-- El pie que cierra con las líneas: en A, neto + IVA por línea; en las demás, el importe final.
create function pg_temp.invoice_footer(p_invoice uuid) returns jsonb language sql as $$
  select jsonb_build_object(
           'net_amount', x.net, 'exempt_amount', x.exempt, 'vat_amount', x.vat, 'internal_tax_amount', x.internal,
           'perception_amount', x.perception, 'total_amount', x.net + x.exempt + x.vat + x.internal + x.perception)
    from (select coalesce(sum(l.line_amount) filter (where not l.is_exempt), 0) as net,
                 coalesce(sum(l.line_amount) filter (where l.is_exempt), 0) as exempt,
                 case when purchasing.invoice_is_a(i.invoice_class)
                      then coalesce(sum(round(l.line_amount * coalesce(l.vat_rate, 0) / 100, 2)), 0) else 0 end as vat,
                 coalesce(sum(l.internal_tax_amount), 0) as internal,
                 coalesce((select sum(t.tax_amount) from purchasing.invoice_taxes t
                            where t.invoice_id = i.id and t.deleted_at is null), 0) as perception
            from purchasing.invoices i
            left join purchasing.invoice_lines l on l.invoice_id = i.id and l.deleted_at is null
           where i.id = p_invoice
           group by i.id, i.invoice_class) x
$$;

-- Una factura de una OC recibida: la crea Compras con las líneas que propone la app (lo recibido, al precio de la
-- lista), le suma la foto, le pone el pie y la controla. p_extra: cuánto de más por envase cobra en la primera línea.
create function pg_temp.invoice(p_supplier uuid, p_order uuid, p_class text, p_pos int, p_number int, p_cae text,
                                p_issued date, p_extra numeric, p_reason text) returns uuid language plpgsql as $$
declare
  v_invoice uuid;
  v_lines   jsonb;
begin
  v_invoice := (purchasing.create_invoice(p_supplier, '00000000-0000-4000-8000-000000000201', array[p_order],
                  jsonb_build_object('invoice_class', p_class, 'point_of_sale', p_pos, 'number', p_number,
                                     'authorization_kind', 'cae', 'authorization_code', p_cae,
                                     'issuer_tax_id', (select tax_id from catalog.suppliers where id = p_supplier),
                                     'receiver_tax_id', (select le.tax_id from org.restaurants r
                                                          join org.legal_entities le on le.id = r.legal_entity_id
                                                         where r.id = '00000000-0000-4000-8000-000000000201'),
                                     'issued_on', p_issued), pg_temp.why(p_reason)) ->> 'invoice_id')::uuid;
  if v_invoice is null then
    raise exception 'No se pudo crear la factura % (%).', p_number, p_reason;
  end if;
  perform pg_temp.ok(purchasing.add_invoice_attachment('invoices', v_invoice, pg_temp.photo('invoices', v_invoice),
                                                       1::smallint), 'adjuntar la foto de una factura');
  if p_extra <> 0 then
    v_lines := pg_temp.invoice_lines(v_invoice);
    v_lines := jsonb_set(jsonb_set(v_lines, '{0,unit_price}',
                                   to_jsonb((v_lines -> 0 ->> 'unit_price')::numeric + p_extra)),
                         '{0,line_amount}', to_jsonb((v_lines -> 0 ->> 'line_amount')::numeric
                                                     + p_extra * (v_lines -> 0 ->> 'billed_quantity')::numeric));
    perform pg_temp.ok(purchasing.save_invoice(v_invoice, '{}', v_lines, '[]', pg_temp.why('las líneas como en el papel')),
                       'guardar las líneas de una factura');
  end if;
  perform pg_temp.ok(purchasing.save_invoice(v_invoice, pg_temp.invoice_footer(v_invoice), null, null,
                                             pg_temp.why('el pie como en el papel')), 'guardar el pie de una factura');
  perform pg_temp.ok(purchasing.run_invoice_checks(v_invoice), 'controlar una factura');
  return v_invoice;
end
$$;

create temporary table pru_ids (kind text, n text, id uuid) on commit drop;

do $$
declare
  v_group    constant uuid := '00000000-0000-4000-8000-000000000001';
  v_centro   constant uuid := '00000000-0000-4000-8000-000000000201';  -- Demo Pastas Centro
  v_admin    constant uuid := '00000000-0000-4000-8000-000000000401';  -- Sofía, Superadministradora (grupo)
  v_manager  constant uuid := '00000000-0000-4000-8000-000000000404';  -- Gonzalo, Gerente de Demo Pastas Centro
  v_ctrl     constant uuid := '00000000-0000-4000-8000-000000000407';  -- Camila, Controller (grupo)
  v_buyer    constant uuid := '00000000-0000-4000-8000-000000000408';  -- Pablo, Compras (grupo)
  v_cook     constant uuid := '00000000-0000-4000-8000-000000000409';  -- Lucía, cocinera de Demo Pastas Centro
  v_today    constant date := recipes.today();
  v_verdu    uuid;
  v_frigo    uuid;
  v_distri   uuid;
  v_missing  text;
  v_res      jsonb;
  v_list     uuid;
  v_order    uuid;
  v_invoice  uuid;
  v_payment  uuid;
  v_account  uuid;
  v_diff     numeric;
  r          record;
begin
  -- Guardas: la prueba de la Fase 2, las personas de prueba con su rol y el local con su razón social.
  select id into v_verdu  from catalog.suppliers where group_id = v_group and tax_id = '30500000119' and deleted_at is null;
  select id into v_frigo  from catalog.suppliers where group_id = v_group and tax_id = '30500000127' and deleted_at is null;
  select id into v_distri from catalog.suppliers where group_id = v_group and tax_id = '30500000135' and deleted_at is null;
  if v_verdu is null or v_frigo is null or v_distri is null
     or (select count(*) from catalog.purchase_products where group_id = v_group and code like 'PRU-%'
                                                          and deleted_at is null and is_active) <> 28 then
    raise exception 'Falta la prueba de la Fase 2 (proveedores y materias primas): primero corré «Cargar materias primas, precios y recetas de prueba».';
  end if;

  select string_agg(x.who, ', ') into v_missing
    from (values (v_admin, 'superadmin', null::uuid, 'Superadministradora'), (v_buyer, 'purchasing', null, 'Compras'),
                 (v_ctrl, 'controller', null, 'Controller'),
                 (v_manager, 'restaurant_manager', v_centro, 'Gerente de Demo Pastas Centro'),
                 (v_cook, 'cook', v_centro, 'Cocinera de Demo Pastas Centro')) as x (id, role, place, who)
   where not exists (select 1 from core.user_role_assignments a join core.roles ro on ro.id = a.role_id
                      where a.user_id = x.id and ro.code = x.role and a.group_id = v_group
                        and a.restaurant_id is not distinct from x.place and a.deleted_at is null
                        and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now()))
      or not exists (select 1 from core.user_profiles u
                      where u.id = x.id and u.status = 'active' and u.deleted_at is null
                        and (u.locked_until is null or u.locked_until <= now()));
  if v_missing is not null then
    raise exception 'Faltan personas de prueba activas y con su rol: %. Cargá primero demo-data.sql.', v_missing;
  end if;

  if not exists (select 1 from org.restaurants where id = v_centro and status = 'active' and deleted_at is null
                                                 and legal_entity_id is not null) then
    raise exception 'Demo Pastas Centro tiene que estar activo y con razón social (la pone la prueba de la Fase 2).';
  end if;
  if exists (select 1 from purchasing.purchase_orders where supplier_id in (v_verdu, v_frigo, v_distri))
     or exists (select 1 from purchasing.invoices where supplier_id in (v_verdu, v_frigo, v_distri))
     or exists (select 1 from purchasing.price_lists where supplier_id in (v_verdu, v_frigo, v_distri)) then
    raise exception 'Los proveedores de la prueba ya tienen listas, órdenes o facturas cargadas a mano. No se cargó nada.';
  end if;

  -- 0. Preparación. Sin código de local no se pueden hacer órdenes de compra (P3): si a Demo Pastas Centro le falta,
  --    la Superadministradora le pone PCE (o PCE1, si PCE ya es de otro local del grupo).
  if (select code from org.restaurants where id = v_centro) is null then
    perform pg_temp.as_user(v_admin);
    perform org.update_restaurant(v_centro, jsonb_build_object('code',
              case when exists (select 1 from org.restaurants where group_id = v_group and code = 'PCE')
                   then 'PCE1' else 'PCE' end), pg_temp.why('código del local para las órdenes de compra'));
  end if;

  --    Las cajas y cuentas de la razón social de Demo Pastas Centro, para las órdenes de pago (ADR-0070): las carga la
  --    Superadministradora, si no tiene ninguna. Datos inventados (el CBU no es de nadie).
  if not exists (select 1 from org.legal_entity_accounts a join org.restaurants r on r.legal_entity_id = a.legal_entity_id
                  where r.id = v_centro and a.deleted_at is null) then
    perform pg_temp.as_user(v_admin);
    perform pg_temp.ok(org.save_legal_entity_accounts(
              (select legal_entity_id from org.restaurants where id = v_centro),
              '[{"kind": "cash", "name": "Caja de prueba"},
                {"kind": "bank", "name": "Cuenta de prueba", "bank": "Banco de Prueba",
                 "cbu": "0000003100099999999999", "alias": "PRUEBA.CUENTA.OP"}]'::jsonb,
              pg_temp.why('cajas y cuentas para las órdenes de pago')), 'cargar las cajas y cuentas');
  end if;

  --    Compras completa la ficha de los 3 proveedores: cómo factura, cada cuánto manda la lista, cómo se le paga y sus
  --    cuentas (alias inventados). Pisa las condiciones que tuvieran; las cuentas se suman.
  if exists (select 1 from purchasing.supplier_payment_accounts
              where supplier_id in (v_verdu, v_frigo, v_distri) and deleted_at is null) then
    raise notice 'Los proveedores de la prueba ya tenían cuentas de pago: se suman las de la prueba y se reemplazan sus condiciones.';
  end if;
  perform pg_temp.as_user(v_buyer);
  for r in select * from (values
             (v_verdu, 'pedidos.verduleria@ejemplo.test', '["b"]'::jsonb, 'weekly', '{"payment_terms": "cash"}'::jsonb, '[]'::jsonb),
             (v_frigo, 'pedidos.frigorifico.prueba@ejemplo.test', '["a"]', 'biweekly', '{"payment_terms": "account", "payment_days": 15}',
              '[{"method": "transfer", "alias": "corral.prueba", "bank": "Banco de Prueba", "holder_name": "Frigorífico El Corral (ficticio)"}]'),
             (v_distri, 'pedidos.distribuidora@ejemplo.test', '["a"]', 'monthly', '{"payment_terms": "account", "payment_days": 30}',
              '[{"method": "transfer", "alias": "trattoria.prueba", "bank": "Banco de Prueba", "holder_name": "Distribuidora Trattoria (ficticia)"}, {"method": "check"}]'))
             as x (id, target, billing, frequency, terms, accounts) loop
    v_res := purchasing.save_supplier_sheet(r.id, purchasing.supplier_sheet_stamp_internal(r.id),
               jsonb_build_object('terms', jsonb_build_object('billing_modes', r.billing,
                                                              'order_days', '[1, 2, 3, 4, 5, 6]'::jsonb,
                                                              'delivery_days', '[1, 2, 3, 4, 5, 6]'::jsonb,
                                                              'receiving_from', '07:00', 'receiving_to', '12:00',
                                                              'po_channel', 'email',
                                                              'po_channel_target', r.target,
                                                              'price_list_frequency', r.frequency,
                                                              'requires_po_approval', false),
                                  'payment_terms', r.terms, 'accounts', r.accounts),
               pg_temp.why('ficha del proveedor de prueba'));
    perform pg_temp.ok(v_res, 'completar la ficha de un proveedor');
  end loop;

  -- 1. Listas de precios (Compras las carga y las acepta). Los renglones se reconocen por la descripción del producto.
  --    Frigorífico: la de hace 25 días y la vigente, 8 % más cara (el gráfico «Cómo subieron los insumos»).
  --    Verdulería: la de hace 3 días (semanal, vigente).
  --    Distribuidora: la de hace 40 días (mensual, vencida: alarma) y una nueva recibida, sin aceptar, con un artículo
  --    que el sistema no conoce (va a la cola «sin mapear»).
  for r in select * from (values
             ('frigo-1', v_frigo, 25, array[10, 11, 12, 13], 1.00, false, true),
             ('frigo-2', v_frigo, 6, array[10, 11, 12, 13], 1.08, false, true),
             ('verdu-1', v_verdu, 3, array[1, 2, 3, 4, 5, 6, 7, 8, 9], 1.00, false, true),
             ('distri-1', v_distri, 40, array[14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27], 1.00, false, true),
             ('distri-2', v_distri, 1, array[14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27], 1.05, true, false))
             as x (n, supplier, days, products, factor, unknown, accept) loop
    -- El precio de lista: el del envase de la Fase 2 (precio del grupo). La Verdulería factura B y su lista viene con
    -- IVA incluido (así su factura y el efectivo que se le paga al recibir cierran justos); las demás, sin IVA.
    select jsonb_agg(jsonb_build_object('name', p.description,
                                        'list_price', case when r.supplier = v_verdu
                                                           then round(pr.gross_package_price * r.factor, 2)
                                                           else round(pr.net_package_price * r.factor, 2) end,
                                        'vat_rate', 21, 'includes_vat', r.supplier = v_verdu)
                     order by p.code)
           || case when r.unknown
                   then jsonb_build_array(jsonb_build_object('name', 'Aceitunas negras, balde de 2 kg (ficticio)',
                                                             'sku', 'TRA-ACE-2', 'list_price', 15800, 'vat_rate', 21))
                   else '[]'::jsonb end
      into v_res
      from unnest(r.products) as k (n)
      join catalog.purchase_products p on p.id = pg_temp.product(k.n)
      join lateral (select net_package_price, gross_package_price from costing.price_records x
                     where x.purchase_product_id = p.id and x.scope_type = 'group' and x.deleted_at is null
                     order by x.valid_from desc limit 1) pr on true;
    v_list := (pg_temp.ok(purchasing.create_price_list(r.supplier, v_today - r.days, v_today - r.days, v_res,
                                                       'Prueba de la Fase 3 para Soy', pg_temp.why('lista de precios')),
                          'cargar una lista de precios') ->> 'price_list_id')::uuid;
    if r.accept then
      perform pg_temp.ok(purchasing.accept_price_list(v_list, pg_temp.why('lista revisada')), 'aceptar una lista');
    end if;
    insert into pru_ids values ('list', r.n, v_list);
  end loop;

  -- 2. Órdenes de compra: las pide la cocinera de Centro.
  perform pg_temp.as_user(v_cook);
  for r in select * from (values
             ('frigo-1', v_frigo, array[[10, 2], [11, 1]], 'Carne de hace tres semanas'),
             ('frigo-2', v_frigo, array[[10, 3], [12, 2]], 'Carne de hace diez días'),
             ('frigo-3', v_frigo, array[[11, 2], [13, 1]], 'Carne de esta semana'),
             ('frigo-4', v_frigo, array[[10, 2], [12, 2]], 'Carne para el fin de semana'),
             ('verdu-1', v_verdu, array[[1, 3], [5, 2], [7, 2]], 'Verdura de la semana'),
             ('verdu-2', v_verdu, array[[2, 1], [4, 2], [6, 3]], 'Verdura que se paga al recibir'),
             ('distri-1', v_distri, array[[14, 1], [19, 2], [22, 1]], 'Almacén del mes'),
             ('distri-2', v_distri, array[[16, 1], [23, 4]], 'Reposición de almacén'))
             as x (n, supplier, items, notes) loop
    v_order := (pg_temp.ok(purchasing.save_order_draft(null, v_centro, r.supplier, pg_temp.lines(r.items), null, null,
                                                       pg_temp.why(r.notes)), 'armar una orden de compra')
                ->> 'purchase_order_id')::uuid;
    perform pg_temp.ok(purchasing.submit_order(v_order, pg_temp.why(r.notes)), 'mandar una orden de compra');
    insert into pru_ids values ('order', r.n, v_order);
  end loop;

  -- 3. Recepciones: las hace el Gerente de Centro. La de almacén llega con un faltante; la verdura que se paga al
  --    recibir deja el efectivo «para confirmar» (tarea de Soy). La reposición de almacén queda sin recibir (OC abierta).
  perform pg_temp.as_user(v_manager);
  for r in select o.n, o.id, o.n = 'distri-1' as short,
                  case when o.n like 'frigo%' then 'invoice_remito' else 'remito' end::purchasing.paper_kind as paper
             from pru_ids o where o.kind = 'order' and o.n <> 'distri-2' and o.n <> 'verdu-2' order by o.n loop
    perform pg_temp.receive(r.id, r.short, r.paper, null, null);
  end loop;
  --    El efectivo: lo pedido al precio de la lista de la Verdulería (con IVA), el mismo que va a facturar.
  select id into v_order from pru_ids where kind = 'order' and n = 'verdu-2';
  perform pg_temp.receive(v_order, false, 'remito', 'R 0001-00000077',
            (select sum(l.quantity * li.list_price)
               from purchasing.purchase_order_lines l
               join purchasing.price_list_items li
                 on li.price_list_id = (select id from pru_ids where kind = 'list' and n = 'verdu-1')
                and li.purchase_product_id = l.purchase_product_id
              where l.purchase_order_id = v_order and l.deleted_at is null));

  -- 4. Facturas: Compras las carga; la Controller da por conformes las que pasan los controles (la lista la aceptó
  --    Compras, así que firma otra persona).
  perform pg_temp.as_user(v_buyer);
  insert into pru_ids
  select 'invoice', x.n,
         pg_temp.invoice(x.supplier, (select id from pru_ids where kind = 'order' and n = x.n), x.class, x.pos, x.number,
                         x.cae, v_today - x.days, x.extra, x.reason)
    from (values
      ('frigo-1', v_frigo, 'invoice_a', 2, 10501, '76000000000101', 20, 0, 'Factura A del Frigorífico (se paga entera)'),
      ('frigo-2', v_frigo, 'invoice_a', 2, 10544, '76000000000102', 10, 0, 'Factura A del Frigorífico (para que la pague Soy)'),
      ('frigo-3', v_frigo, 'invoice_a', 2, 10590, '76000000000103', 3, 150, 'Factura A del Frigorífico (cobra de más; llega nota de crédito)'),
      ('frigo-4', v_frigo, 'invoice_a', 2, 10602, '76000000000104', 1, 90, 'Factura A del Frigorífico (cobra de más; queda observada)'),
      ('verdu-1', v_verdu, 'invoice_b', 4, 3311, '76000000000105', 3, 0, 'Factura B de la Verdulería (se paga una parte)'),
      ('verdu-2', v_verdu, 'invoice_b', 4, 3340, '76000000000106', 0, 0, 'Factura B de la Verdulería (la verdura pagada en efectivo)'))
      as x (n, supplier, class, pos, number, cae, days, extra, reason);

  --    La nota de crédito del Frigorífico cierra lo cobrado de más (con su foto).
  select id into v_invoice from pru_ids where kind = 'invoice' and n = 'frigo-3';
  select 150 * l.billed_quantity into v_diff
    from purchasing.invoice_lines l where l.invoice_id = v_invoice and l.deleted_at is null order by l.line_order limit 1;
  v_res := pg_temp.ok(purchasing.add_credit_debit_note(v_invoice, jsonb_build_object(
             'note_kind', 'credit', 'number', 'NC A 0002-00000431', 'issued_on', v_today,
             'net_amount', v_diff, 'total_amount', round(v_diff * 1.21, 2)),
             pg_temp.why('el Frigorífico reconoce el precio de la lista')), 'cargar la nota de crédito');
  perform pg_temp.ok(purchasing.add_invoice_attachment('credit_debit_notes', (v_res ->> 'note_id')::uuid,
                                                       pg_temp.photo('credit_debit_notes', (v_res ->> 'note_id')::uuid),
                                                       1::smallint), 'adjuntar la foto de la nota de crédito');

  perform pg_temp.as_user(v_ctrl);
  for r in select id, n from pru_ids where kind = 'invoice' and n in ('frigo-1', 'frigo-2', 'frigo-3', 'verdu-1') loop
    v_res := purchasing.approve_invoice(r.id, pg_temp.why('revisada contra la recepción y la lista'));
    if coalesce(v_res ->> 'result', '') not in ('applied', 'approved', 'released') then
      raise exception 'La Controller no pudo dar por conforme la factura %: %', r.n, coalesce(v_res ->> 'message', v_res::text);
    end if;
  end loop;

  -- 5. Pagos (Compras): la primera del Frigorífico entera, por transferencia y con comprobante; la de la Verdulería,
  --    una parte en efectivo (queda vencida con saldo).
  perform pg_temp.as_user(v_buyer);
  select id into v_invoice from pru_ids where kind = 'invoice' and n = 'frigo-1';
  -- La cuenta de la prueba (por su alias), no otra que el proveedor ya tuviera.
  select id into strict v_account from purchasing.supplier_payment_accounts
   where supplier_id = v_frigo and method = 'transfer' and alias = 'corral.prueba' and deleted_at is null;
  v_payment := (pg_temp.ok(purchasing.register_payment(v_centro, v_frigo, v_today - 5, 'transfer', v_account,
                  purchasing.invoice_balance(v_invoice), 'TRF-PRUEBA-0001',
                  jsonb_build_array(jsonb_build_object('invoice_id', v_invoice,
                                                       'amount', purchasing.invoice_balance(v_invoice))),
                  pg_temp.why('transferencia de la factura entera')), 'registrar el pago del Frigorífico')
                ->> 'payment_id')::uuid;
  perform pg_temp.ok(purchasing.add_payment_attachment(v_payment, pg_temp.photo('payments', v_payment), 1::smallint),
                     'adjuntar el comprobante del pago');

  select id into v_invoice from pru_ids where kind = 'invoice' and n = 'verdu-1';
  v_diff := round(purchasing.invoice_balance(v_invoice) * 0.4, -2);
  perform pg_temp.ok(purchasing.register_payment(v_centro, v_verdu, v_today - 1, 'cash', null, v_diff, null,
                       jsonb_build_array(jsonb_build_object('invoice_id', v_invoice, 'amount', v_diff)),
                       pg_temp.why('una parte en efectivo')), 'registrar el pago de la Verdulería');

  perform set_config('request.jwt.claims', '', true);
end
$$;

-- Verificar, no suponer: si algo no quedó como se espera, se deshace todo.
do $$
declare
  v_bad text;
begin
  select string_agg(format('%s: %s (se esperaba %s)', i.n, coalesce(v.status::text, 'sin factura'), i.expected), '; ')
    into v_bad
    from (values ('frigo-1', 'paid'), ('frigo-2', 'released'), ('frigo-3', 'released'), ('frigo-4', 'observed'),
                 ('verdu-1', 'released'), ('verdu-2', 'observed')) as i (n, expected)
    left join pru_ids p on p.kind = 'invoice' and p.n = i.n
    left join purchasing.invoices v on v.id = p.id
   where v.status::text is distinct from i.expected;
  if v_bad is not null then
    raise exception 'Las facturas no quedaron como se esperaba: %. No se cargó nada.', v_bad;
  end if;
  -- La de la verdura pagada en efectivo queda observada solo porque falta la firma de otra persona (la lista la aceptó
  -- Compras): es la que da por conforme Soy.
  if exists (select 1 from purchasing.invoice_checks c
              where c.invoice_id = (select id from pru_ids where kind = 'invoice' and n = 'verdu-2')
                and not c.passed
                and c.run_id = (select run_id from purchasing.invoice_checks x where x.invoice_id = c.invoice_id
                                 order by x.run_at desc, x.entry_number desc limit 1)
                and c.explanation not like '%la da por conforme otra persona%') then
    raise exception 'La factura de la verdura pagada en efectivo tiene que quedar esperando solo la firma de otra persona. No se cargó nada.';
  end if;
  if purchasing.invoice_balance((select id from pru_ids where kind = 'invoice' and n = 'verdu-1')) <= 0
     or purchasing.invoice_balance((select id from pru_ids where kind = 'invoice' and n = 'frigo-2')) <= 0 then
    raise exception 'Las facturas para pagar quedaron sin saldo. No se cargó nada.';
  end if;
  -- Tarea 1 de Soy: la del Frigorífico vence en 5 días.
  if (select due_on from purchasing.invoices
       where id = (select id from pru_ids where kind = 'invoice' and n = 'frigo-2')) <> recipes.today() + 5 then
    raise exception 'La factura del Frigorífico para Soy no vence en 5 días. No se cargó nada.';
  end if;
  -- Tareas 2 y 3: un solo efectivo para confirmar, el de la recepción de la verdura, por el total de su factura.
  if (select count(*) from purchasing.payments p
       where p.supplier_id in (select supplier_id from purchasing.invoices where id in (select id from pru_ids where kind = 'invoice'))
         and p.status = 'to_confirm' and p.deleted_at is null) <> 1
     or not exists (select 1 from purchasing.payments p
                     join purchasing.receipts rc on rc.id = p.receipt_id
                    where p.status = 'to_confirm' and p.deleted_at is null
                      and rc.purchase_order_id = (select id from pru_ids where kind = 'order' and n = 'verdu-2')
                      and p.payment_amount = (select total_amount from purchasing.invoices
                                               where id = (select id from pru_ids where kind = 'invoice' and n = 'verdu-2'))) then
    raise exception 'El efectivo de la verdura no quedó para confirmar por el total de su factura. No se cargó nada.';
  end if;
  if (select count(*) from pru_ids where kind = 'list') <> 5
     or (select count(*) from purchasing.purchase_orders
          where id in (select id from pru_ids where kind = 'order') and status::text <> 'draft') <> 8 then
    raise exception 'Faltan listas u órdenes de compra enviadas. No se cargó nada.';
  end if;
  -- Las 22 fotos: 2 por recepción (7), una por factura (6), la de la nota de crédito y la del pago.
  if (select count(*) from purchasing.attachments a join pru_files f on f.path = a.storage_path) <> 22 then
    raise exception 'Faltan fotos adjuntas (se esperaban 22). No se cargó nada.';
  end if;
end
$$;

-- Control: lo que quedó cargado.
select v.n as factura, i.status as estado, i.total_amount as total, purchasing.invoice_balance(i.id) as saldo,
       i.due_on as vence
  from pru_ids v join purchasing.invoices i on i.id = v.id where v.kind = 'invoice' order by v.n;
select p.status as pago, p.method as medio, p.payment_amount as importe
  from purchasing.payments p
 where p.supplier_id in (select supplier_id from purchasing.invoices where id in (select id from pru_ids where kind = 'invoice'))
   and p.deleted_at is null order by p.created_at;

\if :{?dry_run}
  rollback;
  \echo 'Ensayo (DRY_RUN): se hizo todo y se deshizo. No quedó nada cargado.'
  truncate pru_files;
\else
  commit;
  \echo 'Prueba de la Fase 3 cargada: listas, órdenes de compra, recepciones, facturas y pagos.'
\endif

\endif

\if :{?files_out}
  \set QUIET on
  \pset tuples_only on
  \pset format unaligned
  \o :files_out
  select path from pru_files order by path;
  \o
  \pset tuples_only off
  \pset format aligned
  \set QUIET off
  select count(*) as fotos_para_subir from pru_files;
\endif
