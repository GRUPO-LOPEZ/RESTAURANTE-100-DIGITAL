// Materias primas en una pantalla, con el panel de rubros quieto, el precio vigente para quien ve precios y la foto del
// producto (ADR-0066, pedido de Soy). Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { chooseLocal, login, logout, notice } from "./helpers";

const PASTAS_CENTRO = "00000000-0000-4000-8000-000000000201";
const ZANAHORIA = "00000000-0000-4000-8000-000000000804";
// Un PNG de 1 × 1.
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function overflow(page: Page) {
  return page.evaluate(() => {
    const d = document.scrollingElement ?? document.documentElement;
    return { x: d.scrollWidth - d.clientWidth, y: d.scrollHeight - d.clientHeight };
  });
}

const panel = (page: Page) =>
  page.getByRole("navigation", { name: "Rubros de compra", exact: true });

test("el panel de rubros filtra y no se mueve al desplazar la tabla", async ({
  page,
  isMobile,
}) => {
  test.setTimeout(120_000);
  await login(page, "chefgrupo@ejemplo.test");
  // La lista trae como mucho 50 filas por página: con 300 materias primas se ve lo mismo que acá.
  await page.goto("/materias-primas?filas=50");
  await expect(panel(page).getByRole("link", { name: /^Todas/ })).toHaveAttribute(
    "aria-current",
    "true",
  );
  if (isMobile) {
    expect((await overflow(page)).x).toBeLessThanOrEqual(0);
    const first = panel(page).getByRole("link").first();
    expect((await first.boundingBox())?.height).toBeGreaterThanOrEqual(44);
    await axe(page);
    return;
  }
  for (const [width, height] of [
    [1440, 900],
    [1600, 900],
    [1715, 843],
    [1920, 1080],
  ] as const) {
    await page.setViewportSize({ width, height });
    const table = page.getByRole("region", { name: "Materias primas (tabla)" });
    await expect(table).toBeVisible();
    expect(await overflow(page)).toEqual({ x: 0, y: 0 });
    const before = await panel(page).boundingBox();
    expect(before?.width).toBe(250);
    await table.evaluate((el) => el.scrollTo(0, el.scrollHeight));
    expect(await table.evaluate((el) => el.scrollTop)).toBeGreaterThan(0);
    expect(await panel(page).boundingBox()).toEqual(before);
  }
  await axe(page);

  await panel(page)
    .getByRole("link", { name: /^Carnes \d/ })
    .click();
  await expect(page).toHaveURL(/rubro=/);
  await expect(page.getByText("Rubro: Carnes")).toBeVisible();
  // Con un rubro elegido, la columna «Rubro» no hace falta.
  await expect(page.getByRole("columnheader", { name: "Rubro", exact: true })).toHaveCount(0);
  await panel(page)
    .getByRole("link", { name: /^Todas/ })
    .click();
  await expect(page).not.toHaveURL(/rubro=/);
});

test("el precio vigente: con el local elegido y solo para quien ve precios", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "Las columnas son de la computadora.");
  test.setTimeout(120_000);
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto("/materias-primas");
  const table = page.getByRole("table", { name: "Materias primas" });
  // El local elegido se guarda por persona: otra prueba pudo dejar uno.
  await chooseLocal(page, { label: "Todos mis locales" });
  await expect(page.getByText("para ver los precios, elegí un local arriba")).toBeVisible();
  await expect(table.getByRole("columnheader", { name: "Precio vigente" })).toHaveCount(0);
  await chooseLocal(page, PASTAS_CENTRO);
  await expect(page.getByText("precios de Demo Pastas Centro")).toBeVisible();
  await expect(table.getByRole("columnheader", { name: "Precio vigente" })).toBeVisible();
  // Cada fila dice su precio y una palabra; nunca «Al día» sin precio.
  const rows = table.getByRole("row");
  const texts = (await rows.allTextContents()).slice(1);
  expect(texts.length).toBeGreaterThan(0);
  for (const t of texts) {
    expect(t).toMatch(
      /Al día|Desactualizado|Sin precio|Falta la razón social|Sin datos|Desactivada/,
    );
    if (/Al día|Desactualizado/.test(t)) expect(t).toMatch(/\$\s?[\d.]+(,\d+)? \/ (kg|l|u)/);
  }
  for (const [width, height] of [
    [1440, 900],
    [1715, 843],
  ] as const) {
    await page.setViewportSize({ width, height });
    expect(await overflow(page)).toEqual({ x: 0, y: 0 });
    // La tabla entra de ancho, con las dos columnas de precio.
    const region = page.getByRole("region", { name: "Materias primas (tabla)" });
    expect(await region.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(0);
  }
  await axe(page);
  await logout(page);

  // La Chef no ve precios: ni las columnas ni el pedido de elegir un local.
  await login(page, "chef@ejemplo.test");
  await page.goto("/materias-primas");
  await expect(table).toBeVisible();
  await expect(table.getByRole("columnheader", { name: /Precio/ })).toHaveCount(0);
  await expect(page.getByText(/ver los precios/)).toHaveCount(0);
});

test("la foto: Compras la agrega, la cambia y la quita; la Chef la ve y no la cambia", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "Una vez alcanza: es la misma pantalla.");
  test.setTimeout(180_000);
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto(`/materias-primas/${ZANAHORIA}`);
  const data = page.getByRole("region", { name: "Datos generales" });
  await data.getByRole("button", { name: "Agregar foto" }).click();
  const dialog = page.getByRole("dialog", { name: "Foto del producto" });
  // Sin foto ni motivo, lo dice en los campos.
  await dialog.getByRole("button", { name: "Guardar foto" }).click();
  await expect(dialog.getByText("Elegí una foto.", { exact: true })).toBeVisible();
  await expect(dialog.locator('input[name="photo"]')).toBeFocused();
  // Un archivo que no es una imagen no se sube.
  await dialog
    .locator('input[name="photo"]')
    .setInputFiles({ name: "foto.png", mimeType: "image/png", buffer: Buffer.from("no es") });
  await dialog.locator('input[name="reason"]').first().fill("Foto del proveedor");
  await dialog.getByRole("button", { name: "Guardar foto" }).click();
  await expect(dialog.getByText("No pudimos leer la foto.")).toBeVisible();
  await dialog
    .locator('input[name="photo"]')
    .setInputFiles({ name: "foto.png", mimeType: "image/png", buffer: PNG });
  await dialog.getByRole("button", { name: "Guardar foto" }).click();
  await expect(notice(page)).toContainText("Foto guardada.", { timeout: 20_000 });
  await axe(page);
  await page.keyboard.press("Escape");
  const image = data.getByRole("img", { name: "Foto de Zanahoria", exact: true });
  await expect(image).toBeVisible();
  expect(await image.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBeGreaterThan(0);

  // Cambiarla.
  await data.getByRole("button", { name: "Cambiar foto" }).click();
  await dialog
    .locator('input[name="photo"]')
    .setInputFiles({ name: "otra.png", mimeType: "image/png", buffer: PNG });
  await dialog.locator('input[name="reason"]').first().fill("Otra marca");
  await dialog.getByRole("button", { name: "Guardar foto" }).click();
  await expect(notice(page)).toContainText("Foto guardada.", { timeout: 20_000 });
  await page.keyboard.press("Escape");
  // En la lista, chica.
  await page.goto("/materias-primas?q=Zanahoria");
  const thumb = page
    .getByRole("table", { name: "Materias primas" })
    .getByRole("row", { name: /Zanahoria/ })
    .locator("img");
  await expect(thumb).toBeVisible();
  expect((await thumb.boundingBox())?.height).toBe(32);
  await logout(page);

  // La Chef la ve, sin poder cambiarla.
  await login(page, "chef@ejemplo.test");
  await page.goto(`/materias-primas/${ZANAHORIA}`);
  await expect(image).toBeVisible();
  await expect(data.getByRole("button", { name: /Cambiar foto|Agregar foto/ })).toHaveCount(0);
  await logout(page);

  // Quitarla.
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto(`/materias-primas/${ZANAHORIA}`);
  await data.getByRole("button", { name: "Cambiar foto" }).click();
  await dialog.getByLabel("Motivo para quitarla").fill("Ya no es ese envase");
  await dialog.getByRole("button", { name: "Quitar foto" }).click();
  await expect(notice(page)).toContainText("Foto quitada.", { timeout: 20_000 });
  await page.keyboard.press("Escape");
  await expect(data.getByRole("button", { name: "Agregar foto" })).toBeVisible();
  await expect(image).toHaveCount(0);
});

test("con poco lugar (zoom, una tablet) la lista se puede usar", async ({ page, isMobile }) => {
  test.skip(isMobile, "Es de la computadora.");
  await login(page, "chefgrupo@ejemplo.test");
  for (const [width, height] of [
    [800, 900],
    [960, 600],
    [1024, 600],
    [1280, 600],
  ] as const) {
    await page.setViewportSize({ width, height });
    await page.goto("/materias-primas");
    const table = page.getByRole("region", { name: "Materias primas (tabla)" });
    await expect(table).toBeVisible();
    // La barra de arriba se acomoda al terminar de cargar.
    await expect.poll(async () => (await overflow(page)).x).toBeLessThanOrEqual(0);
    // Al menos unas 4 filas a la vista.
    expect((await table.boundingBox())?.height).toBeGreaterThan(180);
  }
});
