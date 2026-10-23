-- El rol Director de Marca solo se da para una marca (decisión de Joaco del 2026-10-23, ADR-0017).
-- Para todo el grupo ya está Dirección General: un Director de Marca de todo el grupo aprobaría
-- roles sensibles en todos los locales (revisión de seguridad, m3). Si hace falta cambiarlo, se
-- hace con otra migración.
-- También la tabla exige el alcance de los roles que gobiernan: Superadministrador y Dirección
-- General, solo para todo el grupo; Director de Marca, solo para una marca (revisión de seguridad,
-- m2: hasta ahora solo lo controlaba assign_role).

-- ---------------------------------------------------------------------------
-- 1. El alcance de esos roles, en la tabla (para cualquier camino de escritura)
-- ---------------------------------------------------------------------------
create function core.enforce_role_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if new.deleted_at is null and (tg_op = 'INSERT' or new.role_id is distinct from old.role_id
                                 or new.scope_type is distinct from old.scope_type or old.deleted_at is not null) then
    select r.code into v_code from core.roles r where r.id = new.role_id;
    if v_code in ('superadmin', 'general_management') and new.scope_type <> 'group' then
      raise exception 'Ese rol solo se da para todo el grupo.' using errcode = '23514';
    end if;
    if v_code = 'brand_director' and new.scope_type <> 'brand' then
      raise exception 'El rol Director de Marca solo se da para una marca.' using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function core.enforce_role_scope() is
  'Trigger (BEFORE INSERT OR UPDATE) de user_role_assignments: Superadministrador y Dirección General, solo para todo el grupo; Director de Marca, solo para una marca (ADR-0017).';
revoke execute on function core.enforce_role_scope() from public;

create trigger validate_role_scope before insert or update on core.user_role_assignments
  for each row execute function core.enforce_role_scope();

-- Los datos que ya existen tienen que cumplir la regla.
do $$
begin
  if exists (
    select 1 from core.user_role_assignments a join core.roles r on r.id = a.role_id
     where a.deleted_at is null
       and ((r.code in ('superadmin', 'general_management') and a.scope_type <> 'group')
            or (r.code = 'brand_director' and a.scope_type <> 'brand'))) then
    raise exception 'Hay roles de Superadministrador, Dirección o Director de Marca con un alcance que no corresponde: hay que corregirlos antes de aplicar esta migración.';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Al pedir el rol, el mensaje claro
-- ---------------------------------------------------------------------------
create or replace function core.assign_role(p_user_id uuid, p_role_code text, p_scope_type core.scope_type, p_group_id uuid,
                                            p_brand_id uuid default null, p_restaurant_id uuid default null,
                                            p_valid_until timestamptz default null, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor      uuid := core.current_actor_id();
  v_role       core.roles;
  v_missing    text[];
  v_superadmin boolean;
  v_workflow   text;
  v_details    jsonb;
  v_request    uuid;
  v_assignment uuid;
begin
  v_details := jsonb_build_object('role', p_role_code, 'scope_type', p_scope_type, 'group_id', p_group_id,
                                  'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id);
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'El motivo es obligatorio.' using errcode = '22023';
  end if;
  select * into v_role from core.roles where code = p_role_code and deleted_at is null;
  if not found then
    raise exception 'No existe el rol %.', p_role_code using errcode = '22023';
  end if;

  -- Permisos primero: no se revela nada de la persona ni de la estructura sin permiso.
  -- (Un alcance que no cuadra con la estructura también da "sin permiso".)
  if not core.has_permission_for_scope('roles.assign', p_scope_type, p_group_id, p_brand_id, p_restaurant_id) then
    return core.deny('core.assign_role', 'No tenés permiso para dar roles en ese lugar.', p_user_id, v_details,
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;
  if p_user_id = v_actor then
    return core.deny('core.assign_role', 'Nadie se puede dar roles a sí mismo.', p_user_id, v_details,
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;
  v_superadmin := core.has_role_for_scope(array['superadmin'], 'group', p_group_id);
  v_missing := core.missing_permissions_for_role(v_role.id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
  if cardinality(v_missing) > 0 and not v_superadmin then
    return core.deny('core.assign_role',
                     'No podés dar un rol con permisos que vos no tenés en ese lugar: ' || array_to_string(v_missing, ', ') || '.',
                     p_user_id, v_details || jsonb_build_object('missing_permissions', v_missing),
                     p_group_id, p_brand_id, p_restaurant_id);
  end if;

  -- Errores de datos.
  if v_role.code in ('superadmin', 'general_management') and p_scope_type <> 'group' then
    raise exception 'El rol % solo se da para todo el grupo.', v_role.name using errcode = '23514';
  end if;
  -- Director de Marca, solo para una marca: para todo el grupo ya está Dirección General (ADR-0017).
  if v_role.code = 'brand_director' and p_scope_type <> 'brand' then
    raise exception 'El rol % solo se da para una marca.', v_role.name using errcode = '23514';
  end if;
  -- Sin vencimiento: si no, el grupo podría quedarse sin ellos de un día para el otro.
  if v_role.code in ('superadmin', 'general_management') and p_valid_until is not null then
    raise exception 'El rol % no lleva fecha de vencimiento.', v_role.name using errcode = '23514';
  end if;
  perform core.check_scope(p_scope_type, p_group_id, p_brand_id, p_restaurant_id);
  if not exists (select 1 from core.user_profiles u where u.id = p_user_id and u.status = 'active' and u.deleted_at is null) then
    raise exception 'La persona no existe o su cuenta no está activa.' using errcode = '23514';
  end if;
  if not exists (select 1 from core.user_memberships m
                  where m.user_id = p_user_id and m.group_id = p_group_id and m.deleted_at is null
                    and m.starts_at <= now() and m.ends_at is null) then
    raise exception 'La persona no es miembro de ese grupo: primero hay que sumarla al grupo.' using errcode = '23514';
  end if;
  -- El lugar de la membresía limita los roles (respuesta 9 de Joaco).
  if not core.membership_covers(p_user_id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id) then
    raise exception 'La persona no trabaja en ese lugar: primero sumale una membresía de ese local, de su marca o de todo el grupo.'
      using errcode = '23514';
  end if;
  if exists (select 1 from core.user_role_assignments a
              where a.user_id = p_user_id and a.role_id = v_role.id and a.group_id = p_group_id
                and a.brand_id is not distinct from p_brand_id and a.restaurant_id is not distinct from p_restaurant_id
                and a.deleted_at is null) then
    raise exception 'La persona ya tiene ese rol en ese lugar.' using errcode = '23505';
  end if;
  perform core.check_person_separation(p_user_id, v_role.id, p_group_id);

  v_workflow := case
    when v_role.code = 'superadmin' then 'core.assign_superadmin'
    when cardinality(v_missing) > 0 then 'core.assign_by_superadmin'   -- excepción del superadmin
    when core.is_sensitive_role(v_role.id) then 'core.assign_sensitive_role'
  end;

  if v_workflow is not null then
    v_request := workflow.request_approval(v_workflow, p_group_id, p_brand_id, p_restaurant_id, p_user_id, null,
      jsonb_build_object('user_id', p_user_id, 'role_id', v_role.id, 'role_code', v_role.code, 'scope_type', p_scope_type,
                         'group_id', p_group_id, 'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id,
                         'valid_until', p_valid_until, 'role_permissions', to_jsonb(core.role_permission_codes(v_role.id))),
      -- Antes: los roles vigentes de la persona en el lugar del pedido (no los de otras marcas o
      -- locales, que quien ve la solicitud quizás no puede ver; revisión de seguridad, m3).
      jsonb_build_object('roles', coalesce((
        select jsonb_agg(r.code order by r.level)
          from core.user_role_assignments a join core.roles r on r.id = a.role_id
         where a.user_id = p_user_id and a.group_id = p_group_id and a.deleted_at is null
           and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())
           and (p_scope_type = 'group' or a.brand_id = p_brand_id)
           and (p_scope_type <> 'restaurant' or a.restaurant_id = p_restaurant_id)), '[]'::jsonb)),
      p_reason);
    return jsonb_build_object('result', 'pending_approval', 'request_id', v_request,
                              'message', 'Queda pendiente hasta que otra persona lo apruebe.');
  end if;

  perform core.set_change_context(p_reason, 'manual');
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_until)
  values (p_user_id, v_role.id, p_scope_type, p_group_id, p_brand_id, p_restaurant_id, p_valid_until)
  returning id into v_assignment;
  return jsonb_build_object('result', 'applied', 'assignment_id', v_assignment, 'message', 'Rol asignado.');
end
$$;
