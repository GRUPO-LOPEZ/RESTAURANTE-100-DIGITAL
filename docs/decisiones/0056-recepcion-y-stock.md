# ADR-0056: Recepción con fotos, validación por línea y entradas de stock

- **Fecha:** 2026-11-17
- **Estado:** plan aprobado por Joaco el 2026-11-17.
- **Pedido:** Prompt 4 de `docs/prompts/2026-11-14-facturas-modulo-2.md`, que corresponde a la Etapa 3 del documento de Soy.
- **Sigue a:**
  - ADR-0049, alcance del módulo;
  - ADR-0052, artículos, cola de mapeo y adjuntos;
  - ADR-0053, órdenes de compra.
- **Migraciones:**
  - `20261208110000_receipt_kinds.sql`: los avisos y los tipos de foto. Va sola porque un valor nuevo de enum no se usa en la misma transacción;
  - `20261208120000_receipts.sql`.

## Decisiones de Soy que se aplican

- **D3:** el remito valida lo recibido y la factura manda para los costos. La recepción guarda qué papel trajo el proveedor y sus fotos.
- **D8:** la recepción registra entradas de stock. Todavía nada descuenta.
- **7:** «Se pagó en efectivo» con el importe, para que Compras lo confirme.
- **P9:** lote opcional por renglón, que se pueda seguir desde Calidad.

## Decisiones del plan, que Joaco aprobó

1. **La factura queda para el Prompt 5.** La tabla de facturas todavía no existe. La recepción guarda la clase de papel (seis: factura, factura-remito, remito, remito electrónico, comprobante no fiscal y nota a mano) y sus fotos. El Prompt 5 arranca de «recepciones con factura por cargar» y usa esas fotos.
2. **El efectivo, en la recepción hasta el Prompt 6.** Va en `receipts.cash_paid_amount` y avisa a Compras. En el Prompt 6 pasa a un pago «para confirmar».
3. **Una OC recibida en parte se vuelve a recibir.** La segunda recepción decide solo los renglones pendientes. Cuando llegó todo, la OC pasa a `received`.
4. **Los renglones se guardan al cerrar, en una sola transacción.** La recepción abierta guarda solo las fotos. Si se corta, se retoma con las fotos y se vuelven a marcar los renglones.
5. **Una OC pedida por materia prima, sin producto de compra,** entra al stock en la unidad de uso.
6. **El lote se sigue desde Inventario,** con filtro y columna. Calidad tiene un enlace «Buscar un lote». El tablero de trazabilidad queda para la fase de calidad.

## Base

**Permisos:**

- `purchasing.receive`: Gerente, Jefe de Cocina y Cocinero en su local, y Compras.
- `inventory.view`, en un módulo nuevo, «Inventario»: Dirección, Dir. de Marca, Gerente, Chef Ejecutivo, Jefe de Cocina, Controller y Auditor.
- Regla G2: quien administra personas tiene los de los roles que administra. El Director de Marca y el superadmin tienen los dos.
- El Controller y el Auditor ven el inventario y no reciben.

**`purchasing.receipts`** guarda:

- la OC, que queda vacía si llegó sin OC;
- el local que recibe y el proveedor;
- quién recibe y cuándo se cerró;
- el papel y su número, el estado (`open` o `closed`) y el resultado (`complete`, `partial` o `with_differences`);
- el efectivo, en ARS.

Una OC tiene una sola recepción abierta (índice único). Cerrada, no se cambia: lo controla un trigger. **El efectivo se protege por columna:** la API no lo lee, y `receipt_detail` lo devuelve solo a quien tiene `prices.view` en el local. El cocinero sabe que se pagó en efectivo, pero no ve el importe.

**`purchasing.receipt_lines`:** la decisión sobre cada renglón de la OC (OK, u observado con su motivo) o lo que llegó sin estar en la OC. Las reglas están en la tabla:

- OK no lleva observación;
- un renglón es de la OC, o es un artículo reconocido, o uno que fue a la cola de mapeo;
- lo que está en la cola no suma stock.

Los renglones no se cambian nunca: se cargan una vez, al cerrar.

**`inventory.stock_movements`** (esquema nuevo en la API):

- una entrada por cada renglón recibido, en la unidad de uso de la materia prima, con los envases y el lote;
- solo de inserción: un movimiento se corrige con otro, nunca se cambia ni se borra;
- solo lo escribe `close_receipt`;
- lo lee quien tiene `inventory.view` en el local.

**Cuánto entra al stock** (`receipt_stock_quantity`):

- envases × unidades × contenido, convertido a la unidad de uso con `catalog.to_base_quantity`;
- lo que va por peso, si se pesó, entra con los kilos;
- sin producto de compra, la cantidad va en su unidad;
- si no se puede convertir, la recepción no se cierra y lo dice.

**`close_receipt(p_id, p_paper_kind, p_paper_number, p_lines, p_cash_paid_amount, p_reason)`** hace todo en una transacción. Exige:

- la foto 1 y la foto 2;
- la clase de papel;
- una decisión por cada renglón pendiente;
- que cada observación sea coherente: «faltó» trae menos de lo pedido, «de más» trae más y «otro producto» trae 0;
- el motivo, si hubo observaciones.

Al cerrar:

- suma lo recibido a la OC, que queda `received` o `partially_received`;
- registra el stock;
- manda a la cola de mapeo lo que no se reconoce (`found_in = 'receipt'`);
- avisa a quien pidió (`receipt_report`), siempre que no sea quien recibió;
- avisa a Compras (`receipt_differences`) si hubo observaciones o efectivo;
- avisa al chef (`unmapped_article`) si hay artículos nuevos.

**Fotos:**

- Van en el bucket `purchasing-documents`, en la carpeta `<grupo>/receipts/<recepción>/`.
- Las sube quien recibe en el local, mientras la recepción está abierta.
- Las ve quien ve las OC del local.
- Son solo de inserción: «Rehacer» suma otra y vale la última de cada foto y página.
- La foto de un producto observado se sube a la carpeta de la recepción y se registra al cerrar, con su renglón.

**Lecturas:** `receivable_orders`, `receivable_suppliers`, `receipt_detail`, `order_receipts` e `inventory.movement_list`. Esta última filtra por local, materia prima, fechas y lote.

## Pantallas

- **`/compras/recepcion`:** «¿Qué llegó?». Las OC para recibir del local elegido arriba, por proveedor y las de hoy primero, con «Recibir» o «Retomar». Abajo, «Recibir sin OC».
- **`/compras/recepcion/[id]`:** cuatro pasos, uno por pantalla, con 44 px en el celular:
  1. el papel y la foto 1. Las seis clases de papel van como botones a la vista, aunque la regla dice «hasta 5»: el plan aprobado lo pide así, y son seis opciones cortas que entran todas;
  2. renglón por renglón, con ✓ OK o ✕ Observar;
  3. la foto 2, del papel firmado;
  4. el resumen, con el efectivo y el motivo.

  Las fotos se achican en el navegador a 1600 px en JPEG; el achicado es el mismo de las fotos de recetas, en `lib/photos.ts`. Al cerrar, la acción lleva a la recepción cerrada con el «Listo»: así el aviso sobrevive a una recarga.

- **Informe en la ficha de la OC:** una sección «Recepción» con el papel, las fotos, lo observado, los lotes y el efectivo. El aviso lleva ahí con `?seccion=recepcion`, que pasa el foco a la tarjeta (`FocusTarget`).
- **`/inventario`:** listado tipo C en una pantalla, con la tabla que se desplaza adentro y filtros de lote, materia prima y fechas.
- **Navegación:** «Recepción» e «Inventario» van en «Gestión y análisis». **Los títulos de grupo de la barra lateral pasan de 36 a 28 px** (decisión de Joaco, 2026-11-17), para que el menú del Controller entre sin scroll en 1440 × 900.

## Cambios por las revisiones (2026-11-17, migración `20261208130000_receipt_review_fixes.sql`)

**Decisiones de Joaco:**

- **Lo vencido no suma stock.** Lo de mala calidad que se acepta, sí.
- **Toda recepción sin OC le avisa a Compras** (`receipt_differences`, «Llegó sin orden de compra»).
- **El peso de un renglón OK que se aleja más de un 20 % de lo estimado** obliga a marcarlo como observado, y con eso a escribir el motivo.

**Seguridad:**

- Las fotos de una recepción son `.jpg`, con tipo `image/jpeg` y hasta 4 MB. Lo controla la base (`receipt_photo_ok`, `can_upload_document`), no solo la acción de servidor.
- Lo subido y todavía sin registrar lo lee solo quien lo subió, y mientras la recepción está abierta. La política de Storage pasa a exigir el dueño.
- Una observación que no es «de más» no trae más de lo pedido.
- **Se recibe en el local que pidió la orden.** El plan decía que un local podía recibir para otro, pero las revisiones mostraron que así ni quien pidió ni el local que recibe veían todo. Como la pantalla no lo ofrecía, queda para cuando haga falta, con la visibilidad de los dos locales resuelta. Con esto, una recepción abierta ya no puede quedar en el local equivocado.

**Base:**

- `closed_by`: quién cerró, que puede no ser quien abrió. El informe muestra a quien cerró.
- El peso se guarda solo en lo que va por peso.
- Mensajes propios para un 23503 y para un efectivo demasiado grande.
- Lo que va a la cola de mapeo guarda la cantidad «como figura en el papel». La unidad la define el chef al mapearlo.

**Quedan anotados, sin cambio:**

- `stock_movements.source_id` no tiene FK, porque el origen es polimórfico. Lo cuida el índice único y que solo escribe `close_receipt`.
- El filtro por lote usa `like`: se mide con `explain analyze` cuando crezca.
- El efectivo se oculta con `prices.view` en la ficha y con `hide_costs` en el historial; hoy coinciden en todos los roles.
- No se puede anular una recepción abierta: se retoma y se cierra.
- La barra inferior del celular no suma Recepción (sigue en «Menú»). En su lugar, **«Recibir mercadería» va en el encabezado del Inicio** (decisión de Joaco, 2026-11-17, PR aparte), para quien tiene `purchasing.receive`. Con el tablero es un botón secundario, al lado de «Ver qué falta corregir», y lleva el local del tablero; en el Inicio simple (la cocinera) es el principal.

## Riesgos y pendientes

- **La navegación de Dirección y del superadmin** ya se pasaba de 900 de alto antes de este PR, y sigue pasándose: unos 65 y 145 px. **Resuelto en ADR-0057** (grupos plegados).
- **Las fotos del seed son filas inventadas, sin imagen:** la pantalla dice «guardada (no se puede mostrar)». Las fotos reales salen de las pruebas de Playwright.
- **La cámara del navegador cambia según el teléfono.** Se probó con archivos (`setInputFiles`); falta mirarlo en un celular real.
- **La factura y el pago quedan a medias** hasta los Prompts 5 y 6.
