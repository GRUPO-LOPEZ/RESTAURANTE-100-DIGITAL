// Medida práctica (ADR-0064): la misma cuenta que la base (recipes.measure_count_for; supabase/tests/413).
import { describe, expect, it } from "vitest";

import {
  isContentUnit,
  measureCount,
  measureLabel,
  measureText,
  measuresFor,
  type Measure,
} from "@/lib/measures";
import { versionChip } from "@/lib/recipe-format";
import { START_ROWS, withTrailingRow } from "@/lib/recipe-sheet";

const nest: Measure = { id: "n", name: "Nido", content: 120, unit: "g", isActive: true };
const cup: Measure = { id: "t", name: "Taza", content: 240, unit: "ml", isActive: true };
const pair: Measure = { id: "p", name: "Par", content: 2, unit: "unit", isActive: true };

describe("cuántas medidas van", () => {
  it("entre unidades de la misma clase", () => {
    expect(measureCount(480, "g", nest, null)).toBe(4);
    expect(measureCount(1.2, "kg", nest, null)).toBe(10);
    expect(measureCount(360, "ml", cup, null)).toBe(1.5);
    expect(measureCount(2, "cup", cup, null)).toBe(2);
    expect(measureCount(1, "dozen", pair, null)).toBe(6);
  });

  it("con 2 decimales, y nunca cero", () => {
    expect(measureCount(1, "l", cup, null)).toBe(4.17);
    expect(measureCount(0.01, "ml", cup, null)).toBe(0.01);
    // 1,005 × 100 en binario da 100,49999…: se redondea como la base.
    expect(measureCount(120.6, "g", nest, null)).toBe(1.01);
  });

  it("peso con volumen, nunca (tampoco con densidad: no la recibe)", () => {
    expect(measureCount(480, "g", cup, null)).toBeNull();
    expect(measureCount(480, "g", cup, 120)).toBeNull();
    expect(measureCount(100, "ml", nest, 120)).toBeNull();
  });

  it("peso con unidades, solo con el peso por unidad", () => {
    expect(measureCount(1, "unit", nest, 120)).toBe(1);
    expect(measureCount(480, "g", pair, 120)).toBe(2);
    expect(measureCount(1, "unit", nest, null)).toBeNull();
    expect(measureCount(1, "unit", nest, 0)).toBeNull();
  });

  it("sin cantidad o sin unidad, no se supone", () => {
    expect(measureCount(null, "g", nest, null)).toBeNull();
    expect(measureCount(0, "g", nest, null)).toBeNull();
    expect(measureCount(480, "", nest, null)).toBeNull();
    expect(measureCount(480, "caja", nest, null)).toBeNull();
  });
});

describe("las que se ofrecen", () => {
  const all = [nest, cup, pair];
  it("las de la clase de la línea", () => {
    expect(measuresFor(all, "kg", null, "").map((m) => m.id)).toEqual(["n"]);
    expect(measuresFor(all, "ml", null, "").map((m) => m.id)).toEqual(["t"]);
    expect(measuresFor(all, "unit", 120, "").map((m) => m.id)).toEqual(["n", "p"]);
    expect(measuresFor(all, "", null, "")).toEqual([]);
  });

  it("una inactiva, solo donde ya está", () => {
    const off = [{ ...nest, isActive: false }, cup];
    expect(measuresFor(off, "g", null, "")).toEqual([]);
    expect(measuresFor(off, "g", null, "n").map((m) => m.id)).toEqual(["n"]);
  });
});

describe("cómo se lee", () => {
  it("la medida y cuántas van", () => {
    expect(measureLabel(nest)).toBe("Nido (120 g)");
    expect(measureLabel({ ...pair, isActive: false })).toBe("Par (2 u) · inactiva");
    expect(measureText(4, "Nido")).toBe("4 × Nido");
    expect(measureText(1.5, "Taza")).toBe("1,5 × Taza");
    expect(measureText(null, "Nido")).toBeNull();
    expect(measureText(4, null)).toBeNull();
  });

  it("solo hay tres unidades de contenido", () => {
    expect(["ml", "g", "unit"].every(isContentUnit)).toBe(true);
    expect(["kg", "l", "constructor", ""].some(isContentUnit)).toBe(false);
  });

  it("la versión, con su estado", () => {
    expect(versionChip(3, "draft")).toBe("Versión 3 · Borrador");
    expect(versionChip(3, "in_review")).toBe("Versión 3 · En revisión");
    expect(versionChip(2, "published")).toBe("Versión 2 · Publicada");
  });
});

describe("los renglones", () => {
  it("arranca con 8 y, al llenar el último, aparece otro", () => {
    const filled = (r: number) => r > 0;
    expect(START_ROWS).toBe(8);
    expect(withTrailingRow([], filled, () => 0)).toHaveLength(8);
    expect(withTrailingRow([1, 1, 1, 1, 1, 1, 1], filled, () => 0)).toHaveLength(8);
    expect(withTrailingRow([1, 1, 1, 1, 1, 1, 1, 1], filled, () => 0)).toHaveLength(9);
  });
});
