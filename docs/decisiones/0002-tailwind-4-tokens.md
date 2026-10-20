# ADR-0002 — Tailwind CSS 4: la paleta vive en `app/globals.css`

- **Fecha:** 2026-10-20
- **Estado:** aceptada

## Contexto

La sección 7 pide definir la paleta y la tipografía "una sola vez como variables en Tailwind (`tailwind.config`)". La versión actual de Next.js (16) instala Tailwind CSS 4, que ya no usa `tailwind.config`: la configuración se escribe en CSS con el bloque `@theme`.

## Decisión

- Todos los tokens (colores base, estados pastel, series de gráficos, tipografía, radios, alto táctil) se definen en el bloque `@theme` de `app/globals.css`. Cumple la misma regla, "una sola vez, como variables", en el formato nuevo.
- **Se borra la paleta por defecto de Tailwind** (`--color-*: initial`). Clases como `bg-blue-500` directamente no existen, así que un color fuera de la paleta no se puede usar ni por error.
- Los nombres que espera shadcn/ui (`primary`, `muted`, `border`...) se mapean a esos mismos tokens con `@theme inline`.
- Tres controles automáticos:
  - ESLint rechaza colores sueltos (`#hex`, `rgb()`, `hsl()`, `oklch()`) en `app/` y `components/`.
  - `tests/unit/palette-contrast.test.ts` lee los colores del CSS y verifica contraste WCAG AA.
  - Playwright verifica los colores y la fuente que se ven en pantalla, y axe revisa la accesibilidad.

## Opciones descartadas

- Bajar a Tailwind 3 para tener `tailwind.config`: usar una versión vieja para cumplir la letra y no la intención.
- Usar el modo de compatibilidad `@config` de Tailwind 4 con un `tailwind.config.ts`: agrega un archivo y otra forma de hacer lo mismo.

## Consecuencias

- Para agregar un color: primero se aprueba (paleta de la sección 7), después se suma a `@theme` y a la prueba de contraste.
- Tamaño propio `text-kpi` (32 px). `lib/utils.ts` lo registra en `tailwind-merge` para que `cn()` no lo descarte.
