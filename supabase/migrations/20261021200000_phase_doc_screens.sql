-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), paso 3:
-- lecturas de las pantallas de la sección 9.
--   1. audit.v_field_changes: un campo cambiado por fila (sección 6). La usa la exportación.
--   2. core.audit_history con filtros (fecha, persona, marca, local, módulo, registro) y core.audit_export.
--   3. core.users_control_panel: el tablero "¿quién tiene acceso y qué está pasando?".
--   4. core.user_detail: la ficha (último acceso, actividad, intentos rechazados).
--   5. core.users_dashboard con filtros por rol y área.
--   6. core.permission_matrix: la pantalla de roles y permisos.
--   7. Mi cuenta: core.my_account, core.update_my_profile y el registro de contraseña y doble verificación.
--   8. workflow.inbox con el antes y el después.

-- ---------------------------------------------------------------------------
-- 1. Un campo cambiado por fila
-- ---------------------------------------------------------------------------
set role audit_owner;
create index audit_events_module_seq_idx on audit.audit_events (module, sequence_number desc) where module is not null;

create view audit.v_field_changes as
select e.sequence_number, e.id as event_id, e.occurred_at, e.actor_user_id, e.actor_service_account_id, e.actor_role_code,
       e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id, e.module, e.table_schema, e.table_name, e.record_id,
       e.action, e.reason, e.source, e.operation_id, f.field,
       e.old_values -> f.field as old_value, e.new_values -> f.field as new_value
  from audit.audit_events e
  cross join lateral unnest(case
      when e.action in ('insert', 'approve', 'reject') then array(select jsonb_object_keys(e.new_values))
      when e.action = 'delete' then array(select jsonb_object_keys(e.old_values))
      else e.changed_fields end) as f (field)
 -- Las columnas de control no son "cambios" que la gente tenga que leer.
 where f.field not in ('id', 'created_at', 'created_by', 'updated_at', 'updated_by');
comment on view audit.v_field_changes is
  'Cada campo cambiado en una fila: antes, después, quién, cuándo, por qué, módulo y número de operación (sección 6 del documento de Soy). Sin permisos para la API: se lee por core.audit_export, que filtra por alcance.';
revoke all on audit.v_field_changes from public, anon, authenticated, service_role;
-- Como la tabla: postgres (dueño de las funciones que la leen) solo lee.
grant select on audit.v_field_changes to postgres;
do $$
declare
  c record;
begin
  for c in select a.attname from pg_attribute a
            where a.attrelid = 'audit.v_field_changes'::regclass and a.attnum > 0 and not a.attisdropped loop
    execute format('comment on column audit.v_field_changes.%I is %L', c.attname,
      case c.attname
        when 'event_id' then 'Evento de auditoría del que sale la fila.'
        when 'field' then 'Campo que cambió.'
        when 'old_value' then 'Valor anterior del campo (vacío en un alta).'
        when 'new_value' then 'Valor nuevo del campo (vacío en un borrado físico).'
        else (select col_description('audit.audit_events'::regclass, t.attnum)
                from pg_attribute t where t.attrelid = 'audit.audit_events'::regclass and t.attname = c.attname) end);
  end loop;
end
$$;
create index authentication_security_events_group_time_idx on audit.authentication_security_events (scope_group_id, occurred_at);
reset role;

-- ---------------------------------------------------------------------------
-- 2. Historial con filtros y exportación
-- ---------------------------------------------------------------------------
drop function core.audit_history(integer, bigint, uuid);

set role audit_owner;
-- Para el filtro por persona (revisión de base, M2): se lee por su índice y no por alcance.
create index audit_events_actor_seq_idx on audit.audit_events (actor_user_id, sequence_number desc)
  where actor_user_id is not null;
reset role;

-- Los eventos de un alcance, ya filtrados: la base común del historial y de la exportación.
-- Recorre cada local, marca y grupo por su índice, cortado por número de evento (las fechas se
-- convierten antes en números de evento: así el corte entra en el índice y no queda como filtro).
create function core.audit_scope_events(
  p_rids          uuid[],
  p_bids          uuid[],
  p_gids          uuid[],
  p_limit         integer,
  p_before        bigint,
  p_after         bigint,
  p_record_id     uuid,
  p_from          timestamptz,
  p_to            timestamptz,
  p_actor_id      uuid,
  p_module        text,
  p_tables        text[]
)
returns setof audit.audit_events
language sql
stable
security definer
set search_path = ''
as $$
  with events as (
    select e.* from unnest(p_rids) as rid
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and x.scope_restaurant_id = rid
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
           and (p_tables is null or x.table_name = any (p_tables))
         order by x.sequence_number desc limit p_limit) e
    union all
    select e.* from unnest(p_bids) as bid
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and x.scope_restaurant_id is null and x.scope_brand_id = bid
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
           and (p_tables is null or x.table_name = any (p_tables))
         order by x.sequence_number desc limit p_limit) e
    union all
    select e.* from unnest(p_gids) as gid
      cross join lateral (
        select x.* from audit.audit_events x
         where p_actor_id is null and x.scope_brand_id is null and x.scope_group_id = gid
           and x.sequence_number < p_before and x.sequence_number >= p_after
           and (p_record_id is null or x.record_id = p_record_id)
           and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
           and (p_module is null or x.module = p_module)
           and (p_tables is null or x.table_name = any (p_tables))
         order by x.sequence_number desc limit p_limit) e
    union all
    -- Eventos sin alcance (por ejemplo, el catálogo de roles): solo con el permiso de todo el grupo.
    (select x.* from audit.audit_events x
      where p_actor_id is null and cardinality(p_gids) > 0 and x.scope_group_id is null
        and x.sequence_number < p_before and x.sequence_number >= p_after
        and (p_record_id is null or x.record_id = p_record_id)
        and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
        and (p_module is null or x.module = p_module)
        and (p_tables is null or x.table_name = any (p_tables))
      order by x.sequence_number desc limit p_limit)
    union all
    -- Lo que hizo una persona: por su índice, y después se mira que esté en el alcance.
    (select x.* from audit.audit_events x
      where p_actor_id is not null and x.actor_user_id = p_actor_id
        and x.sequence_number < p_before and x.sequence_number >= p_after
        and (x.scope_restaurant_id = any (p_rids)
             or (x.scope_restaurant_id is null and x.scope_brand_id = any (p_bids))
             or (x.scope_brand_id is null and x.scope_group_id = any (p_gids))
             or (x.scope_group_id is null and cardinality(p_gids) > 0))
        and (p_record_id is null or x.record_id = p_record_id)
        and (p_from is null or x.occurred_at >= p_from) and (p_to is null or x.occurred_at < p_to)
        and (p_module is null or x.module = p_module)
        and (p_tables is null or x.table_name = any (p_tables))
      order by x.sequence_number desc limit p_limit)
  )
  select * from events order by events.sequence_number desc limit p_limit
$$;
comment on function core.audit_scope_events(uuid[], uuid[], uuid[], integer, bigint, bigint, uuid, timestamptz, timestamptz, uuid, text, text[]) is
  'Uso interno del historial y la exportación: los últimos eventos de los locales, marcas y grupos indicados, con filtros, leídos por índice. No decide permisos: quien la llama arma las listas de alcance.';
revoke execute on function core.audit_scope_events(uuid[], uuid[], uuid[], integer, bigint, bigint, uuid, timestamptz, timestamptz, uuid, text, text[]) from public;

-- Convierte un período en números de evento (para que el corte entre en el índice), leyendo una
-- sola fila del índice por fecha. occurred_at es la hora de inicio de la transacción y el número
-- se asigna al insertar: un evento de más de una hora antes del período se insertó antes que
-- cualquiera del período, siempre que ninguna transacción dure más de una hora (ADR-0015). El
-- filtro por fecha se sigue aplicando exacto sobre lo que se muestra.
create function core.audit_sequence_bounds(p_from timestamptz, p_to timestamptz, out after_seq bigint, out before_seq bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  after_seq := 0;
  before_seq := 9223372036854775807;
  if p_from is not null then
    select x.sequence_number into after_seq
      from audit.audit_events x where x.occurred_at < p_from - interval '1 hour'
     order by x.occurred_at desc limit 1;
    after_seq := coalesce(after_seq, 0);
  end if;
  if p_to is not null then
    select x.sequence_number into before_seq
      from audit.audit_events x where x.occurred_at >= p_to + interval '1 hour'
     order by x.occurred_at limit 1;
    before_seq := coalesce(before_seq, 9223372036854775807);
  end if;
end
$$;
comment on function core.audit_sequence_bounds(timestamptz, timestamptz) is
  'Uso interno: el primer y el último número de evento de un período.';
revoke execute on function core.audit_sequence_bounds(timestamptz, timestamptz) from public;

create function core.audit_history(
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

  return query
  select e.sequence_number, e.occurred_at,
         coalesce(core.display_name(coalesce(e.actor_user_id, e.actor_service_account_id)),
                  case when e.source is not null then 'Sistema (' || e.source::text || ')' else 'Sistema' end),
         e.actor_role_code, e.action::text, e.module, e.table_schema, e.table_name, e.record_id, e.changed_fields,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.old_values else core.hide_costs(e.old_values) end,
         case when core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) then e.new_values else core.hide_costs(e.new_values) end,
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
  'Historial de cambios que la sesión puede ver (audit.view por alcance), del más nuevo al más viejo, con filtros por registro, fecha, persona, marca, local y módulo, o solo los cambios críticos (roles, permisos, cuentas y aprobaciones). Pagina por número de evento, hasta 200. Oculta los costos a quien no los puede ver.';
revoke execute on function core.audit_history(integer, bigint, uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, boolean) from public;
grant execute on function core.audit_history(integer, bigint, uuid, timestamptz, timestamptz, uuid, uuid, uuid, text, boolean) to authenticated;

create function core.audit_export(
  p_from          timestamptz default null,
  p_to            timestamptz default null,
  p_actor_id      uuid default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null,
  p_record_id     uuid default null,
  p_limit         integer default 2000
)
returns table (occurred_at timestamptz, actor_name text, actor_role_code text, action text, module text, table_name text,
               record_id uuid, field text, old_value text, new_value text, reason text, source text, place_name text,
               operation_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit  int := least(greatest(coalesce(p_limit, 2000), 1), 5000);
  v_bounds record;
  v_rids   uuid[];
  v_bids   uuid[];
  v_gids   uuid[];
  v_count  int;
begin
  if not core.current_session_ok() then
    return;
  end if;
  if p_module is not null and (length(p_module) > 60 or p_module !~ '^[a-z_]+$') then
    raise exception 'Módulo inválido.' using errcode = '22023';
  end if;
  -- Se exporta solo donde la sesión puede exportar (audit.export por alcance).
  v_rids := array(select r.id from org.restaurants r
                   where r.id in (select core.permitted_restaurant_ids('audit.export'))
                     and (p_restaurant_id is null or r.id = p_restaurant_id)
                     and (p_brand_id is null or r.brand_id = p_brand_id));
  v_bids := case when p_restaurant_id is null then
              array(select b from core.permitted_brand_ids('audit.export') b where p_brand_id is null or b = p_brand_id)
            else '{}' end;
  v_gids := case when p_restaurant_id is null and p_brand_id is null then array(select core.permitted_group_ids('audit.export'))
            else '{}' end;
  if cardinality(v_rids) + cardinality(v_bids) + cardinality(v_gids) = 0 then
    perform core.deny('core.audit_export', 'No tenés permiso para exportar el historial de ese lugar.', null,
                      jsonb_strip_nulls(jsonb_build_object('brand_id', p_brand_id, 'restaurant_id', p_restaurant_id)));
    return;
  end if;
  v_bounds := core.audit_sequence_bounds(p_from, p_to);

  -- Primero los eventos (hasta p_limit, leídos por índice); después, un campo por fila.
  return query
  with events as (
    select * from core.audit_scope_events(v_rids, v_bids, v_gids, v_limit, v_bounds.before_seq, v_bounds.after_seq,
                                          p_record_id, p_from, p_to, p_actor_id, p_module, null)
  ),
  fields as (
    select e.*, f.field, core.can_see_costs(e.scope_group_id, e.scope_brand_id, e.scope_restaurant_id) as costs
      from events e
      cross join lateral unnest(case
          when e.action in ('insert', 'approve', 'reject') then array(select jsonb_object_keys(e.new_values))
          when e.action = 'delete' then array(select jsonb_object_keys(e.old_values))
          else e.changed_fields end) as f (field)
     where f.field not in ('id', 'created_at', 'created_by', 'updated_at', 'updated_by')
  )
  select f.occurred_at,
         coalesce(core.display_name(coalesce(f.actor_user_id, f.actor_service_account_id)),
                  case when f.source is not null then 'Sistema (' || f.source::text || ')' else 'Sistema' end),
         f.actor_role_code, f.action::text, f.module, f.table_schema || '.' || f.table_name, f.record_id, f.field,
         -- Los costos salen ocultos para quien no los puede ver, también adentro de los valores
         -- compuestos (revisión de base M4 y de seguridad M-B), igual que en la pantalla.
         (case when f.costs then f.old_values else core.hide_costs(f.old_values) end) ->> f.field,
         (case when f.costs then f.new_values else core.hide_costs(f.new_values) end) ->> f.field,
         f.reason, f.source::text,
         coalesce((select r.name from org.restaurants r where r.id = f.scope_restaurant_id),
                  (select b.name from org.brands b where b.id = f.scope_brand_id),
                  (select g.name from org.groups g where g.id = f.scope_group_id)),
         f.operation_id
    from fields f
   order by f.sequence_number desc, f.field;

  get diagnostics v_count = row_count;
  -- Toda exportación queda en el registro de seguridad: quién, cuándo, con qué filtros y cuántas filas.
  perform audit.log_security_event('audit_exported', 'core.audit_export', 'Exportación del historial',
    core.current_actor_id(), null,
    jsonb_strip_nulls(jsonb_build_object('rows', v_count, 'from', p_from, 'to', p_to, 'actor_id', p_actor_id,
                                         'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id, 'module', p_module,
                                         'record_id', p_record_id)),
    core.user_group(core.current_actor_id()), p_brand_id, p_restaurant_id);
end
$$;
comment on function core.audit_export(timestamptz, timestamptz, uuid, uuid, uuid, text, uuid, integer) is
  'Exporta el historial, un campo cambiado por fila, con los mismos filtros que la pantalla: hasta 5.000 eventos por pedido, leídos por índice. Pide audit.export en el alcance; oculta los costos a quien no los puede ver; cada exportación (o el intento sin permiso) queda en el registro de seguridad.';
revoke execute on function core.audit_export(timestamptz, timestamptz, uuid, uuid, uuid, text, uuid, integer) from public;
grant execute on function core.audit_export(timestamptz, timestamptz, uuid, uuid, uuid, text, uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Tablero de control de usuarios: "¿quién tiene acceso y qué está pasando?"
-- ---------------------------------------------------------------------------
create function core.users_control_panel(
  p_from          date default null,
  p_to            date default null,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null,
  p_module        text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor    uuid := core.current_actor_id();
  v_tz       text := 'America/Argentina/Buenos_Aires';
  v_to       date := coalesce(p_to, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  v_from     date := coalesce(p_from, coalesce(p_to, (now() at time zone 'America/Argentina/Buenos_Aires')::date) - 29);
  v_security boolean;
  v_groups   uuid[];
  v_r        org.restaurants;
  v_b        org.brands;
  v_users    uuid[];
begin
  if v_actor is null or not core.current_session_ok() then
    return null;
  end if;
  if v_from > v_to or v_to - v_from > 366 then
    raise exception 'El período tiene que ir de una fecha a otra posterior, hasta un año.' using errcode = '22023';
  end if;
  if p_restaurant_id is not null then
    select * into v_r from org.restaurants where id = p_restaurant_id;
  end if;
  if p_brand_id is not null then
    select * into v_b from org.brands where id = p_brand_id;
  end if;
  -- El registro de seguridad solo con security.view (de grupo: los ingresos no tienen marca ni local).
  v_groups := array(select core.permitted_group_ids('security.view'));
  v_security := cardinality(v_groups) > 0;

  -- Las personas del tablero: las que la sesión ve, con acceso al local o la marca del filtro.
  v_users := array(
    select p.id from core.user_profiles p
     where p.id in (select core.visible_user_ids()) and p.deleted_at is null
       and (p_restaurant_id is null or exists (
             select 1 from core.user_role_assignments a
              where a.user_id = p.id and a.deleted_at is null and a.group_id = v_r.group_id
                and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
                and (a.scope_type = 'group' or (a.scope_type = 'brand' and a.brand_id = v_r.brand_id)
                     or (a.scope_type = 'restaurant' and a.restaurant_id = v_r.id))))
       and (p_brand_id is null or exists (
             select 1 from core.user_role_assignments a
              where a.user_id = p.id and a.deleted_at is null and a.group_id = v_b.group_id
                and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
                and (a.scope_type = 'group' or a.brand_id = v_b.id))));

  return (
    with people as (select p.* from core.user_profiles p where p.id = any (v_users)),
    sec as (
      select s.event_type, s.occurred_at, s.user_id
        from audit.authentication_security_events s
       where v_security and s.scope_group_id = any (v_groups)
         and s.occurred_at >= least(v_from, v_to - 13)::timestamp at time zone v_tz
         and s.occurred_at < (v_to + 1)::timestamp at time zone v_tz
         and s.event_type in ('login_succeeded', 'login_failed', 'operation_denied')
         -- Con filtro de lugar, solo los de las personas de ese lugar.
         and (p_restaurant_id is null and p_brand_id is null or s.user_id = any (v_users))
    ),
    current_roles as (
      select a.user_id, a.scope_type, a.brand_id, a.restaurant_id, r.code, r.name, r.level
        from core.user_role_assignments a
        join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.id in (select core.visible_assignment_ids())
         and a.user_id = any (v_users) and a.deleted_at is null
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
    )
    select jsonb_build_object(
      'as_of', now(),
      'from', v_from,
      'to', v_to,
      'can_view_security', v_security,
      'active', (select count(*) from people where status = 'active' and (locked_until is null or locked_until <= now())),
      'suspended', (select count(*) from people where status = 'suspended'),
      'deactivated', (select count(*) from people where status = 'deactivated'),
      'locked', (select count(*) from people where locked_until > now()),
      'pending_approvals', (
        select count(*) from workflow.approval_requests r
         where r.status = 'pending' and r.deleted_at is null
           and (p_restaurant_id is null or r.restaurant_id = p_restaurant_id)
           and (p_brand_id is null or r.brand_id = p_brand_id)
           and (r.requested_by = v_actor or r.subject_user_id = v_actor
                or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
                or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
                or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))),
      -- Accesos rechazados: ingresos fallidos y operaciones rechazadas, 7 días contra los 7 anteriores.
      'rejected_7d', case when v_security then (
        select count(*) from sec where event_type in ('login_failed', 'operation_denied')
           and occurred_at >= (v_to - 6)::timestamp at time zone v_tz) end,
      'rejected_prev_7d', case when v_security then (
        select count(*) from sec where event_type in ('login_failed', 'operation_denied')
           and occurred_at >= (v_to - 13)::timestamp at time zone v_tz
           and occurred_at < (v_to - 6)::timestamp at time zone v_tz) end,
      'logins_by_day', case when v_security then (
        select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'succeeded', coalesce(c.ok, 0), 'failed', coalesce(c.bad, 0))
                                  order by d.day), '[]'::jsonb)
          from generate_series(v_from, v_to, interval '1 day') as d (day)
          left join (
            select (occurred_at at time zone v_tz)::date as day,
                   count(*) filter (where event_type = 'login_succeeded') as ok,
                   count(*) filter (where event_type = 'login_failed') as bad
              from sec where occurred_at >= v_from::timestamp at time zone v_tz
             group by 1) c on c.day = d.day::date) end,
      'by_role', coalesce((
        select jsonb_agg(jsonb_build_object('role_code', code, 'role_name', name, 'people', people) order by level)
          from (select code, name, level, count(distinct user_id) as people from current_roles group by code, name, level) s), '[]'::jsonb),
      -- Por local: quienes tienen un rol de ese local o de su marca (los de todo el grupo van aparte).
      'by_restaurant', coalesce((
        select jsonb_agg(jsonb_build_object('restaurant_id', r.id, 'restaurant_name', r.name, 'brand_name', b.name,
                                            'people', (select count(distinct cr.user_id) from current_roles cr
                                                        where cr.restaurant_id = r.id
                                                           or (cr.scope_type = 'brand' and cr.brand_id = r.brand_id)))
                         order by b.name, r.name)
          from org.restaurants r join org.brands b on b.id = r.brand_id
         where r.deleted_at is null and r.id in (select core.permitted_restaurant_ids('users.view'))
           and (p_restaurant_id is null or r.id = p_restaurant_id)
           and (p_brand_id is null or r.brand_id = p_brand_id)), '[]'::jsonb),
      'group_wide_people', (select count(distinct user_id) from current_roles where scope_type = 'group'),
      'critical_changes', coalesce((
        select jsonb_agg(to_jsonb(h) order by h.sequence_number desc)
          from core.audit_history(10, null, null, v_from::timestamp at time zone v_tz, (v_to + 1)::timestamp at time zone v_tz,
                                  null, p_brand_id, p_restaurant_id, p_module, true) h), '[]'::jsonb)
    )
  );
end
$$;
comment on function core.users_control_panel(date, date, uuid, uuid, text) is
  'Tablero de control de usuarios (sección 9): personas activas, suspendidas y desactivadas, aprobaciones pendientes, accesos rechazados en 7 días (contra los 7 anteriores), accesos por día, personas por rol y por local, y los últimos cambios críticos. Filtros: período (30 días por defecto), marca, local y módulo. Los datos de seguridad salen solo con security.view.';
revoke execute on function core.users_control_panel(date, date, uuid, uuid, text) from public;
grant execute on function core.users_control_panel(date, date, uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Ficha de usuario: último acceso, actividad reciente e intentos rechazados
-- ---------------------------------------------------------------------------
create function core.user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p     core.user_profiles;
  v_group uuid;
begin
  if not core.current_session_ok() or not core.can_view_user(p_user_id) then
    return null;
  end if;
  select * into v_p from core.user_profiles where id = p_user_id and deleted_at is null;
  if not found then
    return null;
  end if;
  v_group := core.user_group(p_user_id);
  return jsonb_build_object(
    'id', v_p.id,
    'username', v_p.username,
    'job_title', v_p.job_title,
    'area_id', v_p.area_id,
    'area_name', (select ar.name || ' · ' || r.name from org.areas ar join org.restaurants r on r.id = ar.restaurant_id where ar.id = v_p.area_id),
    'activated_at', v_p.activated_at,
    'last_seen_at', v_p.last_seen_at,
    'invited_by_name', core.display_name(v_p.invited_by),
    'status', v_p.status,
    'suspended_at', v_p.suspended_at,
    'suspension_reason', v_p.suspension_reason,
    'suspended_by_name', core.display_name(v_p.suspended_by),
    'deactivated_at', v_p.deactivated_at,
    'deactivation_reason', v_p.deactivation_reason,
    'deactivated_by_name', core.display_name(v_p.deactivated_by),
    'workplaces', coalesce((
      select jsonb_agg(jsonb_build_object('group_name', g.name, 'brand_name', b.name, 'restaurant_name', r.name,
                                          'starts_at', m.starts_at, 'ends_at', m.ends_at) order by m.starts_at)
        from core.user_memberships m
        join org.groups g on g.id = m.group_id
        left join org.brands b on b.id = m.brand_id
        left join org.restaurants r on r.id = m.restaurant_id
       where m.user_id = p_user_id and m.deleted_at is null and (m.ends_at is null or m.ends_at > now())), '[]'::jsonb),
    -- Lo que hizo la persona, dentro de lo que la sesión puede ver del historial.
    'can_view_activity', exists (select 1 from core.actor_grants('audit.view')),
    'recent_activity', coalesce((
      select jsonb_agg(jsonb_build_object('occurred_at', h.occurred_at, 'action', h.action, 'table_name', h.table_schema || '.' || h.table_name,
                                          'reason', h.reason, 'place_name', h.place_name) order by h.sequence_number desc)
        from core.audit_history(20, null, null, null, null, p_user_id) h), '[]'::jsonb),
    -- Intentos rechazados: solo con security.view del grupo de la persona.
    'can_view_security', coalesce(core.has_permission_in_group('security.view', v_group), false),
    'rejected_attempts', case when coalesce(core.has_permission_in_group('security.view', v_group), false) then coalesce((
      select jsonb_agg(jsonb_build_object('occurred_at', s.occurred_at, 'event_type', s.event_type, 'operation', s.operation,
                                          'reason', s.reason) order by s.occurred_at desc)
        from (select * from audit.authentication_security_events s
               where (s.user_id = p_user_id or s.actor_id = p_user_id)
                 and s.event_type in ('login_failed', 'operation_denied', 'account_locked')
               order by s.occurred_at desc limit 20) s), '[]'::jsonb) end
  );
end
$$;
comment on function core.user_detail(uuid) is
  'Datos de la ficha de una persona que la sesión puede ver: puesto, área, primer y último acceso, quién la invitó, suspensión o baja, dónde trabaja, su actividad reciente (con audit.view) y sus intentos rechazados (con security.view).';
revoke execute on function core.user_detail(uuid) from public;
grant execute on function core.user_detail(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Lista de usuarios con filtros por rol y área
-- ---------------------------------------------------------------------------
drop function core.users_dashboard(text, uuid, uuid, text, text, uuid, integer, uuid);
create function core.users_dashboard(p_search text default null, p_brand_id uuid default null,
                                     p_restaurant_id uuid default null, p_status text default null,
                                     p_after_key text default null, p_after_id uuid default null,
                                     p_limit integer default 25, p_user_id uuid default null,
                                     p_role_code text default null, p_area_id uuid default null)
returns table (id uuid, first_name text, last_name text, email text, status core.account_status, locked boolean,
               roles jsonb, sort_key text, job_title text, area_name text, last_seen_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_search text := nullif(lower(btrim(p_search)), '');
  v_r      org.restaurants;
  v_b      org.brands;
begin
  if p_status is not null and p_status not in ('active', 'suspended', 'deactivated', 'locked') then
    raise exception 'Filtro de estado inválido.' using errcode = '22023';
  end if;
  if (p_after_key is null) <> (p_after_id is null) then
    raise exception 'La página siguiente necesita la clave y el id.' using errcode = '22023';
  end if;
  if p_restaurant_id is not null then
    select * into v_r from org.restaurants where org.restaurants.id = p_restaurant_id;
  end if;
  if p_brand_id is not null then
    select * into v_b from org.brands where org.brands.id = p_brand_id;
  end if;

  return query
  with visible as (select v as user_id from core.visible_user_ids() as v),
       visible_assignments as (select v as assignment_id from core.visible_assignment_ids() as v)
  select p.id, p.first_name, p.last_name, p.email, p.status,
         coalesce(p.locked_until > now(), false),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'assignment_id', a.id, 'role_code', r.code, 'role_name', r.name, 'scope_type', a.scope_type,
                    'scope_name', coalesce(rs.name, b.name, g.name))
                  order by r.level)
             from core.user_role_assignments a
             -- Solo los roles que la sesión puede ver (la misma regla que la RLS).
             join visible_assignments va on va.assignment_id = a.id
             join core.roles r on r.id = a.role_id
             join org.groups g on g.id = a.group_id
             left join org.brands b on b.id = a.brand_id
             left join org.restaurants rs on rs.id = a.restaurant_id
            where a.user_id = p.id and a.deleted_at is null
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())), '[]'::jsonb),
         lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email) as sort_key,
         p.job_title,
         (select ar.name || ' · ' || rs.name from org.areas ar join org.restaurants rs on rs.id = ar.restaurant_id where ar.id = p.area_id),
         p.last_seen_at
    from core.user_profiles p
    join visible vis on vis.user_id = p.id
   where p.deleted_at is null
     and (p_user_id is null or p.id = p_user_id)
     and (v_search is null
          or position(v_search in lower(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '') || ' ' || p.email
                                        || ' ' || coalesce(p.username, '') || ' ' || coalesce(p.job_title, ''))) > 0)
     and (p_status is null
          or (p_status = 'active' and p.status = 'active' and (p.locked_until is null or p.locked_until <= now()))
          or (p_status = 'suspended' and p.status = 'suspended')
          or (p_status = 'deactivated' and p.status = 'deactivated')
          or (p_status = 'locked' and p.locked_until > now()))
     and (p_area_id is null or p.area_id = p_area_id)
     -- Por rol: solo entre los roles que la sesión puede ver.
     and (p_role_code is null or exists (
           select 1 from core.user_role_assignments a
             join visible_assignments va on va.assignment_id = a.id
             join core.roles r on r.id = a.role_id and r.code = p_role_code
            where a.user_id = p.id and a.deleted_at is null
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())))
     -- Quienes tienen acceso a ese local o a esa marca (incluidos los roles de grupo).
     and (p_restaurant_id is null or exists (
           select 1 from core.user_role_assignments a
            where a.user_id = p.id and a.deleted_at is null and a.group_id = v_r.group_id
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
              and (a.scope_type = 'group'
                   or (a.scope_type = 'brand' and a.brand_id = v_r.brand_id)
                   or (a.scope_type = 'restaurant' and a.restaurant_id = v_r.id))))
     and (p_brand_id is null or exists (
           select 1 from core.user_role_assignments a
            where a.user_id = p.id and a.deleted_at is null and a.group_id = v_b.group_id
              and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
              and (a.scope_type = 'group' or a.brand_id = v_b.id)))
     and (p_after_key is null
          or (lower(coalesce(p.last_name, '') || ' ' || coalesce(p.first_name, '') || ' ' || p.email), p.id) > (p_after_key, p_after_id))
   order by 8, 1
   limit least(greatest(coalesce(p_limit, 25), 1), 100);
end
$$;
comment on function core.users_dashboard(text, uuid, uuid, text, text, uuid, integer, uuid, text, uuid) is
  'Lista paginada de las personas que la sesión puede ver, con sus roles visibles, puesto, área y último acceso. Filtros: búsqueda, marca, local, estado (active, suspended, deactivated, locked), rol y área. Pagina por clave.';
revoke execute on function core.users_dashboard(text, uuid, uuid, text, text, uuid, integer, uuid, text, uuid) from public;
grant execute on function core.users_dashboard(text, uuid, uuid, text, text, uuid, integer, uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Matriz rol × permiso
-- ---------------------------------------------------------------------------
create function core.permission_matrix(p_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_manage boolean;
begin
  if not core.current_session_ok() or not core.can_view_scope('org.view', 'group', p_group_id) then
    return null;
  end if;
  v_manage := core.has_permission_in_group('permissions.manage', p_group_id);
  return jsonb_build_object(
    'can_manage', v_manage,
    'roles', (select jsonb_agg(jsonb_build_object('id', r.id, 'code', r.code, 'name', r.name, 'level', r.level,
                                                  'requires_mfa', r.requires_mfa,
                                                  -- Nadie cambia un rol que tiene él mismo.
                                                  'is_mine', exists (select 1 from core.user_role_assignments a
                                                                      where a.user_id = core.current_actor_id() and a.role_id = r.id
                                                                        and a.deleted_at is null))
                                order by r.level)
                from core.roles r where r.deleted_at is null),
    'permissions', (select jsonb_agg(jsonb_build_object('code', p.code, 'module', p.module, 'action', p.action,
                                                        'description', p.description, 'is_sensitive', p.is_sensitive)
                                      order by p.module, p.code)
                      from core.permissions p where p.deleted_at is null),
    'grants', (select coalesce(jsonb_agg(jsonb_build_object('role_code', r.code, 'permission_code', p.code)), '[]'::jsonb)
                 from core.role_permissions rp
                 join core.roles r on r.id = rp.role_id and r.deleted_at is null
                 join core.permissions p on p.id = rp.permission_id and p.deleted_at is null
                where rp.deleted_at is null),
    -- Los cambios pedidos que esperan la aprobación de Dirección General.
    'pending', case when v_manage then (
      select coalesce(jsonb_agg(jsonb_build_object('request_id', q.id, 'role_code', q.proposed_changes ->> 'role_code',
                                                   'permission_code', q.proposed_changes ->> 'permission_code',
                                                   'grant', (q.proposed_changes ->> 'grant')::boolean,
                                                   'requested_by_name', core.display_name(q.requested_by),
                                                   'requested_at', q.requested_at, 'reason', q.reason)
                                order by q.requested_at desc), '[]'::jsonb)
        from workflow.approval_requests q
        join workflow.approval_workflows w on w.id = q.workflow_id and w.code = 'core.change_role_permission'
       where q.group_id = p_group_id and q.status = 'pending' and q.deleted_at is null) else '[]'::jsonb end
  );
end
$$;
comment on function core.permission_matrix(uuid) is
  'Matriz de roles por permiso del grupo, para la pantalla de roles y permisos. Quien tiene permissions.manage ve además los cambios pendientes de aprobación.';
revoke execute on function core.permission_matrix(uuid) from public;
grant execute on function core.permission_matrix(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Mi cuenta
-- ---------------------------------------------------------------------------
create function core.my_account()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor   uuid := core.current_actor_id();
  v_session text := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id';
  v_p       core.user_profiles;
begin
  if v_actor is null or not core.current_session_ok() then
    return null;
  end if;
  select * into v_p from core.user_profiles where id = v_actor and deleted_at is null;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'first_name', v_p.first_name,
    'last_name', v_p.last_name,
    'email', v_p.email,
    'username', v_p.username,
    'job_title', v_p.job_title,
    'activated_at', v_p.activated_at,
    'last_seen_at', v_p.last_seen_at,
    -- Solo datos públicos del factor: nunca el secreto.
    'mfa_factors', coalesce((
      select jsonb_agg(jsonb_build_object('id', f.id, 'friendly_name', f.friendly_name, 'factor_type', f.factor_type,
                                          'status', f.status, 'created_at', f.created_at) order by f.created_at)
        from auth.mfa_factors f where f.user_id = v_actor), '[]'::jsonb),
    -- Las sesiones abiertas, sin tokens.
    'sessions', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'created_at', s.created_at, 'last_used_at', coalesce(s.refreshed_at at time zone 'UTC', s.updated_at),
                                          'user_agent', left(s.user_agent, 300), 'aal', s.aal,
                                          'is_current', s.id::text = v_session) order by coalesce(s.refreshed_at at time zone 'UTC', s.updated_at) desc)
        from auth.sessions s where s.user_id = v_actor and (s.not_after is null or s.not_after > now())), '[]'::jsonb)
  );
end
$$;
comment on function core.my_account() is
  'Datos de la propia cuenta para "Mi cuenta": nombre, puesto, primer y último acceso, factores de doble verificación (sin secretos) y sesiones abiertas (sin tokens).';
revoke execute on function core.my_account() from public;
grant execute on function core.my_account() to authenticated;

create function core.update_my_profile(p_first_name text, p_last_name text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    raise exception 'La sesión no puede operar.' using errcode = '42501';
  end if;
  if exists (select 1 from unnest(array[p_first_name, p_last_name, btrim(coalesce(p_first_name, '') || ' ' || coalesce(p_last_name, ''))]) as n (v)
              where lower(btrim(v)) ~ '^(sistema|system|admin|administrador|superadministrador)'
                 or lower(btrim(v)) in (select lower(r.name) from core.roles r where r.deleted_at is null)) then
    raise exception 'Ese nombre se confunde con el sistema o con un rol: usá tu nombre real.' using errcode = '22023';
  end if;
  perform core.set_change_context('La persona actualizó sus datos', 'manual');
  update core.user_profiles
     set first_name = nullif(btrim(p_first_name), ''), last_name = nullif(btrim(p_last_name), '')
   where id = v_actor;
  return jsonb_build_object('result', 'applied', 'message', 'Datos guardados.');
end
$$;
comment on function core.update_my_profile(text, text) is
  'La persona cambia su propio nombre y apellido. Nada más del perfil (estado, puesto, área) se cambia desde acá.';
revoke execute on function core.update_my_profile(text, text) from public;
grant execute on function core.update_my_profile(text, text) to authenticated;

-- Los eventos de contraseña y de doble verificación los anota la base cuando pasan de verdad, desde
-- Auth (revisión de seguridad M-A): no hay una función que la pantalla pueda llamar para inventarlos.
create function core.log_auth_account_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'users' then
    if new.encrypted_password is distinct from old.encrypted_password and old.encrypted_password is not null
       and exists (select 1 from core.user_profiles p where p.id = new.id) then
      perform audit.log_security_event('password_changed', 'auth.password', 'La persona cambió su contraseña.',
                                       new.id, new.email, null, core.user_group(new.id));
    end if;
  elsif tg_table_name = 'mfa_factors' then
    if new.status::text = 'verified' and (tg_op = 'INSERT' or old.status::text is distinct from 'verified')
       and exists (select 1 from core.user_profiles p where p.id = new.user_id) then
      perform audit.log_security_event('mfa_enrolled', 'auth.mfa', 'La persona registró una app de doble verificación.',
                                       new.user_id, null, null, core.user_group(new.user_id));
    end if;
  end if;
  return null;
end
$$;
comment on function core.log_auth_account_change() is
  'Anota en el registro de seguridad los cambios de contraseña y los registros de doble verificación, cuando Supabase Auth los guarda.';
revoke execute on function core.log_auth_account_change() from public;

create trigger log_password_change after update of encrypted_password on auth.users
  for each row execute function core.log_auth_account_change();
create trigger log_mfa_enrolled after insert or update of status on auth.mfa_factors
  for each row execute function core.log_auth_account_change();

-- Una sesión cerrada (desde "Mi cuenta", al salir, al desactivar o suspender) deja de operar en la
-- consulta siguiente, aunque su token todavía no venza: has_permission exige que la sesión del
-- token siga existiendo en Auth. Los tokens sin session_id (por ejemplo, en pgTAP) no se ven afectados.
create or replace function core.current_session_ok()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  -- El JWT se lee una sola vez por llamada (rendimiento: esto corre en cada política).
  v_claims  jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_actor   uuid := core.current_actor_id();
  v_aal     text := core.current_aal();
  v_session uuid := case when (v_claims ->> 'session_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                         then (v_claims ->> 'session_id')::uuid end;
begin
  if v_actor is null then
    return false;
  end if;
  if v_session is not null and not exists (select 1 from auth.sessions s where s.id = v_session and s.user_id = v_actor) then
    return false;
  end if;
  return exists (
    select 1
      from core.user_profiles p
     where p.id = v_actor
       and p.deleted_at is null
       and p.status = 'active'
       and (p.locked_until is null or p.locked_until <= now())
  )
  and (
    v_aal is not distinct from 'aal2'
    or not exists (
      select 1
        from core.user_role_assignments a
        join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.user_id = v_actor
         and a.deleted_at is null
         and r.requires_mfa
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
    )
  );
end
$$;

-- Mi sesión, para la interfaz: también dice si la sesión del token sigue abierta.
create or replace function core.my_session()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor   uuid := core.current_actor_id();
  v_session uuid := case when (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                         then (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id')::uuid end;
  v_p       core.user_profiles;
begin
  if v_actor is null then
    return jsonb_build_object('signed_in', false);
  end if;
  select * into v_p from core.user_profiles where id = v_actor;
  return jsonb_build_object(
    'signed_in', true,
    'session_active', v_session is null or exists (select 1 from auth.sessions s where s.id = v_session and s.user_id = v_actor),
    'user_id', v_actor,
    'has_profile', v_p.id is not null,
    'status', v_p.status,
    'deleted', v_p.deleted_at is not null,
    'locked', coalesce(v_p.locked_until > now(), false),
    'first_name', v_p.first_name,
    'last_name', v_p.last_name,
    'email', v_p.email,
    'aal', core.current_aal(),
    'requires_mfa', exists (
      select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id and r.deleted_at is null
       where a.user_id = v_actor and a.deleted_at is null and r.requires_mfa
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())),
    'has_roles', exists (
      select 1 from core.user_role_assignments a
       where a.user_id = v_actor and a.deleted_at is null
         and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())),
    'can_operate', core.current_session_ok());
end
$$;

-- ---------------------------------------------------------------------------
-- 8. Bandeja de aprobaciones con el antes y el después
-- ---------------------------------------------------------------------------
drop function workflow.inbox(boolean, integer, timestamptz, uuid);
create function workflow.inbox(p_pending boolean default true, p_limit integer default 50,
                               p_before_created_at timestamptz default null, p_before_id uuid default null)
returns table (id uuid, workflow_code text, workflow_name text, status workflow.request_status, requested_at timestamptz,
               requested_by_name text, summary text, reason text, place_name text, can_decide boolean,
               resolved_at timestamptz, resolved_by_name text, resolution_comment text,
               entity_table text, previous_values jsonb, proposed_changes jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    return;
  end if;
  if (p_before_created_at is null) <> (p_before_id is null) then
    raise exception 'La página siguiente necesita la fecha y el id.' using errcode = '22023';
  end if;
  return query
  -- Primero se filtra, ordena y limita (por conjuntos, una vez por consulta); recién después se
  -- arma el resumen de las pocas filas que quedan.
  with page as (
    select r.*
      from workflow.approval_requests r
     where r.deleted_at is null
       and ((p_pending and r.status = 'pending') or (not p_pending and r.status <> 'pending'))
       and (p_before_created_at is null or (r.created_at, r.id) < (p_before_created_at, p_before_id))
       and (r.requested_by = v_actor or r.subject_user_id = v_actor
            or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
            or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
            or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))
     order by r.created_at desc, r.id desc
     limit least(greatest(coalesce(p_limit, 50), 1), 100)
  )
  select r.id, w.code, w.name, r.status, r.requested_at, core.display_name(r.requested_by),
         case
           when w.code in ('core.assign_sensitive_role', 'core.assign_superadmin', 'core.assign_by_superadmin') then
             'Dar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.revoke_by_superadmin' then
             'Quitar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.change_role_permission' then
             case when (r.proposed_changes ->> 'grant')::boolean then 'Dar el permiso ' else 'Quitar el permiso ' end
             || (r.proposed_changes ->> 'permission_code') || ' al rol '
             || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
           when w.code = 'org.transfer_restaurant' then
             'Traspasar ' || coalesce((select rs.name from org.restaurants rs where rs.id = (r.proposed_changes ->> 'restaurant_id')::uuid), 'un local')
             || ' a la marca ' || coalesce((select b.name from org.brands b where b.id = (r.proposed_changes ->> 'target_brand_id')::uuid), '')
           when w.code = 'core.reactivate_user' then
             'Reactivar la cuenta de ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           else w.name
         end,
         r.reason,
         coalesce((select rs.name from org.restaurants rs where rs.id = r.restaurant_id),
                  (select b.name from org.brands b where b.id = r.brand_id),
                  (select g.name from org.groups g where g.id = r.group_id)),
         r.status = 'pending' and workflow.decision_blocker(r.id) is null,
         r.resolved_at, core.display_name(r.resolved_by), r.resolution_comment,
         r.entity_table,
         case when core.can_see_costs(r.group_id, r.brand_id, r.restaurant_id) then r.previous_values
              else core.hide_costs(r.previous_values) end,
         -- Lo técnico del pedido (a quiénes excluye, la foto de permisos) no se muestra.
         case when core.can_see_costs(r.group_id, r.brand_id, r.restaurant_id)
              then r.proposed_changes - 'excluded_approvers' - 'role_permissions'
              else core.hide_costs(r.proposed_changes - 'excluded_approvers' - 'role_permissions') end
    from page r
    join workflow.approval_workflows w on w.id = r.workflow_id
   order by r.created_at desc, r.id desc;
end
$$;
comment on function workflow.inbox(boolean, int, timestamptz, uuid) is
  'Bandeja de aprobaciones: las pendientes o las resueltas que la sesión puede ver, de la más nueva a la más vieja, con un resumen en español, el antes y el después, y si la sesión puede decidirlas. Pagina por fecha e id, hasta 100 por página.';
revoke execute on function workflow.inbox(boolean, int, timestamptz, uuid) from public;
grant execute on function workflow.inbox(boolean, int, timestamptz, uuid) to authenticated;
