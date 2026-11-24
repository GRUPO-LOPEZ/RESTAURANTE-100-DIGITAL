-- Medida práctica de cada ingrediente (Tanda 2 de Soy, PR B, ADR-0064): la cuenta (misma clase, o peso por unidad; nunca la
-- densidad), lo corregido a mano, la versión congelada, la copia, la lista que cambia y quién la ve. Y el sector, la
-- partida y el equipo elegidos de la lista.
-- Personas del seed: ...0405 chef de marca, ...0408 compras, ...0409 cocinera, ...0413 chef del grupo.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(76);

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
create function pg_temp.unit(p_code text) returns uuid language sql as $$ select id from catalog.units where code = p_code $$;
create function pg_temp.m(p_name text) returns uuid language sql as $$
  select id from catalog.practical_measures where name = p_name and group_id = pg_temp.u(1)
$$;
create function pg_temp.n(p_ing int, p_qty numeric, p_unit text, p_measure text) returns numeric language sql as $$
  select trim_scale(recipes.measure_count_for(pg_temp.u(p_ing), p_qty, pg_temp.unit(p_unit), m.content, m.content_unit_id))
    from catalog.practical_measures m where m.id = pg_temp.m(p_measure)
$$;

-- Una medida en unidades, para el limón (tiene peso por unidad: 120 g).
insert into catalog.practical_measures (group_id, name, content, content_unit_id) values (pg_temp.u(1), 'Par', 2, pg_temp.unit('unit'));

-- ---------------------------------------------------------------------------
-- La cuenta
-- ---------------------------------------------------------------------------
select is(pg_temp.n(827, 480, 'g', 'Nido de pasta'), 4::numeric, 'peso con peso: 480 g son 4 nidos de 120 g');
select is(pg_temp.n(827, 1.2, 'kg', 'Nido de pasta'), 10::numeric, 'en kilos también');
select is(pg_temp.n(823, 360, 'ml', 'Taza'), 1.5::numeric, 'volumen con volumen');
select is(pg_temp.n(823, 2, 'tbsp', 'Cucharada'), 2::numeric, 'una cucharada es una cucharada');
select is(pg_temp.n(823, 1, 'l', 'Taza'), 4.17::numeric, 'con 2 decimales');
select is(pg_temp.n(823, 0.01, 'ml', 'Taza'), 0.01::numeric, 'un poco nunca es cero');
select is(pg_temp.n(827, 480, 'g', 'Taza'), null, 'peso con volumen, no');
select is(pg_temp.n(833, 480, 'g', 'Taza'), null, 'ni aunque la materia prima tenga densidad (aceite de oliva)');
select is(pg_temp.n(833, 20, 'ml', 'Nido de pasta'), null, 'ni al revés');
select is(pg_temp.n(826, 6, 'unit', 'Par'), 3::numeric, 'unidades con unidades');
select is(pg_temp.n(809, 1, 'unit', 'Nido de pasta'), 1::numeric, 'unidades con peso: con el peso por unidad (limón de 120 g)');
select is(pg_temp.n(809, 480, 'g', 'Par'), 2::numeric, 'y peso con unidades');
select is(pg_temp.n(826, 6, 'unit', 'Nido de pasta'), null, 'sin peso por unidad, no');
select is((select recipes.measure_count_for(null, 480, pg_temp.unit('g'), 120, pg_temp.unit('g'))), 4.00, 'una preparación, en la clase de su rendimiento');
select is((select recipes.measure_count_for(null, 4, pg_temp.unit('unit'), 120, pg_temp.unit('g'))), null, 'sin peso por unidad');

-- ---------------------------------------------------------------------------
-- Guardar
-- ---------------------------------------------------------------------------
create temporary table t as
  select r.id as recipe_id, v.id as published_id
    from recipes.recipes r join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published'
   where r.code = 'DEMO-SAL-01';
grant select on t to authenticated;
create temporary table d as select (pg_temp.q(pg_temp.u(413),
  format('select recipes.new_version(%L, ''Prueba'') ->> ''id''', (select recipe_id from t))))::uuid as id;
grant select on d to authenticated;
create function pg_temp.save(p_lines jsonb, p_user int default 413) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select coalesce(r ->> ''result'', ''?'') from recipes.set_components(%L, %L, ''Prueba'') r', (select id from d), p_lines))
$$;
create function pg_temp.line(p_ing int, p_qty text, p_unit text, p_measure text, p_count text default null) returns jsonb language sql as $$
  select jsonb_build_object('ingredient_id', pg_temp.u(p_ing), 'quantity', p_qty, 'unit', p_unit)
         || case when p_measure is null then '{}'::jsonb else jsonb_build_object('measure_id', pg_temp.m(p_measure)) end
         || case when p_count is null then '{}'::jsonb else jsonb_build_object('measure_count', p_count) end
$$;
create function pg_temp.shows(p_version uuid, p_n int) returns text language sql as $$
  select trim_scale(measure_count) || ' ' || measure_name || ' de ' || trim_scale(measure_content) || ' ' || u.code || case when measure_manual then ' (a mano)' else '' end
    from recipes.recipe_components c join catalog.units u on u.id = c.measure_unit_id
   where recipe_version_id = p_version and line_order = p_n and c.deleted_at is null
$$;
select is(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta'), pg_temp.line(823, '300', 'ml', null),
                                         pg_temp.line(833, '30', 'ml', 'Cucharada', '2,5'))), 'applied', 'se guardan las líneas');
select is(pg_temp.shows((select id from d), 1), '4 Nido de pasta de 120 g', 'calculada');
select is(pg_temp.shows((select id from d), 2), null, 'sin medida práctica');
select is(pg_temp.shows((select id from d), 3), '2.5 Cucharada de 15 ml (a mano)', 'corregida a mano, con coma');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Taza'))), 'no es de la misma clase', 'de otra clase, no');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Taza', '2'))), 'no es de la misma clase', 'ni a mano');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta', '0'))), 'mayor que cero', 'cero, no');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta', 'NaN'))), 'mayor que cero|no es válido', 'NaN, no');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta', 'cuatro'))), 'no es válido', 'letras, no');
insert into org.groups (id, name) values (pg_temp.u(60001), 'Otro grupo');
insert into catalog.practical_measures (id, group_id, name, content, content_unit_id) values (pg_temp.u(60002), pg_temp.u(60001), 'Ajena', 10, pg_temp.unit('g'));
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', null) || jsonb_build_object('measure_id', pg_temp.u(60002)))),
  'elegí una medida práctica de la lista', 'de otro grupo, no');
select is(pg_temp.shows((select id from d), 1), '4 Nido de pasta de 120 g', 'lo rechazado no cambió nada');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta', '0.0000001'))), 'mayor que cero', 'lo que redondea a cero, no');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta', '999999.9999999'))), 'mayor que cero', 'ni lo que redondea al tope');
select is(pg_temp.save(jsonb_build_array(pg_temp.line(809, '3', 'unit', 'Nido de pasta'), pg_temp.line(827, '480', 'g', 'Nido de pasta'))), 'applied',
  'con el peso por unidad del limón');
select is(pg_temp.shows((select id from d), 1), '3 Nido de pasta de 120 g', 'tres limones son 3 medidas de 120 g');
select is(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta'), pg_temp.line(823, '300', 'ml', null),
                                         pg_temp.line(833, '30', 'ml', 'Cucharada', '2,5'))), 'applied', 'se vuelve a las líneas de antes');
select is(pg_temp.save(jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta')), 409), 'denied', 'la cocinera no guarda');
select throws_ok(format('update recipes.recipe_components set measure_name = null where recipe_version_id = %L and measure_name is not null and deleted_at is null', (select id from d)),
  '23514', null, 'la medida va entera o no va');
select ok(exists (select 1 from audit.audit_events where table_schema = 'recipes' and table_name = 'recipe_components'
                    and actor_user_id = pg_temp.u(413) and new_values ->> 'measure_name' = 'Nido de pasta'), 'queda en la auditoría');

-- ---------------------------------------------------------------------------
-- La lista cambia: lo siguen los borradores; lo publicado, congelado
-- ---------------------------------------------------------------------------
create temporary table frozen as
  select c.id, to_jsonb(c) as row from recipes.recipe_components c join recipes.recipe_versions v on v.id = c.recipe_version_id
   where v.status <> 'draft';
create function pg_temp.measure(p_name text, p_more jsonb) returns text language sql as $$
  select pg_temp.q(pg_temp.u(413), format('select catalog.save_settings_list(%L, ''measures'', %L, %L, ''Cambio'') ->> ''result''', pg_temp.u(1),
    catalog.settings_list_stamp('measures', pg_temp.u(1)), jsonb_build_array(jsonb_build_object('id', pg_temp.m(p_name)) || p_more)))
$$;
select is(pg_temp.measure('Nido de pasta', '{"content": "100", "name": "Nido chico"}'), 'applied', 'el nido pasa a 100 g');
select is(pg_temp.shows((select id from d), 1), '4.8 Nido chico de 100 g', 'el borrador se recalcula');
select is(pg_temp.measure('Cucharada', '{"content": "20"}'), 'applied', 'la cucharada pasa a 20 ml');
select is(pg_temp.shows((select id from d), 3), '2.5 Cucharada de 20 ml (a mano)', 'lo corregido a mano conserva el número');
select matches(pg_temp.measure('Cucharada', '{"content_unit": "g"}'), 'ya se usa en recetas', 'una medida en uso no cambia de clase');
select is((select count(*)::int from frozen f join recipes.recipe_components c on c.id = f.id where to_jsonb(c) is distinct from f.row), 0,
  'ninguna línea que no es borrador cambia, columna por columna');

-- En revisión queda como está; al volver a borrador se pone al día.
select is(pg_temp.q(pg_temp.u(413), format('select recipes.request_review(%L, ''A revisar'') ->> ''result''', (select id from d))), 'pending_approval', 'se manda a revisión');
select is(pg_temp.measure('Nido chico', '{"content": "120"}'), 'applied', 'el nido vuelve a 120 g');
select is(pg_temp.shows((select id from d), 1), '4.8 Nido chico de 100 g', 'en revisión, congelada');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.withdraw_review(%L, ''La retiro'') ->> ''result''', (select id from d))), 'applied', 'se retira');
select is(pg_temp.shows((select id from d), 1), '4 Nido chico de 120 g', 'al volver a borrador, la de hoy');

-- Quien revisa ve lo que cambió; la cocinera, no.
select is(pg_temp.q(pg_temp.u(409), format('select count(*)::text from recipes.version_measure_diff(%L)', (select id from d))), '0',
  'la cocinera no ve las diferencias de un borrador');

-- Una inactiva sigue donde estaba y no se agrega donde no estaba.
select is(pg_temp.measure('Nido chico', '{"active": false}'), 'applied', 'se desactiva');
select is(pg_temp.save(jsonb_build_array(pg_temp.line(827, '600', 'g', 'Nido chico'))), 'applied', 'donde ya estaba, sigue');
select is(pg_temp.measure('Taza', '{"active": false}'), 'applied', 'otra se desactiva');
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(823, '240', 'ml', 'Taza'))), 'ya no se usa', 'donde no estaba, no');
select is((select (r ->> 'uses')::int from jsonb_array_elements(pg_temp.q(pg_temp.u(413), format('select (catalog.settings_list(%L, ''measures'') -> ''rows'')::text', pg_temp.u(1)))::jsonb) r
            where r ->> 'name' = 'Nido chico'),
  (select count(distinct v.recipe_id)::int from recipes.recipe_components c join recipes.recipe_versions v on v.id = c.recipe_version_id
     join recipes.recipes r on r.id = v.recipe_id and r.deleted_at is null
    where c.practical_measure_id = pg_temp.m('Nido chico') and c.deleted_at is null and v.status <> 'archived' and v.deleted_at is null),
  'la lista dice cuántas recetas la usan');

-- La copia de una versión.
create temporary table p as
  select r.id as recipe_id, v.id as version_id, c.line_order as line
    from recipes.recipes r join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published'
    join recipes.recipe_components c on c.recipe_version_id = v.id and c.measure_name = 'Cucharadita' and c.deleted_at is null
   where r.code = 'DEMO-PAR-06';
grant select on p to authenticated;
select is(pg_temp.shows((select version_id from p), (select line::int from p)), '2 Cucharadita de 5 ml', 'la publicada lleva 2 cucharaditas');
select is(pg_temp.measure('Cucharadita', '{"content": "10"}'), 'applied', 'la cucharadita pasa a 10 ml');
create temporary table copied as select (pg_temp.q(pg_temp.u(413),
  format('select recipes.new_version(%L, ''Prueba'') ->> ''id''', (select recipe_id from p))))::uuid as id;
select is(pg_temp.shows((select id from copied), (select line::int from p)), '1 Cucharadita de 10 ml', 'la versión nueva la toma de hoy');
select is(pg_temp.shows((select version_id from p), (select line::int from p)), '2 Cucharadita de 5 ml', 'la publicada conserva la suya');
select is((select count(*)::int from recipes.recipe_components a join recipes.recipe_components b on b.recipe_version_id = (select id from copied) and b.line_order = a.line_order and b.deleted_at is null
            where a.recipe_version_id = (select version_id from p) and a.deleted_at is null
              and (a.ingredient_id, a.quantity, a.unit_id, a.notes, a.no_scale) is distinct from (b.ingredient_id, b.quantity, b.unit_id, b.notes, b.no_scale)), 0,
  'y lo demás se copia igual');
select is((select count(*)::int from audit.audit_events where table_schema = 'recipes' and table_name = 'recipe_components' and action = 'update'
             and record_id in (select id from recipes.recipe_components where recipe_version_id = (select id from copied))), 0,
  'la copia no deja cambios de más en la auditoría');
-- Quien trabaja la receta ve qué medida cambió, con lo que contiene.
select is(pg_temp.q(pg_temp.u(413), format('select string_agg(old_measures || '' → '' || new_measures, ''; '') from recipes.version_measure_diff(%L)', (select id from copied))),
  '2 × Cucharadita de 5 ml → 1 × Cucharadita de 10 ml', 'lo que cambió, medida por medida');
-- Una medida achicada de más: con un borrador que la usa, la lista lo rechaza; sin borradores, una versión nueva no se traba.
select matches(pg_temp.measure('Cucharadita', '{"content": "0,000001"}'), 'demasiadas medidas', 'con un borrador que la usa, se rechaza');
select is(pg_temp.shows((select id from copied), (select line::int from p)), '1 Cucharadita de 10 ml', 'y el borrador queda igual, sin pasar a mano');
update recipes.recipe_versions set deleted_at = now() where id = (select id from copied);
select is(pg_temp.measure('Cucharadita', '{"content": "0,000001"}'), 'applied', 'sin borradores, se acepta');
create temporary table capped as select (pg_temp.q(pg_temp.u(413),
  format('select recipes.new_version(%L, ''Prueba'') ->> ''id''', (select id from recipes.recipes where code = 'DEMO-CAF-02'))))::uuid as id;
select is(pg_temp.shows((select id from capped), 5), '2 Cucharadita de 0.000001 ml (a mano)', 'y la versión nueva conserva el número, a mano');

-- Sin peso por unidad (el huevo), una medida en gramos avisa.
select matches(pg_temp.save(jsonb_build_array(pg_temp.line(826, '3', 'unit', 'Nido chico'))), 'no es de la misma clase', 'sin peso por unidad, no');
-- La partida de la lista.
select is(pg_temp.q(pg_temp.u(413), format('select recipes.update_recipe(%L, %L, ''Prueba'') ->> ''result''', (select recipe_id from t),
  jsonb_build_object('station_id', (select id from catalog.kitchen_stations where name = 'Salsas' and group_id = pg_temp.u(1))))), 'applied', 'se elige la partida');
select is((select station from recipes.recipes where id = (select recipe_id from t)), 'Salsas', 'con su nombre');
-- Guardar una lista dice qué creó.
select is(jsonb_array_length((pg_temp.q(pg_temp.u(413), format('select catalog.save_settings_list(%L, ''sectors'', %L, %L, ''Prueba'')::text', pg_temp.u(1),
  catalog.settings_list_stamp('sectors', pg_temp.u(1)), '[{"name": "Sector creado"}]')))::jsonb -> 'created'), 1, 'guardar una lista devuelve lo creado');

-- ---------------------------------------------------------------------------
-- La cocina
-- ---------------------------------------------------------------------------
select is((select c ->> 'measure_name' from jsonb_array_elements(
             pg_temp.q(pg_temp.u(413), format('select (recipes.kitchen_card(r.id) -> ''components'')::text from recipes.recipes r where r.code = %L', 'DEMO-PAR-06'))::jsonb) c
            where c ->> 'ingredient' = 'Aceite de oliva'), 'Cucharadita', 'la ficha de cocina lleva la medida práctica');

-- ---------------------------------------------------------------------------
-- Sector, partida y equipo de la lista
-- ---------------------------------------------------------------------------
create function pg_temp.upd(p_changes jsonb) returns text language sql as $$
  select pg_temp.q(pg_temp.u(413), format('select recipes.update_recipe(%L, %L, ''Prueba'') ->> ''result''', (select recipe_id from t), p_changes))
$$;
create function pg_temp.sector(p text) returns uuid language sql as $$ select id from catalog.kitchen_sectors where name = p and group_id = pg_temp.u(1) $$;
select is(pg_temp.upd(jsonb_build_object('sector_id', pg_temp.sector('Cocina fría'))), 'applied', 'se elige el sector');
select is((select sector from recipes.recipes where id = (select recipe_id from t)), 'Cocina fría', 'el texto es el nombre de la lista');
update catalog.kitchen_sectors set is_active = false where id = pg_temp.sector('Pastelería');
select is(pg_temp.upd(jsonb_build_object('sector_id', pg_temp.sector('Pastelería'))), 'ERROR Elegí un sector activo de la lista.', 'inactivo, no');
update catalog.kitchen_sectors set is_active = false where id = pg_temp.sector('Cocina fría');
select is(pg_temp.upd(jsonb_build_object('sector_id', pg_temp.sector('Cocina fría'), 'short_name', 'Fileto')), 'applied', 'el que ya tenía, aunque esté inactivo, sí');
select is(pg_temp.upd('{"sector_id": ""}'), 'applied', 'se saca');
select is((select coalesce(sector, '-') || (sector_id is null) from recipes.recipes where id = (select recipe_id from t)), '-true', 'con su texto');
create function pg_temp.equip(p text) returns uuid language sql as $$ select id from catalog.kitchen_equipment where name = p and group_id = pg_temp.u(1) $$;
create function pg_temp.steps(p_step jsonb) returns text language sql as $$
  select pg_temp.q(pg_temp.u(413), format('select recipes.set_steps(%L, %L, ''Prueba'') ->> ''result''', (select id from d),
    jsonb_build_array(jsonb_build_object('instructions', 'Hervir', 'kind', 'cooking') || p_step)))
$$;
select is(pg_temp.steps(jsonb_build_object('equipment_id', pg_temp.equip('Pastera'))), 'applied', 'se elige el equipo');
select is((select equipment from recipes.recipe_steps where recipe_version_id = (select id from d) and deleted_at is null), 'Pastera', 'con su nombre');
update catalog.kitchen_equipment set is_active = false where name = 'Horno combi' and group_id = pg_temp.u(1);
select is(pg_temp.steps(jsonb_build_object('equipment_id', pg_temp.equip('Horno combi'))), 'ERROR Paso 1: elegí un equipo activo de la lista.', 'inactivo, no');

select * from finish();
rollback;
