-- Un CUIT por proveedor en cada grupo (pedido de Joaco, 2026-11-17; ADR-0055). Hasta ahora el «ya existe» lo
-- controlaba solo la importación. Ahora lo garantiza la base para todos los caminos (alta, ficha e importación), también
-- con dos cargas a la vez. Se compara el CUIT normalizado (sin guiones ni espacios): los cargados antes de la Fase 3
-- pueden estar con guiones. Los proveedores borrados no cuentan.

-- Si ya hay repetidos, la migración no sigue y dice cuáles: se unifican a mano antes de aplicarla.
do $$
declare
  v_dup text;
begin
  select string_agg(x, '; ') into v_dup
    from (select format('CUIT %s: %s', core.normalize_cuit(tax_id), string_agg(code, ', ' order by code)) as x
            from catalog.suppliers
           where deleted_at is null and core.normalize_cuit(tax_id) is not null
           group by group_id, core.normalize_cuit(tax_id)
          having count(*) > 1) d;
  if v_dup is not null then
    raise exception 'Hay proveedores con el mismo CUIT en un grupo. Unificalos antes de aplicar esta migración: %', v_dup;
  end if;
end
$$;

create unique index suppliers_tax_id_key on catalog.suppliers (group_id, core.normalize_cuit(tax_id))
  where deleted_at is null and core.normalize_cuit(tax_id) is not null;
comment on index catalog.suppliers_tax_id_key is
  'Un CUIT por proveedor en cada grupo (ADR-0055), comparado sin guiones ni espacios. Los borrados no cuentan.';

-- El mensaje en castellano del repetido, en las dos funciones que traducen errores (catálogo y compras).
create or replace function catalog.raise_friendly(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'ingredients_code_key' then 'Ya existe una materia prima con ese código en el grupo.'
    when p_constraint = 'ingredients_name_key' then 'Ya existe una materia prima con ese nombre en el grupo.'
    when p_constraint = 'suppliers_code_key' then 'Ya existe un proveedor con ese código en el grupo.'
    when p_constraint = 'suppliers_name_key' then 'Ya existe un proveedor con ese nombre en el grupo.'
    when p_constraint = 'suppliers_tax_id_key' then 'Ya hay un proveedor con ese CUIT en el grupo.'
    when p_constraint = 'purchase_products_code_key' then 'Ya existe un producto de compra con ese código en el grupo.'
    when p_constraint = 'ingredient_categories_name_key' then 'Ya existe una categoría con ese nombre en el mismo nivel.'
    when p_constraint = 'yield_processes_code_key' then 'Ya existe un proceso con ese código en el grupo.'
    when p_constraint = 'yield_processes_name_key' then 'Ya existe un proceso con ese nombre en el grupo.'
    when p_constraint like '%\_code\_check' then
      'El código va en mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).'
    when p_constraint in ('ingredients_name_check', 'suppliers_name_check') then
      'El nombre no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint in ('ingredient_categories_name_check', 'yield_processes_name_check') then
      'El nombre no puede quedar vacío ni pasar los 80 caracteres.'
    when p_constraint = 'purchase_products_description_check' then
      'La descripción no puede quedar vacía ni pasar los 200 caracteres.'
    when p_constraint = 'suppliers_tax_id_check' then 'El CUIT va solo con números y guiones.'
    when p_constraint = 'purchase_products_units_per_package_check' then 'Las unidades por envase van de 1 a 10.000.'
    when p_constraint in ('purchase_products_content_per_unit_check', 'ingredient_unit_conversions_factor_check') then
      'El valor tiene que ser mayor que cero.'
    when p_constraint like '%\_notes\_check' then 'Las observaciones son demasiado largas.'
    when p_state = '23503' then 'La categoría, el proveedor o la unidad elegidos no existen en este grupo.'
    else p_message
  end;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;

create or replace function purchasing.raise_friendly(p_state text, p_constraint text, p_message text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'suppliers_tax_id_valid' then 'El CUIT no es válido: revisá los números.'
    when p_constraint = 'suppliers_tax_id_key' then 'Ya hay un proveedor con ese CUIT en el grupo.'
    when p_constraint = 'suppliers_email_check' then 'Revisá el correo.'
    when p_constraint in ('suppliers_phone_check', 'suppliers_whatsapp_check') then
      'El teléfono va con números, espacios, +, guiones o paréntesis (de 6 a 30).'
    when p_constraint in ('suppliers_trade_name_check', 'suppliers_city_check', 'suppliers_sales_contact_check',
                          'suppliers_admin_contact_check') then
      'El texto no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint = 'suppliers_address_check' then 'El domicilio no puede quedar vacío ni pasar los 200 caracteres.'
    when p_constraint in ('supplier_terms_order_days_check', 'supplier_terms_delivery_days_check') then
      'Los días van de lunes a domingo, sin repetir.'
    when p_constraint = 'supplier_terms_receiving_check' then
      'El horario de recepción va con «desde» y «hasta», y «desde» es antes que «hasta».'
    when p_constraint = 'supplier_terms_channel_check' then
      'El dato no corresponde al canal: un teléfono para WhatsApp, un correo para mail o una dirección https:// para el portal.'
    when p_constraint = 'supplier_terms_billing_check' then 'Cada forma de facturar va una sola vez.'
    when p_constraint = 'supplier_payment_terms_days_check' then
      'En cuenta corriente, los días van de 1 a 180. En el resto de las condiciones no van días.'
    when p_constraint = 'supplier_payment_terms_minimum_check' then 'El pedido mínimo tiene que ser mayor que cero.'
    when p_constraint = 'supplier_payment_accounts_cbu_check' then 'El CBU tiene 22 números.'
    when p_constraint = 'supplier_payment_accounts_alias_check' then
      'El alias va de 6 a 20 caracteres: letras, números, puntos o guiones.'
    when p_constraint = 'supplier_payment_accounts_holder_tax_id_check' then 'El CUIT del titular no es válido.'
    when p_constraint = 'supplier_payment_accounts_code_check' then
      'El código de pago electrónico va de 4 a 40 letras, números o guiones.'
    when p_constraint = 'supplier_payment_accounts_method_check' then
      'La transferencia necesita CBU o alias, y el pago electrónico, su código.'
    when p_constraint in ('supplier_payment_accounts_bank_check', 'supplier_payment_accounts_holder_name_check') then
      'El banco o el titular no pueden quedar vacíos ni ser tan largos.'
    when p_constraint = 'supplier_categories_key' then 'Ese rubro ya está cargado.'
    when p_constraint = 'supplier_customer_numbers_key' then 'Ese local ya tiene un número de cliente con este proveedor.'
    when p_constraint = 'supplier_customer_numbers_number_check' then 'El número de cliente va de 1 a 30 caracteres.'
    when p_constraint = 'supplier_customer_numbers_restaurant_fkey' then 'El local elegido no es de este grupo.'
    when p_constraint = 'supplier_categories_category_fkey' then 'El rubro elegido no es de este grupo.'
    when p_state = '23502' then 'Falta un dato obligatorio: revisá la ficha.'
    else null
  end;
  if v_message is null then
    perform catalog.raise_friendly(p_state, p_constraint, p_message);
  end if;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;
