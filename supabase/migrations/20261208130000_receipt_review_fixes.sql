-- Fase 3, Prompt 4 (ADR-0056): correcciones de las revisiones de base y seguridad, y dos decisiones de Joaco
-- (2026-11-17).
--
-- - Lo vencido no suma stock; lo de mala calidad que se acepta, sí.
-- - Toda recepción sin OC le avisa a Compras. Un renglón OK que pesa más de un 20 % distinto de lo estimado se tiene que
--   observar, con motivo.
-- - Las fotos de una recepción son JPEG de hasta 4 MB: lo controla la base, no solo la pantalla.
-- - Lo subido y todavía sin registrar lo lee solo quien lo subió, mientras la recepción está abierta.
-- - Se recibe en el local que pidió la orden. Una observación que no es «de más» no trae más de lo pedido.
-- - Queda quién cerró la recepción (closed_by), que puede no ser quien la abrió.

-- ---------------------------------------------------------------------------
-- 1. Quién cerró
-- ---------------------------------------------------------------------------
alter table purchasing.receipts add column closed_by uuid references core.actors (id) on delete restrict;
alter table purchasing.receipts add constraint receipts_closed_by_check check ((status = 'closed') = (closed_by is not null));
create index receipts_closed_by_idx on purchasing.receipts (closed_by) where closed_by is not null;
comment on column purchasing.receipts.closed_by is 'Quién cerró la recepción (puede no ser quien la abrió: otra persona del local la retoma).';
comment on column purchasing.receipts.received_by is 'Quién abrió la recepción.';
grant select (closed_by) on purchasing.receipts to authenticated;
comment on column purchasing.receipt_lines.received_quantity is
  'Cuánto se recibió: envases del producto de la OC o reconocido, la cantidad de la materia prima en su unidad («sin nombre de factura») o, en lo que va a la cola de mapeo, envases o unidades como figura en el papel (la unidad la define el chef al mapearlo).';

-- ---------------------------------------------------------------------------
-- 2. Fotos: JPEG de hasta 4 MB, y lo no registrado lo lee solo quien lo subió
-- ---------------------------------------------------------------------------
create function purchasing.receipt_photo_ok(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select o.metadata ->> 'mimetype' = 'image/jpeg'
                          and coalesce((o.metadata ->> 'size')::bigint, 0) <= 4194304
                     from storage.objects o
                    where o.bucket_id = 'purchasing-documents' and o.name = p_name), false)
     and p_name ~ '\.jpg$'
$$;
comment on function purchasing.receipt_photo_ok(text) is
  'Interna: si un archivo de una recepción es una foto JPEG de hasta 4 MB (por su nombre y lo que Storage registró al subirlo).';
revoke execute on function purchasing.receipt_photo_ok(text) from public;

create or replace function purchasing.can_upload_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case d.source_table
             when 'price_lists' then
               core.has_permission_in_group('purchasing.manage_price_lists', d.group_id)
               and exists (select 1 from purchasing.price_lists l
                            where l.id = d.source_id and l.group_id = d.group_id and l.deleted_at is null
                              and l.status = 'received')
             when 'receipts' then
               p_name ~ '\.jpg$'
               and exists (select 1 from purchasing.receipts r
                            where r.id = d.source_id and r.group_id = d.group_id and r.deleted_at is null
                              and r.status = 'open'
                              and purchasing.can_in_restaurant('purchasing.receive', r.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_upload_document(text) is
  'Si la sesión puede subir ese archivo, con nombre <grupo>/<tabla>/<registro>/<uuid>.<ext>: una lista recibida (sin aceptar) del grupo, con purchasing.manage_price_lists; o una foto .jpg de una recepción abierta, con purchasing.receive en su local. Lo cerrado ya no suma archivos.';

create or replace function purchasing.can_read_own_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case d.source_table
             when 'price_lists' then core.has_permission_in_group('purchasing.manage_price_lists', d.group_id)
             when 'receipts' then
               exists (select 1 from purchasing.receipts r
                        where r.id = d.source_id and r.group_id = d.group_id and r.deleted_at is null
                          and r.status = 'open'
                          and purchasing.can_in_restaurant('purchasing.receive', r.restaurant_id))
             else false
           end
      from purchasing.document_parts(p_name) d), false)
$$;
comment on function purchasing.can_read_own_document(text) is
  'Si la sesión puede leer un archivo que acaba de subir, antes de registrarlo: carga listas en el grupo de la carpeta, o recibe en el local de la recepción abierta de la carpeta. La política de Storage exige además que lo haya subido ella.';

-- Lo que acaba de subir: solo lo suyo (revisión de seguridad, 2026-11-17).
drop policy purchasing_documents_read on storage.objects;
create policy purchasing_documents_read on storage.objects for select to authenticated
  using (bucket_id = 'purchasing-documents'
         and (name in (select purchasing.visible_document_paths())
              or (owner_id = (select auth.uid())::text and purchasing.can_read_own_document(name))));

-- ---------------------------------------------------------------------------
-- 3. Mensajes
-- ---------------------------------------------------------------------------
create or replace function purchasing.raise_receipt_error(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'receipt_lines_received_quantity_check' then 'La cantidad recibida no puede ser negativa.'
    when p_constraint = 'receipt_lines_received_weight_check' then 'El peso tiene que ser mayor que cero.'
    when p_constraint = 'receipt_lines_lot_code_check' then 'El lote va hasta 60 caracteres.'
    when p_constraint = 'receipt_lines_note_check' then 'La nota de un renglón va hasta 300 caracteres.'
    when p_constraint = 'receipt_lines_description_check' then 'Escribí qué llegó (hasta 200 caracteres).'
    when p_constraint = 'receipt_lines_issue_check' then 'Elegí qué pasó con el renglón observado.'
    when p_constraint = 'receipt_lines_po_line_key' then 'Hay un renglón de la OC repetido: recargá la página.'
    when p_constraint = 'receipts_paper_number_check' then 'El número del papel va hasta 40 caracteres.'
    when p_constraint = 'receipts_cash_paid_amount_check' then 'El importe en efectivo tiene que ser mayor que cero.'
    when p_constraint = 'receipts_open_order_key' then 'Esta OC ya tiene una recepción abierta: retomala.'
    when p_constraint = 'receipts_closed_by_check' then 'Falta quién cerró la recepción.'
    when p_state = '23503' then 'Algún renglón, producto o materia prima ya no existe: recargá la página.'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la recepción.'
    else null
  end;
  if v_message is null then
    perform purchasing.raise_order_error(p_state, p_constraint, p_message);
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
comment on function purchasing.raise_receipt_error(text, text, text) is
  'Interna: traduce a un mensaje en español el error de una restricción de recepciones (y, si no es suya, usa la de órdenes de compra).';
revoke execute on function purchasing.raise_receipt_error(text, text, text) from public;

-- ---------------------------------------------------------------------------
-- 4. Abrir y sumar fotos
-- ---------------------------------------------------------------------------
-- Recibir una OC enviada (o con novedad, o recibida parcial). Si ya tiene una abierta, la retoma. Recibe el local que
-- la pidió (revisiones de base y seguridad, 2026-11-17): recibir un local para otro queda para cuando haga falta, con
-- la visibilidad de los dos locales resuelta.
create or replace function purchasing.start_receipt(p_order_id uuid, p_restaurant_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_o  purchasing.purchase_orders;
  v_r  org.restaurants;
  v_id uuid;
begin
  select * into v_o from purchasing.purchase_orders where id = p_order_id and deleted_at is null;
  select * into v_r from org.restaurants
   where id = coalesce(p_restaurant_id, v_o.restaurant_id) and group_id = v_o.group_id and deleted_at is null;
  if v_o.id is null or v_r.id is null
     or not purchasing.can_in_restaurant('purchasing.view_orders', v_o.restaurant_id)
     or not purchasing.can_in_restaurant('purchasing.receive', v_r.id) then
    return core.deny('purchasing.start_receipt', 'No tenés permiso para recibir esta orden en este local.', null,
                     jsonb_build_object('purchase_order_id', p_order_id, 'restaurant_id', p_restaurant_id),
                     coalesce(v_r.group_id, v_o.group_id), coalesce(v_r.brand_id, v_o.brand_id),
                     coalesce(v_r.id, v_o.restaurant_id));
  end if;
  if p_restaurant_id is not null and p_restaurant_id <> v_o.restaurant_id then
    raise exception 'Se recibe en el local que pidió la orden.' using errcode = '22023';
  end if;
  select * into v_o from purchasing.purchase_orders where id = v_o.id for update;
  if v_o.status not in ('sent', 'with_news', 'partially_received') then
    raise exception 'Esta orden no está para recibir: tiene que estar enviada o recibida parcial.' using errcode = '23514';
  end if;
  select id into v_id from purchasing.receipts
   where purchase_order_id = v_o.id and status = 'open' and deleted_at is null;
  if v_id is not null then
    return jsonb_build_object('result', 'applied', 'receipt_id', v_id, 'resumed', true);
  end if;
  perform core.set_change_context(format('Recepción de la orden %s', v_o.number), 'manual');
  insert into purchasing.receipts (group_id, brand_id, restaurant_id, supplier_id, purchase_order_id, received_by)
  values (v_r.group_id, v_r.brand_id, v_r.id, v_o.supplier_id, v_o.id, core.current_actor_id())
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'receipt_id', v_id, 'resumed', false);
end
$$;
comment on function purchasing.start_receipt(uuid, uuid) is
  'Abre la recepción de una OC enviada, con novedad o recibida parcial (o retoma la que ya está abierta). Pide ver la OC y purchasing.receive en su local: se recibe en el local que la pidió.';
revoke execute on function purchasing.start_receipt(uuid, uuid) from public;
grant execute on function purchasing.start_receipt(uuid, uuid) to authenticated;

-- «Recibir sin OC»: llegó mercadería de un proveedor sin orden.
create or replace function purchasing.start_receipt_without_order(p_supplier_id uuid, p_restaurant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r  org.restaurants;
  v_s  catalog.suppliers;
  v_id uuid;
begin
  select * into v_r from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.receive', v_r.id) then
    return core.deny('purchasing.start_receipt_without_order', 'No tenés permiso para recibir en este local.', null,
                     jsonb_build_object('restaurant_id', p_restaurant_id), v_r.group_id, v_r.brand_id, v_r.id);
  end if;
  select * into v_s from catalog.suppliers
   where id = p_supplier_id and group_id = v_r.group_id and deleted_at is null and is_active;
  if v_s.id is null then
    raise exception 'Elegí un proveedor activo de este grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(format('Recepción sin OC de %s', coalesce(v_s.trade_name, v_s.name)), 'manual');
  insert into purchasing.receipts (group_id, brand_id, restaurant_id, supplier_id, received_by)
  values (v_r.group_id, v_r.brand_id, v_r.id, v_s.id, core.current_actor_id())
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'receipt_id', v_id, 'resumed', false);
end
$$;
comment on function purchasing.start_receipt_without_order(uuid, uuid) is
  '«Recibir sin OC»: abre una recepción de un proveedor activo del grupo, sin orden. Pide purchasing.receive en el local.';
revoke execute on function purchasing.start_receipt_without_order(uuid, uuid) from public;
grant execute on function purchasing.start_receipt_without_order(uuid, uuid) to authenticated;

-- Registrar una foto ya subida a la carpeta de la recepción: la 1 (el papel como llegó) o la 2 (firmado), con su
-- página. Rehacer suma otra: vale la última de cada foto y página.
create or replace function purchasing.add_receipt_attachment(p_receipt_id uuid, p_storage_path text, p_kind purchasing.doc_kind,
                                                  p_page smallint default 1)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r  purchasing.receipts;
  v_id uuid;
begin
  select * into v_r from purchasing.receipts where id = p_receipt_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.receive', v_r.restaurant_id) then
    return core.deny('purchasing.add_receipt_attachment', 'No tenés permiso para sumar fotos a esta recepción.', null,
                     jsonb_build_object('receipt_id', p_receipt_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if v_r.status <> 'open' then
    raise exception 'Una recepción cerrada no se cambia.' using errcode = '23514';
  end if;
  if p_kind is null or p_kind not in ('receipt_original', 'receipt_signed') then
    raise exception 'La foto es la del papel como llegó o la del papel firmado.' using errcode = '22023';
  end if;
  if coalesce(p_page, 1) not between 1 and 20 then
    raise exception 'Van hasta 20 páginas por foto.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.document_parts(p_storage_path) d
                  where d.group_id = v_r.group_id and d.source_table = 'receipts' and d.source_id = v_r.id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'purchasing-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'La foto no está subida en la carpeta de esta recepción.' using errcode = '22023';
  end if;
  if not purchasing.receipt_photo_ok(p_storage_path) then
    raise exception 'La foto tiene que ser una imagen JPEG de hasta 4 MB.' using errcode = '22023';
  end if;
  perform core.set_change_context(case p_kind when 'receipt_original' then 'Foto del papel como llegó'
                                              else 'Foto del papel firmado' end, 'manual');
  insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
  values (v_r.group_id, 'receipts', v_r.id, p_kind, coalesce(p_page, 1), p_storage_path)
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'attachment_id', v_id);
end
$$;
comment on function purchasing.add_receipt_attachment(uuid, text, purchasing.doc_kind, smallint) is
  'Registra una foto ya subida a la carpeta de una recepción abierta: la del papel como llegó (receipt_original) o la del papel firmado (receipt_signed), con su página. Rehacer suma otra; vale la última. Pide purchasing.receive en el local.';
revoke execute on function purchasing.add_receipt_attachment(uuid, text, purchasing.doc_kind, smallint) from public;
grant execute on function purchasing.add_receipt_attachment(uuid, text, purchasing.doc_kind, smallint) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Cerrar
-- ---------------------------------------------------------------------------
-- Cuánto entra al stock, en la unidad de uso de la materia prima. Envases de un producto: envases × unidades × contenido.
-- Por peso, si se pesó: los kilos. Una materia prima «sin nombre de factura»: la cantidad en su unidad.
create or replace function purchasing.receipt_stock_quantity(p_ingredient_id uuid, p_product_id uuid, p_quantity numeric,
                                                  p_unit_id uuid, p_weight_kg numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p    catalog.purchase_products;
  v_base record;
begin
  if p_product_id is not null then
    select * into v_p from catalog.purchase_products where id = p_product_id;
    if v_p.billed_by_weight and p_weight_kg is not null then
      select b.base_quantity, b.status into v_base
        from catalog.to_base_quantity(p_ingredient_id, p_weight_kg,
                                      (select u.id from catalog.units u where u.code = 'kg' and u.deleted_at is null)) b;
    else
      select b.base_quantity, b.status into v_base
        from catalog.to_base_quantity(p_ingredient_id, p_quantity * v_p.units_per_package * v_p.content_per_unit,
                                      v_p.content_unit_id) b;
    end if;
  else
    select b.base_quantity, b.status into v_base from catalog.to_base_quantity(p_ingredient_id, p_quantity, p_unit_id) b;
  end if;
  if v_base.status is distinct from 'ok' then
    raise exception 'No sabemos pasar «%» a su unidad de uso: revisá el envase del producto o las conversiones de la materia prima.',
      (select name from catalog.ingredients where id = p_ingredient_id) using errcode = '22023';
  end if;
  return v_base.base_quantity;
end
$$;
comment on function purchasing.receipt_stock_quantity(uuid, uuid, numeric, uuid, numeric) is
  'Interna: cuánto entra al stock en la unidad de uso de la materia prima (envases × unidades × contenido; por peso, los kilos si se pesaron; sin producto, la cantidad en su unidad). Error claro si no se puede convertir.';
revoke execute on function purchasing.receipt_stock_quantity(uuid, uuid, numeric, uuid, numeric) from public;

-- p_lines: una decisión por cada renglón pendiente de la OC
--   {purchase_order_line_id, ok, issue, received_quantity, received_weight, lot_code, note, photo_paths}
-- y lo que llegó sin estar en la OC
--   {name, received_quantity, received_weight, lot_code, note, photo_paths}.
-- Un renglón OK recibe lo pendiente; uno observado dice cuánto llegó (0 si faltó o lo devolvió).
create or replace function purchasing.close_receipt(p_id uuid, p_paper_kind purchasing.paper_kind, p_paper_number text,
                                         p_lines jsonb, p_cash_paid_amount numeric, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r            purchasing.receipts;
  v_o            purchasing.purchase_orders;
  v_s            catalog.suppliers;
  v_line         jsonb;
  v_pol          purchasing.purchase_order_lines;
  v_product      catalog.purchase_products;
  v_order        integer := 0;
  v_ok           boolean;
  v_issue        purchasing.receipt_issue;
  v_qty          numeric;
  v_weight       numeric;
  v_expected_kg  numeric;
  v_pending      numeric;
  v_ingredient   uuid;
  v_product_id   uuid;
  v_unit         uuid;
  v_unmapped     uuid;
  v_line_id      uuid;
  v_path         text;
  v_observed     integer := 0;
  v_new_unmapped integer := 0;
  v_seen         uuid[] := '{}';
  v_missing      integer;
  v_result       purchasing.receipt_result;
  v_reason       text;
  v_now          timestamptz := now();
  v_title        text;
  v_body         text;
  v_constraint   text;
  v_message      text;
begin
  select * into v_r from purchasing.receipts where id = p_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.receive', v_r.restaurant_id) then
    return core.deny('purchasing.close_receipt', 'No tenés permiso para cerrar esta recepción.', null,
                     jsonb_build_object('receipt_id', p_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  select * into v_r from purchasing.receipts where id = p_id for update;
  if v_r.status <> 'open' then
    raise exception 'Esta recepción ya se cerró.' using errcode = '23514';
  end if;
  if p_paper_kind is null then
    raise exception 'Elegí qué papel trajo el proveedor.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.attachments
                  where source_table = 'receipts' and source_id = v_r.id and doc_kind = 'receipt_original') then
    raise exception 'Falta la foto 1: el remito o la factura como llegó.' using errcode = '22023';
  end if;
  if not exists (select 1 from purchasing.attachments
                  where source_table = 'receipts' and source_id = v_r.id and doc_kind = 'receipt_signed') then
    raise exception 'Falta la foto 2: el papel firmado.' using errcode = '22023';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Faltan los renglones de la recepción.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_lines) > 600 then
    raise exception 'Una recepción va hasta 600 renglones.' using errcode = '22023';
  end if;
  if p_cash_paid_amount is not null and (p_cash_paid_amount = 'NaN'::numeric or p_cash_paid_amount <= 0) then
    raise exception 'El importe en efectivo tiene que ser mayor que cero.' using errcode = '22023';
  end if;
  if p_cash_paid_amount >= 10000000000 then
    raise exception 'El importe en efectivo es demasiado grande: revisalo.' using errcode = '22023';
  end if;
  select * into v_s from catalog.suppliers where id = v_r.supplier_id;
  if v_r.purchase_order_id is not null then
    select * into v_o from purchasing.purchase_orders where id = v_r.purchase_order_id for update;
    if v_o.status not in ('sent', 'with_news', 'partially_received') then
      raise exception 'Esta orden ya no está para recibir.' using errcode = '23514';
    end if;
  end if;
  -- El contexto va antes de escribir; el motivo, si hubo observaciones, se controla al final.
  v_reason := nullif(btrim(p_reason), '');
  perform core.set_change_context(coalesce(left(v_reason, 500),
                                           case when v_o.id is not null then format('Recepción de la orden %s', v_o.number)
                                                else format('Recepción sin OC de %s', coalesce(v_s.trade_name, v_s.name)) end),
                                  'manual');

  for v_line in select value from jsonb_array_elements(p_lines) loop
    perform org.check_keys(v_line, array['purchase_order_line_id', 'name', 'ok', 'issue', 'received_quantity',
                                         'received_weight', 'lot_code', 'note', 'photo_paths']);
    v_order := v_order + 1;
    v_weight := (v_line ->> 'received_weight')::numeric;
    if v_weight is not null and (v_weight = 'NaN'::numeric or v_weight <= 0) then
      raise exception 'El peso del renglón % tiene que ser mayor que cero.', v_order using errcode = '22023';
    end if;
    v_ingredient := null; v_product_id := null; v_unit := null; v_unmapped := null;

    if v_line ? 'purchase_order_line_id' then
      -- Un renglón de la OC.
      if v_o.id is null then
        raise exception 'Esta recepción no tiene OC: cargá lo que llegó como «Llegó algo que no estaba».' using errcode = '22023';
      end if;
      select * into v_pol from purchasing.purchase_order_lines
       where id = (v_line ->> 'purchase_order_line_id')::uuid and purchase_order_id = v_o.id and deleted_at is null
         for update;
      if v_pol.id is null then
        raise exception 'El renglón % no es de esta orden.', v_order using errcode = '22023';
      end if;
      if v_pol.id = any (v_seen) then
        raise exception 'El renglón % está repetido.', v_order using errcode = '22023';
      end if;
      v_seen := v_seen || v_pol.id;
      v_pending := v_pol.quantity - v_pol.received_quantity;
      if v_pending <= 0 then
        raise exception 'El renglón % ya se recibió entero.', v_order using errcode = '23514';
      end if;
      v_ok := coalesce((v_line ->> 'ok')::boolean, false);
      if v_ok then
        if v_line ? 'issue' then
          raise exception 'El renglón % está OK: no lleva observación.', v_order using errcode = '22023';
        end if;
        v_issue := null;
        v_qty := v_pending;
      else
        v_issue := (v_line ->> 'issue')::purchasing.receipt_issue;
        if v_issue is null then
          raise exception 'Elegí qué pasó con el renglón %.', v_order using errcode = '22023';
        end if;
        v_qty := (v_line ->> 'received_quantity')::numeric;
        if v_qty is null or v_qty = 'NaN'::numeric or v_qty < 0 then
          raise exception 'Escribí cuánto llegó del renglón % (0 si no llegó).', v_order using errcode = '22023';
        end if;
        if v_issue = 'missing' and v_qty >= v_pending then
          raise exception 'En el renglón % marcaste que faltó: lo recibido tiene que ser menos que lo pedido.', v_order
            using errcode = '22023';
        end if;
        if v_issue = 'extra' and v_qty <= v_pending then
          raise exception 'En el renglón % marcaste que vino de más: lo recibido tiene que ser más que lo pedido.', v_order
            using errcode = '22023';
        end if;
        -- Solo «de más» trae más de lo pedido (revisión de seguridad, 2026-11-17).
        if v_issue <> 'extra' and v_qty > v_pending then
          raise exception 'En el renglón % llegó más de lo pedido: marcalo como «De más».', v_order using errcode = '22023';
        end if;
        if v_issue = 'different_product' and v_qty <> 0 then
          raise exception 'En el renglón % mandaron otro producto: lo pedido no llegó (0). Cargá lo que vino como «Llegó algo que no estaba».',
            v_order using errcode = '22023';
        end if;
        v_observed := v_observed + 1;
      end if;
      if v_pol.purchase_product_id is not null then
        select * into v_product from catalog.purchase_products where id = v_pol.purchase_product_id;
        v_product_id := v_product.id;
        v_ingredient := v_product.ingredient_id;
      else
        v_product := null;
        v_ingredient := v_pol.ingredient_id;
        v_unit := v_pol.unit_id;
      end if;
      -- El peso vale solo en lo que va por peso (revisión de base, 2026-11-17).
      if not coalesce(v_product.billed_by_weight, false) then
        v_weight := null;
      end if;
      -- Un renglón OK que pesa muy distinto de lo estimado se observa (Joaco, 2026-11-17: más de un 20 %).
      if v_ok and v_weight is not null and v_product.estimated_weight_per_unit is not null then
        v_expected_kg := v_qty * v_product.units_per_package * v_product.estimated_weight_per_unit
                         / case when (select u.code from catalog.units u where u.id = v_product.content_unit_id) = 'g'
                                then 1000 else 1 end;
        if v_expected_kg > 0 and abs(v_weight - v_expected_kg) > 0.2 * v_expected_kg then
          raise exception 'El peso del renglón % (% kg) se aleja más de un 20 %% de lo estimado (≈ % kg): marcalo como observado, con el motivo.',
            v_order, v_weight, round(v_expected_kg, 1) using errcode = '22023';
        end if;
      end if;
      update purchasing.purchase_order_lines set received_quantity = received_quantity + v_qty where id = v_pol.id;
    else
      -- Llegó algo que no estaba en la OC (o, sin OC, todo lo que llegó).
      if nullif(btrim(v_line ->> 'name'), '') is null then
        raise exception 'Escribí qué llegó en el renglón %.', v_order using errcode = '22023';
      end if;
      if v_line ? 'issue' and v_o.id is null then
        raise exception 'Sin OC no hay observaciones por renglón: anotá lo que llegó.' using errcode = '22023';
      end if;
      v_qty := (v_line ->> 'received_quantity')::numeric;
      if v_qty is null or v_qty = 'NaN'::numeric or v_qty <= 0 then
        raise exception 'Escribí cuánto llegó del renglón %.', v_order using errcode = '22023';
      end if;
      -- Con OC, algo que no estaba es una observación («de más»); sin OC, es lo recibido.
      v_ok := v_o.id is null;
      v_issue := case when v_o.id is null then null else 'extra'::purchasing.receipt_issue end;
      if not v_ok then
        v_observed := v_observed + 1;
      end if;
      v_product_id := purchasing.match_article(v_s.id, null, v_line ->> 'name');
      v_product := null;
      if v_product_id is not null then
        select * into v_product from catalog.purchase_products where id = v_product_id;
        v_ingredient := v_product.ingredient_id;
      else
        -- No se reconoce: a la cola de mapeo (o al pendiente que ya hay). No suma stock: no se sabe qué es.
        select id into v_unmapped from purchasing.unmapped_articles
         where supplier_id = v_s.id and normalized_name = purchasing.normalize_name(v_line ->> 'name')
           and status in ('pending', 'discarded') and deleted_at is null
         order by status = 'pending' desc, resolved_at desc nulls first
         limit 1;
        if v_unmapped is null then
          insert into purchasing.unmapped_articles (group_id, supplier_id, raw_name, found_in, source_id)
          values (v_r.group_id, v_s.id, btrim(v_line ->> 'name'), 'receipt', v_r.id)
          returning id into v_unmapped;
          v_new_unmapped := v_new_unmapped + 1;
        end if;
      end if;
    end if;

    if not coalesce(v_product.billed_by_weight, false) then
      v_weight := null;
    end if;
    insert into purchasing.receipt_lines (group_id, receipt_id, line_order, purchase_order_line_id, purchase_product_id,
                                          ingredient_id, unmapped_article_id, description, ok, issue, received_quantity,
                                          received_weight, lot_code, note)
    values (v_r.group_id, v_r.id, v_order, case when v_line ? 'purchase_order_line_id' then v_pol.id end, v_product_id,
            v_ingredient, v_unmapped, nullif(btrim(v_line ->> 'name'), ''), v_ok, v_issue, v_qty, v_weight,
            nullif(btrim(v_line ->> 'lot_code'), ''), nullif(btrim(v_line ->> 'note'), ''))
    returning id into v_line_id;

    -- La foto de un producto observado: subida a la carpeta de la recepción.
    if v_line ? 'photo_paths' then
      if jsonb_typeof(v_line -> 'photo_paths') <> 'array' or jsonb_array_length(v_line -> 'photo_paths') > 5 then
        raise exception 'Van hasta 5 fotos por renglón.' using errcode = '22023';
      end if;
      for v_path in select value from jsonb_array_elements_text(v_line -> 'photo_paths') loop
        if not exists (select 1 from purchasing.document_parts(v_path) d
                        where d.group_id = v_r.group_id and d.source_table = 'receipts' and d.source_id = v_r.id)
           or not exists (select 1 from storage.objects o
                           where o.bucket_id = 'purchasing-documents' and o.name = v_path
                             and o.owner_id = (select auth.uid())::text)
           or not purchasing.receipt_photo_ok(v_path) then
          raise exception 'La foto del renglón % no está subida en la carpeta de esta recepción.', v_order
            using errcode = '22023';
        end if;
        insert into purchasing.attachments (group_id, source_table, source_id, doc_kind, page, storage_path)
        values (v_r.group_id, 'receipt_lines', v_line_id, 'product_issue',
                (select count(*) + 1 from purchasing.attachments a
                  where a.source_table = 'receipt_lines' and a.source_id = v_line_id), v_path);
      end loop;
    end if;

    -- La entrada de stock (D8): lo que se recibió y se sabe qué materia prima es. Lo vencido no entra (Joaco, 2026-11-17).
    if v_qty > 0 and v_ingredient is not null and v_issue is distinct from 'expired' then
      insert into inventory.stock_movements (group_id, brand_id, restaurant_id, ingredient_id, purchase_product_id, kind,
                                             quantity, unit_id, packages, lot_code, occurred_at, source_table, source_id)
      values (v_r.group_id, v_r.brand_id, v_r.restaurant_id, v_ingredient, v_product_id, 'purchase_receipt',
              purchasing.receipt_stock_quantity(v_ingredient, v_product_id, v_qty, v_unit, v_weight),
              (select recipe_unit_id from catalog.ingredients where id = v_ingredient),
              case when v_product_id is not null then v_qty end, nullif(btrim(v_line ->> 'lot_code'), ''), v_now,
              'receipt_lines', v_line_id);
    end if;
  end loop;

  if v_order = 0 then
    raise exception 'La recepción no tiene renglones.' using errcode = '22023';
  end if;
  if v_o.id is not null then
    -- Cada renglón pendiente de la OC lleva su decisión.
    select count(*) into v_missing from purchasing.purchase_order_lines l
     where l.purchase_order_id = v_o.id and l.deleted_at is null and not (l.id = any (v_seen))
       and l.received_quantity < l.quantity;
    if v_missing = 1 then
      raise exception 'Falta decidir 1 renglón de la orden: marcá OK u Observar.' using errcode = '22023';
    elsif v_missing > 1 then
      raise exception 'Faltan decidir % renglones de la orden: marcá OK u Observar en cada uno.', v_missing
        using errcode = '22023';
    end if;
  end if;
  if v_observed > 0 and (v_reason is null or length(v_reason) < 3) then
    raise exception 'Hubo observaciones: escribí el motivo.' using errcode = '22023';
  end if;

  if v_o.id is not null then
    v_result := case
      when exists (select 1 from purchasing.purchase_order_lines l
                    where l.purchase_order_id = v_o.id and l.deleted_at is null and l.received_quantity < l.quantity)
        then 'partial'
      when v_observed > 0 then 'with_differences'
      else 'complete' end;
    update purchasing.purchase_orders
       set status = case when v_result = 'partial' then 'partially_received'::purchasing.po_status
                         else 'received'::purchasing.po_status end
     where id = v_o.id;
  else
    v_result := 'complete';
  end if;
  update purchasing.receipts
     set status = 'closed', closed_at = v_now, closed_by = core.current_actor_id(), result = v_result, paper_kind = p_paper_kind,
         paper_number = nullif(btrim(p_paper_number), ''), cash_paid_amount = p_cash_paid_amount
   where id = v_r.id;

  -- Avisos: a quien pidió, siempre; a Compras, si hubo observaciones o efectivo; al chef, si hay artículos nuevos.
  if v_o.id is not null then
    v_title := case v_result
                 when 'complete' then format('Llegó la orden %s', v_o.number)
                 when 'partial' then format('Llegó parte de la orden %s', v_o.number)
                 else format('Llegó la orden %s, con observaciones', v_o.number) end;
    v_body := case v_result
                when 'complete' then 'Se recibió todo bien.'
                when 'partial' then 'Quedaron renglones pendientes: se pueden recibir cuando lleguen.'
                else format('Se recibió con %s %s.', v_observed,
                            case when v_observed = 1 then 'observación' else 'observaciones' end) end;
    if v_o.requested_by is distinct from core.current_actor_id() then
      insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
      values (v_o.requested_by, v_o.group_id, 'receipt_report', left(v_title, 200), left(v_body, 500),
              format('/compras/ordenes/%s?seccion=recepcion', v_o.id));
    end if;
  end if;
  -- Sin OC, siempre: nadie la pidió y Compras tiene que saber qué entró (Joaco, 2026-11-17).
  if v_observed > 0 or p_cash_paid_amount is not null or v_o.id is null then
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u, v_r.group_id, 'receipt_differences',
           left(case when v_o.id is not null then format('Recepción de la orden %s para revisar', v_o.number)
                     else format('Recepción sin OC de «%s» para revisar', coalesce(v_s.trade_name, v_s.name)) end, 200),
           left(concat_ws(' ',
                  case when v_o.id is null then 'Llegó sin orden de compra.' end,
                  case when v_observed = 1 then 'Tuvo 1 observación.'
                       when v_observed > 1 then format('Tuvo %s observaciones.', v_observed) end,
                  case when p_cash_paid_amount is not null
                       then 'Se pagó en efectivo: confirmá el importe.' end), 500),
           case when v_o.id is not null then format('/compras/ordenes/%s?seccion=recepcion', v_o.id) else '/compras/recepcion' end
      from purchasing.users_with_permission(v_r.group_id, 'purchasing.approve_orders') u;
  end if;
  if v_new_unmapped > 0 then
    insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
    select u, v_r.group_id, 'unmapped_article',
           left(case when v_new_unmapped = 1
                     then format('Un artículo nuevo de «%s» para mapear', coalesce(v_s.trade_name, v_s.name))
                     else format('%s artículos nuevos de «%s» para mapear', v_new_unmapped, coalesce(v_s.trade_name, v_s.name))
                end, 200),
           'Llegaron en una recepción y el sistema no los reconoce. Decí a qué materia prima corresponde cada uno.',
           '/materias-primas/sin-mapear'
      from purchasing.users_who_map(v_r.group_id) u;
  end if;

  return jsonb_build_object('result', 'applied', 'receipt_result', v_result, 'observed', v_observed,
                            'order_status', (select status from purchasing.purchase_orders where id = v_o.id),
                            'requester_name', case when v_o.id is not null then core.display_name(v_o.requested_by) end,
                            'new_unmapped', v_new_unmapped);
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_receipt_error(sqlstate, v_constraint, v_message);
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los renglones: las cantidades y el peso van con números, y la observación con una de las opciones.'
      using errcode = '22023';
end
$$;
comment on function purchasing.close_receipt(uuid, purchasing.paper_kind, text, jsonb, numeric, text) is
  'Cierra una recepción en una transacción: exige las fotos 1 y 2, la clase de papel y una decisión por cada renglón pendiente de la OC (y el motivo si hubo observaciones); suma lo recibido a la OC (recibida o recibida parcial), registra las entradas de stock en la unidad de uso (lo vencido no entra), manda a la cola de mapeo lo que no se reconoce y avisa a quien pidió, a Compras (observaciones, efectivo o sin OC) y al chef (artículos nuevos). Un renglón OK que pesa más de un 20 % distinto de lo estimado se tiene que observar. Pide purchasing.receive en el local.';
revoke execute on function purchasing.close_receipt(uuid, purchasing.paper_kind, text, jsonb, numeric, text) from public;
grant execute on function purchasing.close_receipt(uuid, purchasing.paper_kind, text, jsonb, numeric, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. La ficha dice quién cerró
-- ---------------------------------------------------------------------------
-- Una recepción entera: cabecera, fotos (la última de cada foto y página), renglones (los decididos o, si está abierta,
-- los pendientes de la OC) y el efectivo solo para quien ve precios en el local.
create or replace function purchasing.receipt_detail(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r     purchasing.receipts;
  v_o     purchasing.purchase_orders;
  v_cash  boolean;
  v_lines jsonb;
begin
  select * into v_r from purchasing.receipts where id = p_id and deleted_at is null;
  if v_r.id is null or not purchasing.can_in_restaurant('purchasing.view_orders', v_r.restaurant_id) then
    return null;
  end if;
  select * into v_o from purchasing.purchase_orders where id = v_r.purchase_order_id;
  v_cash := core.has_permission('prices.view', v_r.restaurant_id);
  if v_r.status = 'closed' then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', l.id, 'line_order', l.line_order, 'purchase_order_line_id', l.purchase_order_line_id,
             'name', coalesce(p.description, i.name, l.description), 'description', l.description,
             'package_name', pu.name, 'unit_name', u.name,
             'ordered', pol.quantity, 'received', l.received_quantity, 'weight', l.received_weight,
             'ok', l.ok, 'issue', l.issue, 'lot_code', l.lot_code, 'note', l.note,
             'unmapped', l.unmapped_article_id is not null,
             'photos', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'path', a.storage_path, 'page', a.page)
                                                  order by a.page), '[]'::jsonb)
                          from purchasing.attachments a where a.source_table = 'receipt_lines' and a.source_id = l.id))
             order by l.line_order), '[]'::jsonb)
      into v_lines
      from purchasing.receipt_lines l
      left join purchasing.purchase_order_lines pol on pol.id = l.purchase_order_line_id
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join catalog.units pu on pu.id = p.package_unit_id
      left join catalog.ingredients i on i.id = coalesce(l.ingredient_id, pol.ingredient_id)
      left join catalog.units u on u.id = pol.unit_id
     where l.receipt_id = v_r.id and l.deleted_at is null;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'purchase_order_line_id', l.id, 'line_order', l.line_order,
             'name', coalesce(p.description, i.name), 'package_name', pu.name, 'unit_name', u.name,
             'ordered', l.quantity, 'already_received', l.received_quantity,
             'pending', l.quantity - l.received_quantity,
             'billed_by_weight', coalesce(p.billed_by_weight, false),
             'estimated_kg', case when p.billed_by_weight and p.estimated_weight_per_unit is not null then
                               round((l.quantity - l.received_quantity) * p.units_per_package
                                     * p.estimated_weight_per_unit / case when cu.code = 'g' then 1000 else 1 end, 1) end,
             'without_invoice_name', l.ingredient_id is not null, 'note', l.line_note)
             order by l.line_order), '[]'::jsonb)
      into v_lines
      from purchasing.purchase_order_lines l
      left join catalog.purchase_products p on p.id = l.purchase_product_id
      left join catalog.units pu on pu.id = p.package_unit_id
      left join catalog.units cu on cu.id = p.content_unit_id
      left join catalog.ingredients i on i.id = l.ingredient_id
      left join catalog.units u on u.id = l.unit_id
     where l.purchase_order_id = v_r.purchase_order_id and l.deleted_at is null
       and l.received_quantity < l.quantity;
  end if;
  return jsonb_build_object(
    'id', v_r.id, 'status', v_r.status, 'result', v_r.result,
    'restaurant_id', v_r.restaurant_id, 'restaurant_name', (select name from org.restaurants where id = v_r.restaurant_id),
    'supplier_id', v_r.supplier_id,
    'supplier_name', (select coalesce(s.trade_name, s.name) from catalog.suppliers s where s.id = v_r.supplier_id),
    'purchase_order_id', v_r.purchase_order_id, 'order_number', v_o.number,
    'requested_by_name', case when v_o.id is not null then core.display_name(v_o.requested_by) end,
    'received_by_name', core.display_name(coalesce(v_r.closed_by, v_r.received_by)), 'mine', v_r.received_by = core.current_actor_id(),
    'started_at', v_r.created_at, 'closed_at', v_r.closed_at,
    'paper_kind', v_r.paper_kind, 'paper_number', v_r.paper_number,
    'can_see_cash', v_cash, 'cash_paid', v_r.cash_paid_amount is not null,
    'cash_paid_amount', case when v_cash then v_r.cash_paid_amount end,
    'can_receive', v_r.status = 'open' and purchasing.can_in_restaurant('purchasing.receive', v_r.restaurant_id),
    'photos', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.doc_kind, 'page', x.page,
                                                            'path', x.storage_path) order by x.doc_kind, x.page), '[]'::jsonb)
                 from (select distinct on (a.doc_kind, a.page) a.id, a.doc_kind, a.page, a.storage_path
                         from purchasing.attachments a
                        where a.source_table = 'receipts' and a.source_id = v_r.id
                        order by a.doc_kind, a.page, a.created_at desc, a.id) x),
    'lines', v_lines);
end
$$;
comment on function purchasing.receipt_detail(uuid) is
  'Una recepción entera (si la sesión ve las OC del local): cabecera, fotos (la última de cada foto y página), renglones (los decididos, o los pendientes de la OC si está abierta) y el efectivo solo para quien ve precios en el local. Vacío si no la ve.';
revoke execute on function purchasing.receipt_detail(uuid) from public;
grant execute on function purchasing.receipt_detail(uuid) to authenticated;

