"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

import {
  MAX_SUPPLIER_FILE_BYTES,
  MAX_SUPPLIER_ROWS,
  readSupplierSheet,
  type SupplierImportRow,
} from "@/lib/imports/supplier-sheet";
import { reasonField } from "@/lib/forms/schemas";
import { createClient } from "@/lib/supabase/server";

// Importación de proveedores desde planilla (ADR-0055). «Revisar» lee el Excel y pide la vista previa a la base, que
// hace todo y lo deshace. «Crear» manda las mismas filas y la base vuelve a validar todo antes de crear: lo que llega
// del navegador es lo mismo que podría cargar a mano quien tiene el permiso (como ADR-0027, decisión 8).

export type PreviewRow = {
  row: number;
  name: string | null;
  tax_id: string | null;
  status: "create" | "skip" | "error";
  message: string;
};
export type PreviewTotals = { rows: number; create: number; skip: number; error: number };
export type ImportState =
  | { status?: undefined }
  | { status: "bad"; message: string; rows?: PreviewRow[]; totals?: PreviewTotals }
  | {
      status: "preview";
      fileName: string;
      rows: PreviewRow[];
      totals: PreviewTotals;
      // Las filas para «Crear»: solo si ninguna tiene error.
      payload: ImportPayload[] | null;
    };

type ImportPayload = Omit<SupplierImportRow, "errors">;

const BaseResult = z.object({
  result: z.enum(["preview", "applied", "rejected", "denied"]),
  message: z.string().optional(),
  rows: z
    .array(
      z.object({
        row: z.number().int(),
        name: z.string().nullable(),
        tax_id: z.string().nullable(),
        status: z.enum(["create", "skip", "error"]),
        message: z.string(),
      }),
    )
    .optional(),
  totals: z
    .object({ rows: z.number(), create: z.number(), skip: z.number(), error: z.number() })
    .optional(),
});

// Lo que la pantalla devuelve al confirmar: la misma forma que arma el lector.
const text = (max: number) => z.string().trim().max(max);
const PayloadRow = z
  .object({
    row: z.number().int().min(1).max(100_000),
    name: text(200).nullable(),
    tax_id: text(20).nullable(),
    supplier: z
      .object({
        trade_name: text(120),
        vat_condition: z.enum(["registered", "monotax", "exempt"]),
        address: text(200),
        city: text(120),
        phone: text(40),
        whatsapp: text(40),
        email: text(320),
        sales_contact: text(120),
        admin_contact: text(120),
      })
      .partial()
      .strict(),
    terms: z
      .object({
        order_days: z.array(z.number().int().min(1).max(7)).max(7),
        delivery_days: z.array(z.number().int().min(1).max(7)).max(7),
        po_channel: z.enum(["whatsapp", "email", "supplier_portal"]),
        po_channel_target: text(320),
        requires_po_approval: z.boolean(),
      })
      .partial()
      .strict(),
    payment_terms: z
      .object({
        payment_terms: z.enum(["cash", "cash_on_delivery", "same_day_transfer", "account"]),
        payment_days: text(3),
        minimum_order_amount: text(20),
      })
      .strict()
      .nullable(),
    categories: z.array(text(120)).max(60),
  })
  .strict();
const Payload = z.array(PayloadRow).min(1).max(MAX_SUPPLIER_ROWS);

async function groupId(): Promise<string | null> {
  const supabase = await createClient();
  // El grupo donde la persona administra proveedores (hoy, uno solo). La base vuelve a controlar el permiso.
  const groups = await supabase
    .schema("core")
    .rpc("permitted_group_ids", { p_permission: "purchasing.manage_suppliers" });
  const id = z
    .string()
    .uuid()
    .safeParse(Array.isArray(groups.data) ? groups.data[0] : null);
  return id.success ? id.data : null;
}

async function callImport(
  group: string,
  rows: ImportPayload[],
  confirm: boolean,
  reason: string | null,
): Promise<z.infer<typeof BaseResult> | { error: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("import_suppliers", {
    p_group_id: group,
    p_rows: rows,
    p_confirm: confirm,
    p_reason: reason ?? "",
  });
  if (error)
    return {
      error:
        error.code === "22023" || error.code === "23514"
          ? error.message
          : "No pudimos revisar la planilla. Probá de nuevo.",
    };
  const parsed = BaseResult.safeParse(data);
  if (!parsed.success) return { error: "No pudimos revisar la planilla. Probá de nuevo." };
  return parsed.data;
}

const strip = (r: SupplierImportRow): ImportPayload => ({
  row: r.row,
  name: r.name,
  tax_id: r.tax_id,
  supplier: r.supplier,
  terms: r.terms,
  payment_terms: r.payment_terms,
  categories: r.categories,
});

// Junta los errores del lector (valores que no se entienden) con lo que dice la base. Las filas con error van primero.
function merge(
  read: SupplierImportRow[],
  base: PreviewRow[],
): {
  rows: PreviewRow[];
  totals: PreviewTotals;
} {
  const byRow = new Map(base.map((b) => [b.row, b]));
  const rows = read.map((r): PreviewRow => {
    const b = byRow.get(r.row);
    if (r.errors.length > 0) {
      const extra = b?.status === "error" ? [b.message] : [];
      return {
        row: r.row,
        name: r.name,
        tax_id: r.tax_id,
        status: "error",
        message: [...new Set([...r.errors, ...extra])].join(" "),
      };
    }
    return (
      b ?? {
        row: r.row,
        name: r.name,
        tax_id: r.tax_id,
        status: "error",
        message: "La base no devolvió esta fila.",
      }
    );
  });
  const order = { error: 0, create: 1, skip: 2 } as const;
  rows.sort((a, b) => order[a.status] - order[b.status] || a.row - b.row);
  return {
    rows,
    totals: {
      rows: rows.length,
      create: rows.filter((r) => r.status === "create").length,
      skip: rows.filter((r) => r.status === "skip").length,
      error: rows.filter((r) => r.status === "error").length,
    },
  };
}

export async function previewSupplierImportAction(
  _prev: ImportState,
  formData: FormData,
): Promise<ImportState> {
  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0)
    return { status: "bad", message: "Elegí la planilla (.xlsx)." };
  if (file.size > MAX_SUPPLIER_FILE_BYTES)
    return {
      status: "bad",
      message: "El archivo pasa 1 MB. Usá la plantilla, sin otras hojas ni imágenes.",
    };
  const group = await groupId();
  if (!group) return { status: "bad", message: "No tenés permiso para importar proveedores." };
  const read = await readSupplierSheet(await file.arrayBuffer());
  if (!read.ok) return { status: "bad", message: read.message };
  const result = await callImport(group, read.rows.map(strip), false, null);
  if ("error" in result) return { status: "bad", message: result.error };
  if (result.result === "denied")
    return {
      status: "bad",
      message: result.message ?? "No tenés permiso para importar proveedores.",
    };
  const merged = merge(read.rows, result.rows ?? []);
  return {
    status: "preview",
    fileName: file.name.slice(0, 120),
    ...merged,
    payload: merged.totals.error === 0 && merged.totals.create > 0 ? read.rows.map(strip) : null,
  };
}

export async function confirmSupplierImportAction(
  payload: unknown,
  reason: unknown,
): Promise<ImportState> {
  const rows = Payload.safeParse(payload);
  if (!rows.success) return { status: "bad", message: "Volvé a subir la planilla." };
  const why = reasonField.safeParse(reason);
  if (!why.success)
    return { status: "bad", message: why.error.issues[0]?.message ?? "Escribí el motivo." };
  const group = await groupId();
  if (!group) return { status: "bad", message: "No tenés permiso para importar proveedores." };
  const result = await callImport(group, rows.data, true, why.data);
  if ("error" in result) return { status: "bad", message: result.error };
  if (result.result === "denied")
    return {
      status: "bad",
      message: result.message ?? "No tenés permiso para importar proveedores.",
    };
  if (result.result !== "applied") {
    // Algo cambió entre la vista previa y la confirmación (otra persona cargó un proveedor, se borró un rubro).
    const merged = merge(
      rows.data.map((r) => ({ ...r, errors: [] })),
      result.rows ?? [],
    );
    return {
      status: "bad",
      message:
        "No se creó ningún proveedor: hay filas con error. Corregí la planilla y subila de nuevo.",
      ...merged,
    };
  }
  revalidatePath("/proveedores");
  redirect(`/proveedores?aviso=importados&n=${result.totals?.create ?? 0}`);
}
