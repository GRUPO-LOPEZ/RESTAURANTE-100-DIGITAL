# Órdenes de compra (lista de cambios para Soy)

Tercera entrega del módulo de compras y facturas (Fase 3). Detalle técnico en ADR-0053.

## Qué cambia para cada persona

- **Cocinero, jefe de cocina, chef y gerente:**
  - desde el celular, en **Órdenes de compra → Nueva orden**, eligen el proveedor;
  - cargan las cantidades con botones − / + grandes: primero aparece lo que más pide ese local;
  - y tocan **«Mandar OC»**;
  - si una materia prima no está entre los artículos del proveedor, se busca y se agrega «sin nombre de factura»;
  - la fecha de entrega se calcula sola con los días de entrega del proveedor;
  - cada orden lleva su número por local, por ejemplo **PCE-0001**.
- **Compras:**
  - si el proveedor tiene marcado «requiere aprobación», la orden le llega a **Aprobaciones** con sus artículos. La aprueba o la rechaza. **Nunca la aprueba quien la pidió**, como pediste;
  - registra novedades («no tiene ricota, llega el jueves»), y a quien pidió la orden le llega el aviso.
- **Mensaje al proveedor:**
  - va con el número bien visible y el pedido de ponerlo en «Orden de compra» de la factura, el local, nuestro número de cliente, la entrega y los artículos;
  - lo que va por peso, con los kg estimados;
  - **por ahora queda «En cola de envío»** (tu decisión 9): todavía no se manda solo por WhatsApp o mail. Mientras tanto, el texto se ve en la orden y se puede copiar.
- **Avisos:** en Aprobaciones ahora se ven también los avisos de compras (cuentas de proveedor, artículos sin mapear, listas vencidas y novedades de órdenes). Antes solo sumaban en la campana. Quien no tiene Aprobaciones, como el cocinero, ve las novedades de sus órdenes arriba del listado de órdenes.
- **Nadie ve precios en las órdenes:** hoy no se cargan. Los controla Compras con la factura.

## Qué controla el sistema

- **El número no se repite ni salta**, aunque dos personas pidan a la vez.
- **Un local sin código no puede pedir:** antes hay que cargar su código en el Panel de control.
- **No se puede pedir un artículo de otro proveedor.**
- **Cada uno ve las órdenes de su local;** Compras y Dirección, las de todo el grupo.
- **Cancelar una orden no la borra:** queda cancelada con su motivo, y si estaba en cola, no se manda.

## Lo que todavía no está

- **Mandar el mensaje solo** por WhatsApp o mail: se suma cuando se defina la cuenta de la empresa.
- **La recepción** (Prompt 4): marcar qué llegó, con fotos.

## Antes de usarlo de verdad

- **Cargá el código de cada local** en el Panel de control (por ejemplo, RAG para Ragú). Sin código, el local no puede pedir.

## Para probar en staging

1. Con el usuario de cocina, en el celular: Órdenes de compra → Nueva orden, elegir un proveedor, sumar dos artículos y «Mandar OC».
2. Con un proveedor que requiere aprobación: mandarla y, con Compras, aprobarla en Aprobaciones.
3. Con Compras, registrar una novedad en una orden y mirar que le llegue a quien la pidió.
