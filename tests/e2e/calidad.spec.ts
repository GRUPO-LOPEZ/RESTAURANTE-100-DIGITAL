// Calidad de datos (ADR-0033): cada número abre la lista de lo que hay que corregir. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout } from "./helpers";

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

test("el Controller abre un indicador y llega a la ficha", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/calidad?local=${PASTAS_CENTRO}`);
  await expect(
    page.getByRole("heading", { name: "¿Qué tan completo y confiable está el recetario?" }),
  ).toBeVisible();
  await expect(page.getByRole("list", { name: "¿Listas para cocinar?" })).toBeVisible();
  await expect(page.getByRole("list", { name: "¿El costo es confiable?" })).toBeVisible();
  await expect(page.getByText("Cómo está cada local")).toBeVisible();
  // Panel del rediseño (ADR-0036): 4 tarjetas arriba, sin selector de local propio.
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(4);
  await expect(page.getByRole("main").getByRole("combobox")).toHaveCount(0);
  await axe(page);
  await noOverflow(page);
  const size = page.viewportSize();
  for (const width of [640, 768, 1024]) {
    await page.setViewportSize({ width, height: 900 });
    await noOverflow(page);
  }
  if (size) await page.setViewportSize(size);

  await page.getByRole("link", { name: /^Recetas con foto/ }).click();
  await expect(page.getByRole("heading", { name: "Recetas sin foto" })).toBeVisible();
  await expect(page.getByText(/^Demo Pastas Centro: \d+ para revisar/)).toBeVisible();
  // Una tabla en la computadora y tarjetas en el celular (ADR-0036).
  const list = page
    .getByRole("table", { name: "Recetas sin foto" })
    .or(page.getByRole("list", { name: "Recetas sin foto" }));
  await expect(list).toBeVisible();
  await axe(page);
  await noOverflow(page);

  await list
    .getByRole("link", { name: /^Ir a / })
    .first()
    .click();
  // «Ir» abre la ficha en la pestaña donde se corrige: la de fotos.
  await expect(page).toHaveURL(/\/recetas\/[0-9a-f-]{36}\?seccion=fotos/);
});

test("quien no ve borradores los cuenta, sin ver sus nombres", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/calidad/recipe_approved?local=${PASTAS_CENTRO}`);
  await expect(page.getByText(/que no podés ver/)).toBeVisible();
  await expect(page.getByText("Risotto de hongos")).toHaveCount(0);
  await axe(page);
});

test("sin elegir local, se compara y se elige", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/calidad");
  // Con «Todos mis locales» en la barra de arriba, la pantalla pide uno.
  await expect(page.getByText("Elegí un local para ver qué falta.")).toBeVisible();
  await page
    .getByRole("list", { name: "Tus locales" })
    .getByRole("link", { name: "Demo Pastas Centro" })
    .click();
  await expect(page).toHaveURL(/local=/);
  await expect(page.getByRole("list", { name: "¿Listas para cocinar?" })).toBeVisible();
});

test("Compras no ve columnas de lo que no puede ver", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto(`/calidad?local=${PASTAS_CENTRO}`);
  await expect(page.getByText("Materias primas con precio").first()).toBeVisible();
  await expect(page.getByText("Recetas con costo completo")).toHaveCount(0);
});

test("el Jefe de Cocina ve lo técnico, sin precios ni costos", async ({ page }) => {
  await login(page, "jefecocina@ejemplo.test");
  await page.goto("/calidad");
  await expect(page.getByRole("list", { name: "¿Listas para cocinar?" })).toBeVisible();
  await expect(page.getByText("Recetas con costo completo")).toHaveCount(0);
  await expect(page.getByText("Materias primas con precio")).toHaveCount(0);
  await expect(page.getByText("Precios al día")).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "¿El catálogo está ordenado?" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "¿El costo es confiable?" })).toHaveCount(0);
  await logout(page);
});

test("la Cocinera no tiene calidad de datos", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await expect(page.getByRole("link", { name: "Calidad", exact: true })).toHaveCount(0);
  await page.goto("/calidad");
  await expect(page).not.toHaveURL(/calidad/);
  await page.goto(`/calidad/recipe_photo?local=${PASTAS_CENTRO}`);
  await expect(page).not.toHaveURL(/calidad/);
});

test("un indicador que no existe no abre nada", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/calidad/no_existe?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: "Qué hay que corregir" })).toHaveCount(0);
  await expect(page.getByText("No encontramos esta página")).toBeVisible();
});

// Cambiar el local arriba, con una lista abierta, muestra la misma lista del otro local (el selector saca
// ?local= de la dirección). Con «Todos mis locales», pide uno (revisión de diseño del PR 3).
test("el selector de arriba cambia el local de un indicador abierto", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/calidad/recipe_photo?local=${PASTAS_CENTRO}`);
  await expect(page.getByText(/^Demo Pastas Centro: \d+ para revisar/)).toBeVisible();
  try {
    await page.getByLabel("Local activo").selectOption({ label: "Demo Pastas Norte · PASTAS" });
    await page.getByRole("button", { name: "Cambiar" }).click();
    await expect(page).not.toHaveURL(/local=/, { timeout: 20_000 });
    await expect(page.getByText(/^Demo Pastas Norte: \d+ para revisar/)).toBeVisible();
  } finally {
    await page.getByLabel("Local activo").selectOption({ label: "Todos mis locales" });
    await page.getByRole("button", { name: "Cambiar" }).click();
  }
  await expect(page.getByText("Elegí un local para ver qué falta.")).toBeVisible({
    timeout: 20_000,
  });
  await axe(page);
});
