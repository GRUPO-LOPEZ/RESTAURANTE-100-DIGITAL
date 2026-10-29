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

// Catálogo (Fase 2): los mismos formatos que exige la base.
const catalogCode = z
  .string({ message: "Escribí el código." })
  .trim()
  .toUpperCase()
  .regex(
    /^[A-Z0-9][A-Z0-9-]{1,29}$/,
    "Mayúsculas, números y guiones, de 2 a 30 caracteres (por ejemplo, ING-0001).",
  );
const catalogName = z
  .string({ message: "Escribí el nombre." })
  .trim()
  .min(1, "Escribí el nombre.")
  .max(120, "Hasta 120 caracteres.");
const notesField = z.string().trim().max(1000, "Hasta 1.000 caracteres.").optional();
// Número positivo, con coma o punto decimal (como se escribe en la Argentina).
export const positiveNumber = z
  .string({ message: "Escribí un número, por ejemplo 0,92." })
  .trim()
  .regex(/^[0-9]{1,12}([.,][0-9]{1,6})?$/, "Escribí un número, por ejemplo 0,92.")
  .refine((v) => Number(v.replace(",", ".")) > 0, "Tiene que ser mayor que cero.");
const choice = (message: string) => z.string({ message }).min(1, message).max(60, message);

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
  ingredient: z.object({
    code: catalogCode,
    name: catalogName,
    category_id: choice("Elegí la categoría."),
    recipe_unit: z.enum(["g", "ml", "unit"], { message: "Elegí en qué se usa: g, ml o unidad." }),
    reason: reasonField,
  }),
  // El código no cambia nunca: no se edita.
  ingredientEdit: z.object({
    name: catalogName,
    category_id: choice("Elegí la categoría."),
    notes: notesField,
    reason: reasonField,
  }),
  aliases: z.object({
    aliases: z.string().trim().max(1000, "Hasta 1.000 caracteres.").optional(),
    reason: reasonField,
  }),
  conversion: z.object({
    kind: z.enum(["density", "unit_weight"], { message: "Elegí qué conversión es." }),
    factor: positiveNumber,
    source: choice("Elegí de dónde sale el dato."),
    measured_on: z
      .string({ message: "Elegí la fecha de la medición." })
      .regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha de la medición."),
    measured_by: z.string().trim().max(120, "Hasta 120 caracteres.").optional(),
    reason: reasonField,
  }),
  allergen: z.object({
    allergen_id: choice("Elegí el alérgeno."),
    status: z.enum(["", "contains", "may_contain", "free_verified"], {
      message: "Elegí el estado.",
    }),
    source: z.string().max(60).optional(),
    reason: reasonField,
  }),
  product: z.object({
    code: catalogCode,
    description: z
      .string({ message: "Escribí la descripción." })
      .trim()
      .min(1, "Escribí la descripción.")
      .max(200, "Hasta 200 caracteres."),
    brand_name: z.string().trim().max(80, "Hasta 80 caracteres.").optional(),
    supplier_id: z.string().max(60).optional(),
    package_unit: choice("Elegí cómo viene."),
    units_per_package: z
      .string({ message: "Escribí cuántas unidades trae, por ejemplo 12." })
      .trim()
      .regex(/^[0-9]{1,5}$/, "Escribí cuántas unidades trae, por ejemplo 12.")
      .refine((v) => Number(v) >= 1 && Number(v) <= 10000, "De 1 a 10.000."),
    content_per_unit: positiveNumber,
    content_unit: choice("Elegí la unidad del contenido."),
    reason: reasonField,
  }),
  supplier: z.object({
    code: catalogCode,
    name: catalogName,
    tax_id: z
      .string()
      .trim()
      .regex(/^$|^[0-9-]{8,15}$/, "El CUIT va solo con números y guiones.")
      .optional(),
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
