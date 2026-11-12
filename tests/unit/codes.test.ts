// Códigos automáticos (ADR-0041): lo que muestra el alta mientras se completa, el aviso cuando salió otro código,
// las pestañas Platos | Preparaciones y la nota de la unidad base. El código lo arma la base (pgTAP 280).
import { describe, expect, it } from "vitest";

import {
  RECIPE_LIST_TABS,
  baseUnitNote,
  codeChangedNotice,
  codePreviewText,
  recipeListTab,
} from "@/lib/codes";
import { fieldErrors, schemas } from "@/lib/forms/schemas";
import { NEW_RECIPE_TYPES, RECIPE_TYPE_LABELS } from "@/lib/recipe-format";

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

describe("vista previa del código", () => {
  it("sin tipo o sin rubro todavía no hay código", () => {
    expect(codePreviewText({ ready: false, loading: false, code: null })).toBe(
      "Se arma al elegir el rubro",
    );
  });
  it("mientras la base responde, lo dice", () => {
    expect(codePreviewText({ ready: true, loading: true, code: null })).toBe("Calculando…");
  });
  it("muestra el código que va a salir", () => {
    expect(codePreviewText({ ready: true, loading: false, code: "PLA-CAF-0001" })).toBe(
      "PLA-CAF-0001",
    );
  });
  it("si la base no da código (sin permiso o rubro sin código), no inventa uno", () => {
    expect(codePreviewText({ ready: true, loading: false, code: null })).toBe(
      "Sin código para ese rubro",
    );
  });
});

describe("aviso cuando salió otro código", () => {
  it("sin aviso si coincide con la vista previa (sin importar espacios o minúsculas)", () => {
    expect(codeChangedNotice("PLA-CAF-0001", "PLA-CAF-0001")).toBeNull();
    expect(codeChangedNotice(" pla-caf-0001 ", "PLA-CAF-0001")).toBeNull();
  });
  it("sin aviso si no hubo vista previa", () => {
    expect(codeChangedNotice(undefined, "PLA-CAF-0001")).toBeNull();
    expect(codeChangedNotice("", "PLA-CAF-0001")).toBeNull();
  });
  it("con aviso si otra alta tomó el número en el medio", () => {
    expect(codeChangedNotice("PLA-CAF-0001", "PLA-CAF-0002")).toBe(
      "Se creó con el código PLA-CAF-0002: el PLA-CAF-0001 lo tomó otra alta mientras cargabas.",
    );
  });
});

describe("tipos de receta (pedido de Soy)", () => {
  it("al crear solo se ofrecen Plato y Preparación, en ese orden", () => {
    expect(NEW_RECIPE_TYPES.map((t) => RECIPE_TYPE_LABELS[t])).toEqual(["Plato", "Preparación"]);
  });
  it("un componente por unidad que ya existía se muestra como Preparación", () => {
    expect(RECIPE_TYPE_LABELS.unit_component).toBe("Preparación");
  });
  it("las pestañas del listado: Platos (rubros de menú) y Preparaciones (sub-recetas, con los componentes)", () => {
    expect(RECIPE_LIST_TABS.map((t) => [t.label, t.rubroClass, [...t.types]])).toEqual([
      ["Platos", "menu", ["dish"]],
      ["Preparaciones", "subrecipe", ["preparation", "unit_component"]],
    ]);
    expect(recipeListTab(undefined).value).toBe("platos");
    expect(recipeListTab("cualquiera").value).toBe("platos");
    expect(recipeListTab("preparaciones").value).toBe("preparaciones");
  });
});

describe("formulario de alta de receta", () => {
  const recipe = {
    scope: "group:00000000-0000-4000-8000-000000000001",
    type: "dish",
    category_id: "00000000-0000-4000-8000-000000001062",
    expected_code: "PLA-PAS-0001",
    name: "Ñoquis",
    reason: "Alta",
  };
  it("con tipo, rubro, nombre y motivo está completo", () => {
    expect(errorsOf("recipe", recipe)).toEqual({});
  });
  it("el rubro es obligatorio: de él sale el código", () => {
    expect(errorsOf("recipe", { ...recipe, category_id: "" })).toEqual({
      category_id: "Elegí el rubro.",
    });
  });
  it("componente por unidad ya no se crea", () => {
    expect(errorsOf("recipe", { ...recipe, type: "unit_component" })).toEqual({
      type: "Elegí el tipo: plato o preparación.",
    });
  });
  it("el código no se escribe: un código a mano no viaja", () => {
    const parsed = schemas.recipe.safeParse({ ...recipe, code: "REC-0001" });
    expect(parsed.success && "code" in parsed.data).toBe(false);
  });
});

describe("unidad base de una materia prima", () => {
  it("dice en qué la calculan las recetas", () => {
    expect(baseUnitNote("mass")).toBe("Las recetas la calculan en gramos (g).");
    expect(baseUnitNote("volume")).toBe("Las recetas la calculan en mililitros (ml).");
    expect(baseUnitNote("count")).toBe("Las recetas la calculan en unidades.");
  });
  it("sin unidad elegida, o con un envase, no dice nada", () => {
    expect(baseUnitNote(null)).toBeNull();
    expect(baseUnitNote("package")).toBeNull();
  });
});
