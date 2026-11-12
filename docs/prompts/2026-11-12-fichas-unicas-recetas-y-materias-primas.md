# Fichas únicas de recetas y materias primas (pedido de Soy, 2026-11-12)

Son **tres prompts**, para **tres ramas y tres PR**, en este orden: el 2 y el 3 usan los códigos y el listado del 1.
Cada uno se pega entero en Claude Code. Claude Code arranca en **modo plan** y Joaco aprueba el plan antes de que se construya nada.

- **Boceto visual de las cinco pantallas:** https://claude.ai/artifact/9U4Shpj45KogWSWBQYPEsK. Soy lo tiene que compartir con Joaco desde el menú «Compartir».
- El boceto muestra la idea, pero manda lo que dice este documento.
- Los precios y las cantidades del boceto son de ejemplo.

## Decisiones de Soy (2026-11-12)

- **Código de receta:** 3 letras del tipo, las 3 letras del rubro y 4 números correlativos por rubro.
  - Plato: `PLA-CAF-0001` (rubro PL-CAF).
  - Preparación: `PRE-SAL-0001` (rubro SR-SAL).
- **Código de materia prima:** el mismo criterio, `MPR-CAR-0001` (rubro MP-CAR).
- **Tipos de receta:** solo Plato y Preparación. «Componente por unidad» deja de ofrecerse al crear y lo que ya existe se muestra como Preparación.
- **«Receta madre»** quiere decir el bloque de peso bruto y peso neto de las preparaciones. No es la receta maestra del grupo.
- **Listados:** arriba van las tarjetas de rubros, como en la pantalla Rubros, y abajo la tabla, que se filtra con un clic en una tarjeta.

---

## Prompt 1: códigos automáticos, altas y listados por rubro

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/ y los ADR 0024, 0036, 0038, 0039 y 0040. Trabajá en modo plan y
seguí el método de 6 pasos. Rama nueva: feat/codigos-y-listados-por-rubro. Pedido de Soy del 2026-11-12. Hay un
boceto en docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md (pantallas 1, 2 y 3).

OBJETIVO
Que el código de cada receta y de cada materia prima lo arme la base, y que los listados de Recetas y de
Materias primas se ordenen por rubro.

1. CÓDIGOS AUTOMÁTICOS (base primero)
- Formato: <TIPO>-<RUBRO>-<NNNN>.
  - TIPO: PLA (plato), PRE (preparación) o MPR (materia prima).
  - RUBRO: las 3 letras del código del rubro de primer nivel (PL-CAF → CAF, SR-SAL → SAL, MP-CAR → CAR).
    Si la receta o la materia prima está en una subcategoría, se usa el rubro madre.
  - NNNN: el número siguiente al último usado en ese tipo y rubro, dentro del grupo, con 4 dígitos.
- La base genera el código dentro de la función de alta, en la misma transacción y con bloqueo, para que dos
  altas simultáneas nunca den el mismo número. Un número no se reutiliza aunque se borre el registro.
- El código no cambia nunca, aunque después cambie el rubro.
- Los códigos que ya existen NO se tocan.
- El modal muestra el código que va a salir (vista previa). Se confirma recién al crear: si alguien creó otra
  receta en el medio, se asigna el siguiente y se avisa.
- Definí en el plan y preguntame:
  - qué pasa al llegar a 9999;
  - qué código llevan las variantes por local (hoy se cargan a mano);
  - qué pasa con la importación de recetas.

2. TIPOS DE RECETA
- Al crear, solo se ofrecen Plato y Preparación.
- «Componente por unidad» (unit_component) deja de ofrecerse y lo que ya existe se muestra como «Preparación».
- No cambies datos ni costos de lo cargado: proponé en el plan si alcanza con la interfaz o si hace falta una
  migración. Las 198 líneas del seed tienen que costar lo mismo antes y después.

3. ALTA DE RECETA (modal, en este orden)
Alcance (grupo, marca o local) → Tipo (dos botones visibles: Plato | Preparación) → Rubro (filtrado por la clase
del tipo: PL para platos, SR para preparaciones) → Código (solo lectura, automático) → Nombre → Motivo → botón
«Crear receta». Al crear, va a la ficha de la receta.

4. ALTA DE MATERIA PRIMA (modal, mismo criterio)
Rubro (MP) → Código (automático, MPR-XXX-NNNN) → Nombre → «Se usa en recetas en», con la lista completa de
catalog.units y sus nombres largos («Kilogramo (kg)»), la misma que usan las recetas → Motivo → «Crear materia
prima».

5. LISTADO DE RECETAS (/recetas)
- Se quedan arriba a la derecha: Categorías, Importaciones y Nueva receta.
- Buscador por nombre o código.
- Dos botones visibles: Platos | Preparaciones, con su cantidad.
- Tarjetas de rubros de la clase elegida, con el mismo diseño de /rubros (reutilizá components/rubro-card.tsx y
  recipes.category_overview si sirven): nombre, código, cantidad y %.
  - Un clic en una tarjeta filtra la tabla; otro clic, o la etiqueta «✕», quita el filtro.
  - Un rubro sin recetas muestra «Sin recetas», nunca 0 %.
- Tabla: Código, Receta, Rubro, Alcance, Estado, Costo sin IVA en el local elegido. Se mantienen la paginación,
  el orden y las pestañas de estado que ya existen.
- En el celular, las tarjetas van en 2 columnas y la tabla pasa a tarjetas.

6. LISTADO DE MATERIAS PRIMAS (/materias-primas)
El mismo patrón: buscador, tarjetas de rubros MP y tabla. Se mantienen Configuración, Nueva materia prima y las
pestañas Activas y Desactivadas.

PERMISOS
Los mismos de hoy para crear recetas y materias primas. La generación del código no abre ningún permiso nuevo.

PRUEBAS
- pgTAP:
  - formato del código;
  - correlativo por tipo y rubro;
  - dos altas simultáneas no se repiten;
  - subcategoría usa el rubro madre;
  - no se reutiliza un número borrado;
  - los códigos existentes no cambian;
  - RLS por rol.
- Vitest para la vista previa del código.
- Playwright con axe, en celular y en computadora (1440, 1600 y 1920): alta de plato, alta de preparación, alta
  de materia prima y filtro por rubro.
- Ajustá las pruebas viejas que esperaban el código escrito a mano, sin debilitarlas.

ENTREGA
ADR nuevo, docs/estado.md, revisores db-reviewer, security-auditor y ui-reviewer, y un resumen en simple para Soy.
Si algo no está claro, preguntame antes de suponer.
```

---

## Prompt 2: ficha única de receta (plato y preparación)

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/ y los ADR 0025, 0032, 0036, 0039 y 0040, y mirá
app/recetas/[id]/page.tsx, components/recipe-lines-editor.tsx, recipe-steps-editor.tsx, recipe-photos.tsx y
app/recetas/[id]/escalar. Modo plan y método de 6 pasos. Rama nueva: feat/ficha-unica-receta. Requiere el
Prompt 1 fusionado. Boceto: pantalla 4 de docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md.

OBJETIVO
Reemplazar las 9 pestañas de la receta por UNA SOLA FICHA que ocupe toda el área (todo menos la barra lateral),
donde se carga todo sin saltar de menú en menú. La misma plantilla sirve para platos y preparaciones. Solo
cambia el bloque de rendimiento.

ESTRUCTURA (de arriba hacia abajo)
1. Encabezado.
   - A la izquierda: código, estado de la versión, nombre, tipo, rubro y alcance, y un índice de secciones con
     enlaces que bajan a cada una.
   - Arriba a la derecha: una foto con flechas ‹ › para pasar entre fotos (carrusel) y «Agregar foto».
     Reutilizá recipe-photos.
2. Datos generales: los campos de hoy (nombre, nombre corto, sector, partida, tiempos, conservación,
   descripción, presentación).
3. Ingredientes y costos: una grilla tipo planilla con estas columnas, en este orden:
   1. #
   2. Código: se escribe el código y se autocompleta.
   3. Ingrediente: se escribe el nombre y se despliegan sugerencias según las letras. Busca materias primas y
      preparaciones; una preparación usada como ingrediente lleva la etiqueta «Preparación».
   4. Cantidad.
   5. Medida: desplegable con las unidades compatibles de catalog.units.
   6. Las dos columnas «Hacer [4] recetas» y «Hacer [10] recetas». El número de cada una se puede escribir, y
      cada columna muestra el peso bruto y el costo por renglón y en el total.
   7. Precio por kg o por l: el precio vigente en el local elegido, en la unidad grande de la medida (100 cc de
      leche → precio del litro; 100 g de harina → precio del kilo).
   8. Costo en la receta: lo que cuesta esa cantidad.
   9. Incidencia en $: el % del costo total.
   10. Incidencia en peso: el % del peso total.
   - Arranca con 10 filas. Al completar la última, se agrega otra.
   - Abajo va una fila de totales.
   - Dos números destacados (componente Metric): «Peso total de la receta» y «Costo total de la receta, sin
     IVA».
   - Nunca suponer: si falta un precio o una conversión (por ejemplo, ml a g sin densidad), la celda muestra
     «—» con el motivo en un tooltip, y el total avisa que está incompleto. Nunca se muestra $ 0.
4. Rendimiento.
   - Plato: «Peso de la porción» (se carga) → «Porciones que salen» (automático: peso total ÷ porción) →
     «Costo por porción».
   - Preparación (lo que Soy llama «receta madre»): «Peso bruto total» (la suma de los ingredientes) →
     «Peso neto total» (se carga a mano) → «Rendimiento» (neto ÷ bruto, en %) → «Costo por kg neto».
   - Ese rendimiento es el valor OBJETIVO contra el que el futuro control de lotes va a comparar cada lote.
     Dejalo guardado en la versión de forma que ese módulo lo pueda leer.
   - Revisá cómo encaja con el «rendimiento final obligatorio» y la merma de cocción del ADR-0040: no dupliques
     datos. Las mermas de cada materia prima siguen en su ficha.
5. Procedimiento: debajo de todos los números, en pasos, con los mismos datos de hoy (qué se hace, tipo, minutos
   trabajando, minutos de espera, equipo) y «+ Agregar paso».
6. Alérgenos y Dónde se usa.
7. Versiones y aprobaciones.
   - Se mantiene el circuito actual.
   - Quien revisa ve la ficha en solo lectura, con los cambios marcados.
   - Solo puede dejar observaciones y elegir «Aprobar» o «No aprobar»: no puede editar nada. Esto lo valida la
     base, no la pantalla. Verificá cómo está hoy y probalo.

EDICIÓN (ADR-0039)
- Se edita donde se ve.
- Una barra fija abajo con el contador de cambios, el motivo obligatorio, Descartar, Guardar cambios (todo en una
  sola transacción, con auditoría) y Enviar a revisión.
- Aviso de cambios sin guardar al salir.
- Una versión publicada no se edita: al editar se trabaja sobre el borrador.

PERMISOS Y SEGURIDAD
- Precios y costos, solo con el permiso de costos que ya existe. El cocinero ve la ficha desde la vista sin
  precios: en ese caso no aparecen las columnas de dinero.
- Las columnas de escala son solo cálculo: no se guardan como dato oficial. Si querés recordar los números
  4 y 10, proponelo en el plan.

SE MANTIENEN
- «Costos» en Gestión y análisis de la barra lateral (después se desarrolla el reporte).
- Las páginas de cocina y escalar.

DISPOSITIVOS
- Diseñada para 1440, 1600 y 1920 px.
- En el celular, la ficha es de consulta: datos, ingredientes en tarjetas, totales y pasos. No es la planilla
  achicada.

PRUEBAS
- Vitest:
  - precio por unidad grande;
  - costo por renglón;
  - incidencias;
  - escala;
  - porciones;
  - rendimiento;
  - casos sin precio o sin conversión.
- pgTAP:
  - guardado en lote;
  - el revisor no edita;
  - rendimiento guardado en la versión;
  - RLS por rol.
- Playwright con axe, en celular y computadora:
  - cargar un plato de punta a punta;
  - cargar una preparación con peso neto;
  - el autocompletado por código y por nombre;
  - la fila 11 que aparece sola;
  - el revisor sin poder editar.
- Las pruebas que hoy usan las pestañas se ajustan a la ficha nueva sin perder lo que controlan.

ENTREGA
ADR nuevo, docs/estado.md, los tres revisores, capturas en 1440, 1600, 1920 y celular, y un resumen en simple
para Soy. Preguntame ante cualquier duda de negocio.
```

---

## Prompt 3: ficha única de materia prima

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/ y los ADR 0029, 0036, 0038, 0039 y 0040, y mirá
app/materias-primas/[id]/page.tsx. Modo plan y método de 6 pasos. Rama nueva: feat/ficha-unica-materia-prima.
Requiere el Prompt 1 fusionado y conviene el Prompt 2, para reutilizar sus componentes de ficha. Boceto:
pantalla 5 de docs/prompts/2026-11-12-fichas-unicas-recetas-y-materias-primas.md.

OBJETIVO
Reemplazar las 6 pestañas de la materia prima por UNA SOLA FICHA con el mismo diseño que la ficha de receta.
Se mantienen todos los campos, reglas, permisos y aprobaciones que ya existen; solo cambia la forma de mostrarlos
y cargarlos.

ESTRUCTURA
1. Encabezado: código, estado, nombre, rubro, unidad de recetas e índice de secciones.
2. Datos generales: nombre, rubro, «Se usa en recetas en» con la lista completa de catalog.units, «Se compra
   en», otros nombres y observaciones.
3. Precios de compra.
   - Precio vigente y costo neto con merma, destacados.
   - La tabla de productos de compra: proveedor, envase, contenido, precio, precio por kg o l, fecha y estado
     de vencimiento.
   - «+ Agregar producto de compra».
4. Mermas y rendimientos.
   - Los 4 indicadores de ADR-0040 y el interruptor «¿Se compra congelada?».
   - La tabla de rendimientos por proceso.
   - «Proponer merma o rendimiento» con la aprobación que ya existe.
5. Conversiones.
6. Alérgenos.
7. Dónde se usa.

EDICIÓN
- La barra fija abajo, con contador, motivo, Descartar y Guardar cambios, guardando en lote y con auditoría
  (ADR-0039).
- Lo que hoy pide aprobación sigue pidiéndola. Lo que pide prices.configure, también.

DISPOSITIVOS
Computadora 1440, 1600 y 1920. En el celular, de consulta.

PRUEBAS
- pgTAP para el guardado en lote, si hace falta una función nueva, y para RLS por rol.
- Playwright con axe, en celular y computadora: editar datos, agregar un producto de compra, proponer una merma
  y agregar una conversión desde la misma ficha.
- Las pruebas viejas de pestañas se ajustan sin debilitarse.

ENTREGA
ADR nuevo, docs/estado.md, los tres revisores, capturas y un resumen en simple para Soy.
```
