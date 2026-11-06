import { describe, expect, it } from "vitest";

import {
  QUALITY_COMPARE,
  QUALITY_COMPARE_LIMIT,
  QUALITY_INDICATORS,
  qualityHref,
  qualityIndicator,
  qualityPercent,
} from "@/lib/quality-labels";

describe("los indicadores de calidad", () => {
  it("son los once de la base, sin repetir", () => {
    const keys = QUALITY_INDICATORS.map((i) => i.key);
    expect(new Set(keys).size).toBe(11);
  });

  it("cada uno dice qué cumple y qué falta", () => {
    for (const i of QUALITY_INDICATORS) {
      expect(i.label).not.toBe("");
      expect(i.missing).not.toBe(i.label);
    }
  });

  it("la comparación usa indicadores que existen", () => {
    for (const key of QUALITY_COMPARE) expect(qualityIndicator(key)).toBeDefined();
  });

  it("un indicador que no existe no se encuentra", () => {
    expect(qualityIndicator("no_existe")).toBeUndefined();
    expect(qualityIndicator(undefined)).toBeUndefined();
  });
});

describe("el porcentaje", () => {
  it("cuenta lo cumplido sobre el total", () => {
    expect(qualityPercent(3, 4)).toBe(75);
    expect(qualityPercent(4, 4)).toBe(100);
    expect(qualityPercent(0, 4)).toBe(0);
  });

  it("sin datos no hay porcentaje: cero sería mentir", () => {
    expect(qualityPercent(0, 0)).toBeNull();
  });
});

describe("la comparación", () => {
  it("va de a 20 locales, como la base", () => {
    expect(QUALITY_COMPARE_LIMIT).toBe(20);
  });
});

describe("el botón Ir", () => {
  it("lleva a la ficha que corrige el dato", () => {
    expect(qualityHref("recipe", "x")).toBe("/recetas/x");
    expect(qualityHref("ingredient", "x")).toBe("/materias-primas/x");
  });
});
