-- Fase 1 · M1: actores, columnas de control, contexto del cambio y privilegios por defecto.
-- Usa una tabla de práctica (test_fixtures.items) que se descarta con el rollback final.
begin;
create extension if not exists pgtap with schema extensions;

select plan(42);

-- ---------------------------------------------------------------------------
-- Preparación: dos usuarios de Auth (persona y cuenta técnica) y la tabla de práctica.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_app_meta_data, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'persona@ejemplo.test', '{}', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'agente@ejemplo.test', '{"actor_type": "service_account"}', 'authenticated', 'authenticated');

create schema test_fixtures;
create table test_fixtures.items (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  created_at  timestamptz,
  created_by  uuid,
  updated_at  timestamptz,
  updated_by  uuid,
  deleted_at  timestamptz,
  deleted_by  uuid
);
create trigger set_control_columns before insert or update on test_fixtures.items
  for each row execute function core.set_control_columns();
grant usage on schema test_fixtures to authenticated;
grant select, insert, update on test_fixtures.items to authenticated;

-- ---------------------------------------------------------------------------
-- Rol dueño de la auditoría
-- ---------------------------------------------------------------------------
select ok(not (select rolcanlogin from pg_roles where rolname = 'audit_owner'), 'audit_owner no puede iniciar sesión');
select ok(
  (select bool_and(not inherit_option) and bool_or(set_option) from pg_auth_members
    where roleid = 'audit_owner'::regrole and member = 'postgres'::regrole),
  'postgres puede ponerse audit_owner, pero no lo hereda'
);

-- ---------------------------------------------------------------------------
-- Actores
-- ---------------------------------------------------------------------------
select has_table('core', 'actors', 'existe core.actors');
select ok((select relrowsecurity from pg_class where oid = 'core.actors'::regclass), 'core.actors tiene RLS activado');
select is(
  (select actor_type from core.actors where id = '11111111-1111-1111-1111-111111111111'),
  'user'::core.actor_type,
  'crear un usuario en Auth crea su actor de tipo persona'
);
select is(
  (select actor_type from core.actors where id = '22222222-2222-2222-2222-222222222222'),
  'service_account'::core.actor_type,
  'con actor_type en app_metadata, el actor queda como cuenta técnica'
);
select ok(not has_table_privilege(r, 'core.actors', 'select'), format('%s no puede leer core.actors', r))
from unnest(array['anon', 'authenticated', 'service_role']) as r;

-- user_metadata lo escribe el propio usuario: nunca puede volverlo cuenta técnica.
-- (El alta hecha por GoTrue con su rol supabase_auth_admin se verificó a mano en la revisión.)
insert into auth.users (id, email, raw_app_meta_data, raw_user_meta_data, aud, role) values
  ('33333333-3333-3333-3333-333333333333', 'usuario@ejemplo.test', '{}', '{"actor_type": "service_account"}', 'authenticated', 'authenticated');
select is(
  (select actor_type from core.actors where id = '33333333-3333-3333-3333-333333333333'),
  'user'::core.actor_type,
  'poner actor_type en user_metadata no vuelve a nadie cuenta técnica'
);

-- ---------------------------------------------------------------------------
-- Actor de la sesión
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '';
select is(core.current_actor_id(), null, 'sin sesión no hay actor');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(core.current_actor_id(), '11111111-1111-1111-1111-111111111111'::uuid, 'el actor sale del sub del JWT');

set local request.jwt.claim.sub to '22222222-2222-2222-2222-222222222222';
select is(core.current_actor_id(), '11111111-1111-1111-1111-111111111111'::uuid,
  'pisar el GUC heredado request.jwt.claim.sub no cambia el actor');

set local request.jwt.claims to '{"sub": "user_2abc", "role": "authenticated"}';
select is(core.current_actor_id(), null, 'un sub que no es uuid deja el actor nulo, sin romper');
select is(core.current_actor_subject(), 'user_2abc', 'pero el sub queda disponible tal cual');

-- ---------------------------------------------------------------------------
-- Columnas de control (como usuario autenticado)
-- ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
set local role authenticated;

insert into test_fixtures.items (id, name, created_at, created_by, updated_by, deleted_at, deleted_by)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'primero', '2000-01-01', '22222222-2222-2222-2222-222222222222',
  '22222222-2222-2222-2222-222222222222', '2000-01-01', '22222222-2222-2222-2222-222222222222'
);

select is((select created_by from test_fixtures.items), '11111111-1111-1111-1111-111111111111'::uuid,
  'created_by lo pone la base, aunque la app mande otro');
select is((select created_at from test_fixtures.items), now(), 'created_at lo pone la base');
select is((select updated_by from test_fixtures.items), '11111111-1111-1111-1111-111111111111'::uuid, 'updated_by lo pone la base');
select ok((select deleted_at is null and deleted_by is null from test_fixtures.items), 'un registro nuevo nunca nace borrado');

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
update test_fixtures.items set name = name;
select is((select updated_by from test_fixtures.items), '11111111-1111-1111-1111-111111111111'::uuid,
  'un cambio que no cambia nada no toca la fila (ni updated_by)');

update test_fixtures.items set name = 'cambiado';
select is((select updated_by from test_fixtures.items), '22222222-2222-2222-2222-222222222222'::uuid, 'un cambio registra quién lo hizo');
select is((select created_by from test_fixtures.items), '11111111-1111-1111-1111-111111111111'::uuid, 'un cambio no toca quién lo creó');

select throws_ok(
  $$update test_fixtures.items set created_by = '22222222-2222-2222-2222-222222222222'$$,
  '42501', null, 'no se puede cambiar created_by'
);
select throws_ok($$update test_fixtures.items set created_at = '2001-01-01'$$, '42501', null, 'no se puede cambiar created_at');
select throws_ok($$update test_fixtures.items set id = gen_random_uuid()$$, '42501', null, 'no se puede cambiar el id');

update test_fixtures.items set deleted_at = '1999-01-01', deleted_by = '11111111-1111-1111-1111-111111111111';
select is((select deleted_by from test_fixtures.items), '22222222-2222-2222-2222-222222222222'::uuid,
  'el borrado lógico registra quién borró, aunque la app mande otro');
select is((select deleted_at from test_fixtures.items), now(), 'el borrado lógico usa la hora de la base');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
update test_fixtures.items set deleted_at = '1990-01-01', deleted_by = '11111111-1111-1111-1111-111111111111';
select ok(
  (select deleted_at = now() and deleted_by = '22222222-2222-2222-2222-222222222222' from test_fixtures.items),
  'sobre algo ya borrado no se puede cambiar quién ni cuándo se borró'
);

update test_fixtures.items set deleted_at = null;
select ok((select deleted_at is null and deleted_by is null from test_fixtures.items), 'restaurar vacía quién y cuándo se borró');

reset role;

-- Conexión equivocada del trigger
create table test_fixtures.wrong_wiring (
  id uuid primary key default gen_random_uuid(), name text,
  created_at timestamptz, created_by uuid, updated_at timestamptz, updated_by uuid, deleted_at timestamptz, deleted_by uuid
);
create trigger set_control_columns after insert on test_fixtures.wrong_wiring
  for each row execute function core.set_control_columns();
select throws_ok($$insert into test_fixtures.wrong_wiring (name) values ('x')$$, 'P0001', null,
  'set_control_columns conectado como AFTER da error en lugar de fallar en silencio');

-- ---------------------------------------------------------------------------
-- Contexto del cambio
-- ---------------------------------------------------------------------------
select throws_ok($$select core.set_change_context('', 'app')$$, '22023', null, 'el motivo vacío se rechaza');
select throws_ok($$select core.set_change_context(repeat('x', 501), 'app')$$, '22023', null, 'un motivo de más de 500 caracteres se rechaza');
select throws_ok($$select core.set_change_context('Motivo', 'cualquiera')$$, '22023', null, 'un origen fuera de la lista se rechaza');
select lives_ok($$select core.set_change_context('Prueba de motivo', 'maintenance')$$, 'un motivo válido se acepta');
select is(current_setting('app.reason', true), 'Prueba de motivo', 'el motivo queda en la transacción');

-- ---------------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------------
select is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
                        'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting')
      and (
        p.proacl is null
        or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
      )
  ),
  0,
  'ninguna función de los esquemas de negocio es ejecutable por PUBLIC'
);

-- anon y service_role no tienen permisos sobre funciones, tablas ni secuencias de negocio.
-- authenticated solo lee y llama funciones puntuales (M5, ADR-0005): la lista exacta
-- está en 050_permissions. Cuando se abra algo más, estas pruebas se actualizan a propósito.
select is(
  (
    select count(*)::int
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join unnest(array['anon', 'service_role']) as r
    where n.nspname in ('core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
                        'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting')
      and has_function_privilege(r, p.oid, 'execute')
  ),
  0,
  'anon y service_role no pueden ejecutar ninguna función de negocio'
);
select is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
                        'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting')
      and c.relkind in ('r', 'p', 'v', 'm')
      and has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate,references,trigger')
  ),
  0,
  'authenticated no escribe directo en ninguna tabla de negocio: las escrituras van por funciones'
);
select is(
  (
    select count(*)::int
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join unnest(array['anon', 'service_role']) as r
    where n.nspname in ('core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
                        'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting')
      and c.relkind in ('r', 'p', 'v', 'm', 'S')
      and (
        (c.relkind = 'S' and has_sequence_privilege(r, c.oid, 'usage,select,update'))
        or (c.relkind <> 'S' and has_table_privilege(r, c.oid, 'select,insert,update,delete,truncate,references,trigger'))
      )
  ),
  0,
  'anon y service_role no tienen ningún permiso sobre tablas ni secuencias de negocio'
);

create function core.tmp_new_function() returns int language sql as $$ select 1 $$;
select ok(
  not has_function_privilege('anon', 'core.tmp_new_function()', 'execute')
  and not has_function_privilege('authenticated', 'core.tmp_new_function()', 'execute'),
  'una función nueva nace cerrada (default privileges)'
);

set local role audit_owner;
create function audit.tmp_new_function() returns int language sql as $$ select 1 $$;
reset role;
select ok(
  not has_function_privilege('anon', 'audit.tmp_new_function()', 'execute')
  and not has_function_privilege('authenticated', 'audit.tmp_new_function()', 'execute'),
  'una función nueva de audit_owner también nace cerrada'
);

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('core', 'audit') and p.prosecdef
      and not coalesce(p.proconfig @> array['search_path=""'], false)),
  0,
  'toda función security definer de core y audit tiene search_path vacío'
);

select * from finish();
rollback;
