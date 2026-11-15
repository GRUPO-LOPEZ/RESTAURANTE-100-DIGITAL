# Costos sin scroll y selector de local: lista de cambios

Para Soy. Fecha: 2026-11-14. Detalle técnico en el ADR-0048.

## Por qué no veías nada en Costos

Arriba decía «Demo Café Centro», pero ese local **no estaba aplicado**: el selector cambiaba lo que se veía apenas lo elegías, y solo se aplicaba al apretar «Cambiar». La pantalla de Costos seguía con «Todos mis locales» y por eso te pedía elegir uno. Lo comprobamos con una prueba que repite exactamente esos pasos.

Pasaba algo parecido con los enlaces que llevan a un local (por ejemplo, un aviso de cambio de costo): la pantalla mostraba ese local y arriba decía otro.

## Qué cambia en el selector de local

1. **Lo que dice arriba es siempre lo aplicado.** Al lado aparece «Aplicado».
2. **Con el mouse o el dedo, elegir un local lo aplica.** No hace falta ningún botón.
3. **Con el teclado** (las flechas), nada cambia hasta confirmar: dice «Sin aplicar» y aparece el botón «Aplicar».
4. **Un enlace a otro local lo aplica también arriba** (decisión de Joaco).
5. **En una pantalla que se ve de a un local** (Costos, Calidad, Reportes, Escenarios), con «Todos mis locales» arriba, dice «Costos se ve de a un local» y muestra un botón por local. Al tocar uno, queda aplicado también arriba.

## Qué cambia en Costos (computadora)

1. **La lista entra en la pantalla, sin bajar.** La tabla se desplaza adentro y los títulos de las columnas quedan fijos.
2. **Arriba, una línea:** «¿Cuánto cuesta cada receta?», el local, cuándo se actualizó y «sin IVA».
3. **4 números grandes**, con la misma regla de colores del Inicio (verde si está todo, amarillo si falta la mitad o menos, rojo si falta más de la mitad, gris si no hay datos):
   - recetas al día;
   - desactualizadas, con «Ver cuáles»;
   - incompletas, con «Ver cuáles»;
   - el plato con mayor costo por porción, con su nombre (lleva a su detalle).
4. **La confiabilidad son botones** a la vista (Todas, Completo, Con estimaciones, Desactualizado, Incompleto), cada uno con su cantidad.
5. **La tabla** tiene receta y código, tipo, costo sin IVA, con IVA, por porción, por kg, confiabilidad y fecha. Si falta un número se ve «—»; al pasar el mouse dice por qué.
6. **El detalle de una receta** también entra en la pantalla:
   - si falta un dato, una franja amarilla dice cuál y por qué;
   - 4 números: costo sin IVA (con el de antes), con IVA, por porción y por kg;
   - **línea por línea, de la que más pesa a la que menos**, con una barra del porcentaje. Las líneas sin dato van al final, en rojo, con su motivo;
   - **cómo fue cambiando:** las últimas fotos del costo y «Ver toda la historia»;
   - **para bajar el costo:** una línea que dice qué ingrediente pesa más y cuánto («Salsa bolognesa es el 67,6 % del costo»), con «Probarlo en Escenarios». Es una cuenta con los números de la pantalla, no un agente.

## Lo que no cambia

- Cómo se calcula el costo, quién lo puede ver y el recálculo de cada minuto.
- Escenarios e Impacto.
- En el celular, Costos sigue siendo de consulta: tarjetas y scroll, con botones grandes.

## Pendiente de tu lado

- Si las pantallas sin scroll se diseñan para el alto real de un monitor de 1440 × 900 (unos 790 px útiles, con las barras del navegador). Hoy se diseñan para la ventana entera.
