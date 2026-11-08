"use server";

import { z } from "zod";

import { reportDefinition } from "@/lib/report-labels";
import { logReport } from "@/lib/reports";

const uuid = z.string().uuid();

// Imprimir también saca información del sistema: queda en el registro antes de abrir el diálogo.
export async function logReportPrint(
  reportKey: string,
  restaurantId: string,
  rows: number,
  recipeId?: string,
): Promise<boolean> {
  const report = reportDefinition(reportKey);
  const place = uuid.safeParse(restaurantId);
  const count = z.number().int().min(0).safeParse(rows);
  const recipe = uuid.optional().safeParse(recipeId);
  if (!report || !place.success || !count.success || !recipe.success) return false;
  // Una ficha es de una receta: la base controla que sea del local.
  return logReport(report.key, place.data, "pdf", count.data, undefined, recipe.data);
}
