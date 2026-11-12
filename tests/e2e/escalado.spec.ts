// Escalado (ADR-0032; caso 14): cuánto hace falta para un lote, sin tocar la receta. La cocina escala sin ver
// importes; quien ve costos, con el costo proyectado. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice, openAction, openSection } from "./helpers";

test.describe.configure({ timeout: 90_000 });

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const NOQUIS = uuid(1109); // 4 porciones, 1,2 kg.
const PASTAS_CENTRO = uuid(201);

test("la Cocinera escala desde la vista de cocina, sin importes", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto(`/recetas/${NOQUIS}/cocina`);
  await expect(page.getByRole("link", { name: "Escalar" })).toHaveAttribute(
    "href",
    `/recetas/${NOQUIS}/escalar`,
  );
  await page.goto(`/recetas/${NOQUIS}/escalar`);
  await page.getByLabel("¿Cuánto querés hacer?").fill("10");
  await page.getByRole("button", { name: "Escalar" }).click();
  await expect(page.locator('[data-slot="kpi"]').first()).toContainText("2,5");
  const lines = page.getByRole("list", { name: "Cantidades para este lote" });
  await expect(lines.getByRole("listitem").first()).toContainText("2.500");
  await expect(page.getByText("Costo proyectado")).toHaveCount(0);
  await expect(page.getByText(/\$\s?\d/)).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Imprimir" })).toBeVisible();
  await axe(page);
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});

test("un objetivo inválido se explica", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto(`/recetas/${NOQUIS}/escalar?por=porciones&objetivo=0`);
  await expect(page.getByText(/mayor que cero/)).toBeVisible();
  await page.goto(`/recetas/${NOQUIS}/escalar?por=porciones&objetivo=diez`);
  await expect(page.getByText(/Escribí un número/)).toBeVisible();
  // "1.500" son mil quinientos, como se ve en la pantalla.
  await page.goto(`/recetas/${NOQUIS}/escalar?por=porciones&objetivo=1.500`);
  await expect(page.getByText(/1\.500 porciones/).first()).toBeAttached();
});

test("el Chef ve el costo proyectado y carga la capacidad en un borrador", async ({
  page,
}, info) => {
  test.setTimeout(180_000);
  await login(page, "chef@ejemplo.test");
  await page.getByLabel("Local activo").selectOption(PASTAS_CENTRO);
  await page.getByRole("button", { name: "Cambiar" }).click();
  await page.goto(`/recetas/${NOQUIS}/escalar?por=porciones&objetivo=8`);
  // El costo sin IVA de los Ñoquis son $ 1.461,43 por lote: el doble.
  await expect(page.getByText(/Costo proyectado en Demo Pastas Centro/)).toBeVisible({
    timeout: 20_000,
  });
  await expect(page.locator('[data-slot="kpi"]').nth(2)).toContainText("2.922,87");
  await axe(page);
  // En la hoja impresa no salen el costo, el menú ni el formulario.
  await page.emulateMedia({ media: "print" });
  await expect(page.getByText(/Costo proyectado/)).toBeHidden();
  await expect(page.getByLabel("¿Cuánto querés hacer?")).toBeHidden();
  await expect(page.getByLabel("Local activo")).toBeHidden();
  await expect(page.getByRole("list", { name: "Cantidades para este lote" })).toBeVisible();
  await page.emulateMedia({ media: "screen" });

  await page.getByLabel("Local activo").selectOption({ label: "Todos mis locales" });
  await page.getByRole("button", { name: "Cambiar" }).click();

  // Una receta nueva por proyecto: el borrador con la capacidad no toca las otras pruebas.
  await page.goto("/recetas/nueva");
  await page.locator("#rec-alta-alcance").selectOption({ label: "Del local Demo Pastas Centro" });
  // Tipo y rubro: el código lo arma la base con los dos (ADR-0041).
  await page.getByRole("group", { name: "Tipo" }).getByText("Plato", { exact: true }).click();
  await page.locator("#rec-alta-categoria").selectOption({ label: "Pastas" });
  await expect(page.locator("#rec-alta-codigo")).toHaveValue(/^PLA-PAS-\d{4}$/);
  await page.locator("#rec-alta-nombre").fill(`Prueba de escalado ${info.project.name}`);
  await page.locator("#rec-alta-motivo").fill("Receta de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page).toHaveURL(/recetas.[0-9a-f-]{36}/);
  await openSection(page, "Rendimientos");
  await openAction(page, "Rendimiento, descripción y presentación");
  await page.locator('[id$="-rinde"]').fill("2");
  await page.locator('[id$="-rinde-unidad"]').selectOption("kg");
  await page.locator('[id$="-motivo-borrador"]').fill("Rendimiento");
  await page.getByRole("button", { name: "Guardar", exact: true }).click();
  await expect(notice(page).filter({ hasText: "Borrador guardado" })).toBeVisible();
  await page.reload();
  await openSection(page, "Procedimiento");
  await page.getByRole("button", { name: "Agregar un paso" }).click();
  await page.getByLabel("Qué se hace").fill("Hornear");
  await page.getByLabel("Equipo", { exact: true }).fill("Horno");
  await page.getByLabel(/Capacidad del equipo/).fill("5");
  await page.getByLabel("Motivo de los cambios").first().fill("Prueba automática");
  await page.getByRole("button", { name: "Guardar pasos" }).click();
  await expect(notice(page).filter({ hasText: "Pasos guardados (1)" })).toBeVisible();
  await page.reload();
  await expect(page.getByLabel("Equipo", { exact: true })).toHaveValue("Horno");
  await expect(page.getByLabel(/Capacidad del equipo/)).toHaveValue("5");
});
