# ADR-0041: Códigos automáticos y listados por rubro

- **Fecha:** 2026-11-12
- **Estado:** aceptada por Joaco (plan aprobado el 2026-11-12).
- **Pedido:** Soy, «Fichas únicas de recetas y materias primas», Prompt 1 (`docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md`).

## Contexto

Hasta ahora el código de cada receta y de cada materia prima se escribía a mano al darla de alta (`REC-0001`, `ING-0051`). Soy quiere que el código diga qué es y dónde está, y que lo arme el sistema:

- `PLA-CAF-0001` para un plato del rubro PL-CAF;
- `PRE-SAL-0001` para una preparación del rubro SR-SAL;
- `MPR-CAR-0001` para una materia prima del rubro MP-CAR.

También pidió:

- solo dos tipos de receta: Plato y Preparación;
- listados ordenados por rubro: arriba las tarjetas de los rubros, como en `/rubros`, y abajo la tabla, que se filtra con un clic en una tarjeta.

Este es el primero de tres PR. El 2 y el 3 (las fichas únicas) usan estos códigos y estos listados.

## Decisiones de Joaco (2026-11-12)

1. **Al llegar a 9999 se pasa a 5 dígitos** (`PLA-CAF-10000`), sin frenar a nadie. Entra en el límite de 30 caracteres.
2. **Variantes por local:** el código de la maestra con `-V01`, `-V02`… (`PLA-PAS-0001-V01`), correlativo por maestra. Se ve de qué receta es variante y no gasta números del rubro.
3. **La importación del recetario queda como está.** Las recetas importadas conservan el prefijo de la marca y el código del Excel (`NON-190000`), que une las sub-recetas dentro del archivo y se puede rastrear contra la planilla. Solo las altas manuales usan el formato nuevo.
4. **«Se usa en recetas en» muestra la lista completa de unidades**, con nombre largo, pero la base guarda la unidad base de esa medida: kg → g, l → ml, docena → unidad. El motor de costos calcula todo sobre la unidad base (sección 8, ADR-0029) y no cambia. La pantalla avisa «Las recetas la calculan en gramos (g)». Los envases no se ofrecen, porque no tienen base.

## Decidido en el plan

- **El rubro pasa a ser obligatorio para crear una receta**, porque sin rubro no hay código. Lo cargado sin rubro no se toca: en la tabla se ve «—» y no entra en ninguna tarjeta.
- **«Componente por unidad»:**
  - El motor de costos no usa `recipe_type` en ningún cálculo, así que alcanza con la interfaz: lo que ya existe se muestra como «Preparación» y queda en la pestaña Preparaciones.
  - La base además rechaza crear recetas nuevas de ese tipo. El valor sigue en el enum, porque lo cargado no se borra.
  - No se cambió ningún dato: la prueba 270 sigue controlando que las 198 líneas del seed cuesten lo mismo.

## Cómo quedó

### Base (`20261127120000_auto_codes.sql`)

- **`catalog.code_series`:** el último número entregado por grupo y prefijo (`PLA-CAF-`, `MPR-CAR-`, `PLA-PAS-0001-V`).
  - Tiene RLS activado y ninguna política, y no se le da ningún permiso a nadie: solo la usan las funciones de alta, que son `security definer`.
  - Lleva columnas de control, auditoría y rechazo de truncate, como toda tabla.
- **`catalog.next_code`:**
  - Entrega el siguiente número con un `update` que bloquea la fila del contador. Dos altas simultáneas esperan una a la otra y nunca reciben el mismo número.
  - La primera vez arranca desde el mayor número que ya exista con ese prefijo, borrados incluidos.
  - Saltea un código ya tomado, por ejemplo uno escrito a mano con el mismo formato.
  - El contador nunca baja, así que un número de un registro borrado no se reutiliza. Si el alta falla, la transacción se deshace y el número no se pierde.
- **`recipes.preview_code` y `catalog.preview_ingredient_code`:**
  - Muestran el código que saldría, con `catalog.peek_code`, sin consumir el número.
  - Piden `recipes.draft` en algún alcance del grupo, o `catalog.manage` en el grupo. Sin permiso devuelven vacío.
- **Altas:**
  - `recipes.create_recipe`, `catalog.create_ingredient` y `recipes.create_variant` ya no reciben el código. Se borraron las firmas viejas, para que no quede un camino para elegirlo a mano.
  - Reciben `p_expected_code`, el código de la vista previa. Si salió otro, la respuesta lo marca (`code_changed`) y lo explica.
  - Los permisos son los mismos de antes: generar el código no abre nada nuevo.
- **El código no cambia nunca:**
  - En las recetas ya lo controlaba `recipes.enforce_recipe_rules` (ADR-0025).
  - Para las materias primas se sumó el trigger `catalog.guard_code`.
- **No se tocaron** el seed, los códigos existentes ni `imports.*`.

### Pantallas

- **Alta de receta** (modal y `/recetas/nueva`), en el orden de Soy:
  1. Alcance.
  2. Tipo, con dos botones a la vista: Plato | Preparación.
  3. Rubro, solo los de la clase del tipo.
  4. Código, en solo lectura, con un tooltip.
  5. Nombre.
  6. Motivo.
  7. Crear receta.
- **Alta de materia prima:**
  1. Rubro.
  2. Código.
  3. Nombre.
  4. «Se usa en recetas en», con la lista completa agrupada en Peso, Volumen y Unidades, y la nota de la unidad base.
  5. Motivo.
- **Variantes:** el alta ya no pide código y explica que lleva el de la maestra con `-V01`.
- **Aviso en la ficha cuando el código cambió:** la acción redirige con `?aviso=codigo&previsto=…`. La ficha arma el texto comparando el código previsto (validado) con el suyo, así que la dirección nunca lleva texto libre.
- **`/recetas`:**
  - botones Platos | Preparaciones, con su cantidad;
  - buscador por nombre o código;
  - se mantiene el filtro de Alcance;
  - tarjetas de rubros de la clase elegida (`components/rubro-filter.tsx`, con el mismo diseño de `/rubros`): un clic filtra, otro clic o la ✕ quitan el filtro. Una tarjeta en 0 dice «Sin recetas», nunca 0 %;
  - tabla con Código, Receta, Rubro, Alcance, Estado y Costo sin IVA, con las mismas pestañas de estado, orden y paginación;
  - se quitaron los desplegables de Tipo y de Categoría, porque los reemplazan los botones y las tarjetas.
- **`/materias-primas`:** el mismo patrón con los rubros de compra, con las pestañas Activas y Desactivadas.
- **Filtro por rubro:** un rubro filtra junto con sus subcategorías (`withSubcategories`).

## Opciones descartadas

- **Una secuencia de Postgres por prefijo:** no se puede «mirar sin consumir» de forma segura para la vista previa, y habría que crear una secuencia por rubro nuevo. La tabla de contadores resuelve las dos cosas.
- **Calcular `max(código) + 1` en cada alta:** con dos altas simultáneas puede repetir, y reutiliza el número de un registro borrado.
- **Guardar kg como unidad de uso:** obligaba a cambiar el motor de costos, los precios y las conversiones. Es un cambio grande y de riesgo, mejor en su propio PR si alguna vez hace falta.

## Pruebas

- **pgTAP:**
  - nueva `280_auto_codes`, con 44 pruebas: formato; correlativo por tipo y rubro; subcategoría; número borrado; código tomado a mano; 9999 → 10000; vista previa sin consumir; aviso; variantes; kg → g; código inmutable; RLS por rol;
  - ajustadas `050`, `140`, `160`, `170`, `190`, `238` y `250`, sin debilitarlas. Donde controlaban un código repetido, ahora controlan que la firma vieja no existe y que la base sigue rechazando un repetido.
- **Vitest:** nueva `codes.test.ts` y ajustada `catalog-schemas.test.ts`.
- **Playwright:**
  - nueva `codigos.spec.ts`, en celular y computadora (1440, 1600 y 1920), con axe: alta de plato, de preparación y de materia prima; filtro por rubro; dos altas simultáneas;
  - ajustadas `recetas`, `materias-primas`, `subrecetas`, `escalado` y `rubros`.

## Después de las revisiones (2026-11-12)

- **Base (sin graves):**
  - se sumaron pruebas de auditoría del contador, de RLS para anónimo y para una persona sin membresía, de los mensajes en español de un código repetido y de la regla de la unidad de recetas en la base;
  - `next_code` recorre lo cargado solo la primera vez de cada prefijo.
- **Seguridad (apto, 3 menores):**
  - el aviso de «salió otro código» se muestra solo si el registro se creó hace menos de 10 minutos, así que un enlace armado a mano no sirve para mostrar un aviso falso;
  - `code_highest` toma en cuenta solo números de hasta 5 dígitos, para que un código importado raro (`PLA-CAF-999999999`) no haga saltar la numeración. Si choca con uno, `next_code` lo saltea.
- **Interfaz (sin graves):**
  - en el celular, el código ya no aparece dos veces;
  - los botones Platos | Preparaciones cuentan con la misma búsqueda y el mismo alcance que la tabla, y si la tabla queda vacía y en la otra pestaña hay resultados, el vacío ofrece «Ver N en Preparaciones»;
  - el código se anuncia al lector de pantalla;
  - el tooltip del código dice de qué sale en cada caso.

## Lo que queda

- **La importación no avisa si una receta queda sin rubro.** Esas recetas conservan su código y no tienen tarjeta hasta que alguien les asigne un rubro.
- **Las tarjetas cuentan todo lo del rubro que la persona ve en el grupo,** igual que `/rubros`: no dependen del buscador, del alcance ni de la pestaña de estado. Al tocar una, la tabla puede mostrar menos.
- **La numeración es del grupo.** Un chef de una sola marca ve en la vista previa un número que deja intuir cuántas recetas del rubro hay en todo el grupo. No ve nombres ni costos. Se acepta por el pedido (un correlativo por grupo); si molesta, habría que numerar por marca.
- **Distintos nombres para lo mismo:** las tarjetas de `/rubros` dicen «insumos» y las de Materias primas dicen «materias primas». Falta unificar el término con Soy.
- **La importación sigue pudiendo usar un prefijo de marca `PLA`, `PRE` o `MPR`.** No rompe la numeración (ver arriba), pero se puede reservar con una migración aparte.
