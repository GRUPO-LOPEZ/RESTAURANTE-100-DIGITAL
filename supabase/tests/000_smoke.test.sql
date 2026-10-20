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

-- Denegar por defecto: ningún rol de la API entra a ningún esquema de negocio, salvo
-- authenticated a core y org (M5, ADR-0005). anon y service_role, a ninguno.
-- Si una migración futura da acceso, tiene que actualizar esta prueba a propósito.
select is(
  has_schema_privilege(r, s, 'usage'),
  r = 'authenticated' and s in ('core', 'org'),
  format('%s %s acceso al esquema %s', r,
         case when r = 'authenticated' and s in ('core', 'org') then 'tiene' else 'no tiene' end, s)
)
from unnest(array[
  'core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
  'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting'
]) as s
cross join unnest(array['anon', 'authenticated', 'service_role']) as r;

select * from finish();
rollback;
