// Configuración del catálogo (ADR-0022): los formularios aceptan lo mismo que la base.
import { describe, expect, it } from "vitest";

import { fieldErrors, schemas } from "@/lib/forms/schemas";

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

describe("formulario de categoría", () => {
  it("con nombre y motivo pasa; la madre es opcional", () => {
    expect(errorsOf("category", { name: "Lácteos", reason: "Categoría nueva" })).toEqual({});
    expect(
      errorsOf("category", {
        name: "Quesos",
        parent_id: "00000000-0000-4000-8000-000000000703",
        reason: "Subcategoría",
      }),
    ).toEqual({});
  });

  it("el nombre va de 1 a 80 caracteres, como en la base", () => {
    expect(errorsOf("category", { name: "  ", reason: "Prueba" })).toEqual({
      name: "Escribí el nombre.",
    });
    expect(errorsOf("category", { name: "a".repeat(81), reason: "Prueba" })).toEqual({
      name: "Hasta 80 caracteres.",
    });
  });

  it("sin motivo no pasa", () => {
    expect(errorsOf("rename", { name: "Carnes", reason: "" })).toEqual({
      reason: "Escribí el motivo.",
    });
  });
});

describe("formulario de proceso", () => {
  it("el código va en mayúsculas, como en la base", () => {
    const parsed = schemas.yieldProcess.safeParse({
      code: "blanqueado",
      name: "Blanqueado",
      reason: "Proceso nuevo",
    });
    expect(parsed.success && parsed.data.code).toBe("BLANQUEADO");
    expect(errorsOf("yieldProcess", { code: "B", name: "Blanqueado", reason: "Prueba" })).toEqual({
      code: "Mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).",
    });
  });
});
