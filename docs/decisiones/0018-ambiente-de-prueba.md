# ADR-0018 — Ambiente de prueba (staging): Supabase y Vercel desde GitHub Actions

- **Fecha:** 2026-10-26
- **Estado:** aceptada por Joaco.

## Contexto

La compuerta de cierre de la Fase 1 (`docs/fases/fase-1.md`, sección 12) se valida en una demo de Soy **sobre el ambiente de prueba**. El prompt maestro (sección 10) dice que en staging escribe solo GitHub Actions, con datos ficticios.

Joaco creó el proyecto de Supabase `grupo-lf-staging` (`tdbciscmemfdwjttgurj`, región São Paulo). Faltaban tres cosas: cómo se publica, de dónde salen las personas de prueba y qué hacer con el correo.

## Opciones

1. **Personas de prueba**
   - A. Un script propio de staging, con la contraseña en un secreto de GitHub.
   - B. Crear solo un superadmin e invitar al resto por correo.
2. **Correo**
   - A. Usar el de Supabase.
   - B. Contratar ya un servicio de correo.
3. **Publicación de la app**
   - A. GitHub Actions, después de las pruebas y de la base.
   - B. La integración automática de Vercel con el repositorio.

## Decisión

**1A, 2A y 3A** (Joaco, 2026-10-26).

- **`supabase/config.toml`:** bloque `[remotes.staging]` con las diferencias respecto de lo local:
  - las direcciones de la app;
  - los límites normales de ingreso, no los 300 de local y CI;
  - el seed apagado.

  Lo sube `supabase config push`. Nada se cambia a mano en el panel.

- **`supabase/staging/demo-data.sql`:**
  - el mismo grupo ficticio del seed, con ids y correos `@ejemplo.test` iguales;
  - **sin** las cuentas de Playwright, el secreto TOTP público ni los ingresos inventados;
  - cada persona con doble verificación la activa con su celular la primera vez que entra;
  - la contraseña llega con `psql -v` desde el secreto `STAGING_DEMO_PASSWORD`, y una sola sentencia la usa para calcular el hash;
  - solo corre sobre una base sin grupos ni personas, y si el grupo de prueba ya está, no hace nada.
- **`.github/workflows/deploy-staging.yml`:**
  - **Cuándo corre:** cuando "Pruebas" termina en verde por un push a `main`, con el commit exacto que se probó, o a mano.
  - **Orden de los pasos:** verificar el destino, `db push`, `functions deploy`, `config push`, datos de prueba (solo a mano y si se pide) y por último la app en Vercel. Si un paso falla, los siguientes no corren.
  - **Destino:** el secreto `STAGING_PROJECT_REF` tiene que ser igual al `project_id` de `[remotes.staging]`.
  - **Secretos:** viven en el ambiente `staging` de GitHub.
- **CLI de Vercel 58.4.4** (versión fija), solo dentro de GitHub Actions. Es la forma documentada de publicar desde una CI propia: `pull`, `build --prod` y `deploy --prebuilt --prod`. No es una tecnología nueva para la app, porque Vercel ya estaba en el stack. Claude Code no la usa: el hook `guard.mjs` la bloquea.
- **Vercel sin clave de servidor:** el proyecto solo tiene `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. No se usa la integración Vercel–Supabase, porque copia la `service_role`.
- **Prueba de Vitest** `tests/hooks/staging-config.test.ts`: vigila todo lo anterior.

## Consecuencias

- La app nunca queda adelantada a la base, y una versión con pruebas en rojo nunca se publica.
- **El primer `db push` es la primera prueba real** sobre Supabase alojado. Si algo choca (roles propios, `pg_cron`, triggers en `auth.users`), se corrige con una migración nueva.
- **Correo:** recuperar la contraseña e invitar solo llegan a miembros de la organización de Supabase, y con pocos envíos por hora. La demo de la compuerta no los necesita. El servicio de correo propio se decide antes de producción.
- **Vercel "production" es nuestro staging.** Producción va a ser otro proyecto de Vercel y de Supabase, con su propio ambiente de GitHub y la aprobación de Soy.
- **Pendiente de Soy:** los planes de Supabase y Vercel. En el plan gratis, Supabase pausa los proyectos sin uso, y el plan Hobby de Vercel es para uso no comercial.
- **A verificar en staging:** el límite por IP de los ingresos que salen de la Edge Function (ADR-0014).
