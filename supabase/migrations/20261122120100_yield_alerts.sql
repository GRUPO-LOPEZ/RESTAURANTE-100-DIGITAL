-- Fase 2, agregados chicos: aviso de rendimiento (ADR-0035; respuestas de Soy en ADR-0024, ADR-0026 y ADR-0030).
-- Cuando un ensayo se desvía del estándar aprobado más que un umbral, se avisa a quien tiene yields.alerts en ese local
-- (el Chef y el Controller; también el Director de marca y Dirección General, que dan y aprueban esos roles). El umbral va en la configuración del grupo, junto con la de precios, y lo cambia quien
-- tiene prices.configure (Dirección General). Un ensayo nunca cambia el estándar: el aviso es para mirar la producción.

-- ---------------------------------------------------------------------------
-- 1. Permiso: recibir los avisos
-- ---------------------------------------------------------------------------
do $$
begin
  perform core.set_change_context('Permiso de avisos de rendimiento (Fase 2, ADR-0035)', 'maintenance');
  insert into core.permissions (code, module, action, description, is_sensitive) values
    ('yields.alerts', 'yields', 'alerts',
     'Recibir un aviso cuando un ensayo de rendimiento se desvía del estándar más que el umbral del grupo.', false);
  insert into core.role_permissions (role_id, permission_id)
  select r.id, p.id
    from (values ('executive_chef', 'yields.alerts'),
                 ('controller', 'yields.alerts'),
                 -- Nadie da un permiso que no tiene: quien da o aprueba el rol de Chef o de Controller lo necesita
                 -- (decisión de Joaco, 2026-11-09). Ellos también reciben el aviso.
                 ('brand_director', 'yields.alerts'),
                 ('general_management', 'yields.alerts')) as m (role_code, permission_code)
    join core.roles r on r.code = m.role_code
    join core.permissions p on p.code = m.permission_code;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. El umbral, en la configuración del grupo
-- ---------------------------------------------------------------------------
alter table costing.price_settings
  add column yield_alert_pct numeric(5,2) not null default 10 check (yield_alert_pct > 0 and yield_alert_pct <= 100);
comment on column costing.price_settings.yield_alert_pct is
  'Si un ensayo de rendimiento se desvía del estándar aprobado más que este porcentaje (en limpieza o en cocción), se avisa a quien tiene yields.alerts en ese local. Se carga a mano (por ejemplo, con la inflación del mes).';

drop function costing.update_price_settings(uuid, numeric, integer, text, integer);
create function costing.update_price_settings(p_group_id uuid, p_approval_variation_pct numeric, p_stale_days integer,
                                              p_reason text, p_lookback_days integer default null,
                                              p_yield_alert_pct numeric default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform org.require(core.has_permission_in_group('prices.configure', p_group_id), 'cambiar la configuración de precios');
  perform core.set_change_context(p_reason, 'manual');
  -- Lo que no llega queda como estaba (sin fila, los valores de fábrica). Así, cambiar solo el umbral de rendimiento no
  -- pisa el porcentaje ni los días que otra persona guardó al mismo tiempo.
  insert into costing.price_settings (group_id, approval_variation_pct, stale_days, lookback_days, yield_alert_pct)
  values (p_group_id, coalesce(p_approval_variation_pct, 15), coalesce(p_stale_days, 30), coalesce(p_lookback_days, 30),
          coalesce(p_yield_alert_pct, 10))
  on conflict (group_id) where deleted_at is null
  do update set approval_variation_pct = coalesce(p_approval_variation_pct, costing.price_settings.approval_variation_pct),
                stale_days = coalesce(p_stale_days, costing.price_settings.stale_days),
                lookback_days = coalesce(p_lookback_days, costing.price_settings.lookback_days),
                yield_alert_pct = coalesce(p_yield_alert_pct, costing.price_settings.yield_alert_pct);
exception when check_violation then
  raise exception 'Los porcentajes van de más de 0 a 100, y los días de 1 a 365.' using errcode = '23514';
end
$$;
comment on function costing.update_price_settings(uuid, numeric, integer, text, integer, numeric) is
  'Cambia el porcentaje que pide también la aprobación de Dirección, los días de un precio desactualizado, los días hacia atrás de la comparación y el umbral del aviso de rendimiento. Lo que llega vacío queda como estaba. Pide prices.configure en el grupo y un motivo.';
revoke execute on function costing.update_price_settings(uuid, numeric, integer, text, integer, numeric) from public;
grant execute on function costing.update_price_settings(uuid, numeric, integer, text, integer, numeric) to authenticated;

-- Interna: el umbral de un grupo (sin fila, el de fábrica: 10 %).
create function catalog.group_yield_alert_pct(p_group_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.yield_alert_pct from costing.price_settings s where s.group_id = p_group_id and s.deleted_at is null), 10)
$$;
comment on function catalog.group_yield_alert_pct(uuid) is 'Interna: el umbral del aviso de rendimiento de un grupo (10 % si no se configuró).';
revoke execute on function catalog.group_yield_alert_pct(uuid) from public;

-- Para la ficha de la materia prima: el umbral vigente, si la sesión ve ese catálogo.
create function catalog.yield_alert_threshold(p_ingredient_id uuid)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select catalog.group_yield_alert_pct(i.group_id)
    from catalog.ingredients i
   where i.id = p_ingredient_id and i.deleted_at is null
     and i.group_id in (select core.visible_group_ids('catalog.view'))
$$;
comment on function catalog.yield_alert_threshold(uuid) is
  'El umbral del aviso de rendimiento del grupo de una materia prima, en %. Vacío si la sesión no ve ese catálogo.';
revoke execute on function catalog.yield_alert_threshold(uuid) from public;
grant execute on function catalog.yield_alert_threshold(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. El desvío de un ensayo y el aviso
-- ---------------------------------------------------------------------------
-- Interna: el desvío relativo de un ensayo contra el estándar que usa el costo (catalog.approved_yield: el del proveedor
-- si lo hay, si no el general; decisión de Joaco, 2026-11-09). Sin estándar, no devuelve nada.
create function catalog.yield_deviation(p_test_id uuid)
returns table (measured_cleaning numeric, standard_cleaning numeric, cleaning_pct numeric,
               measured_cooking numeric, standard_cooking numeric, cooking_pct numeric)
language sql
stable
security definer
set search_path = ''
as $$
  select t.clean_weight / t.gross_weight, p.cleaning_yield,
         (t.clean_weight / t.gross_weight / p.cleaning_yield - 1) * 100,
         t.after_cooking_weight / t.before_cooking_weight, p.cooking_factor,
         (t.after_cooking_weight / t.before_cooking_weight / p.cooking_factor - 1) * 100
    from catalog.ingredient_yield_tests t
    cross join lateral catalog.approved_yield(t.ingredient_id, t.process_id, t.cut, t.supplier_id) p
   where t.id = p_test_id
$$;
comment on function catalog.yield_deviation(uuid) is
  'Interna: cuánto se desvía un ensayo del estándar que usa el costo, en limpieza y en cocción (en %, con signo). Vacío si no hay estándar.';
revoke execute on function catalog.yield_deviation(uuid) from public;

-- Interna: si el ensayo se desvía más que el umbral, avisa a quien tiene yields.alerts en ese local. Quien lo cargó no se
-- avisa a sí mismo. Si algo falla, el ensayo se guarda igual: el aviso no puede frenar la carga en la cocina.
create function catalog.notify_yield_deviation(p_test_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t      catalog.ingredient_yield_tests;
  d      record;
  v_pct  numeric;
  v_name text;
  v_rest org.restaurants;
  -- Los números van con coma y sin ceros de más: 12,5 · 80 · 0,85.
  v_body text;
begin
  select * into t from catalog.ingredient_yield_tests where id = p_test_id;
  if t.id is null then
    return;
  end if;
  select * into d from catalog.yield_deviation(p_test_id);
  if not found then
    return;
  end if;
  v_pct := catalog.group_yield_alert_pct(t.group_id);
  if not (abs(coalesce(d.cleaning_pct, 0)) > v_pct or abs(coalesce(d.cooking_pct, 0)) > v_pct) then
    return;
  end if;
  select name into v_name from catalog.ingredients where id = t.ingredient_id;
  select * into v_rest from org.restaurants where id = t.restaurant_id;
  -- "Limpieza: 50 % contra 80 % del estándar (37,5 % menos)". Los números con coma y sin ceros de más.
  v_body := concat_ws(' ',
    case when d.cleaning_pct is not null then
      format('Limpieza: %s %% contra %s %% del estándar (%s %% %s).',
             replace(trim_scale(round(d.measured_cleaning * 100, 1))::text, '.', ','),
             replace(trim_scale(round(d.standard_cleaning * 100, 1))::text, '.', ','),
             replace(trim_scale(round(abs(d.cleaning_pct), 1))::text, '.', ','),
             case when d.cleaning_pct > 0 then 'más' else 'menos' end)
    end,
    case when d.cooking_pct is not null then
      format('Cocción: rinde ×%s contra ×%s del estándar (%s %% %s).',
             replace(trim_scale(round(d.measured_cooking, 2))::text, '.', ','),
             replace(trim_scale(round(d.standard_cooking, 2))::text, '.', ','),
             replace(trim_scale(round(abs(d.cooking_pct), 1))::text, '.', ','),
             case when d.cooking_pct > 0 then 'más' else 'menos' end)
    end,
    format('En %s, el %s. Avisa con un desvío de más de %s %%.', v_rest.name, to_char(t.tested_on, 'DD/MM/YYYY'),
           replace(trim_scale(v_pct)::text, '.', ',')));
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  select u.user_id, t.group_id, 'yield_deviation', left(format('Rendimiento desviado: %s', v_name), 200), left(v_body, 500),
         format('/materias-primas/%s', t.ingredient_id)
    from (select distinct a.user_id from core.user_role_assignments a
            join core.role_permissions rp on rp.role_id = a.role_id and rp.deleted_at is null
            join core.permissions p on p.id = rp.permission_id and p.code = 'yields.alerts'
           where a.group_id = t.group_id and a.deleted_at is null
             and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())) u
   where u.user_id is distinct from t.created_by
     and core.user_has_permission_for_scope(u.user_id, 'yields.alerts', 'restaurant', t.group_id, v_rest.brand_id, v_rest.id)
     and core.user_has_permission_for_scope(u.user_id, 'catalog.view', 'restaurant', t.group_id, v_rest.brand_id, v_rest.id);
exception when others then
  -- Sin el detalle del error: solo el código, para no mostrar nada interno.
  raise warning 'No se pudo avisar el desvío del ensayo % (código %).', p_test_id, sqlstate;
end
$$;
comment on function catalog.notify_yield_deviation(uuid) is
  'Interna: si un ensayo se desvía del estándar más que el umbral del grupo, avisa a quien tiene yields.alerts y catalog.view en ese local (menos a quien lo cargó).';
revoke execute on function catalog.notify_yield_deviation(uuid) from public;

-- Registrar un ensayo: igual que antes, y en la misma transacción, el aviso si se desvía.
create or replace function catalog.record_yield_test(p_ingredient_id uuid, p_process_id uuid, p_restaurant_id uuid,
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
  perform catalog.notify_yield_deviation(v_id);
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
  'Registra un ensayo de rendimiento en un local. Pide yields.record en ese local y un motivo. p_measures: gross_weight, clean_weight, before_cooking_weight, after_cooking_weight, discard_weight (gramos). p_details: cut, supplier_id, samples, responsible, notes. Nunca cambia el estándar. En la misma transacción, si el ensayo se desvía del estándar más que el umbral del grupo, avisa a quien tiene yields.alerts en ese local (ADR-0035).';

-- Cambiar solo el umbral del aviso de rendimiento, desde /configuracion/precios. Usa update_price_settings (mismo
-- permiso, motivo y auditoría) y deja el resto de la configuración como está.
create function costing.update_yield_alert(p_group_id uuid, p_yield_alert_pct numeric, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_yield_alert_pct is null then
    raise exception 'Falta el porcentaje.' using errcode = '22023';
  end if;
  perform costing.update_price_settings(p_group_id, null, null, p_reason, null, p_yield_alert_pct);
end
$$;
comment on function costing.update_yield_alert(uuid, numeric, text) is
  'Cambia solo el umbral del aviso de rendimiento del grupo. Pide prices.configure en el grupo y un motivo.';
revoke execute on function costing.update_yield_alert(uuid, numeric, text) from public;
grant execute on function costing.update_yield_alert(uuid, numeric, text) to authenticated;
