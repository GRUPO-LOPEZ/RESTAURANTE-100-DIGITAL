# Medidas, mermas y rendimientos: lista de lo que cambia (para Soy)

Pedido: «Medidas, mermas y rendimientos». Decisión técnica: ADR-0040. Rama: `feat/mermas-rendimientos`.

## En pocas palabras

- **Más unidades, con su nombre completo.** Las listas ahora dicen «Kilogramo (kg)», «Cucharada (cda)», «Taza», agrupadas en Peso, Volumen y Unidades. Se sumaron miligramo, libra, onza, cc, taza, cucharada, cucharadita, onza líquida, pizca y porción. El sistema hace las cuentas solo.
- **Unidades nuevas.** En la configuración del catálogo está la lista con su equivalencia («Taza = 240 ml») y se puede sumar otra, por ejemplo un «Cucharón = 60 ml». Si se cargó mal y nadie la usó todavía, se da de baja y se carga de nuevo. Una unidad nueva se usa enseguida al comprar; en las recetas, desde la próxima actualización del sistema.
- **Mermas de cada materia prima.** En la pestaña «Rendimientos» de la ficha se ven cuatro números:
  - la merma de limpieza;
  - la merma de descongelado;
  - lo que rinde neto;
  - el costo neto por kilo en el local elegido arriba.
- **«¿Se compra congelada?»** se cambia con un clic. Si es congelada, su costo suma la merma de descongelado. **Dejar de comprarla congelada baja el costo, así que lo aprueba un Chef de todo el grupo** (decisión de Joaco). Hasta entonces, la ficha muestra «Pedido pendiente».
- **Proponer mermas.** Se escriben en % y la pantalla muestra al momento, por ejemplo, «Rinde 72,0 % neto · Costo neto $ X por kg». Igual que los rendimientos de hoy, **las aprueba un Chef de todo el grupo**, que no puede ser quien las propuso. Hasta entonces, el costo no cambia.
- **Rendimiento final de las sub-recetas, destacado.** En la pestaña «Rendimientos» de cada receta se ven:
  - cuánto rinde terminada;
  - cuánto cuesta el kilo (o el litro, o la unidad);
  - la merma de cocción, como dato informativo.

## Lo que no cambia

- **Los costos de hoy quedan iguales.** Se comprobó con todas las recetas de prueba, antes y después.
- **El sistema nunca supone.** Si falta un dato, se ve «—» con el motivo y el costo queda «incompleto», nunca más barato:
  - una merma que no se cargó no cuenta como 0 %;
  - un litro no pesa un kilo si nadie lo midió.
- **Una merma de 0 % hay que declararla**, marcando «No tiene merma».
- **Una receta no se manda a revisión sin su rendimiento**, como hasta ahora.
- Cada cambio queda en el **Historial**: quién, cuándo, qué y por qué.

## Para que decidas

- **Marcar «congelada» no pide aprobación; desmarcarla, sí.** Marcarla solo puede subir el costo o dejarlo incompleto hasta que se apruebe la merma. Desmarcarla lo baja, y por eso la aprueba un Chef de todo el grupo.
- **Pizca = 0,5 g y porción = 1 unidad.** Son convenciones habituales. Si en la cocina se usan otras, se cambian.
- **Las mermas se cargan en la ficha, no al crear la materia prima.** El alta queda corta; las mermas van después, porque las tiene que aprobar otra persona.
- **La merma de cocción es solo informativa**: compara lo que entra con lo que rinde terminado. Si algún ingrediente está en ml y no tiene su densidad, no se calcula.

## Técnico (para Joaco)

- **Migración** `20261126120000_units_and_waste.sql`:
  - unidades con nombre largo y abreviatura, y las 10 nuevas;
  - `catalog.create_unit`;
  - `ingredients.requires_thawing` y `catalog.set_requires_thawing`: marcar es directo y desmarcar crea la solicitud `catalog.change_requires_thawing`. En los dos casos se encola el recálculo;
  - `catalog.archive_unit` y `catalog.unit_in_use`;
  - los procesos LIMPIEZA y DESCONGELADO en los grupos existentes;
  - `catalog.costing_yield`, que pasa a usar el motor;
  - `catalog.propose_waste` y `recipes.cooking_loss`.
- **Pantallas:**
  - la ficha de la materia prima (tarjeta «Mermas y rendimiento neto»), la ficha de la receta (`YieldKpis`) y la configuración (Unidades);
  - los componentes nuevos `ToggleField`, `SegmentedField`, `InfoTip` y `WastePreview`.
- **Pruebas:**
  - nuevas: pgTAP `270`, Vitest `waste.test.ts` y Playwright `mermas.spec.ts`;
  - ajustadas: `050` y `140`.
- **Revisiones:**
  - seguridad: apta;
  - base y diseño: sin graves;
  - los medios están resueltos o documentados en el ADR-0040.
