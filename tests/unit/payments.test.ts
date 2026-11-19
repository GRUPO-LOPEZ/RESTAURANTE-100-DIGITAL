// Pagos (Fase 3, Prompt 6, ADR-0060): el reparto entre facturas, lo que no puede pasar del pago ni del saldo, los días
// en palabras y la cuenta del proveedor sin el CBU entero.
import { describe, expect, it } from "vitest";

import {
  accountLabel,
  checkAllocations,
  daysLabel,
  distribute,
  paymentSchema,
} from "@/lib/payments";

describe("el reparto de un pago", () => {
  const invoices = [
    { invoice_id: "a", balance: 1000 },
    { invoice_id: "b", balance: 500 },
  ];

  it("cubre primero la que vence antes, sin pasar el saldo", () => {
    expect(distribute(1200, invoices)).toEqual({ allocations: { a: 1000, b: 200 }, left: 0 });
  });

  it("lo que sobra queda a cuenta", () => {
    expect(distribute(1600, invoices)).toEqual({ allocations: { a: 1000, b: 500 }, left: 100 });
  });

  it("un pago chico, parcial en la primera", () => {
    expect(distribute(400, invoices)).toEqual({ allocations: { a: 400 }, left: 0 });
  });
});

describe("lo que se aplica", () => {
  const balances = { a: 1000, b: 500 };

  it("no pasa el saldo de una factura", () => {
    expect(checkAllocations(2000, { a: "1001" }, balances)).toEqual({
      ok: false,
      message: "No se puede pagar más que el saldo de una factura.",
    });
  });

  it("ni el pago", () => {
    expect(checkAllocations(1000, { a: "800", b: "300" }, balances)).toEqual({
      ok: false,
      message: "Lo aplicado a las facturas no puede superar el pago.",
    });
  });

  it("lee los números como acá y deja lo que sobra a cuenta", () => {
    expect(checkAllocations(1500.5, { a: "1.000", b: "", c: "0" }, { ...balances, c: 10 })).toEqual(
      {
        ok: true,
        lines: [{ invoice_id: "a", amount: 1000 }],
        left: 500.5,
      },
    );
  });

  it("sin importe, no hay pago", () => {
    expect(checkAllocations(null, {}, balances)).toEqual({
      ok: false,
      message: "Escribí el importe del pago.",
    });
  });
});

describe("los textos", () => {
  it("los días, en palabras", () => {
    expect(daysLabel(0)).toBe("Vence hoy");
    expect(daysLabel(1)).toBe("Vence mañana");
    expect(daysLabel(3)).toBe("Vence en 3 días");
    expect(daysLabel(-1)).toBe("Venció ayer");
    expect(daysLabel(-5)).toBe("Venció hace 5 días");
  });

  it("la cuenta del proveedor, sin el CBU entero", () => {
    expect(
      accountLabel({
        method: "transfer",
        bank: "Banco Demo",
        alias: "lacteos.demo",
        cbu_end: "0038",
        electronic_code: null,
      }),
    ).toBe("Transferencia · Banco Demo · lacteos.demo · CBU …0038");
  });
});

describe("los datos del pago", () => {
  const base = {
    method: "cash",
    accountId: "",
    paidOn: "2026-11-19",
    amount: "1.500",
    reference: "",
    reason: "Pago de la semana",
  };

  it("en efectivo no pide cuenta", () => {
    expect(paymentSchema.safeParse(base).success).toBe(true);
  });

  it("una transferencia pide la cuenta del proveedor", () => {
    const r = paymentSchema.safeParse({ ...base, method: "transfer" });
    expect(r.success).toBe(false);
    expect(r.error?.issues[0]?.message).toBe("Elegí la cuenta del proveedor.");
  });

  it("con importe y motivo", () => {
    const r = paymentSchema.safeParse({ ...base, amount: "0", reason: "x" });
    expect(r.error?.issues.map((i) => i.path[0])).toEqual(["reason", "amount"]);
  });
});
