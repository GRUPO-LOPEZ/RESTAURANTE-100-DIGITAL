import { getPriceOrigins, type PriceOrigin } from "@/lib/invoices-data";
import {
  COSTS_PAGE,
  lineStatusLabel,
  type CostRow,
  type Reliability,
  type SnapshotReason,
} from "@/lib/cost-labels";
import { getActiveRestaurantId, getMyScopes } from "@/lib/data";
import { missingState } from "@/lib/metrics";
import { perBaseLabel } from "@/lib/money";
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

// Los locales donde la sesión tiene el permiso: los costos de recetas (recipes.view_costs) o, para la ficha de
// materia prima, los precios (prices.view: Compras ve precios sin ver costos; pedido de Soy, 2026-11-16).
async function costPlacesAndNames(permission = "recipes.view_costs"): Promise<{
  places: CostPlace[];
  names: Map<string, string>;
}> {
  const supabase = await createClient();
  const [{ data, error }, scopes] = await Promise.all([
    supabase.schema("core").rpc("permitted_restaurant_ids", { p_permission: permission }),
    getMyScopes(),
  ]);
  if (error || !Array.isArray(data)) throw new Error("No pudimos cargar tus locales.");
  const ids = new Set(data.filter((x): x is string => typeof x === "string"));
  const names = new Map(scopes.map((s) => [s.restaurant_id, s.restaurant_name]));
  const places = [...ids]
    .map((id) => ({ id, name: names.get(id) ?? "" }))
    .filter((p) => p.name)
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
  return { places, names };
}

export async function getCostPlaces(): Promise<CostPlace[]> {
  return (await costPlacesAndNames()).places;
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

export type ResolvedPlace = {
  places: CostPlace[];
  place: CostPlace | null;
  // El local aplicado arriba cuando no es uno de los que dejan ver costos (o precios), para decirlo en vez de pedir uno.
  blockedActive: string | null;
};

export async function resolveCostPlace(
  userId: string | undefined,
  requested?: string,
): Promise<ResolvedPlace> {
  return resolvePlace("recipes.view_costs", userId, requested);
}

// El local de los precios (prices.view), aparte del de los costos: Compras ve el precio del local elegido sin ver
// costos de recetas, y la Chef ve costos sin ver precios.
export async function resolvePricePlace(
  userId: string | undefined,
  requested?: string,
): Promise<ResolvedPlace> {
  return resolvePlace("prices.view", userId, requested);
}

async function resolvePlace(
  permission: string,
  userId: string | undefined,
  requested?: string,
): Promise<ResolvedPlace> {
  const [{ places, names }, activeId] = await Promise.all([
    costPlacesAndNames(permission),
    getActiveRestaurantId(userId),
  ]);
  const place = pickCostPlace(places, requested, activeId);
  const blockedActive =
    !place && activeId && !places.some((p) => p.id === activeId)
      ? (names.get(activeId) ?? null)
      : null;
  return { places, place, blockedActive };
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

// Las claves de orden que entiende la base (costing.restaurant_costs): la pantalla las usa como columnas.
export const COST_SORT_KEYS = [
  "name",
  "code",
  "total",
  "portion",
  "reliability",
  "updated",
] as const;

export async function getRestaurantCosts(filter: {
  restaurantId: string;
  search?: string;
  reliability?: Reliability;
  // Página desde 0 y filas por página (si no se dice, las de siempre).
  page: number;
  size?: number;
  // Una de COST_SORT_KEYS, con "-" para invertir. La base valida la lista.
  order?: string;
}): Promise<{ rows: CostRow[]; total: number }> {
  const supabase = await createClient();
  const size = filter.size ?? COSTS_PAGE;
  const { data, error } = await supabase.schema("costing").rpc("restaurant_costs", {
    p_restaurant_id: filter.restaurantId,
    p_search: filter.search,
    p_reliability: filter.reliability,
    p_limit: size,
    p_offset: filter.page * size,
    p_order: filter.order,
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
  // Si la línea es una preparación (otra receta) y no una materia prima.
  preparation?: boolean;
};

// De la que más pesa a la que menos; las que no tienen dato, al final (pedido de Soy, ADR-0048). Lo que falta se avisa
// arriba, en una franja (missingSummary).
export function sortCostLines(lines: CostLine[]): CostLine[] {
  return [...lines].sort(
    (a, b) =>
      Number(a.missing !== null) - Number(b.missing !== null) ||
      (b.cost ?? 0) - (a.cost ?? 0) ||
      a.order - b.order,
  );
}

// La franja del detalle: qué línea no tiene dato y por qué. null si no falta nada.
export function missingSummary(lines: CostLine[], shown = 2): string | null {
  const missing = lines.filter((l) => l.missing !== null);
  if (missing.length === 0) return null;
  const why = (l: CostLine) => `${l.item}, ${(l.missing ?? "").toLocaleLowerCase("es-AR")}`;
  if (missing.length === 1) return `Falta un dato: ${why(missing[0] as CostLine)}.`;
  const listed = missing.slice(0, shown).map(why).join("; ");
  const rest = missing.length - Math.min(shown, missing.length);
  return `Faltan ${missing.length} datos: ${listed}${rest > 0 ? ` y ${rest} más` : ""}.`;
}

// «Para bajar el costo» (ADR-0048): la línea que más pesa y su parte del total. Es una cuenta con los datos de la
// pantalla, no un agente. Con un dato faltante no hay total contra el que medir: primero se completa.
export function costTip(lines: CostLine[], total: number | null): string | null {
  const missing = lines.filter((l) => l.missing !== null).length;
  if (missing > 0 || total === null) {
    return missing > 1
      ? `Primero hay que completar los ${missing} datos que faltan.`
      : "Primero hay que completar el dato que falta.";
  }
  if (total <= 0) return null;
  const top = sortCostLines(lines).find((l) => l.cost !== null && l.cost > 0);
  if (!top || top.cost === null) return null;
  // Con el mismo redondeo que la tabla (un decimal), así dicen lo mismo.
  const share = (top.share ?? (top.cost * 100) / total).toLocaleString("es-AR", {
    maximumFractionDigits: 1,
  });
  const name = top.preparation ? `${top.item} (una preparación)` : top.item;
  return `${name} es el ${share} % del costo. Un cambio de precio o de cantidad ahí es lo que más mueve el total.`;
}

// Los tres indicadores con número de la lista (ADR-0048), con la regla única de lo que falta (lib/metrics.ts). Sin
// recetas con costo, Metric dice «Sin datos» (nunca «Todas al día»).
export type CostListMetric = {
  key: "up_to_date" | "stale" | "incomplete";
  label: string;
  value: number;
  total: number;
  status: "ok" | "warn" | "bad" | "none";
  statusLabel: string;
  // El filtro de «Ver cuáles», si hay algo para ver.
  filter?: Reliability;
};

export function costListMetrics(summary: {
  total: number;
  complete: number;
  stale: number;
  incomplete: number;
}): CostListMetric[] {
  const { total, complete, stale, incomplete } = summary;
  const behind = missingState(total - complete, total);
  const old = missingState(stale, total);
  const empty = missingState(incomplete, total);
  return [
    {
      key: "up_to_date",
      label: "Recetas al día",
      value: complete,
      total,
      status: behind.status,
      statusLabel: behind.status === "ok" ? "Todas al día" : behind.label,
    },
    {
      key: "stale",
      label: "Desactualizadas",
      value: stale,
      total,
      status: old.status,
      statusLabel: stale > 0 ? `Vencidas: ${stale}` : "Ninguna",
      ...(stale > 0 ? { filter: "stale" as const } : {}),
    },
    {
      key: "incomplete",
      label: "Incompletas",
      value: incomplete,
      total,
      status: empty.status,
      statusLabel: incomplete > 0 ? `Sin total: ${incomplete}` : "Ninguna",
      ...(incomplete > 0 ? { filter: "incomplete" as const } : {}),
    },
  ];
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
      preparation: l.sub_recipe_id !== null,
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

// El costo de una materia prima en un local, por kg (o litro, o unidad) como se compra y limpio, calculado por el mismo
// motor que las recetas (costing.ingredient_line_cost; ADR-0040). El neto usa el estándar de LIMPIEZA y, si se compra
// congelada, el de descongelado. Un costo que no se puede calcular va vacío con su estado (nunca $ 0).
export type IngredientNetCost = {
  gross: number | null;
  net: number | null;
  netStatus: string;
  per: string;
  // Del precio que vale (costing.resolve_price): vencido, heredado de la marca o del grupo, y desde cuándo.
  stale: boolean;
  inherited: boolean;
  validFrom: string | null;
};

export async function getIngredientNetCost(
  ingredientId: string,
  restaurantId: string,
  baseUnit: string,
  cleaningProcessId: string | null,
): Promise<IngredientNetCost | null> {
  const client = await createClient();
  const perBase = perBaseLabel(baseUnit);
  const { data: units } = await client
    .schema("catalog")
    .from("units")
    .select("id")
    .eq("code", baseUnit)
    .maybeSingle();
  if (!units) return null;
  // Pide recipes.view_costs, no prices.view: la Chef ve el costo sin ver la lista de precios (ADR-0054).
  const { data, error } = await client.schema("costing").rpc("ingredient_net_cost", {
    p_ingredient_id: ingredientId,
    p_restaurant_id: restaurantId,
    p_quantity: perBase.factor,
    p_unit_id: units.id,
    ...(cleaningProcessId ? { p_process_id: cleaningProcessId } : {}),
  });
  // Sin permiso para ver costos en ese local no hay costo que mostrar.
  if (error?.code === "42501") return null;
  if (error) throw new Error("No pudimos calcular el costo neto.");
  const c = data?.[0];
  return {
    gross: num(c?.gross ?? null),
    net: num(c?.net ?? null),
    netStatus: c?.net_status ?? "missing_yield",
    per: perBase.label,
    stale: c?.stale ?? false,
    inherited: c?.inherited ?? false,
    validFrom: c?.valid_from ?? null,
  };
}

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
  limit = 10,
): Promise<CostSnapshot[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .from("recipe_cost_snapshots")
    .select("id, created_at, reason, total_cost, reliability")
    .eq("restaurant_id", restaurantId)
    .eq("recipe_id", recipeId)
    .order("entry_number", { ascending: false })
    .limit(limit);
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
  origin: PriceOrigin | null;
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
  const origins = await getPriceOrigins([priceRecordId]);
  return {
    origin: origins.get(priceRecordId) ?? null,
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
