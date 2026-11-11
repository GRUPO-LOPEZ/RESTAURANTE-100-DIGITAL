import { describe, expect, it } from "vitest";

import {
  buildChanges,
  cellKey,
  cellValue,
  pendingLabel,
  sensitiveGrants,
  toggleCell,
} from "@/lib/permission-matrix";

// Borrador de la matriz de permisos (ADR-0039).
const original = new Set([cellKey("cook", "recipes.view"), cellKey("auditor", "audit.view")]);

describe("toggleCell", () => {
  it("un clic suma la celda al borrador con el valor contrario", () => {
    const draft = toggleCell(new Map(), original, cellKey("cook", "recipes.view"));
    expect(draft.get(cellKey("cook", "recipes.view"))).toBe(false);
    expect(draft.size).toBe(1);
  });

  it("volver al valor original la saca del borrador (el contador baja)", () => {
    const once = toggleCell(new Map(), original, cellKey("cook", "audit.view"));
    expect(once.size).toBe(1);
    const twice = toggleCell(once, original, cellKey("cook", "audit.view"));
    expect(twice.size).toBe(0);
  });

  it("no cambia el borrador que recibe", () => {
    const draft = new Map<string, boolean>();
    toggleCell(draft, original, cellKey("cook", "audit.view"));
    expect(draft.size).toBe(0);
  });
});

describe("cellValue", () => {
  it("muestra el borrador si la celda cambió y, si no, la base", () => {
    const draft = toggleCell(new Map(), original, cellKey("cook", "recipes.view"));
    expect(cellValue(draft, original, cellKey("cook", "recipes.view"))).toBe(false);
    expect(cellValue(draft, original, cellKey("auditor", "audit.view"))).toBe(true);
    expect(cellValue(draft, original, cellKey("cook", "audit.view"))).toBe(false);
  });
});

describe("buildChanges", () => {
  it("arma el lote con el id de cada rol", () => {
    const draft = toggleCell(new Map(), original, cellKey("cook", "audit.view"));
    const changes = buildChanges(
      draft,
      new Map([["cook", "11111111-1111-4111-8111-111111111111"]]),
    );
    expect(changes).toEqual([
      {
        role_id: "11111111-1111-4111-8111-111111111111",
        permission_code: "audit.view",
        granted: true,
      },
    ]);
  });

  it("deja afuera un rol que no conoce", () => {
    const draft = toggleCell(new Map(), original, cellKey("otro", "audit.view"));
    expect(buildChanges(draft, new Map())).toEqual([]);
  });
});

describe("sensitiveGrants", () => {
  it("cuenta solo los permisos sensibles que se dan, no los que se quitan", () => {
    let draft = toggleCell(new Map(), original, cellKey("cook", "audit.view"));
    draft = toggleCell(draft, original, cellKey("auditor", "audit.view"));
    draft = toggleCell(draft, original, cellKey("cook", "users.view"));
    expect(sensitiveGrants(draft, new Set(["audit.view"]))).toBe(1);
  });
});

describe("pendingLabel", () => {
  it("dice el número en singular y en plural", () => {
    expect(pendingLabel(1)).toBe("1 cambio sin guardar");
    expect(pendingLabel(3)).toBe("3 cambios sin guardar");
  });
});
