-- Ficha de la persona en una pantalla (Tanda 1 de Soy, Usuarios, ADR-0062).
--
-- * Guardado en lote (core.save_user_sheet): nombre, apellido, puesto y área, roles que se dan y roles que se quitan,
--   con un motivo, en una transacción. Cambiar el nombre pide users.manage y tener todos los permisos de la persona (la
--   regla de core.cannot_act_on_user); el puesto y el área, que no dan permisos, solo users.manage en todos sus lugares
--   (core.cannot_place_user; decisión de Joaco, 2026-11-24). Los roles pasan por core.assign_role y core.revoke_role: los mismos permisos, las
--   mismas aprobaciones y nadie se da roles a sí mismo.
-- * Todo o nada: si la base rechaza un paso, no queda nada a medias y el rechazo se registra igual.
-- * Cerrar todas las sesiones de otra persona (core.close_user_sessions), sin suspenderla: pide users.deactivate, como
--   suspender y liberar el bloqueo, y queda en el registro de seguridad.
-- * Lo que la pantalla necesita (core.user_sheet_state): qué puede hacer la sesión, el sello para guardar y los
--   indicadores. Cada dato sigue la regla de siempre: lo administrativo, quien administra a la persona; la actividad,
--   dentro de lo que ve del historial; los rechazos, quien ve el registro de seguridad.

-- ---------------------------------------------------------------------------
-- 1. El control del nombre, en un solo lugar (antes estaba dentro de update_my_profile)
-- ---------------------------------------------------------------------------
-- Los caracteres que no se ven (de control, de ancho cero, espacios raros, que dan vuelta el texto) sirven para saltear
-- el control o para imitar a otra persona (revisión de seguridad, M3).
create function core.has_hidden_characters(p_text text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(p_text ~ '[\u0001-\u001f\u007f-\u009f\u00ad\u034f\u061c\u115f\u1160\u1680\u17b4\u17b5\u180b-\u180f\u2000-\u200f\u2028-\u202f\u205f-\u206f\u2800\u3000\u3164\ufe00-\ufe0f\ufeff\uffa0\ufff9-\ufffb\U0001bca0-\U0001bca3\U0001d173-\U0001d17a\U000e0000-\U000e0fff]', false)
$$;
comment on function core.has_hidden_characters(text) is
  'Interna: si un texto tiene caracteres que no se ven (de control, de ancho cero, espacios raros o que dan vuelta el texto).';
revoke execute on function core.has_hidden_characters(text) from public;

create function core.check_person_name(p_first_name text, p_last_name text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if core.has_hidden_characters(p_first_name) or core.has_hidden_characters(p_last_name) then
    raise exception 'El nombre tiene caracteres que no se ven: escribilo de nuevo.' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(array[p_first_name, p_last_name, btrim(coalesce(p_first_name, '') || ' ' || coalesce(p_last_name, ''))]) as t (raw)
              cross join lateral (select lower(btrim(regexp_replace(normalize(t.raw, nfkc), '\s+', ' ', 'g')))) as n (v)
              where n.v ~ '^[^[:alpha:]]*(sistema|system|admin|super[^a-z]*admin)'
                 or n.v in (select lower(r.name) from core.roles r where r.deleted_at is null)) then
    raise exception 'Ese nombre se confunde con el sistema o con un rol: usá tu nombre real.' using errcode = '22023';
  end if;
end
$$;
comment on function core.check_person_name(text, text) is
  'Interna: el nombre de una persona no se puede confundir con el sistema ni con un rol.';
revoke execute on function core.check_person_name(text, text) from public;

create or replace function core.update_my_profile(p_first_name text, p_last_name text)
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
  -- El espacio duro que viene pegado de Word o Excel se guarda como espacio.
  perform core.check_person_name(btrim(replace(p_first_name, chr(160), ' ')), btrim(replace(p_last_name, chr(160), ' ')));
  perform core.set_change_context('La persona actualizó sus datos', 'manual');
  update core.user_profiles
     set first_name = nullif(btrim(replace(p_first_name, chr(160), ' ')), ''),
         last_name = nullif(btrim(replace(p_last_name, chr(160), ' ')), '')
   where id = v_actor;
  return jsonb_build_object('result', 'applied', 'message', 'Datos guardados.');
end
$$;

-- ---------------------------------------------------------------------------
-- 2. El sello y lo que necesita la pantalla
-- ---------------------------------------------------------------------------
-- El sello sale del contenido de la ficha (no de updated_at): cambia solo si cambia lo que se edita acá.
create function core.user_sheet_stamp_internal(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(jsonb_build_object(
    'first', u.first_name, 'last', u.last_name, 'job', u.job_title, 'area', u.area_id, 'status', u.status,
    'roles', (select jsonb_agg(a.id order by a.id) from core.user_role_assignments a
               where a.user_id = u.id and a.deleted_at is null))::text)
    from core.user_profiles u
   where u.id = p_user_id and u.deleted_at is null
$$;
comment on function core.user_sheet_stamp_internal(uuid) is
  'Interna: sello de la ficha de una persona (sus datos, su estado y sus roles). Cambia solo si cambia algo de eso.';
revoke execute on function core.user_sheet_stamp_internal(uuid) from public;

-- Por qué la sesión no puede editar los datos ni cerrar las sesiones de una persona (nulo = puede). La regla de siempre
-- (core.cannot_act_on_user) y, además, lo que para suspender o dar de baja pide a Dirección (otro Superadministrador)
-- no se hace por acá sin ella: cerrarle las sesiones una y otra vez sería como suspenderlo.
create function core.cannot_edit_user(p_user_id uuid, p_permission text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(core.cannot_act_on_user(p_user_id, p_permission),
                  case when core.governance_workflow(p_user_id, 'suspend') is not null
                         or core.governance_workflow(p_user_id, 'deactivate') is not null
                       then 'A esta persona solo la cambia Dirección General.' end)
$$;
comment on function core.cannot_edit_user(uuid, text) is
  'Interna: por qué la sesión no puede editar los datos ni cerrar las sesiones de una persona (nulo = puede). Suma a core.cannot_act_on_user lo que pide a Dirección (otro Superadministrador).';
revoke execute on function core.cannot_edit_user(uuid, text) from public;

-- Por qué la sesión no puede cambiarle el puesto y el área (nulo = puede). No dan permisos: alcanza con users.manage en
-- todos los lugares donde la persona tiene roles, sin tener todos sus permisos (decisión de Joaco, 2026-11-24). Siguen
-- afuera la cuenta propia (va en Mi cuenta) y otro Superadministrador.
create function core.cannot_place_user(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    return 'La sesión no puede operar.';
  end if;
  if p_user_id = v_actor then
    return 'No podés hacer esto sobre tu propia cuenta.';
  end if;
  if not exists (select 1 from core.user_profiles where id = p_user_id and deleted_at is null) then
    return 'La persona no existe o no la podés ver.';
  end if;
  if exists (select 1 from core.user_role_assignments a
              where a.user_id = p_user_id and a.deleted_at is null
                and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
                and not core.has_permission_for_scope('users.manage', a.scope_type, a.group_id, a.brand_id, a.restaurant_id)) then
    return 'La persona tiene roles fuera de tu alcance.';
  end if;
  if not exists (select 1 from core.user_role_assignments a
                  where a.user_id = p_user_id and a.deleted_at is null
                    and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now()))
     and not exists (select 1 from core.user_memberships m
                      where m.user_id = p_user_id and m.deleted_at is null
                        and m.starts_at <= now() and (m.ends_at is null or m.ends_at > now())
                        and core.has_permission_in_group('users.manage', m.group_id)) then
    return 'La persona no tiene roles en tu alcance.';
  end if;
  -- Otro Superadministrador, cualquiera sea el rol de quien edita.
  if core.holds_group_role(p_user_id, 'superadmin', core.user_group(p_user_id)) then
    return 'A esta persona solo la cambia Dirección General.';
  end if;
  return null;
end
$$;
comment on function core.cannot_place_user(uuid) is
  'Interna: por qué la sesión no puede cambiarle a una persona el puesto y el área (nulo = puede). Pide users.manage en todos los lugares donde tiene roles, sin exigir tener todos sus permisos: el puesto y el área no dan ninguno. Ni la cuenta propia ni otro Superadministrador.';
revoke execute on function core.cannot_place_user(uuid) from public;

-- Las áreas que se le pueden poner a una persona: en uso, de un local donde trabaja (core.membership_covers) y donde la
-- sesión administra personas (users.manage).
create function core.user_area_ids(p_user_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select ar.id
    from org.areas ar
    join org.restaurants r on r.id = ar.restaurant_id and r.deleted_at is null
   where ar.deleted_at is null and ar.is_active
     and r.id in (select core.permitted_restaurant_ids('users.manage'))
     and core.membership_covers(p_user_id, 'restaurant', r.group_id, r.brand_id, r.id)
$$;
comment on function core.user_area_ids(uuid) is
  'Interna: las áreas en uso de los locales donde trabaja una persona y donde la sesión tiene users.manage.';
revoke execute on function core.user_area_ids(uuid) from public;

create function core.user_sheet_state(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor    uuid := core.current_actor_id();
  v_group    uuid;
  v_admin    boolean;
  v_activity boolean;
  v_security boolean;
  v_act      text;
  v_rids     uuid[];
  v_bids     uuid[];
  v_gids     uuid[];
begin
  if not core.current_session_ok() or not core.can_view_user(p_user_id)
     or not exists (select 1 from core.user_profiles where id = p_user_id and deleted_at is null) then
    return null;
  end if;
  v_group := core.user_group(p_user_id);
  v_admin := core.can_administer_user(p_user_id);
  v_activity := exists (select 1 from core.actor_grants('audit.view'));
  v_security := coalesce(core.has_permission_in_group('security.view', v_group), false);
  v_act := core.cannot_act_on_user(p_user_id, 'users.deactivate');
  if v_activity then
    v_rids := array(select core.permitted_restaurant_ids('audit.view'));
    v_bids := array(select core.permitted_brand_ids('audit.view'));
    v_gids := array(select core.permitted_group_ids('audit.view'));
  end if;
  return jsonb_build_object(
    'stamp', core.user_sheet_stamp_internal(p_user_id),
    'is_me', p_user_id = v_actor,
    'can_edit_profile', core.cannot_edit_user(p_user_id, 'users.manage') is null,
    'can_edit_job', core.cannot_place_user(p_user_id) is null,
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object('id', ar.id, 'label', ar.name || ' · ' || r.name) order by r.name, ar.name)
        from org.areas ar join org.restaurants r on r.id = ar.restaurant_id
       where ar.id in (select core.user_area_ids(p_user_id))), '[]'::jsonb),
    'can_assign', p_user_id <> v_actor and core.has_permission_anywhere('roles.assign')
                  and exists (select 1 from core.user_profiles where id = p_user_id and status = 'active'),
    -- Los roles que la sesión puede quitar o pedir que se quiten (la misma regla que core.revoke_role).
    'revocable', case when p_user_id = v_actor then '[]'::jsonb else coalesce((
      select jsonb_agg(a.id) from core.user_role_assignments a
       where a.user_id = p_user_id and a.deleted_at is null
         and core.has_permission_for_scope('roles.assign', a.scope_type, a.group_id, a.brand_id, a.restaurant_id)
         and (cardinality(core.missing_permissions_for_role(a.role_id, a.scope_type, a.group_id, a.brand_id, a.restaurant_id)) = 0
              or core.has_role_for_scope(array['superadmin'], 'group', a.group_id))), '[]'::jsonb) end,
    'can_close_sessions', core.cannot_edit_user(p_user_id, 'users.deactivate') is null,
    'can_unlock', v_act is null,
    'can_suspend', v_act is null or core.governance_workflow(p_user_id, 'suspend') is not null,
    'can_deactivate', v_act is null or core.governance_workflow(p_user_id, 'deactivate') is not null,
    'can_reactivate', v_act is null or core.governance_workflow(p_user_id, 'reactivate') is not null,
    'mfa', case when v_admin then exists (select 1 from auth.mfa_factors f
                                           where f.user_id = p_user_id and f.status = 'verified') end,
    'sessions', case when v_admin then (select count(*) from auth.sessions s
                                         where s.user_id = p_user_id and (s.not_after is null or s.not_after > now())) end,
    -- Los mismos eventos que muestra el historial con esta persona (core.audit_scope_events).
    -- Con tope: más de 1.000 se muestra «+1.000» y la ficha no tarda más.
    'changes_30d', case when v_activity then (
      select count(*) from (
        select 1 from audit.audit_events x
         where x.actor_user_id = p_user_id and x.occurred_at >= ((now() at time zone 'America/Argentina/Buenos_Aires')::date - 30)::timestamp
                                                     at time zone 'America/Argentina/Buenos_Aires'
           and (x.scope_restaurant_id = any (v_rids)
                or (x.scope_restaurant_id is null and x.scope_brand_id = any (v_bids))
                or (x.scope_brand_id is null and x.scope_group_id = any (v_gids))
                or (x.scope_group_id is null and cardinality(v_gids) > 0))
         limit 1001) c) end,
    -- Los de la persona: sus ingresos fallidos y bloqueos, y las operaciones que intentó ella (no las que otros
    -- intentaron sobre su cuenta). La misma regla que la lista de core.user_detail.
    'rejected_7d', case when v_security then (
      select count(*) from (
        select 1 from audit.authentication_security_events s
         where ((s.event_type in ('login_failed', 'account_locked') and s.user_id = p_user_id)
                or (s.event_type = 'operation_denied' and s.actor_id = p_user_id))
           and s.occurred_at >= now() - interval '7 days'
         limit 1001) c) end);
end
$$;
comment on function core.user_sheet_state(uuid) is
  'Para la ficha de una persona: el sello, qué puede hacer la sesión (editar datos, dar y quitar roles, suspender, desactivar, cerrar sesiones) y los indicadores. La doble verificación y las sesiones, quien administra a la persona; los cambios en 30 días, dentro de lo que ve del historial; los rechazos en 7 días, con security.view. Pide ver a la persona.';
revoke execute on function core.user_sheet_state(uuid) from public;
grant execute on function core.user_sheet_state(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Guardar la ficha
-- ---------------------------------------------------------------------------
create function core.save_user_sheet(p_user_id uuid, p_expected_stamp text, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group   uuid := core.user_group(p_user_id);
  v_c       jsonb;
  v_item    jsonb;
  v_r       jsonb;
  v_why     text;
  -- El nombre pide más que el puesto y el área.
  v_names   boolean := p_changes -> 'profile' ?| array['first_name', 'last_name'];
  v_first   text;
  v_last    text;
  v_old_first text;
  v_old_last  text;
  v_a       core.user_role_assignments;
  -- Lo que se estaba haciendo cuando la base lo rechazó: el registro lleva el rol y el lugar.
  v_op      text;
  v_detail  jsonb;
  v_dg      uuid;
  v_db      uuid;
  v_dr      uuid;
  v_removed int := 0;
  v_pending int := 0;
  v_waiting int := 0;
  v_uuid    constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if not core.current_session_ok() or not core.can_view_user(p_user_id) then
    return core.deny('core.save_user_sheet', 'La persona no existe o no la podés ver.', p_user_id, null, v_group);
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 3 and 500 then
    raise exception 'Escribí el motivo de los cambios (de 3 a 500 caracteres).' using errcode = '22023';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'object'
     or not exists (select 1 from jsonb_each(p_changes) c where c.value not in ('{}'::jsonb, '[]'::jsonb, 'null'::jsonb)) then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, array['profile', 'roles_add', 'roles_remove']);
  -- Solo claves conocidas, antes de registrar nada: el registro de seguridad no se borra (revisión de seguridad, M1).
  if p_changes ? 'profile' then
    perform org.check_keys(p_changes -> 'profile', array['first_name', 'last_name', 'job_title', 'area_id']);
  end if;

  -- Quien no puede, no llega a tomar los bloqueos (revisión de seguridad, m2).
  if p_user_id = core.current_actor_id() then
    v_why := 'No podés hacer esto sobre tu propia cuenta.';
  elsif p_changes ? 'profile' then
    v_why := case when v_names then core.cannot_edit_user(p_user_id, 'users.manage') else core.cannot_place_user(p_user_id) end;
  elsif not core.has_permission_anywhere('roles.assign') then
    v_why := 'No tenés permiso para dar ni quitar roles.';
  end if;
  if v_why is not null then
    return core.deny('core.save_user_sheet', v_why, p_user_id,
                     jsonb_build_object('changes', (select jsonb_agg(k) from jsonb_object_keys(p_changes) k)), v_group);
  end if;

  -- Dos guardados de la misma ficha van de a uno. Primero los roles del grupo y después la persona (el mismo orden que
  -- suspender y desactivar). El permiso se mira con el bloqueo tomado: otra transacción pudo haberlo quitado.
  perform core.lock_group_roles(v_group);
  perform 1 from core.user_profiles where id = p_user_id for no key update;
  if not core.current_session_ok() or not core.can_view_user(p_user_id) then
    return core.deny('core.save_user_sheet', 'La persona no existe o no la podés ver.', p_user_id, null, v_group);
  end if;
  if p_changes ? 'profile' then
    v_why := case when v_names then core.cannot_edit_user(p_user_id, 'users.manage') else core.cannot_place_user(p_user_id) end;
    if v_why is not null then
      return core.deny('core.save_user_sheet', v_why, p_user_id,
                       jsonb_build_object('changes', jsonb_build_array('profile')), v_group);
    end if;
  end if;
  if p_expected_stamp is null or core.user_sheet_stamp_internal(p_user_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió esta ficha mientras la editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;

  -- Todo o nada: un rechazo deshace el bloque entero (con él se deshace su registro) y se vuelve a registrar afuera.
  begin
    v_c := p_changes -> 'profile';
    if v_c is not null and v_c <> '{}'::jsonb then
      if exists (select 1 from jsonb_each(v_c) f where jsonb_typeof(f.value) not in ('string', 'null')) then
        raise exception 'Revisá los datos: van como texto.' using errcode = '22023';
      end if;
      if exists (select 1 from jsonb_each_text(v_c) f where length(btrim(f.value)) > 80) then
        raise exception 'El nombre, el apellido y el puesto tienen hasta 80 caracteres.' using errcode = '23514';
      end if;
      -- El espacio duro que viene pegado de Word o Excel se guarda como espacio.
      select case when v_c ? 'first_name' then nullif(btrim(replace(v_c ->> 'first_name', chr(160), ' ')), '') else u.first_name end,
             case when v_c ? 'last_name' then nullif(btrim(replace(v_c ->> 'last_name', chr(160), ' ')), '') else u.last_name end,
             u.first_name, u.last_name
        into v_first, v_last, v_old_first, v_old_last
        from core.user_profiles u where u.id = p_user_id;
      if (v_c ? 'first_name' and v_first is null) or (v_c ? 'last_name' and v_last is null) then
        raise exception 'El nombre y el apellido no pueden quedar vacíos.' using errcode = '23514';
      end if;
      if v_c ? 'first_name' or v_c ? 'last_name' then
        perform core.check_person_name(v_first, v_last);
      end if;
      -- El puesto puede llamarse como un rol (Jefe de Cocina), pero no imitar al sistema.
      if v_c ? 'job_title'
         and (core.has_hidden_characters(v_c ->> 'job_title')
              or lower(btrim(normalize(coalesce(v_c ->> 'job_title', ''), nfkc))) ~ '^(super[^a-z]*admin.*|sistema|system)$') then
        raise exception 'Ese puesto se confunde con el sistema: escribí el puesto real.' using errcode = '22023';
      end if;
      -- Un área nueva está en uso y es de un local donde la persona trabaja y la sesión administra.
      if nullif(v_c ->> 'area_id', '') is not null then
        if (v_c ->> 'area_id') !~* v_uuid then
          raise exception 'Elegí un área de un local donde trabaja y que administrás.' using errcode = '22023';
        end if;
        if not exists (select 1 from core.user_area_ids(p_user_id) a (id) where a.id = (v_c ->> 'area_id')::uuid) then
          v_op := 'core.save_user_sheet';
          v_detail := jsonb_build_object('area_id', (v_c ->> 'area_id')::uuid);
          v_dg := v_group;
          v_r := jsonb_build_object('message', 'Elegí un área de un local donde trabaja y que administrás.');
          raise exception 'rechazado' using errcode = 'LF001';
        end if;
      end if;
      perform core.set_change_context(p_reason, 'manual');
      update core.user_profiles
         set first_name = v_first,
             last_name  = v_last,
             job_title  = case when v_c ? 'job_title' then nullif(btrim(replace(v_c ->> 'job_title', chr(160), ' ')), '') else job_title end,
             area_id    = case when v_c ? 'area_id' then nullif(v_c ->> 'area_id', '')::uuid else area_id end
       where id = p_user_id;
      -- Que otro le cambie el nombre cambia cómo se la ve en todo el sistema: la persona se entera.
      if v_first is distinct from v_old_first or v_last is distinct from v_old_last then
        insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
        values (p_user_id, v_group, 'account_changed', 'Cambiaron tu nombre',
                left(format('Ahora figurás como «%s %s». Lo cambió %s. Si está mal, corregilo en Mi cuenta.',
                            v_first, v_last, core.display_name(core.current_actor_id())), 500), '/mi-cuenta');
      end if;
    end if;

    -- Primero se quitan y después se dan: así se puede cambiar un rol por otro en un guardado.
    v_c := p_changes -> 'roles_remove';
    if v_c is not null then
      if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 20 then
        raise exception 'Los roles que se quitan van en una lista (hasta 20).' using errcode = '22023';
      end if;
      for v_item in select distinct e from jsonb_array_elements(v_c) e loop
        if jsonb_typeof(v_item) <> 'string' or (v_item #>> '{}') !~* v_uuid then
          raise exception 'Ese rol no es de esta persona.' using errcode = '22023';
        end if;
        select * into v_a from core.user_role_assignments
         where id = (v_item #>> '{}')::uuid and user_id = p_user_id and deleted_at is null and group_id = v_group;
        v_op := 'core.revoke_role';
        if v_a.id is null then
          v_detail := jsonb_build_object('assignment_id', (v_item #>> '{}')::uuid);
          v_dg := v_group; v_db := null; v_dr := null;
          v_r := jsonb_build_object('message', 'Ese rol no es de esta persona.');
          raise exception 'rechazado' using errcode = 'LF001';
        end if;
        v_detail := jsonb_build_object('assignment_id', v_a.id,
                                       'role', (select r.code from core.roles r where r.id = v_a.role_id));
        v_dg := v_a.group_id; v_db := v_a.brand_id; v_dr := v_a.restaurant_id;
        v_r := core.revoke_role(v_a.id, p_reason);
        if v_r ->> 'result' = 'denied' then
          raise exception 'rechazado' using errcode = 'LF001';
        end if;
        v_removed := v_removed + (v_r ->> 'result' = 'applied')::int;
        v_pending := v_pending + (v_r ->> 'result' = 'pending_approval')::int;
      end loop;
    end if;

    v_c := p_changes -> 'roles_add';
    if v_c is not null then
      if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 20 then
        raise exception 'Los roles que se dan van en una lista (hasta 20).' using errcode = '22023';
      end if;
      for v_item in select distinct e from jsonb_array_elements(v_c) e loop
        perform org.check_keys(v_item, array['role_code', 'scope_type', 'group_id', 'brand_id', 'restaurant_id']);
        if coalesce(v_item ->> 'role_code', '') !~ '^[a-z_]{1,60}$'
           or coalesce(v_item ->> 'scope_type', '') not in ('group', 'brand', 'restaurant')
           or coalesce(v_item ->> 'group_id', '') !~* v_uuid
           or coalesce(nullif(v_item ->> 'brand_id', ''), v_item ->> 'group_id') !~* v_uuid
           or coalesce(nullif(v_item ->> 'restaurant_id', ''), v_item ->> 'group_id') !~* v_uuid then
          raise exception 'Elegí el rol y el lugar.' using errcode = '22023';
        end if;
        v_op := 'core.assign_role';
        v_detail := v_item - 'role_code' || jsonb_build_object('role', v_item ->> 'role_code');
        v_dg := (v_item ->> 'group_id')::uuid;
        v_db := nullif(v_item ->> 'brand_id', '')::uuid;
        v_dr := nullif(v_item ->> 'restaurant_id', '')::uuid;
        if v_dg is distinct from v_group then
          v_r := jsonb_build_object('message', 'No tenés permiso para dar roles en ese lugar.');
          raise exception 'rechazado' using errcode = 'LF001';
        end if;
        v_r := core.assign_role(p_user_id, v_item ->> 'role_code', (v_item ->> 'scope_type')::core.scope_type,
                                v_dg, v_db, v_dr, null, p_reason);
        if v_r ->> 'result' = 'denied' then
          raise exception 'rechazado' using errcode = 'LF001';
        end if;
        v_waiting := v_waiting + (v_r ->> 'result' = 'pending_approval')::int;
      end loop;
    end if;

    -- Cambiar un rol por otro que espera una aprobación dejaría a la persona sin el de antes (y quizás sin ninguno)
    -- hasta que alguien decida. Primero se pide el nuevo.
    if v_removed > 0 and v_waiting > 0 then
      raise exception 'El rol nuevo espera una aprobación: guardalo primero y, cuando lo aprueben, quitá el anterior.'
        using errcode = '23514';
    end if;
  exception
    when sqlstate 'LF001' then
      -- El rechazo se registra igual que por assign_role o revoke_role: con el rol y el lugar.
      return core.deny(v_op, v_r ->> 'message', p_user_id, v_detail || jsonb_build_object('from', 'core.save_user_sheet'),
                       v_dg, v_db, v_dr);
  end;

  v_pending := v_pending + v_waiting;
  return jsonb_build_object(
    'result', case when v_pending > 0 then 'pending_approval' else 'applied' end,
    'pending', v_pending,
    -- Quitarle su último rol puede dejarla fuera de lo que esta sesión ve: la pantalla vuelve a la lista.
    'still_visible', core.can_view_user(p_user_id),
    'message', case when v_pending = 0 then 'Cambios guardados.'
                    when v_pending = 1 then 'Guardado. Un cambio de rol queda pendiente hasta que otra persona lo apruebe.'
                    else 'Guardado. ' || v_pending || ' cambios de rol quedan pendientes hasta que otra persona los apruebe.' end);
end
$$;
comment on function core.save_user_sheet(uuid, text, jsonb, text) is
  'Guarda la ficha de una persona en una transacción, con motivo y sello: profile (nombre y apellido: pide users.manage y tener todos sus permisos; puesto y área: solo users.manage en todos sus lugares), roles_remove (asignaciones) y roles_add (rol y lugar). Los roles pasan por revoke_role y assign_role, con sus permisos y aprobaciones. Si algo se rechaza, no queda nada y el rechazo se registra.';
revoke execute on function core.save_user_sheet(uuid, text, jsonb, text) from public;
grant execute on function core.save_user_sheet(uuid, text, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Cerrar todas las sesiones de otra persona
-- ---------------------------------------------------------------------------
create function core.close_user_sessions(p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_why   text;
  v_group uuid := core.user_group(p_user_id);
  v_count int;
begin
  if p_reason is null or length(btrim(p_reason)) not between 3 and 500 then
    raise exception 'Escribí el motivo (de 3 a 500 caracteres).' using errcode = '22023';
  end if;
  v_why := core.cannot_edit_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.close_user_sessions', v_why, p_user_id, null, v_group);
  end if;
  -- Con el bloqueo tomado se vuelve a mirar: en el medio le pudieron dar un rol más alto (los mismos bloqueos que suspender).
  perform core.lock_group_roles(v_group);
  perform 1 from core.user_profiles where id = p_user_id for no key update;
  v_why := core.cannot_edit_user(p_user_id, 'users.deactivate');
  if v_why is not null then
    return core.deny('core.close_user_sessions', v_why, p_user_id, null, v_group);
  end if;
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    return jsonb_build_object('result', 'applied', 'message', 'No tenía sesiones abiertas.');
  end if;
  perform audit.log_security_event('sessions_closed', 'core.close_user_sessions', btrim(p_reason), p_user_id, null,
                                   jsonb_build_object('sessions', v_count), v_group);
  -- La persona se entera de quién fue (revisión de seguridad, M4).
  perform core.set_change_context(p_reason, 'manual');
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  values (p_user_id, v_group, 'account_changed', 'Cerraron tus sesiones',
          left(format('%s cerró todas tus sesiones. Tu cuenta sigue activa: si no sabés por qué, preguntale.',
                      core.display_name(core.current_actor_id())), 500), '/mi-cuenta');
  return jsonb_build_object('result', 'applied',
    'message', case when v_count = 1 then 'Se cerró 1 sesión.' else 'Se cerraron ' || v_count || ' sesiones.' end);
end
$$;
comment on function core.close_user_sessions(uuid, text) is
  'Cierra todas las sesiones de otra persona, sin suspenderla (puede volver a entrar). Pide users.deactivate sobre todos sus roles y un motivo, y queda en el registro de seguridad. Las propias se cierran en Mi cuenta.';
revoke execute on function core.close_user_sessions(uuid, text) from public;
grant execute on function core.close_user_sessions(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. La lista de rechazos de la ficha: los de la persona, la misma regla que el indicador
-- ---------------------------------------------------------------------------
-- Igual que la versión de 20261023120000, salvo el filtro de rejected_attempts: antes sumaba lo que otros intentaron
-- sobre su cuenta, como si lo hubiera intentado ella.
create or replace function core.user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p     core.user_profiles;
  v_group uuid;
  v_admin boolean;
begin
  if not core.current_session_ok() or not core.can_view_user(p_user_id) then
    return null;
  end if;
  select * into v_p from core.user_profiles where id = p_user_id and deleted_at is null;
  if not found then
    return null;
  end if;
  v_group := core.user_group(p_user_id);
  -- El último acceso, quién invitó y los motivos los ve solo quien administra a la persona
  -- (respuesta 2 de Joaco).
  v_admin := core.can_administer_user(p_user_id);
  return jsonb_build_object(
    'id', v_p.id,
    'username', v_p.username,
    'job_title', v_p.job_title,
    'area_id', v_p.area_id,
    'area_name', (select ar.name || ' · ' || r.name from org.areas ar join org.restaurants r on r.id = ar.restaurant_id where ar.id = v_p.area_id),
    'can_view_admin_details', v_admin,
    -- El camino de cada acción sobre la cuenta, para esta sesión (vacío = el de siempre).
    'governance', jsonb_build_object('deactivate', core.governance_workflow(p_user_id, 'deactivate'),
                                     'reactivate', core.governance_workflow(p_user_id, 'reactivate'),
                                     'suspend', core.governance_workflow(p_user_id, 'suspend')),
    'activated_at', case when v_admin then v_p.activated_at end,
    'last_seen_at', case when v_admin then v_p.last_seen_at end,
    'invited_by_name', case when v_admin then core.display_name(v_p.invited_by) end,
    'status', v_p.status,
    'suspended_at', v_p.suspended_at,
    'suspension_reason', case when v_admin then v_p.suspension_reason end,
    'suspended_by_name', case when v_admin then core.display_name(v_p.suspended_by) end,
    'deactivated_at', v_p.deactivated_at,
    'deactivation_reason', case when v_admin then v_p.deactivation_reason end,
    'deactivated_by_name', case when v_admin then core.display_name(v_p.deactivated_by) end,
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
               where (s.event_type in ('login_failed', 'account_locked') and s.user_id = p_user_id)
                  or (s.event_type = 'operation_denied' and s.actor_id = p_user_id)
               order by s.occurred_at desc limit 20) s), '[]'::jsonb) end
  );
end
$$;
