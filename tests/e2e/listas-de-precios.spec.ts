// Listas de precios y cola de mapeo (Fase 3, Prompt 2, ADR-0052). Compras carga una lista con un artículo nuevo, que
// va a la cola; el Chef del grupo lo mapea y el artículo queda en la lista; Compras la acepta y el indicador de la ficha
// del proveedor cambia. «Va a recetas» en Rubros. Con axe, en 1440 × 900 y 1715 × 843, y la cola en el celular con
// controles de 44 px. Cada corrida usa un nombre único, así la prueba se puede repetir.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout } from "./helpers";

const COMPRAS = "compras@ejemplo.test";
const CHEF_GRUPO = "chefgrupo@ejemplo.test";
const COCINERA = "cocinero@ejemplo.test";
const ALMACEN = "00000000-0000-4000-8000-000000000904";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const extra = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(extra).toBeLessThanOrEqual(0);
}

test.describe("listas de precios", () => {
  test("Compras carga una lista, el chef mapea el artículo nuevo y Compras la acepta", async ({
    page,
    isMobile,
  }) => {
    test.skip(isMobile, "La carga es en la computadora (ADR-0036).");
    const stamp = Date.now().toString(36).toUpperCase();
    const article = `Porotos alubia prueba ${stamp}`;

    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/listas-de-precios/nueva?proveedor=${ALMACEN}`);
    await expect(
      page.getByRole("heading", { level: 1, name: "Cargar lista de precios" }),
    ).toBeVisible();
    await page.getByLabel("Artículo (como viene), renglón 1").fill(article);
    await page.getByLabel("Precio de lista ($), renglón 1").fill("1000");
    await page.getByLabel("Bonif. 1 (%), renglón 1").fill("15");
    await page.getByLabel("Bonif. 2 (%), renglón 1").fill("10");
    // El neto se ve antes de cargar (caso 5).
    await expect(page.getByText("$ 765,00")).toBeVisible();
    await page.getByLabel("Motivo").fill("Llegó la lista del Almacén");
    await axe(page);
    await page.getByRole("button", { name: "Cargar lista" }).click();
    await expect(
      page.getByText(/Un artículo no lo reconocimos: va a la cola de mapeo/),
    ).toBeVisible();
    await page.getByRole("link", { name: "Ver la lista cargada" }).click();
    const row = page.getByRole("row", { name: new RegExp(article) });
    await expect(row.getByText("En la cola de mapeo")).toBeVisible();
    const listUrl = page.url();
    await logout(page);

    // El chef del grupo lo resuelve una sola vez, con el factor en palabras antes de confirmar.
    await login(page, CHEF_GRUPO);
    await page.goto("/materias-primas");
    await page.getByRole("link", { name: /Artículos sin mapear \(\d+\)/ }).click();
    await expect(
      page.getByRole("heading", { level: 1, name: "Artículos sin mapear" }),
    ).toBeVisible();
    // Al llegar con un clic, Next pone el título de la pestaña un instante después.
    await expect(page).toHaveTitle(/\S/);
    await axe(page);
    await page.getByRole("button", { name: `Mapear «${article}»` }).click();
    const dialog = page.getByRole("dialog", { name: `Mapear «${article}»` });
    await dialog.getByRole("searchbox", { name: "Materia prima" }).fill("harina 000");
    await dialog
      .getByRole("button", { name: /Harina 000/ })
      .first()
      .click();
    await dialog.getByLabel("Unidades por envase").fill("1");
    await dialog.getByLabel("Contenido de cada una").fill("5");
    await dialog.getByLabel("Unidad", { exact: true }).selectOption("kg");
    await expect(dialog.getByText(/= 5 kg/)).toBeVisible();
    await dialog.getByLabel("Motivo").fill("Es una bolsa de 5 kg");
    await axe(page);
    await dialog.getByRole("button", { name: "Crear el producto de compra" }).click();
    // El artículo sale de la cola: el aviso queda arriba de la página.
    await expect(page.getByText(/ya es un producto de compra/)).toBeVisible();
    await expect(page.getByRole("button", { name: `Mapear «${article}»` })).toHaveCount(0);
    await logout(page);

    // En la lista, el artículo ya no está en la cola. Compras la acepta con motivo.
    await login(page, COMPRAS, { mfa: true });
    await page.goto(listUrl);
    await expect(
      page.getByRole("row", { name: new RegExp(article) }).getByText("En la cola de mapeo"),
    ).toHaveCount(0);
    await page.getByRole("button", { name: "Aceptar" }).click();
    const accept = page.getByRole("dialog", { name: "Aceptar la lista" });
    await accept.getByLabel("Motivo").fill("Revisada");
    await accept.getByRole("button", { name: "Aceptar la lista" }).click();
    // Aceptada, el botón desaparece: el aviso queda arriba del detalle.
    await expect(page.getByText(/Lista aceptada/)).toBeVisible();
    await expect(page.getByRole("button", { name: "Aceptar" })).toHaveCount(0);

    // La ficha del proveedor muestra la lista vigente, al día.
    await page.goto(`/proveedores/${ALMACEN}`);
    const metric = page.locator('[data-slot="kpi"]', { hasText: "Lista de precios vigente" });
    await expect(metric).toContainText("Al día");
    await expect(metric.getByRole("link", { name: "Ver la lista" })).toBeVisible();
  });

  test("el listado filtra por estado y entra en las pantallas de la computadora", async ({
    page,
    isMobile,
  }) => {
    test.skip(isMobile, "Solo en la computadora.");
    await login(page, COMPRAS, { mfa: true });
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1715, height: 843 },
    ]) {
      await page.setViewportSize(size);
      await page.goto("/listas-de-precios?estado=expired");
      const estado = page.getByRole("group", { name: "Estado" });
      await expect(estado.getByRole("button", { name: "Vencidas" })).toHaveAttribute(
        "aria-pressed",
        "true",
      );
      await expect(page.getByRole("table", { name: "Listas de precios" })).toContainText(
        "Verdulería Demo",
      );
      await expect(page.getByRole("table", { name: "Listas de precios" })).toContainText("Vencida");
      await noHorizontalScroll(page);
      await axe(page);
    }
    // La ficha de la Verdulería avisa que la lista venció.
    await page.goto("/proveedores/00000000-0000-4000-8000-000000000901");
    await expect(
      page.locator('[data-slot="kpi"]', { hasText: "Lista de precios vigente" }),
    ).toContainText("Vencida");
  });

  test("la cocinera no ve listas de precios", async ({ page }) => {
    await login(page, COCINERA);
    await page.goto("/listas-de-precios");
    await expect(page).toHaveURL(/\/$/);
    await page.goto(`/proveedores/${ALMACEN}`);
    await expect(
      page.locator('[data-slot="kpi"]:visible', { hasText: "Lista de precios vigente" }),
    ).toContainText("La ven Compras");
  });
});

test("en el celular, la cola se resuelve con controles de 44 px", async ({ page, isMobile }) => {
  test.skip(!isMobile, "Solo en el celular.");
  await login(page, CHEF_GRUPO);
  await page.goto("/materias-primas/sin-mapear");
  const button = page.getByRole("button", { name: /^Mapear «/ }).first();
  await expect(button).toBeVisible();
  const box = await button.boundingBox();
  expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
  await button.click();
  const dialog = page.getByRole("dialog");
  for (const option of ["Es una materia prima", "Es el mismo que…", "Descartar"]) {
    // Son radios con su etiqueta a la vista: se mide la etiqueta, que es lo que se toca.
    const h = (await dialog.locator("label", { hasText: option }).boundingBox())?.height ?? 0;
    expect(h).toBeGreaterThanOrEqual(44);
  }
  await axe(page);
});

test("Rubros: «¿Va a recetas?» es un sí/no de un clic que se guarda con motivo", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "Solo en la computadora.");
  await login(page, COMPRAS, { mfa: true });
  await page.goto("/rubros");
  await page
    .getByRole("navigation", { name: "Rubros de compra", exact: true })
    .getByRole("link", { name: /^Limpieza/ })
    .click();
  const sheet = page.getByRole("region", { name: "Ficha de Limpieza" });
  const toggle = sheet.getByRole("button", { name: "¿Va a recetas?" });
  // Ida y vuelta: queda guardado cada vez.
  for (const [from, to] of [
    ["false", "true"],
    ["true", "false"],
  ] as const) {
    await expect(toggle).toHaveAttribute("aria-pressed", from);
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-pressed", to);
    await sheet.getByLabel("Motivo de los cambios").fill("Prueba de «va a recetas»");
    await sheet.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(sheet.getByText("Cambios guardados.")).toBeVisible({ timeout: 20_000 });
    await page.reload();
    await expect(toggle).toHaveAttribute("aria-pressed", to);
  }
  await axe(page);
});
