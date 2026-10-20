# ADR-0003 — La CLI de Supabase como dependencia del proyecto

- **Fecha:** 2026-10-20
- **Estado:** aceptada

## Contexto

El paso 1 de la sección 0 pide instalar la CLI de Supabase en la máquina. Joaco prefirió no instalarla por ahora. La sección 3 pide una sola herramienta, probada y fácil de mantener.

## Decisión

La CLI se instala como dependencia de desarrollo del proyecto, con **versión fija** (`"supabase": "2.121.0"` en `package.json`), y se usa con `npx supabase ...` o con los scripts `npm run db:*`.

## Por qué

- No hay que instalar nada en la máquina: alcanza con `npm install`.
- La misma versión exacta corre en la computadora de Joaco y en GitHub Actions. Sin diferencias del tipo "en mi máquina anda".
- Dependabot avisa cuando sale una versión nueva, y se actualiza con un PR revisado.

## Opciones descartadas

- Instalación global (Scoop o Chocolatey): cada persona puede terminar con una versión distinta.
- `supabase/setup-cli` en CI con otra versión: dos fuentes de verdad para la versión.

## Consecuencias

- `npx supabase` tarda un poco más la primera vez.
- Los comandos remotos (`link`, `db push --linked`, `--project-ref`) quedan bloqueados para Claude Code por `.claude/settings.json` y por el hook `guard.mjs`.
