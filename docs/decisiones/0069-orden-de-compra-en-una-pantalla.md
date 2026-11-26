# ADR-0069 — Orden de compra en una pantalla, solo artículos del proveedor

- **Fecha:** 2026-11-26
- **Estado:** plan aprobado por Joaco (2026-11-26).
- **Pedido:** correcciones de Compras de Soy, parte B (`docs/prompts/2026-11-23-correcciones-compras.md`, decisiones 1 a 3; boceto `2026-11-23-boceto-compras/Main.dc.html`). Cambia la pantalla de ADR-0053.

## Decisión

1. **Una sola pantalla, sin pasos ni pantalla de «elegí el local»** (criterio 2):
   - el local sale del selector de arriba; con «Todos mis locales», la misma pantalla lo pregunta en una línea (botones hasta 5; si hay más, un desplegable);
   - en la computadora, tres columnas: los proveedores con «Hoy pide» o «Próximo: martes», sus artículos y la orden;
   - en el celular, una columna: el proveedor en un desplegable, los artículos con − / + de 44 px y la barra fija abajo.
2. **El catálogo para pedir** (`purchasing.order_catalog`):
   - primero lo pedido a ese proveedor en ese local en los últimos 60 días, en órdenes que salieron; después el resto;
   - el precio neto por envase de la lista vigente hoy, y si incluye IVA;
   - **la cantidad arranca en 0**, sin «la última vez» (decisión 2).
3. **Quién ve importes** (decisión de Joaco): el precio, el subtotal y el total estimado los ve **solo quien ve listas de precios** (`purchasing.view_price_lists`), y la base lo decide. El cocinero arma la orden sin importes.
4. **El pedido mínimo ya existía:** está en la condición de pago del proveedor (`supplier_payment_terms.minimum_order_amount`), que ya se editaba en su ficha. No hizo falta una columna nueva.
   - En la orden se ve con **la misma regla que en la ficha**: quien ve la condición de pago (`purchasing.can_see_payment`: Compras, Controller y Dirección).
   - No se usó «ve listas de precios», porque le habría mostrado el mínimo a quien hoy no lo ve en la ficha, como el gerente o el director de marca.
   - Avisa «Faltan $ …» o «Supera $ …», pero **no frena** la orden.
5. **La aprobación sigue siendo por proveedor** (decisión de Joaco): no hay monto de aprobación.
6. **Solo artículos del proveedor** (decisión 3):
   - `save_order_draft` pasa a ser interna (`save_order_draft_internal`, sin cambios y sin permiso para la app);
   - la nueva, con el mismo nombre y firma, rechaza toda línea que no sea `purchase_product_id` con «Pedí artículos del proveedor: si no está, sumalo primero a su catálogo.»;
   - la app no escribe `purchase_order_lines`, así que esa función es la única entrada;
   - en el navegador, el esquema es estricto: una clave de más se rechaza y no se descarta en silencio;
   - las OC que ya tenían líneas con materia prima no se tocan y se siguen recibiendo y facturando. Las pruebas 370 y 371 las arman como estaban guardadas.
7. **«Mandar OC» pasa a «Enviar orden»**, como en el boceto. «Enviar a aprobación» queda igual.

## Opciones descartadas

- **Copiar entera `save_order_draft` para quitarle la rama de materia prima:** serían unas 100 líneas duplicadas. El envoltorio deja la de antes intacta y probada.
- **Un trigger en `purchase_order_lines`:** también frenaría a quien recibe una OC vieja si se reescriben sus líneas. Además, hoy la única forma de escribir esa tabla es la función.
- **Mostrar el mínimo a quien ve listas:** le habría abierto un dato de la condición de pago a quien hoy no lo ve.
- **Precalcular el catálogo en `reporting`:** no hace falta con el volumen de hoy. Lee una lista vigente y las OC de 60 días de un local.

## Pendiente, anotado

- **Revisiones:**
  - **Seguridad:** apta. Se cerraron las funciones que la app ya no usa y el catálogo ahora controla que el proveedor esté activo y sea del grupo.
  - **Base:** se corrigió el grave. Un proveedor sin días de entrega ya no corta la pantalla: la próxima entrega queda vacía y se elige en la orden. También se corrigieron los medios (un índice para lo reciente y casos nuevos en la 420) y los menores: el permiso se controla antes que las líneas, para que el rechazo quede registrado.
  - **Diseño:** se corrigieron los medios:
    - fecha dd/mm;
    - «Enviar orden» también en la ficha;
    - sin «$ 0» engañoso: sin precios, «—»; con faltantes, «desde»;
    - la cantidad solo acepta números;
    - los días de pedido de cada proveedor;
    - el aviso sin proveedores en el celular;
    - la barra pegada abajo, sin tapar el menú.
- **«Últimos 60 días»:** son hoy y los 59 anteriores, en hora de la Argentina.
- **El número de la orden sale al guardarla,** no al enviarla: un borrador que nunca se envía igual usa su número. Es la regla de ADR-0053 y no se cambió.
- **Diferencias con el boceto, aceptadas:**
  - los artículos van en una lista sin encabezados de columna, y el subtotal está en «La orden», al lado de cada renglón;
  - no hay «Buscar proveedor» (si son muchos, la lista se desplaza);
  - el encabezado no muestra el número que va a tener;
  - los botones van en una tarjeta debajo de «La orden»;
  - la aprobación es por proveedor, no por monto.
- **IVA en el total:** cada precio dice si es con o sin IVA, pero el total no lo dice. Queda para cuando una misma orden mezcle listas.

- `order_ingredient_search` y `supplier_product_ranking` quedan en la base, pero sin permiso para la app (no se usan). Se pueden borrar más adelante.
- Para pedir algo que el proveedor no tiene, primero hay que sumarlo a su catálogo, desde su ficha o desde una lista de precios. La pantalla vacía lo explica.
- El total es estimado: el costo real sale de la factura.
