-- Listas de precios (ADR-0071): el estado «anulada». Va solo en esta migración: un valor nuevo de un enum no se puede
-- usar en la misma transacción en que se agrega (lo usa la siguiente, 20261220120100_price_list_versions).
alter type purchasing.price_list_status add value if not exists 'voided';
comment on type purchasing.price_list_status is
  'Estado de una lista de precios: received (recibida, sin aceptar), accepted (la vigente del proveedor), replaced (reemplazada por otra o por su versión corregida) y voided (anulada con motivo: cargada por error; no se borra).';
