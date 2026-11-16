"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues, schemas, supplierSheetSchema } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/server";

// Acciones de proveedores (Fase 3, ADR-0050). Cada una llama a una función de la base que valida
// purchasing.manage_suppliers, pide el motivo y deja la auditoría: la pantalla solo valida la forma y traduce la
// respuesta.
const uuid = z.string().uuid();

// Alta corta: crea el proveedor (código automático) y lleva a su ficha para completarla.
export async function createSupplierAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.supplier.safeParse(formValues(formData));
  if (!fields.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: fieldErrors(fields.error),
    };
  const supabase = await createClient();
  // El grupo donde la persona administra proveedores (hoy, uno solo). La base vuelve a controlar el permiso.
  const groups = await supabase
    .schema("core")
    .rpc("permitted_group_ids", { p_permission: "purchasing.manage_suppliers" });
  const groupId = uuid.safeParse(Array.isArray(groups.data) ? groups.data[0] : null);
  if (!groupId.success)
    return { status: "bad", message: "No tenés permiso para dar de alta proveedores." };
  const { data, error } = await supabase.schema("purchasing").rpc("create_supplier", {
    p_group_id: groupId.data,
    p_name: fields.data.name,
    p_tax_id: fields.data.tax_id ?? "",
    p_reason: fields.data.reason,
  });
  if (error || typeof data !== "string") return toActionState(null, error);
  revalidatePath("/proveedores");
  redirect(`/proveedores/${data}?aviso=creado`);
}

// La ficha entera, en una transacción (purchasing.save_supplier_sheet).
export async function saveSupplierSheetAction(
  payload: z.input<typeof supplierSheetSchema>,
): Promise<ActionState> {
  const parsed = supplierSheetSchema.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const p = parsed.data;
  const client = await createClient();
  const { data, error } = await client.schema("purchasing").rpc("save_supplier_sheet", {
    p_supplier_id: p.supplierId,
    p_expected_stamp: p.expectedStamp,
    p_changes: p.changes,
    p_reason: p.reason,
  });
  revalidatePath(`/proveedores/${p.supplierId}`);
  revalidatePath("/proveedores");
  const result = data as { result?: string; message?: string } | null;
  if (error || result?.result !== "applied") return toActionState(result, error);
  return { status: "ok", message: "Cambios guardados." };
}

export async function setSupplierActiveAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const fields = schemas.reason.safeParse(formValues(formData));
  if (!fields.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: fieldErrors(fields.error),
    };
  const id = uuid.safeParse(formData.get("supplierId"));
  if (!id.success) return { status: "bad", message: "Falta el proveedor." };
  const active = formData.get("active") === "true";
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("set_supplier_active", {
    p_id: id.data,
    p_active: active,
    p_reason: fields.data.reason,
  });
  revalidatePath(`/proveedores/${id.data}`);
  revalidatePath("/proveedores");
  const result = data as { result?: string; message?: string } | null;
  if (error || result?.result !== "applied") return toActionState(result, error);
  return {
    status: "ok",
    message: active
      ? "El proveedor volvió a estar activo."
      : "Proveedor desactivado. Su ficha y su historia quedan.",
  };
}
