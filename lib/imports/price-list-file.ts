import {
  LIST_FIELDS,
  TEMPLATE_HEADERS,
  findHeaderRow,
  parseCsv,
  rowsFromTable,
  type ColumnMap,
  type ImportCell,
  type ImportedRow,
} from "@/lib/price-list-columns";
import { looksLikeXlsx, openWorkbook, value, zipTooLarge } from "@/lib/imports/xlsx";

// Leer la lista de precios de un proveedor (ADR-0071, decisiones 12 y 17 de Soy), en el servidor y sin IA:
// - Excel (.xlsx) con exceljs, eligiendo la hoja;
// - CSV, separado por «;» o «,»;
// - PDF hecho por computadora, con pdfjs-dist: el texto de cada página agrupado en renglones por su altura y en
//   columnas por la posición de los encabezados.
// Una foto o un PDF escaneado no tienen texto: se cargan en la pantalla dividida, a mano (la lectura con el agente de
// Facturas es de la Fase 5). El archivo original queda guardado con la lista.

export const LIST_FILE_MAX_BYTES = 3.5 * 1024 * 1024;
export const LIST_MAX_ROWS = 500;
const MAX_SHEET_ROWS = 3000;
const MAX_PDF_PAGES = 30;
// Topes del texto de un PDF (revisión de seguridad): una lista de 500 renglones no llega ni cerca.
const MAX_PDF_PIECES = 50_000;
const MAX_PDF_CHARS = 500_000;

export type ListFileKind = "xlsx" | "csv" | "pdf" | "image";

export type ReadListResult =
  | {
      ok: true;
      kind: "xlsx" | "csv" | "pdf";
      sheets: string[];
      sheet: string | null;
      // La tabla tal como vino (hasta 500 filas debajo del encabezado), para cambiar la columna de un dato.
      header: string[];
      table: ImportCell[][];
      map: ColumnMap;
      rows: ImportedRow[];
      skipped: number;
      truncated: boolean;
    }
  // Sin texto (foto o PDF escaneado): la pantalla dividida.
  | { ok: false; scanned: true; kind: "image" | "pdf"; message: string }
  | { ok: false; scanned?: false; message: string };

// Qué es el archivo por su contenido (no por la extensión ni por lo que dice el navegador).
export function listFileKind(head: Uint8Array, name: string): ListFileKind | null {
  const ascii = (from: number, to: number) => String.fromCharCode(...head.slice(from, to));
  if (ascii(0, 4) === "%PDF") return "pdf";
  if (head[0] === 0x50 && head[1] === 0x4b && head[2] === 0x03 && head[3] === 0x04) return "xlsx";
  if (head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return "image";
  if (head[0] === 0x89 && ascii(1, 4) === "PNG") return "image";
  if (ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return "image";
  // Un CSV es texto: sin bytes de control (salvo saltos y tabulación) y con la extensión que corresponde.
  if (/\.csv$/i.test(name) && isPlainText(head)) return "csv";
  return null;
}

// Texto sin bytes de control (salvo tabulación y saltos). Para el CSV se controla el archivo entero.
export function isPlainText(bytes: Uint8Array): boolean {
  return !bytes.some((b) => b < 9 || (b > 13 && b < 32) || b === 127);
}

// El archivo que se guarda con la lista (decisión 12): qué es por su contenido entero y con qué extensión y tipo se
// guarda. Una sola regla para leer y para guardar (revisión de seguridad).
export function keptFile(
  bytes: ArrayBuffer,
  name: string,
): { ext: "jpg" | "png" | "webp" | "pdf" | "xlsx" | "csv"; contentType: string } | null {
  const head = new Uint8Array(bytes.slice(0, 16));
  const kind = listFileKind(head, name);
  if (kind === "pdf") return { ext: "pdf", contentType: "application/pdf" };
  if (kind === "xlsx")
    return looksLikeXlsx(bytes) && !zipTooLarge(bytes, 60 * 1024 * 1024)
      ? { ext: "xlsx", contentType: XLSX_TYPE }
      : null;
  if (kind === "csv")
    return isPlainText(new Uint8Array(bytes)) ? { ext: "csv", contentType: "text/csv" } : null;
  if (kind === "image") {
    if (head[0] === 0xff) return { ext: "jpg", contentType: "image/jpeg" };
    if (head[0] === 0x89) return { ext: "png", contentType: "image/png" };
    return { ext: "webp", contentType: "image/webp" };
  }
  return null;
}
const XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

function fromTable(
  kind: "xlsx" | "csv" | "pdf",
  table: ImportCell[][],
  sheets: string[],
  sheet: string | null,
): ReadListResult {
  const found = findHeaderRow(table);
  if (!found)
    return {
      ok: false,
      message:
        "No encontramos los encabezados (al menos «Artículo» y «Precio»). Probá con la planilla modelo o cargala a mano.",
    };
  const { rows, skipped, truncated } = rowsFromTable(table, found.index, found.map, LIST_MAX_ROWS);
  if (rows.length === 0)
    return { ok: false, message: "La lista no tiene renglones con artículo y precio." };
  return {
    ok: true,
    kind,
    sheets,
    sheet,
    header: (table[found.index] ?? []).map((c) => String(c ?? "")),
    table: table.slice(found.index + 1, found.index + 1 + LIST_MAX_ROWS + skipped),
    map: found.map,
    rows,
    skipped,
    truncated,
  };
}

async function readXlsx(file: ArrayBuffer, sheetName?: string): Promise<ReadListResult> {
  const opened = await openWorkbook(file, {
    maxBytes: LIST_FILE_MAX_BYTES,
    maxUnzipped: 60 * 1024 * 1024,
    tooBig: "El archivo pesa más de 3,5 MB.",
    tooBigInside:
      "El Excel es demasiado grande por dentro: probá guardando solo la hoja de la lista.",
  });
  if (!opened.ok) return { ok: false, message: opened.message };
  const sheets = opened.wb.worksheets.map((w) => w.name);
  const toTable = (ws: (typeof opened.wb.worksheets)[number]) => {
    const table: ImportCell[][] = [];
    for (let r = 1; r <= Math.min(ws.rowCount, MAX_SHEET_ROWS); r++) {
      const row = ws.getRow(r);
      const cells: ImportCell[] = [];
      for (let c = 1; c <= Math.min(row.cellCount, 40); c++) cells.push(value(row.getCell(c)));
      table.push(cells);
    }
    return table;
  };
  // La hoja elegida o, si no, la primera que tenga encabezados.
  const chosen =
    opened.wb.worksheets.find((w) => w.name === sheetName) ??
    opened.wb.worksheets.find((w) => findHeaderRow(toTable(w))) ??
    opened.wb.worksheets[0];
  if (!chosen) return { ok: false, message: "El Excel no tiene hojas." };
  return fromTable("xlsx", toTable(chosen), sheets, chosen.name);
}

type PdfItem = { str: string; x: number; y: number; w: number };

// El texto de un PDF, en renglones (por altura) y columnas (por la posición de los encabezados).
async function readPdf(file: ArrayBuffer): Promise<ReadListResult> {
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  // Sin fuentes del sistema, scripts, formularios XFA ni dibujo: solo el texto. Se corta ante el primer error.
  const task = pdfjs.getDocument({
    data: new Uint8Array(file),
    disableFontFace: true,
    useSystemFonts: false,
    stopAtErrors: true,
    isOffscreenCanvasSupported: false,
    enableXfa: false,
    verbosity: 0,
  });
  const lines: PdfItem[][] = [];
  let chars = 0;
  let pieces = 0;
  // El documento se cierra siempre, salga bien o mal (si no, queda en memoria).
  try {
    let doc;
    try {
      doc = await task.promise;
    } catch {
      return {
        ok: false,
        message: "No pudimos abrir el PDF: probá con otro o cargá la lista a mano.",
      };
    }
    for (let p = 1; p <= Math.min(doc.numPages, MAX_PDF_PAGES); p++) {
      const page = await doc.getPage(p);
      const content = await page.getTextContent();
      const items: PdfItem[] = [];
      for (const it of content.items) {
        if (!("str" in it) || !it.str.trim()) continue;
        chars += it.str.trim().length;
        pieces++;
        // Un PDF con demasiado texto no es una lista de precios: se corta antes de cargar la memoria.
        if (pieces > MAX_PDF_PIECES || chars > MAX_PDF_CHARS)
          return {
            ok: false,
            message: "El PDF tiene demasiado texto para ser una lista: cargala en Excel o a mano.",
          };
        items.push({ str: it.str.trim(), x: it.transform[4], y: it.transform[5], w: it.width });
      }
      // De arriba hacia abajo; un renglón junta lo que está a menos de 3 puntos de altura.
      items.sort((a, b) => b.y - a.y || a.x - b.x);
      const pageLines: PdfItem[][] = [];
      for (const it of items) {
        const last = pageLines[pageLines.length - 1];
        if (last?.[0] && Math.abs(last[0].y - it.y) < 3) last.push(it);
        else pageLines.push([it]);
      }
      lines.push(...pageLines);
    }
  } catch {
    return {
      ok: false,
      message: "No pudimos leer el PDF: probá con otro o cargá la lista a mano.",
    };
  } finally {
    await task.destroy();
  }
  if (chars < 20)
    return {
      ok: false,
      scanned: true,
      kind: "pdf",
      message: "El PDF no tiene texto (está escaneado): cargá los renglones mirando el archivo.",
    };
  // Cada renglón en celdas: dos textos separados por menos de 4 puntos son la misma celda.
  const cellsOf = (line: PdfItem[]) => {
    const sorted = [...line].sort((a, b) => a.x - b.x);
    const cells: PdfItem[] = [];
    for (const it of sorted) {
      const prev = cells[cells.length - 1];
      if (prev && it.x - (prev.x + prev.w) < 4) {
        prev.str = `${prev.str} ${it.str}`;
        prev.w = it.x + it.w - prev.x;
      } else cells.push({ ...it });
    }
    return cells;
  };
  const merged = lines.map(cellsOf);
  const asText = merged.map((cells) => cells.map((c) => c.str as ImportCell));
  const found = findHeaderRow(asText);
  if (!found) return fromTable("pdf", asText, [], null);
  // Las columnas salen del encabezado: cada texto va a la columna cuyo centro está más cerca del suyo.
  const header = merged[found.index] ?? [];
  const centers = header.map((h) => h.x + h.w / 2);
  const table: ImportCell[][] = merged.map((cells, i) => {
    if (i <= found.index) return cells.map((c) => c.str);
    const row: ImportCell[] = header.map(() => null);
    for (const c of cells) {
      const center = c.x + c.w / 2;
      let best = 0;
      centers.forEach((h, k) => {
        if (Math.abs(h - center) < Math.abs((centers[best] ?? 0) - center)) best = k;
      });
      row[best] = row[best] === null ? c.str : `${row[best]} ${c.str}`;
    }
    return row;
  });
  return fromTable("pdf", table, [], null);
}

export async function readPriceListFile(
  file: ArrayBuffer,
  name: string,
  sheet?: string,
): Promise<ReadListResult> {
  if (file.byteLength === 0) return { ok: false, message: "El archivo está vacío." };
  if (file.byteLength > LIST_FILE_MAX_BYTES)
    return { ok: false, message: "El archivo pesa más de 3,5 MB." };
  const kind = listFileKind(new Uint8Array(file.slice(0, 16)), name);
  if (kind === null)
    return {
      ok: false,
      message:
        "Ese archivo no lo leemos. Subí un Excel (.xlsx), un CSV, un PDF o una foto. Si es un Excel viejo (.xls), guardalo como «Libro de Excel».",
    };
  if (kind === "image")
    return {
      ok: false,
      scanned: true,
      kind: "image",
      message: "Es una foto: cargá los renglones mirándola.",
    };
  if (kind === "xlsx") return readXlsx(file, sheet);
  if (kind === "csv") {
    const text = new TextDecoder("utf-8").decode(file);
    return fromTable("csv", parseCsv(text).slice(0, MAX_SHEET_ROWS), [], null);
  }
  return readPdf(file);
}

// La planilla modelo para los proveedores (decisión 22 de Soy): nuestras columnas, en el orden de la carga, con un
// renglón de ejemplo inventado. Se reconoce sola al subirla (Vitest).
export async function buildPriceListTemplate(supplierName: string): Promise<Buffer> {
  const ExcelJS = (await import("exceljs")).default;
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Lista de precios");
  ws.addRow([`Lista de precios de ${supplierName}`]);
  ws.addRow([
    "Un renglón por artículo. Precios sin IVA, en pesos. Borrá el ejemplo antes de mandarla.",
  ]);
  ws.addRow([]);
  const header = ws.addRow(LIST_FIELDS.map((f) => TEMPLATE_HEADERS[f]));
  header.font = { bold: true };
  ws.addRow(["Ejemplo: tomate perita, cajón de 18 kg", "TOM-18", 21500, 5, 0, 0, 21]);
  ws.columns = [
    { width: 44 },
    { width: 14 },
    { width: 16 },
    { width: 18 },
    { width: 18 },
    { width: 26 },
    { width: 10 },
  ];
  ws.views = [{ state: "frozen", ySplit: 4 }];
  return Buffer.from(await wb.xlsx.writeBuffer());
}
