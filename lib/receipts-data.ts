import { z } from "zod";

import { type PoStatus } from "@/lib/purchase-orders";
import { type PaperKind, type ReceiptIssue, type ReceiptResult } from "@/lib/receipts";
import { createClient } from "@/lib/supabase/server";

// Lecturas de la recepción y del inventario (Fase 3, Prompt 4, ADR-0056). Todo pasa por la base con la sesión de la
// persona: la RLS y las funciones deciden qué ve. El efectivo lo ve solo quien ve precios en el local.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

const BUCKET = "purchasing-documents";
// Los enlaces de las fotos duran 5 minutos (Storage controla que la sesión las pueda leer).
const SIGNED_SECONDS = 300;

// ---------------------------------------------------------------------------
// «¿Qué llegó?»
// ---------------------------------------------------------------------------
const receivableRow = z.object({
  id: z.string(),
  number: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  expected_delivery_on: z.string(),
  status: z.string(),
  pending_lines: z.coerce.number(),
  open_receipt_id: z.string().nullable(),
});
export type ReceivableOrder = Omit<z.infer<typeof receivableRow>, "status"> & { status: PoStatus };

export async function getReceivableOrders(restaurantId: string): Promise<ReceivableOrder[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("receivable_orders", { p_restaurant_id: restaurantId });
  if (error) failed("las órdenes para recibir");
  const parsed = z.array(receivableRow).safeParse(data);
  if (!parsed.success) failed("las órdenes para recibir");
  return parsed.data.map((r) => ({ ...r, status: r.status as PoStatus }));
}

export async function getReceivableSuppliers(
  restaurantId: string,
): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("receivable_suppliers", { p_restaurant_id: restaurantId });
  if (error) failed("los proveedores");
  return data ?? [];
}

// ---------------------------------------------------------------------------
// Una recepción
// ---------------------------------------------------------------------------
const photoRow = z.object({
  id: z.string(),
  kind: z.enum(["receipt_original", "receipt_signed"]),
  page: z.number(),
  path: z.string(),
});
const pendingRow = z.object({
  purchase_order_line_id: z.string(),
  line_order: z.number(),
  name: z.string(),
  package_name: z.string().nullable(),
  unit_name: z.string().nullable(),
  ordered: z.coerce.number(),
  already_received: z.coerce.number(),
  pending: z.coerce.number(),
  billed_by_weight: z.boolean(),
  estimated_kg: z.coerce.number().nullable(),
  without_invoice_name: z.boolean(),
  note: z.string().nullable(),
});
const linePhotoRow = z.object({ id: z.string(), path: z.string(), page: z.number() });
const doneRow = z.object({
  id: z.string(),
  line_order: z.number(),
  purchase_order_line_id: z.string().nullable(),
  name: z.string().nullable(),
  description: z.string().nullable(),
  package_name: z.string().nullable(),
  unit_name: z.string().nullable(),
  ordered: z.coerce.number().nullable(),
  received: z.coerce.number(),
  weight: z.coerce.number().nullable(),
  ok: z.boolean(),
  issue: z.string().nullable(),
  lot_code: z.string().nullable(),
  note: z.string().nullable(),
  unmapped: z.boolean(),
  photos: z.array(linePhotoRow),
});
const detailRow = z.object({
  id: z.string(),
  status: z.enum(["open", "closed"]),
  result: z.string().nullable(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  purchase_order_id: z.string().nullable(),
  order_number: z.string().nullable(),
  requested_by_name: z.string().nullable(),
  received_by_name: z.string(),
  mine: z.boolean(),
  started_at: z.string(),
  closed_at: z.string().nullable(),
  paper_kind: z.string().nullable(),
  paper_number: z.string().nullable(),
  can_see_cash: z.boolean(),
  cash_paid: z.boolean(),
  cash_paid_amount: z.coerce.number().nullable(),
  can_receive: z.boolean(),
  photos: z.array(photoRow),
  lines: z.array(z.unknown()),
});

export type ReceiptPhoto = {
  id: string;
  kind: "receipt_original" | "receipt_signed";
  page: number;
  url: string | null;
};
export type ReceiptPendingLine = {
  purchaseOrderLineId: string;
  lineOrder: number;
  name: string;
  packageName: string | null;
  unitName: string | null;
  ordered: number;
  alreadyReceived: number;
  pending: number;
  billedByWeight: boolean;
  estimatedKg: number | null;
  withoutInvoiceName: boolean;
  note: string | null;
};
export type ReceiptDoneLine = {
  id: string;
  lineOrder: number;
  fromOrder: boolean;
  name: string;
  packageName: string | null;
  unitName: string | null;
  ordered: number | null;
  received: number;
  weight: number | null;
  ok: boolean;
  issue: ReceiptIssue | null;
  lot: string | null;
  note: string | null;
  unmapped: boolean;
  photos: { id: string; url: string | null }[];
};
export type Receipt = {
  id: string;
  status: "open" | "closed";
  result: ReceiptResult | null;
  restaurantId: string;
  restaurantName: string;
  supplierName: string;
  orderId: string | null;
  orderNumber: string | null;
  requestedByName: string | null;
  receivedByName: string;
  mine: boolean;
  startedAt: string;
  closedAt: string | null;
  paperKind: PaperKind | null;
  paperNumber: string | null;
  canSeeCash: boolean;
  cashPaid: boolean;
  cashAmount: number | null;
  canReceive: boolean;
  photos: ReceiptPhoto[];
  pending: ReceiptPendingLine[];
  done: ReceiptDoneLine[];
};

async function signed(paths: string[]): Promise<Map<string, string>> {
  if (paths.length === 0) return new Map();
  const supabase = await createClient();
  const { data } = await supabase.storage.from(BUCKET).createSignedUrls(paths, SIGNED_SECONDS);
  const out = new Map<string, string>();
  for (const s of data ?? []) if (s.path && s.signedUrl) out.set(s.path, s.signedUrl);
  return out;
}

// La recepción entera, o null si no existe o la sesión no la ve.
export async function getReceipt(id: string): Promise<Receipt | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("receipt_detail", { p_id: id });
  if (error) failed("la recepción");
  if (data === null) return null;
  const parsed = detailRow.safeParse(data);
  if (!parsed.success) failed("la recepción");
  const r = parsed.data;
  const pending =
    r.status === "open"
      ? z.array(pendingRow).safeParse(r.lines)
      : { success: true as const, data: [] };
  const done =
    r.status === "closed"
      ? z.array(doneRow).safeParse(r.lines)
      : { success: true as const, data: [] };
  if (!pending.success || !done.success) failed("los renglones de la recepción");
  const urls = await signed([
    ...r.photos.map((p) => p.path),
    ...done.data.flatMap((l) => l.photos.map((p) => p.path)),
  ]);
  return {
    id: r.id,
    status: r.status,
    result: r.result as ReceiptResult | null,
    restaurantId: r.restaurant_id,
    restaurantName: r.restaurant_name,
    supplierName: r.supplier_name,
    orderId: r.purchase_order_id,
    orderNumber: r.order_number,
    requestedByName: r.requested_by_name,
    receivedByName: r.received_by_name,
    mine: r.mine,
    startedAt: r.started_at,
    closedAt: r.closed_at,
    paperKind: r.paper_kind as PaperKind | null,
    paperNumber: r.paper_number,
    canSeeCash: r.can_see_cash,
    cashPaid: r.cash_paid,
    cashAmount: r.cash_paid_amount,
    canReceive: r.can_receive,
    photos: r.photos.map((p) => ({
      id: p.id,
      kind: p.kind,
      page: p.page,
      url: urls.get(p.path) ?? null,
    })),
    pending: pending.data.map((l) => ({
      purchaseOrderLineId: l.purchase_order_line_id,
      lineOrder: l.line_order,
      name: l.name,
      packageName: l.package_name,
      unitName: l.unit_name,
      ordered: l.ordered,
      alreadyReceived: l.already_received,
      pending: l.pending,
      billedByWeight: l.billed_by_weight,
      estimatedKg: l.estimated_kg,
      withoutInvoiceName: l.without_invoice_name,
      note: l.note,
    })),
    done: done.data.map((l) => ({
      id: l.id,
      lineOrder: l.line_order,
      fromOrder: l.purchase_order_line_id !== null,
      name: l.name ?? l.description ?? "",
      packageName: l.package_name,
      unitName: l.unit_name,
      ordered: l.ordered,
      received: l.received,
      weight: l.weight,
      ok: l.ok,
      issue: l.issue as ReceiptIssue | null,
      lot: l.lot_code,
      note: l.note,
      unmapped: l.unmapped,
      photos: l.photos.map((p) => ({ id: p.id, url: urls.get(p.path) ?? null })),
    })),
  };
}

// Las recepciones de una OC, enteras (para el informe en su ficha). La abierta, primero.
export async function getOrderReceipts(orderId: string): Promise<Receipt[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("order_receipts", { p_order_id: orderId });
  if (error) failed("las recepciones de la orden");
  const ids = z.array(z.object({ id: z.string() })).safeParse(data);
  if (!ids.success) failed("las recepciones de la orden");
  const all = await Promise.all(ids.data.map((r) => getReceipt(r.id)));
  return all.filter((r): r is Receipt => r !== null);
}

// ---------------------------------------------------------------------------
// Inventario
// ---------------------------------------------------------------------------
// Las materias primas para el filtro del inventario (id y nombre, las que la sesión ve).
export async function getIngredientOptions(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("ingredients")
    .select("id, name")
    .order("name")
    .limit(2000);
  if (error) failed("las materias primas");
  return data ?? [];
}

const movementRow = z.object({
  id: z.string(),
  occurred_at: z.string(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  ingredient_id: z.string(),
  ingredient_name: z.string(),
  product_name: z.string().nullable(),
  kind: z.string(),
  quantity: z.coerce.number(),
  unit_name: z.string(),
  packages: z.coerce.number().nullable(),
  package_name: z.string().nullable(),
  lot_code: z.string().nullable(),
  supplier_name: z.string().nullable(),
  purchase_order_id: z.string().nullable(),
  order_number: z.string().nullable(),
  total: z.coerce.number(),
});
export type MovementRow = Omit<z.infer<typeof movementRow>, "total">;

export async function getMovements(filter: {
  restaurantId?: string;
  ingredientId?: string;
  from?: string;
  to?: string;
  lot?: string;
  page: number;
  size: number;
}): Promise<{ rows: MovementRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("inventory").rpc("movement_list", {
    p_restaurant_id: filter.restaurantId,
    p_ingredient_id: filter.ingredientId,
    p_from: filter.from,
    p_to: filter.to,
    p_lot: filter.lot,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("los movimientos de stock");
  const parsed = z.array(movementRow).safeParse(data);
  if (!parsed.success) failed("los movimientos de stock");
  return {
    rows: parsed.data.map((r) => {
      const { total, ...row } = r;
      void total;
      return row;
    }),
    total: parsed.data[0]?.total ?? 0,
  };
}
