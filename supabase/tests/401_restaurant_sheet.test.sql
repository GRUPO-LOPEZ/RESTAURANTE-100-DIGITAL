-- Ficha del local en una pantalla (Tanda 1 de Soy, ADR-0061): guardado en lote con motivo y sello, los 8 datos
-- obligatorios para pasar a Abierto, cerrar y reabrir, áreas con baja sin borrar y desde qué fecha factura a nombre
-- de cada razón social.
-- Personas del seed: ...0401 superadministrador, ...0402 Dirección General, ...0403 directora de Demo Pastas (...101),
-- ...0404 gerente de ...201, ...0409 cocinera de ...201. Locales: ...201 a ...203 completos; ...204 (Demo Café) sin
-- teléfono. Razones sociales: ...1501 y ...1502.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(39);

create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
-- Guarda la ficha con el sello vigente (como la pantalla) y devuelve '' si salió bien o el error.
create function pg_temp.save(p_user int, p_id uuid, p_changes jsonb, p_reason text default 'Cambio de prueba')
returns text language sql as $$
  select regexp_replace(pg_temp.q(pg_temp.u(p_user), format('select org.save_restaurant_sheet(%L, %L, %L, %L)::text',
                                  p_id, org.restaurant_sheet_stamp_internal(p_id), p_changes, p_reason)),
                        '^\{"stamp".*\}$', '')
$$;
create temporary table made (k text primary key, id uuid);

-- Un local nuevo nace En apertura y le faltan sus datos.
insert into made select 'sur', pg_temp.q(pg_temp.u(403), format(
  'select org.create_restaurant(%L, ''Sur'', ''restaurant'', ''Local nuevo de prueba'')::text', pg_temp.u(101)))::uuid;
select is(pg_temp.q(pg_temp.u(403), format('select org.restaurant_sheet_state(%L) -> ''missing''', (select id from made where k = 'sur'))),
  '["fecha de apertura", "dirección", "localidad", "teléfono"]',
  'la ficha dice qué le falta al local nuevo (zona, marca y tipo ya están)');
select is(pg_temp.q(pg_temp.u(404), format('select org.restaurant_sheet_state(%L) ->> ''can_edit''', (select id from made where k = 'sur'))),
  null, 'quien no trabaja en ese local no ve su ficha');
select is(pg_temp.q(pg_temp.u(403), format('select org.restaurant_sheet_state(%L)::jsonb - ''stamp'' - ''missing''',
                                           (select id from made where k = 'sur'))),
  '{"can_edit": true, "can_edit_brand_level": true, "can_edit_group_level": false}',
  'la Directora edita datos, tipo y estado, pero no la razón social');

-- Sin los obligatorios no pasa a Abierto.
select is(pg_temp.save(403, (select id from made where k = 'sur'), '{"restaurant": {"state": "open"}}'),
  'ERROR Para abrir el local falta: fecha de apertura, dirección, localidad, teléfono.',
  'un local no pasa a Abierto si le faltan obligatorios, y dice cuáles');
select is(pg_temp.save(403, (select id from made where k = 'sur'), jsonb_build_object('restaurant', jsonb_build_object(
    'opened_on', '2026-12-01', 'address', 'Calle Inventada 10', 'locality', 'Banfield', 'province', '06',
    'postal_code', 'b1828', 'state', 'open'))),
  'ERROR Para abrir el local falta: teléfono.', 'con un solo obligatorio sin cargar, tampoco');
select is((select coalesce(address, '-') from org.restaurants where id = (select id from made where k = 'sur')), '-',
  'el guardado rechazado no deja nada a medias (todo o nada)');
-- La Directora carga los datos; el Superadministrador elige la razón social y abre el local, en un solo guardado.
select is(pg_temp.save(403, (select id from made where k = 'sur'), jsonb_build_object('restaurant', jsonb_build_object(
    'opened_on', '2026-12-01', 'address', 'Calle Inventada 10', 'locality', 'Banfield', 'province', '06',
    'postal_code', 'b1828', 'phone', '011 4000-0099', 'latitude', '-34.744', 'longitude', '-58.392',
    'geo_status', 'found', 'geo_label', 'Calle Inventada 10, Banfield, Buenos Aires')), 'Datos del local nuevo'), '',
  'la Directora carga dirección, teléfono y ubicación');
select is(pg_temp.save(401, (select id from made where k = 'sur'), jsonb_build_object(
    'legal_entity', jsonb_build_object('legal_entity_id', pg_temp.u(1501), 'valid_from', ((now() at time zone 'America/Argentina/Buenos_Aires')::date)::text),
    'restaurant', jsonb_build_object('state', 'open')), 'Abre el local'), '',
  'con todos los datos, la razón social y la apertura van en el mismo guardado');
select is((select opening || ' ' || status || ' ' || postal_code || ' ' || province from org.restaurants
            where id = (select id from made where k = 'sur')), 'false active B1828 06', 'y el local queda Abierto');
select ok(exists (select 1 from audit.audit_events where table_name = 'restaurants' and reason = 'Abre el local'
                    and record_id = (select id from made where k = 'sur') and new_values ->> 'opening' = 'false'),
  'la apertura queda en la auditoría con el motivo');
-- La razón social es opcional para abrir (decisión de Joaco, 2026-11-22): el costo sin IVA queda incompleto, nada más.
insert into made select 'oeste', pg_temp.q(pg_temp.u(403), format(
  'select org.create_restaurant(%L, ''Oeste'', ''restaurant'', ''Local nuevo de prueba'')::text', pg_temp.u(101)))::uuid;
select is(pg_temp.save(403, (select id from made where k = 'oeste'), jsonb_build_object('restaurant', jsonb_build_object(
    'opened_on', '2026-12-01', 'address', 'Calle Inventada 20', 'locality', 'Haedo', 'phone', '011 4000-0098',
    'state', 'open')), 'Abre sin razón social'), '',
  'un local abre sin razón social');

-- Lo que ya estaba abierto no se traba.
select is(pg_temp.save(401, pg_temp.u(204), '{"restaurant": {"address": "Calle de Prueba 46"}}'), '',
  'un local abierto al que le falta el teléfono se sigue editando');
select is(pg_temp.q(pg_temp.u(401), format('select org.restaurant_sheet_state(%L) ->> ''missing''', pg_temp.u(204))),
  '["teléfono"]', 'y la ficha muestra lo que le falta');

-- Cerrar y reabrir.
select is(pg_temp.q(pg_temp.u(404), format('select org.close_restaurant(%L, ''Prueba'')::text', pg_temp.u(201))),
  'ERROR No tenés permiso para cerrar este local.', 'el Gerente no cierra su local');
select is(pg_temp.q(pg_temp.u(401), format('select org.close_restaurant(%L, ''Cierre de prueba'')::text', pg_temp.u(204))), '',
  'el Superadministrador cierra un local');
select is(pg_temp.save(401, pg_temp.u(204), '{"restaurant": {"state": "open"}}'),
  'ERROR El local está cerrado: reabrilo con «Reabrir el local».', 'un local cerrado no se abre desde la ficha');
select is(pg_temp.q(pg_temp.u(401), format('select org.reopen_restaurant(%L, ''Reapertura'')::text', pg_temp.u(204))),
  'ERROR Para abrir el local falta: teléfono.', 'para reabrirlo también hacen falta los obligatorios');
select is(pg_temp.save(401, pg_temp.u(204), '{"restaurant": {"phone": "011 4000-0004"}}'), '',
  'cerrado, se le carga lo que falta');
select is(pg_temp.q(pg_temp.u(401), format('select org.reopen_restaurant(%L, ''Reapertura'')::text', pg_temp.u(204))), '',
  'y entonces se reabre');

-- Permisos por campo (los de ADR-0031).
select is(pg_temp.save(404, pg_temp.u(201), '{"restaurant": {"phone": "011 4000-0011"}}'), '',
  'el Gerente edita los datos de su local');
select is(pg_temp.save(404, pg_temp.u(201), '{"restaurant": {"site_type": "central_kitchen"}}'),
  'ERROR No tenés permiso para cambiar el tipo o el estado de este local.', 'pero no su tipo');
select is(pg_temp.save(404, pg_temp.u(201), jsonb_build_object('legal_entity', jsonb_build_object('legal_entity_id', pg_temp.u(1502)))),
  'ERROR No tenés permiso para elegir la razón social de este local.', 'ni su razón social');
select is(pg_temp.save(409, pg_temp.u(201), '{"restaurant": {"phone": "011 1"}}'),
  'ERROR No tenés permiso para editar este local.', 'la Cocinera no edita el local');
select is(pg_temp.save(402, pg_temp.u(201), '{"restaurant": {"phone": "011 1"}}'),
  'ERROR No tenés permiso para editar este local.', 'Dirección General lo ve, pero no lo edita (no tiene org.manage)');

-- Un nombre con HTML no entra (auditoría de seguridad: el nombre se muestra en el mapa y en muchas pantallas).
select is(pg_temp.save(404, pg_temp.u(201), '{"restaurant": {"zone": "<img src=x onerror=alert(1)>"}}'),
  'ERROR Los nombres no pueden llevar < ni >.', 'una zona con etiquetas se rechaza');
select throws_ok(format('update org.restaurants set zone = ''<b>x</b>'' where id = %L', pg_temp.u(203)), '23514', null,
  'y ni directo en la tabla una zona lleva < ni >');

-- Motivo y sello.
select is(pg_temp.save(401, pg_temp.u(201), '{"restaurant": {"phone": "011 4000-0012"}}', ' '),
  'ERROR Escribí el motivo de los cambios.', 'sin motivo no se guarda');
select is(pg_temp.q(pg_temp.u(401), format('select org.save_restaurant_sheet(%L, %L, ''{"restaurant": {"phone": "011 4000-0013"}}'', ''Prueba'')::text',
                                           pg_temp.u(201), '2020-01-01')),
  'ERROR Otra persona cambió este local mientras lo editabas: recargá la página para ver sus cambios.',
  'si alguien cambió el local en el medio, el guardado se rechaza');

-- Áreas: alta, cambio de nombre y baja sin borrar, en el mismo guardado del local.
select is(pg_temp.save(404, pg_temp.u(201), jsonb_build_object('areas', jsonb_build_array(
    jsonb_build_object('name', 'Barra'),
    jsonb_build_object('id', format('00000000-0000-4000-8000-00000000031%s', 2), 'name', 'Salón principal'),
    jsonb_build_object('id', format('00000000-0000-4000-8000-00000000031%s', 3), 'remove', true))), 'Áreas nuevas'), '',
  'el Gerente agrega, renombra y quita áreas en un guardado');
select is((select string_agg(name || ':' || is_active, ', ' order by name) from org.areas
            where restaurant_id = pg_temp.u(201) and deleted_at is null),
  'Barra:true, Cocina:true, Depósito:false, Salón principal:true', 'quitar un área la deja inactiva, no la borra');
select is(pg_temp.save(404, pg_temp.u(201), '{"areas": [{"name": "depósito"}]}'), '',
  'agregar una con el nombre de una inactiva');
select is((select count(*)::int || ' ' || bool_and(is_active) from org.areas
            where restaurant_id = pg_temp.u(201) and lower(name) = 'depósito'), '1 true', 'la vuelve a activar, sin repetirla');
select is(pg_temp.save(404, pg_temp.u(201), jsonb_build_object('areas', jsonb_build_array(
    jsonb_build_object('id', format('00000000-0000-4000-8000-00000000032%s', 1), 'name', 'Ajena')))),
  'ERROR Esa área no es de este local.', 'no se toca un área de otro local');
select ok((select count(*) from audit.audit_events where table_name = 'areas' and reason = 'Áreas nuevas') = 3,
  'cada área cambiada queda en la auditoría con el motivo');

-- Desde qué fecha factura a nombre de cada razón social. El tramo del seed empieza hoy: se lo corre a 2024 para que
-- el cambio de hoy sea un tramo aparte.
update org.restaurant_legal_entities set valid_from = '2024-01-01' where restaurant_id = pg_temp.u(202);
select is(pg_temp.save(401, pg_temp.u(202), jsonb_build_object('legal_entity', jsonb_build_object(
    'legal_entity_id', pg_temp.u(1502), 'valid_from', ((now() at time zone 'America/Argentina/Buenos_Aires')::date + 1)::text))),
  'ERROR La fecha desde la que factura no puede ser futura: guardá el cambio ese día.',
  'no se programa una razón social para más adelante: el local la usa desde que se guarda');
select is(pg_temp.save(401, pg_temp.u(202), jsonb_build_object('legal_entity', jsonb_build_object(
    'legal_entity_id', pg_temp.u(1502), 'valid_from', ((now() at time zone 'America/Argentina/Buenos_Aires')::date)::text)),
    'Cambio de razón social'), '', 'el local cambia de razón social desde hoy');
select is((select count(*)::int from org.restaurant_legal_entities where restaurant_id = pg_temp.u(202) and deleted_at is null), 2,
  'queda el tramo nuevo y el de antes sigue: las facturas viejas siguen con la anterior');
select is(pg_temp.save(401, pg_temp.u(202), jsonb_build_object('legal_entity', jsonb_build_object(
    'legal_entity_id', pg_temp.u(1501), 'valid_from', '2020-01-01'))),
  'ERROR Ya hay una razón social desde una fecha posterior: elegí una fecha más nueva.',
  'no se mete un tramo antes de uno que ya existe');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.restaurant_legal_entities'), '0',
  'la Cocinera no ve el historial de razones sociales');

select * from finish();
rollback;
