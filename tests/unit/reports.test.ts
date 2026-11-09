import ExcelJS from "exceljs";
import { describe, expect, it } from "vitest";

import { csvCell, csvNumber, safeText } from "@/lib/csv";
import { reportCsv, reportXlsx } from "@/lib/report-files";
import {
  REPORTS,
  allergenAlerts,
  allergenLine,
  argentinaDay,
  cookingEffect,
  formatValue,
  reportDefinition,
  reportFileName,
  reportPeriod,
} from "@/lib/report-labels";

const report = reportDefinition("cost_changes")!;
const header = { place: "Demo Pastas", generated: "7/11/26", period: "1/11/26 a 7/11/26" };
const row = {
  changed_on: "2026-11-05",
  recipe: "=HYPERLINK(1)",
  recipe_type: "Plato",
  version_number: 2,
  reason: "Cambio de precio",
  previous: 1000,
  current_cost: 1500,
  difference: 500,
  difference_pct: 50,
};

describe("las celdas seguras", () => {
  it("no dejan que una planilla ejecute una fórmula", () => {
    for (const text of ["=1+1", "+1", "-1", "@SUM(A1)", "  =1+1", "＝1+1"]) {
      expect(safeText(text).startsWith("'")).toBe(true);
    }
  });

  it("tampoco después de un separador: Excel en español corta por punto y coma", () => {
    expect(safeText("Salsa;=1+1;x")).toBe("Salsa;'=1+1;x");
  });

  it("un número no lleva apóstrofe", () => {
    expect(csvNumber("-$ 500,00")).toBe('"-$ 500,00"');
  });

  it("no tocan un texto común", () => {
    expect(safeText("Harina 000")).toBe("Harina 000");
  });

  it("escapan las comillas del CSV", () => {
    expect(csvCell('Queso "duro"')).toBe('"Queso ""duro"""');
    expect(csvCell(null)).toBe('""');
  });
});

describe("los valores", () => {
  it("se ven en español", () => {
    expect(formatValue(1500, "money")).toMatch(/1\.500,00/);
    expect(formatValue(0.905, "percent")).toBe("90,5 %");
    expect(formatValue(2.5, "unit_cost")).toMatch(/2,5000/);
    expect(formatValue("2026-11-05", "date")).toBe("5/11/26");
  });

  it("sin dato, una raya", () => {
    expect(formatValue(null, "money")).toBe("—");
    expect(formatValue("", "text")).toBe("—");
  });

  it("un cero no es falta de dato", () => {
    expect(formatValue(0, "number")).toBe("0");
  });
});

describe("el CSV", () => {
  const csv = reportCsv(report, header, [row]);

  it("lleva el local, la fecha y el período", () => {
    expect(csv).toContain("Local: Demo Pastas");
    expect(csv).toContain("Fecha de los datos: 7/11/26");
    expect(csv).toContain("Período: 1/11/26 a 7/11/26");
  });

  it("empieza con BOM, para que Excel lea los acentos", () => {
    expect(csv.charCodeAt(0)).toBe(0xfeff);
  });

  it("no deja pasar una fórmula", () => {
    expect(csv).toContain(`"'=HYPERLINK(1)"`);
  });

  it("separa con punto y coma, como abre Excel en español", () => {
    expect(csv).toContain('"Fecha";"Receta"');
  });
});

describe("el Excel", () => {
  it("lleva los números como números y los textos sin fórmula", async () => {
    const book = new ExcelJS.Workbook();
    await book.xlsx.load(await reportXlsx(report, header, [row]));
    const sheet = book.worksheets[0]!;
    expect(sheet.getCell("A1").value).toBe("Cambios de costo");
    const last = sheet.getRow(sheet.rowCount);
    expect(last.getCell(6).value).toBe(1000);
    expect(last.getCell(2).value).toBe("'=HYPERLINK(1)");
  });
});

describe("el período", () => {
  const today = new Date("2026-11-07T12:00:00Z");

  it("por defecto son los últimos 30 días", () => {
    expect(reportPeriod(undefined, undefined, today)).toEqual({
      from: "2026-10-08",
      to: "2026-11-07",
    });
  });

  it("una fecha inválida se ignora", () => {
    expect(reportPeriod("x'; drop", "2026-11-01", today).from).toBe("2026-10-02");
    expect(reportPeriod("2026-02-31", "2026-11-01", today).from).toBe("2026-10-02");
  });

  it("al revés se da vuelta", () => {
    expect(reportPeriod("2026-11-05", "2026-11-01", today)).toEqual({
      from: "2026-11-01",
      to: "2026-11-05",
    });
  });

  it("el día es el de la Argentina, no el de UTC", () => {
    expect(argentinaDay(new Date("2026-11-08T01:00:00Z"))).toBe("2026-11-07");
  });
});

describe("la cocción", () => {
  it("se lee como merma o como expansión", () => {
    expect(cookingEffect(0.8)).toBe("Merma de 20 %");
    expect(cookingEffect(1.2)).toBe("Expansión de 20 %");
    expect(cookingEffect(1)).toBe("No cambia");
  });
});

describe("los alérgenos de la ficha técnica", () => {
  it("primero lo que contiene, después las trazas y lo no verificado", () => {
    const alerts = allergenAlerts([
      { name: "Huevo", status: "may_contain" },
      { name: "Gluten", status: "contains" },
      { name: "Leche", status: "not_verified" },
      { name: "Soja", status: "not_verified" },
      { name: "Maní", status: "free_verified" },
    ]);
    expect(alerts).toEqual([
      { text: "Contiene Gluten", status: "bad" },
      { text: "Puede contener Huevo (trazas)", status: "warn" },
      { text: "Sin verificar: Leche, Soja", status: "warn" },
    ]);
    expect(allergenLine(alerts)).toEqual([
      "Alérgenos: Contiene Gluten · Puede contener Huevo (trazas) · Sin verificar: Leche, Soja",
    ]);
  });

  it("dice si no hay alérgenos cargados o si todo está verificado", () => {
    expect(allergenAlerts([])).toEqual([
      { text: "No hay alérgenos cargados en el catálogo", status: "info" },
    ]);
    expect(allergenAlerts([{ name: "Maní", status: "free_verified" }])).toEqual([
      { text: "Todo verificado: no contiene ningún alérgeno de la lista", status: "ok" },
    ]);
  });

  it("un reporte sin alérgenos no suma líneas al encabezado", () => {
    expect(allergenLine(undefined)).toEqual([]);
  });
});

describe("los reportes", () => {
  it("son siete, sin repetir", () => {
    expect(new Set(REPORTS.map((r) => r.key)).size).toBe(7);
  });

  it("las dos fichas se piden por receta", () => {
    expect(REPORTS.filter((r) => r.recipe).map((r) => r.key)).toEqual(["recipe_card", "cost_card"]);
  });

  it("el nombre del archivo no lleva acentos ni espacios", () => {
    expect(reportFileName("usage", "Demo Pastas Ñuñoa", "2026-11-07")).toBe(
      "reporte-usage-demo-pastas-nunoa-2026-11-07",
    );
  });
});
