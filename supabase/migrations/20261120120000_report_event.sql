-- Fase 2 · Etapa 2.5: reportes (ADR-0034), parte 1. Va sola porque un valor nuevo de un enum no se puede usar en la misma
-- transacción que lo agrega.
set role audit_owner;
alter type audit.security_event_type add value 'report_exported';
comment on type audit.security_event_type is
  'Tipo de evento de seguridad: ingreso bueno o fallido, cuenta bloqueada o liberada (intentos fallidos), operación rechazada por falta de permiso, cuenta desactivada, reactivada, suspendida o con la suspensión levantada, contraseña cambiada, doble verificación registrada, historial exportado y reporte exportado.';
reset role;
