-- Configuración del catálogo (ADR-0022): categorías y procesos de rendimiento se crean, renombran y dan
-- de baja desde la app. Categorías: catalog.manage para todo el grupo. Procesos: yields.approve para todo
-- el grupo. Nada en uso se da de baja, y todo queda en la auditoría con su motivo.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(44);

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
create function pg_temp.cat(p_name text) returns uuid language sql as $$
  select id from catalog.ingredient_categories where name = p_name and deleted_at is null
$$;
create function pg_temp.proc(p_code text) returns uuid language sql as $$
  select id from catalog.yield_processes where code = p_code and deleted_at is null
$$;
grant execute on function pg_temp.u(int), pg_temp.cat(text), pg_temp.proc(text) to authenticated;

-- Compras (408) y Superadmin (401) tienen catalog.manage de grupo. Chef del grupo: 413.
-- Chef de marca: 405. Directora de marca: 403. Jefe de Cocina: 406. Cocinera: 409.

-- ---------------------------------------------------------------------------
-- Categorías
-- ---------------------------------------------------------------------------
select ok(pg_temp.q(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), '  Panificados ', 'Categoría nueva')::text$$)
          ~ '^[0-9a-f-]{36}$', 'Compras crea una categoría');
select is((select name from catalog.ingredient_categories where id = pg_temp.cat('Panificados')), 'Panificados',
  'sin espacios de más');
select ok(pg_temp.q(pg_temp.u(401), $$select catalog.create_category(pg_temp.u(1), 'Panes', 'Sub', pg_temp.cat('Panificados'))::text$$)
          ~ '^[0-9a-f-]{36}$', 'el Superadministrador crea una subcategoría');
select is((select parent_id from catalog.ingredient_categories where id = pg_temp.cat('Panes')), pg_temp.cat('Panificados'),
  'la subcategoría queda debajo de su madre');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_categories'
                    and action = 'insert' and actor_user_id = pg_temp.u(408) and reason = 'Categoría nueva'),
  'la categoría nueva queda en la auditoría, con quién y por qué');

select is(pg_temp.q(pg_temp.u(409), $$select catalog.create_category(pg_temp.u(1), 'Otra', 'Prueba')::text$$),
  'ERROR 42501', 'la Cocinera no crea categorías');
select is(pg_temp.q(pg_temp.u(406), $$select catalog.create_category(pg_temp.u(1), 'Otra', 'Prueba')::text$$),
  'ERROR 42501', 'el Jefe de Cocina no crea categorías');
select is(pg_temp.q(pg_temp.u(405), $$select catalog.create_category(pg_temp.u(1), 'Otra', 'Prueba')::text$$),
  'ERROR 42501', 'la Chef de marca no crea categorías');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'Otra', '')::text$$),
  'ERROR 22023', 'sin motivo no se crea');

select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'carnes', 'Repetida')$$),
  'Ya existe una categoría con ese nombre en el mismo nivel.', 'nombre repetido (sin importar mayúsculas), en español');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'Integrales', 'Tercer nivel', pg_temp.cat('Panes'))$$),
  'Las categorías tienen solo dos niveles: categoría y subcategoría.', 'no hay tercer nivel');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), '   ', 'Vacía')$$),
  'El nombre no puede quedar vacío ni pasar los 80 caracteres.', 'nombre vacío, en español');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), null, 'Nulo')$$),
  'El nombre no puede quedar vacío ni pasar los 80 caracteres.', 'nombre nulo, el mismo mensaje en español');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.rename_category(pg_temp.cat('Panes'), 'CARNES', 'Repetido')$$),
  'sin error', 'el mismo nombre en otro nivel (Panes es subcategoría, Carnes principal) sí se puede');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.rename_category(pg_temp.cat('Lácteos'), 'carnes', 'Repetido')$$),
  'Ya existe una categoría con ese nombre en el mismo nivel.', 'renombrar a un nombre repetido, en español');

select is(pg_temp.msg(pg_temp.u(408), $$select catalog.rename_category(pg_temp.cat('CARNES'), 'Panes y facturas', 'Más claro')$$),
  'sin error', 'Compras renombra una categoría');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_categories'
                    and action = 'update' and new_values ->> 'name' = 'Panes y facturas' and reason = 'Más claro'),
  'el cambio de nombre queda en la auditoría');
select is(pg_temp.q(pg_temp.u(405), $$select catalog.rename_category(pg_temp.cat('Carnes'), 'Proteínas', 'Prueba')::text$$),
  'ERROR 42501', 'la Chef de marca no renombra');

select is(pg_temp.msg(pg_temp.u(408), $$select catalog.archive_category(pg_temp.cat('Verduras y frutas'), 'Prueba')$$),
  format('Tiene %s materias primas: pasalas a otra categoría antes de darla de baja.',
         (select count(*) from catalog.ingredients where category_id = pg_temp.cat('Verduras y frutas') and deleted_at is null)),
  'una categoría con materias primas no se da de baja, y dice cuántas tiene');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.archive_category(pg_temp.cat('Panificados'), 'Prueba')$$),
  'Tiene 1 subcategoría: dala de baja antes.', 'una categoría con subcategorías no se da de baja');

create temporary table archived as select pg_temp.cat('Panes y facturas') as id;
grant select on archived to authenticated;
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.archive_category(pg_temp.cat('Panes y facturas'), 'Ya no se usa')$$),
  'sin error', 'una subcategoría vacía se da de baja');
select ok((select deleted_at is not null and deleted_by = pg_temp.u(408) from catalog.ingredient_categories
            where id = (select id from archived)), 'queda dada de baja, con quién (no se borra)');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredient_categories'
                    and action = 'soft_delete' and record_id = (select id from archived)
                    and new_values ->> 'deleted_at' is not null and reason = 'Ya no se usa'),
  'la baja queda en la auditoría, con el motivo');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'Pan de molde',
            (select id from archived), 'g', null, 'Prueba')::text$$),
  'ERROR 23514', 'una categoría dada de baja no se puede usar en una materia prima nueva');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.rename_category((select id from archived), 'Otra', 'Prueba')::text$$),
  'ERROR 42501', 'ni renombrar');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.archive_category(pg_temp.cat('Panificados'), 'Ya no se usa')$$),
  'sin error', 'sin subcategorías vigentes, la madre se da de baja');

-- Una madre que no sirve responde siempre lo mismo: no revela si el id existe ni de qué tipo es.
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'Integrales', 'Prueba', (select id from archived))$$),
  'Elegí una categoría madre de este grupo.', 'una madre dada de baja no sirve');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_category(pg_temp.u(1), 'Integrales', 'Prueba', gen_random_uuid())$$),
  'Elegí una categoría madre de este grupo.', 'un id que no existe da el mismo mensaje');
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.rename_category(gen_random_uuid(), 'Otra', 'Prueba')$$),
  pg_temp.msg(pg_temp.u(408), $$select catalog.rename_category((select id from archived), 'Otra', 'Prueba')$$),
  'renombrar un id que no existe responde igual que uno dado de baja');

-- ---------------------------------------------------------------------------
-- Procesos de rendimiento
-- ---------------------------------------------------------------------------
select is(pg_temp.msg(pg_temp.u(413), $$select catalog.rename_yield_process(pg_temp.proc('LIMPIEZA'), 'Limpieza general', 'Más claro')$$),
  'sin error', 'el Chef del grupo renombra un proceso');
select is((select code from catalog.yield_processes where name = 'Limpieza general'), 'LIMPIEZA', 'el código no cambia');
select is(pg_temp.q(pg_temp.u(405), $$select catalog.rename_yield_process(pg_temp.proc('LIMPIEZA'), 'Limpieza', 'Prueba')::text$$),
  'ERROR 42501', 'la Chef de marca no renombra procesos');
select is(pg_temp.q(pg_temp.u(403), $$select catalog.archive_yield_process(pg_temp.proc('DESGRASADO'), 'Prueba')::text$$),
  'ERROR 42501', 'la Directora de marca (yields.approve solo en su marca) no da de baja procesos');
select is(pg_temp.msg(pg_temp.u(413), $$select catalog.rename_yield_process(pg_temp.proc('LIMPIEZA'), 'pelado', 'Repetido')$$),
  'Ya existe un proceso con ese nombre en el grupo.', 'nombre de proceso repetido, en español');

select is(pg_temp.msg(pg_temp.u(413), $$select catalog.archive_yield_process(pg_temp.proc('PELADO'), 'Prueba')$$),
  'Tiene rendimientos estándar vigentes: no se puede dar de baja.', 'un proceso con estándar vigente no se da de baja');
select ok(pg_temp.q(pg_temp.u(405), $$select catalog.propose_yield_standard('00000000-0000-4000-8000-000000000803',
            pg_temp.proc('DESHUESADO'), null, 0.7, 1, 'Prueba', false, 'Propuesta')::text$$) ~ '^[0-9a-f-]{36}$',
  'la Chef de marca propone un estándar con DESHUESADO');
select is(pg_temp.msg(pg_temp.u(413), $$select catalog.archive_yield_process(pg_temp.proc('DESHUESADO'), 'Prueba')$$),
  'Tiene propuestas de rendimiento en revisión: esperá a que se decidan.', 'con una propuesta en revisión tampoco');
select is(pg_temp.msg(pg_temp.u(413), $$select catalog.archive_yield_process(pg_temp.proc('DESGRASADO'), 'Ya no se usa')$$),
  'sin error', 'un proceso sin uso se da de baja');
select throws_ok($$insert into catalog.ingredient_yield_tests (group_id, ingredient_id, process_id, restaurant_id, tested_on,
                     samples, gross_weight, clean_weight)
                   values (pg_temp.u(1), '00000000-0000-4000-8000-000000000801',
                           (select id from catalog.yield_processes where code = 'DESGRASADO'), pg_temp.u(201),
                           '2026-10-01', 1, 1000, 800)$$,
  '23514', 'Ese proceso está dado de baja: elegí otro.', 'un proceso dado de baja no se usa en un ensayo nuevo');
select is(pg_temp.msg(pg_temp.u(405), $$select catalog.propose_yield_standard('00000000-0000-4000-8000-000000000803',
            (select id from catalog.yield_processes where code = 'DESGRASADO'), null, 0.7, 1, 'Prueba', false, 'Propuesta')$$),
  'Elegí un proceso del grupo.', 'ni en una propuesta');

-- ---------------------------------------------------------------------------
-- Lectura para la pantalla: cuánto se usa cada una (con RLS de quien consulta)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(408), $$select ingredients::text from catalog.category_usage() where category_id = pg_temp.cat('Carnes')$$),
  (select count(*)::text from catalog.ingredients where category_id = pg_temp.cat('Carnes') and deleted_at is null),
  'cuenta las materias primas vigentes de cada categoría');
select is(pg_temp.q(pg_temp.u(413), $$select standards::text from catalog.process_usage() where process_id = pg_temp.proc('PELADO')$$),
  '1', 'cuenta los estándares vigentes de cada proceso');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from catalog.category_usage()$$), '0',
  'la Cocinera (sin catalog.view) no ve cuántas materias primas hay');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from catalog.process_usage()$$), '0',
  'ni cuántos estándares');

select * from finish();
rollback;
