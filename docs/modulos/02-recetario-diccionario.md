# Diccionario de datos — catalog, recipes

> Generado desde los `comment on` de la base local el 2026-10-30 con `npm run db:dictionary`. No editar a mano: regenerar después de cada migración.

## `catalog.allergens`

Lista configurable de alérgenos (Código Alimentario Argentino). No se usa como válida hasta que un responsable la valida (pregunta N5).

| Columna           | Tipo                       | Nulo | Qué guarda                                                 |
| ----------------- | -------------------------- | ---- | ---------------------------------------------------------- |
| `id`              | `uuid`                     | no   | Identificador.                                             |
| `group_id`        | `uuid`                     | no   | Grupo al que pertenece.                                    |
| `code`            | `text`                     | no   | Código único dentro del grupo (en mayúsculas).             |
| `name`            | `text`                     | no   | Nombre del alérgeno.                                       |
| `legal_reference` | `text`                     | sí   | Referencia normativa (artículo del Código Alimentario).    |
| `validated_by`    | `uuid`                     | sí   | Quién validó el alérgeno en la lista. Vacío = sin validar. |
| `validated_at`    | `timestamp with time zone` | sí   | Cuándo se validó.                                          |
| `created_at`      | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                          |
| `created_by`      | `uuid`                     | sí   | Quién lo creó (lo pone la base).                           |
| `updated_at`      | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).         |
| `updated_by`      | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).          |
| `deleted_at`      | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.   |
| `deleted_by`      | `uuid`                     | sí   | Quién lo borró (lo pone la base).                          |

## `catalog.ingredient_aliases`

Otros nombres de un ingrediente ("muzza" para mozzarella), para buscar e importar sin duplicar. Un alias apunta a un solo ingrediente del grupo.

| Columna         | Tipo                       | Nulo | Qué guarda                                                                |
| --------------- | -------------------------- | ---- | ------------------------------------------------------------------------- |
| `id`            | `uuid`                     | no   | Identificador.                                                            |
| `group_id`      | `uuid`                     | no   | Grupo al que pertenece. El mismo que el del ingrediente.                  |
| `ingredient_id` | `uuid`                     | no   | Ingrediente al que se refiere.                                            |
| `alias`         | `text`                     | no   | El otro nombre, en minúsculas. Único dentro del grupo entre los vigentes. |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                         |
| `created_by`    | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                          |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                        |
| `updated_by`    | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                         |
| `deleted_at`    | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                  |
| `deleted_by`    | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                         |

## `catalog.ingredient_allergens`

Estado de cada alérgeno en cada ingrediente. Sin fila = sin dato: el plato que lo use muestra NO VERIFICADO, nunca "sin alérgenos".

| Columna         | Tipo                       | Nulo | Qué guarda                                                                                          |
| --------------- | -------------------------- | ---- | --------------------------------------------------------------------------------------------------- |
| `id`            | `uuid`                     | no   | Identificador.                                                                                      |
| `group_id`      | `uuid`                     | no   | Grupo al que pertenece.                                                                             |
| `ingredient_id` | `uuid`                     | no   | Ingrediente.                                                                                        |
| `allergen_id`   | `uuid`                     | no   | Alérgeno.                                                                                           |
| `status`        | `catalog.allergen_status`  | no   | Contiene, puede contener (trazas) o no contiene (verificado). Quién lo cargó queda en la auditoría. |
| `source`        | `catalog.data_source`      | no   | De dónde sale el dato.                                                                              |
| `notes`         | `text`                     | sí   | Observaciones.                                                                                      |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                   |
| `created_by`    | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                    |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                  |
| `updated_by`    | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                   |
| `deleted_at`    | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                            |
| `deleted_by`    | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                   |

## `catalog.ingredient_categories`

Categorías y subcategorías de materias primas (dos niveles), por grupo.

| Columna            | Tipo                       | Nulo | Qué guarda                                                                                                                            |
| ------------------ | -------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `id`               | `uuid`                     | no   | Identificador.                                                                                                                        |
| `group_id`         | `uuid`                     | no   | Grupo al que pertenece.                                                                                                               |
| `parent_id`        | `uuid`                     | sí   | Categoría madre, si es una subcategoría. Solo dos niveles.                                                                            |
| `name`             | `text`                     | no   | Nombre. Único dentro de su categoría madre entre las vigentes, sin importar mayúsculas.                                               |
| `stale_price_days` | `smallint`                 | sí   | Días sin actualizar después de los cuales un precio se marca como desactualizado. Vacío = el plazo general (decisión 7, etapa 2.1 C). |
| `created_at`       | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                                     |
| `created_by`       | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                                                      |
| `updated_at`       | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                                    |
| `updated_by`       | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                                                     |
| `deleted_at`       | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                                                              |
| `deleted_by`       | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                                                     |

## `catalog.ingredient_unit_conversions`

Conversiones propias de un ingrediente, medidas y con fuente: densidad (g por ml) o peso por unidad (g por unidad). Sin este dato, una línea que lo necesita queda como CONVERSIÓN FALTANTE: nunca se supone que 1 l pesa 1 kg.

| Columna         | Tipo                       | Nulo | Qué guarda                                                       |
| --------------- | -------------------------- | ---- | ---------------------------------------------------------------- |
| `id`            | `uuid`                     | no   | Identificador.                                                   |
| `group_id`      | `uuid`                     | no   | Grupo al que pertenece. El mismo que el del ingrediente.         |
| `ingredient_id` | `uuid`                     | no   | Ingrediente.                                                     |
| `kind`          | `catalog.conversion_kind`  | no   | density (g por ml) o unit_weight (g por unidad).                 |
| `factor`        | `numeric(18,6)`            | no   | Gramos por mililitro (densidad) o gramos por unidad.             |
| `source`        | `catalog.data_source`      | no   | De dónde sale el dato.                                           |
| `measured_on`   | `date`                     | no   | Fecha de la medición o del dato.                                 |
| `measured_by`   | `text`                     | sí   | Quién lo midió o informó (puede no ser una persona del sistema). |
| `notes`         | `text`                     | sí   | Observaciones.                                                   |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                |
| `created_by`    | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                 |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).               |
| `updated_by`    | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                |
| `deleted_at`    | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.         |
| `deleted_by`    | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                |

## `catalog.ingredient_yield_profiles`

Rendimiento estándar de una materia prima según el proceso (sección 9). Es el que usa el motor de costos. Inmutable: corregirlo es proponer otro, que pasa por aprobación.

| Columna               | Tipo                       | Nulo | Qué guarda                                                                                                                                           |
| --------------------- | -------------------------- | ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                  | `uuid`                     | no   | Identificador.                                                                                                                                       |
| `group_id`            | `uuid`                     | no   | Grupo al que pertenece. El mismo que el del ingrediente.                                                                                             |
| `ingredient_id`       | `uuid`                     | no   | Materia prima.                                                                                                                                       |
| `process_id`          | `uuid`                     | no   | Proceso (pelado, hervido…).                                                                                                                          |
| `cut`                 | `text`                     | sí   | Corte o presentación, si cambia el rendimiento (por ejemplo, "en cubos").                                                                            |
| `supplier_id`         | `uuid`                     | sí   | Proveedor, solo si el rendimiento depende de él. Vacío = vale para todos.                                                                            |
| `cleaning_yield`      | `numeric(7,4)`             | no   | Rendimiento de limpieza: peso comestible / peso bruto, entre 0 y 1 (4 decimales). 1 si el proceso no limpia.                                         |
| `cooking_factor`      | `numeric(7,4)`             | no   | Factor de cocción: peso después / peso antes. Menor a 1 si pierde peso (merma de cocción); mayor a 1 si hidrata (pasta, arroz). 1 si no hay cocción. |
| `method`              | `text`                     | sí   | Cómo se mide o se llegó al valor.                                                                                                                    |
| `declared_no_loss`    | `boolean`                  | no   | Declarado "sin merma": obligatorio para usar 100 % de limpieza sin cambio en la cocción. La firma es la aprobación.                                  |
| `status`              | `catalog.yield_status`     | no   | Propuesto, estándar vigente o reemplazado.                                                                                                           |
| `approval_request_id` | `uuid`                     | sí   | Solicitud de aprobación con la que se propuso.                                                                                                       |
| `approved_by`         | `uuid`                     | sí   | Quién lo aprobó (no puede ser quien lo propuso).                                                                                                     |
| `approved_at`         | `timestamp with time zone` | sí   | Cuándo se aprobó.                                                                                                                                    |
| `notes`               | `text`                     | sí   | Observaciones.                                                                                                                                       |
| `created_at`          | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                                                    |
| `created_by`          | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                                                                     |
| `updated_at`          | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                                                   |
| `updated_by`          | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                                                                    |
| `deleted_at`          | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                                                                             |
| `deleted_by`          | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                                                                    |

## `catalog.ingredient_yield_tests`

Ensayos de rendimiento: lo que se midió en una cocina. Solo inserción. Nunca cambian el estándar: la pantalla muestra la diferencia y el estándar se cambia con una propuesta aprobada.

| Columna                 | Tipo                       | Nulo | Qué guarda                                                              |
| ----------------------- | -------------------------- | ---- | ----------------------------------------------------------------------- |
| `id`                    | `uuid`                     | no   | Identificador.                                                          |
| `group_id`              | `uuid`                     | no   | Grupo al que pertenece. El mismo que el del ingrediente y el del local. |
| `ingredient_id`         | `uuid`                     | no   | Materia prima.                                                          |
| `process_id`            | `uuid`                     | no   | Proceso que se midió.                                                   |
| `cut`                   | `text`                     | sí   | Corte o presentación, si corresponde.                                   |
| `supplier_id`           | `uuid`                     | sí   | Proveedor de la mercadería medida, si se conoce.                        |
| `restaurant_id`         | `uuid`                     | no   | Local donde se midió.                                                   |
| `tested_on`             | `date`                     | no   | Fecha de la medición.                                                   |
| `samples`               | `integer`                  | no   | Cuántas muestras o tandas se pesaron.                                   |
| `gross_weight`          | `numeric(18,6)`            | sí   | Peso bruto, en gramos (antes de limpiar).                               |
| `clean_weight`          | `numeric(18,6)`            | sí   | Peso limpio o comestible, en gramos.                                    |
| `before_cooking_weight` | `numeric(18,6)`            | sí   | Peso antes de cocinar, en gramos.                                       |
| `after_cooking_weight`  | `numeric(18,6)`            | sí   | Peso después de cocinar, en gramos.                                     |
| `discard_weight`        | `numeric(18,6)`            | sí   | Descarte pesado aparte, en gramos (informativo).                        |
| `responsible`           | `text`                     | sí   | Quién hizo la medición (puede no ser una persona del sistema).          |
| `notes`                 | `text`                     | sí   | Observaciones.                                                          |
| `created_at`            | `timestamp with time zone` | no   | Cuándo se registró (lo pone la base).                                   |
| `created_by`            | `uuid`                     | sí   | Quién lo registró (lo pone la base).                                    |

## `catalog.ingredients`

Ingredientes gastronómicos (la mozzarella, no la horma de una marca): se cargan una sola vez para todo el grupo. Nunca se borran: se desactivan.

| Columna            | Tipo                       | Nulo | Qué guarda                                                                                          |
| ------------------ | -------------------------- | ---- | --------------------------------------------------------------------------------------------------- |
| `id`               | `uuid`                     | no   | Identificador.                                                                                      |
| `group_id`         | `uuid`                     | no   | Grupo al que pertenece.                                                                             |
| `code`             | `text`                     | no   | Código único dentro del grupo (en mayúsculas). No cambia nunca: sirve para importar sin duplicar.   |
| `name`             | `text`                     | no   | Nombre gastronómico, sin marca. Único dentro del grupo entre los vigentes, sin importar mayúsculas. |
| `category_id`      | `uuid`                     | no   | Categoría o subcategoría.                                                                           |
| `recipe_unit_id`   | `uuid`                     | no   | Unidad en que se usa en recetas: siempre una unidad base (g, ml o unidad).                          |
| `purchase_unit_id` | `uuid`                     | sí   | Unidad en que se compra normalmente (informativa).                                                  |
| `storage_unit_id`  | `uuid`                     | sí   | Unidad en que se almacena (informativa).                                                            |
| `costing_unit_id`  | `uuid`                     | sí   | Unidad en que se muestra su costo (informativa).                                                    |
| `is_active`        | `boolean`                  | no   | Si se puede usar en recetas nuevas. Desactivar no borra nada.                                       |
| `notes`            | `text`                     | sí   | Observaciones.                                                                                      |
| `created_at`       | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                   |
| `created_by`       | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                    |
| `updated_at`       | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                  |
| `updated_by`       | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                   |
| `deleted_at`       | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                            |
| `deleted_by`       | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                   |

## `catalog.purchase_products`

Productos de compra: cómo se compra un ingrediente ("Mozzarella marca X, horma de 4 kg"). Varios productos pueden apuntar al mismo ingrediente. El precio va aparte (etapa 2.1 C).

| Columna             | Tipo                       | Nulo | Qué guarda                                                                                                                                                             |
| ------------------- | -------------------------- | ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                | `uuid`                     | no   | Identificador.                                                                                                                                                         |
| `group_id`          | `uuid`                     | no   | Grupo al que pertenece. El mismo que el del ingrediente.                                                                                                               |
| `code`              | `text`                     | no   | Código único dentro del grupo (en mayúsculas).                                                                                                                         |
| `ingredient_id`     | `uuid`                     | no   | Ingrediente al que corresponde. No cambia: un producto de otro ingrediente es otro producto.                                                                           |
| `supplier_id`       | `uuid`                     | sí   | Proveedor habitual (opcional: el precio dice a quién se compró).                                                                                                       |
| `description`       | `text`                     | no   | Descripción como la vende el proveedor.                                                                                                                                |
| `brand_name`        | `text`                     | sí   | Marca comercial, si corresponde.                                                                                                                                       |
| `package_unit_id`   | `uuid`                     | no   | Cómo viene: horma, caja, bolsa, botella, kg…                                                                                                                           |
| `units_per_package` | `integer`                  | no   | Cuántas unidades trae el envase (caja de 12 botellas = 12).                                                                                                            |
| `content_per_unit`  | `numeric(18,6)`            | no   | Contenido de cada unidad (botella de 750 ml = 750). Obligatorio: nunca se supone.                                                                                      |
| `content_unit_id`   | `uuid`                     | no   | Unidad del contenido (masa, volumen o conteo; nunca un envase). Si no es de la dimensión de uso del ingrediente, el ingrediente tiene que tener la conversión cargada. |
| `is_active`         | `boolean`                  | no   | Si se sigue comprando. Desactivar no borra nada.                                                                                                                       |
| `notes`             | `text`                     | sí   | Observaciones.                                                                                                                                                         |
| `created_at`        | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                                                                      |
| `created_by`        | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                                                                                       |
| `updated_at`        | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                                                                     |
| `updated_by`        | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                                                                                      |
| `deleted_at`        | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                                                                                               |
| `deleted_by`        | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                                                                                      |

## `catalog.suppliers`

Proveedores del grupo. Nunca se borran: se desactivan.

| Columna       | Tipo                       | Nulo | Qué guarda                                                                               |
| ------------- | -------------------------- | ---- | ---------------------------------------------------------------------------------------- |
| `id`          | `uuid`                     | no   | Identificador.                                                                           |
| `group_id`    | `uuid`                     | no   | Grupo al que pertenece.                                                                  |
| `code`        | `text`                     | no   | Código único dentro del grupo (en mayúsculas).                                           |
| `name`        | `text`                     | no   | Nombre. Único dentro del grupo entre los vigentes, sin importar mayúsculas.              |
| `tax_id`      | `text`                     | sí   | CUIT, si se conoce.                                                                      |
| `is_internal` | `boolean`                  | no   | Si es una unidad del propio grupo que provee a otras (por ejemplo, Pariggi; decisión 6). |
| `is_active`   | `boolean`                  | no   | Si se le sigue comprando. Desactivar no borra nada.                                      |
| `notes`       | `text`                     | sí   | Observaciones.                                                                           |
| `created_at`  | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                        |
| `created_by`  | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                         |
| `updated_at`  | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                       |
| `updated_by`  | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                        |
| `deleted_at`  | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                                 |
| `deleted_by`  | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                        |

## `catalog.unit_conversions`

Conversiones universales dentro de una dimensión, siempre hacia su unidad base (1 kg = 1.000 g; 1 docena = 12 unidades). Nunca entre dimensiones ni para envases.

| Columna        | Tipo                       | Nulo | Qué guarda                                                |
| -------------- | -------------------------- | ---- | --------------------------------------------------------- |
| `id`           | `uuid`                     | no   | Identificador.                                            |
| `from_unit_id` | `uuid`                     | no   | Unidad de origen. Una sola conversión vigente por unidad. |
| `to_unit_id`   | `uuid`                     | no   | Unidad base de la misma dimensión.                        |
| `factor`       | `numeric(18,6)`            | no   | Cuántas unidades base hay en una unidad de origen.        |
| `created_at`   | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                         |
| `created_by`   | `uuid`                     | sí   | Quién lo creó (lo pone la base).                          |
| `updated_at`   | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).        |
| `updated_by`   | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).         |
| `deleted_at`   | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.  |
| `deleted_by`   | `uuid`                     | sí   | Quién lo borró (lo pone la base).                         |

## `catalog.units`

Unidades de medida (referencia global). Todo cálculo se hace en las unidades base: g, ml y unidad (sección 8).

| Columna      | Tipo                       | Nulo | Qué guarda                                                                         |
| ------------ | -------------------------- | ---- | ---------------------------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador.                                                                     |
| `code`       | `text`                     | no   | Código de la unidad (g, kg, ml, l, unit, dozen, box…). Único entre las vigentes.   |
| `name`       | `text`                     | no   | Nombre que se muestra, en español (g, kg, l, docena, caja…).                       |
| `dimension`  | `catalog.dimension`        | no   | Dimensión: masa, volumen, conteo o envase. Las de envase no tienen contenido fijo. |
| `is_base`    | `boolean`                  | no   | Si es la unidad base de su dimensión (g, ml o unidad).                             |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                  |
| `created_by` | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                   |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                 |
| `updated_by` | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                  |
| `deleted_at` | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.                           |
| `deleted_by` | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                  |

## `catalog.yield_processes`

Procesos que cambian el peso de una materia prima: pelado, desgrasado, deshuesado, hervido…

| Columna      | Tipo                       | Nulo | Qué guarda                                                     |
| ------------ | -------------------------- | ---- | -------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador.                                                 |
| `group_id`   | `uuid`                     | no   | Grupo al que pertenece.                                        |
| `code`       | `text`                     | no   | Código único dentro del grupo (en mayúsculas).                 |
| `name`       | `text`                     | no   | Nombre del proceso. Único dentro del grupo entre los vigentes. |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                              |
| `created_by` | `uuid`                     | sí   | Quién lo creó (lo pone la base).                               |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).             |
| `updated_by` | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).              |
| `deleted_at` | `timestamp with time zone` | sí   | Cuándo se borró (borrado lógico). Vacío si está vigente.       |
| `deleted_by` | `uuid`                     | sí   | Quién lo borró (lo pone la base).                              |

## `recipes.recipe_assignments`

Qué receta usa cada local y desde cuándo, sin copiarla. Una receta de local queda asignada a su local sola.

| Columna         | Tipo                       | Nulo | Qué guarda                                             |
| --------------- | -------------------------- | ---- | ------------------------------------------------------ |
| `id`            | `uuid`                     | no   | Identificador de la asignación.                        |
| `group_id`      | `uuid`                     | no   | Grupo de la receta.                                    |
| `recipe_id`     | `uuid`                     | no   | Receta asignada.                                       |
| `restaurant_id` | `uuid`                     | no   | Local que la usa.                                      |
| `valid_from`    | `date`                     | no   | Desde qué día la usa (fecha de la Argentina).          |
| `valid_to`      | `date`                     | sí   | Hasta qué día (sin incluirlo). Vacío si sigue vigente. |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                      |
| `created_by`    | `uuid`                     | sí   | Quién la creó (lo pone la base).                       |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).     |
| `updated_by`    | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).      |
| `deleted_at`    | `timestamp with time zone` | sí   | Borrado lógico.                                        |
| `deleted_by`    | `uuid`                     | sí   | Quién la borró (lo pone la base).                      |

## `recipes.recipe_categories`

Categorías y subcategorías de recetas (dos niveles), por grupo.

| Columna      | Tipo                       | Nulo | Qué guarda                                                                              |
| ------------ | -------------------------- | ---- | --------------------------------------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador de la categoría.                                                          |
| `group_id`   | `uuid`                     | no   | Grupo al que pertenece.                                                                 |
| `parent_id`  | `uuid`                     | sí   | Categoría madre, si es una subcategoría. Solo dos niveles.                              |
| `name`       | `text`                     | no   | Nombre. Único dentro de su categoría madre entre las vigentes, sin importar mayúsculas. |
| `created_at` | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                       |
| `created_by` | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                        |
| `updated_at` | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                      |
| `updated_by` | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                       |
| `deleted_at` | `timestamp with time zone` | sí   | Borrado lógico. Vacío si está vigente.                                                  |
| `deleted_by` | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                       |

## `recipes.recipe_components`

Líneas de la fórmula de una versión: qué materia prima, cuánto y en qué base. Solo cambian mientras la versión es borrador. Las subrecetas llegan en la 2.2 B.

| Columna             | Tipo                       | Nulo | Qué guarda                                                                            |
| ------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------- |
| `id`                | `uuid`                     | no   | Identificador de la línea.                                                            |
| `group_id`          | `uuid`                     | no   | Grupo de la receta.                                                                   |
| `brand_id`          | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance.           |
| `restaurant_id`     | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                             |
| `recipe_version_id` | `uuid`                     | no   | Versión a la que pertenece.                                                           |
| `line_order`        | `integer`                  | no   | Orden de la línea en la receta.                                                       |
| `ingredient_id`     | `uuid`                     | no   | Materia prima.                                                                        |
| `quantity`          | `numeric(18,6)`            | no   | Cantidad, en unit_id.                                                                 |
| `unit_id`           | `uuid`                     | no   | Unidad de la cantidad. Tiene que poder pasarse a la unidad de la materia prima.       |
| `quantity_basis`    | `recipes.quantity_basis`   | no   | Qué representa la cantidad: peso de compra, limpio o cocido.                          |
| `yield_profile_id`  | `uuid`                     | sí   | Rendimiento estándar a aplicar (de esta materia prima), si corresponde.               |
| `no_scale`          | `boolean`                  | no   | Si la línea no se escala (terminaciones, redondeos): se ajusta a mano.                |
| `notes`             | `text`                     | sí   | Observaciones de la línea.                                                            |
| `created_at`        | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                     |
| `created_by`        | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                      |
| `updated_at`        | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                    |
| `updated_by`        | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                     |
| `deleted_at`        | `timestamp with time zone` | sí   | Borrado lógico: al guardar las líneas de un borrador, las anteriores quedan borradas. |
| `deleted_by`        | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                     |

## `recipes.recipe_media`

Fotos de una versión de receta. El archivo está en Storage (bucket recipe-media); acá quedan qué muestra, de qué versión y quién la subió. Solo cambian en un borrador; nada se borra: se da de baja.

| Columna             | Tipo                       | Nulo | Qué guarda                                                                               |
| ------------------- | -------------------------- | ---- | ---------------------------------------------------------------------------------------- |
| `id`                | `uuid`                     | no   | Identificador de la foto en esa versión.                                                 |
| `group_id`          | `uuid`                     | no   | Grupo de la receta.                                                                      |
| `brand_id`          | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance.              |
| `restaurant_id`     | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                                |
| `recipe_id`         | `uuid`                     | no   | Receta de la foto.                                                                       |
| `recipe_version_id` | `uuid`                     | no   | Versión a la que pertenece. La cocina ve solo las fotos de la versión vigente.           |
| `kind`              | `recipes.media_kind`       | no   | Qué muestra: producto final, emplatado, materia prima, paso, punto crítico o un ejemplo. |
| `storage_path`      | `text`                     | no   | Dónde está el archivo en el bucket recipe-media: <grupo>/<receta>/<archivo>.             |
| `description`       | `text`                     | sí   | Qué se ve en la foto.                                                                    |
| `created_at`        | `timestamp with time zone` | no   | Cuándo se agregó a la versión (lo pone la base).                                         |
| `created_by`        | `uuid`                     | sí   | Quién la agregó (lo pone la base).                                                       |
| `updated_at`        | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                       |
| `updated_by`        | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                        |
| `deleted_at`        | `timestamp with time zone` | sí   | Baja de la foto en el borrador. El archivo queda en Storage como historia.               |
| `deleted_by`        | `uuid`                     | sí   | Quién la dio de baja (lo pone la base).                                                  |

## `recipes.recipe_step_dependencies`

Qué paso espera a cuál, para calcular el camino crítico. Misma versión y sin ciclos (trigger).

| Columna              | Tipo                       | Nulo | Qué guarda                                                                  |
| -------------------- | -------------------------- | ---- | --------------------------------------------------------------------------- |
| `id`                 | `uuid`                     | no   | Identificador de la dependencia.                                            |
| `group_id`           | `uuid`                     | no   | Grupo de la receta.                                                         |
| `brand_id`           | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance. |
| `restaurant_id`      | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                   |
| `step_id`            | `uuid`                     | no   | El paso que espera.                                                         |
| `depends_on_step_id` | `uuid`                     | no   | El paso que tiene que terminar antes.                                       |
| `created_at`         | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                           |
| `created_by`         | `uuid`                     | sí   | Quién la creó (lo pone la base).                                            |
| `updated_at`         | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                          |
| `updated_by`         | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                           |
| `deleted_at`         | `timestamp with time zone` | sí   | Borrado lógico, junto con su paso.                                          |
| `deleted_by`         | `uuid`                     | sí   | Quién la borró (lo pone la base).                                           |

## `recipes.recipe_steps`

Procedimiento de una versión: pasos con sus tiempos. Solo cambian mientras la versión es borrador.

| Columna             | Tipo                       | Nulo | Qué guarda                                                                                              |
| ------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------------------- |
| `id`                | `uuid`                     | no   | Identificador del paso.                                                                                 |
| `group_id`          | `uuid`                     | no   | Grupo de la receta.                                                                                     |
| `brand_id`          | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance.                             |
| `restaurant_id`     | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                                               |
| `recipe_version_id` | `uuid`                     | no   | Versión a la que pertenece.                                                                             |
| `step_number`       | `integer`                  | no   | Número del paso (1, 2, 3…).                                                                             |
| `kind`              | `recipes.step_kind`        | no   | Tipo de paso: preparación, cocción, reposo, fermentación, enfriamiento, regeneración, emplatado u otro. |
| `instructions`      | `text`                     | no   | Qué se hace en el paso.                                                                                 |
| `active_minutes`    | `integer`                  | no   | Minutos con una persona trabajando.                                                                     |
| `passive_minutes`   | `integer`                  | no   | Minutos de espera (cocción, reposo, fermentación) sin una persona encima.                               |
| `workers`           | `smallint`                 | sí   | Cuántas personas hacen falta.                                                                           |
| `sector`            | `text`                     | sí   | Sector de la cocina.                                                                                    |
| `equipment`         | `text`                     | sí   | Equipo que se usa.                                                                                      |
| `control_point`     | `text`                     | sí   | Punto de control o criterio de calidad del paso.                                                        |
| `created_at`        | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                       |
| `created_by`        | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                        |
| `updated_at`        | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                      |
| `updated_by`        | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                       |
| `deleted_at`        | `timestamp with time zone` | sí   | Borrado lógico: al guardar los pasos de un borrador, los anteriores quedan borrados.                    |
| `deleted_by`        | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                       |

## `recipes.recipe_versions`

Cada versión de la fórmula de una receta. Nace en borrador; desde aprobada no cambia. Una sola publicada (vigente) por receta.

| Columna               | Tipo                       | Nulo | Qué guarda                                                                                                                           |
| --------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `id`                  | `uuid`                     | no   | Identificador de la versión.                                                                                                         |
| `group_id`            | `uuid`                     | no   | Grupo de la receta.                                                                                                                  |
| `brand_id`            | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance.                                                          |
| `restaurant_id`       | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                                                                            |
| `recipe_id`           | `uuid`                     | no   | Receta a la que pertenece.                                                                                                           |
| `version_number`      | `integer`                  | no   | Número de versión (1, 2, 3…).                                                                                                        |
| `status`              | `core.version_status`      | no   | Estado: borrador, en revisión, aprobada, publicada (vigente) o archivada. Desde aprobada no cambia.                                  |
| `previous_version_id` | `uuid`                     | sí   | Versión de la que salió esta, de la misma receta (para ver las diferencias).                                                         |
| `yield_quantity`      | `numeric(18,6)`            | sí   | Cuánto rinde la receta, en yield_unit_id.                                                                                            |
| `yield_unit_id`       | `uuid`                     | sí   | Unidad del rendimiento (kg, l, unidad…).                                                                                             |
| `portions`            | `integer`                  | sí   | Porciones que salen, si es un plato o se porciona.                                                                                   |
| `portion_grams`       | `numeric(18,6)`            | sí   | Peso de una porción, en gramos.                                                                                                      |
| `description`         | `text`                     | sí   | Descripción gastronómica.                                                                                                            |
| `storage_notes`       | `text`                     | sí   | Conservación (método, temperatura, vida útil), solo desde procedimientos validados y con su referencia. El sistema nunca la propone. |
| `presentation_notes`  | `text`                     | sí   | Presentación: montaje, vajilla, guarnición, terminación.                                                                             |
| `change_summary`      | `text`                     | sí   | Qué cambió respecto de la versión anterior y por qué.                                                                                |
| `review_requested_by` | `uuid`                     | sí   | Quién pidió la revisión. Nunca es quien la aprueba.                                                                                  |
| `approval_request_id` | `uuid`                     | sí   | Solicitud de aprobación (recipes.publish_version) de esta versión.                                                                   |
| `approved_by`         | `uuid`                     | sí   | Quién la aprobó y publicó.                                                                                                           |
| `published_at`        | `timestamp with time zone` | sí   | Cuándo quedó vigente.                                                                                                                |
| `created_at`          | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                                    |
| `created_by`          | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                                                                     |
| `updated_at`          | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                                   |
| `updated_by`          | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                                                                    |
| `deleted_at`          | `timestamp with time zone` | sí   | Borrado lógico. Una versión no se borra (trigger): siempre vacío.                                                                    |
| `deleted_by`          | `uuid`                     | sí   | Quién la borró. Siempre vacío.                                                                                                       |

## `recipes.recipes`

Recetas: la identidad (código, nombre, alcance, tipo). La fórmula vive en recipe_versions. Sin valores económicos: los costos van en costing.

| Columna              | Tipo                       | Nulo | Qué guarda                                                                                  |
| -------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------- |
| `id`                 | `uuid`                     | no   | Identificador de la receta.                                                                 |
| `group_id`           | `uuid`                     | no   | Grupo de la receta.                                                                         |
| `brand_id`           | `uuid`                     | sí   | Marca, si la receta es de marca o de local. Vacío en una maestra del grupo.                 |
| `restaurant_id`      | `uuid`                     | sí   | Local, si la receta es de un local. Vacío si es de marca o del grupo.                       |
| `scope_type`         | `recipes.recipe_scope`     | no   | Alcance: maestra del grupo, de marca o de local.                                            |
| `code`               | `text`                     | no   | Código de la receta. Único en el grupo y no cambia nunca: sirve para importar sin duplicar. |
| `name`               | `text`                     | no   | Nombre de la receta.                                                                        |
| `short_name`         | `text`                     | sí   | Nombre corto para la cocina y las comandas.                                                 |
| `recipe_type`        | `recipes.recipe_type`      | no   | Tipo: preparación, plato terminado o componente unitario.                                   |
| `category_id`        | `uuid`                     | sí   | Categoría o subcategoría de la receta.                                                      |
| `sector`             | `text`                     | sí   | Sector de la cocina donde se prepara (por ejemplo, caliente o pastelería).                  |
| `station`            | `text`                     | sí   | Partida o estación (por ejemplo, plancha o pastas).                                         |
| `technical_owner_id` | `uuid`                     | sí   | Responsable técnico de la receta.                                                           |
| `is_active`          | `boolean`                  | no   | Si la receta se usa. Una receta archivada conserva toda su historia.                        |
| `created_at`         | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                           |
| `created_by`         | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                            |
| `updated_at`         | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                          |
| `updated_by`         | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                           |
| `deleted_at`         | `timestamp with time zone` | sí   | Borrado lógico. Vacío si está vigente.                                                      |
| `deleted_by`         | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                           |

## Tipos

| Tipo                      | Valores                                                                                                      | Qué significa                                                                                                                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `catalog.allergen_status` | `contains`, `may_contain`, `free_verified`                                                                   | Estado de un alérgeno en un ingrediente: contains (contiene), may_contain (puede contener, trazas) o free_verified (no contiene, verificado). Sin fila = sin dato: nunca se toma como "sin alérgenos". |
| `catalog.conversion_kind` | `density`, `unit_weight`                                                                                     | Conversión propia de un ingrediente: density (gramos por mililitro) o unit_weight (gramos por unidad: 1 huevo, 1 atado).                                                                               |
| `catalog.data_source`     | `manual`, `excel_import`, `measured`, `supplier`, `calculated`, `estimated`, `verified`                      | Fuente de un dato (sección 6): manual, importado de Excel, medido en ensayo, informado por proveedor, calculado por el sistema, estimado o verificado por un responsable.                              |
| `catalog.dimension`       | `mass`, `volume`, `count`, `package`                                                                         | Dimensión de una unidad: mass (masa, base g), volume (volumen, base ml), count (conteo, base unidad) o package (envase sin contenido fijo: caja, bolsa, horma).                                        |
| `catalog.yield_status`    | `draft`, `approved`, `superseded`                                                                            | Estado de un perfil de rendimiento: draft (propuesto, esperando aprobación), approved (el estándar vigente) o superseded (reemplazado por otro aprobado).                                              |
| `recipes.media_kind`      | `final_product`, `plating`, `raw_material`, `step`, `critical_point`, `correct_example`, `incorrect_example` | Tipo de foto: producto final, emplatado, materia prima, paso, punto crítico, ejemplo correcto o ejemplo incorrecto.                                                                                    |
| `recipes.quantity_basis`  | `purchase`, `clean`, `cooked`                                                                                | Qué representa la cantidad de una línea: peso de compra (purchase), limpio (clean) o cocido (cooked).                                                                                                  |
| `recipes.recipe_scope`    | `group`, `brand`, `restaurant`                                                                               | Alcance: group (maestra del grupo), brand (de marca) o restaurant (de local). Variante y cocina central llegan en la 2.2 B.                                                                            |
| `recipes.recipe_type`     | `preparation`, `dish`, `unit_component`                                                                      | Tipo de receta: preparation (salsa, masa, caldo), dish (plato terminado, por porción) o unit_component (medallón, bollo, empanada armada).                                                             |
| `recipes.step_kind`       | `preparation`, `cooking`, `resting`, `fermentation`, `cooling`, `regeneration`, `plating`, `other`           | Tipo de paso: preparación, cocción, reposo, fermentación, enfriamiento, regeneración, emplatado u otro.                                                                                                |
