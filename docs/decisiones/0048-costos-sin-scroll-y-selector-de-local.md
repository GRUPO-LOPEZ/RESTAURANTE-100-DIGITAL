# ADR-0048: Costos en una pantalla y un selector de local que muestra lo aplicado

- **Fecha:** 2026-11-14
- **Estado:** plan aprobado por Joaco el 2026-11-14.
- **Pedido:** Soy, `docs/prompts/2026-11-14-costos-sin-scroll.md`; boceto `docs/prompts/2026-11-14-boceto-costos/CostosSinScroll.dc.html`.
- **Sigue a:** ADR-0032 (costos), ADR-0036 (selector de local único y global), ADR-0045 (regla única de lo que falta) y ADR-0046/0047 (pantallas sin scroll).
- **Sin cambios en la base.**

## Contexto

Soy veía «Local: Demo Café Centro» arriba y Costos le pedía «Elegí un local para ver sus costos». No entendía por qué no veía nada. Además pidió que Costos (lista y detalle) entre en una pantalla, con el criterio del Inicio y las fichas.

## La causa del selector, reproducida

Antes de cambiar nada se escribió una prueba de Playwright que reprodujo cada hipótesis con el código de antes (Controller, base recién recreada):

| Hipótesis                                                                 | Qué pasó                                                                                                               | Resultado                                                                         |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| a. El select cambia a la vista, pero no se aplica hasta apretar «Cambiar» | Elegir Demo Pastas Centro en la barra, sin el botón: la barra lo mostraba y Costos seguía pidiendo un local.           | **Se reprodujo.** Es lo que vio Soy.                                              |
| b. Una pantalla guardada por Next muestra un `defaultValue` viejo         | Aplicar un local, pasar a «Todos mis locales» en otra pantalla y volver a Costos: la barra mostró «Todos mis locales». | No se reprodujo.                                                                  |
| c. El local aplicado no está entre los que dejan ver costos               | Superadministrador y Dirección tienen `recipes.view_costs` en todo el grupo.                                           | Descartada para Soy. Le puede pasar a quien tiene costos solo en algunos locales. |
| d. Un enlace con `?local=`                                                | `/costos?local=Pastas Centro` mostraba ese local y la barra decía «Todos mis locales».                                 | **Se reprodujo.** Encontrada al revisar.                                          |

El texto de antes («Elegí uno en «Local», en la barra de arriba») tampoco decía que había que apretar «Cambiar».

## Decisiones

### Selector de local (`components/restaurant-selector.tsx`)

- **Lo que muestra es siempre lo aplicado.** El select es controlado y se arma de nuevo cuando cambia el local aplicado (`key`), así ninguna copia guardada muestra una elección vieja.
- **Con el mouse o el dedo, elegir aplica.** Con el teclado (flechas), nada cambia: el chip dice «Sin aplicar» y aparece «Aplicar», resaltado. Se distingue por el último evento sobre el select (`keydown` o `pointerdown`). Si un navegador no avisa bien, el peor caso es pedir la confirmación, nunca aplicar sin querer con el teclado.
- **Chip al lado** (como el boceto): «Aplicado», «Sin aplicar» o «Aplicando…», en una región `status`.
- **Decisión de Joaco (2026-11-14): un `?local=` se aplica al llegar.** Si la dirección trae uno de tus locales distinto del aplicado, el selector lo aplica con la misma acción (`setActiveRestaurantAction`) y lo saca de la dirección. Se hace en el navegador: el prefetch de un enlace no cambia nada.
- **Se saca de la dirección con `window.history.replaceState`**, que Next sincroniza con `useSearchParams` sin navegar. Con `router.replace`, la navegación pisaba un clic que la persona ya había hecho (ordenar una columna) y dejaba la pestaña sin título un momento. Se lee la dirección de ese momento, no la del render.
- **Mientras aplica, el selector no se aclara:** la opacidad bajaba el contraste del texto por debajo de 4,5:1 (axe). Lo dice el chip «Aplicando…».
- **Un reporte de una receta que no es del local**, pedido a mano con `?local=`, termina en «No encontramos esta página» o, si el `?local=` ya salió de la dirección, en la lista para elegir otra receta (la regla que ya tenía el reporte para cuando se cambia el local arriba). Nunca muestra la ficha de la otra marca, y la exportación con ese local sigue rechazada.
- **`PlacePrompt`** (Costos, Calidad, Reportes, Escenarios): «{Pantalla} se ve de a un local. Arriba está elegido «Todos mis locales». Elegí cuál ver:» y botones que aplican el local (antes, enlaces `?local=` que no tocaban la barra). Si el local aplicado no deja ver costos (caso c), lo dice con su nombre.
- Efecto en las pruebas: entrar con `?local=` cambia el local de esa persona. Las pruebas que empiezan con «Todos mis locales» lo eligen primero (`chooseLocal` en `tests/e2e/helpers.ts`).

### Lista `/costos`

- `AppShell fill`. Encabezado en una línea: «¿Cuánto cuesta cada receta?» y «{local} · actualizado el {fecha} · sin IVA». «Escenarios» a la derecha.
- **4 indicadores** (`costListMetrics` en `lib/costs.ts`, con Vitest), con `missingState`:
  - Recetas al día: completas de total; el estado con lo que falta.
  - Desactualizadas: «Vencidas: N» o «Ninguna»; «Ver cuáles» filtra.
  - Incompletas: «Sin total: N» o «Ninguna»; «Ver cuáles» filtra.
  - Mayor costo por porción: `restaurant_costs` con orden `-portion` y una fila (la base deja los vacíos al final); el nombre lleva al detalle. Sin dato: «—» y el motivo.
- **Confiabilidad como botones** (`components/costs/reliability-filter.tsx`): formulario GET con `aria-pressed`, que conserva búsqueda, orden y filas. Con JavaScript navega sin recargar. Llevan su cantidad; la de «Completo» sale de una lectura con una sola fila (el resumen junta Completo y Con estimaciones). En la tabla y en los botones dice «Completo», no «Completo y verificado».
- **`DataTable scroll`** (nuevo): en la computadora la tabla ocupa el alto que queda, se desplaza adentro y el encabezado queda fijo. Una fila, un renglón (código debajo del nombre) y celdas de 8 px de margen, para que las 8 columnas entren en 1440 sin desplazarse de costado. El contenedor lleva `relative`: sin eso, el título oculto de la tabla (`sr-only`, absoluto) escapaba del recorte y agrandaba la página.
- «—» con el motivo en un tooltip (`components/costs/missing-value.tsx`).

### Detalle `/costos/[id]`

- Encabezado en una línea: «← Costos», el nombre, «código · tipo · actualizado» y el chip de confiabilidad; «Ver la receta» a la derecha, solo para quien la trabaja.
- Si falta un dato, una franja: «Falta un dato: {ingrediente}, {motivo}. El total queda vacío hasta resolverlo.» (`missingSummary`).
- 4 indicadores: Costo sin IVA (con «Antes: $…»), Con IVA, Por porción (o «Es una preparación») y Costo por kg (o litro, o unidad).
- **Línea por línea**, de la que más pesa a la que menos; **las que no tienen dato, al final** (antes iban primero: cambió el pedido, y la prueba de Vitest se cambió con él). Barra del % en `chart-strong-1` con el % escrito. Encabezado fijo y scroll propio.
- **Cómo fue cambiando:** las últimas 4 fotos y «Ver toda la historia (N)» en un panel, hasta 50.
- **Para bajar el costo** (`costTip`): «{ingrediente} es el {N} % del costo…», con el mismo redondeo que la tabla. Con un dato faltante: «Primero hay que completar el dato que falta». «Probarlo en Escenarios» abre Escenarios del local (sin preelegir: Escenarios no cambia en este PR). Es una cuenta, no un agente.

### Celular

De consulta: tarjetas, scroll y 44 px. Sin cambios de idea.

## Revisión de seguridad (2026-11-14)

Apto, sin graves ni medios. Los dos menores:

- **Un enlace de afuera puede cambiar el local aplicado** (solo a uno de los locales de la persona: lo valida `core.set_active_restaurant`). No da acceso a nada nuevo, pero otra pestaña puede quedar mostrando el local anterior hasta refrescarse. Regla: **ninguna acción que escribe toma el local aplicado como valor por defecto**; cada escritura recibe su local explícito. La vigila `tests/unit/active-restaurant-writes.test.ts`.
- **El cambio de local aplicado no se audita** (`last_restaurant_id` está en `audit.untracked_columns`, como antes). Ahora también puede venir de un enlace. Se acepta: es una preferencia de vista, no un dato del negocio.

## Revisión de diseño (2026-11-14)

Sin graves. Corregido:

- **Las líneas sin dato** siguen en `bad-ink`, como pidió Soy, pero ahora llevan la palabra: «Sin dato: {motivo}».
- **Objetivos de 24 px** (nombre de la receta y «—») subidos a 28 px, dentro de la excepción de ADR-0045/0046.
- **El selector y «Aplicar» ya no se deshabilitan mientras aplican** (el foco del teclado quedaba sin lugar): `aria-busy` y `aria-disabled`, y se ignoran los cambios.
- **`PlacePrompt` no afirma lo que no sabe:** solo Costos dice «Arriba está elegido «Todos mis locales»»; las otras pantallas, «Elegí cuál ver (queda elegido también arriba)».
- **Otros arreglos menores:**
  - «Ver las últimas 50» cuando la historia se corta;
  - el «—» del porcentaje dice por qué;
  - el chip, sin `display: contents`.

Quedan:

- **El orden de las columnas de la línea por línea** es el del pedido: costo, peso y con IVA.
- **Un solo `TooltipProvider` por tabla** y una utilidad para la línea del encabezado fijo: son limpiezas de código, no cambian nada a la vista.
- **Falta probar el selector con NVDA en modo exploración.** Si el cambio llega sin `keydown`, se aplicaría al moverse por la lista.
- **Los filtros de confiabilidad no avisan mientras cargan.**

## Lo que queda

- El alto real de un monitor de 1440 × 900 (unos 790 px útiles): pendiente de Soy. No se diseñó para ese alto.
- «Probarlo en Escenarios» no preelige el ingrediente.
- El selector distingue mouse de teclado con eventos del `<select>` nativo; se probó en Chromium.
