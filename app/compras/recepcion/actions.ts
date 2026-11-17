"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { closeSchema } from "@/lib/receipts";
import { createClient } from "@/lib/supabase/server";

// Acciones de la recepción (Fase 3, Prompt 4, ADR-0056). Cada una llama a una función de la base, que controla el
// permiso en el local, deja la auditoría y, al cerrar, vuelve a controlar las fotos, cada renglón y el motivo.

const uuid = z.string().uuid();
const BUCKET = "purchasing-documents";
// Las fotos llegan achicadas desde el navegador (JPEG, hasta 1.600 px): con 4 MB sobra.
const MAX_PHOTO_BYTES = 4 * 1024 * 1024;

function revalidate(orderId?: string | null) {
  revalidatePath("/compras/recepcion");
  revalidatePath("/compras/ordenes");
  revalidatePath("/inventario");
  if (orderId) revalidatePath(`/compras/ordenes/${orderId}`);
}

// Abrir (o retomar) la recepción de una OC y pasar a sus pasos.
export async function startReceiptAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("orderId"));
  if (!id.success) return { status: "bad", message: "Falta la orden." };
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("start_receipt", { p_order_id: id.data });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const receipt = z.object({ receipt_id: z.string() }).safeParse(data);
  if (!receipt.success) return { status: "bad", message: "No pudimos abrir la recepción." };
  revalidate(id.data);
  redirect(`/compras/recepcion/${receipt.data.receipt_id}`);
}

// «Recibir sin OC»: llegó mercadería de un proveedor sin orden.
export async function startWithoutOrderAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const supplier = uuid.safeParse(formData.get("supplierId"));
  const restaurant = uuid.safeParse(formData.get("restaurantId"));
  if (!supplier.success)
    return {
      status: "bad",
      message: "Elegí el proveedor.",
      fieldErrors: { supplierId: "Elegí el proveedor." },
    };
  if (!restaurant.success) return { status: "bad", message: "Elegí el local arriba." };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("start_receipt_without_order", {
    p_supplier_id: supplier.data,
    p_restaurant_id: restaurant.data,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const receipt = z.object({ receipt_id: z.string() }).safeParse(data);
  if (!receipt.success) return { status: "bad", message: "No pudimos abrir la recepción." };
  revalidate();
  redirect(`/compras/recepcion/${receipt.data.receipt_id}`);
}

// Una foto JPEG achicada en el navegador. Se mira el contenido, no solo lo que dice el archivo.
async function checkPhoto(entry: FormDataEntryValue | null): Promise<File | string> {
  if (!(entry instanceof File) || entry.size === 0) return "Sacá o elegí la foto.";
  if (entry.size > MAX_PHOTO_BYTES) return "La foto es muy pesada: probá de nuevo.";
  const head = new Uint8Array(await entry.slice(0, 3).arrayBuffer());
  if (entry.type !== "image/jpeg" || head[0] !== 0xff || head[1] !== 0xd8 || head[2] !== 0xff)
    return "La foto tiene que ser una imagen JPEG.";
  return entry;
}

type Client = Awaited<ReturnType<typeof createClient>>;

// Sube una foto a la carpeta de la recepción (<grupo>/receipts/<recepción>/). Storage controla que la recepción esté
// abierta y que la sesión reciba en su local.
async function upload(
  client: Client,
  receiptId: string,
  file: File,
): Promise<{ path: string } | { error: string }> {
  const { data: row } = await client
    .schema("purchasing")
    .from("receipts")
    .select("group_id")
    .eq("id", receiptId)
    .maybeSingle();
  if (!row) return { error: "No encontramos la recepción." };
  const path = `${row.group_id}/receipts/${receiptId}/${randomUUID()}.jpg`;
  const uploaded = await client.storage
    .from(BUCKET)
    .upload(path, file, { contentType: "image/jpeg", upsert: false });
  if (uploaded.error) return { error: "No pudimos subir la foto. Probá de nuevo." };
  return { path };
}

export type PhotoState = ActionState & {
  photo?: {
    id: string;
    kind: "receipt_original" | "receipt_signed";
    page: number;
    url: string | null;
  };
};

// Foto 1 (el papel como llegó) o foto 2 (firmado), con su página. Rehacer suma otra: vale la última.
export async function uploadReceiptPhotoAction(formData: FormData): Promise<PhotoState> {
  const id = uuid.safeParse(formData.get("receiptId"));
  const kind = z.enum(["receipt_original", "receipt_signed"]).safeParse(formData.get("kind"));
  const page = z.coerce
    .number()
    .int()
    .min(1)
    .max(20)
    .safeParse(formData.get("page") ?? 1);
  if (!id.success || !kind.success || !page.success)
    return { status: "bad", message: "Revisá la foto." };
  const file = await checkPhoto(formData.get("file"));
  if (typeof file === "string") return { status: "bad", message: file };
  const client = await createClient();
  const up = await upload(client, id.data, file);
  if ("error" in up) return { status: "bad", message: up.error };
  const { data, error } = await client.schema("purchasing").rpc("add_receipt_attachment", {
    p_receipt_id: id.data,
    p_storage_path: up.path,
    p_kind: kind.data,
    p_page: page.data,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const attachment = z.object({ attachment_id: z.string() }).safeParse(data);
  if (!attachment.success) return { status: "bad", message: "No pudimos guardar la foto." };
  const signed = await client.storage.from(BUCKET).createSignedUrl(up.path, 300);
  return {
    status: "ok",
    message: "Foto guardada.",
    photo: {
      id: attachment.data.attachment_id,
      kind: kind.data,
      page: page.data,
      url: signed.data?.signedUrl ?? null,
    },
  };
}

export type LinePhotoState = ActionState & { path?: string; url?: string | null };

// La foto de un producto observado: se sube a la carpeta de la recepción y se registra al cerrar, con su renglón.
export async function uploadLinePhotoAction(formData: FormData): Promise<LinePhotoState> {
  const id = uuid.safeParse(formData.get("receiptId"));
  if (!id.success) return { status: "bad", message: "Falta la recepción." };
  const file = await checkPhoto(formData.get("file"));
  if (typeof file === "string") return { status: "bad", message: file };
  const client = await createClient();
  const up = await upload(client, id.data, file);
  if ("error" in up) return { status: "bad", message: up.error };
  const signed = await client.storage.from(BUCKET).createSignedUrl(up.path, 300);
  return { status: "ok", path: up.path, url: signed.data?.signedUrl ?? null };
}

// Cerrar: todo junto, en una transacción de la base. Si sale bien, lleva a la recepción cerrada con el aviso (así el
// «Listo» sobrevive a la página que se vuelve a armar y a una recarga).
export async function closeReceiptAction(payload: unknown): Promise<ActionState> {
  const parsed = closeSchema.safeParse(payload);
  if (!parsed.success)
    return {
      status: "bad",
      message: parsed.error.issues[0]?.message ?? "Revisá la recepción.",
    };
  const p = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("close_receipt", {
    p_id: p.receipt_id,
    p_paper_kind: p.paper_kind,
    p_paper_number: p.paper_number ?? "",
    p_lines: p.lines,
    // Sin efectivo, vacío; los tipos generados no saben que la base acepta null.
    p_cash_paid_amount: p.cash_paid_amount ?? (null as unknown as number),
    p_reason: p.reason ?? "",
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const { data: row } = await supabase
    .schema("purchasing")
    .from("receipts")
    .select("purchase_order_id")
    .eq("id", p.receipt_id)
    .maybeSingle();
  revalidate(row?.purchase_order_id);
  revalidatePath(`/compras/recepcion/${p.receipt_id}`);
  redirect(`/compras/recepcion/${p.receipt_id}?aviso=cerrada`);
}
