import { formatMoney } from "@/lib/money";
import type { BadgeStatus } from "@/components/ui/badge";
import type { Database } from "@/lib/database.types";

// Etiquetas y tipos de los costos de recetas (ADR-0032). Sin acceso a la base: lo usan también los
// componentes del navegador.

export type Reliability = Database["costing"]["Enums"]["cost_reliability"];
export type SnapshotReason = Database["costing"]["Enums"]["cost_snapshot_reason"];

export const COSTS_PAGE = 50;
export const SCENARIO_PAGE = 50;

export const RELIABILITY: Record<Reliability, { label: string; status: BadgeStatus }> = {
  verified: { label: "Completo y verificado", status: "ok" },
  estimated: { label: "Con estimaciones", status: "info" },
  stale: { label: "Desactualizado", status: "warn" },
  incomplete: { label: "Incompleto", status: "bad" },
};
// Un costo simulado no se verifica: estas etiquetas dicen qué datos tuvo la simulación, nunca que es confiable.
export const SCENARIO_RELIABILITY: Record<Reliability, { label: string; status: BadgeStatus }> = {
  verified: { label: "Simulado, sin datos faltantes", status: "review" },
  estimated: { label: "Simulado, con estimaciones", status: "review" },
  stale: { label: "Simulado, con precios viejos", status: "warn" },
  incomplete: { label: "Simulado, faltan datos", status: "bad" },
};
export const RELIABILITY_KEYS = Object.keys(RELIABILITY) as Reliability[];

export const REASON_LABELS: Record<SnapshotReason, string> = {
  publish: "Versión nueva",
  price_change: "Precio nuevo",
  yield_change: "Rendimiento nuevo",
  assignment: "Cambió dónde se usa",
  legal_entity_change: "Cambió la razón social",
  restaurant_reopened: "Se reabrió el local",
  daily: "Actualización diaria",
  month_end: "Cierre de mes",
};

// Qué le falta a una línea, en palabras de la cocina.
const LINE_STATUS_LABELS: Record<string, string> = {
  missing_conversion: "Falta la conversión de unidad",
  invalid_quantity: "La cantidad no es válida",
  unknown_ingredient: "La materia prima ya no existe",
  missing_yield: "Falta el rendimiento",
  missing_price: "Falta el precio",
  missing_legal_entity: "Falta la razón social del local",
  missing_sub_recipe: "La preparación no tiene versión vigente",
  incomplete_sub_recipe: "La preparación está incompleta",
};
export function lineStatusLabel(status: string): string | null {
  if (status === "ok") return null;
  return LINE_STATUS_LABELS[status] ?? "Falta un dato";
}

export function formatPercent(value: number | null): string {
  if (value === null) return "—";
  return `${value.toLocaleString("es-AR", { maximumFractionDigits: 2 })} %`;
}

export function formatDifference(value: number | null): string {
  if (value === null) return "—";
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toLocaleString("es-AR", { maximumFractionDigits: 2 })} %`;
}

// Una diferencia en plata, con su signo.
export function formatMoneyDifference(value: number | null): string {
  if (value === null) return "—";
  const sign = value > 0 ? "+" : value < 0 ? "-" : "";
  return `${sign}${formatMoney(Math.abs(value))}`;
}

export type ScenarioRow = {
  recipeId: string;
  recipe: string;
  today: number | null;
  simulated: number | null;
  difference: number | null;
  differencePct: number | null;
  portionToday: number | null;
  portionSimulated: number | null;
  reliability: Reliability;
};

export type CostRow = {
  recipeId: string;
  code: string;
  name: string;
  type: string;
  versionId: string;
  portions: number | null;
  baseUnit: string | null;
  total: number | null;
  gross: number | null;
  perBaseUnit: number | null;
  perPortion: number | null;
  reliability: Reliability;
  updatedAt: string;
};
