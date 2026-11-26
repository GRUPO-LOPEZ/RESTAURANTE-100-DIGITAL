// Los 4 indicadores de la ficha de una OC (criterios de Soy, ADR-0068), con la regla de las métricas confiables: antes de
// mandarla, lo recibido no se mide; nunca un estado positivo sin datos.
import { describe, expect, it } from "vitest";

import { orderIndicators, type PoStatus } from "@/lib/purchase-orders";

const TODAY = "2026-11-26";
const day = (iso: string) => iso.split("-").reverse().join("/");
const line = (quantity: number, receivedQuantity = 0) => ({ quantity, receivedQuantity });
const order = (
  status: PoStatus,
  lines = [line(2), line(3)],
  expectedOn = "2026-11-27",
  events: { kind: string }[] = [],
) => ({ status, lines, expectedOn, events });
const byKey = (o: ReturnType<typeof order>) =>
  Object.fromEntries(orderIndicators(o, TODAY, day).map((m) => [m.key, m]));

describe("orderIndicators", () => {
  it("son 4, sin precios, en el orden de la ficha", () => {
    const keys = orderIndicators(order("sent"), TODAY, day).map((m) => m.key);
    expect(keys).toEqual(["lines", "delivery", "received", "news"]);
  });

  it("un borrador no mide lo recibido ni las novedades (nunca «0 de 2»)", () => {
    const m = byKey(order("draft"));
    expect(m.received?.value).toBeNull();
    expect(m.received?.missingReason).toBe("Todavía no se mandó al proveedor.");
    expect(m.news?.value).toBeNull();
  });

  it("enviada y sin recibir: 0 de 2, «Sin recibir»", () => {
    const m = byKey(order("sent"));
    expect(m.received).toMatchObject({
      value: 0,
      total: 2,
      status: "none",
      statusLabel: "Sin recibir",
    });
    expect(m.news).toMatchObject({ value: 0, status: "ok", statusLabel: "Sin novedades" });
  });

  it("recibida en parte: cuenta los renglones completos", () => {
    const m = byKey(order("partially_received", [line(2, 2), line(3, 1)]));
    expect(m.received).toMatchObject({
      value: 1,
      total: 2,
      status: "warn",
      statusLabel: "En parte",
    });
  });

  it("recibida entera: «Completa» y la entrega «Llegó»", () => {
    const m = byKey(order("received", [line(2, 2), line(3, 3)]));
    expect(m.received).toMatchObject({ value: 2, status: "ok", statusLabel: "Completa" });
    expect(m.delivery).toMatchObject({ value: "27/11/2026", status: "ok", statusLabel: "Llegó" });
  });

  it("esperada antes de hoy y sin llegar: «Atrasada»", () => {
    const m = byKey(order("sent", undefined, "2026-11-20"));
    expect(m.delivery).toMatchObject({
      value: "20/11/2026",
      status: "warn",
      statusLabel: "Atrasada",
    });
  });

  it("las novedades no cuentan la cancelación", () => {
    const m = byKey(
      order("with_news", undefined, undefined, [{ kind: "shortage" }, { kind: "cancelled" }]),
    );
    expect(m.news).toMatchObject({ value: 1, status: "warn", statusLabel: "Una novedad" });
  });

  it("cancelada: la entrega lo dice y lo recibido no se mide", () => {
    const m = byKey(order("cancelled"));
    expect(m.delivery).toMatchObject({ status: "none", statusLabel: "Cancelada" });
    expect(m.received?.value).toBeNull();
    expect(m.received?.missingReason).toBe("La orden se canceló.");
  });
});
