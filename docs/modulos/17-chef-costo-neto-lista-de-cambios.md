# La Chef ve el costo neto (lista de cambios para Soy)

Arreglo chico en la ficha de materia prima. Detalle técnico en ADR-0054.

## Qué cambia

- **Chef:** en la ficha de materia prima, con un local elegido arriba, el indicador **«Costo neto por kg»** ahora muestra el número: el costo con la merma de limpieza y el descongelado.
  - Antes aparecía vacío y decía «No ves los costos de este local», aunque la Chef sí ve costos.
  - Si falta un dato, dice cuál: por ejemplo, «Falta el rendimiento» si la materia prima todavía no tiene la merma aprobada.
- **La Chef sigue sin ver precios:** ni el precio vigente, ni los productos, ni los proveedores, ni el historial de precios. Eso sigue siendo de Compras, Controller y Dirección.
- **Para los demás no cambia nada.** Compras sigue viendo el precio del local que elige arriba, sin ver costos.

## Qué controla el sistema

- **La base decide quién ve el costo neto:** quien puede ver costos de recetas en ese local. La pantalla solo lo muestra.
- **Nunca muestra $ 0 cuando falta un dato:** dice qué falta.
