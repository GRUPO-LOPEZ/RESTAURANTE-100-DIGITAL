# ADR-0054: La Chef ve el costo neto de la materia prima

- **Fecha:** 2026-11-17
- **Estado:** plan aprobado por Joaco el 2026-11-17 («sí, que la Chef vea el costo neto, en otro PR», 2026-11-16).
- **Origen:** hallazgo menor de `security-auditor` en el PR #80 (Compras ve el precio del local elegido).
- **Sigue a:** ADR-0040 (mermas y rendimientos), ADR-0043 (ficha única de materia prima) y ADR-0046 (ficha sin scroll).
- **Migración:** `20261206120000_ingredient_net_cost.sql`.

## Problema

La ficha de materia prima muestra el indicador «Costo neto» a quien tiene `recipes.view_costs`. El número lo calculaba `costing.ingredient_line_cost`, que pide `prices.view`. La Chef (`executive_chef`) tiene lo primero y no lo segundo: veía el indicador vacío, con el mensaje equivocado «No ves los costos de este local».

## Opciones

1. **Darle `prices.view` a la Chef.** Vería también la lista de precios: productos, proveedores, precio por envase e historial. Es más de lo que necesita.
2. **Que `ingredient_line_cost` acepte `prices.view` o `recipes.view_costs`.** Devuelve el registro de precio y el nivel. Una función con dos permisos es más difícil de auditar.
3. **Una función nueva para la ficha, con `recipes.view_costs`, que devuelva solo lo que la ficha muestra.** El cálculo queda en una sola interna. (Elegida.)

## Decisión

- **`costing.ingredient_line_cost_internal`:** el cálculo de siempre (unidad de uso, rendimiento con descongelado y precio que vale). No controla permisos y nadie la puede llamar directo.
- **`costing.ingredient_line_cost`:** pasa a ser un envoltorio, con la misma firma, el mismo resultado y el mismo permiso (`prices.view`).
- **`costing.ingredient_net_cost`:** la nueva, que pide `recipes.view_costs` en el local y que la materia prima sea del grupo del local.
  - **Devuelve:** el costo de la cantidad como se compra y limpia, sus estados y, del precio que vale, solo si está vencido, si es heredado y desde cuándo.
  - **No devuelve:** el producto, el proveedor ni el registro de precio.
  - **Sin proceso de limpieza, sin merma aprobada o sin precio:** vacío con su motivo, nunca $ 0 ni el bruto como si fuera el neto.
- **La pantalla:** `getIngredientNetCost` (`lib/costs.ts`) hace una sola llamada a la función nueva.

## Por qué está bien que la Chef lo vea

- **Ya ve ese dato en las recetas:** el costo por kg de cada ingrediente en la ficha de receta (`preview_sheet_lines`) y los costos de receta (`recipes.view_costs`). El costo neto por kg es el mismo dato con la merma aplicada.
- **Lo necesita para su tarea:** es quien propone las mermas. La vista previa de mermas le muestra cuánto cambia el costo.
- **Sigue sin ver la lista de precios:** «Precio vigente», la tabla de productos y los precios aprobados piden `prices.view`.

## Límites conocidos

- **El costo bruto por kg es casi el precio por kg** del producto que vale. Se acepta por lo dicho arriba.
- **El rechazo no queda en los eventos de seguridad,** igual que en `ingredient_line_cost` y las pantallas de costos: `org.require` corta con 42501.
- **En el seed ninguna materia prima tiene la limpieza aprobada:** en la pantalla, el neto dice «Falta el rendimiento» para todos. El monto con una merma aprobada lo controla la prueba `360_ingredient_net_cost`.

## Pruebas

- **pgTAP `360_ingredient_net_cost`, 20 controles:**
  - la Chef recibe el mismo neto y el mismo bruto que el motor le da a Dirección;
  - sin merma, sin proceso o sin precio, queda vacío con su motivo;
  - se rechaza a la Chef en otra marca, a Compras y a la Cocinera, la materia prima de otro grupo y la borrada;
  - devuelve solo esas columnas, y la fecha del precio se ve aunque falte la conversión;
  - nadie llama a la interna directo;
  - y la Chef sigue sin poder usar `ingredient_line_cost`.
- **Playwright (`ficha-materia-prima.spec.ts`):** la Chef, con un local elegido, ve «Costo neto por kg», el local y el motivo real. No ve «Precio vigente» ni montos en «Cómo se compra». Sin scroll en 1440 × 900 y 1715 × 843, con axe.
