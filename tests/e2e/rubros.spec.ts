// Rubros (ADR-0038, pedido de Soy): una pantalla con tres pestañas, resumen y grilla de tarjetas. Compras
// o Dirección administran los rubros de compra; el Chef del grupo, los de sub-recetas y de menú; la Cocinera solo
// los ve.
// En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

function grid(page: Page, label: string) {
  return page.getByRole("list", { name: label, exact: true });
}

function card(page: Page, name: string) {
  return page.getByRole("article", { name: new RegExp(`^${name} \\(`) });
}

test("Compras crea un rubro, le cambia el nombre en la tarjeta, lo da de baja y lo reactiva", async ({
  page,
}, testInfo) => {
  const name = `Prueba ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "compras@ejemplo.test");
  await page.goto("/rubros");
  await expect(page.getByRole("heading", { name: "Rubros", level: 1 })).toBeVisible();
  await expect(
    page.getByRole("navigation", { name: "Clases de rubro" }).getByRole("link", {
      name: /Rubros de compra/,
    }),
  ).toHaveAttribute("aria-current", "page");
  // La categoría vieja «Carnes» lleva el código de Soy.
  await expect(card(page, "Carnes")).toContainText("MP-CAR");
  await expect(page.getByLabel("Resumen de rubros de compra")).toContainText("Activos");
  await axe(page);

  // Alta: el código lo arma la base con el prefijo.
  await page.getByRole("button", { name: "Nuevo rubro" }).click();
  const dialog = page.getByRole("dialog", { name: "Nuevo rubro" });
  await dialog.locator("#rub-alta-nombre").fill(name);
  await dialog.locator("#rub-alta-motivo").fill("Rubro de prueba automática");
  await dialog.getByRole("button", { name: "Crear rubro" }).click();
  await expect(notice(page)).toContainText(/Rubro creado con el código MP-[A-Z0-9]{3}\./);
  await page.keyboard.press("Escape");
  await expect(card(page, name)).toContainText("Sin uso");

  // Nombre en el lugar: clic, escribir, Enter.
  const renamed = `${name} bis`;
  await card(page, name)
    .getByRole("button", { name: `${name} (cambiar el nombre)` })
    .click();
  const input = page.getByLabel(/^Nombre de MP-/);
  await expect(input).toBeFocused();
  await input.fill(renamed);
  await input.press("Enter");
  await expect(card(page, renamed)).toBeVisible();
  await expect(
    card(page, renamed).getByRole("button", { name: `${renamed} (cambiar el nombre)` }),
  ).toBeFocused();

  // Escape cancela sin guardar.
  await card(page, renamed)
    .getByRole("button", { name: `${renamed} (cambiar el nombre)` })
    .click();
  await page.getByLabel(/^Nombre de MP-/).fill("No se guarda");
  await page.keyboard.press("Escape");
  await expect(card(page, renamed)).toBeVisible();

  // Baja: sin usos, no pide destino.
  await card(page, renamed)
    .getByRole("button", { name: /^Activo \(dar de baja/ })
    .click();
  const off = page.getByRole("dialog", { name: `Dar de baja «${renamed}»` });
  await expect(off.getByLabel("Pasar a")).toHaveCount(0);
  await off.getByLabel("Motivo").fill("Ya no se usa");
  await off.getByRole("button", { name: "Dar de baja" }).click();
  await expect(notice(page)).toContainText("Rubro dado de baja.");
  await page.keyboard.press("Escape");
  await expect(card(page, renamed)).toContainText("De baja");
  // Los dados de baja van al final de la grilla.
  const items = grid(page, "Rubros de compra").getByRole("article");
  await expect(items.last()).toContainText("De baja");
  await axe(page);

  // Reactivar.
  await card(page, renamed)
    .getByRole("button", { name: /^De baja \(reactivar/ })
    .click();
  const on = page.getByRole("dialog", { name: `Reactivar «${renamed}»` });
  await on.getByLabel("Motivo").fill("Vuelve");
  await on.getByRole("button", { name: "Reactivar" }).click();
  await expect(notice(page)).toContainText("Rubro activo otra vez.");
  await page.keyboard.press("Escape");
  await expect(card(page, renamed)).toContainText("Activo");
});

test("un rubro con insumos pide el destino antes de darlo de baja", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/rubros");
  await card(page, "Carnes")
    .getByRole("button", { name: /^Activo \(dar de baja/ })
    .click();
  const dialog = page.getByRole("dialog", { name: "Dar de baja «Carnes»" });
  const target = dialog.getByLabel("Pasar a");
  await expect(target).toHaveAttribute("required", "");
  await expect(target.getByRole("option", { name: /Carnes$/ })).toHaveCount(0);
  await expect(target.getByRole("option", { name: "MP-PES · Pescados y mariscos" })).toHaveCount(1);
  // Sin destino, la base no lo da de baja y dice por qué.
  await dialog.getByLabel("Motivo").fill("Prueba");
  await dialog.getByRole("button", { name: "Dar de baja" }).click();
  await expect(notice(page)).toContainText("elegí a qué rubro pasarlas antes de darlo de baja");
  await page.keyboard.press("Escape");
  await expect(card(page, "Carnes")).toContainText("Activo");
  await axe(page);
});

test("el buscador y el orden se aplican solos", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/rubros");
  // El de la pantalla (la barra superior tiene la búsqueda global).
  await page.locator("#rub-buscar").fill("lacteos");
  await expect(page).toHaveURL(/q=lacteos/);
  await expect(grid(page, "Rubros de compra").getByRole("article")).toHaveCount(1);
  await expect(card(page, "Lácteos")).toBeVisible();
  await page.goto("/rubros?orden=az");
  await expect(grid(page, "Rubros de compra").getByRole("article").first()).toContainText(
    "Aceites",
  );
});

test("el Chef del grupo administra sub-recetas y menú, y ve los de compra sin editarlos", async ({
  page,
}) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/rubros?clase=menu");
  await expect(card(page, "Carnes")).toContainText("PL-CAR");
  await expect(card(page, "Carnes")).toContainText("4 recetas");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toBeVisible();
  await page.goto("/rubros?clase=sub-recetas");
  await expect(card(page, "Salsas")).toContainText("SR-SAL");
  await page.goto("/rubros");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toHaveCount(0);
  await expect(card(page, "Carnes").getByRole("button")).toHaveCount(0);
  await axe(page);
});

test("la Cocinera ve los rubros y no los edita", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/rubros?clase=sub-recetas");
  await expect(card(page, "Salsas")).toBeVisible();
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toHaveCount(0);
  await expect(card(page, "Salsas").getByRole("button")).toHaveCount(0);
  await axe(page);
});

test("Dirección administra los rubros de compra y ve los de menú sin editarlos", async ({
  page,
}) => {
  // Decisión de Joaco (2026-11-10): los rubros de compra los administran Compras o Dirección.
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/rubros");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toBeVisible();
  await expect(card(page, "Carnes").getByRole("button").first()).toBeVisible();
  await page.goto("/rubros?clase=menu");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toHaveCount(0);
  await expect(card(page, "Carnes").getByRole("button")).toHaveCount(0);
});

test("en la computadora: 5 columnas y sin scroll; en el celular, 2 columnas", async ({
  page,
}, info) => {
  await login(page, "compras@ejemplo.test");
  const columns = () =>
    grid(page, "Rubros de compra").evaluate(
      (el) => getComputedStyle(el).gridTemplateColumns.split(" ").length,
    );
  if (info.project.name !== "computadora") {
    await page.goto("/rubros");
    expect(await columns()).toBe(2);
    return;
  }
  for (const width of [1440, 1600, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/rubros");
    expect(await columns()).toBe(5);
    // Una pantalla, sin scroll (pedido de Soy): entran 5 filas de tarjetas de 88 px (hasta 25 rubros con «+ Nuevo
    // rubro»). Se mide con la grilla y no con la página, porque otras pruebas de la corrida agregan rubros de compra.
    const fit = await grid(page, "Rubros de compra").evaluate((el) => {
      const gap = parseFloat(getComputedStyle(el).rowGap) || 0;
      const main = el.closest("main");
      const padding = main ? parseFloat(getComputedStyle(main).paddingBottom) || 0 : 0;
      const fiveRows = el.getBoundingClientRect().top + window.scrollY + 5 * 88 + 4 * gap;
      return {
        free: window.innerHeight - padding - fiveRows,
        cards: el.children.length,
        scroll: document.documentElement.scrollHeight - window.innerHeight,
      };
    });
    expect(fit.free).toBeGreaterThanOrEqual(0);
    if (fit.cards <= 25) expect(fit.scroll).toBeLessThanOrEqual(0);
    // Tarjetas de 88 px.
    expect((await card(page, "Huevos").boundingBox())?.height).toBe(88);
  }
});

test("al dar de alta una receta, el rubro se ofrece según el tipo", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/recetas/nueva");
  const category = page.locator("#rec-alta-categoria");
  await page.locator("#rec-alta-tipo").selectOption("dish");
  await expect(category.locator("optgroup")).toHaveCount(1);
  await expect(category.locator("optgroup")).toHaveAttribute("label", "Rubros de menú (platos)");
  await expect(category.getByRole("option", { name: "Pastas", exact: true })).toHaveCount(1);
  await expect(category.getByRole("option", { name: "Salsas", exact: true })).toHaveCount(0);
  await page.locator("#rec-alta-tipo").selectOption("preparation");
  await expect(category.locator("optgroup")).toHaveAttribute(
    "label",
    "Sub-recetas (preparaciones y componentes)",
  );
  await expect(category.getByRole("option", { name: "Salsas", exact: true })).toHaveCount(1);
  await axe(page);
});
