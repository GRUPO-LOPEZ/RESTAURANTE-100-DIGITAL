// Fichas técnicas (ADR-0065): la línea de la versión, cuál se abre y qué foto representa a la receta.
import { describe, expect, it } from "vitest";

import {
  RECIPE_CARDS,
  afterSteps,
  mainPhoto,
  recipeCardHref,
  recipeCardKey,
  serviceAmount,
} from "@/lib/recipe-cards";
import { versionLine } from "@/lib/recipe-format";

describe("la versión, en todas las fichas y en lo impreso", () => {
  const v = { number: 2, code: "REC-PAS-012", publishedOn: "20/11/26", approvedBy: "Ana Pérez" };
  it("dice cuál es, cuándo se publicó y quién la aprobó", () => {
    expect(versionLine(v)).toBe(
      "Versión 2 · REC-PAS-012 · publicada el 20/11/26 · aprobó Ana Pérez",
    );
  });
  it("sin el nombre de quien aprobó, lo dice", () => {
    expect(versionLine({ ...v, approvedBy: null })).toBe(
      "Versión 2 · REC-PAS-012 · publicada el 20/11/26 · sin el nombre de quien aprobó",
    );
  });
});

describe("cuál ficha se abre", () => {
  it("las 4, por su nombre; cualquier otra cosa es la Completa", () => {
    for (const c of RECIPE_CARDS) expect(recipeCardKey(c.key)).toBe(c.key);
    for (const other of [undefined, "", "otra", "constructor"])
      expect(recipeCardKey(other)).toBe("completa");
  });
  it("la Completa no lleva parámetro", () => {
    expect(recipeCardHref("x", "completa")).toBe("/recetas/x/fichas");
    expect(recipeCardHref("x", "foto")).toBe("/recetas/x/fichas?ver=foto");
  });
});

describe("la foto de la receta", () => {
  it("el producto final, si no el emplatado, si no la primera", () => {
    const step = { kind: "step" as const };
    const plating = { kind: "plating" as const };
    const final = { kind: "final_product" as const };
    expect(mainPhoto([step, plating, final])).toBe(final);
    expect(mainPhoto([step, plating])).toBe(plating);
    expect(mainPhoto([step])).toBe(step);
    expect(mainPhoto([])).toBeNull();
  });
});

describe("qué va en grande en la ficha de Servicio", () => {
  const amount = "10 ml",
    equivalent = null;
  it("la medida práctica, si da entera", () => {
    expect(serviceAmount({ count: 2, measure: "2 cucharaditas", amount, equivalent })).toEqual({
      big: "2 cucharaditas",
      small: "10 ml",
    });
  });
  it("si no da entera, el gramaje, con la medida abajo (decisión de Joaco)", () => {
    expect(
      serviceAmount({ count: 0.42, measure: "0,42 taza", amount: "100 ml", equivalent }),
    ).toEqual({ big: "100 ml", small: "0,42 taza" });
    expect(
      serviceAmount({ count: 1.5, measure: "1,5 tazas", amount: "360 ml", equivalent }),
    ).toEqual({ big: "360 ml", small: "1,5 tazas" });
  });
  it("sin medida, la cantidad y su equivalente si lo tiene", () => {
    expect(
      serviceAmount({ count: null, measure: null, amount: "8 cda", equivalent: "120 ml" }),
    ).toEqual({ big: "8 cda", small: "120 ml" });
    expect(serviceAmount({ count: null, measure: null, amount, equivalent })).toEqual({
      big: "10 ml",
      small: null,
    });
  });
});

describe("después de qué paso", () => {
  it("en palabras", () => {
    expect(afterSteps([])).toBeNull();
    expect(afterSteps([1])).toBe("después del paso 1");
    expect(afterSteps([1, 2, 3])).toBe("después de los pasos 1, 2 y 3");
  });
});
