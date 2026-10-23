import { z } from "zod";

// Esquemas de los formularios (ADR-0016): los mismos en el navegador (React Hook Form, antes de
// enviar) y en las acciones de servidor (que validan igual, porque nunca se confía en la pantalla).
// Validan lo que escribe la persona; los ids ocultos los valida cada acción.

export const reasonField = z
  .string()
  .trim()
  .min(1, "Escribí el motivo.")
  .max(500, "El motivo tiene hasta 500 caracteres.");

const email = z
  .string()
  .trim()
  .toLowerCase()
  .min(1, "Escribí el correo.")
  .email("Revisá el correo.")
  .max(320, "El correo es demasiado largo.");

// Contraseña: mínimo 12 caracteres, con letras y números (P8; mismo criterio que Auth).
export const passwordRules = z
  .string()
  .min(12, "La contraseña tiene que tener al menos 12 caracteres.")
  .max(200, "La contraseña es demasiado larga.")
  .regex(/[A-Za-z]/, "La contraseña tiene que tener letras.")
  .regex(/[0-9]/, "La contraseña tiene que tener números.");

const code = z
  .string()
  .trim()
  .regex(/^[0-9]{6}$/, "El código tiene 6 números.");

const repeatMatches = (v: { password: string; repeat: string }) => v.password === v.repeat;
const repeatError = { message: "Las dos contraseñas no coinciden.", path: ["repeat"] };

export const schemas = {
  // Acciones con motivo: suspender, desactivar, liberar, quitar un rol, pedir revisión, publicar…
  reason: z.object({ reason: reasonField }),
  assignRole: z.object({
    role: z.string().min(1, "Elegí el rol.").max(60, "Elegí un rol de la lista."),
    place: z.string().min(1, "Elegí el lugar."),
    reason: reasonField,
  }),
  invite: z.object({
    email,
    first_name: z.string().trim().min(1, "Escribí el nombre.").max(80, "Hasta 80 caracteres."),
    last_name: z.string().trim().min(1, "Escribí el apellido.").max(80, "Hasta 80 caracteres."),
    role_code: z.string().min(1, "Elegí el rol.").max(60, "Elegí un rol de la lista."),
    place: z.string().min(1, "Elegí el lugar."),
    reason: reasonField,
  }),
  // La decisión sale del botón que se apretó: "para rechazar, el motivo" se revisa aparte.
  decision: z.object({
    comment: z.string().trim().max(500, "El comentario tiene hasta 500 caracteres.").optional(),
  }),
  login: z.object({
    email,
    password: z
      .string()
      .min(1, "Escribí tu contraseña.")
      .max(200, "La contraseña es demasiado larga."),
  }),
  code: z.object({ code }),
  recover: z.object({ email }),
  newPassword: z
    .object({ password: passwordRules, repeat: z.string() })
    .refine(repeatMatches, repeatError),
  profile: z.object({
    first_name: z.string().trim().min(1, "Escribí tu nombre.").max(80, "Hasta 80 caracteres."),
    last_name: z.string().trim().min(1, "Escribí tu apellido.").max(80, "Hasta 80 caracteres."),
  }),
  changePassword: z
    .object({
      current: z
        .string()
        .min(1, "Escribí tu contraseña actual.")
        .max(200, "La contraseña es demasiado larga."),
      password: passwordRules,
      repeat: z.string(),
    })
    .refine(repeatMatches, repeatError)
    .refine((v) => v.password !== v.current, {
      message: "La contraseña nueva tiene que ser otra.",
      path: ["password"],
    }),
  testDraft: z.object({
    place: z.string().min(1, "Elegí dónde va."),
    title: z.string().trim().min(1, "Escribí el título.").max(120, "Hasta 120 caracteres."),
    content: z.string().trim().max(4000, "Hasta 4.000 caracteres.").optional(),
    cost: z
      .string()
      .trim()
      .regex(
        /^$|^[0-9]{1,10}([.,][0-9]{1,4})?$/,
        "Escribí el costo con números, por ejemplo 1520,50.",
      )
      .optional(),
    reason: reasonField,
  }),
  // Corregir un documento publicado: el lugar y el título viajan ocultos.
  testCorrection: z.object({
    content: z.string().trim().max(4000, "Hasta 4.000 caracteres.").optional(),
    reason: reasonField,
  }),
} as const;

export type FormSchemaName = keyof typeof schemas;

// Los errores de un esquema, uno por campo (el primero), para mostrarlos debajo de cada campo.
export function fieldErrors(error: z.ZodError): Record<string, string> {
  const out: Record<string, string> = {};
  for (const issue of error.issues) {
    const key = issue.path.join(".");
    if (key && !(key in out)) out[key] = issue.message;
  }
  return out;
}

// Los campos de un formulario como objeto (sin archivos), para validarlos con un esquema.
export function formValues(formData: FormData): Record<string, string> {
  const out: Record<string, string> = {};
  formData.forEach((value, key) => {
    if (typeof value === "string") out[key] = value;
  });
  return out;
}
