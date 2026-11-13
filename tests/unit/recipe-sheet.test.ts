// Ficha única de receta (ADR-0042): las cuentas de la grilla. El costo de cada fila lo da la base; acá se prueba que
// la pantalla lo pasa a la unidad grande, lo suma, lo escala y lo reparte sin suponer nada cuando falta un dato.
import { describe, expect, it } from "vitest";

import {
  START_ROWS,
  bigUnitPrice,
  changesLabel,
  compatibleDimensions,
  costPerNetKg,
  countChanges,
  formatPct,
  incidence,
  missingReason,
  parseTimes,
  perPortion,
  portionsFrom,
  scale,
  sheetTotals,
  toGrams,
  withTrailingRow,
  yieldRatio,
} from "@/lib/recipe-sheet";

describe("precio por unidad grande", () => {
  it("100 g de harina → el precio del kilo; 100 cc de leche → el del litro", () => {
    expect(bigUnitPrice(1.8, "g")).toEqual({ value: 1800, unit: "kg" });
    expect(bigUnitPrice(1.25, "ml")).toEqual({ value: 1250, unit: "l" });
    expect(bigUnitPrice(300, "unit")).toEqual({ value: 300, unit: "u" });
  });
  it("sin precio, no hay precio (nunca $ 0)", () => {
    expect(bigUnitPrice(null, "g")).toBeNull();
    expect(bigUnitPrice(5, null)).toBeNull();
  });
});

describe("costo por renglón y totales", () => {
  it("suma los costos y los pesos de las filas", () => {
    const t = sheetTotals([
      { grams: 100, cost: 180 },
      { grams: 250, cost: 320 },
    ]);
    expect(t).toMatchObject({ grams: 350, cost: 500, missingGrams: 0, missingCost: 0, lines: 2 });
  });
  it("si a una fila le falta el costo o el peso, el total queda vacío y dice cuántas faltan", () => {
    const t = sheetTotals([
      { grams: 100, cost: 180 },
      { grams: null, cost: null },
    ]);
    expect(t.grams).toBeNull();
    expect(t.cost).toBeNull();
    expect(t.missingGrams).toBe(1);
    expect(t.missingCost).toBe(1);
  });
  it("sin filas no hay total", () => {
    expect(sheetTotals([])).toMatchObject({ grams: null, cost: null, lines: 0 });
  });
  it("cada motivo se dice en palabras", () => {
    expect(missingReason("missing_price")).toBe("No hay precio vigente en este local.");
    expect(missingReason("missing_conversion")).toMatch(/densidad o el peso por unidad/);
    expect(missingReason("algo_nuevo")).toBe("Falta un dato para calcularlo.");
    expect(missingReason(null)).toBe("Falta un dato para calcularlo.");
  });
});

describe("incidencias", () => {
  it("el % de cada fila sobre el total", () => {
    expect(incidence(180, 500)).toBeCloseTo(36);
    expect(formatPct(incidence(180, 500))).toBe("36,0 %");
  });
  it("sin total, sin incidencia", () => {
    expect(incidence(180, null)).toBeNull();
    expect(incidence(180, 0)).toBeNull();
    expect(incidence(null, 500)).toBeNull();
    expect(formatPct(null)).toBe("—");
  });
});

describe("escala («Hacer N recetas»)", () => {
  it("multiplica peso y costo", () => {
    expect(scale(250, 4)).toBe(1000);
    expect(scale(null, 4)).toBeNull();
    expect(scale(250, null)).toBeNull();
  });
  it("acepta enteros de 1 a 999", () => {
    expect(parseTimes("4")).toBe(4);
    expect(parseTimes(" 10 ")).toBe(10);
    expect(parseTimes("0")).toBeNull();
    expect(parseTimes("1000")).toBeNull();
    expect(parseTimes("2,5")).toBeNull();
    expect(parseTimes("")).toBeNull();
  });
});

describe("porciones del plato", () => {
  it("peso total ÷ peso de la porción, con decimales", () => {
    expect(portionsFrom(296.2, 100)).toBe(2.96);
    expect(portionsFrom(3000, 375)).toBe(8);
  });
  it("sin peso de porción o sin peso total, no se inventan", () => {
    expect(portionsFrom(3000, null)).toBeNull();
    expect(portionsFrom(null, 300)).toBeNull();
    expect(portionsFrom(3000, 0)).toBeNull();
  });
  it("costo por porción", () => {
    expect(perPortion(800, 8)).toBe(100);
    expect(perPortion(null, 8)).toBeNull();
    expect(perPortion(800, null)).toBeNull();
  });
});

describe("rendimiento de la preparación", () => {
  it("neto ÷ bruto (1,5 kg de 2,015 kg = 74,4 %)", () => {
    expect(yieldRatio(toGrams(1.5, "kg"), 2015)).toBeCloseTo(0.7444, 4);
  });
  it("en volumen o en unidades no se pasa a gramos", () => {
    expect(toGrams(2, "l")).toBeNull();
    expect(toGrams(3, "unit")).toBeNull();
    expect(yieldRatio(toGrams(2, "l"), 2000)).toBeNull();
  });
  it("sin peso neto o sin bruto, sin rendimiento", () => {
    expect(yieldRatio(null, 2000)).toBeNull();
    expect(yieldRatio(1500, null)).toBeNull();
  });
  it("costo por kg neto", () => {
    expect(costPerNetKg(3000, 1500)).toBe(2000);
    expect(costPerNetKg(null, 1500)).toBeNull();
  });
});

describe("medidas compatibles", () => {
  it("una materia prima en peso, sin conversiones, solo en peso", () => {
    expect(compatibleDimensions("mass", false, false)).toEqual(["mass"]);
  });
  it("con densidad, también en volumen; con peso por unidad, también en unidades", () => {
    expect(compatibleDimensions("volume", true, false)).toEqual(["mass", "volume"]);
    expect(compatibleDimensions("count", false, true)).toEqual(["mass", "count"]);
    expect(compatibleDimensions("mass", true, true)).toEqual(["mass", "volume", "count"]);
  });
  it("leche en ml sin densidad: solo volumen (no se adivina)", () => {
    expect(compatibleDimensions("volume", false, false)).toEqual(["volume"]);
  });
});

describe("filas de la grilla", () => {
  const filled = (r: { v: string }) => r.v !== "";
  const make = () => ({ v: "" });
  it("arranca con 10 filas", () => {
    expect(withTrailingRow([], filled, make)).toHaveLength(START_ROWS);
  });
  it("al completar la última, aparece la fila 11", () => {
    const rows = Array.from({ length: 10 }, () => ({ v: "x" }));
    const out = withTrailingRow(rows, filled, make);
    expect(out).toHaveLength(11);
    expect(out.at(-1)).toEqual({ v: "" });
  });
  it("si la última está vacía, no agrega otra", () => {
    const rows = [...Array.from({ length: 9 }, () => ({ v: "x" })), { v: "" }];
    expect(withTrailingRow(rows, filled, make)).toHaveLength(10);
  });
});

describe("contador de cambios", () => {
  it("cuenta las filas distintas, agregadas y quitadas", () => {
    const same = (a: string, b: string) => a === b;
    expect(countChanges(["a", "b"], ["a", "b"], same)).toBe(0);
    expect(countChanges(["a", "b"], ["a", "c"], same)).toBe(1);
    expect(countChanges(["a"], ["a", "b", "c"], same)).toBe(2);
    expect(countChanges(["a", "b"], [], same)).toBe(2);
  });
  it("lo dice en palabras", () => {
    expect(changesLabel(0)).toBe("Sin cambios");
    expect(changesLabel(1)).toBe("1 cambio sin guardar");
    expect(changesLabel(3)).toBe("3 cambios sin guardar");
  });
});
