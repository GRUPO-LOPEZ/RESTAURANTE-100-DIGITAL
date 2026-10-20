# Estado del proyecto

_Última actualización: 2026-10-20, cierre de la sesión de la Fase 0._

## Resumen para Soy

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

Rama `chore/fase-0-entorno` (todavía sin subir a GitHub).

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

1. **Subir la rama y abrir el PR** para verificar GitHub Actions en verde. Necesita la confirmación de Joaco para el `git push`.
2. **Proteger `main` en GitHub:** exigir PR, pruebas en verde y aprobación, y prohibir el push forzado. Se hace desde la cuenta de Soy.
3. Responder las preguntas bloqueantes de la Fase 1 (P1, P2, P4, P6 y P7 en `docs/fases/fase-1-plan.md`).
4. Decidir cómo llega la app a los datos (ADR-0005, antes de M3).

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
