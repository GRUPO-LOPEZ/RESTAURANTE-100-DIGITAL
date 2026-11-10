import { describe, expect, it } from "vitest";

import { noticeLink } from "@/lib/notices";

const ING = "/materias-primas/00000000-0000-4000-8000-000000000801";

describe("a dónde lleva un aviso", () => {
  it("un aviso de rendimiento abre la ficha en la pestaña Rendimientos", () => {
    expect(noticeLink("yield_deviation", ING)).toBe(`${ING}?seccion=rendimientos`);
  });

  it("los demás avisos llevan a donde dice la base", () => {
    expect(noticeLink("recipe_changed", "/recetas/abc")).toBe("/recetas/abc");
    expect(noticeLink("recipe_cost_changed", ING)).toBe(ING);
    // Si ya trae parámetros, no se tocan.
    expect(noticeLink("yield_deviation", `${ING}?x=1`)).toBe(`${ING}?x=1`);
  });

  it("nunca lleva fuera del sistema", () => {
    expect(noticeLink("yield_deviation", null)).toBeNull();
    expect(noticeLink("yield_deviation", "https://otro.test")).toBeNull();
    expect(noticeLink("yield_deviation", "//otro.test/materias-primas")).toBeNull();
    expect(noticeLink("recipe_changed", "/recetas/<script>")).toBeNull();
  });
});
