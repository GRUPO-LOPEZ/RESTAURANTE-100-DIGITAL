# ADR-0001 — Organización del repositorio y del entorno local

- **Fecha:** 2026-10-20
- **Estado:** aceptada (aprobada por Joaco en el plan de la Fase 0)

## Contexto

La sección 4 del prompt maestro propone una carpeta `grupo-lf/` con una estructura dada. El repositorio de GitHub (`GRUPO-LOPEZ/RESTAURANTE-100-DIGITAL`) ya existía y se trabaja en Windows con Docker Desktop y unos 3,9 GB de RAM para Docker.

## Decisiones

1. **La raíz del repositorio es el proyecto.** No se agrega una subcarpeta `grupo-lf/`: la estructura de la sección 4 vive directamente en la raíz. Agregar un nivel más no suma nada y complica Vercel y CI.
2. **Finales de línea LF** en todo el repo (`.gitattributes` y `.editorconfig`). Evita diferencias entre Windows y Linux (CI), sobre todo en SQL y scripts.
3. **Hooks de Claude Code escritos en Node** (`.claude/hooks/*.mjs`). Node ya es requisito del proyecto y funciona igual en Windows, macOS y Linux. Bash o PowerShell atarían el proyecto a un sistema. Los hooks tienen pruebas en `tests/hooks/`.
4. **Supabase local liviano:** `analytics` (logs), `edge_runtime` y `storage.vector` quedan apagados en `supabase/config.toml` hasta que un módulo los necesite. Studio queda prendido para mirar datos.
5. **Seguridad desde la configuración:** `auto_expose_new_tables = false` (toda tabla necesita GRANT explícito) y `enable_signup = false` (alta solo por invitación).
6. **Prettier con 100 columnas** para código y Markdown. Las migraciones SQL no pasan por Prettier.

## Opciones descartadas

- Hooks en PowerShell: solo funcionan bien en Windows.
- Dejar todos los servicios de Supabase prendidos: con 3,9 GB de RAM para Docker, el riesgo de que todo ande lento es alto.

## Consecuencias

- Para prender un servicio apagado, se cambia `enabled = true` en `supabase/config.toml` y se anota en `docs/estado.md`.
