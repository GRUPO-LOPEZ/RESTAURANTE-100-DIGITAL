import ExcelJS from "exceljs";

// Un recetario de Excel DEMO con la misma forma que los de los restaurantes (ADR-0027): solapas
// INSUMOS, pre-elaborado y PLATOS, encabezados, bloques con título, medidas caseras, una fórmula con
// error, una línea en 0 g y un código desconocido. Datos ficticios: nunca el Excel real.

// `mark` va en una solapa que se ignora: cambia la huella del archivo sin cambiar su contenido (las
// pruebas de Playwright suben uno distinto por corrida, porque el mismo archivo no se importa dos veces).
export async function buildRecipeBook(mark = ""): Promise<ArrayBuffer> {
  const wb = new ExcelJS.Workbook();

  // INSUMOS: una fila por producto, con precio y merma. Los "Plato finalizado" son los platos de la carta.
  const supplies = wb.addWorksheet("INSUMOS");
  supplies.addRow([
    "CODIGO",
    "RUBRO",
    "PRODUCTO",
    "PROVEEDOR",
    "MARCA",
    "$ NETO x KG / LITRO",
    "$ X KG / LITRO",
    "PRESENTACIÓN (GRS)",
    "$",
    "PESO NETO (GRS)",
    "DIFERENCIA PESO",
    "% DESPERDICIO",
    "FACTOR DE CORRECCION",
  ]);
  supplies.addRow([
    190000,
    "Almacén",
    "AJONJOLI XLS",
    null,
    null,
    18840,
    18840,
    10000,
    188400,
    10000,
    0,
    0,
    1,
  ]);
  supplies.addRow([
    190001,
    "Almacén",
    "SAL GRUESA XLS",
    null,
    null,
    2000,
    2000,
    1000,
    2000,
    1000,
    0,
    0,
    1,
  ]);
  supplies.addRow([
    140000,
    "Verduras",
    "ZAPALLO XLS",
    null,
    null,
    5000,
    4000,
    1000,
    4000,
    800,
    200,
    0.2,
    1.25,
  ]);
  supplies.addRow([
    110000,
    "Fiambres y quesos",
    "QUESO TYBO XLS",
    null,
    null,
    8591,
    8591,
    1000,
    8591,
    1000,
    0,
    0,
    1,
  ]);
  const harina = supplies.addRow([
    190002,
    "Almacén",
    "SEMOLA XLS",
    null,
    null,
    null,
    null,
    1000,
    1500,
    1000,
    0,
    0,
    1,
  ]);
  // Una fórmula que en el Excel da error: la celda queda vacía.
  harina.getCell(6).value = {
    formula: "I6/0",
    result: { error: "#DIV/0!" },
  } as ExcelJS.CellFormulaValue;
  supplies.addRow([240000, "Plato finalizado", "PIZZA XLS"]);
  supplies.addRow([240001, "Plato finalizado", "FOCACCIA XLS SIN RECETA"]);

  // pre-elaborado: bloques con título (código, nombre, peso neto total) y líneas.
  const preps = wb.addWorksheet("pre-elaborado");
  preps.getRow(2).values = [
    300000,
    null,
    null,
    null,
    "SALSA XLS PE",
    null,
    "Peso Neto Total Receta",
    null,
    1000,
  ];
  preps.getRow(4).values = [
    null,
    null,
    "CODIGO",
    null,
    "INGREDIENTES",
    null,
    "Medida",
    null,
    "Receta (GRS)",
  ];
  preps.getRow(6).values = [null, null, 140000, null, "ZAPALLO XLS", null, "GRAMOS", null, 800];
  preps.getRow(7).values = [null, null, 190000, null, "AJONJOLI XLS", null, "CUP 60", null, 50];
  preps.getRow(9).values = [null, null, null, null, null, null, "Peso Bruto Total", null, 850];
  preps.getRow(11).values = [
    300001,
    null,
    null,
    null,
    "MASA XLS PE",
    null,
    "Peso Neto Total Receta",
    null,
    1200,
  ];
  preps.getRow(13).values = [
    null,
    null,
    "CODIGO",
    null,
    "INGREDIENTES",
    null,
    "Medida",
    null,
    "Receta (GRS)",
  ];
  preps.getRow(15).values = [null, null, 190002, null, "SEMOLA XLS", null, "GRAMOS", null, 1000];
  preps.getRow(16).values = [null, null, 300000, null, "SALSA XLS PE", null, "1 CUP", null, 100];
  preps.getRow(17).values = [null, null, 999999, null, "#N/A", null, "GRAMOS", null, 5];

  // PLATOS: el mismo formato, con precio por porción en el título y porciones al final del bloque.
  const dishes = wb.addWorksheet("PLATOS");
  dishes.getRow(2).values = [240000, null, "PIZZA XLS", null, "Precio por porción", null, 1234];
  dishes.getRow(4).values = ["CODIGO", null, "INGREDIENTES", null, "Medida", null, "Receta (GRS)"];
  dishes.getRow(6).values = [300001, null, "MASA XLS PE", null, "1 UNIDAD", null, 360];
  dishes.getRow(7).values = [110000, null, "QUESO TYBO XLS", null, "CUP 250", null, 300];
  dishes.getRow(8).values = [190001, null, "SAL GRUESA XLS", null, "GRAMOS", null, 0];
  dishes.getRow(10).values = [null, null, null, null, "Peso Total", null, 660];
  dishes.getRow(12).values = [
    null,
    null,
    "Peso por porción",
    null,
    660,
    null,
    "Cantidad de porciones/unidades x receta",
    null,
    null,
    null,
    1,
  ];
  dishes.getRow(16).values = [
    240002,
    null,
    "PLATO SOLO EN PLATOS",
    null,
    "Precio por porción",
    null,
    999,
  ];
  // Un número suelto entre el título y el encabezado: no es el título.
  dishes.getRow(17).values = [36];
  dishes.getRow(18).values = ["CODIGO", null, "INGREDIENTES", null, "Medida", null, "Receta (GRS)"];
  dishes.getRow(20).values = [140000, null, "ZAPALLO XLS", null, "2 FETAS", null, 150];
  // Sin porciones cargadas y un costo más a la derecha: el costo no son porciones.
  dishes.getRow(22).values = [
    null,
    null,
    null,
    null,
    null,
    null,
    "Cantidad de porciones/unidades x receta",
    null,
    null,
    null,
    null,
    null,
    9999,
  ];
  // Una plantilla vacía al final, sin código ni nombre: no es una receta ni se suma al bloque anterior.
  // Con un precio a la derecha de la etiqueta: el precio no es un código.
  dishes.getRow(24).values = [null, null, null, null, "Precio por porción", null, 777];
  dishes.getRow(26).values = ["CODIGO", null, "INGREDIENTES", null, "Medida", null, "Receta (GRS)"];
  // Otra con un número suelto como código y nada cargado.
  dishes.getRow(30).values = [5862, null, null, null, "Precio por porción"];
  dishes.getRow(32).values = ["CODIGO", null, "INGREDIENTES", null, "Medida", null, "Receta (GRS)"];

  // Otras solapas del recetario (ventas, cotización): se ignoran.
  const quote = wb.addWorksheet("COTIZACION ACTUAL");
  quote.addRow(["RUBRO", "CODIGO SISTEMA", "ARTÍCULO", "PRECIO DE VTA ACTUAL"]);
  if (mark) quote.addRow([mark]);

  const buffer = await wb.xlsx.writeBuffer();
  return buffer instanceof ArrayBuffer ? buffer : new Uint8Array(buffer).buffer;
}
