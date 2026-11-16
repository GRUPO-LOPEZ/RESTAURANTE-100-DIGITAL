-- Fase 3, Prompt 1 (ADR-0050), parte 1: el tipo de aviso de un cambio en las cuentas de pago de un proveedor. Va sola
-- porque un valor nuevo de un enum no se puede usar en la misma transacción que lo agrega.
alter type core.notification_kind add value 'supplier_account_changed';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación), recipe_cost_changed (cambió el costo de una receta, sin importes), yield_deviation (un ensayo de rendimiento se desvió del estándar más que el umbral) y supplier_account_changed (cambió una cuenta de pago de un proveedor: lo ve quien ve el pago, para controlarlo antes de pagar).';
