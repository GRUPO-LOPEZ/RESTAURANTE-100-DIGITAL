"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import { toActionState, type ActionState } from "@/lib/auth/results";
import { getMenus } from "@/lib/auth/session";
import { keptFile, readPriceListFile, type ReadListResult } from "@/lib/imports/price-list-file";
import { correctPriceListSchema, priceListSchema } from "@/lib/price-lists";
import { getSupplierProducts } from "@/lib/price-lists-data";
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

// El archivo de la lista (opcional): foto, PDF, Excel o CSV (el original importado queda guardado, decisión 12 de Soy).
// Viaja por la acción de servidor, que acepta hasta 4 MB por envío (next.config.ts).
const FILE_MAX_BYTES = 3.5 * 1024 * 1024;
type Kept = NonNullable<ReturnType<typeof keptFile>>;

// Qué es el archivo por su contenido entero (no por el tipo que declara el navegador ni por la extensión): la misma
// regla que al leerlo (lib/imports/price-list-file.ts). Un Excel se controla también por dentro (zip).
async function checkFile(
  file: FormDataEntryValue | null,
): Promise<{ file: File; kept: Kept } | null | string> {
  if (!(file instanceof File) || file.size === 0) return null;
  if (file.size > FILE_MAX_BYTES)
    return "El archivo pesa más de 3,5 MB. Probá con uno más liviano.";
  const kept = keptFile(await file.arrayBuffer(), file.name);
  if (!kept) return "El archivo tiene que ser una foto, un PDF, un Excel (.xlsx) o un CSV.";
  return { file, kept };
}

// Leer el archivo de la lista y devolver sus renglones para la planilla (ADR-0071). No guarda nada: el archivo se
// guarda al cargar la lista. Pide cargar listas en algún grupo (la base lo vuelve a controlar al cargar).
export async function readPriceListFileAction(formData: FormData): Promise<ReadListResult> {
  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0)
    return { ok: false, message: "Elegí el archivo." };
  if (!(await getMenus()).priceListsManage)
    return { ok: false, message: "No tenés permiso para cargar listas." };
  const sheet = formData.get("sheet");
  return readPriceListFile(
    await file.arrayBuffer(),
    file.name,
    typeof sheet === "string" && sheet ? sheet : undefined,
  );
}

// Los controles de la planilla antes de cargar (variación, umbral, «Revisar» y precio por unidad de uso), con la
// misma regla que la ficha: purchasing.price_list_preview.
const previewRow = z.object({
  line: z.number(),
  purchase_product_id: z.string().nullable(),
  product_name: z.string().nullable(),
  net_price: z.coerce.number().nullable(),
  previous_net_price: z.coerce.number().nullable(),
  change_pct: z.coerce.number().nullable(),
  over_threshold: z.boolean(),
  review: z.boolean(),
  per_use_price: z.coerce.number().nullable(),
  per_use_unit: z.string().nullable(),
});
export type PreviewRow = z.infer<typeof previewRow>;

export async function previewPriceListAction(
  supplierId: string,
  items: unknown,
): Promise<PreviewRow[] | null> {
  const id = uuid.safeParse(supplierId);
  // Solo lo que la base entiende de un renglón (lo demás se descarta); números finitos.
  const num = z.number().finite().optional();
  const rows = z
    .array(
      z.object({
        name: z.string().max(200),
        sku: z.string().max(40).optional(),
        purchase_product_id: z.string().uuid().optional(),
        list_price: num,
        bonus1_pct: num,
        bonus2_pct: num,
        bonus_per_unit_amount: num,
        vat_rate: num,
      }),
    )
    .max(500)
    .safeParse(items);
  if (!id.success || !rows.success) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("price_list_preview", {
    p_supplier_id: id.data,
    p_items: rows.data,
  });
  if (error || data === null) return null;
  const parsed = z.array(previewRow).safeParse(data);
  return parsed.success ? parsed.data : null;
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
      ...(r.purchase_product_id ? { purchase_product_id: r.purchase_product_id } : {}),
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
  const attached = file ? await attach(supabase, listId, file.file, file.kept, reason) : null;
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
  kept: Kept,
  reason: string,
): Promise<boolean> {
  const { data: row } = await client
    .schema("purchasing")
    .from("price_lists")
    .select("group_id")
    .eq("id", listId)
    .maybeSingle();
  if (!row) return false;
  const path = `${row.group_id}/price_lists/${listId}/${randomUUID()}.${kept.ext}`;
  const uploaded = await client.storage
    .from("purchasing-documents")
    .upload(path, file, { contentType: kept.contentType, upsert: false });
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
  if (!reason.success || file === null || typeof file === "string")
    return { status: "bad", message: "Revisá los campos marcados.", fieldErrors };
  const client = await createClient();
  const ok = await attach(client, id.data, file.file, file.kept, reason.data);
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
    // Los precios en «Revisar» (10 veces más o menos) se confirman con la casilla de la ventana.
    p_confirm_review: formData.get("confirmReview") === "on",
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

// Corregir la vigente (decisión 13 de Soy): una versión nueva con motivo; la anterior queda en la historia.
export async function correctPriceListAction(
  payload: z.input<typeof correctPriceListSchema>,
): Promise<CreatePriceListState> {
  const parsed = correctPriceListSchema.safeParse(payload);
  if (!parsed.success) {
    const fieldErrors: Record<string, string> = {};
    for (const issue of parsed.error.issues) {
      const key = issue.path.join(".");
      if (!fieldErrors[key]) fieldErrors[key] = issue.message;
    }
    return { status: "bad", message: "Revisá los campos marcados.", fieldErrors };
  }
  const p = parsed.data;
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("correct_price_list", {
    p_id: p.price_list_id,
    p_items: p.items.map((r) => ({
      name: r.name,
      ...(r.sku ? { sku: r.sku } : {}),
      ...(r.purchase_product_id ? { purchase_product_id: r.purchase_product_id } : {}),
      list_price: r.list_price,
      bonus1_pct: r.bonus1_pct,
      bonus2_pct: r.bonus2_pct,
      bonus_per_unit_amount: r.bonus_per_unit_amount,
      vat_rate: r.vat_rate,
    })),
    p_reason: p.reason,
    p_confirm_review: p.confirm_review,
  });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  const created = z.object({ price_list_id: z.string() }).safeParse(data);
  if (!created.success) return { status: "bad", message: "No pudimos corregir la lista." };
  revalidate();
  redirect(`/listas-de-precios/${created.data.price_list_id}?aviso=corregida`);
}

// Anular una lista cargada por error (decisión 24): con motivo, sin borrarla.
export async function voidPriceListAction(
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
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("void_price_list", { p_id: id.data, p_reason: reason.data });
  const state = toActionState(data, error);
  if (state.status !== "ok") return state;
  revalidate();
  const restored = z.object({ restored: z.string().nullable() }).safeParse(data);
  redirect(
    `/listas-de-precios/${id.data}?aviso=${restored.success && restored.data.restored ? "anulada-vuelve" : "anulada"}`,
  );
}

// Los artículos del proveedor, para elegir a mano a cuál corresponde un renglón («Es…»). Con la RLS de quien consulta.
export async function supplierProductsAction(
  supplierId: string,
): Promise<{ id: string; code: string; description: string }[]> {
  if (!uuid.safeParse(supplierId).success) return [];
  try {
    return await getSupplierProducts(supplierId);
  } catch {
    return [];
  }
}
