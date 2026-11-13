// Editar un producto de compra (ADR-0044): solo viaja lo que cambió, y el esquema acepta el envase deshabilitado.
import { describe, expect, it } from "vitest";

import { schemas } from "@/lib/forms/schemas";
import { productChanges, type ProductFormValues } from "@/lib/purchase-product";

const original: ProductFormValues = {
  description: "Tomate perita, cajón de 10 kg",
  brand_name: "",
  supplier_id: "",
  notes: "",
  is_active: "true",
  package_unit: "box",
  units_per_package: "1",
  content_per_unit: "10",
  content_unit: "kg",
};

describe("productChanges", () => {
  it("sin cambios no manda nada", () => {
    expect(productChanges(original, { ...original })).toEqual({});
  });

  it("manda solo lo que cambió, con su tipo", () => {
    expect(
      productChanges(original, {
        ...original,
        description: "  Tomate perita, cajón  ",
        is_active: "false",
        units_per_package: "2",
      }),
    ).toEqual({ description: "Tomate perita, cajón", is_active: false, units_per_package: 2 });
  });

  it("vaciar la marca o el proveedor es un cambio (la base lo guarda vacío)", () => {
    const withBrand = { ...original, brand_name: "La Huerta", supplier_id: "x" };
    expect(productChanges(withBrand, { ...withBrand, brand_name: "", supplier_id: "" })).toEqual({
      brand_name: "",
      supplier_id: "",
    });
  });

  it("«10», «10,0» y «10.000» con coma son el mismo contenido; «10,5» es otro", () => {
    expect(productChanges(original, { ...original, content_per_unit: "10,0" })).toEqual({});
    expect(productChanges(original, { ...original, content_per_unit: "10,5" })).toEqual({
      content_per_unit: 10.5,
    });
  });

  it("el envase deshabilitado (producto con precios) no llega y no cuenta como cambio", () => {
    const submitted: Partial<ProductFormValues> = {
      description: original.description,
      brand_name: "Nueva",
      supplier_id: "",
      notes: "",
      is_active: "true",
    };
    expect(productChanges(original, submitted)).toEqual({ brand_name: "Nueva" });
  });
});

describe("schemas.productEdit", () => {
  const base = { description: "Tomate", is_active: "true", reason: "Corrijo" };

  it("acepta un producto con el envase deshabilitado (sin esos campos)", () => {
    expect(schemas.productEdit.safeParse(base).success).toBe(true);
  });

  it("pide la descripción y el motivo", () => {
    const result = schemas.productEdit.safeParse({ ...base, description: " ", reason: "" });
    expect(result.success).toBe(false);
  });

  it("si llega el contenido, se valida como en el alta", () => {
    expect(schemas.productEdit.safeParse({ ...base, content_per_unit: "0" }).success).toBe(false);
    expect(schemas.productEdit.safeParse({ ...base, units_per_package: "0" }).success).toBe(false);
    expect(
      schemas.productEdit.safeParse({ ...base, content_per_unit: "2,5", units_per_package: "12" })
        .success,
    ).toBe(true);
  });
});
