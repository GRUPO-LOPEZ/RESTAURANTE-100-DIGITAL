// Ficha única de receta (ADR-0042, Prompt 2 de Soy del 2026-11-12): en la computadora se carga un plato de punta a
// punta en la grilla (autocompletado por código y por nombre, la fila 11 que aparece sola, costos de la base, escala)
// y una preparación con su peso neto; quien revisa la ve en solo lectura y decide; en el celular es de consulta.
// Con axe; capturas en 1440, 1600, 1920 y celular.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { fillSheetRow, login, logout, notice, openSection, saveSheet } from "./helpers";

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const PASTAS_CENTRO = uuid(201);
const RAVIOLES = uuid(1108);

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

const kpi = (page: Page, label: string) =>
  page.locator('[data-slot="kpi"]').filter({ hasText: label });

async function choosePlace(page: Page) {
  await page.getByLabel("Local activo").selectOption(PASTAS_CENTRO);
  await page.getByRole("button", { name: "Cambiar" }).click();
  await expect(page.getByLabel("Local activo")).toHaveValue(PASTAS_CENTRO, { timeout: 20_000 });
}

async function newRecipe(page: Page, type: "Plato" | "Preparación", rubro: string, name: string) {
  await page.goto("/recetas/nueva");
  await page.locator("#rec-alta-alcance").selectOption({ label: "De la marca Demo Pastas" });
  await page.getByRole("group", { name: "Tipo" }).getByText(type, { exact: true }).click();
  await page.locator("#rec-alta-categoria").selectOption({ label: rubro });
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-motivo").fill("Ficha de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "La ficha se carga en la computadora (ADR-0036).");

  test("se carga un plato de punta a punta y quien revisa lo aprueba sin poder editarlo", async ({
    page,
  }) => {
    test.setTimeout(180_000);
    const name = `Ravioles de la ficha ${Date.now() % 1_000_000}`;
    await login(page, "director@ejemplo.test", { mfa: true });
    await choosePlace(page);
    await newRecipe(page, "Plato", "Pastas", name);

    // Una sola ficha con su índice; arranca con 10 filas.
    await expect(page.getByRole("navigation", { name: "Secciones de la receta" })).toBeVisible();
    await openSection(page, "Ingredientes y costos");
    await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(10);

    // Por código: se escribe el código y se elige la sugerencia.
    await page.getByLabel("Código, fila 1", { exact: true }).fill("DEMO-ING-027");
    await page
      .getByRole("listbox", { name: "Sugerencias" })
      .getByRole("option", { name: /Harina 000/ })
      .click();
    await expect(page.getByLabel("Ingrediente, fila 1", { exact: true })).toHaveValue("Harina 000");
    await page.getByLabel("Cantidad, fila 1", { exact: true }).fill("100");
    // Por nombre y con el teclado: flecha abajo y Enter.
    const ingredient = page.getByLabel("Ingrediente, fila 2", { exact: true });
    await ingredient.fill("Ricota");
    await expect(page.getByRole("listbox", { name: "Sugerencias" })).toContainText("Ricota");
    await ingredient.press("Enter");
    await expect(ingredient).toHaveValue("Ricota");
    await expect(page.getByLabel("Código, fila 2", { exact: true })).toHaveValue("DEMO-ING-021");
    await page.getByLabel("Cantidad, fila 2", { exact: true }).fill("120");

    // Los costos los calcula la base (sin precios: el Director ve costos, la columna de precio va con prices.view).
    const total = kpi(page, "Costo total de la receta, sin IVA");
    await expect(total).toContainText("$", { timeout: 20_000 });
    await expect(total).toContainText("Demo Pastas Centro");
    await expect(kpi(page, "Peso total de la receta")).toContainText("220 g");
    const row1 = page
      .getByRole("row")
      .filter({ has: page.getByLabel("Cantidad, fila 1", { exact: true }) });
    await expect(row1).toContainText("45,5 %");

    // Escala: «Hacer 2 recetas» duplica el peso, y el número queda en la dirección (no es un dato oficial).
    await page.getByLabel("Cantidad de recetas, columna A").fill("2");
    await expect(row1).toContainText("200 g");
    await expect(page).toHaveURL(/hacer=2(%2C|,)10/);

    // La fila 11 aparece sola al completar la última; quitarla vuelve a 10.
    await fillSheetRow(page, 10, "Sal fina", /Sal fina/, "2");
    await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(11);
    await page.getByRole("button", { name: "Más opciones de la fila 10" }).click();
    await page.getByRole("button", { name: "Quitar la fila" }).click();
    await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(10);

    // Rendimiento del plato: peso de la porción → porciones → costo por porción.
    await openSection(page, "Rendimiento");
    await page.getByLabel("Peso de la porción (g)").fill("110");
    await expect(kpi(page, "Porciones que salen")).toContainText("2");
    await expect(kpi(page, "Costo por porción")).toContainText("$");

    // Un paso y el envío a revisión, todo en un solo guardado.
    await openSection(page, "Procedimiento");
    await page.getByRole("button", { name: "Agregar paso" }).click();
    await page.getByLabel("Qué se hace").first().fill("Rellenar, cerrar y hervir.");
    await expect(page.getByRole("status").filter({ hasText: /cambios sin guardar/ })).toBeVisible();
    await axe(page);
    await noHorizontalScroll(page);
    await saveSheet(page, "Plato nuevo de la ficha", true);
    await expect(notice(page).filter({ hasText: "Está en revisión" })).toBeVisible();
    const url = page.url().split("?")[0] ?? page.url();
    await logout(page);

    // Quien revisa: la ficha en solo lectura, observaciones y «Aprobar» o «No aprobar».
    await login(page, "chefgrupo@ejemplo.test");
    await page.goto(url);
    await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    await expect(page.getByLabel("Cantidad, fila 1", { exact: true })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
    await expect(page.getByRole("table", { name: "Ingredientes y costos" })).toContainText(
      "Harina 000",
    );
    await openSection(page, "Versiones y aprobaciones");
    await page.getByLabel("Observaciones").fill("Bien la porción.");
    await axe(page);
    await page.getByRole("button", { name: "Aprobar", exact: true }).click();
    await expect(notice(page).filter({ hasText: "Aprobada y publicada" })).toBeVisible();
    await page.reload();
    await expect(page.getByText(/^Vigente v1$/)).toBeVisible();
  });

  test("se carga una preparación con su peso neto y su rendimiento", async ({ page }) => {
    test.setTimeout(120_000);
    const name = `Salsa de la ficha ${Date.now() % 1_000_000}`;
    await login(page, "chef@ejemplo.test");
    await newRecipe(page, "Preparación", "Salsas", name);
    await openSection(page, "Ingredientes y costos");
    await fillSheetRow(page, 1, "Tomate perita", /Tomate perita/, "1000");
    await fillSheetRow(page, 2, "Sal fina", /Sal fina/, "10");
    await openSection(page, "Rendimiento");
    await expect(kpi(page, "Peso bruto total")).toContainText(/1.?010 g/);
    await page.getByLabel("Peso neto total").fill("800");
    await page.getByLabel("Unidad", { exact: true }).selectOption("g");
    // 800 g netos ÷ 1.010 g brutos: el objetivo para el control de lotes.
    await expect(kpi(page, "Rendimiento (neto ÷ bruto)")).toContainText("79,2 %");
    await axe(page);
    await saveSheet(page, "Preparación de la ficha");
    await page.reload();
    await expect(page.getByLabel("Peso neto total")).toHaveValue("800");
    await expect(kpi(page, "Rendimiento (neto ÷ bruto)")).toContainText("79,2 %");
  });

  test("capturas de la ficha en 1440, 1600 y 1920", async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await login(page, "chefgrupo@ejemplo.test");
    for (const width of [1440, 1600, 1920]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.goto(`/recetas/${RAVIOLES}`);
      await expect(
        page.getByRole("heading", { name: "Ravioles de ricota", exact: true }),
      ).toBeVisible();
      await expect(page.getByRole("table", { name: "Ingredientes y costos" })).toBeVisible();
      await noHorizontalScroll(page);
      await page.screenshot({ path: testInfo.outputPath(`ficha-${width}.png`), fullPage: true });
    }
  });
});

test("en el celular la ficha es de consulta", async ({ page, isMobile }, testInfo) => {
  test.skip(!isMobile, "Solo en el celular.");
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto(`/recetas/${RAVIOLES}`);
  await expect(
    page.getByRole("heading", { name: "Ravioles de ricota", exact: true }),
  ).toBeVisible();
  // Ingredientes en tarjetas, totales y pasos; ni la planilla ni la barra de guardado.
  const ingredients = page.getByRole("list", { name: "Ingredientes" });
  await expect(ingredients).toContainText("Ricota");
  await expect(page.getByRole("table", { name: "Ingredientes y costos" })).toBeHidden();
  await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeHidden();
  await expect(kpi(page, "Peso total de la receta")).toBeVisible();
  await expect(page.getByRole("list", { name: "Pasos" })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  await page.screenshot({ path: testInfo.outputPath("ficha-celular.png"), fullPage: true });
});
