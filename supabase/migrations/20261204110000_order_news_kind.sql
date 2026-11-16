-- Fase 3, Prompt 3 (ADR-0053), parte 1: el aviso de una novedad en una orden de compra. Va sola porque un valor nuevo
-- de un enum no se puede usar en la misma transacción que lo agrega.
alter type core.notification_kind add value 'order_news';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación), recipe_cost_changed (cambió el costo de una receta, sin importes), yield_deviation (un ensayo de rendimiento se desvió del estándar más que el umbral), supplier_account_changed (cambió una cuenta de pago de un proveedor: lo ve quien ve el pago, para controlarlo antes de pagar), unmapped_article (llegó un artículo de proveedor que el sistema no reconoce: lo resuelve el chef), price_list_expired (venció la lista de precios de un proveedor según su frecuencia: lo ve Compras) y order_news (una orden de compra tiene una novedad, se aprobó, se rechazó o se canceló: lo ve quien la pidió).';
