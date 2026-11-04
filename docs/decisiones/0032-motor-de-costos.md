# ADR-0032 — Motor de costos (etapa 2.3, PR 1 de 3)

- **Fecha:** 2026-11-03
- **Estado:** aceptada (plan aprobado por Joaco)
- **Relacionadas:** ADR-0020, ADR-0021, ADR-0023, ADR-0024, ADR-0025, ADR-0029, ADR-0030

## Contexto

- Había precios y costo de una línea suelta, pero ninguna receta tenía costo.
- Una densidad nueva cambiaba la cantidad de una línea de una receta publicada, sin aprobación (riesgo de ADR-0029).
- `docs/fases/fase-2-plan.md` fija las reglas de cálculo y los casos 3, 4, 5, 7, 9, 14, 15, 18, 19 y 27.

## Decisiones de Joaco (2026-11-03)

1. **El Chef ve el costo por línea.** El detalle de costos no le muestra producto, proveedor, comprobante ni precio del envase.
   - **Se acepta que puede deducir el precio** dividiendo.
   - **Sigue viendo productos y proveedores en el catálogo,** que necesita para trabajar (desde la 2.1). Cruzando los dos llega al precio de un producto.
   - **Ve el costo con IVA y sin IVA** (lo pidió Soy, ADR-0024). Se acepta que eso deja deducir la alícuota, o si hubo factura.
2. **Compras no ve costos de recetas, pero ve fórmulas y precios.** Se acepta que podría hacer la cuenta: los necesita para comprar.
3. **Una baja grande de precio también pasa a Dirección General** (queda en ADR-0029).
4. **El recálculo va por una cola, cada minuto.** Aprobar y publicar no esperan al recálculo. Los costos se actualizan con hasta 1 minuto de demora. Cambia la regla "al publicar, una sola transacción", solo para el costo.
5. **La etapa se reparte en 3 PR:** base (este), pantallas y resto (escalado, escenarios, tarea diaria y `integration_outbox`).

## Cómo quedó (migración `20261112120000_recipe_costs.sql`)

### Cantidades congeladas

- **`recipes.component_base_quantities`:** la cantidad de cada línea en la unidad de uso. Solo de inserción.
- **Se llena al publicar.** Va en una tabla aparte porque las líneas no se tocan fuera de un borrador, y esa regla no se aflojó.
- **Un borrador** usa la conversión de hoy.

### El cálculo

- **Una línea de materia prima:** cantidad en la unidad de uso, rendimiento y precio con herencia. Es la misma cuenta que `costing.ingredient_line_cost`, por `costing.purchase_quantity`.
- **El rendimiento:** de la línea se toman el proceso, el corte y el proveedor, y se busca el estándar **aprobado hoy** (ADR-0024, respuesta 6). Sin estándar, `missing_yield`: nunca se supone 100 %.
- **Una preparación** entra por su costo terminado, así la merma va una sola vez.
- **Si el local tiene una variante publicada** de esa preparación, usa la variante (ADR-0025). No estaba en el plan: salió al revisar el código.
- **Totales:** con IVA y sin IVA. Si falta un dato, el total queda vacío, nunca $ 0.
- **Por unidad base y por porción:** sin rendimiento o sin porciones, no se divide.
- **Confiabilidad:** `verified` < `estimated` < `stale` < `incomplete`. Gana la peor línea. Sin ninguno de los dos costos unitarios, es incompleto.
- **El rendimiento de la receta** es un solo dato (`yield_quantity`), sin medido: se toma como aprobado con la versión y no baja la confiabilidad.

### Tablas

- **`costing.recipe_cost_current`:** el costo vigente por receta y local. Dato derivado.
- **`costing.recipe_cost_snapshots`** y **`recipe_cost_snapshot_lines`:** la historia, solo de inserción. Cada línea guarda lo que no tiene versión: cantidad, versión de la subreceta, rendimiento, precio, contenido del envase y condición frente al IVA.
- **Excepción a la regla de auditoría:** estas tres tablas, y la cola, no llevan `audit.log_change`. Las escribe solo el motor, y lo que cambió ya queda auditado en el precio, el rendimiento o la versión. Las fotos son la historia del costo, y auditarlas duplicaría cada recálculo.

### Quién ve qué

| Rol                                                                   | Costo vigente y fotos | Costo por línea | Precio de la línea  |
| --------------------------------------------------------------------- | --------------------- | --------------- | ------------------- |
| Dirección, Controller, Auditor, Director de Marca, Superadministrador | En su alcance         | Sí              | Por `resolve_price` |
| Gerente                                                               | Su local              | Sí              | Por `resolve_price` |
| Chef Ejecutivo                                                        | En su alcance         | Sí              | **No**              |
| Compras                                                               | **No**                | **No**          | Por `resolve_price` |
| Jefe de Cocina, Cocinera                                              | **No**                | **No**          | **No**              |

- El permiso es `recipes.view_costs`, por local, con `core.permitted_restaurant_ids`.
- `recipe_cost_snapshot_lines` da `select` solo a las columnas sin precio.
- `costing.recipe_cost` y `costing.recipe_cost_lines` son lo que usa la pantalla, también para un borrador. Piden el permiso, ver la versión y que el local esté al alcance de la receta.
- Las funciones `*_internal` y las de recálculo no tienen `grant`.

### Recálculo

Los triggers anotan un pedido en `costing.cost_recalc_queue`, y `costing.process_recalc_queue` recalcula cada minuto, con `pg_cron`:

| Qué pasa                                                        | Motivo de la foto     |
| --------------------------------------------------------------- | --------------------- |
| Se publica o se archiva una versión                             | `publish`             |
| Se aprueba un precio                                            | `price_change`        |
| Se aprueba un rendimiento                                       | `yield_change`        |
| Se asigna una receta a un local, o deja de usarse               | `assignment`          |
| Cambia la razón social de un local o su condición frente al IVA | `legal_entity_change` |
| Se reabre un local                                              | `restaurant_reopened` |

- **Congelar las cantidades sí va en la transacción de publicar:** es lo que no puede esperar.
- **Un solo proceso a la vez** (`pg_try_advisory_xact_lock`): dos recálculos nunca se pisan.
- **Una tanda se recalcula una vez:** los pedidos pendientes se juntan por grupo y motivo.
- **Solo hay foto si el costo cambió.**
- **Si una tanda falla,** se prueba pedido por pedido: los sanos pasan, y el que falla guarda el error y se reintenta hasta 3 veces. Las pantallas del PR 2 lo tienen que mostrar.
- **La corrida tiene su propio límite: 10 minutos.** Una corrida cortada por tiempo no se registra como error y se reintenta entera.
- **La historia queda por tanda:** tres precios en el mismo minuto dan una sola foto, con el motivo de la primera tanda.
- **Lo que un local ya no usa** deja de tener costo vigente, en el mismo recálculo. La historia queda.
- **Los locales cerrados** no se recalculan: su último costo queda como estaba. Al reabrir, se ponen al día.

### Datos raros

- **Un valor que no entra en la columna** (por ejemplo, un rendimiento de una millonésima de gramo) queda vacío y el costo, incompleto. Nunca rompe un recálculo.
- **Un círculo a través de una variante** no se recorre: la línea queda `incomplete_sub_recipe`. Las validaciones de publicación no siguen variantes.
- **Una variante que rinde en cajas o en otra dimensión** deja la línea `missing_yield`: el plato nunca sale más barato.
- **Si una materia prima cambia de unidad de uso** sin tener precios, la cantidad congelada no se usa: `missing_conversion`.

### Rendimiento (`233_recipe_costs_performance`)

300 recetas, 3 cadenas de 10 niveles, 4 locales, una materia prima que usan todas.

| Medición                                        | Primera versión | Versión final         |
| ----------------------------------------------- | --------------- | --------------------- |
| Leer los costos de un local                     | 33 ms           | 69 ms                 |
| Aprobar un precio de grupo de esa materia prima | 198 s           | **9 ms**              |
| Recalcular las 1.200 combinaciones              | 198 s           | **7,7 s, por detrás** |

- La primera versión recalculaba cada preparación por cada plato, y buscaba el precio línea por línea.
- **La final** trae los precios del local una vez, y calcula cada preparación una sola vez (`p_memo`), con todos sus decimales. Una prueba controla que dé lo mismo que la cuenta directa.

## Pruebas

- `230_recipe_costs` (38): casos 3, 4, 7, 9, 18, 19 y 27, IVA, confiabilidad, variante y la planilla DEMO.
- `231_recipe_costs_flow` (75): casos 5, 15 y 16, la cola, cada evento, los datos raros, archivar y publicar por el flujo real, y que las fotos no cambien.
- `232_recipe_costs_permissions` (37): cada rol, borradores, alcance de la receta, versiones que no se ven y la vista de cocina (caso 24 con costos reales).
- `233_recipe_costs_performance` (5).
- **Planilla a mano:** [docs/guias/costos-demo.md](../guias/costos-demo.md). La validan Joaco y el Controller.

## Riesgos y pendientes

- **Los costos pueden tener hasta 1 minuto de demora.** Después de aprobar un precio, una pantalla puede mostrar el costo anterior. La pantalla del PR 2 lo tiene que aclarar.
- **Precios con fecha futura y "desactualizado":** un precio que empieza mañana no anota nada. El paso del tiempo y cambiar los días de desactualizado (`update_price_settings`, `set_category_stale_days`, la categoría) tampoco. Los absorbe la tarea diaria del PR 3.
- **Si un error se repite 3 veces,** ese pedido queda sin procesar hasta que alguien lo mire. El PR 2 lo tiene que mostrar.
- **Casi todo puede salir "con estimaciones":** un precio heredado cuenta como estimación (caso 21). Si los precios se cargan a nivel grupo, cada local los hereda. Hay que mirarlo con datos reales.
- **Las validaciones de publicación no siguen variantes.** El motor se protege (círculos y unidades), pero una variante mal armada se publica igual y queda incompleta. Conviene validarlo al publicar.
- **`recipe_cost_current` no está en plural,** como pedía el plan de la Fase 2.
- **Las fotos crecen** con cada cambio de precio: 1.200 filas y unas 11.000 líneas en el peor caso medido. Se revisa con datos reales.
- **La historia de costos de un local nuevo:** quien entra hoy lee todas las fotos de totales de su local. Las líneas, solo de las versiones que ve.
- **`core.audit_history`** destapa valores con `recipes.view_costs`, no con `prices.view`. Hoy no se explota (ADR-0029): ningún rol con `audit.view` deja de ver precios.
- **La cola no se limpia:** guarda los pedidos procesados. Se revisa con datos reales.
- **Sin tope de trabajo en `recipe_cost`:** sin memo, repite las preparaciones. Con recetas normales no se nota; hay que medirlo cuando el PR 2 lo use en pantalla.
- **La bandeja de aprobaciones** oculta importes por nombre de clave: un Chef o un Jefe de Cocina con `approvals.view` ve el producto, el proveedor y el comprobante de una solicitud de precio. Coincide con la decisión 1, salvo el comprobante.
