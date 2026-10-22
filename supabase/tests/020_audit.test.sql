-- Fase 1 · M2: historial inalterable, trigger genérico de auditoría y sellos.
-- Usa una tabla de práctica (test_fixtures.items) que se descarta con el rollback final.
begin;
create extension if not exists pgtap with schema extensions;

select plan(55);

-- ---------------------------------------------------------------------------
-- Preparación
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_app_meta_data, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'persona@ejemplo.test', '{}', 'authenticated', 'authenticated');

create schema test_fixtures;
create table test_fixtures.items (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid,
  restaurant_id  uuid,
  name           text,
  api_token      text,     -- sensible por nombre
  internal_note  text,     -- sensible por lista de la tabla (argumento del trigger)
  settings       jsonb,    -- puede traer secretos anidados
  created_at     timestamptz,
  created_by     uuid,
  updated_at     timestamptz,
  updated_by     uuid,
  deleted_at     timestamptz,
  deleted_by     uuid
);
create trigger set_control_columns before insert or update on test_fixtures.items
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on test_fixtures.items
  for each row execute function audit.log_change('internal_note');
grant usage on schema test_fixtures to authenticated, service_role;
grant select, insert, update, delete on test_fixtures.items to authenticated, service_role;

create function pg_temp.last_event(p_record uuid)
returns audit.audit_events language sql as $$
  select * from audit.audit_events where record_id = p_record order by sequence_number desc limit 1
$$;
create function pg_temp.events(p_record uuid)
returns int language sql as $$
  select count(*)::int from audit.audit_events where record_id = p_record
$$;

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('audit', 'audit_events', 'existe audit.audit_events');
select ok((select relrowsecurity from pg_class where oid = 'audit.audit_events'::regclass), 'audit_events tiene RLS activado');
select ok((select relrowsecurity from pg_class where oid = 'audit.audit_seals'::regclass), 'audit_seals tiene RLS activado');
select is((select pg_get_userbyid(relowner) from pg_class where oid = 'audit.audit_events'::regclass), 'audit_owner',
  'el dueño de audit_events es audit_owner');
select ok(
  (select prosecdef and pg_get_userbyid(proowner) = 'audit_owner' from pg_proc where oid = 'audit.log_change()'::regprocedure),
  'log_change es security definer y su dueño es audit_owner'
);

-- ---------------------------------------------------------------------------
-- Alta, con motivo y origen
-- ---------------------------------------------------------------------------
do $$ begin perform core.set_change_context('Alta de prueba', 'manual'); end $$;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
set local role authenticated;
insert into test_fixtures.items (id, group_id, restaurant_id, name, api_token, internal_note, settings) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'harina 000', 'tok-123-secreto', 'nota-reservada',
  '{"color": "azul", "nested": {"password": "pw-anidada", "items": [{"api_key": "k-en-lista"}]},
    "session": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.firma", "salt_grams": 12}'
);
reset role;

select is(pg_temp.events('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 1, 'el alta deja un evento');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).action, 'insert'::audit.action, 'la acción es insert');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).actor_user_id, '11111111-1111-1111-1111-111111111111'::uuid, 'registra quién');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).actor_type, 'user'::core.actor_type, 'registra el tipo de actor');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).jwt_role, 'authenticated', 'registra el rol del JWT');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).db_user, session_user::text, 'registra el usuario de la conexión');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).occurred_at, now(), 'registra cuándo');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).reason, 'Alta de prueba', 'registra por qué');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).source, 'manual'::audit.change_origin, 'registra el origen');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).scope_restaurant_id, 'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid, 'registra el restaurante');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).scope_group_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, 'registra el grupo');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).table_name, 'items', 'registra la tabla');
select ok((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).old_values is null, 'en un alta no hay valores anteriores');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values ->> 'name', 'harina 000', 'guarda los valores nuevos');

-- ---------------------------------------------------------------------------
-- Secretos
-- ---------------------------------------------------------------------------
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values ->> 'api_token', '[oculto]', 'una columna sensible por nombre se oculta');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values ->> 'internal_note', '[oculto]', 'una columna excluida por la tabla se oculta');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values #>> '{settings,nested,password}', '[oculto]',
  'un secreto anidado en un jsonb se oculta');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values #>> '{settings,nested,items,0,api_key}', '[oculto]',
  'un secreto dentro de una lista se oculta');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values #>> '{settings,session}', '[oculto]',
  'un valor con forma de JWT se oculta aunque la clave no parezca sensible');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values #>> '{settings,salt_grams}', '12',
  'un dato de cocina (gramos de sal) no se oculta');
select is(
  (select count(*)::int from audit.audit_events
    where coalesce(new_values::text, '') || coalesce(old_values::text, '')
          ~ '(tok-123-secreto|nota-reservada|pw-anidada|k-en-lista|eyJhbGci)'),
  0,
  'ningún secreto aparece en la auditoría'
);

-- ---------------------------------------------------------------------------
-- Cambio, cambio vacío, dos cambios en la misma transacción, borrados
-- ---------------------------------------------------------------------------
set local role authenticated;
update test_fixtures.items set name = 'harina 0000', api_token = 'tok-456-secreto';
reset role;
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).action, 'update'::audit.action, 'un cambio queda como update');
select ok('name' = any ((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).changed_fields), 'registra qué columnas cambiaron');
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).old_values ->> 'name', 'harina 000', 'guarda el valor anterior');
select ok(
  (select count(*) = 0 from audit.audit_events where new_values::text like '%tok-456%' or old_values::text like '%tok-456%'),
  'el secreto nuevo tampoco aparece'
);

set local role authenticated;
update test_fixtures.items set name = name;
reset role;
select is(pg_temp.events('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 2, 'un cambio que no cambia nada no se registra');

set local role authenticated;
update test_fixtures.items set name = 'harina 0001';
update test_fixtures.items set name = 'harina 0002';
reset role;
select is(
  (select array_agg(new_values ->> 'name' order by sequence_number) from audit.audit_events
    where record_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and action = 'update'),
  array['harina 0000', 'harina 0001', 'harina 0002'],
  'dos cambios en la misma transacción quedan como dos eventos, en orden'
);

set local role authenticated;
update test_fixtures.items set deleted_at = now();
reset role;
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).action, 'soft_delete'::audit.action, 'el borrado lógico queda como soft_delete');

set local role authenticated;
update test_fixtures.items set deleted_at = null;
reset role;
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).action, 'restore'::audit.action, 'la restauración queda como restore');

delete from test_fixtures.items where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select is((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).action, 'delete'::audit.action, 'el borrado físico queda como delete');
select ok((pg_temp.last_event('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')).new_values is null, 'en un borrado físico no hay valores nuevos');

-- ---------------------------------------------------------------------------
-- Sin contexto, actor desconocido, motivo y origen cargados a mano
-- ---------------------------------------------------------------------------
set local app.change_reason to '';
set local app.change_source to '';
set local request.jwt.claims to '{"sub": "99999999-9999-9999-9999-999999999999", "role": "authenticated"}';
insert into test_fixtures.items (id, name) values ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'sin actor');
select ok(
  (pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).actor_user_id is null
  and (pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).actor_subject = '99999999-9999-9999-9999-999999999999',
  'si el actor no está registrado, se guarda su identificador igual'
);
select ok(
  (pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).reason is null
  and (pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).source is null,
  'sin contexto, motivo y origen quedan vacíos'
);
select ok(
  (pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).scope_group_id is null
  and (pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).scope_restaurant_id is null,
  'una fila sin grupo ni restaurante deja el alcance vacío'
);

do $$ begin perform set_config('app.change_reason', repeat('m', 2000), true); end $$;
set local app.change_source to 'inventado';
update test_fixtures.items set name = 'con motivo largo' where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd';
select is(length((pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).reason), 500,
  'un motivo cargado a mano se recorta a 500 caracteres');
select ok((pg_temp.last_event('dddddddd-dddd-dddd-dddd-dddddddddddd')).source is null,
  'un origen inválido cargado a mano queda vacío, sin romper el cambio');

-- ---------------------------------------------------------------------------
-- Clave de servidor: el origen es obligatorio
-- ---------------------------------------------------------------------------
set local app.change_reason to '';
set local app.change_source to '';
set local request.jwt.claims to '{"role": "service_role"}';
set local role service_role;
select throws_ok(
  $$insert into test_fixtures.items (name) values ('sin origen')$$,
  '42501', null, 'un cambio con la clave de servidor sin origen se rechaza'
);
reset role;
do $$ begin perform core.set_change_context('Invitación de usuario', 'edge_function'); end $$;
set local role service_role;
insert into test_fixtures.items (id, name) values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'con origen');
reset role;
select ok(
  (pg_temp.last_event('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')).jwt_role = 'service_role'
  and (pg_temp.last_event('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')).source = 'edge_function',
  'con origen declarado, el cambio de servidor queda registrado con su rol'
);

-- ---------------------------------------------------------------------------
-- Conexiones equivocadas del trigger
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
create table test_fixtures.bad (id uuid primary key default gen_random_uuid(), name text);
create trigger log_change_before before insert on test_fixtures.bad
  for each row execute function audit.log_change();
select throws_ok($$insert into test_fixtures.bad (name) values ('x')$$, 'P0001', null,
  'log_change conectado como BEFORE da error en lugar de perder la fila');
drop trigger log_change_before on test_fixtures.bad;
create trigger log_change_typo after insert on test_fixtures.bad
  for each row execute function audit.log_change('pasword');
select throws_ok($$insert into test_fixtures.bad (name) values ('x')$$, 'P0001', null,
  'una columna a ocultar mal escrita da error');

-- ---------------------------------------------------------------------------
-- Inalterable
-- ---------------------------------------------------------------------------
select throws_ok($$update audit.audit_events set reason = 'cambiado'$$, '42501', null, 'nadie puede modificar la auditoría');
select throws_ok($$delete from audit.audit_events$$, '42501', null, 'nadie puede borrar la auditoría');
select throws_ok($$truncate audit.audit_events$$, '42501', null, 'nadie puede vaciar la auditoría');
select throws_ok($$alter table audit.audit_events disable trigger audit_events_no_update_delete$$, '42501', null,
  'postgres no puede desactivar la protección sin ponerse audit_owner a propósito');

set local role authenticated;
select throws_ok($$select * from audit.audit_events$$, '42501', null, 'un usuario autenticado no puede leer la auditoría directamente');
select throws_ok(
  $$insert into audit.audit_events (table_schema, table_name, record_id, action, new_values) values ('x', 'y', gen_random_uuid(), 'insert', '{}')$$,
  '42501', null, 'un usuario autenticado no puede inventar eventos'
);
reset role;

select ok(
  not has_table_privilege('anon', 'audit.audit_events', 'select,insert,update,delete')
  and not has_table_privilege('service_role', 'audit.audit_events', 'select,insert,update,delete'),
  'anon y service_role no tienen ningún permiso sobre la auditoría'
);

-- ---------------------------------------------------------------------------
-- Sellos: detectan cualquier alteración, aunque la haga alguien con la contraseña de postgres
-- ---------------------------------------------------------------------------
-- Las funciones de sellos solo las ejecuta audit_owner: los resultados se guardan en
-- tablas temporales y se comprueban después como postgres.
set local role audit_owner;
create temp table seal_check as select (audit.seal_events(interval '-1 minute')).id as seal_id;
create temp table verify_before as select bool_and(is_valid) as all_valid from audit.verify_seals();

-- Ataque: alguien se pone audit_owner, desactiva la protección y edita un evento.
alter table audit.audit_events disable trigger audit_events_no_update_delete;
update audit.audit_events set reason = 'motivo falsificado'
 where sequence_number = (select min(sequence_number) from audit.audit_events);
alter table audit.audit_events enable trigger audit_events_no_update_delete;
create temp table verify_after as select bool_and(is_valid) as all_valid from audit.verify_seals();
grant select on seal_check, verify_before, verify_after to postgres;
reset role;

select ok((select seal_id is not null from seal_check), 'se puede sellar la auditoría');
select ok((select all_valid from verify_before), 'una auditoría sin tocar verifica bien');
select ok(not (select all_valid from verify_after), 'editar un evento sellado se detecta');

select * from finish();
rollback;
