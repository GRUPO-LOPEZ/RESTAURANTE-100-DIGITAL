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
): Promise<boolean> {
  const report = reportDefinition(reportKey);
  const place = uuid.safeParse(restaurantId);
  const count = z.number().int().min(0).safeParse(rows);
  if (!report || !place.success || !count.success) return false;
  return logReport(report.key, place.data, "pdf", count.data);
}
