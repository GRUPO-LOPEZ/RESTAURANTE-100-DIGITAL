-- Datos de prueba para desarrollo local. SOLO DATOS FICTICIOS: nunca datos reales.
-- Se cargan con `npm run db:reset`, después de las migraciones.
-- Los ids son fijos para que las pruebas puedan referirse a ellos.
--
-- Hecho: un grupo ficticio, 3 marcas, 4 restaurantes y sus áreas (M3);
--        una persona por rol, un gerente de dos locales y una cuenta técnica (M4).
-- Fases siguientes: 50 ingredientes y 20 recetas.

-- NUNCA se carga en staging ni en producción: no usar `db push --include-seed` ni
-- Supabase Branching con seed contra proyectos remotos (ADR-0005).

begin;

-- Guardas: solo sobre una base local recién creada. Supabase alojado siempre usa SSL; la local no.
-- Un proyecto remoto nuevo también está vacío, por eso no alcanza con mirar si hay datos.
do $$
begin
  if current_setting('ssl') = 'on' then
    raise exception 'El seed solo corre en la base local (npm run db:reset). Esta base tiene SSL: no es local.';
  end if;
  if exists (select 1 from org.groups) or exists (select 1 from auth.users) then
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

-- ---------------------------------------------------------------------------
-- Personas de prueba: una por rol, más un gerente de dos locales (M4).
-- Ids ...04NN. Correo <rol>@ejemplo.test. Contraseña de prueba SOLO LOCAL: Demo-Local-2026!
-- Se cargan en auth.users y auth.identities para poder probar el ingreso; el trigger de
-- M1/M4 crea el actor y el perfil.
-- ---------------------------------------------------------------------------
create temporary table seed_people (id uuid, email text, first_name text, last_name text, role_code text,
  scope core.scope_type, brand_id uuid, restaurant_id uuid) on commit drop;

insert into seed_people values
  ('00000000-0000-4000-8000-000000000401', 'superadmin@ejemplo.test',  'Sofía',   'Admin',     'superadmin',         'group', null, null),
  ('00000000-0000-4000-8000-000000000402', 'direccion@ejemplo.test',   'Diego',   'Dirección', 'general_management', 'group', null, null),
  -- Segunda persona de Dirección General: para probar que nadie aprueba lo propio (decisión de Joaco, 2026-10-20).
  ('00000000-0000-4000-8000-000000000412', 'direccion2@ejemplo.test',  'Delia',   'Dirección', 'general_management', 'group', null, null),
  ('00000000-0000-4000-8000-000000000403', 'director@ejemplo.test',    'Marta',   'Marca',     'brand_director',     'brand',
    '00000000-0000-4000-8000-000000000101', null),
  ('00000000-0000-4000-8000-000000000404', 'gerente@ejemplo.test',     'Gonzalo', 'Gerente',   'restaurant_manager', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000405', 'chef@ejemplo.test',        'Carla',   'Chef',      'executive_chef',     'brand',
    '00000000-0000-4000-8000-000000000101', null),
  ('00000000-0000-4000-8000-000000000406', 'jefecocina@ejemplo.test',  'Julián',  'Cocina',    'head_chef',          'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000407', 'controller@ejemplo.test',  'Camila',  'Costos',    'controller',         'group', null, null),
  ('00000000-0000-4000-8000-000000000408', 'compras@ejemplo.test',     'Pablo',   'Compras',   'purchasing',         'group', null, null),
  ('00000000-0000-4000-8000-000000000409', 'cocinero@ejemplo.test',    'Lucía',   'Operadora', 'cook',               'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000410', 'auditor@ejemplo.test',     'Andrés',  'Auditor',   'auditor',            'group', null, null),
  -- Gerente de dos locales: dos asignaciones (Centro y Norte de Demo Pastas).
  ('00000000-0000-4000-8000-000000000411', 'gerente2@ejemplo.test',    'Nora',    'Dos Locales', 'restaurant_manager', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000411', 'gerente2@ejemplo.test',    'Nora',    'Dos Locales', 'restaurant_manager', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000202');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select distinct on (p.id)
  '00000000-0000-0000-0000-000000000000', p.id, 'authenticated', 'authenticated', p.email,
  extensions.crypt('Demo-Local-2026!', extensions.gen_salt('bf')), now(),
  '{"provider": "email", "providers": ["email"]}',
  jsonb_build_object('first_name', p.first_name, 'last_name', p.last_name),
  now(), now(), '', '', '', ''
from seed_people p;

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select distinct on (p.id)
  gen_random_uuid(), p.id, p.id::text, 'email',
  jsonb_build_object('sub', p.id::text, 'email', p.email, 'email_verified', true),
  now(), now(), now()
from seed_people p;

insert into core.user_memberships (user_id, group_id)
select distinct p.id, '00000000-0000-4000-8000-000000000001'::uuid from seed_people p;

insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
select p.id, r.id, p.scope, '00000000-0000-4000-8000-000000000001', p.brand_id, p.restaurant_id
from seed_people p
join core.roles r on r.code = p.role_code;

-- Cuenta técnica de prueba (sin roles ni permisos: los agentes llegan en la Fase 5).
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-000000000499', 'authenticated', 'authenticated',
  'agente.prueba@ejemplo.test', null, now(),
  '{"provider": "email", "providers": ["email"], "actor_type": "service_account"}', '{}',
  now(), now(), '', '', '', ''
);

insert into core.service_accounts (id, code, name, description, owner_user_id) values (
  '00000000-0000-4000-8000-000000000499', 'agente-prueba', 'Agente de prueba',
  'Cuenta técnica ficticia para probar la estructura. Sin permisos.', '00000000-0000-4000-8000-000000000401'
);

commit;
