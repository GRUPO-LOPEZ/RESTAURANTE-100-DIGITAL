# Diccionario de datos — catalog

> Generado desde los `comment on` de la base local el 2026-10-29 con `npm run db:dictionary`. No editar a mano: regenerar después de cada migración.

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

## Tipos

| Tipo                      | Valores                                                                                 | Qué significa                                                                                                                                                                                          |
| ------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `catalog.allergen_status` | `contains`, `may_contain`, `free_verified`                                              | Estado de un alérgeno en un ingrediente: contains (contiene), may_contain (puede contener, trazas) o free_verified (no contiene, verificado). Sin fila = sin dato: nunca se toma como "sin alérgenos". |
| `catalog.conversion_kind` | `density`, `unit_weight`                                                                | Conversión propia de un ingrediente: density (gramos por mililitro) o unit_weight (gramos por unidad: 1 huevo, 1 atado).                                                                               |
| `catalog.data_source`     | `manual`, `excel_import`, `measured`, `supplier`, `calculated`, `estimated`, `verified` | Fuente de un dato (sección 6): manual, importado de Excel, medido en ensayo, informado por proveedor, calculado por el sistema, estimado o verificado por un responsable.                              |
| `catalog.dimension`       | `mass`, `volume`, `count`, `package`                                                    | Dimensión de una unidad: mass (masa, base g), volume (volumen, base ml), count (conteo, base unidad) o package (envase sin contenido fijo: caja, bolsa, horma).                                        |
