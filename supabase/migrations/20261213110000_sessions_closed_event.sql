-- Cerrar las sesiones de una persona queda en el registro de seguridad (Tanda 1 de Soy, Usuarios, ADR-0062). Va en su
-- propia migración: Postgres no deja usar un valor nuevo de un enum en la misma transacción que lo agrega.
set role audit_owner;
alter type audit.security_event_type add value 'sessions_closed';
comment on type audit.security_event_type is
  'Tipo de evento de seguridad: ingreso bueno o fallido, cuenta bloqueada o liberada (intentos fallidos), operación rechazada por falta de permiso, cuenta desactivada, reactivada, suspendida o con la suspensión levantada, sesiones cerradas por quien administra a la persona, contraseña cambiada, doble verificación registrada, historial exportado y reporte exportado.';
reset role;

-- Y a la persona le llega un aviso (también cuando otro le cambia el nombre).
alter type core.notification_kind add value 'account_changed';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación), recipe_cost_changed (cambió el costo de una receta, sin importes), yield_deviation (un ensayo de rendimiento se desvió del estándar más que el umbral), supplier_account_changed (cambió una cuenta de pago de un proveedor), unmapped_article (llegó un artículo de proveedor que el sistema no reconoce), price_list_expired (venció la lista de precios de un proveedor), order_news (novedad de una orden de compra), receipt_report y receipt_differences (informe y diferencias de una recepción), invoice_observed (una factura no pasó el control), price_variation (un precio de factura varió más que el umbral), payment_due (una factura vence en 7 días o venció: lo ve quien paga) y account_changed (otra persona le cambió el nombre o le cerró las sesiones: lo ve en Mi cuenta).';
