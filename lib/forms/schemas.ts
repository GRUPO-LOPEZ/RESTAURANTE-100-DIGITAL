import { z } from "zod";
import { parseAmount } from "@/lib/money";
import { LINE_UNIT_CODES } from "@/lib/recipe-format";

// Esquemas de los formularios (ADR-0016): los mismos en el navegador (React Hook Form, antes de
// enviar) y en las acciones de servidor (que validan igual, porque nunca se confía en la pantalla).
// Validan lo que escribe la persona; los ids ocultos los valida cada acción.

// Un porcentaje de más de 0 a 100, con hasta dos decimales y coma o punto.
const percentField = (example: string) =>
  z
    .string({ message: "Escribí el porcentaje." })
    .trim()
    .regex(/^[0-9]{1,3}([.,][0-9]{1,2})?$/, `Escribí un porcentaje, por ejemplo ${example}.`)
    .refine((v) => {
      const n = Number(v.replace(",", "."));
      return n > 0 && n <= 100;
    }, "De más de 0 a 100.");

// Una merma en %: de 0 a menos de 100, con hasta dos decimales. Vacía = no se carga.
const lossField = z
  .string()
  .trim()
  .regex(/^$|^[0-9]{1,2}([.,][0-9]{1,2})?$/, "Escribí la merma en %, por ejemplo 12,5.")
  .optional();

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
// El código de la vista previa del alta (ADR-0041): no lo escribe nadie, puede faltar.
const expectedCode = z
  .string()
  .trim()
  .regex(/^$|^[A-Z0-9][A-Z0-9-]{1,29}$/)
  .optional();
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

// Estructura del grupo (panel de control, ADR-0031): los mismos formatos que exige la base.
const orgName = z
  .string({ message: "Escribí el nombre." })
  .trim()
  .min(1, "Escribí el nombre.")
  .max(120, "Hasta 120 caracteres.");
const orgCode = z
  .string({ message: "Escribí el código." })
  .trim()
  .toUpperCase()
  .regex(
    /^[A-Z0-9][A-Z0-9-]{1,19}$/,
    "Mayúsculas, números y guiones, de 2 a 20 caracteres (por ejemplo, PASTAS).",
  );
const optionalText = (max: number) =>
  z.string().trim().max(max, `Hasta ${max} caracteres.`).optional();
// El CUIT se puede escribir con o sin guiones; la base lo guarda con 11 números.
export const taxId = z
  .string({ message: "Escribí el CUIT." })
  .trim()
  .transform((v) => v.replace(/[\s-]/g, ""))
  .pipe(z.string().regex(/^[0-9]{11}$/, "El CUIT tiene 11 números (con o sin guiones)."));
const restaurantFields = {
  name: orgName,
  code: z
    .string()
    .trim()
    .toUpperCase()
    .regex(
      /^$|^[A-Z0-9][A-Z0-9-]{1,19}$/,
      "Mayúsculas, números y guiones, de 2 a 20 caracteres (por ejemplo, PAS-CENTRO).",
    )
    .optional(),
  address: optionalText(200),
  locality: optionalText(120),
  phone: z
    .string()
    .trim()
    .regex(/^$|^[0-9 +()-]{6,30}$/, "Solo números, espacios, +, guiones y paréntesis.")
    .optional(),
  opened_on: z
    .string()
    .trim()
    .regex(/^$|^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha.")
    .refine((v) => {
      if (v === "") return true;
      const d = new Date(`${v}T12:00:00Z`);
      return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
    }, "Esa fecha no existe.")
    .optional(),
  site_type: z
    .enum(["restaurant", "central_kitchen", "production_unit"], { message: "Elegí el tipo." })
    .optional(),
  legal_entity_id: z.string().max(60).optional(),
};

// Una fecha obligatoria que existe (2026-02-31 no).
const validDate = z
  .string({ message: "Elegí la fecha." })
  .trim()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha.")
  .refine((v) => {
    const d = new Date(`${v}T12:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
  }, "Esa fecha no existe.");
const days = z
  .string({ message: "Escribí los días." })
  .trim()
  .regex(/^[0-9]{1,3}$/, "Escribí los días, por ejemplo 30.")
  .refine((v) => Number(v) >= 1 && Number(v) <= 365, "De 1 a 365 días.");

// Un número como se escribe en la pantalla ("1.500", "2,5"), dentro de un rango. El límite de arriba incluye su valor.
const amountBetween = (max: number, message: string) =>
  z
    .string({ message })
    .trim()
    .refine((v) => {
      const n = parseAmount(v);
      return n !== null && n > 0 && n <= max;
    }, message);
const scenarioPick = (message: string) => z.string({ message }).min(1, message).max(60, message);

const repeatMatches = (v: { password: string; repeat: string }) => v.password === v.repeat;
const repeatError = { message: "Las dos contraseñas no coinciden.", path: ["repeat"] };

export const schemas = {
  // Escenarios de costo (ADR-0032).
  scenario: z.object({
    name: z.string().trim().min(1, "Escribí el nombre.").max(120, "Hasta 120 caracteres."),
    reason: reasonField,
  }),
  scenarioPrice: z.object({
    ingredient: scenarioPick("Elegí una materia prima."),
    amount: amountBetween(999_999_999, "Escribí un precio mayor que cero, por ejemplo 12.500."),
    supplier: z.string().max(60).optional(),
    reason: reasonField,
  }),
  scenarioYield: z.object({
    ingredient: scenarioPick("Elegí una materia prima."),
    cleaning: amountBetween(100, "Escribí un porcentaje de hasta 100, por ejemplo 80."),
    cooking: amountBetween(10, "Escribí un factor mayor que cero y de hasta 10."),
    reason: reasonField,
  }),
  scenarioQuantity: z.object({
    line: scenarioPick("Elegí una línea."),
    quantity: amountBetween(999_999_999, "Escribí una cantidad mayor que cero."),
    reason: reasonField,
  }),
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
  // El código lo arma la base (ADR-0041): viaja solo el de la vista previa, para avisar si salió otro.
  ingredient: z.object({
    category_id: choice("Elegí el rubro."),
    expected_code: expectedCode,
    name: catalogName,
    recipe_unit: z
      .string()
      .trim()
      .regex(/^[a-z_]{1,20}$/, "Elegí en qué se usa en las recetas."),
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
  // Rubros (ADR-0038): alta con motivo; el nombre se cambia en la tarjeta (motivo fijo); la baja
  // pide destino solo si el rubro tiene usos (lo controla la base).
  rubro: z.object({ name: settingName, reason: reasonField }),
  rubroName: z.object({ name: settingName }),
  // Subcategoría (configuración del catálogo): el primer nivel son los rubros, que se crean en Rubros.
  subcategory: z.object({
    name: settingName,
    parent_id: choice("Elegí el rubro."),
    reason: reasonField,
  }),
  rubroDeactivate: z.object({
    target_id: z.string().max(60).optional(),
    reason: reasonField,
  }),
  // Matriz de permisos (ADR-0039): el lote de cambios y su motivo. La base vuelve a controlar todo.
  permissionMatrix: z.object({
    group_id: z.string().uuid(),
    changes: z
      .array(
        z.object({
          role_id: z.string().uuid(),
          permission_code: z.string().regex(/^[a-z_]+\.[a-z_]+$/),
          granted: z.boolean(),
        }),
      )
      .min(1, "No hay cambios para guardar.")
      .max(1000, "Son demasiados cambios juntos: guardá de a partes."),
    reason: reasonField,
  }),
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
  // Mermas en % (ADR-0040): limpieza y descongelado, al menos una. 0 % solo declarando «No tiene merma».
  waste: z
    .object({
      cleaning_loss: lossField,
      thawing_loss: lossField,
      declared_no_loss: z.union([z.boolean(), z.literal("on"), z.literal("")]).optional(),
      method: z.string().trim().max(500, "Hasta 500 caracteres.").optional(),
      reason: reasonField,
    })
    .refine((v) => (v.cleaning_loss ?? "") !== "" || (v.thawing_loss ?? "") !== "", {
      message: "Cargá al menos una merma.",
      path: ["cleaning_loss"],
    })
    .refine(
      (v) =>
        isChecked(v.declared_no_loss) ||
        ![v.cleaning_loss, v.thawing_loss].some(
          (x) => (x ?? "") !== "" && Number((x ?? "").replace(",", ".")) === 0,
        ),
      { message: "Con 0 % de merma, marcá que no tiene merma.", path: ["declared_no_loss"] },
    ),
  // Una unidad nueva (ADR-0040). Un envase va sin equivalencia; las demás, con cuánto vale en la base.
  unit: z
    .object({
      code: z
        .string()
        .trim()
        .regex(/^[a-z_]{1,20}$/, "Solo minúsculas sin acentos y guion bajo, por ejemplo cucharon."),
      long_name: z.string().trim().min(1, "Escribí el nombre.").max(40, "Hasta 40 caracteres."),
      abbreviation: z
        .string()
        .trim()
        .min(1, "Escribí la abreviatura.")
        .max(12, "Hasta 12 caracteres."),
      dimension: z.enum(["mass", "volume", "count", "package"], { message: "Elegí el tipo." }),
      factor: z
        .string()
        .trim()
        .regex(/^$|^[0-9]{1,9}([.,][0-9]{1,6})?$/, "Escribí un número, por ejemplo 240.")
        .optional(),
      reason: reasonField,
    })
    .refine((v) => v.dimension === "package" || Number((v.factor ?? "").replace(",", ".")) > 0, {
      message: "Escribí cuánto vale en la unidad base.",
      path: ["factor"],
    })
    .refine((v) => v.dimension !== "package" || (v.factor ?? "") === "", {
      message: "Un envase no tiene equivalencia fija: dejalo vacío.",
      path: ["factor"],
    }),
  // Se compra congelada (ADR-0040): sí o no, con motivo (cambia el costo).
  thawing: z.object({
    requires_thawing: z.enum(["true", "false"], { message: "Elegí sí o no." }),
    reason: reasonField,
  }),
  // Recetas (etapa 2.2 A, ADR-0023). El alcance viaja como "group:<id>", "brand:<id>" o "restaurant:<id>".
  recipe: z.object({
    scope: choice("Elegí dónde se usa la receta.").regex(
      /^(group|brand|restaurant):[0-9a-f-]{36}$/,
      "Elegí dónde se usa la receta.",
    ),
    // Solo platos y preparaciones, siempre con rubro: el código lo arma la base (ADR-0041).
    type: z.enum(["dish", "preparation"], { message: "Elegí el tipo: plato o preparación." }),
    category_id: choice("Elegí el rubro."),
    expected_code: expectedCode,
    name: catalogName,
    reason: reasonField,
  }),
  // El código y el alcance no cambian: no se editan.
  recipeEdit: z.object({
    name: catalogName,
    short_name: z.string().trim().max(40, "Hasta 40 caracteres.").optional(),
    category_id: z.string().max(60).optional(),
    sector: z.string().trim().max(60, "Hasta 60 caracteres.").optional(),
    station: z.string().trim().max(60, "Hasta 60 caracteres.").optional(),
    reason: reasonField,
  }),
  recipeDraft: z.object({
    yield_quantity: positiveNumber,
    yield_unit: z.enum(LINE_UNIT_CODES, { message: "Elegí la unidad." }),
    portions: z
      .string()
      .trim()
      .regex(/^$|^[0-9]{1,5}$/, "Escribí cuántas porciones, por ejemplo 4.")
      .optional(),
    portion_grams: z
      .string()
      .trim()
      .regex(/^$|^[0-9]{1,6}([.,][0-9]{1,2})?$/, "Escribí el peso en gramos, por ejemplo 350.")
      .optional(),
    description: z.string().trim().max(2000, "Hasta 2.000 caracteres.").optional(),
    storage_notes: z.string().trim().max(2000, "Hasta 2.000 caracteres.").optional(),
    presentation_notes: z.string().trim().max(2000, "Hasta 2.000 caracteres.").optional(),
    change_summary: z.string().trim().max(1000, "Hasta 1.000 caracteres.").optional(),
    reason: reasonField,
  }),
  assignment: z.object({
    restaurant_id: choice("Elegí el local."),
    reason: reasonField,
  }),
  // Variante local de una maestra (ADR-0025): el local y su nombre. El código es el de la maestra y -V01 (ADR-0041).
  variant: z.object({
    restaurant_id: choice("Elegí el local."),
    name: catalogName,
    reason: reasonField,
  }),
  // El archivo lo controla la acción (tipo y tamaño) y otra vez el bucket.
  recipePhoto: z.object({
    kind: z.enum(
      [
        "final_product",
        "plating",
        "raw_material",
        "step",
        "critical_point",
        "correct_example",
        "incorrect_example",
      ],
      { message: "Elegí qué muestra la foto." },
    ),
    description: z.string().trim().max(300, "Hasta 300 caracteres.").optional(),
    reason: reasonField,
  }),
  // Importar el recetario (ADR-0027): el archivo lo controla el navegador (tipo y tamaño), otra vez
  // el bucket y el lector del servidor.
  importBook: z.object({
    brand_id: choice("Elegí la marca."),
    code_prefix: z
      .string({ message: "Escribí el prefijo." })
      .trim()
      .toUpperCase()
      .regex(/^[A-Z0-9]{2,6}$/, "De 2 a 6 letras o números, por ejemplo NON."),
    reason: reasonField,
  }),
  // Panel de control de la estructura (ADR-0031): los mismos formatos que exige la base.
  brand: z.object({ name: orgName, code: orgCode, reason: reasonField }),
  // Quien administra solo su marca edita el nombre; el código y el estado, quien administra el grupo
  // (los campos que no se muestran no se mandan).
  brandEdit: z.object({
    name: orgName,
    code: orgCode.optional(),
    status: z.enum(["active", "inactive"], { message: "Elegí el estado." }).optional(),
    reason: reasonField,
  }),
  restaurant: z.object({ ...restaurantFields, reason: reasonField }),
  restaurantEdit: z.object({
    ...restaurantFields,
    status: z.enum(["active", "inactive"], { message: "Elegí el estado." }).optional(),
    reason: reasonField,
  }),
  legalEntity: z.object({
    name: z
      .string({ message: "Escribí el nombre." })
      .trim()
      .min(1, "Escribí el nombre.")
      .max(200, "Hasta 200 caracteres."),
    tax_id: taxId,
    vat_condition: z.enum(["registered", "monotax", "exempt"], {
      message: "Elegí la condición frente al IVA.",
    }),
    reason: reasonField,
  }),
  restaurantLegalEntity: z.object({
    legal_entity_id: choice("Elegí la razón social."),
    reason: reasonField,
  }),
  area: z.object({ name: orgName, reason: reasonField }),
  // Precios (ADR-0029): los mismos controles que hace costing.propose_price.
  priceProposal: z
    .object({
      product_id: choice("Elegí el producto."),
      place: choice("Elegí para quién vale."),
      valid_from: validDate,
      package_price: positiveNumber,
      discount_amount: z
        .string()
        .trim()
        .regex(/^$|^[0-9]{1,12}([.,][0-9]{1,4})?$/, "Escribí un número, por ejemplo 150,50.")
        .optional(),
      document_type: z.enum(["invoice", "no_invoice"], { message: "Elegí el comprobante." }),
      vat_rate: z.string().trim().optional(),
      price_includes_vat: z.union([z.boolean(), z.string()]).optional(),
      supplier_id: z.string().max(60).optional(),
      source: z.enum(["manual", "test_value"], { message: "Elegí el origen." }),
      notes: z.string().trim().max(1000, "Hasta 1.000 caracteres.").optional(),
      reason: reasonField,
    })
    .superRefine((v, ctx) => {
      if (v.document_type === "invoice" && !["0", "10.5", "21", "27"].includes(v.vat_rate ?? ""))
        ctx.addIssue({ code: "custom", path: ["vat_rate"], message: "Elegí la alícuota de IVA." });
      const price = Number(v.package_price.replace(",", "."));
      const discount = Number((v.discount_amount || "0").replace(",", "."));
      // Con un precio inválido ya hay un error en el precio: no se suma otro en el descuento.
      if (price > 0 && discount >= price)
        ctx.addIssue({
          code: "custom",
          path: ["discount_amount"],
          message: "El descuento tiene que ser menor que el precio.",
        });
    }),
  priceSettings: z.object({
    approval_variation_pct: percentField("15"),
    stale_days: days,
    lookback_days: days,
    reason: reasonField,
  }),
  // Aviso de rendimiento (ADR-0035): el desvío de un ensayo contra el estándar que dispara el aviso.
  yieldAlert: z.object({
    yield_alert_pct: percentField("10"),
    reason: reasonField,
  }),
  categoryStaleDays: z.object({
    stale_price_days: z
      .string()
      .trim()
      .regex(/^$|^[0-9]{1,3}$/, "Escribí los días, por ejemplo 30.")
      .refine((v) => v === "" || (Number(v) >= 1 && Number(v) <= 365), "De 1 a 365 días.")
      .optional(),
    reason: reasonField,
  }),
} as const;

export type FormSchemaName = keyof typeof schemas;

// Las listas del editor de recetas (líneas y pasos): no son un formulario plano, así que se validan
// con estos esquemas en el navegador y otra vez en la acción de servidor (ADR-0016).
export const recipeLinesSchema = z
  .array(
    z
      .object({
        // Una materia prima o una preparación (subreceta), nunca las dos (ADR-0025).
        ingredient_id: z.string().uuid("Elegí la materia prima.").nullable(),
        sub_recipe_id: z.string().uuid("Elegí la preparación.").nullable(),
        ingredient: z.string().max(200),
        quantity: positiveNumber,
        unit: z.enum(LINE_UNIT_CODES, { message: "Elegí la unidad." }),
        basis: z.enum(["purchase", "clean", "cooked", "finished"]),
        // El perfil de merma de una línea limpia o cocida: la ficha lo conserva al guardar (ADR-0042).
        yield_profile_id: z.string().uuid().nullable().optional(),
        no_scale: z.boolean(),
        notes: z.string().trim().max(500, "Hasta 500 caracteres."),
      })
      .refine((l) => (l.ingredient_id === null) !== (l.sub_recipe_id === null), {
        message: "Elegí una materia prima o una preparación.",
        path: ["ingredient_id"],
      })
      .refine((l) => (l.sub_recipe_id !== null) === (l.basis === "finished"), {
        message: "Una preparación va en cantidad terminada; una materia prima, no.",
        path: ["basis"],
      }),
  )
  .max(200, "Hasta 200 componentes.");

export const recipeStepsSchema = z
  .array(
    z
      .object({
        kind: z.enum([
          "preparation",
          "cooking",
          "resting",
          "fermentation",
          "cooling",
          "regeneration",
          "plating",
          "other",
        ]),
        instructions: z
          .string()
          .trim()
          .min(1, "Escribí qué se hace en el paso.")
          .max(2000, "Hasta 2.000 caracteres."),
        active_minutes: z
          .string()
          .trim()
          .regex(/^[0-9]{1,5}$/, "Minutos: un número entero, por ejemplo 15."),
        passive_minutes: z
          .string()
          .trim()
          .regex(/^[0-9]{1,5}$/, "Minutos: un número entero, por ejemplo 15."),
        equipment: z.string().trim().max(120, "Hasta 120 caracteres."),
        equipment_capacity: z
          .string()
          .trim()
          .refine((v) => v === "" || (parseAmount(v) ?? 0) >= 0.000001, {
            message: "Escribí un número mayor que cero, como 5 o 2,5.",
          }),
        equipment_capacity_unit: z.string().max(20),
        depends_on: z.array(z.number().int().min(1).max(100)).max(99),
      })
      .refine((s) => s.equipment_capacity === "" || s.equipment !== "", {
        message: "Para cargar la capacidad, escribí el equipo.",
        path: ["equipment"],
      }),
  )
  .max(100, "Hasta 100 pasos.");

// Ficha única de receta (ADR-0042): los datos de la receta y de la versión que se editan en la ficha. Cada bloque
// es opcional: solo viaja lo que cambió. En un plato se carga el peso de la porción (las porciones las calcula la
// base); en una preparación, el peso neto con su unidad.
const sheetText = (max: number, message: string) => z.string().trim().max(max, message).optional();
export const recipeSheetDataSchema = z.object({
  name: catalogName,
  short_name: sheetText(40, "Hasta 40 caracteres."),
  category_id: z.string().max(60).optional(),
  sector: sheetText(60, "Hasta 60 caracteres."),
  station: sheetText(60, "Hasta 60 caracteres."),
});
export const recipeSheetDraftSchema = z.object({
  yield_quantity: z
    .string()
    .trim()
    .refine((v) => v === "" || (parseAmount(v) ?? 0) > 0, {
      message: "Escribí un número mayor que cero, como 5 o 2,5.",
    })
    .optional(),
  yield_unit: z.union([z.enum(LINE_UNIT_CODES), z.literal("")]).optional(),
  portion_grams: z
    .string()
    .trim()
    .regex(/^$|^[0-9]{1,6}([.,][0-9]{1,2})?$/, "Escribí el peso en gramos, por ejemplo 350.")
    .refine(
      (v) => v === "" || (parseAmount(v) ?? 0) > 0,
      "El peso de la porción tiene que ser mayor que cero.",
    )
    .optional(),
  description: sheetText(2000, "Hasta 2.000 caracteres."),
  storage_notes: sheetText(2000, "Hasta 2.000 caracteres."),
  presentation_notes: sheetText(2000, "Hasta 2.000 caracteres."),
  change_summary: sheetText(1000, "Hasta 1.000 caracteres."),
});

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
