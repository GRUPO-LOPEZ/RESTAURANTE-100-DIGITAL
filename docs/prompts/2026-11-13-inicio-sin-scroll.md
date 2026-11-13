# Inicio sin scroll: tablero en una pantalla (pedido de Soy, 2026-11-13)

Un solo prompt, un solo PR. Boceto aprobado: `docs/prompts/2026-11-13-boceto-inicio/` (y el enlace en su README).

## Decisiones de Soy

- El Inicio entra **entero en una pantalla de computadora de 1440 × 900, sin scroll**, con las mismas mejoras de aspecto de Recetas, Materias primas y Rubros.
- Los indicadores se ven como tablero: 4 KPIs arriba y, debajo, tarjetas compactas.
- Los accesos a otras pantallas son **botones grandes que muestran su número del momento** (por ejemplo, «4 · sin aprobar» o «Al día»), así se ve dónde hay algo para hacer.
- **No va «+ Nueva receta»** en el Inicio. La única acción del encabezado es «Ver qué falta corregir».
- **Un indicador pasa a rojo (Crítico) cuando falta más de la mitad;** con faltas menores queda en amarillo (Atención).
- Accesos, en este orden: Recetas, Materias primas, Costos, Aprobaciones, Calidad y Reportes. Usuarios, Roles e Historial salen del Inicio porque ya están en la barra lateral.

---

## Prompt (copiar en Claude Code)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md y el boceto aprobado en
docs/prompts/2026-11-13-boceto-inicio/ (Main.dc.html = computadora, Celular.dc.html = celular).
Tarea: rediseñar la pantalla de Inicio (app/page.tsx y components/home-board.tsx) para que entre
en una pantalla sin scroll. Rama: feat/inicio-sin-scroll. Entrá en modo plan y mostrame el plan
antes de tocar nada.

OBJETIVO
En una computadora de 1440 × 900 (y también en 1600 y 1920), el Inicio de quien ve la calidad de
datos entra completo sin scroll vertical. Es una pantalla tipo A (panel) de design.md: se entiende
el estado del recetario del local en 5 segundos.

QUÉ NO CAMBIA
- Los números salen de las mismas funciones de hoy (getQuality, getHomeBoard, getQualityCompare,
  getInbox, getRecentImports, getRecalcStatus). No es un cambio de base: si te parece que hace
  falta una migración o una función nueva, parás y me preguntás.
- El local sale del selector global de la barra superior. No se agrega ningún selector.
- Quien no ve la calidad de datos (por ejemplo, el cocinero) sigue viendo el Inicio simple de hoy,
  con sus roles y los accesos que le corresponden según getMenus().
- La interfaz oculta lo que el usuario no puede hacer: cada acceso y cada tarjeta se muestran
  solo si su menú o su sección está habilitada (menus.*, board.sections), igual que hoy.

DISPOSICIÓN EN COMPUTADORA (de arriba hacia abajo, ver Main.dc.html)
1. Encabezado en una línea: «Hola, {nombre} · {local}» y debajo, en 12 px, «Datos al momento: ...
   · N recetas · N preparaciones · N materias primas». A la derecha, solo el botón principal
   «Ver qué falta corregir». Sacar «+ Nueva receta» (no va). Sacar la línea larga de roles: los
   roles se ven en Mi cuenta.
   Sacar también el título «¿Qué tan completo y confiable está nuestro recetario?».
2. Aviso «Requiere atención» en una sola línea de 44 px (componente Attention, más compacto).
   Si además hay revisiones esperando, se suman al texto. El aviso de recálculo (Recalc), si
   aparece, va en esa misma franja y no agrega otra fila.
3. Fila de 4 KPIs con el componente Metric de hoy (Sin aprobar, Pendientes de revisión, Costo por
   corregir, Materias primas sin precio): número de 32 px, «de N», estado con palabra y
   «Ver cuáles». Regla de estado (decisión de Soy, 2026-11-13):
     - denominador 0 → «Sin datos» (nunca 0 % ni «Al día»);
     - faltan 0 → «Completo» (ok);
     - faltan más de la mitad del total → «Faltan N» en Crítico (bad);
     - faltan la mitad o menos → «Faltan N» en Atención (warn).
   La regla vive en una sola función (con su prueba de Vitest, incluidos los bordes: exactamente
   la mitad = Atención) y la usan los KPIs, los accesos y el celular. Si la misma regla se usa
   en Calidad (components/quality-board.tsx, Missing), se aplica igual ahí: una sola regla en
   todo el sistema.
4. Fila de 3 tarjetas de igual ancho, que ocupan el alto que queda:
   a. «¿Qué tan confiable es el costo?»: deja de ser el gráfico de ancho completo. Pasa a 5 filas
      compactas (estado, barra, cantidad), cada una enlaza a sus recetas. Barras con los tonos
      chart-strong (ADR-0015), el estado siempre con su nombre. «Ver los números» abajo.
   b. «Cómo está cada local»: el local elegido en negrita y los demás como enlace, con barra y %.
      «Comparar los locales» abajo. Con un solo local, la tarjeta no se muestra y las otras dos
      ocupan el ancho.
   c. «Tareas pendientes»: lo que más falta corregir (hasta 3, con su número), una fila
      «Revisiones esperando decisión» con estado (Al día / N esperan), la última importación
      en una línea de 12 px y «Ver las aprobaciones» abajo.
5. Fila de abajo, de alto fijo (alrededor de 236 px):
   a. Izquierda (5/12): UN solo ranking con botones visibles (segmented, components/ui/segmented.tsx;
      CLAUDE.md, «Edición directa», pocas opciones = botones): «Mayor costo por porción»,
      «Materias primas que más pesan», «Afectadas por precio», «Lo más usado». Reemplaza a las
      4 tarjetas de hoy. Muestra hasta 5 filas (nombre y valor, enlazadas). Sin filas: «Sin datos»
      y el texto vacío de hoy de esa lista. La opción elegida puede vivir en la URL
      (?ranking=...) para que no haga falta JavaScript del lado del cliente.
      Solo se ofrecen los botones de las secciones habilitadas (board.sections).
   b. Derecha (7/12): 6 accesos grandes en grilla de 3 × 2: Recetas, Materias primas, Costos,
      Aprobaciones, Calidad y Reportes, en ese orden. Cada uno lleva su ícono Lucide en un
      cuadrado nav-active, el nombre en 16 px semibold y una línea de estado con su número del
      momento, siempre con palabra:
        - Recetas: «N sin aprobar» o «Al día» (ok) con «N recetas».
        - Materias primas: «N sin precio» o «Al día».
        - Costos: «N por corregir» o «Al día».
        (warn o bad según la misma regla de los KPIs)
        - Aprobaciones: «N esperan tu decisión» (info) o «Al día».
        - Calidad: «N datos por completar» (warn) o «Al día».
        - Reportes: sin número, chip neutro «Informes».
      Los números salen de lo que ya se cargó para los KPIs: no se agregan consultas nuevas.
      Usuarios, Roles e Historial dejan de estar en el Inicio (siguen en la barra lateral).

LÍMITES DE ESPACIO
- Nada de max-width global; márgenes del AppShell. Espacios de 16 px entre bloques.
- Las listas largas se cortan (hasta 3 o 5 filas) con su enlace «Ver ...»: la pantalla no crece
  con los datos. Probalo con el seed y con muchos datos (por ejemplo, 50 recetas y 4 locales).
- En 1440 × 900 no puede haber scroll vertical en el área principal. Si con alguna combinación
  real no entra, me avisás antes de achicar letras por debajo de los mínimos de design.md.

CELULAR (menos de 800 px, ver Celular.dc.html)
Es para supervisar: aviso «Requiere atención» como enlace, los 4 KPIs de a 2, una tarjeta
«Para decidir» (aprobaciones con su estado y lo que más falta corregir) y «Costo confiable por
local». El ranking, la confiabilidad y los accesos grandes no se muestran (la barra inferior ya da
los accesos). Ahí sí se puede hacer scroll. Controles de 44 px como mínimo.

PRUEBAS
- Playwright (tests/e2e/, ajustar el spec del Inicio que exista o crear inicio.spec.ts), con axe:
  * en 1440 × 900, 1600 × 900 y 1920 × 1080: el área principal no tiene scroll vertical
    (scrollHeight <= clientHeight), con el seed;
  * con un local sin recetas: los KPIs dicen «Sin datos» y nunca 0 % ni «Al día»;
  * con el seed (4 de 4 sin aprobar): el KPI dice «Faltan 4» como Crítico;
  * el ranking cambia de lista con sus botones y aria-pressed refleja la elección;
  * cada acceso muestra su estado con palabra y lleva a su pantalla;
  * no aparece «+ Nueva receta»;
  * un rol sin calidad de datos (cocinero) ve el Inicio simple, sin el tablero;
  * celular: no hay accesos grandes y los controles miden 44 px o más.
- Vitest para la función que arma el estado de cada acceso (números → palabra y estado).
- Las pruebas que se rompan porque buscaban cosas que ya no están (las 4 tarjetas de ranking, los
  accesos a Usuarios/Roles/Historial, el título largo) se ajustan para controlar lo nuevo.
  No se borran ni se aflojan.
- Corré todo (npm run test). Recordá: no recrear la base mientras corre Playwright.

ENTREGA
- Revisión de ui-reviewer (y security-auditor si cambiaste qué se muestra a cada rol).
- Capturas reales en 1440, 1600, 1920 y celular, con el seed. Guardalas como PNG en
  docs/capturas/inicio-sin-scroll/ y commitealas en el PR: Soy las revisa desde GitHub.
- ADR nuevo en docs/decisiones/ (siguiente número libre): «Inicio en una pantalla».
- docs/modulos/: lista de cambios para Soy, corta y en simple, como la 08.
- docs/estado.md actualizado (y corregí el encabezado, que todavía dice que la ficha de materia
  prima está «en curso»: ya se fusionó en el PR #61).
- PR chico con resumen en simple. Commit: «feat(inicio): tablero en una pantalla sin scroll».
```
