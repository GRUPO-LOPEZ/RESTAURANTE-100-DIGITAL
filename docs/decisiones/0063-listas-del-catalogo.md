# ADR-0063 — Configuración del catálogo en una pantalla: sectores, partidas, equipos y medidas prácticas

- **Fecha:** 2026-11-24
- **Estado:** plan aprobado por Joaco (2026-11-24).
- **Pedido:** Tanda 2 de Soy, punto A (`docs/prompts/2026-11-22-correcciones-modulo-1.md`, boceto `Configuracion.dc.html`). Es el primero de 4 PR.

## Contexto

- El sector y la partida de la receta, y el equipo de cada paso, eran texto libre. No había medidas prácticas.
- La pantalla tenía 4 listas, con un plegable y un motivo por cada cambio.

## Decisión

1. **Cuatro tablas nuevas del grupo**, en `catalog`: `kitchen_sectors`, `kitchen_stations`, `kitchen_equipment` y `practical_measures`.
   - El nombre es único sin distinguir mayúsculas, tildes ni espacios de más (`catalog.list_key`).
   - Nada se escribe directo: solo con `catalog.save_settings_list`.
   - La leen quienes ven el catálogo o las recetas.
2. **Quién edita** (`catalog.can_manage_list`, un solo lugar, sin permisos nuevos):
   - las listas que ya existían, como antes;
   - las cuatro nuevas, `catalog.manage` **o** `recipes.manage_categories` para todo el grupo (Compras, Superadministrador y Chef Ejecutivo).
   - Opción descartada: solo `catalog.manage`. El Chef Ejecutivo no podría agregar una partida.
3. **Quién ve:** quien administra al menos una lista ve las 8. Las ajenas, en lectura.
4. **Con qué nacen:** solo lo que nombró Soy (ADR-0022: nada llega por migración sin que lo apruebe). El resto se agrega desde la pantalla.
5. **El texto pasa a las listas sin tocar la historia:**
   - un elemento por cada texto distinto;
   - se vinculan las recetas y los pasos **en borrador**; los de una versión que ya no es borrador quedan iguales;
   - el texto queda como nombre congelado de cada versión. La receta y los borradores siguen el nombre de la lista (`recipes.follow_list_name`);
   - una versión nueva se vincula sola al copiarse;
   - hasta el PR B la ficha manda texto: la base lo vincula si coincide (`recipes.link_lists`).
   - Opción descartada: reemplazar el texto por el vínculo. Cambiaría lo que dice una versión publicada.
6. **La capacidad de un equipo va en una unidad del sistema o en palabras.** «6 canastos» no es una unidad: se muestra y no entra en la cuenta de tandas.
7. **La medida práctica contiene una cantidad en una unidad base** (ml, g o unidades). Cuánto va en cada receta es del PR B.
8. **Un solo guardado para las 8 listas**, con motivo y sello. Donde ya había funciones (subcategorías, procesos, unidades), las usa: las reglas no se repiten.
   - Las listas de la cocina se desactivan aunque estén en uso: dejan de ofrecerse y lo que las usa no cambia.
   - Las subcategorías, los procesos y las unidades siguen con su regla (nada en uso), y ahora **se reactivan**.
   - Los rubros se dan de baja en Rubros (pueden pedir destino).
9. **En el celular, de consulta** (ADR-0036).

10. **El nombre de una unidad no cambia**, ni siquiera el de una cargada a mano: lo leen las recetas publicadas y los pedidos. Para corregirla se da de baja y se crea otra.
11. **El sector y la partida no son datos de la versión:** cambiar el nombre en la lista lo cambia en todas las recetas que lo usan, también en las publicadas. La pantalla avisa en cuántas. **Confirmado por Joaco (2026-11-24).**

## Revisiones (2026-11-24)

- **`db-reviewer` (1 grave) y `security-auditor` (el mismo grave):** la primera versión dejaba renombrar unidades en uso. Se sacó (punto 10).
- **Medios corregidos:**
  - una equivalencia `NaN` (venía de antes) se rechaza en la tabla y en el guardado;
  - un texto que es solo un espacio duro no corta la migración;
  - una versión que vuelve a borrador toma los nombres de hoy (`recipes.refresh_list_names`);
  - los usos de un sector cuentan también los pasos;
  - los nombres se controlan igual en las 8 listas (`<`, `>` y caracteres que no se ven).
- **`ui-reviewer` (1 grave: desborde en el celular, en lectura):** corregido, con los 11 medios (foco, errores asociados, filas que saltaban, obligatorios marcados).

## Pendiente, anotado

- **Un grupo nuevo necesita `catalog.install_default_lists` en su alta**, igual que `recipes.install_default_categories`. Hoy hay un solo grupo.
- **Las unidades son de todo el sistema** (no tienen grupo): antes de un segundo grupo hay que decidir quién las administra.
- **Las funciones de antes** (`create_category`, `create_unit` y las demás) siguen abiertas a la API: controlan permisos, pero no llevan sello. Revocarlas toca sus pruebas: PR aparte.
- **El registro de rechazos no tiene tope** (el patrón de `core.deny` en todo el sistema).
- **Intercambiar dos nombres en un mismo guardado** se rechaza por repetido: se hace en dos pasos.
- **La ficha de receta manda texto hasta el PR B:** si alguien la tiene abierta mientras cambia un nombre de la lista, al guardar puede quedar el texto viejo sin vincular.

## Fuera de esta decisión

- Los desplegables de la receta y la cuenta de la medida práctica: PR B.
- Fusionar dos elementos parecidos («Horno» y «Horno 1»).
