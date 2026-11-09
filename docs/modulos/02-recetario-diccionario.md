# Diccionario de datos — catalog, recipes, imports, costing

> Generado desde los `comment on` de la base local el 2026-11-08 con `npm run db:dictionary`. No editar a mano: regenerar después de cada migración.

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

## `costing.cost_recalc_queue`

Pedidos de recálculo de costos. Los anotan los triggers al publicar, aprobar un precio o un rendimiento, asignar una receta o cambiar la razón social; los procesa costing.process_recalc_queue cada minuto. Interna: no se expone por la API.

| Columna            | Tipo                           | Nulo | Qué guarda                                                                                 |
| ------------------ | ------------------------------ | ---- | ------------------------------------------------------------------------------------------ |
| `id`               | `uuid`                         | no   | Identificador.                                                                             |
| `entry_number`     | `bigint`                       | no   | Orden de llegada.                                                                          |
| `group_id`         | `uuid`                         | no   | Grupo de las recetas.                                                                      |
| `recipe_ids`       | `uuid[]`                       | no   | Recetas por recalcular. También se recalculan las que las usan.                            |
| `restaurant_ids`   | `uuid[]`                       | sí   | Locales por recalcular. Vacío: todos los que las usan.                                     |
| `reason`           | `costing.cost_snapshot_reason` | no   | Qué lo causó. Es el motivo de la foto.                                                     |
| `attempts`         | `integer`                      | no   | Intentos fallidos. Con 3, deja de intentarse y hay que mirar el error.                     |
| `processed_at`     | `timestamp with time zone`     | sí   | Cuándo se procesó. Vacío: pendiente.                                                       |
| `error`            | `text`                         | sí   | El último error, si falló.                                                                 |
| `created_at`       | `timestamp with time zone`     | no   | Cuándo se anotó (lo pone la base).                                                         |
| `created_by`       | `uuid`                         | sí   | Quién hizo el cambio (lo pone la base).                                                    |
| `updated_at`       | `timestamp with time zone`     | no   | Cuándo cambió por última vez (lo pone la base).                                            |
| `updated_by`       | `uuid`                         | sí   | Quién la cambió por última vez (lo pone la base).                                          |
| `deleted_at`       | `timestamp with time zone`     | sí   | Baja lógica. No se usa.                                                                    |
| `deleted_by`       | `uuid`                         | sí   | Quién la dio de baja (lo pone la base).                                                    |
| `price_record_id`  | `uuid`                         | sí   | El precio que causó el pedido, si fue un precio. Con processed_at dice en qué tanda entró. |
| `source_recipe_id` | `uuid`                         | sí   | La receta publicada que causó el pedido: de ella sale el aviso con el impacto de costo.    |

## `costing.cost_scenario_overrides`

Lo que cambia un escenario. Un cambio vigente por materia prima y tipo, o por línea. Interna: sin política, se lee y se escribe por funciones.

| Columna               | Tipo                             | Nulo | Qué guarda                                                                                           |
| --------------------- | -------------------------------- | ---- | ---------------------------------------------------------------------------------------------------- |
| `id`                  | `uuid`                           | no   | Identificador.                                                                                       |
| `group_id`            | `uuid`                           | no   | Grupo del escenario.                                                                                 |
| `restaurant_id`       | `uuid`                           | no   | Local del escenario: la auditoría toma de acá el alcance.                                            |
| `scenario_id`         | `uuid`                           | no   | Escenario.                                                                                           |
| `kind`                | `costing.scenario_override_kind` | no   | Qué cambia: precio, rendimiento o gramaje.                                                           |
| `ingredient_id`       | `uuid`                           | sí   | Materia prima, si cambia su precio o su rendimiento.                                                 |
| `recipe_component_id` | `uuid`                           | sí   | Línea de una receta, si cambia el gramaje.                                                           |
| `unit_cost`           | `numeric(20,8)`                  | sí   | Costo simulado por unidad de uso: el que cuenta en el local (sin IVA, o con IVA si no lo descuenta). |
| `supplier_id`         | `uuid`                           | sí   | Proveedor de referencia, si se simula comprarle a otro. No calcula nada.                             |
| `cleaning_yield`      | `numeric(7,4)`                   | sí   | Rendimiento de limpieza simulado.                                                                    |
| `cooking_factor`      | `numeric(7,4)`                   | sí   | Factor de cocción simulado.                                                                          |
| `quantity`            | `numeric(18,6)`                  | sí   | Cantidad simulada, en la unidad de la línea.                                                         |
| `currency`            | `text`                           | no   | Moneda del costo simulado.                                                                           |
| `created_at`          | `timestamp with time zone`       | no   | Cuándo se cargó (lo pone la base).                                                                   |
| `created_by`          | `uuid`                           | sí   | Quién lo cargó (lo pone la base).                                                                    |
| `updated_at`          | `timestamp with time zone`       | no   | Cuándo cambió por última vez (lo pone la base).                                                      |
| `updated_by`          | `uuid`                           | sí   | Quién lo cambió por última vez (lo pone la base).                                                    |
| `deleted_at`          | `timestamp with time zone`       | sí   | Baja lógica: el cambio se quitó del escenario.                                                       |
| `deleted_by`          | `uuid`                           | sí   | Quién lo quitó (lo pone la base).                                                                    |

## `costing.cost_scenarios`

Simulaciones de costo de un local. Guardan solo los cambios: el resultado se calcula al abrirlas y nunca toca lo oficial.

| Columna         | Tipo                       | Nulo | Qué guarda                                        |
| --------------- | -------------------------- | ---- | ------------------------------------------------- |
| `id`            | `uuid`                     | no   | Identificador.                                    |
| `group_id`      | `uuid`                     | no   | Grupo del local.                                  |
| `restaurant_id` | `uuid`                     | no   | Local: el costo depende del local.                |
| `name`          | `text`                     | no   | Nombre del escenario.                             |
| `status`        | `costing.scenario_status`  | no   | Activo o archivado.                               |
| `created_at`    | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                 |
| `created_by`    | `uuid`                     | sí   | Quién lo creó (lo pone la base).                  |
| `updated_at`    | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).   |
| `updated_by`    | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base). |
| `deleted_at`    | `timestamp with time zone` | sí   | Baja lógica. No se usa: un escenario se archiva.  |
| `deleted_by`    | `uuid`                     | sí   | Quién lo dio de baja (lo pone la base).           |

## `costing.price_records`

Precios de compra aprobados, para siempre: un precio nuevo es un registro nuevo y nunca se cambia uno viejo. Cada uno vale para un producto de compra en el grupo, una marca o un local, desde una fecha.

| Columna               | Tipo                       | Nulo | Qué guarda                                                                                                                                                                                                              |
| --------------------- | -------------------------- | ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                  | `uuid`                     | no   | Identificador del precio.                                                                                                                                                                                               |
| `entry_number`        | `bigint`                   | no   | Orden de registro. Entre dos precios que empiezan a valer el mismo día, vale el registrado después.                                                                                                                     |
| `group_id`            | `uuid`                     | no   | Grupo al que pertenece. El mismo que el del producto.                                                                                                                                                                   |
| `purchase_product_id` | `uuid`                     | no   | Producto de compra (la presentación que se compra).                                                                                                                                                                     |
| `supplier_id`         | `uuid`                     | sí   | A quién se le compró a ese precio (opcional).                                                                                                                                                                           |
| `scope_type`          | `core.scope_type`          | no   | Para quién vale: todo el grupo, una marca o un local.                                                                                                                                                                   |
| `brand_id`            | `uuid`                     | sí   | La marca, si el precio es de una marca.                                                                                                                                                                                 |
| `restaurant_id`       | `uuid`                     | sí   | El local, si el precio es de un local.                                                                                                                                                                                  |
| `valid_from`          | `date`                     | no   | Desde qué día vale. Para un local vale el último aprobado de cualquier producto de la materia prima, en el nivel más cercano (local, marca o grupo). No puede ser anterior al último precio del mismo producto y lugar. |
| `package_price`       | `numeric(18,4)`            | no   | Precio del envase completo tal como se cotizó (antes del descuento).                                                                                                                                                    |
| `currency`            | `text`                     | no   | Moneda. Solo ARS: nunca se convierte sin una cotización cargada.                                                                                                                                                        |
| `document_type`       | `costing.price_document`   | no   | Factura con IVA discriminado, o "precio ingresado" sin factura.                                                                                                                                                         |
| `vat_rate`            | `numeric(5,2)`             | sí   | Alícuota de IVA en %: 0, 10,5, 21 o 27. Solo con factura.                                                                                                                                                               |
| `price_includes_vat`  | `boolean`                  | no   | Si el precio cargado ya incluye el IVA. Sin factura no se usa.                                                                                                                                                          |
| `discount_amount`     | `numeric(18,4)`            | no   | Descuento por envase, en pesos.                                                                                                                                                                                         |
| `net_package_price`   | `numeric(18,4)`            | no   | Precio del envase sin IVA, con el descuento (lo calcula la base). Sin factura, igual al bruto.                                                                                                                          |
| `gross_package_price` | `numeric(18,4)`            | no   | Precio del envase con IVA, con el descuento (lo calcula la base).                                                                                                                                                       |
| `base_quantity`       | `numeric(18,6)`            | no   | Contenido del envase en la unidad de uso de la materia prima (g, ml o unidad) al registrar el precio. El costo por unidad sale de acá: cambiar el contenido del producto o una conversión no mueve un precio aprobado.  |
| `source`              | `costing.price_source`     | no   | De dónde viene: manual, valor de prueba, importación o factura.                                                                                                                                                         |
| `approval_request_id` | `uuid`                     | sí   | La solicitud que lo aprobó (la de Dirección, si hizo falta). Vacía solo en los valores de prueba.                                                                                                                       |
| `approved_by`         | `uuid`                     | sí   | Quién dio la última aprobación.                                                                                                                                                                                         |
| `approved_at`         | `timestamp with time zone` | sí   | Cuándo se aprobó.                                                                                                                                                                                                       |
| `notes`               | `text`                     | sí   | Observaciones.                                                                                                                                                                                                          |
| `created_at`          | `timestamp with time zone` | no   | Cuándo se registró (lo pone la base).                                                                                                                                                                                   |
| `created_by`          | `uuid`                     | sí   | Quién lo registró (lo pone la base).                                                                                                                                                                                    |
| `updated_at`          | `timestamp with time zone` | no   | Igual a la creación: un precio no se cambia.                                                                                                                                                                            |
| `updated_by`          | `uuid`                     | sí   | Igual a la creación: un precio no se cambia.                                                                                                                                                                            |
| `deleted_at`          | `timestamp with time zone` | sí   | Siempre vacía: un precio no se borra.                                                                                                                                                                                   |
| `deleted_by`          | `uuid`                     | sí   | Siempre vacía: un precio no se borra.                                                                                                                                                                                   |

## `costing.price_settings`

Configuración de precios de cada grupo. Sin fila, valen los valores por defecto (15 % y 30 días). La cambia solo Dirección General (prices.configure).

| Columna                  | Tipo                       | Nulo | Qué guarda                                                                                                                                                                                                        |
| ------------------------ | -------------------------- | ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                     | `uuid`                     | no   | Identificador.                                                                                                                                                                                                    |
| `group_id`               | `uuid`                     | no   | Grupo al que se aplica. Una fila por grupo.                                                                                                                                                                       |
| `approval_variation_pct` | `numeric(5,2)`             | no   | Si un precio sube o baja más que este porcentaje contra el costo que se usa hoy para esa materia prima en ese lugar (por unidad de uso, con o sin IVA), después del Controller aprueba también Dirección General. |
| `stale_days`             | `integer`                  | no   | Días desde la vigencia para marcar un precio como desactualizado (si su categoría no dice otro plazo).                                                                                                            |
| `created_at`             | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                                                                                                                 |
| `created_by`             | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                                                                                                                                                  |
| `updated_at`             | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).                                                                                                                                                                   |
| `updated_by`             | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                                                                                                                                                 |
| `deleted_at`             | `timestamp with time zone` | sí   | Baja lógica. Nunca se borra.                                                                                                                                                                                      |
| `deleted_by`             | `uuid`                     | sí   | Quién la dio de baja (lo pone la base).                                                                                                                                                                           |
| `lookback_days`          | `integer`                  | no   | Días hacia atrás contra los que también se compara un precio nuevo (subas en escalones). Vale la variación más grande entre la de hoy y la de hace estos días.                                                    |

## `costing.recipe_cost_current`

El costo vigente de cada receta en cada local. Dato derivado: lo escribe solo el motor y no pasa por la auditoría, para no llenarla en cada recálculo; la historia son las fotos (recipe_cost_snapshots).

| Columna              | Tipo                       | Nulo | Qué guarda                                                                                                                  |
| -------------------- | -------------------------- | ---- | --------------------------------------------------------------------------------------------------------------------------- |
| `id`                 | `uuid`                     | no   | Identificador.                                                                                                              |
| `group_id`           | `uuid`                     | no   | Grupo de la receta.                                                                                                         |
| `restaurant_id`      | `uuid`                     | no   | Local: una misma receta cuesta distinto en cada uno.                                                                        |
| `recipe_id`          | `uuid`                     | no   | Receta.                                                                                                                     |
| `recipe_version_id`  | `uuid`                     | no   | Versión publicada con la que se calculó.                                                                                    |
| `as_of`              | `date`                     | no   | Fecha de los precios que se usaron.                                                                                         |
| `total_cost`         | `numeric(18,4)`            | sí   | Costo total de la receta, sin el IVA recuperable. Vacío si falta un dato: nunca $ 0.                                        |
| `total_gross_cost`   | `numeric(18,4)`            | sí   | Costo total con IVA. Vacío si falta un dato.                                                                                |
| `cost_per_base_unit` | `numeric(20,8)`            | sí   | Costo por unidad base terminada (g, ml o unidad). Vacío si falta el rendimiento.                                            |
| `cost_per_portion`   | `numeric(18,4)`            | sí   | Costo por porción. Vacío si no hay porciones.                                                                               |
| `reliability`        | `costing.cost_reliability` | no   | Confiabilidad: gana la peor línea.                                                                                          |
| `currency`           | `text`                     | no   | Moneda. Solo ARS.                                                                                                           |
| `method_version`     | `integer`                  | no   | Versión del método de cálculo.                                                                                              |
| `created_at`         | `timestamp with time zone` | no   | Cuándo se calculó por primera vez (lo pone la base).                                                                        |
| `created_by`         | `uuid`                     | sí   | Vacío: lo escribe el proceso de la cola. Quién hizo el cambio está en la auditoría del precio, el rendimiento o la versión. |
| `updated_at`         | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).                                                                             |
| `updated_by`         | `uuid`                     | sí   | Vacío: lo escribe el proceso de la cola.                                                                                    |
| `deleted_at`         | `timestamp with time zone` | sí   | Baja lógica: el local dejó de usar la receta.                                                                               |
| `deleted_by`         | `uuid`                     | sí   | Vacío: lo da de baja el proceso de la cola.                                                                                 |

## `costing.recipe_cost_snapshot_lines`

Detalle de una foto: cada línea con lo que no tiene versión (cantidad, rendimiento, precio, contenido del envase, condición frente al IVA y versión de la subreceta). Solo de inserción. Quien ve costos lee el costo de la línea; el precio y su origen no se exponen por la API.

| Columna                 | Tipo                       | Nulo | Qué guarda                                                                             |
| ----------------------- | -------------------------- | ---- | -------------------------------------------------------------------------------------- |
| `id`                    | `uuid`                     | no   | Identificador.                                                                         |
| `group_id`              | `uuid`                     | no   | Grupo de la receta.                                                                    |
| `restaurant_id`         | `uuid`                     | no   | Local de la foto.                                                                      |
| `snapshot_id`           | `uuid`                     | no   | Foto a la que pertenece.                                                               |
| `recipe_version_id`     | `uuid`                     | no   | Versión de la foto. Una línea muestra la fórmula: la ve quien ve esa versión.          |
| `line_order`            | `integer`                  | no   | Orden de la línea en la fórmula.                                                       |
| `item`                  | `text`                     | no   | Nombre de la materia prima o la preparación en ese momento.                            |
| `ingredient_id`         | `uuid`                     | sí   | Materia prima, si la línea es una.                                                     |
| `sub_recipe_id`         | `uuid`                     | sí   | Preparación, si la línea es una. Puede ser la variante del local.                      |
| `sub_recipe_version_id` | `uuid`                     | sí   | Versión de la preparación que se usó.                                                  |
| `quantity`              | `numeric(18,6)`            | no   | Cantidad de la línea.                                                                  |
| `unit_id`               | `uuid`                     | no   | Unidad de la cantidad.                                                                 |
| `quantity_basis`        | `recipes.quantity_basis`   | no   | Cómo va la cantidad: como se compra, limpia, cocida o terminada.                       |
| `base_quantity`         | `numeric(18,6)`            | sí   | Cantidad en la unidad de uso.                                                          |
| `purchase_quantity`     | `numeric(18,6)`            | sí   | Cantidad a comprar, después del rendimiento.                                           |
| `yield_profile_id`      | `uuid`                     | sí   | Estándar de rendimiento aprobado que se usó.                                           |
| `cleaning_yield`        | `numeric(7,4)`             | sí   | Rendimiento de limpieza usado.                                                         |
| `cooking_factor`        | `numeric(7,4)`             | sí   | Factor de cocción usado.                                                               |
| `price_record_id`       | `uuid`                     | sí   | Precio que se usó.                                                                     |
| `price_level`           | `core.scope_type`          | sí   | De dónde vino el precio: local, marca o grupo.                                         |
| `package_base_quantity` | `numeric(18,6)`            | sí   | Contenido del envase de ese precio, en la unidad de uso.                               |
| `vat_condition`         | `org.vat_condition`        | sí   | Condición frente al IVA del local en ese momento.                                      |
| `unit_cost`             | `numeric(20,8)`            | sí   | Costo por unidad de uso, sin el IVA recuperable.                                       |
| `gross_unit_cost`       | `numeric(20,8)`            | sí   | Costo por unidad de uso, con IVA.                                                      |
| `line_cost`             | `numeric(18,4)`            | sí   | Costo de la línea, sin el IVA recuperable.                                             |
| `line_gross_cost`       | `numeric(18,4)`            | sí   | Costo de la línea, con IVA.                                                            |
| `share_pct`             | `numeric(7,2)`             | sí   | Participación de la línea en el costo total, en %.                                     |
| `line_status`           | `text`                     | no   | Estado: ok, o qué faltó (conversión, rendimiento, precio, razón social o preparación). |
| `created_at`            | `timestamp with time zone` | no   | Cuándo se sacó (lo pone la base).                                                      |
| `created_by`            | `uuid`                     | sí   | Vacío: la saca el proceso de la cola.                                                  |
| `updated_at`            | `timestamp with time zone` | no   | Igual a created_at: la línea no cambia.                                                |
| `updated_by`            | `uuid`                     | sí   | Igual a created_by: la línea no cambia.                                                |
| `deleted_at`            | `timestamp with time zone` | sí   | Siempre vacío: la línea no se da de baja.                                              |
| `deleted_by`            | `uuid`                     | sí   | Siempre vacío: la línea no se da de baja.                                              |

## `costing.recipe_cost_snapshots`

Foto histórica del costo de una receta en un local. Solo de inserción: se saca cada vez que el costo cambia, y una foto vieja nunca cambia. Es la historia del costo, por eso no pasa por la auditoría.

| Columna              | Tipo                           | Nulo | Qué guarda                                                                                                               |
| -------------------- | ------------------------------ | ---- | ------------------------------------------------------------------------------------------------------------------------ |
| `id`                 | `uuid`                         | no   | Identificador.                                                                                                           |
| `group_id`           | `uuid`                         | no   | Grupo de la receta.                                                                                                      |
| `restaurant_id`      | `uuid`                         | no   | Local.                                                                                                                   |
| `recipe_id`          | `uuid`                         | no   | Receta.                                                                                                                  |
| `recipe_version_id`  | `uuid`                         | no   | Versión con la que se calculó.                                                                                           |
| `as_of`              | `date`                         | no   | Fecha de los precios que se usaron.                                                                                      |
| `reason`             | `costing.cost_snapshot_reason` | no   | Por qué se sacó la foto.                                                                                                 |
| `total_cost`         | `numeric(18,4)`                | sí   | Costo total, sin el IVA recuperable. Vacío si faltaba un dato.                                                           |
| `total_gross_cost`   | `numeric(18,4)`                | sí   | Costo total con IVA. Vacío si faltaba un dato.                                                                           |
| `cost_per_base_unit` | `numeric(20,8)`                | sí   | Costo por unidad base terminada.                                                                                         |
| `cost_per_portion`   | `numeric(18,4)`                | sí   | Costo por porción.                                                                                                       |
| `reliability`        | `costing.cost_reliability`     | no   | Confiabilidad en ese momento.                                                                                            |
| `currency`           | `text`                         | no   | Moneda. Solo ARS.                                                                                                        |
| `method_version`     | `integer`                      | no   | Versión del método de cálculo.                                                                                           |
| `created_at`         | `timestamp with time zone`     | no   | Cuándo se sacó (lo pone la base).                                                                                        |
| `created_by`         | `uuid`                         | sí   | Vacío: la saca el proceso de la cola. Quién hizo el cambio está en la auditoría del precio, el rendimiento o la versión. |
| `updated_at`         | `timestamp with time zone`     | no   | Igual a created_at: la foto no cambia.                                                                                   |
| `updated_by`         | `uuid`                         | sí   | Igual a created_by: la foto no cambia.                                                                                   |
| `deleted_at`         | `timestamp with time zone`     | sí   | Siempre vacío: la foto no se da de baja.                                                                                 |
| `deleted_by`         | `uuid`                         | sí   | Siempre vacío: la foto no se da de baja.                                                                                 |
| `entry_number`       | `bigint`                       | no   | Orden de las fotos. Las de una misma tanda comparten la hora.                                                            |

## `imports.import_errors`

Errores y avisos de la validación, por fila, en español. Se descargan para corregir el Excel. Al volver a validar, los anteriores quedan dados de baja.

| Columna      | Tipo                       | Nulo | Qué guarda                                                |
| ------------ | -------------------------- | ---- | --------------------------------------------------------- |
| `id`         | `uuid`                     | no   | Identificador.                                            |
| `group_id`   | `uuid`                     | no   | Grupo.                                                    |
| `job_id`     | `uuid`                     | no   | Importación.                                              |
| `row_id`     | `uuid`                     | sí   | Fila intermedia, si el problema es de una fila.           |
| `sheet`      | `text`                     | sí   | Solapa del Excel.                                         |
| `row_number` | `integer`                  | sí   | Fila del Excel.                                           |
| `field`      | `text`                     | sí   | Columna o dato con problema.                              |
| `code`       | `text`                     | no   | Código del problema (por ejemplo, unknown_code).          |
| `severity`   | `imports.issue_severity`   | no   | Error (la fila no se importa) o aviso (se importa igual). |
| `message`    | `text`                     | no   | Qué pasa y qué hacer, en español.                         |
| `created_at` | `timestamp with time zone` | no   | Cuándo se detectó (lo pone la base).                      |
| `created_by` | `uuid`                     | sí   | Quién validó (lo pone la base).                           |
| `updated_at` | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).           |
| `updated_by` | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).         |
| `deleted_at` | `timestamp with time zone` | sí   | Baja al volver a validar.                                 |
| `deleted_by` | `uuid`                     | sí   | Quién lo dio de baja (lo pone la base).                   |

## `imports.import_jobs`

Cada archivo de Excel que se importa: de qué marca, con qué prefijo de códigos, su huella (para no importarlo dos veces) y en qué paso está.

| Columna                    | Tipo                       | Nulo | Qué guarda                                                                                                                                                            |
| -------------------------- | -------------------------- | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                       | `uuid`                     | no   | Identificador de la importación.                                                                                                                                      |
| `group_id`                 | `uuid`                     | no   | Grupo.                                                                                                                                                                |
| `brand_id`                 | `uuid`                     | no   | Marca a la que van las recetas importadas.                                                                                                                            |
| `kind`                     | `text`                     | no   | Tipo de archivo: recipe_book (el recetario de Excel de un restaurante).                                                                                               |
| `code_prefix`              | `text`                     | no   | Prefijo de la marca para los códigos del Excel (NON → NON-190000). Es siempre el mismo para la marca.                                                                 |
| `file_name`                | `text`                     | no   | Nombre del archivo que se subió.                                                                                                                                      |
| `storage_path`             | `text`                     | no   | Dónde está el archivo en el bucket imports: <grupo>/<marca>/<archivo>.xlsx.                                                                                           |
| `file_sha256`              | `text`                     | no   | Huella SHA-256 del contenido, calculada por el servidor al leerlo: el mismo archivo no se importa dos veces.                                                          |
| `status`                   | `imports.job_status`       | no   | Paso en el que está la importación.                                                                                                                                   |
| `ingredients_confirmed_by` | `uuid`                     | sí   | Quién confirmó las materias primas nuevas (Compras).                                                                                                                  |
| `ingredients_confirmed_at` | `timestamp with time zone` | sí   | Cuándo se confirmaron las materias primas.                                                                                                                            |
| `confirmed_by`             | `uuid`                     | sí   | Quién confirmó las recetas.                                                                                                                                           |
| `confirmed_at`             | `timestamp with time zone` | sí   | Cuándo se confirmaron las recetas.                                                                                                                                    |
| `created_at`               | `timestamp with time zone` | no   | Cuándo se subió (lo pone la base).                                                                                                                                    |
| `created_by`               | `uuid`                     | sí   | Quién la subió (lo pone la base).                                                                                                                                     |
| `updated_at`               | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).                                                                                                                       |
| `updated_by`               | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                                                                                                     |
| `deleted_at`               | `timestamp with time zone` | sí   | Borrado lógico.                                                                                                                                                       |
| `deleted_by`               | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                                                                                                     |
| `expected_rows`            | `integer`                  | sí   | Cuántas filas leyó el servidor en el archivo. Para validar tienen que estar todas cargadas (una carga cortada no se confirma). Vacío en las importaciones anteriores. |

## `imports.import_prices`

Precios de compra que trae el Excel, por materia prima. Son valores de prueba, sin factura: pasan a la tabla de precios en la etapa 2.1 C. Los ve solo quien tiene prices.view.

| Columna        | Tipo                       | Nulo | Qué guarda                                              |
| -------------- | -------------------------- | ---- | ------------------------------------------------------- |
| `id`           | `uuid`                     | no   | Identificador.                                          |
| `group_id`     | `uuid`                     | no   | Grupo.                                                  |
| `job_id`       | `uuid`                     | no   | Importación.                                            |
| `row_id`       | `uuid`                     | no   | Fila de la materia prima.                               |
| `price`        | `numeric(18,4)`            | sí   | Precio de la presentación, tal como estaba en el Excel. |
| `price_per_kg` | `numeric(20,8)`            | sí   | Precio por kilo o litro que calculaba el Excel.         |
| `currency`     | `text`                     | no   | Moneda (ISO 4217).                                      |
| `created_at`   | `timestamp with time zone` | no   | Cuándo se cargó (lo pone la base).                      |
| `created_by`   | `uuid`                     | sí   | Quién lo cargó (lo pone la base).                       |
| `updated_at`   | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).         |
| `updated_by`   | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).       |
| `deleted_at`   | `timestamp with time zone` | sí   | Borrado lógico.                                         |
| `deleted_by`   | `uuid`                     | sí   | Quién lo borró (lo pone la base).                       |

## `imports.import_staging_rows`

Filas del Excel tal como se leyeron (raw) y ya interpretadas (parsed), sin precios, con qué pasa con cada una al confirmar. No tocan lo oficial hasta confirmar.

| Columna             | Tipo                       | Nulo | Qué guarda                                                                                                                              |
| ------------------- | -------------------------- | ---- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                | `uuid`                     | no   | Identificador de la fila.                                                                                                               |
| `group_id`          | `uuid`                     | no   | Grupo.                                                                                                                                  |
| `job_id`            | `uuid`                     | no   | Importación a la que pertenece.                                                                                                         |
| `sheet`             | `text`                     | no   | Solapa del Excel.                                                                                                                       |
| `row_number`        | `integer`                  | no   | Número de fila en la solapa (para encontrarla y corregirla).                                                                            |
| `kind`              | `imports.row_kind`         | no   | Materia prima, preparación, plato o línea de una receta.                                                                                |
| `source_code`       | `text`                     | sí   | Código en el Excel (sin prefijo). En una línea, el código del componente.                                                               |
| `parent_code`       | `text`                     | sí   | En una línea: el código de la receta a la que pertenece.                                                                                |
| `parent_row`        | `integer`                  | sí   | En una línea: la fila de su receta en la misma solapa (ata la línea a su bloque).                                                       |
| `raw`               | `jsonb`                    | no   | Las celdas tal como estaban en el Excel, sin las de precio.                                                                             |
| `parsed`            | `jsonb`                    | no   | Lo interpretado, sin precios: nombre, rubro, rinde, porciones, peso por porción, gramos, medida casera, presentación, peso neto, merma. |
| `action`            | `imports.row_action`       | sí   | Qué pasa al confirmar (la calcula la validación).                                                                                       |
| `ingredient_id`     | `uuid`                     | sí   | Materia prima: la existente que se reutiliza, o la creada al confirmar.                                                                 |
| `recipe_id`         | `uuid`                     | sí   | Receta: la existente que se omite, o la creada al confirmar.                                                                            |
| `recipe_version_id` | `uuid`                     | sí   | Línea: la versión en la que quedó, después de confirmar.                                                                                |
| `level`             | `integer`                  | sí   | En las recetas: niveles de preparaciones que tiene debajo (para crearlas en orden).                                                     |
| `created_at`        | `timestamp with time zone` | no   | Cuándo se cargó (lo pone la base).                                                                                                      |
| `created_by`        | `uuid`                     | sí   | Quién la cargó (lo pone la base).                                                                                                       |
| `updated_at`        | `timestamp with time zone` | no   | Cuándo cambió por última vez (lo pone la base).                                                                                         |
| `updated_by`        | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                                                                       |
| `deleted_at`        | `timestamp with time zone` | sí   | Borrado lógico.                                                                                                                         |
| `deleted_by`        | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                                                                       |

## `recipes.component_base_quantities`

Cantidad de cada línea en la unidad de uso, congelada al publicar la versión: una conversión nueva no mueve una receta publicada. Solo de inserción. No es un dato económico. Solo la lee el motor de costos.

| Columna               | Tipo                       | Nulo | Qué guarda                                                                                           |
| --------------------- | -------------------------- | ---- | ---------------------------------------------------------------------------------------------------- |
| `id`                  | `uuid`                     | no   | Identificador.                                                                                       |
| `group_id`            | `uuid`                     | no   | Grupo de la receta.                                                                                  |
| `recipe_version_id`   | `uuid`                     | no   | Versión publicada.                                                                                   |
| `recipe_component_id` | `uuid`                     | no   | Línea de la fórmula. Una sola cantidad por línea.                                                    |
| `base_quantity`       | `numeric(18,6)`            | no   | Cantidad de la línea en la unidad de uso de la materia prima, o en la unidad base de la preparación. |
| `base_unit_id`        | `uuid`                     | no   | Unidad de esa cantidad (g, ml o unidad).                                                             |
| `created_at`          | `timestamp with time zone` | no   | Cuándo se congeló (lo pone la base).                                                                 |
| `created_by`          | `uuid`                     | sí   | Quién publicó (lo pone la base).                                                                     |
| `updated_at`          | `timestamp with time zone` | no   | Igual a created_at: la fila no cambia.                                                               |
| `updated_by`          | `uuid`                     | sí   | Igual a created_by: la fila no cambia.                                                               |
| `deleted_at`          | `timestamp with time zone` | sí   | Siempre vacío: la fila no se da de baja.                                                             |
| `deleted_by`          | `uuid`                     | sí   | Siempre vacío: la fila no se da de baja.                                                             |

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

Líneas de una versión de receta: una materia prima o una preparación (subreceta), con su cantidad. Solo cambian en un borrador; nada se borra: se da de baja.

| Columna             | Tipo                       | Nulo | Qué guarda                                                                                                                |
| ------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------- |
| `id`                | `uuid`                     | no   | Identificador de la línea.                                                                                                |
| `group_id`          | `uuid`                     | no   | Grupo de la receta.                                                                                                       |
| `brand_id`          | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance.                                               |
| `restaurant_id`     | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                                                                 |
| `recipe_version_id` | `uuid`                     | no   | Versión a la que pertenece.                                                                                               |
| `line_order`        | `integer`                  | no   | Orden de la línea en la receta.                                                                                           |
| `ingredient_id`     | `uuid`                     | sí   | Materia prima, si la línea es una materia prima.                                                                          |
| `quantity`          | `numeric(18,6)`            | no   | Cantidad, en unit_id.                                                                                                     |
| `unit_id`           | `uuid`                     | no   | Unidad de la cantidad. Tiene que poder pasarse a la unidad de la materia prima, o a la del rendimiento de la preparación. |
| `quantity_basis`    | `recipes.quantity_basis`   | no   | Qué representa la cantidad: peso de compra, limpio o cocido (materia prima), o cantidad terminada (preparación).          |
| `yield_profile_id`  | `uuid`                     | sí   | Rendimiento estándar a aplicar (de esta materia prima), si corresponde.                                                   |
| `no_scale`          | `boolean`                  | no   | Si la línea no se escala (terminaciones, redondeos): se ajusta a mano.                                                    |
| `notes`             | `text`                     | sí   | Observaciones de la línea.                                                                                                |
| `created_at`        | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                         |
| `created_by`        | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                                                          |
| `updated_at`        | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                        |
| `updated_by`        | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                                                         |
| `deleted_at`        | `timestamp with time zone` | sí   | Borrado lógico: al guardar las líneas de un borrador, las anteriores quedan borradas.                                     |
| `deleted_by`        | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                                                         |
| `sub_recipe_id`     | `uuid`                     | sí   | Subreceta (una preparación), si la línea es una receta. Se usa siempre su versión vigente.                                |

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

| Columna                      | Tipo                       | Nulo | Qué guarda                                                                                                         |
| ---------------------------- | -------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------ |
| `id`                         | `uuid`                     | no   | Identificador del paso.                                                                                            |
| `group_id`                   | `uuid`                     | no   | Grupo de la receta.                                                                                                |
| `brand_id`                   | `uuid`                     | sí   | Marca de la receta (la copia la base): sirve para la auditoría por alcance.                                        |
| `restaurant_id`              | `uuid`                     | sí   | Local de la receta, si es de un local (lo copia la base).                                                          |
| `recipe_version_id`          | `uuid`                     | no   | Versión a la que pertenece.                                                                                        |
| `step_number`                | `integer`                  | no   | Número del paso (1, 2, 3…).                                                                                        |
| `kind`                       | `recipes.step_kind`        | no   | Tipo de paso: preparación, cocción, reposo, fermentación, enfriamiento, regeneración, emplatado u otro.            |
| `instructions`               | `text`                     | no   | Qué se hace en el paso.                                                                                            |
| `active_minutes`             | `integer`                  | no   | Minutos con una persona trabajando.                                                                                |
| `passive_minutes`            | `integer`                  | no   | Minutos de espera (cocción, reposo, fermentación) sin una persona encima.                                          |
| `workers`                    | `smallint`                 | sí   | Cuántas personas hacen falta.                                                                                      |
| `sector`                     | `text`                     | sí   | Sector de la cocina.                                                                                               |
| `equipment`                  | `text`                     | sí   | Equipo que se usa.                                                                                                 |
| `control_point`              | `text`                     | sí   | Punto de control o criterio de calidad del paso.                                                                   |
| `created_at`                 | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                                  |
| `created_by`                 | `uuid`                     | sí   | Quién lo creó (lo pone la base).                                                                                   |
| `updated_at`                 | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                                 |
| `updated_by`                 | `uuid`                     | sí   | Quién lo cambió por última vez (lo pone la base).                                                                  |
| `deleted_at`                 | `timestamp with time zone` | sí   | Borrado lógico: al guardar los pasos de un borrador, los anteriores quedan borrados.                               |
| `deleted_by`                 | `uuid`                     | sí   | Quién lo borró (lo pone la base).                                                                                  |
| `equipment_capacity`         | `numeric(18,6)`            | sí   | Cuánto entra en el equipo de este paso. Si el lote lo supera, hacen falta más tandas.                              |
| `equipment_capacity_unit_id` | `uuid`                     | sí   | Unidad de la capacidad: la del rendimiento al cargarla. Va guardada porque el rendimiento puede cambiar de unidad. |

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

| Columna                | Tipo                       | Nulo | Qué guarda                                                                                                      |
| ---------------------- | -------------------------- | ---- | --------------------------------------------------------------------------------------------------------------- |
| `id`                   | `uuid`                     | no   | Identificador de la receta.                                                                                     |
| `group_id`             | `uuid`                     | no   | Grupo de la receta.                                                                                             |
| `brand_id`             | `uuid`                     | sí   | Marca, si la receta es de marca o de local. Vacío en una maestra del grupo.                                     |
| `restaurant_id`        | `uuid`                     | sí   | Local, si la receta es de un local. Vacío si es de marca o del grupo.                                           |
| `scope_type`           | `recipes.recipe_scope`     | no   | Alcance: maestra del grupo, de marca o de local.                                                                |
| `code`                 | `text`                     | no   | Código de la receta. Único en el grupo y no cambia nunca: sirve para importar sin duplicar.                     |
| `name`                 | `text`                     | no   | Nombre de la receta.                                                                                            |
| `short_name`           | `text`                     | sí   | Nombre corto para la cocina y las comandas.                                                                     |
| `recipe_type`          | `recipes.recipe_type`      | no   | Tipo: preparación, plato terminado o componente unitario.                                                       |
| `category_id`          | `uuid`                     | sí   | Categoría o subcategoría de la receta.                                                                          |
| `sector`               | `text`                     | sí   | Sector de la cocina donde se prepara (por ejemplo, caliente o pastelería).                                      |
| `station`              | `text`                     | sí   | Partida o estación (por ejemplo, plancha o pastas).                                                             |
| `technical_owner_id`   | `uuid`                     | sí   | Responsable técnico de la receta.                                                                               |
| `is_active`            | `boolean`                  | no   | Si la receta se usa. Una receta archivada conserva toda su historia.                                            |
| `created_at`           | `timestamp with time zone` | no   | Cuándo se creó (lo pone la base).                                                                               |
| `created_by`           | `uuid`                     | sí   | Quién la creó (lo pone la base).                                                                                |
| `updated_at`           | `timestamp with time zone` | no   | Cuándo se cambió por última vez (lo pone la base).                                                              |
| `updated_by`           | `uuid`                     | sí   | Quién la cambió por última vez (lo pone la base).                                                               |
| `deleted_at`           | `timestamp with time zone` | sí   | Borrado lógico. Vacío si está vigente.                                                                          |
| `deleted_by`           | `uuid`                     | sí   | Quién la borró (lo pone la base).                                                                               |
| `variant_of_recipe_id` | `uuid`                     | sí   | Receta maestra de la que sale, si es una variante local. Las diferencias contra la maestra se muestran siempre. |

## Tipos

| Tipo                             | Valores                                                                                                                     | Qué significa                                                                                                                                                                                                             |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `catalog.allergen_status`        | `contains`, `may_contain`, `free_verified`                                                                                  | Estado de un alérgeno en un ingrediente: contains (contiene), may_contain (puede contener, trazas) o free_verified (no contiene, verificado). Sin fila = sin dato: nunca se toma como "sin alérgenos".                    |
| `catalog.conversion_kind`        | `density`, `unit_weight`                                                                                                    | Conversión propia de un ingrediente: density (gramos por mililitro) o unit_weight (gramos por unidad: 1 huevo, 1 atado).                                                                                                  |
| `catalog.data_source`            | `manual`, `excel_import`, `measured`, `supplier`, `calculated`, `estimated`, `verified`                                     | Fuente de un dato (sección 6): manual, importado de Excel, medido en ensayo, informado por proveedor, calculado por el sistema, estimado o verificado por un responsable.                                                 |
| `catalog.dimension`              | `mass`, `volume`, `count`, `package`                                                                                        | Dimensión de una unidad: mass (masa, base g), volume (volumen, base ml), count (conteo, base unidad) o package (envase sin contenido fijo: caja, bolsa, horma).                                                           |
| `catalog.yield_status`           | `draft`, `approved`, `superseded`                                                                                           | Estado de un perfil de rendimiento: draft (propuesto, esperando aprobación), approved (el estándar vigente) o superseded (reemplazado por otro aprobado).                                                                 |
| `costing.cost_reliability`       | `verified`, `estimated`, `stale`, `incomplete`                                                                              | Confiabilidad de un costo; gana la peor línea: verified (completo y verificado), estimated (con estimaciones: algún precio heredado), stale (desactualizado: algún precio vencido) e incomplete (falta un dato).          |
| `costing.cost_snapshot_reason`   | `publish`, `price_change`, `yield_change`, `assignment`, `legal_entity_change`, `restaurant_reopened`, `daily`, `month_end` | Por qué se sacó una foto de costo: se publicó una versión, se aprobó un precio o un rendimiento, se asignó la receta a un local, cambió la razón social, se reabrió el local, la actualización diaria o el cierre de mes. |
| `costing.price_document`         | `invoice`, `no_invoice`                                                                                                     | Comprobante del precio: factura con IVA discriminado, o "precio ingresado" sin factura (el precio es el final y no da crédito fiscal).                                                                                    |
| `costing.price_source`           | `manual`, `test_value`, `excel_import`, `invoice`                                                                           | De dónde viene un precio: carga manual, valor de prueba (simbólico, mientras no lleguen las facturas), importación de Excel o factura (reservado para la Fase 5).                                                         |
| `costing.scenario_override_kind` | `price`, `yield`, `quantity`                                                                                                | Qué cambia un escenario: el precio de una materia prima (también si se simula otro proveedor), su rendimiento, o el gramaje de una línea.                                                                                 |
| `costing.scenario_status`        | `active`, `archived`                                                                                                        | Estado de un escenario: activo o archivado. Nada se borra.                                                                                                                                                                |
| `imports.issue_severity`         | `error`, `warning`                                                                                                          | Un error frena la fila; un aviso no (por ejemplo, una receta sin componentes).                                                                                                                                            |
| `imports.job_status`             | `uploaded`, `staged`, `validated`, `ingredients_confirmed`, `confirmed`, `cancelled`                                        | Estado de una importación: subida, filas cargadas, validada, materias primas confirmadas (por Compras), confirmada (recetas creadas) o cancelada.                                                                         |
| `imports.row_action`             | `create`, `reuse`, `skip`, `error`                                                                                          | Qué pasa con una fila al confirmar: se crea, se reutiliza lo que ya existe, se omite (ya existe y no se pisa) o tiene un error.                                                                                           |
| `imports.row_kind`               | `ingredient`, `preparation`, `dish`, `line`                                                                                 | Qué es una fila del Excel: materia prima, preparación (pre-elaborado), plato o línea de una receta.                                                                                                                       |
| `recipes.media_kind`             | `final_product`, `plating`, `raw_material`, `step`, `critical_point`, `correct_example`, `incorrect_example`                | Tipo de foto: producto final, emplatado, materia prima, paso, punto crítico, ejemplo correcto o ejemplo incorrecto.                                                                                                       |
| `recipes.quantity_basis`         | `purchase`, `clean`, `cooked`, `finished`                                                                                   | Qué representa la cantidad de una línea: peso de compra (purchase), limpio (clean) o cocido (cooked) de una materia prima, o cantidad terminada (finished) de una subreceta.                                              |
| `recipes.recipe_scope`           | `group`, `brand`, `restaurant`                                                                                              | Alcance de una receta: maestra del grupo, de marca o de local. Una variante es una receta de local con su maestra (variant_of_recipe_id). La cocina central no se usa: Pariggi es un proveedor externo (ADR-0025).        |
| `recipes.recipe_type`            | `preparation`, `dish`, `unit_component`                                                                                     | Tipo de receta: preparation (salsa, masa, caldo), dish (plato terminado, por porción) o unit_component (medallón, bollo, empanada armada).                                                                                |
| `recipes.step_kind`              | `preparation`, `cooking`, `resting`, `fermentation`, `cooling`, `regeneration`, `plating`, `other`                          | Tipo de paso: preparación, cocción, reposo, fermentación, enfriamiento, regeneración, emplatado u otro.                                                                                                                   |
