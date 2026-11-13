// Recetas (Fase 2, etapa 2.2 A; ficha única, ADR-0042): el Jefe de Cocina carga una receta completa, sale y vuelve y la
// encuentra igual (caso 12), pide la revisión; la Chef la aprueba en la bandeja y la Cocinera la ve
// en la vista de cocina, sin ningún valor económico (caso 24). En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { fillSheetRow, login, logout, notice, openAction, openSection, saveSheet } from "./helpers";

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
  // La ficha se carga en la computadora; en el celular es de consulta (ADR-0036 y ADR-0042, ficha-receta.spec).
  test.skip(testInfo.project.name === "celular", "La ficha se edita en la computadora.");
  const n = `${testInfo.project.name === "celular" ? "C" : "D"}${Date.now() % 1_000_000}`;
  const name = `Fainá de prueba ${n}`;

  // Alta.
  await login(page, "jefecocina@ejemplo.test");
  await page.goto("/recetas");
  await axe(page);
  await page.getByRole("link", { name: "Nueva receta" }).click();
  await page.locator("#rec-alta-alcance").selectOption({ label: "Del local Demo Pastas Centro" });
  // Tipo y rubro: el código lo arma la base con los dos (ADR-0041).
  await page.getByRole("group", { name: "Tipo" }).getByText("Plato", { exact: true }).click();
  await page.locator("#rec-alta-categoria").selectOption({ label: "Pastas" });
  await expect(page.locator("#rec-alta-codigo")).toHaveValue(/^PLA-PAS-\d{4}$/);
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-motivo").fill("Receta de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();

  // Todo en la ficha única (ADR-0042): ingredientes en la grilla, pasos y peso de la porción, y un solo guardado.
  // La Jefa de Cocina no ve costos: la grilla muestra pesos, sin columnas de dinero.
  await openSection(page, "Ingredientes y costos");
  await fillSheetRow(page, 1, "Harina 000", /Harina 000/, "250");
  await fillSheetRow(page, 2, "Aceite de oliva", /Aceite de oliva/, "30", "ml");
  await expect(page.getByRole("columnheader", { name: "Costo en la receta" })).toHaveCount(0);
  await openSection(page, "Procedimiento");
  await page.getByRole("button", { name: "Agregar paso" }).click();
  await page.getByLabel("Qué se hace").first().fill("Mezclar la harina con el agua y el aceite.");
  await page.getByLabel("Minutos trabajando").first().fill("10");
  await page.getByRole("button", { name: "Agregar paso" }).click();
  await page.getByLabel("Qué se hace").nth(1).fill("Hornear hasta dorar.");
  await page.getByLabel("Minutos de espera").nth(1).fill("25");
  await openSection(page, "Rendimiento");
  await page.getByLabel("Peso de la porción (g)").fill("50");
  // 250 g de harina + 30 ml de aceite (densidad 0,92 = 27,6 g) = 277,6 g ÷ 50 g.
  await expect(page.getByText("5,55", { exact: true })).toBeVisible();
  await expect(page.getByRole("status").filter({ hasText: /cambios sin guardar/ })).toBeVisible();
  await saveSheet(page, "Receta de prueba automática");

  // Caso 12: salir y volver, la receta está igual.
  const url = page.url().split("?")[0] ?? page.url();
  await page.goto("/recetas");
  await page.goto(url);
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await expect(page.getByLabel("Tiempo total")).toHaveValue("35 min");
  await expect(page.getByLabel("Ingrediente, fila 1", { exact: true })).toHaveValue("Harina 000");
  await expect(page.getByLabel("Cantidad, fila 1", { exact: true })).toHaveValue("250");
  await expect(page.getByLabel("Cantidad, fila 2", { exact: true })).toHaveValue("30");
  await expect(page.getByLabel("Qué se hace").first()).toHaveValue(
    "Mezclar la harina con el agua y el aceite.",
  );
  await expect(page.getByLabel("Peso de la porción (g)")).toHaveValue("50");
  await axe(page);
  await noHorizontalScroll(page);
  await noRepeatedIds(page);

  // Enviar a revisión desde la barra.
  await saveSheet(page, "Lista para revisar", true);
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
  // Las preparaciones están en su pestaña (ADR-0041): tampoco ahí ve borradores.
  await page.goto("/recetas?tipo=preparaciones");
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
  test.skip(testInfo.project.name === "celular", "La ficha se edita en la computadora.");
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
  await openSection(page, "Versiones y aprobaciones");
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
  await expect(page.getByText("Versión en preparación", { exact: false })).toBeVisible({
    timeout: 15_000,
  });
  // La foto se agrega desde el carrusel del encabezado.
  await page.getByRole("button", { name: "Agregar foto" }).click();
  const dialog = page.getByRole("dialog", { name: "Agregar foto" });
  await dialog
    .getByLabel("Foto", { exact: true })
    .setInputFiles({ name: "plato.png", mimeType: "image/png", buffer: PNG });
  await dialog.getByLabel("Qué muestra").selectOption("plating");
  await dialog.getByLabel("Descripción (opcional)").fill(description);
  await dialog.getByLabel("Motivo de la foto").fill("Foto de prueba automática");
  await dialog.getByRole("button", { name: "Subir foto" }).click();
  // Achicar y subir la foto puede tardar con la máquina cargada.
  await expect(notice(page).filter({ hasText: "Foto agregada al borrador" })).toBeVisible({
    timeout: 20_000,
  });
  await page.keyboard.press("Escape");
  // El carrusel muestra una foto por vez: se pasa hasta la nueva.
  // Con una sola foto no hay flechas: se espera a que aparezca la foto o la flecha, lo que llegue primero.
  const photo = page.getByRole("img", { name: alt });
  const next = page.getByRole("button", { name: "Foto siguiente" });
  for (let i = 0; i < 10; i++) {
    await expect(photo.or(next).first()).toBeVisible({ timeout: 15_000 });
    if (await photo.isVisible()) break;
    await next.click();
  }
  await expect(photo).toBeVisible();
  await axe(page);
  await saveSheet(page, "Con la foto del emplatado", true);
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
