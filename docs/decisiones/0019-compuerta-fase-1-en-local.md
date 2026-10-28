# ADR-0019 — Compuerta de la Fase 1 aprobada con una demo local

- **Fecha:** 2026-10-28
- **Estado:** aceptada. Soy aprobó la Fase 1 en la demo; Joaco lo informó el mismo día.

## Contexto

La compuerta de la Fase 1 ([fase-1.md](../fases/fase-1.md), sección 12) decía: "en una demo de Joaco sobre el ambiente de prueba".

Staging no pudo publicar todavía:

- Joaco no tiene el rol Admin del repositorio en GitHub, y sin ese rol no aparece "Environments";
- puede faltar además el plan Team de GitHub;
- el detalle está en `docs/estado.md`.

## Opciones

1. Esperar a que staging funcione para hacer la demo.
2. Hacer la demo en la computadora de Joaco, sobre la base local con los datos ficticios del seed, y dejar staging pendiente.

## Decisión

**Opción 2.** El 2026-10-28, Soy vio la demo en local y aprobó la Fase 1. La Fase 2 queda habilitada.

## Consecuencias

- **Staging sigue siendo obligatorio**, pero para más adelante. Lo necesitan:
  - las validaciones de la Fase 2 con personas reales: la etapa 2.2 ("el chef carga una receta completa sin ayuda"), la 2.4 y la 2.5;
  - todo lo que llegue a producción.

  **Staging tiene que funcionar antes de cerrar la etapa 2.2.**

- Lo que solo se puede probar en staging sigue pendiente, sin cambios:
  - las verificaciones de la primera publicación (ADR-0018);
  - el límite por IP del ingreso desde la Edge Function (ADR-0014).
- La casilla "producción no tiene datos de prueba" no aplica todavía, porque producción no existe. Se verifica al crearla.
