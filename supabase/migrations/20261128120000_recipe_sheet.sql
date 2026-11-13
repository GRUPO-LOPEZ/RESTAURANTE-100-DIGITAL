-- Ficha única de receta (Prompt 2 de Soy, 2026-11-12; ADR-0042).
--
-- 1. El rendimiento objetivo de una preparación (peso neto ÷ peso bruto) queda congelado en la versión al pedir la
--    revisión: es contra lo que va a comparar el futuro control de lotes.
-- 2. El motor de costos calcula también líneas que todavía no se guardaron (la grilla de la ficha), sin repetir sus
--    reglas en la pantalla.
-- 3. Las medidas que admite cada materia prima, para ofrecer solo unidades que se pueden convertir.
-- 4. recipes.save_sheet: datos, rendimiento, líneas y pasos en una sola transacción, con un solo motivo.

-- ---------------------------------------------------------------------------
-- 1. Rendimiento objetivo
-- ---------------------------------------------------------------------------
alter table recipes.recipe_versions
  add column target_yield_ratio numeric(9,6) check (target_yield_ratio is null or target_yield_ratio > 0);
comment on column recipes.recipe_versions.target_yield_ratio is
  'Rendimiento objetivo de una preparación: peso neto (el rendimiento, en g) ÷ peso bruto (la suma de las líneas, en g). Lo calcula la base al pedir la revisión y queda congelado con la versión aprobada; lo lee el control de lotes. Vacío en los platos o si alguna línea no se puede pasar a gramos.';

-- Al pasar de borrador a revisión. Desde «approved» la versión no cambia (core.enforce_version_rules), así que el
-- valor que se aprueba es el que queda.
create function recipes.set_target_yield()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'in_review' and old.status = 'draft' then
    -- Fuera de la columna (una preparación que pesa mil veces más, o casi nada) queda vacío: nunca frena la revisión.
    new.target_yield_ratio := (
      select l.factor from recipes.cooking_loss(new.id) l
       where l.status = 'ok' and l.factor > 0 and l.factor < 1000
         and (select r.recipe_type from recipes.recipes r where r.id = new.recipe_id) <> 'dish');
  end if;
  return new;
end
$$;
comment on function recipes.set_target_yield() is
  'Interna (trigger): al pedir la revisión de una preparación, guarda su rendimiento objetivo (recipes.cooking_loss). En un plato queda vacío.';
revoke execute on function recipes.set_target_yield() from public;
create trigger set_target_yield before update of status on recipes.recipe_versions
  for each row execute function recipes.set_target_yield();

-- ---------------------------------------------------------------------------
-- 3. Medidas que admite cada materia prima
-- ---------------------------------------------------------------------------
-- Con la sesión de la persona: solo las materias primas que ve.
create function catalog.ingredient_unit_options(p_ids uuid[])
returns table (ingredient_id uuid, dimension catalog.dimension, has_density boolean, has_unit_weight boolean)
language sql
stable
set search_path = ''
as $$
  select i.id, u.dimension,
         exists (select 1 from catalog.ingredient_unit_conversions c
                  where c.ingredient_id = i.id and c.kind = 'density' and c.deleted_at is null),
         exists (select 1 from catalog.ingredient_unit_conversions c
                  where c.ingredient_id = i.id and c.kind = 'unit_weight' and c.deleted_at is null)
    from catalog.ingredients i
    join catalog.units u on u.id = i.recipe_unit_id
   where i.id = any (p_ids[1:200]) and i.deleted_at is null
$$;
comment on function catalog.ingredient_unit_options(uuid[]) is
  'Medida de uso de cada materia prima y si tiene densidad o peso por unidad: con eso la ficha ofrece solo unidades que se pueden convertir. Hasta 200. Respeta RLS.';
revoke execute on function catalog.ingredient_unit_options(uuid[]) from public, anon;
grant execute on function catalog.ingredient_unit_options(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Guardado en lote
-- ---------------------------------------------------------------------------
-- Una función de escritura que niega devuelve {result: denied} sin error: dentro del lote, eso deshace todo.
create function recipes.require_applied(p_res jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_res ->> 'result' = 'denied' then
    raise exception '%', coalesce(p_res ->> 'message', 'No tenés permiso para hacer ese cambio.') using errcode = '42501';
  end if;
end
$$;
comment on function recipes.require_applied(jsonb) is
  'Interna: dentro de recipes.save_sheet, si una función devolvió denied, corta el lote (no se guarda nada a medias).';
revoke execute on function recipes.require_applied(jsonb) from public;

-- Cada bloque es opcional (null: no se toca). Llama a las funciones de siempre dentro de la misma transacción: si
-- alguna falla o niega, no se guarda nada. Si lo que se ve es la versión vigente, primero crea el borrador (la vigente
-- nunca cambia). En un plato con peso de porción, las porciones salen solas: peso de las líneas ÷ peso de la porción.
-- Si alguna línea no se puede pasar a gramos, se guarda igual sin recalcular las porciones y se avisa; para enviar a
-- revisión, en cambio, tienen que poder calcularse (decisión de Joaco del 2026-11-12).
create function recipes.save_sheet(p_recipe_id uuid, p_version_id uuid, p_expected_updated_at timestamptz,
                                   p_recipe jsonb, p_draft jsonb, p_lines jsonb, p_steps jsonb, p_reason text,
                                   p_submit boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r        recipes.recipes;
  v_v        recipes.recipe_versions;
  v_id       uuid;
  v_res      jsonb;
  v_grams    numeric;
  v_portions numeric;
  v_portion  uuid;
  v_created  boolean := false;
  v_warning  text;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null;
  select * into v_v from recipes.recipe_versions where id = p_version_id and recipe_id = p_recipe_id and deleted_at is null;
  if v_r.id is null or v_v.id is null
     or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.save_sheet', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id, 'version_id', p_version_id),
                     v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if coalesce(p_submit, false) and not recipes.allowed('recipes.review', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.save_sheet', 'No tenés permiso para pedir la revisión de esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id, 'version_id', p_version_id),
                     v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;

  if v_v.status = 'published' then
    -- Se edita sobre lo que se ve: el borrador nace de la vigente, en la misma transacción.
    v_res := recipes.new_version(p_recipe_id, p_reason);
    perform recipes.require_applied(v_res);
    v_id := (v_res ->> 'id')::uuid;
    v_created := true;
  else
    v_id := p_version_id;
    perform recipes.open_draft(v_id, p_expected_updated_at);
  end if;

  if p_recipe is not null then
    perform recipes.require_applied(recipes.update_recipe(p_recipe_id, p_recipe, p_reason));
  end if;
  if p_draft is not null then
    perform recipes.require_applied(recipes.save_draft(v_id, p_draft, p_reason, null));
  end if;
  if p_lines is not null then
    perform recipes.require_applied(recipes.set_components(v_id, p_lines, p_reason, null));
  end if;
  select * into v_v from recipes.recipe_versions where id = v_id;
  select * into v_r from recipes.recipes where id = p_recipe_id;
  if v_r.recipe_type = 'dish' and v_v.portion_grams is not null
     and (p_lines is not null or coalesce(p_draft ? 'portion_grams', false)) then
    select l.input_grams into v_grams from recipes.cooking_loss(v_id) l;
    if v_grams is null then
      if coalesce(p_submit, false) then
        raise exception 'Para enviarla a revisión, todas las líneas tienen que poder pasarse a gramos: así se calculan las porciones.'
          using errcode = '23514';
      end if;
      v_warning := 'Las porciones no se recalcularon: falta pasar algún ingrediente a gramos (densidad o peso por unidad).';
    else
      v_portions := round(v_grams / v_v.portion_grams, 2);
      if v_portions < 1 then
        raise exception 'El peso de la porción es mayor que el de toda la receta.' using errcode = '23514';
      end if;
      select u.id into v_portion from catalog.units u where u.code = 'portion' and u.deleted_at is null;
      if v_portion is null then
        raise exception 'Falta la unidad «porción» en el sistema: avisale a quien administra las unidades.' using errcode = '23514';
      end if;
      perform core.set_change_context(p_reason, 'manual');
      -- portions es la cantidad de porciones enteras que se venden; el rendimiento guarda los decimales.
      update recipes.recipe_versions
         set yield_quantity = v_portions, yield_unit_id = v_portion, portions = least(floor(v_portions), 100000)::integer
       where id = v_id;
    end if;
  end if;

  -- Los pasos, después del rendimiento: la capacidad de cada equipo va en su unidad.
  if p_steps is not null then
    perform recipes.require_applied(recipes.set_steps(v_id, p_steps, p_reason, null));
  end if;

  if coalesce(p_submit, false) then
    v_res := recipes.request_review(v_id, p_reason);
    perform recipes.require_applied(v_res);
    return jsonb_build_object('result', 'pending_approval', 'version_id', v_id, 'created', v_created,
                              'request_id', v_res ->> 'request_id',
                              'message', 'Cambios guardados. Queda en revisión: la tiene que aprobar otra persona con permiso de publicar.');
  end if;
  return jsonb_build_object('result', 'applied', 'version_id', v_id, 'created', v_created,
                            'updated_at', (select updated_at from recipes.recipe_versions where id = v_id),
                            'warning', v_warning,
                            'message', case when v_created then 'Cambios guardados en un borrador nuevo. La versión vigente sigue igual hasta que se publique.'
                                            else 'Cambios guardados.' end
                                       || coalesce(' ' || v_warning, ''));
end
$$;
comment on function recipes.save_sheet(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb, text, boolean) is
  'Guarda la ficha de una receta en una sola transacción: datos (update_recipe), rendimiento y textos (save_draft), líneas (set_components) y pasos (set_steps), cada uno opcional, con un solo motivo. Si la versión es la vigente, crea el borrador. En un plato con peso de porción calcula las porciones. Con p_submit, además pide la revisión. Pide recipes.draft (y recipes.review para enviar).';
revoke execute on function recipes.save_sheet(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb, text, boolean) from public, anon;
grant execute on function recipes.save_sheet(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Líneas sin guardar
-- ---------------------------------------------------------------------------
-- La función vigente (20261126120000_units_and_waste) con un solo cambio: si p_memo trae 'lines', calcula esas
-- líneas en lugar de las guardadas. Sin 'lines', el resultado es el mismo (lo controlan las pruebas 238 y 270).
create or replace function costing.recipe_line_costs_internal(p_version_id uuid, p_restaurant_id uuid, p_as_of date, p_memo jsonb DEFAULT NULL::jsonb)
 RETURNS SETOF costing.recipe_cost_line
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  c        record;
  l        costing.recipe_cost_line;
  v_vat    text;
  v_conv   record;
  v_prof   record;
  v_price  record;
  v_sub    record;
  v_tot    costing.recipe_cost_total;
  v_memo   jsonb;
  v_new    numeric;
  -- Las versiones que se están calculando: un círculo a través de una variante no se recorre.
  v_path   jsonb := coalesce(p_memo -> 'path', '[]'::jsonb) || to_jsonb(p_version_id::text);
begin
  select e.vat_condition::text into v_vat
    from org.restaurants r join org.legal_entities e on e.id = r.legal_entity_id and e.deleted_at is null
   where r.id = p_restaurant_id;

  for c in
    select x.id, x.line_order, x.ingredient_id, x.sub_recipe_id, x.quantity, x.unit_id, x.quantity_basis::text as basis,
           x.yield_profile_id, q.base_quantity as frozen, q.base_unit_id as frozen_unit, i.recipe_unit_id as use_unit,
           coalesce(i.name, s.name) as item, u.dimension as line_dimension
      from recipes.recipe_components x
      join catalog.units u on u.id = x.unit_id
      left join recipes.component_base_quantities q on q.recipe_component_id = x.id
      left join catalog.ingredients i on i.id = x.ingredient_id
      left join recipes.recipes s on s.id = x.sub_recipe_id
     where p_memo -> 'lines' is null and x.recipe_version_id = p_version_id and x.deleted_at is null
    union all
    -- Líneas sin guardar (la grilla de la ficha): ya validadas por costing.preview_sheet_lines.
    select null::uuid, n.line_order, n.ingredient_id, n.sub_recipe_id, n.quantity, u.id, n.basis, n.yield_profile_id,
           null::numeric, null::uuid, i.recipe_unit_id, coalesce(i.name, s.name), u.dimension
      from jsonb_to_recordset(case when jsonb_typeof(p_memo -> 'lines') = 'array' then p_memo -> 'lines' end)
             as n (line_order integer, ingredient_id uuid, sub_recipe_id uuid, quantity numeric, unit text, basis text,
                   yield_profile_id uuid)
      join catalog.units u on u.code = n.unit and u.deleted_at is null
      left join catalog.ingredients i on i.id = n.ingredient_id
      left join recipes.recipes s on s.id = n.sub_recipe_id
     order by 2
  loop
    l := null;
    l.component_id := c.id; l.line_order := c.line_order; l.item := c.item; l.ingredient_id := c.ingredient_id;
    l.sub_recipe_id := c.sub_recipe_id; l.quantity := c.quantity; l.unit_id := c.unit_id; l.quantity_basis := c.basis;
    l.base_quantity := c.frozen; l.vat_condition := v_vat; l.estimated := false; l.stale := false; l.status := 'ok';

    -- Un escenario cambia el gramaje de una línea: la cantidad congelada se ajusta en la misma proporción.
    v_new := (p_memo -> 'quantities' ->> c.id::text)::numeric;
    if v_new is not null then
      l.quantity := v_new;
      l.base_quantity := c.frozen * v_new / nullif(c.quantity, 0);
    end if;

    if c.ingredient_id is not null then
      -- Lo publicado usa la cantidad congelada; un borrador, la conversión de hoy. Si la materia prima cambió
      -- de unidad de uso, la cantidad congelada ya no se puede multiplicar por su precio.
      if c.frozen is not null and c.frozen_unit is distinct from c.use_unit then
        l.status := 'missing_conversion';
      elsif l.base_quantity is null then
        select b.base_quantity, b.status into v_conv from catalog.to_base_quantity(c.ingredient_id, l.quantity, c.unit_id) b;
        l.base_quantity := v_conv.base_quantity;
        if v_conv.status <> 'ok' then
          l.status := v_conv.status;
        end if;
      end if;

      if l.status = 'ok' and c.basis <> 'purchase' then
        v_memo := p_memo -> 'yields' -> c.ingredient_id::text;
        if v_memo is not null then
          -- Un escenario simula otro rendimiento. Si la materia prima se compra congelada, se le suma el descongelado
          -- aprobado, como en el costo real (ADR-0040); sin él, queda no definido.
          l.cleaning_yield := round((v_memo ->> 'cleaning_yield')::numeric
                                    * catalog.thawing_factor(c.ingredient_id,
                                                             (select p.process_id from catalog.ingredient_yield_profiles p
                                                               where p.id = c.yield_profile_id), null), 4);
          l.cooking_factor := (v_memo ->> 'cooking_factor')::numeric;
        else
          -- Siempre el estándar aprobado hoy para ese proceso, corte y proveedor (ADR-0024, respuesta 6), más el
          -- descongelado si la materia prima se compra congelada (ADR-0040).
          select p.process_id, p.cut, p.supplier_id into v_prof
            from catalog.ingredient_yield_profiles p where p.id = c.yield_profile_id;
          if found then
            select a.profile_id, a.cleaning_yield, a.cooking_factor into l.yield_profile_id, l.cleaning_yield, l.cooking_factor
              from catalog.costing_yield(c.ingredient_id, v_prof.process_id, v_prof.cut, v_prof.supplier_id) a;
          end if;
          if l.yield_profile_id is null then
            l.status := 'missing_yield';
          end if;
        end if;
      end if;

      if l.status = 'ok' then
        l.purchase_quantity := costing.purchase_quantity(l.base_quantity, c.basis, l.cleaning_yield, l.cooking_factor);
        if l.purchase_quantity is null then
          l.status := 'missing_yield';
        end if;
      end if;

      if l.status = 'ok' then
        v_memo := p_memo -> 'prices' -> c.ingredient_id::text;
        if v_memo is not null then
          select * into v_price
            from jsonb_to_record(v_memo) as m (price_record_id uuid, price_level text, inherited boolean, gross_unit_cost numeric,
                                               unit_cost numeric, stale boolean, status text);
        else
          select * into v_price from costing.resolve_price_internal(c.ingredient_id, p_restaurant_id, p_as_of);
        end if;
        l.price_record_id := v_price.price_record_id;
        l.price_level := v_price.price_level;
        l.unit_cost := v_price.unit_cost;
        l.gross_unit_cost := v_price.gross_unit_cost;
        l.stale := coalesce(v_price.stale, false);
        l.estimated := coalesce(v_price.inherited, false);
        l.status := case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity' else v_price.status end;
        l.line_cost := l.purchase_quantity * l.unit_cost;
        l.line_gross_cost := l.purchase_quantity * l.gross_unit_cost;
        if l.price_record_id is not null then
          select r.base_quantity into l.package_base_quantity from costing.price_records r where r.id = l.price_record_id;
        end if;
      end if;
    else
      -- La variante del local, si está publicada; si no, la preparación de la línea.
      select v.id, v.recipe_id, r.name, v.yield_quantity * recipes.unit_to_base(v.yield_unit_id) as yield_base,
             yu.dimension as yield_dimension into v_sub
        from recipes.recipe_versions v
        join recipes.recipes r on r.id = v.recipe_id
        left join catalog.units yu on yu.id = v.yield_unit_id
       where v.status = 'published' and r.deleted_at is null
         and (r.id = c.sub_recipe_id
              or (r.variant_of_recipe_id = c.sub_recipe_id and r.restaurant_id = p_restaurant_id and r.is_active))
       order by r.variant_of_recipe_id is null
       limit 1;
      if not found then
        l.status := 'missing_sub_recipe';
      else
        l.sub_recipe_id := v_sub.recipe_id;
        l.sub_recipe_version_id := v_sub.id;
        l.item := v_sub.name;
        if l.base_quantity is null then
          l.base_quantity := l.quantity * recipes.unit_to_base(c.unit_id);
        end if;
        v_memo := p_memo -> 'subs' -> v_sub.id::text;
        if v_memo is not null then
          v_tot := jsonb_populate_record(null::costing.recipe_cost_total, v_memo);
        elsif v_path ? v_sub.id::text then
          v_tot := row(null, null, null, null, 'incomplete')::costing.recipe_cost_total;
        else
          v_tot := costing.recipe_totals_internal(v_sub.id, p_restaurant_id, p_as_of,
                                                  -- Las líneas sin guardar son de esta receta, no de su preparación.
                                                  (coalesce(p_memo, '{}'::jsonb) - 'lines') || jsonb_build_object('path', v_path));
        end if;
        l.estimated := v_tot.reliability = 'estimated';
        l.stale := v_tot.reliability = 'stale';
        -- Una variante puede rendir en otra dimensión o en un envase: no se adivina, queda incompleto.
        if coalesce(v_sub.yield_base, 0) <= 0 or l.base_quantity is null
           or v_sub.yield_dimension is distinct from c.line_dimension then
          l.status := 'missing_yield';
        else
          l.gross_unit_cost := v_tot.total_gross_cost / v_sub.yield_base;
          l.line_gross_cost := l.base_quantity * l.gross_unit_cost;
          if v_tot.total_cost is null or v_tot.reliability = 'incomplete' then
            l.status := 'incomplete_sub_recipe';
          else
            l.unit_cost := v_tot.total_cost / v_sub.yield_base;
            l.line_cost := l.base_quantity * l.unit_cost;
          end if;
        end if;
      end if;
    end if;
    return next l;
  end loop;
end
$$;

comment on function costing.recipe_line_costs_internal(uuid, uuid, date, jsonb) is
  'Interna: las líneas de una versión calculadas en un local (o, con p_memo.lines, líneas sin guardar de la ficha). El rendimiento de cada línea es el estándar aprobado del proceso, por el de descongelado si la materia prima se compra congelada (catalog.costing_yield, ADR-0040); en un escenario, el simulado por el de descongelado. Estados: ok, missing_conversion, missing_yield, missing_price, missing_legal_entity, missing_sub_recipe, incomplete_sub_recipe.';

-- Lo que la grilla muestra mientras se escribe: el peso en gramos de cada línea y, con permiso, su costo y su costo
-- por unidad base en el local. Usa el mismo motor que el costo oficial (p_memo.lines). Solo la usa quien puede editar o
-- publicar la receta: el costo de una fila inventada equivale a un precio, así que se da a quien ya podía obtenerlo
-- guardando un borrador (decisión de Joaco del 2026-11-12, revisión de seguridad). El costo, además, pide
-- recipes.view_costs en el local; el costo por unidad (el precio), prices.view (ADR-0032). Lo demás va vacío.
create function costing.preview_sheet_lines(p_version_id uuid, p_restaurant_id uuid, p_lines jsonb)
returns table (line_order integer, grams numeric, weight_status text, line_cost numeric, unit_cost numeric,
               cost_unit text, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_r      recipes.recipes;
  v_costs  boolean := false;
  v_prices boolean := false;
  v_gram   uuid;
  v_lines  jsonb;
begin
  select r.* into v_r from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id where v.id = p_version_id;
  perform org.require(v_r.id is not null and recipes.can_see_version(p_version_id)
                      and (recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id)
                           or recipes.allowed('recipes.publish', v_r.group_id, v_r.brand_id, v_r.restaurant_id)),
                      'ver la ficha de esta receta');
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) > 200 then
    raise exception 'Las líneas van en una lista de hasta 200.' using errcode = '22023';
  end if;
  -- El local tiene que estar al alcance de la receta; si no, solo pesos.
  if p_restaurant_id is not null and exists (
       select 1 from org.restaurants r
        where r.id = p_restaurant_id and r.group_id = v_r.group_id and r.deleted_at is null
          and (v_r.scope_type = 'group' or (v_r.scope_type = 'brand' and v_r.brand_id = r.brand_id)
               or (v_r.scope_type = 'restaurant' and v_r.restaurant_id = r.id))) then
    v_costs := core.has_permission('recipes.view_costs', p_restaurant_id);
    v_prices := v_costs and core.has_permission('prices.view', p_restaurant_id);
  end if;
  select u.id into v_gram from catalog.units u where u.code = 'g' and u.is_base and u.deleted_at is null;

  -- Solo líneas completas, con las mismas reglas que set_components: materias primas activas del grupo, preparaciones
  -- activas que la persona ve o trabaja y que se pueden usar en esta receta (no otra marca u otro local, ni ella misma),
  -- y el perfil de merma aprobado de esa materia prima. Cada una conserva su posición en la grilla.
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_order', t.ord, 'ingredient_id', i.id, 'sub_recipe_id', s.id, 'quantity', x.quantity, 'unit', x.unit,
           'basis', case when s.id is not null then 'finished'
                         when x.basis in ('clean', 'cooked') then x.basis else 'purchase' end,
           'yield_profile_id', (select p.id from catalog.ingredient_yield_profiles p
                                 where p.id = x.yield_profile_id and p.ingredient_id = i.id and p.status = 'approved'
                                   and p.deleted_at is null))
           order by t.ord), '[]'::jsonb)
    into v_lines
    from jsonb_array_elements(p_lines) with ordinality as t (item, ord)
    cross join lateral jsonb_to_record(t.item) as x (ingredient_id uuid, sub_recipe_id uuid, quantity numeric, unit text,
                                                     basis text, yield_profile_id uuid)
    left join catalog.ingredients i on i.id = x.ingredient_id and i.group_id = v_r.group_id and i.deleted_at is null
                                    and i.is_active
    left join recipes.recipes s on s.id = x.sub_recipe_id and s.group_id = v_r.group_id and s.deleted_at is null
                                 and s.is_active and s.id <> v_r.id
                                 and (recipes.can_view_recipe(s.id) or recipes.can_work_recipe(s.id))
                                 and recipes.sub_in_scope(v_r.id, s.id)
   where jsonb_typeof(t.item) = 'object' and x.quantity > 0 and x.quantity < 1e9
     and (i.id is null) <> (s.id is null)
     and exists (select 1 from catalog.units u where u.code = x.unit and u.deleted_at is null and u.dimension <> 'package');

  return query
  with l as (
    select x.line_order as ord, x.ingredient_id, x.sub_recipe_id, x.quantity, u.id as unit_id, u.dimension, u.is_base,
           (select k.factor from catalog.unit_conversions k where k.from_unit_id = u.id and k.deleted_at is null) as factor
      from jsonb_to_recordset(v_lines) as x (line_order integer, ingredient_id uuid, sub_recipe_id uuid, quantity numeric,
                                            unit text)
      join catalog.units u on u.code = x.unit and u.deleted_at is null),
  w as (
    select l.ord,
           case when l.ingredient_id is not null then cq.quantity
                when l.dimension = 'mass' then l.quantity * case when l.is_base then 1 else l.factor end
           end as grams,
           case when l.ingredient_id is not null then cq.status
                when l.dimension = 'mass' then 'ok'
                else 'not_weight'
           end as weight_status,
           l.ingredient_id, l.sub_recipe_id, l.dimension
      from l
      left join lateral catalog.convert_quantity(l.ingredient_id, l.quantity, l.unit_id, v_gram) cq
        on l.ingredient_id is not null),
  c as (
    select k.line_order, k.line_cost, k.unit_cost, k.status
      from costing.recipe_line_costs_internal(
             p_version_id, p_restaurant_id, recipes.today(), jsonb_build_object('lines', v_lines)) k
     where v_costs)
  select w.ord, round(w.grams, 4), w.weight_status,
         case when v_costs then round(c.line_cost, 4) end,
         case when v_prices then round(c.unit_cost, 8) end,
         case when w.ingredient_id is not null
                then (select bu.code from catalog.ingredients i join catalog.units iu on iu.id = i.recipe_unit_id
                        join catalog.units bu on bu.dimension = iu.dimension and bu.is_base and bu.deleted_at is null
                       where i.id = w.ingredient_id limit 1)
              else (select bu.code from catalog.units bu where bu.dimension = w.dimension and bu.is_base and bu.deleted_at is null limit 1)
         end,
         case when v_costs then c.status end
    from w left join c on c.line_order = w.ord
   order by w.ord;
end
$$;
comment on function costing.preview_sheet_lines(uuid, uuid, jsonb) is
  'La grilla de la ficha mientras se escribe: por cada línea (en el orden recibido) su peso en gramos y, con recipes.view_costs en el local, su costo con el mismo motor que el costo oficial; su costo por unidad base (g, ml o unidad), solo con prices.view. Nunca supone una conversión ni un precio: lo que falta va vacío con su estado. Pide poder editar o publicar la receta.';
revoke execute on function costing.preview_sheet_lines(uuid, uuid, jsonb) from public, anon;
grant execute on function costing.preview_sheet_lines(uuid, uuid, jsonb) to authenticated;
