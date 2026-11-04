// Etiquetas y orden de las pantallas de costos (ADR-0032). La cuenta está en la base y se prueba con pgTAP.
import { describe, expect, it } from "vitest";

import { formatDifference, formatPercent, lineStatusLabel } from "@/lib/cost-labels";
import { pickCostPlace, sortCostLines, type CostLine } from "@/lib/costs";
import { formatMoney, perBaseLabel } from "@/lib/money";

describe("qué le falta a una línea", () => {
  it("una línea bien no dice nada; una incompleta, qué falta", () => {
    expect(lineStatusLabel("ok")).toBeNull();
    expect(lineStatusLabel("missing_price")).toBe("Falta el precio");
    expect(lineStatusLabel("incomplete_sub_recipe")).toBe("La preparación está incompleta");
  });

  it("un estado desconocido nunca se ve en inglés", () => {
    expect(lineStatusLabel("otro_estado")).toBe("Falta un dato");
  });
});

describe("el orden de las líneas", () => {
  const line = (order: number, cost: number | null, missing: string | null = null): CostLine => ({
    order,
    item: `Línea ${order}`,
    quantity: 1,
    unit: "g",
    cost,
    gross: cost,
    share: null,
    missing,
  });

  it("primero lo que falta, después de mayor a menor", () => {
    const sorted = sortCostLines([line(1, 10), line(2, 500), line(3, null, "Falta el precio")]);
    expect(sorted.map((l) => l.order)).toEqual([3, 2, 1]);
  });
});

describe("de qué local se habla", () => {
  const a = { id: "a", name: "Local A" };
  const b = { id: "b", name: "Local B" };

  it("vale el pedido si la persona lo puede ver", () => {
    expect(pickCostPlace([a, b], "b", "a")).toBe(b);
  });

  it("un local ajeno en la dirección no vale: usa el elegido arriba", () => {
    expect(pickCostPlace([a, b], "otro", "a")).toBe(a);
  });

  it("con un solo local, ese; con varios y sin elegir, ninguno", () => {
    expect(pickCostPlace([a], undefined, null)).toBe(a);
    expect(pickCostPlace([a, b], undefined, null)).toBeNull();
  });
});

describe("cómo se muestran los números", () => {
  it("lo que no se sabe sale como una raya, nunca como $ 0", () => {
    expect(formatMoney(null)).toBe("—");
    expect(formatPercent(null)).toBe("—");
    expect(formatDifference(null)).toBe("—");
  });

  it("una suba lleva el signo", () => {
    expect(formatDifference(12.5)).toBe("+12,5 %");
    expect(formatDifference(-3)).toBe("-3 %");
  });

  it("el costo por gramo se muestra por kilo", () => {
    expect(perBaseLabel("g")).toEqual({ factor: 1000, label: "por kg" });
  });
});
