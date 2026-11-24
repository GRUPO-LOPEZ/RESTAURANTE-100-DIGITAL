# Configuración del catálogo (lista de cambios para Soy)

Primera de las cuatro entregas de la **Tanda 2** (Base de conocimiento). Detalle técnico en ADR-0063. Capturas en `docs/capturas/catalogo-listas/`.

## Todas las listas en una pantalla

- **A la izquierda**, las 8 listas con cuántos elementos tiene cada una. **A la derecha**, la que elegís.
- **Se edita en la tabla** y se guarda todo junto, con un motivo.
- «Agregar» suma una fila. Cada fila se puede deshacer.
- **Dar de baja no borra:** lo inactivo se ve con un botón y se puede reactivar.

## Cuatro listas nuevas

- **Sectores:** Cocina caliente, Cocina fría, Pastelería.
- **Partidas:** Pastas, Salsas, Parrilla.
- **Equipos, con su capacidad:** Pastera (6 canastos), Horno combi (10 bandejas GN 1/1).
- **Medidas prácticas, con lo que contienen:** Cucharón 120 ml, Taza 240 ml, Cucharada 15 ml, Cucharadita 5 ml, Nido de pasta 120 g.

Son las que nombraste vos. **El resto lo agregan ustedes desde la pantalla.**

## Lo que ya estaba escrito en las recetas

- Los sectores, partidas y equipos que estaban como texto pasaron a las listas.
- **Las versiones publicadas no se tocaron:** dicen lo mismo que decían.
- Si cambia el nombre de un **sector o una partida**, cambia en todas las recetas que lo usan (la pantalla avisa en cuántas). El de un **equipo**, solo en los borradores.
- Las **unidades de medida no cambian de nombre**, porque las usan las recetas publicadas: se da de baja y se crea otra.

## Quién edita

- Sectores, partidas, equipos y medidas: Compras, el Chef Ejecutivo y el Superadministrador.
- Las otras listas, como antes. Cada uno ve las demás en lectura.

## Todavía no

- **Elegir** el sector, la partida, el equipo y la medida en la receta: llega en la próxima entrega.
