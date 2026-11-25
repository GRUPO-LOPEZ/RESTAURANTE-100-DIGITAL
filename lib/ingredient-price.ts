import { formatMoney } from "@/lib/money";
import { bigUnitPrice } from "@/lib/recipe-sheet";

// El precio vigente de una materia prima en un renglón de la lista (ADR-0066). Sin React ni Supabase. El cálculo es el
// del motor (costing.resolve_prices); acá solo se elige cómo se lee.
export type ListPrice = {
  unitCost: number | null;
  baseUnit: string | null;
  stale: boolean;
  status: string;
};

export type PriceState = { status: "ok" | "warn" | "none"; label: string };

/** «$ 1.250,00 / kg», o null si no hay un precio que valga. */
export function listPriceText(p: ListPrice | undefined): string | null {
  if (!p || p.unitCost === null) return null;
  const big = bigUnitPrice(p.unitCost, p.baseUnit);
  return big ? `${formatMoney(big.value)} / ${big.unit}` : null;
}

/** La palabra del estado: nunca «Al día» sin un precio que valga. */
export function listPriceState(p: ListPrice | undefined): PriceState {
  if (!p || p.status === "missing_price") return { status: "none", label: "Sin precio" };
  if (p.status === "missing_legal_entity")
    return { status: "none", label: "Falta la razón social" };
  if (p.status !== "ok" || listPriceText(p) === null) return { status: "none", label: "Sin datos" };
  return p.stale ? { status: "warn", label: "Desactualizado" } : { status: "ok", label: "Al día" };
}
