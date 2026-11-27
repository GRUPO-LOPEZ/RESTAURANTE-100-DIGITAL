import { VAT_RATES } from "@/lib/price-lists";

// Importar una lista de precios (ADR-0071): reconocer las columnas de la planilla del proveedor y pasar sus filas a los
// renglones de la carga. Sin acceso a la base ni a Node: lo usan el navegador (para cambiar la columna de un dato) y el
// servidor (al leer el archivo). Se prueba con Vitest. La base vuelve a controlar todo al cargar.

export type ImportCell = string | number | null;

// Los datos de un renglón de lista, como los escribe la persona en la planilla de carga.
export const LIST_FIELDS = ["name", "sku", "list", "b1", "b2", "perUnit", "vat"] as const;
export type ListField = (typeof LIST_FIELDS)[number];
export const LIST_FIELD_LABELS: Record<ListField, string> = {
  name: "Artículo",
  sku: "Código",
  list: "Precio de lista",
  b1: "Bonif. 1 %",
  b2: "Bonif. 2 %",
  perUnit: "Bonif. $ por unidad",
  vat: "IVA",
};
export type ColumnMap = Partial<Record<ListField, number>>;

// Las columnas de la planilla modelo (la que se descarga desde la ficha del proveedor), en orden.
export const TEMPLATE_HEADERS: Record<ListField, string> = {
  name: "Artículo",
  sku: "Código",
  list: "Precio de lista",
  b1: "Bonificación 1 %",
  b2: "Bonificación 2 %",
  perUnit: "Bonificación $ por unidad",
  vat: "IVA %",
};

// Un encabezado sin acentos, en minúsculas, sin signos y con un solo espacio.
export function headerKey(v: ImportCell): string {
  return String(v ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9%$]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// Qué dato es una columna por su encabezado. El orden importa: «bonif $» antes que «bonif»; «bonif 2» antes que la 1.
const PATTERNS: [ListField, RegExp][] = [
  [
    "perUnit",
    /^(bonif\w*|descuento|desc|dto)\s*(en\s*)?\$|\$\s*por\s*unidad|^bonificacion \$ por unidad/,
  ],
  ["b2", /^(bonif\w*|descuento|desc|dto)\s*(%\s*)?2\b|^bonificacion 2/],
  ["b1", /^(bonif\w*|descuento|desc|dto)(\s*%)?(\s*1)?(\s*%)?$|^bonificacion 1/],
  ["vat", /^(iva|alicuota|% iva|iva %)(\b|$)/],
  ["sku", /^(cod\w*|sku|art n|n art|ref\w*)(\b|$)/],
  ["list", /^(precio|p lista|importe|valor|\$ ?unit\w*|unitario)(\b|$)/],
  ["name", /^(articulo|descripcion|producto|detalle|item|nombre|concepto)(\b|$)/],
];

export function fieldOfHeader(v: ImportCell): ListField | null {
  const key = headerKey(v);
  if (!key) return null;
  for (const [field, re] of PATTERNS) if (re.test(key)) return field;
  return null;
}

// La fila de encabezados: la primera de las 15 primeras con al menos el artículo y el precio. Devuelve su índice y qué
// columna es cada dato (la primera que aparece de cada uno).
export function findHeaderRow(rows: ImportCell[][]): { index: number; map: ColumnMap } | null {
  for (let r = 0; r < Math.min(15, rows.length); r++) {
    const map: ColumnMap = {};
    (rows[r] ?? []).forEach((cell, c) => {
      const field = fieldOfHeader(cell);
      if (field && map[field] === undefined) map[field] = c;
    });
    if (map.name !== undefined && map.list !== undefined) return { index: r, map };
  }
  return null;
}

// Un número como lo escribe un proveedor de acá: «1.234,56», «1234,56», «1.234» (miles), «1234.56», «$ 1.234», «10 %».
export function readImportNumber(v: ImportCell): number | null {
  if (v === null) return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  let s = v.replace(/[\s$%]/g, "").replace(/^ARS/i, "");
  if (!s) return null;
  if (s.includes(",") && s.includes(".")) {
    // El último separador es el decimal.
    s =
      s.lastIndexOf(",") > s.lastIndexOf(".")
        ? s.replace(/\./g, "").replace(",", ".")
        : s.replace(/,/g, "");
  } else if (s.includes(",")) {
    s =
      /^-?\d{1,3}(,\d{3})+$/.test(s) && !/,\d{1,2}$/.test(s)
        ? s.replace(/,/g, "")
        : s.replace(",", ".");
  } else if (/^-?\d{1,3}(\.\d{3})+$/.test(s)) {
    // «1.234» o «12.345.678»: puntos de miles.
    s = s.replace(/\./g, "");
  }
  if (!/^-?\d+(\.\d+)?$/.test(s)) return null;
  return Number(s);
}

// El IVA de una celda, si es una de las alícuotas (P5); si no, el 21 %.
export function readVat(v: ImportCell): number {
  const n = readImportNumber(v);
  if (n === null) return 21;
  // «0,21» es 21 %.
  const pct = n > 0 && n < 1 ? Math.round(n * 1000) / 10 : n;
  return (VAT_RATES as readonly number[]).includes(pct) ? pct : 21;
}

// Un renglón de la carga, con sus datos como texto (la planilla los muestra y los deja editar).
export type ImportedRow = {
  name: string;
  sku: string;
  list: string;
  b1: string;
  b2: string;
  perUnit: string;
  vat: string;
};

const asText = (n: number | null) => (n === null ? "" : String(n).replace(".", ","));

// Las filas debajo del encabezado, pasadas a renglones con la columna de cada dato. Se saltean las filas sin artículo o
// sin precio (títulos de rubro, totales, renglones en blanco), y se cuentan.
export function rowsFromTable(
  rows: ImportCell[][],
  headerIndex: number,
  map: ColumnMap,
  max = 500,
): { rows: ImportedRow[]; skipped: number; truncated: boolean } {
  const out: ImportedRow[] = [];
  let skipped = 0;
  const cell = (row: ImportCell[], f: ListField) =>
    map[f] === undefined ? null : (row[map[f]] ?? null);
  for (const row of rows.slice(headerIndex + 1)) {
    const name = String(cell(row, "name") ?? "")
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 200);
    const list = readImportNumber(cell(row, "list"));
    // Los totales y subtotales de la planilla no son artículos.
    const total = /^(sub)?total(es)?(\s|:|$)/i.test(name);
    if (!name || total || list === null || list <= 0) {
      if (row.some((c) => c !== null && String(c).trim() !== "")) skipped++;
      continue;
    }
    if (out.length >= max) return { rows: out, skipped, truncated: true };
    out.push({
      name,
      sku: String(cell(row, "sku") ?? "")
        .trim()
        .slice(0, 40),
      list: asText(list),
      b1: asText(readImportNumber(cell(row, "b1"))),
      b2: asText(readImportNumber(cell(row, "b2"))),
      perUnit: asText(readImportNumber(cell(row, "perUnit"))),
      vat: String(readVat(cell(row, "vat"))),
    });
  }
  return { rows: out, skipped, truncated: false };
}

// Un CSV: separado por «;» (Excel en castellano) o «,», con comillas. Devuelve las filas como texto.
export function parseCsv(text: string): ImportCell[][] {
  const body = text.replace(/^﻿/, "");
  const first = body.split(/\r?\n/, 1)[0] ?? "";
  const sep = (first.match(/;/g)?.length ?? 0) >= (first.match(/,/g)?.length ?? 0) ? ";" : ",";
  const rows: ImportCell[][] = [];
  let row: ImportCell[] = [];
  let field = "";
  let quoted = false;
  const push = () => {
    const t = field.trim();
    row.push(t === "" ? null : t);
    field = "";
  };
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (quoted) {
      if (ch === '"' && body[i + 1] === '"') {
        field += '"';
        i++;
      } else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === sep) push();
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && body[i + 1] === "\n") i++;
      push();
      rows.push(row);
      row = [];
    } else field += ch;
  }
  if (field !== "" || row.length > 0) {
    push();
    rows.push(row);
  }
  return rows;
}
