-- Importación del recetario (ADR-0027): las reglas que pidieron las revisiones de base y de seguridad.
-- Una línea con un componente roto no pasa; nombres y bloques repetidos; lo de otra marca, de un local o
-- sin publicar no se usa; unidades; lo que cambia entre validar y confirmar; prefijos por marca; quién ve
-- precios, filas y archivos; auditoría.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(46);

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
create function pg_temp.upload(p_brand int, p_n int) returns text language plpgsql as $$
declare
  v_path text := format('%s/%s/%s.xlsx', pg_temp.u(1), pg_temp.u(p_brand), pg_temp.u(9100 + p_n));
begin
  insert into storage.objects (bucket_id, name) values ('imports', v_path);
  return v_path;
end
$$;
-- Acción y problemas de una fila (por solapa y número de fila).
create function pg_temp.row(p_job uuid, p_sheet text, p_row int) returns text language sql as $$
  select r.action || coalesce(' ' || (select string_agg(e.code, ',' order by e.code) from imports.import_errors e
                                        where e.row_id = r.id and e.deleted_at is null), '')
    from imports.import_staging_rows r where r.job_id = p_job and r.sheet = p_sheet and r.row_number = p_row
$$;

-- Personas del seed: Chef de Demo Pastas 405 (marca 101), Chef del grupo 413, Compras 408, Cocinera 409,
-- Controller 407. DEMO-PAR-01 es de Demo Parrilla (marca 102), DEMO-LOC-01 de un local, DEMO-PAS-06 está
-- en borrador y DEMO-ING-022 (Crema de leche) se mide en ml.

insert into ids values ('job', (pg_temp.q(pg_temp.u(405),
  format($$select imports.create_job(pg_temp.u(101), %L, 'reglas.xlsx', %L, 'DEMO', 'Reglas') ->> 'id'$$,
         pg_temp.upload(101, 1), repeat('c1', 32))))::uuid);
select is(pg_temp.res(pg_temp.u(405), format($$imports.stage_rows(%L, '[
  {"sheet": "INSUMOS", "row_number": 2, "kind": "ingredient", "source_code": "A1", "parsed": {"category": "Almacén"}},
  {"sheet": "INSUMOS", "row_number": 3, "kind": "ingredient", "source_code": "A2", "parsed": {"name": "Sal repetida", "category": "Almacén"}, "price": {"price": 900, "price_per_kg": 900}},
  {"sheet": "INSUMOS", "row_number": 4, "kind": "ingredient", "source_code": "A3", "parsed": {"name": "sal   REPETIDA"}},
  {"sheet": "INSUMOS", "row_number": 6, "kind": "ingredient", "source_code": "A4", "parsed": {"name": "Pimienta de reglas", "category": "Almacén"}},
  {"sheet": "pre-elaborado", "row_number": 2, "kind": "preparation", "source_code": "Q1", "parsed": {"name": "Prep uno", "yield_grams": 500}},
  {"sheet": "pre-elaborado", "row_number": 3, "kind": "line", "parent_row": 2, "source_code": "A2", "parent_code": "Q1", "parsed": {"grams": 100}},
  {"sheet": "pre-elaborado", "row_number": 5, "kind": "preparation", "source_code": "Q1", "parsed": {"name": "Prep uno bis"}},
  {"sheet": "pre-elaborado", "row_number": 6, "kind": "line", "parent_row": 5, "source_code": "A4", "parent_code": "Q1", "parsed": {"grams": 50}},
  {"sheet": "pre-elaborado", "row_number": 8, "kind": "preparation", "source_code": "Q2", "parsed": {}},
  {"sheet": "pre-elaborado", "row_number": 9, "kind": "line", "parent_row": 8, "source_code": "A2", "parent_code": "Q2", "parsed": {"grams": 10}},
  {"sheet": "pre-elaborado", "row_number": 11, "kind": "preparation", "source_code": "Q2", "parsed": {"name": "Q2 repetida"}},
  {"sheet": "pre-elaborado", "row_number": 13, "kind": "preparation", "source_code": "PAR-02", "parsed": {"name": "Pisa otra marca"}},
  {"sheet": "PLATOS", "row_number": 2, "kind": "dish", "source_code": "E1", "parsed": {"name": "Usa uno sin nombre"}},
  {"sheet": "PLATOS", "row_number": 3, "kind": "line", "parent_row": 2, "source_code": "A1", "parent_code": "E1", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 5, "kind": "dish", "source_code": "E2", "parsed": {"name": "Usa Q2"}},
  {"sheet": "PLATOS", "row_number": 6, "kind": "line", "parent_row": 5, "source_code": "Q2", "parent_code": "E2", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 8, "kind": "dish", "source_code": "E3", "parsed": {"name": "Usa otra marca"}},
  {"sheet": "PLATOS", "row_number": 9, "kind": "line", "parent_row": 8, "source_code": "PAR-01", "parent_code": "E3", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 11, "kind": "dish", "source_code": "E4", "parsed": {"name": "Usa un local"}},
  {"sheet": "PLATOS", "row_number": 12, "kind": "line", "parent_row": 11, "source_code": "LOC-01", "parent_code": "E4", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 14, "kind": "dish", "source_code": "E5", "parsed": {"name": "Usa uno sin publicar"}},
  {"sheet": "PLATOS", "row_number": 15, "kind": "line", "parent_row": 14, "source_code": "PAS-06", "parent_code": "E5", "parsed": {"grams": 10}},
  {"sheet": "PLATOS", "row_number": 17, "kind": "dish", "source_code": "E6", "parsed": {"name": "Usa crema en gramos"}},
  {"sheet": "PLATOS", "row_number": 18, "kind": "line", "parent_row": 17, "source_code": "ING-022", "parent_code": "E6", "parsed": {"grams": 100}},
  {"sheet": "PLATOS", "row_number": 20, "kind": "dish", "source_code": "E7", "parsed": {"name": "Plato bien armado", "portions": 1}},
  {"sheet": "PLATOS", "row_number": 21, "kind": "line", "parent_row": 20, "source_code": "Q1", "parent_code": "E7", "parsed": {"grams": 100, "measure": "1 CUP"}},
  {"sheet": "PLATOS", "row_number": 22, "kind": "line", "parent_row": 20, "source_code": "A4", "parent_code": "E7", "parsed": {"grams": 5}}
]')$$, pg_temp.id('job'))), 'applied', 'carga las filas');
select is(pg_temp.res(pg_temp.u(405), format($$imports.validate_job(%L)$$, pg_temp.id('job'))), 'applied', 'valida');

-- Componentes rotos: nunca pasan a "se crea" (revisión de base, G1).
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 3), 'error broken_component',
  'una línea que usa una materia prima del Excel con error no pasa');
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 2), 'error line_errors', 'y su plato tampoco');
select is(pg_temp.row(pg_temp.id('job'), 'pre-elaborado', 11), 'error duplicate_code', 'una receta repetida cuya primera fila tiene error, tampoco');
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 6), 'error broken_component', 'ni la línea que la usa');
-- Nombres repetidos (revisión de base, G2).
select is(pg_temp.row(pg_temp.id('job'), 'INSUMOS', 4), 'error duplicate_name',
  'dos materias primas con el mismo nombre (escrito distinto) y otro código: la segunda es un error');
-- Bloques repetidos (revisión de base, M1).
select is(pg_temp.row(pg_temp.id('job'), 'pre-elaborado', 5) || ' / ' || pg_temp.row(pg_temp.id('job'), 'pre-elaborado', 6),
  'skip duplicate_code / skip', 'el segundo bloque de una receta se omite, con sus líneas (no se mezclan)');
select is(pg_temp.row(pg_temp.id('job'), 'pre-elaborado', 9), 'skip', 'las líneas de una receta con error se omiten');
-- Alcance y reglas del recetario (revisión de seguridad, G1).
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 9), 'error out_of_scope', 'no usa una receta de otra marca');
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 12), 'error out_of_scope', 'ni una receta de un local');
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 15), 'error not_published', 'ni una preparación sin versión vigente');
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 18), 'error unit_mismatch',
  'ni una materia prima en ml sin conversión a gramos');
select is(pg_temp.row(pg_temp.id('job'), 'pre-elaborado', 13), 'error code_taken',
  'una receta con el código de otra marca es un error');
select is((select coalesce(recipe_id::text, 'sin id') from imports.import_staging_rows
            where job_id = pg_temp.id('job') and sheet = 'pre-elaborado' and row_number = 13),
  'sin id', 'y no deja ver el id de la receta ajena');
select is(pg_temp.row(pg_temp.id('job'), 'PLATOS', 20), 'create', 'el plato bien armado se crea');

-- Quién ve qué.
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from imports.import_staging_rows$$) || '/' ||
          pg_temp.q(pg_temp.u(409), $$select count(*)::text from imports.import_errors$$), '0/0',
  'la Cocinera no ve filas ni errores');
select is(pg_temp.q(pg_temp.u(405), $$select count(*)::text from imports.import_prices$$), '0',
  'la Chef importa sin ver los precios');
select is(pg_temp.q(pg_temp.u(408), $$select string_agg(price::numeric(10,0)::text, ',') from imports.import_prices$$), '900',
  'Compras sí los ve');
select is(pg_temp.q(pg_temp.u(405), $$select count(*)::text from storage.objects where bucket_id = 'imports'$$), '0',
  'la Chef no baja el Excel (tiene precios)');
select is(pg_temp.q(pg_temp.u(408), $$select (count(*) > 0)::text from storage.objects where bucket_id = 'imports'$$), 'true',
  'Compras sí');
select ok(pg_temp.q(pg_temp.u(409), format($$insert into storage.objects (bucket_id, name) values ('imports', '%s/%s/%s.xlsx') returning 'x'$$,
    pg_temp.u(1), pg_temp.u(101), pg_temp.u(9199))) like 'ERROR 42501%', 'la Cocinera no sube archivos');
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.stage_rows(%L, '[{"sheet": "X", "row_number": 1, "kind": "ingredient",
    "source_code": "Z", "raw": {"PRECIO": 10}}]')$$, pg_temp.id('job'))),
  'Esta importación ya se validó: para cambiar filas, subí el archivo de nuevo.', 'validada, no se cargan más filas');
select ok(exists (select 1 from audit.audit_events where table_name = 'import_staging_rows' and source::text = 'import'),
  'las filas intermedias quedan en la auditoría');

-- Lo que cambia entre validar y confirmar (revisión de base, M2).
insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id)
values (pg_temp.u(1), 'DEMO-A4', 'Pimienta de reglas', (select id from catalog.ingredient_categories where name = 'Almacén'),
        (select id from catalog.units where code = 'g'));
select ok(pg_temp.msg(pg_temp.u(408), format($$select imports.confirm_ingredients(%L, 'Materias primas')$$, pg_temp.id('job')))
          like 'Algo cambió desde la validación (INSUMOS fila 6)%', 'si alguien creó esa materia prima mientras tanto, se pide validar otra vez');
select is(pg_temp.res(pg_temp.u(405), format($$imports.validate_job(%L)$$, pg_temp.id('job'))), 'applied', 'se vuelve a validar');
select is(pg_temp.row(pg_temp.id('job'), 'INSUMOS', 6), 'reuse', 'y ahora se reutiliza');
select is(pg_temp.res(pg_temp.u(408), format($$imports.confirm_ingredients(%L, 'Materias primas')$$, pg_temp.id('job'))), 'applied',
  'Compras confirma');
select is(pg_temp.res(pg_temp.u(407), format($$imports.cancel_job(%L, 'No')$$, pg_temp.id('job'))), 'denied',
  'el Controller no cancela una importación que no carga');
select is(pg_temp.res(pg_temp.u(405), format($$imports.confirm_recipes(%L, 'Recetas')$$, pg_temp.id('job'))), 'applied',
  'la Chef confirma las recetas');
select is((select string_agg(coalesce(i.code, s.code), ', ' order by c.line_order) from recipes.recipe_components c
             join recipes.recipe_versions v on v.id = c.recipe_version_id join recipes.recipes r on r.id = v.recipe_id
             left join catalog.ingredients i on i.id = c.ingredient_id left join recipes.recipes s on s.id = c.sub_recipe_id
            where r.code = 'DEMO-Q1'), 'DEMO-A2', 'la preparación tiene solo las líneas de su primer bloque');
select is((select string_agg(coalesce(i.code, s.code), ', ' order by c.line_order) from recipes.recipe_components c
             join recipes.recipe_versions v on v.id = c.recipe_version_id join recipes.recipes r on r.id = v.recipe_id
             left join catalog.ingredients i on i.id = c.ingredient_id left join recipes.recipes s on s.id = c.sub_recipe_id
            where r.code = 'DEMO-E7'), 'DEMO-Q1, DEMO-A4', 'el plato usa la preparación importada y la materia prima existente');
select is((select count(*)::int from recipes.recipes where brand_id = pg_temp.u(101) and code in ('DEMO-E1', 'DEMO-E2', 'DEMO-E3', 'DEMO-E4', 'DEMO-E5', 'DEMO-E6', 'DEMO-PAR-02')),
  0, 'nada con errores se creó');
select is((select count(*)::int from recipes.recipe_components c join recipes.recipes p on p.id = c.sub_recipe_id
            where p.code = 'DEMO-PAR-01' and c.deleted_at is null), 0, 'y la receta de Parrilla no quedó usada por Pastas');

-- Las celdas crudas: lista cerrada y valores simples (un precio no se cuela por otro nombre ni anidado).
insert into ids values ('job_raw', (pg_temp.q(pg_temp.u(405),
  format($$select imports.create_job(pg_temp.u(101), %L, 'crudo.xlsx', %L, 'DEMO', 'Prueba') ->> 'id'$$,
         pg_temp.upload(101, 4), repeat('c4', 32))))::uuid);
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.stage_rows(%L, '[{"sheet": "INSUMOS", "row_number": 2,
    "kind": "ingredient", "source_code": "Z1", "parsed": {"name": "Z"}, "raw": {"F": 1708}}]')$$, pg_temp.id('job_raw'))),
  'Campos que no se pueden cambiar acá: F.', 'una celda que no está en la lista (por ejemplo, la columna del precio) se rechaza');
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.stage_rows(%L, '[{"sheet": "INSUMOS", "row_number": 2,
    "kind": "ingredient", "source_code": "Z1", "parsed": {"name": "Z"}, "raw": {"producto": {"PRECIO": 999}}}]')$$, pg_temp.id('job_raw'))),
  'Las celdas de una fila van como textos o números.', 'y un valor anidado también');

-- Materias primas dadas de baja (segunda revisión de base): por nombre al validar, y entre los dos pasos.
update catalog.ingredients set is_active = false where code = 'DEMO-ING-050';
select is(pg_temp.res(pg_temp.u(405), format($$imports.stage_rows(%L, '[
  {"sheet": "INSUMOS", "row_number": 2, "kind": "ingredient", "source_code": "Z2", "parsed": {"name": "champiñones"}},
  {"sheet": "INSUMOS", "row_number": 3, "kind": "ingredient", "source_code": "Z3", "parsed": {"name": "Ingrediente que se va"}},
  {"sheet": "pre-elaborado", "row_number": 2, "kind": "preparation", "source_code": "Z4", "parsed": {"name": "Usa el que se va"}},
  {"sheet": "pre-elaborado", "row_number": 3, "kind": "line", "parent_row": 2, "source_code": "Z3", "parent_code": "Z4", "parsed": {"grams": 10}}
]')$$, pg_temp.id('job_raw'))), 'applied', 'carga otro archivo');
select is(pg_temp.res(pg_temp.u(405), format($$imports.validate_job(%L)$$, pg_temp.id('job_raw'))), 'applied', 'lo valida');
select is(pg_temp.row(pg_temp.id('job_raw'), 'INSUMOS', 2), 'error inactive_name',
  'el nombre de una materia prima dada de baja no se crea ni se reutiliza (y no traba la confirmación)');
select is(pg_temp.res(pg_temp.u(408), format($$imports.confirm_ingredients(%L, 'Materias primas')$$, pg_temp.id('job_raw'))), 'applied',
  'Compras confirma las demás');
update catalog.ingredients set is_active = false where code = 'DEMO-Z3';
select ok(pg_temp.msg(pg_temp.u(405), format($$select imports.confirm_recipes(%L, 'Recetas')$$, pg_temp.id('job_raw')))
          like 'Algo cambió desde la validación%', 'si una se da de baja antes de las recetas, se pide validar otra vez');
select is(pg_temp.res(pg_temp.u(405), format($$imports.validate_job(%L)$$, pg_temp.id('job_raw'))), 'applied',
  'se revalida con las materias primas ya confirmadas');
select is(pg_temp.row(pg_temp.id('job_raw'), 'INSUMOS', 3) || ' / ' || pg_temp.row(pg_temp.id('job_raw'), 'pre-elaborado', 2),
  'error inactive / error line_errors', 'la dada de baja pasa a error y se contagia a la receta que la usa');
select is(pg_temp.res(pg_temp.u(405), format($$imports.confirm_recipes(%L, 'Recetas')$$, pg_temp.id('job_raw'))), 'applied',
  'y la confirmación ya no se traba');

-- Prefijos: uno por marca, y cada marca siempre el mismo.
select is(pg_temp.msg(pg_temp.u(413), format($$select imports.create_job(pg_temp.u(102), %L, 'parrilla.xlsx', %L, 'DEMO', 'Prueba')$$,
    pg_temp.upload(102, 2), repeat('c2', 32))),
  'El prefijo DEMO ya lo usa otra marca del grupo: elegí otro.', 'otra marca no usa el prefijo de Pastas');
select is(pg_temp.msg(pg_temp.u(405), format($$select imports.create_job(pg_temp.u(101), %L, 'otro.xlsx', %L, 'OTRO', 'Prueba')$$,
    pg_temp.upload(101, 3), repeat('c3', 32))),
  'Esta marca ya importó con el prefijo DEMO: usá el mismo, así no se duplican los códigos.', 'Pastas no cambia de prefijo');

select * from finish();
rollback;
