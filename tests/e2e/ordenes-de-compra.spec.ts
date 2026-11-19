// Órdenes de compra (Fase 3, Prompt 3, ADR-0053). La cocinera arma una OC en el celular con los botones grandes y la
// manda: queda «En cola de envío». Una OC a un proveedor que requiere aprobación va a la bandeja, Compras la aprueba y se
// encola. Compras registra una novedad y la cocinera la ve. El listado y la ficha en la computadora. Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout } from "./helpers";

const COCINERA = "cocinero@ejemplo.test";
const COMPRAS = "compras@ejemplo.test";

async function axe(page: Page) {
  await expect(page).toHaveTitle(/\S/);
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const extra = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(extra).toBeLessThanOrEqual(0);
}

test("en el celular, la cocinera arma una OC con botones grandes y la manda", async ({
  page,
  isMobile,
}) => {
  test.skip(!isMobile, "Solo en el celular.");
  await login(page, COCINERA);
  await page.goto("/compras/ordenes/nueva");
  await page.getByRole("button", { name: /^Lácteos Demo/ }).click();
  const plus = page.getByRole("button", { name: /^Uno más de / }).first();
  await expect(plus).toBeVisible();
  const box = await plus.boundingBox();
  expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
  await plus.click();
  await plus.click();
  await expect(page.getByText("1 artículo")).toBeVisible();
  await axe(page);
  await page.getByRole("button", { name: "Mandar OC" }).click();
  await expect(
    page.getByText("Orden mandada: quedó en la cola de envío al proveedor."),
  ).toBeVisible();
  await expect(page.getByText("En cola de envío").first()).toBeVisible();
  await expect(page.getByText(/ORDEN DE COMPRA PCE-\d{4}/)).toBeVisible();
  await axe(page);
});

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("una OC con aprobación va a la bandeja, Compras la aprueba y registra una novedad", async ({
    page,
  }) => {
    // La cocinera pide al Frigorífico, que requiere aprobación.
    await login(page, COCINERA);
    await page.goto("/compras/ordenes/nueva");
    await page.getByRole("button", { name: /^Frigorífico Demo/ }).click();
    await page
      .getByRole("button", { name: /^Uno más de / })
      .first()
      .click();
    await page.getByRole("button", { name: "Enviar a aprobación" }).click();
    await expect(page.getByText(/Enviada a aprobación: la aprueba Compras/)).toBeVisible();
    const number =
      (await page.getByRole("heading", { level: 1 }).textContent())?.split(" · ")[0] ?? "";
    expect(number).toMatch(/^PCE-\d{4}$/);
    const orderUrl = page.url().replace(/\?.*$/, "");
    await logout(page);

    // Compras la ve en la bandeja, con sus líneas, y la aprueba.
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/aprobaciones");
    const card = page
      .locator("li", { hasText: number })
      .filter({ has: page.getByRole("button", { name: "Aprobar" }) });
    await expect(card.getByRole("list", { name: "Artículos de la orden" })).toBeVisible();
    await axe(page);
    await card.getByLabel("Comentario").fill("Está bien");
    await card.getByRole("button", { name: "Aprobar" }).click();
    // Resuelta, la tarjeta ya no ofrece «Aprobar».
    await expect(card).toHaveCount(0);
    await page.goto(orderUrl);
    await expect(page.getByText("En cola de envío").first()).toBeVisible();

    // Compras registra una novedad.
    await page.getByRole("button", { name: "Registrar novedad" }).click();
    const dialog = page.getByRole("dialog", { name: `Novedad en la orden ${number}` });
    await dialog.getByLabel("Novedad").fill("No tiene nalga: llega el jueves");
    await dialog.getByRole("button", { name: "Registrar" }).click();
    await expect(page.getByText("Novedad registrada. Le avisamos a quien la pidió.")).toBeVisible();
    await expect(page.getByText(/Falta mercadería: No tiene nalga/)).toBeVisible();
    await logout(page);

    // La cocinera ve la novedad arriba del listado de órdenes.
    await login(page, COCINERA);
    await page.goto("/compras/ordenes");
    await expect(page.getByRole("link", { name: `Novedad en la orden ${number}` })).toBeVisible();
    await axe(page);
  });

  test("el listado y la ficha entran en las pantallas de la computadora", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1715, height: 843 },
    ]) {
      await page.setViewportSize(size);
      await page.goto("/compras/ordenes?estado=todas");
      await expect(page.getByRole("table", { name: "Órdenes de compra" })).toContainText(
        "PCE-0004",
      );
      await noHorizontalScroll(page);
      await axe(page);
      await page.getByRole("link", { name: "PCE-0004" }).click();
      await expect(page.getByText("Con novedad").first()).toBeVisible();
      await expect(page.getByText(/El proveedor avisó que no tiene ricota/)).toBeVisible();
      await noHorizontalScroll(page);
      await axe(page);
    }
  });

  test("un local sin código no puede pedir", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/compras/ordenes/nueva?local=00000000-0000-4000-8000-000000000204");
    await expect(page.getByText("Falta el código del local.")).toBeVisible();
  });
});
