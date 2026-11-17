import { z } from "zod";

import { getActiveRestaurantId, getMyScopes } from "@/lib/data";
import { type PoStatus } from "@/lib/purchase-orders";
import { createClient } from "@/lib/supabase/server";

// Lecturas de órdenes de compra (Fase 3, Prompt 3, ADR-0053). Todo pasa por la base con la sesión de la persona: la RLS
// y las funciones deciden qué ve (el cocinero, su local; Compras, todo el grupo). Sin precios.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

// ---------------------------------------------------------------------------
// Local
// ---------------------------------------------------------------------------
export type OrderPlace = { id: string; name: string; code: string | null };

// Los locales donde la sesión tiene el permiso, con nombre y código.
export async function orderPlaces(permission: string): Promise<OrderPlace[]> {
  const supabase = await createClient();
  const [{ data, error }, scopes] = await Promise.all([
    supabase.schema("core").rpc("permitted_restaurant_ids", { p_permission: permission }),
    getMyScopes(),
  ]);
  if (error || !Array.isArray(data)) failed("tus locales");
  const ids = new Set(data.filter((x): x is string => typeof x === "string"));
  const byId = new Map(scopes.map((s) => [s.restaurant_id, s]));
  return [...ids]
    .map((id) => ({
      id,
      name: byId.get(id)?.restaurant_name ?? "",
      code: byId.get(id)?.restaurant_code ?? null,
    }))
    .filter((p) => p.name)
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
}

// El pedido en la dirección, el local elegido arriba o el único que tiene. Si no, ninguno.
export async function resolveOrderPlace(
  userId: string | undefined,
  requested: string | undefined,
  permission = "purchasing.create_orders",
): Promise<{ places: OrderPlace[]; place: OrderPlace | null }> {
  const [places, activeId] = await Promise.all([
    orderPlaces(permission),
    getActiveRestaurantId(userId),
  ]);
  const place =
    places.find((p) => p.id === requested) ??
    places.find((p) => p.id === activeId) ??
    (places.length === 1 ? (places[0] ?? null) : null);
  return { places, place };
}

// ---------------------------------------------------------------------------
// Proveedores y artículos para pedir
// ---------------------------------------------------------------------------
export type OrderSupplier = {
  id: string;
  name: string;
  orderDays: number[];
  deliveryDays: number[];
  requiresApproval: boolean;
  channel: string | null;
};

export async function getOrderSuppliers(): Promise<OrderSupplier[]> {
  const supabase = await createClient();
  const [suppliers, terms] = await Promise.all([
    supabase
      .schema("catalog")
      .from("suppliers")
      .select("id, name, trade_name")
      .eq("is_active", true)
      .order("name"),
    supabase
      .schema("purchasing")
      .from("supplier_terms")
      .select("supplier_id, order_days, delivery_days, requires_po_approval, po_channel"),
  ]);
  if (suppliers.error || terms.error) failed("los proveedores");
  const bySupplier = new Map(terms.data.map((t) => [t.supplier_id, t]));
  return suppliers.data.map((s) => {
    const t = bySupplier.get(s.id);
    return {
      id: s.id,
      name: s.trade_name || s.name,
      orderDays: t?.order_days ?? [],
      deliveryDays: t?.delivery_days ?? [],
      requiresApproval: t?.requires_po_approval ?? false,
      channel: t?.po_channel ?? null,
    };
  });
}

const rankingRow = z.object({
  purchase_product_id: z.string(),
  code: z.string(),
  description: z.string(),
  supplier_sku: z.string().nullable(),
  package_name: z.string(),
  units_per_package: z.number(),
  content_per_unit: z.coerce.number(),
  content_unit: z.string(),
  billed_by_weight: z.boolean(),
  estimated_weight_per_unit: z.coerce.number().nullable(),
  times_ordered: z.coerce.number(),
});
export type RankedProduct = z.infer<typeof rankingRow>;

export async function getSupplierRanking(
  supplierId: string,
  restaurantId: string,
): Promise<RankedProduct[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("supplier_product_ranking", {
    p_supplier_id: supplierId,
    p_restaurant_id: restaurantId,
  });
  if (error) failed("los artículos del proveedor");
  const parsed = z.array(rankingRow).safeParse(data);
  if (!parsed.success) failed("los artículos del proveedor");
  return parsed.data;
}

export async function searchOrderIngredients(
  restaurantId: string,
  query: string,
): Promise<{ id: string; code: string; name: string; unit_name: string }[]> {
  const q = query.trim().slice(0, 80);
  if (q.length < 2) return [];
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("order_ingredient_search", { p_restaurant_id: restaurantId, p_query: q });
  if (error) failed("las materias primas");
  return data ?? [];
}

export async function getExpectedDelivery(
  supplierId: string,
  from: string,
): Promise<string | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("expected_delivery", { p_supplier_id: supplierId, p_from: from });
  return error || typeof data !== "string" ? null : data;
}

// ---------------------------------------------------------------------------
// Listado y ficha
// ---------------------------------------------------------------------------
const listRow = z.object({
  id: z.string(),
  number: z.string(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  created_at: z.string(),
  expected_delivery_on: z.string(),
  status: z.string(),
  lines: z.coerce.number(),
  news: z.coerce.number(),
  mine: z.boolean(),
  total: z.coerce.number(),
});
export type OrderRow = Omit<z.infer<typeof listRow>, "total" | "status"> & { status: PoStatus };

export async function getOrders(filter: {
  status?: string;
  supplierId?: string;
  restaurantId?: string;
  mine: boolean;
  page: number;
  size: number;
}): Promise<{ rows: OrderRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("order_list", {
    p_status: filter.status,
    p_supplier_id: filter.supplierId,
    p_restaurant_id: filter.restaurantId,
    p_mine: filter.mine,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("las órdenes de compra");
  const parsed = z.array(listRow).safeParse(data);
  if (!parsed.success) failed("las órdenes de compra");
  return {
    rows: parsed.data.map((r) => {
      const { total, ...row } = r;
      void total;
      return { ...row, status: row.status as PoStatus };
    }),
    total: parsed.data[0]?.total ?? 0,
  };
}

export type OrderLine = {
  lineOrder: number;
  purchaseProductId: string | null;
  ingredientId: string | null;
  name: string;
  sku: string | null;
  packageName: string | null;
  unitName: string | null;
  quantity: number;
  receivedQuantity: number;
  note: string | null;
  billedByWeight: boolean;
  estimatedKg: number | null;
  withoutInvoiceName: boolean;
};

export type OrderDetail = {
  id: string;
  number: string;
  status: PoStatus;
  restaurantId: string;
  restaurantName: string;
  supplierId: string;
  supplierName: string;
  requiresApproval: boolean;
  requestedBy: string;
  mine: boolean;
  createdAt: string;
  expectedOn: string;
  sentAt: string | null;
  sentChannel: string | null;
  notes: string | null;
  approvalRequestId: string | null;
  lines: OrderLine[];
  events: { id: string; kind: string; message: string; createdAt: string }[];
  message: {
    status: string;
    channel: string;
    target: string;
    body: string;
    createdAt: string;
  } | null;
};

export async function getOrderDetail(
  id: string,
  userId: string | undefined,
): Promise<OrderDetail | null> {
  const supabase = await createClient();
  const purchasing = supabase.schema("purchasing");
  const [order, lines, events, messages] = await Promise.all([
    purchasing
      .from("purchase_orders")
      .select(
        "id, number, status, restaurant_id, supplier_id, requested_by, created_at, expected_delivery_on, sent_at, sent_channel, notes, approval_request_id",
      )
      .eq("id", id)
      .maybeSingle(),
    purchasing.rpc("order_lines", { p_order_id: id }),
    purchasing
      .from("purchase_order_events")
      .select("id, kind, message, created_at")
      .eq("purchase_order_id", id)
      .order("created_at"),
    purchasing
      .from("outbound_messages")
      .select("status, channel, target, body, created_at")
      .eq("source_id", id)
      .order("created_at", { ascending: false })
      .limit(1),
  ]);
  if (order.error || lines.error || events.error || messages.error) failed("la orden de compra");
  if (!order.data) return null;
  const [restaurant, supplier, terms] = await Promise.all([
    supabase
      .schema("org")
      .from("restaurants")
      .select("name")
      .eq("id", order.data.restaurant_id)
      .maybeSingle(),
    supabase
      .schema("catalog")
      .from("suppliers")
      .select("name, trade_name")
      .eq("id", order.data.supplier_id)
      .maybeSingle(),
    supabase
      .schema("purchasing")
      .from("supplier_terms")
      .select("requires_po_approval")
      .eq("supplier_id", order.data.supplier_id)
      .maybeSingle(),
  ]);
  const o = order.data;
  const m = messages.data[0];
  return {
    id: o.id,
    number: o.number,
    status: o.status as PoStatus,
    restaurantId: o.restaurant_id,
    restaurantName: restaurant.data?.name ?? "Local",
    supplierId: o.supplier_id,
    supplierName: supplier.data?.trade_name || supplier.data?.name || "Proveedor",
    requiresApproval: terms.data?.requires_po_approval ?? false,
    requestedBy: o.requested_by,
    mine: o.requested_by === userId,
    createdAt: o.created_at,
    expectedOn: o.expected_delivery_on,
    sentAt: o.sent_at,
    sentChannel: o.sent_channel,
    notes: o.notes,
    approvalRequestId: o.approval_request_id,
    lines: (lines.data ?? []).map((l) => ({
      lineOrder: l.line_order,
      purchaseProductId: l.purchase_product_id,
      ingredientId: l.ingredient_id,
      name: l.name,
      sku: l.supplier_sku,
      packageName: l.package_name,
      unitName: l.unit_name,
      quantity: Number(l.quantity),
      receivedQuantity: Number(l.received_quantity),
      note: l.line_note,
      billedByWeight: l.billed_by_weight,
      estimatedKg: l.estimated_kg === null ? null : Number(l.estimated_kg),
      withoutInvoiceName: l.without_invoice_name,
    })),
    events: events.data.map((e) => ({
      id: e.id,
      kind: e.kind,
      message: e.message,
      createdAt: e.created_at,
    })),
    message: m
      ? {
          status: m.status,
          channel: m.channel,
          target: m.target,
          body: m.body,
          createdAt: m.created_at,
        }
      : null,
  };
}

// Novedades sin leer de mis órdenes (order_news) y sus recepciones (receipt_report y, para Compras, receipt_differences;
// ADR-0056). El cocinero no tiene la bandeja de Aprobaciones: las ve en el
// listado de órdenes. La RLS de core.notifications deja ver solo las propias.
export async function getOrderNotices(): Promise<
  { id: string; title: string; body: string | null; link: string | null; createdAt: string }[]
> {
  const client = await createClient();
  const { data, error } = await client
    .schema("core")
    .from("notifications")
    .select("id, title, body, link, created_at")
    .in("kind", ["order_news", "receipt_report", "receipt_differences"])
    .is("read_at", null)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(11);
  if (error) failed("las novedades de tus órdenes");
  return data.map((n) => ({
    id: n.id,
    title: n.title,
    body: n.body,
    link: n.link && /^\/compras\/ordenes\/[0-9a-f-]{36}$/.test(n.link) ? n.link : null,
    createdAt: n.created_at,
  }));
}
