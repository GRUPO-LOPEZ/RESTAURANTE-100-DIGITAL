import { describe, expect, it } from "vitest";

import { invoiceTab, newInvoiceSchema } from "@/lib/invoices";
import {
  accountKindFor,
  companyAccountSchema,
  emptyLine,
  linesForBase,
  monthName,
  monthRange,
  paymentOrderSchema,
} from "@/lib/payment-orders";

// Orden de pago, cajas y cuentas, y el alta corta de factura (ADR-0070).
describe("linesForBase", () => {
  const cash = { ...emptyLine("cash"), amount: "1.000,50", companyAccountId: "caja" };

  it("pide al menos un medio y hasta 5", () => {
    expect(linesForBase([])).toMatchObject({ ok: false });
    expect(linesForBase(Array.from({ length: 6 }, () => cash))).toMatchObject({
      ok: false,
      message: "Una orden de pago va hasta con 5 medios.",
    });
  });

  it("suma los importes y redondea a centavos", () => {
    const r = linesForBase([cash, { ...cash, amount: "0,333" }]);
    expect(r).toMatchObject({ ok: true, total: 1000.83 });
  });

  it("pide el importe, la caja o cuenta y la cuenta del proveedor en la transferencia", () => {
    expect(linesForBase([{ ...cash, amount: "" }])).toMatchObject({
      ok: false,
      message: "Escribí el importe.",
    });
    expect(linesForBase([{ ...cash, companyAccountId: "" }])).toMatchObject({ ok: false });
    const transfer = { ...emptyLine("transfer"), amount: "10", companyAccountId: "banco" };
    expect(linesForBase([transfer])).toMatchObject({
      ok: false,
      message: "Elegí la cuenta del proveedor.",
    });
    expect(linesForBase([{ ...transfer, supplierAccountId: "cta" }])).toMatchObject({
      ok: true,
      lines: [{ method: "transfer", company_account_id: "banco", supplier_account_id: "cta" }],
    });
  });

  it("dice qué medio falla cuando hay varios", () => {
    expect(linesForBase([cash, { ...cash, amount: "0" }])).toMatchObject({
      ok: false,
      message: "Escribí el importe (medio 2).",
    });
  });

  it("el cheque propio lleva número, banco y fecha, y viaja como check", () => {
    const own = { ...emptyLine("own_check"), amount: "50", companyAccountId: "banco" };
    expect(linesForBase([own])).toMatchObject({ ok: false });
    const full = { ...own, checkNumber: "123", checkBank: "Banco", checkDueOn: "2026-12-10" };
    const r = linesForBase([full]);
    expect(r).toMatchObject({
      ok: true,
      lines: [{ method: "check", check_number: "123", check_due_on: "2026-12-10" }],
    });
    if (r.ok) expect(r.lines[0]).not.toHaveProperty("check_third_party");
  });

  it("el de terceros no sale de una cuenta nuestra y pide el librador", () => {
    expect(accountKindFor("third_party_check")).toBeNull();
    const third = {
      ...emptyLine("third_party_check"),
      amount: "50",
      checkNumber: "9",
      checkBank: "Banco",
      checkDueOn: "2026-12-10",
    };
    expect(linesForBase([third])).toMatchObject({
      ok: false,
      message: "Escribí quién libró el cheque de terceros.",
    });
    const r = linesForBase([{ ...third, drawerName: "Cliente", drawerTaxId: "20-12345678-9" }]);
    expect(r).toMatchObject({
      ok: true,
      lines: [{ method: "check", check_third_party: true, check_drawer_tax_id: "20123456789" }],
    });
    if (r.ok) expect(r.lines[0]).not.toHaveProperty("company_account_id");
  });
});

describe("paymentOrderSchema", () => {
  it("pide la fecha y el motivo", () => {
    expect(paymentOrderSchema.safeParse({ paidOn: "", notes: "", reason: "ok" }).success).toBe(
      false,
    );
    expect(
      paymentOrderSchema.safeParse({ paidOn: "2026-11-26", notes: "", reason: "Pago" }).success,
    ).toBe(true);
  });
});

describe("companyAccountSchema", () => {
  const base = {
    kind: "cash" as const,
    name: "Caja",
    bank: "",
    accountNumber: "",
    cbu: "",
    alias: "",
    cardLast4: "",
  };
  it("una caja lleva solo el nombre", () => {
    expect(companyAccountSchema.safeParse(base).success).toBe(true);
    expect(companyAccountSchema.safeParse({ ...base, name: " " }).success).toBe(false);
  });
  it("una cuenta lleva el banco y el CBU de 22 números o el número", () => {
    expect(companyAccountSchema.safeParse({ ...base, kind: "bank" }).success).toBe(false);
    expect(
      companyAccountSchema.safeParse({ ...base, kind: "bank", bank: "B", cbu: "123" }).success,
    ).toBe(false);
    expect(
      companyAccountSchema.safeParse({ ...base, kind: "bank", bank: "B", accountNumber: "1" })
        .success,
    ).toBe(true);
    expect(
      companyAccountSchema.safeParse({
        ...base,
        kind: "bank",
        bank: "B",
        cbu: "0000003100012345678901",
        alias: "a b",
      }).success,
    ).toBe(false);
  });
  it("una tarjeta lleva sus últimos 4 números", () => {
    expect(companyAccountSchema.safeParse({ ...base, kind: "card", cardLast4: "12" }).success).toBe(
      false,
    );
    expect(
      companyAccountSchema.safeParse({ ...base, kind: "card", cardLast4: "4321" }).success,
    ).toBe(true);
  });
});

describe("monthRange", () => {
  it("este mes y el pasado, también en enero y en febrero bisiesto", () => {
    expect(monthRange("2026-11-26", "this")).toEqual({ from: "2026-11-01", to: "2026-11-30" });
    expect(monthRange("2026-11-26", "last")).toEqual({ from: "2026-10-01", to: "2026-10-31" });
    expect(monthRange("2027-01-05", "last")).toEqual({ from: "2026-12-01", to: "2026-12-31" });
    expect(monthRange("2028-03-01", "last")).toEqual({ from: "2028-02-01", to: "2028-02-29" });
    expect(monthName("2026-11-01")).toBe("noviembre");
  });
});

describe("el alta corta de factura", () => {
  const base = {
    supplierId: "00000000-0000-4000-8000-000000000001",
    class_pick: "invoice_a",
    other_class: "invoice_c",
    point_of_sale: "3",
    number: "1234",
    issued_on: "2026-11-26",
  };
  it("no pide el CAE (va en la ficha), pero si viene tiene 14 números", () => {
    expect(newInvoiceSchema.safeParse(base).success).toBe(true);
    expect(newInvoiceSchema.safeParse({ ...base, authorization_code: "123" }).success).toBe(false);
  });
  it("«Otro» toma el comprobante del desplegable", () => {
    const r = newInvoiceSchema.safeParse({
      ...base,
      class_pick: "other",
      other_class: "handwritten_note",
      point_of_sale: "",
    });
    expect(r.success && r.data.invoice_class).toBe("handwritten_note");
  });
  it("una fiscal pide el punto de venta", () => {
    expect(newInvoiceSchema.safeParse({ ...base, point_of_sale: "" }).success).toBe(false);
  });
});

describe("invoiceTab", () => {
  it("los estados nuevos y el enlace de antes a las canceladas", () => {
    expect(invoiceTab("para-dar-conforme").filter).toBe("to_approve");
    expect(invoiceTab("vencidas").filter).toBe("overdue");
    expect(invoiceTab("canceladas").label).toBe("Anuladas");
    expect(invoiceTab("cualquiera").label).toBe("Todas");
  });
});
