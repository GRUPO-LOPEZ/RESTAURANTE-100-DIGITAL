# ADR-0038: Rubros del recetario (tabla maestra de compra, sub-recetas y menú)

- **Fecha:** 2026-11-10
- **Estado:** aceptada. Pedido de Soy (`instrucciones-rubros-claude-code.md`); Joaco aprobó el plan y las cuatro decisiones de abajo.
- **Migraciones:** `20261124120000_rubros.sql`.

## Contexto

Soy pidió ordenar el recetario en una tabla maestra de **rubros** con tres clases y códigos con prefijo:

- **MP:** rubros de compra (materias primas).
- **SR:** sub-recetas (salsas, masas, fondos).
- **PL:** rubros de menú (platos).

También pidió un panel para dar de alta, renombrar y dar de baja rubros, con conteos y porcentajes. Puso una condición: cambios **solo aditivos**, sin romper pantallas ni consultas.

Ya existían dos tablas de categorías con dos niveles, auditoría y RLS:

- `catalog.ingredient_categories`, con los días de precio vencido por categoría.
- `recipes.recipe_categories`.

El costeo en cascada ya existía: `recipes.recipe_components` vincula una materia prima o una sub-receta (ADR-0025 y ADR-0032).

## Decisiones de Joaco (2026-11-10)

1. **Se extienden las dos tablas y una vista las junta.** No hay tabla nueva ni llaves que cambien.
   - Columnas nuevas:
     - en las dos tablas: `code` e `is_active`;
     - en `recipe_categories`: `kind`, de tipo `recipes.category_class`.
   - Vista nueva: `recipes.top_categories`, con `security_invoker`.
   - Se descartó una tabla única `rubros`: obligaba a cambiar las llaves de materias primas y recetas, y eso toca precios, importación, reportes, costos y calidad.
2. **Tipo de receta y clase de rubro:**
   - `dish` va con un rubro de menú (PL);
   - `preparation` y `unit_component` van con uno de sub-recetas (SR).
3. **El rubro es el primer nivel.** Las subcategorías siguen dentro de su rubro: no llevan código, heredan la clase y no se ven en el panel.
4. **Colores con los tokens existentes,** sin los hex del documento de Soy:
   - `ok` y `bad` para el estado;
   - `chart-2`, `chart-4` y `chart-6` para la barra de cada pestaña.

   Los hex de Soy son casi iguales a los tokens, y las reglas de diseño prohíben colores propios por módulo.

## Cómo funciona

- **Código:**
  - Va en el primer nivel y en mayúsculas, con el formato `^(MP|SR|PL)-[A-Z0-9]{3}$` y el prefijo de su clase.
  - Es único por grupo y no cambia. No se reutiliza el código de un rubro borrado.
  - Si no se indica, lo arma la base: prefijo + 3 letras del nombre sin tildes (Tápas → PL-TAP). Si está tomado, prueba 2 letras y un dígito, y después 1 letra y dos dígitos.
- **Nombre:** no se repite entre los rubros de recetas del grupo, porque sub-recetas y menú comparten la lista. Por eso la migración no crea un rubro de Soy si una categoría vieja ya usa ese nombre en la otra clase.
- **Baja:**
  - Es `is_active = false` y se puede reactivar. `deleted_at` sigue siendo el borrado lógico de siempre.
  - Un rubro dado de baja no recibe materias primas, recetas ni subcategorías nuevas.
  - Para no cruzarse con una alta simultánea, los triggers leen el rubro y su madre con `for share`, y la baja bloquea el rubro y sus subcategorías.
  - Si tiene usos, también en sus subcategorías, la base **exige un destino** de la misma clase y activo. En la misma transacción pasa todo al destino y da de baja (`recipes.deactivate_top_category`).
  - Si tiene recetas cargadas antes en la clase equivocada, la baja lo dice y pide corregirlas primero.
  - **Materias primas con precios** (decisión de Joaco, 2026-11-10): al dar de baja el rubro, las pasa Compras o Dirección, cada uno por su cuenta.
    - Fuera de una baja sigue la regla de ADR-0029: cambiar la categoría de una materia prima con precios pide `prices.configure`, porque cambia cuándo un precio está desactualizado.
    - La migración reemplaza `catalog.guard_priced_ingredient` para agregar un caso: también la cambia quien tiene `catalog.manage` si la saca de un rubro dado de baja. La baja marca el rubro como inactivo antes de pasar las materias primas, y un rubro dado de baja no recibe nada nuevo.
- **Regla de clase:** la controla un trigger en `recipes.recipes`, solo al crear una receta o al cambiarle la categoría o el tipo.
  - Lo cargado antes **no se toca**: editar otra cosa sigue funcionando.
  - Una variante nueva que copia el rubro de su maestra se crea igual.
  - El panel cuenta las recetas que quedaron en la otra clase, para corregirlas a mano.
- **Datos actuales:** la migración llama a `recipes.map_legacy_categories(grupo, equivalencias)` en cada grupo existente. La función está probada en `250_rubros` con categorías viejas simuladas, y hace esto:
  1. **Clase** de las categorías de recetas: la del tipo de la mayoría de sus recetas. En empate o sin recetas, el nombre decide (sub-recetas si es el de un rubro SR de Soy; si no, menú). Las subcategorías heredan la de su rubro.
  2. **Código de Soy**, emparejando con un rubro de la misma clase, en este orden:
     - la equivalencia acordada (nombre sin tildes → código);
     - el mismo nombre;
     - la misma primera palabra, si es única de los dos lados («Carnes» → MP-CAR «Carnes y aves»).
     - La emparejada toma también el **nombre de Soy** (decisión de Soy, 2026-11-11), salvo que otro rubro vigente del grupo ya se llame así.
  3. Los **rubros de Soy que faltan** (`recipes.install_default_categories`).
  4. Un **código propio** para el resto.
  - **Lo borrado queda como estaba.** Un registro borrado no se edita (`core.set_control_columns`), así que las reglas de código y clase valen solo para lo vigente.
- **Permisos** (decisiones de Joaco, 2026-11-10), para todo el grupo y en una sola función, `recipes.can_manage_category`:
  - Compra: `catalog.manage` (Compras) o `prices.configure` (Dirección).
  - Sub-recetas y menú: un permiso propio, `recipes.manage_categories`, para que Soy se lo pueda dar a otro rol. Arranca en los roles que tenían `recipes.draft`, así que hoy no cambia quién puede.
  - Ver el panel: `catalog.view` o `recipes.view`.
- **Conteos:** `recipes.category_overview(group)` hace una sola consulta agrupada por rubro, con los permisos de quien consulta.
- **Panel:** `/rubros`, en Base de conocimiento.
  - Pestañas, resumen en una franja y grilla de tarjetas de 88 px (5 columnas en la computadora, 2 en el celular).
  - En cada tarjeta, el nombre va a todo el ancho y en hasta dos líneas. Abajo van el código, el % y el contador, el estado con ícono y palabra (en gris si está dado de baja) y una barra fina con el tono fuerte de la pestaña.
  - El nombre se edita en el lugar: Enter guarda y Escape cancela, con un motivo fijo, «Cambio de nombre desde Rubros».
  - «+ Nuevo rubro» va al final.
- **Alta de una receta:** el selector ofrece solo los rubros de la clase del tipo elegido.
- **Configuración del catálogo:** desde ahí se crean solo subcategorías. Los rubros se crean, se dan de baja y se reactivan en Rubros.

## Lo que se dejó afuera, y por qué

- **El resumen no usa tarjetas de KPI.** Cuatro tarjetas de 140 px no entran sin scroll con cinco filas de rubros en 1440 × 900. Soy pidió «una pantalla, sin scroll».
  - Igual, «sin scroll» depende de la cantidad de rubros: en 1440 × 900 entran hasta 25 de una pestaña con «+ Nuevo rubro»; en 1280 × 800, menos.
- **Los selectores siguen mostrando el nombre, sin el código.** Se evita romper las pantallas y pruebas que eligen por nombre. Sí dejan de ofrecer los rubros dados de baja y, en recetas, se agrupan o filtran por clase.
- **La importación sigue reconociendo el rubro por nombre, no por código.** La función que lo lee no conoce el grupo. Si el Excel nombra un rubro dado de baja, la confirmación falla sin decir la fila. Si hace falta, va en otro PR.
- **Las funciones viejas todavía crean rubros:** `catalog.create_category` sin madre crea un rubro de compra con su código. Pide el mismo permiso y queda auditado, así que no es un agujero; la pantalla ya no lo usa. Cerrarlo obliga a reescribir `160_catalog_settings`, y va en otro PR.

## Riesgos

- **Equivalencias de nombres (aprobadas por Soy, 2026-11-11):** a partir de las categorías de staging (consulta de solo lectura de Joaco), la migración carga `carne → MP-CAR`, `quesos → MP-LAC`, `verdura → MP-VER`, `carnes → PL-CAR` y `pescados → PL-PES`. «PASTAS» y «POSTRES» se emparejan solas. `250_rubros` simula esas 7 categorías y comprueba que quedan exactamente los 46 rubros de Soy. Si producción tiene otras categorías que staging no tiene, quedan con código propio: antes de producción, conviene correr la misma consulta allá.
- Las recetas ya cargadas en staging con un rubro de la otra clase no se modifican: hay que corregirlas a mano (el panel avisa cuántas son).
- Una categoría vieja de recetas usada por platos y preparaciones queda con la clase de la mayoría. Las de la minoría quedan en la otra clase hasta que se corrijan.
- **Compras puede cambiar cuándo vence un precio sin pasar por Dirección**, cuando da de baja un rubro y sus materias primas con precios pasan a un rubro con otros días de vencimiento. Joaco lo aceptó: queda en la auditoría, con quién y por qué.
  - **Aceptado por Joaco (2026-11-10)**, a partir de la revisión de seguridad: dar de baja un rubro y reactivarlo enseguida permite a Compras pasar todas sus materias primas con precio a un rubro con más días y así cambiar cuándo vencen sus precios sin Dirección. Queda auditado. La alternativa, que la baja pida `prices.configure` cuando los días de vencimiento del origen y del destino son distintos, se descartó.
  - El guard confía en `is_active` del rubro y no en una marca de la baja: si en el futuro otra función cambia la categoría de una materia prima de un rubro dado de baja, hereda el caso. Hoy no hay ninguna.
- **Las funciones de antes de los rubros:** `recipes.rename_category` y `recipes.archive_category` piden `recipes.draft`. Para que no esquiven el permiso nuevo, el trigger `recipes.guard_top_category` pide `recipes.manage_categories` para cambiar un rubro de recetas por cualquier camino. Las subcategorías siguen con `recipes.draft`.
