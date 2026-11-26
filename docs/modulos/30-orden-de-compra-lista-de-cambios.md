# Orden de compra en una pantalla — lista de cambios (PR B)

_2026-11-26. Segunda parte de las correcciones de Compras (`docs/prompts/2026-11-23-correcciones-compras.md`, decisiones 1 a 3). ADR-0069._

## Qué cambia, en simple

- **Una sola pantalla.** Ya no aparece la pantalla de «elegí el local»: se usa el local de arriba. Si arriba dice «Todos mis locales», la misma pantalla pregunta «¿Para qué local es la orden?» con un botón por local.
- **En la computadora, tres columnas:**
  - a la izquierda, los proveedores, con «Hoy pide» o «Próximo: martes»;
  - al medio, sus artículos;
  - a la derecha, la orden.
- **En el celular, una columna:**
  - el proveedor arriba;
  - los artículos con botones grandes de más y menos;
  - abajo, siempre a la vista, la cantidad, el total y «Enviar orden».
- **Primero lo que se pidió en los últimos 60 días** en ese local, después el resto. **La cantidad arranca en 0** en todos.
- **Precio de la lista vigente, subtotal y total estimado,** solo para quien ve listas de precios. La cocina arma la orden igual, sin importes.
- **Pedido mínimo:** la orden avisa «Faltan $ …» o «Supera $ …». No frena. Lo ve quien ve la condición de pago del proveedor (Compras, Controller y Dirección), igual que en la ficha.
- **«Llega martes 24/11 · Cambiar»:** la entrega se cambia ahí mismo.
- **Solo artículos de ese proveedor.** Ya no se puede pedir una materia prima suelta «sin nombre de factura». Si el artículo no está, primero se suma al catálogo del proveedor.
- El botón dice **«Enviar orden»** (antes, «Mandar OC»).

## Para probar en staging

1. **Como Compras,** con Demo Pastas Centro arriba: Órdenes de compra → «Nueva orden».
   - Elegí Lácteos Demo: arriba aparecen «Pedidos en los últimos 60 días», con precio y cantidad en 0.
   - Sumá dos envases: tienen que aparecer el total y el aviso del mínimo.
2. **Con «Todos mis locales» arriba:** «Nueva orden» pregunta el local en la misma línea.
3. **Como cocinera, en el celular:** armá una orden y mandala. No tiene que aparecer ningún importe.
