// Lector de la planilla de proveedores (ADR-0055), con planillas inventadas que arma la prueba. Nunca la planilla real.
import { deflateRawSync } from "node:zlib";

import ExcelJS from "exceljs";
import { describe, expect, it } from "vitest";

import { zipTooLarge } from "@/lib/imports/xlsx";

import {
  MAX_SUPPLIER_ROWS,
  SUPPLIER_COLUMNS,
  buildSupplierTemplate,
  parseDays,
  readSupplierSheet,
} from "@/lib/imports/supplier-sheet";

type Value = ExcelJS.CellValue;

async function sheet(
  rows: Value[][],
  headers: string[] = SUPPLIER_COLUMNS.map((c) => c.header),
  name = "Proveedores",
): Promise<ArrayBuffer> {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(name);
  ws.addRow(headers);
  for (const r of rows) ws.addRow(r);
  const buf = await wb.xlsx.writeBuffer();
  return new Uint8Array(buf as ArrayBuffer).slice().buffer;
}

// Una fila completa, en el orden de la plantilla, con CUIT inventados con su dígito verificador.
const full: Value[] = [
  "Verduras Inventadas SRL",
  "30-12345678-1",
  "La Verdu",
  "Responsable inscripto",
  "Calle Falsa 123",
  "Ciudad Demo",
  "011 4000-0000",
  "+54 9 11 4000-0000",
  "Pedidos@Ejemplo.test",
  "Ana",
  "Luis",
  "Verduras, Frutas",
  "lun, mié, vie",
  "Martes y jueves",
  "WhatsApp",
  "+54 9 11 4000-0000",
  "Sí",
  "Cuenta corriente",
  30,
  "150.000",
];

describe("lector de la planilla de proveedores", () => {
  it("lee una fila completa con las etiquetas de la ficha", async () => {
    const r = await readSupplierSheet(await sheet([full]));
    if (!r.ok) throw new Error(r.message);
    expect(r.rows).toHaveLength(1);
    const row = r.rows[0]!;
    expect(row.errors).toEqual([]);
    expect(row).toMatchObject({
      row: 2,
      name: "Verduras Inventadas SRL",
      tax_id: "30123456781",
      supplier: {
        trade_name: "La Verdu",
        vat_condition: "registered",
        email: "pedidos@ejemplo.test",
        phone: "011 4000-0000",
      },
      terms: {
        order_days: [1, 3, 5],
        delivery_days: [2, 4],
        po_channel: "whatsapp",
        po_channel_target: "+54 9 11 4000-0000",
        requires_po_approval: true,
      },
      payment_terms: {
        payment_terms: "account",
        payment_days: "30",
        minimum_order_amount: "150000",
      },
      categories: ["Verduras", "Frutas"],
    });
  });

  it("acepta encabezados con otras mayúsculas, sin tildes y en otro orden", async () => {
    const r = await readSupplierSheet(
      await sheet(
        [["30-12345678-1", "Otro SA", "monotributo"]],
        ["cuit", "RAZON SOCIAL", "condicion iva"],
      ),
    );
    if (!r.ok) throw new Error(r.message);
    expect(r.rows[0]).toMatchObject({
      name: "Otro SA",
      tax_id: "30123456781",
      supplier: { vat_condition: "monotax" },
    });
  });

  it("lee celdas con fórmula, con hipervínculo y booleanos", async () => {
    const r = await readSupplierSheet(
      await sheet(
        [
          [
            { formula: '"Fórmula "&"SA"', result: "Fórmula SA" },
            "30-12345678-1",
            true,
            { text: "a@b.test", hyperlink: "mailto:a@b.test" },
          ],
        ],
        ["Razón social", "CUIT", "Requiere aprobación de la OC", "Correo"],
      ),
    );
    if (!r.ok) throw new Error(r.message);
    expect(r.rows[0]).toMatchObject({
      name: "Fórmula SA",
      supplier: { email: "a@b.test" },
      terms: { requires_po_approval: true },
      errors: [],
    });
  });

  it("saltea las filas vacías y numera con la fila del Excel", async () => {
    const r = await readSupplierSheet(
      await sheet(
        [[], ["Uno SA", "30-12345678-1"], [], ["Dos SA", "20-12345678-6"]],
        ["Razón social", "CUIT"],
      ),
    );
    if (!r.ok) throw new Error(r.message);
    expect(r.rows.map((x) => [x.row, x.name])).toEqual([
      [3, "Uno SA"],
      [5, "Dos SA"],
    ]);
  });

  it("marca los errores de cada fila en castellano, con la columna y el valor", async () => {
    const r = await readSupplierSheet(
      await sheet(
        [
          [
            "",
            "30-12345678-2",
            "Monotributista",
            "lun, feriado",
            "Paloma",
            "x",
            "Quizás",
            "Cuenta corriente",
            "",
          ],
          ["Tres SA", "", "", "", "Mail", "no-es-correo", "", "Contado", ""],
        ],
        [
          "Razón social",
          "CUIT",
          "Condición IVA",
          "Días de pedido",
          "Canal de la OC",
          "Destino de la OC",
          "Requiere aprobación de la OC",
          "Condición de pago",
          "Días de pago",
        ],
      ),
    );
    if (!r.ok) throw new Error(r.message);
    expect(r.rows[0]!.errors).toEqual([
      "Falta la razón social.",
      "CUIT: «30-12345678-2» no es un CUIT válido.",
      "Días de pedido: «feriado» no es un día de la semana.",
      "Canal de la OC: «Paloma» no es una opción (WhatsApp, Mail o Sistema propio).",
      "Requiere aprobación de la OC: «Quizás» va como Sí o No.",
      "Días de pago: la cuenta corriente va con los días, de 1 a 180.",
    ]);
    // «Monotributista» se entiende.
    expect(r.rows[0]!.errors.join(" ")).not.toContain("Condición IVA");
    expect(r.rows[1]!.errors).toEqual([
      "Falta el CUIT.",
      expect.stringContaining("Destino de la OC: «no-es-correo» no corresponde al canal"),
    ]);
  });

  it("el mismo CUIT dos veces en la planilla es un error en las dos filas", async () => {
    const r = await readSupplierSheet(
      await sheet(
        [
          ["Uno SA", "30-12345678-1"],
          ["Uno bis SA", "30123456781"],
        ],
        ["Razón social", "CUIT"],
      ),
    );
    if (!r.ok) throw new Error(r.message);
    for (const row of r.rows)
      expect(row.errors).toEqual(["CUIT repetido en la planilla (filas 2, 3): dejá uno solo."]);
  });

  it("rechaza más de 200 proveedores", async () => {
    const rows = Array.from({ length: MAX_SUPPLIER_ROWS + 1 }, (_, i) => [
      `Proveedor ${i}`,
      "30-12345678-1",
    ]);
    const r = await readSupplierSheet(await sheet(rows, ["Razón social", "CUIT"]));
    expect(r).toEqual({
      ok: false,
      message: "La planilla tiene más de 200 proveedores. Partila en dos archivos.",
    });
  });

  it("rechaza un archivo que no es un Excel, uno vacío y uno sin los encabezados", async () => {
    expect(
      await readSupplierSheet(new TextEncoder().encode("razón social;cuit").buffer as ArrayBuffer),
    ).toMatchObject({
      ok: false,
      message: expect.stringContaining("no es un Excel"),
    });
    expect(await readSupplierSheet(new ArrayBuffer(0))).toEqual({
      ok: false,
      message: "El archivo está vacío.",
    });
    expect(await readSupplierSheet(await sheet([["Uno SA"]], ["Nombre"]))).toMatchObject({
      ok: false,
      message: expect.stringContaining("«Razón social» y «CUIT»"),
    });
    expect(await readSupplierSheet(await sheet([], ["Razón social", "CUIT"]))).toEqual({
      ok: false,
      message: "La planilla no tiene proveedores cargados.",
    });
  });

  it("entiende los días escritos de varias formas", () => {
    expect(parseDays("Lunes, MIÉRCOLES y viernes")).toEqual({ days: [1, 3, 5], unknown: [] });
    expect(parseDays("lu mi vi do")).toEqual({ days: [1, 3, 5, 7], unknown: [] });
    expect(parseDays("sáb; dom")).toEqual({ days: [6, 7], unknown: [] });
    expect(parseDays("lun, lun")).toEqual({ days: [1], unknown: [] });
  });

  it("la plantilla se vuelve a leer, y su fila de ejemplo no se crea si no la borran", async () => {
    const buf = await buildSupplierTemplate(["Verduras", "Carnes"]);
    const r = await readSupplierSheet(new Uint8Array(buf).slice().buffer);
    if (!r.ok) throw new Error(r.message);
    expect(r.rows).toHaveLength(1);
    // El único error es que es el ejemplo: el resto de sus valores se entienden.
    expect(r.rows[0]!.errors).toEqual([
      "Es la fila de ejemplo de la plantilla: borrala antes de subir.",
    ]);
    expect(r.rows[0]!.categories).toEqual(["Verduras", "Carnes"]);
  });
});

// Un zip de una sola entrada, armado a mano, que declara en su índice el tamaño que le digan.
function zipWith(content: Buffer, declaredSize: number): ArrayBuffer {
  const name = Buffer.from("xl/media/x.png");
  const data = deflateRawSync(content);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0);
  local.writeUInt16LE(20, 4);
  local.writeUInt16LE(8, 8);
  local.writeUInt32LE(data.length, 18);
  local.writeUInt32LE(declaredSize, 22);
  local.writeUInt16LE(name.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0);
  central.writeUInt16LE(20, 4);
  central.writeUInt16LE(20, 6);
  central.writeUInt16LE(8, 10);
  central.writeUInt32LE(data.length, 20);
  central.writeUInt32LE(declaredSize, 24);
  central.writeUInt16LE(name.length, 28);
  central.writeUInt32LE(0, 42);
  const centralAt = local.length + name.length + data.length;
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(1, 8);
  end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + name.length, 12);
  end.writeUInt32LE(centralAt, 16);
  const all = Buffer.concat([local, name, data, central, name, end]);
  return new Uint8Array(all).slice().buffer;
}

describe("tope del contenido descomprimido (zip bomb)", () => {
  const tope = 1024 * 1024;

  it("no le cree al índice: mide lo que de verdad sale al descomprimir", () => {
    // 5 MB de ceros comprimen a unos pocos KB y el índice dice 1 KB.
    expect(zipTooLarge(zipWith(Buffer.alloc(5 * tope), 1024), tope)).toBe(true);
  });

  it("deja pasar un zip honesto debajo del tope", () => {
    expect(zipTooLarge(zipWith(Buffer.alloc(tope / 2), tope / 2), tope)).toBe(false);
  });

  it("un zip que declara más que el tope se rechaza sin descomprimir", () => {
    expect(zipTooLarge(zipWith(Buffer.alloc(10), 2 * tope), tope)).toBe(true);
  });

  it("una planilla real armada con ExcelJS pasa", async () => {
    expect(zipTooLarge(await sheet([full]))).toBe(false);
  });
});
