import { describe, expect, it } from "vitest";

import {
  buildPriceListTemplate,
  listFileKind,
  readPriceListFile,
} from "@/lib/imports/price-list-file";
import { checkBadge, perUseLabel } from "@/lib/price-lists";
import {
  fieldOfHeader,
  findHeaderRow,
  parseCsv,
  readImportNumber,
  readVat,
  rowsFromTable,
  TEMPLATE_HEADERS,
} from "@/lib/price-list-columns";
import { PNG_HEAD, csvFixture, excelFixture, pdfFixture } from "../fixtures/listas";

// Importar listas de precios (ADR-0071): columnas, números y los tres formatos que se leen solos.
describe("los encabezados", () => {
  it("reconoce cada dato con los nombres que usan los proveedores", () => {
    expect(fieldOfHeader("Descripción")).toBe("name");
    expect(fieldOfHeader("Artículo")).toBe("name");
    expect(fieldOfHeader("Cód.")).toBe("sku");
    expect(fieldOfHeader("Precio s/IVA")).toBe("list");
    expect(fieldOfHeader("Desc. %")).toBe("b1");
    expect(fieldOfHeader("Bonif. 2 (%)")).toBe("b2");
    expect(fieldOfHeader("Bonif. ($ por unidad)")).toBe("perUnit");
    expect(fieldOfHeader("Alícuota")).toBe("vat");
    expect(fieldOfHeader("IVA %")).toBe("vat");
    expect(fieldOfHeader("Observaciones")).toBeNull();
  });

  it("la planilla modelo se reconoce entera", () => {
    for (const [field, header] of Object.entries(TEMPLATE_HEADERS))
      expect(fieldOfHeader(header)).toBe(field);
  });

  it("busca la fila de encabezados debajo de los títulos", () => {
    const found = findHeaderRow([["Lista ficticia"], [], ["Código", "Artículo", "Precio"]]);
    expect(found).toEqual({ index: 2, map: { sku: 0, name: 1, list: 2 } });
    expect(findHeaderRow([["Solo", "texto"]])).toBeNull();
  });
});

describe("los números de acá", () => {
  it("lee miles con punto y decimales con coma", () => {
    expect(readImportNumber("1.899,72")).toBe(1899.72);
    expect(readImportNumber("$ 1.234")).toBe(1234);
    expect(readImportNumber("12.345.678")).toBe(12345678);
    expect(readImportNumber("1899.72")).toBe(1899.72);
    expect(readImportNumber("1,5")).toBe(1.5);
    expect(readImportNumber("10 %")).toBe(10);
    expect(readImportNumber(42)).toBe(42);
    expect(readImportNumber("consultar")).toBeNull();
  });

  it("el IVA es una de las alícuotas; si no, 21 %", () => {
    expect(readVat("10,5")).toBe(10.5);
    expect(readVat(0.21)).toBe(21);
    expect(readVat("27%")).toBe(27);
    expect(readVat("19")).toBe(21);
    expect(readVat(null)).toBe(21);
  });

  it("saltea títulos de rubro y totales, y los cuenta", () => {
    const table = [
      ["Código", "Artículo", "Precio"],
      ["", "VERDURAS", ""],
      ["A1", "Tomate", "1.000"],
      ["", "Total", "1.000"],
    ];
    const found = findHeaderRow(table);
    const out = rowsFromTable(table, found!.index, found!.map);
    expect(out.rows).toEqual([
      { name: "Tomate", sku: "A1", list: "1000", b1: "", b2: "", perUnit: "", vat: "21" },
    ]);
    // El título del rubro y el total.
    expect(out.skipped).toBe(2);
  });
});

describe("el CSV", () => {
  it("con «;», comillas y coma decimal", () => {
    expect(parseCsv('a;"b;c";1,5\r\nd;e;2')).toEqual([
      ["a", "b;c", "1,5"],
      ["d", "e", "2"],
    ]);
    expect(parseCsv("a,b\n1,2")).toEqual([
      ["a", "b"],
      ["1", "2"],
    ]);
  });
});

describe("leer el archivo", () => {
  it("un Excel: busca la hoja con la lista y vuelca los renglones", async () => {
    const r = await readPriceListFile(await excelFixture(), "lista.xlsx");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.sheets).toEqual(["Portada", "Precios"]);
    expect(r.sheet).toBe("Precios");
    expect(r.rows).toHaveLength(3);
    expect(r.rows[0]).toMatchObject({
      name: "Albahaca fresca, por kg",
      sku: "FR007",
      list: "1899,72",
      vat: "10.5",
    });
    expect(r.rows[1]).toMatchObject({ b1: "5", vat: "21" });
    expect(r.skipped).toBe(2);
  });

  it("un CSV", async () => {
    const r = await readPriceListFile(csvFixture(), "lista.csv");
    expect(r.ok && r.rows.map((x) => [x.name, x.list, x.b1])).toEqual([
      ["Albahaca fresca; por kg", "1899,72", "0"],
      ["Perejil, por kg", "2047,68", "5"],
    ]);
  });

  it("un PDF hecho por computadora: renglones y columnas por posición", async () => {
    const r = await readPriceListFile(await pdfFixture(), "lista.pdf");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.kind).toBe("pdf");
    expect(r.rows.map((x) => [x.sku, x.name, x.list, x.vat])).toEqual([
      ["FR007", "Albahaca fresca, por kg", "1899,72", "10.5"],
      ["FR008", "Perejil, por kg", "2047,68", "21"],
      ["FR011", "Carne picada especial, por kg", "2491,56", "10.5"],
    ]);
  });

  it("un PDF escaneado o una foto: la pantalla dividida", async () => {
    const scanned = await readPriceListFile(await pdfFixture(false), "lista.pdf");
    expect(scanned).toMatchObject({ ok: false, scanned: true, kind: "pdf" });
    const photo = new Uint8Array(64);
    photo.set(PNG_HEAD);
    expect(await readPriceListFile(photo.buffer, "lista.png")).toMatchObject({
      ok: false,
      scanned: true,
      kind: "image",
    });
  });

  it("lo que no es una lista no se lee", async () => {
    expect(listFileKind(new TextEncoder().encode("MZ\u0000\u0001"), "virus.csv")).toBeNull();
    const r = await readPriceListFile(
      new TextEncoder().encode("hola").buffer as ArrayBuffer,
      "x.exe",
    );
    expect(r).toMatchObject({ ok: false });
  });
});

describe("la planilla modelo y los controles", () => {
  it("la planilla modelo se lee sola (con su renglón de ejemplo)", async () => {
    const buf = await buildPriceListTemplate("Distribuidora Ejemplo");
    const file = new Uint8Array(buf).buffer;
    const r = await readPriceListFile(file, "modelo.xlsx");
    expect(r.ok && r.rows).toEqual([
      {
        name: "Ejemplo: tomate perita, cajón de 18 kg",
        sku: "TOM-18",
        list: "21500",
        b1: "5",
        b2: "0",
        perUnit: "0",
        vat: "21",
      },
    ]);
  });

  it("el precio por unidad de uso", () => {
    expect(perUseLabel(9856.4, "kg")).toBe("$ 9.856 por kg");
    expect(perUseLabel(12.5, "u")).toBe("$ 12,50 por u");
    expect(perUseLabel(null, "kg")).toBe("—");
    expect(perUseLabel(10, null)).toBe("—");
  });

  it("la palabra del control: Revisar, la suba resaltada, Nuevo", () => {
    const base = { perUsePrice: null, perUseUnit: null };
    expect(checkBadge({ ...base, changePct: 950, overThreshold: true, review: true })).toEqual({
      label: "Revisar",
      status: "bad",
    });
    expect(checkBadge({ ...base, changePct: 31.6, overThreshold: true, review: false })).toEqual({
      label: "+31,6 %",
      status: "warn",
    });
    expect(checkBadge({ ...base, changePct: -3, overThreshold: false, review: false })).toEqual({
      label: "−3 %",
      status: "none",
    });
    expect(
      checkBadge({ ...base, changePct: null, overThreshold: false, review: false }).label,
    ).toBe("Nuevo");
  });
});
