-- Medida práctica de cada ingrediente (Tanda 2 de Soy, PR B; ADR-0064): «480 g · 4 nidos».
--   * Cada línea guarda la medida y cuántas van, con el nombre y lo que contiene en ese momento. Una versión que ya no es
--     borrador queda congelada (decisión de Joaco, 2026-11-24); los borradores siguen la lista, salvo lo corregido a mano.
--   * La cuenta está en un solo lugar (recipes.measure_count_for): peso con peso, volumen con volumen, unidades con
--     unidades; peso con unidades solo con el peso por unidad de la materia prima. Nunca con la densidad.
--   * No toca costos ni pesos.

-- ---------------------------------------------------------------------------
-- 1. Columnas
-- ---------------------------------------------------------------------------
alter table recipes.recipe_components
  add column practical_measure_id uuid,
  add column measure_count        numeric(18,6),
  add column measure_name         text,
  add column measure_content      numeric(18,6),
  add column measure_unit_id      uuid references catalog.units (id) on delete restrict,
  add column measure_manual       boolean not null default false,
  add constraint recipe_components_measure_fkey foreign key (practical_measure_id, group_id)
    references catalog.practical_measures (id, group_id) on delete restrict,
  add constraint recipe_components_measure_count_check
    check (measure_count > 0 and measure_count < 1000000 and measure_count <> 'NaN'),
  -- Todo o nada.
  add constraint recipe_components_measure_whole check (
    num_nonnulls(practical_measure_id, measure_count, measure_name, measure_content, measure_unit_id) in (0, 5)
    and (practical_measure_id is not null or not measure_manual));
create index recipe_components_measure_idx on recipes.recipe_components (practical_measure_id, group_id)
  where practical_measure_id is not null;
create index recipe_components_measure_unit_idx on recipes.recipe_components (measure_unit_id) where measure_unit_id is not null;
comment on column recipes.recipe_components.practical_measure_id is
  'Medida práctica elegida para el cocinero (cucharón, nido). Vacía = sin medida práctica.';
comment on column recipes.recipe_components.measure_count is 'Cuántas medidas prácticas van: calculada o corregida a mano.';
comment on column recipes.recipe_components.measure_name is 'Nombre de la medida práctica. Queda congelado con la versión.';
comment on column recipes.recipe_components.measure_content is 'Lo que contiene la medida práctica, en su unidad base. Queda congelado con la versión.';
comment on column recipes.recipe_components.measure_unit_id is 'Unidad base de lo que contiene la medida práctica (ml, g o unidad).';
comment on column recipes.recipe_components.measure_manual is 'Si la cantidad de medidas se corrigió a mano (no se recalcula).';

-- ---------------------------------------------------------------------------
-- 2. La cuenta
-- ---------------------------------------------------------------------------
create function recipes.measure_count_for(p_ingredient_id uuid, p_quantity numeric, p_unit_id uuid, p_content numeric,
                                          p_content_unit_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when q.base is null or p_content is null or p_content <= 0 or q.per is null then null
           -- Con 2 decimales, y nunca cero: un poco es «0,01», no «0».
           else greatest(round(q.base * q.per / (p_content * q.content_base), 2), 0.01)
         end
    from (select p_quantity * recipes.unit_to_base(p_unit_id) as base, recipes.unit_to_base(p_content_unit_id) as content_base,
                 case
                   when u.dimension = m.dimension then 1
                   -- Peso y unidades, con el peso por unidad de la materia prima (una preparación no tiene).
                   when u.dimension = 'count' and m.dimension = 'mass' then w.factor
                   when u.dimension = 'mass' and m.dimension = 'count' then 1 / w.factor
                 end as per
            from catalog.units u
            join catalog.units m on m.id = p_content_unit_id
            left join catalog.ingredient_unit_conversions w
              on w.ingredient_id = p_ingredient_id and w.kind = 'unit_weight' and w.deleted_at is null
           where u.id = p_unit_id) q
$$;
comment on function recipes.measure_count_for(uuid, numeric, uuid, numeric, uuid) is
  'Interna: cuántas medidas prácticas son una cantidad. Solo entre unidades de la misma clase, o entre peso y unidades con el peso por unidad de la materia prima. Nulo si no se puede. Nunca usa la densidad.';
revoke execute on function recipes.measure_count_for(uuid, numeric, uuid, numeric, uuid) from public;

-- La medida de una línea que se guarda: la controla y calcula cuántas van.
create function recipes.line_measure(p_version_id uuid, p_group_id uuid, p_ingredient_id uuid, p_quantity numeric,
                                     p_unit_id uuid, p_line jsonb, p_n integer, p_item text,
                                     out measure catalog.practical_measures, out measure_count numeric, out manual boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_given text := nullif(btrim(p_line ->> 'measure_count'), '');
begin
  manual := false;
  if nullif(p_line ->> 'measure_id', '') is null then
    return;
  end if;
  select * into measure from catalog.practical_measures
   where id = (p_line ->> 'measure_id')::uuid and group_id = p_group_id and deleted_at is null;
  if measure.id is null then
    raise exception 'Línea % (%): elegí una medida práctica de la lista.', p_n, p_item using errcode = '22023';
  end if;
  -- Una inactiva solo sigue donde ya estaba (las líneas de antes quedan con su baja lógica).
  if not measure.is_active
     and not exists (select 1 from recipes.recipe_components c
                      where c.recipe_version_id = p_version_id and c.practical_measure_id = measure.id) then
    raise exception 'Línea % (%): la medida práctica «%» ya no se usa: elegí otra.', p_n, p_item, measure.name using errcode = '22023';
  end if;
  measure_count := recipes.measure_count_for(p_ingredient_id, p_quantity, p_unit_id, measure.content, measure.content_unit_id);
  -- Sin cuenta posible (otra clase, o se borró el peso por unidad): solo sigue lo que ya estaba corregido a mano.
  if measure_count is null
     and not (v_given is not null
              and exists (select 1 from recipes.recipe_components c
                           where c.recipe_version_id = p_version_id and c.practical_measure_id = measure.id and c.measure_manual
                             and c.ingredient_id is not distinct from p_ingredient_id and c.unit_id = p_unit_id)) then
    raise exception 'Línea % (%): la medida práctica «%» no es de la misma clase que la unidad.', p_n, p_item, measure.name
      using errcode = '22023';
  end if;
  if v_given is not null then
    measure_count := round(replace(v_given, ',', '.')::numeric, 6);
    if measure_count <= 0 or measure_count >= 1000000 or measure_count = 'NaN' then
      raise exception 'Línea % (%): escribí cuántas medidas van: un número mayor que cero.', p_n, p_item using errcode = '22023';
    end if;
    manual := true;
  elsif measure_count >= 1000000 then
    raise exception 'Línea % (%): son demasiadas medidas: elegí una más grande.', p_n, p_item using errcode = '22023';
  end if;
end
$$;
comment on function recipes.line_measure(uuid, uuid, uuid, numeric, uuid, jsonb, integer, text) is
  'Interna: la medida práctica de una línea que se guarda. Controla que sea del grupo, que esté activa (o que ya estuviera en la versión) y que sea de la misma clase; la cantidad la calcula, salvo que venga corregida a mano.';
revoke execute on function recipes.line_measure(uuid, uuid, uuid, numeric, uuid, jsonb, integer, text) from public;

-- Pone al día las medidas de un borrador: el nombre y lo que contiene la lista hoy, y cuántas van (salvo lo corregido a
-- mano). Si ya no se puede calcular (se borró el peso por unidad), queda el número, como corregido a mano.
create function recipes.refresh_measures(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Primero la versión, y después (en otra sentencia, que ya ve lo que otro guardó) sus líneas: no se cruza con quien la
  -- está guardando ni con quien la manda a revisión (revisión de base, G2).
  perform 1 from recipes.recipe_versions where id = p_version_id and status = 'draft' and deleted_at is null for update;
  if not found then
    return;
  end if;
  update recipes.recipe_components c
     set measure_name = x.name, measure_content = x.content, measure_unit_id = x.content_unit_id,
         measure_count = x.n, measure_manual = x.manual
    from (select c2.id, m.name, m.content, m.content_unit_id,
                 case when c2.measure_manual then c2.measure_count else coalesce(k.n, c2.measure_count) end as n,
                 c2.measure_manual or k.n is null as manual
            from recipes.recipe_components c2
            join catalog.practical_measures m on m.id = c2.practical_measure_id
           cross join lateral (select nullif(recipes.measure_count_for(c2.ingredient_id, c2.quantity, c2.unit_id, m.content,
                                                                       m.content_unit_id), 'NaN') as raw) r
            -- Más de un millón de medidas no entra: queda el número de antes, como corregido a mano (G1).
           cross join lateral (select case when r.raw < 1000000 then r.raw end as n) k
           where c2.recipe_version_id = p_version_id and c2.deleted_at is null) x
   where x.id = c.id and c.deleted_at is null
     and (c.measure_name, c.measure_content, c.measure_unit_id, c.measure_count, c.measure_manual)
         is distinct from (x.name, x.content, x.content_unit_id, x.n, x.manual);
end
$$;

-- Guardar una receta y guardar la lista de medidas no se cruzan: la lista toma este candado entero
-- (catalog.save_settings_list) y las recetas lo comparten, siempre antes de bloquear la versión.
create function recipes.share_measures(p_group_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  select pg_advisory_xact_lock_shared(hashtextextended('catalog.settings_list:measures:' || p_group_id, 0))
$$;
comment on function recipes.share_measures(uuid) is
  'Interna: comparte el candado de la lista de medidas prácticas del grupo hasta el fin de la transacción. Se toma antes de bloquear una versión.';
revoke execute on function recipes.share_measures(uuid) from public;
comment on function recipes.refresh_measures(uuid) is
  'Interna: pone al día las medidas prácticas de un borrador con la lista de hoy. No toca lo que ya no es borrador ni lo corregido a mano (salvo el nombre y lo que contiene).';
revoke execute on function recipes.refresh_measures(uuid) from public;

-- La lista cambia: lo siguen los borradores. La clase de una medida en uso no cambia (sería otra medida).
create function recipes.follow_measure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version uuid;
begin
  if tg_when = 'BEFORE' then
    if (select dimension from catalog.units where id = new.content_unit_id)
         is distinct from (select dimension from catalog.units where id = old.content_unit_id)
       and exists (select 1 from recipes.recipe_components where practical_measure_id = new.id and deleted_at is null) then
      raise exception '«%» ya se usa en recetas: no puede pasar de peso, volumen o unidades a otra clase. Creá otra medida.', old.name
        using errcode = '23514';
    end if;
    return new;
  end if;
  -- Un contenido tan chico que algún borrador pasaría el millón de medidas se rechaza acá: si no, ese borrador quedaría con
  -- su número «a mano» para siempre, aunque después se corrija la lista.
  if exists (select 1
               from recipes.recipe_components c
               join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status = 'draft' and v.deleted_at is null
              where c.practical_measure_id = new.id and c.deleted_at is null and not c.measure_manual
                and recipes.measure_count_for(c.ingredient_id, c.quantity, c.unit_id, new.content, new.content_unit_id) >= 1000000) then
    raise exception 'Con ese contenido, alguna receta llevaría demasiadas medidas: revisalo.' using errcode = '23514';
  end if;
  for v_version in
    select distinct c.recipe_version_id
      from recipes.recipe_components c
      join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status = 'draft' and v.deleted_at is null
     where c.practical_measure_id = new.id and c.deleted_at is null
     order by 1
  loop
    perform recipes.refresh_measures(v_version);
  end loop;
  return null;
end
$$;
comment on function recipes.follow_measure() is
  'Trigger de las medidas prácticas: al cambiar el nombre o lo que contiene, lo siguen los borradores; la clase de una medida en uso no cambia.';
revoke execute on function recipes.follow_measure() from public;
create trigger keep_measure_class before update of content_unit_id on catalog.practical_measures
  for each row execute function recipes.follow_measure();
create trigger follow_measure after update of name, content, content_unit_id on catalog.practical_measures
  for each row when ((old.name, old.content, old.content_unit_id) is distinct from (new.name, new.content, new.content_unit_id))
  execute function recipes.follow_measure();

comment on function recipes.refresh_list_names() is
  'Trigger de las versiones: al volver a borrador, los pasos toman el nombre actual del sector y del equipo de la lista, y las líneas, la medida práctica de hoy.';
-- Al volver a borrador, también las medidas (PR A: los nombres).
create or replace function recipes.refresh_list_names()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
begin
  update recipes.recipe_steps s
     set sector = coalesce(k.name, s.sector), equipment = coalesce(e.name, s.equipment)
    from recipes.recipe_steps x
    left join catalog.kitchen_sectors k on k.id = x.sector_id
    left join catalog.kitchen_equipment e on e.id = x.equipment_id
   where x.id = s.id and s.recipe_version_id = new.id and s.deleted_at is null
     and ((k.name is not null and k.name is distinct from s.sector)
          or (e.name is not null and e.name is distinct from s.equipment));
  perform recipes.refresh_measures(new.id);
  return null;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Guardar, copiar y leer
-- ---------------------------------------------------------------------------
create or replace function recipes.set_components(p_version_id uuid, p_lines jsonb, p_reason text, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_v          recipes.recipe_versions;
  v_r          recipes.recipes;
  v_line       jsonb;
  v_n          integer := 0;
  v_ing        catalog.ingredients;
  v_sub        recipes.recipes;
  v_sub_unit   uuid;
  v_unit       catalog.units;
  v_status     text;
  v_qty        numeric;
  v_basis      recipes.quantity_basis;
  v_profile    uuid;
  v_lm         record;
  v_constraint text;
  v_message    text;
begin
  perform recipes.share_measures(v.group_id) from recipes.recipe_versions v where v.id = p_version_id;
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.set_components', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  v_v := recipes.open_draft(p_version_id, p_expected_updated_at);
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then
    raise exception 'Las líneas tienen que ser una lista (hasta 200).' using errcode = '22023';
  end if;
  -- Con preparaciones, los cambios del árbol del grupo van de a uno.
  if exists (select 1 from jsonb_array_elements(p_lines) e
              where jsonb_typeof(e) = 'object' and nullif(e ->> 'sub_recipe_id', '') is not null) then
    perform recipes.lock_sub_graph(v_r.group_id);
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_components set deleted_at = now() where recipe_version_id = p_version_id and deleted_at is null;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_n := v_n + 1;
    perform org.check_keys(v_line, array['ingredient_id', 'sub_recipe_id', 'quantity', 'unit', 'basis', 'yield_profile_id',
                                         'no_scale', 'notes', 'measure_id', 'measure_count']);
    v_ing := null;
    v_sub := null;
    v_qty := nullif(v_line ->> 'quantity', '')::numeric;
    select * into v_unit from catalog.units where code = v_line ->> 'unit';
    if nullif(v_line ->> 'sub_recipe_id', '') is not null then
      -- Una preparación: que la persona la vea (antes de nombrarla en un mensaje: revisión de seguridad,
      -- M1), activa, con vigente, al alcance del plato, sin círculos y hasta 10 niveles.
      select * into v_sub from recipes.recipes
       where id = (v_line ->> 'sub_recipe_id')::uuid and group_id = v_r.group_id and deleted_at is null and is_active;
      if v_sub.id is not null and not (recipes.can_view_recipe(v_sub.id) or recipes.can_work_recipe(v_sub.id)) then
        v_sub := null;
      end if;
      if v_sub.id is not null then
        perform 1 from recipes.recipes where id = v_sub.id and is_active for share;
        if not found then
          v_sub := null;
        end if;
      end if;
      select yield_unit_id into v_sub_unit from recipes.recipe_versions
       where recipe_id = v_sub.id and status = 'published';
      if v_sub.id is null or v_sub_unit is null then
        raise exception 'Línea %: elegí una preparación con una versión vigente.', v_n using errcode = '22023';
      end if;
      if coalesce(nullif(v_line ->> 'basis', ''), 'finished') <> 'finished' or nullif(v_line ->> 'yield_profile_id', '') is not null then
        raise exception 'Línea % (%): una preparación va en cantidad terminada, sin rendimiento de materia prima.', v_n, v_sub.name
          using errcode = '22023';
      end if;
      if v_sub.id = v_r.id then
        raise exception 'Línea % (%): una receta no se puede usar a sí misma.', v_n, v_sub.name using errcode = '23514';
      end if;
      if not recipes.sub_in_scope(v_r.id, v_sub.id) then
        raise exception 'Línea % (%): esa preparación no se puede usar acá: es de otra marca o de otro local.', v_n, v_sub.name
          using errcode = '23514';
      end if;
      if recipes.reaches(v_sub.id, v_r.id, false) then
        raise exception 'Línea % (%): esa preparación ya usa esta receta: se formaría un círculo.', v_n, v_sub.name
          using errcode = '23514';
      end if;
      if recipes.sub_height(v_r.id) + 1 + coalesce(recipes.sub_depth(v_sub.id), 0) > 9 then
        raise exception 'Línea % (%): se pasaría de 10 niveles de preparaciones.', v_n, v_sub.name using errcode = '23514';
      end if;
      if v_qty is null or v_qty <= 0 then
        raise exception 'Línea % (%): la cantidad tiene que ser mayor que cero.', v_n, v_sub.name using errcode = '22023';
      end if;
      if v_unit.id is null or recipes.unit_to_base(v_unit.id) is null or recipes.unit_to_base(v_sub_unit) is null
         or v_unit.dimension is distinct from (select dimension from catalog.units where id = v_sub_unit) then
        raise exception 'Línea % (%): usá una unidad como la de su rendimiento (%).', v_n, v_sub.name,
          (select name from catalog.units where id = v_sub_unit) using errcode = '22023';
      end if;
      select * into v_lm
        from recipes.line_measure(p_version_id, v_r.group_id, null, v_qty, v_unit.id, v_line, v_n, v_sub.name) m;
      insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id,
                                             quantity_basis, no_scale, notes, practical_measure_id, measure_count,
                                             measure_name, measure_content, measure_unit_id, measure_manual)
      values (v_r.group_id, p_version_id, v_n, v_sub.id, v_qty, v_unit.id, 'finished',
              coalesce((v_line ->> 'no_scale')::boolean, false), nullif(btrim(v_line ->> 'notes'), ''),
              (v_lm.measure).id, v_lm.measure_count, (v_lm.measure).name, (v_lm.measure).content, (v_lm.measure).content_unit_id,
            coalesce(v_lm.manual, false));
      continue;
    end if;
    select * into v_ing from catalog.ingredients
     where id = nullif(v_line ->> 'ingredient_id', '')::uuid and group_id = v_r.group_id and deleted_at is null and is_active;
    if v_ing.id is null then
      raise exception 'Línea %: elegí una materia prima vigente del grupo.', v_n using errcode = '22023';
    end if;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Línea % (%): la cantidad tiene que ser mayor que cero.', v_n, v_ing.name using errcode = '22023';
    end if;
    if v_unit.id is null then
      raise exception 'Línea % (%): elegí la unidad.', v_n, v_ing.name using errcode = '22023';
    end if;
    -- La cantidad se tiene que poder pasar a la unidad de la materia prima: si no, el costo no se podría calcular.
    select b.status into v_status from catalog.to_base_quantity(v_ing.id, v_qty, v_unit.id) b;
    if v_status is distinct from 'ok' then
      raise exception 'Línea % (%): no se puede pasar de % a la unidad de la materia prima. Cargá la conversión en su ficha o usá otra unidad.',
        v_n, v_ing.name, v_unit.name using errcode = '22023';
    end if;
    v_basis := coalesce(nullif(v_line ->> 'basis', ''), 'purchase')::recipes.quantity_basis;
    if v_basis::text = 'finished' then
      raise exception 'Línea % (%): la cantidad terminada es solo para preparaciones.', v_n, v_ing.name using errcode = '22023';
    end if;
    v_profile := nullif(v_line ->> 'yield_profile_id', '')::uuid;
    if v_profile is not null and not exists (select 1 from catalog.ingredient_yield_profiles
                                               where id = v_profile and ingredient_id = v_ing.id and status = 'approved'
                                                 and deleted_at is null) then
      raise exception 'Línea % (%): el rendimiento elegido no es un estándar vigente de esa materia prima.', v_n, v_ing.name
        using errcode = '22023';
    end if;
    select * into v_lm
      from recipes.line_measure(p_version_id, v_r.group_id, v_ing.id, v_qty, v_unit.id, v_line, v_n, v_ing.name) m;
    insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id,
                                           quantity_basis, yield_profile_id, no_scale, notes, practical_measure_id,
                                           measure_count, measure_name, measure_content, measure_unit_id, measure_manual)
    values (v_r.group_id, p_version_id, v_n, v_ing.id, v_qty, v_unit.id, v_basis, v_profile,
            coalesce((v_line ->> 'no_scale')::boolean, false), nullif(btrim(v_line ->> 'notes'), ''),
            (v_lm.measure).id, v_lm.measure_count, (v_lm.measure).name, (v_lm.measure).content, (v_lm.measure).content_unit_id,
            coalesce(v_lm.manual, false));
  end loop;
  update recipes.recipe_versions set updated_at = now() where id = p_version_id;
  return jsonb_build_object('result', 'applied', 'message', format('Componentes guardados (%s).', v_n));
exception when check_violation or invalid_text_representation or numeric_value_out_of_range or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if sqlstate in ('22P02', '22003') then
    raise exception 'Línea %: algún dato no es válido.', v_n using errcode = '22023';
  end if;
  if v_constraint is null then
    raise;
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;

create or replace function recipes.copy_version_content(p_from uuid, p_to uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_to recipes.recipe_versions;
begin
  select * into v_to from recipes.recipe_versions where id = p_to;
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, sub_recipe_id, quantity,
                                         unit_id, quantity_basis, yield_profile_id, no_scale, notes, practical_measure_id,
                                         measure_count, measure_name, measure_content, measure_unit_id, measure_manual)
  -- La medida práctica, la de hoy (la publicada conserva la suya): la misma regla que recipes.refresh_measures.
  select v_to.group_id, p_to, c.line_order, c.ingredient_id, c.sub_recipe_id, c.quantity, c.unit_id, c.quantity_basis,
         c.yield_profile_id, c.no_scale, c.notes, c.practical_measure_id,
         case when c.measure_manual then c.measure_count else coalesce(k.n, c.measure_count) end,
         coalesce(m.name, c.measure_name), coalesce(m.content, c.measure_content), coalesce(m.content_unit_id, c.measure_unit_id),
         c.practical_measure_id is not null and (c.measure_manual or k.n is null)
    from recipes.recipe_components c
    left join catalog.practical_measures m on m.id = c.practical_measure_id
   cross join lateral (select nullif(recipes.measure_count_for(c.ingredient_id, c.quantity, c.unit_id, m.content,
                                                               m.content_unit_id), 'NaN') as raw) r
   cross join lateral (select case when r.raw < 1000000 then r.raw end as n) k
   where c.recipe_version_id = p_from and c.deleted_at is null;
  insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                    passive_minutes, workers, sector, sector_id, equipment, equipment_id, equipment_capacity,
                                    equipment_capacity_unit_id, control_point)
  select v_to.group_id, p_to, step_number, kind, instructions, active_minutes, passive_minutes, workers, sector, sector_id,
         equipment, equipment_id, equipment_capacity, equipment_capacity_unit_id, control_point
    from recipes.recipe_steps where recipe_version_id = p_from and deleted_at is null;
  -- Las dependencias se copian por número de paso.
  insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
  select v_to.group_id, ns.id, nd.id
    from recipes.recipe_step_dependencies d
    join recipes.recipe_steps os on os.id = d.step_id
    join recipes.recipe_steps od on od.id = d.depends_on_step_id
    join recipes.recipe_steps ns on ns.recipe_version_id = p_to and ns.step_number = os.step_number and ns.deleted_at is null
    join recipes.recipe_steps nd on nd.recipe_version_id = p_to and nd.step_number = od.step_number and nd.deleted_at is null
   where os.recipe_version_id = p_from and d.deleted_at is null;
  insert into recipes.recipe_media (group_id, recipe_id, recipe_version_id, kind, storage_path, description)
  select v_to.group_id, v_to.recipe_id, p_to, kind, storage_path, description
    from recipes.recipe_media where recipe_version_id = p_from and deleted_at is null;
end
$$;

create or replace function recipes.kitchen_card(p_recipe_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_r     recipes.recipes;
  v_v     recipes.recipe_versions;
  v_total integer;
  v_act   integer;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null;
  if v_r.id is null or not recipes.can_view_recipe(v_r.id) then
    return null;
  end if;
  select * into v_v from recipes.recipe_versions where recipe_id = p_recipe_id and status = 'published';
  if v_v.id is null then
    return null;
  end if;
  select c.total_minutes, c.active_minutes into v_total, v_act from recipes.critical_path(v_v.id) c;
  return jsonb_build_object(
    'recipe_id', v_r.id, 'code', v_r.code, 'name', v_r.name, 'short_name', v_r.short_name,
    'recipe_type', v_r.recipe_type, 'version_number', v_v.version_number, 'published_at', v_v.published_at,
    'yield_quantity', v_v.yield_quantity, 'yield_unit', (select u.name from catalog.units u where u.id = v_v.yield_unit_id),
    'portions', v_v.portions, 'portion_grams', v_v.portion_grams, 'description', v_v.description,
    'storage_notes', v_v.storage_notes, 'presentation_notes', v_v.presentation_notes,
    'total_minutes', v_total, 'active_minutes', v_act,
    -- La maestra, solo para quien la ve (revisión de seguridad, m1).
    'variant_of', (select jsonb_build_object('recipe_id', m.id, 'name', m.name) from recipes.recipes m
                    where m.id = v_r.variant_of_recipe_id
                      and (recipes.can_view_recipe(m.id) or recipes.can_work_recipe(m.id))),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object('line', c.line_order, 'ingredient', coalesce(i.name, s.name),
                                          'sub_recipe_id', c.sub_recipe_id, 'quantity', c.quantity, 'unit', u.name,
                                          'basis', c.quantity_basis, 'notes', c.notes,
                                          'measure_count', c.measure_count, 'measure_name', c.measure_name,
                                          'measure_content', c.measure_content, 'measure_unit', mu.code) order by c.line_order)
        from recipes.recipe_components c
        left join catalog.ingredients i on i.id = c.ingredient_id
        left join recipes.recipes s on s.id = c.sub_recipe_id
        join catalog.units u on u.id = c.unit_id
        left join catalog.units mu on mu.id = c.measure_unit_id
       where c.recipe_version_id = v_v.id and c.deleted_at is null), '[]'),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
               'number', s.step_number, 'kind', s.kind, 'instructions', s.instructions,
               'active_minutes', s.active_minutes, 'passive_minutes', s.passive_minutes, 'equipment', s.equipment,
               'control_point', s.control_point,
               'depends_on', coalesce((select jsonb_agg(o.step_number order by o.step_number)
                                         from recipes.recipe_step_dependencies d
                                         join recipes.recipe_steps o on o.id = d.depends_on_step_id
                                        where d.step_id = s.id and d.deleted_at is null), '[]'))
             order by s.step_number)
        from recipes.recipe_steps s
       where s.recipe_version_id = v_v.id and s.deleted_at is null), '[]'),
    'allergens', coalesce((select jsonb_agg(jsonb_build_object('name', a.name, 'status', a.status))
                             from recipes.version_allergens(v_v.id) a), '[]'));
end
$$;

create or replace function catalog.settings_list(p_group_id uuid, p_list catalog.settings_list)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_rows jsonb;
begin
  perform org.require(core.current_session_ok() and catalog.can_see_lists(p_group_id), 'ver la configuración del catálogo');
  if p_list = 'ingredient_categories' then
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'code', c.code, 'parent_id', c.parent_id,
             'active', c.deleted_at is null and c.is_active, 'editable', true,
             'uses', (select count(*) from catalog.ingredients i where i.category_id = c.id and i.deleted_at is null),
             'why', catalog.cannot_archive_item(p_list, c.id)) order by lower(c.name))
      into v_rows
      from catalog.ingredient_categories c
      left join catalog.ingredient_categories m on m.id = c.parent_id
     where c.group_id = p_group_id and ((c.deleted_at is null and (c.parent_id is not null or c.is_active))
                                        or (c.parent_id is not null and m.deleted_at is null and m.is_active));
  elsif p_list = 'recipe_categories' then
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'code', c.code, 'parent_id', c.parent_id,
             'active', c.deleted_at is null and c.is_active, 'editable', true,
             'uses', (select count(*) from recipes.recipes r where r.category_id = c.id and r.deleted_at is null),
             'why', catalog.cannot_archive_item(p_list, c.id)) order by lower(c.name))
      into v_rows
      from recipes.recipe_categories c
      left join recipes.recipe_categories m on m.id = c.parent_id
     where c.group_id = p_group_id and ((c.deleted_at is null and (c.parent_id is not null or c.is_active))
                                        or (c.parent_id is not null and m.deleted_at is null and m.is_active));
  elsif p_list = 'sectors' then
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active, 'editable', true,
             -- Por la receta o por alguno de sus pasos.
             'uses', (select count(*) from recipes.recipes r
                       where r.group_id = p_group_id and r.deleted_at is null
                         and (r.sector_id = s.id
                              or exists (select 1 from recipes.recipe_versions v
                                           join recipes.recipe_steps t on t.recipe_version_id = v.id and t.deleted_at is null
                                          where v.recipe_id = r.id and v.deleted_at is null and v.status <> 'archived'
                                            and (t.sector_id = s.id
                                                 or (t.sector_id is null and t.sector is not null
                                                     and catalog.list_key(t.sector) = catalog.list_key(s.name))))))) order by lower(s.name))
      into v_rows from catalog.kitchen_sectors s where s.group_id = p_group_id and s.deleted_at is null;
  elsif p_list = 'stations' then
    select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active, 'editable', true,
             'uses', (select count(*) from recipes.recipes r where r.station_id = s.id and r.deleted_at is null)) order by lower(s.name))
      into v_rows from catalog.kitchen_stations s where s.group_id = p_group_id and s.deleted_at is null;
  elsif p_list = 'equipment' then
    -- Una versión anterior a las listas guarda el equipo como texto: cuenta por el nombre.
    with used as (
      select coalesce(s.equipment_id::text, catalog.list_key(s.equipment)) as key, count(distinct v.recipe_id) as recipes,
             array_agg(distinct v.recipe_id) as ids
        from recipes.recipe_steps s
        join recipes.recipe_versions v on v.id = s.recipe_version_id and v.deleted_at is null and v.status <> 'archived'
        join recipes.recipes r on r.id = v.recipe_id and r.deleted_at is null
       where s.group_id = p_group_id and s.deleted_at is null and s.equipment is not null
       group by 1
    )
    select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name, 'capacity', e.capacity, 'capacity_unit', u.code,
             'capacity_label', e.capacity_label, 'active', e.is_active, 'editable', true,
             'uses', (select count(distinct x) from used, unnest(used.ids) x
                       where used.key in (e.id::text, catalog.list_key(e.name)))) order by lower(e.name))
      into v_rows
      from catalog.kitchen_equipment e left join catalog.units u on u.id = e.capacity_unit_id
     where e.group_id = p_group_id and e.deleted_at is null;
  elsif p_list = 'measures' then
    select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'content', m.content, 'content_unit', u.code,
             'usage_note', m.usage_note, 'active', m.is_active, 'editable', true,
             'uses', (select count(distinct v.recipe_id) from recipes.recipe_components c
                        join recipes.recipe_versions v on v.id = c.recipe_version_id and v.deleted_at is null and v.status <> 'archived'
                        join recipes.recipes r on r.id = v.recipe_id and r.deleted_at is null
                       where c.practical_measure_id = m.id and c.group_id = p_group_id and c.deleted_at is null)) order by lower(m.name))
      into v_rows
      from catalog.practical_measures m join catalog.units u on u.id = m.content_unit_id
     where m.group_id = p_group_id and m.deleted_at is null;
  elsif p_list = 'units' then
    select jsonb_agg(jsonb_build_object('id', u.id, 'code', u.code, 'name', u.long_name, 'abbreviation', u.abbreviation,
             'dimension', u.dimension, 'is_base', u.is_base, 'factor', c.factor, 'base_unit', b.abbreviation,
             'active', u.deleted_at is null, 'editable', false,
             'why', catalog.cannot_archive_item(p_list, u.id)) order by u.dimension, u.is_base desc, lower(u.long_name))
      into v_rows
      from catalog.units u
      left join lateral (select c.factor, c.to_unit_id from catalog.unit_conversions c
                          where c.from_unit_id = u.id order by c.deleted_at is null desc, c.deleted_at desc limit 1) c on true
      left join catalog.units b on b.id = c.to_unit_id
     where u.deleted_at is null or u.created_by is not null;
  else
    select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'active', p.deleted_at is null, 'editable', true,
             'uses', (select count(distinct y.ingredient_id) from catalog.ingredient_yield_profiles y
                       where y.process_id = p.id and y.status = 'approved'),
             'why', catalog.cannot_archive_item(p_list, p.id)) order by lower(p.name))
      into v_rows from catalog.yield_processes p where p.group_id = p_group_id;
  end if;
  return jsonb_build_object('list', p_list, 'can_edit', catalog.can_manage_list(p_list, p_group_id),
                            'stamp', catalog.settings_list_stamp(p_list, p_group_id), 'rows', coalesce(v_rows, '[]'::jsonb));
end
$$;

-- Lo que cambió de las medidas contra la versión anterior: solo para quien trabaja la receta (como version_diff).
create function recipes.version_measure_diff(p_version_id uuid)
returns table (ingredient text, old_measures text, new_measures text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_prev uuid;
begin
  select v.previous_version_id into v_prev from recipes.recipe_versions v
   where v.id = p_version_id and v.deleted_at is null and recipes.can_work_recipe(v.recipe_id);
  if not found or v_prev is null then
    return;
  end if;
  return query
    with lines as (
      select c.recipe_version_id as version_id, coalesce(c.ingredient_id, c.sub_recipe_id) as item, min(c.line_order) as line,
             -- «4 × Nido de 120 g + 1 × Taza de 240 ml»: cada medida con lo que contiene, en un orden fijo.
             string_agg(case when c.measure_name is null then 'sin medida'
                             else replace(trim_scale(c.measure_count)::text, '.', ',') || ' × ' || c.measure_name || ' de '
                                  || replace(trim_scale(c.measure_content)::text, '.', ',') || ' ' || u.abbreviation end,
                        ' + ' order by c.measure_name nulls last, c.measure_count, c.measure_content) as words
        from recipes.recipe_components c left join catalog.units u on u.id = c.measure_unit_id
       where c.recipe_version_id in (p_version_id, v_prev) and c.deleted_at is null
       group by 1, 2)
    select coalesce(i.name, r.name), o.words, n.words
      from lines n join lines o on o.item = n.item and o.version_id = v_prev
      left join catalog.ingredients i on i.id = n.item
      left join recipes.recipes r on r.id = n.item
     where n.version_id = p_version_id and n.words is distinct from o.words
     order by n.line;
end
$$;
comment on function recipes.version_measure_diff(uuid) is
  'Las medidas prácticas que cambiaron contra la versión anterior. Solo para quien trabaja la receta.';
revoke execute on function recipes.version_measure_diff(uuid) from public, anon;
grant execute on function recipes.version_measure_diff(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Lo demás que guarda, copia o manda a revisión
-- ---------------------------------------------------------------------------
-- Comparten el candado de la lista de medidas antes de bloquear nada.
create or replace function recipes.save_sheet(p_recipe_id uuid, p_version_id uuid, p_expected_updated_at timestamp with time zone, p_recipe jsonb, p_draft jsonb, p_lines jsonb, p_steps jsonb, p_reason text, p_submit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
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
  perform recipes.share_measures(x.group_id) from recipes.recipes x where x.id = p_recipe_id;
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

create or replace function recipes.new_version(p_recipe_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_r      recipes.recipes;
  v_base   recipes.recipe_versions;
  v_id     uuid;
  v_open   uuid;
begin
  perform recipes.share_measures(x.group_id) from recipes.recipes x where x.id = p_recipe_id;
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.new_version', 'No tenés permiso para crear versiones de esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if not v_r.is_active then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  select id into v_open from recipes.recipe_versions where recipe_id = p_recipe_id and status in ('draft', 'in_review');
  if v_open is not null then
    raise exception 'Ya hay una versión en borrador o en revisión: seguí con esa.' using errcode = '23505';
  end if;
  -- La base es la vigente; si no hay, la última.
  select * into v_base from recipes.recipe_versions
   where recipe_id = p_recipe_id order by (status = 'published') desc, version_number desc limit 1;
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipe_versions (group_id, recipe_id, version_number, previous_version_id, yield_quantity,
                                       yield_unit_id, portions, portion_grams, description, storage_notes,
                                       presentation_notes)
  select v_r.group_id, p_recipe_id, (select max(version_number) + 1 from recipes.recipe_versions where recipe_id = p_recipe_id),
         v_base.id, v_base.yield_quantity, v_base.yield_unit_id, v_base.portions, v_base.portion_grams, v_base.description,
         v_base.storage_notes, v_base.presentation_notes
  returning id into v_id;
  perform recipes.copy_version_content(v_base.id, v_id);
  return jsonb_build_object('result', 'applied', 'id', v_id,
                            'message', 'Versión nueva en borrador. La vigente sigue igual hasta que se publique esta.');
end
$$;

create or replace function recipes.create_variant(p_master_id uuid, p_restaurant_id uuid, p_name text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_m          recipes.recipes;
  v_mv         recipes.recipe_versions;
  v_rest       org.restaurants;
  v_code       text;
  v_recipe     uuid;
  v_version    uuid;
  v_constraint text;
  v_message    text;
begin
  perform recipes.share_measures(x.group_id) from recipes.recipes x where x.id = p_master_id;
  select * into v_m from recipes.recipes where id = p_master_id and deleted_at is null;
  select * into v_rest from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_m.id is null or v_rest.id is null or not core.has_permission('recipes.approve', p_restaurant_id)
     or not (recipes.can_view_recipe(v_m.id) or recipes.can_work_recipe(v_m.id)) then
    return core.deny('recipes.create_variant', 'No tenés permiso para crear variantes en ese local.', null,
                     jsonb_build_object('recipe_id', p_master_id, 'restaurant_id', p_restaurant_id),
                     coalesce(v_m.group_id, v_rest.group_id), v_rest.brand_id, p_restaurant_id);
  end if;
  -- Recién con permiso se bloquea la maestra (para que no se archive mientras tanto).
  select * into v_m from recipes.recipes where id = v_m.id for share;
  if not v_m.is_active or v_m.scope_type = 'restaurant' or v_m.variant_of_recipe_id is not null then
    raise exception 'Solo se hacen variantes de una receta maestra del grupo o de una marca, activa.' using errcode = '23514';
  end if;
  if v_rest.group_id <> v_m.group_id or (v_m.scope_type = 'brand' and v_rest.brand_id <> v_m.brand_id) then
    raise exception 'Ese local no usa esa receta: está fuera de su alcance.' using errcode = '23514';
  end if;
  select * into v_mv from recipes.recipe_versions where recipe_id = v_m.id and status = 'published';
  if v_mv.id is null then
    raise exception 'La receta maestra no tiene una versión vigente.' using errcode = '23514';
  end if;
  -- El código de la maestra y -V01, -V02… (decisión de Joaco, ADR-0041).
  if length(v_m.code) + 4 > 30 then
    raise exception 'El código de la maestra es demasiado largo para sumarle -V01.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  v_code := catalog.next_code(v_m.group_id, v_m.code || '-V', 2);
  insert into recipes.recipes (group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id,
                               sector, station, variant_of_recipe_id)
  values (v_m.group_id, v_rest.brand_id, v_rest.id, 'restaurant', v_code, btrim(p_name), v_m.recipe_type,
          v_m.category_id, v_m.sector, v_m.station, v_m.id)
  returning id into v_recipe;
  insert into recipes.recipe_versions (group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions,
                                       portion_grams, description, storage_notes, presentation_notes, change_summary)
  values (v_m.group_id, v_recipe, 1, v_mv.yield_quantity, v_mv.yield_unit_id, v_mv.portions, v_mv.portion_grams,
          v_mv.description, v_mv.storage_notes, v_mv.presentation_notes,
          format('Variante de «%s» (v%s) para %s.', v_m.name, v_mv.version_number, v_rest.name))
  returning id into v_version;
  perform recipes.copy_version_content(v_mv.id, v_version);
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (v_m.group_id, v_recipe, v_rest.id, recipes.today());
  return jsonb_build_object('result', 'applied', 'id', v_recipe, 'version_id', v_version, 'code', v_code,
                            'message', format('Variante %s creada en borrador. Cuando se publique, el local deja de usar la maestra.', v_code));
exception when unique_violation or check_violation or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'recipes_variant_key' then
    raise exception 'Ese local ya tiene una variante de esta receta.' using errcode = '23505';
  elsif v_constraint is null and sqlstate = '23502' then
    raise exception 'Falta el nombre.' using errcode = '22023';
  elsif v_constraint is null then
    raise;
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;

-- Al pedir la revisión, las cuentas quedan al día (por ejemplo, si cambió el peso por unidad) y desde ahí, congeladas.
create or replace function recipes.request_review(p_version_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_v        recipes.recipe_versions;
  v_r        recipes.recipes;
  v_current  recipes.recipe_versions;
  v_lines    integer;
  v_steps    integer;
  v_changes  jsonb;
  v_request  uuid;
  v_bad      record;
begin
  perform recipes.share_measures(x.group_id) from recipes.recipe_versions x where x.id = p_version_id;
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.allowed('recipes.review', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.request_review', 'No tenés permiso para pedir la revisión de esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  perform recipes.reopen_returned(p_version_id);
  select * into v_v from recipes.recipe_versions where id = p_version_id;
  perform 1 from recipes.recipes where id = v_r.id and is_active for share;
  if not found then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  if v_v.status <> 'draft' then
    raise exception 'Solo se pide la revisión de un borrador.' using errcode = '23514';
  end if;
  -- Las líneas copiadas de una versión anterior se vuelven a validar con las reglas de set_components.
  select * into v_bad from recipes.first_invalid_line(p_version_id);
  if v_bad.line_order is not null then
    raise exception 'Línea % (%): %. Corregila antes de pedir la revisión.', v_bad.line_order, v_bad.item, v_bad.why
      using errcode = '23514';
  end if;
  select count(*) into v_lines from recipes.recipe_components where recipe_version_id = p_version_id and deleted_at is null;
  select count(*) into v_steps from recipes.recipe_steps where recipe_version_id = p_version_id and deleted_at is null;
  if v_lines = 0 or v_steps = 0 or v_v.yield_quantity is null then
    raise exception 'Para pedir la revisión, la receta necesita al menos un componente, un paso y su rendimiento.'
      using errcode = '23514';
  end if;
  select * into v_current from recipes.recipe_versions where recipe_id = v_r.id and status = 'published';
  -- La solicitud la ve cualquiera con approvals.view: lleva solo cuántas líneas cambian, sin la fórmula.
  -- El detalle lo lee quien trabaja la receta, con version_diff (revisión de seguridad, M3).
  select jsonb_build_object('added', count(*) filter (where d.change = 'added'),
                            'removed', count(*) filter (where d.change = 'removed'),
                            'changed', count(*) filter (where d.change = 'changed'))
    into v_changes from recipes.version_diff(p_version_id) d;
  perform core.set_change_context(p_reason, 'manual');
  perform recipes.refresh_measures(p_version_id);
  update recipes.recipe_versions set status = 'in_review', review_requested_by = core.current_actor_id()
   where id = p_version_id;
  v_request := workflow.request_approval(
    'recipes.publish_version', v_r.group_id, v_r.brand_id, v_r.restaurant_id, null, p_version_id,
    jsonb_build_object('recipe', v_r.name, 'code', v_r.code, 'version_number', v_v.version_number,
                       'lines', v_lines, 'steps', v_steps, 'line_changes', v_changes, 'recipe_id', v_r.id,
                       'version_id', p_version_id),
    case when v_current.id is null then jsonb_build_object('version_number', null)
         else jsonb_build_object('version_number', v_current.version_number,
                                 'lines', (select count(*) from recipes.recipe_components
                                            where recipe_version_id = v_current.id and deleted_at is null)) end,
    p_reason);
  update recipes.recipe_versions set approval_request_id = v_request where id = p_version_id;
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                            'message', 'Queda en revisión: la tiene que aprobar otra persona con permiso de publicar.');
end
$$;

-- Retirar una revisión y guardar los datos vuelven a borrador: también comparten el candado.
create or replace function recipes.withdraw_review(p_version_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_v      recipes.recipe_versions;
  v_r      recipes.recipes;
  v_result jsonb;
begin
  perform recipes.share_measures(x.group_id) from recipes.recipe_versions x where x.id = p_version_id;
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.can_work_recipe(v_r.id) then
    return core.deny('recipes.withdraw_review', 'No tenés permiso sobre esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if v_v.status <> 'in_review' then
    raise exception 'Esa versión no está en revisión.' using errcode = '23514';
  end if;
  -- Solo quien pidió la revisión la retira (regla de workflow.cancel_request).
  v_result := workflow.cancel_request(v_v.approval_request_id, p_reason);
  if v_result ->> 'result' not in ('cancelled', 'already_resolved') then
    return v_result;
  end if;
  perform recipes.reopen_returned(p_version_id);
  return jsonb_build_object('result', 'applied', 'message', 'Volvió a borrador: corregila y pedí la revisión de nuevo.');
end
$$;

create or replace function recipes.save_draft(p_version_id uuid, p_data jsonb, p_reason text, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_v          recipes.recipe_versions;
  v_r          recipes.recipes;
  v_unit       uuid;
  v_constraint text;
  v_message    text;
begin
  perform recipes.share_measures(x.group_id) from recipes.recipe_versions x where x.id = p_version_id;
  select * into v_v from recipes.recipe_versions where id = p_version_id and deleted_at is null for update;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and deleted_at is null;
  if v_v.id is null or v_r.id is null or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.save_draft', 'No tenés permiso para editar esa receta.', null,
                     jsonb_build_object('version_id', p_version_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  v_v := recipes.open_draft(p_version_id, p_expected_updated_at);
  perform org.check_keys(p_data, array['yield_quantity', 'yield_unit', 'portions', 'portion_grams', 'description',
                                       'storage_notes', 'presentation_notes', 'change_summary']);
  if p_data ? 'yield_unit' and nullif(p_data ->> 'yield_unit', '') is not null then
    select id into v_unit from catalog.units where code = p_data ->> 'yield_unit';
    if v_unit is null then
      raise exception 'Elegí la unidad del rendimiento.' using errcode = '22023';
    end if;
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_versions
     set yield_quantity     = case when p_data ? 'yield_quantity' then nullif(p_data ->> 'yield_quantity', '')::numeric else yield_quantity end,
         yield_unit_id      = case when p_data ? 'yield_unit' then v_unit else yield_unit_id end,
         portions           = case when p_data ? 'portions' then nullif(p_data ->> 'portions', '')::integer else portions end,
         portion_grams      = case when p_data ? 'portion_grams' then nullif(p_data ->> 'portion_grams', '')::numeric else portion_grams end,
         description        = case when p_data ? 'description' then nullif(btrim(p_data ->> 'description'), '') else description end,
         storage_notes      = case when p_data ? 'storage_notes' then nullif(btrim(p_data ->> 'storage_notes'), '') else storage_notes end,
         presentation_notes = case when p_data ? 'presentation_notes' then nullif(btrim(p_data ->> 'presentation_notes'), '')
                                   else presentation_notes end,
         change_summary     = case when p_data ? 'change_summary' then nullif(btrim(p_data ->> 'change_summary'), '') else change_summary end
   where id = p_version_id;
  return jsonb_build_object('result', 'applied', 'message', 'Borrador guardado.');
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'recipe_versions_yield_unit_check' then
    raise exception 'El rendimiento necesita la cantidad y la unidad.' using errcode = '23514';
  elsif sqlstate in ('22P02', '22003') then
    raise exception 'Algún número no es válido.' using errcode = '22023';
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;

-- Los mensajes, en palabras.
create or replace function recipes.raise_friendly(p_state text, p_constraint text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $$
declare
  v_message text;
begin
  v_message := case
    when p_constraint = 'recipes_code_key' then 'Ya existe una receta con ese código en el grupo.'
    when p_constraint = 'recipes_code_check' then
      'El código va en mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, REC-0001).'
    when p_constraint = 'recipes_name_check' then 'El nombre no puede quedar vacío ni pasar los 120 caracteres.'
    when p_constraint = 'recipes_short_name_check' then 'El nombre corto va hasta 40 caracteres.'
    when p_constraint = 'recipe_categories_name_key' then 'Ya existe una categoría con ese nombre en el mismo nivel.'
    when p_constraint = 'recipe_categories_name_check' then 'El nombre no puede quedar vacío ni pasar los 80 caracteres.'
    when p_constraint = 'recipe_versions_open_key' then 'Ya hay una versión en borrador o en revisión: seguí con esa.'
    when p_constraint = 'recipe_assignments_open_key' then 'La receta ya está asignada a ese local.'
    when p_constraint = 'recipe_steps_instructions_check' then 'Cada paso necesita sus instrucciones (hasta 2.000 caracteres).'
    when p_constraint like 'recipe_steps_%_minutes_check' then 'Los minutos van de 0 a 10.080 (una semana).'
    when p_constraint = 'recipe_components_measure_count_check' then 'Las medidas prácticas van de 0,000001 a 999.999: revisá cuántas van.'
    when p_constraint = 'recipe_components_quantity_check' then 'La cantidad tiene que ser mayor que cero.'
    when p_constraint like '%\_notes\_check' or p_constraint like 'recipe_versions_%_check' then
      'Algún texto es demasiado largo o algún número no es válido.'
    when p_state = '23503' then 'Algo de lo elegido (local, categoría, materia prima o unidad) no existe en este grupo.'
    else p_message
  end;
  raise exception '%', v_message using errcode = case when p_state = '23503' then '22023' else p_state end;
end
$$;

-- Guardar una lista devuelve los elementos creados (created): quien agrega uno sin salir de la receta elige ese, y no el
-- último que se haya cargado.
create or replace function catalog.save_settings_list(p_group_id uuid, p_list catalog.settings_list, p_expected_stamp timestamp with time zone, p_items jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_keys   text[];
  v_item   jsonb;
  v_key    text;
  v_value  jsonb;
  v_id     uuid;
  v_created uuid[] := '{}';
  v_active boolean;
  v_name   text;
  v_hit    boolean;
  v_new    boolean;
  v_unit   uuid;
  v_cap    numeric;
  v_constraint text;
  v_uuid   constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  v_soft   boolean := p_list in ('ingredient_categories', 'recipe_categories', 'processes', 'units');
begin
  if not core.current_session_ok() or p_list is null or not catalog.can_manage_list(p_list, p_group_id) then
    return core.deny('catalog.save_settings_list', 'No tenés permiso para editar esta lista.', null,
                     jsonb_build_object('list', p_list),
                     (select g from core.visible_group_ids('catalog.view') g where g = p_group_id));
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 3 and 500 then
    raise exception 'Escribí el motivo de los cambios (de 3 a 500 caracteres).' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 100 then
    raise exception 'Son demasiados cambios juntos: guardá hasta 100 por vez.' using errcode = '22023';
  end if;
  v_keys := array['id', 'name', 'active'] || case p_list
    when 'ingredient_categories' then array['parent_id']
    when 'recipe_categories' then array['parent_id']
    when 'equipment' then array['capacity', 'capacity_unit', 'capacity_label']
    when 'measures' then array['content', 'content_unit', 'usage_note']
    when 'processes' then array['code']
    when 'units' then array['code', 'abbreviation', 'dimension', 'factor']
    else array[]::text[] end;
  for v_item in select value from jsonb_array_elements(p_items) loop
    perform org.check_keys(v_item, v_keys);
    if v_item ? 'id' and coalesce(v_item ->> 'id', '') !~ v_uuid then
      raise exception 'Algún elemento no es válido: recargá la página.' using errcode = '22023';
    end if;
    if v_item ? 'id' and v_item ?| array['parent_id', 'code', 'dimension', 'factor'] then
      raise exception 'El rubro, el código, el tipo y la equivalencia no cambian.' using errcode = '22023';
    end if;
    -- El nombre de una unidad lo leen las recetas publicadas y los pedidos: cambiarlo reescribiría lo ya publicado
    -- (revisión de seguridad y de base, G1). Para corregirla, se da de baja y se crea otra.
    if v_item ? 'id' and p_list = 'units' and v_item ?| array['name', 'abbreviation'] then
      raise exception 'Una unidad no cambia de nombre: dala de baja y creá otra.' using errcode = '23514';
    end if;
    -- Solo textos (y active), limpios: lo que no se ve o un < imitan a otro elemento. También en las listas de antes.
    for v_key, v_value in select key, value from jsonb_each(v_item) loop
      if v_key <> 'active' and jsonb_typeof(v_value) <> 'string' then
        raise exception 'Algún elemento no es válido: recargá la página.' using errcode = '22023';
      end if;
      if v_key <> 'active' and (core.has_hidden_characters(replace(v_value #>> '{}', chr(160), ' ')) or v_value #>> '{}' ~ '[<>]') then
        raise exception 'Algún texto lleva < o > o caracteres que no se ven: escribilo de nuevo.' using errcode = '22023';
      end if;
      if v_key in ('capacity', 'content', 'factor') and btrim(v_value #>> '{}') !~ '^$|^-?[0-9]{1,9}([.,][0-9]{1,6})?$' then
        raise exception 'Revisá los números: alguno no tiene el formato esperado.' using errcode = '22023';
      end if;
    end loop;
    if v_item ? 'active' and jsonb_typeof(v_item -> 'active') <> 'boolean' then
      raise exception 'Algún elemento no es válido: recargá la página.' using errcode = '22023';
    end if;
    if not v_item ? 'id' and nullif(btrim(v_item ->> 'name'), '') is null then
      raise exception 'Escribí el nombre de lo que agregaste.' using errcode = '22023';
    end if;
  end loop;

  -- Dos guardados de la misma lista van de a uno; el segundo ve que el primero cambió algo.
  perform pg_advisory_xact_lock(hashtextextended('catalog.settings_list:' || p_list || ':' || case when p_list = 'units' then '' else p_group_id::text end, 0));
  if p_expected_stamp is null or catalog.settings_list_stamp(p_list, p_group_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió esta lista mientras la editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');

  -- Primero las bajas (liberan el nombre), después los cambios, las reactivaciones y lo nuevo.
  for v_item, v_new in
    select value, not value ? 'id' from jsonb_array_elements(p_items) with ordinality t (value, n)
     order by (not value ? 'id'), case when value -> 'active' = 'false'::jsonb then 0 else 1 end, n
  loop
    v_id := (v_item ->> 'id')::uuid;
    v_name := v_item ->> 'name';
    v_active := (v_item ->> 'active')::boolean;

    -- El elemento es de esta lista y de este grupo (las unidades son de todo el sistema).
    if not v_new then
      v_hit := case p_list
        when 'ingredient_categories' then exists (select 1 from catalog.ingredient_categories where id = v_id and group_id = p_group_id)
        when 'recipe_categories' then exists (select 1 from recipes.recipe_categories where id = v_id and group_id = p_group_id)
        when 'sectors' then exists (select 1 from catalog.kitchen_sectors where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'stations' then exists (select 1 from catalog.kitchen_stations where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'equipment' then exists (select 1 from catalog.kitchen_equipment where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'measures' then exists (select 1 from catalog.practical_measures where id = v_id and group_id = p_group_id and deleted_at is null)
        when 'units' then exists (select 1 from catalog.units where id = v_id)
        else exists (select 1 from catalog.yield_processes where id = v_id and group_id = p_group_id) end;
      if not v_hit then
        raise exception 'Algún elemento ya no está en la lista: recargá la página.' using errcode = '22023';
      end if;
    end if;

    if v_soft then
      -- Las que ya existían: con sus funciones de siempre. Reactivar va antes de cambiar el nombre, y la baja después
      -- (un registro borrado no se edita).
      if not v_new and v_active and not catalog.item_is_live(p_list, v_id) then
        perform catalog.restore_item(p_list, p_group_id, v_id);
      end if;
      if p_list = 'ingredient_categories' then
        if v_new then
          if nullif(v_item ->> 'parent_id', '') is null then
            raise exception 'Elegí el rubro de la subcategoría nueva.' using errcode = '22023';
          end if;
          perform catalog.create_category(p_group_id, v_name, p_reason, (v_item ->> 'parent_id')::uuid);
        elsif v_item ? 'name' then
          perform catalog.rename_category(v_id, v_name, p_reason);
        end if;
        if not v_new and v_active is false then
          if exists (select 1 from catalog.ingredient_categories where id = v_id and parent_id is null) then
            raise exception 'Un rubro se da de baja en Rubros.' using errcode = '23514';
          end if;
          perform catalog.archive_category(v_id, p_reason);
        end if;
      elsif p_list = 'recipe_categories' then
        if v_new then
          if nullif(v_item ->> 'parent_id', '') is null then
            raise exception 'Elegí el rubro de la subcategoría nueva.' using errcode = '22023';
          end if;
          perform recipes.create_category(p_group_id, v_name, p_reason, (v_item ->> 'parent_id')::uuid);
        elsif v_item ? 'name' then
          perform recipes.rename_category(v_id, v_name, p_reason);
        end if;
        if not v_new and v_active is false then
          if exists (select 1 from recipes.recipe_categories where id = v_id and parent_id is null) then
            raise exception 'Un rubro se da de baja en Rubros.' using errcode = '23514';
          end if;
          perform recipes.archive_category(v_id, p_reason);
        end if;
      elsif p_list = 'processes' then
        if v_new then
          perform catalog.create_yield_process(p_group_id, v_item ->> 'code', v_name, p_reason);
        elsif v_item ? 'name' then
          perform catalog.rename_yield_process(v_id, v_name, p_reason);
        end if;
        if not v_new and v_active is false then
          perform catalog.archive_yield_process(v_id, p_reason);
        end if;
      else
        if v_new then
          if not coalesce(v_item ->> 'dimension', '') = any (enum_range(null::catalog.dimension)::text[]) then
            raise exception 'Elegí si la unidad es de peso, volumen, unidades o un envase.' using errcode = '22023';
          end if;
          perform catalog.create_unit(p_group_id, v_item ->> 'code', v_name, v_item ->> 'abbreviation',
                                      (v_item ->> 'dimension')::catalog.dimension, p_reason,
                                      nullif(replace(btrim(v_item ->> 'factor'), ',', '.'), '')::numeric);
        end if;
        if not v_new and v_active is false then
          perform catalog.archive_unit(p_group_id, v_id, p_reason);
        end if;
      end if;
      continue;
    end if;

    -- Las listas de la cocina.
    if v_item ? 'name' and nullif(btrim(v_name), '') is null then
      raise exception 'El nombre no puede quedar vacío.' using errcode = '22023';
    end if;
    if p_list = 'sectors' then
      if v_new then
        insert into catalog.kitchen_sectors (group_id, name, is_active) values (p_group_id, v_name, coalesce(v_active, true))
        returning id into v_id;
        v_created := v_created || v_id;
      else
        update catalog.kitchen_sectors set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active) where id = v_id;
      end if;
    elsif p_list = 'stations' then
      if v_new then
        insert into catalog.kitchen_stations (group_id, name, is_active) values (p_group_id, v_name, coalesce(v_active, true))
        returning id into v_id;
        v_created := v_created || v_id;
      else
        update catalog.kitchen_stations set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active) where id = v_id;
      end if;
    elsif p_list = 'equipment' then
      -- La capacidad viaja entera: número y, o bien una unidad del sistema, o bien una palabra.
      v_cap := nullif(replace(btrim(v_item ->> 'capacity'), ',', '.'), '')::numeric;
      v_unit := null;
      if nullif(v_item ->> 'capacity_unit', '') is not null then
        select id into v_unit from catalog.units where code = v_item ->> 'capacity_unit' and deleted_at is null;
        if v_unit is null then
          raise exception 'Elegí la unidad de la capacidad.' using errcode = '22023';
        end if;
      end if;
      if v_item ?| array['capacity', 'capacity_unit', 'capacity_label']
         and not v_item ?& array['capacity', 'capacity_unit', 'capacity_label'] then
        raise exception 'La capacidad va completa: cuánto y en qué.' using errcode = '22023';
      end if;
      if v_new then
        insert into catalog.kitchen_equipment (group_id, name, capacity, capacity_unit_id, capacity_label, is_active)
        values (p_group_id, v_name, v_cap, v_unit, nullif(btrim(v_item ->> 'capacity_label'), ''), coalesce(v_active, true))
        returning id into v_id;
        v_created := v_created || v_id;
      else
        update catalog.kitchen_equipment
           set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active),
               capacity = case when v_item ? 'capacity' then v_cap else capacity end,
               capacity_unit_id = case when v_item ? 'capacity' then v_unit else capacity_unit_id end,
               capacity_label = case when v_item ? 'capacity' then nullif(btrim(v_item ->> 'capacity_label'), '') else capacity_label end
         where id = v_id;
      end if;
    else
      v_cap := nullif(replace(btrim(v_item ->> 'content'), ',', '.'), '')::numeric;
      v_unit := null;
      if v_item ? 'content_unit' then
        select id into v_unit from catalog.units where code = v_item ->> 'content_unit' and is_base and deleted_at is null;
        if v_unit is null then
          raise exception 'Lo que contiene la medida va en ml, g o unidades.' using errcode = '22023';
        end if;
      end if;
      if v_new then
        if v_cap is null or v_unit is null then
          raise exception 'Escribí cuánto contiene «%» y en qué unidad.', btrim(v_name) using errcode = '22023';
        end if;
        insert into catalog.practical_measures (group_id, name, content, content_unit_id, usage_note, is_active)
        values (p_group_id, v_name, v_cap, v_unit, nullif(btrim(v_item ->> 'usage_note'), ''), coalesce(v_active, true))
        returning id into v_id;
        v_created := v_created || v_id;
      else
        if v_item ? 'content' and v_cap is null then
          raise exception 'Escribí cuánto contiene la medida.' using errcode = '22023';
        end if;
        update catalog.practical_measures
           set name = coalesce(v_name, name), is_active = coalesce(v_active, is_active),
               content = coalesce(v_cap, content), content_unit_id = coalesce(v_unit, content_unit_id),
               usage_note = case when v_item ? 'usage_note' then nullif(btrim(v_item ->> 'usage_note'), '') else usage_note end
         where id = v_id;
      end if;
    end if;
  end loop;

  return jsonb_build_object('result', 'applied', 'message', 'Cambios guardados.', 'created', to_jsonb(v_created),
                            'stamp', catalog.settings_list_stamp(p_list, p_group_id));
exception
  when unique_violation or check_violation then
    get stacked diagnostics v_constraint = constraint_name;
    -- Los mensajes propios de la base y de las funciones de siempre pasan tal cual.
    if coalesce(v_constraint, '') = '' then
      raise;
    elsif v_constraint like '%\_name\_key' then
      raise exception 'Ya hay un elemento con ese nombre en la lista (puede estar inactivo).' using errcode = '23505';
    elsif v_constraint in ('yield_processes_code_key', 'units_code_key') then
      raise exception 'Ya hay un elemento con ese código.' using errcode = '23505';
    elsif v_constraint like '%\_name\_check' then
      raise exception 'El nombre no puede quedar vacío, ser demasiado largo ni llevar < o >.' using errcode = '23514';
    elsif v_constraint = 'kitchen_equipment_capacity_form' then
      raise exception 'La capacidad va completa: cuánto y en qué.' using errcode = '23514';
    elsif v_constraint = 'kitchen_equipment_label_check' then
      raise exception 'La capacidad en palabras va hasta 40 caracteres, sin < ni >.' using errcode = '23514';
    elsif v_constraint = 'practical_measures_note_check' then
      raise exception '«Se usa con» va hasta 120 caracteres, sin < ni >.' using errcode = '23514';
    elsif v_constraint = 'recipe_components_measure_count_check' then
      raise exception 'Con ese contenido, alguna receta llevaría demasiadas medidas: revisalo.' using errcode = '23514';
    elsif v_constraint in ('kitchen_equipment_capacity_check', 'practical_measures_content_check') then
      raise exception 'El número tiene que ser mayor que cero y no tan grande.' using errcode = '23514';
    elsif v_constraint in ('unit_conversions_factor_check', 'unit_conversions_factor_number') then
      raise exception 'La equivalencia tiene que ser un número mayor que cero y no tan grande.' using errcode = '23514';
    elsif v_constraint in ('units_abbreviation_check', 'units_long_name_check') then
      raise exception 'La unidad lleva un nombre (hasta 40 caracteres) y una abreviatura (hasta 12).' using errcode = '23514';
    end if;
    raise;
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Revisá los números: alguno no tiene el formato esperado o es demasiado grande.' using errcode = '22023';
end
$$;
