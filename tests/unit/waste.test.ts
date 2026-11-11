// Medidas, mermas y rendimientos (ADR-0040): el rendimiento neto y su vista previa nunca suponen un dato, las unidades
// se muestran «Kilogramo (kg)» y los formularios piden lo que pide la base.
import { describe, expect, it } from "vitest";

import { schemas } from "@/lib/forms/schemas";
import {
  LINE_UNITS,
  lineUnitForYield,
  unitDimension,
  unitGroups,
  unitOptionLabel,
} from "@/lib/recipe-format";
import {
  formatLoss,
  formatNetYield,
  netYield,
  parseLossPercent,
  previewNetYield,
} from "@/lib/yields";

describe("rendimiento neto", () => {
  it("limpieza por descongelado, con 4 decimales como la base", () => {
    expect(netYield({ cleaning: 0.8, thawing: 0.9, requiresThawing: true })).toEqual({
      value: 0.72,
      missing: null,
    });
  });

  it("sin congelar, el descongelado no cuenta aunque exista", () => {
    expect(netYield({ cleaning: 0.8, thawing: 0.9, requiresThawing: false }).value).toBe(0.8);
  });

  it("nunca supone: sin limpieza, o congelada sin descongelado, falta el dato", () => {
    expect(netYield({ cleaning: null, thawing: 0.9, requiresThawing: true })).toEqual({
      value: null,
      missing: "Falta la merma de limpieza.",
    });
    expect(netYield({ cleaning: 0.8, thawing: null, requiresThawing: true })).toEqual({
      value: null,
      missing: "Falta la merma de descongelado.",
    });
  });

  it("se dice como merma y como rendimiento", () => {
    expect(formatLoss(0.8)).toBe("20,0 %");
    expect(formatNetYield(0.72)).toBe("Rinde 72,0 % neto");
  });
});

describe("mermas escritas en %", () => {
  it("con coma o punto; vacía es «no cargada»", () => {
    expect(parseLossPercent("12,5")).toBe(0.125);
    expect(parseLossPercent("8.25")).toBeCloseTo(0.0825);
    expect(parseLossPercent("  ")).toBeNull();
  });

  it("100 o más, o texto, no es una merma", () => {
    expect(parseLossPercent("100")).toBeNaN();
    expect(parseLossPercent("abc")).toBeNaN();
  });

  it("la vista previa usa lo escrito y, si falta, lo aprobado", () => {
    const base = { requiresThawing: true, approvedCleaning: 0.8, approvedThawing: null };
    expect(previewNetYield({ ...base, cleaningLoss: "", thawingLoss: "10" }).value).toBe(0.72);
    expect(previewNetYield({ ...base, cleaningLoss: "25", thawingLoss: "10" }).value).toBe(0.675);
    expect(previewNetYield({ ...base, cleaningLoss: "", thawingLoss: "" }).missing).toBe(
      "Falta la merma de descongelado.",
    );
    expect(previewNetYield({ ...base, cleaningLoss: "x", thawingLoss: "" }).missing).toBe(
      "Revisá los porcentajes.",
    );
  });
});

describe("unidades", () => {
  it("se muestran con nombre y abreviatura", () => {
    expect(unitOptionLabel("kg")).toBe("Kilogramo (kg)");
    expect(unitOptionLabel("tbsp")).toBe("Cucharada (cda)");
    // Si el nombre ya es la abreviatura, no se repite.
    expect(unitOptionLabel("pinch")).toBe("Pizca");
    expect(unitOptionLabel("otra")).toBe("otra");
  });

  it("cada una tiene su dimensión, y los grupos no dejan ninguna afuera", () => {
    expect(unitDimension("cup")).toBe("volume");
    expect(unitDimension("lb")).toBe("mass");
    expect(unitDimension("portion")).toBe("count");
    expect(unitGroups().flatMap((g) => g.units)).toHaveLength(LINE_UNITS.length);
    expect(unitGroups("volume").map((g) => g.label)).toEqual(["Volumen"]);
  });

  it("una preparación se usa en la unidad chica de su rendimiento", () => {
    expect(lineUnitForYield("lb")).toBe("g");
    expect(lineUnitForYield("cup")).toBe("ml");
    expect(lineUnitForYield("portion")).toBe("unit");
    expect(lineUnitForYield(null)).toBe("g");
  });
});

describe("formularios", () => {
  const waste = (v: Record<string, unknown>) =>
    schemas.waste.safeParse({ reason: "Pesado en la cocina", ...v });

  it("mermas: al menos una, y 0 % solo declarado", () => {
    expect(waste({ cleaning_loss: "", thawing_loss: "" }).success).toBe(false);
    expect(waste({ cleaning_loss: "20", thawing_loss: "" }).success).toBe(true);
    expect(waste({ cleaning_loss: "0", thawing_loss: "" }).success).toBe(false);
    expect(waste({ cleaning_loss: "0", declared_no_loss: true }).success).toBe(true);
    expect(waste({ cleaning_loss: "100" }).success).toBe(false);
  });

  it("unidad nueva: con equivalencia, salvo un envase", () => {
    const unit = (v: Record<string, unknown>) =>
      schemas.unit.safeParse({
        code: "cucharon",
        long_name: "Cucharón",
        abbreviation: "cuch",
        reason: "La usamos",
        ...v,
      });
    expect(unit({ dimension: "volume", factor: "60" }).success).toBe(true);
    expect(unit({ dimension: "volume", factor: "" }).success).toBe(false);
    expect(unit({ dimension: "package", factor: "" }).success).toBe(true);
    expect(unit({ dimension: "package", factor: "20" }).success).toBe(false);
    expect(unit({ dimension: "volume", factor: "60", code: "Cucharón" }).success).toBe(false);
  });

  it("las recetas aceptan las unidades nuevas", () => {
    expect(
      schemas.recipeDraft.shape.yield_unit.safeParse("cup").success &&
        schemas.recipeDraft.shape.yield_unit.safeParse("caja").success === false,
    ).toBe(true);
  });
});
