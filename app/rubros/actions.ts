"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { isRubroClass } from "@/lib/rubros";
import { createClient } from "@/lib/supabase/server";

// Acciones de Rubros (ADR-0038). Cada una llama a una función de la base, que controla el permiso de la
// clase (compra: catalog.manage o prices.configure; sub-recetas y menú: recipes.manage_categories), pide el motivo
// y deja la auditoría.
const uuid = z.string().uuid();

// Motivo fijo del cambio de nombre en la tarjeta (decisión del plan aprobado): la auditoría guarda quién y cuándo.
const RENAME_REASON = "Cambio de nombre desde Rubros";

function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

function rubroClass(formData: FormData) {
  const value = formData.get("rubroClass");
  return isRubroClass(value) ? value : null;
}

function done(error: { message?: string; code?: string } | null, message: string): ActionState {
  // Los rubros se eligen al cargar materias primas y recetas: esas pantallas también cambian.
  revalidatePath("/rubros");
  revalidatePath("/materias-primas", "layout");
  revalidatePath("/recetas", "layout");
  return error ? toActionState(null, error) : { status: "ok", message };
}

export async function createRubroAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.rubro.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const groupId = uuid.safeParse(formData.get("groupId"));
  const cls = rubroClass(formData);
  if (!groupId.success || !cls) return { status: "bad", message: "Falta el grupo o la clase." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("create_top_category", {
    p_group_id: groupId.data,
    p_class: cls,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  if (error) return done(error, "");
  // El código lo genera la base: se lee para decirlo.
  const { data: created } = await supabase
    .schema("recipes")
    .from("top_categories")
    .select("code")
    .eq("id", data)
    .maybeSingle();
  return done(null, created ? `Rubro creado con el código ${created.code}.` : "Rubro creado.");
}

export async function renameRubroAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.rubroName.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("rubroId"));
  const cls = rubroClass(formData);
  if (!id.success || !cls) return { status: "bad", message: "Falta el rubro." };
  const supabase = await createClient();
  const { error } = await supabase.schema("recipes").rpc("rename_top_category", {
    p_class: cls,
    p_id: id.data,
    p_name: fields.data.name,
    p_reason: RENAME_REASON,
  });
  return done(error, "Nombre cambiado.");
}

export async function deactivateRubroAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.rubroDeactivate.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("rubroId"));
  const cls = rubroClass(formData);
  if (!id.success || !cls) return { status: "bad", message: "Falta el rubro." };
  const target = fields.data.target_id ? uuid.safeParse(fields.data.target_id) : null;
  if (target && !target.success)
    return { status: "bad", fieldErrors: { target_id: "Elegí el rubro destino." } };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("deactivate_top_category", {
    p_class: cls,
    p_id: id.data,
    p_reason: fields.data.reason,
    ...(target ? { p_target_id: target.data } : {}),
  });
  const moved = typeof data === "number" && data > 0 ? ` Se pasaron ${data} al rubro destino.` : "";
  return done(error, `Rubro dado de baja.${moved}`);
}

export async function reactivateRubroAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("rubroId"));
  const cls = rubroClass(formData);
  if (!id.success || !cls) return { status: "bad", message: "Falta el rubro." };
  const supabase = await createClient();
  const { error } = await supabase.schema("recipes").rpc("reactivate_top_category", {
    p_class: cls,
    p_id: id.data,
    p_reason: fields.data.reason,
  });
  return done(error, "Rubro activo otra vez.");
}
