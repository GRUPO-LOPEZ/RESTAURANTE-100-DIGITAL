-- Fase 2 · Etapa 2.5: las fichas por receta (ADR-0034). Quién saca cada ficha, y de qué recetas. Los ids se buscan afuera
-- de la sesión, para que la prueba pueda fallar.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(32);

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
create function pg_temp.list(p_user int, p_rest int default 201) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select coalesce(string_agg(x, '','' order by x), ''nada'') from costing.report_list(%L) x', pg_temp.u(p_rest)))
$$;
create function pg_temp.recipes(p_user int, p_sql text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(p_sql, pg_temp.u(201)))
$$;
create function pg_temp.rid(p_code text) returns uuid language sql as $$
  select id from recipes.recipes where code = p_code
$$;
create function pg_temp.without(p_role text, p_permission text) returns void language plpgsql as $$
begin
  perform core.set_change_context('Prueba: rol ajustado', 'maintenance');
  update core.role_permissions set deleted_at = now()
   where role_id = (select id from core.roles where code = p_role)
     and permission_id = (select id from core.permissions where code = p_permission);
end
$$;

-- Quién saca cada ficha. 404 Gerente, 405 Chef, 406 Jefe de Cocina, 407 Controller, 408 Compras, 409 Cocinera, 410 Auditor.
select is(pg_temp.list(407), 'cost_card,cost_changes,ingredients,quality,recipe_card,usage,yields', 'el Controller saca las dos fichas');
select is(pg_temp.list(405), 'cost_card,cost_changes,quality,recipe_card,usage,yields', 'la Chef también, sin el reporte de precios');
select is(pg_temp.list(410), 'cost_card,cost_changes,ingredients,quality,recipe_card,usage,yields', 'y el Auditor');
select is(pg_temp.list(406), 'nada', 'el Jefe de Cocina no saca reportes');
select is(pg_temp.list(408), 'nada', 'Compras no');
select is(pg_temp.list(409), 'nada', 'la Cocinera no');

-- De qué recetas: las vigentes del local que ve.
select ok((select id from recipes.recipes where code = 'DEMO-PAS-03') is not null, 'los Ravioles existen');
select is(pg_temp.recipes(407, format($$select count(*)::text from costing.report_recipes(%%L) where recipe_id = %L$$, (select id from recipes.recipes where code = 'DEMO-PAS-03'))),
  '1', 'el Controller elige los Ravioles');
select is(pg_temp.recipes(407, format($$select count(*)::text from costing.report_recipes(%%L) where recipe_id = %L$$, (select id from recipes.recipes where code = 'DEMO-PAS-06'))),
  '0', 'pero no un borrador, que no tiene ficha vigente');
select is(pg_temp.recipes(407, format($$select count(*)::text from costing.report_recipes(%%L) where recipe_id = %L$$, (select id from recipes.recipes where code = 'DEMO-PAR-02'))),
  '0', 'ni una receta de otra marca');
select is(pg_temp.recipes(407, $$select string_agg(name, ',') from costing.report_recipes(%L, 'raviol')$$), 'Ravioles de ricota', 'se busca por nombre');
select ok((select case when a ~ '^[0-9]+$' then a::int > 1 and a = b else false end
              from (select pg_temp.recipes(407, $$select max(total_rows)::text from costing.report_recipes(%L, null, 1)$$) a,
                           pg_temp.recipes(407, $$select count(*)::text from costing.report_recipes(%L, null, 100)$$) b) x),
  'trae el total aunque la página sea de una');
select ok(pg_temp.recipes(408, $$select count(*)::text from costing.report_recipes(%L)$$) like 'ERROR%No tenés permiso%', 'Compras no lista recetas');
select ok(pg_temp.q(pg_temp.u(404), format('select count(*)::text from costing.report_recipes(%L)', pg_temp.u(203))) like 'ERROR%No tenés permiso%',
  'el Gerente no lista recetas de otro local');

-- La búsqueda: sin acentos, y también por código.
select ok(pg_temp.recipes(407, $$select string_agg(name, ',') from costing.report_recipes(%L, 'noquis')$$) like '%Ñoquis de papa%', 'se busca sin acentos');
select is(pg_temp.recipes(407, $$select string_agg(name, ',') from costing.report_recipes(%L, 'demo-pas-03')$$), 'Ravioles de ricota', 'y por código');
select is(pg_temp.recipes(407, $$select count(*)::text from costing.report_recipes(%L, repeat('x', 5000))$$), '0', 'una búsqueda larguísima no rompe nada');
-- En el local Norte, la variante del local y no la maestra.
select is(pg_temp.q(pg_temp.u(407), format($$select string_agg(code, ',' order by code) from costing.report_recipes(%L, 'oquis')$$, pg_temp.u(202))),
  'DEMO-LOC-02', 'en el Norte sale la variante del local');
select is(pg_temp.recipes(405, format($$select count(*)::text from costing.report_recipes(%%L) where recipe_id = %L$$, pg_temp.rid('DEMO-PAS-03'))),
  '1', 'la Chef también elige los Ravioles');

-- Una ficha es de una receta del local. El Controller ve la receta de otra marca, pero no la saca a nombre de este local.
select ok(pg_temp.q(pg_temp.u(407), format($$select (recipes.kitchen_card(%L) is not null)::text$$, pg_temp.rid('DEMO-PAR-02'))) = 'true',
  'el Controller ve la receta de otra marca');
select ok(pg_temp.recipes(407, format($$select costing.require_report_recipe('recipe_card', %%L, %L)::text$$, pg_temp.rid('DEMO-PAR-02'))) like 'ERROR%No tenés permiso%',
  'pero no saca su ficha en este local');
select is(pg_temp.recipes(407, format($$select costing.require_report_recipe('recipe_card', %%L, %L)::text$$, pg_temp.rid('DEMO-PAS-03'))), '',
  'la de los Ravioles, sí');
select ok(pg_temp.recipes(407, format($$select costing.require_report_recipe('cost_card', %%L, %L)::text$$, pg_temp.rid('DEMO-PAS-06'))) like 'ERROR%No tenés permiso%',
  'ni la de un borrador');

-- El registro dice de qué receta es la ficha.
select is(pg_temp.recipes(407, format($$select costing.log_report('recipe_card', %%L, 'pdf', 3, null, null, %L)::text$$, pg_temp.rid('DEMO-PAS-03'))), '',
  'una ficha se registra');
select is((select string_agg(detail ->> 'recipe_code', ',') from audit.authentication_security_events
            where event_type = 'report_exported' and detail ->> 'report' = 'recipe_card'),
  'DEMO-PAS-03', 'con el código de la receta');
select ok(pg_temp.recipes(407, $$select costing.log_report('recipe_card', %L, 'pdf')::text$$) like 'ERROR%No tenés permiso%', 'una ficha sin receta no se registra');
select ok(pg_temp.recipes(407, format($$select costing.log_report('cost_card', %%L, 'xlsx', 1, null, null, %L)::text$$, pg_temp.rid('DEMO-PAR-02'))) like 'ERROR%No tenés permiso%',
  'ni la de una receta de otra marca');
select ok(pg_temp.recipes(407, format($$select costing.log_report('ingredients', %%L, 'csv', 1, null, null, %L)::text$$, pg_temp.rid('DEMO-PAS-03'))) like 'ERROR%no es de una receta%',
  'un reporte de lista no lleva receta');

-- Sin ver costos sale la ficha técnica y no la de costeo.
select pg_temp.without('controller', 'recipes.view_costs');
select ok(pg_temp.list(407) like '%recipe_card%' and pg_temp.list(407) not like '%cost_card%', 'sin ver costos, solo la ficha técnica');
select ok(pg_temp.recipes(407, format($$select costing.require_report_recipe('cost_card', %%L, %L)::text$$, pg_temp.rid('DEMO-PAS-03'))) like 'ERROR%No tenés permiso%',
  'y la base no deja armar la de costeo');
-- Sin ver recetas, ninguna ficha.
select pg_temp.without('controller', 'recipes.view');
select ok(pg_temp.list(407) not like '%recipe_card%' and pg_temp.list(407) not like '%cost_card%', 'sin ver recetas, ninguna ficha');
select ok(pg_temp.recipes(407, $$select count(*)::text from costing.report_recipes(%L)$$) like 'ERROR%No tenés permiso%', 'ni la lista de recetas');

select * from finish();
rollback;
