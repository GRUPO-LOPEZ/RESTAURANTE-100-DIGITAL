# Módulo 0 — Módulo Maestro de Usuarios

> **La bajada técnica de Soy está en [docs/fases/fase-1.md](../fases/fase-1.md)** y manda (ADR-0015). **Texto completo del Módulo Maestro: PENDIENTE.** Según el prompt maestro (sección 6), el Módulo Maestro de Usuarios lo redactó Soy, "es ley" y se guarda acá completo. Por ahora solo llegó la parte de roles (abajo). Si algo de lo que se construya contradice el texto completo cuando llegue, manda el texto de Soy.

## Roles iniciales

_Recibido de Joaco el 2026-10-20, extraído del Módulo Maestro. Copia fiel._

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

## Pruebas (sección 10 del Módulo Maestro)

_Recibido de Joaco el 2026-10-20. Copia fiel._

La Fase 1 cierra cuando las 13 pruebas obligatorias del Módulo Maestro y las 10 adicionales corren en GitHub Actions y pasan. Cada prueba usa usuarios ficticios del seed.sql, uno por rol.

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

**Pruebas adicionales** (recibidas de Joaco el 2026-10-20, copia fiel):

1. Un usuario no puede darse permisos ni roles a sí mismo.
2. No se puede aprobar la propia solicitud cuando la política lo prohíbe.
3. Ni el superadministrador puede borrar o modificar audit_events desde la app.
4. Revocar un rol corta el acceso en la siguiente consulta.
5. Un usuario suspendido no puede iniciar sesión; uno reactivado sí.
6. Las asignaciones con alcance incoherente son rechazadas por la base.
7. Tras 5 intentos fallidos de login se bloquea temporalmente y queda registrado.
8. Los roles 1 a 4 y Controller no entran sin MFA.
9. Todas las tablas tienen RLS activo (prueba que recorre el catálogo de la base).
10. Las consultas del tablero de usuarios responden en menos de 300 ms con 500 usuarios de prueba.

---

_Lo que sigue no es texto de Soy: es cómo se implementó, aprobado por Joaco._

## Doble verificación (MFA)

Confirmado por Joaco el 2026-10-20: llevan MFA los niveles 1 a 4 de la tabla (Superadministrador, Dirección General, Director de Marca, Gerente de Restaurante) y Controller / Costos. El nivel sigue el orden de la tabla y no da permisos. A un rol del catálogo inicial no se le puede sacar el MFA (lo impide la base).

## Matriz de permisos de la Fase 1

Aprobada por Joaco el 2026-10-20 y ampliada el 2026-10-21 con los permisos del documento de Soy (ADR-0015): `permissions.manage`, `security.view` y `org.archive`. El 2026-10-22 se sumó `users.view_admin_details`: ver el primer y el último acceso de una persona, quién la invitó y los motivos de su suspensión o baja, si alcanza todos sus roles (respuesta 2 de Joaco).

**Aprobaciones (ADR-0017):**

- Un rol sensible lo aprueba Dirección General o el Director de Marca de ese lugar; el Director, solo si tiene todos los permisos del rol.
- Quitarle el rol, suspender o dar de baja a otro Superadministrador lo aprueba Dirección.
- A alguien de Dirección lo da de baja o lo reactiva otra persona de Dirección.
- Un local o una marca cerrados no dan permisos.

**Dónde trabaja limita los roles** (respuesta 9): con una membresía de todo el grupo se puede dar cualquier rol; de una marca, roles de esa marca o de sus locales; de un local, solo roles de ese local. La base no deja terminar una membresía que cubre un rol vigente. Los permisos de ensayo (`test_documents.*`) están aparte, más abajo. El alcance lo da cada asignación (grupo, marca o local), no el rol. Los permisos de recetas, costos y compras se suman en la fase de cada módulo.

| Rol                    | Permisos                                                                                                                                                                                                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Superadministrador     | `org.view`, `org.manage`, `org.archive`, `org.transfer`, `users.view`, `users.view_admin_details`, `users.invite`, `users.manage`, `users.deactivate`, `roles.assign`, `roles.manage`, `permissions.manage`, `audit.view`, `audit.export`, `security.view`, `workflows.manage`, `approvals.view` |
| Dirección General      | `org.view`, `org.transfer`, `users.view`, `users.view_admin_details`, `audit.view`, `audit.export`, `security.view`, `approvals.view`, `approvals.decide`                                                                                                                                        |
| Director de Marca      | `org.view`, `org.manage`, `org.archive`, `users.view`, `users.view_admin_details`, `users.invite`, `users.manage`, `users.deactivate`, `roles.assign`, `audit.view`, `approvals.view`, `approvals.decide`                                                                                        |
| Gerente de Restaurante | `org.view`, `org.manage`, `users.view`, `users.view_admin_details`, `users.invite`, `users.manage`, `users.deactivate`, `roles.assign`, `approvals.view`                                                                                                                                         |
| Chef Ejecutivo         | `org.view`, `approvals.view`, `approvals.decide`                                                                                                                                                                                                                                                 |
| Jefe de Cocina         | `org.view`, `approvals.view`                                                                                                                                                                                                                                                                     |
| Controller / Costos    | `org.view`, `audit.view`, `approvals.view`, `approvals.decide`                                                                                                                                                                                                                                   |
| Compras                | `org.view`, `approvals.view`                                                                                                                                                                                                                                                                     |
| Cocinero / Operador    | `org.view`                                                                                                                                                                                                                                                                                       |
| Auditor / Consulta     | `org.view`, `users.view`, `audit.view`, `audit.export`, `security.view`, `approvals.view`                                                                                                                                                                                                        |

### Permisos de ensayo (solo Fase 1)

La tabla de ensayo `core.test_documents` imita una receta para las pruebas 2, 3 y 7 y para la demo de cierre. Se borra al cerrar la Fase 1.

| Permiso                     | Lo tienen                                                                       |
| --------------------------- | ------------------------------------------------------------------------------- |
| `test_documents.view`       | Todos los roles operativos                                                      |
| `test_documents.edit`       | Jefe de Cocina, Chef Ejecutivo, Gerente, Director de Marca y Superadministrador |
| `test_documents.publish`    | Chef Ejecutivo y Director de Marca                                              |
| `test_documents.view_costs` | Controller y Dirección General                                                  |

## Dónde se prueba cada una (Fase 1)

_Lo que sigue no es texto de Soy: es el mapa de las pruebas, para controlarlas. Cada prueba lleva en su nombre el número de la tabla de arriba. pgTAP está en `supabase/tests/` y Playwright en `tests/e2e/`._

| #   | Prueba                                                    | pgTAP                                                                   | Playwright (celular y computadora)                          |
| --- | --------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------- |
| 1   | Sin sesión no se consulta información privada             | `050_permissions` ("1. …")                                              | `fase1.spec.ts` ("1. sin sesión…")                          |
| 2   | Cocinero abre la receta vigente pero no ve costos         | `100_features` ("2. …", `core.test_documents`), `060_roles_workflow`    | `admin.spec.ts` ("el cocinero ve el documento de ensayo…")  |
| 3   | Jefe de cocina crea borrador pero no publica sin permiso  | `100_features` ("3. …"), `060_roles_workflow` ("3. …")                  | —                                                           |
| 4   | Gerente no edita fuera de su restaurante                  | `050_permissions` ("4. …")                                              | —                                                           |
| 5   | Dirección ve lo consolidado según permisos                | `050_permissions` ("5. …")                                              | —                                                           |
| 6   | Un cambio registra usuario, fecha, campo y valores        | `020_audit`, `050_permissions` (roles de quien cambia)                  | —                                                           |
| 7   | Una versión aprobada conserva su historia                 | `100_features` ("7. …"), `060_roles_workflow` ("7. …")                  | —                                                           |
| 8   | Una cuenta desactivada pierde acceso                      | `080_accounts` ("8. …")                                                 | `fase1.spec.ts` ("8 y A5…")                                 |
| 9   | Usuario con dos restaurantes opera solo en los suyos      | `050_permissions` ("9. …")                                              | —                                                           |
| 10  | Una cuenta técnica no supera sus permisos                 | `050_permissions` ("10. …"), `090_alignment` ("10. …")                  | —                                                           |
| 11  | Una operación rechazada queda registrada                  | `060_roles_workflow` ("11. …"), `100_features`, `110_screens` ("11. …") | —                                                           |
| 12  | Una aprobación guarda identidad, fecha y decisión         | `060_roles_workflow` ("12. …")                                          | `admin.spec.ts` ("se pide un cambio de la matriz…")         |
| 13  | No se puede alterar el historial con operaciones normales | `020_audit`, `050_permissions` ("A3. …")                                | —                                                           |
| A1  | Nadie se da permisos ni roles a sí mismo                  | `060_roles_workflow` ("A1. …")                                          | —                                                           |
| A2  | No se aprueba la propia solicitud                         | `060_roles_workflow` ("A2. …"), `080_accounts` ("A5. …")                | `fase1.spec.ts` ("8 y A5…")                                 |
| A3  | Ni el superadmin altera `audit_events` desde la app       | `050_permissions` ("A3. …")                                             | —                                                           |
| A4  | Revocar un rol corta el acceso en la consulta siguiente   | `050_permissions` ("A4. …")                                             | —                                                           |
| A5  | Suspendido no entra; reactivado sí                        | `080_accounts`, `090_alignment`, `100_features` ("A5. …")               | `fase1.spec.ts` ("8 y A5…"), `admin.spec.ts` ("suspender…") |
| A6  | Asignaciones con alcance incoherente rechazadas           | `040_identity`, `060_roles_workflow` ("A6. …")                          | —                                                           |
| A7  | 5 intentos fallidos bloquean y queda registrado           | `080_accounts` ("A7. …")                                                | `fase1.spec.ts` ("A7. …")                                   |
| A8  | Roles 1 a 4 y Controller no entran sin MFA                | `050_permissions` ("A8. …")                                             | `fase1.spec.ts` ("A8. …")                                   |
| A9  | Todas las tablas tienen RLS (recorre el catálogo)         | `060_roles_workflow` ("A9. …")                                          | —                                                           |
| A10 | Tablero de usuarios en menos de 300 ms con 500 personas   | `080_accounts`, `100_features`, `110_screens` ("A10. …")                | `fase1.spec.ts` ("tablero…", axe)                           |
