-- El sector, la partida y el equipo de las recetas pasan del texto a las listas del grupo (ADR-0063), sin tocar la historia:
-- un elemento por texto distinto, los borradores quedan vinculados y las versiones que ya no son borrador, iguales.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(41);

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
create function pg_temp.step(p_version uuid, p_n int) returns recipes.recipe_steps language sql as $$
  select s from recipes.recipe_steps s where s.recipe_version_id = p_version and s.step_number = p_n and s.deleted_at is null
$$;
grant execute on function pg_temp.u(int) to authenticated;

-- Dos recetas del grupo con versión vigente y pasos: de una se abre un borrador.
create temporary table t as
  select row_number() over (order by r.code) as n, r.id as recipe_id, v.id as version_id, r.code
    from recipes.recipes r
    join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published' and v.deleted_at is null
   where r.scope_type = 'group' and r.deleted_at is null and r.variant_of_recipe_id is null
     and exists (select 1 from recipes.recipe_steps s where s.recipe_version_id = v.id and s.step_number = 1 and s.deleted_at is null)
   order by r.code limit 3;
grant select on t to authenticated;
select cmp_ok((select count(*)::int from t), '=', 3, 'hay con qué probar');
create function pg_temp.r(p_n int) returns uuid language sql as $$ select recipe_id from t where n = p_n $$;
create function pg_temp.v(p_n int) returns uuid language sql as $$ select version_id from t where n = p_n $$;

-- Así estaban antes de las listas: textos sueltos, sin vincular.
alter table recipes.recipes disable trigger link_lists;
alter table recipes.recipe_steps disable trigger link_lists;
alter table recipes.recipe_steps disable trigger enforce_draft_lines;
update recipes.recipes set sector = 'cocina  FRIA', station = 'Wok' where id = pg_temp.r(1);
update recipes.recipes set sector = 'Barra', station = 'wok' where id = pg_temp.r(2);
update recipes.recipes set sector = 'Barra', station = '<i>rara</i>' where id = pg_temp.r(3);
update recipes.recipe_steps set equipment = 'Horno de barro', sector = 'Patio' where id = (pg_temp.step(pg_temp.v(1), 1)).id;
update recipes.recipe_steps set sector = chr(160) where id = (pg_temp.step(pg_temp.v(2), 1)).id;
update recipes.recipe_steps set equipment = 'HORNO DE BARRO' where id = (pg_temp.step(pg_temp.v(2), 1)).id;
-- La 3 queda en borrador.
create temporary table drafts as select (pg_temp.q(pg_temp.u(413),
  format('select (recipes.new_version(%L, ''Borrador de prueba'') ->> ''id'')', pg_temp.r(3))))::uuid as id;
update recipes.recipe_steps set equipment = 'pastera', sector = 'Cocina caliente', equipment_id = null, sector_id = null
 where id = (pg_temp.step((select id from drafts), 1)).id;
alter table recipes.recipe_steps enable trigger enforce_draft_lines;
alter table recipes.recipe_steps enable trigger link_lists;
alter table recipes.recipes enable trigger link_lists;

select is((select sector_id from recipes.recipes where id = pg_temp.r(1)), null, 'antes: sin vincular');
create temporary table before_published as
  select s.id, to_jsonb(s) as row from recipes.recipe_steps s join recipes.recipe_versions v on v.id = s.recipe_version_id
   where v.status <> 'draft';
create temporary table before_versions as select v.id, to_jsonb(v) as row from recipes.recipe_versions v;

select core.set_change_context('Paso a las listas (prueba)', 'maintenance');
select lives_ok($$select recipes.link_lists_from_text(pg_temp.u(1))$$, 'pasa lo cargado a las listas');

-- Un elemento por cada texto distinto; si ya estaba, se usa ese.
select is((select count(*)::int from catalog.kitchen_sectors where group_id = pg_temp.u(1) and catalog.list_key(name) = 'cocina fria'), 1,
  'el que ya estaba no se repite');
select is((select count(*)::int from catalog.kitchen_stations where group_id = pg_temp.u(1) and catalog.list_key(name) = 'wok'), 1,
  'dos escrituras del mismo texto son un elemento');
select is((select count(*)::int from catalog.kitchen_sectors where group_id = pg_temp.u(1) and name = 'Barra'), 1, 'y uno nuevo por texto');
select is((select count(*)::int from catalog.kitchen_equipment where group_id = pg_temp.u(1) and catalog.list_key(name) = 'horno de barro'), 1,
  'los equipos de las versiones publicadas también llegan a la lista');
select is((select count(*)::int from catalog.kitchen_sectors where group_id = pg_temp.u(1) and name = 'Patio'), 1, 'y los sectores de sus pasos');
select is((select count(*)::int from catalog.kitchen_stations where name ~ '[<>]'), 0, 'lo que la lista no acepta no llega');
select is((select count(*)::int from catalog.kitchen_sectors where catalog.list_key(name) = ''), 0, 'un texto que es solo un espacio duro no corta el paso');
select is((select (r ->> 'uses')::int from jsonb_array_elements(pg_temp.q(pg_temp.u(413), format('select (catalog.settings_list(%L, ''sectors'') -> ''rows'')::text', pg_temp.u(1)))::jsonb) r
            where r ->> 'name' = 'Patio'), 1, 'un sector usado solo en un paso también cuenta');

-- La receta queda vinculada y sigue el nombre de la lista.
select is((select k.name || '|' || r.sector from recipes.recipes r join catalog.kitchen_sectors k on k.id = r.sector_id where r.id = pg_temp.r(1)),
  'Cocina fría|Cocina fría', 'la receta queda vinculada, con el nombre de la lista');
select is((select count(distinct station_id)::int from recipes.recipes where id in (pg_temp.r(1), pg_temp.r(2)) and station_id is not null), 1,
  'las dos recetas, a la misma partida');
select is((select station || '|' || (station_id is null) from recipes.recipes where id = pg_temp.r(3)), '<i>rara</i>|true',
  'lo que no pasa queda como texto');
select is((pg_temp.step((select id from drafts), 1)).equipment_id, (select id from catalog.kitchen_equipment where name = 'Pastera' and group_id = pg_temp.u(1)),
  'el borrador queda vinculado al equipo');
select is((pg_temp.step((select id from drafts), 1)).sector_id, (select id from catalog.kitchen_sectors where name = 'Cocina caliente' and group_id = pg_temp.u(1)),
  'y al sector');

-- La historia no se toca.
select is((select count(*)::int from before_published b join recipes.recipe_steps s on s.id = b.id where to_jsonb(s) is distinct from b.row), 0,
  'los pasos de las versiones que no son borrador quedan iguales, columna por columna');
select is((select count(*)::int from before_versions b join recipes.recipe_versions v on v.id = b.id where to_jsonb(v) is distinct from b.row), 0,
  'y ninguna versión cambia (ni su sello)');
select ok(exists (select 1 from audit.audit_events where table_schema = 'recipes' and table_name = 'recipes' and record_id = pg_temp.r(1)
                    and reason = 'Paso a las listas (prueba)' and source = 'maintenance'), 'el vínculo queda en la auditoría');
select lives_ok($$select recipes.link_lists_from_text(pg_temp.u(1))$$, 'se puede repetir');
select is((select count(*)::int from catalog.kitchen_equipment where group_id = pg_temp.u(1)), 3, 'sin duplicar');

-- Una versión nueva de una publicada se vincula sola por el nombre.
create temporary table copies as select (pg_temp.q(pg_temp.u(413),
  format('select (recipes.new_version(%L, ''Versión nueva de prueba'') ->> ''id'')', pg_temp.r(1))))::uuid as id;
select is((select e.name from catalog.kitchen_equipment e where e.id = (pg_temp.step((select id from copies), 1)).equipment_id),
  (select name from catalog.kitchen_equipment where catalog.list_key(name) = 'horno de barro'), 'la copia se vincula sola');

-- Cambiar el nombre en la lista: lo siguen la receta y los borradores, y lo publicado no.
create function pg_temp.rename(p_list text, p_id uuid, p_name text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(413), format('select catalog.save_settings_list(%L, %L, %L, %L, %L) ->> ''result''', pg_temp.u(1), p_list,
    catalog.settings_list_stamp(p_list::catalog.settings_list, pg_temp.u(1)), jsonb_build_array(jsonb_build_object('id', p_id, 'name', p_name)), 'Nombre más claro'))
$$;
select is(pg_temp.rename('equipment', (pg_temp.step((select id from copies), 1)).equipment_id, 'Horno a leña'), 'applied', 'el equipo cambia de nombre');
select is((pg_temp.step((select id from copies), 1)).equipment, 'Horno a leña', 'el borrador lo sigue');
select is((pg_temp.step(pg_temp.v(1), 1)).equipment, 'Horno de barro', 'la versión publicada conserva el suyo');
select is(pg_temp.rename('sectors', (select sector_id from recipes.recipes where id = pg_temp.r(1)), 'Garde manger'), 'applied', 'el sector cambia de nombre');
select is((select sector from recipes.recipes where id = pg_temp.r(1)), 'Garde manger', 'la receta lo sigue');
select is(pg_temp.rename('stations', (select station_id from recipes.recipes where id = pg_temp.r(2)), 'Wok y salteados'), 'applied', 'la partida cambia de nombre');
select is((select string_agg(distinct station, ',') from recipes.recipes where id in (pg_temp.r(1), pg_temp.r(2))), 'Wok y salteados', 'en las dos recetas');

-- Una versión en revisión conserva el nombre y, si vuelve a borrador, toma el de hoy.
select is(pg_temp.q(pg_temp.u(413), format('select recipes.request_review(%L, ''A revisar'') ->> ''result''', (select id from copies))), 'pending_approval', 'se manda a revisión');
select is(pg_temp.rename('equipment', (pg_temp.step((select id from copies), 1)).equipment_id, 'Horno de piedra'), 'applied', 'el equipo cambia otra vez');
select is((pg_temp.step((select id from copies), 1)).equipment, 'Horno a leña', 'en revisión conserva el suyo');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.withdraw_review(%L, ''La retiro'') ->> ''result''', (select id from copies))), 'applied', 'se retira');
select is((pg_temp.step((select id from copies), 1)).equipment, 'Horno de piedra', 'al volver a borrador toma el de hoy');
select isnt((pg_temp.step((select id from copies), 1)).equipment_id, null, 'y sigue vinculado');

-- La ficha de hoy sigue mandando texto: se vincula si coincide, y si no, queda como texto.
select is(pg_temp.q(pg_temp.u(413), format('select recipes.update_recipe(%L, ''{"sector": "PASTELERIA", "station": "Emplatado libre"}'', ''Cambio'') ->> ''result''', pg_temp.r(2))),
  'applied', 'la ficha guarda texto');
select is((select k.name || '|' || r.sector from recipes.recipes r join catalog.kitchen_sectors k on k.id = r.sector_id where r.id = pg_temp.r(2)),
  'Pastelería|PASTELERIA', 'el sector coincide y queda vinculado');
select is((select station || '|' || (station_id is null) from recipes.recipes where id = pg_temp.r(2)), 'Emplatado libre|true', 'la partida no está: queda como texto');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.update_recipe(%L, ''{"sector": ""}'', ''Cambio'') ->> ''result''', pg_temp.r(2))), 'applied', 'vaciar el texto');
select is((select coalesce(sector, '-') || (sector_id is null) from recipes.recipes where id = pg_temp.r(2)), '-true', 'saca también el vínculo');
select throws_ok(format('update recipes.recipes set sector_id = %L where id = %L', gen_random_uuid(), pg_temp.r(2)), '22023', null,
  'un sector que no existe, no');

select * from finish();
rollback;
