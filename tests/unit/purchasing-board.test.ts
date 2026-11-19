// Tablero de compras (Fase 3, Prompt 6, ADR-0060): las barras del gasto, las líneas de los insumos y la franja de
// atención.
import { describe, expect, it } from "vitest";

import {
  alertParts,
  historyRows,
  lastChange,
  spendBars,
  urgentCount,
} from "@/lib/purchasing-board";

describe("el gasto por rubro", () => {
  it("muestra hasta 5 rubros, junta el resto y deja fletes y percepciones aparte", () => {
    const rows = [
      ...["A", "B", "C", "D", "E", "F", "G"].map((label, i) => ({
        label,
        kind: "recipes" as const,
        amount: 100 - i * 10,
      })),
      { label: "Fletes y servicios", kind: "freight" as const, amount: 30 },
      { label: "Percepciones", kind: "perception" as const, amount: 0 },
    ];
    expect(spendBars(rows).map((b) => `${b.label}:${b.amount}`)).toEqual([
      "A:100",
      "B:90",
      "C:80",
      "D:70",
      "E:60",
      "Otros rubros:90",
      "Fletes y servicios:30",
    ]);
  });

  it("sin compras, sin barras", () => {
    expect(spendBars([])).toEqual([]);
  });
});

describe("cómo subieron los insumos", () => {
  const series = [
    {
      ingredient_id: "a",
      name: "Tomate",
      points: [
        { on: "2026-10-01", change_pct: 0 },
        { on: "2026-11-01", change_pct: 12.5 },
      ],
    },
    { ingredient_id: "b", name: "Harina", points: [{ on: "2026-10-15", change_pct: 0 }] },
    { ingredient_id: "c", name: "Sin precio", points: null },
  ];

  it("una fila por fecha, vacía donde no hubo precio", () => {
    expect(historyRows(series)).toEqual([
      { on: "2026-10-01", a: 0, b: null, c: null },
      { on: "2026-10-15", a: null, b: 0, c: null },
      { on: "2026-11-01", a: 12.5, b: null, c: null },
    ]);
  });

  it("la última variación de cada una", () => {
    expect(series.map(lastChange)).toEqual([12.5, 0, null]);
  });
});

describe("requiere atención", () => {
  const kinds = { unmapped_article: 4, payment_due: 1, invoice_observed: 2, order_news: 1 };

  it("de la más grave, en palabras y con plural", () => {
    expect(alertParts(kinds)).toEqual([
      "2 facturas observadas",
      "1 pago por vencer",
      "1 OC con novedad",
    ]);
  });

  it("los artículos sin mapear no cuentan para la franja", () => {
    expect(urgentCount(kinds)).toBe(4);
    expect(urgentCount({ unmapped_article: 3 })).toBe(0);
  });
});
