"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { parseDecimal } from "@/lib/price-lists";
import { getSupplierProducts, searchIngredients } from "@/lib/price-lists-data";
import { createClient } from "@/lib/supabase/server";

// Acciones de la cola de mapeo (Fase 3, ADR-0052). La base controla el permiso (catalog.map_articles para todo el
// grupo), pide el motivo y deja la auditoría. Resolver crea el producto de compra del proveedor y pasa a él los
// renglones de lista, en una transacción.

const uuid = z.string().uuid();
const reason = z.string().trim().min(3, "Escribí el motivo (al menos 3 letras).").max(500);

// Las unidades de contenido que se ofrecen; kg y l se pasan a g y ml antes de guardar.
const CONTENT_UNITS = {
  g: ["g", 1],
  kg: ["g", 1000],
  ml: ["ml", 1],
  l: ["ml", 1000],
  unit: ["unit", 1],
} as const;

// Si salió bien, el artículo sale de la cola y su fila (con la ventana) desaparece: el aviso va arriba de la página,
// con ?aviso= (como en Aprobaciones). Si no, el error se muestra en la ventana.
function done(
  error: { message?: string; code?: string } | null,
  data: unknown,
  notice: "resuelto" | "vinculado" | "descartado",
): ActionState {
  revalidatePath("/materias-primas/sin-mapear");
  revalidatePath("/materias-primas");
  revalidatePath("/listas-de-precios");
  const state = toActionState(data, error);
  if (state.status === "ok") redirect(`/materias-primas/sin-mapear?aviso=${notice}`);
  return state;
}

function invalid(fieldErrors: Record<string, string>): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors };
}

export async function resolveArticleAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("articleId"));
  if (!id.success) return { status: "bad", message: "Falta el artículo." };
  const errors: Record<string, string> = {};
  const ingredient = uuid.safeParse(formData.get("ingredient_id"));
  if (!ingredient.success) errors.ingredient_id = "Elegí la materia prima.";
  const packageUnit = z.string().min(1).max(30).safeParse(formData.get("package_unit"));
  if (!packageUnit.success) errors.package_unit = "Elegí cómo viene.";
  const units = Number(formData.get("units_per_package"));
  if (!Number.isInteger(units) || units < 1 || units > 10000)
    errors.units_per_package = "Va un número entero de 1 a 10000.";
  const content = parseDecimal(String(formData.get("content_per_unit") ?? ""));
  if (content === null || content <= 0) errors.content_per_unit = "Tiene que ser mayor que cero.";
  const unitKey = String(formData.get("content_unit") ?? "");
  const unit =
    unitKey in CONTENT_UNITS ? CONTENT_UNITS[unitKey as keyof typeof CONTENT_UNITS] : null;
  if (!unit) errors.content_unit = "Elegí la unidad.";
  const why = reason.safeParse(formData.get("reason"));
  if (!why.success) errors.reason = "Escribí el motivo (al menos 3 letras).";
  if (
    Object.keys(errors).length > 0 ||
    !ingredient.success ||
    !packageUnit.success ||
    !unit ||
    !why.success ||
    content === null
  )
    return invalid(errors);
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("resolve_article", {
    p_id: id.data,
    p_ingredient_id: ingredient.data,
    p_package_unit: packageUnit.data,
    p_units_per_package: units,
    p_content_per_unit: content * unit[1],
    p_content_unit: unit[0],
    p_details: {},
    p_reason: why.data,
  });
  return done(error, data, "resuelto");
}

export async function linkArticleAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("articleId"));
  if (!id.success) return { status: "bad", message: "Falta el artículo." };
  const product = uuid.safeParse(formData.get("purchase_product_id"));
  const why = reason.safeParse(formData.get("reason"));
  if (!product.success || !why.success)
    return invalid({
      ...(product.success ? {} : { purchase_product_id: "Elegí el producto." }),
      ...(why.success ? {} : { reason: "Escribí el motivo (al menos 3 letras)." }),
    });
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("link_article", {
    p_id: id.data,
    p_purchase_product_id: product.data,
    p_reason: why.data,
  });
  return done(error, data, "vinculado");
}

export async function discardArticleAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("articleId"));
  if (!id.success) return { status: "bad", message: "Falta el artículo." };
  const why = reason.safeParse(formData.get("reason"));
  if (!why.success) return invalid({ reason: "Escribí el motivo (al menos 3 letras)." });
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("discard_article", {
    p_id: id.data,
    p_reason: why.data,
  });
  return done(error, data, "descartado");
}

// Búsquedas del panel (con la sesión de la persona: la base decide qué ve).
export async function searchIngredientsAction(query: unknown) {
  const q = z.string().max(80).safeParse(query);
  return q.success ? searchIngredients(q.data) : [];
}

export async function supplierProductsAction(supplierId: unknown) {
  const id = uuid.safeParse(supplierId);
  if (!id.success) return [];
  return getSupplierProducts(id.data);
}
