# ADR-0004 — `clsx` + `tailwind-merge` en lugar del paquete `cn`

- **Fecha:** 2026-10-20
- **Estado:** aceptada

## Contexto

`shadcn init` (4.22) instaló el paquete `cn` (0.5.0) como reemplazo de `clsx` + `tailwind-merge`. Es del equipo de shadcn, pero está en versión 0.x, la 0.5.0 salió el 16/10/2026 y cambió cinco veces en el último mes.

## Decisión

Usar `clsx` (2.x) + `tailwind-merge` (3.x) en `lib/utils.ts`. Son el estándar que shadcn/ui usó durante años y están probados en producción. La firma de `cn()` es la misma, así que los componentes no cambian.

## Por qué

Principio 1 (calidad antes que velocidad) y sección 3 ("stack probado"): una dependencia 0.x que cambia cada semana es un riesgo innecesario para la utilidad que usan todos los componentes.

## Consecuencias

- Al agregar componentes con `npx shadcn add`, cambiar `import { cn } from "cn"` por `import { cn } from "@/lib/utils"`. Si se olvida, `npm run typecheck` falla, porque el paquete `cn` ya no está instalado.
- Revisar de nuevo cuando `cn` llegue a 1.0.
