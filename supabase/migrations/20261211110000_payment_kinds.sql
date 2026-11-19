-- Fase 3, Prompt 6 (ADR-0060): los valores nuevos de los tipos que usan los pagos. Van solos, en su propia transacción:
-- un valor nuevo de un enum no se puede usar en la misma transacción que lo crea.

alter type core.notification_kind add value 'payment_due';
alter type purchasing.doc_kind add value 'payment_receipt';

comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación), recipe_cost_changed (cambió el costo de una receta, sin importes), yield_deviation (un ensayo de rendimiento se desvió del estándar más que el umbral), supplier_account_changed (cambió una cuenta de pago de un proveedor), unmapped_article (llegó un artículo de proveedor que el sistema no reconoce), price_list_expired (venció la lista de precios de un proveedor), order_news (novedad de una orden de compra), receipt_report y receipt_differences (informe y diferencias de una recepción), invoice_observed (una factura no pasó el control), price_variation (un precio de factura varió más que el umbral) y payment_due (una factura vence en 7 días o venció: lo ve quien paga).';
comment on type purchasing.doc_kind is
  'Qué muestra un archivo de compras: price_list (la lista de precios), receipt_original y receipt_signed (el papel de la recepción como llegó y firmado), product_issue (la foto de un producto observado), invoice_original (la factura), credit_note (una nota de crédito o débito) y payment_receipt (el comprobante de un pago).';
