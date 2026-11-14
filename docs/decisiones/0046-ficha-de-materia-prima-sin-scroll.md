# ADR-0046: Ficha de materia prima en una pantalla, y el patrón de pantallas de carga sin scroll

- **Fecha:** 2026-11-13
- **Estado:** aceptada por Joaco (plan aprobado el 2026-11-13).
- **Pedido:** Soy, `docs/prompts/2026-11-13-fichas-sin-scroll.md` (Prompt 1), boceto `docs/prompts/2026-11-13-boceto-fichas-sin-scroll/FichaMateriaPrima.dc.html`.
- **Sigue a:** ADR-0043 (ficha única de materia prima) y ADR-0045 (Inicio en una pantalla).

## Contexto

La ficha única de materia prima (ADR-0043) era una página larga:

- un índice de botones;
- seis secciones apiladas;
- dos tarjetas de precios que decían lo mismo;
- cuatro indicadores de mermas;
- 14 alérgenos, cada uno con 4 botones y un desplegable de origen.

Para ver todo había que bajar. Soy pidió que entre entera en 1440 × 900, con el mismo patrón que el Inicio, y que ese patrón quede escrito para las pantallas que vengan.

## Decisiones

### El patrón «Pantalla de carga sin scroll» (`.claude/rules/design.md`)

1. Encabezado en una línea. La acción secundaria es un botón a la derecha.
2. 4 indicadores (`Metric` compacto) que no se repiten abajo.
3. Tarjetas en columnas que ocupan el alto que queda. Se edita donde se ve.
4. Listas cortadas con «Ver los N».
5. La barra de guardado de siempre.
6. Pruebas en 1440, 1600 y 1920. El celular es de consulta.

Piezas comunes nuevas, que también usa el Inicio:

- `components/ui/tile.tsx`: la tarjeta compacta. Con `id`, recibe el foco de los enlaces de antes.
- `components/ui/short-list.tsx`: la lista cortada con «Ver los N».
- `components/focus-target.tsx`: lleva el foco a la tarjeta del `#ancla`.
- `AppShell` / `PageHeader` con `back` y `meta`: el encabezado en una línea.
- `Kpi` / `Metric` con `action`: «Ver cuáles» abre un panel en lugar de ir a otra página.
- `ActionModal` con `variant="link"`, `icon="none"` y `size="sm"`: los «Ver …» y las acciones chicas de una tarjeta.

### La ficha

- **Encabezado:** «← Materias primas», el nombre y «código · rubro · se usa en g», con el chip Activa o Desactivada (y «Se compra congelada»).
  - «Desactivar» deja de ser un desplegable: es un botón a la derecha, que abre un panel con el motivo.
  - El enlace se anuncia como «Volver a materias primas».
- **Indicadores:**
  - Precio vigente (con el local);
  - Costo neto por kg (con merma y descongelado);
  - Rinde neto;
  - Recetas que la usan.
  - Quien no ve precios ve, en lugar de los dos de plata, «Productos de compra» y «Merma de limpieza». Nunca dinero.
- **Columna 1, Datos generales:** se editan donde se ven.
  - Rubro y unidad van en una fila.
  - «¿Se compra congelada?» es un interruptor de un clic. Dejar de comprarla congelada sigue pidiendo aprobación.
  - La explicación de la unidad pasa a la línea de ayuda, porque la columna es angosta para un tooltip.
- **Columna 2, Precios de compra** (una sola tarjeta; antes eran dos):
  - Hasta 3 productos, cada uno con su precio por kg, l o u y su estado.
  - «Ver los N productos» abre un panel con la tabla completa: «Editar», los que ya no se compran, el costo en el local (con y sin IVA) y el historial de precios con su impacto.
  - «Proponer precio» es un panel y **sigue en el celular** (ADR-0044). Las altas de producto y de proveedor quedan en la computadora.
- **Columna 2, Mermas y rendimientos:**
  - La merma de limpieza y la de descongelado, con su valor y su estado. Sin dato, «—», el estado y el motivo.
  - Una línea con el resumen de los rendimientos por proceso: cuántos, con estándar, en revisión y desviados. «Ver todos» abre la tabla de hoy.
  - Las propuestas y los ensayos, como hoy.
- **Columna 3, Conversiones:** cada una en una línea.
  - «Editar» abre un panel que trabaja **sobre el mismo borrador**: lo cambiado cuenta en la barra y se guarda junto.
  - Si el guardado marca un error en una conversión, se abre su panel con el foco en el campo.
- **Columna 3, Alérgenos:** un botón por alérgeno que cambia en cada clic (Sin dato → No contiene → Puede contener → Contiene), con su color y su palabra. El nombre del botón es «Gluten Contiene. Cambiar» (y borde punteado si cambió).
  - El prompt decía «Gluten: Contiene. Cambiar». Sin los dos puntos, el nombre contiene el texto visible tal cual, como pide WCAG 2.5.3; axe lo marcaba con los dos puntos.
  - **Origen del dato — un solo «Origen de estos cambios»** para todos los alérgenos cambiados. No se completa solo: si falta, el guardado lo pide.
  - El origen guardado de cada uno se ve en el tooltip del botón.
  - Si el ciclo vuelve al estado guardado, también vuelve su origen y no cuenta como cambio (`lib/ingredient-sheet.ts`, con Vitest).
  - La lista sin validar es un chip «Sin validar» al lado del título.
- **«Dónde se usa» (decisión de Joaco, 2026-11-13):**
  - Con los 14 alérgenos, la tercera columna no entraba en 1440 × 900 (le sobraban unos 110 px). El boceto tampoco entraba: cortaba los alérgenos.
  - Se sacó la tarjeta. El número ya está en el indicador «Recetas que la usan», que tiene «Ver cuáles» con la lista. Así tampoco se repite el dato.
  - `?seccion=uso` lleva el foco a ese indicador.
- **Columnas en proporción 4 : 5 : 4,** como el boceto. El prompt decía «4/12, 5/12, 4/12», que suma 13.
- **Los enlaces de antes:** `?seccion=…` sigue redirigiendo a `#ancla`, y `FocusTarget` lleva el foco a la tarjeta y la marca.
- **Barra de guardado:** la misma. Baja de 12 a 8 px de margen vertical para que la pantalla entre.

### Sin cambios

- La base, los permisos y las aprobaciones. Los paneles de alta (producto, proveedor, merma, rendimiento, ensayo) son los mismos formularios.
- **Celular:** consulta, con scroll, una columna y 44 px. «¿Se compra congelada? No» se lee como antes.

## Después de las revisiones (2026-11-14)

**Seguridad: apto,** sin hallazgos graves ni medios.

- Corregido: una dirección mal armada (`#%E0`) ya no rompe la ficha (`FocusTarget`).
- **El Chef había dejado de ver el «Costo neto»:** la ficha pedía permiso de precios además del de costos.
  - Ahora vuelve a la regla de antes: el costo neto, con costos; el precio, con precios.
  - Quien no ve costos ve «Alérgenos con dato» (N de 14, con la regla única de colores), y no la merma repetida.

**Diseño: no aprobado en la primera vuelta, por un grave.** Todo corregido:

- **Grave: los montos se salían de su tarjeta** en el celular, y en 1440 con precios de 6 cifras.
  - En el celular los indicadores van de a uno.
  - La unidad («/ kg») va aparte del número.
  - El número puede pasar de renglón antes que salirse.
- **Medios:**
  - el motivo de un dato faltante se ve entero, en su renglón (12 px); antes se cortaba;
  - quien solo lee ve los alérgenos en la misma grilla de 2 columnas, y hay una prueba sin scroll con la Chef;
  - el botón de un alérgeno cambiado dice «Cambio sin guardar» al lector de pantalla;
  - el origen guardado se anuncia; antes estaba solo en un `title`;
  - los nombres largos pasan a dos renglones en vez de cortarse;
  - «Sin validar» tiene su ayuda (ⓘ);
  - al cerrar el panel de una conversión, el foco vuelve a su fila o al botón para agregarla;
  - en `design.md` se amplió la excepción de 28 y 32 px a las pantallas de carga sin scroll y se sumaron aclaraciones: h1 de 20 px, la unidad en `unit`, prueba con un rol que solo lee y con las listas llenas.
- **Menores:**
  - HTML válido (un `h2` y un aviso ya no van dentro de un `span`);
  - espacios en múltiplos de 4 px;
  - el foco de la tarjeta se marca solo con el teclado o un enlace;
  - «Ver los N productos» cuenta lo que muestra el panel;
  - en la tarjeta va primero la descripción del producto y después el proveedor;
  - el pedido pendiente de la congelada también se ve en el celular;
  - `FocusTarget` escucha `popstate`;
  - el texto del panel de precios ya no nombra un botón que no está ahí.
- **Queda para después:** entre 800 y 1279 px las tres columnas son angostas. No es un ancho objetivo, y en 1280 no se sale.
- **El aviso de guardado va en la barra de abajo,** al lado del contador, y no en una fila arriba (con 5 productos esa fila hacía scroll). En el celular, y para quien no edita, sigue arriba.

## Pruebas

- **Vitest:**
  - el ciclo de alérgenos, el origen común y la vuelta al estado guardado (`ingredient-sheet.test.ts`);
  - la lista cortada (`short-list.test.ts`).
- **Playwright `ficha-materia-prima.spec.ts`:**
  - la ficha entra en 1440, 1600 y 1920 con las 5 tarjetas a la vista;
  - `?seccion=alergenos`, `compra` y `uso` llevan el foco a su tarjeta;
  - «Desactivar» es un botón;
  - «Ver cuáles» de recetas;
  - el alérgeno con dos clics, el `aria-label` y el origen común (sin origen, el guardado lleva el foco ahí);
  - la conversión en su panel;
  - el producto editado y reactivado en el panel;
  - **con 5 productos, la tarjeta muestra 3 y «Ver los 5 productos», y la pantalla sigue sin scroll.**
- **Ajustadas, sin aflojarlas:**
  - `materias-primas`: todo a la vista, el foco en la tarjeta, el chip «Sin validar»;
  - `mermas`: las mermas son filas con su motivo;
  - `rendimientos`: la tabla está en «Ver todos»;
  - `precios` y `costos`: «Proponer precio» y el detalle de precios en sus paneles;
  - `openSection` controla que la tarjeta esté a la vista.

- **Corrida completa (2026-11-14), con la base recién recreada:** Vitest 382 de 382, pgTAP en verde, Playwright 269 en verde y 1 falla inestable en `rubros`, que esta rama no toca (sola, 24 de 24 en verde).
- **Capturas:** `docs/capturas/ficha-materia-prima-sin-scroll/`.

## Riesgos y lo que queda

- **1440 × 900 entra justo con el seed, que tiene 8 alérgenos; la base real tiene 14. Con 14 no está probado:** es una cuenta.
  - 7 filas de 28 px con 4 px entre ellas dan unos 475 px en la tercera columna, y con el «Origen de estos cambios» a la vista, unos 516, contra 528 disponibles.
  - Hay que mirarla en staging con los alérgenos reales.
- **La ficha usa la excepción de 28 y 32 px** del ADR-0045 en filas, alérgenos y enlaces. El celular sigue en 44 px.
- **Distintos orígenes** para dos alérgenos cambiados a la vez se cargan en dos guardados.
- **Para preguntar (pasa igual antes de este cambio):** el local de la ficha sale de los que dejan ver costos de recetas. Compras ve precios sin ver costos, y por eso no ve el precio del local que elige arriba.
