-- Fase 2 · Etapa 2.3, PR 3A: los costos se mantienen al día solos (ADR-0032). Tarea diaria, foto de fin de mes,
-- recálculos fallidos, aviso con impacto solo a quien ve costos, y eventos sin importes.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(49);

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.q(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
-- Una materia prima que se usa en gramos y se compra por kg: el precio del envase es el precio por kg.
create function pg_temp.ing(p_n int) returns void language sql as $$
  insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
  values (pg_temp.u(95000 + p_n), pg_temp.u(1), 'COSTO-ING-' || p_n, 'Materia prima ' || p_n, pg_temp.u(707),
          (select id from catalog.units where code = 'g'));
  insert into catalog.purchase_products (id, group_id, code, ingredient_id, description, package_unit_id, units_per_package,
                                         content_per_unit, content_unit_id)
  values (pg_temp.u(96000 + p_n), pg_temp.u(1), 'COSTO-PROD-' || p_n, pg_temp.u(95000 + p_n), 'Producto ' || p_n,
          (select id from catalog.units where code = 'kg'), 1, 1000, (select id from catalog.units where code = 'g'));
$$;
-- Precios sin factura (el precio es el final), salvo que se pida factura con 21 %.
create function pg_temp.price(p_n int, p_price numeric, p_scope text default 'group', p_place int default null,
                              p_days_ago int default 1, p_invoice boolean default false)
returns void language sql as $$
  insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, restaurant_id, valid_from, package_price,
                                     document_type, vat_rate, source)
  values (pg_temp.u(1), pg_temp.u(96000 + p_n), p_scope::core.scope_type,
          case when p_scope = 'brand' then pg_temp.u(p_place) end,
          case when p_scope = 'restaurant' then pg_temp.u(p_place) end,
          current_date - p_days_ago, p_price,
          case when p_invoice then 'invoice' else 'no_invoice' end::costing.price_document,
          case when p_invoice then 21 end, 'test_value')
$$;
create function pg_temp.yield(p_n int, p_process int, p_clean numeric, p_cook numeric) returns uuid language sql as $$
  insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, status,
                                                 approved_by, approved_at)
  values (pg_temp.u(1), pg_temp.u(95000 + p_n), pg_temp.u(p_process), p_clean, p_cook, 'approved', pg_temp.u(413), now())
  returning id
$$;
create function pg_temp.recipe(p_n int, p_kind text, p_yield numeric, p_unit text, p_portions int) returns void language sql as $$
  insert into recipes.recipes (id, group_id, scope_type, code, name, recipe_type, category_id)
  values (pg_temp.u(97000 + p_n), pg_temp.u(1), 'group', 'COSTO-REC-' || p_n, 'Receta ' || p_n, p_kind::recipes.recipe_type, pg_temp.u(1061));
  insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions)
  values (pg_temp.u(98000 + p_n), pg_temp.u(1), pg_temp.u(97000 + p_n), 1, p_yield,
          (select id from catalog.units where code = p_unit), p_portions);
$$;
create function pg_temp.line(p_n int, p_order int, p_ing int, p_qty numeric, p_unit text, p_basis text default 'purchase',
                             p_profile uuid default null)
returns void language sql as $$
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id, quantity_basis,
                                         yield_profile_id)
  values (pg_temp.u(1), pg_temp.u(98000 + p_n), p_order, pg_temp.u(95000 + p_ing), p_qty,
          (select id from catalog.units where code = p_unit), p_basis::recipes.quantity_basis, p_profile)
$$;
create function pg_temp.sub(p_n int, p_order int, p_sub int, p_qty numeric, p_unit text) returns void language sql as $$
  insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
  values (pg_temp.u(1), pg_temp.u(98000 + p_n), p_order, pg_temp.u(97000 + p_sub), p_qty,
          (select id from catalog.units where code = p_unit), 'finished')
$$;
create function pg_temp.publish(p_n int) returns void language sql as $$
  update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(98000 + p_n);
  update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(98000 + p_n);
  update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(98000 + p_n);
$$;
create function pg_temp.assign(p_n int, p_rest int) returns void language sql as $$
  insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
  values (pg_temp.u(1), pg_temp.u(97000 + p_n), pg_temp.u(p_rest), current_date - 1)
$$;
create function pg_temp.cost(p_n int, p_rest int, p_column text default 'total_cost') returns text language plpgsql as $$
declare
  v text;
begin
  perform costing.process_recalc_queue(1000);
  execute format('select %I::text from costing.recipe_cost_current where recipe_id = $1 and restaurant_id = $2 and deleted_at is null', p_column)
    into v using pg_temp.u(97000 + p_n), pg_temp.u(p_rest);
  return v;
end
$$;
create function pg_temp.line_status(p_n int, p_rest int) returns text language sql as $$
  select string_agg(l.status, ',' order by l.line_order)
    from costing.recipe_line_costs_internal(pg_temp.u(98000 + p_n), pg_temp.u(p_rest), current_date) l
$$;

create function pg_temp.snapshots(p_n int, p_rest int, p_reason text) returns bigint language sql as $$
  select costing.process_recalc_queue(1000);
  select count(*) from costing.recipe_cost_snapshots
   where recipe_id = pg_temp.u(97000 + p_n) and restaurant_id = pg_temp.u(p_rest) and reason::text = p_reason
$$;

-- La foto de este mes ya se sacó: las pruebas de la tarea diaria no la disparan.
insert into costing.cost_recalc_queue (group_id, recipe_ids, reason, processed_at)
select pg_temp.u(1), array[id], 'month_end', now() from recipes.recipes limit 1;

-- Un plato con un precio de hace 10 días.
select pg_temp.ing(1);
select pg_temp.price(1, 1000, 'group', null, 10);
select pg_temp.recipe(1, 'dish', 1000, 'g', 1);
select pg_temp.line(1, 1, 1, 1000, 'g');
select pg_temp.publish(1);
select pg_temp.assign(1, 201);
select is(pg_temp.cost(1, 201), '1000.0000', 'de partida, $ 1.000');

-- Un precio con fecha futura no cambia nada hasta su día.
insert into costing.price_records (id, group_id, purchase_product_id, scope_type, valid_from, package_price, document_type, source)
values (pg_temp.u(99200), pg_temp.u(1), pg_temp.u(96001), 'group', recipes.today() + 1, 2000, 'no_invoice', 'test_value');
select is(pg_temp.cost(1, 201), '1000.0000', 'un precio de mañana todavía no cuenta');
select is((select count(*) from costing.cost_recalc_queue where price_record_id = pg_temp.u(99200)), 0::bigint, 'y no anota un pedido');
-- La tarea del día anterior tampoco lo toma.
select costing.daily_refresh(recipes.today());
select is((select count(*) from costing.cost_recalc_queue where price_record_id = pg_temp.u(99200)), 0::bigint, 'la tarea de hoy no toma un precio de mañana');
-- Mañana, sí, con su pedido: el impacto queda anclado.
select costing.daily_refresh(recipes.today() + 1);
select is((select count(*) from costing.cost_recalc_queue where price_record_id = pg_temp.u(99200)), 1::bigint, 'la tarea de ese día anota su pedido');
select costing.daily_refresh(recipes.today() + 1);
select is((select count(*) from costing.cost_recalc_queue where price_record_id = pg_temp.u(99200)), 1::bigint, 'y no lo repite');

-- La tarea diaria: "desactualizado" se actualiza sin que nadie toque nada.
select pg_temp.ing(2);
select pg_temp.price(2, 1000, 'restaurant', 201, 10);
select pg_temp.recipe(2, 'dish', 1000, 'g', 1);
select pg_temp.line(2, 1, 2, 1000, 'g');
select pg_temp.publish(2);
select pg_temp.assign(2, 201);
select is(pg_temp.cost(2, 201, 'reliability'), 'verified', 'con el precio al día, verificado');
insert into costing.price_settings (group_id, stale_days) values (pg_temp.u(1), 5)
  on conflict (group_id) where deleted_at is null do update set stale_days = 5;
select is(pg_temp.cost(2, 201, 'reliability'), 'verified', 'cambiar el plazo no recalcula en el momento');
select costing.daily_refresh();
select is(pg_temp.cost(2, 201, 'reliability'), 'stale', 'la tarea diaria lo pasa a desactualizado');
select cmp_ok(pg_temp.snapshots(2, 201, 'daily'), '>=', 1::bigint, 'con una foto de la tarea diaria');
update costing.price_settings set stale_days = 30 where group_id = pg_temp.u(1);
select costing.daily_refresh();
select is(pg_temp.cost(2, 201, 'reliability'), 'verified', 'y vuelve si cambia el plazo');
create temporary table before_daily as select pg_temp.snapshots(2, 201, 'daily') as n;
select costing.daily_refresh();
select is(pg_temp.snapshots(2, 201, 'daily'), (select n from before_daily), 'sin cambios, la tarea diaria no saca foto');

-- Una asignación que venció sola.
select pg_temp.recipe(3, 'dish', 1000, 'g', 1);
select pg_temp.line(3, 1, 2, 1000, 'g');
select pg_temp.publish(3);
select pg_temp.assign(3, 201);
select is(pg_temp.cost(3, 201), '1000.0000', 'una receta asignada');
alter table recipes.recipe_assignments disable trigger recalculate_costs;
update recipes.recipe_assignments set valid_to = recipes.today() where recipe_id = pg_temp.u(97003);
alter table recipes.recipe_assignments enable trigger recalculate_costs;
select costing.daily_refresh();
select is(pg_temp.cost(3, 201), null, 'al vencer su asignación, la tarea diaria da de baja el costo');

-- La foto de fin de mes se saca aunque nada cambie.
select is(pg_temp.snapshots(2, 201, 'month_end'), 0::bigint, 'todavía no hay foto de fin de mes');
select costing.month_end_snapshots();
select is(pg_temp.snapshots(2, 201, 'month_end'), 1::bigint, 'se saca aunque nada haya cambiado');
select is((select count(*) from costing.recipe_cost_snapshot_lines l join costing.recipe_cost_snapshots s on s.id = l.snapshot_id
            where s.recipe_id = pg_temp.u(97002) and s.reason = 'month_end'), 1::bigint, 'con su detalle');
select is((select count(*) from integration.integration_outbox o
            where o.event_type = 'cost.changed' and o.payload ->> 'reason' = 'month_end'), 0::bigint,
  'la foto de fin de mes sin cambios no es un evento');

-- Un recálculo que falló: la tarea diaria lo cierra si todo sale bien.
insert into costing.cost_recalc_queue (group_id, recipe_ids, reason, attempts, error)
values (pg_temp.u(1), array[pg_temp.u(97002)], 'publish', 3, 'Falla de prueba');
select is(pg_temp.q(pg_temp.u(407), 'select failed::text from costing.recalc_status()'), '1', 'el fallido se ve');
select costing.daily_refresh();
select costing.process_recalc_queue(1000);
select is(pg_temp.q(pg_temp.u(407), 'select failed::text from costing.recalc_status()'), '0', 'el recálculo completo lo cierra');
select is((select error from costing.cost_recalc_queue where attempts = 3 limit 1), 'Falla de prueba', 'el error queda guardado');
-- Si la tarea diaria falla, el aviso queda.
insert into costing.cost_recalc_queue (group_id, recipe_ids, reason, attempts, error)
values (pg_temp.u(1), array[pg_temp.u(97002)], 'publish', 3, 'Otra falla');
create function pg_temp.boom() returns trigger language plpgsql as $f$
begin
  raise exception 'Falla de prueba';
end
$f$;
update costing.price_settings set stale_days = 5 where group_id = pg_temp.u(1);
create trigger boom before update on costing.recipe_cost_current for each row execute function pg_temp.boom();
select costing.daily_refresh();
select costing.process_recalc_queue(1000);
select is((select count(*) from costing.cost_recalc_queue where error = 'Otra falla' and processed_at is null), 1::bigint,
  'si el recálculo completo falla, el fallido sigue abierto');
drop trigger boom on costing.recipe_cost_current;
update costing.price_settings set stale_days = 30 where group_id = pg_temp.u(1);
update costing.cost_recalc_queue set processed_at = now() where processed_at is null;

-- Una foto de fin de mes fallida no se cierra: se perdería.
insert into costing.cost_recalc_queue (group_id, recipe_ids, reason, attempts, error)
values (pg_temp.u(1), array[pg_temp.u(97002)], 'month_end', 3, 'Falla de cierre');
select costing.daily_refresh();
select costing.process_recalc_queue(1000);
select is((select count(*) from costing.cost_recalc_queue where error = 'Falla de cierre' and processed_at is null), 1::bigint,
  'el recálculo diario no cierra una foto de fin de mes fallida');
-- La tarea diaria de la primera semana la reanota, sale la foto y se va el aviso.
delete from costing.cost_recalc_queue where reason = 'month_end' and error is null;
select costing.daily_refresh(date_trunc('month', recipes.today())::date);
select costing.process_recalc_queue(1000);
select is((select count(*) from costing.cost_recalc_queue where error = 'Falla de cierre' and processed_at is null), 0::bigint,
  'una foto que sale bien cierra la fallida');
select cmp_ok(pg_temp.snapshots(2, 201, 'month_end'), '>=', 2::bigint, 'y la foto se sacó');
select is(pg_temp.q(pg_temp.u(407), 'select failed::text from costing.recalc_status()'), '0', 'y el aviso se va');
update costing.cost_recalc_queue set processed_at = now() where processed_at is null;

-- Un pedido anotado después del diario tampoco se cierra.
insert into costing.cost_recalc_queue (group_id, recipe_ids, reason, processed_at)
select pg_temp.u(1), array[id], 'month_end', now() from recipes.recipes limit 1;
select costing.daily_refresh();
insert into costing.cost_recalc_queue (group_id, recipe_ids, reason, attempts, error)
values (pg_temp.u(1), array[pg_temp.u(97002)], 'publish', 3, 'Falla posterior');
select costing.process_recalc_queue(1000);
select is((select count(*) from costing.cost_recalc_queue where error = 'Falla posterior' and processed_at is null), 1::bigint,
  'un fallido posterior al recálculo diario sigue abierto');
update costing.cost_recalc_queue set processed_at = now() where processed_at is null;

-- Si la foto de fin de mes no corrió, la tarea diaria la saca en la primera semana del mes siguiente.
select costing.daily_refresh((date_trunc('month', recipes.today()) + interval '2 months')::date);
select is((select count(*) from costing.cost_recalc_queue where reason = 'month_end' and processed_at is null), 1::bigint,
  'la tarea diaria recupera la foto que faltó');
update costing.cost_recalc_queue set processed_at = now() where processed_at is null;

-- El aviso con el impacto: una preparación nueva que encarece un plato.
select pg_temp.ing(3);
select pg_temp.price(3, 1000, 'group', null, 2);
select pg_temp.recipe(4, 'preparation', 1000, 'g', null);
select pg_temp.line(4, 1, 3, 1000, 'g');
select pg_temp.publish(4);
select pg_temp.recipe(5, 'dish', 1, 'unit', 1);
select pg_temp.sub(5, 1, 4, 500, 'g');
select pg_temp.publish(5);
select pg_temp.assign(5, 201);
select pg_temp.assign(5, 203);
select is(pg_temp.cost(5, 201), '500.0000', 'de partida, $ 500');
select is((select count(*) from core.notifications where kind = 'recipe_cost_changed' and link like '%0000000970%'), 0::bigint, 'sin cambios de costo no hay aviso');
-- Las fotos de partida son de una corrida anterior: en la prueba, todo pasa en la misma transacción.
alter table costing.recipe_cost_snapshots disable trigger user;
update costing.recipe_cost_snapshots set created_at = created_at - interval '1 hour';
alter table costing.recipe_cost_snapshots enable trigger user;
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, previous_version_id)
values (pg_temp.u(98104), pg_temp.u(1), pg_temp.u(97004), 2, 500, (select id from catalog.units where code = 'g'), pg_temp.u(98004));
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
values (pg_temp.u(1), pg_temp.u(98104), 1, pg_temp.u(95003), 1000, (select id from catalog.units where code = 'g'));
update recipes.recipe_versions set status = 'archived' where id = pg_temp.u(98004);
update recipes.recipe_versions set status = 'in_review' where id = pg_temp.u(98104);
update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(413) where id = pg_temp.u(98104);
update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.u(98104);
select is(pg_temp.cost(5, 201), '1000.0000', 'la versión nueva rinde la mitad: el plato cuesta el doble');

create function pg_temp.notice(p_user int) returns text language sql as $$
  select title || ' / ' || body from core.notifications
   where kind = 'recipe_cost_changed' and recipient_user_id = pg_temp.u(p_user) order by created_at desc limit 1
$$;
select is(pg_temp.notice(407), 'Cambió el costo de «Receta 4» / 1 receta en 2 de tus locales.', 'el Controller recibe el aviso de sus dos locales');
select is(pg_temp.notice(404), 'Cambió el costo de «Receta 4» / 1 receta en 1 de tus locales.', 'el Gerente cuenta solo su local');
select is(pg_temp.notice(405), 'Cambió el costo de «Receta 4» / 1 receta en 1 de tus locales.', 'la Chef de la marca, solo los de su marca');
select is((select count(*) from core.notifications where kind = 'recipe_cost_changed' and link like '%0000000970%' and body ~ '[$%]'), 0::bigint,
  'el aviso no lleva importes ni porcentajes');
select is(pg_temp.q(pg_temp.u(404), format('select count(*)::text from core.notifications where recipient_user_id = %L and kind = ''recipe_cost_changed''', pg_temp.u(407))), '0',
  'nadie lee el aviso de otro');
select is(pg_temp.notice(408), null, 'Compras no');
select is(pg_temp.notice(406), null, 'el Jefe de Cocina tampoco');
select is(pg_temp.notice(409), null, 'ni la Cocinera');
select is((select link from core.notifications where kind = 'recipe_cost_changed' and recipient_user_id = pg_temp.u(407) and link like '%0000000970%' limit 1),
  format('/costos/%s?local=%s', pg_temp.u(97004), pg_temp.u(201)), 'con enlace al costo en ese local');

-- Los eventos.
select cmp_ok((select count(*) from integration.integration_outbox where event_type = 'cost.changed'), '>', 0::bigint, 'el cambio de costo es un evento');
select is((select count(*) from integration.integration_outbox where event_type = 'recipe.published' and aggregate_id = pg_temp.u(98104)), 1::bigint,
  'la publicación también');
select is((select count(*) from integration.integration_outbox where payload::text ~* '(total_cost|package_price|unit_cost|line_cost)'), 0::bigint,
  'ningún evento lleva importes');
select ok(not has_schema_privilege('authenticated', 'integration', 'usage') and not has_schema_privilege('anon', 'integration', 'usage')
           and not has_schema_privilege('service_role', 'integration', 'usage'), 'el esquema no se expone');
select ok(not has_table_privilege('authenticated', 'integration.integration_outbox', 'select')
           and not has_table_privilege('anon', 'integration.integration_outbox', 'select'), 'ni la tabla');
select is((select relrowsecurity from pg_class where oid = 'integration.integration_outbox'::regclass), true, 'con RLS activo');

-- Las tareas.
select is((select schedule from cron.job where jobname = 'grupo-lf-costos-diario'), '30 6 * * *', 'la tarea diaria corre a las 3:30 de la Argentina');
select is((select schedule from cron.job where jobname = 'grupo-lf-costos-fin-de-mes'), '30 2 1 * *', 'la de fin de mes, el último día a las 23:30');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where (n.nspname, p.proname) in (('costing', 'daily_refresh'), ('costing', 'month_end_snapshots'), ('costing', 'enqueue_price'),
                                             ('costing', 'notify_cost_changed'), ('costing', 'fit'), ('integration', 'emit'))
              and has_function_privilege('authenticated', p.oid, 'execute')), 0::bigint, 'las funciones nuevas no se llaman desde afuera');

select * from finish();
rollback;
