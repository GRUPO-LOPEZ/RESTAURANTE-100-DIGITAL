# ADR-0014 — Cómo se implementó el ingreso: Edge Functions, hook y registro de seguridad

- **Fecha:** 2026-10-21
- **Estado:** aceptada. Es la implementación de ADR-0009 y ADR-0010, dentro del plan aprobado de la Fase 1. Migraciones `20261020225110` y `20261020225120`, y carpeta `supabase/functions/`.

## Decisión

1. **Registro de seguridad: `audit.security_events`.** Reemplaza al nombre `authentication_security_events` de la primera versión de `database.md`, porque guarda más que ingresos.
   - **Actualizado por ADR-0015 (2026-10-21):** el documento de Soy manda, y la tabla volvió a llamarse `audit.authentication_security_events`, con `user_id`, `ip_address` y `detail`.
   - Qué guarda: ingresos buenos y fallidos, bloqueos y liberaciones, operaciones rechazadas, desactivaciones y reactivaciones.
   - Protección: solo de inserción, con sus propios sellos (`audit.security_event_seals`). Nadie lo lee por la API.
2. **Edge Function `auth-login` (pública).** La usa la acción de servidor de `/ingresar`. Pasos:
   1. revisa si la cuenta está bloqueada;
   2. pide el token a Supabase Auth;
   3. si la contraseña es incorrecta, anota el fallo. Al quinto fallo seguido dentro de 10 minutos, bloquea la cuenta 10 minutos (P18).

   Los mensajes nunca dicen si el correo existe.

3. **Edge Function `invite-user` (exige sesión).**
   - Valida con la identidad de quien invita: `core.can_invite`.
   - Invita con la Admin API.
   - Suma a la persona al grupo y le da el rol: `core.add_member` y `core.assign_role`, también con su identidad.
4. **La clave de servidor (`service_role`)** la pone Supabase dentro de cada Edge Function. No está en la app, ni en el navegador, ni en el repositorio, ni en ningún `.env`.
   - En la base solo puede ejecutar dos funciones: `core.login_status` y `core.record_failed_login`. La prueba `080_accounts` fija esa lista.
5. **Custom Access Token hook (`core.custom_access_token_hook`).** Supabase Auth lo llama antes de entregar cada token: al ingresar y al renovar la sesión.
   - Niega el token a las cuentas desactivadas, borradas o bloqueadas.
   - Pone en cero los fallos y registra el ingreso.
   - Solo lo ejecuta `supabase_auth_admin`.
6. **Doble verificación (TOTP).**
   - El primer ingreso de un rol que la exige obliga a registrar la app de autenticación.
   - `has_permission` no deja operar sin `aal2`.
   - En el seed hay un secreto TOTP **ficticio y solo local** para las pruebas.
7. **Origen `auth` en la auditoría**, para los cambios que hace Supabase Auth. Va en su propia migración, porque un valor nuevo de un enum no se puede usar en la misma transacción que lo agrega.
8. **Sellado cada hora** con `pg_cron`, que llama a `audit.seal_all()` para la auditoría y el registro de seguridad.
9. **`.env.example`** tiene la URL y la clave publishable de Supabase **local**, que son públicas. La CI verifica que esa clave coincida con la de su Supabase local.

## Límites

- **Intentos por fuera de la pantalla:** los que alguien haga llamando a Auth directamente no cuentan para el bloqueo de 5 (ADR-0010). Igual nunca reciben un token si la cuenta está bloqueada.
- **Registrar la doble verificación con la contraseña sola:** en el plan Free y Pro, una persona sin factor registrado podría hacerlo. Por eso la pantalla obliga a registrarla en el primer ingreso.
- **Abuso del registro de seguridad:** cualquier sesión puede generar eventos de "operación rechazada" a propósito. Antes de producción conviene limitar la frecuencia.
- **Límite por IP en staging y producción:** los ingresos salen de la IP de la Edge Function, así que hay que verificar cómo cuenta Auth ese límite.

## Revisión del 2026-10-21 (base, seguridad y diseño)

Se corrigió en `20261021133336_accounts_review_fixes.sql`:

- **Contador de intentos por correo**, exista o no la cuenta (`core.login_throttles`). El bloqueo ya no revela qué correos existen.
  - La ventana de 10 minutos cuenta desde el primer fallo.
  - Un fallo durante un bloqueo no lo extiende.
  - El contador salió del perfil: antes, cada fallo dejaba además un evento en la auditoría.
- **Rendimiento:** la bandeja de aprobaciones y el historial filtran por conjuntos y por índice. La bandeja separa pendientes y resueltas y pagina con cursor. Con 5.000 solicitudes y 100.000 eventos responden en menos de 300 ms para cualquier alcance; antes tardaban entre 5 y 19 segundos.
- **Tablero de usuarios:** solo muestra los roles que la sesión puede ver, y filtra por marca.
- **Reactivación:**
  - al aplicarse vuelve a validar que quien pidió tenga permiso y que la cuenta siga desactivada;
  - quien aprueba tiene que poder actuar sobre esa persona (no puede tener menos permisos que ella).
- **IP del cliente:** la Edge Function ya no le reenvía a Auth la IP que manda el cliente, porque se podía falsificar. En el registro queda como dato informativo.
- **Encabezados de seguridad:** no se puede meter la app dentro de otro sitio (`frame-ancestors 'none'`), y se suman `nosniff`, `Referrer-Policy` y HSTS.

**Riesgos que quedan, para decidir con Joaco antes de producción:**

1. **Intentos directos a Auth.** No cuentan para el bloqueo ni quedan en el registro: solo los frena el límite por IP de Supabase. Para cerrarlo hay dos caminos: el plan Teams (opción A de ADR-0010) o CAPTCHA en Auth.
2. **Bloqueo sostenido a propósito.** Cualquiera que conozca un correo puede fallar 5 veces cada 10 minutos y dejar a esa persona afuera, aunque sea un superadmin. Opciones:
   - dejar entrar igual a las cuentas con doble verificación si la contraseña y el código son correctos;
   - demoras crecientes en lugar de bloqueo;
   - CAPTCHA.
3. **Primer factor de doble verificación.** Una persona sin factor registrado lo puede registrar con solo la contraseña. Pasa, por ejemplo, con un cocinero ascendido a gerente.
4. **Quién aprueba una reactivación.** Hoy basta con otra persona con `users.deactivate` que pueda actuar sobre esa persona. Ejemplo: dos gerentes pueden deshacer una baja que hizo el superadmin. ¿Tiene que aprobar alguien de igual o mayor alcance que quien desactivó?
5. **Enlace mágico y recuperación de contraseña.** Siguen activos en Auth, así que quien tenga acceso al correo de un rol sin doble verificación puede entrar sin contraseña. El hook igual niega las cuentas bloqueadas y desactivadas.
6. **Antes de producción:**
   - límite de frecuencia para los eventos de "operación rechazada";
   - una política de contenido (CSP) completa;
   - fijar la dirección de vuelta de la invitación con una variable del servidor.
7. **Para la Fase 2 (costos):** `core.hide_costs` oculta por nombre de campo. Con las tablas de costos hay que pasar a una lista explícita de columnas por tabla, probada en pgTAP.
8. **Para cuando haya más de un grupo:** los eventos de identidad sin grupo los ve cualquier persona con `audit.view` de grupo.
