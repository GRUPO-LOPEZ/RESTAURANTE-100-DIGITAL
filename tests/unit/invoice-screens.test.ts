// Facturas, pantallas (Fase 3, Prompt 5B, ADR-0058): los números escritos, el borrador de la ficha y lo que se manda a
// la base, el alta, las notas, la diferencia contra la lista y el vencimiento.
import { describe, expect, it } from "vitest";

import {
  countInvoiceChanges,
  dueState,
  failedLabel,
  headerAmounts,
  invoiceChanges,
  invoicePayload,
  lineAmount,
  linesNet,
  newInvoiceSchema,
  noteSchema,
  numberText,
  priceDifference,
  readNumber,
  shortDate,
  type CheckRow,
  type InvoiceDraft,
  type LineDraft,
} from "@/lib/invoices";

const line = (patch: Partial<LineDraft> = {}): LineDraft => ({
  key: "l1",
  id: "l1",
  line_class: "product",
  purchase_product_id: "p1",
  purchase_order_line_id: "pol1",
  product: "Tomate perita, cajón de 10 kg",
  raw_name: "Tomate perita, cajón de 10 kg",
  supplier_sku: "",
  units: "",
  billed_quantity: "2",
  list_price: 937,
  bonus1_pct: 0,
  bonus2_pct: 0,
  bonus_per_unit_amount: 0,
  unit_price: "937",
  vat_rate: "10.5",
  is_exempt: false,
  internal_tax_amount: "0",
  by_weight: false,
  ...patch,
});

const saved: InvoiceDraft = {
  header: {
    invoice_class: "invoice_a",
    point_of_sale: "1",
    number: "2001",
    authorization_kind: "cae",
    authorization_code: "75000000000004",
    issuer_tax_id: "30500000011",
    receiver_tax_id: "",
    issued_on: "2026-11-17",
    due_on: "",
    net_amount: "1874",
    exempt_amount: "0",
    vat_amount: "196,77",
    internal_tax_amount: "0",
    perception_amount: "0",
    discount_amount: "0",
    rounding_amount: "0",
    total_amount: "2070,77",
  },
  lines: [line()],
  taxes: [],
};

describe("los números que se escriben en la ficha", () => {
  it("se leen como acá: punto de miles, coma decimal", () => {
    expect(readNumber("1.500")).toBe(1500);
    expect(readNumber("60.500,50")).toBe(60500.5);
    expect(readNumber("2,5")).toBe(2.5);
    expect(readNumber("2.5")).toBe(2.5);
    expect(readNumber("")).toBeNull();
    expect(readNumber("dos")).toBeNull();
  });

  it("el signo menos solo donde se admite (el redondeo)", () => {
    expect(readNumber("-0,5")).toBeNull();
    expect(readNumber("-0,5", true)).toBe(-0.5);
  });

  it("se escriben sin separador de miles, y se vuelven a leer igual", () => {
    expect(numberText(1874.5)).toBe("1874,5");
    expect(readNumber(numberText(196.77))).toBe(196.77);
    expect(numberText(null)).toBe("");
  });

  it("el importe de una línea es cantidad × precio, a centavos", () => {
    expect(lineAmount(32.8, 7650)).toBe(250920);
    expect(lineAmount(3, 1074.333)).toBe(3223);
    expect(lineAmount(null, 1)).toBeNull();
    expect(linesNet([line(), line({ key: "l2", billed_quantity: "3", unit_price: "1074" })])).toBe(
      5096,
    );
  });

  it("la cuenta del pie no se arma si un importe no se entiende", () => {
    expect(headerAmounts(saved.header)?.total_amount).toBe(2070.77);
    expect(headerAmounts({ ...saved.header, vat_amount: "mucho" })).toBeNull();
  });
});

describe("el borrador de la ficha", () => {
  it("cuenta cada dato, línea y percepción que cambió", () => {
    const draft: InvoiceDraft = {
      ...saved,
      header: { ...saved.header, net_amount: "1880", total_amount: "2077,4" },
      lines: [line({ unit_price: "940" }), line({ key: "nueva", id: null, line_class: "freight" })],
      taxes: [
        { key: "t", tax_kind: "iibb", jurisdiction: "CABA", rate_pct: "3", tax_amount: "56" },
      ],
    };
    const c = invoiceChanges(saved, draft);
    expect(c.header).toEqual(["net_amount", "total_amount"]);
    expect(c.lines).toEqual(["l1", "nueva"]);
    expect(countInvoiceChanges(c)).toBe(5);
  });

  it("quitar una línea también es un cambio", () => {
    const c = invoiceChanges(saved, { ...saved, lines: [] });
    expect(c.removedLines).toBe(1);
    expect(countInvoiceChanges(c)).toBe(1);
  });

  it("sin cambios en las líneas ni en las percepciones, esas listas no se mandan (la base las deja)", () => {
    const built = invoicePayload(saved, {
      ...saved,
      header: { ...saved.header, receiver_tax_id: "30-00000000-1" },
    });
    expect(built.ok).toBe(true);
    if (!built.ok) return;
    expect(built.payload.lines).toBeNull();
    expect(built.payload.taxes).toBeNull();
    expect(built.payload.header).toMatchObject({
      invoice_class: "invoice_a",
      point_of_sale: 1,
      number: 2001,
      vat_amount: 196.77,
      total_amount: 2070.77,
      due_on: null,
    });
  });

  it("con una línea cambiada se mandan todas, con su importe", () => {
    const built = invoicePayload(saved, { ...saved, lines: [line({ unit_price: "940" })] });
    expect(built.ok && built.payload.lines).toEqual([
      expect.objectContaining({ unit_price: 940, line_amount: 1880, vat_rate: 10.5 }),
    ]);
  });

  it("un comprobante X no lleva punto de venta ni autorización", () => {
    const built = invoicePayload(saved, {
      ...saved,
      header: { ...saved.header, invoice_class: "non_fiscal" },
    });
    expect(built.ok && built.payload.header).toMatchObject({
      point_of_sale: null,
      authorization_kind: null,
      authorization_code: null,
    });
  });

  it("dice qué dato no se entiende, en simple", () => {
    expect(
      invoicePayload(saved, { ...saved, header: { ...saved.header, vat_amount: "x" } }),
    ).toEqual({ ok: false, message: "IVA: escribí un número." });
    expect(invoicePayload(saved, { ...saved, lines: [line({ billed_quantity: "0" })] })).toEqual({
      ok: false,
      message: "Línea 1: la cantidad tiene que ser mayor que cero.",
    });
    expect(
      invoicePayload(saved, {
        ...saved,
        taxes: [{ key: "t", tax_kind: "iibb", jurisdiction: "", rate_pct: "", tax_amount: "" }],
      }),
    ).toEqual({ ok: false, message: "Cada percepción lleva su importe, mayor que cero." });
  });
});

describe("el control, para la pantalla", () => {
  const checks: CheckRow[] = [
    { kind: "price", lineId: "l1", passed: false, explanation: "", expected: 937, actual: 940 },
    { kind: "price", lineId: "l2", passed: true, explanation: "", expected: 1074, actual: 1074 },
    { kind: "totals", lineId: null, passed: true, explanation: "", expected: 1, actual: 1 },
  ];

  it("la diferencia contra la lista, en pesos, por lo facturado de más", () => {
    const quantities = new Map([
      ["l1", 2],
      ["l2", 3],
      ["l3", 1],
    ]);
    expect(priceDifference(checks, quantities)).toEqual({ value: 6, withoutList: 0 });
    expect(priceDifference(checks.slice(1), quantities)).toEqual({ value: 0, withoutList: 0 });
    // Lo cobrado de menos no compensa lo de más (la misma regla que el control).
    const cheaper: CheckRow = {
      kind: "price",
      lineId: "l3",
      passed: false,
      explanation: "",
      expected: 100,
      actual: 90,
    };
    expect(priceDifference([...checks, cheaper], quantities).value).toBe(6);
    // Sin precios comparados (sin lista o sin controlar) no hay diferencia que mostrar.
    expect(priceDifference(checks.slice(2), new Map()).value).toBeNull();
  });

  it("una línea sin lista no deja decir «igual a la lista»", () => {
    const noList: CheckRow = {
      kind: "price",
      lineId: "l3",
      passed: false,
      explanation: "Sin lista de precios vigente.",
      expected: null,
      actual: null,
    };
    expect(priceDifference([checks[1]!, noList], new Map([["l2", 3]]))).toEqual({
      value: 0,
      withoutList: 1,
    });
  });

  it("lo que no pasó, en palabras", () => {
    expect(failedLabel(["notes", "price"])).toBe(
      "Notas de crédito y débito · Precio contra la lista",
    );
    expect(failedLabel([])).toBe("—");
  });

  it("el vencimiento: vencida, por vencer en 7 días, al día; pagada no aplica", () => {
    expect(dueState("2026-11-17", "2026-11-18", "released")).toBe("bad");
    expect(dueState("2026-11-25", "2026-11-18", "released")).toBe("warn");
    expect(dueState("2026-12-18", "2026-11-18", "loaded")).toBe("ok");
    expect(dueState("2026-11-01", "2026-11-18", "paid")).toBe("none");
  });

  it("las fechas, como se leen acá", () => {
    expect(shortDate("2026-11-18")).toBe("18/11/2026");
    expect(shortDate(null)).toBe("—");
  });
});

describe("el alta y las notas", () => {
  const alta = {
    supplierId: "00000000-0000-4000-8000-000000000901",
    invoice_class: "invoice_a",
    point_of_sale: "1",
    number: "2001",
    issued_on: "2026-11-18",
    authorization_kind: "cae",
    authorization_code: "75000000000004",
  };

  it("una factura fiscal pide punto de venta y los 14 números de la autorización", () => {
    expect(newInvoiceSchema.safeParse(alta).success).toBe(true);
    const bad = newInvoiceSchema.safeParse({
      ...alta,
      point_of_sale: "",
      authorization_code: "123",
    });
    expect(bad.success).toBe(false);
    expect(bad.error?.issues.map((i) => i.path[0])).toEqual([
      "point_of_sale",
      "authorization_code",
    ]);
  });

  it("un comprobante X o una nota a mano no los piden", () => {
    expect(
      newInvoiceSchema.safeParse({
        supplierId: alta.supplierId,
        invoice_class: "handwritten_note",
        number: "12",
        issued_on: "2026-11-18",
      }).success,
    ).toBe(true);
  });

  it("el número va sin guiones", () => {
    expect(newInvoiceSchema.safeParse({ ...alta, number: "0001-2001" }).success).toBe(false);
  });

  it("una nota lleva importe y motivo; el total no es menor que el importe", () => {
    const nota = {
      note_kind: "credit",
      number: "",
      issued_on: "2026-11-18",
      net_amount: "6",
      total_amount: "",
      reason: "Diferencia de precio",
    };
    expect(noteSchema.safeParse(nota).success).toBe(true);
    expect(noteSchema.safeParse({ ...nota, net_amount: "0" }).success).toBe(false);
    expect(noteSchema.safeParse({ ...nota, total_amount: "5" }).success).toBe(false);
    expect(noteSchema.safeParse({ ...nota, reason: "x" }).success).toBe(false);
  });
});
