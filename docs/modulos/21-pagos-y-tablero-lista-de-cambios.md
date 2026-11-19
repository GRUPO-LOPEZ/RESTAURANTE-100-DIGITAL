# Pagos, cuenta corriente y Tablero de compras (lista de cambios para Soy)

Sexta y última entrega del módulo de compras (Fase 3). Cierra el circuito **pedido → recepción → factura → pago**. Detalle técnico en ADR-0060. Capturas en `docs/capturas/pagos-y-tablero/`.

## Qué cambia

- **«Pagos»**, en el grupo Compras del menú: qué hay que pagar y a quién le debemos.
  - Pestañas: **Por vencer**, **Vencidas**, **Pagadas** y **Para confirmar** (el efectivo que se pagó al recibir).
  - Lo ven Dirección, el director de marca, el gerente (solo su local), el Controller, Compras y el Auditor. El cocinero y el chef no.
- **«Registrar pago»** (solo Compras): se elige el proveedor y aparecen sus facturas con saldo. Se escribe el importe y **se reparte solo**, empezando por la que vence antes; cada una se puede corregir.
  - El medio de pago sale de las cuentas de la ficha del proveedor (efectivo, transferencia, cheque…). Se suman la fecha, la referencia, el comprobante (foto o PDF) y el motivo.
  - **Lo que no se aplica a facturas queda a cuenta** del proveedor y se puede aplicar después.
  - Una factura que queda en cero pasa a **«Pagada»** sola.
  - El aviso al proveedor queda en cola por el canal de su ficha. Todavía nadie lo manda (tu decisión 9).
- **El efectivo que se paga al recibir** (tu decisión 7) aparece en «Para confirmar». Compras lo confirma (corrigiendo el importe si hace falta) y queda a cuenta. Cuando la factura de esa recepción queda conforme, **se le aplica solo**.
- **Un pago es de un local.** Una transferencia que paga dos locales se carga como dos pagos con la misma referencia.
- **Anular un pago** (con motivo): la factura vuelve a tener saldo y la historia queda.
- **Una nota de crédito que llega cuando la factura ya está pagada:** lo pagado de más vuelve a cuenta del proveedor.
- **Avisos de vencimiento:** Compras recibe un aviso 7 días antes y el día que vence. Una sola vez por factura.

## La cuenta corriente del proveedor

- En la ficha del proveedor ya no dicen «Sin datos» tres indicadores:
  - **Saldo de cuenta corriente**, con su estado en palabras:
    - «Con vencidas»;
    - «Al día»;
    - «A favor»;
    - «No coincide», si el saldo que informó el proveedor en su última factura es distinto del nuestro.
  - **Órdenes de compra abiertas**, con «Ver cuáles».
  - **Última compra**: la fecha de la última factura conforme.
- **«Ver la cuenta corriente»** abre los movimientos (facturas, notas y pagos) con el saldo acumulado, y el saldo que dice el proveedor al lado del nuestro.
- **En la ficha de cada factura**, en «Todo junto»: el saldo («Pagada», «Pagada en parte», «Sin pagos» o «Vencida») y los pagos que la cancelan.

## El Tablero de compras

- Es lo primero del grupo Compras. Entra en una pantalla, sin moverse, como el Inicio. Para quien lo usa a diario: Compras, Dirección, el Controller y el director de marca.
  - **Arriba:** «Requiere atención» con lo más urgente y 4 indicadores:
    - facturas observadas;
    - facturas que vencen esta semana, con el importe;
    - órdenes de compra abiertas;
    - listas de precios vencidas.
  - **Gasto por rubro del mes:** los 5 rubros que más gastaron, el resto junto, y aparte fletes y percepciones. Se distingue lo que va a recetas de lo que no.
  - **Cómo subieron los insumos:** cuánto subió en % el costo de las 4 materias primas que más se compran, en los últimos 90 días. En % porque en pesos los insumos caros taparían a los baratos.
  - **Alarmas** de la más urgente a la menos, y abajo los **pagos próximos** y los **artículos sin mapear**.
- **El chef ve el tablero sin importes** (tu decisión: los montos, solo quien ve pagos).
- **En el celular:** la franja, los indicadores y las alarmas, sin gráficos.

## Qué controla el sistema

- **Nunca se paga de más:** ni más que el saldo de una factura ni más que el pago, aunque dos personas paguen a la vez.
- **El saldo se calcula siempre de las facturas, las notas y los pagos.** No es un número que alguien escribe.
- **Un pago registrado no se cambia:** se anula, con motivo, y se carga de nuevo.
- Todo queda en el historial, con quién, cuándo y el motivo.

## Lo que queda afuera por ahora

- **Retenciones** (tu respuesta P8): el pago tiene el lugar preparado, pero no se cargan.
- **El envío del comprobante al proveedor:** queda en cola hasta que se defina quién lo manda.

## Para probar en staging (antes de cargar proveedores reales)

Con los datos de prueba: Joaco los carga con la opción «Cargar compras, facturas y pagos de prueba» de Publicar en staging. Lo que se carga, el recorrido y los importes exactos están en la guía `docs/guias/prueba-fase-3-soy.md`.

1. Pagar en dos partes una factura conforme (la del Frigorífico que vence en 5 días). Ver que pase a «Pagada» y que el saldo del proveedor baje.
2. Confirmar en «Para confirmar» el efectivo que se pagó al recibir la verdura, y dar por conforme su factura: el efectivo se le aplica solo.
3. Mirar el Tablero de compras como Compras (con importes) y como chef (sin importes).
