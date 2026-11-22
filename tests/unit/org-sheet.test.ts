import { describe, expect, it } from "vitest";

import {
  countLegalEntityChanges,
  countRestaurantChanges,
  legalEntityChanges,
  legalEntityPayload,
  missingLabel,
  restaurantChanges,
  restaurantMissing,
  restaurantPayload,
  type LegalEntityDraft,
  type RestaurantDraft,
} from "@/lib/org-sheet";

// Fichas del local y de la razón social en una pantalla (ADR-0061): qué cambió y qué viaja a la base.
const place: RestaurantDraft = {
  fields: {
    zone: "Leloir",
    opened_on: "2019-03-15",
    address: "Calle Ficticia 100",
    locality: "Parque Leloir",
    province: "06",
    postal_code: "B1713",
    phone: "011 4000-0001",
  },
  geo: { status: "found", latitude: "-34.6", longitude: "-58.6", label: "Calle Ficticia 100" },
  siteType: "restaurant",
  state: "open",
  legalEntityId: "00000000-0000-4000-8000-000000001501",
  legalFrom: "2024-01-01",
  areas: [
    { key: "a1", id: "a1", name: "Cocina", active: true },
    { key: "a2", id: "a2", name: "Salón", active: true },
    { key: "a3", id: "a3", name: "Barra", active: false },
  ],
};

describe("ficha del local", () => {
  it("sin cambios no manda nada", () => {
    expect(countRestaurantChanges(restaurantChanges(place, place))).toBe(0);
    expect(restaurantPayload(place, place)).toEqual({});
  });

  it("manda solo lo que cambió, con la ubicación de Georef junto a la dirección", () => {
    const draft: RestaurantDraft = {
      ...place,
      fields: { ...place.fields, phone: " 011 4000-0002 ", address: "Calle Ficticia 200" },
      geo: { status: "not_found", latitude: "", longitude: "", label: "" },
    };
    const c = restaurantChanges(place, draft);
    // Dirección y teléfono; la ubicación no suma otro cambio porque va con la dirección.
    expect(countRestaurantChanges(c)).toBe(2);
    expect(restaurantPayload(place, draft)).toEqual({
      restaurant: {
        phone: "011 4000-0002",
        address: "Calle Ficticia 200",
        geo_status: "not_found",
        latitude: "",
        longitude: "",
        geo_label: "",
      },
    });
  });

  it("las áreas: nueva sin id, quitada con remove, renombrada y vuelta a usar con su nombre", () => {
    const draft: RestaurantDraft = {
      ...place,
      areas: [
        { key: "a1", id: "a1", name: "Cocina caliente", active: true },
        { key: "a2", id: "a2", name: "Salón", active: false },
        { key: "a3", id: "a3", name: "Barra", active: true },
        { key: "nueva-1", id: null, name: " Pastelería ", active: true },
      ],
    };
    expect(countRestaurantChanges(restaurantChanges(place, draft))).toBe(4);
    expect(restaurantPayload(place, draft).areas).toEqual([
      { id: "a1", name: "Cocina caliente" },
      { id: "a2", remove: true },
      { id: "a3", name: "Barra" },
      { name: "Pastelería" },
    ]);
  });

  it("la razón social nueva viaja con desde qué fecha", () => {
    const draft = {
      ...place,
      legalEntityId: "00000000-0000-4000-8000-000000001502",
      legalFrom: "2026-11-22",
    };
    expect(restaurantPayload(place, draft)).toEqual({
      legal_entity: {
        legal_entity_id: "00000000-0000-4000-8000-000000001502",
        valid_from: "2026-11-22",
      },
    });
  });

  it("dice qué falta para abrir, como la base", () => {
    const empty: RestaurantDraft = {
      ...place,
      fields: { ...place.fields, phone: "", opened_on: "" },
      legalEntityId: "",
    };
    expect(restaurantMissing(place)).toEqual([]);
    expect(restaurantMissing(empty)).toEqual(["fecha de apertura", "teléfono"]);
    expect(missingLabel(["teléfono"])).toBe("Falta teléfono");
    expect(missingLabel(["teléfono", "dirección", "localidad"])).toBe(
      "Faltan teléfono, dirección y localidad",
    );
  });
});

const entity: LegalEntityDraft = {
  fields: {
    name: "Demo S.R.L.",
    tax_id: "30-00000000-7",
    vat_condition: "registered",
    legal_form: "srl",
    activity_start: "2018-05-02",
    trade_name: "",
    fiscal_street: "Calle Ficticia 100",
    fiscal_locality: "San Nicolás",
    fiscal_postal_code: "C1000",
    fiscal_province: "02",
    electronic_domicile: "",
    income_tax: "registered",
    gross_income_regime: "multilateral",
    gross_income_number: "901-000001-7",
    gross_income_province: "02",
  },
  flags: { is_employer: true, is_withholding_agent: false, is_perception_agent: false },
  activities: [
    {
      key: "x1",
      id: "x1",
      code: "561011",
      description: "Restaurantes",
      primary: true,
      removed: false,
    },
    {
      key: "x2",
      id: "x2",
      code: "561020",
      description: "Para llevar",
      primary: false,
      removed: false,
    },
  ],
};

describe("ficha de la razón social", () => {
  it("los toggles y los datos cambiados", () => {
    const draft: LegalEntityDraft = {
      ...entity,
      fields: { ...entity.fields, trade_name: "Ragú" },
      flags: { ...entity.flags, is_withholding_agent: true },
    };
    expect(countLegalEntityChanges(legalEntityChanges(entity, draft))).toBe(2);
    expect(legalEntityPayload(entity, draft)).toEqual({
      entity: { trade_name: "Ragú", is_withholding_agent: true },
    });
  });

  it("cambiar la principal manda las dos actividades; una nueva va sin id; una quitada, con remove", () => {
    const draft: LegalEntityDraft = {
      ...entity,
      activities: [
        { ...entity.activities[0]!, primary: false, removed: true },
        { ...entity.activities[1]!, primary: true },
        {
          key: "nueva",
          id: null,
          code: "561019",
          description: "Expendio",
          primary: false,
          removed: false,
        },
      ],
    };
    expect(legalEntityPayload(entity, draft).activities).toEqual([
      { id: "x1", remove: true },
      { id: "x2", code: "561020", description: "Para llevar", is_primary: true },
      { code: "561019", description: "Expendio", is_primary: false },
    ]);
  });
});
