-- Fotos de las recetas (ADR-0023, PR 3). Las fotos son parte de la versión: se agregan en un borrador,
-- viajan con la revisión y la cocina ve solo las de la vigente. El bucket privado recipe-media tiene los
-- mismos permisos: sube quien escribe la receta, en su carpeta; lee quien la trabaja o quien ve una
-- versión que tiene la foto registrada y vigente. Nada se borra.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(31);

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
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.rec(p_code text) returns uuid language sql as $$
  select id from recipes.recipes where code = p_code
$$;
create function pg_temp.ver(p_code text, p_number int) returns uuid language sql as $$
  select v.id from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id
   where r.code = p_code and v.version_number = p_number
$$;
-- Un nombre de archivo nuevo en la carpeta de una receta: <grupo>/<receta>/<uuid>.jpg
create function pg_temp.path(p_code text, p_file uuid) returns text language sql as $$
  select format('%s/%s/%s.jpg', pg_temp.u(1), pg_temp.rec(p_code), p_file)
$$;
grant execute on function pg_temp.u(int), pg_temp.rec(text), pg_temp.ver(text, int), pg_temp.path(text, uuid) to authenticated;
create temporary table files (k text primary key, path text);
grant select on files to authenticated;
insert into files values
  ('local', pg_temp.path('DEMO-LOC-01', gen_random_uuid())),
  ('suelta', pg_temp.path('DEMO-LOC-01', gen_random_uuid())),
  ('sin_subir', pg_temp.path('DEMO-LOC-01', gen_random_uuid())),
  ('marca', pg_temp.path('DEMO-PAS-01', gen_random_uuid())),
  ('archivada', pg_temp.path('DEMO-PAS-03', gen_random_uuid())),
  ('parrilla', pg_temp.path('DEMO-PAR-01', gen_random_uuid()));
create function pg_temp.file(p_k text) returns text language sql as $$ select path from files where k = p_k $$;
grant execute on function pg_temp.file(text) to authenticated;
create function pg_temp.sees_file(p_user uuid, p_k text) returns text language sql as $$
  select pg_temp.q(p_user, format('select count(*)::text from storage.objects where bucket_id = %L and name = %L',
                                  'recipe-media', pg_temp.file(p_k)))
$$;

-- Personas: Jefe de Cocina de Demo Pastas Centro 406, Cocinera del mismo local 409, Chef de Demo Pastas 405.

-- ---------------------------------------------------------------------------
-- El bucket
-- ---------------------------------------------------------------------------
select is((select public::text || '/' || file_size_limit || '/' || array_to_string(allowed_mime_types, ',')
             from storage.buckets where id = 'recipe-media'),
  'false/3145728/image/jpeg,image/png,image/webp', 'el bucket es privado, hasta 3 MB y solo imágenes');
select ok(not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                        and cmd in ('UPDATE', 'DELETE', 'ALL')),
  'ningún archivo de Storage se cambia ni se borra: no hay políticas de update ni de delete');
select ok(not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
                        and 'anon' = any (roles)),
  'anon no tiene ninguna política en Storage');

-- ---------------------------------------------------------------------------
-- Subir: quien escribe la receta, en su carpeta, con un nombre válido
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(406), $$insert into storage.objects (bucket_id, name) values ('recipe-media', pg_temp.file('local'))$$),
  'sin error', 'el Jefe de Cocina sube una foto a una receta de su local');
select is(pg_temp.msg(pg_temp.u(406), $$insert into storage.objects (bucket_id, name) values ('recipe-media', pg_temp.file('suelta'))$$),
  'sin error', 'y otra que no va a registrar');
select isnt(pg_temp.msg(pg_temp.u(406), $$insert into storage.objects (bucket_id, name) values ('recipe-media', pg_temp.file('marca'))$$),
  'sin error', 'no a una receta de marca, que no escribe');
select isnt(pg_temp.msg(pg_temp.u(406), $$insert into storage.objects (bucket_id, name)
                                            values ('recipe-media', format('%s/%s/%s.jpg', gen_random_uuid(), pg_temp.rec('DEMO-LOC-01'), gen_random_uuid()))$$),
  'sin error', 'ni en la carpeta de otro grupo');
select isnt(pg_temp.msg(pg_temp.u(406), $$insert into storage.objects (bucket_id, name)
                                            values ('recipe-media', format('%s/%s/../%s.jpg', pg_temp.u(1), pg_temp.rec('DEMO-LOC-01'), gen_random_uuid()))$$),
  'sin error', 'ni con un nombre que se sale de la carpeta');
select isnt(pg_temp.msg(pg_temp.u(406), $$insert into storage.objects (bucket_id, name)
                                            values ('recipe-media', format('%s/%s/foto.exe', pg_temp.u(1), pg_temp.rec('DEMO-LOC-01')))$$),
  'sin error', 'ni con otro nombre o tipo de archivo');
select isnt(pg_temp.msg(pg_temp.u(409), $$insert into storage.objects (bucket_id, name) values ('recipe-media', pg_temp.file('local'))$$),
  'sin error', 'la Cocinera no sube fotos');
select is(pg_temp.q(pg_temp.u(405), $$select (recipes.archive_recipe(pg_temp.rec('DEMO-PAS-03'), 'Sale de la carta')) ->> 'result'$$),
  'applied', 'la Chef archiva una receta');
select isnt(pg_temp.msg(pg_temp.u(405), $$insert into storage.objects (bucket_id, name) values ('recipe-media', pg_temp.file('archivada'))$$),
  'sin error', 'y ya no se le suben fotos');
select is(pg_temp.q(pg_temp.u(406), $$with x as (update storage.objects set name = name || 'x'
                                                   where bucket_id = 'recipe-media' and name = pg_temp.file('local') returning 1)
                                     select count(*)::text from x$$),
  '0', 'ni quien la subió cambia el archivo');

-- ---------------------------------------------------------------------------
-- Las fotos van con la versión: se agregan en un borrador
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(406), $$select recipes.add_media(pg_temp.rec('DEMO-LOC-01'), pg_temp.file('local'), 'plating',
                                                                null, 'Foto nueva')$$),
  'Las fotos van con una versión: creá una versión nueva para agregarlas.', 'sin borrador no se agrega una foto');
select is(pg_temp.q(pg_temp.u(406), $$select (recipes.new_version(pg_temp.rec('DEMO-LOC-01'), 'Fotos')) ->> 'result'$$),
  'applied', 'el Jefe de Cocina abre una versión nueva');
select is(pg_temp.q(pg_temp.u(406), $$select (recipes.add_media(pg_temp.rec('DEMO-LOC-01'), pg_temp.file('local'), 'plating',
                                                                'Emplatado final', 'Foto nueva')) ->> 'result'$$),
  'applied', 'y le agrega la foto subida');
select is((select restaurant_id::text || '/' || (recipe_version_id = pg_temp.ver('DEMO-LOC-01', 2))::text
             from recipes.recipe_media where storage_path = pg_temp.file('local')),
  pg_temp.u(201)::text || '/true', 'la foto queda en el borrador, con el local de la receta');
select ok(exists (select 1 from audit.audit_events where table_name = 'recipe_media' and action = 'insert'
                    and scope_restaurant_id = pg_temp.u(201) and reason = 'Foto nueva'),
  'y en la auditoría, con el alcance de la receta y el motivo');
select is(pg_temp.msg(pg_temp.u(406), $$select recipes.add_media(pg_temp.rec('DEMO-LOC-01'), pg_temp.file('sin_subir'), 'plating',
                                                                null, 'Foto nueva')$$),
  'La foto no se subió bien: probá de nuevo.', 'no se agrega una foto que no está en el bucket');
select is(pg_temp.q(pg_temp.u(409), $$select (recipes.add_media(pg_temp.rec('DEMO-LOC-01'), pg_temp.file('local'), 'step',
                                                                null, 'Intento')) ->> 'result'$$),
  'denied', 'la Cocinera no agrega fotos');

-- La cocina no ve la foto del borrador: ni la fila ni el archivo. Tampoco un archivo nunca registrado.
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_media where recipe_id = pg_temp.rec('DEMO-LOC-01')$$),
  '0', 'la Cocinera no ve las fotos de un borrador');
select is(pg_temp.sees_file(pg_temp.u(409), 'local'), '0', 'ni puede bajar el archivo por la API de Storage');
select is(pg_temp.sees_file(pg_temp.u(409), 'suelta'), '0', 'ni un archivo subido sin registrar');
select is(pg_temp.sees_file(pg_temp.u(406), 'suelta'), '1', 'quien trabaja la receta sí ve todos sus archivos');

-- Al publicar la versión, la cocina ve la foto.
select is(pg_temp.q(pg_temp.u(406), format($$select (recipes.request_review(%L, 'Con foto')) ->> 'result'$$, pg_temp.ver('DEMO-LOC-01', 2))),
  'pending_approval', 'pide la revisión con la foto');
select is(pg_temp.q(pg_temp.u(405), format($$select workflow.decide_approval(%L, 'approved', null) ->> 'result'$$,
                                          (select approval_request_id from recipes.recipe_versions where id = pg_temp.ver('DEMO-LOC-01', 2)))),
  'approved', 'la Chef la aprueba');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_media where recipe_id = pg_temp.rec('DEMO-LOC-01')$$)
          || '/' || pg_temp.sees_file(pg_temp.u(409), 'local'),
  '1/1', 'publicada, la Cocinera ve la foto y baja el archivo');

-- Una versión nueva copia las fotos; la de la vigente no se toca, se quita en el borrador.
select is(pg_temp.q(pg_temp.u(406), $$select (recipes.new_version(pg_temp.rec('DEMO-LOC-01'), 'Sin foto')) ->> 'result'$$),
  'applied', 'otra versión nueva');
select is((select count(*)::int from recipes.recipe_media where recipe_version_id = pg_temp.ver('DEMO-LOC-01', 3) and deleted_at is null),
  1, 'copia la foto de la vigente');
select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.remove_media(%L, 'Intento')$$,
                                            (select id from recipes.recipe_media where recipe_version_id = pg_temp.ver('DEMO-LOC-01', 2)))),
  'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.', 'la foto de la vigente no se quita');
select is(pg_temp.q(pg_temp.u(406), format($$select (recipes.remove_media(%L, 'Se ve oscura')) ->> 'result'$$,
                                          (select id from recipes.recipe_media where recipe_version_id = pg_temp.ver('DEMO-LOC-01', 3)))),
  'applied', 'en el borrador sí se quita, y el archivo sigue en Storage');

select * from finish();
rollback;
