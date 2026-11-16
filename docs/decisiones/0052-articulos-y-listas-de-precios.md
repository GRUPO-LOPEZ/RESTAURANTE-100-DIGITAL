# ADR-0052: Artículos de proveedor, cola de mapeo y listas de precios

- **Fecha:** 2026-11-16
- **Estado:** plan aprobado por Joaco el 2026-11-15; «Quién mapea» decidido por Joaco el 2026-11-16.
- **Pedido:** Prompt 2 de `docs/prompts/2026-11-14-facturas-modulo-2.md`.
- **Sigue a:** ADR-0049 (alcance del módulo), ADR-0050 (ficha de proveedor), ADR-0041 (códigos automáticos), ADR-0038 (rubros).
- **Migraciones:** `20261203110000_price_list_kinds.sql` (los dos avisos nuevos) y `20261203120000_price_lists.sql`.

## Respuestas que se aplican

- **P2 (Joaco):** «va a recetas» es una columna del rubro de compra de primer nivel.
- **P5 (Soy):** alícuotas de IVA de 0; 2,5; 5; 10,5; 21 y 27 %.
- **P6 (Soy):** la bonificación en pesos es por unidad y se resta después de los porcentajes.

## Base

- **Un artículo de proveedor es un producto de compra** (`catalog.purchase_products`), con el código del proveedor (`supplier_sku`, único por proveedor), si se factura por peso y el peso estimado por unidad. No hay otra tabla.
- **Reconocer un renglón** (`purchasing.match_article`): primero por proveedor y código; si no, por proveedor y nombre normalizado (mayúsculas, sin acentos, sin puntos, con un solo espacio). Mira el producto y sus otros nombres (`purchasing.article_aliases`).
- **Cola de mapeo** (`purchasing.unmapped_articles`): un solo pendiente por proveedor y nombre. Se resuelve de tres formas, cada una en una transacción y con motivo:
  - `resolve_article`: crea el producto de compra del proveedor con su envase. Los renglones de lista que esperaban pasan al producto;
  - `link_article` («Es el mismo que…»): el proveedor renombró un producto. El nombre y el código nuevos quedan como otro nombre;
  - `discard_article`: no se usa.
- **Código del producto nuevo:** el de la materia prima más `-P01`, `-P02`… Los productos de compra se cargaban con el código a mano; los de la cola necesitan uno automático.
- **Listas** (`purchasing.price_lists` y `price_list_items`):
  - estados: recibida, aceptada y reemplazada. Una sola aceptada por proveedor (índice único);
  - aceptar es una transacción: la anterior pasa a reemplazada. No se acepta una lista más vieja que la vigente;
  - el neto es lista × (1 − b1) × (1 − b2) − bonificación en pesos (`purchasing.net_list_price`; caso 5: 76,50);
  - **los precios de lista nunca son costos:** no se escribe en `costing.price_records` (caso 10, probado).
- **«Vencida» se calcula, no se guarda:** una lista aceptada vence a los 7, 15 o 31 días de su vigencia según la frecuencia de la ficha, con la fecha de la Argentina. Una semanal vigente desde el lunes vence el lunes siguiente (caso 7, con el borde probado). Sin frecuencia, no vence.
- **Aviso de vencida:** `purchasing.notify_expired_price_lists`, una vez por lista, a Compras. Va en un trabajo propio (`grupo-lf-compras-diario`, 06:45 de la Argentina) para no tocar el recálculo de costos (ADR-0032).
- **Aviso de la cola:** uno por carga (no uno por artículo), a quien mapea.
- **Rubros que no van a recetas:**
  - Limpieza (MP-LIM) y Descartables (MP-DES) nacen con «no va a recetas», también en grupos nuevos (trigger);
  - una línea de receta nueva con una materia prima de esos rubros se rechaza. **Lo que la receta ya usaba sigue:** sus versiones nuevas lo copian;
  - el buscador de componentes no las ofrece.
- **Adjuntos:** bucket privado `purchasing-documents` (fotos y PDF) con carpetas `<grupo>/price_lists/<lista>/`. `purchasing.attachments` es solo de inserción. Sube quien carga listas; lee quien ve listas, solo archivos registrados.
- **Variación:** `reporting.v_price_list_changes` (`security_invoker`). La app la lee por `purchasing.price_list_changes`, que controla el permiso, porque el esquema `reporting` no está abierto a la app.

## Permisos

| Permiso                         | Sensible | Roles                                                               |
| ------------------------------- | -------- | ------------------------------------------------------------------- |
| `purchasing.view_price_lists`   | no       | Compras, Controller, Dirección, Director de Marca, Gerente, Auditor |
| `purchasing.manage_price_lists` | sí       | Compras                                                             |
| `catalog.map_articles`          | no       | Chef Ejecutivo y Jefe de Cocina                                     |

- El superadmin suma los tres por la regla G2, como en ADR-0050.
- El cocinero no ve listas ni la cola. La Chef no ve listas de precios, pero sí la cola.

## Quién mapea (decisión de Joaco, 2026-11-16)

Mapear crea un producto de compra, que es de **todo el grupo**. Joaco decidió que la cola la resuelvan también los chefs de una marca y de un local, no solo los de todo el grupo:

- alcanza con tener `catalog.map_articles` en cualquier alcance del grupo (`purchasing.can_map_articles`). Es una excepción a la regla de que un cambio de todo el grupo pide el permiso para todo el grupo, decidida para este caso;
- el producto nuevo queda para todo el grupo igual, y cada resolución queda en la auditoría con su motivo;
- el aviso de artículos nuevos llega a todos los que pueden resolver;
- por la regla G2, el Director de Marca y el Gerente también tienen el permiso (administran a los chefs), así que también pueden resolver.

## Pantallas

- **Ficha de proveedor:** el indicador «Lista de precios vigente» muestra la fecha y el estado (Al día, Vencida o Sin datos). Tiene «Ver la lista» o, si no hay, «Cargar lista». No suma una tarjeta: la ficha tiene que entrar en 1715 × 843 (ADR-0051).
- **`/listas-de-precios`** (tipo C, en Gestión y análisis): filtro por proveedor y estado como botones, la tabla y 15 por página.
- **`/listas-de-precios/[id]`:** los artículos con el neto y la variación; «Aceptar» con motivo.
- **`/listas-de-precios/nueva`:** proveedor, fechas, archivo opcional y la grilla. **Es una pantalla y no un panel:** la grilla necesita el ancho de la computadora.
- **`/materias-primas/sin-mapear`:** la cola. Se llega con «Artículos sin mapear (N)» desde Materias primas. «Mapear» abre una ventana corta con tres opciones y el factor en palabras antes de confirmar («1 bolsa = 50 kg»).
- **`/rubros`:** «Va a recetas» como sí/no de un clic en los rubros de compra. El motivo queda fijo («Desde Rubros: …»), como el cambio de nombre.

## Revisiones (2026-11-16)

`db-reviewer` y `security-auditor`: sin hallazgos graves. Se corrigió:

- **Las variantes:** una variante de una receta que ya usaba una materia prima de Limpieza o Descartables no se podía crear. Ahora vale lo que usaba la maestra. Solo cuentan las líneas vigentes.
- **Un artículo descartado no vuelve a la cola:** si llega otra vez, el renglón queda con ese artículo y no se avisa al chef. Se puede revisar si Joaco prefiere otra cosa.
- **«En la cola» cuenta solo lo pendiente.**
- **Rechazos:** «Va a recetas» y la cola registran siempre el rechazo (`core.deny`), con su grupo.
- **El historial** oculta precios, bonificaciones, IVA y observaciones de las listas a quien no tiene `purchasing.view_price_lists`, aunque vea costos (`core.hide_payment` se amplió).
- **`price_list_expired`** responde solo por listas que la sesión ve. El aviso diario usa la versión interna.
- **Archivos:**
  - se suben solo a listas recibidas, y cada archivo tiene que ser de quien lo sube y lo registra;
  - quien carga listas puede leer su carpeta, para que Storage pueda guardar;
  - `attachments.source_id` no tiene clave foránea porque va a apuntar a varias tablas (listas, facturas, recepciones). El grupo y la lista los controla `add_price_list_attachment`, el único camino de escritura.
- **Controles:** una lista no llega en una fecha futura; un número fuera de rango y el mismo artículo dos veces en una lista dan un mensaje claro; hay índices para las claves foráneas.
- **El seed** suma 2 materias primas (Limpieza y Descartables): quedan 52.

Quedan anotados:

- **Lista con vigencia futura (decisión de Joaco, 2026-11-16):** se puede aceptar cuando llega y pasa a ser la vigente al instante; la anterior queda reemplazada. No toca costos y la fecha «vale desde» se ve. Si pasa seguido, se puede activar sola el día que empieza a valer.
- la vista previa de la ficha de receta no avisa todavía «no va a recetas»: lo dice al guardar, porque el buscador ya no ofrece esas materias primas.

## Decisión posterior de Soy (2026-11-16)

- **Compras ve el precio del local elegido (decisión posterior de Soy, 2026-11-16).** Llegó cuando este prompt ya estaba fusionado (PR #76), así que se resolvió aparte, antes de Facturas (Prompt 5). Compras ve en la ficha de materia prima el precio del local que elige arriba, sin ver los costos de las recetas. La ficha toma el local de los precios con `prices.view` y el de los costos con `recipes.view_costs`, cada uno por su lado. La base ya lo permitía: no hubo migración.

## Límites conocidos

- **El archivo de la lista viaja por una acción de servidor,** que acepta hasta 4 MB por envío (`next.config.ts`). La pantalla pide hasta 3,5 MB; el bucket ya acepta 10 MB para cuando se suba directo desde el navegador.
- **La grilla se carga a mano.** Pegar desde una planilla queda para después.
- **Las listas no se editan:** una lista mal cargada se reemplaza con otra.
