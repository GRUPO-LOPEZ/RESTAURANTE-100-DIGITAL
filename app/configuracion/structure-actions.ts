"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { getMenus, requireOperable } from "@/lib/auth/session";
import {
  fieldErrors,
  formValues,
  legalEntitySheetSchema,
  placeSheetSchema,
  schemas,
} from "@/lib/forms/schemas";
import { findAddress, type GeorefResult } from "@/lib/georef";
import { createClient } from "@/lib/supabase/server";

// Acciones del Panel de control en una pantalla (Tanda 1 de Soy, ADR-0061). Cada una llama a una función de org.* que
// controla el permiso (org.manage en el nivel que corresponde), pide el motivo y deja la auditoría: la pantalla solo
// valida la forma y traduce la respuesta.
const uuid = z.string().uuid();

type DbError = { message?: string; code?: string } | null;

function invalid(error: z.ZodError): ActionState {
  return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: fieldErrors(error) };
}

// Los «No tenés permiso para …» de org.require se muestran tal cual; lo demás, como siempre (los mensajes propios de
// la base en español pasan; los crudos, no).
function failed(error: DbError): ActionState {
  if (error?.code === "42501" && error.message?.startsWith("No tenés permiso para"))
    return { status: "bad", message: error.message };
  return toActionState(null, error);
}

const PANEL = "/configuracion";

// ---------------------------------------------------------------------------
// Marcas
// ---------------------------------------------------------------------------
export async function createBrandAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.brandNew.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const group = uuid.safeParse(formData.get("groupId"));
  if (!group.success) return { status: "bad", message: "Falta el grupo." };
  const client = await createClient();
  const { error } = await client.schema("org").rpc("create_brand", {
    p_group_id: group.data,
    p_name: fields.data.name,
    p_short_name: fields.data.short_name,
    p_code_word: fields.data.code_word ?? "",
    p_reason: fields.data.reason,
  });
  if (error) return failed(error);
  revalidatePath(PANEL);
  return { status: "ok", message: "Marca creada." };
}

export async function updateBrandAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.brandUpdate.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("brandId"));
  if (!id.success) return { status: "bad", message: "Falta la marca." };
  const changes: Record<string, string> = {
    name: fields.data.name,
    short_name: fields.data.short_name,
  };
  if (fields.data.status !== undefined) changes.status = fields.data.status;
  const client = await createClient();
  const { error } = await client.schema("org").rpc("update_brand", {
    p_id: id.data,
    p_changes: changes,
    p_reason: fields.data.reason,
  });
  if (error) return failed(error);
  revalidatePath(PANEL);
  return { status: "ok", message: "Marca guardada." };
}

// La vista previa del código de una marca nueva (04-SUSHI), sin consumir el número.
export async function peekBrandCodeAction(groupId: string, word: string): Promise<string | null> {
  const group = uuid.safeParse(groupId);
  if (!group.success) return null;
  const client = await createClient();
  const { data, error } = await client
    .schema("org")
    .rpc("peek_brand_code", { p_group_id: group.data, p_word: word.slice(0, 40) });
  return error || typeof data !== "string" ? null : data;
}

// ---------------------------------------------------------------------------
// Locales
// ---------------------------------------------------------------------------
export async function createPlaceAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.placeNew.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const brand = uuid.safeParse(fields.data.brand_id);
  if (!brand.success)
    return {
      status: "bad",
      fieldErrors: { brand_id: "Elegí la marca." },
      message: "Elegí la marca.",
    };
  const client = await createClient();
  const { data, error } = await client.schema("org").rpc("create_restaurant", {
    p_brand_id: brand.data,
    p_zone: fields.data.zone,
    p_site_type: fields.data.site_type,
    p_reason: fields.data.reason,
  });
  if (error || typeof data !== "string") return failed(error);
  revalidatePath(PANEL);
  redirect(`/configuracion/locales/${data}?aviso=creado`);
}

// La vista previa del nombre y el código de un local nuevo (Ragú Belgrano · RAGU-002).
export async function peekPlaceAction(
  brandId: string,
  zone: string,
): Promise<{ name: string | null; code: string } | null> {
  const brand = uuid.safeParse(brandId);
  if (!brand.success) return null;
  const client = await createClient();
  const { data, error } = await client
    .schema("org")
    .rpc("peek_restaurant", { p_brand_id: brand.data, p_zone: zone.slice(0, 80) });
  const parsed = z.object({ name: z.string().nullable(), code: z.string() }).safeParse(data);
  return error || !parsed.success ? null : parsed.data;
}

// La ficha entera del local, en una transacción (org.save_restaurant_sheet).
export async function savePlaceSheetAction(
  payload: z.input<typeof placeSheetSchema>,
): Promise<ActionState & { stamp?: string }> {
  const parsed = placeSheetSchema.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const p = parsed.data;
  const client = await createClient();
  const { data, error } = await client.schema("org").rpc("save_restaurant_sheet", {
    p_id: p.placeId,
    p_expected_stamp: p.expectedStamp,
    p_changes: p.changes,
    p_reason: p.reason,
  });
  if (error) return failed(error);
  revalidatePath(PANEL);
  revalidatePath(`/configuracion/locales/${p.placeId}`);
  const stamp = z.object({ stamp: z.string() }).safeParse(data);
  return {
    status: "ok",
    message: "Cambios guardados.",
    stamp: stamp.success ? stamp.data.stamp : undefined,
  };
}

// Cerrar y reabrir el local: aparte de la ficha, con su motivo (como «Desactivar» del proveedor).
export async function setPlaceOpenAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success) return invalid(fields.error);
  const id = uuid.safeParse(formData.get("placeId"));
  const open = z.enum(["close", "reopen"]).safeParse(formData.get("action"));
  if (!id.success || !open.success) return { status: "bad", message: "Falta el local." };
  const client = await createClient();
  const { error } = await client
    .schema("org")
    .rpc(open.data === "close" ? "close_restaurant" : "reopen_restaurant", {
      p_id: id.data,
      p_reason: fields.data.reason,
    });
  if (error) return failed(error);
  revalidatePath(PANEL);
  revalidatePath(`/configuracion/locales/${id.data}`);
  return { status: "ok", message: open.data === "close" ? "Local cerrado." : "Local reabierto." };
}

// Buscar la dirección en Georef. Solo quien administra algún local (org.manage) y solo al tocar «Buscar».
export async function findAddressAction(input: {
  address: string;
  locality: string;
  province: string;
}): Promise<GeorefResult> {
  await requireOperable();
  const menus = await getMenus();
  if (!menus.orgManage) return { status: "unavailable" };
  const address = z.string().trim().min(3).max(200).safeParse(input.address);
  if (!address.success) return { status: "not_found" };
  return findAddress({
    address: address.data,
    locality: input.locality.slice(0, 120),
    provinceCode: /^[0-9]{2}$/.test(input.province) ? input.province : undefined,
  });
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
  const client = await createClient();
  const { data, error } = await client.schema("org").rpc("create_legal_entity", {
    p_group_id: group.data,
    p_name: fields.data.name,
    p_tax_id: fields.data.tax_id,
    p_vat_condition: fields.data.vat_condition,
    p_reason: fields.data.reason,
  });
  if (error || typeof data !== "string") return failed(error);
  revalidatePath(PANEL);
  redirect(`/configuracion/razones-sociales/${data}?aviso=creada`);
}

export async function saveLegalEntitySheetAction(
  payload: z.input<typeof legalEntitySheetSchema>,
): Promise<ActionState & { stamp?: string }> {
  const parsed = legalEntitySheetSchema.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const p = parsed.data;
  const client = await createClient();
  const { data, error } = await client.schema("org").rpc("save_legal_entity_sheet", {
    p_id: p.legalEntityId,
    p_expected_stamp: p.expectedStamp,
    p_changes: p.changes,
    p_reason: p.reason,
  });
  if (error) return failed(error);
  revalidatePath(PANEL);
  revalidatePath(`/configuracion/razones-sociales/${p.legalEntityId}`);
  const stamp = z.object({ stamp: z.string() }).safeParse(data);
  return {
    status: "ok",
    message: "Cambios guardados.",
    stamp: stamp.success ? stamp.data.stamp : undefined,
  };
}

// La constancia de ARCA en PDF: se sube con la sesión de la persona (Storage controla org.manage del grupo) y después
// se registra con su fecha de emisión.
const BUCKET = "org-documents";
const PDF_MAX_BYTES = 3.5 * 1024 * 1024;

export async function uploadConstanciaAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("legalEntityId"));
  if (!id.success) return { status: "bad", message: "Falta la razón social." };
  const issued = z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .safeParse(formData.get("issued_on"));
  if (!issued.success)
    return {
      status: "bad",
      message: "Escribí la fecha de emisión de la constancia.",
      fieldErrors: { issued_on: "Escribí la fecha de emisión." },
    };
  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0)
    return { status: "bad", message: "Elegí el PDF.", fieldErrors: { file: "Elegí el PDF." } };
  if (file.size > PDF_MAX_BYTES)
    return {
      status: "bad",
      message: "El PDF pesa más de 3,5 MB.",
      fieldErrors: { file: "Pesa más de 3,5 MB." },
    };
  const head = new Uint8Array(await file.slice(0, 4).arrayBuffer());
  if (file.type !== "application/pdf" || String.fromCharCode(...head) !== "%PDF")
    return {
      status: "bad",
      message: "Tiene que ser un PDF.",
      fieldErrors: { file: "Tiene que ser un PDF." },
    };
  const client = await createClient();
  const { data: entity } = await client
    .schema("org")
    .from("legal_entities")
    .select("group_id")
    .eq("id", id.data)
    .maybeSingle();
  if (!entity) return { status: "bad", message: "No encontramos la razón social." };
  const path = `${entity.group_id}/legal_entities/${id.data}/${randomUUID()}.pdf`;
  const uploaded = await client.storage
    .from(BUCKET)
    .upload(path, file, { contentType: "application/pdf", upsert: false });
  if (uploaded.error)
    return {
      status: "bad",
      message: "No pudimos subir el PDF. Revisá que puedas editar esta razón social.",
    };
  const { error } = await client.schema("org").rpc("add_legal_entity_document", {
    p_legal_entity_id: id.data,
    p_storage_path: path,
    p_issued_on: issued.data,
  });
  if (error) return failed(error);
  revalidatePath(PANEL);
  revalidatePath(`/configuracion/razones-sociales/${id.data}`);
  return { status: "ok", message: "Constancia guardada." };
}

// ---------------------------------------------------------------------------
// Cajas y cuentas de la razón social (ADR-0070): en lote y con motivo, en una transacción
// (org.save_legal_entity_accounts). Las carga quien administra el grupo (lo decide la base).
// ---------------------------------------------------------------------------
const accountChange = z
  .object({
    id: uuid.optional(),
    remove: z.boolean().optional(),
    kind: z.enum(["cash", "bank", "card"]).optional(),
    name: z.string().trim().max(80).optional(),
    bank: z.string().trim().max(80).optional(),
    account_number: z.string().trim().max(40).optional(),
    cbu: z.string().trim().max(30).optional(),
    alias: z.string().trim().max(20).optional(),
    card_last4: z.string().trim().max(4).optional(),
    is_active: z.boolean().optional(),
  })
  .strict();
const accountsPayload = z.object({
  legalEntityId: uuid,
  reason: z.string().trim().min(3, "Escribí el motivo de los cambios.").max(500),
  changes: z.array(accountChange).min(1, "No hay cambios para guardar.").max(30),
});

export async function saveLegalEntityAccountsAction(
  payload: z.input<typeof accountsPayload>,
): Promise<ActionState> {
  const parsed = accountsPayload.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const p = parsed.data;
  const client = await createClient();
  const { data, error } = await client.schema("org").rpc("save_legal_entity_accounts", {
    p_legal_entity_id: p.legalEntityId,
    p_changes: p.changes,
    p_reason: p.reason,
  });
  if (error) return failed(error);
  const state = toActionState(data, null);
  if (state.status !== "ok") return state;
  revalidatePath(`/configuracion/razones-sociales/${p.legalEntityId}`);
  return { status: "ok", message: "Cajas y cuentas guardadas." };
}
