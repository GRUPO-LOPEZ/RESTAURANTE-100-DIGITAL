-- Códigos automáticos de marca (01-RAGU) y de local (RAGU-001), nombre corto y zona (Tanda 1 de Soy, ADR-0061).
-- Personas del seed: ...0401 superadministrador, ...0402 Dirección General (sin org.manage), ...0403 directora de
-- Demo Pastas (...101), ...0404 gerente de ...201, ...0409 cocinera. Marcas: ...101 PASTAS, ...102 PARRILLA,
-- ...103 CAFE (números 1 a 3). Locales con código: ...201 PCE, ...202 PNO, ...203 PAR; ...204 sin código.
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists pgrowlocks with schema extensions;
set search_path = extensions, public;

select plan(38);

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
create function pg_temp.u(p_n int) returns uuid language sql as $$
  select format('00000000-0000-4000-8000-%s', lpad(p_n::text, 12, '0'))::uuid
$$;
create temporary table made (k text primary key, id uuid);

-- Lo de antes: los números por orden de alta y los códigos que ya existían, intactos.
select is((select string_agg(number || ':' || code, ',' order by number) from org.brands where group_id = pg_temp.u(1)),
  '1:PASTAS,2:PARRILLA,3:CAFE', 'las marcas del seed tienen su número y conservan su código');
select is((select string_agg(coalesce(code, '-'), ',' order by id) from org.restaurants where group_id = pg_temp.u(1)),
  'PCE,PNO,PAR,-', 'los locales conservan su código (PCE sigue: lo usan las OC) y el que no tenía sigue sin código');
select is((select string_agg(number::text, ',' order by id) from org.restaurants where group_id = pg_temp.u(1)),
  '1,2,1,1', 'cada local tiene su número dentro de su marca');
select is((select count(*)::int from org.restaurants where group_id = pg_temp.u(1) and name = org.restaurant_name(
             (select short_name from org.brands b where b.id = brand_id), zone)), 4,
  'con su zona, el nombre de cada local es el nombre corto de la marca y la zona');

-- La palabra del código, como en lib/org-codes.ts.
select is(org.code_word('  Ragú Bodegón! '), 'RAGUBODEGON', 'la palabra va en mayúsculas, sin tildes ni espacios');
select is(org.brand_code(10, 'Ñandú'), '10-NANDU', 'el número de la marca va con dos cifras');
select is(org.restaurant_code('01-RAGU', 1) || ' ' || org.restaurant_code('PASTAS', 12), 'RAGU-001 PASTAS-012',
  'el local usa la palabra de la marca sin su número, o el código viejo entero');

-- Vista previa sin consumir el número, solo para quien puede crear.
select is(pg_temp.q(pg_temp.u(401), format('select org.peek_brand_code(%L, ''Casa Sushi'')', pg_temp.u(1))),
  '04-CASASUSHI', 'la vista previa muestra el código de la marca nueva');
select is(pg_temp.q(pg_temp.u(403), format('select coalesce(org.peek_brand_code(%L, ''Sushi''), ''nada'')', pg_temp.u(1))),
  'nada', 'quien no crea marcas no ve la vista previa');

-- Alta de marca.
insert into made select 'nonnos', pg_temp.q(pg_temp.u(401), format(
  'select org.create_brand(%L, ''Casa Nonnos'', ''Nonnos'', null, ''Marca nueva de prueba'')::text', pg_temp.u(1)))::uuid;
select is((select number || ' ' || code || ' ' || short_name from org.brands where id = (select id from made where k = 'nonnos')),
  '4 04-NONNOS Nonnos', 'la marca nueva sigue con el 4 y su código sale del nombre corto');
insert into made select 'sushi', pg_temp.q(pg_temp.u(401), format(
  'select org.create_brand(%L, ''Sushi del Río'', ''Sushi'', ''sr'', ''Marca nueva de prueba'')::text', pg_temp.u(1)))::uuid;
select is((select code from org.brands where id = (select id from made where k = 'sushi')), '05-SR',
  'la palabra del código se puede corregir al crearla');
select is(pg_temp.q(pg_temp.u(401), format('select org.create_brand(%L, ''X'', ''X'', null, ''Prueba'')::text', pg_temp.u(1))),
  'ERROR El código necesita al menos dos letras o números.', 'una palabra de una letra no alcanza');
select is(pg_temp.q(pg_temp.u(403), format('select org.create_brand(%L, ''Otra'', ''Otra'', null, ''Prueba'')::text', pg_temp.u(1))),
  'ERROR No tenés permiso para crear marcas en este grupo.', 'la Directora de Marca no crea marcas');
select is(pg_temp.q(pg_temp.u(402), format('select org.create_brand(%L, ''Otra'', ''Otra'', null, ''Prueba'')::text', pg_temp.u(1))),
  'ERROR No tenés permiso para crear marcas en este grupo.', 'Dirección General tampoco (no tiene org.manage)');
select ok(exists (select 1 from audit.audit_events where table_name = 'brands' and record_id = (select id from made where k = 'nonnos')
                    and reason = 'Marca nueva de prueba'), 'el alta de la marca queda en la auditoría con su motivo');

-- El código de la marca no cambia: ni por la función ni directo.
select is(pg_temp.q(pg_temp.u(401), format('select org.update_brand(%L, ''{"code": "NONO"}'', ''Prueba'')::text',
                                           (select id from made where k = 'nonnos'))),
  'ERROR El código de la marca no cambia.', 'la función no cambia el código de una marca');
select throws_ok(format('update org.brands set code = ''XX'' where id = %L', pg_temp.u(101)), '23514',
  'El código de la marca no cambia.', 'ni siquiera directo en la tabla');
select throws_ok(format('update org.brands set number = 9 where id = %L', pg_temp.u(101)), '23514',
  'El número de la marca no cambia.', 'el número de la marca tampoco');

-- Alta de local: marca, zona y tipo. El nombre y el código los pone la base.
select is(pg_temp.q(pg_temp.u(403), format('select org.peek_restaurant(%L, ''Sur'')::text', pg_temp.u(101))),
  '{"code": "PASTAS-003", "name": "Demo Pastas Sur", "number": 3}', 'la vista previa del local muestra su nombre y su código');
insert into made select 'sur', pg_temp.q(pg_temp.u(403), format(
  'select org.create_restaurant(%L, ''Sur'', ''restaurant'', ''Local nuevo de prueba'')::text', pg_temp.u(101)))::uuid;
select is((select number || ' ' || code || ' ' || name || ' ' || opening || ' ' || status from org.restaurants
            where id = (select id from made where k = 'sur')),
  '3 PASTAS-003 Demo Pastas Sur true active', 'el local nuevo sigue con el 3, se arma solo y nace En apertura');
insert into made select 'leloir', pg_temp.q(pg_temp.u(401), format(
  'select org.create_restaurant(%L, ''Leloir'', ''restaurant'', ''Local nuevo de prueba'')::text',
  (select id from made where k = 'nonnos')))::uuid;
select is((select code || ' ' || name from org.restaurants where id = (select id from made where k = 'leloir')),
  'NONNOS-001 Nonnos Leloir', 'en una marca nueva, el primer local es el 001');
select is(pg_temp.q(pg_temp.u(403), format('select org.create_restaurant(%L, ''sur'', ''restaurant'', ''Prueba'')::text',
                                           pg_temp.u(101))),
  'ERROR Ya hay un local «Demo Pastas sur» en esta marca.', 'no se repite el nombre de un local en la marca');
select is(pg_temp.q(pg_temp.u(403), format('select org.create_restaurant(%L, ''  '', ''restaurant'', ''Prueba'')::text',
                                           pg_temp.u(101))),
  'ERROR Escribí la zona o ubicación del local.', 'sin zona no hay alta');

-- El código del local no cambia; uno que faltaba sí se asigna.
select throws_ok(format('update org.restaurants set code = ''XYZ'' where id = %L', pg_temp.u(201)), '23514',
  'El código del local no cambia: lo usan el historial y las órdenes de compra.', 'el código PCE no cambia');
select is(pg_temp.q(pg_temp.u(401), format('select org.update_restaurant(%L, ''{"code": "CAF"}'', ''Código que faltaba'')::text',
                                           pg_temp.u(204))), '', 'a un local sin código se le puede asignar uno');
select throws_ok(format('update org.restaurants set number = 7 where id = %L', pg_temp.u(201)), '23514',
  'El número del local no cambia.', 'el número del local no cambia');
-- Ni pasando por vacío (revisión de db-reviewer, G1): ni directo ni con la función, ni el Gerente ni el Superadministrador.
select throws_ok(format('update org.restaurants set code = null where id = %L', pg_temp.u(201)), '23514',
  'El código del local no cambia: lo usan el historial y las órdenes de compra.', 'el código no se vacía');
select is(pg_temp.q(pg_temp.u(404), format('select org.update_restaurant(%L, ''{"code": ""}'', ''Prueba'')::text', pg_temp.u(201))),
  'ERROR El código del local no cambia: lo usan el historial y las órdenes de compra.',
  'el Gerente no vacía el código de su local para ponerle otro');
select is(pg_temp.q(pg_temp.u(401), format('select org.update_restaurant(%L, ''{"code": "OTRO"}'', ''Prueba'')::text', pg_temp.u(204))),
  'ERROR El código del local no cambia: lo usan el historial y las órdenes de compra.',
  'un código asignado ya no se cambia');

-- La palabra del código no se repite en el grupo (revisión de db-reviewer, G2): si no, dos marcas armarían los mismos
-- códigos de local. Cuenta también la de los códigos de antes (PASTAS).
select is(pg_temp.q(pg_temp.u(401), format('select org.create_brand(%L, ''Otra Nonnos'', ''Nonnos'', null, ''Prueba'')::text', pg_temp.u(1))),
  'ERROR Ya hay una marca con la palabra NONNOS en el código: elegí otra.', 'otra marca con la palabra NONNOS se rechaza');
select is(pg_temp.q(pg_temp.u(401), format('select org.create_brand(%L, ''Pastas Nuevas'', ''Pastas'', null, ''Prueba'')::text', pg_temp.u(1))),
  'ERROR Ya hay una marca con la palabra PASTAS en el código: elegí otra.', 'y la de un código de antes también');
select throws_ok(format('update org.brands set code = ''NUEVA-ABCDEF12'' where id = %L', pg_temp.u(102)), '23514',
  'El código de la marca no cambia.', 'el valor provisorio del alta no sirve para cambiar el código de una marca');

-- El nombre lo arma la base: si cambia la zona o el nombre corto de la marca, cambia el nombre; el código, no.
update org.restaurants set zone = 'Microcentro' where id = pg_temp.u(201);
select is((select name || ' ' || code from org.restaurants where id = pg_temp.u(201)), 'Demo Pastas Microcentro PCE',
  'si el local se muda, cambia la zona y el nombre; el código, no');
select is(pg_temp.q(pg_temp.u(401), format('select org.update_brand(%L, ''{"short_name": "Pastas Demo"}'', ''Nombre corto nuevo'')::text',
                                           pg_temp.u(101))), '', 'se cambia el nombre corto de la marca');
select is((select string_agg(name, ', ' order by number) from org.restaurants where brand_id = pg_temp.u(101)),
  'Pastas Demo Microcentro, Pastas Demo Norte, Pastas Demo Sur', 'sus locales cambian de nombre');
select ok(exists (select 1 from audit.audit_events where table_name = 'restaurants' and record_id = pg_temp.u(202)
                    and reason = 'Nombre corto nuevo' and new_values ->> 'name' = 'Pastas Demo Norte'),
  'y cada cambio de nombre queda en la auditoría con el motivo');

-- Dos altas a la vez: el alta toma la fila de la marca (locales) y la del grupo (marcas) hasta terminar la
-- transacción. Otra alta en la misma marca o grupo espera a que termine y recién ahí toma el número siguiente: no hay
-- números repetidos ni saltos.
select ok(exists (select 1 from extensions.pgrowlocks('org.brands') l
                   where l.locked_row = (select ctid from org.brands where id = pg_temp.u(101))
                     and cardinality(l.modes) > 0),
  'el alta de un local deja tomada su marca hasta el final: otra alta en la misma marca espera');
select ok(exists (select 1 from extensions.pgrowlocks('org.groups') l
                   where l.locked_row = (select ctid from org.groups where id = pg_temp.u(1))
                     and cardinality(l.modes) > 0),
  'el alta de una marca deja tomado su grupo hasta el final: otra alta en el grupo espera');

select * from finish();
rollback;
