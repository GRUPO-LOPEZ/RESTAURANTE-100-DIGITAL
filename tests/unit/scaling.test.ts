// Escalado (ADR-0032). La cuenta está en la base y se prueba con pgTAP; acá, lo que lee la pantalla y el editor.
import { describe, expect, it } from "vitest";

import { recipeStepsSchema } from "@/lib/forms/schemas";
import { parseAmount } from "@/lib/money";
import { parseScaled } from "@/lib/scaling";

const step = {
  kind: "preparation",
  instructions: "Hornear",
  active_minutes: "10",
  passive_minutes: "0",
  equipment: "Horno",
  equipment_capacity: "4,5",
  equipment_capacity_unit: "",
  depends_on: [],
};

describe("un número como se escribe acá", () => {
  it("el punto de los miles no es una coma", () => {
    expect(parseAmount("1.500")).toBe(1500);
    expect(parseAmount("2.500,5")).toBe(2500.5);
    expect(parseAmount("1.000.000")).toBe(1000000);
  });

  it("la coma y el punto decimal valen", () => {
    expect(parseAmount("2,5")).toBe(2.5);
    expect(parseAmount("2.5")).toBe(2.5);
    expect(parseAmount("0.500")).toBe(0.5);
    expect(parseAmount("25")).toBe(25);
  });

  it("lo demás no es un número", () => {
    expect(parseAmount("abc")).toBeNull();
    expect(parseAmount("10 kg")).toBeNull();
    expect(parseAmount("")).toBeNull();
  });
});

describe("la capacidad del equipo", () => {
  it("acepta coma decimal y puede quedar vacía", () => {
    expect(recipeStepsSchema.safeParse([step]).success).toBe(true);
    expect(recipeStepsSchema.safeParse([{ ...step, equipment_capacity: "" }]).success).toBe(true);
  });

  it("pide el equipo", () => {
    expect(recipeStepsSchema.safeParse([{ ...step, equipment: "" }]).success).toBe(false);
  });

  it("tiene que ser un número mayor que cero", () => {
    expect(recipeStepsSchema.safeParse([{ ...step, equipment_capacity: "0" }]).success).toBe(false);
    expect(recipeStepsSchema.safeParse([{ ...step, equipment_capacity: "mucho" }]).success).toBe(
      false,
    );
  });
});

describe("lo que devuelve la base", () => {
  const data = {
    factor: 2.5,
    exact_factor: 2.5,
    target_portions: 25,
    target_yield: 5,
    yield_unit: "kg",
    lines: [{ order: 1, item: "Papa", unit: "g", quantity: 1000, scaled: 2500, no_scale: false }],
    steps: [{ number: 1, equipment: "Horno", capacity: 3, capacity_unit: "kg", batches: 2 }],
  };

  it("se lee con los nombres de la pantalla", () => {
    const scaled = parseScaled(data);
    expect(scaled?.factor).toBe(2.5);
    expect(scaled?.lines[0]?.noScale).toBe(false);
    expect(scaled?.steps[0]?.batches).toBe(2);
  });

  it("si la forma no es la esperada, no se muestra nada a medias", () => {
    expect(parseScaled({ factor: "mucho" })).toBeNull();
  });
});
