// Edición de un producto de compra desde la ficha de la materia prima (ADR-0044). La base decide qué se puede cambiar
// (con precios, el envase y el contenido quedan fijos); acá solo se arma lo que cambió, para mandar a
// catalog.update_purchase_product solo eso (así la auditoría registra cambios reales).

// Lo que el formulario muestra y manda. Todo como texto, como llega de un formulario.
export type ProductFormValues = {
  description: string;
  brand_name: string;
  supplier_id: string;
  notes: string;
  is_active: string;
  package_unit?: string;
  units_per_package?: string;
  content_per_unit?: string;
  content_unit?: string;
};

// Lo que viaja a la base: solo las claves que cambiaron, con su tipo.
export type ProductChanges = Partial<{
  description: string;
  brand_name: string;
  supplier_id: string;
  notes: string;
  is_active: boolean;
  package_unit: string;
  units_per_package: number;
  content_per_unit: number;
  content_unit: string;
}>;

const TEXT_KEYS = ["description", "brand_name", "supplier_id", "notes"] as const;
const UNIT_KEYS = ["package_unit", "content_unit"] as const;

// «1,5» y «1.5» son lo mismo; «5» y «5.000» también.
export const toNumber = (value: string) => Number(value.trim().replace(",", "."));

// Compara lo enviado con lo que tenía el producto al abrir el panel. Un campo que no llega (deshabilitado porque el
// producto tiene precios) no cuenta como cambio.
export function productChanges(
  original: ProductFormValues,
  submitted: Partial<ProductFormValues>,
): ProductChanges {
  const changes: ProductChanges = {};
  for (const key of TEXT_KEYS) {
    const value = submitted[key];
    if (value !== undefined && value.trim() !== original[key].trim()) changes[key] = value.trim();
  }
  if (submitted.is_active !== undefined && submitted.is_active !== original.is_active) {
    changes.is_active = submitted.is_active === "true";
  }
  for (const key of UNIT_KEYS) {
    const value = submitted[key];
    if (value !== undefined && value !== "" && value !== original[key]) changes[key] = value;
  }
  const units = submitted.units_per_package;
  if (
    units !== undefined &&
    units.trim() !== "" &&
    toNumber(units) !== toNumber(original.units_per_package ?? "")
  ) {
    changes.units_per_package = toNumber(units);
  }
  const content = submitted.content_per_unit;
  if (
    content !== undefined &&
    content.trim() !== "" &&
    toNumber(content) !== toNumber(original.content_per_unit ?? "")
  ) {
    changes.content_per_unit = toNumber(content);
  }
  return changes;
}
