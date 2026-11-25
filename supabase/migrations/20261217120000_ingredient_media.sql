-- Foto del producto de una materia prima (pedido de Soy, Tanda 2, punto D; ADR-0066). Mismo patrón y mismo bucket privado
-- que las fotos de recetas (ADR-0023), con permisos propios:
--
-- * Una foto vigente por materia prima. Cambiarla da de baja la anterior (queda como historia); nada se borra.
-- * Ruta: <grupo>/ingredients/<materia prima>/<uuid>.jpg|png|webp. La segunda carpeta no es un identificador: las
--   políticas de recetas (que leen ahí la receta) no alcanzan a estos archivos, ni estas a los de recetas.
-- * Sube y cambia quien edita la materia prima (catalog.manage en el grupo). La vigente la ve quien ve la materia prima
--   (catalog.view); lo dado de baja o nunca registrado, solo quien la edita.
-- * Sin políticas de update ni de delete en storage.objects: un archivo subido no se cambia ni se borra.

-- ---------------------------------------------------------------------------
-- 1. Tabla
-- ---------------------------------------------------------------------------
create table catalog.ingredient_media (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null,
  ingredient_id  uuid not null,
  storage_path   text not null,
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint ingredient_media_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  -- El archivo es de esa materia prima y de ese grupo.
  constraint ingredient_media_path_check check (
    storage_path ~ ('^' || group_id::text || '/ingredients/' || ingredient_id::text
                    || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'))
);
-- Una vigente por materia prima, y un archivo se registra una sola vez.
create unique index ingredient_media_current_key on catalog.ingredient_media (ingredient_id) where deleted_at is null;
create unique index ingredient_media_path_key on catalog.ingredient_media (storage_path);
create index ingredient_media_ingredient_idx on catalog.ingredient_media (ingredient_id, group_id);
create index ingredient_media_group_idx on catalog.ingredient_media (group_id);
comment on table catalog.ingredient_media is
  'Foto del producto de cada materia prima. El archivo está en Storage (bucket recipe-media); acá quedan cuál es la vigente y quién la subió. Cambiarla da de baja la anterior; nada se borra.';
comment on column catalog.ingredient_media.id is 'Identificador.';
comment on column catalog.ingredient_media.group_id is 'Grupo de la materia prima.';
comment on column catalog.ingredient_media.ingredient_id is 'Materia prima de la foto.';
comment on column catalog.ingredient_media.storage_path is 'Dónde está el archivo en el bucket recipe-media: <grupo>/ingredients/<materia prima>/<archivo>.';
comment on column catalog.ingredient_media.created_at is 'Cuándo se subió (lo pone la base).';
comment on column catalog.ingredient_media.created_by is 'Quién la subió (lo pone la base).';
comment on column catalog.ingredient_media.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column catalog.ingredient_media.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column catalog.ingredient_media.deleted_at is 'Baja: se cambió por otra o se quitó. El archivo queda en Storage como historia.';
comment on column catalog.ingredient_media.deleted_by is 'Quién la dio de baja (lo pone la base).';

alter table catalog.ingredient_media enable row level security;
revoke all on catalog.ingredient_media from public, anon, authenticated, service_role;

-- Una foto registrada no cambia: solo se da de baja, una vez.
create function catalog.guard_ingredient_media()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una foto no se borra: se da de baja.' using errcode = '42501';
  end if;
  if old.deleted_at is not null
     or (new.id, new.group_id, new.ingredient_id, new.storage_path)
        is distinct from (old.id, old.group_id, old.ingredient_id, old.storage_path) then
    raise exception 'Una foto registrada no cambia: subí una nueva.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function catalog.guard_ingredient_media() is
  'Trigger de catalog.ingredient_media: una foto registrada solo se da de baja (una vez) y nunca se borra.';
revoke execute on function catalog.guard_ingredient_media() from public;
create trigger guard_ingredient_media before update or delete on catalog.ingredient_media
  for each row execute function catalog.guard_ingredient_media();
create trigger set_control_columns before insert or update on catalog.ingredient_media
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on catalog.ingredient_media
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on catalog.ingredient_media
  for each statement execute function core.reject_truncate();

-- La misma regla que catalog.ingredients: si la materia prima se borra, su foto no se ve más.
create policy ingredient_media_select on catalog.ingredient_media for select to authenticated
  using (deleted_at is null and group_id in (select core.visible_group_ids('catalog.view'))
         and exists (select 1 from catalog.ingredients i where i.id = ingredient_id and i.deleted_at is null));
grant select on catalog.ingredient_media to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Permisos en Storage
-- ---------------------------------------------------------------------------
-- La materia prima de un archivo del bucket, si el nombre tiene la forma completa; si no, vacío.
create function catalog.photo_ingredient_id(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case when p_name ~ ('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ingredients/'
                             || '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
                             || '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$')
              then split_part(p_name, '/', 3)::uuid end
$$;
comment on function catalog.photo_ingredient_id(text) is
  'La materia prima de un archivo del bucket recipe-media con la forma <grupo>/ingredients/<materia prima>/<uuid>.jpg|png|webp; vacío si no la tiene.';

-- Subir: quien edita esa materia prima, en la carpeta de su grupo. También si está desactivada: se edita como el resto de
-- su ficha (catalog.save_ingredient_sheet tampoco lo impide).
create function catalog.can_manage_photo(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select split_part(p_name, '/', 1) = i.group_id::text
           and core.has_permission_in_group('catalog.manage', i.group_id)
      from catalog.ingredients i
     where i.id = catalog.photo_ingredient_id(p_name) and i.deleted_at is null), false)
$$;
comment on function catalog.can_manage_photo(text) is
  'Si la sesión puede subir ese archivo como foto de una materia prima: catalog.manage en su grupo y la carpeta correcta.';

-- Archivos vigentes que la sesión puede leer.
create function catalog.visible_photo_paths()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select m.storage_path
    from catalog.ingredient_media m
    join catalog.ingredients i on i.id = m.ingredient_id and i.deleted_at is null
   where m.deleted_at is null and m.group_id in (select core.visible_group_ids('catalog.view'))
$$;
comment on function catalog.visible_photo_paths() is
  'Fotos vigentes de las materias primas que la sesión ve (catalog.view). Para la política de lectura de Storage.';

-- Carpetas cuya historia (lo dado de baja o sin registrar) lee quien edita. De una vez, no un permiso por archivo.
create function catalog.manageable_photo_folders()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select i.group_id::text || '/ingredients/' || i.id::text
    from catalog.ingredients i
   where i.deleted_at is null and i.group_id in (select core.visible_group_ids('catalog.manage'))
     and core.has_permission_in_group('catalog.manage', i.group_id)
$$;
comment on function catalog.manageable_photo_folders() is
  'Carpetas de fotos de las materias primas que la sesión edita (catalog.manage en el grupo). Para la política de lectura de Storage.';

create policy ingredient_media_read on storage.objects for select to authenticated
  using (bucket_id = 'recipe-media'
         and (name in (select catalog.visible_photo_paths())
              or regexp_replace(name, '/[^/]*$', '') in (select catalog.manageable_photo_folders())));
create policy ingredient_media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-media' and catalog.can_manage_photo(name));

-- ---------------------------------------------------------------------------
-- 3. Escritura
-- ---------------------------------------------------------------------------
create function catalog.set_ingredient_photo(p_ingredient_id uuid, p_storage_path text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_i  catalog.ingredients;
  v_id uuid;
begin
  select * into v_i from catalog.ingredients where id = p_ingredient_id and deleted_at is null;
  if v_i.id is null or not core.has_permission_in_group('catalog.manage', v_i.group_id) then
    return core.deny('catalog.set_ingredient_photo', 'No tenés permiso para cambiar la foto de esta materia prima.', null,
                     jsonb_build_object('ingredient_id', p_ingredient_id), v_i.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo del cambio.' using errcode = '22023';
  end if;
  -- El archivo tiene que estar en la carpeta de esta materia prima y ya subido al bucket.
  if catalog.photo_ingredient_id(p_storage_path) is distinct from v_i.id
     or split_part(p_storage_path, '/', 1) <> v_i.group_id::text
     or not exists (select 1 from storage.objects o where o.bucket_id = 'recipe-media' and o.name = p_storage_path) then
    raise exception 'La foto no se subió bien: probá de nuevo.' using errcode = '22023';
  end if;
  -- Dos cambios de la misma foto van de a uno; si mientras tanto se borró la materia prima, no hay qué cambiar.
  perform 1 from catalog.ingredients where id = v_i.id and deleted_at is null for update;
  if not found then
    raise exception 'Esta materia prima ya no está.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  if exists (select 1 from catalog.ingredient_media where storage_path = p_storage_path) then
    raise exception 'Esa foto ya está cargada.' using errcode = '23505';
  end if;
  update catalog.ingredient_media set deleted_at = now() where ingredient_id = v_i.id and deleted_at is null;
  insert into catalog.ingredient_media (group_id, ingredient_id, storage_path)
  values (v_i.group_id, v_i.id, p_storage_path)
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'id', v_id, 'message', 'Foto guardada. La anterior queda en el historial.');
end
$$;
comment on function catalog.set_ingredient_photo(uuid, text, text) is
  'Pone la foto de una materia prima (ya subida al bucket recipe-media en su carpeta) y da de baja la anterior. Pide catalog.manage y un motivo; sin permiso devuelve denied y queda registrado.';

create function catalog.remove_ingredient_photo(p_ingredient_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_i catalog.ingredients;
begin
  select * into v_i from catalog.ingredients where id = p_ingredient_id and deleted_at is null;
  if v_i.id is null or not core.has_permission_in_group('catalog.manage', v_i.group_id) then
    return core.deny('catalog.remove_ingredient_photo', 'No tenés permiso para quitar la foto de esta materia prima.', null,
                     jsonb_build_object('ingredient_id', p_ingredient_id), v_i.group_id);
  end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'Escribí el motivo del cambio.' using errcode = '22023';
  end if;
  perform 1 from catalog.ingredients where id = v_i.id and deleted_at is null for update;
  if not found then
    raise exception 'Esta materia prima ya no está.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredient_media set deleted_at = now() where ingredient_id = v_i.id and deleted_at is null;
  if not found then
    raise exception 'Esta materia prima no tiene foto.' using errcode = '22023';
  end if;
  return jsonb_build_object('result', 'applied', 'message', 'Foto quitada. Queda en el historial.');
end
$$;
comment on function catalog.remove_ingredient_photo(uuid, text) is
  'Da de baja la foto de una materia prima (el archivo queda como historia). Pide catalog.manage y un motivo; sin permiso devuelve denied y queda registrado.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'catalog.photo_ingredient_id(text)',
    'catalog.can_manage_photo(text)',
    'catalog.visible_photo_paths()',
    'catalog.manageable_photo_folders()',
    'catalog.set_ingredient_photo(uuid, text, text)',
    'catalog.remove_ingredient_photo(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
