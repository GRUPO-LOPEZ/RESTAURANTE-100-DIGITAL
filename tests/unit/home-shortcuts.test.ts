// La regla única de lo que falta (decisión de Soy, 2026-11-13) y el estado de los accesos del Inicio (ADR-0045).
import { describe, expect, it } from "vitest";

import { shortcutStates, type ShortcutInput } from "@/lib/home-shortcuts";
import { missingState } from "@/lib/metrics";

describe("lo que falta de un total", () => {
  it("sin total no hay datos: nunca «Completo» ni 0 %", () => {
    expect(missingState(0, 0)).toEqual({ status: "none", label: "Sin datos" });
  });

  it("sin faltas está completo", () => {
    expect(missingState(0, 4)).toEqual({ status: "ok", label: "Completo" });
  });

  it("si falta más de la mitad, es crítico", () => {
    expect(missingState(4, 4)).toEqual({ status: "bad", label: "Faltan 4" });
    expect(missingState(3, 5)).toEqual({ status: "bad", label: "Faltan 3" });
    expect(missingState(1, 1)).toEqual({ status: "bad", label: "Falta 1" });
  });

  it("exactamente la mitad es atención, no crítico", () => {
    expect(missingState(2, 4)).toEqual({ status: "warn", label: "Faltan 2" });
    expect(missingState(1, 2)).toEqual({ status: "warn", label: "Falta 1" });
  });

  it("con faltas menores a la mitad, atención", () => {
    expect(missingState(1, 10)).toEqual({ status: "warn", label: "Falta 1" });
    expect(missingState(1200, 5000)).toEqual({ status: "warn", label: "Faltan 1.200" });
  });
});

const none: ShortcutInput = {
  approved: null,
  priced: null,
  costed: null,
  approvals: null,
  quality: null,
};

describe("los accesos del Inicio", () => {
  it("cada acceso dice su número con palabra y el estado de la regla única", () => {
    const s = shortcutStates({
      approved: { done: 0, total: 4 },
      priced: { done: 2, total: 3 },
      costed: { done: 2, total: 4 },
      approvals: { count: 3, capped: false },
      quality: { done: 10, total: 20 },
    });
    expect(s.recipes).toEqual({ status: "bad", label: "4 sin aprobar", text: null });
    expect(s.ingredients).toEqual({ status: "warn", label: "1 sin precio", text: null });
    expect(s.costs).toEqual({ status: "warn", label: "2 por corregir", text: null });
    expect(s.approvals).toEqual({ status: "info", label: "3 esperan tu decisión", text: null });
    expect(s.quality).toEqual({ status: "warn", label: "10 datos por completar", text: null });
    expect(s.reports).toEqual({ status: "neutral", label: "Informes", text: "Costos y recetario" });
  });

  it("sin faltas dicen «Al día» con su total", () => {
    const s = shortcutStates({
      approved: { done: 1, total: 1 },
      priced: { done: 3, total: 3 },
      costed: { done: 1, total: 1 },
      approvals: { count: 0, capped: false },
      quality: { done: 5, total: 5 },
    });
    expect(s.recipes).toEqual({ status: "ok", label: "Al día", text: "1 receta" });
    expect(s.ingredients).toEqual({ status: "ok", label: "Al día", text: "3 cargadas" });
    expect(s.costs.label).toBe("Al día");
    expect(s.approvals).toEqual({ status: "ok", label: "Al día", text: "Nada para decidir" });
    expect(s.quality.label).toBe("Al día");
  });

  it("sin nada que medir dicen «Sin datos», nunca «Al día»", () => {
    const empty = { done: 0, total: 0 };
    const s = shortcutStates({
      ...none,
      approved: empty,
      priced: empty,
      costed: empty,
      quality: empty,
    });
    for (const key of ["recipes", "ingredients", "costs", "quality"] as const) {
      expect(s[key].status).toBe("none");
      expect(s[key].label).toBe("Sin datos");
    }
  });

  it("si el rol no ve el número, el acceso va sin chip y nunca «Al día»", () => {
    const s = shortcutStates(none);
    for (const key of ["recipes", "ingredients", "costs", "approvals", "quality"] as const) {
      expect(s[key]).toEqual({ status: "neutral", label: "", text: null });
    }
  });

  it("si la lectura de aprobaciones llegó al tope, lo dice", () => {
    const s = shortcutStates({ ...none, approvals: { count: 50, capped: true } });
    expect(s.approvals.label).toBe("50 o más esperan tu decisión");
    expect(
      shortcutStates({ ...none, approvals: { count: 1, capped: false } }).approvals.label,
    ).toBe("1 espera tu decisión");
  });
});
