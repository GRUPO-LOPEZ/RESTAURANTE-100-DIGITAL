# Informe de cierre de la Fase 1 — Fundaciones: identidad, permisos y auditoría

- **Para:** Soy (dueño y aprobador final).
- **Preparado por:** Joaco, con Claude Code.
- **Fecha:** 2026-10-21.
- **Estado:** listo para la demo **en local**. Antes de la demo de la compuerta (sección 12), hace falta el ambiente de prueba (staging): ver "Lo que falta".

## Qué se hizo, en simple

El sistema ya sabe **quién es cada persona, qué puede hacer y dónde**, y **guarda cada cambio para siempre**.

- **Entrar:**
  - Solo por invitación.
  - Las cuentas de dirección, marca, gerencia y costos usan una app de doble verificación en el celular.
  - Se puede recuperar la contraseña por correo.
  - "Recordar sesión" es opcional.
  - Cinco intentos fallidos bloquean la cuenta 10 minutos.
- **Mi cuenta:** cada persona cambia su nombre y su contraseña, cambia de celular para la doble verificación y ve dónde tiene la sesión abierta. Puede cerrar las demás sesiones, y se cortan en el momento.
- **Ver solo lo propio:** cada persona ve su grupo, su marca o su local. Quien tiene varios locales elige con cuál trabajar, y la app lo recuerda.
- **Cuentas:**
  - **Suspender** es una pausa, por ejemplo una licencia: corta el acceso al instante y se levanta sin aprobación.
  - **Desactivar** es para quien se va: para volver hace falta que lo apruebe otra persona.
- **Aprobaciones:**
  - Los cambios sensibles los aprueba otra persona, nunca quien los pidió.
  - Quien puede decidir recibe un aviso en la app.
  - La bandeja muestra el antes y el después.
- **Roles y permisos:** una pantalla muestra qué puede hacer cada rol. Cambiarlo pide un motivo y la aprobación de Dirección General.
- **Historial:**
  - Quién cambió qué, cuándo y por qué.
  - Se busca por fecha, persona, marca, local y módulo, y se exporta a una planilla.
  - Nadie lo puede borrar ni modificar.
- **Tablero de usuarios:** responde "¿quién tiene acceso y qué está pasando?" con:
  - cuentas activas y desactivadas;
  - aprobaciones pendientes;
  - accesos rechazados de la semana;
  - el gráfico de ingresos de 30 días;
  - las personas por local y por rol;
  - los últimos cambios importantes.
- **Documento de ensayo:** imita una receta para probar que el cocinero no ve costos y que una versión publicada no se modifica. Quien lo manda a revisión no lo puede publicar: lo publica otra persona. Se borra al empezar la Fase 2.
- **Dónde trabaja cada persona limita sus roles:** a alguien de un local solo se le dan roles de ese local.
- **Datos sensibles de cada persona:** el último acceso, quién la invitó y por qué se la suspendió o dio de baja los ve solo quien la administra.
- **Formularios más claros:** si falta algo, el error aparece debajo del campo antes de enviar.

## Pruebas

Verificación completa del 2026-10-22, en la computadora de desarrollo y desde una base nueva, ya con las respuestas de Joaco:

| Prueba                                                                                         | Resultado                                           |
| ---------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| Base de datos: permisos, auditoría, aprobaciones y rendimiento (pgTAP)                         | ✅ 736 de 736                                       |
| Lógica y configuración (Vitest)                                                                | ✅ 95 de 95                                         |
| Pantallas en celular y computadora, con accesibilidad (Playwright + axe)                       | ✅ 58 de 58                                         |
| Formato, lint y tipos                                                                          | ✅                                                  |
| Las 13 pruebas obligatorias y las 10 adicionales del Módulo Maestro                            | ✅ (mapa en `docs/modulos/00-identidad.md`)         |
| Rendimiento del tablero, el historial y la bandeja, con 500 a 2.000 personas y 100.000 eventos | ✅ todo por debajo de 300 ms (lo más lento, 150 ms) |

Además, la revisaron los tres revisores automáticos (base de datos, seguridad y diseño), dos veces. Lo grave y lo medio está corregido.

**Todavía no se vio en GitHub:** la primera corrida en GitHub Actions es al subir el pull request.

## Compuerta de cierre (sección 12)

| Punto                                                                      | Estado                                                     |
| -------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Vi en GitHub las 23 pruebas en verde                                       | Pendiente: hay que mirar GitHub Actions en el pull request |
| Entré como dirección y vi los 4 restaurantes de prueba                     | Listo en local (prueba `admin.spec.ts`)                    |
| Entré como gerente de un local y no vi los otros                           | Listo en local                                             |
| Entré como cocinero y no vi costos en el documento de ensayo               | Listo en local                                             |
| Pedí un cambio, intenté aprobarlo yo mismo y el sistema no me dejó         | Listo en local                                             |
| Otra persona lo aprobó y en el historial figuran ambos, con fecha y motivo | Listo en local                                             |
| Desactivé un usuario y perdió el acceso en el momento                      | Listo en local                                             |
| El tablero de control de usuarios se ve simple y se entiende en el celular | Listo en local (pantalla revisada en celular)              |
| Recibí el informe de cierre                                                | Este documento                                             |
| Las cuentas siguen a mi nombre y producción no tiene datos de prueba       | Para que lo confirme Soy                                   |

## Lo que falta (fuera del código)

- **Ambiente de prueba (staging)** y proyecto de desarrollo en la nube de Supabase, a nombre de Soy. La demo de la compuerta es sobre staging.
- **Vercel** para publicar la app de staging.
- **Proteger `main`** en GitHub (Joaco lo postergó).
- **Ver las pruebas en verde en GitHub Actions.**

## Riesgos y decisiones abiertas

- **Decisiones de Joaco:** las 9 preguntas abiertas están respondidas e implementadas (ADR-0015). Siguen abiertas las preguntas anteriores de `docs/estado.md`, que no frenan la demo pero sí la salida a producción.
- **Antes de producción** (ADR-0014): CAPTCHA o el plan Teams de Supabase, una política de contenido completa (CSP) y límites de frecuencia.
- **Sellos de la auditoría:** la migración de alineación solo se puede aplicar antes del primer sello. Hoy se cumple, porque no existen staging ni producción. Si alguna base ya selló algo, hay que recrearla.
