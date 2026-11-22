-- Fichas del local y de la razón social en una pantalla: guardado en lote, en una sola transacción, con motivo y sello
-- de concurrencia, como purchasing.save_supplier_sheet (Tanda 1 de las correcciones de Soy, ADR-0061).
--
-- * Local: datos, ubicación, estado (En apertura · Abierto), razón social con su fecha y áreas, todo junto. Los
--   permisos por campo son los de siempre (ADR-0031): org.manage en el local para los datos y las áreas, en la marca
--   para el tipo y el estado, en el grupo para la razón social.
-- * Áreas: se agregan, se renombran y se quitan sin borrar (quedan inactivas con su historia). Agregar una con el
--   nombre de una inactiva la vuelve a activar.
-- * Cerrar y reabrir el local van aparte, con su motivo, como «Desactivar» del proveedor. Reabrir pide los datos
--   obligatorios.
-- * Razón social: los datos de ARCA y sus actividades, todo junto. Pide org.manage en el grupo.

-- ---------------------------------------------------------------------------
-- 1. Áreas activas e inactivas
-- ---------------------------------------------------------------------------
alter table org.areas add column is_active boolean not null default true;
comment on column org.areas.is_active is
  'Si el área está en uso. Quitarla desde la ficha del local la deja inactiva, con su historia; no se borra.';

-- ---------------------------------------------------------------------------
-- 2. Ficha del local
-- ---------------------------------------------------------------------------
create function org.restaurant_sheet_stamp_internal(p_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest((select updated_at from org.restaurants where id = p_id),
                  (select max(updated_at) from org.areas where restaurant_id = p_id))
$$;
comment on function org.restaurant_sheet_stamp_internal(uuid) is
  'Interna: el último cambio de la ficha de un local (el local y sus áreas).';
revoke execute on function org.restaurant_sheet_stamp_internal(uuid) from public;

-- Lo que la pantalla necesita además de lo que lee por RLS: el sello, lo que falta y qué puede hacer la sesión.
create function org.restaurant_sheet_state(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_r org.restaurants;
begin
  select * into v_r from org.restaurants where id = p_id and deleted_at is null;
  if v_r.id is null or not core.has_permission('org.view', p_id) then
    return null;
  end if;
  return jsonb_build_object(
    'stamp', org.restaurant_sheet_stamp_internal(p_id),
    'missing', to_jsonb(org.restaurant_missing(v_r)),
    'can_edit', core.has_permission('org.manage', p_id),
    'can_edit_brand_level', core.has_permission_in_brand('org.manage', v_r.brand_id),
    'can_edit_group_level', core.has_permission_in_group('org.manage', v_r.group_id));
end
$$;
comment on function org.restaurant_sheet_state(uuid) is
  'Para la ficha del local: el sello para guardar, los datos obligatorios que le faltan y qué puede cambiar la sesión (datos y áreas; tipo y estado; razón social). Pide org.view en el local.';
revoke execute on function org.restaurant_sheet_state(uuid) from public;
grant execute on function org.restaurant_sheet_state(uuid) to authenticated;

-- El texto de una clave, vacío como nulo; si la clave no viene, el valor de antes.
create function org.text_or(p_obj jsonb, p_key text, p_old text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_obj ? p_key then nullif(btrim(p_obj ->> p_key), '') else p_old end
$$;
comment on function org.text_or(jsonb, text, text) is
  'Interna: el texto de una clave del objeto (vacío = nulo) o, si la clave no viene, el valor anterior.';
revoke execute on function org.text_or(jsonb, text, text) from public;

create function org.save_restaurant_sheet(p_id uuid, p_expected_stamp timestamptz, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r     org.restaurants;
  v_c     jsonb;
  v_item  jsonb;
  v_area  org.areas;
  v_name  text;
  v_from  date;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  select * into v_r from org.restaurants where id = p_id and deleted_at is null;
  perform org.require(v_r.id is not null and core.has_permission('org.manage', p_id), 'editar este local');
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, array['restaurant', 'legal_entity', 'areas']);
  if p_changes = '{}'::jsonb then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  -- Dos guardados de la misma ficha van de a uno; el segundo ve que el primero cambió algo.
  perform 1 from org.restaurants where id = p_id for update;
  if p_expected_stamp is null or org.restaurant_sheet_stamp_internal(p_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió este local mientras lo editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');

  -- La razón social va primero: así el local guarda su tramo con la fecha elegida antes que los demás cambios.
  v_c := p_changes -> 'legal_entity';
  if v_c is not null then
    perform org.check_keys(v_c, array['legal_entity_id', 'valid_from']);
    perform org.require(core.has_permission_in_group('org.manage', v_r.group_id), 'elegir la razón social de este local');
    if coalesce(v_c ->> 'legal_entity_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or not exists (select 1 from org.legal_entities
                       where id = (v_c ->> 'legal_entity_id')::uuid and group_id = v_r.group_id and deleted_at is null) then
      raise exception 'Elegí una razón social vigente del grupo.' using errcode = '22023';
    end if;
    v_from := coalesce(nullif(v_c ->> 'valid_from', '')::date, v_today);
    -- La razón social vale desde que se guarda (las facturas y los costos de hoy ya la usan): la fecha no puede ser
    -- futura. Un cambio programado se guarda ese día.
    if v_from < date '2000-01-01' then
      raise exception 'La fecha desde la que factura no puede ser anterior al 2000.' using errcode = '22023';
    end if;
    if v_from > v_today then
      raise exception 'La fecha desde la que factura no puede ser futura: guardá el cambio ese día.' using errcode = '22023';
    end if;
    if exists (select 1 from org.restaurant_legal_entities
                where restaurant_id = p_id and deleted_at is null and valid_from > v_from) then
      raise exception 'Ya hay una razón social desde una fecha posterior: elegí una fecha más nueva.' using errcode = '23514';
    end if;
    perform set_config('app.legal_entity_from', v_from::text, true);
    update org.restaurants set legal_entity_id = (v_c ->> 'legal_entity_id')::uuid where id = p_id;
    perform set_config('app.legal_entity_from', '', true);
  end if;

  v_c := p_changes -> 'restaurant';
  if v_c is not null then
    perform org.check_keys(v_c, array['zone', 'opened_on', 'address', 'locality', 'province', 'postal_code', 'phone',
                                      'latitude', 'longitude', 'geo_status', 'geo_label', 'site_type', 'state']);
    if v_c ? 'site_type' or v_c ? 'state' then
      perform org.require(core.has_permission_in_brand('org.manage', v_r.brand_id), 'cambiar el tipo o el estado de este local');
    end if;
    if v_c ? 'zone' and nullif(btrim(v_c ->> 'zone'), '') is null then
      raise exception 'La zona no puede quedar vacía: arma el nombre del local.' using errcode = '23514';
    end if;
    if coalesce(v_c ->> 'zone', '') ~ '[<>]' or coalesce(v_c ->> 'geo_label', '') ~ '[<>]' then
      raise exception 'Los nombres no pueden llevar < ni >.' using errcode = '23514';
    end if;
    if v_c ? 'site_type' and not (v_c ->> 'site_type' = any (enum_range(null::org.site_type)::text[])) then
      raise exception 'Elegí el tipo de local.' using errcode = '22023';
    end if;
    if v_c ? 'state' and coalesce(v_c ->> 'state', '') not in ('opening', 'open') then
      raise exception 'Elegí En apertura o Abierto. Para cerrar el local, usá «Cerrar el local».' using errcode = '22023';
    end if;
    if v_c ? 'state' and v_r.status <> 'active' then
      raise exception 'El local está cerrado: reabrilo con «Reabrir el local».' using errcode = '23514';
    end if;
    if v_c ? 'geo_status' and nullif(v_c ->> 'geo_status', '') is not null
       and not (v_c ->> 'geo_status' = any (enum_range(null::org.geo_status)::text[])) then
      raise exception 'La ubicación en el mapa no es válida.' using errcode = '22023';
    end if;
    update org.restaurants
       set zone        = org.text_or(v_c, 'zone', zone),
           opened_on   = case when v_c ? 'opened_on' then nullif(v_c ->> 'opened_on', '')::date else opened_on end,
           address     = org.text_or(v_c, 'address', address),
           locality    = org.text_or(v_c, 'locality', locality),
           province    = org.text_or(v_c, 'province', province),
           postal_code = upper(org.text_or(v_c, 'postal_code', postal_code)),
           phone       = org.text_or(v_c, 'phone', phone),
           latitude    = case when v_c ? 'latitude' then nullif(v_c ->> 'latitude', '')::numeric else latitude end,
           longitude   = case when v_c ? 'longitude' then nullif(v_c ->> 'longitude', '')::numeric else longitude end,
           geo_status  = case when v_c ? 'geo_status' then nullif(v_c ->> 'geo_status', '')::org.geo_status
                              else geo_status end,
           geo_label   = org.text_or(v_c, 'geo_label', geo_label),
           site_type   = coalesce(nullif(v_c ->> 'site_type', '')::org.site_type, site_type),
           opening     = case when v_c ? 'state' then v_c ->> 'state' = 'opening' else opening end
     where id = p_id;
  end if;

  -- Áreas: cada una con id (cambia de nombre o se quita con remove) o sin id (nueva).
  v_c := p_changes -> 'areas';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 30 then
      raise exception 'Las áreas van en una lista (hasta 30).' using errcode = '22023';
    end if;
    for v_item in select * from jsonb_array_elements(v_c) loop
      perform org.check_keys(v_item, array['id', 'name', 'remove']);
      v_name := nullif(btrim(v_item ->> 'name'), '');
      if v_item ? 'id' then
        select * into v_area from org.areas
         where id = (v_item ->> 'id')::uuid and restaurant_id = p_id and deleted_at is null;
        if v_area.id is null then
          raise exception 'Esa área no es de este local.' using errcode = '22023';
        end if;
        if coalesce((v_item ->> 'remove')::boolean, false) then
          update org.areas set is_active = false where id = v_area.id;
        elsif v_item ? 'name' then
          if v_name is null then
            raise exception 'El nombre del área no puede quedar vacío.' using errcode = '23514';
          end if;
          update org.areas set name = v_name, is_active = true where id = v_area.id;
        end if;
      else
        if v_name is null then
          raise exception 'Escribí el nombre del área nueva.' using errcode = '23514';
        end if;
        update org.areas set is_active = true
         where restaurant_id = p_id and deleted_at is null and lower(name) = lower(v_name) and not is_active;
        if not found then
          insert into org.areas (group_id, restaurant_id, name) values (v_r.group_id, p_id, v_name);
        end if;
      end if;
    end loop;
  end if;

  return jsonb_build_object('stamp', org.restaurant_sheet_stamp_internal(p_id));
exception
  when unique_violation then
    raise exception 'Ya hay un local o un área con ese nombre: elegí otro.' using errcode = '23505';
  -- Lo mal formado, en palabras y no con el error crudo (los mensajes propios de la base pasan tal cual).
  when check_violation or foreign_key_violation then
    get stacked diagnostics v_name = constraint_name;
    case v_name
      when 'restaurants_geo_check' then
        raise exception 'La ubicación en el mapa no está completa: buscá la dirección de nuevo.' using errcode = '23514';
      when 'restaurants_province_fkey' then
        raise exception 'Elegí la provincia de la lista.' using errcode = '23514';
      when 'restaurants_postal_code_check' then
        raise exception 'El código postal tiene 4 cifras o el CPA (por ejemplo, B1713ABC).' using errcode = '23514';
      when 'restaurants_phone_check' then
        raise exception 'El teléfono lleva números, espacios, +, guiones y paréntesis (de 6 a 30).' using errcode = '23514';
      else
        raise;
    end case;
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'Revisá los datos: alguno no tiene el formato esperado (una fecha, un número o un área).'
      using errcode = '22023';
end
$$;
comment on function org.save_restaurant_sheet(uuid, timestamptz, jsonb, text) is
  'Guarda la ficha de un local en una transacción, con motivo y sello: restaurant (datos, ubicación, tipo y estado En apertura u Abierto), legal_entity (razón social y desde qué fecha) y areas (alta, nombre y baja sin borrar). Pide org.manage en el local; el tipo y el estado, en la marca; la razón social, en el grupo. Devuelve el sello nuevo.';
revoke execute on function org.save_restaurant_sheet(uuid, timestamptz, jsonb, text) from public;
grant execute on function org.save_restaurant_sheet(uuid, timestamptz, jsonb, text) to authenticated;

create function org.close_restaurant(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r org.restaurants;
begin
  select * into v_r from org.restaurants where id = p_id and deleted_at is null;
  perform org.require(v_r.id is not null and core.has_permission_in_brand('org.manage', v_r.brand_id),
                      'cerrar este local');
  if v_r.status <> 'active' then
    raise exception 'El local ya está cerrado.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.restaurants set status = 'inactive' where id = p_id;
end
$$;
comment on function org.close_restaurant(uuid, text) is
  'Cierra un local (queda con su historia; un local cerrado no da permisos). Pide org.manage en la marca y un motivo.';
revoke execute on function org.close_restaurant(uuid, text) from public;
grant execute on function org.close_restaurant(uuid, text) to authenticated;

create function org.reopen_restaurant(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r org.restaurants;
begin
  select * into v_r from org.restaurants where id = p_id and deleted_at is null;
  perform org.require(v_r.id is not null and core.has_permission_in_brand('org.manage', v_r.brand_id),
                      'reabrir este local');
  if v_r.status = 'active' then
    raise exception 'El local ya está abierto.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Vuelve como estaba: Abierto (el trigger pide los datos obligatorios) o, si se cerró antes de abrir, En apertura.
  update org.restaurants set status = 'active' where id = p_id;
end
$$;
comment on function org.reopen_restaurant(uuid, text) is
  'Reabre un local cerrado: vuelve a Abierto si tiene sus 7 datos obligatorios. Pide org.manage en la marca y un motivo.';
revoke execute on function org.reopen_restaurant(uuid, text) from public;
grant execute on function org.reopen_restaurant(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Ficha de la razón social
-- ---------------------------------------------------------------------------
create function org.legal_entity_sheet_stamp_internal(p_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select greatest((select updated_at from org.legal_entities where id = p_id),
                  (select max(updated_at) from org.legal_entity_activities where legal_entity_id = p_id),
                  (select max(created_at) from org.legal_entity_documents where legal_entity_id = p_id))
$$;
comment on function org.legal_entity_sheet_stamp_internal(uuid) is
  'Interna: el último cambio de la ficha de una razón social (sus datos, sus actividades y sus constancias).';
revoke execute on function org.legal_entity_sheet_stamp_internal(uuid) from public;

create function org.legal_entity_sheet_state(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_e    org.legal_entities;
  v_last date;
begin
  select * into v_e from org.legal_entities where id = p_id and deleted_at is null;
  if v_e.id is null or not org.can_see_legal_entity(p_id) then
    return null;
  end if;
  select max(issued_on) into v_last from org.legal_entity_documents where legal_entity_id = p_id;
  return jsonb_build_object(
    'stamp', org.legal_entity_sheet_stamp_internal(p_id),
    'missing', to_jsonb(org.legal_entity_missing(v_e)),
    'document_issued_on', v_last,
    'document_status', org.document_status(v_last),
    'can_edit', core.has_permission_in_group('org.manage', v_e.group_id));
end
$$;
comment on function org.legal_entity_sheet_state(uuid) is
  'Para la ficha de la razón social: el sello, los obligatorios que faltan, la fecha y el estado de la última constancia y si la sesión la puede editar. Pide verla (org.can_see_legal_entity).';
revoke execute on function org.legal_entity_sheet_state(uuid) from public;
grant execute on function org.legal_entity_sheet_state(uuid) to authenticated;

create function org.save_legal_entity_sheet(p_id uuid, p_expected_stamp timestamptz, p_changes jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e          org.legal_entities;
  v_c          jsonb;
  v_item       jsonb;
  v_act        org.legal_entity_activities;
  v_constraint text;
begin
  select * into v_e from org.legal_entities where id = p_id and deleted_at is null;
  perform org.require(v_e.id is not null and core.has_permission_in_group('org.manage', v_e.group_id),
                      'editar esta razón social');
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo de los cambios.' using errcode = '22023';
  end if;
  perform org.check_keys(p_changes, array['entity', 'activities']);
  if p_changes = '{}'::jsonb then
    raise exception 'No hay cambios para guardar.' using errcode = '22023';
  end if;
  perform 1 from org.legal_entities where id = p_id for update;
  if p_expected_stamp is null or org.legal_entity_sheet_stamp_internal(p_id) is distinct from p_expected_stamp then
    raise exception 'Otra persona cambió esta razón social mientras la editabas: recargá la página para ver sus cambios.'
      using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');

  v_c := p_changes -> 'entity';
  if v_c is not null then
    perform org.check_keys(v_c, array['name', 'tax_id', 'vat_condition', 'legal_form', 'activity_start', 'trade_name',
                                      'fiscal_street', 'fiscal_locality', 'fiscal_postal_code', 'fiscal_province',
                                      'electronic_domicile', 'income_tax', 'gross_income_regime',
                                      'gross_income_number', 'gross_income_province', 'is_employer',
                                      'is_withholding_agent', 'is_perception_agent']);
    if (v_c ? 'name' and nullif(btrim(v_c ->> 'name'), '') is null)
       or (v_c ? 'tax_id' and nullif(btrim(v_c ->> 'tax_id'), '') is null)
       or (v_c ? 'vat_condition' and nullif(v_c ->> 'vat_condition', '') is null) then
      raise exception 'La razón social, el CUIT y el IVA no pueden quedar vacíos.' using errcode = '23514';
    end if;
    if v_c ? 'activity_start' and nullif(v_c ->> 'activity_start', '')::date
                                  > (now() at time zone 'America/Argentina/Buenos_Aires')::date then
      raise exception 'El inicio de actividades no puede ser una fecha futura.' using errcode = '22023';
    end if;
    update org.legal_entities
       set name                  = coalesce(org.text_or(v_c, 'name', name), name),
           tax_id                = case when v_c ? 'tax_id' then core.normalize_cuit(v_c ->> 'tax_id') else tax_id end,
           vat_condition         = coalesce(nullif(v_c ->> 'vat_condition', '')::org.vat_condition, vat_condition),
           legal_form            = case when v_c ? 'legal_form' then nullif(v_c ->> 'legal_form', '')::org.legal_form
                                        else legal_form end,
           activity_start        = case when v_c ? 'activity_start' then nullif(v_c ->> 'activity_start', '')::date
                                        else activity_start end,
           trade_name            = org.text_or(v_c, 'trade_name', trade_name),
           fiscal_street         = org.text_or(v_c, 'fiscal_street', fiscal_street),
           fiscal_locality       = org.text_or(v_c, 'fiscal_locality', fiscal_locality),
           fiscal_postal_code    = upper(org.text_or(v_c, 'fiscal_postal_code', fiscal_postal_code)),
           fiscal_province       = org.text_or(v_c, 'fiscal_province', fiscal_province),
           electronic_domicile   = lower(org.text_or(v_c, 'electronic_domicile', electronic_domicile)),
           income_tax            = case when v_c ? 'income_tax'
                                        then nullif(v_c ->> 'income_tax', '')::org.income_tax_status else income_tax end,
           gross_income_regime   = case when v_c ? 'gross_income_regime'
                                        then nullif(v_c ->> 'gross_income_regime', '')::org.gross_income_regime
                                        else gross_income_regime end,
           gross_income_number   = org.text_or(v_c, 'gross_income_number', gross_income_number),
           gross_income_province = org.text_or(v_c, 'gross_income_province', gross_income_province),
           is_employer           = coalesce((v_c ->> 'is_employer')::boolean, is_employer),
           is_withholding_agent  = coalesce((v_c ->> 'is_withholding_agent')::boolean, is_withholding_agent),
           is_perception_agent   = coalesce((v_c ->> 'is_perception_agent')::boolean, is_perception_agent)
     where id = p_id;
  end if;

  -- Actividades: con id (cambia o se quita con remove) o sin id (nueva). Si una pasa a principal, las demás dejan
  -- de serlo antes (hay una sola principal vigente).
  v_c := p_changes -> 'activities';
  if v_c is not null then
    if jsonb_typeof(v_c) <> 'array' or jsonb_array_length(v_c) > 30 then
      raise exception 'Las actividades van en una lista (hasta 30).' using errcode = '22023';
    end if;
    if exists (select 1 from jsonb_array_elements(v_c) e
                where coalesce((e ->> 'is_primary')::boolean, false) and not coalesce((e ->> 'remove')::boolean, false)) then
      update org.legal_entity_activities set is_primary = false
       where legal_entity_id = p_id and deleted_at is null and is_primary;
    end if;
    for v_item in select * from jsonb_array_elements(v_c) loop
      perform org.check_keys(v_item, array['id', 'code', 'description', 'is_primary', 'remove']);
      if v_item ? 'id' then
        select * into v_act from org.legal_entity_activities
         where id = (v_item ->> 'id')::uuid and legal_entity_id = p_id and deleted_at is null;
        if v_act.id is null then
          raise exception 'Esa actividad no es de esta razón social.' using errcode = '22023';
        end if;
        if coalesce((v_item ->> 'remove')::boolean, false) then
          update org.legal_entity_activities set deleted_at = now() where id = v_act.id;
        else
          update org.legal_entity_activities
             set code        = coalesce(org.text_or(v_item, 'code', code), code),
                 description = coalesce(org.text_or(v_item, 'description', description), description),
                 is_primary  = coalesce((v_item ->> 'is_primary')::boolean, is_primary)
           where id = v_act.id;
        end if;
      else
        if nullif(btrim(v_item ->> 'code'), '') is null or nullif(btrim(v_item ->> 'description'), '') is null then
          raise exception 'Cada actividad lleva su código de 6 cifras y su descripción.' using errcode = '23514';
        end if;
        insert into org.legal_entity_activities (group_id, legal_entity_id, code, description, is_primary)
        values (v_e.group_id, p_id, btrim(v_item ->> 'code'), btrim(v_item ->> 'description'),
                coalesce((v_item ->> 'is_primary')::boolean, false));
      end if;
    end loop;
  end if;

  return jsonb_build_object('stamp', org.legal_entity_sheet_stamp_internal(p_id));
exception
  when unique_violation or check_violation or foreign_key_violation then
    get stacked diagnostics v_constraint = constraint_name;
    case v_constraint
      when 'legal_entities_tax_id_key' then
        raise exception 'Ya hay una razón social con ese CUIT en el grupo.' using errcode = '23505';
      when 'legal_entities_tax_id_valid' then
        raise exception 'El CUIT no es válido: revisá los números.' using errcode = '23514';
      when 'legal_entities_tax_id_check' then
        raise exception 'El CUIT tiene 11 números (con o sin guiones).' using errcode = '23514';
      when 'legal_entities_electronic_domicile_check' then
        raise exception 'El domicilio fiscal electrónico es un correo (por ejemplo, fiscal@empresa.com).' using errcode = '23514';
      when 'legal_entities_fiscal_postal_code_check' then
        raise exception 'El código postal tiene 4 cifras o el CPA (por ejemplo, B1713ABC).' using errcode = '23514';
      when 'legal_entities_gross_income_number_check' then
        raise exception 'El número de Ingresos Brutos lleva números, puntos, barras o guiones.' using errcode = '23514';
      when 'legal_entities_fiscal_province_fkey', 'legal_entities_gross_income_province_fkey' then
        raise exception 'Elegí la provincia de la lista.' using errcode = '23514';
      when 'legal_entity_activities_code_key' then
        raise exception 'Esa actividad ya está cargada.' using errcode = '23505';
      when 'legal_entity_activities_primary_key' then
        raise exception 'Hay una sola actividad principal: marcá una.' using errcode = '23505';
      when 'legal_entity_activities_code_check' then
        raise exception 'El código de la actividad tiene 6 cifras.' using errcode = '23514';
      when 'legal_entity_activities_description_check' then
        raise exception 'La descripción de la actividad tiene hasta 200 caracteres.' using errcode = '23514';
      else
        raise;
    end case;
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'Revisá los datos: alguno no tiene el formato esperado (una fecha o una opción).'
      using errcode = '22023';
end
$$;
comment on function org.save_legal_entity_sheet(uuid, timestamptz, jsonb, text) is
  'Guarda la ficha de una razón social en una transacción, con motivo y sello: entity (los datos de la constancia de ARCA) y activities (alta, cambio y baja; una sola principal). Pide org.manage en el grupo. Devuelve el sello nuevo.';
revoke execute on function org.save_legal_entity_sheet(uuid, timestamptz, jsonb, text) from public;
grant execute on function org.save_legal_entity_sheet(uuid, timestamptz, jsonb, text) to authenticated;

-- El alta de razón social de antes, con el mensaje del CUIT inválido (antes decía «11 números» para todo).
create or replace function org.create_legal_entity(p_group_id uuid, p_name text, p_tax_id text, p_vat_condition text,
                                                   p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id         uuid;
  v_constraint text;
begin
  perform org.require(core.has_permission_in_group('org.manage', p_group_id), 'crear razones sociales en este grupo');
  if p_vat_condition is null or p_vat_condition not in ('registered', 'monotax', 'exempt') then
    raise exception 'Elegí la condición frente al IVA.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into org.legal_entities (group_id, name, tax_id, vat_condition)
  values (p_group_id, btrim(p_name), regexp_replace(coalesce(p_tax_id, ''), '[^0-9]', '', 'g'), p_vat_condition::org.vat_condition)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'Ya hay una razón social con ese CUIT en el grupo.' using errcode = '23505';
  when check_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'legal_entities_tax_id_valid' then
      raise exception 'El CUIT no es válido: revisá los números.' using errcode = '23514';
    end if;
    raise exception 'Revisá el nombre y el CUIT (11 números).' using errcode = '23514';
end
$$;

-- La edición suelta de antes (la usan el Panel hasta que llegue la ficha nueva y los scripts de staging): suma la
-- zona y no deja escribir el nombre a mano en un local con zona, porque ahí el nombre lo arma la base.
create or replace function org.update_restaurant(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r org.restaurants;
begin
  select * into v_r from org.restaurants where id = p_id;
  perform org.require(core.has_permission('org.manage', p_id), 'editar este local');
  perform org.check_keys(p_changes, array['name', 'zone', 'status', 'code', 'address', 'locality', 'legal_name', 'tax_id',
                                          'phone', 'opened_on', 'time_zone', 'site_type']);
  if p_changes ? 'status' then
    perform org.require(core.has_permission_in_brand('org.manage', v_r.brand_id), 'abrir o cerrar este local');
  end if;
  if p_changes ? 'site_type' then
    perform org.require(core.has_permission_in_brand('org.manage', v_r.brand_id), 'cambiar el tipo de este local');
  end if;
  if p_changes ? 'name' and nullif(btrim(coalesce(p_changes ->> 'zone', v_r.zone)), '') is not null then
    raise exception 'El nombre del local se arma con la marca y la zona: cambiá la zona.' using errcode = '23514';
  end if;
  if p_changes ? 'zone' and nullif(btrim(p_changes ->> 'zone'), '') is null then
    raise exception 'La zona no puede quedar vacía: arma el nombre del local.' using errcode = '23514';
  end if;
  -- El código solo se asigna a un local que no tiene; nunca se cambia ni se vacía (ADR-0061).
  if p_changes ? 'code' and (v_r.code is not null or nullif(btrim(p_changes ->> 'code'), '') is null) then
    raise exception 'El código del local no cambia: lo usan el historial y las órdenes de compra.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- Para los datos opcionales, una clave presente con texto vacío o null los borra.
  update org.restaurants
     set name       = coalesce(btrim(p_changes ->> 'name'), name),
         zone       = coalesce(btrim(p_changes ->> 'zone'), zone),
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
comment on function org.update_restaurant(uuid, jsonb, text) is
  'Edita un local de a un dato (la ficha nueva usa org.save_restaurant_sheet). Pide org.manage en el local; el estado y el tipo, en la marca. En un local con zona, el nombre lo arma la base. El código solo se asigna si faltaba.';

-- ---------------------------------------------------------------------------
-- 4. Lo de antes que acompaña las reglas nuevas (revisión de db-reviewer)
-- ---------------------------------------------------------------------------
-- Un local no se queda sin razón social: el historial (org.restaurant_legal_entities) quedaría mostrando la anterior
-- como vigente. Se cambia por otra.
create or replace function org.set_restaurant_legal_entity(p_restaurant_id uuid, p_legal_entity_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from org.restaurants where id = p_restaurant_id and deleted_at is null;
  -- Cambia si el costo va con o sin IVA: la elige solo quien administra todo el grupo (decisión de Joaco,
  -- 2026-11-02), no el Gerente ni el Director de una marca.
  perform org.require(v_group is not null and core.has_permission_in_group('org.manage', v_group),
                      'elegir la razón social de este local');
  if p_legal_entity_id is null
     or not exists (select 1 from org.legal_entities where id = p_legal_entity_id and group_id = v_group and deleted_at is null) then
    raise exception 'Elegí una razón social vigente del grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.restaurants set legal_entity_id = p_legal_entity_id where id = p_restaurant_id;
end
$$;
comment on function org.set_restaurant_legal_entity(uuid, uuid, text) is
  'Elige la razón social de un local (desde hoy; queda en su historial). No se puede dejar vacía: se cambia por otra. Pide org.manage en todo el grupo y un motivo.';

-- La edición suelta de antes, con el mensaje del CUIT inválido (como el alta).
create or replace function org.update_legal_entity(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group      uuid;
  v_constraint text;
begin
  select group_id into v_group from org.legal_entities where id = p_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('org.manage', v_group), 'editar esta razón social');
  perform org.check_keys(p_changes, array['name', 'tax_id', 'vat_condition']);
  if p_changes ? 'vat_condition' and coalesce(p_changes ->> 'vat_condition', '') not in ('registered', 'monotax', 'exempt') then
    raise exception 'Elegí la condición frente al IVA.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.legal_entities
     set name          = coalesce(btrim(p_changes ->> 'name'), name),
         tax_id        = coalesce(regexp_replace(p_changes ->> 'tax_id', '[^0-9]', '', 'g'), tax_id),
         vat_condition = coalesce((p_changes ->> 'vat_condition')::org.vat_condition, vat_condition)
   where id = p_id;
exception
  when unique_violation then
    raise exception 'Ya hay una razón social con ese CUIT en el grupo.' using errcode = '23505';
  when check_violation or not_null_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'legal_entities_tax_id_valid' then
      raise exception 'El CUIT no es válido: revisá los números.' using errcode = '23514';
    end if;
    raise exception 'Revisá el nombre y el CUIT (11 números).' using errcode = '23514';
end
$$;

-- El traspaso de un local a otra marca (ADR-0017), con lo nuevo: el código del local viejo pasa al nuevo (lo libera
-- con app.releasing_code, la única forma de quitarle el código a un local), el local nuevo hereda ubicación, tipo,
-- razón social y estado (En apertura o Abierto), y solo se copian las áreas activas. La zona no se copia: el nombre lo
-- eligió quien pidió el traspaso; se completa en la ficha.
create or replace function org.apply_transfer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req   workflow.approval_requests := workflow.approved_request(p_request_id);
  v_p     jsonb := v_req.proposed_changes;
  v_old   org.restaurants;
  v_new   uuid;
  v_brand uuid := (v_req.proposed_changes ->> 'target_brand_id')::uuid;
  v_code  text;
begin
  if not core.user_has_permission_for_scope(v_req.requested_by, 'org.transfer', 'group', v_req.group_id) then
    perform workflow.cannot_apply('quien lo pidió ya no puede traspasar locales');
  end if;
  select * into v_old from org.restaurants where id = (v_p ->> 'restaurant_id')::uuid for update;
  if v_old.deleted_at is not null or v_old.status <> 'active' then
    perform workflow.cannot_apply('el local ya no está operando');
  end if;
  if not exists (select 1 from org.brands b
                  where b.id = v_brand and b.group_id = v_old.group_id and b.deleted_at is null and b.status = 'active') then
    perform workflow.cannot_apply('la marca de destino ya no está vigente');
  end if;
  if exists (select 1 from org.restaurants x
              where x.brand_id = v_brand and x.deleted_at is null and lower(x.name) = lower(v_p ->> 'new_name')) then
    perform workflow.cannot_apply('ya hay un local con ese nombre en la marca de destino');
  end if;
  perform core.lock_group_roles(v_old.group_id);
  perform core.set_change_context('Traspaso de local aprobado (solicitud ' || p_request_id || ')', 'manual');

  -- El código corto pasa al local nuevo (el historial y las órdenes de compra siguen con él).
  v_code := v_old.code;
  if v_code is not null then
    perform set_config('app.releasing_code', v_old.id::text, true);
    update org.restaurants set code = null where id = v_old.id;
    perform set_config('app.releasing_code', '', true);
  end if;

  insert into org.restaurants (group_id, brand_id, name, code, address, locality, legal_name, tax_id, phone,
                               opened_on, time_zone, predecessor_id, site_type, opening, province, postal_code,
                               latitude, longitude, geo_status, geo_label, legal_entity_id)
  values (v_old.group_id, v_brand, v_p ->> 'new_name', v_code, v_old.address, v_old.locality, v_old.legal_name,
          v_old.tax_id, v_old.phone, v_old.opened_on, v_old.time_zone, v_old.id, v_old.site_type, v_old.opening,
          v_old.province, v_old.postal_code, v_old.latitude, v_old.longitude, v_old.geo_status, v_old.geo_label,
          v_old.legal_entity_id)
  returning id into v_new;

  insert into org.areas (group_id, restaurant_id, name)
  select a.group_id, v_new, a.name from org.areas a
   where a.restaurant_id = v_old.id and a.deleted_at is null and a.is_active;

  -- Quienes pasan con su rol trabajan en el local nuevo (respuesta 9): si su membresía era del
  -- local viejo o de la marca vieja, se les suma una del local nuevo.
  insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
  select distinct a.user_id, a.group_id, v_brand, v_new
    from core.user_role_assignments a
    join core.user_profiles u on u.id = a.user_id and u.status = 'active' and u.deleted_at is null
   where a.restaurant_id = v_old.id and a.deleted_at is null
     and (a.valid_until is null or a.valid_until > now())
     and not core.membership_covers(a.user_id, 'restaurant', a.group_id, v_brand, v_new);

  -- Los roles del local viejo pasan al nuevo (los vigentes y los que empiezan más adelante, con
  -- sus mismas fechas); los de personas bloqueadas y los ya vencidos solo se quitan.
  insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_from, valid_until)
  select a.user_id, a.role_id, 'restaurant', a.group_id, v_brand, v_new, greatest(a.valid_from, now()), a.valid_until
    from core.user_role_assignments a
    join core.user_profiles u on u.id = a.user_id and u.status = 'active' and u.deleted_at is null
   where a.restaurant_id = v_old.id and a.deleted_at is null
     and (a.valid_until is null or a.valid_until > now());
  update core.user_role_assignments set deleted_at = now() where restaurant_id = v_old.id and deleted_at is null;
  -- Las membresías del local viejo terminan con él (una que empezó en esta misma operación no
  -- puede terminar en el mismo instante: se borra).
  update core.user_memberships set deleted_at = now()
   where restaurant_id = v_old.id and deleted_at is null and ends_at is null and starts_at >= now();
  update core.user_memberships set ends_at = now()
   where restaurant_id = v_old.id and deleted_at is null and ends_at is null;

  update org.restaurants set status = 'inactive' where id = v_old.id;
end
$$;

-- Un área inactiva no se le asigna a una persona (la ficha del local la quitó). Las que ya la tenían, la conservan.
create function core.guard_active_area()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.area_id is not null and (tg_op = 'INSERT' or new.area_id is distinct from old.area_id)
     and exists (select 1 from org.areas where id = new.area_id and not is_active) then
    raise exception 'Esa área ya no está en uso en el local: elegí otra.' using errcode = '23514';
  end if;
  return new;
end
$$;
comment on function core.guard_active_area() is
  'Trigger: a una persona no se le asigna un área inactiva. Quien ya la tenía, la conserva hasta que se la cambien.';
revoke execute on function core.guard_active_area() from public;
create trigger guard_active_area before insert or update of area_id on core.user_profiles
  for each row execute function core.guard_active_area();
