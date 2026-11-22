import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";
import type { LegalEntityRow, SiteType, UnitStatus, VatCondition } from "@/lib/org";

// Lecturas del Panel de control y de las fichas de local y de razón social en una pantalla (Tanda 1 de Soy, ADR-0061).
// Todo con la sesión de la persona: la base decide qué ve (RLS) y qué puede cambiar (org.restaurant_sheet_state y
// org.legal_entity_sheet_state). Lo de acá solo decide qué se muestra.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export type LegalForm = Database["org"]["Enums"]["legal_form"];
export type IncomeTaxStatus = Database["org"]["Enums"]["income_tax_status"];
export type GrossIncomeRegime = Database["org"]["Enums"]["gross_income_regime"];

export const LEGAL_FORM_LABELS: Record<LegalForm, string> = {
  srl: "S.R.L.",
  sa: "S.A.",
  sas: "S.A.S.",
  person: "Persona",
};
export const INCOME_TAX_LABELS: Record<IncomeTaxStatus, string> = {
  registered: "Inscripta",
  exempt: "Exenta",
  not_subject: "No alcanzada",
};
export const GROSS_INCOME_LABELS: Record<GrossIncomeRegime, string> = {
  multilateral: "Conv. Multilateral",
  local: "Local",
  exempt: "Exento",
};
export const VAT_SHORT_LABELS: Record<VatCondition, string> = {
  registered: "Resp. inscripto",
  monotax: "Monotributo",
  exempt: "Exento",
};

/** Hoy en la Argentina (AAAA-MM-DD). */
export function todayAr(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires" }).format(
    new Date(),
  );
}

export type Province = { code: string; name: string };

export async function getProvinces(): Promise<Province[]> {
  const client = await createClient();
  const { data, error } = await client
    .schema("org")
    .from("provinces")
    .select("code, name")
    .order("name");
  if (error) failed("las provincias");
  return data;
}

// ---------------------------------------------------------------------------
// Locales
// ---------------------------------------------------------------------------
export type PlaceRow = {
  id: string;
  groupId: string;
  brandId: string;
  name: string;
  code: string | null;
  number: number;
  status: UnitStatus;
  siteType: SiteType;
  legalEntityId: string | null;
  zone: string | null;
  opening: boolean;
  address: string | null;
  locality: string | null;
  province: string | null;
  postalCode: string | null;
  phone: string | null;
  openedOn: string | null;
  latitude: number | null;
  longitude: number | null;
  geoStatus: "found" | "not_found" | null;
  geoLabel: string | null;
  missing: string[];
};

const PLACE_COLUMNS =
  "id, group_id, brand_id, name, code, number, status, site_type, legal_entity_id, zone, opening, address, locality, province, postal_code, phone, opened_on, latitude, longitude, geo_status, geo_label";

type PlaceDbRow = Pick<
  Database["org"]["Tables"]["restaurants"]["Row"],
  | "id"
  | "group_id"
  | "brand_id"
  | "name"
  | "code"
  | "number"
  | "status"
  | "site_type"
  | "legal_entity_id"
  | "zone"
  | "opening"
  | "address"
  | "locality"
  | "province"
  | "postal_code"
  | "phone"
  | "opened_on"
  | "latitude"
  | "longitude"
  | "geo_status"
  | "geo_label"
>;

// La misma lista que org.restaurant_missing (marca y tipo siempre están; la razón social es opcional).
function placeMissing(r: PlaceDbRow): string[] {
  const out: string[] = [];
  if (!r.zone?.trim()) out.push("zona");
  if (!r.opened_on) out.push("fecha de apertura");
  if (!r.address?.trim()) out.push("dirección");
  if (!r.locality?.trim()) out.push("localidad");
  if (!r.phone?.trim()) out.push("teléfono");
  return out;
}

function toPlace(r: PlaceDbRow): PlaceRow {
  return {
    id: r.id,
    groupId: r.group_id,
    brandId: r.brand_id,
    name: r.name,
    code: r.code,
    number: r.number,
    status: r.status,
    siteType: r.site_type,
    legalEntityId: r.legal_entity_id,
    zone: r.zone,
    opening: r.opening,
    address: r.address,
    locality: r.locality,
    province: r.province,
    postalCode: r.postal_code,
    phone: r.phone,
    openedOn: r.opened_on,
    latitude: r.latitude === null ? null : Number(r.latitude),
    longitude: r.longitude === null ? null : Number(r.longitude),
    geoStatus: r.geo_status,
    geoLabel: r.geo_label,
    missing: placeMissing(r),
  };
}

/** El estado con palabra de un local: Cerrado, En apertura o Abierto. */
export function placeState(p: { status: UnitStatus; opening: boolean }): {
  label: string;
  status: "ok" | "info" | "none";
} {
  if (p.status !== "active") return { label: "Cerrado", status: "none" };
  if (p.opening) return { label: "En apertura", status: "info" };
  return { label: "Abierto", status: "ok" };
}

// ---------------------------------------------------------------------------
// Panel de control: marcas con sus locales y razones sociales
// ---------------------------------------------------------------------------
export type PanelBrand = {
  id: string;
  groupId: string;
  name: string;
  shortName: string;
  code: string;
  number: number;
  status: UnitStatus;
  places: PlaceRow[];
};

export type PanelLegalEntity = LegalEntityRow & {
  places: number;
  documentIssuedOn: string | null;
};

export type StructurePanel = {
  groupId: string | null;
  brands: PanelBrand[];
  legalEntities: PanelLegalEntity[];
};

export async function getStructurePanel(): Promise<StructurePanel> {
  const client = await createClient();
  const [brands, places, entities, documents] = await Promise.all([
    client
      .schema("org")
      .from("brands")
      .select("id, group_id, name, short_name, code, number, status")
      .is("deleted_at", null)
      .order("number"),
    client
      .schema("org")
      .from("restaurants")
      .select(PLACE_COLUMNS)
      .is("deleted_at", null)
      .order("number"),
    client
      .schema("org")
      .from("legal_entities")
      .select("id, group_id, name, tax_id, vat_condition")
      .is("deleted_at", null)
      .order("name"),
    client.schema("org").from("legal_entity_documents").select("legal_entity_id, issued_on"),
  ]);
  if (brands.error || places.error || entities.error || documents.error)
    failed("la estructura del grupo");
  const rows = places.data.map(toPlace);
  const latest = new Map<string, string>();
  for (const d of documents.data)
    if ((latest.get(d.legal_entity_id) ?? "") < d.issued_on)
      latest.set(d.legal_entity_id, d.issued_on);
  const usedBy = new Map<string, number>();
  for (const p of rows)
    if (p.legalEntityId && p.status === "active")
      usedBy.set(p.legalEntityId, (usedBy.get(p.legalEntityId) ?? 0) + 1);
  return {
    groupId: brands.data[0]?.group_id ?? entities.data[0]?.group_id ?? null,
    brands: brands.data.map((b) => ({
      id: b.id,
      groupId: b.group_id,
      name: b.name,
      shortName: b.short_name,
      code: b.code,
      number: b.number,
      status: b.status,
      places: rows.filter((p) => p.brandId === b.id),
    })),
    legalEntities: entities.data.map((l) => ({
      id: l.id,
      groupId: l.group_id,
      name: l.name,
      taxId: l.tax_id,
      vatCondition: l.vat_condition,
      places: usedBy.get(l.id) ?? 0,
      documentIssuedOn: latest.get(l.id) ?? null,
    })),
  };
}

// ---------------------------------------------------------------------------
// Ficha del local
// ---------------------------------------------------------------------------
export type PlaceSheet = PlaceRow & {
  brand: { id: string; name: string; shortName: string; code: string };
  areas: { id: string; name: string; active: boolean }[];
  legalEntity: { id: string; name: string; taxId: string; vatCondition: VatCondition } | null;
  legalFrom: string | null;
  stamp: string | null;
  canEdit: boolean;
  canEditBrandLevel: boolean;
  canEditGroupLevel: boolean;
  // Personas activas y recetas asignadas: null si la sesión no las puede ver.
  people: number | null;
  recipes: number | null;
  // La constancia de ARCA de su razón social: si la sesión la ve, y la fecha de la última (null si no hay).
  document: { visible: boolean; issuedOn: string | null };
};

export async function getPlaceSheet(id: string): Promise<PlaceSheet | null> {
  const client = await createClient();
  const [place, areas, state] = await Promise.all([
    client
      .schema("org")
      .from("restaurants")
      .select(PLACE_COLUMNS)
      .eq("id", id)
      .is("deleted_at", null)
      .maybeSingle(),
    client
      .schema("org")
      .from("areas")
      .select("id, name, is_active")
      .eq("restaurant_id", id)
      .is("deleted_at", null)
      .order("name"),
    client.schema("org").rpc("restaurant_sheet_state", { p_id: id }),
  ]);
  if (place.error || areas.error || state.error) failed("el local");
  if (!place.data) return null;
  const p = toPlace(place.data);
  const s = (state.data ?? {}) as {
    stamp?: string;
    can_edit?: boolean;
    can_edit_brand_level?: boolean;
    can_edit_group_level?: boolean;
  };
  const [brand, entity, history, overview, recipes, seeEntity, documents] = await Promise.all([
    client
      .schema("org")
      .from("brands")
      .select("id, name, short_name, code")
      .eq("id", p.brandId)
      .maybeSingle(),
    p.legalEntityId
      ? client
          .schema("org")
          .from("legal_entities")
          .select("id, name, tax_id, vat_condition")
          .eq("id", p.legalEntityId)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    client
      .schema("org")
      .from("restaurant_legal_entities")
      .select("valid_from")
      .eq("restaurant_id", id)
      .is("deleted_at", null)
      .order("valid_from", { ascending: false })
      .limit(1)
      .maybeSingle(),
    client.schema("core").rpc("users_overview", { p_restaurant_id: id }),
    client
      .schema("recipes")
      .from("recipe_assignments")
      .select("id", { count: "exact", head: true })
      .eq("restaurant_id", id)
      .is("deleted_at", null)
      .is("valid_to", null),
    p.legalEntityId
      ? client.schema("org").rpc("can_see_legal_entity", { p_legal_entity_id: p.legalEntityId })
      : Promise.resolve({ data: false, error: null }),
    p.legalEntityId
      ? client
          .schema("org")
          .from("legal_entity_documents")
          .select("issued_on")
          .eq("legal_entity_id", p.legalEntityId)
          .order("issued_on", { ascending: false })
          .limit(1)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (brand.error || !brand.data) failed("la marca del local");
  const active = (overview.data as { active?: number } | null)?.active;
  return {
    ...p,
    brand: {
      id: brand.data.id,
      name: brand.data.name,
      shortName: brand.data.short_name,
      code: brand.data.code,
    },
    areas: areas.data.map((a) => ({ id: a.id, name: a.name, active: a.is_active })),
    legalEntity: entity.data
      ? {
          id: entity.data.id,
          name: entity.data.name,
          taxId: entity.data.tax_id,
          vatCondition: entity.data.vat_condition,
        }
      : null,
    legalFrom: history.data?.valid_from ?? null,
    stamp: s.stamp ?? null,
    canEdit: s.can_edit === true,
    canEditBrandLevel: s.can_edit_brand_level === true,
    canEditGroupLevel: s.can_edit_group_level === true,
    people: overview.error || typeof active !== "number" ? null : active,
    recipes: recipes.error ? null : (recipes.count ?? 0),
    document: {
      visible: seeEntity.data === true && !documents.error,
      issuedOn: documents.data?.[0]?.issued_on ?? null,
    },
  };
}

// ---------------------------------------------------------------------------
// Ficha de la razón social
// ---------------------------------------------------------------------------
export type LegalEntitySheet = {
  id: string;
  groupId: string;
  name: string;
  taxId: string;
  vatCondition: VatCondition;
  legalForm: LegalForm | null;
  activityStart: string | null;
  tradeName: string | null;
  fiscalStreet: string | null;
  fiscalLocality: string | null;
  fiscalPostalCode: string | null;
  fiscalProvince: string | null;
  electronicDomicile: string | null;
  incomeTax: IncomeTaxStatus | null;
  grossIncomeRegime: GrossIncomeRegime | null;
  grossIncomeNumber: string | null;
  grossIncomeProvince: string | null;
  isEmployer: boolean;
  isWithholdingAgent: boolean;
  isPerceptionAgent: boolean;
  activities: { id: string; code: string; description: string; primary: boolean }[];
  places: {
    id: string;
    code: string | null;
    name: string;
    brandId: string;
    validFrom: string | null;
  }[];
  documents: { id: string; issuedOn: string; path: string }[];
  missing: string[];
  stamp: string | null;
  canEdit: boolean;
  // Compras del mes a su nombre: solo para quien ve las facturas (null si no).
  monthPurchases: { total: number; invoices: number } | null;
  // Si la sesión ve facturas pero la consulta falló: el indicador lo dice (no inventa otro motivo).
  monthPurchasesFailed: boolean;
};

const ENTITY_COLUMNS =
  "id, group_id, name, tax_id, vat_condition, legal_form, activity_start, trade_name, fiscal_street, fiscal_locality, fiscal_postal_code, fiscal_province, electronic_domicile, income_tax, gross_income_regime, gross_income_number, gross_income_province, is_employer, is_withholding_agent, is_perception_agent";

export async function getLegalEntitySheet(
  id: string,
  options: { seeInvoices: boolean },
): Promise<LegalEntitySheet | null> {
  const client = await createClient();
  const [entity, activities, history, documents, places, state] = await Promise.all([
    client
      .schema("org")
      .from("legal_entities")
      .select(ENTITY_COLUMNS)
      .eq("id", id)
      .is("deleted_at", null)
      .maybeSingle(),
    client
      .schema("org")
      .from("legal_entity_activities")
      .select("id, code, description, is_primary")
      .eq("legal_entity_id", id)
      .is("deleted_at", null)
      .order("is_primary", { ascending: false })
      .order("code"),
    client
      .schema("org")
      .from("restaurant_legal_entities")
      .select("restaurant_id, valid_from")
      .eq("legal_entity_id", id)
      .is("deleted_at", null),
    client
      .schema("org")
      .from("legal_entity_documents")
      .select("id, issued_on, storage_path")
      .eq("legal_entity_id", id)
      .order("issued_on", { ascending: false }),
    client
      .schema("org")
      .from("restaurants")
      .select("id, code, name, brand_id")
      .eq("legal_entity_id", id)
      .is("deleted_at", null)
      .order("name"),
    client.schema("org").rpc("legal_entity_sheet_state", { p_id: id }),
  ]);
  if (
    entity.error ||
    activities.error ||
    history.error ||
    documents.error ||
    places.error ||
    state.error
  )
    failed("la razón social");
  const e = entity.data;
  if (!e) return null;
  const s = (state.data ?? {}) as { stamp?: string; can_edit?: boolean; missing?: string[] };
  // Desde cuándo factura cada local a su nombre: el tramo más nuevo con esta razón social.
  const from = new Map<string, string>();
  for (const h of history.data)
    if ((from.get(h.restaurant_id) ?? "") < h.valid_from) from.set(h.restaurant_id, h.valid_from);
  let monthPurchases: LegalEntitySheet["monthPurchases"] = null;
  let monthPurchasesFailed = false;
  if (options.seeInvoices) {
    const today = todayAr();
    const { data, error } = await client
      .schema("purchasing")
      .from("invoices")
      .select("total_amount")
      .eq("legal_entity_id", id)
      .in("status", ["approved", "released"])
      .gte("issued_on", `${today.slice(0, 8)}01`)
      .is("deleted_at", null);
    if (error) monthPurchasesFailed = true;
    else
      monthPurchases = {
        total: data.reduce((sum, i) => sum + Number(i.total_amount), 0),
        invoices: data.length,
      };
  }
  return {
    id: e.id,
    groupId: e.group_id,
    name: e.name,
    taxId: e.tax_id,
    vatCondition: e.vat_condition,
    legalForm: e.legal_form,
    activityStart: e.activity_start,
    tradeName: e.trade_name,
    fiscalStreet: e.fiscal_street,
    fiscalLocality: e.fiscal_locality,
    fiscalPostalCode: e.fiscal_postal_code,
    fiscalProvince: e.fiscal_province,
    electronicDomicile: e.electronic_domicile,
    incomeTax: e.income_tax,
    grossIncomeRegime: e.gross_income_regime,
    grossIncomeNumber: e.gross_income_number,
    grossIncomeProvince: e.gross_income_province,
    isEmployer: e.is_employer,
    isWithholdingAgent: e.is_withholding_agent,
    isPerceptionAgent: e.is_perception_agent,
    activities: activities.data.map((a) => ({
      id: a.id,
      code: a.code,
      description: a.description,
      primary: a.is_primary,
    })),
    places: places.data.map((p) => ({
      id: p.id,
      code: p.code,
      name: p.name,
      brandId: p.brand_id,
      validFrom: from.get(p.id) ?? null,
    })),
    documents: documents.data.map((d) => ({
      id: d.id,
      issuedOn: d.issued_on,
      path: d.storage_path,
    })),
    missing: Array.isArray(s.missing) ? s.missing : [],
    stamp: s.stamp ?? null,
    canEdit: s.can_edit === true,
    monthPurchases,
    monthPurchasesFailed,
  };
}
