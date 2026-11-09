-- Fase 2 · Etapa 2.5: las fichas por receta (ADR-0034; sección 18 del documento de Soy). Ficha técnica y ficha de costeo se
-- suman a los reportes: mismo permiso, mismo registro de lo que se exporta. Los datos salen de funciones que ya existen
-- (recipes.kitchen_card y costing.recipe_cost_lines), con sus propios controles.

create or replace function costing.report_list(p_restaurant_id uuid)
returns setof text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_catalog boolean := core.has_permission('catalog.view', p_restaurant_id);
  v_recipes boolean := core.has_permission('recipes.view', p_restaurant_id);
  v_costs   boolean := core.has_permission('recipes.view_costs', p_restaurant_id);
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
    return next 'recipe_card';
  end if;
  if v_recipes and v_costs then
    return next 'cost_changes';
    return next 'cost_card';
  end if;
  if costing.quality_allowed(p_restaurant_id) then
    return next 'quality';
  end if;
end
$$;
comment on function costing.report_list(uuid) is 'Los reportes que la sesión puede sacar en un local, también las fichas por receta.';

-- Interna: las recetas vigentes de un local que la sesión ve. Es el mismo criterio de la ficha de cocina
-- (recipes.viewable_recipe_ids, con versión publicada), cortado por las que el local usa.
create function costing.report_recipe_ids(p_restaurant_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select r.id
    from recipes.recipes r
   where r.deleted_at is null and r.is_active
     and r.id in (select recipes.viewable_recipe_ids())
     and r.id in (select costing.restaurant_recipes(p_restaurant_id))
$$;
comment on function costing.report_recipe_ids(uuid) is 'Interna: las recetas vigentes de un local que la sesión ve, de las que se puede sacar una ficha.';
revoke execute on function costing.report_recipe_ids(uuid) from public;

-- Para buscar sin importar mayúsculas ni acentos: "noquis" encuentra "Ñoquis".
create function costing.search_text(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$ select translate(lower(coalesce(p_text, '')), 'áéíóúüñàèìòù', 'aeiouunaeiou') $$;
comment on function costing.search_text(text) is 'Interna: el texto en minúsculas y sin acentos, para buscar.';
revoke execute on function costing.search_text(text) from public;

-- Las recetas vigentes del local que la sesión ve, para elegir de cuál sacar la ficha.
create function costing.report_recipes(p_restaurant_id uuid, p_search text default null, p_limit integer default 50,
                                       p_offset integer default 0)
returns table (recipe_id uuid, code text, name text, recipe_type text, total_rows bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- Una búsqueda larga no suma nada: se corta en 100 caracteres.
  v_search text := costing.search_text(left(btrim(p_search), 100));
begin
  perform costing.require_report('recipe_card', p_restaurant_id);
  return query
    select r.id, r.code, r.name, r.recipe_type::text, count(*) over ()
      from recipes.recipes r
     where r.id in (select costing.report_recipe_ids(p_restaurant_id))
       and (v_search = ''
            or strpos(costing.search_text(r.name), v_search) > 0 or strpos(costing.search_text(r.code), v_search) > 0)
     order by r.name, r.id
     limit least(greatest(coalesce(p_limit, 50), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end
$$;
comment on function costing.report_recipes(uuid, text, integer, integer) is
  'Las recetas vigentes de un local que la sesión ve, para elegir de cuál sacar una ficha. Busca sin acentos.';

-- Una ficha es de una receta del local: la base lo controla antes de armarla y antes de registrarla. Sin esto, la ficha
-- de una receta de otra marca saldría a nombre de este local.
create function costing.require_report_recipe(p_report text, p_restaurant_id uuid, p_recipe_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_report not in ('recipe_card', 'cost_card') then
    raise exception 'Ese reporte no es de una receta.' using errcode = '22023';
  end if;
  perform costing.require_report(p_report, p_restaurant_id);
  perform org.require(p_recipe_id in (select costing.report_recipe_ids(p_restaurant_id)), 'sacar la ficha de esa receta en este local');
end
$$;
comment on function costing.require_report_recipe(text, uuid, uuid) is
  'Corta si la sesión no puede sacar esa ficha, o si la receta no es una vigente del local.';

-- El registro de lo exportado dice también de qué receta es la ficha. Se reemplaza la función: suma la receta al final.
drop function costing.log_report(text, uuid, text, integer, date, date);
create function costing.log_report(p_report text, p_restaurant_id uuid, p_format text, p_rows integer default null,
                                   p_from date default null, p_to date default null, p_recipe_id uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r org.restaurants;
  v_recipe recipes.recipes;
begin
  if p_report in ('recipe_card', 'cost_card') then
    perform costing.require_report_recipe(p_report, p_restaurant_id, p_recipe_id);
    select * into v_recipe from recipes.recipes x where x.id = p_recipe_id;
  else
    perform costing.require_report(p_report, p_restaurant_id);
    if p_recipe_id is not null then
      raise exception 'Ese reporte no es de una receta.' using errcode = '22023';
    end if;
  end if;
  if p_format is null or p_format not in ('pdf', 'xlsx', 'csv') then
    raise exception 'Elegí un formato: PDF, Excel o CSV.' using errcode = '22023';
  end if;
  if p_rows < 0 then
    raise exception 'La cantidad de filas no puede ser negativa.' using errcode = '22023';
  end if;
  select * into r from org.restaurants x where x.id = p_restaurant_id;
  perform audit.log_security_event('report_exported', 'costing.log_report', 'Exportación de un reporte', core.current_actor_id(), null,
    jsonb_strip_nulls(jsonb_build_object('report', p_report, 'format', p_format, 'rows', p_rows, 'from', p_from, 'to', p_to,
                                         'recipe_id', v_recipe.id, 'recipe_code', v_recipe.code)),
    r.group_id, r.brand_id, r.id);
end
$$;
comment on function costing.log_report(text, uuid, text, integer, date, date, uuid) is
  'Deja en el registro de seguridad que se exportó un reporte; si es una ficha, de qué receta.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'costing.report_recipes(uuid, text, integer, integer)',
    'costing.require_report_recipe(text, uuid, uuid)',
    'costing.log_report(text, uuid, text, integer, date, date, uuid)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
