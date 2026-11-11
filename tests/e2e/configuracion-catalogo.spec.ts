// Configuración del catálogo (ADR-0022): Compras crea una subcategoría dentro de un rubro (los rubros se
// crean en Rubros, ADR-0038) y ya la puede elegir al cargar una materia prima; el Chef del grupo ve solo los procesos; la Cocinera no entra. En celular y
// computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice, openAction } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

test("Compras crea una subcategoría, la usa en el alta y la da de baja vacía", async ({
  page,
}, testInfo) => {
  const name = `Prueba ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas");
  await page.getByRole("link", { name: "Configuración" }).click();
  await expect(page.getByRole("heading", { name: "Configuración del catálogo" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Categorías", exact: true })).toContainText("Carnes");
  // Compras no administra procesos (eso es del Chef del grupo).
  await expect(page.getByRole("heading", { name: "Procesos de rendimiento" })).toHaveCount(0);
  await axe(page);

  await openAction(page, "Nueva subcategoría");
  await page.locator("#cfg-mp-cat-nombre").fill(name);
  await page.locator("#cfg-mp-cat-madre").selectOption({ label: "Carnes" });
  await page.locator("#cfg-mp-cat-motivo").fill("Subcategoría de prueba automática");
  await page.getByRole("button", { name: "Crear subcategoría" }).click();
  await expect(notice(page)).toContainText("Subcategoría creada");
  await expect(page.getByRole("list", { name: "Subcategorías de Carnes" })).toContainText(name);

  await page.goto("/materias-primas/nueva");
  await expect(
    page.locator("#mp-alta-categoria").getByRole("option", { name: `Carnes › ${name}` }),
  ).toHaveCount(1);

  // Vacía: se puede dar de baja, y deja de aparecer.
  await page.goto("/materias-primas/configuracion");
  await openAction(page, `Dar de baja «${name}»`);
  // La subcategoría va dentro del ítem del rubro: el ítem más interno es el último.
  const item = page
    .getByRole("listitem")
    .filter({ hasText: `Dar de baja «${name}»` })
    .last();
  await item.getByLabel("Motivo de la baja").fill("Ya no se usa");
  await item.getByRole("button", { name: "Dar de baja" }).click();
  // La categoría desaparece con su formulario: el aviso queda arriba de la pantalla, con el foco,
  // y la dirección queda limpia para que no vuelva a aparecer.
  const archived = notice(page).filter({ hasText: "Categoría dada de baja" });
  await expect(archived).toBeFocused();
  await expect(page).toHaveURL(/\/materias-primas\/configuracion$/);
  await expect(page.getByRole("list", { name: "Categorías", exact: true })).not.toContainText(name);
  await axe(page);
});

test("un rubro no se da de baja desde la configuración: lleva a Rubros", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas/configuracion");
  const item = page.getByRole("listitem").filter({ hasText: "Cambiar el nombre de «Carnes»" });
  await expect(item.getByText("Es un rubro: se da de baja en Rubros.")).toBeVisible();
  await expect(item.getByRole("link", { name: "Rubros" })).toHaveAttribute("href", "/rubros");
  await expect(item.locator("summary", { hasText: "Dar de baja" })).toHaveCount(0);
  // Tampoco se crea un rubro desde acá: la subcategoría pide su rubro.
  await expect(page.locator("#cfg-mp-cat-madre option", { hasText: "Ninguna" })).toHaveCount(0);
});

test("el Chef del grupo ve los procesos, no las categorías de materias primas", async ({
  page,
}) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/materias-primas/configuracion");
  await expect(page.getByRole("list", { name: "Procesos de rendimiento" })).toContainText("Pelado");
  await expect(page.getByRole("heading", { name: "Categorías", exact: true })).toHaveCount(0);
  await axe(page);
});

test("la Cocinera no ve la configuración ni entra", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/materias-primas");
  await expect(page.getByRole("link", { name: "Configuración" })).toHaveCount(0);
  await page.goto("/materias-primas/configuracion");
  await expect(page).toHaveURL(/\/$/);
});
