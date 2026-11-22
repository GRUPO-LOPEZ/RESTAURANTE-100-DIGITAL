// Fichas del local y de la razón social (ADR-0061): el borrador que se edita en la pantalla, qué cambió y lo que viaja a
// la base para guardarlo todo junto (org.save_restaurant_sheet y org.save_legal_entity_sheet). Sin React ni Supabase,
// para probarlo con Vitest.

export type SiteType = "restaurant" | "central_kitchen" | "production_unit";
export type OpenState = "opening" | "open";

export const SITE_TYPE_OPTIONS: { value: SiteType; label: string }[] = [
  { value: "restaurant", label: "Restaurante" },
  { value: "central_kitchen", label: "Cocina central" },
  { value: "production_unit", label: "Producción" },
];

export const OPEN_STATE_OPTIONS: { value: OpenState; label: string }[] = [
  { value: "opening", label: "En apertura" },
  { value: "open", label: "Abierto" },
];

// ---------------------------------------------------------------------------
// Ficha del local
// ---------------------------------------------------------------------------
export type RestaurantField =
  "zone" | "opened_on" | "address" | "locality" | "province" | "postal_code" | "phone";

export type GeoState = {
  status: "found" | "not_found" | "";
  latitude: string;
  longitude: string;
  label: string;
};

export type SheetArea = {
  // Clave de la pantalla: el id de la base, o «nueva-N» para un área sin guardar.
  key: string;
  id: string | null;
  name: string;
  active: boolean;
};

export type RestaurantDraft = {
  fields: Record<RestaurantField, string>;
  geo: GeoState;
  siteType: SiteType;
  state: OpenState;
  legalEntityId: string;
  legalFrom: string;
  areas: SheetArea[];
};

export const RESTAURANT_FIELDS: RestaurantField[] = [
  "zone",
  "opened_on",
  "address",
  "locality",
  "province",
  "postal_code",
  "phone",
];

export type RestaurantChanges = {
  fields: RestaurantField[];
  geo: boolean;
  siteType: boolean;
  state: boolean;
  legalEntity: boolean;
  areas: string[];
};

function sameGeo(a: GeoState, b: GeoState): boolean {
  return (
    a.status === b.status &&
    a.latitude === b.latitude &&
    a.longitude === b.longitude &&
    a.label === b.label
  );
}

/** Qué cambió entre lo guardado y el borrador. */
export function restaurantChanges(
  saved: RestaurantDraft,
  draft: RestaurantDraft,
): RestaurantChanges {
  const savedAreas = new Map(saved.areas.map((a) => [a.key, a]));
  return {
    fields: RESTAURANT_FIELDS.filter((f) => saved.fields[f].trim() !== draft.fields[f].trim()),
    geo: !sameGeo(saved.geo, draft.geo),
    siteType: saved.siteType !== draft.siteType,
    state: saved.state !== draft.state,
    legalEntity: saved.legalEntityId !== draft.legalEntityId,
    areas: draft.areas
      .filter((a) => {
        const before = savedAreas.get(a.key);
        if (!before) return a.active && a.name.trim() !== "";
        return before.name.trim() !== a.name.trim() || before.active !== a.active;
      })
      .map((a) => a.key),
  };
}

/** Cuántos cambios hay, para el contador de la barra. La ubicación en el mapa cuenta junto con la dirección. */
export function countRestaurantChanges(c: RestaurantChanges): number {
  return (
    c.fields.length +
    (c.geo && !c.fields.includes("address") ? 1 : 0) +
    (c.siteType ? 1 : 0) +
    (c.state ? 1 : 0) +
    (c.legalEntity ? 1 : 0) +
    c.areas.length
  );
}

export type RestaurantPayload = {
  restaurant?: Partial<
    Record<
      | RestaurantField
      | "latitude"
      | "longitude"
      | "geo_status"
      | "geo_label"
      | "site_type"
      | "state",
      string
    >
  >;
  legal_entity?: { legal_entity_id: string; valid_from?: string };
  areas?: ({ id: string; name?: string; remove?: boolean } | { name: string })[];
};

/** Lo que viaja a org.save_restaurant_sheet: solo lo que cambió. */
export function restaurantPayload(
  saved: RestaurantDraft,
  draft: RestaurantDraft,
): RestaurantPayload {
  const c = restaurantChanges(saved, draft);
  const out: RestaurantPayload = {};
  const restaurant: NonNullable<RestaurantPayload["restaurant"]> = {};
  for (const f of c.fields) restaurant[f] = draft.fields[f].trim();
  if (c.geo) {
    restaurant.geo_status = draft.geo.status;
    restaurant.latitude = draft.geo.latitude;
    restaurant.longitude = draft.geo.longitude;
    restaurant.geo_label = draft.geo.label;
  }
  if (c.siteType) restaurant.site_type = draft.siteType;
  if (c.state) restaurant.state = draft.state;
  if (Object.keys(restaurant).length > 0) out.restaurant = restaurant;
  if (c.legalEntity && draft.legalEntityId)
    out.legal_entity = {
      legal_entity_id: draft.legalEntityId,
      ...(draft.legalFrom ? { valid_from: draft.legalFrom } : {}),
    };
  if (c.areas.length > 0)
    // Una nueva va sin id; una quitada, con remove; una renombrada o vuelta a activar, con su nombre (la base la activa).
    out.areas = draft.areas
      .filter((a) => c.areas.includes(a.key))
      .map((a) =>
        !a.id
          ? { name: a.name.trim() }
          : !a.active
            ? { id: a.id, remove: true }
            : { id: a.id, name: a.name.trim() },
      );
  return out;
}

/** Cuántos datos obligatorios tiene un local (marca, zona, tipo, fecha, dirección, localidad, teléfono). La razón social es opcional. */
export const PLACE_REQUIRED = 7;
/** Cuántos datos obligatorios tiene una razón social (los de la constancia de ARCA). */
export const LEGAL_ENTITY_REQUIRED = 13;

/** Los obligatorios que le faltan al borrador (la misma lista que org.restaurant_missing), para avisar antes de abrir. */
export function restaurantMissing(d: RestaurantDraft): string[] {
  const out: string[] = [];
  if (!d.fields.zone.trim()) out.push("zona");
  if (!d.fields.opened_on.trim()) out.push("fecha de apertura");
  if (!d.fields.address.trim()) out.push("dirección");
  if (!d.fields.locality.trim()) out.push("localidad");
  if (!d.fields.phone.trim()) out.push("teléfono");
  return out;
}

/** «Falta teléfono», «Faltan teléfono y dirección»: lo que se muestra en lugar del estado de un local incompleto. */
export function missingLabel(missing: string[]): string {
  if (missing.length === 0) return "";
  if (missing.length === 1) return `Falta ${missing[0]}`;
  return `Faltan ${missing.slice(0, -1).join(", ")} y ${missing[missing.length - 1]}`;
}

// ---------------------------------------------------------------------------
// Ficha de la razón social
// ---------------------------------------------------------------------------
export type LegalEntityField =
  | "name"
  | "tax_id"
  | "vat_condition"
  | "legal_form"
  | "activity_start"
  | "trade_name"
  | "fiscal_street"
  | "fiscal_locality"
  | "fiscal_postal_code"
  | "fiscal_province"
  | "electronic_domicile"
  | "income_tax"
  | "gross_income_regime"
  | "gross_income_number"
  | "gross_income_province";

export type LegalEntityFlag = "is_employer" | "is_withholding_agent" | "is_perception_agent";

export const LEGAL_ENTITY_FIELDS: LegalEntityField[] = [
  "name",
  "tax_id",
  "vat_condition",
  "legal_form",
  "activity_start",
  "trade_name",
  "fiscal_street",
  "fiscal_locality",
  "fiscal_postal_code",
  "fiscal_province",
  "electronic_domicile",
  "income_tax",
  "gross_income_regime",
  "gross_income_number",
  "gross_income_province",
];
export const LEGAL_ENTITY_FLAGS: LegalEntityFlag[] = [
  "is_employer",
  "is_withholding_agent",
  "is_perception_agent",
];

export type SheetActivity = {
  key: string;
  id: string | null;
  code: string;
  description: string;
  primary: boolean;
  removed: boolean;
};

export type LegalEntityDraft = {
  fields: Record<LegalEntityField, string>;
  flags: Record<LegalEntityFlag, boolean>;
  activities: SheetActivity[];
};

export type LegalEntityChanges = {
  fields: LegalEntityField[];
  flags: LegalEntityFlag[];
  activities: string[];
};

export function legalEntityChanges(
  saved: LegalEntityDraft,
  draft: LegalEntityDraft,
): LegalEntityChanges {
  const before = new Map(saved.activities.map((a) => [a.key, a]));
  return {
    fields: LEGAL_ENTITY_FIELDS.filter((f) => saved.fields[f].trim() !== draft.fields[f].trim()),
    flags: LEGAL_ENTITY_FLAGS.filter((f) => saved.flags[f] !== draft.flags[f]),
    activities: draft.activities
      .filter((a) => {
        const b = before.get(a.key);
        if (!b) return !a.removed && (a.code.trim() !== "" || a.description.trim() !== "");
        return (
          b.code !== a.code.trim() ||
          b.description !== a.description.trim() ||
          b.primary !== a.primary ||
          b.removed !== a.removed
        );
      })
      .map((a) => a.key),
  };
}

export function countLegalEntityChanges(c: LegalEntityChanges): number {
  return c.fields.length + c.flags.length + c.activities.length;
}

export type LegalEntityPayload = {
  entity?: Partial<Record<LegalEntityField, string> & Record<LegalEntityFlag, boolean>>;
  activities?: {
    id?: string;
    code?: string;
    description?: string;
    is_primary?: boolean;
    remove?: boolean;
  }[];
};

export function legalEntityPayload(
  saved: LegalEntityDraft,
  draft: LegalEntityDraft,
): LegalEntityPayload {
  const c = legalEntityChanges(saved, draft);
  const out: LegalEntityPayload = {};
  const entity: NonNullable<LegalEntityPayload["entity"]> = {};
  for (const f of c.fields) entity[f] = draft.fields[f].trim();
  for (const f of c.flags) entity[f] = draft.flags[f];
  if (Object.keys(entity).length > 0) out.entity = entity;
  if (c.activities.length > 0)
    out.activities = draft.activities
      .filter((a) => c.activities.includes(a.key))
      .map((a) => {
        if (a.removed && a.id) return { id: a.id, remove: true };
        const body = {
          code: a.code.trim(),
          description: a.description.trim(),
          is_primary: a.primary,
        };
        return a.id ? { id: a.id, ...body } : body;
      });
  return out;
}
