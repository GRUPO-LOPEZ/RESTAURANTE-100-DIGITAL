// Formularios del panel de control de la estructura (ADR-0031): los mismos formatos que exige la base,
// para que la persona vea el error antes de enviar.
import { describe, expect, it } from "vitest";

import { formatTaxId } from "@/lib/org";
import { fieldErrors, schemas } from "@/lib/forms/schemas";

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

const entity = {
  name: "Demo S.R.L.",
  tax_id: "30-12345678-9",
  vat_condition: "registered",
  reason: "Alta",
};

describe("formularios de la estructura", () => {
  it("el CUIT se escribe con o sin guiones y queda con 11 números", () => {
    const parsed = schemas.legalEntity.safeParse(entity);
    expect(parsed.success && parsed.data.tax_id).toBe("30123456789");
    expect(schemas.legalEntity.safeParse({ ...entity, tax_id: "30123456789" }).success).toBe(true);
    expect(errorsOf("legalEntity", { ...entity, tax_id: "30-1234-9" })).toEqual({
      tax_id: "El CUIT tiene 11 números (con o sin guiones).",
    });
    expect(errorsOf("legalEntity", { ...entity, vat_condition: "otra" })).toEqual({
      vat_condition: "Elegí la condición frente al IVA.",
    });
  });

  it("muestra el CUIT con sus guiones", () => {
    expect(formatTaxId("30123456789")).toBe("30-12345678-9");
  });

  it("el código de una marca queda en mayúsculas y sigue el formato de la base", () => {
    const parsed = schemas.brand.safeParse({ name: "Casa Nonnos", code: "nonnos", reason: "Alta" });
    expect(parsed.success && parsed.data.code).toBe("NONNOS");
    expect(errorsOf("brand", { name: "Casa Nonnos", code: "N", reason: "Alta" })).toHaveProperty(
      "code",
    );
    expect(errorsOf("brand", { name: "", code: "NONNOS", reason: "Alta" })).toEqual({
      name: "Escribí el nombre.",
    });
  });

  it("el local: código, teléfono y fecha opcionales, con el formato de la base", () => {
    const base = { name: "Nonnos Palermo", reason: "Alta" };
    expect(
      schemas.restaurant.safeParse({ ...base, code: "", phone: "", opened_on: "" }).success,
    ).toBe(true);
    const parsed = schemas.restaurant.safeParse({
      ...base,
      code: "non-palermo",
      site_type: "restaurant",
    });
    expect(parsed.success && parsed.data.code).toBe("NON-PALERMO");
    expect(errorsOf("restaurant", { ...base, phone: "llamar" })).toEqual({
      phone: "Solo números, espacios, +, guiones y paréntesis.",
    });
    expect(errorsOf("restaurant", { ...base, site_type: "bar" })).toEqual({
      site_type: "Elegí el tipo.",
    });
  });

  it("una fecha de apertura que no existe se rechaza", () => {
    const base = { name: "Nonnos Palermo", reason: "Alta" };
    expect(errorsOf("restaurant", { ...base, opened_on: "2026-02-31" })).toEqual({
      opened_on: "Esa fecha no existe.",
    });
    expect(schemas.restaurant.safeParse({ ...base, opened_on: "2026-02-28" }).success).toBe(true);
  });

  it("el motivo es obligatorio", () => {
    expect(errorsOf("area", { name: "Salón", reason: "" })).toEqual({
      reason: "Escribí el motivo.",
    });
  });
});
