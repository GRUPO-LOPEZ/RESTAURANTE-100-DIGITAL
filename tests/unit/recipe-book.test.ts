// Lector del recetario de Excel (ADR-0027, PR 2), con un Excel DEMO del mismo formato que los de los
// restaurantes. Nunca el Excel real.
import { beforeAll, describe, expect, it } from "vitest";

import { readRecipeBook, type StageRow } from "@/lib/imports/recipe-book";

import { buildRecipeBook } from "../fixtures/recipe-book-fixture";

let rows: StageRow[] = [];
let sha = "";

beforeAll(async () => {
  const result = await readRecipeBook(await buildRecipeBook());
  if (!result.ok) throw new Error(result.message);
  rows = result.rows;
  sha = result.sha256;
});

const find = (kind: StageRow["kind"], code: string, parent?: string) =>
  rows.find(
    (r) =>
      r.kind === kind &&
      r.source_code === code &&
      (parent === undefined || r.parent_code === parent),
  );

describe("lector del recetario", () => {
  it("lee las materias primas de INSUMOS, sin los platos de la carta", () => {
    expect(rows.filter((r) => r.kind === "ingredient").map((r) => r.source_code)).toEqual([
      "190000",
      "190001",
      "140000",
      "110000",
      "190002",
    ]);
    expect(find("ingredient", "140000")?.parsed).toEqual({
      name: "ZAPALLO XLS",
      category: "Verduras",
      presentation_grams: 1000,
      net_grams: 800,
      waste_percent: 0.2,
    });
  });

  it("el precio va aparte, nunca en las celdas ni en lo interpretado", () => {
    expect(find("ingredient", "190000")?.price).toEqual({ price: 188400, price_per_kg: 18840 });
    const allowed = [
      "codigo",
      "rubro",
      "producto",
      "proveedor",
      "marca",
      "presentacion",
      "peso_neto",
    ];
    for (const r of rows.filter((x) => x.kind === "ingredient")) {
      expect(Object.keys(r.raw).every((k) => allowed.includes(k))).toBe(true);
      expect(JSON.stringify(r.parsed)).not.toMatch(/188400|18840/);
    }
  });

  it("una fórmula con error queda vacía", () => {
    expect(find("ingredient", "190002")?.price).toEqual({ price: 1500, price_per_kg: null });
  });

  it("lee los pre-elaborados con su rinde y sus líneas atadas al título", () => {
    expect(find("preparation", "300000")?.parsed).toEqual({
      name: "SALSA XLS PE",
      yield_grams: 1000,
    });
    const lines = rows.filter((r) => r.kind === "line" && r.parent_code === "300001");
    expect(lines.map((l) => [l.source_code, l.parent_row, l.parsed.grams])).toEqual([
      ["190002", 11, 1000],
      ["300000", 11, 100],
      ["999999", 11, 5],
    ]);
  });

  it("la medida casera queda; «GRAMOS» no (ya va en gramos)", () => {
    expect(find("line", "190000", "300000")?.parsed).toEqual({ grams: 50, measure: "CUP 60" });
    expect(find("line", "140000", "300000")?.parsed).toEqual({ grams: 800 });
  });

  it("lee los platos con porciones y peso por porción, y sus líneas (también las de 0 g)", () => {
    expect(find("dish", "240000")?.parsed).toEqual({
      name: "PIZZA XLS",
      portions: 1,
      portion_grams: 660,
    });
    expect(
      rows.filter((r) => r.kind === "line" && r.parent_code === "240000").map((l) => l.source_code),
    ).toEqual(["300001", "110000", "190001"]);
    expect(find("line", "190001", "240000")?.parsed).toEqual({ grams: 0 });
  });

  it("un bloque no se come el título del siguiente", () => {
    expect(
      rows.filter((r) => r.kind === "line" && r.parent_code === "240000").map((l) => l.row_number),
    ).toEqual([6, 7, 8]);
    expect(find("line", "140000", "240002")?.parent_row).toBe(16);
  });

  it("las plantillas vacías y los números sueltos no son recetas ni líneas", () => {
    expect(find("dish", "240002")?.row_number).toBe(16);
    expect(rows.filter((r) => r.kind === "line" && r.parent_code === "240002")).toHaveLength(1);
    expect(rows.some((r) => ["36", "5862", "777", "CODIGO"].includes(r.source_code ?? ""))).toBe(
      false,
    );
  });

  it("un costo a la derecha de una etiqueta vacía no se toma como dato", () => {
    expect(find("dish", "240002")?.parsed).toEqual({
      name: "PLATO SOLO EN PLATOS",
      portions: null,
      portion_grams: null,
    });
  });

  it("rechaza un Excel que se descomprime en algo enorme, antes de abrirlo", async () => {
    const book = new Uint8Array(await buildRecipeBook());
    const view = new DataView(book.buffer);
    // El primer archivo del índice del zip dice ocupar 300 MB descomprimido.
    let at = book.length - 22;
    while (view.getUint32(at, true) !== 0x06054b50) at--;
    const first = view.getUint32(at + 16, true);
    view.setUint32(first + 24, 300 * 1024 * 1024, true);
    expect(await readRecipeBook(book.buffer)).toEqual({
      ok: false,
      message:
        "El Excel es demasiado grande por dentro. Sacale las solapas que no son del recetario.",
    });
  });

  it("un plato de la carta sin bloque entra sin componentes; con bloque, no se repite", () => {
    expect(find("dish", "240001")?.sheet).toBe("INSUMOS");
    expect(rows.filter((r) => r.kind === "dish" && r.source_code === "240000")).toHaveLength(1);
  });

  it("calcula la huella del contenido", () => {
    expect(sha).toMatch(/^[0-9a-f]{64}$/);
  });

  it("rechaza lo que no es un Excel y el archivo vacío", async () => {
    const notXlsx = await readRecipeBook(
      new TextEncoder().encode("CODIGO;PRODUCTO\n1;X").buffer as ArrayBuffer,
    );
    expect(notXlsx).toEqual({
      ok: false,
      message:
        "El archivo no es un Excel (.xlsx). Guardalo como «Libro de Excel» y probá de nuevo.",
    });
    expect(await readRecipeBook(new ArrayBuffer(0))).toEqual({
      ok: false,
      message: "El archivo está vacío.",
    });
  });
});
