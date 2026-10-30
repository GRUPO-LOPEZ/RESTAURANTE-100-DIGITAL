-- Fase 1 · M5: has_permission, lectura por la API con RLS, escrituras por funciones,
-- datos del local (P10) y "un registro borrado no se edita" (P13).
-- Pruebas obligatorias del Módulo Maestro que cubre: 1 (pgTAP), 4, 5, 9, 10, y adicionales A3, A4 y A8 (pgTAP).
-- Personas del seed: ...0401 superadmin (grupo), ...0402 dirección (grupo), ...0403 director (marca ...101),
-- ...0404 gerente (local ...201), ...0405 chef (marca ...101), ...0406 jefe de cocina (...201), ...0407 controller,
-- ...0408 compras, ...0409 cocinero (...201), ...0410 auditor, ...0411 gerente de ...201 y ...202, ...0499 cuenta técnica.
begin;
create extension if not exists pgtap with schema extensions;

select plan(73);

-- Corre una consulta como una persona (o sin sesión si p_user es nulo) y devuelve el resultado
-- como texto, o "ERROR <código>" si falla. Vuelve siempre a postgres.
create function pg_temp.q(p_user uuid, p_sql text, p_aal text default 'aal2')
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims',
    case when p_user is null then '{"role": "anon"}'
         else json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text end, true);
  execute case when p_user is null then 'set local role anon' else 'set local role authenticated' end;
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
-- Llama a una función que no devuelve nada: "ok" si anduvo.
create function pg_temp.call(p_user uuid, p_call text, p_aal text default 'aal2')
returns text
language sql
as $$ select pg_temp.q(p_user, format('select ''ok'' from (select %s) as s', p_call), p_aal) $$;

create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;

-- ---------------------------------------------------------------------------
-- Qué abre la API (ADR-0005): la lista exacta. Si cambia, esta prueba se actualiza a propósito.
-- ---------------------------------------------------------------------------
create function pg_temp.business_schemas() returns text[] language sql as $$
  select array['core', 'org', 'audit', 'workflow', 'catalog', 'recipes', 'costing', 'purchasing',
               'inventory', 'production', 'ai', 'reporting']
$$;
select is(
  (select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname collate "C")
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = any (pg_temp.business_schemas()) and has_function_privilege('authenticated', p.oid, 'execute')),
  array['catalog.archive_category', 'catalog.archive_yield_process', 'catalog.category_usage',
        'catalog.convert_quantity', 'catalog.create_category', 'catalog.create_ingredient', 'catalog.create_purchase_product',
        'catalog.create_supplier', 'catalog.create_yield_process', 'catalog.ingredient_usage', 'catalog.process_usage',
        'catalog.propose_yield_standard', 'catalog.record_yield_test', 'catalog.rename_category', 'catalog.rename_yield_process',
        'catalog.search_components', 'catalog.set_aliases', 'catalog.set_allergen_status',
        'catalog.set_ingredient_active', 'catalog.set_unit_conversion', 'catalog.standard_yield', 'catalog.to_base_quantity',
        'catalog.update_ingredient', 'catalog.update_purchase_product', 'catalog.update_supplier', 'catalog.yield_summary',
        'core.add_member', 'core.assign_role', 'core.audit_export', 'core.audit_history', 'core.can_invite',
        'core.can_view_scope', 'core.can_view_user', 'core.create_test_document_draft', 'core.current_aal',
        'core.current_actor_id', 'core.current_actor_subject', 'core.current_session_ok', 'core.disable_user',
        'core.has_permission', 'core.has_permission_anywhere', 'core.has_permission_for_scope',
        'core.has_permission_in_brand', 'core.has_permission_in_group', 'core.is_assignment_current',
        'core.lift_suspension', 'core.mark_notifications_read', 'core.my_account', 'core.my_active_restaurant', 'core.my_scopes',
        'core.my_session', 'core.permission_matrix', 'core.permitted_brand_ids', 'core.permitted_group_ids',
        'core.permitted_restaurant_ids', 'core.publish_test_document', 'core.request_reactivation',
        'core.request_role_permission_change', 'core.request_test_document_review', 'core.revoke_role',
        'core.set_active_restaurant', 'core.suspend_user', 'core.unlock_user', 'core.update_my_profile',
        'core.user_detail', 'core.users_control_panel', 'core.users_dashboard', 'core.users_overview',
        'core.visible_assignment_ids', 'core.visible_brand_ids', 'core.visible_group_ids', 'core.visible_user_ids',
        'org.create_area',
        'org.create_brand', 'org.create_restaurant', 'org.request_transfer', 'org.set_deleted', 'org.update_area',
        'org.update_brand', 'org.update_group', 'org.update_restaurant',
        'recipes.add_media', 'recipes.archive_category', 'recipes.archive_recipe', 'recipes.can_upload_media',
        'recipes.category_usage',
        'recipes.create_category', 'recipes.create_recipe', 'recipes.critical_path', 'recipes.kitchen_card',
        'recipes.media_recipe_id', 'recipes.new_version',
        'recipes.remove_media', 'recipes.rename_category', 'recipes.request_review', 'recipes.save_draft',
        'recipes.set_assignment',
        'recipes.set_components', 'recipes.set_steps', 'recipes.update_recipe', 'recipes.version_allergens',
        'recipes.version_diff', 'recipes.viewable_recipe_ids', 'recipes.visible_media_paths',
        'recipes.visible_version_ids',
        'recipes.withdraw_review', 'recipes.workable_recipe_ids', 'workflow.cancel_request',
        'workflow.decide_approval', 'workflow.inbox'],
  'authenticated solo puede llamar a estas funciones (en los 12 esquemas de negocio)'
);
select is(
  (select array_agg(n.nspname || '.' || c.relname order by n.nspname || '.' || c.relname collate "C")
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = any (pg_temp.business_schemas()) and c.relkind in ('r', 'p', 'v', 'm')
      and has_table_privilege('authenticated', c.oid, 'select')),
  array['catalog.allergens', 'catalog.ingredient_aliases', 'catalog.ingredient_allergens',
        'catalog.ingredient_categories', 'catalog.ingredient_unit_conversions', 'catalog.ingredient_yield_profiles',
        'catalog.ingredient_yield_tests', 'catalog.ingredients', 'catalog.purchase_products', 'catalog.suppliers',
        'catalog.unit_conversions', 'catalog.units', 'catalog.yield_processes',
        'core.notifications', 'core.permissions', 'core.role_permissions', 'core.roles', 'core.user_memberships',
        'core.user_role_assignments', 'core.v_test_documents', 'org.areas', 'org.brands',
        'org.groups', 'org.restaurants', 'org.time_zones', 'recipes.recipe_assignments', 'recipes.recipe_categories',
        'recipes.recipe_components', 'recipes.recipe_media', 'recipes.recipe_step_dependencies', 'recipes.recipe_steps', 'recipes.recipe_versions',
        'recipes.recipes', 'workflow.approval_decisions',
        'workflow.approval_workflows'],
  'authenticated solo puede leer estas tablas enteras (y nada de audit ni de cuentas técnicas)'
);
-- Personas y solicitudes se leen por columna: sin los datos de administración ni el "antes" de
-- una solicitud (respuesta 2 de Joaco, ADR-0015).
select is(
  (select array_agg(a.attname::text order by a.attname::text collate "C") from pg_attribute a
    where a.attrelid = 'core.user_profiles'::regclass and a.attnum > 0 and not a.attisdropped
      and has_column_privilege('authenticated', a.attrelid, a.attnum, 'select')),
  array['area_id', 'created_at', 'created_by', 'deactivated_at', 'deleted_at', 'deleted_by', 'email',
        'first_name', 'id', 'job_title', 'last_name', 'locked_until', 'status', 'suspended_at',
        'updated_at', 'updated_by', 'username'],
  'de las personas se leen estas columnas: no el primer ni el último acceso, quién invitó, el local elegido ni los motivos'
);
select is(
  (select array_agg(a.attname::text order by a.attname::text collate "C") from pg_attribute a
    where a.attrelid = 'workflow.approval_requests'::regclass and a.attnum > 0 and not a.attisdropped
      and not has_column_privilege('authenticated', a.attrelid, a.attnum, 'select')),
  array['previous_values'], 'de las solicitudes se lee todo menos el antes (sale por la bandeja)'
);
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = any (pg_temp.business_schemas())
      and case when c.relkind = 'S' then has_sequence_privilege('authenticated', c.oid, 'usage,select,update') else false end),
  0, 'authenticated no usa ninguna secuencia de negocio'
);
select is(
  (select count(*)::int from pg_policies
    where schemaname in ('core', 'org') and (coalesce(qual, '') || coalesce(with_check, '')) like '%has_permission_anywhere%'),
  0, 'ninguna política usa has_permission_anywhere (solo sirve para menús)'
);

-- ---------------------------------------------------------------------------
-- Prueba obligatoria 1: sin sesión no se consulta información privada
-- ---------------------------------------------------------------------------
select is(pg_temp.q(null, 'select count(*)::text from org.restaurants'), 'ERROR 42501', '1. sin sesión no se leen locales');
select is(pg_temp.q(null, 'select count(*)::text from core.user_profiles'), 'ERROR 42501', '1. sin sesión no se leen personas');
select is(pg_temp.q(null, 'select core.has_permission(''org.view'', ''00000000-0000-4000-8000-000000000201'')::text'),
  'ERROR 42501', '1. sin sesión no se pueden llamar las funciones');
select is(
  pg_temp.q('11111111-1111-1111-1111-111111111111', 'select count(*)::text from org.restaurants'),
  '0', '1. un token sin persona registrada no ve nada'
);

-- ---------------------------------------------------------------------------
-- has_permission: alcance por grupo, marca y restaurante
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(401), 'select core.has_permission(''org.view'', null)::text'), 'false',
  'restaurante nulo da falso, aunque sea superadmin');
select is(pg_temp.q(pg_temp.u(401), 'select count(*)::text from org.restaurants'), '4', 'superadmin (grupo) ve los 4 locales');
select is(pg_temp.q(pg_temp.u(409), 'select string_agg(id::text, '','') from org.restaurants'),
  '00000000-0000-4000-8000-000000000201', 'el cocinero ve solo su local');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.areas'), '3', 'el cocinero ve las 3 áreas de su local');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.brands') || '/' || pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.groups'),
  '1/1', 'el cocinero ve el nombre de su marca y de su grupo, y nada más');
select is(pg_temp.q(pg_temp.u(403), 'select string_agg(right(id::text, 3), '','' order by id) from org.restaurants'),
  '201,202', 'el director de marca ve los locales de su marca');
select is(pg_temp.q(pg_temp.u(403), 'select core.has_permission_in_brand(''org.manage'', ''00000000-0000-4000-8000-000000000102'')::text'),
  'false', 'el director de marca no tiene permisos en otra marca');

-- Prueba 9: usuario con dos restaurantes opera solo en los suyos.
select is(pg_temp.q(pg_temp.u(411), 'select string_agg(right(id::text, 3), '','' order by id) from org.restaurants'),
  '201,202', '9. el gerente de dos locales ve solo sus dos locales');
select is(pg_temp.call(pg_temp.u(411), 'org.update_restaurant(''00000000-0000-4000-8000-000000000202'', ''{"phone": "11 4444-5555"}'', ''Prueba'')'),
  'ok', '9. el gerente de dos locales edita su segundo local');
select is(pg_temp.call(pg_temp.u(411), 'org.update_restaurant(''00000000-0000-4000-8000-000000000203'', ''{"phone": "11 4444-5555"}'', ''Prueba'')'),
  'ERROR 42501', '9. el gerente de dos locales no edita un local que no es suyo');

-- Prueba 5: dirección ve lo consolidado según permisos.
select is(pg_temp.q(pg_temp.u(402), 'select count(*)::text from org.restaurants'), '4', '5. dirección ve todos los locales del grupo');
select is(pg_temp.q(pg_temp.u(402), 'select count(*)::text from core.user_profiles'), '21', '5. dirección ve a todas las personas (users.view de grupo)');
select is(
  pg_temp.q(pg_temp.u(402), 'select (core.has_permission(''approvals.decide'', ''00000000-0000-4000-8000-000000000203'')
                                     and not core.has_permission(''org.manage'', ''00000000-0000-4000-8000-000000000203''))::text'),
  'true', '5. dirección aprueba en todo el grupo pero no administra la estructura (según su matriz)');

-- ---------------------------------------------------------------------------
-- Adicional A8 (parte de base): los roles con MFA no operan sin doble verificación
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from org.restaurants', 'aal1'), '0', 'A8. el gerente sin doble verificación (aal1) no ve nada');
select is(pg_temp.q(pg_temp.u(401), 'select core.has_permission(''org.view'', ''00000000-0000-4000-8000-000000000201'')::text', 'aal1'),
  'false', 'A8. el superadmin sin doble verificación no tiene ningún permiso');
select is(pg_temp.q(pg_temp.u(407), 'select count(*)::text from org.restaurants', 'aal1'), '0', 'A8. Controller sin doble verificación no ve nada');
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.restaurants', 'aal1'), '1', 'A8. el cocinero (sin MFA obligatorio) entra con contraseña sola');
select is(pg_temp.q(pg_temp.u(404), 'select core.current_session_ok()::text', 'aal1'), 'false', 'A8. la sesión del gerente sin MFA no puede operar');

-- ---------------------------------------------------------------------------
-- Prueba 4: gerente no edita fuera de su restaurante
-- ---------------------------------------------------------------------------
select is(pg_temp.call(pg_temp.u(404), 'org.update_restaurant(''00000000-0000-4000-8000-000000000202'', ''{"name": "Otro"}'', ''Prueba'')'),
  'ERROR 42501', '4. el gerente no edita otro local de su marca');
select is(pg_temp.call(pg_temp.u(404), 'org.update_area(''00000000-0000-4000-8000-000000000331'', ''{"name": "Otra"}'', ''Prueba'')'),
  'ERROR 42501', '4. el gerente no edita un área de otro local');
select is(pg_temp.call(pg_temp.u(404), 'org.create_area(''00000000-0000-4000-8000-000000000203'', ''Barra'', ''Prueba'')'),
  'ERROR 42501', '4. el gerente no crea áreas en otro local');
select is(pg_temp.q(pg_temp.u(404), 'insert into org.areas (group_id, restaurant_id, name) values (''00000000-0000-4000-8000-000000000001'', ''00000000-0000-4000-8000-000000000201'', ''Directo'') returning ''ok'''),
  'ERROR 42501', '4. nadie escribe directo en las tablas, ni en su propio local');
select is(pg_temp.call(pg_temp.u(404), 'org.update_restaurant(''00000000-0000-4000-8000-000000000201'', ''{"name": "Demo Pastas Centro Renovado"}'', ''Cambio de cartel'')'),
  'ok', 'el gerente sí edita su propio local');
select is((select name from org.restaurants where id = pg_temp.u(201)), 'Demo Pastas Centro Renovado', 'el cambio del gerente quedó guardado');
select ok(
  (select actor_user_id = pg_temp.u(404) and reason = 'Cambio de cartel' and source = 'manual'
      and actor_roles @> '[{"role": "restaurant_manager", "restaurant_id": "00000000-0000-4000-8000-000000000201"}]'
     from audit.audit_events where record_id = pg_temp.u(201) and action = 'update'
    order by sequence_number desc limit 1),
  'el historial guarda quién, el motivo, el origen y con qué roles se hizo el cambio'
);
select is(pg_temp.call(pg_temp.u(404), 'org.update_restaurant(''00000000-0000-4000-8000-000000000201'', ''{"status": "inactive"}'', ''Prueba'')'),
  'ERROR 42501', 'el gerente no puede cerrar su local (eso se decide en la marca)');
select is(pg_temp.call(pg_temp.u(404), 'org.set_deleted(''restaurants'', ''00000000-0000-4000-8000-000000000201'', true, ''Prueba'')'),
  'ERROR 42501', 'el gerente no puede borrar su local');
select is(pg_temp.call(pg_temp.u(409), 'org.update_area(''00000000-0000-4000-8000-000000000311'', ''{"name": "Cocina 2"}'', ''Prueba'')'),
  'ERROR 42501', 'el cocinero no edita la estructura');
select is(pg_temp.q(pg_temp.u(403), 'select (org.create_restaurant(''00000000-0000-4000-8000-000000000101'', ''Demo Pastas Sur'', ''{"code": "DP-SUR"}'', ''Apertura'') is not null)::text'),
  'true', 'el director de marca crea un local en su marca');
select is(pg_temp.q(pg_temp.u(403), 'select org.create_restaurant(''00000000-0000-4000-8000-000000000102'', ''Intruso'', null, ''Prueba'')::text'),
  'ERROR 42501', 'el director de marca no crea locales en otra marca');
select is(pg_temp.call(pg_temp.u(404), 'org.update_restaurant(''00000000-0000-4000-8000-000000000201'', ''{"brand_id": "00000000-0000-4000-8000-000000000102"}'', ''Prueba'')'),
  'ERROR 22023', 'mover un local de marca no es una edición: se rechaza el campo');

-- ---------------------------------------------------------------------------
-- Adicional A4: revocar un rol corta el acceso en la siguiente consulta.
-- También una cuenta bloqueada o con bloqueo temporal deja de operar.
-- ---------------------------------------------------------------------------
update core.user_role_assignments set deleted_at = now() where user_id = pg_temp.u(409);
select is(pg_temp.q(pg_temp.u(409), 'select count(*)::text from org.restaurants'), '0', 'A4. al cocinero le quitaron el rol: en la consulta siguiente ya no ve nada');
update core.user_profiles set status = 'deactivated', deactivated_at = now() where id = pg_temp.u(408);
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from org.restaurants'), '0', 'una cuenta bloqueada no ve nada');
update core.user_profiles set locked_until = now() + interval '10 minutes' where id = pg_temp.u(410);
select is(pg_temp.q(pg_temp.u(410), 'select count(*)::text from org.restaurants'), '0', 'una cuenta con bloqueo temporal no ve nada');

-- ---------------------------------------------------------------------------
-- Prueba obligatoria 10: una cuenta técnica no supera sus permisos (no tiene ninguno hasta la Fase 5)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(499), 'select (select count(*) from org.restaurants) + (select count(*) from core.user_profiles) + (select count(*) from core.roles)')::text,
  '0', '10. la cuenta técnica no ve locales, personas ni el catálogo');
select is(pg_temp.call(pg_temp.u(499), 'org.update_area(''00000000-0000-4000-8000-000000000311'', ''{"name": "Bot"}'', ''Prueba'')'),
  'ERROR 42501', '10. la cuenta técnica no cambia la estructura');
select is(pg_temp.q(pg_temp.u(499), 'select count(*)::text from core.service_accounts'), 'ERROR 42501', '10. la cuenta técnica no lee core.service_accounts');

-- ---------------------------------------------------------------------------
-- Adicional A3: ni el superadministrador altera el historial desde la app
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(401), 'delete from audit.audit_events returning ''borrado'''), 'ERROR 42501', 'A3. el superadmin no borra el historial desde la app');
select is(pg_temp.q(pg_temp.u(401), 'update audit.audit_events set reason = ''x'' returning ''cambiado'''), 'ERROR 42501', 'A3. el superadmin no modifica el historial desde la app');
select is(pg_temp.q(pg_temp.u(401), 'select count(*)::text from audit.audit_events'), 'ERROR 42501', 'A3. el historial no se lee directo: se va a leer por una función con alcance');

-- ---------------------------------------------------------------------------
-- Ver personas (users.view por alcance)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(404), 'select string_agg(right(id::text, 3), '','' order by id) from core.user_profiles'),
  '404,406,411,501,502,503,504,505,506,507,508', 'el gerente ve a las personas con roles en su local (y a sí mismo)');
select is(pg_temp.q(pg_temp.u(406), 'select string_agg(right(id::text, 3), '','' order by id) from core.user_profiles'),
  '406', 'el jefe de cocina solo se ve a sí mismo');
select is(pg_temp.q(pg_temp.u(406), 'select count(*)::text from core.roles'), '10', 'cualquier persona activa ve el catálogo de roles');

-- ---------------------------------------------------------------------------
-- P13: un registro borrado no se edita; primero se restaura
-- ---------------------------------------------------------------------------
update org.areas set deleted_at = now() where id = pg_temp.u(312);
select throws_ok(format($$update org.areas set name = 'Salón 2' where id = %L$$, pg_temp.u(312)),
  '42501', null, 'P13. un área borrada no se edita');
select throws_ok(format($$update org.areas set name = 'Salón 2', deleted_at = null where id = %L$$, pg_temp.u(312)),
  '42501', null, 'P13. restaurar y cambiar a la vez se rechaza: son dos pasos');
update org.areas set deleted_at = null where id = pg_temp.u(312);
update org.areas set name = 'Salón 2' where id = pg_temp.u(312);
select is(
  (select array_agg(action::text order by sequence_number) from audit.audit_events where record_id = pg_temp.u(312) and action <> 'insert'),
  array['soft_delete', 'restore', 'update'],
  'P13. restaurar y después editar quedan como dos pasos en el historial'
);

-- ---------------------------------------------------------------------------
-- P10: datos opcionales del local
-- ---------------------------------------------------------------------------
select throws_ok(format($$update org.restaurants set tax_id = '20-12345678-9' where id = %L$$, pg_temp.u(204)),
  '23514', null, 'P10. el CUIT tiene que ser de 11 dígitos sin guiones');
select throws_ok(format($$update org.restaurants set time_zone = 'Marte/Base' where id = %L$$, pg_temp.u(204)),
  '23503', null, 'P10. la zona horaria tiene que existir (tabla de referencia)');
select is(pg_temp.q(pg_temp.u(403), 'select code from org.restaurants where name = ''Demo Pastas Sur'''), 'DP-SUR',
  'P10. el código del local queda en mayúsculas');
select ok((select time_zone = 'America/Argentina/Buenos_Aires' from org.restaurants where name = 'Demo Pastas Sur'),
  'P10. sin zona horaria, el local queda en Buenos Aires');
select throws_ok(
  format($$insert into org.restaurants (group_id, brand_id, name, predecessor_id) values (%L, %L, 'Sucesor 1', %L), (%L, %L, 'Sucesor 2', %L)$$,
         pg_temp.u(1), pg_temp.u(102), pg_temp.u(204), pg_temp.u(1), pg_temp.u(102), pg_temp.u(204)),
  '23505', null, 'un local tiene a lo sumo un sucesor (ADR-0007)');

-- ---------------------------------------------------------------------------
-- Lectura de asignaciones y membresías (cada rol ve lo suyo o su alcance)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(406), 'select count(*)::text from core.user_role_assignments'), '1', 'el jefe de cocina ve solo su asignación');
select is(pg_temp.q(pg_temp.u(404), 'select string_agg(right(user_id::text, 3), '','' order by user_id) from core.user_role_assignments where deleted_at is null'),
  '404,406,411,501,502,503,504,505,506,507,508', 'el gerente ve las asignaciones vigentes de su local');
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from core.user_role_assignments', 'aal1'), '0', 'el gerente sin doble verificación no ve asignaciones');
select is(pg_temp.q(pg_temp.u(406), 'select count(*)::text from core.user_memberships'), '2', 'el jefe de cocina ve solo sus membresías (el grupo y su local)');

-- Una asignación vencida no hace visible a la persona.
insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id, valid_from, valid_until)
select pg_temp.u(407), r.id, 'restaurant', pg_temp.u(1), pg_temp.u(101), pg_temp.u(201), now() - interval '10 days', now() - interval '1 day'
  from core.roles r where r.code = 'cook';
select is(pg_temp.q(pg_temp.u(404), 'select count(*)::text from core.user_profiles where id = ''00000000-0000-4000-8000-000000000407'''),
  '0', 'una asignación vencida en el local no hace visible a esa persona');

-- has_permission_for_scope no se deja engañar con ids mezclados.
select is(pg_temp.q(pg_temp.u(403), 'select core.has_permission_for_scope(''org.manage'', ''restaurant'', ''00000000-0000-4000-8000-000000000001'', ''00000000-0000-4000-8000-000000000101'', ''00000000-0000-4000-8000-000000000203'')::text'),
  'false', 'un local de otra marca no queda cubierto pasando la marca propia');

-- ---------------------------------------------------------------------------
-- Escrituras que sí se pueden (con el permiso en el nivel correcto)
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(401), 'select (org.create_brand(''00000000-0000-4000-8000-000000000001'', ''Demo Sushi'', ''SUSHI'', ''Marca nueva'') is not null)::text'),
  'true', 'el superadmin crea una marca');
select is(pg_temp.call(pg_temp.u(401), 'org.update_brand(''00000000-0000-4000-8000-000000000103'', ''{"status": "inactive"}'', ''Cierre de la marca'')'),
  'ok', 'el superadmin cierra una marca (estado, nivel grupo)');
select is(pg_temp.q(pg_temp.u(404), 'select (org.create_area(''00000000-0000-4000-8000-000000000201'', ''Pastelería'', ''Área nueva'') is not null)::text'),
  'true', 'el gerente crea un área en su local');
select is(pg_temp.call(pg_temp.u(403), 'org.set_deleted(''areas'', ''00000000-0000-4000-8000-000000000323'', true, ''Error de carga'')')
          || '/' || pg_temp.call(pg_temp.u(403), 'org.set_deleted(''areas'', ''00000000-0000-4000-8000-000000000323'', false, ''Se borró por error'')'),
  'ok/ok', 'el director borra y restaura un área de un local de su marca');
select is(pg_temp.call(pg_temp.u(403), 'org.set_deleted(''areas'', ''00000000-0000-4000-8000-000000000323'', null, ''x'')'),
  'ERROR 22023', 'set_deleted exige decir si se borra o se restaura');
select throws_ok(format($$update org.areas set name = 'Otra', deleted_at = now() where id = %L$$, pg_temp.u(322)),
  '42501', null, 'P13. editar y borrar a la vez se rechaza: son dos pasos');

select * from finish();
rollback;
