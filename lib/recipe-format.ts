import type { Database } from "@/lib/database.types";

// Tipos, etiquetas y formatos del recetario, sin acceso a la base: los usan las pantallas del
// servidor y los editores del navegador (como lib/yields.ts). Las lecturas están en lib/recipes.ts.

type Recipes = Database["recipes"];
export type RecipeType = Recipes["Enums"]["recipe_type"];
export type RecipeScope = Recipes["Enums"]["recipe_scope"];
export type QuantityBasis = Recipes["Enums"]["quantity_basis"];
export type StepKind = Recipes["Enums"]["step_kind"];
export type VersionStatus = Database["core"]["Enums"]["version_status"];

export const RECIPE_TYPE_LABELS: Record<RecipeType, string> = {
  preparation: "Preparación",
  dish: "Plato",
  unit_component: "Componente unitario",
};

export const SCOPE_LABELS: Record<RecipeScope, string> = {
  group: "Maestra del grupo",
  brand: "De marca",
  restaurant: "De local",
};

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

// Unidades que se usan en las líneas de una receta (las de envase no: no tienen contenido fijo).
export const LINE_UNITS = [
  { code: "g", label: "g" },
  { code: "kg", label: "kg" },
  { code: "ml", label: "ml" },
  { code: "l", label: "l" },
  { code: "unit", label: "unidad" },
  { code: "dozen", label: "docena" },
] as const;

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
