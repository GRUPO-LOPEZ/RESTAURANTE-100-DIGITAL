// Facturas (Fase 3, Prompt 5, ADR-0058): la cabecera, los totales y cómo se lee una factura.
import { describe, expect, it } from "vitest";

import {
  invoiceHeaderSchema,
  invoiceLabel,
  isClassA,
  isFiscal,
  totalsClose,
  totalsDifference,
  type InvoiceHeaderInput,
} from "@/lib/invoices";

const base: InvoiceHeaderInput = {
  invoice_class: "invoice_a",
  point_of_sale: 3,
  number: 12345,
  authorization_kind: "cae",
  authorization_code: "71000000000001",
  issuer_tax_id: "30-50000003-8",
  receiver_tax_id: "30000000001",
  issued_on: "2026-11-17",
  due_on: null,
  net_amount: 50000,
  exempt_amount: 0,
  vat_amount: 10500,
  internal_tax_amount: 0,
  perception_amount: 0,
  discount_amount: 0,
  rounding_amount: 0,
  total_amount: 60500,
};

function errors(input: InvoiceHeaderInput): string[] {
  const r = invoiceHeaderSchema.safeParse(input);
  return r.success ? [] : r.error.issues.map((i) => i.message);
}

describe("cabecera de la factura", () => {
  it("una A completa pasa", () => {
    expect(errors(base)).toEqual([]);
  });
  it("una A sin CAE no pasa (caso 29)", () => {
    expect(errors({ ...base, authorization_code: null })).toContain(
      "Una factura fiscal lleva autorización (CAE, CAI o CAEA).",
    );
  });
  it("el CAE tiene 14 números", () => {
    expect(errors({ ...base, authorization_code: "123" })).toContain(
      "La autorización tiene 14 números.",
    );
  });
  it("el emisor de ejemplo se frena (caso 29)", () => {
    expect(errors({ ...base, issuer_tax_id: "99-99999999-9" })).toContain(
      "El CUIT del emisor es de ejemplo (99-99999999-9): esa factura no vale.",
    );
  });
  it("un CUIT con el dígito verificador mal no pasa", () => {
    expect(errors({ ...base, issuer_tax_id: "30-50000003-9" })).toContain(
      "El CUIT del emisor no es válido.",
    );
  });
  it("el punto de venta va de 1 a 99999 y el número hasta 99999999", () => {
    expect(errors({ ...base, point_of_sale: 100000 })).toContain(
      "El punto de venta va de 1 a 99999.",
    );
    expect(errors({ ...base, number: 100000000 })).toContain("El número va de 1 a 99999999.");
  });
  it("totales que no cierran por $ 0,02 no pasan (caso 30)", () => {
    expect(errors({ ...base, total_amount: 60500.02 })).toContain("Las partes no suman el total.");
  });
  it("un comprobante X no lleva punto de venta ni CAE, pero tampoco IVA", () => {
    const x: InvoiceHeaderInput = {
      ...base,
      invoice_class: "non_fiscal",
      point_of_sale: null,
      authorization_kind: null,
      authorization_code: null,
      issuer_tax_id: null,
    };
    expect(errors(x)).toEqual(["Un comprobante X o una nota a mano no llevan IVA."]);
    expect(errors({ ...x, net_amount: 60500, vat_amount: 0 })).toEqual([]);
  });
  it("el vencimiento no va antes de la fecha", () => {
    expect(errors({ ...base, due_on: "2026-11-16" })).toContain(
      "El vencimiento no puede ser anterior a la fecha de la factura.",
    );
  });
});

describe("totales", () => {
  it("las partes suman el total con 0,01 de tolerancia", () => {
    expect(totalsClose(base)).toBe(true);
    expect(totalsClose({ ...base, total_amount: 60500.01 })).toBe(true);
    expect(totalsDifference({ ...base, total_amount: 60500.02 })).toBe(-0.02);
  });
  it("percepciones e internos suman; la bonificación general resta", () => {
    expect(
      totalsClose({
        ...base,
        internal_tax_amount: 2000,
        perception_amount: 1500,
        discount_amount: 500,
        total_amount: 63500,
      }),
    ).toBe(true);
  });
});

describe("cómo se lee una factura", () => {
  it("clase, punto de venta y número", () => {
    expect(invoiceLabel("invoice_a", 3, 12345)).toBe("Factura A 0003-00012345");
    expect(invoiceLabel("non_fiscal", null, 15)).toBe("Comprobante X 00000015");
  });
  it("qué clases son fiscales y cuáles discriminan IVA", () => {
    expect(isFiscal("invoice_b")).toBe(true);
    expect(isFiscal("handwritten_note")).toBe(false);
    expect(isClassA("invoice_remito_a")).toBe(true);
    expect(isClassA("invoice_b")).toBe(false);
  });
});
