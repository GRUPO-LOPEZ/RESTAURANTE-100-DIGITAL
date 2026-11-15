// Ficha de proveedor (Fase 3, Prompt 1, ADR-0050): la lógica sin base, para la pantalla y para Vitest. La base vuelve a
// controlar todo al guardar (purchasing.save_supplier_sheet) y decide los permisos.

import type { Database } from "@/lib/database.types";

type Purchasing = Database["purchasing"]["Enums"];
export type Channel = Purchasing["channel"];
export type BillingMode = Purchasing["billing_mode"];
export type ListFrequency = Purchasing["list_frequency"];
export type PaymentTerms = Purchasing["payment_terms"];
export type PaymentMethod = Purchasing["payment_method"];
export type VatCondition = Database["org"]["Enums"]["vat_condition"];

// ---------------------------------------------------------------------------
// CUIT: la misma regla que core.valid_cuit
// ---------------------------------------------------------------------------
const CUIT_WEIGHTS = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];

// Sin espacios, puntos ni guiones. Las letras quedan, para que la validación las rechace.
export function normalizeCuit(value: string): string {
  return value.replace(/[\s.-]/g, "");
}

// 11 números con su dígito verificador: 11 − (suma mod 11), con 11 → 0 y 10 → 9.
export function validCuit(value: string): boolean {
  const cuit = normalizeCuit(value);
  if (!/^[0-9]{11}$/.test(cuit)) return false;
  const sum = CUIT_WEIGHTS.reduce((acc, w, i) => acc + Number(cuit[i]) * w, 0);
  const rest = 11 - (sum % 11);
  const check = rest === 11 ? 0 : rest === 10 ? 9 : rest;
  return check === Number(cuit[10]);
}

// 20-12345678-6. Lo que no son 11 números queda como vino (por ejemplo, un CUIT viejo cargado con otro formato).
export function formatCuit(value: string | null | undefined): string {
  if (!value) return "";
  const cuit = normalizeCuit(value);
  return /^[0-9]{11}$/.test(cuit)
    ? `${cuit.slice(0, 2)}-${cuit.slice(2, 10)}-${cuit.slice(10)}`
    : value;
}

// ---------------------------------------------------------------------------
// Días de la semana: 1 = lunes … 7 = domingo
// ---------------------------------------------------------------------------
export const WEEK_DAYS: { day: number; letter: string; name: string }[] = [
  { day: 1, letter: "Lu", name: "lunes" },
  { day: 2, letter: "Ma", name: "martes" },
  { day: 3, letter: "Mi", name: "miércoles" },
  { day: 4, letter: "Ju", name: "jueves" },
  { day: 5, letter: "Vi", name: "viernes" },
  { day: 6, letter: "Sá", name: "sábado" },
  { day: 7, letter: "Do", name: "domingo" },
];

export function sortDays(days: number[]): number[] {
  return [...new Set(days)].filter((d) => d >= 1 && d <= 7).sort((a, b) => a - b);
}

// «Lu Mi Vi» (en la tabla): dos letras, para no confundir martes con miércoles. Sin días: «Sin días».
export function daysLabel(days: number[] | null | undefined): string {
  const list = sortDays(days ?? []);
  if (list.length === 0) return "Sin días";
  if (list.length === 7) return "Todos los días";
  return list.map((d) => WEEK_DAYS[d - 1]?.letter ?? "").join(" ");
}

// «lunes, miércoles y viernes» (para lectores de pantalla y la ficha de consulta).
export function daysLongLabel(days: number[] | null | undefined): string {
  const names = sortDays(days ?? []).map((d) => WEEK_DAYS[d - 1]?.name ?? "");
  if (names.length === 0) return "Sin días";
  if (names.length === 7) return "Todos los días";
  return names.length === 1 ? names[0]! : `${names.slice(0, -1).join(", ")} y ${names.at(-1)}`;
}

export function toggleDay(days: number[], day: number): number[] {
  return days.includes(day) ? days.filter((d) => d !== day) : sortDays([...days, day]);
}

// ---------------------------------------------------------------------------
// Nombres en castellano
// ---------------------------------------------------------------------------
export const VAT_LABELS: Record<VatCondition, string> = {
  registered: "Responsable inscripto",
  monotax: "Monotributo",
  exempt: "Exento",
};
export const VAT_SHORT: Record<VatCondition, string> = {
  registered: "RI",
  monotax: "Monotributo",
  exempt: "Exento",
};
export const CHANNEL_LABELS: Record<Channel, string> = {
  whatsapp: "WhatsApp",
  email: "Mail",
  supplier_portal: "Sistema propio",
};
export const CHANNEL_TARGET_LABELS: Record<Channel, string> = {
  whatsapp: "Número",
  email: "Correo",
  supplier_portal: "Dirección (https)",
};
export const BILLING_LABELS: Record<BillingMode, string> = {
  a: "Factura A",
  b: "Factura B",
  c: "Factura C",
  invoice_remito: "Factura/remito",
  remito_then_invoice: "Remito y factura",
  non_fiscal: "Comprobante X",
  handwritten_note: "Nota a mano",
};
export const BILLING_ORDER: BillingMode[] = [
  "a",
  "b",
  "c",
  "invoice_remito",
  "remito_then_invoice",
  "non_fiscal",
  "handwritten_note",
];
export const FREQUENCY_LABELS: Record<ListFrequency, string> = {
  weekly: "Semanal",
  biweekly: "Quincenal",
  monthly: "Mensual",
};
export const PAYMENT_TERMS_LABELS: Record<PaymentTerms, string> = {
  cash: "Contado",
  cash_on_delivery: "Contra entrega",
  same_day_transfer: "Transferencia en el día",
  account: "Cuenta corriente",
};
export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: "Efectivo",
  transfer: "Transferencia",
  check: "Cheque",
  echeq: "eCheq",
  card: "Tarjeta",
  electronic_code: "Pago electrónico con código",
};

// «Cuenta corriente a 30 días», «Contado».
export function paymentLabel(
  terms: PaymentTerms | null | undefined,
  days: number | null | undefined,
): string {
  if (!terms) return "Sin cargar";
  return terms === "account" && days
    ? `Cuenta corriente a ${days} días`
    : PAYMENT_TERMS_LABELS[terms];
}

// Una cuenta en una línea: «Transferencia · alias frigorifico.demo · Banco Demo».
export function accountLabel(a: {
  method: PaymentMethod | "";
  cbu: string;
  alias: string;
  bank: string;
  electronicCode: string;
}): string {
  const parts: string[] = [a.method ? PAYMENT_METHOD_LABELS[a.method] : "Sin medio"];
  if (a.alias) parts.push(`alias ${a.alias}`);
  else if (a.cbu) parts.push(`CBU …${a.cbu.slice(-4)}`);
  if (a.electronicCode) parts.push(`código ${a.electronicCode}`);
  if (a.bank) parts.push(a.bank);
  return parts.join(" · ");
}

// ---------------------------------------------------------------------------
// El borrador de la ficha y lo que cambió
// ---------------------------------------------------------------------------
export const SUPPLIER_FIELDS = [
  "name",
  "trade_name",
  "tax_id",
  "vat_condition",
  "address",
  "city",
  "phone",
  "whatsapp",
  "email",
  "sales_contact",
  "admin_contact",
  "notes",
] as const;
export type SupplierField = (typeof SUPPLIER_FIELDS)[number];

export type SheetAccount = {
  // id de la base; vacío si es nueva. key: para React, también en las nuevas.
  id: string;
  key: string;
  method: PaymentMethod | "";
  cbu: string;
  alias: string;
  bank: string;
  holderName: string;
  holderTaxId: string;
  electronicCode: string;
  isActive: boolean;
  remove: boolean;
};

export type SupplierSheetDraft = {
  supplier: Record<SupplierField, string>;
  terms: {
    orderDays: number[];
    deliveryDays: number[];
    receivingFrom: string;
    receivingTo: string;
    poChannel: Channel | "";
    poChannelTarget: string;
    billingModes: BillingMode[];
    priceListFrequency: ListFrequency | "";
    requiresPoApproval: boolean;
  };
  // Vacío para quien no ve el pago (la base no se lo da).
  payment: {
    paymentTerms: PaymentTerms | "";
    paymentDays: string;
    minimumOrderAmount: string;
  } | null;
  accounts: SheetAccount[] | null;
  categories: string[];
  customerNumbers: { restaurantId: string; number: string }[];
};

type TermsKey = keyof SupplierSheetDraft["terms"];
const TERMS_KEYS: TermsKey[] = [
  "orderDays",
  "deliveryDays",
  "receivingFrom",
  "receivingTo",
  "poChannel",
  "poChannelTarget",
  "billingModes",
  "priceListFrequency",
  "requiresPoApproval",
];

export type SupplierChanges = {
  supplier: SupplierField[];
  terms: TermsKey[];
  payment: boolean;
  accounts: boolean;
  categories: boolean;
  customerNumbers: boolean;
};

const sameList = <T>(a: T[], b: T[]) =>
  a.length === b.length && [...a].sort().join("|") === [...b].sort().join("|");

function accountKey(a: SheetAccount): string {
  return [
    a.method,
    a.cbu.trim(),
    a.alias.trim(),
    a.bank.trim(),
    a.holderName.trim(),
    normalizeCuit(a.holderTaxId),
    a.electronicCode.trim(),
    a.isActive,
    a.remove,
  ].join("|");
}

function customerKey(list: { restaurantId: string; number: string }[]): string {
  return list
    .filter((c) => c.number.trim() !== "")
    .map((c) => `${c.restaurantId}=${c.number.trim()}`)
    .sort()
    .join("|");
}

export function supplierChanges(
  saved: SupplierSheetDraft,
  draft: SupplierSheetDraft,
): SupplierChanges {
  const terms = TERMS_KEYS.filter((k) => {
    const a = saved.terms[k];
    const b = draft.terms[k];
    if (Array.isArray(a) && Array.isArray(b)) return !sameList(a as unknown[], b as unknown[]);
    return typeof a === "string" ? a.trim() !== String(b).trim() : a !== b;
  });
  const payment =
    !!saved.payment &&
    !!draft.payment &&
    (saved.payment.paymentTerms !== draft.payment.paymentTerms ||
      saved.payment.paymentDays.trim() !== draft.payment.paymentDays.trim() ||
      saved.payment.minimumOrderAmount.trim() !== draft.payment.minimumOrderAmount.trim());
  const accounts =
    !!saved.accounts &&
    !!draft.accounts &&
    (saved.accounts.length !== draft.accounts.length ||
      draft.accounts.some((a, i) => {
        const before = saved.accounts![i];
        return !before || before.key !== a.key || accountKey(before) !== accountKey(a);
      }));
  return {
    supplier: SUPPLIER_FIELDS.filter((k) => saved.supplier[k].trim() !== draft.supplier[k].trim()),
    terms,
    payment,
    accounts,
    categories: !sameList(saved.categories, draft.categories),
    customerNumbers: customerKey(saved.customerNumbers) !== customerKey(draft.customerNumbers),
  };
}

export function countSupplierChanges(c: SupplierChanges): number {
  return (
    c.supplier.length +
    c.terms.length +
    (c.payment ? 1 : 0) +
    (c.accounts ? 1 : 0) +
    (c.categories ? 1 : 0) +
    (c.customerNumbers ? 1 : 0)
  );
}

// Lo que viaja a la base (p_changes): solo lo que cambió, con los nombres de la base.
export type SupplierPayload = {
  supplier?: Partial<Record<SupplierField, string>>;
  terms?: {
    order_days?: number[];
    delivery_days?: number[];
    receiving_from?: string;
    receiving_to?: string;
    po_channel?: string;
    po_channel_target?: string;
    billing_modes?: string[];
    price_list_frequency?: string;
    requires_po_approval?: boolean;
  };
  payment_terms?: { payment_terms: string; payment_days: string; minimum_order_amount: string };
  accounts?: {
    id?: string;
    remove?: boolean;
    method?: string;
    cbu?: string;
    alias?: string;
    bank?: string;
    holder_name?: string;
    holder_tax_id?: string;
    electronic_code?: string;
    is_active?: boolean;
  }[];
  categories?: string[];
  customer_numbers?: { restaurant_id: string; customer_number: string }[];
};

const TERMS_COLUMN: Record<TermsKey, keyof NonNullable<SupplierPayload["terms"]>> = {
  orderDays: "order_days",
  deliveryDays: "delivery_days",
  receivingFrom: "receiving_from",
  receivingTo: "receiving_to",
  poChannel: "po_channel",
  poChannelTarget: "po_channel_target",
  billingModes: "billing_modes",
  priceListFrequency: "price_list_frequency",
  requiresPoApproval: "requires_po_approval",
};

export function supplierPayload(
  saved: SupplierSheetDraft,
  draft: SupplierSheetDraft,
): SupplierPayload {
  const c = supplierChanges(saved, draft);
  const out: SupplierPayload = {};
  if (c.supplier.length > 0) {
    out.supplier = Object.fromEntries(c.supplier.map((k) => [k, draft.supplier[k].trim()]));
  }
  if (c.terms.length > 0) {
    const terms: Record<string, unknown> = {};
    for (const k of c.terms) {
      const v = draft.terms[k];
      terms[TERMS_COLUMN[k]] = typeof v === "string" ? v.trim() : v;
    }
    // El canal y su dato van juntos: la base los controla como par.
    if (c.terms.includes("poChannel") || c.terms.includes("poChannelTarget")) {
      terms.po_channel = draft.terms.poChannel;
      terms.po_channel_target = draft.terms.poChannel ? draft.terms.poChannelTarget.trim() : "";
    }
    // El horario también: desde y hasta.
    if (c.terms.includes("receivingFrom") || c.terms.includes("receivingTo")) {
      terms.receiving_from = draft.terms.receivingFrom;
      terms.receiving_to = draft.terms.receivingTo;
    }
    out.terms = terms as SupplierPayload["terms"];
  }
  if (c.payment && draft.payment) {
    out.payment_terms = {
      payment_terms: draft.payment.paymentTerms,
      payment_days:
        draft.payment.paymentTerms === "account" ? draft.payment.paymentDays.trim() : "0",
      minimum_order_amount: draft.payment.minimumOrderAmount.trim().replace(",", "."),
    };
  }
  if (c.accounts && draft.accounts && saved.accounts) {
    const before = new Map(saved.accounts.map((a) => [a.key, a]));
    out.accounts = draft.accounts
      .filter((a) => {
        const old = before.get(a.key);
        if (!a.id) return !a.remove;
        return !old || accountKey(old) !== accountKey(a);
      })
      .map((a) =>
        a.id && a.remove
          ? { id: a.id, remove: true }
          : {
              ...(a.id ? { id: a.id } : {}),
              method: a.method,
              cbu: a.cbu.trim(),
              alias: a.alias.trim(),
              bank: a.bank.trim(),
              holder_name: a.holderName.trim(),
              holder_tax_id: a.holderTaxId.trim(),
              electronic_code: a.electronicCode.trim(),
              is_active: a.isActive,
            },
      );
  }
  if (c.categories) out.categories = draft.categories;
  if (c.customerNumbers) {
    out.customer_numbers = draft.customerNumbers
      .filter((n) => n.number.trim() !== "")
      .map((n) => ({ restaurant_id: n.restaurantId, customer_number: n.number.trim() }));
  }
  return out;
}

export function emptyAccount(key: string): SheetAccount {
  return {
    id: "",
    key,
    method: "transfer",
    cbu: "",
    alias: "",
    bank: "",
    holderName: "",
    holderTaxId: "",
    electronicCode: "",
    isActive: true,
    remove: false,
  };
}
