// Configuración del catálogo en una pantalla (ADR-0063): qué cambió en una lista, qué le falta a una fila y qué viaja a
// la base (catalog.save_settings_list).
import { describe, expect, it } from "vitest";

import {
  EMPTY_FIELDS,
  IN_WORDS,
  LIST_INFO,
  SETTINGS_LISTS,
  changedKeys,
  inOrder,
  inputNumber,
  readNumber,
  itemErrors,
  listFromSlug,
  listPayload,
  newItem,
  type ListFields,
  type ListItem,
} from "@/lib/settings-lists";

function item(id: string, fields: Partial<ListFields>, more: Partial<ListItem> = {}): ListItem {
  return { ...newItem(0), key: id, id, fields: { ...EMPTY_FIELDS, ...fields }, ...more };
}
function fresh(n: number, fields: Partial<ListFields>): ListItem {
  return { ...newItem(n), fields: { ...EMPTY_FIELDS, ...fields } };
}

describe("las listas", () => {
  it("cada una tiene su dirección, y una dirección rara no es ninguna", () => {
    for (const list of SETTINGS_LISTS) expect(listFromSlug(LIST_INFO[list].slug)).toBe(list);
    expect(new Set(SETTINGS_LISTS.map((l) => LIST_INFO[l].slug)).size).toBe(SETTINGS_LISTS.length);
    expect(listFromSlug("otra")).toBeNull();
    expect(listFromSlug(undefined)).toBeNull();
    expect(listFromSlug("constructor")).toBeNull();
  });
});

describe("qué cambió", () => {
  const saved = [item("a", { name: "Pastas" }), item("b", { name: "Salsas" })];

  it("los espacios de más no son un cambio", () => {
    const draft = [item("a", { name: " Pastas " }), saved[1] as ListItem];
    expect(changedKeys("stations", saved, draft).size).toBe(0);
    expect(listPayload("stations", saved, draft)).toEqual([]);
  });

  it("de cada fila viaja solo lo que cambió", () => {
    const draft = [
      item("a", { name: "Pastas frescas" }),
      item("b", { name: "Salsas" }, { active: false }),
      fresh(1, { name: " Parrilla " }),
    ];
    expect([...changedKeys("stations", saved, draft)]).toEqual(["a", "b", "nuevo-1"]);
    expect(listPayload("stations", saved, draft)).toEqual([
      { id: "a", name: "Pastas frescas" },
      { id: "b", active: false },
      { name: "Parrilla" },
    ]);
  });

  it("lo que no se edita en la lista no cuenta", () => {
    const process = [item("p", { name: "Pelado", code: "PELADO" })];
    expect(
      changedKeys("processes", process, [item("p", { name: "Pelado", code: "OTRO" })]).size,
    ).toBe(0);
  });
});

describe("equipos", () => {
  const saved = [
    item("h", { name: "Horno", capacity: "5", capacityUnit: "kg" }),
    item("p", {
      name: "Pastera",
      capacity: "6",
      capacityUnit: IN_WORDS,
      capacityLabel: "canastos",
    }),
  ];

  it("la capacidad viaja entera, en una unidad o en palabras", () => {
    const draft = [
      item("h", { name: "Horno", capacity: "8", capacityUnit: IN_WORDS, capacityLabel: "placas" }),
      item("p", { name: "Pastera", capacity: "6", capacityUnit: "kg", capacityLabel: "canastos" }),
    ];
    expect(listPayload("equipment", saved, draft)).toEqual([
      { id: "h", capacity: "8", capacity_unit: "", capacity_label: "placas" },
      { id: "p", capacity: "6", capacity_unit: "kg", capacity_label: "" },
    ]);
  });

  it("una palabra escrita que no se usa no es un cambio", () => {
    const draft = [
      item("h", { name: "Horno", capacity: "5", capacityUnit: "kg", capacityLabel: "placas" }),
      saved[1] as ListItem,
    ];
    expect(changedKeys("equipment", saved, draft).size).toBe(0);
  });

  it("dice qué falta", () => {
    const errors = (f: Partial<ListFields>) =>
      itemErrors("equipment", item("x", { name: "X", ...f }));
    expect(errors({})).toEqual({});
    expect(errors({ capacity: "5" })).toEqual({ capacityUnit: "Elegí en qué." });
    expect(errors({ capacityUnit: "kg" })).toEqual({ capacity: "Escribí cuánto entra." });
    expect(errors({ capacity: "0", capacityUnit: "kg" }).capacity).toMatch(/mayor que cero/);
    expect(errors({ capacity: "cinco", capacityUnit: "kg" }).capacity).toMatch(/mayor que cero/);
    expect(errors({ capacity: "6", capacityUnit: IN_WORDS }).capacityLabel).toMatch(/canastos/);
    expect(errors({ capacity: "5,5", capacityUnit: "kg" })).toEqual({});
  });
});

describe("medidas prácticas", () => {
  it("contiene un número mayor que cero, con coma o punto", () => {
    const errors = (content: string) =>
      itemErrors("measures", fresh(1, { name: "Taza", content })).content;
    expect(errors("240")).toBeUndefined();
    expect(errors("7,5")).toBeUndefined();
    expect(errors("7.5")).toBeUndefined();
    for (const bad of ["", "0", "-1", "1.000,5", "un vaso"]) expect(errors(bad)).toBeDefined();
  });

  it("una nueva viaja con todo", () => {
    const draft = [
      fresh(1, { name: "Puñado", content: "30", contentUnit: "g", usageNote: "Hierbas" }),
    ];
    expect(listPayload("measures", [], draft)).toEqual([
      { name: "Puñado", content: "30", content_unit: "g", usage_note: "Hierbas" },
    ]);
  });
});

describe("lo que se carga solo al crear", () => {
  it("una subcategoría pide su rubro", () => {
    expect(itemErrors("ingredient_categories", fresh(1, { name: "Quesos" }))).toEqual({
      parentId: "Elegí el rubro.",
    });
    expect(
      listPayload("ingredient_categories", [], [fresh(1, { name: "Quesos", parentId: "r" })]),
    ).toEqual([{ name: "Quesos", parent_id: "r" }]);
  });

  it("un proceso pide su código, en mayúsculas", () => {
    expect(itemErrors("processes", fresh(1, { name: "Curado", code: "C" })).code).toMatch(
      /Mayúsculas/,
    );
    expect(listPayload("processes", [], [fresh(1, { name: "Curado", code: "curado" })])).toEqual([
      { name: "Curado", code: "CURADO" },
    ]);
  });

  it("una unidad pide tipo y equivalencia, salvo un envase", () => {
    const base = { name: "Cucharón", abbreviation: "cuch", code: "cucharon" };
    expect(itemErrors("units", fresh(1, base)).dimension).toBe("Elegí el tipo.");
    expect(itemErrors("units", fresh(1, { ...base, dimension: "volume" })).factor).toBeDefined();
    expect(itemErrors("units", fresh(1, { ...base, dimension: "volume", factor: "60" }))).toEqual(
      {},
    );
    expect(itemErrors("units", fresh(1, { ...base, dimension: "package" }))).toEqual({});
    expect(
      itemErrors("units", fresh(1, { ...base, code: "Cucharón", dimension: "package" })).code,
    ).toBeDefined();
  });
});

describe("el nombre", () => {
  it("no va vacío, ni largo, ni con < o >", () => {
    const error = (name: string) => itemErrors("sectors", fresh(1, { name })).name;
    expect(error("  ")).toBe("Escribí el nombre.");
    expect(error("a".repeat(61))).toBe("Hasta 60 caracteres.");
    expect(error("<b>")).toBe("Sin < ni >.");
    expect(error("Barra")).toBeUndefined();
  });
});

describe("el orden", () => {
  it("cada subcategoría va debajo de su rubro, y las nuevas al final hasta guardar", () => {
    const items = [
      item("q", { name: "Quesos", parentId: "l" }),
      item("c", { name: "Carnes" }),
      item("l", { name: "Lácteos" }),
      fresh(1, { name: "Sin rubro" }),
      fresh(2, { name: "Cremas", parentId: "l" }),
    ];
    expect(inOrder("ingredient_categories", items).map((i) => i.key)).toEqual([
      "c",
      "l",
      "q",
      "nuevo-1",
      "nuevo-2",
    ]);
    expect(inOrder("sectors", items)).toEqual(items);
  });
});

describe("el número en un campo", () => {
  it("va con coma y sin puntos de miles", () => {
    expect(inputNumber(5.5)).toBe("5,5");
    expect(inputNumber(1200)).toBe("1200");
    expect(inputNumber(null)).toBe("");
    expect(readNumber("1000")).toBe("1.000");
    expect(readNumber("453,59237")).toBe("453,59237");
    expect(readNumber("")).toBe("");
  });
});
