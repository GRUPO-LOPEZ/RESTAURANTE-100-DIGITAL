# ADR-0064 — Ficha de receta: medida práctica, listas del grupo y materia prima nueva sin salir

- **Fecha:** 2026-11-24
- **Estado:** plan aprobado por Joaco (2026-11-24).
- **Pedido:** Tanda 2 de Soy, punto B (`docs/prompts/2026-11-22-correcciones-modulo-1.md`, boceto `Main.dc.html`). Sigue al ADR-0063.

## Decisión

1. **Medida práctica por línea** («480 g · 4 nidos»). Se guarda cuántas van, con el nombre y lo que contiene la medida en ese momento.
   - La cuenta está en un solo lugar (`recipes.measure_count_for`; `lib/measures.ts` la repite en pantalla y manda la base): peso con peso, volumen con volumen, unidades con unidades. Peso con unidades, solo con el peso por unidad. **Nunca con la densidad.**
   - **Lo que no es borrador queda congelado** (decisión de Joaco). Los borradores siguen la lista, salvo lo corregido a mano.
   - Una medida en uso no cambia de clase (de peso a volumen). Si se achica tanto que un borrador pasaría el millón de medidas, la lista lo rechaza; si no hay borradores, una versión nueva conserva el número, como corregido a mano.
   - Quien revisa ve qué medida cambió (`recipes.version_measure_diff`).
2. **Sector, partida y equipo se eligen de las listas** (por su id: un borrador abierto mientras cambia un nombre no pierde el vínculo). Un texto fuera de la lista se conserva hasta elegir otro; un inactivo sigue donde ya estaba.
   - **Sector y partida, en el panel «Editar datos»**, no en la tarjeta como el boceto: la columna derecha no entraba sin scroll.
   - El equipo trae su capacidad si está en una unidad como la del rendimiento; en palabras, se muestra al lado.
3. **«Nueva materia prima» desde la receta**, con un permiso nuevo, `catalog.create_ingredients`, para todo el grupo (decisión de Joaco): Compras, Superadministrador y Chef Ejecutivo. La Directora de Marca lo tiene por la regla G2, pero con rol de marca la base la rechaza.
   - Solo nombre, rubro que va a recetas y unidad; sin precio. Muestra las parecidas y avisa a quien administra el catálogo (`ingredient_created`). Hasta 30 por hora por persona.
4. **Planilla de 8 renglones**, con las columnas más angostas. Se conservan Código, las dos «Hacer» y los 4 indicadores. Sin dinero entra en 1440; con dinero se desplaza dentro de su tarjeta (175 px en 1440; antes, 296).
5. **«Versión 3 · Borrador»** y «vigente: versión 2 del …» en el encabezado y en el listado.

## Revisiones (2026-11-24)

- **`db-reviewer`, 2 graves:** achicar una medida trababa recetas, y guardar la lista se cruzaba con guardar una receta. Corregidos: tope en la cuenta, y `recipes.share_measures` (un candado compartido que se toma antes de bloquear la versión). Segunda pasada: los dos resueltos, probado con tres sesiones a la vez; corregidos también los medios que sumó.
- **`security-auditor`, sin graves;** los 2 medios corregidos: la limpieza del nombre en todas las altas y el largo de la búsqueda de parecidas.
- **`ui-reviewer`, 1 grave:** la materia prima nueva podía pisar un renglón a medio cargar. Corregido, con los medios.

## Pruebas

- **La suite completa de Playwright la corre GitHub Actions y no la máquina local:** excepción de Joaco (2026-11-24), por falta de memoria. En local se corrió lo que toca este PR: 58 bien, 19 salteadas y 1 falla por lentitud (la base había guardado; pasa 3 de 3).

## Pendiente, anotado

- En 1440, con cambios sobre una receta publicada, la barra de abajo se parte en dos renglones.
- En un borrador con nombre largo, el encabezado pasa a dos renglones en 1440 (la página sigue sin scroll). En 1715 × 843, la columna derecha se desplaza adentro unos 10 px.
- La planilla sigue en `sheet-editor.tsx`: el plan la separaba, y moverla sumaba riesgo sin cambiar nada a la vista.
- Si cambia el peso por unidad de una materia prima, los borradores se ponen al día al guardarlos o al pedir la revisión.
- Un elemento inactivo mandado como texto (importación) se vincula igual.
- Editar una materia prima (`catalog.update_ingredient`) no limpia el nombre como el alta.
- El volumen del registro de rechazos (patrón de `core.deny`).
