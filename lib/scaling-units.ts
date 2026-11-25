import { TO_BASE } from "@/lib/measures";
import { LINE_UNITS, formatQuantity, type LineUnit } from "@/lib/recipe-format";

// Hacer varias recetas (ADR-0065): cada línea se multiplica en su propia unidad. Al llegar a 1.000 pasa a la mayor de
// su clase (g → kg, ml → l) y nunca de volumen a peso: por eso no hace falta la densidad. Sin React ni Supabase: la
// usan «Hacer varias recetas», la planilla de la ficha y las fichas técnicas.

export type Amount = { value: number; unit: string };

const BIGGER: Partial<Record<string, string>> = { mg: "g", g: "kg", ml: "l", cc: "l" };

// Los 6 decimales de la base, sin el error de los binarios.
const round6 = (n: number) => Math.round((n + Number.EPSILON) * 1e6) / 1e6;

/** La misma cantidad en la unidad que corresponde leer: 1.200 ml → 1,2 l. */
export function toBigger({ value, unit }: Amount): Amount {
  let out = { value: round6(value), unit };
  for (let next = BIGGER[out.unit]; next && out.value >= 1000; next = BIGGER[out.unit])
    out = { value: round6(out.value / 1000), unit: next };
  return out;
}

/** Una línea por N recetas. «No se multiplica» queda igual. Nulo si falta la cantidad o cuántas. */
export function scaleLine(
  quantity: number | null,
  unit: string,
  times: number | null,
  noScale = false,
): Amount | null {
  if (quantity === null || times === null || unit === "") return null;
  return toBigger({ value: noScale ? quantity : quantity * times, unit });
}

/** Cómo se escribe la unidad al lado del número: «unidades», «cdas», «tazas». */
export function unitText(value: number, unit: string): string {
  const label = LINE_UNITS.find((u) => u.code === unit)?.label ?? unit;
  if (value <= 1) return label;
  switch (unit) {
    case "unit":
      return "unidades";
    case "dozen":
      return "docenas";
    case "portion":
      return "porciones";
    case "pinch":
      return "pizcas";
    case "cup":
      return "tazas";
    default:
      return label;
  }
}

export function amountText({ value, unit }: Amount): string {
  return `${formatQuantity(value)} ${unitText(value, unit)}`;
}

// Desde cuántas conviene decir cuánto es: 4 cucharadas (60 ml), 6 cucharaditas (30 ml), 2 tazas (480 ml) y 10 pizcas.
const SPOON_FROM: Partial<Record<string, { from: number; base: "ml" | "g" }>> = {
  tbsp: { from: 4, base: "ml" },
  tsp: { from: 6, base: "ml" },
  cup: { from: 2, base: "ml" },
  pinch: { from: 10, base: "g" },
};

/** «120 ml» al lado de «8 cdas». En su propia clase: de una cucharada a gramos haría falta la densidad. */
export function spoonEquivalent({ value, unit }: Amount): string | null {
  const rule = SPOON_FROM[unit];
  if (!rule || value < rule.from) return null;
  return amountText(toBigger({ value: value * TO_BASE[unit as LineUnit], unit: rule.base }));
}
