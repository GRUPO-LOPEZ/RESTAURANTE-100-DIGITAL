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
-- authenticated a core, org y workflow (M5 y M7, ADR-0005) y a catalog, recipes y costing (Fase 2, ADR-0020, ADR-0023 y ADR-0029). service_role solo a core, para las dos funciones de ingreso (M8). anon, a ninguno.
-- Si una migración futura da acceso, tiene que actualizar esta prueba a propósito.
select is(
  has_schema_privilege(r, s, 'usage'),
  (r = 'authenticated' and s in ('core', 'org', 'workflow', 'catalog', 'recipes', 'costing')) or (r = 'service_role' and s = 'core'),
  format('%s %s acceso al esquema %s', r,
         case when (r = 'authenticated' and s in ('core', 'org', 'workflow', 'catalog', 'recipes', 'costing')) or (r = 'service_role' and s = 'core') then 'tiene' else 'no tiene' end, s)
)
from unnest(array[
  'core', 'org', 'audit', 'workflow', 'catalog', 'recipes',
  'costing', 'purchasing', 'inventory', 'production', 'ai', 'reporting'
]) as s
cross join unnest(array['anon', 'authenticated', 'service_role']) as r;

select * from finish();
rollback;
