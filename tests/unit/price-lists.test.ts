import { describe, expect, it } from "vitest";

import {
  changeLabel,
  contentWords,
  netListPrice,
  packageFactorWords,
  parseDecimal,
  priceListItemSchema,
  priceListSchema,
  shownStatus,
} from "@/lib/price-lists";

// Listas de precios y cola de mapeo (ADR-0052): las reglas de la pantalla. La base hace las mismas cuentas
// (purchasing.net_list_price) y las prueba pgTAP (330).
describe("neto de un renglón de lista", () => {
  it("caso 5: 100 con 15 % y 10 % da 76,50", () => {
    expect(netListPrice(100, 15, 10)).toBe(76.5);
  });
  it("la bonificación en pesos se resta después de los porcentajes (P6)", () => {
    expect(netListPrice(100, 15, 10, 5)).toBe(71.5);
  });
  it("sin bonificaciones, el neto es el precio de lista", () => {
    expect(netListPrice(1234.5)).toBe(1234.5);
  });
  it("redondea a 4 decimales, como la base", () => {
    expect(netListPrice(10, 33.333)).toBe(6.6667);
  });
});

describe("el factor del envase en palabras", () => {
  it("una bolsa de 50 kg", () => {
    expect(packageFactorWords("Bolsa", 1, 50000, "g")).toBe("1 bolsa = 50 kg");
  });
  it("una caja de 12 litros", () => {
    expect(packageFactorWords("Caja", 12, 1000, "ml")).toBe("1 caja = 12 × 1 l (12 l)");
  });
  it("un maple de 30 huevos", () => {
    expect(packageFactorWords("Maple", 30, 1, "unit")).toBe(
      "1 maple = 30 × 1 unidad (30 unidades)",
    );
  });
  it("sin datos completos no inventa un factor", () => {
    expect(packageFactorWords("Bolsa", 0, 50, "g")).toBeNull();
    expect(packageFactorWords("Bolsa", 1, 0, "g")).toBeNull();
    expect(packageFactorWords(" ", 1, 50, "g")).toBeNull();
  });
  it("las cantidades chicas quedan en g o ml, con coma decimal", () => {
    expect(contentWords(500, "ml")).toBe("500 ml");
    expect(contentWords(1500, "g")).toBe("1,5 kg");
  });
});

describe("números escritos a mano", () => {
  it("acepta coma decimal y puntos de miles", () => {
    expect(parseDecimal("1.234,50")).toBe(1234.5);
    expect(parseDecimal("76,5")).toBe(76.5);
    expect(parseDecimal("76.5")).toBe(76.5);
  });
  it("lo que no es un número queda vacío", () => {
    expect(parseDecimal("")).toBeNull();
    expect(parseDecimal("doce")).toBeNull();
    expect(parseDecimal("1,2,3")).toBeNull();
  });
});

describe("la variación entre listas", () => {
  it("con signo y palabra", () => {
    expect(changeLabel(8)).toBe("+8 %");
    expect(changeLabel(-3.5)).toBe("−3,5 %");
    expect(changeLabel(0)).toBe("Igual");
    expect(changeLabel(null)).toBe("Nuevo");
  });
  it("una aceptada vencida se muestra como Vencida", () => {
    expect(shownStatus("accepted", true)).toBe("expired");
    expect(shownStatus("accepted", false)).toBe("accepted");
    expect(shownStatus("replaced", true)).toBe("replaced");
  });
});

describe("el esquema de la grilla", () => {
  const ok = {
    name: "Harina 000 x 25 kg",
    list_price: 100,
    bonus1_pct: 0,
    bonus2_pct: 0,
    bonus_per_unit_amount: 0,
    vat_rate: 10.5,
  };
  it("acepta un renglón completo, con las alícuotas de 2,5 y 5 % (P5)", () => {
    expect(priceListItemSchema.safeParse(ok).success).toBe(true);
    expect(priceListItemSchema.safeParse({ ...ok, vat_rate: 2.5 }).success).toBe(true);
    expect(priceListItemSchema.safeParse({ ...ok, vat_rate: 5 }).success).toBe(true);
  });
  it("rechaza una alícuota que no existe", () => {
    expect(priceListItemSchema.safeParse({ ...ok, vat_rate: 19 }).success).toBe(false);
  });
  it("rechaza un neto en cero o negativo", () => {
    const result = priceListItemSchema.safeParse({
      ...ok,
      bonus1_pct: 50,
      bonus2_pct: 50,
      bonus_per_unit_amount: 30,
    });
    expect(result.success).toBe(false);
    expect(result.error?.issues[0]?.message).toBe(
      "Con esas bonificaciones el neto queda en cero o negativo.",
    );
  });
  it("rechaza bonificaciones de 100 % o negativas, y un precio en cero", () => {
    expect(priceListItemSchema.safeParse({ ...ok, bonus1_pct: 100 }).success).toBe(false);
    expect(priceListItemSchema.safeParse({ ...ok, bonus2_pct: -1 }).success).toBe(false);
    expect(priceListItemSchema.safeParse({ ...ok, list_price: 0 }).success).toBe(false);
  });
  it("una lista sin renglones o sin motivo no se carga", () => {
    const base = {
      supplier_id: "00000000-0000-4000-8000-000000000904",
      received_on: "2026-11-16",
      valid_from: "2026-11-16",
      items: [ok],
      reason: "Llegó la lista",
    };
    expect(priceListSchema.safeParse(base).success).toBe(true);
    expect(priceListSchema.safeParse({ ...base, items: [] }).success).toBe(false);
    expect(priceListSchema.safeParse({ ...base, reason: "x" }).success).toBe(false);
  });
});
