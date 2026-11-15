# Módulo 2 «Facturas»: administración y compras (pedido de Soy, 2026-11-14)

Siete prompts, en orden, **un PR cada uno**. El documento de Soy está completo en `docs/fases/fase-3-facturas.md`: hay que leerlo entero antes del Prompt 0. Soy lo llama **Módulo 2: Facturas**; en la hoja de ruta del prompt maestro es la **Fase 3 (compras)**. En los docs y en las pantallas se usa el nombre de Soy: «Compras y facturas».

Es el módulo más grande desde el recetario: va de la ficha de proveedor hasta el pago, y es la **única fuente de costos de materia prima** del sistema. Por eso va con la base primero, con pruebas en cada paso, y con el plan aprobado por Joaco antes de cada PR.

## Decisiones de Soy (del documento, 2026-11-14)

1. Compras y numeración de OC **por local** (por ejemplo, RAG-0001).
2. **Costo vigente = última compra conforme**, neta de IVA cuando la factura es A.
3. El **remito valida lo recibido; la factura manda para los costos.**
4. La factura se carga **por foto** y la valida administración. OCR y ARCA: después.
5. Las listas de precios las **sube y acepta administración**. Queda el histórico para analizar aumentos. Agente de carga: después.
6. La **aprobación de OC** es configurable por proveedor (tilde «requiere aprobación de administración»).
7. Pagos: **agenda de vencimientos y cuenta corriente por proveedor**, pantallas simples.
8. La recepción **registra entradas de stock**. El descuento por ventas queda preparado, no activo.
9. «Mandar OC» envía por el canal de la ficha **desde las cuentas de la empresa**. El canal real (WhatsApp API, mail) se define después: todo queda listo y en cola.
10. El cocinero da de alta las materias primas; un artículo nuevo en una factura va a la **cola de mapeo** con alarma al chef.

## Lo que ya existe y se reutiliza (no se duplica nada)

Soy pide usar lo que ya hay. La base ya tiene gran parte del modelo; estos prompts lo completan en vez de crear tablas paralelas.

- **Proveedor** = `catalog.suppliers` (código, nombre, CUIT, interno, activo, notas). La ficha completa se construye **sobre esta tabla**, no sobre una `proveedores` nueva.
- **Insumo genérico** = `catalog.ingredients`, con su unidad de uso y su rubro (`catalog.ingredient_categories`). Las recetas ya referencian solo materias primas, nunca marcas.
- **Artículo de proveedor** = `catalog.purchase_products`: `description` es el nombre de factura, `supplier_id` el proveedor, y el envase (`package_unit_id`, `units_per_package`, `content_per_unit`, `content_unit_id`) ya es el **factor de conversión** a la unidad de uso (`catalog.to_base_quantity`). Un producto apunta a una sola materia prima; una materia prima tiene N productos. **No se crea `articulos_proveedor`.**
- **Costos** = `costing.price_records`, que es solo de inserción y ya tiene el origen `invoice` reservado desde ADR-0029. **`costos_insumo` es esta tabla; `costos_vigentes` son `costing.resolve_prices` y `costing.price_rows`** (local → marca → grupo, último aprobado, neto o bruto según la razón social, desactualizado). El recálculo de recetas ya existe (`costing.cost_recalc_queue`, cada minuto, ADR-0032). No se crean ni tabla ni vista nuevas de costos.
- **IVA recuperable** = `org.legal_entities.vat_condition` (ADR-0029): el costo va neto solo con factura A y razón social responsable inscripta. Con B o C, el costo es el total.
- **Aprobaciones** = `workflow.approval_workflows` / `approval_requests`, con `approver_role_codes`, `excluded_approvers` y función `apply_*` (como `costing.apply_price`). Sirve para la OC que requiere aprobación.
- **Avisos** = `core.notifications` (hoy con un solo tipo, `approval_requested`). Las alarmas del módulo son tipos nuevos de este enum más una función que avisa a todos los usuarios con un permiso en un alcance. **No se crea `alarmas`.**
- **Numeración correlativa** = `catalog.code_series` (ADR-0041), con el prefijo del código del local.
- **Eventos** = `integration.integration_outbox` (`cost.changed`, `price.approved`, `recipe.published`).
- **Fotos y archivos** = Supabase Storage con el patrón de `recipe-media` (bucket privado, tipos y tamaño limitados, RLS por carpeta).
- **Importes ocultos** = `core.hide_costs` esconde las columnas con `price` o `amount` en el nombre a quien no ve costos. Toda columna de dinero del módulo se nombra así.
- **Pantallas** = los tres tipos de `design.md` (A paneles, B carga, C listados), el patrón «pantalla de carga sin scroll» de las fichas, `Metric`, `SegmentedField`, `ToggleField`, la barra fija con contador y motivo, y los paneles laterales de alta.

## Quién es quién (roles de la base)

Soy habla de «administración», «cocinero» y «chef». En la base son estos roles; Joaco lo confirma en el plan del Prompt 0.

- **Administración** = rol **Compras** (`purchasing`) para cargar: ficha de proveedor, listas, facturas y pagos. El **Controller** (`controller`) ve todo el módulo con importes y da por conforme lo que no cierra solo. **Dirección General** ve todo.
- **Cocinero que pide y recibe** = `cook`, `head_chef` y `restaurant_manager`, cada uno en su local.
- **Chef que mapea artículos y da de alta materias primas** = `executive_chef` y `head_chef` (ya tienen `catalog.manage`).
- **Auditor** lee todo, sin importes salvo que su rol los tenga hoy.
- Las razones sociales y la condición frente al IVA siguen siendo de `org.manage` (ADR-0029, decisión 8).

## Tres decisiones más de Soy (respondidas el 2026-11-14)

Se preguntaron con una recomendación y Soy las confirmó. Van al ADR del prompt que las usa.

1. **Factura conforme = precio aprobado (Prompt 5).** Hoy un precio entra solo si lo aprueba el Controller y, si la variación supera el % del grupo (15 %), también Dirección General (ADR-0029). **Decisión:** dar por conforme la factura **es** la aprobación del precio: quien lo hace queda como `approved_by`. Si la variación supera el % del grupo, el precio entra igual y salta una alarma a Dirección General con el detalle (valor anterior, nuevo y diferencia), sin frenar la operación. El camino de hoy (proponer y aprobar a mano) sigue existiendo para los precios sin factura.
2. **Separación de funciones en facturas (Prompt 5).** Si el control automático de 3 vías pasa, alcanza con Compras: la factura queda conforme sola. Si falló y hay que darla por conforme a mano, lo hace **otra persona distinta de quien la cargó** (el Controller, o alguien con `purchasing.approve_invoices` que no sea quien la cargó), con motivo. **La base lo valida**, no la pantalla.
3. **Quién aprueba una OC que requiere aprobación (Prompt 3).** **Compras** (`purchasing`), en el alcance del local. Nunca quien la pidió (`excluded_approvers`).

## Lo que no entra todavía (Soy, 2026-11-14)

Tablero de alarmas por perfil (al final del sistema), agente de carga de listas, OCR / ARCA, precios autocompletados en la OC, WhatsApp Business API, descuento de stock por ventas. Todo queda **preparado** (columnas, estados, cola de mensajes) pero no se construye.

## Lo que muestran las facturas reales (33 comprobantes de Soy, 2026-11-14)

Soy mandó dos PDF con 33 comprobantes reales de unos 30 proveedores de los tres locales. **Son proveedores reales que el sistema tiene que reconocer desde el primer día.** Los PDF tienen CUIT, domicilios, precios y firmas reales y el repositorio es público: **nunca se commitean, no van al seed ni a las capturas, y no se suben a ningún servicio.** Joaco los recibe aparte. Este resumen no tiene nombres, CUIT ni importes.

Lo que cambia el diseño (cada punto está en el prompt que lo usa):

1. **Hay seis clases de papel, no solo A, B y C:** factura A (la mayoría); factura/remito A (un solo papel que es las dos cosas); remito R (código 91, «no válido como factura», a veces con «valor declarado» y la factura llega después); remito electrónico harinero (código 993, con la factura enviada por mail); comprobante X (no fiscal, con el saldo de la cuenta corriente); y nota de pedido escrita a mano (puesto del mercado, sin CUIT, «no válido como factura»).
2. **Mucho se factura por peso:** se piden piezas, cajas o unidades, pero se cobra por kg («8 piezas · 32,80 kg», «7 unidades / 130,05 kg», «5 cajas · 50 kg»). La línea tiene dos cantidades: unidades y kg facturados. El precio es por kg.
3. **Descuentos por línea:** precio de lista, uno o dos % de bonificación (15, 45, 50, 65 %) y precio neto. Hay líneas con 99,99 % de bonificación (regalos), una línea «descuento por volumen» y bonificación general al pie.
4. **Más impuestos que el IVA:** alícuotas de 10,5 % y 21 % mezcladas en la misma factura; líneas exentas; impuestos internos (bebidas, por línea); percepciones de IIBB de CABA o de Provincia, percepción de IVA (RG 3337, RG 5329) y «otros tributos»; ajuste por redondeo.
5. **Líneas que no son mercadería:** flete, envío, «servicios administrativos», redondeo, envases retornables (barril) y un servicio de gestión y traslado.
6. **Mucho no es comida:** limpieza (desengrasantes, bidones), descartables (bandejas, bobinas, guantes, sorbetes) y bebidas que se revenden (vinos, gaseosas, cerveza, agua). Hoy todo artículo de compra tiene que apuntar a una materia prima.
7. **Quien recibe y quien factura pueden no coincidir:** un local recibe mercadería facturada a la razón social de otro local, y un proveedor usa el domicilio fiscal y otro el de entrega. Cada proveedor nos tiene con su propio número de cliente.
8. **Autorización fiscal variada:** CAE (la mayoría), CAI (talonario preimpreso) y CAEA. Una factura «A» trae datos de emisor de ejemplo (CUIT 99-99999999-9, sin CAE): el sistema la tiene que frenar.
9. **Vencimiento impreso:** casi todas traen la fecha de pago o la condición («7 días fecha factura», «30 días FF», «contado contra entrega», «transferencia en el día»).
10. **Referencias cruzadas:** la factura nombra el remito, el pedido o un casillero «Orden de compra» vacío. Varias son de más de una página.
11. **Sellos del local en el papel:** «{LOCAL} RECIBIDO» con fecha y firma (es la foto 2 del documento de Soy), «PAGADO EFECTIVO» (se pagó al recibir) y «PASADA» (ya se cargó). Dos traen el saldo de la cuenta corriente según el proveedor.
12. **Cada proveedor tiene su código de artículo** en casi todas las facturas. Es la clave para reconocer un artículo la segunda vez sin preguntar.

## Cuatro decisiones más de Soy (salen de las facturas reales, respondidas el 2026-11-14)

4. **Impuestos internos y percepciones (Prompt 5). Ninguno suma al costo** (decisión de Soy; la recomendación era sumar los internos). El costo de la materia prima es el precio neto de la línea, sin IVA, sin impuestos internos y sin percepciones. Los impuestos internos y las percepciones se guardan aparte en la factura, cuentan para el total y el pago, y se ven en el tablero de compras.
5. **Flete, envío y servicios (Prompt 5).** No se reparten entre los productos. Quedan como gasto de la factura y se ven en el tablero de compras.
6. **Lo que no es comida (Prompt 2).** Limpieza, descartables y bebidas que se revenden se cargan como materias primas en rubros que no van a recetas. Así entran igual en la OC, la recepción, la factura, los pagos y el gasto por rubro.
7. **Pago en efectivo al recibir (Prompt 4).** En la recepción se marca «Se pagó en efectivo» con el importe, y queda como pago para que Compras lo confirme.

## Carga real: cómo el sistema reconoce a los proveedores de Soy

- **Nunca por el seed ni por una migración.** Los datos reales viven solo en producción, y Claude Code trabaja solo en desarrollo.
- **Después del Prompt 1 en producción:** Compras carga los proveedores reales desde la ficha, con la lista privada que arma Joaco a partir de los PDF (fuera del repositorio). Joaco puede proponer en el plan del Prompt 1 una importación desde planilla, con el mismo patrón del importador de recetas (ADR-0027), si cargarlos a mano lleva mucho.
- **Después del Prompt 2 en producción:** se cargan sus artículos con el código del proveedor y se mapean a las materias primas. Desde ahí, cada factura nueva de esos proveedores se reconoce sola.
- **Para diseñar y probar:** el seed copia **la forma** de cada clase de papel (factura/remito por peso, remito R, comprobante X, nota manuscrita, factura con impuestos internos y percepciones) con proveedores, CUIT e importes inventados.

## Orden

- **Prompt 0:** plan de la Fase 3 (solo documentos). Rama `docs/plan-fase-3-compras`.
- **Prompt 1:** proveedores: ficha completa. Rama `feat/proveedores`.
- **Prompt 2:** artículos de proveedor, cola de mapeo y listas de precios. Rama `feat/articulos-y-listas-de-precios`.
- **Prompt 3:** orden de compra. Rama `feat/ordenes-de-compra`.
- **Prompt 4:** recepción y stock. Rama `feat/recepcion`.
- **Prompt 5:** facturas, control de 3 vías y costos. Rama `feat/facturas`.
- **Prompt 6:** pagos, cuenta corriente y tablero de compras. Rama `feat/pagos-y-tablero-de-compras`.

Cada PR deja el sistema usable: después del Prompt 1 ya se cargan proveedores; después del 3, ya se piden OC. El seed crece en cada PR con datos **ficticios** (nunca un CUIT, un proveedor ni una factura reales, tampoco las de referencia que manda Soy).

En todos los prompts vale lo de siempre: `CLAUDE.md`, modo plan con aprobación de Joaco, base primero con pgTAP, pantallas con `components/ui/`, revisores, capturas en `docs/capturas/<tema>/` dentro del PR, ADR, lista de cambios para Soy en `docs/modulos/` y `docs/estado.md`.

---

## Prompt 0: plan de la Fase 3 (solo documentos)

```text
Leé CLAUDE.md, docs/estado.md, docs/prompt-maestro.md (secciones 5, 6 y 11), docs/fases/fase-2-plan.md
(es el modelo), docs/fases/fase-3-facturas.md (el documento de Soy, completo) y
docs/prompts/2026-11-14-facturas-modulo-2.md (este archivo, con lo que se reutiliza y las decisiones
pendientes). Leé también las migraciones de proveedores, productos de compra, precios, series de
códigos, notificaciones y aprobaciones (catalog.suppliers, catalog.purchase_products,
costing.price_records, catalog.code_series, core.notifications, workflow.*).
Tarea: escribir el plan de la Fase 3 (Módulo 2 «Facturas», compras) en docs/fases/fase-3-plan.md,
con la misma estructura que fase-2-plan.md. Rama: docs/plan-fase-3-compras. Solo documentos: no se
toca app/ ni supabase/. Entrá en modo plan y mostrame el índice antes de escribir.

EL PLAN TIENE
1. Resumen para Soy, en simple: qué va a poder hacer cada persona cuando termine el módulo.
2. Arquitectura: qué se reutiliza de las Fases 1 y 2 y qué se agrega. Esquemas nuevos: purchasing
   (proveedores ampliados, listas, OC, recepciones, facturas, notas, pagos, adjuntos, mensajes
   salientes) e inventory (solo stock_movements). Dónde va cada tabla y por qué. Decí explícitamente
   que NO se crean articulos_proveedor, costos_insumo, costos_vigentes ni alarmas (ya existen con
   otro nombre) y qué tabla de hoy cumple cada papel.
3. Diagrama de entidades (mermaid) con las tablas de hoy en un color y las nuevas en otro.
4. Diccionario inicial: tabla, columnas, tipo, obligatoria, qué guarda. Dinero en numeric(18,4)
   con nombres que terminen en _price o _amount (core.hide_costs). Estados como enum documentados.
5. Permisos nuevos del módulo purchasing (código = módulo.acción) y reparto por rol, como lista:
   view_suppliers, manage_suppliers, view_price_lists, manage_price_lists, map_articles (o el
   nombre que elijas, en catalog), view_orders, create_orders, approve_orders, record_order_news,
   receive, view_invoices, manage_invoices, approve_invoices, pay, view_payments, view_dashboard,
   inventory.view. Marcá cuáles son sensibles. Respetá «Quién es quién» de este archivo.
6. Pantallas (las 9 del documento de Soy): tipo A, B o C de design.md, dispositivo principal, qué
   pregunta responde cada una, y dónde va cada entrada en la barra lateral (propuesta: «Proveedores»
   en Base de conocimiento; «Órdenes de compra», «Recepción», «Facturas», «Pagos» y «Tablero de
   compras» en Gestión y análisis; la barra inferior del celular no cambia, lo nuevo entra en
   «Menú»). Recepción y Nueva OC se diseñan para celular primero.
7. Reglas exactas: numeración RAG-0001 por local con code_series; fecha de entrega esperada a partir
   de los días de entrega; ranking de artículos por frecuencia; vencimiento de listas según la
   frecuencia (semanal 7 días, quincenal 15, mensual 31, desde la vigencia); control de 3 vías
   (cantidad facturada = recibida; precio facturado = lista aceptada, tolerancia 0; artículo mapeado);
   costo neto solo con factura A y razón social RI; vencimiento de pago = fecha de factura + días de
   la condición. Para cada regla, un ejemplo con números, como los 27 casos de la Fase 2.
8. Orden de construcción: los 6 PRs de este archivo, con qué deja usable cada uno y su compuerta
   (quién valida con datos de prueba).
9. Riesgos (por ejemplo: productos de compra sin proveedor que ya existen; precios de prueba
   test_value que conviven con los de factura; la carrera entre dos cocineros que piden a la vez).
10. Decisiones: las siete que Soy ya respondió (en este archivo) y las preguntas nuevas que
    encuentres. Nada se decide en el plan: se pregunta.
11. «Lo que muestran las facturas reales»: los 12 puntos de este archivo, uno por uno, con la tabla
    o la columna que lo resuelve. Mirá vos los PDF que te pasa Soy (fuera del repositorio) y sumá lo
    que falte. En el plan no va ningún nombre, CUIT ni importe real.

ENTREGA
- ADR nuevo (siguiente número libre): «Módulo de compras y facturas: alcance y reutilización».
- docs/estado.md: encabezado y una sección «Fase 3: compras y facturas» con el orden de los PRs.
- Formato (npm run format), PR chico con resumen en simple. Commit: «docs(compras): plan de la
  Fase 3, módulo de compras y facturas».
```

---

## Prompt 1: proveedores, ficha completa

```text
Leé docs/fases/fase-3-plan.md (aprobado), docs/fases/fase-3-facturas.md (Etapa 0), CLAUDE.md,
.claude/rules/design.md (incluida la sección «Pantallas de carga sin scroll», si ya se fusionó),
docs/decisiones/0029 y 0043, la migración de catalog.suppliers y la ficha de materia prima
(components/ingredient-sheet/) como modelo de ficha.
Tarea: la ficha completa de proveedor y su listado. Rama: feat/proveedores. Entrá en modo plan y
mostrame el plan antes de tocar nada.

BASE (primero, con pgTAP)
- Esquema purchasing: create schema, grant usage a authenticated, revoke all a los demás.
- catalog.suppliers se completa, no se reemplaza: trade_name, vat_condition (org.vat_condition, el
  enum ya existe), address, city, phone, whatsapp, email, sales_contact, admin_contact. El CUIT
  nuevo se guarda con 11 números sin guiones; las filas de hoy no se tocan.
- purchasing.supplier_terms (una fila por proveedor): días de pedido y días de entrega (1 = lunes a
  7 = domingo, como arreglos de smallint con check), horario de recepción (desde y hasta), pedido
  mínimo (minimum_order_amount, puede ser nulo), canal de envío de OC (enum: whatsapp, email,
  supplier_portal) y su dato (número, dirección o URL, validado según el canal), cómo factura
  (enum: a, b, c, remito_only), frecuencia esperada de lista (enum: weekly, biweekly, monthly),
  condición de pago (enum: cash, account) y días (0 si es contado), requires_po_approval boolean.
- purchasing.supplier_payment_accounts: medio (enum: cash, transfer, check, echeq, card), CBU,
  alias, banco, titular, CUIT del titular, activa. Un proveedor puede tener varias.
- purchasing.supplier_categories: proveedor + rubro (catalog.ingredient_categories), único.
- Funciones: purchasing.create_supplier(...) con código automático (code_series, prefijo PROV-) y
  purchasing.save_supplier_sheet(p_supplier_id, p_changes jsonb, p_reason) que guarda todo en una
  transacción con motivo (como catalog.save_ingredient_sheet). Desactivar conserva todo.
- Permisos: purchasing.view_suppliers (cook, head_chef, executive_chef, restaurant_manager,
  purchasing, controller, brand_director, general_management, auditor) y purchasing.manage_suppliers
  (purchasing, general_management). Las cuentas de pago y la condición de pago las ve solo quien
  tiene manage_suppliers o controller: el cocinero ve nombre, contacto, días y canal, nada más.
  La ve la base, no la pantalla: política por tabla o vista sin esas columnas.
- RLS en todo, columnas de control, auditoría, comentarios en español, reject_truncate.
- Seed: los proveedores ficticios que ya existen quedan completos (ficha entera, 2 con «requiere
  aprobación», uno inactivo, uno con cuenta corriente a 30 días, uno contado). Ninguno real.

FACTURAS REALES (sección del mismo nombre en este archivo)
- El CUIT es opcional (el puesto del mercado no tiene) y, si se carga, se valida el dígito
  verificador. Un CUIT inválido no se guarda.
- «Cómo factura» admite: a, b, c, invoice_remito (factura/remito en un papel), remito_then_invoice
  (remito y la factura después), non_fiscal (comprobante X) y handwritten_note (nota manuscrita).
  Puede ser más de uno.
- purchasing.supplier_customer_numbers: proveedor + local + nuestro número de cliente en ese
  proveedor (cada uno nos tiene con otro número). Se ve en la ficha.
- Condición de pago: además de contado y cuenta corriente, «contado contra entrega» y
  «transferencia en el día»; los días se cuentan desde la fecha de la factura.
- Carga inicial: decí en el plan si conviene una importación desde planilla para los proveedores
  reales (unos 30), con el patrón del importador de recetas. Se usa solo en producción, por Compras.

PANTALLAS
- app/proveedores (tipo C): filtros en una línea (rubro, estado, canal), pestañas Activos /
  Inactivos, tabla de ancho completo (nombre, CUIT, rubros, días de entrega, condición de pago,
  estado con palabra), 15 filas con paginación. «+ Nuevo proveedor» abre el modal corto que crea
  el borrador y lleva a la ficha. Celular: tarjetas con nombre, estado y «Ver».
- app/proveedores/[id] (tipo B, patrón sin scroll de las fichas, 1440 × 900):
  1. Encabezado en una línea: «← Proveedores», nombre de fantasía, razón social · CUIT · condición
     frente al IVA, chip de estado y a la derecha «Desactivar» / «Reactivar».
  2. 4 indicadores (Metric): Lista de precios vigente, Saldo de cuenta corriente, OC abiertas y
     Última compra. Hasta que existan los prompts que los llenan, muestran «—» con el motivo
     («Todavía no hay listas de precios cargadas») y estado Sin datos. Nunca un estado positivo
     sin datos.
  3. Tres columnas que ocupan el alto que queda, se edita donde se ve:
     a. Identificación y contacto (texto corto; condición frente al IVA como botones segmentados).
     b. Operativa: días de pedido y días de entrega como 7 botones L M M J V S D con aria-pressed,
        de un clic; horario de recepción; pedido mínimo. Envío de OC: canal segmentado + su dato.
        Facturación: cómo factura y frecuencia de lista, segmentados.
     c. Pago: condición segmentada (Contado / Cuenta corriente) y días; cuentas como lista con
        «+ Agregar cuenta» en panel lateral. Permisos: «Requiere aprobación de administración
        antes de enviar la OC» como toggle de un clic con tooltip que explica qué pasa. Rubros que
        provee como chips con ✕ y «+ Agregar».
  4. Barra fija: contador, motivo obligatorio, Descartar, Guardar cambios. El campo cambiado lleva
     borde punteado.
  Quien no tiene manage_suppliers la ve en solo lectura y sin la tarjeta de pago. Celular: consulta.
- Barra lateral: «Proveedores» en Base de conocimiento, con ícono Lucide y texto.
- Zod: el mismo esquema en navegador y servidor (CUIT 11 dígitos, mail, teléfono, URL si el canal
  es portal, días 1 a 7, horario desde < hasta).

PRUEBAS
- pgTAP (archivo nuevo 32x_suppliers): RLS por rol (el cocinero no ve cuentas ni condición de pago;
  Compras edita; el Gerente de otro grupo no ve nada), save_supplier_sheet en una transacción con
  auditoría y motivo, validaciones (CUIT, días, canal según dato), código automático, desactivar
  conserva la historia.
- Vitest: el esquema Zod de la ficha (bordes de CUIT, horarios y canal).
- Playwright con axe: lista con filtros y paginación; ficha sin scroll en 1440 × 900, 1600 × 900
  y 1920 × 1080 con un proveedor completo; los botones de días cambian con un clic y el contador
  suma; guardar con motivo queda en el historial; toggle de aprobación; quien no edita ve solo
  lectura y sin pago; celular: consulta, 44 px.
- Corré todo (npm run test). No recrear la base mientras corre Playwright.

ENTREGA
db-reviewer, security-auditor y ui-reviewer. Capturas reales en 1440, 1600, 1920 y celular
(lista y ficha) en docs/capturas/proveedores/, commiteadas en el PR. ADR nuevo. Lista de cambios
para Soy en docs/modulos/ (siguiente número). docs/estado.md. Tipos regenerados. PR chico.
Commit: «feat(proveedores): ficha completa de proveedor».
```

---

## Prompt 2: artículos de proveedor, cola de mapeo y listas de precios

```text
Leé docs/fases/fase-3-plan.md, docs/fases/fase-3-facturas.md (Etapa 1 y «El problema del
azúcar»), docs/decisiones/0029, 0041 y 0044, la migración de catalog.purchase_products y de
recipe_media (Storage), y la ficha de proveedor del PR anterior.
Tarea: artículos de proveedor sobre los productos de compra, la cola de artículos sin mapear y las
listas de precios con aceptación e histórico. Rama: feat/articulos-y-listas-de-precios. Entrá en
modo plan y mostrame el plan antes de tocar nada.

BASE
- Artículo de proveedor = catalog.purchase_products con supplier_id. Se agrega supplier_sku
  (código del proveedor, opcional). El nombre de factura es description. El factor de conversión
  es el envase (ya existe). No se crea otra tabla. Los productos de hoy sin proveedor siguen
  valiendo para costos, pero no pueden ir en una OC ni en una factura (lo exige la base).
- purchasing.unmapped_articles: proveedor, nombre tal como vino, código del proveedor, pista de
  envase, dónde apareció (enum: price_list, invoice, receipt), id de origen, estado (enum: pending,
  resolved, discarded), producto resultante, quién y cuándo. Función purchasing.resolve_article
  (p_id, p_ingredient_id, envase y contenido, p_reason): crea el producto de compra para esa
  materia prima (con la función de alta que ya existe) y cierra la cola en una transacción; o
  vincula a un producto existente del mismo proveedor (proveedor que renombró: el historial no se
  pierde). Avisar al chef (notificación nueva, kind unmapped_article) cuando entra uno.
- purchasing.price_lists: proveedor, fecha de recepción, vigencia desde, estado (enum: received,
  accepted, replaced, expired), quién aceptó y cuándo, adjunto, notas. Una sola aceptada por
  proveedor (índice único parcial). purchasing.price_list_items: lista, producto de compra O
  artículo sin mapear (check: uno de los dos), package_price, alícuota de IVA, si incluye IVA.
  Los precios de lista NO son costos: nunca van a costing.price_records. Sirven para controlar
  facturas y, después, para autocompletar OC.
- Función purchasing.accept_price_list(p_id, p_reason): en una transacción pasa la aceptada
  anterior a replaced y acepta la nueva. Vencida se calcula, no se guarda: una función o vista
  dice si la aceptada ya pasó su plazo según la frecuencia de la ficha (semanal 7, quincenal 15,
  mensual 31 días desde la vigencia), y una función purchasing.notify_expired_price_lists() crea el
  aviso a Compras (kind price_list_expired) una sola vez por lista. Si el proyecto ya tiene un
  trabajo programado (el recálculo de costos, ADR-0032), colgala ahí; si no, decime cómo.
- Adjuntos: bucket purchasing-documents (privado, jpeg, png, webp y pdf, 10 MB) y tabla
  purchasing.attachments (grupo, tabla y registro al que pertenece, ruta, tipo enum: price_list,
  receipt_original, receipt_signed, product_issue, invoice_original, credit_note, payment_receipt,
  tomado cuándo y por quién). RLS de Storage por carpeta como recipe-media.
- Para análisis: vista reporting.v_price_list_changes con la variación % por artículo entre dos
  listas aceptadas consecutivas del mismo proveedor (la incidencia ponderada por compra queda para
  el Prompt 6, cuando haya facturas).
- Permisos: purchasing.view_price_lists (purchasing, controller, general_management,
  brand_director, restaurant_manager), purchasing.manage_price_lists (purchasing) y
  catalog.map_articles (executive_chef, head_chef). El cocinero no ve precios de lista (hide_costs).
- Seed: artículos para las 50 materias primas repartidos entre los proveedores, 2 listas aceptadas,
  1 reemplazada, 1 vencida (frecuencia semanal, vigencia vieja) y 3 artículos sin mapear.

FACTURAS REALES (sección del mismo nombre en este archivo)
- Reconocer un artículo: primero por proveedor + código del proveedor (supplier_sku, único por
  proveedor); si no hay código, por proveedor + descripción normalizada (mayúsculas, sin espacios
  dobles ni puntos). Lo que no se reconoce va a la cola de mapeo.
- Artículos que se facturan por peso: billed_by_weight boolean y estimated_weight_per_unit (por
  ejemplo, «pieza de jamón ≈ 4,5 kg»). Se piden por unidad y se facturan por kg; el precio de lista
  es por kg.
- Lo que no es comida (decisión 6): limpieza, descartables y bebidas que se revenden se mapean a
  materias primas de rubros marcados «no va a recetas» (decí en el plan si el rubro ya tiene algo
  así o hace falta una columna). No aparecen al armar una receta.
- Precio de lista con bonificación: el ítem guarda precio de lista y hasta dos % de bonificación;
  el neto se calcula.

PANTALLAS
- Ficha de proveedor: el indicador «Lista de precios vigente» ya muestra fecha y estado (Al día /
  Vencida con la fecha / Sin datos). Tarjeta nueva «Lista de precios»: la vigente con hasta 5
  artículos y precio, «Ver los N artículos», «+ Cargar lista» (panel lateral: archivo + grilla
  artículo del proveedor / precio / IVA; un nombre que no existe crea el artículo sin mapear) y
  «Ver historial».
- app/listas-de-precios (tipo C): filtros proveedor y estado, tabla, «Aceptar» con motivo desde la
  fila o el detalle, detalle en panel lateral con los artículos y la variación contra la anterior.
- Cola de mapeo: en Materias primas, pestaña «Artículos sin mapear (N)» (o la ubicación que
  propongas en el plan). Cada fila: proveedor, nombre tal como vino, dónde apareció, «Mapear».
  Resolver en un panel simple: buscar la materia prima (código y nombre), envase y contenido, y
  el sistema muestra el factor en palabras («1 bolsa = 50 kg») antes de confirmar. O «Es el mismo
  que…» para elegir un producto existente del proveedor.
- Ficha de materia prima: la lista de productos de compra muestra el proveedor y el nombre de
  factura (ya está); no se agrega nada más ahí.

PRUEBAS
- pgTAP: una sola lista aceptada por proveedor; aceptar reemplaza en una transacción con auditoría;
  vencida según la frecuencia (bordes: exactamente 7 días); el aviso sale una vez; resolver un
  artículo crea el producto con el envase y cierra la cola; vincular a uno existente; RLS (el
  cocinero no ve precios de lista; el chef mapea; Compras no mapea); los precios de lista no tocan
  costing.price_records; adjuntos solo de su grupo.
- Vitest: cálculo del factor en palabras y el Zod de la grilla.
- Playwright con axe: cargar una lista con un artículo nuevo → aparece en la cola → el chef lo
  mapea → el artículo queda en la lista; aceptar con motivo; el indicador de la ficha cambia;
  celular: la cola se puede resolver con 44 px.
- Corré todo.

ENTREGA
Los tres revisores. Capturas en docs/capturas/listas-de-precios/ (ficha con lista, listado, cola
de mapeo, panel de mapeo; 1440 y celular). ADR nuevo. Lista de cambios para Soy. docs/estado.md.
Commit: «feat(compras): artículos de proveedor, cola de mapeo y listas de precios».
```

---

## Prompt 3: orden de compra

```text
Leé docs/fases/fase-3-plan.md, docs/fases/fase-3-facturas.md (Etapa 2), docs/decisiones/0029
(cómo se arma una aprobación con apply_*), 0041 (code_series) y los dos PRs anteriores.
Decisión de Soy (2026-11-14, en docs/prompts/2026-11-14-facturas-modulo-2.md): una OC que requiere
aprobación la aprueba Compras, en el alcance del local, y nunca quien la pidió.
Tarea: la orden de compra digital, su aprobación opcional, el envío en cola y las novedades.
Rama: feat/ordenes-de-compra. Entrá en modo plan y mostrame el plan antes de tocar nada.

BASE
- purchasing.purchase_orders: grupo, local, proveedor, número (texto, «RAG-0001»: prefijo = código
  del local + «-», contador en catalog.code_series, correlativo sin saltos ni repeticiones, también
  con dos cocineros a la vez), estado (enum: draft, pending_approval, sent, with_news,
  partially_received, received, closed, cancelled), solicitante, fecha esperada de entrega
  (calculada: el próximo día de entrega del proveedor posterior al pedido; editable con motivo),
  enviada cuándo y por qué canal, observaciones, solicitud de aprobación.
- purchasing.purchase_order_lines: orden, producto de compra del proveedor (obligatorio salvo la
  excepción de abajo), cantidad en la unidad del envase, cantidad recibida (0 hasta la recepción),
  nota de línea, y preparado para el futuro: unit_price nulo y price_list_item_id nulo (hoy no se
  llenan; Soy lo pidió así). Excepción: una materia prima del catálogo que el proveedor no tiene
  como artículo se pide por ingredient_id con cantidad en su unidad de uso y queda marcada «sin
  nombre de factura»; al facturarla, el artículo entra a la cola de mapeo.
- Ranking: función purchasing.supplier_product_ranking(p_supplier_id, p_restaurant_id) que ordena
  los artículos del proveedor por cantidad de órdenes enviadas o recibidas que los incluyen (se
  calcula desde la historia, sin contadores guardados; índice que lo haga rápido).
- Aprobación: workflow nuevo purchasing.approve_order con approver_role_codes = purchasing (en el
  alcance del local) y excluded_approvers = quien la pidió; función purchasing.apply_order_approval. Si el proveedor
  no requiere aprobación, «Mandar OC» envía directo.
- Envío: purchasing.outbound_messages (grupo, canal, destino, asunto, cuerpo, adjunto opcional,
  entidad de origen, estado enum: queued, sent, failed, cancelled). purchasing.send_order(p_id,
  p_reason) arma el texto (número, local, proveedor, fecha de entrega, líneas con nombre de factura
  y cantidad) y encola el mensaje desde la cuenta de la empresa. Hoy nadie lo despacha (decisión 9
  de Soy): en pantalla se ve «En cola de envío». Nunca se envía desde el usuario del cocinero.
- Novedades: purchasing.purchase_order_events (orden, tipo enum: news, shortage, delivery_change,
  note, cancelled; mensaje; quién). Registrar una novedad pasa la OC a with_news y avisa al
  solicitante (kind order_news) con enlace a la OC.
- Permisos: purchasing.view_orders (quien pide, Compras, Controller, Gerente, Director de Marca,
  Dirección, Auditor, cada uno en su alcance), purchasing.create_orders (cook, head_chef,
  executive_chef, restaurant_manager, purchasing, en su local), purchasing.approve_orders
  (purchasing), purchasing.record_order_news (purchasing, restaurant_manager).
- Seed: 4 OC en distintos estados (borrador, pendiente de aprobación, enviada, con novedad).

FACTURAS REALES (sección del mismo nombre en este archivo)
- El mensaje de la OC lleva su número bien visible y pide «poner este número en Orden de compra»:
  varios proveedores tienen ese casillero y hoy viene vacío.
- Artículos por peso: se piden por unidad y la OC muestra los kg estimados («8 piezas ≈ 36 kg»).
- Nuestro número de cliente en ese proveedor va en el mensaje.

PANTALLAS
- app/compras/ordenes/nueva (celular primero, también computadora):
  1. Elegir proveedor: tarjetas con nombre, días de pedido y entrega, y si requiere aprobación.
  2. Líneas: los artículos del proveedor ordenados por el ranking, cada uno con su nombre de
     factura y su envase («Bolsa 50 kg»), cantidad con botones − / + grandes (44 px) y campo
     numérico. Buscador arriba que busca en todos los artículos del proveedor y en el catálogo de
     materias primas (las que no tiene el proveedor se agregan «sin nombre de factura», con aviso).
  3. Resumen: fecha de entrega esperada (editable), observaciones y el botón principal «Mandar OC»
     (o «Enviar a aprobación» si el proveedor lo requiere). Sin precios en ninguna parte (el
     cocinero no los ve, y hoy no se cargan).
- app/compras/ordenes (tipo C): pestañas por estado, filtros proveedor y fecha, tabla (número,
  proveedor, fecha, entrega esperada, estado con palabra, novedades). «Mis OC» es la misma
  pantalla filtrada por solicitante para el cocinero. Detalle en ficha: líneas, línea de tiempo
  (creada, aprobada, enviada, novedades, recepción), estado del envío, «Registrar novedad»
  (Compras), «Cancelar» con motivo. La novedad se ve dentro de la OC y en los avisos del usuario.
- Aprobaciones: la OC pendiente aparece en la bandeja de aprobaciones existente (app/aprobaciones)
  con sus líneas; aprobar o rechazar con motivo.

PRUEBAS
- pgTAP: numeración correlativa por local y sin repetir con dos sesiones concurrentes; fecha de
  entrega esperada (bordes: pedido el mismo día de entrega, proveedor sin días cargados → error
  claro); ranking (más pedido primero); aprobación obligatoria si el proveedor lo requiere y quien
  pidió no puede aprobar; send_order encola y cambia el estado; una novedad avisa al solicitante;
  RLS (el cocinero ve solo su local; Compras ve todo el grupo); no se puede pedir un producto de
  otro proveedor; auditoría con motivo.
- Vitest: Zod de la OC y la función de fecha esperada si vive en TypeScript (si vive en SQL, solo
  pgTAP).
- Playwright con axe: el cocinero crea una OC en celular (390 px) con los botones grandes, la
  manda y la ve «En cola de envío»; una OC a un proveedor con aprobación va a la bandeja, Compras
  la aprueba y se envía; Compras registra una novedad y el cocinero ve el aviso; computadora en
  1440 para el listado.
- Corré todo.

ENTREGA
Los tres revisores. Capturas en docs/capturas/ordenes-de-compra/ (nueva OC en celular, listado y
ficha en 1440, bandeja con la OC). ADR nuevo. Lista de cambios para Soy. docs/estado.md.
Commit: «feat(compras): orden de compra con numeración por local, aprobación y envío en cola».
```

---

## Prompt 4: recepción y stock

```text
Leé docs/fases/fase-3-plan.md, docs/fases/fase-3-facturas.md (Etapa 3), el PR de órdenes de
compra y el de adjuntos (purchasing.attachments y el bucket).
Tarea: la recepción en celular con dos fotos y validación línea por línea, las entradas de stock y
el informe al cocinero. Rama: feat/recepcion. Entrá en modo plan y mostrame el plan antes de tocar
nada.

BASE
- purchasing.receipts: orden, local, quién recibe, cuándo, documento en papel (enum: invoice,
  remito) y su número si se ve, estado (enum: open, closed), resultado (enum: complete, partial,
  with_differences), notas, foto 1 (original) y foto 2 (firmada) como adjuntos.
- purchasing.receipt_lines: recepción, línea de la OC (o nula si llegó algo que no estaba, con su
  producto de compra o un artículo sin mapear nuevo), ok boolean, tipo de observación (enum:
  missing, extra, different_product, quality, expired; obligatorio si ok es falso), cantidad
  recibida, nota corta, foto opcional del producto.
- Esquema inventory con inventory.stock_movements: grupo, local, materia prima, producto de compra,
  tipo (enum: purchase_receipt; dejar previstos sale, adjustment y count sin usarlos), cantidad en
  la unidad de uso de la materia prima (convertida con catalog.to_base_quantity desde la cantidad
  de envases), cantidad de envases, cuándo, origen (tabla y registro). Solo inserción desde
  close_receipt. Nada descuenta todavía (decisión 8).
- purchasing.close_receipt(p_id, p_reason), en una transacción: exige las dos fotos y una decisión
  por cada línea de la OC; actualiza received_quantity en las líneas; pasa la OC a received o
  partially_received; inserta los movimientos de stock; crea el artículo sin mapear si llegó algo
  desconocido; avisa al solicitante (kind receipt_report) siempre y a Compras (kind
  receipt_differences) si hubo observaciones.
- Permisos: purchasing.receive (cook, head_chef, restaurant_manager, purchasing, en el local) e
  inventory.view (restaurant_manager, executive_chef, head_chef, controller, brand_director,
  general_management, auditor).
- Seed: 2 recepciones cerradas (una completa, una con faltante y uno de más) con sus movimientos.

FACTURAS REALES (sección del mismo nombre en este archivo)
- El papel que llega es de una de seis clases (factura A/B/C, factura/remito, remito R, remito
  electrónico, comprobante X, nota manuscrita): botones segmentados al sacar la foto 1. Si es
  factura o factura/remito, la recepción deja la factura en borrador para Compras con la foto.
- Varias fotos por documento (hay facturas de varias páginas): «+ Otra página».
- Artículos por peso: además de ✓ / ✕, se carga el peso recibido (lo que dice la balanza o el
  papel). El stock entra con el peso, no con las piezas.
- Llegan cosas sin OC (el mercado, el panadero): «Recibir sin OC» con proveedor y líneas; queda
  marcado y avisa a Compras.
- Pago al recibir (decisión 7): «Se pagó en efectivo» con el importe, que queda como pago para
  confirmar por Compras.
- Recepción hecha por un local para otro (un local recibe a nombre de otro): se elige el local
  que recibe; la razón social facturada se controla en la factura.

PANTALLAS
- app/compras/recepcion (celular primero, un paso por pantalla, botones de 44 px o más, también
  usable en computadora):
  1. «¿Qué llegó?»: las OC enviadas del local, agrupadas por proveedor, con las de hoy primero.
  2. Foto 1: botón grande «Sacar foto del remito o la factura» (input con capture=environment),
     vista previa, «Rehacer». Obligatoria para seguir.
  3. Línea por línea: nombre de factura, cantidad pedida y envase; dos botones grandes ✓ «OK» (ok)
     y ✕ «Observar» (bad), siempre con palabra. Observar abre: tipo (5 botones segmentados),
     cantidad recibida, nota corta, foto opcional. «Llegó algo que no estaba» agrega una línea.
     Arriba, el avance («7 de 12»). Solo las observadas quedan marcadas en el resumen.
  4. «Firmar el papel»: instrucción en simple (escribir las observaciones, sello, fecha y firma) y
     Foto 2 obligatoria.
  5. Resumen y «Cerrar recepción» con motivo si hubo diferencias. Después: «Listo. La OC quedó
     recibida (o recibida parcial). Se avisó a {solicitante}».
- Informe de recepción: en la ficha de la OC, sección «Recepción» con las dos fotos, las líneas
  observadas con su tipo y cantidad, y quién recibió. El cocinero lo ve desde el aviso.
- Stock: app/inventario (tipo C, consulta): movimientos por local y materia prima, con filtros de
  fecha; es solo informe. En la barra lateral, «Inventario» en Gestión y análisis.

PRUEBAS
- pgTAP: cerrar sin alguna de las fotos o con una línea sin decidir → error claro; completa →
  received; faltante → partially_received y received_quantity correcta; «de más» y «no estaba» →
  artículo sin mapear; movimientos de stock en la unidad de uso con la conversión del envase
  (ejemplo: 2 bolsas de 50 kg → 100.000 g si la unidad de uso es g); avisos al solicitante y a
  Compras; RLS (recibe solo quien está en el local; nadie edita una recepción cerrada); auditoría.
- Playwright con axe en celular (390 × 844): el flujo completo con fotos de prueba (fixtures
  ficticios), una línea observada, el cierre y el aviso al cocinero; en 1440, el informe en la OC
  y el listado de inventario.
- Corré todo.

ENTREGA
Los tres revisores (ui-reviewer con foco en celular). Capturas en docs/capturas/recepcion/ (los 5
pasos en celular y el informe en 1440). ADR nuevo. Lista de cambios para Soy. docs/estado.md.
Commit: «feat(compras): recepción con fotos, validación por línea y entradas de stock».
```

---

## Prompt 5: facturas, control de 3 vías y costos

```text
Leé docs/fases/fase-3-plan.md, docs/fases/fase-3-facturas.md (Etapa 4 y «Costos para todo el
sistema»), docs/decisiones/0029 y 0032 (cómo entra un precio y cómo se recalcula), la migración de
costing.price_records (su restricción de aprobación y el trigger de solo inserción) y los PRs
anteriores.
Decisiones de Soy (2026-11-14, en docs/prompts/2026-11-14-facturas-modulo-2.md): 1) dar por
conforme la factura es la aprobación del precio; una variación mayor al % del grupo entra igual y
avisa a Dirección General; 2) si el control automático falló, el conforme a mano lo da otra persona
distinta de quien cargó la factura, y la base lo valida.
Tarea: la factura de compra, el control de 3 vías, las notas de crédito y débito, y la actualización
de costos. Rama: feat/facturas. Entrá en modo plan y mostrame el plan antes de tocar nada.

BASE
- purchasing.invoices: grupo, local, proveedor, razón social del local en ese momento, tipo (enum:
  a, b, c), punto de venta (1 a 99999), número (1 a 99999999), CAE (14 dígitos, opcional en C),
  fecha, vencimiento (fecha + días de la condición de pago; contado = la misma fecha), neto, IVA,
  percepciones y total (todos _amount; check: neto + IVA + percepciones = total), estado (enum:
  loaded, in_control, observed, approved, released, paid), motivo de observación, quién la dio
  por conforme y cuándo, foto original (adjunto, obligatoria), notas. Única por proveedor, tipo,
  punto de venta y número. Una factura puede cubrir una o más OC recibidas del mismo proveedor y
  local (tabla purchasing.invoice_orders).
- purchasing.invoice_lines: factura, producto de compra O artículo sin mapear, nombre tal como está
  en la factura, cantidad, unit_price, alícuota, line_amount, línea de OC a la que corresponde
  (nula si no se pudo asociar). Al cargar desde una OC recibida, las líneas se prellenan con lo
  recibido y Compras las ajusta a lo que dice el papel.
- purchasing.credit_debit_notes: factura, tipo (enum: credit, debit, discount), número, fecha,
  amount, adjunto, motivo.
- Control de 3 vías: purchasing.run_invoice_checks(p_invoice_id) guarda en
  purchasing.invoice_checks una fila por control y línea (tipo enum: quantity, price, mapping,
  totals; esperado, real, pasó sí/no, explicación en simple):
    * cantidad facturada = cantidad recibida de esa línea (con las observaciones de recepción);
    * precio unitario facturado = precio de la lista aceptada vigente a la fecha de la factura
      (tolerancia 0); sin lista vigente o sin el artículo en la lista → no pasa («Sin lista de
      precios vigente»);
    * cada línea tiene un producto de compra mapeado (un artículo sin mapear → no pasa y queda en
      la cola con alarma al chef);
    * los totales cierran.
  Todo pasa → approved (conforme) y enseguida released (liberada a pago). Algo no pasa → observed,
  con aviso a Compras (kind invoice_observed). Al adjuntar una NC, ND o descuento que cierra la
  diferencia, se vuelve a controlar; si cierra, pasa a conforme. Si no cierra solo, «Dar por
  conforme» a mano con motivo, solo por alguien con purchasing.approve_invoices que no sea quien
  cargó la factura (decisión 2; lo valida la función, no la pantalla).
- Costos (decisión 1): al quedar conforme, por cada línea con producto de compra se
  inserta un costing.price_records con source = 'invoice', alcance local, valid_from = fecha de la
  factura, package_price = unit_price (por envase), document_type y vat según el tipo de factura
  (A: IVA discriminado; B y C: el precio es final, sin IVA recuperable; que price_rows dé el neto
  solo con A y razón social RI, como hoy), descuento 0, la referencia a la línea de factura, y
  approved_by = quien la dio por conforme. Hace falta una migración que admita el origen invoice
  sin solicitud de aprobación (la restricción de hoy la exige salvo test_value): hacelo con una
  columna invoice_line_id y un check que pida una u otra. Reutilizá la función interna que usa
  costing.insert_approved_price para registrar, así el evento price.approved y la cola de recálculo
  disparan igual. Si la variación contra costing.reference_price supera el % del grupo, el precio
  entra igual y se avisa a Dirección General (kind price_variation) con el valor anterior, el nuevo
  y la diferencia (decisión 1). No se crea la segunda solicitud de Dirección para estos precios.
- Inmutabilidad: una factura conforme no cambia sus datos fiscales ni sus líneas (trigger). Se
  corrige con NC, ND o descuento. Cancelar una factura cargada por error es un estado, con motivo.
- Permisos: purchasing.view_invoices (purchasing, controller, general_management, brand_director,
  restaurant_manager en su local, auditor), purchasing.manage_invoices (purchasing),
  purchasing.approve_invoices (controller y purchasing; la función rechaza a quien cargó esa
  factura). El cocinero y el chef no ven facturas.
- Seed: 4 facturas ficticias: una A conforme (con sus precios en price_records), una B conforme,
  una observada por precio, una observada por artículo sin mapear; una NC que resuelve una
  diferencia. Los importes son de prueba. Sumá un comprobante inventado de cada clase de papel real:
  factura/remito por peso con dos bonificaciones, factura con 10,5 % y 21 % mezclados e impuestos
  internos y percepciones, comprobante X, nota manuscrita y remito R con la factura después.
  **Los PDF reales de Soy no se copian ni se commitean: tienen datos reales.**

FACTURAS REALES (sección del mismo nombre en este archivo)
- Clase de comprobante (enum): invoice_a, invoice_b, invoice_c, invoice_remito_a (factura/remito),
  non_fiscal (X) y handwritten_note. Los remitos R y el harinero se cargan en la recepción, no acá.
  En non_fiscal y handwritten_note no hay CAE, IVA ni punto de venta obligatorios, y el costo es el
  total (price_records con document_type no_invoice, como hoy).
- Autorización: tipo (CAE, CAI, CAEA), número de 14 dígitos y su vencimiento. Obligatoria en las
  clases fiscales.
- CUIT del emisor: dígito verificador válido y tiene que ser el del proveedor elegido; si no, no se
  guarda («El CUIT de la factura no es el del proveedor»). Una factura con CUIT 99-99999999-9 o sin
  CAE se frena.
- CUIT del receptor: se compara con la razón social del local que recibió. Si es la de otro local,
  la factura queda observada con «Facturada a otra razón social» (pasa en la realidad: un local
  recibe a nombre de otro).
- Líneas: clase (product, freight, service, rounding, deposit, free_of_charge), unidades y cantidad
  facturada (kg si va por peso), precio de lista, bonificación 1 y 2 (%), precio neto unitario,
  alícuota por línea (0, 10,5, 21, 27 o exento) e impuestos internos por línea (internal_tax_amount).
  Una línea con 99 % o más de bonificación es free_of_charge y no cambia ningún costo.
- Pie: neto gravado por alícuota, exento, IVA por alícuota, impuestos internos, percepciones (tabla
  purchasing.invoice_taxes: tipo enum iibb, vat_perception, municipal, other; jurisdicción; amount),
  bonificación general, redondeo y total. Check: todo suma el total, con 0,01 de tolerancia.
- Costos (decisiones 4 y 5): el costo es el precio neto de la línea. Ni los impuestos internos ni
  las percepciones suman al costo: se guardan aparte, cuentan para el total y el pago, y se ven en el
  tablero. Flete y servicios no se reparten y se ven como gasto. Prueba pgTAP: una línea con
  impuestos internos registra en price_records el neto sin ellos.
- Vencimiento: el impreso en la factura; si no tiene, el calculado con la condición del proveedor.
- Referencias: números de remito y de pedido que trae la factura, y la OC del sistema si está.
- Saldo informado por el proveedor (opcional): se guarda para compararlo con la cuenta corriente.
- Control de cantidad en artículos por peso: kg facturados contra kg recibidos (tolerancia 0,5 %,
  configurable por grupo).

PANTALLAS
- app/compras/facturas (tipo C): pestañas por estado (Cargadas, Observadas, Conformes, Liberadas,
  Pagadas), filtros proveedor, local y fecha, tabla (proveedor, tipo y número, fecha, total,
  estado con palabra, qué falló), 15 filas. «+ Nueva factura» abre el modal corto (proveedor y OC
  recibidas de ese proveedor en el local) y lleva a la ficha en borrador.
- app/compras/facturas/[id] (tipo B, sin scroll en 1440 × 900):
  1. Encabezado: «← Facturas», proveedor, «A 0003-00012345», fecha, chip de estado, a la derecha
     «Controlar» / «Dar por conforme» / «Observar» según el estado y el permiso.
  2. 4 indicadores: Total, Diferencia contra lo recibido, Diferencia contra la lista, Vence el.
  3. Tres columnas: a) datos fiscales (campos cortos; tipo como botones segmentados A / B / C; CAE;
     neto, IVA, percepciones, total con la cuenta que cierra en verde o no cierra en rojo, con
     palabra); b) líneas como planilla con scroll propio (nombre en factura, cantidad, precio,
     IVA, importe, y a la derecha los dos controles de la línea con ✓ / ✕ y tooltip que explica);
     c) «Todo junto»: foto original, foto firmada de la recepción, observaciones de la recepción,
     resultado de los controles, notas de crédito y débito con «+ Adjuntar NC / ND».
  4. Barra fija: contador, motivo, Descartar, Guardar. Conforme = solo lectura con la historia.
- Las NC / ND se cargan en panel lateral (tipo, número, fecha, importe, foto, motivo).
- Al quedar conforme, la ficha de materia prima y Costos muestran el precio nuevo con su origen
  «Factura A 0003-00012345 · Proveedor» (ya muestran de dónde viene cada precio).

PRUEBAS
- pgTAP (los casos con números, como los 27 de la Fase 2): factura igual a lo recibido y a la lista
  → conforme y liberada, con un price_records por línea en $ por envase y el costo por unidad de
  uso correcto (ejemplo: bolsa de 50 kg a $ 60.500 con IVA 21 % en A y razón social RI → neto
  $ 50.000 → $ 1.000 por kg; la misma en B → $ 1.210 por kg); cantidad facturada > recibida →
  observada por cantidad; precio distinto de la lista → observada por precio; sin lista vigente →
  observada; artículo sin mapear → observada y en la cola; NC que cierra la diferencia → conforme;
  conforme a mano por quien cargó la factura → rechazado; por el Controller → pasa; variación mayor
  al % → el precio entra y Dirección recibe el aviso;
  conforme inmutable; totales que no cierran → rechazado; única por tipo, PV y número; RLS (el
  cocinero no ve nada; el Gerente ve su local sin editar); auditoría con motivo; la cola de
  recálculo recibe el cambio.
- Vitest: Zod de la factura (CAE, PV, número, totales) y el texto de explicación de cada control.
- Playwright con axe: cargar una factura desde una OC recibida, controlar, ver un ✕ con su tooltip,
  adjuntar una NC, quedar conforme y ver el precio nuevo en la ficha de la materia prima; la ficha
  sin scroll en 1440, 1600 y 1920; celular: consulta.
- Corré todo. Mirá que las pruebas de precios de hoy (210, 211, 212) sigan en verde sin aflojarlas.

ENTREGA
Los tres revisores, con security-auditor obligatorio (toca costos). Capturas en
docs/capturas/facturas/ (listado, ficha observada, ficha conforme, panel de NC; 1440 y celular).
ADR nuevo con las decisiones 1 y 2 de Soy escritas. Lista de cambios para Soy. docs/estado.md.
Commit: «feat(compras): facturas con control de 3 vías y costos desde la factura conforme».
```

---

## Prompt 6: pagos, cuenta corriente y tablero de compras

```text
Leé docs/fases/fase-3-plan.md, docs/fases/fase-3-facturas.md (Etapa 5, «Estados y alarmas» y
«Pantallas» 8 y 9), docs/decisiones/0033 y 0045 (tableros tipo A), .claude/rules/design.md
(gráficos) y los PRs anteriores.
Tarea: pagos con agenda de vencimientos y cuenta corriente, el envío del comprobante en cola, las
alarmas consolidadas y el tablero de compras. Rama: feat/pagos-y-tablero-de-compras. Entrá en modo
plan y mostrame el plan antes de tocar nada.

BASE
- purchasing.payments: grupo, local, proveedor, fecha, medio (una de las cuentas de pago del
  proveedor), referencia, amount, comprobante (adjunto), notas, estado (enum: registered,
  receipt_queued). purchasing.payment_allocations: pago, factura, amount (un pago puede cubrir
  varias facturas y una factura puede pagarse en partes; la suma por factura no supera su saldo).
- Saldo de una factura = total − NC − descuentos + ND − pagos aplicados. Cuando llega a 0 pasa a
  paid, en la misma transacción (purchasing.register_payment).
- Cuenta corriente: vista reporting.v_supplier_account (por proveedor y local: facturado conforme,
  notas, pagado, saldo, última factura, último pago) y reporting.v_supplier_account_movements
  (cada movimiento con fecha, tipo, importe y saldo acumulado). Agenda: reporting.v_payment_schedule
  (facturas liberadas con saldo, vencimiento, días que faltan, estado: Al día / Vence en 7 días
  (warn) / Vencida (bad), siempre con palabra).
- Comprobante al proveedor: register_payment encola en purchasing.outbound_messages el aviso con el
  comprobante adjunto, por el canal de la ficha, desde la cuenta de la empresa (nadie lo despacha
  todavía, decisión 9).
- Alarmas consolidadas: vista reporting.v_purchasing_alerts, una fila por alarma pendiente con
  tipo, destinatario (permiso y alcance), entidad y enlace: lista vencida o no enviada, OC con
  novedad, recepción con diferencias, artículo sin mapear, factura observada, vencimiento próximo
  o vencido. Función purchasing.notify_due_payments() que avisa una vez por factura a 7 días y al
  vencer (kind payment_due), colgada del mismo trabajo programado que las listas vencidas.
- Tablero: vistas reporting.v_purchasing_kpis (por local y mes: gasto por rubro desde facturas
  conformes, cantidad de OC abiertas, facturas observadas, listas vencidas, pagos que vencen esta
  semana) y reporting.v_ingredient_cost_history (evolución del costo por unidad de uso de cada
  materia prima desde costing.price_records, para graficar inflación de insumos). Con el seed
  multiplicado (500 facturas, 5.000 líneas) cada consulta del tablero por debajo de 300 ms
  (explain analyze en el ADR).
- Incidencia ponderada de los aumentos (pedido de Soy, Etapa 1): vista
  reporting.v_price_list_impact: variación % de cada proveedor entre listas aceptadas, ponderada
  por su peso en la compra de los últimos 90 días.
- Permisos: purchasing.pay (purchasing), purchasing.view_payments (purchasing, controller,
  general_management, brand_director, restaurant_manager en su local, auditor),
  purchasing.view_dashboard (los mismos más executive_chef sin importes).
- Seed: 3 pagos (uno parcial, uno que paga dos facturas, uno con comprobante), una factura vencida
  y una que vence en 3 días.

FACTURAS REALES (sección del mismo nombre en este archivo)
- Los pagos en efectivo al recibir (Prompt 4) aparecen en «Pagos para confirmar»: Compras los
  confirma o los corrige con motivo.
- La cuenta corriente muestra al lado el último «saldo según el proveedor» cargado de una factura y
  la diferencia con el nuestro, con estado (Al día si coincide, Atención si no).
- El gasto por rubro separa lo que va a recetas de lo que no (limpieza, descartables, reventa), y
  muestra aparte fletes y percepciones.

PANTALLAS
- app/compras/pagos (tipo C): pestañas «Por vencer», «Vencidas», «Pagadas»; filtros proveedor y
  local; tabla (proveedor, factura, vencimiento, saldo, estado con palabra); «Registrar pago» en
  panel lateral: facturas a aplicar con sus saldos, medio (las cuentas de la ficha), importe,
  referencia, comprobante, motivo. Al confirmar: «Pago registrado. El comprobante quedó en cola
  para {canal}».
- Ficha de proveedor: el indicador «Saldo de cuenta corriente» ya muestra el saldo con estado, y la
  tarjeta «Cuenta corriente» muestra los últimos 5 movimientos y «Ver la cuenta corriente» (panel
  o pantalla con todos los movimientos y el saldo acumulado). También se llenan «OC abiertas» y
  «Última compra».
- app/compras (Tablero de compras, tipo A, entra en 1440 × 900 sin scroll como el Inicio):
  1. Encabezado «Compras · {local}» y la línea de datos; acción «Ver facturas observadas».
  2. Franja «Requiere atención» con la suma de alarmas y las 3 más urgentes.
  3. 4 KPIs (Metric): Facturas observadas, Vencen esta semana (con el importe para quien ve costos),
     OC abiertas, Listas de precios vencidas. Regla de estado única del sistema (missingState).
  4. Tres tarjetas: a) «Gasto por rubro del mes» (barras con chart-strong, hasta 5 rubros y
     «Otros», con «Ver el detalle»); b) «Cómo subieron los insumos» (líneas de hasta 4 materias
     primas que más pesan en la compra, 90 días, con «Ver todas»); c) «Alarmas» (hasta 5 filas con
     tipo, palabra de estado y enlace, «Ver todas»).
  5. Fila de abajo: «Artículos sin mapear (N)» con «Mapear» y «Pagos próximos» (5 filas).
  Quien no ve costos ve el tablero sin importes (los KPIs de plata dicen «Sin acceso a importes»).
  Celular: franja, KPIs de a 2 y alarmas; sin gráficos.
- Barra lateral: «Tablero de compras» y «Pagos» en Gestión y análisis.

PRUEBAS
- pgTAP: pago parcial deja saldo y no cambia el estado; pago total → paid en la transacción; un
  pago sobre dos facturas; no se puede aplicar más que el saldo; NC y ND en el saldo; agenda con
  los bordes (vence hoy, venció ayer, 7 días exactos); avisos una sola vez; RLS (el cocinero no ve
  pagos; el Gerente ve su local); auditoría; rendimiento del tablero bajo 300 ms con datos
  multiplicados.
- Vitest: la regla de estado de los KPIs del tablero reutiliza missingState (sin regla nueva).
- Playwright con axe: registrar un pago parcial y total; la cuenta corriente del proveedor cambia;
  el tablero sin scroll en 1440, 1600 y 1920; quien no ve costos no ve importes; celular.
- Corré todo.

ENTREGA
Los tres revisores. Capturas en docs/capturas/pagos-y-tablero/ (pagos, panel de pago, cuenta
corriente, tablero en 1440, 1600, 1920 y celular). ADR nuevo. Lista de cambios para Soy.
docs/estado.md con la compuerta de la Fase 3 (qué valida Soy con datos de prueba antes de cargar
proveedores reales). Commit: «feat(compras): pagos, cuenta corriente y tablero de compras».
```
