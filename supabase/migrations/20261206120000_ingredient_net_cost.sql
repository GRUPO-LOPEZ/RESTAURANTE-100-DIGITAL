-- La Chef ve el costo neto de la materia prima (ADR-0054).
--
-- La ficha de materia prima mostraba el costo neto con costing.ingredient_line_cost, que pide prices.view. La Chef
-- (executive_chef) tiene recipes.view_costs y no prices.view: el indicador quedaba vacío. Ya ve el costo por kg de cada
-- ingrediente en la ficha de receta; el neto es el mismo dato con la merma aplicada.
--
-- 1. El cálculo pasa a una interna (costing.ingredient_line_cost_internal), sin execute para nadie.
-- 2. costing.ingredient_line_cost queda como envoltorio con el mismo permiso de antes (prices.view).
-- 3. costing.ingredient_net_cost, nueva, pide recipes.view_costs y devuelve solo lo que muestra la ficha: el costo como se
--    compra y limpio de una cantidad, y del precio solo si está vencido, si es heredado y desde cuándo vale. Nunca el
--    producto, el proveedor ni el registro de precio.

create function costing.ingredient_line_cost_internal(p_ingredient_id uuid, p_restaurant_id uuid, p_quantity numeric,
                                                      p_unit_id uuid, p_basis text, p_process_id uuid, p_as_of date)
returns table (base_quantity numeric, purchase_quantity numeric, unit_cost numeric, line_cost numeric, price_level text,
               inherited boolean, price_record_id uuid, status text, valid_from date, stale boolean)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_base   record;
  v_qty    numeric;
  v_price  record;
begin
  if p_basis is null or p_basis not in ('purchase', 'clean', 'cooked') then
    raise exception 'La cantidad va como se compra, limpia o cocida.' using errcode = '22023';
  end if;
  select b.base_quantity, b.status into v_base from catalog.to_base_quantity(p_ingredient_id, p_quantity, p_unit_id) b;
  if v_base.status <> 'ok' then
    return query select null::numeric, null::numeric, null::numeric, null::numeric, null::text, null::boolean, null::uuid,
                        v_base.status, null::date, null::boolean;
    return;
  end if;
  v_qty := v_base.base_quantity;
  if p_basis <> 'purchase' then
    -- El mismo rendimiento que la receta, con el descongelado (ADR-0040). Sin proceso o sin estándar, vacío.
    v_qty := (select costing.purchase_quantity(v_base.base_quantity, p_basis, y.cleaning_yield, y.cooking_factor)
                from catalog.costing_yield(p_ingredient_id, p_process_id, null, null) y
               where p_process_id is not null);
    if v_qty is null then
      return query select v_base.base_quantity, null::numeric, null::numeric, null::numeric, null::text, null::boolean,
                          null::uuid, 'missing_yield'::text, null::date, null::boolean;
      return;
    end if;
  end if;
  select * into v_price
    from costing.resolve_price_internal(p_ingredient_id, p_restaurant_id,
                                        coalesce(p_as_of, (now() at time zone 'America/Argentina/Buenos_Aires')::date));
  return query select v_base.base_quantity, v_qty, v_price.unit_cost,
                      case when v_price.unit_cost is null then null else v_qty * v_price.unit_cost end,
                      v_price.price_level, v_price.inherited, v_price.price_record_id,
                      case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity'
                           else v_price.status end,
                      v_price.valid_from, v_price.stale;
end
$$;

revoke execute on function costing.ingredient_line_cost_internal(uuid, uuid, numeric, uuid, text, uuid, date)
  from public, anon, authenticated;

comment on function costing.ingredient_line_cost_internal(uuid, uuid, numeric, uuid, text, uuid, date) is
  'Interna: el costo de una cantidad de materia prima en un local (unidad de uso, rendimiento de la receta con el descongelado y precio que vale). No controla permisos: la llaman ingredient_line_cost (prices.view) e ingredient_net_cost (recipes.view_costs). Estados: ok, missing_conversion, missing_yield, missing_price o missing_legal_entity (nunca $ 0).';

-- El envoltorio de siempre: misma firma, mismo resultado y mismo permiso (prices.view).
create or replace function costing.ingredient_line_cost(p_ingredient_id uuid, p_restaurant_id uuid, p_quantity numeric,
                                                        p_unit_id uuid, p_basis text default 'purchase',
                                                        p_process_id uuid default null,
                                                        p_as_of date default (now() at time zone 'America/Argentina/Buenos_Aires')::date)
returns table (base_quantity numeric, purchase_quantity numeric, unit_cost numeric, line_cost numeric, price_level text,
               inherited boolean, price_record_id uuid, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission('prices.view', p_restaurant_id)
                      and exists (select 1 from catalog.ingredients i join org.restaurants r on r.group_id = i.group_id
                                   where i.id = p_ingredient_id and r.id = p_restaurant_id),
                      'ver costos de este local');
  return query select c.base_quantity, c.purchase_quantity, c.unit_cost, c.line_cost, c.price_level, c.inherited,
                      c.price_record_id, c.status
                 from costing.ingredient_line_cost_internal(p_ingredient_id, p_restaurant_id, p_quantity, p_unit_id,
                                                            p_basis, p_process_id, p_as_of) c;
end
$$;

comment on function costing.ingredient_line_cost(uuid, uuid, numeric, uuid, text, uuid, date) is
  'Costo de una línea de materia prima en un local: pasa la cantidad a la unidad de uso, aplica el rendimiento que usa la receta (limpia o cocida, con el descongelado si se compra congelada: catalog.costing_yield) y el precio que vale. Estados: ok, missing_conversion, missing_yield, missing_price o missing_legal_entity (nunca $ 0). Pide prices.view en el local. El cálculo está en ingredient_line_cost_internal.';

create function costing.ingredient_net_cost(p_ingredient_id uuid, p_restaurant_id uuid, p_quantity numeric,
                                            p_unit_id uuid, p_process_id uuid default null)
returns table (gross numeric, net numeric, gross_status text, net_status text, stale boolean, inherited boolean,
               valid_from date)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  g record;
  n record;
  p record;
begin
  -- Una materia prima o un local borrados no tienen ficha: se rechazan. Una inactiva sí (su ficha muestra el costo).
  perform org.require(core.has_permission('recipes.view_costs', p_restaurant_id)
                      and exists (select 1 from catalog.ingredients i join org.restaurants r on r.group_id = i.group_id
                                   where i.id = p_ingredient_id and r.id = p_restaurant_id
                                     and i.deleted_at is null and r.deleted_at is null),
                      'ver costos de este local');
  -- Del precio que vale, solo vencido, heredado y desde cuándo; aparte, así se ve aunque falte la conversión de unidad.
  select x.stale, x.inherited, x.valid_from into p
    from costing.resolve_price_internal(p_ingredient_id, p_restaurant_id, v_today) x;
  select * into g from costing.ingredient_line_cost_internal(p_ingredient_id, p_restaurant_id, p_quantity, p_unit_id,
                                                             'purchase', null, v_today);
  if p_process_id is null then
    -- Sin proceso de limpieza no hay neto: vacío con su motivo, nunca el bruto como si fuera el neto.
    select null::numeric as line_cost, 'missing_yield'::text as status into n;
  else
    select * into n from costing.ingredient_line_cost_internal(p_ingredient_id, p_restaurant_id, p_quantity, p_unit_id,
                                                               'clean', p_process_id, v_today);
  end if;
  return query select g.line_cost, n.line_cost, g.status, n.status, coalesce(p.stale, false), coalesce(p.inherited, false),
                      p.valid_from;
end
$$;

revoke execute on function costing.ingredient_net_cost(uuid, uuid, numeric, uuid, uuid) from public, anon;
grant execute on function costing.ingredient_net_cost(uuid, uuid, numeric, uuid, uuid) to authenticated;

comment on function costing.ingredient_net_cost(uuid, uuid, numeric, uuid, uuid) is
  'Para la ficha de materia prima: el costo de una cantidad como se compra (gross) y limpia (net, con el proceso de limpieza y el descongelado), y del precio que vale solo si está vencido, si es heredado y desde cuándo. Pide recipes.view_costs en el local (la Chef lo ve sin prices.view; ADR-0054). No devuelve producto, proveedor ni registro de precio. Sin proceso o sin precio, vacío con su estado (nunca $ 0).';
