import ExcelJS from "exceljs";

import { csvCell, csvNumber, safeText } from "@/lib/csv";
import { formatValue, type ReportDefinition, type ReportRow } from "@/lib/report-labels";

// Los archivos de un reporte. Solo en el servidor: el navegador no carga ExcelJS (ADR-0027).
export type ReportHeader = {
  place: string;
  generated: string;
  period?: string;
  note?: string;
  summary?: string[];
};

// Excel en español abre un CSV separado por punto y coma, y los números llevan coma decimal.
const SEPARATOR = ";";

function headerLines(report: ReportDefinition, header: ReportHeader): string[] {
  return [
    report.title,
    `Local: ${header.place}`,
    `Fecha de los datos: ${header.generated}`,
    ...(header.summary ?? []),
    ...(header.period ? [`Período: ${header.period}`] : []),
    ...(header.note ? [header.note] : []),
  ];
}

export function reportCsv(
  report: ReportDefinition,
  header: ReportHeader,
  rows: ReportRow[],
): string {
  const lines = [
    ...headerLines(report, header).map((l) => csvCell(l)),
    "",
    report.columns.map((c) => csvCell(c.label)).join(SEPARATOR),
    ...rows.map((row) =>
      report.columns
        .map((c) => {
          const text = formatValue(row[c.key] ?? null, c.kind);
          return c.kind === "text" ? csvCell(text) : csvNumber(text);
        })
        .join(SEPARATOR),
    ),
  ];
  // Con BOM, para que Excel lea bien los acentos.
  return `﻿${lines.join("\r\n")}\r\n`;
}

export async function reportXlsx(
  report: ReportDefinition,
  header: ReportHeader,
  rows: ReportRow[],
): Promise<ArrayBuffer> {
  const book = new ExcelJS.Workbook();
  const sheet = book.addWorksheet(report.title.slice(0, 31));
  for (const line of headerLines(report, header)) sheet.addRow([safeText(line)]);
  sheet.addRow([]);
  const head = sheet.addRow(report.columns.map((c) => c.label));
  head.font = { bold: true };
  for (const row of rows) {
    sheet.addRow(
      report.columns.map((c) => {
        const value = row[c.key] ?? null;
        if (value === null) return null;
        // Los números van como números, para poder sumarlos. Lo demás, como se ve en pantalla.
        if (c.kind === "date") return formatValue(value, c.kind);
        if (c.kind === "text") return safeText(String(value));
        return Number(value);
      }),
    );
  }
  report.columns.forEach((c, i) => {
    sheet.getColumn(i + 1).width = c.kind === "text" ? 32 : 16;
  });
  const buffer = await book.xlsx.writeBuffer();
  return buffer as unknown as ArrayBuffer;
}
