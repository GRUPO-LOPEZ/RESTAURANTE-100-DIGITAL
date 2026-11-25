// Las 4 fichas técnicas (pedido de Soy, Tanda 2; ADR-0065): Completa, Servicio, Foto y Procedimiento, con su versión y
// quién la aprobó, sin importes; en la computadora sin scroll de página con quien edita y con quien solo lee; en el
// celular, una columna con letra grande; en el papel sale todo. Y el punto crítico, que guardar los pasos no borra.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { closePanels, login, logout, notice, openSection, saveSheet } from "./helpers";

test.describe.configure({ timeout: 120_000 });

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const NOQUIS = uuid(1109);
const BOLOGNESA = uuid(1102);
const SALSA_BLANCA = uuid(1103);
const SIZES = [
  { width: 1440, height: 900 },
  { width: 1600, height: 900 },
  { width: 1715, height: 843 },
  { width: 1920, height: 1080 },
];
const CARDS = ["completa", "servicio", "foto", "procedimiento"] as const;

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function overflow(page: Page) {
  return page.evaluate(() => ({
    x: document.documentElement.scrollWidth - window.innerWidth,
    y: document.documentElement.scrollHeight - window.innerHeight,
  }));
}

const VERSION = /Versión \d+ · DEMO-[A-Z]+-\d+ · publicada el \d{1,2}\/\d{1,2}\/\d{2} · aprobó \S+/;

const ready = (page: Page) => expect(page.getByText(VERSION).first()).toBeVisible();

test("la Cocinera ve las 4 fichas con su versión, sin importes", async ({ page, isMobile }) => {
  await login(page, "cocinero@ejemplo.test");
  // La dirección de antes sigue andando.
  await page.goto(`/recetas/${NOQUIS}/cocina`);
  await expect(page).toHaveURL(/\/fichas$/);
  const tabs = page.getByRole("navigation", { name: "Fichas técnicas" });

  // 1 · Completa.
  await expect(page.getByRole("heading", { level: 1, name: "Ñoquis de papa" })).toBeVisible();
  await ready(page);
  await expect(page.getByRole("list", { name: "Ingredientes" })).toContainText(/1\.000\s?g/);
  await expect(page.getByRole("list", { name: "Paso a paso" })).toContainText(
    "Punto crítico: Sacar los ñoquis apenas suben",
  );
  await expect(page.getByText("Sector · Partida")).toBeVisible();
  await expect(page.locator("main")).not.toContainText(/\$|costo|precio/i);
  // La ficha de antes era una sola: con «Volver a recetas» y «Hacer varias recetas».
  await expect(page.getByRole("link", { name: "Volver a recetas" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Hacer varias recetas" })).toBeVisible();
  await axe(page);

  // 2 · Servicio: alérgenos a la vista.
  await tabs.getByRole("link", { name: /Servicio/ }).click();
  await expect(page).toHaveURL(/ver=servicio$/);
  await expect(tabs.getByRole("link", { name: /Servicio/ })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await expect(page.getByRole("region", { name: "Alérgenos" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Ingredientes" })).toContainText("Papa");
  await ready(page);
  await axe(page);

  // 3 · Foto.
  await tabs.getByRole("link", { name: /Foto/ }).click();
  await expect(page).toHaveURL(/ver=foto$/);
  await ready(page);
  await axe(page);

  // 4 · Procedimiento: solo los pasos, con sus tiempos.
  await tabs.getByRole("link", { name: /Procedimiento/ }).click();
  await expect(page).toHaveURL(/ver=procedimiento$/);
  await expect(page.getByRole("list", { name: "Paso a paso" })).toContainText("trabajando");
  await expect(page.getByRole("list", { name: "Ingredientes" })).toHaveCount(0);
  await ready(page);
  await expect(page.locator("main")).not.toContainText(/\$|costo|precio/i);
  await axe(page);
  expect((await overflow(page)).x).toBeLessThanOrEqual(0);

  // Una ficha que no existe es la Completa.
  await page.goto(`/recetas/${NOQUIS}/fichas?ver=otra`);
  await expect(tabs.getByRole("link", { name: /Completa/ })).toHaveAttribute(
    "aria-current",
    "page",
  );
  // En el celular: una columna, letra de 20 px y controles de 44.
  if (isMobile) {
    const size = await page
      .getByRole("list", { name: "Ingredientes" })
      .evaluate((el) => getComputedStyle(el).fontSize);
    expect(size).toBe("20px");
    for (const link of await tabs.getByRole("link").all())
      expect((await link.boundingBox())?.height).toBeGreaterThanOrEqual(44);
    expect((await overflow(page)).x).toBeLessThanOrEqual(0);
  }
});

test("en la ficha de servicio va grande la medida que da entera; si no, el gramaje", async ({
  page,
}) => {
  await login(page, "cocinero@ejemplo.test");
  // Una cocinera de Pastas no ve esta receta del Café: lo dice, sin nombrarla.
  await page.goto(`/recetas/${uuid(1118)}/fichas`);
  await expect(page.getByText("no tiene una versión vigente para tu cocina")).toBeVisible();
  await logout(page);

  await login(page, "chefgrupo@ejemplo.test");
  await page.goto(`/recetas/${uuid(1118)}/fichas?ver=servicio`);
  const item = (name: string) =>
    page
      .getByRole("list", { name: "Ingredientes" })
      .getByRole("listitem")
      .filter({ hasText: name });
  const size = (name: string, text: RegExp) =>
    item(name)
      .getByText(text)
      .evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  // 100 ml en tazas de 240 no dan una medida entera: el gramaje en grande y la medida abajo.
  await expect(item("Leche entera")).toContainText(/100\s?ml\s*0,42 taza/);
  expect(await size("Leche entera", /^100\s?ml$/)).toBeGreaterThan(
    await size("Leche entera", /^0,42 taza$/),
  );
  // 10 ml en cucharaditas de 5 son 2 justas: la medida en grande y el gramaje abajo.
  await page.goto(`/recetas/${uuid(1119)}/fichas?ver=servicio`);
  await expect(item("Aceite de oliva")).toContainText(/2 cucharaditas\s*10\s?ml/);
  expect(await size("Aceite de oliva", /^2 cucharaditas$/)).toBeGreaterThan(
    await size("Aceite de oliva", /^10\s?ml$/),
  );
});

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "En el celular la página tiene scroll");

  for (const who of [
    { email: "chefgrupo@ejemplo.test", name: "quien edita" },
    { email: "cocinero@ejemplo.test", name: "quien solo lee" },
  ])
    test(`sin scroll de página en los 4 tamaños (${who.name})`, async ({ page }) => {
      test.setTimeout(240_000);
      await login(page, who.email);
      for (const size of SIZES) {
        await page.setViewportSize(size);
        for (const id of [BOLOGNESA, SALSA_BLANCA])
          for (const card of CARDS) {
            await page.goto(`/recetas/${id}/fichas?ver=${card}`);
            await ready(page);
            const over = await overflow(page);
            expect(over, `${card} ${size.width} × ${size.height}`).toEqual({
              x: expect.any(Number),
              y: 0,
            });
            expect(over.x).toBeLessThanOrEqual(0);
          }
        await page.goto(`/recetas/${BOLOGNESA}/escalar?por=recetas&objetivo=12`);
        await expect(page.getByRole("table", { name: "Cantidades para este lote" })).toBeVisible();
        expect(await overflow(page)).toEqual({ x: expect.any(Number), y: 0 });
        expect((await overflow(page)).x).toBeLessThanOrEqual(0);
      }
    });

  test("en el papel sale todo, con el nombre y la versión", async ({ page }) => {
    await login(page, "cocinero@ejemplo.test");
    // Una ventana baja: en la pantalla los pasos se desplazan adentro de su tarjeta.
    await page.setViewportSize({ width: 1440, height: 600 });
    for (const card of ["completa", "procedimiento"] as const) {
      await page.goto(`/recetas/${BOLOGNESA}/fichas?ver=${card}`);
      await ready(page);
      await page.emulateMedia({ media: "print" });
      await expect(page.getByText(/^Ficha técnica \d · /)).toBeVisible();
      await expect(page.getByText(VERSION).locator("visible=true")).toBeVisible();
      await expect(page.getByRole("button", { name: "Imprimir esta ficha" })).toBeHidden();
      await expect(page.getByLabel("Local activo")).toBeHidden();
      // Nada queda cortado: ninguna tarjeta recorta su contenido.
      const cut = await page.evaluate(() =>
        Array.from(document.querySelectorAll("main section, main ol, main ul"))
          .filter((el) => {
            const css = getComputedStyle(el);
            return css.overflowY !== "visible" && el.scrollHeight > el.clientHeight + 1;
          })
          .map((el) => el.getAttribute("aria-label")),
      );
      expect(cut).toEqual([]);
      await page.emulateMedia({ media: "screen" });
    }
  });

  test("el punto crítico se carga en el paso y guardar los pasos no lo borra", async ({ page }) => {
    test.setTimeout(240_000);
    await login(page, "chefgrupo@ejemplo.test");
    // La bolognesa tiene un punto crítico en el paso 2: se toca otro paso y tiene que seguir.
    await page.goto(`/recetas/${BOLOGNESA}`);
    await openSection(page, "Procedimiento");
    await page.getByRole("button", { name: /^(Editar|Ver) los 4 pasos$/ }).click();
    await expect(page.getByLabel("Punto crítico (paso 2)")).toHaveValue(/74 °C/);
    await page.getByLabel("Punto crítico (paso 4)").fill("Enfriar a 4 °C antes de 2 horas.");
    await closePanels(page);
    await saveSheet(page, "Punto crítico (prueba)", true);
    await expect(notice(page).filter({ hasText: "Está en revisión" })).toBeVisible({
      timeout: 20_000,
    });
    await page.reload();
    await page.getByRole("button", { name: /^(Editar|Ver) los 4 pasos$/ }).click();
    // Dentro del panel: la ficha tiene otra copia detrás, que no se ve.
    const panel = page.getByRole("dialog", { name: "Procedimiento" });
    await expect(panel.getByText("Enfriar a 4 °C antes de 2 horas.")).toBeVisible();
    await expect(panel.getByText(/74 °C en el centro/)).toBeVisible();
    await axe(page);
  });
});
