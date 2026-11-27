# Facturas y orden de pago: lista de cambios (PR C)

Resumen para Soy, en simple. La decisión técnica está en [ADR-0070](../decisiones/0070-orden-de-pago-cajas-y-cae-al-controlar.md).

## Facturas

- **Cargar una factura es más corto.** Se elige el proveedor, el comprobante con un botón (Factura A, Factura B, Factura-remito A u «Otro»), el punto de venta y el número. La foto es opcional.
- **La fecha y el CAE ya no se piden al cargar.** La fecha arranca en hoy y el CAE se completa en la ficha. El sistema no deja controlar una factura sin CAE.
- Si el proveedor tiene una orden recibida, se avisa y las líneas salen de ahí.
- **El listado responde «¿Qué facturas hay para revisar y pagar?».**
  - Arriba hay tres botones: Observadas, Para dar conforme y Vencidas.
  - «Para dar conforme» muestra solo las que te toca decidir a vos: las que no cargaste.
  - Los demás estados van en un desplegable. «Cancelada» ahora se llama «Anulada».
  - La fecha se elige con Este mes, El mes pasado u Otras fechas.
  - Hay una columna nueva, Vence.

## Pagos

- **Cada pago es una orden de pago con número**: OP-0001, OP-0002…, por razón social.
- **En una orden se pueden combinar hasta 5 medios**: efectivo, transferencia, cheque propio, cheque de terceros, e-cheq o tarjeta.
- **Cada medio dice de dónde sale la plata**: qué caja, qué cuenta del banco o qué tarjeta de la razón social.
- **La transferencia muestra la cuenta completa del proveedor** (banco, titular, CUIT, CBU y alias), para no equivocarse.
- **Los cheques llevan** número, banco y fecha de cobro. Si son de terceros, también quién los libró.
- **Lo que se paga se reparte solo** entre las facturas, empezando por la que vence antes. Lo que sobra queda a cuenta del proveedor.
- **Las retenciones ya tienen su lugar**, en $ 0, hasta definir cómo se calculan.
- **Al registrar el pago se abre la orden**, que se puede imprimir o compartir. Lleva la versión y quién la registró.
- Se puede anular, con motivo. No se borra.
- **Pagos tiene una pestaña nueva, «Órdenes de pago»**, con todas las órdenes.

## Razón social

- **La ficha tiene una tarjeta nueva, «Cajas y cuentas»**: las cajas, las cuentas bancarias y las tarjetas de las que sale la plata.
- **Las carga quien administra el grupo.** Se agregan, se cambian y se dan de baja juntas, con un motivo.

## Lo que queda para después

- Calcular las retenciones (falta definir la regla).
- Pagar por adelantado a un proveedor que todavía no tiene facturas.
- La cartera de cheques de terceros.
