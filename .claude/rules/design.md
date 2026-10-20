---
paths:
  - "app/**"
  - "components/**"
---

# Sistema de diseño: simple, plano y pastel (prompt maestro, sección 7)

Estilo minimalista y flat de tipo SaaS corporativo. El objetivo es bajar la carga mental: **cada pantalla responde una pregunta** y muestra solo lo necesario para actuar.

Todo está definido **una sola vez** como variables en `app/globals.css` (bloque `@theme` de Tailwind 4) y en `components/ui/`. **Ningún componente usa colores sueltos fuera de la paleta**: nada de `#hex`, `rgb()` ni colores por defecto de Tailwind (`bg-blue-500`, etc.) en `app/` o `components/`. Usar las clases de los tokens (`bg-app`, `text-ink`, `bg-ok text-ok-ink`, etc.).

## Paleta base

| Uso                | Color                            | Hex       | Token                     |
| ------------------ | -------------------------------- | --------- | ------------------------- |
| Fondo de la app    | Blanco cálido                    | `#FAFAF9` | `app`                     |
| Tarjetas y paneles | Blanco                           | `#FFFFFF` | `surface`                 |
| Bordes y divisores | Gris piedra claro                | `#E7E5E4` | `line`                    |
| Texto principal    | Gris pizarra                     | `#1F2937` | `ink`                     |
| Texto secundario   | Gris medio                       | `#6B7280` | `ink-muted`               |
| Acción principal   | Azul pizarra suave, texto blanco | `#4F6D9A` | `primary` / `primary-ink` |

## Pasteles de estados y etiquetas

Fondo pastel + texto oscuro del mismo tono.

| Significado             | Fondo                    | Texto     | Token                   |
| ----------------------- | ------------------------ | --------- | ----------------------- |
| Bien, aprobado, en meta | Verde menta `#D1FAE5`    | `#065F46` | `ok` / `ok-ink`         |
| Atención, pendiente     | Amarillo crema `#FEF3C7` | `#92400E` | `warn` / `warn-ink`     |
| Problema, rechazado     | Rosa suave `#FFE4E6`     | `#9F1239` | `bad` / `bad-ink`       |
| Información             | Celeste `#E0F2FE`        | `#075985` | `info` / `info-ink`     |
| En revisión             | Lavanda `#EDE9FE`        | `#5B21B6` | `review` / `review-ink` |
| Borrador                | Durazno `#FFEDD5`        | `#9A3412` | `draft` / `draft-ink`   |

## Gráficos

- Series: `#93C5FD`, `#86EFAC`, `#FCD34D`, `#FDA4AF`, `#C4B5FD`, `#FDBA74` (tokens `chart-1` a `chart-6`).
- Máximo **4 series** por gráfico.
- El color **nunca** es la única señal: siempre con etiqueta o ícono.

## Tipografía

- Una sola familia: **Inter**, con la fuente del sistema de respaldo.
- Tamaños: 14 px texto chico, 16 px texto base, 20 px subtítulos, 24 px títulos, 32 px números de KPI.
- Pesos: 400 normal, 500 etiquetas, 600 títulos. Nunca cursiva decorativa ni tipografías caligráficas.
- Números con ancho fijo (`tabular-nums`) para que las columnas se alineen.

## Formas y espacio

- Grilla de 8 px. Mucho aire entre bloques.
- Bordes redondeados de 8 a 12 px. Bordes finos de 1 px.
- Sin degradados, sin sombras fuertes, sin fondos con imágenes ni texturas.
- Íconos de línea simples (Lucide), **siempre con texto al lado**.

## Reglas de tableros

1. Un tablero = una pregunta de negocio, escrita como título.
2. Arriba, de 3 a 6 tarjetas KPI: valor, comparación con el período anterior y estado en pastel.
3. Debajo, un gráfico principal y una tabla de detalle.
4. Filtros fijos arriba: fecha, marca, restaurante.
5. Siempre visibles la fecha de los datos y la última actualización.
6. Estados vacíos, de carga y de error diseñados. Nunca pantallas en blanco.

## Celular primero

- Una columna. Botones de **mínimo 44 px** de alto.
- Acciones principales al alcance del pulgar.
- Formularios cortos, con teclado numérico donde corresponda (`inputMode="decimal"`).
- Listas paginadas: nunca traer tablas completas al navegador.

## Accesibilidad

- Contraste mínimo WCAG AA: 4,5 a 1 en texto. Lo verifica `tests/unit/palette-contrast.test.ts` y axe en Playwright.
- Todo se puede usar con teclado, con foco visible.
- Modo oscuro opcional, en una fase posterior. No construirlo ahora.

## Idioma y código

- Todo lo visible en español rioplatense. Código en inglés.
- Formularios con React Hook Form + Zod, con el mismo esquema en el navegador y en el servidor.
- La interfaz oculta lo que el usuario no puede hacer, pero nunca reemplaza a la seguridad de la base.
- Antes de cerrar, pedir revisión al subagente `ui-reviewer` y mirar la pantalla real en celular y computadora.
