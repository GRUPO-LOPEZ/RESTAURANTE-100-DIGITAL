# ADR-0006 — Cómo se protege la auditoría y qué límites quedan

- **Fecha:** 2026-10-20
- **Estado:** aceptada. Implementada en M1 y M2, a revisar con Soy.

## Contexto

La sección 6 pide que `audit.audit_events` sea "solo de inserción: sin permisos de update ni delete para nadie, tampoco para administradores comunes". La revisión de seguridad mostró que el rol `postgres` de Supabase no es superusuario, pero sí es la cuenta de las migraciones y del editor SQL del panel. Si es dueño, o hereda al dueño, puede desactivar triggers y reescribir la historia.

## Decisión

Cinco capas, de la más fuerte a la más débil:

1. **Ningún rol de la API toca la auditoría.** `anon`, `authenticated` y `service_role` no tienen ningún permiso. RLS está activado sin políticas, y la tabla nunca se expone en la API.
2. **Dueño dedicado sin login (`audit_owner`).** `postgres` puede ponerse ese rol (`SET`), pero **no lo hereda**. Sin un `set role audit_owner` deliberado, no puede alterar la tabla, desactivar triggers ni escribir. Solo tiene lectura y permiso para conectar `log_change` a tablas nuevas.
3. **Triggers que rechazan todo** `update`, `delete` y `truncate`, sin importar quién lo intente.
4. **Sellos (`audit.audit_seals`).** Son una cadena de huellas sha256 sobre los eventos, en orden. Cada sello encadena con el anterior, y `audit.verify_seals()` detecta cualquier evento editado, borrado o inventado dentro de un tramo sellado. Hay una prueba que lo demuestra con un ataque simulado.
5. **Evidencia fuera de la base.** La exportación semanal del esquema `audit` (sección 10) guarda también la última huella sellada. Quien altere la base y recalcule los sellos no puede cambiar lo que ya está afuera.

## Límites que quedan (dichos claramente)

- **Quien tenga la contraseña de `postgres` puede hacer `set role audit_owner`** y modificar la base, incluidos los sellos. Las capas 4 y 5 hacen que eso **se detecte**, pero no lo impiden. Por eso esa contraseña tiene que estar solo en manos de Soy y nunca en esta máquina (sección 10).
- **Los eventos que todavía no se sellaron** se pueden alterar sin dejar rastro. Conviene sellar seguido: la propuesta es cada hora, con una tarea programada (pendiente).
- **Un evento de una transacción que tarda más que el margen del sellado** (10 minutos por defecto) puede quedar dentro de un tramo ya sellado. En ese caso `verify_seals` lo marca como alteración: es un falso positivo que hay que revisar a mano.

## Otras decisiones de la revisión

- **Quién hizo el cambio.** El actor sale **solo** de `request.jwt.claims` (el JWT completo), nunca del GUC heredado `request.jwt.claim.sub`. Se guardan además `jwt_role` y `db_user`, y un cambio hecho con la clave de servidor **sin origen declarado se rechaza**.
- **Secretos.** Se ocultan en cualquier nivel del jsonb, por nombre de clave y por forma del valor (JWT, claves de API, llaves PEM). Palabras como `salt` o `hash` no se ocultan, porque en una cocina son datos.
- **Columnas a ocultar.** Si una tabla pasa a `log_change` una columna que no existe (un error de tipeo), el cambio falla. Así un secreto no queda grabado para siempre por un descuido.
- **Conexión de los triggers.** `log_change` y `set_control_columns` verifican cómo se conectaron (AFTER o BEFORE, por fila) y fallan si se conectan mal, en lugar de perder datos en silencio.

## Pendiente para cuando se exponga la lectura (ADR-0005, M4)

- `old_values` y `new_values` guardan la fila completa. La lectura de la auditoría **tiene que ocultar costos y precios** a quien no tenga `costing.view_costs`, con una prueba propia. Nunca se expone `audit_events` directamente.
- Al exponer `core`, `org` o `workflow`, **no** usar el `grant all on all tables in schema ... to anon, authenticated, service_role` que sugiere el panel de Supabase. `audit` nunca entra en los esquemas expuestos.
