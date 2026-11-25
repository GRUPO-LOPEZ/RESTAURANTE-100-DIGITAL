import { LINE_UNITS, formatQuantity, type LineUnit, type UnitDimension } from "@/lib/recipe-format";

// Medida práctica de cada ingrediente (ADR-0064): «480 g · 4 nidos». La cuenta es la misma que la de la base
// (recipes.measure_count_for), que es la que manda al guardar: peso con peso, volumen con volumen, unidades con unidades;
// peso con unidades solo con el peso por unidad de la materia prima. Nunca con la densidad. Sin React ni Supabase.

export type ContentUnit = "ml" | "g" | "unit";
export type Measure = {
  id: string;
  name: string;
  content: number;
  unit: ContentUnit;
  isActive: boolean;
};

const CONTENT_DIMENSION: Record<ContentUnit, UnitDimension> = {
  ml: "volume",
  g: "mass",
  unit: "count",
};

// Cuánto vale cada unidad en la base de su clase (los factores de catalog.unit_conversions).
export const TO_BASE: Record<LineUnit, number> = {
  g: 1,
  kg: 1000,
  mg: 0.001,
  lb: 453.59237,
  oz: 28.349523,
  pinch: 0.5,
  ml: 1,
  l: 1000,
  cc: 1,
  cup: 240,
  tbsp: 15,
  tsp: 5,
  fl_oz: 29.57353,
  unit: 1,
  dozen: 12,
  portion: 1,
};

function dimensionOf(unit: string): UnitDimension | null {
  return LINE_UNITS.find((u) => u.code === unit)?.dimension ?? null;
}

// Por cuánto se multiplica para pasar de la clase de la línea a la de la medida. Nulo si no se puede.
function bridge(from: UnitDimension, to: UnitDimension, unitWeight: number | null): number | null {
  if (from === to) return 1;
  if (unitWeight === null || unitWeight <= 0) return null;
  if (from === "count" && to === "mass") return unitWeight;
  if (from === "mass" && to === "count") return 1 / unitWeight;
  return null;
}

/** Cuántas medidas son una cantidad, con 2 decimales y nunca cero. Nulo si no se puede o falta la cantidad. */
export function measureCount(
  quantity: number | null,
  unit: string,
  measure: Pick<Measure, "content" | "unit">,
  unitWeight: number | null,
): number | null {
  const from = dimensionOf(unit);
  if (quantity === null || quantity <= 0 || from === null || measure.content <= 0) return null;
  const per = bridge(from, CONTENT_DIMENSION[measure.unit], unitWeight);
  if (per === null) return null;
  const n = (quantity * TO_BASE[unit as LineUnit] * per) / measure.content;
  // El redondeo de la base: a la mitad, para arriba (sin el error de los decimales binarios).
  return Math.max(Math.round((n + Number.EPSILON) * 100) / 100, 0.01);
}

/** Las medidas que se ofrecen para una línea: las activas de su clase, y la que ya tiene aunque esté inactiva. */
export function measuresFor(
  measures: Measure[],
  unit: string,
  unitWeight: number | null,
  current: string,
): Measure[] {
  const from = dimensionOf(unit);
  if (from === null) return measures.filter((m) => m.id === current);
  return measures.filter(
    (m) =>
      (m.isActive || m.id === current) &&
      bridge(from, CONTENT_DIMENSION[m.unit], unitWeight) !== null,
  );
}

const SHORT: Record<ContentUnit, string> = { ml: "ml", g: "g", unit: "u" };

/** «Nido de pasta (120 g)». */
export function measureLabel(m: Pick<Measure, "name" | "content" | "unit" | "isActive">): string {
  return `${m.name} (${formatQuantity(m.content)} ${SHORT[m.unit]})${m.isActive ? "" : " · inactiva"}`;
}

// El plural de la primera palabra, si se puede sin inventar: «Nido de pasta» → «nidos de pasta». Un nombre con un adjetivo
// («Taza chica») o un código («GN 1/1») queda como está escrito: null.
function pluralName(name: string): string | null {
  const m = /^([A-ZÁÉÍÓÚÑ]?[a-záéíóúñ]{2,})((?: (?:de|del|para|con) .+)?)$/.exec(name.trim());
  if (!m || m[1] === undefined) return null;
  const word = m[1].toLowerCase();
  const plural = word.endsWith("ón")
    ? `${word.slice(0, -2)}ones`
    : /[aeiouáéó]$/.test(word)
      ? `${word}s`
      : word.endsWith("z")
        ? `${word.slice(0, -1)}ces`
        : /[dr]$/.test(word)
          ? `${word}es`
          : null;
  return plural === null ? null : plural + (m[2] ?? "");
}

/** «4 nidos de pasta»: cuántas van, para el cocinero. Si el nombre no se puede pasar a plural: «4 × Taza chica». */
export function measureText(count: number | null, name: string | null): string | null {
  if (count === null || !name) return null;
  const plural = pluralName(name);
  if (plural === null) return `${formatQuantity(count)} × ${name}`;
  return `${formatQuantity(count)} ${count > 1 ? plural : name.charAt(0).toLowerCase() + name.slice(1)}`;
}

/** «48 nidos de pasta de 120 g»: con lo que contiene cada una. */
export function measureWithContent(
  count: number | null,
  name: string | null,
  content: number | null,
  unit: string | null,
): string | null {
  const text = measureText(count, name);
  if (text === null || content === null || unit === null || !isContentUnit(unit)) return text;
  return `${text} de ${formatQuantity(content)} ${SHORT[unit]}`;
}

export function isContentUnit(value: string): value is ContentUnit {
  return value === "ml" || value === "g" || value === "unit";
}
