-- Fase 2, agregados chicos: aviso de rendimiento (ADR-0035), parte 1. Va sola porque un valor nuevo de un enum no se puede
-- usar en la misma transacción que lo agrega.
alter type core.notification_kind add value 'yield_deviation';
comment on type core.notification_kind is
  'Tipo de aviso: approval_requested (pedido de aprobación), recipe_changed (cambió una preparación), recipe_cost_changed (cambió el costo de una receta, sin importes) y yield_deviation (un ensayo de rendimiento se desvió del estándar más que el umbral).';
