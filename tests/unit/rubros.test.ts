// Rubros (ADR-0038): porcentajes confiables, resumen, búsqueda y orden de la pantalla, y los esquemas
// de los formularios (los mismos en el navegador y en el servidor).
import { describe, expect, it } from "vitest";

import { schemas } from "@/lib/forms/schemas";
import {
  arrangeRubros,
  isRubroClass,
  rubroClassFromTab,
  sharePercent,
  summarize,
  usesLabel,
  type Rubro,
} from "@/lib/rubros";

function rubro(over: Partial<Rubro>): Rubro {
  return {
    rubroClass: "purchase",
    id: over.code ?? "x",
    code: "MP-XXX",
    name: "Rubro",
    isActive: true,
    uses: 0,
    mismatched: 0,
    ...over,
  };
}

describe("el porcentaje de un rubro", () => {
  it("es su parte del total de la pestaña, redondeada", () => {
    expect(sharePercent(1, 3)).toBe(33);
    expect(sharePercent(0, 10)).toBe(0);
  });

  it("sin total no hay porcentaje (nunca «0 %»)", () => {
    expect(sharePercent(0, 0)).toBeNull();
  });
});

describe("cuánto se usa", () => {
  it("dice insumos, sub-recetas o recetas según la clase", () => {
    expect(usesLabel("purchase", 0)).toBe("Sin insumos");
    expect(usesLabel("purchase", 1)).toBe("1 insumo");
    expect(usesLabel("subrecipe", 2)).toBe("2 sub-recetas");
    expect(usesLabel("menu", 1500)).toBe("1.500 recetas");
  });
});

describe("el resumen de la pestaña", () => {
  it("cuenta total, activos, dados de baja, sin uso, usos y recetas de la otra clase", () => {
    const s = summarize([
      rubro({ code: "MP-A", uses: 3 }),
      rubro({ code: "MP-B", uses: 0 }),
      rubro({ code: "MP-C", uses: 0, isActive: false, mismatched: 2 }),
    ]);
    expect(s).toEqual({ total: 3, active: 2, inactive: 1, unused: 2, uses: 3, mismatched: 2 });
  });

  it("sin rubros, todo en cero", () => {
    expect(summarize([])).toEqual({
      total: 0,
      active: 0,
      inactive: 0,
      unused: 0,
      uses: 0,
      mismatched: 0,
    });
  });
});

describe("la grilla", () => {
  const list = [
    rubro({ code: "MP-ACE", name: "Aceites", uses: 2 }),
    rubro({ code: "MP-LAC", name: "Lácteos", uses: 9 }),
    rubro({ code: "MP-CAR", name: "Carnes", uses: 9, isActive: false }),
    rubro({ code: "MP-ESP", name: "Especias", uses: 5 }),
  ];

  it("por cantidad: de mayor a menor, con los dados de baja al final", () => {
    expect(arrangeRubros(list, "", "cantidad").map((r) => r.code)).toEqual([
      "MP-LAC",
      "MP-ESP",
      "MP-ACE",
      "MP-CAR",
    ]);
  });

  it("de la A a la Z, también con los dados de baja al final", () => {
    expect(arrangeRubros(list, "", "az").map((r) => r.code)).toEqual([
      "MP-ACE",
      "MP-ESP",
      "MP-LAC",
      "MP-CAR",
    ]);
  });

  it("busca por nombre (sin tildes ni mayúsculas) o por código", () => {
    expect(arrangeRubros(list, "lacteos", "az").map((r) => r.code)).toEqual(["MP-LAC"]);
    expect(arrangeRubros(list, "mp-esp", "az").map((r) => r.code)).toEqual(["MP-ESP"]);
    expect(arrangeRubros(list, "pescado", "az")).toEqual([]);
  });

  it("no cambia la lista que recibe", () => {
    const before = list.map((r) => r.code);
    arrangeRubros(list, "", "cantidad");
    expect(list.map((r) => r.code)).toEqual(before);
  });
});

describe("las pestañas", () => {
  it("la dirección elige la pestaña; sin ella o con otra cosa, compra", () => {
    expect(rubroClassFromTab("menu").rubroClass).toBe("menu");
    expect(rubroClassFromTab("sub-recetas").rubroClass).toBe("subrecipe");
    expect(rubroClassFromTab(undefined).rubroClass).toBe("purchase");
    expect(rubroClassFromTab("otra").rubroClass).toBe("purchase");
  });

  it("solo se aceptan las tres clases", () => {
    expect(isRubroClass("menu")).toBe(true);
    expect(isRubroClass("dish")).toBe(false);
    expect(isRubroClass(null)).toBe(false);
  });
});

describe("los formularios de rubros", () => {
  it("el alta pide nombre y motivo", () => {
    expect(schemas.rubro.safeParse({ name: "Tapas", reason: "Rubro nuevo" }).success).toBe(true);
    expect(schemas.rubro.safeParse({ name: " ", reason: "Rubro nuevo" }).success).toBe(false);
    expect(schemas.rubro.safeParse({ name: "Tapas", reason: "" }).success).toBe(false);
  });

  it("el nombre en la tarjeta va de 1 a 80 caracteres", () => {
    expect(schemas.rubroName.safeParse({ name: "Tapas y pinchos" }).success).toBe(true);
    expect(schemas.rubroName.safeParse({ name: "x".repeat(81) }).success).toBe(false);
  });

  it("la baja pide motivo; el destino es opcional (la base lo exige si hay usos)", () => {
    expect(schemas.rubroDeactivate.safeParse({ reason: "Ya no se usa" }).success).toBe(true);
    expect(schemas.rubroDeactivate.safeParse({ target_id: "", reason: "" }).success).toBe(false);
  });

  it("una subcategoría pide su rubro", () => {
    expect(
      schemas.subcategory.safeParse({ name: "Quesos", parent_id: "", reason: "Sub" }).success,
    ).toBe(false);
    expect(
      schemas.subcategory.safeParse({ name: "Quesos", parent_id: "abc", reason: "Sub" }).success,
    ).toBe(true);
  });
});
