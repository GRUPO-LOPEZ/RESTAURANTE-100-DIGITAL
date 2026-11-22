# Correcciones del Módulo 1 (pedido de Soy, desde el 2026-11-22)

Soy está recorriendo el sistema en staging y junta las correcciones en tandas. **Se mandan todas juntas** y se aplican todas. Cada tanda trae su boceto validado y su prompt. Hasta que lleguen todas, no se arranca un módulo nuevo.

| Tanda | Qué toca                                                                                      | Boceto                                | Estado                        |
| ----- | --------------------------------------------------------------------------------------------- | ------------------------------------- | ----------------------------- |
| 1     | Panel de control (estructura del grupo, marcas, locales, razones sociales, áreas) y Usuarios | `2026-11-22-boceto-panel-y-usuarios/` | Validada por Soy (2026-11-22) |
| 2     | Base de conocimiento: recetas, fichas técnicas, materias primas, catálogo y rubros            | `2026-11-22-boceto-base-de-conocimiento/` | Validada por Soy (2026-11-22) |

---

## Tanda 1: Panel de control y Usuarios, cada cosa en una pantalla

### Lo que pidió Soy

- El Panel de control, en todas sus partes, tiene que cargarse como las fichas de receta y de materia prima: **todos los datos en una sola pantalla**, no en pantallas sucesivas, con los formatos de carga ya validados en otros menús. Más fácil e intuitivo.
- **Marca:** el código se arma solo, con un número correlativo y el nombre. Ejemplo: Ragú → 1-RAGU, la segunda marca → 2-PADELLA.
- **Local nuevo:** el nombre se arma solo con la marca y la zona (Ragú Leloir, Ragú Belgrano). El código, con la marca y un número correlativo.
- **Dirección, localidad, teléfono y fecha de apertura** dejan de ser opcionales. Con las direcciones se arma **un mapa** en el Panel con todos los restaurantes.
- **Razón social:** una ficha completa con todos los datos que hoy tiene ARCA.
- **Las áreas**, en la misma pantalla del local.
- **Usuarios:** simplificar la carga, con poco o nada de scroll.

### Decisiones de Soy sobre las propuestas (2026-11-22)

1. **Código de marca con dos cifras:** `01-RAGU`, `02-PADELLA`, `03-NONNOS`. El número es correlativo y lo pone el sistema. Así la marca 10 no se ordena antes que la 2.
2. **Código de local corto y fijo, `RAGU-001`, con la zona solo en el nombre** («Ragú Leloir»). Soy había pedido «RAGU 001 LELOIR» como código y aceptó la propuesta: el código no cambia nunca (lo usan el historial y las órdenes de compra) y la zona sí puede cambiar si el local se muda. Además, el número de cada OC empieza con el código del local.
3. **Mapa con herramientas gratis:** OpenStreetMap para el mapa y Georef (el servicio de normalización de direcciones del gobierno argentino) para encontrar la dirección. Sin claves ni costo. Google Maps queda descartado por ahora. Es una tecnología nueva: justificala por escrito en el ADR, como pide CLAUDE.md.
4. **Razón social cargada a mano**, con el PDF de la constancia de inscripción de ARCA adjunto. Autocompletar desde ARCA con el CUIT queda para cuando esté el certificado digital (el mismo que va a pedir la factura electrónica).
5. **Obligatorios sin trabar lo existente:** los locales que ya existen y no tienen esos datos no se traban; muestran «Falta teléfono» (o el dato que sea) hasta completarlos. **Un local no puede pasar a «Abierto» si le falta un obligatorio** (lo valida la base).
6. **Invitar a una persona en un modal corto:** nombre, mail, rol y dónde trabaja. El resto se completa en su ficha.

---

### Prompt (copiar en Claude Code)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md (pantallas de carga sin scroll, ADR-0046),
docs/decisiones/0030, 0031, 0036, 0039 y 0051, y el boceto
docs/prompts/2026-11-22-boceto-panel-y-usuarios/ (README y los 5 .dc.html).
Tarea: Panel de control y Usuarios, cada cosa en una sola pantalla, como las fichas de receta y de
materia prima. Rama: feat/panel-y-usuarios-en-una-pantalla. Entrá en modo plan y mostrame el plan
antes de tocar nada. Si el plan queda grande, proponé partirlo en 2 PRs (base y pantallas).

PANTALLAS (ver el boceto; 1440 × 900, 1600 × 900, 1715 × 843 y 1920 × 1080 sin scroll de página)
1. /configuracion: «¿Cómo está armado el grupo?». Reemplaza el menú de tarjetas de hoy por una
   sola pantalla tipo A:
   - 4 indicadores (Metric): Marcas, Locales (cuántos restaurantes y cocinas centrales),
     Razones sociales (constancias al día) y Datos que faltan (locales con obligatorios sin
     cargar, con «Completar»). Sin datos: «Sin …», nunca un estado positivo.
   - Izquierda: marcas con sus locales en una lista agrupada (código, nombre, dirección, tipo y
     estado con palabra). Clic en un local abre su ficha. «Nueva marca» se agrega en la misma
     lista, mostrando el código que va a tener (04-…).
   - Derecha: el mapa con todos los locales (OpenStreetMap) y las razones sociales (nombre, CUIT,
     condición de IVA, cuántos locales); cada una enlaza a su ficha.
   - Abajo, una línea con los otros accesos que hoy tiene el Panel (Configuración de precios,
     Usuarios, Roles y permisos, Configuración del catálogo), según los permisos de cada persona.
   - Botones arriba: «+ Nueva marca» y «+ Nuevo local».
2. Alta de local: modal corto. Marca (botones, no desplegable), Zona o ubicación, Tipo
   (Restaurante · Cocina central · Producción) y Motivo. Muestra «Así va a quedar»: el nombre
   (marca + zona) y el código (RAGU-002). «Crear y completar la ficha» crea el local en
   «En apertura» y abre su ficha.
3. Ficha de local (/configuracion/locales/[id]), tipo B sin scroll:
   - encabezado en una línea: «← Panel de control», nombre, código · marca · tipo, estado con
     palabra; a la derecha «Cerrar el local»;
   - 4 indicadores: Personas que trabajan acá (con «Ver quiénes»), Recetas asignadas, Razón
     social (con «Abrir ficha») y Datos obligatorios (N de 8);
   - tarjetas: «El local» (marca fija, zona, nombre automático, código fijo, tipo y estado como
     botones, fecha de apertura); «Ubicación y contacto» (dirección con búsqueda en Georef y la
     marca «Encontrada», localidad, provincia y CP, teléfono, mini mapa); «Razón social» (a nombre
     de quién factura, CUIT, IVA, desde qué fecha, «Cambiar»); «Áreas» (chips que se renombran
     con un clic, se agregan en la misma tarjeta y se quitan sin borrar: quedan inactivas);
   - barra fija abajo: contador, motivo obligatorio, Descartar y Guardar cambios. Todo se guarda
     en una sola transacción.
4. Ficha de marca: la misma idea, más chica (nombre, código, estado y sus locales). Si entra en
   la pantalla 1 como edición en el lugar, mejor: proponelo en el plan.
5. Ficha de razón social (/configuracion/razones-sociales/[id]), tipo B sin scroll, con los datos
   de la constancia de inscripción de ARCA:
   - Identidad: razón social, CUIT (con dígito verificador), forma jurídica (S.R.L. · S.A. ·
     S.A.S. · Persona), inicio de actividades, nombre de fantasía;
   - Domicilio fiscal: calle y número, localidad y CP, provincia, domicilio fiscal electrónico;
   - Impuestos: IVA (Resp. inscripto · Monotributo · Exento, como hoy), Ganancias, Ingresos
     Brutos (Convenio Multilateral · Local · Exento), número de IIBB, jurisdicción sede,
     empleadora, agente de retención, agente de percepción (toggles de un clic);
   - Actividades de ARCA: código y descripción, una principal y las secundarias;
   - Locales que la usan, con desde qué fecha;
   - la constancia en PDF (Storage, como las fotos de facturas) con su fecha, y el indicador
     «Al día» o «Vencida» (proponé la regla en el plan; por ejemplo, más de 12 meses = Atención).
   El agente de retención se conecta con la columna que quedó preparada en Pagos (P8): solo se
   marca, el cálculo sigue fuera de esta tarea.
6. Usuarios:
   - Ficha de persona (/usuarios/[id]) sin scroll: encabezado con nombre, mail, puesto, marca y
     estado; a la derecha Suspender y Desactivar. 4 indicadores (último ingreso y doble
     verificación, roles, cambios en 30 días con «Ver historial», accesos rechazados en 7 días).
     Tarjetas: Datos y Cuenta (estado como botones, doble verificación, sesiones abiertas con
     «Cerrar todas»); Roles y dónde los usa, con «Dar otro rol» en la misma tarjeta; Lo último
     que hizo (5 y «Ver los N», en un panel lateral). Barra fija con motivo.
   - Invitar: modal corto (nombre, mail, rol, dónde trabaja). Reemplaza la pantalla /usuarios/invitar.
   - Revisá también el tablero y la lista de usuarios con la regla de sin scroll de página.

BASE (antes de cualquier pantalla; migraciones nuevas, RLS, auditoría y pgTAP)
- Marca: número correlativo por grupo, que asigna la base (sin saltos ni repetidos, como
  catalog.code_series), y código «NN-NOMBRE» en mayúsculas, sin tildes ni espacios. Proponé en el
  plan qué parte del nombre va (por ejemplo, la primera palabra: Ragú Bodegón → RAGU) y si se
  puede editar antes de guardar.
- Local: número correlativo por marca y código «MARCA-NNN», fijo. Columna nueva para la zona; el
  nombre se arma con marca + zona (decidí en el plan si se guarda o se calcula, y qué pasa si la
  marca cambia de nombre).
- Los códigos que ya existen NO se cambian solos: las OC ya emitidas, los prefijos de importación
  de recetas y los códigos de recetas y materias primas siguen iguales. En el plan, decime dónde se
  usan hoy el código de marca y el de local, y qué proponés para los que ya existen (en producción
  todavía no hay datos reales; en staging sí hay OC con el código PCE).
- Dirección, localidad, teléfono y fecha de apertura obligatorios para locales nuevos y para pasar
  a «Abierto»; los existentes muestran lo que falta. Latitud y longitud del local (de Georef),
  provincia y código postal.
- Razón social: las columnas de ARCA de arriba, actividades (tabla aparte) y la constancia
  (adjunto con fecha).
- Áreas: alta, cambio de nombre y baja lógica desde la ficha, en el mismo guardado del local.
- Todo con motivo y auditoría, como hoy. Los permisos no cambian (org.manage y los de usuarios).

TECNOLOGÍA NUEVA (justificar en el ADR, aprobación de Joaco)
- Mapa: Leaflet (o la opción más liviana que propongas) con teselas de OpenStreetMap, respetando
  su política de uso y la atribución.
- Georef: https://apis.datos.gob.ar/georef/ desde una función de servidor (sin claves). Si no
  encuentra la dirección, se guarda igual y queda «Sin ubicar en el mapa», sin trabar.
- Nada de Google Maps.

PRUEBAS
- pgTAP: correlativos de marca y de local sin saltos ni repetidos (también con dos altas a la vez),
  obligatorios para pasar a «Abierto», CUIT válido, áreas con baja lógica, auditoría con motivo,
  RLS por rol (quien no tiene org.manage no ve ni cambia nada de esto).
- Vitest: armado del nombre y de los códigos, regla de la constancia.
- Playwright con axe: las pantallas sin scroll de página en los 4 tamaños, con un rol que edita y
  uno que solo lee; alta de local desde el modal hasta la ficha; agregar y quitar un área;
  invitar a una persona desde el modal; dar un rol desde la ficha; celular de consulta con 44 px.
- Las pruebas que se rompan por la nueva disposición se ajustan para controlar lo mismo. No se
  borran ni se aflojan. Corré todo (npm run test).

ENTREGA
db-reviewer, security-auditor y ui-reviewer. Capturas reales en 1440, 1600, 1715 × 843, 1920 y
celular de cada pantalla, como PNG en docs/capturas/panel-y-usuarios/, commiteadas en el PR. ADR
nuevo. Lista de cambios para Soy en docs/modulos/. docs/estado.md. Commit: «feat(panel): estructura
del grupo, local, razón social y persona en una pantalla».
```

---

## Tanda 2: Base de conocimiento (recetas, materias primas, catálogo y rubros)

### Lo que pidió Soy

**Recetas**

1. La pantalla de categorías, con las formas de carga, edición y visualización ya validadas.
2. En los ingredientes de la receta, un botón para cargar una materia prima nueva sin salir.
3. Al hacer varias recetas, no pasar todo a peso: cada ingrediente mantiene su unidad (si es en litros, sigue en litros) y pasa a la unidad mayor cuando corresponde (1.200 ml → 1,2 l). Hoy, al ampliar en litros, pedía la densidad. La idea es que el operador no haga cuentas.
4. En la planilla de la receta, la cantidad y la unidad ocupan demasiado: la unidad, el ancho de la unidad más larga. Las celdas de «hacer varias» también son muy grandes. Ingredientes: 8 renglones; al llenar el octavo aparece otro, y así. Botón «Agregar ingrediente».
5. Medidas prácticas (taza, cuchara y las que hagan falta) para decirle al operador cuántas unidades del elemento práctico usar.
6. En el procedimiento, el equipo de cada paso sale de una lista que se carga donde corresponda.
7. Cuatro fichas técnicas: 1, completa, para capacitar; 2, ingredientes y sus elementos de uso, para el servicio; 3, la foto; 4, solo el procedimiento. En el celular se adaptan.
8. Sector y partida de la receta: desplegables con listas genéricas, con la posibilidad de agregar desde donde corresponda.
9. Que la receta muestre su número de versión junto al nombre.

**Materias primas**

1. Configuración del catálogo con todas las listas y parámetros de las pantallas ya hablados.
2. En la lista, los botones de rubros más amigables, con un ícono genérico y más chicos, en un panel a la izquierda que no se desplaza aunque haya muchas materias primas.
3. Foto del producto en la ficha.
4. «Proponer precio», con una carga más simple; el mismo criterio para las demás subpantallas de la ficha.

**Rubros**

1. El mismo criterio que Materias primas para los botones y los desplegables.
2. Al hacer clic en un rubro, ver su descripción, como en Materias primas.

### Decisiones de Soy sobre las propuestas (2026-11-22, todas aprobadas)

1. **Medida práctica con una lista del sistema.** En Configuración del catálogo, una lista «Medidas prácticas» con lo que contiene cada una (cucharón 120 ml, taza 240 ml, cucharada 15 ml, cucharadita 5 ml, nido de pasta 120 g). En la receta, cada línea elige su medida práctica y el sistema calcula cuántas van (se puede corregir a mano). Al hacer varias recetas, también se multiplican. El cocinero ve «480 g · 4 nidos».
2. **Hacer varias recetas, sin pasar de volumen a peso.** Cada línea se multiplica en su propia unidad. Pasa a la unidad mayor de la misma clase al llegar a 1.000 (g → kg, ml → l). Las cucharadas y tazas se multiplican y, si quedan muchas, muestran al lado su equivalente en ml o g. Nunca hace falta la densidad para escalar.
3. **Las fichas se adaptan al ancho de la pantalla** (no a la detección del aparato): mismo resultado, más confiable, y sirve también en tablet o ventana angosta.
4. **Sectores, partidas, equipos y medidas prácticas: listas nuevas del grupo** en Configuración del catálogo. Desde la receta, «+ Agregar» lo ve solo quien puede editar el catálogo. La capacidad pasa a ser un dato del equipo (Pastera 6 canastos, Horno combi 10 GN 1/1); el paso puede corregirla.
5. **La versión en todas las fichas y en lo impreso:** «Versión 2 · REC-PAS-012 · publicada el 20/11/26 · aprobó {persona}». En la ficha de edición, el chip «Versión 3 · Borrador» y «vigente: versión 2 del {fecha}».
6. **«+ Nueva materia prima» desde la receta en un modal corto** (nombre, rubro, unidad de uso). Crea la materia prima sin precio y la agrega al renglón; el costo dice «Sin precio» hasta cargarlo.
7. **«Proponer precio» con cinco datos:** producto (botones si son 5 o menos), precio del envase, si incluye IVA (toggle), para quién vale (botones) y motivo; «desde» es hoy y se puede cambiar. Muestra en el momento cuánto queda por unidad de uso sin IVA y cuánto sube contra el anterior. El resto (descuento, comprobante, alícuota, proveedor, origen, observaciones) va en «Más datos». La alícuota y el proveedor salen del producto por defecto.
8. **Cada rubro elige su ícono de un set fijo de unos 12** (Lucide), que se usan en Materias primas y en Rubros.

---

### Prompt (copiar en Claude Code)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md (pantallas de carga sin scroll, ADR-0046),
los ADR de recetas, escalado, fichas, materias primas, precios y rubros (0039, 0041, 0043, 0044,
0046, 0047, 0051 y los que correspondan), y el boceto docs/prompts/2026-11-22-boceto-base-de-conocimiento/
(README y los 8 .dc.html). La sección «Tanda 2» de docs/prompts/2026-11-22-correcciones-modulo-1.md
tiene lo que pidió Soy y sus 8 decisiones: mandan sobre el boceto.
Tarea: correcciones de la Base de conocimiento. Entrá en modo plan y mostrame el plan antes de tocar
nada. Es grande: proponé partirla en PRs chicos, por ejemplo:
  A. listas nuevas del catálogo (base + Configuración del catálogo en una pantalla);
  B. ficha de receta (planilla, medida práctica, sector, partida, equipo, nueva materia prima, versión);
  C. hacer varias recetas (unidades) y las 4 fichas técnicas;
  D. materias primas y rubros (panel de rubros con ícono, foto, «Proponer precio» simple).
Una rama por PR (feat/catalogo-listas, feat/receta-planilla, feat/fichas-tecnicas,
feat/materias-primas-y-rubros). Cada uno con su plan aprobado.

A. CONFIGURACIÓN DEL CATÁLOGO (boceto Configuracion)
- Una sola pantalla: a la izquierda las listas (Categorías de materias primas, Categorías de
  recetas, Sectores, Partidas, Equipos, Medidas prácticas, Unidades de medida, Procesos de
  rendimiento), a la derecha la lista elegida en una tabla que se edita en el lugar, con «+ Agregar»,
  toggle de activa y barra fija con contador y motivo. Todas las listas se editan igual.
- Base: tablas nuevas del grupo para sectores, partidas, equipos (nombre, capacidad y unidad de la
  capacidad) y medidas prácticas (nombre, contenido y unidad: ml o g o unidad). Baja lógica,
  auditoría, RLS con el permiso de configuración del catálogo que ya existe.
- Hoy sector, partida y equipo son texto libre en la receta y en los pasos: proponé en el plan cómo
  pasar lo cargado a las listas (por ejemplo, crear un elemento por cada texto distinto y vincularlo),
  sin perder historia de versiones publicadas.
- Las categorías de recetas y de materias primas pasan a esta pantalla con la misma forma.

B. FICHA DE RECETA (boceto Main)
- Planilla de ingredientes: Cantidad angosta (unos 76 px), Unidad del ancho de la unidad más larga,
  y dos columnas nuevas para la medida práctica (cuántas y cuál). 8 renglones; al llenar el último
  aparece uno nuevo. «+ Agregar ingrediente» y «+ Nueva materia prima» (modal corto: nombre, rubro,
  unidad de uso; crea la materia prima sin precio y la deja en el renglón).
- Medida práctica: la cantidad se calcula con lo que contiene la medida elegida y se puede corregir
  a mano (decí en el plan si se guarda el número o se calcula siempre). Solo si la unidad de la
  línea y la de la medida son de la misma clase (volumen con volumen, peso con peso), o con el peso
  por unidad que ya tiene la materia prima.
- Sector y partida: desplegables de las listas, con «+ Agregar» para quien puede editar el catálogo.
- Equipo de cada paso: desplegable de la lista; la capacidad viene del equipo y el paso puede
  corregirla.
- Encabezado: chip «Versión N · Borrador / En revisión / Publicada» y «vigente: versión M del
  {fecha}».
- La ficha sigue sin scroll de página en 1440 × 900, 1600 × 900, 1715 × 843 y 1920 × 1080.

C. HACER VARIAS RECETAS Y FICHAS TÉCNICAS (boceto Escalar, FichaTecnica y FichaCelular)
- Escalado: cada línea se multiplica en su unidad; g → kg y ml → l al llegar a 1.000; nunca convierte
  volumen a peso para escalar (hoy pide densidad: encontrá por qué en el plan, con la prueba que lo
  reproduce). Cucharadas, cucharaditas y tazas se multiplican y muestran al lado el equivalente en
  ml o g cuando pasan de un umbral (proponelo). Las medidas prácticas también se multiplican
  («48 nidos de 120 g»). Celdas más chicas: el número grande, la unidad al lado.
- Fichas técnicas, con botones 1 · Completa, 2 · Servicio, 3 · Foto, 4 · Procedimiento, cada una
  imprimible:
  1. Completa, para capacitar: arriba, debajo del nombre, los datos (rinde, sector · partida,
     tiempo, alérgenos) y la foto arriba a la derecha; abajo, los ingredientes en el 25 % del ancho
     a la izquierda (cantidad y medida práctica) y el paso a paso en el resto, con el punto crítico.
  2. Servicio: los ingredientes con la medida práctica, en renglones con el ingrediente a la
     izquierda y la cantidad a la derecha (medida práctica grande, gramaje chico debajo); alérgenos.
  3. Foto: la foto grande, con nombre y versión.
  4. Procedimiento: solo el paso a paso, con equipo y tiempos.
  Todas llevan «Versión N · código · publicada el {fecha} · aprobó {persona}».
- Se adaptan al ancho (no a la detección del aparato): por debajo de 800 px, una columna, letra
  grande y controles de 44 px. Reemplazan o absorben la «Ficha de cocina» de hoy
  (/recetas/[id]/cocina): decilo en el plan.

D. MATERIAS PRIMAS Y RUBROS (boceto MateriasPrimas, FichaMP y Rubros)
- Lista de materias primas: a la izquierda un panel fijo de 250 px con «Todas» y los rubros
  (ícono, nombre y cantidad), que no se desplaza; a la derecha la tabla con su propio scroll, la
  búsqueda y la etiqueta del filtro. Reemplaza las tarjetas grandes de rubros de arriba
  (RubroFilterGrid). En el celular, los rubros pasan a un desplegable o a una fila deslizable.
- Ícono del rubro: un set fijo de unos 12 íconos de Lucide; el rubro guarda cuál usa (columna nueva).
- Rubros (/rubros): el mismo panel a la izquierda, con la clase (De compra · Preparación · Carta)
  como botones; al hacer clic en un rubro, a la derecha su ficha: nombre, código, estado,
  indicadores (materias primas, con precio al día, recetas que las usan), descripción editable,
  «va a recetas», subrubros y «Ver sus N materias primas».
- Foto del producto en la ficha de materia prima: una foto, con subir o sacar con la cámara del
  celular (mismo patrón y bucket que las fotos de recetas). Se ve chica en la lista.
- «Proponer precio» (components/ingredient-prices.tsx): panel lateral con producto (botones si son
  5 o menos), precio del envase en grande, toggle «incluye IVA», para quién vale (botones), desde
  (hoy, con «Cambiar») y motivo. Muestra en el momento el precio por unidad de uso sin IVA y la
  variación contra el anterior, y quién lo aprueba. «Más datos» (cerrado) tiene descuento,
  comprobante, alícuota, proveedor, origen y observaciones; alícuota y proveedor salen del producto.
  Revisá con el mismo criterio las otras subpantallas de la ficha (productos de compra, mermas,
  rendimientos, conversiones) y proponé en el plan cuáles simplificar.

PRUEBAS
- pgTAP: listas nuevas (RLS, baja lógica, auditoría), el paso de los textos a las listas, medida
  práctica y su cálculo, ícono del rubro, foto.
- Vitest: escalado por unidad (g → kg, ml → l, cucharadas con equivalente, sin densidad), cálculo
  de la medida práctica, armado de la versión, cálculo del «Proponer precio».
- Playwright con axe: sin scroll de página en los 4 tamaños con un rol que edita y uno que solo lee;
  la planilla agrega un renglón al llenar el octavo; nueva materia prima desde la receta; escalar
  una receta con litros sin que pida densidad; las 4 fichas en computadora y en celular; el panel de
  rubros no se desplaza con 300 materias primas; proponer un precio con los 5 datos.
- Las pruebas que se rompan por la nueva disposición se ajustan para controlar lo mismo. No se
  borran ni se aflojan. Corré todo (npm run test).

ENTREGA (en cada PR)
db-reviewer, security-auditor y ui-reviewer. Capturas reales en 1440, 1600, 1715 × 843, 1920 y
celular, como PNG en docs/capturas/<carpeta del PR>/, commiteadas. ADR nuevo por PR. Lista de cambios
para Soy en docs/modulos/. docs/estado.md.
```
