"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { priceListSchema } from "@/lib/price-lists";
import { createClient } from "@/lib/supabase/server";

// Acciones de listas de precios (Fase 3, ADR-0052). Cada una llama a una función de la base, que controla el permiso
// (purchasing.manage_price_lists para todo el grupo), pide el motivo y deja la auditoría. Los precios de lista nunca
// tocan los costos.

const uuid = z.string().uuid();

function revalidate(supplierId?: string) {
  revalidatePath("/listas-de-precios");
  revalidatePath("/materias-primas/sin-mapear");
  if (supplierId) revalidatePath(`/proveedores/${supplierId}`);
}

export type CreatePriceListState = ActionState & { priceListId?: string };

// El archivo de la lista (opcional): foto o PDF. Viaja por la acción de servidor, que acepta hasta 4 MB por envío
// (next.config.ts); el bucket acepta hasta 10 MB para cuando se suba directo desde el navegador.
const FILE_MAX_BYTES = 3.5 * 1024 * 1024;
const FILE_TYPES = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "application/pdf": "pdf",
} as const;
type FileType = keyof typeof FILE_TYPES;

// El contenido real tiene que ser lo que dice ser (no solo el tipo que declara el navegador).
function matchesType(head: Uint8Array, type: FileType): boolean {
  const ascii = (from: number, to: number) => String.fromCharCode(...head.slice(from, to));
  if (type === "image/jpeg") return head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff;
  if (type === "image/png") return head[0] === 0x89 && ascii(1, 4) === "PNG";
  if (type === "application/pdf") return ascii(0, 4) === "%PDF";
  return ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP";
}

async function checkFile(file: FormDataEntryValue | null): Promise<File | null | string> {
  if (!(file instanceof File) || file.size === 0) return null;
  const type = file.type as FileType;
  if (!(type in FILE_TYPES)) return "El archivo tiene que ser una foto (JPG, PNG o WebP) o un PDF.";
  if (file.size > FILE_MAX_BYTES)
    return "El archivo pesa más de 3,5 MB. Probá con una foto más liviana.";
  if (!matchesType(new Uint8Array(await file.slice(0, 12).arrayBuffer()), type))
    return "El archivo no es lo que dice ser: probá con otro.";
  return file;
}

// La grilla viaja como JSON (un renglón por artículo); se valida con el mismo esquema que en el navegador.
export async function createPriceListAction(
  _prev: CreatePriceListState,
  formData: FormData,
): Promise<CreatePriceListState> {
  let items: unknown;
  try {
    items = JSON.parse(String(formData.get("items") ?? "[]"));
  } catch {
    return { status: "bad", message: "Revisá los renglones de la lista." };
  }
  const parsed = priceListSchema.safeParse({
    supplier_id: formData.get("supplier_id"),
    received_on: formData.get("received_on"),
    valid_from: formData.get("valid_from"),
    items,
    reason: formData.get("reason"),
  });
  if (!parsed.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      const key = issue.path.join(".");
      if (!fieldErrors[key]) fieldErrors[key] = issue.message;
    }
    return { status: "bad", message: "Revisá los campos marcados.", fieldErrors };
  }
  const { supplier_id, received_on, valid_from, items: rows, reason } = parsed.data;
  const file = await checkFile(formData.get("file"));
  if (typeof file === "string")
    return { status: "bad", message: "Revisá los campos marcados.", fieldErrors: { file } };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("create_price_list", {
    p_supplier_id: supplier_id,
    p_received_on: received_on,
    p_valid_from: valid_from,
    p_items: rows.map((r) => ({
      name: r.name,
      ...(r.sku ? { sku: r.sku } : {}),
      list_price: r.list_price,
      bonus1_pct: r.bonus1_pct,
      bonus2_pct: r.bonus2_pct,
      bonus_per_unit_amount: r.bonus_per_unit_amount,
      vat_rate: r.vat_rate,
    })),
    p_notes: "",
    p_reason: reason,
  });
  revalidate(supplier_id);
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const result = z
    .object({ price_list_id: z.string(), items: z.number(), queued: z.number() })
    .safeParse(data);
  if (!result.success) return { status: "ok", message: "Lista cargada." };
  const { queued, price_list_id: listId } = result.data;
  const attached = file ? await attach(supabase, listId, file, reason) : null;
  const summary =
    queued === 0
      ? "Lista cargada. Reconocimos todos los artículos."
      : queued === 1
        ? "Lista cargada. Un artículo no lo reconocimos: va a la cola de mapeo y le avisamos al chef."
        : `Lista cargada. ${queued} artículos no los reconocimos: van a la cola de mapeo y le avisamos al chef.`;
  // Si el archivo no se pudo subir, la lista ya está cargada: se avisa en amarillo y se adjunta desde su detalle.
  return {
    status: attached === false ? "warn" : "ok",
    priceListId: listId,
    message:
      summary +
      (attached === true
        ? " El archivo quedó adjunto."
        : attached === false
          ? " No pudimos subir el archivo: adjuntalo desde el detalle de la lista."
          : ""),
  };
}

type Client = Awaited<ReturnType<typeof createClient>>;

// Sube el archivo a la carpeta de la lista (<grupo>/price_lists/<lista>/) y lo registra como adjunto.
async function attach(
  client: Client,
  listId: string,
  file: File,
  reason: string,
): Promise<boolean> {
  const { data: row } = await client
    .schema("purchasing")
    .from("price_lists")
    .select("group_id")
    .eq("id", listId)
    .maybeSingle();
  if (!row) return false;
  const path = `${row.group_id}/price_lists/${listId}/${randomUUID()}.${FILE_TYPES[file.type as FileType]}`;
  const uploaded = await client.storage
    .from("purchasing-documents")
    .upload(path, file, { contentType: file.type, upsert: false });
  if (uploaded.error) return false;
  const registered = await client.schema("purchasing").rpc("add_price_list_attachment", {
    p_price_list_id: listId,
    p_storage_path: path,
    p_page: 1,
    p_reason: reason,
  });
  return !registered.error && toActionState(registered.data, null).status === "ok";
}

// Adjuntar el archivo después (si no subió al cargar), mientras la lista está recibida.
export async function attachFileAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("priceListId"));
  if (!id.success) return { status: "bad", message: "Falta la lista." };
  const reason = z.string().trim().min(3).max(500).safeParse(formData.get("reason"));
  const file = await checkFile(formData.get("file"));
  const fieldErrors: Record<string, string> = {};
  if (!reason.success) fieldErrors.reason = "Escribí el motivo (al menos 3 letras).";
  if (file === null) fieldErrors.file = "Elegí el archivo.";
  if (typeof file === "string") fieldErrors.file = file;
  if (!reason.success || !(file instanceof File))
    return { status: "bad", message: "Revisá los campos marcados.", fieldErrors };
  const client = await createClient();
  const ok = await attach(client, id.data, file, reason.data);
  revalidatePath(`/listas-de-precios/${id.data}`);
  return ok
    ? { status: "ok", message: "Archivo adjunto." }
    : {
        status: "bad",
        message:
          "No pudimos subir el archivo. Revisá que la lista siga sin aceptar y probá de nuevo.",
      };
}

export async function acceptPriceListAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const id = uuid.safeParse(formData.get("priceListId"));
  const reason = z.string().trim().min(3).max(500).safeParse(formData.get("reason"));
  if (!id.success) return { status: "bad", message: "Falta la lista." };
  if (!reason.success)
    return {
      status: "bad",
      message: "Revisá los campos marcados.",
      fieldErrors: { reason: "Escribí el motivo (al menos 3 letras)." },
    };
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("accept_price_list", {
    p_id: id.data,
    p_reason: reason.data,
  });
  revalidate(
    typeof formData.get("supplierId") === "string" ? String(formData.get("supplierId")) : undefined,
  );
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  // Aceptada, el botón «Aceptar» (y su ventana) desaparece: el aviso va arriba del detalle, con ?aviso=.
  const replaced = z.object({ replaced: z.string().nullable() }).safeParse(data);
  redirect(
    `/listas-de-precios/${id.data}?aviso=${replaced.success && replaced.data.replaced ? "reemplazo" : "aceptada"}`,
  );
}
