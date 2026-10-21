# ADR-0008 — Qué cambios de la Fase 1 necesitan aprobación

- **Fecha:** 2026-10-20
- **Estado:** aceptada por Joaco (P7). Se implementa en M6 y M7. Las aprobaciones de recetas y precios se definen en la Fase 2.

## Contexto

La sección 6 del prompt maestro pide que las políticas puedan exigir que apruebe alguien distinto de quien pidió el cambio, y que **lo valide la base, no la pantalla**. La revisión de seguridad de M4 mostró los riesgos de no hacerlo:

- **Cuentas títere:** quien tiene `users.invite` y `roles.assign` puede invitar un segundo correo propio y darle un rol que aprueba.
- **Superadmin que se da permisos:** con `roles.manage` puede editar la matriz y darse `approvals.decide`.

## Decisión

| Cambio                                                                                               | Aprobación | Quién aprueba                                                        |
| ---------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------- |
| Dar un rol con `approvals.decide` (Dirección General, Director de Marca, Chef Ejecutivo, Controller) | Sí         | Otra persona con `approvals.decide` en ese alcance                   |
| Dar el rol Superadministrador                                                                        | Sí         | Dirección General                                                    |
| Dar un rol sin `approvals.decide` (Gerente, Jefe de Cocina, Compras, Cocinero, Auditor)              | No         | Se aplica al instante, con las reglas de M6, y queda en el historial |
| Cambiar la matriz de permisos o el catálogo de roles                                                 | Sí         | Dirección General, distinta de quien lo pide                         |
| Traspasar un local o una marca (ADR-0007)                                                            | Sí         | Dirección General                                                    |
| Crear o editar marcas, locales y áreas                                                               | No         | Queda en el historial                                                |
| Bloquear una cuenta                                                                                  | No         | Inmediato, por seguridad; queda en el historial con motivo           |
| Reactivar una cuenta bloqueada                                                                       | Sí         | Otra persona, distinta de quien la bloqueó                           |

Reglas comunes:

- **Un solo aprobador**, siempre distinto de quien pide (`requires_different_approver = true`, `required_approvals = 1`).
- La base lo valida en `workflow.decide`. La prueba adicional 2 lo demuestra.
- Lo que se aprueba es exactamente lo que se aplica: el pedido no cambia después de creado (M7).
- Mientras la solicitud está pendiente, el cambio no tiene efecto.

## Consecuencias

- M6: `assign_role` crea una solicitud en vez de aplicar cuando el rol incluye `approvals.decide` o es Superadministrador.
- M7: el catálogo inicial de `workflow.approval_workflows` sale de esta tabla.
- Hace falta al menos una persona de Dirección General activa para aprobar los cambios críticos. Si no hay ninguna, el camino de emergencia es una migración documentada, con motivo en el historial.
- Se puede ajustar después desde el panel (`workflows.manage`) sin tocar código.
