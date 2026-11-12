# Códigos automáticos y listados por rubro: lista de lo que cambia (para Soy)

Pedido: «Fichas únicas de recetas y materias primas», Prompt 1. Decisión técnica: ADR-0041. Rama: `feat/codigos-y-listados-por-rubro`.

## En pocas palabras

- **El código lo pone el sistema.** Nadie lo escribe más:
  - un plato de Cafetería sale `PLA-CAF-0001`;
  - una salsa, `PRE-SAL-0001`;
  - una carne que se compra, `MPR-CAR-0001`.

  El número sigue solo dentro de cada tipo y rubro.

- **Se ve antes de crear.** Al elegir el tipo y el rubro, la ventana muestra el código que va a salir. Si justo otra persona creó una receta del mismo rubro, se le da el siguiente número y la ficha lo avisa.
- **El código no cambia nunca,** aunque después la receta cambie de rubro. Un número de algo que se borró no se vuelve a usar.
- **Solo Plato o Preparación.** «Componente por unidad» ya no se ofrece al crear, y lo que ya estaba cargado se muestra como Preparación.
- **Recetas y Materias primas ordenadas por rubro.**
  - Arriba van las tarjetas de los rubros, iguales a las de Rubros, con cantidad y porcentaje. Un clic en una tarjeta muestra solo ese rubro, y otro clic (o la ✕) vuelve a mostrar todo.
  - En Recetas hay dos botones: Platos y Preparaciones, cada uno con su cantidad.
  - La tabla muestra código, nombre, rubro, alcance, estado y costo.
- **Unidad de las materias primas.** Al crearlas se puede elegir cualquier medida («Kilogramo (kg)», «Litro (l)», «Docena»…). El sistema avisa en qué la calculan las recetas: gramos, mililitros o unidades.

## Decisiones de Joaco

- **Pasado el 9999** sigue con 5 números (`PLA-CAF-10000`), sin frenar a nadie.
- **Una variante de un local** lleva el código de su receta con `-V01`, `-V02`… Por ejemplo, `PLA-PAS-0001-V01`.
- **Las recetas que se importan desde el Excel** conservan su código de la planilla, para poder encontrarlas en el archivo original.

## Lo que no cambia

- **Los códigos que ya existen no se tocan.**
- **Los costos quedan iguales.** Se comprobó con todas las recetas de prueba.
- **Quién puede crear recetas y materias primas** es lo mismo que antes.
- Cada alta queda en el **Historial**: quién, cuándo y por qué.
