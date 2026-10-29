-- Datos de prueba para desarrollo local. SOLO DATOS FICTICIOS: nunca datos reales.
-- Se cargan con `npm run db:reset`, después de las migraciones.
-- Los ids son fijos para que las pruebas puedan referirse a ellos.
--
-- Hecho: un grupo ficticio, 3 marcas, 4 restaurantes y sus áreas (M3);
--        una persona por rol, un gerente de dos locales y una cuenta técnica (M4).
--        50 materias primas con alias, proveedores, productos de compra y alérgenos de prueba (2.1 A).
-- Fases siguientes: precios, rendimientos y 20 recetas.

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
  -- Chef de todo el grupo: aprueba los rendimientos estándar, que valen para todas las marcas
  -- (decisión de Joaco, 2026-10-29, ADR-0021).
  ('00000000-0000-4000-8000-000000000413', 'chefgrupo@ejemplo.test',   'Gabriel', 'Chef Grupo', 'executive_chef',    'group', null, null),
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
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000202'),
  -- Cuentas de prueba para Playwright (ids ...05NN): una por proyecto (celular y computadora)
  -- para las pruebas que bloquean o desactivan cuentas, así no se pisan entre sí.
  ('00000000-0000-4000-8000-000000000501', 'e2e-bloqueo-celular@ejemplo.test',     'Prueba', 'Bloqueo Celular',     'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000502', 'e2e-bloqueo-computadora@ejemplo.test', 'Prueba', 'Bloqueo Computadora', 'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000503', 'e2e-baja-celular@ejemplo.test',        'Prueba', 'Baja Celular',        'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000504', 'e2e-baja-computadora@ejemplo.test',    'Prueba', 'Baja Computadora',    'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  -- Suspender y levantar la suspensión (pantalla de la ficha).
  ('00000000-0000-4000-8000-000000000505', 'e2e-pausa-celular@ejemplo.test',       'Prueba', 'Pausa Celular',       'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000506', 'e2e-pausa-computadora@ejemplo.test',   'Prueba', 'Pausa Computadora',   'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  -- Recuperar y cambiar la contraseña (cambian la contraseña: nadie más las usa).
  ('00000000-0000-4000-8000-000000000507', 'e2e-clave-celular@ejemplo.test',       'Prueba', 'Clave Celular',       'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201'),
  ('00000000-0000-4000-8000-000000000508', 'e2e-clave-computadora@ejemplo.test',   'Prueba', 'Clave Computadora',   'cook', 'restaurant',
    '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000201');

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

-- Doble verificación ya registrada para las personas con roles que la exigen (niveles 1 a 4 y
-- Controller). Secreto TOTP FICTICIO, solo local y público a propósito: JBSWY3DPEHPK3PXP.
-- Las pruebas de Playwright calculan el código con ese secreto.
insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, secret, created_at, updated_at)
select gen_random_uuid(), p.id, 'App de prueba', 'totp', 'verified', 'JBSWY3DPEHPK3PXP', now(), now()
  from (select distinct p.id from seed_people p
          join core.roles r on r.code = p.role_code and r.requires_mfa) as p;

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

-- ---------------------------------------------------------------------------
-- Datos de la Fase 1 según el documento de Soy: dónde trabaja cada persona, puestos y áreas,
-- documentos de ensayo e ingresos de los últimos 30 días (todo ficticio).
-- ---------------------------------------------------------------------------
-- Quienes tienen un rol de local trabajan en ese local.
insert into core.user_memberships (user_id, group_id, brand_id, restaurant_id)
select distinct p.id, '00000000-0000-4000-8000-000000000001'::uuid, p.brand_id, p.restaurant_id
  from seed_people p where p.scope = 'restaurant';

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

-- ---------------------------------------------------------------------------
-- Catálogo de materias primas (Fase 2, etapa 2.1 A). Todo ficticio, con código DEMO-.
-- Ids fijos: categorías ...0007CC, ingredientes ...0008NN, proveedores ...0009PP.
-- Sin precios ni rendimientos: llegan en 2.1 B y 2.1 C.
-- ---------------------------------------------------------------------------
insert into catalog.ingredient_categories (id, group_id, name) values
  ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-000000000001', 'Verduras y frutas'),
  ('00000000-0000-4000-8000-000000000702', '00000000-0000-4000-8000-000000000001', 'Carnes'),
  ('00000000-0000-4000-8000-000000000703', '00000000-0000-4000-8000-000000000001', 'Lácteos'),
  ('00000000-0000-4000-8000-000000000704', '00000000-0000-4000-8000-000000000001', 'Huevos'),
  ('00000000-0000-4000-8000-000000000705', '00000000-0000-4000-8000-000000000001', 'Harinas y pastas secas'),
  ('00000000-0000-4000-8000-000000000706', '00000000-0000-4000-8000-000000000001', 'Aceites y grasas'),
  ('00000000-0000-4000-8000-000000000707', '00000000-0000-4000-8000-000000000001', 'Almacén'),
  ('00000000-0000-4000-8000-000000000708', '00000000-0000-4000-8000-000000000001', 'Especias y condimentos');

create temporary table seed_ingredients (n int, name text, category int, unit text, aliases text[]) on commit drop;
insert into seed_ingredients values
  (1, 'Tomate perita', 1, 'g', '{tomate}'), (2, 'Cebolla', 1, 'g', '{cebolla blanca}'), (3, 'Ajo', 1, 'g', '{}'),
  (4, 'Zanahoria', 1, 'g', '{}'), (5, 'Papa', 1, 'g', '{papa blanca}'), (6, 'Morrón rojo', 1, 'g', '{pimiento rojo}'),
  (7, 'Albahaca', 1, 'g', '{}'), (8, 'Perejil', 1, 'g', '{}'), (9, 'Limón', 1, 'unit', '{}'),
  (10, 'Zapallo', 1, 'g', '{calabaza}'), (11, 'Carne picada especial', 2, 'g', '{picada}'),
  (12, 'Bola de lomo', 2, 'g', '{}'), (13, 'Nalga', 2, 'g', '{}'), (14, 'Pechuga de pollo', 2, 'g', '{suprema}'),
  (15, 'Bondiola de cerdo', 2, 'g', '{bondiola}'), (16, 'Panceta', 2, 'g', '{}'), (17, 'Vacío', 2, 'g', '{}'),
  (18, 'Chorizo parrillero', 2, 'unit', '{chorizo}'), (19, 'Mozzarella', 3, 'g', '{muzza,mozza}'),
  (20, 'Queso rallado', 3, 'g', '{rallado}'), (21, 'Ricota', 3, 'g', '{ricotta}'), (22, 'Crema de leche', 3, 'ml', '{crema}'),
  (23, 'Leche entera', 3, 'ml', '{leche}'), (24, 'Manteca', 3, 'g', '{}'), (25, 'Queso provolone', 3, 'g', '{provoleta}'),
  (26, 'Huevo', 4, 'unit', '{huevos}'), (27, 'Harina 000', 5, 'g', '{harina}'), (28, 'Harina 0000', 5, 'g', '{}'),
  (29, 'Sémola', 5, 'g', '{}'), (30, 'Spaghetti secos', 5, 'g', '{fideos}'), (31, 'Arroz carnaroli', 5, 'g', '{arroz}'),
  (32, 'Pan rallado', 5, 'g', '{}'), (33, 'Aceite de oliva', 6, 'ml', '{oliva}'), (34, 'Aceite de girasol', 6, 'ml', '{girasol}'),
  (35, 'Tomate triturado', 7, 'g', '{pulpa de tomate}'), (36, 'Azúcar', 7, 'g', '{}'), (37, 'Sal fina', 7, 'g', '{sal}'),
  (38, 'Vinagre de alcohol', 7, 'ml', '{vinagre}'), (39, 'Vino tinto para cocinar', 7, 'ml', '{vino}'),
  (40, 'Levadura fresca', 7, 'g', '{levadura}'), (41, 'Pimienta negra', 8, 'g', '{pimienta}'), (42, 'Orégano', 8, 'g', '{}'),
  (43, 'Ají molido', 8, 'g', '{}'), (44, 'Nuez moscada', 8, 'g', '{}'), (45, 'Pimentón dulce', 8, 'g', '{pimentón}'),
  (46, 'Laurel', 8, 'g', '{}'), (47, 'Comino', 8, 'g', '{}'), (48, 'Aceitunas verdes', 7, 'g', '{aceitunas}'),
  (49, 'Atún al natural', 7, 'g', '{atún}'), (50, 'Champiñones', 1, 'g', '{hongos}');

insert into catalog.ingredients (id, group_id, code, name, category_id, recipe_unit_id)
select format('00000000-0000-4000-8000-%s', lpad((800 + s.n)::text, 12, '0'))::uuid,
       '00000000-0000-4000-8000-000000000001', format('DEMO-ING-%s', lpad(s.n::text, 3, '0')), s.name,
       format('00000000-0000-4000-8000-%s', lpad((700 + s.category)::text, 12, '0'))::uuid, u.id
  from seed_ingredients s join catalog.units u on u.code = s.unit;

insert into catalog.ingredient_aliases (group_id, ingredient_id, alias)
select '00000000-0000-4000-8000-000000000001', format('00000000-0000-4000-8000-%s', lpad((800 + s.n)::text, 12, '0'))::uuid, a
  from seed_ingredients s cross join unnest(s.aliases) as a;

-- Conversiones de prueba. La del aceite es la densidad del caso 16 del documento de Soy.
insert into catalog.ingredient_unit_conversions (group_id, ingredient_id, kind, factor, source, measured_on, measured_by)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000833', 'density', 0.92, 'measured', '2026-10-01', 'Dato de prueba (caso 16)'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000809', 'unit_weight', 120, 'estimated', '2026-10-01', 'Dato de prueba'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000818', 'unit_weight', 110, 'estimated', '2026-10-01', 'Dato de prueba');

insert into catalog.suppliers (id, group_id, code, name, is_internal) values
  ('00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000000001', 'DEMO-PROV-01', 'Verdulería Demo', false),
  ('00000000-0000-4000-8000-000000000902', '00000000-0000-4000-8000-000000000001', 'DEMO-PROV-02', 'Frigorífico Demo', false),
  ('00000000-0000-4000-8000-000000000903', '00000000-0000-4000-8000-000000000001', 'DEMO-PROV-03', 'Lácteos Demo', false),
  ('00000000-0000-4000-8000-000000000904', '00000000-0000-4000-8000-000000000001', 'DEMO-PROV-04', 'Almacén Mayorista Demo', false),
  ('00000000-0000-4000-8000-000000000905', '00000000-0000-4000-8000-000000000001', 'DEMO-PROV-05', 'Molino Demo', false),
  ('00000000-0000-4000-8000-000000000906', '00000000-0000-4000-8000-000000000001', 'DEMO-PROV-06', 'Pastas Demo (interna)', true);

-- Un producto por ingrediente, según cómo se compra cada categoría, y un segundo producto para
-- algunos (la mozzarella de dos marcas es la pregunta N6).
insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, package_unit_id,
                                       units_per_package, content_per_unit, content_unit_id)
select '00000000-0000-4000-8000-000000000001', format('DEMO-PROD-%s', lpad(s.n::text, 3, '0')),
       format('00000000-0000-4000-8000-%s', lpad((800 + s.n)::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad((900 + p.supplier)::text, 12, '0'))::uuid,
       s.name || ', ' || p.label, pu.id, p.units, p.content, cu.id
  from seed_ingredients s
  join (values
    (1, 1, 'cajón de 10 kg', 'box', 1, 10000, 'g'),   (2, 2, 'por kg', 'kg', 1, 1000, 'g'),
    (3, 3, 'horma de 4 kg', 'wheel', 1, 4000, 'g'),   (4, 4, 'bolsa de 5 kg', 'bag', 1, 5000, 'g'),
    (5, 5, 'bolsa de 25 kg', 'bag', 1, 25000, 'g'),   (6, 4, 'caja de 12 × 500 ml', 'box', 12, 500, 'ml'),
    (7, 4, 'lata de 1 kg', 'can', 1, 1000, 'g'),      (8, 4, 'paquete de 100 g', 'pack', 1, 100, 'g'),
    (9, 3, 'caja de 12 × 1 l', 'box', 12, 1000, 'ml'), (10, 1, 'maple de 30', 'box', 30, 1, 'unit'),
    (11, 1, 'por kg', 'kg', 1, 1000, 'g'),            (12, 4, 'bidón de 5 l', 'jug', 1, 5000, 'ml')
  ) as p (k, supplier, label, package, units, content, content_unit)
    on p.k = case
      when s.n in (9, 18) then 11                                   -- se usan por unidad, se compran por kg
      when s.n = 26 then 10
      when s.n = 7 or s.n = 8 then 2
      when s.category = 1 then 1
      when s.category = 2 then 2
      when s.n in (19, 25) then 3
      when s.n in (22, 23) then 9
      when s.category = 3 then 4
      when s.category = 5 and s.n <> 27 then 4
      when s.n = 27 then 5
      when s.n = 33 then 6
      when s.n in (34, 38, 39) then 12
      when s.n in (35, 48, 49) then 7
      when s.category = 8 then 8
      else 4 end
  join catalog.units pu on pu.code = p.package
  join catalog.units cu on cu.code = p.content_unit;

insert into catalog.purchase_products (group_id, code, ingredient_id, supplier_id, description, brand_name, package_unit_id,
                                       units_per_package, content_per_unit, content_unit_id)
select '00000000-0000-4000-8000-000000000001', format('DEMO-PROD-%s', lpad((100 + x.n)::text, 3, '0')),
       format('00000000-0000-4000-8000-%s', lpad((800 + x.n)::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad((900 + x.supplier)::text, 12, '0'))::uuid,
       x.description, x.brand, pu.id, x.units, x.content, cu.id
  from (values
    (19, 3, 'Mozzarella Marca Demo B, barra de 3 kg', 'Marca Demo B', 'pack', 1, 3000, 'g'),
    (11, 2, 'Carne picada especial, caja de 10 kg', null, 'box', 1, 10000, 'g'),
    (27, 5, 'Harina 000, bolsa de 1 kg', null, 'bag', 1, 1000, 'g'),
    (33, 4, 'Aceite de oliva, bidón de 5 l', null, 'jug', 1, 5000, 'ml'),
    (26, 1, 'Huevo, cajón de 180', null, 'box', 180, 1, 'unit'),
    (1, 4, 'Tomate perita, por kg', null, 'kg', 1, 1000, 'g'),
    (21, 6, 'Ricota de la planta interna, balde de 5 kg', null, 'pack', 1, 5000, 'g'),
    (30, 6, 'Spaghetti de la planta interna, bolsa de 5 kg', null, 'bag', 1, 5000, 'g'),
    (24, 3, 'Manteca, pan de 5 kg', null, 'pack', 1, 5000, 'g'),
    (23, 3, 'Leche entera, sachet de 1 l', null, 'bag', 1, 1000, 'ml')
  ) as x (n, supplier, description, brand, package, units, content, content_unit)
  join catalog.units pu on pu.code = x.package
  join catalog.units cu on cu.code = x.content_unit;

-- Alérgenos de prueba, SIN VALIDAR: la lista real la valida un responsable (pregunta N5).
insert into catalog.allergens (id, group_id, code, name) values
  ('00000000-0000-4000-8000-000000000951', '00000000-0000-4000-8000-000000000001', 'DEMO-GLUTEN', 'Cereales con gluten'),
  ('00000000-0000-4000-8000-000000000952', '00000000-0000-4000-8000-000000000001', 'DEMO-LECHE', 'Leche'),
  ('00000000-0000-4000-8000-000000000953', '00000000-0000-4000-8000-000000000001', 'DEMO-HUEVO', 'Huevo'),
  ('00000000-0000-4000-8000-000000000954', '00000000-0000-4000-8000-000000000001', 'DEMO-PESCADO', 'Pescado'),
  ('00000000-0000-4000-8000-000000000955', '00000000-0000-4000-8000-000000000001', 'DEMO-SOJA', 'Soja'),
  ('00000000-0000-4000-8000-000000000956', '00000000-0000-4000-8000-000000000001', 'DEMO-MANI', 'Maní'),
  ('00000000-0000-4000-8000-000000000957', '00000000-0000-4000-8000-000000000001', 'DEMO-FRUTOS-SECOS', 'Frutos secos'),
  ('00000000-0000-4000-8000-000000000958', '00000000-0000-4000-8000-000000000001', 'DEMO-CRUSTACEOS', 'Crustáceos');

-- Algunos estados de prueba. El resto queda "sin dato", a propósito.
insert into catalog.ingredient_allergens (group_id, ingredient_id, allergen_id, status, source)
select '00000000-0000-4000-8000-000000000001', format('00000000-0000-4000-8000-%s', lpad((800 + x.n)::text, 12, '0'))::uuid,
       format('00000000-0000-4000-8000-%s', lpad((950 + x.allergen)::text, 12, '0'))::uuid,
       x.status::catalog.allergen_status, 'manual'
  from (values (19, 2, 'contains'), (20, 2, 'contains'), (21, 2, 'contains'), (22, 2, 'contains'), (23, 2, 'contains'),
               (24, 2, 'contains'), (25, 2, 'contains'), (26, 3, 'contains'), (27, 1, 'contains'), (28, 1, 'contains'),
               (29, 1, 'contains'), (30, 1, 'contains'), (32, 1, 'contains'), (49, 4, 'contains'),
               (30, 3, 'may_contain'), (1, 1, 'free_verified')) as x (n, allergen, status);

-- Rendimientos (etapa 2.1 B). Ids fijos de procesos: ...00096P. Los estándares usan los valores
-- de prueba del documento de Soy (caso 2: tomate pelado 80 %; caso 18: pasta que se expande ×2,5)
-- y los aprueba el Chef del grupo. Un ensayo del tomate da 77 %: la ficha muestra la diferencia.
insert into catalog.yield_processes (id, group_id, code, name) values
  ('00000000-0000-4000-8000-000000000961', '00000000-0000-4000-8000-000000000001', 'PELADO', 'Pelado'),
  ('00000000-0000-4000-8000-000000000962', '00000000-0000-4000-8000-000000000001', 'LIMPIEZA', 'Limpieza'),
  ('00000000-0000-4000-8000-000000000963', '00000000-0000-4000-8000-000000000001', 'DESGRASADO', 'Desgrasado'),
  ('00000000-0000-4000-8000-000000000964', '00000000-0000-4000-8000-000000000001', 'DESHUESADO', 'Deshuesado'),
  ('00000000-0000-4000-8000-000000000965', '00000000-0000-4000-8000-000000000001', 'HERVIDO', 'Hervido');

insert into catalog.ingredient_yield_profiles (group_id, ingredient_id, process_id, cleaning_yield, cooking_factor, method,
                                               status, approved_by, approved_at)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000801', '00000000-0000-4000-8000-000000000961',
   0.80, 1, 'Dato de prueba (caso 2)', 'approved', '00000000-0000-4000-8000-000000000413', now()),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000830', '00000000-0000-4000-8000-000000000965',
   1, 2.5, 'Dato de prueba (caso 18)', 'approved', '00000000-0000-4000-8000-000000000413', now());

insert into catalog.ingredient_yield_tests (group_id, ingredient_id, process_id, restaurant_id, tested_on, samples,
                                            gross_weight, clean_weight, before_cooking_weight, after_cooking_weight,
                                            responsible, created_by)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000801', '00000000-0000-4000-8000-000000000961',
   '00000000-0000-4000-8000-000000000201', current_date - 2, 3, 10000, 7700, null, null, 'Julián (prueba)',
   '00000000-0000-4000-8000-000000000406'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000830', '00000000-0000-4000-8000-000000000965',
   '00000000-0000-4000-8000-000000000201', current_date - 1, 1, null, null, 1000, 2450, 'Julián (prueba)',
   '00000000-0000-4000-8000-000000000406');

-- Ingresos ficticios de los últimos 30 días, para el gráfico del tablero.
set role audit_owner;
insert into audit.authentication_security_events (event_type, occurred_at, operation, reason, user_id, email, scope_group_id)
select case when (d * 7 + n) % 9 = 0 then 'login_failed'::audit.security_event_type else 'login_succeeded' end,
       now() - make_interval(days => d, hours => n % 10),
       'auth.login', 'Dato de prueba del seed', p.id, p.email, '00000000-0000-4000-8000-000000000001'
  from generate_series(1, 29) as d
 cross join generate_series(1, 6) as n
 -- Ids y correos fijos del seed (audit_owner no lee los perfiles).
 join (values (0, '00000000-0000-4000-8000-000000000409'::uuid, 'cocinero@ejemplo.test'),
              (1, '00000000-0000-4000-8000-000000000404'::uuid, 'gerente@ejemplo.test'),
              (2, '00000000-0000-4000-8000-000000000406'::uuid, 'jefecocina@ejemplo.test')) as p (k, id, email)
   on p.k = n % 3;
reset role;

commit;
