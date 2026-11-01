# ADR-0027 — Importar el recetario de Excel (etapa 2.4)

- **Fecha:** 2026-10-31
- **Estado:** aceptada por Joaco (plan de la sesión aprobado).
- **Base:** pedido de Soy (ADR-0026, pregunta 11), plan de la Fase 2 (§3 `imports`, §6 etapa 2.4) y análisis del recetario de Casa Nonnos.

## Contexto

- **Soy quiere cargar el recetario actual de cada restaurante desde su Excel.** Primero el de Casa Nonnos, después los de Ragú Bodegón y Trattoria Padella, que tienen el mismo formato. De ahí en adelante, todo se carga por pantallas.
- **El Excel de Nonnos**, analizado sin copiarlo al repositorio:
  - **INSUMOS:** 294 filas con nombre, cada una con código por rubro, presentación, precio y peso neto. Incluye 133 del rubro "Plato finalizado", que son los platos de la carta.
  - **pre-elaborado:** 65 bloques de subrecetas, hasta 3 niveles y sin ciclos.
  - **PLATOS:** 66 bloques de platos; la mitad de sus líneas usa un pre-elaborado.
  - **Problemas que trae:** 166 insumos sin precio, ninguno con proveedor ni marca, la "medida" escrita a mano de 33 formas distintas, recetas vacías y fórmulas rotas (`#VALUE!`, `#N/A`).
- **Compuerta 2.4:** "el recetario actual se importa sin duplicados". La validan Joaco y el Chef.

## Decisiones de Joaco (2026-10-31)

1. **Precios del Excel:** se importan como valores de prueba. Quedan guardados aparte (`imports.import_prices`, ver decisión 7), con su importación y su archivo, y pasan a la tabla de precios cuando exista (2.1 C) como "precio del Excel, sin factura". Nunca van en `raw` ni en `parsed`: las dos columnas aceptan solo una lista cerrada de datos. No se construye un modelo de precios a medias.
2. **"Plato finalizado"** son los platos terminados de la carta (pizza, bruschetta). Los que tienen receta en PLATOS entran con sus líneas; los que no, como plato sin componentes, para completar.
3. **Códigos:** se conservan, con el prefijo de la marca (`NON-190000`). El Chef los reconoce y sirven para volver a importar sin duplicar.
4. **Mismo formato para las tres marcas:** un solo importador.
5. **Se lee con ExcelJS en el servidor** (PR 2). Es una dependencia nueva y está justificada abajo.
6. **Confirmación en dos pasos:**
   - **Compras** confirma las materias primas nuevas, porque el catálogo es suyo (`catalog.manage`);
   - después **el Chef o el Director** confirma las recetas (`imports.approve` y `recipes.draft` en la marca);
   - nadie confirma solo todo lo que no le corresponde.
7. **Precios:** van aparte (`import_prices`) y los ve solo quien tiene `prices.view`. El Chef importa sin ver precios y no puede bajar el Excel subido, porque tiene precios.
8. **Carga de las filas:** la hace el servidor con la sesión de quien importa. Alguien con `imports.run` podría cargar filas inventadas por la API. **Se acepta el riesgo:**
   - es lo mismo que podría cargar a mano en las pantallas;
   - las filas pasan por la vista previa y las confirman Compras y la cocina;
   - cada receta pasa la revisión normal;
   - la vista previa muestra quién subió el archivo;
   - el servidor calcula la huella del contenido.

## Regla que manda: nunca datos reales en desarrollo

- El importador se construye y se prueba con **un Excel ficticio del mismo formato**, generado por un script del repositorio.
- **El Excel real de Nonnos se carga en producción**, desde la pantalla, por quien tenga permiso. Desde Claude Code nunca se toca producción.
- El archivo real queda fuera del repositorio (`recetarios/`, al lado del proyecto).

## Cómo quedó (PR 1, base)

- **Migración** `20261106120000_imports.sql`. El esquema `imports` se expone por la API y entra en los tipos y el diccionario.
- **Bucket privado `imports`:**
  - solo `.xlsx` y hasta 15 MB;
  - la ruta es `<grupo>/<marca>/<archivo>.xlsx`;
  - sube quien tiene `imports.run` en la marca;
  - baja el archivo solo quien tiene `prices.view` en el grupo, porque trae precios. El servidor lo lee en el momento de subirlo, así que quien importa no necesita bajarlo;
  - sin update ni delete.
- **Tablas** (con RLS, auditoría, columnas de control y rechazo de truncate):
  - `import_jobs`: el archivo, la marca, el prefijo, la huella SHA-256 (única por grupo, salvo las canceladas) y el paso. Los pasos son subida → filas cargadas → validada → materias primas confirmadas → confirmada, o cancelada;
  - `import_staging_rows`: cada fila tal como se leyó (`raw`, sin las celdas de precio) e interpretada (`parsed`). Lleva:
    - su acción: crear, reutilizar, omitir o error;
    - la fila de su receta (`parent_row`), que ata cada línea a su bloque;
    - claves foráneas a lo que reutiliza o crea (`ingredient_id`, `recipe_id`, `recipe_version_id`);
    - topes de tamaño;
  - `import_prices`: los precios del Excel, con su propia política;
  - `import_errors`: errores y avisos por fila, en español. Al volver a validar, los anteriores se dan de baja.
  - **Sin `import_column_mappings`:** el formato es fijo. Se suma si llega uno distinto.
- **Quién ve una importación:** `imports.run` o `imports.approve` en su marca, o `catalog.manage` en el grupo, para que Compras confirme. Se calcula con `imports.visible_job_ids()`, un conjunto que se arma una vez por consulta.
- **Funciones** (devuelven `{"result": …}`; un rechazo pasa por `core.deny`; el origen de la auditoría es `import`):
  - **`create_job`:** rechaza el mismo archivo dos veces (caso 8) y un archivo que no está en el bucket.
  - **`stage_rows`:** carga lotes de hasta 500 filas.
  - **`validate_job`:** calcula todo por conjuntos, sin tocar nada oficial. Se puede repetir. Controla:
    - códigos y nombres, y repetidos dentro del archivo;
    - un código que es a la vez materia prima y receta;
    - materias primas existentes, por código o por nombre normalizado: se reutilizan;
    - recetas existentes por código, solo del grupo o de la marca: se omiten y no se pisan. Si el código lo tiene otra marca, un local, una variante o una receta archivada, es error, sin mostrar de quién es;
    - componentes existentes con las reglas del recetario: al alcance de la marca, preparación con versión vigente, materia prima activa y que pueda pasarse a gramos;
    - líneas sin receta, sin código, que se usan a sí mismas, con gramos en cero o con un código desconocido;
    - círculos entre preparaciones y más de 10 niveles;
    - el error se contagia: la línea que usa una materia prima o una preparación con error, y la receta con una línea con error, tampoco se crean;
    - un bloque repetido de una receta se omite junto con sus líneas;
    - un nombre repetido con otro código es error, porque el catálogo no admite dos nombres iguales;
    - las líneas de una receta que no se crea se omiten.
    - **Aviso, no error:** una receta sin componentes.
  - **`confirm_ingredients`** (Compras): crea los rubros que falten como categorías y las materias primas, con unidad de receta en gramos.
  - **`confirm_recipes`** (cocina): crea las recetas de la marca en versión 1, en borrador, en orden de nivel (preparaciones primero).
    - **Rendimiento:** el pre-elaborado rinde su peso neto en g; el plato, sus porciones y el peso por porción.
    - **Líneas:** todas en gramos. La materia prima va en peso de compra y el pre-elaborado en cantidad terminada.
    - **La medida casera** ("CUP 250", "2 FETAS") va como observación de la línea.
    - **Usa el bloqueo del árbol de preparaciones** (`recipes.lock_sub_graph`).
  - **Cada confirmación vuelve a comprobar, con bloqueo, que nada haya cambiado** desde la validación: códigos libres, lo reutilizado vigente y los componentes. Si algo cambió, pide volver a validar con un mensaje claro. Con las materias primas ya confirmadas, se pueden revalidar las recetas.
  - **`cancel_job`:** pide `imports.run`. Lo ya confirmado queda, y el mismo archivo se puede volver a subir.
  - **Prefijos:** un prefijo es de una sola marca, y cada marca usa siempre el mismo. Si no, el caso 8 se rompería con otro código.
  - **`job_summary`:** totales por tipo y acción, contados en la base.
- **Las recetas importadas no tienen pasos.** La base exige uno para pedir la revisión, así que el Chef los completa. Además, un plato cuyo pre-elaborado todavía está en borrador no pasa la revisión hasta que se publique el pre-elaborado. Es el orden natural: primero las salsas, después los platos.

## Pruebas

- **`200_imports.test.sql` (47):**
  - estructura, bucket, permisos y RLS por rol;
  - caso 8: el mismo archivo y los mismos códigos, sin duplicados;
  - validar no toca lo oficial;
  - cada error con su motivo;
  - los dos pasos con sus permisos y el rechazo registrado;
  - qué se crea, con sus líneas, rendimientos y medida casera;
  - auditoría con origen y motivo;
  - cancelar y volver a subir.
- **`201_imports_rules.test.sql` (46):** un caso por cada hallazgo de las revisiones:
  - componentes rotos, nombres y bloques repetidos;
  - recetas de otra marca, de un local o sin publicar;
  - unidades;
  - lo que cambia entre validar y confirmar;
  - prefijos;
  - quién ve filas, errores, precios y el archivo;
  - auditoría de las filas.
- **`205_imports_performance.test.sql`:** un recetario del tamaño del de Nonnos (300 materias primas, 130 recetas, unas 700 líneas).
  - **Medido el 2026-10-31:** cargar 1,4 s, validar 4,9 s, confirmar materias primas 1 s, confirmar recetas 5,2 s.
  - Con auditoría completa. Sin auditoría, cada paso tarda la mitad; no se quita.
  - Validar tardaba 8 s fila por fila; se reescribió por conjuntos.
- **`050`:** el esquema `imports` entra en los controles de quién ejecuta y quién lee.

## Revisiones (PR 1)

- **`db-reviewer`:** 2 graves, reproducidos, y 6 medios. Todos resueltos:
  - **G1:** una línea con un componente roto pasaba la validación y después trababa la confirmación.
  - **G2:** dos nombres iguales con distinto código hacían fallar la confirmación de Compras.
  - **Medios:**
    - bloques repetidos que se mezclaban;
    - cambios entre validar y confirmar;
    - lo existente sin mirar si está activo ni su alcance;
    - unidades;
    - claves foráneas;
    - pruebas.
  - **Menores:** la mayoría resueltos (topes, mensajes, bloqueo después del permiso, rubros largos, más de 200 líneas).
- **`security-auditor`:** 1 grave, reproducido, y resuelto.
  - **El grave:** una marca podía meter en sus recetas una receta de otra marca y trabarla. Ahora la importación aplica las reglas de alcance del recetario.
  - **Medios:**
    - precios aparte con su permiso (decisión 7);
    - carga de filas, con el riesgo aceptado (decisión 8).
  - **Menores resueltos:**
    - la cancelación pide `imports.run`;
    - `file_brand_id` no confirma marcas ajenas;
    - el bloqueo va después del permiso.
- **Error encontrado por las pruebas:** en la política de lectura del bucket, `name` se resolvía como el nombre de la marca y no el del archivo, así que nadie veía nada. Ahora usa `imports.file_group_id(name)`.
- **Segunda pasada:**
  - **`security-auditor`: apto.** Cerró el grave. Su único medio también quedó resuelto: `raw` acepta solo una lista cerrada de celdas con valores simples, así que un precio no se cuela con otro nombre ni anidado.
  - **`db-reviewer`:** cerró todos los hallazgos de la primera pasada. Encontró 1 grave nuevo y 2 medios, resueltos y con prueba en la `201`:
    - **El grave:** el nombre de una materia prima dada de baja trababa la confirmación. Ahora es un error en la vista previa.
    - **Medio:** una materia prima dada de baja entre los dos pasos trababa las recetas. Ahora la revalidación la marca y el error se contagia.
    - **Medio:** el contagio de errores tenía un tope de 12 vueltas. Ahora corre hasta que no cambia nada.
- **Para el PR 2:**
  - escapar las celdas del CSV de errores que empiezan con `= + - @`;
  - tratar el `.xlsx` como no confiable: tope de tamaño y de filas al leerlo, y validar el contenido, no solo el tipo que declara el navegador.

## Por qué ExcelJS (PR 2)

- **Para qué:** leer un `.xlsx` necesita una librería. Un `.xlsx` es un zip con XML, con fórmulas, valores calculados y textos compartidos.
- **Opciones:**
  - **ExcelJS:** licencia MIT, muy usada y mantenida;
  - **SheetJS:** la versión de npm quedó vieja y con avisos de seguridad; las nuevas solo se bajan de su sitio;
  - **un lector propio:** código nuestro que hay que mantener y que solo entiende lo básico.
- **Elegida: ExcelJS, solo en el servidor** y con versión fija. El navegador no la carga y no decide nada.

## Riesgos

- **El Excel real puede traer casos que el ficticio no tiene.** El lector informa toda fila que no entiende como error, nunca la adivina, y la vista previa no toca nada oficial.
- **Materias primas parecidas entre marcas:** solo se reutiliza con el nombre exacto normalizado. Unir las parecidas queda para una pantalla de "unificar".
- **Medidas caseras sin conversión:** se importan los gramos, que el Excel siempre trae, y la medida queda como nota.
- **La merma de los insumos** (20 con desperdicio) no se convierte en rendimiento estándar, porque eso necesita aprobación (2.1 B). Queda guardada en la fila.
