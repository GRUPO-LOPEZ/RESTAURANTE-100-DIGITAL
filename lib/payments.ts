import { z } from "zod";

import { readNumber } from "@/lib/invoices";

// Pagos (Fase 3, Prompt 6, ADR-0060): reglas de la pantalla, sin acceso a la base. Se prueban con Vitest. La base vuelve
// a controlar todo (purchasing.register_payment: el saldo, el local, la cuenta del proveedor).

export type PaymentMethod = "cash" | "transfer" | "check" | "echeq" | "card" | "electronic_code";

export const METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: "Efectivo",
  transfer: "Transferencia",
  check: "Cheque",
  echeq: "eCheq",
  card: "Tarjeta",
  electronic_code: "Pago electrónico",
};

// Pestañas de /compras/pagos.
export const PAYMENT_TABS: {
  value: string | undefined;
  label: string;
  tab: "due" | "overdue" | "paid" | "cash" | "orders";
}[] = [
  { value: undefined, label: "Por vencer", tab: "due" },
  { value: "vencidas", label: "Vencidas", tab: "overdue" },
  { value: "pagadas", label: "Pagadas", tab: "paid" },
  { value: "para-confirmar", label: "Para confirmar", tab: "cash" },
  { value: "ordenes", label: "Órdenes de pago", tab: "orders" },
];

// El estado de un vencimiento, siempre con palabra.
export const DUE_LABELS: Record<
  "ok" | "warn" | "bad" | "none",
  { label: string; status: "ok" | "warn" | "bad" | "none" }
> = {
  ok: { label: "Al día", status: "ok" },
  warn: { label: "Vence pronto", status: "warn" },
  bad: { label: "Vencida", status: "bad" },
  none: { label: "Pagada", status: "none" },
};

// Cuántos días faltan, en palabras.
export function daysLabel(daysLeft: number): string {
  if (daysLeft === 0) return "Vence hoy";
  if (daysLeft === 1) return "Vence mañana";
  if (daysLeft > 1) return `Vence en ${daysLeft} días`;
  if (daysLeft === -1) return "Venció ayer";
  return `Venció hace ${-daysLeft} días`;
}

export const MOVEMENT_LABELS: Record<
  "invoice" | "credit_note" | "debit_note" | "discount" | "payment",
  string
> = {
  invoice: "Factura",
  credit_note: "Nota de crédito",
  debit_note: "Nota de débito",
  discount: "Descuento",
  payment: "Pago",
};

// Una cuenta de pago del proveedor, en una línea (sin el CBU entero: la base da los últimos 4).
export function accountLabel(a: {
  method: PaymentMethod;
  bank: string | null;
  alias: string | null;
  cbu_end: string | null;
  electronic_code: string | null;
}): string {
  const parts = [
    METHOD_LABELS[a.method],
    a.bank,
    a.alias,
    a.cbu_end ? `CBU …${a.cbu_end}` : null,
    a.electronic_code ? `código ${a.electronic_code}` : null,
  ];
  return parts.filter(Boolean).join(" · ");
}

// Reparte un importe entre las facturas, de la que vence antes a la que vence después, sin pasar el saldo de cada una.
// Lo que sobra queda a cuenta.
export function distribute(
  amount: number,
  invoices: { invoice_id: string; balance: number }[],
): { allocations: Record<string, number>; left: number } {
  let left = Math.round(amount * 100) / 100;
  const allocations: Record<string, number> = {};
  for (const i of invoices) {
    if (left <= 0) break;
    const take = Math.min(left, Math.round(i.balance * 100) / 100);
    if (take > 0) {
      allocations[i.invoice_id] = take;
      left = Math.round((left - take) * 100) / 100;
    }
  }
  return { allocations, left };
}

// Lo que se aplica no pasa del pago ni del saldo de cada factura (la base lo vuelve a controlar).
export function checkAllocations(
  amount: number | null,
  allocations: Record<string, string>,
  balances: Record<string, number>,
):
  | { ok: true; lines: { invoice_id: string; amount: number }[]; left: number }
  | { ok: false; message: string } {
  if (amount === null || amount <= 0) return { ok: false, message: "Escribí el importe del pago." };
  const lines: { invoice_id: string; amount: number }[] = [];
  for (const [invoiceId, text] of Object.entries(allocations)) {
    if (text.trim() === "") continue;
    const n = readNumber(text);
    if (n === null || n < 0)
      return { ok: false, message: "Lo que se paga de cada factura va en números." };
    if (n === 0) continue;
    if (n > (balances[invoiceId] ?? 0) + 0.00001)
      return { ok: false, message: "No se puede pagar más que el saldo de una factura." };
    lines.push({ invoice_id: invoiceId, amount: n });
  }
  const applied = Math.round(lines.reduce((s, l) => s + l.amount, 0) * 100) / 100;
  if (applied > amount + 0.00001)
    return { ok: false, message: "Lo aplicado a las facturas no puede superar el pago." };
  return { ok: true, lines, left: Math.round((amount - applied) * 100) / 100 };
}

// Los datos del pago (lo que no son las facturas). El mismo esquema en el navegador y en la acción.
export const paymentSchema = z
  .object({
    method: z.enum(["cash", "transfer", "check", "echeq", "card", "electronic_code"], {
      message: "Elegí el medio de pago.",
    }),
    accountId: z.string().trim(),
    paidOn: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha."),
    amount: z.string().trim(),
    reference: z.string().trim().max(80, "Hasta 80 caracteres."),
    reason: z.string().trim().min(3, "Escribí el motivo.").max(500, "Hasta 500 caracteres."),
  })
  .superRefine((v, ctx) => {
    const n = readNumber(v.amount);
    if (n === null || n <= 0)
      ctx.addIssue({ code: "custom", path: ["amount"], message: "Escribí el importe del pago." });
    if (v.method !== "cash" && !/^[0-9a-f-]{36}$/.test(v.accountId))
      ctx.addIssue({
        code: "custom",
        path: ["accountId"],
        message: "Elegí la cuenta del proveedor.",
      });
  });
