import { createHash } from "node:crypto";
import ExcelJS from "exceljs";

// Lector del recetario de Excel (ADR-0027, PR 2). Convierte el archivo en las filas que espera
// imports.stage_rows: materias primas (solapa INSUMOS), preparaciones (pre-elaborado) y platos
// (PLATOS), con sus líneas atadas a la fila del título de su bloque. No adivina: lo que no entiende
// lo deja vacío y la validación de la base lo informa fila por fila. Los precios van aparte (`price`),
// nunca en `raw` ni en `parsed` (decisión de Joaco: el Chef no ve precios).

export const MAX_FILE_BYTES = 15 * 1024 * 1024; // como el bucket
export const MAX_ROWS = 10_000; // como imports.stage_rows
// Topes del archivo descomprimido (revisión de seguridad, M1): un .xlsx chico puede descomprimirse en
// varios GB ("zip bomb"). El recetario real de Nonnos ocupa 53 MB descomprimido.
export const MAX_UNZIPPED_BYTES = 250 * 1024 * 1024;
const MAX_ZIP_ENTRIES = 5_000;
// Filas que se recorren por solapa, aunque el Excel diga que tiene más.
const MAX_SHEET_ROWS = 20_000;

type Cell = string | number | null;
export type StageRow = {
  sheet: string;
  row_number: number;
  kind: "ingredient" | "preparation" | "dish" | "line";
  source_code?: string;
  parent_code?: string;
  parent_row?: number;
  raw: Record<string, Cell>;
  parsed: Record<string, Cell>;
  price?: { price: number | null; price_per_kg: number | null };
};
export type ReadResult =
  { ok: true; rows: StageRow[]; sha256: string } | { ok: false; message: string };

// ---------------------------------------------------------------------------
// Celdas
// ---------------------------------------------------------------------------
// El valor de una celda: el resultado de una fórmula, el texto de un texto con formato; un error de
// Excel (#N/A, #VALUE!) queda vacío.
function value(cell: ExcelJS.Cell | undefined): Cell {
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

function text(v: Cell): string | null {
  if (v === null) return null;
  const s = String(v).replace(/\s+/g, " ").trim();
  return s === "" ? null : s.slice(0, 200);
}

function num(v: Cell): number | null {
  if (typeof v === "number") return v;
  if (typeof v === "string" && /^-?\d+([.,]\d+)?$/.test(v.trim()))
    return Number(v.trim().replace(",", "."));
  return null;
}

// Un código del Excel: un número entero (190000) o un texto corto sin espacios.
function code(v: Cell): string | null {
  if (typeof v === "number") return Number.isInteger(v) && v > 0 ? String(v) : null;
  const s = text(v);
  return s && /^[A-Za-z0-9-]{1,30}$/.test(s) ? s.toUpperCase() : null;
}

// Para comparar encabezados: sin tildes, en minúsculas y sin espacios de más.
function norm(v: Cell): string {
  return String(v ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

function rowCells(sheet: ExcelJS.Worksheet, r: number): Cell[] {
  const row = sheet.getRow(r);
  // Indexada desde 1, como las columnas de Excel; sin huecos (la 0 queda vacía).
  const last = Math.min(row.cellCount, 60);
  const out: Cell[] = new Array<Cell>(last + 1).fill(null);
  for (let c = 1; c <= last; c++) out[c] = value(row.getCell(c));
  return out;
}

function lastRow(sheet: ExcelJS.Worksheet): number {
  return Math.min(sheet.rowCount, MAX_SHEET_ROWS);
}

function findSheet(wb: ExcelJS.Workbook, name: string): ExcelJS.Worksheet | undefined {
  return wb.worksheets.find((ws) => norm(ws.name) === name);
}

// Lo que dice el índice del zip (directorio central) sobre el contenido, antes de descomprimir nada:
// cuántos archivos tiene y cuánto ocupan descomprimidos. Un zip sin índice legible o con formato
// ZIP64 (para archivos de más de 4 GB) no es un recetario.
export function zipTooLarge(file: ArrayBuffer): boolean {
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
  for (let n = 0; n < entries; n++) {
    if (at + 46 > file.byteLength || view.getUint32(at, true) !== 0x02014b50) return true;
    const size = view.getUint32(at + 24, true);
    if (size === 0xffffffff) return true;
    total += size;
    if (total > MAX_UNZIPPED_BYTES) return true;
    at += 46 + view.getUint16(at + 28, true) + view.getUint16(at + 30, true) + view.getUint16(at + 32, true);
  }
  return false;
}

// ---------------------------------------------------------------------------
// INSUMOS: una fila por materia prima; las de rubro "Plato finalizado" son platos de la carta
// ---------------------------------------------------------------------------
function readSupplies(sheet: ExcelJS.Worksheet): { rows: StageRow[]; dishes: StageRow[] } {
  const rows: StageRow[] = [];
  const dishes: StageRow[] = [];
  let header = 0;
  const col: Record<string, number> = {};
  for (let r = 1; r <= Math.min(sheet.rowCount, 10) && !header; r++) {
    const cells = rowCells(sheet, r);
    const names = cells.map(norm);
    if (names.includes("codigo") && names.includes("producto")) {
      header = r;
      names.forEach((n, c) => {
        if (n === "codigo") col.code ??= c;
        else if (n === "rubro") col.category ??= c;
        else if (n === "producto") col.name ??= c;
        else if (n === "proveedor") col.supplier ??= c;
        else if (n === "marca") col.brand ??= c;
        else if (n.startsWith("$ neto x kg")) col.pricePerKg ??= c;
        else if (n === "$") col.price ??= c;
        else if (n.startsWith("presentacion")) col.presentation ??= c;
        else if (n.startsWith("peso neto")) col.net ??= c;
        else if (n.startsWith("% desperdicio")) col.waste ??= c;
      });
    }
  }
  if (!header || !col.code || !col.name) return { rows, dishes };
  for (let r = header + 1; r <= lastRow(sheet); r++) {
    const cells = rowCells(sheet, r);
    const sourceCode = code(cells[col.code] ?? null);
    const name = text(cells[col.name] ?? null);
    if (!sourceCode || !name) continue;
    const category = col.category ? text(cells[col.category] ?? null) : null;
    const raw = {
      codigo: sourceCode,
      rubro: category,
      producto: name,
      proveedor: col.supplier ? text(cells[col.supplier] ?? null) : null,
      marca: col.brand ? text(cells[col.brand] ?? null) : null,
      presentacion: col.presentation ? num(cells[col.presentation] ?? null) : null,
      peso_neto: col.net ? num(cells[col.net] ?? null) : null,
    };
    if (category && norm(category).startsWith("plato")) {
      // Un plato de la carta: si tiene bloque en PLATOS se usa el bloque.
      dishes.push({
        sheet: sheet.name,
        row_number: r,
        kind: "dish",
        source_code: sourceCode,
        raw: {
          codigo: sourceCode,
          nombre: name,
          peso_total: null,
          porciones: null,
          peso_porcion: null,
        },
        parsed: { name },
      });
      continue;
    }
    const parsed: Record<string, Cell> = { name, category };
    if (raw.presentacion !== null) parsed.presentation_grams = raw.presentacion;
    if (raw.peso_neto !== null) parsed.net_grams = raw.peso_neto;
    const waste = col.waste ? num(cells[col.waste] ?? null) : null;
    if (waste !== null) parsed.waste_percent = waste;
    rows.push({
      sheet: sheet.name,
      row_number: r,
      kind: "ingredient",
      source_code: sourceCode,
      raw,
      parsed,
      price: {
        price: col.price ? num(cells[col.price] ?? null) : null,
        price_per_kg: col.pricePerKg ? num(cells[col.pricePerKg] ?? null) : null,
      },
    });
  }
  return { rows, dishes };
}

// ---------------------------------------------------------------------------
// pre-elaborado y PLATOS: bloques con un título (código y nombre), una fila de encabezados
// (CODIGO / INGREDIENTES / Medida / Receta (GRS)) y las líneas
// ---------------------------------------------------------------------------
const LABELS = ["precio por porcion", "peso neto total receta", "peso total", "peso bruto total"];
const TITLE_LABELS = ["precio por porcion", "peso neto total"];

// El número de la primera celda con algo después de una etiqueta, a lo sumo 4 columnas más allá
// ("Peso Neto Total Receta" → 29247). Si esa celda está vacía no se sigue buscando: más a la
// derecha puede haber un costo, que nunca tiene que terminar como dato de la receta.
function numberAfter(cells: Cell[], label: string): number | null {
  const at = cells.findIndex((c) => norm(c).startsWith(label));
  if (at < 0) return null;
  for (let c = at + 1; c < Math.min(cells.length, at + 5); c++) {
    const v = cells[c] ?? null;
    if (v !== null) return num(v);
  }
  return null;
}

function readBlocks(sheet: ExcelJS.Worksheet, kind: "preparation" | "dish"): StageRow[] {
  // Cada fila de encabezados abre un bloque, aunque sea una plantilla vacía: así un bloque nunca se
  // come las filas del siguiente. El título es la fila de arriba con la etiqueta del título
  // ("Precio por porción" en PLATOS, "Peso Neto Total Receta" en pre-elaborado); a falta de
  // etiqueta, la más cercana con un código. Un número suelto entre el título y el encabezado no cuenta.
  type Block = {
    header: number;
    title: number;
    titleCells: Cell[];
    code: number;
    name: number;
    measure: number;
    grams: number;
  };
  const blocks: Block[] = [];
  for (let r = 1; r <= lastRow(sheet); r++) {
    const names = rowCells(sheet, r).map(norm);
    const codeCol = names.indexOf("codigo");
    if (codeCol <= 0 || !names.includes("ingredientes")) continue;
    const above: number[] = [];
    for (let t = r - 1; t >= Math.max(1, r - 4); t--) above.push(t);
    const hasCode = (cells: Cell[]) => cells.some((c) => typeof c === "number" && code(c) !== null);
    const title =
      above.find((t) =>
        rowCells(sheet, t).some((c) => TITLE_LABELS.some((l) => norm(c).startsWith(l))),
      ) ??
      above.find((t) => hasCode(rowCells(sheet, t))) ??
      r;
    blocks.push({
      header: r,
      title,
      titleCells: title === r ? [] : rowCells(sheet, title),
      code: codeCol,
      name: names.indexOf("ingredientes"),
      measure: names.indexOf("medida"),
      grams: names.findIndex((n) => n.startsWith("receta (grs)")),
    });
  }
  const out: StageRow[] = [];
  blocks.forEach((b, i) => {
    // El código es la primera celda con algo del título, antes de cualquier etiqueta: si esa celda
    // está vacía, un número más a la derecha (un precio) no se toma como código.
    const codeAt = b.titleCells.findIndex((c) => c !== null);
    const sourceCode =
      codeAt < 0 || typeof b.titleCells[codeAt] !== "number"
        ? null
        : code(b.titleCells[codeAt] ?? null);
    // Una plantilla sin código (filas con fórmulas en #N/A, sin nada cargado) no es una receta.
    if (!sourceCode) return;
    const name =
      b.titleCells
        .slice(codeAt + 1)
        .map((c) => (typeof c === "string" ? text(c) : null))
        .find((c) => c && !LABELS.some((l) => norm(c).startsWith(l))) ?? null;
    // El bloque termina antes del título del bloque siguiente.
    const next = blocks[i + 1];
    const end = next ? next.title - 1 : sheet.rowCount;
    let portions: number | null = null;
    let portionGrams: number | null = null;
    const lines: StageRow[] = [];
    for (let r = b.header + 1; r <= end; r++) {
      const cells = rowCells(sheet, r);
      portionGrams ??= numberAfter(cells, "peso por porcion");
      portions ??= numberAfter(cells, "cantidad de porciones");
      const lineCode = code(cells[b.code] ?? null);
      if (!lineCode) continue;
      const grams = b.grams > 0 ? num(cells[b.grams] ?? null) : null;
      const measure = b.measure > 0 ? text(cells[b.measure] ?? null) : null;
      const parsed: Record<string, Cell> = { grams };
      // "GRAMOS" no es una medida casera: la cantidad ya va en gramos.
      if (measure && !["gramos", "gr", "grs", "g"].includes(norm(measure)))
        parsed.measure = measure;
      lines.push({
        sheet: sheet.name,
        row_number: r,
        kind: "line",
        source_code: lineCode,
        parent_code: sourceCode,
        parent_row: b.title,
        raw: {
          codigo: lineCode,
          ingrediente: b.name > 0 ? text(cells[b.name] ?? null) : null,
          medida: measure,
          gramos: grams,
        },
        parsed,
      });
    }
    // Sin nombre ni líneas es una plantilla con un número suelto: no hay receta que importar.
    if (!name && lines.length === 0) return;
    const yieldGrams = numberAfter(b.titleCells, "peso neto total");
    out.push({
      sheet: sheet.name,
      row_number: b.title,
      kind,
      source_code: sourceCode,
      raw: {
        codigo: sourceCode,
        nombre: name,
        peso_total: kind === "preparation" ? yieldGrams : null,
        porciones: kind === "dish" ? portions : null,
        peso_porcion: kind === "dish" ? portionGrams : null,
      },
      parsed:
        kind === "preparation"
          ? { name, yield_grams: yieldGrams }
          : { name, portions, portion_grams: portionGrams },
    });
    out.push(...lines);
  });
  return out;
}

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------
export async function readRecipeBook(file: ArrayBuffer): Promise<ReadResult> {
  if (file.byteLength === 0) return { ok: false, message: "El archivo está vacío." };
  if (file.byteLength > MAX_FILE_BYTES)
    return {
      ok: false,
      message: "El archivo pasa los 15 MB. Sacale las solapas que no son del recetario.",
    };
  // Un .xlsx es un zip: empieza con "PK\x03\x04". Se mira el contenido, no la extensión.
  const head = new Uint8Array(file, 0, 4);
  if (head[0] !== 0x50 || head[1] !== 0x4b || head[2] !== 0x03 || head[3] !== 0x04)
    return {
      ok: false,
      message:
        "El archivo no es un Excel (.xlsx). Guardalo como «Libro de Excel» y probá de nuevo.",
    };
  if (zipTooLarge(file))
    return {
      ok: false,
      message: "El Excel es demasiado grande por dentro. Sacale las solapas que no son del recetario.",
    };
  const wb = new ExcelJS.Workbook();
  try {
    await wb.xlsx.load(file);
  } catch {
    return {
      ok: false,
      message: "No pudimos leer el Excel. Revisá que se abra bien y guardalo de nuevo.",
    };
  }
  const supplies = findSheet(wb, "insumos");
  const preparations = findSheet(wb, "pre-elaborado");
  const dishes = findSheet(wb, "platos");
  if (!supplies && !preparations && !dishes)
    return { ok: false, message: "No encontramos las solapas INSUMOS, pre-elaborado ni PLATOS." };

  const supplyRows = supplies ? readSupplies(supplies) : { rows: [], dishes: [] };
  const prepRows = preparations ? readBlocks(preparations, "preparation") : [];
  const dishRows = dishes ? readBlocks(dishes, "dish") : [];
  // Los platos de la carta sin bloque en PLATOS entran sin componentes.
  const withBlock = new Set(dishRows.filter((r) => r.kind === "dish").map((r) => r.source_code));
  const rows = [
    ...supplyRows.rows,
    ...supplyRows.dishes.filter((d) => !withBlock.has(d.source_code)),
    ...prepRows,
    ...dishRows,
  ];
  if (rows.length === 0) return { ok: false, message: "El Excel no tiene filas para importar." };
  if (rows.length > MAX_ROWS)
    return { ok: false, message: `El Excel tiene ${rows.length} filas: el máximo es ${MAX_ROWS}.` };
  return {
    ok: true,
    rows,
    sha256: createHash("sha256").update(new Uint8Array(file)).digest("hex"),
  };
}
