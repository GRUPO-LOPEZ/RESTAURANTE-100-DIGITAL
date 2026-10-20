-- Prueba de humo de la Fase 0: pgTAP funciona y existen los esquemas de la sección 5.
begin;
create extension if not exists pgtap with schema extensions;

select plan(26);

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

-- Denegar por defecto: los roles de la API no pueden entrar a los esquemas de negocio.
select ok(not has_schema_privilege('anon', 'core', 'usage'), 'anon no tiene acceso al esquema core');
select ok(not has_schema_privilege('authenticated', 'audit', 'usage'), 'authenticated no tiene acceso al esquema audit todavía');

select * from finish();
rollback;
