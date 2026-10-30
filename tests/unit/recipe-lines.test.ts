// Líneas de una receta (ADR-0025): cada línea es una materia prima o una preparación (subreceta), y la
// preparación va siempre en cantidad terminada, como controla la base.
import { describe, expect, it } from "vitest";

import { recipeLinesSchema } from "@/lib/forms/schemas";

const ingredient = "00000000-0000-4000-8000-000000000801";
const preparation = "00000000-0000-4000-8000-000000001102";
const base = { ingredient: "x", quantity: "100", unit: "g", no_scale: false, notes: "" } as const;

function messages(line: Record<string, unknown>) {
  const parsed = recipeLinesSchema.safeParse([{ ...base, ...line }]);
  return parsed.success ? [] : parsed.error.issues.map((i) => i.message);
}

describe("líneas de una receta", () => {
  it("una materia prima con su base de cantidad pasa", () => {
    expect(messages({ ingredient_id: ingredient, sub_recipe_id: null, basis: "clean" })).toEqual(
      [],
    );
  });

  it("una preparación en cantidad terminada pasa", () => {
    expect(
      messages({ ingredient_id: null, sub_recipe_id: preparation, basis: "finished" }),
    ).toEqual([]);
  });

  it("no puede ser las dos cosas ni ninguna", () => {
    expect(
      messages({ ingredient_id: ingredient, sub_recipe_id: preparation, basis: "finished" }),
    ).toContain("Elegí una materia prima o una preparación.");
    expect(messages({ ingredient_id: null, sub_recipe_id: null, basis: "purchase" })).toContain(
      "Elegí una materia prima o una preparación.",
    );
  });

  it("la cantidad terminada es solo para preparaciones", () => {
    const wrong = "Una preparación va en cantidad terminada; una materia prima, no.";
    expect(messages({ ingredient_id: ingredient, sub_recipe_id: null, basis: "finished" })).toEqual(
      [wrong],
    );
    expect(
      messages({ ingredient_id: null, sub_recipe_id: preparation, basis: "purchase" }),
    ).toEqual([wrong]);
  });
});
