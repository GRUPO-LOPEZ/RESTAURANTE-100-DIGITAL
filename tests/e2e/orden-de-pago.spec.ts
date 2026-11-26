// Orden de pago (ADR-0070). En la computadora: Compras registra una orden con dos medios (transferencia a la cuenta del
// proveedor y cheque propio) desde las cuentas de la razón social del local, se abre la orden con su número, los medios,
// lo que cancela y la versión, se imprime y aparece en «Órdenes de pago»; quien paga la anula con motivo. El panel y la
// ficha entran sin scroll. La Superadministradora carga una caja en la ficha de la razón social. En el celular, un pago
// con cheque de terceros. Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { DESK_SIZES, localSettled, login, noPageScroll } from "./helpers";

test.describe.configure({ timeout: 180_000 });

const COMPRAS = "compras@ejemplo.test";
const SUPERADMIN = "superadmin@ejemplo.test";
// Demo Parrilla Centro (factura a nombre de Demo Gastronomía, con caja, cuenta y tarjeta en el seed) y Lácteos Demo
// (tiene una factura liberada con saldo y una cuenta para transferencias).
const PARRILLA = "00000000-0000-4000-8000-000000000203";
const LACTEOS = "00000000-0000-4000-8000-000000000903";
const RAZON_SOCIAL = "00000000-0000-4000-8000-000000001501";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function openPanel(page: Page) {
  await page.goto(`/compras/pagos?local=${PARRILLA}`);
  await localSettled(page);
  await page.getByRole("button", { name: "Registrar pago" }).locator("visible=true").click();
  const panel = page.getByRole("dialog", { name: "Registrar pago" });
  const supplier = panel.getByLabel("Proveedor");
  const value = await supplier.locator("option", { hasText: "Lácteos Demo" }).getAttribute("value");
  expect(value).toBe(LACTEOS);
  await supplier.selectOption(LACTEOS);
  await expect(panel.getByRole("list", { name: "Facturas con saldo" })).toBeVisible();
  return panel;
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("Compras registra una orden con transferencia y cheque, la imprime y la anula", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, COMPRAS, { mfa: true });
    const panel = await openPanel(page);
    await expect(panel.getByText(/paga Demo Gastronomía/)).toBeVisible();

    // Medio 1: transferencia, de la cuenta de la razón social a la del proveedor (se ve completa).
    await expect(panel.getByLabel("Medio de pago")).toHaveValue("transfer");
    await expect(panel.getByRole("radio", { name: "Banco Demo CC 1234" })).toBeChecked();
    await expect(panel.getByText(/alias lacteos\.demo/)).toBeVisible();
    await panel.getByLabel("Importe", { exact: true }).fill("100");

    // Medio 2: cheque propio, con número, banco y fecha de cobro.
    await panel.getByRole("button", { name: "Otro medio" }).click();
    await expect(panel.getByLabel("Medio 2", { exact: true })).toHaveValue("own_check");
    const second = panel.getByRole("list", { name: "Medios de pago" }).getByRole("listitem").nth(1);
    await second.getByLabel("Importe").fill("50,50");
    await second.getByLabel("N.º de cheque").fill("00012345");
    await second.getByLabel("Banco", { exact: true }).fill("Banco de Prueba");
    await second.getByLabel("Fecha de cobro").fill("31/12/2026");
    await expect(panel.getByText("$ 150,50")).toBeVisible();
    // Se reparte solo en la factura que vence antes.
    await expect(
      panel.getByRole("list", { name: "Facturas con saldo" }).getByRole("textbox").first(),
    ).toHaveValue(/150,5/);
    await expect(panel.getByText("sin cálculo por ahora")).toBeVisible();
    await panel.getByLabel("Motivo").fill("Pago de prueba con dos medios");
    // El panel no se desplaza: entra entero en 1440 × 900 (criterio 4 de Soy).
    const scrolls = await panel.evaluate((el) => el.scrollHeight - el.clientHeight);
    expect(scrolls, "el panel de pago se desplaza").toBeLessThanOrEqual(1);
    await axe(page);
    await panel.getByRole("button", { name: "Registrar pago" }).click();

    // La orden: número, quién paga, los medios con de dónde salen, la factura y la versión.
    const title = page.getByRole("heading", { level: 1, name: /^Orden de pago OP-\d{4,}$/ });
    await expect(title).toBeVisible();
    const number = (await title.innerText()).replace("Orden de pago ", "");
    await expect(page.getByText(/^Pago registrado\./)).toBeVisible();
    const means = page.getByRole("list", { name: "Medios de pago" });
    await expect(means.getByRole("listitem")).toHaveCount(2);
    await expect(
      means.getByText("Sale de: Banco Demo CC 1234 (cuenta bancaria)").first(),
    ).toBeVisible();
    await expect(means.getByText(/A la cuenta: .*alias lacteos\.demo/)).toBeVisible();
    await expect(
      means.getByText(/N\.º 00012345 · Banco de Prueba · se cobra el 31\/12\/2026/),
    ).toBeVisible();
    await expect(page.getByText(/^Versión 1 · registrada por /)).toBeVisible();
    await expect(page.getByRole("table", { name: "Facturas que cancela" })).toBeVisible();
    for (const size of DESK_SIZES) {
      await page.setViewportSize(size);
      await noPageScroll(page, `la orden de pago (${size.width} × ${size.height})`);
    }
    await page.setViewportSize({ width: 1440, height: 900 });
    await axe(page);

    // Impresa: sin menú ni botones.
    await page.emulateMedia({ media: "print" });
    await expect(page.getByRole("button", { name: "Imprimir" })).toBeHidden();
    for (const aside of await page.locator("aside[data-sidebar]").all())
      await expect(aside).toBeHidden();
    await expect(means).toBeVisible();
    await page.emulateMedia({ media: "screen" });

    // En «Órdenes de pago», con su número.
    await page.goto(`/compras/pagos?local=${PARRILLA}&estado=ordenes`);
    await localSettled(page);
    const table = page.getByRole("table", { name: "Órdenes de pago" }).locator("visible=true");
    await expect(table.getByRole("link", { name: number })).toBeVisible();
    await table.getByRole("link", { name: number }).click();

    // Anular: con motivo, no se borra.
    await page.getByRole("button", { name: `Anular la orden de pago ${number}` }).click();
    const dialog = page.getByRole("dialog", { name: "Anular la orden de pago" });
    await dialog.getByLabel("Motivo").fill("Prueba de anulación");
    await dialog.getByRole("button", { name: "Anular la orden" }).click();
    await expect(page.getByText(/^Orden de pago anulada\./)).toBeVisible();
    await expect(page.getByText("Anulada", { exact: true }).first()).toBeVisible();
    await expect(
      page.getByRole("button", { name: `Anular la orden de pago ${number}` }),
    ).toHaveCount(0);
  });

  test("la Superadministradora carga una caja en la razón social", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, SUPERADMIN, { mfa: true });
    await page.goto(`/configuracion/razones-sociales/${RAZON_SOCIAL}`);
    const tile = page.getByRole("region", { name: "Cajas y cuentas" });
    await expect(tile.getByText("Caja Parrilla Centro")).toBeVisible();
    await noPageScroll(page, "la ficha de la razón social con sus cajas y cuentas");
    await tile.getByRole("button", { name: /^(Editar|Ver las \d+)/ }).click();
    const panel = page.getByRole("dialog", { name: "Cajas y cuentas" });
    await panel.getByRole("button", { name: "Agregar caja o cuenta" }).click();
    const name = `Caja de prueba ${Date.now() % 100000}`;
    await panel.getByLabel("Nombre").fill(name);
    await panel.getByRole("button", { name: "Listo" }).click();
    await expect(panel.getByText("1 cambio sin guardar")).toBeVisible();
    await panel.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(panel.getByText("Escribí el motivo de los cambios.")).toBeVisible();
    await panel.getByLabel("Motivo").fill("Caja nueva de prueba");
    await axe(page);
    await panel.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(panel.getByText("Cajas y cuentas guardadas.")).toBeVisible();
    await expect(panel.getByText(name)).toBeVisible();
    await expect(panel.getByText("Sin cambios")).toBeVisible();
    // La baja: no se borra, deja de ofrecerse para pagar.
    await panel.getByRole("button", { name: `Dar de baja ${name}` }).click();
    await expect(panel.getByText("De baja", { exact: true })).toBeVisible();
    await panel.getByLabel("Motivo").fill("Era de prueba");
    await panel.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(panel.getByText("Cajas y cuentas guardadas.")).toBeVisible();
    await expect(panel.getByText(name)).toHaveCount(0);
  });
});

test.describe("en el celular", () => {
  test.skip(({ isMobile }) => !isMobile, "Solo en el celular.");

  test("un pago con cheque de terceros, con controles de 44 px", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    const panel = await openPanel(page);
    await panel.getByLabel("Medio de pago").selectOption("third_party_check");
    await expect(
      panel.getByText("Cheque de terceros: no sale de una cuenta propia."),
    ).toBeVisible();
    const amount = panel.getByLabel("Importe", { exact: true });
    expect((await amount.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    await amount.fill("10");
    await panel.getByLabel("N.º de cheque").fill("777");
    await panel.getByLabel("Banco").fill("Banco de Prueba");
    await panel.getByLabel("Fecha de cobro").fill("31/12/2026");
    await panel.getByLabel("Quién lo libró").fill("Cliente de prueba");
    await panel.getByLabel("Motivo").fill("Cheque de terceros de prueba");
    await axe(page);
    await panel.getByRole("button", { name: "Registrar pago" }).click();
    await expect(page.getByRole("heading", { level: 1, name: /^Orden de pago OP-/ })).toBeVisible();
    await expect(page.getByText("Cheque de terceros")).toBeVisible();
    await expect(page.getByText(/libró Cliente de prueba/)).toBeVisible();
    await axe(page);
  });
});
