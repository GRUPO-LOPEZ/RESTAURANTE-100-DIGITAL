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

## Cómo quedó (PR 2, lector y pantallas; 2026-11-01)

- **El archivo no pasa por el servidor de la app.** Vercel acepta hasta 4,5 MB por pedido a una función, y el Excel de Nonnos pesa 7,3 MB.
  - El navegador sube el Excel directo al bucket privado `imports` (`<grupo>/<marca>/<uuid>.xlsx`), con la sesión de la persona.
  - Después llama a una **acción de servidor** que recibe solo la ruta, la marca, el prefijo, el nombre y el motivo. La acción baja el archivo, lo lee y llama a `create_job`, `stage_rows` (en lotes de 500) y `validate_job`. Si la carga de filas falla a mitad de camino, cancela la importación.
  - Se descartó una función Edge con `service_role`: tiene 2 s de CPU por pedido, poco para un Excel de 7 MB.
  - Se eligió una acción de servidor en lugar de una ruta `POST`. Hace lo mismo y Next le agrega su control contra pedidos de otros sitios. La pantalla le da hasta 60 s (`maxDuration`); el Excel real se lee en unos 15 s.
- **"Lee quien subió"** (migración `20261108120000_imports_upload_checks.sql`): la política `imports_read` del bucket suma `owner_id = auth.uid()`, **mientras esa persona siga importando en la marca**.
  - `owner_id` lo pone Storage al subir, y la política de subida exige que sea el de la sesión: nadie sube a nombre de otro.
  - Así el servidor lee el archivo con la sesión de quien lo subió, sin ninguna clave especial. No expone nada nuevo, porque es su propio archivo.
  - Los archivos de los demás siguen visibles solo con `prices.view`. Pruebas en la `201`.
- **La misma migración suma dos controles** (de la revisión de seguridad):
  - `create_job` registra una importación solo sobre un archivo que subió la misma persona;
  - `create_job` guarda cuántas filas leyó el servidor (`expected_rows`), y un trigger no deja pasar a "validada" si las filas cargadas no son esas. Una carga cortada a mitad de camino (un corte de tiempo, una caída) no se puede confirmar como si fuera el recetario completo.
- **El lector** (`lib/imports/recipe-book.ts`) encuentra las columnas por el título, no por la posición:
  - **INSUMOS:** una materia prima por fila. Las de rubro "Plato finalizado" son platos: si tienen bloque en PLATOS se usa el bloque; si no, entran sin componentes.
  - **pre-elaborado y PLATOS:** cada fila `CODIGO / INGREDIENTES / Medida / Receta (GRS)` abre un bloque, **aunque sea una plantilla vacía**. Así un bloque nunca se come las filas del siguiente.
  - **El título del bloque** es la fila de arriba con "Precio por porción" o "Peso Neto Total". Un número suelto entre el título y el encabezado no cuenta.
  - **Se descartan** las plantillas sin código, y las que no tienen nombre ni líneas.
  - **El precio va en `price`,** nunca en `raw` ni en `parsed`. Una fórmula con error (`#N/A`) queda vacía.
  - **Topes:** 15 MB, 10.000 filas, y se mira que el contenido sea un zip.
- **Comprobado contra el Excel real de Nonnos, solo leyéndolo** (con una prueba temporal que se borró; nada entró en la base de desarrollo):
  - 161 materias primas, 65 preparaciones, 64 platos de PLATOS y 71 de INSUMOS sin bloque;
  - 289 líneas en pre-elaborado y 313 en PLATOS: las mismas que contó el análisis inicial;
  - 2 líneas sin gramos, y recetas con nombre pero sin ingredientes cargados, que entran con aviso;
  - descomprimido ocupa 53 MB (el tope es 250 MB) y se lee en unos 15 s.
  - La primera versión del lector contaba 72 preparaciones y 873 líneas: se comía las plantillas vacías y tomaba el rinde de una plantilla sin código como si fuera el código. Ya no.
- **Pantallas:**
  - `/recetas/importar` (lista);
  - `/recetas/importar/nueva` (subir);
  - `/recetas/importar/[id]` (vista previa con totales, próximo paso según permiso, recetas creadas, problemas paginados y cancelar);
  - `/recetas/importar/[id]/errores`, el CSV de problemas: escapa las celdas que empiezan con `= + - @` y pide de a 1.000 filas.
  - Ninguna pantalla lee precios.
- **Dependencias:** `exceljs` 4.4.0 fija, con un override de `uuid` 11.1.1 que cierra su aviso. Quedan **8 avisos moderados** de `npm audit` (`minimatch`, vía `archiver`), que ExcelJS usa solo para **escribir** archivos. Acá solo se leen. Riesgo aceptado por Joaco; se revisa con Dependabot.

## Revisiones (PR 2)

- **`ui-reviewer`:** sin graves.
  - **5 medios, resueltos:**
    - el formulario ya no se pierde si la lectura falla;
    - el prefijo de una marca no queda puesto al elegir otra;
    - antes de validar, los totales dicen "Sin validar" en vez de "Sin errores";
    - las recetas creadas están paginadas;
    - en celular, los totales van en una columna.
  - **Menores resueltos:**
    - etiquetas de motivo distintas en cada formulario;
    - "Validar" como acción principal antes de validar;
    - el avance se anuncia al lector de pantalla;
    - el campo del problema aparece en la lista;
    - un error del CSV vuelve a la pantalla con un aviso;
    - axe también en la lista y en el formulario con errores;
    - el botón de Recetas dice "Importaciones".
- **`security-auditor`: apto, sin graves.**
  - **Resueltos:**
    - medio 1, archivo enorme por dentro: se mira el índice del zip antes de abrirlo (tope de 250 MB descomprimido y 5.000 archivos) y se recorren hasta 20.000 filas por solapa;
    - medio 3, carga cortada: `expected_rows` y el trigger;
    - menor 1: el dueño lee su archivo solo mientras importa en la marca;
    - menor 2: la importación solo se registra sobre un archivo propio;
    - menor 3: un número a la derecha de una etiqueta vacía, o de un título sin código, ya no se toma como dato. Era real: así se colaban 7 preparaciones falsas del Excel de Nonnos;
    - menor 5: el CSV también escapa los caracteres de ancho completo y los espacios de adelante.
  - **Pendiente, medio 2: archivos huérfanos.** Si la lectura falla o la persona cierra la pantalla, el Excel queda en el bucket, sin importación y sin forma de borrarlo. Lo ven quien lo subió y quien ve precios. Hace falta una limpieza programada en el servidor (con la clave de servicio, nunca en el navegador) y una regla de cuánto se guardan los archivos. **Se decide con Joaco antes de producción.**
  - **Pendiente, menor 4:** `stage_rows` no exige valores simples en `parsed`, como sí lo hace en `raw`. Requiere a alguien de adentro que además ya ve precios. Va en la próxima migración de importaciones.
- **`db-reviewer`:** la primera pasada encontró 1 grave: la prueba "la Chef no baja un Excel ajeno" fallaba al poner el dueño en los archivos de prueba. Se corrigió para que cuente solo archivos ajenos, sin debilitarla. Además se sumaron las pruebas de Compras leyendo el archivo de otra persona y del dueño que ya no importa. La segunda pasada no encontró graves ni medios.
  - **Menor resuelto:** prueba de la carga con filas de más.
  - **Menor aceptado:** `create_job` acepta `expected_rows` vacío, para no romper las importaciones anteriores. La app siempre lo manda, y quien llama a la función directo ya decide qué filas carga, así que no gana nada.
  - **Menor aceptado:** si la carga quedó incompleta, "Validar" muestra el error y la salida es "Cancelar importación", que está en la misma pantalla.

## Riesgos

- **El Excel real puede traer casos que el ficticio no tiene.** El lector informa toda fila que no entiende como error, nunca la adivina, y la vista previa no toca nada oficial.
- **Materias primas parecidas entre marcas:** solo se reutiliza con el nombre exacto normalizado. Unir las parecidas queda para una pantalla de "unificar".
- **Medidas caseras sin conversión:** se importan los gramos, que el Excel siempre trae, y la medida queda como nota.
- **La merma de los insumos** (20 con desperdicio) no se convierte en rendimiento estándar, porque eso necesita aprobación (2.1 B). Queda guardada en la fila.
