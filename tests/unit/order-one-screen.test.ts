// La orden de compra en una pantalla (ADR-0069): el total estimado, el aviso del pedido mínimo y si hoy es día de pedido.
import { describe, expect, it } from "vitest";

import { minimumNotice, orderDayLabel, orderEstimate } from "@/lib/purchase-orders";

describe("orderEstimate", () => {
  it("suma cantidad por precio de lista", () => {
    expect(
      orderEstimate(
        [
          { quantity: 2, price: 39400 },
          { quantity: 4, price: 21400 },
        ],
        true,
      ),
    ).toEqual({ total: 164400, missing: 0 });
  });
  it("lo que no tiene precio en la lista no suma, y se dice cuántos", () => {
    expect(
      orderEstimate(
        [
          { quantity: 2, price: 100.5 },
          { quantity: 1, price: null },
        ],
        true,
      ),
    ).toEqual({ total: 201, missing: 1 });
  });
  it("las cantidades en cero no cuentan", () => {
    expect(orderEstimate([{ quantity: 0, price: null }], true)).toEqual({ total: 0, missing: 0 });
  });
  it("quien no ve precios no tiene total (nunca un $ 0 que confunda)", () => {
    expect(orderEstimate([{ quantity: 2, price: null }], false)).toBeNull();
  });
});

describe("minimumNotice", () => {
  it("sin mínimo cargado, nada", () => {
    expect(minimumNotice(1000, null)).toBeNull();
    expect(minimumNotice(1000, 0)).toBeNull();
  });
  it("avisa cuánto falta", () => {
    expect(minimumNotice(68000, 80000)).toEqual({ reached: false, short: 12000 });
  });
  it("lo alcanza justo o lo supera", () => {
    expect(minimumNotice(80000, 80000)).toEqual({ reached: true, short: 0 });
    expect(minimumNotice(164400, 80000)).toEqual({ reached: true, short: 0 });
  });
});

describe("orderDayLabel", () => {
  // 2026-11-26 es jueves (4).
  const THURSDAY = "2026-11-26";
  it("hoy pide", () => {
    expect(orderDayLabel([1, 4], THURSDAY)).toBe("Hoy pide");
  });
  it("el próximo día de pedido, aunque sea la semana que viene", () => {
    expect(orderDayLabel([5], THURSDAY)).toBe("Próximo: viernes");
    expect(orderDayLabel([2], THURSDAY)).toBe("Próximo: martes");
  });
  it("el domingo es el 7", () => {
    expect(orderDayLabel([7], "2026-11-29")).toBe("Hoy pide");
    expect(orderDayLabel([1], "2026-11-29")).toBe("Próximo: lunes");
  });
  it("todos los días o ninguno", () => {
    expect(orderDayLabel([1, 2, 3, 4, 5, 6, 7], THURSDAY)).toBe("Pide todos los días");
    expect(orderDayLabel([], THURSDAY)).toBe("Sin días de pedido");
    expect(orderDayLabel(null, THURSDAY)).toBe("Sin días de pedido");
  });
});
