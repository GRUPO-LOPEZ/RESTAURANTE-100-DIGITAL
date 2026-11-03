import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";

// Lecturas del panel de control de la estructura (ADR-0031). Todo con la sesión de la persona: la base
// decide qué marcas, locales y razones sociales ve (RLS) y qué puede cambiar (las funciones de org.*).
// Los permisos de acá solo deciden qué formularios se muestran.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export type UnitStatus = Database["org"]["Enums"]["unit_status"];
export type SiteType = Database["org"]["Enums"]["site_type"];
export type VatCondition = Database["org"]["Enums"]["vat_condition"];

export const BRAND_STATUS_LABELS: Record<UnitStatus, string> = {
  active: "Activa",
  inactive: "Inactiva",
};
export const RESTAURANT_STATUS_LABELS: Record<UnitStatus, string> = {
  active: "Abierto",
  inactive: "Cerrado",
};
export const SITE_TYPE_LABELS: Record<SiteType, string> = {
  restaurant: "Restaurante",
  central_kitchen: "Cocina central",
  production_unit: "Unidad productiva",
};
export const VAT_CONDITION_LABELS: Record<VatCondition, string> = {
  registered: "Responsable inscripto",
  monotax: "Monotributo",
  exempt: "Exento",
};

// CUIT con guiones, para mostrar (30-12345678-9).
export function formatTaxId(taxId: string): string {
  return /^\d{11}$/.test(taxId)
    ? `${taxId.slice(0, 2)}-${taxId.slice(2, 10)}-${taxId.slice(10)}`
    : taxId;
}

// ---------------------------------------------------------------------------
// Dónde puede administrar la sesión (org.manage): grupo, marcas y locales
// ---------------------------------------------------------------------------
export type OrgPermissions = { groups: string[]; brands: string[]; restaurants: string[] };

export async function getOrgPermissions(): Promise<OrgPermissions> {
  const supabase = await createClient();
  const [groups, brands, restaurants] = await Promise.all([
    supabase.schema("core").rpc("permitted_group_ids", { p_permission: "org.manage" }),
    supabase.schema("core").rpc("permitted_brand_ids", { p_permission: "org.manage" }),
    supabase.schema("core").rpc("permitted_restaurant_ids", { p_permission: "org.manage" }),
  ]);
  if (groups.error || brands.error || restaurants.error) failed("tus permisos");
  const ids = (data: unknown) =>
    Array.isArray(data) ? data.filter((x): x is string => typeof x === "string") : [];
  return { groups: ids(groups.data), brands: ids(brands.data), restaurants: ids(restaurants.data) };
}

// ---------------------------------------------------------------------------
// Marcas
// ---------------------------------------------------------------------------
export type BrandRow = {
  id: string;
  groupId: string;
  name: string;
  code: string;
  status: UnitStatus;
  restaurants: number;
};

export async function getBrands(): Promise<BrandRow[]> {
  const supabase = await createClient();
  const [brands, restaurants] = await Promise.all([
    supabase
      .schema("org")
      .from("brands")
      .select("id, group_id, name, code, status")
      .is("deleted_at", null)
      .order("name"),
    supabase.schema("org").from("restaurants").select("brand_id").is("deleted_at", null),
  ]);
  if (brands.error || restaurants.error) failed("las marcas");
  const count = new Map<string, number>();
  for (const r of restaurants.data) count.set(r.brand_id, (count.get(r.brand_id) ?? 0) + 1);
  return brands.data.map((b) => ({
    id: b.id,
    groupId: b.group_id,
    name: b.name,
    code: b.code,
    status: b.status,
    restaurants: count.get(b.id) ?? 0,
  }));
}

export async function getBrand(id: string): Promise<BrandRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("org")
    .from("brands")
    .select("id, group_id, name, code, status")
    .eq("id", id)
    .is("deleted_at", null)
    .maybeSingle();
  if (error) failed("la marca");
  if (!data) return null;
  return {
    id: data.id,
    groupId: data.group_id,
    name: data.name,
    code: data.code,
    status: data.status,
    restaurants: 0,
  };
}

// ---------------------------------------------------------------------------
// Locales
// ---------------------------------------------------------------------------
export type RestaurantRow = {
  id: string;
  groupId: string;
  brandId: string;
  name: string;
  code: string | null;
  status: UnitStatus;
  siteType: SiteType;
  legalEntityId: string | null;
};

export type RestaurantDetail = RestaurantRow & {
  address: string | null;
  locality: string | null;
  phone: string | null;
  openedOn: string | null;
  areas: { id: string; name: string }[];
};

const RESTAURANT_COLUMNS =
  "id, group_id, brand_id, name, code, status, site_type, legal_entity_id, address, locality, phone, opened_on";

export async function getRestaurants(brandId?: string): Promise<RestaurantRow[]> {
  const supabase = await createClient();
  let query = supabase
    .schema("org")
    .from("restaurants")
    .select(RESTAURANT_COLUMNS)
    .is("deleted_at", null)
    .order("name");
  if (brandId) query = query.eq("brand_id", brandId);
  const { data, error } = await query;
  if (error) failed("los locales");
  return data.map((r) => ({
    id: r.id,
    groupId: r.group_id,
    brandId: r.brand_id,
    name: r.name,
    code: r.code,
    status: r.status,
    siteType: r.site_type,
    legalEntityId: r.legal_entity_id,
  }));
}

export async function getRestaurant(id: string): Promise<RestaurantDetail | null> {
  const supabase = await createClient();
  const [restaurant, areas] = await Promise.all([
    supabase
      .schema("org")
      .from("restaurants")
      .select(RESTAURANT_COLUMNS)
      .eq("id", id)
      .is("deleted_at", null)
      .maybeSingle(),
    supabase
      .schema("org")
      .from("areas")
      .select("id, name")
      .eq("restaurant_id", id)
      .is("deleted_at", null)
      .order("name"),
  ]);
  if (restaurant.error || areas.error) failed("el local");
  const r = restaurant.data;
  if (!r) return null;
  return {
    id: r.id,
    groupId: r.group_id,
    brandId: r.brand_id,
    name: r.name,
    code: r.code,
    status: r.status,
    siteType: r.site_type,
    legalEntityId: r.legal_entity_id,
    address: r.address,
    locality: r.locality,
    phone: r.phone,
    openedOn: r.opened_on,
    areas: areas.data,
  };
}

// ---------------------------------------------------------------------------
// Razones sociales
// ---------------------------------------------------------------------------
export type LegalEntityRow = {
  id: string;
  groupId: string;
  name: string;
  taxId: string;
  vatCondition: VatCondition;
};

export async function getLegalEntities(): Promise<LegalEntityRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("org")
    .from("legal_entities")
    .select("id, group_id, name, tax_id, vat_condition")
    .is("deleted_at", null)
    .order("name");
  if (error) failed("las razones sociales");
  return data.map((l) => ({
    id: l.id,
    groupId: l.group_id,
    name: l.name,
    taxId: l.tax_id,
    vatCondition: l.vat_condition,
  }));
}
