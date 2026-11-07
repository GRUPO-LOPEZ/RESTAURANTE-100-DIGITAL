// El tablero de Inicio (ADR-0033): qué tan completo y confiable está el recetario. En celular y computadora, con axe.
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
const QUESTION = "¿Qué tan completo y confiable está nuestro recetario?";

test("el Controller ve el tablero y llega a lo que falta", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: QUESTION })).toBeVisible();
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(6);
  // Cada tarjeta dice si falta algo, y lo que falta se toca.
  await expect(page.getByRole("link", { name: /Costo por corregir/ })).toBeVisible();
  // Los estados en cero también se ven, y lo oficial conserva su nombre.
  await expect(
    page.getByRole("heading", { name: "Recetas afectadas por cambios de precio" }),
  ).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "¿Qué tan confiable es el costo?" }),
  ).toBeVisible();
  await expect(page.getByRole("list", { name: "Mayor costo por porción" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Materias primas que más pesan" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Lo más usado" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Actividad" })).toBeVisible();
  await axe(page);
  await noOverflow(page);
  const size = page.viewportSize();
  for (const width of [360, 640, 768, 1024]) {
    await page.setViewportSize({ width, height: 900 });
    await noOverflow(page);
  }
  if (size) await page.setViewportSize(size);

  // La misma información del gráfico, en una tabla.
  await page.locator("summary", { hasText: "Ver los números" }).click();
  await expect(page.getByRole("table", { name: "Recetas en cada estado del costo" })).toBeVisible();

  await page.getByRole("link", { name: "Ver qué falta corregir" }).click();
  await expect(page).toHaveURL(/\/calidad\?local=/);
});

test("el Jefe de Cocina ve lo técnico, sin costos", async ({ page }) => {
  await login(page, "jefecocina@ejemplo.test");
  await expect(page.getByRole("heading", { name: QUESTION })).toBeVisible();
  await expect(page.getByRole("list", { name: "Lo más usado" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "¿Qué tan confiable es el costo?" })).toHaveCount(
    0,
  );
  await expect(page.getByText("Mayor costo por porción")).toHaveCount(0);
  await expect(page.getByText("Materias primas sin precio")).toHaveCount(0);
  await axe(page);
});

test("la Cocinera ve el Inicio de siempre", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await expect(page.getByRole("heading", { name: QUESTION })).toHaveCount(0);
  await expect(page.getByRole("navigation", { name: "Accesos" })).toBeVisible();
  await axe(page);
});

test("sin elegir local, se pide elegir uno", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await expect(page.getByText("Elegí un local para ver cómo está su recetario.")).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Accesos" })).toBeVisible();
  await axe(page);
  await page.getByRole("link", { name: "Comparar los locales" }).click();
  await expect(page.getByText("Cómo está cada local")).toBeVisible();
});
