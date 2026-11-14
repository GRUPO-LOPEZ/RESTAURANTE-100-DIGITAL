// Cuentas de la ficha única de receta (ADR-0042). El costo de cada línea lo calcula la base (el mismo motor que el
// costo oficial, costing.preview_sheet_lines); acá solo se suman, se escalan y se reparten esos valores, sin
// suponer nada: si falta un dato, el resultado queda vacío (null) y la pantalla dice por qué.

import { missingState, type MetricInput } from "@/lib/metrics";
import { formatMoney } from "@/lib/money";
import { formatMinutes, formatQuantity, type UnitDimension } from "@/lib/recipe-format";

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

// ---------------------------------------------------------------------------
// Ficha sin scroll (ADR-0047): los 4 indicadores de arriba, la marca de quien revisa y el estado del total
// ---------------------------------------------------------------------------

export type SheetKpi = MetricInput & {
  key: string;
  label: string;
  unit?: string;
  period?: string;
  comparison?: string;
};

export type SheetKpiInput = {
  dish: boolean;
  // Ve costos (menú de costos) y el local elegido arriba (sin local, no hay costo).
  money: boolean;
  place: string | null;
  // Filas completas de la planilla, y lo que la base pudo pasar a gramos y costear.
  lines: number;
  grams: number | null;
  missingGrams: number;
  cost: number | null;
  missingCost: number;
  // Plato: el peso de la porción escrito (texto), el número leído y las porciones (calculadas o cargadas a mano).
  portionText: string;
  portionGrams: number | null;
  portions: number | null;
  manualPortions: number | null;
  // Preparación: el peso neto escrito (texto), en gramos si se puede, y neto ÷ bruto.
  netText: string;
  netGrams: number | null;
  ratio: number | null;
  totalMinutes: number;
};

const plural = (n: number, one: string, many: string) => (n === 1 ? one : many);

// Los 4 indicadores de la ficha. Plato: costo total, costo por porción, peso total y porciones. Preparación: costo
// total, costo por kg neto, peso bruto → neto y rendimiento. Quien no ve costos nunca ve dinero: en lugar de los dos
// de plata, el tiempo total y los ingredientes con peso (con la regla única de lo que falta). Sin dato: null y el
// motivo (la tarjeta muestra «—», nunca un número supuesto).
export function sheetKpis(i: SheetKpiInput): SheetKpi[] {
  const noLines = "Todavía no tiene ingredientes.";
  const noPlace = "Elegí un local arriba para ver el costo.";
  const costMissing = !i.place
    ? noPlace
    : i.lines === 0
      ? noLines
      : `Incompleto: falta el costo de ${i.missingCost} ${plural(i.missingCost, "fila", "filas")}.`;
  const gramsMissing =
    i.lines === 0
      ? noLines
      : `Incompleto: ${i.missingGrams} ${plural(i.missingGrams, "fila no se pasa", "filas no se pasan")} a gramos.`;
  const cost = i.money && i.place ? i.cost : null;
  const shownPortions = i.portions ?? i.manualPortions;

  const total: SheetKpi = {
    key: "costo",
    label: "Costo total",
    value: cost === null ? null : formatMoney(cost),
    missingReason: costMissing,
    period: i.place ?? undefined,
    comparison: "sin IVA",
    status: "ok",
    statusLabel: "Completo",
    emptyLabel: "Sin datos",
  };
  const weighed = missingState(i.missingGrams, i.lines);
  const noMoney: SheetKpi[] = [
    {
      key: "tiempo",
      label: "Tiempo total",
      value: i.totalMinutes > 0 ? formatMinutes(i.totalMinutes) : null,
      missingReason: "Todavía no tiene pasos con minutos.",
      comparison: "sale de los pasos",
      status: "info",
      statusLabel: "Calculado",
      emptyLabel: "Sin datos",
    },
    {
      key: "con-peso",
      label: "Ingredientes con peso",
      value: i.lines - i.missingGrams,
      total: i.lines,
      comparison: `de ${i.lines}`,
      emptyLabel: noLines,
      status: weighed.status,
      statusLabel: weighed.label,
    },
  ];

  if (i.dish) {
    const portionsKpi: SheetKpi = {
      key: "porciones",
      label: "Porciones",
      value: shownPortions === null ? null : formatQuantity(shownPortions),
      missingReason: !i.portionText
        ? "Sin peso de porción."
        : i.portionGrams === null || i.portionGrams <= 0
          ? "Revisá el peso de la porción."
          : i.lines === 0
            ? noLines
            : "Falta pasar algún ingrediente a gramos.",
      comparison:
        i.portions !== null
          ? `de ${formatQuantity(i.portionGrams)} g`
          : i.manualPortions !== null
            ? "cargadas a mano"
            : undefined,
      status: "info",
      statusLabel: i.portions !== null ? "Calculado" : "Cargadas a mano",
      emptyLabel: "Sin datos",
    };
    const weight: SheetKpi = {
      key: "peso",
      label: "Peso total",
      value: i.grams === null ? null : formatGrams(i.grams),
      missingReason: gramsMissing,
      comparison: "suma de los ingredientes",
      status: "ok",
      statusLabel: "Completo",
      emptyLabel: "Sin datos",
    };
    if (!i.money) return [weight, portionsKpi, ...noMoney];
    const per = perPortion(cost, shownPortions);
    return [
      total,
      {
        key: "porcion",
        label: "Costo por porción",
        value: per === null ? null : formatMoney(per),
        missingReason:
          cost === null ? costMissing : "Faltan las porciones: cargá el peso de la porción.",
        period: i.place ?? undefined,
        status: "ok",
        statusLabel: "Completo",
        emptyLabel: "Sin datos",
      },
      weight,
      portionsKpi,
    ];
  }

  const ratioKpi: SheetKpi = {
    key: "rendimiento",
    label: "Rendimiento",
    value: i.ratio === null ? null : formatPct(i.ratio * 100),
    missingReason: !i.netText
      ? "Sin peso neto."
      : i.netGrams === null
        ? "Rinde en volumen o en unidades: se calcula solo en peso."
        : gramsMissing,
    comparison: "neto ÷ bruto",
    status: "info",
    statusLabel: "Objetivo de los lotes",
    emptyLabel: "Sin datos",
  };
  const grossNet: SheetKpi = {
    key: "bruto-neto",
    label: "Peso bruto → neto",
    value:
      i.grams === null || i.netGrams === null
        ? null
        : `${formatGrams(i.grams)} → ${formatGrams(i.netGrams)}`,
    missingReason:
      i.grams === null
        ? gramsMissing
        : !i.netText
          ? "Sin peso neto."
          : "Rinde en volumen o en unidades: se calcula solo en peso.",
    comparison: "lo que queda al terminar",
    status: "info",
    statusLabel: "Calculado",
    emptyLabel: "Sin datos",
  };
  if (!i.money) return [grossNet, ratioKpi, ...noMoney];
  const perKg = costPerNetKg(cost, i.netGrams);
  return [
    total,
    {
      key: "kg-neto",
      label: "Costo por kg neto",
      value: perKg === null ? null : formatMoney(perKg),
      missingReason: cost === null ? costMissing : "Falta el peso neto en peso.",
      period: i.place ?? undefined,
      status: "ok",
      statusLabel: "Completo",
      emptyLabel: "Sin datos",
    },
    grossNet,
    ratioKpi,
  ];
}

// La marca de una fila para quien revisa: «antes 380 g» si cambió la cantidad, «Nueva» si se agregó.
export function reviewMark(d: {
  change: string;
  unit: string;
  oldQuantity: number | null;
}): string | null {
  if (d.change === "added") return "Nueva";
  if (d.change === "changed")
    return d.oldQuantity === null ? "Cambió" : `antes ${formatQuantity(d.oldQuantity)} ${d.unit}`;
  return null;
}

// El estado del total de la planilla: «Completo» o «Incompleto: falta 1 dato».
export function totalState(
  lines: number,
  missing: number,
): { status: "ok" | "warn" | "none"; label: string } {
  if (lines === 0) return { status: "none", label: "Sin ingredientes" };
  if (missing === 0) return { status: "ok", label: "Completo" };
  return {
    status: "warn",
    label: `Incompleto: ${missing === 1 ? "falta 1 dato" : `faltan ${missing} datos`}`,
  };
}
