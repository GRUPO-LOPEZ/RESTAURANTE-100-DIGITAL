# ADR-0060: Pagos, cuenta corriente y Tablero de compras

- **Fecha:** 2026-11-19
- **Estado:** plan aprobado por Joaco el 2026-11-18. Último PR de la Fase 3 (Prompt 6).
- **Sigue a:**
  - ADR-0049: alcance de la Fase 3;
  - ADR-0053: órdenes de compra y la cola de mensajes;
  - ADR-0056: recepción (el efectivo que se paga al recibir);
  - ADR-0057: menú con grupos plegados;
  - ADR-0058: facturas.

## Problema

Con las facturas conformes en la base faltaba cerrar el circuito **pedido → recepción → factura → pago**: registrar lo que se paga, saber cuánto se le debe a cada proveedor y qué vence, avisar los vencimientos, y darle a Dirección y a Compras un tablero que diga qué hay que atender.

## Decisiones de Joaco (2026-11-18)

1. **Menú:** «Tablero de compras» (`/compras`) y «Pagos» (`/compras/pagos`) suman dos accesos. Contraído, los íconos bajan a 28 px si los de 32 no entran (`collapsedIconSize`: 36, 32 o 28). Es el último escalón: el próximo módulo que sume accesos tiene que plegar por grupos también contraído.
2. **El efectivo al recibir** (decisión 7 de Soy):
   - la recepción que anota `cash_paid_amount` crea un pago «para confirmar» (`to_confirm`);
   - Compras lo confirma (con el importe corregido si hace falta) y queda **a cuenta** del proveedor en ese local;
   - cuando la factura de esa recepción queda conforme, el pago a cuenta se aplica solo, hasta su saldo; lo que sobra sigue a cuenta.
3. **Un pago, un local.** Una transferencia que paga dos locales se registra como dos pagos con la misma referencia.
4. **Sin segunda firma** para los pagos: los registra Compras (`purchasing.pay`), con motivo y auditoría.
5. **Una nota de crédito que llega tarde** (con la factura ya pagada): lo que sobra queda a cuenta, y la factura vuelve a «liberada» solo si le queda saldo.
6. **Los importes del tablero** los ve quien ve pagos (`purchasing.view_payments`), también el superadministrador. El chef ejecutivo ve el tablero sin importes ni las alarmas de plata.

Ya decididas: las retenciones quedan fuera (P8; columna `withholding_amount` preparada), y el comprobante al proveedor queda en cola en `outbound_messages` (decisión 9; nadie lo despacha todavía).

## Cómo se hizo

- **Tablas:** `purchasing.payments` y `purchasing.payment_allocations`, con RLS por `purchasing.view_payments` en el local, auditoría, `reject_truncate` y borrado lógico. Un pago registrado no se edita: se anula con motivo.
- **El saldo nunca se guarda.** `purchasing.invoice_balance(id)` = total − notas de crédito − descuentos + notas de débito − pagos aplicados. Lo usan las funciones que pagan, las vistas y la ficha de la factura (`purchasing.invoice_payments`): la pantalla no lo recalcula.
- **Pagar de más no puede pasar**, ni con dos pagos a la vez: `guard_payment_allocation` bloquea el pago y la factura (`for update`) y rechaza lo que pase el saldo de la factura o el importe del pago. Una factura que llega a 0 pasa a «pagada» en la misma transacción.
- **El efectivo se cuelga de triggers** (`on_receipt_closed`, `on_invoice_released`) en vez de copiar `close_receipt` y `release_invoice`: las pruebas de recepción y facturas siguieron en verde sin cambios.
- **Avisos:** `notify_due_payments()` avisa una vez por factura a 7 días y al vencer, a quien tiene `purchasing.pay` en el local. Corre con el trabajo diario de compras.
- **Lectura:** las vistas `security_invoker` viven en `reporting` (que no está en la API) y las leen funciones `security definer` de `purchasing`, como Calidad: `payment_schedule_list`, `cash_to_confirm`, `payable_invoices`, `supplier_account`, `invoice_payments` y `purchasing_dashboard`.
- **La cuenta corriente en la ficha del proveedor** no es una tarjeta nueva (la ficha no tiene scroll, ADR-0046): el indicador «Saldo de cuenta corriente» lleva su estado con palabra y «Ver la cuenta corriente», que abre los movimientos con el saldo acumulado y el saldo que informó el proveedor.
- **Cómo subieron los insumos:** variación en % desde el primer precio de los últimos 90 días, de las 4 materias primas que más se compran. En pesos, los insumos caros taparían a los baratos. Solo entran las que tienen al menos dos precios en el período: con uno solo, la línea es un punto que no dice nada.
- **El Tablero de compras (`/compras`) es la pantalla actual solo en su dirección**, como el Inicio: si no, se marcaba junto con Pagos, Facturas y las demás pantallas de compras (hallazgo grave de `ui-reviewer`).

## Revisiones (migración 170000 y pantallas)

- **Un solo orden de bloqueo en todo pagos: primero las facturas (por id), después el pago.** Liberar una factura y agregar una nota ya lo hacían así, porque el trigger corre con la factura bloqueada. Confirmar el efectivo, aplicar lo que estaba a cuenta y anular iban al revés, y dos personas a la vez podían trabarse (`db-reviewer`, medio).
- **Un solo umbral para «saldada»: hasta medio centavo (0,005).** Los importes van con 4 decimales y se pagan con 2: una factura de $ 1.000,1234 pagada con $ 1.000,12 queda pagada en todos lados, también en `guard_invoice` y al sumar una nota (`db-reviewer`, medio).
- **Una nota de crédito que deja saldo a favor y no tiene pagos que devolver a cuenta se rechaza.** Si no, la factura quedaba pagada con saldo negativo y la cuenta corriente mostraba un número sin explicación.
- **La cuenta corriente, en el mismo día, pone primero la factura, después las notas y al final el pago** (`purchasing.movement_rank`). La ficha la muestra en el orden inverso exacto del saldo acumulado: el movimiento de arriba lleva el saldo final. Se vio en la captura: con dos movimientos del mismo instante, el saldo y la lista desempataban distinto.
- **`invoice_payments` decide el permiso con `purchasing.can_in_restaurant`**, como el resto de compras (descarta los locales dados de baja).
- **Las lecturas sin permiso devuelven nulo y no quedan en el historial**, igual que las otras lecturas de compras. El rechazo de una escritura sí queda (`core.deny`).
- **Anotado, sin cambio:**
  - el chef ve cuántas facturas vencen y cuáles (proveedor, número y fecha) sin importes: es lo que pide el plan («el tablero sin importes»). Si Soy lo considera reservado, se corta en la base;
  - el comprobante se sube después de guardar el pago: si no se puede registrar, el archivo se borra de Storage.

## Rendimiento (caso 34)

Con 500 facturas y 5.000 líneas generadas en la prueba (`391_purchasing_dashboard`), cada lectura queda por debajo de 300 ms. Medido en la base local (`clock_timestamp`, sesión de Compras):

| Lectura                          | Tiempo                     |
| -------------------------------- | -------------------------- |
| `purchasing_dashboard(un local)` | 16 a 18 ms (tres corridas) |
| `payment_schedule_list('due')`   | 3 ms                       |

No hizo falta una vista materializada. Si con datos reales alguna lectura pasa de 300 ms, `v_purchase_spend` es la primera candidata (con refresco diario).

## Riesgos

- Toca dinero: el saldo sale siempre de las tablas y las funciones bloquean lo que tocan.
- El menú contraído llegó a su último escalón (28 px).
- El comprobante al proveedor queda en cola hasta que exista quien lo despache.
