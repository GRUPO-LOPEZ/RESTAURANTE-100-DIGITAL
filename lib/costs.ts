import {
  COSTS_PAGE,
  lineStatusLabel,
  type CostRow,
  type Reliability,
  type SnapshotReason,
} from "@/lib/cost-labels";
import { getActiveRestaurantId, getMyScopes } from "@/lib/data";
import type { Database } from "@/lib/database.types";
import { createClient } from "@/lib/supabase/server";

// Lecturas de costos de recetas (ADR-0032). Todo con la sesión de la persona: la base pide
// recipes.view_costs en el local. Ninguna de estas lecturas trae precios, productos ni proveedores.

export {
  COSTS_PAGE,
  REASON_LABELS,
  RELIABILITY,
  RELIABILITY_KEYS,
  formatDifference,
  formatPercent,
  lineStatusLabel,
  type CostRow,
  type Reliability,
  type SnapshotReason,
} from "@/lib/cost-labels";

// ---------------------------------------------------------------------------
// De qué local se habla
// ---------------------------------------------------------------------------
export type CostPlace = { id: string; name: string };

export async function getCostPlaces(): Promise<CostPlace[]> {
  const supabase = await createClient();
  const [{ data, error }, scopes] = await Promise.all([
    supabase.schema("core").rpc("permitted_restaurant_ids", { p_permission: "recipes.view_costs" }),
    getMyScopes(),
  ]);
  if (error || !Array.isArray(data)) throw new Error("No pudimos cargar tus locales.");
  const ids = new Set(data.filter((x): x is string => typeof x === "string"));
  const names = new Map(scopes.map((s) => [s.restaurant_id, s.restaurant_name]));
  return [...ids]
    .map((id) => ({ id, name: names.get(id) ?? "" }))
    .filter((p) => p.name)
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
}

// El pedido en la dirección, el local elegido arriba o el único que tiene. Si no, ninguno.
export function pickCostPlace(
  places: CostPlace[],
  requested: string | undefined,
  activeId: string | null,
): CostPlace | null {
  return (
    places.find((p) => p.id === requested) ??
    places.find((p) => p.id === activeId) ??
    (places.length === 1 ? (places[0] ?? null) : null)
  );
}

export async function resolveCostPlace(
  userId: string | undefined,
  requested?: string,
): Promise<{ places: CostPlace[]; place: CostPlace | null }> {
  const [places, activeId] = await Promise.all([getCostPlaces(), getActiveRestaurantId(userId)]);
  return { places, place: pickCostPlace(places, requested, activeId) };
}

// ---------------------------------------------------------------------------
// La lista de un local
// ---------------------------------------------------------------------------
const num = (v: number | null) => (v === null ? null : Number(v));

type RawCostRow = Database["costing"]["Functions"]["restaurant_costs"]["Returns"][number];
function toRow(r: RawCostRow): CostRow {
  return {
    recipeId: r.recipe_id,
    code: r.code,
    name: r.name,
    type: r.recipe_type,
    versionId: r.recipe_version_id,
    portions: r.portions,
    baseUnit: r.base_unit,
    total: num(r.total_cost),
    gross: num(r.total_gross_cost),
    perBaseUnit: num(r.cost_per_base_unit),
    perPortion: num(r.cost_per_portion),
    reliability: r.reliability,
    updatedAt: r.updated_at,
  };
}

export async function getRestaurantCosts(filter: {
  restaurantId: string;
  search?: string;
  reliability?: Reliability;
  page: number;
}): Promise<{ rows: CostRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("restaurant_costs", {
    p_restaurant_id: filter.restaurantId,
    p_search: filter.search,
    p_reliability: filter.reliability,
    p_limit: COSTS_PAGE,
    p_offset: filter.page * COSTS_PAGE,
  });
  if (error) throw new Error("No pudimos cargar los costos.");
  return { rows: data.map(toRow), total: Number(data[0]?.total_rows ?? 0) };
}

export type CostSummary = {
  total: number;
  complete: number;
  stale: number;
  incomplete: number;
  updatedAt: string | null;
};

export async function getCostSummary(restaurantId: string): Promise<CostSummary> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("restaurant_cost_summary", { p_restaurant_id: restaurantId });
  const row = data?.[0];
  if (error || !row) throw new Error("No pudimos cargar los costos.");
  return {
    total: Number(row.total),
    complete: Number(row.complete),
    stale: Number(row.stale),
    incomplete: Number(row.incomplete),
    updatedAt: row.updated_at,
  };
}

export type RecalcStatus = { pending: number; failed: number };

export async function getRecalcStatus(): Promise<RecalcStatus> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("recalc_status");
  if (error) throw new Error("No pudimos saber si los costos están al día.");
  return { pending: Number(data[0]?.pending ?? 0), failed: Number(data[0]?.failed ?? 0) };
}

// ---------------------------------------------------------------------------
// Una receta en un local
// ---------------------------------------------------------------------------
export async function getCostRow(restaurantId: string, recipeId: string): Promise<CostRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("restaurant_costs", { p_restaurant_id: restaurantId, p_recipe_id: recipeId });
  if (error) throw new Error("No pudimos cargar el costo.");
  return data[0] ? toRow(data[0]) : null;
}

export type CostLine = {
  order: number;
  item: string;
  quantity: number;
  unit: string;
  cost: number | null;
  gross: number | null;
  share: number | null;
  missing: string | null;
};

// De la que más pesa a la que menos; lo que falta, primero: es lo que hay que resolver.
export function sortCostLines(lines: CostLine[]): CostLine[] {
  return [...lines].sort(
    (a, b) =>
      Number(b.missing !== null) - Number(a.missing !== null) ||
      (b.cost ?? 0) - (a.cost ?? 0) ||
      a.order - b.order,
  );
}

export async function getCostLines(versionId: string, restaurantId: string): Promise<CostLine[]> {
  const supabase = await createClient();
  const [lines, units] = await Promise.all([
    supabase
      .schema("costing")
      .rpc("recipe_cost_lines", { p_version_id: versionId, p_restaurant_id: restaurantId }),
    supabase.schema("catalog").from("units").select("id, code"),
  ]);
  if (lines.error || units.error) throw new Error("No pudimos cargar el detalle del costo.");
  const unit = new Map(units.data.map((u) => [u.id, u.code]));
  return sortCostLines(
    lines.data.map((l) => ({
      order: l.line_order,
      item: l.item,
      quantity: Number(l.quantity),
      unit: unit.get(l.unit_id) ?? "",
      cost: num(l.line_cost),
      gross: num(l.line_gross_cost),
      share: num(l.share_pct),
      missing: lineStatusLabel(l.status),
    })),
  );
}

// El costo de una versión con los precios de hoy, también de un borrador. Vacío si la sesión no lo puede ver.
export type LiveCost = {
  total: number | null;
  gross: number | null;
  perPortion: number | null;
  perBaseUnit: number | null;
  reliability: Reliability;
};

export async function getLiveCost(
  versionId: string,
  restaurantId: string,
): Promise<LiveCost | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("recipe_cost", { p_version_id: versionId, p_restaurant_id: restaurantId });
  // Sin permiso (por ejemplo, la receta no es de ese local) no hay costo que mostrar. Otro error es un error.
  if (error?.code === "42501") return null;
  const row = data?.[0];
  if (error || !row) throw new Error("No pudimos calcular el costo.");
  return {
    total: num(row.total_cost),
    gross: num(row.total_gross_cost),
    perPortion: num(row.cost_per_portion),
    perBaseUnit: num(row.cost_per_base_unit),
    reliability: row.reliability,
  };
}

export type CostSnapshot = {
  id: string;
  at: string;
  reason: SnapshotReason;
  total: number | null;
  reliability: Reliability;
};

export async function getCostHistory(
  restaurantId: string,
  recipeId: string,
): Promise<CostSnapshot[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .from("recipe_cost_snapshots")
    .select("id, created_at, reason, total_cost, reliability")
    .eq("restaurant_id", restaurantId)
    .eq("recipe_id", recipeId)
    .order("entry_number", { ascending: false })
    .limit(10);
  if (error) throw new Error("No pudimos cargar la historia del costo.");
  return data.map((s) => ({
    id: s.id,
    at: s.created_at,
    reason: s.reason,
    total: num(s.total_cost),
    reliability: s.reliability,
  }));
}

// Los costos de varias recetas en un local, para la lista de recetas.
export async function getCostsByRecipe(
  restaurantId: string,
  recipeIds: string[],
): Promise<Map<string, { total: number | null; reliability: Reliability }>> {
  if (recipeIds.length === 0) return new Map();
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .from("recipe_cost_current")
    .select("recipe_id, total_cost, reliability")
    .eq("restaurant_id", restaurantId)
    .in("recipe_id", recipeIds);
  if (error) throw new Error("No pudimos cargar los costos.");
  return new Map(
    data.map((c) => [c.recipe_id, { total: num(c.total_cost), reliability: c.reliability }]),
  );
}

// ---------------------------------------------------------------------------
// El impacto de un precio
// ---------------------------------------------------------------------------
export const IMPACT_PAGE = 200;

export type ImpactRow = {
  recipeId: string;
  recipe: string;
  restaurantId: string;
  restaurant: string;
  before: number | null;
  after: number | null;
  difference: number | null;
  differencePct: number | null;
  versionChanged: boolean;
};

export async function getPriceImpact(priceRecordId: string): Promise<{
  ingredient: string | null;
  validFrom: string | null;
  calculatedAt: string | null;
  total: number;
  rows: ImpactRow[];
}> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("price_impact", { p_price_record_id: priceRecordId, p_limit: IMPACT_PAGE });
  if (error) throw new Error("No pudimos cargar el impacto del precio.");
  return {
    ingredient: data[0]?.ingredient ?? null,
    validFrom: data[0]?.valid_from ?? null,
    calculatedAt: data[0]?.calculated_at ?? null,
    total: Number(data[0]?.total_rows ?? 0),
    rows: data.map((r) => ({
      recipeId: r.recipe_id,
      recipe: r.recipe,
      restaurantId: r.restaurant_id,
      restaurant: r.restaurant,
      before: num(r.cost_before),
      after: num(r.cost_after),
      difference: num(r.difference),
      differencePct: num(r.difference_pct),
      versionChanged: r.version_changed,
    })),
  };
}
