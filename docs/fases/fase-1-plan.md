# Plan de la Fase 1 — Fundaciones: identidad, permisos y auditoría

- **Fecha:** 2026-10-20
- **Estado:** borrador para revisar con Joaco y Soy. **No se empieza a construir** hasta responder las preguntas abiertas marcadas como **bloqueantes**.
- **Fuentes:** prompt maestro (secciones 5, 6, 9 y 14). El Módulo Maestro de Usuarios de Soy (`docs/modulos/00-identidad.md`) **todavía no está en el repositorio**: donde este plan depende de él, se marca como pregunta abierta en lugar de suponer.

## Objetivo, en simple

Que el sistema sepa **quién es cada persona, qué puede hacer y dónde**, y que **todo cambio quede registrado para siempre**: quién, cuándo, qué y por qué. Sin esto no se habilita ningún otro módulo.

## Alcance

Esquemas `core`, `org`, `audit` y `workflow`, la función `core.has_permission`, el trigger de auditoría, el seed ficticio y las 13 pruebas obligatorias. **Sin pantallas de negocio**: solo login, la pantalla de "sin acceso" y lo mínimo que piden las pruebas de Playwright.

## Migraciones, en orden

Cada una es un archivo nuevo en `supabase/migrations/` con su prueba pgTAP. Las migraciones van en este orden porque cada una depende de la anterior.

### M1 — Utilidades comunes (`core`)

- `core.set_control_columns()`: trigger `before insert or update` que completa `created_at/by` y `updated_at/by` con `now()` y `auth.uid()`, impide cambiar `id`, `created_at` y `created_by`, y completa `deleted_by` cuando se marca `deleted_at`.
- `core.current_user_id()`: devuelve `auth.uid()`, o la cuenta técnica en uso.
- `core.set_change_context(reason text, origin text)`: hace `set_config('app.reason', ..., true)` y `set_config('app.origin', ..., true)`, que valen solo para la transacción.
- Revocar `execute` a `public` y otorgarlo solo a quien corresponda.

### M2 — Auditoría (`audit`)

- Tipo `audit.action` (enum): `insert`, `update`, `soft_delete`, `restore`, `delete`.
- `audit.audit_events`: `id`, `occurred_at timestamptz`, `actor_user_id`, `actor_service_account_id`, `actor_roles jsonb` (los roles vigentes en ese momento), `scope_group_id`, `scope_brand_id`, `scope_restaurant_id`, `schema_name`, `table_name`, `record_id`, `action`, `old_values jsonb`, `new_values jsonb`, `changed_fields text[]`, `reason`, `origin`, `transaction_id bigint`.
  - Índices: `(schema_name, table_name, record_id, occurred_at desc)`, `(actor_user_id, occurred_at desc)`, `(occurred_at)`.
  - **Solo inserción:** `revoke update, delete, truncate` a todos los roles, incluidos `postgres` y `service_role` donde se pueda, más un trigger `before update or delete or truncate` que lanza un error **siempre**.
  - Preparada para partición mensual por `occurred_at`: se decide en P3 si se particiona desde el inicio.
- `audit.authentication_security_events`: inicios de sesión, fallas, MFA, desactivaciones. Se carga con hooks de Supabase Auth o con un trigger sobre `auth.audit_log_entries` (se decide en P5).
- `audit.log_change()`: trigger genérico `after insert or update or delete`, `security definer` con `search_path` fijo. Lee el motivo y el origen de `current_setting('app.reason', true)`.
  - **Quita campos sensibles** antes de guardar (lista de columnas prohibidas: `password`, `token`, `secret`, `key`, `encrypted_*`).
  - Un update que solo marca `deleted_at` se registra como `soft_delete`.
- Lectura: solo con `audit.view` (auditores, dirección), filtrada por alcance.

### M3 — Organización (`org`)

- `org.groups`, `org.brands` (`group_id`), `org.restaurants` (`group_id`, `brand_id`), `org.areas` (`group_id`, `restaurant_id`; por ejemplo cocina, salón, depósito).
- Todas con columnas de control, `comment on` en español, índices parciales `where deleted_at is null`, `unique (group_id, lower(name)) where deleted_at is null`, triggers de control y auditoría.
- **Consistencia de alcance:** un `check` o trigger valida que el `brand_id` de un restaurante pertenezca a su mismo `group_id`.

### M4 — Identidad (`core`)

- `core.user_profiles`: `id = auth.users.id`, nombre, teléfono opcional, `status` (enum `active`, `disabled`), `disabled_at`, `disabled_by`, `disabled_reason`.
- `core.permissions`: `code` único (`modulo.accion`), módulo, descripción en español. Catálogo cargado por migración, no por la app.
- `core.roles`: `code`, nombre, nivel (P1), `requires_mfa boolean`, `is_system boolean`.
- `core.role_permissions`: `(role_id, permission_id)`.
- `core.user_memberships`: usuario + grupo (a qué grupo pertenece la persona).
- `core.user_role_assignments`: usuario + rol + **alcance**. `scope_type` (enum `group`, `brand`, `restaurant`), con `group_id` obligatorio y `brand_id` / `restaurant_id` según el tipo, validado con `check`. Más `valid_from`, `valid_until` y `granted_by`.
- `core.service_accounts`: cuentas técnicas para agentes e integraciones, con permisos explícitos y sin login interactivo.

### M5 — La función que decide todo

- `core.has_permission(permission_code text, restaurant_id uuid default null) returns boolean`, `stable`, `security definer`, `search_path` fijo.
  - Devuelve `false` si el usuario no existe, está desactivado o no tiene sesión.
  - Devuelve `true` si alguna asignación vigente del usuario tiene un rol con ese permiso **y** el alcance cubre al restaurante: alcance de grupo cubre todo el grupo, alcance de marca cubre sus restaurantes, alcance de restaurante solo ese.
  - Con `restaurant_id` nulo, responde "¿tiene el permiso en algún lado?", para mostrar u ocultar menús.
  - Si el rol exige MFA y la sesión no es `aal2`, devuelve `false` (depende de P2).
- Variantes por alcance: `core.has_permission_in_brand(code, brand_id)` y `core.has_permission_in_group(code, group_id)`. Todas usan **la misma lógica interna**: no se duplica.
- Índices pensados para esta función (es la consulta más frecuente del sistema): `user_role_assignments (user_id) where deleted_at is null`, `role_permissions (permission_id, role_id)`.
- Objetivo de rendimiento: menos de 1 ms por llamada con el seed. Se mide con `explain analyze`.

### M6 — RLS en todas las tablas

- `enable row level security` en **cada** tabla de `core`, `org`, `audit` y `workflow`.
- Políticas por operación (`select`, `insert`, `update`), cada una con `core.has_permission(...)`. **Sin política de `delete`:** el borrado es lógico.
- GRANT explícitos solo a `authenticated` (nunca a `anon`), y solo lo necesario.
- Cada persona ve su propio perfil. Los perfiles de otros solo con `core.users.view` dentro del alcance.
- Una prueba pgTAP recorre el catálogo y **falla si aparece una tabla sin RLS** o sin políticas.

### M7 — Aprobaciones (`workflow`)

- Tipo `workflow.request_status`: `pending`, `approved`, `rejected`, `cancelled`.
- `workflow.approval_workflows`: qué tipo de cambio aprueba, qué permiso hace falta para aprobar, cuántas aprobaciones pide y `requires_different_approver boolean`.
- `workflow.approval_requests`: qué registro cambiaría, quién lo pidió, alcance, estado, `payload jsonb` con el cambio propuesto.
- `workflow.approval_decisions`: quién decidió, decisión, comentario y fecha. Solo inserción.
- `workflow.decide(request_id, decision, comment)`: función transaccional. Valida el permiso, **rechaza que el que pidió apruebe su propio pedido si la regla lo exige (lo valida la base, no la pantalla)**, registra la decisión, actualiza el estado y audita, todo en una sola transacción.
- Estados de versión (borrador, en revisión, aprobada, publicada, archivada): el tipo `core.version_status` se crea acá para que lo usen los módulos siguientes. La regla "una versión publicada es inmutable" se prueba con una tabla de prueba en pgTAP.

### M8 — Cuentas: invitación y desactivación

- `core.invite_user(email, role, scope...)`: solo con `core.users.invite`. Crea la invitación (Edge Function con `service_role` del lado del servidor; la clave nunca llega al navegador) y registra la asignación inicial.
- `core.disable_user(user_id, reason)`: solo con `core.users.disable`. Marca el perfil como `disabled`, **borra las sesiones y los refresh tokens del usuario en `auth.sessions` y `auth.refresh_tokens`** y audita. Desde ese momento `has_permission` devuelve `false` aunque el token siga sin vencer.
- Nada se borra: el usuario desactivado conserva toda su historia.

### M9 — Seed ficticio (`supabase/seed.sql`)

- Un grupo ficticio ("Grupo Demo"), 3 marcas y 4 restaurantes ficticios, áreas básicas.
- Un usuario de prueba por rol (P1), con correos `@ejemplo.test` y contraseñas de prueba solo locales.
- Nombres inventados: **ningún dato real** de Grupo LF.

## Interfaz mínima de la Fase 1

- `/ingresar`: correo y contraseña, y el paso de MFA cuando el rol lo exige.
- `/sin-acceso`: pantalla para quien entra sin permisos o está desactivado.
- Cliente de Supabase en `lib/supabase/` (servidor y navegador) con `@supabase/ssr`. Los tipos salen de `npm run db:types`.
- Todo con los componentes de `components/ui/`, revisado por `ui-reviewer`.

## Las 13 pruebas obligatorias

> **Importante:** el prompt maestro dice que son 13, pero la lista oficial está en el documento de Soy, que todavía no tenemos. Esta es una **propuesta derivada de las secciones 6 y 14**, para comparar contra la lista de Soy. No se da por buena hasta confirmarla (P4).

| #   | Prueba                                                                                                            | Herramienta        |
| --- | ----------------------------------------------------------------------------------------------------------------- | ------------------ |
| 1   | Cada usuario ve solo las filas de su alcance (grupo, marca, restaurante)                                          | pgTAP + Playwright |
| 2   | El cocinero no tiene `costing.view_costs` y no ve precios ni costos                                               | pgTAP + Playwright |
| 3   | Todo cambio deja en `audit_events` quién, cuándo, qué (antes/después) y por qué                                   | pgTAP + Playwright |
| 4   | Nadie puede modificar ni borrar `audit_events`, ni siquiera un administrador                                      | pgTAP              |
| 5   | Quien pidió un cambio no puede aprobarlo cuando la regla lo prohíbe                                               | pgTAP + Playwright |
| 6   | Un usuario desactivado pierde el acceso al instante, aunque tenga una sesión abierta                              | pgTAP + Playwright |
| 7   | Todas las tablas de todos los esquemas tienen RLS y políticas; una tabla sin política no devuelve nada            | pgTAP              |
| 8   | No existe el registro libre: solo se entra por invitación de un administrador autorizado                          | pgTAP + Playwright |
| 9   | Los roles que exigen MFA no operan sin el segundo factor                                                          | pgTAP + Playwright |
| 10  | Una versión publicada no se puede modificar; corregir crea una versión nueva                                      | pgTAP              |
| 11  | La auditoría nunca guarda contraseñas, tokens ni secretos                                                         | pgTAP              |
| 12  | El borrado es lógico: un `delete` físico de un usuario común se rechaza y la historia se conserva                 | pgTAP              |
| 13  | Una cuenta técnica (agente) solo puede lo que tiene asignado explícitamente, y nunca escribe en `audit` ni `core` | pgTAP              |

Cada prueba se corre con **un usuario de prueba por rol**, simulando la sesión en pgTAP (`set local role authenticated` + `request.jwt.claims`).

## Riesgos

| Riesgo                                                                                     | Qué hacemos                                                                                                            |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Construir roles y permisos que después no coinciden con el documento de Soy                | No se cargan roles ni permisos definitivos hasta tener el documento (P1). La estructura sí se puede construir antes.   |
| `has_permission` lenta, porque se ejecuta en cada fila de cada consulta                    | Función `stable`, índices dedicados, `explain analyze` con el seed y, si hace falta, caché por transacción.            |
| Funciones `security definer` mal hechas, que abren un agujero                              | `search_path` fijo, permisos revisados por `security-auditor` y pruebas de "no puede" para cada rol.                   |
| La tabla de auditoría crece rápido                                                         | Índices desde el día uno y partición mensual lista para activar (P3).                                                  |
| Desactivar un usuario no corta sesiones ya emitidas (los JWT siguen valiendo hasta vencer) | Doble barrera: se borran sesiones y refresh tokens, **y** `has_permission` mira el estado del perfil en cada consulta. |
| MFA en local                                                                               | Supabase local soporta TOTP. Se prueba con un secreto de prueba en el seed, nunca uno real.                            |
| RAM de Docker justa                                                                        | Servicios apagados en local (ADR-0001). Si no alcanza, ampliar la memoria de WSL.                                      |

## Preguntas abiertas

**Bloqueantes** (sin respuesta no se puede cerrar la Fase 1):

- **P1. Roles y niveles.** ¿Cuál es la lista oficial de roles y qué nivel (1 a 4) tiene cada uno? Del documento salen estos perfiles de usuario: dirección, director de marca, gerente, chef, jefe de cocina, controller, compras, cocinero, auditor y superadministrador. ¿Son roles, o algunos son el mismo rol con distinto alcance?
- **P2. MFA.** "Obligatorio para niveles 1 a 4 y para Controller": ¿qué roles quedan en esos niveles? ¿Los cocineros entran sin MFA?
- **P4. Las 13 pruebas.** ¿Coincide la lista propuesta arriba con la del documento de Soy?
- **P6. Matriz de permisos.** ¿Qué permisos (`modulo.accion`) tiene cada rol? Como mínimo, para identidad, organización y auditoría.
- **P7. Aprobaciones.** ¿Qué cambios de la Fase 1 necesitan aprobación (por ejemplo, dar un rol de nivel alto) y cuáles exigen que apruebe otra persona?

**No bloqueantes** (se pueden decidir durante la fase):

- **P3.** ¿Particionamos `audit_events` por mes desde el inicio o cuando crezca? Propuesta: dejarlo preparado y activarlo al pasar el millón de filas.
- **P5.** Eventos de autenticación: ¿alcanza con los logs de Supabase Auth o hay que copiarlos a `audit.authentication_security_events` en tiempo real?
- **P8.** Política de contraseñas: largo mínimo y complejidad. Propuesta: 12 caracteres como mínimo.
- **P9.** ¿Quién puede invitar usuarios y con qué alcance? ¿Un gerente puede invitar cocineros de su restaurante?
- **P10.** Lista completa de marcas y restaurantes reales, y si entran otros negocios del grupo (vinos, consultoría). No cambia el diseño, que ya soporta N marcas y N restaurantes, pero sí el seed de staging.
- **P11.** La tabla de fases (sección 12) no llegó completa: confirmar qué entra en cada fase y en qué compuerta.

## Definición de terminado de la Fase 1

Además de la definición de terminado general (`CLAUDE.md`):

- [ ] Las 13 pruebas obligatorias en verde, en local y en GitHub Actions.
- [ ] Prueba de catálogo: ninguna tabla sin RLS.
- [ ] `has_permission` medida con `explain analyze`.
- [ ] Revisión de `db-reviewer` y `security-auditor` sin hallazgos graves.
- [ ] Checklist de la sección 14 recorrida con Soy: los puntos de usuarios, cocinero sin costos, historial, autoaprobación y desactivación.
