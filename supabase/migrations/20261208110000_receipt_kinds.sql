-- Fase 3, Prompt 4 (ADR-0056), parte 1: los avisos de una recepción y los tipos de foto del papel. Va sola porque un
-- valor nuevo de un enum no se puede usar en la misma transacción que lo agrega.
alter type core.notification_kind add value 'receipt_report';
alter type core.notification_kind add value 'receipt_differences';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación), recipe_cost_changed (cambió el costo de una receta, sin importes), yield_deviation (un ensayo de rendimiento se desvió del estándar más que el umbral), supplier_account_changed (cambió una cuenta de pago de un proveedor: lo ve quien ve el pago, para controlarlo antes de pagar), unmapped_article (llegó un artículo de proveedor que el sistema no reconoce: lo resuelve el chef), price_list_expired (venció la lista de precios de un proveedor según su frecuencia: lo ve Compras), order_news (una orden de compra tiene una novedad, se aprobó, se rechazó o se canceló: lo ve quien la pidió), receipt_report (se recibió una orden de compra: lo ve quien la pidió) y receipt_differences (una recepción tuvo observaciones o se pagó en efectivo: lo ve Compras).';

alter type purchasing.doc_kind add value 'receipt_original';
alter type purchasing.doc_kind add value 'receipt_signed';
alter type purchasing.doc_kind add value 'product_issue';
comment on type purchasing.doc_kind is
  'Tipo de documento adjunto: price_list (la lista de precios escaneada o en PDF), receipt_original (foto 1 de una recepción: el remito o la factura como llegó), receipt_signed (foto 2: el papel firmado por quien recibió), product_issue (foto de un producto observado al recibir) u other.';
