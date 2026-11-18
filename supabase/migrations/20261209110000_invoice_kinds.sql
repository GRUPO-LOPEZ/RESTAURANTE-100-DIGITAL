-- Fase 3, Prompt 5 (ADR-0058): los valores nuevos de enums que usan las facturas. Van en su propia migración: un valor
-- agregado a un enum no se puede usar en la misma transacción que lo agrega.

alter type core.notification_kind add value if not exists 'invoice_observed';
alter type core.notification_kind add value if not exists 'price_variation';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (hay algo para aprobar), recipe_changed, recipe_cost_changed, yield_deviation, supplier_account_changed, unmapped_article (artículo para mapear), price_list_expired (lista vencida), order_news (novedad en una OC), receipt_report (informe de recepción), receipt_differences (recepción para revisar), invoice_observed (factura observada, para Compras) y price_variation (un precio de factura que varió más que el % del grupo, para Dirección).';

alter type purchasing.doc_kind add value if not exists 'invoice_original';
alter type purchasing.doc_kind add value if not exists 'credit_note';
comment on type purchasing.doc_kind is
  'Qué muestra un adjunto de compras: price_list (lista de precios), other, receipt_original (el papel como llegó), receipt_signed (el papel firmado), product_issue (foto de un renglón observado), invoice_original (la foto de la factura) y credit_note (la foto de una nota de crédito, débito o descuento).';
