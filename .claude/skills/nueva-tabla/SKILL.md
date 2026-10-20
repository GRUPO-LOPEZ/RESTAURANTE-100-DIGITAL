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

```sql
create table <esquema>.<tabla> (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references org.groups (id) on delete restrict,
  -- brand_id / restaurant_id si corresponde
  -- ... columnas del concepto (timestamptz, numeric(14,4) + currency, cantidad + unit_id, enums)
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users (id) on delete restrict,
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users (id) on delete restrict,
  deleted_at    timestamptz,
  deleted_by    uuid references auth.users (id) on delete restrict
);

comment on table  <esquema>.<tabla> is '<Qué guarda, en español>';
comment on column <esquema>.<tabla>.<col> is '<Qué guarda, en español>';  -- una por columna

create index on <esquema>.<tabla> (group_id) where deleted_at is null;
-- un índice por cada FK y por cada columna de filtro

create trigger set_control_columns before insert or update on <esquema>.<tabla>
  for each row execute function core.set_control_columns();
create trigger log_change after insert or update or delete on <esquema>.<tabla>
  for each row execute function audit.log_change();

alter table <esquema>.<tabla> enable row level security;
create policy <tabla>_select on <esquema>.<tabla> for select to authenticated
  using (deleted_at is null and core.has_permission('<modulo>.view', restaurant_id));
-- políticas de insert / update con su permiso. Sin política de delete: el borrado es lógico.
```

(Los nombres exactos de las funciones de control y de auditoría se fijan en la Fase 1. Usá los que existan en `supabase/migrations/`.)

## 3. Escrituras críticas

Si la escritura toca más de una tabla o necesita motivo de auditoría, va en una función SQL transaccional que hace `set_config('app.reason', ..., true)` y `set_config('app.origin', ..., true)` antes de escribir.

## 4. Pruebas pgTAP (`supabase/tests/<esquema>_<tabla>.test.sql`)

- Estructura: la tabla, las columnas, las FKs y los índices existen.
- Restricciones: los `check` y los `not null` rechazan datos malos.
- RLS: por cada rol de prueba, ve o no ve, y puede o no puede escribir, según su alcance.
- Auditoría: un insert o un update deja un registro en `audit.audit_events` con usuario, acción y motivo.

## 5. Cierre

1. `npm run db:reset` sin errores → `npm run test:db` en verde.
2. `npm run db:types` → `npm run typecheck` en verde.
3. Revisión con el subagente `db-reviewer` y, si toca permisos, con `security-auditor`.
4. Actualizar el diccionario de datos en `docs/modulos/` y `docs/estado.md`.
