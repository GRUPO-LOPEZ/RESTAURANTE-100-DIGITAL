-- Las pruebas obligatorias 2, 3 y 7 de la Fase 1, sobre las recetas reales (ADR-0023). Antes se probaban con el documento
-- de ensayo, que se retiró. Personas del seed: 403 Directora, 405 Chef, 406 Jefe de Cocina, 407 Controller, 409 Cocinera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(45);

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
    v := 'ERROR ' || sqlstate;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.rec(p_code text) returns uuid language sql as $$
  select id from recipes.recipes where code = p_code
$$;
create temporary table ids (k text primary key, id uuid);
grant select on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant execute on function pg_temp.u(int), pg_temp.rec(text), pg_temp.id(text) to authenticated;
create function pg_temp.res(p_user uuid, p_call text) returns text language sql as $$
  select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call))
$$;
create function pg_temp.decide(p_user uuid, p_request uuid) returns text language sql as $$
  select pg_temp.q(p_user, format('select workflow.decide_approval(%L, ''approved'', null) ->> ''result''', p_request))
$$;
create function pg_temp.status(p_version uuid) returns text language sql as $$
  select status::text from recipes.recipe_versions where id = p_version
$$;

-- ---------------------------------------------------------------------------
-- 2. El cocinero abre la receta vigente pero no ve costos
-- ---------------------------------------------------------------------------
select costing.process_recalc_queue(1000);
create temporary table official as
  select total_cost from costing.recipe_cost_current
   where recipe_id = pg_temp.rec('DEMO-PAS-03') and restaurant_id = pg_temp.u(201) and deleted_at is null;
select ok((select total_cost from official) > 0, '2. la receta tiene costo calculado en el local');
select is(pg_temp.q(pg_temp.u(409), $$select recipes.kitchen_card(pg_temp.rec('DEMO-PAS-03')) ->> 'name'$$), 'Ravioles de ricota',
  '2. el cocinero abre la receta vigente');
select ok(pg_temp.q(pg_temp.u(409), $$select recipes.kitchen_card(pg_temp.rec('DEMO-PAS-03'))::text$$)
          !~* '(ERROR|cost|price|precio|costo|currency|margin)', '2. y no trae ningún valor económico');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.recipe_cost_current'), '0', '2. no lee el costo vigente');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.recipe_cost_snapshots'), '0', '2. ni las fotos del costo');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.price_records'), '0', '2. ni los precios');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from costing.price_settings'), '0', '2. ni su configuración');
select is(pg_temp.q(pg_temp.u(407), format('select total_cost::text from costing.recipe_cost_current where recipe_id = %L and restaurant_id = %L',
                                           pg_temp.rec('DEMO-PAS-03'), pg_temp.u(201))),
  (select total_cost::text from official), 'el Controller sí ve ese costo');
-- El id se busca afuera: con la sesión del cocinero, la receta no se ve y la ficha recibiría vacío sin probar nada.
select ok(pg_temp.rec('DEMO-PAR-01') is not null, 'la receta de otra marca existe');
select is(pg_temp.q(pg_temp.u(409), format('select coalesce(recipes.kitchen_card(%L)::text, ''nada'')', pg_temp.rec('DEMO-PAR-01'))), 'nada',
  'el cocinero no ve recetas de otra marca');

-- ---------------------------------------------------------------------------
-- 3. El jefe de cocina crea un borrador pero no publica sin permiso
-- ---------------------------------------------------------------------------
insert into ids values ('receta', (pg_temp.q(pg_temp.u(406), $$select recipes.create_recipe(null, null, pg_temp.u(201),
  'Ñoquis del 29', 'dish', pg_temp.u(1062), 'Receta nueva del local') ->> 'id'$$))::uuid);
select ok(pg_temp.id('receta') is not null, '3. el jefe de cocina crea una receta en su local');
insert into ids values ('v1', (select id from recipes.recipe_versions where recipe_id = pg_temp.id('receta')));
select is(pg_temp.status(pg_temp.id('v1')), 'draft', '3. queda en borrador');
select is(pg_temp.q(pg_temp.u(409), format('select count(*)::text from recipes.recipe_versions where id = %L', pg_temp.id('v1'))), '0',
  '3. el cocinero no ve borradores');
select is(pg_temp.res(pg_temp.u(406), format($$recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000827", "quantity": 250, "unit": "g"}]', 'Componentes')$$, pg_temp.id('v1'))),
  'applied', '3. carga los componentes');
select is(pg_temp.res(pg_temp.u(406), format($$recipes.set_steps(%L, '[{"instructions": "Amasar", "active_minutes": 20}]', 'Pasos')$$, pg_temp.id('v1'))),
  'applied', '3. y los pasos');
select is(pg_temp.res(pg_temp.u(406), format($$recipes.save_draft(%L, '{"yield_quantity": "1", "yield_unit": "kg", "portions": 4}', 'Rendimiento')$$, pg_temp.id('v1'))),
  'applied', '3. y el rendimiento');
select is(pg_temp.res(pg_temp.u(406), format($$recipes.request_review(%L, 'Lista para revisar')$$, pg_temp.id('v1'))),
  'pending_approval', '3. pide la revisión');
select is((select review_requested_by from recipes.recipe_versions where id = pg_temp.id('v1')), pg_temp.u(406),
  '1. la base anota quién la mandó a revisión');
select is(pg_temp.q(pg_temp.u(403), format('select review_requested_by::text from recipes.recipe_versions where id = %L', pg_temp.id('v1'))),
  pg_temp.u(406)::text, '1. y quien decide lo ve');
insert into ids values ('pedido', (select approval_request_id from recipes.recipe_versions where id = pg_temp.id('v1')));
select is(pg_temp.decide(pg_temp.u(406), pg_temp.id('pedido')), 'denied', '3. pero no la puede publicar');
select is(pg_temp.status(pg_temp.id('v1')), 'in_review', '3. y sigue en revisión');
select is((select count(*) from audit.authentication_security_events
             where event_type = 'operation_denied' and operation = 'workflow.decide_approval' and actor_id = pg_temp.u(406)
               and reason = 'No podés decidir esta solicitud.'),
  1::bigint, '11. el intento queda en el registro de seguridad, una vez y por falta de permiso');
select is(pg_temp.decide(pg_temp.u(405), pg_temp.id('pedido')), 'approved', '3. la chef de la marca la aprueba');
select is(pg_temp.status(pg_temp.id('v1')), 'published', '3. y queda publicada');

-- ---------------------------------------------------------------------------
-- 7. Una versión aprobada conserva su historia
-- ---------------------------------------------------------------------------
select throws_ok(format($q$update recipes.recipe_versions set change_summary = 'Otra cosa' where id = %L$q$, pg_temp.id('v1')),
  '42501', null, '7. una versión publicada no se modifica');
select throws_ok(format($q$update recipes.recipe_components set quantity = 1 where recipe_version_id = %L$q$, pg_temp.id('v1')),
  '42501', null, '7. ni sus líneas');
select is(pg_temp.res(pg_temp.u(405), format('recipes.new_version(%L, ''Más cocción'')', pg_temp.id('receta'))), 'applied',
  '7. corregir es crear la versión 2');
insert into ids values ('v2', (select id from recipes.recipe_versions where recipe_id = pg_temp.id('receta') and version_number = 2));
select is(pg_temp.res(pg_temp.u(405), format($$recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000827", "quantity": 300, "unit": "g"}]', 'Más harina')$$, pg_temp.id('v2'))),
  'applied', '7. que cambia sus líneas');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.request_review(%L, 'Revisión')$$, pg_temp.id('v2'))), 'pending_approval', '7. y pide la revisión');
select is(pg_temp.decide(pg_temp.u(405), (select approval_request_id from recipes.recipe_versions where id = pg_temp.id('v2')))
          || '/' || pg_temp.decide(pg_temp.u(403), (select approval_request_id from recipes.recipe_versions where id = pg_temp.id('v2'))),
  'denied/approved', '1. quien la mandó no la publica, y otra persona sí');
select ok(exists (select 1 from audit.authentication_security_events
                   where event_type = 'operation_denied' and operation = 'workflow.decide_approval' and actor_id = pg_temp.u(405)
                     and reason like 'No podés decidir una solicitud propia%'),
  '1. aprobar lo propio queda en el registro de seguridad, con su motivo');
select is(pg_temp.status(pg_temp.id('v1')) || '/' || pg_temp.status(pg_temp.id('v2')), 'archived/published', '7. la v1 queda archivada y la v2 vigente');
select is((select quantity from recipes.recipe_components where recipe_version_id = pg_temp.id('v1') and deleted_at is null), 250::numeric,
  '7. la v1 conserva sus líneas');
select is((select quantity from recipes.recipe_components where recipe_version_id = pg_temp.id('v2') and deleted_at is null), 300::numeric,
  '7. y la v2 tiene las suyas');
select is((select string_agg(new_values ->> 'status', ',' order by sequence_number) from audit.audit_events
            where table_name = 'recipe_versions' and record_id = pg_temp.id('v1')
              and (action::text = 'insert' or old_values ->> 'status' is distinct from new_values ->> 'status')),
  'draft,in_review,approved,published,archived', '7. y su historia queda completa');
select is((select string_agg(action::text, ',' order by sequence_number) from audit.audit_events
            where table_name = 'recipe_versions' and record_id = pg_temp.id('v1')
              and (action::text = 'insert' or old_values ->> 'status' is distinct from new_values ->> 'status')),
  'insert,update,update,publish,update', '7. con la publicación como tal');

-- ---------------------------------------------------------------------------
-- El retiro: se fue lo de ensayo, y el historial lo sigue entendiendo
-- ---------------------------------------------------------------------------
select ok(to_regclass('core.test_documents') is null, 'no queda la tabla');
select ok(to_regclass('core.v_test_documents') is null, 'ni la vista');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'core' and p.proname like '%test_document%'), 0::bigint, 'ni las funciones');
select is((select count(*) from core.permissions where module = 'test_documents' and deleted_at is null), 0::bigint, 'ni los permisos');
select is((select count(*) from core.role_permissions rp join core.permissions p on p.id = rp.permission_id
            where p.module = 'test_documents' and rp.deleted_at is null), 0::bigint, 'ni en los roles');
select ok(exists (select 1 from core.permissions where module = 'test_documents' and deleted_at is not null), 'los permisos quedan dados de baja');

-- Un evento viejo del documento de ensayo: se sigue leyendo, y el costo se sigue tapando en el historial y la exportación.
set local role audit_owner;
insert into audit.audit_events (table_schema, table_name, record_id, action, new_values, module, scope_group_id, scope_brand_id)
values ('core', 'test_documents', '00000000-0000-4000-8000-000000099601', 'insert', '{"cost": 1520.5, "title": "Salsa"}', 'test_documents',
        '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101');
reset role;
create function pg_temp.old_event(p_call text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(410), p_call)
$$;
select is(pg_temp.old_event($$select (new_values ->> 'cost') || '/' || (new_values ->> 'title')
                                from core.audit_history(5, p_module => 'test_documents') where table_name = 'test_documents'$$),
  '1520.5/Salsa', 'el Auditor lee un evento viejo por el historial');
do $$
begin
  perform core.set_change_context('Prueba: sin permiso de costos', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = 'auditor')
     and permission_id = (select id from core.permissions where code = 'recipes.view_costs');
end
$$;
select is(pg_temp.old_event($$select (new_values ->> 'cost') || '/' || (new_values ->> 'title')
                                from core.audit_history(5, p_module => 'test_documents') where table_name = 'test_documents'$$),
  '[oculto]/Salsa', 'sin ver costos, el historial lo tapa');
select is(pg_temp.old_event($$select new_value from core.audit_export(now() - interval '1 day', now() + interval '1 day', p_module => 'test_documents')
                               where field = 'cost'$$),
  '[oculto]', 'y la exportación también');

select * from finish();
rollback;
