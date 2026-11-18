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
  cancelled: { label: "Cancelada", status: "none" },
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
