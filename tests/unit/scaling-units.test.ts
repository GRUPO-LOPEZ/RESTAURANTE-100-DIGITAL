// Hacer varias recetas (ADR-0065): cada línea en su unidad, sin densidad. La misma regla que recipes.scale_version.
import { describe, expect, it } from "vitest";

import { amountText, scaleLine, spoonEquivalent, toBigger, unitText } from "@/lib/scaling-units";

describe("cada línea se multiplica en su unidad", () => {
  it("litros sin densidad: no hace falta para multiplicar (la causa del pedido de Soy)", () => {
    const line = scaleLine(1.2, "l", 2);
    expect(line).toEqual({ value: 2.4, unit: "l" });
    expect(line === null ? null : amountText(line)).toBe("2,4 l");
  });

  it("pasa a la unidad mayor al llegar a 1.000", () => {
    expect(scaleLine(480, "g", 12)).toEqual({ value: 5.76, unit: "kg" });
    expect(scaleLine(100, "ml", 12)).toEqual({ value: 1.2, unit: "l" });
    expect(scaleLine(100, "cc", 10)).toEqual({ value: 1, unit: "l" });
    expect(scaleLine(999.9, "g", 1)).toEqual({ value: 999.9, unit: "g" });
    expect(scaleLine(1000, "g", 1)).toEqual({ value: 1, unit: "kg" });
    expect(toBigger({ value: 2_500_000, unit: "mg" })).toEqual({ value: 2.5, unit: "kg" });
  });

  it("nunca baja de unidad ni cambia las demás", () => {
    expect(scaleLine(0.5, "kg", 1)).toEqual({ value: 0.5, unit: "kg" });
    expect(scaleLine(1500, "unit", 2)).toEqual({ value: 3000, unit: "unit" });
    expect(scaleLine(1000, "oz", 2)).toEqual({ value: 2000, unit: "oz" });
    expect(scaleLine(1000, "tbsp", 2)).toEqual({ value: 2000, unit: "tbsp" });
  });

  it("sin el error de los decimales binarios", () => {
    expect(scaleLine(0.1, "l", 3)).toEqual({ value: 0.3, unit: "l" });
  });

  it("«no se multiplica» queda igual, pero se lee en la unidad que corresponde", () => {
    expect(scaleLine(10, "g", 12, true)).toEqual({ value: 10, unit: "g" });
    expect(scaleLine(1500, "g", 12, true)).toEqual({ value: 1.5, unit: "kg" });
  });

  it("sin la cantidad, la unidad o cuántas recetas, no hay número", () => {
    expect(scaleLine(null, "g", 2)).toBeNull();
    expect(scaleLine(10, "", 2)).toBeNull();
    expect(scaleLine(10, "g", null)).toBeNull();
  });
});

describe("cómo se escribe", () => {
  it("el plural de las unidades", () => {
    expect(unitText(1, "unit")).toBe("unidad");
    expect(unitText(72, "unit")).toBe("unidades");
    expect(unitText(6, "dozen")).toBe("docenas");
    expect(unitText(48, "portion")).toBe("porciones");
    expect(unitText(2, "cup")).toBe("tazas");
    expect(unitText(0.5, "cup")).toBe("taza");
    expect(unitText(8, "tbsp")).toBe("cda");
    expect(unitText(2, "kg")).toBe("kg");
    expect(unitText(2, "otra")).toBe("otra");
  });
});

describe("cucharadas, cucharaditas y tazas", () => {
  const eq = (value: number, unit: string) => spoonEquivalent({ value, unit });
  it("desde el umbral, cuánto es en ml", () => {
    expect(eq(8, "tbsp")).toBe("120 ml");
    expect(eq(4, "tbsp")).toBe("60 ml");
    expect(eq(3.99, "tbsp")).toBeNull();
    expect(eq(6, "tsp")).toBe("30 ml");
    expect(eq(5, "tsp")).toBeNull();
    expect(eq(2, "cup")).toBe("480 ml");
    expect(eq(1.5, "cup")).toBeNull();
    expect(eq(12, "cup")).toBe("2,88 l");
  });
  it("la pizca es de peso: va en gramos. De volumen a peso, nunca", () => {
    expect(eq(10, "pinch")).toBe("5 g");
    expect(eq(100, "tbsp")).toBe("1,5 l");
  });
  it("las demás no llevan equivalente", () => {
    expect(eq(5000, "g")).toBeNull();
    expect(eq(50, "unit")).toBeNull();
  });
});
