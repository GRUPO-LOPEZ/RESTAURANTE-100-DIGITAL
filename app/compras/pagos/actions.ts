"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { readNumber } from "@/lib/invoices";
import { getPayable, type Payable } from "@/lib/payments-data";
import { paymentOrderSchema } from "@/lib/payment-orders";
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
    // Si se subió pero no se pudo registrar (por ejemplo, anularon el pago en el medio), no queda suelto en Storage.
    if (path && uploaded && !uploaded.error && (!registered || registered.error)) {
      await supabase.storage.from(BUCKET).remove([path]);
    }
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
// Registrar una orden de pago (ADR-0070): de 1 a 5 medios, lo que cancela de cada factura y el comprobante
// ---------------------------------------------------------------------------
export type PaymentOrderState = ActionState & { paymentOrderId?: string };

const orderLine = z
  .object({
    method: z.enum(["cash", "transfer", "check", "echeq", "card"]),
    amount: z.number().positive(),
    company_account_id: uuid.optional(),
    supplier_account_id: uuid.optional(),
    reference: z.string().max(80).optional(),
    check_number: z.string().max(30).optional(),
    check_bank: z.string().max(80).optional(),
    check_due_on: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/)
      .optional(),
    check_third_party: z.boolean().optional(),
    check_drawer_name: z.string().max(120).optional(),
    check_drawer_tax_id: z.string().max(11).optional(),
  })
  .strict();

export async function registerPaymentOrderAction(formData: FormData): Promise<PaymentOrderState> {
  const restaurant = uuid.safeParse(formData.get("restaurantId"));
  const supplier = uuid.safeParse(formData.get("supplierId"));
  if (!restaurant.success) return { status: "bad", message: "Elegí el local arriba." };
  if (!supplier.success) return { status: "bad", message: "Elegí el proveedor." };
  const fields = paymentOrderSchema.safeParse({
    paidOn: formData.get("paidOn"),
    notes: formData.get("notes") ?? "",
    reason: formData.get("reason"),
  });
  if (!fields.success)
    return { status: "bad", message: fields.error.issues[0]?.message ?? "Revisá el pago." };
  let rawLines: unknown;
  let rawAllocations: unknown;
  try {
    rawLines = JSON.parse(String(formData.get("lines") ?? "[]"));
    rawAllocations = JSON.parse(String(formData.get("allocations") ?? "[]"));
  } catch {
    return { status: "bad", message: "El pago no se entiende: recargá la página." };
  }
  const lines = z.array(orderLine).min(1).max(5).safeParse(rawLines);
  if (!lines.success) return { status: "bad", message: "Revisá los medios de pago." };
  const allocations = z
    .array(z.object({ invoice_id: uuid, amount: z.number().positive() }))
    .max(50)
    .safeParse(rawAllocations);
  if (!allocations.success)
    return { status: "bad", message: "Revisá lo que se cancela de cada factura." };
  const file = await checkFile(formData.get("file"));
  if (typeof file === "string") return { status: "bad", message: file };
  const legalEntity = uuid.safeParse(formData.get("legalEntityId"));
  const f = fields.data;
  const db = await createClient();
  const { data, error } = await db.schema("purchasing").rpc("register_payment_order", {
    p_restaurant_id: restaurant.data,
    p_supplier_id: supplier.data,
    p_paid_on: f.paidOn,
    p_legal_entity_id: orNull(legalEntity.success ? legalEntity.data : null),
    p_lines: lines.data,
    p_allocations: allocations.data,
    p_notes: orNull(f.notes || null),
    p_reason: f.reason,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const result = z.object({ payment_order_id: z.string(), number: z.string() }).safeParse(data);
  if (!result.success) return { status: "bad", message: "No pudimos registrar la orden de pago." };
  // El comprobante va con el primer medio de la orden (la base controla el permiso y el estado).
  if (file instanceof File) {
    const { data: first } = await db
      .schema("purchasing")
      .from("payments")
      .select("id, group_id")
      .eq("payment_order_id", result.data.payment_order_id)
      .order("created_at")
      .limit(1)
      .maybeSingle();
    const note = first ? await attachReceipt(first.id, first.group_id, file) : "x";
    if (note) {
      revalidate();
      redirect(
        `/compras/pagos/ordenes/${result.data.payment_order_id}?aviso=registrada-sin-comprobante`,
      );
    }
  }
  revalidate();
  redirect(`/compras/pagos/ordenes/${result.data.payment_order_id}?aviso=registrada`);
}

// Sube un comprobante a la carpeta de un pago y lo registra; si no se pudo registrar, no queda suelto. Devuelve "" si
// salió bien.
async function attachReceipt(paymentId: string, groupId: string, file: File): Promise<string> {
  const db = await createClient();
  const ext = file.type === "application/pdf" ? "pdf" : "jpg";
  const path = `${groupId}/payments/${paymentId}/${randomUUID()}.${ext}`;
  const uploaded = await db.storage
    .from(BUCKET)
    .upload(path, file, { contentType: file.type, upsert: false });
  if (uploaded.error) return "No pudimos subir el comprobante.";
  const registered = await db.schema("purchasing").rpc("add_payment_attachment", {
    p_payment_id: paymentId,
    p_storage_path: path,
    p_page: 1,
  });
  if (registered.error) {
    await db.storage.from(BUCKET).remove([path]);
    return "No pudimos registrar el comprobante.";
  }
  return "";
}

// Anular una orden de pago (con motivo).
export async function voidPaymentOrderAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("paymentOrderId"));
  const why = reason.safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta la orden de pago." };
  if (!why.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: why.error.issues[0]?.message ?? "Escribí el motivo." },
    };
  const db = await createClient();
  const { data, error } = await db
    .schema("purchasing")
    .rpc("void_payment_order", { p_id: id.data, p_reason: why.data });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate();
  redirect(`/compras/pagos/ordenes/${id.data}?aviso=anulada`);
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
