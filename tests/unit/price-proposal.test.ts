// «Proponer precio» (ADR-0067): los textos del resultado, quién lo aprueba y lo que se completa solo.
import { describe, expect, it } from "vitest";

import { isChecked, schemas } from "@/lib/forms/schemas";
import { parseMoney } from "@/lib/money";
import {
  approversText,
  previewText,
  productDefaults,
  proposalSummary,
  type PricePreview,
} from "@/lib/price-proposal";

const preview = (over: Partial<PricePreview> = {}): PricePreview => ({
  netUnitCost: 1.176,
  grossUnitCost: 1.423,
  baseUnit: "g",
  variation: 4,
  variationToday: 4,
  variationLookback: null,
  lookbackDays: 30,
  first: false,
  direction: false,
  ...over,
});
const text = (p: PricePreview, invoice = true) => previewText(p, invoice).replace(/\s/g, " ");

describe("cómo queda", () => {
  it("por kilo, sin IVA, y cuánto sube contra hoy", () => {
    expect(text(preview())).toBe(
      "Queda $ 1.176,00 por kg sin IVA: sube 4 % contra el precio de hoy.",
    );
  });
  it("baja, con decimales", () => {
    expect(text(preview({ variation: -12.04, variationToday: -12.04 }))).toContain(
      "baja 12,04 % contra el precio de hoy.",
    );
  });
  it("si pesa más la de hace N días, lo dice", () => {
    expect(
      text(preview({ variation: 40.5, variationToday: 12, variationLookback: 40.5 })),
    ).toContain("sube 40,5 % contra el de hace 30 días.");
  });
  it("igual que hoy, y el primer precio", () => {
    expect(text(preview({ variation: 0, variationToday: 0 }))).toContain(
      "igual que el precio de hoy.",
    );
    expect(text(preview({ variation: null, variationToday: null, first: true }))).toContain(
      "Es el primer precio en ese lugar.",
    );
  });
  it("por litro o por unidad; sin factura no habla de IVA", () => {
    expect(text(preview({ baseUnit: "ml" }))).toContain("por litro");
    expect(text(preview({ baseUnit: "unit", netUnitCost: 250 }), false)).toBe(
      "Queda $ 250,00 por unidad: sube 4 % contra el precio de hoy.",
    );
  });
});

describe("quién lo aprueba", () => {
  it("el Controller, o también Dirección si cambia mucho", () => {
    expect(approversText({ direction: false })).toBe("Lo aprueba el Controller.");
    expect(approversText({ direction: true })).toBe(
      "Lo aprueban el Controller y Dirección General.",
    );
  });
});

describe("lo que se completa al elegir un producto", () => {
  const rows = [
    { productId: "a", vatRate: null },
    { productId: "b", vatRate: 27 },
    { productId: "a", vatRate: 10.5 },
    { productId: "a", vatRate: 21 },
  ];
  it("la alícuota de su último precio con IVA; si no hay, 21 %", () => {
    expect(productDefaults("a", null, rows, new Set()).vatRate).toBe("10.5");
    expect(productDefaults("z", null, rows, new Set()).vatRate).toBe("21");
    expect(productDefaults("z", null, [{ productId: "z", vatRate: 99 }], new Set()).vatRate).toBe(
      "21",
    );
  });
  it("su proveedor, si sigue activo", () => {
    expect(productDefaults("a", "s1", rows, new Set(["s1"])).supplierId).toBe("s1");
    expect(productDefaults("a", "s1", rows, new Set(["s2"])).supplierId).toBe("");
  });
});

describe("el resumen de «Más datos»", () => {
  const v = {
    invoice: true,
    vatRate: "10.5",
    supplier: "Verdulería",
    discount: "",
    testValue: false,
    notes: "",
  };
  it("dice lo que va a viajar", () => {
    expect(proposalSummary(v)).toBe("Factura · IVA 10,5 % · Verdulería");
    expect(
      proposalSummary({
        ...v,
        invoice: false,
        supplier: null,
        discount: "150",
        testValue: true,
        notes: "x",
      }),
    ).toMatch(
      /^Sin factura · sin proveedor · descuento \$\s150,00 · valor de prueba · con observaciones$/,
    );
    expect(proposalSummary({ ...v, discount: "$ 1.500" })).toMatch(/descuento \$\s1\.500,00$/);
    expect(proposalSummary({ ...v, discount: "abc" })).not.toContain("descuento");
  });
});

describe("un sí o no de formulario", () => {
  it("vale como casilla o como toggle", () => {
    expect(["on", true, "true"].every((x) => isChecked(x))).toBe(true);
    expect(["", false, "false", undefined].some((x) => isChecked(x))).toBe(false);
  });
  it("el 0 % de merma pide declararlo, también con el toggle", () => {
    const waste = { cleaning_loss: "0", thawing_loss: "", reason: "Prueba" };
    expect(schemas.waste.safeParse({ ...waste, declared_no_loss: "false" }).success).toBe(false);
    expect(schemas.waste.safeParse({ ...waste, declared_no_loss: "true" }).success).toBe(true);
  });
});

describe("los importes se leen como se escriben acá", () => {
  const base = {
    product_id: "p",
    place: "group:x",
    valid_from: "2026-11-25",
    document_type: "no_invoice",
    source: "manual",
    reason: "Prueba",
  };
  const ok = (package_price: string, discount_amount = "") =>
    schemas.priceProposal.safeParse({ ...base, package_price, discount_amount }).success;
  it("«26.000» son veintiséis mil, con o sin signo", () => {
    expect(parseMoney("26.000")).toBe(26000);
    expect(parseMoney("$ 26.000,50")).toBe(26000.5);
    expect(parseMoney("1500,5")).toBe(1500.5);
    expect(parseMoney("1.50")).toBe(1.5);
    expect(parseMoney("12,")).toBeNull();
    expect(["26.000", "$ 26.000,50", "1.500,25", "900"].every((v) => ok(v))).toBe(true);
  });
  it("ni cero, ni texto, ni más de 4 decimales; el descuento, menor que el precio", () => {
    expect(["0", "", "abc", "12,", "1,23456", "99999999999"].some((v) => ok(v))).toBe(false);
    expect(ok("26.000", "1.500")).toBe(true);
    expect(ok("26.000", "26.000")).toBe(false);
  });
});
