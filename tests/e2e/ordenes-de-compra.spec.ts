// Órdenes de compra (Fase 3, Prompt 3, ADR-0053; en una pantalla, ADR-0069). La cocinera arma una OC en el celular con
// los botones grandes y la manda: queda «En cola de envío». Compras la arma en la computadora con precios, total y el
// pedido mínimo; la cocinera, sin importes. Sin pantalla de elegir el local: con «Todos mis locales» se elige en la
// misma línea. Una OC a un proveedor que requiere aprobación va a la bandeja, Compras la aprueba y se
// encola. Compras registra una novedad y la cocinera la ve. El listado y la ficha en la computadora. Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { DESK_SIZES, chooseLocal, login, logout, noPageScroll } from "./helpers";

const COCINERA = "cocinero@ejemplo.test";
const COMPRAS = "compras@ejemplo.test";
// Demo Pastas Centro y Lácteos Demo (que tiene lista vigente, pedidos en el local y un mínimo de $ 50.000).
const PCE = "00000000-0000-4000-8000-000000000201";
const LACTEOS = "00000000-0000-4000-8000-000000000903";

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
  // En el celular, el proveedor se elige arriba (desplegable, 44 px).
  const supplier = page.getByLabel("Proveedor", { exact: true });
  // La pantalla llega en streaming: se mide cuando el desplegable ya está (si no, la caja es nula y mide 0).
  await expect(supplier).toBeVisible();
  expect((await supplier.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
  await supplier.selectOption(LACTEOS);
  const plus = page.getByRole("button", { name: /^Uno más de / }).first();
  await expect(plus).toBeVisible();
  const box = await plus.boundingBox();
  expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
  await plus.click();
  await plus.click();
  await expect(page.getByText("1 artículo")).toBeVisible();
  await axe(page);
  // Sin importes: la cocinera no ve listas de precios.
  await expect(page.getByText("Total estimado")).toHaveCount(0);
  await page.getByRole("button", { name: "Enviar orden" }).click();
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
      // El local lo elige la prueba: otra pudo dejarle a Compras otro local guardado (ADR-0059).
      await page.goto(`/compras/ordenes?estado=todas&local=${PCE}`);
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

  test("Compras arma la orden en una pantalla: precios, total, mínimo y la entrega; la manda", async ({
    page,
  }) => {
    test.setTimeout(120_000);
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/ordenes/nueva?local=${PCE}`);
    await expect(page.getByText("el número sale al guardarla")).toBeVisible();
    const lacteos = page.getByRole("button", { name: /^Lácteos Demo/ });
    await lacteos.click();
    await expect(lacteos).toHaveAttribute("aria-pressed", "true");
    // Primero lo pedido en los últimos 60 días; la cantidad arranca en 0.
    await expect(
      page.getByRole("heading", { name: "Pedidos en los últimos 60 días" }),
    ).toBeVisible();
    const first = page.getByRole("group", { name: /^Cantidad de / }).first();
    await expect(first.getByRole("textbox")).toHaveValue("");
    // Con el precio de la lista vigente.
    await expect(page.getByText(/^(con|sin) IVA$/).first()).toBeVisible();
    await first.getByRole("button", { name: /^Uno más de / }).click();
    await first.getByRole("button", { name: /^Uno más de / }).click();
    const order = page.getByRole("region", { name: "La orden" });
    await expect(order.getByText("Total estimado")).toBeVisible();
    await expect(order.getByText(/^(Faltan|Supera) \$/)).toBeVisible();
    await expect(order.getByText(/^Se manda por/)).toBeVisible();
    // La entrega se cambia en el lugar.
    await order.getByRole("button", { name: "Cambiar la fecha de entrega" }).click();
    await expect(order.getByLabel("Entrega esperada")).toBeVisible();
    await axe(page);
    for (const size of DESK_SIZES) {
      await page.setViewportSize(size);
      await noPageScroll(page, `nueva OC con Compras (${size.width} × ${size.height})`);
    }
    await page.getByRole("button", { name: "Enviar orden" }).click();
    await expect(
      page.getByText("Orden mandada: quedó en la cola de envío al proveedor."),
    ).toBeVisible();
  });

  test("la cocinera arma la orden en la computadora sin importes, en una pantalla", async ({
    page,
  }) => {
    await login(page, COCINERA);
    await page.goto("/compras/ordenes/nueva");
    await page.getByRole("button", { name: /^Lácteos Demo/ }).click();
    await expect(page.getByText("Sin precios: los ve Compras")).toBeVisible();
    await page
      .getByRole("button", { name: /^Uno más de / })
      .first()
      .click();
    await expect(page.getByText("Total estimado")).toHaveCount(0);
    await expect(page.getByText(/^Pedido mínimo/)).toHaveCount(0);
    for (const size of DESK_SIZES) {
      await page.setViewportSize(size);
      await noPageScroll(page, `nueva OC con la cocinera (${size.width} × ${size.height})`);
    }
    await axe(page);
  });

  test("con «Todos mis locales» arriba, el local se elige en la misma pantalla", async ({
    page,
  }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/compras/ordenes");
    await chooseLocal(page, { label: "Todos mis locales" });
    await page.goto("/compras/ordenes/nueva");
    await expect(page.getByText("¿Para qué local es la orden?")).toBeVisible();
    await axe(page);
    await page.getByRole("link", { name: "Demo Pastas Centro" }).click();
    await expect(page.getByRole("button", { name: /^Lácteos Demo/ })).toBeVisible();
    await expect(page.getByText("el número sale al guardarla")).toBeVisible();
  });

  test("un local sin código no puede pedir", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/compras/ordenes/nueva?local=00000000-0000-4000-8000-000000000204");
    await expect(page.getByText("Falta el código del local.")).toBeVisible();
  });
});
