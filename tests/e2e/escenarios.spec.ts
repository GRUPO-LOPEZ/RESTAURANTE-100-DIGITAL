// Escenarios de costo (ADR-0032): simular un cambio sin tocar lo oficial. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice, openAction } from "./helpers";

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

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const PASTAS_CENTRO = uuid(201);

// Lo que /costos muestra de las recetas, sin la hora de actualización.
async function officialCosts(page: Page) {
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  const list = page.locator("table:visible, ul[aria-label='Costos de las recetas']:visible");
  await expect(list.first()).toBeVisible();
  return list.first().innerText();
}

test("el Controller simula un precio y lo oficial no cambia", async ({ page }, info) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  const before = await officialCosts(page);

  await page.getByRole("link", { name: "Escenarios" }).click();
  await expect(page.getByRole("heading", { name: "¿Qué pasaría si…?" })).toBeVisible();
  await expect(page.getByText("Es una simulación").first()).toBeVisible();
  await axe(page);

  const name = `E2E ${info.project.name} ${Date.now()}`;
  await openAction(page, "Nuevo escenario");
  await page.getByLabel("Nombre").fill(name);
  await page.getByLabel("Motivo").fill("Prueba automática");
  await page.getByRole("button", { name: "Crear escenario" }).click();
  await expect(page.getByText("Este escenario todavía no tiene cambios.")).toBeVisible();

  await openAction(page, "Precio, también de otro proveedor");
  const form = page.locator("details[open]");
  const select = form.getByLabel("Materia prima");
  const option = await select.locator("option", { hasText: "hoy" }).first().getAttribute("value");
  await select.selectOption(option ?? "");
  await form.getByLabel("Precio simulado").fill("999.999");
  await form.getByLabel("Motivo").fill("Prueba automática");
  await form.getByRole("button", { name: "Simular este precio" }).click();
  await expect(notice(page).filter({ hasText: "Precio simulado cargado" })).toBeVisible();

  await page.reload();
  await expect(page.getByRole("list", { name: "Cambios del escenario" })).toContainText("simulado");
  await expect(page.getByText("Recetas que cambiarían")).toBeVisible();
  await expect(page.getByText("Cómo quedarían las recetas (simulado)")).toBeVisible();
  // Un costo simulado nunca se lee como verificado.
  await expect(page.getByText(/verificado/i)).toHaveCount(0);
  await axe(page);
  await noOverflow(page);
  // Tablets y celulares acostados: ahí la tabla ya no entra.
  const size = page.viewportSize();
  for (const width of [640, 768, 1024]) {
    await page.setViewportSize({ width, height: 900 });
    await noOverflow(page);
  }
  if (size) await page.setViewportSize(size);

  // Lo oficial sigue igual.
  expect(await officialCosts(page)).toBe(before);
});

test("un precio inválido se explica", async ({ page }, info) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/costos/escenarios?local=${PASTAS_CENTRO}`);
  await openAction(page, "Nuevo escenario");
  await page.getByLabel("Nombre").fill(`E2E inválido ${info.project.name} ${Date.now()}`);
  await page.getByLabel("Motivo").fill("Prueba automática");
  await page.getByRole("button", { name: "Crear escenario" }).click();
  await expect(page.getByText("Este escenario todavía no tiene cambios.")).toBeVisible();
  await openAction(page, "Precio, también de otro proveedor");
  const form = page.locator("details[open]");
  const select = form.getByLabel("Materia prima");
  const option = await select.locator("option", { hasText: "hoy" }).first().getAttribute("value");
  await select.selectOption(option ?? "");
  await form.getByLabel("Precio simulado").fill("cero");
  await form.getByLabel("Motivo").fill("Prueba automática");
  await form.getByRole("button", { name: "Simular este precio" }).click();
  await expect(page.getByText(/Escribí un precio mayor que cero/)).toBeVisible();
});

test("el Gerente ve costos pero no escenarios", async ({ page }) => {
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: "¿Cuánto cuesta cada receta?" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Escenarios" })).toHaveCount(0);
  await page.goto("/costos/escenarios");
  await expect(page).not.toHaveURL(/escenarios/);
});
