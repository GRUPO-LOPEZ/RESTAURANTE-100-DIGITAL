import type { Database } from "@/lib/database.types";

// Tipos, etiquetas y formatos del recetario, sin acceso a la base: los usan las pantallas del
// servidor y los editores del navegador (como lib/yields.ts). Las lecturas están en lib/recipes.ts.

type Recipes = Database["recipes"];
export type RecipeType = Recipes["Enums"]["recipe_type"];
export type RecipeScope = Recipes["Enums"]["recipe_scope"];
export type QuantityBasis = Recipes["Enums"]["quantity_basis"];
export type StepKind = Recipes["Enums"]["step_kind"];
export type VersionStatus = Database["core"]["Enums"]["version_status"];

// Solo platos y preparaciones (pedido de Soy, ADR-0041): los componentes por unidad que ya existían se muestran como
// preparaciones; la base ya no los crea.
export const RECIPE_TYPE_LABELS: Record<RecipeType, string> = {
  preparation: "Preparación",
  dish: "Plato",
  unit_component: "Preparación",
};

// Los tipos que se ofrecen al crear una receta, en este orden.
export const NEW_RECIPE_TYPES = ["dish", "preparation"] as const satisfies readonly RecipeType[];
export type NewRecipeType = (typeof NEW_RECIPE_TYPES)[number];

export const SCOPE_LABELS: Record<RecipeScope, string> = {
  group: "Maestra del grupo",
  brand: "De marca",
  restaurant: "De local",
};

// Filtro de la lista: las variantes de local (ADR-0025).
export const VARIANT_FILTER_LABEL = "Variantes de local";

export const VERSION_STATUS_LABELS: Record<VersionStatus, string> = {
  draft: "Borrador",
  in_review: "En revisión",
  approved: "Aprobada",
  published: "Vigente",
  archived: "Archivada",
};

export const BASIS_LABELS: Record<QuantityBasis, string> = {
  purchase: "Peso de compra",
  clean: "Limpio",
  cooked: "Cocido",
  finished: "Terminado",
};

export const STEP_KIND_LABELS: Record<StepKind, string> = {
  preparation: "Preparación",
  cooking: "Cocción",
  resting: "Reposo",
  fermentation: "Fermentación",
  cooling: "Enfriamiento",
  regeneration: "Regeneración",
  plating: "Emplatado",
  other: "Otro",
};

export const ALLERGEN_LABELS: Record<string, string> = {
  contains: "Contiene",
  may_contain: "Puede contener (trazas)",
  free_verified: "No contiene (verificado)",
  not_verified: "No verificado",
};

// Unidades que se usan en las líneas y el rendimiento de una receta (las de envase no: no tienen contenido fijo).
// Son las de catalog.units (migraciones 20261028120100 y 20261126120000, ADR-0040): la base hace las conversiones;
// acá van el código, la abreviatura (label, la que acompaña a las cantidades), el nombre largo y la dimensión.
// Los desplegables muestran «Kilogramo (kg)» (unitOptionLabel), agrupados por dimensión.
export const LINE_UNITS = [
  { code: "g", label: "g", name: "Gramo", dimension: "mass" },
  { code: "kg", label: "kg", name: "Kilogramo", dimension: "mass" },
  { code: "mg", label: "mg", name: "Miligramo", dimension: "mass" },
  { code: "lb", label: "lb", name: "Libra", dimension: "mass" },
  { code: "oz", label: "oz", name: "Onza", dimension: "mass" },
  { code: "pinch", label: "pizca", name: "Pizca", dimension: "mass" },
  { code: "ml", label: "ml", name: "Mililitro", dimension: "volume" },
  { code: "l", label: "l", name: "Litro", dimension: "volume" },
  { code: "cc", label: "cc", name: "Centímetro cúbico", dimension: "volume" },
  { code: "cup", label: "taza", name: "Taza", dimension: "volume" },
  { code: "tbsp", label: "cda", name: "Cucharada", dimension: "volume" },
  { code: "tsp", label: "cdta", name: "Cucharadita", dimension: "volume" },
  { code: "fl_oz", label: "fl oz", name: "Onza líquida", dimension: "volume" },
  { code: "unit", label: "unidad", name: "Unidad", dimension: "count" },
  { code: "dozen", label: "docena", name: "Docena", dimension: "count" },
  { code: "portion", label: "porción", name: "Porción", dimension: "count" },
] as const;

export type LineUnit = (typeof LINE_UNITS)[number]["code"];
export type UnitDimension = (typeof LINE_UNITS)[number]["dimension"];
// Los códigos, para los esquemas de Zod (el mismo en el navegador y en el servidor).
export const LINE_UNIT_CODES = LINE_UNITS.map((u) => u.code) as [LineUnit, ...LineUnit[]];

export const DIMENSION_LABELS: Record<UnitDimension, string> = {
  mass: "Peso",
  volume: "Volumen",
  count: "Unidades",
};

// «Kilogramo (kg)». Una unidad desconocida se muestra con su código.
export function unitOptionLabel(code: string): string {
  const u = LINE_UNITS.find((x) => x.code === code);
  if (!u) return code;
  return u.name.toLowerCase() === u.label ? u.name : `${u.name} (${u.label})`;
}

// Las unidades agrupadas por dimensión, para los <optgroup> de los desplegables.
export function unitGroups(
  only?: UnitDimension | null,
): { dimension: UnitDimension; label: string; units: (typeof LINE_UNITS)[number][] }[] {
  return (["mass", "volume", "count"] as const)
    .filter((d) => !only || d === only)
    .map((d) => ({
      dimension: d,
      label: DIMENSION_LABELS[d],
      units: LINE_UNITS.filter((u) => u.dimension === d),
    }));
}

// La unidad sugerida para una línea de preparación: la del rendimiento, en la unidad chica de su
// dimensión (una salsa que rinde kilos se usa en gramos). Sin rendimiento, gramos.
export function lineUnitForYield(yieldUnit: string | null): LineUnit {
  switch (unitDimension(yieldUnit ?? "")) {
    case "volume":
      return "ml";
    case "count":
      return "unit";
    default:
      return "g";
  }
}

// De qué se trata una unidad de línea: peso, volumen o unidades (se convierten solo dentro de su tipo).
export function unitDimension(unit: string): UnitDimension | null {
  return LINE_UNITS.find((u) => u.code === unit)?.dimension ?? null;
}

// Formatos para la cocina: "1,5 kg", "1 h 30 min".
const quantityFormat = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 3 });
export function formatQuantity(value: number | null): string {
  return value == null ? "—" : quantityFormat.format(value);
}
export function formatMinutes(minutes: number): string {
  if (minutes <= 0) return "0 min";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return h === 0 ? `${m} min` : m === 0 ? `${h} h` : `${h} h ${m} min`;
}

export type MediaKind = Recipes["Enums"]["media_kind"];

export const MEDIA_KIND_LABELS: Record<MediaKind, string> = {
  final_product: "Producto final",
  plating: "Emplatado",
  raw_material: "Materia prima",
  step: "Paso",
  critical_point: "Punto crítico",
  correct_example: "Ejemplo correcto",
  incorrect_example: "Ejemplo incorrecto",
};

// Tipos de imagen que acepta el bucket (lo mismo controla la base).
export const PHOTO_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export const PHOTO_MAX_BYTES = 3 * 1024 * 1024;
