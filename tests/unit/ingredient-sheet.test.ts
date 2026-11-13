// Ficha única de materia prima (ADR-0043): qué cambió contra lo guardado, el contador y lo que viaja a la base.
import { describe, expect, it } from "vitest";

import { ingredientSheetSchema } from "@/lib/forms/schemas";
import {
  countSheetChanges,
  normalizeAliases,
  priceState,
  sheetChanges,
  sheetPayload,
  splitAliases,
  type IngredientSheetDraft,
} from "@/lib/ingredient-sheet";

const ID = "00000000-0000-4000-8000-000000000828";
const ALLERGEN = "00000000-0000-4000-8000-000000000951";

const saved: IngredientSheetDraft = {
  data: {
    name: "Harina 0000",
    category_id: "00000000-0000-4000-8000-000000000701",
    recipe_unit: "g",
    purchase_unit: "",
    notes: "",
  },
  aliases: ["harina fina"],
  requiresThawing: false,
  conversions: {
    density: { factor: "0,55", source: "measured", measured_on: "2026-11-10", measured_by: "" },
    unit_weight: null,
  },
  allergens: { [ALLERGEN]: { status: "contains", source: "supplier" } },
};

const edit = (patch: Partial<IngredientSheetDraft>): IngredientSheetDraft => ({
  ...saved,
  ...patch,
});

describe("cambios de la ficha", () => {
  it("sin tocar nada no hay cambios", () => {
    expect(countSheetChanges(sheetChanges(saved, saved))).toBe(0);
  });

  it("cada campo, conversión y alérgeno cuenta uno", () => {
    const draft = edit({
      data: { ...saved.data, name: "Harina 0000 Pureza", notes: "Tacho hermético" },
      requiresThawing: true,
      conversions: {
        density: saved.conversions.density,
        unit_weight: {
          factor: "90",
          source: "measured",
          measured_on: "2026-11-12",
          measured_by: "",
        },
      },
      allergens: { [ALLERGEN]: { status: "may_contain", source: "supplier" } },
    });
    const c = sheetChanges(saved, draft);
    expect(c.data).toEqual(["name", "notes"]);
    expect(c.thawing).toBe(true);
    expect(c.conversions).toEqual(["unit_weight"]);
    expect(c.allergens).toEqual([ALLERGEN]);
    expect(countSheetChanges(c)).toBe(5);
  });

  it("los otros nombres se comparan como los guarda la base: minúsculas, sin repetir ni espacios", () => {
    expect(countSheetChanges(sheetChanges(saved, edit({ aliases: [" Harina Fina "] })))).toBe(0);
    expect(normalizeAliases(["B", "a", " a "])).toEqual(["a", "b"]);
    expect(splitAliases("cuatro ceros, harina\n fina ")).toEqual([
      "cuatro ceros",
      "harina",
      "fina",
    ]);
  });

  it("volver al valor guardado deja de contar", () => {
    const draft = edit({ data: { ...saved.data, name: "Otra" } });
    expect(countSheetChanges(sheetChanges(saved, draft))).toBe(1);
    const back = edit({ data: { ...draft.data, name: "Harina 0000" } });
    expect(countSheetChanges(sheetChanges(saved, back))).toBe(0);
  });

  it("un alérgeno sin dato no cuenta su fuente", () => {
    const none = edit({ allergens: {} });
    const noneWithSource = edit({ allergens: { [ALLERGEN]: { status: "", source: "supplier" } } });
    expect(countSheetChanges(sheetChanges(none, noneWithSource))).toBe(0);
  });
});

describe("lo que viaja a la base", () => {
  it("solo los bloques que cambiaron; los demás van vacíos y la base no los toca", () => {
    const p = sheetPayload(saved, edit({ data: { ...saved.data, name: "Harina 0000 Pureza" } }));
    expect(p).toEqual({
      data: { name: "Harina 0000 Pureza" },
      aliases: null,
      requiresThawing: null,
      conversions: null,
      allergens: null,
    });
  });

  it("una conversión quitada viaja como quitada; un alérgeno sin dato, sin fuente", () => {
    const p = sheetPayload(
      saved,
      edit({
        conversions: { density: null, unit_weight: null },
        allergens: { [ALLERGEN]: { status: "", source: "supplier" } },
      }),
    );
    expect(p.conversions).toEqual([{ removed: true, kind: "density" }]);
    expect(p.allergens).toEqual([{ allergen_id: ALLERGEN, status: null, source: null }]);
  });

  it("el esquema pide el motivo y la fuente de un alérgeno o de una conversión", () => {
    const base = { ingredientId: ID, expectedStamp: "2026-11-12T10:00:00+00:00", reason: "Prueba" };
    const ok = ingredientSheetSchema.safeParse({
      ...base,
      ...sheetPayload(saved, edit({ requiresThawing: true })),
    });
    expect(ok.success).toBe(true);
    expect(
      ingredientSheetSchema.safeParse({ ...base, reason: " ", ...sheetPayload(saved, saved) })
        .success,
    ).toBe(false);
    const noSource = ingredientSheetSchema.safeParse({
      ...base,
      ...sheetPayload(
        saved,
        edit({ allergens: { [ALLERGEN]: { status: "contains", source: "" } } }),
      ),
    });
    expect(noSource.success).toBe(false);
    const noConversionSource = ingredientSheetSchema.safeParse({
      ...base,
      ...sheetPayload(
        saved,
        edit({
          conversions: {
            density: saved.conversions.density,
            unit_weight: { factor: "90", source: "", measured_on: "2026-11-12", measured_by: "" },
          },
        }),
      ),
    });
    expect(noConversionSource.success).toBe(false);
    expect(noConversionSource.error?.issues[0]?.message).toBe("Elegí de dónde sale la conversión.");
  });

  it("un valor de conversión que no es un número no pasa", () => {
    const r = ingredientSheetSchema.safeParse({
      ingredientId: ID,
      expectedStamp: "x",
      reason: "Prueba",
      ...sheetPayload(
        saved,
        edit({
          conversions: {
            density: { ...saved.conversions.density!, factor: "medio" },
            unit_weight: null,
          },
        }),
      ),
    });
    expect(r.success).toBe(false);
  });
});

describe("estado del precio de un producto", () => {
  const base = { status: "ok", stale: false, daysOld: 3, inherited: false };
  it("siempre con una palabra, nunca solo color", () => {
    expect(priceState(base)).toEqual({ status: "ok", label: "Vigente" });
    expect(priceState({ ...base, inherited: true })).toEqual({ status: "info", label: "Heredado" });
    expect(priceState({ ...base, stale: true, daysOld: 22 })).toEqual({
      status: "warn",
      label: "Atención: 22 días",
    });
    expect(priceState({ ...base, status: "missing_price", stale: null, daysOld: null })).toEqual({
      status: "none",
      label: "Sin precio",
    });
    expect(priceState({ ...base, status: "missing_legal_entity" }).status).toBe("warn");
  });
});
