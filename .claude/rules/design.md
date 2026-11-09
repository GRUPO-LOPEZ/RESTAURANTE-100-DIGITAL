# Grupo LF Design System: simple, plano y pastel (prompt maestro, sección 7; rediseño en ADR-0036)

Estilo minimalista y flat, de tipo SaaS corporativo. **La complejidad del negocio se resuelve en la arquitectura; para el usuario, la experiencia es simple.** Cada pantalla responde una pregunta y muestra solo lo necesario para actuar. Los números importantes tienen protagonismo; los títulos, no.

Todo está definido **una sola vez**: los valores en `app/globals.css` (bloque `@theme` de Tailwind 4) y los componentes en `components/ui/`. **Ningún módulo define colores, tamaños ni espacios propios**: nada de `#hex`, `rgb()` ni colores por defecto de Tailwind (`bg-blue-500`, etc.) en `app/` o `components/`. Se usan las clases de los tokens (`bg-app`, `text-ink`, `bg-ok text-ok-ink`, etc.). Cada módulo nuevo reutiliza la misma interfaz.

## Dispositivos

| Contexto                   | Dispositivo                       | Para qué                                                               |
| -------------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| Operación (prioridad)      | Computadora: 1440, 1600 y 1920 px | Cargar y editar recetas, materias primas, costos, usuarios y reportes  |
| Supervisión                | Celular                           | KPIs, alertas, aprobaciones, reportes resumidos y consulta de fichas   |
| Carga en cocina (a futuro) | Celular                           | Checklists, temperaturas y registros: botones grandes, un paso por vez |

El celular **no** es una copia achicada de la computadora: tiene su propia disposición de lectura. No se compromete la computadora para que todo se vea igual. La vista de cocina, el escalado y las fichas impresas siguen pensadas para celular y papel.

## Layout global (`components/app-shell.tsx`)

- **Barra lateral fija** (desde 800 px): 240 px expandida, 68 px contraída (solo íconos; se recuerda en una cookie del navegador). Logo arriba; usuario, Mi cuenta y Salir abajo. Grupos: Visión general · Base de conocimiento · Gestión y análisis · Control · Administración. La navegación entra sin scroll en 1440 px.
- **Barra superior fija** de 64 px: ruta de navegación, selector global de local, búsqueda, avisos y perfil.
- **El selector de local es único y global.** No se agregan selectores de local dentro de las pantallas.
- **Área principal fluida:** sin `max-width` global. Márgenes de 32 px (45 px desde 1700 px). Solo los formularios de texto largo limitan su ancho.
- **Celular (menos de 800 px):** barra inferior con 4 accesos (Inicio, Recetas, Reportes, Control) y el resto en "Menú". Las tablas pasan a tarjetas con nombre, estado y acción.

## Paleta base

| Uso                          | Hex                   | Token                           |
| ---------------------------- | --------------------- | ------------------------------- |
| Fondo general                | `#F7F8FA`             | `app`                           |
| Tarjetas, tablas, paneles    | `#FFFFFF`             | `surface`                       |
| Bordes de 1 px               | `#E5E7EB`             | `line`                          |
| Texto principal              | `#1F2937`             | `ink`                           |
| Texto secundario y etiquetas | `#6B7280`             | `ink-muted`                     |
| Barra lateral                | `#22304A` / `#D6DEEC` | `nav` / `nav-ink`               |
| Ítem activo de la barra      | `#EAF0FB` / `#2F4F8F` | `nav-active` / `nav-active-ink` |
| Botón principal y enlaces    | `#4A6FB8` / `#3D5E9F` | `primary` / `primary-hover`     |

## Estados

Fondo pastel + texto oscuro del mismo tono, **siempre con una palabra** (nunca solo color).

| Estado                   | Fondo     | Texto     | Token                   |
| ------------------------ | --------- | --------- | ----------------------- |
| Al día                   | `#DCFCE7` | `#166534` | `ok` / `ok-ink`         |
| Atención                 | `#FEF3C7` | `#92400E` | `warn` / `warn-ink`     |
| Crítico                  | `#FEE2E2` | `#991B1B` | `bad` / `bad-ink`       |
| Sin datos / No aplicable | `#F1F2F4` | `#4B5563` | `none` / `none-ink`     |
| Información              | `#DBEAFE` | `#1E40AF` | `info` / `info-ink`     |
| En revisión (versiones)  | `#EDE9FE` | `#5B21B6` | `review` / `review-ink` |
| Borrador (versiones)     | `#FFEDD5` | `#9A3412` | `draft` / `draft-ink`   |

## Métricas confiables

**Un indicador nunca muestra un estado positivo cuando no hay datos.** Se usa el componente `Metric` (`components/ui/metric.tsx`).

| Situación                    | Se muestra                                 | Estado      |
| ---------------------------- | ------------------------------------------ | ----------- |
| Denominador = 0              | "Sin {cosa}" (nunca 0 % ni "Todas al día") | Sin datos   |
| Dato faltante o no calculado | "—" y el motivo                            | Sin datos   |
| Valor real igual a cero      | 0                                          | Según regla |
| Dato vencido                 | El valor y su fecha                        | Atención    |
| Dato completo y vigente      | El valor                                   | Al día      |

Cada estado sale de una regla verificable y cada tarjeta enlaza a los registros que originan su número.

## Gráficos

- Series pastel (`chart-1` a `chart-5`): `#93B4E8`, `#9ED9B8`, `#F4A9A0`, `#C4B5FD`, `#F6D59A`, para rellenos suaves.
- **Barras, líneas y puntos** van con los tonos fuertes (`chart-strong-1` a `chart-strong-6`), que llegan a 3:1 sobre el fondo (WCAG 1.4.11). Solo en gráficos (ADR-0015).
- Máximo **4 series** por gráfico. Nunca colores de estado como decoración. El color **nunca** es la única señal.

## Tipografía

- Una sola familia: **Inter**, con la fuente del sistema de respaldo.
- Escala: 12 (`xs`), 14 (`sm`), 16 (`base`), 20 (`xl`) y 28 px (`2xl`); números de KPI en 32 px (`kpi`), peso 600. **Mínimo 12 px** en cualquier texto.
- Pesos: 400 normal, 500 etiquetas, 600 títulos y KPI.
- Números tabulares (`tabular-nums`), alineados a la derecha en las tablas.

## Formas y espacio

- Espaciado en múltiplos de 4 px. Radio de 10 px en tarjetas (`rounded-md`) y 8 px en controles (`rounded-sm`). Bordes de 1 px.
- Controles de 36 a 40 px de alto en la computadora; **44 px como mínimo en el celular** (táctil).
- Sin degradados, sin sombras pesadas, sin fondos con imágenes ni texturas.
- Íconos de trazo, del mismo set en todo el sistema (Lucide), **siempre con texto al lado** o con nombre accesible.

## Tres tipos de pantalla

- **A. Paneles** (Inicio, Panel de control, Calidad): entender el estado en 5 segundos. Encabezado con acción a la derecha, aviso "Requiere atención", fila de 4 KPIs, comparación entre locales y tareas pendientes, tabla resumida con "Ver todas". Lo principal entra sin scroll.
- **B. Carga y edición** (fichas, configuraciones): secciones o pestañas, obligatorios marcados, validación al salir del campo, barra de Guardar / Cancelar fija abajo, aviso de cambios sin guardar. Las altas simples van en un modal corto que crea el borrador.
- **C. Listados e informes**: filtros en una línea que se aplican solos (con etiquetas que se pueden quitar), pestañas de estado, tabla de ancho completo ordenable, paginación de 15 filas (10, 25, 50) con total. El detalle se abre en un panel lateral o una ficha con "← Volver", sin perder filtros ni página.

Mismo lugar para los botones, misma lógica de filtros y mismos nombres para las mismas acciones en todo el sistema.

## Accesibilidad (WCAG 2.2 AA)

- Contraste mínimo de 4,5:1 en texto. Lo verifica `tests/unit/palette-contrast.test.ts` y axe en Playwright.
- Sobre un fondo pastel, el texto va **siempre** en su tono oscuro (`ok-ink` sobre `ok`, etc.). `ink-muted` sobre pastel no llega a AA.
- Los estados hover no aclaran fondos con texto encima: usar `primary-hover`, subrayado o `bg-line/50`.
- Todo se puede usar con teclado, con foco visible. Los estados no dependen solo del color.

## Componentes nuevos de shadcn/ui

La paleta, los tamaños, los pesos y los radios por defecto de Tailwind están **borrados** (`initial` en `@theme`). Al agregar un componente con `npx shadcn add`, revisá todas sus clases. `bg-black/50`, `text-white`, `font-bold`, `rounded-xl` y `dark:` no generan nada **y no dan error**. Reemplazalas por tokens y cambiá `import { cn } from "cn"` por `@/lib/utils` (ADR-0004).

- Modo oscuro opcional, en una fase posterior. No construirlo ahora.

## Idioma y código

- Todo lo visible en español rioplatense. Código en inglés.
- Formularios con React Hook Form + Zod, con el mismo esquema en el navegador y en el servidor.
- La interfaz oculta lo que el usuario no puede hacer, pero nunca reemplaza a la seguridad de la base.
- Antes de cerrar, pedir revisión al subagente `ui-reviewer` y mirar la pantalla real en computadora (1440, 1600 y 1920 px) y en celular.
