# ADR-0005 — Cómo llega la app a los datos

- **Fecha:** 2026-10-20
- **Estado:** aceptada (plan de M3 aprobado por Joaco). Se **aplica** en M5/M6, cuando existan `has_permission` y las políticas.

## Contexto

Supabase expone por su API (PostgREST) solo los esquemas listados en `supabase/config.toml` (`api.schemas`). Hoy son `public` y `graphql_public`. Los esquemas de negocio (`core`, `org`, `workflow`...) están cerrados: los roles de la API no tienen `usage`, GRANT ni políticas. Hay que decidir cómo va a leer y escribir la app.

## Opciones

- **A. Exponer los esquemas de negocio** (`core`, `org`, `workflow`; después `catalog`, `recipes`...), con GRANT mínimos por tabla y RLS con `has_permission` en cada operación.
- **B. No exponerlos** y que la app use solo funciones RPC en `public`.

## Decisión: A, con tres reglas

1. **Lectura y escrituras simples por la API, protegidas por RLS.** Cada tabla expuesta tiene GRANT explícitos y mínimos para `authenticated`: `select`, `insert` y `update`, pero **nunca `delete`**, porque el borrado es lógico. `anon` no recibe nada en los esquemas de negocio.
2. **Las escrituras sensibles van solo por RPC.** Asignar roles, aprobar, publicar, bloquear usuarios y borrar lógicamente se hacen por funciones SQL que validan, escriben y auditan en una transacción. Esas tablas no reciben GRANT de escritura directa.
3. **`audit` nunca se expone.** El historial se lee por una vista o RPC que filtra por alcance y oculta costos a quien no tenga `costing.view_costs` (ADR-0006).

## Por qué

- Con B habría que escribir y mantener una función por cada lectura y cada filtro, y las pantallas con tablas, filtros y paginación (TanStack Table y Query, sección 3) quedarían atadas a esas funciones. Es más código y más lugares donde equivocarse con los permisos.
- Con A, la seguridad sigue estando **en la base** (RLS + `has_permission`), que es lo que piden las secciones 5 y 6. La API no agrega permisos: solo deja pasar lo que RLS permite.
- Las RPC quedan para lo que de verdad necesita varias tablas, validaciones o auditoría con motivo.

## Qué se hace al aplicarla (M5/M6)

- Sumar los esquemas a `api.schemas` en `supabase/config.toml`, y a la configuración de staging y producción.
- `grant usage on schema <esquema> to authenticated`. Nunca a `anon`.
- GRANT **por tabla y por operación**. **Nunca** el `grant all on all tables in schema ... to anon, authenticated, service_role` que sugiere el panel de Supabase.
- Actualizar a propósito la prueba de humo (`000_smoke`) y la de catálogo (`010`), que hoy exigen "ningún acceso", para que exijan exactamente los accesos decididos.
- Prueba de catálogo nueva: toda tabla con GRANT a `authenticated` tiene RLS y una política por cada operación otorgada.

## Riesgos que se cierran al aplicarla (revisión de seguridad del 2026-10-20)

- **`service_role` saltea RLS (BYPASSRLS).** Solo recibe GRANT mínimos y explícitos, y se usa únicamente en Edge Functions de servidor. Nunca en la app, en agentes ni en Claude Code. Una prueba fija exactamente qué permisos tiene, y `audit.log_change()` ya rechaza sus cambios si no declaran origen.
- **Vistas.** Una vista creada por `postgres` corre con los permisos de su dueño, que saltea RLS. Toda vista en un esquema expuesto se crea con `security_invoker = true`, y la lectura de la auditoría va por una RPC que filtra con `has_permission` y oculta costos.
- **Update por columnas, no de la fila entera.** `grant update (col1, col2...)` sin `deleted_at` ni columnas de alcance (`group_id`, `brand_id`, `restaurant_id`). Las políticas de insert y update llevan `WITH CHECK` con `has_permission` sobre la fila nueva. Además, en `org` el trigger `validate_hierarchy` ya impide mover el alcance con una edición común.
- **Tablas en `public`.** Los permisos por defecto de Supabase daban DELETE y TRUNCATE a los roles de la API sobre toda tabla nueva de `postgres` en `public`. M3 los corta, con su prueba.
- **Seed.** `supabase/seed.sql` nunca se carga en staging ni en producción: nada de `db push --include-seed` ni Supabase Branching con seed. El seed aborta si la base ya tiene grupos.

## Consecuencias

- Hasta M5/M6 ninguna pantalla puede leer datos de negocio. Es lo esperado: no hay pantallas de negocio antes del Módulo 0.
- Los tipos (`npm run db:types`) ya incluyen `core`, `org` y `workflow`.
