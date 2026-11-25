import type { MediaKind } from "@/lib/recipe-format";

// Las 4 fichas técnicas de una receta (pedido de Soy, ADR-0065). Sin React ni Supabase.
export const RECIPE_CARDS = [
  { key: "completa", label: "Completa", purpose: "para capacitar" },
  { key: "servicio", label: "Servicio", purpose: "ingredientes y medidas" },
  { key: "foto", label: "Foto", purpose: "cómo queda" },
  { key: "procedimiento", label: "Procedimiento", purpose: "paso a paso" },
] as const;

export type RecipeCardKey = (typeof RECIPE_CARDS)[number]["key"];

/** La ficha de la dirección (?ver=). Cualquier otra cosa es la Completa. */
export function recipeCardKey(value: string | undefined): RecipeCardKey {
  return RECIPE_CARDS.find((c) => c.key === value)?.key ?? "completa";
}

export function recipeCardHref(recipeId: string, key: RecipeCardKey): string {
  return key === "completa"
    ? `/recetas/${recipeId}/fichas`
    : `/recetas/${recipeId}/fichas?ver=${key}`;
}

// La foto que representa a la receta: el producto final, si no el emplatado, si no la primera que haya.
const MAIN_PHOTO: MediaKind[] = ["final_product", "plating"];
export function mainPhoto<T extends { kind: MediaKind }>(photos: T[]): T | null {
  for (const kind of MAIN_PHOTO) {
    const found = photos.find((p) => p.kind === kind);
    if (found) return found;
  }
  return photos[0] ?? null;
}

/** «después del paso 1», «después de los pasos 1 y 3». */
export function afterSteps(steps: number[]): string | null {
  if (steps.length === 0) return null;
  if (steps.length === 1) return `después del paso ${steps[0]}`;
  return `después de los pasos ${steps.slice(0, -1).join(", ")} y ${steps.at(-1)}`;
}
