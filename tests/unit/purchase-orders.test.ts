import { describe, expect, it } from "vitest";

import {
  daysLong,
  daysShort,
  estimatedKg,
  orderSchema,
  PO_STATUS,
  qtyText,
} from "@/lib/purchase-orders";

// Órdenes de compra (ADR-0053): las reglas de la pantalla. La base hace las mismas cuentas en el mensaje
// (purchasing.order_message) y las prueba pgTAP (340).
describe("kg estimados de lo que va por peso", () => {
  it("8 piezas de 4,5 kg ≈ 36 kg", () => {
    expect(estimatedKg(8, 1, 4500, "g")).toBe(36);
  });
  it("con unidades por envase", () => {
    expect(estimatedKg(2, 3, 1500, "g")).toBe(9);
  });
  it("sin peso estimado o sin cantidad, no se inventa", () => {
    expect(estimatedKg(8, 1, null, "g")).toBeNull();
    expect(estimatedKg(0, 1, 4500, "g")).toBeNull();
  });
});

describe("días del proveedor", () => {
  it("cortos y largos, en orden", () => {
    expect(daysShort([6, 2, 4])).toBe("Ma, Ju y Sá");
    expect(daysLong([2, 4, 6])).toBe("martes, jueves y sábado");
  });
  it("sin días lo dice", () => {
    expect(daysShort([])).toBe("Sin días");
    expect(daysLong(null)).toBe("sin días cargados");
  });
});

describe("estados y cantidades", () => {
  it("cada estado tiene su palabra", () => {
    expect(PO_STATUS.sent.label).toBe("En cola de envío");
    expect(PO_STATUS.pending_approval.label).toBe("Espera aprobación");
  });
  it("cantidades con coma y sin ceros de más", () => {
    expect(qtyText(2)).toBe("2");
    expect(qtyText(1.5)).toBe("1,5");
  });
});

describe("el esquema de la orden", () => {
  const base = {
    restaurant_id: "00000000-0000-4000-8000-000000000201",
    supplier_id: "00000000-0000-4000-8000-000000000903",
    lines: [{ purchase_product_id: "00000000-0000-4000-8000-000000000001", quantity: 2 }],
  };
  it("acepta una orden con un artículo", () => {
    expect(orderSchema.safeParse(base).success).toBe(true);
  });
  // Decisión 3 de Soy (ADR-0069): solo artículos del proveedor; una materia prima suelta ya no se pide.
  it("rechaza una materia prima sin nombre de factura", () => {
    expect(
      orderSchema.safeParse({
        ...base,
        lines: [{ ingredient_id: "00000000-0000-4000-8000-000000000819", quantity: 500 }],
      }).success,
    ).toBe(false);
  });
  it("rechaza una orden sin líneas, una cantidad en cero y una línea con las dos cosas", () => {
    expect(orderSchema.safeParse({ ...base, lines: [] }).success).toBe(false);
    expect(
      orderSchema.safeParse({ ...base, lines: [{ ...base.lines[0], quantity: 0 }] }).success,
    ).toBe(false);
    expect(
      orderSchema.safeParse({
        ...base,
        lines: [{ ...base.lines[0], ingredient_id: "00000000-0000-4000-8000-000000000819" }],
      }).success,
    ).toBe(false);
  });
});
