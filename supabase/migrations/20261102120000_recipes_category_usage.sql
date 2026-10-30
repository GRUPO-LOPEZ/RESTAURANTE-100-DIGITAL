-- Cuántas recetas tiene cada categoría de recetas, para la pantalla de configuración (etapa 2.2 A,
-- PR 2; ADR-0023). Igual que catalog.category_usage: con los permisos de quien consulta (RLS) y
-- contando en la base, porque la API devuelve hasta 1.000 filas por consulta.
create function recipes.category_usage()
returns table (category_id uuid, recipes bigint)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.category_id, count(*) from recipes.recipes r
   where r.deleted_at is null and r.category_id is not null
   group by r.category_id
$$;
comment on function recipes.category_usage() is
  'Cuántas recetas vigentes tiene cada categoría de recetas, entre las que ve la sesión. Para la pantalla de configuración.';
revoke execute on function recipes.category_usage() from public;
grant execute on function recipes.category_usage() to authenticated;
