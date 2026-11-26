# ADR-0068 — Criterios de Soy en Compras: panel de grupos, archivo y fecha propios, título de 20 px

- **Fecha:** 2026-11-26
- **Estado:** plan aprobado por Joaco (2026-11-26).
- **Pedido:** correcciones de Compras de Soy (`docs/prompts/2026-11-23-correcciones-compras.md`, parte A) con sus 15 criterios de pantallas (`.claude/rules/design.md`, PR #106). Es el primero de 4 PRs (A a D). Cambia las pantallas de los ADR-0052, 0053, 0058 y 0060.

## Decisión

1. **Listados con panel a la izquierda** (criterio 7). Órdenes, facturas, pagos y listas de precios agrupan por proveedor; proveedores agrupa por rubro (`components/ui/group-panel.tsx`, token `group-panel` de 250 px). Cada grupo muestra su cantidad. La cuenta la hace la base con los mismos filtros y permisos de la lista, menos el del grupo: `purchasing.order_supplier_counts`, `invoice_supplier_counts`, `payment_supplier_counts`, `price_list_supplier_counts` y `supplier_rubro_counts` (migración `20261219120000`, pgTAP 419, que compara cada conteo con su lista para cuatro roles). Pagos es `security definer`, como su agenda, y filtra igual (`purchasing.view_payments`). El panel son enlaces: el filtro queda en la dirección. En el celular no hay panel: queda el filtro de arriba.
2. **Pantalla fija con la tabla desplazándose adentro**, como Costos (ADR-0048). Para que la tabla entre a lo ancho en 1440 junto al panel:
   - las columnas de texto pasan a dos renglones (`DataColumn.wrap`): la principal con 160 px como mínimo y las secundarias con 96 px;
   - cortan entre palabras (`overflow-wrap: break-word`);
   - los encabezados largos también pasan a dos renglones;
   - una columna que repite lo que dice otra parte de la pantalla puede verse solo en el celular (`desk: "hidden"`). Es el caso del estado de los proveedores, que ya dice la pestaña Activos / Inactivos.
3. **Fechas dd/mm/aaaa propias** (criterio 12). El campo de fecha del navegador sigue el idioma de Chrome. `components/ui/date-input.tsx` es un campo de texto con las barras puestas solas, más un botón que abre el calendario del navegador (`showPicker`). El valor viaja en ISO en un campo oculto, así que las acciones de servidor y los filtros no cambian. `FormDate` lo conecta con React Hook Form. La lectura está en `lib/dates.ts`, con Vitest. Reemplaza los 22 campos de fecha de la app. No se agregó ninguna librería (decisión de Joaco).
4. **Subir archivos con botón propio** (criterio 12). `components/ui/file-upload.tsx` muestra «Subir foto o PDF», «Subir planilla», etc., y al lado el nombre del archivo. El input sigue siendo el control (Tab, teclado, `required`, la etiqueta del campo), pero transparente y encima del botón. En el celular, con imágenes, suma «Sacar foto» con su propio nombre de campo. Reemplaza los 8 campos de archivo a la vista. Una prueba de Vitest (`no-native-inputs`) frena un campo de fecha o de archivo del navegador nuevo.
5. **Título de 20 px en todas las pantallas** (decisión de Joaco: todo el sistema). Las acciones del encabezado van en fila y no se achican. Si no entra todo, baja lo de la izquierda (criterio 5).
6. **Ficha de la OC**:
   - en una pantalla, con 4 indicadores (Artículos, Entrega esperada, Recibido, Novedades), sin precios y con la regla de métricas confiables: antes de mandarla, lo recibido no se mide (`orderIndicators`, con Vitest);
   - las tarjetas se desplazan adentro;
   - «Cancelar la orden» pasa a «Cancelar», como en la factura (criterio 15);
   - «pedida el …» sale del encabezado porque ya está en «Qué pasó».
7. **Ficha de factura**: la columna de datos ahora entra entera en los cuatro tamaños, con 26 px de margen o más:
   - pasa a 5 : 7 : 4;
   - la fecha y el vencimiento van en la misma fila, igual que los dos CUIT, y desde 1700 px también la autorización;
   - el pie va debajo de las líneas, como en el papel.
8. **Nombres sin «…»** (criterio 13) en el tablero de compras y en los listados: pasan a dos renglones. En «Pagos próximos», si el nombre no entra, la fecha y el importe bajan a su renglón.
9. **Novedades de mis órdenes**: se ven las 3 más nuevas y el título dice cuántas hay en total. La pantalla no crece con los datos.

## Opciones descartadas

- **Una librería de calendario** (react-day-picker): es tecnología nueva y no hacía falta para que el campo se lea dd/mm/aaaa.
- **Contar en el navegador con la página que llega:** solo vería 15 filas. Y **una sola función de conteo con «tipo de lista»:** mezclaría reglas de permisos distintas.
- **Esconder la columna Local cuando hay un local elegido:** cambia la tabla según el selector. Con dos renglones alcanza.
- **Achicar letra o controles para que entre:** el diseño lo prohíbe (ADR-0051).

## Pendiente, anotado

- El calendario que se despliega sigue el idioma de Chrome. El campo siempre muestra dd/mm/aaaa.
- Con un proveedor de nombre largo y tres acciones, el encabezado de la OC pasa a dos renglones en 1440. Las acciones siguen en fila. **Joaco decidió dejarlo así (2026-11-26).**
- Si un grupo tiene cientos de proveedores, el panel se desplaza adentro. La búsqueda dentro del panel queda para cuando haga falta.
- La nueva OC, el alta de factura, «Registrar pago» y la carga de listas se rediseñan en los PR B, C y D. Acá solo recibieron la fecha y el archivo propios.
- Revisiones:
  - **Seguridad:** apta.
  - **Base:** los dos medios se corrigieron. Ninguna comparación de la prueba 419 pasa ahora sin datos: una gerente de dos locales tiene facturas y un pago, y cada filtro se ejercita.
  - **Diseño:** se corrigieron el grave (`FormDate` sin etiqueta con React Hook Form) y los medios.
- Quedan anotados:
  - **Botones de calendario con el mismo nombre:** todos se llaman «Abrir calendario». Desde / Hasta quedan con dos iguales. Si el nombre incluye la etiqueta, `getByLabel("Desde")` encuentra también el botón.
  - **«Sacar foto»** no tiene descripción propia.
  - **Proveedores sin rubro:** solo aparecen en «Todos». Decidir si hace falta un grupo «Sin rubro».
  - **Rendimiento de las listas de precios:** el conteo calcula el vencimiento de cada lista, igual que la lista. Hay que medirlo con volumen.
