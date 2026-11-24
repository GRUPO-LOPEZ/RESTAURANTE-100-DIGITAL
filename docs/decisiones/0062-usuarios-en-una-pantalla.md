# ADR-0062: Usuarios en una pantalla

- **Fecha:** 2026-11-24
- **Estado:** plan aprobado por Joaco el 2026-11-22 (tercer PR de la Tanda 1 de las correcciones de Soy, `docs/prompts/2026-11-22-correcciones-modulo-1.md`). Cierra la Tanda 1.
- **Sigue a:** ADR-0017 (aprobaciones de Dirección), ADR-0036 (ficha por pestañas, que se reemplaza), ADR-0046 y ADR-0051 (pantallas sin scroll), ADR-0061 (Panel de control).

## Problema

Soy pidió simplificar la carga de Usuarios, con poco o nada de scroll: la ficha de la persona en una pantalla, invitar en un modal corto, y revisar el tablero y la lista con la misma regla. Hoy la ficha va por pestañas, cada rol se da o se quita con su propio formulario, y el puesto y el área de una persona no se podían cargar desde ningún lado.

## Decisiones

1. **Un guardado para datos y roles** (`core.save_user_sheet`): nombre, apellido, puesto, área, roles que se dan y roles que se quitan, con un motivo y un sello.
   - El nombre pide `users.manage` («Editar personas», un permiso que existía y no se usaba) y tener todos los permisos de la persona (la regla de `core.cannot_act_on_user`). El puesto y el área, que no dan permisos, piden solo `users.manage` en todos sus lugares (ver «Decisiones de Joaco»).
   - Los roles pasan por `core.assign_role` y `core.revoke_role`: los mismos permisos, las mismas aprobaciones, y nadie se da roles a sí mismo.
   - **Todo o nada.** Si la base rechaza un paso, no queda nada. El rechazo se registra igual que antes, con el rol y el lugar.
   - **Cambiar un rol por otro que espera aprobación se rechaza** («guardalo primero y, cuando lo aprueben, quitá el anterior»): si no, la persona quedaba sin rol hasta que alguien decidiera.
   - Si al quitarle su último rol la persona sale del alcance de quien edita, la pantalla vuelve a la lista y lo dice.
2. **La ficha propia no se edita desde acá:** va en Mi cuenta.
3. **El área** que se le pone a una persona está en uso, es de un local donde trabaja y donde quien edita administra personas.
4. **Cerrar todas las sesiones** de otra persona (`core.close_user_sessions`), sin suspenderla. Pide `users.deactivate`, como suspender, y queda en el registro de seguridad (evento nuevo `sessions_closed`). Las propias, en Mi cuenta.
5. **Suspender, desactivar, reactivar y liberar el bloqueo** siguen igual (con sus aprobaciones), ahora como botones arriba a la derecha. El estado se muestra y no se elige: un control por cada cosa.
6. **Los botones salen de la base** (`core.user_sheet_state`): antes los veía cualquiera que viera la ficha y la base los rechazaba. Ahora se muestra lo que la sesión puede hacer o pedir; la base lo controla igual.
7. **Indicadores, con la regla de siempre:**
   - último ingreso, doble verificación y sesiones: quien administra a la persona;
   - cambios en 30 días: dentro de lo que cada uno ve del historial;
   - accesos rechazados en 7 días: quien ve el registro de seguridad. Cuenta solo los de la persona; antes la lista sumaba lo que otros habían intentado sobre su cuenta.
8. **En el celular, de consulta,** salvo lo urgente: suspender, desactivar, liberar el bloqueo y cerrar sesiones. Invitar también funciona (el modal; sin JavaScript, la página `/usuarios/invitar`).
9. **Nombres en el Historial:** 45 tablas con auditoría (recetas, compras, precios, razones sociales) decían «Dato del sistema». Ahora todas tienen nombre, y una prueba de Vitest lo vigila.

## Se aparta del boceto

- Nombre y apellido van en dos campos: la base los guarda separados.
- El estado de la cuenta no es un grupo de botones: los cambios van arriba, con su motivo y su aprobación.
- Se suman «Trabaja en» y el motivo de una suspensión o baja, que la ficha de antes ya mostraba.

## Revisión de `db-reviewer` (corregida antes del commit)

- **Grave:** cambiar un rol por otro pendiente dejaba a la persona sin rol y a quien lo hizo sin su ficha.
- **Medios:** el permiso se miraba antes del bloqueo; el rechazo perdía el rol y el lugar; los rechazos contaban los de otros; el área no se controlaba contra el lugar; otro Superadministrador se podía editar sin Dirección.

## Revisión de `security-auditor` (apto, sin graves; corregida antes del commit)

- **El registro de seguridad no se llena con texto libre:** las claves se controlan antes de registrar un rechazo (no se puede borrar).
- **Cada rechazo lleva su grupo,** así cuenta en el tablero de Usuarios.
- **Nombres y puestos que imitan a otro:** se rechazan los caracteres que no se ven y las variantes de «Administrador» y «Sistema» (ancho completo, separadas, con un signo adelante), y el puesto no puede decir «Superadministrador» o «Sistema». Vale también en Mi cuenta. No cubre letras parecidas de otro alfabeto: el cambio queda auditado y la persona se entera.
- **La persona se entera:** le llega un aviso si otro le cambia el nombre o le cierra las sesiones, con quién fue (tipo nuevo `account_changed`). Lo ve en Mi cuenta, con un número en su perfil, aunque no tenga la bandeja de aprobaciones.
- **También se registra** el intento de quitar por una ficha el rol de otra persona y el de poner un área fuera de alcance. Quien no puede guardar no llega a tomar los bloqueos, y cerrar sesiones mira el permiso dos veces.
- **Pendiente (de antes):** el alta por invitación (`invite-user`) no pasa por el control del nombre. Va en un PR aparte, porque toca una Edge Function. También, que las demás pantallas lean `?aviso=` con `own` como Usuarios.
- **Queda así:** los avisos no tienen tope (renombrar ida y vuelta avisa cada vez; todo auditado). El sello cambia con cualquier rol de la persona, también de otro local (no revela cuál), y dos personas con el mismo rol y lugar se pueden editar entre sí, como ya se podían suspender.

## Revisión de `ui-reviewer` (sin graves; corregida antes del commit)

Aviso y foco después de una acción sobre la cuenta, rol elegido y no agregado que no se pierde al guardar, errores junto a su campo, listas del tablero enteras a la vista, y textos.

## Decisiones de Joaco (2026-11-24)

- **Otro Superadministrador** queda como está: un Superadministrador no le edita los datos ni le cierra las sesiones a otro. Suspenderlo se puede pedir, como hoy.
- **El puesto y el área de cualquiera.** Se revisó darle `users.manage` a Dirección y no alcanza: la regla pide tener también todos los permisos de la persona, y Dirección no tiene los de la operación (por ejemplo, `recipes.review`): editaría solo a los Auditores. En cambio, como el puesto y el área no dan ningún permiso, cambiarlos pide `users.manage` en **todos** los lugares donde la persona tiene roles, sin exigir tener todos sus permisos (`core.cannot_place_user`). Así, el Superadministrador se los carga a Dirección, el Controller, los chefs y la Directora de Marca. Nadie se los cambia a sí mismo ni a otro Superadministrador. El nombre, los roles y las sesiones siguen con la regla de antes.
