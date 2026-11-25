# Proponer precio (lista de cambios para Soy)

Última entrega de la **Tanda 2**. Detalle técnico en ADR-0067. Capturas en `docs/capturas/proponer-precio/`.

## Proponer un precio

- **Cinco datos:** producto, precio del envase, si incluye IVA, para quién vale y motivo. La fecha es hoy y se cambia con un clic.
- **Se ve cómo queda antes de proponerlo:** «Queda $ 1.176 por kg sin IVA: sube 4 % contra el precio de hoy. Lo aprueba el Controller». Si cambia mucho, avisa que también lo aprueba Dirección General.
- **«26.000» ahora son veintiséis mil.** Antes el sistema lo leía como $ 26.
- **El resto, en «Más datos»:** descuento, comprobante, alícuota, proveedor, origen y observaciones. Sin abrirlo se lee lo que va a viajar.
- La alícuota es la del último precio aprobado de ese producto y el proveedor, el suyo.

## Lo demás de la ficha

- **Producto de compra:** el código se arma solo.
- **Mermas, rendimientos y ensayos:** menos campos a la vista; lo opcional va en «Más datos».

## Qué no cambia

- Quién aprueba y cuándo pasa a Dirección.
- Los precios y los códigos que ya están cargados.

## Distinto del boceto

- El precio dice «Precio por bolsa» (o el envase que sea) en vez de «Precio de la bolsa».
