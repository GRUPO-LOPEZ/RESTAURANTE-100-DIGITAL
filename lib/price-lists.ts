import { z } from "zod";

// Listas de precios y cola de mapeo (Fase 3, ADR-0052): reglas de la pantalla, sin acceso a la base. Se prueban con
// Vitest. La base vuelve a controlar todo (purchasing.create_price_list, resolve_article…).

export type PriceListStatus = "received" | "accepted" | "replaced" | "voided";
// «Vencida» no es un estado de la base: se calcula con la frecuencia del proveedor (purchasing.price_list_expired).
export type PriceListShownStatus = PriceListStatus | "expired";

export const PRICE_LIST_STATUS: Record<
  PriceListShownStatus,
  { label: string; status: "ok" | "info" | "none" | "warn" }
> = {
  accepted: { label: "Vigente", status: "ok" },
  received: { label: "Recibida", status: "info" },
  replaced: { label: "Reemplazada", status: "none" },
  voided: { label: "Anulada", status: "none" },
  expired: { label: "Vencida", status: "warn" },
};

export function shownStatus(status: PriceListStatus, expired: boolean): PriceListShownStatus {
  return status === "accepted" && expired ? "expired" : status;
}

// Lo que va en la dirección (?estado=) y lo que entiende purchasing.price_list_list.
export const STATUS_FILTERS = [
  { value: "accepted", label: "Vigentes" },
  { value: "received", label: "Recibidas" },
  { value: "expired", label: "Vencidas" },
  { value: "replaced", label: "Reemplazadas" },
  { value: "voided", label: "Anuladas" },
] as const;
export type StatusFilter = (typeof STATUS_FILTERS)[number]["value"];
export function isStatusFilter(value: unknown): value is StatusFilter {
  return STATUS_FILTERS.some((f) => f.value === value);
}

// Alícuotas de IVA (P5, Soy: también 2,5 % y 5 %).
export const VAT_RATES = [0, 2.5, 5, 10.5, 21, 27] as const;

export const FOUND_IN_LABELS: Record<string, string> = {
  price_list: "Lista de precios",
  invoice: "Factura",
  receipt: "Recepción",
};

// El neto, igual que purchasing.net_list_price: lista × (1 − b1) × (1 − b2) − bonificación por unidad, a 4 decimales.
// Caso 5 del plan: 100 con 15 % y 10 % da 76,50.
export function netListPrice(
  listPrice: number,
  bonus1Pct = 0,
  bonus2Pct = 0,
  bonusPerUnitAmount = 0,
): number {
  const net = listPrice * (1 - bonus1Pct / 100) * (1 - bonus2Pct / 100) - bonusPerUnitAmount;
  return Math.round(net * 10000) / 10000;
}

// Pesos con coma y dos decimales: «$ 76,50».
export function formatMoney(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—";
  return `$ ${value.toLocaleString("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

// La variación entre listas, con signo y palabra: «+8 %», «−3,5 %», «Igual». Sin anterior, «Nuevo».
export function changeLabel(pct: number | null | undefined): string {
  if (pct === null || pct === undefined || !Number.isFinite(pct)) return "Nuevo";
  if (pct === 0) return "Igual";
  const abs = Math.abs(pct).toLocaleString("es-AR", { maximumFractionDigits: 2 });
  return `${pct > 0 ? "+" : "−"}${abs} %`;
}

// Una cantidad de contenido en palabras, pasando a kg o l cuando es redonda: 50000 g → «50 kg», 500 ml → «500 ml».
export function contentWords(quantity: number, unit: "g" | "ml" | "unit"): string {
  const n = (v: number) => v.toLocaleString("es-AR", { maximumFractionDigits: 3 });
  if (unit === "unit") return quantity === 1 ? "1 unidad" : `${n(quantity)} unidades`;
  if (quantity >= 1000) return `${n(quantity / 1000)} ${unit === "g" ? "kg" : "l"}`;
  return `${n(quantity)} ${unit}`;
}

// El factor en palabras antes de confirmar (pedido del Prompt 2): «1 bolsa = 50 kg», «1 caja = 12 × 1 l (12 l)».
export function packageFactorWords(
  packageName: string,
  unitsPerPackage: number,
  contentPerUnit: number,
  contentUnit: "g" | "ml" | "unit",
): string | null {
  if (!(unitsPerPackage >= 1) || !(contentPerUnit > 0) || !packageName.trim()) return null;
  const one = `1 ${packageName.trim().toLowerCase()}`;
  if (unitsPerPackage === 1) return `${one} = ${contentWords(contentPerUnit, contentUnit)}`;
  return `${one} = ${unitsPerPackage} × ${contentWords(contentPerUnit, contentUnit)} (${contentWords(
    unitsPerPackage * contentPerUnit,
    contentUnit,
  )})`;
}

// Un número escrito a mano: acepta coma decimal y puntos de miles («1.234,50»).
export function parseDecimal(text: string): number | null {
  const clean = text.trim().replace(/\s/g, "");
  if (!clean) return null;
  const normalized = clean.includes(",") ? clean.replace(/\./g, "").replace(",", ".") : clean;
  if (!/^-?\d+(\.\d+)?$/.test(normalized)) return null;
  return Number(normalized);
}

const pct = z
  .number({ message: "Va un número." })
  .min(0, "No puede ser negativa.")
  .lt(100, "Tiene que ser menor que 100 %.");

// Un renglón de la grilla de carga. El mismo esquema en el navegador y en el servidor.
export const priceListItemSchema = z
  .object({
    name: z
      .string()
      .trim()
      .min(1, "Escribí el nombre del artículo.")
      .max(200, "Hasta 200 caracteres."),
    sku: z.string().trim().max(40, "Hasta 40 caracteres.").optional(),
    // El artículo elegido a mano («Es…»): la base controla que sea del proveedor.
    purchase_product_id: z.string().uuid().optional(),
    list_price: z.number({ message: "Va un número." }).positive("Tiene que ser mayor que cero."),
    bonus1_pct: pct,
    bonus2_pct: pct,
    bonus_per_unit_amount: z.number({ message: "Va un número." }).min(0, "No puede ser negativa."),
    vat_rate: z
      .number()
      .refine((v) => (VAT_RATES as readonly number[]).includes(v), "Elegí el IVA."),
  })
  .refine(
    (r) => netListPrice(r.list_price, r.bonus1_pct, r.bonus2_pct, r.bonus_per_unit_amount) > 0,
    {
      message: "Con esas bonificaciones el neto queda en cero o negativo.",
      path: ["bonus_per_unit_amount"],
    },
  );
export type PriceListItemInput = z.infer<typeof priceListItemSchema>;

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Elegí la fecha.");

export const priceListSchema = z.object({
  supplier_id: z.string().uuid("Elegí el proveedor."),
  received_on: isoDate,
  valid_from: isoDate,
  items: z.array(priceListItemSchema).min(1, "Cargá al menos un renglón.").max(2000),
  reason: z.string().trim().min(3, "Escribí el motivo (al menos 3 letras).").max(500),
});
export type PriceListInput = z.infer<typeof priceListSchema>;

// Corregir la vigente (ADR-0071): los renglones de la versión nueva, el motivo y si se confirmaron los «Revisar».
export const correctPriceListSchema = z.object({
  price_list_id: z.string().uuid("Falta la lista."),
  items: z.array(priceListItemSchema).min(1, "Cargá al menos un renglón.").max(2000),
  reason: z.string().trim().min(3, "Escribí el motivo (al menos 3 letras).").max(500),
  confirm_review: z.boolean(),
});

// El precio por unidad de uso, al lado del neto (decisión 23 de Soy): «$ 9.856 por kg». Sin envase, «—».
export function perUseLabel(
  price: number | null | undefined,
  unit: string | null | undefined,
): string {
  if (price === null || price === undefined || !Number.isFinite(price) || !unit) return "—";
  const digits = price >= 100 ? 0 : 2;
  return `$ ${price.toLocaleString("es-AR", { minimumFractionDigits: digits, maximumFractionDigits: digits })} por ${unit}`;
}

// Los controles de un renglón (los mismos que calcula la base: purchasing.price_line_check).
export type LineCheck = {
  changePct: number | null;
  overThreshold: boolean;
  review: boolean;
  perUsePrice: number | null;
  perUseUnit: string | null;
};
// La palabra del control: «Revisar» (10 veces), la variación («+12 %», resaltada si pasa el umbral) o «Nuevo».
export function checkBadge(c: LineCheck | null | undefined): {
  label: string;
  status: "bad" | "warn" | "ok" | "none" | "info";
} {
  if (!c) return { label: "—", status: "none" };
  if (c.review) return { label: "Revisar", status: "bad" };
  if (c.changePct === null) return { label: "Nuevo", status: "info" };
  if (c.overThreshold) return { label: changeLabel(c.changePct), status: "warn" };
  return { label: changeLabel(c.changePct), status: "none" };
}
