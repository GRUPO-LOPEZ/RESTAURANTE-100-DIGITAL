"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { fieldErrors, formValues } from "@/lib/forms/schemas";
import { isFiscal, newInvoiceSchema, noteSchema, readNumber } from "@/lib/invoices";
import { createClient } from "@/lib/supabase/server";

// Acciones de facturas (Fase 3, Prompt 5B, ADR-0058). Cada una llama a una función de la base, que controla el permiso
// en el local, la regla de «otra persona», el motivo y la auditoría. La pantalla solo arma los datos.

const uuid = z.string().uuid();
const reason = z
  .string()
  .trim()
  .min(3, "Escribí el motivo (al menos 3 letras).")
  .max(500, "Hasta 500 caracteres.");
const BUCKET = "purchasing-documents";
// La foto llega achicada desde el navegador (JPEG); el PDF, como está. Entra en el tope de la acción (4 MB).
const FILE_MAX_BYTES = 3.5 * 1024 * 1024;

function revalidate(invoiceId?: string) {
  revalidatePath("/compras/facturas");
  if (invoiceId) revalidatePath(`/compras/facturas/${invoiceId}`);
}

// ---------------------------------------------------------------------------
// Alta
// ---------------------------------------------------------------------------
export async function createInvoiceAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const restaurant = uuid.safeParse(formData.get("restaurantId"));
  if (!restaurant.success) return { status: "bad", message: "Elegí el local arriba." };
  const fields = newInvoiceSchema.safeParse(formValues(formData));
  if (!fields.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: fieldErrors(fields.error),
    };
  const orderIds = formData.getAll("orderId").filter((v): v is string => typeof v === "string");
  if (!orderIds.every((o) => uuid.safeParse(o).success))
    return { status: "bad", message: "Revisá las órdenes elegidas." };
  const f = fields.data;
  const supabase = await createClient();
  // El CUIT del emisor es el del proveedor (la base lo vuelve a controlar).
  const { data: supplier } = await supabase
    .schema("catalog")
    .from("suppliers")
    .select("tax_id")
    .eq("id", f.supplierId)
    .maybeSingle();
  const fiscal = isFiscal(f.invoice_class);
  if (fiscal && !supplier?.tax_id)
    return {
      status: "bad",
      message:
        "El proveedor no tiene CUIT: cargalo en su ficha antes de cargar una factura fiscal.",
      fieldErrors: { supplierId: "Sin CUIT en su ficha." },
    };
  const { data, error } = await supabase.schema("purchasing").rpc("create_invoice", {
    p_supplier_id: f.supplierId,
    p_restaurant_id: restaurant.data,
    p_order_ids: orderIds,
    p_header: {
      invoice_class: f.invoice_class,
      point_of_sale: fiscal ? Number(f.point_of_sale) : null,
      number: Number(f.number),
      issued_on: f.issued_on,
      authorization_kind: fiscal ? f.authorization_kind : null,
      authorization_code: fiscal ? f.authorization_code : null,
      issuer_tax_id: fiscal ? supplier?.tax_id : null,
    },
    p_reason: "Factura cargada",
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const created = z.object({ invoice_id: z.string() }).safeParse(data);
  if (!created.success) return { status: "bad", message: "No pudimos cargar la factura." };
  revalidate();
  redirect(`/compras/facturas/${created.data.invoice_id}?aviso=creada`);
}

// ---------------------------------------------------------------------------
// Guardar la ficha, en lote y con motivo
// ---------------------------------------------------------------------------
const cell = z.union([z.string(), z.number(), z.boolean(), z.null()]);
const saveSchema = z.object({
  invoiceId: uuid,
  reason,
  header: z.record(z.string(), cell),
  lines: z.array(z.record(z.string(), cell)).max(600).nullable(),
  taxes: z.array(z.record(z.string(), cell)).max(50).nullable(),
});

export async function saveInvoiceAction(payload: z.input<typeof saveSchema>): Promise<ActionState> {
  const parsed = saveSchema.safeParse(payload);
  if (!parsed.success)
    return { status: "bad", message: parsed.error.issues[0]?.message ?? "Revisá los datos." };
  const p = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("save_invoice", {
    p_id: p.invoiceId,
    p_header: p.header,
    // null: esa lista no cambia (la base la deja como está).
    p_lines: p.lines,
    p_taxes: p.taxes,
    p_reason: p.reason,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate(p.invoiceId);
  const news = z.object({ new_unmapped: z.number() }).safeParse(data);
  const unmapped = news.success ? news.data.new_unmapped : 0;
  return {
    status: "ok",
    message:
      unmapped > 0
        ? `Cambios guardados. ${unmapped === 1 ? "Un artículo nuevo fue" : `${unmapped} artículos nuevos fueron`} a la lista del chef para mapear.`
        : "Cambios guardados. Controlala de nuevo.",
  };
}

// ---------------------------------------------------------------------------
// Controlar, dar por conforme y cancelar
// ---------------------------------------------------------------------------
const STATUS_MESSAGES: Record<string, ActionState> = {
  released: {
    status: "ok",
    message: "Quedó conforme y liberada a pago. Su precio pasa a ser el costo.",
  },
  observed: { status: "warn", message: "Quedó observada: mirá qué no pasó en «Controles»." },
};

export async function runInvoiceChecksAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("invoiceId"));
  if (!id.success) return { status: "bad", message: "Falta la factura." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("run_invoice_checks", { p_id: id.data });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate(id.data);
  const status = z.object({ status: z.string() }).safeParse(data);
  // Vuelve a la ficha con el resultado en la barra de abajo.
  if (status.success && (status.data.status === "released" || status.data.status === "observed"))
    redirect(
      `/compras/facturas/${id.data}?aviso=${status.data.status === "released" ? "conforme" : "observada"}`,
    );
  return state;
}

export async function approveInvoiceAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("invoiceId"));
  const version = z.string().min(10).safeParse(formData.get("version"));
  const why = reason.safeParse(formData.get("reason"));
  if (!id.success || !version.success) return { status: "bad", message: "Falta la factura." };
  if (!why.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: why.error.issues[0]?.message ?? "Escribí el motivo." },
    };
  const supabase = await createClient();
  // La versión que se miró: si la factura cambió mientras tanto, la base no la aprueba.
  const { data, error } = await supabase.schema("purchasing").rpc("approve_invoice", {
    p_id: id.data,
    p_reason: why.data,
    p_version: version.data,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate(id.data);
  redirect(`/compras/facturas/${id.data}?aviso=conforme`);
}

export async function cancelInvoiceAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("invoiceId"));
  const why = reason.safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta la factura." };
  if (!why.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: why.error.issues[0]?.message ?? "Escribí el motivo." },
    };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("cancel_invoice", { p_id: id.data, p_reason: why.data });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate(id.data);
  redirect(`/compras/facturas/${id.data}?aviso=cancelada`);
}

// ---------------------------------------------------------------------------
// Notas de crédito, débito y descuentos
// ---------------------------------------------------------------------------
export async function addNoteAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const invoice = uuid.safeParse(formData.get("invoiceId"));
  if (!invoice.success) return { status: "bad", message: "Falta la factura." };
  const fields = noteSchema.safeParse(formValues(formData));
  if (!fields.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: fieldErrors(fields.error),
    };
  const f = fields.data;
  const net = readNumber(f.net_amount);
  const total = f.total_amount === "" ? net : readNumber(f.total_amount);
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("add_credit_debit_note", {
    p_invoice_id: invoice.data,
    p_note: {
      note_kind: f.note_kind,
      number: f.number || null,
      issued_on: f.issued_on,
      net_amount: net,
      total_amount: total,
    },
    p_reason: f.reason,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate(invoice.data);
  return {
    status: "ok",
    message: "Nota guardada. Subí su foto: cuenta para el control recién con la foto.",
  };
}

// ---------------------------------------------------------------------------
// Foto o PDF de la factura o de una nota
// ---------------------------------------------------------------------------
async function checkFile(entry: FormDataEntryValue | null): Promise<File | string> {
  if (!(entry instanceof File) || entry.size === 0) return "Elegí la foto o el PDF.";
  if (entry.size > FILE_MAX_BYTES) return "El archivo pesa más de 3,5 MB: probá con otro.";
  const head = new Uint8Array(await entry.slice(0, 4).arrayBuffer());
  const jpeg =
    entry.type === "image/jpeg" && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff;
  const pdf =
    entry.type === "application/pdf" && String.fromCharCode(...head.slice(0, 4)) === "%PDF";
  if (!jpeg && !pdf) return "Tiene que ser una foto (JPG) o un PDF.";
  return entry;
}

// Lo que vuelve de subir un archivo: además del mensaje, qué aviso mostrar en la barra de la ficha.
export type UploadState = ActionState & { notice?: "archivo" | "nota-observada" | "nota-conforme" };

export async function uploadInvoiceFileAction(
  _prev: ActionState,
  formData: FormData,
): Promise<UploadState> {
  const table = z.enum(["invoices", "credit_debit_notes"]).safeParse(formData.get("sourceTable"));
  const sourceId = uuid.safeParse(formData.get("sourceId"));
  const invoiceId = uuid.safeParse(formData.get("invoiceId"));
  if (!table.success || !sourceId.success || !invoiceId.success)
    return { status: "bad", message: "Falta la factura." };
  const file = await checkFile(formData.get("file"));
  if (typeof file === "string") return { status: "bad", message: file, fieldErrors: { file } };
  const supabase = await createClient();
  const { data: row } = await supabase
    .schema("purchasing")
    .from("invoices")
    .select("group_id")
    .eq("id", invoiceId.data)
    .maybeSingle();
  if (!row) return { status: "bad", message: "No encontramos la factura." };
  const ext = file.type === "application/pdf" ? "pdf" : "jpg";
  const path = `${row.group_id}/${table.data}/${sourceId.data}/${randomUUID()}.${ext}`;
  // Storage controla que la sesión cargue facturas en ese local y que la factura todavía se pueda cambiar.
  const uploaded = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { contentType: file.type, upsert: false });
  if (uploaded.error)
    return { status: "bad", message: "No pudimos subir el archivo. Probá de nuevo." };
  const { data, error } = await supabase.schema("purchasing").rpc("add_invoice_attachment", {
    p_source_table: table.data,
    p_source_id: sourceId.data,
    p_storage_path: path,
    p_page: 1,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate(invoiceId.data);
  // El aviso va en la barra de la ficha (?aviso=): el botón de subir desaparece cuando la nota ya tiene su foto, y con
  // él se iría un mensaje que viviera a su lado.
  const status = z.object({ status: z.string() }).safeParse(data);
  if (status.success && STATUS_MESSAGES[status.data.status]) {
    const after = STATUS_MESSAGES[status.data.status];
    return {
      status: after?.status,
      message: `Foto guardada. Se volvió a controlar: ${after?.message?.toLowerCase()}`,
      notice: status.data.status === "released" ? "nota-conforme" : "nota-observada",
    };
  }
  return { status: "ok", message: "Archivo guardado.", notice: "archivo" };
}
