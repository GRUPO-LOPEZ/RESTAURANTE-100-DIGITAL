# Ficha de receta sin scroll: lista de cambios

Para Soy. Fecha: 2026-11-14. Detalle técnico en el ADR-0047.

## Qué cambia en la computadora

1. **La ficha entra en la pantalla, sin bajar.** La única parte que se desplaza es la lista de ingredientes, como en una planilla de cálculo. Los títulos de las columnas y la fila del total quedan siempre a la vista.
2. **Arriba, una sola línea:** «← Recetas», el nombre, el código, el rubro, si es plato o preparación y la versión (Vigente, Borrador o En revisión). A la derecha, «Ficha de cocina» y «Escalar».
3. **Si está en revisión, una franja violeta** dice quién pidió el cambio, cuándo y por qué.
4. **4 números grandes:**
   - en un plato: costo total, costo por porción, peso total y porciones;
   - en una preparación: costo total, costo por kg neto, peso bruto → neto y rendimiento.
   - Si falta un dato se ve «—» y el motivo, nunca un número inventado.
   - Quien no ve costos ve el tiempo total y cuántos ingredientes tienen peso, en vez de la plata.
5. **La planilla:**
   - cada escala («Hacer 4», «Hacer 10») es una sola columna con el peso arriba y el costo abajo, y el número se cambia en el título de la columna;
   - la medida se ve abreviada («g», «kg», «cda»), como en una planilla de cálculo;
   - el total dice «Completo» o «Incompleto: falta 1 dato»;
   - **es mucho más rápida:** con 25 ingredientes, los pesos y costos se calculaban en 4 segundos y ahora en menos de una décima. Las sugerencias al escribir un código aparecen al instante;
   - quien ve costos tiene más columnas: en las pantallas de 1440 y 1600 la planilla se corre de costado, pero **el código y el nombre del ingrediente quedan siempre fijos a la izquierda**. En 1920 entra entera.
6. **A la derecha:**
   - **Fotos y datos generales:** el rubro se cambia ahí mismo, y «Editar datos» abre el resto.
   - **Rendimiento:** el peso de la porción o el peso neto.
   - **Procedimiento:** los pasos que entran, una línea cada uno, y «Editar los N pasos» abre todos.
   - **Un resumen:** el primer alérgeno que contiene y cuántos más, dónde se usa y las versiones, cada uno con su «Ver».
7. **Lo que se edita en un panel se guarda junto con todo lo demás**, con la barra de abajo de siempre: cuántos cambios hay, el motivo, Descartar y Guardar.
8. **Quien revisa ve la ficha sin poder editarla**, con los cambios marcados en violeta («antes 380 g», «Nueva»). Aprueba o no aprueba desde la barra de abajo.

## Lo que no cambia

- Las cuentas, los permisos, las aprobaciones y las versiones son los mismos.
- En el celular, la ficha es para consultar y se baja con el dedo. Quien revisa también puede aprobar desde el celular.

## Para mirar

- **Probada en 1440, 1600 y 1920:** entra sin bajar, con quien ve costos y con quien no.
- **Decidido con Joaco:** quien no ve costos ve «Tiempo total» e «Ingredientes con peso» en lugar de los números de plata.
