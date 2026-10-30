-- Fotos de las recetas (etapa 2.2 A, PR 3; ADR-0023). Documento de Soy, sección 14: fotos de producto
-- final, emplatado, materia prima, pasos y puntos críticos, con los mismos permisos que la receta.
--
-- - Las fotos son parte de la versión, como los componentes y los pasos: se agregan o se quitan en un
--   borrador, viajan con la revisión ("presentación o fotos: revisión del chef", sección 14) y la
--   cocina ve solo las de la versión vigente. Una versión nueva copia las fotos de la anterior.
-- - Los archivos van en un bucket privado de Supabase Storage, en carpetas <grupo>/<receta>/<archivo>.
--   Lee un archivo quien trabaja la receta, o quien ve una versión que lo tiene registrado y vigente.
--   Sube quien escribe la receta (recipes.draft), en su carpeta.
-- - Nada se borra: una foto se da de baja en su borrador y el archivo queda como historia. Por eso
--   storage.objects no tiene políticas de update ni de delete.
-- - Las imágenes llegan achicadas desde el navegador (hasta 1.600 px, JPEG); el bucket solo acepta
--   imágenes de hasta 3 MB, y la acción del servidor controla el contenido real del archivo.

-- ---------------------------------------------------------------------------
-- 1. Bucket
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('recipe-media', 'recipe-media', false, 3145728, array['image/jpeg', 'image/png', 'image/webp']);

-- ---------------------------------------------------------------------------
-- 2. Tabla
-- ---------------------------------------------------------------------------
create type recipes.media_kind as enum ('final_product', 'plating', 'raw_material', 'step', 'critical_point',
                                        'correct_example', 'incorrect_example');
comment on type recipes.media_kind is
  'Tipo de foto: producto final, emplatado, materia prima, paso, punto crítico, ejemplo correcto o ejemplo incorrecto.';

create table recipes.recipe_media (
  id                 uuid primary key default gen_random_uuid(),
  group_id           uuid not null,
  brand_id           uuid,
  restaurant_id      uuid,
  recipe_id          uuid not null,
  recipe_version_id  uuid not null,
  kind               recipes.media_kind not null,
  storage_path       text not null check (storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'),
  description        text check (description is null or length(btrim(description)) between 1 and 300),
  created_at         timestamptz not null default now(),
  created_by         uuid references core.actors (id) on delete restrict,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references core.actors (id) on delete restrict,
  deleted_at         timestamptz,
  deleted_by         uuid references core.actors (id) on delete restrict,
  constraint recipe_media_recipe_fkey foreign key (recipe_id, group_id)
    references recipes.recipes (id, group_id) on delete restrict,
  constraint recipe_media_version_fkey foreign key (recipe_version_id, recipe_id)
    references recipes.recipe_versions (id, recipe_id) on delete restrict
);
-- Un archivo aparece una vez por versión (una versión nueva lo vuelve a registrar al copiarlo).
create unique index recipe_media_version_path_key on recipes.recipe_media (recipe_version_id, storage_path)
  where deleted_at is null;
create index recipe_media_group_idx on recipes.recipe_media (group_id);
create index recipe_media_recipe_idx on recipes.recipe_media (recipe_id, group_id);
create index recipe_media_version_idx on recipes.recipe_media (recipe_version_id, recipe_id) where deleted_at is null;
create index recipe_media_path_idx on recipes.recipe_media (storage_path) where deleted_at is null;
comment on table recipes.recipe_media is
  'Fotos de una versión de receta. El archivo está en Storage (bucket recipe-media); acá quedan qué muestra, de qué versión y quién la subió. Solo cambian en un borrador; nada se borra: se da de baja.';
comment on column recipes.recipe_media.id is 'Identificador de la foto en esa versión.';
comment on column recipes.recipe_media.group_id is 'Grupo de la receta.';
comment on column recipes.recipe_media.brand_id is 'Marca de la receta (la copia la base): sirve para la auditoría por alcance.';
comment on column recipes.recipe_media.restaurant_id is 'Local de la receta, si es de un local (lo copia la base).';
comment on column recipes.recipe_media.recipe_id is 'Receta de la foto.';
comment on column recipes.recipe_media.recipe_version_id is 'Versión a la que pertenece. La cocina ve solo las fotos de la versión vigente.';
comment on column recipes.recipe_media.kind is 'Qué muestra: producto final, emplatado, materia prima, paso, punto crítico o un ejemplo.';
comment on column recipes.recipe_media.storage_path is 'Dónde está el archivo en el bucket recipe-media: <grupo>/<receta>/<archivo>.';
comment on column recipes.recipe_media.description is 'Qué se ve en la foto.';
comment on column recipes.recipe_media.created_at is 'Cuándo se agregó a la versión (lo pone la base).';
comment on column recipes.recipe_media.created_by is 'Quién la agregó (lo pone la base).';
comment on column recipes.recipe_media.updated_at is 'Cuándo se cambió por última vez (lo pone la base).';
comment on column recipes.recipe_media.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column recipes.recipe_media.deleted_at is 'Baja de la foto en el borrador. El archivo queda en Storage como historia.';
comment on column recipes.recipe_media.deleted_by is 'Quién la dio de baja (lo pone la base).';

-- La marca y el local los copia la base desde la receta, como en las versiones.
create or replace function recipes.inherit_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name in ('recipe_versions', 'recipe_media') then
    select r.brand_id, r.restaurant_id into new.brand_id, new.restaurant_id from recipes.recipes r where r.id = new.recipe_id;
  elsif tg_table_name in ('recipe_components', 'recipe_steps') then
    select v.brand_id, v.restaurant_id into new.brand_id, new.restaurant_id
      from recipes.recipe_versions v where v.id = new.recipe_version_id;
  else
    select s.brand_id, s.restaurant_id into new.brand_id, new.restaurant_id from recipes.recipe_steps s where s.id = new.step_id;
  end if;
  return new;
end
$$;
comment on function recipes.inherit_scope() is
  'Trigger (BEFORE INSERT OR UPDATE) de recipe_versions, recipe_components, recipe_steps, recipe_step_dependencies y recipe_media: copia la marca y el local de la receta.';

alter table recipes.recipe_media enable row level security;
revoke all on recipes.recipe_media from public, anon, authenticated, service_role;
create trigger inherit_scope before insert or update on recipes.recipe_media
  for each row execute function recipes.inherit_scope();
-- Como las líneas: solo cambian mientras su versión es borrador, y nunca se borran.
create trigger enforce_draft_lines before insert or update or delete on recipes.recipe_media
  for each row execute function recipes.enforce_draft_lines();
create trigger set_control_columns before insert or update on recipes.recipe_media
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on recipes.recipe_media
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on recipes.recipe_media
  for each statement execute function core.reject_truncate();

-- Quien solo ve, ve las fotos de la vigente; quien trabaja la receta, las de todas sus versiones.
create policy recipe_media_select on recipes.recipe_media for select to authenticated
  using (deleted_at is null and recipe_version_id in (select recipes.visible_version_ids()));
grant select on recipes.recipe_media to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Permisos en Storage
-- ---------------------------------------------------------------------------
-- La receta de un archivo del bucket, si el nombre tiene la forma <grupo>/<receta>/<archivo>.
create function recipes.media_recipe_id(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case when split_part(p_name, '/', 2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 2)::uuid end
$$;
comment on function recipes.media_recipe_id(text) is
  'La receta de un archivo del bucket recipe-media (segunda carpeta del nombre), o vacío si el nombre no tiene la forma esperada.';

-- Archivos que la sesión puede leer sin trabajar la receta: los registrados y vigentes en una versión
-- que ve (la vigente). Lo dado de baja o nunca registrado no lo ve (revisión de seguridad, M1).
create function recipes.visible_media_paths()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select m.storage_path
    from recipes.recipe_media m
   where m.deleted_at is null and m.recipe_version_id in (select recipes.visible_version_ids())
$$;
comment on function recipes.visible_media_paths() is
  'Archivos del bucket recipe-media registrados y vigentes en una versión que la sesión ve. Para la política de lectura de Storage.';

-- Subir: quien escribe la receta (recipes.draft en su alcance), en la carpeta de su grupo y su receta,
-- con un nombre de archivo nuevo (<uuid>.jpg|png|webp) y la receta activa.
create function recipes.can_upload_media(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select r.is_active
           and split_part(p_name, '/', 1) = r.group_id::text
           and p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$'
           and recipes.allowed('recipes.draft', r.group_id, r.brand_id, r.restaurant_id)
      from recipes.recipes r
     where r.id = recipes.media_recipe_id(p_name) and r.deleted_at is null), false)
$$;
comment on function recipes.can_upload_media(text) is
  'Si la sesión puede subir ese archivo: recipes.draft en la receta, carpeta <grupo>/<receta>/ correcta, nombre <uuid>.jpg|png|webp y receta activa.';

create policy recipe_media_read on storage.objects for select to authenticated
  using (bucket_id = 'recipe-media'
         and (recipes.media_recipe_id(name) in (select recipes.workable_recipe_ids())
              or name in (select recipes.visible_media_paths())));
create policy recipe_media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-media' and recipes.can_upload_media(name));
-- Sin políticas de update ni de delete: un archivo subido no se cambia ni se borra.

-- ---------------------------------------------------------------------------
-- 4. Escritura
-- ---------------------------------------------------------------------------
-- Agregar una foto al borrador abierto (las fotos se revisan con la versión).
create function recipes.add_media(p_recipe_id uuid, p_storage_path text, p_kind recipes.media_kind,
                                  p_description text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r          recipes.recipes;
  v_draft      recipes.recipe_versions;
  v_id         uuid;
  v_constraint text;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for share;
  if not found or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.add_media', 'No tenés permiso para agregar fotos a esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  select * into v_draft from recipes.recipe_versions where recipe_id = v_r.id and status in ('draft', 'in_review');
  if v_draft.id is null then
    raise exception 'Las fotos van con una versión: creá una versión nueva para agregarlas.' using errcode = '23514';
  end if;
  v_draft := recipes.open_draft(v_draft.id, null);
  if p_kind is null then
    raise exception 'Elegí qué muestra la foto.' using errcode = '22023';
  end if;
  -- El archivo tiene que estar en la carpeta de la receta y ya subido al bucket.
  if p_storage_path is null or split_part(p_storage_path, '/', 1) <> v_r.group_id::text
     or recipes.media_recipe_id(p_storage_path) is distinct from v_r.id
     or not exists (select 1 from storage.objects o where o.bucket_id = 'recipe-media' and o.name = p_storage_path) then
    raise exception 'La foto no se subió bien: probá de nuevo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipe_media (group_id, recipe_id, recipe_version_id, kind, storage_path, description)
  values (v_r.group_id, v_r.id, v_draft.id, p_kind, p_storage_path, nullif(btrim(p_description), ''))
  returning id into v_id;
  return jsonb_build_object('result', 'applied', 'id', v_id,
                            'message', 'Foto agregada al borrador. La cocina la ve cuando se publique la versión.');
exception when unique_violation or check_violation then
  -- Solo se traducen las restricciones de la tabla; los mensajes propios (sin restricción) pasan tal cual.
  get stacked diagnostics v_constraint = constraint_name;
  if v_constraint = 'recipe_media_version_path_key' then
    raise exception 'Esa foto ya está cargada.' using errcode = '23505';
  elsif v_constraint like 'recipe_media_%_check' then
    raise exception 'La descripción va hasta 300 caracteres, y la foto tiene que ser JPG, PNG o WebP.' using errcode = '23514';
  end if;
  raise;
end
$$;
comment on function recipes.add_media(uuid, text, recipes.media_kind, text, text) is
  'Agrega al borrador abierto una foto ya subida al bucket recipe-media en la carpeta de la receta. Pide recipes.draft y un motivo; sin permiso devuelve denied y queda registrado.';

-- Quitar una foto del borrador (la de la versión vigente se quita creando una versión nueva).
create function recipes.remove_media(p_media_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m recipes.recipe_media;
begin
  select * into v_m from recipes.recipe_media where id = p_media_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.draft', v_m.group_id, v_m.brand_id, v_m.restaurant_id) then
    return core.deny('recipes.remove_media', 'No tenés permiso para quitar fotos de esa receta.', null,
                     jsonb_build_object('media_id', p_media_id), v_m.group_id, v_m.brand_id, v_m.restaurant_id);
  end if;
  -- Solo en un borrador de una receta activa (open_draft lo controla y reabre una revisión rechazada).
  perform recipes.open_draft(v_m.recipe_version_id, null);
  perform core.set_change_context(p_reason, 'manual');
  update recipes.recipe_media set deleted_at = now() where id = p_media_id;
  return jsonb_build_object('result', 'applied', 'message', 'Foto quitada del borrador. Queda en el historial.');
end
$$;
comment on function recipes.remove_media(uuid, text) is
  'Da de baja una foto de un borrador (el archivo queda como historia). Pide recipes.draft y un motivo.';

-- Una versión nueva copia también las fotos de la anterior (mismo archivo, registrado en la nueva).
create or replace function recipes.new_version(p_recipe_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_r      recipes.recipes;
  v_base   recipes.recipe_versions;
  v_id     uuid;
  v_open   uuid;
begin
  select * into v_r from recipes.recipes where id = p_recipe_id and deleted_at is null for update;
  if not found or not recipes.allowed('recipes.draft', v_r.group_id, v_r.brand_id, v_r.restaurant_id) then
    return core.deny('recipes.new_version', 'No tenés permiso para crear versiones de esa receta.', null,
                     jsonb_build_object('recipe_id', p_recipe_id), v_r.group_id, v_r.brand_id, v_r.restaurant_id);
  end if;
  if not v_r.is_active then
    raise exception 'La receta está archivada.' using errcode = '23514';
  end if;
  select id into v_open from recipes.recipe_versions where recipe_id = p_recipe_id and status in ('draft', 'in_review');
  if v_open is not null then
    raise exception 'Ya hay una versión en borrador o en revisión: seguí con esa.' using errcode = '23505';
  end if;
  -- La base es la vigente; si no hay, la última.
  select * into v_base from recipes.recipe_versions
   where recipe_id = p_recipe_id order by (status = 'published') desc, version_number desc limit 1;
  perform core.set_change_context(p_reason, 'manual');
  insert into recipes.recipe_versions (group_id, recipe_id, version_number, previous_version_id, yield_quantity,
                                       yield_unit_id, portions, portion_grams, description, storage_notes,
                                       presentation_notes)
  select v_r.group_id, p_recipe_id, (select max(version_number) + 1 from recipes.recipe_versions where recipe_id = p_recipe_id),
         v_base.id, v_base.yield_quantity, v_base.yield_unit_id, v_base.portions, v_base.portion_grams, v_base.description,
         v_base.storage_notes, v_base.presentation_notes
  returning id into v_id;
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id,
                                         quantity_basis, yield_profile_id, no_scale, notes)
  select group_id, v_id, line_order, ingredient_id, quantity, unit_id, quantity_basis, yield_profile_id, no_scale, notes
    from recipes.recipe_components where recipe_version_id = v_base.id and deleted_at is null;
  insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes,
                                    passive_minutes, workers, sector, equipment, control_point)
  select group_id, v_id, step_number, kind, instructions, active_minutes, passive_minutes, workers, sector, equipment,
         control_point
    from recipes.recipe_steps where recipe_version_id = v_base.id and deleted_at is null;
  -- Las dependencias se copian por número de paso.
  insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
  select v_r.group_id, ns.id, nd.id
    from recipes.recipe_step_dependencies d
    join recipes.recipe_steps os on os.id = d.step_id
    join recipes.recipe_steps od on od.id = d.depends_on_step_id
    join recipes.recipe_steps ns on ns.recipe_version_id = v_id and ns.step_number = os.step_number and ns.deleted_at is null
    join recipes.recipe_steps nd on nd.recipe_version_id = v_id and nd.step_number = od.step_number and nd.deleted_at is null
   where os.recipe_version_id = v_base.id and d.deleted_at is null;
  insert into recipes.recipe_media (group_id, recipe_id, recipe_version_id, kind, storage_path, description)
  select group_id, recipe_id, v_id, kind, storage_path, description
    from recipes.recipe_media where recipe_version_id = v_base.id and deleted_at is null;
  return jsonb_build_object('result', 'applied', 'id', v_id,
                            'message', 'Versión nueva en borrador. La vigente sigue igual hasta que se publique esta.');
end
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'recipes.media_recipe_id(text)',
    'recipes.visible_media_paths()',
    'recipes.can_upload_media(text)',
    'recipes.add_media(uuid, text, recipes.media_kind, text, text)',
    'recipes.remove_media(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
