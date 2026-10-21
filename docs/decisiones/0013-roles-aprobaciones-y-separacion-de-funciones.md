# ADR-0013 — Dar y quitar roles, aprobaciones y separación de funciones

- **Fecha:** 2026-10-21
- **Estado:** aceptada.
  - El punto 2 lo decidió Joaco el 2026-10-20 (el superadmin pide y Dirección General aprueba).
  - El resto sale de las revisiones de seguridad y de base de datos de M6 y M7, dentro del plan aprobado de la Fase 1.
  - Se implementó en `20261020223502_roles_and_approvals.sql`.

## Contexto

La regla contra la escalada de privilegios es esta: quien da un rol tiene que tener todos sus permisos. Con la matriz aprobada, eso deja a nadie habilitado para dar Dirección General ni Controller a nivel de grupo, porque el Superadministrador no tiene `approvals.decide`.

La primera auditoría de seguridad de M6 y M7 mostró además estos huecos:

- **Excepción sin control:** lo que pedía el superadmin con su excepción lo podía aprobar cualquiera con `approvals.decide`, por ejemplo Controller.
- **Quitar roles a los superiores:** el superadmin podía quitarles el rol a las dos personas de Dirección General y dejar al grupo sin aprobadores.
- **Matriz por etapas:** un cambio de la matriz se podía armar en pasos para darle permisos de seguridad a quien aprueba.

## Decisión

1. **Única vía:** `core.assign_role` y `core.revoke_role`. No hay escritura directa sobre las asignaciones. Las dos funciones devuelven `applied`, `pending_approval` o `denied`, y los rechazos quedan registrados (ADR-0009).
2. **El Superadministrador puede pedir cualquier rol** para otra persona, aunque tenga permisos que él no tiene.
   - Ese pedido siempre lo aprueba **Dirección General**, con su rol asignado para todo el grupo (flujo `core.assign_by_superadmin`).
   - Quitar un rol con permisos que el superadmin no tiene también es un pedido, por el flujo `core.revoke_by_superadmin`.
3. **Roles sensibles con aprobación de otra persona:** los que aprueban cambios (`approvals.decide`), los que administran la seguridad (`roles.manage`, `workflows.manage`) y Superadministrador.
4. **Superadministrador y Dirección General:**
   - solo se dan para todo el grupo;
   - no llevan vencimiento;
   - el grupo nunca se queda sin al menos una persona activa con cada uno de esos dos roles (`core.group_governance_gap`, con un bloqueo por grupo para que dos cambios simultáneos no se crucen).
5. **Separación de funciones**, que sale del Módulo Maestro: Dirección General no administra la seguridad técnica y el Superadministrador no aprueba cambios de negocio.
   - Ningún rol junta `approvals.decide` con `roles.manage` o `workflows.manage`.
   - Ninguna persona junta esos dos tipos de rol en el mismo grupo.
   - A Dirección General no se le quita `approvals.decide`, y al Superadministrador no se le quita `roles.manage`.
6. **Quién no aprueba:** quien pidió el cambio, la persona afectada, quien bloqueó la cuenta (en las reactivaciones) y, en los cambios de la matriz, cualquiera que tenga hoy el rol que se cambia.
7. **Lo aprobado es lo pedido:**
   - el pedido no se puede modificar;
   - cada función que aplica vuelve a validar todo: quien pidió sigue con permiso, el rol no cambió de permisos, la persona sigue activa y el lugar sigue abierto.

   Si algo dejó de valer, la aprobación no se aplica y la solicitud queda pendiente. La puede retirar quien la pidió.

8. **La función que aplica** solo puede ser una `apply_*(uuid)` de `core` u `org`, y quien aprueba tiene que ser un permiso y unos roles que existan.

## Consecuencias

- Un cambio de la matriz sobre el rol Dirección General no lo puede aprobar nadie, porque todas las personas de Dirección General quedan excluidas. Solo se hace con una migración documentada.
- Nadie puede desactivar a una persona de Dirección General desde la app, porque tiene permisos que nadie más tiene. Solo con una migración documentada. **Pendiente de confirmar con Joaco.**
- Dos superadmins se pueden quitar el rol entre sí sin aprobación, siempre que quede uno. **Pendiente de confirmar con Joaco.**
- Controller tiene `approvals.decide` en todo el grupo, así que puede aprobar que se le dé a alguien un rol sensible de marca o de local (ADR-0008). **Pendiente de confirmar con Joaco.**
- Los roles y la matriz son del sistema entero, no de cada grupo. Con un solo grupo no cambia nada. Si se suma otro negocio, hay que revisarlo.
