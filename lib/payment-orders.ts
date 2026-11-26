import { z } from "zod";

import { readNumber } from "@/lib/invoices";

// Orden de pago (ADR-0070): reglas de la pantalla, sin acceso a la base. Se prueban con Vitest. La base vuelve a
// controlar todo (purchasing.register_payment_order: el permiso, las cajas y cuentas, los cheques, el saldo).

// Los medios de una orden de pago, como los ve la persona (el cheque de terceros es un cheque con su librador).
export type OrderMethod =
  "cash" | "transfer" | "own_check" | "third_party_check" | "echeq" | "card";

export const ORDER_METHOD_LABELS: Record<OrderMethod, string> = {
  cash: "Efectivo",
  transfer: "Transferencia",
  own_check: "Cheque propio",
  third_party_check: "Cheque de terceros",
  echeq: "E-cheq",
  card: "Tarjeta",
};
export const ORDER_METHODS = Object.keys(ORDER_METHOD_LABELS) as OrderMethod[];

export type AccountKind = "cash" | "bank" | "card";
export const ACCOUNT_KIND_LABELS: Record<AccountKind, string> = {
  cash: "Caja",
  bank: "Cuenta bancaria",
  card: "Tarjeta",
};

// De qué tipo de caja o cuenta sale cada medio (null: el cheque de terceros no sale de una cuenta nuestra).
export function accountKindFor(method: OrderMethod): AccountKind | null {
  if (method === "cash") return "cash";
  if (method === "card") return "card";
  if (method === "third_party_check") return null;
  return "bank";
}

// Si el medio lleva los datos de un cheque, y si lleva la cuenta del proveedor.
export const hasCheck = (m: OrderMethod) =>
  m === "own_check" || m === "third_party_check" || m === "echeq";
export const needsSupplierAccount = (m: OrderMethod) => m === "transfer";

// Un medio de la orden, como se carga en la pantalla (los importes y fechas como texto).
export type OrderLine = {
  method: OrderMethod;
  companyAccountId: string;
  supplierAccountId: string;
  amount: string;
  reference: string;
  checkNumber: string;
  checkBank: string;
  checkDueOn: string;
  drawerName: string;
  drawerTaxId: string;
};
export const emptyLine = (method: OrderMethod = "transfer"): OrderLine => ({
  method,
  companyAccountId: "",
  supplierAccountId: "",
  amount: "",
  reference: "",
  checkNumber: "",
  checkBank: "",
  checkDueOn: "",
  drawerName: "",
  drawerTaxId: "",
});

// Lo que viaja a la base (purchasing.register_payment_order, p_lines), o el primer error en castellano.
export function linesForBase(
  lines: OrderLine[],
):
  | { ok: true; lines: Record<string, string | number | boolean>[]; total: number }
  | { ok: false; message: string } {
  if (lines.length === 0) return { ok: false, message: "Elegí cómo se paga (al menos un medio)." };
  if (lines.length > 5) return { ok: false, message: "Una orden de pago va hasta con 5 medios." };
  const out: Record<string, string | number | boolean>[] = [];
  let total = 0;
  for (const [i, l] of lines.entries()) {
    const n = readNumber(l.amount);
    const which = lines.length > 1 ? ` (medio ${i + 1})` : "";
    if (n === null || n <= 0) return { ok: false, message: `Escribí el importe${which}.` };
    const kind = accountKindFor(l.method);
    if (kind && !l.companyAccountId)
      return { ok: false, message: `Elegí de qué caja o cuenta sale${which}.` };
    if (needsSupplierAccount(l.method) && !l.supplierAccountId)
      return { ok: false, message: `Elegí la cuenta del proveedor${which}.` };
    if (hasCheck(l.method) && (!l.checkNumber.trim() || !l.checkBank.trim() || !l.checkDueOn))
      return { ok: false, message: `El cheque lleva número, banco y fecha de cobro${which}.` };
    if (l.method === "third_party_check" && !l.drawerName.trim())
      return { ok: false, message: `Escribí quién libró el cheque de terceros${which}.` };
    total += n;
    const base: Record<string, string | number | boolean> = {
      method: l.method === "own_check" || l.method === "third_party_check" ? "check" : l.method,
      amount: Math.round(n * 100) / 100,
    };
    if (kind) base.company_account_id = l.companyAccountId;
    if (l.supplierAccountId && l.method === "transfer")
      base.supplier_account_id = l.supplierAccountId;
    if (l.reference.trim()) base.reference = l.reference.trim().slice(0, 80);
    if (hasCheck(l.method)) {
      base.check_number = l.checkNumber.trim();
      base.check_bank = l.checkBank.trim();
      base.check_due_on = l.checkDueOn;
    }
    if (l.method === "third_party_check") {
      base.check_third_party = true;
      base.check_drawer_name = l.drawerName.trim();
      if (l.drawerTaxId.trim()) base.check_drawer_tax_id = l.drawerTaxId.replace(/\D/g, "");
    }
    out.push(base);
  }
  return { ok: true, lines: out, total: Math.round(total * 100) / 100 };
}

// El resto de la orden: fecha, notas y motivo. El mismo esquema en el navegador y en la acción.
export const paymentOrderSchema = z.object({
  paidOn: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha del pago."),
  notes: z.string().trim().max(500, "Las observaciones van hasta 500 caracteres."),
  reason: z.string().trim().min(3, "Escribí el motivo.").max(500, "Hasta 500 caracteres."),
});

// ---------------------------------------------------------------------------
// Cajas y cuentas de la razón social (su ficha)
// ---------------------------------------------------------------------------
export const companyAccountSchema = z
  .object({
    kind: z.enum(["cash", "bank", "card"], { message: "Elegí si es caja, cuenta o tarjeta." }),
    name: z.string().trim().min(1, "Escribí cómo se llama.").max(80, "Hasta 80 caracteres."),
    bank: z.string().trim().max(80, "Hasta 80 caracteres."),
    accountNumber: z.string().trim().max(40, "Hasta 40 caracteres."),
    cbu: z.string().trim(),
    alias: z.string().trim(),
    cardLast4: z.string().trim(),
  })
  .superRefine((v, ctx) => {
    const cbu = v.cbu.replace(/\D/g, "");
    if (v.kind === "bank") {
      if (!v.bank) ctx.addIssue({ code: "custom", path: ["bank"], message: "Escribí el banco." });
      if (!cbu && !v.accountNumber)
        ctx.addIssue({
          code: "custom",
          path: ["cbu"],
          message: "Escribí el CBU o el número de cuenta.",
        });
    }
    if (cbu && cbu.length !== 22)
      ctx.addIssue({ code: "custom", path: ["cbu"], message: "El CBU tiene 22 números." });
    if (v.alias && !/^[A-Za-z0-9.-]{6,20}$/.test(v.alias))
      ctx.addIssue({
        code: "custom",
        path: ["alias"],
        message: "El alias va de 6 a 20 letras, números, puntos o guiones.",
      });
    if (v.kind === "card" && !/^\d{4}$/.test(v.cardLast4))
      ctx.addIssue({
        code: "custom",
        path: ["cardLast4"],
        message: "Escribí los últimos 4 números de la tarjeta.",
      });
  });

// ---------------------------------------------------------------------------
// Fechas del listado de facturas: «este mes» y «el mes pasado»
// ---------------------------------------------------------------------------
const pad = (n: number) => String(n).padStart(2, "0");
// Desde y hasta (aaaa-mm-dd) del mes de una fecha, y del anterior. today es la fecha de hoy en la Argentina.
export function monthRange(today: string, which: "this" | "last"): { from: string; to: string } {
  const [y = 1970, m = 1] = today.split("-").map(Number);
  const year = which === "last" && m === 1 ? y - 1 : y;
  const month = which === "last" ? (m === 1 ? 12 : m - 1) : m;
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return { from: `${year}-${pad(month)}-01`, to: `${year}-${pad(month)}-${pad(last)}` };
}

const MONTHS = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre",
];
// «de noviembre» para el subtítulo del listado.
export function monthName(iso: string): string {
  const m = Number(iso.slice(5, 7));
  return MONTHS[m - 1] ?? "";
}
