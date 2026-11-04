import { describe, expect, it } from "vitest";

import { SCENARIO_RELIABILITY, formatMoneyDifference } from "@/lib/cost-labels";
import { schemas } from "@/lib/forms/schemas";

const reason = "Simular";

describe("formatMoneyDifference", () => {
  it("muestra el signo de la diferencia", () => {
    expect(formatMoneyDifference(1500)).toMatch(/^\+\$\s?1\.500/);
    expect(formatMoneyDifference(-1500)).toMatch(/^-\$\s?1\.500/);
  });

  it("cero va sin signo, y sin dato, una raya", () => {
    expect(formatMoneyDifference(0)).toMatch(/^\$\s?0/);
    expect(formatMoneyDifference(null)).toBe("—");
  });
});

describe("las etiquetas de lo simulado", () => {
  it("dicen simulado, y ninguna se lee como un costo verificado", () => {
    for (const { label, status } of Object.values(SCENARIO_RELIABILITY)) {
      expect(label).toMatch(/^Simulado/);
      expect(label).not.toMatch(/verificado/i);
      expect(status).not.toBe("ok");
    }
  });
});

describe("el formulario de un escenario", () => {
  it("pide nombre y motivo", () => {
    expect(schemas.scenario.safeParse({ name: "La mozzarella sube", reason }).success).toBe(true);
    expect(schemas.scenario.safeParse({ name: "  ", reason }).success).toBe(false);
    expect(schemas.scenario.safeParse({ name: "Sube", reason: "" }).success).toBe(false);
  });
});

describe("el precio simulado", () => {
  const price = (amount: string) =>
    schemas.scenarioPrice.safeParse({ ingredient: "x", amount, reason }).success;

  it("se escribe como en la pantalla", () => {
    expect(price("12.500")).toBe(true);
    expect(price("2,5")).toBe(true);
  });

  it("es un número mayor que cero", () => {
    expect(price("0")).toBe(false);
    expect(price("-5")).toBe(false);
    expect(price("mucho")).toBe(false);
    expect(price("")).toBe(false);
  });

  it("pide la materia prima", () => {
    expect(schemas.scenarioPrice.safeParse({ ingredient: "", amount: "5", reason }).success).toBe(
      false,
    );
  });
});

describe("el rendimiento simulado", () => {
  const yields = (cleaning: string, cooking: string) =>
    schemas.scenarioYield.safeParse({ ingredient: "x", cleaning, cooking, reason }).success;

  it("va hasta 100 % de limpieza", () => {
    expect(yields("100", "1")).toBe(true);
    expect(yields("100,5", "1")).toBe(false);
    expect(yields("0", "1")).toBe(false);
  });

  it("y hasta un factor de 10", () => {
    expect(yields("80", "10")).toBe(true);
    expect(yields("80", "11")).toBe(false);
  });
});

describe("el gramaje simulado", () => {
  it("pide la línea y una cantidad mayor que cero", () => {
    const parse = (line: string, quantity: string) =>
      schemas.scenarioQuantity.safeParse({ line, quantity, reason }).success;
    expect(parse("x", "270")).toBe(true);
    expect(parse("", "270")).toBe(false);
    expect(parse("x", "0")).toBe(false);
  });
});
