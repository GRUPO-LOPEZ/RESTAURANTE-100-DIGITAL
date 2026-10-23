# Prompt Fase 1 — Fundaciones: identidad, permisos y auditoría (Grupo LF)

19 oct 2026 · Soy (Luciano Lopez Fuente)

> Documento de Soy, guardado tal cual lo entregó (solo se le devolvió el formato de tablas y código). **Manda** sobre el plan de trabajo [fase-1-plan.md](fase-1-plan.md). Cómo se cumple cada punto y qué se hizo distinto está en [docs/estado.md](../estado.md) y en los ADR de `docs/decisiones/`.

## 1. Objetivo y alcance

Al cerrar la Fase 1, Grupo LF tiene una identidad central donde cada persona entra con su cuenta, ve solo lo que le corresponde y cada cambio queda registrado para siempre. Ningún módulo operativo empieza antes.

Este documento es la bajada técnica del Módulo Maestro de Usuarios redactado por Soy, que se guarda en `docs/modulos/00-identidad.md` y manda ante cualquier duda. Se apoya en el Prompt Maestro (`docs/prompt-maestro.md`).

| Entra en la Fase 1                                       | Queda para después                          |
| -------------------------------------------------------- | ------------------------------------------- |
| Estructura del grupo: grupo, marcas, restaurantes, áreas | Recetas, ingredientes, proveedores (Fase 2) |
| Login, recuperación, verificación, MFA, sesiones         | Compras, stock, producción (Fase 3)         |
| Perfiles, roles, permisos y asignaciones por alcance     | Tableros de negocio (Fase 4)                |
| Función central de permisos y RLS en todas las tablas    | Agentes de IA funcionando (Fase 5)          |
| Auditoría inalterable y eventos de seguridad             | Modo oscuro                                 |
| Motor de aprobaciones genérico                           | Integraciones externas                      |
| Cuentas técnicas para futuros agentes (solo estructura)  |                                             |
| Panel de administración de usuarios y tablero de control |                                             |
| Las 13 pruebas obligatorias, más las adicionales         |                                             |

## 2. Condiciones previas

La Fase 1 arranca solo si la Fase 0 está cerrada y aprobada. Claude Code lo verifica al inicio de la primera sesión y se detiene si algo falta.

- [ ] Repositorio en GitHub a nombre de Soy, con `main` protegida
- [ ] `CLAUDE.md`, `.claude/rules/`, `.claude/settings.json` y los 4 subagentes revisores creados
- [ ] Next.js + TypeScript strict + Tailwind + shadcn/ui con la paleta y la tipografía del sistema de diseño
- [ ] Supabase local funcionando y `supabase db reset` sin errores
- [ ] pgTAP, Vitest y Playwright instalados, con una prueba de ejemplo en verde
- [ ] GitHub Actions corriendo todas las pruebas en cada pull request
- [ ] Proyectos de Supabase de desarrollo y prueba creados; producción todavía sin datos
- [ ] `docs/prompt-maestro.md`, `docs/modulos/00-identidad.md` y `docs/estado.md` en el repositorio

## 3. Orden de construcción

Diez migraciones en este orden exacto. Cada una se aplica desde cero con `supabase db reset`, tiene sus pruebas pgTAP y va en su propio pull request.

| #   | Archivo                          | Qué crea                                                                                                                                |
| --- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `0001_schemas_y_extensiones.sql` | Esquemas core, org, audit, workflow, ai, reporting; extensiones necesarias; permisos base revocados a public                            |
| 2   | `0002_tipos_y_utilidades.sql`    | Tipos enum de estados y alcances; trigger `set_updated_fields()` para updated_at y updated_by                                           |
| 3   | `0003_organizacion.sql`          | `org.groups`, `org.brands`, `org.restaurants`, `org.areas`                                                                              |
| 4   | `0004_perfiles.sql`              | `core.user_profiles` ligada a `auth.users`; alta automática al aceptar invitación                                                       |
| 5   | `0005_roles_y_permisos.sql`      | `core.roles`, `core.permissions`, `core.role_permissions`, catálogo inicial                                                             |
| 6   | `0006_asignaciones.sql`          | `core.user_memberships`, `core.user_role_assignments` con alcance grupo, marca o restaurante                                            |
| 7   | `0007_funcion_permisos.sql`      | `core.has_permission()` y helpers; RLS activado y políticas en todas las tablas anteriores                                              |
| 8   | `0008_auditoria.sql`             | `audit.audit_events`, `audit.authentication_security_events`, trigger `audit.log_change()` en todas las tablas, bloqueo de modificación |
| 9   | `0009_aprobaciones.sql`          | `workflow.approval_workflows`, `approval_requests`, `approval_decisions` y funciones `request_approval()` / `decide_approval()`         |
| 10  | `0010_cuentas_tecnicas.sql`      | `core.service_accounts`, `ai.integration_permissions` (solo estructura, sin agentes activos)                                            |

Una migración ya aplicada en prueba o producción nunca se edita: cualquier corrección es una migración nueva.

## 4. Modelo de datos

Diecisiete tablas en cinco esquemas (`org`, `core`, `audit`, `workflow`, `ai`). Todas llevan id uuid, columnas de control (`created_at`, `created_by`, `updated_at`, `updated_by`) y `comment on` en español; las modificables llevan además `deleted_at` y `deleted_by`.

| Tabla                                  | Columnas clave                                                                                                                                 | Reglas                                                   |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `org.groups`                           | name, legal_name, tax_id, status                                                                                                               | Hoy un solo grupo; preparado para varios                 |
| `org.brands`                           | group_id, name, code, status                                                                                                                   | code único por grupo (ej. RAGU)                          |
| `org.restaurants`                      | group_id, brand_id, name, code, address, timezone, status                                                                                      | group_id coincide con el de su marca                     |
| `org.areas`                            | group_id, name                                                                                                                                 | Cocina, salón, administración, compras                   |
| `core.user_profiles`                   | id = auth.users.id, first_name, last_name, email, username, job_title, area_id, status, activated_at, last_seen_at, deactivated_at, invited_by | status: activo, suspendido, desactivado. Nunca se borra  |
| `core.roles`                           | code, name, level, is_system                                                                                                                   | 10 roles iniciales; level es orientativo, no da permisos |
| `core.permissions`                     | code, module, action, description, is_sensitive                                                                                                | code = módulo.acción, ej. recipes.publish                |
| `core.role_permissions`                | role_id, permission_id                                                                                                                         | Único por par                                            |
| `core.user_memberships`                | user_id, group_id, brand_id, restaurant_id, starts_at, ends_at                                                                                 | Dónde trabaja cada persona                               |
| `core.user_role_assignments`           | user_id, role_id, scope_type, group_id, brand_id, restaurant_id, granted_by, granted_at, revoked_at, revoked_by                                | check: el alcance y sus columnas son coherentes          |
| `core.service_accounts`                | code, name, description, status, owner_user_id                                                                                                 | Una por agente o integración                             |
| `audit.audit_events`                   | ver sección 6                                                                                                                                  | Solo inserción                                           |
| `audit.authentication_security_events` | occurred_at, user_id, event_type, ip_address, user_agent, detail                                                                               | Logins, fallos, bloqueos, MFA, accesos denegados         |
| `workflow.*`                           | ver sección 7                                                                                                                                  | Motor de aprobaciones genérico                           |

Índices mínimos: cada clave foránea; `user_role_assignments (user_id) where revoked_at is null`; `restaurants (brand_id)`; `audit_events (table_name, record_id, occurred_at desc)` y `(actor_user_id, occurred_at desc)`.

> Pendiente de confirmar con Soy: si se necesita guardar CUIT y razón social por restaurante, además de por grupo.

## 5. Permisos: función central y RLS

Una sola función decide si alguien puede hacer algo, y todas las políticas, funciones y pantallas la usan. Si la función dice que no, no hay forma de hacerlo.

**Cómo decide:** el usuario está activo, tiene una asignación vigente con un rol que incluye ese permiso, y el alcance de la asignación cubre la marca o el restaurante pedido. Una asignación de grupo cubre todo; una de marca cubre sus restaurantes; una de restaurante cubre solo ese local.

Base de referencia para la migración 0007 (Claude Code la ajusta y la prueba, no la copia a ciegas):

```sql
create or replace function core.has_permission(
  p_permission    text,
  p_brand_id      uuid default null,
  p_restaurant_id uuid default null
) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from core.user_role_assignments a
    join core.user_profiles  u  on u.id = a.user_id and u.status = 'active'
    join core.role_permissions rp on rp.role_id = a.role_id
    join core.permissions    p  on p.id = rp.permission_id and p.code = p_permission
    where a.user_id = auth.uid()
      and a.revoked_at is null
      and (
        a.scope_type = 'group'
        or (a.scope_type = 'brand' and a.brand_id = coalesce(
              p_brand_id,
              (select r.brand_id from org.restaurants r where r.id = p_restaurant_id)))
        or (a.scope_type = 'restaurant' and a.restaurant_id = p_restaurant_id)
      )
  );
$$;

revoke all on function core.has_permission(text, uuid, uuid) from public;
grant execute on function core.has_permission(text, uuid, uuid) to authenticated;
```

Ejemplo de política sobre una tabla:

```sql
alter table org.restaurants enable row level security;

create policy restaurants_select on org.restaurants
  for select to authenticated
  using (core.has_permission('org.view', brand_id, id));

create policy restaurants_update on org.restaurants
  for update to authenticated
  using (core.has_permission('org.manage', brand_id, id))
  with check (core.has_permission('org.manage', brand_id, id));
```

Reglas:

- RLS activado en todas las tablas, con una política por operación (select, insert, update, delete). Sin política = sin acceso.
- Nadie hace delete físico desde la app: el borrado lógico es un update con su propio permiso (`*.archive`).
- Las acciones sensibles (publicar, aprobar, cambiar permisos) no se hacen con update directo sino con funciones SQL que validan, escriben y auditan juntas.
- Un helper `core.my_scopes()` devuelve las marcas y restaurantes del usuario, para armar menús y filtros sin consultas repetidas.
- Revisar con `explain analyze` que las políticas usen índices; si hace falta, cachear con `(select auth.uid())` dentro de la política.
- Las cuentas técnicas de agentes tendrán su propia función equivalente en la Fase 5; en la Fase 1 solo se crea la estructura.

## 6. Auditoría inalterable

Cada cambio en cualquier tabla de negocio se registra solo, desde la base, dentro de la misma transacción. Si el registro de auditoría falla, el cambio tampoco se guarda.

**Columnas de `audit.audit_events`:** id, occurred_at, actor_user_id, actor_service_account_id, actor_role_code, scope_brand_id, scope_restaurant_id, module, table_schema, table_name, record_id, action (insert, update, delete, approve, reject, publish, login_denied), changed_fields text[], old_values jsonb, new_values jsonb, reason, source (manual, importación, integración, agente), operation_id, status.

**Cómo llega el contexto:** las funciones de servidor fijan motivo, origen y número de operación al comenzar la transacción, y el trigger los lee.

```sql
-- dentro de una función que hace un cambio sensible
perform set_config('app.change_reason', p_reason, true);
perform set_config('app.change_source', 'manual', true);
perform set_config('app.operation_id', gen_random_uuid()::text, true);
```

**Trigger genérico `audit.log_change()`:** se instala con un `after insert or update or delete` en cada tabla de negocio. Guarda los valores anteriores y nuevos en jsonb, calcula `changed_fields` comparando ambos y quita columnas sensibles definidas en una lista de exclusión.

**Historia que nadie puede reescribir:**

```sql
revoke update, delete, truncate on audit.audit_events
  from public, anon, authenticated, service_role;

create trigger audit_events_block_changes
  before update or delete on audit.audit_events
  for each row execute function audit.reject_change();
```

- Lectura del historial solo con el permiso `audit.view`, filtrada por alcance.
- Una vista `audit.v_field_changes` muestra cada campo cambiado en una fila (antes, después, quién, cuándo, por qué). Es la que usa la pantalla de historial.
- Los accesos denegados y los fallos de login van a `authentication_security_events`.
- Nunca se guardan contraseñas, tokens, claves ni el contenido de `auth.*`.
- Cuando la tabla crezca, se particiona por mes sin cambiar la aplicación.

## 7. Aprobaciones

Un solo motor de aprobaciones sirve para todo el sistema: recetas, precios, permisos y propuestas de agentes. Cada módulo solo declara qué cambios necesitan aprobación y quién puede darla.

Una solicitud rechazada o cancelada nunca se reabre: se corrige y se pide de nuevo, así la historia queda completa.

| Tabla                         | Columnas clave                                                                                                                    |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `workflow.approval_workflows` | code, entity_table, required_permission, allow_self_approval, min_approvers, is_active                                            |
| `workflow.approval_requests`  | workflow_id, entity_table, entity_id, brand_id, restaurant_id, requested_by, requested_at, reason, proposed_changes jsonb, status |
| `workflow.approval_decisions` | request_id, decided_by, decision, comment, decided_at                                                                             |

- `workflow.request_approval()` crea el pedido con motivo obligatorio y avisa a quienes pueden decidir.
- `workflow.decide_approval()` valida permiso, alcance y regla de no autoaprobación; registra la decisión y, si aprueba, aplica el cambio en la misma transacción.
- Las decisiones no se editan ni se borran. Quedan auditadas como cualquier otro cambio.

> Pendiente de confirmar con Soy: qué cambios exigen dos aprobadores, por ejemplo precios por encima de cierto porcentaje de aumento.

## 8. Roles iniciales

Los 10 roles del Módulo Maestro se cargan como catálogo inicial. Son un punto de partida: el administrador los ajusta desde el panel sin tocar código.

| Rol                    | Alcance típico      | Puede                                                        | No puede                                 |
| ---------------------- | ------------------- | ------------------------------------------------------------ | ---------------------------------------- |
| Superadministrador     | Grupo               | Seguridad técnica, usuarios, roles, permisos                 | Reescribir o borrar auditoría            |
| Dirección General      | Grupo               | Ver todo lo consolidado, aprobar cambios críticos            | Administrar la seguridad técnica         |
| Director de Marca      | Marca               | Gestionar su marca y sus locales, aprobar dentro de la marca | Ver otras marcas salvo permiso explícito |
| Gerente de Restaurante | Restaurante         | Gestionar su local y su equipo, ver reportes                 | Editar recetas de otros locales          |
| Chef Ejecutivo         | Marca               | Aprobar y publicar recetas                                   | Cambiar precios de materias primas       |
| Jefe de Cocina         | Restaurante o marca | Crear borradores y pedir revisión                            | Publicar sin aprobación                  |
| Controller / Costos    | Grupo o marca       | Ver y modificar costos, aprobar precios                      | Cambiar gramajes aprobados               |
| Compras                | Grupo o marca       | Cargar proveedores y precios propuestos                      | Aprobar sus propios precios              |
| Cocinero / Operador    | Restaurante         | Ver fichas vigentes de su local                              | Ver precios y costos                     |
| Auditor / Consulta     | Según asignación    | Leer historial y reportes                                    | Crear, editar o aprobar                  |

**Permisos de la Fase 1:** `org.view`, `org.manage`, `users.view`, `users.invite`, `users.manage`, `users.deactivate`, `roles.manage`, `permissions.manage`, `audit.view`, `audit.export`, `security.view`, `approvals.view`, `approvals.decide`, `workflows.manage`.

Los permisos de recetas, costos y compras se agregan al catálogo en la fase de cada módulo, con el mismo formato.

## 9. Pantallas

Diez pantallas, todas con la estética simple del Prompt Maestro: fondo blanco cálido, tarjetas blancas, estados en pastel, tipografía Inter, celular primero.

| Pantalla                | Quién la usa       | Qué muestra y permite                                                                        |
| ----------------------- | ------------------ | -------------------------------------------------------------------------------------------- |
| Ingreso                 | Todos              | Correo y contraseña, recordar sesión, enlace de recuperación                                 |
| Recuperar contraseña    | Todos              | Pedido por correo y cambio con enlace seguro                                                 |
| Aceptar invitación      | Nuevo usuario      | Crear contraseña, verificar correo, activar MFA si su rol lo exige                           |
| Mi cuenta               | Todos              | Datos propios, cambio de contraseña, MFA, sesiones abiertas                                  |
| Selector de local       | Quien tiene varios | Elegir marca y restaurante activos; recordar el último                                       |
| Usuarios                | Administración     | Lista con filtros por estado, marca, restaurante, rol y área; invitar, suspender, desactivar |
| Ficha de usuario        | Administración     | Roles y alcances, último acceso, actividad reciente, intentos rechazados                     |
| Roles y permisos        | Superadministrador | Matriz rol por permiso, con cambios auditados y motivo obligatorio                           |
| Bandeja de aprobaciones | Quien aprueba      | Solicitudes pendientes, diferencias antes y después, aprobar o rechazar con motivo           |
| Historial               | Auditor, dirección | Búsqueda por fecha, usuario, marca, restaurante, módulo y registro; exportar                 |

**Tablero de control de usuarios** (pregunta: "¿quién tiene acceso y qué está pasando?"):

- Tarjetas KPI: usuarios activos, desactivados, aprobaciones pendientes, accesos rechazados en 7 días.
- Gráfico: accesos por día en los últimos 30 días.
- Tablas: usuarios por restaurante y por rol, últimos cambios críticos.
- Filtros fijos: fecha, marca, restaurante, módulo.

Toda pantalla consulta la base con el usuario conectado, así RLS filtra solo lo que corresponde. Un botón que no corresponde no se muestra, pero la protección real está en la base.

## 10. Pruebas

La Fase 1 cierra cuando las 13 pruebas obligatorias del Módulo Maestro y las 10 adicionales corren en GitHub Actions y pasan. Cada prueba usa usuarios ficticios del `seed.sql`, uno por rol.

| #   | Prueba obligatoria                                        | Dónde                       |
| --- | --------------------------------------------------------- | --------------------------- |
| 1   | Sin sesión no se consulta información privada             | pgTAP + Playwright          |
| 2   | Cocinero abre la receta vigente pero no ve costos         | pgTAP (con tabla de prueba) |
| 3   | Jefe de cocina crea borrador pero no publica sin permiso  | pgTAP                       |
| 4   | Gerente no edita fuera de su restaurante                  | pgTAP                       |
| 5   | Dirección ve lo consolidado según permisos                | pgTAP                       |
| 6   | Un cambio registra usuario, fecha, campo y valores        | pgTAP                       |
| 7   | Una versión aprobada conserva su historia                 | pgTAP                       |
| 8   | Una cuenta desactivada pierde acceso                      | pgTAP + Playwright          |
| 9   | Usuario con dos restaurantes opera solo en los suyos      | pgTAP                       |
| 10  | Una cuenta técnica no supera sus permisos                 | pgTAP                       |
| 11  | Una operación rechazada queda registrada                  | pgTAP                       |
| 12  | Una aprobación guarda identidad, fecha y decisión         | pgTAP                       |
| 13  | No se puede alterar el historial con operaciones normales | pgTAP                       |

Las pruebas 2, 3 y 7 hablan de recetas, que llegan en la Fase 2. En la Fase 1 se prueban con una tabla de ensayo `core.test_documents` que imita una receta (borrador, costos, versiones) y se borra al cerrar la fase. En la Fase 2 se repiten sobre las tablas reales.

**Pruebas adicionales:**

1. Un usuario no puede darse permisos ni roles a sí mismo.
2. No se puede aprobar la propia solicitud cuando la política lo prohíbe.
3. Ni el superadministrador puede borrar o modificar `audit_events` desde la app.
4. Revocar un rol corta el acceso en la siguiente consulta.
5. Un usuario suspendido no puede iniciar sesión; uno reactivado sí.
6. Las asignaciones con alcance incoherente son rechazadas por la base.
7. Tras 5 intentos fallidos de login se bloquea temporalmente y queda registrado.
8. Los roles 1 a 4 y Controller no entran sin MFA.
9. Todas las tablas tienen RLS activo (prueba que recorre el catálogo de la base).
10. Las consultas del tablero de usuarios responden en menos de 300 ms con 500 usuarios de prueba.

## 11. Prompts para pegar, sesión por sesión

Siete sesiones, una por bloque. Joaco guarda este documento como `docs/fases/fase-1.md` y abre cada sesión en modo plan con el prompt correspondiente.

**Prompt de apertura** (se pega al inicio de cada sesión):

```text
Leé docs/prompt-maestro.md, docs/modulos/00-identidad.md,
docs/fases/fase-1.md y docs/estado.md. Confirmá en qué sesión
estamos y qué quedó pendiente. Después proponé el plan de esta
sesión en modo plan: migraciones, funciones, políticas, pantallas,
pruebas y riesgos. No escribas código hasta que apruebe el plan.
```

| Sesión                              | Prompt                                                                                                                                                                                                                            |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Organización y perfiles          | "Construí las migraciones 0001 a 0004 de la sección 3, con el modelo de la sección 4. Incluí el seed.sql con un grupo ficticio, 3 marcas, 4 restaurantes y un usuario por rol. Pruebas pgTAP de restricciones y triggers."        |
| 2. Roles, permisos y asignaciones   | "Construí 0005 y 0006 con el catálogo de la sección 8. Validá en la base que el alcance de cada asignación sea coherente. Pruebas de alta, revocación y alcances."                                                                |
| 3. Función de permisos y RLS        | "Construí 0007 siguiendo la sección 5. Activá RLS en todas las tablas con una política por operación. Agregá la prueba que recorre el catálogo y falla si alguna tabla queda sin RLS. Revisá con explain analyze."                |
| 4. Auditoría                        | "Construí 0008 siguiendo la sección 6. Instalá el trigger en todas las tablas de negocio, bloqueá la modificación del historial y creá la vista de cambios por campo. Pruebas 6, 11 y 13."                                        |
| 5. Aprobaciones y cuentas técnicas  | "Construí 0009 y 0010 siguiendo la sección 7. Funciones request_approval y decide_approval, regla de no autoaprobación, tabla de ensayo test_documents. Pruebas 3, 7, 10 y 12."                                                   |
| 6. Ingreso y cuenta                 | "Construí las pantallas de ingreso, recuperación, invitación, mi cuenta y selector de local con Supabase Auth y MFA, siguiendo el sistema de diseño. Pruebas Playwright en celular y computadora."                                |
| 7. Administración, tablero y cierre | "Construí usuarios, ficha de usuario, roles y permisos, bandeja de aprobaciones, historial y tablero de control de la sección 9. Corré las 23 pruebas, pedí revisión a los 4 subagentes y prepará el informe de cierre para Soy." |

Al terminar cada sesión, Claude Code actualiza `docs/estado.md`, deja un pull request con resumen en simple y espera la aprobación de Joaco antes de la siguiente.

## 12. Compuerta de cierre

La Fase 2 (recetario y costos) se habilita solo cuando Soy marca todo esto, en una demo de Joaco sobre el ambiente de prueba.

- [ ] Vi en GitHub las 23 pruebas en verde
- [ ] Entré como dirección y vi los 4 restaurantes de prueba
- [ ] Entré como gerente de un local y no vi los otros
- [ ] Entré como cocinero y no vi costos en el documento de ensayo
- [ ] Pedí un cambio, intenté aprobarlo yo mismo y el sistema no me dejó
- [ ] Otra persona lo aprobó y en el historial figuran ambos, con fecha y motivo
- [ ] Desactivé un usuario y perdió el acceso en el momento
- [ ] El tablero de control de usuarios se ve simple y se entiende en el celular
- [ ] Recibí el informe de cierre: qué se hizo, qué quedó pendiente, riesgos
- [ ] Confirmé que las cuentas siguen a mi nombre y que producción no tiene datos de prueba
