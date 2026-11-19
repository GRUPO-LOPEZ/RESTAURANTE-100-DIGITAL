# ADR-0058: Facturas con control de 3 vías y costos desde la factura conforme

- **Fecha:** 2026-11-18
- **Estado:** plan aprobado por Joaco el 2026-11-18. PR 5A: la base (#86). PR 5B: las pantallas.
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

## Revisión de base y de seguridad (2026-11-18)

`db-reviewer` y `security-auditor` encontraron tres hallazgos graves, que `security-auditor` reprodujo en la base. Se corrigieron en `20261209150000_invoice_review_fixes.sql`, sin editar las migraciones anteriores, y cada uno tiene su prueba en la pgTAP 380.

- **Facturar dos veces la misma mercadería pasaba sola.** Ahora no pasa:
  - una OC facturada entera (cerrada) no se vuelve a facturar;
  - el control de cantidad descuenta lo que ya está en otras facturas vigentes de esa línea de la OC;
  - dos líneas de una factura no van contra la misma línea de la OC;
  - al cargar, las líneas de la OC quedan bloqueadas y solo se prellena lo que falta facturar.
- **Quien corrige la factura después la daba por conforme.**
  - `edited_by` anota a quien guarda cambios o suma notas. Ni quien la cargó, ni quien la corrigió, ni quien le sumó una nota la da por conforme a mano.
  - El conforme a mano puede recibir la versión que se miró (`p_version`): si la factura cambió mientras tanto, no se aprueba.
- **Una sola persona de Compras podía fijar cualquier costo:** cargaba la lista, la aceptaba y controlaba la factura. **Decisión de Joaco (2026-11-18):** el conforme automático no vale si quien controla cargó o aceptó la lista vigente de ese proveedor. La factura queda observada («la da por conforme otra persona»).
  - Consecuencia: con una sola persona en Compras, toda factura con lista la da por conforme el Controller. Así está armado el seed.
- **Doble verificación para Compras.** **Decisión de Joaco (2026-11-18):** cargar y controlar facturas escribe costos, así que el rol Compras exige doble verificación, como el Controller, y «Cargar facturas» pasa a ser sensible. Se actualizó `.claude/rules/security.md` (el documento de Soy decía niveles 1 a 4 y Controller). Las pruebas de Playwright ingresan como Compras con doble verificación.
- **Otros cambios:**
  - **sin fecha futura;**
  - **la historia no se reescribe:** un precio de factura no empieza antes del último precio de ese producto en el local ni del que vale hoy (`costing.valid_from_floor`, el mismo piso que el precio cargado a mano);
  - **una nota de crédito cuenta con su foto:** al registrar la foto se vuelve a controlar;
  - **lo que el chef mapea después** se asocia a su línea de la OC;
  - **en la base, un trigger (`costing.check_invoice_price`)** exige que un precio de factura venga de una factura conforme, del mismo producto y local, aprobado por quien la dio por conforme;
  - **la cobertura por notas** se calcula una vez por corrida;
  - **validaciones de carga:** las claves de las percepciones se validan, el proveedor tiene que estar activo y los errores de fecha o número salen en español.
- **Quedó anotado, sin cambio:**
  - los avisos van a quien tiene el permiso en todo el grupo, igual que en la recepción;
  - el conforme a mano acepta fallas «duras» (totales, razón social), con motivo;
  - en A, si la lista trae el precio con IVA, el esperado se redondea a 4 decimales;
  - dos líneas del mismo producto dejan dos precios del mismo día y vale el último;
  - cada fila del control se audita;
  - el dinero va en `numeric(18,4)`, como en el recetario (ADR-0020), y no en el `numeric(14,4)` de la regla general.

### Segunda pasada (2026-11-18)

Corregido en `20261209160000_invoice_review_fixes_2.sql`, con pruebas en la 380:

- **Una factura vieja no pisa un costo más nuevo:**
  - es la que queda conforme después de otra más nueva;
  - si es anterior al último precio del producto en el local o al que vale hoy ahí, **no registra precio**;
  - queda conforme para el pago, y el costo vigente sigue siendo el de la compra más nueva («costo vigente = última compra conforme»).
- **Una línea de la OC, una línea de la factura:** índice único. Lo que el chef mapea después se asocia de a una línea.
- **Las notas no dejan la factura conforme sola** si quien controla la cargó, la corrigió o le sumó notas. Las notas de crédito y los descuentos no superan el total de la factura.
- **Quien cambia la foto de la factura queda anotado** (`edited_by`).
- **La explicación de cantidad** dice cuánto ya está en otras facturas de la OC.
- **Anotado:**
  - `p_version` es opcional en la base; la pantalla (PR 5B) lo manda siempre;
  - una factura cargada y olvidada de la misma OC frena a la buena hasta que se cancela (es conservador: nunca paga de más);
  - quien aprieta «Controlar» sobre una lista que cargó otra persona la deja conforme a su nombre. Es lo que se decidió con la opción b.

## PR 5B: las pantallas (2026-11-18)

- **Listado** (`/compras/facturas`, tipo C):
  - pestañas Todas, Cargadas, Observadas, Conformes (suma las liberadas: el conforme libera en la misma transacción), Pagadas y Canceladas;
  - filtros de proveedor y fecha; el local sale del selector de arriba;
  - la columna «Qué no pasó»: dice qué falló en el último control y, en una conforme que no había pasado, «Conforme a mano».
- **Alta** («Nueva factura», modal corto y página `/compras/facturas/nueva`):
  - pide el proveedor, las OC recibidas que cubre (ninguna para un flete o un servicio), el comprobante, el número, la fecha y la autorización;
  - el CUIT del emisor lo pone la acción: es el del proveedor;
  - una OC con una factura en curso (cargada u observada) no se ofrece: esa se termina o se cancela.
- **Ficha** (`/compras/facturas/[id]`, tipo B sin scroll):
  - **4 indicadores:** Total (cierra o no), Contra lo recibido, Contra la lista (lo cobrado de más; si una línea no tiene lista, «Sin lista», nunca «igual») y Vence el;
  - **tres tarjetas:** los datos y el pie; las líneas como planilla, con el control de cada una en un tooltip; y «Todo junto», con el papel, la OC y su recepción, los controles y las notas;
  - se guarda en lote, con motivo, y vuelve a «cargada»;
  - **acciones:** Controlar, Dar por conforme (manda la versión que se miró, `p_version`) y Cancelar. El resultado sale en la barra de abajo;
  - en el celular es de consulta, pero «Dar por conforme» está (aprobar es supervisar).
- **Lecturas de la base** (`20261210120000_invoice_screens.sql` y `20261210140000_invoice_screens_fixes.sql`):
  - `invoice_list`: invoker, con la RLS de quien consulta;
  - `invoiceable_orders`;
  - `invoice_access`: qué puede hacer la sesión; anticipa la regla de «otra persona», que sigue decidiendo `approve_invoice`;
  - `costing.price_origins`: el origen de un precio para quien ve ese precio; el proveedor, solo si ve proveedores.
- **Textos del control** (`20261210130000_invoice_texts.sql`): la plata y las cantidades como se leen acá («$ 3.403,00»). Las reglas no cambian.
- **Origen del precio:** «Factura A 0003-00012345 · Proveedor» en la ficha de la materia prima (tabla de productos y precios) y en el impacto de un precio en Costos. Quien ve facturas la abre.
- **Revisiones:**
  - `security-auditor`: apto, 0 graves;
  - `db-reviewer`: 0 graves. Se corrigió el medio: la OC con una factura en curso;
  - `ui-reviewer`: 1 grave, corregido: «Contra la lista» decía «igual» sin lista. También se corrigieron los medios.
- **Queda anotado, sin cambio:**
  - `p_version` sigue opcional en la base; la pantalla lo manda siempre;
  - el aviso de variación compara con el envase nuevo («lo que habría costado con el precio anterior»).

## Opciones que se descartaron

- **Crear una solicitud de aprobación por cada precio de factura**, como hoy. Duplicaba el conforme y frenaba la operación, que es justo lo que Soy pidió evitar.
- **Repartir el flete y los internos en el costo.** Soy decidió que no (decisiones 4 y 5).
- **Guardar el costo por kilo en una columna nueva.** Habría cambiado `price_rows` y el trigger de precios. Pasarlo a precio por envase da el mismo resultado sin tocarlos.

## Consecuencias

- **Una factura conforme cambia costos:** al día siguiente el recálculo mueve las recetas del local. En el seed hay dos facturas conformes en Demo Parrilla Centro, a propósito, para que se vea.
- **Una factura vieja no pisa un costo más nuevo:** `resolve_prices` toma el último por vigencia.
- **Riesgo de redondeo en B o C:** se compara a centavos. Si en la práctica aparecen diferencias de un centavo, se revisa con Joaco antes de aflojar la tolerancia.
- **Lo que queda para el Prompt 6:** los pagos y el tablero de compras.
