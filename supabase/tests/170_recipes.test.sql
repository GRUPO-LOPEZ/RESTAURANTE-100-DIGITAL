-- Fase 2 · Etapa 2.2 A: recetas (ADR-0023). Casos del documento de Soy: 6 (versión nueva, la vigente
-- sigue), 11 (un local no edita la receta de otro, y queda registrado), 22 (camino crítico) y 24 (la
-- cocina no ve ningún valor económico). Aprobar = publicar, y quien pidió la revisión no la aprueba.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(102);

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
create function pg_temp.msg(p_user uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  set local role authenticated;
  begin
    execute p_sql;
    v := 'sin error';
  exception when others then
    v := sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
-- Recetas y versiones del seed por código; ids guardados durante la prueba por nombre.
create function pg_temp.rec(p_code text) returns uuid language sql as $$
  select id from recipes.recipes where code = p_code
$$;
create function pg_temp.ver(p_code text, p_number int) returns uuid language sql as $$
  select v.id from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id
   where r.code = p_code and v.version_number = p_number
$$;
create temporary table ids (k text primary key, id uuid);
grant select on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant execute on function pg_temp.u(int), pg_temp.rec(text), pg_temp.ver(text, int), pg_temp.id(text) to authenticated;
-- El resultado de una función que devuelve {"result": ...}.
create function pg_temp.res(p_user uuid, p_call text) returns text language sql as $$
  select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call))
$$;
create function pg_temp.decide(p_user uuid, p_request uuid, p_decision text default 'approved') returns text language sql as $$
  select pg_temp.q(p_user, format('select workflow.decide_approval(%L, %L, %L) ->> ''result''', p_request, p_decision,
                                  case when p_decision = 'rejected' then 'Falta el paso de enfriado' end))
$$;
create function pg_temp.status(p_version uuid) returns text language sql as $$
  select status::text from recipes.recipe_versions where id = p_version
$$;

-- Personas del seed: Chef de Demo Pastas 405, Chef del grupo 413, Dirección 402, Jefe de Cocina 406
-- (Demo Pastas Centro, 201), Gerente 404 (201), Cocinera 409 (201), Controller 407, Compras 408.

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_tables where schemaname = 'recipes'), 9, 'el esquema recipes tiene 9 tablas (con las fotos y las cantidades congeladas)');
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'recipes' and c.relkind = 'r' and not c.relrowsecurity),
  'RLS activado en todas las tablas de recipes');
select ok(not exists (select 1 from information_schema.columns
                       where table_schema = 'recipes'
                         and column_name ~* '(cost|price|precio|costo|amount|importe|currency|moneda|margin|margen)'),
  'caso 24: ninguna tabla de recipes tiene columnas de costo o precio');
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'recipes' and c.relkind = 'r'
                         and has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate')),
  'nadie escribe directo en las tablas de recipes: solo por funciones');
select ok(not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = 'recipes' and c.relkind = 'r'
                         and (select count(*) from pg_trigger g
                               where g.tgrelid = c.oid
                                 and g.tgname in ('log_change', 'set_control_columns', 'reject_truncate')) <> 3),
  'todas las tablas de recipes tienen auditoría, columnas de control y rechazo de truncate');

-- ---------------------------------------------------------------------------
-- Quién ve qué
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_versions where recipe_id = pg_temp.rec('DEMO-SAL-01')$$),
  '1', 'la Cocinera ve la versión vigente de una maestra asignada a su local');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipes where code = 'DEMO-PAR-01'$$),
  '0', 'no ve una receta de otra marca que no está asignada a su local');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_versions where recipe_id = pg_temp.rec('DEMO-PAS-06')$$),
  '0', 'no ve un borrador');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipes where code = 'DEMO-LOC-01'$$),
  '1', 've la receta propia de su local');
select is(pg_temp.q(pg_temp.u(405), $$select count(*)::text from recipes.recipe_versions where recipe_id = pg_temp.rec('DEMO-PAS-06')$$),
  '1', 'la Chef de la marca ve el borrador de una receta de la marca');
select is(pg_temp.q(pg_temp.u(406), $$select count(*)::text from recipes.recipe_versions where recipe_id = pg_temp.rec('DEMO-PAS-06')$$),
  '0', 'el Jefe de Cocina de un local no ve los borradores de las recetas de marca');
select is(pg_temp.q(pg_temp.u(407), 'select count(*)::text from recipes.recipes'), '20',
  'el Controller ve las 20 recetas vigentes (el risotto solo tiene un borrador; suma la variante de Norte)');
select is(pg_temp.q(pg_temp.u(405), $$select count(*)::text from recipes.recipes where code = 'DEMO-SAL-01'$$),
  '1', 'la Chef de marca ve las maestras del grupo (para asignarlas)');

-- ---------------------------------------------------------------------------
-- Vista de cocina y tiempos (casos 22 y 24)
-- ---------------------------------------------------------------------------
select is((select total_minutes from recipes.critical_path(pg_temp.ver('DEMO-SAL-02', 1))), 90,
  'caso 22: camino crítico 20 + máx(60, 30) + 10 = 90 minutos');
select is((select active_minutes from recipes.critical_path(pg_temp.ver('DEMO-SAL-02', 1))), 75,
  'los minutos activos sí se suman');
select is(pg_temp.q(pg_temp.u(409), $$select (recipes.kitchen_card(pg_temp.rec('DEMO-SAL-02')) ->> 'total_minutes')$$), '90',
  'la Cocinera abre la ficha de cocina con el tiempo total');
select is(pg_temp.q(pg_temp.u(409), $$select jsonb_array_length(recipes.kitchen_card(pg_temp.rec('DEMO-SAL-02')) -> 'components')::text$$),
  '8', 'con los componentes (nombre y cantidad), aunque no ve el catálogo');
select ok(pg_temp.q(pg_temp.u(409), $$select recipes.kitchen_card(pg_temp.rec('DEMO-SAL-02'))::text$$)
          !~* '(cost|price|precio|costo|currency|margin)',
  'caso 24: la ficha de cocina no trae ningún valor económico');
select is(pg_temp.q(pg_temp.u(409), format('select coalesce(recipes.kitchen_card(%L)::text, ''nada'')', pg_temp.rec('DEMO-PAR-01'))), 'nada',
  'una receta que no le corresponde no le devuelve nada');

-- ---------------------------------------------------------------------------
-- Alérgenos
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$select string_agg(code || '=' || status, ', ' order by code)
                                        from recipes.version_allergens(pg_temp.ver('DEMO-PAS-02', 1))
                                       where code in ('DEMO-GLUTEN', 'DEMO-HUEVO', 'DEMO-LECHE', 'DEMO-PESCADO')$$),
  'DEMO-GLUTEN=contains, DEMO-HUEVO=may_contain, DEMO-LECHE=contains, DEMO-PESCADO=not_verified',
  'alérgenos del spaghetti (para la Cocinera): contiene gluten y leche, trazas de huevo; pescado sin dato = no verificado');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.version_allergens(pg_temp.ver('DEMO-PAR-01', 1))$$), '0',
  'los alérgenos de una receta que no ve no se los devuelve');

-- ---------------------------------------------------------------------------
-- Crear y editar
-- ---------------------------------------------------------------------------
insert into ids values ('nueva', (pg_temp.q(pg_temp.u(406), $$select recipes.create_recipe(null, null, pg_temp.u(201),
  'Fainá de prueba', 'dish', pg_temp.u(1062), 'Receta nueva del local') ->> 'id'$$))::uuid);
select ok(pg_temp.id('nueva') is not null, 'el Jefe de Cocina crea una receta de su local');
select is((select scope_type::text || '/' || code from recipes.recipes where id = pg_temp.id('nueva')), 'restaurant/PLA-PAS-0001',
  'queda como receta de local, con el código que arma la base (ADR-0041)');
select is((select count(*)::int from recipes.recipe_assignments where recipe_id = pg_temp.id('nueva') and restaurant_id = pg_temp.u(201)),
  1, 'y asignada a su local');
insert into ids values ('nueva_v1', (select id from recipes.recipe_versions where recipe_id = pg_temp.id('nueva')));
select is(pg_temp.status(pg_temp.id('nueva_v1')), 'draft', 'su versión 1 nace en borrador');
select is(pg_temp.res(pg_temp.u(406), $$recipes.create_recipe(null, null, pg_temp.u(203), 'Otra', 'dish', pg_temp.u(1062), 'Prueba')$$),
  'denied', 'no crea recetas en otro local');
select is(pg_temp.res(pg_temp.u(409), $$recipes.create_recipe(null, null, pg_temp.u(201), 'Otra', 'dish', pg_temp.u(1062), 'Prueba')$$),
  'denied', 'la Cocinera no crea recetas');
select throws_ok($$insert into recipes.recipes (group_id, scope_type, code, name, recipe_type, category_id)
                   values (pg_temp.u(1), 'group', 'DEMO-PAS-01', 'Repetida', 'dish', pg_temp.u(1062))$$,
  '23505', null, 'un código repetido lo sigue rechazando la base (el código ya no se elige: ADR-0041)');

select is(pg_temp.res(pg_temp.u(406), format($$recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000827", "quantity": 250, "unit": "g"},
    {"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 0.2, "unit": "kg", "basis": "clean"}
  ]', 'Componentes')$$, pg_temp.id('nueva_v1'))), 'applied', 'carga los componentes del borrador');
select is((select count(*)::int from recipes.recipe_components where recipe_version_id = pg_temp.id('nueva_v1') and deleted_at is null),
  2, 'quedan dos líneas');
select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000826", "quantity": 100, "unit": "g"}]', 'Huevo en gramos')$$,
    pg_temp.id('nueva_v1'))),
  'Línea 1 (Huevo): no se puede pasar de g a la unidad de la materia prima. Cargá la conversión en su ficha o usá otra unidad.',
  'una unidad que no se puede convertir se rechaza: el costo no se podría calcular');
select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000827", "quantity": 0, "unit": "g"}]', 'Cero')$$, pg_temp.id('nueva_v1'))),
  'Línea 1 (Harina 000): la cantidad tiene que ser mayor que cero.', 'cantidad cero, en español');
select is((select count(*)::int from recipes.recipe_components where recipe_version_id = pg_temp.id('nueva_v1') and deleted_at is null),
  2, 'un guardado rechazado no toca las líneas que había');

select is(pg_temp.res(pg_temp.u(406), format($$recipes.set_steps(%L, '[
    {"instructions": "Preparar", "active_minutes": 20},
    {"kind": "cooking", "instructions": "Cocinar", "active_minutes": 15, "passive_minutes": 45, "depends_on": [1]},
    {"instructions": "Otra preparación", "active_minutes": 30, "depends_on": [1]},
    {"kind": "plating", "instructions": "Terminar", "active_minutes": 10, "depends_on": [2, 3]}
  ]', 'Pasos')$$, pg_temp.id('nueva_v1'))), 'applied', 'carga los pasos con sus dependencias');
select is((select total_minutes from recipes.critical_path(pg_temp.id('nueva_v1'))), 90, 'y el camino crítico da 90');
select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.set_steps(%L, '[
    {"instructions": "A", "depends_on": [2]}, {"instructions": "B", "depends_on": [1]}]', 'Ciclo')$$, pg_temp.id('nueva_v1'))),
  'Los pasos no pueden esperarse en círculo.', 'los pasos no se esperan en círculo');
select is((select count(*)::int from recipes.recipe_steps where recipe_version_id = pg_temp.id('nueva_v1') and deleted_at is null),
  4, 'y los pasos que había siguen');

select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.request_review(%L, 'Lista')$$, pg_temp.id('nueva_v1'))),
  'Para pedir la revisión, la receta necesita al menos un componente, un paso y su rendimiento.',
  'sin rendimiento no se pide revisión');
select is(pg_temp.res(pg_temp.u(406), format($$recipes.save_draft(%L, '{"yield_quantity": "1", "yield_unit": "kg", "portions": 4}', 'Rendimiento')$$,
    pg_temp.id('nueva_v1'))), 'applied', 'guarda el rendimiento');

-- ---------------------------------------------------------------------------
-- Caso 11: un local no edita la receta de otro, y queda registrado
-- ---------------------------------------------------------------------------
insert into ids values ('norte', (pg_temp.q(pg_temp.u(405), $$select recipes.create_recipe(null, null, pg_temp.u(202),
  'Receta de Norte', 'dish', pg_temp.u(1062), 'Receta del otro local') ->> 'version_id'$$))::uuid);
select is(pg_temp.res(pg_temp.u(406), format($$recipes.set_components(%L, '[]', 'Intento')$$, pg_temp.id('norte'))), 'denied',
  'caso 11: el Jefe de Cocina de Centro no edita una receta de Norte');
set local role audit_owner;
create temporary table denied_edit as
  select count(*)::int as n from audit.authentication_security_events
   where event_type = 'operation_denied' and operation = 'recipes.set_components' and actor_id = '00000000-0000-4000-8000-000000000406';
reset role;
select is((select n from denied_edit), 1, 'caso 11: el intento queda en el registro de seguridad');

-- ---------------------------------------------------------------------------
-- Revisión y publicación: aprobar = publicar; quien pidió no aprueba
-- ---------------------------------------------------------------------------
select is(pg_temp.res(pg_temp.u(406), format($$recipes.request_review(%L, 'Lista para revisar')$$, pg_temp.id('nueva_v1'))),
  'pending_approval', 'el Jefe de Cocina pide la revisión');
select is(pg_temp.status(pg_temp.id('nueva_v1')), 'in_review', 'la versión queda en revisión');
insert into ids values ('req1', (select approval_request_id from recipes.recipe_versions where id = pg_temp.id('nueva_v1')));
select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.set_components(%L, '[]', 'Cambio')$$, pg_temp.id('nueva_v1'))),
  'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.', 'en revisión no se edita');
select throws_ok(format($$update recipes.recipe_components set quantity = 1 where recipe_version_id = %L$$, pg_temp.id('nueva_v1')),
  '42501', 'Solo se cambia un borrador: para corregir una receta, creá una versión nueva.',
  'ni siquiera directo en la tabla');
select is(pg_temp.decide(pg_temp.u(406), pg_temp.id('req1')), 'denied', 'quien pidió la revisión no la aprueba');
select is(pg_temp.decide(pg_temp.u(404), pg_temp.id('req1')), 'denied', 'el Gerente tampoco: no tiene recipes.publish');
select is(pg_temp.decide(pg_temp.u(405), pg_temp.id('req1')), 'approved', 'la Chef de la marca la aprueba');
select is(pg_temp.status(pg_temp.id('nueva_v1')), 'published', 'y queda publicada en el acto');
select is((select approved_by from recipes.recipe_versions where id = pg_temp.id('nueva_v1')), pg_temp.u(405),
  'con quién la aprobó');
select ok(exists (select 1 from audit.audit_events where table_name = 'recipe_versions' and record_id = pg_temp.id('nueva_v1')
                    and new_values ->> 'status' = 'in_review' and reason = 'Lista para revisar'),
  'el pedido de revisión queda en la auditoría con su motivo');

-- ---------------------------------------------------------------------------
-- Caso 6: versión nueva; la vigente sigue hasta que se publique la nueva
-- ---------------------------------------------------------------------------
select is(pg_temp.res(pg_temp.u(413), $$recipes.new_version(pg_temp.rec('DEMO-SAL-01'), 'Menos sal')$$), 'applied',
  'el Chef del grupo crea la versión 2 de una maestra');
select is(pg_temp.status(pg_temp.ver('DEMO-SAL-01', 2)) || '/' || pg_temp.status(pg_temp.ver('DEMO-SAL-01', 1)), 'draft/published',
  'caso 6: la v2 nace en borrador y la v1 sigue vigente');
select is((select count(*)::int from recipes.recipe_components where recipe_version_id = pg_temp.ver('DEMO-SAL-01', 2) and deleted_at is null)
          || '/' || (select count(*) from recipes.recipe_step_dependencies d join recipes.recipe_steps s on s.id = d.step_id
                      where s.recipe_version_id = pg_temp.ver('DEMO-SAL-01', 2) and d.deleted_at is null),
  '7/2', 'copia las líneas y las dependencias de los pasos');
select is(pg_temp.q(pg_temp.u(409), $$select recipes.kitchen_card(pg_temp.rec('DEMO-SAL-01')) ->> 'version_number'$$), '1',
  'la cocina sigue viendo la v1');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.new_version(pg_temp.rec('DEMO-SAL-01'), 'Otra')$$),
  'Ya hay una versión en borrador o en revisión: seguí con esa.', 'una sola versión abierta por receta');
select is(pg_temp.res(pg_temp.u(413), format($$recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000835", "quantity": 2000, "unit": "g"},
    {"ingredient_id": "00000000-0000-4000-8000-000000000802", "quantity": 300, "unit": "g"},
    {"ingredient_id": "00000000-0000-4000-8000-000000000837", "quantity": 10, "unit": "g"}]', 'Menos sal')$$,
    pg_temp.ver('DEMO-SAL-01', 2))), 'applied', 'cambia las líneas de la v2');
select is(pg_temp.q(pg_temp.u(413), $$select string_agg(change || ' ' || ingredient, ', ' order by ingredient)
                                        from recipes.version_diff(pg_temp.ver('DEMO-SAL-01', 2))$$),
  'removed Aceite de oliva, removed Ajo, removed Albahaca, removed Azúcar, changed Sal fina',
  'las diferencias contra la v1, línea por línea');
select is(pg_temp.res(pg_temp.u(413), format($$recipes.request_review(%L, 'Menos sal')$$, pg_temp.ver('DEMO-SAL-01', 2))),
  'pending_approval', 'pide la revisión');
insert into ids values ('req2', (select approval_request_id from recipes.recipe_versions where id = pg_temp.ver('DEMO-SAL-01', 2)));
select is(pg_temp.decide(pg_temp.u(405), pg_temp.id('req2')), 'denied',
  'la Chef de una marca no aprueba una maestra del grupo (le falta alcance)');
select is(pg_temp.decide(pg_temp.u(402), pg_temp.id('req2')), 'approved', 'Dirección la aprueba');
select is(pg_temp.status(pg_temp.ver('DEMO-SAL-01', 1)) || '/' || pg_temp.status(pg_temp.ver('DEMO-SAL-01', 2)), 'archived/published',
  'la v1 queda archivada y la v2 vigente');
select is(pg_temp.q(pg_temp.u(409), $$select recipes.kitchen_card(pg_temp.rec('DEMO-SAL-01')) ->> 'version_number'$$), '2',
  'la cocina ya ve la v2');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.version_diff(pg_temp.ver('DEMO-SAL-01', 2))$$), '0',
  'la Cocinera no ve las diferencias: la versión anterior es historia');
select ok((select proposed_changes::text from workflow.approval_requests where id = pg_temp.id('req2')) !~ '(Ajo|Albahaca|Sal fina)',
  'la solicitud lleva un resumen, no la fórmula (la ve cualquiera con approvals.view)');
select is((select proposed_changes -> 'line_changes' from workflow.approval_requests where id = pg_temp.id('req2')),
  '{"added": 0, "changed": 1, "removed": 4}'::jsonb, 'cuántas líneas se agregan, quitan o cambian');

-- ---------------------------------------------------------------------------
-- Rechazo y retiro: vuelve a borrador para corregir
-- ---------------------------------------------------------------------------
select is(pg_temp.res(pg_temp.u(405), $$recipes.new_version(pg_temp.rec('DEMO-PAS-02'), 'Más queso')$$), 'applied', 'otra versión nueva');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.request_review(%L, 'Más queso')$$, pg_temp.ver('DEMO-PAS-02', 2))),
  'pending_approval', 'la Chef pide la revisión');
select is(pg_temp.res(pg_temp.u(403), format($$recipes.withdraw_review(%L, 'La retiro yo')$$, pg_temp.ver('DEMO-PAS-02', 2))),
  'denied', 'solo quien la pidió la retira');
select is(pg_temp.decide(pg_temp.u(403), (select approval_request_id from recipes.recipe_versions where id = pg_temp.ver('DEMO-PAS-02', 2)),
                         'rejected'), 'rejected', 'la Directora de marca la rechaza');
select is(pg_temp.res(pg_temp.u(409), format($$recipes.save_draft(%L, '{}', 'Intento')$$, pg_temp.ver('DEMO-PAS-02', 2))),
  'denied', 'la Cocinera no edita el borrador rechazado');
select is(pg_temp.status(pg_temp.ver('DEMO-PAS-02', 2)), 'in_review', 'y su intento no cambia nada: ni siquiera el estado');
select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.save_draft(%L, '{}', 'Viejo', '2000-01-01 00:00:00+00')$$,
    pg_temp.ver('DEMO-PAS-02', 2))),
  'Otra persona cambió este borrador mientras lo editabas: recargá la página para ver sus cambios.',
  'si otra persona cambió el borrador desde que se leyó, no se pisa');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.save_draft(%L, '{"change_summary": "Con el paso de enfriado"}', 'Corrijo')$$,
    pg_temp.ver('DEMO-PAS-02', 2))), 'applied', 'la versión rechazada vuelve a borrador y se corrige');
select is(pg_temp.status(pg_temp.ver('DEMO-PAS-02', 2)), 'draft', 'queda en borrador');

-- ---------------------------------------------------------------------------
-- Asignaciones y archivo
-- ---------------------------------------------------------------------------
select is(pg_temp.res(pg_temp.u(405), $$recipes.set_assignment(pg_temp.rec('DEMO-PAS-01'), pg_temp.u(203), true, 'Prueba')$$),
  'denied', 'la Chef de Pastas no asigna en un local de Parrilla (no tiene permiso ahí)');
select is(pg_temp.res(pg_temp.u(405), $$recipes.set_assignment(pg_temp.rec('DEMO-GUA-02'), pg_temp.u(201), false, 'Ya no se usa')$$),
  'applied', 'deja de asignar una maestra a su local');
select is(pg_temp.q(pg_temp.u(409), format('select coalesce(recipes.kitchen_card(%L)::text, ''nada'')', pg_temp.rec('DEMO-GUA-02'))), 'nada',
  'y la cocina de ese local deja de verla');
select is(pg_temp.res(pg_temp.u(405), $$recipes.archive_recipe(pg_temp.rec('DEMO-PAS-03'), 'Sale de la carta')$$), 'applied',
  'la Chef archiva una receta');
select is(pg_temp.status(pg_temp.ver('DEMO-PAS-03', 1)) || '/' || (select is_active::text from recipes.recipes where code = 'DEMO-PAS-03'),
  'archived/false', 'su versión vigente queda archivada y la receta inactiva');
select is(pg_temp.msg(pg_temp.u(405), $$select recipes.set_assignment(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(202), true, 'Prueba')$$),
  'La receta está archivada.', 'una receta archivada no se asigna');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_assignments where recipe_id = pg_temp.rec('DEMO-SAL-01')$$),
  '1', 'la Cocinera ve la asignación de su local, no las de otros locales');

-- ---------------------------------------------------------------------------
-- Líneas, pasos y revalidación al pedir revisión
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_components where recipe_version_id = pg_temp.ver('DEMO-SAL-02', 1)$$),
  '8', 'la Cocinera ve las líneas de una receta vigente');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipe_steps where recipe_version_id = pg_temp.ver('DEMO-PAS-06', 1)$$),
  '0', 'y no los pasos de un borrador');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.recipes where code = 'DEMO-PAS-06'$$), '0',
  'ni el nombre de una receta que solo tiene un borrador');
select ok(exists (select 1 from audit.audit_events where table_name = 'recipe_components' and action = 'insert'
                    and scope_restaurant_id = pg_temp.u(201) and new_values ->> 'recipe_version_id' = pg_temp.id('nueva_v1')::text),
  'la auditoría de las líneas queda con el alcance de la receta (su local)');
update catalog.ingredients set is_active = false where id = '00000000-0000-4000-8000-000000000820';
select is(pg_temp.res(pg_temp.u(405), $$recipes.new_version(pg_temp.rec('DEMO-PAS-02'), 'Otra')$$), 'ERROR 23505',
  'no hay otra versión abierta posible mientras la v2 sigue en borrador');
select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.request_review(%L, 'Lista')$$, pg_temp.ver('DEMO-PAS-02', 2))),
  'Línea 4 (Queso rallado): la materia prima ya no está vigente. Corregila antes de pedir la revisión.',
  'las líneas copiadas se vuelven a validar al pedir la revisión');

-- Muchos pasos que esperan a todos los anteriores: el camino crítico sigue siendo inmediato.
select is(pg_temp.res(pg_temp.u(406), format('recipes.new_version(%L, %L)', pg_temp.id('nueva'), 'Muchos pasos')), 'applied',
  'versión nueva con muchos pasos');
select is(pg_temp.res(pg_temp.u(406), format('recipes.set_steps(%L, %L, %L)',
    (select id from recipes.recipe_versions where recipe_id = pg_temp.id('nueva') and status = 'draft'),
    (select jsonb_agg(jsonb_build_object('instructions', 'Paso ' || n, 'active_minutes', 1,
                                         'depends_on', (select coalesce(jsonb_agg(m), '[]') from generate_series(1, n - 1) m)))
       from generate_series(1, 100) n),
    'Cien pasos')), 'applied', 'guarda 100 pasos donde cada uno espera a todos los anteriores');
create temporary table cp_timing as
  select clock_timestamp() as t0, (select total_minutes from recipes.critical_path(
           (select id from recipes.recipe_versions where recipe_id = pg_temp.id('nueva') and status = 'draft'))) as total,
         clock_timestamp() as t1;
select is((select total from cp_timing), 100, 'el camino crítico de 100 pasos en fila da 100 minutos');
select ok((select t1 - t0 < interval '500 milliseconds' from cp_timing), 'y se calcula en menos de medio segundo');

-- ---------------------------------------------------------------------------
-- Categorías y responsable técnico
-- ---------------------------------------------------------------------------
-- El primer nivel son los rubros (ADR-0038): se crean con su clase (recipes.create_top_category, 250_rubros).
-- Con la función de siempre se crean subcategorías, que heredan la clase de su rubro.
select ok(pg_temp.q(pg_temp.u(413), $$select recipes.create_category(pg_temp.u(1), 'Panadería', 'Subcategoría nueva',
                                                                    '00000000-0000-4000-8000-000000001061')::text$$)
          ~ '^[0-9a-f-]{36}$', 'el Chef del grupo crea una subcategoría de recetas');
select is((select kind::text from recipes.recipe_categories where name = 'Panadería'), 'subrecipe',
  'que hereda la clase de su rubro');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_category(pg_temp.u(1), 'Sin clase', 'Prueba')$$),
  'Elegí la clase del rubro: sub-recetas o menú.', 'un rubro sin clase no se crea con la función de siempre');
select is(pg_temp.q(pg_temp.u(406), $$select recipes.create_category(pg_temp.u(1), 'Otra', 'Prueba')::text$$), 'ERROR 42501',
  'el Jefe de Cocina no');
select is(pg_temp.msg(pg_temp.u(406), format($$select recipes.update_recipe(%L, '{"technical_owner_id": "%s"}', 'Responsable')$$,
    pg_temp.id('nueva'), gen_random_uuid())),
  'Elegí como responsable técnico a una persona del grupo.', 'el responsable técnico tiene que ser del grupo');
select is(pg_temp.res(pg_temp.u(406), format($$recipes.update_recipe(%L, '{"technical_owner_id": "%s", "sector": "Caliente"}', 'Responsable')$$,
    pg_temp.id('nueva'), pg_temp.u(406))), 'applied', 'el Jefe de Cocina queda como responsable de su receta');

-- ---------------------------------------------------------------------------
-- Aprobaciones solo con funciones apply_* de los esquemas permitidos
-- ---------------------------------------------------------------------------
select throws_ok($$insert into workflow.approval_workflows (code, name, required_permission, min_approvers, apply_function)
                   values ('recipes.prueba', 'Prueba', 'recipes.publish', 1, 'recipes.kitchen_card(uuid)'::regprocedure)$$,
  '42501', null, 'una función de recipes que no es apply_* no puede aplicar aprobaciones');

-- ---------------------------------------------------------------------------
-- Conteo por categoría (pantalla de configuración): solo cuenta lo que la sesión ve
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(413), $$select recipes::text from recipes.category_usage()
                                       where category_id = '00000000-0000-4000-8000-000000001063'$$), '4',
  'el Chef del grupo cuenta las 4 recetas de Carnes (la bondiola braseada es una sub-receta: va en Cocciones base)');
select is(pg_temp.q(pg_temp.u(409), $$select count(*)::text from recipes.category_usage()
                                       where category_id = '00000000-0000-4000-8000-000000001063'$$), '0',
  'la Cocinera de Pastas no cuenta las recetas de Carnes, que son de otra marca y no ve');
select ok(not has_function_privilege('anon', 'recipes.category_usage()', 'execute'), 'anon no puede contar');

select * from finish();
rollback;
