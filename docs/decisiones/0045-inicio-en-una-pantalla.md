# ADR-0045: Inicio en una pantalla

- **Fecha:** 2026-11-13
- **Estado:** aceptada por Joaco (plan aprobado el 2026-11-13).
- **Pedido:** Soy, `docs/prompts/2026-11-13-inicio-sin-scroll.md`, con el boceto aprobado en `docs/prompts/2026-11-13-boceto-inicio/`.
- **Sigue a:** ADR-0033 (tablero de calidad de datos) y ADR-0036 (rediseño, pantalla tipo A).

## Contexto

El Inicio no entraba en una pantalla. Tenía, uno debajo del otro:

- el título y la pregunta;
- los 4 KPIs;
- la comparación entre locales y las tareas;
- un gráfico de ancho completo;
- 4 tarjetas de ranking que casi siempre estaban vacías;
- los accesos a Usuarios, Roles e Historial.

Para ver todo había que hacer scroll, y el estado del local no se entendía en 5 segundos.

## Decisiones de Soy (2026-11-13)

- El Inicio **entra entero en 1440 × 900, sin scroll** (y en 1600 × 900 y 1920 × 1080).
- 4 KPIs arriba. Debajo, tres tarjetas compactas: confiabilidad del costo, cómo está cada local y tareas pendientes.
- **Un solo ranking con botones** en lugar de las 4 tarjetas.
- **6 accesos grandes** con su número del momento, en este orden: Recetas, Materias primas, Costos, Aprobaciones, Calidad y Reportes.
- Usuarios, Roles e Historial salen del Inicio, porque ya están en la barra lateral.
- No va «+ Nueva receta».
- **Regla nueva para lo que falta:** si falta más de la mitad, el indicador es Crítico (rojo); si falta la mitad o menos, Atención (amarillo); si no falta nada, Completo (verde); sin nada que medir, «Sin datos». **Una sola regla para todo el sistema.**

## Cómo se hizo

**No cambia la base.** Se usan las mismas funciones de antes: `getQuality`, `getHomeBoard`, `getQualityCompare`, `getInbox`, `getRecentImports` y `getRecalcStatus`.

### La regla única

- `missingState(missing, total)`, en `lib/metrics.ts`, decide el estado. Exactamente la mitad queda en Atención.
- La usan los KPIs (`Missing`, en el Inicio y en Calidad), la lista de indicadores de Calidad (antes, siempre amarilla), los accesos y el celular.
- `shortcutStates`, en `lib/home-shortcuts.ts`, arma la palabra y el estado de cada acceso con los conteos que el Inicio ya cargó.
- Si un rol no ve el número de un acceso (por ejemplo, el Jefe de Cocina no ve precios), el acceso dice «Abrir» en gris. Nunca «Al día».

### La pantalla en la computadora

- **`AppShell` tiene la opción `fill`** (solo el Inicio): en la computadora, la pantalla mide lo mismo que la ventana y la fila del medio ocupa el alto que queda. **No oculta nada:** si algo no entra, la página crece y la prueba lo detecta.
- **Encabezado.** El h1 es «Hola, {nombre} · {local}», con la línea «Datos al momento…» en 12 px. Su única acción es «Ver qué falta corregir». Los roles se ven en Mi cuenta.
- **Aviso «Requiere atención».** Va en una franja de 44 px que lleva a Calidad. Suma las solicitudes que esperan una decisión y el estado del recálculo, así que no agrega filas. En la computadora se corta en una línea; el texto completo queda en el nombre del enlace.
- **KPIs.** Tienen una variante compacta (`compact` en `Kpi` y `Metric`): «de N» va al lado del número.
- **Confiabilidad.** Son 5 filas con su nombre, una barra en los tonos fuertes de gráficos (ADR-0015) y la cantidad. Cada fila lleva a Costos filtrado por ese estado; «Sin costo» lleva a Calidad.
  - Se borró `ReliabilityChart`, que era el gráfico de Recharts.
  - La tabla «Ver los números» ya no hace falta, porque los números están escritos en cada fila.
- **Ranking** (`components/home/ranking.tsx`):
  - Los botones tienen `aria-pressed` y están dentro de un formulario `GET` (`?ranking=`).
    - Sin JavaScript, o antes de que cargue, la página vuelve con la lista elegida.
    - Con JavaScript, la lista cambia al instante y la elección queda anotada en la dirección.
  - Se descartó usar enlaces, porque `aria-pressed` no es válido en un enlace.
  - Las 4 listas llegan juntas en `getHomeBoard`, así que cambiar de lista no consulta nada.
  - Solo se ofrecen las secciones que la base habilita (`board.sections`).
- **Aprobaciones.**
  - Se cuenta lo que la persona puede decidir (`can_decide`), de toda su bandeja: es lo mismo que ve al entrar a Aprobaciones.
  - Se lee hasta 50 solicitudes; si llega a 50, dice «50 o más».
  - Antes, las tareas mostraban solo las solicitudes del recetario, con un límite de 20.
- **Medidas.**
  - Filas de 28 px y enlaces de 32 px en la computadora.
  - Los botones del ranking van en 12 px, el mínimo, para que entren en dos líneas.
  - En 1440 × 900 el contenido termina en 889 px, sobre 900.

### En el celular

Es para supervisar. Muestra:

- el aviso, como enlace;
- los KPIs de a 2;
- «Para decidir»: Aprobaciones con su estado y las 2 faltas más grandes;
- «Cómo está cada local».

No muestra el ranking, la confiabilidad ni los accesos grandes, porque los accesos están en la barra de abajo. Toda fila que se toca mide 44 px.

### El Inicio simple

Lo ve quien no tiene calidad de datos, como la Cocinera, y sigue como antes: sus roles y sus accesos. Como el h1 ahora es el saludo, la tarjeta se llama «Tus roles».

### Los roles, en Mi cuenta

El prompt daba por hecho que los roles se veían en Mi cuenta, pero no estaban ahí. Como salen del Inicio, Mi cuenta («Mis datos») suma la tarjeta «Tus roles», con los mismos datos que usaba el Inicio (`getUser` de la propia persona). Si no, nadie tendría dónde ver sus propios roles.

## Pruebas

- **Vitest, `home-shortcuts.test.ts` (10 pruebas):**
  - los bordes de la regla: la mitad es Atención, 1 de 1 es Crítico y 0 de 0 es «Sin datos»;
  - la palabra de cada acceso;
  - el acceso neutro;
  - el tope de la bandeja.
- **Playwright, `inicio.spec.ts`, en celular y computadora, con axe:**
  - sin scroll en 1440 × 900, 1600 × 900 y 1920 × 1080;
  - **las pruebas siguen la regla, no números fijos:** cada KPI lee «N» y «de M» de la pantalla y controla el color que corresponde (la regla está escrita de nuevo en la prueba, sin usar el código que prueba). En los 4 locales del seed tiene que aparecer al menos un Crítico, y la lista de Calidad sigue la misma regla;
  - un local de una marca nueva (la prueba crea la marca y el local y los cierra al terminar): sin recetas dice «Sin datos» y nunca «Al día» ni un %;
  - el ranking cambia con sus botones, `aria-pressed` acompaña y la elección sigue después de recargar;
  - los 6 accesos van en orden, con su palabra, y llevan a su pantalla;
  - no aparece «+ Nueva receta»;
  - el Jefe de Cocina no ve costos;
  - la Cocinera ve el Inicio simple;
  - en el celular no hay accesos grandes y todo lo que se toca mide 44 px o más.
- **Ajustadas, sin aflojarlas:** el ingreso de las pruebas (`login` y 9 lugares más) esperaba un h1 «Inicio». Ahora espera el h1 del saludo («Hola, …»), que solo existe en el Inicio.
- **Por qué la regla y no números fijos:** el seed cambió desde que se escribió el prompt (Pastas Centro ya no tiene «4 de 4 sin aprobar»), y en una corrida completa las pruebas anteriores cambian los números: Pastas Norte pasó de «6 de 11» a «11 de 16». Además, crean recetas para todo el grupo, que llegan a cualquier local nuevo. Por eso, en una corrida completa, el local «sin recetas» puede tener recetas: ahí la prueba controla la regla con sus números. El caso «Sin datos» queda siempre probado en Vitest (`missingState`, `metricView` y los accesos), y en Playwright cuando el local llega vacío.
- **`fase1` A8:** buscaba el rol «Gerente de Restaurante» en el Inicio. Ahora lo busca en Mi cuenta, después de la doble verificación: controla lo mismo.

## Excepción a design.md: controles más bajos en este panel

`design.md` pide controles de 36 a 40 px en la computadora. Para que el Inicio entre en una pantalla, en la computadora este panel usa:

- filas de lista de 28 px (`desk:min-h-7`): confiabilidad, locales, tareas y ranking;
- enlaces «Ver …» y botones del ranking de 32 px (`desk:min-h-8`).

Cumplen WCAG 2.5.8, que pide 24 px como mínimo. **En el celular todo sigue en 44 px.** La excepción vale solo para paneles de una pantalla como este. Joaco la aprobó el 2026-11-13 y quedó escrita en `.claude/rules/design.md`, «Formas y espacio».

## Riesgos y lo que queda

- **El margen en 1440 × 900 es chico:** 11 px. Las listas tienen tope (3 o 5 filas) y los nombres largos se cortan con «…», así que con más datos no crece. Lo que sí podría pasar de una pantalla:
  - una ventana más baja que 900 px;
  - la barra del navegador o el zoom, que achican el alto útil.
    En esos casos la página hace scroll, no esconde nada.
- **Comparar locales:** la tarjeta muestra hasta 5 locales, siempre con el elegido, y dice «5 de N» cuando hay más. El resto se ve en Calidad.
- **El aviso «Requiere atención» se corta en una línea en la computadora.** El texto completo está en Calidad y en el nombre accesible del enlace.
- **«Calidad · N datos por completar»** suma todos los indicadores que ve la persona. Es un número grande y queda siempre en Atención (no en Crítico), porque mezcla indicadores de distinto peso.
