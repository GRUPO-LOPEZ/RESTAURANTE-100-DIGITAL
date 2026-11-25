"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { RUBRO_DESCRIPTION_MAX, RUBRO_ICONS, isRubroClass } from "@/lib/rubros";
import { createClient } from "@/lib/supabase/server";

// Acciones de Rubros (ADR-0038). Cada una llama a una función de la base, que controla el permiso de la
// clase (compra: catalog.manage o prices.configure; sub-recetas y menú: recipes.manage_categories), pide el motivo
// y deja la auditoría.
const uuid = z.string().uuid();

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
  return done(
    null,
    created
      ? `Rubro creado con el código ${created.code}. Está en «Sin uso» hasta que se use.`
      : "Rubro creado. Está en «Sin uso» hasta que se use.",
  );
}

// La ficha entera, con motivo (ADR-0066). La base controla el permiso, las claves y que nadie la haya cambiado.
const saveSchema = z.object({
  rubroClass: z.enum(["purchase", "subrecipe", "menu"]),
  id: uuid,
  expectedStamp: z.string().min(1),
  changes: z
    .object({
      name: z.string().max(80).optional(),
      description: z.string().max(RUBRO_DESCRIPTION_MAX).nullable().optional(),
      icon: z.enum(RUBRO_ICONS).optional(),
      used_in_recipes: z.boolean().optional(),
    })
    .strict(),
  reason: z.string().trim().min(3, "Escribí el motivo de los cambios.").max(500),
});

export async function saveRubroAction(payload: z.input<typeof saveSchema>): Promise<ActionState> {
  const parsed = saveSchema.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("save_top_category", {
    p_class: parsed.data.rubroClass,
    p_id: parsed.data.id,
    p_expected_stamp: parsed.data.expectedStamp,
    p_changes: parsed.data.changes,
    p_reason: parsed.data.reason,
  });
  const state = toActionState(data, error);
  // Solo si se guardó: con un conflicto, la página no se recarga y lo escrito queda.
  if (state.status === "ok") {
    revalidatePath("/rubros");
    revalidatePath("/materias-primas", "layout");
    revalidatePath("/recetas", "layout");
  }
  return state;
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
