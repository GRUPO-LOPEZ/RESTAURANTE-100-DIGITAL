# Facturas (lista de cambios para Soy)

Quinta entrega del módulo de compras y facturas (Fase 3), en dos partes: **la base** (lo que el sistema controla y guarda) y **las pantallas**. Detalle técnico en ADR-0058.

## Qué cambia

- **El costo de cada materia prima sale de la última factura conforme** (tu decisión 2). Ya no hace falta cargar el precio a mano y que lo apruebe el Controller.
- **Compras carga la factura** desde las órdenes recibidas. Las líneas salen solas de lo que llegó, con el precio de la lista vigente a la fecha de la factura, y se ajustan a lo que dice el papel. La foto (o el PDF) es obligatoria.
- **El sistema la controla sola, contra la orden, la recepción y la lista:**
  - **cantidad:** lo facturado contra lo recibido. Lo que va por kilo se compara en kilos, con un 0,5 % de margen;
  - **precio:** contra la lista vigente a la fecha de la factura, sin margen. En A se compara sin IVA; en B, C, X y nota a mano, el precio final;
  - **artículos reconocidos:** uno nuevo va a la lista del chef para que diga qué materia prima es;
  - **totales:** las líneas, el IVA, los impuestos internos y las percepciones suman el total;
  - **razón social:** la factura está a nombre del local que recibió.
- **Si todo cierra, queda conforme y liberada a pago, sola** (salvo que la controle quien cargó o aceptó la lista: ver «Doble control»). Su precio pasa a ser el costo y las recetas del local se recalculan.
- **Si algo no cierra, queda observada**, con el motivo en simple, y Compras recibe un aviso.
- **Una nota de crédito o un descuento que cubre la diferencia la deja conforme.** El costo queda con el precio de la lista, porque es lo que se terminó pagando.
- **Si sigue sin cerrar, la da por conforme a mano otra persona**, distinta de quien la cargó (tu decisión, la 2 sobre facturas), con un motivo: el Controller o alguien de Compras. Lo controla la base, no la pantalla.
- **Una factura sin orden ni recepción** (un flete, un servicio) nunca queda conforme sola: siempre la da otra persona.
- **Si un precio sube o baja más del 15 %**, entra igual y Dirección recibe un aviso con el precio de antes, el de ahora y la diferencia (tu decisión 1).

## Doble control (decisiones de Joaco, 2026-11-18)

- **Quien carga o acepta la lista de precios de un proveedor no deja conformes solas sus facturas:** la factura queda observada y la da otra persona (por ejemplo, el Controller). Así nadie fija un costo sin que otra persona lo mire. Con una sola persona en Compras, el Controller da por conforme las facturas.
- **Nadie da por conforme una factura que cargó o corrigió**, ni una a la que le sumó una nota.
- **Compras entra con doble verificación** (código del celular), como el Controller, porque ahora carga facturas que cambian costos. La primera vez que entre después de este cambio, el sistema le pide registrarla.
- **Una nota de crédito cuenta recién con su foto.**
- **No se factura dos veces la misma mercadería:** una orden facturada entera no se vuelve a facturar, y lo ya facturado se descuenta.
- **No se cargan facturas con fecha futura,** y un precio de factura no cambia costos de días pasados.

## Qué controla el sistema

- **El CUIT de la factura tiene que ser el del proveedor.** Una factura con un CUIT de ejemplo (99-99999999-9) o sin CAE no se guarda.
- **No se carga dos veces la misma factura:** mismo proveedor, clase, punto de venta y número.
- **Una factura conforme no se cambia.** Se corrige con una nota de crédito o débito. Una cargada por error se cancela, con motivo, y queda en la historia.
- **Lo que no es costo de la materia prima no entra al costo** (tus decisiones 4 y 5): impuestos internos, percepciones, flete, servicios y regalos.
- **En A, el costo va sin IVA** (con razón social responsable inscripta). **En B, C, X y nota a mano, el costo es el precio final.**
  - Ejemplo: una bolsa de 50 kg a $ 60.500 da $ 1.000 el kilo en una A y $ 1.210 el kilo en una B.
- **El cocinero y el chef no ven facturas.** El gerente ve las de su local, sin poder cambiarlas.
- **Se suman las alícuotas de 2,5 % y 5 %** (tu respuesta P5), también al cargar un precio a mano.

## Las pantallas (segunda parte)

- **«Facturas»**, en el grupo Compras del menú. La ven Compras, el Controller, Dirección y los gerentes (solo las de su local, sin cambiarlas). El cocinero y el chef no.
- **El listado:** pestañas por estado (cargadas, observadas, conformes, pagadas, canceladas), filtros de proveedor y fecha, y qué no pasó en cada una.
- **«Nueva factura»:** se elige el proveedor y las órdenes recibidas que cubre; se escriben el número, la fecha y el CAE. Las líneas salen solas de lo que llegó, con el precio de la lista.
- **La ficha de la factura, en una pantalla:**
  - arriba, el total, la diferencia contra lo recibido, la diferencia contra la lista y el vencimiento;
  - los datos y el pie, las líneas como planilla (con ✓ o ✕ y la explicación) y «Todo junto»: la foto, la orden y su recepción, los controles y las notas;
  - se corrige donde se ve y se guarda todo junto, con un motivo;
  - los botones **Controlar**, **Dar por conforme** y **Cancelar**.
- **En el celular** se consulta, y se puede dar por conforme.
- **El origen del precio:** en la ficha de cada materia prima y en Costos se ve de qué factura salió el precio («Factura A 0003-00012345 · Proveedor»). Se abre con un clic.
- **Capturas:** `docs/capturas/facturas/`.

## Lo que todavía no está

- **Los pagos y el tablero de compras** (Prompt 6).

## Para probar en staging

Las facturas de prueba están en **Demo Parrilla Centro**, todas inventadas:

- dos conformes, una A y una B;
- una que quedó conforme con una nota de crédito;
- dos observadas, una por precio y otra por un artículo que el sistema no reconoce;
- una con impuestos internos y percepción, sin orden;
- una por peso, un comprobante X y una nota a mano, cargados.

Se ven en **Compras → Facturas**, con el local elegido arriba.
