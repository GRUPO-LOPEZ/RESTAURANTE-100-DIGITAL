"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import {
  fieldErrors,
  formValues,
  recipeLinesSchema,
  recipeStepsSchema,
  schemas,
} from "@/lib/forms/schemas";
import { PHOTO_MAX_BYTES, PHOTO_TYPES } from "@/lib/recipe-format";
import { createClient } from "@/lib/supabase/server";

// Acciones del recetario (ADR-0023). Cada una llama a una función de la base, que controla el
// permiso, pide el motivo y deja la auditoría: la pantalla solo valida la forma y traduce la respuesta.
const uuid = z.string().uuid();
const decimal = (value: string) => Number(value.replace(",", "."));

function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

function ids(formData: FormData) {
  return {
    recipe: uuid.safeParse(formData.get("recipeId")),
    version: uuid.safeParse(formData.get("versionId")),
    // Cuándo se leyó el borrador: si otra persona lo cambió después, la base no lo pisa.
    expected: z.string().min(1).max(40).safeParse(formData.get("expectedUpdatedAt")),
  };
}

function refresh(recipeId: string) {
  revalidatePath(`/recetas/${recipeId}`);
  revalidatePath("/recetas");
}

export async function createRecipeAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.recipe.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const [kind, place] = fields.data.scope.split(":") as ["group" | "brand" | "restaurant", string];
  const category = fields.data.category_id ? uuid.safeParse(fields.data.category_id) : null;
  if (category && !category.success)
    return { status: "bad", fieldErrors: { category_id: "Elegí la categoría." } };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("create_recipe", {
    // La función acepta lugares vacíos (el alcance es el más chico indicado); el tipo generado no lo refleja.
    p_group_id: (kind === "group" ? place : null) as string,
    p_brand_id: (kind === "brand" ? place : null) as string,
    p_restaurant_id: (kind === "restaurant" ? place : null) as string,
    p_code: fields.data.code,
    p_name: fields.data.name,
    p_type: fields.data.type,
    p_category_id: (category?.data ?? null) as string,
    p_reason: fields.data.reason,
  });
  const result = data as { result?: string; id?: string } | null;
  if (error || result?.result !== "applied" || !result.id) return toActionState(data, error);
  revalidatePath("/recetas");
  redirect(`/recetas/${result.id}`);
}

export async function updateRecipeAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.recipeEdit.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  if (!recipe.success) return { status: "bad", message: "Falta la receta." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("update_recipe", {
    p_id: recipe.data,
    p_changes: {
      name: fields.data.name,
      short_name: fields.data.short_name ?? "",
      category_id: fields.data.category_id ?? "",
      sector: fields.data.sector ?? "",
      station: fields.data.station ?? "",
    },
    p_reason: fields.data.reason,
  });
  refresh(recipe.data);
  return toActionState(data, error);
}

export async function saveDraftAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.recipeDraft.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe, version, expected } = ids(formData);
  if (!recipe.success || !version.success) return { status: "bad", message: "Falta la versión." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("save_draft", {
    p_version_id: version.data,
    p_data: {
      yield_quantity: String(decimal(fields.data.yield_quantity)),
      yield_unit: fields.data.yield_unit,
      portions: fields.data.portions ?? "",
      portion_grams: fields.data.portion_grams ? String(decimal(fields.data.portion_grams)) : "",
      description: fields.data.description ?? "",
      storage_notes: fields.data.storage_notes ?? "",
      presentation_notes: fields.data.presentation_notes ?? "",
      change_summary: fields.data.change_summary ?? "",
    },
    p_reason: fields.data.reason,
    ...(expected.success ? { p_expected_updated_at: expected.data } : {}),
  });
  refresh(recipe.data);
  return toActionState(data, error);
}

// Líneas y pasos: vienen como objetos desde los editores (listas que la persona arma en la pantalla).
// Todo el argumento se valida con un solo esquema: nunca se confía en lo que manda el navegador.
const editorBase = z.object({
  recipeId: z.string().uuid(),
  versionId: z.string().uuid(),
  expectedUpdatedAt: z.string().min(1).max(40),
  reason: schemas.reason.shape.reason,
});
const linesPayload = editorBase.extend({ lines: recipeLinesSchema });
const stepsPayload = editorBase.extend({ steps: recipeStepsSchema });

function invalidList(error: z.ZodError, what: string): ActionState {
  const issue = error.issues[0];
  const index = issue?.path[1];
  const where = typeof index === "number" ? `${what} ${index + 1}: ` : "";
  return { status: "bad", message: `${where}${issue?.message ?? "Revisá los datos."}` };
}

export async function saveLinesAction(payload: z.input<typeof linesPayload>): Promise<ActionState> {
  const parsed = linesPayload.safeParse(payload);
  if (!parsed.success) return invalidList(parsed.error, "Línea");
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("set_components", {
    p_version_id: parsed.data.versionId,
    p_lines: parsed.data.lines.map((l) => ({
      ingredient_id: l.ingredient_id,
      quantity: decimal(l.quantity),
      unit: l.unit,
      basis: l.basis,
      no_scale: l.no_scale,
      notes: l.notes,
    })),
    p_reason: parsed.data.reason,
    p_expected_updated_at: parsed.data.expectedUpdatedAt,
  });
  refresh(parsed.data.recipeId);
  return toActionState(data, error);
}

export async function saveStepsAction(payload: z.input<typeof stepsPayload>): Promise<ActionState> {
  const parsed = stepsPayload.safeParse(payload);
  if (!parsed.success) return invalidList(parsed.error, "Paso");
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("set_steps", {
    p_version_id: parsed.data.versionId,
    p_steps: parsed.data.steps.map((s) => ({
      kind: s.kind,
      instructions: s.instructions,
      active_minutes: Number(s.active_minutes),
      passive_minutes: Number(s.passive_minutes),
      depends_on: s.depends_on,
    })),
    p_reason: parsed.data.reason,
    p_expected_updated_at: parsed.data.expectedUpdatedAt,
  });
  refresh(parsed.data.recipeId);
  return toActionState(data, error);
}

// Buscador de materias primas para el editor: desde 3 letras, por nombre, alias o código. Un error
// se informa como error (no como "no hay resultados").
export type IngredientSearch =
  | { status: "ok"; results: { id: string; name: string; code: string; unit: string }[] }
  | { status: "error" };

export async function searchIngredientsAction(query: unknown): Promise<IngredientSearch> {
  const text = z.string().max(200).safeParse(query);
  if (!text.success) return { status: "error" };
  const q = text.data
    .replace(/[^\p{L}\p{N} -]/gu, "")
    .trim()
    .slice(0, 60);
  if (q.length < 3) return { status: "ok", results: [] };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .rpc("search_components", { p_query: q, p_limit: 12 });
  if (error) return { status: "error" };
  return {
    status: "ok",
    results: data
      .filter((c) => c.kind === "ingredient")
      .map((c) => ({ id: c.id, name: c.name, code: c.code, unit: c.unit })),
  };
}

async function versionCall(
  formData: FormData,
  fn: "request_review" | "withdraw_review",
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe, version } = ids(formData);
  if (!recipe.success || !version.success) return { status: "bad", message: "Falta la versión." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc(fn, { p_version_id: version.data, p_reason: fields.data.reason });
  refresh(recipe.data);
  revalidatePath("/aprobaciones");
  return toActionState(data, error);
}

export async function requestReviewAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  return versionCall(formData, "request_review");
}

export async function withdrawReviewAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  return versionCall(formData, "withdraw_review");
}

export async function newVersionAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  if (!recipe.success) return { status: "bad", message: "Falta la receta." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("new_version", { p_recipe_id: recipe.data, p_reason: fields.data.reason });
  refresh(recipe.data);
  return toActionState(data, error);
}

export async function archiveRecipeAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  if (!recipe.success) return { status: "bad", message: "Falta la receta." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("archive_recipe", { p_recipe_id: recipe.data, p_reason: fields.data.reason });
  refresh(recipe.data);
  return toActionState(data, error);
}

export async function assignAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const fields = schemas.assignment.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  const restaurant = uuid.safeParse(fields.data.restaurant_id);
  if (!recipe.success) return { status: "bad", message: "Falta la receta." };
  if (!restaurant.success)
    return { status: "bad", fieldErrors: { restaurant_id: "Elegí el local." } };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("set_assignment", {
    p_recipe_id: recipe.data,
    p_restaurant_id: restaurant.data,
    p_assigned: formData.get("assigned") !== "false",
    p_reason: fields.data.reason,
  });
  refresh(recipe.data);
  return toActionState(data, error);
}

// Categorías de recetas, en la pantalla de configuración (como las de materias primas). Las
// administra quien escribe recetas para todo el grupo; la base lo controla.
function categoryDone(
  error: { message?: string; code?: string } | null,
  message: string,
): ActionState {
  revalidatePath("/materias-primas/configuracion");
  revalidatePath("/recetas", "layout");
  return error ? toActionState(null, error) : { status: "ok", message };
}

export async function createRecipeCategoryAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.category.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const groupId = uuid.safeParse(formData.get("groupId"));
  if (!groupId.success) return { status: "bad", message: "Falta el grupo." };
  const parent = fields.data.parent_id ? uuid.safeParse(fields.data.parent_id) : null;
  if (parent && !parent.success)
    return { status: "bad", fieldErrors: { parent_id: "Elegí la categoría madre." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("recipes").rpc("create_category", {
    p_group_id: groupId.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
    ...(parent ? { p_parent_id: parent.data } : {}),
  });
  return categoryDone(error, "Categoría creada. Ya la podés elegir en las recetas.");
}

export async function renameRecipeCategoryAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.rename.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("categoryId"));
  if (!id.success) return { status: "bad", message: "Falta la categoría." };
  const supabase = await createClient();
  const { error } = await supabase.schema("recipes").rpc("rename_category", {
    p_id: id.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  return categoryDone(error, "Nombre cambiado.");
}

export async function archiveRecipeCategoryAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("categoryId"));
  if (!id.success) return { status: "bad", message: "Falta la categoría." };
  const supabase = await createClient();
  const { error } = await supabase
    .schema("recipes")
    .rpc("archive_category", { p_id: id.data, p_reason: fields.data.reason });
  if (error) return toActionState(null, error);
  // La categoría desaparece con su formulario: el aviso va arriba de la pantalla.
  revalidatePath("/recetas", "layout");
  redirect("/materias-primas/configuracion?baja=categoria-receta");
}

// Fotos (PR 3). La foto llega achicada desde el navegador; acá se controla de nuevo tipo y tamaño,
// se sube al bucket con la sesión de la persona (Storage aplica los permisos de la receta) y se
// registra en la base. El nombre del archivo lo arma el servidor, nunca la pantalla.
const PHOTO_EXTENSIONS: Record<(typeof PHOTO_TYPES)[number], string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

// Los primeros bytes de cada formato: JPEG FF D8 FF; PNG 89 50 4E 47; WebP "RIFF" .... "WEBP".
function matchesType(head: Uint8Array, type: (typeof PHOTO_TYPES)[number]): boolean {
  const ascii = (from: number, to: number) => String.fromCharCode(...head.slice(from, to));
  if (type === "image/jpeg") return head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff;
  if (type === "image/png") return head[0] === 0x89 && ascii(1, 4) === "PNG";
  return ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
}

export async function uploadPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.recipePhoto.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  if (!recipe.success) return { status: "bad", message: "Falta la receta." };
  const photo = formData.get("photo");
  if (!(photo instanceof File) || photo.size === 0)
    return { status: "bad", fieldErrors: { photo: "Elegí una foto." } };
  const type = photo.type as (typeof PHOTO_TYPES)[number];
  if (!PHOTO_TYPES.includes(type))
    return { status: "bad", fieldErrors: { photo: "La foto tiene que ser JPG, PNG o WebP." } };
  if (photo.size > PHOTO_MAX_BYTES)
    return { status: "bad", fieldErrors: { photo: "La foto pesa más de 3 MB." } };
  // El contenido real tiene que ser la imagen que dice ser (no solo el tipo que declara el navegador).
  if (!matchesType(new Uint8Array(await photo.slice(0, 12).arrayBuffer()), type))
    return {
      status: "bad",
      fieldErrors: { photo: "El archivo no es una imagen JPG, PNG o WebP." },
    };
  const supabase = await createClient();
  const { data: row, error: readError } = await supabase
    .schema("recipes")
    .from("recipes")
    .select("id, group_id")
    .eq("id", recipe.data)
    .maybeSingle();
  if (readError || !row) return { status: "bad", message: "No encontramos la receta." };
  const path = `${row.group_id}/${row.id}/${randomUUID()}.${PHOTO_EXTENSIONS[type]}`;
  const { error: uploadError } = await supabase.storage
    .from("recipe-media")
    .upload(path, photo, { contentType: type, upsert: false });
  if (uploadError)
    return {
      status: "bad",
      message: "No pudimos subir la foto. Revisá que tengas permiso y probá de nuevo.",
    };
  const { data, error } = await supabase.schema("recipes").rpc("add_media", {
    p_recipe_id: row.id,
    p_storage_path: path,
    p_kind: fields.data.kind,
    p_description: fields.data.description ?? "",
    p_reason: fields.data.reason,
  });
  refresh(row.id);
  return toActionState(data, error);
}

export async function removePhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  const media = uuid.safeParse(formData.get("mediaId"));
  if (!recipe.success || !media.success) return { status: "bad", message: "Falta la foto." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("remove_media", { p_media_id: media.data, p_reason: fields.data.reason });
  refresh(recipe.data);
  return toActionState(data, error);
}
