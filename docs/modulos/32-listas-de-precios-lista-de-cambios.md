# Listas de precios: lista de cambios (PR D)

Resumen para Soy, en simple. La decisión técnica está en [ADR-0071](../decisiones/0071-listas-importar-versiones.md).

## Cargar una lista

- **Se sube el archivo del proveedor y se lee solo:**
  - Excel o CSV;
  - PDF hecho por computadora, sin IA.
- Los renglones caen en la planilla para revisarlos antes de cargar.
- Si el proveedor llama distinto a las columnas, se elige cuál es cuál.
- **Una foto o un PDF escaneado** abren la pantalla dividida: el archivo a la izquierda, con zoom, y la planilla a la derecha para copiar.
- **El archivo original queda guardado** con la lista, para comparar si aparece un error.
- **La planilla modelo** se baja desde la ficha del proveedor («Planilla modelo»), para mandársela. Si la usan, se lee sola.

## Controles antes de aceptar

- Cada renglón muestra **cuánto subió o bajó** contra la lista vigente.
- Las subas que pasan **el umbral de Dirección (15 %)** se resaltan.
- Un precio **10 veces más alto o más bajo** que el anterior dice **«Revisar»**. Para cargar o aceptar la lista hay que confirmar que se revisó.
- Al lado de cada renglón, **el precio por unidad de uso** («$ 9.856 por kg»).
- Si el sistema no reconoce un artículo, se elige a mano («Es…»). Un chef lo confirma y **desde ahí la próxima lista lo reconoce sola**.

## Corregir y anular

- **Corregir una lista vigente** crea una **versión nueva** con su motivo. La anterior queda en la historia («Ver las versiones»).
- **Una lista cargada por error se anula** con motivo. No se borra.
- Si era la vigente, **vuelve a valer la anterior**.
- «Aceptada» ahora se llama **«Vigente»**.

## Lo que viene en la parte E

- Cuando una lista vence, **el pedido de la nueva sale solo por mail** desde el Gmail de la empresa. Para eso Soy tiene que cargar él mismo la contraseña de aplicación como secreto.
- **Un botón de WhatsApp** que abre el mensaje armado para mandarlo con un clic.
