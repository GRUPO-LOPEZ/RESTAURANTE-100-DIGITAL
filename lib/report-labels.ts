import type { BadgeStatus } from "@/components/ui/badge";
// Los reportes (ADR-0034): qué son y cómo se muestra cada columna. Sin base de datos: lo usan pantallas y pruebas.
export type ReportKey =
  "ingredients" | "yields" | "usage" | "cost_changes" | "quality" | "recipe_card" | "cost_card";
export type ColumnKind = "text" | "money" | "unit_cost" | "number" | "percent" | "date";
export type ReportColumn = { key: string; label: string; kind: ColumnKind };
export type ReportValue = string | number | null;
export type ReportRow = Record<string, ReportValue> & { href?: string | null };

export type ReportDefinition = {
  key: ReportKey;
  title: string;
  text: string;
  period?: boolean;
  // Una ficha es de una receta: primero se elige cuál.
  recipe?: boolean;
  empty: string;
  columns: ReportColumn[];
};

export const REPORTS: ReportDefinition[] = [
  {
    key: "ingredients",
    title: "Materias primas",
    text: "Nombre, categoría, unidad, precio por unidad y fecha.",
    empty: "Este local todavía no tiene materias primas.",
    columns: [
      { key: "name", label: "Materia prima", kind: "text" },
      { key: "category", label: "Categoría", kind: "text" },
      { key: "unit", label: "Unidad", kind: "text" },
      { key: "unit_cost", label: "Precio por unidad", kind: "unit_cost" },
      { key: "valid_from", label: "Fecha del precio", kind: "date" },
      { key: "state", label: "Estado", kind: "text" },
    ],
  },
  {
    key: "yields",
    title: "Rendimientos",
    text: "Rendimiento, merma y fecha de validación de cada proceso.",
    empty: "Todavía no hay rendimientos aprobados.",
    columns: [
      { key: "ingredient", label: "Materia prima", kind: "text" },
      { key: "process", label: "Proceso", kind: "text" },
      { key: "cut", label: "Corte", kind: "text" },
      { key: "supplier", label: "Proveedor", kind: "text" },
      { key: "cleaning_yield", label: "Rendimiento", kind: "percent" },
      { key: "waste", label: "Merma", kind: "percent" },
      { key: "cooking", label: "Cocción", kind: "text" },
      { key: "approved_at", label: "Validado el", kind: "date" },
    ],
  },
  {
    key: "usage",
    title: "Dónde se usa",
    text: "Cada materia prima o preparación, con las recetas vigentes que la usan.",
    empty: "Este local todavía no tiene recetas vigentes.",
    columns: [
      { key: "component", label: "Materia prima o preparación", kind: "text" },
      { key: "recipe", label: "Receta", kind: "text" },
      { key: "version_number", label: "Versión", kind: "number" },
      { key: "quantity", label: "Cantidad", kind: "number" },
      { key: "unit", label: "Unidad", kind: "text" },
      { key: "through", label: "A través de", kind: "text" },
    ],
  },
  {
    key: "cost_changes",
    title: "Cambios de costo",
    text: "Costo anterior, actual y variación de cada receta en un período.",
    period: true,
    empty: "No hubo cambios de costo en este período. Probá con otras fechas.",
    columns: [
      { key: "changed_on", label: "Fecha", kind: "date" },
      { key: "recipe", label: "Receta", kind: "text" },
      { key: "recipe_type", label: "Tipo", kind: "text" },
      { key: "version_number", label: "Versión", kind: "number" },
      { key: "reason", label: "Motivo", kind: "text" },
      { key: "previous", label: "Anterior", kind: "money" },
      { key: "current_cost", label: "Actual", kind: "money" },
      { key: "difference", label: "Diferencia", kind: "money" },
      { key: "difference_pct", label: "Variación (%)", kind: "number" },
    ],
  },
  {
    key: "quality",
    title: "Calidad de datos",
    text: "Los registros incompletos y qué hay que hacer para completarlos.",
    empty: "No falta nada por corregir.",
    columns: [
      { key: "problem", label: "Qué falta", kind: "text" },
      { key: "item", label: "Registro", kind: "text" },
      { key: "detail", label: "Detalle", kind: "text" },
      { key: "action", label: "Qué hacer", kind: "text" },
    ],
  },

  {
    key: "recipe_card",
    title: "Ficha técnica",
    text: "Ingredientes, cantidades, rendimiento, procedimiento, fotos y versión de una receta.",
    recipe: true,
    empty: "Esta receta no tiene una versión vigente.",
    columns: [
      { key: "item", label: "Ingrediente o preparación", kind: "text" },
      { key: "quantity", label: "Cantidad", kind: "number" },
      { key: "unit", label: "Unidad", kind: "text" },
      { key: "basis", label: "Se mide", kind: "text" },
      { key: "notes", label: "Notas", kind: "text" },
    ],
  },
  {
    key: "cost_card",
    title: "Ficha de costeo",
    text: "Costo por línea, preparaciones, total, unitario, participación y estado de una receta.",
    recipe: true,
    empty: "Esta receta no tiene costo en este local.",
    columns: [
      { key: "item", label: "Ingrediente o preparación", kind: "text" },
      { key: "quantity", label: "Cantidad", kind: "number" },
      { key: "unit", label: "Unidad", kind: "text" },
      { key: "cost", label: "Costo sin IVA", kind: "money" },
      { key: "share", label: "Participación (%)", kind: "number" },
      { key: "state", label: "Estado", kind: "text" },
    ],
  },
];

export const REPORT_PAGE = 50;
// Lo máximo que se exporta de una vez: nunca se traen tablas enteras.
export const REPORT_EXPORT_LIMIT = 5000;
// La API devuelve hasta 1.000 filas por pedido.
export const REPORT_CHUNK = 1000;

export const COST_REASON: Record<string, string> = {
  publish: "Versión publicada",
  recipe_changed: "Cambió la receta",
  price_change: "Cambio de precio",
  yield_change: "Cambio de rendimiento",
  assignment: "Asignación al local",
  legal_entity_change: "Cambio de razón social",
  restaurant_reopened: "Local reabierto",
  month_end: "Cierre de mes",
  daily: "Revisión diaria",
};

// Qué hay que hacer para completar cada indicador.
export const QUALITY_ACTION: Record<string, string> = {
  ingredient_price: "Cargarle un precio",
  price_stale: "Actualizar el precio",
  ingredient_unit: "Cargarle un producto de compra",
  ingredient_yield: "Aprobar un rendimiento",
  ingredient_duplicate: "Revisar si es la misma",
  recipe_cost: "Revisar los precios de sus líneas",
  recipe_approved: "Mandarla a revisión",
  recipe_review: "Decidir la revisión",
  recipe_photo: "Subir una foto",
  recipe_yield: "Cargar el rendimiento",
  recipe_components: "Reemplazar lo inactivo",
};

// Cómo se lee un factor de cocción (sección 9): menos de 1 es merma, más de 1 es expansión.
export function cookingEffect(factor: number): string {
  const percent = Math.abs(1 - factor) * 100;
  const text = percent.toLocaleString("es-AR", { maximumFractionDigits: 1 });
  if (factor < 1) return `Merma de ${text} %`;
  if (factor > 1) return `Expansión de ${text} %`;
  return "No cambia";
}

export function reportDefinition(key: string | undefined): ReportDefinition | undefined {
  return REPORTS.find((r) => r.key === key);
}

// Un valor como se ve en pantalla y en el CSV. El Excel lleva los números como números.
export function formatValue(value: ReportValue, kind: ColumnKind): string {
  if (value === null || value === "") return "—";
  if (kind === "text") return String(value);
  if (kind === "date") {
    const text = String(value);
    return new Intl.DateTimeFormat("es-AR", {
      dateStyle: "short",
      timeZone: "America/Argentina/Buenos_Aires",
    }).format(new Date(text.length === 10 ? `${text}T12:00:00-03:00` : text));
  }
  const number = Number(value);
  if (kind === "percent") {
    return `${(number * 100).toLocaleString("es-AR", { maximumFractionDigits: 1 })} %`;
  }
  if (kind === "money") {
    return number.toLocaleString("es-AR", { style: "currency", currency: "ARS" });
  }
  if (kind === "unit_cost") {
    return number.toLocaleString("es-AR", {
      style: "currency",
      currency: "ARS",
      minimumFractionDigits: 4,
      maximumFractionDigits: 4,
    });
  }
  return number.toLocaleString("es-AR", { maximumFractionDigits: 4 });
}

export function reportFileName(key: string, place: string, day: string): string {
  const slug = place
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return `reporte-${key}-${slug}-${day}`;
}

// El día de hoy en la Argentina: después de las 21 h, en UTC ya es mañana.
export function argentinaDay(now: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Argentina/Buenos_Aires",
  }).format(now);
}

// Una fecha real: 2026-02-31 no existe, aunque tenga buena forma.
function validDay(value: string | undefined): string | undefined {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return undefined;
  const date = new Date(`${value}T12:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value
    ? value
    : undefined;
}

// Un período válido: por defecto los últimos 30 días. Si vienen al revés, se dan vuelta.
export function reportPeriod(
  from: string | undefined,
  to: string | undefined,
  today: Date,
): { from: string; to: string } {
  const end = validDay(to) ?? argentinaDay(today);
  const start = new Date(`${end}T12:00:00Z`);
  start.setUTCDate(start.getUTCDate() - 30);
  const begin = validDay(from) ?? start.toISOString().slice(0, 10);
  return begin <= end ? { from: begin, to: end } : { from: end, to: begin };
}

// Los alérgenos de la ficha técnica: en pantalla van marcados y en el archivo, en el encabezado.
export type ReportAlert = { text: string; status: BadgeStatus };

// Los alérgenos como en la vista de cocina: primero lo que contiene, después lo que puede contener y lo no verificado.
export function allergenAlerts(allergens: { name: string; status: string }[]): ReportAlert[] {
  if (allergens.length === 0) {
    return [{ text: "No hay alérgenos cargados en el catálogo", status: "info" }];
  }
  const names = (status: string) => allergens.filter((a) => a.status === status).map((a) => a.name);
  const alerts: ReportAlert[] = [
    ...names("contains").map((n) => ({ text: `Contiene ${n}`, status: "bad" as const })),
    ...names("may_contain").map((n) => ({
      text: `Puede contener ${n} (trazas)`,
      status: "warn" as const,
    })),
  ];
  const unverified = names("not_verified");
  if (unverified.length > 0) {
    alerts.push({ text: `Sin verificar: ${unverified.join(", ")}`, status: "warn" });
  }
  if (alerts.length === 0) {
    alerts.push({ text: "Todo verificado: no contiene ningún alérgeno de la lista", status: "ok" });
  }
  return alerts;
}

// En el Excel y el CSV, los alérgenos van en una línea del encabezado.
export function allergenLine(alerts: ReportAlert[] | undefined): string[] {
  return alerts?.length ? [`Alérgenos: ${alerts.map((a) => a.text).join(" · ")}`] : [];
}
