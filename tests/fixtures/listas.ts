import ExcelJS from "exceljs";
import { PDFDocument, StandardFonts } from "pdf-lib";

// Listas de precios inventadas para las pruebas (ADR-0071). Nunca listas reales: se arman acá, en memoria.

const ROWS = [
  ["FR007", "Albahaca fresca, por kg", 1899.72, 0, 10.5],
  ["FR008", "Perejil, por kg", 2047.68, 5, 21],
  ["FR011", "Carne picada especial, por kg", 2491.56, 0, 10.5],
] as const;

// Un Excel con una portada sin encabezados y la lista en la segunda hoja, con encabezados de otro proveedor.
export async function excelFixture(): Promise<ArrayBuffer> {
  const wb = new ExcelJS.Workbook();
  const cover = wb.addWorksheet("Portada");
  cover.addRow(["Distribuidora Ejemplo (ficticia)"]);
  cover.addRow(["Lista de noviembre"]);
  const ws = wb.addWorksheet("Precios");
  ws.addRow(["Lista de precios — ficticia"]);
  ws.addRow([]);
  ws.addRow(["Cód.", "Descripción", "Precio s/IVA", "Desc. %", "Alícuota"]);
  ws.addRow(["VERDURAS"]);
  for (const r of ROWS) ws.addRow([...r]);
  ws.addRow(["", "Total", 6438.96]);
  const buf = new Uint8Array(await wb.xlsx.writeBuffer());
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;
}

// Un CSV como lo guarda Excel en castellano: «;», coma decimal, puntos de miles y comillas.
export function csvFixture(): ArrayBuffer {
  const text =
    "﻿Codigo;Articulo;Precio de lista;Bonif. 1 %;IVA\r\n" +
    'FR007;"Albahaca fresca; por kg";1.899,72;0;10,5\r\n' +
    "FR008;Perejil, por kg;2.047,68;5;21\r\n";
  return new TextEncoder().encode(text).buffer as ArrayBuffer;
}

// Un PDF hecho por computadora, con la tabla en columnas (los números alineados a la derecha).
export async function pdfFixture(withText = true): Promise<ArrayBuffer> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([595, 842]);
  if (withText) {
    const font = await doc.embedFont(StandardFonts.Helvetica);
    const head = ["Codigo", "Articulo", "Precio", "IVA"];
    const xs = [40, 120, 380, 480];
    head.forEach((t, i) => page.drawText(t, { x: xs[i] ?? 0, y: 760, size: 10, font }));
    ROWS.forEach((r, i) => {
      const y = 740 - i * 18;
      page.drawText(r[0], { x: 40, y, size: 10, font });
      page.drawText(r[1], { x: 120, y, size: 10, font });
      const price = r[2].toLocaleString("es-AR", { minimumFractionDigits: 2 });
      page.drawText(price, { x: 420 - font.widthOfTextAtSize(price, 10), y, size: 10, font });
      page.drawText(String(r[4]).replace(".", ","), { x: 480, y, size: 10, font });
    });
  } else {
    // Escaneado: solo un rectángulo, sin texto.
    page.drawRectangle({ x: 40, y: 600, width: 500, height: 200 });
  }
  const bytes = await doc.save();
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

export const PNG_HEAD = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
