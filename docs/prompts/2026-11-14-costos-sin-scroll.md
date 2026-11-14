# Costos sin scroll y selector de local (pedido de Soy, 2026-11-14)

Un solo prompt, un solo PR. Se corre **después** de las dos fichas sin scroll (`2026-11-13-fichas-sin-scroll.md`), porque reutiliza su patrón (sección «Pantallas … sin scroll» de `design.md`) y la regla única de estado del Inicio (`lib/metrics.ts`).

Boceto: `docs/prompts/2026-11-14-boceto-costos/` (y el enlace en su README).

## Lo que pidió Soy

- **Costos sigue los mismos criterios** que el Inicio y las fichas: la misma apariencia, sin scroll de página y la regla del rojo.
- **El selector de local confunde.** Arriba decía «Local: Demo Café Centro», pero la pantalla de Costos pedía «Elegí un local para ver sus costos». Soy no entendía por qué no veía nada.
- Soy no puede ver Costos con datos, porque todavía no hay precios cargados. Por eso se armó una simulación con costos inventados, que queda en el boceto.

---

## Prompt (copiar en Claude Code)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md (con la sección de pantallas sin scroll que
agregó el PR de la ficha de materia prima), docs/decisiones/0032, 0036 y 0045, y el boceto
docs/prompts/2026-11-14-boceto-costos/ (CostosSinScroll.dc.html es la propuesta;
CostosHoySimulado.dc.html es la pantalla de hoy con datos inventados).
Tarea: dos cosas en un PR. Rama: feat/costos-sin-scroll. Entrá en modo plan y mostrame el plan
antes de tocar nada.

PARTE 1: EL SELECTOR DE LOCAL (components/restaurant-selector.tsx)
Problema que vio Soy: la barra de arriba mostraba «Demo Café Centro» y /costos decía «Elegí un
local para ver sus costos». Primero averiguá la causa y mostrámela en el plan, con la prueba que
la reproduce. No supongas. Hipótesis a revisar:
  a. el select cambia a la vista pero el local no se aplica hasta apretar «Cambiar»;
  b. Next guarda copias ocultas de pantallas anteriores y el defaultValue queda viejo;
  c. el local activo guardado no está entre los locales de costos (getCostPlaces).
Propuesta (decidila en el plan con la causa a la vista): que lo que muestra el selector sea
siempre lo que está aplicado. Por ejemplo, aplicarlo al elegir con el mouse o el dedo, o mostrar
«Sin aplicar» con el botón resaltado mientras no se confirme. Con el teclado no debe cambiar nada
hasta confirmar (como hoy). La opción «Todos mis locales», en una pantalla que necesita un solo
local, tiene que decirlo con claridad en vez de pedir «Elegí un local».
Prueba de Playwright: elegir un local en la barra y llegar a /costos ve ese local, sin pasos de más.

PARTE 2: COSTOS SIN SCROLL (app/costos/page.tsx y app/costos/[id]/page.tsx)
QUÉ NO CAMBIA
- La base, getRestaurantCosts, getCostSummary, getCostLines, getCostHistory, los permisos (quien
  no ve costos no entra) y la cola de recálculo. Si hace falta una migración, parás y me preguntás.
- Escenarios e Impacto quedan como están (otro PR si hace falta).
- El celular sigue siendo de consulta: tarjetas y scroll.

LISTA /costos (1440 × 900, ver el boceto)
1. Encabezado en una línea: «¿Cuánto cuesta cada receta?», y al lado en 13 px «{local} ·
   actualizado el {fecha} · sin IVA». A la derecha, «Escenarios».
2. 4 indicadores (Metric) con la regla única de lib/metrics.ts:
   - Recetas al día (N de total; lo que falta, con la regla);
   - Desactualizadas (N de total, «Ver cuáles» filtra);
   - Incompletas (N de total, «Ver cuáles» filtra);
   - Mayor costo por porción ($ y el nombre del plato, enlaza a su detalle). Sin dato: «—».
   Sin recetas con costo: «Sin datos», nunca «Todas al día» ni 0 %.
3. Una tarjeta que ocupa el alto que queda:
   - una línea con «Buscar» y la confiabilidad como botones segmentados (Todas · Completo · Con
     estimaciones · Desactualizado · Incompleto, con su cantidad), en vez de pestañas; los
     filtros activos como etiquetas con ✕ (FilterBar);
   - la tabla con encabezado fijo y scroll propio: Receta (nombre y código), Tipo, Costo sin IVA,
     Con IVA, Por porción, Por kg, Confiabilidad y Actualizado. «—» con el motivo en el tooltip
     cuando falta un dato;
   - la paginación fija abajo (15 filas por defecto; 10, 25 y 50), con el total.
4. El detalle mantiene la página y los filtros al volver (?volver=, como hoy).

DETALLE /costos/[id] (1440 × 900, en el boceto: clic en una receta)
1. Encabezado en una línea: «← Costos», nombre, código · tipo · actualizado, chip de
   confiabilidad y a la derecha «Ver la receta» (solo si la trabaja, como hoy).
2. Si falta un dato: una franja de una línea, «Falta un dato: {ingrediente}, {motivo}. El total
   queda vacío hasta resolverlo».
3. 4 indicadores: Costo sin IVA (con «Antes: $…»), Con IVA, Por porción (o «Es una
   preparación») y Por kg.
4. Dos columnas que ocupan el alto que queda:
   a. «Línea por línea», ordenada de la que más pesa a la que menos: ingrediente, cantidad,
      costo, barra con el % del costo (tono chart-strong y el % escrito) y con IVA. Encabezado
      fijo y scroll propio. Las líneas sin dato van al final, en bad-ink, con el motivo.
   b. Derecha (360 px): «Cómo fue cambiando», las últimas 3 a 5 fotos con motivo y fecha y «Ver
      toda la historia» (panel lateral), y «Para bajar el costo»: una línea que dice qué
      ingrediente es el que más pesa y su %, con el enlace «Probarlo en Escenarios». Es un
      cálculo con los datos de la pantalla, no un agente de IA.

PRUEBAS
- Playwright con axe (costos.spec.ts y los que toquen costos), con el seed y con datos de costo
  cargados en la prueba (precios y recetas publicadas, para que haya Completo, Desactualizado e
  Incompleto):
  * en 1440 × 900, 1600 × 900 y 1920 × 1080, lista y detalle sin scroll de página; la tabla sí
    tiene scroll propio cuando hay más filas que alto;
  * los indicadores siguen la regla (leé N y total de la pantalla, como en inicio.spec.ts);
  * los botones de confiabilidad filtran y aria-pressed lo refleja; «Ver cuáles» filtra;
  * volver del detalle conserva filtros y página;
  * una receta incompleta muestra la franja, el «—» y la línea sin dato al final;
  * el selector de local: elegir en la barra y ver ese local en /costos;
  * celular: tarjetas, controles de 44 px o más.
- Vitest para el armado de «Para bajar el costo» y el orden de las líneas.
- Las pruebas que se rompan por la nueva disposición se ajustan para controlar lo mismo. No se
  borran ni se aflojan. Corré todo (npm run test).

ENTREGA
ui-reviewer y security-auditor. Capturas reales en 1440, 1600, 1920 y celular, de la lista y del
detalle (una receta completa y una incompleta), guardadas como PNG en docs/capturas/costos-sin-scroll/
y commiteadas en el PR (Soy las revisa desde GitHub). ADR nuevo. Lista de cambios para Soy en
docs/modulos/. docs/estado.md. PR chico. Commit: «feat(costos): lista y detalle en una pantalla, y
selector de local que muestra lo aplicado».
```

## Pendiente de Soy (no bloquea este prompt)

- **Alto real de la pantalla.** Joaco anotó que, en un monitor de 1440 × 900, las barras del navegador dejan unos 790 px útiles y ahí el Inicio hace un poco de scroll. Falta decidir si las pantallas sin scroll se diseñan para ese alto real.
