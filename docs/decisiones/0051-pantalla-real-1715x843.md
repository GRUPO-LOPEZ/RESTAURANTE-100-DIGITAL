# ADR-0051: Pantalla real de 1715 × 843

- **Fecha:** 2026-11-15
- **Estado:** plan aprobado por Joaco el 2026-11-15.
- **Pedido:** Soy, por correo, el 2026-11-15.
- **Sigue a:** ADR-0045 y ADR-0046 (pantallas sin scroll), ADR-0048 (Costos en una pantalla) y ADR-0050 (ficha de proveedor, en el PR #74, todavía sin fusionar).
- **Sin cambios en la base.**

## Contexto

Soy midió su computadora, con Chrome como lo usa siempre y sin tocar el zoom:

| Medida                         | Valor                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------ |
| Lugar útil en Chrome           | 1715 × 843 px                                                                  |
| Pantalla completa              | 1715 × 965 px (DPR 1,12; probablemente 1920 × 1080 con todo agrandado un 12 %) |
| Lo que ocupan Windows y Chrome | 122 px de alto                                                                 |

Las pantallas sin scroll se probaban en 1440 × 900, 1600 × 900 y 1920 × 1080. Ninguna bajaba de 900 de alto, así que en la computadora real podían sobrar unos 57 px.

## Medido antes del cambio (`main`, seed, 1715 × 843)

| Pantalla                  | Rol             | Resultado                                                    |
| ------------------------- | --------------- | ------------------------------------------------------------ |
| Lista y detalle de Costos | Controller      | Entran                                                       |
| Ficha de receta           | Chef y Director | Entra: la columna derecha y la planilla se desplazan adentro |
| Ficha de materia prima    | Compras (edita) | 874 px: se pasa por 31                                       |
| Inicio                    | Controller      | 857 px: se pasa por 14                                       |

## Decisión

- **Se prueba también en 1715 × 843,** sin sacar los tamaños de antes: Inicio, ficha de materia prima, ficha de receta, lista y detalle de Costos y, desde el Prompt 1 de Facturas, la ficha de proveedor. Se prueba con un rol que edita y con uno que solo lee.
- **Si algo no entra, la página queda quieta y lo que sobra se desplaza dentro de su tarjeta,** como la tabla de Costos:
  - la grilla de tarjetas lleva `min-h-0`, base `0px` y `grid-rows-[minmax(0,1fr)]`;
  - cada tarjeta lleva `relative min-h-0 overflow-y-auto` (la opción `scroll` de `Tile`);
  - mientras una tarjeta se desplaza, entra en el orden de Tab: con el teclado se llega y se recorre con las flechas, aunque abajo solo haya texto;
  - no se achica letra ni controles por debajo de los mínimos.
- **Si con eso no alcanza,** se avisa y se decide qué sale.
- **No se diseña para menos de 843 de alto** hasta tener la medición de la computadora de un local. Si da menos, la más chica pasa a ser el mínimo.
- **Dónde se aplicó:**
  - en la ficha de materia prima, sus tres columnas. Conversiones queda con su alto; Precios, Mermas y Alérgenos se reparten el resto;
  - en el Inicio, la fila de tarjetas (confiabilidad, locales y tareas);
  - la ficha de proveedor nace así (ADR-0050), cuando se fusione el PR #74.
- **Ficha de materia prima con Compras:** en 1715 × 843, «Observaciones» queda abajo en «Datos generales», a un desplazamiento de la tarjeta. Se acepta: no es un dato para decidir y el resto de la tarjeta se ve.
- Queda escrito en `.claude/rules/design.md`, «Pantallas de carga sin scroll».

## Consecuencias

- **La página nunca se mueve en la computadora,** aunque la pantalla sea más baja o los datos sean más.
- **Una tarjeta que se desplaza puede esconder parte de su contenido.** Por eso se sigue midiendo el alto natural con datos reales, y si lo importante queda escondido se propone qué sacar. Las pruebas, además de mirar que la página no tenga scroll, controlan en 1715 × 843 que «Ver los N», «Ver cuáles», los alérgenos y «Ver los números» queden a la vista, y corren axe en ese tamaño.
- **Las capturas no muestran las barras de desplazamiento.** En el Chrome de Soy, con Windows, una tarjeta que se desplaza muestra una barra fina a la derecha.
