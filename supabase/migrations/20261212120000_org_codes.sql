-- Códigos automáticos de marca y de local, nombre corto de la marca y zona del local (Tanda 1 de las correcciones de
-- Soy del Módulo 1, ADR-0061).
--
-- * Marca: número correlativo por grupo (01, 02…) y código «NN-NOMBRE» con el nombre corto en mayúsculas, sin tildes
--   ni espacios (02-PADELLA). La palabra se puede corregir al crearla; el número, no. Después queda fija.
-- * Local: número correlativo por marca y código «MARCA-NNN» (RAGU-001), fijo para siempre: lo usan el historial y
--   el número de las órdenes de compra. El nombre se arma solo con el nombre corto de la marca y la zona («Ragú
--   Leloir»), se guarda (lo leen muchas pantallas y reportes) y lo recalcula la base.
-- * Lo que ya existe no cambia solo: las marcas conservan su código y los locales con código, el suyo (PCE). Los
--   locales sin código reciben el automático: asignar uno que falta no es cambiarlo.
-- * Los números no se saltean ni se repiten: el alta bloquea la fila del grupo (marcas) o de la marca (locales) hasta
--   el final de la transacción y toma el siguiente. Si la transacción falla, el número no se pierde.

-- ---------------------------------------------------------------------------
-- 1. Columnas nuevas
-- ---------------------------------------------------------------------------
alter table org.brands
  add column short_name text check (short_name is null or (length(btrim(short_name)) between 1 and 40 and short_name !~ '[<>]')),
  add column number smallint check (number is null or number between 1 and 99);
comment on column org.brands.short_name is
  'Nombre corto de la marca (Ragú, Padella): arma el nombre de sus locales («Ragú Leloir») y la palabra de su código.';
comment on column org.brands.number is
  'Número correlativo de la marca dentro del grupo (1, 2, 3…). Lo pone la base al crearla, sin saltos ni repetidos, y no cambia.';

alter table org.restaurants
  add column zone text check (zone is null or (length(btrim(zone)) between 1 and 80 and zone !~ '[<>]')),
  add column number smallint check (number is null or number between 1 and 999);
comment on column org.restaurants.zone is
  'Zona o ubicación del local (Leloir, Belgrano). Con el nombre corto de la marca arma el nombre del local. Si el local se muda, cambia la zona y el nombre; el código, no.';
comment on column org.restaurants.number is
  'Número correlativo del local dentro de su marca (1, 2, 3…). Lo pone la base al crearlo, sin saltos ni repetidos, y no cambia.';

-- Lo que ya existe: número por orden de alta y nombre corto igual al nombre (se corrige desde el Panel).
do $$
begin
  if exists (select 1 from org.brands) then
    perform core.set_change_context('Números correlativos y nombre corto de las marcas y locales (ADR-0061)', 'maintenance');
    update org.brands b
       set number = n.rn, short_name = left(btrim(b.name), 40)
      from (select id, row_number() over (partition by group_id order by created_at, id) as rn from org.brands) n
     where n.id = b.id;
    update org.restaurants r
       set number = n.rn
      from (select id, row_number() over (partition by brand_id order by created_at, id) as rn from org.restaurants) n
     where n.id = r.id;
  end if;
end
$$;

alter table org.brands alter column short_name set not null, alter column number set not null;
-- Los nombres se muestran en muchas pantallas (y en el mapa): sin < ni >, como defensa en profundidad contra HTML.
alter table org.brands add constraint brands_name_plain check (name !~ '[<>]') not valid;
alter table org.restaurants add constraint restaurants_name_plain check (name !~ '[<>]') not valid;
alter table org.restaurants alter column number set not null;
create unique index brands_number_key on org.brands (group_id, number);
create unique index restaurants_number_key on org.restaurants (brand_id, number);

-- ---------------------------------------------------------------------------
-- 2. Cómo se arman los códigos y el nombre (la misma regla está en lib/org-codes.ts)
-- ---------------------------------------------------------------------------
-- La palabra de un código: mayúsculas, sin tildes, solo letras y números, hasta 16.
create function org.code_word(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(left(regexp_replace(translate(upper(btrim(coalesce(p_text, ''))), 'ÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑÇ',
                                              'AAAAEEEEIIIIOOOOUUUUNC'), '[^A-Z0-9]', '', 'g'), 16), '')
$$;
comment on function org.code_word(text) is
  'La palabra de un código: el texto en mayúsculas, sin tildes, solo letras y números, hasta 16 caracteres (Ragú → RAGU).';

create function org.brand_code(p_number int, p_word text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lpad(p_number::text, 2, '0') || '-' || org.code_word(p_word)
$$;
comment on function org.brand_code(int, text) is 'El código de una marca: número de dos cifras y palabra (02-PADELLA).';

-- La palabra de una marca: su código sin el número (01-RAGU → RAGU); un código viejo (PASTAS) va entero.
create function org.brand_word(p_brand_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(p_brand_code, '^[0-9]{2}-', '')
$$;
comment on function org.brand_word(text) is
  'La palabra del código de una marca, sin su número: 01-RAGU → RAGU. Un código de antes (PASTAS) va entero.';

-- La palabra no se repite entre las marcas vigentes de un grupo: si no, dos marcas armarían los mismos códigos de local.
create unique index brands_word_key on org.brands (group_id, org.brand_word(code)) where deleted_at is null;

create function org.restaurant_code(p_brand_code text, p_number int)
returns text
language sql
immutable
set search_path = ''
as $$
  select org.brand_word(p_brand_code) || '-' || lpad(p_number::text, 3, '0')
$$;
comment on function org.restaurant_code(text, int) is
  'El código de un local: la palabra del código de su marca y el número de tres cifras (RAGU-001).';

create function org.restaurant_name(p_short_name text, p_zone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select btrim(p_short_name) || ' ' || btrim(p_zone)
$$;
comment on function org.restaurant_name(text, text) is 'El nombre de un local: el nombre corto de la marca y la zona (Ragú Leloir).';

grant execute on function org.code_word(text), org.brand_code(int, text), org.brand_word(text), org.restaurant_code(text, int),
                          org.restaurant_name(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Triggers: número correlativo, nombre armado y código fijo
-- ---------------------------------------------------------------------------
create function org.assign_brand_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Un alta a la vez por grupo: la segunda espera y ve el número de la primera.
  -- FOR NO KEY UPDATE: serializa las altas sin trabar las escrituras que solo apuntan al grupo (sus FK).
  perform 1 from org.groups where id = new.group_id for no key update;
  new.number := coalesce((select max(number) from org.brands where group_id = new.group_id), 0) + 1;
  new.short_name := coalesce(nullif(btrim(new.short_name), ''), left(btrim(new.name), 40));
  return new;
end
$$;
comment on function org.assign_brand_number() is
  'Trigger: pone el número correlativo de la marca (sin saltos ni repetidos, también con dos altas a la vez) y, si falta, el nombre corto.';
revoke execute on function org.assign_brand_number() from public;

create trigger assign_number before insert on org.brands
  for each row execute function org.assign_brand_number();

create function org.assign_restaurant_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_short text;
begin
  select short_name into v_short from org.brands where id = new.brand_id for no key update;
  new.number := coalesce((select max(number) from org.restaurants where brand_id = new.brand_id), 0) + 1;
  if nullif(btrim(new.zone), '') is not null then
    new.name := org.restaurant_name(v_short, new.zone);
  end if;
  return new;
end
$$;
comment on function org.assign_restaurant_number() is
  'Trigger: pone el número correlativo del local dentro de su marca (sin saltos ni repetidos) y, si tiene zona, arma su nombre.';
revoke execute on function org.assign_restaurant_number() from public;

create trigger assign_number before insert on org.restaurants
  for each row execute function org.assign_restaurant_number();

create function org.guard_restaurant_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.number is distinct from old.number then
    raise exception 'El número del local no cambia.' using errcode = '23514', constraint = 'restaurants_number_fixed';
  end if;
  -- El código no cambia nunca, ni pasando por vacío. Un local sin código puede recibirlo. Solo el traspaso aprobado
  -- (org.apply_transfer) libera el código del local viejo para el nuevo, y lo avisa en la transacción.
  if old.code is not null and new.code is distinct from old.code
     and coalesce(current_setting('app.releasing_code', true), '') <> old.id::text then
    raise exception 'El código del local no cambia: lo usan el historial y las órdenes de compra.'
      using errcode = '23514', constraint = 'restaurants_code_fixed';
  end if;
  if nullif(btrim(new.zone), '') is not null
     and (new.zone is distinct from old.zone or new.name is distinct from old.name) then
    new.name := org.restaurant_name((select short_name from org.brands where id = new.brand_id), new.zone);
  end if;
  return new;
end
$$;
comment on function org.guard_restaurant_identity() is
  'Trigger: el número y el código de un local no cambian (el código solo se asigna si faltaba o se libera en un traspaso). Con zona, el nombre lo arma la base.';
revoke execute on function org.guard_restaurant_identity() from public;

create trigger guard_identity before update on org.restaurants
  for each row execute function org.guard_restaurant_identity();

create function org.guard_brand_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.number is distinct from old.number then
    raise exception 'El número de la marca no cambia.' using errcode = '23514', constraint = 'brands_number_fixed';
  end if;
  -- El alta arma el código en la misma transacción, desde un valor provisorio (NUEVA-…) que solo vale ahí.
  if new.code is distinct from old.code
     and not (old.code ~ '^NUEVA-[0-9A-F]{8}$' and old.created_at = now()) then
    raise exception 'El código de la marca no cambia.' using errcode = '23514', constraint = 'brands_code_fixed';
  end if;
  return new;
end
$$;
comment on function org.guard_brand_identity() is 'Trigger: el número y el código de una marca no cambian.';
revoke execute on function org.guard_brand_identity() from public;

create trigger guard_identity before update on org.brands
  for each row execute function org.guard_brand_identity();

-- Si cambia el nombre corto de la marca, sus locales con zona cambian de nombre (queda en la auditoría de cada uno).
create function org.rename_brand_restaurants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update org.restaurants
     set name = org.restaurant_name(new.short_name, zone)
   where brand_id = new.id and deleted_at is null and nullif(btrim(zone), '') is not null;
  return null;
end
$$;
comment on function org.rename_brand_restaurants() is
  'Trigger: cuando cambia el nombre corto de una marca, rearma el nombre de sus locales que tienen zona.';
revoke execute on function org.rename_brand_restaurants() from public;

create trigger rename_restaurants after update of short_name on org.brands
  for each row when (new.short_name is distinct from old.short_name)
  execute function org.rename_brand_restaurants();

-- ---------------------------------------------------------------------------
-- 4. Locales sin código: reciben el automático (los que tienen código lo conservan)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from org.restaurants where code is null and deleted_at is null) then
    perform core.set_change_context('Código automático para los locales que no tenían (ADR-0061)', 'maintenance');
    update org.restaurants r
       set code = org.restaurant_code(b.code, r.number)
      from org.brands b
     where b.id = r.brand_id and r.code is null and r.deleted_at is null;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Alta y edición de marcas
-- ---------------------------------------------------------------------------
-- Vista previa del código que va a tener la marca nueva (sin consumir el número).
create function org.peek_brand_code(p_group_id uuid, p_word text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not core.has_permission_in_group('org.manage', p_group_id) then
    return null;
  end if;
  return org.brand_code(coalesce((select max(number) from org.brands where group_id = p_group_id), 0) + 1,
                        coalesce(org.code_word(p_word), ''));
end
$$;
comment on function org.peek_brand_code(uuid, text) is
  'Vista previa del código de una marca nueva (04-SUSHI), sin consumir el número. Pide org.manage en el grupo; si no, nada.';
revoke execute on function org.peek_brand_code(uuid, text) from public;
grant execute on function org.peek_brand_code(uuid, text) to authenticated;

drop function org.create_brand(uuid, text, text, text);
create function org.create_brand(p_group_id uuid, p_name text, p_short_name text, p_code_word text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    uuid;
  v_short text := nullif(btrim(p_short_name), '');
  v_word  text;
begin
  perform org.require(core.has_permission_in_group('org.manage', p_group_id), 'crear marcas en este grupo');
  if nullif(btrim(p_name), '') is null then
    raise exception 'Escribí el nombre de la marca.' using errcode = '23514';
  end if;
  v_short := coalesce(v_short, btrim(p_name));
  if p_name ~ '[<>]' or v_short ~ '[<>]' then
    raise exception 'Los nombres no pueden llevar < ni >.' using errcode = '23514';
  end if;
  v_word := coalesce(org.code_word(p_code_word), org.code_word(v_short));
  if v_word is null or length(v_word) < 2 then
    raise exception 'El código necesita al menos dos letras o números.' using errcode = '23514';
  end if;
  -- La palabra no se repite en el grupo (contando los códigos de antes): arma los códigos de los locales.
  if exists (select 1 from org.brands where group_id = p_group_id and deleted_at is null and org.brand_word(code) = v_word) then
    raise exception 'Ya hay una marca con la palabra % en el código: elegí otra.', v_word
      using errcode = '23505', constraint = 'brands_word_key';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  -- El número lo pone el trigger; el código se arma con ese número, desde un valor provisorio único.
  insert into org.brands (group_id, name, short_name, code)
  values (p_group_id, btrim(p_name), v_short, 'NUEVA-' || upper(left(md5(gen_random_uuid()::text), 8)))
  returning id into v_id;
  update org.brands set code = org.brand_code(number, v_word) where id = v_id;
  return v_id;
end
$$;
comment on function org.create_brand(uuid, text, text, text, text) is
  'Crea una marca: nombre, nombre corto (arma el nombre de sus locales) y, si se quiere corregir, la palabra del código. El número y el código (02-PADELLA) los pone la base. Pide org.manage en el grupo y un motivo.';
revoke execute on function org.create_brand(uuid, text, text, text, text) from public;
grant execute on function org.create_brand(uuid, text, text, text, text) to authenticated;

create or replace function org.update_brand(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from org.brands where id = p_id;
  perform org.require(core.has_permission_in_brand('org.manage', p_id), 'editar esta marca');
  if p_changes ? 'code' then
    raise exception 'El código de la marca no cambia.' using errcode = '23514';
  end if;
  perform org.check_keys(p_changes, array['name', 'short_name', 'status']);
  if p_changes ? 'status' then
    perform org.require(core.has_permission_in_group('org.manage', v_group), 'abrir o cerrar esta marca');
  end if;
  if coalesce(p_changes ->> 'name', '') ~ '[<>]' or coalesce(p_changes ->> 'short_name', '') ~ '[<>]' then
    raise exception 'Los nombres no pueden llevar < ni >.' using errcode = '23514';
  end if;
  if (p_changes ? 'name' and nullif(btrim(p_changes ->> 'name'), '') is null)
     or (p_changes ? 'short_name' and nullif(btrim(p_changes ->> 'short_name'), '') is null) then
    raise exception 'El nombre de la marca no puede quedar vacío.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.brands
     set name       = coalesce(btrim(p_changes ->> 'name'), name),
         short_name = coalesce(btrim(p_changes ->> 'short_name'), short_name),
         status     = coalesce((p_changes ->> 'status')::org.unit_status, status)
   where id = p_id;
end
$$;
comment on function org.update_brand(uuid, jsonb, text) is
  'Edita una marca: nombre, nombre corto y estado (abrir o cerrar pide org.manage en el grupo). El código no cambia. Si cambia el nombre corto, sus locales cambian de nombre.';
