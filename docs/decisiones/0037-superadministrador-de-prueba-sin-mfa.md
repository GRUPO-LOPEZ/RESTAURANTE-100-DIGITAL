# ADR-0037: Superadministrador de prueba sin doble verificación (temporal)

- **Fecha:** 2026-11-10
- **Estado:** aceptada, temporal. Joaco aprobó el plan.
- **Excepción a:** el Módulo 0 de Soy (`docs/modulos/00-identidad.md`) y `.claude/rules/security.md`, que exigen la doble verificación (MFA) en los niveles 1 a 4 y para el Controller.
- **Migraciones:** ninguna.

## Contexto

Joaco pidió otro usuario superadministrador con la doble verificación apagada, solo por ahora y para testear: el MFA ya se probó y funciona, y para recorrer el sistema hace falta entrar sin el código. Lo necesita en la base local y en staging (la preview de Vercel).

## Decisión

- **Un rol de prueba, no una excepción en la base.**
  - El MFA se exige por rol (`core.roles.requires_mfa`), en la base (`core.current_session_ok`) y en la aplicación (`requireOperable`).
  - El rol `superadmin_test` («Superadministrador de prueba») tiene los mismos permisos que el Superadministrador y `requires_mfa = false`. Una persona con ese rol y sin código registrado entra solo con la contraseña.
  - No cambia ninguna migración ni la regla de MFA de los demás usuarios. Una marca «sin MFA» por usuario en la base habría llegado a producción y abierto una puerta para saltear el MFA. Se descartó.
- **Fuera del seed:** `040_identity` y `050_permissions` controlan que el catálogo tenga los 10 roles del Módulo 0. Por eso el rol y la persona se crean con un script aparte, `supabase/dev/test-superadmin.sql`, que se corre a pedido:
  - **local:** `npm run db:test-admin`, después de cada `npm run db:reset`, con la contraseña pública de desarrollo del seed;
  - **staging:** Actions → «Publicar en staging» → «Crear el superadministrador de prueba», con el secreto `STAGING_TEST_ADMIN_PASSWORD`, que crea Joaco en GitHub.
- **Guardas del script:**
  - solo corre si el único grupo de la base es el ficticio de prueba (en producción no existe);
  - la contraseña va en una sola consulta, que valida y calcula el hash con costo 10, y enseguida se borra: nunca viaja en un INSERT que Postgres pueda registrar;
  - la contraseña llega por variable de entorno, con al menos 16 caracteres, letras y números, y nunca se escribe en el repositorio;
  - se puede correr más de una vez sin cambiar nada;
  - deja el motivo en la auditoría, con el número de corrida de GitHub Actions;
  - una prueba de Vitest (`tests/unit/test-superadmin-guard.test.ts`) falla si el script aparece en otro flujo, en una migración o en el seed.
- **Persona:** `superadmin.prueba@ejemplo.test`, a nivel de todo el grupo ficticio.

## Riesgos que se aceptan mientras exista (revisión de seguridad, 2026-11-10)

- **Puede suspender o dar de baja a otro Superadministrador sin la aprobación de Dirección.** Las funciones de gobierno solo desvían a aprobación cuando quien pide tiene el rol exacto `superadmin`. Hoy hay un solo Superadministrador en local y en staging, y la regla de que el grupo no se quede sin uno lo frena. **No cargar un segundo Superadministrador en staging mientras exista el rol de prueba.**
- **El rol se puede asignar a otras personas desde Usuarios.** Como tiene permisos sensibles, el pedido lo aprueba Dirección, pero el pedido no muestra que no pide la doble verificación. **Dirección no tiene que aprobar pedidos de «Superadministrador de prueba».** Una persona que además tenga otro rol con doble verificación la sigue necesitando.
- **Puede proponer cambios en la matriz del rol Superadministrador.** Los aprueba Dirección. Las bajas de `roles.manage` y `permissions.manage` siguen prohibidas.
- **Queda sin actor en la auditoría,** porque el script corre como `postgres`, igual que el seed. Lo identifica el motivo.

## Lo que no hace

- Las acciones que el sistema reserva al rol exacto `superadmin`: dar o aprobar el rol de Superadministrador, y la regla de que el grupo no se quede sin uno. Para eso sigue el Superadministrador de siempre, con su código.
- **En la base local**, después de correr el script, `040` y `050` fallan porque hay 11 roles. Antes de correr las pruebas, `npm run db:reset`. GitHub Actions recrea la base y no se ve afectado.

## Cómo se quita

- **En staging, desactivar la cuenta no alcanza:** la asignación y el rol quedan vivos, y el rol se podría seguir asignando. Hay que quitarle el rol a la persona, desactivar la cuenta y después dar de baja (borrado lógico) los permisos del rol y el rol. La historia se conserva; nada se borra físicamente.
- **En el código:** cuando ya no haga falta, se sacan el script, la opción de Actions y el secreto. **Antes de la Fase de producción tiene que estar quitado.**
