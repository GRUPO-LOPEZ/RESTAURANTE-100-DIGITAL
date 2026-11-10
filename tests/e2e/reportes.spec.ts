// Reportes (ADR-0034): sacar la información en PDF, Excel y CSV. En celular y computadora, con axe.
import { readFile } from "node:fs/promises";

import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login } from "./helpers";

test.describe.configure({ timeout: 90_000 });

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noOverflow(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

const PASTAS_CENTRO = "00000000-0000-4000-8000-000000000201";
const RAVIOLES = "00000000-0000-4000-8000-000000001108";
// Vacío a la parrilla (DEMO-PAR-02): de otra marca; el Controller la ve, pero no es del local de Pastas.
const VACIO = "00000000-0000-4000-8000-000000001113";

test("el Controller saca un reporte en Excel, en CSV y en PDF", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/reportes?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: "¿Qué reporte necesitás?" })).toBeVisible();
  const list = page.getByRole("navigation", { name: "Reportes" });
  for (const title of [
    "Materias primas",
    "Rendimientos",
    "Dónde se usa",
    "Cambios de costo",
    "Calidad de datos",
  ]) {
    await expect(list.getByRole("link", { name: new RegExp(title) })).toBeVisible();
  }
  await axe(page);
  await noOverflow(page);

  await list.getByRole("link", { name: /Materias primas/ }).click();
  await expect(page.getByRole("heading", { name: "Materias primas" })).toBeVisible();
  await expect(page.getByText(/Demo Pastas Centro · Datos del/).first()).toBeVisible();
  await axe(page);
  await noOverflow(page);
  const size = page.viewportSize();
  for (const width of [360, 640, 768, 1024]) {
    await page.setViewportSize({ width, height: 900 });
    await noOverflow(page);
  }
  if (size) await page.setViewportSize(size);

  const excel = page.waitForEvent("download");
  await page.getByRole("link", { name: "Bajar en Excel" }).click();
  expect((await excel).suggestedFilename()).toMatch(/^reporte-ingredients-.*\.xlsx$/);

  const csv = page.waitForEvent("download");
  await page.getByRole("link", { name: "Bajar en CSV" }).click();
  expect((await csv).suggestedFilename()).toMatch(/^reporte-ingredients-.*\.csv$/);

  // La vista para imprimir trae todas las filas, sin paginar.
  await page.getByRole("link", { name: "Preparar para imprimir o PDF" }).click();
  await expect(page).toHaveURL(/imprimir=1/);
  // Imprimir: se anota y abre el diálogo del navegador, que acá se reemplaza.
  await page.evaluate(() => {
    window.print = () => {
      document.body.dataset.printed = "si";
    };
  });
  await page.getByRole("button", { name: "Imprimir o guardar como PDF" }).click();
  await expect(page.locator("body")).toHaveAttribute("data-printed", "si");
  await axe(page);

  // Al imprimir no salen el menú ni los botones, y sale la tabla aunque sea un celular.
  await page.emulateMedia({ media: "print" });
  await expect(page.getByRole("button", { name: "Imprimir o guardar como PDF" })).toBeHidden();
  await expect(page.locator("table").first()).toBeVisible();
  // Cada hoja dice de qué es: el encabezado se repite.
  await expect(page.locator("thead").first()).toContainText(
    /Grupo LF · Materias primas · Demo Pastas Centro/,
  );
});

test("cambios de costo se pide por período", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/reportes/cost_changes?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: "Cambios de costo" })).toBeVisible();
  await expect(page.getByLabel("Desde")).toBeVisible();
  await page.getByLabel("Desde").fill("2020-01-01");
  await page.getByLabel("Hasta").fill("2020-01-31");
  // El período se aplica solo, sin botón (ADR-0036), y conserva el local.
  await expect(page).toHaveURL(/desde=2020-01-01/);
  await expect(page).toHaveURL(/hasta=2020-01-31/);
  await expect(page).toHaveURL(/local=/);
  await expect(page.getByText("No hubo cambios de costo en este período.")).toBeVisible();
  await axe(page);
});

test("un reporte largo va por páginas, y para imprimir trae todo", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/reportes/usage?local=${PASTAS_CENTRO}`);
  await expect(page.getByText(/Página 1 de \d+/)).toBeVisible();
  await page.getByRole("link", { name: "Siguiente" }).click();
  await expect(page.getByText(/Página 2 de \d+/)).toBeVisible();
  await page.goto(`/reportes/usage?local=${PASTAS_CENTRO}&imprimir=1`);
  await expect(page.getByRole("button", { name: "Imprimir o guardar como PDF" })).toBeVisible();
  await expect(page.getByText(/Página \d+ de/)).toHaveCount(0);
});

test("quien ve el registro de seguridad ve las exportaciones", async ({ page }) => {
  await login(page, "auditor@ejemplo.test");
  const download = await page.request.get(
    `/reportes/yields/exportar?local=${PASTAS_CENTRO}&formato=csv`,
  );
  expect(download.ok()).toBe(true);
  await page.goto(`/reportes?local=${PASTAS_CENTRO}`);
  // Una tabla en la computadora y tarjetas en el celular (ADR-0036).
  const exported = page
    .getByRole("table", { name: "Últimas exportaciones" })
    .getByRole("row")
    .or(page.getByRole("list", { name: "Últimas exportaciones" }).getByRole("listitem"))
    .filter({ hasText: "Rendimientos" })
    .filter({ hasText: "CSV" });
  await expect(exported.first()).toBeVisible();
  await axe(page);
});

test("la ficha técnica y la de costeo de una receta", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/reportes?local=${PASTAS_CENTRO}`);
  await page
    .getByRole("navigation", { name: "Reportes" })
    .getByRole("link", { name: /Ficha técnica/ })
    .click();
  await expect(page.getByText("¿De qué receta?")).toBeVisible();
  // La búsqueda se aplica sola al dejar de escribir.
  await page.getByLabel("Buscar", { exact: true }).fill("raviol");
  await expect(page).toHaveURL(/buscar=raviol/);
  await page
    .getByRole("list", { name: "Recetas" })
    .getByRole("link", { name: /Ravioles de ricota/ })
    .click();
  await expect(page.getByRole("list", { name: "De qué receta es" })).toContainText(
    "Ravioles de ricota",
  );
  await expect(page.getByRole("list", { name: "Paso a paso" })).toBeVisible();
  // Los alérgenos, siempre: es lo primero que se mira en la mesada.
  await expect(
    page.getByRole("list", { name: "Alérgenos" }).getByRole("listitem").first(),
  ).toBeVisible();
  // La ficha técnica nunca trae un importe.
  // Solo la pantalla visible: Next guarda oculta la anterior (la búsqueda ya no recarga la página).
  await expect(page.locator("main:visible")).not.toContainText(/\$\s?\d/);
  await expect(page.getByRole("button", { name: "Imprimir o guardar como PDF" })).toBeVisible();
  await axe(page);
  await noOverflow(page);
  const csv = page.waitForEvent("download");
  await page.getByRole("link", { name: "Bajar en CSV" }).click();
  const file = await csv;
  expect(file.suggestedFilename()).toMatch(/^reporte-recipe_card-.*\.csv$/);
  // El archivo también lleva los alérgenos, en el encabezado.
  const text = await readFile(await file.path(), "utf8");
  expect(text).toContain("Alérgenos:");

  // Una receta de otra marca, pedida a mano, no sale a nombre de este local.
  await page.goto(`/reportes/recipe_card?local=${PASTAS_CENTRO}&receta=${VACIO}`);
  await expect(page.getByText("No encontramos esta página")).toBeVisible();
  const other = await page.request.get(
    `/reportes/recipe_card/exportar?local=${PASTAS_CENTRO}&receta=${VACIO}&formato=csv`,
    { maxRedirects: 0 },
  );
  expect(other.status()).toBe(404);

  // Una búsqueda sin resultados lo dice, y propone otra cosa.
  await page.goto(`/reportes/recipe_card?local=${PASTAS_CENTRO}&buscar=zzzz`);
  await expect(
    page.getByText("No encontramos recetas vigentes con ese nombre o código."),
  ).toBeVisible();
  // Sin acentos también la encuentra.
  await page.goto(`/reportes/recipe_card?local=${PASTAS_CENTRO}&buscar=noquis`);
  await expect(page.getByRole("list", { name: "Recetas" })).toContainText("Ñoquis");

  await page.goto(`/reportes/cost_card?local=${PASTAS_CENTRO}&receta=${RAVIOLES}`);
  await expect(page.getByRole("list", { name: "De qué receta es" })).toContainText("Total sin IVA");
  await expect(
    page.locator("table:visible, ul[aria-label='Filas de Ficha de costeo']:visible").first(),
  ).toContainText("Salsa bolognesa");
  await axe(page);
  await noOverflow(page);
});

test("la Chef no saca el reporte de precios", async ({ page }) => {
  await login(page, "chef@ejemplo.test");
  await page.goto(`/reportes?local=${PASTAS_CENTRO}`);
  const list = page.getByRole("navigation", { name: "Reportes" });
  await expect(list.getByRole("link", { name: /Rendimientos/ })).toBeVisible();
  await expect(list.getByRole("link", { name: /Materias primas/ })).toHaveCount(0);
  await page.goto(`/reportes/ingredients?local=${PASTAS_CENTRO}`);
  await expect(page.getByText("No encontramos esta página")).toBeVisible();
  const download = await page.request.get(
    `/reportes/ingredients/exportar?local=${PASTAS_CENTRO}&formato=csv`,
    { maxRedirects: 0 },
  );
  expect(download.status()).not.toBe(200);
});

test("Compras no tiene reportes", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await expect(page.getByRole("link", { name: "Reportes", exact: true })).toHaveCount(0);
  await page.goto("/reportes");
  await expect(page).not.toHaveURL(/reportes/);
});

test("un formato o un reporte que no existe no abre nada", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  const format = await page.request.get(
    `/reportes/ingredients/exportar?local=${PASTAS_CENTRO}&formato=doc`,
  );
  expect(format.status()).toBe(404);
  await page.goto(`/reportes/no_existe?local=${PASTAS_CENTRO}`);
  await expect(page.getByText("No encontramos esta página")).toBeVisible();
});

// Rediseño (ADR-0036): el local es el de la barra de arriba. Sin selector propio; con «Todos mis
// locales», la pantalla pide uno y lleva a sus reportes.
test("Reportes usa el local de la barra de arriba", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/reportes");
  await expect(page.getByText("Elegí un local para ver sus reportes.")).toBeVisible();
  await expect(page.getByRole("main").getByRole("combobox")).toHaveCount(0);
  await axe(page);
  await page
    .getByRole("list", { name: "Tus locales" })
    .getByRole("link", { name: "Demo Pastas Centro" })
    .click();
  await expect(page).toHaveURL(new RegExp(`local=${PASTAS_CENTRO}`));
  await expect(page.getByRole("heading", { name: "Reportes de Demo Pastas Centro" })).toBeVisible();
  // El reporte vuelve a la lista de su local.
  await page
    .getByRole("navigation", { name: "Reportes" })
    .getByRole("link", { name: /Rendimientos/ })
    .click();
  await page.getByRole("link", { name: "Volver a los reportes" }).click();
  await expect(page).toHaveURL(new RegExp(`/reportes\\?local=${PASTAS_CENTRO}$`));
});

// Cambiar el local arriba, con un reporte abierto, muestra el mismo reporte del otro local (el selector saca
// ?local= de la dirección). Con «Todos mis locales», pide uno (revisión de diseño del PR 3).
test("el selector de arriba cambia el local de un reporte abierto", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/reportes/usage?local=${PASTAS_CENTRO}`);
  await expect(page.getByText(/Demo Pastas Centro · Datos del/).first()).toBeVisible();
  try {
    await page.getByLabel("Local activo").selectOption({ label: "Demo Pastas Norte · PASTAS" });
    await page.getByRole("button", { name: "Cambiar" }).click();
    await expect(page).not.toHaveURL(/local=/, { timeout: 20_000 });
    await expect(page.getByRole("heading", { name: "Dónde se usa" })).toBeVisible();
    await expect(page.getByText(/Demo Pastas Norte · Datos del/).first()).toBeVisible();
  } finally {
    await page.getByLabel("Local activo").selectOption({ label: "Todos mis locales" });
    await page.getByRole("button", { name: "Cambiar" }).click();
  }
  await expect(page.getByText("Elegí un local para ver este reporte.")).toBeVisible({
    timeout: 20_000,
  });
  await axe(page);
});
