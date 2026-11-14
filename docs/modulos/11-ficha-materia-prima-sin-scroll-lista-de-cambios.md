# Ficha de materia prima sin scroll: lista de cambios

Para Soy. Fecha: 2026-11-14. Detalle técnico en el ADR-0046. Capturas en `docs/capturas/ficha-materia-prima-sin-scroll/`.

## Qué cambia en la computadora

1. **La ficha entra entera en la pantalla, sin bajar.** Probado en 1440 × 900, 1600 × 900 y 1920 × 1080.
2. **Arriba, una sola línea:** «← Materias primas», el nombre, el código, el rubro, en qué se usa y si está activa. **«Desactivar» es un botón a la derecha**, ya no un desplegable.
3. **4 números grandes:** precio vigente, costo neto por kg, rinde neto y en cuántas recetas se usa.
   - Quien no ve precios ve, en lugar del precio, cuántos productos de compra tiene.
   - Quien no ve costos ve, en lugar del costo, cuántos alérgenos tienen dato (en rojo si falta más de la mitad).
   - Cada uno ve solo la plata que le corresponde: el Chef ve el costo pero no el precio.
4. **Tres columnas, y se edita donde se ve:**
   - **Datos generales.** «¿Se compra congelada?» se cambia con un clic.
   - **Precios de compra.** Ahora es una sola tarjeta, antes eran dos que decían lo mismo. Muestra hasta 3 productos, y «Ver los N productos» abre todo: editar, los que ya no se compran, el costo con y sin IVA, y el historial de precios. Debajo, **Mermas y rendimientos**.
   - **Conversiones y alérgenos.**
5. **Alérgenos: un botón por alérgeno que cambia con cada clic.** Pasa por Sin dato → No contiene → Puede contener → Contiene, y cada estado tiene su color y su palabra. Si cambiás varios, elegís una sola vez de dónde sale el dato («Origen de estos cambios»).
6. **«Dónde se usa»** pasó al número «Recetas que la usan». Su botón «Ver cuáles» muestra la lista. Es la decisión de Joaco del 2026-11-13: con los 14 alérgenos, la tarjeta no entraba.
7. **La barra de abajo es la misma de siempre:** cuántos cambios hay, el motivo, Descartar y Guardar cambios.

## Lo que no cambia

- **«Proponer precio» se puede hacer también desde el celular**, como hasta ahora.
- En el celular, la ficha es para consultar y se baja con el dedo.
- Los permisos, las aprobaciones y los datos son los mismos.

## Para mirar

- **Probado con 8 alérgenos (los datos de prueba); falta mirarla con los 14 de verdad.** Con 14 entra por la cuenta, pero hay que verla en staging.
- **Una pregunta que ya venía de antes:** Compras ve precios, pero en la ficha no ve el precio del local que elige arriba (solo lo ve quien también ve costos). ¿Tiene que verlo? Lo confirmamos con Joaco.
- **Desde ahora, las pantallas de carga nuevas siguen este mismo diseño.** Quedó escrito en las reglas de diseño.
