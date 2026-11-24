-- Listas de la cocina y Configuración del catálogo en una pantalla (Tanda 2 de Soy, PR A, ADR-0063): estructura, quién ve
-- y quién edita cada lista, guardado en lote con sello y motivo, baja y reactivación, y auditoría.
-- Personas del seed: ...0401 superadministrador, ...0402 Dirección General, ...0403 directora de Demo Pastas, ...0404
-- gerente, ...0405 chef de marca, ...0406 jefe de cocina, ...0408 compras, ...0409 cocinera, ...0413 chef del grupo.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(111);

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
create function pg_temp.u(p_n int) returns uuid language sql strict as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.list(p_user int, p_list text) returns jsonb language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select catalog.settings_list(%L, %L)::text', pg_temp.u(1), p_list))::jsonb
$$;
create function pg_temp.row(p_list text, p_name text) returns jsonb language sql as $$
  select r from jsonb_array_elements(pg_temp.list(401, p_list) -> 'rows') r where r ->> 'name' = p_name
$$;
-- Guarda con el sello vigente y devuelve «resultado: mensaje», o el error.
create function pg_temp.save(p_user int, p_list text, p_items jsonb, p_reason text default 'Cambio de prueba',
                             p_stamp timestamptz default null, p_group int default 1)
returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select (r ->> ''result'') || '': '' || (r ->> ''message'') from catalog.save_settings_list(%L, %L, %L, %L, %L) r',
    pg_temp.u(p_group), p_list, coalesce(p_stamp, catalog.settings_list_stamp(p_list::catalog.settings_list, pg_temp.u(p_group))),
    p_items, p_reason))
$$;
create function pg_temp.item(p_id uuid, p_more jsonb) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('id', p_id) || p_more)
$$;
create function pg_temp.sector(p_name text) returns uuid language sql as $$
  select id from catalog.kitchen_sectors where name = p_name and group_id = pg_temp.u(1)
$$;
create function pg_temp.measure(p_name text) returns uuid language sql as $$
  select id from catalog.practical_measures where name = p_name and group_id = pg_temp.u(1)
$$;
create function pg_temp.equip(p_name text) returns uuid language sql as $$
  select id from catalog.kitchen_equipment where name = p_name and group_id = pg_temp.u(1)
$$;
create function pg_temp.denials() returns int language sql as $$
  select count(*)::int from audit.authentication_security_events
   where event_type = 'operation_denied' and operation = 'catalog.save_settings_list'
$$;
grant execute on function pg_temp.u(int) to authenticated;

-- ---------------------------------------------------------------------------
-- Estructura y lectura directa
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'catalog' and c.relrowsecurity
              and c.relname in ('kitchen_sectors', 'kitchen_stations', 'kitchen_equipment', 'practical_measures')), 4,
  'las 4 tablas, con RLS');
select is((select count(*)::int from information_schema.role_table_grants
            where table_schema = 'catalog' and grantee in ('authenticated', 'anon') and privilege_type <> 'SELECT'
              and table_name in ('kitchen_sectors', 'kitchen_stations', 'kitchen_equipment', 'practical_measures')), 0,
  'nadie las escribe directo');
select is((select count(*)::int from pg_trigger where tgname in ('log_change', 'set_control_columns', 'reject_truncate', 'clean_list_item')
              and tgrelid in ('catalog.kitchen_sectors'::regclass, 'catalog.kitchen_stations'::regclass,
                              'catalog.kitchen_equipment'::regclass, 'catalog.practical_measures'::regclass)), 16,
  'con auditoría, columnas de control, sin truncate y con limpieza');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from catalog.kitchen_sectors'), '3',
  'la cocinera lee los sectores (los ve en la receta)');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from catalog.practical_measures'), '5', 'y las medidas prácticas');
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from catalog.kitchen_equipment'), '2', 'el gerente, los equipos');
select matches(pg_temp.q(pg_temp.u(401), 'insert into catalog.kitchen_sectors (group_id, name) values (pg_temp.u(1), ''X'') returning id::text'),
  'permission denied', 'ni el superadministrador inserta directo');
select matches(pg_temp.q(pg_temp.u(408), 'delete from catalog.practical_measures returning id::text'), 'permission denied',
  'ni se borra');

-- Otro grupo no se ve.
insert into org.groups (id, name) values (pg_temp.u(60001), 'Otro grupo');
select catalog.install_default_lists(pg_temp.u(60001));
select is((select count(*)::int from catalog.kitchen_stations where group_id = pg_temp.u(60001)), 3, 'el otro grupo tiene sus partidas');
select is(pg_temp.q(pg_temp.u(401), 'select count(*)::text from catalog.kitchen_stations'), '3', 'y nadie de este grupo las ve');

-- Con qué nacen: lo que nombró Soy.
select is((select array_agg(name order by name collate "C") from catalog.kitchen_sectors where group_id = pg_temp.u(1)),
  array['Cocina caliente', 'Cocina fría', 'Pastelería'], 'sectores');
select is((select array_agg(name order by name collate "C") from catalog.kitchen_stations where group_id = pg_temp.u(1)),
  array['Parrilla', 'Pastas', 'Salsas'], 'partidas');
select is((select array_agg(name || ' ' || trim_scale(capacity) || ' ' || capacity_label order by name) from catalog.kitchen_equipment
            where group_id = pg_temp.u(1)), array['Horno combi 10 bandejas GN 1/1', 'Pastera 6 canastos'], 'equipos, con su capacidad');
select is((select array_agg(m.name || ' ' || trim_scale(m.content) || ' ' || u.code order by m.name collate "C")
             from catalog.practical_measures m join catalog.units u on u.id = m.content_unit_id where m.group_id = pg_temp.u(1)),
  array['Cucharada 15 ml', 'Cucharadita 5 ml', 'Cucharón 120 ml', 'Nido de pasta 120 g', 'Taza 240 ml'], 'medidas prácticas');
select catalog.install_default_lists(pg_temp.u(1));
select is((select count(*)::int from catalog.practical_measures where group_id = pg_temp.u(1)), 5, 'se puede repetir sin duplicar');

-- ---------------------------------------------------------------------------
-- Restricciones de las tablas
-- ---------------------------------------------------------------------------
select throws_ok($$insert into catalog.kitchen_sectors (group_id, name) values (pg_temp.u(1), ' cocina  FRIA ')$$, '23505', null,
  'el mismo nombre con otras mayúsculas, tildes o espacios, no');
select throws_ok($$insert into catalog.kitchen_sectors (group_id, name) values (pg_temp.u(1), '   ')$$, '23514', null, 'vacío, no');
select throws_ok($$insert into catalog.kitchen_sectors (group_id, name) values (pg_temp.u(1), '<b>Barra</b>')$$, '23514', null, 'con < o >, no');
select throws_ok($$insert into catalog.kitchen_sectors (group_id, name) values (pg_temp.u(1), U&'Bar\200Bra')$$, '22023', null,
  'con caracteres que no se ven, no');
select throws_ok($$insert into catalog.kitchen_equipment (group_id, name, capacity) values (pg_temp.u(1), 'Olla', 5)$$, '23514', null,
  'una capacidad sin unidad ni palabra, no');
select throws_ok($$insert into catalog.kitchen_equipment (group_id, name, capacity_label) values (pg_temp.u(1), 'Olla', 'litros')$$,
  '23514', null, 'una palabra sin número, no');
select throws_ok($$insert into catalog.kitchen_equipment (group_id, name, capacity, capacity_unit_id, capacity_label)
  values (pg_temp.u(1), 'Olla', 5, (select id from catalog.units where code = 'l'), 'litros')$$, '23514', null, 'las dos formas a la vez, no');
select throws_ok($$insert into catalog.kitchen_equipment (group_id, name, capacity, capacity_unit_id)
  values (pg_temp.u(1), 'Olla', 5, (select id from catalog.units where code = 'box'))$$, '23514', null, 'en un envase, no');
select throws_ok($$insert into catalog.kitchen_equipment (group_id, name, capacity, capacity_label) values (pg_temp.u(1), 'Olla', 'NaN', 'x')$$,
  '23514', null, 'NaN, no');
select throws_ok($$insert into catalog.practical_measures (group_id, name, content, content_unit_id)
  values (pg_temp.u(1), 'Balde', 5, (select id from catalog.units where code = 'l'))$$, '23514', null, 'una medida en litros, no: en ml');
select throws_ok($$insert into catalog.practical_measures (group_id, name, content, content_unit_id)
  values (pg_temp.u(1), 'Balde', 0, (select id from catalog.units where code = 'ml'))$$, '23514', null, 'que contiene cero, no');

-- ---------------------------------------------------------------------------
-- Quién entra y quién edita cada lista
-- ---------------------------------------------------------------------------
create function pg_temp.editable(p_user int) returns text language sql as $$
  select string_agg(l ->> 'list', ',' order by n)
    from jsonb_array_elements(pg_temp.q(pg_temp.u(p_user), format('select catalog.settings_lists(%L)::text', pg_temp.u(1)))::jsonb)
         with ordinality t (l, n) where (l ->> 'can_edit')::boolean
$$;
select is(pg_temp.editable(408), 'ingredient_categories,sectors,stations,equipment,measures,units', 'Compras: las suyas y las de la cocina');
select is(pg_temp.editable(413), 'recipe_categories,sectors,stations,equipment,measures,processes', 'el Chef del grupo: las suyas y las de la cocina');
select is(pg_temp.editable(401), 'ingredient_categories,recipe_categories,sectors,stations,equipment,measures,units',
  'el Superadministrador: todas menos los procesos, que aprueba el Chef');
select matches(pg_temp.q(pg_temp.u(409), format('select catalog.settings_lists(%L)::text', pg_temp.u(1))), '^ERROR No tenés permiso',
  'la cocinera no entra');
select matches(pg_temp.q(pg_temp.u(404), format('select catalog.settings_lists(%L)::text', pg_temp.u(1))), '^ERROR No tenés permiso', 'el gerente tampoco');
select matches(pg_temp.q(pg_temp.u(405), format('select catalog.settings_list(%L, ''sectors'')::text', pg_temp.u(1))), '^ERROR No tenés permiso',
  'la chef de una marca tampoco');
select matches(pg_temp.q(pg_temp.u(406), format('select catalog.settings_list(%L, ''measures'')::text', pg_temp.u(1))), '^ERROR No tenés permiso',
  'ni el jefe de cocina de un local');
select matches(pg_temp.q(pg_temp.u(401), format('select catalog.settings_lists(%L)::text', pg_temp.u(60001))), '^ERROR No tenés permiso',
  'nadie lee la configuración de otro grupo');
select is(pg_temp.list(408, 'processes') ->> 'can_edit', 'false', 'Compras lee los procesos');
select cmp_ok(jsonb_array_length(pg_temp.list(408, 'processes') -> 'rows'), '>=', 5, 'y los ve');
select is(pg_temp.list(413, 'units') ->> 'can_edit', 'false', 'el Chef del grupo lee las unidades');
select is((select (l ->> 'active')::int from jsonb_array_elements(
             pg_temp.q(pg_temp.u(401), format('select catalog.settings_lists(%L)::text', pg_temp.u(1)))::jsonb) l where l ->> 'list' = 'measures'), 5,
  'cuántos activos tiene cada lista');

select is(pg_temp.save(405, 'sectors', '[{"name": "Barra"}]'), 'denied: No tenés permiso para editar esta lista.', 'la chef de una marca no edita');
select is(pg_temp.save(409, 'measures', '[{"name": "Barra"}]'), 'denied: No tenés permiso para editar esta lista.', 'la cocinera, tampoco');
select is(pg_temp.save(408, 'processes', '[{"name": "Curado", "code": "CURADO"}]'), 'denied: No tenés permiso para editar esta lista.',
  'Compras no edita procesos');
select is(pg_temp.save(413, 'units', pg_temp.item((select id from catalog.units where code = 'kg'), '{"name": "Kilo"}')),
  'denied: No tenés permiso para editar esta lista.', 'el Chef del grupo no edita unidades');
select is(pg_temp.save(413, 'ingredient_categories', '[{"name": "X"}]'), 'denied: No tenés permiso para editar esta lista.', 'ni categorías de materias primas');
select is(pg_temp.save(408, 'recipe_categories', '[{"name": "X"}]'), 'denied: No tenés permiso para editar esta lista.', 'Compras, ni las de recetas');
select is(pg_temp.save(401, 'sectors', '[{"name": "X"}]', p_group => 60001), 'denied: No tenés permiso para editar esta lista.', 'ni en otro grupo');
select is(pg_temp.denials(), 7, 'cada rechazo queda registrado');
select is((select count(*)::int from catalog.kitchen_sectors where name in ('Barra', 'X')), 0, 'y no se guardó nada');

-- ---------------------------------------------------------------------------
-- Guardar
-- ---------------------------------------------------------------------------
select is(pg_temp.save(408, 'sectors', '[{"name": "Barra"}]', ''), 'ERROR Escribí el motivo de los cambios (de 3 a 500 caracteres).', 'sin motivo, no');
select is(pg_temp.save(408, 'sectors', '[]'), 'ERROR No hay cambios para guardar.', 'sin cambios, no');
select matches(pg_temp.save(408, 'sectors', '[{"name": "Barra", "group_id": "x"}]'), 'Campos que no se pueden cambiar', 'otras claves, no');
select matches(pg_temp.save(408, 'sectors', '[{"id": "x", "name": "Barra"}]'), 'recargá la página', 'un id mal formado, no');
select matches(pg_temp.save(408, 'sectors', pg_temp.item((select id from catalog.kitchen_sectors where group_id = pg_temp.u(60001) limit 1), '{"name": "Mío"}')),
  'ya no está en la lista', 'un elemento de otro grupo, no');
select is(pg_temp.save(408, 'sectors', '[{"name": {"a": 1}}]'), 'ERROR Algún elemento no es válido: recargá la página.', 'un nombre que no es texto, no');
select matches(pg_temp.save(408, 'sectors', '[{"name": "Ba\u200brra"}]'), 'caracteres que no se ven', 'con caracteres ocultos, no');
select matches(pg_temp.save(408, 'ingredient_categories', '[{"name": "<b>Quesos</b>"}]'), 'lleva < o >', 'ni con < o >, tampoco en las listas de antes');
select matches(pg_temp.save(413, 'processes', '[{"name": "Cu\u202erado", "code": "CURADO"}]'), 'caracteres que no se ven', 'ni en los procesos');
select is(pg_temp.save(408, 'sectors', '[{"name": "Barra"}]', 'Cambio', '2020-01-01'),
  'ERROR Otra persona cambió esta lista mientras la editabas: recargá la página para ver sus cambios.', 'con un sello viejo, no');
select is(pg_temp.save(408, 'sectors', (select jsonb_agg(jsonb_build_object('name', 'S' || n)) from generate_series(1, 101) n)),
  'ERROR Son demasiados cambios juntos: guardá hasta 100 por vez.', 'hasta 100 por vez');

select is(pg_temp.save(413, 'sectors', '[{"name": "  Barra   y  café "}, {"name": "Depósito", "active": false}]', 'Sectores nuevos'),
  'applied: Cambios guardados.', 'el Chef del grupo agrega dos sectores');
select isnt(pg_temp.sector('Barra y café'), null, 'sin espacios de más');
select is((select is_active from catalog.kitchen_sectors where id = pg_temp.sector('Depósito')), false, 'uno nace inactivo');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'kitchen_sectors' and action = 'insert'
                    and actor_user_id = pg_temp.u(413) and reason = 'Sectores nuevos'), 'queda en la auditoría, con el motivo');
select is(pg_temp.save(408, 'sectors', '[{"name": "BARRA Y CAFE"}]'),
  'ERROR Ya hay un elemento con ese nombre en la lista (puede estar inactivo).', 'repetido, no');
select is(pg_temp.save(408, 'sectors', pg_temp.item(pg_temp.sector('Cocina fría'), '{"name": "Garde manger"}') || '[{"name": "pastelería"}]'),
  'ERROR Ya hay un elemento con ese nombre en la lista (puede estar inactivo).', 'todo o nada');
select isnt(pg_temp.sector('Cocina fría'), null, 'no quedó el primer cambio');
select is(pg_temp.save(408, 'sectors', pg_temp.item(pg_temp.sector('Cocina fría'), '{"active": false}')), 'applied: Cambios guardados.', 'se desactiva');
select is(pg_temp.row('sectors', 'Cocina fría') ->> 'active', 'false', 'y se sigue viendo, inactivo');
select is(pg_temp.save(408, 'sectors', pg_temp.item(pg_temp.sector('Cocina fría'), '{"active": true, "name": "Garde manger"}')),
  'applied: Cambios guardados.', 'se reactiva y cambia de nombre en el mismo guardado');
select is((select is_active from catalog.kitchen_sectors where id = pg_temp.sector('Garde manger')), true, 'queda activo');
select is(pg_temp.save(408, 'sectors', pg_temp.item(pg_temp.sector('Garde manger'), '{"name": "  "}')), 'ERROR El nombre no puede quedar vacío.', 'sin nombre, no');

select is(pg_temp.save(413, 'stations', '[{"name": "Plancha"}]'), 'applied: Cambios guardados.', 'una partida');
select is(pg_temp.save(413, 'stations', pg_temp.item((select id from catalog.kitchen_stations where name = 'Plancha'), '{"name": "Plancha y parrilla"}')),
  'applied: Cambios guardados.', 'y cambia de nombre');

-- Equipos.
select is(pg_temp.save(413, 'equipment', '[{"name": "Horno", "capacity": "5,5", "capacity_unit": "kg", "capacity_label": ""}]'),
  'applied: Cambios guardados.', 'un equipo con su capacidad en kg, con coma');
select is((select trim_scale(e.capacity) || ' ' || u.code from catalog.kitchen_equipment e join catalog.units u on u.id = e.capacity_unit_id
            where e.id = pg_temp.equip('Horno')), '5.5 kg', 'guardada');
select is(pg_temp.save(413, 'equipment', pg_temp.item(pg_temp.equip('Horno'), '{"capacity": "8", "capacity_unit": "", "capacity_label": "placas"}')),
  'applied: Cambios guardados.', 'pasa a palabras');
select is((select trim_scale(capacity) || ' ' || capacity_label || coalesce(capacity_unit_id::text, '') from catalog.kitchen_equipment
            where id = pg_temp.equip('Horno')), '8 placas', 'y deja la unidad');
select is(pg_temp.save(413, 'equipment', pg_temp.item(pg_temp.equip('Horno'), '{"capacity": "8"}')),
  'ERROR La capacidad va completa: cuánto y en qué.', 'la capacidad viaja entera');
select is(pg_temp.save(413, 'equipment', pg_temp.item(pg_temp.equip('Horno'), '{"capacity": "ocho", "capacity_unit": "kg", "capacity_label": ""}')),
  'ERROR Revisá los números: alguno no tiene el formato esperado.', 'con letras, no');
select is(pg_temp.save(413, 'equipment', pg_temp.item(pg_temp.equip('Horno'), '{"capacity": "8", "capacity_unit": "kg", "capacity_label": "placas"}')),
  'ERROR La capacidad va completa: cuánto y en qué.', 'las dos formas, no');
select is(pg_temp.save(413, 'equipment', pg_temp.item(pg_temp.equip('Horno'), '{"capacity": "", "capacity_unit": "", "capacity_label": ""}')),
  'applied: Cambios guardados.', 'y se puede sacar');

-- Medidas prácticas.
select is(pg_temp.save(408, 'measures', '[{"name": "Puñado", "content": "30", "content_unit": "g", "usage_note": "Hierbas, verdes"}]'),
  'applied: Cambios guardados.', 'una medida práctica');
select is(pg_temp.row('measures', 'Puñado') ->> 'usage_note', 'Hierbas, verdes', 'con qué se usa');
select is(pg_temp.save(408, 'measures', pg_temp.item(pg_temp.measure('Cucharón'), '{"content": "150,5"}')), 'applied: Cambios guardados.', 'cambia lo que contiene');
select is((select trim_scale(content)::text from catalog.practical_measures where id = pg_temp.measure('Cucharón')), '150.5', 'con coma');
select is(pg_temp.save(408, 'measures', '[{"name": "Balde", "content": "5", "content_unit": "l"}]'),
  'ERROR Lo que contiene la medida va en ml, g o unidades.', 'en litros, no');
select is(pg_temp.save(408, 'measures', '[{"name": "Balde"}]'), 'ERROR Escribí cuánto contiene «Balde» y en qué unidad.', 'sin contenido, no');
select is(pg_temp.save(408, 'measures', pg_temp.item(pg_temp.measure('Taza'), '{"content": "-1"}')), 'ERROR El número tiene que ser mayor que cero y no tan grande.', 'negativo, no');
select is(pg_temp.save(408, 'measures', pg_temp.item(pg_temp.measure('Taza'), '{"content": "NaN"}')),
  'ERROR Revisá los números: alguno no tiene el formato esperado.', 'NaN, no');
select is(pg_temp.save(408, 'measures', pg_temp.item(pg_temp.measure('Taza'), '{"content": "2000000"}')),
  'ERROR El número tiene que ser mayor que cero y no tan grande.', 'ni un disparate');

-- Subcategorías: con las reglas de siempre, y ahora se reactivan.
select is(pg_temp.save(408, 'ingredient_categories', jsonb_build_array(jsonb_build_object('name', 'Vacuna de prueba', 'parent_id',
            (select id from catalog.ingredient_categories where name = 'Carnes' and parent_id is null)))), 'applied: Cambios guardados.', 'una subcategoría');
select is(pg_temp.save(408, 'ingredient_categories', '[{"name": "Suelta"}]'), 'ERROR Elegí el rubro de la subcategoría nueva.', 'sin rubro, no');
select is(pg_temp.save(408, 'ingredient_categories', pg_temp.item((select id from catalog.ingredient_categories where name = 'Vacuna de prueba'), '{"active": false}')),
  'applied: Cambios guardados.', 'vacía, se da de baja');
select is(pg_temp.row('ingredient_categories', 'Vacuna de prueba') ->> 'active', 'false', 'y se ve inactiva');
select is(pg_temp.save(408, 'ingredient_categories', pg_temp.item((select id from catalog.ingredient_categories where name = 'Vacuna de prueba'),
            '{"active": true, "name": "Vacuna otra vez"}')), 'applied: Cambios guardados.', 'se reactiva y cambia de nombre');
select is(pg_temp.save(408, 'ingredient_categories', pg_temp.item((select id from catalog.ingredient_categories where name = 'Carnes' and parent_id is null), '{"active": false}')),
  'ERROR Un rubro se da de baja en Rubros.', 'un rubro, no: va en Rubros');
select is(pg_temp.row('ingredient_categories', 'Carnes') ->> 'why', 'Es un rubro: se da de baja en Rubros.', 'y la pantalla lo dice');
select is(pg_temp.save(413, 'recipe_categories', pg_temp.item((select id from recipes.recipe_categories where parent_id is null and deleted_at is null and is_active limit 1),
            '{"parent_id": "00000000-0000-4000-8000-000000000001"}')), 'ERROR El rubro, el código, el tipo y la equivalencia no cambian.', 'ni cambia de lugar');

-- Procesos y unidades.
select is(pg_temp.save(413, 'processes', '[{"name": "Curado", "code": "curado"}]'), 'applied: Cambios guardados.', 'un proceso');
select is(pg_temp.save(413, 'processes', pg_temp.item((select id from catalog.yield_processes where code = 'PELADO'), '{"active": false}')),
  'ERROR Tiene rendimientos estándar vigentes: no se puede dar de baja.', 'en uso, no se da de baja');
select is(pg_temp.save(408, 'units', '[{"name": "Cucharón de prueba", "abbreviation": "cpr", "code": "cucharon_pr", "dimension": "volume", "factor": "60"}]'),
  'applied: Cambios guardados.', 'una unidad');
select is(pg_temp.save(408, 'units', pg_temp.item((select id from catalog.units where code = 'cucharon_pr'), '{"active": false}')),
  'applied: Cambios guardados.', 'sin usar, se da de baja');
select is(pg_temp.save(408, 'units', pg_temp.item((select id from catalog.units where code = 'cucharon_pr'), '{"active": true}')),
  'applied: Cambios guardados.', 'y se reactiva');
select is((select trim_scale(c.factor)::text || ' ' || u.name from catalog.units u join catalog.unit_conversions c on c.from_unit_id = u.id and c.deleted_at is null
            where u.code = 'cucharon_pr' and u.deleted_at is null), '60 cpr', 'con su equivalencia');
select is(pg_temp.save(408, 'units', pg_temp.item((select id from catalog.units where code = 'cucharon_pr'), '{"active": true}')),
  'applied: Cambios guardados.', 'reactivar lo que ya está activo no rompe nada');
-- El nombre de una unidad lo leen las recetas publicadas: no cambia, ni siquiera el de una cargada a mano.
select is(pg_temp.save(408, 'units', pg_temp.item((select id from catalog.units where code = 'cucharon_pr'), '{"abbreviation": "kg"}')),
  'ERROR Una unidad no cambia de nombre: dala de baja y creá otra.', 'la abreviatura de una unidad no cambia');
select is(pg_temp.save(408, 'units', pg_temp.item((select id from catalog.units where code = 'cucharon_pr'), '{"name": "Kilogramo"}')),
  'ERROR Una unidad no cambia de nombre: dala de baja y creá otra.', 'ni su nombre');
select is(pg_temp.save(408, 'units', '[{"name": "Nada", "abbreviation": "nd", "code": "nada", "dimension": "volume", "factor": "NaN"}]'),
  'ERROR Revisá los números: alguno no tiene el formato esperado.', 'una equivalencia NaN, no');
select throws_ok($$insert into catalog.unit_conversions (from_unit_id, to_unit_id, factor)
  select f.id, t.id, 'NaN' from catalog.units f, catalog.units t where f.code = 'cucharon_pr' and t.code = 'ml'$$, null, null, 'ni directo en la tabla');
select is(pg_temp.save(408, 'units', pg_temp.item((select id from catalog.units where code = 'kg'), '{"name": "Kilo"}')),
  'ERROR Una unidad no cambia de nombre: dala de baja y creá otra.', 'las del sistema, tampoco');
select is((select array_agg(distinct table_name order by table_name) from audit.audit_events
            where table_schema = 'catalog' and actor_user_id in (pg_temp.u(408), pg_temp.u(413))
              and table_name in ('kitchen_sectors', 'kitchen_stations', 'kitchen_equipment', 'practical_measures') and action = 'insert'),
  array['kitchen_equipment', 'kitchen_sectors', 'kitchen_stations', 'practical_measures'], 'las 4 tablas quedan en la auditoría');
select is((select count(*)::int from audit.audit_events where table_schema = 'catalog' and reason = 'Cambio de prueba'
              and table_name in ('units', 'yield_processes', 'ingredient_categories', 'practical_measures', 'kitchen_equipment') and actor_user_id is null), 0,
  'todo quedó con su autor');

select * from finish();
rollback;
