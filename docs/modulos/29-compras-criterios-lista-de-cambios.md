# Compras con tus criterios de pantallas — lista de cambios (PR A)

_2026-11-26. Primera de las 4 partes de las correcciones de Compras (`docs/prompts/2026-11-23-correcciones-compras.md`). ADR-0068._

## Qué cambia, en simple

- **Listados con los proveedores a la izquierda.** En Órdenes, Facturas, Pagos y Listas de precios hay un panel fijo con cada proveedor y cuántos registros tiene. Un clic filtra la tabla. En Proveedores, el panel muestra los rubros. La tabla está al lado y se desplaza sola, sin mover la página.
- **Fechas siempre dd/mm/aaaa,** también si Chrome está en inglés. Se escribe «19112026» y aparece «19/11/2026». El ícono del calendario abre el calendario.
- **Ningún «Choose File».** Para subir archivos hay un botón «Subir foto o PDF» (o «Subir planilla»), y al lado se ve el nombre del archivo. En el celular también aparece «Sacar foto».
- **Títulos de 20 px en todo el sistema,** y los botones del encabezado en fila, nunca apilados.
- **Ficha de la orden de compra en una pantalla,** con 4 indicadores: artículos, entrega esperada, cuánto se recibió y novedades.
- **Ficha de factura:** la columna «Datos de la factura» se ve entera, sin scroll. El pie (neto, IVA, percepciones, total) pasó debajo de las líneas, como en el papel.
- **Nombres sin «…»** en el tablero y en los listados: si no entran, pasan a dos renglones.

## Para probar en staging

1. **Facturas:** elegí «Lácteos Demo» en el panel de la izquierda. El número del panel tiene que coincidir con «N facturas» de la tabla. «Todos los proveedores» vuelve a la lista entera.
2. **Fecha:** en Facturas, escribí «01112026» en «Desde». Tiene que quedar «01/11/2026» y la lista se filtra sola.
3. **Archivo:** en Proveedores → «Importar desde planilla» tiene que decir «Subir planilla», nunca «Choose File».
4. **Orden de compra:** abrí una. Arriba van los 4 indicadores y los botones en fila. Nada tiene scroll de página.

## Qué no cambia todavía

La nueva orden en una pantalla, el alta de factura, la orden de pago completa y la carga de listas llegan en las partes B, C y D.
