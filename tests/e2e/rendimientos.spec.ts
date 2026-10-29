// Rendimientos (Fase 2, etapa 2.1 B): un ensayo no cambia el estándar; el estándar se propone y
// lo aprueba un Chef de todo el grupo. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, openAction } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function openIngredient(page: Page, name: string) {
  await page.goto(`/materias-primas?q=${encodeURIComponent(name)}`);
  await page.getByRole("link", { name, exact: true }).first().click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
}

test("el Jefe de Cocina registra un ensayo y el estándar no cambia", async ({ page }) => {
  await login(page, "jefecocina@ejemplo.test");
  await openIngredient(page, "Tomate perita");
  const pelado = page
    .getByRole("list", { name: "Rendimientos por proceso" })
    .getByRole("listitem")
    .first();
  await expect(pelado).toContainText("Limpieza 80,0 %");
  await axe(page);

  await openAction(page, "Registrar un ensayo");
  await page.locator("#mp-ren-proceso").selectOption({ label: "Pelado" });
  await page.getByLabel("Peso bruto (g)").fill("1000");
  await page.getByLabel("Peso limpio (g)").fill("700");
  await page.locator("#mp-motivo-ensayo").fill("Ensayo de prueba automática");
  await page.getByRole("button", { name: "Registrar ensayo" }).click();
  await expect(notice(page)).toContainText("Ensayo registrado. El estándar no cambia");
  // El estándar sigue en 80 %: el ensayo solo suma al promedio.
  await expect(pelado).toContainText("Limpieza 80,0 %");
  await axe(page);
});

test("el Chef propone un estándar y el Chef del grupo lo aprueba", async ({ page }, testInfo) => {
  const cut = `prueba ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "chef@ejemplo.test");
  await openIngredient(page, "Zanahoria");
  await openAction(page, "Proponer un estándar nuevo");
  await page.locator("#mp-est-proceso").selectOption({ label: "Pelado" });
  await page.locator("#mp-est-corte").fill(cut);
  await page.getByLabel("Limpieza (%)").fill("85");
  await page.locator("#mp-motivo-estandar").fill("Propuesta de prueba automática");
  await page.getByRole("button", { name: "Proponer estándar" }).click();
  await expect(notice(page)).toContainText(
    "Queda pendiente: lo tiene que aprobar un Chef de todo el grupo",
  );
  const row = page
    .getByRole("list", { name: "Rendimientos por proceso" })
    .getByRole("listitem")
    .filter({ hasText: cut });
  await expect(row.getByText("Propuesta en revisión")).toBeVisible();
  await expect(row.getByText("Sin estándar aprobado")).toBeVisible();
  await logout(page);

  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/aprobaciones");
  const pending = page
    .getByRole("listitem")
    .filter({ hasText: "Propuesta de prueba automática" })
    .filter({ hasText: "Pendiente" })
    .filter({ hasText: cut })
    .first();
  await expect(pending).toContainText("Rendimiento estándar");
  await axe(page);
  await pending.getByRole("button", { name: "Aprobar" }).click();
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: cut })
      .first()
      .getByText("Aprobada", { exact: true }),
  ).toBeVisible();

  await openIngredient(page, "Zanahoria");
  const approved = page
    .getByRole("list", { name: "Rendimientos por proceso" })
    .getByRole("listitem")
    .filter({ hasText: cut });
  await expect(approved).toContainText("Limpieza 85,0 %");
  await expect(approved.getByText("Propuesta en revisión")).toHaveCount(0);
});
