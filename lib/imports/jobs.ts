import type { BadgeStatus } from "@/components/ui/badge";
import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";

// Lecturas de las importaciones del recetario (ADR-0027). Todo con la sesión de la persona: la base
// decide qué importación ve (RLS) y nunca devuelve precios a quien no los ve. Esta capa no lee precios.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export type JobStatus = Database["imports"]["Enums"]["job_status"];
export type RowKind = Database["imports"]["Enums"]["row_kind"];
export type RowAction = Database["imports"]["Enums"]["row_action"];

export const JOB_STATUS_LABELS: Record<JobStatus, string> = {
  uploaded: "Subida",
  staged: "Filas cargadas",
  validated: "Validada",
  ingredients_confirmed: "Materias primas confirmadas",
  confirmed: "Confirmada",
  cancelled: "Cancelada",
};

export const JOB_STATUS_BADGE: Record<JobStatus, BadgeStatus> = {
  uploaded: "draft",
  staged: "draft",
  validated: "review",
  ingredients_confirmed: "review",
  confirmed: "ok",
  cancelled: "neutral",
};

export const ROW_KIND_LABELS: Record<RowKind, string> = {
  ingredient: "Materias primas",
  preparation: "Preparaciones",
  dish: "Platos",
  line: "Componentes",
};

export const ROW_ACTION_LABELS: Record<RowAction, string> = {
  create: "Se crean",
  reuse: "Se reutilizan",
  skip: "Ya existen",
  error: "Con error",
};

export const IMPORT_JOBS_PAGE = 25;
export const IMPORT_ERRORS_PAGE = 50;

// ---------------------------------------------------------------------------
// Marcas donde la sesión importa, con el prefijo que ya usó cada una
// ---------------------------------------------------------------------------
export type ImportBrand = { id: string; groupId: string; name: string; prefix: string | null };

export async function getImportBrands(): Promise<ImportBrand[]> {
  const supabase = await createClient();
  const [allowed, brands, jobs] = await Promise.all([
    supabase.schema("core").rpc("permitted_brand_ids", { p_permission: "imports.run" }),
    supabase
      .schema("org")
      .from("brands")
      .select("id, name, group_id")
      .is("deleted_at", null)
      .order("name"),
    supabase
      .schema("imports")
      .from("import_jobs")
      .select("brand_id, code_prefix")
      .neq("status", "cancelled")
      .is("deleted_at", null)
      // Las importaciones vigentes de una marca usan todas el mismo prefijo (lo exige la base).
      .order("created_at", { ascending: false })
      .limit(1000),
  ]);
  if (allowed.error || brands.error || jobs.error) failed("las marcas");
  const ids = new Set(
    Array.isArray(allowed.data) ? allowed.data.filter((x) => typeof x === "string") : [],
  );
  const prefixes = new Map(jobs.data.map((j) => [j.brand_id, j.code_prefix]));
  return brands.data
    .filter((b) => ids.has(b.id))
    .map((b) => ({
      id: b.id,
      groupId: b.group_id,
      name: b.name,
      prefix: prefixes.get(b.id) ?? null,
    }));
}

// ---------------------------------------------------------------------------
// Lista de importaciones
// ---------------------------------------------------------------------------
export type ImportJobRow = {
  id: string;
  fileName: string;
  brandName: string;
  prefix: string;
  status: JobStatus;
  createdAt: string;
};

export async function getImportJobs(
  page: number,
): Promise<{ rows: ImportJobRow[]; total: number }> {
  const supabase = await createClient();
  const from = page * IMPORT_JOBS_PAGE;
  const [jobs, brands] = await Promise.all([
    supabase
      .schema("imports")
      .from("import_jobs")
      .select("id, file_name, brand_id, code_prefix, status, created_at", { count: "exact" })
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .range(from, from + IMPORT_JOBS_PAGE - 1),
    supabase.schema("org").from("brands").select("id, name"),
  ]);
  if (jobs.error || brands.error) failed("las importaciones");
  const brandName = new Map(brands.data.map((b) => [b.id, b.name]));
  return {
    total: jobs.count ?? 0,
    rows: jobs.data.map((j) => ({
      id: j.id,
      fileName: j.file_name,
      brandName: brandName.get(j.brand_id) ?? "",
      prefix: j.code_prefix,
      status: j.status,
      createdAt: j.created_at,
    })),
  };
}

// ---------------------------------------------------------------------------
// Una importación: totales, problemas y recetas creadas
// ---------------------------------------------------------------------------
export type ImportIssue = {
  sheet: string | null;
  row: number | null;
  field: string | null;
  severity: Database["imports"]["Enums"]["issue_severity"];
  message: string;
};

export type ImportJob = ImportJobRow & {
  brandId: string;
  ingredientsConfirmedAt: string | null;
  confirmedAt: string | null;
  // Cuántas filas hay por tipo y acción (las filas sin acción todavía no se validaron).
  summary: { kind: RowKind; action: RowAction | null; rows: number }[];
  errors: number;
  warnings: number;
};

export async function getImportJob(id: string): Promise<ImportJob | null> {
  const supabase = await createClient();
  const { data: job, error } = await supabase
    .schema("imports")
    .from("import_jobs")
    .select(
      "id, file_name, brand_id, code_prefix, status, created_at, ingredients_confirmed_at, confirmed_at",
    )
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) failed("la importación");
  if (!job) return null;
  const [summary, brand, errors, warnings] = await Promise.all([
    supabase.schema("imports").rpc("job_summary", { p_job_id: id }),
    supabase.schema("org").from("brands").select("name").eq("id", job.brand_id).maybeSingle(),
    issueCount(id, "error"),
    issueCount(id, "warning"),
  ]);
  if (summary.error || brand.error) failed("la importación");
  return {
    id: job.id,
    fileName: job.file_name,
    brandId: job.brand_id,
    brandName: brand.data?.name ?? "",
    prefix: job.code_prefix,
    status: job.status,
    createdAt: job.created_at,
    ingredientsConfirmedAt: job.ingredients_confirmed_at,
    confirmedAt: job.confirmed_at,
    summary: summary.data.map((s) => ({ kind: s.kind, action: s.action, rows: Number(s.rows) })),
    errors,
    warnings,
  };
}

async function issueCount(jobId: string, severity: ImportIssue["severity"]): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .schema("imports")
    .from("import_errors")
    .select("id", { count: "exact", head: true })
    .eq("job_id", jobId)
    .eq("severity", severity);
  if (error) failed("los problemas de la importación");
  return count ?? 0;
}

// Los problemas por fila: primero los errores, después los avisos, en el orden del Excel.
export async function getImportIssues(
  jobId: string,
  page: number,
  limit = IMPORT_ERRORS_PAGE,
): Promise<{ rows: ImportIssue[]; total: number }> {
  const supabase = await createClient();
  const from = page * limit;
  const { data, count, error } = await supabase
    .schema("imports")
    .from("import_errors")
    .select("sheet, row_number, field, severity, message", { count: "exact" })
    .eq("job_id", jobId)
    .order("severity")
    .order("sheet")
    .order("row_number")
    .order("id")
    .range(from, from + limit - 1);
  if (error) failed("los problemas de la importación");
  return {
    total: count ?? 0,
    rows: data.map((e) => ({
      sheet: e.sheet,
      row: e.row_number,
      field: e.field,
      severity: e.severity,
      message: e.message,
    })),
  };
}

// Las recetas que creó la importación, con su enlace.
export type ImportedRecipe = { recipeId: string; code: string; name: string; kind: RowKind };

export const IMPORTED_RECIPES_PAGE = 50;

export async function getImportedRecipes(
  jobId: string,
  page: number,
): Promise<{ rows: ImportedRecipe[]; total: number }> {
  const supabase = await createClient();
  const from = page * IMPORTED_RECIPES_PAGE;
  const { data, count, error } = await supabase
    .schema("imports")
    .from("import_staging_rows")
    .select("recipe_id, source_code, kind, parsed", { count: "exact" })
    .eq("job_id", jobId)
    .eq("action", "create")
    .in("kind", ["preparation", "dish"])
    .not("recipe_id", "is", null)
    .order("kind", { ascending: true })
    .order("row_number")
    .order("id")
    .range(from, from + IMPORTED_RECIPES_PAGE - 1);
  if (error) failed("las recetas importadas");
  const rows = data.flatMap((r) => {
    const parsed = r.parsed as { name?: unknown } | null;
    return r.recipe_id
      ? [
          {
            recipeId: r.recipe_id,
            code: r.source_code ?? "",
            name: typeof parsed?.name === "string" ? parsed.name : "",
            kind: r.kind,
          },
        ]
      : [];
  });
  return { rows, total: count ?? 0 };
}
