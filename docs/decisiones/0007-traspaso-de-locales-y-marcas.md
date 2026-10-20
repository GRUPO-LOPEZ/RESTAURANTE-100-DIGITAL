# ADR-0007 — Traspaso de locales y marcas: se crea uno nuevo y se cierra el viejo

- **Fecha:** 2026-10-20
- **Estado:** aceptada por Joaco (P15, opción A). Se implementa en M5. Se puede pasar a la opción B si Soy lo necesita.

## Contexto

En M3 y M4 la base se armó con dos reglas que protegen los permisos y el historial:

1. Cada asignación de rol queda atada a su alcance con FKs compuestas: el local pertenece a esa marca y a ese grupo, y lo mismo vale para las áreas.
2. Una asignación no cambia nunca, ni siquiera cuando ya está quitada: para otro rol o lugar se crea otra.

Juntas, impiden mover un local a otra marca (o una marca a otro grupo) apenas tuvo alguna asignación. Lo detectó `db-reviewer` en la revisión de M4.

## Opciones

- **A. Crear uno nuevo y cerrar el viejo.** El traspaso:
  - cierra el local viejo (`status = 'inactive'`, sin borrarlo);
  - crea uno nuevo en la marca destino y deja anotado de qué local viene;
  - vuelve a dar los roles en el local nuevo.

  La historia de cada local queda con la marca que tenía en ese momento.

- **B. Mover el mismo local.** Hay que aflojar las FKs compuestas y diseñar qué pasa con las asignaciones y los registros que apuntan a la marca vieja. Es más complejo y deja más lugar para errores de alcance en los permisos.

## Decisión

**Opción A.** El trámite de traspaso (`org.transfer`, M5) es una función transaccional que en una sola operación:

- cierra el local viejo;
- crea el nuevo, con una referencia al anterior, por ejemplo `predecessor_id`;
- reasigna los roles con las reglas de M6;
- deja todo auditado, con motivo y con el origen.

El detalle se aprueba en el plan de M5. Si P7 lo confirma, pasa por aprobación.

## Consecuencias

- La historia es limpia: nada de lo pasado cambia de marca a escondidas.
- Para ver la historia completa de un lugar físico hay que seguir la cadena de locales. Los tableros lo resuelven con esa referencia.
- **Es reversible hacia B:** pasar a B es aflojar una regla, y los datos cargados con A ya la cumplen. Al revés, de B a A, no sería así.
