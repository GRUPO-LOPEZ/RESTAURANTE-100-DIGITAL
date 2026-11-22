# ADR-0061: Panel de control en una pantalla, códigos automáticos, razón social de ARCA y mapa

- **Fecha:** 2026-11-22
- **Estado:** plan aprobado por Joaco el 2026-11-22. Tanda 1 de las correcciones del Módulo 1 (pedido de Soy, `docs/prompts/2026-11-22-correcciones-modulo-1.md`). La base y las pantallas del Panel van en un solo PR (decisión de Joaco, 2026-11-22: el Panel de antes no encajaba con las reglas nuevas). Usuarios va en el PR siguiente (ADR-0062).
- **Sigue a:** ADR-0030 y ADR-0031 (panel de control), ADR-0029 (razones sociales), ADR-0046 y ADR-0051 (pantallas sin scroll), ADR-0053 (el código del local arma el número de las OC).
- **Cambia:** ADR-0031 decía que «el Gerente puede cambiar el código de su local». Ahora el código de un local no cambia nunca.

## Problema

Soy pidió que el Panel de control se cargue como las fichas de receta y de materia prima: todo en una pantalla, sin pantallas sucesivas. Además:

- códigos de marca y de local que se arman solos;
- el nombre del local con la marca y la zona;
- dirección, localidad, teléfono y fecha de apertura obligatorios;
- un mapa con los locales;
- la razón social con los datos de la constancia de ARCA y su PDF;
- las áreas dentro de la ficha del local.

## Decisiones (de Soy, y las del plan aprobadas por Joaco)

1. **Código de marca `NN-PALABRA`** (`01-RAGU`, `02-PADELLA`):
   - el número es correlativo por grupo y lo pone la base;
   - la palabra sale del **nombre corto** de la marca (columna nueva `short_name`: Ragú, Padella, Nonnos), que también arma el nombre de sus locales; se puede corregir al crearla;
   - la palabra no se repite en el grupo (índice único `brands_word_key`, que cuenta también los códigos de antes);
   - después de creado, el código queda fijo.
2. **Código de local `PALABRA-NNN`** (`RAGU-001`):
   - correlativo por marca, fijo para siempre;
   - el **nombre** («Ragú Leloir») se guarda, lo arma la base con el nombre corto de la marca y la zona, y se rearma si cambia cualquiera de los dos; el código, no.
3. **Lo que ya existe no cambia solo:**
   - las marcas conservan su código (`PASTAS`) y reciben su número;
   - los locales con código lo conservan (`PCE`, con OC emitidas en staging);
   - los locales sin código reciben el automático, porque asignar uno que falta no es cambiarlo.
   - Los prefijos de importación y los códigos de recetas y materias primas no dependen de la marca ni del local, así que no se tocan.
4. **«En apertura» es la columna `opening`, no un estado nuevo.** La base tiene más de 70 controles de `status = 'active'` (permisos, costos, tableros). Un local en apertura funciona como uno abierto, para poder prepararlo.
   - En apertura = activo + `opening`.
   - Abierto = activo sin `opening`.
   - Cerrado = `inactive`.
5. **7 datos obligatorios para pasar a Abierto:** marca, zona, tipo, fecha de apertura, dirección, localidad y teléfono.
   - Soy pidió 4; se suma la zona, que arma el nombre.
   - La razón social es **opcional** (decisión de Joaco, 2026-11-22): sin ella, el costo sin IVA queda incompleto, pero el local abre.
   - Lo controla un trigger, solo en la transición a Abierto. Lo que ya estaba abierto no se traba: muestra «Falta teléfono» y cuenta en «Datos que faltan».
6. **Constancia de ARCA:** se carga a mano, con el PDF adjunto (decisión 4 de Soy). Autocompletar desde ARCA queda para cuando esté el certificado digital.
   - **Al día:** emitida hace 12 meses o menos.
   - **Vencida** (Atención): más de 12 meses.
   - **Sin constancia** (Sin datos): no hay PDF.
   - ARCA no les pone vencimiento: es una regla nuestra para que se actualicen una vez por año.
7. **Desde qué fecha factura cada local a nombre de cada razón social:** historial aparte (`org.restaurant_legal_entities`). `restaurants.legal_entity_id` sigue siendo la vigente, así las facturas y los costos no cambian. La fecha no puede ser futura: la razón social rige desde que se guarda.
8. **Áreas sin borrar:** quitar un área desde la ficha la deja inactiva (`is_active`), con su historia. Agregar una con el mismo nombre la vuelve a activar. A una persona no se le asigna un área inactiva.
9. **Un control por cada cosa:**
   - el estado del local se elige en su tarjeta (En apertura · Abierto);
   - «Cerrar el local» y «Reabrir el local» van arriba, con su motivo, como «Desactivar» del proveedor;
   - reabrir deja el local como estaba: Abierto (con los 7 datos) o En apertura.
10. **La ficha de marca es un panel lateral del Panel** (nombre, nombre corto, estado y sus locales). Las direcciones de antes (`/configuracion/marcas`, `/marcas/[id]` y `/razones-sociales`) llevan al Panel.
11. **Los permisos no cambian** (ADR-0031):
    - `org.manage` en el local: los datos y las áreas;
    - en la marca: el tipo, el estado y los locales nuevos;
    - en el grupo: las marcas y las razones sociales.
    - La razón social se ve como antes (`org.manage` del grupo o quien ve precios).
    - «Compras del mes» (plata) solo la ve quien ve las facturas.

## Tecnología nueva (justificada, como pide CLAUDE.md)

- **Mapa: Leaflet 1.9.4** (unos 42 KB comprimido, sin dependencias) con las teselas de **OpenStreetMap**.
  - Es la librería de mapas más usada y la más liviana que funciona con OSM sin claves ni costo (decisión 3 de Soy: Google Maps descartado).
  - Va sin `react-leaflet`, para no sumar otra dependencia: un componente cliente (`components/org-map.tsx`) la carga solo en el navegador.
  - **Política de uso de OSM:**
    - la atribución «© colaboradores de OpenStreetMap» se ve siempre;
    - el uso es bajo (un puñado de locales, pocas personas);
    - no hay descargas masivas;
    - la rueda del mouse no hace zoom.
  - **Riesgo:** si el uso crece, OSM puede pedir que se use otro proveedor de teselas. Se cambia con la variable `NEXT_PUBLIC_MAP_TILES_URL`, sin tocar código.
  - Los puntos van con los tonos fuertes de los gráficos (3:1 sobre el fondo), leídos de la paleta. Cada punto lleva el nombre del local y la lista de locales está al lado: el mapa no es la única forma de ver dónde están.
- **Direcciones: Georef** (`apis.datos.gob.ar/georef`), el servicio de normalización del gobierno argentino, gratis y sin claves.
  - Se consulta desde una acción del servidor (`lib/georef.ts`), solo al tocar «Buscar» y solo con `org.manage`. Tiene tiempo límite de 5 s.
  - Si no encuentra la dirección o no responde, el local se guarda igual y queda «Sin ubicar en el mapa».
  - Georef no devuelve el código postal: se escribe a mano.
  - La URL se cambia con `GEOREF_URL`: las pruebas usan un servidor de mentira (`tests/e2e/georef-stub.mjs`).

## Cómo se hizo

- **Migraciones:** cinco, una idea por archivo.
  - `20261212120000_org_codes.sql`: números, nombre corto, zona, códigos y triggers de identidad.
  - `20261212130000_restaurant_location.sql`: provincias, ubicación, apertura y alta nueva.
  - `20261212140000_legal_entity_arca.sql`: datos de ARCA, actividades e historial de razón social.
  - `20261212150000_legal_entity_documents.sql`: bucket `org-documents`, solo PDF, y constancias solo de inserción.
  - `20261212160000_org_sheets.sql`: guardado en lote de las dos fichas con sello de concurrencia, cerrar y reabrir, y lo de antes que acompaña.
- **Correlativos sin saltos ni repetidos:**
  - el alta toma la fila del grupo o de la marca con `FOR NO KEY UPDATE` hasta el final de la transacción: otra alta espera y ve el número siguiente;
  - `FOR NO KEY UPDATE` no traba las escrituras que solo apuntan al grupo o a la marca;
  - lo controla pgTAP con `pgrowlocks`.
- **El código no se cambia ni pasando por vacío:** el trigger rechaza cualquier cambio de un código cargado. Solo el traspaso aprobado (`org.apply_transfer`) lo libera para el local nuevo, y lo avisa en la transacción (`app.releasing_code`).
- **El traspaso** copia ahora la ubicación, el tipo, la razón social y el estado, y solo las áreas activas. La zona no se copia: el nombre lo eligió quien pidió el traspaso. Un local traspasado conserva el código de su marca de antes, como ya hacía el traspaso (lo usan las OC).
- **Pantallas:**
  - `/configuracion`: tipo A. 4 indicadores, marcas y locales, mapa, razones sociales y los otros accesos.
  - `/configuracion/locales/[id]`: ficha del local.
  - `/configuracion/locales/nuevo`: el alta sin JavaScript; con JavaScript es un modal corto.
  - `/configuracion/razones-sociales/[id]`: ficha de la razón social.
  - Las tres fichas siguen el patrón sin scroll (ADR-0046 y ADR-0051).
- **Componentes:**
  - nuevos: `components/place-sheet/`, `components/legal-entity-sheet/`, `components/structure-panel.tsx`, `components/new-place-form.tsx` y `components/org-map.tsx`;
  - `Kpi` y `Metric` suman `smallValue` (20 px) para un valor de texto largo, como el nombre de una razón social.
- **Revisión de `db-reviewer`:** 2 hallazgos graves y 6 medios, todos corregidos antes del commit.
  - G1: el código se podía cambiar pasando por vacío.
  - G2: dos marcas con la misma palabra armaban los mismos códigos de local.
  - M1: la razón social con fecha futura regía hoy.
  - M2: quitar la razón social dejaba mal el historial.
  - M3: el traspaso no acompañaba las reglas nuevas.
  - M4: las áreas inactivas se podían asignar.
  - M5: los candados trababan las FK.
  - M6: la app usaba las firmas viejas.

## Revisión de `security-auditor` (corregido antes del commit)

- **Grave, HTML en el mapa.** Leaflet ponía el nombre del local como HTML en el cartel del punto. Un gerente podía escribir etiquetas en la zona de su local y hacer correr código con la sesión de quien mirara el mapa. Se corrigió en tres lugares:
  - **El mapa:** el cartel se arma con un nodo de texto, nunca como HTML.
  - **La base:** rechaza `<` y `>` en la zona, el nombre corto y el nombre de marcas y locales. Hay checks en las tablas y mensajes claros en las funciones.
  - **Prueba:** pgTAP lo controla.
- **Medio, quién ve los datos de ARCA.** Las actividades, el historial de razones sociales y las constancias los veía cualquiera con `prices.view` en un solo local del grupo. Ahora los ve quien administra todo el grupo, o quien ve precios en algún local que factura con esa razón social (`org.can_see_legal_entity`).
  - La fila de `org.legal_entities` (nombre, CUIT, IVA y los datos de ARCA nuevos) sigue con la regla de antes, porque la usan costos, precios y facturas. **Decisión de Joaco (2026-11-22): no se restringe.**
- **Menores corregidos:**
  - el enlace firmado del PDF vence a los 5 minutos;
  - el bucket aceptaba 5 MB y ahora acepta 3,5, como la app;
  - la fecha desde la que factura no puede ser anterior al 2000.
- **Menores anotados:**
  - Las coordenadas las manda el navegador: un gerente podría ubicar mal su local. Afecta solo el mapa.
  - «Compras del mes» suma lo que la persona ve: quien ve facturas de un solo local ve un total parcial.
  - Cuando llegue la CSP completa (pendiente antes de producción), hay que sumar el dominio de las teselas en `img-src`.

## Revisión de `ui-reviewer` (sin graves; medios corregidos)

- **`FocusTarget`:** está en las tres pantallas, así que los enlaces con `#ancla` llevan el foco a su tarjeta.
- **El mapa dentro del sistema de diseño:** Inter, sin sombras, bordes y radios del sistema, zoom en español y de 44 px en el celular.
- **En el mapa el color no es la única señal:** un restaurante es un punto lleno y una cocina o producción, un círculo vacío, con leyenda.
- **El indicador repetido:** en la ficha del local, «Razón social» repetía la tarjeta de abajo. Ahora es «Constancia de la razón social», con su fecha y Al día o Vencida.
- **Validación:** los obligatorios vacíos se marcan al salir del campo, y «Agregar» dice por qué no agrega.
- **Motivo real:** «Compras del mes» distingue «no pudimos cargarlas» de «no tenés permiso».

## Queda para después

- Una tarea de limpieza de los PDF subidos y nunca registrados en `org-documents` (no se pueden borrar desde la app).
- Si alguien cargó a mano un código de local con la forma automática de otra marca (por ejemplo, `PASTAS-002` en otra), el alta de esa marca avisa en palabras y lo tiene que revisar quien administra el grupo.
- El cálculo de la retención (P8): hoy «Agente de retención» solo se marca.
- El Panel trae todas las marcas, locales y razones sociales de una vez (sin paginar). Con el volumen de hoy alcanza y las tarjetas se desplazan adentro; si el grupo crece a decenas de marcas, hay que paginar o filtrar por marca.
