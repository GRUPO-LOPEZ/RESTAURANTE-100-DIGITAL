import { SCENARIO_PAGE, type Reliability, type ScenarioRow } from "@/lib/cost-labels";
import { getCostPlaces, type CostPlace } from "@/lib/costs";
import { createClient } from "@/lib/supabase/server";

// Lecturas de los escenarios de costo (ADR-0032). Todo con la sesión de la persona: la base pide
// scenarios.manage y recipes.view_costs en el local. Nada de esto toca lo oficial.

const num = (v: number | null) => (v === null ? null : Number(v));

// Los locales donde la persona puede simular: maneja escenarios y ve costos.
export async function getScenarioPlaces(): Promise<CostPlace[]> {
  const supabase = await createClient();
  const [{ data, error }, places] = await Promise.all([
    supabase.schema("core").rpc("permitted_restaurant_ids", { p_permission: "scenarios.manage" }),
    getCostPlaces(),
  ]);
  if (error || !Array.isArray(data)) throw new Error("No pudimos cargar tus locales.");
  const allowed = new Set(data.filter((x): x is string => typeof x === "string"));
  return places.filter((p) => allowed.has(p.id));
}

export type Scenario = {
  id: string;
  name: string;
  restaurantId: string;
  archived: boolean;
  createdAt: string;
};

const SCENARIO_COLUMNS = "id, name, restaurant_id, status, created_at";

type RawScenario = {
  id: string;
  name: string;
  restaurant_id: string;
  status: string;
  created_at: string;
};

function toScenario(s: RawScenario): Scenario {
  return {
    id: s.id,
    name: s.name,
    restaurantId: s.restaurant_id,
    archived: s.status === "archived",
    createdAt: s.created_at,
  };
}

// Primero los activos: los archivados no les quitan lugar.
export const SCENARIO_LIST = 200;

export async function getScenarios(restaurantId: string): Promise<Scenario[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .from("cost_scenarios")
    .select(SCENARIO_COLUMNS)
    .eq("restaurant_id", restaurantId)
    .order("status")
    .order("created_at", { ascending: false })
    .limit(SCENARIO_LIST);
  if (error) throw new Error("No pudimos cargar los escenarios.");
  return data.map(toScenario);
}

export async function getScenario(id: string): Promise<Scenario | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .from("cost_scenarios")
    .select(SCENARIO_COLUMNS)
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error("No pudimos cargar el escenario.");
  return data ? toScenario(data) : null;
}

export type ScenarioChange = {
  id: string;
  kind: "price" | "yield" | "quantity";
  item: string;
  recipe: string | null;
  unit: string | null;
  unitCost: number | null;
  supplier: string | null;
  cleaningYield: number | null;
  cookingFactor: number | null;
  quantity: number | null;
  originalQuantity: number | null;
  applies: boolean;
};

export async function getScenarioChanges(id: string): Promise<ScenarioChange[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("scenario_changes", { p_scenario_id: id });
  if (error) throw new Error("No pudimos cargar los cambios del escenario.");
  return data.map((c) => ({
    id: c.id,
    kind: c.kind as ScenarioChange["kind"],
    item: c.item,
    recipe: c.recipe,
    unit: c.unit,
    unitCost: num(c.unit_cost),
    supplier: c.supplier,
    cleaningYield: num(c.cleaning_yield),
    cookingFactor: num(c.cooking_factor),
    quantity: num(c.quantity),
    originalQuantity: num(c.original_quantity),
    applies: c.applies,
  }));
}

export type ScenarioIngredient = {
  id: string;
  name: string;
  unit: string;
  unitCost: number | null;
};

export async function getScenarioIngredients(id: string): Promise<ScenarioIngredient[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("scenario_ingredients", { p_scenario_id: id });
  if (error) throw new Error("No pudimos cargar las materias primas.");
  return data.map((i) => ({
    id: i.id,
    name: i.name,
    unit: i.unit,
    unitCost: num(i.unit_cost),
  }));
}

export async function getScenarioRecipes(id: string): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("scenario_recipes", { p_scenario_id: id });
  if (error) throw new Error("No pudimos cargar las recetas.");
  return data;
}

export type ScenarioLine = { id: string; item: string; quantity: number; unit: string };

export async function getScenarioLines(id: string, recipeId: string): Promise<ScenarioLine[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("scenario_recipe_lines", { p_scenario_id: id, p_recipe_id: recipeId });
  if (error) throw new Error("No pudimos cargar las líneas de la receta.");
  return data.map((l) => ({
    id: l.id,
    item: l.item,
    quantity: Number(l.quantity),
    unit: l.unit,
  }));
}

export type ScenarioResult = {
  rows: ScenarioRow[];
  total: number;
  changed: number;
  topRise: { recipe: string; amount: number } | null;
  topDrop: { recipe: string; amount: number } | null;
};

export async function getScenarioResult(id: string, page: number): Promise<ScenarioResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("scenario_result", {
    p_scenario_id: id,
    p_limit: SCENARIO_PAGE,
    p_offset: page * SCENARIO_PAGE,
  });
  if (error) throw new Error("No pudimos calcular el escenario.");
  const head = data[0];
  const rise = num(head?.top_rise ?? null);
  const drop = num(head?.top_drop ?? null);
  return {
    rows: data.map((r) => ({
      recipeId: r.recipe_id,
      recipe: r.recipe,
      today: num(r.cost_today),
      simulated: num(r.cost_simulated),
      difference: num(r.difference),
      differencePct: num(r.difference_pct),
      portionToday: num(r.portion_today),
      portionSimulated: num(r.portion_simulated),
      reliability: r.reliability as Reliability,
    })),
    total: Number(head?.total_rows ?? 0),
    changed: Number(head?.changed_rows ?? 0),
    topRise:
      head && rise !== null && rise > 0 ? { recipe: head.top_rise_recipe, amount: rise } : null,
    topDrop:
      head && drop !== null && drop < 0 ? { recipe: head.top_drop_recipe, amount: drop } : null,
  };
}
