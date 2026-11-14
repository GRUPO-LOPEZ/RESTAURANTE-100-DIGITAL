// Ficha de receta sin scroll (ADR-0047): los 4 indicadores de arriba según el tipo y los permisos, la marca de quien
// revisa y el estado del total de la planilla. Nunca un número supuesto: sin dato, null y el motivo.
import { describe, expect, it } from "vitest";

import { metricView } from "@/lib/metrics";
import { reviewMark, sheetKpis, totalState, type SheetKpiInput } from "@/lib/recipe-sheet";

const base: SheetKpiInput = {
  dish: true,
  money: true,
  place: "Demo Pastas Centro",
  lines: 2,
  grams: 1000,
  missingGrams: 0,
  cost: 5000,
  missingCost: 0,
  portionText: "250",
  portionGrams: 250,
  portions: 4,
  manualPortions: null,
  netText: "",
  netGrams: null,
  ratio: null,
  totalMinutes: 45,
};

const labels = (i: SheetKpiInput) => sheetKpis(i).map((k) => k.label);
const money = /\$/;

describe("los 4 indicadores", () => {
  it("un plato: costo total, costo por porción, peso total y porciones", () => {
    const kpis = sheetKpis(base);
    expect(kpis.map((k) => k.label)).toEqual([
      "Costo total",
      "Costo por porción",
      "Peso total",
      "Porciones",
    ]);
    expect(kpis[0]?.value).toMatch(money);
    expect(kpis[1]?.value).toMatch(/1\.250/);
    expect(kpis[2]?.value).toBe("1.000 g");
    expect(kpis[3]?.value).toBe("4");
  });

  it("una preparación: costo total, costo por kg neto, peso bruto → neto y rendimiento", () => {
    const prep = { ...base, dish: false, netText: "800", netGrams: 800, ratio: 0.8 };
    const kpis = sheetKpis(prep);
    expect(kpis.map((k) => k.label)).toEqual([
      "Costo total",
      "Costo por kg neto",
      "Peso bruto → neto",
      "Rendimiento",
    ]);
    // 5000 $ ÷ 0,8 kg = 6250 $ por kg neto.
    expect(kpis[1]?.value).toMatch(/6\.250/);
    expect(kpis[2]?.value).toBe("1.000 g → 800 g");
    expect(kpis[3]?.value).toBe("80,0 %");
  });

  it("quien no ve costos no ve dinero: tiempo total e ingredientes con peso", () => {
    for (const dish of [true, false]) {
      const kpis = sheetKpis({ ...base, dish, money: false });
      expect(kpis).toHaveLength(4);
      expect(kpis.map((k) => k.label)).toContain("Tiempo total");
      expect(kpis.map((k) => k.label)).toContain("Ingredientes con peso");
      for (const k of kpis) expect(String(k.value ?? "")).not.toMatch(money);
    }
    expect(labels({ ...base, money: false })).not.toContain("Costo total");
  });

  it("con permiso de costos pero sin local: «—» y el motivo, nunca $ 0", () => {
    const [total, perPortion] = sheetKpis({ ...base, place: null });
    expect(total?.value).toBeNull();
    expect(total?.missingReason).toBe("Elegí un local arriba para ver el costo.");
    expect(perPortion?.value).toBeNull();
    expect(metricView(total!).value).toBe("—");
  });

  it("si falta el costo de una fila, el total no se supone: queda vacío con el motivo", () => {
    const [total] = sheetKpis({ ...base, cost: null, missingCost: 1 });
    expect(total?.value).toBeNull();
    expect(total?.missingReason).toBe("Incompleto: falta el costo de 1 fila.");
  });

  it("sin peso de la porción, las porciones dicen por qué", () => {
    const kpis = sheetKpis({ ...base, portionText: "", portionGrams: null, portions: null });
    const portions = kpis.find((k) => k.key === "porciones");
    expect(portions?.value).toBeNull();
    expect(portions?.missingReason).toBe("Sin peso de porción.");
  });

  it("las porciones cargadas a mano (platos viejos) se ven y se dicen", () => {
    const kpis = sheetKpis({ ...base, portionText: "", portions: null, manualPortions: 6 });
    const portions = kpis.find((k) => k.key === "porciones");
    expect(portions?.value).toBe("6");
    expect(portions?.statusLabel).toBe("Cargadas a mano");
  });

  it("una preparación que rinde en litros no calcula el rendimiento en peso", () => {
    const kpis = sheetKpis({ ...base, dish: false, netText: "2", netGrams: null, ratio: null });
    expect(kpis.find((k) => k.key === "rendimiento")?.missingReason).toBe(
      "Rinde en volumen o en unidades: se calcula solo en peso.",
    );
  });

  it("sin ingredientes, «Ingredientes con peso» dice que no hay (nunca «Completo»)", () => {
    const kpis = sheetKpis({ ...base, money: false, lines: 0, grams: null });
    const weighed = kpis.find((k) => k.key === "con-peso")!;
    expect(metricView(weighed).statusLabel).toBe("Sin datos");
  });

  it("con más de la mitad sin peso, «Ingredientes con peso» es crítico", () => {
    const kpis = sheetKpis({ ...base, money: false, lines: 3, missingGrams: 2, grams: null });
    const weighed = kpis.find((k) => k.key === "con-peso")!;
    expect(metricView(weighed).status).toBe("bad");
    expect(weighed.value).toBe(1);
  });
});

describe("la marca de quien revisa", () => {
  it("una cantidad que cambió dice cuánto era; una fila nueva, «Nueva»", () => {
    expect(reviewMark({ change: "changed", unit: "g", oldQuantity: 380 })).toBe("antes 380 g");
    expect(reviewMark({ change: "added", unit: "g", oldQuantity: null })).toBe("Nueva");
    expect(reviewMark({ change: "removed", unit: "g", oldQuantity: 5 })).toBeNull();
  });
});

describe("el estado del total", () => {
  it("completo, incompleto con cuántos datos faltan o sin ingredientes", () => {
    expect(totalState(3, 0)).toEqual({ status: "ok", label: "Completo" });
    expect(totalState(3, 1)).toEqual({ status: "warn", label: "Incompleto: falta 1 dato" });
    expect(totalState(3, 2).label).toBe("Incompleto: faltan 2 datos");
    expect(totalState(0, 0).status).toBe("none");
  });
});
