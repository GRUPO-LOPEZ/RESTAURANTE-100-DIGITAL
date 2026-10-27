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
  - **dos contraseñas** (Joaco, 2026-10-27):
    - `STAGING_DEMO_ADMIN_PASSWORD` para los roles con doble verificación. La tienen solo Joaco y Soy, que activan la doble verificación con su celular antes de repartir nada;
    - `STAGING_DEMO_PASSWORD` para el resto;
  - psql las lee de variables de entorno (`\getenv`), nunca de la línea de comando. El flujo valida largo, letras, números y que sean distintas antes de llegar a la base;
  - una sola sentencia las usa, y es una consulta, no DDL (que Postgres puede registrar en sus logs). Calcula los hash con costo 10, como Supabase Auth;
  - el motivo de auditoría lleva el número de corrida de GitHub Actions;
  - solo corre sobre una base sin grupos ni personas, y si el grupo de prueba ya está, no hace nada.
- **`.github/workflows/deploy-staging.yml`, en dos jobs:**
  - **`base`:**
    - comprueba que "Pruebas" pasó para el commit (también en la corrida manual, con la API de GitHub);
    - verifica el destino:
      - `STAGING_PROJECT_REF` igual al `project_id` de `[remotes.staging]`;
      - `STAGING_DB_URL` con el usuario `postgres.<ref>` y sin la contraseña adentro;
    - corre `db push`, `functions deploy`, `config push` y, solo a mano y si se pide, los datos de prueba.
  - **`app`:** corre solo si `base` salió bien.
    - Trae la configuración de Vercel y comprueba que apunte a la base de staging y que no tenga claves de servidor.
    - Arma y publica la app.
    - Comprueba que `grupo-lf-staging.vercel.app` sea de este equipo de Vercel.
  - **Secretos:** viven en el ambiente `staging` de GitHub y se declaran **paso por paso**. La instalación de dependencias y la CLI de Vercel nunca ven las claves de Supabase. La contraseña de la base va en `PGPASSWORD`, no en la dirección.
- **CLI de Vercel como dependencia de desarrollo con versión exacta** (Joaco, 2026-10-27): queda en el `package-lock` con verificación de integridad y la actualiza Dependabot. Se usa solo dentro de GitHub Actions. Es la forma documentada de publicar desde una CI propia: `pull`, `build --prod` y `deploy --prebuilt --prod`. No es una tecnología nueva para la app, porque Vercel ya estaba en el stack. Claude Code no la usa: el hook `guard.mjs` la bloquea.
  - **Versión 63.1.2** (9 de octubre de 2026), la más nueva con al menos dos semanas de publicada.
  - **`npm audit` sobre lo que se publica** (`--omit=dev`) da 0 vulnerabilidades.
  - **`npm audit` completo** suma unas 30 altas y 1 crítica, todas de las dependencias de esta CLI. La versión 58.4.4 tenía las mismas.
    - Las altas son casi todas de denegación de servicio con datos armados a propósito (`js-yaml`, `minimatch`, `path-to-regexp`, `zod`, `undici` y otras).
    - La crítica es `tar`, al descomprimir archivos maliciosos.
    - La CLI corre solo en GitHub Actions, con nuestro propio código y sin archivos de terceros, y no llega a la app. Se acepta el riesgo.
    - Dependabot la actualiza cada mes. Se revisa de nuevo antes de producción.
- **Vercel sin clave de servidor:** el proyecto solo tiene `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. No se usa la integración Vercel–Supabase, porque copia la `service_role`.
- **Prueba de Vitest** `tests/hooks/staging-config.test.ts`: vigila todo lo anterior.

## Consecuencias

- La app nunca queda adelantada a la base, y una versión con pruebas en rojo nunca se publica.
- **El primer `db push` es la primera prueba real** sobre Supabase alojado. Si algo choca (roles propios, `pg_cron`, triggers en `auth.users`), se corrige con una migración nueva.
- **Correo:** recuperar la contraseña e invitar solo llegan a miembros de la organización de Supabase, y con pocos envíos por hora. La demo de la compuerta no los necesita. El servicio de correo propio se decide antes de producción.
- **Vercel "production" es nuestro staging.** Producción va a ser otro proyecto de Vercel y de Supabase, con su propio ambiente de GitHub y la aprobación de Soy.
- **Pendiente de Soy:** los planes de Supabase y Vercel. En el plan gratis, Supabase pausa los proyectos sin uso, y el plan Hobby de Vercel es para uso no comercial.
- **Bloqueante para crear producción:** el `SUPABASE_ACCESS_TOKEN` de hoy es el personal de Joaco y sirve para todas sus organizaciones, incluida la de Soy, donde va a estar producción. Antes de producción:
  - Soy crea una organización aparte solo para staging;
  - se transfiere `grupo-lf-staging`;
  - el token pasa a salir de una cuenta técnica, a nombre de Soy, que solo es miembro de esa organización.

  Decidido por Joaco el 2026-10-27, por la revisión de `security-auditor`.

- **A verificar en staging:**
  - el límite por IP de los ingresos que salen de la Edge Function (ADR-0014). `_shared/http.ts` toma el primer valor de `x-forwarded-for`: hay que probar con encabezados falsos qué IP queda registrada, y corregir la función si se puede esquivar;
  - que `config push` acepte `email_sent = 2`; si no, se saca esa línea.
- **Acciones de GitHub por etiqueta (`@v4`)**, igual que en `ci.yml`. Son de GitHub y las actualiza Dependabot. Fijarlas por SHA queda para antes de producción.
