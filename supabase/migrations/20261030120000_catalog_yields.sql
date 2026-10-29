-- Fase 2 · Etapa 2.1 B: rendimientos (docs/fases/fase-2-recetario.md, sección 9; ADR-0021).
--   1. Procesos, perfiles de rendimiento (el estándar, inmutable y con aprobación) y ensayos (solo
--      inserción). Un ensayo nunca cambia el estándar: el estándar cambia solo con aprobación.
--   2. El estándar vale para todo el grupo: lo propone quien tenga yields.record en algún lugar del
--      grupo y lo aprueba otra persona con yields.approve para todo el grupo (decisión de Joaco).
--   3. Las funciones que aplican aprobaciones pueden ser también de catalog (check_apply_function).
--   4. Lectura para el motor (standard_yield: sin estándar es "no definido", nunca 100 %) y para la
--      pantalla (yield_summary: estándar, promedio de ensayos y diferencia).

-- ---------------------------------------------------------------------------
-- 1. Tablas
-- ---------------------------------------------------------------------------
create type catalog.yield_status as enum ('draft', 'approved', 'superseded');
comment on type catalog.yield_status is
  'Estado de un perfil de rendimiento: draft (propuesto, esperando aprobación), approved (el estándar vigente) o superseded (reemplazado por otro aprobado).';

create table catalog.yield_processes (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references org.groups (id) on delete restrict,
  code        text not null check (code ~ '^[A-Z0-9][A-Z0-9-]{1,29}$'),
  name        text not null check (length(btrim(name)) between 1 and 80),
  created_at  timestamptz not null default now(),
  created_by  uuid references core.actors (id) on delete restrict,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references core.actors (id) on delete restrict,
  deleted_at  timestamptz,
  deleted_by  uuid references core.actors (id) on delete restrict,
  constraint yield_processes_id_group_key unique (id, group_id)
);
create index yield_processes_group_idx on catalog.yield_processes (group_id);
create unique index yield_processes_code_key on catalog.yield_processes (group_id, code) where deleted_at is null;
create unique index yield_processes_name_key on catalog.yield_processes (group_id, lower(name)) where deleted_at is null;
comment on table catalog.yield_processes is 'Procesos que cambian el peso de una materia prima: pelado, desgrasado, deshuesado, hervido…';
comment on column catalog.yield_processes.group_id is 'Grupo al que pertenece.';
comment on column catalog.yield_processes.code is 'Código único dentro del grupo (en mayúsculas).';
comment on column catalog.yield_processes.name is 'Nombre del proceso. Único dentro del grupo entre los vigentes.';

create table catalog.ingredient_yield_profiles (
  id                   uuid primary key default gen_random_uuid(),
  group_id             uuid not null references org.groups (id) on delete restrict,
  ingredient_id        uuid not null,
  process_id           uuid not null,
  cut                  text check (cut is null or length(btrim(cut)) between 1 and 80),
  supplier_id          uuid,
  cleaning_yield       numeric(7,4) not null check (cleaning_yield > 0 and cleaning_yield <= 1),
  cooking_factor       numeric(7,4) not null check (cooking_factor > 0 and cooking_factor <= 10),
  method               text check (method is null or length(btrim(method)) between 1 and 500),
  declared_no_loss     boolean not null default false,
  status               catalog.yield_status not null default 'draft',
  approval_request_id  uuid references workflow.approval_requests (id) on delete restrict,
  approved_by          uuid references core.actors (id) on delete restrict,
  approved_at          timestamptz,
  notes                text check (notes is null or length(notes) <= 1000),
  created_at           timestamptz not null default now(),
  created_by           uuid references core.actors (id) on delete restrict,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references core.actors (id) on delete restrict,
  deleted_at           timestamptz,
  deleted_by           uuid references core.actors (id) on delete restrict,
  constraint ingredient_yield_profiles_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint ingredient_yield_profiles_process_fkey foreign key (process_id, group_id)
    references catalog.yield_processes (id, group_id) on delete restrict,
  constraint ingredient_yield_profiles_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  -- 100 % de limpieza y sin cambio en la cocción solo si alguien lo declara "sin merma" (sección 9).
  constraint ingredient_yield_profiles_no_loss_declared
    check (not (cleaning_yield = 1 and cooking_factor = 1) or declared_no_loss),
  constraint ingredient_yield_profiles_approval_consistent
    check ((status = 'draft') = (approved_at is null) and (approved_at is null) = (approved_by is null))
);
create index ingredient_yield_profiles_group_idx on catalog.ingredient_yield_profiles (group_id);
create index ingredient_yield_profiles_ingredient_idx on catalog.ingredient_yield_profiles (ingredient_id, group_id);
create index ingredient_yield_profiles_process_idx on catalog.ingredient_yield_profiles (process_id, group_id);
create index ingredient_yield_profiles_supplier_idx on catalog.ingredient_yield_profiles (supplier_id, group_id);
create index ingredient_yield_profiles_request_idx on catalog.ingredient_yield_profiles (approval_request_id);
create index ingredient_yield_profiles_approved_by_idx on catalog.ingredient_yield_profiles (approved_by);
-- Un solo estándar vigente por ingrediente, proceso, corte y proveedor.
create unique index ingredient_yield_profiles_approved_key on catalog.ingredient_yield_profiles
  (ingredient_id, process_id, coalesce(lower(cut), ''), coalesce(supplier_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where status = 'approved' and deleted_at is null;
comment on table catalog.ingredient_yield_profiles is
  'Rendimiento estándar de una materia prima según el proceso (sección 9). Es el que usa el motor de costos. Inmutable: corregirlo es proponer otro, que pasa por aprobación.';
comment on column catalog.ingredient_yield_profiles.group_id is 'Grupo al que pertenece. El mismo que el del ingrediente.';
comment on column catalog.ingredient_yield_profiles.ingredient_id is 'Materia prima.';
comment on column catalog.ingredient_yield_profiles.process_id is 'Proceso (pelado, hervido…).';
comment on column catalog.ingredient_yield_profiles.cut is 'Corte o presentación, si cambia el rendimiento (por ejemplo, "en cubos").';
comment on column catalog.ingredient_yield_profiles.supplier_id is 'Proveedor, solo si el rendimiento depende de él. Vacío = vale para todos.';
comment on column catalog.ingredient_yield_profiles.cleaning_yield is
  'Rendimiento de limpieza: peso comestible / peso bruto, entre 0 y 1 (4 decimales). 1 si el proceso no limpia.';
comment on column catalog.ingredient_yield_profiles.cooking_factor is
  'Factor de cocción: peso después / peso antes. Menor a 1 si pierde peso (merma de cocción); mayor a 1 si hidrata (pasta, arroz). 1 si no hay cocción.';
comment on column catalog.ingredient_yield_profiles.method is 'Cómo se mide o se llegó al valor.';
comment on column catalog.ingredient_yield_profiles.declared_no_loss is
  'Declarado "sin merma": obligatorio para usar 100 % de limpieza sin cambio en la cocción. La firma es la aprobación.';
comment on column catalog.ingredient_yield_profiles.status is 'Propuesto, estándar vigente o reemplazado.';
comment on column catalog.ingredient_yield_profiles.approval_request_id is 'Solicitud de aprobación con la que se propuso.';
comment on column catalog.ingredient_yield_profiles.approved_by is 'Quién lo aprobó (no puede ser quien lo propuso).';
comment on column catalog.ingredient_yield_profiles.approved_at is 'Cuándo se aprobó.';
comment on column catalog.ingredient_yield_profiles.notes is 'Observaciones.';

create table catalog.ingredient_yield_tests (
  id                     uuid primary key default gen_random_uuid(),
  group_id               uuid not null references org.groups (id) on delete restrict,
  ingredient_id          uuid not null,
  process_id             uuid not null,
  cut                    text check (cut is null or length(btrim(cut)) between 1 and 80),
  supplier_id            uuid,
  restaurant_id          uuid not null,
  tested_on              date not null,
  samples                integer not null default 1 check (samples between 1 and 1000),
  gross_weight           numeric(18,6) check (gross_weight > 0),
  clean_weight           numeric(18,6) check (clean_weight > 0),
  before_cooking_weight  numeric(18,6) check (before_cooking_weight > 0),
  after_cooking_weight   numeric(18,6) check (after_cooking_weight > 0),
  discard_weight         numeric(18,6) check (discard_weight >= 0),
  responsible            text check (responsible is null or length(btrim(responsible)) between 1 and 120),
  notes                  text check (notes is null or length(notes) <= 1000),
  created_at             timestamptz not null default now(),
  created_by             uuid default core.current_actor_id() references core.actors (id) on delete restrict,
  constraint ingredient_yield_tests_ingredient_fkey foreign key (ingredient_id, group_id)
    references catalog.ingredients (id, group_id) on delete restrict,
  constraint ingredient_yield_tests_process_fkey foreign key (process_id, group_id)
    references catalog.yield_processes (id, group_id) on delete restrict,
  constraint ingredient_yield_tests_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint ingredient_yield_tests_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  -- Al menos un par completo: bruto y limpio, o antes y después de la cocción.
  constraint ingredient_yield_tests_has_measure check (
    (gross_weight is not null and clean_weight is not null)
    or (before_cooking_weight is not null and after_cooking_weight is not null)),
  constraint ingredient_yield_tests_pairs check (
    (gross_weight is null) = (clean_weight is null)
    and (before_cooking_weight is null) = (after_cooking_weight is null)),
  constraint ingredient_yield_tests_clean_le_gross check (clean_weight is null or clean_weight <= gross_weight)
);
create index ingredient_yield_tests_group_idx on catalog.ingredient_yield_tests (group_id);
create index ingredient_yield_tests_ingredient_idx on catalog.ingredient_yield_tests (ingredient_id, group_id, tested_on desc);
create index ingredient_yield_tests_process_idx on catalog.ingredient_yield_tests (process_id, group_id);
create index ingredient_yield_tests_supplier_idx on catalog.ingredient_yield_tests (supplier_id, group_id);
create index ingredient_yield_tests_restaurant_idx on catalog.ingredient_yield_tests (restaurant_id, group_id);
create index ingredient_yield_tests_created_by_idx on catalog.ingredient_yield_tests (created_by);
comment on table catalog.ingredient_yield_tests is
  'Ensayos de rendimiento: lo que se midió en una cocina. Solo inserción. Nunca cambian el estándar: la pantalla muestra la diferencia y el estándar se cambia con una propuesta aprobada.';
comment on column catalog.ingredient_yield_tests.id is 'Identificador.';
comment on column catalog.ingredient_yield_tests.group_id is 'Grupo al que pertenece. El mismo que el del ingrediente y el del local.';
comment on column catalog.ingredient_yield_tests.ingredient_id is 'Materia prima.';
comment on column catalog.ingredient_yield_tests.process_id is 'Proceso que se midió.';
comment on column catalog.ingredient_yield_tests.cut is 'Corte o presentación, si corresponde.';
comment on column catalog.ingredient_yield_tests.supplier_id is 'Proveedor de la mercadería medida, si se conoce.';
comment on column catalog.ingredient_yield_tests.restaurant_id is 'Local donde se midió.';
comment on column catalog.ingredient_yield_tests.tested_on is 'Fecha de la medición.';
comment on column catalog.ingredient_yield_tests.samples is 'Cuántas muestras o tandas se pesaron.';
comment on column catalog.ingredient_yield_tests.gross_weight is 'Peso bruto, en gramos (antes de limpiar).';
comment on column catalog.ingredient_yield_tests.clean_weight is 'Peso limpio o comestible, en gramos.';
comment on column catalog.ingredient_yield_tests.before_cooking_weight is 'Peso antes de cocinar, en gramos.';
comment on column catalog.ingredient_yield_tests.after_cooking_weight is 'Peso después de cocinar, en gramos.';
comment on column catalog.ingredient_yield_tests.discard_weight is 'Descarte pesado aparte, en gramos (informativo).';
comment on column catalog.ingredient_yield_tests.responsible is 'Quién hizo la medición (puede no ser una persona del sistema).';
comment on column catalog.ingredient_yield_tests.notes is 'Observaciones.';
comment on column catalog.ingredient_yield_tests.created_at is 'Cuándo se registró (lo pone la base).';
comment on column catalog.ingredient_yield_tests.created_by is 'Quién lo registró (lo pone la base).';

-- ---------------------------------------------------------------------------
-- 2. Reglas: perfiles inmutables, ensayos solo inserción
-- ---------------------------------------------------------------------------
create function catalog.enforce_yield_profile_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Solo sin una persona en la sesión (el seed y las migraciones) nace aprobado. El origen del
    -- cambio (set_change_context) es informativo y nunca decide permisos.
    if new.status <> 'draft' and core.current_actor_id() is not null then
      raise exception 'Un rendimiento estándar nace como propuesta y se aprueba con una solicitud.' using errcode = '42501';
    end if;
    return new;
  end if;
  -- Los valores no cambian nunca: corregir es proponer otro perfil. Tampoco se borra: no hay baja
  -- de un estándar (si hiciera falta, llega con su propia aprobación).
  if (to_jsonb(new) - array['status', 'approved_by', 'approved_at', 'approval_request_id', 'updated_at', 'updated_by'])
     is distinct from
     (to_jsonb(old) - array['status', 'approved_by', 'approved_at', 'approval_request_id', 'updated_at', 'updated_by']) then
    raise exception 'Un rendimiento no se edita: se propone uno nuevo, que pasa por aprobación.' using errcode = '42501';
  end if;
  if new.approval_request_id is distinct from old.approval_request_id and old.approval_request_id is not null then
    raise exception 'La solicitud de un rendimiento no cambia.' using errcode = '42501';
  end if;
  if new.status is distinct from old.status
     and not ((old.status = 'draft' and new.status = 'approved') or (old.status = 'approved' and new.status = 'superseded')) then
    raise exception 'Un rendimiento solo pasa de propuesto a aprobado, o de aprobado a reemplazado.' using errcode = '42501';
  end if;
  if old.status <> 'draft' and (new.approved_by is distinct from old.approved_by or new.approved_at is distinct from old.approved_at) then
    raise exception 'Quién y cuándo aprobó un rendimiento no cambia.' using errcode = '42501';
  end if;
  return new;
end
$$;
comment on function catalog.enforce_yield_profile_rules() is
  'Trigger (BEFORE INSERT OR UPDATE) de ingredient_yield_profiles: nace como propuesta (salvo sin persona en la sesión: seed y migraciones), los valores y el borrado nunca cambian y el estado solo pasa de propuesto a aprobado y de aprobado a reemplazado.';
revoke execute on function catalog.enforce_yield_profile_rules() from public;
create trigger enforce_yield_profile_rules before insert or update on catalog.ingredient_yield_profiles
  for each row execute function catalog.enforce_yield_profile_rules();

create function catalog.reject_yield_test_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Un ensayo de rendimiento no se cambia ni se borra: si estuvo mal, se registra otro.' using errcode = '42501';
end
$$;
comment on function catalog.reject_yield_test_change() is 'Trigger: los ensayos de rendimiento son solo inserción.';
revoke execute on function catalog.reject_yield_test_change() from public;
create trigger reject_yield_test_change before update or delete on catalog.ingredient_yield_tests
  for each row execute function catalog.reject_yield_test_change();

-- Quién y cuándo registró un ensayo lo pone la base (como set_control_columns en las demás
-- tablas). Sin persona en la sesión (seed) se respeta lo que viene.
create function catalog.set_yield_test_creation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.created_at := now();
  if core.current_actor_id() is not null then
    new.created_by := core.current_actor_id();
  end if;
  return new;
end
$$;
comment on function catalog.set_yield_test_creation() is
  'Trigger (BEFORE INSERT) de ingredient_yield_tests: la hora y la persona del registro las pone la base.';
revoke execute on function catalog.set_yield_test_creation() from public;
create trigger set_yield_test_creation before insert on catalog.ingredient_yield_tests
  for each row execute function catalog.set_yield_test_creation();

-- Control, auditoría y truncate (los ensayos no tienen columnas de cambio: son solo inserción).
do $$
declare
  t text;
begin
  foreach t in array array['yield_processes', 'ingredient_yield_profiles', 'ingredient_yield_tests'] loop
    execute format('alter table catalog.%I enable row level security', t);
    execute format('revoke all on catalog.%I from public, anon, authenticated, service_role', t);
    if t <> 'ingredient_yield_tests' then
      execute format(
        'create trigger set_control_columns before insert or update on catalog.%I
           for each row execute function core.set_control_columns()', t);
      execute format('comment on column catalog.%I.id is %L', t, 'Identificador.');
      execute format('comment on column catalog.%I.created_at is %L', t, 'Cuándo se creó (lo pone la base).');
      execute format('comment on column catalog.%I.created_by is %L', t, 'Quién lo creó (lo pone la base).');
      execute format('comment on column catalog.%I.updated_at is %L', t, 'Cuándo se cambió por última vez (lo pone la base).');
      execute format('comment on column catalog.%I.updated_by is %L', t, 'Quién lo cambió por última vez (lo pone la base).');
      execute format('comment on column catalog.%I.deleted_at is %L', t, 'Cuándo se borró (borrado lógico). Vacío si está vigente.');
      execute format('comment on column catalog.%I.deleted_by is %L', t, 'Quién lo borró (lo pone la base).');
    end if;
    execute format(
      'create trigger log_change after insert or update or delete on catalog.%I
         for each row execute function audit.log_change()', t);
    execute format(
      'create trigger reject_truncate before truncate on catalog.%I
         for each statement execute function core.reject_truncate()', t);
    execute format(
      'create policy %I on catalog.%I for select to authenticated
         using (group_id in (select core.visible_group_ids(''catalog.view'')) %s)',
      t || '_select', t, case when t = 'ingredient_yield_tests' then '' else 'and deleted_at is null' end);
  end loop;
end
$$;
grant select on catalog.yield_processes, catalog.ingredient_yield_profiles, catalog.ingredient_yield_tests to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Las aprobaciones pueden aplicar cambios en catalog
-- ---------------------------------------------------------------------------
-- Misma regla que la versión de 20261021180100, con catalog en la lista de esquemas.
create or replace function workflow.check_apply_function()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
       select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where p.oid = new.apply_function::oid and n.nspname in ('core', 'org', 'catalog') and p.proname like 'apply\_%'
          and p.pronargs = 1 and p.proargtypes[0] = 'uuid'::regtype and p.prorettype = 'void'::regtype) then
    raise exception 'La función que aplica una aprobación tiene que ser una de las funciones apply_* de core, org o catalog.'
      using errcode = '42501';
  end if;
  -- Quién aprueba: un permiso y roles que existen (un error de tipeo dejaría todo sin aprobar,
  -- y vaciar los roles exigidos abriría la aprobación a cualquiera con el permiso).
  if not exists (select 1 from core.permissions p where p.code = new.required_permission and p.deleted_at is null) then
    raise exception 'El permiso para aprobar % no existe.', new.required_permission using errcode = '23514';
  end if;
  if exists (select 1 from unnest(coalesce(new.approver_role_codes, '{}')) c
              where not exists (select 1 from core.roles r where r.code = c and r.deleted_at is null)) then
    raise exception 'Algún rol exigido para aprobar no existe.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and cardinality(coalesce(old.approver_role_codes, '{}')) > cardinality(coalesce(new.approver_role_codes, '{}')) then
    raise exception 'Los roles exigidos para aprobar no se quitan con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  -- Dejar que alguien se apruebe lo propio, o pedir menos aprobaciones, tampoco se hace con una edición.
  -- Un tipo nuevo nace sin autoaprobación (revisión de seguridad, m1): habilitarla pide cambiar esta regla.
  if tg_op = 'INSERT' and new.allow_self_approval then
    raise exception 'Un tipo de aprobación nuevo no permite aprobarse lo propio: hace falta una migración documentada que cambie esta regla.'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and ((new.allow_self_approval and not old.allow_self_approval) or new.min_approvers < old.min_approvers) then
    raise exception 'Permitir la autoaprobación o pedir menos aprobaciones no se hace con una edición: hace falta una migración documentada.'
      using errcode = '42501';
  end if;
  return new;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Lectura
-- ---------------------------------------------------------------------------
-- El estándar que usa el motor: el del proveedor si lo hay, si no el general. Sin estándar,
-- status = 'undefined' (RENDIMIENTO NO DEFINIDO) y los valores vacíos: nunca se supone 100 %.
create function catalog.approved_yield(p_ingredient_id uuid, p_process_id uuid, p_cut text, p_supplier_id uuid)
returns table (profile_id uuid, cleaning_yield numeric, cooking_factor numeric, declared_no_loss boolean)
language sql
stable
set search_path = ''
as $$
  select p.id, p.cleaning_yield, p.cooking_factor, p.declared_no_loss
    from catalog.ingredient_yield_profiles p
   where p.ingredient_id = p_ingredient_id and p.process_id = p_process_id
     and coalesce(lower(p.cut), '') = coalesce(lower(btrim(p_cut)), '')
     and p.status = 'approved' and p.deleted_at is null
     and (p.supplier_id is null or p.supplier_id = p_supplier_id)
     and exists (select 1 from catalog.ingredients i where i.id = p.ingredient_id and i.deleted_at is null)
     and exists (select 1 from catalog.yield_processes y where y.id = p.process_id and y.deleted_at is null)
   order by p.supplier_id is null
   limit 1
$$;
comment on function catalog.approved_yield(uuid, uuid, text, uuid) is
  'Interna: el estándar aprobado (el del proveedor si lo hay, si no el general), o ninguna fila.';
revoke execute on function catalog.approved_yield(uuid, uuid, text, uuid) from public;

create function catalog.standard_yield(p_ingredient_id uuid, p_process_id uuid, p_cut text default null,
                                       p_supplier_id uuid default null)
returns table (profile_id uuid, cleaning_yield numeric, cooking_factor numeric, declared_no_loss boolean, status text)
language sql
stable
set search_path = ''
as $$
  -- La misma consulta que approved_yield (que es interna): esta la llama la app con sus permisos.
  with a as (
    select p.id, p.cleaning_yield, p.cooking_factor, p.declared_no_loss
      from catalog.ingredient_yield_profiles p
     where p.ingredient_id = p_ingredient_id and p.process_id = p_process_id
       and coalesce(lower(p.cut), '') = coalesce(lower(btrim(p_cut)), '')
       and p.status = 'approved' and p.deleted_at is null
       and (p.supplier_id is null or p.supplier_id = p_supplier_id)
       -- Un ingrediente o un proceso borrados no tienen estándar.
       and exists (select 1 from catalog.ingredients i where i.id = p.ingredient_id and i.deleted_at is null)
       and exists (select 1 from catalog.yield_processes y where y.id = p.process_id and y.deleted_at is null)
     order by p.supplier_id is null
     limit 1)
  select a.id, a.cleaning_yield, a.cooking_factor, a.declared_no_loss, 'approved'::text from a
  union all
  select null::uuid, null::numeric, null::numeric, null::boolean, 'undefined'::text
   where not exists (select 1 from a)
$$;
comment on function catalog.standard_yield(uuid, uuid, text, uuid) is
  'El rendimiento estándar que usa el motor: status approved con sus valores (el del proveedor si lo hay, si no el general), o undefined (RENDIMIENTO NO DEFINIDO) con los valores vacíos. Nunca supone 100 %. Respeta RLS.';
revoke execute on function catalog.standard_yield(uuid, uuid, text, uuid) from public;
grant execute on function catalog.standard_yield(uuid, uuid, text, uuid) to authenticated;

-- Para la ficha: por proceso, corte y proveedor, el estándar, el promedio de los ensayos, la
-- diferencia y si hay una propuesta esperando aprobación.
create function catalog.yield_summary(p_ingredient_id uuid)
returns table (process_id uuid, process_name text, cut text, supplier_id uuid, supplier_name text,
               standard_cleaning numeric, standard_cooking numeric, declared_no_loss boolean, approved_at timestamptz,
               tests integer, measured_cleaning numeric, measured_cooking numeric, last_tested_on date,
               pending_proposals integer)
language sql
stable
-- Con permisos propios para contar las propuestas pendientes (las solicitudes de todo el grupo no
-- las ve, por ejemplo, un Jefe de Cocina): por eso controla acá que la sesión vea ese catálogo.
-- Solo informa cuántas propuestas hay, nunca su contenido.
security definer
set search_path = ''
as $$
  with visible as (
    select i.id from catalog.ingredients i
     where i.id = p_ingredient_id and i.deleted_at is null
       and i.group_id in (select core.visible_group_ids('catalog.view'))
  ),
  keys as (
    select p.process_id, lower(p.cut) as cut_key, max(p.cut) as cut, p.supplier_id
      from catalog.ingredient_yield_profiles p
     where p.ingredient_id in (select id from visible) and p.deleted_at is null
       and (p.status = 'approved'
            or exists (select 1 from workflow.approval_requests r
                        where r.id = p.approval_request_id and r.status = 'pending'))
     group by p.process_id, lower(p.cut), p.supplier_id
    union
    select t.process_id, lower(t.cut), max(t.cut), t.supplier_id
      from catalog.ingredient_yield_tests t
     where t.ingredient_id in (select id from visible)
     group by t.process_id, lower(t.cut), t.supplier_id
  ),
  dedup as (
    select process_id, cut_key, max(cut) as cut, supplier_id from keys group by process_id, cut_key, supplier_id
  )
  select k.process_id, pr.name, k.cut, k.supplier_id, s.name,
         std.cleaning_yield, std.cooking_factor, std.declared_no_loss, std.approved_at,
         coalesce(m.tests, 0), m.cleaning, m.cooking, m.last_on,
         (select count(*)::int from catalog.ingredient_yield_profiles d
           join workflow.approval_requests r on r.id = d.approval_request_id and r.status = 'pending'
          where d.ingredient_id = p_ingredient_id and d.process_id = k.process_id and d.status = 'draft' and d.deleted_at is null
            and coalesce(lower(d.cut), '') = coalesce(k.cut_key, '')
            and d.supplier_id is not distinct from k.supplier_id)
    from dedup k
    join catalog.yield_processes pr on pr.id = k.process_id and pr.deleted_at is null
    left join catalog.suppliers s on s.id = k.supplier_id and s.deleted_at is null
    left join lateral (
      select p.cleaning_yield, p.cooking_factor, p.declared_no_loss, p.approved_at
        from catalog.ingredient_yield_profiles p
       where p.ingredient_id = p_ingredient_id and p.process_id = k.process_id and p.status = 'approved' and p.deleted_at is null
         and coalesce(lower(p.cut), '') = coalesce(k.cut_key, '') and p.supplier_id is not distinct from k.supplier_id
       limit 1) std on true
    left join lateral (
      -- Promedio ponderado por muestras: un ensayo de 10 muestras pesa más que uno de 1
      -- (decisión de Joaco, 2026-10-30). Cada promedio usa solo los ensayos que tienen ese par.
      select count(*)::int as tests,
             sum(t.clean_weight / t.gross_weight * t.samples) filter (where t.gross_weight is not null)
               / nullif(sum(t.samples) filter (where t.gross_weight is not null), 0) as cleaning,
             sum(t.after_cooking_weight / t.before_cooking_weight * t.samples) filter (where t.before_cooking_weight is not null)
               / nullif(sum(t.samples) filter (where t.before_cooking_weight is not null), 0) as cooking,
             max(t.tested_on) as last_on
        from catalog.ingredient_yield_tests t
       where t.ingredient_id = p_ingredient_id and t.process_id = k.process_id
         and coalesce(lower(t.cut), '') = coalesce(k.cut_key, '') and t.supplier_id is not distinct from k.supplier_id) m on true
   order by pr.name, k.cut nulls first, s.name nulls first
$$;
comment on function catalog.yield_summary(uuid) is
  'Para la ficha de la materia prima: por proceso, corte y proveedor, el estándar aprobado, los ensayos (cantidad, promedio de limpieza y de cocción, último) y cuántas propuestas esperan aprobación. Corre con permisos propios y solo devuelve filas si la sesión ve el catálogo de ese grupo (catalog.view).';
revoke execute on function catalog.yield_summary(uuid) from public;
grant execute on function catalog.yield_summary(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Escritura
-- ---------------------------------------------------------------------------
-- Si la sesión tiene el permiso en algún alcance de ese grupo (grupo, marca o local), con la misma
-- base que usan todas las funciones de permisos (core.actor_grants). Para PROPONER lo que es de
-- todo el grupo: la decisión la toma otra persona con el permiso para todo el grupo (ADR-0021).
create function core.has_permission_in_group_any_scope(p_permission text, p_group_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (select 1 from core.actor_grants(p_permission) g where g.group_id = p_group_id);
end
$$;
comment on function core.has_permission_in_group_any_scope(text, uuid) is
  'Interna, de la familia has_permission_*: si la sesión tiene el permiso en algún alcance del grupo (grupo, marca o local). Solo para proponer lo que es de todo el grupo; nunca en políticas RLS ni para aprobar (ADR-0021).';
revoke execute on function core.has_permission_in_group_any_scope(text, uuid) from public;

create function catalog.record_yield_test(p_ingredient_id uuid, p_process_id uuid, p_restaurant_id uuid,
                                          p_tested_on date, p_measures jsonb, p_details jsonb, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group      uuid;
  v_id         uuid;
  v_constraint text;
  v_message    text;
begin
  select group_id into v_group from catalog.ingredients where id = p_ingredient_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission('yields.record', p_restaurant_id)
                      and exists (select 1 from org.restaurants where id = p_restaurant_id and group_id = v_group),
                      'registrar ensayos de rendimiento en ese local');
  perform org.check_keys(coalesce(p_measures, '{}'::jsonb),
                         array['gross_weight', 'clean_weight', 'before_cooking_weight', 'after_cooking_weight', 'discard_weight']);
  perform org.check_keys(coalesce(p_details, '{}'::jsonb), array['cut', 'supplier_id', 'samples', 'responsible', 'notes']);
  if not exists (select 1 from catalog.yield_processes where id = p_process_id and group_id = v_group and deleted_at is null) then
    raise exception 'Elegí un proceso del grupo.' using errcode = '22023';
  end if;
  if nullif(p_details ->> 'supplier_id', '') is not null
     and not exists (select 1 from catalog.suppliers
                      where id = (p_details ->> 'supplier_id')::uuid and group_id = v_group and deleted_at is null) then
    raise exception 'Elegí un proveedor vigente del grupo.' using errcode = '22023';
  end if;
  if p_tested_on is null or p_tested_on > (now() at time zone 'America/Argentina/Buenos_Aires')::date then
    raise exception 'La fecha del ensayo no puede ser futura.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.ingredient_yield_tests (group_id, ingredient_id, process_id, cut, supplier_id, restaurant_id, tested_on,
                                              samples, gross_weight, clean_weight, before_cooking_weight,
                                              after_cooking_weight, discard_weight, responsible, notes)
  values (v_group, p_ingredient_id, p_process_id, nullif(btrim(p_details ->> 'cut'), ''),
          nullif(p_details ->> 'supplier_id', '')::uuid, p_restaurant_id, p_tested_on,
          coalesce((p_details ->> 'samples')::integer, 1),
          (p_measures ->> 'gross_weight')::numeric, (p_measures ->> 'clean_weight')::numeric,
          (p_measures ->> 'before_cooking_weight')::numeric, (p_measures ->> 'after_cooking_weight')::numeric,
          (p_measures ->> 'discard_weight')::numeric,
          nullif(btrim(p_details ->> 'responsible'), ''), nullif(btrim(p_details ->> 'notes'), ''))
  returning id into v_id;
  return v_id;
exception
  when invalid_text_representation then
    raise exception 'Algún dato tiene un formato que no se entiende (un número o un proveedor).' using errcode = '22023';
  when unique_violation or check_violation or foreign_key_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.record_yield_test(uuid, uuid, uuid, date, jsonb, jsonb, text) is
  'Registra un ensayo de rendimiento en un local. Pide yields.record en ese local y un motivo. p_measures: gross_weight, clean_weight, before_cooking_weight, after_cooking_weight, discard_weight (gramos). p_details: cut, supplier_id, samples, responsible, notes. Nunca cambia el estándar.';

create function catalog.propose_yield_standard(p_ingredient_id uuid, p_process_id uuid, p_cut text,
                                               p_cleaning_yield numeric, p_cooking_factor numeric, p_method text,
                                               p_declared_no_loss boolean, p_reason text,
                                               p_supplier_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ing        catalog.ingredients;
  v_process    text;
  v_cur_id     uuid;
  v_cur_clean  numeric;
  v_cur_cook   numeric;
  v_cur_noloss boolean;
  v_exact_id   uuid;
  v_profile    uuid;
  v_request    uuid;
  v_constraint text;
  v_message    text;
begin
  select * into v_ing from catalog.ingredients where id = p_ingredient_id and deleted_at is null;
  perform org.require(v_ing.id is not null and core.has_permission_in_group_any_scope('yields.record', v_ing.group_id),
                      'proponer rendimientos en este grupo');
  select name into v_process from catalog.yield_processes
   where id = p_process_id and group_id = v_ing.group_id and deleted_at is null;
  if v_process is null then
    raise exception 'Elegí un proceso del grupo.' using errcode = '22023';
  end if;
  if p_cleaning_yield is null or p_cooking_factor is null then
    raise exception 'Faltan la limpieza o el factor de cocción.' using errcode = '22023';
  end if;
  if p_supplier_id is not null
     and not exists (select 1 from catalog.suppliers where id = p_supplier_id and group_id = v_ing.group_id and deleted_at is null) then
    raise exception 'Elegí un proveedor vigente del grupo.' using errcode = '22023';
  end if;
  -- Una sola propuesta pendiente por ingrediente, proceso, corte y proveedor: así nadie aprueba
  -- sobre un "antes" que ya cambió (revisiones de base y de seguridad, M1).
  if exists (select 1 from catalog.ingredient_yield_profiles d
               join workflow.approval_requests r on r.id = d.approval_request_id and r.status = 'pending'
              where d.ingredient_id = p_ingredient_id and d.process_id = p_process_id and d.status = 'draft'
                and coalesce(lower(d.cut), '') = coalesce(lower(nullif(btrim(p_cut), '')), '')
                and d.supplier_id is not distinct from p_supplier_id and d.deleted_at is null) then
    raise exception 'Ya hay una propuesta pendiente para ese proceso: esperá a que se decida o pedí que la retiren.'
      using errcode = '23505';
  end if;
  -- El estándar de esta misma clave: el que la aprobación reemplaza.
  select p.id into v_exact_id
    from catalog.ingredient_yield_profiles p
   where p.ingredient_id = p_ingredient_id and p.process_id = p_process_id and p.status = 'approved'
     and coalesce(lower(p.cut), '') = coalesce(lower(nullif(btrim(p_cut), '')), '')
     and p.supplier_id is not distinct from p_supplier_id and p.deleted_at is null;
  select a.profile_id, a.cleaning_yield, a.cooking_factor, a.declared_no_loss
    into v_cur_id, v_cur_clean, v_cur_cook, v_cur_noloss
    from catalog.approved_yield(p_ingredient_id, p_process_id, p_cut, p_supplier_id) a;
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cut, supplier_id, cleaning_yield,
                                                 cooking_factor, method, declared_no_loss)
  values (v_ing.group_id, p_ingredient_id, p_process_id, nullif(btrim(p_cut), ''), p_supplier_id, p_cleaning_yield,
          p_cooking_factor, nullif(btrim(p_method), ''), coalesce(p_declared_no_loss, false))
  returning id into v_profile;
  v_request := workflow.request_approval(
    'catalog.approve_yield_profile', v_ing.group_id, null, null, null, v_profile,
    jsonb_build_object('ingredient', v_ing.name, 'process', v_process, 'cut', nullif(btrim(p_cut), ''),
                       'cleaning_yield', p_cleaning_yield, 'cooking_factor', p_cooking_factor,
                       'declared_no_loss', coalesce(p_declared_no_loss, false), 'method', nullif(btrim(p_method), ''),
                       'profile_id', v_profile, 'current_profile_id', v_exact_id),
    case when v_cur_id is null then jsonb_build_object('cleaning_yield', null, 'cooking_factor', null)
         else jsonb_build_object('cleaning_yield', v_cur_clean, 'cooking_factor', v_cur_cook,
                                 'declared_no_loss', v_cur_noloss) end,
    p_reason);
  update catalog.ingredient_yield_profiles set approval_request_id = v_request where id = v_profile;
  return v_request;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'ingredient_yield_profiles_no_loss_declared' then
    raise exception 'Un rendimiento de 100 %% sin merma se tiene que declarar "sin merma".' using errcode = '23514';
  end if;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.propose_yield_standard(uuid, uuid, text, numeric, numeric, text, boolean, text, uuid) is
  'Propone un rendimiento estándar: crea el perfil propuesto y la solicitud de aprobación (catalog.approve_yield_profile). Pide yields.record en algún lugar del grupo y un motivo. Devuelve el id de la solicitud.';

-- Aplica la aprobación (la llama workflow.decide_approval en su transacción).
create function catalog.apply_yield_profile(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req     workflow.approval_requests := workflow.approved_request(p_request_id);
  v_profile catalog.ingredient_yield_profiles;
begin
  select * into v_profile from catalog.ingredient_yield_profiles
   where id = v_req.entity_id and approval_request_id = p_request_id and deleted_at is null
   for update;
  if not found or v_profile.status <> 'draft' then
    perform workflow.cannot_apply('el rendimiento propuesto ya no está pendiente');
  end if;
  if not exists (select 1 from catalog.ingredients where id = v_profile.ingredient_id and deleted_at is null) then
    perform workflow.cannot_apply('la materia prima ya no está vigente');
  end if;
  -- El "antes" que vio quien aprobó tiene que seguir siendo el vigente.
  if (select p.id from catalog.ingredient_yield_profiles p
       where p.ingredient_id = v_profile.ingredient_id and p.process_id = v_profile.process_id
         and coalesce(lower(p.cut), '') = coalesce(lower(v_profile.cut), '')
         and p.supplier_id is not distinct from v_profile.supplier_id
         and p.status = 'approved' and p.deleted_at is null)
     is distinct from nullif(v_req.proposed_changes ->> 'current_profile_id', '')::uuid then
    perform workflow.cannot_apply('el estándar cambió desde que se propuso; proponé de nuevo con el valor actual');
  end if;
  update catalog.ingredient_yield_profiles set status = 'superseded'
   where ingredient_id = v_profile.ingredient_id and process_id = v_profile.process_id
     and coalesce(lower(cut), '') = coalesce(lower(v_profile.cut), '')
     and supplier_id is not distinct from v_profile.supplier_id
     and status = 'approved' and deleted_at is null;
  update catalog.ingredient_yield_profiles
     set status = 'approved', approved_by = v_req.resolved_by, approved_at = now()
   where id = v_profile.id;
end
$$;
comment on function catalog.apply_yield_profile(uuid) is
  'Interna (aprobación catalog.approve_yield_profile): el estándar anterior de esa clave pasa a reemplazado y el propuesto a vigente, con quién y cuándo lo aprobó.';
revoke execute on function catalog.apply_yield_profile(uuid) from public;

create function catalog.create_yield_process(p_group_id uuid, p_code text, p_name text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id         uuid;
  v_constraint text;
  v_message    text;
begin
  perform org.require(core.has_permission_in_group('yields.approve', p_group_id), 'crear procesos en este grupo');
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.yield_processes (group_id, code, name) values (p_group_id, upper(btrim(p_code)), btrim(p_name))
  returning id into v_id;
  return v_id;
exception when unique_violation or check_violation or foreign_key_violation then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_yield_process(uuid, text, text, text) is
  'Crea un proceso (pelado, hervido…). Pide yields.approve para todo el grupo y un motivo.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'catalog.record_yield_test(uuid, uuid, uuid, date, jsonb, jsonb, text)',
    'catalog.propose_yield_standard(uuid, uuid, text, numeric, numeric, text, boolean, text, uuid)',
    'catalog.create_yield_process(uuid, text, text, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;

-- El tipo de aprobación. La solicitud es de todo el grupo: decide quien tenga yields.approve para
-- todo el grupo (workflow.decision_blocker), nunca quien la pidió.
do $$
begin
  perform core.set_change_context('Aprobación de rendimientos estándar (Fase 2, etapa 2.1 B)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, min_approvers, apply_function,
                                           entity_table)
  values ('catalog.approve_yield_profile', 'Rendimiento estándar',
          'Cambiar el rendimiento estándar de una materia prima (lo usa el motor de costos). Lo aprueba un Chef Ejecutivo de todo el grupo, distinto de quien lo propuso.',
          'yields.approve', 1, 'catalog.apply_yield_profile(uuid)'::regprocedure, 'catalog.ingredient_yield_profiles');
end
$$;
