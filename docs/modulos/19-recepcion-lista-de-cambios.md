# Recepción y stock (lista de cambios para Soy)

Cuarta entrega del módulo de compras y facturas (Fase 3). Detalle técnico en ADR-0056.

## Qué cambia para cada persona

- **Gerente, jefe de cocina y cocinero** reciben desde el celular, en la puerta de la cocina, en **Recepción**:
  1. **«¿Qué llegó?»:** las órdenes del local para recibir, por proveedor y las de hoy primero. Se toca **«Recibir»**.
  2. **Foto 1:** qué papel trajo el proveedor (remito, factura, factura-remito, remito electrónico, comprobante no fiscal o nota a mano) y una foto del papel tal como llegó. Si tiene varias hojas, «Otra página».
  3. **Renglón por renglón:** **✓ OK** o **✕ Observar**. Al observar se dice qué pasó (faltó, de más, otro producto, mala calidad o vencido), cuánto llegó y, si se quiere, una nota, el lote y una foto del producto. También se puede anotar «llegó algo que no estaba».
  4. **Foto 2:** el papel firmado.
  5. **Resumen:** si se pagó en efectivo, el importe, y el motivo si hubo observaciones. **«Cerrar recepción».**
- **Quien pidió la orden** recibe el aviso: «Llegó la orden», «Llegó parte de la orden» o «Llegó con observaciones». En la ficha de la orden aparece la sección **Recepción**, con las dos fotos, lo observado y los lotes.
- **Compras** recibe un aviso si hubo observaciones o si se pagó en efectivo, para confirmar el importe. También puede recibir.
- **«Recibir mercadería» en el Inicio:** quien recibe lo tiene arriba de todo, a un toque, también en el celular.
- **Recibir sin orden:** si llega mercadería sin orden de compra, «Recibir sin OC», se elige el proveedor y se anota lo que llegó.
- **Inventario** (Dirección, directores de marca, gerentes, chefs, jefes de cocina, Controller y Auditor): lo que entró al stock de cada local, en la unidad de uso, con su lote. Se puede **buscar un lote**, también desde Calidad.

## Qué controla el sistema

- **No se cierra sin las dos fotos** (como llegó y firmado) **ni sin decidir cada renglón.**
- **Con observaciones, el motivo es obligatorio.** Queda en el historial.
- **Lo que se carga tiene que tener sentido:** si se marca «faltó», tiene que haber llegado menos de lo pedido; si es «de más», más.
- **La orden queda recibida o recibida en parte.** Si faltó algo, cuando llega se vuelve a recibir solo lo que faltaba.
- **El stock entra en la unidad de uso:** 2 bolsas de 50 kg de harina son 100.000 g. Lo que va por peso entra con los kilos pesados.
- **Lo que llegó y el sistema no reconoce** va a la lista del chef para decir qué materia prima es; hasta entonces no suma stock.
- **Una recepción cerrada no se cambia,** y una entrada de stock no se borra: se corrige con otra.
- **El cocinero no ve el importe en efectivo:** sabe que se pagó, pero el importe lo ven quienes ven precios.
- **Cada uno recibe y ve lo de su local;** Compras y Dirección, todo el grupo.
- **Lo vencido no entra al stock;** lo de mala calidad que se acepta, sí.
- **Si se recibe sin orden de compra, Compras se entera** con un aviso.
- **Si algo que va por peso pesa más de un 20 % distinto de lo esperado,** no se puede marcar OK: hay que observarlo y decir el motivo.

## Lo que todavía no está

- **La factura** (Prompt 5): si el papel es una factura, en ese prompt se carga desde la recepción, con estas fotos.
- **El pago en efectivo** (Prompt 6): hoy queda anotado y avisa a Compras; ahí pasa a un pago «para confirmar».
- **Descontar stock** (ventas, conteos): por ahora solo entra (tu decisión D8).

## Para probar en staging

1. Con el usuario de cocina, mandar una orden de dos artículos.
2. Con el gerente, en el celular: Recepción → Recibir, sacar la foto del remito, marcar uno OK y el otro «Faltó», sacar la foto firmada y cerrar.
3. Con el usuario de cocina, ver el aviso en Órdenes de compra y la sección Recepción en la orden.
4. Con el Controller: Inventario, buscar el lote.
