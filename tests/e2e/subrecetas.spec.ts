// Subrecetas y variantes (Fase 2, etapa 2.2 B; ADR-0025 y ADR-0026): la Chef agrega una preparación
// desde el buscador, la ficha la enlaza, el Chef del grupo ve dónde se usa y sus avisos, la Cocinera
// pasa del plato a la preparación en la vista de cocina, y la Chef crea una variante para un local.
// En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, openAction, openSection, saveSheet } from "./helpers";

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// Next guarda ocultas las páginas anteriores: un id repetido dejaría una etiqueta sin su campo.
async function noRepeatedIds(page: Page) {
  const repeated = await page.evaluate(() => {
    const ids = [...document.querySelectorAll("[id]")].map((el) => el.id);
    return ids.filter((id, i) => ids.indexOf(id) !== i);
  });
  expect(repeated).toEqual([]);
}

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function openRecipe(page: Page, name: string) {
  await page.goto(`/recetas?q=${encodeURIComponent(name.slice(0, 8))}`);
  // La lista entra en Platos (ADR-0041): una preparación buscada ahí se alcanza con «Ver N en Preparaciones».
  const link = page.getByRole("link", { name, exact: true }).first();
  const other = page.getByRole("link", { name: /^Ver \d+ en Preparaciones$/ });
  await expect(link.or(other).first()).toBeVisible();
  if (!(await link.isVisible())) await other.click();
  await link.click();
}

test("la Chef agrega una preparación desde el buscador y la ficha la enlaza", async ({
  page,
}, testInfo) => {
  test.setTimeout(90_000);
  const n = `${testInfo.project.name === "celular" ? "C" : "D"}${Date.now() % 1_000_000}`;
  const name = `Tallarines con bolognesa ${n}`;
  await login(page, "chef@ejemplo.test");
  await page.goto("/recetas/nueva");
  await page.locator("#rec-alta-alcance").selectOption({ label: "De la marca Demo Pastas" });
  // Tipo y rubro: el código lo arma la base con los dos (ADR-0041).
  await page.getByRole("group", { name: "Tipo" }).getByText("Plato", { exact: true }).click();
  await page.locator("#rec-alta-categoria").selectOption({ label: "Pastas" });
  await expect(page.locator("#rec-alta-codigo")).toHaveValue(/^PLA-PAS-\d{4}$/);
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-motivo").fill("Receta de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();

  // La grilla de la ficha (ADR-0042) busca materias primas y preparaciones en la misma lista de sugerencias; la
  // preparación lleva su etiqueta. En el celular la ficha es de consulta: la carga se prueba en la computadora.
  if (testInfo.project.name !== "celular") {
    await openSection(page, "Ingredientes y costos");
    await page.getByLabel("Ingrediente, fila 1", { exact: true }).fill("bolognesa");
    const suggestions = page.getByRole("listbox", { name: "Sugerencias" });
    await expect(
      suggestions.getByRole("option", { name: /Salsa bolognesa.*Preparación/ }),
    ).toBeVisible();
    await axe(page);
    await suggestions
      .getByRole("option", { name: /Salsa bolognesa/ })
      .first()
      .click();
    await expect(
      page.getByRole("link", { name: "Abrir la preparación Salsa bolognesa" }),
    ).toBeVisible();
    // Rinde en kilos: se sugiere gramos, y solo unidades de peso, como su rendimiento: no se puede elegir una
    // que la base rechace.
    const unit = page.getByLabel("Medida, fila 1", { exact: true });
    await expect(unit).toHaveValue("g");
    await expect(unit.locator("option")).toHaveText([
      "Elegí",
      "Gramo (g)",
      "Kilogramo (kg)",
      "Miligramo (mg)",
      "Libra (lb)",
      "Onza (oz)",
      "Pizca",
    ]);
    await page.getByLabel("Cantidad, fila 1", { exact: true }).fill("180");
    // Una preparación va siempre en cantidad terminada: no se pregunta la base.
    await page.getByRole("button", { name: "Más opciones de la fila 1" }).click();
    await expect(page.getByLabel("La cantidad es")).toHaveCount(0);
    await saveSheet(page, "Lleva la bolognesa de la casa");
    await noRepeatedIds(page);
    await noHorizontalScroll(page);
  }

  // En una receta publicada, la preparación es un enlace a su ficha.
  await openRecipe(page, "Lasaña bolognesa");
  await openSection(page, "Ingredientes y costos");
  const prep =
    testInfo.project.name === "celular"
      ? page.getByRole("list", { name: "Ingredientes" }).getByRole("link", { name: "Salsa blanca" })
      : page.getByRole("link", { name: "Abrir la preparación Salsa blanca" });
  await expect(prep).toBeVisible();
  await axe(page);
});

test("el Chef del grupo ve dónde se usa una salsa y sus avisos de cambios", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await openRecipe(page, "Salsa bolognesa");
  await openSection(page, "Dónde se usa");
  const usage = page.getByRole("list", { name: "Recetas que la usan" });
  await expect(usage.getByRole("link", { name: "Lasaña bolognesa", exact: true })).toBeVisible();
  await expect(usage.getByRole("link", { name: "Ravioles de ricota", exact: true })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);

  // El aviso del seed: qué cambió y el enlace a la receta (no se marca como leído acá).
  await page.goto("/aprobaciones");
  const notices = page.getByRole("region", { name: /Avisos de recetas/ });
  await expect(
    notices.getByRole("heading", { name: "Cambió «Salsa bolognesa» (v1)" }),
  ).toBeVisible();
  await axe(page);
  await notices.getByRole("link", { name: "Ver la receta" }).first().click();
  await expect(page.getByRole("heading", { name: "Salsa bolognesa", exact: true })).toBeVisible();
});

test("la Cocinera pasa del plato a la ficha de cocina de su preparación", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await openRecipe(page, "Lasaña bolognesa");
  await expect(page).toHaveURL(/\/cocina$/);
  const ingredients = page.getByRole("list", { name: "Ingredientes" });
  await expect(ingredients.getByText("Preparación").first()).toBeVisible();
  await axe(page);
  await ingredients.getByRole("link", { name: "Salsa blanca" }).click();
  await expect(page).toHaveURL(/\/cocina$/);
  await expect(page.getByRole("heading", { name: "Salsa blanca", exact: true })).toBeVisible();
  await expect(page.getByText("Crear una variante para un local")).toHaveCount(0);
});

test("la Chef crea una variante para un local y la ve contra la maestra", async ({
  page,
}, testInfo) => {
  test.setTimeout(90_000);
  // Una variante por local: cada proyecto usa su local, y si ya existe (otra corrida) se abre esa.
  const place = testInfo.project.name === "celular" ? "Demo Pastas Centro" : "Demo Pastas Norte";
  const name = `Ravioles de ricota (${place.replace("Demo Pastas ", "")} e2e)`;
  await login(page, "chef@ejemplo.test");
  await openRecipe(page, "Ravioles de ricota");
  await openSection(page, "Dónde se usa");
  await expect(page.getByRole("heading", { name: "Variantes de local" })).toBeVisible();
  const options = page.locator('select[id$="-variante-local"] option', { hasText: place });
  if ((await options.count()) > 0) {
    await openAction(page, "Crear una variante para un local");
    await page.locator('select[id$="-variante-local"]').selectOption({ label: place });
    await page.getByLabel("Nombre de la variante").fill(name);
    await page.locator('textarea[id$="-motivo-variante"]').fill("Variante de prueba automática");
    await page.getByRole("button", { name: "Crear variante" }).click();
  } else {
    await page.getByRole("list", { name: "Variantes" }).getByRole("link", { name }).click();
  }
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await expect(page.getByText("Variante", { exact: true }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: "Ravioles de ricota", exact: true })).toBeVisible();
  // Las diferencias con la maestra van en «Dónde se usa» (ficha única, ADR-0042).
  await openSection(page, "Dónde se usa");
  await expect(page.getByRole("heading", { name: "Diferencias con la maestra" })).toBeVisible();
  await axe(page);
  await noRepeatedIds(page);
  await noHorizontalScroll(page);

  // La lista filtra las variantes de local (en celular son tarjetas; en computadora, una tabla).
  await page.goto("/recetas?alcance=variant");
  await expect(page.locator("a:visible", { hasText: name }).first()).toBeVisible();
  await expect(
    page.locator('[data-slot="badge"]:visible', { hasText: /^Variante$/ }).first(),
  ).toBeVisible();
  await expect(page.locator("a:visible", { hasText: "Lasaña bolognesa" })).toHaveCount(0);
});

test("el Jefe de Cocina no crea variantes", async ({ page }) => {
  await login(page, "jefecocina@ejemplo.test");
  await openRecipe(page, "Ravioles de ricota");
  await expect(page.getByText("Ravioles de ricota", { exact: true }).first()).toBeVisible();
  await expect(page.getByText("Crear una variante para un local")).toHaveCount(0);
});
