-- Rubro con precios editable y producto de compra con envase fijo (ADR-0044, decisiones de Joaco del 2026-11-13).
--
-- 1. El rubro de una materia prima con precios lo cambia quien edita el catálogo (catalog.manage, que ya pide
--    update_ingredient), con motivo y auditoría. Antes pedía prices.configure, que ningún rol tenía junto con
--    catalog.manage: nadie lo podía cambiar. La unidad de recetas sigue fija con precios.
-- 2. Un producto de compra con precios no cambia su envase ni su contenido: el precio se carga por envase. Cada precio
--    ya guarda su contenido (base_quantity) y el costo no se mueve, pero los precios siguientes quedarían sobre otro
--    envase bajo el mismo producto (la historia deja de ser comparable) y las solicitudes pendientes no se podrían
--    aplicar. Si cambió el envase, es otro producto.
-- 3. El estado de la ficha deja de informar el rubro trabado e informa qué productos tienen precios (para que la
--    pantalla deshabilite el envase y el contenido de esos productos, con la misma regla que el trigger).

-- ---------------------------------------------------------------------------
-- 1. Materia prima: con precios, solo la unidad de recetas queda fija
-- ---------------------------------------------------------------------------
create or replace function catalog.guard_priced_ingredient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.recipe_unit_id is distinct from old.recipe_unit_id
     and exists (select 1 from costing.price_records p join catalog.purchase_products pp on pp.id = p.purchase_product_id
                  where pp.ingredient_id = new.id and p.deleted_at is null) then
    raise exception 'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).'
      using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function catalog.guard_priced_ingredient() is
  'Trigger de catalog.ingredients: con precios cargados, la unidad de uso no cambia. El rubro lo cambia quien edita el catálogo (ADR-0044).';

-- El trigger ya no mira el rubro: se dispara solo cuando cambia la unidad.
drop trigger guard_priced_ingredient on catalog.ingredients;
create trigger guard_priced_ingredient before update of recipe_unit_id on catalog.ingredients
  for each row execute function catalog.guard_priced_ingredient();

-- La regla del rubro ya no existe.
drop function catalog.category_locked_by_prices(uuid, uuid);

-- ---------------------------------------------------------------------------
-- 2. Producto de compra: con precios, el envase y el contenido no cambian
-- ---------------------------------------------------------------------------
create function catalog.purchase_product_has_prices_internal(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from costing.price_records p where p.purchase_product_id = p_id and p.deleted_at is null)
$$;
comment on function catalog.purchase_product_has_prices_internal(uuid) is
  'Interna: si el producto de compra tiene precios cargados. Un precio nunca se borra (costing.price_record_defaults lo impide), así que no hay forma de destrabar el envase. La usan el trigger guard_priced_product y catalog.ingredient_sheet_state.';
revoke execute on function catalog.purchase_product_has_prices_internal(uuid) from public;

create function catalog.guard_priced_product()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.package_unit_id is distinct from old.package_unit_id
      or new.units_per_package is distinct from old.units_per_package
      or new.content_per_unit is distinct from old.content_per_unit
      or new.content_unit_id is distinct from old.content_unit_id)
     and catalog.purchase_product_has_prices_internal(new.id) then
    raise exception 'Este producto ya tiene precios: el envase y el contenido no cambian. Si cambió, agregá otro producto de compra.'
      using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function catalog.guard_priced_product() is
  'Trigger de catalog.purchase_products: con precios cargados, el envase (unidad y unidades por envase) y el contenido (cantidad y unidad) no cambian: el precio se guarda por envase (ADR-0044).';
revoke execute on function catalog.guard_priced_product() from public;
create trigger guard_priced_product
  before update of package_unit_id, units_per_package, content_per_unit, content_unit_id on catalog.purchase_products
  for each row execute function catalog.guard_priced_product();

-- ---------------------------------------------------------------------------
-- 3. Estado de la ficha
-- ---------------------------------------------------------------------------
create or replace function catalog.ingredient_sheet_state(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'stamp', catalog.ingredient_sheet_stamp_internal(i.id),
           'has_prices', exists (select 1 from costing.price_records p
                                   join catalog.purchase_products pp on pp.id = p.purchase_product_id
                                  where pp.ingredient_id = i.id and p.deleted_at is null),
           'priced_products', coalesce((select jsonb_agg(pp.id order by pp.id)
                                          from catalog.purchase_products pp
                                         where pp.ingredient_id = i.id and pp.deleted_at is null
                                           and catalog.purchase_product_has_prices_internal(pp.id)), '[]'::jsonb))
    from catalog.ingredients i
   where i.id = p_id and i.deleted_at is null
     and core.has_permission_in_group('catalog.manage', i.group_id)
$$;
comment on function catalog.ingredient_sheet_state(uuid) is
  'Para editar la ficha de una materia prima: el sello del último cambio (para no pisar lo de otra persona), si tiene precios (su unidad de recetas no cambia) y qué productos de compra tienen precios (su envase y su contenido no cambian). Solo para quien la puede editar (catalog.manage); si no, null.';

-- ---------------------------------------------------------------------------
-- 4. Sin carrera entre cambiar el envase y registrar el primer precio (revisión de base y de seguridad)
-- ---------------------------------------------------------------------------
-- Todo precio nuevo pasa por este trigger. Lee el producto con for share: si otra transacción le está cambiando el
-- envase, espera a que termine y usa el contenido nuevo (si el precio venía aprobado con otro, lo rechaza). Y un
-- cambio de envase que llega después espera al precio y lo ve (guard_priced_product). Lo demás no cambia.
create or replace function costing.price_record_defaults()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_base numeric;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Un precio aprobado no se cambia ni se borra: cargá un precio nuevo.' using errcode = '42501';
  end if;
  select a.net_amount, a.gross_amount into new.net_package_price, new.gross_package_price
    from costing.package_amounts(new.package_price, new.discount_amount, new.document_type, new.vat_rate,
                                 new.price_includes_vat) a;
  -- El contenido del envase en la unidad de uso, tal como está al registrar el precio (queda congelado).
  -- Si viene el aprobado (desde una solicitud), tiene que ser el mismo: así nada cambia entre el control y
  -- el registro (revisión de seguridad, cuarta pasada).
  perform 1 from catalog.purchase_products pp where pp.id = new.purchase_product_id for share;
  select b.base_quantity into v_base
    from catalog.purchase_products pp
   cross join lateral catalog.to_base_quantity(pp.ingredient_id, pp.content_per_unit * pp.units_per_package,
                                               pp.content_unit_id) b
   where pp.id = new.purchase_product_id and b.status = 'ok';
  if coalesce(v_base, 0) <= 0 then
    raise exception 'El contenido de ese producto no se pasa a la unidad de uso de la materia prima: cargá primero su conversión.'
      using errcode = '23514';
  end if;
  if new.base_quantity is not null and new.base_quantity <> v_base then
    raise exception 'El contenido del producto cambió desde que se aprobó el precio: proponelo de nuevo.' using errcode = '23514';
  end if;
  new.base_quantity := v_base;
  return new;
end
$$;
comment on function costing.price_record_defaults() is
  'Trigger de costing.price_records: calcula neto, bruto y el contenido en la unidad de uso al registrar (queda congelado; lee el producto con for share para no cruzarse con un cambio de envase, ADR-0044), y rechaza cualquier cambio o borrado (solo inserción).';
