# ADR-0024 — Respuestas de Soy a las decisiones de la Fase 2

- **Fecha:** 2026-10-30
- **Estado:** respuestas de Soy, recibidas por Joaco. Lo marcado "a confirmar" es la interpretación técnica, que Joaco confirma con Soy antes de construirlo.
- **Base:** la lista de preguntas que se le pasó a Joaco el 2026-10-29 (16 preguntas, ordenadas por urgencia), el documento de Soy (`docs/fases/fase-2-recetario.md`, sección 22) y el plan de la Fase 2.

## Respuestas y qué cambia

### A. Precios (etapa 2.1 C)

1. **Si un local no tiene precio propio:** se acepta la propuesta. Primero el precio del local, después el de su marca y después el del grupo. **Además, la pantalla dice de dónde viene el precio heredado** ("precio de la marca Demo Pastas", "precio del grupo").

2. **IVA y otros impuestos:**
   - **a) Los costos se calculan sin el IVA recuperable, pero se muestran las dos cifras: con IVA y sin IVA.**
   - **Productos sin factura:** su precio se toma como precio final y no genera crédito fiscal. En el sistema actual del grupo esto se llama "precio ingresado" (en MARIA).
   - **b) Cada local tiene su propia razón social.** Si varios locales comparten una razón social, el costo o la factura se atribuye a la razón social y también al local. La razón social se elige al crear el local.
   - **c) Fletes y otros cargos no se suman al costo del producto:** quedan como un costo aparte, que se analiza al final.

   **Qué cambia:**
   - Hace falta una tabla de **razones sociales** (`org.legal_entities`, con CUIT y condición frente al IVA). Cada local apunta a una, y al crear un local se elige. Esto toca la Fase 1 (`org.restaurants`), con una migración nueva.
   - Cada precio guarda si tiene factura con IVA discriminado o es un **precio ingresado** (sin factura): en ese caso el neto es igual al final y no hay crédito fiscal.
   - Los fletes y cargos se guardan aparte del precio, y no entran en el costo de la receta.

   **A confirmar con Soy:**
   - c) "fletes u otros se dejan como un costo analizable al final": entendemos que no suben el costo de cada ingrediente, sino que se registran y se ven en un reporte aparte. ¿Es así?
   - b) Cuando un local nuevo comparte razón social, ¿alcanza con elegir la razón social existente al crearlo?

3. **Quién aprueba un precio:** Compras lo carga y el Controller lo aprueba (Compras nunca aprueba lo propio). **Dirección aprueba también cuando la variación supera un porcentaje que se configura en el panel de control** (15 %, 8 %, 4 %…).
   - **Qué cambia:** el porcentaje no va fijo en el código. Va en una configuración del grupo, que solo cambia quien tiene permiso, con motivo y auditoría.
   - **A confirmar:** ¿la variación es contra el precio vigente de ese mismo producto, tanto si sube como si baja?

4. **Con qué producto se costea si hay varias marcas o presentaciones:** **sin respuesta.** Sigue pendiente; la propuesta es que Compras elija un producto "preferido" por ingrediente.

5. **Precio desactualizado:** se acepta la propuesta. A los 30 días, ajustable por categoría.

6. **Rendimiento que usa el costo:** siempre el aprobado (como ya está construido en la 2.1 B). **Además: alertas cuando las mediciones se desvían del aprobado**, para controlar las producciones.
   - **Qué cambia:** la ficha ya muestra la diferencia entre ensayos y estándar. Se suma una **alerta** cuando el desvío supera un umbral. Esa alerta va en el tablero de calidad (2.5) y, a futuro, en producción (Fase 3).
   - **A confirmar:** ¿desde qué desvío se alerta (por ejemplo, 3 puntos), y a quién (Chef, Controller)?

### B. Quién ve qué

7. **El Gerente de un local ve los costos y precios de su local, sin poder editarlos:** se acepta la propuesta.
   - **Qué cambia:** el rol Gerente (`restaurant_manager`) suma `recipes.view_costs` y `prices.view` en su local, con una migración nueva. Las pruebas de permisos se actualizan a propósito.

8. **El Superadministrador tiene permisos del recetario:** sí, está bien. Queda como está.

9. **Compras trabaja para todo el grupo.** Puede haber productos que compre excepcionalmente otra persona, por el tipo de producto, pero la tendencia es un solo Compras para todos.
   - **Qué cambia:** nada por ahora; Compras sigue con alcance de grupo.
   - **A confirmar (más adelante, en Compras, Fase 3):** las compras excepcionales, ¿las carga esa persona en el sistema? ¿Qué rol tiene?

### C. Recetas (etapa 2.2 B)

10. **Cuando cambia una salsa o preparación que usan varios platos, los platos cambian solos,** y se avisa al Chef, a la gerencia de Compras y a la gerencia general.
    - **Esto es distinto de la propuesta**, que era atar cada plato a una versión fija de la salsa.
    - **Qué cambia:**
      - una línea de subreceta apunta a la **receta**, no a una versión fija, y siempre usa su versión vigente;
      - al publicar una versión nueva de una preparación, la base lista los platos que la usan y crea avisos para esas personas, con el impacto de costo cuando exista el motor (2.3);
      - el caso 26 del documento se reescribe: "publicar v2 de la salsa → los platos usan la v2 y se avisa".
    - **A confirmar:** "gerencia de Compras" y "gerencia general": ¿son el rol Compras y el rol Dirección General, del grupo o de la marca del plato?

11. **Pariggi es un proveedor externo, como cualquier otro.**
    - **Qué cambia:** se carga como proveedor en el catálogo, sin nada especial. Ya no hace falta el alcance "cocina central" para Pariggi; el alcance queda en el documento por si en el futuro el grupo tiene una cocina central propia.

12. **Alérgenos:** el Chef los controla, pero **firma un externo contratado para auditorías y alérgenos.**
    - **Qué cambia:** la lista de alérgenos y su validación necesitan una persona externa con cuenta propia y un permiso específico (por ejemplo, `allergens.validate`). Esa persona firma la lista oficial y los estados de cada materia prima. El rol Auditor de hoy es solo de lectura y no alcanza.
    - **A confirmar:** ¿el externo entra al sistema con su usuario y firma ahí, o firma por fuera y alguien del grupo lo carga con la referencia al documento firmado?

### D. Validación de cada etapa

13. **Quiénes validan:** Compras, el Chef y **el dueño responsable del área, como Superadministrador, porque es un tema sensible.**
    - **A confirmar:** ¿quién hace cada validación? Nuestra lectura:
      - precios e impuestos: Compras y el dueño;
      - la receta completa cargada sin ayuda: el Chef;
      - el costo de las 20 recetas: el dueño.

      También: ¿quiénes son esas personas, por nombre, y cuándo pueden?

    - **Nota:** el documento de Soy pone al Controller como validador de costos. Si no hay Controller, lo reemplaza el dueño.

14. **El Excel del recetario actual:** sin respuesta. Sigue pendiente.

15. **Las primeras 20 recetas reales:** las pasa después.

### E. Para después

16. **Marcas, locales y otros negocios del grupo:** lo responde después.

## Preguntas abiertas de Joaco (ADR-0023)

Siguen pendientes:

- ¿quien redactó un borrador puede aprobarlo si la revisión la pidió otra persona?
- en un traspaso de local, ¿pasan sus recetas?

## Consecuencias para el plan

- **2.1 C (precios) se puede planificar.** Falta la respuesta 4 (producto preferido) y conviene confirmar los puntos marcados en 2 y 3 antes de construir. Suma:
  - razones sociales (toca la Fase 1);
  - el precio "ingresado" sin factura;
  - fletes y cargos aparte;
  - el porcentaje de aprobación de Dirección, configurable.
- **2.2 B (subrecetas) se simplifica:**
  - los platos siguen siempre a la versión vigente de su preparación, con avisos;
  - Pariggi es un proveedor.

  Para los alérgenos, falta definir cómo firma el externo.

- **Permisos:** el Gerente ve costos y precios de su local.
- **Los casos de prueba del documento** que cambian (26, y el 1 por el aviso de "heredado de…") se actualizan en el plan de la Fase 2, a propósito.
