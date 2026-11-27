# ADR-0070 — Orden de pago, cajas y cuentas, y facturas con el CAE al controlar

- **Fecha:** 2026-11-26
- **Estado:** plan aprobado por Joaco (2026-11-26).
- **Pedido:** correcciones de Compras de Soy, parte C (`docs/prompts/2026-11-23-correcciones-compras.md`, decisiones 4 a 11; bocetos `NuevaFactura`, `Facturas` y `Pagos`). Cambia el pago de ADR-0060 y el alta de factura de ADR-0058.

## Decisión

1. **Cada pago es una orden de pago** (`purchasing.payment_orders`):
   - numerada **OP-0001 por razón social** (decisión de Joaco), con `catalog.code_series`;
   - de 1 a 5 medios: efectivo, transferencia, cheque propio, cheque de terceros, e-cheq y tarjeta;
   - cada medio es un pago de los de antes (`purchasing.payments`, con `payment_order_id`). Las aplicaciones, el saldo de la factura, las notas de crédito y el anticipo (lo que queda a cuenta) **no cambian**;
   - `purchasing.register_payment_order` hace todo en una transacción: controla el permiso, las cuentas y los cheques, numera, reparte entre las facturas, deja lo que sobra a cuenta y encola **un** aviso al proveedor;
   - la orden se abre al registrarla, se imprime y lleva «Versión 1 · registrada por … el …» (criterio 14);
   - se anula con motivo (`void_payment_order`) y no se borra. Las facturas vuelven a tener saldo.
2. **De dónde sale la plata:** tabla nueva `org.legal_entity_accounts`, con las cajas, las cuentas bancarias y las tarjetas de cada razón social.
   - **Las carga quien administra el grupo** (`org.manage`), en la ficha de la razón social (decisión de Joaco). En la práctica es la Superadministradora: Dirección no tiene `org.manage`.
   - El efectivo sale de una caja. La transferencia, el cheque propio y el e-cheq salen de una cuenta bancaria. La tarjeta sale de una tarjeta. El cheque de terceros no sale de una cuenta nuestra.
   - Las ve quien administra el grupo o quien paga o ve pagos en un local que factura con esa razón social.
   - Se guardan en lote, con motivo, en una transacción (`org.save_legal_entity_accounts`). El panel tiene su propio contador y su propio «Guardar cambios»: no se suma a la barra de la ficha, porque son dos funciones de la base distintas y cada guardado queda en una sola transacción.
3. **Transferencia a la cuenta completa del proveedor** (banco, titular, CUIT, CBU y alias). La cuenta completa solo la ve quien paga o ve la condición de pago. Los demás ven los últimos 4 números.
4. **Cheques: solo los datos en el pago** (decisión de Joaco). Son número, banco, fecha de cobro y, si es de terceros, el librador. No hay cartera de cheques.
5. **Las retenciones tienen lugar y valen 0** (Ganancias, IVA e IIBB), con `check (= 0)`, hasta que se defina P8.
6. **El CAE se exige al controlar, no al cargar:**
   - `invoices_fiscal_check` pide siempre el punto de venta y el emisor;
   - `invoices_authorization_required_check` pide la autorización salvo en «Cargada» y «Anulada»;
   - `run_invoice_checks` frena con «Cargá la autorización (CAE, CAI o CAEA y su número) antes de controlar.».
7. **El alta corta de factura:**
   - pide proveedor, comprobante (Factura A, Factura B y Factura-remito A como botones; «Otro» abre un desplegable con C, X y nota a mano), punto de venta, número y foto opcional;
   - la fecha arranca en hoy y el CAE va en la ficha;
   - si el proveedor tiene una orden recibida, lo dice y las líneas salen de ahí. Si tiene varias, van todas marcadas.
8. **El listado de facturas:**
   - título «¿Qué facturas hay para revisar y pagar?»;
   - los estados en un desplegable, más botones a la vista para lo que pide hacer algo: Observadas, Para dar conforme y Vencidas;
   - «Para dar conforme» son las observadas que la persona puede dar por conforme y que no cargó ella (doble firma, decisión de Joaco);
   - la fecha se elige con Este mes, El mes pasado u Otras fechas. Lo que pide hacer algo arranca en todas las fechas, porque una vencida del mes pasado sigue pendiente;
   - la columna Vence. La columna Local se saca cuando hay un local elegido arriba;
   - «Cancelada» pasa a «Anulada». Un enlace viejo a `?estado=canceladas` sigue funcionando.

## Opciones descartadas

- **Rehacer pagos como una tabla nueva:** obligaba a rehacer el saldo, la cuenta corriente y las pruebas de ADR-0060. Usar los pagos de antes como medios conserva todo eso.
- **Numerar por grupo o por local:** el comprobante es de quien paga, así que va por razón social.
- **Cartera de cheques de terceros:** se descartó por ahora (decisión de Joaco).
- **Cajas y cuentas dentro del borrador de la ficha:** hacía falta unir dos funciones de guardado de la base, o hacer dos transacciones.

## Revisiones (2026-11-26)

- **Seguridad (un grave, corregido):** se podía emitir una orden a nombre de otra razón social del grupo. Ahora paga solo la razón social del local.
- **Base (un grave, corregido):** se podía anular suelto un medio de una orden. `void_payment` pasó a ser interna (`void_payment_internal`); la nueva, con el mismo nombre, lo rechaza: «Este pago es parte de la orden OP-…: anulá la orden entera.».
- **Medios corregidos:**
  - el cheque de terceros no guarda caja propia, y la base lo exige;
  - las cajas y la razón social llevan clave foránea por grupo;
  - las columnas de control tienen su clave a `core.actors`;
  - «Para dar conforme» usa la misma regla que `approve_invoice`: ni quien cargó, ni quien corrigió, ni quien sumó una nota;
  - una factura fiscal cargada sin CAE no se controla sola al subir la foto de una nota (`check_invoice` envuelve a `check_invoice_internal`);
  - el CBU completo en «Registrar pago» se muestra solo de un proveedor que trabaja con ese local, o a quien ve la condición de pago;
  - «Vencidas» no deja saber el saldo de una factura ajena;
  - el listado de facturas resuelve en línea los estados simples.
- **Pantallas:**
  - los paneles se desplazan adentro;
  - las retenciones dicen «—» con el motivo;
  - una orden anulada no muestra indicadores en verde;
  - «Volver» conserva los filtros;
  - el panel de Pagos cuenta órdenes en su pestaña;
  - «Cancelar» la factura pasa a «Anular»;
  - se suma el botón «Todas las fechas»;
  - los medios tienen los mismos nombres en todo el sistema.
- **Para decidir con Joaco:**
  - quien solo ve pagos (gerente, auditor) lee el CBU y el alias completos de las cuentas propias;
  - la auditoría guarda el CBU (igual que con las cuentas de los proveedores);
  - el prefijo de la numeración usa 12 caracteres del id de la razón social. Si dos coincidieran, compartirían contador. Se puede pasar a un código de la razón social.

## Riesgos

- Los pagos viejos quedan sin número OP. Siguen en la cuenta corriente y en la factura.
- Una factura puede estar «Cargada» sin CAE. La base lo exige antes de controlar o dar conforme.
- La lista de proveedores del panel de pago muestra solo los que tienen saldo. Para un anticipo sin facturas falta sumar «otro proveedor».
