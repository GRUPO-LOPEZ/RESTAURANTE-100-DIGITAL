import { createHash } from "node:crypto";
import type ExcelJS from "exceljs";
import { findSheet, norm, openWorkbook, text, value, type Cell } from "@/lib/imports/xlsx";

// Lector del recetario de Excel (ADR-0027, PR 2). Convierte el archivo en las filas que espera
// imports.stage_rows: materias primas (solapa INSUMOS), preparaciones (pre-elaborado) y platos
// (PLATOS), con sus líneas atadas a la fila del título de su bloque. No adivina: lo que no entiende
// lo deja vacío y la validación de la base lo informa fila por fila. Los precios van aparte (`price`),
// nunca en `raw` ni en `parsed` (decisión de Joaco: el Chef no ve precios).

export const MAX_FILE_BYTES = 15 * 1024 * 1024; // como el bucket
export const MAX_ROWS = 10_000; // como imports.stage_rows
// Filas que se recorren por solapa, aunque el Excel diga que tiene más.
const MAX_SHEET_ROWS = 20_000;

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
// Celdas (lo común está en lib/imports/xlsx.ts)
// ---------------------------------------------------------------------------
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
  const opened = await openWorkbook(file, {
    maxBytes: MAX_FILE_BYTES,
    tooBig: "El archivo pasa los 15 MB. Sacale las solapas que no son del recetario.",
    tooBigInside:
      "El Excel es demasiado grande por dentro. Sacale las solapas que no son del recetario.",
  });
  if (!opened.ok) return opened;
  const wb = opened.wb;
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
