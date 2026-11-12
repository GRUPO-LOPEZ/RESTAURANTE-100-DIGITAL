-- Códigos automáticos (ADR-0041, pedido de Soy del 2026-11-12): <TIPO>-<RUBRO>-<NNNN> para platos (PLA),
-- preparaciones (PRE) y materias primas (MPR); variantes con el código de la maestra y -V01. La base arma el código,
-- con bloqueo y sin reutilizar números, y el código no cambia nunca.
-- Personas del seed: Chef del grupo 413, Chef de Demo Pastas 405, Jefe de Cocina 406 (Demo Pastas Centro, 201),
-- Cocinera 409 (201), Compras 408 (administra el catálogo).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(51);

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
create function pg_temp.rec(p_code text) returns uuid language sql as $$
  select id from recipes.recipes where code = p_code
$$;
grant execute on function pg_temp.u(int), pg_temp.rec(text) to authenticated;
-- Crea un plato o una preparación del grupo como el Chef del grupo y devuelve el jsonb del resultado.
create function pg_temp.dish(p_category int, p_type text default 'dish', p_expected text default null,
                             p_user int default 413, p_restaurant int default null)
returns jsonb language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select recipes.create_recipe(%s, null, %s, %L, %L, pg_temp.u(%s), %L, %L)::text',
    case when p_restaurant is null then 'pg_temp.u(1)' else 'null' end,
    case when p_restaurant is null then 'null' else format('pg_temp.u(%s)', p_restaurant) end,
    'Receta de prueba ' || gen_random_uuid(), p_type, p_category, 'Prueba de códigos', p_expected))::jsonb
$$;
create function pg_temp.ing(p_category int, p_unit text, p_expected text default null, p_user int default 408)
returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select catalog.create_ingredient(pg_temp.u(1), %L, pg_temp.u(%s), %L, %L::jsonb, %L, %L)::text',
    'Materia prima de prueba ' || gen_random_uuid(), p_category, p_unit, '{}', 'Prueba de códigos', p_expected))
$$;

-- ---------------------------------------------------------------------------
-- Lo que ya estaba cargado no cambia
-- ---------------------------------------------------------------------------
select is((select count(*)::int from recipes.recipes where code !~ '^DEMO-'), 0,
          'las recetas del seed conservan su código de antes (DEMO-…)');
select is((select count(*)::int from catalog.ingredients where code !~ '^DEMO-ING-'), 0,
          'las materias primas del seed conservan el suyo (DEMO-ING-…)');

-- ---------------------------------------------------------------------------
-- La tabla de contadores
-- ---------------------------------------------------------------------------
select has_table('catalog', 'code_series', 'existe la tabla de contadores');
select ok((select relrowsecurity from pg_class where oid = 'catalog.code_series'::regclass), 'tiene RLS activado');
select is(pg_temp.q(pg_temp.u(413), 'select count(*)::text from catalog.code_series'), 'ERROR 42501',
          'nadie la lee directo (Chef del grupo)');
select is(pg_temp.q(pg_temp.u(408), 'select count(*)::text from catalog.code_series'), 'ERROR 42501',
          'nadie la lee directo (Compras)');
select is(pg_temp.q(pg_temp.u(413), $$update catalog.code_series set last_number = 0 returning 'x'$$), 'ERROR 42501',
          'ni la cambia');
-- Anónimo: sin sesión, tampoco.
create function pg_temp.anon(p_sql text) returns text language plpgsql as $$
declare
  v text;
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  set local role anon;
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
select is(pg_temp.anon('select count(*)::text from catalog.code_series'), 'ERROR 42501', 'ni sin sesión');

-- ---------------------------------------------------------------------------
-- Vista previa
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(413), $$select recipes.preview_code(pg_temp.u(1062), 'dish')$$), 'PLA-PAS-0001',
          'vista previa de un plato de Pastas: PLA-PAS-0001');
select is(pg_temp.q(pg_temp.u(413), $$select recipes.preview_code(pg_temp.u(1061), 'preparation')$$), 'PRE-SAL-0001',
          'vista previa de una preparación de Salsas: PRE-SAL-0001');
select is((select count(*)::int from catalog.code_series), 0, 'la vista previa no entrega números');
select is(pg_temp.q(pg_temp.u(409), $$select coalesce(recipes.preview_code(pg_temp.u(1062), 'dish'), 'vacío')$$), 'vacío',
          'la Cocinera (sin recipes.draft) no recibe vista previa');
select is(pg_temp.q(pg_temp.u(413), $$select coalesce(recipes.preview_code(pg_temp.u(1061), 'unit_component'), 'vacío')$$),
          'vacío', 'componente por unidad ya no tiene vista previa');
select is(pg_temp.q(pg_temp.u(408), $$select catalog.preview_ingredient_code(pg_temp.u(702))$$), 'MPR-CAR-0001',
          'vista previa de una materia prima de Carnes: MPR-CAR-0001');
select is(pg_temp.q(pg_temp.u(409), $$select coalesce(catalog.preview_ingredient_code(pg_temp.u(702)), 'vacío')$$), 'vacío',
          'la Cocinera (sin catalog.manage) no recibe vista previa de materias primas');
-- Alguien que no es del grupo no recibe nada, ni sabe si el rubro existe.
select is(pg_temp.q(gen_random_uuid(), $$select coalesce(recipes.preview_code(pg_temp.u(1062), 'dish'), 'vacío')$$), 'vacío',
          'una persona sin membresía no recibe la vista previa de recetas');
select is(pg_temp.q(gen_random_uuid(), $$select coalesce(catalog.preview_ingredient_code(pg_temp.u(702)), 'vacío')$$), 'vacío',
          'ni la de materias primas');

-- ---------------------------------------------------------------------------
-- Altas de recetas
-- ---------------------------------------------------------------------------
create temporary table r (k text primary key, v jsonb);
insert into r values ('p1', pg_temp.dish(1062, 'dish', 'PLA-PAS-0001'));
select is(r.v ->> 'code', 'PLA-PAS-0001', 'primer plato de Pastas: PLA-PAS-0001') from r where k = 'p1';
select is(r.v ->> 'code_changed', 'false', 'coincide con la vista previa: sin aviso') from r where k = 'p1';
select ok(exists (select 1 from audit.audit_events
                   where table_schema = 'catalog' and table_name = 'code_series' and action in ('insert', 'update')
                     and reason = 'Prueba de códigos' and new_values ->> 'prefix' = 'PLA-PAS-'),
          'el contador queda en la auditoría, con el motivo del alta');
select is((select code from recipes.recipes where id = (r.v ->> 'id')::uuid), 'PLA-PAS-0001', 'y queda guardado')
  from r where k = 'p1';
select is(pg_temp.dish(1062) ->> 'code', 'PLA-PAS-0002', 'el siguiente plato de Pastas: PLA-PAS-0002');
select is(pg_temp.dish(1063) ->> 'code', 'PLA-CAR-0001', 'cada rubro tiene su propia numeración: PLA-CAR-0001');
select is(pg_temp.dish(1061, 'preparation') ->> 'code', 'PRE-SAL-0001', 'una preparación de Salsas: PRE-SAL-0001');
select is(pg_temp.dish(1061, 'preparation') ->> 'code', 'PRE-SAL-0002', 'la siguiente: PRE-SAL-0002');

-- Subcategoría: usa el rubro madre.
select core.set_change_context('Prueba de códigos', 'manual');
insert into recipes.recipe_categories (id, group_id, parent_id, name)
values (pg_temp.u(1099), pg_temp.u(1), pg_temp.u(1062), 'Pastas rellenas');
select is(pg_temp.dish(1099) ->> 'code', 'PLA-PAS-0003', 'una subcategoría de Pastas usa el rubro madre: PLA-PAS-0003');

-- Alguien creó otra en el medio: se asigna el siguiente y se avisa.
insert into r values ('tarde', pg_temp.dish(1062, 'dish', 'PLA-PAS-0003'));
select is(r.v ->> 'code', 'PLA-PAS-0004', 'con la vista previa vieja se asigna el siguiente') from r where k = 'tarde';
select is(r.v ->> 'code_changed', 'true', 'y lo marca') from r where k = 'tarde';
select is(r.v ->> 'message', 'Receta creada con el código PLA-PAS-0004: el PLA-PAS-0003 lo tomó otra alta mientras cargabas.',
          'con un aviso que se entiende') from r where k = 'tarde';

-- Un número borrado no se reutiliza.
update recipes.recipes set deleted_at = now() where code = 'PLA-PAS-0004';
select is(pg_temp.dish(1062) ->> 'code', 'PLA-PAS-0005', 'después de borrar PLA-PAS-0004 sigue con PLA-PAS-0005');

-- Un código ya tomado a mano se saltea.
insert into recipes.recipes (group_id, scope_type, code, name, recipe_type, category_id)
values (pg_temp.u(1), 'group', 'PLA-PAS-0006', 'Cargada a mano', 'dish', pg_temp.u(1062));
select is(pg_temp.dish(1062) ->> 'code', 'PLA-PAS-0007', 'saltea un código tomado a mano (0006) y da PLA-PAS-0007');

-- Pasado 9999 sigue con 5 dígitos (decisión de Joaco).
update catalog.code_series set last_number = 9999 where group_id = pg_temp.u(1) and prefix = 'PLA-CAR-';
select is(pg_temp.dish(1063) ->> 'code', 'PLA-CAR-10000', 'después de PLA-CAR-9999 viene PLA-CAR-10000');

-- La numeración es del grupo, aunque la receta sea de un local.
select is(pg_temp.dish(1068, 'dish', null, 406, 201) ->> 'code', 'PLA-ENS-0001',
          'el Jefe de Cocina crea un plato de su local: PLA-ENS-0001');
select is(pg_temp.dish(1068, 'dish', null, 409, 201) ->> 'result', 'denied',
          'la Cocinera no crea recetas (el código no abre ningún permiso)');

-- Reglas del alta.
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_recipe(pg_temp.u(1), null, null, 'Medallón', 'unit_component', pg_temp.u(1061), 'Prueba')$$),
          'Elegí el tipo: plato o preparación.', 'componente por unidad ya no se crea');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_recipe(pg_temp.u(1), null, null, 'Sin rubro', 'dish', null, 'Prueba')$$),
          'Elegí el rubro de la receta.', 'sin rubro no hay código: se pide');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.create_recipe(pg_temp.u(1), null, null, 'Plato mal', 'dish', pg_temp.u(1061), 'Prueba')$$),
          'Un plato va en un rubro de menú; una preparación o un componente, en un rubro de sub-recetas.',
          'un plato en un rubro de sub-recetas sigue rechazado');
select is((select count(*)::int from recipes.recipes where code like 'PLA-SAL-%'), 0,
          'y el alta rechazada no dejó receta');

-- ---------------------------------------------------------------------------
-- Altas de materias primas
-- ---------------------------------------------------------------------------
insert into r values ('m1', pg_temp.ing(702, 'kg', 'MPR-CAR-0001')::jsonb);
select is(r.v ->> 'code', 'MPR-CAR-0001', 'primera materia prima de Carnes: MPR-CAR-0001') from r where k = 'm1';
select is((select u.code from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id
            where i.id = (r.v ->> 'id')::uuid), 'g', 'elegida en kilogramos, se guarda en g (la base)') from r where k = 'm1';
insert into r values ('m2', pg_temp.ing(702, 'l')::jsonb);
select is(r.v ->> 'code', 'MPR-CAR-0002', 'la siguiente: MPR-CAR-0002') from r where k = 'm2';
select is((select u.code from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id
            where i.id = (r.v ->> 'id')::uuid), 'ml', 'elegida en litros, se guarda en ml') from r where k = 'm2';
select is(pg_temp.msg(pg_temp.u(408), $$select catalog.create_ingredient(pg_temp.u(1), 'En caja', pg_temp.u(702), 'box', '{}', 'Prueba')$$),
          'Elegí una medida de peso, de volumen o de cantidad.', 'un envase no sirve como medida de recetas');
select is(pg_temp.ing(702, 'kg', null, 409), 'ERROR 42501', 'la Cocinera no crea materias primas');
-- La base sigue exigiendo g, ml o unidad aunque alguien se saltee la función.
select throws_ok($$update catalog.ingredients set recipe_unit_id = (select id from catalog.units where code = 'kg' and deleted_at is null)
                    where code = 'MPR-CAR-0002'$$,
                 '23514', 'La unidad de uso en recetas tiene que ser g, ml o unidad.',
                 'la unidad de uso en recetas guardada es siempre g, ml o unidad');
-- Si un código repetido llegara igual (una carrera con uno cargado a mano), el mensaje sale en español.
select throws_ok($$select catalog.raise_friendly('23505', 'ingredients_code_key', 'duplicate key')$$,
                 '23505', 'Ya existe una materia prima con ese código en el grupo.', 'código de materia prima repetido, en español');
select throws_ok($$select recipes.raise_friendly('23505', 'recipes_code_key', 'duplicate key')$$,
                 '23505', 'Ya existe una receta con ese código en el grupo.', 'código de receta repetido, en español');

-- ---------------------------------------------------------------------------
-- Variantes por local: código de la maestra y -V01
-- ---------------------------------------------------------------------------
select is(pg_temp.q(pg_temp.u(405), $$select recipes.create_variant(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(201), 'Ravioles (Centro)', 'Más relleno') ->> 'code'$$),
          'DEMO-PAS-03-V01', 'la primera variante de DEMO-PAS-03 es DEMO-PAS-03-V01');
select is(pg_temp.q(pg_temp.u(405), $$select recipes.create_variant(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(202), 'Ravioles (Norte)', 'Sin nuez') ->> 'code'$$),
          'DEMO-PAS-03-V02', 'la segunda, DEMO-PAS-03-V02');

-- ---------------------------------------------------------------------------
-- El código no cambia nunca
-- ---------------------------------------------------------------------------
select throws_ok($$update recipes.recipes set code = 'OTRO-0001' where code = 'PLA-PAS-0001'$$, '42501',
                 'El código, el alcance y la maestra de una receta no cambian.', 'el código de una receta no cambia');
select throws_ok($$update catalog.ingredients set code = 'OTRO-0001' where code = 'MPR-CAR-0001'$$, '42501',
                 'El código no cambia nunca.', 'ni el de una materia prima');

select * from finish();
rollback;
