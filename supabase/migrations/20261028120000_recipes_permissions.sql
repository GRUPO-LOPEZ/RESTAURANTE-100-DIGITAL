-- Fase 2 · Etapa 2.1 A (docs/fases/fase-2-plan.md, ADR-0020):
--   1. Tipo de establecimiento (sección 3 del documento de Soy): restaurante, cocina central o
--      unidad productiva (Pariggi). Mismos permisos, costos y auditoría que un restaurante.
--   2. Los 19 permisos del recetario (sección 17) y su reparto por rol. Quien administra personas
--      recibe además los permisos de los roles que administra, como en la Fase 1: nadie da un rol
--      ni suspende a alguien con permisos que él no tiene (decisión de Joaco del 2026-10-28).
--   3. N1: los costos se ven con recipes.view_costs (costing.view_costs nunca existió), en
--      can_see_costs y en el historial.
--   4. core.visible_group_ids: el catálogo es de todo el grupo; lo lee quien tenga el permiso en
--      cualquier nivel del grupo. Solo para lectura.

-- ---------------------------------------------------------------------------
-- 1. Tipo de establecimiento
-- ---------------------------------------------------------------------------
create type org.site_type as enum ('restaurant', 'central_kitchen', 'production_unit');
comment on type org.site_type is
  'Tipo de establecimiento: restaurant (restaurante), central_kitchen (cocina central) o production_unit (unidad productiva, como Pariggi).';

alter table org.restaurants add column site_type org.site_type not null default 'restaurant';
comment on column org.restaurants.site_type is
  'Tipo de establecimiento: restaurante, cocina central o unidad productiva. Todos usan los mismos permisos, costos y auditoría.';

-- update_restaurant: igual que la versión de 20261021180100, más el tipo. Cambiar el tipo pide
-- el permiso en la marca, como abrir o cerrar el local.
create or replace function org.update_restaurant(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_brand uuid;
begin
  select brand_id into v_brand from org.restaurants where id = p_id;
  perform org.require(core.has_permission('org.manage', p_id), 'editar este local');
  perform org.check_keys(p_changes, array['name', 'status', 'code', 'address', 'locality', 'legal_name', 'tax_id', 'phone',
                                          'opened_on', 'time_zone', 'site_type']);
  if p_changes ? 'status' then
    perform org.require(core.has_permission_in_brand('org.manage', v_brand), 'abrir o cerrar este local');
  end if;
  if p_changes ? 'site_type' then
    perform org.require(core.has_permission_in_brand('org.manage', v_brand), 'cambiar el tipo de este local');
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Para los datos opcionales, una clave presente con texto vacío o null los borra.
  update org.restaurants
     set name       = coalesce(btrim(p_changes ->> 'name'), name),
         status     = coalesce((p_changes ->> 'status')::org.unit_status, status),
         code       = case when p_changes ? 'code' then upper(nullif(btrim(p_changes ->> 'code'), '')) else code end,
         address    = case when p_changes ? 'address' then nullif(btrim(p_changes ->> 'address'), '') else address end,
         locality   = case when p_changes ? 'locality' then nullif(btrim(p_changes ->> 'locality'), '') else locality end,
         legal_name = case when p_changes ? 'legal_name' then nullif(btrim(p_changes ->> 'legal_name'), '') else legal_name end,
         tax_id     = case when p_changes ? 'tax_id' then nullif(btrim(p_changes ->> 'tax_id'), '') else tax_id end,
         phone      = case when p_changes ? 'phone' then nullif(btrim(p_changes ->> 'phone'), '') else phone end,
         opened_on  = case when p_changes ? 'opened_on' then (nullif(p_changes ->> 'opened_on', ''))::date else opened_on end,
         time_zone  = case when p_changes ? 'time_zone'
                           then coalesce(nullif(btrim(p_changes ->> 'time_zone'), ''), 'America/Argentina/Buenos_Aires')
                           else time_zone end,
         site_type  = coalesce((p_changes ->> 'site_type')::org.site_type, site_type)
   where id = p_id;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Permisos del recetario y su reparto
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos del recetario (Fase 2, sección 17)', 'maintenance');

  insert into core.permissions (code, module, action, description, is_sensitive) values
    ('catalog.view',       'catalog',   'view',       'Ver materias primas, productos de compra, proveedores y alérgenos.', false),
    ('catalog.manage',     'catalog',   'manage',     'Crear y editar materias primas, productos de compra, proveedores, conversiones y alérgenos.', false),
    ('prices.view',        'prices',    'view',       'Ver los precios de compra y su historial.', true),
    ('prices.propose',     'prices',    'propose',    'Cargar precios nuevos como propuesta, para que otra persona los apruebe.', true),
    ('prices.approve',     'prices',    'approve',    'Aprobar o rechazar precios propuestos por otra persona.', true),
    ('yields.record',      'yields',    'record',     'Registrar ensayos de rendimiento y proponer cambios al estándar.', false),
    ('yields.approve',     'yields',    'approve',    'Aprobar el rendimiento estándar que usa el motor de costos.', false),
    ('recipes.view',       'recipes',   'view',       'Ver las recetas vigentes (sin costos).', false),
    ('recipes.view_costs', 'recipes',   'view_costs', 'Ver costos y precios de recetas e ingredientes, también en el historial.', true),
    ('recipes.draft',      'recipes',   'draft',      'Crear y editar borradores de recetas y pedir su revisión.', false),
    ('recipes.review',     'recipes',   'review',     'Revisar versiones de recetas y comentar.', false),
    ('recipes.approve',    'recipes',   'approve',    'Aprobar versiones de recetas pedidas por otra persona.', false),
    ('recipes.publish',    'recipes',   'publish',    'Publicar versiones aprobadas de recetas.', false),
    ('recipes.archive',    'recipes',   'archive',    'Archivar recetas y versiones.', false),
    ('recipes.assign',     'recipes',   'assign',     'Asignar recetas a establecimientos.', false),
    ('scenarios.manage',   'scenarios', 'manage',     'Crear y usar escenarios de costo simulados (nunca tocan los oficiales).', true),
    ('imports.run',        'imports',   'run',        'Subir archivos de Excel y preparar importaciones.', false),
    ('imports.approve',    'imports',   'approve',    'Confirmar importaciones revisadas.', false),
    ('reports.export',     'reports',   'export',     'Exportar reportes del recetario a PDF, Excel y CSV.', true);

  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
  from (values
    -- Configuración técnica. Además, los permisos de quienes puede suspender o desactivar
    -- (Gerente, Jefe de Cocina, Cocinero, Compras y Auditor), como en la Fase 1 (G2).
    ('superadmin', 'catalog.view'), ('superadmin', 'catalog.manage'), ('superadmin', 'prices.view'),
    ('superadmin', 'prices.propose'), ('superadmin', 'imports.run'), ('superadmin', 'recipes.view'),
    ('superadmin', 'recipes.view_costs'), ('superadmin', 'recipes.draft'), ('superadmin', 'recipes.review'),
    ('superadmin', 'yields.record'), ('superadmin', 'reports.export'),
    -- Ver todo con costos, aprobar cambios críticos, exportar.
    ('general_management', 'catalog.view'), ('general_management', 'prices.view'),
    ('general_management', 'prices.approve'), ('general_management', 'recipes.view'),
    ('general_management', 'recipes.view_costs'), ('general_management', 'recipes.approve'),
    ('general_management', 'recipes.publish'), ('general_management', 'recipes.archive'),
    ('general_management', 'recipes.assign'), ('general_management', 'scenarios.manage'),
    ('general_management', 'imports.approve'), ('general_management', 'reports.export'),
    -- Su marca, con costos; además, lo del Chef y el Gerente, que asigna y administra.
    ('brand_director', 'catalog.view'), ('brand_director', 'prices.view'), ('brand_director', 'recipes.view'),
    ('brand_director', 'recipes.view_costs'), ('brand_director', 'recipes.draft'), ('brand_director', 'recipes.review'),
    ('brand_director', 'recipes.approve'), ('brand_director', 'recipes.publish'), ('brand_director', 'recipes.archive'),
    ('brand_director', 'recipes.assign'), ('brand_director', 'yields.record'), ('brand_director', 'yields.approve'),
    ('brand_director', 'scenarios.manage'), ('brand_director', 'imports.run'), ('brand_director', 'imports.approve'),
    ('brand_director', 'reports.export'),
    -- Su local y lo del Jefe de Cocina, que asigna. SIN costos ni precios hasta que Soy responda
    -- la pregunta N2 (denegar por defecto; revisión de seguridad de la etapa 2.1 A).
    ('restaurant_manager', 'catalog.view'), ('restaurant_manager', 'recipes.view'),
    ('restaurant_manager', 'recipes.draft'), ('restaurant_manager', 'recipes.review'),
    ('restaurant_manager', 'yields.record'), ('restaurant_manager', 'reports.export'),
    -- Borrador, revisión, aprobación, publicación, asignación y rendimientos. Nunca precios.
    ('executive_chef', 'catalog.view'), ('executive_chef', 'yields.record'), ('executive_chef', 'yields.approve'),
    ('executive_chef', 'recipes.view'), ('executive_chef', 'recipes.view_costs'), ('executive_chef', 'recipes.draft'),
    ('executive_chef', 'recipes.review'), ('executive_chef', 'recipes.approve'), ('executive_chef', 'recipes.publish'),
    ('executive_chef', 'recipes.archive'), ('executive_chef', 'recipes.assign'), ('executive_chef', 'imports.run'),
    ('executive_chef', 'imports.approve'), ('executive_chef', 'reports.export'),
    -- Borradores, pedir revisión y ensayos de su local. Sin costos.
    ('head_chef', 'catalog.view'), ('head_chef', 'yields.record'), ('head_chef', 'recipes.view'),
    ('head_chef', 'recipes.draft'), ('head_chef', 'recipes.review'),
    -- Costos, aprobar precios, escenarios y reportes. Nunca gramajes ni procedimientos.
    ('controller', 'catalog.view'), ('controller', 'prices.view'), ('controller', 'prices.approve'),
    ('controller', 'recipes.view'), ('controller', 'recipes.view_costs'), ('controller', 'scenarios.manage'),
    ('controller', 'imports.approve'), ('controller', 'reports.export'),
    -- Catálogo, productos de compra, proponer precios e importar. Nunca aprobar sus propios precios.
    ('purchasing', 'catalog.view'), ('purchasing', 'catalog.manage'), ('purchasing', 'prices.view'),
    ('purchasing', 'prices.propose'), ('purchasing', 'recipes.view'), ('purchasing', 'imports.run'),
    -- Solo la vista de cocina de su local: sin precios ni costos.
    ('cook', 'recipes.view'),
    -- Leer historial y reportes. Nunca crear, editar ni aprobar.
    ('auditor', 'catalog.view'), ('auditor', 'prices.view'), ('auditor', 'recipes.view'),
    ('auditor', 'recipes.view_costs'), ('auditor', 'reports.export')
  ) as m (role_code, permission_code)
  join core.roles r on r.code = m.role_code
  join core.permissions p on p.code = m.permission_code;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. N1: el historial muestra costos con recipes.view_costs
-- ---------------------------------------------------------------------------
create or replace function core.can_see_costs(p_group_id uuid, p_brand_id uuid, p_restaurant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return case
    when p_restaurant_id is not null then core.has_permission('recipes.view_costs', p_restaurant_id)
    when p_brand_id is not null then core.has_permission_in_brand('recipes.view_costs', p_brand_id)
    when p_group_id is not null then core.has_permission_in_group('recipes.view_costs', p_group_id)
    else false
  end;
end
$$;
comment on function core.can_see_costs(uuid, uuid, uuid) is
  'Interna. Si la sesión puede ver costos en ese alcance (recipes.view_costs, ADR-0020).';

-- El historial arma sus conjuntos de costos una vez por consulta (por rendimiento), con la misma
-- regla de alcance que can_see_costs. Igual que la versión de 20261023120000, con recipes.view_costs
-- (revisión de seguridad de la etapa 2.1 A: había quedado con el permiso que nunca existió).
create or replace function core.audit_history(
  p_limit         integer default 50,
  p_before        bigint default null,
  p_record_id     uuid default null,
  p_from          timestamptz default null,
  p_to            timestamptz default null,
  p_actor_id      uuid default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null,
  p_critical_only boolean default false
)
returns table (sequence_number bigint, occurred_at timestamptz, actor_name text, actor_role_code text, action text,
               module text, table_schema text, table_name text, record_id uuid, changed_fields text[],
               old_values jsonb, new_values jsonb, reason text, source text, place_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit  int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_bounds record;
  v_rids   uuid[];
  v_bids   uuid[];
  v_gids   uuid[];
  v_cost_rids uuid[];
  v_cost_bids uuid[];
  v_cost_gids uuid[];
begin
  if not core.current_session_ok() then
    return;
  end if;
  if p_module is not null and (length(p_module) > 60 or p_module !~ '^[a-z_]+$') then
    raise exception 'Módulo inválido.' using errcode = '22023';
  end if;
  v_bounds := core.audit_sequence_bounds(p_from, p_to);
  -- El alcance pedido, dentro de lo que la sesión puede ver: un local, una marca (sus locales y la
  -- marca) o todo lo visible.
  v_rids := array(select r.id from org.restaurants r
                   where r.id in (select core.permitted_restaurant_ids('audit.view'))
                     and (p_restaurant_id is null or r.id = p_restaurant_id)
                     and (p_brand_id is null or r.brand_id = p_brand_id));
  v_bids := case when p_restaurant_id is null then
              array(select b from core.permitted_brand_ids('audit.view') b where p_brand_id is null or b = p_brand_id)
            else '{}' end;
  v_gids := case when p_restaurant_id is null and p_brand_id is null then array(select core.permitted_group_ids('audit.view'))
            else '{}' end;

  v_cost_rids := array(select core.permitted_restaurant_ids('recipes.view_costs'));
  v_cost_bids := array(select core.permitted_brand_ids('recipes.view_costs'));
  v_cost_gids := array(select core.permitted_group_ids('recipes.view_costs'));

  return query
  select e.sequence_number, e.occurred_at,
         coalesce(core.display_name(coalesce(e.actor_user_id, e.actor_service_account_id)),
                  case when e.source is not null then 'Sistema (' || e.source::text || ')' else 'Sistema' end),
         e.actor_role_code, e.action::text, e.module, e.table_schema, e.table_name, e.record_id, e.changed_fields,
         case when (e.scope_restaurant_id is not null and e.scope_restaurant_id = any (v_cost_rids))
                or (e.scope_restaurant_id is null and e.scope_brand_id is not null and e.scope_brand_id = any (v_cost_bids))
                or (e.scope_brand_id is null and e.scope_group_id is not null and e.scope_group_id = any (v_cost_gids))
              then e.old_values else core.hide_costs(e.old_values) end,
         case when (e.scope_restaurant_id is not null and e.scope_restaurant_id = any (v_cost_rids))
                or (e.scope_restaurant_id is null and e.scope_brand_id is not null and e.scope_brand_id = any (v_cost_bids))
                or (e.scope_brand_id is null and e.scope_group_id is not null and e.scope_group_id = any (v_cost_gids))
              then e.new_values else core.hide_costs(e.new_values) end,
         e.reason, e.source::text,
         coalesce((select r.name from org.restaurants r where r.id = e.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = e.scope_brand_id),
                  (select g.name from org.groups g where g.id = e.scope_group_id))
    from core.audit_scope_events(v_rids, v_bids, v_gids, v_limit, least(coalesce(p_before, 9223372036854775807), v_bounds.before_seq),
                                 v_bounds.after_seq, p_record_id, p_from, p_to, p_actor_id, p_module,
                                 case when p_critical_only then array['user_role_assignments', 'role_permissions', 'user_profiles',
                                   'roles', 'permissions', 'approval_decisions', 'approval_workflows'] end) e
   order by e.sequence_number desc;
end
$$;
comment on function core.audit_history(integer, bigint, uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, boolean) is
  'Historial de cambios que la sesión puede ver (audit.view por alcance), del más nuevo al más viejo, con quién, cuándo, qué y por qué. Lee por índice cada alcance visible. Oculta costos y precios sin recipes.view_costs (ADR-0020).';

-- ---------------------------------------------------------------------------
-- 4. Grupos visibles, para leer lo que es de todo el grupo (catálogo)
-- ---------------------------------------------------------------------------
create function core.visible_group_ids(p_permission text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select distinct g.group_id from core.actor_grants(p_permission) g;
end
$$;
comment on function core.visible_group_ids(text) is
  'Solo para lectura: grupos donde la sesión tiene el permiso en cualquier nivel (grupo, marca o local). Lo usan las políticas de lo que es de todo el grupo, como el catálogo. Nunca para autorizar un cambio.';
revoke execute on function core.visible_group_ids(text) from public;
grant execute on function core.visible_group_ids(text) to authenticated;
