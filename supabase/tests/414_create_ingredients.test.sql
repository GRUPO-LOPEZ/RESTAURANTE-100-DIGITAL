-- «+ Nueva materia prima» desde la receta (Tanda 2 de Soy, PR B, ADR-0064): quién la crea, con qué, el aviso a Compras, el
-- rechazo registrado y las parecidas.
-- Personas del seed: ...0401 superadministrador, ...0402 Dirección, ...0403 directora de marca, ...0404 gerente, ...0405 chef
-- de marca, ...0406 jefe de cocina, ...0408 compras, ...0409 cocinera, ...0410 auditor, ...0413 chef del grupo.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(43);

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
grant execute on function pg_temp.u(int) to authenticated;
create function pg_temp.cat(p_name text) returns uuid language sql as $$
  select id from catalog.ingredient_categories where name = p_name and parent_id is null and group_id = pg_temp.u(1) and deleted_at is null
$$;
create function pg_temp.quick(p_user int, p_name text, p_cat uuid default pg_temp.cat('Carnes'), p_unit text default 'kg',
                              p_reason text default 'La necesito para una receta', p_group uuid default pg_temp.u(1))
returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select (r ->> ''result'') from catalog.quick_ingredient(%L, %L, %L, %L, %L) r',
    p_group, p_name, p_cat, p_unit, p_reason))
$$;
create function pg_temp.denials() returns int language sql as $$
  select count(*)::int from audit.authentication_security_events where event_type = 'operation_denied' and operation = 'catalog.quick_ingredient'
$$;

-- El permiso.
select is((select array_agg(r.code order by r.code) from core.role_permissions rp join core.roles r on r.id = rp.role_id
             join core.permissions p on p.id = rp.permission_id
            where p.code = 'catalog.create_ingredients' and rp.deleted_at is null),
  array['brand_director', 'executive_chef', 'purchasing', 'superadmin'],
  'lo tienen Compras, el Superadministrador, el Chef Ejecutivo y, por la regla G2, la Directora de Marca');

-- Quién crea.
select is(pg_temp.quick(413, 'Panceta de prueba'), 'applied', 'el Chef Ejecutivo crea');
select is(pg_temp.quick(408, 'Panceta de compras'), 'applied', 'Compras crea');
select is(pg_temp.quick(401, 'Panceta de sistema'), 'applied', 'el Superadministrador crea');
select is(pg_temp.quick(405, 'No'), 'denied', 'la chef de una marca, no');
select is(pg_temp.quick(403, 'No'), 'denied', 'la directora de marca lo tiene, pero se pide para todo el grupo: no');
select is(pg_temp.quick(404, 'No'), 'denied', 'el gerente, no');
select is(pg_temp.quick(406, 'No'), 'denied', 'el jefe de cocina, no');
select is(pg_temp.quick(409, 'No'), 'denied', 'la cocinera, no');
select is(pg_temp.quick(402, 'No'), 'denied', 'Dirección, no');
select is(pg_temp.quick(410, 'No'), 'denied', 'el auditor, no');
select is(pg_temp.denials(), 7, 'cada rechazo queda registrado');
select is((select count(*)::int from catalog.ingredients where name = 'No'), 0, 'y no se creó nada');

-- Con qué: nombre, rubro que va a recetas y unidad. Sin precio ni producto.
select is((select u.code from catalog.ingredients i join catalog.units u on u.id = i.recipe_unit_id where i.name = 'Panceta de prueba'), 'g',
  'se usa en la base de la unidad elegida');
select ok((select code like 'MPR-CAR-%' from catalog.ingredients where name = 'Panceta de prueba'), 'con su código automático');
select is((select count(*)::int from catalog.purchase_products p join catalog.ingredients i on i.id = p.ingredient_id where i.name = 'Panceta de prueba'), 0,
  'sin producto de compra');
select is(pg_temp.quick(413, 'Cajas de prueba', pg_temp.cat('Descartables y packaging')), 'ERROR Elegí un rubro que vaya a recetas.', 'un rubro que no va a recetas, no');
select matches(pg_temp.q(pg_temp.u(413), format('select catalog.create_ingredient(%L, ''Cajas'', %L, ''kg'', ''{}'', ''Prueba'')::text', pg_temp.u(1), pg_temp.cat('Descartables y packaging'))),
  '^ERROR No tenés permiso', 'ni por la función de siempre');
select matches(pg_temp.q(pg_temp.u(413), format('select catalog.create_ingredient(%L, ''Con datos'', %L, ''kg'', ''{"notes": "x"}'', ''Prueba'')::text', pg_temp.u(1), pg_temp.cat('Carnes'))),
  '^ERROR No tenés permiso', 'con datos extra, no');
select matches(pg_temp.q(pg_temp.u(413), format('select catalog.create_ingredient(%L, %L, %L, ''kg'', ''{}'', ''Prueba'')::text', pg_temp.u(1), U&'<b>Pan</b>\200B', pg_temp.cat('Carnes'))),
  'caracteres que no se ven', 'con el nombre sucio, no, tampoco por la función de siempre');
select matches(pg_temp.q(pg_temp.u(413), format('select catalog.create_ingredient(%L, ''Corto'', %L, ''kg'', ''{}'', ''x'')::text', pg_temp.u(1), pg_temp.cat('Carnes'))),
  'Escribí el motivo', 'ni con un motivo de una letra');
select is(pg_temp.quick(413, '  Ternera   nalga de prueba '), 'applied', 'con espacios de más');
select is((select count(*)::int from catalog.ingredients where name = 'Ternera nalga de prueba'), 1, 'entra limpio');
select is(pg_temp.quick(413, 'Panceta de prueba'), 'ERROR Ya existe una materia prima con ese nombre en el grupo.', 'repetida, no');
select matches(pg_temp.quick(413, '<b>Panceta</b>'), 'caracteres que no se ven', 'con < o >, no');
select matches(pg_temp.quick(413, U&'Pan\200Bceta'), 'caracteres que no se ven', 'con caracteres ocultos, no');
select is(pg_temp.quick(413, '   '), 'ERROR Escribí el nombre de la materia prima.', 'sin nombre, no');
select is(pg_temp.quick(413, 'Sin motivo', p_reason => ''), 'ERROR Escribí el motivo (de 3 a 500 caracteres).', 'sin motivo, no');
select is(pg_temp.quick(413, 'En caja', p_unit => 'box'), 'ERROR Elegí una medida de peso, de volumen o de cantidad.', 'en un envase, no');
insert into org.groups (id, name) values (pg_temp.u(60001), 'Otro grupo');
select is(pg_temp.quick(413, 'Ajena', p_group => pg_temp.u(60001)), 'denied', 'en otro grupo, no');
-- El Chef Ejecutivo no la edita después: eso es de Compras.
select matches(pg_temp.q(pg_temp.u(413), format('select catalog.set_ingredient_active(%L, false, ''Prueba'')::text', (select id from catalog.ingredients where name = 'Panceta de prueba'))),
  'ERROR|denied', 'crear no es editar');

-- El aviso.
select is((select array_agg(n.recipient_user_id order by n.recipient_user_id) from core.notifications n where n.kind = 'ingredient_created'),
  array[pg_temp.u(401), pg_temp.u(401), pg_temp.u(408), pg_temp.u(408)], 'cada alta de la cocina avisa a quienes administran el catálogo, y los de Compras no avisan');
select matches((select body from core.notifications where kind = 'ingredient_created' and title like '%Panceta de prueba%' limit 1), '^La creó Gabriel Chef Grupo desde una receta \(MPR-CAR-', 'con quién y su código');
select is((select title from core.notifications where kind = 'ingredient_created' and title like '%Panceta de prueba%' limit 1),
  'Materia prima nueva: «Panceta de prueba»', 'con el nombre entre comillas');
select is((select link from core.notifications where kind = 'ingredient_created' and title like '%Panceta de prueba%' limit 1),
  '/materias-primas/' || (select id from catalog.ingredients where name = 'Panceta de prueba'), 'y el enlace a su ficha');
select ok(exists (select 1 from audit.audit_events where table_schema = 'catalog' and table_name = 'ingredients' and action = 'insert'
                    and actor_user_id = pg_temp.u(413) and reason = 'La necesito para una receta'), 'queda en la auditoría');

-- «¿Es esta?»
select is(pg_temp.q(pg_temp.u(413), format('select string_agg(name, '','') from catalog.similar_ingredients(%L, ''ACEITE DE ÓLIVA'')', pg_temp.u(1)))
  like 'Aceite de oliva%', true, 'encuentra la misma sin tildes ni mayúsculas');
select is(pg_temp.q(pg_temp.u(413), format('select count(*)::text from catalog.similar_ingredients(%L, ''Xilofón'')', pg_temp.u(1))), '0', 'sin parecidas, nada');
select is(pg_temp.q(pg_temp.u(409), format('select count(*)::text from catalog.similar_ingredients(%L, ''Aceite de oliva'')', pg_temp.u(1))), '0',
  'quien no ve el catálogo no las ve');
select is(pg_temp.q(pg_temp.u(413), format('select count(*)::text from catalog.similar_ingredients(%L, repeat(''aceite de oliva '', 60000))', pg_temp.u(1))), '0',
  'un texto enorme ni se busca');

-- El tope por hora (cada alta avisa a Compras).
select is((select count(*)::int from generate_series(1, 28) n where pg_temp.quick(413, 'Tope de prueba ' || n) = 'applied'), 28, 'hasta 30 por hora');
select matches(pg_temp.quick(413, 'Tope de prueba 29'), 'muchas materias primas', 'más, no');
select is(pg_temp.quick(408, 'Compras sin tope'), 'applied', 'Compras no tiene tope');

select * from finish();
rollback;
