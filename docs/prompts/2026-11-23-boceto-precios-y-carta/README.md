# Boceto: Precios y Carta (2026-11-23)

Copia del boceto que aprobó Soy el 2026-11-23. Se ve en https://claude.ai/artifact/5LDsm3JHSzQ2y2hoXxTX7T (pedile a Soy que te lo comparta).

Estos archivos son la fuente del boceto y quedan como registro. No se abren solos en el navegador y **no son código del sistema**: no se copian a `app/` ni a `components/`.

Todas las pantallas están en 1440 × 900 y cumplen los 15 criterios de `design.md` (sin scroll de página, panel de 250 px en los listados, altas en modal, encabezado en una línea, 4 indicadores en las fichas y barra fija abajo).

- `Main.dc.html`: pestaña **Platos**. Rubros de menú a la izquierda y planilla de repreciación: el precio se edita en la celda, al lado va el sugerido, y la barra de abajo junta los cambios con motivo y «Enviar a aprobación» (mejora 1).
- `FichaPlato.dc.html`: **ficha del plato** (Tagliatelle a la bolognesa). 4 indicadores (precio neto, costo, contribución, food cost), precio por canal, **nombre de fantasía y descripción** con el nombre en TapTapChef, lo que viene de la receta (alérgenos, foto), historia del precio, cuadrante y etiquetas.
- `NuevoPlato.dc.html`: **alta en modal**. Receta de tipo plato, rubro y costo de la receta, nombre de fantasía propuesto desde TapTapChef y precio sugerido. Entra «En prueba» con 35 días de gracia.
- `Inicio.dc.html`: **Inicio del módulo**. Aviso de la factura que subió un costo (mejora 2), indicadores del grupo, las 4 preguntas de Soy y la comparación entre locales.
- `Matriz.dc.html`: **matriz de ingeniería de menú** por rubro, con los cortes a la vista y qué hacer con cada plato.
- `Configuracion.dc.html`: **Configuración**. Las casillas amarillas las completa Soy (mejora 6): políticas por rubro, platos emblema por marca, canales, IIBB, comisiones y redondeo. Hasta que estén completas, no se inventan valores.

Los números son de ejemplo. Si el boceto y el prompt no coinciden, manda el prompt: `../2026-11-23-precios-y-carta-modulo-3.md`.
