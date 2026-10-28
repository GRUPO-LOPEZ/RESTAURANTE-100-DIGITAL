# Guía: poner en marcha el ambiente de prueba (staging)

Para Joaco. Se hace una sola vez. Decisión técnica: ADR-0018.

**Regla de oro:** las contraseñas, tokens y claves se copian directo de un panel a otro. Nunca pasan por el chat, por Claude Code ni por un archivo del repositorio.

## 1. Supabase

1. Confirmá que el proyecto `grupo-lf-staging` está en la **organización de Soy**: arriba a la izquierda del panel tiene que aparecer el nombre de su organización.
2. **Token de acceso:**
   - Entrá a tu cuenta → **Account → Access Tokens → Generate new token**.
   - Ponele de nombre `github-actions-staging`.
   - Copialo: se ve una sola vez.

   **Ojo:** ese token sirve para todas las organizaciones de tu cuenta, no solo para staging. Hoy está bien, porque producción no existe. **Antes de crear producción**, Soy crea una organización aparte solo para staging, se mueve `grupo-lf-staging` ahí (**Project Settings → General → Transfer project**) y el token pasa a salir de una cuenta técnica que solo es miembro de esa organización (ADR-0018).

3. **Conexión para los datos de prueba:**
   - En el proyecto, botón **Connect**, opción **Session pooler**.
   - Copiá la dirección que empieza con `postgresql://postgres.tdbciscmemfdwjttgurj`.
   - **Borrale la contraseña:** sacá `:[YOUR-PASSWORD]`, con los dos puntos incluidos. Tiene que quedar así: `postgresql://postgres.tdbciscmemfdwjttgurj@aws-…pooler.supabase.com:5432/postgres`. La contraseña la toma el flujo de `SUPABASE_DB_PASSWORD`; si la URL la trae, el flujo se corta.

   No uses la "Direct connection": GitHub Actions no la puede usar.

## 2. Vercel

1. Soy crea la cuenta y un equipo (team) a su nombre, y te invita como miembro.
2. El proyecto de Vercel de staging es `restaurante-100-digital`:
   - **No** lo conectes con el repositorio de GitHub: lo publica GitHub Actions.
   - **No** instales la integración de Supabase, porque copia la clave `service_role`.
3. La dirección del proyecto es `https://restaurante-100-digital.vercel.app`. Si cambia, hay que cambiarla en `supabase/config.toml`, en el flujo y en su prueba. El flujo además comprueba, después de publicar, que esa dirección sea de este equipo.
4. **Variables:**
   - En **Settings → Environment Variables**, entorno **Production**, cargá:
     - `NEXT_PUBLIC_SUPABASE_URL`: en Supabase, **Project Settings → API → Project URL**;
     - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: en Supabase, **Project Settings → API Keys → Publishable key**.
   - Ninguna otra.
5. **Token:**
   - En **Account Settings → Tokens**, creá un token con alcance solo en el equipo de Soy.
   - Ponele de nombre `github-actions-staging`.
   - **Antes de crear producción**, el proyecto de producción va en un equipo de Vercel distinto, para que este token no lo alcance (ADR-0018).
6. **Los dos identificadores:**
   - **Team ID:** en **Team Settings → General**.
   - **Project ID:** en **Project Settings → General**.

## 3. GitHub

1. En el repositorio: **Settings → Environments → New environment**, con el nombre `staging`.
2. En **Deployment branches**, elegí **Selected branches** y agregá solo `main`.
3. En ese ambiente, cargá estos **secretos**:

| Secreto                       | Valor                                                                    |
| ----------------------------- | ------------------------------------------------------------------------ |
| `SUPABASE_ACCESS_TOKEN`       | El token de Supabase (paso 1.2)                                          |
| `SUPABASE_DB_PASSWORD`        | La contraseña de la base de staging                                      |
| `STAGING_PROJECT_REF`         | `tdbciscmemfdwjttgurj`                                                   |
| `STAGING_DB_URL`              | La dirección del Session pooler, **sin** la contraseña (paso 1.3)        |
| `STAGING_DEMO_ADMIN_PASSWORD` | Contraseña nueva para los roles con doble verificación (ver abajo)       |
| `STAGING_DEMO_PASSWORD`       | Otra contraseña nueva, distinta, para el resto de las personas de prueba |
| `VERCEL_TOKEN`                | El token de Vercel (paso 2.5)                                            |
| `VERCEL_ORG_ID`               | El Team ID de Vercel                                                     |
| `VERCEL_PROJECT_ID`           | El Project ID de Vercel                                                  |

Las dos contraseñas de la demo tienen que tener 16 caracteres o más, con letras y números, y ser distintas. Guardalas en tu gestor de contraseñas.

## 4. Primera publicación

1. Fusioná el pull request de staging. Cuando "Pruebas" termine en verde, arranca solo "Publicar en staging".
2. Si falla, abrí la corrida, copiá el error y pasámelo. El error no muestra claves, porque GitHub las tapa.
3. Cuando esté en verde: **Actions → Publicar en staging → Run workflow**, rama `main`, con la casilla **Cargar las personas y datos de prueba** tildada.
4. **Antes de pasarle cualquier contraseña a otra persona,** entrá a `https://restaurante-100-digital.vercel.app` con **cada una** de las cuentas que tienen doble verificación (tabla de abajo), con `STAGING_DEMO_ADMIN_PASSWORD`. En cada una te va a pedir que la actives con una app del celular (Google Authenticator, Microsoft Authenticator o similar). Las de Dirección las puede activar Soy con su celular.

## Personas de prueba

- **Con doble verificación:** usan `STAGING_DEMO_ADMIN_PASSWORD`. Esa contraseña la tienen **solo Joaco y Soy**. Si alguien más la tuviera antes de que esté activada la doble verificación, podría registrar su propio celular y quedarse con la cuenta.
- **El resto:** usa `STAGING_DEMO_PASSWORD`, que se puede compartir para probar.

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

- **"STAGING_PROJECT_REF no coincide":** el secreto llega vacío o no es `tdbciscmemfdwjttgurj`.
  - Revisá que esté en **Environment secrets** del ambiente `staging`, no en variables ni en otro ambiente.
  - Si **Settings → Environments** no existe o da "página no encontrada", hay dos causas posibles:
    - no sos Admin del repositorio;
    - la organización está en el plan gratis de GitHub, que no tiene ambientes en repositorios privados.
  - En los dos casos lo resuelve Soy.
- **"STAGING_DB_URL no es la del pooler de staging":** la dirección no empieza con `postgresql://postgres.tdbciscmemfdwjttgurj@` o todavía tiene la contraseña adentro (paso 1.3).
- **"El proyecto de Vercel no apunta a la base de staging":** revisá `NEXT_PUBLIC_SUPABASE_URL` en Vercel (paso 2.4).
- **Una cuenta de prueba quedó bloqueada** (5 intentos fallidos): se libera sola a los 10 minutos, o la libera antes un administrador desde la ficha de la persona.
- **Alguien activó la doble verificación con el celular equivocado:** en el panel de Supabase de staging, **Authentication → Users**, se le borra el factor a esa persona, y vuelve a activarla quien corresponde. Es staging: en producción esto se hace con aprobación.
- **"Los datos de prueba solo se cargan en una base vacía":** la base ya tiene personas o grupos. No se tocó nada.
- **El proyecto de Supabase está pausado** (plan gratis, sin uso): en el panel, **Restore project**, y volvé a correr el flujo.
