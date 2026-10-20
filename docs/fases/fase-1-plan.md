# Plan de la Fase 1 — Fundaciones: identidad, permisos y auditoría

- **Fecha:** 2026-10-20 (revisado el mismo día con `db-reviewer` y `security-auditor`)
- **Estado:** borrador para revisar con Joaco y Soy. **No se empieza a construir** hasta responder las preguntas abiertas marcadas como **bloqueantes**.
- **Fuentes:** prompt maestro (secciones 5, 6, 9 y 14). El Módulo Maestro de Usuarios de Soy (`docs/modulos/00-identidad.md`) **todavía no está en el repositorio**: donde este plan depende de él, se marca como pregunta abierta en lugar de suponer.

## Objetivo, en simple

Que el sistema sepa **quién es cada persona, qué puede hacer y dónde**, y que **todo cambio quede registrado para siempre**: quién, cuándo, qué y por qué. Sin esto no se habilita ningún otro módulo.

## Alcance

Esquemas `core`, `org`, `audit` y `workflow`, la función `core.has_permission`, el trigger de auditoría, el seed ficticio y las 13 pruebas obligatorias. **Sin pantallas de negocio**: solo login, la pantalla de "sin acceso" y lo mínimo que piden las pruebas de Playwright.

## Reglas de diseño que salen de la revisión

Estas reglas valen para todas las migraciones de la fase. Salen de los hallazgos de los revisores.

1. **RLS en la misma migración que crea la tabla.** `enable row level security`, las políticas y los GRANT van junto con el `create table`. Nunca existe, ni por un momento, una tabla sin RLS. La prueba de catálogo (M7) lo controla.
2. **Ninguna función queda abierta por defecto.** En M1, para cada esquema: `revoke all on schema … from public` y `alter default privileges in schema … revoke execute on functions from public`. Cada función recibe `grant execute` explícito.
3. **Las cuentas técnicas nunca usan `service_role`.** `service_role` saltea RLS (BYPASSRLS). Los agentes entran como usuarios de Supabase Auth con un claim firmado en `app_metadata` (`actor_type = 'service_account'`, más el id de la cuenta), con rol `authenticated` y permisos solo sobre `ai`. `service_role` queda reservado a una sola Edge Function de servidor (invitaciones y bloqueo de cuentas) y nunca llega a un agente, a la app ni a Claude Code.
4. **La identidad sale del JWT, nunca de algo que el cliente pueda escribir.** `reason` y `origin` (motivo y origen, cargados con `set_config`) son **solo informativos**: se guardan en la auditoría y nunca se usan para decidir permisos.
5. **Alcance consistente por estructura.** `unique (id, group_id)` en `org.brands` y `org.restaurants`, y FKs compuestas `(restaurant_id, group_id) references org.restaurants (id, group_id)` en toda tabla con más de un nivel de alcance. Así una fila no puede decir que es de un restaurante de otro grupo.
6. **Borrado lógico sin GRANT de `delete`.** Ningún rol de la API recibe `delete`: un `DELETE` da "permission denied" en lugar de borrar 0 filas en silencio. El borrado lógico se hace con funciones transaccionales (`core.soft_delete(...)`), no con un update directo, para evitar el choque con la política `select ... where deleted_at is null`.
7. **Rendimiento de las políticas.** Cuando la llamada a `has_permission` no depende de la fila, se envuelve en `(select core.has_permission(...))` para que Postgres la evalúe una sola vez. Toda política se mide con `explain analyze`.

## Migraciones, en orden

Cada una es un archivo nuevo en `supabase/migrations/`, con su prueba pgTAP y con RLS incluido (regla 1).

### M1 — Base común y privilegios por defecto

- Rol `audit_owner` (`nologin`): dueño de todo el esquema `audit` y de `audit.log_change()`.
- Revocación de privilegios por defecto en los 12 esquemas (regla 2).
- `core.actors`: tabla común de "quién hizo algo". Tiene una fila por persona (`auth.users`) y una por cuenta técnica. Las columnas `created_by`, `updated_by` y `deleted_by` apuntan acá. Así una acción de un agente no rompe la FK, y se sabe siempre qué tipo de actor fue.
- `core.current_actor_id()`: sale **solo** de `auth.uid()` y del claim firmado `app_metadata` del JWT (regla 4).
- `core.set_control_columns()`: trigger `before insert or update` que completa las columnas de control con `now()` y `core.current_actor_id()`, impide cambiar `id`, `created_at` y `created_by`, y completa `deleted_by` cuando se marca `deleted_at`.
- `core.set_change_context(reason, origin)`: `set_config(..., true)`, que vale solo para la transacción (regla 4).

### M2 — Auditoría (`audit`)

- Tipo `audit.action` (enum): `insert`, `update`, `soft_delete`, `restore`, `delete`.
- `audit.audit_events`: `id`, `occurred_at`, `actor_id` (FK a `core.actors`), `actor_type`, `actor_roles jsonb` (roles vigentes en ese momento), `scope_group_id`, `scope_brand_id`, `scope_restaurant_id`, `schema_name`, `table_name`, `record_id`, `action`, `old_values jsonb`, `new_values jsonb`, `changed_fields text[]`, `reason`, `origin`, `transaction_id`.
  - Índices: `(schema_name, table_name, record_id, occurred_at desc)`, `(actor_id, occurred_at desc)`, `(occurred_at)`.
- **Solo inserción, de verdad:**
  - Ningún rol de la API recibe `insert`, `update`, `delete` ni `truncate`. **Solo `audit.log_change()` inserta** (`security definer`, con `audit_owner` como dueño). Así nadie puede inventar eventos.
  - Dos triggers que lanzan un error siempre: uno `before update or delete for each row` y otro `before truncate for each statement`. No se pueden combinar en uno solo.
  - **Límite que queda, y está documentado:** un superusuario de Postgres (el dueño del proyecto en Supabase) puede desactivar triggers. Contra eso, la evidencia es la **exportación semanal** del esquema `audit` a un almacenamiento separado (sección 10).
- `audit.log_change()`: trigger genérico `after insert or update or delete`, `search_path` fijo.
  - **Filtro de secretos:** primero, un patrón de nombre de columna (`%password%`, `%token%`, `%secret%`, `%api_key%`); después, una lista de columnas a excluir que cada tabla pasa como argumento del trigger. La prueba 11 usa una tabla con una columna sensible.
  - Un update que solo marca `deleted_at` se registra como `soft_delete`.
- `audit.authentication_security_events`: inicios de sesión, fallas, MFA y bloqueos. Se carga desde hooks de Supabase Auth o con una copia periódica, **nunca con triggers sobre `auth.*`**, que Supabase desaconseja (P5).
- Lectura: solo con `audit.view`, filtrada por alcance.

### M3 — Organización (`org`)

- `org.groups`, `org.brands` (`group_id`), `org.restaurants` (`group_id`, `brand_id`) y `org.areas` (`group_id`, `restaurant_id`; por ejemplo cocina, salón o depósito).
- Columnas de control, `comment on` en español, índices parciales `where deleted_at is null`, `unique (group_id, lower(name)) where deleted_at is null` y los triggers de control y auditoría.
- FKs compuestas de alcance (regla 5): el `brand_id` de un restaurante pertenece al mismo `group_id`.

### M4 — Identidad (`core`)

- `core.user_profiles`: `id = auth.users.id`, nombre, teléfono opcional, `status` (enum `active` o `disabled`), `disabled_at`, `disabled_by`, `disabled_reason`.
  - GRANT de `update` **por columna**: la persona solo edita su nombre y su teléfono. Nunca `status` ni `disabled_*`, para que nadie se reactive solo.
- `core.permissions`: `code` único (`modulo.accion`), módulo y descripción. Catálogo cargado por migración.
- `core.roles`: `code`, nombre, nivel (P1), `requires_mfa`, `is_system`.
- `core.role_permissions`: `(role_id, permission_id)`.
- `core.user_memberships`: persona + grupo.
- `core.user_role_assignments`: persona + rol + alcance. `scope_type` (enum `group`, `brand` o `restaurant`), `group_id` obligatorio y `brand_id` / `restaurant_id` según el tipo, validado con `check` y con FKs compuestas. Incluye `valid_from`, `valid_until` y `granted_by`.
- `core.service_accounts`: cuentas técnicas (regla 3), cada una vinculada a su fila de `core.actors` y a su usuario técnico de Auth.

### M5 — Las funciones que deciden

- `core.has_permission(permission_code, restaurant_id) returns boolean`: `stable`, `security definer`, `search_path` fijo.
  - **`restaurant_id` es obligatorio. Si viene nulo, devuelve `false`.** Así una política no puede abrir por error una tabla entera.
  - Devuelve `false` si no hay sesión, si el actor está desactivado o si el rol exige MFA y la sesión no es `aal2` (P2).
  - Devuelve `true` si alguna asignación vigente tiene un rol con ese permiso y el alcance cubre al restaurante: alcance de grupo, todo el grupo; alcance de marca, sus restaurantes; alcance de restaurante, solo ese.
- `core.has_permission_in_brand(code, brand_id)` y `core.has_permission_in_group(code, group_id)`: para tablas de nivel marca o grupo, con la misma lógica interna.
- `core.has_permission_anywhere(code)`: "¿tiene este permiso en algún lado?". **Solo para mostrar u ocultar menús. Prohibida en políticas RLS**: una prueba pgTAP recorre `pg_policies` y falla si alguna la usa.
- Índices pensados para estas funciones: `user_role_assignments (user_id) where deleted_at is null` y `role_permissions (permission_id, role_id)`. Objetivo: menos de 1 ms por llamada con el seed.

### M6 — Asignación de roles sin escalada de privilegios

- `core.assign_role(user_id, role_id, scope...)`: es **la única vía** para crear asignaciones. Ningún rol de la API tiene `insert` directo sobre `user_role_assignments`. La base valida que:
  1. quien asigna tenga `core.roles.assign` en ese alcance;
  2. **los permisos del rol que otorga sean un subconjunto de los suyos** en ese alcance;
  3. **el alcance otorgado quede dentro del suyo**;
  4. **nadie se asigne roles a sí mismo**;
  5. los roles de nivel alto (P1) pasen por `workflow` con aprobador distinto.
- Una prueba pgTAP de "no puede" por cada regla.

### M7 — Aprobaciones (`workflow`) y prueba de catálogo

- Tipo `workflow.request_status`: `pending`, `approved`, `rejected`, `cancelled`.
- `workflow.approval_workflows`: qué tipo de cambio aprueba, qué permiso hace falta, cuántas aprobaciones pide y `requires_different_approver`.
- `workflow.approval_requests`: registro afectado, quién pidió, alcance, estado y `payload jsonb`. **El `payload` y el registro afectado son inmutables** una vez creado el pedido: lo que se aprueba es exactamente lo que se aplica.
- `workflow.approval_decisions`: solo inserción, con `unique (request_id, decided_by)`.
- `workflow.decide(request_id, decision, comment)`: función transaccional que:
  - hace `select ... for update` sobre el pedido;
  - valida que esté `pending`;
  - valida el permiso;
  - **rechaza la autoaprobación cuando la regla lo exige (lo valida la base, no la pantalla)**;
  - registra la decisión, actualiza el estado y audita, todo en una sola transacción.
- Tipo `core.version_status` (borrador, en revisión, aprobada, publicada, archivada), para los módulos siguientes. La regla "versión publicada inmutable" se prueba con una tabla de prueba.
- **Prueba de catálogo:** ninguna tabla de ningún esquema sin RLS o sin políticas, ninguna función con `execute` para `public` y ninguna política que use `has_permission_anywhere`.

### M8 — Cuentas: invitación, MFA y bloqueo

- **Invitación** (el flujo va del servidor a la base, no al revés):
  1. Una Edge Function de servidor (con `edge_runtime` prendido) valida con RPC que quien invita tenga `core.users.invite` en ese alcance.
  2. La Edge Function invita con la Admin API de Auth, usando `service_role` solo de su lado.
  3. Después llama a `core.register_invitation(...)` y a `core.assign_role(...)`, que audita todo y aplica las reglas de M6.
- **MFA:** el factor se registra **solo en el primer ingreso por invitación**. Para resetear un factor hace falta un administrador, y queda auditado. Así, quien tiene solo la contraseña no puede registrar su propio TOTP. Hay que prender `[auth.mfa.totp]` en `supabase/config.toml`.
- **Bloqueo** con `core.disable_user(user_id, reason)`, solo con `core.users.disable`:
  1. marca el perfil como `disabled`;
  2. borra sesiones y refresh tokens;
  3. **banea al usuario en Auth** (`ban_duration`, vía la Edge Function), para que no pueda volver a entrar con su contraseña;
  4. audita.
  - Además, toda política pasa por `has_permission` o chequea el estado, así que el acceso se corta en la consulta siguiente aunque el JWT siga vigente.
- Nada se borra: el usuario desactivado conserva toda su historia.
- Política de contraseñas en `config.toml` y en el panel de staging y producción (P8).

### M9 — Seed ficticio (`supabase/seed.sql`)

- "Grupo Demo", con 3 marcas y 4 restaurantes ficticios y sus áreas básicas.
- Un usuario de prueba por rol (P1), con correos `@ejemplo.test`, contraseñas de prueba solo locales y una cuenta técnica de prueba.
- **Ningún dato real** de Grupo LF.

## Cómo llega la app a los datos (decisión pendiente → ADR-0005)

Hoy la API expone solo `public` y `graphql_public` (`supabase/config.toml`). Hay dos opciones:

- **A (propuesta):** exponer `core`, `org` y `workflow` en la API, con GRANT mínimos y RLS. `audit` nunca se expone para escritura: se lee por vistas o RPC.
- **B:** no exponer los esquemas de negocio y que la app use solo funciones RPC en `public`.

Se decide antes de M3, se registra en `docs/decisiones/0005-...` y se agregan los `grant usage on schema` que correspondan.

## Interfaz mínima de la Fase 1

- `/ingresar`: correo y contraseña, más el paso de MFA cuando el rol lo exige.
- `/sin-acceso`: pantalla para quien entra sin permisos o está desactivado.
- Cliente de Supabase en `lib/supabase/` (servidor y navegador) con `@supabase/ssr`. Los tipos salen de `npm run db:types`.
- Componentes de `components/ui/`, revisados por `ui-reviewer`.

## Las 13 pruebas obligatorias

> **Importante:** el prompt maestro dice que son 13, pero la lista oficial está en el documento de Soy, que todavía no tenemos. Esta es una **propuesta derivada de las secciones 6 y 14**, para comparar contra la lista de Soy. No se da por buena hasta confirmarla (P4).

| #   | Prueba                                                                                                                             | Herramienta        |
| --- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| 1   | Cada usuario ve solo las filas de su alcance (grupo, marca, restaurante), incluido el caso de `restaurant_id` nulo                 | pgTAP + Playwright |
| 2   | El cocinero no tiene `costing.view_costs` y no ve precios ni costos                                                                | pgTAP + Playwright |
| 3   | Todo cambio deja en `audit_events` quién, cuándo, qué (antes y después) y por qué                                                  | pgTAP + Playwright |
| 4   | Nadie puede modificar, borrar, truncar ni insertar a mano en `audit_events`, ni siquiera un administrador                          | pgTAP              |
| 5   | Quien pidió un cambio no puede aprobarlo cuando la regla lo prohíbe, y una decisión no se puede duplicar                           | pgTAP + Playwright |
| 6   | Un usuario desactivado pierde el acceso al instante y no puede volver a entrar                                                     | pgTAP + Playwright |
| 7   | Todas las tablas tienen RLS y políticas, ninguna función queda abierta a `public` y ninguna política usa `has_permission_anywhere` | pgTAP              |
| 8   | Solo se entra por invitación, y nadie se asigna roles a sí mismo ni otorga más de lo que tiene                                     | pgTAP + Playwright |
| 9   | Los roles que exigen MFA no operan sin el segundo factor, y el factor no se registra con la contraseña sola                        | pgTAP + Playwright |
| 10  | Una versión publicada no se puede modificar; corregir crea una versión nueva                                                       | pgTAP              |
| 11  | La auditoría nunca guarda contraseñas, tokens ni secretos                                                                          | pgTAP              |
| 12  | El borrado es lógico: un `DELETE` de un usuario común da "permission denied" y la historia se conserva                             | pgTAP              |
| 13  | Una cuenta técnica (agente) solo puede lo asignado explícitamente, no saltea RLS y nunca escribe en `audit` ni `core`              | pgTAP              |

Cada prueba se corre con **un usuario de prueba por rol**, simulando la sesión en pgTAP (`set local role authenticated` + `request.jwt.claims`).

## Riesgos

| Riesgo                                                                 | Qué hacemos                                                                                              |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Roles y permisos que después no coincidan con el documento de Soy      | No se cargan roles ni permisos definitivos hasta tener el documento (P1). La estructura sí se construye. |
| `has_permission` lenta (se ejecuta en cada consulta)                   | `stable`, índices dedicados, `(select ...)` donde se pueda, `explain analyze` con el seed.               |
| Funciones `security definer` que abren un agujero                      | `search_path` fijo, `execute` explícito, pruebas de "no puede" por rol, revisión de `security-auditor`.  |
| Escalada de privilegios por asignación de roles                        | `core.assign_role` como única vía, con las 5 validaciones de M6.                                         |
| Un superusuario de Postgres puede desactivar los triggers de auditoría | Límite documentado. Evidencia externa: exportación semanal de `audit`.                                   |
| La tabla de auditoría crece rápido                                     | Índices desde el día uno y partición mensual lista para activar (P3).                                    |
| MFA en local                                                           | TOTP de Supabase local con un secreto de prueba en el seed, nunca uno real.                              |
| RAM de Docker justa                                                    | Servicios apagados en local (ADR-0001). Si falta, apagar realtime y storage.                             |

## Preguntas abiertas

**Bloqueantes** (sin respuesta no se puede cerrar la Fase 1):

- **P1. Roles y niveles.** ¿Cuál es la lista oficial de roles y qué nivel (1 a 4) tiene cada uno? Del documento salen estos perfiles: dirección, director de marca, gerente, chef, jefe de cocina, controller, compras, cocinero, auditor y superadministrador. ¿Son roles distintos, o algunos son el mismo rol con otro alcance? ¿Qué roles son "de nivel alto" y necesitan aprobación para asignarse?
- **P2. MFA.** "Obligatorio para niveles 1 a 4 y para Controller": ¿qué roles quedan en esos niveles? ¿Los cocineros entran sin MFA?
- **P4. Las 13 pruebas.** ¿Coincide la lista propuesta con la del documento de Soy?
- **P6. Matriz de permisos.** ¿Qué permisos (`modulo.accion`) tiene cada rol? Como mínimo, para identidad, organización y auditoría.
- **P7. Aprobaciones.** ¿Qué cambios de la Fase 1 necesitan aprobación y cuáles exigen que apruebe otra persona?

**No bloqueantes:**

- **P3.** ¿Particionamos `audit_events` por mes desde el inicio? Propuesta: dejarlo preparado y activarlo al pasar el millón de filas.
- **P5.** Eventos de autenticación: ¿hooks de Auth en tiempo real o una copia periódica?
- **P8.** Política de contraseñas. Propuesta: 12 caracteres como mínimo, con letras y números.
- **P9.** ¿Quién puede invitar y con qué alcance? ¿Un gerente invita cocineros de su restaurante?
- **P10.** Lista completa de marcas y restaurantes reales, y si entran otros negocios del grupo (vinos, consultoría).
- **P11.** La tabla de fases (sección 12) no llegó completa: confirmar qué entra en cada fase.
- **P12.** Cómo llega la app a los datos: opción A o B (ADR-0005).

## Definición de terminado de la Fase 1

Además de la definición de terminado general (`CLAUDE.md`):

- [ ] Las 13 pruebas obligatorias en verde, en local y en GitHub Actions.
- [ ] Prueba de catálogo (M7) en verde.
- [ ] `has_permission` medida con `explain analyze`.
- [ ] Revisión de `db-reviewer` y `security-auditor` sin hallazgos graves.
- [ ] Checklist de la sección 14 recorrida con Soy: los puntos de usuarios, cocinero sin costos, historial, autoaprobación y desactivación.
