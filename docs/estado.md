# Estado del proyecto

_Última actualización: 2026-10-21. Fase 1 construida en local: M1 a M9, pantallas y las 23 pruebas. Falta subirla a GitHub y que Soy la valide._

## Resumen para Soy: la Fase 1 está construida

**Qué se hizo:** el sistema ya tiene la base de todo lo que viene. Sabe **quién es cada persona, qué puede hacer y dónde**, y **registra cada cambio para siempre**.

- **Ingreso:**
  - Se entra solo por invitación, con correo y contraseña.
  - Los roles de los niveles 1 a 4 y Controller además usan una **app de doble verificación** en el celular.
  - **Cinco intentos fallidos bloquean la cuenta 10 minutos.** Un administrador la puede liberar antes.
- **Permisos por lugar:**
  - Cada persona ve y hace solo lo de su grupo, su marca o su local.
  - El cocinero no ve costos.
  - Nadie se puede dar permisos a sí mismo.
  - Los roles que aprueban cosas los tiene que aprobar otra persona.
  - El Superadministrador puede **pedir** cualquier rol, pero lo aprueba Dirección General.
- **Aprobaciones:** hay una bandeja para aprobar o rechazar cambios. Nadie aprueba lo que pidió, y quien bloquea una cuenta no puede reactivarla.
- **Cuentas:** desactivar una cuenta la saca al instante y cierra todas sus sesiones. Para reactivarla hace falta la aprobación de otra persona.
- **Historial:** se ve quién cambió qué, cuándo y por qué. Es inalterable y está sellado cada hora.
- **Pantallas:**
  - ingreso;
  - doble verificación;
  - inicio;
  - **tablero de usuarios** ("¿Quién tiene acceso y dónde?");
  - ficha de cada persona;
  - invitar;
  - aprobaciones;
  - historial.

  Todas están en español, pensadas primero para el celular y con los colores pastel.

**Cómo está probado (en la computadora de desarrollo, 2026-10-21):**

| Prueba                                                                   | Resultado                                                   |
| ------------------------------------------------------------------------ | ----------------------------------------------------------- |
| Base de datos (pgTAP)                                                    | ✅ 520 de 520                                               |
| Lógica y configuración (Vitest)                                          | ✅ 73 de 73                                                 |
| Pantallas en celular y computadora, con accesibilidad (Playwright + axe) | ✅ 28 de 28                                                 |
| Lint, formato, tipos y compilación                                       | ✅                                                          |
| Las **13 pruebas obligatorias y las 10 adicionales** del Módulo Maestro  | ✅ todas, en local (mapa en `docs/modulos/00-identidad.md`) |

**Revisiones:** cada paso pasó por los revisores de base de datos, seguridad y diseño, varias veces. Los graves que encontraron se corrigieron.

- **Seguridad:** en la primera ronda de M6 y M7 encontró dos huecos graves en cómo el Superadministrador daba y quitaba roles. Están cerrados.
- **Base:** encontró consultas que con mucho volumen tardaban segundos. Ahora tardan milisegundos.
- **Diseño:** pidió una pantalla de error, una página de "no encontrada" en español y un historial en lenguaje simple. Las tres están hechas.

**Qué falta para cerrar la Fase 1:**

1. Subir las ramas a GitHub y ver las pruebas en verde allá (es requisito). Necesita la confirmación de Joaco.
2. Que usted recorra la **checklist de validación** (sección 14 del prompt maestro) con los usuarios de prueba.
3. Las decisiones que están abajo.

## Preguntas para Joaco (no frenan el cierre en local, pero sí la salida a producción)

1. ¿Un superadmin le puede quitar el rol a otro superadmin sin aprobación, siempre que quede uno? Hoy sí.
2. ¿Un local cerrado o borrado deja de dar permisos a quienes tenían rol ahí? Hoy no.
3. Nadie puede desactivar a una persona de Dirección General, ni cambiar los permisos de ese rol, salvo con una migración documentada. ¿Está bien?
4. Controller puede aprobar que se le dé a alguien un rol que aprueba cosas (ADR-0008). ¿Se mantiene?
5. ¿Quién aprueba una reactivación? Hoy, otra persona con permiso sobre esa cuenta. ¿Tiene que ser alguien de igual o mayor alcance que quien la desactivó?
6. Ante el bloqueo a propósito de una cuenta (alguien falla 5 veces cada 10 minutos), ¿dejamos entrar igual a quien pone la contraseña y el código de doble verificación correctos?
7. El tablero de usuarios muestra el **estado actual**, sin comparar con un período anterior. ¿Lo aceptamos como excepción a la regla de tableros?

Riesgos técnicos antes de producción: ADR-0014, sección "Riesgos que quedan".

## Dónde está cada cosa

| Paso                                                | Rama / commit                                |
| --------------------------------------------------- | -------------------------------------------- |
| M5: permisos y lectura por la API                   | `feat/fase-1-permisos` · `2d49eaa`           |
| M6 y M7: roles, aprobaciones, registro de seguridad | `feat/fase-1-roles-aprobaciones` · `607ebd4` |
| M8 y M9, pantallas, Edge Functions, CI              | `feat/fase-1-cuentas-pantallas`              |

Las ramas están apiladas una sobre la otra y **todavía no están en GitHub**.

**Notas técnicas:**

- `.env.example` tiene la clave pública (publishable) de Supabase local. La CI verifica que coincida con la suya.
- Supabase local prende las Edge Functions (`auth-login` e `invite-user`), el hook de ingreso y la doble verificación TOTP.
- Playwright recrea la base antes de correr.
- Usuarios de prueba: `<rol>@ejemplo.test` con la contraseña `Demo-Local-2026!`. Los roles con doble verificación usan el secreto TOTP ficticio `JBSWY3DPEHPK3PXP`.

## Resumen para Soy: personas, roles y permisos (M4)

**Qué se hizo:** la base ya conoce a las personas y qué puede hacer cada una.

- Están cargados **los 10 roles de su Módulo Maestro** y los permisos de esta fase. Cada rol tiene su lista de permisos (la matriz que aprobó Joaco está en `docs/modulos/00-identidad.md`).
- **Llevan doble verificación (MFA):** Superadministrador, Dirección General, Director de Marca, Gerente y Controller. A esos roles nadie les puede sacar el MFA.
- Cada persona tiene un rol **en un lugar**: todo el grupo, una marca o un local. La base no deja dar un local que no es de esa marca, ni dar un rol a alguien que no es del grupo o que tiene la cuenta bloqueada.
- **Nada se borra:** sacar un rol deja quién lo sacó, cuándo y por qué. Una persona no se borra, se bloquea.
- Para probar hay **una persona inventada por rol**, un gerente de dos locales y una cuenta técnica para los agentes del futuro. Ya se puede entrar con ellas en la computadora de desarrollo.
- Todo sigue **cerrado**: ninguna pantalla puede leer estos datos hasta que existan las reglas de acceso (M5).

**Cómo está probado:** 285 pruebas de base de datos en verde. Pasó por los revisores de base de datos y de seguridad: ninguno encontró problemas graves, y los puntos que se podían arreglar ahora ya se arreglaron. El resto quedó anotado como requisito de M5, M6 y M8.

**Preguntas para usted:**

- ~~**P15:** ¿cómo se pasa un local a otra marca?~~ Resuelta por Joaco: se crea el local nuevo y se cierra el viejo, que conserva su historia. Si hiciera falta, se puede cambiar más adelante (ADR-0007).
- ~~**P16:** las 10 pruebas adicionales.~~ Recibidas; la 6 (alcance incoherente) ya pasa.
- ~~**P5:** cómo se registran los ingresos.~~ Resuelta por Joaco (ADR-0010). El ingreso pasa por una función nuestra que anota y cuenta los intentos, y una cuenta bloqueada no recibe sesión. Funciona con el plan gratis o Pro.
- ~~**P18:** duración del bloqueo.~~ Resuelta por Joaco: dura 10 minutos y se libera solo. Un administrador puede liberarlo antes, y eso queda registrado.
- ~~**P17:** operación rechazada.~~ Resuelta por Joaco: quedan registradas las aprobaciones rechazadas y los intentos sin permiso en las funciones importantes (ADR-0009).
- ~~**P7:** ¿qué cambios necesitan aprobación?~~ Resuelta por Joaco (ADR-0008). Piden aprobación de otra persona:
  - dar roles que aprueban;
  - dar el rol Superadministrador;
  - cambiar los permisos de los roles;
  - pasar un local a otra marca;
  - reactivar una cuenta.

  Bloquear una cuenta es inmediato.

**Estado:** rama `feat/fase-1-identidad` (sale de `feat/fase-1-organizacion`). Es un **adelanto**: no se suma a `main` sin su aprobación.

| Prueba                                        | Resultado                                         |
| --------------------------------------------- | ------------------------------------------------- |
| pgTAP (`000` a `040`)                         | ✅ 285 de 285                                     |
| `npx supabase db reset` (con el seed)         | ✅                                                |
| Ingreso local con una persona del seed (Auth) | ✅ entra; contraseña mala y alta libre rechazadas |

Revisiones de M4:

- **`db-reviewer`:** sin hallazgos graves. Corregidos en la misma migración:
  - asignación duplicada;
  - carrera entre dar un rol y sacar la membresía;
  - reglas entre tablas (permisos y roles borrados, cuentas bloqueadas);
  - vigencias que se extendían;
  - pruebas faltantes;
  - el ingreso local apagado por `config.toml`.

  Anotados: el traspaso (P15), la sincronización del correo (M8) y SSO.

- **`security-auditor`:** apto. Corregidos:
  - los códigos de permisos y roles, que se podían renombrar (era una vía para darse más permisos);
  - el MFA de los roles del catálogo, que se podía bajar;
  - la guarda del seed, ahora más fuerte.

  Pasaron a requisitos de M5, M6 y M8: separación de funciones (cuentas títere, superadmin que edita la matriz), reglas sobre a quién se puede bloquear, comparación por permisos y no por nivel, y la configuración de Auth en los paneles remotos.

## Resumen para Soy: estructura del grupo (M3)

**Qué se hizo:** la base ya conoce cómo está armado el grupo: **grupo → marcas → restaurantes → áreas** (cocina, salón, depósito). Para probar hay datos inventados: "Grupo Demo", 3 marcas y 4 locales.

- Un local **no puede quedar en una marca de otro grupo**, ni un área en un local de otro grupo: la base lo rechaza.
- Por decisión de Joaco:
  - **no se puede borrar algo que todavía tiene cosas vigentes adentro** (una marca con locales abiertos, por ejemplo);
  - **un local no se puede mover a otra marca con una edición común**. Va a haber un trámite que pide motivo y queda en el historial.
- Cada alta, cambio o borrado queda en el historial, **con el local, la marca y el grupo correctos**, aunque alguien intente cargar datos engañosos.
- Todo sigue **cerrado**: ninguna pantalla puede leer estos datos hasta que existan los permisos (ADR-0005).

**Cómo está probado:** 207 pruebas de base de datos en verde, revisadas por los revisores de base de datos y de seguridad (sin hallazgos graves; lo que encontraron está corregido).

**Preguntas para usted:** P13 (¿se puede editar algo borrado?), P14 (¿alcanzan los estados "operando" y "cerrado"?) y P10 (¿qué datos lleva cada local: dirección, CUIT…?).

**Estado:** rama `feat/fase-1-organizacion` (sale de `feat/fase-1-base-auditoria`). Es un **adelanto**: no se suma a `main` sin su aprobación.

| Prueba                                | Resultado     |
| ------------------------------------- | ------------- |
| Lint, formato y tipos                 | ✅            |
| Vitest                                | ✅ 63 de 63   |
| pgTAP (`000`, `010`, `020`, `030`)    | ✅ 207 de 207 |
| Playwright + axe                      | ✅ 10 de 10   |
| `npx supabase db reset` (con el seed) | ✅            |

Revisiones de M3: `db-reviewer` sin graves (2 medias que eran reglas de negocio, ya decididas por Joaco, y 5 menores corregidas). `security-auditor` apto (3 medias latentes: alcance falsificable en la auditoría, ya corregido; riesgos del ADR-0005, ya documentados; permisos por defecto en `public`, ya cortados; y 4 menores corregidas).

## Adelanto de la Fase 1: base común y auditoría (M1 y M2)

**Qué se hizo:** se construyó el **historial inalterable** del sistema, la parte de la Fase 1 que no depende de su documento:

- Cada cambio que se haga en cualquier tabla va a quedar registrado: **quién, cuándo, qué había antes, qué quedó y por qué**.
- **Nadie puede borrar ni cambiar ese historial**, ni siquiera un administrador. Y si alguien con la contraseña máxima de la base lo intentara, unos **sellos** (huellas digitales encadenadas) lo detectan. Hay una prueba que simula ese ataque.
- Las contraseñas, tokens y claves **nunca** quedan en el historial, aunque vengan escondidos dentro de otros datos.
- Los datos de "quién creó o cambió esto" los pone siempre la base, nunca la aplicación, así que no se pueden falsear.

**Cómo está probado:** 156 pruebas de base de datos en verde, revisadas por los revisores de base de datos y de seguridad (sin hallazgos graves; todo lo que encontraron ya está corregido).

**Qué falta:** su Módulo Maestro de Usuarios, para los roles, permisos y las 13 pruebas. Y una pregunta nueva (P13): ¿se puede editar algo que ya está borrado, o hay que restaurarlo primero?

**Estado:** rama `feat/fase-1-base-auditoria`. Es un **adelanto**: no se suma a `main` hasta que usted apruebe la Fase 0 y este avance.

### Pruebas de esta tarea (local, 2026-10-20)

| Prueba                               | Resultado     |
| ------------------------------------ | ------------- |
| Lint, formato y tipos                | ✅            |
| Vitest                               | ✅ 63 de 63   |
| pgTAP (`000`, `010`, `020`)          | ✅ 156 de 156 |
| Playwright + axe                     | ✅ 10 de 10   |
| `npx supabase db reset` (desde cero) | ✅            |

Revisiones: `db-reviewer` sin graves (4 medias y 6 menores, corregidas o anotadas), `security-auditor` apto (4 medias y 8 menores, corregidas o anotadas en ADR-0006). Dos errores reales los encontraron las propias pruebas antes de commitear: los permisos por defecto por esquema no cerraban nada, y `postgres` sin herencia no podía conectar el trigger de auditoría.

### Pendientes de la Fase 1 que salen de esta tarea

- Tarea programada que selle la auditoría cada hora, y exportación externa con la última huella (ADR-0006).
- `audit.authentication_security_events` (diseño en ADR-0009 y ADR-0010).
- La lectura de la auditoría tiene que ocultar costos a quien no tenga `costing.view_costs` (ADR-0006).
- P13 (resuelta): un registro borrado no se edita, primero se restaura. Se implementa junto con M5.

## Fase 0 (mergeada en `main`, PR #1)

**Qué se hizo:** se preparó el "taller" donde se va a construir el sistema. Todavía no hay pantallas para los restaurantes; eso es a propósito. Quedó listo:

- **Las reglas del proyecto adentro del código.** Claude las lee solo en cada sesión: principios, base de datos, seguridad, diseño y agentes.
- **Candados automáticos.** Claude no puede leer claves, no puede tocar producción, no puede forzar cambios en GitHub ni editar cambios de base de datos ya guardados. Cada candado tiene su prueba.
- **La base de datos local**, ordenada en 12 temas (identidad, organización, auditoría, recetas, costos, etc.), todavía vacía y **cerrada por defecto**: nadie entra a nada hasta que se le dé permiso explícito.
- **El estilo visual:** colores pastel, letra Inter, botones grandes para el celular. Está controlado por pruebas automáticas: si alguien usa un color fuera de la paleta o con poco contraste, la prueba falla.
- **Pruebas automáticas que corren en cada cambio** (en GitHub, una vez que se suba).
- **El plan detallado de la Fase 1** (usuarios, permisos e historial), ya revisado por los revisores de base de datos y de seguridad.

**Qué falta para arrancar la Fase 1:** el documento del Módulo Maestro de Usuarios (roles, niveles, permisos y las 13 pruebas). Sin eso no se puede cerrar la Fase 1.

**Riesgos:** ninguno grave en lo construido. Los riesgos de diseño que encontraron los revisores ya están corregidos en el plan de la Fase 1.

## Hecho

Rama `chore/fase-0-entorno`, mergeada en `main` con el PR #1. Falta confirmar si GitHub Actions dio verde en ese PR.

| Paso del prompt de arranque                   | Estado  | Dónde                                                                                  |
| --------------------------------------------- | ------- | -------------------------------------------------------------------------------------- |
| 1. Estructura del repositorio (sección 4)     | ✅      | raíz del repo (ADR-0001)                                                               |
| 2. `CLAUDE.md` y `.claude/rules/`             | ✅      | `CLAUDE.md`, `.claude/rules/{database,security,design,agents}.md`                      |
| 3. Permisos y hooks                           | ✅      | `.claude/settings.json`, `.claude/hooks/` (guardián, migraciones, formato, pre-commit) |
| 4. Subagentes revisores y skills              | ✅      | `.claude/agents/`, `.claude/skills/{nueva-tabla,nuevo-modulo}`                         |
| 5. Next.js + TS strict + Tailwind + shadcn/ui | ✅      | Next 16.4, Tailwind 4 (ADR-0002), tokens en `app/globals.css`                          |
| 6. Supabase local, pgTAP, Playwright, CI      | ✅ / ⚠️ | Todo corre en local. **CI escrito, sin verificar en GitHub** (falta subir la rama).    |
| 7. Plan de la Fase 1                          | ✅      | `docs/fases/fase-1-plan.md`                                                            |

### Pruebas (corridas en local el 2026-10-20, resultado literal)

| Prueba                                          | Resultado                         |
| ----------------------------------------------- | --------------------------------- |
| `npm run lint`                                  | ✅ sin errores ni advertencias    |
| `npm run format:check`                          | ✅                                |
| `npm run typecheck`                             | ✅                                |
| Vitest (hooks + contraste de la paleta)         | ✅ 63 de 63                       |
| `npx supabase db reset`                         | ✅ aplica la migración desde cero |
| pgTAP (`npx supabase test db`)                  | ✅ 60 de 60                       |
| Playwright + axe (celular Pixel 7 y escritorio) | ✅ 10 de 10                       |
| `npm audit --omit=dev`                          | ✅ 0 vulnerabilidades             |

### Revisiones de los subagentes

- **ui-reviewer:** aprobado con cambios. Corregidos: contraste del hover del botón, `link` sin 44 px, pruebas del botón (tamaño y foco), tamaños, pesos y radios fuera de la escala, pares de contraste nuevos y aviso sobre componentes nuevos de shadcn en `design.md`.
- **db-reviewer:** Fase 0 sin hallazgos graves. Prueba de humo ampliada (12 esquemas × 3 roles). Sus 2 graves y 9 medios del diseño de la Fase 1, corregidos en el plan y en la skill `nueva-tabla`.
- **security-auditor:** Fase 0 apta. Corregidos los 9 hallazgos del guardián y los permisos (17 ataques nuevos en las pruebas), `format.mjs` sin shell, `shadcn` movido a dependencias de desarrollo y control de migraciones inmutables en CI. Sus 2 graves de diseño de la Fase 1 (escalada en asignación de roles y suplantación de cuentas técnicas), corregidos en el plan.

### Control de reglas (paso 2)

Se compararon 110 reglas clave del prompt maestro contra `CLAUDE.md` + `.claude/rules/` + `settings.json`. Faltaban 2, que ya se agregaron: "Joaco accede como miembro" y la nota pendiente sobre marcas, locales y otros negocios.

## Falta

_Actualizado el 2026-10-20._

**Hecho fuera de la Fase 1:** conector MCP de Supabase solo contra la base local, en solo lectura (ADR-0011, rama `chore/mcp-supabase-local`). Pendiente: el MCP de GitHub.

1. **Construir M5, M6 y M8** y las pantallas de ingreso, "sin acceso" y usuarios. No dependen de nadie.
2. **M7 (aprobaciones)**: P7 y P17 ya están resueltas (ADR-0008 y ADR-0009).
3. Preguntas de la Fase 1: **todas resueltas**. P10, P13 y P14 se implementan junto con M5. Para producción falta la lista real de marcas y locales.
4. **Subir las 3 ramas de adelanto** (M1–M2, M3, M4) como PRs y verificar GitHub Actions en verde. Necesita la confirmación de Joaco para el `git push`.
5. **Supabase remoto:**
   - Soy ya creó la organización y Joaco es administrador.
   - Faltan los proyectos `grupo-lf-staging` y `grupo-lf-prod` (región São Paulo), los ajustes de Auth en el panel, y el flujo de GitHub Actions con sus secretos. Lo hace Joaco desde el panel, nunca Claude Code.
   - Pendiente también una guía escrita para Soy.
6. Vercel, respaldos y exportación semanal del historial (Soy).
7. **Proteger `main` en GitHub: postergado por decisión de Joaco (2026-10-20).** Mientras tanto se sigue la regla igual, por costumbre:
   - nada entra a `main` sin un PR aprobado por Soy;
   - Claude Code nunca hace push a `main`;
   - el push forzado está bloqueado por el guardián.

   Se retoma antes de pasar a producción.

8. Texto completo del Módulo Maestro y tabla de fases (sección 12) de Soy.

## Bloqueado

- **Fase 1:** necesita el Módulo Maestro de Usuarios de Soy (`docs/modulos/00-identidad.md` está vacío, con un aviso de pendiente).
- **Tabla de fases** (sección 12 del prompt maestro): no llegó completa.

## Riesgos y avisos conocidos

- `npm audit` completo (con desarrollo) marca 5 vulnerabilidades altas de `braces`, en el linter de Next (`eslint-config-next`). No afecta lo que llega al usuario. El "arreglo" automático baja el linter a una versión vieja; se espera el arreglo de Next y lo trae Dependabot.
- npm 11 avisa que `unrs-resolver` tiene un script de instalación no aprobado. ESLint funciona sin ese script.
- El guardián de Claude Code es una ayuda, no la única barrera. La defensa real es que **en esta máquina nunca haya claves ni tokens de staging o producción**, y que nunca se haga `supabase link`.
- Docker tiene unos 3,9 GB de RAM; Supabase local usa alrededor de 1,1 GB. Si se pone lento, ver ADR-0001.

## Prueba de restauración mensual

Todavía no aplica: no hay producción.
