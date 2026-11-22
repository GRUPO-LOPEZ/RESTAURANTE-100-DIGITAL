-- Ubicación y apertura del local (Tanda 1 de las correcciones de Soy, ADR-0061).
--
-- * Provincia, código postal y ubicación en el mapa (latitud y longitud de Georef). Si Georef no encuentra la
--   dirección, el local se guarda igual y queda «Sin ubicar en el mapa».
-- * «En apertura» es una columna aparte (opening) y no un estado nuevo: la base tiene muchos controles de
--   status = 'active' (permisos, costos, tableros) y un local en apertura tiene que funcionar igual que uno abierto,
--   para poder prepararlo. En apertura = activo + opening; Abierto = activo sin opening; Cerrado = inactive.
-- * Para pasar a Abierto (desde En apertura o al reabrir) hacen falta los 7 datos obligatorios: marca, zona, tipo,
--   fecha de apertura, dirección, localidad y teléfono (la razón social es opcional: decisión de Joaco, 2026-11-22). Lo que ya estaba abierto no se traba.
-- * Alta de local nueva: marca, zona, tipo y motivo. El nombre y el código los arma la base y el local nace En
--   apertura.

-- ---------------------------------------------------------------------------
-- 1. Provincias (las 24 jurisdicciones, con el código que usan Georef y el INDEC)
-- ---------------------------------------------------------------------------
create table org.provinces (
  code text primary key check (code ~ '^[0-9]{2}$'),
  name text not null unique check (length(btrim(name)) between 1 and 80)
);
comment on table org.provinces is
  'Las 24 jurisdicciones de la Argentina, con el código de Georef y el INDEC. Se carga por migración y no cambia.';
comment on column org.provinces.code is 'Código de dos cifras de la provincia en Georef y el INDEC (02 = CABA, 06 = Buenos Aires).';
comment on column org.provinces.name is 'Nombre de la provincia, como se muestra.';

insert into org.provinces (code, name) values
  ('02', 'Ciudad Autónoma de Buenos Aires'), ('06', 'Buenos Aires'), ('10', 'Catamarca'), ('14', 'Córdoba'),
  ('18', 'Corrientes'), ('22', 'Chaco'), ('26', 'Chubut'), ('30', 'Entre Ríos'), ('34', 'Formosa'), ('38', 'Jujuy'),
  ('42', 'La Pampa'), ('46', 'La Rioja'), ('50', 'Mendoza'), ('54', 'Misiones'), ('58', 'Neuquén'),
  ('62', 'Río Negro'), ('66', 'Salta'), ('70', 'San Juan'), ('74', 'San Luis'), ('78', 'Santa Cruz'),
  ('82', 'Santa Fe'), ('86', 'Santiago del Estero'), ('90', 'Tucumán'),
  ('94', 'Tierra del Fuego, Antártida e Islas del Atlántico Sur');

alter table org.provinces enable row level security;
revoke all on org.provinces from public, anon, authenticated, service_role;
grant select on org.provinces to authenticated;
-- Tabla de referencia pública (como org.time_zones): la lee cualquiera con sesión, nadie escribe (sin grants de
-- escritura) y se carga solo por migración. Por eso no lleva columnas de control ni auditoría.
create policy provinces_select on org.provinces for select to authenticated using (true);
create trigger reject_truncate before truncate on org.provinces
  for each statement execute function core.reject_truncate();

-- ---------------------------------------------------------------------------
-- 2. Columnas nuevas del local
-- ---------------------------------------------------------------------------
create type org.geo_status as enum ('found', 'not_found');
comment on type org.geo_status is
  'Si Georef encontró la dirección del local: found (está en el mapa) o not_found (se guardó igual, «Sin ubicar en el mapa»).';

alter table org.restaurants
  add column opening     boolean not null default false,
  add column province    text references org.provinces (code) on delete restrict,
  add column postal_code text check (postal_code is null or postal_code ~ '^[A-Z]?[0-9]{4}([A-Z]{3})?$'),
  add column latitude    numeric(9, 6) check (latitude is null or latitude between -90 and 90),
  add column longitude   numeric(9, 6) check (longitude is null or longitude between -180 and 180),
  add column geo_status  org.geo_status,
  add column geo_label   text check (geo_label is null or length(geo_label) between 1 and 300),
  add constraint restaurants_geo_check check ((latitude is null) = (longitude is null)
                                              and (geo_status = 'found') = (latitude is not null));
comment on column org.restaurants.opening is
  'En apertura: el local funciona como uno abierto (permisos, recetas, compras), pero todavía no abrió al público. Para pasar a Abierto hacen falta sus 7 datos obligatorios.';
comment on column org.restaurants.province is 'Provincia del local (la que devuelve Georef, o la que se elige).';
comment on column org.restaurants.postal_code is 'Código postal del local: 4 cifras o el CPA (B1713ABC). Georef no lo devuelve: se escribe.';
comment on column org.restaurants.latitude is 'Latitud del local, de Georef. Vacía si no se ubicó en el mapa.';
comment on column org.restaurants.longitude is 'Longitud del local, de Georef. Vacía si no se ubicó en el mapa.';
comment on column org.restaurants.geo_status is
  'Si Georef encontró la dirección: found (con latitud y longitud) o not_found («Sin ubicar en el mapa»). Vacío si nunca se buscó.';
comment on column org.restaurants.geo_label is 'La dirección como la normalizó Georef (calle, número, localidad y provincia).';
create index restaurants_province_idx on org.restaurants (province);

-- ---------------------------------------------------------------------------
-- 3. Los 7 datos obligatorios y la regla para abrir
-- ---------------------------------------------------------------------------
-- Lo que le falta a un local para estar completo, en palabras (vacío si está completo). Marca y tipo nunca faltan.
create function org.restaurant_missing(p_r org.restaurants)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[
    case when nullif(btrim(p_r.zone), '') is null then 'zona' end,
    case when p_r.opened_on is null then 'fecha de apertura' end,
    case when nullif(btrim(p_r.address), '') is null then 'dirección' end,
    case when nullif(btrim(p_r.locality), '') is null then 'localidad' end,
    case when nullif(btrim(p_r.phone), '') is null then 'teléfono' end
  ], null)
$$;
comment on function org.restaurant_missing(org.restaurants) is
  'Los datos obligatorios que le faltan a un local, en palabras (zona, fecha de apertura, dirección, localidad, teléfono). Marca y tipo siempre están: son 7 en total. La razón social es opcional.';
revoke execute on function org.restaurant_missing(org.restaurants) from public;

create function org.guard_restaurant_open()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_missing text[];
begin
  -- Solo al pasar a Abierto: de En apertura, o al reabrir un local cerrado. Lo que ya estaba abierto no se traba.
  if new.status = 'active' and not new.opening and new.deleted_at is null
     and (old.status <> 'active' or old.opening) then
    v_missing := org.restaurant_missing(new);
    if cardinality(v_missing) > 0 then
      raise exception 'Para abrir el local falta: %.', array_to_string(v_missing, ', ')
        using errcode = '23514', constraint = 'restaurants_open_requires_data';
    end if;
  end if;
  return new;
end
$$;
comment on function org.guard_restaurant_open() is
  'Trigger: un local no pasa a Abierto (desde En apertura o al reabrirse) si le falta alguno de sus 7 datos obligatorios.';
revoke execute on function org.guard_restaurant_open() from public;

create trigger guard_open before update on org.restaurants
  for each row execute function org.guard_restaurant_open();

-- ---------------------------------------------------------------------------
-- 4. Alta de local: marca, zona, tipo y motivo
-- ---------------------------------------------------------------------------
-- Vista previa del nombre y el código que va a tener un local nuevo, sin consumir el número.
create function org.peek_restaurant(p_brand_id uuid, p_zone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_b      org.brands;
  v_number int;
begin
  if not core.has_permission_in_brand('org.manage', p_brand_id) then
    return null;
  end if;
  select * into v_b from org.brands where id = p_brand_id and deleted_at is null;
  if v_b.id is null then
    return null;
  end if;
  v_number := coalesce((select max(number) from org.restaurants where brand_id = p_brand_id), 0) + 1;
  return jsonb_build_object(
    'name', case when nullif(btrim(p_zone), '') is null then null else org.restaurant_name(v_b.short_name, p_zone) end,
    'code', org.restaurant_code(v_b.code, v_number),
    'number', v_number);
end
$$;
comment on function org.peek_restaurant(uuid, text) is
  'Vista previa de un local nuevo: su nombre (marca + zona), su código (RAGU-002) y su número, sin consumirlo. Pide org.manage en la marca; si no, nada.';
revoke execute on function org.peek_restaurant(uuid, text) from public;
grant execute on function org.peek_restaurant(uuid, text) to authenticated;

drop function org.create_restaurant(uuid, text, jsonb, text);
create function org.create_restaurant(p_brand_id uuid, p_zone text, p_site_type org.site_type, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_b  org.brands;
  v_id uuid;
begin
  perform org.require(core.has_permission_in_brand('org.manage', p_brand_id), 'crear locales en esta marca');
  select * into v_b from org.brands where id = p_brand_id and deleted_at is null;
  if v_b.id is null or v_b.status <> 'active' then
    raise exception 'Elegí una marca vigente.' using errcode = '22023';
  end if;
  if nullif(btrim(p_zone), '') is null then
    raise exception 'Escribí la zona o ubicación del local.' using errcode = '23514';
  end if;
  if p_zone ~ '[<>]' then
    raise exception 'Los nombres no pueden llevar < ni >.' using errcode = '23514';
  end if;
  if exists (select 1 from org.restaurants
              where brand_id = p_brand_id and deleted_at is null
                and lower(name) = lower(org.restaurant_name(v_b.short_name, p_zone))) then
    raise exception 'Ya hay un local «%» en esta marca.', org.restaurant_name(v_b.short_name, p_zone)
      using errcode = '23505', constraint = 'restaurants_name_key';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- El número y el nombre los pone el trigger; el código se arma con ese número.
  insert into org.restaurants (group_id, brand_id, name, zone, site_type, opening)
  values (v_b.group_id, p_brand_id, org.restaurant_name(v_b.short_name, p_zone), btrim(p_zone),
          coalesce(p_site_type, 'restaurant'), true)
  returning id into v_id;
  -- Un código cargado a mano antes (otro local con PASTAS-002) chocaría: se avisa en palabras.
  if exists (select 1 from org.restaurants x
              where x.group_id = v_b.group_id and x.deleted_at is null and x.id <> v_id
                and x.code = (select org.restaurant_code(v_b.code, r.number) from org.restaurants r where r.id = v_id)) then
    raise exception 'Otro local ya usa el código que le toca a este: pedile a quien administra el grupo que lo revise.'
      using errcode = '23505', constraint = 'restaurants_code_key';
  end if;
  update org.restaurants set code = org.restaurant_code(v_b.code, number) where id = v_id;
  return v_id;
end
$$;
comment on function org.create_restaurant(uuid, text, org.site_type, text) is
  'Crea un local En apertura: marca, zona y tipo. El nombre (Ragú Belgrano), el número y el código (RAGU-002) los pone la base. El resto se completa en su ficha. Pide org.manage en la marca y un motivo.';
revoke execute on function org.create_restaurant(uuid, text, org.site_type, text) from public;
grant execute on function org.create_restaurant(uuid, text, org.site_type, text) to authenticated;
