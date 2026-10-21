# ADR-0009 — Las operaciones rechazadas quedan registradas

- **Fecha:** 2026-10-20
- **Estado:** aceptada por Joaco (P17, opción 2). Se implementa en M6, M7, M8 y M9. El diseño detallado se aprueba en el plan de cada una.

## Contexto

La prueba obligatoria 11 del Módulo Maestro dice "Una operación rechazada queda registrada". Se podía entender de dos maneras:

1. Solo las solicitudes de aprobación rechazadas.
2. Además, los intentos que la base frena por falta de permiso.

Hay un problema técnico con la segunda: cuando la base rechaza una operación con un error, deshace toda la transacción, y con ella el evento de auditoría. Lo mismo pasa con los ingresos fallidos que pide la prueba adicional 7 (P5).

## Decisión

**Opción 2.** Quedan registradas:

- las solicitudes de aprobación rechazadas, en `workflow.approval_decisions` (M7);
- los **intentos frenados en las funciones críticas**: dar o quitar roles (`assign_role`), decidir aprobaciones (`workflow.decide`), bloquear o reactivar cuentas (`disable_user` y su par), invitar (`register_invitation`), traspasar locales o marcas y cambiar la matriz.

No se registra cada consulta que RLS filtra, para no llenar el registro de ruido.

**Cómo se guarda a pesar del rollback:**

- Las funciones críticas validan los permisos **antes** de cambiar nada.
- Si el permiso falta, anotan el intento en un registro de seguridad, solo de inserción, en el esquema `audit`, y **terminan sin error**: devuelven un resultado de "rechazado" con el motivo.
- Como la transacción termina bien, el registro queda guardado y no se cambió ningún dato.
- Los errores de datos (formato, alcance incoherente) siguen siendo errores comunes.

El registro de seguridad se arma junto con el de ingresos y fallos (P5 y prueba adicional 7). Tiene las mismas protecciones que `audit_events`:

- nadie lo modifica ni lo borra;
- nunca guarda contraseñas ni tokens;
- solo lo leen quienes tienen `audit.view`.

## Consecuencias

- La interfaz tiene que mirar el resultado de estas funciones, no solo si hubo error.
- La prueba 11 se escribe con varios casos: un cocinero que intenta dar un rol, un gerente que intenta aprobar y alguien que intenta aprobar su propia solicitud. En todos se verifica que el intento queda registrado y que no cambió ningún dato.
- Una función nueva que se sume a la lista de críticas tiene que seguir el mismo patrón. `db-reviewer` lo controla.
