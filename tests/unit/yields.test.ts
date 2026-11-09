// Rendimientos (etapa 2.1 B): cómo se muestran y qué aceptan los formularios.
import { describe, expect, it } from "vitest";

import { fieldErrors, schemas } from "@/lib/forms/schemas";
import {
  cleaningDifference,
  describeCooking,
  exceedsYieldAlert,
  formatCleaning,
  measuredCleaning,
  measuredCooking,
  parseDecimal,
  yieldDeviationPct,
} from "@/lib/yields";

// Por las dudas, cualquier espacio se compara como espacio común.
const plain = (text: string) => text.replace(/\s/g, " ");

describe("cómo se muestra un rendimiento", () => {
  it("la limpieza va en % con 1 decimal", () => {
    expect(plain(formatCleaning(0.8))).toBe("80,0 %");
    expect(plain(formatCleaning(0.7654))).toBe("76,5 %");
  });

  it("la cocción es merma si pierde peso y expansión si gana: nunca merma negativa", () => {
    expect(plain(describeCooking(0.85))).toBe("merma de cocción 15,0 %");
    expect(describeCooking(2.5)).toBe("se expande ×2,5");
    expect(describeCooking(1)).toBe("sin cambio en la cocción");
    expect(describeCooking(2.5)).not.toContain("-");
  });

  it("lo medido sale de los pesos, y sin el par no hay número", () => {
    expect(measuredCleaning(10000, 7700)).toBeCloseTo(0.77);
    expect(measuredCooking(1000, 2450)).toBeCloseTo(2.45);
    expect(measuredCleaning(10000, undefined)).toBeUndefined();
    expect(measuredCooking(0, 100)).toBeUndefined();
  });

  it("la diferencia contra el estándar se dice con palabras, sin signos", () => {
    expect(cleaningDifference(0.77, 0.8)).toBe("3,0 puntos menos que el estándar");
    expect(cleaningDifference(0.815, 0.8)).toBe("1,5 puntos más que el estándar");
    expect(cleaningDifference(0.81, 0.8)).toBe("1,0 punto más que el estándar");
    expect(cleaningDifference(0.8, 0.8)).toBe("igual al estándar");
  });

  it("acepta coma o punto decimal", () => {
    expect(parseDecimal("78,5")).toBe(78.5);
    expect(parseDecimal("2.5")).toBe(2.5);
  });
});

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

const test = {
  process_id: "00000000-0000-4000-8000-000000000961",
  restaurant_id: "00000000-0000-4000-8000-000000000201",
  tested_on: "2026-10-29",
  samples: "2",
  gross_weight: "10000",
  clean_weight: "7700",
  before_cooking_weight: "",
  after_cooking_weight: "",
  reason: "Ensayo",
};

describe("formulario de ensayo", () => {
  it("con un par completo de pesos, pasa", () => {
    expect(errorsOf("yieldTest", test)).toEqual({});
    expect(
      errorsOf("yieldTest", {
        ...test,
        gross_weight: "",
        clean_weight: "",
        before_cooking_weight: "1000",
        after_cooking_weight: "2450",
      }),
    ).toEqual({});
  });

  it("pide el par completo y al menos uno", () => {
    expect(errorsOf("yieldTest", { ...test, clean_weight: "" })).toEqual({
      clean_weight: "Para la limpieza hacen falta los dos pesos: bruto y limpio.",
    });
    expect(errorsOf("yieldTest", { ...test, gross_weight: "", clean_weight: "" })).toEqual({
      gross_weight: "Cargá al menos un par de pesos.",
    });
  });

  it("la fecha del ensayo no puede ser futura", () => {
    expect(errorsOf("yieldTest", { ...test, tested_on: "2999-01-01" })).toEqual({
      tested_on: "La fecha del ensayo no puede ser futura.",
    });
  });

  it("el limpio no pesa más que el bruto", () => {
    expect(errorsOf("yieldTest", { ...test, clean_weight: "12000" })).toEqual({
      clean_weight: "El peso limpio no puede ser mayor que el bruto.",
    });
  });
});

describe("formulario de propuesta de estándar", () => {
  const proposal = {
    process_id: "00000000-0000-4000-8000-000000000961",
    cleaning_percent: "78,5",
    cooking_factor: "1",
    reason: "Promedio de ensayos",
  };

  it("la limpieza va de 0 a 100 % y la cocción hasta 10", () => {
    expect(errorsOf("yieldProposal", proposal)).toEqual({});
    expect(errorsOf("yieldProposal", { ...proposal, cleaning_percent: "120" })).toEqual({
      cleaning_percent: "La limpieza va de 0 a 100 %.",
    });
    expect(errorsOf("yieldProposal", { ...proposal, cooking_factor: "12" })).toEqual({
      cooking_factor: "El factor de cocción va hasta 10.",
    });
    expect(errorsOf("yieldProposal", { ...proposal, cooking_factor: "0" })).toEqual({
      cooking_factor: "Tiene que ser mayor que cero.",
    });
  });

  it("100 % y factor 1 exige marcar «no tiene merma», como la base", () => {
    const noLoss = { ...proposal, cleaning_percent: "100", cooking_factor: "1" };
    expect(errorsOf("yieldProposal", noLoss)).toEqual({
      declared_no_loss: "Con 100 % de limpieza y factor 1, marcá que no tiene merma.",
    });
    // Marcada en el navegador (true) o en el formulario enviado ("on").
    const parsed = schemas.yieldProposal.safeParse({ ...noLoss, declared_no_loss: true });
    expect(parsed.success).toBe(true);
    expect(errorsOf("yieldProposal", { ...noLoss, declared_no_loss: "on" })).toEqual({});
  });
});

describe("el aviso de rendimiento (ADR-0035)", () => {
  it("mide el desvío relativo contra el estándar", () => {
    // Limpieza de 68 % contra 80 %: 0,68 / 0,80 = 0,85.
    expect(yieldDeviationPct(0.68, 0.8)).toBeCloseTo(-15, 9);
    // Cocción: factor 3 contra 2,5 = 1,2.
    expect(yieldDeviationPct(3, 2.5)).toBeCloseTo(20, 9);
  });

  it("avisa solo si pasa el umbral, no si llega justo", () => {
    expect(exceedsYieldAlert(0.68, 0.8, 10)).toBe(true);
    expect(exceedsYieldAlert(0.76, 0.8, 10)).toBe(false);
    // 0,72 contra 0,80 es justo −10 %: con decimales de por medio, sigue sin avisar.
    expect(exceedsYieldAlert(0.72, 0.8, 10)).toBe(false);
    expect(exceedsYieldAlert(3, 2.5, 20)).toBe(false);
    expect(exceedsYieldAlert(3, 2.5, 19.99)).toBe(true);
  });

  it("el umbral se carga con coma o punto, de más de 0 a 100", () => {
    const ok = (v: string) =>
      schemas.yieldAlert.safeParse({ yield_alert_pct: v, reason: "Inflación del mes" }).success;
    expect(ok("10")).toBe(true);
    expect(ok("2,5")).toBe(true);
    expect(ok("0")).toBe(false);
    expect(ok("150")).toBe(false);
    expect(ok("diez")).toBe(false);
    expect(schemas.yieldAlert.safeParse({ yield_alert_pct: "10", reason: "" }).success).toBe(false);
  });
});
