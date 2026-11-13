import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";
import { todayInArgentina } from "@/lib/forms/schemas";

// Lecturas de precios (ADR-0029). Todo con la sesión de la persona: la base solo devuelve los precios que
// puede ver (prices.view en su alcance) y las funciones de costo vuelven a pedir el permiso. Si la persona
// no ve precios, estas lecturas no se llaman (la ficha no muestra la tarjeta).

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export type PriceDocument = Database["costing"]["Enums"]["price_document"];
export type PriceSource = Database["costing"]["Enums"]["price_source"];
export type PriceScope = Database["core"]["Enums"]["scope_type"];

export const DOCUMENT_LABELS: Record<PriceDocument, string> = {
  invoice: "Factura con IVA",
  no_invoice: "Precio ingresado (sin factura)",
};
export const SOURCE_LABELS: Record<PriceSource, string> = {
  manual: "Carga manual",
  test_value: "Valor de prueba",
  excel_import: "Importado de Excel",
  invoice: "Factura",
};
export const VAT_RATES = ["21", "10.5", "27", "0"] as const;

export { formatMoney, perBaseLabel } from "@/lib/money";

// ---------------------------------------------------------------------------
// Los precios cargados de una materia prima
// ---------------------------------------------------------------------------
export type PriceRecordRow = {
  id: string;
  productId: string;
  product: string;
  scope: PriceScope;
  place: string;
  validFrom: string;
  packagePrice: number;
  netPackagePrice: number;
  grossPackagePrice: number;
  document: PriceDocument;
  vatRate: number | null;
  source: PriceSource;
};

export async function getIngredientPrices(ingredientId: string): Promise<PriceRecordRow[]> {
  const supabase = await createClient();
  const { data: products, error: productsError } = await supabase
    .schema("catalog")
    .from("purchase_products")
    .select("id, description")
    .eq("ingredient_id", ingredientId)
    .is("deleted_at", null);
  if (productsError) failed("los precios");
  if (products.length === 0) return [];
  const records = await supabase
    .schema("costing")
    .from("price_records")
    .select(
      "id, purchase_product_id, scope_type, brand_id, restaurant_id, valid_from, package_price, net_package_price, gross_package_price, document_type, vat_rate, source",
    )
    .in(
      "purchase_product_id",
      products.map((p) => p.id),
    )
    .order("valid_from", { ascending: false })
    .order("entry_number", { ascending: false })
    .limit(200);
  if (records.error) failed("los precios");
  // Solo los nombres de las marcas y locales que aparecen en los precios.
  const brandIds = [...new Set(records.data.flatMap((r) => (r.brand_id ? [r.brand_id] : [])))];
  const restaurantIds = [
    ...new Set(records.data.flatMap((r) => (r.restaurant_id ? [r.restaurant_id] : []))),
  ];
  const [brands, restaurants] = await Promise.all([
    supabase.schema("org").from("brands").select("id, name").in("id", brandIds),
    supabase.schema("org").from("restaurants").select("id, name").in("id", restaurantIds),
  ]);
  if (brands.error || restaurants.error) failed("los precios");
  const productName = new Map(products.map((p) => [p.id, p.description]));
  const brandName = new Map(brands.data.map((b) => [b.id, b.name]));
  const restaurantName = new Map(restaurants.data.map((r) => [r.id, r.name]));
  return records.data.map((r) => ({
    id: r.id,
    productId: r.purchase_product_id,
    product: productName.get(r.purchase_product_id) ?? "",
    scope: r.scope_type,
    place:
      r.scope_type === "group"
        ? "Todo el grupo"
        : r.scope_type === "brand"
          ? `Marca ${brandName.get(r.brand_id ?? "") ?? ""}`
          : `Local ${restaurantName.get(r.restaurant_id ?? "") ?? ""}`,
    validFrom: r.valid_from,
    packagePrice: Number(r.package_price),
    netPackagePrice: Number(r.net_package_price),
    grossPackagePrice: Number(r.gross_package_price),
    document: r.document_type,
    vatRate: r.vat_rate === null ? null : Number(r.vat_rate),
    source: r.source,
  }));
}

// El vigente de cada producto y lugar (la lista ya viene ordenada del más nuevo al más viejo).
export function currentByProductAndPlace(rows: PriceRecordRow[]): PriceRecordRow[] {
  const seen = new Set<string>();
  const today = todayInArgentina();
  return rows.filter((r) => {
    if (r.validFrom > today) return false;
    const key = `${r.productId}|${r.place}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// ---------------------------------------------------------------------------
// El costo que vale en un local (local → marca → grupo)
// ---------------------------------------------------------------------------
export type LocalCost = Database["costing"]["Functions"]["resolve_price"]["Returns"][number] & {
  restaurant: string;
};

export async function getLocalCost(
  ingredientId: string,
  restaurantId: string,
): Promise<LocalCost | null> {
  const supabase = await createClient();
  const [cost, restaurant] = await Promise.all([
    supabase
      .schema("costing")
      .rpc("resolve_price", { p_ingredient_id: ingredientId, p_restaurant_id: restaurantId }),
    supabase.schema("org").from("restaurants").select("name").eq("id", restaurantId).maybeSingle(),
  ]);
  // Sin permiso en ese local (por ejemplo, el elegido arriba no es suyo para precios): no se muestra.
  if (cost.error || !cost.data?.[0]) return null;
  return { ...cost.data[0], restaurant: restaurant.data?.name ?? "" };
}

// ---------------------------------------------------------------------------
// Dónde puede proponer precios la sesión
// ---------------------------------------------------------------------------
export type PricePlace = { value: string; label: string };

export async function getProposalPlaces(): Promise<PricePlace[]> {
  const supabase = await createClient();
  const [groups, brands, restaurants, groupNames, brandNames, restaurantNames] = await Promise.all([
    supabase.schema("core").rpc("permitted_group_ids", { p_permission: "prices.propose" }),
    supabase.schema("core").rpc("permitted_brand_ids", { p_permission: "prices.propose" }),
    supabase.schema("core").rpc("permitted_restaurant_ids", { p_permission: "prices.propose" }),
    supabase.schema("org").from("groups").select("id, name"),
    supabase.schema("org").from("brands").select("id, name").is("deleted_at", null).order("name"),
    supabase
      .schema("org")
      .from("restaurants")
      .select("id, name")
      .is("deleted_at", null)
      .order("name"),
  ]);
  if (groups.error || brands.error || restaurants.error) failed("tus permisos");
  const ids = (data: unknown) =>
    new Set(Array.isArray(data) ? data.filter((x): x is string => typeof x === "string") : []);
  const g = ids(groups.data);
  const b = ids(brands.data);
  const r = ids(restaurants.data);
  return [
    ...(groupNames.data ?? [])
      .filter((x) => g.has(x.id))
      .map((x) => ({ value: `group:${x.id}`, label: `Todo el grupo (${x.name})` })),
    ...(brandNames.data ?? [])
      .filter((x) => b.has(x.id))
      .map((x) => ({ value: `brand:${x.id}`, label: `La marca ${x.name}` })),
    ...(restaurantNames.data ?? [])
      .filter((x) => r.has(x.id))
      .map((x) => ({ value: `restaurant:${x.id}`, label: `El local ${x.name}` })),
  ];
}

// ---------------------------------------------------------------------------
// Configuración de precios del grupo
// ---------------------------------------------------------------------------
export type PriceSettings = {
  approvalVariationPct: number;
  staleDays: number;
  lookbackDays: number;
  // Umbral del aviso de rendimiento (ADR-0035): desvío de un ensayo contra el estándar, en %.
  yieldAlertPct: number;
};

export async function getPriceSettings(groupId: string): Promise<PriceSettings> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("costing")
    .from("price_settings")
    .select("approval_variation_pct, stale_days, lookback_days, yield_alert_pct")
    .eq("group_id", groupId)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) failed("la configuración de precios");
  // Sin fila, valen los valores por defecto (ADR-0029).
  return {
    approvalVariationPct: data ? Number(data.approval_variation_pct) : 15,
    staleDays: data?.stale_days ?? 30,
    lookbackDays: data?.lookback_days ?? 30,
    yieldAlertPct: data ? Number(data.yield_alert_pct) : 10,
  };
}

// ---------------------------------------------------------------------------
// La tabla de productos de compra de la ficha (ADR-0043)
// ---------------------------------------------------------------------------
// Por producto activo, el precio que vale en el local elegido arriba, con la misma regla que el motor de costos. Sin
// prices.view en ese local, la base no devuelve filas.
export type ProductPrice = {
  productId: string;
  priceRecordId: string | null;
  priceLevel: string | null;
  inherited: boolean | null;
  validFrom: string | null;
  packageCost: number | null;
  unitCost: number | null;
  baseUnit: string;
  stale: boolean | null;
  daysOld: number | null;
  status: string;
  // Un producto que ya no se compra aparece solo si tiene el precio que vale (puede ser el que usa el costo).
  isActive: boolean;
};

export async function getProductPrices(
  ingredientId: string,
  restaurantId: string,
): Promise<ProductPrice[]> {
  const client = await createClient();
  const { data, error } = await client.schema("costing").rpc("ingredient_product_prices", {
    p_ingredient_id: ingredientId,
    p_restaurant_id: restaurantId,
  });
  if (error) failed("los precios de los productos");
  return data.map((r) => ({
    productId: r.purchase_product_id,
    priceRecordId: r.price_record_id,
    priceLevel: r.price_level,
    inherited: r.inherited,
    validFrom: r.valid_from,
    packageCost: r.package_cost,
    unitCost: r.unit_cost,
    baseUnit: r.base_unit,
    stale: r.stale,
    daysOld: r.days_old,
    status: r.status,
    isActive: r.is_active,
  }));
}
