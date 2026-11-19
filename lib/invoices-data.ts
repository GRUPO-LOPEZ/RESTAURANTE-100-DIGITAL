import { z } from "zod";

import {
  numberText,
  type CheckRow,
  type HeaderDraft,
  type InvoiceCheckKind,
  type InvoiceClass,
  type InvoiceDraft,
  type InvoiceLineClass,
  type InvoiceStatus,
  type InvoiceTaxKind,
  type NoteKind,
} from "@/lib/invoices";
import { createClient } from "@/lib/supabase/server";

// Lecturas de facturas (Fase 3, Prompt 5B, ADR-0058). Todo con la sesión de la persona: la RLS de purchasing.invoices
// (purchasing.view_invoices en el local) decide qué ve, y purchasing.invoice_access qué puede hacer. El cocinero y el
// chef no ven facturas.

const BUCKET = "purchasing-documents";
const SIGNED_SECONDS = 600;

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

// ---------------------------------------------------------------------------
// Listado
// ---------------------------------------------------------------------------
const listRow = z.object({
  id: z.string(),
  invoice_class: z.string(),
  point_of_sale: z.number().nullable(),
  number: z.coerce.number(),
  restaurant_id: z.string(),
  restaurant_name: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  issued_on: z.string(),
  due_on: z.string(),
  total_amount: z.coerce.number(),
  status: z.string(),
  failed: z.array(z.string()),
  total: z.coerce.number(),
});
export type InvoiceRow = Omit<z.infer<typeof listRow>, "total" | "invoice_class" | "status"> & {
  invoice_class: InvoiceClass;
  status: InvoiceStatus;
};

export async function getInvoices(filter: {
  status?: string;
  supplierId?: string;
  restaurantId?: string;
  from?: string;
  to?: string;
  page: number;
  size: number;
}): Promise<{ rows: InvoiceRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("invoice_list", {
    p_status: filter.status,
    p_supplier_id: filter.supplierId,
    p_restaurant_id: filter.restaurantId,
    p_from: filter.from,
    p_to: filter.to,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("las facturas");
  const parsed = z.array(listRow).safeParse(data);
  if (!parsed.success) failed("las facturas");
  return {
    rows: parsed.data.map((r) => {
      const { total, ...row } = r;
      void total;
      return {
        ...row,
        invoice_class: row.invoice_class as InvoiceClass,
        status: row.status as InvoiceStatus,
      };
    }),
    total: parsed.data[0]?.total ?? 0,
  };
}

// ---------------------------------------------------------------------------
// Alta
// ---------------------------------------------------------------------------
export type InvoiceableOrder = {
  id: string;
  number: string;
  supplierId: string;
  supplierName: string;
  partial: boolean;
  receivedOn: string | null;
  lines: number;
};

export async function getInvoiceableOrders(restaurantId: string): Promise<InvoiceableOrder[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("purchasing")
    .rpc("invoiceable_orders", { p_restaurant_id: restaurantId });
  if (error) failed("las órdenes recibidas");
  return data.map((o) => ({
    id: o.id,
    number: o.number,
    supplierId: o.supplier_id,
    supplierName: o.supplier_name,
    partial: o.status === "partially_received",
    receivedOn: o.received_on,
    lines: Number(o.lines),
  }));
}

// Los proveedores activos para el alta (también los que no tienen OC: un flete, un servicio), con su CUIT.
export async function getInvoiceSuppliers(): Promise<
  { id: string; name: string; taxId: string | null }[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("suppliers")
    .select("id, name, trade_name, tax_id")
    .eq("is_active", true)
    .is("deleted_at", null)
    .order("name");
  if (error) failed("los proveedores");
  return data.map((s) => ({ id: s.id, name: s.trade_name || s.name, taxId: s.tax_id }));
}

// ---------------------------------------------------------------------------
// Ficha
// ---------------------------------------------------------------------------
const access = z.object({
  loaded_by_name: z.string(),
  approved_by_name: z.string().nullable(),
  can_edit: z.boolean(),
  can_add_note: z.boolean(),
  can_approve: z.boolean(),
  approve_blocked: z.string().nullable(),
});
export type InvoiceAccess = z.infer<typeof access>;

export type InvoiceFile = { id: string; page: number; url: string | null; pdf: boolean };

export type InvoiceNote = {
  id: string;
  kind: NoteKind;
  number: string | null;
  issuedOn: string;
  netAmount: number;
  totalAmount: number;
  reason: string;
  files: InvoiceFile[];
};

export type InvoiceDetail = {
  id: string;
  status: InvoiceStatus;
  invoiceClass: InvoiceClass;
  pointOfSale: number | null;
  number: number;
  restaurantId: string;
  restaurantName: string;
  supplierId: string;
  supplierName: string;
  legalEntityTaxId: string | null;
  issuedOn: string;
  dueOn: string;
  dueOnPrinted: boolean;
  totalAmount: number;
  observedReason: string | null;
  cancelledReason: string | null;
  approvedAt: string | null;
  // El sello del último cambio: «Dar por conforme» lo manda y la base rechaza si cambió (p_version).
  version: string;
  access: InvoiceAccess;
  draft: InvoiceDraft;
  orders: { id: string; number: string }[];
  // El último control: vacío si nunca se controló o se cambió después (vuelve a «cargada»).
  checks: CheckRow[];
  checkedAt: string | null;
  notes: InvoiceNote[];
  files: InvoiceFile[];
  // Lo que se facturó por línea guardada (para la diferencia en pesos).
  quantities: Map<string, number>;
};

async function signed(paths: string[]): Promise<Map<string, string | null>> {
  if (paths.length === 0) return new Map();
  const supabase = await createClient();
  const { data } = await supabase.storage.from(BUCKET).createSignedUrls(paths, SIGNED_SECONDS);
  return new Map((data ?? []).map((d) => [d.path ?? "", d.signedUrl ?? null]));
}

export async function getInvoiceDetail(id: string): Promise<InvoiceDetail | null> {
  const supabase = await createClient();
  const purchasing = supabase.schema("purchasing");
  const [invoice, lines, taxes, orders, checks, notes, rights] = await Promise.all([
    purchasing
      .from("invoices")
      .select(
        "id, status, invoice_class, point_of_sale, number, restaurant_id, supplier_id, legal_entity_tax_id, authorization_kind, authorization_code, issuer_tax_id, receiver_tax_id, issued_on, due_on, due_on_source, net_amount, exempt_amount, vat_amount, internal_tax_amount, perception_amount, discount_amount, rounding_amount, total_amount, observed_reason, cancelled_reason, approved_at, updated_at",
      )
      .eq("id", id)
      .maybeSingle(),
    purchasing
      .from("invoice_lines")
      .select(
        "id, line_order, line_class, purchase_product_id, purchase_order_line_id, raw_name, supplier_sku, units, billed_quantity, list_price, bonus1_pct, bonus2_pct, bonus_per_unit_amount, unit_price, vat_rate, is_exempt, internal_tax_amount",
      )
      .eq("invoice_id", id)
      .order("line_order"),
    purchasing
      .from("invoice_taxes")
      .select("id, tax_kind, jurisdiction, rate_pct, tax_amount")
      .eq("invoice_id", id)
      .order("created_at"),
    purchasing.from("invoice_orders").select("purchase_order_id").eq("invoice_id", id),
    purchasing
      .from("invoice_checks")
      .select(
        "run_id, invoice_line_id, check_kind, passed, explanation, expected_amount, actual_amount, run_at, entry_number",
      )
      .eq("invoice_id", id)
      .order("entry_number", { ascending: false })
      .limit(600),
    purchasing
      .from("credit_debit_notes")
      .select("id, note_kind, number, issued_on, net_amount, total_amount, reason")
      .eq("invoice_id", id)
      .order("issued_on"),
    purchasing.rpc("invoice_access", { p_id: id }),
  ]);
  if (
    invoice.error ||
    lines.error ||
    taxes.error ||
    orders.error ||
    checks.error ||
    notes.error ||
    rights.error
  )
    failed("la factura");
  if (!invoice.data) return null;
  const rightsParsed = access.safeParse(rights.data);
  if (!rightsParsed.success) return null;
  const inv = invoice.data;

  const productIds = [
    ...new Set(lines.data.flatMap((l) => (l.purchase_product_id ? [l.purchase_product_id] : []))),
  ];
  const orderIds = orders.data.map((o) => o.purchase_order_id);
  const noteIds = notes.data.map((n) => n.id);
  const [restaurant, supplier, products, orderRows, attachments] = await Promise.all([
    supabase
      .schema("org")
      .from("restaurants")
      .select("name")
      .eq("id", inv.restaurant_id)
      .maybeSingle(),
    supabase
      .schema("catalog")
      .from("suppliers")
      .select("name, trade_name")
      .eq("id", inv.supplier_id)
      .maybeSingle(),
    productIds.length > 0
      ? supabase
          .schema("catalog")
          .from("purchase_products")
          .select("id, description, billed_by_weight")
          .in("id", productIds)
      : Promise.resolve({ data: [], error: null }),
    orderIds.length > 0
      ? purchasing.from("purchase_orders").select("id, number").in("id", orderIds).order("number")
      : Promise.resolve({ data: [], error: null }),
    purchasing
      .from("attachments")
      .select("id, source_table, source_id, page, storage_path, created_at")
      .in("source_id", [id, ...noteIds])
      .in("source_table", ["invoices", "credit_debit_notes"])
      .order("created_at", { ascending: false }),
  ]);
  if (products.error || orderRows.error || attachments.error) failed("la factura");
  const product = new Map(products.data.map((p) => [p.id, p]));

  // Rehacer suma otra foto: vale la última de cada página.
  const latest = new Map<string, (typeof attachments.data)[number]>();
  for (const a of attachments.data) {
    const key = `${a.source_id}|${a.page}`;
    if (!latest.has(key)) latest.set(key, a);
  }
  const kept = [...latest.values()].sort((a, b) => a.page - b.page);
  const urls = await signed(kept.map((a) => a.storage_path));
  const filesOf = (sourceId: string): InvoiceFile[] =>
    kept
      .filter((a) => a.source_id === sourceId)
      .map((a) => ({
        id: a.id,
        page: a.page,
        url: urls.get(a.storage_path) ?? null,
        pdf: a.storage_path.toLowerCase().endsWith(".pdf"),
      }));

  // El último control vale mientras la factura no volvió a «cargada» (guardar cambios la vuelve a cargada).
  const lastRun = inv.status === "loaded" ? null : (checks.data[0]?.run_id ?? null);
  const runRows = lastRun ? checks.data.filter((c) => c.run_id === lastRun) : [];

  const header: HeaderDraft = {
    invoice_class: inv.invoice_class,
    point_of_sale: inv.point_of_sale === null ? "" : String(inv.point_of_sale),
    number: String(inv.number),
    authorization_kind: inv.authorization_kind ?? "cae",
    authorization_code: inv.authorization_code ?? "",
    issuer_tax_id: inv.issuer_tax_id ?? "",
    receiver_tax_id: inv.receiver_tax_id ?? "",
    issued_on: inv.issued_on,
    // Un vencimiento que salió de la condición de pago no se manda como impreso.
    due_on: inv.due_on_source === "printed" ? inv.due_on : "",
    net_amount: numberText(Number(inv.net_amount)),
    exempt_amount: numberText(Number(inv.exempt_amount)),
    vat_amount: numberText(Number(inv.vat_amount)),
    internal_tax_amount: numberText(Number(inv.internal_tax_amount)),
    perception_amount: numberText(Number(inv.perception_amount)),
    discount_amount: numberText(Number(inv.discount_amount)),
    rounding_amount: numberText(Number(inv.rounding_amount)),
    total_amount: numberText(Number(inv.total_amount)),
  };

  return {
    id: inv.id,
    status: inv.status as InvoiceStatus,
    invoiceClass: inv.invoice_class as InvoiceClass,
    pointOfSale: inv.point_of_sale,
    number: Number(inv.number),
    restaurantId: inv.restaurant_id,
    restaurantName: restaurant.data?.name ?? "Local",
    supplierId: inv.supplier_id,
    supplierName: supplier.data?.trade_name || supplier.data?.name || "Proveedor",
    legalEntityTaxId: inv.legal_entity_tax_id,
    issuedOn: inv.issued_on,
    dueOn: inv.due_on,
    dueOnPrinted: inv.due_on_source === "printed",
    totalAmount: Number(inv.total_amount),
    observedReason: inv.observed_reason,
    cancelledReason: inv.cancelled_reason,
    approvedAt: inv.approved_at,
    version: inv.updated_at,
    access: rightsParsed.data,
    draft: {
      header,
      lines: lines.data.map((l) => {
        const p = l.purchase_product_id ? product.get(l.purchase_product_id) : undefined;
        return {
          key: l.id,
          id: l.id,
          line_class: l.line_class as InvoiceLineClass,
          purchase_product_id: l.purchase_product_id,
          purchase_order_line_id: l.purchase_order_line_id,
          product: p?.description ?? null,
          raw_name: l.raw_name,
          supplier_sku: l.supplier_sku ?? "",
          units: l.units === null ? "" : numberText(Number(l.units)),
          billed_quantity: numberText(Number(l.billed_quantity)),
          list_price: l.list_price === null ? null : Number(l.list_price),
          bonus1_pct: Number(l.bonus1_pct),
          bonus2_pct: Number(l.bonus2_pct),
          bonus_per_unit_amount: Number(l.bonus_per_unit_amount),
          unit_price: numberText(Number(l.unit_price)),
          vat_rate: l.vat_rate === null ? "" : String(Number(l.vat_rate)),
          is_exempt: l.is_exempt,
          internal_tax_amount: numberText(Number(l.internal_tax_amount)),
          by_weight: (p?.billed_by_weight ?? false) || l.units !== null,
        };
      }),
      taxes: taxes.data.map((t) => ({
        key: t.id,
        tax_kind: t.tax_kind as InvoiceTaxKind,
        jurisdiction: t.jurisdiction ?? "",
        rate_pct: t.rate_pct === null ? "" : numberText(Number(t.rate_pct)),
        tax_amount: numberText(Number(t.tax_amount)),
      })),
    },
    orders: orderRows.data.map((o) => ({ id: o.id, number: o.number })),
    checks: runRows
      .sort((a, b) => a.entry_number - b.entry_number)
      .map((c) => ({
        kind: c.check_kind as InvoiceCheckKind,
        lineId: c.invoice_line_id,
        passed: c.passed,
        explanation: c.explanation,
        expected: c.expected_amount === null ? null : Number(c.expected_amount),
        actual: c.actual_amount === null ? null : Number(c.actual_amount),
      })),
    checkedAt: runRows[0]?.run_at ?? null,
    notes: notes.data.map((n) => ({
      id: n.id,
      kind: n.note_kind as NoteKind,
      number: n.number,
      issuedOn: n.issued_on,
      netAmount: Number(n.net_amount),
      totalAmount: Number(n.total_amount),
      reason: n.reason,
      files: filesOf(n.id),
    })),
    files: filesOf(inv.id),
    quantities: new Map(lines.data.map((l) => [l.id, Number(l.billed_quantity)])),
  };
}

// ---------------------------------------------------------------------------
// El origen de un precio de factura (ficha de la materia prima e impacto de un precio)
// ---------------------------------------------------------------------------
// El proveedor es nulo si la sesión no ve proveedores (costing.price_origins).
export type PriceOrigin = {
  invoiceId: string;
  label: string;
  supplier: string | null;
  canOpen: boolean;
};

export async function getPriceOrigins(priceRecordIds: string[]): Promise<Map<string, PriceOrigin>> {
  const ids = [...new Set(priceRecordIds)];
  if (ids.length === 0) return new Map();
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .rpc("price_origins", { p_price_record_ids: ids });
  // Sin el origen, la ficha se ve igual (con el tipo de comprobante): no se corta la pantalla.
  if (error) return new Map();
  return new Map(
    data.map((o) => [
      o.price_record_id,
      {
        invoiceId: o.invoice_id,
        label: o.label,
        supplier: (o.supplier_name as string | null) ?? null,
        canOpen: o.can_open,
      },
    ]),
  );
}
