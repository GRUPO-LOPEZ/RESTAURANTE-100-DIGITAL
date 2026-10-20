---
name: nueva-tabla
description: Receta para crear una tabla de negocio completa en Supabase según las reglas de Grupo LF (migración, columnas de control, índices, RLS con has_permission, auditoría, comentarios en español, pgTAP y tipos). Usala cada vez que haya que agregar una tabla nueva.
---

# Crear una tabla nueva

Seguí estos pasos en orden. No saltees ninguno. Reglas completas: `.claude/rules/database.md` y `.claude/rules/security.md`.

## 0. Antes de empezar

- Confirmá el esquema (tema) de la tabla y su alcance: grupo, marca o restaurante.
- Confirmá qué permisos la leen y la escriben (`modulo.accion`). Si no está claro, **preguntale a Joaco**.
- Revisá que no exista ya una tabla para ese concepto.

## 1. Migración nueva

`npx supabase migration new <esquema>_<tabla>`. Nunca edites una migración ya commiteada.

## 2. Plantilla

Todo va en **la misma migración**: tabla, índices, triggers, RLS, políticas y GRANT. Nunca existe una tabla sin RLS, ni por un momento.

Ejemplo para una tabla de **alcance restaurante**:

```sql
create table <esquema>.<tabla> (
  id             uuid primary key default gen_random_uuid(),
  group_id       uuid not null references org.groups (id) on delete restrict,
  restaurant_id  uuid not null,
  -- ... columnas del concepto (timestamptz, numeric(14,4) + currency, cantidad + unit_id, enums)
  created_at     timestamptz not null default now(),
  created_by     uuid references core.actors (id) on delete restrict,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references core.actors (id) on delete restrict,
  deleted_at     timestamptz,
  deleted_by     uuid references core.actors (id) on delete restrict,
  -- FK compuesta: el restaurante pertenece al mismo grupo (alcance consistente)
  foreign key (restaurant_id, group_id) references org.restaurants (id, group_id) on delete restrict
);

comment on table  <esquema>.<tabla> is '<Qué guarda, en español>';
-- un comment on por CADA columna, incluidas las de control
comment on column <esquema>.<tabla>.restaurant_id is 'Restaurante al que pertenece el registro.';

-- un índice por cada FK y por cada columna de filtro
create index on <esquema>.<tabla> (restaurant_id) where deleted_at is null;
create index on <esquema>.<tabla> (group_id) where deleted_at is null;

create trigger set_control_columns before insert or update on <esquema>.<tabla>
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on <esquema>.<tabla>
  for each row execute function audit.log_change();

alter table <esquema>.<tabla> enable row level security;

create policy <tabla>_select on <esquema>.<tabla> for select to authenticated
  using (deleted_at is null and core.has_permission('<modulo>.view', restaurant_id));
create policy <tabla>_insert on <esquema>.<tabla> for insert to authenticated
  with check (core.has_permission('<modulo>.edit', restaurant_id));
create policy <tabla>_update on <esquema>.<tabla> for update to authenticated
  using (deleted_at is null and core.has_permission('<modulo>.edit', restaurant_id))
  with check (core.has_permission('<modulo>.edit', restaurant_id));

-- GRANT explícito y mínimo (auto_expose_new_tables = false). NUNCA delete: el borrado es lógico.
grant select, insert, update on <esquema>.<tabla> to authenticated;
```

**Según el alcance de la tabla:**

| Alcance     | Columnas                                   | Función en la política                         |
| ----------- | ------------------------------------------ | ---------------------------------------------- |
| Restaurante | `group_id`, `restaurant_id` (FK compuesta) | `core.has_permission(code, restaurant_id)`     |
| Marca       | `group_id`, `brand_id` (FK compuesta)      | `core.has_permission_in_brand(code, brand_id)` |
| Grupo       | `group_id`                                 | `core.has_permission_in_group(code, group_id)` |

- **Nunca** uses `core.has_permission_anywhere` en una política: es solo para menús, y la prueba de catálogo lo detecta.
- Si la condición no depende de la fila, envolvela en `(select ...)` para que se evalúe una sola vez.
- El borrado lógico se hace con la función transaccional de borrado (Fase 1), no con un `update` directo desde la app.

(Los nombres exactos de las funciones de control, auditoría y permisos se fijan en la Fase 1: ver `docs/fases/fase-1-plan.md`. Usá los que existan en `supabase/migrations/`.)

## 3. Escrituras críticas

Si la escritura toca más de una tabla o necesita motivo de auditoría, va en una función SQL transaccional que hace `set_config('app.reason', ..., true)` y `set_config('app.origin', ..., true)` antes de escribir. El motivo y el origen son **solo informativos**: nunca se usan para decidir permisos. La función lleva `search_path` fijo y `grant execute` explícito: por defecto ninguna función es ejecutable.

## 4. Pruebas pgTAP (`supabase/tests/<esquema>_<tabla>.test.sql`)

- Estructura: la tabla, las columnas, las FKs y los índices existen.
- Restricciones: los `check` y los `not null` rechazan datos malos.
- RLS: por cada rol de prueba, ve o no ve, y puede o no puede escribir, según su alcance. Incluí un usuario de **otro** restaurante del mismo grupo.
- Borrado: un `DELETE` da "permission denied" (`throws_ok`), no 0 filas.
- Auditoría: un insert o un update deja un registro en `audit.audit_events` con usuario, acción y motivo.

## 5. Cierre

1. `npm run db:reset` sin errores → `npm run test:db` en verde.
2. `npm run db:types` → `npm run typecheck` en verde.
3. Revisión con el subagente `db-reviewer` y, si toca permisos, con `security-auditor`.
4. Actualizar el diccionario de datos en `docs/modulos/` y `docs/estado.md`.
