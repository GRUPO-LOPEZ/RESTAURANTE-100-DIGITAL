import { z } from "zod";

import { createClient } from "@/lib/supabase/server";

// Buscador de la planilla de la ficha: desde 3 letras, materias primas (por nombre, alias o código) y preparaciones con
// versión vigente al alcance de la receta (ADR-0025). Lee con la sesión de la persona: la base decide qué ve. Un error se
// informa como error (no como "no hay resultados"). Se usa desde una ruta GET (ADR-0047): las acciones de servidor se
// corren de a una y la búsqueda quedaba esperando detrás del cálculo de la planilla.
export type ComponentFound = { id: string; name: string; code: string; unit: string };
export type ComponentSearch =
  | { status: "ok"; ingredients: ComponentFound[]; preparations: ComponentFound[] }
  | { status: "error" };

export async function searchComponents(
  query: unknown,
  recipeId: unknown,
): Promise<ComponentSearch> {
  const text = z.string().max(200).safeParse(query);
  const recipe = z.string().uuid().safeParse(recipeId);
  if (!text.success || !recipe.success) return { status: "error" };
  const q = text.data
    .replace(/[^\p{L}\p{N} -]/gu, "")
    .trim()
    .slice(0, 60);
  if (q.length < 3) return { status: "ok", ingredients: [], preparations: [] };
  const supabase = await createClient();
  const [ingredients, preparations] = await Promise.all([
    supabase.schema("catalog").rpc("search_components", { p_query: q, p_limit: 12 }),
    supabase
      .schema("recipes")
      .rpc("search_subrecipes", { p_query: q, p_recipe_id: recipe.data, p_limit: 12 }),
  ]);
  if (ingredients.error || preparations.error) return { status: "error" };
  return {
    status: "ok",
    ingredients: ingredients.data
      .filter((c) => c.kind === "ingredient")
      .map((c) => ({ id: c.id, name: c.name, code: c.code, unit: c.unit })),
    preparations: preparations.data.map((p) => ({
      id: p.id,
      name: p.name,
      code: p.code,
      unit: p.unit,
    })),
  };
}
