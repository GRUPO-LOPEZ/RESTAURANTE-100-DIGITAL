# ADR-0058: Facturas con control de 3 vías y costos desde la factura conforme

- **Fecha:** 2026-11-18
- **Estado:** plan aprobado por Joaco el 2026-11-18. PR 5A: la base.
- **Sigue a:**
  - ADR-0029: cómo entra un precio;
  - ADR-0032: el recálculo en cola;
  - ADR-0049: alcance de la Fase 3;
  - ADR-0052: listas de precios;
  - ADR-0053: órdenes de compra;
  - ADR-0056: recepción.

## Problema

Hasta ahora, un precio entraba a costos solo si alguien lo proponía y el Controller lo aprobaba a mano (ADR-0029). Soy pidió que **el costo de cada materia prima salga de la última factura conforme**, sin cargarlo a mano. Además, la factura tiene que controlarse sola contra lo que se pidió, lo que llegó y la lista de precios vigente.

## Decisiones de Soy (2026-11-14)

1. **Dar por conforme la factura es aprobar el precio.**
   - Quien la da por conforme queda como `approved_by`. Si quedó conforme sola, es quien corrió el control.
   - Si la variación supera el % del grupo (15 %), el precio entra igual. Dirección recibe un aviso (`price_variation`) con el valor anterior, el nuevo y la diferencia, sin frenar la operación.
   - No se crea la solicitud de Dirección. El camino de hoy (proponer y aprobar a mano) sigue para los precios sin factura.
2. **Separación de funciones.**
   - Si el control pasa, alcanza con Compras: la factura queda conforme sola.
   - Si falló, la da por conforme a mano **otra persona**, distinta de quien la cargó, con `purchasing.approve_invoices` y un motivo.
   - Lo valida `purchasing.approve_invoice`, no la pantalla.
3. **Lo que no entra al costo** (decisiones 4 y 5): los impuestos internos, las percepciones, el flete y los servicios. Se guardan aparte, suman al total y al pago, y se van a ver en el tablero de compras.
4. **P4:** una factura sin OC ni recepción (un flete, un servicio) nunca queda conforme sola: la da otra persona.
5. **P5:** las alícuotas de 2,5 % y 5 % valen en las facturas y en los precios.

## Decisiones de Joaco (2026-11-18)

- **Dos PRs:**
  - **5A, base:** tablas, control, costos, seed y pgTAP;
  - **5B, pantallas:** listado y ficha.

  El cambio en la única fuente de costos se revisa solo, sin pantallas encima.

- **Por peso, el precio de la lista y el de la factura son por kilo.**
  - El control compara $/kg contra la lista.
  - El costo se registra por envase: $/kg × los kilos del envase del producto. Así `price_rows` da el $/kg sin tocar el trigger de precios.
  - Si el envase no se pasa a kilos, da un error claro.

## Cómo funciona

- **Carga.** `purchasing.create_invoice` toma el proveedor, el local y las OC recibidas, y prellena las líneas con lo recibido y el precio de la lista vigente a la fecha. Compras las ajusta al papel con `save_invoice`, en lote y con motivo.
- **Copia de la razón social.** La factura guarda la razón social del local y su CUIT al cargarla, porque la base solo tiene la actual.
- **Control de 3 vías** (`run_invoice_checks`): una fila por control y por línea en `purchasing.invoice_checks`, solo de inserción, con la explicación en simple.

  | Control      | Regla                                                                                                                                                                                    |
  | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | Cantidad     | Lo facturado contra lo recibido en la línea de la OC. Por peso, kg contra kg, con la tolerancia del grupo (0,5 %, `price_settings.invoice_weight_tolerance_pct`). Sin peso, las unidades |
  | Precio       | Contra la lista aceptada vigente a la fecha (`price_list_at`), con tolerancia 0. En A, el neto; en las demás, el final (neto de lista con IVA, a centavos)                               |
  | Mapeo        | Cada línea de mercadería tiene producto. Si no, va a la cola de mapeo (`found_in = 'invoice'`) y avisa al chef                                                                           |
  | Totales      | Las líneas, el IVA, los internos y las percepciones suman el total (±0,01)                                                                                                               |
  | Razón social | El CUIT del receptor es el de la razón social del local                                                                                                                                  |
  | OC           | Tiene OC y recepción (P4)                                                                                                                                                                |
  | Notas        | Si solo fallaron cantidad o precio, las notas de crédito y descuento (menos las de débito) cubren la diferencia                                                                          |

  Todo pasa → conforme y liberada. Algo no pasa → observada, con aviso a Compras.

- **Costos** (`release_invoice`): por cada línea de mercadería que no es regalo, un `costing.price_records` con:
  - origen `invoice`, alcance del local, vigente desde la fecha de la factura y la referencia a la línea;
  - en A, el neto, con IVA aparte;
  - en B, C, X y nota a mano, el precio final como «sin factura», porque no hay IVA recuperable. Bolsa de 50 kg a $ 60.500: en A con RI da $ 1.000/kg; en B, $ 1.210/kg;
  - si una nota cubrió la diferencia de precio, el costo es el de la lista.

  Las OC recibidas que cubre pasan a cerradas.

- **Cambio en `price_records`:**
  - columna `invoice_line_id`;
  - el check de aprobación pide una de tres: solicitud aprobada, línea de factura con quien la dio por conforme, o valor de prueba;
  - `on_price_recorded` emite `price.approved` también para los de factura, y el recálculo sale igual.
- **Inmutable.** Desde conforme, ni la factura ni sus líneas cambian (trigger): se corrige con una nota. Cancelar una cargada por error es un estado, con motivo.
- **CUIT.** El del emisor tiene que ser el del proveedor. Uno de ejemplo (99-99999999-9) o una clase fiscal sin autorización no se guardan.

## Opciones que se descartaron

- **Crear una solicitud de aprobación por cada precio de factura**, como hoy. Duplicaba el conforme y frenaba la operación, que es justo lo que Soy pidió evitar.
- **Repartir el flete y los internos en el costo.** Soy decidió que no (decisiones 4 y 5).
- **Guardar el costo por kilo en una columna nueva.** Habría cambiado `price_rows` y el trigger de precios. Pasarlo a precio por envase da el mismo resultado sin tocarlos.

## Consecuencias

- **Una factura conforme cambia costos:** al día siguiente el recálculo mueve las recetas del local. En el seed hay dos facturas conformes en Demo Parrilla Centro, a propósito, para que se vea.
- **Una factura vieja no pisa un costo más nuevo:** `resolve_prices` toma el último por vigencia.
- **Riesgo de redondeo en B o C:** se compara a centavos. Si en la práctica aparecen diferencias de un centavo, se revisa con Joaco antes de aflojar la tolerancia.
- **Lo que queda para el PR 5B:**
  - las pantallas (listado y ficha sin scroll);
  - el origen «Factura A 0003-00012345 · Proveedor» en la ficha de la materia prima y en Costos;
  - las funciones de lectura de la pantalla.
