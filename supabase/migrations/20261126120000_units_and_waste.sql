-- Medidas, mermas y rendimientos (pedido de Soy; ADR-0040). Solo aditiva: el costo de lo que ya está cargado no
-- cambia (lo prueba 270_units_and_waste).
--   1. Unidades: nombre largo y abreviatura («Kilogramo (kg)») y las medidas de recetario que faltaban (mg, lb, oz,
--      cc, taza, cucharada, cucharadita, onza líquida, pizca y porción), cada una con su conversión a la base.
--      catalog.create_unit suma otras. Las unidades son de todo el sistema (como antes).
--   2. Descongelado: la marca «se compra congelada» en la materia prima y el proceso DESCONGELADO. Su estándar
--      aprobado (cleaning_yield = 1 − merma) se suma, en el motor, al rendimiento de las líneas limpias o cocidas.
--      Sin estándar de descongelado, la línea queda RENDIMIENTO NO DEFINIDO: nunca se supone 0 % de merma.
--   3. Mermas en %: catalog.propose_waste propone, en una sola transacción, los estándares de limpieza y de
--      descongelado. Los aprueba un Chef de todo el grupo, como cualquier rendimiento (ADR-0021, decisión de Joaco).
--   4. Merma de cocción informativa de una receta (recipes.cooking_loss): peso terminado / peso de las líneas.
--   5. Decisiones de Joaco después de las revisiones (2026-11-11): dejar de comprar congelada (que baja el costo)
--      pide la aprobación de un Chef de todo el grupo; marcarla es directo. Una unidad que nada usó se puede dar de
--      baja (catalog.archive_unit), para corregir un error de carga.
--   El rendimiento final de una receta ya es obligatorio para pedir la revisión (recipes.request_review).

-- ---------------------------------------------------------------------------
-- 1. Unidades
-- ---------------------------------------------------------------------------
alter table catalog.units
  add column long_name    text check (long_name is null or length(btrim(long_name)) between 1 and 40),
  add column abbreviation text check (abbreviation is null or length(btrim(abbreviation)) between 1 and 12);
comment on column catalog.units.long_name is 'Nombre completo, en español («Kilogramo»). Se muestra con la abreviatura: «Kilogramo (kg)».';
comment on column catalog.units.name is 'Nombre corto de siempre (g, kg, unidad, docena…). Las unidades nuevas lo copian de la abreviatura.';
comment on column catalog.units.abbreviation is 'Abreviatura que se muestra junto a las cantidades («kg», «cda»).';

do $$
begin
  perform core.set_change_context('Unidades con nombre y abreviatura, y las medidas de recetario (ADR-0040)', 'maintenance');
  update catalog.units u
     set long_name = v.long_name, abbreviation = v.abbreviation
    from (values ('g', 'Gramo', 'g'), ('kg', 'Kilogramo', 'kg'), ('ml', 'Mililitro', 'ml'), ('l', 'Litro', 'l'),
                 ('unit', 'Unidad', 'u'), ('dozen', 'Docena', 'doc'), ('pack', 'Paquete', 'paq'), ('box', 'Caja', 'caja'),
                 ('bag', 'Bolsa', 'bolsa'), ('bottle', 'Botella', 'bot'), ('can', 'Lata', 'lata'), ('bunch', 'Atado', 'atado'),
                 ('wheel', 'Horma', 'horma'), ('jug', 'Bidón', 'bidón')) as v (code, long_name, abbreviation)
   where u.code = v.code and u.deleted_at is null;
  -- Alguna unidad cargada después, sin nombre largo: su nombre de siempre.
  update catalog.units set long_name = name where long_name is null;
  update catalog.units set abbreviation = left(name, 12) where abbreviation is null;

  insert into catalog.units (code, name, long_name, abbreviation, dimension, is_base)
  select v.code, v.abbreviation, v.long_name, v.abbreviation, v.dimension::catalog.dimension, false
    from (values ('mg', 'Miligramo', 'mg', 'mass'), ('lb', 'Libra', 'lb', 'mass'), ('oz', 'Onza', 'oz', 'mass'),
                 ('pinch', 'Pizca', 'pizca', 'mass'), ('cc', 'Centímetro cúbico', 'cc', 'volume'),
                 ('cup', 'Taza', 'taza', 'volume'), ('tbsp', 'Cucharada', 'cda', 'volume'),
                 ('tsp', 'Cucharadita', 'cdta', 'volume'), ('fl_oz', 'Onza líquida', 'fl oz', 'volume'),
                 ('portion', 'Porción', 'porción', 'count')) as v (code, long_name, abbreviation, dimension)
   where not exists (select 1 from catalog.units x where x.code = v.code and x.deleted_at is null);

  -- Factores hacia la base de su dimensión. La pizca vale 0,5 g y la porción, una unidad (pedido de Soy, plan aprobado).
  insert into catalog.unit_conversions (from_unit_id, to_unit_id, factor)
  select f.id, t.id, c.factor
    from (values ('mg', 'g', 0.001), ('lb', 'g', 453.59237), ('oz', 'g', 28.349523), ('pinch', 'g', 0.5),
                 ('cc', 'ml', 1), ('cup', 'ml', 240), ('tbsp', 'ml', 15), ('tsp', 'ml', 5), ('fl_oz', 'ml', 29.57353),
                 ('portion', 'unit', 1)) as c (from_code, to_code, factor)
    join catalog.units f on f.code = c.from_code and f.deleted_at is null
    join catalog.units t on t.code = c.to_code and t.deleted_at is null
   where not exists (select 1 from catalog.unit_conversions x where x.from_unit_id = f.id and x.deleted_at is null);
end
$$;

alter table catalog.units
  alter column long_name set not null,
  alter column abbreviation set not null;

-- Suma una unidad nueva con su conversión a la base. Las unidades valen para todo el sistema: la crea quien administra
-- el catálogo de un grupo, con motivo y auditoría. Los envases no tienen conversión fija.
create function catalog.create_unit(p_group_id uuid, p_code text, p_long_name text, p_abbreviation text,
                                    p_dimension catalog.dimension, p_reason text, p_factor numeric default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id         uuid;
  v_base       uuid;
  v_constraint text;
  v_message    text;
begin
  perform org.require(core.has_permission_in_group('catalog.manage', p_group_id), 'crear unidades');
  if p_dimension is null then
    raise exception 'Elegí si es de peso, volumen, unidades o un envase.' using errcode = '22023';
  end if;
  if p_dimension = 'package' and p_factor is not null then
    raise exception 'Un envase no tiene un contenido fijo: va sin conversión.' using errcode = '22023';
  end if;
  if p_dimension <> 'package' and (p_factor is null or p_factor <= 0) then
    raise exception 'Falta cuánto vale en la unidad base (g, ml o unidad).' using errcode = '22023';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  insert into catalog.units (code, name, long_name, abbreviation, dimension, is_base)
  values (lower(btrim(p_code)), btrim(p_abbreviation), btrim(p_long_name), btrim(p_abbreviation), p_dimension, false)
  returning id into v_id;
  if p_dimension <> 'package' then
    select id into v_base from catalog.units where dimension = p_dimension and is_base and deleted_at is null;
    insert into catalog.unit_conversions (from_unit_id, to_unit_id, factor) values (v_id, v_base, p_factor);
  end if;
  return v_id;
exception when unique_violation or check_violation or numeric_value_out_of_range then
  get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
  if v_constraint = 'units_code_key' then
    raise exception 'Ya hay una unidad con ese código.' using errcode = '23505';
  end if;
  if sqlstate = '22003' then
    raise exception 'El factor es demasiado grande.' using errcode = '22003';
  end if;
  perform catalog.raise_friendly(sqlstate, v_constraint, v_message);
end
$$;
comment on function catalog.create_unit(uuid, text, text, text, catalog.dimension, text, numeric) is
  'Crea una unidad (código en minúsculas, nombre largo y abreviatura) y su conversión a la base de su dimensión (sin conversión si es un envase). Las unidades son de todo el sistema: pide catalog.manage en un grupo y un motivo.';
revoke execute on function catalog.create_unit(uuid, text, text, text, catalog.dimension, text, numeric) from public, anon;
grant execute on function catalog.create_unit(uuid, text, text, text, catalog.dimension, text, numeric) to authenticated;

-- Si algo usa (o usó) una unidad: cualquier fila de las tablas que la referencian, también las borradas y las fotos de
-- costos (la historia no se toca). Las conversiones de la propia unidad no cuentan. Se arma con las claves foráneas
-- de la base: una tabla nueva que use unidades queda incluida sola.
create function catalog.unit_in_use(p_unit_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r     record;
  v_hit boolean;
begin
  for r in
    select c.conrelid::regclass as tbl, a.attname as col
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
     where c.contype = 'f' and c.confrelid = 'catalog.units'::regclass
       and c.conrelid <> 'catalog.unit_conversions'::regclass
  loop
    execute format('select exists (select 1 from %s where %I = $1)', r.tbl, r.col) into v_hit using p_unit_id;
    if v_hit then
      return true;
    end if;
  end loop;
  return false;
end
$$;
comment on function catalog.unit_in_use(uuid) is
  'Si una unidad se usa o se usó en algún lado (materias primas, productos, recetas, pasos, fotos de costos). Busca por las claves foráneas que apuntan a catalog.units.';
revoke execute on function catalog.unit_in_use(uuid) from public, anon;
grant execute on function catalog.unit_in_use(uuid) to authenticated;

-- Da de baja una unidad cargada a mano que nada usó (para corregir un error de carga: se da de baja y se crea bien).
-- Las base, las del sistema y las que ya se usan no se tocan nunca. Pide catalog.manage en un grupo y un motivo; la baja es lógica, con su conversión.
create function catalog.archive_unit(p_group_id uuid, p_unit_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_unit catalog.units;
begin
  perform org.require(core.has_permission_in_group('catalog.manage', p_group_id), 'dar de baja unidades');
  select * into v_unit from catalog.units where id = p_unit_id and deleted_at is null for update;
  if not found then
    raise exception 'La unidad ya no está vigente.' using errcode = '22023';
  end if;
  if v_unit.is_base then
    raise exception 'Las unidades base (g, ml y unidad) no se dan de baja.' using errcode = '23514';
  end if;
  -- Las que trae el sistema (las cargan las migraciones, sin autor) las usan las recetas desde lib/recipe-format.ts.
  if v_unit.created_by is null then
    raise exception 'Las unidades del sistema no se dan de baja: solo las que se cargaron a mano.' using errcode = '23514';
  end if;
  if catalog.unit_in_use(p_unit_id) then
    raise exception 'La unidad «%» ya se usa: no se da de baja.', v_unit.long_name using errcode = '23514';
  end if;
  perform core.set_change_context(p_reason, 'manual');
  update catalog.unit_conversions set deleted_at = now() where from_unit_id = p_unit_id and deleted_at is null;
  update catalog.units set deleted_at = now() where id = p_unit_id;
end
$$;
comment on function catalog.archive_unit(uuid, uuid, text) is
  'Da de baja (lógica) una unidad cargada a mano que nada usa ni usó, con su conversión. Nunca una base, una del sistema ni una en uso. Pide catalog.manage en un grupo y un motivo.';
revoke execute on function catalog.archive_unit(uuid, uuid, text) from public, anon;
grant execute on function catalog.archive_unit(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Descongelado
-- ---------------------------------------------------------------------------
alter table catalog.ingredients add column requires_thawing boolean not null default false;
comment on column catalog.ingredients.requires_thawing is
  'Se compra congelada: el costo de sus líneas limpias o cocidas suma la merma de descongelado (estándar aprobado del proceso DESCONGELADO). Sin ese estándar, la línea queda RENDIMIENTO NO DEFINIDO.';

-- Los procesos de limpieza y de descongelado en cada grupo que ya existe (los grupos nuevos se cargan con los suyos;
-- el seed los trae). Si el grupo ya tiene uno con ese código o ese nombre, queda el suyo.
do $$
begin
  perform core.set_change_context('Procesos de limpieza y descongelado para las mermas (ADR-0040)', 'maintenance');
  insert into catalog.yield_processes (group_id, code, name)
  select g.id, p.code, p.name
    from org.groups g
   cross join (values ('LIMPIEZA', 'Limpieza'), ('DESCONGELADO', 'Descongelado')) as p (code, name)
   where g.deleted_at is null
     and not exists (select 1 from catalog.yield_processes y
                      where y.group_id = g.id and y.deleted_at is null and (y.code = p.code or lower(y.name) = lower(p.name)));
  -- Un grupo que ya usa ese nombre con otro código no recibe el proceso: las mermas lo buscan por código y avisan que
  -- falta. Queda dicho en el registro de la migración.
  if exists (select 1 from org.groups g
               cross join (values ('LIMPIEZA'), ('DESCONGELADO')) as p (code)
              where g.deleted_at is null
                and not exists (select 1 from catalog.yield_processes y
                                 where y.group_id = g.id and y.code = p.code and y.deleted_at is null)) then
    raise notice 'Hay grupos sin el proceso LIMPIEZA o DESCONGELADO (el nombre ya lo usa otro proceso): créenlo con ese código.';
  end if;
end
$$;

-- Marcar «se compra congelada» se aplica en el momento: solo puede dejar el costo incompleto (sin merma aprobada) o
-- subirlo. Desmarcar baja el costo: queda como solicitud que aprueba un Chef de todo el grupo, nunca quien la pidió
-- (decisión de Joaco, 2026-11-11). Devuelve {result: applied | pending_approval | unchanged}.
create function catalog.set_requires_thawing(p_ingredient_id uuid, p_value boolean, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_group   uuid := catalog.ingredient_group(p_ingredient_id);
  v_ing     catalog.ingredients;
  v_request uuid;
begin
  if p_value is null then
    raise exception 'Elegí si se compra congelada.' using errcode = '22023';
  end if;
  select * into v_ing from catalog.ingredients where id = p_ingredient_id for update;
  if v_ing.requires_thawing = p_value then
    return jsonb_build_object('result', 'unchanged');
  end if;
  if p_value then
    perform core.set_change_context(p_reason, 'manual');
    update catalog.ingredients set requires_thawing = true where id = p_ingredient_id;
    return jsonb_build_object('result', 'applied');
  end if;
  if exists (select 1 from workflow.approval_requests r
               join workflow.approval_workflows w on w.id = r.workflow_id
              where w.code = 'catalog.change_requires_thawing' and r.entity_id = p_ingredient_id
                and r.status = 'pending') then
    raise exception 'Ya hay un pedido pendiente para dejar de comprarla congelada.' using errcode = '23505';
  end if;
  v_request := workflow.request_approval(
    'catalog.change_requires_thawing', v_group, null, null, null, p_ingredient_id,
    jsonb_build_object('ingredient', v_ing.name, 'requires_thawing', false),
    jsonb_build_object('requires_thawing', true),
    p_reason);
  return jsonb_build_object('result', 'pending_approval', 'request_id', v_request);
end
$$;
comment on function catalog.set_requires_thawing(uuid, boolean, text) is
  'Marca una materia prima como «se compra congelada» (en el momento) o pide desmarcarla (solicitud catalog.change_requires_thawing, que aprueba un Chef de todo el grupo: baja el costo). Pide catalog.manage y un motivo.';
revoke execute on function catalog.set_requires_thawing(uuid, boolean, text) from public, anon;
grant execute on function catalog.set_requires_thawing(uuid, boolean, text) to authenticated;

-- Aplica la aprobación (la llama workflow.decide_approval en su transacción).
create function catalog.apply_requires_thawing(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req workflow.approval_requests := workflow.approved_request(p_request_id);
  v_ing catalog.ingredients;
begin
  select * into v_ing from catalog.ingredients where id = v_req.entity_id and deleted_at is null for update;
  if not found then
    perform workflow.cannot_apply('la materia prima ya no está vigente');
  end if;
  if not v_ing.requires_thawing then
    perform workflow.cannot_apply('ya no se compra congelada');
  end if;
  update catalog.ingredients set requires_thawing = false where id = v_ing.id;
end
$$;
comment on function catalog.apply_requires_thawing(uuid) is
  'Interna (aprobación catalog.change_requires_thawing): la materia prima deja de comprarse congelada. El trigger anota el recálculo.';
revoke execute on function catalog.apply_requires_thawing(uuid) from public;

-- Si hay un pedido pendiente para dejar de comprarla congelada (para la ficha). Solo sí o no: quien ve el catálogo.
create function catalog.thawing_change_pending(p_ingredient_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from workflow.approval_requests r
                   join workflow.approval_workflows w on w.id = r.workflow_id
                   join catalog.ingredients i on i.id = r.entity_id
                  where w.code = 'catalog.change_requires_thawing' and r.entity_id = p_ingredient_id
                    and r.status = 'pending'
                    and core.has_permission_in_group_any_scope('catalog.view', i.group_id))
$$;
comment on function catalog.thawing_change_pending(uuid) is
  'Si hay una solicitud pendiente para dejar de comprar congelada esa materia prima. Solo para quien ve el catálogo del grupo.';
revoke execute on function catalog.thawing_change_pending(uuid) from public, anon;
grant execute on function catalog.thawing_change_pending(uuid) to authenticated;

-- El tipo de aprobación: lo decide quien tenga yields.approve para todo el grupo, nunca quien lo pidió.
do $$
begin
  perform core.set_change_context('Aprobación para dejar de comprar congelada (ADR-0040)', 'maintenance');
  insert into workflow.approval_workflows (code, name, description, required_permission, min_approvers, apply_function,
                                           entity_table)
  values ('catalog.change_requires_thawing', 'Dejar de comprar congelada',
          'Desmarcar «se compra congelada» en una materia prima: su costo deja de sumar la merma de descongelado y baja. Lo aprueba un Chef Ejecutivo de todo el grupo, distinto de quien lo pidió.',
          'yields.approve', 1, 'catalog.apply_requires_thawing(uuid)'::regprocedure, 'catalog.ingredients');
end
$$;

create function costing.on_thawing_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform costing.enqueue_recalc(costing.recipes_using_ingredient(new.id), null, 'yield_change');
  return null;
end
$$;
comment on function costing.on_thawing_changed() is
  'Trigger de ingredients: al marcar o desmarcar «se compra congelada», anota el recálculo de las recetas que la usan.';
revoke execute on function costing.on_thawing_changed() from public;
create trigger recalculate_costs_thawing after update of requires_thawing on catalog.ingredients
  for each row when (old.requires_thawing is distinct from new.requires_thawing)
  execute function costing.on_thawing_changed();

-- El rendimiento que usa el costo: el estándar aprobado del proceso de la línea y, si la materia prima se compra
-- congelada, además el de descongelado (multiplicados, con 4 decimales como los guarda el costo). La línea del propio
-- proceso de descongelado no lo suma dos veces. Congelada y sin estándar de descongelado: ninguna fila (el motor
-- marca RENDIMIENTO NO DEFINIDO). approved_yield sigue siendo el estándar de un proceso solo: lo usan las propuestas
-- y los avisos de ensayos.
-- Cuánto queda al descongelar, para multiplicar el rendimiento de una línea: 1 si no se compra congelada o si la línea
-- es del propio proceso de descongelado; el estándar aprobado de DESCONGELADO si se compra congelada; vacío si se
-- compra congelada y no hay estándar (o el grupo no tiene el proceso): nunca 0 % de merma.
create function catalog.thawing_factor(p_ingredient_id uuid, p_process_id uuid, p_supplier_id uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case
           when not i.requires_thawing then 1
           when y.id is not null and y.id = p_process_id then 1
           else (select a.cleaning_yield from catalog.approved_yield(i.id, y.id, null, p_supplier_id) a where y.id is not null)
         end
    from catalog.ingredients i
    left join catalog.yield_processes y on y.group_id = i.group_id and y.code = 'DESCONGELADO' and y.deleted_at is null
   where i.id = p_ingredient_id
$$;
comment on function catalog.thawing_factor(uuid, uuid, uuid) is
  'Interna: el factor de descongelado de una línea. 1 si no se compra congelada (o si la línea es del proceso DESCONGELADO), el estándar aprobado si se compra congelada, vacío si falta (nunca 0 % de merma).';
revoke execute on function catalog.thawing_factor(uuid, uuid, uuid) from public;

create function catalog.costing_yield(p_ingredient_id uuid, p_process_id uuid, p_cut text, p_supplier_id uuid)
returns table (profile_id uuid, cleaning_yield numeric, cooking_factor numeric, thawing_yield numeric)
language sql
stable
set search_path = ''
as $$
  select a.profile_id, round(a.cleaning_yield * f.t, 4), a.cooking_factor, f.t
    from catalog.approved_yield(p_ingredient_id, p_process_id, p_cut, p_supplier_id) a
   cross join (select catalog.thawing_factor(p_ingredient_id, p_process_id, p_supplier_id) as t) f
   where f.t is not null
$$;
comment on function catalog.costing_yield(uuid, uuid, text, uuid) is
  'Interna: el rendimiento que usa el motor de costos. El estándar aprobado del proceso y, si la materia prima se compra congelada, por el de descongelado. Congelada sin estándar de descongelado: ninguna fila (nunca 0 % de merma).';
revoke execute on function catalog.costing_yield(uuid, uuid, text, uuid) from public;

-- ---------------------------------------------------------------------------
-- 3. Mermas en %
-- ---------------------------------------------------------------------------
-- Propone, juntas, la merma de limpieza (proceso LIMPIEZA) y la de descongelado (DESCONGELADO) de una materia prima.
-- Cada una queda como propuesta de estándar (catalog.propose_yield_standard): no cambia el costo hasta que la apruebe
-- un Chef de todo el grupo, distinto de quien la propuso. La limpieza conserva el factor de cocción que ya tenía.
-- Una merma de 0 % solo si se declara «No tiene merma» (nunca se supone).
create function catalog.propose_waste(p_ingredient_id uuid, p_declared_no_loss boolean, p_method text, p_reason text,
                                      p_cleaning_loss numeric default null, p_thawing_loss numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ing       catalog.ingredients;
  v_clean     uuid;
  v_thaw      uuid;
  v_cooking   numeric;
  v_requests  integer := 0;
begin
  select * into v_ing from catalog.ingredients where id = p_ingredient_id and deleted_at is null;
  perform org.require(v_ing.id is not null and core.has_permission_in_group_any_scope('yields.record', v_ing.group_id),
                      'proponer mermas en este grupo');
  if p_cleaning_loss is null and p_thawing_loss is null then
    raise exception 'Cargá al menos una merma.' using errcode = '22023';
  end if;
  if p_cleaning_loss < 0 or p_cleaning_loss >= 1 or p_thawing_loss < 0 or p_thawing_loss >= 1 then
    raise exception 'Una merma va de 0 %% a menos de 100 %%.' using errcode = '22023';
  end if;
  -- Se guarda con 4 decimales: una merma que redondea a 0 es una merma de 0 %.
  if (round(1 - p_cleaning_loss, 4) = 1 or round(1 - p_thawing_loss, 4) = 1) and not coalesce(p_declared_no_loss, false) then
    raise exception 'Una merma de 0 %% se tiene que declarar «No tiene merma».' using errcode = '23514';
  end if;
  select id into v_clean from catalog.yield_processes
   where group_id = v_ing.group_id and code = 'LIMPIEZA' and deleted_at is null;
  select id into v_thaw from catalog.yield_processes
   where group_id = v_ing.group_id and code = 'DESCONGELADO' and deleted_at is null;
  if p_cleaning_loss is not null then
    if v_clean is null then
      raise exception 'El grupo no tiene el proceso de limpieza (código LIMPIEZA).' using errcode = '22023';
    end if;
    -- LIMPIEZA es un proceso de limpieza: su factor de cocción es 1 («no se cocina»), como en el formulario de
    -- estándares. Si ya tenía otro aprobado, se conserva. El factor viaja en la solicitud: quien aprueba lo ve.
    select a.cooking_factor into v_cooking from catalog.approved_yield(p_ingredient_id, v_clean, null, null) a;
    perform catalog.propose_yield_standard(p_ingredient_id, v_clean, null, round(1 - p_cleaning_loss, 4),
                                           coalesce(v_cooking, 1), p_method, round(1 - p_cleaning_loss, 4) = 1, p_reason);
    v_requests := v_requests + 1;
  end if;
  if p_thawing_loss is not null then
    if v_thaw is null then
      raise exception 'El grupo no tiene el proceso de descongelado (código DESCONGELADO).' using errcode = '22023';
    end if;
    -- El descongelado no cocina: el motor usa solo su rendimiento (catalog.thawing_factor), nunca su cocción.
    perform catalog.propose_yield_standard(p_ingredient_id, v_thaw, null, round(1 - p_thawing_loss, 4), 1, p_method,
                                           round(1 - p_thawing_loss, 4) = 1, p_reason);
    v_requests := v_requests + 1;
  end if;
  return jsonb_build_object('requests', v_requests);
end
$$;
comment on function catalog.propose_waste(uuid, boolean, text, text, numeric, numeric) is
  'Propone la merma de limpieza y la de descongelado (entre 0 y 1) como estándares de LIMPIEZA y DESCONGELADO, en una sola transacción. Pide yields.record en el grupo y un motivo; las aprueba un Chef de todo el grupo. 0 solo con p_declared_no_loss.';
revoke execute on function catalog.propose_waste(uuid, boolean, text, text, numeric, numeric) from public, anon;
grant execute on function catalog.propose_waste(uuid, boolean, text, text, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Merma de cocción informativa
-- ---------------------------------------------------------------------------
-- Peso terminado (el rendimiento, en gramos) sobre el peso de las líneas tal como están escritas en la receta. Menor a
-- 1: pierde peso; mayor: se hidrata. Solo si todo se puede pasar a gramos (el rendimiento en peso y cada línea por su
-- unidad o con la densidad o el peso por unidad de la materia prima); si no, status dice qué falta y el factor va vacío.
-- Con la sesión de la persona: solo las versiones y las materias primas que ve. Por eso no usa recipes.unit_to_base
-- (interna): el factor sale de catalog.unit_conversions, que lee cualquiera con sesión.
create function recipes.cooking_loss(p_version_id uuid)
returns table (input_grams numeric, output_grams numeric, factor numeric, status text)
language sql
stable
set search_path = ''
as $$
  with v as (select rv.id, rv.yield_quantity, u.dimension, (case when u.is_base then 1 else (select k.factor from catalog.unit_conversions k
                                       where k.from_unit_id = u.id and k.deleted_at is null) end) as to_base
               from recipes.recipe_versions rv
               left join catalog.units u on u.id = rv.yield_unit_id
              where rv.id = p_version_id),
       gram as (select id from catalog.units where code = 'g' and is_base and deleted_at is null),
       l as (select case
                      when x.ingredient_id is not null
                        then (select c.quantity from gram cross join lateral catalog.convert_quantity(x.ingredient_id, x.quantity, x.unit_id, gram.id) c)
                      when u.dimension = 'mass' then x.quantity * (case when u.is_base then 1 else (select k.factor from catalog.unit_conversions k
                                       where k.from_unit_id = u.id and k.deleted_at is null) end)
                    end as grams
               from recipes.recipe_components x
               join catalog.units u on u.id = x.unit_id
              where x.recipe_version_id = p_version_id and x.deleted_at is null),
       s as (select count(*) as lines, count(grams) as known, sum(grams) as total from l)
  -- Una suma parcial no se muestra: si falta convertir una línea, el peso de entrada va vacío.
  select case when s.lines > 0 and s.lines = s.known then s.total end,
         case when v.dimension = 'mass' then v.yield_quantity * v.to_base end,
         case when v.dimension = 'mass' and s.lines > 0 and s.lines = s.known and s.total > 0
              then round(v.yield_quantity * v.to_base / s.total, 4) end,
         case when v.yield_quantity is null then 'missing_yield'
              when v.dimension is distinct from 'mass' then 'yield_not_weight'
              when s.lines = 0 then 'no_lines'
              when s.lines > s.known then 'missing_conversion'
              else 'ok' end
    from v cross join s
$$;
comment on function recipes.cooking_loss(uuid) is
  'Merma de cocción informativa de una versión: peso de las líneas (en g), peso terminado (el rendimiento, en g) y su cociente. status: ok, missing_yield, yield_not_weight (rinde en volumen o unidades), no_lines o missing_conversion. Nunca supone una densidad. Respeta RLS.';
revoke execute on function recipes.cooking_loss(uuid) from public, anon;
grant execute on function recipes.cooking_loss(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. El motor usa el rendimiento con el descongelado
-- ---------------------------------------------------------------------------
-- Las dos funciones son las vigentes (20261116120000_cost_scenarios y 20261112120000_recipe_costs) con un solo cambio:
-- el rendimiento sale de catalog.costing_yield en lugar de approved_yield / standard_yield. Sin materias primas
-- congeladas, el resultado es el mismo.

CREATE OR REPLACE FUNCTION costing.recipe_line_costs_internal(p_version_id uuid, p_restaurant_id uuid, p_as_of date, p_memo jsonb DEFAULT NULL::jsonb)
 RETURNS SETOF costing.recipe_cost_line
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  c        record;
  l        costing.recipe_cost_line;
  v_vat    text;
  v_conv   record;
  v_prof   record;
  v_price  record;
  v_sub    record;
  v_tot    costing.recipe_cost_total;
  v_memo   jsonb;
  v_new    numeric;
  -- Las versiones que se están calculando: un círculo a través de una variante no se recorre.
  v_path   jsonb := coalesce(p_memo -> 'path', '[]'::jsonb) || to_jsonb(p_version_id::text);
begin
  select e.vat_condition::text into v_vat
    from org.restaurants r join org.legal_entities e on e.id = r.legal_entity_id and e.deleted_at is null
   where r.id = p_restaurant_id;

  for c in
    select x.id, x.line_order, x.ingredient_id, x.sub_recipe_id, x.quantity, x.unit_id, x.quantity_basis::text as basis,
           x.yield_profile_id, q.base_quantity as frozen, q.base_unit_id as frozen_unit, i.recipe_unit_id as use_unit,
           coalesce(i.name, s.name) as item, u.dimension as line_dimension
      from recipes.recipe_components x
      join catalog.units u on u.id = x.unit_id
      left join recipes.component_base_quantities q on q.recipe_component_id = x.id
      left join catalog.ingredients i on i.id = x.ingredient_id
      left join recipes.recipes s on s.id = x.sub_recipe_id
     where x.recipe_version_id = p_version_id and x.deleted_at is null
     order by x.line_order
  loop
    l := null;
    l.component_id := c.id; l.line_order := c.line_order; l.item := c.item; l.ingredient_id := c.ingredient_id;
    l.sub_recipe_id := c.sub_recipe_id; l.quantity := c.quantity; l.unit_id := c.unit_id; l.quantity_basis := c.basis;
    l.base_quantity := c.frozen; l.vat_condition := v_vat; l.estimated := false; l.stale := false; l.status := 'ok';

    -- Un escenario cambia el gramaje de una línea: la cantidad congelada se ajusta en la misma proporción.
    v_new := (p_memo -> 'quantities' ->> c.id::text)::numeric;
    if v_new is not null then
      l.quantity := v_new;
      l.base_quantity := c.frozen * v_new / nullif(c.quantity, 0);
    end if;

    if c.ingredient_id is not null then
      -- Lo publicado usa la cantidad congelada; un borrador, la conversión de hoy. Si la materia prima cambió
      -- de unidad de uso, la cantidad congelada ya no se puede multiplicar por su precio.
      if c.frozen is not null and c.frozen_unit is distinct from c.use_unit then
        l.status := 'missing_conversion';
      elsif l.base_quantity is null then
        select b.base_quantity, b.status into v_conv from catalog.to_base_quantity(c.ingredient_id, l.quantity, c.unit_id) b;
        l.base_quantity := v_conv.base_quantity;
        if v_conv.status <> 'ok' then
          l.status := v_conv.status;
        end if;
      end if;

      if l.status = 'ok' and c.basis <> 'purchase' then
        v_memo := p_memo -> 'yields' -> c.ingredient_id::text;
        if v_memo is not null then
          -- Un escenario simula otro rendimiento. Si la materia prima se compra congelada, se le suma el descongelado
          -- aprobado, como en el costo real (ADR-0040); sin él, queda no definido.
          l.cleaning_yield := round((v_memo ->> 'cleaning_yield')::numeric
                                    * catalog.thawing_factor(c.ingredient_id,
                                                             (select p.process_id from catalog.ingredient_yield_profiles p
                                                               where p.id = c.yield_profile_id), null), 4);
          l.cooking_factor := (v_memo ->> 'cooking_factor')::numeric;
        else
          -- Siempre el estándar aprobado hoy para ese proceso, corte y proveedor (ADR-0024, respuesta 6), más el
          -- descongelado si la materia prima se compra congelada (ADR-0040).
          select p.process_id, p.cut, p.supplier_id into v_prof
            from catalog.ingredient_yield_profiles p where p.id = c.yield_profile_id;
          if found then
            select a.profile_id, a.cleaning_yield, a.cooking_factor into l.yield_profile_id, l.cleaning_yield, l.cooking_factor
              from catalog.costing_yield(c.ingredient_id, v_prof.process_id, v_prof.cut, v_prof.supplier_id) a;
          end if;
          if l.yield_profile_id is null then
            l.status := 'missing_yield';
          end if;
        end if;
      end if;

      if l.status = 'ok' then
        l.purchase_quantity := costing.purchase_quantity(l.base_quantity, c.basis, l.cleaning_yield, l.cooking_factor);
        if l.purchase_quantity is null then
          l.status := 'missing_yield';
        end if;
      end if;

      if l.status = 'ok' then
        v_memo := p_memo -> 'prices' -> c.ingredient_id::text;
        if v_memo is not null then
          select * into v_price
            from jsonb_to_record(v_memo) as m (price_record_id uuid, price_level text, inherited boolean, gross_unit_cost numeric,
                                               unit_cost numeric, stale boolean, status text);
        else
          select * into v_price from costing.resolve_price_internal(c.ingredient_id, p_restaurant_id, p_as_of);
        end if;
        l.price_record_id := v_price.price_record_id;
        l.price_level := v_price.price_level;
        l.unit_cost := v_price.unit_cost;
        l.gross_unit_cost := v_price.gross_unit_cost;
        l.stale := coalesce(v_price.stale, false);
        l.estimated := coalesce(v_price.inherited, false);
        l.status := case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity' else v_price.status end;
        l.line_cost := l.purchase_quantity * l.unit_cost;
        l.line_gross_cost := l.purchase_quantity * l.gross_unit_cost;
        if l.price_record_id is not null then
          select r.base_quantity into l.package_base_quantity from costing.price_records r where r.id = l.price_record_id;
        end if;
      end if;
    else
      -- La variante del local, si está publicada; si no, la preparación de la línea.
      select v.id, v.recipe_id, r.name, v.yield_quantity * recipes.unit_to_base(v.yield_unit_id) as yield_base,
             yu.dimension as yield_dimension into v_sub
        from recipes.recipe_versions v
        join recipes.recipes r on r.id = v.recipe_id
        left join catalog.units yu on yu.id = v.yield_unit_id
       where v.status = 'published' and r.deleted_at is null
         and (r.id = c.sub_recipe_id
              or (r.variant_of_recipe_id = c.sub_recipe_id and r.restaurant_id = p_restaurant_id and r.is_active))
       order by r.variant_of_recipe_id is null
       limit 1;
      if not found then
        l.status := 'missing_sub_recipe';
      else
        l.sub_recipe_id := v_sub.recipe_id;
        l.sub_recipe_version_id := v_sub.id;
        l.item := v_sub.name;
        if l.base_quantity is null then
          l.base_quantity := l.quantity * recipes.unit_to_base(c.unit_id);
        end if;
        v_memo := p_memo -> 'subs' -> v_sub.id::text;
        if v_memo is not null then
          v_tot := jsonb_populate_record(null::costing.recipe_cost_total, v_memo);
        elsif v_path ? v_sub.id::text then
          v_tot := row(null, null, null, null, 'incomplete')::costing.recipe_cost_total;
        else
          v_tot := costing.recipe_totals_internal(v_sub.id, p_restaurant_id, p_as_of,
                                                  coalesce(p_memo, '{}'::jsonb) || jsonb_build_object('path', v_path));
        end if;
        l.estimated := v_tot.reliability = 'estimated';
        l.stale := v_tot.reliability = 'stale';
        -- Una variante puede rendir en otra dimensión o en un envase: no se adivina, queda incompleto.
        if coalesce(v_sub.yield_base, 0) <= 0 or l.base_quantity is null
           or v_sub.yield_dimension is distinct from c.line_dimension then
          l.status := 'missing_yield';
        else
          l.gross_unit_cost := v_tot.total_gross_cost / v_sub.yield_base;
          l.line_gross_cost := l.base_quantity * l.gross_unit_cost;
          if v_tot.total_cost is null or v_tot.reliability = 'incomplete' then
            l.status := 'incomplete_sub_recipe';
          else
            l.unit_cost := v_tot.total_cost / v_sub.yield_base;
            l.line_cost := l.base_quantity * l.unit_cost;
          end if;
        end if;
      end if;
    end if;
    return next l;
  end loop;
end
$$;

CREATE OR REPLACE FUNCTION costing.ingredient_line_cost(p_ingredient_id uuid, p_restaurant_id uuid, p_quantity numeric, p_unit_id uuid, p_basis text DEFAULT 'purchase'::text, p_process_id uuid DEFAULT NULL::uuid, p_as_of date DEFAULT ((now() AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))::date)
 RETURNS TABLE(base_quantity numeric, purchase_quantity numeric, unit_cost numeric, line_cost numeric, price_level text, inherited boolean, price_record_id uuid, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_base   record;
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
    -- El mismo rendimiento que la receta, con el descongelado (ADR-0040). Sin proceso o sin estándar, vacío.
    v_qty := (select costing.purchase_quantity(v_base.base_quantity, p_basis, y.cleaning_yield, y.cooking_factor)
                from catalog.costing_yield(p_ingredient_id, p_process_id, null, null) y
               where p_process_id is not null);
    if v_qty is null then
      return query select v_base.base_quantity, null::numeric, null::numeric, null::numeric, null::text, null::boolean,
                          null::uuid, 'missing_yield'::text;
      return;
    end if;
  end if;
  select * into v_price from costing.resolve_price_internal(p_ingredient_id, p_restaurant_id, coalesce(p_as_of, (now() at time zone 'America/Argentina/Buenos_Aires')::date));
  return query select v_base.base_quantity, v_qty, v_price.unit_cost,
                      case when v_price.unit_cost is null then null else v_qty * v_price.unit_cost end,
                      v_price.price_level, v_price.inherited, v_price.price_record_id,
                      case when v_price.status = 'ok' and v_price.unit_cost is null then 'missing_legal_entity'
                           else v_price.status end;
end
$$;

comment on function costing.recipe_line_costs_internal(uuid, uuid, date, jsonb) is
  'Interna: las líneas de una versión calculadas en un local. El rendimiento de cada línea es el estándar aprobado del proceso, por el de descongelado si la materia prima se compra congelada (catalog.costing_yield, ADR-0040); en un escenario, el simulado por el de descongelado. Estados: ok, missing_conversion, missing_yield, missing_price, missing_legal_entity, missing_sub_recipe, incomplete_sub_recipe.';
comment on function costing.ingredient_line_cost(uuid, uuid, numeric, uuid, text, uuid, date) is
  'Costo de una línea de materia prima en un local: pasa la cantidad a la unidad de uso, aplica el rendimiento que usa la receta (limpia o cocida, con el descongelado si se compra congelada: catalog.costing_yield) y el precio que vale. Estados: ok, missing_conversion, missing_yield, missing_price o missing_legal_entity (nunca $ 0). Pide prices.view en el local.';
