-- Hacer varias recetas y fichas técnicas (Tanda 2 de Soy, PR C, ADR-0065): cada línea en su unidad y sin densidad, las
-- medidas prácticas multiplicadas, quién aprobó (solo el nombre) y el punto crítico que se conserva.
-- Personas del seed: ...0405 chef de marca, ...0407 controller, ...0409 cocinera, ...0413 chef del grupo.
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
    v := 'ERROR ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end
$$;
create function pg_temp.u(p_n int) returns uuid language sql strict as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create function pg_temp.rec(p_code text) returns uuid language sql as $$ select id from recipes.recipes where code = p_code $$;
create function pg_temp.pub(p_code text) returns uuid language sql as $$
  select v.id from recipes.recipe_versions v join recipes.recipes r on r.id = v.recipe_id where r.code = p_code and v.status = 'published'
$$;
create function pg_temp.m(p_name text) returns uuid language sql as $$
  select id from catalog.practical_measures where name = p_name and group_id = pg_temp.u(1)
$$;
create function pg_temp.scale(p_user int, p_version uuid, p_target numeric, p_mode text, p_unit text default null) returns jsonb
language plpgsql as $$
declare
  v text;
begin
  v := pg_temp.q(pg_temp.u(p_user), format('select recipes.scale_version(%L, %s, %L, %L)::text', p_version, p_target, p_mode, p_unit));
  return case when v like 'ERROR%' then to_jsonb(v) else v::jsonb end;
end
$$;
create function pg_temp.card(p_user int, p_code text) returns jsonb language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select recipes.kitchen_card(%L)::text', pg_temp.rec(p_code)))::jsonb
$$;

-- ---------------------------------------------------------------------------
-- Por recetas, en la unidad de cada línea y sin densidad
-- ---------------------------------------------------------------------------
-- La salsa blanca lleva 1.000 ml de leche, que no tiene densidad.
select ok(not exists (select 1 from catalog.ingredient_unit_conversions where ingredient_id = pg_temp.u(823) and kind = 'density' and deleted_at is null),
  'la leche no tiene densidad');
select is(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 3, 'recipes') ->> 'factor', '3.000000', '3 recetas: factor 3');
select is(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 3, 'recipes') -> 'lines' -> 0 ->> 'scaled', '3000.000000', 'la leche se multiplica');
select is(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 3, 'recipes') -> 'lines' -> 0 ->> 'unit', 'ml', 'y sigue en mililitros');
select ok((select bool_and((l ->> 'scaled')::numeric = (l ->> 'quantity')::numeric * 3)
             from jsonb_array_elements(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 3, 'recipes') -> 'lines') l), 'todas las líneas, por tres');
select is((pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 3, 'recipes') ->> 'target_yield')::numeric, 3::numeric, 'rinde 3 litros');
select is(pg_temp.scale(409, pg_temp.pub('DEMO-PAS-04'), 12, 'recipes') ->> 'target_portions', '48.00', '12 recetas de 4 son 48 porciones');
select is(pg_temp.scale(409, pg_temp.pub('DEMO-PAS-04'), 0.5, 'recipes') ->> 'factor', '0.500000', 'media receta también');
select is(pg_temp.scale(409, pg_temp.pub('DEMO-PAS-04'), 48, 'portions') -> 'lines', pg_temp.scale(409, pg_temp.pub('DEMO-PAS-04'), 12, 'recipes') -> 'lines',
  'por porciones da lo mismo');
select matches(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 0, 'recipes') #>> '{}', 'mayor que cero', 'cero recetas, no');
select matches(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 9999999, 'recipes') #>> '{}', 'demasiado chico o demasiado grande', 'ni una cantidad absurda');
select matches(pg_temp.scale(409, pg_temp.pub('DEMO-PAR-04'), 2, 'recipes') #>> '{}', 'No tenés permiso', 'quien no ve la receta no la multiplica');
select ok(pg_temp.scale(409, pg_temp.pub('DEMO-SAL-03'), 3, 'recipes')::text !~* '(cost|price|\$)', 'sin importes');
select matches(pg_temp.q(null, format('select recipes.scale_version(%L, 2, ''recipes'')::text', pg_temp.pub('DEMO-SAL-03'))), 'No tenés permiso', 'sin sesión, no');

-- ---------------------------------------------------------------------------
-- Medidas prácticas
-- ---------------------------------------------------------------------------
create temporary table d as select (pg_temp.q(pg_temp.u(413),
  format('select recipes.new_version(%L, ''Prueba'') ->> ''id''', pg_temp.rec('DEMO-SAL-01'))))::uuid as id;
grant select on d to authenticated;
create function pg_temp.line(p_ing int, p_qty text, p_unit text, p_measure text, p_count text default null) returns jsonb language sql as $$
  select jsonb_build_object('ingredient_id', pg_temp.u(p_ing), 'quantity', p_qty, 'unit', p_unit)
         || case when p_measure is null then '{}'::jsonb else jsonb_build_object('measure_id', pg_temp.m(p_measure)) end
         || case when p_count is null then '{}'::jsonb else jsonb_build_object('measure_count', p_count) end
$$;
select is(pg_temp.q(pg_temp.u(413), format('select recipes.set_components(%L, %L, ''Prueba'') ->> ''result''', (select id from d),
  jsonb_build_array(pg_temp.line(827, '480', 'g', 'Nido de pasta'), pg_temp.line(823, '80', 'ml', 'Taza'),
                    pg_temp.line(833, '30', 'ml', 'Cucharada', '2,5'), pg_temp.line(809, '3', 'unit', 'Nido de pasta'),
                    pg_temp.line(837, '10', 'g', null), pg_temp.line(828, '120', 'g', 'Nido de pasta') || '{"no_scale": true}'))), 'applied', 'un borrador con medidas');
create function pg_temp.ms(p_target numeric, p_n int) returns text language sql as $$
  select trim_scale((l ->> 'measure_scaled')::numeric)::text
    from jsonb_array_elements(pg_temp.scale(413, (select id from d), p_target, 'recipes') -> 'lines') l where (l ->> 'order')::int = p_n
$$;
select is(pg_temp.ms(12, 1), '48', '48 nidos de 120 g');
select is(pg_temp.scale(413, (select id from d), 12, 'recipes') -> 'lines' -> 0 ->> 'measure_name', 'Nido de pasta', 'con su nombre');
select is(trim_scale((pg_temp.scale(413, (select id from d), 12, 'recipes') -> 'lines' -> 0 ->> 'measure_content')::numeric)::text, '120', 'lo que contiene');
select is(pg_temp.scale(413, (select id from d), 12, 'recipes') -> 'lines' -> 0 ->> 'measure_unit', 'g', 'y en qué');
select is(pg_temp.ms(3, 2), '1', 'tres veces 80 ml son una taza: no arrastra el redondeo (3 × 0,33)');
select is(pg_temp.ms(4, 3), '10', 'lo corregido a mano se multiplica');
select is(pg_temp.ms(4, 4), '12', 'con el peso por unidad, también');
select is(pg_temp.ms(4, 5), null, 'sin medida práctica, vacía');
select is(pg_temp.ms(4, 6), '1', 'una línea «no escalar» conserva las suyas');
-- El peso por unidad de la materia prima cambia después: lo guardado manda.
update catalog.ingredient_unit_conversions set factor = 60 where ingredient_id = pg_temp.u(809) and kind = 'unit_weight' and deleted_at is null;
select is(pg_temp.ms(4, 4), '12', 'si cambia el peso por unidad, sale de lo que tiene la versión');
select is(pg_temp.ms(0.001, 3), '0.01', 'un poco nunca es cero');

-- Con factor 1, lo mismo que tiene la versión; por rendimiento, lo mismo que por recetas.
select ok((select bool_and((l ->> 'measure_scaled')::numeric = (l ->> 'measure_count')::numeric)
             from jsonb_array_elements(pg_temp.scale(413, (select id from d), 1, 'recipes') -> 'lines') l where l ->> 'measure_count' is not null),
  'una receta: las medidas de la versión');
select is(pg_temp.scale(413, (select id from d), 8, 'yield', 'l') -> 'lines', pg_temp.scale(413, (select id from d), 4, 'recipes') -> 'lines',
  'por rendimiento (8 l de una receta de 2 l) da lo mismo que 4 recetas');
-- Un factor periódico (un tercio): 0,375 ml son 0,125, y el medio va para arriba.
insert into catalog.practical_measures (group_id, name, content, content_unit_id)
values (pg_temp.u(1), 'Gotero', 1, (select id from catalog.units where code = 'ml'));
update recipes.recipe_versions set portions = 3 where id = (select id from d);
select is(pg_temp.q(pg_temp.u(413), format('select recipes.set_components(%L, %L, ''Prueba'') ->> ''result''', (select id from d),
  jsonb_build_array(pg_temp.line(833, '0.375', 'ml', 'Gotero')))), 'applied', 'una línea para el redondeo');
select is(trim_scale((pg_temp.scale(413, (select id from d), 1, 'portions') -> 'lines' -> 0 ->> 'measure_scaled')::numeric)::text, '0.13',
  'el factor periódico no corre el redondeo');

-- ---------------------------------------------------------------------------
-- La ficha: quién aprobó, sector y partida
-- ---------------------------------------------------------------------------
update recipes.recipes set sector = 'Cocina caliente', station = 'Pastas' where code = 'DEMO-PAS-04';
select is(pg_temp.card(409, 'DEMO-PAS-04') ->> 'approved_by_name',
  (select btrim(first_name || ' ' || last_name) from core.user_profiles where id = pg_temp.u(405)), 'la Cocinera ve quién aprobó');
select ok(strpos(pg_temp.card(409, 'DEMO-PAS-04')::text, pg_temp.u(405)::text) = 0 and pg_temp.card(409, 'DEMO-PAS-04')::text not like '%@%',
  'sin su id ni su correo');
select isnt(pg_temp.card(409, 'DEMO-PAS-04') ->> 'approved_by_name', null, 'el nombre no está vacío');
select is(pg_temp.card(409, 'DEMO-SAL-03') ->> 'yield_unit_code', 'l', 'lo que rinde, con el código de su unidad');
select ok(strpos(pg_temp.card(409, 'DEMO-PAS-04')::text, (select email from core.user_profiles where id = pg_temp.u(405))) = 0, 'su correo no está');
-- Una persona suspendida sigue siendo quien aprobó; sin aprobador, no hay nombre.
update core.user_profiles set status = 'suspended', suspended_at = now(), suspension_reason = 'Prueba' where id = pg_temp.u(405);
select isnt(pg_temp.card(409, 'DEMO-PAS-04') ->> 'approved_by_name', null, 'una cuenta suspendida conserva su historia');
alter table recipes.recipe_versions disable trigger user;
update recipes.recipe_versions set approved_by = null where id = pg_temp.pub('DEMO-PAS-04');
alter table recipes.recipe_versions enable trigger user;
select is(pg_temp.card(409, 'DEMO-PAS-04') ->> 'approved_by_name', null, 'sin aprobador, vacío: nunca se supone');
select is(pg_temp.card(409, 'DEMO-PAS-04') ? 'approved_by', false, 'ni la clave con su id');
select ok(pg_temp.card(409, 'DEMO-PAS-04')::text !~* '(cost|price|email)', 'en ningún nivel hay importes ni correos');
select is(pg_temp.card(409, 'DEMO-PAS-04') ->> 'sector', 'Cocina caliente', 'el sector');
select is(pg_temp.card(409, 'DEMO-PAS-04') ->> 'station', 'Pastas', 'y la partida');
select is(pg_temp.card(409, 'DEMO-SAL-03') -> 'components' -> 0 ->> 'unit_code', 'ml', 'cada línea con el código de su unidad');
select is(pg_temp.card(409, 'DEMO-PAR-04'), null, 'quien no ve la receta no recibe la ficha');
select is((select count(*)::int from jsonb_object_keys(pg_temp.card(409, 'DEMO-PAS-04')) k where k ~* '(cost|price|email|_by$|_by_id$)'), 0, 'ni importes ni datos de la persona');

-- ---------------------------------------------------------------------------
-- Punto crítico
-- ---------------------------------------------------------------------------
select matches(pg_temp.card(409, 'DEMO-PAS-04') -> 'steps' -> 1 ->> 'control_point', 'apenas suben', 'la ficha trae el punto crítico');
select is(pg_temp.q(pg_temp.u(413), format('select recipes.set_steps(%L, %L, ''Prueba'') ->> ''result''', (select id from d),
  '[{"instructions": "Hervir", "kind": "cooking", "control_point": "A 74 °C"}, {"instructions": "Servir", "control_point": "  "}]')), 'applied', 'se guarda');
select is((select string_agg(coalesce(control_point, '—'), ',' order by step_number) from recipes.recipe_steps
            where recipe_version_id = (select id from d) and deleted_at is null), 'A 74 °C,—', 'y vacío es sin punto crítico');
select ok(pg_temp.q(pg_temp.u(413), format('select recipes.set_steps(%L, %L, ''Prueba'') ->> ''result''', (select id from d),
  jsonb_build_array(jsonb_build_object('instructions', 'Hervir', 'control_point', repeat('x', 501))))) is distinct from 'applied', 'hasta 500 caracteres');
select is((select control_point from recipes.recipe_steps where recipe_version_id = (select id from d) and step_number = 1 and deleted_at is null), 'A 74 °C',
  'lo rechazado no cambió nada');
create temporary table n as select (pg_temp.q(pg_temp.u(413),
  format('select recipes.new_version(%L, ''Prueba'') ->> ''id''', pg_temp.rec('DEMO-SAL-02'))))::uuid as id;
select matches((select control_point from recipes.recipe_steps where recipe_version_id = (select id from n) and step_number = 2), '74 °C',
  'una versión nueva lo copia');
select ok(exists (select 1 from audit.audit_events where table_schema = 'recipes' and table_name = 'recipe_steps'
                    and actor_user_id = pg_temp.u(413) and new_values ->> 'control_point' = 'A 74 °C'), 'queda en la auditoría');

select * from finish();
rollback;
