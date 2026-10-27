-- Personas y datos de prueba para el ambiente de prueba (staging), ADR-0018. SOLO DATOS FICTICIOS.
-- Lo corre el flujo "Publicar en staging" de GitHub Actions, a pedido, con psql 15 o más:
--   psql -X --no-password -f supabase/staging/demo-data.sql "$STAGING_DB_URL"
-- con PGPASSWORD, DEMO_ADMIN_PASSWORD y DEMO_PASSWORD como variables de entorno (el flujo ya
-- validó largo, letras, números y que sean distintas).
--
-- Es el mismo grupo ficticio que supabase/seed.sql (ids fijos, un usuario por rol), sin lo que
-- solo sirve para las pruebas automáticas: cuentas e2e-*, secreto TOTP público e ingresos inventados.
-- Dos contraseñas: DEMO_ADMIN_PASSWORD para los roles con doble verificación (solo Joaco y Soy, que
-- la activan con su celular antes de repartir nada) y DEMO_PASSWORD para el resto.
-- Las contraseñas nunca se escriben en este archivo.
--
-- Se puede correr más de una vez: si el grupo de prueba ya está, no cambia nada.
-- Nunca corre sobre una base con otros datos (por ejemplo, producción).

\set ON_ERROR_STOP on

\getenv demo_admin_password DEMO_ADMIN_PASSWORD
\getenv demo_password DEMO_PASSWORD
\getenv run_id GITHUB_RUN_ID
\if :{?run_id}
  \set change_reason 'Datos de prueba de staging (corrida ' :run_id ' de GitHub Actions)'
\else
  \set change_reason 'Datos de prueba de staging (a mano)'
\endif

\if :{?demo_admin_password}
\else
  do $$ begin raise exception 'Falta DEMO_ADMIN_PASSWORD (contraseña de los roles con doble verificación).'; end $$;
\endif
\if :{?demo_password}
\else
  do $$ begin raise exception 'Falta DEMO_PASSWORD (contraseña del resto de las personas de prueba).'; end $$;
\endif

select exists (select 1 from org.groups where id = '00000000-0000-4000-8000-000000000001') as demo_loaded \gset
\if :demo_loaded
  \echo 'Los datos de prueba ya estaban cargados: no se cambia nada.'
  \quit
\endif

begin;

-- Guarda: solo sobre una base sin grupos ni personas. Si hay cualquier otro dato, no toca nada.
do $$
begin
  if exists (select 1 from org.groups) or exists (select 1 from auth.users) then
    raise exception 'Los datos de prueba solo se cargan en una base vacía. Esta base ya tiene grupos o personas.';
  end if;
end
$$;

-- La única sentencia que lleva las contraseñas, y es una consulta (no DDL, que Postgres puede
-- registrar). De acá en adelante solo se usan los hash, con el costo de Supabase Auth (10).
select extensions.crypt(:'demo_admin_password', extensions.gen_salt('bf', 10)) as demo_admin_hash,
       extensions.crypt(:'demo_password', extensions.gen_salt('bf', 10)) as demo_hash \gset
\unset demo_admin_password
\unset demo_password

select core.set_change_context(:'change_reason', 'seed');

-- Razón social y CUIT ficticios (el CUIT no es válido a propósito).
insert into org.groups (id, name, legal_name, tax_id) values
  ('00000000-0000-4000-8000-000000000001', 'Grupo Demo', 'Grupo Demo S.A. (ficticia)', '00000000000');

insert into org.brands (id, group_id, name, code) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000001', 'Demo Pastas', 'PASTAS'),
  ('00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000001', 'Demo Parrilla', 'PARRILLA'),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-000000000001', 'Demo Café', 'CAFE');

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

-- Personas de prueba: una por rol, una segunda de Dirección (para aprobar lo que pide la
-- primera) y un gerente de dos locales. Mismos ids y correos que el seed local.
create temporary table demo_people (id uuid, email text, first_name text, last_name text, role_code text,
  scope core.scope_type, brand_id uuid, restaurant_id uuid) on commit drop;

insert into demo_people values
  ('00000000-0000-4000-8000-000000000401', 'superadmin@ejemplo.test',  'Sofía',   'Admin',     'superadmin',         'group', null, null),
  ('00000000-0000-4000-8000-000000000402', 'direccion@ejemplo.test',   'Diego',   'Dirección', 'general_management', 'group', null, null),
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
  case when r.requires_mfa then :'demo_admin_hash' else :'demo_hash' end, now(),
  '{"provider": "email", "providers": ["email"]}',
  jsonb_build_object('first_name', p.first_name, 'last_name', p.last_name),
  now(), now(), '', '', '', ''
from demo_people p
join core.roles r on r.code = p.role_code;

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select distinct on (p.id)
  gen_random_uuid(), p.id, p.id::text, 'email',
  jsonb_build_object('sub', p.id::text, 'email', p.email, 'email_verified', true),
  null, now(), now()
from demo_people p;

insert into core.user_memberships (user_id, group_id)
select distinct p.id, '00000000-0000-4000-8000-000000000001'::uuid from demo_people p;

-- Quienes tienen un rol de local trabajan en ese local.
insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
select distinct p.id, '00000000-0000-4000-8000-000000000001'::uuid, p.brand_id, p.restaurant_id
  from demo_people p where p.scope = 'restaurant';

insert into core.user_role_assignments (user_id, role_id, scope_type, group_id, brand_id, restaurant_id)
select p.id, r.id, p.scope, '00000000-0000-4000-8000-000000000001', p.brand_id, p.restaurant_id
from demo_people p
join core.roles r on r.code = p.role_code;

update core.user_profiles set job_title = v.job_title, area_id = v.area_id::uuid
  from (values
    ('00000000-0000-4000-8000-000000000404', 'Gerente del local', null),
    ('00000000-0000-4000-8000-000000000406', 'Jefe de cocina', '00000000-0000-4000-8000-000000000311'),
    ('00000000-0000-4000-8000-000000000409', 'Cocinera de línea', '00000000-0000-4000-8000-000000000311'),
    ('00000000-0000-4000-8000-000000000405', 'Chef de la marca', null),
    ('00000000-0000-4000-8000-000000000407', 'Analista de costos', null),
    ('00000000-0000-4000-8000-000000000408', 'Responsable de compras', null)
  ) as v (id, job_title, area_id)
 where core.user_profiles.id = v.id::uuid;

-- Documentos de ensayo: uno vigente de la marca (con costo), uno vigente de un local y un borrador.
insert into core.test_documents (id, group_id, brand_id, restaurant_id, document_key, version_number, title, content, cost) values
  ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101', null,
   '00000000-0000-4000-8000-000000000611', 1, 'Salsa de tomate de la casa',
   'Sofreír ajo y cebolla, agregar tomate triturado y cocinar 40 minutos a fuego bajo.', 1520.50),
  ('00000000-0000-4000-8000-000000000602', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000102',
   '00000000-0000-4000-8000-000000000203', '00000000-0000-4000-8000-000000000612', 1, 'Chimichurri',
   'Perejil, ajo, orégano, ají molido, vinagre y aceite. Reposar 12 horas.', 830.00),
  ('00000000-0000-4000-8000-000000000603', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000613', 1, 'Ñoquis de papa',
   'Papa, harina y huevo. Borrador del jefe de cocina.', null);
update core.test_documents set status = 'in_review' where id in ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000602');
update core.test_documents set status = 'approved' where id in ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000602');
update core.test_documents set status = 'published' where id in ('00000000-0000-4000-8000-000000000601', '00000000-0000-4000-8000-000000000602');

commit;

\echo 'Datos de prueba cargados.'
