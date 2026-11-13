# ADR-0043: Ficha única de materia prima

- **Fecha:** 2026-11-12
- **Estado:** aceptada por Joaco (plan aprobado el 2026-11-12).
- **Pedido:** Soy, «Fichas únicas de recetas y materias primas», Prompt 3 (`docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md`). Boceto: `docs/prompts/2026-11-12-boceto/FichaMateriaPrima.dc.html` (pantalla 5).
- **Reemplaza:** las 6 pestañas de la ficha de materia prima del ADR-0036.
- **Sigue a:** el ADR-0042 (ficha única de receta), con la misma forma.

## Contexto

La materia prima tenía 6 pestañas (`?seccion=`) y unos 12 formularios sueltos, cada uno con su motivo: datos, otros nombres, activar, producto, proveedor, conversión, alérgeno (de a uno), congelada, mermas, ensayo, estándar y precio. Para corregir tres datos había que escribir tres motivos.

Soy pidió la misma forma que la ficha de receta, con estas secciones:

1. encabezado;
2. datos generales;
3. precios de compra;
4. mermas y rendimientos;
5. conversiones;
6. alérgenos;
7. dónde se usa.

Además: arriba un índice, se edita donde se ve, y abajo una barra con contador, motivo, Descartar y Guardar cambios. **No cambia ninguna regla, permiso ni aprobación.**

## Decidido en el plan

### Qué va en el guardado en lote y qué no

- **En el lote (la barra de abajo):** son datos de la ficha que se cambian juntos.
  - datos generales: nombre, rubro, unidad de recetas, unidad de compra y observaciones;
  - otros nombres;
  - «¿Se compra congelada?»;
  - conversiones;
  - alérgenos.
- **Con su propio flujo, en un panel corto:** son altas o propuestas, cada una con su aprobación o su motivo.
  - agregar un producto de compra;
  - crear un proveedor;
  - proponer una merma o un rendimiento por proceso (un solo botón, y adentro se elige cuál);
  - registrar un ensayo;
  - proponer un precio.
- **Activar o desactivar** sigue aparte, con su motivo. No es un dato de la ficha, sino sacarla de uso.

### La base: `20261129120000_ingredient_sheet.sql`

- **`catalog.save_ingredient_sheet`:** guarda en una transacción con un solo motivo. Cada bloque es opcional.
  - Llama a las funciones de siempre: `update_ingredient`, `set_aliases`, `set_unit_conversion`, `set_allergen_status` y `set_requires_thawing`.
  - Por eso siguen valiendo todas las reglas:
    - el permiso `catalog.manage`;
    - con precios, la unidad de recetas no cambia y el rubro lo cambia quien tiene `prices.configure` (el trigger `guard_priced_ingredient`);
    - para cambiar la unidad, un producto comprado en otra medida necesita antes su densidad;
    - dejar de comprarla congelada queda pendiente hasta que lo apruebe un Chef de todo el grupo.
  - Si algo falla, no se guarda nada.
  - Quien no tiene `catalog.manage` recibe `denied` y el intento queda registrado.
  - Un rubro trabado por precios lo frena el trigger, que deshace todo el guardado. Ese rechazo no queda en los eventos de seguridad, igual que antes de la ficha. La pantalla no deja intentarlo: muestra el rubro deshabilitado.
  - `p_data` acepta solo los cinco datos de la ficha y no puede venir vacío. Cada conversión va una sola vez.
- **El sello de la ficha:** antes de guardar, la base controla que nadie la haya cambiado en el medio.
  - Un alérgeno o una conversión no tocan la fila de la materia prima. Por eso el sello es el último cambio de la materia prima, sus otros nombres, sus conversiones y sus alérgenos, incluidos los borrados.
- **La unidad de recetas** se guarda en la base de su tipo (kg → g), como al crearla (ADR-0041).
  - `update_ingredient` no lo hacía: las materias primas que ya tienen otra unidad no se tocan.
- **`catalog.ingredient_sheet_state`:** le dice a la pantalla el sello, si tiene precios y si el rubro está trabado para esa persona.
  - Así la pantalla deshabilita, con un tooltip que explica por qué, lo que la base va a rechazar. No hay una segunda regla en la pantalla: la decide la base.
  - **La regla del rubro está escrita una sola vez,** en `catalog.category_locked_by_prices`. La usan el trigger `guard_priced_ingredient` (se redefinió sin cambiar lo que hace) y el estado de la ficha, también con la excepción del rubro dado de baja (ADR-0038).
- **`costing.ingredient_product_prices`:** arma la tabla de productos con el precio que vale en el local elegido arriba.
  - Repite la elección, el costo y la regla de vencimiento de `costing.price_rows` sin tocar el motor de costos.
  - La prueba 300 controla que, para el producto que usa el costo, den lo mismo.
  - Sin `prices.view` en el local, no devuelve filas.
  - Un producto que ya no se compra aparece si tiene el precio que vale, marcado «Ya no se compra»: puede ser el que usa el costo (el último costo conocido).

### La pantalla

- La página (del servidor) pone las secciones en el orden del boceto.
- Los campos que se editan, el interruptor de congelada y la barra comparten un borrador en un contexto de cliente (`components/ingredient-sheet/sheet-editor.tsx`).
- **Datos generales:**
  - «Se usa en recetas en» muestra la lista completa de unidades y avisa «Las recetas la calculan en gramos (g)».
  - Los otros nombres se ven como etiquetas que se agregan y se quitan.
- **Precios de compra:**
  - el precio vigente y el costo neto con merma, destacados;
  - la tabla de productos: proveedor, en qué viene, contenido, precio, precio por kg, l o u, fecha y estado («Vigente», «Atención: N días», «Heredado», «Sin precio»);
  - sin `prices.view` la sección se llama «Cómo se compra» y no tiene columnas de dinero;
  - debajo siguen los precios aprobados, el historial y «Proponer precio» (`IngredientPrices`).
- **Mermas y rendimientos:**
  - los 4 indicadores del ADR-0040;
  - el interruptor de congelada;
  - la tabla «Rendimientos por proceso»;
  - «Proponer merma o rendimiento» y «Registrar un ensayo».
- **Conversiones:** se editan en la fila (valor, de dónde sale, fecha, quién lo midió). «Agregar…» abre la que falta.
- **Alérgenos:** un segmentado por alérgeno (Sin dato, Contiene, Puede contener, No contiene) y «De dónde sale».
- **Cambios marcados:** lo cambiado lleva el borde punteado, como en la matriz de permisos.
- **En el celular, de consulta:** los mismos datos en texto y tarjetas, sin barra ni paneles de alta.
- **Enlaces viejos:** `?seccion=` baja a su sección (los de Calidad y los de las pruebas siguen funcionando).

### Componentes nuevos o ampliados

- `components/ui/segmented.tsx`: botones a la vista fuera de un formulario. Comparte el estilo con `SegmentedField`.
- `ToggleField` acepta `value` y `onChange`, para usarlo dentro de una ficha que guarda todo junto.
- `components/action-modal.tsx`: un botón que abre un panel con un formulario, y devuelve el foco al cerrar.

## Lo que queda

- **Nadie tiene hoy `catalog.manage` y `prices.configure` a la vez,** ni el Superadministrador.
  - Por eso el rubro de una materia prima con precios solo cambia dando de baja su rubro (ADR-0038).
  - Es igual que antes de la ficha única. La prueba 300 controla la regla dándole a Compras los dos permisos dentro de la prueba.
  - Si Soy quiere que alguien pueda hacerlo, es un cambio de roles para decidir con Joaco.
- **«Proponer precio» sigue disponible en el celular,** como antes.
  - El resto de la carga es solo en la computadora.
  - Si se prefiere que el celular sea solo de consulta también acá, es un ajuste chico de pantalla y de `precios.spec`.
- **Editar un producto de compra** (descripción, proveedor, dejar de comprarlo) no tenía pantalla y sigue sin tenerla. La función `update_purchase_product` existe.
- **Las funciones sueltas de antes siguen habilitadas** (`set_aliases`, `set_unit_conversion`, `set_allergen_status`):
  - las usan otras pruebas pgTAP y la importación;
  - un cambio hecho por ese camino al mismo tiempo que un guardado de la ficha no pasa por el sello;
  - para dejar un solo camino de escritura, habría que revocarlas en una migración aparte.
- **El sello usa `updated_at`, que es la hora del comienzo de cada transacción.** Una transacción muy larga podría no moverlo. Es raro con el uso previsto.
- **«Dónde se usa» trae la lista completa,** como antes. Si un insumo común aparece en cientos de recetas, conviene paginarla.
- **El costo neto aparece dos veces,** en «Precios de compra» y en los indicadores de mermas, porque el pedido de Soy lo pone en las dos secciones.
- **Un dato mal formado mandado directo a la base** (sin pasar por la pantalla) puede dar un error de Postgres en inglés. La pantalla y el servidor lo validan antes, con Zod.

## Después de las revisiones (2026-11-12)

- **Seguridad: apto,** sin hallazgos graves ni medios. Se corrigieron los menores: la prueba de rechazos es exacta, un bloque de datos vacío se rechaza y el texto sobre el rechazo del rubro. Las funciones sueltas quedan anotadas en «Lo que queda».
- **Base: sin graves.** Se corrigieron los tres medios:
  - la regla del rubro en una sola función, con la excepción del rubro dado de baja;
  - los productos desactivados con precio;
  - la prueba del sello con cambios solo en alérgenos u otros nombres.

  De los menores se corrigieron las claves de `p_data`, las conversiones repetidas y el uso de `recipes.today()`. El resto está en «Lo que queda».

- **Diseño: aprobable con cambios,** sin graves. Se corrigieron:
  - los errores dicen en qué campo están, lo marcan (`aria-invalid`) y le llevan el foco;
  - la tarjeta de producto en el celular dice siempre su estado;
  - un otro nombre escrito y no agregado cuenta como cambio y se guarda;
  - «Desactivar» solo en la computadora;
  - el interruptor de congelada se bloquea con un pedido pendiente;
  - el motivo marcado como obligatorio;
  - los ids únicos por ficha;
  - el borde punteado ya no mueve la fila;
  - el texto repetido en cada alérgeno.

  «Dónde se usa» sin paginar y el costo neto repetido quedan anotados.

## Pruebas

- **pgTAP `300_ingredient_sheet` (49):**
  - un guardado con todos los bloques y un solo motivo en las cuatro tablas;
  - un sello viejo se rechaza;
  - un bloque inválido no guarda nada;
  - la unidad de recetas: kg pasa a g, un envase no se acepta, con precios no cambia y sin densidad no pasa a volumen;
  - el rubro con precios;
  - congelada aplicada y pendiente con su solicitud;
  - rechazos registrados, uno por persona: Jefe de Cocina, Cocinera y sin membresía; anónimo no puede llamarla;
  - un bloque de datos vacío no se acepta;
  - con el rubro dado de baja, la ficha no lo traba y la base lo acepta;
  - el sello se mueve con un cambio solo en un alérgeno o en otro nombre;
  - un producto desactivado con el precio del costo sigue en la tabla;
  - el estado de la ficha;
  - la tabla de productos igual al motor, sin `prices.view` y fuera del alcance.
- **`050`:** se suman las tres funciones.
- **Vitest `ingredient-sheet.test.ts`:** el diff, el contador, lo que viaja a la base, el esquema y el estado del precio.
- **Playwright `ficha-materia-prima.spec.ts`, en la computadora:**
  - datos con contador, Descartar, motivo obligatorio y aviso al salir;
  - kg guardado como g;
  - conversión y alérgeno en un guardado;
  - producto y merma;
  - con precios, unidad y rubro deshabilitados con su explicación;
  - capturas en 1440, 1600 y 1920.
- **Playwright `ficha-materia-prima.spec.ts`, en el celular:** consulta sin barra y sin desborde.
- **Ajustadas:** `materias-primas`, `mermas`, `rendimientos` y `precios`. Lo que se cargaba en el celular pasa a la computadora, y en el celular se controla la consulta.
