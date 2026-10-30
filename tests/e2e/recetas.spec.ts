// Recetas (Fase 2, etapa 2.2 A): el Jefe de Cocina carga una receta completa, sale y vuelve y la
// encuentra igual (caso 12), pide la revisión; la Chef la aprueba en la bandeja y la Cocinera la ve
// en la vista de cocina, sin ningún valor económico (caso 24). En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, openAction } from "./helpers";

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// Next guarda ocultas la lista y el alta: si un id se repitiera, una etiqueta podría apuntar al campo
// oculto y el visible quedaría sin nombre (axe no lo ve).
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

test("el Jefe de Cocina carga una receta y, aprobada, la cocina la ve sin costos", async ({
  page,
}, testInfo) => {
  test.setTimeout(120_000);
  const n = `${testInfo.project.name === "celular" ? "C" : "D"}${Date.now() % 1_000_000}`;
  const name = `Fainá de prueba ${n}`;

  // Alta.
  await login(page, "jefecocina@ejemplo.test");
  await page.goto("/recetas");
  await axe(page);
  await page.getByRole("link", { name: "Nueva receta" }).click();
  await page.locator("#rec-alta-alcance").selectOption({ label: "Del local Demo Pastas Centro" });
  await page.locator("#rec-alta-codigo").fill(`E2E-${n}`);
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-tipo").selectOption("dish");
  await page.locator("#rec-alta-motivo").fill("Receta de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();

  // Componentes: buscar desde 3 letras y agregar.
  await page.getByLabel("Agregar materia prima").fill("Harina 000");
  await page
    .getByRole("button", { name: /Harina 000/ })
    .first()
    .click();
  const lines = page.getByRole("list", { name: "Componentes del borrador" });
  await lines.getByLabel("Cantidad", { exact: true }).first().fill("250");
  await page.getByLabel("Agregar materia prima").fill("Aceite de oliva");
  await page
    .getByRole("button", { name: /Aceite de oliva/ })
    .first()
    .click();
  await lines.getByLabel("Cantidad", { exact: true }).nth(1).fill("30");
  await lines.getByLabel("Unidad", { exact: true }).nth(1).selectOption("ml");
  await page.getByLabel("Motivo de los cambios").first().fill("Componentes de la receta");
  await page.getByRole("button", { name: "Guardar componentes" }).click();
  await expect(notice(page).filter({ hasText: "Componentes guardados (2)" })).toBeVisible();

  // Pasos.
  await page.getByRole("button", { name: "Agregar un paso" }).click();
  await page.getByLabel("Qué se hace").first().fill("Mezclar la harina con el agua y el aceite.");
  await page.getByLabel("Minutos trabajando").first().fill("10");
  await page.getByRole("button", { name: "Agregar un paso" }).click();
  await page.getByLabel("Qué se hace").nth(1).fill("Hornear hasta dorar.");
  await page.getByLabel("Minutos de espera").nth(1).fill("25");
  await page.getByLabel("Motivo de los cambios").nth(1).fill("Pasos de la receta");
  await page.getByRole("button", { name: "Guardar pasos" }).click();
  await expect(notice(page).filter({ hasText: "Pasos guardados (2)" })).toBeVisible();

  // Rendimiento.
  await openAction(page, "Rendimiento, descripción y presentación");
  await page.locator('[id$="-rinde"]').fill("1,2");
  await page.locator('[id$="-rinde-unidad"]').selectOption("kg");
  await page.locator('[id$="-porciones"]').fill("6");
  await page.locator('[id$="-motivo-borrador"]').fill("Rendimiento");
  await page.getByRole("button", { name: "Guardar", exact: true }).click();
  await expect(notice(page).filter({ hasText: "Borrador guardado" })).toBeVisible();

  // Caso 12: salir y volver, la receta está igual.
  const url = page.url();
  await page.goto("/recetas");
  await page.goto(url);
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  const saved = page.getByRole("list", { name: "Componentes del borrador" });
  await expect(saved.getByText("1. Harina 000")).toBeVisible();
  await expect(saved.getByLabel("Cantidad", { exact: true }).first()).toHaveValue("250");
  await expect(saved.getByLabel("Cantidad", { exact: true }).nth(1)).toHaveValue("30");
  await expect(page.getByLabel("Qué se hace").first()).toHaveValue(
    "Mezclar la harina con el agua y el aceite.",
  );
  await expect(page.getByText("Tiempo total", { exact: true })).toBeVisible();
  await expect(page.getByText("35 min", { exact: true })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  await noRepeatedIds(page);

  // Pedir la revisión.
  await openAction(page, "Pedir la revisión");
  await page.locator('[id$="-motivo-revision"]').fill("Lista para revisar");
  await page.getByRole("button", { name: "Pedir la revisión" }).click();
  // El formulario desaparece con la versión en revisión: queda el aviso fijo de la versión.
  await expect(notice(page).filter({ hasText: "Está en revisión" })).toBeVisible();
  await logout(page);

  // La Chef de la marca la aprueba en la bandeja.
  await login(page, "chef@ejemplo.test");
  await page.goto("/aprobaciones");
  const request = page
    .getByRole("listitem")
    .filter({ hasText: name })
    .filter({ hasText: "Pendiente" })
    .first();
  await expect(request).toContainText("Versión de receta");
  await expect(request).toContainText("2 se agregan");
  await axe(page);
  await request.getByRole("button", { name: "Aprobar" }).click();
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: name })
      .first()
      .getByText("Aprobada", { exact: true }),
  ).toBeVisible();
  await logout(page);

  // La Cocinera la ve en la vista de cocina, sin ningún valor económico.
  await login(page, "cocinero@ejemplo.test");
  await page.goto(url);
  await expect(page).toHaveURL(/\/cocina$/);
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  const ingredients = page.getByRole("list", { name: "Ingredientes" });
  await expect(ingredients).toContainText("Harina 000");
  await expect(ingredients).toContainText("250 g");
  await expect(page.getByText("35 min").first()).toBeVisible();
  await expect(page.locator("main")).not.toContainText(/\$|costo|precio/i);
  await axe(page);
  await noHorizontalScroll(page);
});

test("la Cocinera no ve borradores ni crea recetas", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/recetas");
  await expect(page.getByRole("link", { name: "Nueva receta" })).toHaveCount(0);
  await expect(page.getByText("Risotto de hongos")).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Salsa bolognesa" }).first()).toBeVisible();
  await page.goto("/recetas/nueva");
  await expect(page).toHaveURL(/\/$/);
});

test("el Chef del grupo administra las categorías de recetas", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/materias-primas/configuracion");
  await expect(page.getByRole("list", { name: "Categorías de recetas" })).toContainText("Salsas");
  await axe(page);
});

// Una foto chica (PNG de 1 × 1): el navegador la pasa a JPEG antes de subirla.
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==",
  "base64",
);

test("las fotos van con la versión: la Cocinera las ve cuando se publica", async ({
  page,
}, testInfo) => {
  test.setTimeout(150_000);
  const description = `Emplatado ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  const alt = `Foto: Emplatado – ${description}`;

  // El Jefe de Cocina abre una versión nueva de una receta de su local y le agrega la foto.
  await login(page, "jefecocina@ejemplo.test");
  await page.goto("/recetas?q=Sorrentinos");
  await page.getByRole("link", { name: "Sorrentinos de zapallo" }).first().click();
  await expect(
    page.getByRole("heading", { name: "Sorrentinos de zapallo", exact: true }),
  ).toBeVisible();
  const url = page.url();
  // La receta puede venir con una versión abierta (otro proyecto o un reintento): se sigue con esa.
  if ((await page.locator("summary", { hasText: "Retirar de revisión" }).count()) > 0) {
    await openAction(page, "Retirar de revisión");
    await page.locator('[id$="-motivo-retiro"]').fill("Reintento de la prueba");
    await page.getByRole("button", { name: "Retirar" }).click();
  }
  if ((await page.locator("summary", { hasText: "Crear una versión nueva" }).count()) > 0) {
    await openAction(page, "Crear una versión nueva");
    await page.locator('[id$="-motivo-version"]').fill("Fotos del emplatado");
    await page.getByRole("button", { name: "Crear versión nueva" }).click();
  }
  await expect(page.getByText("Versión en preparación", { exact: false })).toBeVisible();
  await openAction(page, "Subir una foto");
  await page
    .getByLabel("Foto", { exact: true })
    .setInputFiles({ name: "plato.png", mimeType: "image/png", buffer: PNG });
  await page.getByLabel("Qué muestra").selectOption("plating");
  await page.getByLabel("Descripción (opcional)").fill(description);
  await page.getByLabel("Motivo de la foto").fill("Foto de prueba automática");
  await page.getByRole("button", { name: "Subir foto" }).click();
  await expect(notice(page).filter({ hasText: "Foto agregada al borrador" })).toBeVisible();
  await expect(page.getByRole("img", { name: alt })).toBeVisible();
  await axe(page);
  await openAction(page, "Pedir la revisión");
  await page.locator('[id$="-motivo-revision"]').fill("Con la foto del emplatado");
  await page.getByRole("button", { name: "Pedir la revisión" }).click();
  await expect(notice(page).filter({ hasText: "Está en revisión" })).toBeVisible();
  await logout(page);

  // En revisión, la cocina todavía no la ve.
  await login(page, "cocinero@ejemplo.test");
  await page.goto(url);
  await expect(page).toHaveURL(/\/cocina$/);
  await expect(page.getByRole("img", { name: alt })).toHaveCount(0);
  await logout(page);

  // La Chef de la marca la aprueba.
  await login(page, "chef@ejemplo.test");
  await page.goto("/aprobaciones");
  const request = page
    .getByRole("listitem")
    .filter({ hasText: "Sorrentinos de zapallo" })
    .filter({ hasText: "Pendiente" })
    .first();
  await request.getByRole("button", { name: "Aprobar" }).click();
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: "Sorrentinos de zapallo" })
      .first()
      .getByText("Aprobada", { exact: true }),
  ).toBeVisible();
  await logout(page);

  // Publicada, la Cocinera ve la foto cargada de verdad (el enlace firmado funciona con su sesión).
  await login(page, "cocinero@ejemplo.test");
  await page.goto(url);
  const seen = page.getByRole("img", { name: alt });
  await expect(seen).toBeVisible();
  await expect
    .poll(() => seen.evaluate((img: HTMLImageElement) => img.naturalWidth))
    .toBeGreaterThan(0);
  await expect(page.getByText(/Quitar la foto/)).toHaveCount(0);
  await axe(page);
});
