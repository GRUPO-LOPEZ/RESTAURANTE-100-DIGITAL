// Subrecetas y variantes (Fase 2, etapa 2.2 B; ADR-0025 y ADR-0026): la Chef agrega una preparación
// desde el buscador, la ficha la enlaza, el Chef del grupo ve dónde se usa y sus avisos, la Cocinera
// pasa del plato a la preparación en la vista de cocina, y la Chef crea una variante para un local.
// En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice, openAction } from "./helpers";

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
  await page.getByRole("link", { name, exact: true }).first().click();
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
  await page.locator("#rec-alta-codigo").fill(`E2E-SUB-${n}`);
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-tipo").selectOption("dish");
  await page.locator("#rec-alta-motivo").fill("Receta de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();

  // El buscador separa materias primas y preparaciones.
  await page.getByLabel("Agregar materia prima o preparación").fill("bolognesa");
  const preparations = page.getByRole("list", { name: /^Preparaciones/ });
  await expect(preparations).toBeVisible();
  await axe(page);
  await preparations.getByRole("button", { name: /Salsa bolognesa/ }).click();
  const lines = page.getByRole("list", { name: "Componentes del borrador" });
  await expect(lines.getByText("Preparación", { exact: true })).toBeVisible();
  // Rinde en kilos: se sugiere gramos, y no se pregunta la base de la cantidad.
  await expect(lines.getByLabel("Unidad", { exact: true }).first()).toHaveValue("g");
  await expect(lines.getByLabel("La cantidad es")).toHaveCount(0);
  await expect(lines.getByText("Cantidad terminada")).toBeVisible();
  // Solo unidades de peso, como su rendimiento: no se puede elegir una que la base rechace.
  await expect(lines.getByLabel("Unidad", { exact: true }).first().locator("option")).toHaveText([
    "g",
    "kg",
  ]);
  await lines.getByLabel("Cantidad", { exact: true }).first().fill("180");
  await page.getByLabel("Motivo de los cambios").first().fill("Lleva la bolognesa de la casa");
  await page.getByRole("button", { name: "Guardar componentes" }).click();
  await expect(notice(page).filter({ hasText: "Componentes guardados (1)" })).toBeVisible();
  await noRepeatedIds(page);
  await noHorizontalScroll(page);

  // En una receta publicada, la preparación es un enlace a su ficha.
  await openRecipe(page, "Lasaña bolognesa");
  const components = page.getByRole("list", { name: "Componentes", exact: true });
  await expect(components.getByRole("link", { name: "Salsa blanca" })).toBeVisible();
  await expect(components.getByText("Preparación").first()).toBeVisible();
  await axe(page);
});

test("el Chef del grupo ve dónde se usa una salsa y sus avisos de cambios", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await openRecipe(page, "Salsa bolognesa");
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
  await expect(page.getByRole("heading", { name: "Variantes de local" })).toBeVisible();
  const options = page.locator('select[id$="-variante-local"] option', { hasText: place });
  if ((await options.count()) > 0) {
    await openAction(page, "Crear una variante para un local");
    await page.locator('select[id$="-variante-local"]').selectOption({ label: place });
    await page.getByLabel("Código de la variante").fill(`E2E-VAR-${Date.now() % 1_000_000}`);
    await page.getByLabel("Nombre de la variante").fill(name);
    await page.locator('textarea[id$="-motivo-variante"]').fill("Variante de prueba automática");
    await page.getByRole("button", { name: "Crear variante" }).click();
  } else {
    await page.getByRole("list", { name: "Variantes" }).getByRole("link", { name }).click();
  }
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await expect(page.getByText("Variante", { exact: true }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: "Ravioles de ricota", exact: true })).toBeVisible();
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
