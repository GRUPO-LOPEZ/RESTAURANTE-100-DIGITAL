# ADR-0033 — Calidad de datos (etapa 2.5, PR 1)

- **Fecha:** 2026-11-06
- **Estado:** aceptada. Joaco aprobó el plan.
- **Migración:** `20261118120000_data_quality.sql`.

## Contexto

La sección 16 del documento de Soy pide responder qué tan completo y confiable está el recetario, sin ningún índice inventado: se cuentan hechos, y cada indicador abre la lista exacta de lo que hay que corregir.

## Decisiones de Joaco (2026-11-06)

- **Quién ve:** sin permiso nuevo. Cada indicador pide el permiso de su dato.
- **Por marca o grupo:** se elige un local, y quien ve más de uno tiene una tabla con un local por fila. No se suman porcentajes: el precio y el costo dependen del local.
- **Se cuenta todo, y se ocultan los nombres:** el número incluye las recetas que la persona no puede ver. La lista muestra solo las que ve y aclara cuántas más hay. Sin esto, el Controller veía "aprobadas: 100 %" aunque hubiera borradores.
- **Qué recetas cuentan en un local:** las que usa, más las que todavía no se publicaron en su marca o en el grupo. Sin esto, lo importado por Excel, que nadie asignó, no aparecía en ninguna cuenta. Una receta sin publicar cuenta en cada local de su marca: como no se suman, no se cuenta dos veces.

## Cómo funciona

- **Acceso:** se entra con `recipes.draft`, `recipes.view_costs` o `prices.view` en el local. Así el cocinero, que tiene `recipes.view`, queda como hoy.
- **Indicadores:**

| Grupo    | Indicadores                                                                           | Permiso                                                              |
| -------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Recetas  | Aprobadas, sin revisión pendiente, con rendimiento, con foto, con componentes activos | `recipes.view`                                                       |
| Costo    | Recetas con costo completo                                                            | `recipes.view_costs`                                                 |
| Precios  | Materias primas con precio, precios al día                                            | `prices.view` y `catalog.view`: llevan el nombre de la materia prima |
| Catálogo | Unidad normalizada, rendimiento aprobado, sin parecidos                               | `catalog.view`                                                       |

- **Una sola fuente:** `costing.quality_items` arma los registros. Los números y las listas salen de ahí, así que no pueden diferir.
- **Sin umbrales:** el estado solo dice "Completo" o "Faltan N". Un "80 % es amarillo" sería el índice inventado que Soy no quiere.

## Definiciones (a validar con el Controller)

- **Costo completo:** confiabilidad "verificado" o "con estimaciones", como en `/costos`. Acá el total incluye las recetas que todavía no tienen costo.
- **Unidad normalizada:** tiene un producto de compra activo que se convierte a su unidad de uso (`catalog.missing_conversion`, la regla del motor).
- **Posible duplicado:** otra materia prima activa del grupo con parecido de 0,6 o más, comparando nombres y alias entre sí.
- **Con foto:** cualquier foto de la versión vigente.
- **Recetas aprobadas:** publicadas. Aprobar y publicar pasan juntos (ADR-0023).
- **Materias primas:** todas las activas del grupo, no solo las que usa el local.

## Cambios contra el plan

- **Los parecidos se calculan de noche** (`reporting.mv_ingredient_twins`, tarea `grupo-lf-calidad-parecidos`). Comparar nombres al abrir tardaba 2,1 s por local. El dato es del grupo y no del local, así que no hacía falta repetirlo. Un parecido nuevo aparece al día siguiente, y la pantalla lo avisa.
- **`reporting.v_data_quality` tiene una fila por local e indicador,** y no una por local: se agregan indicadores sin cambiar columnas.
- **"Propuestas de actualización de subrecetas" no se mide:** según ADR-0024, un plato sigue siempre la versión vigente de su preparación, así que esas propuestas no existen.

## Medido (`240`)

Con 300 recetas en 4 locales y 500 materias primas en familias de 10 nombres parecidos:

- un local: de 139 a 204 ms, según la carga de la máquina;
- una lista: de 113 a 168 ms;
- los 4 locales: de 475 a 535 ms;
- los parecidos, de noche: menos de 2 s.

## Excepciones a las reglas de tableros (a confirmar con Joaco)

- **Sin comparación contra el período anterior:** estos conteos no guardan historia.
- **Sin gráfico en `/calidad`:** son listas para corregir. El gráfico va en el Inicio.
- **Sin filtro de fecha:** se calcula con los datos de hoy.
- **La comparación de locales pasa de 300 ms:** tarda cerca de 110 ms por local. Se carga aparte, sin frenar al local elegido, y va de a 20 locales.

## Riesgos

- **Más de 20 locales:** la comparación muestra los primeros 20 y lo avisa; los demás se eligen arriba. Hoy son 4.
- **`reporting.v_data_quality` no mira la sesión y cruza todos los grupos:** antes de abrírsela a una cuenta técnica (Fase 5), hay que filtrarla por su alcance.
- **Si la tarea de la noche falla,** los parecidos quedan viejos y nada avisa.
- **Una revisión pendiente se ve aunque la versión no:** quien solo ve lo vigente sabe que una receta tiene una versión en revisión, sin su contenido.
- **Precio en la cola:** los costos pueden ir un minuto atrás.
- **Nombres muy repetidos:** los parecidos tardan más, pero corren de noche.

## Pruebas

`239_data_quality` (cuenta a mano, listas y permisos), `240_data_quality_performance`, `tests/unit/quality.test.ts` y Playwright `calidad`.
