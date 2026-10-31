-- Fase 2, etapa 2.4: importar el recetario de Excel (ADR-0027). Pedido de Soy (ADR-0026, pregunta 11):
-- cargar el recetario actual de cada restaurante desde su Excel; después, todo por pantallas.
--
-- - El servidor lee el archivo al subirlo y carga sus filas en una zona intermedia (import_staging_rows).
--   Validar no toca nada oficial: muestra qué se crea, qué se reutiliza, qué se omite y qué tiene
--   errores, fila por fila, con las mismas reglas que el recetario (alcance, unidades, círculos, niveles).
-- - Se confirma en dos pasos (decisión de Joaco, 2026-10-31): Compras confirma las materias primas
--   nuevas (catalog.manage) y después el Chef o el Director confirma las recetas (imports.approve y
--   recipes.draft en la marca). Todo queda en borrador y pasa por la revisión de siempre.
-- - Sin duplicados (caso 8): el mismo archivo no se importa dos veces; un código que ya existe no se
--   vuelve a crear (la materia prima se reutiliza, la receta de la marca se omite y no se pisa).
-- - Los códigos del Excel se conservan con el prefijo de la marca (NON-190000): un prefijo es de una sola
--   marca, y cada marca usa siempre el mismo.
-- - Los precios del Excel van aparte (import_prices) y los ve solo quien tiene prices.view (decisión de
--   Joaco, 2026-10-31): el Chef importa sin ver precios. Pasan a la tabla de precios en la etapa 2.1 C.

create schema if not exists imports;
comment on schema imports is
  'Carga de Excel en dos tiempos: filas intermedias revisables y confirmación. Nada pasa a lo oficial sin confirmar (ADR-0027).';
grant usage on schema imports to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Tipos y tablas
-- ---------------------------------------------------------------------------
create type imports.job_status as enum ('uploaded', 'staged', 'validated', 'ingredients_confirmed', 'confirmed', 'cancelled');
comment on type imports.job_status is
  'Estado de una importación: subida, filas cargadas, validada, materias primas confirmadas (por Compras), confirmada (recetas creadas) o cancelada.';
create type imports.row_kind as enum ('ingredient', 'preparation', 'dish', 'line');
comment on type imports.row_kind is 'Qué es una fila del Excel: materia prima, preparación (pre-elaborado), plato o línea de una receta.';
create type imports.row_action as enum ('create', 'reuse', 'skip', 'error');
comment on type imports.row_action is
  'Qué pasa con una fila al confirmar: se crea, se reutiliza lo que ya existe, se omite (ya existe y no se pisa) o tiene un error.';
create type imports.issue_severity as enum ('error', 'warning');
comment on type imports.issue_severity is 'Un error frena la fila; un aviso no (por ejemplo, una receta sin componentes).';

create table imports.import_jobs (
  id                        uuid primary key default gen_random_uuid(),
  group_id                  uuid not null references org.groups (id) on delete restrict,
  brand_id                  uuid not null,
  kind                      text not null default 'recipe_book' check (kind = 'recipe_book'),
  code_prefix               text not null check (code_prefix ~ '^[A-Z0-9]{2,6}$'),
  file_name                 text not null check (length(btrim(file_name)) between 1 and 200),
  storage_path              text not null check (storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.xlsx$'),
  file_sha256               text not null check (file_sha256 ~ '^[0-9a-f]{64}$'),
  status                    imports.job_status not null default 'uploaded',
  ingredients_confirmed_by  uuid references core.actors (id) on delete restrict,
  ingredients_confirmed_at  timestamptz,
  confirmed_by              uuid references core.actors (id) on delete restrict,
  confirmed_at              timestamptz,
  created_at                timestamptz not null default now(),
  created_by                uuid references core.actors (id) on delete restrict,
  updated_at                timestamptz not null default now(),
  updated_by                uuid references core.actors (id) on delete restrict,
  deleted_at                timestamptz,
  deleted_by                uuid references core.actors (id) on delete restrict,
  constraint import_jobs_id_group_key unique (id, group_id),
  constraint import_jobs_brand_fkey foreign key (brand_id, group_id) references org.brands (id, group_id) on delete restrict
);
-- El mismo archivo no se importa dos veces en el grupo (caso 8), salvo que se haya cancelado.
create unique index import_jobs_sha_key on imports.import_jobs (group_id, file_sha256)
  where status <> 'cancelled' and deleted_at is null;
create index import_jobs_brand_idx on imports.import_jobs (brand_id, group_id);
create index import_jobs_prefix_idx on imports.import_jobs (group_id, code_prefix) where status <> 'cancelled' and deleted_at is null;
create index import_jobs_created_idx on imports.import_jobs (group_id, created_at desc);
comment on table imports.import_jobs is
  'Cada archivo de Excel que se importa: de qué marca, con qué prefijo de códigos, su huella (para no importarlo dos veces) y en qué paso está.';
comment on column imports.import_jobs.id is 'Identificador de la importación.';
comment on column imports.import_jobs.group_id is 'Grupo.';
comment on column imports.import_jobs.brand_id is 'Marca a la que van las recetas importadas.';
comment on column imports.import_jobs.kind is 'Tipo de archivo: recipe_book (el recetario de Excel de un restaurante).';
comment on column imports.import_jobs.code_prefix is 'Prefijo de la marca para los códigos del Excel (NON → NON-190000). Es siempre el mismo para la marca.';
comment on column imports.import_jobs.file_name is 'Nombre del archivo que se subió.';
comment on column imports.import_jobs.storage_path is 'Dónde está el archivo en el bucket imports: <grupo>/<marca>/<archivo>.xlsx.';
comment on column imports.import_jobs.file_sha256 is 'Huella SHA-256 del contenido, calculada por el servidor al leerlo: el mismo archivo no se importa dos veces.';
comment on column imports.import_jobs.status is 'Paso en el que está la importación.';
comment on column imports.import_jobs.ingredients_confirmed_by is 'Quién confirmó las materias primas nuevas (Compras).';
comment on column imports.import_jobs.ingredients_confirmed_at is 'Cuándo se confirmaron las materias primas.';
comment on column imports.import_jobs.confirmed_by is 'Quién confirmó las recetas.';
comment on column imports.import_jobs.confirmed_at is 'Cuándo se confirmaron las recetas.';
comment on column imports.import_jobs.created_at is 'Cuándo se subió (lo pone la base).';
comment on column imports.import_jobs.created_by is 'Quién la subió (lo pone la base).';
comment on column imports.import_jobs.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column imports.import_jobs.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column imports.import_jobs.deleted_at is 'Borrado lógico.';
comment on column imports.import_jobs.deleted_by is 'Quién la borró (lo pone la base).';

create table imports.import_staging_rows (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null,
  job_id             uuid not null,
  sheet              text not null check (length(btrim(sheet)) between 1 and 60),
  row_number         integer not null check (row_number between 1 and 100000),
  kind               imports.row_kind not null,
  source_code        text check (source_code is null or length(source_code) between 1 and 40),
  parent_code        text check (parent_code is null or length(parent_code) between 1 and 40),
  parent_row         integer check (parent_row is null or parent_row between 1 and 100000),
  raw                jsonb not null default '{}' check (pg_column_size(raw) < 8192),
  parsed             jsonb not null default '{}' check (pg_column_size(parsed) < 4096),
  action             imports.row_action,
  ingredient_id      uuid,
  recipe_id          uuid,
  recipe_version_id  uuid,
  level              integer check (level is null or level between 0 and 12),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint import_staging_rows_id_job_key unique (id, job_id),
  constraint import_staging_rows_job_fkey foreign key (job_id, group_id)
    references imports.import_jobs (id, group_id) on delete restrict,
  constraint import_staging_rows_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint import_staging_rows_recipe_fkey foreign key (recipe_id, group_id)
    references recipes.recipes (id, group_id) on delete restrict,
  constraint import_staging_rows_version_fkey foreign key (recipe_version_id, group_id)
    references recipes.recipe_versions (id, group_id) on delete restrict,
  -- Una línea pertenece a un bloque: la fila de su receta, en la misma solapa.
  constraint import_staging_rows_line_check
    check ((kind = 'line') = (parent_code is not null) and (kind = 'line') = (parent_row is not null)),
  -- Lo que se reutiliza apunta a la materia prima existente.
  constraint import_staging_rows_reuse_check
    check (action is distinct from 'reuse' or (kind = 'ingredient' and ingredient_id is not null))
);
create unique index import_staging_rows_key on imports.import_staging_rows (job_id, sheet, row_number) where deleted_at is null;
create index import_staging_rows_group_idx on imports.import_staging_rows (group_id);
create index import_staging_rows_code_idx on imports.import_staging_rows (job_id, kind, source_code);
create index import_staging_rows_parent_idx on imports.import_staging_rows (job_id, sheet, parent_row) where parent_row is not null;
create index import_staging_rows_ingredient_idx on imports.import_staging_rows (ingredient_id, group_id) where ingredient_id is not null;
create index import_staging_rows_recipe_idx on imports.import_staging_rows (recipe_id, group_id) where recipe_id is not null;
create index import_staging_rows_version_idx on imports.import_staging_rows (recipe_version_id, group_id) where recipe_version_id is not null;
comment on table imports.import_staging_rows is
  'Filas del Excel tal como se leyeron (raw) y ya interpretadas (parsed), sin precios, con qué pasa con cada una al confirmar. No tocan lo oficial hasta confirmar.';
comment on column imports.import_staging_rows.id is 'Identificador de la fila.';
comment on column imports.import_staging_rows.group_id is 'Grupo.';
comment on column imports.import_staging_rows.job_id is 'Importación a la que pertenece.';
comment on column imports.import_staging_rows.sheet is 'Solapa del Excel.';
comment on column imports.import_staging_rows.row_number is 'Número de fila en la solapa (para encontrarla y corregirla).';
comment on column imports.import_staging_rows.kind is 'Materia prima, preparación, plato o línea de una receta.';
comment on column imports.import_staging_rows.source_code is 'Código en el Excel (sin prefijo). En una línea, el código del componente.';
comment on column imports.import_staging_rows.parent_code is 'En una línea: el código de la receta a la que pertenece.';
comment on column imports.import_staging_rows.parent_row is 'En una línea: la fila de su receta en la misma solapa (ata la línea a su bloque).';
comment on column imports.import_staging_rows.raw is 'Las celdas tal como estaban en el Excel, sin las de precio.';
comment on column imports.import_staging_rows.parsed is
  'Lo interpretado, sin precios: nombre, rubro, rinde, porciones, peso por porción, gramos, medida casera, presentación, peso neto, merma.';
comment on column imports.import_staging_rows.action is 'Qué pasa al confirmar (la calcula la validación).';
comment on column imports.import_staging_rows.ingredient_id is 'Materia prima: la existente que se reutiliza, o la creada al confirmar.';
comment on column imports.import_staging_rows.recipe_id is 'Receta: la existente que se omite, o la creada al confirmar.';
comment on column imports.import_staging_rows.recipe_version_id is 'Línea: la versión en la que quedó, después de confirmar.';
comment on column imports.import_staging_rows.level is 'En las recetas: niveles de preparaciones que tiene debajo (para crearlas en orden).';
comment on column imports.import_staging_rows.created_at is 'Cuándo se cargó (lo pone la base).';
comment on column imports.import_staging_rows.created_by is 'Quién la cargó (lo pone la base).';
comment on column imports.import_staging_rows.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column imports.import_staging_rows.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column imports.import_staging_rows.deleted_at is 'Borrado lógico.';
comment on column imports.import_staging_rows.deleted_by is 'Quién la borró (lo pone la base).';

-- Los precios del Excel, aparte: los ve solo quien tiene prices.view (el Chef importa sin verlos).
create table imports.import_prices (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null,
  job_id        uuid not null,
  row_id        uuid not null,
  price         numeric(18, 4) check (price is null or price >= 0),
  price_per_kg  numeric(20, 8) check (price_per_kg is null or price_per_kg >= 0),
  currency      text not null default 'ARS' check (currency ~ '^[A-Z]{3}$'),
  created_at    timestamptz not null default now(),
  created_by    uuid references core.actors (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references core.actors (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references core.actors (id) on delete restrict,
  constraint import_prices_job_fkey foreign key (job_id, group_id) references imports.import_jobs (id, group_id) on delete restrict,
  constraint import_prices_row_fkey foreign key (row_id, job_id) references imports.import_staging_rows (id, job_id) on delete restrict
);
create unique index import_prices_row_key on imports.import_prices (row_id) where deleted_at is null;
create index import_prices_row_idx on imports.import_prices (row_id, job_id);
create index import_prices_job_idx on imports.import_prices (job_id, group_id);
create index import_prices_group_idx on imports.import_prices (group_id);
comment on table imports.import_prices is
  'Precios de compra que trae el Excel, por materia prima. Son valores de prueba, sin factura: pasan a la tabla de precios en la etapa 2.1 C. Los ve solo quien tiene prices.view.';
comment on column imports.import_prices.id is 'Identificador.';
comment on column imports.import_prices.group_id is 'Grupo.';
comment on column imports.import_prices.job_id is 'Importación.';
comment on column imports.import_prices.row_id is 'Fila de la materia prima.';
comment on column imports.import_prices.price is 'Precio de la presentación, tal como estaba en el Excel.';
comment on column imports.import_prices.price_per_kg is 'Precio por kilo o litro que calculaba el Excel.';
comment on column imports.import_prices.currency is 'Moneda (ISO 4217).';
comment on column imports.import_prices.created_at is 'Cuándo se cargó (lo pone la base).';
comment on column imports.import_prices.created_by is 'Quién lo cargó (lo pone la base).';
comment on column imports.import_prices.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column imports.import_prices.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column imports.import_prices.deleted_at is 'Borrado lógico.';
comment on column imports.import_prices.deleted_by is 'Quién lo borró (lo pone la base).';

create table imports.import_errors (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null,
  job_id      uuid not null,
  row_id      uuid,
  sheet       text check (sheet is null or length(btrim(sheet)) between 1 and 60),
  row_number  integer check (row_number is null or row_number between 1 and 100000),
  field       text check (field is null or length(field) between 1 and 60),
  code        text not null check (code ~ '^[a-z_]{1,40}$'),
  severity    imports.issue_severity not null default 'error',
  message     text not null check (length(btrim(message)) between 1 and 300),
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint import_errors_job_fkey foreign key (job_id, group_id)
    references imports.import_jobs (id, group_id) on delete restrict,
  constraint import_errors_row_fkey foreign key (row_id, job_id)
    references imports.import_staging_rows (id, job_id) on delete restrict
);
create index import_errors_job_idx on imports.import_errors (job_id, group_id);
create index import_errors_group_idx on imports.import_errors (group_id);
create index import_errors_row_idx on imports.import_errors (row_id, job_id) where row_id is not null;
comment on table imports.import_errors is
  'Errores y avisos de la validación, por fila, en español. Se descargan para corregir el Excel. Al volver a validar, los anteriores quedan dados de baja.';
comment on column imports.import_errors.id is 'Identificador.';
comment on column imports.import_errors.group_id is 'Grupo.';
comment on column imports.import_errors.job_id is 'Importación.';
comment on column imports.import_errors.row_id is 'Fila intermedia, si el problema es de una fila.';
comment on column imports.import_errors.sheet is 'Solapa del Excel.';
comment on column imports.import_errors.row_number is 'Fila del Excel.';
comment on column imports.import_errors.field is 'Columna o dato con problema.';
comment on column imports.import_errors.code is 'Código del problema (por ejemplo, unknown_code).';
comment on column imports.import_errors.severity is 'Error (la fila no se importa) o aviso (se importa igual).';
comment on column imports.import_errors.message is 'Qué pasa y qué hacer, en español.';
comment on column imports.import_errors.created_at is 'Cuándo se detectó (lo pone la base).';
comment on column imports.import_errors.created_by is 'Quién validó (lo pone la base).';
comment on column imports.import_errors.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column imports.import_errors.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column imports.import_errors.deleted_at is 'Baja al volver a validar.';
comment on column imports.import_errors.deleted_by is 'Quién lo dio de baja (lo pone la base).';

do $$
declare
  t text;
begin
  foreach t in array array['import_jobs', 'import_staging_rows', 'import_prices', 'import_errors'] loop
    execute format('alter table imports.%I enable row level security', t);
    execute format('revoke all on imports.%I from public, anon, authenticated, service_role', t);
    execute format('create trigger set_control_columns before insert or update on imports.%I
                      for each row execute function core.set_control_columns()', t);
    execute format('create trigger log_change after insert or update or delete on imports.%I
                      for each row execute function audit.log_change()', t);
    execute format('create trigger reject_truncate before truncate on imports.%I
                      for each statement execute function core.reject_truncate()', t);
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Quién ve una importación: quien sube o confirma recetas en la marca, o Compras del grupo
-- ---------------------------------------------------------------------------
create function imports.visible_job_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select j.id
    from imports.import_jobs j
   where j.deleted_at is null
     and (j.brand_id in (select core.permitted_brand_ids('imports.run'))
          or j.brand_id in (select core.permitted_brand_ids('imports.approve'))
          or j.group_id in (select core.permitted_group_ids('catalog.manage')))
$$;
comment on function imports.visible_job_ids() is
  'Importaciones que ve la sesión: con imports.run o imports.approve en su marca, o catalog.manage en el grupo (Compras). Para las políticas.';
revoke execute on function imports.visible_job_ids() from public;
grant execute on function imports.visible_job_ids() to authenticated;

create policy import_jobs_select on imports.import_jobs for select to authenticated
  using (id in (select imports.visible_job_ids()));
create policy import_staging_rows_select on imports.import_staging_rows for select to authenticated
  using (deleted_at is null and job_id in (select imports.visible_job_ids()));
create policy import_errors_select on imports.import_errors for select to authenticated
  using (deleted_at is null and job_id in (select imports.visible_job_ids()));
-- Los precios, además, piden prices.view en el grupo.
create policy import_prices_select on imports.import_prices for select to authenticated
  using (deleted_at is null and job_id in (select imports.visible_job_ids())
         and group_id in (select core.permitted_group_ids('prices.view')));
grant select on imports.import_jobs, imports.import_staging_rows, imports.import_prices, imports.import_errors to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Bucket privado para los archivos
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('imports', 'imports', false, 15728640,
        array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);

-- La marca de un archivo del bucket (<grupo>/<marca>/<archivo>.xlsx), si es de ese grupo y la sesión
-- importa ahí o ve precios (no confirma la existencia de marcas ajenas).
create function imports.file_brand_id(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b.id
    from org.brands b
   where p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.xlsx$'
     and b.id::text = split_part(p_name, '/', 2) and b.group_id::text = split_part(p_name, '/', 1)
     and b.deleted_at is null
     and (core.has_permission_in_brand('imports.run', b.id) or core.has_permission_in_group('prices.view', b.group_id))
$$;
comment on function imports.file_brand_id(text) is
  'La marca de un archivo del bucket imports (segunda carpeta del nombre), si la ruta tiene la forma esperada, la marca es de ese grupo y la sesión importa ahí o ve precios.';
revoke execute on function imports.file_brand_id(text) from public;
grant execute on function imports.file_brand_id(text) to authenticated;

-- El grupo de un archivo del bucket (primera carpeta), con las mismas condiciones que file_brand_id.
create function imports.file_group_id(p_name text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b.group_id from org.brands b where b.id = imports.file_brand_id(p_name)
$$;
comment on function imports.file_group_id(text) is 'El grupo de un archivo del bucket imports (el de su marca).';
revoke execute on function imports.file_group_id(text) from public;
grant execute on function imports.file_group_id(text) to authenticated;

-- Sube quien importa en la marca. El archivo tiene precios: lo baja solo quien ve precios en el grupo (el
-- servidor lo lee en el momento de subirlo, así que quien importa no necesita bajarlo).
create policy imports_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'imports'
              and core.has_permission_in_brand('imports.run', imports.file_brand_id(name)));
create policy imports_read on storage.objects for select to authenticated
  using (bucket_id = 'imports' and core.has_permission_in_group('prices.view', imports.file_group_id(name)));
-- Sin políticas de update ni de delete: un archivo subido no se cambia ni se borra.

-- ---------------------------------------------------------------------------
-- 4. Ayudantes
-- ---------------------------------------------------------------------------
-- Un nombre comparable: sin espacios de más y en minúsculas ("ACEITE  DE OLIVA " = "aceite de oliva").
create function imports.norm(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(regexp_replace(btrim(coalesce(p_text, '')), '\s+', ' ', 'g'))
$$;
comment on function imports.norm(text) is 'Interna: nombre comparable (minúsculas, sin espacios de más).';
revoke execute on function imports.norm(text) from public;

-- Un texto para guardar: sin espacios de más (así lo que se compara y lo que se guarda coinciden).
create function imports.clean(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(btrim(coalesce(p_text, '')), '\s+', ' ', 'g')
$$;
comment on function imports.clean(text) is 'Interna: texto sin espacios de más.';
revoke execute on function imports.clean(text) from public;

-- El rubro de una materia prima, como se guarda en las categorías (hasta 80 caracteres).
create function imports.category_name(p_parsed jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(imports.clean(coalesce(nullif(btrim(p_parsed ->> 'category'), ''), 'Importado')), 80)
$$;
comment on function imports.category_name(jsonb) is 'Interna: rubro de la fila, recortado como se guarda (o "Importado").';
revoke execute on function imports.category_name(jsonb) from public;

-- El código completo en el sistema: prefijo de la marca + código del Excel (NON + 190000 → NON-190000).
create function imports.full_code(p_prefix text, p_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(p_prefix || '-' || btrim(p_code))
$$;
comment on function imports.full_code(text, text) is 'Interna: código con el prefijo de la marca.';
revoke execute on function imports.full_code(text, text) from public;

-- Un número de una celda (puede venir como texto: "1708", "0,5", "#N/A"); vacío si no es un número.
create function imports.num(p_value text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case when btrim(coalesce(p_value, '')) ~ '^-?[0-9]{1,12}([.,][0-9]{1,8})?$'
              then replace(btrim(p_value), ',', '.')::numeric end
$$;
comment on function imports.num(text) is 'Interna: el número de una celda, o vacío si no es un número.';
revoke execute on function imports.num(text) from public;

-- La importación sin bloquear (para mirar el permiso antes de bloquear nada).
create function imports.find_job(p_job_id uuid)
returns imports.import_jobs
language sql
stable
security definer
set search_path = ''
as $$
  select * from imports.import_jobs where id = p_job_id and deleted_at is null
$$;
comment on function imports.find_job(uuid) is 'Interna: la importación, sin bloquearla (vacía si no existe).';
revoke execute on function imports.find_job(uuid) from public;

-- La importación bloqueada para cambiarla. Se llama después de controlar el permiso.
create function imports.lock_job(p_job_id uuid)
returns imports.import_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job imports.import_jobs;
begin
  select * into v_job from imports.import_jobs where id = p_job_id and deleted_at is null for update;
  return v_job;
end
$$;
comment on function imports.lock_job(uuid) is 'Interna: la importación bloqueada (después de controlar el permiso).';
revoke execute on function imports.lock_job(uuid) from public;

-- Las recetas existentes que una receta nueva de la marca puede usar u omitir: activas, del grupo o de esa
-- marca (mismas reglas de alcance que recipes.sub_in_scope). Lo de otras marcas, de un local o una variante,
-- nunca. Con la unidad de su versión vigente, si tiene.
create function imports.brand_recipes(p_group_id uuid, p_brand_id uuid)
returns table (id uuid, code text, published_unit uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select r.id, r.code,
         (select v.yield_unit_id from recipes.recipe_versions v where v.recipe_id = r.id and v.status = 'published')
    from recipes.recipes r
   where r.group_id = p_group_id and r.deleted_at is null and r.is_active
     and (r.scope_type = 'group' or (r.scope_type = 'brand' and r.brand_id = p_brand_id))
$$;
comment on function imports.brand_recipes(uuid, uuid) is
  'Interna: recetas activas del grupo o de la marca (las únicas que una importación de esa marca puede usar u omitir), con la unidad de su vigente.';
revoke execute on function imports.brand_recipes(uuid, uuid) from public;

-- Error en español cuando lo validado ya no vale (algo cambió entre validar y confirmar).
create function imports.changed_since_validation(p_what text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Algo cambió desde la validación (%): volvé a validar y revisá la vista previa.', p_what
    using errcode = '23514';
end
$$;
comment on function imports.changed_since_validation(text) is 'Interna: error en español cuando lo validado ya no vale.';
revoke execute on function imports.changed_since_validation(text) from public;

-- ---------------------------------------------------------------------------
-- 5. Subir y cargar las filas
-- ---------------------------------------------------------------------------
create function imports.create_job(p_brand_id uuid, p_storage_path text, p_file_name text, p_file_sha256 text,
                                   p_code_prefix text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_brand    org.brands;
  v_prefix   text := upper(btrim(coalesce(p_code_prefix, '')));
  v_previous timestamptz;
  v_other    text;
  v_id       uuid;
begin
  select * into v_brand from org.brands where id = p_brand_id and deleted_at is null;
  if v_brand.id is null or not core.has_permission_in_brand('imports.run', p_brand_id) then
    return core.deny('imports.create_job', 'No tenés permiso para importar recetas en esa marca.', null,
                     jsonb_build_object('brand_id', p_brand_id), v_brand.group_id, p_brand_id, null);
  end if;
  if imports.file_brand_id(p_storage_path) is distinct from p_brand_id
     or not exists (select 1 from storage.objects o where o.bucket_id = 'imports' and o.name = p_storage_path) then
    raise exception 'El archivo no se subió bien: probá de nuevo.' using errcode = '22023';
  end if;
  if v_prefix !~ '^[A-Z0-9]{2,6}$' then
    raise exception 'El prefijo de los códigos lleva de 2 a 6 letras o números (por ejemplo, NON).' using errcode = '22023';
  end if;
  -- Las importaciones del grupo se registran de a una (prefijos y huellas sin cruces).
  perform pg_advisory_xact_lock(hashtextextended('imports.jobs:' || v_brand.group_id::text, 0));
  -- Un prefijo es de una sola marca, y cada marca usa siempre el mismo (si no, el caso 8 se rompería).
  if exists (select 1 from imports.import_jobs
              where group_id = v_brand.group_id and code_prefix = v_prefix and brand_id <> p_brand_id
                and status <> 'cancelled' and deleted_at is null) then
    raise exception 'El prefijo % ya lo usa otra marca del grupo: elegí otro.', v_prefix using errcode = '23514';
  end if;
  select code_prefix into v_other from imports.import_jobs
   where brand_id = p_brand_id and code_prefix <> v_prefix and status <> 'cancelled' and deleted_at is null limit 1;
  if v_other is not null then
    raise exception 'Esta marca ya importó con el prefijo %: usá el mismo, así no se duplican los códigos.', v_other
      using errcode = '23514';
  end if;
  select created_at into v_previous from imports.import_jobs
   where group_id = v_brand.group_id and file_sha256 = lower(p_file_sha256) and status <> 'cancelled' and deleted_at is null;
  if v_previous is not null then
    raise exception 'Este archivo ya se importó el %. Si cambió, subí la versión nueva.',
      to_char(v_previous at time zone 'America/Argentina/Buenos_Aires', 'DD/MM/YYYY') using errcode = '23505';
  end if;
  perform core.set_change_context(p_reason, 'import');
  begin
    insert into imports.import_jobs (group_id, brand_id, code_prefix, file_name, storage_path, file_sha256)
    values (v_brand.group_id, p_brand_id, v_prefix, btrim(p_file_name), p_storage_path, lower(p_file_sha256))
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'Este archivo ya se importó.' using errcode = '23505';
    when check_violation or not_null_violation then
      raise exception 'Algún dato del archivo no es válido (nombre o huella).' using errcode = '22023';
  end;
  return jsonb_build_object('result', 'applied', 'id', v_id, 'message', 'Archivo recibido. Ahora se leen sus filas.');
end
$$;
comment on function imports.create_job(uuid, text, text, text, text, text) is
  'Registra un archivo subido al bucket imports para una marca. Rechaza el mismo archivo dos veces (caso 8) y un prefijo de otra marca. Pide imports.run en la marca y un motivo.';

create function imports.stage_rows(p_job_id uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job  imports.import_jobs := imports.find_job(p_job_id);
  v_row  jsonb;
  v_id   uuid;
  v_n    integer := 0;
  v_kind imports.row_kind;
begin
  if v_job.id is null or not core.has_permission_in_brand('imports.run', v_job.brand_id) then
    return core.deny('imports.stage_rows', 'No tenés permiso para cargar esa importación.', null,
                     jsonb_build_object('job_id', p_job_id), v_job.group_id, v_job.brand_id, null);
  end if;
  v_job := imports.lock_job(p_job_id);
  if v_job.status not in ('uploaded', 'staged') then
    raise exception 'Esta importación ya se validó: para cambiar filas, subí el archivo de nuevo.' using errcode = '23514';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then
    raise exception 'Las filas van en lotes de hasta 500.' using errcode = '22023';
  end if;
  if (select count(*) from imports.import_staging_rows where job_id = v_job.id and deleted_at is null)
     + jsonb_array_length(p_rows) > 10000 then
    raise exception 'El archivo tiene demasiadas filas (hasta 10.000).' using errcode = '22023';
  end if;
  perform core.set_change_context('Carga de filas del Excel', 'import');
  -- Solo los errores de las filas se traducen (los avisos propios de arriba no pasan por acá).
  begin
    for v_row in select value from jsonb_array_elements(p_rows) loop
      perform org.check_keys(v_row, array['sheet', 'row_number', 'kind', 'source_code', 'parent_code', 'parent_row',
                                          'raw', 'parsed', 'price']);
      v_kind := (v_row ->> 'kind')::imports.row_kind;
      -- Lo interpretado lleva solo estos datos; los precios van aparte, y no en las celdas.
      perform org.check_keys(coalesce(v_row -> 'parsed', '{}'),
        case v_kind when 'ingredient' then array['name', 'category', 'presentation_grams', 'net_grams', 'waste_percent']
                    when 'line' then array['grams', 'measure']
                    else array['name', 'yield_grams', 'portions', 'portion_grams'] end);
      -- Las celdas tal como estaban, también con una lista cerrada y solo valores simples: un precio no
      -- puede colarse con otro nombre ni anidado (revisión de seguridad, M1).
      if jsonb_typeof(coalesce(v_row -> 'raw', '{}')) <> 'object' then
        raise exception 'Las celdas de una fila van como un objeto.' using errcode = '22023';
      end if;
      perform org.check_keys(coalesce(v_row -> 'raw', '{}'),
        case v_kind when 'ingredient' then array['codigo', 'rubro', 'producto', 'proveedor', 'marca', 'presentacion',
                                                 'peso_neto']
                    when 'line' then array['codigo', 'ingrediente', 'medida', 'gramos']
                    else array['codigo', 'nombre', 'peso_total', 'porciones', 'peso_porcion'] end);
      if exists (select 1 from jsonb_each(coalesce(v_row -> 'raw', '{}')) e
                  where jsonb_typeof(e.value) not in ('string', 'number', 'null')) then
        raise exception 'Las celdas de una fila van como textos o números.' using errcode = '22023';
      end if;
      insert into imports.import_staging_rows (group_id, job_id, sheet, row_number, kind, source_code, parent_code,
                                               parent_row, raw, parsed)
      values (v_job.group_id, v_job.id, v_row ->> 'sheet', (v_row ->> 'row_number')::integer, v_kind,
              nullif(btrim(v_row ->> 'source_code'), ''), nullif(btrim(v_row ->> 'parent_code'), ''),
              (v_row ->> 'parent_row')::integer, coalesce(v_row -> 'raw', '{}'), coalesce(v_row -> 'parsed', '{}'))
      returning id into v_id;
      if v_kind = 'ingredient' and jsonb_typeof(v_row -> 'price') = 'object' then
        perform org.check_keys(v_row -> 'price', array['price', 'price_per_kg']);
        insert into imports.import_prices (group_id, job_id, row_id, price, price_per_kg)
        values (v_job.group_id, v_job.id, v_id, imports.num(v_row -> 'price' ->> 'price'),
                imports.num(v_row -> 'price' ->> 'price_per_kg'));
      end if;
      v_n := v_n + 1;
    end loop;
  exception
    when unique_violation then
      raise exception 'Una fila del Excel vino dos veces.' using errcode = '23505';
    when invalid_text_representation or check_violation or not_null_violation or numeric_value_out_of_range then
      raise exception 'Alguna fila no tiene la forma esperada.' using errcode = '22023';
  end;
  update imports.import_jobs set status = 'staged' where id = v_job.id;
  return jsonb_build_object('result', 'applied', 'message', format('%s filas cargadas.', v_n));
end
$$;
comment on function imports.stage_rows(uuid, jsonb) is
  'Carga hasta 500 filas leídas del Excel en la zona intermedia (los precios, aparte). No toca nada oficial. Pide imports.run en la marca. La carga la hace el servidor con la sesión de quien importa (riesgo aceptado, ADR-0027).';

-- ---------------------------------------------------------------------------
-- 6. Validar: qué se crea, qué se reutiliza, qué se omite y qué tiene errores
-- ---------------------------------------------------------------------------
create function imports.validate_job(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job     imports.import_jobs := imports.find_job(p_job_id);
  v_full    boolean;
  v_a       integer;
  v_b       integer;
  v_round   integer := 0;
begin
  if v_job.id is null or not core.has_permission_in_brand('imports.run', v_job.brand_id) then
    return core.deny('imports.validate_job', 'No tenés permiso para validar esa importación.', null,
                     jsonb_build_object('job_id', p_job_id), v_job.group_id, v_job.brand_id, null);
  end if;
  v_job := imports.lock_job(p_job_id);
  if v_job.status not in ('staged', 'validated', 'ingredients_confirmed') then
    raise exception 'Esta importación no se puede validar en este paso.' using errcode = '23514';
  end if;
  -- Con las materias primas ya confirmadas, se revalidan solo las recetas y sus líneas.
  v_full := v_job.status <> 'ingredients_confirmed';
  perform core.set_change_context('Validación de la importación', 'import');

  -- Se empieza de cero: los problemas anteriores se dan de baja y las acciones se recalculan. Todo por
  -- conjuntos (una sentencia por tipo de fila), para que cada fila se actualice pocas veces.
  update imports.import_errors e set deleted_at = now()
   where e.job_id = v_job.id and e.deleted_at is null
     and (v_full or e.row_id in (select r.id from imports.import_staging_rows r
                                  where r.job_id = v_job.id and r.kind <> 'ingredient'));
  update imports.import_staging_rows set action = null, recipe_id = null, level = null,
         ingredient_id = case when v_full then null else ingredient_id end
   where job_id = v_job.id and deleted_at is null and (v_full or kind <> 'ingredient')
     and (action is not null or recipe_id is not null or level is not null or (v_full and ingredient_id is not null));

  if v_full then
    -- Materias primas: código y nombre; existe por código (activa: se reutiliza; dada de baja: error), por
    -- nombre (activa: se reutiliza) o es nueva. Un código o un nombre repetido en el archivo: error en la
    -- repetida (el código repetido se omite si la primera fila sirve).
    with s as (
      select r.*, imports.full_code(v_job.code_prefix, r.source_code) as full_code,
             row_number() over (partition by r.source_code order by r.sheet, r.row_number) as rn_code
        from imports.import_staging_rows r
       where r.job_id = v_job.id and r.deleted_at is null and r.kind = 'ingredient'),
    -- Todas las no borradas, como el índice único de nombres (también las dadas de baja: si el nombre es
    -- de una dada de baja, la fila no se puede crear ni reutilizar).
    names as (
      select distinct on (lower(i.name)) lower(i.name) as name, i.id, i.is_active
        from catalog.ingredients i
       where i.group_id = v_job.group_id and i.deleted_at is null
       order by lower(i.name), i.is_active desc, i.created_at),
    m as (
      select s.*, bc.id as by_code, bc.is_active as code_active, n.id as by_name, n.is_active as name_active,
             row_number() over (partition by imports.norm(s.parsed ->> 'name'), (bc.id is null)
                                order by s.sheet, s.row_number) as rn_name
        from s
        left join catalog.ingredients bc
          on bc.group_id = v_job.group_id and bc.deleted_at is null and bc.code = s.full_code
        left join names n on n.name = imports.norm(s.parsed ->> 'name')),
    c as (
      select m.id, m.group_id, m.job_id, m.sheet, m.row_number,
             case when m.source_code is null or m.full_code !~ '^[A-Z0-9][A-Z0-9-]{1,29}$' then 'bad_code'
                  when length(imports.clean(m.parsed ->> 'name')) not between 1 and 120 then 'missing_name'
                  when m.rn_code > 1 then 'duplicate_code'
                  when m.by_code is not null and not m.code_active then 'inactive'
                  when m.by_code is null and m.by_name is not null and not m.name_active then 'inactive_name'
                  when m.by_code is null and m.by_name is null and m.rn_name > 1 then 'duplicate_name' end as issue,
             coalesce(m.by_code, m.by_name) as match
        from m),
    issues as (
      insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
      select c.group_id, c.job_id, c.id, c.sheet, c.row_number,
             case when c.issue in ('missing_name', 'duplicate_name', 'inactive_name') then 'nombre' else 'código' end, c.issue,
             case c.issue
               when 'bad_code' then 'El código falta o no es válido (letras, números y guiones).'
               when 'missing_name' then 'Falta el nombre (hasta 120 caracteres).'
               when 'duplicate_code' then 'Ese código ya está en otra fila de la solapa: se usa la primera.'
               when 'inactive' then 'Esa materia prima está dada de baja en el sistema: reactivala o cambiá el código.'
               when 'inactive_name' then 'Ya hay una materia prima dada de baja con ese nombre: reactivala o cambiá el nombre.'
               else 'Otra fila tiene el mismo nombre con otro código: unificalas en el Excel.' end
        from c where c.issue is not null)
    update imports.import_staging_rows r
       set action = case when c.issue is null then case when c.match is null then 'create' else 'reuse' end
                         when c.issue = 'duplicate_code' then 'skip' else 'error' end::imports.row_action,
           ingredient_id = case when c.issue is null then c.match end
      from c
     where r.id = c.id;
    -- Un código repetido cuya primera fila no sirve: la repetida tampoco.
    update imports.import_staging_rows d set action = 'error'
     where d.job_id = v_job.id and d.deleted_at is null and d.kind = 'ingredient' and d.action = 'skip'
       and not exists (select 1 from imports.import_staging_rows f
                        where f.job_id = v_job.id and f.deleted_at is null and f.kind = 'ingredient'
                          and f.source_code = d.source_code and f.action in ('create', 'reuse'));
  else
    -- Con las materias primas ya confirmadas: si alguna se dio de baja desde entonces, su fila pasa a error
    -- (y el error se contagia a las líneas que la usan), así la revalidación destraba la confirmación.
    with gone as (
      update imports.import_staging_rows r set action = 'error'
       where r.job_id = v_job.id and r.deleted_at is null and r.kind = 'ingredient' and r.action in ('create', 'reuse')
         and not exists (select 1 from catalog.ingredients i
                          where i.id = r.ingredient_id and i.deleted_at is null and i.is_active)
      returning r.group_id, r.job_id, r.id, r.sheet, r.row_number)
    insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
    select group_id, job_id, id, sheet, row_number, 'código', 'inactive',
           'Esa materia prima se dio de baja después de confirmarla: reactivala o corregí el Excel.'
      from gone;
  end if;

  -- Recetas: código, nombre, que no esté repetida ni choque con una materia prima. Si ya existe una del
  -- grupo o de la marca con ese código, se omite (no se pisa). Si la tiene otra marca, un local, una
  -- variante o está archivada: error, sin decir de quién es.
  with s as (
    select r.*, imports.full_code(v_job.code_prefix, r.source_code) as full_code,
           row_number() over (partition by r.source_code order by r.sheet, r.row_number) as rn
      from imports.import_staging_rows r
     where r.job_id = v_job.id and r.deleted_at is null and r.kind in ('preparation', 'dish')),
  c as (
    select s.id, s.group_id, s.job_id, s.sheet, s.row_number,
           case when s.source_code is null or s.full_code !~ '^[A-Z0-9][A-Z0-9-]{1,29}$' then 'bad_code'
                when length(imports.clean(s.parsed ->> 'name')) not between 1 and 120 then 'missing_name'
                when s.rn > 1 then 'duplicate_code'
                when exists (select 1 from imports.import_staging_rows o
                              where o.job_id = v_job.id and o.deleted_at is null and o.kind = 'ingredient'
                                and o.source_code = s.source_code) then 'ambiguous_code'
                when mine.id is null and exists (select 1 from recipes.recipes x
                                                  where x.group_id = v_job.group_id and x.deleted_at is null
                                                    and x.code = s.full_code) then 'code_taken'
                when (select count(*) from imports.import_staging_rows l
                       where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line'
                         and l.sheet = s.sheet and l.parent_row = s.row_number) > 200 then 'too_many_lines' end as issue,
           mine.id as existing
      from s
      left join imports.brand_recipes(v_job.group_id, v_job.brand_id) mine on mine.code = s.full_code),
  issues as (
    insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
    select c.group_id, c.job_id, c.id, c.sheet, c.row_number,
           case c.issue when 'missing_name' then 'nombre' when 'too_many_lines' then 'componentes' else 'código' end, c.issue,
           case c.issue
             when 'bad_code' then 'El código falta o no es válido (letras, números y guiones).'
             when 'missing_name' then 'Falta el nombre (hasta 120 caracteres).'
             when 'duplicate_code' then 'Esa receta ya está en otro bloque del Excel: se usa el primero.'
             when 'ambiguous_code' then 'Ese código es también de una materia prima: no se sabe a cuál apuntan las líneas.'
             when 'code_taken' then 'Ese código ya lo usa otra receta que esta marca no puede pisar: cambiá el código.'
             else 'Tiene más de 200 componentes.' end
      from c where c.issue is not null)
  update imports.import_staging_rows r
     set action = case when c.issue is null then case when c.existing is null then 'create' else 'skip' end
                       when c.issue = 'duplicate_code' then 'skip' else 'error' end::imports.row_action,
         recipe_id = case when c.issue is null then c.existing end
    from c
   where r.id = c.id;
  update imports.import_staging_rows d set action = 'error'
   where d.job_id = v_job.id and d.deleted_at is null and d.kind in ('preparation', 'dish') and d.action = 'skip'
     and d.recipe_id is null
     and not exists (select 1 from imports.import_staging_rows f
                      where f.job_id = v_job.id and f.deleted_at is null and f.kind in ('preparation', 'dish')
                        and f.source_code = d.source_code and (f.action = 'create' or f.recipe_id is not null));

  -- Líneas: su bloque (la fila de la receta), el componente y los gramos. Un componente sirve si es una
  -- materia prima del archivo que se crea o reutiliza, una receta del archivo que se crea u omite, o una
  -- materia prima o preparación existente que esta marca puede usar (con las reglas del recetario).
  with valid_ing as (
    select distinct on (o.source_code) o.source_code, o.ingredient_id
      from imports.import_staging_rows o
     where o.job_id = v_job.id and o.deleted_at is null and o.kind = 'ingredient' and o.action in ('create', 'reuse')
     order by o.source_code, o.sheet, o.row_number),
  valid_rec as (
    select distinct on (o.source_code) o.source_code, o.recipe_id, o.action
      from imports.import_staging_rows o
     where o.job_id = v_job.id and o.deleted_at is null and o.kind in ('preparation', 'dish')
       and (o.action = 'create' or (o.action = 'skip' and o.recipe_id is not null))
     order by o.source_code, o.sheet, o.row_number),
  in_file as (
    select distinct o.source_code from imports.import_staging_rows o
     where o.job_id = v_job.id and o.deleted_at is null and o.kind in ('ingredient', 'preparation', 'dish')
       and o.source_code is not null),
  mine as (select * from imports.brand_recipes(v_job.group_id, v_job.brand_id)),
  c as (
    select l.id, l.group_id, l.job_id, l.sheet, l.row_number, l.source_code,
           case when p.id is null then 'unknown_parent'
                when p.action is distinct from 'create' then 'parent_not_created'
                when l.source_code is null then 'missing_code'
                when l.source_code = l.parent_code then 'self_reference'
                when coalesce(imports.num(l.parsed ->> 'grams'), 0) <= 0 then 'bad_quantity'
                when vi.source_code is not null then
                  case when vi.ingredient_id is not null
                            and (select b.status from catalog.to_base_quantity(vi.ingredient_id, imports.num(l.parsed ->> 'grams'),
                                                                               catalog.unit_id('g')) b) is distinct from 'ok'
                       then 'unit_mismatch' end
                when vr.source_code is not null then
                  case when vr.action = 'skip'
                            and (select mr.published_unit from mine mr where mr.id = vr.recipe_id) is null
                       then 'not_published'
                       when vr.action = 'skip'
                            and (select u.dimension::text from catalog.units u
                                  where u.id = (select mr.published_unit from mine mr where mr.id = vr.recipe_id))
                                is distinct from 'mass'
                       then 'unit_mismatch' end
                when l.source_code in (select f.source_code from in_file f) then 'broken_component'
                when ei.id is not null then
                  case when not ei.is_active then 'inactive'
                       when (select b.status from catalog.to_base_quantity(ei.id, imports.num(l.parsed ->> 'grams'),
                                                                           catalog.unit_id('g')) b) is distinct from 'ok'
                         then 'unit_mismatch' end
                when er.id is not null then
                  case when er.published_unit is null then 'not_published'
                       when (select u.dimension::text from catalog.units u where u.id = er.published_unit) is distinct from 'mass'
                         then 'unit_mismatch' end
                when exists (select 1 from recipes.recipes x
                              where x.group_id = v_job.group_id and x.deleted_at is null
                                and x.code = imports.full_code(v_job.code_prefix, l.source_code)) then 'out_of_scope'
                else 'unknown_code' end as issue
      from imports.import_staging_rows l
      left join imports.import_staging_rows p
        on p.job_id = l.job_id and p.deleted_at is null and p.sheet = l.sheet and p.row_number = l.parent_row
       and p.kind in ('preparation', 'dish') and p.source_code = l.parent_code
      left join valid_ing vi on vi.source_code = l.source_code
      left join valid_rec vr on vr.source_code = l.source_code and vi.source_code is null
      left join catalog.ingredients ei
        on ei.group_id = v_job.group_id and ei.deleted_at is null and ei.code = imports.full_code(v_job.code_prefix, l.source_code)
      left join mine er on er.code = imports.full_code(v_job.code_prefix, l.source_code)
     where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line'),
  issues as (
    insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
    select c.group_id, c.job_id, c.id, c.sheet, c.row_number,
           case c.issue when 'bad_quantity' then 'gramos' else 'código' end, c.issue,
           case c.issue
             when 'unknown_parent' then 'La línea no pertenece a ninguna receta del Excel.'
             when 'missing_code' then 'Falta el código del ingrediente.'
             when 'self_reference' then 'Una receta no se puede usar a sí misma.'
             when 'bad_quantity' then 'Faltan los gramos, o no son mayores que cero.'
             when 'broken_component' then 'Usa un ingrediente o una preparación del Excel que tiene errores.'
             when 'unit_mismatch' then 'Ese componente no se mide en peso: cargá su conversión a gramos o corregí la línea.'
             when 'inactive' then 'Usa una materia prima dada de baja.'
             when 'not_published' then 'Usa una preparación que todavía no tiene versión vigente.'
             when 'out_of_scope' then 'Usa una receta de otra marca o de un local: esta marca no la puede usar.'
             else format('El código %s no está en INSUMOS ni en los pre-elaborados.', left(c.source_code, 40)) end
      from c where c.issue is not null and c.issue <> 'parent_not_created')
  update imports.import_staging_rows r
     set action = case when c.issue is null then 'create'
                       when c.issue = 'parent_not_created' then 'skip' else 'error' end::imports.row_action
    from c
   where r.id = c.id;

  -- Círculos entre las recetas del archivo.
  with recursive edges as (
    select l.parent_code as parent, l.source_code as child
      from imports.import_staging_rows l
     where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line' and l.action = 'create'
       and exists (select 1 from imports.import_staging_rows p
                    where p.job_id = v_job.id and p.deleted_at is null and p.kind in ('preparation', 'dish')
                      and p.action = 'create' and p.source_code = l.source_code)),
  walk (start, node, depth) as (
    select parent, child, 1 from edges
    union
    select w.start, e.child, w.depth + 1 from walk w join edges e on e.parent = w.node where w.depth < 12),
  cyc as (
    update imports.import_staging_rows s set action = 'error'
      from (select distinct start from walk where node = start) c
     where s.job_id = v_job.id and s.deleted_at is null and s.kind in ('preparation', 'dish') and s.source_code = c.start
       and s.action = 'create'
    returning s.group_id, s.job_id, s.id, s.sheet, s.row_number)
  insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
  select group_id, job_id, id, sheet, row_number, 'código', 'cycle',
         'Esta preparación se usa a sí misma a través de otras: se formaría un círculo.'
    from cyc;

  -- Un error se contagia: la línea que usa una receta del archivo que no se crea ni se omite bien, y la
  -- receta con alguna línea con error. Hasta que no cambie nada.
  loop
    v_round := v_round + 1;
    with broken as (
      update imports.import_staging_rows l set action = 'error'
       where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line' and l.action = 'create'
         and exists (select 1 from imports.import_staging_rows p
                      where p.job_id = v_job.id and p.deleted_at is null and p.kind in ('preparation', 'dish')
                        and p.source_code = l.source_code)
         and not exists (select 1 from imports.import_staging_rows p
                          where p.job_id = v_job.id and p.deleted_at is null and p.kind in ('preparation', 'dish')
                            and p.source_code = l.source_code
                            and (p.action = 'create' or (p.action = 'skip' and p.recipe_id is not null)))
      returning l.group_id, l.job_id, l.id, l.sheet, l.row_number)
    insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
    select group_id, job_id, id, sheet, row_number, 'código', 'broken_component',
           'Usa un ingrediente o una preparación del Excel que tiene errores.'
      from broken;
    get diagnostics v_a = row_count;
    with failed as (
      update imports.import_staging_rows p set action = 'error'
       where p.job_id = v_job.id and p.deleted_at is null and p.kind in ('preparation', 'dish') and p.action = 'create'
         and exists (select 1 from imports.import_staging_rows l
                      where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line'
                        and l.sheet = p.sheet and l.parent_row = p.row_number and l.action = 'error')
      returning p.group_id, p.job_id, p.id, p.sheet, p.row_number)
    insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
    select group_id, job_id, id, sheet, row_number, 'componentes', 'line_errors',
           'Alguna de sus líneas tiene un error: corregila y volvé a subir.'
      from failed;
    get diagnostics v_b = row_count;
    -- Cada vuelta solo pasa filas de "se crea" a "error", así que termina sola; el tope es de seguridad
    -- (una vuelta por receta del archivo alcanza para cualquier cadena).
    exit when v_a + v_b = 0
           or v_round > (select count(*) from imports.import_staging_rows
                          where job_id = v_job.id and deleted_at is null and kind in ('preparation', 'dish'));
  end loop;

  -- Las líneas sin error de una receta que no se crea (con error u omitida) se omiten.
  update imports.import_staging_rows l set action = 'skip'
   where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line' and l.action = 'create'
     and not exists (select 1 from imports.import_staging_rows p
                      where p.job_id = v_job.id and p.deleted_at is null and p.sheet = l.sheet and p.row_number = l.parent_row
                        and p.action = 'create');

  -- Niveles de las recetas que se crean (para crearlas de abajo hacia arriba), contando también los de las
  -- preparaciones existentes que usan. Hasta 10 (mismas reglas que el recetario).
  with recursive edges as (
    select l.parent_code as parent, l.source_code as child
      from imports.import_staging_rows l
     where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line' and l.action = 'create'),
  file_recipes as (
    select o.source_code from imports.import_staging_rows o
     where o.job_id = v_job.id and o.deleted_at is null and o.kind in ('preparation', 'dish') and o.action = 'create'),
  -- Hasta dónde baja una preparación existente que se usa (o una omitida, que ya existe).
  outside as (
    select e.parent, max(recipes.sub_depth(br.id) + 1) as depth
      from edges e
      join imports.brand_recipes(v_job.group_id, v_job.brand_id) br
        on br.code = imports.full_code(v_job.code_prefix, e.child)
     where e.child not in (select source_code from file_recipes)
     group by e.parent),
  walk (start, node, depth) as (
    select f.source_code, f.source_code, 0 from file_recipes f
    union
    select w.start, e.child, w.depth + 1
      from walk w join edges e on e.parent = w.node
     where w.depth < 12 and e.child in (select source_code from file_recipes)),
  depths as (
    select w.start, max(w.depth + coalesce(o.depth, 0)) as depth
      from walk w left join outside o on o.parent = w.node
     group by w.start),
  leveled as (
    update imports.import_staging_rows s set level = least(d.depth, 12)
      from depths d
     where s.job_id = v_job.id and s.deleted_at is null and s.kind in ('preparation', 'dish') and s.action = 'create'
       and s.source_code = d.start
    returning s.group_id, s.job_id, s.id, s.sheet, s.row_number, s.level)
  insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, message)
  select group_id, job_id, id, sheet, row_number, 'componentes', 'too_deep', 'Tiene más de 10 niveles de preparaciones.'
    from leveled where level > 9;
  update imports.import_staging_rows set action = 'error'
   where job_id = v_job.id and deleted_at is null and kind in ('preparation', 'dish') and action = 'create' and level > 9;

  -- Avisos (no frenan): una receta sin componentes queda para completar en la ficha.
  insert into imports.import_errors (group_id, job_id, row_id, sheet, row_number, field, code, severity, message)
  select p.group_id, p.job_id, p.id, p.sheet, p.row_number, 'componentes', 'empty_recipe', 'warning',
         'No tiene componentes en el Excel: queda en borrador para completarla en la ficha.'
    from imports.import_staging_rows p
   where p.job_id = v_job.id and p.deleted_at is null and p.kind in ('preparation', 'dish') and p.action = 'create'
     and not exists (select 1 from imports.import_staging_rows l
                      where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line'
                        and l.sheet = p.sheet and l.parent_row = p.row_number and l.action = 'create');

  if v_full then
    update imports.import_jobs set status = 'validated' where id = v_job.id;
  end if;
  return jsonb_build_object('result', 'applied', 'message', 'Importación validada. Revisá la vista previa antes de confirmar.');
end
$$;
comment on function imports.validate_job(uuid) is
  'Calcula qué pasa con cada fila (se crea, se reutiliza, se omite o tiene error) con las reglas del recetario, y registra los problemas, sin tocar nada oficial. Se puede repetir; con las materias primas ya confirmadas, revalida solo las recetas. Pide imports.run en la marca.';

-- ---------------------------------------------------------------------------
-- 7. Confirmar, en dos pasos. Cada paso vuelve a comprobar lo que pudo cambiar desde la validación.
-- ---------------------------------------------------------------------------
-- Paso 1 (Compras): las materias primas nuevas y sus categorías (rubros).
create function imports.confirm_ingredients(p_job_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job imports.import_jobs := imports.find_job(p_job_id);
  v_bad text;
  v_n   integer;
begin
  if v_job.id is null or not core.has_permission_in_group('catalog.manage', v_job.group_id) then
    return core.deny('imports.confirm_ingredients', 'No tenés permiso para crear materias primas.', null,
                     jsonb_build_object('job_id', p_job_id), v_job.group_id, v_job.brand_id, null);
  end if;
  v_job := imports.lock_job(p_job_id);
  if v_job.status <> 'validated' then
    raise exception 'Las materias primas se confirman con la importación validada (y una sola vez).' using errcode = '23514';
  end if;
  -- Las altas de materias primas del grupo, de a una importación por vez.
  perform pg_advisory_xact_lock(hashtextextended('catalog.ingredients:' || v_job.group_id::text, 0));
  perform core.set_change_context(p_reason, 'import');
  -- Lo que se reutiliza sigue vigente; lo que se crea sigue libre (código y nombre).
  select string_agg(r.sheet || ' fila ' || r.row_number, ', ' order by r.sheet, r.row_number) into v_bad
    from imports.import_staging_rows r
    left join catalog.ingredients i on i.id = r.ingredient_id
   where r.job_id = v_job.id and r.deleted_at is null and r.kind = 'ingredient'
     and ((r.action = 'reuse' and (i.deleted_at is not null or not i.is_active))
          or (r.action = 'create' and exists (select 1 from catalog.ingredients x
                                               where x.group_id = v_job.group_id and x.deleted_at is null
                                                 and (x.code = imports.full_code(v_job.code_prefix, r.source_code)
                                                      or lower(x.name) = imports.norm(r.parsed ->> 'name')))));
  if v_bad is not null then
    perform imports.changed_since_validation(left(v_bad, 200));
  end if;
  -- Los rubros que falten, como categorías del primer nivel (con el mismo corte con el que se comparan).
  insert into catalog.ingredient_categories (group_id, name)
  select distinct on (lower(imports.category_name(r.parsed))) v_job.group_id, imports.category_name(r.parsed)
    from imports.import_staging_rows r
   where r.job_id = v_job.id and r.deleted_at is null and r.kind = 'ingredient' and r.action = 'create'
     and not exists (select 1 from catalog.ingredient_categories c
                      where c.group_id = v_job.group_id and c.parent_id is null and c.deleted_at is null
                        and lower(c.name) = lower(imports.category_name(r.parsed)))
   order by lower(imports.category_name(r.parsed));
  -- Las materias primas nuevas, en gramos (el Excel mide todo en gramos).
  with created as (
    insert into catalog.ingredients (group_id, code, name, category_id, recipe_unit_id, notes)
    select v_job.group_id, imports.full_code(v_job.code_prefix, r.source_code), imports.clean(r.parsed ->> 'name'),
           (select c.id from catalog.ingredient_categories c
             where c.group_id = v_job.group_id and c.parent_id is null and c.deleted_at is null
               and lower(c.name) = lower(imports.category_name(r.parsed))
             order by c.created_at limit 1),
           catalog.unit_id('g'), left(format('Importada del recetario «%s».', v_job.file_name), 500)
      from imports.import_staging_rows r
     where r.job_id = v_job.id and r.deleted_at is null and r.kind = 'ingredient' and r.action = 'create'
    returning id, code)
  update imports.import_staging_rows r set ingredient_id = c.id
    from created c
   where r.job_id = v_job.id and r.deleted_at is null and r.kind = 'ingredient' and r.action = 'create'
     and imports.full_code(v_job.code_prefix, r.source_code) = c.code;
  get diagnostics v_n = row_count;
  update imports.import_jobs
     set status = 'ingredients_confirmed', ingredients_confirmed_by = core.current_actor_id(), ingredients_confirmed_at = now()
   where id = v_job.id;
  return jsonb_build_object('result', 'applied',
                            'message', format('Materias primas confirmadas: %s nuevas. Ahora la cocina confirma las recetas.', v_n));
exception when unique_violation then
  perform imports.changed_since_validation('una materia prima o un rubro ya existe');
end
$$;
comment on function imports.confirm_ingredients(uuid, text) is
  'Paso 1 de la confirmación: crea las materias primas nuevas en gramos (y los rubros que falten) y reutiliza las que ya existen, comprobando que nada haya cambiado. Pide catalog.manage en el grupo (Compras) y un motivo.';

-- Paso 2 (cocina): las recetas, en borrador, de abajo hacia arriba.
create function imports.confirm_recipes(p_job_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job      imports.import_jobs := imports.find_job(p_job_id);
  v_r        imports.import_staging_rows;
  v_recipe   uuid;
  v_version  uuid;
  v_bad      text;
  v_expected integer;
  v_inserted integer;
  v_unit_g   uuid := catalog.unit_id('g');
  v_unit_u   uuid := catalog.unit_id('unit');
  v_n        integer := 0;
begin
  if v_job.id is null or not core.has_permission_in_brand('imports.approve', v_job.brand_id)
     or not core.has_permission_in_brand('recipes.draft', v_job.brand_id) then
    return core.deny('imports.confirm_recipes', 'No tenés permiso para confirmar recetas en esa marca.', null,
                     jsonb_build_object('job_id', p_job_id), v_job.group_id, v_job.brand_id, null);
  end if;
  v_job := imports.lock_job(p_job_id);
  if v_job.status in ('confirmed', 'cancelled') then
    raise exception 'Esta importación ya se confirmó o se canceló.' using errcode = '23514';
  end if;
  if v_job.status in ('uploaded', 'staged') then
    raise exception 'Primero hay que validar la importación.' using errcode = '23514';
  end if;
  if v_job.status = 'validated'
     and exists (select 1 from imports.import_staging_rows
                  where job_id = v_job.id and deleted_at is null and kind = 'ingredient' and action in ('create', 'reuse')) then
    raise exception 'Primero Compras tiene que confirmar las materias primas.' using errcode = '23514';
  end if;
  perform recipes.lock_sub_graph(v_job.group_id);
  perform core.set_change_context(p_reason, 'import');

  -- Nada cambió desde la validación: los códigos nuevos siguen libres y lo que se omite o reutiliza sigue
  -- vigente y al alcance.
  select string_agg(r.sheet || ' fila ' || r.row_number, ', ' order by r.sheet, r.row_number) into v_bad
    from imports.import_staging_rows r
   where r.job_id = v_job.id and r.deleted_at is null
     and ((r.kind in ('preparation', 'dish') and r.action = 'create'
           and exists (select 1 from recipes.recipes x where x.group_id = v_job.group_id and x.deleted_at is null
                          and x.code = imports.full_code(v_job.code_prefix, r.source_code)))
          or (r.kind in ('preparation', 'dish') and r.action = 'skip' and r.recipe_id is not null
              and not exists (select 1 from imports.brand_recipes(v_job.group_id, v_job.brand_id) b where b.id = r.recipe_id))
          or (r.kind = 'ingredient' and r.action in ('create', 'reuse')
              and not exists (select 1 from catalog.ingredients i
                               where i.id = r.ingredient_id and i.deleted_at is null and i.is_active)));
  if v_bad is not null then
    perform imports.changed_since_validation(left(v_bad, 200));
  end if;

  -- Recetas y su versión 1 en borrador, de las más simples a las que usan más preparaciones.
  for v_r in select * from imports.import_staging_rows
              where job_id = v_job.id and deleted_at is null and kind in ('preparation', 'dish') and action = 'create'
              order by level, sheet, row_number loop
    insert into recipes.recipes (group_id, brand_id, scope_type, code, name, recipe_type)
    values (v_job.group_id, v_job.brand_id, 'brand', imports.full_code(v_job.code_prefix, v_r.source_code),
            imports.clean(v_r.parsed ->> 'name'), v_r.kind::text::recipes.recipe_type)
    returning id into v_recipe;
    insert into recipes.recipe_versions (group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions,
                                         portion_grams, change_summary)
    values (v_job.group_id, v_recipe, 1,
            case when v_r.kind = 'preparation' then nullif(imports.num(v_r.parsed ->> 'yield_grams'), 0)
                 else nullif(imports.num(v_r.parsed ->> 'portions'), 0) end,
            case when v_r.kind = 'preparation' and nullif(imports.num(v_r.parsed ->> 'yield_grams'), 0) is not null then v_unit_g
                 when v_r.kind = 'dish' and nullif(imports.num(v_r.parsed ->> 'portions'), 0) is not null then v_unit_u end,
            case when v_r.kind = 'dish' then round(nullif(imports.num(v_r.parsed ->> 'portions'), 0))::integer end,
            case when v_r.kind = 'dish' then nullif(imports.num(v_r.parsed ->> 'portion_grams'), 0) end,
            left(format('Importada del recetario «%s» (%s, fila %s).', v_job.file_name, v_r.sheet, v_r.row_number), 1000))
    returning id into v_version;
    update imports.import_staging_rows set recipe_id = v_recipe where id = v_r.id;
    -- Sus líneas: materia prima en peso de compra; preparación en cantidad terminada. Todo en gramos, y la
    -- medida casera del Excel ("CUP 250", "2 FETAS") como observación. Componente: lo del archivo primero,
    -- y si no, lo existente que la marca puede usar (como en la validación).
    select count(*) into v_expected from imports.import_staging_rows l
     where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line' and l.action = 'create'
       and l.sheet = v_r.sheet and l.parent_row = v_r.row_number;
    with lines as (
      select row_number() over (order by l.row_number) as n,
             imports.num(l.parsed ->> 'grams') as grams,
             left(nullif(imports.clean(l.parsed ->> 'measure'), ''), 500) as notes,
             coalesce(fi.ingredient_id,
                      case when fr.source_code is null then ei.id end) as ingredient_id,
             coalesce(fr.recipe_id, er.id) as sub_recipe_id
        from imports.import_staging_rows l
        left join lateral (select o.ingredient_id from imports.import_staging_rows o
                            where o.job_id = v_job.id and o.deleted_at is null and o.kind = 'ingredient'
                              and o.source_code = l.source_code and o.action in ('create', 'reuse')
                            order by o.sheet, o.row_number limit 1) fi on true
        left join lateral (select o.source_code, o.recipe_id from imports.import_staging_rows o
                            where o.job_id = v_job.id and o.deleted_at is null and o.kind in ('preparation', 'dish')
                              and o.source_code = l.source_code and o.action in ('create', 'skip') and o.recipe_id is not null
                            order by o.sheet, o.row_number limit 1) fr on true
        left join catalog.ingredients ei
          on ei.group_id = v_job.group_id and ei.deleted_at is null and ei.is_active
         and ei.code = imports.full_code(v_job.code_prefix, l.source_code)
        left join imports.brand_recipes(v_job.group_id, v_job.brand_id) er
          on er.code = imports.full_code(v_job.code_prefix, l.source_code) and er.published_unit is not null
       where l.job_id = v_job.id and l.deleted_at is null and l.kind = 'line' and l.action = 'create'
         and l.sheet = v_r.sheet and l.parent_row = v_r.row_number)
    insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, sub_recipe_id, quantity,
                                           unit_id, quantity_basis, notes)
    select v_job.group_id, v_version, x.n, x.ingredient_id, case when x.ingredient_id is null then x.sub_recipe_id end,
           x.grams, v_unit_g, case when x.ingredient_id is null then 'finished' else 'purchase' end::recipes.quantity_basis,
           x.notes
      from lines x
     where x.ingredient_id is not null or x.sub_recipe_id is not null;
    get diagnostics v_inserted = row_count;
    if v_inserted <> v_expected then
      perform imports.changed_since_validation(format('%s, fila %s: un componente ya no está', v_r.sheet, v_r.row_number));
    end if;
    update imports.import_staging_rows set recipe_version_id = v_version
     where job_id = v_job.id and deleted_at is null and kind = 'line' and action = 'create'
       and sheet = v_r.sheet and parent_row = v_r.row_number;
    v_n := v_n + 1;
  end loop;
  update imports.import_jobs set status = 'confirmed', confirmed_by = core.current_actor_id(), confirmed_at = now()
   where id = v_job.id;
  return jsonb_build_object('result', 'applied',
                            'message', format('Recetas importadas en borrador: %s. Completá los pasos y pedí la revisión de cada una.', v_n));
exception when unique_violation then
  perform imports.changed_since_validation('una receta con ese código ya existe');
end
$$;
comment on function imports.confirm_recipes(uuid, text) is
  'Paso 2 de la confirmación: crea las recetas de la marca en borrador (preparaciones primero) con sus líneas en gramos, comprobando que nada haya cambiado. Pide imports.approve y recipes.draft en la marca, y un motivo. Si hay materias primas, antes las tiene que confirmar Compras.';

create function imports.cancel_job(p_job_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job imports.import_jobs := imports.find_job(p_job_id);
begin
  if v_job.id is null or not core.has_permission_in_brand('imports.run', v_job.brand_id) then
    return core.deny('imports.cancel_job', 'No tenés permiso para cancelar esa importación.', null,
                     jsonb_build_object('job_id', p_job_id), v_job.group_id, v_job.brand_id, null);
  end if;
  v_job := imports.lock_job(p_job_id);
  if v_job.status in ('confirmed', 'cancelled') then
    raise exception 'Esta importación ya se confirmó o se canceló.' using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'import');
  update imports.import_jobs set status = 'cancelled' where id = v_job.id;
  return jsonb_build_object('result', 'applied',
                            'message', 'Importación cancelada. Lo que ya se confirmó (materias primas) queda; el archivo se puede volver a subir.');
end
$$;
comment on function imports.cancel_job(uuid, text) is
  'Cancela una importación que no terminó. Lo ya confirmado queda. Pide imports.run en la marca y un motivo.';

-- Totales por tipo de fila y acción (la API devuelve hasta 1.000 filas: se cuenta en la base).
create function imports.job_summary(p_job_id uuid)
returns table (kind imports.row_kind, action imports.row_action, rows bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select s.kind, s.action, count(*)
    from imports.import_staging_rows s
   where s.job_id = p_job_id and s.deleted_at is null
   group by s.kind, s.action
   order by s.kind, s.action
$$;
comment on function imports.job_summary(uuid) is 'Cuántas filas hay de cada tipo y acción en una importación. Respeta RLS.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'imports.create_job(uuid, text, text, text, text, text)',
    'imports.stage_rows(uuid, jsonb)',
    'imports.validate_job(uuid)',
    'imports.confirm_ingredients(uuid, text)',
    'imports.confirm_recipes(uuid, text)',
    'imports.cancel_job(uuid, text)',
    'imports.job_summary(uuid)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
