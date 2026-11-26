# ADR-0067 — «Proponer precio» con cinco datos y código automático del producto

- **Fecha:** 2026-11-25
- **Estado:** plan aprobado por Joaco (2026-11-25).
- **Pedido:** Tanda 2 de Soy, decisión 7 y punto D (`docs/prompts/2026-11-22-correcciones-modulo-1.md`, boceto `FichaMP`). Segunda parte del PR D (la primera, ADR-0066). Cambia las pantallas de los ADR-0029, 0040 y 0044.

## Decisión

1. **Cinco datos a la vista** (producto, precio del envase, si incluye IVA, para quién vale y motivo) y «Desde hoy · Cambiar». Hasta 5 opciones, botones; más, un desplegable (`components/choice-field.tsx`).
2. **El resultado antes de proponer:** por unidad de uso sin IVA, cuánto varía y quién lo aprueba. Lo calcula la base (`costing.preview_price`) con **la misma cuenta** de la propuesta: `costing.propose_price` se partió en controles (`check_price_proposal`, `check_price_dates`) e importes (`price_proposal_amounts`) que usan las dos. Lo que guarda la propuesta no cambió: las pruebas de antes no se tocaron. Lo que vale es lo que se calcula al proponer.
3. **La vista previa pide `prices.propose` y `prices.view`** en el lugar, porque muestra la variación contra el precio vigente. Es `stable`: no escribe nada, tampoco registra rechazos (se llama mientras se escribe).
4. **«Más datos»** (`components/more-data.tsx`), cerrado, con un resumen de lo que va a viajar. Un error de adentro lo abre. La alícuota sale del último precio aprobado del producto (si no hay, 21 %) y el proveedor, del producto; el origen arranca en «Carga manual» (decisiones de Joaco).
5. **Código del producto automático** (`catalog.next_product_code`), con el formato que ya usaba `purchasing.resolve_article` (código de la materia prima y `-P01`). Las altas del grupo van de a una: dos a la vez no eligen el mismo. De paso, se corrige que se trababa al llegar a 100.
6. **Mermas, rendimientos, ensayos y productos**, con el mismo criterio: lo opcional en «Más datos» y los sí/no con toggle. Los datos no cambian.
7. **Los importes se leen como se escriben acá:** «26.000» son veintiséis mil (antes, $ 26). Y un precio `NaN`, que pasaba los controles por la API, se rechaza en la función y en la tabla.
8. **Un toggle de formulario vuelve a su valor** cuando el formulario se limpia (`components/ui/toggle-field.tsx`): si no, el siguiente envío podía salir con el valor anterior. Muestra su ayuda y su error, y recibe el foco.

## Opciones descartadas

- **Calcular la variación en el navegador:** sería otra regla, que se puede separar de la real.
- **Mostrar el resultado recién al proponer** (como antes): quien carga no sabía si iba a Dirección.
- **Un contador nuevo para los códigos:** los que ya existen usan el formato de `resolve_article`.
- **No pisar la alícuota y el proveedor elegidos a mano al cambiar de producto:** son de cada producto; el resumen los muestra.

## Pendiente, anotado

- Con un solo grupo no aplica, pero los mensajes de una propuesta dejan saber si existe un producto de otro grupo (hay que adivinar su identificador; no da precios). Ya estaba.
- Las demás pantallas con importes (listas de precios, facturas) tienen su propia lectura: no se tocaron.
- «26,000» con coma son $ 26: acá la coma es decimal. El resultado a la vista es el que avisa.
- El asterisco de los obligatorios en todos los formularios (`FormInput` no lo dibuja): es de todo el sistema.
