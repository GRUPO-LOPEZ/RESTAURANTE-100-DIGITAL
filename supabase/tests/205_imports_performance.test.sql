-- Importación con volumen (ADR-0027): un recetario del tamaño del de Casa Nonnos (300 materias primas,
-- 40 preparaciones en 4 niveles, 90 platos, unas 700 líneas) se valida y se confirma en pocos segundos.
-- Medido el 2026-10-31: cargar 1,4 s, validar 4,9 s, materias primas 1 s, recetas 5,2 s (con auditoría
-- completa; sin ella, la mitad). El límite es holgado por las máquinas de GitHub Actions.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(4);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.as_user(p_user uuid, p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;

-- Filas generadas: I1..I300, P1..P40 (P11..P40 usan una de 10 más abajo), D1..D90.
create temporary table gen (n serial, row jsonb);
insert into gen (row)
select jsonb_build_object('sheet', 'INSUMOS', 'row_number', i, 'kind', 'ingredient', 'source_code', 'I' || i,
                          'parsed', jsonb_build_object('name', 'Insumo de carga ' || i, 'category', 'Carga ' || (i % 8)))
  from generate_series(1, 300) i;
insert into gen (row)
select r from generate_series(1, 40) p,
  lateral (select jsonb_build_object('sheet', 'pre-elaborado', 'row_number', p * 10, 'kind', 'preparation',
                                     'source_code', 'P' || p, 'parsed', jsonb_build_object('name', 'Preparación de carga ' || p,
                                                                                            'yield_grams', 1000)) as r
           union all
           select jsonb_build_object('sheet', 'pre-elaborado', 'row_number', p * 10 + k, 'kind', 'line', 'parent_row', p * 10,
                                     'source_code', 'I' || ((p * 7 + k) % 300 + 1), 'parent_code', 'P' || p,
                                     'parsed', jsonb_build_object('grams', 100 + k))
             from generate_series(1, 5) k
           union all
           select jsonb_build_object('sheet', 'pre-elaborado', 'row_number', p * 10 + 6, 'kind', 'line', 'parent_row', p * 10,
                                     'source_code', 'P' || (p - 10), 'parent_code', 'P' || p,
                                     'parsed', jsonb_build_object('grams', 200))
            where p > 10) x;
insert into gen (row)
select r from generate_series(1, 90) d,
  lateral (select jsonb_build_object('sheet', 'PLATOS', 'row_number', d * 10, 'kind', 'dish', 'source_code', 'D' || d,
                                     'parsed', jsonb_build_object('name', 'Plato de carga ' || d, 'portions', 1,
                                                                  'portion_grams', 350)) as r
           union all
           select jsonb_build_object('sheet', 'PLATOS', 'row_number', d * 10 + k, 'kind', 'line', 'parent_row', d * 10,
                                     'source_code', 'I' || ((d * 11 + k) % 300 + 1), 'parent_code', 'D' || d,
                                     'parsed', jsonb_build_object('grams', 50 + k, 'measure', 'CUP ' || k))
             from generate_series(1, 4) k
           union all
           select jsonb_build_object('sheet', 'PLATOS', 'row_number', d * 10 + 5, 'kind', 'line', 'parent_row', d * 10,
                                     'source_code', 'P' || (d % 40 + 1), 'parent_code', 'D' || d,
                                     'parsed', jsonb_build_object('grams', 150))) x;

create temporary table timings (what text, ms numeric);
create temporary table job (id uuid);
insert into storage.objects (bucket_id, name)
values ('imports', format('%s/%s/%s.xlsx', pg_temp.u(1), pg_temp.u(101), pg_temp.u(9500)));
insert into job
select (pg_temp.as_user(pg_temp.u(405), format(
  $$select imports.create_job(%L, '%s/%s/%s.xlsx', 'carga.xlsx', %L, 'CARGA', 'Prueba de volumen')$$,
  pg_temp.u(101), pg_temp.u(1), pg_temp.u(101), pg_temp.u(9500), repeat('ab', 32))) ->> 'id')::uuid;

do $$
declare
  t0 timestamptz := clock_timestamp();
  b  integer;
begin
  for b in 0..(select (count(*) - 1) / 500 from gen) loop
    perform pg_temp.as_user(pg_temp.u(405), format($f$select imports.stage_rows(%L, %L)$f$, (select id from job),
      (select jsonb_agg(row order by n) from gen where n > b * 500 and n <= (b + 1) * 500)));
  end loop;
  insert into timings values ('cargar las filas', extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  perform pg_temp.as_user(pg_temp.u(405), format($f$select imports.validate_job(%L)$f$, (select id from job)));
  insert into timings values ('validar', extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  perform pg_temp.as_user(pg_temp.u(408), format($f$select imports.confirm_ingredients(%L, 'Prueba')$f$, (select id from job)));
  insert into timings values ('confirmar materias primas', extract(epoch from clock_timestamp() - t0) * 1000);
  t0 := clock_timestamp();
  perform pg_temp.as_user(pg_temp.u(405), format($f$select imports.confirm_recipes(%L, 'Prueba')$f$, (select id from job)));
  insert into timings values ('confirmar recetas', extract(epoch from clock_timestamp() - t0) * 1000);
end
$$;

select is((select count(*)::int from gen), (select count(*)::int from imports.import_staging_rows where job_id = (select id from job)),
  'todas las filas quedaron cargadas');
select is((select count(*)::int from imports.import_staging_rows where job_id = (select id from job) and action = 'error'), 0,
  'sin errores');
select is((select count(*)::int from recipes.recipes where code like 'CARGA-%'), 130, 'se crearon las 130 recetas');
select ok((select bool_and(ms < 20000) from timings),
  'cada paso tarda menos de 20 segundos (en la máquina de desarrollo, unos 5): ' || (select string_agg(what || ' ' || round(ms) || ' ms', ', ') from timings));

select * from finish();
rollback;
