-- Prueba de la Fase 2 para Soy en staging: materias primas, precios, recetas y costos. SOLO DATOS INVENTADOS.
-- Lo corre el flujo "Publicar en staging" de GitHub Actions, a pedido, con psql 15 o más, DESPUÉS de
-- demo-data.sql (necesita el Grupo Demo y sus personas de prueba):
--   psql -X --no-password -f supabase/staging/demo-recipes.sql "$STAGING_DB_URL"
--
-- Todo se carga con las MISMAS funciones que usa la app y con la sesión de cada persona de prueba, como las
-- órdenes de compra del seed: Compras crea las materias primas y propone los precios, la Controller los aprueba,
-- la Chef de Demo Pastas arma las recetas y las manda a revisión, y la Directora de marca las publica. Así cada
-- paso pasa por los permisos, los códigos automáticos, las versiones, las aprobaciones y la auditoría.
--
-- Dos casos a propósito, para que se vea que el sistema avisa en vez de inventar un número:
--   - la salvia tiene un precio viejo (60 días o el doble del plazo de vencimiento): los Ñoquis de espinaca salen «desactualizados»;
--   - el azafrán no tiene precio: el Risotto alla milanese sale «incompleto» (sin costo, nunca $ 0).
--
-- Se puede correr más de una vez: si ya se cargó, no cambia nada. Si choca con algo que ya está en staging
-- (un nombre o un código), frena sin tocar nada y dice qué.
-- Con DRY_RUN definida (con cualquier valor, también 0) hace todo y al final lo deshace (rollback): sirve para probarlo
-- en la base local. En Actions no se define.

\set ON_ERROR_STOP on

\getenv run_id GITHUB_RUN_ID
\getenv dry_run DRY_RUN
\if :{?run_id}
  \set change_reason 'Prueba de la Fase 2 para Soy (corrida ' :run_id ' de GitHub Actions)'
\else
  \set change_reason 'Prueba de la Fase 2 para Soy (a mano)'
\endif

select exists (select 1 from org.groups where id = '00000000-0000-4000-8000-000000000001' and deleted_at is null)
  as group_loaded \gset
\if :group_loaded
\else
  do $$ begin raise exception 'Falta el Grupo Demo: primero cargá las personas y datos de prueba (demo-data.sql).'; end $$;
\endif

-- La marca de esta carga: la nota de sus materias primas.
select exists (select 1 from catalog.ingredients
                where group_id = '00000000-0000-4000-8000-000000000001' and deleted_at is null
                  and notes = 'Prueba de la Fase 2 para Soy') as recipes_loaded \gset
\if :recipes_loaded
  \echo 'La prueba de la Fase 2 ya estaba cargada: no se cambia nada.'
  \quit
\endif

begin;

select set_config('pru.reason', :'change_reason', true);

-- La sesión de una persona de prueba, como la arma la app al entrar (con doble verificación).
create function pg_temp.as_user(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
                    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true)
$$;

-- Proveedores inventados. CUIT con dígito verificador válido, en el rango ficticio del seed (30-500000xx), sin repetir
-- los que ya usa el seed (011, 029, 038, 046, 054 y 070).
create temporary table pru_suppliers (n int, name text, tax_id text) on commit drop;
insert into pru_suppliers values
  (1, 'Verdulería La Huerta (ficticia)', '30500000119'),
  (2, 'Frigorífico El Corral (ficticio)', '30500000127'),
  (3, 'Distribuidora Trattoria (ficticia)', '30500000135');

-- Materias primas: rubro de Soy, medida de receta, proveedor, envase y precio del envase con IVA (inventado).
-- days_ago: hace cuántos días vale el precio (hoy, salvo la salvia, que se ajusta al plazo de vencimiento del grupo).
-- Sin precio (null): el azafrán.
create temporary table pru_ingredients (n int, name text, rubro text, unit text, supplier int, description text,
  package text, units int, content numeric, content_unit text, price numeric, days_ago int) on commit drop;
insert into pru_ingredients values
  (1,  'Cebolla morada',              'MP-VER', 'g',    1, 'Cebolla morada, por kg',            'kg',   1,  1000, 'g',     1800, 0),
  (2,  'Ajo morado',                  'MP-VER', 'g',    1, 'Ajo morado, por kg',                'kg',   1,  1000, 'g',     6500, 0),
  (3,  'Apio',                        'MP-VER', 'g',    1, 'Apio, por kg',                      'kg',   1,  1000, 'g',     2900, 0),
  (4,  'Puerro',                      'MP-VER', 'g',    1, 'Puerro, por kg',                    'kg',   1,  1000, 'g',     3800, 0),
  (5,  'Tomate cherry',               'MP-VER', 'g',    1, 'Tomate cherry, por kg',             'kg',   1,  1000, 'g',     7500, 0),
  (6,  'Berenjena',                   'MP-VER', 'g',    1, 'Berenjena, por kg',                 'kg',   1,  1000, 'g',     3200, 0),
  (7,  'Espinaca',                    'MP-VER', 'g',    1, 'Espinaca, por kg',                  'kg',   1,  1000, 'g',     4500, 0),
  (8,  'Romero fresco',               'MP-HIE', 'g',    1, 'Romero fresco, atado de 100 g',     'pack', 1,   100, 'g',     2200, 0),
  (9,  'Salvia fresca',               'MP-HIE', 'g',    1, 'Salvia fresca, atado de 100 g',     'pack', 1,   100, 'g',     2800, 60),
  (10, 'Osobuco',                     'MP-CAR', 'g',    2, 'Osobuco, por kg',                   'kg',   1,  1000, 'g',     9800, 0),
  (11, 'Peceto',                      'MP-CAR', 'g',    2, 'Peceto, por kg',                    'kg',   1,  1000, 'g',    16500, 0),
  (12, 'Muslo de pollo',              'MP-CAR', 'g',    2, 'Muslo de pollo, por kg',            'kg',   1,  1000, 'g',     5900, 0),
  (13, 'Panceta ahumada',             'MP-FIA', 'g',    2, 'Panceta ahumada, por kg',           'kg',   1,  1000, 'g',    18000, 0),
  (14, 'Queso parmesano',             'MP-LAC', 'g',    3, 'Queso parmesano, horma de 4 kg',    'wheel', 1, 4000, 'g',   128000, 0),
  (15, 'Queso pategrás',              'MP-LAC', 'g',    3, 'Queso pategrás, por kg',            'kg',   1,  1000, 'g',    14500, 0),
  (16, 'Manteca sin sal',             'MP-LAC', 'g',    3, 'Manteca sin sal, caja de 5 kg',     'box',  1,  5000, 'g',    52000, 0),
  (17, 'Crema para cocinar',          'MP-LAC', 'ml',   3, 'Crema para cocinar, caja de 12 × 1 l', 'box', 12, 1000, 'ml',  66000, 0),
  (18, 'Huevo de campo',              'MP-HUE', 'unit', 3, 'Huevo de campo, maple de 30',       'box', 30,     1, 'unit',  7800, 0),
  (19, 'Harina 00 italiana',          'MP-HAR', 'g',    3, 'Harina 00 italiana, bolsa de 25 kg', 'bag', 1, 25000, 'g',    32000, 0),
  (20, 'Semolín de trigo candeal',    'MP-HAR', 'g',    3, 'Semolín de trigo candeal, bolsa de 5 kg', 'bag', 1, 5000, 'g', 9500, 0),
  (21, 'Arroz arborio',               'MP-ALM', 'g',    3, 'Arroz arborio, bolsa de 5 kg',      'bag',  1,  5000, 'g',    24000, 0),
  (22, 'Aceite de oliva extra virgen', 'MP-ACE', 'ml',  3, 'Aceite de oliva extra virgen, bidón de 5 l', 'jug', 1, 5000, 'ml', 58000, 0),
  (23, 'Tomate pelado en lata',       'MP-CON', 'g',    3, 'Tomate pelado, lata de 2,5 kg',     'can',  1,  2500, 'g',     6900, 0),
  (24, 'Puré de tomate',              'MP-CON', 'g',    3, 'Puré de tomate, caja de 12 × 520 g', 'box', 12,  520, 'g',    16800, 0),
  (25, 'Vino blanco seco',            'MP-VIN', 'ml',   3, 'Vino blanco seco, caja de 6 × 750 ml', 'box', 6, 750, 'ml',   27000, 0),
  (26, 'Sal gruesa',                  'MP-ESP', 'g',    3, 'Sal gruesa, bolsa de 5 kg',         'bag',  1,  5000, 'g',     3500, 0),
  (27, 'Pimienta blanca molida',      'MP-ESP', 'g',    3, 'Pimienta blanca molida, paquete de 500 g', 'pack', 1, 500, 'g', 12000, 0),
  (28, 'Azafrán en hebras',           'MP-ESP', 'g',    3, 'Azafrán en hebras, sobre de 1 g',   'pack', 1,     1, 'g',     null, null);

-- Recetas de Demo Pastas: 4 preparaciones (1 a 4) y 9 platos (5 a 13).
create temporary table pru_recipes (n int, name text, kind text, rubro text, yield_qty numeric, yield_unit text,
  portions int, description text, steps jsonb) on commit drop;
insert into pru_recipes values
  (1, 'Salsa pomodoro', 'preparation', 'SR-SAL', 2000, 'g', null, 'Salsa de tomate de la casa, base de varios platos.',
   '[{"kind": "preparation", "instructions": "Picar la cebolla y el ajo.", "active_minutes": 10},
     {"kind": "cooking", "instructions": "Rehogar en el aceite, sumar el tomate y la sal y cocinar a fuego bajo.", "active_minutes": 10, "passive_minutes": 40}]'),
  (2, 'Ragú de osobuco', 'preparation', 'SR-SAL', 2500, 'g', null, 'Ragú braseado de osobuco, desmenuzado.',
   '[{"kind": "preparation", "instructions": "Cortar las verduras en brunoise y sellar el osobuco.", "active_minutes": 25},
     {"kind": "cooking", "instructions": "Desglasar con el vino, sumar el puré y brasear hasta que la carne se desarme.", "active_minutes": 15, "passive_minutes": 180},
     {"kind": "cooling", "instructions": "Desmenuzar, enfriar y rotular.", "active_minutes": 15, "passive_minutes": 60}]'),
  (3, 'Masa al huevo', 'preparation', 'SR-MAS', 1400, 'g', null, 'Masa fresca para pastas largas.',
   '[{"kind": "preparation", "instructions": "Formar la corona con la harina y el semolín, sumar los huevos y la sal y amasar.", "active_minutes": 20},
     {"kind": "resting", "instructions": "Dejar descansar tapada.", "passive_minutes": 30},
     {"kind": "preparation", "instructions": "Estirar y cortar según el plato.", "active_minutes": 25}]'),
  (4, 'Fondo de verduras', 'preparation', 'SR-FON', 3000, 'ml', null, 'Caldo claro de verduras para risottos.',
   '[{"kind": "cooking", "instructions": "Cubrir las verduras con agua fría, sumar el romero y la sal y hervir suave.", "active_minutes": 10, "passive_minutes": 50},
     {"kind": "cooling", "instructions": "Colar y enfriar.", "active_minutes": 5, "passive_minutes": 30}]'),
  (5, 'Tagliatelle al ragú de osobuco', 'dish', 'PL-PAS', 1, 'portion', 1, 'Tagliatelle frescos con ragú de osobuco y parmesano.',
   '[{"kind": "cooking", "instructions": "Hervir la pasta 3 minutos y saltear con el ragú y la manteca.", "active_minutes": 6},
     {"kind": "plating", "instructions": "Emplatar y terminar con parmesano.", "active_minutes": 1}]'),
  (6, 'Fettuccine al pomodoro', 'dish', 'PL-PAS', 1, 'portion', 1, 'Fettuccine frescos con salsa pomodoro.',
   '[{"kind": "cooking", "instructions": "Hervir la pasta y saltear con la salsa.", "active_minutes": 5},
     {"kind": "plating", "instructions": "Terminar con parmesano y un hilo de oliva.", "active_minutes": 1}]'),
  (7, 'Tagliatelle carbonara', 'dish', 'PL-PAS', 1, 'portion', 1, 'Con panceta ahumada, yema y parmesano.',
   '[{"kind": "cooking", "instructions": "Dorar la panceta. Hervir la pasta y ligar fuera del fuego con el huevo y el queso.", "active_minutes": 8},
     {"kind": "plating", "instructions": "Emplatar y terminar con pimienta.", "active_minutes": 1}]'),
  (8, 'Fettuccine Alfredo', 'dish', 'PL-PAS', 1, 'portion', 1, 'Fettuccine con crema, manteca y parmesano.',
   '[{"kind": "cooking", "instructions": "Reducir la crema con la manteca y ligar la pasta con el parmesano.", "active_minutes": 6},
     {"kind": "plating", "instructions": "Emplatar.", "active_minutes": 1}]'),
  (9, 'Ñoquis de espinaca con manteca y salvia', 'dish', 'PL-PAS', 4, 'portion', 4, 'Ñoquis verdes con manteca de salvia (rinde 4 porciones).',
   '[{"kind": "preparation", "instructions": "Blanquear y picar la espinaca, formar la masa con la harina, el huevo y el queso y cortar los ñoquis.", "active_minutes": 40},
     {"kind": "cooking", "instructions": "Hervir hasta que suban y saltear en la manteca con la salvia.", "active_minutes": 6},
     {"kind": "plating", "instructions": "Emplatar y terminar con parmesano.", "active_minutes": 2}]'),
  (10, 'Risotto alla milanese', 'dish', 'PL-RIS', 1, 'portion', 1, 'Risotto con azafrán, mantecado con parmesano.',
   '[{"kind": "cooking", "instructions": "Nacarar el arroz con la cebolla, desglasar con el vino y sumar el fondo de a poco con el azafrán.", "active_minutes": 18},
     {"kind": "plating", "instructions": "Mantecar fuera del fuego con la manteca y el parmesano y emplatar.", "active_minutes": 2}]'),
  (11, 'Pollo al romero con tomates cherry', 'dish', 'PL-CAR', 1, 'portion', 1, 'Muslo de pollo al horno con romero y cherrys.',
   '[{"kind": "preparation", "instructions": "Condimentar el pollo con el ajo, el romero, la sal y el aceite.", "active_minutes": 5},
     {"kind": "cooking", "instructions": "Hornear a 200 °C y sumar los tomates los últimos 10 minutos.", "active_minutes": 3, "passive_minutes": 35},
     {"kind": "plating", "instructions": "Emplatar con el jugo de cocción.", "active_minutes": 1}]'),
  (12, 'Lasaña de berenjenas', 'dish', 'PL-VEG', 1, 'portion', 1, 'Capas de berenjena grillada, pomodoro y quesos.',
   '[{"kind": "preparation", "instructions": "Cortar y grillar la berenjena.", "active_minutes": 12},
     {"kind": "cooking", "instructions": "Armar las capas con la salsa y los quesos y gratinar.", "active_minutes": 5, "passive_minutes": 20},
     {"kind": "plating", "instructions": "Porcionar y emplatar.", "active_minutes": 1}]'),
  (13, 'Peceto braseado al vino blanco', 'dish', 'PL-CAR', 1, 'portion', 1, 'Peceto sellado y braseado con cebolla y vino blanco.',
   '[{"kind": "cooking", "instructions": "Sellar el peceto, sumar la cebolla y el vino y brasear tapado.", "active_minutes": 10, "passive_minutes": 90},
     {"kind": "plating", "instructions": "Fetear y salsear con el fondo de cocción.", "active_minutes": 3}]');

-- Líneas: materia prima (ingredient) o preparación (sub), cantidad y unidad. Las preparaciones van en cantidad
-- terminada, en la unidad de su rendimiento.
create temporary table pru_lines (recipe int, line int, ingredient int, sub int, qty numeric, unit text) on commit drop;
insert into pru_lines values
  (1, 1, 23, null, 2500, 'g'), (1, 2, 1, null, 300, 'g'), (1, 3, 2, null, 20, 'g'), (1, 4, 22, null, 80, 'ml'),
  (1, 5, 26, null, 15, 'g'),
  (2, 1, 10, null, 2000, 'g'), (2, 2, 1, null, 300, 'g'), (2, 3, 3, null, 150, 'g'), (2, 4, 4, null, 150, 'g'),
  (2, 5, 25, null, 300, 'ml'), (2, 6, 24, null, 1040, 'g'), (2, 7, 22, null, 60, 'ml'), (2, 8, 26, null, 20, 'g'),
  (2, 9, 27, null, 3, 'g'),
  (3, 1, 19, null, 1000, 'g'), (3, 2, 20, null, 200, 'g'), (3, 3, 18, null, 10, 'unit'), (3, 4, 26, null, 10, 'g'),
  (4, 1, 1, null, 200, 'g'), (4, 2, 3, null, 200, 'g'), (4, 3, 4, null, 200, 'g'), (4, 4, 8, null, 2, 'g'),
  (4, 5, 26, null, 10, 'g'),
  (5, 1, null, 3, 180, 'g'), (5, 2, null, 2, 220, 'g'), (5, 3, 14, null, 15, 'g'), (5, 4, 16, null, 10, 'g'),
  (6, 1, null, 3, 180, 'g'), (6, 2, null, 1, 180, 'g'), (6, 3, 14, null, 10, 'g'), (6, 4, 22, null, 10, 'ml'),
  (7, 1, null, 3, 180, 'g'), (7, 2, 13, null, 60, 'g'), (7, 3, 18, null, 1, 'unit'), (7, 4, 14, null, 25, 'g'),
  (7, 5, 27, null, 1, 'g'),
  (8, 1, null, 3, 180, 'g'), (8, 2, 17, null, 100, 'ml'), (8, 3, 16, null, 15, 'g'), (8, 4, 14, null, 25, 'g'),
  (9, 1, 7, null, 400, 'g'), (9, 2, 19, null, 250, 'g'), (9, 3, 18, null, 2, 'unit'), (9, 4, 14, null, 60, 'g'),
  (9, 5, 16, null, 80, 'g'), (9, 6, 9, null, 10, 'g'), (9, 7, 26, null, 8, 'g'),
  (10, 1, 21, null, 90, 'g'), (10, 2, null, 4, 300, 'ml'), (10, 3, 28, null, 0.1, 'g'), (10, 4, 16, null, 20, 'g'),
  (10, 5, 14, null, 20, 'g'), (10, 6, 25, null, 30, 'ml'), (10, 7, 1, null, 20, 'g'),
  (11, 1, 12, null, 350, 'g'), (11, 2, 5, null, 120, 'g'), (11, 3, 8, null, 3, 'g'), (11, 4, 22, null, 20, 'ml'),
  (11, 5, 2, null, 5, 'g'), (11, 6, 26, null, 4, 'g'),
  (12, 1, 6, null, 250, 'g'), (12, 2, null, 1, 150, 'g'), (12, 3, 15, null, 80, 'g'), (12, 4, 14, null, 20, 'g'),
  (12, 5, 22, null, 20, 'ml'),
  (13, 1, 11, null, 250, 'g'), (13, 2, 25, null, 50, 'ml'), (13, 3, 1, null, 50, 'g'), (13, 4, 22, null, 10, 'ml'),
  (13, 5, 26, null, 3, 'g');

create temporary table pru_ids (kind text, n int, id uuid, version_id uuid) on commit drop;

do $$
declare
  v_group    constant uuid := '00000000-0000-4000-8000-000000000001';
  v_pastas   constant uuid := '00000000-0000-4000-8000-000000000101';
  v_centro   constant uuid := '00000000-0000-4000-8000-000000000201';  -- Demo Pastas Centro
  v_buyer    constant uuid := '00000000-0000-4000-8000-000000000408';  -- Pablo, Compras (grupo)
  v_ctrl     constant uuid := '00000000-0000-4000-8000-000000000407';  -- Camila, Controller (grupo)
  v_chef     constant uuid := '00000000-0000-4000-8000-000000000405';  -- Carla, Chef de Demo Pastas
  v_director constant uuid := '00000000-0000-4000-8000-000000000403';  -- Marta, Directora de Demo Pastas
  v_reason   constant text := current_setting('pru.reason');
  v_missing  text;
  v_id       uuid;
  v_request  uuid;
  v_res      jsonb;
  v_today    date := recipes.today();
  v_round    int;
  r          record;
begin
  -- Guardas: las personas de prueba con su rol, los rubros de Soy y nada que choque con lo que ya está.
  select string_agg(x.who, ', ') into v_missing
    from (values (v_buyer, 'purchasing', null::uuid, 'Compras'), (v_ctrl, 'controller', null, 'Controller'),
                 (v_chef, 'executive_chef', v_pastas, 'Chef de Demo Pastas'),
                 (v_director, 'brand_director', v_pastas, 'Directora de Demo Pastas')) as x (id, role, brand, who)
   where not exists (select 1 from core.user_role_assignments a join core.roles ro on ro.id = a.role_id
                      where a.user_id = x.id and ro.code = x.role and a.group_id = v_group
                        and a.brand_id is not distinct from x.brand and a.deleted_at is null
                        and a.valid_from <= now() and (a.valid_until is null or a.valid_until > now()))
      or not exists (select 1 from core.user_profiles u
                      where u.id = x.id and u.status = 'active' and u.deleted_at is null
                        and (u.locked_until is null or u.locked_until <= now()));
  if v_missing is not null then
    raise exception 'Faltan personas de prueba activas y con su rol: %. Cargá primero demo-data.sql.', v_missing;
  end if;

  if (select count(*) from org.restaurants
       where id in ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-000000000202')
         and brand_id = v_pastas and status = 'active' and deleted_at is null) <> 2 then
    raise exception 'Faltan los locales Demo Pastas Centro y Norte, activos.';
  end if;

  -- Los rubros de materias primas en su tabla y los de recetas en la suya, activos.
  select string_agg(distinct c.code, ', ') into v_missing
    from (select rubro as code, 'ingredient' as kind from pru_ingredients
          union select rubro, 'recipe' from pru_recipes) c
   where (c.kind = 'ingredient'
          and not exists (select 1 from catalog.ingredient_categories k
                           where k.group_id = v_group and k.code = c.code and k.parent_id is null
                             and k.is_active and k.deleted_at is null))
      or (c.kind = 'recipe'
          and not exists (select 1 from recipes.recipe_categories k
                           where k.group_id = v_group and k.code = c.code and k.parent_id is null
                             and k.is_active and k.deleted_at is null));
  if v_missing is not null then
    raise exception 'Faltan estos rubros activos en el grupo: %.', v_missing;
  end if;

  -- La salvia tiene que salir desactualizada con la configuración de este grupo: su precio es del doble del plazo
  -- de su rubro (o del grupo, o 30 días), y nunca de menos de 60 días.
  update pru_ingredients p
     set days_ago = greatest(2 * coalesce(c.stale_price_days, s.stale_days, 30), 60)
    from catalog.ingredient_categories c
    left join costing.price_settings s on s.group_id = c.group_id
   where p.n = 9 and c.group_id = v_group and c.code = p.rubro and c.parent_id is null and c.deleted_at is null;

  select string_agg(i.name, ', ') into v_missing
    from pru_ingredients p join catalog.ingredients i
      on i.group_id = v_group and lower(i.name) = lower(p.name) and i.deleted_at is null;
  if v_missing is not null then
    raise exception 'Ya hay materias primas con estos nombres: %. No se cargó nada.', v_missing;
  end if;
  select string_agg(s.name, ', ') into v_missing
    from pru_suppliers p join catalog.suppliers s
      on s.group_id = v_group and s.deleted_at is null
     and (lower(s.name) = lower(p.name) or core.normalize_cuit(s.tax_id) = p.tax_id);
  if v_missing is not null then
    raise exception 'Ya hay proveedores con ese nombre o CUIT: %. No se cargó nada.', v_missing;
  end if;
  if exists (select 1 from catalog.purchase_products where group_id = v_group and code like 'PRU-%' and deleted_at is null) then
    raise exception 'Ya hay productos de compra con código PRU-. No se cargó nada.';
  end if;
  if exists (select 1 from recipes.recipes r2 join pru_recipes p on lower(p.name) = lower(r2.name)
              where r2.group_id = v_group and r2.deleted_at is null) then
    raise exception 'Ya hay recetas con alguno de estos nombres. No se cargó nada.';
  end if;

  -- 1. Compras: proveedores, materias primas, productos de compra y precios propuestos.
  perform pg_temp.as_user(v_buyer);
  for r in select * from pru_suppliers order by n loop
    v_id := purchasing.create_supplier(v_group, r.name, r.tax_id, v_reason);
    insert into pru_ids values ('supplier', r.n, v_id, null);
  end loop;

  for r in select p.*, c.id as category_id, s.id as supplier_id
             from pru_ingredients p
             join catalog.ingredient_categories c
               on c.group_id = v_group and c.code = p.rubro and c.parent_id is null and c.deleted_at is null
             join pru_ids s on s.kind = 'supplier' and s.n = p.supplier
            order by p.n loop
    v_res := catalog.create_ingredient(v_group, r.name, r.category_id, r.unit,
                                       jsonb_build_object('notes', 'Prueba de la Fase 2 para Soy'), v_reason);
    v_id := catalog.create_purchase_product((v_res ->> 'id')::uuid, format('PRU-%s', lpad(r.n::text, 3, '0')),
                                            r.description, r.package, r.units, r.content, r.content_unit,
                                            jsonb_build_object('supplier_id', r.supplier_id), v_reason);
    insert into pru_ids values ('ingredient', r.n, (v_res ->> 'id')::uuid, v_id);
  end loop;

  -- 2. Dos rondas de precios: primero el del grupo y después el propio de Demo Pastas Centro (cada propuesta se
  --    compara con el precio que vale hoy en su lugar, así que la de Centro va cuando el del grupo ya está).
  --    Centro usa el suyo (costo «verificado»); Norte hereda el del grupo («con estimaciones»).
  --    Compras propone y la Controller aprueba: otra persona, como pide el circuito.
  for v_round in 1..2 loop
    perform pg_temp.as_user(v_buyer);
    for r in select p.*, i.version_id as product_id, s.id as supplier_id
               from pru_ingredients p
               join pru_ids i on i.kind = 'ingredient' and i.n = p.n
               join pru_ids s on s.kind = 'supplier' and s.n = p.supplier
              where p.price is not null
              order by p.n loop
      v_request := costing.propose_price(r.product_id, case v_round when 1 then 'group' else 'restaurant' end, null,
                                         case v_round when 2 then v_centro end, v_today - r.days_ago, r.price,
                                         'invoice', 21, true, 0, r.supplier_id, 'test_value',
                                         case v_round when 1 then 'Precio inventado para la prueba de la Fase 2'
                                              else 'Precio inventado para la prueba de la Fase 2 (Demo Pastas Centro)' end,
                                         v_reason);
      insert into pru_ids values ('price_request', v_round, v_request, null);
    end loop;

    perform pg_temp.as_user(v_ctrl);
    for r in select id from pru_ids where kind = 'price_request' and n = v_round loop
      v_res := workflow.decide_approval(r.id, 'approved', v_reason || ': precio revisado');
      if coalesce(v_res ->> 'result', '') <> 'approved' then
        raise exception 'La Controller no pudo aprobar un precio: %', v_res ->> 'message';
      end if;
    end loop;
  end loop;

  -- 3. Recetas: primero las preparaciones (los platos las usan publicadas) y después los platos.
  --    La Chef las arma y pide la revisión; la Directora de marca las aprueba y quedan publicadas.
  for r in select p.*, c.id as category_id from pru_recipes p
             join recipes.recipe_categories c
               on c.group_id = v_group and c.code = p.rubro and c.parent_id is null and c.deleted_at is null
            order by (p.kind <> 'preparation'), p.n loop
    perform pg_temp.as_user(v_chef);
    v_res := recipes.create_recipe(v_group, v_pastas, null, r.name, r.kind::recipes.recipe_type, r.category_id, v_reason);
    if coalesce(v_res ->> 'result', '') <> 'applied' then
      raise exception 'No se pudo crear «%»: %', r.name, v_res ->> 'message';
    end if;
    insert into pru_ids values ('recipe', r.n, (v_res ->> 'id')::uuid, (v_res ->> 'version_id')::uuid);

    v_res := recipes.save_sheet(
      (v_res ->> 'id')::uuid, (v_res ->> 'version_id')::uuid,
      (select updated_at from recipes.recipe_versions where id = (v_res ->> 'version_id')::uuid),
      null,
      jsonb_strip_nulls(jsonb_build_object('yield_quantity', r.yield_qty, 'yield_unit', r.yield_unit,
                                           'portions', r.portions, 'description', r.description)),
      (select jsonb_agg(case when l.sub is null
                             then jsonb_build_object('ingredient_id', i.id, 'quantity', l.qty, 'unit', l.unit)
                             else jsonb_build_object('sub_recipe_id', s.id, 'quantity', l.qty, 'unit', l.unit,
                                                     'basis', 'finished') end
                        order by l.line)
         from pru_lines l
         left join pru_ids i on i.kind = 'ingredient' and i.n = l.ingredient
         left join pru_ids s on s.kind = 'recipe' and s.n = l.sub
        where l.recipe = r.n),
      r.steps, v_reason, true);
    if coalesce(v_res ->> 'result', '') <> 'pending_approval' then
      raise exception 'No se pudo mandar a revisión «%»: %', r.name, v_res ->> 'message';
    end if;

    perform pg_temp.as_user(v_director);
    v_res := workflow.decide_approval((v_res ->> 'request_id')::uuid, 'approved', v_reason || ': receta revisada');
    if coalesce(v_res ->> 'result', '') <> 'approved' then
      raise exception 'La Directora de marca no pudo publicar «%»: %', r.name, v_res ->> 'message';
    end if;
  end loop;

  -- 4. La Chef asigna todas las recetas a los dos locales de Demo Pastas.
  perform pg_temp.as_user(v_chef);
  for r in select i.id, x.restaurant_id
             from pru_ids i
            cross join (values ('00000000-0000-4000-8000-000000000201'::uuid),
                               ('00000000-0000-4000-8000-000000000202'::uuid)) as x (restaurant_id)
            where i.kind = 'recipe' loop
    v_res := recipes.set_assignment(r.id, r.restaurant_id, true, v_reason);
    if coalesce(v_res ->> 'result', '') not in ('applied', 'unchanged') then
      raise exception 'No se pudo asignar una receta a su local: %', v_res ->> 'message';
    end if;
  end loop;

  perform set_config('request.jwt.claims', '', true);
end
$$;

-- Los costos guardados de las recetas: en la base los calcula la cola cada minuto; acá, sin esperar. Si justo la está
-- procesando el cron de staging, devuelve 0 y quedan para el minuto siguiente: el control de abajo no depende de esto
-- (costing.recipe_cost calcula en el momento).
select costing.process_recalc_queue(10000) as recetas_recalculadas;

-- Verificar, no suponer: si algo no quedó como se espera, se deshace todo.
do $$
declare
  v_ing       int;
  v_prices    int;
  v_published int;
  v_bad       text;
begin
  select count(*) into v_ing from pru_ids where kind = 'ingredient';
  select count(*) into v_prices
    from costing.price_records pr join pru_ids i on i.kind = 'ingredient' and i.version_id = pr.purchase_product_id;
  select count(*) into v_published
    from recipes.recipe_versions v join pru_ids i on i.kind = 'recipe' and i.id = v.recipe_id where v.status = 'published';
  if v_ing <> 28 or v_prices <> 54 or v_published <> 13 then
    raise exception 'La carga no quedó completa: % materias primas (28), % precios (54), % recetas publicadas (13). No se cargó nada.',
      v_ing, v_prices, v_published;
  end if;

  -- Centro: todo verificado salvo los Ñoquis (desactualizado) y el Risotto (incompleto). Norte: lo mismo, pero con
  -- estimaciones (usa los precios del grupo).
  perform pg_temp.as_user('00000000-0000-4000-8000-000000000407');
  select string_agg(format('%s en %s: %s', r.name, x.local, coalesce(c.reliability::text, 'sin costo')), '; ') into v_bad
    from pru_ids i
    join recipes.recipes r on r.id = i.id
    join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published'
    cross join (values ('Centro', '00000000-0000-4000-8000-000000000201'::uuid, 'verified'),
                       ('Norte', '00000000-0000-4000-8000-000000000202'::uuid, 'estimated')) as x (local, id, normal)
    left join lateral costing.recipe_cost(v.id, x.id) c on true
   where i.kind = 'recipe'
     and c.reliability::text is distinct from case i.n when 9 then 'stale' when 10 then 'incomplete' else x.normal end;
  perform set_config('request.jwt.claims', '', true);
  if v_bad is not null then
    raise exception 'Los costos no salieron como se esperaba: %. No se cargó nada.', v_bad;
  end if;
end
$$;

-- Control: lo que quedó cargado y el costo de cada receta en Demo Pastas Centro.
select (select count(*) from pru_ids where kind = 'ingredient') as materias_primas,
       (select count(*) from costing.price_records pr join pru_ids i on i.kind = 'ingredient' and i.version_id = pr.purchase_product_id)
         as precios_vigentes,
       (select count(*) from recipes.recipe_versions v join pru_ids i on i.kind = 'recipe' and i.id = v.recipe_id
         where v.status = 'published') as recetas_publicadas;

select pg_temp.as_user('00000000-0000-4000-8000-000000000407');
select r.name as receta, x.local, c.reliability as confiabilidad, round(c.total_gross_cost, 2) as total_con_iva,
       round(c.total_cost, 2) as total_sin_iva, round(c.cost_per_portion, 2) as porcion_sin_iva
  from pru_ids i
  join recipes.recipes r on r.id = i.id
  join recipes.recipe_versions v on v.recipe_id = r.id and v.status = 'published'
  cross join (values (1, 'Centro', '00000000-0000-4000-8000-000000000201'::uuid),
                     (2, 'Norte', '00000000-0000-4000-8000-000000000202'::uuid)) as x (k, local, id)
  cross join lateral costing.recipe_cost(v.id, x.id) c
 where i.kind = 'recipe'
 order by i.n, x.k;
select set_config('request.jwt.claims', '', true);

\if :{?dry_run}
  rollback;
  \echo 'Ensayo (DRY_RUN): se hizo todo y se deshizo. No quedó nada cargado.'
\else
  commit;
  \echo 'Prueba de la Fase 2 cargada: materias primas, precios, recetas y costos.'
\endif
