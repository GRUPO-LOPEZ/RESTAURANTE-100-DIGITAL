"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { readNumber } from "@/lib/invoices";
import { getPayable, type Payable } from "@/lib/payments-data";
import { paymentSchema } from "@/lib/payments";
import { createClient } from "@/lib/supabase/server";

// Acciones de pagos (Fase 3, Prompt 6, ADR-0060). Cada una llama a una función de la base, que controla el permiso en
// el local, el saldo de cada factura, la cuenta del proveedor, el motivo y la auditoría. La pantalla solo arma los datos.

const uuid = z.string().uuid();
const reason = z.string().trim().min(3, "Escribí el motivo.").max(500, "Hasta 500 caracteres.");
const BUCKET = "purchasing-documents";
const FILE_MAX_BYTES = 3.5 * 1024 * 1024;
const CHANNEL_LABELS: Record<string, string> = {
  whatsapp: "WhatsApp",
  email: "correo",
  supplier_portal: "el sistema del proveedor",
};

// Un parámetro que la función de la base acepta nulo aunque los tipos generados lo pidan (los genera la firma, que no
// tiene default): PostgREST lo manda como NULL.
function orNull<T>(value: T | null | undefined): T {
  return (value ?? null) as T;
}

function revalidate() {
  revalidatePath("/compras/pagos");
  revalidatePath("/compras");
  revalidatePath("/compras/facturas");
  revalidatePath("/proveedores");
}

// Lo que se puede pagar de un proveedor en un local (para el panel, al elegir el proveedor).
export async function loadPayableAction(
  restaurantId: string,
  supplierId: string,
): Promise<Payable | null> {
  if (!uuid.safeParse(restaurantId).success || !uuid.safeParse(supplierId).success) return null;
  return getPayable(restaurantId, supplierId);
}

// ---------------------------------------------------------------------------
// Registrar un pago, con el comprobante si viene
// ---------------------------------------------------------------------------
export type RegisterState = ActionState & { paymentId?: string };

async function checkFile(entry: FormDataEntryValue | null): Promise<File | null | string> {
  if (!(entry instanceof File) || entry.size === 0) return null;
  if (entry.size > FILE_MAX_BYTES) return "El comprobante pesa más de 3,5 MB: probá con otro.";
  const head = new Uint8Array(await entry.slice(0, 4).arrayBuffer());
  const jpeg =
    entry.type === "image/jpeg" && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff;
  const pdf =
    entry.type === "application/pdf" && String.fromCharCode(...head.slice(0, 4)) === "%PDF";
  if (!jpeg && !pdf) return "El comprobante tiene que ser una foto (JPG) o un PDF.";
  return entry;
}

export async function registerPaymentAction(formData: FormData): Promise<RegisterState> {
  const restaurant = uuid.safeParse(formData.get("restaurantId"));
  const supplier = uuid.safeParse(formData.get("supplierId"));
  if (!restaurant.success) return { status: "bad", message: "Elegí el local arriba." };
  if (!supplier.success) return { status: "bad", message: "Elegí el proveedor." };
  const fields = paymentSchema.safeParse({
    method: formData.get("method"),
    accountId: formData.get("accountId") ?? "",
    paidOn: formData.get("paidOn"),
    amount: formData.get("amount"),
    reference: formData.get("reference") ?? "",
    reason: formData.get("reason"),
  });
  if (!fields.success)
    return { status: "bad", message: fields.error.issues[0]?.message ?? "Revisá el pago." };
  let lines: unknown;
  try {
    lines = JSON.parse(String(formData.get("allocations") ?? "[]"));
  } catch {
    return { status: "bad", message: "Las facturas a pagar no se entienden." };
  }
  const allocations = z
    .array(z.object({ invoice_id: uuid, amount: z.number().positive() }))
    .max(50)
    .safeParse(lines);
  if (!allocations.success)
    return { status: "bad", message: "Revisá lo que se paga de cada factura." };
  const file = await checkFile(formData.get("file"));
  if (typeof file === "string") return { status: "bad", message: file };
  const f = fields.data;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("register_payment", {
    p_restaurant_id: restaurant.data,
    p_supplier_id: supplier.data,
    p_paid_on: f.paidOn,
    p_method: f.method,
    p_account_id: orNull(f.method === "cash" ? null : f.accountId),
    p_amount: readNumber(f.amount) ?? 0,
    p_reference: orNull(f.reference || null),
    p_allocations: allocations.data,
    p_reason: f.reason,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const result = z
    .object({ payment_id: z.string(), unapplied: z.number(), channel: z.string().nullable() })
    .safeParse(data);
  if (!result.success) return { status: "bad", message: "No pudimos registrar el pago." };
  // El comprobante: se sube a la carpeta del pago y se registra (la base controla el permiso y el estado).
  let receiptNote = "";
  if (file instanceof File) {
    const { data: row } = await supabase
      .schema("purchasing")
      .from("payments")
      .select("group_id")
      .eq("id", result.data.payment_id)
      .maybeSingle();
    const ext = file.type === "application/pdf" ? "pdf" : "jpg";
    const path = row
      ? `${row.group_id}/payments/${result.data.payment_id}/${randomUUID()}.${ext}`
      : null;
    const uploaded = path
      ? await supabase.storage
          .from(BUCKET)
          .upload(path, file, { contentType: file.type, upsert: false })
      : null;
    const registered =
      path && uploaded && !uploaded.error
        ? await supabase.schema("purchasing").rpc("add_payment_attachment", {
            p_payment_id: result.data.payment_id,
            p_storage_path: path,
            p_page: 1,
          })
        : null;
    receiptNote =
      registered && !registered.error
        ? ""
        : " No pudimos subir el comprobante: subilo de nuevo desde el pago.";
  }
  revalidate();
  const queued = result.data.channel
    ? ` El aviso al proveedor quedó en cola para ${CHANNEL_LABELS[result.data.channel] ?? result.data.channel}.`
    : " El proveedor no tiene canal en su ficha: el aviso no se mandó.";
  const credit =
    result.data.unapplied > 0.005
      ? ` Quedaron $ ${result.data.unapplied.toLocaleString("es-AR", { minimumFractionDigits: 2 })} a cuenta.`
      : "";
  return {
    status: receiptNote ? "warn" : "ok",
    message: `Pago registrado.${queued}${credit}${receiptNote}`,
    paymentId: result.data.payment_id,
  };
}

// ---------------------------------------------------------------------------
// Confirmar el efectivo pagado al recibir
// ---------------------------------------------------------------------------
export async function confirmCashAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("paymentId"));
  const why = reason.safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta el pago." };
  if (!why.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: why.error.issues[0]?.message ?? "Escribí el motivo." },
    };
  const text = String(formData.get("amount") ?? "").trim();
  const amount = text === "" ? null : readNumber(text);
  if (text !== "" && (amount === null || amount <= 0))
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { amount: "Escribí el importe, mayor que cero." },
    };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("confirm_cash_payment", {
    p_id: id.data,
    p_amount: orNull(amount),
    p_reason: why.data,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate();
  // El aviso va en la página: la fila (y su ventana) desaparece de «Para confirmar» al confirmar.
  const left = z.object({ unapplied: z.number() }).safeParse(data);
  redirect(
    `/compras/pagos?estado=para-confirmar&aviso=${left.success && left.data.unapplied > 0.005 ? "efectivo-a-cuenta" : "efectivo-aplicado"}`,
  );
}

// ---------------------------------------------------------------------------
// Anular un pago
// ---------------------------------------------------------------------------
export async function voidPaymentAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("paymentId"));
  const why = reason.safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta el pago." };
  if (!why.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: why.error.issues[0]?.message ?? "Escribí el motivo." },
    };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("void_payment", { p_id: id.data, p_reason: why.data });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate();
  return {
    status: "ok",
    message: "Pago anulado. Las facturas que cancelaba vuelven a tener saldo.",
  };
}
