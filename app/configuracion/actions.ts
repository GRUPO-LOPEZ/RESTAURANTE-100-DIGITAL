"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/server";

// Acciones del panel de control de la estructura (ADR-0031). Cada una llama a una función de org.*
// que controla el permiso (org.manage en el nivel que corresponde), pide el motivo y deja la
// auditoría: la pantalla solo valida la forma y traduce la respuesta.
const uuid = z.string().uuid();

function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

type DbError = { message?: string; code?: string } | null;

// Las restricciones de la base, en español y en el campo que corresponde.
const CONSTRAINTS: Record<string, { field: string; message: string }> = {
  brands_code_key: { field: "code", message: "Ya hay una marca con ese código en el grupo." },
  brands_name_key: { field: "name", message: "Ya hay una marca con ese nombre en el grupo." },
  restaurants_code_key: { field: "code", message: "Ya hay un local con ese código en el grupo." },
  restaurants_name_key: { field: "name", message: "Ya hay un local con ese nombre en esta marca." },
  areas_name_key: { field: "name", message: "Ya hay un área con ese nombre en este local." },
};

function failed(error: DbError): ActionState {
  const constraint = Object.keys(CONSTRAINTS).find((c) => error?.message?.includes(c));
  if (constraint) {
    const known = CONSTRAINTS[constraint];
    if (known)
      return {
        status: "bad",
        message: "Revisá los campos marcados.",
        fieldErrors: { [known.field]: known.message },
      };
  }
  // Los rechazos de org.require ("No tenés permiso para …") se muestran tal cual; cualquier otro, no:
  // podría traer nombres de funciones, tablas o restricciones.
  if (error?.code === "42501")
    return {
      status: "bad",
      message: error.message?.startsWith("No tenés permiso para")
        ? error.message
        : "No tenés permiso para hacer esto.",
    };
  // Los mensajes propios de la base (en español) pasan; los crudos de Postgres ("... violates ..."), no.
  if ((error?.code === "23505" || error?.code === "23514") && error.message?.includes("violates"))
    return { status: "bad", message: "Revisá los datos: alguno no es válido o ya existe." };
  return toActionState(null, error);
}

function done(error: DbError, message: string, paths: string[]): ActionState {
  if (error) return failed(error);
  for (const p of paths) revalidatePath(p);
  return { status: "ok", message };
}

// ---------------------------------------------------------------------------
// Configuración de precios (ADR-0029): prices.configure de todo el grupo (Dirección General)
// ---------------------------------------------------------------------------
export async function updatePriceSettingsAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.priceSettings.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  if (!group.success) return { status: "bad", message: "Falta el grupo." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("update_price_settings", {
    p_group_id: group.data,
    p_approval_variation_pct: Number(fields.data.approval_variation_pct.replace(",", ".")),
    p_stale_days: Number(fields.data.stale_days),
    p_lookback_days: Number(fields.data.lookback_days),
    p_reason: fields.data.reason,
  });
  return done(error, "Configuración de precios guardada.", ["/configuracion/precios"]);
}

// El umbral del aviso de rendimiento (ADR-0035): va en la misma configuración del grupo. Se manda solo el umbral: la
// base deja el resto como está, así no pisa lo que otra persona guardó al mismo tiempo.
export async function updateYieldAlertAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.yieldAlert.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  if (!group.success) return { status: "bad", message: "Falta el grupo." };
  const supabase = await createClient();
  const { error } = await supabase.schema("costing").rpc("update_yield_alert", {
    p_group_id: group.data,
    p_yield_alert_pct: Number(fields.data.yield_alert_pct.replace(",", ".")),
    p_reason: fields.data.reason,
  });
  return done(error, "Aviso de rendimiento guardado.", ["/configuracion/precios"]);
}

export async function setCategoryStaleDaysAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.categoryStaleDays.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const category = uuid.safeParse(formData.get("categoryId"));
  if (!category.success) return { status: "bad", message: "Falta la categoría." };
  const supabase = await createClient();
  const { error } = await supabase.schema("catalog").rpc("set_category_stale_days", {
    p_category_id: category.data,
    // Vacío: vale el plazo del grupo. La función acepta null; el tipo generado no lo refleja.
    p_days: (fields.data.stale_price_days ? Number(fields.data.stale_price_days) : null) as number,
    p_reason: fields.data.reason,
  });
  return done(error, "Días guardados.", ["/configuracion/precios"]);
}
