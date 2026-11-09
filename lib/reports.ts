import { RELIABILITY } from "@/lib/cost-labels";
import { getCostLines, getCostRow } from "@/lib/costs";
import { formatMoney } from "@/lib/money";
import { qualityHref, qualityIndicator } from "@/lib/quality-labels";
import { formatDateTime } from "@/lib/data";
import { LINE_UNITS } from "@/lib/recipe-format";
import { BASIS_LABELS, formatMinutes, formatQuantity, getKitchenCard } from "@/lib/recipes";
import {
  COST_REASON,
  QUALITY_ACTION,
  REPORT_CHUNK,
  REPORT_EXPORT_LIMIT,
  allergenAlerts,
  type ReportAlert,
  cookingEffect,
  type ReportKey,
  type ReportRow,
} from "@/lib/report-labels";
import { createClient } from "@/lib/supabase/server";

// Lecturas de los reportes (ADR-0034). Todo con la sesión de la persona: la base pide reports.export
// y el permiso de cada dato. La pantalla, el Excel y el CSV salen de estas filas.

export type ReportPlace = { id: string; name: string };

export async function getReportPlaces(): Promise<ReportPlace[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("report_places");
  if (error) throw new Error("No pudimos cargar tus locales.");
  return data;
}

export async function getReportList(restaurantId: string): Promise<string[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("report_list", { p_restaurant_id: restaurantId });
  if (error) throw new Error("No pudimos cargar los reportes.");
  return data;
}

type Filter = { restaurantId: string; from: string; to: string; recipeId?: string };
// Una ficha trae, además de las filas, de qué receta es: va en el encabezado de la pantalla y del archivo.
// Una ficha trae también los alérgenos: en pantalla van marcados y en el archivo, en el encabezado.
type Page = { rows: ReportRow[]; total: number; summary?: string[]; alerts?: ReportAlert[] };

export type ReportRecipe = { id: string; code: string; name: string; type: string };

// Las recetas de las que se puede sacar una ficha en un local.
export async function getReportRecipes(
  restaurantId: string,
  search: string | undefined,
): Promise<{ recipes: ReportRecipe[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("report_recipes", {
    p_restaurant_id: restaurantId,
    p_search: search,
    p_limit: 50,
  });
  if (error) throw new Error("No pudimos cargar las recetas.");
  return {
    recipes: data.map((r) => ({
      id: r.recipe_id,
      code: r.code,
      name: r.name,
      type: r.recipe_type === "preparation" ? "Preparación" : "Plato",
    })),
    total: Number(data[0]?.total_rows ?? 0),
  };
}

// La ficha técnica: lo de la vista de cocina, que nunca trae valores económicos.
async function recipeCard(recipeId: string): Promise<Page | null> {
  const card = await getKitchenCard(recipeId);
  if (!card) return null;
  const rows: ReportRow[] = card.components.map((c) => ({
    item: c.sub_recipe_id ? `${c.ingredient} (preparación)` : c.ingredient,
    quantity: c.quantity,
    unit: c.unit,
    basis: BASIS_LABELS[c.basis],
    notes: c.notes,
  }));
  const summary = [
    `${card.name} · ${card.code} · versión ${card.versionNumber} · vigente desde ${formatDateTime(card.publishedAt)}`,
    ...(card.variantOf ? [`Variante de «${card.variantOf.name}» para este local`] : []),
    ...(card.description ? [card.description] : []),
    `Rinde: ${card.yieldQuantity ? `${formatQuantity(card.yieldQuantity)} ${card.yieldUnit ?? ""}` : "sin cargar"}${
      card.portions ? `, ${card.portions} ${card.portions === 1 ? "porción" : "porciones"}` : ""
    }${card.portionGrams ? ` de ${formatQuantity(card.portionGrams)} g` : ""}`,
    `Tiempo total: ${formatMinutes(card.totalMinutes)} · Trabajando: ${formatMinutes(card.activeMinutes)}`,
  ];
  return { rows, total: rows.length, summary, alerts: allergenAlerts(card.allergens) };
}

// La ficha de costeo: el costo de cada línea en el local.
async function costCard(restaurantId: string, recipeId: string): Promise<Page | null> {
  const row = await getCostRow(restaurantId, recipeId);
  if (!row) return null;
  const client = await createClient();
  const [lines, version] = await Promise.all([
    getCostLines(row.versionId, restaurantId),
    client
      .schema("recipes")
      .from("recipe_versions")
      .select("version_number")
      .eq("id", row.versionId)
      .maybeSingle(),
  ]);
  const rows: ReportRow[] = lines.map((l) => ({
    item: l.preparation ? `${l.item} (preparación)` : l.item,
    quantity: l.quantity,
    // La unidad como se lee, no su código.
    unit: LINE_UNITS.find((u) => u.code === l.unit)?.label ?? l.unit,
    cost: l.cost,
    share: l.share,
    state: l.missing ?? "Completo",
  }));
  const summary = [
    `${row.name} · ${row.code}${version.data ? ` · versión ${version.data.version_number}` : ""}`,
    `Costo: ${RELIABILITY[row.reliability].label}${
      row.reliability === "stale" ? " (algún precio pasó su plazo sin actualizarse)" : ""
    }`,
    `Total sin IVA: ${row.total === null ? "sin costo" : formatMoney(row.total)} · Con IVA: ${
      row.gross === null ? "sin costo" : formatMoney(row.gross)
    }`,
    `Por porción: ${row.perPortion === null ? "—" : formatMoney(row.perPortion)}${
      row.portions ? ` (${row.portions} ${row.portions === 1 ? "porción" : "porciones"})` : ""
    }`,
  ];
  return { rows, total: rows.length, summary };
}
const STATE = (stale: boolean | null, status: string | null) =>
  status === "missing_legal_entity"
    ? "Falta la razón social del local"
    : status !== "ok"
      ? "Sin precio"
      : stale
        ? "Desactualizado"
        : "Al día";

// Una página de un reporte. Sin permiso, null: la pantalla responde que no existe.
export async function getReportPage(
  key: ReportKey,
  filter: Filter,
  limit: number,
  offset: number,
): Promise<Page | null> {
  if (key === "recipe_card" || key === "cost_card") {
    if (!filter.recipeId) return null;
    // La base controla el permiso del reporte y que la receta sea una vigente del local.
    const client = await createClient();
    const { error } = await client.schema("costing").rpc("require_report_recipe", {
      p_report: key,
      p_restaurant_id: filter.restaurantId,
      p_recipe_id: filter.recipeId,
    });
    if (error?.code === "42501") return null;
    if (error) throw new Error("No pudimos cargar la ficha.");
    // Una ficha no se pagina: entra entera.
    if (offset > 0) return { rows: [], total: 0 };
    return key === "recipe_card"
      ? recipeCard(filter.recipeId)
      : costCard(filter.restaurantId, filter.recipeId);
  }
  const supabase = await createClient();
  const costing = supabase.schema("costing");
  const range = { p_restaurant_id: filter.restaurantId, p_limit: limit, p_offset: offset };
  const finish = <T extends { total_rows: number }>(
    data: T[] | null,
    error: { code?: string } | null,
    map: (row: T) => ReportRow,
  ): Page | null => {
    if (error?.code === "42501") return null;
    if (error || !data) throw new Error("No pudimos cargar el reporte.");
    return { rows: data.map(map), total: Number(data[0]?.total_rows ?? 0) };
  };

  if (key === "ingredients") {
    const { data, error } = await costing.rpc("report_ingredients", range);
    return finish(data, error, (r) => ({
      name: r.name,
      category: r.category,
      unit: r.unit,
      unit_cost: r.unit_cost as number | null,
      valid_from: r.valid_from as string | null,
      state: STATE(r.stale as boolean | null, r.status as string | null),
      href: qualityHref("ingredient", r.item_id),
    }));
  }
  if (key === "yields") {
    const { data, error } = await costing.rpc("report_yields", range);
    return finish(data, error, (r) => ({
      ingredient: r.ingredient,
      process: r.process,
      cut: r.cut as string | null,
      supplier: r.supplier as string | null,
      cleaning_yield: r.cleaning_yield,
      waste: r.waste,
      cooking: cookingEffect(Number(r.cooking_factor)),
      approved_at: r.approved_at as string | null,
    }));
  }
  if (key === "usage") {
    const { data, error } = await costing.rpc("report_usage", range);
    return finish(data, error, (r) => ({
      component: r.component,
      recipe: r.recipe,
      version_number: r.version_number,
      quantity: r.quantity as number | null,
      unit: r.unit as string | null,
      through: r.through as string | null,
    }));
  }
  if (key === "cost_changes") {
    const { data, error } = await costing.rpc("report_cost_changes", {
      ...range,
      p_from: filter.from,
      p_to: filter.to,
    });
    return finish(data, error, (r) => ({
      changed_on: r.changed_on,
      recipe: r.in_use ? r.recipe : `${r.recipe} (ya no se usa)`,
      recipe_type: r.recipe_type === "preparation" ? "Preparación" : "Plato",
      version_number: r.version_number,
      reason: COST_REASON[r.reason] ?? "Otro",
      previous: r.previous as number | null,
      current_cost: r.current_cost as number | null,
      difference: r.difference as number | null,
      difference_pct: r.difference_pct as number | null,
    }));
  }
  const { data, error } = await costing.rpc("report_quality", range);
  return finish(data, error, (r) => ({
    problem: qualityIndicator(r.indicator)?.missing ?? r.indicator,
    item: r.item,
    detail: r.detail as string | null,
    action: QUALITY_ACTION[r.indicator] ?? null,
    href: qualityHref(r.kind, r.item_id),
  }));
}

// Todas las filas para exportar, de a páginas y con tope.
export async function getReportRows(key: ReportKey, filter: Filter): Promise<Page | null> {
  const rows: ReportRow[] = [];
  let total = 0;
  let summary: string[] | undefined;
  let alerts: ReportAlert[] | undefined;
  for (let offset = 0; offset < REPORT_EXPORT_LIMIT; offset += REPORT_CHUNK) {
    const page = await getReportPage(key, filter, REPORT_CHUNK, offset);
    if (!page) return null;
    rows.push(...page.rows);
    total = Math.max(total, page.total);
    summary ??= page.summary;
    alerts ??= page.alerts;
    if (rows.length >= page.total || page.rows.length < REPORT_CHUNK) break;
  }
  return { rows, total, summary, alerts };
}

export type ReportExport = {
  at: string;
  person: string;
  report: string;
  format: string;
  rows: number | null;
  place: string;
};

// Quién exportó qué: la base solo trae los locales donde la persona ve el registro de seguridad.
export async function getReportExports(): Promise<ReportExport[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("report_exports");
  if (error) return [];
  return data.map((e) => ({
    at: e.occurred_at,
    person: e.person,
    report: e.report,
    format: e.format,
    rows: e.rows_count as number | null,
    place: e.restaurant,
  }));
}

export async function logReport(
  key: ReportKey,
  restaurantId: string,
  format: "pdf" | "xlsx" | "csv",
  rows: number,
  period?: { from: string; to: string },
  recipeId?: string,
): Promise<boolean> {
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("log_report", {
    p_report: key,
    p_restaurant_id: restaurantId,
    p_format: format,
    p_rows: rows,
    p_from: period?.from,
    p_to: period?.to,
    p_recipe_id: recipeId,
  });
  return !error;
}
