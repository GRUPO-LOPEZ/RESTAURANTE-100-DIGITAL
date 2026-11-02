// Importar el recetario de Excel (Fase 2, etapa 2.4; ADR-0027): la Chef sube un Excel DEMO y ve la
// vista previa sin precios, baja los problemas en CSV, Compras confirma las materias primas, la Chef
// confirma las recetas, el mismo archivo no entra dos veces y la Cocinera no ve la importación.
// En celular y computadora, con axe. Nunca el Excel real.
import { writeFileSync } from "node:fs";
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { buildRecipeBook } from "../fixtures/recipe-book-fixture";
import { login, notice } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

async function upload(page: Page, file: string) {
  await page.goto("/recetas/importar/nueva");
  await page.getByLabel("Marca").selectOption({ label: "Demo Pastas" });
  const prefix = page.getByLabel("Prefijo de los códigos");
  // La primera importación de la marca elige el prefijo; las siguientes usan el mismo.
  if (await prefix.isEditable()) await prefix.fill("DEMO");
  await page.getByLabel("Recetario de Excel").setInputFiles(file);
  await page.getByLabel("Motivo").fill("Carga de prueba automática");
  await page.getByRole("button", { name: "Subir y revisar" }).click();
}

test("la Chef sube el recetario, Compras confirma las materias primas y la Chef, las recetas", async ({
  page,
  browser,
}, testInfo) => {
  test.setTimeout(180_000);
  const file = testInfo.outputPath("recetario-demo.xlsx");
  writeFileSync(file, Buffer.from(await buildRecipeBook(`${testInfo.project.name}-${Date.now()}`)));

  await login(page, "chef@ejemplo.test");
  await page.goto("/recetas");
  await page.getByRole("link", { name: "Importaciones" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Importaciones" })).toBeVisible();
  await axe(page);
  await page.getByRole("link", { name: "Importar recetario" }).click();
  // Sin archivo ni motivo: los errores debajo de cada campo, accesibles.
  await page.getByRole("button", { name: "Subir y revisar" }).click();
  await expect(page.getByText("Elegí el Excel.")).toBeVisible();
  await noHorizontalScroll(page);
  await axe(page);
  await upload(page, file);

  // La vista previa: totales y problemas por fila, sin un solo precio.
  await expect(
    page.getByRole("heading", { level: 1, name: "Vista previa de la importación" }),
  ).toBeVisible({ timeout: 60_000 });
  const url = page.url();
  await expect(page.getByText("Materias primas: 5", { exact: true })).toBeVisible();
  await expect(page.getByText("Preparaciones: 2", { exact: true })).toBeVisible();
  await expect(page.getByText(/^Platos: 3$/)).toBeVisible();
  await expect(page.getByRole("list", { name: "Problemas por fila" })).toContainText("999999");
  const body = await page.getByRole("main").innerText();
  for (const price of ["188400", "188.400", "18840", "18.840"]) expect(body).not.toContain(price);
  await expect(page.getByText("Falta que Compras confirme las materias primas.")).toBeVisible();
  await noHorizontalScroll(page);
  await axe(page);

  // El CSV de problemas.
  const download = page.waitForEvent("download");
  await page.getByRole("link", { name: "Descargar (CSV)" }).click();
  expect((await download).suggestedFilename()).toBe("problemas-importacion.csv");

  // El mismo archivo otra vez no entra.
  await upload(page, file);
  await expect(notice(page)).toContainText("Este archivo ya se importó");

  // Compras confirma las materias primas.
  const purchasing = await browser.newPage({ ...testInfo.project.use });
  await login(purchasing, "compras@ejemplo.test");
  await purchasing.goto(url);
  await purchasing.getByLabel("Motivo de la confirmación").fill("Materias primas del recetario de prueba");
  await purchasing.getByRole("button", { name: "Confirmar materias primas" }).click();
  // La pantalla pasa al paso siguiente: la confirmación queda en el encabezado.
  await expect(purchasing.getByText(/^Materias primas confirmadas el /)).toBeVisible();
  await expect(purchasing.getByText("Falta que la cocina confirme las recetas.")).toBeVisible();
  await purchasing.close();

  // La Chef confirma las recetas: quedan en borrador, con su enlace.
  await page.goto(url);
  await page.getByLabel("Motivo de la confirmación").fill("Recetas del recetario de prueba");
  await page.getByRole("button", { name: "Confirmar recetas" }).click();
  await expect(page.getByText(/^Recetas confirmadas el /)).toBeVisible();
  await expect(page.getByText("Confirmada", { exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: /^Recetas creadas: \d+$/ })).toBeVisible();
  await axe(page);
});

test("la Cocinera no ve la importación", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/recetas");
  await expect(page.getByRole("heading", { level: 1, name: "Recetas" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Importaciones" })).toHaveCount(0);
  await page.goto("/recetas/importar");
  await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();
});
