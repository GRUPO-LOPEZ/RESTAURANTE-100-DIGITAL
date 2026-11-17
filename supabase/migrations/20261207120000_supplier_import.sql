-- Importación de proveedores desde planilla, para la carga inicial (P1 de la Fase 3, ADR-0055).
--
-- 1. El alta y la ficha pasan a internas (create_supplier_internal y save_supplier_sheet_internal), sin execute para
--    nadie. create_supplier y save_supplier_sheet quedan como envoltorios: mismo permiso, mismo motivo, mismo resultado
--    y origen 'manual'. Así hay un solo camino de escritura.
-- 2. purchasing.import_suppliers valida y crea todos los proveedores de la planilla en una transacción, con origen
--    'import'. En la vista previa (o si alguna fila tiene error) hace todo y al final lo deshace: lo que se ve es lo
--    que va a pasar, y no queda nada creado, ni un código PROV ni auditoría.
--
-- Sin tablas de carga intermedia (excepción a .claude/rules/database.md, anotada en el ADR): son unas 30 filas, la
-- vista previa es la validación previa y no se toca nada hasta confirmar. El archivo no se guarda: lo que tiene queda en
-- la ficha de cada proveedor.

create function purchasing.create_supplier_internal(p_group_id uuid, p_name text, p_tax_id text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  -- Sin permisos ni motivo: los controla quien la llama (create_supplier o import_suppliers).
  if nullif(btrim(p_name), '') is null then
    raise exception 'Escribí la razón social.' using errcode = '23514';
  end if;
  insert into catalog.suppliers (group_id, code, name, tax_id)
  values (p_group_id, catalog.next_code(p_group_id, 'PROV-', 4), btrim(p_name), core.normalize_cuit(p_tax_id))
  returning id into v_id;
  insert into purchasing.supplier_terms (group_id, supplier_id) values (p_group_id, v_id);
  return v_id;
end
$$;
comment on function purchasing.create_supplier_internal(uuid, text, text) is
  'Interna: da de alta un proveedor con código automático (PROV-0001) y su operativa vacía. No controla permisos ni motivo.';
revoke execute on function purchasing.create_supplier_internal(uuid, text, text) from public, anon, authenticated;

create or replace function purchasing.create_supplier(p_group_id uuid, p_name text, p_tax_id text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_constraint text;
  v_message    text;
begin
  perform org.require(core.has_permission_in_group('purchasing.manage_suppliers', p_group_id),
                      'dar de alta proveedores en este grupo');
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo del alta.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  return purchasing.create_supplier_internal(p_group_id, p_name, p_tax_id);
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function purchasing.create_supplier(uuid, text, text, text) is
  'Da de alta un proveedor con código automático (PROV-0001) y su operativa vacía. Pide purchasing.manage_suppliers en el grupo y un motivo. El alta está en create_supplier_internal.';

create function purchasing.save_supplier_sheet_internal(p_supplier_id uuid, p_changes jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_s          catalog.suppliers;
  v_c          jsonb;
  v_item       jsonb;
  v_terms      purchasing.supplier_terms;
  v_pay        purchasing.supplier_payment_terms;
  v_ids        uuid[];
  v_id         uuid;
  v_acc        purchasing.supplier_payment_accounts;
  v_new        purchasing.supplier_payment_accounts;
  v_notes      text[] := '{}';
  v_constraint text;
  v_message    text;
begin
  -- Sin permisos ni motivo: los controla quien la llama (save_supplier_sheet o import_suppliers), que además fija el
  -- origen del cambio para la auditoría.
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null then
    raise exception 'Ese proveedor no existe.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, array['supplier', 'terms', 'payment_terms', 'accounts', 'categories',
                                          'customer_numbers']);

  -- Datos del proveedor.
  v_c := p_changes -> 'supplier';
  if v_c is not null then
    perform org.check_keys(v_c, array['name', 'trade_name', 'tax_id', 'vat_condition', 'address', 'city', 'phone',
                                      'whatsapp', 'email', 'sales_contact', 'admin_contact', 'notes']);
    if v_c ? 'name' and nullif(btrim(v_c ->> 'name'), '') is null then
      raise exception 'La razón social no puede quedar vacía.' using errcode = '23514';
    end if;
    update catalog.suppliers
       set name          = coalesce(purchasing.text_or(v_c, 'name', name), name),
           trade_name    = purchasing.text_or(v_c, 'trade_name', trade_name),
           tax_id        = case when v_c ? 'tax_id' then core.normalize_cuit(v_c ->> 'tax_id') else tax_id end,
           vat_condition = case when v_c ? 'vat_condition'
                                then nullif(v_c ->> 'vat_condition', '')::org.vat_condition else vat_condition end,
           address       = purchasing.text_or(v_c, 'address', address),
           city          = purchasing.text_or(v_c, 'city', city),
           phone         = purchasing.text_or(v_c, 'phone', phone),
           whatsapp      = purchasing.text_or(v_c, 'whatsapp', whatsapp),
           email         = lower(purchasing.text_or(v_c, 'email', email)),
           sales_contact = purchasing.text_or(v_c, 'sales_contact', sales_contact),
           admin_contact = purchasing.text_or(v_c, 'admin_contact', admin_contact),
           notes         = purchasing.text_or(v_c, 'notes', notes)
     where id = p_supplier_id;
  end if;

  -- Operativa.
  v_c := p_changes -> 'terms';
  if v_c is not null then
    perform org.check_keys(v_c, array['order_days', 'delivery_days', 'receiving_from', 'receiving_to', 'po_channel',
                                      'po_channel_target', 'billing_modes', 'price_list_frequency',
                                      'requires_po_approval']);
    select * into v_terms from purchasing.supplier_terms where supplier_id = p_supplier_id and deleted_at is null;
    if v_terms.id is null then
      insert into purchasing.supplier_terms (group_id, supplier_id) values (v_s.group_id, p_supplier_id)
      returning * into v_terms;
    end if;
    if v_c ? 'billing_modes' and jsonb_typeof(v_c -> 'billing_modes') <> 'array' then
      raise exception 'Las formas de facturar van en una lista.' using errcode = '22023';
    end if;
    update purchasing.supplier_terms
       set order_days           = case when v_c ? 'order_days' then purchasing.days_from(v_c -> 'order_days')
                                       else order_days end,
           delivery_days        = case when v_c ? 'delivery_days' then purchasing.days_from(v_c -> 'delivery_days')
                                       else delivery_days end,
           receiving_from       = case when v_c ? 'receiving_from' then nullif(v_c ->> 'receiving_from', '')::time
                                       else receiving_from end,
           receiving_to         = case when v_c ? 'receiving_to' then nullif(v_c ->> 'receiving_to', '')::time
                                       else receiving_to end,
           po_channel           = case when v_c ? 'po_channel'
                                       then nullif(v_c ->> 'po_channel', '')::purchasing.channel else po_channel end,
           po_channel_target    = purchasing.text_or(v_c, 'po_channel_target', po_channel_target),
           billing_modes        = case when v_c ? 'billing_modes'
                                       then array(select e::purchasing.billing_mode
                                                    from jsonb_array_elements_text(v_c -> 'billing_modes') as e)
                                       else billing_modes end,
           price_list_frequency = case when v_c ? 'price_list_frequency'
                                       then nullif(v_c ->> 'price_list_frequency', '')::purchasing.list_frequency
                                       else price_list_frequency end,
           requires_po_approval = case when v_c ? 'requires_po_approval'
                                       then (v_c ->> 'requires_po_approval')::boolean else requires_po_approval end
     where id = v_terms.id;
  end if;

  -- Condición de pago.
  v_c := p_changes -> 'payment_terms';
  if v_c is not null then
    perform org.check_keys(v_c, array['payment_terms', 'payment_days', 'minimum_order_amount']);
    select * into v_pay from purchasing.supplier_payment_terms where supplier_id = p_supplier_id and deleted_at is null;
    if v_pay.id is null then
      if nullif(v_c ->> 'payment_terms', '') is null then
        raise exception 'Elegí la condición de pago.' using errcode = '23514';
      end if;
      insert into purchasing.supplier_payment_terms (group_id, supplier_id, payment_terms, payment_days,
                                                     minimum_order_amount)
      values (v_s.group_id, p_supplier_id, (v_c ->> 'payment_terms')::purchasing.payment_terms,
              coalesce(nullif(v_c ->> 'payment_days', '')::smallint, 0),
              nullif(v_c ->> 'minimum_order_amount', '')::numeric);
    else
      update purchasing.supplier_payment_terms
         set payment_terms        = coalesce(nullif(v_c ->> 'payment_terms', '')::purchasing.payment_terms, payment_terms),
             payment_days         = case when v_c ? 'payment_days'
                                         then coalesce(nullif(v_c ->> 'payment_days', '')::smallint, 0)
                                         else payment_days end,
             minimum_order_amount = case when v_c ? 'minimum_order_amount'
                                         then nullif(v_c ->> 'minimum_order_amount', '')::numeric
                                         else minimum_order_amount end
       where id = v_pay.id;
    end if;
  end if;

  -- Cuentas: cada una con id (cambia o se quita con remove) o sin id (nueva).
  v_c := p_changes -> 'accounts';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 20 then
      raise exception 'Las cuentas van en una lista (hasta 20).' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(v_c) loop
      perform org.check_keys(v_item, array['id', 'remove', 'method', 'cbu', 'alias', 'bank', 'holder_name',
                                           'holder_tax_id', 'electronic_code', 'is_active']);
      if v_item ? 'id' then
        v_id := (v_item ->> 'id')::uuid;
        perform 1 from purchasing.supplier_payment_accounts
         where id = v_id and supplier_id = p_supplier_id and deleted_at is null;
        if not found then
          raise exception 'Esa cuenta no es de este proveedor.' using errcode = '22023';
        end if;
        select * into v_acc from purchasing.supplier_payment_accounts where id = v_id;
        if coalesce((v_item ->> 'remove')::boolean, false) then
          update purchasing.supplier_payment_accounts set deleted_at = now() where id = v_id;
          v_notes := v_notes || ('Se quitó: ' || purchasing.account_label(v_acc));
        else
          update purchasing.supplier_payment_accounts
             set method          = coalesce(nullif(v_item ->> 'method', '')::purchasing.payment_method, method),
                 cbu             = case when v_item ? 'cbu' then core.normalize_cuit(v_item ->> 'cbu') else cbu end,
                 alias           = purchasing.text_or(v_item, 'alias', alias),
                 bank            = purchasing.text_or(v_item, 'bank', bank),
                 holder_name     = purchasing.text_or(v_item, 'holder_name', holder_name),
                 holder_tax_id   = case when v_item ? 'holder_tax_id'
                                        then core.normalize_cuit(v_item ->> 'holder_tax_id') else holder_tax_id end,
                 electronic_code = purchasing.text_or(v_item, 'electronic_code', electronic_code),
                 is_active       = coalesce((v_item ->> 'is_active')::boolean, is_active)
           where id = v_id
          returning * into v_new;
          if purchasing.account_label(v_new) is distinct from purchasing.account_label(v_acc)
             or v_new.holder_tax_id is distinct from v_acc.holder_tax_id then
            v_notes := v_notes || ('Cambió: ' || purchasing.account_label(v_acc) || ' → ' || purchasing.account_label(v_new));
          end if;
        end if;
      else
        if nullif(v_item ->> 'method', '') is null then
          raise exception 'Elegí el medio de pago de la cuenta.' using errcode = '23514';
        end if;
        insert into purchasing.supplier_payment_accounts (group_id, supplier_id, method, cbu, alias, bank, holder_name,
                                                          holder_tax_id, electronic_code, is_active)
        values (v_s.group_id, p_supplier_id, (v_item ->> 'method')::purchasing.payment_method,
                core.normalize_cuit(v_item ->> 'cbu'), nullif(btrim(v_item ->> 'alias'), ''),
                nullif(btrim(v_item ->> 'bank'), ''), nullif(btrim(v_item ->> 'holder_name'), ''),
                core.normalize_cuit(v_item ->> 'holder_tax_id'), nullif(btrim(v_item ->> 'electronic_code'), ''),
                coalesce((v_item ->> 'is_active')::boolean, true))
        returning * into v_new;
        v_notes := v_notes || ('Nueva: ' || purchasing.account_label(v_new));
      end if;
    end loop;
    if cardinality(v_notes) > 0 then
      perform purchasing.notify_account_change(v_s, v_notes);
    end if;
  end if;

  -- Rubros: la lista entera de lo que provee.
  v_c := p_changes -> 'categories';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 60 then
      raise exception 'Los rubros van en una lista.' using errcode = '22023';
    end if;
    v_ids := array(select distinct (e #>> '{}')::uuid from jsonb_array_elements(v_c) as e);
    if exists (select 1 from unnest(v_ids) as x (id)
                where not exists (select 1 from catalog.ingredient_categories c
                                   where c.id = x.id and c.group_id = v_s.group_id and c.parent_id is null
                                     and c.deleted_at is null and c.is_active)) then
      raise exception 'Elegí rubros de compra vigentes (del primer nivel).' using errcode = '23514';
    end if;
    update purchasing.supplier_categories set deleted_at = now()
     where supplier_id = p_supplier_id and deleted_at is null and not (category_id = any (v_ids));
    insert into purchasing.supplier_categories (group_id, supplier_id, category_id)
    select v_s.group_id, p_supplier_id, x.id
      from unnest(v_ids) as x (id)
     where not exists (select 1 from purchasing.supplier_categories sc
                        where sc.supplier_id = p_supplier_id and sc.category_id = x.id and sc.deleted_at is null);
  end if;

  -- Números de cliente: la lista entera (local → número). Un local que no viene se quita.
  v_c := p_changes -> 'customer_numbers';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 200 then
      raise exception 'Los números de cliente van en una lista.' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(v_c) loop
      perform org.check_keys(v_item, array['restaurant_id', 'customer_number']);
      if not exists (select 1 from org.restaurants r
                      where r.id = (v_item ->> 'restaurant_id')::uuid and r.group_id = v_s.group_id
                        and r.deleted_at is null and r.status = 'active') then
        raise exception 'El número de cliente va en un local vigente del grupo.' using errcode = '23514';
      end if;
    end loop;
    update purchasing.supplier_customer_numbers n set deleted_at = now()
     where n.supplier_id = p_supplier_id and n.deleted_at is null
       and not exists (select 1 from jsonb_array_elements(v_c) as e
                        where (e ->> 'restaurant_id')::uuid = n.restaurant_id
                          and btrim(e ->> 'customer_number') = n.customer_number);
    insert into purchasing.supplier_customer_numbers (group_id, supplier_id, restaurant_id, customer_number)
    select v_s.group_id, p_supplier_id, (e ->> 'restaurant_id')::uuid, btrim(e ->> 'customer_number')
      from jsonb_array_elements(v_c) as e
     where not exists (select 1 from purchasing.supplier_customer_numbers n
                        where n.supplier_id = p_supplier_id and n.deleted_at is null
                          and n.restaurant_id = (e ->> 'restaurant_id')::uuid);
  end if;

  return jsonb_build_object('result', 'applied', 'stamp', purchasing.supplier_sheet_stamp_internal(p_supplier_id));
exception
  when unique_violation or check_violation or foreign_key_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform purchasing.raise_friendly(sqlstate, v_constraint, v_message);
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow
       or numeric_value_out_of_range then
    raise exception 'Hay un dato con un valor que no corresponde: revisá la ficha.' using errcode = '22023';
end
$$;
comment on function purchasing.save_supplier_sheet_internal(uuid, jsonb) is
  'Interna: guarda los bloques de la ficha de un proveedor (datos, operativa, condición de pago, cuentas, rubros y números de cliente). No controla permisos ni motivo: la llaman save_supplier_sheet (origen manual) e import_suppliers (origen import).';
revoke execute on function purchasing.save_supplier_sheet_internal(uuid, jsonb) from public, anon, authenticated;

create or replace function purchasing.save_supplier_sheet(p_supplier_id uuid, p_expected_stamp timestamptz,
                                                          p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s catalog.suppliers;
begin
  select * into v_s from catalog.suppliers where id = p_supplier_id and deleted_at is null;
  if v_s.id is null or not core.has_permission_in_group('purchasing.manage_suppliers', v_s.group_id) then
    return core.deny('purchasing.save_supplier_sheet', 'No tenés permiso para editar este proveedor.', null,
                     jsonb_build_object('supplier_id', p_supplier_id), v_s.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, array['supplier', 'terms', 'payment_terms', 'accounts', 'categories',
                                          'customer_numbers']);
  if p_changes = '{}'::jsonb then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  -- Dos guardados de la misma ficha van de a uno; el segundo ve que el primero cambió algo.
  perform 1 from catalog.suppliers where id = p_supplier_id for update;
  if p_expected_stamp is null
     or purchasing.supplier_sheet_stamp_internal(p_supplier_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió este proveedor mientras lo editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  return purchasing.save_supplier_sheet_internal(p_supplier_id, p_changes);
end
$$;
comment on function purchasing.save_supplier_sheet(uuid, timestamptz, jsonb, text) is
  'Guarda la ficha de un proveedor en una sola transacción, con motivo y control de cambios simultáneos (sello). Pide purchasing.manage_suppliers en el grupo. El guardado está en save_supplier_sheet_internal.';

-- La planilla entera: cada fila trae row, name, tax_id y los bloques de la ficha (supplier, terms, payment_terms) más
-- los rubros por nombre (categories). Devuelve qué pasa con cada fila y los totales.
create function purchasing.import_suppliers(p_group_id uuid, p_rows jsonb, p_confirm boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item     jsonb;
  v_row      integer;
  v_name     text;
  v_cuit     text;
  v_existing text;
  v_cat      text;
  v_cat_id   uuid;
  v_cat_ids  uuid[];
  v_errors   text[];
  v_changes  jsonb;
  v_id       uuid;
  v_out      jsonb := '[]'::jsonb;
  v_create   integer := 0;
  v_skip     integer := 0;
  v_bad      integer := 0;
  v_result   jsonb;
  v_state      text;
  v_constraint text;
  v_message    text;
begin
  if not core.has_permission_in_group('purchasing.manage_suppliers', p_group_id) then
    return core.deny('purchasing.import_suppliers', 'No tenés permiso para importar proveedores.', null,
                     jsonb_build_object('group_id', p_group_id), p_group_id);
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'La planilla no tiene proveedores.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 200 then
    raise exception 'La planilla tiene más de 200 proveedores. Partila en dos archivos.' using errcode = '22023';
  end if;
  if octet_length(p_rows::text) > 1048576 then
    raise exception 'La planilla pasa 1 MB.' using errcode = '22023';
  end if;
  if coalesce(p_confirm, false) and (p_reason is null or length(btrim(p_reason)) < 3) then
    raise exception 'Escribí el motivo de la importación.' using errcode = '22023';
  end if;
  perform core.set_change_context(coalesce(nullif(btrim(p_reason), ''), 'Vista previa de la importación'), 'import');
  -- Dos confirmaciones a la vez del mismo grupo (un doble clic) no pueden crear dos veces el mismo CUIT: van en fila.
  if coalesce(p_confirm, false) then
    perform pg_advisory_xact_lock(hashtext('purchasing.import_suppliers'), hashtext(p_group_id::text));
  end if;

  begin
    for v_item in select e from jsonb_array_elements(p_rows) as e loop
      if jsonb_typeof(v_item) <> 'object' then
        raise exception 'Cada proveedor va como un objeto.' using errcode = '22023';
      end if;
      perform org.check_keys(v_item, array['row', 'name', 'tax_id', 'supplier', 'terms', 'payment_terms', 'categories']);
      -- Solo lo que trae la planilla. La razón social y el CUIT van arriba (los controla esta función, no la ficha), y
      -- las cuentas de pago y los números de cliente no se importan.
      if v_item ? 'supplier' then
        if jsonb_typeof(v_item -> 'supplier') <> 'object' then
          raise exception 'Los datos del proveedor van como un objeto.' using errcode = '22023';
        end if;
        perform org.check_keys(v_item -> 'supplier', array['trade_name', 'vat_condition', 'address', 'city', 'phone',
                                                            'whatsapp', 'email', 'sales_contact', 'admin_contact']);
      end if;
      if v_item ? 'terms' then
        if jsonb_typeof(v_item -> 'terms') <> 'object' then
          raise exception 'La operativa va como un objeto.' using errcode = '22023';
        end if;
        perform org.check_keys(v_item -> 'terms', array['order_days', 'delivery_days', 'po_channel', 'po_channel_target',
                                                         'requires_po_approval']);
      end if;
      if jsonb_typeof(v_item -> 'payment_terms') = 'object' then
        perform org.check_keys(v_item -> 'payment_terms', array['payment_terms', 'payment_days', 'minimum_order_amount']);
      end if;
      v_row := (v_item ->> 'row')::integer;
      v_name := nullif(btrim(v_item ->> 'name'), '');
      v_cuit := core.normalize_cuit(v_item ->> 'tax_id');
      v_errors := '{}';
      v_existing := null;

      if v_name is null then
        v_errors := v_errors || 'Falta la razón social.'::text;
      end if;
      if v_cuit is null then
        v_errors := v_errors || 'Falta el CUIT.'::text;
      elsif not core.valid_cuit(v_cuit) then
        v_errors := v_errors || format('CUIT: «%s» no es un CUIT válido.', v_item ->> 'tax_id');
      elsif (select count(*) from jsonb_array_elements(p_rows) as o
              where core.normalize_cuit(o ->> 'tax_id') = v_cuit) > 1 then
        v_errors := v_errors || 'CUIT repetido en la planilla: dejá uno solo.'::text;
      else
        select s.code into v_existing from catalog.suppliers s
         where s.group_id = p_group_id and core.normalize_cuit(s.tax_id) = v_cuit and s.deleted_at is null
         order by s.created_at limit 1;
      end if;

      -- Rubros por nombre: de compra (primer nivel), vigentes y del grupo, sin importar tildes ni mayúsculas.
      v_cat_ids := '{}';
      if v_item ? 'categories' then
        if jsonb_typeof(v_item -> 'categories') <> 'array' or jsonb_array_length(v_item -> 'categories') > 60 then
          raise exception 'Los rubros van en una lista.' using errcode = '22023';
        end if;
        for v_cat in select e from jsonb_array_elements_text(v_item -> 'categories') as e loop
          select c.id into v_cat_id from catalog.ingredient_categories c
           where c.group_id = p_group_id and c.parent_id is null and c.deleted_at is null and c.is_active
             and purchasing.normalize_name(c.name) = purchasing.normalize_name(v_cat)
           limit 1;
          if v_cat_id is null then
            v_errors := v_errors || format('Rubros: «%s» no es un rubro de compra del grupo.', v_cat);
          elsif not v_cat_id = any (v_cat_ids) then
            v_cat_ids := v_cat_ids || v_cat_id;
          end if;
        end loop;
      end if;

      if cardinality(v_errors) = 0 and v_existing is not null then
        v_skip := v_skip + 1;
        v_out := v_out || jsonb_build_object('row', v_row, 'name', v_name, 'tax_id', v_cuit, 'status', 'skip',
                                             'message', format('Ya existe (%s): se omite.', v_existing));
        continue;
      end if;

      if cardinality(v_errors) = 0 then
        -- Cada proveedor en su subtransacción: si la base rechaza un dato, se deshace solo esa fila y queda el motivo.
        begin
          v_id := purchasing.create_supplier_internal(p_group_id, v_name, v_cuit);
          v_changes := jsonb_strip_nulls(jsonb_build_object(
            'supplier', nullif(coalesce(v_item -> 'supplier', '{}'::jsonb), '{}'::jsonb),
            'terms', nullif(coalesce(v_item -> 'terms', '{}'::jsonb), '{}'::jsonb),
            'payment_terms', case when jsonb_typeof(v_item -> 'payment_terms') = 'object' then v_item -> 'payment_terms' end,
            'categories', case when cardinality(v_cat_ids) > 0 then to_jsonb(v_cat_ids) end));
          if v_changes <> '{}'::jsonb then
            perform purchasing.save_supplier_sheet_internal(v_id, v_changes);
          end if;
        exception when data_exception or integrity_constraint_violation then
          -- El mismo mensaje en castellano que da la ficha (purchasing.raise_friendly).
          get stacked diagnostics v_state = returned_sqlstate, v_constraint = constraint_name, v_message = message_text;
          begin
            perform purchasing.raise_friendly(v_state, v_constraint, v_message);
          exception when others then
            -- En la importación no hay ficha abierta: el motivo apunta a la fila.
            v_errors := v_errors || replace(sqlerrm, 'revisá la ficha', 'revisá la fila');
          end;
        end;
      end if;

      if cardinality(v_errors) = 0 then
        v_create := v_create + 1;
        v_out := v_out || jsonb_build_object('row', v_row, 'name', v_name, 'tax_id', v_cuit, 'status', 'create',
                                             'message', 'Se crea.');
      else
        v_bad := v_bad + 1;
        v_out := v_out || jsonb_build_object('row', v_row, 'name', v_name, 'tax_id', v_cuit, 'status', 'error',
                                             'message', array_to_string(v_errors, ' '));
      end if;
    end loop;

    v_result := jsonb_build_object(
      'result', case when not coalesce(p_confirm, false) then 'preview' when v_bad > 0 then 'rejected' else 'applied' end,
      'rows', v_out,
      'totals', jsonb_build_object('rows', jsonb_array_length(p_rows), 'create', v_create, 'skip', v_skip,
                                   'error', v_bad));
    -- Vista previa, o confirmación con errores: se deshace todo (proveedores, códigos PROV y auditoría).
    if not coalesce(p_confirm, false) or v_bad > 0 then
      raise exception 'deshacer la importación' using errcode = 'LF001';
    end if;
  exception when sqlstate 'LF001' then
    null;
  end;
  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Hay un dato con un valor que no corresponde: revisá la planilla.' using errcode = '22023';
end
$$;
comment on function purchasing.import_suppliers(uuid, jsonb, boolean, text) is
  'Importa proveedores desde planilla (ADR-0055). Pide purchasing.manage_suppliers en el grupo. Con p_confirm falso es la vista previa: hace todo y lo deshace. Al confirmar crea todo en una transacción, con origen import y el motivo, o nada si alguna fila tiene error. Un CUIT que ya existe en el grupo se omite. Hasta 200 filas y 1 MB.';
revoke execute on function purchasing.import_suppliers(uuid, jsonb, boolean, text) from public, anon;
grant execute on function purchasing.import_suppliers(uuid, jsonb, boolean, text) to authenticated;
