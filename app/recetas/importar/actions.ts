"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { MAX_FILE_BYTES, readRecipeBook } from "@/lib/imports/recipe-book";
import { createClient } from "@/lib/supabase/server";

// Acciones de la importación del recetario (ADR-0027). Cada paso lo valida la base (permiso, motivo,
// estado y auditoría); acá solo se valida la forma y se traduce la respuesta.
const uuid = z.string().uuid();
const BATCH = 500;
// <grupo>/<marca>/<archivo>.xlsx, como exige el bucket.
const PATH = /^([0-9a-f-]{36})\/([0-9a-f-]{36})\/[0-9a-f-]{36}\.xlsx$/;

function refresh(jobId?: string) {
  if (jobId) revalidatePath(`/recetas/importar/${jobId}`);
  revalidatePath("/recetas/importar");
}

// El navegador ya subió el Excel al bucket (Vercel no acepta pedidos de más de 4,5 MB). Acá el
// servidor lo baja con la sesión de quien lo subió, lo lee, registra la importación, carga las filas
// y la valida. Si la carga falla a mitad de camino, la importación se cancela.
export async function readImportAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.importBook.safeParse(formValues(formData));
  if (!fields.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: fieldErrors(fields.error),
    };
  const path = PATH.exec(String(formData.get("path") ?? ""));
  const fileName = String(formData.get("file_name") ?? "")
    .trim()
    .slice(0, 200);
  if (!path || path[2] !== fields.data.brand_id || !fileName)
    return { status: "bad", message: "El archivo no se subió bien: probá de nuevo." };

  const supabase = await createClient();
  const { data: blob, error: downloadError } = await supabase.storage
    .from("imports")
    .download(path[0]);
  if (downloadError || !blob)
    return { status: "bad", message: "No pudimos leer el archivo subido. Probá de nuevo." };
  if (blob.size > MAX_FILE_BYTES) return { status: "bad", message: "El archivo pasa los 15 MB." };
  const book = await readRecipeBook(await blob.arrayBuffer());
  if (!book.ok) return { status: "bad", message: book.message };

  const created = await supabase.schema("imports").rpc("create_job", {
    p_brand_id: fields.data.brand_id,
    p_storage_path: path[0],
    p_file_name: fileName,
    p_file_sha256: book.sha256,
    p_code_prefix: fields.data.code_prefix,
    p_reason: fields.data.reason,
    // La base no deja validar si la carga queda cortada (un corte de tiempo, una falla a mitad de camino).
    p_expected_rows: book.rows.length,
  });
  const job = created.data as { result?: string; id?: string } | null;
  if (created.error || job?.result !== "applied" || !job.id)
    return toActionState(created.data, created.error);

  for (let i = 0; i < book.rows.length; i += BATCH) {
    const staged = await supabase.schema("imports").rpc("stage_rows", {
      p_job_id: job.id,
      p_rows: book.rows.slice(i, i + BATCH),
    });
    const result = staged.data as { result?: string } | null;
    if (staged.error || result?.result !== "applied") {
      await supabase.schema("imports").rpc("cancel_job", {
        p_job_id: job.id,
        p_reason: "La carga de las filas del Excel falló",
      });
      refresh();
      return toActionState(staged.data, staged.error);
    }
  }
  // Si la validación falla, la vista previa ofrece "Validar de nuevo".
  await supabase.schema("imports").rpc("validate_job", { p_job_id: job.id });
  refresh(job.id);
  redirect(`/recetas/importar/${job.id}`);
}

// Los pasos de la vista previa: el id de la importación y, salvo validar, un motivo.
type Step = "confirm_ingredients" | "confirm_recipes" | "cancel_job";

async function step(rpc: Step, formData: FormData): Promise<ActionState> {
  const job = uuid.safeParse(formData.get("jobId"));
  if (!job.success) return { status: "bad", message: "Falta la importación." };
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: fieldErrors(fields.error),
    };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("imports")
    .rpc(rpc, { p_job_id: job.data, p_reason: fields.data.reason });
  refresh(job.data);
  return toActionState(data, error);
}

export async function confirmIngredientsAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  return step("confirm_ingredients", formData);
}

export async function confirmRecipesAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  return step("confirm_recipes", formData);
}

export async function cancelImportAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  return step("cancel_job", formData);
}

export async function validateImportAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const job = uuid.safeParse(formData.get("jobId"));
  if (!job.success) return { status: "bad", message: "Falta la importación." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("imports")
    .rpc("validate_job", { p_job_id: job.data });
  refresh(job.data);
  return toActionState(data, error);
}
