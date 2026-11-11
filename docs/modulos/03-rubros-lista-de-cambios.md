# Rubros: lista de lo que cambia (para Soy)

Pedido: `instrucciones-rubros-claude-code.md`. Decisión técnica: ADR-0038. Rama: `feat/rubros`.

## En pocas palabras

- El recetario ahora tiene **rubros con código**, en tres clases:
  - **de compra (MP):** por ejemplo, MP-CAR Carnes y aves;
  - **de sub-recetas (SR):** por ejemplo, SR-SAL Salsas;
  - **de menú (PL):** por ejemplo, PL-PAS Pastas.
- Están cargados **los 46 rubros de tu lista**.
- Hay una pantalla nueva, **Rubros**, para:
  - darlos de alta, cambiarles el nombre, darlos de baja y reactivarlos;
  - ver cuántos insumos o recetas tiene cada uno y qué parte del total representa.
- **No se borró nada.** No se borraron tablas, campos ni datos. Las categorías que ya existían pasaron a ser rubros: toman el código y el nombre de tu lista cuando se emparejan con uno de tus rubros. Si no se emparejan, conservan su nombre y llevan un código propio con el mismo formato.

## Qué ve la gente

| Dónde                               | Qué cambia                                                                                                |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Menú lateral (Base de conocimiento) | Aparece **Rubros**. Lo ve quien ve materias primas o recetas.                                             |
| Rubros                              | Tres pestañas, un resumen (total, activos, dados de baja, sin uso) y una tarjeta por rubro.               |
| Alta de una materia prima           | No ofrece los rubros dados de baja.                                                                       |
| Alta de una receta                  | Los rubros aparecen agrupados: de menú (para platos) y de sub-recetas (para preparaciones y componentes). |
| Ficha de una receta                 | Solo ofrece los rubros que corresponden a su tipo.                                                        |
| Configuración del catálogo          | Desde ahí se crean solo **subcategorías** dentro de un rubro. Los rubros se manejan en Rubros.            |

## Reglas nuevas, que controla la base (no la pantalla)

1. Un **plato** va en un rubro de **menú**. Una **preparación** o un **componente** va en uno de **sub-recetas**.
2. Un rubro **dado de baja** no recibe insumos ni recetas nuevos. Se puede reactivar.
3. Para dar de baja un rubro que se usa, hay que **elegir a qué rubro pasar** sus insumos o recetas. El pase y la baja se hacen juntos.
4. El **código** se arma solo con el prefijo y tres letras del nombre, y no cambia nunca.
5. Todo queda en el **historial**: quién, cuándo y por qué.

**Quién puede:**

- Rubros de compra: Compras o Dirección, cada uno por su cuenta.
- Rubros de sub-recetas y de menú: un permiso nuevo, «administrar rubros de sub-recetas y menú». Lo tienen los mismos roles que hoy crean recetas, como el Chef del grupo, siempre para todo el grupo. Soy se lo puede dar a otro rol desde Roles.
- El resto de la gente los ve sin poder cambiarlos.

## Lo que ya existía y no cambia

- **El costo en cascada:** una receta usa insumos y sub-recetas, y el costo sube por la cadena. Ya funcionaba y sigue igual.
- Las subcategorías (por ejemplo, Lácteos › Quesos) siguen igual, ahora dentro de su rubro.
- Los días de precio vencido por categoría, la importación del recetario, los reportes, los costos y la calidad de datos siguen funcionando.

## A revisar antes de producción

- **Recetas viejas en el rubro equivocado:** si en staging hay un plato en un rubro de sub-recetas (o al revés), la base no lo toca. La pantalla de Rubros avisa cuántas son, y hay que corregirlas desde la ficha de cada receta.
- **Categorías de staging (aprobado por vos el 2026-11-11):** las 7 categorías que hay hoy en staging quedan así, con tu código y tu nombre, sin rubros repetidos:

  | Hoy en staging | Queda como                    |
  | -------------- | ----------------------------- |
  | Carne          | MP-CAR Carnes y aves          |
  | QUESOS         | MP-LAC Lácteos y quesos       |
  | Verdura        | MP-VER Verduras y hortalizas  |
  | CARNES         | PL-CAR Principales de carne   |
  | PASTAS         | PL-PAS Pastas                 |
  | PESCADOS       | PL-PES Principales de pescado |
  | POSTRES        | PL-POS Postres                |
  - Si producción tiene categorías que staging no tiene, antes de pasar hay que revisarlas igual.
  - Después también se pueden juntar: se da de baja el rubro viejo eligiendo el tuyo como destino.

- **Insumos con precio:** al dar de baja un rubro de compra, sus insumos con precio pasan al rubro elegido, y eso lo puede hacer Compras o Dirección. Si el rubro nuevo tiene otros días de vencimiento, cambia cuándo ese precio se considera viejo. Fuera de una baja, cambiarle el rubro a un insumo con precio lo sigue decidiendo Dirección.
- **Lo que estaba borrado** antes de los rubros queda como estaba, sin código.
- **Colores:** se usaron los colores del sistema, casi iguales a los del documento, para no tener dos paletas.

## Técnico (para Joaco)

- **Migración:** `20261124120000_rubros.sql`. Agrega:
  - el tipo `recipes.category_class`;
  - el permiso `recipes.manage_categories`;
  - las columnas `code` e `is_active` en las dos tablas de categorías, y `kind` en la de recetas;
  - restricciones e índices, cuatro triggers y la vista `recipes.top_categories`;
  - las funciones `category_overview`, `create_top_category`, `rename_top_category`, `deactivate_top_category`, `reactivate_top_category` e `install_default_categories`, y el caso nuevo de `catalog.guard_priced_ingredient` (insumos con precio al dar de baja un rubro).
- **Seed:** las categorías ficticias llevan su código. Tres recetas de prueba cambiaron de rubro para cumplir la regla: la masa de pasta, la bondiola braseada y la ensalada de atún.
- **Pruebas:**
  - nuevas: `supabase/tests/250_rubros.test.sql`, `tests/unit/rubros.test.ts` y `tests/e2e/rubros.spec.ts`;
  - ajustadas por los datos de prueba (los platos ahora usan un rubro de menú): 170, 230 a 237, 239 y 050 (lista de funciones), además de `configuracion-catalogo.spec.ts` y `design-system.test.ts`.
