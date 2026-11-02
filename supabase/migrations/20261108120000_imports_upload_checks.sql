-- Importar el recetario, PR 2 (ADR-0027): el archivo lo sube el navegador y lo lee el servidor con la
-- sesión de quien lo subió. Más los controles de la revisión de seguridad del PR 2.
--
-- 1. Quien sube un Excel lo puede volver a leer, mientras siga importando en esa marca.
--    Vercel acepta hasta 4,5 MB por pedido a una función, y un recetario pesa más (el de Nonnos, 7,3 MB):
--    el navegador sube el archivo directo al bucket y el servidor lo baja de ahí para leerlo, con la
--    sesión de quien importa. Leer su propio archivo no expone nada nuevo. Si deja de importar en la
--    marca, deja de leerlo (revisión de seguridad, menor 1). Los archivos de los demás siguen visibles
--    solo para quien tiene prices.view en el grupo (traen precios). owner_id lo pone la API de Storage.
-- 2. Una importación se registra solo sobre un archivo que subió la misma persona (menor 2).
-- 3. Una carga de filas cortada a mitad de camino no se puede validar (medio 3): la importación guarda
--    cuántas filas tiene el archivo, y pasar a "validada" exige que estén todas.

-- 1. -------------------------------------------------------------------------
drop policy imports_read on storage.objects;
create policy imports_read on storage.objects for select to authenticated
  using (bucket_id = 'imports'
         and ((owner_id = (select auth.uid())::text
               and core.has_permission_in_brand('imports.run', imports.file_brand_id(name)))
              or core.has_permission_in_group('prices.view', imports.file_group_id(name))));

-- Y se sube solo a nombre propio (revisión de base, menor 4): hoy owner_id lo pone Storage y el esquema
-- storage no se expone, pero la base lo exige igual.
drop policy imports_upload on storage.objects;
create policy imports_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'imports'
              and owner_id = (select auth.uid())::text
              and core.has_permission_in_brand('imports.run', imports.file_brand_id(name)));

-- 3. -------------------------------------------------------------------------
alter table imports.import_jobs
  add column expected_rows integer check (expected_rows is null or expected_rows between 1 and 10000);
comment on column imports.import_jobs.expected_rows is
  'Cuántas filas leyó el servidor en el archivo. Para validar tienen que estar todas cargadas (una carga cortada no se confirma). Vacío en las importaciones anteriores.';

create function imports.check_expected_rows()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if new.status = 'validated' and old.status = 'staged' and new.expected_rows is not null then
    select count(*) into v_rows from imports.import_staging_rows where job_id = new.id and deleted_at is null;
    if v_rows <> new.expected_rows then
      raise exception 'La carga de filas no coincide con el archivo (% de %). Cancelá esta importación y subí el archivo de nuevo.',
        v_rows, new.expected_rows using errcode = '23514';
    end if;
  end if;
  return new;
end
$$;
comment on function imports.check_expected_rows() is
  'Rechaza validar una importación con menos (o más) filas cargadas que las que leyó el servidor en el archivo.';
revoke execute on function imports.check_expected_rows() from public;

create trigger check_expected_rows before update of status on imports.import_jobs
  for each row execute function imports.check_expected_rows();

-- 2 y 3. ----------------------------------------------------------------------
drop function imports.create_job(uuid, text, text, text, text, text);
create function imports.create_job(p_brand_id uuid, p_storage_path text, p_file_name text, p_file_sha256 text,
                                   p_code_prefix text, p_reason text, p_expected_rows integer default null)
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
  -- El archivo está en el bucket, es de esa marca y lo subió quien registra la importación.
  if imports.file_brand_id(p_storage_path) is distinct from p_brand_id
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'imports' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
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
  -- La huella la calcula el servidor de la app: avisa a quien sube dos veces el mismo archivo (caso 8),
  -- no es una garantía contra quien llama a la función directo.
  select created_at into v_previous from imports.import_jobs
   where group_id = v_brand.group_id and file_sha256 = lower(p_file_sha256) and status <> 'cancelled' and deleted_at is null;
  if v_previous is not null then
    raise exception 'Este archivo ya se importó el %. Si cambió, subí la versión nueva.',
      to_char(v_previous at time zone 'America/Argentina/Buenos_Aires', 'DD/MM/YYYY') using errcode = '23505';
  end if;
  perform core.set_change_context(p_reason, 'import');
  begin
    insert into imports.import_jobs (group_id, brand_id, code_prefix, file_name, storage_path, file_sha256, expected_rows)
    values (v_brand.group_id, p_brand_id, v_prefix, btrim(p_file_name), p_storage_path, lower(p_file_sha256),
            p_expected_rows)
    returning id into v_id;
  exception
    when unique_violation then
      raise exception 'Este archivo ya se importó.' using errcode = '23505';
    when check_violation or not_null_violation then
      raise exception 'Algún dato del archivo no es válido (nombre, huella o cantidad de filas).' using errcode = '22023';
  end;
  return jsonb_build_object('result', 'applied', 'id', v_id, 'message', 'Archivo recibido. Ahora se leen sus filas.');
end
$$;
comment on function imports.create_job(uuid, text, text, text, text, text, integer) is
  'Registra un archivo que la misma persona subió al bucket imports para una marca, con la cantidad de filas que leyó el servidor. Rechaza el mismo archivo dos veces (caso 8) y un prefijo de otra marca. Pide imports.run en la marca y un motivo.';
revoke execute on function imports.create_job(uuid, text, text, text, text, text, integer) from public;
grant execute on function imports.create_job(uuid, text, text, text, text, text, integer) to authenticated;
