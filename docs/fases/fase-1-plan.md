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
2. **Ninguna función queda abierta por defecto.** En M1: `revoke all on schema … from public` en los 12 esquemas, y `alter default privileges revoke execute on functions from public` **global**, para cada rol que crea funciones (`postgres` y `audit_owner`). La versión por esquema no sirve: solo puede sumar permisos, no quitar los globales (lo detectó una prueba). Cada función recibe `grant execute` explícito.
3. **Las cuentas técnicas nunca usan `service_role`.** `service_role` saltea RLS (BYPASSRLS). Los agentes entran como usuarios de Supabase Auth con un claim firmado en `app_metadata` (`actor_type = 'service_account'`, más el id de la cuenta), con rol `authenticated` y permisos solo sobre `ai`. `service_role` queda reservado a una sola Edge Function de servidor (invitaciones y bloqueo de cuentas) y nunca llega a un agente, a la app ni a Claude Code.
4. **La identidad sale del JWT, nunca de algo que el cliente pueda escribir.** `reason` y `origin` (motivo y origen, cargados con `set_config`) son **solo informativos**: se guardan en la auditoría y nunca se usan para decidir permisos.
5. **Alcance consistente por estructura.** `unique (id, group_id)` en `org.brands` y `org.restaurants`, y FKs compuestas `(restaurant_id, group_id) references org.restaurants (id, group_id)` en toda tabla con más de un nivel de alcance. Así una fila no puede decir que es de un restaurante de otro grupo.
6. **Borrado lógico sin GRANT de `delete`.** Ningún rol de la API recibe `delete`: un `DELETE` da "permission denied" en lugar de borrar 0 filas en silencio. El borrado lógico se hace con funciones transaccionales (`core.soft_delete(...)`), no con un update directo, para evitar el choque con la política `select ... where deleted_at is null`.
7. **Rendimiento de las políticas.** Cuando la llamada a `has_permission` no depende de la fila, se envuelve en `(select core.has_permission(...))` para que Postgres la evalúe una sola vez. Toda política se mide con `explain analyze`.

## Migraciones, en orden

Cada una es un archivo nuevo en `supabase/migrations/`, con su prueba pgTAP y con RLS incluido (regla 1).

### M1 — Base común y privilegios por defecto ✅ construida (adelanto, rama `feat/fase-1-base-auditoria`)

Archivo: `supabase/migrations/20261020173808_core_base.sql`. Pruebas: `supabase/tests/010_core_base.test.sql` (41).

- Rol `audit_owner` (`nologin`): dueño de todo el esquema `audit`. `postgres` puede ponerse el rol pero **no lo hereda** (ADR-0006).
- Privilegios por defecto cerrados (regla 2).
- `core.actors`: una fila por usuario de Auth (persona o cuenta técnica), cargada por un trigger sobre `auth.users`, que es el patrón estándar de Supabase. Las columnas `created_by`, `updated_by` y `deleted_by` apuntan acá.
  - `actor_type` es descriptivo: los permisos de una cuenta técnica salen de `core.service_accounts` (M4).
  - Un usuario con historia no se puede borrar de Auth (`on delete restrict`): se bloquea (M8).
- `core.current_actor_id()` y `core.current_actor_subject()`: salen **solo** de `request.jwt.claims` (el JWT completo), nunca del GUC heredado `request.jwt.claim.sub`. Un `sub` que no es uuid deja el actor nulo, sin romper.
- `core.set_control_columns()`: trigger que verifica que esté conectado como BEFORE por fila.
  - Completa las columnas de control e impide cambiar `id`, `created_at` y `created_by`.
  - Ignora los cambios que no cambian nada, y conserva quién y cuándo se borró algo ya borrado.
- `core.set_change_context(reason, origin)`: el origen se recibe como **texto** y se valida contra la lista, para no exigir acceso al esquema `audit`.

### M2 — Auditoría (`audit`) ✅ construida (adelanto)

Archivo: `supabase/migrations/20261020173811_audit_events.sql`. Pruebas: `supabase/tests/020_audit.test.sql` (55). Decisiones y límites: **ADR-0006**.

- `audit.audit_events` con todo lo previsto, más:
  - `sequence_number`: el orden exacto;
  - `jwt_role` y `db_user`: quién hizo el cambio aunque no haya persona;
  - un `check` de largo del motivo.
- Índices: por registro, por actor, por restaurante, por transacción y por fecha.
- **Solo inserción:**
  - ningún rol de la API tiene permisos;
  - triggers que rechazan `update`, `delete` y `truncate`;
  - `postgres` no hereda al dueño;
  - **sellos** (`audit.audit_seals`, `audit.seal_events()`, `audit.verify_seals()`) que detectan cualquier alteración de lo sellado.
- `audit.log_change()`:
  - verifica que esté conectado como AFTER por fila;
  - falla si una columna a ocultar no existe;
  - oculta secretos en cualquier nivel del jsonb (por nombre y por forma del valor);
  - recorta el motivo a 500 caracteres y descarta orígenes inválidos;
  - **rechaza los cambios con la clave de servidor que no declaran origen**.
- **Pendiente:**
  - `audit.authentication_security_events` (espera P5);
  - la tarea programada que sella cada hora;
  - la exportación externa con la última huella;
  - la lectura con `audit.view`, que tiene que **ocultar costos** a quien no tenga `costing.view_costs` (ADR-0006).
- **Pregunta abierta P13:** hoy se puede editar un registro que ya está borrado (queda auditado como `update`). ¿Debe rechazarse, o hay que restaurarlo primero?

### M3 — Organización (`org`) ✅ construida (adelanto, rama `feat/fase-1-organizacion`)

Archivo: `supabase/migrations/20261020181421_org_structure.sql`. Pruebas: `supabase/tests/030_org.test.sql` (51). Seed: 1 grupo, 3 marcas, 4 restaurantes y 12 áreas, todos ficticios. Acceso de la app: **ADR-0005**.

- `org.groups`, `org.brands`, `org.restaurants` y `org.areas`, con las 6 columnas de control y comentarios en español. Los estados `active` e `inactive` son una propuesta (**P14**).
- FKs compuestas de alcance (regla 5) y `unique (id, group_id)` en marcas, restaurantes y áreas.
- **Nombres únicos:**
  - grupo: entre todos los grupos;
  - marca: por grupo;
  - restaurante: **por marca** (decisión: dos marcas pueden tener un local con el mismo nombre);
  - área: por restaurante;
  - en todos los casos sin importar mayúsculas y entre los vigentes.
- **Decisiones de Joaco (2026-10-20), aplicadas con el trigger `validate_hierarchy`:**
  - No se borra algo que tiene elementos vigentes adentro, y no se da de alta ni se restaura algo bajo un padre borrado.
  - El alcance no se mueve con una edición común. Mover un restaurante de marca, o una marca de grupo, tendrá un **trámite** (una función con motivo y permiso propio, en M5) que se habilita con una migración nueva.
- `TRUNCATE` rechazado en las tablas de negocio (`core.reject_truncate()`).
- Auditoría: el alcance de cada evento sale de la estructura (`org.restaurants` / `org.brands`), no de lo que diga la fila. En las filas de `org`, sale de su propio id.
- Se cortaron los permisos por defecto de Supabase en `public` (DELETE y TRUNCATE para los roles de la API).
- **Excepción documentada a "índice en cada FK":** `created_by`, `updated_by` y `deleted_by` (hacia `core.actors`) no se indexan. Un actor nunca se borra, así que esas FKs no se recorren al borrar. Si una pantalla filtra "creado por", se agrega el índice.
- **Pendiente:** dirección, CUIT, código de marca y zona horaria (P10), y el trámite de traspaso (M5).

### M4 — Identidad (`core`) ✅ construida (adelanto, rama `feat/fase-1-identidad`)

- `core.user_profiles`: `id = auth.users.id`, nombre, apellido, correo, `status` (enum `core.account_status`: `active` o `disabled`), `disabled_at`, `disabled_reason`. Se crea sola al dar de alta una persona en Auth. **No se borra: se bloquea.**
  - Para M5: GRANT de `update` **por columna**. La persona solo edita su nombre, nunca `status` ni `disabled_*`, para que nadie se reactive solo.
  - Quedaron para M8: `disabled_by` (hoy lo cubre `updated_by` y la auditoría), `phone` y la sincronización del correo con Auth.
- `core.permissions`: los 14 permisos de la Fase 1. El código no se puede cambiar: renombrar `org.view` a `roles.manage` le daría `roles.manage` a todos los roles. Tampoco se borra un permiso que algún rol tiene.
- `core.roles`: los 10 roles del Módulo Maestro, con nivel 1 a 10 y `requires_mfa` en los niveles 1 a 4 más Controller. El código no se puede cambiar, y a un rol del catálogo no se le puede sacar el MFA.
- `core.role_permissions`: la matriz aprobada, 55 relaciones (`docs/modulos/00-identidad.md`). Solo con roles y permisos vigentes.
- `core.user_memberships`: persona + grupo.
- `core.user_role_assignments`: persona + rol + alcance. `scope_type` (enum `group`, `brand` o `restaurant`), `group_id` obligatorio y `brand_id` / `restaurant_id` según el tipo, validado con `check` y con 3 FKs compuestas. Incluye `valid_from` y `valid_until`; quién la dio es `created_by`.
  - No se repite la misma asignación vigente (`unique ... nulls not distinct`).
  - Persona, rol y alcance no cambian. `valid_from` no cambia y `valid_until` solo se acorta.
  - Para tener un rol (también al restaurarlo) hace falta ser miembro del grupo, que el rol esté vigente y que la cuenta esté activa. Esos registros se bloquean con `for share`, así que no se cruzan con un borrado simultáneo.
- `core.service_accounts`: cuentas técnicas, cada una con su actor de tipo `service_account` y una persona responsable activa. Sin roles hasta la Fase 5, porque `user_role_assignments.user_id` apunta a perfiles de persona, y eso se decide en la Fase 5.
- Seed: 11 personas (una por rol y un gerente de dos locales) y una cuenta técnica. Contraseña local `Demo-Local-2026!`. El ingreso local está probado contra Auth.
  - La guarda del seed aborta si la base tiene SSL (Supabase alojado siempre lo usa) o si ya hay grupos o usuarios.
- `config.toml`: en la CLI, `[auth.email] enable_signup = false` apagaba **todo** el ingreso con correo. Ahora el alta libre se cierra solo con `[auth] enable_signup = false`. Está probado que el alta libre devuelve `signup_disabled`.

### M5 — Las funciones que deciden

- `core.has_permission(permission_code, restaurant_id) returns boolean`: `stable`, `security definer`, `search_path` fijo.
  - **`restaurant_id` es obligatorio. Si viene nulo, devuelve `false`.** Así una política no puede abrir por error una tabla entera.
  - Devuelve `false` si no hay sesión, si el actor está desactivado o si el rol exige MFA y la sesión no es `aal2` (P2).
  - Devuelve `true` si alguna asignación vigente tiene un rol con ese permiso y el alcance cubre al restaurante: alcance de grupo, todo el grupo; alcance de marca, sus restaurantes; alcance de restaurante, solo ese.
- `core.has_permission_in_brand(code, brand_id)` y `core.has_permission_in_group(code, group_id)`: para tablas de nivel marca o grupo, con la misma lógica interna.
- `core.has_permission_anywhere(code)`: "¿tiene este permiso en algún lado?". **Solo para mostrar u ocultar menús. Prohibida en políticas RLS**: una prueba pgTAP recorre `pg_policies` y falla si alguna la usa.
- Índices pensados para estas funciones: `user_role_assignments_key` (empieza por `user_id`, solo vigentes) y `role_permissions (permission_id, role_id)`. Objetivo: menos de 1 ms por llamada con el seed.
- Requisitos que salen de la revisión de M4. Cada uno lleva su prueba de "no puede":
  - `has_permission` filtra roles, permisos, relaciones, membresías y asignaciones borrados, la vigencia (`valid_from` ≤ ahora < `valid_until`) y el perfil activo.
  - **Deniega a todo actor que no tenga un perfil activo o una cuenta técnica activa.** Hoy se puede crear un actor `service_account` sin su fila en `service_accounts`.
  - `core.permissions`, `core.roles` y `core.role_permissions` no tienen escritura para ningún rol de la API. El catálogo se cambia por migración o por funciones que pasan por `workflow`.
  - `core.service_accounts`: nadie más que `postgres` la escribe hasta la Fase 5.
- **Traspaso de locales y marcas (P15, resuelta: opción A, ADR-0007):** el trámite de traspaso, en una sola transacción y auditado:
  - cierra el local viejo;
  - crea uno nuevo en la marca destino, con una referencia al anterior;
  - reasigna los roles con las reglas de M6.

  Las FKs compuestas no se aflojan.

### M6 — Asignación de roles sin escalada de privilegios

- `core.assign_role(user_id, role_id, scope...)`: es **la única vía** para crear asignaciones. Ningún rol de la API tiene `insert` directo sobre `user_role_assignments`. La base valida que:
  1. quien asigna tenga `roles.assign` en ese alcance;
  2. **los permisos del rol que otorga sean un subconjunto de los suyos** en ese alcance. Se comparan **conjuntos de permisos, nunca `level`**: si se comparara el nivel, el gerente (nivel 4) podría dar Chef Ejecutivo (nivel 5), que tiene `approvals.decide`;
  3. **el alcance otorgado quede dentro del suyo**;
  4. **nadie se asigne roles a sí mismo**, ni siquiera en otro alcance;
  5. los roles que incluyen `approvals.decide` o algún permiso `is_sensitive` pasan por `workflow`, con aprobación de otra persona. Así se evitan las "cuentas títere": invitar un segundo correo propio y darle el mismo rol para aprobarse a uno mismo.
- Extender una vigencia o restaurar una asignación también pasa por `assign_role`.
- Cambios del catálogo con `roles.manage`:
  - van por `workflow`, con aprobador distinto;
  - nadie modifica un rol que tiene él mismo. Si no, el superadmin podría darse `approvals.decide`.
- Hay que tomar `for share`/`for update` sobre la membresía y el perfil, como ya hace el trigger de M4.
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
  1. Una Edge Function de servidor (con `edge_runtime` prendido) valida con RPC que quien invita tenga `users.invite` en ese alcance. También valida el nombre (hasta 80 caracteres): uno más largo hace fallar el alta entera en Auth. Los nombres pueden traer HTML, así que la interfaz nunca los muestra como HTML crudo.
  2. La Edge Function invita con la Admin API de Auth, usando `service_role` solo de su lado.
  3. Después llama a `core.register_invitation(...)` y a `core.assign_role(...)`, que audita todo y aplica las reglas de M6.
- **MFA:** el factor se registra **solo en el primer ingreso por invitación**. Para resetear un factor hace falta un administrador, y queda auditado. Así, quien tiene solo la contraseña no puede registrar su propio TOTP. Hay que prender `[auth.mfa.totp]` en `supabase/config.toml`.
- `register_invitation` fija el contexto (origen y motivo). Hoy las altas que vienen de Auth quedan auditadas sin ninguno de los dos.
- **Correo:** un trigger `after update of email on auth.users` sincroniza el perfil y lo audita. Si no, el perfil queda con el correo viejo y ese correo bloquea futuras invitaciones. La otra salida es no dejar que el usuario cambie su propio correo en Auth.
- **Sobre otra persona** (`users.manage` y `users.deactivate`):
  - todas sus asignaciones vigentes tienen que estar dentro del alcance de quien actúa, y con permisos que sean un subconjunto de los suyos;
  - nunca sobre uno mismo, y nunca sobre el último superadmin activo.
- **Bloqueo** con `core.disable_user(user_id, reason)`, solo con `users.deactivate`:
  1. marca el perfil como `disabled`;
  2. borra sesiones y refresh tokens;
  3. **banea al usuario en Auth** (`ban_duration`, vía la Edge Function), para que no pueda volver a entrar con su contraseña;
  4. audita.
  - Además, toda política pasa por `has_permission` o chequea el estado, así que el acceso se corta en la consulta siguiente aunque el JWT siga vigente.
- Nada se borra: el usuario desactivado conserva toda su historia.
- Política de contraseñas en `config.toml` y en el panel de staging y producción (P8). Hoy local tiene TOTP apagado, mínimo de 6 caracteres y `secure_password_change = false`.
- En los paneles de staging y producción hay que confirmar a mano tres cosas (`config.toml` no se aplica al remoto):
  - alta libre apagada;
  - ingreso anónimo apagado;
  - cambio de correo controlado.
- La cuenta técnica del seed no tiene contraseña, pero podría entrar por enlace mágico. Para la Fase 5: correos que no reciban mensajes, o bloquear ese ingreso.
- CI: un paso que falle si algún workflow usa `--include-seed` contra un remoto. Después de cada despliegue, verificar que no haya `%@ejemplo.test` en `auth.users`.

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

La lista oficial está en la sección 10 del Módulo Maestro (copiada en `docs/modulos/00-identidad.md`). P4 quedó resuelta. Faltan las **10 adicionales** (P16).

| #   | Prueba obligatoria (Módulo Maestro)                       | Dónde                       | Se construye en                                                       |
| --- | --------------------------------------------------------- | --------------------------- | --------------------------------------------------------------------- |
| 1   | Sin sesión no se consulta información privada             | pgTAP + Playwright          | M5 (RLS y API) + pantalla `/ingresar`                                 |
| 2   | Cocinero abre la receta vigente pero no ve costos         | pgTAP (con tabla de prueba) | M7 (tabla de prueba con versión y vista sin costos)                   |
| 3   | Jefe de cocina crea borrador pero no publica sin permiso  | pgTAP                       | M7 (tabla de prueba con versiones)                                    |
| 4   | Gerente no edita fuera de su restaurante                  | pgTAP                       | M5                                                                    |
| 5   | Dirección ve lo consolidado según permisos                | pgTAP                       | M5                                                                    |
| 6   | Un cambio registra usuario, fecha, campo y valores        | pgTAP                       | M2 (ya cubierta en `020_audit`; se repite con usuario real en M5)     |
| 7   | Una versión aprobada conserva su historia                 | pgTAP                       | M7                                                                    |
| 8   | Una cuenta desactivada pierde acceso                      | pgTAP + Playwright          | M8                                                                    |
| 9   | Usuario con dos restaurantes opera solo en los suyos      | pgTAP                       | M5 (persona del seed `...0411`)                                       |
| 10  | Una cuenta técnica no supera sus permisos                 | pgTAP                       | M5 y M6                                                               |
| 11  | Una operación rechazada queda registrada                  | pgTAP                       | M7 o M9, según P17                                                    |
| 12  | Una aprobación guarda identidad, fecha y decisión         | pgTAP                       | M7                                                                    |
| 13  | No se puede alterar el historial con operaciones normales | pgTAP                       | M2 (ya cubierta en `020_audit`; se repite como `authenticated` en M5) |

Cada prueba se corre con **un usuario de prueba por rol**, simulando la sesión en pgTAP (`set local role authenticated` + `request.jwt.claims`). Las pruebas que había propuesto antes (RLS en todas las tablas, invitación, MFA, secretos en la auditoría, borrado lógico) no se pierden: quedan como pruebas propias de M5 a M8.

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

- ~~**P1. Roles y niveles.**~~ Resuelta: los 10 roles del Módulo Maestro, con nivel según el orden de la tabla.
- ~~**P2. MFA.**~~ Resuelta: niveles 1 a 4 más Controller.
- ~~**P4. Las 13 pruebas.**~~ Resuelta: lista oficial de la sección 10 del Módulo Maestro.
- ~~**P6. Matriz de permisos.**~~ Resuelta: matriz aprobada por Joaco (`docs/modulos/00-identidad.md`).
- **P7. Aprobaciones.** ¿Qué cambios de la Fase 1 necesitan aprobación y cuáles exigen que apruebe otra persona? La propuesta de seguridad es que pasen por aprobación tres cosas: dar roles con `approvals.decide` o con permisos sensibles, los cambios de la matriz y los traspasos.
- ~~**P15. Traspaso de locales y marcas.**~~ Resuelta por Joaco el 2026-10-20: opción A. Se crea un local nuevo en la marca nueva y se cierra el viejo, que conserva su historia (ADR-0007). Si hace falta, se puede pasar a B más adelante.
- **P16. Las 10 pruebas adicionales** del Módulo Maestro: no llegaron.
- **P17. "Una operación rechazada queda registrada" (prueba 11):** ¿se refiere a una solicitud de aprobación rechazada, o también a un intento sin permiso que la base frena (por ejemplo, un cocinero que quiere editar un costo)? En el segundo caso hace falta un registro aparte, porque lo que la base rechaza se deshace entero, y su auditoría también.

**No bloqueantes:**

- **P3.** ¿Particionamos `audit_events` por mes desde el inicio? Propuesta: dejarlo preparado y activarlo al pasar el millón de filas.
- **P5.** Eventos de autenticación: ¿hooks de Auth en tiempo real o una copia periódica?
- **P8.** Política de contraseñas. Propuesta: 12 caracteres como mínimo, con letras y números.
- **P9.** ¿Quién puede invitar y con qué alcance? ¿Un gerente invita cocineros de su restaurante?
- **P10.** Lista completa de marcas y restaurantes reales, y si entran otros negocios del grupo (vinos, consultoría).
- **P11.** La tabla de fases (sección 12) no llegó completa: confirmar qué entra en cada fase.
- ~~**P12.** Cómo llega la app a los datos: opción A o B.~~ Resuelta: opción A (ADR-0005), que se aplica en M5/M6.
- **P13.** ¿Se puede editar un registro que ya está borrado, o hay que restaurarlo primero? Hoy se permite y queda auditado como `update`.
- **P14.** Estados de grupo, marca y restaurante: ¿alcanzan `active` (operando) e `inactive` (cerrado, visible en la historia)? ¿Hace falta otro, por ejemplo "en apertura"?

## Definición de terminado de la Fase 1

Además de la definición de terminado general (`CLAUDE.md`):

- [ ] Las 13 pruebas obligatorias en verde, en local y en GitHub Actions.
- [ ] Prueba de catálogo (M7) en verde.
- [ ] `has_permission` medida con `explain analyze`.
- [ ] Revisión de `db-reviewer` y `security-auditor` sin hallazgos graves.
- [ ] Checklist de la sección 14 recorrida con Soy: los puntos de usuarios, cocinero sin costos, historial, autoaprobación y desactivación.
