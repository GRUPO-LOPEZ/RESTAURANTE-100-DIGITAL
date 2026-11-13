# Ficha única de materia prima: lista de lo que cambia (para Soy)

Pedido: «Fichas únicas de recetas y materias primas», Prompt 3. Decisión técnica: ADR-0043. Rama: `feat/ficha-unica-materia-prima`.

## En pocas palabras

- **Una sola ficha, sin pestañas.** Es la misma forma que la ficha de receta. Arriba están el código, el estado, el rubro y la unidad de recetas, y un índice que lleva a cada parte:
  1. datos generales;
  2. precios de compra;
  3. mermas y rendimientos;
  4. conversiones;
  5. alérgenos;
  6. dónde se usa.
- **Se edita donde se ve y se guarda todo junto.**
  - El nombre, el rubro, la unidad, los otros nombres, las observaciones, «¿Se compra congelada?», las conversiones y los alérgenos se cambian directamente en la ficha.
  - Abajo, una barra cuenta los cambios, pide un solo motivo y tiene «Descartar» y «Guardar cambios».
  - Si te vas con cambios sin guardar, avisa.
- **Precios de compra:**
  - el precio vigente y el costo neto con merma, destacados, para el local elegido arriba;
  - una tabla con cada producto de compra: proveedor, en qué viene, contenido, precio, precio por kg (o litro o unidad), fecha y estado («Vigente», «Atención: 22 días», «Heredado», «Sin precio»).
- **Mermas y rendimientos:** los 4 indicadores de siempre, el interruptor de congelada y una tabla con los rendimientos por proceso (estándar, ensayos y estado).
- **Altas y propuestas en un panel al costado:**
  - «Agregar producto de compra»;
  - «Crear un proveedor»;
  - «Proponer merma o rendimiento»: un solo botón, y adentro se elige cuál;
  - «Registrar un ensayo»;
  - «Proponer precio».
- **Alérgenos:** cada alérgeno tiene cuatro botones a la vista (Sin dato, Contiene, Puede contener, No contiene), y al lado se elige de dónde sale el dato.
- **En el celular, la ficha se consulta:** se ve todo, en tarjetas, sin campos para cargar.

## Qué no cambia

- **Las reglas, los permisos y las aprobaciones:**
  - quien no tiene permiso para el catálogo ve la ficha sin poder editarla;
  - con precios cargados, la unidad de recetas no cambia, y el rubro lo cambia quien maneja la configuración de precios. La ficha lo muestra deshabilitado y explica por qué;
  - dejar de comprarla congelada sigue pidiendo la aprobación de un Chef de todo el grupo;
  - las mermas, los rendimientos y los precios siguen pasando por su aprobación.
- **Quien no ve precios** no ve dinero: la sección se llama «Cómo se compra».
- **Los enlaces de antes** (por ejemplo, desde Calidad) siguen funcionando y bajan a su sección.

## Para decidir más adelante

- **El rubro de una materia prima con precios:** hoy ningún rol puede cambiarlo, porque hacen falta dos permisos que nadie tiene juntos. Solo cambia si se da de baja el rubro. Era así antes de esta ficha. Si querés que alguien pueda hacerlo, se ajustan los roles con Joaco.
- **«Proponer precio» se puede usar desde el celular,** como antes. El resto se carga en la computadora.
- **Editar un producto de compra ya cargado** (descripción, proveedor o dejar de comprarlo) todavía no tiene pantalla.
