# Ficha de receta (lista de cambios para Soy)

Segunda de las cuatro entregas de la **Tanda 2**. Detalle técnico en ADR-0064. Capturas en `docs/capturas/receta-planilla/`.

## La planilla

- **Más compacta:** 8 renglones; al llenar el octavo aparece otro. Botón «Agregar ingrediente».
- **Medida práctica:** elegís la medida y el sistema calcula cuántas van («480 g · 4 nidos»). Se puede corregir a mano y volver al cálculo.
- Solo se ofrecen las medidas que corresponden: peso con peso, volumen con volumen. Nunca pide densidad.
- El cocinero la ve en la ficha de cocina.

## Sin salir de la receta

- **«Nueva materia prima»:** nombre, rubro, unidad y motivo. Queda en el renglón, sin precio, y **Compras recibe un aviso** para completarla. Si ya hay una parecida, la muestra («¿Es esta?»). La crean Compras, el Chef Ejecutivo y el Superadministrador.
- **Sector, partida y equipo** salen de las listas, con «+» para agregar uno (quien edita esas listas).
- El equipo trae su capacidad.

## La versión

- «Versión 3 · Borrador» al lado del nombre, y cuál está vigente y desde cuándo.

## Qué no cambia

- Una receta publicada **queda como está**, aunque cambie una lista.
- Los costos se calculan igual: la medida práctica no los toca.

## Distinto del boceto

- **Sector y partida** se eligen en «Editar datos»: en la tarjeta no entraban sin scroll.
- La planilla conserva el código y las columnas «Hacer», que se trabajan en la próxima entrega.
