import { z } from "zod";

import { validCuit } from "@/lib/suppliers";

// Facturas de compra (Fase 3, Prompt 5, ADR-0058): reglas de la pantalla, sin acceso a la base. Se prueban con Vitest.
// La base vuelve a controlar todo (purchasing.create_invoice, save_invoice, run_invoice_checks…).

export type InvoiceClass =
  "invoice_a" | "invoice_b" | "invoice_c" | "invoice_remito_a" | "non_fiscal" | "handwritten_note";
export type InvoiceStatus =
  "loaded" | "in_control" | "observed" | "approved" | "released" | "paid" | "cancelled";
export type InvoiceCheckKind =
  "quantity" | "price" | "mapping" | "totals" | "legal_entity" | "order" | "notes";

export const INVOICE_CLASSES: { value: InvoiceClass; label: string; short: string }[] = [
  { value: "invoice_a", label: "Factura A", short: "A" },
  { value: "invoice_b", label: "Factura B", short: "B" },
  { value: "invoice_c", label: "Factura C", short: "C" },
  { value: "invoice_remito_a", label: "Factura-remito A", short: "A (remito)" },
  { value: "non_fiscal", label: "Comprobante X", short: "X" },
  { value: "handwritten_note", label: "Nota a mano", short: "Nota" },
];

// Los que van en «Otro» del alta (los de siempre son botones).
export const OTHER_INVOICE_CLASSES: InvoiceClass[] = [
  "invoice_c",
  "non_fiscal",
  "handwritten_note",
];

// Fiscales: llevan punto de venta, autorización y CUIT del emisor (como invoices_fiscal_check).
export function isFiscal(invoiceClass: InvoiceClass): boolean {
  return invoiceClass !== "non_fiscal" && invoiceClass !== "handwritten_note";
}

// Discriminan IVA: el costo va neto con razón social responsable inscripta (como purchasing.invoice_is_a).
export function isClassA(invoiceClass: InvoiceClass): boolean {
  return invoiceClass === "invoice_a" || invoiceClass === "invoice_remito_a";
}

// Estados con palabra (nunca solo color).
export const INVOICE_STATUS: Record<
  InvoiceStatus,
  { label: string; status: "ok" | "info" | "none" | "warn" | "bad" | "review" }
> = {
  loaded: { label: "Cargada", status: "info" },
  in_control: { label: "En control", status: "review" },
  observed: { label: "Observada", status: "warn" },
  approved: { label: "Conforme", status: "ok" },
  released: { label: "Liberada", status: "ok" },
  paid: { label: "Pagada", status: "ok" },
  cancelled: { label: "Anulada", status: "none" },
};

export const CHECK_LABELS: Record<InvoiceCheckKind, string> = {
  quantity: "Cantidad contra lo recibido",
  price: "Precio contra la lista",
  mapping: "Artículo reconocido",
  totals: "Totales",
  legal_entity: "Razón social del local",
  order: "Orden de compra y recepción",
  notes: "Notas de crédito y débito",
};

// Cómo se lee una factura, igual que purchasing.invoice_label: «Factura A 0003-00012345».
export function invoiceLabel(
  invoiceClass: InvoiceClass,
  pointOfSale: number | null,
  number: number,
): string {
  const name = INVOICE_CLASSES.find((c) => c.value === invoiceClass)?.label ?? "Factura";
  const pos = pointOfSale !== null ? `${String(pointOfSale).padStart(4, "0")}-` : "";
  return `${name} ${pos}${String(number).padStart(8, "0")}`;
}

// Las partes suman el total, con 0,01 de tolerancia (como invoices_totals_check).
export type InvoiceAmounts = {
  net_amount: number;
  exempt_amount: number;
  vat_amount: number;
  internal_tax_amount: number;
  perception_amount: number;
  discount_amount: number;
  rounding_amount: number;
  total_amount: number;
};
export function totalsDifference(a: InvoiceAmounts): number {
  const parts =
    a.net_amount +
    a.exempt_amount +
    a.vat_amount +
    a.internal_tax_amount +
    a.perception_amount -
    a.discount_amount +
    a.rounding_amount;
  return Math.round((parts - a.total_amount) * 100) / 100;
}
export function totalsClose(a: InvoiceAmounts): boolean {
  return Math.abs(totalsDifference(a)) <= 0.01;
}

const amount = z.number({ message: "Va un número." }).min(0, "No puede ser negativo.");
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha.");

// La cabecera de una factura. El mismo esquema en el navegador y en el servidor.
export const invoiceHeaderSchema = z
  .object({
    invoice_class: z.enum(
      ["invoice_a", "invoice_b", "invoice_c", "invoice_remito_a", "non_fiscal", "handwritten_note"],
      { message: "Elegí la clase de comprobante." },
    ),
    point_of_sale: z
      .number({ message: "Va un número." })
      .int("Va sin decimales.")
      .min(1, "El punto de venta va de 1 a 99999.")
      .max(99999, "El punto de venta va de 1 a 99999.")
      .nullable(),
    number: z
      .number({ message: "Va un número." })
      .int("Va sin decimales.")
      .min(1, "El número va de 1 a 99999999.")
      .max(99999999, "El número va de 1 a 99999999."),
    authorization_kind: z.enum(["cae", "cai", "caea"]).nullable(),
    authorization_code: z
      .string()
      .trim()
      .regex(/^\d{14}$/, "La autorización tiene 14 números.")
      .nullable(),
    issuer_tax_id: z.string().trim().nullable(),
    receiver_tax_id: z.string().trim().nullable(),
    issued_on: isoDate,
    due_on: isoDate.nullable(),
    net_amount: amount,
    exempt_amount: amount,
    vat_amount: amount,
    internal_tax_amount: amount,
    perception_amount: amount,
    discount_amount: amount,
    rounding_amount: z.number({ message: "Va un número." }).min(-100).max(100),
    total_amount: amount,
  })
  .superRefine((h, ctx) => {
    if (isFiscal(h.invoice_class)) {
      if (h.point_of_sale === null)
        ctx.addIssue({
          code: "custom",
          path: ["point_of_sale"],
          message: "Escribí el punto de venta.",
        });
      if (h.authorization_kind === null || h.authorization_code === null)
        ctx.addIssue({
          code: "custom",
          path: ["authorization_code"],
          message: "Una factura fiscal lleva autorización (CAE, CAI o CAEA).",
        });
      if (!h.issuer_tax_id)
        ctx.addIssue({
          code: "custom",
          path: ["issuer_tax_id"],
          message: "Escribí el CUIT del emisor.",
        });
    } else if (h.vat_amount !== 0) {
      ctx.addIssue({
        code: "custom",
        path: ["vat_amount"],
        message: "Un comprobante X o una nota a mano no llevan IVA.",
      });
    }
    const issuer = h.issuer_tax_id?.replace(/\D/g, "") ?? "";
    if (issuer === "99999999999")
      ctx.addIssue({
        code: "custom",
        path: ["issuer_tax_id"],
        message: "El CUIT del emisor es de ejemplo (99-99999999-9): esa factura no vale.",
      });
    else if (issuer && !validCuit(issuer))
      ctx.addIssue({
        code: "custom",
        path: ["issuer_tax_id"],
        message: "El CUIT del emisor no es válido.",
      });
    if (h.due_on !== null && h.due_on < h.issued_on)
      ctx.addIssue({
        code: "custom",
        path: ["due_on"],
        message: "El vencimiento no puede ser anterior a la fecha de la factura.",
      });
    if (!totalsClose(h))
      ctx.addIssue({
        code: "custom",
        path: ["total_amount"],
        message: "Las partes no suman el total.",
      });
  });
export type InvoiceHeaderInput = z.infer<typeof invoiceHeaderSchema>;

// ---------------------------------------------------------------------------
// Pantallas (PR 5B): listado, alta y ficha. Reglas sin acceso a la base, probadas con Vitest.
// ---------------------------------------------------------------------------

// Pestañas del listado. «Conformes» suma las liberadas a pago: el conforme libera en la misma transacción.
// Los estados del listado (ADR-0070): un desplegable con todos y, a la vista, los tres que piden hacer algo.
export const INVOICE_TABS: {
  value: string | undefined;
  label: string;
  filter?: string;
  todo?: boolean;
}[] = [
  { value: undefined, label: "Todas" },
  { value: "cargadas", label: "Cargadas", filter: "loaded" },
  { value: "observadas", label: "Observadas", filter: "observed", todo: true },
  { value: "para-dar-conforme", label: "Para dar conforme", filter: "to_approve", todo: true },
  { value: "conformes", label: "Conformes", filter: "released" },
  { value: "vencidas", label: "Vencidas", filter: "overdue", todo: true },
  { value: "pagadas", label: "Pagadas", filter: "paid" },
  { value: "anuladas", label: "Anuladas", filter: "cancelled" },
];
// Un enlace de antes (?estado=canceladas) sigue llevando a las anuladas.
export function invoiceTab(value: string | undefined) {
  const v = value === "canceladas" ? "anuladas" : value;
  return INVOICE_TABS.find((t) => t.value === v) ?? INVOICE_TABS[0]!;
}

export type InvoiceLineClass =
  "product" | "freight" | "service" | "rounding" | "deposit" | "free_of_charge";
export const LINE_CLASS_LABELS: Record<InvoiceLineClass, string> = {
  product: "Mercadería",
  freight: "Flete",
  service: "Servicio",
  rounding: "Redondeo",
  deposit: "Envase retornable",
  free_of_charge: "Regalo",
};
// Lo que se suma a mano (la mercadería sale de la OC; el regalo, de la bonificación del 99 % o más).
export const NEW_LINE_CLASSES: InvoiceLineClass[] = [
  "product",
  "freight",
  "service",
  "deposit",
  "rounding",
];

export type NoteKind = "credit" | "debit" | "discount";
export const NOTE_KINDS: { value: NoteKind; label: string }[] = [
  { value: "credit", label: "Nota de crédito" },
  { value: "debit", label: "Nota de débito" },
  { value: "discount", label: "Descuento" },
];

export type InvoiceTaxKind = "iibb" | "vat_perception" | "municipal" | "other";
export const TAX_KIND_LABELS: Record<InvoiceTaxKind, string> = {
  iibb: "Ingresos brutos",
  vat_perception: "Percepción de IVA",
  municipal: "Municipal",
  other: "Otro",
};

// Las alícuotas de IVA de una línea (como invoice_lines.vat_rate; con 2,5 % y 5 %, P5).
export const INVOICE_VAT_RATES = ["21", "10.5", "27", "5", "2.5", "0"] as const;

export const AUTHORIZATION_KINDS: { value: "cae" | "cai" | "caea"; label: string }[] = [
  { value: "cae", label: "CAE" },
  { value: "cai", label: "CAI" },
  { value: "caea", label: "CAEA" },
];

// Un número para un campo de texto, con coma decimal y sin separador de miles (readNumber lo vuelve a leer igual).
export function numberText(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return "";
  return String(Math.round(value * 1e6) / 1e6).replace(".", ",");
}

// Un número escrito en la ficha, como parseAmount: «1.500» son mil quinientos; «2,5» y «2.5», dos y medio. Vacío es
// null. Con signo menos solo donde se admite (el redondeo).
export function readNumber(text: string, allowNegative = false): number | null {
  const value = text.trim();
  if (value === "") return null;
  const negative = allowNegative && value.startsWith("-");
  const body = negative ? value.slice(1).trim() : value;
  let n: number | null = null;
  if (/^[1-9]\d{0,2}(\.\d{3})+(,\d+)?$/.test(body))
    n = Number(body.replaceAll(".", "").replace(",", "."));
  else if (/^\d+([.,]\d+)?$/.test(body)) n = Number(body.replace(",", "."));
  if (n === null) return null;
  return negative ? -n : n;
}

// El importe de una línea: cantidad × precio neto, a centavos (como purchasing.write_invoice_lines).
export function lineAmount(quantity: number | null, price: number | null): number | null {
  if (quantity === null || price === null) return null;
  return Math.round(quantity * price * 100) / 100;
}

export type HeaderField =
  | "invoice_class"
  | "point_of_sale"
  | "number"
  | "authorization_kind"
  | "authorization_code"
  | "receiver_tax_id"
  | "issued_on"
  | "due_on"
  | "net_amount"
  | "exempt_amount"
  | "vat_amount"
  | "internal_tax_amount"
  | "perception_amount"
  | "discount_amount"
  | "rounding_amount"
  | "total_amount";

export const AMOUNT_FIELDS: { field: keyof InvoiceAmounts & HeaderField; label: string }[] = [
  { field: "net_amount", label: "Neto gravado" },
  { field: "exempt_amount", label: "Exento" },
  { field: "vat_amount", label: "IVA" },
  { field: "internal_tax_amount", label: "Impuestos internos" },
  { field: "perception_amount", label: "Percepciones" },
  { field: "discount_amount", label: "Descuento" },
  { field: "rounding_amount", label: "Redondeo" },
  { field: "total_amount", label: "Total" },
];

export type HeaderDraft = Record<HeaderField, string> & { issuer_tax_id: string };

export type LineDraft = {
  key: string;
  // La línea guardada (null si es nueva): sirve para mostrar su control.
  id: string | null;
  line_class: InvoiceLineClass;
  purchase_product_id: string | null;
  purchase_order_line_id: string | null;
  // El producto reconocido, para leer al lado.
  product: string | null;
  raw_name: string;
  supplier_sku: string;
  units: string;
  billed_quantity: string;
  list_price: number | null;
  bonus1_pct: number;
  bonus2_pct: number;
  bonus_per_unit_amount: number;
  unit_price: string;
  vat_rate: string;
  is_exempt: boolean;
  internal_tax_amount: string;
  by_weight: boolean;
};

export type TaxDraft = {
  key: string;
  tax_kind: InvoiceTaxKind;
  jurisdiction: string;
  rate_pct: string;
  tax_amount: string;
};

export type InvoiceDraft = { header: HeaderDraft; lines: LineDraft[]; taxes: TaxDraft[] };

const LINE_KEYS: (keyof LineDraft)[] = [
  "line_class",
  "purchase_product_id",
  "raw_name",
  "supplier_sku",
  "units",
  "billed_quantity",
  "unit_price",
  "vat_rate",
  "is_exempt",
  "internal_tax_amount",
];
const TAX_KEYS: (keyof TaxDraft)[] = ["tax_kind", "jurisdiction", "rate_pct", "tax_amount"];

function sameBy<T>(a: T, b: T, keys: (keyof T)[]): boolean {
  return keys.every((k) => a[k] === b[k]);
}

export type InvoiceChanges = {
  header: HeaderField[];
  // Las líneas cambiadas o nuevas (por su clave) y cuántas se quitaron.
  lines: string[];
  removedLines: number;
  taxes: string[];
  removedTaxes: number;
};

export function invoiceChanges(saved: InvoiceDraft, draft: InvoiceDraft): InvoiceChanges {
  const header = (Object.keys(saved.header) as (keyof HeaderDraft)[]).filter(
    (k): k is HeaderField => k !== "issuer_tax_id" && saved.header[k] !== draft.header[k],
  );
  const savedLines = new Map(saved.lines.map((l) => [l.key, l]));
  const lines = draft.lines
    .filter((l) => {
      const before = savedLines.get(l.key);
      return !before || !sameBy(before, l, LINE_KEYS);
    })
    .map((l) => l.key);
  const draftLineKeys = new Set(draft.lines.map((l) => l.key));
  const savedTaxes = new Map(saved.taxes.map((t) => [t.key, t]));
  const taxes = draft.taxes
    .filter((t) => {
      const before = savedTaxes.get(t.key);
      return !before || !sameBy(before, t, TAX_KEYS);
    })
    .map((t) => t.key);
  const draftTaxKeys = new Set(draft.taxes.map((t) => t.key));
  return {
    header,
    lines,
    removedLines: saved.lines.filter((l) => !draftLineKeys.has(l.key)).length,
    taxes,
    removedTaxes: saved.taxes.filter((t) => !draftTaxKeys.has(t.key)).length,
  };
}

export function countInvoiceChanges(c: InvoiceChanges): number {
  return c.header.length + c.lines.length + c.removedLines + c.taxes.length + c.removedTaxes;
}

// Lo que se manda a purchasing.save_invoice: la cabecera siempre (la base la aplica entera); las líneas y las
// percepciones, enteras y solo si cambiaron (la base reemplaza cada lista). Si un dato no se entiende, el error.
export type InvoicePayload = {
  header: Record<string, string | number | null>;
  lines: Record<string, string | number | boolean | null>[] | null;
  taxes: Record<string, string | number | null>[] | null;
};

export function invoicePayload(
  saved: InvoiceDraft,
  draft: InvoiceDraft,
): { ok: true; payload: InvoicePayload } | { ok: false; message: string } {
  const c = invoiceChanges(saved, draft);
  const h = draft.header;
  const fiscal = isFiscal(h.invoice_class as InvoiceClass);
  const amounts: Record<string, number> = {};
  for (const { field, label } of AMOUNT_FIELDS) {
    const n = readNumber(h[field], field === "rounding_amount");
    if (n === null && h[field].trim() !== "")
      return { ok: false, message: `${label}: escribí un número.` };
    amounts[field] = n ?? 0;
  }
  const number = readNumber(h.number);
  if (number === null || !Number.isInteger(number))
    return { ok: false, message: "Escribí el número de la factura." };
  const header: InvoicePayload["header"] = {
    invoice_class: h.invoice_class,
    point_of_sale: fiscal ? readNumber(h.point_of_sale) : null,
    number,
    authorization_kind: fiscal ? h.authorization_kind || null : null,
    authorization_code: fiscal ? h.authorization_code.trim() || null : null,
    receiver_tax_id: h.receiver_tax_id.trim() || null,
    issued_on: h.issued_on,
    due_on: h.due_on || null,
    ...amounts,
  };
  let lines: InvoicePayload["lines"] = null;
  if (c.lines.length > 0 || c.removedLines > 0) {
    lines = [];
    for (const [i, l] of draft.lines.entries()) {
      const qty = readNumber(l.billed_quantity);
      const price = readNumber(l.unit_price);
      if (!l.raw_name.trim()) return { ok: false, message: `Línea ${i + 1}: escribí qué es.` };
      if (qty === null || qty <= 0)
        return { ok: false, message: `Línea ${i + 1}: la cantidad tiene que ser mayor que cero.` };
      if (price === null) return { ok: false, message: `Línea ${i + 1}: escribí el precio.` };
      lines.push({
        line_class: l.line_class,
        purchase_product_id: l.purchase_product_id,
        purchase_order_line_id: l.purchase_order_line_id,
        raw_name: l.raw_name.trim(),
        supplier_sku: l.supplier_sku.trim() || null,
        units: readNumber(l.units),
        billed_quantity: qty,
        list_price: l.list_price,
        bonus1_pct: l.bonus1_pct,
        bonus2_pct: l.bonus2_pct,
        bonus_per_unit_amount: l.bonus_per_unit_amount,
        unit_price: price,
        vat_rate: l.vat_rate === "" ? null : Number(l.vat_rate),
        is_exempt: l.is_exempt,
        internal_tax_amount: readNumber(l.internal_tax_amount) ?? 0,
        line_amount: lineAmount(qty, price),
      });
    }
  }
  let taxes: InvoicePayload["taxes"] = null;
  if (c.taxes.length > 0 || c.removedTaxes > 0) {
    taxes = [];
    for (const t of draft.taxes) {
      const amount = readNumber(t.tax_amount);
      if (amount === null || amount <= 0)
        return { ok: false, message: "Cada percepción lleva su importe, mayor que cero." };
      taxes.push({
        tax_kind: t.tax_kind,
        jurisdiction: t.jurisdiction.trim() || null,
        rate_pct: readNumber(t.rate_pct),
        tax_amount: amount,
      });
    }
  }
  return { ok: true, payload: { header, lines, taxes } };
}

// La suma de las líneas (sin IVA), a centavos: se compara con el neto del pie.
export function linesNet(lines: LineDraft[]): number {
  const total = lines.reduce(
    (s, l) => s + (lineAmount(readNumber(l.billed_quantity), readNumber(l.unit_price)) ?? 0),
    0,
  );
  return Math.round(total * 100) / 100;
}

// La cuenta del pie con números (vacío vale cero). null si algún dato no se entiende.
export function headerAmounts(h: HeaderDraft): InvoiceAmounts | null {
  const out: InvoiceAmounts = {
    net_amount: 0,
    exempt_amount: 0,
    vat_amount: 0,
    internal_tax_amount: 0,
    perception_amount: 0,
    discount_amount: 0,
    rounding_amount: 0,
    total_amount: 0,
  };
  for (const { field } of AMOUNT_FIELDS) {
    const text = h[field];
    const n = readNumber(text, field === "rounding_amount");
    if (n === null && text.trim() !== "") return null;
    out[field] = n ?? 0;
  }
  return out;
}

// Una fila del último control, para la ficha.
export type CheckRow = {
  kind: InvoiceCheckKind;
  lineId: string | null;
  passed: boolean;
  explanation: string;
  expected: number | null;
  actual: number | null;
};

// Lo que falló, en palabras, para la columna del listado.
export function failedLabel(kinds: string[]): string {
  const known = kinds.filter((k): k is InvoiceCheckKind => k in CHECK_LABELS);
  if (known.length === 0) return "—";
  return known.map((k) => CHECK_LABELS[k]).join(" · ");
}

// La diferencia de precio contra la lista, en pesos: lo facturado de más en las líneas que no pasaron (la misma regla
// que el control: lo cobrado de menos no compensa). Cuántas líneas no tienen lista para comparar: si hay alguna, no se
// puede decir «igual a la lista» (métricas confiables). value es null si el control no comparó ningún precio.
export function priceDifference(
  checks: CheckRow[],
  quantities: Map<string, number>,
): { value: number | null; withoutList: number } {
  const lines = checks.filter((c) => c.kind === "price" && c.lineId !== null);
  const compared = lines.filter((c) => c.expected !== null && c.actual !== null);
  const withoutList = lines.length - compared.length;
  if (compared.length === 0) return { value: null, withoutList };
  const diff = compared
    .filter((c) => !c.passed)
    .reduce(
      (s, c) =>
        s +
        Math.max((c.actual ?? 0) - (c.expected ?? 0), 0) * (quantities.get(c.lineId ?? "") ?? 0),
      0,
    );
  return { value: Math.round(diff * 100) / 100, withoutList };
}

// El vencimiento de pago: vencido (crítico), en 7 días o menos (atención) o al día. Pagada o cancelada: no aplica.
export function dueState(
  dueOn: string,
  today: string,
  status: InvoiceStatus,
): "ok" | "warn" | "bad" | "none" {
  if (status === "paid" || status === "cancelled") return "none";
  if (dueOn < today) return "bad";
  const limit = new Date(`${today}T12:00:00Z`);
  limit.setUTCDate(limit.getUTCDate() + 7);
  return dueOn <= limit.toISOString().slice(0, 10) ? "warn" : "ok";
}

// Una fecha (aaaa-mm-dd) como se lee acá (dd/mm/aaaa), sin depender de la zona horaria.
export function shortDate(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
}

// El alta: proveedor, las OC recibidas que cubre (ninguna para un flete o un servicio: P4) y los datos del papel. El local
// (oculto) y las OC los valida la acción; el CUIT del emisor lo pone la acción: es el del proveedor.
// El comprobante llega como uno de los botones (class_pick) o, con «Otro», como el elegido en el desplegable
// (other_class); un formulario de antes puede mandar invoice_class directo. El CAE ya no se pide acá (ADR-0070): se
// completa en la ficha y la base lo exige al controlar. Si viene, tiene que tener sus 14 números.
const INVOICE_CLASS_VALUES = [
  "invoice_a",
  "invoice_b",
  "invoice_c",
  "invoice_remito_a",
  "non_fiscal",
  "handwritten_note",
] as const;
export const newInvoiceSchema = z.preprocess(
  (raw) => {
    if (!raw || typeof raw !== "object") return raw;
    const v = raw as Record<string, unknown>;
    const pick = typeof v.class_pick === "string" ? v.class_pick : undefined;
    const invoice_class =
      pick === "other" ? v.other_class : pick !== undefined ? pick : v.invoice_class;
    return { ...v, invoice_class };
  },
  z
    .object({
      supplierId: z.string().uuid("Elegí el proveedor."),
      class_pick: z.string().optional(),
      other_class: z.string().optional(),
      invoice_class: z.enum(INVOICE_CLASS_VALUES, { message: "Elegí la clase de comprobante." }),
      // En un comprobante X o una nota a mano no se piden: pueden no venir.
      point_of_sale: z.string().trim().default(""),
      number: z
        .string()
        .trim()
        .regex(/^\d{1,8}$/, "El número va de 1 a 99999999, sin guiones."),
      issued_on: isoDate,
      authorization_kind: z.enum(["cae", "cai", "caea"]).default("cae"),
      authorization_code: z.string().trim().default(""),
    })
    .superRefine((v, ctx) => {
      if (Number(v.number) < 1)
        ctx.addIssue({
          code: "custom",
          path: ["number"],
          message: "El número va de 1 a 99999999.",
        });
      if (!isFiscal(v.invoice_class)) return;
      if (!/^\d{1,5}$/.test(v.point_of_sale) || Number(v.point_of_sale) < 1)
        ctx.addIssue({
          code: "custom",
          path: ["point_of_sale"],
          message: "El punto de venta va de 1 a 99999.",
        });
      if (v.authorization_code && !/^\d{14}$/.test(v.authorization_code))
        ctx.addIssue({
          code: "custom",
          path: ["authorization_code"],
          message: "La autorización (CAE, CAI o CAEA) tiene 14 números.",
        });
    }),
);

// Una nota de crédito, débito o descuento. El total es opcional: sin él, vale el importe. La factura (oculta) la valida
// la acción.
export const noteSchema = z
  .object({
    note_kind: z.enum(["credit", "debit", "discount"], { message: "Elegí qué es." }),
    number: z.string().trim().max(40, "Hasta 40 caracteres."),
    issued_on: isoDate,
    net_amount: z.string().trim(),
    total_amount: z.string().trim(),
    reason: z.string().trim().min(3, "Escribí el motivo.").max(500, "Hasta 500 caracteres."),
  })
  .superRefine((v, ctx) => {
    const net = readNumber(v.net_amount);
    if (net === null || net <= 0)
      ctx.addIssue({
        code: "custom",
        path: ["net_amount"],
        message: "Escribí el importe, mayor que cero.",
      });
    const total = v.total_amount === "" ? net : readNumber(v.total_amount);
    if (total === null || (net !== null && total < net))
      ctx.addIssue({
        code: "custom",
        path: ["total_amount"],
        message: "El total no puede ser menor que el importe sin IVA.",
      });
  });
