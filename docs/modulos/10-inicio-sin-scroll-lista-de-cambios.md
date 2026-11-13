# Inicio sin scroll: lista de cambios

Para Soy. Fecha: 2026-11-13. Detalle técnico en el ADR-0045.

## Qué cambia en el Inicio (computadora)

1. **Entra entero en la pantalla, sin bajar.** Probado en 1440 × 900, 1600 × 900 y 1920 × 1080.
2. **Arriba dice «Hola, {nombre} · {local}»**, con la hora de los datos y cuántas recetas, preparaciones y materias primas hay. El único botón es «Ver qué falta corregir». Ya no está «+ Nueva receta».
3. **El aviso amarillo «Requiere atención»** ocupa una sola línea y lleva a Calidad. Ahí también se suman las revisiones que esperan tu decisión.
4. **Los 4 indicadores** muestran «1 de 12» al lado del número.
5. **Tres tarjetas chicas:**
   - **¿Qué tan confiable es el costo?** Cuántas recetas hay en cada estado. Cada fila lleva a esas recetas.
   - **Cómo está cada local.** Hasta 5 locales, con el elegido en negrita.
   - **Tareas pendientes.** Lo que más falta corregir, las revisiones que esperan y la última importación.
6. **Un solo ranking con botones:** Mayor costo por porción, Materias primas que más pesan, Afectadas por precio y Lo más usado. Reemplaza a las 4 tarjetas que casi siempre estaban vacías.
7. **6 accesos grandes con su número del momento:** Recetas, Materias primas, Costos, Aprobaciones, Calidad y Reportes. Por ejemplo, «1 sin aprobar», «3 sin precio» o «Al día».
8. **Usuarios, Roles e Historial ya no están en el Inicio.** Siguen en la barra de la izquierda.

## Colores de los indicadores (decisión tuya del 2026-11-13)

Es una sola regla para todo el sistema: el Inicio, Calidad y los accesos.

| Situación              | Se ve                      |
| ---------------------- | -------------------------- |
| Falta más de la mitad  | Rojo, «Faltan N» (crítico) |
| Falta la mitad o menos | Amarillo, «Faltan N»       |
| No falta nada          | Verde, «Completo»          |
| No hay nada que medir  | Gris, «Sin datos»          |

Un ejemplo: si faltan 6 de 12, es justo la mitad, y queda en amarillo. Si faltan 6 de 11, pasa a rojo.

**Ojo:** en Calidad, algunos indicadores que antes se veían en amarillo ahora se ven en rojo, porque les falta más de la mitad.

## En el celular

Es para mirar cómo está todo:

- el aviso;
- los 4 indicadores de a dos;
- «Para decidir»: las aprobaciones y lo que más falta;
- cómo está cada local.

El ranking y los accesos grandes no aparecen, porque los accesos están en la barra de abajo. Todos los botones miden lo mismo que un dedo.

## Qué no cambia

- Los números salen de los mismos datos de siempre. No se tocó la base.
- Cada persona ve solo lo que le corresponde. Por ejemplo, el Jefe de Cocina no ve costos ni precios.
- La Cocinera sigue viendo su Inicio simple, con sus roles y sus accesos.

## Y en Mi cuenta

- **Tus roles** ahora se ven en Mi cuenta, en «Mis datos». Antes estaban en el Inicio.
