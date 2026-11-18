import { z } from "zod";

import { parseAmount } from "@/lib/money";

// Recepción (Fase 3, Prompt 4, ADR-0056): reglas de la pantalla, sin acceso a la base. Se prueban con Vitest. La base
// vuelve a controlar todo al cerrar (purchasing.close_receipt): las fotos, cada renglón pendiente y el motivo.

export type PaperKind =
  "invoice" | "invoice_remito" | "remito" | "electronic_remito" | "non_fiscal" | "handwritten_note";

// Las seis clases de papel, con palabras de todos los días.
export const PAPER_KINDS: { value: PaperKind; label: string }[] = [
  { value: "remito", label: "Remito" },
  { value: "invoice", label: "Factura" },
  { value: "invoice_remito", label: "Factura-remito" },
  { value: "electronic_remito", label: "Remito electrónico" },
  { value: "non_fiscal", label: "Comprobante no fiscal" },
  { value: "handwritten_note", label: "Nota a mano" },
];
export const PAPER_LABEL: Record<PaperKind, string> = Object.fromEntries(
  PAPER_KINDS.map((p) => [p.value, p.label]),
) as Record<PaperKind, string>;

export type ReceiptIssue = "missing" | "extra" | "different_product" | "quality" | "expired";

// Las cinco observaciones de un renglón.
export const ISSUES: { value: ReceiptIssue; label: string }[] = [
  { value: "missing", label: "Faltó" },
  { value: "extra", label: "De más" },
  { value: "different_product", label: "Otro producto" },
  { value: "quality", label: "Mala calidad" },
  { value: "expired", label: "Vencido" },
];
export const ISSUE_LABEL: Record<ReceiptIssue, string> = Object.fromEntries(
  ISSUES.map((i) => [i.value, i.label]),
) as Record<ReceiptIssue, string>;

export type ReceiptResult = "complete" | "partial" | "with_differences";
export const RESULT: Record<ReceiptResult, { label: string; status: "ok" | "warn" }> = {
  complete: { label: "Completa", status: "ok" },
  partial: { label: "Parcial", status: "warn" },
  with_differences: { label: "Con observaciones", status: "warn" },
};

// ---------------------------------------------------------------------------
// Decisiones por renglón y resumen
// ---------------------------------------------------------------------------
export type PendingLine = {
  purchaseOrderLineId: string;
  name: string;
  pending: number;
  billedByWeight: boolean;
};

// Lo que decidió quien recibe en un renglón de la OC. Sin decisión, el renglón falta.
export type LineDecision =
  | { ok: true; weight?: number; lot?: string }
  | {
      ok: false;
      issue: ReceiptIssue;
      received: number;
      weight?: number;
      lot?: string;
      note?: string;
      photoPaths?: string[];
    };

// Algo que llegó y no estaba en la OC (o, sin OC, lo que llegó).
export type ExtraLine = {
  key: string;
  name: string;
  received: number;
  weight?: number;
  lot?: string;
  note?: string;
  photoPaths?: string[];
};

// Si una observación es coherente con lo que se recibió (la misma regla que la base). Devuelve el error o null.
export function decisionError(decision: LineDecision, pending: number): string | null {
  if (decision.weight !== undefined && !(decision.weight > 0))
    return "El peso tiene que ser mayor que cero.";
  if (decision.ok) return null;
  const { issue, received } = decision;
  if (!Number.isFinite(received) || received < 0) return "Escribí cuánto llegó (0 si no llegó).";
  if (issue === "missing" && received >= pending)
    return "Marcaste que faltó: lo recibido tiene que ser menos que lo pedido.";
  if (issue !== "extra" && received > pending)
    return "Llegó más de lo pedido: marcalo como «De más».";
  if (issue === "extra" && received <= pending)
    return "Marcaste que vino de más: lo recibido tiene que ser más que lo pedido.";
  if (issue === "different_product" && received !== 0)
    return "Si mandaron otro producto, lo pedido no llegó: va 0. Cargá lo que vino en «Llegó algo que no estaba».";
  return null;
}

// Lo que se recibe de un renglón (OK = todo lo pendiente).
export function receivedQuantity(decision: LineDecision, pending: number): number {
  return decision.ok ? pending : decision.received;
}

export type ReceiptSummary = {
  decided: number;
  total: number;
  observed: number;
  // Con observaciones, el motivo es obligatorio.
  needsReason: boolean;
  // Cómo va a quedar: completa, parcial (queda algo pendiente) o con observaciones.
  result: ReceiptResult;
  // Los renglones sin decidir, para avisar cuáles faltan.
  undecided: string[];
};

export function receiptSummary(
  lines: PendingLine[],
  decisions: Record<string, LineDecision | undefined>,
  extras: ExtraLine[],
  hasOrder: boolean,
): ReceiptSummary {
  let decided = 0;
  let observed = 0;
  let incomplete = false;
  const undecided: string[] = [];
  for (const line of lines) {
    const d = decisions[line.purchaseOrderLineId];
    if (!d) {
      undecided.push(line.name);
      incomplete = true;
      continue;
    }
    decided += 1;
    if (!d.ok) observed += 1;
    if (receivedQuantity(d, line.pending) < line.pending) incomplete = true;
  }
  // Con OC, lo que no estaba es una observación («de más»); sin OC, es lo recibido.
  if (hasOrder) observed += extras.length;
  const result: ReceiptResult = !hasOrder
    ? "complete"
    : incomplete
      ? "partial"
      : observed > 0
        ? "with_differences"
        : "complete";
  return {
    decided,
    total: lines.length,
    observed,
    needsReason: observed > 0,
    result,
    undecided,
  };
}

// ---------------------------------------------------------------------------
// Lo que viaja a la base al cerrar
// ---------------------------------------------------------------------------
const PAPERS = [
  "invoice",
  "invoice_remito",
  "remito",
  "electronic_remito",
  "non_fiscal",
  "handwritten_note",
] as const;
const ISSUE_VALUES = ["missing", "extra", "different_product", "quality", "expired"] as const;
const PATH = /^[0-9a-f-]{36}\/receipts\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg$/;

const optionalText = (max: number) => z.string().trim().max(max).optional();

export const closeSchema = z.object({
  receipt_id: z.string().uuid(),
  paper_kind: z.enum(PAPERS, { message: "Elegí qué papel trajo el proveedor." }),
  paper_number: optionalText(40),
  cash_paid_amount: z
    .number()
    .positive("El importe en efectivo tiene que ser mayor que cero.")
    .max(1_000_000_000)
    .nullable(),
  reason: optionalText(500),
  lines: z
    .array(
      z.union([
        z.object({
          purchase_order_line_id: z.string().uuid(),
          ok: z.boolean(),
          issue: z.enum(ISSUE_VALUES).optional(),
          received_quantity: z.number().min(0).max(1_000_000).optional(),
          received_weight: z.number().positive().max(100_000).optional(),
          lot_code: optionalText(60),
          note: optionalText(300),
          photo_paths: z.array(z.string().regex(PATH)).max(5).optional(),
        }),
        z.object({
          name: z.string().trim().min(1, "Escribí qué llegó.").max(200),
          received_quantity: z.number().positive("Escribí cuánto llegó.").max(1_000_000),
          received_weight: z.number().positive().max(100_000).optional(),
          lot_code: optionalText(60),
          note: optionalText(300),
          photo_paths: z.array(z.string().regex(PATH)).max(5).optional(),
        }),
      ]),
    )
    .max(600),
});
export type ClosePayload = z.infer<typeof closeSchema>;

// Arma los renglones para la base, sin campos vacíos (la base rechaza claves que no conoce).
export function buildCloseLines(
  lines: PendingLine[],
  decisions: Record<string, LineDecision | undefined>,
  extras: ExtraLine[],
): ClosePayload["lines"] {
  const clean = (s: string | undefined) => (s && s.trim() ? s.trim() : undefined);
  const out: ClosePayload["lines"] = [];
  for (const line of lines) {
    const d = decisions[line.purchaseOrderLineId];
    if (!d) continue;
    out.push(
      d.ok
        ? {
            purchase_order_line_id: line.purchaseOrderLineId,
            ok: true,
            ...(d.weight !== undefined ? { received_weight: d.weight } : {}),
            ...(clean(d.lot) ? { lot_code: clean(d.lot) } : {}),
          }
        : {
            purchase_order_line_id: line.purchaseOrderLineId,
            ok: false,
            issue: d.issue,
            received_quantity: d.received,
            ...(d.weight !== undefined ? { received_weight: d.weight } : {}),
            ...(clean(d.lot) ? { lot_code: clean(d.lot) } : {}),
            ...(clean(d.note) ? { note: clean(d.note) } : {}),
            ...(d.photoPaths && d.photoPaths.length > 0 ? { photo_paths: d.photoPaths } : {}),
          },
    );
  }
  for (const e of extras) {
    out.push({
      name: e.name.trim(),
      received_quantity: e.received,
      ...(e.weight !== undefined ? { received_weight: e.weight } : {}),
      ...(clean(e.lot) ? { lot_code: clean(e.lot) } : {}),
      ...(clean(e.note) ? { note: clean(e.note) } : {}),
      ...(e.photoPaths && e.photoPaths.length > 0 ? { photo_paths: e.photoPaths } : {}),
    });
  }
  return out;
}

// Lo que se escribió en un campo de número: vacío es «nada» (null); lo que no es un número, NaN (para avisarlo). La
// lectura es la de toda la app (lib/money: «1.500» son mil quinientos, «2,5» dos y medio).
export function readNumber(text: string): number | null {
  if (!text.trim()) return null;
  return parseAmount(text) ?? Number.NaN;
}
