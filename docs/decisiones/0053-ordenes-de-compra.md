# ADR-0053: Orden de compra con numeración por local, aprobación y envío en cola

- **Fecha:** 2026-11-16
- **Estado:** plan aprobado por Joaco el 2026-11-16.
- **Pedido:** Prompt 3 de `docs/prompts/2026-11-14-facturas-modulo-2.md`.
- **Sigue a:** ADR-0049 (alcance del módulo), ADR-0050 (proveedores), ADR-0052 (artículos y listas), ADR-0029 (cómo se arma una aprobación) y ADR-0041 (contadores).
- **Migraciones:** `20261204110000_order_news_kind.sql` (el aviso `order_news`) y `20261204120000_purchase_orders.sql`.

## Decisiones que se aplican

- **Soy, decisión 3:** una OC que requiere aprobación la aprueba Compras, en el alcance del local, y nunca quien la pidió.
- **Soy, decisión 9:** el mensaje queda en cola; nadie lo despacha todavía. La pantalla dice «En cola de envío» y muestra el texto, para copiarlo y mandarlo a mano mientras tanto.
- **P3:** un local sin código no puede pedir. «Nueva OC» dice «Falta el código del local» y enlaza al Panel de control.

## Base

- **Tablas nuevas (`purchasing`):**
  - `purchase_orders`;
  - `purchase_order_lines`, cada una con un artículo del proveedor **o** una materia prima «sin nombre de factura»;
  - `purchase_order_events`, las novedades;
  - `outbound_messages`, la cola de envío.

  Todas con columnas de control, auditoría y RLS. **Sin precios:** `unit_price` y `price_list_item_id` quedan preparados y vacíos.

- **Numeración:** el código del local + «-» + 4 cifras («PCE-0001»), con `catalog.next_code`.
  - El `update … returning` bloquea el contador hasta el commit: no repite aunque dos personas pidan a la vez, y si la transacción falla el número vuelve.
  - El número queda guardado en la OC: si el local cambia de código, las viejas no cambian.
- **Fecha de entrega esperada (`expected_delivery`):** el próximo día de entrega de la ficha **después** del día del pedido, con la fecha de la Argentina.
  - Un pedido del mismo día de entrega va al próximo: lo de hoy no llega hoy.
  - Sin días cargados, da un error claro.
  - Se puede cambiar al pedir; el cambio queda en la auditoría.
- **Ranking (`supplier_product_ranking`):** los artículos del proveedor ordenados por cuántas OC enviadas, o más adelante, de ese local los incluyen. Se calcula desde la historia.
- **«Mandar OC» (`submit_order`):**
  - si el proveedor tiene «requiere aprobación», crea la solicitud `purchasing.approve_order`. En la solicitud van las líneas, así que lo que se aprueba es lo que se pidió. Quien la pidió queda excluido;
  - si no, el mensaje va directo a la cola.
- **Aprobación:**
  - `apply_order_approval` vuelve a validar y encola;
  - si Compras la rechaza, un trigger sobre `workflow.approval_requests` la vuelve a borrador, deja la novedad y avisa a quien la pidió. No se tocó `workflow.decide_approval`;
  - `workflow.check_apply_function` suma el esquema `purchasing` a los permitidos, sin aflojar ninguna otra regla.
- **El mensaje** lleva el número bien visible y el pedido de ponerlo en «Orden de compra», el local, nuestro número de cliente, la entrega y las líneas, con los kg estimados de lo que va por peso («≈ 36 kg»).
- **Novedades y cancelación:**
  - una novedad pasa la OC a «Con novedad» y avisa a quien la pidió;
  - cancelar, antes de recibir, cancela la aprobación pendiente y el mensaje en cola.
- **Lectura:**
  - el cocinero no lee el catálogo de productos (no tiene `catalog.view`);
  - las líneas con sus nombres salen de `order_lines`, que controla que la OC sea de un local que la persona ve;
  - la búsqueda de materias primas para pedir sale de `order_ingredient_search`.

## Permisos

| Permiso                        | Sensible | Roles                                                                                                          |
| ------------------------------ | -------- | -------------------------------------------------------------------------------------------------------------- |
| `purchasing.view_orders`       | no       | Cocinero, Jefe de Cocina, Chef Ejecutivo, Gerente, Director de Marca, Compras, Controller, Dirección y Auditor |
| `purchasing.create_orders`     | no       | Cocinero, Jefe de Cocina, Chef Ejecutivo, Gerente y Compras (y, por G2, el Director de Marca)                  |
| `purchasing.approve_orders`    | sí       | Compras                                                                                                        |
| `purchasing.record_order_news` | no       | Compras y Gerente (y, por G2, el Director de Marca)                                                            |

- El superadmin suma los cuatro por la regla G2.
- La RLS es por local (`permitted_restaurant_ids('purchasing.view_orders')`): el cocinero ve las de su local y Compras, las de todo el grupo.

## Pantallas

- **`/compras/ordenes/nueva`** (celular primero):
  - el proveedor en tarjetas;
  - las cantidades con − / + de 44 px;
  - el buscador, con las materias primas que el proveedor no tiene;
  - la entrega y las observaciones;
  - la barra fija con «Mandar OC» o «Enviar a aprobación».

  Usa el local del selector global.

- **`/compras/ordenes`** (tipo C):
  - pestañas Abiertas, Borradores, A aprobar, Con novedad y Todas;
  - «Mías» como botón y el filtro de proveedor;
  - arriba, las novedades sin leer de mis órdenes.
- **`/compras/ordenes/[id]`:**
  - las líneas y la línea de tiempo;
  - el mensaje al proveedor con su estado;
  - «Mandar OC», «Registrar novedad» y «Cancelar».
- **`/aprobaciones`:**
  - la OC se ve con sus líneas;
  - la sección «Avisos» suma los avisos de compras: cuentas de proveedor (Prompt 1), artículos sin mapear y listas vencidas (Prompt 2), y novedades de una OC. Hasta ahora esos avisos se contaban en la campana pero no se veían en ninguna pantalla.

## Riesgos y límites

- **`catalog.next_code` saltea un número si una receta o una materia prima ya usa ese código exacto** («PCE-0003»). Es improbable con los códigos actuales.
- **Los locales reales no tienen código todavía:** hay que cargarlo en el Panel de control antes de pedir.
- **La cocinera no tiene la bandeja de Aprobaciones:** ve las novedades de sus órdenes arriba del listado de órdenes.
- **«Mandar OC» guarda el borrador y lo manda en dos pasos:** si el envío falla (por ejemplo, el proveedor no tiene canal), el borrador queda guardado y se manda desde su ficha.
