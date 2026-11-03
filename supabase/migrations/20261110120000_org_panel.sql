-- Panel de control de la estructura del grupo (ADR-0031; respuesta 2 de Soy, ADR-0030).
--
-- Las pantallas usan las funciones que ya existen (marcas, locales, áreas y razones sociales). Lo único
-- que cambia en la base: al crear un local se pueden elegir, en la misma operación, su razón social
-- (ADR-0024, respuesta 2 b) y su tipo. La razón social sigue pidiendo org.manage de todo el grupo
-- (decisión 8 de ADR-0029), igual que org.set_restaurant_legal_entity. Además, una fecha de apertura
-- vacía ya no rompe el alta (antes se convertía '' a fecha y fallaba).

create or replace function org.create_restaurant(p_brand_id uuid, p_name text, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group  uuid;
  v_id     uuid;
  v_d      jsonb := coalesce(p_details, '{}'::jsonb);
  v_entity uuid;
begin
  perform org.require(core.has_permission_in_brand('org.manage', p_brand_id), 'crear locales en esta marca');
  perform org.check_keys(v_d, array['code', 'address', 'locality', 'legal_name', 'tax_id', 'phone', 'opened_on', 'time_zone',
                                    'site_type', 'legal_entity_id']);
  select group_id into v_group from org.brands where id = p_brand_id;
  -- Datos mal formados, con un mensaje en español (y no el error crudo de la conversión).
  if nullif(v_d ->> 'site_type', '') is not null
     and not (v_d ->> 'site_type' = any (enum_range(null::org.site_type)::text[])) then
    raise exception 'Elegí el tipo de local.' using errcode = '22023';
  end if;
  if nullif(v_d ->> 'legal_entity_id', '') is not null
     and (v_d ->> 'legal_entity_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'Elegí una razón social vigente del grupo.' using errcode = '22023';
  end if;
  v_entity := nullif(v_d ->> 'legal_entity_id', '')::uuid;
  if v_entity is not null then
    -- Cambia si el costo va con o sin IVA: la elige solo quien administra todo el grupo.
    perform org.require(core.has_permission_in_group('org.manage', v_group), 'elegir la razón social de este local');
    if not exists (select 1 from org.legal_entities where id = v_entity and group_id = v_group and deleted_at is null) then
      raise exception 'Elegí una razón social vigente del grupo.' using errcode = '22023';
    end if;
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into org.restaurants (group_id, brand_id, name, code, address, locality, legal_name, tax_id, phone, opened_on, time_zone,
                               site_type, legal_entity_id)
  values (v_group, p_brand_id, btrim(p_name),
          upper(nullif(btrim(v_d ->> 'code'), '')), nullif(btrim(v_d ->> 'address'), ''),
          nullif(btrim(v_d ->> 'locality'), ''), nullif(btrim(v_d ->> 'legal_name'), ''),
          nullif(btrim(v_d ->> 'tax_id'), ''), nullif(btrim(v_d ->> 'phone'), ''),
          nullif(btrim(v_d ->> 'opened_on'), '')::date,
          coalesce(nullif(btrim(v_d ->> 'time_zone'), ''), 'America/Argentina/Buenos_Aires'),
          coalesce(nullif(v_d ->> 'site_type', '')::org.site_type, 'restaurant'),
          v_entity)
  returning id into v_id;
  return v_id;
end
$$;
comment on function org.create_restaurant(uuid, text, jsonb, text) is
  'Crea un local en una marca. Pide org.manage en la marca y un motivo. En p_details puede ir su tipo (site_type) y su razón social (legal_entity_id); la razón social pide además org.manage de todo el grupo.';

comment on column org.restaurants.legal_name is
  'Dato viejo (Fase 1): la razón social del local ahora es legal_entity_id, que define el IVA del costo. El panel de control no lo muestra.';
comment on column org.restaurants.tax_id is
  'Dato viejo (Fase 1): el CUIT del local ahora está en su razón social (legal_entity_id). El panel de control no lo muestra.';
