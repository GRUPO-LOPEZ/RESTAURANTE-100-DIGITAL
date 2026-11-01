# ADR-0028 — El sellado de la auditoría no deja huecos en la secuencia

- **Fecha:** 2026-11-01
- **Estado:** aceptada por Joaco (plan aprobado). Arreglo de la Fase 1.
- **Base:** reglas de seguridad (`.claude/rules/security.md`): la historia es inalterable y se puede verificar.

## Contexto

- **Qué pasó:** el 2026-10-31, al fusionar `main` en la rama de la importación, falló la prueba `060` ("los sellos del registro de seguridad verifican"). Nadie había tocado ningún evento.
- **Cómo funciona el sellado:** la auditoría y el registro de seguridad se sellan cada hora con una tarea programada (`audit.seal_all`, a los 7 minutos). Cada sello cubre un tramo de eventos y encadena su huella con la del anterior.
- **La causa:**
  - el sellado tomaba los eventos con más de 10 minutos de antigüedad y salteaba los más nuevos, **aunque quedaran en el medio** de la secuencia;
  - el sello guarda hasta qué número llega y cuántos eventos tiene;
  - la verificación recorre todo lo que hay hasta ese número.
  - Con un evento nuevo salteado en el medio, no coinciden: el sello sale "alterado".
- **Cuándo pasa:**
  - **en local:** si la tarea corre en los 10 minutos posteriores a un `db reset`. Los eventos del seed tienen fechas viejas y números más altos que los recién creados;
  - **en producción:** con dos transacciones que se cruzan. El evento con número más bajo puede tener una hora más nueva.
- **Por qué importa:** es una **falsa alarma de auditoría alterada**, justo en lo que tiene que dar confianza. Además, con muchas falsas alarmas una alteración real pasaría desapercibida.

## Decisión

- **El sellado toma solo el tramo continuo:** recorre los eventos sin sellar en orden de secuencia y **se detiene en el primer evento demasiado nuevo**, sin saltearlo. Lo demás se sella en la corrida siguiente, cuando todo el tramo tiene la antigüedad pedida.
- **Funciones cambiadas:** `audit.seal_events` y `audit.seal_security_events`, en la migración `20261107120000_audit_seal_contiguous.sql`. Mantienen la misma firma, el mismo dueño (`audit_owner`) y los mismos permisos.
- **Las verificaciones no cambian:** su regla (todo lo que hay hasta el último número sellado tiene que estar en el sello) es la correcta.

- **Ningún evento puede tener fecha futura** (trigger `audit.reject_future_event` en los dos registros). Con el sellado continuo, un evento así lo frenaría para siempre y sin aviso. Los triggers de la app nunca ponen la fecha (usan la hora de la transacción); el control rechaza también una carga a mano (revisión de seguridad, menor 1).

## Lo que no cubre

- **Una transacción de más de 10 minutos que se cruce con el sellado** (revisión de base, medio 1).
  - **Por qué deja un hueco:** la hora del evento es la del comienzo de su transacción, pero el número se le asigna al grabarlo.
  - **Los dos casos:**
    - una transacción todavía abierta con un número menor que un evento ya confirmado con más de 10 minutos;
    - una transacción confirmada que empezó hace más de 10 minutos y tomó su número después que otras.
  - **Hoy es muy improbable:** las operaciones tardan segundos (la confirmación de una importación completa, unos 5).
  - **Pendiente antes de las importaciones grandes:** acotar la duración de las transacciones (`statement_timeout` e `idle_in_transaction_session_timeout` por rol) a menos que el margen del sellado, o subir ese margen.
- **Por qué no frenar en cualquier hueco de numeración:** las transacciones que se deshacen dejan huecos para siempre, y el sellado no avanzaría nunca.
- **Si alguna vez pasa:** la verificación lo marca y se investiga. Nunca se borra ni se reescribe un sello.

## Pruebas

- **`025_audit_seal_order.test.sql` (14):** en los dos registros, una secuencia con un evento nuevo en el medio: dos viejos, uno nuevo y dos viejos.
  - el sello toma los dos primeros y se detiene antes del nuevo;
  - verifica bien;
  - la corrida siguiente sella el resto y todo sigue verificando.
  - **Comprobado contra el código anterior** (las funciones viejas, dentro de una transacción que se deshace): fallan 10 de 14 casos. El sello toma cuatro eventos, salteando el nuevo, y la verificación da "alterado". Es la falsa alarma.
  - La verificación se calcula en una sentencia aparte del sellado: en la misma sentencia no vería el sello recién creado.
- **Reproducido el caso real:**
  - después de un `db reset` y con `audit.seal_all()` forzado en el momento, antes se sellaban 174 eventos con un hueco;
  - ahora no se sella nada hasta que el primer evento cumple los 10 minutos;
  - `060` y `020` pasan.
- **Sellos existentes:** no hay datos reales en producción, así que no hay sellos con huecos que migrar.
