# Ficha única de receta: lista de lo que cambia (para Soy)

Pedido: «Fichas únicas de recetas y materias primas», Prompt 2. Decisión técnica: ADR-0042. Rama: `feat/ficha-unica-receta`.

## En pocas palabras

- **Una sola ficha, sin pestañas.** La receta entera está en una página que ocupa toda la pantalla. Arriba hay un índice que lleva a cada parte:
  1. datos generales;
  2. ingredientes y costos;
  3. rendimiento;
  4. procedimiento;
  5. alérgenos;
  6. dónde se usa;
  7. versiones y aprobaciones.

  A la derecha del encabezado están las fotos, con flechas ‹ › para pasarlas y «Agregar foto».

- **Los ingredientes se cargan como en una planilla:**
  - arranca con 10 filas y, al completar la última, aparece otra;
  - se escribe el código o el nombre y se elige de la lista (las preparaciones dicen «Preparación» y llevan a su ficha);
  - en cada fila se ven la medida, el peso y el costo de hacer 4 y 10 recetas (los números se pueden cambiar), el precio por kg o por litro, lo que cuesta en la receta y cuánto pesa en el costo y en el peso total;
  - abajo van el total, el peso total de la receta y el costo total sin IVA.
- **Nunca un número inventado.** Si falta un precio o no se sabe pasar algo a gramos (por ejemplo, leche en ml sin su densidad), la celda muestra «—» y, al pasar el mouse, dice qué falta. El total avisa que está incompleto. Nunca aparece $ 0.
- **Rendimiento:**
  - **En un plato** se carga el peso de la porción y el sistema calcula cuántas porciones salen y cuánto cuesta cada una.
  - **En una preparación** se ve el peso bruto (la suma de los ingredientes), se carga el peso neto (lo que queda al terminar) y el sistema calcula el rendimiento en % y el costo por kg neto.
  - Ese rendimiento queda guardado al aprobar la receta: es contra lo que se van a comparar los lotes cuando exista el control de producción.
- **Se edita donde se ve y se guarda todo junto.**
  - Abajo hay una barra fija que cuenta los cambios, pide un solo motivo y tiene «Descartar», «Guardar cambios» y «Enviar a revisión».
  - Si la receta ya está vigente, al guardar se crea un borrador nuevo. Lo que usan las cocinas no cambia hasta que se apruebe.
  - Si alguien intenta salir con cambios sin guardar, se le avisa.
- **Quien revisa** ve la ficha sin poder tocarla, con los cambios marcados, y deja sus observaciones con «Aprobar» o «No aprobar». El sistema no deja editar en la revisión, ni aprobar a la misma persona que la pidió.
- **En el celular** la ficha es para consultar: datos, ingredientes en tarjetas, totales y pasos. Las aprobaciones siguen funcionando en el celular.

## Decisiones de Joaco

- **El precio por kg o por litro** lo ven solo quienes ya veían precios (Gerente, Compras y Dirección). Los chefs ven el costo de cada fila y los totales, como hasta ahora.
- **Los platos ya cargados** conservan sus porciones hasta que alguien cargue el peso de la porción. Desde ese momento se calculan solas.
- **El costo mientras se carga** lo ve solo quien puede editar o aprobar esa receta. Quien solo mira costos los ve en «Costos», con lo ya guardado.
- **Si un ingrediente no se puede pasar a gramos**, el plato se guarda igual y avisa que las porciones no se recalcularon. Para mandarlo a revisión, hay que completar ese dato.

## Lo que no cambia

- **Los costos de las recetas son los mismos:** los calcula el mismo sistema de siempre.
- **El circuito de aprobación es el mismo:** borrador, revisión por otra persona y publicación.
- **Siguen igual** «Costos» en el menú, la ficha de cocina y Escalar.
- **Cada cambio queda en el Historial,** con quién, cuándo y por qué.
