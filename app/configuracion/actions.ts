"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
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

// Los datos opcionales del local: los que vienen en el formulario, vacíos incluidos (vacío los borra).
function restaurantDetails(data: Record<string, string | undefined>) {
  const out: Record<string, string> = {};
  for (const key of ["code", "address", "locality", "phone", "opened_on", "site_type"]) {
    const value = data[key];
    if (value !== undefined) out[key] = value;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Marcas
// ---------------------------------------------------------------------------
export async function createBrandAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.brand.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  if (!group.success) return { status: "bad", message: "Falta el grupo." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("org").rpc("create_brand", {
    p_group_id: group.data,
    p_name: fields.data.name,
    p_code: fields.data.code,
    p_reason: fields.data.reason,
  });
  if (error || typeof data !== "string") return failed(error);
  revalidatePath("/configuracion/marcas");
  redirect(`/configuracion/marcas/${data}`);
}

export async function updateBrandAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.brandEdit.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("brandId"));
  if (!id.success) return { status: "bad", message: "Falta la marca." };
  const changes: Record<string, string> = { name: fields.data.name };
  if (fields.data.code !== undefined) changes.code = fields.data.code;
  if (fields.data.status !== undefined) changes.status = fields.data.status;
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("update_brand", {
    p_id: id.data,
    p_changes: changes,
    p_reason: fields.data.reason,
  });
  return done(error, "Marca guardada.", [
    "/configuracion/marcas",
    `/configuracion/marcas/${id.data}`,
  ]);
}

// ---------------------------------------------------------------------------
// Locales
// ---------------------------------------------------------------------------
export async function createRestaurantAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.restaurant.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const brand = uuid.safeParse(formData.get("brandId"));
  if (!brand.success) return { status: "bad", message: "Falta la marca." };
  const details: Record<string, string> = restaurantDetails(fields.data);
  if (fields.data.legal_entity_id) {
    const entity = uuid.safeParse(fields.data.legal_entity_id);
    if (!entity.success)
      return { status: "bad", fieldErrors: { legal_entity_id: "Elegí la razón social." } };
    details.legal_entity_id = entity.data;
  }
  const supabase = await createClient();
  const { data, error } = await supabase.schema("org").rpc("create_restaurant", {
    p_brand_id: brand.data,
    p_name: fields.data.name,
    p_details: details,
    p_reason: fields.data.reason,
  });
  if (error || typeof data !== "string") return failed(error);
  revalidatePath(`/configuracion/marcas/${brand.data}`);
  redirect(`/configuracion/locales/${data}`);
}

export async function updateRestaurantAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.restaurantEdit.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("restaurantId"));
  if (!id.success) return { status: "bad", message: "Falta el local." };
  const changes: Record<string, string> = {
    name: fields.data.name,
    ...restaurantDetails(fields.data),
  };
  if (fields.data.status !== undefined) changes.status = fields.data.status;
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("update_restaurant", {
    p_id: id.data,
    p_changes: changes,
    p_reason: fields.data.reason,
  });
  return done(error, "Local guardado.", [
    `/configuracion/locales/${id.data}`,
    "/configuracion/marcas",
  ]);
}

export async function setRestaurantLegalEntityAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.restaurantLegalEntity.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("restaurantId"));
  const entity = uuid.safeParse(fields.data.legal_entity_id);
  if (!id.success) return { status: "bad", message: "Falta el local." };
  if (!entity.success)
    return { status: "bad", fieldErrors: { legal_entity_id: "Elegí la razón social." } };
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("set_restaurant_legal_entity", {
    p_restaurant_id: id.data,
    p_legal_entity_id: entity.data,
    p_reason: fields.data.reason,
  });
  return done(
    error,
    "Razón social guardada. El costo sin IVA de este local ya se puede calcular.",
    [`/configuracion/locales/${id.data}`, "/configuracion/razones-sociales"],
  );
}

// ---------------------------------------------------------------------------
// Áreas
// ---------------------------------------------------------------------------
export async function createAreaAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.area.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("restaurantId"));
  if (!id.success) return { status: "bad", message: "Falta el local." };
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("create_area", {
    p_restaurant_id: id.data,
    p_name: fields.data.name,
    p_reason: fields.data.reason,
  });
  return done(error, "Área creada.", [`/configuracion/locales/${id.data}`]);
}

export async function renameAreaAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.area.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const area = uuid.safeParse(formData.get("areaId"));
  const restaurant = uuid.safeParse(formData.get("restaurantId"));
  if (!area.success || !restaurant.success) return { status: "bad", message: "Falta el área." };
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("update_area", {
    p_id: area.data,
    p_changes: { name: fields.data.name },
    p_reason: fields.data.reason,
  });
  return done(error, "Nombre cambiado.", [`/configuracion/locales/${restaurant.data}`]);
}

// ---------------------------------------------------------------------------
// Razones sociales
// ---------------------------------------------------------------------------
export async function createLegalEntityAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.legalEntity.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  if (!group.success) return { status: "bad", message: "Falta el grupo." };
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("create_legal_entity", {
    p_group_id: group.data,
    p_name: fields.data.name,
    p_tax_id: fields.data.tax_id,
    p_vat_condition: fields.data.vat_condition,
    p_reason: fields.data.reason,
  });
  return done(error, "Razón social creada. Ya la podés elegir en los locales.", [
    "/configuracion/razones-sociales",
  ]);
}

export async function updateLegalEntityAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.legalEntity.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("legalEntityId"));
  if (!id.success) return { status: "bad", message: "Falta la razón social." };
  const supabase = await createClient();
  const { error } = await supabase.schema("org").rpc("update_legal_entity", {
    p_id: id.data,
    p_changes: {
      name: fields.data.name,
      tax_id: fields.data.tax_id,
      vat_condition: fields.data.vat_condition,
    },
    p_reason: fields.data.reason,
  });
  return done(error, "Razón social guardada.", ["/configuracion/razones-sociales"]);
}
