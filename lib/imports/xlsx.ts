import { inflateRawSync } from "node:zlib";

import ExcelJS from "exceljs";

// Lo común a los lectores de Excel (recetario, ADR-0027; proveedores, ADR-0055): leer una celda, comparar
// encabezados y abrir el archivo con los controles de tamaño, sin confiar en la extensión.

// Topes del archivo descomprimido (revisión de seguridad, M1): un .xlsx chico puede descomprimirse en
// varios GB ("zip bomb"). El recetario real de Nonnos ocupa 53 MB descomprimido.
export const MAX_UNZIPPED_BYTES = 250 * 1024 * 1024;
const MAX_ZIP_ENTRIES = 5_000;

export type Cell = string | number | null;

// El valor de una celda: el resultado de una fórmula, el texto de un texto con formato o de un
// hipervínculo; un error de Excel (#N/A, #VALUE!), una fecha o un booleano quedan vacíos.
export function value(cell: ExcelJS.Cell | undefined): Cell {
  const v: unknown = cell?.value;
  if (v === null || v === undefined) return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string") return v.trim() === "" ? null : v.trim();
  if (v instanceof Date) return null;
  if (typeof v === "object") {
    if ("error" in v) return null;
    if ("result" in v) return value({ value: (v as { result: unknown }).result } as ExcelJS.Cell);
    if ("richText" in v) {
      const text = (v as { richText: { text: string }[] }).richText
        .map((r) => r.text)
        .join("")
        .trim();
      return text === "" ? null : text;
    }
    if ("text" in v) return value({ value: (v as { text: unknown }).text } as ExcelJS.Cell);
  }
  return null;
}

// Un texto de una línea, sin espacios de más, cortado en `max` caracteres.
export function text(v: Cell, max = 200): string | null {
  if (v === null) return null;
  const s = String(v).replace(/\s+/g, " ").trim();
  return s === "" ? null : s.slice(0, max);
}

// Para comparar encabezados y opciones: sin tildes, en minúsculas y sin espacios de más.
export function norm(v: Cell): string {
  return String(v ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

export function findSheet(wb: ExcelJS.Workbook, name: string): ExcelJS.Worksheet | undefined {
  return wb.worksheets.find((ws) => norm(ws.name) === name);
}

// Si el contenido del zip pasa el tope, antes de dárselo a ExcelJS. Primero se mira el índice
// (directorio central): cuántos archivos tiene y cuánto dice que ocupan. Pero el índice lo escribe
// quien arma el archivo y puede mentir (revisión de seguridad de ADR-0055, M1), así que después se
// descomprime cada entrada con un tope real de salida (zlib corta al pasarlo) y se suma lo que de
// verdad sale. Un zip sin índice legible, con ZIP64 (más de 4 GB) o con otra compresión que no sea
// deflate no es una planilla que esperemos.
export function zipTooLarge(file: ArrayBuffer, maxUnzipped = MAX_UNZIPPED_BYTES): boolean {
  const view = new DataView(file);
  const min = Math.max(0, file.byteLength - 22 - 65_535);
  let end = -1;
  for (let i = file.byteLength - 22; i >= min; i--) {
    if (view.getUint32(i, true) === 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) return true;
  const entries = view.getUint16(end + 10, true);
  let at = view.getUint32(end + 16, true);
  if (entries === 0xffff || at === 0xffffffff || entries > MAX_ZIP_ENTRIES) return true;
  let total = 0;
  const parts: { method: number; compressed: number; local: number }[] = [];
  for (let n = 0; n < entries; n++) {
    if (at + 46 > file.byteLength || view.getUint32(at, true) !== 0x02014b50) return true;
    const size = view.getUint32(at + 24, true);
    const compressed = view.getUint32(at + 20, true);
    const local = view.getUint32(at + 42, true);
    if (size === 0xffffffff || compressed === 0xffffffff || local === 0xffffffff) return true;
    total += size;
    if (total > maxUnzipped) return true;
    parts.push({ method: view.getUint16(at + 10, true), compressed, local });
    at +=
      46 +
      view.getUint16(at + 28, true) +
      view.getUint16(at + 30, true) +
      view.getUint16(at + 32, true);
  }
  return realSizeTooLarge(file, parts, maxUnzipped);
}

function realSizeTooLarge(
  file: ArrayBuffer,
  parts: { method: number; compressed: number; local: number }[],
  maxUnzipped: number,
): boolean {
  const view = new DataView(file);
  const bytes = new Uint8Array(file);
  let total = 0;
  for (const part of parts) {
    const at = part.local;
    if (at + 30 > file.byteLength || view.getUint32(at, true) !== 0x04034b50) return true;
    const start = at + 30 + view.getUint16(at + 26, true) + view.getUint16(at + 28, true);
    const end = start + part.compressed;
    if (end > file.byteLength) return true;
    if (part.method === 0) {
      total += part.compressed;
    } else if (part.method === 8) {
      try {
        // Nunca más de lo que queda del tope (+1, para saber si se pasó): zlib corta con un error.
        total += inflateRawSync(bytes.subarray(start, end), {
          maxOutputLength: maxUnzipped - total + 1,
        }).byteLength;
      } catch {
        return true;
      }
    } else {
      return true;
    }
    if (total > maxUnzipped) return true;
  }
  return false;
}

// Un .xlsx es un zip: empieza con "PK\x03\x04". Se mira el contenido, no la extensión.
export function looksLikeXlsx(file: ArrayBuffer): boolean {
  if (file.byteLength < 4) return false;
  const head = new Uint8Array(file, 0, 4);
  return head[0] === 0x50 && head[1] === 0x4b && head[2] === 0x03 && head[3] === 0x04;
}

export type OpenLimits = {
  maxBytes: number;
  maxUnzipped?: number;
  tooBig: string;
  tooBigInside: string;
};

// Abre el Excel con los controles de tamaño y de formato. Los mensajes van en castellano, para la pantalla.
export async function openWorkbook(
  file: ArrayBuffer,
  limits: OpenLimits,
): Promise<{ ok: true; wb: ExcelJS.Workbook } | { ok: false; message: string }> {
  if (file.byteLength === 0) return { ok: false, message: "El archivo está vacío." };
  if (file.byteLength > limits.maxBytes) return { ok: false, message: limits.tooBig };
  if (!looksLikeXlsx(file))
    return {
      ok: false,
      message:
        "El archivo no es un Excel (.xlsx). Guardalo como «Libro de Excel» y probá de nuevo.",
    };
  if (zipTooLarge(file, limits.maxUnzipped)) return { ok: false, message: limits.tooBigInside };
  const wb = new ExcelJS.Workbook();
  try {
    await wb.xlsx.load(file);
  } catch {
    return {
      ok: false,
      message: "No pudimos leer el Excel. Revisá que se abra bien y guardalo de nuevo.",
    };
  }
  return { ok: true, wb };
}
