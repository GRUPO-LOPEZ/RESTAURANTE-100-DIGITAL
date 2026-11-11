# ADR-0039 — Matriz de permisos con edición directa

- **Fecha:** 2026-11-11
- **Estado:** aceptada por Joaco.
- **Pedido:** prompt de Soy «Rediseño pantalla Roles y permisos → Matriz de permisos».

## Contexto

La pantalla de Roles mostraba los permisos de un rol por vez, con «Lo tiene / Pedir que se lo quiten». Cada cambio era una solicitud que aprobaba Dirección General, una persona distinta de quien lo pedía (ADR-0008).

Soy pidió:

- una matriz de roles por permisos;
- toggles de un clic, un contador de cambios y guardado en lote;
- un criterio de «edición directa» en el CLAUDE.md, para todo el sistema.

## Decisiones de Joaco (2026-11-11)

1. **«Guardar cambios» aplica en el momento**, sin la aprobación de Dirección. Cambia ADR-0008 solo para la matriz: el catálogo de roles y las asignaciones siguen igual.
2. **Mixto, después de la revisión de seguridad:**
   - las quitas y las altas de permisos comunes se aplican al guardar;
   - las altas de **permisos sensibles** (`is_sensitive`, el punto naranja) quedan como pedido para Dirección General.

   Sin esto, el Superadministrador podía darle en el momento «Cambiar la matriz de permisos» a un rol como Compras, que entra sin doble verificación, y alguien de Compras terminaba administrando la seguridad sin que nadie lo aprobara.

   Joaco eligió «una solicitud que aprueba Dirección». Se implementó con el pedido que ya existía, **uno por cada permiso sensible** (`core.request_role_permission_change`). Ese pedido ya estaba probado: lo aprueba Dirección y nunca quien tiene ese rol. Si se prefiere una sola tarjeta para todo el lote, hace falta un tipo de aprobación nuevo, y eso va en otro PR.

## Cómo quedó

- **Lo que ya existía y se usa:**
  - `core.roles` (ordenada por `level`), `core.permissions`, `core.role_permissions` (con borrado lógico) y su auditoría;
  - `core.check_role_permission_change`, `core.request_role_permission_change` y `core.permission_matrix`;
  - el permiso **`permissions.manage`**, que es lo que el pedido llama «roles.manage». `roles.manage` existe, pero es para editar el catálogo de roles.
- **Lo nuevo en la base** (`20261125120000_permission_matrix.sql`):
  - `core.permissions.name` (nombre corto, obligatorio en lo vigente) y `sort_order` (no negativo), cargados para los 40 permisos. La descripción pasa a ser el texto del tooltip;
  - `core.permission_modules`: nombre y orden de cada módulo. Es un catálogo global, como los roles;
  - **`core.apply_permission_matrix(grupo, cambios, motivo)`**, que guarda todo o nada:
    - primero controla la forma y el tamaño (hasta 1.000 cambios, ids de verdad, ninguna celda repetida);
    - pide `permissions.manage` en el grupo; si no lo tiene, `core.deny` deja el intento en el registro de seguridad, con la cantidad de cambios y no el lote entero;
    - bloquea la matriz y el alta de roles de los grupos afectados (`core.lock_group_roles`, siempre en el mismo orden), para que una asignación simultánea no deje a una persona aprobando y administrando la seguridad a la vez;
    - rechaza cualquier cambio sobre un rol que la persona tiene;
    - aplica primero las quitas y después las altas comunes, cada una controlada con `check_role_permission_change`;
    - pide las altas sensibles con `request_role_permission_change`, con el mismo motivo;
    - el motivo es obligatorio y cada alta o quita queda en `audit.audit_events`;
  - que nunca falte quien cambie la matriz ni quien apruebe lo garantizan los bloqueos fijos de `check_role_permission_change` (al Superadministrador no se le quitan `permissions.manage` ni `roles.manage`, y a Dirección no se le quita `approvals.decide`);
  - `core.apply_role_permission_change` (aplicar un pedido aprobado) toma los mismos bloqueos;
  - `core.permission_matrix` devuelve además los módulos, el nombre y el orden.
- **Pantalla `/roles`** (`components/permission-matrix.tsx`):
  - filas de permisos agrupadas por módulo y columnas de roles; el encabezado de roles queda a la vista al bajar en la computadora;
  - la primera columna queda fija, y en el celular la tabla se corre de costado;
  - en 1440 px entran los 10 roles;
  - cada celda es un botón de 44 px con `aria-pressed`: ✓ sobre `ok`, ✕ sobre `bad`, y la celda cambiada lleva un borde punteado. Los colores son **los tokens del sistema y no los hex del pedido**, que son casi iguales;
  - una celda con un pedido esperando muestra un reloj, sobre `info`, y no se puede tocar;
  - un punto marca los permisos sensibles;
  - el tooltip (`components/ui/tooltip.tsx`, con el Radix que ya estaba instalado) se abre con el mouse y con el teclado, y muestra la descripción y el código. En el celular la descripción va debajo del nombre;
  - el borrador local lleva contador, motivo obligatorio, Descartar y Guardar. Hay un enlace «Ir a guardar los cambios» para el teclado, una confirmación al dar permisos sensibles y un aviso al salir con cambios;
  - la columna de un rol propio se ve, pero no se puede cambiar.
- **CLAUDE.md:** sección «Edición directa», y la referencia en `.claude/rules/design.md`.

## Riesgos y límites

- **Las quitas y los permisos comunes no tienen aprobación.** Quien tiene `permissions.manage` (hoy, solo el Superadministrador) puede quitarles permisos a otros roles en el momento, incluso permisos sensibles. Lo limitan:
  - no poder tocar un rol propio;
  - los permisos que no se quitan;
  - la auditoría con motivo.
- **La matriz es una sola para todo el sistema** (los roles no tienen grupo). Hoy hay un grupo. Si se suma otro, quien tenga `permissions.manage` en uno cambiaría los roles de todos, y hay que revisarlo.
- **Pedidos de antes:** los pedidos pendientes de la matriz siguen en Aprobaciones y se pueden aprobar. Al aplicarse vuelven a controlar las reglas, con los mismos bloqueos.
- **Quién entra:** solo quien tiene `permissions.manage`, como antes. El pedido decía «solo lectura o sin acceso».
- **La prueba 12 del Módulo 0** usaba el cambio de matriz con aprobación. Ahora usa dar un rol que aprueba (Chef Ejecutivo), y Dirección lo rechaza. Prueba lo mismo: la decisión queda con identidad, fecha y comentario, y nadie la decide sobre lo propio.

## Revisiones (2026-11-11)

- **`security-auditor`: no apto en la primera versión**, por el hallazgo grave de los permisos sensibles. Se resolvió con la decisión 2. También se corrigieron:
  - la carrera con las asignaciones de roles;
  - los bloqueos al aplicar pedidos viejos;
  - que un rechazo pudiera llenar el registro de seguridad;
  - los duplicados escritos en mayúsculas;
  - el control del rol propio, que ahora se hace después del bloqueo.
- **`db-reviewer`:** el grave (el nombre obligatorio rompía los datos de prueba de `040` y `060`) quedó corregido completando los nombres en esas pruebas. También:
  - el control final, que no podía dispararse, se reemplazó por los bloqueos fijos, documentados;
  - se agregó `sort_order >= 0`;
  - se documentó que el catálogo es global;
  - se validan los ids de verdad;
  - se sumaron pruebas de RLS de los módulos y del mensaje de la restricción.
- **`ui-reviewer`, sin graves de código.** Se corrigieron:
  - la descripción en el celular;
  - el ancho de la primera columna;
  - el encabezado fijo;
  - el enlace para saltar a Guardar;
  - el motivo obligatorio, con foco al faltar;
  - el nombre del módulo y el borde de la columna fija;
  - la barra alineada con los márgenes y oculta en el celular sin cambios;
  - la marca de la celda cambiada, que no se pierde con el foco;
  - el subrayado visible;
  - «sensible» en el nombre accesible;
  - la tabla a todo el ancho;
  - axe con WCAG 2.2.

  Quedó como está, a pedido explícito de Soy: el código técnico en el tooltip y el rojo para «No lo tiene».

## Pruebas

- **pgTAP `260_permission_matrix` (38):**
  - estructura, nombres y RLS de los módulos;
  - el lote, todo o nada;
  - un lote mixto, y que lo sensible quede pedido y Dirección lo apruebe;
  - los rechazos: sin permiso, sin doble verificación, sin sesión, rol propio, separación de funciones y permisos que no se quitan;
  - el motivo, la auditoría, y los duplicados en mayúsculas.

  Además se ajustaron `040`, `050` y `060`.

- **Vitest `permission-matrix.test.ts`:** el borrador.
- **Playwright `roles.spec.ts`:**
  - el contador, guardar y recargar;
  - lo sensible, confirmado y pendiente;
  - el rol propio y el tooltip con teclado;
  - que sin permiso no se entra;
  - la columna fija y todos los roles en 1440 px;
  - axe con WCAG 2.2, en celular y computadora.

  La prueba 12 está en `admin.spec.ts`.
