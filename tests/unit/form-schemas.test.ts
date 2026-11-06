// Esquemas de los formularios (ADR-0016): los mismos que usan el navegador y el servidor.
import { describe, expect, it } from "vitest";

import { zodResolver } from "@/lib/forms/resolver";
import { fieldErrors, formValues, schemas } from "@/lib/forms/schemas";

function errorsOf(name: keyof typeof schemas, values: Record<string, string>) {
  const parsed = schemas[name].safeParse(values);
  return parsed.success ? {} : fieldErrors(parsed.error);
}

describe("esquemas de formularios", () => {
  it("el motivo es obligatorio y tiene hasta 500 caracteres", () => {
    expect(errorsOf("reason", { reason: "   " })).toEqual({ reason: "Escribí el motivo." });
    expect(errorsOf("reason", { reason: "x".repeat(501) })).toEqual({
      reason: "El motivo tiene hasta 500 caracteres.",
    });
    expect(errorsOf("reason", { reason: "Licencia" })).toEqual({});
  });

  it("el correo se revisa y se guarda en minúsculas", () => {
    expect(errorsOf("recover", { email: "no-es-un-correo" })).toEqual({
      email: "Revisá el correo.",
    });
    const parsed = schemas.recover.safeParse({ email: "  Persona@Ejemplo.TEST " });
    expect(parsed.success && parsed.data.email).toBe("persona@ejemplo.test");
  });

  it("la contraseña nueva: 12 caracteres, letras y números, repetida igual", () => {
    expect(errorsOf("newPassword", { password: "corta1", repeat: "corta1" })).toEqual({
      password: "La contraseña tiene que tener al menos 12 caracteres.",
    });
    expect(
      errorsOf("newPassword", { password: "sololetrasmuchas", repeat: "sololetrasmuchas" }),
    ).toEqual({
      password: "La contraseña tiene que tener números.",
    });
    expect(
      errorsOf("newPassword", { password: "Clave-Larga-2026", repeat: "Otra-Clave-2026" }),
    ).toEqual({
      repeat: "Las dos contraseñas no coinciden.",
    });
    expect(
      errorsOf("newPassword", { password: "Clave-Larga-2026", repeat: "Clave-Larga-2026" }),
    ).toEqual({});
  });

  it("cambiar la contraseña pide la actual y que la nueva sea otra", () => {
    expect(
      errorsOf("changePassword", {
        current: "",
        password: "Clave-Larga-2026",
        repeat: "Clave-Larga-2026",
      }),
    ).toEqual({ current: "Escribí tu contraseña actual." });
    expect(
      errorsOf("changePassword", {
        current: "Clave-Larga-2026",
        password: "Clave-Larga-2026",
        repeat: "Clave-Larga-2026",
      }),
    ).toEqual({ password: "La contraseña nueva tiene que ser otra." });
  });

  it("el código de doble verificación tiene 6 números", () => {
    expect(errorsOf("code", { code: "12a456" })).toEqual({ code: "El código tiene 6 números." });
    expect(errorsOf("code", { code: " 123456 " })).toEqual({});
  });

  it("dar un rol pide el rol, el lugar y el motivo, cada uno con su error", () => {
    expect(errorsOf("assignRole", { role: "", place: "", reason: "" })).toEqual({
      role: "Elegí el rol.",
      place: "Elegí el lugar.",
      reason: "Escribí el motivo.",
    });
  });

  it("formValues deja solo los textos del formulario", () => {
    const data = new FormData();
    data.set("reason", "Motivo");
    data.set("archivo", new Blob(["x"]));
    expect(formValues(data)).toEqual({ reason: "Motivo" });
  });
});

describe("adaptador de Zod para React Hook Form", () => {
  const resolve = zodResolver(schemas.reason);
  const options = { fields: {}, shouldUseNativeValidation: false } as const;

  it("devuelve un error por campo, con el mensaje en español", async () => {
    const result = await resolve({ reason: "" }, undefined, options);
    expect(result.values).toEqual({});
    expect(result.errors).toEqual({ reason: { type: "validate", message: "Escribí el motivo." } });
  });

  it("sin errores, deja pasar los valores", async () => {
    const result = await resolve({ reason: "Licencia" }, undefined, options);
    expect(result.errors).toEqual({});
    expect(result.values).toEqual({ reason: "Licencia" });
  });
});
