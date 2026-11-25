# ADR-0065 — Hacer varias recetas sin densidad y cuatro fichas técnicas

- **Fecha:** 2026-11-25
- **Estado:** plan aprobado por Joaco (2026-11-24).
- **Pedido:** Tanda 2 de Soy, punto C (`docs/prompts/2026-11-22-correcciones-modulo-1.md`, bocetos `Escalar`, `FichaTecnica` y `FichaCelular`). Sigue al ADR-0064; cambia la pantalla del ADR-0032 y reemplaza a la vista de cocina.

## Por qué pedía densidad

La base ya multiplicaba cada línea en su unidad (`recipes.scale_version`). La planilla de la ficha no: multiplicaba los **gramos** de la línea, y sin densidad no hay gramos. De paso, multiplicaba las líneas «no escalar», que la base no multiplica.

## Decisión

1. **Una sola regla de unidades** (`lib/scaling-units.ts`): cómo se lee cada cantidad en la planilla, en «Hacer varias recetas» y en las fichas.
   - Cada línea sigue en su unidad. g → kg, ml y cc → l, mg → g al llegar a 1.000; nunca al revés. Las demás unidades no cambian.
   - Cucharadas, cucharaditas y tazas dicen al lado cuánto son, desde 4, 6 y 2. En ml; en gramos solo la pizca, que es de peso.
   - Las medidas prácticas, con el nombre y el contenido **congelados** en la versión. De la misma clase se cuentan de nuevo (no se arrastra el redondeo); lo corregido a mano o con peso por unidad se multiplica. Esa cuenta está solo en la base.
   - «No se multiplica» queda igual, en las cantidades y en el costo.
2. **`recipes.scale_version` suma el modo `recipes`**, que no pide porciones ni rendimiento. El total de «Hacer» en la planilla es lo que rinde, no la suma en gramos.
3. **Cuatro fichas en `/recetas/[id]/fichas?ver=`**, de la versión vigente y sin importes. `/recetas/[id]/cocina` redirige (temporal, en `next.config.ts`: con Cache Components una página que solo redirige no se puede prearmar).
   - Se acomodan por el ancho, no por el aparato: desde 1.280 px, en columnas y sin scroll de página; por debajo, una columna; por debajo de 800, además, letra de 20 px y 44 px. Con un corte único en 800, una tablet o el zoom dejaban columnas de menos de 100 px. En el papel sale todo: una hoja A4 mide menos de 800 px, así que lo que hace falta va también con `print:`.
   - El nombre y la versión se repiten en todas las hojas impresas, también en «Hacer varias recetas» (pedido de Joaco, 2026-11-25; `components/recipe-cards/paper-pages.tsx`).
   - La foto de la receta es el producto final; si no hay, el emplatado; si no, la primera.
4. **«aprobó {nombre y apellido}» lo ve todo el que ve la ficha** (decisión de Joaco). La base manda solo el nombre: ni el id ni el correo. Si no lo hay (sin aprobador o cuenta sin nombre), se dice «sin el nombre de quien aprobó». El nombre es el de hoy: si la persona lo corrige, cambia en la ficha.
5. **En la ficha de Servicio va grande la medida que da entera; si no da («0,42 taza»), el gramaje, con la medida abajo** (decisión de Joaco, 2026-11-25).
6. **Punto crítico por paso** (decisión de Joaco). La columna existía; la ficha no la mandaba y guardar los pasos la borraba.

## Opciones descartadas

- **Pasar las cucharadas a gramos** (como el boceto): haría falta la densidad.
- **Detectar el celular:** Soy pidió el ancho; sirve igual en una tablet o en una ventana angosta.
- **Guardar las cantidades multiplicadas:** no son un dato oficial.

## Pendiente, anotado

- Una cantidad `NaN` se puede guardar por la API con el permiso de editar recetas (`NaN > 0` es verdadero). Ya estaba; va en una migración aparte.
- La medida multiplicada no tiene tope (solo se muestra).
- Guardar los pasos no conserva «workers» ni «sector» del paso, que la ficha no carga (ya estaba; hoy no hay ninguno).
- La ficha nombra siempre la preparación de una línea; «Hacer varias recetas» dice «Preparación» si la sesión no la ve (ya estaba; hoy, 0 casos).
- La Cocinera puede leer por la API el identificador de quien aprobó («approved_by», ya estaba) y ahora su nombre.
