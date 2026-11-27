import { z } from "zod";

import { type PriceListStatus, type StatusFilter } from "@/lib/price-lists";
import { createClient } from "@/lib/supabase/server";

// Lecturas de listas de precios y de la cola de mapeo (Fase 3, ADR-0052). Todo pasa por la base con la sesión de la
// persona: la RLS decide qué ve (el cocinero no ve listas). Si una lectura falla, se corta con un error en lugar de
// mostrar «no hay datos».

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

const listRow = z.object({
  id: z.string(),
  supplier_id: z.string(),
  supplier_name: z.string(),
  received_on: z.string(),
  valid_from: z.string(),
  status: z.enum(["received", "accepted", "replaced", "voided"]),
  expired: z.boolean(),
  items: z.coerce.number(),
  queued: z.coerce.number(),
  version: z.coerce.number(),
  total: z.coerce.number(),
});
export type PriceListRow = Omit<z.infer<typeof listRow>, "total">;

export async function getPriceLists(filter: {
  supplierId?: string;
  status?: StatusFilter;
  page: number;
  size: number;
}): Promise<{ rows: PriceListRow[]; total: number }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("purchasing").rpc("price_list_list", {
    p_supplier_id: filter.supplierId,
    p_status: filter.status,
    p_limit: filter.size,
    p_offset: filter.page * filter.size,
  });
  if (error) failed("las listas de precios");
  const parsed = z.array(listRow).safeParse(data);
  if (!parsed.success) failed("las listas de precios");
  return {
    rows: parsed.data.map((r) => {
      const { total, ...row } = r;
      void total;
      return row;
    }),
    total: parsed.data[0]?.total ?? 0,
  };
}

export type PriceListItem = {
  id: string;
  lineOrder: number;
  rawName: string;
  sku: string | null;
  mapped: boolean;
  listPrice: number;
  bonus1Pct: number;
  bonus2Pct: number;
  bonusPerUnit: number;
  vatRate: number;
  net: number | null;
  previousNet: number | null;
  changePct: number | null;
  // Los controles (ADR-0071): si la suba pasa el umbral de Dirección, «Revisar» a 10 veces y el precio por unidad de uso.
  overThreshold: boolean;
  review: boolean;
  perUsePrice: number | null;
  perUseUnit: string | null;
  purchaseProductId: string | null;
};

// Una versión de la lista (ADR-0071): la 1 cargada y sus correcciones.
export type PriceListVersion = {
  id: string;
  version: number;
  status: PriceListStatus;
  createdAt: string;
};

export type PriceListDetail = {
  id: string;
  supplierId: string;
  supplierName: string;
  receivedOn: string;
  validFrom: string;
  status: PriceListStatus;
  expired: boolean;
  notes: string | null;
  version: number;
  previousVersionId: string | null;
  voidedReason: string | null;
  voidedAt: string | null;
  versions: PriceListVersion[];
  items: PriceListItem[];
  attachments: { id: string; path: string; page: number; url: string | null }[];
};

const itemRow = z.object({
  id: z.string(),
  line_order: z.number(),
  raw_name: z.string(),
  supplier_sku: z.string().nullable(),
  purchase_product_id: z.string().nullable(),
  list_price: z.coerce.number(),
  bonus1_pct: z.coerce.number(),
  bonus2_pct: z.coerce.number(),
  bonus_per_unit_amount: z.coerce.number(),
  vat_rate: z.coerce.number(),
});
const changeRow = z.object({
  purchase_product_id: z.string().nullable(),
  raw_name: z.string(),
  net_price: z.coerce.number().nullable(),
  previous_net_price: z.coerce.number().nullable(),
  change_pct: z.coerce.number().nullable(),
  over_threshold: z.boolean().nullable(),
  review: z.boolean().nullable(),
  per_use_price: z.coerce.number().nullable(),
  per_use_unit: z.string().nullable(),
});

export async function getPriceListDetail(id: string): Promise<PriceListDetail | null> {
  const supabase = await createClient();
  const purchasing = supabase.schema("purchasing");
  const [list, items, changes, attachments] = await Promise.all([
    purchasing
      .from("price_lists")
      .select(
        "id, supplier_id, received_on, valid_from, status, notes, version, previous_version_id, voided_reason, voided_at",
      )
      .eq("id", id)
      .maybeSingle(),
    purchasing
      .from("price_list_items")
      .select(
        "id, line_order, raw_name, supplier_sku, purchase_product_id, list_price, bonus1_pct, bonus2_pct, bonus_per_unit_amount, vat_rate",
      )
      .eq("price_list_id", id)
      .order("line_order"),
    purchasing.rpc("price_list_changes", { p_price_list_id: id }),
    purchasing
      .from("attachments")
      .select("id, storage_path, page")
      .eq("source_id", id)
      .order("page"),
  ]);
  if (list.error || items.error || changes.error || attachments.error)
    failed("la lista de precios");
  if (!list.data) return null;
  const [supplier, expired, chain] = await Promise.all([
    supabase
      .schema("catalog")
      .from("suppliers")
      .select("name, trade_name")
      .eq("id", list.data.supplier_id)
      .maybeSingle(),
    purchasing.rpc("price_list_expired", { p_id: id }),
    // Las versiones de la misma lista: misma vigencia y proveedor; se arma la cadena por previous_version_id.
    purchasing
      .from("price_lists")
      .select("id, version, status, created_at, previous_version_id")
      .eq("supplier_id", list.data.supplier_id)
      .eq("valid_from", list.data.valid_from)
      .order("version"),
  ]);
  if (supplier.error || expired.error || chain.error) failed("la lista de precios");
  const parsedItems = z.array(itemRow).safeParse(items.data);
  const parsedChanges = z.array(changeRow).safeParse(changes.data);
  if (!parsedItems.success || !parsedChanges.success) failed("la lista de precios");
  // La variación sale por renglón y en el mismo orden: se cruzan por producto y nombre.
  // Enlaces firmados por 5 minutos para abrir cada archivo (Storage controla que la sesión lo pueda leer).
  const files = await Promise.all(
    (attachments.data ?? []).map(async (a) => {
      // Un Excel o un CSV del proveedor se descarga, no se abre en el navegador (revisión de seguridad).
      const download = /\.(xlsx|csv)$/.test(a.storage_path);
      const signed = await supabase.storage
        .from("purchasing-documents")
        .createSignedUrl(a.storage_path, 300, download ? { download: true } : undefined);
      return { id: a.id, path: a.storage_path, page: a.page, url: signed.data?.signedUrl ?? null };
    }),
  );
  const byKey = new Map(
    parsedChanges.data.map((c) => [`${c.purchase_product_id ?? ""}|${c.raw_name}`, c]),
  );
  return {
    id: list.data.id,
    supplierId: list.data.supplier_id,
    supplierName: supplier.data?.trade_name || supplier.data?.name || "Proveedor",
    receivedOn: list.data.received_on,
    validFrom: list.data.valid_from,
    status: list.data.status,
    expired: expired.data === true,
    notes: list.data.notes,
    version: list.data.version,
    previousVersionId: list.data.previous_version_id,
    voidedReason: list.data.voided_reason,
    voidedAt: list.data.voided_at,
    versions: versionChain(list.data.id, chain.data ?? []),
    items: parsedItems.data.map((i) => {
      const c = byKey.get(`${i.purchase_product_id ?? ""}|${i.raw_name}`);
      return {
        id: i.id,
        lineOrder: i.line_order,
        rawName: i.raw_name,
        sku: i.supplier_sku,
        mapped: i.purchase_product_id !== null,
        listPrice: i.list_price,
        bonus1Pct: i.bonus1_pct,
        bonus2Pct: i.bonus2_pct,
        bonusPerUnit: i.bonus_per_unit_amount,
        vatRate: i.vat_rate,
        net: c?.net_price ?? null,
        previousNet: c?.previous_net_price ?? null,
        changePct: c?.change_pct ?? null,
        overThreshold: c?.over_threshold ?? false,
        review: c?.review ?? false,
        perUsePrice: c?.per_use_price ?? null,
        perUseUnit: c?.per_use_unit ?? null,
        purchaseProductId: i.purchase_product_id,
      };
    }),
    attachments: files,
  };
}

// Las versiones de una lista: desde la 1 hasta la última corrección, siguiendo previous_version_id.
function versionChain(
  id: string,
  rows: {
    id: string;
    version: number;
    status: PriceListStatus;
    created_at: string;
    previous_version_id: string | null;
  }[],
): PriceListVersion[] {
  const byId = new Map(rows.map((r) => [r.id, r]));
  const next = new Map(
    rows.filter((r) => r.previous_version_id).map((r) => [r.previous_version_id!, r]),
  );
  let first = byId.get(id);
  while (first?.previous_version_id && byId.has(first.previous_version_id))
    first = byId.get(first.previous_version_id);
  const out: PriceListVersion[] = [];
  for (let r = first; r && out.length < 50; r = next.get(r.id))
    out.push({ id: r.id, version: r.version, status: r.status, createdAt: r.created_at });
  return out;
}

// La lista vigente de un proveedor (la aceptada), para el indicador de su ficha. Vacío si no ve listas o no hay.
export async function getCurrentPriceList(supplierId: string): Promise<{
  id: string;
  validFrom: string;
  expired: boolean;
  items: number;
  total: number;
  // Es una recibida sin aceptar (no hay aceptada).
  pending: boolean;
} | null> {
  const supabase = await createClient();
  const [current, all] = await Promise.all([
    supabase.schema("purchasing").rpc("price_list_list", {
      p_supplier_id: supplierId,
      p_status: undefined,
      p_limit: 50,
      p_offset: 0,
    }),
    supabase
      .schema("purchasing")
      .from("price_lists")
      .select("id", { count: "exact", head: true })
      .eq("supplier_id", supplierId),
  ]);
  if (current.error || all.error) failed("la lista de precios del proveedor");
  const parsed = z.array(listRow).safeParse(current.data);
  if (!parsed.success) failed("la lista de precios del proveedor");
  const accepted = parsed.data.find((r) => r.status === "accepted");
  // Sin aceptada, la recibida más nueva (para no invitar a cargarla otra vez).
  const received = parsed.data.find((r) => r.status === "received");
  if (!accepted)
    return received
      ? {
          id: received.id,
          validFrom: received.valid_from,
          expired: false,
          items: received.items,
          total: all.count ?? 0,
          pending: true,
        }
      : null;
  return {
    pending: false,
    id: accepted.id,
    validFrom: accepted.valid_from,
    expired: accepted.expired,
    items: accepted.items,
    total: all.count ?? 0,
  };
}

// ---------------------------------------------------------------------------
// Cola de mapeo
// ---------------------------------------------------------------------------
export type UnmappedArticle = {
  id: string;
  supplierId: string;
  supplierName: string;
  rawName: string;
  sku: string | null;
  packageHint: string | null;
  foundIn: string;
  createdAt: string;
  suggested: { id: string; description: string } | null;
};

export async function getUnmappedArticles(filter: {
  supplierId?: string;
  page: number;
  size: number;
}): Promise<{ rows: UnmappedArticle[]; total: number }> {
  const supabase = await createClient();
  let query = supabase
    .schema("purchasing")
    .from("unmapped_articles")
    .select(
      "id, supplier_id, raw_name, supplier_sku, package_hint, found_in, created_at, suggested_product_id",
      {
        count: "exact",
      },
    )
    .eq("status", "pending")
    .order("created_at", { ascending: true })
    .order("raw_name")
    .range(filter.page * filter.size, filter.page * filter.size + filter.size - 1);
  if (filter.supplierId) query = query.eq("supplier_id", filter.supplierId);
  const { data, error, count } = await query;
  if (error) failed("los artículos sin mapear");
  const supplierIds = [...new Set(data.map((a) => a.supplier_id))];
  const names = new Map<string, string>();
  if (supplierIds.length > 0) {
    const suppliers = await supabase
      .schema("catalog")
      .from("suppliers")
      .select("id, name, trade_name")
      .in("id", supplierIds);
    if (suppliers.error) failed("los proveedores de la cola");
    for (const s of suppliers.data) names.set(s.id, s.trade_name || s.name);
  }
  // Lo que sugirió Compras al elegir a mano en una lista (ADR-0071): el chef lo confirma.
  const suggestedIds = [
    ...new Set(data.map((a) => a.suggested_product_id).filter((v): v is string => !!v)),
  ];
  const suggested = new Map<string, string>();
  if (suggestedIds.length > 0) {
    const products = await supabase
      .schema("catalog")
      .from("purchase_products")
      .select("id, description")
      .in("id", suggestedIds);
    if (products.error) failed("los productos sugeridos");
    for (const p of products.data) suggested.set(p.id, p.description);
  }
  return {
    rows: data.map((a) => ({
      id: a.id,
      supplierId: a.supplier_id,
      supplierName: names.get(a.supplier_id) ?? "Proveedor",
      rawName: a.raw_name,
      sku: a.supplier_sku,
      packageHint: a.package_hint,
      foundIn: a.found_in,
      createdAt: a.created_at,
      suggested:
        a.suggested_product_id && suggested.has(a.suggested_product_id)
          ? { id: a.suggested_product_id, description: suggested.get(a.suggested_product_id)! }
          : null,
    })),
    total: count ?? 0,
  };
}

// Cuántos esperan en la cola (para «Artículos sin mapear (N)» en Materias primas). null si no la ve.
export async function countUnmappedArticles(): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .schema("purchasing")
    .from("unmapped_articles")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending");
  if (error) failed("los artículos sin mapear");
  return count ?? 0;
}

// Los productos activos de un proveedor, para «Es el mismo que…».
export async function getSupplierProducts(
  supplierId: string,
): Promise<{ id: string; code: string; description: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("purchase_products")
    .select("id, code, description")
    .eq("supplier_id", supplierId)
    .eq("is_active", true)
    .order("description");
  if (error) failed("los productos del proveedor");
  return data;
}

// Las materias primas activas, para elegir a cuál corresponde un artículo (también las de Limpieza o Descartables).
export async function searchIngredients(
  query: string,
): Promise<{ id: string; code: string; name: string }[]> {
  const q = query.trim().slice(0, 80);
  if (q.length < 2) return [];
  const supabase = await createClient();
  // % y _ se buscan como letras, no como comodines; comas, paréntesis y comillas no pueden armar otro filtro.
  const safe = q.replace(/[,()"]/g, " ").replace(/[\\%_]/g, (c) => `\\${c}`);
  const { data, error } = await supabase
    .schema("catalog")
    .from("ingredients")
    .select("id, code, name")
    .eq("is_active", true)
    .or(`name.ilike.%${safe}%,code.ilike.${safe}%`)
    .order("name")
    .limit(12);
  if (error) failed("las materias primas");
  return data;
}
