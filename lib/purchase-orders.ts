import { z } from "zod";

// Órdenes de compra (Fase 3, Prompt 3, ADR-0053): reglas de la pantalla, sin acceso a la base. Se prueban con Vitest.
// La base vuelve a controlar todo (purchasing.save_order_draft, submit_order…). Sin precios: hoy no se cargan.

export type PoStatus =
  | "draft"
  | "pending_approval"
  | "sent"
  | "with_news"
  | "partially_received"
  | "received"
  | "closed"
  | "cancelled";

// Estado con palabra (nunca solo color).
export const PO_STATUS: Record<
  PoStatus,
  { label: string; status: "ok" | "warn" | "bad" | "none" | "info" | "review" | "draft" }
> = {
  draft: { label: "Borrador", status: "draft" },
  pending_approval: { label: "Espera aprobación", status: "review" },
  sent: { label: "En cola de envío", status: "info" },
  with_news: { label: "Con novedad", status: "warn" },
  partially_received: { label: "Recibida en parte", status: "warn" },
  received: { label: "Recibida", status: "ok" },
  closed: { label: "Cerrada", status: "none" },
  cancelled: { label: "Cancelada", status: "none" },
};

// Las pestañas del listado. «open» = lo que todavía no se recibió.
export const PO_TABS = [
  { value: undefined, label: "Abiertas", filter: "open" },
  { value: "borradores", label: "Borradores", filter: "draft" },
  { value: "aprobacion", label: "A aprobar", filter: "pending_approval" },
  { value: "novedades", label: "Con novedad", filter: "with_news" },
  { value: "todas", label: "Todas", filter: undefined },
] as const;

export const EVENT_KINDS = {
  news: "Novedad",
  shortage: "Falta mercadería",
  delivery_change: "Cambia la entrega",
  note: "Nota",
  cancelled: "Cancelada",
} as const;
export type EventKind = keyof typeof EVENT_KINDS;
// Lo que se puede registrar como novedad (cancelar va por «Cancelar»).
export const NEWS_KINDS = ["shortage", "delivery_change", "news", "note"] as const;

export const CHANNEL_NAMES: Record<string, string> = {
  whatsapp: "WhatsApp",
  email: "correo",
  supplier_portal: "el portal del proveedor",
};

// Una cantidad con coma y sin ceros de más: 2, 1,5.
export function qtyText(value: number): string {
  return value.toLocaleString("es-AR", { maximumFractionDigits: 3 });
}

// Los kg estimados de lo que se factura por peso: cantidad × unidades por envase × peso estimado por unidad (en la
// unidad de contenido del producto; si es g, se pasa a kg). «8 piezas ≈ 36 kg».
export function estimatedKg(
  quantity: number,
  unitsPerPackage: number,
  estimatedWeightPerUnit: number | null,
  contentUnit: string,
): number | null {
  if (!estimatedWeightPerUnit || !(quantity > 0)) return null;
  const total = quantity * unitsPerPackage * estimatedWeightPerUnit;
  const kg = contentUnit === "g" ? total / 1000 : total;
  return Math.round(kg * 10) / 10;
}

// Días de la semana (1 = lunes … 7 = domingo) en palabras cortas: «Ma, Ju y Sá».
const DAY_SHORT = ["", "Lu", "Ma", "Mi", "Ju", "Vi", "Sá", "Do"];
const DAY_LONG = ["", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
function joinEs(items: string[]): string {
  if (items.length <= 1) return items.join("");
  return `${items.slice(0, -1).join(", ")} y ${items[items.length - 1]}`;
}
export function daysShort(days: number[] | null | undefined): string {
  const list = (days ?? []).filter((d) => d >= 1 && d <= 7).sort();
  return list.length === 0 ? "Sin días" : joinEs(list.map((d) => DAY_SHORT[d] ?? ""));
}
export function daysLong(days: number[] | null | undefined): string {
  const list = (days ?? []).filter((d) => d >= 1 && d <= 7).sort();
  return list.length === 0 ? "sin días cargados" : joinEs(list.map((d) => DAY_LONG[d] ?? ""));
}

const line = z
  .object({
    purchase_product_id: z.string().uuid().optional(),
    ingredient_id: z.string().uuid().optional(),
    quantity: z
      .number({ message: "Va un número." })
      .positive("La cantidad tiene que ser mayor que cero.")
      .max(100000, "Es demasiado."),
    note: z.string().trim().max(300, "La nota va hasta 300 caracteres.").optional(),
  })
  .refine((l) => (l.purchase_product_id ? 1 : 0) + (l.ingredient_id ? 1 : 0) === 1, {
    message: "Cada línea va con un artículo o una materia prima.",
  });

// La OC que arma la pantalla. El mismo esquema en el navegador y en el servidor.
export const orderSchema = z.object({
  order_id: z.string().uuid().optional(),
  restaurant_id: z.string().uuid("Elegí el local arriba."),
  supplier_id: z.string().uuid("Elegí el proveedor."),
  lines: z
    .array(line)
    .min(1, "Agregá al menos un artículo.")
    .max(500, "Una orden va hasta 500 líneas."),
  notes: z.string().trim().max(1000, "Las observaciones van hasta 1000 caracteres.").optional(),
  expected_on: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha.")
    .optional(),
});
export type OrderInput = z.infer<typeof orderSchema>;

// Estado del mensaje al proveedor, con palabra y su color (un mensaje que falló nunca va en verde).
export const MESSAGE_STATUS: Record<
  string,
  { label: string; status: "ok" | "info" | "bad" | "none" }
> = {
  queued: { label: "En cola de envío", status: "info" },
  sent: { label: "Enviado", status: "ok" },
  failed: { label: "No se pudo mandar", status: "bad" },
  cancelled: { label: "No se manda", status: "none" },
};
export function messageStatus(status: string) {
  return MESSAGE_STATUS[status] ?? { label: "Sin datos", status: "none" as const };
}
