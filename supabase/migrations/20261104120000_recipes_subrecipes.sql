-- Fase 2, etapa 2.2 B: subrecetas y variantes locales (ADR-0025). Documento de Soy, sección 11, y sus
-- respuestas (ADR-0024):
--
-- - Una línea puede ser una materia prima o una subreceta (una preparación). La línea apunta a la receta,
--   no a una versión: el plato usa siempre la versión vigente de la preparación ("cambian solos",
--   respuesta 10 de Soy). Al publicarse una versión nueva de una preparación, se avisa.
-- - Sin ciclos (A usa B, B usa C, C usa A) y hasta 10 niveles. La subreceta tiene que estar al alcance
--   del plato y su unidad, poder convertirse a la de su rendimiento.
-- - Alérgenos: se propagan por las subrecetas; un dato que falta en cualquier nivel deja "no verificado".
-- - Quien ve un plato ve también las preparaciones que usa (para cocinarlas).
-- - Variante local: una receta de un local hecha a partir de una maestra. La crea el Chef Ejecutivo (o
--   quien tenga recipes.approve en ese local). Al publicarse, el local deja de usar la maestra.
-- - Pariggi es un proveedor externo (respuesta 11): no hace falta nada especial.

-- ---------------------------------------------------------------------------
-- 1. Estructura
-- ---------------------------------------------------------------------------
alter type recipes.quantity_basis add value 'finished';
comment on type recipes.quantity_basis is
  'Qué representa la cantidad de una línea: peso de compra (purchase), limpio (clean) o cocido (cooked) de una materia prima, o cantidad terminada (finished) de una subreceta.';
alter type core.notification_kind add value 'recipe_changed';

alter table recipes.recipe_components
  alter column ingredient_id drop not null,
  add column sub_recipe_id uuid,
  add constraint recipe_components_sub_recipe_fkey foreign key (sub_recipe_id, group_id)
    references recipes.recipes (id, group_id) on delete restrict,
  -- Una línea es una materia prima o una subreceta, nunca las dos.
  add constraint recipe_components_item_check check ((ingredient_id is null) <> (sub_recipe_id is null)),
  -- Una subreceta se mide en cantidad terminada; una materia prima, nunca.
  add constraint recipe_components_basis_check check ((sub_recipe_id is not null) = (quantity_basis::text = 'finished')),
  add constraint recipe_components_yield_profile_check check (sub_recipe_id is null or yield_profile_id is null);
-- No parcial por deleted_at: lo usa también el control de la clave foránea.
create index recipe_components_sub_recipe_idx on recipes.recipe_components (sub_recipe_id, group_id)
  where sub_recipe_id is not null;
comment on table recipes.recipe_components is
  'Líneas de una versión de receta: una materia prima o una preparación (subreceta), con su cantidad. Solo cambian en un borrador; nada se borra: se da de baja.';
comment on column recipes.recipe_components.ingredient_id is 'Materia prima, si la línea es una materia prima.';
comment on column recipes.recipe_components.sub_recipe_id is
  'Subreceta (una preparación), si la línea es una receta. Se usa siempre su versión vigente.';
comment on column recipes.recipe_components.quantity_basis is
  'Qué representa la cantidad: peso de compra, limpio o cocido (materia prima), o cantidad terminada (preparación).';
comment on column recipes.recipe_components.unit_id is
  'Unidad de la cantidad. Tiene que poder pasarse a la unidad de la materia prima, o a la del rendimiento de la preparación.';
comment on type recipes.recipe_scope is
  'Alcance de una receta: maestra del grupo, de marca o de local. Una variante es una receta de local con su maestra (variant_of_recipe_id). La cocina central no se usa: Pariggi es un proveedor externo (ADR-0025).';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (una solicitud que la persona puede decidir) o recipe_changed (se publicó una versión nueva de una preparación que usan otras recetas).';
comment on column core.notifications.kind is
  'Tipo de aviso: approval_requested (una solicitud que la persona puede decidir) o recipe_changed (cambió una preparación que se usa).';

alter table recipes.recipes
  add column variant_of_recipe_id uuid,
  add constraint recipes_variant_fkey foreign key (variant_of_recipe_id, group_id)
    references recipes.recipes (id, group_id) on delete restrict,
  -- Una variante es siempre de un local.
  add constraint recipes_variant_check check (variant_of_recipe_id is null or scope_type = 'restaurant');
create index recipes_variant_idx on recipes.recipes (variant_of_recipe_id, group_id) where variant_of_recipe_id is not null;
-- Una sola variante activa por maestra y local.
create unique index recipes_variant_key on recipes.recipes (variant_of_recipe_id, restaurant_id)
  where variant_of_recipe_id is not null and is_active and deleted_at is null;
comment on column recipes.recipes.variant_of_recipe_id is
  'Receta maestra de la que sale, si es una variante local. Las diferencias contra la maestra se muestran siempre.';

-- El código, el alcance y la maestra de una receta no cambian; la categoría tiene que estar vigente.
create or replace function recipes.enforce_recipe_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted timestamptz;
begin
  if tg_op = 'UPDATE' and (new.code is distinct from old.code or new.scope_type is distinct from old.scope_type
                           or new.brand_id is distinct from old.brand_id
                           or new.restaurant_id is distinct from old.restaurant_id
                           or new.variant_of_recipe_id is distinct from old.variant_of_recipe_id) then
    raise exception 'El código, el alcance y la maestra de una receta no cambian.' using errcode = '42501';
  end if;
  if new.category_id is not null and (tg_op = 'INSERT' or new.category_id is distinct from old.category_id) then
    select deleted_at into v_deleted from recipes.recipe_categories where id = new.category_id for share;
    if v_deleted is not null then
      raise exception 'Esa categoría está borrada: elegí otra.' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function recipes.enforce_recipe_rules() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipes: el código, el alcance y la maestra no cambian; la categoría tiene que estar vigente.';

-- ---------------------------------------------------------------------------
-- 2. Ayudantes: alcance, unidades, ciclos y profundidad
-- ---------------------------------------------------------------------------
-- Si un plato puede usar una preparación: la maestra del grupo, cualquiera; la de marca, las recetas de
-- esa marca y de sus locales; la de local, solo las de ese local.
create function recipes.sub_in_scope(p_parent uuid, p_sub uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.group_id = s.group_id
           and case s.scope_type when 'group' then true
                                 when 'brand' then p.brand_id = s.brand_id
                                 else p.restaurant_id = s.restaurant_id end
      from recipes.recipes p, recipes.recipes s
     where p.id = p_parent and s.id = p_sub), false)
$$;
comment on function recipes.sub_in_scope(uuid, uuid) is
  'Interna: si el plato p_parent puede usar la preparación p_sub (mismo grupo y dentro de su alcance).';
revoke execute on function recipes.sub_in_scope(uuid, uuid) from public;

-- Cuánto vale una unidad en la unidad base de su dimensión (kg → 1.000 g). Vacío para los envases.
create function recipes.unit_to_base(p_unit_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case when u.is_base then 1
              else (select c.factor from catalog.unit_conversions c
                     join catalog.units b on b.id = c.to_unit_id and b.is_base and b.dimension = u.dimension
                    where c.from_unit_id = u.id and c.deleted_at is null limit 1) end
    from catalog.units u
   where u.id = p_unit_id and u.dimension <> 'package'
$$;
comment on function recipes.unit_to_base(uuid) is 'Interna: factor de una unidad a la base de su dimensión (g, ml o unidad), o vacío.';
revoke execute on function recipes.unit_to_base(uuid) from public;

-- Si p_target se alcanza desde p_from siguiendo sus subrecetas. Con p_only_published, solo por las
-- versiones vigentes; si no, también por los borradores y las revisiones abiertas.
create function recipes.reaches(p_from uuid, p_target uuid, p_only_published boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive walk (recipe_id, depth) as (
    select p_from, 1
    union
    select c.sub_recipe_id, w.depth + 1
      from walk w
      join recipes.recipe_versions v
        on v.recipe_id = w.recipe_id
       and (v.status = 'published' or (not p_only_published and v.status in ('draft', 'in_review')))
      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null and c.sub_recipe_id is not null
     where w.depth < 12)
  select exists (select 1 from walk where recipe_id = p_target)
$$;
comment on function recipes.reaches(uuid, uuid, boolean) is
  'Interna: si p_target aparece al recorrer las subrecetas de p_from (para no formar ciclos).';
revoke execute on function recipes.reaches(uuid, uuid, boolean) from public;

-- Cuántos niveles de subrecetas tiene una receta por sus versiones vigentes (0 si no usa ninguna).
create function recipes.sub_depth(p_recipe_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with recursive walk (recipe_id, depth) as (
    select p_recipe_id, 0
    union
    select c.sub_recipe_id, w.depth + 1
      from walk w
      join recipes.recipe_versions v on v.recipe_id = w.recipe_id and v.status = 'published'
      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null and c.sub_recipe_id is not null
     where w.depth < 12)
  select max(depth) from walk
$$;
comment on function recipes.sub_depth(uuid) is 'Interna: niveles de subrecetas de una receta por sus versiones vigentes.';
revoke execute on function recipes.sub_depth(uuid) from public;

-- Cuántos niveles de recetas tiene encima: las que la usan, por sus versiones vigentes o abiertas (0 si
-- nadie la usa). El límite de 10 niveles mira para los dos lados (revisión de base, G1).
create function recipes.sub_height(p_recipe_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  with recursive walk (recipe_id, height) as (
    select p_recipe_id, 0
    union
    select v.recipe_id, w.height + 1
      from walk w
      join recipes.recipe_components c on c.sub_recipe_id = w.recipe_id and c.deleted_at is null
      join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status in ('published', 'draft', 'in_review')
     where w.height < 12)
  select max(height) from walk
$$;
comment on function recipes.sub_height(uuid) is
  'Interna: niveles de recetas que usan a esta (por sus versiones vigentes o abiertas).';
revoke execute on function recipes.sub_height(uuid) from public;

-- Los cambios del árbol de preparaciones de un grupo van de a uno (guardar líneas y publicar): así dos
-- cambios simultáneos no forman un círculo ni pasan el límite de niveles sin verse.
create function recipes.lock_sub_graph(p_group_id uuid)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('recipes.sub_graph:' || p_group_id::text, 0))
$$;
comment on function recipes.lock_sub_graph(uuid) is
  'Interna: bloqueo de transacción por grupo para los cambios del árbol de preparaciones.';
revoke execute on function recipes.lock_sub_graph(uuid) from public;

-- La primera línea que ya no sirve de una versión (al guardar, al pedir la revisión y al publicar), con
-- las mismas reglas que set_components: materia prima o preparación que ya no está vigente, fuera del
-- alcance, unidad que no se convierte, estándar vencido, círculo o más de 10 niveles.
create function recipes.first_invalid_line(p_version_id uuid)
returns table (line_order integer, item text, why text)
language sql
stable
security definer
set search_path = ''
as $$
  select x.line_order, x.item, x.why
    from (
      select c.line_order, coalesce(i.name, s.name) as item,
             case
               when c.ingredient_id is not null and (i.id is null or i.deleted_at is not null or not i.is_active)
                 then 'la materia prima ya no está vigente'
               when c.ingredient_id is not null and b.status is distinct from 'ok'
                 then 'no se puede pasar a la unidad de la materia prima'
               when c.yield_profile_id is not null
                    and not exists (select 1 from catalog.ingredient_yield_profiles p
                                     where p.id = c.yield_profile_id and p.ingredient_id = c.ingredient_id
                                       and p.status = 'approved' and p.deleted_at is null)
                 then 'el rendimiento elegido ya no es el estándar vigente'
               when c.sub_recipe_id is null
                 then null
               when s.id is null or s.deleted_at is not null or not s.is_active or sv.id is null
                 then 'la preparación ya no tiene una versión vigente'
               when not recipes.sub_in_scope(v.recipe_id, c.sub_recipe_id)
                 then 'la preparación está fuera del alcance de esta receta'
               when recipes.unit_to_base(c.unit_id) is null or recipes.unit_to_base(sv.yield_unit_id) is null
                 then 'la unidad no sirve para una preparación'
               when (select dimension from catalog.units where id = c.unit_id)
                    is distinct from (select dimension from catalog.units where id = sv.yield_unit_id)
                 then 'la unidad no se puede pasar a la del rendimiento de la preparación'
               when c.sub_recipe_id = v.recipe_id or recipes.reaches(c.sub_recipe_id, v.recipe_id, true)
                 then 'la preparación ya usa esta receta: se formaría un círculo'
               when recipes.sub_height(v.recipe_id) + 1 + coalesce(recipes.sub_depth(c.sub_recipe_id), 0) > 9
                 then 'se pasaría de 10 niveles de preparaciones'
             end as why
        from recipes.recipe_components c
        join recipes.recipe_versions v on v.id = c.recipe_version_id
        left join catalog.ingredients i on i.id = c.ingredient_id
        left join lateral catalog.to_base_quantity(c.ingredient_id, c.quantity, c.unit_id) b on c.ingredient_id is not null
        left join recipes.recipes s on s.id = c.sub_recipe_id
        left join recipes.recipe_versions sv on sv.recipe_id = c.sub_recipe_id and sv.status = 'published'
       where c.recipe_version_id = p_version_id and c.deleted_at is null) x
   where x.why is not null
   order by x.line_order
   limit 1
$$;
comment on function recipes.first_invalid_line(uuid) is
  'Interna: la primera línea de una versión que ya no sirve (materia prima o preparación no vigente, fuera del alcance, unidad, estándar vencido, círculo o más de 10 niveles), o nada.';
revoke execute on function recipes.first_invalid_line(uuid) from public;

-- ---------------------------------------------------------------------------
-- 3. Quien ve un plato ve también las preparaciones que usa
-- ---------------------------------------------------------------------------
create or replace function recipes.viewable_recipe_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive base as (
    select r.id
      from recipes.recipes r
     where r.deleted_at is null
       and exists (select 1 from recipes.recipe_versions v where v.recipe_id = r.id and v.status = 'published')
       and (r.restaurant_id in (select core.permitted_restaurant_ids('recipes.view'))
            or (r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('recipes.view')))
            or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('recipes.view')))
            or (r.brand_id is null
                and r.group_id in (select b.group_id from org.brands b
                                    where b.id in (select core.permitted_brand_ids('recipes.view'))))
            or r.id in (select a.recipe_id from recipes.recipe_assignments a
                         where a.deleted_at is null and a.valid_from <= recipes.today()
                           and (a.valid_to is null or a.valid_to > recipes.today())
                           and a.restaurant_id in (select core.permitted_restaurant_ids('recipes.view'))))),
  -- Las preparaciones de lo que se ve, por las versiones vigentes, hasta 10 niveles.
  expanded (id, depth) as (
    select id, 0 from base
    union
    select c.sub_recipe_id, e.depth + 1
      from expanded e
      join recipes.recipe_versions v on v.recipe_id = e.id and v.status = 'published'
      join recipes.recipe_components c on c.recipe_version_id = v.id and c.deleted_at is null and c.sub_recipe_id is not null
     where e.depth < 10)
  select distinct e.id
    from expanded e
    join recipes.recipes r on r.id = e.id and r.deleted_at is null
   where exists (select 1 from recipes.recipe_versions v where v.recipe_id = e.id and v.status = 'published')
$$;
comment on function recipes.viewable_recipe_ids() is
  'Recetas cuya versión vigente ve la sesión: por su alcance, por ver toda una marca (maestras del grupo), porque está asignada a un local suyo, o porque es una preparación de una receta que ve. Para las políticas.';

-- ---------------------------------------------------------------------------
-- 4. Componentes: materias primas o subrecetas
-- ---------------------------------------------------------------------------
create or replace function recipes.set_components(p_version_id uuid, p_lines jsonb, p_reason text,
                                                  p_expected_updated_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  v_constraint text;
  v_message    text;
begin
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
                                         'no_scale', 'notes']);
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
      insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id,
                                             quantity_basis, no_scale, notes)
      values (v_r.group_id, p_version_id, v_n, v_sub.id, v_qty, v_unit.id, 'finished',
              coalesce((v_line ->> 'no_scale')::boolean, false), nullif(btrim(v_line ->> 'notes'), ''));
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
    insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id,
                                           quantity_basis, yield_profile_id, no_scale, notes)
    values (v_r.group_id, p_version_id, v_n, v_ing.id, v_qty, v_unit.id, v_basis, v_profile,
            coalesce((v_line ->> 'no_scale')::boolean, false), nullif(btrim(v_line ->> 'notes'), ''));
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
comment on function recipes.set_components(uuid, jsonb, text, timestamptz) is
  'Reemplaza las líneas de un borrador. Cada línea: ingredient_id (materia prima) o sub_recipe_id (preparación, con su versión vigente, al alcance del plato, sin ciclos y hasta 10 niveles), quantity, unit (código), basis, yield_profile_id, no_scale, notes. Con p_expected_updated_at, rechaza si otra persona lo cambió. Pide recipes.draft y un motivo.';

-- ---------------------------------------------------------------------------
-- 5. Revisión: las líneas se validan con las mismas reglas (también las preparaciones)
-- ---------------------------------------------------------------------------
create or replace function recipes.request_review(p_version_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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

-- ---------------------------------------------------------------------------
-- 6. Publicar: se vuelve a controlar el ciclo, se avisa a quienes usan la preparación y, si es una
--    variante, su local deja de usar la maestra
-- ---------------------------------------------------------------------------
-- A quién se avisa cuando cambia una preparación (provisorio hasta la pregunta 5 de Soy, ADR-0025):
-- Compras y Dirección General de todo el grupo, y quien puede publicar cada plato afectado.
create function recipes.notify_recipe_changed(p_version_id uuid, p_approver uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r recipes.recipes;
  v_v recipes.recipe_versions;
begin
  select * into v_v from recipes.recipe_versions where id = p_version_id;
  select * into v_r from recipes.recipes where id = v_v.recipe_id;
  -- Los alcances distintos de los platos que la usan en su versión vigente (como mucho, locales + marcas
  -- + 1): así el permiso se pregunta pocas veces aunque la usen miles de platos (revisión de base, M3).
  -- El aviso no dice cuántos platos son: un destinatario no tiene por qué saber de los de otras marcas.
  if not exists (select 1 from recipes.recipe_components c
                   join recipes.recipe_versions pv on pv.id = c.recipe_version_id and pv.status = 'published'
                   join recipes.recipes p on p.id = pv.recipe_id and p.deleted_at is null and p.is_active
                  where c.sub_recipe_id = v_r.id and c.deleted_at is null) then
    return;
  end if;
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  with scopes as materialized (
    select distinct p.scope_type::text::core.scope_type as scope_type, p.brand_id, p.restaurant_id
      from recipes.recipe_components c
      join recipes.recipe_versions pv on pv.id = c.recipe_version_id and pv.status = 'published'
      join recipes.recipes p on p.id = pv.recipe_id and p.deleted_at is null and p.is_active
     where c.sub_recipe_id = v_r.id and c.deleted_at is null)
  select u.user_id, v_r.group_id, 'recipe_changed',
         format('Cambió «%s» (v%s)', v_r.name, v_v.version_number),
         'Las recetas que la usan ya usan la versión nueva. Revisá si hace falta ajustar algo.',
         '/recetas/' || v_r.id
    from (select distinct a.user_id
            from core.user_role_assignments a
           where a.group_id = v_r.group_id and a.deleted_at is null
             and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())) u
   where u.user_id is distinct from p_approver
     and (core.user_has_role_for_scope(u.user_id, array['purchasing', 'general_management'], 'group', v_r.group_id)
          or exists (select 1 from scopes f
                      where core.user_has_permission_for_scope(u.user_id, 'recipes.publish', f.scope_type, v_r.group_id,
                                                               f.brand_id, f.restaurant_id)));
end
$$;
comment on function recipes.notify_recipe_changed(uuid, uuid) is
  'Interna: avisa que cambió una preparación a Compras y Dirección General del grupo y a quien puede publicar cada plato que la usa, salvo a quien la aprobó.';
revoke execute on function recipes.notify_recipe_changed(uuid, uuid) from public;

create or replace function recipes.apply_publish_version(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests := workflow.approved_request(p_request_id);
  v_v   recipes.recipe_versions;
  v_r   recipes.recipes;
  v_bad   record;
  v_users text;
begin
  select * into v_v from recipes.recipe_versions
   where id = v_req.entity_id and approval_request_id = p_request_id and deleted_at is null
   for update;
  if not found or v_v.status <> 'in_review' then
    perform workflow.cannot_apply('la versión ya no está en revisión');
  end if;
  select * into v_r from recipes.recipes where id = v_v.recipe_id and is_active and deleted_at is null;
  if v_r.id is null then
    perform workflow.cannot_apply('la receta está archivada');
  end if;
  -- Las publicaciones del grupo van de a uno: dos borradores cruzados no se aprueban a la vez.
  perform recipes.lock_sub_graph(v_r.group_id);
  -- Por si dos borradores se cruzaron, o una preparación dejó de estar vigente mientras tanto.
  select * into v_bad from recipes.first_invalid_line(v_v.id);
  if v_bad.line_order is not null then
    perform workflow.cannot_apply(format('línea %s (%s): %s', v_bad.line_order, v_bad.item, v_bad.why));
  end if;
  -- Las recetas que la usan miden su cantidad en la unidad del rendimiento: no puede cambiar de tipo
  -- (de kilos a unidades, por ejemplo) mientras alguna la use (revisión de base, M2).
  select string_agg(distinct p.name, ', ') into v_users
    from recipes.recipe_components c
    join recipes.recipe_versions pv on pv.id = c.recipe_version_id and pv.status in ('published', 'draft', 'in_review')
    join recipes.recipes p on p.id = pv.recipe_id and p.is_active and p.deleted_at is null
    join catalog.units u on u.id = c.unit_id
   where c.sub_recipe_id = v_r.id and c.deleted_at is null
     and u.dimension is distinct from (select dimension from catalog.units where id = v_v.yield_unit_id);
  if v_users is not null then
    perform workflow.cannot_apply(format('el rendimiento cambia de tipo de unidad y lo usan otras recetas (%s)',
                                         left(v_users, 300)));
  end if;
  -- Una variante: la maestra no se reasigna a este local mientras tanto.
  if v_r.variant_of_recipe_id is not null then
    perform 1 from recipes.recipes where id = v_r.variant_of_recipe_id for share;
  end if;
  update recipes.recipe_versions set status = 'archived' where recipe_id = v_v.recipe_id and status = 'published';
  update recipes.recipe_versions set status = 'approved', approved_by = v_req.resolved_by where id = v_v.id;
  update recipes.recipe_versions set status = 'published', published_at = now() where id = v_v.id;
  -- Una variante publicada reemplaza a su maestra en su local.
  if v_r.variant_of_recipe_id is not null then
    update recipes.recipe_assignments set valid_to = greatest(valid_from, recipes.today())
     where recipe_id = v_r.variant_of_recipe_id and restaurant_id = v_r.restaurant_id
       and valid_to is null and deleted_at is null;
  end if;
  perform recipes.notify_recipe_changed(v_v.id, v_req.resolved_by);
end
$$;
comment on function recipes.apply_publish_version(uuid) is
  'Interna (aprobación recipes.publish_version): vuelve a validar las líneas (preparaciones, círculos, niveles y unidad del rendimiento si otras recetas la usan); la vigente pasa a archivada y la aprobada queda publicada; si es una variante, su local deja de usar la maestra; avisa a quienes usan la preparación.';

-- ---------------------------------------------------------------------------
-- 7. Alérgenos por las subrecetas
-- ---------------------------------------------------------------------------
create or replace function recipes.version_allergens(p_version_id uuid)
returns table (allergen_id uuid, code text, name text, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_group   uuid;
  v_tree    uuid[];
  v_missing boolean;
  v_cut     boolean;
begin
  if not recipes.can_see_version(p_version_id) then
    return;
  end if;
  select group_id into v_group from recipes.recipe_versions where id = p_version_id;
  -- Las versiones del árbol: esta y las vigentes de sus preparaciones, hasta 10 niveles.
  with recursive tree (version_id, depth) as (
    select p_version_id, 0
    union
    select sv.id, t.depth + 1
      from tree t
      join recipes.recipe_components c on c.recipe_version_id = t.version_id and c.deleted_at is null and c.sub_recipe_id is not null
      join recipes.recipe_versions sv on sv.recipe_id = c.sub_recipe_id and sv.status = 'published'
     where t.depth < 10)
  select array_agg(distinct t.version_id),
         -- Si en el último nivel todavía hay preparaciones, el árbol quedó cortado: no se puede decir que
         -- no tiene un alérgeno (revisión de base, G1). Nunca un "verificado" parcial.
         coalesce(bool_or(t.depth >= 10 and exists (select 1 from recipes.recipe_components c
                                                     where c.recipe_version_id = t.version_id and c.deleted_at is null
                                                       and c.sub_recipe_id is not null)), false)
    into v_tree, v_cut from tree t;
  -- Una preparación sin versión vigente deja todo sin verificar.
  select v_cut or exists (select 1 from recipes.recipe_components c
                           where c.recipe_version_id = any (v_tree) and c.deleted_at is null and c.sub_recipe_id is not null
                             and not exists (select 1 from recipes.recipe_versions sv
                                              where sv.recipe_id = c.sub_recipe_id and sv.status = 'published'))
    into v_missing;
  return query
  with ings as (select distinct c.ingredient_id
                  from recipes.recipe_components c
                 where c.recipe_version_id = any (v_tree) and c.deleted_at is null and c.ingredient_id is not null)
  select a.id, a.code, a.name,
         case when bool_or(ia.status = 'contains') then 'contains'
              when bool_or(ia.status = 'may_contain') then 'may_contain'
              when v_missing then 'not_verified'
              when count(i.ingredient_id) > 0 and count(i.ingredient_id) = count(*) filter (where ia.status = 'free_verified')
                then 'free_verified'
              else 'not_verified' end
    from catalog.allergens a
    left join ings i on true
    left join catalog.ingredient_allergens ia
      on ia.ingredient_id = i.ingredient_id and ia.allergen_id = a.id and ia.deleted_at is null
   where a.group_id = v_group and a.deleted_at is null
   group by a.id, a.code, a.name
   order by a.name;
end
$$;
comment on function recipes.version_allergens(uuid) is
  'Alérgenos de una versión, también por sus preparaciones (hasta 10 niveles): contains, may_contain, free_verified (todo verificado) o not_verified (algún dato falta o una preparación no tiene vigente). Vacío si la sesión no ve la versión.';

-- ---------------------------------------------------------------------------
-- 8. Ficha de cocina y diferencias, con las preparaciones
-- ---------------------------------------------------------------------------
create or replace function recipes.kitchen_card(p_recipe_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
                                          'basis', c.quantity_basis, 'notes', c.notes) order by c.line_order)
        from recipes.recipe_components c
        left join catalog.ingredients i on i.id = c.ingredient_id
        left join recipes.recipes s on s.id = c.sub_recipe_id
        join catalog.units u on u.id = c.unit_id
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
comment on function recipes.kitchen_card(uuid) is
  'Ficha de cocina de la versión vigente: componentes (materias primas y preparaciones, con su enlace), pasos, tiempos y alérgenos, sin ningún valor económico. Vacío si la sesión no ve la receta o no hay versión vigente.';

-- Diferencias entre dos versiones (de la misma receta, o una variante contra su maestra).
create function recipes.compare_versions(p_new uuid, p_old uuid)
returns table (change text, ingredient text, unit text, basis recipes.quantity_basis, old_quantity numeric,
               new_quantity numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with n as (select coalesce(c.ingredient_id, c.sub_recipe_id) as item, c.unit_id, c.quantity_basis, sum(c.quantity) as q
               from recipes.recipe_components c
              where c.recipe_version_id = p_new and c.deleted_at is null group by 1, 2, 3),
       o as (select coalesce(c.ingredient_id, c.sub_recipe_id) as item, c.unit_id, c.quantity_basis, sum(c.quantity) as q
               from recipes.recipe_components c
              where c.recipe_version_id = p_old and c.deleted_at is null group by 1, 2, 3)
  select case when o.q is null then 'added' when n.q is null then 'removed' else 'changed' end,
         coalesce(i.name, r.name), u.name, coalesce(n.quantity_basis, o.quantity_basis), o.q, n.q
    from n full join o using (item, unit_id, quantity_basis)
    left join catalog.ingredients i on i.id = coalesce(n.item, o.item)
    left join recipes.recipes r on r.id = coalesce(n.item, o.item)
    join catalog.units u on u.id = coalesce(n.unit_id, o.unit_id)
   where n.q is distinct from o.q
   order by 2
$$;
comment on function recipes.compare_versions(uuid, uuid) is
  'Interna: qué líneas (materias primas o preparaciones) se agregan, quitan o cambian de cantidad entre dos versiones.';
revoke execute on function recipes.compare_versions(uuid, uuid) from public;

create or replace function recipes.version_diff(p_version_id uuid)
returns table (change text, ingredient text, unit text, basis recipes.quantity_basis, old_quantity numeric,
               new_quantity numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_prev uuid;
begin
  -- Compara con la versión anterior, que es historia: solo para quien trabaja la receta.
  select v.previous_version_id into v_prev from recipes.recipe_versions v
   where v.id = p_version_id and v.deleted_at is null and recipes.can_work_recipe(v.recipe_id);
  if not found then
    return;
  end if;
  return query select * from recipes.compare_versions(p_version_id, v_prev);
end
$$;

-- Una variante contra la vigente de su maestra (se muestran siempre, para quien trabaja la variante).
create function recipes.variant_diff(p_variant_id uuid)
returns table (change text, ingredient text, unit text, basis recipes.quantity_basis, old_quantity numeric,
               new_quantity numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_mine   uuid;
  v_master uuid;
begin
  -- Quien trabaja la variante y también ve la maestra: la fórmula de la maestra no se abre a quien ya no
  -- la ve (revisión de seguridad, M3).
  if not recipes.can_work_recipe(p_variant_id)
     or not exists (select 1 from recipes.recipes r
                     where r.id = p_variant_id
                       and (recipes.can_view_recipe(r.variant_of_recipe_id) or recipes.can_work_recipe(r.variant_of_recipe_id))) then
    return;
  end if;
  select v.id into v_mine from recipes.recipe_versions v
   where v.recipe_id = p_variant_id and v.status in ('draft', 'in_review', 'published')
   order by (v.status <> 'published') desc limit 1;
  select mv.id into v_master
    from recipes.recipes r
    join recipes.recipe_versions mv on mv.recipe_id = r.variant_of_recipe_id and mv.status = 'published'
   where r.id = p_variant_id;
  if v_mine is null or v_master is null then
    return;
  end if;
  return query select * from recipes.compare_versions(v_mine, v_master);
end
$$;
comment on function recipes.variant_diff(uuid) is
  'Diferencias de una variante (su versión abierta o la vigente) contra la vigente de su maestra. Solo para quien trabaja la variante y ve la maestra.';

-- ---------------------------------------------------------------------------
-- 9. Copiar el contenido de una versión (versión nueva y variante)
-- ---------------------------------------------------------------------------
create function recipes.copy_version_content(p_from uuid, p_to uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_to recipes.recipe_versions;
begin
  select * into v_to from recipes.recipe_versions where id = p_to;
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, sub_recipe_id, quantity,
                                         unit_id, quantity_basis, yield_profile_id, no_scale, notes)
  select v_to.group_id, p_to, line_order, ingredient_id, sub_recipe_id, quantity, unit_id, quantity_basis, yield_profile_id,
         no_scale, notes
    from recipes.recipe_components where recipe_version_id = p_from and deleted_at is null;
  insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                    passive_minutes, workers, sector, equipment, control_point)
  select v_to.group_id, p_to, step_number, kind, instructions, active_minutes, passive_minutes, workers, sector, equipment,
         control_point
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
comment on function recipes.copy_version_content(uuid, uuid) is
  'Interna: copia líneas, pasos, dependencias y fotos de una versión a un borrador nuevo.';
revoke execute on function recipes.copy_version_content(uuid, uuid) from public;

create or replace function recipes.new_version(p_recipe_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r      recipes.recipes;
  v_base   recipes.recipe_versions;
  v_id     uuid;
  v_open   uuid;
begin
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

-- Una preparación que otra receta usa (en su vigente o en preparación) no se archiva: primero hay que
-- sacarla de esas recetas. El for update choca con el for share de set_components.
create or replace function recipes.archive_recipe(p_recipe_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r     recipes.recipes;
  v_users text;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.archive', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.archive_recipe', 'No tenés permiso para archivar esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if exists (select 1 from recipes.recipe_versions where recipe_id = p_recipe_id and status = 'in_review'
               and approval_request_id in (select id from workflow.approval_requests where status = 'pending')) then
    raise exception 'Tiene una versión en revisión: que se decida o se retire antes de archivar.' using errcode = '23514';
  end if;
  select string_agg(distinct p.name, ', ') into v_users
    from recipes.recipe_components c
    join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status in ('published', 'draft', 'in_review')
    join recipes.recipes p on p.id = v.recipe_id and p.is_active and p.deleted_at is null
   where c.sub_recipe_id = p_recipe_id and c.deleted_at is null and p.id <> p_recipe_id;
  if v_users is not null then
    raise exception 'La usan otras recetas (%): sacala de ellas antes de archivarla.', left(v_users, 300)
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipes set is_active = false where id = p_recipe_id;
  update recipes.recipe_versions set status = 'archived' where recipe_id = p_recipe_id and status = 'published';
  update recipes.recipe_assignments set valid_to = greatest(valid_from, recipes.today())
   where recipe_id = p_recipe_id and valid_to is null and deleted_at is null;
  return jsonb_build_object('result', 'applied', 'message', 'Receta archivada. Su historia se conserva.');
end
$$;
comment on function recipes.archive_recipe(uuid, text) is
  'Archiva una receta: su vigente pasa a archivada y deja de estar asignada. No se archiva si tiene una revisión pendiente o si otra receta la usa como preparación. Pide recipes.archive y un motivo.';
comment on function recipes.new_version(uuid, text) is
  'Crea la versión siguiente en borrador a partir de la vigente (o de la última), con sus líneas, pasos, dependencias y fotos. La vigente sigue hasta que se publique la nueva. Pide recipes.draft y un motivo.';

-- Un local que ya usa una variante publicada no vuelve a usar la maestra al mismo tiempo (revisión de
-- base, M4): primero se archiva la variante. El for update choca con el for share de la publicación.
create or replace function recipes.set_assignment(p_recipe_id uuid, p_restaurant_id uuid, p_assigned boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r     recipes.recipes;
  v_rest  org.restaurants;
  v_open  uuid;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  select * into v_rest from org.restaurants where id = p_restaurant_id and deleted_at is null;
  if v_r.id is null or v_rest.id is null or not core.has_permission('recipes.assign', p_restaurant_id)
     or not (recipes.can_view_recipe(v_r.id) or recipes.can_work_recipe(v_r.id)) then
    return core.deny('recipes.set_assignment', 'No tenés permiso para asignar recetas en ese local.', null,
                     jsonb_build_object('recipe_id', p_recipe_id, 'restaurant_id', p_restaurant_id),
                     coalesce(v_r.group_id, v_rest.group_id), v_rest.brand_id, p_restaurant_id);
  end if;
  -- El local tiene que estar dentro del alcance de la receta.
  if v_rest.group_id <> v_r.group_id
     or (v_r.scope_type = 'brand' and v_rest.brand_id <> v_r.brand_id)
     or (v_r.scope_type = 'restaurant' and v_rest.id <> v_r.restaurant_id) then
    raise exception 'Esa receta no se puede usar en ese local: está fuera de su alcance.' using errcode = '23514';
  end if;
  if not v_r.is_active and coalesce(p_assigned, true) then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  if coalesce(p_assigned, true)
     and exists (select 1 from recipes.recipes x
                  where x.variant_of_recipe_id = p_recipe_id and x.restaurant_id = p_restaurant_id
                    and x.is_active and x.deleted_at is null
                    and exists (select 1 from recipes.recipe_versions xv where xv.recipe_id = x.id and xv.status = 'published')) then
    raise exception 'Ese local usa una variante de esta receta: archivala antes de volver a la maestra.' using errcode = '23514';
  end if;
  select id into v_open from recipes.recipe_assignments
   where recipe_id = p_recipe_id and restaurant_id = p_restaurant_id and valid_to is null and deleted_at is null;
  perform core.set_change_context(p_reason, 'manual');
  if coalesce(p_assigned, true) then
    if v_open is not null then
      return jsonb_build_object('result', 'applied', 'message', 'Ya estaba asignada a ese local.');
    end if;
    insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
    values (v_r.group_id, p_recipe_id, p_restaurant_id, recipes.today());
    return jsonb_build_object('result', 'applied', 'message', 'Receta asignada al local.');
  end if;
  if v_open is null then
    return jsonb_build_object('result', 'applied', 'message', 'No estaba asignada a ese local.');
  end if;
  update recipes.recipe_assignments set valid_to = greatest(valid_from, recipes.today()) where id = v_open;
  return jsonb_build_object('result', 'applied', 'message', 'El local deja de usar la receta.');
end
$$;
comment on function recipes.set_assignment(uuid, uuid, boolean, text) is
  'Asigna una receta a un local (o deja de asignarla), dentro del alcance de la receta. Una maestra no se asigna a un local que usa una variante suya publicada. Pide recipes.assign en ese local y un motivo.';

-- ---------------------------------------------------------------------------
-- 10. Variantes locales
-- ---------------------------------------------------------------------------
create function recipes.create_variant(p_master_id uuid, p_restaurant_id uuid, p_code text, p_name text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m          recipes.recipes;
  v_mv         recipes.recipe_versions;
  v_rest       org.restaurants;
  v_recipe     uuid;
  v_version    uuid;
  v_constraint text;
  v_message    text;
begin
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
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipes (group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id,
                               sector, station, variant_of_recipe_id)
  values (v_m.group_id, v_rest.brand_id, v_rest.id, 'restaurant', upper(btrim(p_code)), btrim(p_name), v_m.recipe_type,
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
  return jsonb_build_object('result', 'applied', 'id', v_recipe, 'version_id', v_version,
                            'message', 'Variante creada en borrador. Cuando se publique, el local deja de usar la maestra.');
exception when unique_violation or check_violation or not_null_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'recipes_variant_key' then
    raise exception 'Ese local ya tiene una variante de esta receta.' using errcode = '23505';
  elsif v_constraint is null and sqlstate = '23502' then
    raise exception 'Faltan el código o el nombre.' using errcode = '22023';
  elsif v_constraint is null then
    raise;
  end if;
  perform recipes.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function recipes.create_variant(uuid, uuid, text, text, text) is
  'Crea una variante local de una receta maestra (del grupo o de una marca): copia su vigente en un borrador y la asigna al local. Pide recipes.approve en ese local y un motivo; sin permiso devuelve denied y queda registrado.';

-- ---------------------------------------------------------------------------
-- 11. Lectura: dónde se usa una receta y buscador de preparaciones
-- ---------------------------------------------------------------------------
create function recipes.recipe_usage(p_recipe_id uuid)
returns table (recipe_id uuid, code text, name text, version_number integer, status core.version_status)
language sql
stable
security invoker
set search_path = ''
as $$
  select distinct on (r.id) r.id, r.code, r.name, v.version_number, v.status
    from recipes.recipe_components c
    join recipes.recipe_versions v on v.id = c.recipe_version_id and v.status in ('published', 'draft', 'in_review')
    join recipes.recipes r on r.id = v.recipe_id
   where c.sub_recipe_id = p_recipe_id and c.deleted_at is null
   order by r.id, (v.status = 'published') desc, v.version_number desc
$$;
comment on function recipes.recipe_usage(uuid) is
  'Recetas (vigentes o en preparación) que usan una receta como preparación, entre las que ve la sesión.';

create function recipes.search_subrecipes(p_query text, p_recipe_id uuid, p_limit integer default 12)
returns table (id uuid, code text, name text, unit text)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.id, r.code, r.name, u.code
    from recipes.recipes p
    join recipes.recipes r on r.group_id = p.group_id and r.id <> p.id and r.is_active and r.deleted_at is null
    join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published'
    join catalog.units u on u.id = v.yield_unit_id
   where p.id = p_recipe_id and length(btrim(p_query)) >= 3
     -- El texto se busca tal cual: % y _ no son comodines.
     and (r.name ilike '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
          or r.code ilike replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%')
     -- Al alcance del plato (la misma regla que recipes.sub_in_scope).
     and case r.scope_type when 'group' then true
                           when 'brand' then p.brand_id = r.brand_id
                           else p.restaurant_id = r.restaurant_id end
   order by r.name
   limit greatest(1, least(coalesce(p_limit, 12), 50))
$$;
comment on function recipes.search_subrecipes(text, uuid, integer) is
  'Buscador de preparaciones para usar en una receta: desde 3 letras, con versión vigente, al alcance de la receta y que no sea ella misma. Respeta RLS.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'recipes.create_variant(uuid, uuid, text, text, text)',
    'recipes.variant_diff(uuid)',
    'recipes.recipe_usage(uuid)',
    'recipes.search_subrecipes(text, uuid, integer)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
