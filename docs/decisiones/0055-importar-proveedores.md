# ADR-0055: Importar proveedores desde planilla, sin tablas de carga intermedia

- **Fecha:** 2026-11-17
- **Estado:** plan aprobado por Joaco el 2026-11-16. P1 de la Fase 3, decidida el 2026-11-15 (ADR-0050): «sí, en un PR aparte, justo después».
- **Sigue a:** ADR-0050 (ficha de proveedor), ADR-0053 (órdenes de compra) y ADR-0027 (importador del recetario).
- **Migraciones:** `20261207120000_supplier_import.sql` y `20261207130000_supplier_tax_id_unique.sql`.

## Para qué

Cargar de una vez los ~30 proveedores reales en producción, desde la app y por Compras, sin tipearlos uno por uno. La planilla real **nunca** entra al repositorio ni a la máquina de desarrollo: se arma y se prueba con planillas inventadas.

## Opciones

1. **El importador del recetario** (ADR-0027): bucket, `import_jobs`, filas intermedias y dos confirmaciones. Es para cientos de filas y tres tipos de dato; para 30 proveedores en una hoja, es demasiado.
2. **Cargarlos a mano en la ficha.** Son 30 fichas con 20 datos cada una.
3. **Una función que valida y crea todo, con vista previa que se deshace.** (Elegida.)

## Decisión

- **El servidor lee el `.xlsx`** con ExcelJS, que ya es una dependencia (`lib/imports/supplier-sheet.ts`). Lo común con el recetario (leer una celda, el control del zip, abrir el archivo) pasó a `lib/imports/xlsx.ts`. El recetario lee igual que antes.
- **Los valores con nombre los traduce el lector,** con las mismas etiquetas que la ficha (`lib/suppliers.ts`):
  - condición IVA, días, canal, condición de pago y Sí/No;
  - un valor que no entiende es un error de esa fila, con la columna y el valor.

  Es un ajuste del plan, que los traducía en la base: así hay una sola lista de etiquetas. La base igual vuelve a controlar cada valor.

- **Los rubros van por nombre** y los busca la base, porque son del grupo. Se comparan sin tildes ni mayúsculas (`purchasing.normalize_name`).
- **`purchasing.import_suppliers(p_group_id, p_rows, p_confirm, p_reason)`:**
  - pide `purchasing.manage_suppliers` en el grupo; si no, `core.deny`, que deja el rechazo en los eventos de seguridad;
  - topes: 200 filas y 1 MB;
  - **vista previa** (`p_confirm` falso): hace todo y al final lo deshace. Lo que se ve es lo que va a pasar, y no queda nada: ni proveedores, ni números PROV, ni auditoría;
  - **confirmar:** lo mismo, de verdad, en una transacción y con motivo. Si una fila tiene error, no se crea nada;
  - cada proveedor va en su subtransacción: si la base rechaza un dato, el motivo de esa fila sale con el mismo mensaje que la ficha (`purchasing.raise_friendly`).
- **Un solo camino de escritura:** el alta y la ficha pasaron a internas (`create_supplier_internal` y `save_supplier_sheet_internal`), sin `execute` para nadie.
  - `create_supplier` y `save_supplier_sheet` quedaron como envoltorios, con el mismo permiso, el mismo motivo y el mismo resultado, y origen `manual`.
  - La importación audita con origen `import`.
- **Un CUIT que ya existe en el grupo se omite** («Ya existe (PROV-0003): se omite»), no es un error. Así se puede volver a subir la planilla corregida. El mismo CUIT dos veces en el archivo sí es un error.
- **El archivo no se guarda.** Lo que trae (CUIT, contactos) queda en la ficha de cada proveedor.
- **No entran:**
  - **Las cuentas de pago (CBU, alias):** cambiar una cuenta avisa a Controller y Dirección porque es el punto clásico de fraude. Se cargan a mano, una por una.
  - **Los números de cliente por local:** se cargan en la ficha.

## Excepción a la regla de las importaciones

`.claude/rules/database.md` pide «importaciones masivas en lotes, con tabla de carga intermedia y validación previa». Acá no hay tabla intermedia, por tres razones:

- son unas 30 filas;
- la vista previa es la validación previa: corre la misma función y se deshace;
- no se toca nada hasta confirmar.

## Riesgos aceptados

- **Las filas viajan del navegador al servidor entre la vista previa y la confirmación.** La base las vuelve a validar enteras. Lo que se podría mandar es lo mismo que puede cargar a mano quien tiene el permiso (como ADR-0027, decisión 8).
- **Una planilla real distinta de la plantilla:** Compras pasa sus datos a la plantilla. El formato es fijo, como con el recetario.
- **Los envoltorios se reescribieron** en una migración nueva. La red de seguridad es la prueba `320_suppliers`, que pasa sin cambios, y la `350` controla que sigan auditando con origen `manual`.
- **Un rechazo de la pantalla no deja evento de seguridad:** si la persona no administra proveedores en ningún grupo, la acción de servidor contesta sin llamar a la base. La pantalla y el botón ya no se le muestran, y una llamada directa a la base sí queda registrada (`core.deny`).

## Un CUIT por proveedor (Joaco, 2026-11-17)

Las revisiones notaron que la base no impedía dos proveedores con el mismo CUIT: el «ya existe» lo controlaba solo la importación. Joaco decidió: **un CUIT por proveedor.**

- **Índice único `catalog.suppliers_tax_id_key`** sobre `(group_id, core.normalize_cuit(tax_id))`, sin contar los borrados. Se compara sin guiones porque los CUIT cargados antes de la Fase 3 pueden tenerlos.
- **Vale para todos los caminos:** el alta, la ficha y la importación, también con dos cargas a la vez. El mensaje es «Ya hay un proveedor con ese CUIT en el grupo.» (en `catalog.raise_friendly` y `purchasing.raise_friendly`).
- **Si ya hubiera repetidos** (en staging o en producción), la migración no sigue y dice cuáles, para unificarlos a mano. Hoy no hay ninguno: producción todavía no tiene proveedores.
- **La importación sigue omitiendo** el CUIT que ya existe, en vez de dar error. Sigue el candado por grupo al confirmar, así dos importaciones a la vez dan «se omite» y no un error.
- **Pruebas:**
  - la `350` controla el alta con el CUIT de otro proveedor, con y sin guiones, y la ficha que intenta ponérselo;
  - la `320` y `proveedores.spec.ts` daban de alta con un CUIT fijo o repetido del seed. Ahora usan uno inventado y distinto, y controlan lo mismo que antes.

## Cambios por las revisiones

- **Base (`db-reviewer` y `security-auditor`):**
  - `supplier`, `terms` y `payment_terms` solo aceptan las claves de la planilla. Llamando directo a la base no se puede pisar el CUIT ni la razón social dentro de la ficha (saltearía el control de repetidos), ni cargar el horario de recepción.
  - El candado por grupo al confirmar.
  - El motivo de un valor que no corresponde dice «revisá la fila», no «revisá la ficha».
  - Pruebas nuevas: el contador PROV, la confirmación rechazada sin auditoría, el tope de 1 MB y el origen `manual` de los envoltorios.
- **El tope del zip ahora es real** (`security-auditor`, medio): antes se sumaba lo que el índice del zip dice que pesa cada archivo, y el índice puede mentir. Ahora `zipTooLarge` (`lib/imports/xlsx.ts`) además descomprime cada entrada con `zlib` y un tope de salida, antes de dárselo a ExcelJS. Vale también para el recetario. Sin dependencias nuevas.
- **La fila de ejemplo de la plantilla** da error si no la borran.
- **Pantalla (`ui-reviewer`):**
  - si falla la confirmación (red, permiso, motivo), el aviso se ve en la barra y el botón sigue para reintentar;
  - los 4 indicadores están desde el principio, «Sin datos» hasta revisar;
  - el resultado se anuncia al lector de pantalla;
  - el motivo usa el mismo esquema en el navegador y en el servidor;
  - en el celular, un aviso: «La importación de proveedores se hace en la computadora».

## Pruebas

- **pgTAP `350_supplier_import`:**
  - la vista previa no deja nada, ni un número PROV;
  - confirmar crea la ficha, los días, el canal, la condición de pago y los rubros, con origen `import` y el motivo;
  - un CUIT existente se omite y la misma planilla, subida de nuevo, omite todo;
  - una fila mala frena todo, con su motivo: rubro, CUIT, CUIT repetido, canal, valor que no existe o sin razón social;
  - más de 200 filas se rechaza;
  - la Cocinera, el Gerente y el Controller son rechazados, y el rechazo queda en los eventos de seguridad;
  - nadie llama a las internas directo.
- **Vitest `supplier-sheet.test.ts`:**
  - una fila completa;
  - encabezados distintos;
  - fórmulas, hipervínculos y booleanos;
  - filas vacías;
  - errores por fila;
  - CUIT repetido;
  - más de 200 filas;
  - archivos que no son Excel;
  - días escritos de varias formas;
  - y que la plantilla se vuelva a leer sin errores.
- **Playwright con axe (`importar-proveedores.spec.ts`):**
  - Compras baja la plantilla, ve un error, corrige, crea dos proveedores y los ve en el listado;
  - subir de nuevo los omite;
  - sin scroll en 1440 × 900 y 1715 × 843;
  - la Cocinera no ve el botón, ni la pantalla, ni la plantilla.
