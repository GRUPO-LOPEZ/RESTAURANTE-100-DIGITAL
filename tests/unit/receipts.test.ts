// Recepción (Fase 3, Prompt 4, ADR-0056): la cuenta del resumen, la coherencia de cada observación, lo que viaja a la
// base y el tamaño de la foto achicada. La base vuelve a controlar todo al cerrar (pgTAP 370 y 371).
import { describe, expect, it } from "vitest";

import { fitSize } from "@/lib/photos";
import {
  buildCloseLines,
  closeSchema,
  decisionError,
  readNumber,
  receiptSummary,
  type ExtraLine,
  type LineDecision,
  type PendingLine,
} from "@/lib/receipts";

const A = "00000000-0000-4000-8000-00000000000a";
const B = "00000000-0000-4000-8000-00000000000b";
const C = "00000000-0000-4000-8000-00000000000c";
const lines: PendingLine[] = [
  { purchaseOrderLineId: A, name: "Tomate", pending: 2, billedByWeight: false },
  { purchaseOrderLineId: B, name: "Cebolla", pending: 3, billedByWeight: false },
  { purchaseOrderLineId: C, name: "Carne", pending: 1, billedByWeight: true },
];

describe("el resumen de la recepción", () => {
  it("cuenta el avance y dice qué falta decidir", () => {
    const s = receiptSummary(lines, { [A]: { ok: true } }, [], true);
    expect(s.decided).toBe(1);
    expect(s.total).toBe(3);
    expect(s.undecided).toEqual(["Cebolla", "Carne"]);
    expect(s.result).toBe("partial");
  });

  it("todo OK: completa y sin motivo", () => {
    const all = { [A]: { ok: true }, [B]: { ok: true }, [C]: { ok: true } } as const;
    const s = receiptSummary(lines, all, [], true);
    expect(s).toMatchObject({ observed: 0, needsReason: false, result: "complete" });
  });

  it("con un faltante: parcial, y pide el motivo", () => {
    const d: Record<string, LineDecision> = {
      [A]: { ok: true },
      [B]: { ok: false, issue: "missing", received: 1 },
      [C]: { ok: true },
    };
    expect(receiptSummary(lines, d, [], true)).toMatchObject({
      observed: 1,
      needsReason: true,
      result: "partial",
    });
  });

  it("todo recibido pero con mala calidad: con observaciones", () => {
    const d: Record<string, LineDecision> = {
      [A]: { ok: true },
      [B]: { ok: false, issue: "quality", received: 3 },
      [C]: { ok: true },
    };
    expect(receiptSummary(lines, d, [], true).result).toBe("with_differences");
  });

  it("con OC, lo que no estaba es una observación; sin OC, es lo recibido", () => {
    const all = { [A]: { ok: true }, [B]: { ok: true }, [C]: { ok: true } } as const;
    const extra: ExtraLine[] = [{ key: "x", name: "Manteca", received: 1 }];
    expect(receiptSummary(lines, all, extra, true)).toMatchObject({
      observed: 1,
      needsReason: true,
      result: "with_differences",
    });
    expect(receiptSummary([], {}, extra, false)).toMatchObject({
      observed: 0,
      needsReason: false,
      result: "complete",
    });
  });
});

describe("la coherencia de una observación (la misma regla que la base)", () => {
  it("«faltó» con todo lo pedido no vale", () => {
    expect(decisionError({ ok: false, issue: "missing", received: 2 }, 2)).toMatch(/faltó/);
    expect(decisionError({ ok: false, issue: "missing", received: 1 }, 2)).toBeNull();
  });
  it("«de más» tiene que traer más", () => {
    expect(decisionError({ ok: false, issue: "extra", received: 2 }, 2)).toMatch(/de más/);
    expect(decisionError({ ok: false, issue: "extra", received: 3 }, 2)).toBeNull();
  });
  it("«otro producto» no recibe lo pedido", () => {
    expect(decisionError({ ok: false, issue: "different_product", received: 1 }, 2)).toMatch(
      /otro producto/,
    );
    expect(decisionError({ ok: false, issue: "different_product", received: 0 }, 2)).toBeNull();
  });
  it("sin cantidad o con un peso inválido, avisa", () => {
    expect(decisionError({ ok: false, issue: "quality", received: Number.NaN }, 2)).toMatch(
      /cuánto llegó/,
    );
    expect(decisionError({ ok: true, weight: Number.NaN }, 1)).toMatch(/peso/);
    expect(decisionError({ ok: true, weight: 6.3 }, 1)).toBeNull();
  });
});

describe("lo que viaja a la base al cerrar", () => {
  it("sin campos vacíos, y lo que no estaba con su nombre", () => {
    const d: Record<string, LineDecision> = {
      [A]: { ok: true, lot: "  " },
      [B]: { ok: false, issue: "missing", received: 1, note: "Uno solo", lot: "L-1" },
      [C]: { ok: true, weight: 6.3 },
    };
    const out = buildCloseLines(lines, d, [{ key: "x", name: " Manteca ", received: 1 }]);
    expect(out).toEqual([
      { purchase_order_line_id: A, ok: true },
      {
        purchase_order_line_id: B,
        ok: false,
        issue: "missing",
        received_quantity: 1,
        lot_code: "L-1",
        note: "Uno solo",
      },
      { purchase_order_line_id: C, ok: true, received_weight: 6.3 },
      { name: "Manteca", received_quantity: 1 },
    ]);
    const payload = {
      receipt_id: A,
      paper_kind: "remito",
      cash_paid_amount: null,
      lines: out,
    };
    expect(closeSchema.safeParse(payload).success).toBe(true);
  });

  it("el esquema rechaza un papel que no existe, efectivo negativo y fotos de otra carpeta", () => {
    const base = { receipt_id: A, paper_kind: "remito", cash_paid_amount: null, lines: [] };
    expect(closeSchema.safeParse({ ...base, paper_kind: "ticket" }).success).toBe(false);
    expect(closeSchema.safeParse({ ...base, cash_paid_amount: -1 }).success).toBe(false);
    expect(
      closeSchema.safeParse({
        ...base,
        lines: [
          {
            purchase_order_line_id: A,
            ok: false,
            issue: "quality",
            received_quantity: 1,
            photo_paths: [`${A}/price_lists/${B}/${C}.jpg`],
          },
        ],
      }).success,
    ).toBe(false);
  });
});

describe("los números que se escriben", () => {
  it("vacío es nada; «15.000» son quince mil; «2,5» dos y medio; lo demás, NaN", () => {
    expect(readNumber("  ")).toBeNull();
    expect(readNumber("15.000")).toBe(15000);
    expect(readNumber("2,5")).toBe(2.5);
    expect(readNumber("dos")).toBeNaN();
  });
});

describe("la foto achicada", () => {
  it("el lado más largo queda en 1.600 px, sin agrandar las chicas", () => {
    expect(fitSize(4000, 3000)).toEqual({ width: 1600, height: 1200 });
    expect(fitSize(3000, 4000)).toEqual({ width: 1200, height: 1600 });
    expect(fitSize(800, 600)).toEqual({ width: 800, height: 600 });
  });
});
