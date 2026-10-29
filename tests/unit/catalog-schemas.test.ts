// Formularios del catálogo (Fase 2, etapa 2.1 A): los mismos formatos que exige la base, para que
// la persona vea el error antes de enviar.
import { describe, expect, it } from "vitest";

import { cleanSearch } from "@/lib/catalog";
import { fieldErrors, schemas } from "@/lib/forms/schemas";

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

const ingredient = {
  code: "ing-0051",
  name: "Rúcula",
  category_id: "00000000-0000-4000-8000-000000000701",
  recipe_unit: "g",
  reason: "Alta",
};

describe("formularios del catálogo", () => {
  it("el código queda en mayúsculas y sigue el formato de la base", () => {
    const parsed = schemas.ingredient.safeParse(ingredient);
    expect(parsed.success && parsed.data.code).toBe("ING-0051");
    expect(errorsOf("ingredient", { ...ingredient, code: "x" })).toEqual({
      code: "Mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).",
    });
    expect(errorsOf("ingredient", { ...ingredient, code: "ING 51" })).toHaveProperty("code");
  });

  it("una materia prima se usa en recetas solo en g, ml o unidades", () => {
    expect(errorsOf("ingredient", ingredient)).toEqual({});
    expect(errorsOf("ingredient", { ...ingredient, recipe_unit: "kg" })).toEqual({
      recipe_unit: "Elegí en qué se usa: g, ml o unidad.",
    });
  });

  it("los números aceptan coma decimal y tienen que ser mayores que cero", () => {
    const conversion = {
      kind: "density",
      factor: "0,92",
      source: "measured",
      measured_on: "2026-10-01",
      reason: "Medición",
    };
    expect(errorsOf("conversion", conversion)).toEqual({});
    expect(errorsOf("conversion", { ...conversion, factor: "0.92" })).toEqual({});
    expect(errorsOf("conversion", { ...conversion, factor: "0" })).toEqual({
      factor: "Tiene que ser mayor que cero.",
    });
    expect(errorsOf("conversion", { ...conversion, factor: "uno" })).toEqual({
      factor: "Escribí un número, por ejemplo 0,92.",
    });
  });

  it("una conversión necesita fuente y fecha: nunca se supone", () => {
    expect(
      errorsOf("conversion", { kind: "density", factor: "0,92", source: "", reason: "x" }),
    ).toEqual({
      source: "Elegí de dónde sale el dato.",
      measured_on: "Elegí la fecha de la medición.",
    });
  });

  it("un producto de compra dice cuánto trae: unidades de 1 a 10.000 y contenido positivo", () => {
    const product = {
      code: "PROD-1",
      description: "Aceite de oliva, caja de 12 × 500 ml",
      package_unit: "box",
      units_per_package: "12",
      content_per_unit: "500",
      content_unit: "ml",
      reason: "Alta",
    };
    expect(errorsOf("product", product)).toEqual({});
    expect(errorsOf("product", { ...product, units_per_package: "0" })).toEqual({
      units_per_package: "De 1 a 10.000.",
    });
    expect(errorsOf("product", { ...product, content_per_unit: "" })).toHaveProperty(
      "content_per_unit",
    );
  });

  it("un alérgeno puede volver a «sin dato» (estado vacío)", () => {
    const allergen = {
      allergen_id: "00000000-0000-4000-8000-000000000951",
      status: "",
      reason: "Se corrige",
    };
    expect(errorsOf("allergen", allergen)).toEqual({});
    expect(errorsOf("allergen", { ...allergen, status: "sin_alergenos" })).toEqual({
      status: "Elegí el estado.",
    });
  });

  it("el CUIT del proveedor es opcional, solo con números y guiones", () => {
    const supplier = { code: "PROV-1", name: "Verdulería", reason: "Alta" };
    expect(errorsOf("supplier", supplier)).toEqual({});
    expect(errorsOf("supplier", { ...supplier, tax_id: "30-12345678-9" })).toEqual({});
    expect(errorsOf("supplier", { ...supplier, tax_id: "CUIT" })).toEqual({
      tax_id: "El CUIT va solo con números y guiones.",
    });
  });
});

describe("búsqueda de materias primas", () => {
  it("solo deja letras, números, espacios y guiones (arma un filtro de PostgREST)", () => {
    expect(cleanSearch("  Muzza  ")).toBe("Muzza");
    expect(cleanSearch("ñoquis,id.eq.1)")).toBe("ñoquisideq1");
    expect(cleanSearch("ING-001")).toBe("ING-001");
    expect(cleanSearch("(),%*")).toBeUndefined();
    expect(cleanSearch(undefined)).toBeUndefined();
    expect(cleanSearch("x".repeat(80))).toHaveLength(60);
  });
});
