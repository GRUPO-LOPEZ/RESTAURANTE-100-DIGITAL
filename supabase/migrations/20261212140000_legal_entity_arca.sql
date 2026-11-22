-- Razón social con los datos de la constancia de inscripción de ARCA (Tanda 1 de las correcciones de Soy, ADR-0061).
--
-- * Se cargan a mano (decisión 4 de Soy): autocompletar desde ARCA queda para cuando esté el certificado digital.
-- * El CUIT se controla con su dígito verificador cuando se carga o se cambia (como en proveedores, ADR-0050).
-- * Actividades de ARCA en una tabla aparte: una principal y las secundarias, con baja lógica.
-- * Desde qué fecha cada local factura a nombre de cada razón social: historial aparte. restaurants.legal_entity_id
--   sigue siendo la vigente, así las facturas, los costos y sus triggers no cambian.
-- * «Agente de retención» solo se marca: el cálculo en los pagos (purchasing.payments.withholding_amount, P8) sigue
--   fuera de esta tarea.
-- * Quién ve: lo mismo que la razón social hoy (org.manage del grupo o quien ve precios). Quién cambia: org.manage
--   del grupo.

-- ---------------------------------------------------------------------------
-- 1. Tipos
-- ---------------------------------------------------------------------------
create type org.legal_form as enum ('srl', 'sa', 'sas', 'person');
comment on type org.legal_form is 'Forma jurídica de una razón social: S.R.L., S.A., S.A.S. o persona humana.';
create type org.income_tax_status as enum ('registered', 'exempt', 'not_subject');
comment on type org.income_tax_status is 'Situación frente a Ganancias: inscripta, exenta o no alcanzada.';
create type org.gross_income_regime as enum ('multilateral', 'local', 'exempt');
comment on type org.gross_income_regime is
  'Régimen de Ingresos Brutos: Convenio Multilateral (varias provincias), local (una sola) o exento.';

-- ---------------------------------------------------------------------------
-- 2. Columnas nuevas de la razón social
-- ---------------------------------------------------------------------------
alter table org.legal_entities
  add column legal_form            org.legal_form,
  add column activity_start        date,
  add column trade_name            text check (trade_name is null or length(btrim(trade_name)) between 1 and 200),
  add column fiscal_street         text check (fiscal_street is null or length(btrim(fiscal_street)) between 1 and 200),
  add column fiscal_locality       text check (fiscal_locality is null or length(btrim(fiscal_locality)) between 1 and 120),
  add column fiscal_postal_code    text check (fiscal_postal_code is null or fiscal_postal_code ~ '^[A-Z]?[0-9]{4}([A-Z]{3})?$'),
  add column fiscal_province       text references org.provinces (code) on delete restrict,
  add column electronic_domicile   text check (electronic_domicile is null
                                               or (length(electronic_domicile) <= 320
                                                   and electronic_domicile ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  add column income_tax            org.income_tax_status,
  add column gross_income_regime   org.gross_income_regime,
  add column gross_income_number   text check (gross_income_number is null or gross_income_number ~ '^[0-9][0-9./-]{3,19}$'),
  add column gross_income_province text references org.provinces (code) on delete restrict,
  add column is_employer           boolean not null default false,
  add column is_withholding_agent  boolean not null default false,
  add column is_perception_agent   boolean not null default false;
comment on column org.legal_entities.legal_form is 'Forma jurídica (S.R.L., S.A., S.A.S. o persona), como figura en ARCA.';
comment on column org.legal_entities.activity_start is 'Fecha de inicio de actividades en ARCA.';
comment on column org.legal_entities.trade_name is 'Nombre de fantasía (opcional).';
comment on column org.legal_entities.fiscal_street is 'Domicilio fiscal: calle y número, como figura en la constancia.';
comment on column org.legal_entities.fiscal_locality is 'Domicilio fiscal: localidad.';
comment on column org.legal_entities.fiscal_postal_code is 'Domicilio fiscal: código postal (4 cifras o el CPA).';
comment on column org.legal_entities.fiscal_province is 'Domicilio fiscal: provincia.';
comment on column org.legal_entities.electronic_domicile is 'Domicilio fiscal electrónico: el correo donde ARCA manda las notificaciones.';
comment on column org.legal_entities.income_tax is 'Situación frente a Ganancias.';
comment on column org.legal_entities.gross_income_regime is 'Régimen de Ingresos Brutos.';
comment on column org.legal_entities.gross_income_number is 'Número de inscripción en Ingresos Brutos.';
comment on column org.legal_entities.gross_income_province is 'Jurisdicción sede de Ingresos Brutos.';
comment on column org.legal_entities.is_employer is 'Si figura como empleadora en ARCA.';
comment on column org.legal_entities.is_withholding_agent is
  'Si es agente de retención: los pagos a proveedores tienen que calcularla (columna preparada en Pagos; el cálculo todavía no está).';
comment on column org.legal_entities.is_perception_agent is 'Si es agente de percepción.';
create index legal_entities_fiscal_province_idx on org.legal_entities (fiscal_province);
create index legal_entities_gross_income_province_idx on org.legal_entities (gross_income_province);

-- El CUIT con dígito verificador, solo cuando se carga o se cambia (los de antes no se traban hasta que alguien los
-- corrige). El check viejo de «11 números» sigue.
create function org.guard_legal_entity_tax_id()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.tax_id is distinct from old.tax_id then
    -- El largo lo controla el check de siempre («11 números»); acá, el dígito verificador.
    if new.tax_id ~ '^[0-9]{11}$' and not core.valid_cuit(new.tax_id) then
      raise exception 'El CUIT no es válido: revisá los números.'
        using errcode = '23514', constraint = 'legal_entities_tax_id_valid';
    end if;
  end if;
  return new;
end
$$;
comment on function org.guard_legal_entity_tax_id() is
  'Interna: el CUIT nuevo o cambiado de una razón social tiene su dígito verificador válido.';
revoke execute on function org.guard_legal_entity_tax_id() from public;
create trigger guard_tax_id before insert or update of tax_id on org.legal_entities
  for each row execute function org.guard_legal_entity_tax_id();

-- ---------------------------------------------------------------------------
-- 3. Actividades de ARCA
-- ---------------------------------------------------------------------------
create table org.legal_entity_activities (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null,
  legal_entity_id uuid not null,
  code            text not null check (code ~ '^[0-9]{6}$'),
  description     text not null check (length(btrim(description)) between 1 and 200),
  is_primary      boolean not null default false,
  created_at      timestamptz not null default now(),
  created_by      uuid references core.actors (id) on delete restrict,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references core.actors (id) on delete restrict,
  deleted_at      timestamptz,
  deleted_by      uuid references core.actors (id) on delete restrict,
  constraint legal_entity_activities_entity_fkey foreign key (legal_entity_id, group_id)
    references org.legal_entities (id, group_id) on delete restrict
);
create unique index legal_entity_activities_code_key on org.legal_entity_activities (legal_entity_id, code)
  where deleted_at is null;
create unique index legal_entity_activities_primary_key on org.legal_entity_activities (legal_entity_id)
  where is_primary and deleted_at is null;
create index legal_entity_activities_entity_idx on org.legal_entity_activities (legal_entity_id, group_id);
comment on table org.legal_entity_activities is
  'Actividades de una razón social en ARCA (código de 6 cifras y descripción): una principal y las secundarias.';
comment on column org.legal_entity_activities.id is 'Identificador de la actividad.';
comment on column org.legal_entity_activities.group_id is 'Grupo al que pertenece.';
comment on column org.legal_entity_activities.legal_entity_id is 'Razón social.';
comment on column org.legal_entity_activities.code is 'Código de la actividad en ARCA (CLAE), 6 cifras: 561011.';
comment on column org.legal_entity_activities.description is 'Descripción de la actividad: Restaurantes y cantinas sin espectáculo.';
comment on column org.legal_entity_activities.is_primary is 'Si es la actividad principal. Hay una sola principal vigente.';
comment on column org.legal_entity_activities.created_at is 'Cuándo se creó (lo pone la base).';
comment on column org.legal_entity_activities.created_by is 'Quién la creó (lo pone la base).';
comment on column org.legal_entity_activities.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column org.legal_entity_activities.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column org.legal_entity_activities.deleted_at is 'Baja lógica: la actividad se quitó. Nunca se borra.';
comment on column org.legal_entity_activities.deleted_by is 'Quién la quitó (lo pone la base).';

-- Quién ve los datos de ARCA de una razón social (actividades, historial y constancias): quien administra todo el
-- grupo, o quien ve precios en algún local que factura con ella (auditoría de seguridad, M1).
create function org.can_see_legal_entity(p_legal_entity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from org.legal_entities e
                  where e.id = p_legal_entity_id and e.deleted_at is null
                    and (core.has_permission_in_group('org.manage', e.group_id)
                         or exists (select 1 from org.restaurants r
                                     where r.legal_entity_id = e.id and r.deleted_at is null
                                       and core.has_permission('prices.view', r.id))))
$$;
comment on function org.can_see_legal_entity(uuid) is
  'Si la sesión ve los datos de ARCA de una razón social: org.manage en todo el grupo, o prices.view en algún local que factura con ella.';
revoke execute on function org.can_see_legal_entity(uuid) from public;
grant execute on function org.can_see_legal_entity(uuid) to authenticated;

alter table org.legal_entity_activities enable row level security;
revoke all on org.legal_entity_activities from public, anon, authenticated, service_role;
grant select on org.legal_entity_activities to authenticated;
create policy legal_entity_activities_select on org.legal_entity_activities for select to authenticated
  using (deleted_at is null and org.can_see_legal_entity(legal_entity_id));
create trigger set_control_columns before insert or update on org.legal_entity_activities
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on org.legal_entity_activities
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on org.legal_entity_activities
  for each statement execute function core.reject_truncate();

-- ---------------------------------------------------------------------------
-- 4. Desde qué fecha cada local factura a nombre de cada razón social
-- ---------------------------------------------------------------------------
create table org.restaurant_legal_entities (
  id              uuid primary key default gen_random_uuid(),
  group_id        uuid not null,
  restaurant_id   uuid not null,
  legal_entity_id uuid not null,
  valid_from      date not null,
  created_at      timestamptz not null default now(),
  created_by      uuid references core.actors (id) on delete restrict,
  updated_at      timestamptz not null default now(),
  updated_by      uuid references core.actors (id) on delete restrict,
  deleted_at      timestamptz,
  deleted_by      uuid references core.actors (id) on delete restrict,
  constraint restaurant_legal_entities_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint restaurant_legal_entities_entity_fkey foreign key (legal_entity_id, group_id)
    references org.legal_entities (id, group_id) on delete restrict
);
create unique index restaurant_legal_entities_from_key on org.restaurant_legal_entities (restaurant_id, valid_from)
  where deleted_at is null;
create index restaurant_legal_entities_restaurant_idx on org.restaurant_legal_entities (restaurant_id, group_id);
create index restaurant_legal_entities_entity_idx on org.restaurant_legal_entities (legal_entity_id, group_id);
comment on table org.restaurant_legal_entities is
  'Historial de razones sociales de cada local: desde qué fecha factura a nombre de cuál. La vigente está también en restaurants.legal_entity_id; las facturas viejas siguen con la anterior.';
comment on column org.restaurant_legal_entities.id is 'Identificador del tramo.';
comment on column org.restaurant_legal_entities.group_id is 'Grupo al que pertenece.';
comment on column org.restaurant_legal_entities.restaurant_id is 'Local.';
comment on column org.restaurant_legal_entities.legal_entity_id is 'Razón social a cuyo nombre factura el local desde valid_from.';
comment on column org.restaurant_legal_entities.valid_from is 'Desde qué fecha (día de la Argentina) el local factura a nombre de esta razón social.';
comment on column org.restaurant_legal_entities.created_at is 'Cuándo se registró (lo pone la base).';
comment on column org.restaurant_legal_entities.created_by is 'Quién lo registró (lo pone la base).';
comment on column org.restaurant_legal_entities.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column org.restaurant_legal_entities.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column org.restaurant_legal_entities.deleted_at is 'Baja lógica. Nunca se borra.';
comment on column org.restaurant_legal_entities.deleted_by is 'Quién lo dio de baja (lo pone la base).';

alter table org.restaurant_legal_entities enable row level security;
revoke all on org.restaurant_legal_entities from public, anon, authenticated, service_role;
grant select on org.restaurant_legal_entities to authenticated;
create policy restaurant_legal_entities_select on org.restaurant_legal_entities for select to authenticated
  using (deleted_at is null and (group_id in (select core.permitted_group_ids('org.manage'))
                                 or core.has_permission('prices.view', restaurant_id)));
create trigger set_control_columns before insert or update on org.restaurant_legal_entities
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on org.restaurant_legal_entities
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on org.restaurant_legal_entities
  for each statement execute function core.reject_truncate();

-- Cada vez que cambia la razón social de un local, queda el tramo nuevo. La fecha viaja en la transacción
-- (app.legal_entity_from, la pone org.save_restaurant_sheet); si no viene, es hoy en la Argentina.
create function org.track_restaurant_legal_entity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from date := coalesce(nullif(current_setting('app.legal_entity_from', true), '')::date,
                          (now() at time zone 'America/Argentina/Buenos_Aires')::date);
begin
  if new.legal_entity_id is null
     or (tg_op = 'UPDATE' and new.legal_entity_id is not distinct from old.legal_entity_id) then
    return null;
  end if;
  update org.restaurant_legal_entities
     set legal_entity_id = new.legal_entity_id
   where restaurant_id = new.id and valid_from = v_from and deleted_at is null;
  if not found then
    insert into org.restaurant_legal_entities (group_id, restaurant_id, legal_entity_id, valid_from)
    values (new.group_id, new.id, new.legal_entity_id, v_from);
  end if;
  return null;
end
$$;
comment on function org.track_restaurant_legal_entity() is
  'Trigger: cuando un local cambia de razón social, registra desde qué fecha (app.legal_entity_from o hoy en la Argentina).';
revoke execute on function org.track_restaurant_legal_entity() from public;
create trigger track_legal_entity after insert or update of legal_entity_id on org.restaurants
  for each row execute function org.track_restaurant_legal_entity();

-- Lo que ya existe: el tramo vigente, desde el día de alta del local.
do $$
begin
  if exists (select 1 from org.restaurants where legal_entity_id is not null) then
    perform core.set_change_context('Historial de razones sociales de los locales (ADR-0061)', 'maintenance');
    insert into org.restaurant_legal_entities (group_id, restaurant_id, legal_entity_id, valid_from)
    select group_id, id, legal_entity_id, (created_at at time zone 'America/Argentina/Buenos_Aires')::date
      from org.restaurants
     where legal_entity_id is not null and deleted_at is null;
  end if;
end
$$;

-- Lo que le falta a una razón social para estar completa (los obligatorios de la constancia).
create function org.legal_entity_missing(p_e org.legal_entities)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[
    case when p_e.legal_form is null then 'forma jurídica' end,
    case when p_e.activity_start is null then 'inicio de actividades' end,
    case when nullif(btrim(p_e.fiscal_street), '') is null then 'calle y número' end,
    case when nullif(btrim(p_e.fiscal_locality), '') is null then 'localidad' end,
    case when p_e.fiscal_postal_code is null then 'código postal' end,
    case when p_e.fiscal_province is null then 'provincia' end,
    case when p_e.income_tax is null then 'Ganancias' end,
    case when p_e.gross_income_regime is null then 'Ingresos Brutos' end,
    case when p_e.gross_income_regime is distinct from 'exempt' and p_e.gross_income_number is null
         then 'número de Ingresos Brutos' end,
    case when not exists (select 1 from org.legal_entity_activities a
                           where a.legal_entity_id = p_e.id and a.is_primary and a.deleted_at is null)
         then 'actividad principal' end
  ], null)
$$;

comment on function org.legal_entity_missing(org.legal_entities) is
  'Los datos obligatorios de la constancia que le faltan a una razón social, en palabras. Son 10; con el nombre, el CUIT y el IVA, que nunca faltan, la ficha cuenta 13.';
revoke execute on function org.legal_entity_missing(org.legal_entities) from public;
