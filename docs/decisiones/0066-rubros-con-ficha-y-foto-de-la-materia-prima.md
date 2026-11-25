# ADR-0066 — Rubros con ficha, materias primas en una pantalla y foto del producto

- **Fecha:** 2026-11-25
- **Estado:** plan aprobado por Joaco (2026-11-25).
- **Pedido:** Tanda 2 de Soy, punto D (`docs/prompts/2026-11-22-correcciones-modulo-1.md`, bocetos `MateriasPrimas`, `Rubros` y `FichaMP`). Va en dos PR: este (D1) y D2, «Proponer precio» y subpantallas. Cambia las pantallas de los ADR-0038, 0041 y 0052.

## Decisión

1. **Ícono y descripción del rubro**, solo en el primer nivel (`catalog.category_icon`, 14 íconos: con 12 no alcanzaba para compra, preparaciones y carta). Si no se elige, el de su código.
2. **Un panel de rubros** (`components/rubro-panel.tsx`) para Materias primas y Rubros: 250 px, fijo; si no entran, se desplaza adentro. Los que no se usan, plegados («Sin uso»). Por debajo de 1.280 px, una fila deslizable (con un corte en 800, una tablet o el zoom dejaban la tabla sin lugar).
3. **La ficha del rubro se guarda junta, con motivo** (`recipes.save_top_category`, con sello). El nombre y «va a recetas» dejan de guardarse con un clic y un motivo fijo, y sus dos funciones de antes se quitan: eran otro camino para lo mismo, sin sello. Los permisos no cambian (`recipes.can_manage_category`).
4. **El precio vigente en la lista y «Con precio al día»**, con el motor de costos (`costing.resolve_prices`, `costing.price_rows`), en el local de arriba y solo para quien ve precios (decisión de Joaco). Con precios, el «Estado» de la fila es el del precio (como en el boceto) o «Desactivada»: así la tabla entra en 1440.
5. **Foto:** una vigente por materia prima, en el bucket de las fotos de recetas y con permisos propios. Ruta `<grupo>/ingredients/<materia prima>/<archivo>`: la segunda carpeta no es un identificador, así que las políticas de recetas no la alcanzan. La cambia `catalog.manage`; la vigente la ve quien ve la materia prima; la historia, solo quien edita. Se aplica al subirla: un archivo no viaja en el guardado en lote. Se puede cambiar en una materia prima desactivada, como el resto de su ficha; de una borrada no se ve.
6. **Lo escrito no se pierde:** buscar u ordenar no cambian la ficha abierta (el rubro queda en la dirección) y «Atrás» pregunta, en todas las fichas (`components/use-unsaved-warning.ts`, con el evento «navigate» del navegador: con popstate, Next ya había cambiado de pantalla). Donde el navegador no lo tiene, sale sin preguntar, como antes.
7. **Los íconos de los rubros ya cargados** se completan también en los borrados: si no, restaurar uno fallaba.
8. **La lista de Recetas no cambia** (decisión de Joaco): sigue con las tarjetas.

## Opciones descartadas

- **Un bucket nuevo:** más políticas y configuración por ambiente para el mismo tipo de archivo.
- **«Precios que maneja: por kg · IVA 10,5 %»** (boceto): el sistema no guarda ese dato.
- **Que los números del panel sigan la búsqueda:** dicen el tamaño del rubro.
- **«Heredado» en la lista:** ahí la pregunta es si el precio está al día; la ficha ya lo dice.
- **Un desplegable en el celular:** con los «Sin uso» plegados, la fila alcanza (Soy aceptó las dos formas).
- **Probar con 300 materias primas en el navegador:** la lista muestra hasta 50 por página. El volumen se mide en la base (500: 41, 30 y 45 ms).

## Pendiente, anotado

- La foto en la ficha de recepción (el boceto la menciona; el prompt, no).
- Un archivo subido que no se llega a registrar queda en el bucket (como en recetas): no se borra y solo lo ve quien edita.
