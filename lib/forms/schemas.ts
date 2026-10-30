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
const settingName = catalogName.max(80, "Hasta 80 caracteres.");
const notesField = z.string().trim().max(1000, "Hasta 1.000 caracteres.").optional();
// Número positivo, con coma o punto decimal (como se escribe en la Argentina).
export const positiveNumber = z
  .string({ message: "Escribí un número, por ejemplo 0,92." })
  .trim()
  .regex(/^[0-9]{1,12}([.,][0-9]{1,6})?$/, "Escribí un número, por ejemplo 0,92.")
  .refine((v) => Number(v.replace(",", ".")) > 0, "Tiene que ser mayor que cero.");
// Una casilla marcada: true en el navegador, "on" en el formulario enviado.
export function isChecked(value: boolean | string | undefined): boolean {
  return value === true || value === "on";
}
// Hoy en la Argentina (AAAA-MM-DD), igual en el navegador y en el servidor.
export function todayInArgentina(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires" }).format(
    new Date(),
  );
}
// Peso opcional en gramos: vacío o un número positivo.
const optionalGrams = z
  .string()
  .trim()
  .regex(/^$|^[0-9]{1,9}([.,][0-9]{1,3})?$/, "Escribí el peso en gramos, por ejemplo 7700.")
  .refine((v) => v === "" || Number(v.replace(",", ".")) > 0, "Tiene que ser mayor que cero.")
  .optional();
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
  // Configuración del catálogo (ADR-0022): categorías y procesos, con nombres de hasta 80, como la base.
  category: z.object({
    name: settingName,
    parent_id: z.string().max(60).optional(),
    reason: reasonField,
  }),
  rename: z.object({ name: settingName, reason: reasonField }),
  yieldProcess: z.object({ code: catalogCode, name: settingName, reason: reasonField }),
  // Ensayo de rendimiento: pesos en gramos, al menos un par completo (bruto y limpio, o antes y
  // después de cocinar), y el limpio no pesa más que el bruto. Lo mismo exige la base.
  yieldTest: z
    .object({
      process_id: choice("Elegí el proceso."),
      restaurant_id: choice("Elegí el local donde se midió."),
      cut: z.string().trim().max(80, "Hasta 80 caracteres.").optional(),
      tested_on: z
        .string({ message: "Elegí la fecha del ensayo." })
        .regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha del ensayo.")
        .refine((v) => v <= todayInArgentina(), "La fecha del ensayo no puede ser futura."),
      samples: z
        .string({ message: "Escribí cuántas muestras." })
        .trim()
        .regex(/^[0-9]{1,4}$/, "Escribí cuántas muestras, por ejemplo 3.")
        .refine((v) => Number(v) >= 1, "Al menos 1."),
      gross_weight: optionalGrams,
      clean_weight: optionalGrams,
      before_cooking_weight: optionalGrams,
      after_cooking_weight: optionalGrams,
      responsible: z.string().trim().max(120, "Hasta 120 caracteres.").optional(),
      reason: reasonField,
    })
    .refine((v) => Boolean(v.gross_weight) === Boolean(v.clean_weight), {
      message: "Para la limpieza hacen falta los dos pesos: bruto y limpio.",
      path: ["clean_weight"],
    })
    .refine((v) => Boolean(v.before_cooking_weight) === Boolean(v.after_cooking_weight), {
      message: "Para la cocción hacen falta los dos pesos: antes y después.",
      path: ["after_cooking_weight"],
    })
    .refine((v) => Boolean(v.gross_weight) || Boolean(v.before_cooking_weight), {
      message: "Cargá al menos un par de pesos.",
      path: ["gross_weight"],
    })
    .refine(
      (v) =>
        !v.gross_weight ||
        !v.clean_weight ||
        Number(v.clean_weight.replace(",", ".")) <= Number(v.gross_weight.replace(",", ".")),
      { message: "El peso limpio no puede ser mayor que el bruto.", path: ["clean_weight"] },
    ),
  // Propuesta de estándar: la limpieza se escribe en % (78,5) y la cocción como factor (2,5).
  // 100 % de limpieza con factor 1 solo si se marca "sin merma": lo exige la base (sección 9).
  yieldProposal: z
    .object({
      process_id: choice("Elegí el proceso."),
      cut: z.string().trim().max(80, "Hasta 80 caracteres.").optional(),
      cleaning_percent: positiveNumber.refine(
        (v) => Number(v.replace(",", ".")) <= 100,
        "La limpieza va de 0 a 100 %.",
      ),
      cooking_factor: positiveNumber.refine(
        (v) => Number(v.replace(",", ".")) <= 10,
        "El factor de cocción va hasta 10.",
      ),
      method: z.string().trim().max(500, "Hasta 500 caracteres.").optional(),
      // React Hook Form la entrega como true o false; el formulario enviado, como "on".
      declared_no_loss: z.union([z.boolean(), z.literal("on"), z.literal("")]).optional(),
      reason: reasonField,
    })
    .refine(
      (v) =>
        isChecked(v.declared_no_loss) ||
        !(
          Number(v.cleaning_percent.replace(",", ".")) === 100 &&
          Number(v.cooking_factor.replace(",", ".")) === 1
        ),
      {
        message: "Con 100 % de limpieza y factor 1, marcá que no tiene merma.",
        path: ["declared_no_loss"],
      },
    ),
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
