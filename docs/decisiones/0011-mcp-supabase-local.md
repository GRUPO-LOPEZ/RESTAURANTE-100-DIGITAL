# ADR-0011 — MCP de Supabase: solo la base local, en solo lectura

- **Fecha:** 2026-10-20
- **Estado:** aceptada por Joaco (opción A).

## Contexto

La sección 4 del prompt maestro pide conectar Supabase a Claude Code por MCP, "solo el proyecto de desarrollo; nunca producción con permisos de escritura". En este proyecto, el ambiente de desarrollo es la base **local** (`npx supabase start`).

Para conectarse a la nube, Supabase usa OAuth: se autoriza a Claude Code sobre una organización. Según la documentación de Supabase, consultada el 2026-10-20, no está claro que ese acceso quede limitado a un solo proyecto. Staging y producción van a estar en la organización de Soy.

Comprobado hoy contra la base local (CLI 2.121, servidor MCP 0.12.0):

- `http://localhost:54321/mcp` ofrece 11 herramientas;
- con `?read_only=true` desaparece `apply_migration`, y `execute_sql` rechaza cualquier escritura ("cannot execute UPDATE in a read-only transaction").

## Opciones

- **A. MCP de la base local.** No usa la cuenta, ni tokens, ni claves.
- **B. MCP de la nube**, en una organización aparte solo para desarrollo, con `project_ref` y `read_only=true`. La autorización la hace Joaco desde una terminal (`claude` → `/mcp`), eligiendo solo esa organización.

## Decisión

**Opción A.** Tiene tres capas:

1. **`.mcp.json`:** un solo servidor, `supabase-local`, apuntando a `http://localhost:54321/mcp?read_only=true`. Claude Code pide aprobarlo la primera vez.
2. **`.claude/settings.json`:**
   - las herramientas de lectura quedan permitidas;
   - `execute_sql` siempre pide aprobación, por el riesgo de que los datos traigan instrucciones escondidas;
   - `apply_migration` y `get_publishable_keys` quedan denegadas. La base se sigue cambiando solo con archivos en `supabase/migrations/`.
3. **Prueba `tests/hooks/mcp-config.test.ts`:** falla en la CI si alguien apunta el MCP a la nube, le saca el solo lectura, suma otro servidor o afloja esos permisos.

## Límites

- No ve nada de la nube. Hoy no hay nada en la nube, así que no se pierde nada.
- Solo funciona con Supabase local prendido.
- El MCP de GitHub queda para más adelante. Hoy alcanza con `gh`.

## Cómo pasar a B, si hace falta

1. Soy crea una organización aparte (por ejemplo "Grupo LF – Desarrollo") con un proyecto `grupo-lf-dev`.
2. Se agrega un servidor nuevo con `https://mcp.supabase.com/mcp?project_ref=<id>&read_only=true`.
3. La prueba se actualiza en el mismo PR, con este ADR reemplazado.

**Nunca** se autoriza la organización donde estén staging o producción.
