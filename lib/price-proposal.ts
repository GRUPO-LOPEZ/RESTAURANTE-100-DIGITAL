import { formatMoney, parseMoney } from "@/lib/money";
import { bigUnitPrice } from "@/lib/recipe-sheet";

// «Proponer precio» (pedido de Soy, ADR-0067): textos y valores por defecto, sin React ni Supabase. Los números los
// calcula la base (costing.preview_price, la misma cuenta de la propuesta); acá solo se leen.

// Con 2,5 % y 5 % (P5, ADR-0058).
export const VAT_RATES = ["21", "10.5", "27", "5", "2.5", "0"] as const;
const DEFAULT_VAT = "21";

/** Hasta 5 opciones, botones a la vista; más, un desplegable (edición directa, ADR-0039). */
export const CHOICE_MAX = 5;

export type PricePreview = {
  netUnitCost: number;
  grossUnitCost: number;
  baseUnit: string;
  variation: number | null;
  variationToday: number | null;
  variationLookback: number | null;
  lookbackDays: number;
  // No hay con qué comparar: es el primer precio en ese lugar.
  first: boolean;
  // Además del Controller, lo aprueba Dirección General.
  direction: boolean;
};

const pct = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 2 });
const UNIT_WORDS = { kg: "kg", l: "litro", u: "unidad" } as const;

/** «Queda $ 1.176,00 por kg sin IVA: sube 4 % contra el precio de hoy.» */
export function previewText(p: PricePreview, invoice: boolean): string {
  const big = bigUnitPrice(p.netUnitCost, p.baseUnit);
  const cost = big
    ? `${formatMoney(big.value)} por ${UNIT_WORDS[big.unit]}`
    : `${formatMoney(p.netUnitCost)} por ${p.baseUnit}`;
  const head = `Queda ${cost}${invoice ? " sin IVA" : ""}`;
  if (p.variation === null) return `${head}. Es el primer precio en ese lugar.`;
  // La que vale es la más grande de las dos (subas en escalones, ADR-0030).
  const against =
    p.variationLookback !== null &&
    p.variation === p.variationLookback &&
    p.variation !== p.variationToday
      ? `el de hace ${p.lookbackDays} días`
      : "el precio de hoy";
  if (p.variation === 0) return `${head}: igual que ${against}.`;
  const word = p.variation > 0 ? "sube" : "baja";
  return `${head}: ${word} ${pct.format(Math.abs(p.variation))} % contra ${against}.`;
}

export function approversText(p: Pick<PricePreview, "direction">): string {
  return p.direction
    ? "Lo aprueban el Controller y Dirección General."
    : "Lo aprueba el Controller.";
}

export type ProposalProduct = {
  id: string;
  label: string;
  // En qué viene («bolsa»), para el nombre del precio.
  packageUnit: string;
  vatRate: string;
  supplierId: string;
};

/**
 * Lo que se completa solo al elegir un producto: la alícuota de su último precio aprobado (si no hay, 21 %) y su proveedor
 * habitual, si sigue activo. rows: del más nuevo al más viejo.
 */
export function productDefaults(
  productId: string,
  supplierId: string | null,
  rows: { productId: string; vatRate: number | null }[],
  activeSuppliers: ReadonlySet<string>,
): { vatRate: string; supplierId: string } {
  const last = rows.find((r) => r.productId === productId && r.vatRate !== null);
  const rate = last ? String(last.vatRate) : DEFAULT_VAT;
  return {
    vatRate: VAT_RATES.find((v) => v === rate) ?? DEFAULT_VAT,
    supplierId: supplierId && activeSuppliers.has(supplierId) ? supplierId : "",
  };
}

/** Lo que va a viajar de «Más datos», en una línea: nada queda escondido. */
export function proposalSummary(v: {
  invoice: boolean;
  vatRate: string;
  supplier: string | null;
  discount: string;
  testValue: boolean;
  notes: string;
}): string {
  const discount = parseMoney(v.discount);
  return [
    v.invoice ? `Factura · IVA ${v.vatRate.replace(".", ",")} %` : "Sin factura",
    v.supplier ?? "sin proveedor",
    discount ? `descuento ${formatMoney(discount)}` : null,
    v.testValue ? "valor de prueba" : null,
    v.notes.trim() ? "con observaciones" : null,
  ]
    .filter((x): x is string => x !== null)
    .join(" · ");
}
