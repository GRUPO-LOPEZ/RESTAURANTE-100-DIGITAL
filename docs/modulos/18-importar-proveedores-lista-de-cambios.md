# Importar proveedores desde planilla (lista de cambios para Soy)

Para la carga inicial de los proveedores reales, en producción. Detalle técnico en ADR-0055.

## Qué cambia

- **Compras** tiene, en **Proveedores**, el botón **«Importar desde planilla»** (en la computadora).
  1. **Baja la plantilla:** un Excel con las columnas, una fila de ejemplo y una hoja «Valores» con las opciones y los rubros.
  2. **Completa una fila por proveedor.** Solo la razón social y el CUIT son obligatorios. Se puede cargar también:
     - nombre de fantasía, condición IVA, domicilio, localidad, teléfono, WhatsApp, correo y contactos;
     - rubros, días de pedido y de entrega;
     - canal de la orden de compra y si requiere aprobación;
     - condición de pago y pedido mínimo.
  3. **Sube la planilla y toca «Revisar».** Ve qué pasa con cada fila: **Se crea**, **Se omite** (ese CUIT ya está cargado) o **Error**, con el motivo.
  4. **Si no hay errores,** escribe el motivo y toca **«Crear N proveedores»**.
- **No van en la planilla** las cuentas de pago (CBU, alias) ni los números de cliente por local. Se cargan a mano en la ficha de cada proveedor, porque un cambio de cuenta es el punto más delicado para el fraude.

## Qué controla el sistema

- **Si una fila tiene un error, no se crea ninguno.** Se corrige la planilla y se sube de nuevo.
- **Un CUIT que ya está cargado no se duplica:** esa fila se omite. Así se puede subir la planilla corregida sin miedo.
- **Un CUIT por proveedor, en todo el sistema:** tampoco se puede dar de alta a mano un proveedor con el CUIT de otro, ni cambiarlo en la ficha por uno que ya está. El sistema avisa «Ya hay un proveedor con ese CUIT en el grupo».
- **Revisar no crea nada.** Solo «Crear» crea, y queda en el historial con el motivo y como «Carga masiva».
- **Solo Compras y Dirección** pueden importar.
- **La planilla no se guarda en el sistema:** sus datos quedan en la ficha de cada proveedor.
