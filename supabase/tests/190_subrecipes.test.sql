-- Fase 2 · Etapa 2.2 B: subrecetas y variantes locales (ADR-0025). Casos del documento de Soy:
-- 10 (sin ciclos), 23 (un dato que falta en una subreceta deja el plato "no verificado") y 26, según la
-- respuesta 10 de Soy (al publicar la v2 de una preparación, los platos ya la usan y se avisa).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(79);

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
    v := 'ERROR ' || sqlstate || ' ' || sqlerrm;
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
create function pg_temp.ver(p_code text, p_number int) returns uuid language sql as $$
  select v.id from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id
   where r.code = p_code and v.version_number = p_number
$$;
create temporary table ids (k text primary key, id uuid);
grant select on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select id from ids where k = p_k $$;
grant execute on function pg_temp.u(int), pg_temp.rec(text), pg_temp.ver(text, int), pg_temp.id(text) to authenticated;
create function pg_temp.res(p_user uuid, p_call text) returns text language sql as $$
  select pg_temp.q(p_user, format('select (%s) ->> ''result''', p_call))
$$;
create function pg_temp.status(p_version uuid) returns text language sql as $$
  select status::text from recipes.recipe_versions where id = p_version
$$;
-- Una línea de subreceta, en JSON.
create function pg_temp.sub(p_code text, p_qty numeric, p_unit text) returns text language sql as $$
  select json_build_object('sub_recipe_id', pg_temp.rec(p_code), 'quantity', p_qty, 'unit', p_unit)::text
$$;
-- Crea una receta, le carga líneas, un paso y rendimiento (1 kg), y la publica: la pide p_author y la
-- aprueba p_approver. Devuelve el estado final de la versión 1.
create function pg_temp.publish_new(p_author uuid, p_approver uuid, p_group uuid, p_brand uuid, p_code text, p_name text,
                                    p_type text, p_lines text)
returns text
language plpgsql
as $$
declare
  v_version uuid;
begin
  v_version := (pg_temp.q(p_author, format($f$select recipes.create_recipe(%L, %L, null, %L, %L, %L, null, 'Prueba') ->> 'version_id'$f$,
                                          p_group, p_brand, p_code, p_name, p_type)))::uuid;
  perform pg_temp.q(p_author, format($f$select recipes.set_components(%L, %L, 'Prueba')$f$, v_version, p_lines));
  perform pg_temp.q(p_author, format($f$select recipes.set_steps(%L, '[{"instructions": "Hacer", "active_minutes": 10}]', 'Prueba')$f$,
                                     v_version));
  perform pg_temp.q(p_author, format($f$select recipes.save_draft(%L, '{"yield_quantity": "1", "yield_unit": "kg"}', 'Prueba')$f$,
                                     v_version));
  return pg_temp.publish(p_author, p_approver, v_version);
end
$$;
-- Pide la revisión de una versión y la aprueba otra persona. Devuelve el estado final.
create function pg_temp.publish(p_author uuid, p_approver uuid, p_version uuid)
returns text
language plpgsql
as $$
begin
  perform pg_temp.q(p_author, format($f$select recipes.request_review(%L, 'Prueba')$f$, p_version));
  perform pg_temp.q(p_approver, format($f$select workflow.decide_approval(%L, 'approved', null)$f$,
                                       (select approval_request_id from recipes.recipe_versions where id = p_version)));
  return pg_temp.status(p_version);
end
$$;
create function pg_temp.allergens(p_user uuid, p_version uuid) returns text language sql as $$
  select pg_temp.q(p_user, format($f$select string_agg(code || '=' || status, ', ' order by code)
                                       from recipes.version_allergens(%L) where code in ('DEMO-GLUTEN', 'DEMO-LECHE')$f$, p_version))
$$;

-- Personas del seed: Chef de Demo Pastas 405 (marca 101), Chef del grupo 413, Dirección 402, Director de
-- marca 403, Jefe de Cocina 406 (Demo Pastas Centro, 201), Cocinera 409 (201), Compras 408. Grupo ...001.
-- Marcas 101 (Pastas), 102 (Parrilla). Locales 201 y 202 (Pastas), 203 (Parrilla).

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_column('recipes', 'recipe_components', 'sub_recipe_id', 'una línea puede ser una subreceta');
select has_column('recipes', 'recipes', 'variant_of_recipe_id', 'una receta puede ser variante de una maestra');
select throws_ok(format($$insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, sub_recipe_id,
                                                                  quantity, unit_id, quantity_basis)
                          select group_id, id, 90, '00000000-0000-4000-8000-000000000801', %L, 1,
                                 (select id from catalog.units where code = 'g'), 'finished'
                            from recipes.recipe_versions where id = %L$$,
                         pg_temp.rec('DEMO-SAL-01'), pg_temp.ver('DEMO-PAS-06', 1)),
  '23514', null, 'una línea es materia prima o subreceta, no las dos');
select throws_ok(format($$insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id,
                                                                  quantity, unit_id, quantity_basis)
                          select group_id, id, 91, '00000000-0000-4000-8000-000000000801', 1,
                                 (select id from catalog.units where code = 'g'), 'finished'
                            from recipes.recipe_versions where id = %L$$, pg_temp.ver('DEMO-PAS-06', 1)),
  '23514', null, 'la cantidad terminada es solo para subrecetas');
select throws_ok(format($$insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id,
                                                                  quantity, unit_id, quantity_basis)
                          select group_id, id, 92, %L, 1, (select id from catalog.units where code = 'g'), 'purchase'
                            from recipes.recipe_versions where id = %L$$,
                         pg_temp.rec('DEMO-SAL-01'), pg_temp.ver('DEMO-PAS-06', 1)),
  '23514', null, 'y una subreceta se mide siempre en cantidad terminada');
select is((select count(*)::int from recipes.recipe_components
            where recipe_version_id = pg_temp.ver('DEMO-PAS-05', 1) and sub_recipe_id is not null and deleted_at is null),
  2, 'seed: la Lasaña usa dos preparaciones (bolognesa y salsa blanca)');
select is((select count(*)::int from recipes.recipe_assignments
            where recipe_id = pg_temp.rec('DEMO-PAS-04') and restaurant_id = pg_temp.u(202) and valid_to is null),
  0, 'seed: Demo Pastas Norte ya no usa los Ñoquis maestros: usa su variante');

-- ---------------------------------------------------------------------------
-- Quien ve un plato ve también sus preparaciones
-- ---------------------------------------------------------------------------
select is(pg_temp.res(pg_temp.u(405), $$recipes.set_assignment(pg_temp.rec('DEMO-SAL-03'), pg_temp.u(201), false, 'Ya no se usa sola')$$),
  'applied', 'la Salsa blanca deja de estar asignada a Centro');
select is(pg_temp.q(pg_temp.u(409), $$select recipes.kitchen_card(pg_temp.rec('DEMO-SAL-03')) ->> 'name'$$), 'Salsa blanca',
  'la Cocinera la sigue viendo: la usa la Lasaña de su local, y la tiene que cocinar');
select is(pg_temp.res(pg_temp.u(413), $$recipes.new_version(pg_temp.rec('DEMO-SAL-03'), 'Más espesa')$$), 'applied',
  'el Chef del grupo abre una versión nueva de la Salsa blanca');
select is(pg_temp.q(pg_temp.u(409), $$select string_agg(version_number::text || status, ', ') from recipes.recipe_versions
                                       where recipe_id = pg_temp.rec('DEMO-SAL-03')$$),
  '1published', 'la Cocinera ve solo la vigente, no el borrador');
select is(pg_temp.q(pg_temp.u(409), $$select string_agg(c ->> 'ingredient', ', ' order by (c ->> 'line')::int)
                                        from jsonb_array_elements(recipes.kitchen_card(pg_temp.rec('DEMO-PAS-05')) -> 'components') c
                                       where c ->> 'sub_recipe_id' is not null$$),
  'Salsa bolognesa, Salsa blanca', 'la ficha de cocina de la Lasaña muestra sus preparaciones, con su enlace');
select is(pg_temp.q(pg_temp.u(409), $$select coalesce(recipes.kitchen_card(pg_temp.rec('DEMO-PAR-01'))::text, 'nada')$$), 'nada',
  'pero no ve una preparación de otra marca que no usa');

-- ---------------------------------------------------------------------------
-- Validaciones al cargar una subreceta
-- ---------------------------------------------------------------------------
insert into ids
select 'plato', (r ->> 'id')::uuid from (select pg_temp.q(pg_temp.u(405),
  $$select recipes.create_recipe(null, pg_temp.u(101), null, 'PRB-PLATO', 'Plato de prueba', 'dish', null, 'Prueba')::text$$)::jsonb as r) x;
insert into ids select 'plato_v1', id from recipes.recipe_versions where recipe_id = pg_temp.id('plato');

select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('DEMO-PAS-06', 100, 'g') || ']')),
  'Línea 1: elegí una preparación con una versión vigente.', 'una receta sin versión vigente no se usa como preparación');
select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('DEMO-PAR-01', 100, 'ml') || ']')),
  'Línea 1: elegí una preparación con una versión vigente.',
  'quien no ve una preparación no la usa, y el mensaje no la nombra');
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('DEMO-PAR-01', 100, 'ml') || ']')),
  'Línea 1 (Chimichurri): esa preparación no se puede usar acá: es de otra marca o de otro local.',
  'un plato de Pastas no usa una preparación de Parrilla, aunque quien edita la vea');
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('DEMO-LOC-01', 1, 'unit') || ']')),
  'Línea 1 (Sorrentinos de zapallo): esa preparación no se puede usar acá: es de otra marca o de otro local.',
  'un plato de marca no usa una receta de un local');
select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('DEMO-SAL-01', 200, 'g') || ']')),
  format('Línea 1 (Salsa fileto): usá una unidad como la de su rendimiento (%s).', (select name from catalog.units where code = 'l')),
  'la unidad tiene que poder pasarse a la del rendimiento de la preparación (la fileto rinde litros)');
select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 100, "unit": "g", "basis": "finished"}]', 'Prueba')$$,
    pg_temp.id('plato_v1'))),
  'Línea 1 (Tomate perita): la cantidad terminada es solo para preparaciones.', 'una materia prima no va en cantidad terminada');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[{"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 100, "unit": "g"}, '
      || pg_temp.sub('DEMO-SAL-01', 200, 'ml') || ']')),
  'applied', 'una preparación vigente del grupo, en mililitros, se carga');
select is((select quantity_basis::text from recipes.recipe_components
            where recipe_version_id = pg_temp.id('plato_v1') and sub_recipe_id is not null and deleted_at is null),
  'finished', 'y queda en cantidad terminada');
select is(pg_temp.q(pg_temp.u(405), format($$select string_agg(code, ', ' order by code)
                                               from recipes.search_subrecipes('salsa', %L)$$, pg_temp.id('plato'))),
  'DEMO-SAL-01, DEMO-SAL-02, DEMO-SAL-03', 'el buscador trae las preparaciones vigentes a su alcance');
select is(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from recipes.search_subrecipes('chimi', %L)$$, pg_temp.id('plato'))),
  '0', 'y no las de otra marca');
select is(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from recipes.search_subrecipes('sa', %L)$$, pg_temp.id('plato'))),
  '0', 'desde tres letras');
select is(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from recipes.search_subrecipes('%%%%%%', %L)$$, pg_temp.id('plato'))),
  '0', 'los signos de porcentaje se buscan tal cual, no traen todo');
select ok(exists (select 1 from audit.audit_events where table_name = 'recipe_components' and reason = 'Prueba'
                    and new_values ->> 'sub_recipe_id' = pg_temp.rec('DEMO-SAL-01')::text),
  'la línea con la preparación queda en la auditoría, con su motivo');

-- ---------------------------------------------------------------------------
-- Caso 10: sin ciclos (A usa B, B usa C: C no puede usar A)
-- ---------------------------------------------------------------------------
select is(pg_temp.publish_new(pg_temp.u(413), pg_temp.u(402), pg_temp.u(1), null, 'PRB-C', 'Prueba C', 'preparation',
    '[{"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 100, "unit": "g"}]'),
  'published', 'la preparación C queda vigente');
select is(pg_temp.publish_new(pg_temp.u(413), pg_temp.u(402), pg_temp.u(1), null, 'PRB-B', 'Prueba B', 'preparation',
    '[' || pg_temp.sub('PRB-C', 100, 'g') || ']'), 'published', 'B usa C');
select is(pg_temp.publish_new(pg_temp.u(413), pg_temp.u(402), pg_temp.u(1), null, 'PRB-A', 'Prueba A', 'preparation',
    '[' || pg_temp.sub('PRB-B', 0.1, 'kg') || ']'), 'published', 'A usa B (en kilos: se convierte)');
select is(pg_temp.res(pg_temp.u(413), $$recipes.new_version(pg_temp.rec('PRB-C'), 'Con A')$$), 'applied', 'versión nueva de C');
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.set_components(%L, %L, 'Con A')$$, pg_temp.ver('PRB-C', 2),
    '[' || pg_temp.sub('PRB-A', 100, 'g') || ']')),
  'Línea 1 (Prueba A): esa preparación ya usa esta receta: se formaría un círculo.', 'caso 10: C no puede usar A');
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.set_components(%L, %L, 'Sí misma')$$, pg_temp.ver('PRB-C', 2),
    '[' || pg_temp.sub('PRB-C', 100, 'g') || ']')),
  'Línea 1 (Prueba C): una receta no se puede usar a sí misma.', 'ni usarse a sí misma');
-- Una línea que entró sin pasar por set_components (por ejemplo, copiada) se controla al pedir la revisión.
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select group_id, id, 2, pg_temp.rec('PRB-A'), 100, (select id from catalog.units where code = 'g'), 'finished'
  from recipes.recipe_versions where id = pg_temp.ver('PRB-C', 2);
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.request_review(%L, 'Con A')$$, pg_temp.ver('PRB-C', 2))),
  'Línea 2 (Prueba A): la preparación ya usa esta receta: se formaría un círculo. Corregila antes de pedir la revisión.',
  'caso 10: el círculo también se frena al pedir la revisión');
update recipes.recipe_components set deleted_at = now()
 where recipe_version_id = pg_temp.ver('PRB-C', 2) and sub_recipe_id = pg_temp.rec('PRB-A');

-- Hasta 10 niveles: una cadena de 10 preparaciones (N1 la más baja) ya tiene 9 niveles debajo de N10.
do $$
begin
  perform pg_temp.publish_new(pg_temp.u(413), pg_temp.u(402), pg_temp.u(1), null, 'PRB-N1', 'Nivel 1', 'preparation',
    '[{"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 100, "unit": "g"}]');
  for i in 2..10 loop
    perform pg_temp.publish_new(pg_temp.u(413), pg_temp.u(402), pg_temp.u(1), null, 'PRB-N' || i, 'Nivel ' || i, 'preparation',
      '[' || pg_temp.sub('PRB-N' || (i - 1), 100, 'g') || ']');
  end loop;
end
$$;
select is(pg_temp.status(pg_temp.ver('PRB-N10', 1)), 'published', 'la cadena de 10 niveles queda vigente');
select is(pg_temp.msg(pg_temp.u(405), format($$select recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('PRB-N10', 100, 'g') || ']')),
  'Línea 1 (Nivel 10): se pasaría de 10 niveles de preparaciones.', 'más de 10 niveles no');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.set_components(%L, %L, 'Prueba')$$, pg_temp.id('plato_v1'),
    '[' || pg_temp.sub('PRB-N9', 100, 'g') || ']')),
  'applied', 'diez justos, sí');
select is(pg_temp.allergens(pg_temp.u(405), pg_temp.ver('PRB-N10', 1)), 'DEMO-GLUTEN=free_verified, DEMO-LECHE=not_verified',
  'los alérgenos bajan los 10 niveles (el tomate de N1 está verificado sin gluten)');
select is(pg_temp.res(pg_temp.u(413), $$recipes.new_version(pg_temp.rec('PRB-N1'), 'Con C')$$), 'applied', 'versión nueva de la más baja');
select is(pg_temp.msg(pg_temp.u(413), format($$select recipes.set_components(%L, %L, 'Con C')$$, pg_temp.ver('PRB-N1', 2),
    '[' || pg_temp.sub('PRB-C', 100, 'g') || ']')),
  'Línea 1 (Prueba C): se pasaría de 10 niveles de preparaciones.',
  'la cadena tampoco se alarga desde abajo: cuenta los niveles que tiene encima');
-- Aunque una cadena más larga entrara por otro lado, los alérgenos no dicen "verificado" a medias.
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select group_id, id, 2, pg_temp.rec('PRB-B'), 100, (select id from catalog.units where code = 'g'), 'finished'
  from recipes.recipe_versions where id = pg_temp.ver('PRB-N1', 2);
update recipes.recipe_versions set status = 'archived' where id = pg_temp.ver('PRB-N1', 1);
update recipes.recipe_versions set status = 'in_review' where id = pg_temp.ver('PRB-N1', 2);
update recipes.recipe_versions set status = 'approved', approved_by = pg_temp.u(402) where id = pg_temp.ver('PRB-N1', 2);
update recipes.recipe_versions set status = 'published', published_at = now() where id = pg_temp.ver('PRB-N1', 2);
select is(pg_temp.allergens(pg_temp.u(405), pg_temp.ver('PRB-N10', 1)), 'DEMO-GLUTEN=not_verified, DEMO-LECHE=not_verified',
  'con un nivel 11, el árbol queda cortado: "no verificado", nunca un sin gluten parcial');

-- ---------------------------------------------------------------------------
-- Casos 23 y 26: la preparación cambia, los platos la usan sola, y se avisa
-- ---------------------------------------------------------------------------
select is(pg_temp.publish_new(pg_temp.u(413), pg_temp.u(402), pg_temp.u(1), null, 'PRB-SALSA', 'Salsa simple de prueba', 'preparation',
    '[{"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 500, "unit": "g"}]'),
  'published', 'una salsa simple de tomate');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.set_components(%L, %L, 'Con salsa')$$, pg_temp.id('plato_v1'),
    '[{"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 100, "unit": "g"}, '
      || pg_temp.sub('PRB-SALSA', 150, 'g') || ']')),
  'applied', 'el plato usa la salsa');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.set_steps(%L, '[{"instructions": "Servir", "active_minutes": 5}]', 'Pasos')$$,
    pg_temp.id('plato_v1'))), 'applied', 'con un paso');
select is(pg_temp.res(pg_temp.u(405), format($$recipes.save_draft(%L, '{"yield_quantity": "1", "yield_unit": "unit", "portions": 1}', 'Rinde')$$,
    pg_temp.id('plato_v1'))), 'applied', 'y su rendimiento');
select is(pg_temp.publish(pg_temp.u(405), pg_temp.u(403), pg_temp.id('plato_v1')), 'published',
  'lo pide la Chef y lo aprueba la Directora de marca');
select is(pg_temp.allergens(pg_temp.u(405), pg_temp.id('plato_v1')), 'DEMO-GLUTEN=free_verified, DEMO-LECHE=not_verified',
  'todo tomate: sin gluten verificado');
select is(pg_temp.q(pg_temp.u(405), $$select string_agg(code, ', ') from recipes.recipe_usage(pg_temp.rec('PRB-SALSA'))$$),
  'PRB-PLATO', 'la salsa sabe dónde se usa');

select is(pg_temp.res(pg_temp.u(405), format($$recipes.set_assignment(%L, pg_temp.u(201), true, 'Se sirve en Centro')$$, pg_temp.id('plato'))),
  'applied', 'el plato se usa en Demo Pastas Centro');
select is(pg_temp.res(pg_temp.u(413), $$recipes.new_version(pg_temp.rec('PRB-SALSA'), 'Con cebolla y leche')$$), 'applied',
  'versión 2 de la salsa');
select is(pg_temp.res(pg_temp.u(413), format($$recipes.set_components(%L, '[
    {"ingredient_id": "00000000-0000-4000-8000-000000000801", "quantity": 500, "unit": "g"},
    {"ingredient_id": "00000000-0000-4000-8000-000000000802", "quantity": 100, "unit": "g"},
    {"ingredient_id": "00000000-0000-4000-8000-000000000823", "quantity": 100, "unit": "ml"}]', 'Con cebolla y leche')$$,
    pg_temp.ver('PRB-SALSA', 2))), 'applied', 'suma cebolla (sin dato de gluten) y leche');
select is(pg_temp.publish(pg_temp.u(413), pg_temp.u(402), pg_temp.ver('PRB-SALSA', 2)), 'published', 'Dirección publica la v2');
select is(pg_temp.status(pg_temp.id('plato_v1')), 'published', 'caso 26: el plato no necesita una versión nueva');
select is(pg_temp.allergens(pg_temp.u(405), pg_temp.id('plato_v1')), 'DEMO-GLUTEN=not_verified, DEMO-LECHE=contains',
  'casos 23 y 26: el plato ya usa la v2: contiene leche, y la cebolla sin dato lo deja "no verificado"');
select is((select string_agg(recipient_user_id::text, ', ' order by recipient_user_id) from core.notifications
            where kind = 'recipe_changed' and link = '/recetas/' || pg_temp.rec('PRB-SALSA')),
  array_to_string(array[pg_temp.u(403), pg_temp.u(404), pg_temp.u(405), pg_temp.u(408), pg_temp.u(411), pg_temp.u(412),
                        pg_temp.u(413)]::text[], ', '),
  'caso 26 (respuesta 5 de Soy): avisa a quienes publican el plato y a Compras, Dirección y Gerencia de Centro, que lo usa; no a quien aprobó');
select is((select title || ' / ' || body from core.notifications
            where kind = 'recipe_changed' and recipient_user_id = pg_temp.u(408) and link = '/recetas/' || pg_temp.rec('PRB-SALSA')),
  'Cambió «Salsa simple de prueba» (v2) / Las recetas que la usan ya usan la versión nueva. Revisá si hace falta ajustar algo.',
  'el aviso dice qué cambió, sin contar platos de otras marcas');
select is((select count(*)::int from core.notifications where kind = 'recipe_changed' and recipient_user_id = pg_temp.u(409)),
  0, 'la Cocinera no recibe avisos de cambios');
select is(pg_temp.msg(pg_temp.u(413), $$select recipes.archive_recipe(pg_temp.rec('PRB-SALSA'), 'Ya no')$$),
  'La usan otras recetas (Plato de prueba): sacala de ellas antes de archivarla.',
  'una preparación que se usa no se archiva');
select is(pg_temp.res(pg_temp.u(413), $$recipes.new_version(pg_temp.rec('PRB-SALSA'), 'En unidades')$$), 'applied', 'versión 3 de la salsa');
select is(pg_temp.res(pg_temp.u(413), format($$recipes.save_draft(%L, '{"yield_quantity": "1", "yield_unit": "unit"}', 'En unidades')$$,
    pg_temp.ver('PRB-SALSA', 3))), 'applied', 'que rinde en unidades');
select is(pg_temp.publish(pg_temp.u(413), pg_temp.u(402), pg_temp.ver('PRB-SALSA', 3)), 'in_review',
  'no se publica: el plato la usa en gramos y quedaría sin poder convertirse');

-- ---------------------------------------------------------------------------
-- Variantes locales
-- ---------------------------------------------------------------------------
select is(pg_temp.res(pg_temp.u(406), $$recipes.create_variant(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(201), 'PRB-VAR', 'Ravioles (Centro)', 'Más relleno')$$),
  'denied', 'el Jefe de Cocina no crea variantes: solo el Chef Ejecutivo');
insert into ids
select 'var', (r ->> 'id')::uuid from (select pg_temp.q(pg_temp.u(405),
  $$select recipes.create_variant(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(201), 'prb-var', 'Ravioles (Centro)', 'Más relleno')::text$$)::jsonb as r) x;
insert into ids select 'var_v1', id from recipes.recipe_versions where recipe_id = pg_temp.id('var');
select is((select scope_type::text || '/' || restaurant_id::text || '/' || variant_of_recipe_id::text from recipes.recipes where id = pg_temp.id('var')),
  'restaurant/' || pg_temp.u(201) || '/' || pg_temp.rec('DEMO-PAS-03'), 'la Chef crea la variante de Centro');
select ok(exists (select 1 from audit.audit_events where table_name = 'recipes' and record_id = pg_temp.id('var')
                    and reason = 'Más relleno' and new_values ->> 'variant_of_recipe_id' = pg_temp.rec('DEMO-PAS-03')::text),
  'la variante queda en la auditoría, con su maestra y su motivo');
select is(pg_temp.status(pg_temp.id('var_v1')) || '/' ||
          (select count(*) from recipes.recipe_components where recipe_version_id = pg_temp.id('var_v1') and deleted_at is null),
  'draft/6', 'en borrador, con las 6 líneas de la maestra (también su preparación)');
select is(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from recipes.variant_diff(%L)$$, pg_temp.id('var'))), '0',
  'todavía igual a la maestra');
select is(pg_temp.msg(pg_temp.u(405), $$select recipes.create_variant(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(201), 'PRB-VAR2', 'Otra', 'Otra')$$),
  'Ese local ya tiene una variante de esta receta.', 'una sola variante por local');
select is(pg_temp.msg(pg_temp.u(402), $$select recipes.create_variant(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(203), 'PRB-VAR3', 'Otra', 'Otra')$$),
  'Ese local no usa esa receta: está fuera de su alcance.', 'no se hace la variante para un local de otra marca');
select is(pg_temp.msg(pg_temp.u(405), $$select recipes.create_variant(pg_temp.rec('DEMO-LOC-01'), pg_temp.u(202), 'PRB-VAR4', 'Otra', 'Otra')$$),
  'Solo se hacen variantes de una receta maestra del grupo o de una marca, activa.', 'ni de una receta de local');

select is(pg_temp.res(pg_temp.u(406), format($$recipes.set_components(%L, %L, 'Más ricota')$$, pg_temp.id('var_v1'),
    '[{"ingredient_id": "00000000-0000-4000-8000-000000000827", "quantity": 100, "unit": "g"},
      {"ingredient_id": "00000000-0000-4000-8000-000000000826", "quantity": 1, "unit": "unit"},
      {"ingredient_id": "00000000-0000-4000-8000-000000000821", "quantity": 160, "unit": "g"},
      {"ingredient_id": "00000000-0000-4000-8000-000000000820", "quantity": 20, "unit": "g"},
      {"ingredient_id": "00000000-0000-4000-8000-000000000844", "quantity": 0.5, "unit": "g"}, '
      || pg_temp.sub('DEMO-SAL-02', 150, 'g') || ']')),
  'applied', 'el Jefe de Cocina de Centro ajusta la variante de su local');
select is(pg_temp.q(pg_temp.u(406), format($$select string_agg(change || ' ' || ingredient || ' ' || old_quantity::numeric(10,0) || '→' || new_quantity::numeric(10,0), ', ')
                                               from recipes.variant_diff(%L)$$, pg_temp.id('var'))),
  'changed Ricota 120→160', 'las diferencias contra la maestra');
select is(pg_temp.q(pg_temp.u(409), format($$select count(*)::text from recipes.variant_diff(%L)$$, pg_temp.id('var'))), '0',
  'la Cocinera no ve las diferencias');
select is(pg_temp.publish(pg_temp.u(406), pg_temp.u(405), pg_temp.id('var_v1')), 'published', 'la Chef publica la variante');
select is((select count(*)::int from recipes.recipe_assignments
            where recipe_id = pg_temp.rec('DEMO-PAS-03') and restaurant_id = pg_temp.u(201) and valid_to is null and deleted_at is null)
          || '/' ||
          (select count(*)::int from recipes.recipe_assignments
            where recipe_id = pg_temp.rec('DEMO-PAS-03') and restaurant_id = pg_temp.u(202) and valid_to is null and deleted_at is null),
  '0/1', 'Centro deja de usar la maestra; Norte la sigue usando');
select is(pg_temp.q(pg_temp.u(405), format($$select recipes.kitchen_card(%L) -> 'variant_of' ->> 'name'$$, pg_temp.id('var'))),
  'Ravioles de ricota', 'la ficha de la variante dice de qué maestra sale');
select is(pg_temp.q(pg_temp.u(409), format($$select coalesce(recipes.kitchen_card(%L) ->> 'variant_of', 'sin maestra') || '/' ||
                                                      (recipes.kitchen_card(%L) ->> 'name')$$, pg_temp.id('var'), pg_temp.id('var'))),
  'sin maestra/Ravioles (Centro)', 'la cocina de Centro ve la variante, sin la maestra que ya no usa');
select is(pg_temp.q(pg_temp.u(406), format($$select count(*)::text from recipes.variant_diff(%L)$$, pg_temp.id('var'))), '0',
  'el Jefe de Cocina ya no ve la maestra, así que tampoco las diferencias');
select is(pg_temp.q(pg_temp.u(405), format($$select count(*)::text from recipes.variant_diff(%L)$$, pg_temp.id('var'))), '1',
  'la Chef de la marca, sí');
select is(pg_temp.msg(pg_temp.u(405), $$select recipes.set_assignment(pg_temp.rec('DEMO-PAS-03'), pg_temp.u(201), true, 'Vuelve')$$),
  'Ese local usa una variante de esta receta: archivala antes de volver a la maestra.',
  'la maestra no vuelve al local mientras use la variante');
select throws_ok(format($$update recipes.recipes set variant_of_recipe_id = null where id = %L$$, pg_temp.id('var')),
  '42501', 'El código, el alcance y la maestra de una receta no cambian.', 'la maestra de una variante no cambia');

select * from finish();
rollback;
