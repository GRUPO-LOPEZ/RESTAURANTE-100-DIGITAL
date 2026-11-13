# Fichas sin scroll: materia prima y receta (pedido de Soy, 2026-11-13)

Dos prompts, en orden, un PR cada uno. Se corren **después** del Inicio sin scroll (`2026-11-13-inicio-sin-scroll.md`), porque reutilizan lo que arma ese PR: la regla única de estado (Crítico si falta más de la mitad) y el patrón de pantalla en una sola vista.

Boceto aprobado: `docs/prompts/2026-11-13-boceto-fichas-sin-scroll/` (y el enlace en su README).

## Decisiones de Soy

- **Todas las pantallas siguen los mismos criterios** que el Inicio, Recetas, Materias primas y Rubros: la misma apariencia, el mismo uso y nada repetido.
- **La ficha de materia prima entra entera en 1440 × 900, sin scroll.** Boceto aprobado.
- **Alérgenos:** un botón por alérgeno que cambia de estado con cada clic (Sin dato → No contiene → Puede contener → Contiene), cada estado con su color y su palabra. Reemplaza a los 4 botones por alérgeno, que no entran sin scroll.
- **La ficha de receta tampoco tiene scroll de página.** La planilla de ingredientes es la única parte con su propio scroll, como una hoja de cálculo. Boceto aprobado: `FichaRecetaSinScroll.dc.html`.

## El patrón común (va en los dos prompts)

Esto es «una pantalla de carga sin scroll». Se documenta en `.claude/rules/design.md` en el Prompt 1, y el Prompt 2 lo reutiliza:

1. **Encabezado en una línea:** «← Volver», nombre, código, rubro y estado. La acción secundaria (por ejemplo, Desactivar) es un botón a la derecha, no un desplegable.
2. **4 indicadores arriba** con `Metric`. No se repiten más abajo.
3. **Tarjetas en columnas** que ocupan el alto que queda. Se edita donde se ve.
4. **Las listas se cortan** en 3 a 5 filas con «Ver los N …», que abre el panel lateral. La pantalla no crece con los datos.
5. **Barra fija abajo:** contador, motivo obligatorio, Descartar y Guardar cambios. Es la de hoy, sin cambios.
6. **Se prueba en 1440 × 900, 1600 × 900 y 1920 × 1080.** En celular sigue siendo de consulta, con scroll.

---

## Prompt 1: ficha de materia prima sin scroll

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md, docs/decisiones/0043 y el boceto aprobado
docs/prompts/2026-11-13-boceto-fichas-sin-scroll/FichaMateriaPrima.dc.html.
Tarea: que la ficha de materia prima (app/materias-primas/[id]/page.tsx y
components/ingredient-sheet/) entre entera en una pantalla, sin scroll. Rama:
feat/ficha-materia-prima-sin-scroll. Entrá en modo plan y mostrame el plan antes de tocar nada.

QUÉ NO CAMBIA
- La base: catalog.save_ingredient_sheet, los permisos, las aprobaciones y los paneles de alta
  (producto, proveedor, merma o rendimiento, ensayo, precio) siguen como están. Si te parece que
  hace falta una migración, parás y me preguntás.
- Las reglas de ADR-0043: unidad trabada con precios, rubro trabado, «Cómo se compra» para quien
  no ve precios, dejar de comprarla congelada pide aprobación.
- Los enlaces de antes (Calidad, ?seccion=, #anclas) siguen funcionando: en vez de bajar a la
  sección, llevan el foco a su tarjeta y la marcan.
- El celular sigue siendo de consulta (puede tener scroll).

DISPOSICIÓN (1440 × 900, ver el boceto)
1. Encabezado en una línea: «← Materias primas», nombre, código · rubro · «se usa en gramos»,
   chip de estado (Activa) y a la derecha el botón «Desactivar» (sale del desplegable de hoy).
   Se van el subtítulo «Cómo se compra, cómo se mide…» y el índice de botones: ya se ve todo.
2. 4 indicadores (Metric): Precio vigente (con el local), Costo neto por kg (con merma y
   descongelado), Rinde neto y Recetas que la usan. Sin dato: «—», el motivo y «Sin datos».
   Estas tarjetas reemplazan a las 2 de «Precios de compra» y a las 4 de «Mermas y rendimientos»
   de hoy: no se repiten abajo.
3. Tres columnas (4/12, 5/12, 4/12) que ocupan el alto que queda:
   a. Datos generales: Nombre; Rubro y «Se usa en recetas en» en una fila; Se compra en;
      «¿Se compra congelada?» como toggle de un clic (ToggleField); Otros nombres como chips
      con ✕ y «+ Agregar»; Observaciones, que ocupa lo que sobra.
   b. «Precios de compra»: se unifica con la tarjeta «Precios» de hoy (son dos tarjetas que dicen
      lo mismo). Arriba, el aviso amarillo si no hay precio que valga en el local. Hasta 3
      productos (proveedor · presentación, precio por kg/l/u y estado con palabra) y «Ver los N
      productos». Botones: «+ Producto de compra», «+ Proveedor», «Proponer precio».
      Debajo, «Mermas y rendimientos»: merma de limpieza y de descongelado (valor y estado), una
      línea con el resumen de rendimientos por proceso y «Ver todos», y los botones «Proponer
      merma o rendimiento» y «Registrar un ensayo».
   c. «Conversiones» (filas cargadas o «No aplica» con el motivo, y los dos botones de alta),
      «Alérgenos» (los 14 en una grilla de 2 columnas, un botón por alérgeno que cambia de estado
      con cada clic: Sin dato → No contiene → Puede contener → Contiene, con colores none, ok,
      warn y bad y siempre con la palabra; aria-label «Gluten: Contiene. Cambiar»; el origen del
      dato que hoy se elige al lado pasa a un tooltip o al panel, decidilo en el plan y mostrame
      cómo) y «Dónde se usa» (hasta 3 recetas con su cantidad y «Ver las N recetas»).
4. La barra fija de abajo no cambia. La celda o el campo cambiado lleva el borde punteado.
5. Los paneles laterales de alta, igual que hoy.

PATRÓN COMÚN
Agregá a .claude/rules/design.md una sección «Pantallas de carga sin scroll» con los 6 puntos del
patrón común de docs/prompts/2026-11-13-fichas-sin-scroll.md, y su ADR. Si en el PR del Inicio
quedó un componente o una función reutilizable (la regla de estado, la lista cortada con «Ver
los N»), usala; si no existe, creala en components/ui/ y que la use el Inicio también.

PRUEBAS
- Playwright con axe (ficha-materia-prima.spec.ts y los specs que tocan la ficha):
  * en 1440 × 900, 1600 × 900 y 1920 × 1080, con el seed y con una materia prima con muchos
    datos (5 productos, 4 rendimientos, 7 recetas): el área principal no tiene scroll vertical;
  * cada alérgeno cambia de estado con un clic y aria-pressed/aria-label lo reflejan;
    el contador suma; guardar con motivo lo deja en la auditoría;
  * el toggle de congelada en un clic; dejar de comprarla congelada sigue pidiendo aprobación;
  * los enlaces de Calidad y ?seccion= llevan a su tarjeta;
  * quien no tiene catalog.manage la ve sin poder editar; quien no ve precios no ve dinero;
  * celular: consulta, controles de 44 px o más.
- Las pruebas que buscaban el índice o las 4 opciones por alérgeno se ajustan para controlar lo
  nuevo. No se borran ni se aflojan.
- Corré todo (npm run test). No recrear la base mientras corre Playwright.

ENTREGA
ui-reviewer (y security-auditor si cambia qué ve cada rol). Capturas reales en 1440, 1600, 1920
y celular, guardadas como PNG en docs/capturas/ficha-materia-prima-sin-scroll/ y commiteadas en
el PR (Soy las revisa desde GitHub). ADR nuevo. Lista de cambios para Soy en docs/modulos/.
docs/estado.md. PR chico. Commit: «feat(materias-primas): ficha en una pantalla sin scroll».
```

---

## Prompt 2: ficha de receta sin scroll de página

```text
Leé docs/estado.md, CLAUDE.md, .claude/rules/design.md (con la sección nueva «Pantallas de carga
sin scroll» del PR anterior), docs/decisiones/0042, la ficha de materia prima ya hecha y el boceto
aprobado docs/prompts/2026-11-13-boceto-fichas-sin-scroll/FichaRecetaSinScroll.dc.html.
Tarea: que la ficha de receta (app/recetas/[id]/page.tsx y components/recipe-sheet/) entre en
una pantalla sin scroll de página. La planilla de ingredientes es la única parte con scroll
propio, como una hoja de cálculo. Rama: feat/ficha-receta-sin-scroll. Entrá en modo plan y
mostrame el plan antes de tocar nada. Si algo del boceto no se puede hacer igual, decímelo en el
plan con el motivo.

QUÉ NO CAMBIA
- La base: recipes.save_sheet, costing.preview_sheet_lines, los permisos (precio por kg solo
  con prices.view; costo de filas sin guardar solo para quien edita o publica), la revisión en
  solo lectura y el circuito de versiones. Si hace falta una migración, parás y me preguntás.
- La planilla: 10 filas que suman una al llenar la última, autocompletar por código y nombre,
  columnas de 4 y 10 recetas, precio por kg/l, costo, incidencias, «—» con motivo y nunca $ 0.
- Los enlaces de antes (?seccion=, #anclas, Calidad) llevan el foco a su tarjeta.
- El celular sigue siendo de consulta (puede tener scroll).

DISPOSICIÓN (1440 × 900, ver el boceto)
1. Encabezado en una línea: «← Recetas», nombre, código · rubro · Plato o Preparación, chip de
   versión y estado (Vigente v2, Borrador, En revisión), y a la derecha «Ficha de cocina» y
   «Escalar». En revisión, debajo, una franja violeta (review) en una línea: quién pidió la
   versión, cuándo y su motivo.
2. 4 indicadores (Metric):
   - en un Plato: Costo total, Costo por porción, Peso total y Porciones;
   - en una Preparación: Costo total, Costo por kg neto, Peso bruto → neto y Rendimiento %.
   Si el costo está incompleto: «—» y el motivo, nunca un número supuesto.
3. Dos columnas:
   a. Izquierda (el ancho que queda), alta: la planilla, con encabezado fijo y la fila de
      totales fija abajo (con su estado: «Completo» o «Incompleto: falta N dato»). Solo el cuerpo
      de la planilla hace scroll. Los números de las escalas (4 y 10) se editan en el encabezado
      de su columna. Con teclado, el foco que baja de fila la lleva a la vista. En revisión, las
      filas cambiadas van en fondo review con «antes 380 g» o «nuevo».
   b. Derecha (300 px), de arriba hacia abajo:
      - Fotos (carrusel chico con ‹ ›) y Datos generales compactos (rubro, alcance, + Agregar
        foto), en una tarjeta.
      - Rendimiento: el peso de la porción (Plato) o el peso neto (Preparación), editable.
      - Procedimiento: pasos numerados, hasta los que entren, y «Ver los N pasos» o edición en el
        panel lateral. Decidí en el plan si los pasos se editan en la tarjeta (con su propio
        scroll) o en el panel, y explicá por qué.
      - Una franja de resumen con Alérgenos (los que contiene, que salen de las materias primas),
        Dónde se usa (cantidad y «Ver») y Versiones y aprobaciones (versión, estado y «Ver el
        historial»), cada uno con su panel lateral.
4. Quien revisa ve lo mismo en solo lectura, con los cambios marcados, y decide con Aprobar /
   No aprobar en la barra de abajo, en vez de Guardar.
5. La barra fija de abajo no cambia: contador, motivo, Descartar, Guardar y Enviar a revisión.

PRUEBAS
- Playwright con axe (ficha-receta.spec.ts y los specs que tocan la ficha):
  * en 1440 × 900, 1600 × 900 y 1920 × 1080, con una receta de 25 ingredientes y 12 pasos:
    la página no tiene scroll vertical y la planilla sí lo tiene (su scrollHeight > clientHeight);
    la fila de totales sigue a la vista;
  * cargar una fila nueva con el teclado y que aparezca la fila 11;
  * Plato y Preparación muestran sus 4 indicadores;
  * quien revisa no puede editar y decide desde la barra;
  * los enlaces de Calidad y ?seccion= llevan a su tarjeta;
  * celular: consulta, controles de 44 px o más.
- Las pruebas que se rompan por la nueva disposición se ajustan para controlar lo mismo. No se
  borran ni se aflojan. Corré todo (npm run test).

ENTREGA
ui-reviewer y security-auditor. Capturas reales en 1440, 1600, 1920 y celular, de un Plato y de
una Preparación, en edición y en revisión, guardadas como PNG en
docs/capturas/ficha-receta-sin-scroll/ y commiteadas en el PR. ADR nuevo. Lista de cambios para Soy en docs/modulos/.
docs/estado.md. PR chico. Commit: «feat(recetas): ficha en una pantalla con planilla con scroll propio».
```
