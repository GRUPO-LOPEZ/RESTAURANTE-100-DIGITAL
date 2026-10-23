-- Fase 1 · Alineación con el documento de Soy (docs/fases/fase-1.md, ADR-0015), parte 1: tipos.
-- Va sola porque un valor nuevo de un enum no se puede usar en la misma transacción que lo agrega.
-- La parte 2 (20261021180100_align_with_phase_doc.sql) recrea las funciones que usan estos valores.

-- Estados de cuenta (sección 4): activo, suspendido y desactivado. Decisión de Joaco del 2026-10-21:
-- suspender es una pausa que se levanta sin aprobación; desactivar es que la persona se fue.
alter type core.account_status rename value 'disabled' to 'deactivated';
alter type core.account_status add value 'suspended' before 'deactivated';
comment on type core.account_status is
  'Estado de una cuenta: active (puede operar), suspended (pausa temporal: no entra hasta que se levante, sin aprobación) o deactivated (la persona se fue: volver necesita una aprobación). Conserva toda su historia.';

set role audit_owner;

-- Acciones de la auditoría (sección 6): además de las de fila, aprobar, rechazar y publicar.
alter type audit.action add value 'approve';
alter type audit.action add value 'reject';
alter type audit.action add value 'publish';
comment on type audit.action is
  'Qué pasó con el registro: insert (alta), update (cambio), soft_delete (borrado lógico), restore (restauración), delete (borrado físico, solo mantenimiento), approve o reject (una decisión de aprobación) y publish (una versión publicada).';

-- Origen del cambio (sección 6): manual, importación, integración, agente. Se conservan los propios
-- del sistema (función de servidor, seed, mantenimiento y Supabase Auth).
alter type audit.change_origin rename value 'app' to 'manual';
alter type audit.change_origin add value 'integration' after 'import';
comment on type audit.change_origin is
  'Desde dónde se hizo un cambio: manual (una persona desde la aplicación), edge_function (función de servidor), agent (agente de IA), import (carga masiva), integration (sistema externo), seed (datos de prueba), maintenance (mantenimiento documentado) o auth (Supabase Auth, por ejemplo al ingresar).';

-- Eventos de seguridad nuevos: suspensión, cambio de contraseña, doble verificación y exportaciones.
alter type audit.security_event_type add value 'account_suspended';
alter type audit.security_event_type add value 'account_unsuspended';
alter type audit.security_event_type add value 'password_changed';
alter type audit.security_event_type add value 'mfa_enrolled';
alter type audit.security_event_type add value 'audit_exported';
comment on type audit.security_event_type is
  'Tipo de evento de seguridad: ingreso bueno o fallido, cuenta bloqueada o liberada (intentos fallidos), operación rechazada por falta de permiso, cuenta desactivada, reactivada, suspendida o con la suspensión levantada, contraseña cambiada, doble verificación registrada e historial exportado.';

reset role;
