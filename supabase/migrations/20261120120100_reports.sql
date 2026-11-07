-- Fase 2 · Etapa 2.5: reportes (ADR-0034; sección 18 del documento de Soy), parte 2. Cada reporte pide reports.export y el
-- permiso de su dato en el local. Solo leen; lo que se exporta queda en el registro de seguridad.
-- Un reporte lleva nombres: a diferencia de la calidad de datos, solo trae lo que la sesión puede ver.

-- Qué reportes puede sacar la sesión en un local.
create function costing.report_list(p_restaurant_id uuid)
returns setof text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_catalog boolean := core.has_permission('catalog.view', p_restaurant_id);
  v_recipes boolean := core.has_permission('recipes.view', p_restaurant_id);
begin
  if not core.has_permission('reports.export', p_restaurant_id) then
    return;
  end if;
  if v_catalog and core.has_permission('prices.view', p_restaurant_id) then
    return next 'ingredients';
  end if;
  if v_catalog then
    return next 'yields';
  end if;
  if v_recipes then
    return next 'usage';
  end if;
  if v_recipes and core.has_permission('recipes.view_costs', p_restaurant_id) then
    return next 'cost_changes';
  end if;
  if costing.quality_allowed(p_restaurant_id) then
    return next 'quality';
  end if;
end
$$;
comment on function costing.report_list(uuid) is 'Los reportes que la sesión puede sacar en un local.';

-- Interna: frena si la sesión no puede sacar ese reporte en ese local.
create function costing.require_report(p_report text, p_restaurant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(p_report in (select costing.report_list(p_restaurant_id)), 'sacar este reporte');
end
$$;
comment on function costing.require_report(text, uuid) is 'Interna: frena si la sesión no puede sacar ese reporte en ese local.';
revoke execute on function costing.require_report(text, uuid) from public;

-- Los locales donde se sacan reportes.
create function costing.report_places()
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.name
    from org.restaurants r
   where r.deleted_at is null and r.status = 'active' and r.id in (select core.permitted_restaurant_ids('reports.export'))
   order by r.name, r.id
$$;
comment on function costing.report_places() is 'Los locales donde la sesión saca reportes.';

-- Materias primas: nombre, categoría, unidad y precio normalizado del local.
create function costing.report_ingredients(p_restaurant_id uuid, p_limit integer default 50, p_offset integer default 0)
returns table (item_id uuid, name text, category text, unit text, unit_cost numeric, valid_from date, stale boolean, status text, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform costing.require_report('ingredients', p_restaurant_id);
  return query
    select i.id, i.name, c.name, u.name, p.unit_cost, p.valid_from, p.stale, p.status, count(*) over ()
      from org.restaurants r
      join catalog.ingredients i on i.group_id = r.group_id and i.deleted_at is null and i.is_active
      join catalog.ingredient_categories c on c.id = i.category_id
      join catalog.units u on u.id = i.recipe_unit_id
      left join costing.price_rows(p_restaurant_id, recipes.today(), null) p on p.ingredient_id = i.id
     where r.id = p_restaurant_id
     order by i.name, i.id
     limit least(greatest(coalesce(p_limit, 50), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.report_ingredients(uuid, integer, integer) is 'Reporte de materias primas de un local, con su precio normalizado y su fecha.';

-- Rendimientos aprobados del grupo del local.
create function costing.report_yields(p_restaurant_id uuid, p_limit integer default 50, p_offset integer default 0)
returns table (item_id uuid, ingredient text, process text, cut text, supplier text, cleaning_yield numeric, waste numeric, cooking_factor numeric,
               approved_at timestamptz, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform costing.require_report('yields', p_restaurant_id);
  return query
    select i.id, i.name, x.name, y.cut, s.name, y.cleaning_yield, 1 - y.cleaning_yield, y.cooking_factor, y.approved_at, count(*) over ()
      from org.restaurants r
      join catalog.ingredient_yield_profiles y on y.group_id = r.group_id and y.deleted_at is null and y.status = 'approved'
      join catalog.ingredients i on i.id = y.ingredient_id and i.deleted_at is null and i.is_active
      join catalog.yield_processes x on x.id = y.process_id
      left join catalog.suppliers s on s.id = y.supplier_id
     where r.id = p_restaurant_id
     order by i.name, x.name, y.id
     limit least(greatest(coalesce(p_limit, 50), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.report_yields(uuid, integer, integer) is 'Reporte de rendimientos aprobados del grupo de un local.';

-- Dónde se usa: cada materia prima o preparación, con todas las recetas vigentes del local que la usan, también a través de
-- otra preparación. Una preparación se resuelve como la usa el local: con su variante, si tiene una publicada.
create function costing.report_usage(p_restaurant_id uuid, p_limit integer default 50, p_offset integer default 0)
returns table (item_id uuid, kind text, component text, recipe_id uuid, recipe text, version_number integer, quantity numeric, unit text,
               through text, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seen uuid[];
begin
  perform costing.require_report('usage', p_restaurant_id);
  v_seen := array(select costing.visible_recipe_ids());
  return query
    with recursive roots as (
      select r.id as recipe_id, r.name as recipe, v.id as version_id, v.version_number
        from recipes.recipes r
        join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published'
       where r.deleted_at is null and r.id = any (v_seen) and r.id in (select costing.restaurant_recipes(p_restaurant_id))
    ), lines as (
      -- La línea con la preparación ya resuelta a la del local.
      select c.id, c.recipe_version_id, c.line_order, c.ingredient_id, c.quantity, c.unit_id,
             coalesce((select var.id
                         from recipes.recipes var
                         join recipes.recipe_versions vv on vv.recipe_id = var.id and vv.status = 'published'
                        where var.variant_of_recipe_id = c.sub_recipe_id and var.restaurant_id = p_restaurant_id
                          and var.is_active and var.deleted_at is null
                        limit 1), c.sub_recipe_id) as sub_id
        from recipes.recipe_components c
       where c.deleted_at is null
    ), walk (recipe_id, recipe, root_version, version_id, through, depth) as (
      select o.recipe_id, o.recipe, o.version_number, o.version_id, null::text, 0
        from roots o
      union all
      select w.recipe_id, w.recipe, w.root_version, v.id, s.name, w.depth + 1
        from walk w
        join lines l on l.recipe_version_id = w.version_id and l.sub_id is not null
        join recipes.recipes s on s.id = l.sub_id
        join recipes.recipe_versions v on v.recipe_id = s.id and v.status = 'published'
       where w.depth < 10
    )
    select coalesce(l.ingredient_id, l.sub_id), case when l.ingredient_id is not null then 'ingredient' else 'recipe' end,
           coalesce(i.name, s.name), w.recipe_id, w.recipe, w.root_version,
           case when w.through is null then l.quantity end, case when w.through is null then u.name end, w.through, count(*) over ()
      from walk w
      join lines l on l.recipe_version_id = w.version_id
      join catalog.units u on u.id = l.unit_id
      left join catalog.ingredients i on i.id = l.ingredient_id
      left join recipes.recipes s on s.id = l.sub_id
     order by 3, 5, 9 nulls first, w.recipe_id, l.line_order, l.id
     limit least(greatest(coalesce(p_limit, 50), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.report_usage(uuid, integer, integer) is
  'Reporte de dónde se usa cada materia prima o preparación en las recetas vigentes de un local, también a través de otra preparación.';

-- Cambios de costo en un período: lo que pasó en el local, aunque la receta ya no esté vigente. Cada foto contra la anterior:
-- si cambió la versión, el motivo es la receta y no un precio. Una receta que recién tiene costo aparece sin diferencia.
create function costing.report_cost_changes(p_restaurant_id uuid, p_from date, p_to date, p_limit integer default 50, p_offset integer default 0)
returns table (recipe_id uuid, recipe text, recipe_type text, version_number integer, changed_on date, reason text, previous numeric, current_cost numeric,
               difference numeric, difference_pct numeric, in_use boolean, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_used uuid[];
begin
  perform costing.require_report('cost_changes', p_restaurant_id);
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'Elegí un período: la fecha de inicio tiene que ser anterior a la del final.' using errcode = '22023';
  end if;
  v_used := array(select costing.restaurant_recipes(p_restaurant_id));
  return query
    select s.recipe_id, r.name, r.recipe_type::text, v.version_number, (s.created_at at time zone 'America/Argentina/Buenos_Aires')::date,
           case when p.recipe_version_id <> s.recipe_version_id then 'recipe_changed' else s.reason::text end,
           p.total_cost, s.total_cost, s.total_cost - p.total_cost,
           case when p.total_cost > 0 then round((s.total_cost - p.total_cost) / p.total_cost * 100, 2) end,
           s.recipe_id = any (v_used) and r.is_active and r.deleted_at is null, count(*) over ()
      from costing.recipe_cost_snapshots s
      join recipes.recipes r on r.id = s.recipe_id
      join recipes.recipe_versions v on v.id = s.recipe_version_id
      cross join lateral (select y.total_cost, y.recipe_version_id
                            from costing.recipe_cost_snapshots y
                           where y.recipe_id = s.recipe_id and y.restaurant_id = s.restaurant_id and y.entry_number < s.entry_number
                           order by y.entry_number desc
                           limit 1) p
     where s.restaurant_id = p_restaurant_id
       and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
       and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
       and s.total_cost is distinct from p.total_cost
     order by s.entry_number desc
     limit least(greatest(coalesce(p_limit, 50), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.report_cost_changes(uuid, date, date, integer, integer) is
  'Reporte de los cambios de costo de un local en un período, también de recetas que ya no están vigentes.';

-- Calidad de datos: lo que falta corregir, con los nombres que la sesión puede ver.
create function costing.report_quality(p_restaurant_id uuid, p_limit integer default 50, p_offset integer default 0)
returns table (indicator text, kind text, item_id uuid, item text, detail text, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_seen uuid[];
begin
  perform costing.require_report('quality', p_restaurant_id);
  v_seen := array(select costing.visible_recipe_ids());
  return query
    select q.indicator, q.kind, q.item_id, q.item, q.detail, count(*) over ()
      from costing.quality_items(p_restaurant_id) q
     where not q.ok and q.indicator in (select costing.quality_indicators(p_restaurant_id))
       and (q.kind <> 'recipe' or q.item_id = any (v_seen))
     order by q.indicator, q.item, q.item_id
     limit least(greatest(coalesce(p_limit, 50), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.report_quality(uuid, integer, integer) is 'Reporte de lo que falta corregir en un local, con los nombres que la sesión puede ver.';

-- Lo que sale por la aplicación queda registrado: quién, qué reporte, de qué local, en qué formato y de qué período. Es trazabilidad:
-- esos datos la persona ya los puede leer por las pantallas de cada módulo.
create function costing.log_report(p_report text, p_restaurant_id uuid, p_format text, p_rows integer default null,
                                   p_from date default null, p_to date default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r org.restaurants;
begin
  perform costing.require_report(p_report, p_restaurant_id);
  if p_format is null or p_format not in ('pdf', 'xlsx', 'csv') then
    raise exception 'Elegí un formato: PDF, Excel o CSV.' using errcode = '22023';
  end if;
  if p_rows < 0 then
    raise exception 'La cantidad de filas no puede ser negativa.' using errcode = '22023';
  end if;
  select * into r from org.restaurants x where x.id = p_restaurant_id;
  perform audit.log_security_event('report_exported', 'costing.log_report', 'Exportación de un reporte', core.current_actor_id(), null,
    jsonb_strip_nulls(jsonb_build_object('report', p_report, 'format', p_format, 'rows', p_rows, 'from', p_from, 'to', p_to)),
    r.group_id, r.brand_id, r.id);
end
$$;
comment on function costing.log_report(text, uuid, text, integer, date, date) is 'Deja en el registro de seguridad que se exportó un reporte.';

-- Quién exportó qué: lo ve quien puede ver el registro de seguridad de ese local.
create function costing.report_exports(p_limit integer default 20)
returns table (occurred_at timestamptz, person text, report text, format text, rows_count integer, restaurant text)
language sql
stable
security definer
set search_path = ''
as $$
  select e.occurred_at, btrim(concat(p.first_name, ' ', p.last_name)), e.detail ->> 'report', e.detail ->> 'format',
         (e.detail ->> 'rows')::integer, r.name
    from audit.authentication_security_events e
    join org.restaurants r on r.id = e.scope_restaurant_id
    left join core.user_profiles p on p.id = e.actor_id
   where e.event_type = 'report_exported'
     and e.scope_restaurant_id in (select core.permitted_restaurant_ids('security.view'))
   order by e.occurred_at desc, e.id
   limit least(greatest(coalesce(p_limit, 20), 1), 100)
$$;
comment on function costing.report_exports(integer) is 'Las últimas exportaciones de reportes de los locales donde la sesión ve el registro de seguridad.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'costing.report_list(uuid)',
    'costing.report_places()',
    'costing.report_ingredients(uuid, integer, integer)',
    'costing.report_yields(uuid, integer, integer)',
    'costing.report_usage(uuid, integer, integer)',
    'costing.report_cost_changes(uuid, date, date, integer, integer)',
    'costing.report_quality(uuid, integer, integer)',
    'costing.log_report(text, uuid, text, integer, date, date)',
    'costing.report_exports(integer)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
