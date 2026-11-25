-- Foto de la materia prima (ADR-0066): una vigente, la anterior queda como historia. Mismo bucket que las fotos de recetas,
-- con permisos propios que no se cruzan con aquellos. Sube quien edita la materia prima; la vigente la ve quien la ve.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(54);

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
    v := 'ERROR ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.path(p_ingredient uuid, p_ext text default 'jpg') returns text language sql as $$
  select format('%s/ingredients/%s/%s.%s', pg_temp.u(1), p_ingredient, gen_random_uuid(), p_ext)
$$;
create temporary table files (k text primary key, path text);
grant select on files to authenticated;
insert into files values
  ('a', pg_temp.path(pg_temp.u(801))), ('b', pg_temp.path(pg_temp.u(801), 'webp')), ('suelta', pg_temp.path(pg_temp.u(801))),
  ('sin_subir', pg_temp.path(pg_temp.u(801))), ('otra', pg_temp.path(pg_temp.u(802))),
  ('receta', format('%s/%s/%s.jpg', pg_temp.u(1), pg_temp.u(1102), gen_random_uuid()));
create function pg_temp.file(p_k text) returns text language sql as $$ select path from files where k = p_k $$;
grant execute on function pg_temp.u(int), pg_temp.file(text) to authenticated;
create function pg_temp.up(p_user int, p_path text) returns text language sql as $$
  select coalesce(pg_temp.q(pg_temp.u(p_user), format('insert into storage.objects (bucket_id, name) values (''recipe-media'', %L) returning ''ok''', p_path)), '')
$$;
create function pg_temp.sees(p_user int, p_k text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select count(*)::text from storage.objects where bucket_id = ''recipe-media'' and name = %L', pg_temp.file(p_k)))
$$;
create function pg_temp.put(p_user int, p_k text, p_reason text default 'Foto del proveedor', p_ing int default 801) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select catalog.set_ingredient_photo(%L, %L, %L) ->> ''result''', pg_temp.u(p_ing), pg_temp.file(p_k), p_reason))
$$;
create function pg_temp.rows(p_user int) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select count(*)::text from catalog.ingredient_media where ingredient_id = %L', pg_temp.u(801)))
$$;

create function pg_temp.aal1(p_user int, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.u(p_user), 'role', 'authenticated', 'aal', 'aal1')::text, true);
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
-- Compras 408 edita; Chef 405 la ve; Jefe de Cocina 406 escribe recetas de su local; Cocinera 409 no ve materias primas.

-- ---------------------------------------------------------------------------
-- Subir
-- ---------------------------------------------------------------------------
select is(pg_temp.up(408, pg_temp.file('a')), 'ok', 'Compras sube la foto de una materia prima');
select is(pg_temp.up(408, pg_temp.file('b')), 'ok', 'y otra, en WebP');
select is(pg_temp.up(408, pg_temp.file('suelta')), 'ok', 'y una que no va a registrar');
select is(pg_temp.up(408, pg_temp.file('otra')), 'ok', 'y la de otra materia prima');
select matches(pg_temp.up(405, pg_temp.path(pg_temp.u(801))), '^ERROR 42501', 'la Chef ve, no sube');
select matches(pg_temp.up(409, pg_temp.path(pg_temp.u(801))), '^ERROR 42501', 'la Cocinera tampoco');
select matches(pg_temp.up(410, pg_temp.path(pg_temp.u(801))), '^ERROR 42501', 'ni el Auditor');
select matches(pg_temp.up(408, format('%s/ingredients/%s/%s.jpg', gen_random_uuid(), pg_temp.u(801), gen_random_uuid())), '^ERROR 42501', 'ni en la carpeta de otro grupo');
select matches(pg_temp.up(408, pg_temp.path(gen_random_uuid())), '^ERROR 42501', 'ni de una materia prima que no existe');
select matches(pg_temp.up(408, format('%s/ingredients/%s/../%s.jpg', pg_temp.u(1), pg_temp.u(801), gen_random_uuid())), '^ERROR 42501', 'ni saliéndose de la carpeta');
select matches(pg_temp.up(408, format('%s/ingredients/%s/foto.jpg', pg_temp.u(1), pg_temp.u(801))), '^ERROR 42501', 'ni con otro nombre');
select matches(pg_temp.up(408, pg_temp.path(pg_temp.u(801), 'svg')), '^ERROR 42501', 'ni de otro tipo');

-- Una cosa no abre la otra.
select matches(pg_temp.up(408, pg_temp.file('receta')), '^ERROR 42501', 'editar materias primas no deja subir fotos de recetas');
select matches(pg_temp.up(406, pg_temp.path(pg_temp.u(801))), '^ERROR 42501', 'escribir recetas no deja subir fotos de materias primas');
select is(recipes.media_recipe_id(pg_temp.file('a')), null, 'para las recetas, el archivo no es de ninguna');
select is(catalog.photo_ingredient_id(pg_temp.file('receta')), null, 'y el de una receta no es de ninguna materia prima');

-- ---------------------------------------------------------------------------
-- Registrar, cambiar y quitar
-- ---------------------------------------------------------------------------
select is(pg_temp.sees(405, 'a'), '0', 'antes de registrarla, la Chef no la ve');
select is(pg_temp.sees(408, 'a'), '1', 'quien la subió, sí');
select is(pg_temp.put(405, 'a'), 'denied', 'la Chef no la cambia');
select is(pg_temp.put(409, 'a'), 'denied', 'ni la Cocinera');
select ok(exists (select 1 from audit.authentication_security_events where operation = 'catalog.set_ingredient_photo'), 'y queda registrado');
select matches(pg_temp.put(408, 'a', ' '), 'Escribí el motivo', 'pide un motivo');
select matches(pg_temp.put(408, 'sin_subir'), 'no se subió bien', 'el archivo tiene que estar subido');
select matches(pg_temp.put(408, 'otra'), 'no se subió bien', 'y ser de esa materia prima');
select is(pg_temp.put(408, 'a'), 'applied', 'Compras la pone');
select is(pg_temp.sees(405, 'a'), '1', 'ahora la Chef la ve');
select is(pg_temp.sees(409, 'a'), '0', 'la Cocinera no: no ve materias primas');
select is(pg_temp.rows(405) || '/' || pg_temp.rows(409), '1/0', 'lo mismo en la tabla');
select ok(exists (select 1 from audit.audit_events where table_name = 'ingredient_media' and action = 'insert' and reason = 'Foto del proveedor'), 'queda en la auditoría, con el motivo');
select matches(pg_temp.put(408, 'a'), 'ya está cargada', 'la misma no se carga dos veces');
select is(pg_temp.put(408, 'b', 'Foto mejor'), 'applied', 'cambiarla da de baja la anterior');
select is((select string_agg((deleted_at is null)::text, '/' order by storage_path = pg_temp.file('b')) from catalog.ingredient_media where ingredient_id = pg_temp.u(801)),
  'false/true', 'una sola vigente; la otra queda como historia');
select is(pg_temp.sees(405, 'a') || '/' || pg_temp.sees(405, 'b'), '0/1', 'quien solo ve, ve la vigente');
select is(pg_temp.sees(408, 'a') || '/' || pg_temp.sees(408, 'suelta'), '1/1', 'quien edita ve también la historia');
select is((select created_by from catalog.ingredient_media where storage_path = pg_temp.file('b')), pg_temp.u(408), 'quién la subió lo pone la base');
select is((select deleted_by from catalog.ingredient_media where storage_path = pg_temp.file('a')), pg_temp.u(408), 'y quién dio de baja la anterior');
select ok(exists (select 1 from audit.audit_events where table_name = 'ingredient_media' and action = 'soft_delete' and reason = 'Foto mejor'), 'la baja queda en la auditoría, con su motivo');
-- Un archivo subido no se cambia ni se borra, tampoco quien lo subió.
select is(pg_temp.q(pg_temp.u(408), format('with x as (update storage.objects set name = name || ''x'' where bucket_id = ''recipe-media'' and name = %L returning 1) select count(*)::text from x', pg_temp.file('a'))),
  '0', 'el archivo no se cambia');
select ok(coalesce(pg_temp.q(pg_temp.u(408), format('with x as (delete from storage.objects where bucket_id = ''recipe-media'' and name = %L returning 1) select count(*)::text from x', pg_temp.file('a'))), '0')
          ~ '^(0|ERROR 42501)', 'ni se borra');
select is((select count(*)::int from storage.objects where bucket_id = 'recipe-media' and name = pg_temp.file('a')), 1, 'sigue ahí');
-- Sin segundo factor o sin sesión.
select is(pg_temp.aal1(408, format('select count(*)::text from storage.objects where name = %L', pg_temp.file('b'))), '0', 'Compras sin segundo factor no la lee');
select is(pg_temp.aal1(408, format('select catalog.set_ingredient_photo(%L, %L, ''Prueba'') ->> ''result''', pg_temp.u(801), pg_temp.file('suelta'))), 'denied', 'ni la cambia');
select ok(not has_schema_privilege('anon', 'catalog', 'usage') and not has_function_privilege('anon', 'catalog.set_ingredient_photo(uuid, text, text)', 'execute'), 'anon no llega');
-- Desactivada, se sigue editando (como el resto de su ficha); borrada, la foto no se ve ni se cambia.
update catalog.ingredients set is_active = false where id = pg_temp.u(801);
select is(pg_temp.put(408, 'suelta', 'Con la materia prima desactivada'), 'applied', 'desactivada, se cambia igual');
update catalog.ingredients set deleted_at = now() where id = pg_temp.u(801);
select is(pg_temp.sees(405, 'suelta') || '/' || pg_temp.rows(405), '0/0', 'de una materia prima borrada no se ve ni el archivo ni la fila');
select is(pg_temp.put(408, 'b'), 'denied', 'ni se cambia');
update catalog.ingredients set deleted_at = null where id = pg_temp.u(801);
select is(pg_temp.q(pg_temp.u(405), format('select catalog.remove_ingredient_photo(%L, ''Prueba'') ->> ''result''', pg_temp.u(801))), 'denied', 'la Chef no la quita');
select is(pg_temp.q(pg_temp.u(408), format('select catalog.remove_ingredient_photo(%L, ''Ya no es ese envase'') ->> ''result''', pg_temp.u(801))), 'applied', 'Compras la quita');
select matches(pg_temp.q(pg_temp.u(408), format('select catalog.remove_ingredient_photo(%L, ''Otra vez'')::text', pg_temp.u(801))), 'no tiene foto', 'y no se quita dos veces');
select is((select count(*)::int from catalog.ingredient_media where ingredient_id = pg_temp.u(801)), 3, 'nada se borró');

-- ---------------------------------------------------------------------------
-- La tabla
-- ---------------------------------------------------------------------------
select throws_ok('delete from catalog.ingredient_media', '42501', null, 'una foto no se borra');
select throws_ok('update catalog.ingredient_media set deleted_at = null', '42501', null, 'ni vuelve una dada de baja');
select is(pg_temp.q(pg_temp.u(408), 'insert into catalog.ingredient_media (group_id, ingredient_id, storage_path) select group_id, ingredient_id, storage_path from catalog.ingredient_media returning ''x'''),
  'ERROR 42501: permission denied for table ingredient_media', 'no se escribe directo');
select throws_ok(format('insert into catalog.ingredient_media (group_id, ingredient_id, storage_path) values (%L, %L, %L)', pg_temp.u(1), pg_temp.u(802), pg_temp.path(pg_temp.u(803))),
  '23514', null, 'la ruta es de esa materia prima');

select * from finish();
rollback;
