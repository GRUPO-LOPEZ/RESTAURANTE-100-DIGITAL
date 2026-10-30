# ADR-0022 — Configuración del catálogo: categorías y procesos desde la app

- **Fecha:** 2026-10-29
- **Estado:** aceptada por Joaco (plan de la sesión aprobado).

## Contexto

- **Cada materia prima necesita una categoría:** la base lo exige (`catalog.ingredients.category_id not null`).
- **Las categorías solo las cargaba el seed** (`supabase/seed.sql`). El seed no corre en staging ni en producción, y no había ninguna función ni pantalla para crearlas.
- **Resultado:** fuera de la compu de desarrollo no se podía cargar ninguna materia prima. Joaco lo detectó en staging.
- **Origen:** ADR-0020 dejó las funciones de escritura de categorías para "la configuración (2.1 C)". No se vio que eso bloqueaba la carga.
- **Los procesos de rendimiento** tenían el mismo hueco a medias: había función (`catalog.create_yield_process`), pero no pantalla.

## Decisión

- **Las listas las define el grupo desde la app.** No se cargan categorías fijas por migración, porque llegarían a producción sin que Soy las apruebe.
- **Pantalla nueva** `/materias-primas/configuracion`, con dos secciones:
  - **Categorías:** crear (principal o subcategoría), renombrar y dar de baja. Pide `catalog.manage` para todo el grupo, igual que el resto del catálogo (Superadministrador y Compras de grupo).
  - **Procesos de rendimiento:** crear, renombrar y dar de baja. Pide `yields.approve` para todo el grupo, igual que `create_yield_process` (el Chef de todo el grupo).
- **Dar de baja es borrado lógico** (`deleted_at`). La base lo rechaza si está en uso:
  - una categoría con materias primas o subcategorías vigentes, con un mensaje que dice cuántas tiene;
  - un proceso con un estándar vigente o una propuesta en revisión. Los ensayos viejos no lo bloquean, porque son historia.
- **El código de un proceso no cambia** al renombrarlo: lo van a usar las importaciones.

## Cómo quedó

- **Migración** `20261031120000_catalog_settings.sql`, sin tablas nuevas:
  - `catalog.create_category`, `rename_category`, `archive_category`;
  - `catalog.rename_yield_process`, `archive_yield_process`;
  - `catalog.category_usage` y `process_usage`: cuentan en la base, con RLS de quien consulta, porque la API devuelve hasta 1.000 filas;
  - nueva versión de `catalog.raise_friendly`, con los mensajes en español de categorías y procesos repetidos o vacíos.
- **La auditoría, las columnas de control, los dos niveles y la madre vigente** ya los hacían los triggers existentes; no se tocaron.
- **Una baja y una carga al mismo tiempo no se cruzan:**
  - la baja bloquea la fila (`for update`);
  - el trigger `catalog.enforce_live_references` (nueva versión) lee la categoría, la madre, el proveedor o el proceso con `for share`: espera a que termine la baja y después la ve. Antes leía sin bloquear, y una materia prima podía quedar en una categoría dada de baja (lo encontró la revisión de base y se reprodujo con dos sesiones);
  - ese trigger ahora también cuida los procesos en las propuestas y los ensayos nuevos.
  - Se probó a mano con dos sesiones a la vez: la carga espera y se rechaza con "Esa categoría está borrada". pgTAP corre en una sola sesión y no lo puede probar.
- **La categoría madre** se controla al principio de `create_category`, con un solo mensaje ("Elegí una categoría madre de este grupo."): no revela si un id existe en otro grupo ni de qué tipo es.
- **Pantalla:**
  - enlace "Configuración" en la lista de materias primas, para quien tenga alguno de los dos permisos;
  - el alta de materia prima, si no hay categorías, avisa y lleva a la configuración en vez de mostrar una lista vacía;
  - la ficha, si no hay procesos, lleva a la configuración a quien puede crearlos;
  - después de dar de baja, la pantalla vuelve con un aviso arriba, porque el elemento desaparece de la lista junto con su formulario. El aviso (`components/flash-notice.tsx`) se lleva el foco, para que lo lea el lector de pantalla, y saca `?baja=` de la dirección, para que no reaparezca;
  - "Cambiar el nombre" y "Dar de baja" van en plegables separados, cada uno con su motivo, para no escribir el motivo en el formulario equivocado desde el celular.
- **El plegable de acciones** de la ficha pasó a `components/disclosure.tsx`, para usarlo en las dos pantallas. La ficha de una persona (`app/usuarios/[id]`) todavía tiene el suyo: se unifica más adelante.
- **Las listas no se paginan:** son catálogos chicos del grupo (decenas de categorías y procesos). Es una excepción consciente a la regla de listas paginadas.

## Fuera de esta decisión

- **Alérgenos:** la lista la define Soy (pregunta N5).
- **Plazo de precio desactualizado por categoría** (`stale_price_days`): llega con los precios (2.1 C, decisión 7).
- **Reactivar algo dado de baja:** no hay. Se puede crear otra categoría o proceso con el mismo nombre, porque el nombre es único solo entre los vigentes. Si hace falta, se suma después.

## Revisiones (2026-10-29)

**`security-auditor`: apto, sin graves ni medios. `db-reviewer`: sin graves. `ui-reviewer`: sin graves.**

**Resuelto en este PR:**

- **Carreras entre una baja y una carga** (base, M1 y M2; seguridad, m1 y m2): `for share` en el trigger, descripto arriba.
- **Un id de otro grupo como madre** daba mensajes distintos según qué era (seguridad, m3): ahora siempre el mismo.
- **Pruebas que faltaban** (seguridad, m4; base, m7): madre dada de baja o inexistente, renombrar un id inexistente, conteos sin `catalog.view`, proceso dado de baja en un ensayo o una propuesta, nombre nulo, nombre repetido al renombrar, auditoría de la baja. La `160` tiene 44 pruebas.
- **Las funciones de conteo** filtran lo borrado ellas mismas, sin depender de RLS (base, m3).
- **Mensajes:** nombre nulo en español, singular y plural ("dala" o "dalas"), "en el mismo nivel" (base, m4 a m6).
- **Pantalla** (diseño, M1 a M3 y menores): plegables separados con su motivo, aviso de una sola vez y con foco, el total de una categoría madre suma sus subcategorías, enlace de la ficha con altura táctil, estado vacío si no hay listas que configurar, aviso de que una baja no se revierte desde la pantalla.
- **Con varios grupos**, cada sección muestra solo las listas del grupo donde se tiene el permiso (seguridad, observación).

**De paso, una prueba de la 2.1 B:** la `150` registraba ensayos con la fecha del servidor (UTC). Después de las 21 h de la Argentina, en UTC ya es mañana, y la base la rechazaba por futura. Ahora usa la fecha de la Argentina, como la base.

## Consecuencias

- **En staging**, después de fusionar, alguien con `catalog.manage` de grupo crea las categorías reales desde la pantalla. Recién ahí se pueden cargar materias primas.
- **La prueba `050`** suma las 7 funciones nuevas a la lista de funciones abiertas, a propósito. Las internas (`category_group`, `yield_process_group`, `require_name`) no se abren.
