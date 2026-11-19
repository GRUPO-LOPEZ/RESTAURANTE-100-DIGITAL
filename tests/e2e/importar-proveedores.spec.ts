// Importar proveedores desde planilla (ADR-0055): Compras baja la plantilla, sube una planilla inventada con un error,
// lo ve, sube la corregida y crea los proveedores. La cocinera no ve el botón ni la pantalla. Con axe y sin scroll en
// la computadora. Nombres y CUIT nuevos en cada corrida (inventados, con dígito verificador), así se puede repetir.
import AxeBuilder from "@axe-core/playwright";
import ExcelJS from "exceljs";
import { expect, test, type Page } from "@playwright/test";

import { inventedCuit as cuit, login } from "./helpers";

const COMPRAS = "compras@ejemplo.test";
const COCINERA = "cocinero@ejemplo.test";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noVerticalScroll(page: Page) {
  const { scroll, client } = await page.evaluate(() => {
    const d = document.scrollingElement ?? document.documentElement;
    return { scroll: d.scrollHeight, client: d.clientHeight };
  });
  expect(scroll).toBeLessThanOrEqual(client);
}

async function planilla(rows: (string | number)[][]): Promise<Buffer> {
  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet("Proveedores");
  ws.addRow([
    "Razón social",
    "CUIT",
    "Rubros",
    "Días de entrega",
    "Canal de la OC",
    "Destino de la OC",
  ]);
  for (const r of rows) ws.addRow(r);
  return Buffer.from(await wb.xlsx.writeBuffer());
}

// El renglón con el número del indicador, sin la etiqueta ni el nombre del archivo.
const metric = (page: Page, label: string) =>
  page.locator('[data-slot="kpi"]', { hasText: label }).locator("p:has(> span)").first();

// Lo que anuncia el lector de pantalla (la barra de abajo dice lo mismo, oculta para él).
const announced = (page: Page, text: string) =>
  page.getByRole("status").filter({ hasText: text }).first();

const SCREENS = [
  [1440, 900],
  [1600, 900],
  [1715, 843],
  [1920, 1080],
] as const;

async function noScrollOnScreens(page: Page) {
  for (const [width, height] of SCREENS) {
    await page.setViewportSize({ width, height });
    await noVerticalScroll(page);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "la carga inicial se hace en la computadora");

  test("Compras importa proveedores: ve el error, corrige y crea", async ({ page }) => {
    const stamp = String(Date.now()).slice(-8);
    const uno = { name: `Importado Uno ${stamp}`, cuit: cuit(`30${stamp}`) };
    const dos = { name: `Importado Dos ${stamp}`, cuit: cuit(`33${stamp}`) };

    await login(page, COMPRAS, { mfa: true });
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("/proveedores");
    await page.getByRole("link", { name: "Importar desde planilla" }).click();
    await expect(
      page.getByRole("heading", { level: 1, name: "Importar proveedores" }),
    ).toBeVisible();

    // La plantilla se baja y es un Excel.
    const download = page.waitForEvent("download");
    await page.getByRole("link", { name: "Bajar la plantilla" }).click();
    expect((await download).suggestedFilename()).toBe("plantilla-proveedores.xlsx");
    // Antes de revisar: los 4 indicadores sin datos (nunca en verde) y la tabla vacía con su motivo.
    await expect(metric(page, "Con error")).toHaveText(/^—/);
    await expect(page.getByText("Todavía no subiste la planilla.")).toBeVisible();
    await noScrollOnScreens(page);
    await axe(page);

    // Una planilla con un rubro que no existe: la vista previa lo muestra y no deja crear.
    const file = page.getByLabel("2. Subí la planilla completa (.xlsx)");
    await file.setInputFiles({
      name: "proveedores.xlsx",
      mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      buffer: await planilla([
        [uno.name, uno.cuit, "Verduras y frutas", "lun, jue", "WhatsApp", "+54 9 11 4000-0001"],
        [dos.name, dos.cuit, "Bebidas espirituosas", "", "", ""],
      ]),
    });
    await page.getByRole("button", { name: "Revisar", exact: true }).click();
    await expect(metric(page, "Con error")).toHaveText(/^1(?![0-9])/);
    await expect(metric(page, "Se crean")).toHaveText(/^1(?![0-9])/);
    const preview = page
      .getByRole("table", { name: "Vista previa de la importación" })
      .locator("visible=true");
    await expect(preview).toContainText(
      "Rubros: «Bebidas espirituosas» no es un rubro de compra del grupo.",
    );
    await expect(page.getByRole("button", { name: /^Crear/ })).toHaveCount(0);
    await expect(announced(page, "Corregí la planilla y subila de nuevo")).toBeAttached();
    await noScrollOnScreens(page);
    await axe(page);

    // La corregida: se crean los dos, con motivo.
    await file.setInputFiles({
      name: "proveedores.xlsx",
      mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      buffer: await planilla([
        [uno.name, uno.cuit, "Verduras y frutas", "lun, jue", "WhatsApp", "+54 9 11 4000-0001"],
        [dos.name, dos.cuit, "Almacén", "", "", ""],
      ]),
    });
    await page.getByRole("button", { name: "Revisar", exact: true }).click();
    await expect(metric(page, "Con error")).toHaveText(/^0(?![0-9])/);
    const crear = page.getByRole("button", { name: "Crear 2 proveedores" });
    const motivo = page.getByRole("textbox", { name: "Motivo de la importación" });
    // Sin motivo no crea: lo dice al lado del campo y lleva el foco ahí.
    await crear.click();
    await expect(page.getByText("Escribí el motivo.")).toBeVisible();
    await expect(motivo).toBeFocused();
    await axe(page);
    // Un motivo que la base no acepta (muy corto): el aviso se ve y se puede corregir sin volver a subir.
    await motivo.fill("ok");
    await crear.click();
    await expect(page.getByText("Escribí el motivo de la importación.")).toBeVisible();
    await expect(crear).toBeEnabled();
    await motivo.fill("Carga inicial (prueba)");
    await crear.click();

    await expect(page).toHaveURL(/\/proveedores\?aviso=importados&n=2$/);
    await expect(page.getByText("Se crearon 2 proveedores desde la planilla.")).toBeVisible();
    await page.getByLabel("Buscar").fill(stamp);
    await page.getByLabel("Buscar").press("Enter");
    const table = page.getByRole("table", { name: "Proveedores" }).locator("visible=true");
    await expect(table).toContainText(uno.name);
    await expect(table).toContainText(dos.name);

    // Subir la misma planilla de nuevo: se omiten los dos.
    await page.goto("/proveedores/importar");
    await page.getByLabel("2. Subí la planilla completa (.xlsx)").setInputFiles({
      name: "proveedores.xlsx",
      mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      buffer: await planilla([
        [uno.name, uno.cuit],
        [dos.name, dos.cuit],
      ]),
    });
    await page.getByRole("button", { name: "Revisar", exact: true }).click();
    await expect(metric(page, "Se omiten")).toHaveText(/^2(?![0-9])/);
    await expect(announced(page, "No hay proveedores nuevos para crear.")).toBeAttached();
    await expect(page.getByRole("button", { name: /^Crear/ })).toHaveCount(0);
  });

  test("la cocinera no importa proveedores", async ({ page }) => {
    await login(page, COCINERA);
    await page.goto("/proveedores");
    await expect(page.getByRole("heading", { level: 1, name: "Proveedores" })).toBeVisible();
    await expect(page.getByRole("link", { name: "Importar desde planilla" })).toHaveCount(0);
    await page.goto("/proveedores/importar");
    await expect(page).not.toHaveURL(/importar/);
    const plantilla = await page.request.get("/proveedores/importar/plantilla", {
      maxRedirects: 0,
    });
    expect(plantilla.status()).toBe(307);
  });
});

test("en el celular, la importación avisa que se hace en la computadora", async ({
  page,
  isMobile,
}) => {
  test.skip(!isMobile, "solo en el celular");
  await login(page, COMPRAS, { mfa: true });
  await page.goto("/proveedores");
  await expect(page.getByRole("link", { name: "Importar desde planilla" })).toHaveCount(0);
  await page.goto("/proveedores/importar");
  await expect(
    page.getByText("La importación de proveedores se hace en la computadora."),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Revisar", exact: true })).toBeHidden();
  const { scroll, client } = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));
  expect(scroll).toBeLessThanOrEqual(client);
  await axe(page);
});
