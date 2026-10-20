# Diccionario de datos — core, audit y org

> Generado desde los `comment on` de la base local el 2026-10-20. No editar a mano: regenerar después de cada migración.

## `audit.audit_events`

Historia inalterable de todos los cambios: quién, cuándo, qué (antes y después) y por qué. Solo se inserta desde audit.log_change(); nadie puede modificar ni borrar, y los sellos (audit_seals) detectan cualquier alteración.

| Columna               | Tipo                       | Nulo | Qué guarda                                                                                                          |
| --------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------- |
| `id`                  | `uuid`                     | no   | Identificador del evento.                                                                                           |
| `sequence_number`     | `bigint`                   | no   | Orden exacto de los eventos, incluso dentro de una misma transacción. Base de los sellos.                           |
| `occurred_at`         | `timestamp with time zone` | no   | Cuándo ocurrió el cambio (hora de la transacción).                                                                  |
| `actor_id`            | `uuid`                     | sí   | Quién hizo el cambio. Nulo en migraciones, seed, clave de servidor o si el actor no estaba registrado.              |
| `actor_type`          | `core.actor_type`          | sí   | Persona o cuenta técnica, en el momento del cambio.                                                                 |
| `actor_subject`       | `text`                     | sí   | El sub del JWT cuando no corresponde a ningún actor registrado (para no perder el rastro).                          |
| `jwt_role`            | `text`                     | sí   | Rol del JWT de la sesión (authenticated, service_role...). Nulo sin JWT, por ejemplo en una conexión directa.       |
| `db_user`             | `text`                     | no   | Usuario de Postgres de la conexión (authenticator para la API, postgres para migraciones o el editor SQL).          |
| `actor_roles`         | `jsonb`                    | sí   | Roles vigentes del actor en el momento del cambio. Se completa desde que existan los roles (M4).                    |
| `scope_group_id`      | `uuid`                     | sí   | Grupo al que pertenece el registro cambiado, si tiene.                                                              |
| `scope_brand_id`      | `uuid`                     | sí   | Marca a la que pertenece el registro cambiado, si tiene.                                                            |
| `scope_restaurant_id` | `uuid`                     | sí   | Restaurante al que pertenece el registro cambiado, si tiene.                                                        |
| `schema_name`         | `text`                     | no   | Esquema de la tabla cambiada.                                                                                       |
| `table_name`          | `text`                     | no   | Tabla cambiada.                                                                                                     |
| `record_id`           | `uuid`                     | no   | Id del registro cambiado.                                                                                           |
| `action`              | `audit.action`             | no   | Qué pasó: alta, cambio, borrado lógico, restauración o borrado físico.                                              |
| `old_values`          | `jsonb`                    | sí   | Valores anteriores, sin secretos. Nulo en un alta. OJO al exponer: incluye todas las columnas (por ejemplo costos). |
| `new_values`          | `jsonb`                    | sí   | Valores nuevos, sin secretos. Nulo en un borrado físico. OJO al exponer: incluye todas las columnas.                |
| `changed_fields`      | `text[]`                   | sí   | Columnas que cambiaron (solo en cambios, borrados lógicos y restauraciones).                                        |
| `reason`              | `text`                     | sí   | Motivo del cambio (hasta 500 caracteres), informado por la función que lo hizo. Informativo.                        |
| `origin`              | `audit.change_origin`      | sí   | Desde dónde se hizo el cambio. Nulo si no se informó o si el valor no era válido. Informativo.                      |
| `transaction_id`      | `bigint`                   | no   | Transacción de Postgres: agrupa los eventos de una misma operación.                                                 |

## `audit.audit_seals`

Sellos de la auditoría: cada uno cubre un tramo de eventos y encadena su huella con la del sello anterior. Permite detectar cualquier alteración de eventos ya sellados.

| Columna          | Tipo                       | Nulo | Qué guarda                                                      |
| ---------------- | -------------------------- | ---- | --------------------------------------------------------------- |
| `id`             | `bigint`                   | no   | Número de sello, en orden.                                      |
| `sealed_at`      | `timestamp with time zone` | no   | Cuándo se selló el tramo.                                       |
| `first_sequence` | `bigint`                   | no   | Primer sequence_number del tramo sellado.                       |
| `last_sequence`  | `bigint`                   | no   | Último sequence_number del tramo sellado.                       |
| `event_count`    | `integer`                  | no   | Cantidad de eventos que había en el tramo al sellarlo.          |
| `previous_hash`  | `bytea`                    | no   | Huella del sello anterior (o la huella inicial, en el primero). |
| `chain_hash`     | `bytea`                    | no   | Huella acumulada hasta el último evento del tramo.              |

## `core.actors`

Quién puede hacer cambios: una fila por cada usuario de Supabase Auth, sea persona o cuenta técnica. Las columnas created_by, updated_by y deleted_by de todas las tablas apuntan acá. Un usuario con historia no se borra: se bloquea.

| Columna      | Tipo                       | Nulo | Qué guarda                                                                                                                    |
| ------------ | -------------------------- | ---- | ----------------------------------------------------------------------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Mismo id que el usuario en auth.users.                                                                                        |
| `actor_type` | `core.actor_type`          | no   | Persona o cuenta técnica, según app_metadata al darse de alta (solo lo escribe el servidor). Descriptivo: no decide permisos. |
| `created_at` | `timestamp with time zone` | no   | Cuándo se dio de alta el actor.                                                                                               |

## `core.permissions`

Catálogo de permisos. Un permiso es módulo + acción, por ejemplo recipes.publish. Se carga por migración.

| Columna        | Tipo                       | Nulo | Qué guarda                                                  |
| -------------- | -------------------------- | ---- | ----------------------------------------------------------- |
| `id`           | `uuid`                     | no   | Identificador del permiso.                                  |
| `code`         | `text`                     | no   | Código módulo.acción, en minúsculas.                        |
| `module`       | `text`                     | no   | Módulo al que pertenece (la parte antes del punto).         |
| `description`  | `text`                     | no   | Qué permite hacer, en español.                              |
| `is_sensitive` | `boolean`                  | no   | Si es un permiso delicado (seguridad, usuarios, auditoría). |
| `created_at`   | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                           |
| `created_by`   | `uuid`                     | sí   | Quién lo creó (lo pone la base).                            |
| `updated_at`   | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).          |
| `updated_by`   | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).           |
| `deleted_at`   | `timestamp with time zone` | sí   | Borrado lógico. Vacío si está vigente.                      |
| `deleted_by`   | `uuid`                     | sí   | Quién lo borró (lo pone la base).                           |

## `core.role_permissions`

Qué permisos tiene cada rol. Quitar un permiso es un borrado lógico, que queda en el historial.

| Columna         | Tipo                       | Nulo | Qué guarda                                               |
| --------------- | -------------------------- | ---- | -------------------------------------------------------- |
| `id`            | `uuid`                     | no   | Identificador de la relación.                            |
| `role_id`       | `uuid`                     | no   | Rol.                                                     |
| `permission_id` | `uuid`                     | no   | Permiso que tiene ese rol.                               |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se otorgó (lo pone la base).                      |
| `created_by`    | `uuid`                     | sí   | Quién lo otorgó (lo pone la base).                       |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).       |
| `updated_by`    | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).        |
| `deleted_at`    | `timestamp with time zone` | sí   | Cuándo se quitó (borrado lógico). Vacío si está vigente. |
| `deleted_by`    | `uuid`                     | sí   | Quién lo quitó (lo pone la base).                        |

## `core.roles`

Roles del Módulo Maestro (por ejemplo, Gerente de Restaurante). Un rol agrupa permisos; el alcance lo da cada asignación.

| Columna        | Tipo                       | Nulo | Qué guarda                                                             |
| -------------- | -------------------------- | ---- | ---------------------------------------------------------------------- |
| `id`           | `uuid`                     | no   | Identificador del rol.                                                 |
| `code`         | `text`                     | no   | Código del rol, en minúsculas.                                         |
| `name`         | `text`                     | no   | Nombre del rol, en español.                                            |
| `description`  | `text`                     | sí   | Qué puede y qué no puede, según el Módulo Maestro.                     |
| `level`        | `smallint`                 | sí   | Nivel orientativo (orden del Módulo Maestro). No da permisos.          |
| `requires_mfa` | `boolean`                  | no   | Si las personas con este rol tienen que usar doble verificación (MFA). |
| `is_system`    | `boolean`                  | no   | Si es un rol del catálogo inicial.                                     |
| `created_at`   | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                      |
| `created_by`   | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                       |
| `updated_at`   | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                     |
| `updated_by`   | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                      |
| `deleted_at`   | `timestamp with time zone` | sí   | Borrado lógico. Vacío si está vigente.                                 |
| `deleted_by`   | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                      |

## `core.service_accounts`

Cuenta técnica de un agente o integración. Es un usuario de Auth de tipo cuenta técnica, con permisos mínimos y explícitos (Fase 5). Nunca usa la clave service_role.

| Columna         | Tipo                       | Nulo | Qué guarda                                          |
| --------------- | -------------------------- | ---- | --------------------------------------------------- |
| `id`            | `uuid`                     | no   | Mismo id que su actor y su usuario técnico de Auth. |
| `code`          | `text`                     | no   | Código de la cuenta (por ejemplo, agente-facturas). |
| `name`          | `text`                     | no   | Nombre de la cuenta, en español.                    |
| `description`   | `text`                     | sí   | Para qué se usa.                                    |
| `status`        | `core.account_status`      | no   | Si la cuenta puede operar o está bloqueada.         |
| `owner_user_id` | `uuid`                     | no   | Persona responsable de la cuenta.                   |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                   |
| `created_by`    | `uuid`                     | sí   | Quién la creó (lo pone la base).                    |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).  |
| `updated_by`    | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).   |
| `deleted_at`    | `timestamp with time zone` | sí   | Borrado lógico. Vacío si está vigente.              |
| `deleted_by`    | `uuid`                     | sí   | Quién la borró (lo pone la base).                   |

## `core.user_memberships`

A qué grupo pertenece cada persona. Hace falta ser miembro para recibir roles en ese grupo.

| Columna      | Tipo                       | Nulo | Qué guarda                                              |
| ------------ | -------------------------- | ---- | ------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador de la membresía.                          |
| `user_id`    | `uuid`                     | no   | Persona.                                                |
| `group_id`   | `uuid`                     | no   | Grupo al que pertenece.                                 |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                       |
| `created_by` | `uuid`                     | sí   | Quién la creó (lo pone la base).                        |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).      |
| `updated_by` | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).       |
| `deleted_at` | `timestamp with time zone` | sí   | Cuándo terminó (borrado lógico). Vacío si está vigente. |
| `deleted_by` | `uuid`                     | sí   | Quién la terminó (lo pone la base).                     |

## `core.user_profiles`

Persona que usa el sistema. Una por cada usuario persona de Supabase Auth. Nunca se borra: se bloquea.

| Columna           | Tipo                       | Nulo | Qué guarda                                                                                                                             |
| ----------------- | -------------------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `id`              | `uuid`                     | no   | Mismo id que el usuario en Auth y que su actor.                                                                                        |
| `first_name`      | `text`                     | sí   | Nombre.                                                                                                                                |
| `last_name`       | `text`                     | sí   | Apellido.                                                                                                                              |
| `email`           | `text`                     | no   | Correo con el que entra (copiado de Auth al darse de alta). No se edita a mano; la sincronización con los cambios de Auth llega en M8. |
| `status`          | `core.account_status`      | no   | Si la cuenta puede operar o está bloqueada.                                                                                            |
| `disabled_at`     | `timestamp with time zone` | sí   | Cuándo se bloqueó la cuenta. Vacío si está activa.                                                                                     |
| `disabled_reason` | `text`                     | sí   | Por qué se bloqueó la cuenta.                                                                                                          |
| `created_at`      | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                                      |
| `created_by`      | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                                                       |
| `updated_at`      | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                                     |
| `updated_by`      | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                                                      |
| `deleted_at`      | `timestamp with time zone` | sí   | Borrado lógico. Un perfil con historia no se borra: se bloquea.                                                                        |
| `deleted_by`      | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                                                      |

## `core.user_role_assignments`

Qué rol tiene cada persona y dónde: en todo el grupo, en una marca o en un local. Quitar un rol es un borrado lógico. Desde M6 solo se escribe con core.assign_role().

| Columna         | Tipo                       | Nulo | Qué guarda                                                      |
| --------------- | -------------------------- | ---- | --------------------------------------------------------------- |
| `id`            | `uuid`                     | no   | Identificador de la asignación.                                 |
| `user_id`       | `uuid`                     | no   | Persona.                                                        |
| `role_id`       | `uuid`                     | no   | Rol asignado.                                                   |
| `scope_type`    | `core.scope_type`          | no   | Alcance: grupo, marca o restaurante.                            |
| `group_id`      | `uuid`                     | no   | Grupo de la asignación (siempre).                               |
| `brand_id`      | `uuid`                     | sí   | Marca, si el alcance es marca o restaurante.                    |
| `restaurant_id` | `uuid`                     | sí   | Restaurante, si el alcance es restaurante.                      |
| `valid_from`    | `timestamp with time zone` | no   | Desde cuándo vale.                                              |
| `valid_until`   | `timestamp with time zone` | sí   | Hasta cuándo vale. Vacío si no vence.                           |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se asignó (lo pone la base).                             |
| `created_by`    | `uuid`                     | sí   | Quién lo asignó (lo pone la base).                              |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).              |
| `updated_by`    | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).               |
| `deleted_at`    | `timestamp with time zone` | sí   | Cuándo se quitó el rol (borrado lógico). Vacío si está vigente. |
| `deleted_by`    | `uuid`                     | sí   | Quién quitó el rol (lo pone la base).                           |

## `org.areas`

Área de trabajo dentro de un restaurante (por ejemplo, cocina, salón o depósito).

| Columna         | Tipo                       | Nulo | Qué guarda                                                                                 |
| --------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------ |
| `id`            | `uuid`                     | no   | Identificador del área.                                                                    |
| `group_id`      | `uuid`                     | no   | Grupo al que pertenece. Tiene que coincidir con el de su restaurante.                      |
| `restaurant_id` | `uuid`                     | no   | Restaurante al que pertenece el área.                                                      |
| `name`          | `text`                     | no   | Nombre del área. Único dentro del restaurante entre las vigentes, sin importar mayúsculas. |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                          |
| `created_by`    | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                           |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                         |
| `updated_by`    | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                          |
| `deleted_at`    | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                   |
| `deleted_by`    | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                          |

## `org.brands`

Marca del grupo (por ejemplo, RAGU). Tiene sus recetas estándar, precios y reportes.

| Columna      | Tipo                       | Nulo | Qué guarda                                                                              |
| ------------ | -------------------------- | ---- | --------------------------------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador de la marca.                                                              |
| `group_id`   | `uuid`                     | no   | Grupo al que pertenece la marca.                                                        |
| `name`       | `text`                     | no   | Nombre de la marca. Único dentro del grupo entre las vigentes, sin importar mayúsculas. |
| `status`     | `org.unit_status`          | no   | Si la marca está operando o cerrada.                                                    |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                       |
| `created_by` | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                        |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                      |
| `updated_by` | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                       |
| `deleted_at` | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                |
| `deleted_by` | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                       |

## `org.groups`

Grupo gastronómico: el nivel más alto de la organización (por ejemplo, Grupo LF). Preparado para más de uno.

| Columna      | Tipo                       | Nulo | Qué guarda                                                                  |
| ------------ | -------------------------- | ---- | --------------------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador del grupo.                                                    |
| `name`       | `text`                     | no   | Nombre del grupo. Único entre los grupos vigentes, sin importar mayúsculas. |
| `status`     | `org.unit_status`          | no   | Si el grupo está operando o cerrado.                                        |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                           |
| `created_by` | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                            |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                          |
| `updated_by` | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                           |
| `deleted_at` | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                    |
| `deleted_by` | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                           |

## `org.restaurants`

Restaurante (local) de una marca (por ejemplo, RAGU Parque Leloir). Es donde pasa la operación diaria.

| Columna      | Tipo                       | Nulo | Qué guarda                                                                                    |
| ------------ | -------------------------- | ---- | --------------------------------------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador del restaurante.                                                                |
| `group_id`   | `uuid`                     | no   | Grupo al que pertenece. Tiene que coincidir con el de su marca.                               |
| `brand_id`   | `uuid`                     | no   | Marca del restaurante.                                                                        |
| `name`       | `text`                     | no   | Nombre del restaurante. Único dentro de la marca entre los vigentes, sin importar mayúsculas. |
| `status`     | `org.unit_status`          | no   | Si el restaurante está operando o cerrado.                                                    |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                             |
| `created_by` | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                              |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                            |
| `updated_by` | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                             |
| `deleted_at` | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                      |
| `deleted_by` | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                             |

## Tipos

| Tipo                  | Valores                                                          | Qué significa                                                                                                                                                                                           |
| --------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `audit.action`        | `insert`, `update`, `soft_delete`, `restore`, `delete`           | Qué pasó con el registro: insert (alta), update (cambio), soft_delete (borrado lógico), restore (restauración) o delete (borrado físico, solo mantenimiento).                                           |
| `audit.change_origin` | `app`, `edge_function`, `agent`, `import`, `seed`, `maintenance` | Desde dónde se hizo un cambio: app (la aplicación), edge_function (función de servidor), agent (agente de IA), import (carga masiva), seed (datos de prueba) o maintenance (mantenimiento documentado). |
| `core.account_status` | `active`, `disabled`                                             | Estado de una cuenta: active (puede operar) o disabled (bloqueada; conserva toda su historia).                                                                                                          |
| `core.actor_type`     | `user`, `service_account`                                        | Tipo de actor: user (persona) o service_account (cuenta técnica de un agente o integración).                                                                                                            |
| `core.scope_type`     | `group`, `brand`, `restaurant`                                   | Alcance de una asignación de rol: group (todo el grupo), brand (una marca y sus locales) o restaurant (un local).                                                                                       |
| `org.unit_status`     | `active`, `inactive`                                             | Estado de un grupo, marca o restaurante: active (operando) o inactive (cerrado, pero visible en la historia). Borrar un registro es otra cosa: corrige un error de carga.                               |
