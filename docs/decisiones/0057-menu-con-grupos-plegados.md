# ADR-0057: Menú con grupos plegados

- **Fecha:** 2026-11-17
- **Estado:** plan aprobado por Joaco el 2026-11-17 (eligió «Grupos plegados»).
- **Sigue a:**
  - ADR-0036: el rediseño y la barra lateral;
  - ADR-0051: la pantalla más baja medida, de 1715 × 843;
  - ADR-0056: los títulos de grupo de 28 px y el riesgo anotado.

## Problema

Con todos los grupos abiertos, el menú no entraba en 843 de alto para los roles con muchos menús. Lo medimos el 2026-11-17, en 1440 × 843, con 614 px de lugar para el menú:

| Rol                             | Grupos | Accesos | Alto del menú abierto |
| ------------------------------- | ------ | ------- | --------------------- |
| Superadmin                      | 5      | 17      | 816 (calculado)       |
| Director de Marca               | 5      | 16      | 776                   |
| Dirección y Gerente             | 5      | 15      | 736                   |
| Auditor                         | 5      | 14      | 696                   |
| Controller                      | 5      | 13      | 656                   |
| Chefs, Jefe de Cocina y Compras | 4      | 10 a 11 | 508 a 548             |
| Cocinero                        | 3      | 6       | entra                 |

Con facturas y pagos (Prompts 5 y 6) se suman más accesos.

## Opciones que se mostraron

1. **Grupos plegados.** Si el menú no entra, los grupos arrancan cerrados salvo el de la pantalla actual. **Elegida.**
2. **Pie compacto y accesos de 32 px.** Entraba por unos 5 px, se rompía con el próximo módulo y pedía una excepción nueva a la regla de controles.
3. **Administración en una sola entrada,** con una página propia. Sumaba una página y un clic para llegar a Usuarios, y no resolvía el crecimiento.

## Decisión

- **Cuándo se pliega:** `lib/nav.ts`, con `navFits`, cuenta el alto del menú abierto: 28 px por título de grupo, 40 px por acceso y −4. Lo compara con el lugar que queda en 843 de alto (606 px, con 4 px alrededor para que no se recorte el foco), dejando 20 px de margen porque Linux mide más alto.
  - Se cuenta en vez de medir en el navegador: el servidor y el navegador muestran lo mismo y no hay salto al cargar.
  - Las cuentas coinciden con lo medido (pruebas de Vitest con las medidas reales).
- **Plegado:** queda abierto el grupo de la pantalla actual (`currentGroup`, también en sus pantallas internas). Los demás se abren con un clic.
  - Lo que la persona abre o cierra a mano vale en esa pantalla. Cada pantalla arma su propia barra (`AppShell` va en cada página), así que en la siguiente vuelve a lo básico, con el grupo de esa pantalla abierto. No se guarda en una cookie.
- **Un grupo cerrado no esconde sus avisos:** el número de avisos sin leer (por ejemplo, de Aprobaciones) va en el título del grupo.
- **Los roles que entran abiertos** (Cocinero, Chefs, Jefe de Cocina, Compras) no cambian.
- **Barra contraída (solo íconos):** sin espacio entre íconos, que siguen en 36 px, y con una línea entre grupos. Los 17 del superadmin pasan de 712 a 624 px (con el margen del foco) y entran en 843.

## Consecuencias

- **Hay un clic más** para llegar a un grupo cerrado. Lo compensan el buscador de arriba y que el grupo actual siempre está abierto.
- **El Controller, el Auditor, el Gerente y Dirección** también ven los grupos plegados: en 843 de alto no entraban.
- **Si cambian los altos** de los accesos o del pie, hay que actualizar las constantes de `lib/nav.ts`. Lo cuida `layout.spec.ts`: el superadmin no puede tener scroll en el menú en 1440 × 900 ni en 1715 × 843, tampoco con la barra contraída.
