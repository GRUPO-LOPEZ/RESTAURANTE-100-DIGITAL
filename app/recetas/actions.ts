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
  recipeSheetDataSchema,
  recipeSheetDraftSchema,
  recipeStepsSchema,
  schemas,
} from "@/lib/forms/schemas";
import { codeChangedHref } from "@/lib/codes";
import {
  LINE_UNIT_CODES,
  PHOTO_MAX_BYTES,
  PHOTO_TYPES,
  type NewRecipeType,
  type UnitDimension,
} from "@/lib/recipe-format";
import { compatibleDimensions, type PreviewLine } from "@/lib/recipe-sheet";
import { parseAmount } from "@/lib/money";
import { getUnitWeights } from "@/lib/recipes";
import { createClient } from "@/lib/supabase/server";

// Acciones del recetario (ADR-0023). Cada una llama a una función de la base, que controla el
// permiso, pide el motivo y deja la auditoría: la pantalla solo valida la forma y traduce la respuesta.
const uuid = z.string().uuid();

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
  const category = uuid.safeParse(fields.data.category_id);
  if (!category.success) return { status: "bad", fieldErrors: { category_id: "Elegí el rubro." } };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("create_recipe", {
    // La función acepta lugares vacíos (el alcance es el más chico indicado); el tipo generado no lo refleja.
    p_group_id: (kind === "group" ? place : null) as string,
    p_brand_id: (kind === "brand" ? place : null) as string,
    p_restaurant_id: (kind === "restaurant" ? place : null) as string,
    p_name: fields.data.name,
    p_type: fields.data.type,
    p_category_id: category.data,
    p_reason: fields.data.reason,
    p_expected_code: fields.data.expected_code ?? "",
  });
  const result = data as { result?: string; id?: string; code?: string } | null;
  if (error || result?.result !== "applied" || !result.id) return toActionState(data, error);
  revalidatePath("/recetas");
  // Si salió otro código que el de la vista previa, la ficha lo avisa (ADR-0041).
  redirect(codeChangedHref(`/recetas/${result.id}`, fields.data.expected_code, result.code));
}

// El buscador de la planilla está en lib/recipe-search.ts y se usa por la ruta GET /recetas/buscar-componentes
// (ADR-0047).

// Variante local de una maestra: la base pide recipes.approve en ese local, copia la vigente y la
// asigna. Al crearla, se va a su ficha para ajustarla.
export async function createVariantAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.variant.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const { recipe } = ids(formData);
  const place = uuid.safeParse(fields.data.restaurant_id);
  if (!recipe.success) return { status: "bad", message: "Falta la receta." };
  if (!place.success) return { status: "bad", fieldErrors: { restaurant_id: "Elegí el local." } };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("create_variant", {
    p_master_id: recipe.data,
    p_restaurant_id: place.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  const result = data as { result?: string; id?: string } | null;
  if (error || result?.result !== "applied" || !result.id) return toActionState(data, error);
  refresh(recipe.data);
  redirect(`/recetas/${result.id}`);
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

// En el celular no está la barra de la ficha: la revisión se pide desde «Versiones y aprobaciones».
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

// Vista previa del código de una receta nueva (ADR-0041): la base dice qué código saldría para ese rubro y tipo,
// sin entregar el número. Sin permiso o sin rubro devuelve null.
export async function previewRecipeCodeAction(
  categoryId: string,
  type: NewRecipeType,
): Promise<string | null> {
  const category = uuid.safeParse(categoryId);
  if (!category.success || (type !== "dish" && type !== "preparation")) return null;
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("preview_code", { p_category_id: category.data, p_type: type });
  return error ? null : (data ?? null);
}

// ---------------------------------------------------------------------------------------------------------------
// Ficha única de receta (ADR-0042)
// ---------------------------------------------------------------------------------------------------------------

// La grilla mientras se escribe: la base calcula cada fila con el mismo motor que el costo oficial y devuelve solo
// lo que la sesión puede ver (pesos; costos con recipes.view_costs; precios con prices.view).
const previewLine = z.object({
  ingredient_id: uuid.nullable(),
  sub_recipe_id: uuid.nullable(),
  quantity: z.number().positive().max(1e9),
  unit: z.enum(LINE_UNIT_CODES),
  basis: z.enum(["purchase", "clean", "cooked", "finished"]),
  yield_profile_id: uuid.nullable().optional(),
});
export type SheetPreview = { status: "ok"; lines: PreviewLine[] } | { status: "error" };

export async function previewSheetLinesAction(
  versionId: unknown,
  restaurantId: unknown,
  lines: unknown,
): Promise<SheetPreview> {
  const version = uuid.safeParse(versionId);
  const place = uuid.nullable().safeParse(restaurantId ?? null);
  // Las filas sin completar van como null: así cada respuesta conserva la posición en la grilla.
  const rows = z.array(previewLine.nullable()).max(200).safeParse(lines);
  if (!version.success || !place.success || !rows.success) return { status: "error" };
  const client = await createClient();
  const { data, error } = await client.schema("costing").rpc("preview_sheet_lines", {
    p_version_id: version.data,
    // Sin local: solo pesos. El tipo generado no admite null (argumento sin valor por defecto).
    p_restaurant_id: place.data as string,
    p_lines: rows.data.map((r) => r ?? {}),
  });
  if (error) return { status: "error" };
  const num = (v: number | null) => (v === null ? null : Number(v));
  return {
    status: "ok",
    lines: data.map((l) => ({
      lineOrder: l.line_order,
      grams: num(l.grams),
      weightStatus: l.weight_status,
      lineCost: num(l.line_cost),
      unitCost: num(l.unit_cost),
      costUnit: l.cost_unit,
      status: l.status,
    })),
  };
}

// Medidas que admite cada materia prima de la grilla (para ofrecer solo unidades que se pueden convertir).
export async function unitOptionsAction(
  ingredientIds: unknown,
): Promise<Record<string, { dims: UnitDimension[]; unitWeight: number | null }>> {
  const list = z.array(uuid).max(200).safeParse(ingredientIds);
  if (!list.success || list.data.length === 0) return {};
  const client = await createClient();
  const { data, error } = await client
    .schema("catalog")
    .rpc("ingredient_unit_options", { p_ids: list.data });
  if (error) return {};
  // El peso por unidad, para la medida práctica (si no se puede leer, no se ofrece cruzar peso con unidades).
  const weights = await getUnitWeights(list.data).catch((): Record<string, number> => ({}));
  return Object.fromEntries(
    data.map((o) => [
      o.ingredient_id,
      {
        dims: compatibleDimensions(o.dimension as UnitDimension, o.has_density, o.has_unit_weight),
        unitWeight: weights[o.ingredient_id] ?? null,
      },
    ]),
  );
}

// «+ Nueva materia prima» desde la receta (ADR-0064): solo nombre, rubro, unidad y motivo. La base controla el permiso
// (catalog.create_ingredients o catalog.manage para todo el grupo) y le avisa a Compras.
export type QuickIngredient = { id: string; code: string; name: string; unit: string };
export type SimilarIngredient = QuickIngredient;

const quickIngredientSchema = z.object({
  groupId: uuid,
  name: z.string().trim().min(1, "Escribí el nombre.").max(120, "Hasta 120 caracteres."),
  categoryId: z.string().uuid("Elegí el rubro."),
  unit: z.string().min(1, "Elegí la unidad.").max(20),
  reason: schemas.reason.shape.reason,
});

export async function quickIngredientAction(
  payload: z.input<typeof quickIngredientSchema>,
): Promise<ActionState & { ingredient?: QuickIngredient }> {
  const parsed = quickIngredientSchema.safeParse(payload);
  if (!parsed.success) return invalid(parsed.error);
  const p = parsed.data;
  const client = await createClient();
  const { data, error } = await client.schema("catalog").rpc("quick_ingredient", {
    p_group_id: p.groupId,
    p_name: p.name,
    p_category_id: p.categoryId,
    p_recipe_unit: p.unit,
    p_reason: p.reason,
  });
  const result = toActionState(data, error);
  const out = z.object({ id: uuid, code: z.string() }).safeParse(data);
  if (result.status !== "ok" || !out.success) return result;
  revalidatePath("/materias-primas");
  const { data: row } = await client
    .schema("catalog")
    .from("ingredients")
    .select("name, recipe_unit_id")
    .eq("id", out.data.id)
    .maybeSingle();
  const { data: unit } = row
    ? await client
        .schema("catalog")
        .from("units")
        .select("code")
        .eq("id", row.recipe_unit_id)
        .maybeSingle()
    : { data: null };
  return {
    ...result,
    ingredient: {
      id: out.data.id,
      code: out.data.code,
      name: row?.name ?? p.name,
      unit: unit?.code ?? "g",
    },
  };
}

// «¿Es esta?»: las parecidas, para no crear una repetida. Si no se puede leer, ninguna.
export async function similarIngredientsAction(
  groupId: unknown,
  name: unknown,
): Promise<SimilarIngredient[]> {
  const parsed = z
    .object({ groupId: uuid, name: z.string().max(120) })
    .safeParse({ groupId, name });
  if (!parsed.success || parsed.data.name.trim().length < 3) return [];
  const client = await createClient();
  const { data, error } = await client.schema("catalog").rpc("similar_ingredients", {
    p_group_id: parsed.data.groupId,
    p_name: parsed.data.name,
  });
  return error ? [] : data.map((i) => ({ id: i.id, code: i.code, name: i.name, unit: i.unit }));
}

// «+ Agregar» un sector, una partida o un equipo sin salir de la receta (ADR-0064): lo guarda en la lista en el momento, con
// su motivo. La base controla quién edita la lista (catalog.save_settings_list) y que no se repita.
const QUICK_LISTS = {
  sectors: "kitchen_sectors",
  stations: "kitchen_stations",
  equipment: "kitchen_equipment",
} as const;
export type QuickList = keyof typeof QUICK_LISTS;
const quickListSchema = z.object({
  groupId: uuid,
  list: z.enum(["sectors", "stations", "equipment"]),
  name: z.string().trim().min(1, "Escribí el nombre.").max(120, "Hasta 120 caracteres."),
  capacity: z.string().trim().max(20).default(""),
  capacityUnit: z.string().max(20).default(""),
  capacityLabel: z.string().trim().max(40).default(""),
  reason: schemas.reason.shape.reason,
});

export async function quickListItemAction(
  payload: z.input<typeof quickListSchema>,
): Promise<ActionState & { item?: { id: string; name: string } }> {
  const parsed = quickListSchema.safeParse(payload);
  if (!parsed.success) return invalid(parsed.error);
  const p = parsed.data;
  const client = await createClient();
  const { data: list, error: readError } = await client
    .schema("catalog")
    .rpc("settings_list", { p_group_id: p.groupId, p_list: p.list });
  const stamp = z.object({ stamp: z.string() }).safeParse(list);
  if (readError || !stamp.success)
    return { status: "bad", message: "No tenés permiso para editar esta lista." };
  const { data, error } = await client.schema("catalog").rpc("save_settings_list", {
    p_group_id: p.groupId,
    p_list: p.list,
    p_expected_stamp: stamp.data.stamp,
    p_items: [
      {
        name: p.name,
        ...(p.list === "equipment"
          ? {
              capacity: p.capacity,
              capacity_unit: p.capacityUnit,
              capacity_label: p.capacityLabel,
            }
          : {}),
      },
    ],
    p_reason: p.reason,
  });
  const result = toActionState(data, error);
  if (result.status !== "ok") return result;
  revalidatePath("/materias-primas/configuracion");
  // La base devuelve el id de lo creado; el nombre, como quedó (sin espacios de más).
  const created = z.object({ created: z.array(uuid).length(1) }).safeParse(data);
  if (!created.success) return result;
  const { data: item } = await client
    .schema("catalog")
    .from(QUICK_LISTS[p.list])
    .select("id, name")
    .eq("id", created.data.created[0] ?? "")
    .maybeSingle();
  return item ? { ...result, item: { id: item.id, name: item.name } } : result;
}

// Guardado en lote: datos, rendimiento, líneas y pasos en una sola transacción, con un solo motivo. Con submit,
// además pide la revisión. Todo el argumento se valida con un esquema: nunca se confía en lo que manda el navegador.
const sheetPayload = z.object({
  recipeId: uuid,
  versionId: uuid,
  expectedUpdatedAt: z.string().min(1).max(40),
  reason: schemas.reason.shape.reason,
  submit: z.boolean(),
  recipe: recipeSheetDataSchema.nullable(),
  draft: recipeSheetDraftSchema.nullable(),
  lines: recipeLinesSchema.nullable(),
  steps: recipeStepsSchema.nullable(),
});
// warning: se guardó, pero algo no se pudo calcular (por ejemplo, las porciones de un plato).
export type SheetResult = ActionState & { versionId?: string; warning?: string };

export async function saveSheetAction(payload: z.input<typeof sheetPayload>): Promise<SheetResult> {
  const parsed = sheetPayload.safeParse(payload);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const [block, index] = issue?.path ?? [];
    const where =
      block === "lines" && typeof index === "number"
        ? `Fila ${index + 1}: `
        : block === "steps" && typeof index === "number"
          ? `Paso ${index + 1}: `
          : "";
    return { status: "bad", message: `${where}${issue?.message ?? "Revisá los datos."}` };
  }
  const p = parsed.data;
  const draft = p.draft
    ? Object.fromEntries(
        Object.entries(p.draft).map(([k, v]) => [
          k,
          // parseAmount entiende «1.500» y «2,5» (es-AR); el esquema ya controló que sea un número.
          (k === "yield_quantity" || k === "portion_grams") && v
            ? String(parseAmount(v))
            : (v ?? ""),
        ]),
      )
    : null;
  const client = await createClient();
  const { data, error } = await client.schema("recipes").rpc("save_sheet", {
    p_recipe_id: p.recipeId,
    p_version_id: p.versionId,
    p_expected_updated_at: p.expectedUpdatedAt,
    // Los bloques que no cambiaron van vacíos: la base no los toca.
    p_recipe: p.recipe as unknown as string,
    p_draft: draft as unknown as string,
    p_lines: (p.lines
      ? p.lines.map((l) => ({
          ingredient_id: l.ingredient_id,
          sub_recipe_id: l.sub_recipe_id,
          quantity: parseAmount(l.quantity),
          unit: l.unit,
          basis: l.basis,
          yield_profile_id: l.yield_profile_id ?? null,
          no_scale: l.no_scale,
          notes: l.notes,
          ...(l.measure_id
            ? {
                measure_id: l.measure_id,
                measure_count: l.measure_count ? String(parseAmount(l.measure_count)) : "",
              }
            : {}),
        }))
      : null) as unknown as string,
    p_steps: (p.steps
      ? p.steps.map((s) => ({
          // El elemento manda sobre el texto: un borrador abierto mientras la lista cambia un nombre no pierde el vínculo.
          ...(s.equipment_id ? { equipment_id: s.equipment_id } : { equipment: s.equipment }),
          equipment_capacity: s.equipment_capacity ? String(parseAmount(s.equipment_capacity)) : "",
          equipment_capacity_unit: s.equipment_capacity_unit,
          kind: s.kind,
          instructions: s.instructions,
          active_minutes: Number(s.active_minutes),
          passive_minutes: Number(s.passive_minutes),
          control_point: s.control_point,
          depends_on: s.depends_on,
        }))
      : null) as unknown as string,
    p_reason: p.reason,
    p_submit: p.submit,
  });
  refresh(p.recipeId);
  const result = toActionState(data, error);
  const out = data as { version_id?: string; warning?: string | null } | null;
  return {
    ...result,
    ...(out?.version_id ? { versionId: out.version_id } : {}),
    ...(out?.warning ? { warning: out.warning } : {}),
  };
}

// Quien revisa decide desde la ficha (la base vuelve a controlar que tenga permiso y que no sea quien la pidió).
const decisionPayload = z.object({
  recipeId: uuid,
  requestId: uuid,
  decision: z.enum(["approved", "rejected"]),
  comment: z.string().trim().max(1000, "Hasta 1.000 caracteres."),
});
export async function decideReviewAction(
  payload: z.input<typeof decisionPayload>,
): Promise<ActionState> {
  const parsed = decisionPayload.safeParse(payload);
  if (!parsed.success) return { status: "bad", message: "Elegí aprobar o no aprobar." };
  if (parsed.data.decision === "rejected" && !parsed.data.comment) {
    return { status: "bad", message: "Para no aprobarla, escribí la observación." };
  }
  const client = await createClient();
  const { data, error } = await client.schema("workflow").rpc("decide_approval", {
    p_request_id: parsed.data.requestId,
    p_decision: parsed.data.decision,
    p_comment: parsed.data.comment || undefined,
  });
  refresh(parsed.data.recipeId);
  revalidatePath("/aprobaciones");
  return toActionState(data, error);
}
