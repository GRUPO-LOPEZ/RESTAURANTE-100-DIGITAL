-- Prueba de humo de la Fase 0: pgTAP funciona y existen los esquemas de la sección 5.
begin;
create extension if not exists pgtap with schema extensions;

select plan(60);

select has_schema(s, format('existe el esquema %s', s))
from unnest(array[
  'core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
  'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting'
]) as s;

-- Cada esquema tiene su descripción en español.
select ok(obj_description(s::regnamespace, 'pg_namespace') is not null, format('el esquema %s tiene comentario', s))
from unnest(array[
  'core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
  'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting'
]) as s;

-- Denegar por defecto: ningún rol de la API entra a ningún esquema de negocio.
-- Si una migración futura da acceso, tiene que actualizar esta prueba a propósito.
select ok(
  not has_schema_privilege(r, s, 'usage'),
  format('%s no tiene acceso al esquema %s', r, s)
)
from unnest(array[
  'core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
  'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting'
]) as s
cross join unnest(array['anon', 'authenticated', 'service_role']) as r;

select * from finish();
rollback;
