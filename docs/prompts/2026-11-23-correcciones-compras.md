# Correcciones de Compras (pedido de Soy, 2026-11-22 y 2026-11-23)

Soy recorrió Compras en staging y pidió dos cosas: que **los criterios de pantallas** queden en la base de conocimiento de todo el proyecto, y que Compras se corrija con ellos. Va después de las correcciones del Módulo 1 (`2026-11-22-correcciones-modulo-1.md`).

- **Criterios:** `.claude/rules/design.md`, sección «Criterios de Soy para todas las pantallas» (15 reglas), con una línea en `CLAUDE.md`. Valen para todo módulo nuevo y para corregir los que existen.
- **Boceto aprobado:** `2026-11-23-boceto-compras/`.

## Lo que vio Soy en Compras (capturas de los PR #77 a #94)

- **Nueva orden de compra:** antes de cargar, una pantalla intermedia para elegir el local, aunque el selector de arriba ya lo dice.
- **Nueva factura:** un modal largo, con scroll y el botón cortado, y después la ficha vuelve a pedir lo mismo.
- **Registrar pago:** el panel tiene scroll y la fecha sale en formato de Estados Unidos (11/19/2026).
- **Subir archivos:** el control del navegador dice «Choose File No file chosen».
- **Tablero:** el título es de 28 px (las demás pantallas, 20 px) y los nombres se cortan con «…».
- **Ficha de la orden:** las acciones apiladas en vez de en fila. **Ficha de factura:** la columna de datos tiene scroll propio.

## Decisiones de Soy (2026-11-23, las 24 aprobadas)

**Orden de compra**

1. Se adapta: en la computadora, tres columnas como el boceto; en el celular, una columna (proveedor arriba, artículos con botones grandes de más y menos, barra fija abajo con el total y «Enviar orden»).
2. Primero aparecen los artículos que se le pidieron a ese proveedor en los últimos 60 días, para ese local, con el precio de la última lista aceptada. **La cantidad arranca en cero**, sin «la última vez» ni «repetir el último pedido»: Soy quiere que quien pide piense cada cantidad.
3. La orden solo acepta artículos de ese proveedor. Se saca la línea «materia prima sin nombre de factura»: si el artículo no está, primero se suma al catálogo del proveedor.

**Facturas**

4. Filtro con todos los estados (Todas, Cargadas, Observadas, Para dar conforme, Conformes, Vencidas, Pagadas, Anuladas): desplegable, con Observadas, Para dar conforme y Vencidas también como botones a la vista. Al lado, el filtro de fecha (este mes, el mes pasado, otras fechas).

**Registrar pago** (lo que tiene un sistema de gestión simple)

5. Orden de pago con número correlativo (OP-0001), imprimible y para mandar al proveedor como comprobante.
6. De dónde sale la plata: caja o cuenta bancaria del grupo, y con qué razón social se paga.
7. A dónde va: la cuenta del proveedor completa (banco, titular, CUIT, CBU o CVU, alias).
8. Medios: efectivo, transferencia, cheque propio, cheque de terceros, e-cheq y tarjeta. Con cheque: número, banco y fecha de cobro.
9. Qué cancela: facturas, menos notas de crédito; lo que sobra queda como anticipo a cuenta.
10. Retenciones (Ganancias, IVA, Ingresos Brutos) con su lugar, en cero por ahora (P8 sigue fuera de esta fase).
11. Se adapta al celular: una columna, controles de 44 px.

**Listas de precios**

12. Cargar desde Excel, CSV, PDF y fotos. Excel y CSV se leen solos; el PDF hecho por computadora también (punto 17); las fotos y los PDF escaneados, con la pantalla dividida (punto 16) hasta la Fase 5 (punto 18). El archivo original queda guardado para comparar si aparece un error.
13. Corregir una lista aceptada crea una versión nueva con motivo; la anterior queda en la historia.
14. Cuando una lista vence, el pedido de la lista nueva sale solo por mail, **desde el mail de la empresa** (Soy le da el acceso a Joaco).
15. Por WhatsApp, el pedido queda listo para mandar con un clic (abre WhatsApp con el mensaje). La API paga de WhatsApp Business queda para más adelante.
16. Pantalla dividida: la foto o el PDF a la izquierda, con zoom, y la planilla a la derecha.
17. Los PDF generados por computadora se leen sin IA y se vuelcan en la planilla.
18. En la Fase 5, el agente de Facturas también lee fotos y PDF de listas y propone los renglones; una persona los acepta. **Antes de la Fase 5 no se escribe código de agentes** (`.claude/rules/agents.md`).
19. Antes de aceptar, cada renglón muestra cuánto subió o bajó contra la lista anterior; las subas que pasan el umbral de Dirección se resaltan.
20. Un precio diez veces más alto o más bajo que el anterior se marca «Revisar» antes de aceptar.
21. Un artículo reconocido se recuerda (código y descripción del proveedor) para la próxima lista.
22. Una planilla modelo en Excel para los proveedores, con nuestras columnas.
23. Al lado de cada renglón, el precio por unidad de uso («$ 9.856 por kg»).
24. Una lista cargada por error no se borra: se anula con motivo.

---

## Prompt (copiar en Claude Code)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md (en especial la sección nueva «Criterios
de Soy para todas las pantallas»), .claude/rules/agents.md, los ADR de compras (0049 a 0060) y el
boceto docs/prompts/2026-11-23-boceto-compras/ (README y los 5 .dc.html). Las 24 decisiones de
docs/prompts/2026-11-23-correcciones-compras.md mandan sobre el boceto.
Tarea: corregir Compras con los criterios y sumar lo que pidió Soy. Va después de las correcciones
del Módulo 1. Entrá en modo plan y mostrame el plan antes de tocar nada. Proponé partirlo en PRs
chicos, por ejemplo:
  A. criterios en todas las pantallas de Compras (feat/compras-criterios);
  B. orden de compra (feat/orden-de-compra-una-pantalla);
  C. facturas y pagos con orden de pago (feat/orden-de-pago);
  D. listas de precios: importar, versiones, controles y pedido automático (feat/listas-importar).

A. CRITERIOS EN TODO COMPRAS
- Ninguna pantalla con scroll de página, ningún panel ni modal con scroll, en 1440 × 900,
  1600 × 900, 1715 × 843 y 1920 × 1080. Medilo con un test por pantalla, como en las fichas.
- Un componente propio para subir archivos («Subir foto o PDF», «Sacar foto» en el celular) que
  reemplace todos los <input type="file"> de la app, no solo los de Compras.
- Fechas siempre dd/mm/aaaa, también en los campos de fecha (revisá el date input en Chrome en
  inglés: hoy muestra 11/19/2026).
- Tablero: título de 20 px como las demás pantallas; nombres de proveedores y comprobantes sin «…».
- Ficha de la orden: acciones en fila en el encabezado y 4 indicadores. Ficha de factura: la
  columna de datos en dos columnas, sin scroll propio.
- Listados (proveedores, listas, órdenes, facturas, pagos): panel izquierdo fijo de 250 px con la
  agrupación (proveedores con su cantidad) y la tabla con su propio scroll.

B. ORDEN DE COMPRA (boceto Main)
- /compras/ordenes/nueva en una pantalla, sin la pantalla de elegir el local: el local sale del
  selector de arriba; si está en «Todos mis locales», la misma pantalla lo pide en una línea con
  botones.
- Computadora: proveedores a la izquierda (con sus días de pedido y si hoy pide), artículos del
  proveedor al medio, la orden a la derecha (total estimado, pedido mínimo, cuándo llega con
  «Cambiar», canal, nota, si requiere aprobación, «Guardar borrador» y «Enviar orden»).
- Celular: una columna (proveedor, artículos con más y menos de 44 px, barra fija con total y
  «Enviar orden»).
- Artículos: primero los pedidos a ese proveedor en los últimos 60 días para ese local, con el
  precio de la última lista aceptada; después el resto del catálogo del proveedor, con búsqueda.
  La cantidad arranca en 0; no mostrar la cantidad anterior ni «repetir pedido» (decisión de Soy).
- Solo artículos de ese proveedor: sacá la línea con ingredient_id sin purchase_product (migración
  nueva; las OC ya emitidas no se tocan). La base lo exige, no solo la pantalla.

C. FACTURAS Y PAGOS (boceto NuevaFactura, Facturas y Pagos)
- Nueva factura: modal corto (proveedor, comprobante con botones y «Otro», punto de venta y
  número, foto opcional). Si el proveedor tiene una OC recibida sin facturar, lo dice y las
  líneas salen de ahí. Crea el borrador y abre la ficha, que no vuelve a pedir esos datos.
- Listado de facturas: proveedores a la izquierda; estados en un desplegable con Observadas, Para
  dar conforme y Vencidas también como botones; filtro de fecha; título «¿Qué facturas hay para
  revisar y pagar?».
- Orden de pago (base nueva, con RLS, auditoría y pgTAP):
  * número correlativo por razón social o por grupo (proponelo), con catalog.code_series;
  * cuentas del grupo (cajas y cuentas bancarias por razón social): tabla nueva;
  * cuenta destino del proveedor completa (banco, titular, CUIT, CBU o CVU, alias), desde las
    cuentas que ya tiene la ficha del proveedor;
  * medio: efectivo, transferencia, cheque propio, cheque de terceros, e-cheq, tarjeta; con
    cheque, número, banco y fecha de cobro;
  * aplicación a facturas menos notas de crédito; el sobrante, anticipo a cuenta;
  * retenciones de Ganancias, IVA e IIBB con sus columnas, en 0 por ahora, sin cálculo;
  * comprobante adjunto, observaciones y motivo; impresión de la orden de pago (con la versión
    y quién la registró, criterio 14).
- Panel «Registrar pago» sin scroll (dos columnas en la computadora, una en el celular).

D. LISTAS DE PRECIOS (boceto Lista)
- Importar Excel y CSV: elegir la hoja, reconocer las columnas (artículo, código, precio,
  bonificaciones, IVA) y volcarlas en la planilla para revisar antes de cargar. El archivo
  original queda guardado y se puede abrir desde la lista.
- PDF generado por computadora: leer su texto y volcarlo igual. Proponé en el plan la librería
  (tecnología nueva: justificarla en el ADR). Sin IA.
- Fotos y PDF escaneados: pantalla dividida (el archivo a la izquierda con zoom, la planilla a la
  derecha). La lectura automática con el agente de Facturas queda para la Fase 5: no escribas
  código de agentes ahora.
- Controles antes de aceptar: variación contra la lista anterior por renglón (resaltar las que
  pasan el umbral de Dirección), «Revisar» si el precio es 10 veces mayor o menor que el anterior,
  y el precio por unidad de uso al lado.
- Recordar el artículo reconocido (código y descripción normalizada del proveedor).
- Planilla modelo en Excel para descargar desde la ficha del proveedor.
- Corregir una lista aceptada: versión nueva con motivo; anular una lista cargada por error: con
  motivo, sin borrar.
- Pedido automático cuando la lista vence: un mail por lista vencida, desde el mail de la empresa
  (Soy te da el acceso). Las credenciales van como secretos de la función de servidor, nunca en el
  repo ni en el navegador. Usá la cola outbound_messages que ya existe. Por WhatsApp, un botón que
  abre WhatsApp con el mensaje armado (wa.me). Proponé en el plan cómo conectar el mail (SMTP o la
  API del proveedor del mail) y qué pasa si el envío falla.

PRUEBAS
- pgTAP: OC solo con artículos del proveedor; orden de pago (número sin saltos, aplicación,
  anticipo, cheques, retenciones en 0, RLS, auditoría); versiones y anulación de listas; artículo
  recordado.
- Vitest: lectura de Excel, CSV y PDF de ejemplo (archivos inventados en tests/fixtures/), control
  de 10 veces, variación, precio por unidad de uso, artículos de los últimos 60 días.
- Playwright con axe: cada pantalla sin scroll de página en los 4 tamaños y en el celular; nueva OC
  en computadora y celular sin pasar por elegir el local; nueva factura desde el modal; registrar
  un pago con cheque en el celular; importar un Excel; la fecha dd/mm/aaaa y el botón «Subir foto
  o PDF» en lugar del control del navegador.
- Nunca facturas ni listas reales en el repo: los archivos de prueba son inventados.
- Las pruebas que se rompan por la nueva disposición se ajustan para controlar lo mismo. No se
  borran ni se aflojan. Corré todo (npm run test).

ENTREGA (en cada PR)
db-reviewer, security-auditor y ui-reviewer. Capturas reales en 1440, 1600, 1715 × 843, 1920 y
celular, como PNG en docs/capturas/<carpeta del PR>/, commiteadas. ADR nuevo por PR. Lista de
cambios para Soy en docs/modulos/. docs/estado.md.
```
