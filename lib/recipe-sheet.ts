// Cuentas de la ficha única de receta (ADR-0042). El costo de cada línea lo calcula la base (el mismo motor que el
// costo oficial, costing.preview_sheet_lines); acá solo se suman, se escalan y se reparten esos valores, sin
// suponer nada: si falta un dato, el resultado queda vacío (null) y la pantalla dice por qué.

import type { UnitDimension } from "@/lib/recipe-format";

// Lo que devuelve la base por cada fila de la grilla.
export type PreviewLine = {
  lineOrder: number;
  grams: number | null;
  weightStatus: string;
  lineCost: number | null;
  unitCost: number | null;
  costUnit: string | null;
  status: string | null;
};

// Motivos, en palabras, de una celda vacía.
export const MISSING_REASON: Record<string, string> = {
  missing_conversion:
    "Falta la densidad o el peso por unidad de la materia prima para pasarla a gramos.",
  not_weight: "La preparación rinde en volumen o en unidades: no se pasa a gramos.",
  invalid_quantity: "Revisá la cantidad.",
  unknown_ingredient: "La materia prima ya no existe.",
  missing_yield: "Falta la merma aprobada o el rendimiento de la preparación.",
  missing_price: "No hay precio vigente en este local.",
  missing_legal_entity: "Falta la razón social del local para saber si el precio va con o sin IVA.",
  missing_sub_recipe: "La preparación no tiene versión vigente.",
  incomplete_sub_recipe: "Al costo de la preparación le falta un dato.",
};
export const missingReason = (status: string | null | undefined): string =>
  MISSING_REASON[status ?? ""] ?? "Falta un dato para calcularlo.";

// El precio en la unidad grande de su medida: 100 cc de leche → el litro; 100 g de harina → el kilo.
export function bigUnitPrice(
  unitCost: number | null,
  costUnit: string | null,
): { value: number; unit: "kg" | "l" | "u" } | null {
  if (unitCost === null || !Number.isFinite(unitCost)) return null;
  if (costUnit === "g") return { value: unitCost * 1000, unit: "kg" };
  if (costUnit === "ml") return { value: unitCost * 1000, unit: "l" };
  if (costUnit === "unit") return { value: unitCost, unit: "u" };
  return null;
}

// Las medidas en las que se puede cargar una materia prima: la suya y, con densidad o peso por unidad, las otras.
export function compatibleDimensions(
  base: UnitDimension,
  hasDensity: boolean,
  hasUnitWeight: boolean,
): UnitDimension[] {
  const reachesMass =
    base === "mass" || (base === "volume" && hasDensity) || (base === "count" && hasUnitWeight);
  const out = new Set<UnitDimension>([base]);
  if (reachesMass) {
    out.add("mass");
    if (hasDensity) out.add("volume");
    if (hasUnitWeight) out.add("count");
  }
  return (["mass", "volume", "count"] as const).filter((d) => out.has(d));
}

// Cuántos gramos es una cantidad en una unidad de peso (los mismos factores que catalog.unit_conversions).
const GRAMS: Record<string, number> = {
  g: 1,
  kg: 1000,
  mg: 0.001,
  lb: 453.59237,
  oz: 28.349523,
  pinch: 0.5,
};
export function toGrams(quantity: number | null, unit: string | null): number | null {
  if (quantity === null || unit === null || !(unit in GRAMS)) return null;
  const factor = GRAMS[unit];
  return factor === undefined ? null : quantity * factor;
}

export type SheetTotals = {
  grams: number | null;
  cost: number | null;
  // Cuántas filas cargadas no tienen peso o costo: si hay alguna, el total queda vacío (nunca una suma parcial).
  missingGrams: number;
  missingCost: number;
  lines: number;
};

export function sheetTotals(rows: { grams: number | null; cost: number | null }[]): SheetTotals {
  const missingGrams = rows.filter((r) => r.grams === null).length;
  const missingCost = rows.filter((r) => r.cost === null).length;
  const sum = (k: "grams" | "cost") => rows.reduce((a, r) => a + (r[k] ?? 0), 0);
  return {
    grams: rows.length > 0 && missingGrams === 0 ? sum("grams") : null,
    cost: rows.length > 0 && missingCost === 0 ? sum("cost") : null,
    missingGrams,
    missingCost,
    lines: rows.length,
  };
}

// La incidencia de una fila sobre el total, en %. Sin total (o en cero), no hay incidencia.
export function incidence(part: number | null, total: number | null): number | null {
  if (part === null || total === null || total <= 0) return null;
  return (part / total) * 100;
}

// «Hacer N recetas»: un número entero de 1 a 999.
export function parseTimes(text: string): number | null {
  const t = text.trim();
  if (!/^[0-9]{1,3}$/.test(t)) return null;
  const n = Number(t);
  return n >= 1 ? n : null;
}
export function scale(value: number | null, times: number | null): number | null {
  return value === null || times === null ? null : value * times;
}

// Plato: cuántas porciones salen del peso total. Con decimales, para no esconder sobrante.
export function portionsFrom(
  totalGrams: number | null,
  portionGrams: number | null,
): number | null {
  if (totalGrams === null || portionGrams === null || portionGrams <= 0) return null;
  return Math.round((totalGrams / portionGrams) * 100) / 100;
}
export function perPortion(totalCost: number | null, portions: number | null): number | null {
  return totalCost === null || portions === null || portions <= 0 ? null : totalCost / portions;
}

// Preparación: rendimiento = peso neto ÷ peso bruto (como recipes.cooking_loss).
export function yieldRatio(netGrams: number | null, grossGrams: number | null): number | null {
  if (netGrams === null || grossGrams === null || grossGrams <= 0 || netGrams <= 0) return null;
  return netGrams / grossGrams;
}
export function costPerNetKg(totalCost: number | null, netGrams: number | null): number | null {
  return totalCost === null || netGrams === null || netGrams <= 0
    ? null
    : (totalCost / netGrams) * 1000;
}

// La grilla arranca con 10 filas y, cuando se completa la última, suma otra vacía.
export const START_ROWS = 10;
export function withTrailingRow<T>(rows: T[], isFilled: (row: T) => boolean, make: () => T): T[] {
  const out = [...rows];
  while (out.length < START_ROWS) out.push(make());
  const last = out.at(-1);
  if (last !== undefined && isFilled(last)) out.push(make());
  return out;
}

// «N cambios sin guardar»: cuántas filas, pasos o campos difieren de lo guardado.
export function countChanges<T>(saved: T[], current: T[], same: (a: T, b: T) => boolean): number {
  let n = Math.abs(saved.length - current.length);
  for (let i = 0; i < Math.min(saved.length, current.length); i++) {
    const a = saved[i];
    const b = current[i];
    if (a !== undefined && b !== undefined && !same(a, b)) n++;
  }
  return n;
}
export function changesLabel(n: number): string {
  return n === 0 ? "Sin cambios" : n === 1 ? "1 cambio sin guardar" : `${n} cambios sin guardar`;
}

const pct = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
export const formatPct = (v: number | null): string => (v === null ? "—" : `${pct.format(v)} %`);
const grams = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 1 });
export function formatGrams(v: number | null): string {
  if (v === null) return "—";
  return v >= 10000 ? `${grams.format(v / 1000)} kg` : `${grams.format(v)} g`;
}
