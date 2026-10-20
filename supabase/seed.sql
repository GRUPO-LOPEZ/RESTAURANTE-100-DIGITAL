-- Datos de prueba para desarrollo local. SOLO DATOS FICTICIOS: nunca datos reales.
-- Se cargan con `npm run db:reset`, después de las migraciones.
-- Los ids son fijos para que las pruebas puedan referirse a ellos.
--
-- Hecho: un grupo ficticio, 3 marcas, 4 restaurantes y sus áreas (M3).
-- Pendiente: un usuario de prueba por rol (M4, cuando Soy defina los roles: P1).
-- Fases siguientes: 50 ingredientes y 20 recetas.

-- NUNCA se carga en staging ni en producción: no usar `db push --include-seed` ni
-- Supabase Branching con seed contra proyectos remotos (ADR-0005).

begin;

-- Guarda: si la base ya tiene grupos, no es una base local recién creada.
do $$
begin
  if exists (select 1 from org.groups) then
    raise exception 'El seed solo corre sobre una base vacía (npm run db:reset). Esta base ya tiene datos.';
  end if;
end
$$;

select core.set_change_context('Datos de prueba locales', 'seed');

insert into org.groups (id, name) values
  ('00000000-0000-4000-8000-000000000001', 'Grupo Demo');

insert into org.brands (id, group_id, name) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000001', 'Demo Pastas'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000001', 'Demo Parrilla'),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-000000000001', 'Demo Café');

insert into org.restaurants (id, group_id, brand_id, name) values
  ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', 'Demo Pastas Centro'),
  ('00000000-0000-4000-8000-000000000202', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', 'Demo Pastas Norte'),
  ('00000000-0000-4000-8000-000000000203', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000102', 'Demo Parrilla Centro'),
  ('00000000-0000-4000-8000-000000000204', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000103', 'Demo Café Centro');

-- Áreas con ids fijos: ...03RA, donde R es el restaurante (1 a 4) y A el área (1 a 3).
insert into org.areas (id, group_id, restaurant_id, name)
select
  format('00000000-0000-4000-8000-0000000003%s%s', right(r.id::text, 1), a.n)::uuid,
  r.group_id, r.id, a.name
from org.restaurants r
cross join (values (1, 'Cocina'), (2, 'Salón'), (3, 'Depósito')) as a (n, name);

commit;
