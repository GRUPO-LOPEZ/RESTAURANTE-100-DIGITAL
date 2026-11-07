import { qualityHref, qualityIndicator } from "@/lib/quality-labels";
import {
  COST_REASON,
  QUALITY_ACTION,
  REPORT_CHUNK,
  REPORT_EXPORT_LIMIT,
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

type Filter = { restaurantId: string; from: string; to: string };
type Page = { rows: ReportRow[]; total: number };
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
export async function getReportRows(
  key: ReportKey,
  filter: Filter,
): Promise<{ rows: ReportRow[]; total: number } | null> {
  const rows: ReportRow[] = [];
  let total = 0;
  for (let offset = 0; offset < REPORT_EXPORT_LIMIT; offset += REPORT_CHUNK) {
    const page = await getReportPage(key, filter, REPORT_CHUNK, offset);
    if (!page) return null;
    rows.push(...page.rows);
    total = Math.max(total, page.total);
    if (rows.length >= page.total || page.rows.length < REPORT_CHUNK) break;
  }
  return { rows, total };
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
): Promise<boolean> {
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("log_report", {
    p_report: key,
    p_restaurant_id: restaurantId,
    p_format: format,
    p_rows: rows,
    p_from: period?.from,
    p_to: period?.to,
  });
  return !error;
}
