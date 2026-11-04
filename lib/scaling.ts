import { z } from "zod";

import type { Reliability } from "@/lib/cost-labels";
import { createClient } from "@/lib/supabase/server";

// Escalado (ADR-0032). La cuenta está en la base (recipes.scale_version y costing.scaled_cost): acá solo se lee.
const scaledSchema = z.object({
  factor: z.number(),
  exact_factor: z.number(),
  target_portions: z.number().nullable(),
  target_yield: z.number().nullable(),
  yield_unit: z.string().nullable(),
  lines: z.array(
    z.object({
      order: z.number(),
      item: z.string(),
      unit: z.string(),
      quantity: z.number(),
      scaled: z.number(),
      no_scale: z.boolean(),
    }),
  ),
  steps: z.array(
    z.object({
      number: z.number(),
      equipment: z.string(),
      capacity: z.number().nullable(),
      capacity_unit: z.string().nullable(),
      batches: z.number().nullable(),
    }),
  ),
});

export type ScaledRecipe = {
  factor: number;
  exactFactor: number;
  targetPortions: number | null;
  targetYield: number | null;
  yieldUnit: string | null;
  lines: {
    order: number;
    item: string;
    unit: string;
    quantity: number;
    scaled: number;
    noScale: boolean;
  }[];
  steps: {
    number: number;
    equipment: string;
    capacity: number | null;
    capacityUnit: string | null;
    batches: number | null;
  }[];
};

export function parseScaled(data: unknown): ScaledRecipe | null {
  const parsed = scaledSchema.safeParse(data);
  if (!parsed.success) return null;
  const d = parsed.data;
  return {
    factor: d.factor,
    exactFactor: d.exact_factor,
    targetPortions: d.target_portions,
    targetYield: d.target_yield,
    yieldUnit: d.yield_unit,
    lines: d.lines.map((l) => ({ ...l, noScale: l.no_scale })),
    steps: d.steps.map((s) => ({ ...s, capacityUnit: s.capacity_unit })),
  };
}

export type ScaleResult = { status: "ok"; data: ScaledRecipe } | { status: "bad"; message: string };

export async function scaleVersion(
  versionId: string,
  target: number,
  mode: "portions" | "yield",
  unit: string | null,
): Promise<ScaleResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("recipes").rpc("scale_version", {
    p_version_id: versionId,
    p_target: target,
    p_mode: mode,
    p_unit: unit ?? undefined,
  });
  // Las validaciones de la base ya vienen en español (objetivo, unidad).
  if (error?.code === "22023") return { status: "bad", message: error.message };
  if (error) throw new Error("No pudimos escalar la receta.");
  const scaled = parseScaled(data);
  if (!scaled) throw new Error("No pudimos escalar la receta.");
  return { status: "ok", data: scaled };
}

// El costo proyectado. Vacío si la sesión no lo puede ver en ese local.
export async function getScaledCost(
  versionId: string,
  restaurantId: string,
  factor: number,
): Promise<{ total: number | null; gross: number | null; reliability: Reliability } | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("costing").rpc("scaled_cost", {
    p_version_id: versionId,
    p_restaurant_id: restaurantId,
    p_factor: factor,
  });
  // Sin permiso en ese local no hay nada que mostrar. Otro error es un error.
  if (error?.code === "42501") return null;
  const row = data?.[0];
  if (error || !row) throw new Error("No pudimos calcular el costo proyectado.");
  return {
    reliability: row.reliability,
    total: row.total_cost === null ? null : Number(row.total_cost),
    gross: row.total_gross_cost === null ? null : Number(row.total_gross_cost),
  };
}
