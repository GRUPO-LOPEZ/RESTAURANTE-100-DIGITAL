-- Un precio es un número (revisiones de base y de seguridad del ADR-0067). En PostgreSQL «NaN > 0» es verdadero, así que
-- los controles de costing.price_records lo dejaban pasar por la API. No hay ninguno cargado.
alter table costing.price_records
  add constraint price_records_numbers_check check (
    package_price <> 'NaN' and discount_amount <> 'NaN' and net_package_price <> 'NaN' and gross_package_price <> 'NaN'
    and base_quantity <> 'NaN');
comment on constraint price_records_numbers_check on costing.price_records is
  'Los importes y el contenido son números: NaN pasaría los demás controles (para PostgreSQL es mayor que todo).';
