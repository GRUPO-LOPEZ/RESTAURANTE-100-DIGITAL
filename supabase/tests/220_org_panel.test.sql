-- Panel de control de la estructura (ADR-0031, rehecho en ADR-0061): el alta de local es corta (marca, zona, tipo y
-- motivo) y la razón social se elige en la ficha, con org.manage de todo el grupo (decisión 8 de ADR-0029).
-- Personas del seed: ...0401 superadministrador (grupo), ...0403 directora de Demo Pastas (...101),
-- ...0404 gerente de ...201, ...0409 cocinera. Razón social del seed: ...1501 (responsable inscripta).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(14);

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
create function pg_temp.create(p_user int, p_zone text, p_type text default 'restaurant') returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select org.create_restaurant(%L, %L, %L, ''Local nuevo de prueba'')::text',
                                             pg_temp.u(101), p_zone, p_type))
$$;
-- Elige la razón social desde la ficha, con el sello vigente.
create function pg_temp.entity(p_user int, p_restaurant text, p_entity text) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format(
    'select org.save_restaurant_sheet(%L, %L, %L, ''Razón social de prueba'')::text',
    p_restaurant, org.restaurant_sheet_stamp_internal(p_restaurant::uuid), jsonb_build_object('legal_entity', jsonb_build_object('legal_entity_id', p_entity))))
$$;
create temporary table made (k text primary key, id text);

-- El Superadministrador crea un local con su tipo y después elige su razón social.
insert into made values ('super', pg_temp.create(401, 'Sur', 'central_kitchen'));
select ok((select id from made where k = 'super') ~ '^[0-9a-f-]{36}$', 'el Superadministrador crea un local');
select ok(pg_temp.entity(401, (select id from made where k = 'super'), pg_temp.u(1501)::text) like '{"stamp"%',
  'y elige su razón social en la ficha');
select is((select site_type || '/' || legal_entity_id from org.restaurants where id::text = (select id from made where k = 'super')),
  'central_kitchen/' || pg_temp.u(1501), 'con su tipo y su razón social');
select ok(exists (select 1 from audit.audit_events where table_name = 'restaurants' and action::text = 'insert'
                    and record_id::text = (select id from made where k = 'super') and reason = 'Local nuevo de prueba'),
  'el alta queda en la auditoría con su motivo');

-- La Directora de Marca crea locales de su marca, pero no elige la razón social.
insert into made values ('director', pg_temp.create(403, 'Oeste'));
select ok((select id from made where k = 'director') ~ '^[0-9a-f-]{36}$', 'la Directora crea un local de su marca');
select is((select coalesce(legal_entity_id::text, '-') || '/' || site_type from org.restaurants
             where id::text = (select id from made where k = 'director')), '-/restaurant',
  'sin razón social (su costo sin IVA queda incompleto hasta que se elija) y como restaurante');
select is(pg_temp.entity(403, (select id from made where k = 'director'), pg_temp.u(1501)::text),
  'ERROR No tenés permiso para elegir la razón social de este local.',
  'la Directora no elige la razón social: cambia el IVA del costo');
select is((select legal_entity_id from org.restaurants where id::text = (select id from made where k = 'director')), null,
  'y el local sigue sin razón social');

-- Una razón social de otro grupo o dada de baja no se elige.
insert into org.groups (id, name) values (pg_temp.u(9001), 'Otro grupo de prueba');
insert into org.legal_entities (id, group_id, name, tax_id, vat_condition)
values (pg_temp.u(9002), pg_temp.u(9001), 'Ajena S.A. (ficticia)', '30999999995', 'registered');
select is(pg_temp.entity(401, (select id from made where k = 'director'), pg_temp.u(9002)::text),
  'ERROR Elegí una razón social vigente del grupo.', 'una razón social de otro grupo se rechaza');
update org.legal_entities set deleted_at = now() where id = pg_temp.u(1502);
select is(pg_temp.entity(401, (select id from made where k = 'director'), pg_temp.u(1502)::text),
  'ERROR Elegí una razón social vigente del grupo.', 'una razón social dada de baja también');

-- Datos mal formados: un mensaje en español, no el error crudo de la conversión.
select is(pg_temp.q(pg_temp.u(401), format(
    'select org.save_restaurant_sheet(%L, %L, ''{"restaurant": {"site_type": "bar"}}'', ''Prueba'')::text',
    pg_temp.u(201), org.restaurant_sheet_stamp_internal(pg_temp.u(201)))),
  'ERROR Elegí el tipo de local.', 'un tipo que no existe se rechaza con un mensaje claro');
select is(pg_temp.entity(401, pg_temp.u(201)::text, 'no-es-un-id'),
  'ERROR Elegí una razón social vigente del grupo.', 'una razón social mal escrita también');

-- El Gerente administra su local, pero no crea locales en la marca.
select is(pg_temp.create(404, 'Del Gerente'), 'ERROR No tenés permiso para crear locales en esta marca.',
  'el Gerente no crea locales');

-- La Cocinera no crea locales.
select is(pg_temp.create(409, 'Cocina'), 'ERROR No tenés permiso para crear locales en esta marca.',
  'la Cocinera no crea locales');

select * from finish();
rollback;
