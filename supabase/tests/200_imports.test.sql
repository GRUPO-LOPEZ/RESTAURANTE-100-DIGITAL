-- Fase 2 · Etapa 2.4: importar el recetario de Excel (ADR-0027). Caso 8 (el mismo archivo no se importa
-- dos veces, y un código que ya existe no se duplica), validación sin tocar lo oficial, errores fila por
-- fila y la confirmación en dos pasos: Compras las materias primas, la cocina las recetas.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(47);

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
    v := 'ERROR ' || sqlstate || ' ' || sqlerrm;
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
create function pg_temp.res(p_user uuid, p_call text) returns text language sql as $$
  select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call))
$$;
create temporary table ids (k text primary key, id uuid);
grant select on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant execute on function pg_temp.u(int), pg_temp.id(text) to authenticated;
-- Un archivo "subido" al bucket por la Chef 405 (la prueba no pasa por la API de Storage, que pone owner_id).
create function pg_temp.upload(p_n int) returns text language plpgsql as $$
declare
  v_path text := format('%s/%s/%s.xlsx', pg_temp.u(1), pg_temp.u(101), pg_temp.u(9000 + p_n));
begin
  insert into storage.objects (bucket_id, name, owner_id) values ('imports', v_path, pg_temp.u(405)::text);
  return v_path;
end
$$;
create function pg_temp.sha(p_n int) returns text language sql as $$ select repeat(lpad(p_n::text, 2, '0'), 32) $$;
create function pg_temp.actions(p_job uuid, p_kinds text[]) returns text language sql as $$
  select string_agg(a || '=' || n, ', ' order by a)
    from (select coalesce(action::text, 'sin acción') as a, count(*) as n from imports.import_staging_rows
           where job_id = p_job and kind::text = any (p_kinds) and deleted_at is null group by 1) x
$$;

-- Personas del seed: Chef de Demo Pastas 405 (marca 101), Compras 408 (grupo), Cocinera 409 (local 201),
-- Controller 407. Grupo ...001, marca 101. La materia prima del seed DEMO-ING-001 es el Tomate perita.

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_tables where schemaname = 'imports'), 4, 'el esquema imports tiene 4 tablas (los precios, aparte)');
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'imports' and c.relkind = 'r' and not c.relrowsecurity),
  'RLS activado en todas las tablas de imports');
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'imports' and c.relkind = 'r'
                         and has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate')),
  'nadie escribe directo en imports: solo por funciones');
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'imports' and c.relkind = 'r'
                         and (select count(*) from pg_trigger g
                               where g.tgrelid = c.oid
                                 and g.tgname in ('log_change', 'set_control_columns', 'reject_truncate')) <> 3),
  'todas las tablas de imports tienen auditoría, columnas de control y rechazo de truncate');
select is((select public::text || '/' || file_size_limit from storage.buckets where id = 'imports'), 'false/15728640',
  'el bucket imports es privado y acepta hasta 15 MB');

-- ---------------------------------------------------------------------------
-- Subir: permisos y caso 8 (el mismo archivo no se importa dos veces)
-- ---------------------------------------------------------------------------
create temporary table paths (n int primary key, path text);
insert into paths select n, pg_temp.upload(n) from generate_series(1, 4) n;
grant select on paths to authenticated;
select is(pg_temp.res(pg_temp.u(409), format($$imports.create_job(pg_temp.u(101), %L, 'recetario.xlsx', %L, 'DEMO', 'Prueba')$$,
    (select path from paths where n = 1), pg_temp.sha(1))), 'denied', 'la Cocinera no importa recetas');
insert into ids values ('job1', (pg_temp.q(pg_temp.u(405),
  format($$select imports.create_job(pg_temp.u(101), %L, 'recetario.xlsx', %L, 'demo', 'Recetario de prueba') ->> 'id'$$,
         (select path from paths where n = 1), pg_temp.sha(1))))::uuid);
select ok(pg_temp.id('job1') is not null, 'la Chef sube el recetario de su marca');
select is((select code_prefix || '/' || status from imports.import_jobs where id = pg_temp.id('job1')), 'DEMO/uploaded',
  'con el prefijo en mayúsculas, y queda subido');
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.create_job(pg_temp.u(101), '%s/%s/%s.xlsx', 'x.xlsx', %L, 'DEMO', 'Prueba')$$,
    pg_temp.u(1), pg_temp.u(101), pg_temp.u(9999), pg_temp.sha(9))),
  'El archivo no se subió bien: probá de nuevo.', 'un archivo que no está en el bucket se rechaza');
select ok(pg_temp.msg(pg_temp.u(405), format($$select imports.create_job(pg_temp.u(101), %L, 'copia.xlsx', %L, 'DEMO', 'Otra vez')$$,
    (select path from paths where n = 2), pg_temp.sha(1))) like 'Este archivo ya se importó el %',
  'caso 8: el mismo archivo (misma huella) no se importa dos veces');

-- ---------------------------------------------------------------------------
-- Cargar filas y validar, sin tocar lo oficial
-- ---------------------------------------------------------------------------
create temporary table before as
  select (select count(*) from catalog.ingredients) as ingredients, (select count(*) from recipes.recipes) as recipes;
select is(pg_temp.res(pg_temp.u(405), format($$imports.stage_rows(%L, '[
  {"sheet": "INSUMOS", "row_number": 2, "kind": "ingredient", "source_code": "ING-001", "parsed": {"name": "TOMATE PERITA", "category": "Verduras"}, "price": {"price": 1500, "price_per_kg": 1500}},
  {"sheet": "INSUMOS", "row_number": 3, "kind": "ingredient", "source_code": "X100", "parsed": {"name": " tomate   perita ", "category": "Verduras"}},
  {"sheet": "INSUMOS", "row_number": 4, "kind": "ingredient", "source_code": "X101", "parsed": {"name": "Harina importada", "category": "almacén"}},
  {"sheet": "INSUMOS", "row_number": 5, "kind": "ingredient", "source_code": "X102", "parsed": {"name": "Especia nueva", "category": "Rubro nuevo"}},
  {"sheet": "INSUMOS", "row_number": 6, "kind": "ingredient", "source_code": "X101", "parsed": {"name": "Harina repetida"}},
  {"sheet": "INSUMOS", "row_number": 7, "kind": "ingredient", "parsed": {"name": "Sin código"}},
  {"sheet": "pre-elaborado", "row_number": 2, "kind": "preparation", "source_code": "P1", "parsed": {"name": "Salsa base importada", "yield_grams": 1000}},
  {"sheet": "pre-elaborado", "row_number": 3, "kind": "line", "parent_row": 2, "source_code": "X101", "parent_code": "P1", "parsed": {"grams": 500, "measure": "CUP 250"}},
  {"sheet": "pre-elaborado", "row_number": 4, "kind": "line", "parent_row": 2, "source_code": "ING-001", "parent_code": "P1", "parsed": {"grams": 300}},
  {"sheet": "pre-elaborado", "row_number": 6, "kind": "preparation", "source_code": "P2", "parsed": {"name": "Salsa doble importada", "yield_grams": 800}},
  {"sheet": "pre-elaborado", "row_number": 7, "kind": "line", "parent_row": 6, "source_code": "P1", "parent_code": "P2", "parsed": {"grams": 400}},
  {"sheet": "pre-elaborado", "row_number": 8, "kind": "line", "parent_row": 6, "source_code": "X102", "parent_code": "P2", "parsed": {"grams": 10}},
  {"sheet": "pre-elaborado", "row_number": 10, "kind": "preparation", "source_code": "P3", "parsed": {"name": "Ciclo A"}},
  {"sheet": "pre-elaborado", "row_number": 11, "kind": "line", "parent_row": 10, "source_code": "P4", "parent_code": "P3", "parsed": {"grams": 10}},
  {"sheet": "pre-elaborado", "row_number": 13, "kind": "preparation", "source_code": "P4", "parsed": {"name": "Ciclo B"}},
  {"sheet": "pre-elaborado", "row_number": 14, "kind": "line", "parent_row": 13, "source_code": "P3", "parent_code": "P4", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 2, "kind": "dish", "source_code": "D1", "parsed": {"name": "Plato importado", "portions": 2, "portion_grams": 350}},
  {"sheet": "PLATOS", "row_number": 3, "kind": "line", "parent_row": 2, "source_code": "P2", "parent_code": "D1", "parsed": {"grams": 200, "measure": "2 CUP"}},
  {"sheet": "PLATOS", "row_number": 4, "kind": "line", "parent_row": 2, "source_code": "X100", "parent_code": "D1", "parsed": {"grams": 50}},
  {"sheet": "PLATOS", "row_number": 6, "kind": "dish", "source_code": "D2", "parsed": {"name": "Plato sin receta"}},
  {"sheet": "PLATOS", "row_number": 8, "kind": "dish", "source_code": "D3", "parsed": {"name": "Plato con cero gramos"}},
  {"sheet": "PLATOS", "row_number": 9, "kind": "line", "parent_row": 8, "source_code": "X101", "parent_code": "D3", "parsed": {"grams": 0}},
  {"sheet": "PLATOS", "row_number": 11, "kind": "dish", "source_code": "D4", "parsed": {"name": "Plato con código raro"}},
  {"sheet": "PLATOS", "row_number": 12, "kind": "line", "parent_row": 11, "source_code": "ZZZ", "parent_code": "D4", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 14, "kind": "dish", "source_code": "D5", "parsed": {"name": "Plato con el círculo"}},
  {"sheet": "PLATOS", "row_number": 15, "kind": "line", "parent_row": 14, "source_code": "P3", "parent_code": "D5", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 17, "kind": "dish", "source_code": "PAS-01", "parsed": {"name": "Masa que ya existe"}},
  {"sheet": "PLATOS", "row_number": 18, "kind": "line", "parent_row": 17, "source_code": "X101", "parent_code": "PAS-01", "parsed": {"grams": 100}}
]')$$, pg_temp.id('job1'))), 'applied', 'la Chef carga las filas leídas del Excel');
select is((select count(*)::int from imports.import_staging_rows where job_id = pg_temp.id('job1')), 28, 'quedan 28 filas intermedias');
select is(pg_temp.res(pg_temp.u(405), format($$imports.validate_job(%L)$$, pg_temp.id('job1'))), 'applied', 'valida');
select is((select (select count(*) from catalog.ingredients) || '/' || (select count(*) from recipes.recipes)),
          (select ingredients || '/' || recipes from before), 'validar no toca materias primas ni recetas');
select is(pg_temp.actions(pg_temp.id('job1'), array['ingredient']), 'create=2, error=1, reuse=2, skip=1',
  'materias primas: 2 nuevas, 2 que ya existen (por código y por nombre), 1 repetida y 1 sin código');
select is((select string_agg(source_code, ', ' order by source_code) from imports.import_staging_rows
            where job_id = pg_temp.id('job1') and kind = 'ingredient' and action = 'reuse'
              and ingredient_id = (select id from catalog.ingredients where code = 'DEMO-ING-001')),
  'ING-001, X100', 'el Tomate se reutiliza por código y también por el mismo nombre escrito distinto');
select is(pg_temp.actions(pg_temp.id('job1'), array['preparation', 'dish']), 'create=4, error=5, skip=1',
  'recetas: 4 se crean, 5 con error y la que ya existe se omite (no se pisa)');
select is(pg_temp.actions(pg_temp.id('job1'), array['line']), 'create=6, error=5, skip=1', 'líneas: 6 se crean, 5 con error, 1 se omite');
select is((select string_agg(distinct code, ', ' order by code) from imports.import_errors
            where job_id = pg_temp.id('job1') and deleted_at is null and severity = 'error'),
  'bad_code, bad_quantity, broken_component, cycle, duplicate_code, line_errors, unknown_code',
  'cada problema con su motivo: código, gramos, círculo, repetido, componente roto y código desconocido');
select is((select message from imports.import_errors where job_id = pg_temp.id('job1') and code = 'unknown_code' and deleted_at is null),
  'El código ZZZ no está en INSUMOS ni en los pre-elaborados.', 'el mensaje dice qué código falta');
select is((select severity::text || ': ' || message from imports.import_errors
            where job_id = pg_temp.id('job1') and code = 'empty_recipe' and deleted_at is null),
  'warning: No tiene componentes en el Excel: queda en borrador para completarla en la ficha.',
  'un plato sin receta es un aviso, no un error');
select is((select string_agg(source_code || '=' || level, ', ' order by source_code) from imports.import_staging_rows
            where job_id = pg_temp.id('job1') and action = 'create' and kind in ('preparation', 'dish')),
  'D1=2, D2=0, P1=0, P2=1', 'los niveles ordenan la creación: primero las preparaciones de abajo');
select is(pg_temp.res(pg_temp.u(405), format($$imports.validate_job(%L)$$, pg_temp.id('job1'))), 'applied', 'se puede validar otra vez');
select is((select count(*)::int from imports.import_errors where job_id = pg_temp.id('job1') and deleted_at is null), 13,
  'y los problemas no se duplican: siguen siendo 12 errores y 1 aviso (los anteriores quedan dados de baja)');

-- ---------------------------------------------------------------------------
-- Confirmar en dos pasos
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.confirm_recipes(%L, 'Recetas')$$, pg_temp.id('job1'))),
  'Primero Compras tiene que confirmar las materias primas.', 'las recetas esperan a que Compras confirme las materias primas');
select is(pg_temp.res(pg_temp.u(405), format($$imports.confirm_ingredients(%L, 'Materias primas')$$, pg_temp.id('job1'))), 'denied',
  'la Chef no crea materias primas: es de Compras');
set local role audit_owner;
create temporary table denied as
  select count(*)::int as n from audit.authentication_security_events
   where event_type = 'operation_denied' and operation = 'imports.confirm_ingredients' and actor_id = '00000000-0000-4000-8000-000000000405';
reset role;
select is((select n from denied), 1, 'y el intento queda en el registro de seguridad');
select is(pg_temp.res(pg_temp.u(408), format($$imports.confirm_ingredients(%L, 'Materias primas del recetario')$$, pg_temp.id('job1'))),
  'applied', 'Compras confirma las materias primas');
select is((select string_agg(i.code || ' en ' || c.name, ', ' order by i.code) from catalog.ingredients i
             join catalog.ingredient_categories c on c.id = i.category_id where i.code in ('DEMO-X101', 'DEMO-X102')),
  'DEMO-X101 en Almacén, DEMO-X102 en Rubro nuevo', 'con su código y su rubro (el que existía, o uno nuevo)');
select is((select count(*)::int from catalog.ingredients where code = 'DEMO-X100'), 0,
  'la que ya existía con otro código no se duplica');
select is(pg_temp.res(pg_temp.u(408), format($$imports.confirm_recipes(%L, 'Recetas')$$, pg_temp.id('job1'))), 'denied',
  'Compras no crea recetas');
select is(pg_temp.res(pg_temp.u(405), format($$imports.confirm_recipes(%L, 'Recetario de Demo Pastas')$$, pg_temp.id('job1'))),
  'applied', 'la Chef confirma las recetas');
select is((select string_agg(r.code || ':' || r.recipe_type || ':' || v.status, ', ' order by r.code)
             from recipes.recipes r join recipes.recipe_versions v on v.recipe_id = r.id
            where r.code in ('DEMO-D1', 'DEMO-D2', 'DEMO-P1', 'DEMO-P2')),
  'DEMO-D1:dish:draft, DEMO-D2:dish:draft, DEMO-P1:preparation:draft, DEMO-P2:preparation:draft',
  'las 4 recetas quedan en la marca, en borrador');
select is((select count(*)::int from recipes.recipes where code in ('DEMO-P3', 'DEMO-P4', 'DEMO-D3', 'DEMO-D4', 'DEMO-D5')), 0,
  'las que tienen errores no se crean');
select is((select string_agg(coalesce(i.name, s.code) || ' ' || c.quantity::numeric(10,0) || ' ' || u.code || ' ' || c.quantity_basis
                             || coalesce(' (' || c.notes || ')', ''), ', ' order by c.line_order)
             from recipes.recipe_components c
             join recipes.recipe_versions v on v.id = c.recipe_version_id
             join recipes.recipes r on r.id = v.recipe_id
             join catalog.units u on u.id = c.unit_id
             left join catalog.ingredients i on i.id = c.ingredient_id
             left join recipes.recipes s on s.id = c.sub_recipe_id
            where r.code = 'DEMO-D1'),
  'DEMO-P2 200 g finished (2 CUP), Tomate perita 50 g purchase',
  'el plato usa la preparación importada (cantidad terminada) y el Tomate que ya existía; la medida casera va de observación');
select is((select v.yield_quantity::numeric(10,0) || ' ' || u.code from recipes.recipe_versions v
             join recipes.recipes r on r.id = v.recipe_id join catalog.units u on u.id = v.yield_unit_id
            where r.code = 'DEMO-P2'), '800 g', 'la preparación rinde su peso neto');
select is((select v.portions || ' de ' || v.portion_grams::numeric(10,0) || ' g' from recipes.recipe_versions v
             join recipes.recipes r on r.id = v.recipe_id where r.code = 'DEMO-D1'), '2 de 350 g', 'el plato, sus porciones');
select is((select count(*)::int from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id
            where r.code = 'DEMO-PAS-01'), 1, 'la receta que ya existía no se tocó');
select ok(exists (select 1 from audit.audit_events where table_name = 'recipes' and source::text = 'import'
                    and reason = 'Recetario de Demo Pastas'),
  'la creación queda en la auditoría, con origen importación y el motivo');
select is((select status || '/' || (confirmed_by = pg_temp.u(405)) || '/' || (ingredients_confirmed_by = pg_temp.u(408))
             from imports.import_jobs where id = pg_temp.id('job1')), 'confirmed/true/true', 'la importación queda confirmada, con quién');
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.confirm_recipes(%L, 'Otra vez')$$, pg_temp.id('job1'))),
  'Esta importación ya se confirmó o se canceló.', 'confirmar dos veces no crea nada más');

-- ---------------------------------------------------------------------------
-- Otro archivo con los mismos códigos: nada se duplica (caso 8). Quién ve. Cancelar.
-- ---------------------------------------------------------------------------
insert into ids values ('job2', (pg_temp.q(pg_temp.u(405),
  format($$select imports.create_job(pg_temp.u(101), %L, 'recetario-v2.xlsx', %L, 'DEMO', 'Versión corregida') ->> 'id'$$,
         (select path from paths where n = 3), pg_temp.sha(2))))::uuid);
select pg_temp.q(pg_temp.u(405), format($$select imports.stage_rows(%L, '[
  {"sheet": "INSUMOS", "row_number": 4, "kind": "ingredient", "source_code": "X101", "parsed": {"name": "Harina importada"}},
  {"sheet": "pre-elaborado", "row_number": 2, "kind": "preparation", "source_code": "P1", "parsed": {"name": "Salsa base importada"}},
  {"sheet": "pre-elaborado", "row_number": 3, "kind": "line", "parent_row": 2, "source_code": "X101", "parent_code": "P1", "parsed": {"grams": 500}}
]')$$, pg_temp.id('job2')));
select pg_temp.q(pg_temp.u(405), format($$select imports.validate_job(%L)$$, pg_temp.id('job2')));
select is(pg_temp.actions(pg_temp.id('job2'), array['ingredient', 'preparation', 'line']), 'reuse=1, skip=2',
  'caso 8: con los mismos códigos, la materia prima se reutiliza y la receta se omite');
select pg_temp.q(pg_temp.u(408), format($$select imports.confirm_ingredients(%L, 'Materias primas')$$, pg_temp.id('job2')));
select pg_temp.q(pg_temp.u(405), format($$select imports.confirm_recipes(%L, 'Recetas')$$, pg_temp.id('job2')));
select is((select (select count(*) from catalog.ingredients where code = 'DEMO-X101') || '/' ||
                  (select count(*) from recipes.recipes where code = 'DEMO-P1')), '1/1', 'caso 8: 0 duplicados');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from imports.import_jobs'), '0', 'la Cocinera no ve las importaciones');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from imports.import_jobs'), '2', 'Compras las ve, para confirmar materias primas');
insert into ids values ('job3', (pg_temp.q(pg_temp.u(405),
  format($$select imports.create_job(pg_temp.u(101), %L, 'equivocado.xlsx', %L, 'DEMO', 'Prueba') ->> 'id'$$,
         (select path from paths where n = 4), pg_temp.sha(3))))::uuid);
select is(pg_temp.res(pg_temp.u(405), format($$imports.cancel_job(%L, 'Me equivoqué de archivo')$$, pg_temp.id('job3'))), 'applied',
  'una importación sin confirmar se cancela');
select ok(pg_temp.q(pg_temp.u(405), format($$select imports.create_job(pg_temp.u(101), %L, 'equivocado.xlsx', %L, 'DEMO', 'Ahora sí') ->> 'id'$$,
    (select path from paths where n = 4), pg_temp.sha(3))) ~ '^[0-9a-f-]{36}$',
  'y ese mismo archivo se puede volver a subir');

select * from finish();
rollback;
