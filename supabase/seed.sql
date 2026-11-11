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
-- Datos de la Fase 1 según el documento de Soy: dónde trabaja cada persona, puestos y áreas
-- e ingresos de los últimos 30 días (todo ficticio).
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

-- ---------------------------------------------------------------------------
-- Catálogo de materias primas (Fase 2, etapa 2.1 A). Todo ficticio, con código DEMO-.
-- Ids fijos: categorías ...0007CC, ingredientes ...0008NN, proveedores ...0009PP.
-- Sin precios ni rendimientos: llegan en 2.1 B y 2.1 C.
-- ---------------------------------------------------------------------------
-- Rubros (ADR-0038): las categorías del seed conservan su nombre viejo y llevan a mano el código del rubro
-- de Soy que les corresponde (el mismo que les daría recipes.map_legacy_categories por la primera palabra).
-- «Almacén» no coincide con ninguno y su código lo arma el trigger (MP-ALM). Los rubros de Soy que faltan los
-- carga recipes.install_default_categories. El mapeo de datos ya cargados se prueba en 250_rubros.
insert into catalog.ingredient_categories (id, group_id, name, code) values
  ('00000000-0000-4000-8000-000000000701', '00000000-0000-4000-8000-000000000001', 'Verduras y frutas', 'MP-VER'),
  ('00000000-0000-4000-8000-000000000702', '00000000-0000-4000-8000-000000000001', 'Carnes', 'MP-CAR'),
  ('00000000-0000-4000-8000-000000000703', '00000000-0000-4000-8000-000000000001', 'Lácteos', 'MP-LAC'),
  ('00000000-0000-4000-8000-000000000704', '00000000-0000-4000-8000-000000000001', 'Huevos', 'MP-HUE'),
  ('00000000-0000-4000-8000-000000000705', '00000000-0000-4000-8000-000000000001', 'Harinas y pastas secas', 'MP-HAR'),
  ('00000000-0000-4000-8000-000000000706', '00000000-0000-4000-8000-000000000001', 'Aceites y grasas', 'MP-ACE'),
  ('00000000-0000-4000-8000-000000000707', '00000000-0000-4000-8000-000000000001', 'Almacén', null),
  ('00000000-0000-4000-8000-000000000708', '00000000-0000-4000-8000-000000000001', 'Especias y condimentos', 'MP-ESP');

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
  ('00000000-0000-4000-8000-000000000965', '00000000-0000-4000-8000-000000000001', 'HERVIDO', 'Hervido'),
  -- Descongelado (ADR-0040): ninguna materia prima del seed se compra congelada, así el costo de prueba no cambia.
  ('00000000-0000-4000-8000-000000000966', '00000000-0000-4000-8000-000000000001', 'DESCONGELADO', 'Descongelado');

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

-- ---------------------------------------------------------------------------
-- Recetas (Fase 2, etapa 2.2 A). Todo ficticio, con código DEMO-.
-- Ids fijos: categorías ...00106C, recetas ...0011NN, versiones ...0012NN.
-- Maestras del grupo (1 a 5), de Demo Pastas (6 a 11), de Demo Parrilla (12 a 17), de Demo Café (18 y 19)
-- y una de local (20, Demo Pastas Centro). Todas publicadas salvo el risotto (11), en borrador.
-- La bolognesa (2) tiene los pasos del caso 22: 20 + máx(60, 30) + 10 = 90 minutos.
-- ---------------------------------------------------------------------------
-- Rubros (ADR-0038): un plato va en un rubro de menú (PL) y una preparación en uno de sub-recetas (SR).
-- Las categorías viejas llevan el código de Soy que les corresponde; 6 a 8 son rubros de Soy con id fijo
-- para las recetas que no entraban en la categoría vieja (masa, bondiola braseada y ensalada).
insert into recipes.recipe_categories (id, group_id, name, kind, code) values
  ('00000000-0000-4000-8000-000000001061', '00000000-0000-4000-8000-000000000001', 'Salsas', 'subrecipe', 'SR-SAL'),
  ('00000000-0000-4000-8000-000000001062', '00000000-0000-4000-8000-000000000001', 'Pastas', 'menu', 'PL-PAS'),
  ('00000000-0000-4000-8000-000000001063', '00000000-0000-4000-8000-000000000001', 'Carnes', 'menu', 'PL-CAR'),
  ('00000000-0000-4000-8000-000000001064', '00000000-0000-4000-8000-000000000001', 'Guarniciones pre-elaboradas',
   'subrecipe', 'SR-GUA'),
  ('00000000-0000-4000-8000-000000001065', '00000000-0000-4000-8000-000000000001', 'Pastelería y café', 'subrecipe',
   'SR-PST'),
  ('00000000-0000-4000-8000-000000001066', '00000000-0000-4000-8000-000000000001', 'Masas', 'subrecipe', 'SR-MAS'),
  ('00000000-0000-4000-8000-000000001067', '00000000-0000-4000-8000-000000000001', 'Cocciones base', 'subrecipe',
   'SR-COC'),
  ('00000000-0000-4000-8000-000000001068', '00000000-0000-4000-8000-000000000001', 'Ensaladas', 'menu', 'PL-ENS');
select recipes.install_default_categories('00000000-0000-4000-8000-000000000001');

create temporary table seed_recipes (n int, code text, name text, kind text, brand int, restaurant int, category int,
                                     yield_qty numeric, yield_unit text, portions int, portion_grams numeric,
                                     cook_text text, active int, passive int, published boolean) on commit drop;
insert into seed_recipes values
  (1, 'DEMO-SAL-01', 'Salsa fileto', 'preparation', null, null, 1, 2, 'l', null, null,
   'Rehogar cebolla y ajo en el aceite, sumar el tomate y cocinar a fuego bajo.', 15, 40, true),
  (2, 'DEMO-SAL-02', 'Salsa bolognesa', 'preparation', null, null, 1, 3, 'kg', null, null, null, 0, 0, true),
  (3, 'DEMO-SAL-03', 'Salsa blanca', 'preparation', null, null, 1, 1, 'l', null, null,
   'Hacer un roux con la manteca y la harina, sumar la leche caliente y batir hasta espesar.', 15, 5, true),
  (4, 'DEMO-GUA-01', 'Puré de papas', 'preparation', null, null, 4, 2, 'kg', null, null,
   'Hervir las papas, pisarlas y sumar la manteca y la leche caliente.', 15, 25, true),
  (5, 'DEMO-GUA-02', 'Papas rústicas', 'preparation', null, null, 4, 1.5, 'kg', null, null,
   'Cortar en gajos, condimentar y hornear hasta dorar.', 10, 40, true),
  (6, 'DEMO-PAS-01', 'Masa de pasta fresca', 'preparation', 1, null, 6, 1.2, 'kg', null, null,
   'Formar la masa, amasar y dejar reposar tapada.', 15, 30, true),
  (7, 'DEMO-PAS-02', 'Spaghetti al fileto', 'dish', 1, null, 2, 1, 'unit', 1, 350,
   'Hervir la pasta al dente y saltear con la salsa.', 5, 9, true),
  (8, 'DEMO-PAS-03', 'Ravioles de ricota', 'dish', 1, null, 2, 1, 'unit', 1, 300,
   'Estirar la masa, rellenar, cortar y hervir.', 20, 5, true),
  (9, 'DEMO-PAS-04', 'Ñoquis de papa', 'dish', 1, null, 2, 1.2, 'kg', 4, 300,
   'Hacer la masa con la papa pisada, cortar los ñoquis y hervir hasta que suban.', 30, 5, true),
  (10, 'DEMO-PAS-05', 'Lasaña bolognesa', 'dish', 1, null, 2, 3, 'kg', 8, 375,
   'Armar capas de pasta, salsa y queso, y hornear.', 25, 45, true),
  (11, 'DEMO-PAS-06', 'Risotto de hongos', 'dish', 1, null, 2, 1.2, 'kg', 4, 300,
   'Nacarar el arroz, sumar caldo de a poco y terminar con manteca y queso.', 25, 0, false),
  (12, 'DEMO-PAR-01', 'Chimichurri', 'preparation', 2, null, 1, 0.5, 'l', null, null,
   'Picar, mezclar con el vinagre y el aceite, y dejar macerar.', 15, 60, true),
  (13, 'DEMO-PAR-02', 'Vacío a la parrilla', 'dish', 2, null, 3, 1, 'unit', 1, 350,
   'Asar a fuego medio, dar vuelta una vez y dejar reposar antes de cortar.', 10, 80, true),
  (14, 'DEMO-PAR-03', 'Provoleta', 'dish', 2, null, 3, 1, 'unit', 1, 200,
   'Grillar en provoletera hasta dorar los dos lados.', 5, 8, true),
  (15, 'DEMO-PAR-04', 'Bondiola braseada', 'preparation', 2, null, 7, 2, 'kg', null, null,
   'Sellar, sumar la cebolla y el vino, tapar y cocinar a fuego bajo.', 20, 150, true),
  (16, 'DEMO-PAR-05', 'Chorizo a la parrilla', 'dish', 2, null, 3, 1, 'unit', 1, 120,
   'Asar a fuego medio dando vuelta seguido.', 5, 20, true),
  (17, 'DEMO-PAR-06', 'Pollo grillado al limón', 'dish', 2, null, 3, 1, 'unit', 1, 250,
   'Marinar con limón y aceite, y grillar hasta cocinar bien.', 10, 15, true),
  (18, 'DEMO-CAF-01', 'Budín de limón', 'preparation', 3, null, 5, 1, 'unit', 10, 80,
   'Batir, sumar los secos y la ralladura, y hornear en molde.', 20, 45, true),
  (19, 'DEMO-CAF-02', 'Ensalada de atún', 'dish', 3, null, 8, 1, 'unit', 1, 330,
   'Hervir la papa y el huevo, enfriar y armar con el atún y las aceitunas.', 10, 20, true),
  (20, 'DEMO-LOC-01', 'Sorrentinos de zapallo', 'dish', 1, 201, 2, 1, 'unit', 1, 320,
   'Asar el zapallo, hacer el relleno, armar los sorrentinos y hervir.', 30, 40, true);

create temporary table seed_recipe_lines (ord int generated always as identity, n int, ingredient int, qty numeric, unit text)
  on commit drop;
insert into seed_recipe_lines (n, ingredient, qty, unit) values
  (1, 35, 2000, 'g'), (1, 2, 300, 'g'), (1, 3, 20, 'g'), (1, 33, 60, 'ml'), (1, 7, 10, 'g'), (1, 37, 15, 'g'), (1, 36, 10, 'g'),
  (2, 11, 1500, 'g'), (2, 35, 1500, 'g'), (2, 2, 400, 'g'), (2, 4, 200, 'g'), (2, 39, 200, 'ml'), (2, 34, 50, 'ml'),
  (2, 37, 20, 'g'), (2, 46, 2, 'g'),
  (3, 23, 1000, 'ml'), (3, 24, 60, 'g'), (3, 28, 60, 'g'), (3, 44, 1, 'g'), (3, 37, 8, 'g'),
  (4, 5, 2, 'kg'), (4, 24, 100, 'g'), (4, 23, 300, 'ml'), (4, 37, 15, 'g'), (4, 44, 1, 'g'),
  (5, 5, 2000, 'g'), (5, 34, 100, 'ml'), (5, 37, 15, 'g'), (5, 45, 5, 'g'), (5, 42, 3, 'g'),
  (6, 27, 1000, 'g'), (6, 26, 8, 'unit'), (6, 37, 10, 'g'), (6, 33, 20, 'ml'),
  (7, 30, 120, 'g'), (7, 35, 150, 'g'), (7, 33, 10, 'ml'), (7, 20, 15, 'g'), (7, 7, 2, 'g'),
  (8, 27, 100, 'g'), (8, 26, 1, 'unit'), (8, 21, 120, 'g'), (8, 20, 20, 'g'), (8, 44, 0.5, 'g'),
  (9, 5, 1000, 'g'), (9, 27, 250, 'g'), (9, 26, 1, 'unit'), (9, 37, 8, 'g'),
  (10, 19, 500, 'g'), (10, 27, 500, 'g'), (10, 26, 4, 'unit'),
  (11, 31, 320, 'g'), (11, 50, 300, 'g'), (11, 2, 100, 'g'), (11, 24, 60, 'g'), (11, 20, 60, 'g'), (11, 33, 20, 'ml'),
  (12, 8, 50, 'g'), (12, 3, 20, 'g'), (12, 42, 10, 'g'), (12, 43, 5, 'g'), (12, 38, 100, 'ml'), (12, 34, 300, 'ml'),
  (12, 37, 8, 'g'),
  (13, 17, 400, 'g'), (13, 37, 6, 'g'),
  (14, 25, 200, 'g'), (14, 42, 1, 'g'), (14, 43, 0.5, 'g'), (14, 33, 5, 'ml'),
  (15, 15, 2500, 'g'), (15, 2, 400, 'g'), (15, 39, 300, 'ml'), (15, 46, 2, 'g'), (15, 37, 20, 'g'), (15, 41, 3, 'g'),
  (16, 18, 1, 'unit'),
  (17, 14, 250, 'g'), (17, 9, 1, 'unit'), (17, 33, 10, 'ml'), (17, 37, 3, 'g'), (17, 41, 1, 'g'),
  (18, 28, 250, 'g'), (18, 36, 200, 'g'), (18, 26, 3, 'unit'), (18, 24, 150, 'g'), (18, 9, 1, 'unit'), (18, 23, 100, 'ml'),
  (19, 49, 120, 'g'), (19, 5, 150, 'g'), (19, 26, 1, 'unit'), (19, 48, 20, 'g'), (19, 33, 10, 'ml'), (19, 37, 2, 'g'),
  (20, 27, 120, 'g'), (20, 26, 1, 'unit'), (20, 10, 200, 'g'), (20, 20, 20, 'g'), (20, 24, 20, 'g'), (20, 44, 0.5, 'g');

insert into recipes.recipes (id, group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id)
select format('00000000-0000-4000-8000-%s', lpad((1100 + r.n)::text, 12, '0'))::uuid, '00000000-0000-4000-8000-000000000001',
       case when r.brand is not null then format('00000000-0000-4000-8000-%s', lpad((100 + r.brand)::text, 12, '0'))::uuid end,
       case when r.restaurant is not null then format('00000000-0000-4000-8000-%s', lpad(r.restaurant::text, 12, '0'))::uuid end,
       case when r.restaurant is not null then 'restaurant' when r.brand is not null then 'brand' else 'group' end::recipes.recipe_scope,
       r.code, r.name, r.kind::recipes.recipe_type,
       format('00000000-0000-4000-8000-%s', lpad((1060 + r.category)::text, 12, '0'))::uuid
  from seed_recipes r;

insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions,
                                     portion_grams, description)
select format('00000000-0000-4000-8000-%s', lpad((1200 + r.n)::text, 12, '0'))::uuid, '00000000-0000-4000-8000-000000000001',
       format('00000000-0000-4000-8000-%s', lpad((1100 + r.n)::text, 12, '0'))::uuid, 1, r.yield_qty, u.id, r.portions,
       r.portion_grams, 'Receta de prueba (DEMO).'
  from seed_recipes r join catalog.units u on u.code = r.yield_unit;

insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select '00000000-0000-4000-8000-000000000001', format('00000000-0000-4000-8000-%s', lpad((1200 + l.n)::text, 12, '0'))::uuid,
       row_number() over (partition by l.n order by l.ord), format('00000000-0000-4000-8000-%s', lpad((800 + l.ingredient)::text, 12, '0'))::uuid,
       l.qty, u.id
  from seed_recipe_lines l join catalog.units u on u.code = l.unit;

-- Subrecetas (etapa 2.2 B): la Lasaña usa la Salsa bolognesa y la Salsa blanca; los Ravioles, la bolognesa.
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, sub_recipe_id, quantity, unit_id, quantity_basis)
select '00000000-0000-4000-8000-000000000001', format('00000000-0000-4000-8000-%s', lpad((1200 + x.n)::text, 12, '0'))::uuid,
       x.line, format('00000000-0000-4000-8000-%s', lpad((1100 + x.sub)::text, 12, '0'))::uuid, x.qty, u.id, 'finished'
  from (values (10, 4, 2, 1.6, 'kg'), (10, 5, 3, 1, 'l'), (8, 6, 2, 150, 'g')) as x (n, line, sub, qty, unit)
  join catalog.units u on u.code = x.unit;

-- Pasos: preparar, el paso propio de cada receta y terminar (uno espera al otro). La bolognesa, en paralelo.
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes, passive_minutes)
select '00000000-0000-4000-8000-000000000001', format('00000000-0000-4000-8000-%s', lpad((1200 + r.n)::text, 12, '0'))::uuid,
       s.step, s.kind::recipes.step_kind, s.instructions, s.active, s.passive
  from seed_recipes r
 cross join lateral (values
   (1, 'preparation', 'Pesar y preparar los ingredientes.', 10, 0),
   (2, 'cooking', r.cook_text, r.active, r.passive),
   (3, case when r.kind = 'dish' then 'plating' else 'cooling' end,
    case when r.kind = 'dish' then 'Emplatar y servir.' else 'Enfriar, rotular y guardar según el procedimiento validado.' end, 5, 0)
 ) as s (step, kind, instructions, active, passive)
 where r.n <> 2;
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes, passive_minutes)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000001202', 1, 'preparation',
   'Picar la cebolla y la zanahoria.', 20, 0),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000001202', 2, 'cooking',
   'Dorar la carne, sumar el vino y el tomate, y cocinar a fuego bajo.', 15, 45),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000001202', 3, 'cooking',
   'Rehogar la cebolla y la zanahoria en otra olla.', 30, 0),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000001202', 4, 'cooking',
   'Unir todo, ajustar la sal y enfriar.', 10, 0);
insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
select '00000000-0000-4000-8000-000000000001', s.id, d.id
  from (values (2, 1), (3, 2)) as x (step, dep)
  join recipes.recipe_steps s on s.step_number = x.step
  join recipes.recipe_steps d on d.recipe_version_id = s.recipe_version_id and d.step_number = x.dep
 where s.recipe_version_id <> '00000000-0000-4000-8000-000000001202';
insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
select '00000000-0000-4000-8000-000000000001', s.id, d.id
  from (values (2, 1), (3, 1), (4, 2), (4, 3)) as x (step, dep)
  join recipes.recipe_steps s on s.recipe_version_id = '00000000-0000-4000-8000-000000001202' and s.step_number = x.step
  join recipes.recipe_steps d on d.recipe_version_id = s.recipe_version_id and d.step_number = x.dep;

-- Publicadas: recorren los estados de siempre. Las aprueba la Chef de Demo Pastas o el Chef del grupo.
update recipes.recipe_versions v set status = 'in_review'
  from seed_recipes r where v.id = format('00000000-0000-4000-8000-%s', lpad((1200 + r.n)::text, 12, '0'))::uuid and r.published;
update recipes.recipe_versions v
   set status = 'approved',
       approved_by = case when r.brand = 1 then '00000000-0000-4000-8000-000000000405'
                          else '00000000-0000-4000-8000-000000000413' end::uuid
  from seed_recipes r where v.id = format('00000000-0000-4000-8000-%s', lpad((1200 + r.n)::text, 12, '0'))::uuid and r.published;
update recipes.recipe_versions v set status = 'published', published_at = now()
  from seed_recipes r where v.id = format('00000000-0000-4000-8000-%s', lpad((1200 + r.n)::text, 12, '0'))::uuid and r.published;

-- Asignaciones: las maestras a los locales de Pastas y Parrilla; las de marca, a sus locales.
insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
select '00000000-0000-4000-8000-000000000001', format('00000000-0000-4000-8000-%s', lpad((1100 + r.n)::text, 12, '0'))::uuid,
       rest.id, current_date - 30
  from seed_recipes r
  join org.restaurants rest
    on case when r.restaurant is not null
              then rest.id = ('00000000-0000-4000-8000-' || lpad(r.restaurant::text, 12, '0'))::uuid
            when r.brand is not null
              then rest.brand_id = ('00000000-0000-4000-8000-' || lpad((100 + r.brand)::text, 12, '0'))::uuid
            else rest.brand_id in ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000102') end;

-- Una variante local (etapa 2.2 B): los Ñoquis de Demo Pastas Norte llevan menos harina y queso arriba.
-- Publicada, así que ese local dejó de usar la maestra.
insert into recipes.recipes (id, group_id, brand_id, restaurant_id, scope_type, code, name, recipe_type, category_id,
                             variant_of_recipe_id)
values ('00000000-0000-4000-8000-000000001121', '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-000000000202', 'restaurant', 'DEMO-LOC-02',
        'Ñoquis de papa (Norte)', 'dish', '00000000-0000-4000-8000-000000001062', '00000000-0000-4000-8000-000000001109');
insert into recipes.recipe_versions (id, group_id, recipe_id, version_number, yield_quantity, yield_unit_id, portions,
                                     portion_grams, description, change_summary)
select '00000000-0000-4000-8000-000000001221', group_id, '00000000-0000-4000-8000-000000001121', 1, yield_quantity,
       yield_unit_id, portions, portion_grams, description, 'Variante de «Ñoquis de papa» (v1) para Demo Pastas Norte.'
  from recipes.recipe_versions where id = '00000000-0000-4000-8000-000000001209';
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select group_id, '00000000-0000-4000-8000-000000001221', line_order, ingredient_id,
       case when ingredient_id = '00000000-0000-4000-8000-000000000827' then 200 else quantity end, unit_id
  from recipes.recipe_components where recipe_version_id = '00000000-0000-4000-8000-000000001209';
insert into recipes.recipe_components (group_id, recipe_version_id, line_order, ingredient_id, quantity, unit_id)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000001221', 5,
       '00000000-0000-4000-8000-000000000820', 80, id
  from catalog.units where code = 'g';
insert into recipes.recipe_steps (group_id, recipe_version_id, step_number, kind, instructions, active_minutes, passive_minutes)
select group_id, '00000000-0000-4000-8000-000000001221', step_number, kind, instructions, active_minutes, passive_minutes
  from recipes.recipe_steps where recipe_version_id = '00000000-0000-4000-8000-000000001209';
insert into recipes.recipe_step_dependencies (group_id, step_id, depends_on_step_id)
select '00000000-0000-4000-8000-000000000001', s.id, d.id
  from (values (2, 1), (3, 2)) as x (step, dep)
  join recipes.recipe_steps s on s.recipe_version_id = '00000000-0000-4000-8000-000000001221' and s.step_number = x.step
  join recipes.recipe_steps d on d.recipe_version_id = s.recipe_version_id and d.step_number = x.dep;
update recipes.recipe_versions set status = 'in_review' where id = '00000000-0000-4000-8000-000000001221';
update recipes.recipe_versions set status = 'approved', approved_by = '00000000-0000-4000-8000-000000000405'
 where id = '00000000-0000-4000-8000-000000001221';
update recipes.recipe_versions set status = 'published', published_at = now() where id = '00000000-0000-4000-8000-000000001221';
insert into recipes.recipe_assignments (group_id, recipe_id, restaurant_id, valid_from)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000001121',
        '00000000-0000-4000-8000-000000000202', current_date - 7);
update recipes.recipe_assignments set valid_to = current_date - 7
 where recipe_id = '00000000-0000-4000-8000-000000001109' and restaurant_id = '00000000-0000-4000-8000-000000000202';

-- Un aviso de cambio de receta sin leer para el Chef del grupo (etapa 2.2 B, ADR-0026).
insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
values ('00000000-0000-4000-8000-000000000413', '00000000-0000-4000-8000-000000000001', 'recipe_changed',
        'Cambió «Salsa bolognesa» (v1)',
        'Las recetas que la usan ya usan la versión nueva. Revisá si hace falta ajustar algo.',
        '/recetas/00000000-0000-4000-8000-000000001102');

-- ---------------------------------------------------------------------------
-- Precios (Fase 2, etapa 2.1 C; ADR-0029). Todo ficticio: razones sociales con CUIT inventado y
-- valores simbólicos (source test_value), como pidió Soy mientras no lleguen las facturas.
-- Ids fijos: razones sociales ...0015NN.
-- ---------------------------------------------------------------------------
insert into org.legal_entities (id, group_id, name, tax_id, vat_condition) values
  ('00000000-0000-4000-8000-000000001501', '00000000-0000-4000-8000-000000000001', 'Demo Gastronomía S.R.L. (ficticia)', '30000000001', 'registered'),
  ('00000000-0000-4000-8000-000000001502', '00000000-0000-4000-8000-000000000001', 'Demo Café de Lucía (ficticia)', '20000000002', 'monotax');
update org.restaurants set legal_entity_id = '00000000-0000-4000-8000-000000001501'
 where id in ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202', '00000000-0000-4000-8000-000000000203');
update org.restaurants set legal_entity_id = '00000000-0000-4000-8000-000000001502'
 where id = '00000000-0000-4000-8000-000000000204';

-- Precios de grupo, con factura y 21 % de IVA incluido, de los productos de las materias primas 1 a 50. Las 25, 28 y
-- 29 no tienen precio: sus recetas salen incompletas, y las pruebas proponen ahí un primer precio o cambian su unidad.
insert into costing.price_records (group_id, purchase_product_id, supplier_id, scope_type, valid_from, package_price,
                                   document_type, vat_rate, price_includes_vat, source, notes)
select p.group_id, p.id, p.supplier_id, 'group', current_date - 10, 1000 * s.n + 500, 'invoice', 21, true, 'test_value',
       'Valor simbólico de prueba'
  from seed_ingredients s
  join catalog.purchase_products p on p.code = format('DEMO-PROD-%s', lpad(s.n::text, 3, '0'))
 where s.n between 1 and 50 and s.n not in (7, 20, 25, 28, 29);
-- La albahaca, "precio ingresado" (sin factura): el precio es el final.
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type,
                                   source, notes)
select group_id, id, 'group', current_date - 10, 2500, 'no_invoice', 'test_value', 'Valor simbólico de prueba, sin factura'
  from catalog.purchase_products where code = 'DEMO-PROD-007';
-- El queso rallado, con un precio viejo: desactualizado.
insert into costing.price_records (group_id, purchase_product_id, scope_type, valid_from, package_price, document_type,
                                   vat_rate, source, notes)
select group_id, id, 'group', current_date - 60, 9000, 'invoice', 21, 'test_value', 'Valor simbólico de prueba, viejo'
  from catalog.purchase_products where code = 'DEMO-PROD-020';
-- La mozzarella: Demo Pastas tiene su propio precio (los locales de Pastas no heredan el del grupo).
insert into costing.price_records (group_id, purchase_product_id, scope_type, brand_id, valid_from, package_price,
                                   document_type, vat_rate, source, notes)
select group_id, id, 'brand', '00000000-0000-4000-8000-000000000101', current_date - 5, 36000, 'invoice', 21, 'test_value',
       'Valor simbólico de prueba, de la marca'
  from catalog.purchase_products where code = 'DEMO-PROD-019';

-- Un aviso de cambio de costo sin leer para el Controller (ADR-0032).
insert into core.notifications (recipient_user_id, group_id, kind, title, body, link)
values ('00000000-0000-4000-8000-000000000407', '00000000-0000-4000-8000-000000000001', 'recipe_cost_changed',
        'Cambió el costo de «Salsa bolognesa»', '2 recetas en 1 de tus locales.',
        '/costos/00000000-0000-4000-8000-000000001108?local=00000000-0000-4000-8000-000000000201');

-- Los costos de las recetas: en la base los calcula la cola cada minuto.
select costing.process_recalc_queue(10000);

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

-- Las materias primas parecidas se calculan de noche: acá, para que se vean sin esperar.
refresh materialized view reporting.mv_ingredient_twins;

commit;
