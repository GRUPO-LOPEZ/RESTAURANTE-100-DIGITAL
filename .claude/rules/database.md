---
paths:
  - "supabase/**"
---

# Base de datos ordenada por temas (prompt maestro, sección 5)

Toda la información vive en PostgreSQL, separada en esquemas por tema. Cada tema es una carpeta lógica: fácil de encontrar, de permisar y de respaldar.

| Esquema       | Tema                                 | Tablas principales                                                                                                                           |
| ------------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `core`        | Identidad, roles y permisos          | user_profiles, roles, permissions, role_permissions, user_memberships, user_role_assignments, service_accounts, notifications                |
| `org`         | Estructura del grupo                 | groups, brands, restaurants, areas, legal_entities (razones sociales; ADR-0029)                                                              |
| `audit`       | Historia inalterable                 | audit_events, authentication_security_events (ingresos, bloqueos y rechazos; ADR-0014 y ADR-0015), sellos                                    |
| `workflow`    | Aprobaciones                         | approval_workflows, approval_requests, approval_decisions                                                                                    |
| `catalog`     | Materias primas y proveedores        | ingredients, ingredient_aliases, purchase_products, suppliers, units, unit_conversions, allergens (precios: costing; ADR-0020)               |
| `recipes`     | Recetario y fichas técnicas          | recipes, recipe_versions, recipe_lines, recipe_steps, recipe_photos                                                                          |
| `costing`     | Costos                               | price_records y price_settings (precios; ADR-0029), recipe_cost_current, recipe_cost_snapshots, cost_recalc_queue, cost_scenarios (ADR-0032) |
| `purchasing`  | Compras                              | purchase_orders, purchase_order_lines, invoices, invoice_lines                                                                               |
| `inventory`   | Stock                                | stock_locations, stock_movements, stock_counts                                                                                               |
| `production`  | Producción                           | production_plans, production_batches                                                                                                         |
| `ai`          | Agentes                              | agent_runs, agent_proposals, integration_permissions                                                                                         |
| `reporting`   | Lectura para tableros                | vistas y vistas materializadas, **nunca datos propios**                                                                                      |
| `imports`     | Carga de Excel (Fase 2)              | import_jobs, import_column_mappings, import_staging_rows, import_errors (ADR-0020)                                                           |
| `integration` | Eventos para otros sistemas (Fase 2) | integration_outbox. No se expone por la API (ADR-0020)                                                                                       |

## Migraciones

- Las migraciones en `supabase/migrations/` son la **única** forma de cambiar la base. Nada de cambios a mano en Studio.
- Una migración ya commiteada **no se edita** (un hook lo bloquea). Para corregir, se crea una migración nueva.
- Toda migración tiene que aplicar desde cero con `npm run db:reset` sin errores.
- Después de cada cambio de esquema: `npm run db:types`. Los tipos nunca se escriben a mano.

## Convenciones obligatorias

- Nombres en inglés, snake_case, tablas en plural. Una tabla = un concepto.
- Clave primaria `id uuid` generada en la base. Nunca reutilizar ni cambiar un id.
- Toda tabla de negocio lleva `group_id`, y `brand_id` / `restaurant_id` cuando corresponda. Así funcionan los permisos por alcance.
- Columnas de control en toda tabla modificable: `created_at`, `created_by`, `updated_at`, `updated_by`, `deleted_at`, `deleted_by`. **Se completan por trigger, no desde la app.**
- Fechas siempre `timestamptz`. Dinero en `numeric(14,4)` con su moneda (en el recetario, importes en `numeric(18,4)` y costo por gramo, mililitro o unidad en `numeric(20,8)`: ADR-0020, N1b). Cantidades con su unidad. **Nunca `float` para plata.**
- Estados con tablas de referencia o tipos enum documentados, nunca texto libre.
- Claves foráneas siempre declaradas, con `on delete restrict` por defecto.
- Borrado lógico (`deleted_at`). El borrado físico solo lo hace el superadministrador en tareas de mantenimiento documentadas.
- **RLS activado en todas las tablas de todos los esquemas**, sin excepción (ver `security.md`).

## Eficiencia de escritura

- Escrituras críticas dentro de funciones SQL transaccionales: dato y auditoría en una sola operación. El costo se recalcula con una cola (ADR-0032).
- Pocas tablas por operación y restricciones (`check`, `unique`, `not null`) para que el error se detecte en la base.
- Importaciones masivas en lotes, con tabla de carga intermedia y validación previa.

## Eficiencia de lectura

- Índice en cada clave foránea y en cada columna usada para filtrar (`restaurant_id`, fechas, estados).
- Índices parciales para lo vigente, por ejemplo `where deleted_at is null`.
- Los tableros leen del esquema `reporting`: vistas para lo simple, vistas materializadas que se refrescan para lo pesado.
- Paginación en todas las listas. Nunca traer tablas completas al navegador.
- Revisar con `explain analyze` toda consulta de tablero antes de publicarla (objetivo: menos de 300 ms con datos de prueba realistas).

## Documentación viva

- Cada esquema, tabla y columna lleva un `comment on` **en español** que explica qué guarda.
- Se mantiene un diccionario de datos en `docs/modulos/`, generado desde la base.

## Datos de prueba

- `supabase/seed.sql`: grupo ficticio, 3 marcas, 4 restaurantes, un usuario por rol, 50 ingredientes y 20 recetas.
- **Nunca datos reales en desarrollo.**

## Pruebas

- Cada tabla nueva tiene pgTAP en `supabase/tests/`: existencia y restricciones, RLS por rol y alcance, y que la auditoría registre.
- Antes de cerrar, pedir revisión al subagente `db-reviewer`.
