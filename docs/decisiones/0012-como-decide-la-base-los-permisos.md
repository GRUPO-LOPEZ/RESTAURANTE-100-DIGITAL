# ADR-0012 — Cómo decide la base los permisos y cómo escribe la app

- **Fecha:** 2026-10-20
- **Estado:** aceptada. Se implementó en M5 (migración `20261020222115_core_permissions.sql`), como parte del plan de la Fase 1 que aprobó Joaco.

## Contexto

`security.md` pide **una sola función** que decida los permisos, `core.has_permission(permiso, restaurant_id)`, usada por las políticas RLS, las funciones de servidor y la interfaz. ADR-0005 abre `core`, `org` y `workflow` por la API con RLS.

Dos problemas aparecieron al construirlo:

1. **Rendimiento.** Una política que llama a una función por fila escala mal. Con 2.000 locales, la lista tardaba unos 750 ms, más del objetivo de 300 ms. Las funciones `security definer` en SQL además se replanifican en cada llamada: llegaban a 4 ms por llamada.
2. **Motivo y origen.** Si la app escribe directo en las tablas por PostgREST, no puede fijar el motivo (`set_change_context`) en la misma transacción.

## Decisión

1. **Una regla de alcance, en una función: `core.has_permission_for_scope`.**
   - Un permiso de grupo cubre todo el grupo; uno de marca, la marca y sus locales; uno de restaurante, solo ese local.
   - Valida que el alcance pedido cuadre con la estructura.
   - `has_permission`, `has_permission_in_brand` y `has_permission_in_group` son atajos de esta función.
   - Antes de decidir, exige que la sesión pueda operar (`core.current_session_ok`):
     - perfil activo;
     - sin bloqueo temporal;
     - con doble verificación (aal2) si algún rol vigente la exige. El MFA corta todo.
2. **Versiones "de conjunto" para las políticas** de tablas que crecen: `core.permitted_restaurant_ids`, `visible_brand_ids`, `visible_user_ids` y `visible_assignment_ids`.
   - Aplican la misma regla de alcance, pero devuelven el conjunto de ids una vez por consulta.
   - La política queda `id in (select core.permitted_restaurant_ids('org.view'))`.
   - Con 2.000 locales y 500 personas, las listas pasaron de unos 750 ms a menos de 5 ms.
   - **Toda tabla de negocio de la Fase 2 en adelante sigue este patrón.**
3. **Funciones de decisión en plpgsql**, leyendo el JWT una sola vez por llamada (0,24 ms por llamada).
4. **La API solo lee.** `authenticated` tiene `SELECT` con RLS y ningún `INSERT`, `UPDATE` ni `DELETE` directo. Toda escritura va por funciones (RPC) que:
   - validan el permiso en la base;
   - fijan motivo y origen;
   - dejan que los triggers completen el control y la auditoría.

   En `org`, crear, cerrar, borrar y restaurar piden `org.manage` en el nivel de arriba, y editar nombre y datos, en el propio nivel.

5. `has_permission_anywhere` existe solo para mostrar u ocultar menús. Ninguna política la usa, y una prueba lo controla.

## Consecuencias

- La prueba `050_permissions` fija la lista exacta de funciones y tablas que `authenticated` puede usar en los 12 esquemas. Abrir algo nuevo obliga a actualizarla a propósito.
- La condición de vigencia de una asignación se repite dentro de cada consulta de permisos, a propósito, para que Postgres use los índices.
- Pendiente de decidir con Joaco: hoy un local **cerrado o borrado** sigue dando permisos a quienes tenían rol ahí. Las escrituras igual las frenan P13 y la jerarquía.
