# ADR-0071 — Listas de precios: importar, controles, versiones y anulación

- **Fecha:** 2026-11-27
- **Estado:** plan aprobado por Joaco (2026-11-27).
- **Pedido:** correcciones de Compras de Soy, parte D (`docs/prompts/2026-11-23-correcciones-compras.md`, decisiones 12, 13 y 16 a 24; boceto `Lista.dc.html`). Sigue a ADR-0052.
- **Migraciones:** `20261220120000_price_list_voided.sql` (el estado nuevo va solo, porque un valor de enum no se usa en la misma transacción en que se agrega) y `20261220120100_price_list_versions.sql`.

## Decisiones de Joaco (2026-11-27)

- **Se parte en D y E.** Este es D. El pedido automático por mail cuando vence una lista y el botón de WhatsApp van en E, cuando Soy cargue la contraseña de aplicación.
- **El mail será Gmail / Google Workspace** (SMTP de Google).
- **Solo saldrá el pedido de lista:** las órdenes de compra y de pago siguen en cola sin enviarse.

## Decisión

1. **Importar sin IA, en el servidor** (`lib/imports/price-list-file.ts`):
   - **Excel (.xlsx)** con `exceljs`, que ya estaba (con el control del zip de ADR-0055). Se elige la hoja; si no, se toma la primera que tenga encabezados.
   - **CSV** con un lector propio: `;` o `,`, comillas, coma decimal y puntos de miles.
   - **PDF hecho por computadora** con **`pdfjs-dist` 6.5.438** (tecnología nueva):
     - el texto de cada página se agrupa en renglones por su altura;
     - cada texto va a la columna del encabezado cuyo centro está más cerca, así que los números alineados a la derecha caen bien.
   - **Una foto o un PDF sin texto** abren la **pantalla dividida**: el archivo a la izquierda, con zoom y arrastre, y la planilla a la derecha para tipear. La lectura automática es del agente de Facturas, en la Fase 5: no hay código de agentes.
   - **Columnas reconocidas por su encabezado, con sinónimos** («Descripción», «Cód.», «Precio s/IVA», «Desc. %», «Alícuota»…). La persona puede cambiar la columna de cada dato con un desplegable.
   - Se saltean títulos de rubro, totales y renglones sin precio, y se cuentan.
   - Topes: 3,5 MB y 500 renglones.
   - **El original queda guardado con la lista.** El bucket y `attachments` aceptan `xlsx` y `csv`. El tipo se decide por el contenido, nunca por la extensión.
2. **Planilla modelo** (decisión 22): `/proveedores/[id]/planilla-lista` genera un `.xlsx` con nuestras columnas y un renglón de ejemplo inventado. Se baja desde el indicador de la ficha del proveedor y se reconoce sola al subirla.
3. **Controles con una sola regla** (`purchasing.price_line_check`), que usan la vista previa de la carga (`price_list_preview`) y la ficha (`price_list_changes`). Cada renglón tiene:
   - la variación contra la lista vigente;
   - la suba **resaltada si pasa el umbral de Dirección** (`costing.price_settings.approval_variation_pct`, 15 % por defecto);
   - **«Revisar»** si el neto es 10 o más veces mayor o menor que el anterior;
   - el **precio por unidad de uso** del envase («$ 9.856 por kg»; por kg o por litro si el contenido viene en gramos o mililitros).
4. **Aceptar con «Revisar» pide confirmarlos** (`accept_price_list(…, p_confirm_review)`). La base lo vuelve a controlar.
5. **Artículo elegido a mano y recordado** (decisión 21):
   - en la planilla, «Es…» elige el artículo del proveedor (`purchase_product_id`), y la base controla que sea de ese proveedor;
   - al aceptar o corregir, cada renglón que no se reconocía solo entra a la cola de mapeo con la sugerencia; cuando el chef la confirma queda como otro nombre (`article_aliases`) y la próxima lista lo reconoce sola (ver Revisiones).
6. **Versiones** (decisión 13): `correct_price_list` corrige la vigente.
   - Crea la versión N+1, ya aceptada, con la misma vigencia. La anterior queda reemplazada.
   - Todo en una transacción y con motivo. Una versión se corrige una sola vez.
7. **Anular** (decisión 24): `void_price_list` anula una recibida o la vigente, con motivo y sin borrar nada.
   - Si era la vigente, vuelve a valer la última reemplazada del proveedor (la versión que corregía o la lista anterior).
   - «Todas» no muestra las anuladas; tienen su filtro, «Anuladas».
8. **Pantallas:**
   - la carga y la ficha son sin scroll de página, como el boceto;
   - la ficha tiene 4 indicadores (artículos, subas sobre el umbral, para revisar y sin reconocer);
   - acciones en fila: el original, las versiones, Anular, Corregir y Aceptar;
   - «Aceptada» pasa a decir «Vigente».

## Revisiones (2026-11-27)

- **Quién deja recordado un artículo (decisión de Joaco):** Compras elige y el chef confirma. Al aceptar o corregir, lo elegido a mano entra a la cola de mapeo con la sugerencia (`unmapped_articles.suggested_product_id`), y el chef lo confirma con «Es el mismo que…», que ya viene elegido. El motivo: el recuerdo también reconoce las facturas, que escriben costos. Esto ajusta el punto 5.
- **El umbral de Dirección resalta solo las subas** (decisión 19 de Soy). En costing el mismo umbral mira las dos direcciones para pedir la aprobación de Dirección. Queda escrito en `price_line_check`.
- **Base:**
  - la corrección conserva el aviso de vencida;
  - la vista previa controla el permiso sin `not in` y corta en 500 renglones;
  - un número mal escrito deja ese renglón sin neto en lugar de romper toda la vista previa;
  - la vista previa no devuelve el umbral;
  - los comentarios de estado quedaron al día;
  - pgTAP 423 suma la cocinera, anular la vigente (vuelve la anterior), una sola vigente, la auditoría, costos intactos y corregir sin confirmar los «Revisar».
- **Seguridad:**
  - el PDF se cierra siempre y se corta a 50.000 textos o 500.000 caracteres, sin XFA ni canvas;
  - el archivo que se guarda se controla entero, con la misma regla que al leerlo (el Excel también por dentro);
  - un Excel o CSV guardado se descarga, no se abre en el navegador;
  - la planilla modelo controla el grupo del proveedor.
- **Pantallas:**
  - el error de un renglón va en su campo y escrito en «Control»;
  - la pantalla dividida le da más ancho a la planilla;
  - columnas y avisos más cortos;
  - los renglones ya no saltan de alto;
  - los mismos nombres en la carga y en la ficha;
  - «Ver los N».
- **Pendiente, anotado:**
  - leer el PDF en un proceso aparte con tope de memoria y de tiempo (hoy se corta por cantidad de texto);
  - al anular una lista, los artículos que dejó en la cola siguen ahí hasta que el chef los resuelva;
  - una prueba con un segundo grupo (el seed tiene uno solo);
  - pdfjs-dist trae un binario opcional de canvas que no se usa.

## `pdfjs-dist` (tecnología nueva)

- **Por qué:** decisión 17 de Soy («los PDF generados por computadora se leen sin IA»). Leer el texto con su posición es lo único que permite armar columnas.
- **Qué es:** la biblioteca de PDF de Mozilla, la de Firefox. Licencia Apache-2.0, sin servicios externos.
- **Cómo se usa:**
  - solo en el servidor, con la versión `legacy` de Node;
  - fuera del empaquetado de Next (`serverExternalPackages`), porque carga su «worker» con una importación dinámica;
  - sin fuentes del sistema ni scripts.
- **Descartados:**
  - `pdf-parse`: devuelve el texto sin posiciones, y no se pueden armar columnas;
  - un servicio de OCR o IA: lo pidió Soy sin IA, y es de la Fase 5.
- `pdf-lib` entra solo como dependencia de desarrollo, para armar los PDF inventados de las pruebas.

## Límites conocidos

- Un PDF con columnas muy desordenadas puede leerse mal. Se ve en la planilla antes de cargar, se corrige la columna o se tipea con la pantalla dividida.
- El formato viejo `.xls` no se lee: se pide guardarlo como «Libro de Excel».
- El panel de «Es…» muestra todos los artículos activos del proveedor en un desplegable.
- **Next 16 conserva el estado de una pantalla ya visitada** aunque cambien los parámetros de la dirección. La planilla lleva una clave por lista para que «Corregir» no muestre la carga anterior.
