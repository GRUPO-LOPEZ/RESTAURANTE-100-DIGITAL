# Prueba de la Fase 3 para Soy: compras, facturas y pagos

La trattoria inventada de la prueba de la Fase 2 (en **Demo Pastas Centro**) ahora compra: listas de precios, órdenes de compra, recepciones, facturas y pagos. Es para ver el circuito **pedido → recepción → factura → pago** funcionando en staging antes de cargar proveedores reales (la compuerta de la Fase 3).

**Todo es inventado**: los 3 proveedores «(ficticios)» de la Fase 2, con CUIT de prueba, y facturas con números, CAE e importes de prueba. Las fotos de los comprobantes son una imagen que dice **«FACTURA DE PRUEBA — datos inventados»**. Nada sale de las facturas reales.

## Qué se carga

| Qué                 | Detalle                                                                                                                                                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Fichas de proveedor | Cómo factura cada uno, cada cuánto manda su lista, los días de pedido y entrega, y cómo se le paga: la Verdulería al contado, el Frigorífico a 15 días por transferencia y la Distribuidora a 30 días (transferencia o cheque) |
| Listas de precios   | 5: dos del Frigorífico (la vigente, un 8 % más cara), una de la Verdulería, una vieja y **vencida** de la Distribuidora y una nueva **sin aceptar**, que trae un artículo que el sistema no conoce                             |
| Órdenes de compra   | 8, todas de Demo Pastas Centro. Las pide la cocinera                                                                                                                                                                           |
| Recepciones         | 7. Las hace el Gerente de Centro. Una llega con un faltante y otra **se pagó en efectivo al recibir**. Una OC de la Distribuidora queda sin recibir (abierta)                                                                  |
| Facturas            | 6, que carga Compras y da por conformes la Controller (ver abajo)                                                                                                                                                              |
| Nota de crédito     | 1: el Frigorífico reconoce lo que cobró de más en una factura                                                                                                                                                                  |
| Pagos               | 2 registrados (uno entero por transferencia, con comprobante, y uno parcial en efectivo) y el efectivo de la recepción, **para confirmar**                                                                                     |

Si a Demo Pastas Centro le falta el código de local (en staging no lo carga `demo-data.sql`), la Superadministradora de prueba le pone **PCE**: sin código no se pueden hacer órdenes de compra.

### Las 6 facturas

| Proveedor   | Factura         | Total       | Cómo queda                                                                                    |
| ----------- | --------------- | ----------- | --------------------------------------------------------------------------------------------- |
| Frigorífico | A 0002-00010501 | $ 36.099,99 | **Pagada** (transferencia con comprobante)                                                    |
| Frigorífico | A 0002-00010544 | $ 41.199,98 | Conforme, sin pagar: **vence en 5 días** (tarea 1)                                            |
| Frigorífico | A 0002-00010590 | $ 55.443,00 | Conforme: cobró $ 150 de más por envase y la nota de crédito lo cierra (saldo $ 55.080)       |
| Frigorífico | A 0002-00010602 | $ 34.129,82 | **Observada**: cobra $ 90 de más por envase y no hay nota                                     |
| Verdulería  | B 0004-00003311 | $ 29.400,00 | Conforme, **vencida**, con $ 11.800 pagados en efectivo (saldo $ 17.600)                      |
| Verdulería  | B 0004-00003340 | $ 23.700,00 | La de la verdura pagada en efectivo: **espera que otra persona la dé por conforme** (tarea 3) |

Los vencimientos se calculan el día de la carga. Si la prueba se hace días después, «vence en 5 días» puede figurar como vencida: es lo esperado.

Las órdenes y las recepciones quedan con la fecha del día de la carga, y las facturas con fechas de hasta 20 días atrás (para que haya una vencida y un precio que sube). Por eso algunas facturas figuran emitidas antes que su recepción: es de la prueba, no un error del sistema.

## Cómo se carga (Joaco)

1. Que staging esté activo (el plan gratis de Supabase lo pausa después de una semana sin uso) y que ya esté cargada la **prueba de la Fase 2**: esta se apoya en sus proveedores y materias primas.
2. GitHub → Actions → **Publicar en staging** → Run workflow, desde `main`, con **«Cargar compras, facturas y pagos de prueba»** tildada. Se puede tildar junto con la de la Fase 2: corre después.
   - Para ensayar primero sin dejar nada, tildar también **«solo ensayar»**: hace todo, lo deshace y no sube fotos. Después, correrlo de nuevo sin esa opción.
3. El paso termina con dos tablas (las facturas con su estado y saldo, y los pagos) que tienen que coincidir con las de arriba. El paso siguiente, **«Subir las fotos de prueba»**, termina con «Fotos de prueba subidas: 22».

Es todo o nada: antes de confirmar, el script controla el estado y el saldo de cada factura, que el efectivo quede para confirmar y que estén las 5 listas y las 8 órdenes. Si algo no coincide, deshace todo. Si ya se cargó, no hace nada. Si falta la Fase 2, o los proveedores de la prueba ya tienen listas, órdenes o facturas cargadas a mano, frena sin tocar nada.

Si la subida de fotos se corta, se puede volver a correr con la misma opción tildada: la carga no se repite y solo se suben las fotos que faltan.

## Recorrido para Soy (15 minutos)

En la dirección de staging, con el **superadministrador de prueba** (la contraseña la tiene Joaco) y el local **Demo Pastas Centro** elegido arriba.

1. **Tablero de compras** (Compras → Tablero de compras): «Requiere atención» con la factura vencida, las observadas, la lista vencida, el efectivo para confirmar y el artículo sin mapear; el gasto del mes por rubro y «Cómo subieron los insumos».
2. **Facturas**: abrir la A 0002-00010590 del Frigorífico. En «Todo junto» se ven la nota de crédito, los controles y el saldo. «Ver foto» muestra el comprobante de prueba.
3. **Proveedor**: abrir el Frigorífico El Corral. El saldo de la cuenta corriente y «Ver la cuenta corriente», con las facturas, la nota y el pago.

### Las 3 tareas (la compuerta de la Fase 3)

1. **Pagar una factura en dos partes.** En Compras → Pagos, «Registrar pago»: el Frigorífico, por transferencia a su cuenta, primero **$ 20.000** aplicados a la A 0002-00010544 y después el resto (**$ 21.199,98**). Con el segundo pago la factura pasa sola a **«Pagada»** y el saldo del proveedor baja.
2. **Confirmar el efectivo.** En Pagos → **Para confirmar**: los **$ 23.700** que se pagaron al recibir la verdura. Confirmarlos con un motivo: quedan a cuenta de la Verdulería.
3. **Dar por conforme la factura de esa verdura.** En Facturas, la B 0004-00003340: está observada solo porque la lista de la Verdulería la aceptó Compras y la tiene que firmar otra persona. Darla por conforme: el efectivo confirmado **se le aplica solo** y queda **«Pagada»**.

Al final, el Tablero de compras ya no muestra el efectivo para confirmar.

## Cómo está hecho

El script es `supabase/staging/demo-purchasing.sql`. Como el de la Fase 2, no escribe en las tablas de compras directamente: llama a las funciones de la app (`purchasing.save_supplier_sheet`, `create_price_list`, `accept_price_list`, `save_order_draft`, `submit_order`, `start_receipt`, `close_receipt`, `create_invoice`, `save_invoice`, `run_invoice_checks`, `add_credit_debit_note`, `approve_invoice` y `register_payment`) con la sesión de cada persona de prueba: Compras, la cocinera y el Gerente de Centro, la Controller y la Superadministradora. Así pasa por el control de permisos de esas funciones (si alguna dice «sin permiso», se corta todo), los controles de la factura, la doble firma y la auditoría. No pasa por las políticas de las tablas: el script corre con el usuario administrador de la base.

En la historia, cada paso lleva el motivo «Prueba de la Fase 3 para Soy (corrida N de GitHub Actions): …», salvo las fotos y los controles de factura, que la app registra con su propio texto («Foto de la factura», «Control de la Factura A 0002-…»). Esos se reconocen por la persona de prueba y la hora de la corrida.

**Las fotos.** La app exige que la foto esté subida antes de adjuntarla. El script deja el registro de cada foto en Storage, sin archivo, y escribe sus rutas. Después, el paso «Subir las fotos de prueba» borra cada registro vacío y sube en su lugar `supabase/staging/factura-de-prueba.jpg`, con la CLI de Supabase y el proyecto ya conectado (no suma claves). Solo acepta rutas del Grupo Demo con la forma que pide la app.

**Solo para el Grupo Demo y con datos inventados**, como la prueba de la Fase 2: este patrón no se usa con personas ni facturas reales.

Para probarlo en la base local sin dejar nada: `DRY_RUN=1` hace todo y al final lo deshace.
