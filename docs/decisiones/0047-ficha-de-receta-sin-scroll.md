# ADR-0047: Ficha de receta en una pantalla, con la planilla como única parte con scroll

- **Fecha:** 2026-11-14
- **Estado:** plan aprobado por Joaco el 2026-11-14. Falta la corrida con la base y la revisión de los subagentes.
- **Pedido:** Soy, `docs/prompts/2026-11-13-fichas-sin-scroll.md` (Prompt 2), boceto `docs/prompts/2026-11-13-boceto-fichas-sin-scroll/FichaRecetaSinScroll.dc.html`.
- **Sigue a:** ADR-0042 (ficha única de receta) y ADR-0046 (el patrón de pantallas de carga sin scroll).

## Contexto

La ficha única de receta (ADR-0042) era una página larga, con un índice de botones y 7 secciones apiladas. Soy pidió que entre en 1440 × 900 sin scroll de página, con el patrón del ADR-0046. La única parte con scroll propio es la planilla de ingredientes, como en una hoja de cálculo.

## Decisiones

### Disposición

- **Encabezado en una línea** (`AppShell` con `back`, `meta` y `actions`):
  - «← Recetas», el nombre (h1 de 20 px) y «código · rubro · Plato o Preparación»;
  - los chips Vigente vN / Borrador vN / En revisión vN, más Archivada y Variante;
  - a la derecha, «Ficha de cocina» y «Escalar» (solo con una versión vigente).
  - La aclaración «la vigente sigue en las cocinas hasta que se publique» pasó a un tooltip (ⓘ) al lado de los chips.
- **Franja de una línea:** en revisión, violeta (`Notice status="review"`, estado nuevo con los tokens `review`), con quién pidió la versión, cuándo y su motivo. Esos datos salen de `workflow.inbox` (`getInbox`), sin migración. Si no se puede leer la solicitud, la franja dice solo la versión. Si la revisión volvió (rechazada o retirada), la franja es amarilla.
- **4 indicadores** (`sheetKpis` en `lib/recipe-sheet.ts`, con Vitest):
  - Plato: Costo total · Costo por porción · Peso total · Porciones.
  - Preparación: Costo total · Costo por kg neto · Peso bruto → neto · Rendimiento.
  - Sin dato: «—» y el motivo, nunca un número supuesto. Si falta el costo de una fila, el total queda vacío; el boceto mostraba una suma parcial, y eso no se hizo.
  - **Quien no ve costos nunca ve dinero:** en lugar de los dos de plata, «Tiempo total» e «Ingredientes con peso» (N de M, con la regla única de lo que falta). Confirmado por Joaco el 2026-11-14.
  - Las `Metric` que había debajo de la planilla y en «Rendimiento» se fueron: no se repiten.
- **Dos columnas** `minmax(0,1fr) 300px`, que ocupan el alto que queda (fila `minmax(0,1fr)`).
  - **Ninguna de las dos impone su alto.** `AppShell fill` pone un alto _mínimo_ (el de la ventana): lo que no se achica estira la página. Por eso:
    - la planilla tiene `height: 0` y `flex: 1 1 0px`. Con `flex-1` (base `0%`) el navegador tomaba el alto de la tabla igual, porque una base en porcentaje dentro de un alto indefinido se trata como «contenido»;
    - la columna derecha va en una capa `absolute inset-0` dentro de su celda, y el procedimiento se queda con lo que sobra.
  - **Planilla:**
    - **El scroll:** el encabezado y el total son `sticky` dentro de un contenedor con `overflow: auto`.
    - **El foco:** `scroll-padding` deja a la vista la fila que recibe el foco con el teclado.
    - **El total** lleva «Completo» o «Incompleto: falta N dato» (`totalState`).
    - **Columnas:**
      - cada escala es una sola columna, «Hacer [4]» con el número editable en su encabezado y, debajo, el peso y el costo en dos renglones de 12 px. Si faltan los dos, un solo «—» con los dos motivos (`Missing compact`, 24 px);
      - salió la columna «#»; el número de fila sigue en los nombres de los campos («Código, fila 11»);
      - los títulos se acortaron: «$ por kg o l», «Costo», «% $» y «% peso», con su nombre completo en `abbr`;
      - la medida muestra la abreviatura («g», «kg», «cda»), con el nombre completo al pasar el mouse: «Gramo (g)» no entra en la columna;
      - anchos mínimos: Código 140 px (entra «DEMO-ING-001»), Ingrediente 144 y Medida 88. **Sin dinero entra en 1440.**
    - **Con dinero** la planilla necesita unos 1080 px: en 1440 y 1600 se desplaza de costado dentro de su tarjeta (296 y 136 px), nunca la página. **Código e Ingrediente quedan fijos a la izquierda** (decisión de Joaco del 2026-11-14), así nunca se pierde de qué fila es cada número. En 1920 entra entera.
    - **Autocompletar:**
      - la lista de sugerencias sigue al campo cuando se desplaza cualquier contenedor, porque escucha el `scroll` en captura;
      - la búsqueda depende solo del texto buscado: antes, cada desplazamiento la reiniciaba y con la planilla moviéndose quedaba en «Buscando…»;
      - va por una ruta GET propia (`/recetas/buscar-componentes`, ver «Velocidad»).
    - **Revisión:** la fila cambiada va en fondo `review` con «antes 380 g» o «Nueva» (`reviewMark`, desde `getVersionDiff`).
  - **Derecha** (tarjetas de 12 px de margen, controles de 32 px):
    - **Datos generales:** «Editar datos» en el título; la miniatura de fotos (`PhotoCarousel compact`, 96 × 72, con ‹ › y «+» encima; sin fotos, la miniatura vacía es «Agregar foto»), el rubro (editable) y el alcance.
    - **Rendimiento:** en la computadora, solo el campo (peso de la porción, o peso neto y unidad): las porciones, el peso bruto y el rendimiento están en los indicadores y no se repiten. En el celular, con su frase.
    - **Procedimiento:** «Editar los N pasos» en el título; los pasos que entran en el alto que queda, una línea cada uno. Los que no entran pasan a una segunda columna oculta (`flex-col flex-wrap overflow-hidden`): nunca se ve un paso cortado a la mitad, sin medir con JavaScript. Su tooltip pasó a la descripción del panel, para que el título entre en una línea.
    - **El resumen:** filas de una línea. Alérgenos: el primero que contiene y «+N»; si no contiene ninguno, «N puede contener» o «Sin verificar»; la lista entera en «Ver». Dónde se usa y Versiones, cada uno con su «Ver».
- **Los datos generales y los pasos se editan en un panel lateral sobre el mismo borrador:** lo cambiado cuenta en la barra y se guarda junto.
  - Datos: son 10 campos y en 300 px entran 2.
  - Pasos: cada paso tiene 6 campos, más la capacidad del equipo y de qué pasos depende. Una tarjeta con su propio scroll sería una segunda zona con scroll, y Soy pidió una sola. El panel reutiliza `StepCard` tal cual.
  - Al lado de «Editar datos» se avisa cuántos cambios hay sin guardar en el panel.
- **Barra de abajo:** la de siempre. El último aviso de guardado va al lado del contador, como en el ADR-0046; en el celular y para quien no edita, arriba.
  - **Quien revisa** decide en esa misma barra: «Revisión de vN · N cambios marcados», Observaciones, No aprobar y Aprobar (`ReviewBox variant="bar"`).
  - En el celular, la tarjeta «Tu revisión» va arriba de la ficha: las aprobaciones también se hacen desde el celular (ADR-0036).
- **Enlaces de antes:** `?seccion=` redirige a `#ancla`, y `FocusTarget` lleva el foco a la tarjeta:
  - `datos` y `fotos` → Datos generales;
  - `ingredientes` y `costos` → la planilla;
  - `rendimiento` y `rendimientos` → Rendimiento;
  - `procedimiento` → Procedimiento;
  - `alergenos`, `uso` y `versiones` → su fila del resumen.
  - Calidad sigue enlazando con `?seccion=fotos`.

### Velocidad de la planilla (decisión de Joaco del 2026-11-14)

- **El problema:** con 17 ingredientes, las sugerencias tardaban 5 s. Medido en la base local (`auto_explain`):
  - `costing.preview_sheet_lines` tardaba 4,3 s con 25 filas, aun sin local;
  - el 99 % era el armado de las filas: el join de la preparación evaluaba `can_view_recipe`, `can_work_recipe` y `sub_in_scope` para **todas** las recetas del grupo, por cada fila, aunque la fila fuera una materia prima;
  - el motor de costos tarda 34 ms;
  - Next corre las acciones de servidor de a una, así que la búsqueda esperaba detrás del cálculo.
- **Migración `20261201120000_preview_sheet_fast.sql`:**
  - el mismo cuerpo, con la preparación buscada por su id en un `left join lateral (… offset 0)`;
  - el `offset 0` impide que el planificador la aplane en un join común (sin él seguía en 3 s);
  - los permisos se evalúan solo para la preparación que la fila usa, y las reglas no cambian;
  - **25 filas: de 4,3 s a 73 ms** con costos y 23 ms solo con pesos.
  - pgTAP (`290`, 6 nuevas):
    - las filas guardadas pasan todas;
    - no pasan la receta misma, la preparación de otra marca ni una desactivada;
    - un tope de 1 s con 25 filas, que además exige las 25. Con esas mismas filas, la función anterior tardaba 4,3 s.
  - Revisión de `db-reviewer`: sin graves ni medios. Se tomaron sus menores (el conteo en la prueba de tiempo, errores en `pg_temp.ms` y la preparación desactivada).
- **La búsqueda va por una ruta GET** (`app/recetas/buscar-componentes/route.ts`, lógica en `lib/recipe-search.ts`):
  - no hace cola detrás de las acciones;
  - tiene la misma sesión y las mismas funciones de la base (`search_components`, `search_subrecipes`); sin sesión, 401; sin caché;
  - el pedido anterior se cancela al seguir escribiendo.

### Sin cambios

- `recipes.save_sheet`, los permisos (precio por kg con `prices.view`, costo de filas sin guardar solo para quien edita o publica), la revisión en solo lectura y el circuito de versiones.
- La planilla: 10 filas más una al llenar la última, autocompletar por código y nombre, las dos escalas, «—» con motivo y nunca $ 0.
- **Celular:** consulta, con scroll, una columna y 44 px. Las fotos grandes, todos los pasos y los ingredientes en tarjetas.

## Pruebas

- **Vitest** (`recipe-sheet-kpis.test.ts`, 12 pruebas):
  - los indicadores de Plato y de Preparación, con y sin costos;
  - sin local, sin costo de una fila, sin peso de la porción, las porciones cargadas a mano, la preparación en litros;
  - «Ingredientes con peso» con la regla única de lo que falta;
  - la marca de revisión y el estado del total.
- **Playwright** (`ficha-receta.spec.ts`):
  - **con 25 ingredientes cargados con el teclado y 12 pasos, en 1440 × 900, 1600 × 900 y 1920 × 1080:**
    - la página no tiene scroll y la planilla sí (`scrollHeight > clientHeight`);
    - el total sigue a la vista;
    - la fila que recibe el foco queda a la vista;
  - Plato y Preparación muestran sus 4 indicadores;
  - quien revisa no edita y decide en la barra;
  - `?seccion=` lleva el foco a su tarjeta;
  - el panel de datos suma en el contador;
  - en el celular, los controles tienen 44 px o más.
- **Ajustadas, sin aflojarlas:**
  - `helpers.ts`: `openSection` abre el panel de las filas del resumen, y `closePanels` cierra los paneles antes de guardar o de cargar una fila;
  - `recetas` y `respuestas`: el chip «Borrador vN» en lugar del texto «Versión en preparación»;
  - `mermas` y `costos`: los nombres nuevos de los indicadores y de las columnas.

## Revisiones (2026-11-14)

- **`db-reviewer`:** sin graves ni medios. Tomé sus menores:
  - el conteo en la prueba de tiempo;
  - los errores dentro de `pg_temp.ms`;
  - una prueba con una preparación desactivada.
- **`security-auditor`:** apto, sin graves ni medios. Corregido:
  - la ruta GET pide `recipes.view` en algún alcance, como el menú de la pantalla (403 si no);
  - la franja de revisión pide 100 pendientes, el tope real de `workflow.inbox`.
  - Queda: con más de 100 pendientes, la franja muestra solo la versión. Una lectura puntual por id pide una migración.
- **`ui-reviewer`:** 2 graves y 6 medios, todos corregidos.
  - **Graves:** el «—» iba en `ink-muted` sobre fondos pastel (la fila marcada y el total). Ahora va en `ink` y el total, en `bg-app`.
  - **Medios:**
    - la lista de sugerencias se abre hacia arriba si abajo no hay lugar, su alto no pasa del espacio que queda, y la opción activa se lleva a la vista;
    - «Más opciones» se abre fijo al borde visible y lleva el foco a su primer control;
    - la planilla se enfoca con el teclado (`tabIndex`, región con nombre);
    - en los alérgenos, cada estado con su palabra: «Contiene: …», «Puede contener: N», «Sin verificar», «Sin alérgenos»; si la lista está vacía, «Sin datos» y nunca «ninguno declarado»;
    - las insignias del resumen se recortan con «…»;
    - quien revisa ve «N cambios marcados» (nuevos o cambiados) y aparte «N ingredientes quitados (en Versiones)».
  - **Menores corregidos:**
    - plurales;
    - «Rubro» sin `label` en solo lectura;
    - nombre accesible de «Hacer»;
    - indicadores de a uno hasta 800 px;
    - borde de 1 px en el paso cambiado;
    - la ayuda de Observaciones en `aria-describedby`;
    - la opción activa con `bg-line/50` en lugar del token de la barra.
  - **Menores que quedan:**
    - «% $» como título (tiene su nombre completo en `abbr`);
    - el campo de solo lectura de Rendimiento con aspecto de campo;
    - los botones sobre la miniatura;
    - el ancho máximo de Ingrediente fijo;
    - la unidad dentro del valor en «Peso total» y «Peso bruto → neto», porque cambia entre g y kg y lleva la flecha.

## Riesgos y lo que queda

- **Medido con `next start`** en 1440 × 900, 1600 × 900 y 1920 × 1080, con el chef (sin dinero) y el director con local (con dinero): sin scroll de página en ningún caso. `next dev` no sirve para medir desde `127.0.0.1`: bloquea sus recursos para otro origen y la página no se hidrata.
