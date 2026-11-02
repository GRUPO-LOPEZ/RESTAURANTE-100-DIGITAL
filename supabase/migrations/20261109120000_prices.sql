-- Etapa 2.1 C: precios con historia y aprobación (ADR-0029).
--
-- Lo que pidió Soy (ADR-0024 y ADR-0026) y decidió Joaco (2026-11-02):
--   - un precio nunca se pisa: cada cambio es un registro nuevo, y solo entra aprobado;
--   - búsqueda local → marca → grupo, diciendo de dónde viene un precio heredado;
--   - el costo va sin el IVA recuperable (según la razón social del local), y se ven las dos cifras;
--     un "precio ingresado" (sin factura) es el precio final;
--   - Compras propone y el Controller aprueba; si la variación supera un % del grupo, aprueba también
--     Dirección General (dos solicitudes seguidas, sin cambiar el motor de aprobaciones);
--   - con varios productos con precio, se usa el último aprobado;
--   - un precio con más de N días (30, o el de su categoría) se marca desactualizado;
--   - fletes: más adelante, con las facturas.
-- Cada precio guarda el contenido del envase en la unidad de uso con el que se aprobó: cambiar el
-- contenido de un producto o una conversión no mueve ningún costo (hay que proponer un precio nuevo).

grant usage on schema costing to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Razones sociales (respuesta 2 b de Soy, ADR-0024)
-- ---------------------------------------------------------------------------
create type org.vat_condition as enum ('registered', 'monotax', 'exempt');
comment on type org.vat_condition is
  'Condición frente al IVA de una razón social: responsable inscripto (computa crédito fiscal), monotributo o exento.';

create table org.legal_entities (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  name           text not null check (length(btrim(name)) between 1 and 200),
  tax_id         text not null check (tax_id ~ '^[0-9]{11}$'),
  vat_condition  org.vat_condition not null,
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  constraint legal_entities_id_group_key unique (id, group_id)
);
create unique index legal_entities_tax_id_key on org.legal_entities (group_id, tax_id) where deleted_at is null;
create index legal_entities_group_idx on org.legal_entities (group_id) where deleted_at is null;
comment on table org.legal_entities is
  'Razones sociales del grupo (sociedades con CUIT). Cada local apunta a una; varios locales pueden compartirla. Define si el IVA de las compras es recuperable.';
comment on column org.legal_entities.id is 'Identificador de la razón social.';
comment on column org.legal_entities.group_id is 'Grupo al que pertenece.';
comment on column org.legal_entities.name is 'Nombre de la sociedad, como figura en el CUIT.';
comment on column org.legal_entities.tax_id is 'CUIT, 11 números sin guiones. Único dentro del grupo.';
comment on column org.legal_entities.vat_condition is 'Condición frente al IVA. Solo un responsable inscripto descuenta el IVA de sus costos.';
comment on column org.legal_entities.created_at is 'Cuándo se creó (lo pone la base).';
comment on column org.legal_entities.created_by is 'Quién la creó (lo pone la base).';
comment on column org.legal_entities.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column org.legal_entities.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column org.legal_entities.deleted_at is 'Baja lógica. Nunca se borra.';
comment on column org.legal_entities.deleted_by is 'Quién la dio de baja (lo pone la base).';

alter table org.restaurants add column legal_entity_id uuid;
alter table org.restaurants add constraint restaurants_legal_entity_fkey
  foreign key (legal_entity_id, group_id) references org.legal_entities (id, group_id) on delete restrict;
create index restaurants_legal_entity_idx on org.restaurants (legal_entity_id, group_id) where legal_entity_id is not null;
comment on column org.restaurants.legal_entity_id is
  'Razón social del local. Sin ella, el costo sin IVA queda incompleto (el sistema no supone la condición frente al IVA).';

alter table org.legal_entities enable row level security;
revoke all on org.legal_entities from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on org.legal_entities
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on org.legal_entities
  for each row execute function audit.log_change();
create trigger reject_truncate before truncate on org.legal_entities
  for each statement execute function core.reject_truncate();
-- La política de lectura va después de costing.price_view_group_ids (sección 4).
grant select on org.legal_entities to authenticated;

create function org.create_legal_entity(p_group_id uuid, p_name text, p_tax_id text, p_vat_condition text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform org.require(core.has_permission_in_group('org.manage', p_group_id), 'crear razones sociales en este grupo');
  if p_vat_condition is null or p_vat_condition not in ('registered', 'monotax', 'exempt') then
    raise exception 'Elegí la condición frente al IVA.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into org.legal_entities (group_id, name, tax_id, vat_condition)
  values (p_group_id, btrim(p_name), regexp_replace(coalesce(p_tax_id, ''), '[^0-9]', '', 'g'), p_vat_condition::org.vat_condition)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'Ya hay una razón social con ese CUIT en el grupo.' using errcode = '23505';
  when check_violation or not_null_violation then
    raise exception 'Revisá el nombre y el CUIT (11 números).' using errcode = '23514';
end
$$;
comment on function org.create_legal_entity(uuid, text, text, text, text) is
  'Crea una razón social del grupo. Pide org.manage en el grupo y un motivo. El CUIT se guarda sin guiones.';

create function org.update_legal_entity(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from org.legal_entities where id = p_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('org.manage', v_group), 'editar esta razón social');
  perform org.check_keys(p_changes, array['name', 'tax_id', 'vat_condition']);
  if p_changes ? 'vat_condition' and coalesce(p_changes ->> 'vat_condition', '') not in ('registered', 'monotax', 'exempt') then
    raise exception 'Elegí la condición frente al IVA.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.legal_entities
     set name          = coalesce(btrim(p_changes ->> 'name'), name),
         tax_id        = coalesce(regexp_replace(p_changes ->> 'tax_id', '[^0-9]', '', 'g'), tax_id),
         vat_condition = coalesce((p_changes ->> 'vat_condition')::org.vat_condition, vat_condition)
   where id = p_id;
exception
  when unique_violation then
    raise exception 'Ya hay una razón social con ese CUIT en el grupo.' using errcode = '23505';
  when check_violation or not_null_violation then
    raise exception 'Revisá el nombre y el CUIT (11 números).' using errcode = '23514';
end
$$;
comment on function org.update_legal_entity(uuid, jsonb, text) is
  'Edita nombre, CUIT o condición frente al IVA de una razón social. Pide org.manage en el grupo y un motivo.';

create function org.set_restaurant_legal_entity(p_restaurant_id uuid, p_legal_entity_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from org.restaurants where id = p_restaurant_id and deleted_at is null;
  -- Cambia si el costo va con o sin IVA: la elige solo quien administra todo el grupo (decisión de Joaco,
  -- 2026-11-02), no el Gerente ni el Director de una marca.
  perform org.require(v_group is not null and core.has_permission_in_group('org.manage', v_group),
                      'elegir la razón social de este local');
  if p_legal_entity_id is not null
     and not exists (select 1 from org.legal_entities where id = p_legal_entity_id and group_id = v_group and deleted_at is null) then
    raise exception 'Elegí una razón social vigente del grupo.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update org.restaurants set legal_entity_id = p_legal_entity_id where id = p_restaurant_id;
end
$$;
comment on function org.set_restaurant_legal_entity(uuid, uuid, text) is
  'Elige (o quita, con null) la razón social de un local. Pide org.manage en todo el grupo y un motivo.';

-- ---------------------------------------------------------------------------
-- 2. Permisos: configurar precios (Dirección General) y el Gerente ve precios y costos de su local
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permisos de precios (Fase 2, etapa 2.1 C)', 'maintenance');
  insert into core.permissions (code, module, action, description, is_sensitive) values
    ('prices.configure', 'prices', 'configure',
     'Cambiar el porcentaje de variación que pide también la aprobación de Dirección y los días para marcar un precio desactualizado.', true);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values ('general_management', 'prices.configure'),
                 -- Respuesta 7 de Soy (ADR-0024): el Gerente ve los costos y precios de su local, sin editarlos.
                 ('restaurant_manager', 'prices.view'),
                 ('restaurant_manager', 'recipes.view_costs')) as m (role_code, permission_code)
    join core.roles r on r.code = m.role_code
    join core.permissions p on p.code = m.permission_code;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Configuración de precios del grupo
-- ---------------------------------------------------------------------------
create table costing.price_settings (
  id                      uuid primary key default gen_random_uuid(),
  group_id                uuid not null references org.groups (id) on delete restrict,
  approval_variation_pct  numeric(5,2) not null default 15 check (approval_variation_pct > 0 and approval_variation_pct <= 100),
  stale_days              integer not null default 30 check (stale_days between 1 and 365),
  created_at              timestamptz not null default now(),
  created_by              uuid references core.actors (id) on delete restrict,
  updated_at              timestamptz not null default now(),
  updated_by              uuid references core.actors (id) on delete restrict,
  deleted_at              timestamptz,
  deleted_by              uuid references core.actors (id) on delete restrict
);
create unique index price_settings_group_key on costing.price_settings (group_id) where deleted_at is null;
comment on table costing.price_settings is
  'Configuración de precios de cada grupo. Sin fila, valen los valores por defecto (15 % y 30 días). La cambia solo Dirección General (prices.configure).';
comment on column costing.price_settings.id is 'Identificador.';
comment on column costing.price_settings.group_id is 'Grupo al que se aplica. Una fila por grupo.';
comment on column costing.price_settings.approval_variation_pct is
  'Si un precio sube o baja más que este porcentaje contra el costo que se usa hoy para esa materia prima en ese lugar (por unidad de uso, con o sin IVA), después del Controller aprueba también Dirección General.';
comment on column costing.price_settings.stale_days is 'Días desde la vigencia para marcar un precio como desactualizado (si su categoría no dice otro plazo).';
comment on column costing.price_settings.created_at is 'Cuándo se creó (lo pone la base).';
comment on column costing.price_settings.created_by is 'Quién la creó (lo pone la base).';
comment on column costing.price_settings.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column costing.price_settings.updated_by is 'Quién la cambió por última vez (lo pone la base).';
comment on column costing.price_settings.deleted_at is 'Baja lógica. Nunca se borra.';
comment on column costing.price_settings.deleted_by is 'Quién la dio de baja (lo pone la base).';

-- Los días por categoría ya existen desde la 2.1 A (catalog.ingredient_categories.stale_price_days):
-- vacío, vale el plazo del grupo.

-- ---------------------------------------------------------------------------
-- 4. Precios
-- ---------------------------------------------------------------------------
create type costing.price_document as enum ('invoice', 'no_invoice');
comment on type costing.price_document is
  'Comprobante del precio: factura con IVA discriminado, o "precio ingresado" sin factura (el precio es el final y no da crédito fiscal).';
create type costing.price_source as enum ('manual', 'test_value', 'excel_import', 'invoice');
comment on type costing.price_source is
  'De dónde viene un precio: carga manual, valor de prueba (simbólico, mientras no lleguen las facturas), importación de Excel o factura (reservado para la Fase 5).';

create table costing.price_records (
  id                   uuid primary key default gen_random_uuid(),
  entry_number         bigint generated always as identity,
  group_id             uuid not null references org.groups (id) on delete restrict,
  purchase_product_id  uuid not null,
  supplier_id          uuid,
  scope_type           core.scope_type not null,
  brand_id             uuid,
  restaurant_id        uuid,
  valid_from           date not null check (valid_from >= date '2000-01-01'),
  package_price        numeric(18,4) not null check (package_price > 0),
  currency             text not null default 'ARS' check (currency = 'ARS'),
  document_type        costing.price_document not null,
  vat_rate             numeric(5,2) check (vat_rate is null or vat_rate in (0, 10.5, 21, 27)),
  price_includes_vat   boolean not null default true,
  discount_amount      numeric(18,4) not null default 0 check (discount_amount >= 0),
  net_package_price    numeric(18,4) not null check (net_package_price > 0),
  gross_package_price  numeric(18,4) not null check (gross_package_price > 0),
  base_quantity        numeric(18,6) not null check (base_quantity > 0),
  source               costing.price_source not null,
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
  constraint price_records_product_fkey foreign key (purchase_product_id, group_id)
    references catalog.purchase_products (id, group_id) on delete restrict,
  constraint price_records_supplier_fkey foreign key (supplier_id, group_id)
    references catalog.suppliers (id, group_id) on delete restrict,
  constraint price_records_brand_fkey foreign key (brand_id, group_id)
    references org.brands (id, group_id) on delete restrict,
  constraint price_records_restaurant_fkey foreign key (restaurant_id, group_id)
    references org.restaurants (id, group_id) on delete restrict,
  constraint price_records_scope_check check (
    (scope_type = 'group' and brand_id is null and restaurant_id is null)
    or (scope_type = 'brand' and brand_id is not null and restaurant_id is null)
    or (scope_type = 'restaurant' and brand_id is null and restaurant_id is not null)),
  constraint price_records_vat_check check (
    (document_type = 'invoice' and vat_rate is not null) or (document_type = 'no_invoice' and vat_rate is null)),
  constraint price_records_discount_check check (discount_amount < package_price),
  constraint price_records_approval_check check (
    (approval_request_id is null) = (approved_by is null) and (approved_by is null) = (approved_at is null)
    and (approval_request_id is not null or source = 'test_value'))
);
create index price_records_lookup_idx on costing.price_records
  (purchase_product_id, scope_type, brand_id, restaurant_id, valid_from desc, entry_number desc) where deleted_at is null;
create index price_records_group_idx on costing.price_records (group_id, valid_from desc) where deleted_at is null;
create index price_records_brand_idx on costing.price_records (brand_id, group_id) where brand_id is not null;
create index price_records_restaurant_idx on costing.price_records (restaurant_id, group_id) where restaurant_id is not null;
create index price_records_supplier_idx on costing.price_records (supplier_id, group_id) where supplier_id is not null;
create index price_records_request_idx on costing.price_records (approval_request_id) where approval_request_id is not null;
create index price_records_approved_by_idx on costing.price_records (approved_by) where approved_by is not null;
comment on table costing.price_records is
  'Precios de compra aprobados, para siempre: un precio nuevo es un registro nuevo y nunca se cambia uno viejo. Cada uno vale para un producto de compra en el grupo, una marca o un local, desde una fecha.';
comment on column costing.price_records.id is 'Identificador del precio.';
comment on column costing.price_records.entry_number is
  'Orden de registro. Entre dos precios que empiezan a valer el mismo día, vale el registrado después.';
comment on column costing.price_records.group_id is 'Grupo al que pertenece. El mismo que el del producto.';
comment on column costing.price_records.purchase_product_id is 'Producto de compra (la presentación que se compra).';
comment on column costing.price_records.supplier_id is 'A quién se le compró a ese precio (opcional).';
comment on column costing.price_records.scope_type is 'Para quién vale: todo el grupo, una marca o un local.';
comment on column costing.price_records.brand_id is 'La marca, si el precio es de una marca.';
comment on column costing.price_records.restaurant_id is 'El local, si el precio es de un local.';
comment on column costing.price_records.valid_from is
  'Desde qué día vale. Para un local vale el último aprobado de cualquier producto de la materia prima, en el nivel más cercano (local, marca o grupo). No puede ser anterior al último precio del mismo producto y lugar.';
comment on column costing.price_records.package_price is 'Precio del envase completo tal como se cotizó (antes del descuento).';
comment on column costing.price_records.currency is 'Moneda. Solo ARS: nunca se convierte sin una cotización cargada.';
comment on column costing.price_records.document_type is 'Factura con IVA discriminado, o "precio ingresado" sin factura.';
comment on column costing.price_records.vat_rate is 'Alícuota de IVA en %: 0, 10,5, 21 o 27. Solo con factura.';
comment on column costing.price_records.price_includes_vat is 'Si el precio cargado ya incluye el IVA. Sin factura no se usa.';
comment on column costing.price_records.discount_amount is 'Descuento por envase, en pesos.';
comment on column costing.price_records.net_package_price is 'Precio del envase sin IVA, con el descuento (lo calcula la base). Sin factura, igual al bruto.';
comment on column costing.price_records.gross_package_price is 'Precio del envase con IVA, con el descuento (lo calcula la base).';
comment on column costing.price_records.base_quantity is
  'Contenido del envase en la unidad de uso de la materia prima (g, ml o unidad) al registrar el precio. El costo por unidad sale de acá: cambiar el contenido del producto o una conversión no mueve un precio aprobado.';
comment on column costing.price_records.source is 'De dónde viene: manual, valor de prueba, importación o factura.';
comment on column costing.price_records.approval_request_id is 'La solicitud que lo aprobó (la de Dirección, si hizo falta). Vacía solo en los valores de prueba.';
comment on column costing.price_records.approved_by is 'Quién dio la última aprobación.';
comment on column costing.price_records.approved_at is 'Cuándo se aprobó.';
comment on column costing.price_records.notes is 'Observaciones.';
comment on column costing.price_records.created_at is 'Cuándo se registró (lo pone la base).';
comment on column costing.price_records.created_by is 'Quién lo registró (lo pone la base).';
comment on column costing.price_records.updated_at is 'Igual a la creación: un precio no se cambia.';
comment on column costing.price_records.updated_by is 'Igual a la creación: un precio no se cambia.';
comment on column costing.price_records.deleted_at is 'Siempre vacía: un precio no se borra.';
comment on column costing.price_records.deleted_by is 'Siempre vacía: un precio no se borra.';

-- Neto y bruto de un envase: sin factura, el precio es el final; con factura, se separa el IVA.
create function costing.package_amounts(p_price numeric, p_discount numeric, p_document costing.price_document,
                                        p_vat_rate numeric, p_includes_vat boolean)
returns table (net_amount numeric, gross_amount numeric)
language sql
immutable
set search_path = ''
as $$
  select case when p_document = 'no_invoice' or not p_includes_vat then d
              else round(d / (1 + p_vat_rate / 100), 4) end,
         case when p_document = 'no_invoice' or p_includes_vat then d
              else round(d * (1 + p_vat_rate / 100), 4) end
    from (select p_price - coalesce(p_discount, 0) as d) x
$$;
comment on function costing.package_amounts(numeric, numeric, costing.price_document, numeric, boolean) is
  'Interna: el precio de un envase sin IVA y con IVA, con el descuento. Sin factura, los dos son el precio final.';
revoke execute on function costing.package_amounts(numeric, numeric, costing.price_document, numeric, boolean) from public;

create function costing.price_record_defaults()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_base numeric;
begin
  if tg_op <> 'INSERT' then
    raise exception 'Un precio aprobado no se cambia ni se borra: cargá un precio nuevo.' using errcode = '42501';
  end if;
  select a.net_amount, a.gross_amount into new.net_package_price, new.gross_package_price
    from costing.package_amounts(new.package_price, new.discount_amount, new.document_type, new.vat_rate,
                                 new.price_includes_vat) a;
  -- El contenido del envase en la unidad de uso, tal como está al registrar el precio (queda congelado).
  -- Si viene el aprobado (desde una solicitud), tiene que ser el mismo: así nada cambia entre el control y
  -- el registro (revisión de seguridad, cuarta pasada).
  select b.base_quantity into v_base
    from catalog.purchase_products pp
   cross join lateral catalog.to_base_quantity(pp.ingredient_id, pp.content_per_unit * pp.units_per_package,
                                               pp.content_unit_id) b
   where pp.id = new.purchase_product_id and b.status = 'ok';
  if coalesce(v_base, 0) <= 0 then
    raise exception 'El contenido de ese producto no se pasa a la unidad de uso de la materia prima: cargá primero su conversión.'
      using errcode = '23514';
  end if;
  if new.base_quantity is not null and new.base_quantity <> v_base then
    raise exception 'El contenido del producto cambió desde que se aprobó el precio: proponelo de nuevo.' using errcode = '23514';
  end if;
  new.base_quantity := v_base;
  return new;
end
$$;
comment on function costing.price_record_defaults() is
  'Trigger de costing.price_records: calcula neto, bruto y el contenido en la unidad de uso al registrar (queda congelado), y rechaza cualquier cambio o borrado (solo inserción).';
revoke execute on function costing.price_record_defaults() from public;

alter table costing.price_records enable row level security;
alter table costing.price_settings enable row level security;
revoke all on costing.price_records, costing.price_settings from public, anon, authenticated, service_role;
create trigger price_record_defaults before insert or update or delete on costing.price_records
  for each row execute function costing.price_record_defaults();
do $$
declare
  t text;
begin
  foreach t in array array['price_records', 'price_settings'] loop
    execute format('create trigger set_control_columns before insert or update on costing.%I
                      for each row execute function core.set_control_columns()', t);
    execute format('create trigger log_change after insert or update or delete on costing.%I
                      for each row execute function audit.log_change()', t);
    execute format('create trigger reject_truncate before truncate on costing.%I
                      for each statement execute function core.reject_truncate()', t);
  end loop;
end
$$;

-- Dónde ve precios la sesión. Un precio de marca lo ve quien tiene prices.view en la marca o en
-- alguno de sus locales; uno de grupo, quien lo tiene en cualquier lugar del grupo. Así un Gerente
-- ve los precios heredados que usa su local, pero no los de otra marca.
create function costing.price_view_brand_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b from core.permitted_brand_ids('prices.view') b
  union
  select r.brand_id from org.restaurants r where r.id in (select core.permitted_restaurant_ids('prices.view'))
$$;
comment on function costing.price_view_brand_ids() is
  'Marcas donde la sesión ve precios de marca: prices.view en toda la marca o en alguno de sus locales. Para políticas.';

create function costing.price_view_group_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select g from core.permitted_group_ids('prices.view') g
  union
  select b.group_id from org.brands b where b.id in (select costing.price_view_brand_ids())
$$;
comment on function costing.price_view_group_ids() is
  'Grupos donde la sesión ve precios de grupo: prices.view en cualquier lugar del grupo. Para políticas.';
revoke execute on function costing.price_view_brand_ids(), costing.price_view_group_ids() from public;
grant execute on function costing.price_view_brand_ids(), costing.price_view_group_ids() to authenticated;

create policy legal_entities_select on org.legal_entities for select to authenticated
  using (deleted_at is null and (group_id in (select costing.price_view_group_ids())
                                 or group_id in (select core.permitted_group_ids('org.manage'))));
create policy price_records_select on costing.price_records for select to authenticated
  using (deleted_at is null
         and ((scope_type = 'restaurant' and restaurant_id in (select core.permitted_restaurant_ids('prices.view')))
              or (scope_type = 'brand' and brand_id in (select costing.price_view_brand_ids()))
              or (scope_type = 'group' and group_id in (select costing.price_view_group_ids()))));
create policy price_settings_select on costing.price_settings for select to authenticated
  using (deleted_at is null and (group_id in (select costing.price_view_group_ids())
                                 or group_id in (select core.permitted_group_ids('prices.configure'))));
grant select on costing.price_records, costing.price_settings to authenticated;

-- Una materia prima con precios aprobados no cambia su unidad de uso: los precios guardan el contenido en
-- esa unidad. Y su categoría decide cuándo un precio está desactualizado: la cambia quien configura
-- precios (revisión de seguridad). Sin persona en la sesión (seed, migraciones) no se controla.
create function catalog.guard_priced_ingredient()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.recipe_unit_id is distinct from old.recipe_unit_id or new.category_id is distinct from old.category_id)
     and exists (select 1 from costing.price_records p join catalog.purchase_products pp on pp.id = p.purchase_product_id
                  where pp.ingredient_id = new.id and p.deleted_at is null) then
    if new.recipe_unit_id is distinct from old.recipe_unit_id then
      raise exception 'Esta materia prima ya tiene precios: su unidad de uso no cambia (los precios se guardaron en esa unidad).'
        using errcode = '23514';
    end if;
    if core.current_actor_id() is not null and not core.has_permission_in_group('prices.configure', new.group_id) then
      raise exception 'Esta materia prima ya tiene precios: cambiar su categoría cambia cuándo un precio está desactualizado, y eso lo decide Dirección General.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end
$$;
comment on function catalog.guard_priced_ingredient() is
  'Trigger de catalog.ingredients: con precios aprobados, la unidad de uso no cambia y la categoría la cambia solo quien tiene prices.configure.';
revoke execute on function catalog.guard_priced_ingredient() from public;
create trigger guard_priced_ingredient before update of recipe_unit_id, category_id on catalog.ingredients
  for each row execute function catalog.guard_priced_ingredient();

-- ---------------------------------------------------------------------------
-- 5. Configurar (Dirección General)
-- ---------------------------------------------------------------------------
create function costing.update_price_settings(p_group_id uuid, p_approval_variation_pct numeric, p_stale_days integer,
                                              p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission_in_group('prices.configure', p_group_id), 'cambiar la configuración de precios');
  if p_approval_variation_pct is null or p_stale_days is null then
    raise exception 'Faltan el porcentaje o los días.' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into costing.price_settings (group_id, approval_variation_pct, stale_days)
  values (p_group_id, p_approval_variation_pct, p_stale_days)
  on conflict (group_id) where deleted_at is null
  do update set approval_variation_pct = excluded.approval_variation_pct, stale_days = excluded.stale_days;
exception when check_violation then
  raise exception 'El porcentaje va de más de 0 a 100, y los días de 1 a 365.' using errcode = '23514';
end
$$;
comment on function costing.update_price_settings(uuid, numeric, integer, text) is
  'Cambia el porcentaje que pide también la aprobación de Dirección y los días de un precio desactualizado. Pide prices.configure en el grupo y un motivo.';

create function catalog.set_category_stale_days(p_category_id uuid, p_days integer, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group uuid;
begin
  select group_id into v_group from catalog.ingredient_categories where id = p_category_id and deleted_at is null;
  perform org.require(v_group is not null and core.has_permission_in_group('prices.configure', v_group),
                      'cambiar los días de precio desactualizado');
  perform core.set_change_context(p_reason, 'manual');
  update catalog.ingredient_categories set stale_price_days = p_days where id = p_category_id;
exception when check_violation then
  raise exception 'Los días van de 1 a 365 (vacío: el plazo del grupo).' using errcode = '23514';
end
$$;
comment on function catalog.set_category_stale_days(uuid, integer, text) is
  'Días para marcar desactualizado el precio de una categoría (null: el del grupo). Pide prices.configure en el grupo y un motivo.';

-- ---------------------------------------------------------------------------
-- 6. Proponer y aprobar un precio
-- ---------------------------------------------------------------------------
-- El precio que vale hoy para una materia prima en un lugar (local → marca → grupo, el último aprobado de
-- cualquiera de sus productos), por unidad de uso. Es la referencia de la variación de un precio nuevo.
create function costing.reference_price(p_ingredient_id uuid, p_scope core.scope_type, p_group_id uuid, p_brand_id uuid,
                                        p_restaurant_id uuid, p_as_of date)
returns table (price_record_id uuid, net_unit_cost numeric, gross_unit_cost numeric, valid_from date)
language sql
stable
security definer
set search_path = ''
as $$
  -- El último aprobado de cualquier producto de la materia prima, también de uno desactivado: desactivar
  -- un producto no borra el último costo conocido (revisión de seguridad).
  select p.id, p.net_package_price / p.base_quantity, p.gross_package_price / p.base_quantity, p.valid_from
    from catalog.purchase_products pp
    join costing.price_records p on p.purchase_product_id = pp.id
   where pp.ingredient_id = p_ingredient_id and pp.deleted_at is null
     and p.deleted_at is null and p.valid_from <= p_as_of and p.group_id = p_group_id
     and ((p_scope = 'restaurant' and p.scope_type = 'restaurant' and p.restaurant_id = p_restaurant_id)
          or (p_scope in ('restaurant', 'brand') and p.scope_type = 'brand'
              and p.brand_id = case when p_scope = 'restaurant'
                                    then (select r.brand_id from org.restaurants r where r.id = p_restaurant_id)
                                    else p_brand_id end)
          or p.scope_type = 'group')
   order by case p.scope_type when 'restaurant' then 1 when 'brand' then 2 else 3 end, p.valid_from desc, p.entry_number desc
   limit 1
$$;
comment on function costing.reference_price(uuid, core.scope_type, uuid, uuid, uuid, date) is
  'Interna: el precio que vale hoy para una materia prima en un lugar (con herencia y cualquier producto), por unidad de uso con y sin IVA. Referencia de la variación de un precio nuevo.';
revoke execute on function costing.reference_price(uuid, core.scope_type, uuid, uuid, uuid, date) from public;

-- La historia registrada no se reescribe (decisión de Joaco, 2026-11-02): un precio nuevo no empieza antes
-- que el último del mismo producto y lugar, ni antes que el precio que vale hoy en ese lugar (con herencia y
-- de cualquier producto; si no, un precio propio de un local con fecha vieja cambiaría su costo pasado).
create function costing.valid_from_floor(p_product_id uuid, p_scope core.scope_type, p_brand_id uuid, p_restaurant_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    (select max(p.valid_from) from costing.price_records p
      where p.purchase_product_id = p_product_id and p.scope_type = p_scope and p.deleted_at is null
        and p.brand_id is not distinct from p_brand_id and p.restaurant_id is not distinct from p_restaurant_id),
    (select r.valid_from
       from catalog.purchase_products pp
      cross join lateral costing.reference_price(pp.ingredient_id, p_scope, pp.group_id, p_brand_id, p_restaurant_id,
                                                 (now() at time zone 'America/Argentina/Buenos_Aires')::date) r
      where pp.id = p_product_id))
$$;
comment on function costing.valid_from_floor(uuid, core.scope_type, uuid, uuid) is
  'Interna: desde qué fecha puede empezar un precio nuevo: no antes del último del mismo producto y lugar, ni del que vale hoy en ese lugar (la historia no se reescribe).';
revoke execute on function costing.valid_from_floor(uuid, core.scope_type, uuid, uuid) from public;

create function costing.has_scope_permission(p_permission text, p_scope core.scope_type, p_group_id uuid, p_brand_id uuid,
                                             p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_scope
           when 'restaurant' then core.has_permission(p_permission, p_restaurant_id)
           when 'brand' then core.has_permission_in_brand(p_permission, p_brand_id)
           else core.has_permission_in_group(p_permission, p_group_id) end
$$;
comment on function costing.has_scope_permission(text, core.scope_type, uuid, uuid, uuid) is
  'Interna: si la sesión tiene el permiso para ese alcance (grupo, marca o local).';
revoke execute on function costing.has_scope_permission(text, core.scope_type, uuid, uuid, uuid) from public;

create function costing.propose_price(p_purchase_product_id uuid, p_scope_type text, p_brand_id uuid, p_restaurant_id uuid,
                                      p_valid_from date, p_package_price numeric, p_document_type text, p_vat_rate numeric,
                                      p_price_includes_vat boolean, p_discount_amount numeric, p_supplier_id uuid,
                                      p_source text, p_notes text, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product  catalog.purchase_products;
  v_ing      catalog.ingredients;
  v_scope    core.scope_type;
  v_doc      costing.price_document;
  v_net      numeric;
  v_gross    numeric;
  v_ref      record;
  v_ref_date date;
  v_floor    date;
  v_base     record;
  v_net_unit numeric;
  v_gross_unit numeric;
  v_var_net  numeric;
  v_var_gross numeric;
  v_variation numeric;
  v_request  uuid;
begin
  select * into v_product from catalog.purchase_products where id = p_purchase_product_id and deleted_at is null;
  if p_scope_type is null or p_scope_type not in ('group', 'brand', 'restaurant') then
    raise exception 'Elegí para quién vale el precio: el grupo, una marca o un local.' using errcode = '22023';
  end if;
  v_scope := p_scope_type::core.scope_type;
  perform org.require(v_product.id is not null
                      and costing.has_scope_permission('prices.propose', v_scope, v_product.group_id, p_brand_id, p_restaurant_id),
                      'proponer precios en ese lugar');
  if not v_product.is_active then
    raise exception 'Ese producto de compra está desactivado.' using errcode = '23514';
  end if;
  -- El alcance es del grupo del producto y coherente (una marca o un local, nunca los dos).
  if (v_scope = 'group' and (p_brand_id is not null or p_restaurant_id is not null))
     or (v_scope = 'brand' and (p_restaurant_id is not null
         or not exists (select 1 from org.brands where id = p_brand_id and group_id = v_product.group_id and deleted_at is null)))
     or (v_scope = 'restaurant' and (p_brand_id is not null
         or not exists (select 1 from org.restaurants where id = p_restaurant_id and group_id = v_product.group_id
                                                         and deleted_at is null))) then
    raise exception 'Elegí una marca o un local del grupo.' using errcode = '22023';
  end if;
  if p_supplier_id is not null
     and not exists (select 1 from catalog.suppliers where id = p_supplier_id and group_id = v_product.group_id
                                                     and is_active and deleted_at is null) then
    raise exception 'Elegí un proveedor vigente del grupo.' using errcode = '22023';
  end if;
  if length(p_notes) > 1000 then
    raise exception 'Las observaciones tienen hasta 1.000 caracteres.' using errcode = '22023';
  end if;
  if p_valid_from is null or p_valid_from < date '2000-01-01' or p_valid_from > (now() at time zone 'America/Argentina/Buenos_Aires')::date + 366 then
    raise exception 'Revisá la fecha desde la que vale el precio.' using errcode = '22023';
  end if;
  if p_package_price is null or p_package_price <= 0 or coalesce(p_discount_amount, 0) < 0
     or coalesce(p_discount_amount, 0) >= p_package_price then
    raise exception 'El precio tiene que ser mayor que cero y el descuento, menor que el precio.' using errcode = '22023';
  end if;
  if p_document_type is null or p_document_type not in ('invoice', 'no_invoice') then
    raise exception 'Elegí el comprobante: factura o precio ingresado.' using errcode = '22023';
  end if;
  v_doc := p_document_type::costing.price_document;
  if (v_doc = 'invoice' and (p_vat_rate is null or p_vat_rate not in (0, 10.5, 21, 27)))
     or (v_doc = 'no_invoice' and p_vat_rate is not null) then
    raise exception 'Con factura, elegí la alícuota de IVA (0, 10,5, 21 o 27); sin factura no lleva IVA.' using errcode = '22023';
  end if;
  -- Por ahora se cargan a mano o como valores de prueba (las facturas llegan en la Fase 5).
  if p_source is null or p_source not in ('manual', 'test_value') then
    raise exception 'El origen del precio es una carga manual o un valor de prueba.' using errcode = '22023';
  end if;

  -- Las propuestas de la misma materia prima, de a una por vez.
  select * into v_ing from catalog.ingredients where id = v_product.ingredient_id for update;
  v_floor := costing.valid_from_floor(p_purchase_product_id, v_scope, p_brand_id, p_restaurant_id);
  if v_floor is not null and p_valid_from < v_floor then
    raise exception 'Un precio nuevo no puede empezar antes que el que vale hoy en ese lugar (%). Cargalo desde esa fecha o después.',
      to_char(v_floor, 'DD/MM/YYYY') using errcode = '23514';
  end if;
  if exists (select 1 from workflow.approval_requests r
               join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code in ('costing.approve_price', 'costing.approve_price_direction') and r.status = 'pending'
                and r.deleted_at is null and r.entity_id = p_purchase_product_id
                and r.proposed_changes ->> 'scope_type' = p_scope_type
                and (r.proposed_changes ->> 'brand_id') is not distinct from p_brand_id::text
                and (r.proposed_changes ->> 'restaurant_id') is not distinct from p_restaurant_id::text
                and (r.proposed_changes ->> 'valid_from')::date = p_valid_from) then
    raise exception 'Ya hay un precio pendiente para ese producto, lugar y fecha: esperá a que se decida o pedí que lo retiren.'
      using errcode = '23505';
  end if;

  select a.net_amount, a.gross_amount into v_net, v_gross
    from costing.package_amounts(p_package_price, coalesce(p_discount_amount, 0), v_doc, p_vat_rate,
                                 coalesce(p_price_includes_vat, true)) a;
  -- El precio por unidad de uso (g, ml o unidad): así se compara con otro producto de otro tamaño.
  select b.base_quantity, b.status into v_base
    from catalog.to_base_quantity(v_product.ingredient_id, v_product.content_per_unit * v_product.units_per_package,
                                  v_product.content_unit_id) b;
  if v_base.status <> 'ok' or coalesce(v_base.base_quantity, 0) <= 0 then
    raise exception 'El contenido de ese producto no se pasa a la unidad de uso de la materia prima: cargá primero su conversión.'
      using errcode = '23514';
  end if;
  v_net_unit := v_net / v_base.base_quantity;
  v_gross_unit := v_gross / v_base.base_quantity;
  -- La variación es contra el costo que se usa hoy en ese lugar (con herencia y cualquier producto), con y
  -- sin IVA: la más grande de las dos. Sin referencia (el primer precio) alcanza con el Controller.
  v_ref_date := greatest(p_valid_from, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  select * into v_ref
    from costing.reference_price(v_product.ingredient_id, v_scope, v_product.group_id, p_brand_id, p_restaurant_id, v_ref_date);
  if v_ref.price_record_id is not null then
    v_var_net := round((v_net_unit - v_ref.net_unit_cost) / v_ref.net_unit_cost * 100, 2);
    v_var_gross := round((v_gross_unit - v_ref.gross_unit_cost) / v_ref.gross_unit_cost * 100, 2);
    v_variation := case when abs(v_var_gross) > abs(v_var_net) then v_var_gross else v_var_net end;
  end if;

  v_request := workflow.request_approval(
    'costing.approve_price', v_product.group_id,
    case when v_scope = 'brand' then p_brand_id
         when v_scope = 'restaurant' then (select brand_id from org.restaurants where id = p_restaurant_id) end,
    p_restaurant_id, null, p_purchase_product_id,
    jsonb_build_object('ingredient', v_ing.name, 'ingredient_id', v_ing.id, 'product', v_product.description,
                       'purchase_product_id', p_purchase_product_id, 'scope_type', p_scope_type,
                       'brand_id', p_brand_id, 'restaurant_id', p_restaurant_id, 'valid_from', p_valid_from,
                       'package_price', p_package_price, 'discount_amount', coalesce(p_discount_amount, 0),
                       'document_type', p_document_type, 'vat_rate', p_vat_rate,
                       'price_includes_vat', coalesce(p_price_includes_vat, true), 'supplier_id', p_supplier_id,
                       'source', p_source, 'notes', nullif(btrim(p_notes), ''),
                       'net_package_price', v_net, 'gross_package_price', v_gross,
                       'net_unit_cost', round(v_net_unit, 8), 'gross_unit_cost', round(v_gross_unit, 8),
                       'base_quantity', v_base.base_quantity, 'recipe_unit_id', v_ing.recipe_unit_id,
                       'price_variation_pct', v_variation,
                       'reference_price_record_id', v_ref.price_record_id, 'reference_as_of', v_ref_date),
    case when v_ref.price_record_id is null then jsonb_build_object('net_unit_cost', null)
         else jsonb_build_object('net_unit_cost', round(v_ref.net_unit_cost, 8),
                                 'gross_unit_cost', round(v_ref.gross_unit_cost, 8)) end,
    p_reason);
  return v_request;
end
$$;
comment on function costing.propose_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text, text, text) is
  'Propone un precio para un producto de compra en el grupo, una marca o un local: crea la solicitud costing.approve_price con el antes, el después y la variación contra el costo que se usa hoy en ese lugar. Pide prices.propose en ese lugar y un motivo. Devuelve el id de la solicitud.';

-- Lo que vio quien aprobó (la referencia de la variación) sigue siendo lo vigente, y la fecha sigue siendo válida.
create function costing.check_reference(p_req workflow.approval_requests)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c       jsonb := p_req.proposed_changes;
  v_product catalog.purchase_products;
  v_ref     uuid;
  v_base    numeric;
  v_floor   date;
begin
  select * into v_product from catalog.purchase_products
   where id = (v_c ->> 'purchase_product_id')::uuid and deleted_at is null;
  if v_product.id is null or not v_product.is_active then
    perform workflow.cannot_apply('el producto de compra ya no está vigente');
  end if;
  -- El contenido del envase (en la unidad de uso) es el mismo con el que se calculó la variación: si
  -- Compras lo cambió mientras tanto, lo que vio quien aprueba ya no es real (revisión de seguridad).
  select b.base_quantity into v_base
    from catalog.to_base_quantity(v_product.ingredient_id, v_product.content_per_unit * v_product.units_per_package,
                                  v_product.content_unit_id) b
   where b.status = 'ok';
  if v_base is distinct from (v_c ->> 'base_quantity')::numeric
     or (select i.recipe_unit_id from catalog.ingredients i where i.id = v_product.ingredient_id)
        is distinct from (v_c ->> 'recipe_unit_id')::uuid then
    perform workflow.cannot_apply('el contenido del producto cambió desde que se propuso; proponé de nuevo');
  end if;
  v_floor := costing.valid_from_floor(v_product.id, (v_c ->> 'scope_type')::core.scope_type, (v_c ->> 'brand_id')::uuid,
                                      (v_c ->> 'restaurant_id')::uuid);
  if v_floor is not null and (v_c ->> 'valid_from')::date < v_floor then
    perform workflow.cannot_apply(format('ya vale un precio desde el %s; proponé uno desde esa fecha o después',
                                         to_char(v_floor, 'DD/MM/YYYY')));
  end if;
  -- A la fecha de hoy (o la del precio, si es futura): si mientras tanto empezó a valer otro precio, la
  -- variación que vio quien aprobó ya no es la real.
  select r.price_record_id into v_ref
    from costing.reference_price(v_product.ingredient_id, (v_c ->> 'scope_type')::core.scope_type, v_product.group_id,
                                 (v_c ->> 'brand_id')::uuid, (v_c ->> 'restaurant_id')::uuid,
                                 greatest((v_c ->> 'valid_from')::date, (now() at time zone 'America/Argentina/Buenos_Aires')::date)) r;
  if v_ref is distinct from (v_c ->> 'reference_price_record_id')::uuid then
    perform workflow.cannot_apply('el precio vigente cambió desde que se propuso; proponé de nuevo con el valor actual');
  end if;
end
$$;
comment on function costing.check_reference(workflow.approval_requests) is
  'Interna: corta la aprobación si cambió algo de lo que vio quien aprueba: el contenido del producto, la fecha mínima o el precio de referencia.';
revoke execute on function costing.check_reference(workflow.approval_requests) from public;

create function costing.insert_approved_price(p_req workflow.approval_requests)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c       jsonb := p_req.proposed_changes;
  v_product catalog.purchase_products;
begin
  select * into v_product from catalog.purchase_products
   where id = (v_c ->> 'purchase_product_id')::uuid and deleted_at is null;
  if v_product.id is null or not v_product.is_active then
    perform workflow.cannot_apply('el producto de compra ya no está vigente');
  end if;
  perform 1 from catalog.ingredients where id = v_product.ingredient_id for update;
  perform costing.check_reference(p_req);
  insert into costing.price_records (group_id, purchase_product_id, supplier_id, scope_type, brand_id, restaurant_id,
                                     valid_from, package_price, document_type, vat_rate, price_includes_vat,
                                     discount_amount, source, approval_request_id, approved_by, approved_at, notes,
                                     base_quantity)
  values (v_product.group_id, v_product.id, (v_c ->> 'supplier_id')::uuid, (v_c ->> 'scope_type')::core.scope_type,
          (v_c ->> 'brand_id')::uuid, (v_c ->> 'restaurant_id')::uuid, (v_c ->> 'valid_from')::date,
          (v_c ->> 'package_price')::numeric, (v_c ->> 'document_type')::costing.price_document,
          (v_c ->> 'vat_rate')::numeric, (v_c ->> 'price_includes_vat')::boolean,
          (v_c ->> 'discount_amount')::numeric, (v_c ->> 'source')::costing.price_source,
          p_req.id, p_req.resolved_by, now(), v_c ->> 'notes', (v_c ->> 'base_quantity')::numeric);
end
$$;
comment on function costing.insert_approved_price(workflow.approval_requests) is
  'Interna: registra el precio de una solicitud aprobada, si el precio vigente sigue siendo el que vio quien aprobó.';
revoke execute on function costing.insert_approved_price(workflow.approval_requests) from public;

-- Aprobación del Controller. Si la variación supera el % del grupo, no aplica: pasa a Dirección.
create function costing.apply_price(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req       workflow.approval_requests := workflow.approved_request(p_request_id);
  v_threshold numeric;
  v_variation numeric := (v_req.proposed_changes ->> 'price_variation_pct')::numeric;
begin
  select approval_variation_pct into v_threshold from costing.price_settings
   where group_id = v_req.group_id and deleted_at is null;
  v_threshold := coalesce(v_threshold, 15);
  if v_variation is not null and abs(v_variation) > v_threshold then
    -- Antes de pasar a Dirección, lo vigente tiene que seguir igual.
    perform costing.check_reference(v_req);
    -- La segunda solicitud la decide Dirección General: ni quien propuso ni quien ya aprobó.
    perform workflow.request_approval(
      'costing.approve_price_direction', v_req.group_id, v_req.brand_id, v_req.restaurant_id, null, v_req.entity_id,
      v_req.proposed_changes || jsonb_build_object(
        'first_request_id', v_req.id, 'proposed_by', v_req.requested_by, 'first_approved_by', v_req.resolved_by,
        'approval_variation_pct', v_threshold,
        'excluded_approvers', jsonb_build_array(v_req.requested_by, v_req.resolved_by)),
      v_req.previous_values, v_req.reason);
    return;
  end if;
  perform costing.insert_approved_price(v_req);
end
$$;
comment on function costing.apply_price(uuid) is
  'Interna (aprobación costing.approve_price): registra el precio, o si la variación supera el % del grupo crea la solicitud para Dirección General (costing.approve_price_direction).';
revoke execute on function costing.apply_price(uuid) from public;

create function costing.apply_price_direction(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.insert_approved_price(workflow.approved_request(p_request_id));
end
$$;
comment on function costing.apply_price_direction(uuid) is
  'Interna (aprobación costing.approve_price_direction): Dirección General aprueba una variación grande y el precio se registra.';
revoke execute on function costing.apply_price_direction(uuid) from public;

-- Las funciones que aplican aprobaciones también pueden ser de costing (antes: core, org, catalog y recipes).
create or replace function workflow.check_apply_function()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
       select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where p.oid = new.apply_function::oid and n.nspname in ('core', 'org', 'catalog', 'recipes', 'costing')
          and p.proname like 'apply\_%'
          and p.pronargs = 1 and p.proargtypes[0] = 'uuid'::regtype and p.prorettype = 'void'::regtype) then
    raise exception 'La función que aplica una aprobación tiene que ser una de las funciones apply_* de core, org, catalog, recipes o costing.'
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

do $$
begin
  perform core.set_change_context('Aprobación de precios (Fase 2, etapa 2.1 C)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, approver_role_codes, min_approvers,
                                           apply_function, entity_table)
  values ('costing.approve_price', 'Precio de compra',
          'Un precio nuevo de un producto de compra. Lo propone Compras y lo aprueba el Controller de todo el grupo. Si la variación contra el costo que se usa hoy supera el % del grupo, pasa a Dirección General.',
          'prices.approve', array['controller'], 1, 'costing.apply_price(uuid)'::regprocedure, 'catalog.purchase_products');
  insert into workflow.approval_workflows (code, name, description, required_permission, approver_role_codes, min_approvers,
                                           apply_function, entity_table)
  values ('costing.approve_price_direction', 'Precio de compra con variación grande',
          'Segunda aprobación de un precio cuya variación contra el costo que se usa hoy en ese lugar supera el % del grupo. La da Dirección General, distinta de quien lo propuso y de quien ya lo aprobó.',
          'prices.approve', array['general_management'], 1, 'costing.apply_price_direction(uuid)'::regprocedure,
          'catalog.purchase_products');
end
$$;

-- ---------------------------------------------------------------------------
-- 7. Los precios de una solicitud, solo para quien ve precios (revisiones de base y de seguridad)
-- ---------------------------------------------------------------------------
-- El detalle de una solicitud sale solo por workflow.inbox, que oculta los importes a quien no los
-- puede ver. Hasta ahora ninguna solicitud traía precios de compra; desde la 2.1 C sí, y un Chef o un
-- Jefe de Cocina con approvals.view los leería directo de la tabla.
revoke select (proposed_changes) on workflow.approval_requests from authenticated;

create function workflow.can_see_amounts(p_workflow_code text, p_group_id uuid, p_brand_id uuid, p_restaurant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_workflow_code like 'costing.%'
              then costing.has_scope_permission('prices.view',
                     case when p_restaurant_id is not null then 'restaurant'
                          when p_brand_id is not null then 'brand' else 'group' end::core.scope_type,
                     p_group_id, p_brand_id, p_restaurant_id)
              else core.can_see_costs(p_group_id, p_brand_id, p_restaurant_id) end
$$;
comment on function workflow.can_see_amounts(text, uuid, uuid, uuid) is
  'Interna: si la sesión ve los importes de una solicitud: de un precio de compra, con prices.view en ese lugar (así Compras ve lo que propone y el Chef no); de las demás, con recipes.view_costs.';
revoke execute on function workflow.can_see_amounts(text, uuid, uuid, uuid) from public;

create or replace function workflow.inbox(p_pending boolean default true, p_limit integer default 50,
                               p_before_created_at timestamptz default null, p_before_id uuid default null)
returns table (id uuid, workflow_code text, workflow_name text, status workflow.request_status, requested_at timestamptz,
               requested_by_name text, summary text, reason text, place_name text, can_decide boolean,
               resolved_at timestamptz, resolved_by_name text, resolution_comment text,
               entity_table text, previous_values jsonb, proposed_changes jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := core.current_actor_id();
begin
  if v_actor is null or not core.current_session_ok() then
    return;
  end if;
  if (p_before_created_at is null) <> (p_before_id is null) then
    raise exception 'La página siguiente necesita la fecha y el id.' using errcode = '22023';
  end if;
  return query
  -- Primero se filtra, ordena y limita (por conjuntos, una vez por consulta); recién después se
  -- arma el resumen de las pocas filas que quedan.
  with page as (
    select r.*
      from workflow.approval_requests r
     where r.deleted_at is null
       and ((p_pending and r.status = 'pending') or (not p_pending and r.status <> 'pending'))
       and (p_before_created_at is null or (r.created_at, r.id) < (p_before_created_at, p_before_id))
       and (r.requested_by = v_actor or r.subject_user_id = v_actor
            or (r.brand_id is null and r.group_id in (select core.permitted_group_ids('approvals.view')))
            or (r.brand_id is not null and r.restaurant_id is null and r.brand_id in (select core.permitted_brand_ids('approvals.view')))
            or (r.restaurant_id in (select core.permitted_restaurant_ids('approvals.view'))))
     order by r.created_at desc, r.id desc
     limit least(greatest(coalesce(p_limit, 50), 1), 100)
  )
  select r.id, w.code, w.name, r.status, r.requested_at, core.display_name(r.requested_by),
         case
           when w.code in ('core.assign_sensitive_role', 'core.assign_superadmin', 'core.assign_by_superadmin') then
             'Dar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.revoke_by_superadmin' then
             'Quitar el rol ' || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
             || ' a ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           when w.code = 'core.change_role_permission' then
             case when (r.proposed_changes ->> 'grant')::boolean then 'Dar el permiso ' else 'Quitar el permiso ' end
             || (r.proposed_changes ->> 'permission_code') || ' al rol '
             || coalesce((select ro.name from core.roles ro where ro.id = (r.proposed_changes ->> 'role_id')::uuid), r.proposed_changes ->> 'role_code')
           when w.code = 'org.transfer_restaurant' then
             'Traspasar ' || coalesce((select rs.name from org.restaurants rs where rs.id = (r.proposed_changes ->> 'restaurant_id')::uuid), 'un local')
             || ' a la marca ' || coalesce((select b.name from org.brands b where b.id = (r.proposed_changes ->> 'target_brand_id')::uuid), '')
           when w.code in ('core.change_general_management_status', 'core.change_superadmin_status') then
             case when r.proposed_changes ->> 'status' in ('deactivated', 'suspended', 'active') then
               case r.proposed_changes ->> 'status' when 'deactivated' then 'Dar de baja a ' when 'suspended' then 'Suspender a '
                    else 'Reactivar la cuenta de ' end
               || coalesce(core.display_name(r.subject_user_id), 'una persona')
               || case when w.code = 'core.change_general_management_status' then ' (Dirección General)' else ' (Superadministrador)' end
             else w.name end
           when w.code = 'core.reactivate_user' then
             'Reactivar la cuenta de ' || coalesce(core.display_name(r.subject_user_id), 'una persona')
           else w.name
         end,
         r.reason,
         coalesce((select rs.name from org.restaurants rs where rs.id = r.restaurant_id),
                  (select b.name from org.brands b where b.id = r.brand_id),
                  (select g.name from org.groups g where g.id = r.group_id)),
         r.status = 'pending' and workflow.decision_blocker(r.id) is null,
         r.resolved_at, core.display_name(r.resolved_by), r.resolution_comment,
         r.entity_table,
         (case when workflow.can_see_amounts(w.code, r.group_id, r.brand_id, r.restaurant_id) then r.previous_values
               else core.hide_costs(r.previous_values) end)
           -- El motivo de una baja, solo para quien administra a la persona o puede decidir (respuesta 2).
           - case when r.subject_user_id is null or core.can_administer_user(r.subject_user_id)
                       or (r.status = 'pending' and workflow.decision_blocker(r.id) is null)
                  then '' else 'deactivation_reason' end,
         -- Lo técnico del pedido (a quiénes excluye, la foto de permisos) no se muestra.
         case when workflow.can_see_amounts(w.code, r.group_id, r.brand_id, r.restaurant_id)
              then r.proposed_changes - 'excluded_approvers' - 'role_permissions'
              else core.hide_costs(r.proposed_changes - 'excluded_approvers' - 'role_permissions') end
    from page r
    join workflow.approval_workflows w on w.id = r.workflow_id
   order by r.created_at desc, r.id desc;
end
$$;

-- ---------------------------------------------------------------------------
-- 8. Qué precio vale para un local y cuánto cuesta una línea
-- ---------------------------------------------------------------------------
-- status: ok, missing_price (nunca $ 0) o missing_legal_entity (el local no tiene razón social: no se sabe si
-- el IVA se recupera; el costo con IVA igual se ve). El costo por unidad sale del contenido congelado de cada precio. El costo que usa el motor es el neto si hay factura y la razón social
-- es responsable inscripta; si no, el bruto.
-- Todo en una sola consulta (para listas y tableros: 500 materias primas en una pasada). Con
-- p_ingredient_id, una sola. Sin el local, ninguna fila.
create function costing.price_rows(p_restaurant_id uuid, p_as_of date, p_ingredient_id uuid)
returns table (ingredient_id uuid, price_record_id uuid, purchase_product_id uuid, product_description text,
               price_level text, inherited boolean, valid_from date, document_type text, net_unit_cost numeric,
               gross_unit_cost numeric, unit_cost numeric, base_unit text, stale boolean, status text)
language sql
stable
security definer
set search_path = ''
as $$
  with rest as (
    select r.id, r.group_id, r.brand_id, l.vat_condition
      from org.restaurants r
      left join org.legal_entities l on l.id = r.legal_entity_id and l.deleted_at is null
     where r.id = p_restaurant_id and r.deleted_at is null
  ), pick as (
    -- Local → marca → grupo; en el nivel más cercano con precio, el último aprobado de cualquiera de
    -- los productos de la materia prima (también de uno desactivado: es el último costo conocido).
    select i.id as ing_id, u.code as unit_code, coalesce(c.stale_price_days, s.stale_days, 30) as stale_days,
           rest.vat_condition, x.*
      from rest
      join catalog.ingredients i on i.group_id = rest.group_id and i.deleted_at is null
                                and (p_ingredient_id is null or i.id = p_ingredient_id)
      join catalog.units u on u.id = i.recipe_unit_id
      join catalog.ingredient_categories c on c.id = i.category_id
      left join costing.price_settings s on s.group_id = rest.group_id and s.deleted_at is null
      left join lateral (
        select p.id as rec_id, p.scope_type as rec_scope, p.valid_from as rec_valid_from, p.document_type as rec_doc,
               p.net_package_price / p.base_quantity as net_unit, p.gross_package_price / p.base_quantity as gross_unit,
               pp.id as product_id, pp.description as product
          from catalog.purchase_products pp
          join costing.price_records p on p.purchase_product_id = pp.id
         where pp.ingredient_id = i.id and pp.deleted_at is null
           and p.deleted_at is null and p.valid_from <= p_as_of
           and ((p.scope_type = 'restaurant' and p.restaurant_id = rest.id)
                or (p.scope_type = 'brand' and p.brand_id = rest.brand_id)
                or p.scope_type = 'group')
         order by case p.scope_type when 'restaurant' then 1 when 'brand' then 2 else 3 end, p.valid_from desc,
                  p.entry_number desc
         limit 1) x on true
  )
  select ing_id, rec_id, product_id, product, rec_scope::text, case when rec_id is not null then rec_scope <> 'restaurant' end,
         rec_valid_from, rec_doc::text, round(net_unit, 8), round(gross_unit, 8),
         -- El costo: el neto si hay factura y la razón social es responsable inscripta; si no, el bruto.
         case when rec_id is null then null
              when rec_doc = 'no_invoice' then round(gross_unit, 8)
              when vat_condition is null then null
              when vat_condition = 'registered' then round(net_unit, 8)
              else round(gross_unit, 8) end,
         unit_code,
         case when rec_id is not null then p_as_of - rec_valid_from > stale_days end,
         case when rec_id is null then 'missing_price'
              when rec_doc = 'invoice' and vat_condition is null then 'missing_legal_entity'
              else 'ok' end
    from pick
$$;
comment on function costing.price_rows(uuid, date, uuid) is
  'Interna (la usa el motor de costos): para cada materia prima del grupo de un local (o una sola), el precio que vale a una fecha, su nivel (local, marca o grupo), el costo por unidad de uso con IVA, sin IVA y el que cuenta, si está desactualizado y su estado.';
revoke execute on function costing.price_rows(uuid, date, uuid) from public;

create function costing.resolve_price_internal(p_ingredient_id uuid, p_restaurant_id uuid, p_as_of date)
returns table (price_record_id uuid, purchase_product_id uuid, product_description text, price_level text, inherited boolean,
               valid_from date, document_type text, net_unit_cost numeric, gross_unit_cost numeric, unit_cost numeric,
               base_unit text, stale boolean, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select r.price_record_id, r.purchase_product_id, r.product_description, r.price_level, r.inherited,
                      r.valid_from, r.document_type, r.net_unit_cost, r.gross_unit_cost, r.unit_cost, r.base_unit,
                      r.stale, r.status
                 from costing.price_rows(p_restaurant_id, p_as_of, p_ingredient_id) r;
  if not found then
    return query select null::uuid, null::uuid, null::text, null::text, null::boolean, null::date, null::text,
                        null::numeric, null::numeric, null::numeric, null::text, null::boolean, 'missing_price'::text;
  end if;
end
$$;
comment on function costing.resolve_price_internal(uuid, uuid, date) is
  'Interna (la usa el motor de costos): costing.price_rows para una materia prima; siempre una fila (missing_price si no hay precio o local).';
revoke execute on function costing.resolve_price_internal(uuid, uuid, date) from public;

create function costing.resolve_price(p_ingredient_id uuid, p_restaurant_id uuid, p_as_of date default (now() at time zone 'America/Argentina/Buenos_Aires')::date)
returns table (price_record_id uuid, purchase_product_id uuid, product_description text, price_level text, inherited boolean,
               valid_from date, document_type text, net_unit_cost numeric, gross_unit_cost numeric, unit_cost numeric,
               base_unit text, stale boolean, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission('prices.view', p_restaurant_id), 'ver precios de este local');
  return query select * from costing.resolve_price_internal(p_ingredient_id, p_restaurant_id, coalesce(p_as_of, (now() at time zone 'America/Argentina/Buenos_Aires')::date));
end
$$;
comment on function costing.resolve_price(uuid, uuid, date) is
  'El precio que vale para una materia prima en un local a una fecha (local → marca → grupo, el último aprobado). Pide prices.view en el local.';

-- Los precios de todas las materias primas del grupo para un local (listas y tableros), en una pasada.
create function costing.resolve_prices(p_restaurant_id uuid, p_as_of date default (now() at time zone 'America/Argentina/Buenos_Aires')::date)
returns table (ingredient_id uuid, price_record_id uuid, purchase_product_id uuid, product_description text,
               price_level text, inherited boolean, valid_from date, document_type text, net_unit_cost numeric,
               gross_unit_cost numeric, unit_cost numeric, base_unit text, stale boolean, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission('prices.view', p_restaurant_id), 'ver precios de este local');
  return query select * from costing.price_rows(p_restaurant_id, coalesce(p_as_of, (now() at time zone 'America/Argentina/Buenos_Aires')::date), null);
end
$$;
comment on function costing.resolve_prices(uuid, date) is
  'Los precios que valen en un local a una fecha para todas las materias primas del grupo (una fila por materia prima, con su estado). Pide prices.view en el local.';

-- Costo de una línea: cantidad a la unidad de uso, rendimiento estándar si va limpia o cocida, y precio.
-- basis: purchase (como se compra), clean (limpia) o cooked (cocida). Nunca da $ 0: si falta algo, el
-- costo queda vacío y el estado dice qué falta.
create function costing.ingredient_line_cost(p_ingredient_id uuid, p_restaurant_id uuid, p_quantity numeric, p_unit_id uuid,
                                             p_basis text default 'purchase', p_process_id uuid default null,
                                             p_as_of date default (now() at time zone 'America/Argentina/Buenos_Aires')::date)
returns table (base_quantity numeric, purchase_quantity numeric, unit_cost numeric, line_cost numeric, price_level text,
               inherited boolean, price_record_id uuid, status text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_base   record;
  v_yield  record;
  v_qty    numeric;
  v_price  record;
begin
  perform org.require(core.has_permission('prices.view', p_restaurant_id)
                      and exists (select 1 from catalog.ingredients i join org.restaurants r on r.group_id = i.group_id
                                   where i.id = p_ingredient_id and r.id = p_restaurant_id),
                      'ver costos de este local');
  if p_basis is null or p_basis not in ('purchase', 'clean', 'cooked') then
    raise exception 'La cantidad va como se compra, limpia o cocida.' using errcode = '22023';
  end if;
  select b.base_quantity, b.status into v_base from catalog.to_base_quantity(p_ingredient_id, p_quantity, p_unit_id) b;
  if v_base.status <> 'ok' then
    return query select null::numeric, null::numeric, null::numeric, null::numeric, null::text, null::boolean, null::uuid,
                        v_base.status;
    return;
  end if;
  v_qty := v_base.base_quantity;
  if p_basis <> 'purchase' then
    select y.cleaning_yield, y.cooking_factor, y.status into v_yield
      from catalog.standard_yield(p_ingredient_id, p_process_id) y;
    if p_process_id is null or v_yield.status <> 'approved' or coalesce(v_yield.cleaning_yield, 0) <= 0
       or (p_basis = 'cooked' and coalesce(v_yield.cooking_factor, 0) <= 0) then
      return query select v_base.base_quantity, null::numeric, null::numeric, null::numeric, null::text, null::boolean,
                          null::uuid, 'missing_yield'::text;
      return;
    end if;
    v_qty := case when p_basis = 'clean' then v_qty / v_yield.cleaning_yield
                  else v_qty / (v_yield.cleaning_yield * v_yield.cooking_factor) end;
  end if;
  select * into v_price from costing.resolve_price_internal(p_ingredient_id, p_restaurant_id, coalesce(p_as_of, (now() at time zone 'America/Argentina/Buenos_Aires')::date));
  return query select v_base.base_quantity, v_qty, v_price.unit_cost,
                      case when v_price.unit_cost is null then null else v_qty * v_price.unit_cost end,
                      v_price.price_level, v_price.inherited, v_price.price_record_id,
                      case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity'
                           else v_price.status end;
end
$$;
comment on function costing.ingredient_line_cost(uuid, uuid, numeric, uuid, text, uuid, date) is
  'Costo de una línea de materia prima en un local: pasa la cantidad a la unidad de uso, aplica el rendimiento estándar (limpia o cocida) y el precio que vale. Estados: ok, missing_conversion, missing_yield, missing_price o missing_legal_entity (nunca $ 0). Pide prices.view en el local.';

do $$
declare
  f text;
begin
  foreach f in array array[
    'org.create_legal_entity(uuid, text, text, text, text)',
    'org.update_legal_entity(uuid, jsonb, text)',
    'org.set_restaurant_legal_entity(uuid, uuid, text)',
    'costing.update_price_settings(uuid, numeric, integer, text)',
    'catalog.set_category_stale_days(uuid, integer, text)',
    'costing.propose_price(uuid, text, uuid, uuid, date, numeric, text, numeric, boolean, numeric, uuid, text, text, text)',
    'costing.resolve_price(uuid, uuid, date)',
    'costing.resolve_prices(uuid, date)',
    'costing.ingredient_line_cost(uuid, uuid, numeric, uuid, text, uuid, date)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$$;
