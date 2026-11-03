// Formularios de precios (ADR-0029): los mismos controles que costing.propose_price y
// costing.update_price_settings, para que la persona vea el error antes de enviar.
import { describe, expect, it } from "vitest";

import { fieldErrors, schemas } from "@/lib/forms/schemas";
import {
  currentByProductAndPlace,
  formatMoney,
  perBaseLabel,
  type PriceRecordRow,
} from "@/lib/prices";

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

const proposal = {
  product_id: "00000000-0000-4000-8000-000000000001",
  place: "group:00000000-0000-4000-8000-000000000001",
  valid_from: "2026-11-03",
  package_price: "12100,50",
  document_type: "invoice",
  vat_rate: "21",
  source: "test_value",
  reason: "Precio nuevo",
};

describe("proponer un precio", () => {
  it("acepta un precio con coma decimal", () => {
    expect(schemas.priceProposal.safeParse(proposal).success).toBe(true);
  });

  it("con factura, la alícuota es obligatoria; sin factura, no se pide", () => {
    expect(errorsOf("priceProposal", { ...proposal, vat_rate: "" })).toEqual({
      vat_rate: "Elegí la alícuota de IVA.",
    });
    expect(
      schemas.priceProposal.safeParse({ ...proposal, document_type: "no_invoice", vat_rate: "" })
        .success,
    ).toBe(true);
  });

  it("el precio es mayor que cero y el descuento, menor que el precio", () => {
    expect(errorsOf("priceProposal", { ...proposal, package_price: "0" })).toEqual({
      package_price: "Tiene que ser mayor que cero.",
    });
    expect(errorsOf("priceProposal", { ...proposal, discount_amount: "12100,50" })).toEqual({
      discount_amount: "El descuento tiene que ser menor que el precio.",
    });
  });

  it("la fecha tiene que existir y el origen es manual o de prueba", () => {
    expect(errorsOf("priceProposal", { ...proposal, valid_from: "2026-02-30" })).toEqual({
      valid_from: "Esa fecha no existe.",
    });
    expect(errorsOf("priceProposal", { ...proposal, source: "invoice" })).toEqual({
      source: "Elegí el origen.",
    });
  });
});

describe("configuración de precios", () => {
  const settings = {
    approval_variation_pct: "15",
    stale_days: "30",
    lookback_days: "30",
    reason: "Ajuste",
  };
  it("el % va de más de 0 a 100 y los días de 1 a 365", () => {
    expect(schemas.priceSettings.safeParse(settings).success).toBe(true);
    expect(errorsOf("priceSettings", { ...settings, approval_variation_pct: "0" })).toEqual({
      approval_variation_pct: "De más de 0 a 100.",
    });
    expect(errorsOf("priceSettings", { ...settings, lookback_days: "400" })).toEqual({
      lookback_days: "De 1 a 365 días.",
    });
  });
});

describe("cómo se muestran los precios", () => {
  it("el costo por gramo se muestra por kilo y en pesos", () => {
    expect(perBaseLabel("g")).toEqual({ factor: 1000, label: "por kg" });
    expect(perBaseLabel("unit")).toEqual({ factor: 1, label: "por unidad" });
    expect(formatMoney(1234.5)).toMatch(/1\.234,50/);
  });

  it("de cada producto y lugar queda el vigente, sin los de fecha futura", () => {
    const row = (id: string, validFrom: string, place = "Todo el grupo"): PriceRecordRow => ({
      id,
      productId: "p",
      product: "Producto",
      scope: "group",
      place,
      validFrom,
      packagePrice: 1,
      netPackagePrice: 1,
      grossPackagePrice: 1,
      document: "no_invoice",
      vatRate: null,
      source: "test_value",
    });
    const rows = [
      row("futuro", "2999-01-01"),
      row("nuevo", "2026-10-01"),
      row("viejo", "2026-01-01"),
      row("marca", "2026-01-01", "Marca X"),
    ];
    expect(currentByProductAndPlace(rows).map((r) => r.id)).toEqual(["nuevo", "marca"]);
  });
});
