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

## PR 2: pantallas (2026-11-04)

Migración `20261113120000_cost_screens.sql`.

### Pantallas

- **Menú "Costos":** con `recipes.view_costs` en algún local.
- **`/costos`:** ¿cuánto cuesta cada receta en este local? Tarjetas, filtros, lista paginada y avisos de la cola.
- **`/costos/[id]`:** ¿qué encarece esta receta? Tarjetas, línea por línea, de mayor a menor, y las últimas 10 fotos. Calcula con los precios de hoy.
- **`/costos/impacto/[id]`:** ¿a qué le pegó este precio? Se llega desde "Ver el impacto", en cada precio vigente de la ficha de materia prima.
- **`/recetas`:** suma el costo, con un local definido. **`/recetas/[id]`:** una tarjeta con el costo, también de un borrador.
- **La vista de cocina no cambió.**
- **El detalle va en una pantalla propia** y no en una pestaña de la receta: el Gerente y el Controller no trabajan recetas, y `/recetas/[id]` los manda a la vista de cocina.

### Base

- **`costing.recalc_status`:** pendientes y fallidos, solo de los locales de la sesión. Nunca el texto del error.
- **`costing.restaurant_costs`** y **`restaurant_cost_summary`:** la lista y las tarjetas de un local, solo con recetas que la persona ve.
- **`costing.price_impact`:** el antes y el después.
  - **La tanda sale del pedido:** `cost_recalc_queue.price_record_id`. Las fotos repiten todas las líneas, así que no alcanzan para saber qué precio causó qué.
  - **Solo las recetas que lo usan:** las fotos de esa tanda con una línea de ese precio y, hacia arriba, las que usan esas preparaciones.
  - **Un precio que no cambió nada** no muestra impacto.
  - **La diferencia incluye lo demás** que entró en esa tanda. Si cambió la versión, lo dice.
- **`recipe_cost_snapshots.entry_number`:** el orden de las fotos, porque las de una tanda comparten la hora.

### Excepciones a las reglas de tableros (a confirmar con Joaco)

- **`/costos` no compara contra el período anterior:** todavía no hay fotos de fin de mes. Llega con el PR 3.
- **Sin filtro de marca ni de fecha:** se elige un local, que ya define la marca, y el costo es el vigente.
- **Sin gráfico:** son una lista y un detalle. El candidato es "Cómo fue cambiando", cuando haya historia real.

### Pruebas del PR 2

- `234_cost_screens` (42): quién ve qué, la cuenta del antes y el después, dos precios en una tanda, un precio sin efecto y recetas que un local dejó de usar.
- `tests/unit/costs.test.ts` (9) y Playwright `costos` (celular y computadora, con axe), con la tarea de la cola de verdad.

### Revisiones (PR 2)

- **`db-reviewer`:** dos graves, resueltos con el ancla en la cola: el impacto mostraba recetas de otro precio de la misma tanda, y un precio sin efecto heredaba la suba de otro.
- **`security-auditor`:** apto. Resuelto: las funciones mostraban nombres de recetas que la persona ya no ve, y el estado de la cola contaba pedidos de otros locales.
- **`ui-reviewer`:** resueltos los graves: fecha de los datos, tarjetas con estado y comparación, y errores que se veían como datos vacíos. También unidades en español y etiquetas.

## PR 3A: costos al día (2026-11-04)

Migración `20261114120000_costs_up_to_date.sql`.

- **Tarea diaria (3:30 de la Argentina):** anota los precios que empiezan a valer, con hasta una semana de margen, y el recálculo de todas las recetas publicadas. Cubre "desactualizado", los cambios de plazos y de categoría, y las asignaciones que vencen.
- **Foto de fin de mes (último día, 23:30 de la Argentina):** una foto de cada receta en cada local abierto, aunque nada haya cambiado, con los precios de ese mes. Si no corrió o falló, la tarea diaria la saca en la primera semana del mes siguiente, con los precios de ese día.
- **Recálculos fallidos:** sin botón ni permiso nuevo. Si el recálculo completo del grupo sale bien, se cierran los fallidos anteriores, salvo una foto de fin de mes. El error queda guardado. Un fallido de un local cerrado se pone al día recién al reabrir.
- **Aviso de cambio de costo:** `recipe_cost_changed`, una vez recalculada una publicación, a quien ve costos y recetas en esos locales. Dice cuántas recetas de sus locales cambiaron. **Sin importes ni porcentajes** (cambio contra el plan): el aviso es igual de útil, y un porcentaje mezclaría locales que la persona no ve, seguiría visible al perder el permiso y quedaría en la auditoría. El número se ve en `/costos`. Si nada cambió, no avisa, y si falla, no frena el recálculo.
- **`integration.integration_outbox`:** `cost.changed`, `price.approved` y `recipe.published`, con ids y estados, sin importes. No se expone por la API y nadie la consume todavía. Como la cola, no pasa por la auditoría: repite cambios ya auditados, y hoy no se limpia.
- **Pruebas:** `235_costs_up_to_date` (49).

## PR 3B: escalado (2026-11-04)

Migración `20261115120000_recipe_scaling.sql`.

- **`/recetas/[id]/escalar`:** cuánto hace falta para un lote, por porciones o por la unidad del rendimiento. Lo ve cualquiera que vea la receta, también la cocina. Se puede imprimir.
- **Escalar nunca cambia la versión:** `recipes.scale_version` solo lee. Tampoco guarda nada: el módulo de producción no existe, y una versión nueva se hace con el flujo de siempre.
- **Las líneas "no escalar"** se muestran aparte y quedan como en la receta.
- **`recipe_steps.equipment_capacity` y su unidad:** cuánto entra en el equipo de ese paso. La unidad es la del rendimiento al cargarla, y va guardada porque el rendimiento puede cambiar. No hay `batch_size`, como decía el plan de la Fase 2: el lote ya es el objetivo. Con eso sale el aviso de "más tandas", comparando contra el rendimiento terminado. Los tiempos no se multiplican.
- **"1.500" son mil quinientos,** como se ve en pantalla (`parseAmount`; confirmado por Joaco el 2026-11-04). "2,5" y "2.5" son dos y medio. Lo demás se rechaza con un aviso.
- **En la hoja impresa** no salen el costo, el menú ni el formulario, y sí la versión y la fecha.
- **El editor de pasos** ahora pide equipo y capacidad.
- **`costing.scaled_cost`:** el costo proyectado, con su confiabilidad, solo para quien ve costos. Cada línea por el factor, salvo las "no escalar". Las líneas "no escalar" de una preparación escalan con ella.
- **Pruebas:** `236_recipe_scaling` (48), `tests/unit/scaling.test.ts` (8) y Playwright `escalado`.

## PR 3C: escenarios (2026-11-04)

Migración `20261116120000_cost_scenarios.sql`.

- **Un escenario es de un local** y guarda solo los cambios: precio, rendimiento y gramaje. El resultado se calcula al abrirlo, con los datos de hoy, y no se guarda. Así no se puede confundir con un costo oficial.
- **Nunca toca lo oficial:** `costing.scenario_result` es `stable`, y Postgres rechaza una escritura directa desde una función así. Tampoco llama a ninguna que escriba. La prueba `237` compara el costo vigente, las fotos, la cola y los eventos antes y después.
- **Un proveedor se simula como un precio.** El proveedor queda como referencia y no calcula nada: hacerlo de otra forma exigiría precios cargados de alguien a quien todavía no se le compra.
- **El precio simulado es el que cuenta en ese local:** sin IVA, o con IVA si el local no lo descuenta. Reemplaza al costo sin IVA y al costo con IVA por igual, así que un escenario no simula el IVA.
- **El precio se escribe por kg o por litro,** como se ve en costos, y se guarda por unidad de uso. La acción convierte con la unidad que dice la base, no con un dato del navegador.
- **El motor** lee `yields` y `quantities` de `p_memo`. Sin esas claves da lo mismo que antes. La recursión las pasa a las preparaciones, también a las que la persona no ve.
- **Un gramaje ajusta la cantidad congelada** en la misma proporción: no se vuelve a convertir con la densidad de hoy.
- **Un gramaje de una versión vieja** queda en el escenario, con un aviso, y no se aplica.
- **Las tarjetas** (mayor suba y mayor baja) miran todas las recetas, no solo las de la página.
- **Quién lo usa:** `scenarios.manage` y `recipes.view_costs` en el local. Hoy, Dirección General, Director de Marca y Controller.
- **Lo simulado nunca dice verificado:** un precio simulado no es verificable, aunque el motor marque la receta como completa. La pantalla usa etiquetas propias (`SCENARIO_RELIABILITY`), sin el estado verde.
- **Un precio simulado completa una receta:** si a una receta le faltaba un precio y se simula, el resultado sale con costo. Es lo que se quiere saber.
- **El local también va en cada cambio** (`restaurant_id`): la auditoría toma de ahí el alcance. Sin eso, quien audita un local no vería los cambios.
- **Lo que la persona ya no ve se tapa** en `scenario_changes` ("No disponible"): el cambio queda, para poder quitarlo. Una línea solo se carga si la receta se ve.
- **Cambio contra el plan:** no hay `owner_id`. El dueño es `created_by`, que ya pone la base.
- **Medido** en `233`: 410 ms con las 300 recetas alcanzadas, y 534 ms con una materia prima que solo tienen los 270 platos. Las preparaciones que no cambian se calculan una sola vez, como en el recálculo. Se calcula entero en cada página, aunque muestre 50.
- **Pruebas:** `237_cost_scenarios`, `233` (dos pruebas nuevas), `tests/unit/scenarios.test.ts` y Playwright `escenarios`.

## Riesgos y pendientes

- **Los costos pueden tener hasta 1 minuto de demora.** Después de aprobar un precio, una pantalla puede mostrar el costo anterior. La pantalla del PR 2 lo tiene que aclarar.
- **Si un error se repite 3 veces,** ese pedido queda sin procesar. `/costos` avisa. El aviso se va cuando el recálculo diario sale bien; el de una foto de fin de mes, cuando sale otra foto.
- **Casi todo puede salir "con estimaciones":** un precio heredado cuenta como estimación (caso 21). Si los precios se cargan a nivel grupo, cada local los hereda. Hay que mirarlo con datos reales.
- **Las validaciones de publicación no siguen variantes.** El motor se protege (círculos y unidades), pero una variante mal armada se publica igual y queda incompleta. Conviene validarlo al publicar.
- **`recipe_cost_current` no está en plural,** como pedía el plan de la Fase 2.
- **Al impacto de un precio le puede faltar alguna receta** si otro recálculo lo tomó antes que su propio pedido (por ejemplo, si el pedido falló). Nunca atribuye de más. Es poco frecuente.
- **Falta medir `price_impact` con `explain analyze`** en el escenario grande. La lista de un local sí está medida.
- **Se puede perder un aviso:** si una publicación falla 3 veces y la cierra el recálculo diario, el costo queda bien pero el aviso no sale. Si falla el aviso mismo, solo queda en el log de la base.
- **Dos publicaciones en la misma corrida** pueden mezclarse en el aviso: el nombre de una variante de un local puede llegarle a quien ve recetas en otro. Nunca lleva costos.
- **La cola y los eventos no se limpian.** Se revisa con datos reales.
- **Si el cron no corre,** los costos no se ponen al día y nada lo avisa, salvo la última actualización de `/costos`.
- **La capacidad se carga receta por receta,** y las recetas publicadas no la tienen: hay que cargarla en una versión nueva. Un catálogo de equipos sería mejor, pero es otro módulo.
- **El escalado es lineal:** condimentos y levaduras no siempre escalan igual. Para eso están las líneas "no escalar".
- **Las fotos crecen** con cada cambio de precio: 1.200 filas y unas 11.000 líneas en el peor caso medido. Se revisa con datos reales.
- **La historia de costos de un local nuevo:** quien entra hoy lee todas las fotos de totales de su local. Las líneas, solo de las versiones que ve.
- **`core.audit_history`** destapa valores con `recipes.view_costs`, no con `prices.view`. Hoy no se explota (ADR-0029): ningún rol con `audit.view` deja de ver precios.
- **La cola no se limpia:** guarda los pedidos procesados. Se revisa con datos reales.
- **Un escenario se calcula entero al abrirlo:** con muchas más recetas que las 300 medidas, puede tardar. Si pasa, se limita por página.
- **El costo de hoy es el guardado, y el simulado se calcula al abrir:** con un precio nuevo todavía en la cola, un cambio sin efecto puede mostrar diferencia hasta que la cola lo procese (un minuto, o más si el pedido falló).
- **Un rendimiento simulado alcanza solo a las líneas con limpieza o cocción.** Las demás recetas que usan esa materia prima aparecen con diferencia cero.
- **Sin tope de trabajo en `recipe_cost`:** sin memo, repite las preparaciones. Con recetas normales no se nota; falta medirlo con datos reales.
- **Quien tiene varios locales y ninguno elegido** no ve costos en `/recetas`: los ve en `/costos`.
- **La bandeja de aprobaciones** oculta importes por nombre de clave: un Chef o un Jefe de Cocina con `approvals.view` ve el producto, el proveedor y el comprobante de una solicitud de precio. Coincide con la decisión 1, salvo el comprobante.
