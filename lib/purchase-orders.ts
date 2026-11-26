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

// Solo artículos del proveedor (decisión 3 de Soy, ADR-0069): una materia prima suelta ya no se pide. La base lo
// vuelve a controlar.
const line = z
  .object({
    purchase_product_id: z.string().uuid("Pedí artículos del proveedor."),
    quantity: z
      .number({ message: "Va un número." })
      .positive("La cantidad tiene que ser mayor que cero.")
      .max(100000, "Es demasiado."),
    note: z.string().trim().max(300, "La nota va hasta 300 caracteres.").optional(),
  })
  // Estricto: una clave de más (una materia prima, «ingredient_id») no se descarta en silencio, se rechaza.
  .strict();

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

// ---------------------------------------------------------------------------
// Los 4 indicadores de la ficha de una OC (criterios de Soy, ADR-0068)
// ---------------------------------------------------------------------------
// Con la regla de las métricas confiables (lib/metrics.ts): sin artículos, «Sin artículos»; antes de mandarla, lo
// recibido no se mide (nunca «0 de 5» en un borrador). Sin precios: la ficha no los muestra.
export type OrderIndicator = {
  key: "lines" | "delivery" | "received" | "news";
  label: string;
  value: number | string | null;
  total?: number;
  comparison?: string;
  missingReason?: string;
  status: "ok" | "warn" | "bad" | "info" | "none";
  statusLabel: string;
};

const NOT_SENT: PoStatus[] = ["draft", "pending_approval"];
const WAITING: PoStatus[] = ["sent", "with_news", "partially_received"];

export function orderIndicators(
  o: {
    status: PoStatus;
    expectedOn: string;
    lines: { quantity: number; receivedQuantity: number }[];
    events: { kind: string }[];
  },
  today: string,
  formatDay: (iso: string) => string,
): OrderIndicator[] {
  const n = o.lines.length;
  const complete = o.lines.filter((l) => l.receivedQuantity >= l.quantity).length;
  const news = o.events.filter((e) => e.kind !== "cancelled").length;
  const notSent = NOT_SENT.includes(o.status);
  const cancelled = o.status === "cancelled";
  const late = WAITING.includes(o.status) && o.expectedOn < today;
  return [
    { key: "lines", label: "Artículos", value: n, total: n, status: "info", statusLabel: "" },
    {
      key: "delivery",
      label: "Entrega esperada",
      value: o.expectedOn ? formatDay(o.expectedOn) : null,
      missingReason: "La orden no tiene fecha de entrega.",
      ...(cancelled
        ? { status: "none" as const, statusLabel: "Cancelada" }
        : late
          ? { status: "warn" as const, statusLabel: "Atrasada" }
          : complete === n && n > 0 && !notSent
            ? { status: "ok" as const, statusLabel: "Llegó" }
            : { status: "info" as const, statusLabel: "" }),
    },
    {
      key: "received",
      label: "Recibido",
      value: notSent || cancelled ? null : complete,
      total: n,
      comparison: `de ${n}`,
      missingReason: cancelled ? "La orden se canceló." : "Todavía no se mandó al proveedor.",
      ...(complete === n
        ? { status: "ok" as const, statusLabel: "Completa" }
        : complete > 0
          ? { status: "warn" as const, statusLabel: "En parte" }
          : { status: "none" as const, statusLabel: "Sin recibir" }),
    },
    {
      key: "news",
      label: "Novedades",
      value: notSent ? null : news,
      missingReason: "Todavía no se mandó al proveedor.",
      ...(news > 0
        ? { status: "warn" as const, statusLabel: news === 1 ? "Una novedad" : "Con novedades" }
        : { status: "ok" as const, statusLabel: "Sin novedades" }),
    },
  ];
}

// ---------------------------------------------------------------------------
// La orden en una pantalla (ADR-0069)
// ---------------------------------------------------------------------------
// El total estimado con el precio de lista de cada renglón. Si a un renglón le falta el precio (no está en la lista
// vigente), se dice cuántos: el total no miente. null si la persona no ve precios.
export function orderEstimate(
  lines: { quantity: number; price: number | null }[],
  canSeePrices: boolean,
): { total: number; missing: number } | null {
  if (!canSeePrices) return null;
  let total = 0;
  let missing = 0;
  for (const l of lines) {
    if (!(l.quantity > 0)) continue;
    if (l.price === null) missing += 1;
    else total += l.quantity * l.price;
  }
  return { total: Math.round(total * 100) / 100, missing };
}

// El aviso del pedido mínimo: no frena la orden (decisión de Joaco), avisa. Sin mínimo cargado, nada.
export function minimumNotice(
  total: number,
  minimum: number | null,
): { reached: boolean; short: number } | null {
  if (minimum === null || !(minimum > 0)) return null;
  return {
    reached: total >= minimum,
    short: Math.max(0, Math.round((minimum - total) * 100) / 100),
  };
}

// Si hoy es día de pedido del proveedor, o cuál es el próximo. Los días van de 1 (lunes) a 7 (domingo), como en la base;
// hoy es una fecha aaaa-mm-dd de la Argentina.
export function orderDayLabel(orderDays: number[] | null | undefined, today: string): string {
  const days = (orderDays ?? []).filter((d) => d >= 1 && d <= 7);
  if (days.length === 0) return "Sin días de pedido";
  if (days.length === 7) return "Pide todos los días";
  const [y, m, d] = today.split("-").map(Number);
  const js = new Date(Date.UTC(y ?? 1970, (m ?? 1) - 1, d ?? 1)).getUTCDay();
  const iso = js === 0 ? 7 : js;
  if (days.includes(iso)) return "Hoy pide";
  for (let i = 1; i <= 7; i += 1) {
    const next = ((iso - 1 + i) % 7) + 1;
    if (days.includes(next)) return `Próximo: ${DAY_LONG[next]}`;
  }
  return "Sin días de pedido";
}
