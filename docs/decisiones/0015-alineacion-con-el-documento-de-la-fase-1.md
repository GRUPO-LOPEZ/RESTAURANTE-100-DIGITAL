# ADR-0015 — Alineación con el documento de la Fase 1 de Soy

- **Fecha:** 2026-10-21
- **Estado:** aceptada. Joaco decidió que el documento de Soy (`docs/fases/fase-1.md`) manda sobre lo construido y aprobó el plan de alineación. Se implementó en cuatro migraciones:
  - `20261021180000_phase_doc_enums.sql`
  - `20261021180100_align_with_phase_doc.sql`
  - `20261021190000_phase_doc_features.sql`
  - `20261021200000_phase_doc_screens.sql`

## Contexto

La Fase 1 se construyó con el prompt maestro y con las decisiones de Joaco (ADR-0005 a ADR-0014). Después llegó el documento de Soy, con la bajada técnica de la Fase 1: nombres de tablas y columnas, permisos, pantallas y la compuerta de cierre. Comparándolo con lo construido aparecieron:

- nombres distintos;
- columnas que faltaban;
- cinco pantallas que no existían;
- un tablero distinto del pedido.

## Decisiones de Joaco (2026-10-21)

1. **El documento manda.** Lo que difiere se ajusta con migraciones nuevas, sin editar las ya commiteadas.
2. **Nombres:** se usan los del documento.
   - `audit.authentication_security_events`, con `user_id`, `ip_address` y `detail`.
   - `audit_events.actor_user_id`, `table_schema` y `source`.
   - `workflow.request_approval()` y `workflow.decide_approval()`.
   - `required_permission`, `min_approvers`, `allow_self_approval` y `proposed_changes`.
3. **Suspender es una pausa.**
   - Corta el acceso al instante y cierra las sesiones.
   - La levanta, **sin aprobación**, cualquiera con `users.deactivate` sobre esa persona.
   - **Desactivar** sigue siendo "la persona se fue": volver necesita la aprobación de otra persona.
4. **Avisos solo dentro de la app** (`core.notifications`), sin correo. `request_approval` avisa a quienes pueden decidir.
5. **Permisos: se suman sin quitar.**
   - Entran `permissions.manage` (pedir cambios de la matriz), `security.view` (el registro de seguridad) y `org.archive` (archivar y restaurar).
   - Se quedan `roles.assign` y `org.transfer`, porque el documento dice que el catálogo se amplía con el mismo formato.
   - `roles.manage` pasa a ser el catálogo de roles.

## Cómo se implementó

- **Estados de cuenta:** `active`, `suspended` y `deactivated` (antes `disabled`).
  - El hook de ingreso niega el token a las suspendidas.
  - `has_permission` les corta el acceso en la consulta siguiente.
- **Columnas de la sección 4:**
  - **Grupo:** razón social y CUIT. **Marca:** código único por grupo, obligatorio.
  - **Perfil:** usuario, puesto, área, primer y último acceso, quién invitó y el último local elegido.
  - **Membresía:** marca o local donde trabaja, con fechas de inicio y fin.
  - **Permiso:** la acción, separada del módulo.
- **Membresías con fechas.** Un rol vale solo con una membresía vigente en el grupo.
  - Para dar un rol hace falta una membresía **sin fecha de fin**. Si no, el rol podría "revivir" al sumarse otra membresía (revisión de seguridad).
  - No se termina la última membresía mientras haya roles vigentes.
- **Columnas sin historia** (`audit.untracked_columns`): el último acceso, el local elegido y la lectura de un aviso.
  - No generan evento ni marcan la fila como editada.
  - Cualquier otro cambio en la misma fila sí se audita.
  - La lista es explícita y está probada.
- **Auditoría (sección 6):**
  - columnas nuevas: módulo, número de operación (uno por transacción), estado del registro y rol principal de quien actuó;
  - cuenta técnica separada de la persona;
  - acciones nuevas: `approve`, `reject` y `publish`;
  - el contexto viaja en `app.change_reason`, `app.change_source` y `app.operation_id`.
- **Sellos.** La huella de cada evento ignora las columnas vacías del primer nivel. Así, sumar una columna nueva que nace vacía no invalida los sellos.
  - Renombrar columnas sí los invalida. Por eso la migración de alineación **solo se aplica si todavía no hay sellos**, y aborta si los hay.
  - Hoy es así: no existen staging ni producción, y en local se recrea la base.
- **Aprobaciones:**
  - Cada solicitud guarda el antes (`previous_values`), lo que cambia (`proposed_changes`), la tabla y el registro.
  - La autoaprobación nace en falso. Activarla, o pedir menos aprobaciones, no se puede con una edición: hace falta una migración.
- **Registro de seguridad:** los cambios de contraseña y los registros de doble verificación los anota la base, con triggers sobre Auth. No hay una función que la pantalla pueda llamar para inventarlos.
- **Sesiones cerradas.** `has_permission` exige que la sesión del token siga existiendo en Auth.
  - Cerrar las demás sesiones desde "Mi cuenta", salir, desactivar o suspender corta el acceso en la consulta siguiente, no cuando vence el token.
  - Si el token no trae `session_id` (por ejemplo, en pgTAP), no se aplica.
- **Historial y exportación** (`core.audit_scope_events`):
  - lee por índice en cada alcance;
  - el filtro por persona usa su propio índice;
  - las fechas se convierten en números de evento leyendo una sola fila del índice por fecha. Supuesto: **ninguna transacción dura más de una hora**. El filtro por fecha se sigue aplicando exacto sobre lo que se muestra;
  - la exportación oculta los costos también dentro de los valores compuestos y deja un evento `audit_exported`.
- **Tabla de ensayo `core.test_documents`** (sección 10). Imita una receta y se lee solo por la vista `core.v_test_documents`:
  - el costo sale vacío sin `test_documents.view_costs`;
  - quien no edita ve solo lo publicado.

  Se borra con una migración al cerrar la Fase 1. Permisos de ensayo:

  | Permiso    | Lo tienen                                                     |
  | ---------- | ------------------------------------------------------------- |
  | Ver        | Todos los roles operativos                                    |
  | Editar     | Jefe de Cocina, Chef, Gerente, Director de Marca y Superadmin |
  | Publicar   | Chef y Director de Marca                                      |
  | Ver costos | Controller y Dirección                                        |

  Respecto del plan aprobado, se sumaron Gerente, Director de Marca y Superadmin, porque nadie da un rol con permisos que no tiene:
  - sin "editar", el Gerente no podría dar el rol de Jefe de Cocina;
  - sin ver, editar y publicar, el Director de Marca no podría dar el rol de Chef;
  - sin ver y editar, el Superadmin no podría suspender ni desactivar a quien los tiene.

  **Le falta el visto bueno de Joaco.**

## Diferencias que quedan con el documento (y por qué)

| Documento                                                              | Lo construido                                                                       | Motivo                                                                                                                           |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `granted_by`, `granted_at`, `revoked_at`, `revoked_by` en asignaciones | `created_*` y `deleted_*`                                                           | El mismo documento exige las columnas de control en todas las tablas. Serían columnas duplicadas.                                |
| `has_permission(code, brand_id, restaurant_id)`                        | `has_permission(code, restaurant_id)`, más las variantes por marca, grupo y alcance | Decidido en ADR-0012: cada variante usa un índice y no hay ambigüedad de alcance.                                                |
| Una política RLS por operación                                         | Solo lectura por la API; las escrituras van por funciones                           | ADR-0005: sin política no hay acceso, como pide la sección 5, y cada escritura lleva motivo y auditoría en la misma transacción. |
| 10 migraciones numeradas, un PR por sesión                             | 15 migraciones con fecha, en una rama                                               | La Fase 1 ya estaba construida cuando llegó el documento. Una migración commiteada no se edita.                                  |
| Exportar sin límite                                                    | Hasta 5.000 eventos por pedido                                                      | Rendimiento. Para más, se exporta por períodos.                                                                                  |
| `login_denied` como acción de auditoría                                | Va al registro de seguridad                                                         | La misma sección 6 lo manda ahí.                                                                                                 |
| Pantalla de usuarios con el tablero                                    | `/usuarios` es el tablero; la lista está en `/usuarios/lista`                       | En el celular, tablero y lista juntos quedaban demasiado largos.                                                                 |

## Pendiente de decidir con Joaco

- **La Chef publica lo que ella misma mandó a revisión.** Hoy se permite. La revisión de seguridad propone exigir que publique otra persona, que es lo que harán las recetas reales de la Fase 2.
- **Columnas que ve quien tiene `users.view`:** el último acceso, el motivo de la suspensión o la baja y quién invitó. ¿Las ve todo el que ve a la persona, o solo quien la administra?
- **El lugar de la membresía no limita los roles.** Una membresía de un local valida un rol de todo el grupo.
- **Colores de los gráficos.** Los pasteles de `design.md` tienen poco contraste para las barras. Se compensó con borde oscuro, leyenda con texto y tabla. ¿Sumamos tonos más oscuros solo para gráficos?
- **Exportación:** límite de frecuencia y período máximo. Hoy, hasta 2.000 cambios por archivo, avisado en la pantalla.
- **Comparación de los KPI** (regla de tableros 2). Solo "Accesos rechazados" se compara con los 7 días anteriores. "Cuentas activas", "Desactivadas o suspendidas" y "Aprobaciones pendientes" muestran el estado actual. Hay dos caminos:
  - compararlas con hace 7 días (altas y bajas del período);
  - dejarlas como excepción escrita.
- **React Hook Form** (`design.md`). Los formularios usan `useActionState` y validan con zod en el servidor, como el resto del proyecto. No hay errores por campo ni validación antes de enviar. Hay dos caminos:
  - sumar React Hook Form;
  - escribir la excepción y devolver los errores por campo desde el servidor.
- **"Recordar mi sesión" viene marcado.** En tablets compartidas de la cocina, ¿conviene que venga sin marcar?

## Revisión de diseño (2026-10-22)

`ui-reviewer`: sin graves. Se corrigieron los medios:

- **Menú en el celular:** queda detrás de "Menú" y marca la pantalla actual con `aria-current`.
- **Filtros:** se pliegan en el celular, con el resumen de los activos.
- **Selector de local:**
  - se confirma con "Cambiar", y moverse por la lista con el teclado no cambia nada;
  - muestra el error si la base lo rechaza;
  - la etiqueta se ve;
  - al cambiar, saca el `?local=` de la dirección.
- **Gráfico:** pasa a semanas en períodos de más de 45 días, y muestra un estado vacío si no hubo ingresos.
- **Exportación:**
  - si falla, vuelve al historial con un aviso;
  - el CSV sale en español, con la hora de Buenos Aires;
  - la pantalla avisa el tope.
- **Ficha:** las acciones con motivo van plegadas.
- **Mi cuenta:** nunca queda en blanco.
- **Filtro de persona del historial:** incluye a la persona elegida aunque no esté entre las primeras 100.

Menores corregidos:

- los requisitos de la contraseña pasan a ser la ayuda del campo;
- "100 o más" en la bandeja;
- la matriz completa muestra descripciones en español;
- "Cancelar" al cambiar de app de verificación;
- el KPI sin permiso, el contador en la grilla de 8 px y los separadores vacíos;
- el enlace de la ficha al historial de la persona.
