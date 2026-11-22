-- Constancia de inscripción de ARCA de cada razón social, en PDF (Tanda 1 de las correcciones de Soy, ADR-0061).
--
-- * Bucket privado org-documents, solo PDF y hasta 3,5 MB (como controla la app). Ruta: <grupo>/legal_entities/<razón social>/<uuid>.pdf.
-- * org.legal_entity_documents es solo de inserción: una constancia nueva se suma y vale la última (la de fecha de
--   emisión más reciente). Nada se cambia ni se borra.
-- * Sube quien administra el grupo (org.manage); lee quien ve la razón social.
-- * Regla del indicador (P6 del plan): Al día si la última constancia se emitió hace 12 meses o menos; Vencida
--   (Atención) si hace más; Sin constancia si no hay ninguna. ARCA no les pone vencimiento: es una regla nuestra
--   para que se actualicen una vez por año.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('org-documents', 'org-documents', false, 3670016, array['application/pdf']);

create table org.legal_entity_documents (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null,
  legal_entity_id uuid not null,
  issued_on       date not null,
  storage_path    text not null check (
    storage_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/legal_entities/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$'),
  created_at      timestamptz not null default now(),
  created_by      uuid references core.actors (id) on delete restrict,
  constraint legal_entity_documents_entity_fkey foreign key (legal_entity_id, group_id)
    references org.legal_entities (id, group_id) on delete restrict
);
create unique index legal_entity_documents_path_key on org.legal_entity_documents (storage_path);
create index legal_entity_documents_entity_idx on org.legal_entity_documents (legal_entity_id, group_id, issued_on desc);
comment on table org.legal_entity_documents is
  'Constancias de inscripción de ARCA (PDF) de cada razón social, en el bucket org-documents. Solo de inserción: vale la de fecha de emisión más reciente.';
comment on column org.legal_entity_documents.id is 'Identificador.';
comment on column org.legal_entity_documents.group_id is 'Grupo, el mismo que el de la razón social.';
comment on column org.legal_entity_documents.legal_entity_id is 'Razón social.';
comment on column org.legal_entity_documents.issued_on is 'Fecha de emisión de la constancia, como figura en el PDF.';
comment on column org.legal_entity_documents.storage_path is 'Dónde está el PDF en el bucket: <grupo>/legal_entities/<razón social>/<archivo>.pdf.';
comment on column org.legal_entity_documents.created_at is 'Cuándo se subió (lo pone la base).';
comment on column org.legal_entity_documents.created_by is 'Quién lo subió (lo pone la base).';

create function org.documents_insert_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := core.current_actor_id();
    return new;
  end if;
  raise exception 'Una constancia subida no se cambia ni se borra: subí una nueva.' using errcode = '42501';
end
$$;
comment on function org.documents_insert_only() is
  'Interna: completa quién y cuándo en una constancia nueva y rechaza cualquier cambio o borrado.';
revoke execute on function org.documents_insert_only() from public;
create trigger documents_insert_only before insert or update or delete on org.legal_entity_documents
  for each row execute function org.documents_insert_only();
create trigger log_change after insert on org.legal_entity_documents
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on org.legal_entity_documents
  for each statement execute function core.reject_truncate();

alter table org.legal_entity_documents enable row level security;
revoke all on org.legal_entity_documents from public, anon, authenticated, service_role;
grant select on org.legal_entity_documents to authenticated;
create policy legal_entity_documents_select on org.legal_entity_documents for select to authenticated
  using (org.can_see_legal_entity(legal_entity_id));

-- El grupo y la razón social de un archivo, si el nombre tiene la forma esperada.
create function org.document_parts(p_name text)
returns table (group_id uuid, legal_entity_id uuid)
language sql
immutable
set search_path = ''
as $$
  select split_part(p_name, '/', 1)::uuid, split_part(p_name, '/', 3)::uuid
   where p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/legal_entities/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$'
$$;
comment on function org.document_parts(text) is
  'El grupo y la razón social de un archivo del bucket org-documents (<grupo>/legal_entities/<razón social>/<uuid>.pdf). Vacío si el nombre no tiene esa forma.';
revoke execute on function org.document_parts(text) from public;

-- Sube quien administra todo el grupo de la carpeta, a una razón social vigente de ese grupo.
create function org.can_upload_document(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from org.document_parts(p_name) d
                   join org.legal_entities e on e.id = d.legal_entity_id and e.group_id = d.group_id
                                            and e.deleted_at is null
                  where core.has_permission_in_group('org.manage', d.group_id))
$$;
comment on function org.can_upload_document(text) is
  'Si la sesión puede subir ese archivo: org.manage en el grupo de la carpeta, para una razón social vigente de ese grupo.';
revoke execute on function org.can_upload_document(text) from public;
grant execute on function org.can_upload_document(text) to authenticated;

-- Lee lo registrado de una razón social que ve, o lo que acaba de subir ella misma (antes de registrarlo).
create function org.can_read_document(p_name text, p_owner text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from org.legal_entity_documents d
                  where d.storage_path = p_name and org.can_see_legal_entity(d.legal_entity_id))
      or (p_owner = (select auth.uid())::text and org.can_upload_document(p_name))
$$;
comment on function org.can_read_document(text, text) is
  'Si la sesión puede leer un archivo de org-documents: una constancia registrada de una razón social que ve, o una que acaba de subir ella.';
revoke execute on function org.can_read_document(text, text) from public;
grant execute on function org.can_read_document(text, text) to authenticated;

create policy org_documents_read on storage.objects for select to authenticated
  using (bucket_id = 'org-documents' and org.can_read_document(name, owner_id));
create policy org_documents_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'org-documents' and owner_id = (select auth.uid())::text and org.can_upload_document(name));
-- Sin políticas de update ni de delete: un archivo subido no se cambia ni se borra.

-- Registrar una constancia ya subida.
create function org.add_legal_entity_document(p_legal_entity_id uuid, p_storage_path text, p_issued_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e  org.legal_entities;
  v_id uuid;
begin
  select * into v_e from org.legal_entities where id = p_legal_entity_id and deleted_at is null;
  perform org.require(v_e.id is not null and core.has_permission_in_group('org.manage', v_e.group_id),
                      'subir la constancia de esta razón social');
  if p_issued_on is null or p_issued_on > (now() at time zone 'America/Argentina/Buenos_Aires')::date
     or p_issued_on < date '2000-01-01' then
    raise exception 'Escribí la fecha de emisión de la constancia (no puede ser futura).' using errcode = '22023';
  end if;
  if not exists (select 1 from org.document_parts(p_storage_path) d
                  where d.group_id = v_e.group_id and d.legal_entity_id = v_e.id)
     or not exists (select 1 from storage.objects o
                     where o.bucket_id = 'org-documents' and o.name = p_storage_path
                       and o.owner_id = (select auth.uid())::text) then
    raise exception 'El archivo no está subido en la carpeta de esta razón social.' using errcode = '22023';
  end if;
  if exists (select 1 from org.legal_entity_documents where storage_path = p_storage_path) then
    raise exception 'Esa constancia ya está registrada.' using errcode = '23505';
  end if;
  perform core.set_change_context('Constancia de inscripción de ARCA', 'manual');
  insert into org.legal_entity_documents (group_id, legal_entity_id, issued_on, storage_path)
  values (v_e.group_id, v_e.id, p_issued_on, p_storage_path)
  returning id into v_id;
  return v_id;
end
$$;
comment on function org.add_legal_entity_document(uuid, text, date) is
  'Registra la constancia de ARCA (PDF) ya subida de una razón social, con su fecha de emisión. Subir otra suma una nueva; vale la más reciente. Pide org.manage en el grupo.';
revoke execute on function org.add_legal_entity_document(uuid, text, date) from public;
grant execute on function org.add_legal_entity_document(uuid, text, date) to authenticated;

-- Estado de la constancia: al_dia, vencida o sin_constancia (misma regla que lib/legal-entity.ts).
create function org.document_status(p_issued_on date)
returns text
language sql
stable
set search_path = ''
as $$
  select case when p_issued_on is null then 'missing'
              when p_issued_on >= ((now() at time zone 'America/Argentina/Buenos_Aires')::date - interval '12 months')::date
                then 'current'
              else 'stale' end
$$;
comment on function org.document_status(date) is
  'Estado de una constancia según su fecha de emisión: current (12 meses o menos), stale (más de 12 meses, Atención) o missing (no hay).';
grant execute on function org.document_status(date) to authenticated;
