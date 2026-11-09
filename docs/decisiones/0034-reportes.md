# ADR-0034 — Reportes (etapa 2.5)

- **Fecha:** 2026-11-07
- **Estado:** aceptada. Joaco aprobó el plan.
- **Migraciones:** `20261120120000_report_event.sql` y `20261120120100_reports.sql`.

## Contexto

La sección 18 del documento de Soy pide siete reportes en PDF, Excel y CSV, con fecha de datos, versión y local. Este PR trae los cinco de listas. Las dos fichas por receta (técnica y de costeo) van en el siguiente.

## Decisiones

- **El PDF sale de la impresión del navegador (Joaco, 2026-11-07):** sin dependencia nueva, igual que el escalado. El Excel usa ExcelJS, que ya estaba por el importador (ADR-0027).
- **Una sola definición por reporte** (`lib/report-labels.ts` y `lib/reports.ts`): la pantalla, el Excel y el CSV salen de las mismas filas.
- **Quién puede:** `reports.export` en el local, más el permiso del dato. Compras, Jefe de Cocina y Cocinera no tienen reportes.

| Reporte          | Además de `reports.export`                                     |
| ---------------- | -------------------------------------------------------------- |
| Materias primas  | `catalog.view` y `prices.view`                                 |
| Rendimientos     | `catalog.view`                                                 |
| Dónde se usa     | `recipes.view`                                                 |
| Cambios de costo | `recipes.view_costs`                                           |
| Calidad de datos | Entrar a la calidad de datos, y los permisos de cada indicador |

- **Un reporte lleva nombres:** a diferencia de `/calidad`, que cuenta todo, acá solo sale lo que la sesión puede ver.
- **Lo que sale por la aplicación queda registrado:** Excel, CSV y el botón de PDF dejan `report_exported` en el registro de seguridad, con el reporte, el formato, las filas, el local y el período. Quien ve ese registro lo consulta en `/reportes`.
- **Es trazabilidad, no un muro:** esos datos la persona ya los puede leer por las pantallas de cada módulo. Ctrl+P y las funciones llamadas directo por la API no dejan registro, y `reports.export` no reemplaza a los permisos de cada dato.
- **Mirar un reporte en pantalla no se registra:** son datos que la persona ya ve.
- **Tope de 5.000 filas por exportación,** con aviso en el archivo si se corta.
- **Imprimir trae todas las filas:** "Preparar para imprimir" abre una vista sin paginar, y cada hoja repite el reporte, el local y la fecha. Si alguien imprime la pantalla paginada, la hoja avisa que no trae todo.
- **El CSV va separado por punto y coma:** es como lo abre Excel en español, y los importes llevan coma decimal.
- **Celdas seguras:** lo que empieza con `=`, `+`, `-` o `@` no se ejecuta como fórmula. Está en `lib/csv.ts`, con la versión más estricta, y lo usan también el historial y los errores de importación.
- **Cambios de costo muestra lo que pasó en el período (Joaco, 2026-11-07):** quien ve costos en el local recibe todo, aunque la receta ya esté archivada o el local no la use, y se marca "ya no se usa". Así todos sacan el mismo reporte.
- **Una versión nueva aparece marcada (Joaco, 2026-11-07):** con el motivo "Cambió la receta", para que las variaciones cierren.
- **Dónde se usa llega a los platos:** recorre las preparaciones hacia arriba, con la variante del local, y dice a través de cuál.

## Cambios contra el plan

- **"Versión":** solo la llevan los reportes de recetas (Dónde se usa y Cambios de costo). En los demás no hay versión que mostrar.
- **Una función más:** `report_list` y `report_places`, para saber qué reportes y qué locales ofrecer.

## Riesgos

- **El PDF depende del navegador:** los cortes de página pueden variar. Falta probar en una impresora real.
- **Un archivo descargado sale del control del sistema:** por eso el permiso, el registro y el tope.
- **Reportes de más de 5.000 filas** se cortan, con aviso. Hoy el recetario está lejos.
- **El registro se puede llenar:** quien tiene el permiso puede llamar `log_report` sin límite, y las filas son un dato declarado. La identidad y el local no se pueden falsear.
- **Cambios de costo con años de historia** no está medido: `240` mide con pocas fotos.
- **Una receta que vuelve a un local** se compara contra su última foto, de hace meses.

## Las fichas por receta (2026-11-08)

Migración `20261121120000_recipe_cards.sql`. Con esto están los siete reportes de la sección 18.

- **Ficha técnica:** alérgenos, ingredientes, cantidades, cómo se mide cada uno, rendimiento, peso por porción, tiempos, paso a paso (con el orden entre pasos), fotos, presentación, conservación, versión y desde cuándo rige. Sale de `recipes.kitchen_card`, así que nunca trae un importe. Pide `recipes.view`.
- **Ficha de costeo:** costo de cada línea (preparaciones incluidas), total con y sin IVA, por porción, participación y estado. Sale de `costing.recipe_cost_lines`. Pide `recipes.view` y `recipes.view_costs`.
- **Primero se elige la receta,** entre las vigentes del local que la persona ve (`costing.report_recipes`). Se busca por nombre o código, sin importar acentos ni mayúsculas.
- **Los alérgenos van siempre:** en pantalla, marcados como en la vista de cocina, y en Excel y CSV en una línea del encabezado. Un papel que va a la mesada sin alérgenos es un riesgo.
- **Una ficha entra entera:** se imprime tal como se ve, sin el paso "Preparar para imprimir".
- **Excel y CSV llevan la tabla de líneas** y, en el encabezado, la receta, la versión y el total. El paso a paso y las fotos van solo en pantalla y en papel.
- **Las fotos** salen con el enlace firmado de Storage, de diez minutos.
- **La base controla que la receta sea del local** (`costing.require_report_recipe`): el permiso del reporte y que la receta sea una vigente del local. Sin esto, alguien que ve recetas de otra marca podría sacar su ficha a nombre de este local. La pantalla y la exportación la llaman antes de armar la ficha.
- **El registro dice de qué receta es la ficha:** `log_report` suma la receta, la exige en las fichas y la vuelve a controlar contra el local.

## Pruebas

`242_reports`, `243_recipe_cards`, `240_data_quality_performance`, `tests/unit/reports.test.ts` y Playwright `reportes`.
