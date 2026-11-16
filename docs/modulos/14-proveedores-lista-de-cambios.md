# Proveedores: ficha completa (lista de cambios para Soy)

Primera entrega del módulo de compras y facturas (Fase 3). Detalle técnico en ADR-0050.

## Qué cambia para cada persona

- **Compras:**
  - tiene la pantalla **Proveedores**, en la barra lateral, debajo de Rubros;
  - da de alta un proveedor con la razón social y, si tiene, el CUIT. El código lo pone el sistema (PROV-0001);
  - completa la ficha en una sola pantalla y guarda todo junto, con un motivo que queda en el historial:
    - **Identificación y contacto:** razón social, nombre de fantasía, CUIT, condición frente al IVA, domicilio, teléfonos, correo y contactos.
    - **Operativa:** días de pedido y de entrega (un clic por día), horario de recepción, por dónde se le manda la orden de compra (WhatsApp, mail o su sistema) y a qué dato, si la orden necesita aprobación, cómo factura, cada cuánto manda la lista de precios y nuestro número de cliente en cada local.
    - **Pago:** condición (contado, contra entrega, transferencia en el día o cuenta corriente a N días), pedido mínimo y cuentas (CBU, alias, banco, titular, código de pago electrónico).
    - **Rubros que provee.**
- **Cocinero, gerente y chefs:** ven la ficha de cada proveedor (contacto, días, horario y canal), pero **no ven** la condición de pago ni las cuentas bancarias. Eso lo decide la base de datos, no la pantalla.
- **Controller:** ve el pago y las cuentas, pero no los edita.
- **Dirección:** ve y edita todo.

## Qué controla el sistema

- **El CUIT:** se revisa el dígito verificador. Un CUIT con un número mal no se guarda.
- **Los datos tienen que corresponder:** un horario «desde» posterior a «hasta», un canal con un dato que no corresponde (un mail que no es un mail), una transferencia sin CBU ni alias o una cuenta corriente sin días no se guardan.
- **Si dos personas editan la misma ficha a la vez,** la segunda recibe un aviso para recargar.
- **Desactivar un proveedor no borra nada:** su ficha y su historia quedan, y se lo puede reactivar.

## Lo que todavía no está

- **Los 4 indicadores de arriba** (lista de precios vigente, saldo de cuenta corriente, OC abiertas y última compra) dicen «Sin datos» hasta las próximas entregas.
- **La carga de los proveedores reales** desde una planilla llega en el PR que sigue.

## Para probar en staging

1. Con el usuario de Compras: Proveedores → «+ Nuevo proveedor», crear uno de prueba y completar su ficha.
2. Marcar los días, el canal y la condición de pago, escribir el motivo y guardar.
3. Entrar con la cocinera y mirar que la ficha no muestre el pago.
