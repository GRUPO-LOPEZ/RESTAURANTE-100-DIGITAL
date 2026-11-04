-- Fase 2 · Etapa 2.3, PR 3A: que los costos se mantengan al día solos (ADR-0032).
-- 1. Tarea diaria: precios que empiezan a valer, "desactualizado", asignaciones que vencen y fallidos.
-- 2. Foto de fin de mes: se saca aunque nada haya cambiado.
-- 3. Aviso con el impacto de costo de una publicación, solo a quien ve costos.
-- 4. integration.integration_outbox: eventos para otros sistemas.

alter type costing.cost_snapshot_reason add value 'daily';
alter type costing.cost_snapshot_reason add value 'month_end';
comment on type costing.cost_snapshot_reason is
  'Por qué se sacó una foto de costo: se publicó una versión, se aprobó un precio o un rendimiento, se asignó la receta a un local, cambió la razón social, se reabrió el local, la actualización diaria o el cierre de mes.';
alter type core.notification_kind add value 'recipe_cost_changed';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación) y recipe_cost_changed (cambió el costo de una receta, sin importes).';

-- ---------------------------------------------------------------------------
-- 1. Eventos para otros sistemas
-- ---------------------------------------------------------------------------
create schema integration;
comment on schema integration is 'Eventos para otros sistemas. No se expone por la API (ADR-0020).';
revoke all on schema integration from public, anon, authenticated, service_role;

create table integration.integration_outbox (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references org.groups (id) on delete restrict,
  event_type       text not null check (event_type in ('cost.changed', 'price.approved', 'recipe.published')),
  aggregate_table  text not null check (length(btrim(aggregate_table)) between 1 and 120),
  aggregate_id     uuid not null,
  payload          jsonb not null default '{}'::jsonb,
  occurred_at      timestamptz not null default now(),
  published_at     timestamptz,
  created_at       timestamptz not null default now(),
  created_by       uuid references core.actors (id) on delete restrict,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references core.actors (id) on delete restrict,
  deleted_at       timestamptz,
  deleted_by       uuid references core.actors (id) on delete restrict
);
create index integration_outbox_pending_idx on integration.integration_outbox (occurred_at) where published_at is null;
create index integration_outbox_group_idx on integration.integration_outbox (group_id);
create index integration_outbox_aggregate_idx on integration.integration_outbox (aggregate_table, aggregate_id);
comment on table integration.integration_outbox is
  'Eventos de cambio para sistemas futuros. No se expone por la API y nadie los consume todavía. Llevan ids y estados, nunca importes: quien los consuma los pide con sus permisos.';
comment on column integration.integration_outbox.id is 'Identificador del evento.';
comment on column integration.integration_outbox.group_id is 'Grupo del evento.';
comment on column integration.integration_outbox.event_type is 'Qué pasó: cost.changed, price.approved o recipe.published.';
comment on column integration.integration_outbox.aggregate_table is 'Tabla del registro que cambió.';
comment on column integration.integration_outbox.aggregate_id is 'Registro que cambió.';
comment on column integration.integration_outbox.payload is 'Datos del evento: ids y estados, sin importes.';
comment on column integration.integration_outbox.occurred_at is 'Cuándo pasó.';
comment on column integration.integration_outbox.published_at is 'Cuándo se entregó. Vacío: pendiente.';
comment on column integration.integration_outbox.created_at is 'Cuándo se registró (lo pone la base).';
comment on column integration.integration_outbox.created_by is 'Quién hizo el cambio, si fue en una sesión (lo pone la base).';
comment on column integration.integration_outbox.updated_at is 'Cuándo cambió por última vez (lo pone la base).';
comment on column integration.integration_outbox.updated_by is 'Quién lo cambió por última vez (lo pone la base).';
comment on column integration.integration_outbox.deleted_at is 'Baja lógica. No se usa.';
comment on column integration.integration_outbox.deleted_by is 'Quién lo dio de baja (lo pone la base).';

alter table integration.integration_outbox enable row level security;
revoke all on integration.integration_outbox from public, anon, authenticated, service_role;
create trigger set_control_columns before insert or update on integration.integration_outbox
  for each row execute function core.set_control_columns();
create trigger reject_truncate before truncate on integration.integration_outbox
  for each statement execute function core.reject_truncate();

create function integration.emit(p_group_id uuid, p_event_type text, p_aggregate_table text, p_aggregate_id uuid, p_payload jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into integration.integration_outbox (group_id, event_type, aggregate_table, aggregate_id, payload)
  values (p_group_id, p_event_type, p_aggregate_table, p_aggregate_id, p_payload)
$$;
comment on function integration.emit(uuid, text, text, uuid, jsonb) is 'Interna: registra un evento para otros sistemas.';
revoke execute on function integration.emit(uuid, text, text, uuid, jsonb) from public;

-- ---------------------------------------------------------------------------
-- 2. La cola sabe qué receta se publicó
-- ---------------------------------------------------------------------------
alter table costing.cost_recalc_queue add column source_recipe_id uuid references recipes.recipes (id) on delete restrict;
comment on column costing.cost_recalc_queue.source_recipe_id is 'La receta publicada que causó el pedido: de ella sale el aviso con el impacto de costo.';
create index cost_recalc_queue_source_idx on costing.cost_recalc_queue (source_recipe_id) where source_recipe_id is not null;

drop function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason, uuid);
create function costing.enqueue_recalc(p_recipe_ids uuid[], p_restaurant_ids uuid[], p_reason costing.cost_snapshot_reason,
                                       p_price_record_id uuid default null, p_source_recipe_id uuid default null)
returns void
language sql
security definer
set search_path = ''
as $f$
  insert into costing.cost_recalc_queue (group_id, recipe_ids, restaurant_ids, reason, price_record_id, source_recipe_id)
  select r.group_id, p_recipe_ids, p_restaurant_ids, p_reason, p_price_record_id, p_source_recipe_id
    from recipes.recipes r where r.id = p_recipe_ids[1]
$f$;
comment on function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason, uuid, uuid) is
  'Interna: anota un pedido de recálculo. Sin recetas, no hace nada.';
revoke execute on function costing.enqueue_recalc(uuid[], uuid[], costing.cost_snapshot_reason, uuid, uuid) from public;

create or replace function costing.on_version_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'published' then
    perform recipes.freeze_base_quantities(new.id);
    perform costing.enqueue_recalc(costing.recipes_below(new.recipe_id), null, 'publish', null, new.recipe_id);
    perform integration.emit(new.group_id, 'recipe.published', 'recipes.recipe_versions', new.id,
                             jsonb_build_object('recipe_id', new.recipe_id, 'version_number', new.version_number));
  else
    perform costing.enqueue_recalc(array[new.recipe_id], null, 'publish');
  end if;
  return null;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. Un precio entra a la cola al aprobarse, o el día que empieza a valer
-- ---------------------------------------------------------------------------
create function costing.enqueue_price(p_price_record_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_price      costing.price_records;
  v_ingredient uuid;
  v_places     uuid[];
begin
  select * into v_price from costing.price_records where id = p_price_record_id;
  select p.ingredient_id into v_ingredient from catalog.purchase_products p where p.id = v_price.purchase_product_id;
  v_places := case v_price.scope_type
                when 'restaurant' then array[v_price.restaurant_id]
                when 'brand' then array(select r.id from org.restaurants r where r.brand_id = v_price.brand_id)
              end;
  perform costing.enqueue_recalc(costing.recipes_using_ingredient(v_ingredient), v_places, 'price_change', p_price_record_id);
end
$$;
comment on function costing.enqueue_price(uuid) is 'Interna: anota el recálculo de las recetas que usan ese precio, en los locales de su alcance.';
revoke execute on function costing.enqueue_price(uuid) from public;

create or replace function costing.on_price_recorded()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.approval_request_id is not null then
    perform integration.emit(new.group_id, 'price.approved', 'costing.price_records', new.id,
                             jsonb_build_object('purchase_product_id', new.purchase_product_id, 'scope_type', new.scope_type,
                                                'valid_from', new.valid_from));
  end if;
  -- Uno con fecha futura todavía no vale: lo anota la tarea diaria el día que empieza.
  if new.valid_from <= recipes.today() then
    perform costing.enqueue_price(new.id);
  end if;
  return null;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Las tareas programadas
-- ---------------------------------------------------------------------------
-- Cada día: los precios que empiezan a valer (con hasta una semana de margen, por si la tarea no corrió) y todas las
-- recetas publicadas. Así se actualizan "desactualizado", las asignaciones que vencen y los cambios de plazos.
create function costing.daily_refresh(p_day date default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := coalesce(p_day, recipes.today());
  v     record;
begin
  for v in
    select p.id from costing.price_records p
     where p.deleted_at is null and p.valid_from between v_day - 7 and v_day
       and not exists (select 1 from costing.cost_recalc_queue q where q.price_record_id = p.id)
     order by p.valid_from, p.entry_number
  loop
    perform costing.enqueue_price(v.id);
  end loop;
  for v in
    select x.group_id, array_agg(distinct x.recipe_id) as recipe_ids
      from recipes.recipe_versions x where x.status = 'published' group by x.group_id
  loop
    perform costing.enqueue_recalc(v.recipe_ids, null, 'daily');
  end loop;
  -- Si la foto de fin de mes no corrió o falló, se saca en la primera semana del mes. Sale con los precios de ese día.
  if v_day - date_trunc('month', v_day)::date < 7 then
    for v in
      select x.group_id, array_agg(distinct x.recipe_id) as recipe_ids
        from recipes.recipe_versions x
       where x.status = 'published'
         and not exists (select 1 from costing.cost_recalc_queue q
                          where q.group_id = x.group_id and q.reason = 'month_end'
                            and q.created_at >= date_trunc('month', v_day) - interval '2 days'
                            and (q.processed_at is not null or q.attempts < 3))
       group by x.group_id
    loop
      perform costing.enqueue_recalc(v.recipe_ids, null, 'month_end');
    end loop;
  end if;
end
$$;
comment on function costing.daily_refresh(date) is
  'Tarea diaria: anota los precios que empiezan a valer y el recálculo de todas las recetas publicadas. Si sale bien, cierra los pedidos que habían fallado.';
revoke execute on function costing.daily_refresh(date) from public;

create function costing.month_end_snapshots()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
begin
  for v in
    select x.group_id, array_agg(distinct x.recipe_id) as recipe_ids
      from recipes.recipe_versions x where x.status = 'published' group by x.group_id
  loop
    perform costing.enqueue_recalc(v.recipe_ids, null, 'month_end');
  end loop;
end
$$;
comment on function costing.month_end_snapshots() is
  'Tarea del último día del mes: anota una foto de todas las recetas en todos los locales abiertos, aunque nada haya cambiado. Es la base para comparar contra el mes anterior.';
revoke execute on function costing.month_end_snapshots() from public;

-- pg_cron usa UTC. 6:30 son las 3:30 de la Argentina. El día 1 a las 2:30 todavía es el último día del mes, a las 23:30
-- de la Argentina: la foto de cierre usa los precios de ese mes.
select cron.schedule('grupo-lf-costos-diario', '30 6 * * *', 'select costing.daily_refresh()');
select cron.schedule('grupo-lf-costos-fin-de-mes', '30 2 1 * *', 'select costing.month_end_snapshots()');

-- ---------------------------------------------------------------------------
-- 5. El aviso con el impacto de una publicación
-- ---------------------------------------------------------------------------
-- Compara las fotos de esta corrida (misma hora) con la última anterior a la corrida, de cada receta y local. Cada
-- persona cuenta solo sus locales, y el aviso no lleva importes: el número se ve en /costos, que pide el permiso.
-- Avisar nunca frena un recálculo.
create function costing.notify_cost_changed(p_recipe_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recipe recipes.recipes;
begin
  select * into v_recipe from recipes.recipes where id = p_recipe_id;
  perform core.set_change_context('Aviso de cambio de costo', 'maintenance');
  insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
  with changes as materialized (
    select s.recipe_id, s.restaurant_id, o.brand_id
      from costing.recipes_above(array[p_recipe_id]) up (id)
      join costing.recipe_cost_snapshots s on s.recipe_id = up.id and s.created_at = now()
      join org.restaurants o on o.id = s.restaurant_id
      cross join lateral (
        select p.total_cost from costing.recipe_cost_snapshots p
         where p.recipe_id = s.recipe_id and p.restaurant_id = s.restaurant_id and p.created_at < now()
         order by p.entry_number desc limit 1) b
     where s.total_cost is distinct from b.total_cost),
  places as materialized (
    select distinct restaurant_id, brand_id from changes),
  allowed as (
    select u.user_id, l.restaurant_id
      from (select distinct a.user_id from core.user_role_assignments a
             where a.group_id = v_recipe.group_id and a.deleted_at is null
               and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now())) u
      cross join places l
     where core.user_has_permission_for_scope(u.user_id, 'recipes.view_costs', 'restaurant', v_recipe.group_id, l.brand_id, l.restaurant_id)
       and core.user_has_permission_for_scope(u.user_id, 'recipes.view', 'restaurant', v_recipe.group_id, l.brand_id, l.restaurant_id)),
  mine as (
    select a.user_id, count(distinct c.recipe_id) as recipes, count(distinct a.restaurant_id) as places, min(a.restaurant_id::text) as first_place
      from allowed a
      join changes c on c.restaurant_id = a.restaurant_id
     group by a.user_id)
  select m.user_id, v_recipe.group_id, 'recipe_cost_changed',
         format('Cambió el costo de «%s»', v_recipe.name),
         format('%s %s en %s de tus locales.', m.recipes, case when m.recipes = 1 then 'receta' else 'recetas' end, m.places),
         format('/costos/%s?local=%s', p_recipe_id, m.first_place)
    from mine m;
exception when others then
  raise warning 'No se pudo avisar el cambio de costo de %: %', p_recipe_id, sqlerrm;
end
$$;
comment on function costing.notify_cost_changed(uuid) is
  'Interna: después de recalcular una publicación, avisa a quien ve costos y recetas en esos locales cuántas recetas de sus locales cambiaron. Sin importes. Si nada cambió, no avisa, y si falla, no frena el recálculo.';
revoke execute on function costing.notify_cost_changed(uuid) from public;

create or replace function costing.store_recipe_cost(p_recipe_id uuid, p_version_id uuid, p_group_id uuid, p_restaurant_id uuid,
                                          p_reason costing.cost_snapshot_reason, p_total costing.recipe_cost_total,
                                          p_lines costing.recipe_cost_line[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today    date := recipes.today();
  v_cur      record;
  v_total    numeric(18,4) := p_total.total_cost;
  v_gross    numeric(18,4) := p_total.total_gross_cost;
  v_unit     numeric(20,8) := p_total.cost_per_base_unit;
  v_portion  numeric(18,4) := p_total.cost_per_portion;
  v_reliable costing.cost_reliability := p_total.reliability;
  v_snapshot uuid;
  v_changed  boolean := true;
begin
  select * into v_cur from costing.recipe_cost_current c
   where c.recipe_id = p_recipe_id and c.restaurant_id = p_restaurant_id and c.deleted_at is null;
  if found and v_cur.recipe_version_id = p_version_id and v_cur.total_cost is not distinct from v_total
     and v_cur.total_gross_cost is not distinct from v_gross and v_cur.cost_per_base_unit is not distinct from v_unit
     and v_cur.cost_per_portion is not distinct from v_portion and v_cur.reliability = v_reliable then
    -- Sin cambios no hay foto, salvo la de fin de mes, que se saca igual.
    if p_reason <> 'month_end' then
      return;
    end if;
    v_changed := false;
  end if;

  insert into costing.recipe_cost_current (group_id, restaurant_id, recipe_id, recipe_version_id, as_of, total_cost,
                                           total_gross_cost, cost_per_base_unit, cost_per_portion, reliability)
  values (p_group_id, p_restaurant_id, p_recipe_id, p_version_id, v_today, v_total, v_gross, v_unit, v_portion, v_reliable)
  on conflict (recipe_id, restaurant_id) where deleted_at is null
  do update set recipe_version_id = excluded.recipe_version_id, as_of = excluded.as_of, total_cost = excluded.total_cost,
                total_gross_cost = excluded.total_gross_cost, cost_per_base_unit = excluded.cost_per_base_unit,
                cost_per_portion = excluded.cost_per_portion, reliability = excluded.reliability;

  insert into costing.recipe_cost_snapshots (group_id, restaurant_id, recipe_id, recipe_version_id, as_of, reason, total_cost,
                                             total_gross_cost, cost_per_base_unit, cost_per_portion, reliability)
  values (p_group_id, p_restaurant_id, p_recipe_id, p_version_id, v_today, p_reason, v_total, v_gross, v_unit, v_portion, v_reliable)
  returning id into v_snapshot;

  insert into costing.recipe_cost_snapshot_lines (group_id, restaurant_id, snapshot_id, recipe_version_id, line_order, item, ingredient_id, sub_recipe_id,
                                                  sub_recipe_version_id, quantity, unit_id, quantity_basis, base_quantity,
                                                  purchase_quantity, yield_profile_id, cleaning_yield, cooking_factor, price_record_id,
                                                  price_level, package_base_quantity, vat_condition, unit_cost, gross_unit_cost,
                                                  line_cost, line_gross_cost, share_pct, line_status)
  select p_group_id, p_restaurant_id, v_snapshot, p_version_id, l.line_order, l.item, l.ingredient_id, l.sub_recipe_id,
         l.sub_recipe_version_id, l.quantity, l.unit_id, l.quantity_basis::recipes.quantity_basis, costing.fit(l.base_quantity, 9e11),
         costing.fit(l.purchase_quantity, 9e11), l.yield_profile_id, l.cleaning_yield, l.cooking_factor, l.price_record_id,
         l.price_level::core.scope_type, l.package_base_quantity, l.vat_condition::org.vat_condition, costing.fit(l.unit_cost, 9e11),
         costing.fit(l.gross_unit_cost, 9e11), costing.fit(l.line_cost, 9e13), costing.fit(l.line_gross_cost, 9e13),
         case when p_total.total_cost > 0 then round(l.line_cost / p_total.total_cost * 100, 2) end, l.status
    from unnest(p_lines) l;

  if v_changed then
    perform integration.emit(p_group_id, 'cost.changed', 'costing.recipe_cost_snapshots', v_snapshot,
                             jsonb_build_object('recipe_id', p_recipe_id, 'recipe_version_id', p_version_id,
                                                'restaurant_id', p_restaurant_id, 'reason', p_reason, 'reliability', v_reliable));
  end if;
end
$$;

create or replace function costing.process_recalc_queue(p_limit integer default 500)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  b      record;
  r      record;
  v_done integer := 0;
begin
  if not pg_try_advisory_xact_lock(hashtext('costing.process_recalc_queue')) then
    return 0;
  end if;
  for b in
    with pending as (
      select q.* from costing.cost_recalc_queue q
       where q.processed_at is null and q.attempts < 3
       order by q.entry_number
       limit p_limit)
    select p.group_id, p.reason, min(p.entry_number) as first_entry, array_agg(p.id) as ids,
           (select array_agg(distinct x) from pending o cross join lateral unnest(o.recipe_ids) x
             where o.group_id = p.group_id and o.reason = p.reason) as recipe_ids,
           case when not bool_or(p.restaurant_ids is null)
                then (select coalesce(array_agg(distinct x), '{}') from pending o cross join lateral unnest(o.restaurant_ids) x
                       where o.group_id = p.group_id and o.reason = p.reason) end as restaurant_ids
      from pending p
     group by p.group_id, p.reason
     order by 3
  loop
    begin
      perform costing.refresh_recipes(b.recipe_ids, b.restaurant_ids, b.reason);
      update costing.cost_recalc_queue set processed_at = now(), error = null where id = any (b.ids);
      v_done := v_done + cardinality(b.ids);
      perform costing.notify_cost_changed(q.source_recipe_id)
         from (select distinct y.source_recipe_id from costing.cost_recalc_queue y
                where y.id = any (b.ids) and y.source_recipe_id is not null) q;
      -- El recálculo completo del grupo salió bien: lo que había fallado antes ya está al día. El error queda guardado.
      -- Una foto de fin de mes no: la cierra otra foto que salga bien (la recupera la tarea diaria).
      if b.reason = 'daily' then
        update costing.cost_recalc_queue x set processed_at = now()
         where x.group_id = b.group_id and x.processed_at is null and x.attempts >= 3
           and x.reason <> 'month_end' and x.entry_number < b.first_entry;
      elsif b.reason = 'month_end' then
        update costing.cost_recalc_queue x set processed_at = now()
         where x.group_id = b.group_id and x.processed_at is null and x.attempts >= 3
           and x.reason = 'month_end' and x.entry_number < b.first_entry;
      end if;
    exception when others then
      for r in select x.id, x.recipe_ids, x.restaurant_ids, x.reason from costing.cost_recalc_queue x
                where x.id = any (b.ids) order by x.entry_number loop
        begin
          perform costing.refresh_recipes(r.recipe_ids, r.restaurant_ids, r.reason);
          update costing.cost_recalc_queue set processed_at = now(), error = null where id = r.id;
          v_done := v_done + 1;
          perform costing.notify_cost_changed(x.source_recipe_id)
             from costing.cost_recalc_queue x where x.id = r.id and x.source_recipe_id is not null;
        exception when others then
          update costing.cost_recalc_queue set attempts = attempts + 1, error = left(sqlerrm, 500) where id = r.id;
        end;
      end loop;
    end;
  end loop;
  return v_done;
end
$$;
