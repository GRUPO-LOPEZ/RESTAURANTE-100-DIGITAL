-- Fase 1 · M3: estructura del grupo (grupos, marcas, restaurantes, áreas) y seed ficticio.
-- Ids del seed: grupo ...001; marcas ...101 (Pastas), ...102 (Parrilla), ...103 (Café);
-- restaurantes ...201 y ...202 (Pastas), ...203 (Parrilla), ...204 (Café); áreas ...03RA.
begin;
create extension if not exists pgtap with schema extensions;

select plan(51);

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
select has_table('org', t, format('existe org.%s', t))
from unnest(array['groups', 'brands', 'restaurants', 'areas']) as t;

select ok((select relrowsecurity from pg_class where oid = format('org.%I', t)::regclass), format('org.%s tiene RLS activado', t))
from unnest(array['groups', 'brands', 'restaurants', 'areas']) as t;

select is(
  (select count(*)::int
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'org' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
      and col_description(c.oid, a.attnum) is null),
  0,
  'todas las columnas de org tienen comentario en español'
);

select is(
  (select count(*)::int
     from unnest(array['groups', 'brands', 'restaurants', 'areas']) as t
    where (select count(*) from pg_trigger g
            where g.tgrelid = format('org.%I', t)::regclass
              and g.tgname in ('set_control_columns', 'validate_hierarchy', 'log_change', 'reject_truncate')
              and g.tgenabled = 'O') = 4),
  4,
  'las 4 tablas tienen activos los triggers de control, jerarquía, auditoría y anti-vaciado'
);

-- ---------------------------------------------------------------------------
-- Seed (prompt maestro, sección 9)
-- ---------------------------------------------------------------------------
select is((select count(*)::int from org.groups), 1, 'el seed tiene 1 grupo');
select is((select count(*)::int from org.brands), 3, 'el seed tiene 3 marcas');
select is((select count(*)::int from org.restaurants), 4, 'el seed tiene 4 restaurantes');
select is((select count(*)::int from org.areas), 12, 'el seed tiene 3 áreas por restaurante');
select is((select name from org.areas where id = '00000000-0000-4000-8000-000000000342'), 'Salón',
  'las áreas del seed tienen ids fijos');
select is(
  (select count(*)::int from audit.audit_events where table_schema = 'org' and source = 'seed'),
  20,
  'cada alta del seed quedó auditada con origen seed'
);

-- ---------------------------------------------------------------------------
-- Alcance consistente por estructura
-- ---------------------------------------------------------------------------
insert into org.groups (id, name) values ('00000000-0000-4000-8000-000000000002', 'Otro Grupo');
insert into org.brands (id, group_id, name, code) values
  ('00000000-0000-4000-8000-000000000199', '00000000-0000-4000-8000-000000000002', 'Marca del otro grupo', 'OTRA');

select throws_ok(
  $$insert into org.restaurants (group_id, brand_id, name)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000199', 'Mezclado')$$,
  '23503', null, 'un restaurante con una marca de otro grupo se rechaza'
);
select throws_ok(
  $$insert into org.areas (group_id, restaurant_id, name)
    values ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000201', 'Barra')$$,
  '23503', null, 'un área con un restaurante de otro grupo se rechaza'
);

-- ---------------------------------------------------------------------------
-- El alcance no se mueve con una edición común (decisión de Joaco)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update org.restaurants set brand_id = '00000000-0000-4000-8000-000000000102'
     where id = '00000000-0000-4000-8000-000000000201'$$,
  '42501', null, 'no se puede mover un restaurante a otra marca con una edición común'
);
select throws_ok(
  $$update org.restaurants set group_id = '00000000-0000-4000-8000-000000000002'
     where id = '00000000-0000-4000-8000-000000000201'$$,
  '42501', null, 'no se puede mover un restaurante a otro grupo'
);
select throws_ok(
  $$update org.brands set group_id = '00000000-0000-4000-8000-000000000002'
     where id = '00000000-0000-4000-8000-000000000101'$$,
  '42501', null, 'no se puede mover una marca a otro grupo'
);
select throws_ok(
  $$update org.areas set restaurant_id = '00000000-0000-4000-8000-000000000202'
     where id = '00000000-0000-4000-8000-000000000311'$$,
  '42501', null, 'no se puede mover un área a otro restaurante'
);
select lives_ok(
  $$update org.restaurants set name = 'Demo Pastas Centro (renovado)'
     where id = '00000000-0000-4000-8000-000000000201'$$,
  'cambiar el nombre de un restaurante sí se permite'
);

-- ---------------------------------------------------------------------------
-- No se borra algo con elementos vigentes adentro (decisión de Joaco)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update org.brands set deleted_at = now() where id = '00000000-0000-4000-8000-000000000101'$$,
  '23514', null, 'no se puede borrar una marca que tiene restaurantes vigentes'
);
select throws_ok(
  $$update org.groups set deleted_at = now() where id = '00000000-0000-4000-8000-000000000001'$$,
  '23514', null, 'no se puede borrar un grupo que tiene marcas vigentes'
);
select throws_ok(
  $$update org.restaurants set deleted_at = now() where id = '00000000-0000-4000-8000-000000000204'$$,
  '23514', null, 'no se puede borrar un restaurante que tiene áreas vigentes'
);

update org.brands set deleted_at = now() where id = '00000000-0000-4000-8000-000000000199';
select ok((select deleted_at is not null from org.brands where id = '00000000-0000-4000-8000-000000000199'),
  'una marca sin restaurantes vigentes sí se puede borrar');
select throws_ok(
  $$insert into org.restaurants (group_id, brand_id, name)
    values ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000199', 'Local nuevo')$$,
  '23514', null, 'no se puede dar de alta un restaurante en una marca borrada'
);
select throws_ok(
  $$insert into org.restaurants (group_id, brand_id, name, deleted_at)
    values ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000199', 'Local truco', now())$$,
  '23514', null, 'mandar un deleted_at falso no saltea la regla'
);

update org.areas set deleted_at = now() where restaurant_id = '00000000-0000-4000-8000-000000000204';
update org.restaurants set deleted_at = now() where id = '00000000-0000-4000-8000-000000000204';
select ok((select deleted_at is not null from org.restaurants where id = '00000000-0000-4000-8000-000000000204'),
  'después de borrar sus áreas, el restaurante sí se puede borrar');
select throws_ok(
  $$update org.areas set deleted_at = null where id = '00000000-0000-4000-8000-000000000341'$$,
  '23514', null, 'no se puede restaurar un área dentro de un restaurante borrado'
);

-- ---------------------------------------------------------------------------
-- Nombres
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into org.brands (group_id, name, code) values ('00000000-0000-4000-8000-000000000001', 'demo PASTAS', 'PASTAS2')$$,
  '23505', null, 'una marca repetida en el mismo grupo se rechaza, aunque cambien las mayúsculas'
);
select lives_ok(
  $$insert into org.brands (group_id, name, code) values ('00000000-0000-4000-8000-000000000002', 'Demo Pastas', 'PASTAS')$$,
  'el mismo nombre de marca en otro grupo se permite'
);
select throws_ok(
  $$insert into org.restaurants (group_id, brand_id, name)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', 'Demo Pastas Norte')$$,
  '23505', null, 'un restaurante repetido en la misma marca se rechaza'
);
select lives_ok(
  $$insert into org.restaurants (group_id, brand_id, name)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000102', 'Demo Pastas Norte')$$,
  'el mismo nombre de restaurante en otra marca se permite (decisión: único por marca)'
);
select throws_ok(
  $$insert into org.areas (group_id, restaurant_id, name)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000201', 'cocina')$$,
  '23505', null, 'un área repetida en el mismo restaurante se rechaza'
);
select throws_ok($$insert into org.groups (name) values ('   ')$$, '23514', null, 'un nombre vacío se rechaza');

update org.areas set deleted_at = now() where id = '00000000-0000-4000-8000-000000000313';
select lives_ok(
  $$insert into org.areas (group_id, restaurant_id, name)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000201', 'Depósito')$$,
  'el nombre de un área borrada se puede volver a usar'
);

-- ---------------------------------------------------------------------------
-- Borrado físico y vaciado protegidos
-- ---------------------------------------------------------------------------
select throws_ok(
  $$delete from org.groups where id = '00000000-0000-4000-8000-000000000001'$$,
  '23503', null, 'no se puede borrar físicamente un grupo que tiene marcas'
);
-- Con cascade no frena ninguna clave foránea: lo frena el trigger.
select throws_ok($$truncate org.areas cascade$$, '42501', null, 'no se puede vaciar una tabla de org');

-- ---------------------------------------------------------------------------
-- Columnas de control y alcance en la auditoría
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_app_meta_data, aud, role) values
  ('11111111-1111-1111-1111-111111111111', 'persona@ejemplo.test', '{}', 'authenticated', 'authenticated');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin perform core.set_change_context('Apertura de local de prueba', 'manual'); end $$;

insert into org.restaurants (id, group_id, brand_id, name) values
  ('00000000-0000-4000-8000-000000000299', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000103', 'Demo Café Sur');

select is(
  (select created_by from org.restaurants where id = '00000000-0000-4000-8000-000000000299'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'el alta de un restaurante registra quién lo creó'
);
select ok(
  (select scope_group_id = '00000000-0000-4000-8000-000000000001'
      and scope_brand_id = '00000000-0000-4000-8000-000000000103'
      and scope_restaurant_id = '00000000-0000-4000-8000-000000000299'
      and reason = 'Apertura de local de prueba'
     from audit.audit_events where record_id = '00000000-0000-4000-8000-000000000299'
    order by sequence_number desc limit 1),
  'el evento de un restaurante tiene su grupo, su marca y el propio restaurante como alcance'
);
select ok(
  (select scope_group_id = '00000000-0000-4000-8000-000000000001'
      and scope_brand_id = '00000000-0000-4000-8000-000000000101'
      and scope_restaurant_id is null
     from audit.audit_events where record_id = '00000000-0000-4000-8000-000000000101'
    order by sequence_number desc limit 1),
  'el evento de una marca tiene la propia marca como alcance'
);
select ok(
  (select scope_group_id = '00000000-0000-4000-8000-000000000001'
     from audit.audit_events where record_id = '00000000-0000-4000-8000-000000000001'
    order by sequence_number desc limit 1),
  'el evento de un grupo tiene el propio grupo como alcance'
);

update org.areas set name = 'Cocina caliente' where id = '00000000-0000-4000-8000-000000000321';
select ok(
  (select action = 'update' and scope_restaurant_id = '00000000-0000-4000-8000-000000000202'
      and scope_brand_id = '00000000-0000-4000-8000-000000000101'
      and scope_group_id = '00000000-0000-4000-8000-000000000001'
     from audit.audit_events where record_id = '00000000-0000-4000-8000-000000000321'
    order by sequence_number desc limit 1),
  'un cambio en un área queda como update, con su restaurante, su marca y su grupo'
);
select is(
  (select action from audit.audit_events where record_id = '00000000-0000-4000-8000-000000000313'
    order by sequence_number desc limit 1),
  'soft_delete'::audit.action,
  'el borrado lógico de un área queda como soft_delete'
);

-- Una tabla fuera de org con un alcance inventado: manda la estructura, no la fila.
create schema test_fixtures;
create table test_fixtures.items (
  id uuid primary key default gen_random_uuid(), group_id uuid, brand_id uuid, restaurant_id uuid
);
create trigger log_change after insert on test_fixtures.items
  for each row execute function audit.log_change();
insert into test_fixtures.items (id, group_id, brand_id, restaurant_id) values (
  'ffffffff-ffff-ffff-ffff-ffffffffffff', '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000201'
);
select ok(
  (select scope_brand_id = '00000000-0000-4000-8000-000000000101'
      and scope_group_id = '00000000-0000-4000-8000-000000000001'
     from audit.audit_events where record_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'),
  'un alcance inventado en la fila no engaña a la auditoría: manda el restaurante real'
);

-- ---------------------------------------------------------------------------
-- Cerradas para la API (hasta M5, ADR-0005)
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::int
     from unnest(array['groups', 'brands', 'restaurants', 'areas']) as t
     cross join unnest(array['anon', 'authenticated', 'service_role']) as r
    where has_table_privilege(r, format('org.%I', t), 'insert,update,delete,truncate,references,trigger')
       or (r <> 'authenticated' and has_table_privilege(r, format('org.%I', t), 'select'))),
  0,
  'en org nadie escribe directo, y solo authenticated lee (M5): anon y service_role no tienen nada'
);
select ok(
  not has_schema_privilege('anon', 'org', 'usage')
  and has_schema_privilege('authenticated', 'org', 'usage')
  and not has_schema_privilege('service_role', 'org', 'usage'),
  'al esquema org entra solo authenticated (M5)'
);
select is(
  (select array_agg(policyname || ':' || cmd order by policyname)::text[]
     from pg_policies where schemaname = 'org' and roles <> '{audit_owner}'),
  array['areas_select:SELECT', 'brands_select:SELECT', 'groups_select:SELECT', 'restaurants_select:SELECT', 'time_zones_select:SELECT'],
  'en org solo hay políticas de lectura (las escrituras van por funciones), más las de la auditoría'
);
select is(
  (select count(*)::int
     from pg_default_acl d
     cross join aclexplode(d.defaclacl) a
    where d.defaclrole = 'postgres'::regrole
      and d.defaclnamespace = 'public'::regnamespace
      and d.defaclobjtype in ('r', 'S')
      and a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)),
  0,
  'una tabla nueva de postgres en public no nace abierta a los roles de la API'
);

select * from finish();
rollback;
