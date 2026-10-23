# ADR-0017 — Las preguntas pendientes de la Fase 1

- **Fecha:** 2026-10-23 (decidido por Joaco el 2026-10-22).
- **Estado:** aceptada. Se implementó en `20261023120000_old_questions.sql`, con las pruebas `130_old_questions.test.sql`.

## Contexto

En `docs/estado.md` quedaban seis preguntas sobre permisos y cuentas. No frenaban la demo de cierre, pero sí la salida a producción. Joaco aceptó las recomendaciones. La sexta se cambió al revisar el código.

## Decisiones

1. **Quitarle el rol a otro Superadministrador lo aprueba Dirección General.**
   - Va por el mismo camino que ya existía para los roles con permisos que uno no tiene (`core.revoke_by_superadmin`).
   - Quitarse el rol uno mismo sigue siendo directo, salvo que sea el último.
   - **Suspender o dar de baja la cuenta** de otro Superadministrador también lo aprueba Dirección. Si no, la regla se esquivaba con una sola llamada (revisión de base, G1; Joaco, 2026-10-23). Es el tipo de aprobación `core.change_superadmin_status`. Levantar la suspensión y reactivar siguen sus reglas de siempre.
2. **Un local o una marca inactivos o borrados dejan de dar permisos.**
   - Lo controla `core.assignment_unit_open`, desde las tres funciones de donde salen todos los permisos (`actor_grants`, `user_has_permission_for_scope` y `user_has_role_for_scope`).
   - Los roles de marca o de grupo siguen viendo el local cerrado y su historia.
   - Si la unidad se reabre, los roles vuelven a valer.
   - Es `security definer` con `search_path` vacío, como el resto, y no se puede ejecutar desde la API.
   - **Efecto a tener en cuenta:** quien cierra una marca (el Superadmin, con `org.manage`) corta al instante los roles de esa marca, incluidos los de quienes él no podría suspender. Queda auditado y se revierte al reabrir.
3. **A una persona de Dirección General se la da de baja o se la reactiva con aprobación.**
   - Lo pide el Superadministrador u otra persona de Dirección. Es la misma función que en la pregunta 1, `core.request_governance_status`, llamada desde `disable_user`, `request_reactivation` y `suspend_user`.
   - Lo aprueba otra persona de Dirección, nunca la afectada ni quien pidió. Es el tipo de aprobación nuevo `core.change_general_management_status`.
   - El grupo nunca se queda sin Dirección: se revisa al pedir y al aplicar.
   - Si no hay otra persona de Dirección que lo pueda aprobar, el pedido se rechaza de entrada, para que no quede pendiente para siempre. Con dos personas en Dirección, la baja la pide el Superadmin y la aprueba la otra.
   - Solo desvía a este camino cuando quien pide puede pedirlo. Al resto le sale el rechazo de siempre, así no se entera de quién es de Dirección.
   - Por ahora vale para una sola persona en un solo grupo: si la persona tiene roles o membresías en otro grupo, se rechaza. Cuando haya varios grupos, el control de "nunca sin gobierno" tendrá que mirar cada uno.
   - **Suspender** a alguien de Dirección sigue como antes.
   - **Los permisos del rol Dirección** solo se cambian con una migración documentada. Quien lo aprobara tendría ese rol y se estaría beneficiando del cambio.
4. **Un rol sensible lo aprueba Dirección General o el Director de Marca de ese lugar.**
   - El Controller y la Chef ya no lo aprueban.
   - El rol de quien aprueba se mira en el lugar de la solicitud. Dirección es de todo el grupo y cubre cualquier lugar; un Director de Marca cubre solo su marca y sus locales.
   - **El Director de Marca solo aprueba si tiene todos los permisos del rol** (decisión de Joaco, 2026-10-23). Es la misma regla que para quien da el rol. Si no los tiene, lo aprueba Dirección.
   - Los demás tipos de aprobación siguen exigiendo el rol para todo el grupo.
   - Los avisos siguen la misma regla.
   - **Pendiente de confirmar con Joaco:** hoy nada impide dar el rol Director de Marca para todo el grupo, con aprobación de Dirección. Quien lo tuviera aprobaría roles sensibles en todo el grupo.
5. **Quien aprueba una reactivación alcanza todos los roles de la persona.** Ya funcionaba así (`workflow.decision_blocker` con `cannot_act_on_user`). Se sumó una prueba.
6. **Bloqueo a propósito de una cuenta (alguien falla 5 veces para dejar afuera a otra persona): se resuelve antes de producción.**
   - Lo recomendado al principio era dejar entrar con contraseña y código correctos aunque la cuenta esté bloqueada. Tenía un problema: la pantalla le mostraría al atacante cuándo acertó la contraseña, y podría seguir probando durante el bloqueo.
   - Para producción, el plan es un **dispositivo de confianza**: el navegador donde la persona ya entró con contraseña y código queda marcado con una cookie firmada en el servidor, y desde ahí puede entrar aunque la cuenta esté bloqueada. Va junto con el CAPTCHA y los límites de frecuencia de ADR-0014.
   - Mientras tanto queda como hoy: el bloqueo dura 10 minutos y un administrador lo puede liberar antes.

## Rendimiento (A10)

Al medir los cambios aparecieron dos lentitudes que ya venían de antes:

| Qué                 | Antes        | Ahora        |
| ------------------- | ------------ | ------------ |
| Tablero de usuarios | 213 a 668 ms | 55 a 123 ms  |
| Historial filtrado  | 147 a 374 ms | 129 a 205 ms |

En los dos casos, el objetivo es por debajo de 300 ms.

- **Cambios críticos:** se leen por tabla. Hay índices nuevos en `audit_events` por alcance y tabla. Antes se recorría todo el alcance hasta encontrar las tablas críticas.
- **Plan de `audit_scope_events`:** se arma con los valores reales de cada llamada (`plan_cache_mode = force_custom_plan`). Con un plan genérico, Postgres suponía un rango de eventos chico y recorría el índice de todos los eventos, descartando unas 76.000 filas por local.
- **Costos en el historial:** dónde se ven los costos se calcula una sola vez por consulta, no dos veces por evento.
- **Costo de los índices:** cada evento de auditoría actualiza un índice más al insertarse (las condiciones de los tres se excluyen entre sí). Con la carga de A10, suman unos 19 MB sobre 101 MB de tabla.
  - En producción conviene crearlos con `create index concurrently`, para no frenar las escrituras auditadas mientras se arman.
- **Falta medir:** los cambios críticos de un rol de grupo con muchos locales (500 a 2.000), porque cada local suma una búsqueda por tabla. Va con la prueba de volumen de producción.
