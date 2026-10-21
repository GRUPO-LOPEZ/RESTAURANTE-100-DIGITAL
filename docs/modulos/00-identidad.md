# Módulo 0 — Módulo Maestro de Usuarios

> **Texto completo de Soy: PENDIENTE.** Según el prompt maestro (sección 6), el Módulo Maestro de Usuarios lo redactó Soy, "es ley" y se guarda acá completo. Por ahora solo llegó la parte de roles (abajo). Si algo de lo que se construya contradice el texto completo cuando llegue, manda el texto de Soy.

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

Aprobada por Joaco el 2026-10-20. El alcance lo da cada asignación (grupo, marca o local), no el rol. Los permisos de recetas, costos y compras se suman en la fase de cada módulo.

| Rol                    | Permisos                                                                                                                                                                                                       |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Superadministrador     | `org.view`, `org.manage`, `org.transfer`, `users.view`, `users.invite`, `users.manage`, `users.deactivate`, `roles.assign`, `roles.manage`, `audit.view`, `audit.export`, `workflows.manage`, `approvals.view` |
| Dirección General      | `org.view`, `org.transfer`, `users.view`, `audit.view`, `audit.export`, `approvals.view`, `approvals.decide`                                                                                                   |
| Director de Marca      | `org.view`, `org.manage`, `users.view`, `users.invite`, `users.manage`, `users.deactivate`, `roles.assign`, `audit.view`, `approvals.view`, `approvals.decide`                                                 |
| Gerente de Restaurante | `org.view`, `org.manage`, `users.view`, `users.invite`, `users.manage`, `users.deactivate`, `roles.assign`, `approvals.view`                                                                                   |
| Chef Ejecutivo         | `org.view`, `approvals.view`, `approvals.decide`                                                                                                                                                               |
| Jefe de Cocina         | `org.view`, `approvals.view`                                                                                                                                                                                   |
| Controller / Costos    | `org.view`, `audit.view`, `approvals.view`, `approvals.decide`                                                                                                                                                 |
| Compras                | `org.view`, `approvals.view`                                                                                                                                                                                   |
| Cocinero / Operador    | `org.view`                                                                                                                                                                                                     |
| Auditor / Consulta     | `org.view`, `users.view`, `audit.view`, `audit.export`, `approvals.view`                                                                                                                                       |

## Dónde se prueba cada una (Fase 1)

_Lo que sigue no es texto de Soy: es el mapa de las pruebas, para controlarlas. Cada prueba lleva en su nombre el número de la tabla de arriba. pgTAP está en `supabase/tests/` y Playwright en `tests/e2e/`._

| #   | Prueba                                                    | pgTAP                                                    | Playwright (celular y computadora) |
| --- | --------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------- |
| 1   | Sin sesión no se consulta información privada             | `050_permissions` ("1. …")                               | `fase1.spec.ts` ("1. sin sesión…") |
| 2   | Cocinero abre la receta vigente pero no ve costos         | `060_roles_workflow` ("2. …", tabla de prueba)           | —                                  |
| 3   | Jefe de cocina crea borrador pero no publica sin permiso  | `060_roles_workflow` ("3. …")                            | —                                  |
| 4   | Gerente no edita fuera de su restaurante                  | `050_permissions` ("4. …")                               | —                                  |
| 5   | Dirección ve lo consolidado según permisos                | `050_permissions` ("5. …")                               | —                                  |
| 6   | Un cambio registra usuario, fecha, campo y valores        | `020_audit`, `050_permissions` (roles de quien cambia)   | —                                  |
| 7   | Una versión aprobada conserva su historia                 | `060_roles_workflow` ("7. …")                            | —                                  |
| 8   | Una cuenta desactivada pierde acceso                      | `080_accounts` ("8. …")                                  | `fase1.spec.ts` ("8 y A5…")        |
| 9   | Usuario con dos restaurantes opera solo en los suyos      | `050_permissions` ("9. …")                               | —                                  |
| 10  | Una cuenta técnica no supera sus permisos                 | `050_permissions` ("10. …")                              | —                                  |
| 11  | Una operación rechazada queda registrada                  | `060_roles_workflow` ("11. …")                           | —                                  |
| 12  | Una aprobación guarda identidad, fecha y decisión         | `060_roles_workflow` ("12. …")                           | —                                  |
| 13  | No se puede alterar el historial con operaciones normales | `020_audit`, `050_permissions` ("A3. …")                 | —                                  |
| A1  | Nadie se da permisos ni roles a sí mismo                  | `060_roles_workflow` ("A1. …")                           | —                                  |
| A2  | No se aprueba la propia solicitud                         | `060_roles_workflow` ("A2. …"), `080_accounts` ("A5. …") | `fase1.spec.ts` ("8 y A5…")        |
| A3  | Ni el superadmin altera `audit_events` desde la app       | `050_permissions` ("A3. …")                              | —                                  |
| A4  | Revocar un rol corta el acceso en la consulta siguiente   | `050_permissions` ("A4. …")                              | —                                  |
| A5  | Suspendido no entra; reactivado sí                        | `080_accounts` ("A5. …")                                 | `fase1.spec.ts` ("8 y A5…")        |
| A6  | Asignaciones con alcance incoherente rechazadas           | `040_identity`, `060_roles_workflow` ("A6. …")           | —                                  |
| A7  | 5 intentos fallidos bloquean y queda registrado           | `080_accounts` ("A7. …")                                 | `fase1.spec.ts` ("A7. …")          |
| A8  | Roles 1 a 4 y Controller no entran sin MFA                | `050_permissions` ("A8. …")                              | `fase1.spec.ts` ("A8. …")          |
| A9  | Todas las tablas tienen RLS (recorre el catálogo)         | `060_roles_workflow` ("A9. …")                           | —                                  |
| A10 | Tablero de usuarios en menos de 300 ms con 500 personas   | `080_accounts` ("A10. …")                                | `fase1.spec.ts` ("tablero…", axe)  |
