-- Panel de control de la estructura (ADR-0031): al crear un local se eligen su tipo y su razón social en
-- una sola operación. La razón social pide org.manage de todo el grupo (decisión 8 de ADR-0029).
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
create function pg_temp.create(p_user int, p_name text, p_details jsonb) returns text language sql as $$
  select pg_temp.q(pg_temp.u(p_user), format('select org.create_restaurant(%L, %L, %L, ''Local nuevo de prueba'')::text',
                                             pg_temp.u(101), p_name, p_details))
$$;
create temporary table made (k text primary key, id text);

-- El Superadministrador crea un local con su tipo y su razón social, en un paso.
insert into made values ('super', pg_temp.create(401, 'Demo Pastas Sur',
  jsonb_build_object('code', 'pas-sur', 'site_type', 'central_kitchen', 'legal_entity_id', pg_temp.u(1501))));
select ok((select id from made where k = 'super') ~ '^[0-9a-f-]{36}$', 'el Superadministrador crea un local');
select is((select code || '/' || site_type || '/' || legal_entity_id from org.restaurants where id::text = (select id from made where k = 'super')),
  'PAS-SUR/central_kitchen/' || pg_temp.u(1501), 'con su código, su tipo y su razón social en la misma operación');
select ok(exists (select 1 from audit.audit_events where table_name = 'restaurants' and action::text = 'insert'
                    and record_id::text = (select id from made where k = 'super') and reason = 'Local nuevo de prueba'),
  'el alta queda en la auditoría con su motivo');

-- La Directora de Marca crea locales de su marca, pero no elige la razón social.
insert into made values ('director', pg_temp.create(403, 'Demo Pastas Oeste', '{}'));
select ok((select id from made where k = 'director') ~ '^[0-9a-f-]{36}$', 'la Directora crea un local de su marca');
select is((select coalesce(legal_entity_id::text, '-') || '/' || site_type from org.restaurants
             where id::text = (select id from made where k = 'director')), '-/restaurant',
  'sin razón social (su costo sin IVA queda incompleto hasta que se elija) y, sin decir el tipo, es un restaurante');
select is(pg_temp.create(403, 'Demo Pastas Este', jsonb_build_object('legal_entity_id', pg_temp.u(1501))),
  'ERROR No tenés permiso para elegir la razón social de este local.',
  'la Directora no elige la razón social: cambia el IVA del costo');
select is((select count(*)::int from audit.audit_events where table_name = 'restaurants' and new_values ->> 'name' = 'Demo Pastas Este'), 0,
  'y no queda nada registrado de ese intento como alta');

-- Una razón social de otro grupo o dada de baja no se elige.
insert into org.groups (id, name) values (pg_temp.u(9001), 'Otro grupo de prueba');
insert into org.legal_entities (id, group_id, name, tax_id, vat_condition)
values (pg_temp.u(9002), pg_temp.u(9001), 'Ajena S.A. (ficticia)', '30999999991', 'registered');
select is(pg_temp.create(401, 'Demo Pastas Ajena', jsonb_build_object('legal_entity_id', pg_temp.u(9002))),
  'ERROR Elegí una razón social vigente del grupo.', 'una razón social de otro grupo se rechaza');
update org.legal_entities set deleted_at = now() where id = pg_temp.u(1502);
select is(pg_temp.create(401, 'Demo Pastas Baja', jsonb_build_object('legal_entity_id', pg_temp.u(1502))),
  'ERROR Elegí una razón social vigente del grupo.', 'una razón social dada de baja también');

-- Un formulario con la fecha de apertura vacía no rompe el alta.
select ok(pg_temp.create(401, 'Demo Pastas Sin Fecha', '{"opened_on": "", "code": "", "phone": ""}') ~ '^[0-9a-f-]{36}$',
  'una fecha de apertura vacía queda vacía y el local se crea');

-- Datos mal formados: un mensaje en español, no el error crudo de la conversión.
select is(pg_temp.create(401, 'Demo Pastas Raro', '{"site_type": "bar"}'), 'ERROR Elegí el tipo de local.',
  'un tipo que no existe se rechaza con un mensaje claro');
select is(pg_temp.create(401, 'Demo Pastas Raro', '{"legal_entity_id": "no-es-un-id"}'), 'ERROR Elegí una razón social vigente del grupo.',
  'una razón social mal escrita también');

-- El Gerente administra su local, pero no crea locales en la marca.
select is(pg_temp.create(404, 'Demo Pastas del Gerente', '{}'), 'ERROR No tenés permiso para crear locales en esta marca.',
  'el Gerente no crea locales');

-- La Cocinera no crea locales.
select is(pg_temp.create(409, 'Demo Pastas Cocina', '{}'), 'ERROR No tenés permiso para crear locales en esta marca.',
  'la Cocinera no crea locales');

select * from finish();
rollback;
