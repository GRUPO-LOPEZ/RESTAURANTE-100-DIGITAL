# Matriz de permisos: lista de lo que cambia (para Soy)

Pedido: «Rediseño pantalla Roles y permisos → Matriz de permisos». Decisión técnica: ADR-0039. Rama: `feat/matriz-permisos`.

## En pocas palabras

- **Roles y permisos** ahora es una tabla: una fila por permiso, agrupadas por tema (Personas, Recetas, Precios…), y una columna por rol.
- Cada casillero muestra ✓ verde (lo tiene) o ✕ rojo (no lo tiene). **Un clic lo cambia.**
- Los cambios se juntan: abajo se ve «N cambios sin guardar». Con un motivo y **«Guardar cambios»** se guardan todos juntos, o ninguno si algo no se puede.
- **Quitar permisos y dar permisos comunes se aplica en el momento**, sin esperar la aprobación de Dirección General (decisión de Joaco del 2026-11-11).
- **Dar un permiso delicado** (los del punto naranja: administrar la seguridad, aprobar, invitar, bloquear cuentas, ver precios…) **sigue necesitando la aprobación de Dirección General.** Se pide al guardar, y la casilla muestra un reloj hasta que Dirección decide. Así nadie le da en el momento un permiso de seguridad a un rol que entra solo con contraseña.
- Al pasar el mouse (o el teclado) por el nombre de un permiso, se ve qué permite y su código.
- Antes de pedir permisos delicados, el sistema pide confirmación: «Vas a dar N permisos sensibles: quedan pendientes hasta que los apruebe Dirección General. ¿Confirmás?».
- Si te vas de la pantalla con cambios sin guardar, te avisa.

## Lo que no cambia (protecciones que siguen)

- Solo la usa quien tiene el permiso **«Cambiar la matriz de permisos»** (hoy, el Superadministrador).
- **Nadie cambia los permisos de un rol que tiene él mismo.**
- Quien aprueba cambios no puede, además, administrar la seguridad (y al revés).
- El sistema nunca se queda sin alguien que pueda cambiar la matriz ni sin alguien que apruebe.
- Cada cambio queda en el **Historial**: quién, cuándo, qué rol, qué permiso, antes y después, y el motivo.
- Todo lo controla la base, no la pantalla. Llamar a la base «por atrás» tampoco saltea las reglas.

## Para que decidas

- **Sin aprobación para lo común:** hasta ahora, cualquier cambio necesitaba el visto bueno de Dirección. Ahora solo dar permisos delicados. Quitar permisos (también los delicados) lo hace el Superadministrador en el momento, y queda registrado.
- **Una tarjeta por permiso:** si en un mismo guardado se dan varios permisos delicados, Dirección recibe un pedido por cada uno. Si preferís que lleguen todos juntos en una sola tarjeta, se puede hacer en un cambio aparte.
- **Quién ve la pantalla:** sigue siendo solo quien puede cambiarla. Si querés que otros roles (por ejemplo, el Auditor) la vean sin poder tocarla, se agrega.

## Regla nueva para todo el sistema: «edición directa»

Está en las reglas del proyecto (CLAUDE.md) y vale para los módulos que vienen:

- sí/no → un clic;
- pocas opciones → botones a la vista, no listas desplegables;
- explicaciones → al pasar el mouse;
- se edita donde se ve;
- cambios importantes → contador, guardar todo junto y registro en el historial.

## Técnico (para Joaco)

- **Migración** `20261125120000_permission_matrix.sql`: nombre y orden de los permisos, tabla `core.permission_modules` y la función `core.apply_permission_matrix` (las altas sensibles van por `core.request_role_permission_change`). Además, las versiones nuevas de `core.permission_matrix` y de `core.apply_role_permission_change` (con los mismos bloqueos).
- **Pantalla:** `app/roles/page.tsx`, `components/permission-matrix.tsx` y `components/ui/tooltip.tsx`. `Confirm` también se puede abrir sin un botón propio.
- **Pruebas:**
  - nuevas: `260_permission_matrix`, `permission-matrix.test.ts` y `roles.spec.ts`;
  - ajustadas: `040` y `060` (sus permisos de prueba llevan nombre), `050` (inventarios) y la prueba 12 del Módulo 0 en `admin.spec.ts`, que ahora usa la aprobación de un rol.
