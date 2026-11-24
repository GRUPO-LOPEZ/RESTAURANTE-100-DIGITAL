import { describe, expect, it } from "vitest";

import {
  countUserChanges,
  hasRole,
  rolePlaces,
  userChanges,
  userPayload,
  type UserDraft,
} from "@/lib/user-sheet";

// Ficha de la persona en una pantalla (ADR-0062): qué cambió y qué viaja a la base.
const saved: UserDraft = {
  fields: { first_name: "Carla", last_name: "Chef", job_title: "Chef", area_id: "" },
  roles: [
    {
      key: "a1",
      assignmentId: "a1",
      roleCode: "cook",
      roleName: "Cocinero",
      place: "",
      placeLabel: "Local Demo Pastas Centro",
      removed: false,
    },
  ],
};

describe("ficha de la persona", () => {
  it("sin cambios no manda nada", () => {
    expect(countUserChanges(userChanges(saved, saved))).toBe(0);
    expect(userPayload(saved, saved)).toEqual({});
  });

  it("manda solo los datos que cambiaron, sin espacios de más", () => {
    const draft = {
      ...saved,
      fields: { ...saved.fields, job_title: " Jefa de cocina ", first_name: "Carla " },
    };
    expect(countUserChanges(userChanges(saved, draft))).toBe(1);
    expect(userPayload(saved, draft)).toEqual({ profile: { job_title: "Jefa de cocina" } });
  });

  it("quita y da roles; uno agregado y quitado antes de guardar no cuenta", () => {
    const role = saved.roles[0]!;
    const draft: UserDraft = {
      ...saved,
      roles: [
        { ...role, removed: true },
        {
          ...role,
          key: "n1",
          assignmentId: null,
          roleCode: "head_chef",
          place: "restaurant:g:b:r",
          removed: false,
        },
        { ...role, key: "n2", assignmentId: null, removed: true },
      ],
    };
    expect(countUserChanges(userChanges(saved, draft))).toBe(2);
    expect(userPayload(saved, draft)).toEqual({
      roles_remove: ["a1"],
      roles_add: [{ role_code: "head_chef", place: "restaurant:g:b:r" }],
    });
  });

  it("no se agrega dos veces el mismo rol en el mismo lugar", () => {
    expect(hasRole(saved, "cook", "Local Demo Pastas Centro")).toBe(true);
    expect(hasRole(saved, "cook", "Local Demo Pastas Norte")).toBe(false);
  });

  it("dice dónde usa sus roles", () => {
    expect(rolePlaces([])).toBe("Sin roles");
    expect(rolePlaces([{ scope_type: "group", scope_name: "Grupo" }])).toBe("En todo el grupo");
    expect(
      rolePlaces([
        { scope_type: "brand", scope_name: "Ragú" },
        { scope_type: "restaurant", scope_name: "Ragú Leloir" },
        { scope_type: "restaurant", scope_name: "Ragú Leloir" },
      ]),
    ).toBe("En 1 marca y 1 local");
  });
});
