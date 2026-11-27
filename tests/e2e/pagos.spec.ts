// Pagos y Tablero de compras (Fase 3, Prompt 6, ADR-0060). En la computadora: Compras paga en parte y después el saldo
// de la B de la Verdulería, la factura queda «Pagada» con sus pagos en la ficha y la cuenta corriente del proveedor lo
// muestra; confirma el efectivo que se pagó al recibir. El Tablero de compras entra sin scroll en las cuatro pantallas,
// con quien ve importes (Compras) y con el chef (sin importes). En el celular, el tablero de consulta. Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { localSettled, login, logout } from "./helpers";

test.describe.configure({ timeout: 120_000 });

const COMPRAS = "compras@ejemplo.test";
const CHEF = "chefgrupo@ejemplo.test";
// Demo Parrilla Centro: las facturas y los pagos del seed. La Verdulería Demo.
const PARRILLA = "00000000-0000-4000-8000-000000000203";
const VERDULERIA = "00000000-0000-4000-8000-000000000901";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noVerticalScroll(page: Page) {
  const { scroll, client } = await page.evaluate(() => {
    const d = document.scrollingElement ?? document.documentElement;
    return { scroll: d.scrollHeight, client: d.clientHeight };
  });
  expect(scroll).toBeLessThanOrEqual(client);
}

async function noOverflow(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// «$ 3.969,40» → «3969,40», como lo escribe una persona.
function typed(money: string): string {
  return money.replace(/[^\d,]/g, "");
}

async function boardReady(page: Page) {
  await expect(page.locator('[data-slot="kpi"]').locator("visible=true")).toHaveCount(4);
  await expect(
    page.getByRole("region", { name: /^Alarmas/ }).locator("visible=true"),
  ).toBeVisible();
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("Compras paga en parte y después el saldo; la factura y la cuenta corriente lo muestran", async ({
    page,
  }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/pagos?local=${PARRILLA}`);
    await localSettled(page);
    await expect(page.getByRole("heading", { level: 1, name: "Pagos" })).toBeVisible();
    // En el menú, solo «Pagos» es la pantalla actual (el Tablero de compras está arriba, en /compras).
    const nav = page
      .locator("aside[data-sidebar]:visible")
      .getByRole("navigation", { name: "Menú principal" });
    await expect(nav.locator("[aria-current=page]")).toHaveCount(1);
    await expect(nav.getByRole("link", { name: "Pagos" })).toHaveAttribute("aria-current", "page");
    await axe(page);

    // Cada pago es una orden de pago (ADR-0070): en efectivo, de la caja de la razón social del local (la Verdulería
    // solo cobra en efectivo). Al registrar, se abre la orden.
    const pay = async (amount: (balance: string) => string, reason: string) => {
      await page.goto(`/compras/pagos?local=${PARRILLA}`);
      await localSettled(page);
      await page.getByRole("button", { name: "Registrar pago" }).locator("visible=true").click();
      const panel = page.getByRole("dialog", { name: "Registrar pago" });
      await panel.getByLabel("Proveedor").selectOption(VERDULERIA);
      const invoice = panel.getByRole("list", { name: "Facturas con saldo" }).getByRole("listitem");
      await expect(invoice.filter({ hasText: /1234$|00001234/ })).toBeVisible();
      const row = invoice.filter({ hasText: "00001234" });
      const balance = /saldo (\$\s?[\d.,]+)/.exec(await row.innerText())?.[1] ?? "";
      expect(balance).not.toBe("");
      await panel.getByLabel("Medio de pago").selectOption("cash");
      // Arranca en la primera caja; se elige la del local (puede haber otras: botones, criterio 9).
      await panel.getByText("Caja Parrilla Centro", { exact: true }).click();
      await expect(panel.getByRole("radio", { name: "Caja Parrilla Centro" })).toBeChecked();
      await panel.getByLabel("Importe", { exact: true }).fill(amount(balance));
      // Se reparte solo: va todo a la B (es la única con saldo de la Verdulería).
      await expect(row.getByRole("textbox")).toHaveValue(/\d/);
      await panel.getByLabel("Motivo").fill(reason);
      await panel.getByRole("button", { name: "Registrar pago" }).click();
      await expect(
        page.getByRole("heading", { level: 1, name: /^Orden de pago OP-\d{4,}$/ }),
      ).toBeVisible();
      await expect(page.getByText(/^Pago registrado\./)).toBeVisible();
      return balance;
    };

    // Un pago parcial: la factura sigue con saldo.
    const before = await pay(() => "1.000", "Pago parcial de prueba");
    // El saldo: lo que quedaba después del pago parcial.
    await pay((b) => typed(b), "Pago del saldo de prueba");
    expect(before).not.toBe("");

    // En «Pagadas» está la B; su ficha dice «Pagada» y lista sus pagos (el del seed y los dos de recién).
    await page.goto(`/compras/pagos?local=${PARRILLA}&estado=pagadas`);
    await localSettled(page);
    await page
      .getByRole("link", { name: /00001234$/ })
      .locator("visible=true")
      .first()
      .click();
    const together = page.getByRole("region", { name: "Todo junto" });
    await expect(together.getByRole("heading", { name: "Saldo y pagos" })).toBeVisible();
    await expect(together.getByText("Pagada", { exact: true })).toBeVisible();
    await expect(
      together.getByRole("list", { name: "Pagos de la factura" }).getByRole("listitem"),
    ).toHaveCount(3);

    // La cuenta corriente del proveedor: los pagos en sus movimientos.
    await page.goto(`/proveedores/${VERDULERIA}?local=${PARRILLA}`);
    await localSettled(page);
    await page.getByRole("button", { name: "Ver la cuenta corriente" }).click();
    const account = page.getByRole("dialog", { name: /^Cuenta corriente de/ });
    await expect(
      account.getByRole("table", { name: "Movimientos de la cuenta corriente" }),
    ).toBeVisible();
    await expect(account.getByRole("cell", { name: /^Pago/ })).toHaveCount(3);
    await axe(page);
  });

  test("Compras confirma el efectivo que se pagó al recibir", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/pagos?local=${PARRILLA}&estado=para-confirmar`);
    await localSettled(page);
    const table = page
      .getByRole("table", { name: "Efectivo para confirmar" })
      .locator("visible=true");
    await expect(table.getByText("Lácteos Demo")).toBeVisible();
    await table.getByRole("button", { name: "Confirmar el efectivo de Lácteos Demo" }).click();
    const dialog = page.getByRole("dialog", { name: "Confirmar el efectivo" });
    await dialog.getByLabel("Motivo").fill("Contado en la caja");
    await dialog.getByRole("button", { name: "Confirmar" }).click();
    await expect(page.getByText(/^Efectivo confirmado/).locator("visible=true")).toBeVisible();
    await expect(
      page.getByText("No hay efectivo para confirmar.").locator("visible=true"),
    ).toBeVisible();
  });

  test("el Tablero de compras entra en una pantalla, con importes y sin ellos", async ({
    page,
  }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras?local=${PARRILLA}`);
    await localSettled(page);
    await expect(page.getByRole("heading", { level: 1 })).toContainText("Demo Parrilla Centro");
    await boardReady(page);
    await expect(page.getByRole("region", { name: /^Gasto por rubro de/ })).toBeVisible();
    await expect(page.getByText("Sin acceso a importes.")).toHaveCount(0);
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      { width: 1715, height: 843 },
      { width: 1920, height: 1080 },
    ]) {
      await page.setViewportSize(size);
      await page.reload();
      await boardReady(page);
      await noVerticalScroll(page);
      await noOverflow(page);
      if (size.height === 843) await axe(page);
    }

    // El chef ve el tablero sin importes ni las alarmas de plata, y también entra sin scroll.
    await logout(page);
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, CHEF);
    await page.goto(`/compras?local=${PARRILLA}`);
    await localSettled(page);
    await boardReady(page);
    await expect(page.getByText("Sin acceso a importes.")).toHaveCount(2);
    await expect(page.getByText(/^\$/)).toHaveCount(0);
    await noVerticalScroll(page);
    await axe(page);
  });
});

test.describe("en el celular", () => {
  test.skip(({ isMobile }) => !isMobile, "Solo en el celular.");

  test("el tablero de consulta: los indicadores y las alarmas, sin gráficos", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras?local=${PARRILLA}`);
    await localSettled(page);
    await boardReady(page);
    await expect(page.getByRole("region", { name: /^Gasto por rubro de/ })).toBeHidden();
    await noOverflow(page);
    await axe(page);
  });
});
