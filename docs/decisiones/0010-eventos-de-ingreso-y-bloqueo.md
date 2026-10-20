# ADR-0010 — Eventos de ingreso y bloqueo por intentos fallidos

- **Fecha:** 2026-10-20
- **Estado:** aceptada por Joaco (P5, opción B). Se implementa en M8 y M9. Duración del bloqueo resuelta por Joaco (P18): 10 minutos, con liberación anticipada por un administrador.

## Contexto

La prueba adicional 7 del Módulo Maestro pide: "Tras 5 intentos fallidos de login se bloquea temporalmente y queda registrado". Además, la prueba 11 y ADR-0009 piden un registro de seguridad que sobreviva a los rechazos.

Según la documentación de Supabase, consultada el 2026-10-20:

- El _Password Verification Attempt hook_, que recibe cada intento de contraseña válido o inválido y puede rechazarlo, está disponible solo en los planes **Teams y Enterprise**.
- El _Custom Access Token hook_ está en los planes **Free y Pro**:
  - corre antes de entregar cada token, también al renovarlo (`authentication_method = token_refresh`);
  - puede negarlo devolviendo un error con `http_code`;
  - puede ser una función de Postgres y se configura en local en `config.toml`.

## Opciones

- **A. Password Verification Attempt hook.** Supabase cuenta y bloquea cada intento, venga de donde venga. Requiere el plan Teams.
- **B. Ingreso por una función de servidor propia + Custom Access Token hook.** Funciona con Free y Pro.

## Decisión

**Opción B**, con la puerta abierta a A si Soy contrata Teams.

1. **El ingreso pasa por una función de servidor** de Next.js (acción de servidor) y no desde el navegador directo a Auth. La función:
   1. revisa si la cuenta está bloqueada temporalmente;
   2. si no lo está, intenta el ingreso con Auth;
   3. anota el resultado (ingreso o fallo) en el registro de seguridad del esquema `audit`, con una función que solo puede llamar el servidor;
   4. al quinto fallo seguido dentro de la ventana, bloquea la cuenta temporalmente.
2. **Custom Access Token hook** (función de Postgres): niega el token si la cuenta está bloqueada, temporal o definitivamente (`disabled`). Como corre también al renovar la sesión:
   - una cuenta bloqueada no consigue sesión aunque la contraseña sea correcta, y aunque alguien llame a Auth sin pasar por nuestra pantalla;
   - una cuenta desactivada pierde la sesión, a más tardar, en la próxima renovación. Esto se suma a `has_permission`, que ya corta el acceso en la consulta siguiente.
3. **Registro de seguridad.** Se arma junto con el de ADR-0009 y tiene las mismas protecciones que `audit_events`:
   - nadie lo modifica ni lo borra;
   - nunca guarda contraseñas ni tokens;
   - solo lo leen quienes tienen `audit.view`.

   Guarda la persona (si existe), el correo intentado normalizado, el resultado, la hora y el origen.

## Duración y liberación (P18)

- **5 fallos seguidos** de la misma cuenta, sin un ingreso bueno entre medio, dentro de 10 minutos → **bloqueo de 10 minutos**. Pasado ese tiempo se libera solo y el contador vuelve a cero. Un ingreso bueno también lo pone en cero.
- **Un administrador puede liberarlo antes** con una función (`core.unlock_user`). Hace falta `users.deactivate` en un alcance que cubra todas las asignaciones de la persona, con las mismas reglas sobre otra persona que M8. No pide aprobación: el bloqueo es temporal y se iba a liberar solo. Igual queda en el registro de seguridad, con quién lo liberó y por qué.
- No se confunde con la cuenta **desactivada** (`disabled`), que es definitiva hasta que se reactive, y la reactivación sí pide aprobación (ADR-0008).

## Límites (dichos claramente)

- Los intentos fallidos que alguien haga **llamando a Auth directamente**, sin pasar por nuestra pantalla, no se cuentan para el bloqueo de 5. Los frena el límite por IP de Supabase, y nunca obtienen sesión si la cuenta está bloqueada. Con la opción A este hueco se cierra.
- **Riesgo de abuso:** cualquiera que sepa el correo de otra persona puede fallar 5 veces a propósito y dejarla bloqueada un rato. Por eso:
  - el bloqueo es temporal;
  - el mensaje de la pantalla no dice si el correo existe;
  - se revisa en la revisión de seguridad de M8.
- La función que anota los intentos no se puede llamar desde el navegador: si no, alguien podría bloquear cuentas ajenas sin siquiera intentar entrar.

## Consecuencias

- Pasar a A, si Soy contrata Teams, no rehace nada: el registro de seguridad es el mismo, y solo cambia quién cuenta los intentos.
- La prueba adicional 7 se escribe en pgTAP (contador y bloqueo) y en Playwright (5 fallos en pantalla, bloqueo y registro).
- Hay que prender el hook en `config.toml` (local) y en el panel de cada proyecto remoto.
