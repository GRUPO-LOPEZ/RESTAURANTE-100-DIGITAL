// Panel izquierdo de los listados (criterio 7 de Soy, ADR-0068): el orden de los grupos, el elegido siempre a la vista y
// el «Todos».
import { describe, expect, it } from "vitest";

import { panelGroups, sumCounts } from "@/lib/group-counts";

const g = (id: string, name: string, count: number) => ({ id, name, count });

describe("panelGroups", () => {
  it("ordena como se lee en castellano, sin importar mayúsculas ni tildes", () => {
    const out = panelGroups([
      g("1", "Verdulería Demo", 4),
      g("2", "almacén", 1),
      g("3", "Ñoquis SA", 1),
      g("4", "Nonno", 2),
    ]);
    expect(out.map((x) => x.name)).toEqual(["almacén", "Nonno", "Ñoquis SA", "Verdulería Demo"]);
  });
  it("el elegido aparece aunque con los filtros de ahora no tenga nada (con 0)", () => {
    const out = panelGroups([g("1", "Lácteos Demo", 2)], { id: "9", name: "Frigorífico Demo" });
    expect(out).toEqual([g("9", "Frigorífico Demo", 0), g("1", "Lácteos Demo", 2)]);
  });
  it("si el elegido ya está, no se repite", () => {
    const out = panelGroups([g("1", "Lácteos Demo", 2)], { id: "1", name: "Lácteos Demo" });
    expect(out).toHaveLength(1);
  });
  it("no cambia la lista que recibe", () => {
    const items = [g("2", "B", 1), g("1", "A", 1)];
    panelGroups(items);
    expect(items.map((x) => x.id)).toEqual(["2", "1"]);
  });
});

describe("sumCounts", () => {
  it("«Todos» es la suma cuando cada registro está en un solo grupo", () => {
    expect(sumCounts([g("1", "A", 4), g("2", "B", 5)])).toBe(9);
  });
  it("sin grupos, 0 (un valor real, no un «Sin datos»)", () => {
    expect(sumCounts([])).toBe(0);
  });
});
