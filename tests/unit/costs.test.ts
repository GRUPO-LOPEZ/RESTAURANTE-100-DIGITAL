// Etiquetas y orden de las pantallas de costos (ADR-0032). La cuenta está en la base y se prueba con pgTAP.
import { describe, expect, it } from "vitest";

import { REASON_LABELS, formatDifference, formatPercent, lineStatusLabel } from "@/lib/cost-labels";
import {
  costListMetrics,
  costTip,
  missingSummary,
  pickCostPlace,
  sortCostLines,
  type CostLine,
} from "@/lib/costs";
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

describe("por qué cambió un costo", () => {
  it("los motivos automáticos también se leen en español", () => {
    expect(REASON_LABELS.daily).toBe("Actualización diaria");
    expect(REASON_LABELS.month_end).toBe("Cierre de mes");
  });
});

describe("el orden de las líneas", () => {
  const line = (
    order: number,
    cost: number | null,
    missing: string | null = null,
    extra: Partial<CostLine> = {},
  ): CostLine => ({
    order,
    item: `Línea ${order}`,
    quantity: 1,
    unit: "g",
    cost,
    gross: cost,
    share: null,
    missing,
    ...extra,
  });

  // Pedido de Soy (ADR-0048): de la que más pesa a la que menos; lo que falta, al final (la franja de arriba lo avisa).
  it("de mayor a menor y lo que falta al final", () => {
    const sorted = sortCostLines([line(1, 10), line(3, null, "Falta el precio"), line(2, 500)]);
    expect(sorted.map((l) => l.order)).toEqual([2, 1, 3]);
  });

  it("a igual costo, el orden de la receta", () => {
    const sorted = sortCostLines([line(2, 100), line(1, 100)]);
    expect(sorted.map((l) => l.order)).toEqual([1, 2]);
  });

  describe("la franja de lo que falta", () => {
    it("sin faltas, no hay franja", () => {
      expect(missingSummary([line(1, 10)])).toBeNull();
    });

    it("una falta dice cuál y por qué", () => {
      expect(
        missingSummary([line(1, 10), line(2, null, "Falta el precio", { item: "Comino" })]),
      ).toBe("Falta un dato: Comino, falta el precio.");
    });

    it("varias: las primeras y cuántas más", () => {
      const lines = [
        line(1, null, "Falta el precio", { item: "Comino" }),
        line(2, null, "Falta el rendimiento", { item: "Cebolla" }),
        line(3, null, "Falta el precio", { item: "Ají" }),
      ];
      expect(missingSummary(lines)).toBe(
        "Faltan 3 datos: Comino, falta el precio; Cebolla, falta el rendimiento y 1 más.",
      );
    });
  });

  describe("para bajar el costo", () => {
    it("nombra la línea que más pesa y su parte del total", () => {
      const lines = [line(1, 250, null, { item: "Harina" }), line(2, 750, null, { item: "Queso" })];
      expect(costTip(lines, 1000)).toBe(
        "Queso es el 75 % del costo. Un cambio de precio o de cantidad ahí es lo que más mueve el total.",
      );
    });

    it("usa el porcentaje de la base si lo trae, y marca las preparaciones", () => {
      const lines = [
        line(1, 600, null, { item: "Salsa bolognesa", share: 66.6, preparation: true }),
      ];
      expect(costTip(lines, 900)).toBe(
        "Salsa bolognesa (una preparación) es el 66,6 % del costo. Un cambio de precio o de cantidad ahí es lo que más mueve el total.",
      );
    });

    it("con un dato faltante, primero hay que completarlo (sin total no hay contra qué medir)", () => {
      expect(costTip([line(1, 100), line(2, null, "Falta el precio")], null)).toBe(
        "Primero hay que completar el dato que falta.",
      );
      expect(
        costTip([line(1, null, "Falta el precio"), line(2, null, "Falta el precio")], null),
      ).toBe("Primero hay que completar los 2 datos que faltan.");
    });

    it("sin líneas con costo no inventa nada", () => {
      expect(costTip([], 0)).toBeNull();
      expect(costTip([line(1, 0)], 0)).toBeNull();
    });
  });
});

describe("los indicadores de la lista", () => {
  const byKey = (summary: Parameters<typeof costListMetrics>[0]) =>
    Object.fromEntries(costListMetrics(summary).map((m) => [m.key, m]));

  it("sin recetas con costo, sin datos (nunca «Todas al día»)", () => {
    const m = byKey({ total: 0, complete: 0, stale: 0, incomplete: 0 });
    expect(m.up_to_date?.status).toBe("none");
    expect(m.stale?.status).toBe("none");
    expect(m.incomplete?.filter).toBeUndefined();
  });

  it("todo completo: al día, y nada para ver", () => {
    const m = byKey({ total: 4, complete: 4, stale: 0, incomplete: 0 });
    expect(m.up_to_date).toMatchObject({ status: "ok", statusLabel: "Todas al día" });
    expect(m.stale).toMatchObject({ status: "ok", statusLabel: "Ninguna" });
    expect(m.stale?.filter).toBeUndefined();
  });

  it("la regla única: la mitad o menos, atención; más de la mitad, crítico", () => {
    const m = byKey({ total: 10, complete: 4, stale: 5, incomplete: 1 });
    expect(m.up_to_date).toMatchObject({ status: "bad", statusLabel: "Faltan 6" });
    expect(m.stale).toMatchObject({ status: "warn", statusLabel: "Vencidas: 5", filter: "stale" });
    expect(m.incomplete).toMatchObject({
      status: "warn",
      statusLabel: "Sin total: 1",
      filter: "incomplete",
    });
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
