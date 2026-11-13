# ADR-0042: Ficha única de receta

- **Fecha:** 2026-11-12
- **Estado:** aceptada por Joaco (plan aprobado el 2026-11-12).
- **Pedido:** Soy, «Fichas únicas de recetas y materias primas», Prompt 2 (`docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md`). Boceto: `docs/prompts/2026-11-12-boceto/FichaReceta.dc.html`.
- **Reemplaza:** las 9 pestañas de la ficha de receta del ADR-0036.

## Contexto

La receta tenía 9 pestañas (`?seccion=`) y tres guardados separados, cada uno con su motivo:

- datos y rendimiento (`update_recipe` y `save_draft`);
- componentes (`set_components`);
- pasos (`set_steps`).

El editor de componentes no mostraba costos. Cargar una receta obligaba a saltar de pestaña en pestaña y a escribir tres motivos.

Soy pidió una sola ficha que ocupe toda el área, con la misma plantilla para platos y preparaciones, en este orden:

1. encabezado con fotos;
2. datos generales;
3. una grilla tipo planilla de ingredientes y costos;
4. rendimiento;
5. procedimiento;
6. alérgenos y dónde se usa;
7. versiones y aprobaciones.

Arriba va un índice que baja a cada sección y abajo una barra fija que guarda todo junto.

## Decisiones de Joaco (2026-11-12)

1. **«Precio por kg o por l» solo con `prices.view`** en el local elegido, como dice el ADR-0032. Con `recipes.view_costs` se ven el costo por renglón, las incidencias y los totales, pero no la columna de precio. Sin `view_costs` no aparece ninguna columna de dinero.
2. **Los platos ya cargados conservan sus porciones escritas a mano**, con la etiqueta «cargadas a mano». Cuando alguien carga el peso de la porción, las porciones pasan a calcularse solas. No se toca ningún dato.
3. **El costo de las filas que todavía no se guardaron lo ve solo quien puede editar o publicar la receta** (y ve costos en el local). El costo de una fila inventada equivale a un precio: así se da a quien ya podía obtenerlo guardando un borrador. Quien solo ve costos (por ejemplo, el Controller) los lee de lo guardado, en Costos. Lo marcaron las revisiones de seguridad y de base.
4. **En un plato, si algún ingrediente no se puede pasar a gramos, se guarda igual**: las porciones no se recalculan y la ficha lo avisa. Para enviarla a revisión, en cambio, las porciones tienen que poder calcularse.

## Decidido en el plan

### Un solo guardado en la base: `recipes.save_sheet`

- Datos de la receta, rendimiento y textos de la versión, líneas y pasos van **en una sola transacción, con un solo motivo**. Cada bloque es opcional: solo viaja lo que cambió.
- Por dentro llama a las funciones de siempre (`update_recipe`, `save_draft`, `set_components` y `set_steps`). Así las reglas de cada una (permisos, ciclos de preparaciones, unidades, auditoría) siguen en un solo lugar. Si alguna falla, no se guarda nada.
- El control de que nadie cambió el borrador mientras se editaba (`expected_updated_at`) se hace una sola vez, al principio.
- **Si lo que se ve es la versión vigente, el borrador nace en la misma transacción** (`new_version`). Se edita donde se ve, y la versión publicada nunca cambia.
- **«Enviar a revisión»** guarda y además pide la revisión en el mismo paso (`p_submit`, que pide `recipes.review`).
- Las funciones de antes quedan, porque las usan la importación y las pruebas. En la pantalla ya no hay otro camino para guardar una receta.

### La grilla no repite el motor de costos

- `costing.preview_sheet_lines` calcula las filas que se están escribiendo, todavía sin guardar, con el mismo motor que el costo oficial.
- Para eso `costing.recipe_line_costs_internal` acepta `p_memo.lines`. Sin ese dato, el resultado es exactamente el de antes: lo controlan las pruebas 238 y 270, y la 290 compara las dos cuentas.
- Solo entran filas completas, con materias primas y preparaciones del mismo grupo, y el perfil de merma solo si es de esa materia prima.
- **Cada uno ve lo suyo:**
  - quien trabaja la receta ve los pesos;
  - con `recipes.view_costs` en el local, también el costo;
  - con `prices.view`, también el costo por unidad base, que es el precio.
  - Lo demás llega vacío desde la base, no lo oculta la pantalla.
- **Sin suponer:** si falta un precio, una merma aprobada o una conversión (por ejemplo, ml a g sin densidad), la celda muestra «—» con el motivo en un tooltip y el total no se suma: dice que está incompleto. Nunca se muestra $ 0.
- En la pantalla (`lib/recipe-sheet.ts`, con Vitest) solo se pasa el precio a la unidad grande (g → kg, ml → l), se suma, se escala y se calculan las incidencias.
- `catalog.ingredient_unit_options` dice qué medidas admite cada materia prima (la suya y, con densidad o peso por unidad, las otras). Así «Medida» ofrece solo unidades que se pueden convertir.

### Rendimiento: un solo dato, sin duplicar

- **Plato.** Se carga «Peso de la porción», y la base calcula «Porciones que salen» = peso de las líneas en gramos ÷ peso de la porción.
  - Las porciones se guardan como rendimiento de la versión, en la unidad «porción», con sus decimales para no esconder sobrante.
  - `portions` guarda las porciones enteras que se venden.
  - Si alguna línea no se puede pasar a gramos, no se inventan porciones: se avisa.
- **Preparación** (lo que Soy llama «receta madre»):
  - «Peso bruto total» es la suma de las líneas en gramos.
  - «Peso neto total» es el rendimiento de siempre (`yield_quantity`), cargado a mano.
  - «Rendimiento» es neto ÷ bruto, la misma cuenta que la merma de cocción del ADR-0040 (`recipes.cooking_loss`). La reemplaza en la pantalla; no se agregan columnas de peso.
- **El rendimiento objetivo queda congelado en la versión.**
  - Al pedir la revisión de una preparación, un trigger guarda `recipe_versions.target_yield_ratio`.
  - Desde «approved» la versión no cambia (`core.enforce_version_rules`), así que el valor aprobado es el que va a leer el futuro control de lotes.
  - Es un dato derivado, guardado a propósito, igual que las cantidades que se congelan al publicar.
- Las mermas de limpieza y descongelado de cada materia prima siguen en su ficha (ADR-0040).

### Quien revisa no edita

- La base ya rechaza cualquier cambio a una versión en revisión, aunque quien lo intente tenga `recipes.publish`:
  - las funciones de escritura pasan por `open_draft`;
  - las tablas, por el trigger `enforce_draft_lines`.
- La 290 lo prueba con la sesión de quien revisa, también con `save_sheet`.
- En la pantalla, quien revisa ve la ficha en solo lectura, con las filas cambiadas marcadas («Nueva» o «Cambió», de `version_diff`). Tiene «Observaciones», «Aprobar» y «No aprobar», que usan `workflow.decide_approval`, la misma función de la bandeja de Aprobaciones. La base vuelve a controlar que no decida quien pidió la revisión.

### Pantalla

- **Una sola página:** índice de anclas (`#datos`, `#ingredientes`, `#rendimiento`, `#procedimiento`, `#alergenos`, `#uso` y `#versiones`; las fotos, `#fotos`).
- **Direcciones de antes:** `?seccion=` redirige a su ancla, y los enlaces de Calidad ya usan las anclas.
- **Grilla:**
  - arranca con 10 filas y agrega otra al completar la última;
  - autocompletado accesible (`combobox` y `listbox` «Sugerencias»: flechas, Enter y Escape), por código y por nombre;
  - la etiqueta «Preparación» es también el enlace a la ficha de esa preparación;
  - «Más opciones» de cada fila abre la base de la cantidad, las observaciones y «Quitar la fila».
- **«Hacer N recetas» es solo cálculo.** Los números (4 y 10 por defecto) se recuerdan en la dirección (`?hacer=4,10`) y no se guardan en la base.
- **Barra fija (ADR-0039):** «N cambios sin guardar», motivo obligatorio, Descartar, Guardar cambios y Enviar a revisión. Hay aviso de cambios sin guardar al salir. El campo cambiado lleva borde punteado.
- **Celular:** ficha de consulta, con datos, ingredientes en tarjetas, totales y pasos. No hay planilla ni barra. La revisión se pide desde «Versiones y aprobaciones».
- **Se mantienen** «Costos» en la barra lateral, la vista de cocina y Escalar (con un botón en el encabezado).

## Después de las revisiones (2026-11-12)

- **Base y seguridad:**
  - la grilla aplica las mismas reglas que el guardado: materias primas activas; preparaciones activas que la persona ve, que se pueden usar en esta receta y que no son ella misma; mermas aprobadas; locales activos;
  - `save_sheet` corta el lote si una función interna niega (`recipes.require_applied`);
  - el rendimiento objetivo fuera de rango queda vacío y no frena la revisión;
  - la conversión a gramos se calcula una vez por fila;
  - la pantalla lee los números con `parseAmount` («1.500» no se guarda como 1,5) y no acepta una porción de 0 g.
- **Diseño:**
  - la planilla entra en 1440 px;
  - las sugerencias se dibujan fijas debajo del campo (la tabla no las recorta), se cierran al salir del campo y anuncian «Buscando…» y «Sin resultados»;
  - el combobox del código también anuncia la opción activa;
  - en el celular el rendimiento se lee y no se edita;
  - cada «—» de las incidencias dice su motivo, y en el celular el costo que falta también;
  - un error del servidor al calcular se avisa aparte de un dato que falta;
  - sin local elegido, las métricas dicen «Elegí un local arriba»;
  - la barra llega a los bordes desde 1700 px y el motivo tiene etiqueta visible;
  - el error de una fila señala su número en la grilla;
  - sin códigos repetidos en el encabezado, y controles con radio de 8 px.

## Lo que queda

- La pantalla de Aprobaciones sigue igual. Desde la ficha se decide con la misma función.
- Antes de decidir, quien pidió la revisión ve «Aprobar»; si lo intenta, la base lo rechaza con su mensaje. Mostrarlo de entrada necesita saber quién la pidió, que hoy no está en la lectura de la versión.
- El costo de la grilla se calcula en el local elegido arriba. Sin local, solo se ven los pesos.
- La ficha de materia prima (Prompt 3) sigue con pestañas.
- Menores de las revisiones, para un PR chico aparte:
  - «La cantidad es» (3 opciones) como botones visibles en lugar de desplegable (ADR-0039);
  - el borde punteado en las filas de ingredientes cambiadas;
  - asociar cada celda de escala a su columna A o B para los lectores de pantalla;
  - menos paradas de Tab en las filas sin precio;
  - reutilizar el costo de una misma preparación entre filas (`p_memo.subs`), con `explain analyze` de 200 filas.
