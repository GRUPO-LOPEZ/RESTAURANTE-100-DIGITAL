# Guía: poner en marcha el ambiente de prueba (staging)

Para Joaco. Se hace una sola vez. Decisión técnica: ADR-0018.

**Regla de oro:** las contraseñas, tokens y claves se copian directo de un panel a otro. Nunca pasan por el chat, por Claude Code ni por un archivo del repositorio.

## 1. Supabase

1. Confirmá que el proyecto `grupo-lf-staging` está en la **organización de Soy**: arriba a la izquierda del panel tiene que aparecer el nombre de su organización.
2. **Token de acceso:**
   - Entrá a tu cuenta → **Account → Access Tokens → Generate new token**.
   - Ponele de nombre `github-actions-staging`.
   - Copialo: se ve una sola vez.
3. **Conexión para los datos de prueba:**
   - En el proyecto, botón **Connect**, opción **Session pooler**.
   - Copiá la dirección que empieza con `postgresql://`.
   - Reemplazá `[YOUR-PASSWORD]` por la contraseña de la base.

   No uses la "Direct connection": GitHub Actions no la puede usar.

## 2. Vercel

1. Soy crea la cuenta y un equipo (team) a su nombre, y te invita como miembro.
2. Creá un proyecto llamado `grupo-lf-staging`:
   - **No** lo conectes con el repositorio de GitHub: lo publica GitHub Actions.
   - **No** instales la integración de Supabase, porque copia la clave `service_role`.
3. Fijate que la dirección del proyecto sea `https://grupo-lf-staging.vercel.app`. Si Vercel te da otra, avisame: hay que cambiarla en `supabase/config.toml` y en el flujo.
4. **Variables:**
   - En **Settings → Environment Variables**, entorno **Production**, cargá:
     - `NEXT_PUBLIC_SUPABASE_URL`: en Supabase, **Project Settings → API → Project URL**;
     - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: en Supabase, **Project Settings → API Keys → Publishable key**.
   - Ninguna otra.
5. **Token:**
   - En **Account Settings → Tokens**, creá un token con alcance solo en el equipo de Soy.
   - Ponele de nombre `github-actions-staging`.
6. **Los dos identificadores:**
   - **Team ID:** en **Team Settings → General**.
   - **Project ID:** en **Project Settings → General**.

## 3. GitHub

1. En el repositorio: **Settings → Environments → New environment**, con el nombre `staging`.
2. En **Deployment branches**, elegí **Selected branches** y agregá solo `main`.
3. En ese ambiente, cargá estos **secretos**:

| Secreto                 | Valor                                                           |
| ----------------------- | --------------------------------------------------------------- |
| `SUPABASE_ACCESS_TOKEN` | El token de Supabase (paso 1.2)                                 |
| `SUPABASE_DB_PASSWORD`  | La contraseña de la base de staging                             |
| `STAGING_PROJECT_REF`   | `tdbciscmemfdwjttgurj`                                          |
| `STAGING_DB_URL`        | La dirección del Session pooler, con la contraseña (paso 1.3)   |
| `STAGING_DEMO_PASSWORD` | Una contraseña nueva, de 16 caracteres o más, solo para la demo |
| `VERCEL_TOKEN`          | El token de Vercel (paso 2.5)                                   |
| `VERCEL_ORG_ID`         | El Team ID de Vercel                                            |
| `VERCEL_PROJECT_ID`     | El Project ID de Vercel                                         |

Guardá `STAGING_DEMO_PASSWORD` en tu gestor de contraseñas: es la que van a usar Soy y vos para entrar a la demo.

## 4. Primera publicación

1. Fusioná el pull request de staging. Cuando "Pruebas" termine en verde, arranca solo "Publicar en staging".
2. Si falla, abrí la corrida, copiá el error y pasámelo. El error no muestra claves, porque GitHub las tapa.
3. Cuando esté en verde: **Actions → Publicar en staging → Run workflow**, rama `main`, con la casilla **Cargar las personas y datos de prueba** tildada.
4. Entrá a `https://grupo-lf-staging.vercel.app` con `direccion@ejemplo.test` y la contraseña de la demo. Te va a pedir que actives la doble verificación con una app del celular (Google Authenticator, Microsoft Authenticator o similar).

## Personas de prueba

Todas usan la misma contraseña (`STAGING_DEMO_PASSWORD`).

| Correo                    | Rol                                               | Doble verificación |
| ------------------------- | ------------------------------------------------- | ------------------ |
| `superadmin@ejemplo.test` | Superadministrador                                | Sí                 |
| `direccion@ejemplo.test`  | Dirección General                                 | Sí                 |
| `direccion2@ejemplo.test` | Dirección General (para aprobar lo de la primera) | Sí                 |
| `director@ejemplo.test`   | Director de Marca (Demo Pastas)                   | Sí                 |
| `gerente@ejemplo.test`    | Gerente (Demo Pastas Centro)                      | Sí                 |
| `gerente2@ejemplo.test`   | Gerente de dos locales                            | Sí                 |
| `chef@ejemplo.test`       | Chef Ejecutivo                                    | No                 |
| `jefecocina@ejemplo.test` | Jefe de Cocina                                    | No                 |
| `controller@ejemplo.test` | Controller                                        | Sí                 |
| `compras@ejemplo.test`    | Compras                                           | No                 |
| `cocinero@ejemplo.test`   | Cocinero (Demo Pastas Centro)                     | No                 |
| `auditor@ejemplo.test`    | Auditor                                           | No                 |

Los correos `@ejemplo.test` no existen, así que "recuperar contraseña" no funciona con estas cuentas. Se entra solo con la contraseña.

## Si algo sale mal

- **"STAGING_PROJECT_REF no coincide":** el secreto no es `tdbciscmemfdwjttgurj`. Revisalo.
- **"Los datos de prueba solo se cargan en una base vacía":** la base ya tiene personas o grupos. No se tocó nada.
- **El proyecto de Supabase está pausado** (plan gratis, sin uso): en el panel, **Restore project**, y volvé a correr el flujo.
