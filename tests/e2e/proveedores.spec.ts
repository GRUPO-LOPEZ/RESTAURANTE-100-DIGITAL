// Proveedores (Fase 3, Prompt 1, ADR-0050): el listado (tipo C) y la ficha completa (tipo B, sin scroll en la
// computadora). Compras edita; la cocinera solo lee y no ve el pago (lo decide la base: pgTAP 320). El celular es de
// consulta. Con axe. La edición se hace sobre un proveedor nuevo (nombre único), así la prueba se puede repetir.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { inventedCuit, login, logout } from "./helpers";

const COMPRAS = "compras@ejemplo.test";
const COCINERA = "cocinero@ejemplo.test";
const FRIGORIFICO = "/proveedores/00000000-0000-4000-8000-000000000902";

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

async function pageHeight(page: Page): Promise<number> {
  return page.evaluate(() => (document.scrollingElement ?? document.documentElement).scrollHeight);
}

const table = (page: Page) =>
  page.getByRole("table", { name: "Proveedores" }).locator("visible=true");
const card = (page: Page, title: string) =>
  page.locator("section:visible", {
    has: page.getByRole("heading", { level: 2, name: title, exact: true }),
  });

test.describe("listado de proveedores", () => {
  test("Compras filtra por canal, pasa a Inactivos y ve la condición de pago", async ({
    page,
    isMobile,
  }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/proveedores");
    await expect(page.getByRole("heading", { level: 1, name: "Proveedores" })).toBeVisible();
    await expect(page.getByText("Frigorífico Demo").locator("visible=true").first()).toBeVisible();
    if (!isMobile) {
      await expect(table(page).getByRole("columnheader", { name: "Pago" })).toBeVisible();
      await expect(table(page).getByText("Cuenta corriente a 30 días")).toBeVisible();
    }
    await axe(page);

    // El filtro se aplica solo y queda como etiqueta que se puede quitar.
    // Pocas opciones: botones con aria-pressed (ADR-0039).
    const canal = page.getByRole("group", { name: "Pedidos por" });
    await canal.getByRole("button", { name: "Sistema propio" }).click();
    await expect(canal.getByRole("button", { name: "Sistema propio" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(page).toHaveURL(/canal=supplier_portal/);
    await expect(
      page.getByText("1 proveedor", { exact: true }).locator("visible=true"),
    ).toBeVisible();
    await expect(
      page.getByText("Almacén Mayorista Demo").locator("visible=true").first(),
    ).toBeVisible();

    await page.getByRole("link", { name: "Inactivos" }).click();
    await expect(page).toHaveURL(/estado=inactivos/);
    await expect(
      page.getByText("No hay proveedores con esos filtros.").locator("visible=true"),
    ).toBeVisible();
    await page.goto("/proveedores?estado=inactivos");
    await expect(page.getByText("Molino Demo").locator("visible=true").first()).toBeVisible();
  });

  test("la cocinera ve el listado sin la condición de pago", async ({ page, isMobile }) => {
    test.skip(isMobile, "La columna de pago es de la computadora.");
    await login(page, COCINERA);
    await page.goto("/proveedores");
    await expect(page.getByText("Frigorífico Demo").locator("visible=true").first()).toBeVisible();
    await expect(table(page).getByRole("columnheader", { name: "Pago" })).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Nuevo proveedor" })).toHaveCount(0);
  });
});

test.describe("ficha de proveedor", () => {
  test("Compras da de alta un proveedor y edita su ficha con un clic por dato", async ({
    page,
    isMobile,
  }) => {
    test.skip(isMobile, "La ficha se carga en la computadora.");
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/proveedores");
    const name = `Proveedor de prueba ${Date.now()} S.A.`;
    // Un CUIT por proveedor: uno nuevo en cada corrida, y el mismo con el verificador cambiado para el error.
    const cuit = inventedCuit(`20${String(Date.now()).slice(-8)}`);
    const wrong = cuit.slice(0, -1) + ((Number(cuit.slice(-1)) + 1) % 10);
    await page.getByRole("link", { name: "Nuevo proveedor" }).click();
    const dialog = page.getByRole("dialog", { name: "Nuevo proveedor" });
    await dialog.getByLabel("Razón social").fill(name);
    await dialog.getByLabel("CUIT").fill(wrong);
    await dialog.getByLabel("Motivo").fill("Alta de prueba");
    await dialog.getByRole("button", { name: "Crear y completar la ficha" }).click();
    // Un CUIT con el verificador mal no se acepta.
    await expect(dialog.getByText("El CUIT no es válido: revisá los números.")).toBeVisible();
    await dialog.getByLabel("CUIT").fill(cuit);
    await dialog.getByRole("button", { name: "Crear y completar la ficha" }).click();
    await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();
    await expect(
      page.getByText("Proveedor creado. Completá su ficha y guardá.").locator("visible=true"),
    ).toBeVisible();

    // Días: un clic prende el día y el contador suma.
    const pedido = page.getByRole("group", { name: /^Días de pedido/ });
    const lunes = pedido.getByRole("button", { name: "lunes" });
    await expect(lunes).toHaveAttribute("aria-pressed", "false");
    await lunes.click();
    await expect(lunes).toHaveAttribute("aria-pressed", "true");
    await pedido.getByRole("button", { name: "jueves" }).click();
    await expect(page.getByText("1 cambio sin guardar")).toBeVisible();

    // Aprobación antes de enviar la OC: sí o no de un clic.
    const aprobacion = page.getByRole("button", { name: "Requiere aprobación de la OC" });
    await expect(aprobacion).toHaveAttribute("aria-pressed", "false");
    await aprobacion.click();
    await expect(aprobacion).toHaveAttribute("aria-pressed", "true");

    // Canal y su dato: un correo que no es correo no se guarda.
    await card(page, "Operativa")
      .locator("label", { hasText: /^Mail$/ })
      .click();
    await expect(page.getByRole("radio", { name: "Mail" })).toBeChecked();
    await card(page, "Operativa").getByLabel("Correo", { exact: true }).fill("no es un correo");
    await expect(page.getByText("4 cambios sin guardar")).toBeVisible();

    await page.getByLabel("Motivo de los cambios", { exact: true }).fill("Ficha inicial");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(
      page.getByText(
        "El dato no corresponde al canal: un teléfono para WhatsApp, un correo para mail o una dirección https:// para el portal.",
      ),
    ).toBeVisible();
    await card(page, "Operativa")
      .getByLabel("Correo", { exact: true })
      .fill("pedidos@ejemplo.test");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(page.getByText("Cambios guardados.").locator("visible=true")).toBeVisible();
    await expect(page.getByText("Sin cambios")).toBeVisible();

    // Lo guardado vuelve igual al recargar.
    await page.reload();
    await expect(
      page.getByRole("group", { name: /^Días de pedido/ }).getByRole("button", { name: "jueves" }),
    ).toHaveAttribute("aria-pressed", "true");
    // Guardada en Sí, ya no se desmarca con un clic: se pide que deje de requerirla y lo aprueba Dirección (ADR-0053).
    await expect(page.locator("p", { hasText: "Requiere aprobación de la OC:" })).toContainText(
      "Sí",
    );
    await expect(page.getByRole("button", { name: "Requiere aprobación de la OC" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Pedir que deje de requerir" })).toBeVisible();
    await axe(page);
  });

  test("entra sin scroll en 1440, 1600, 1715 × 843 y 1920, para quien edita y para quien solo lee", async ({
    page,
    isMobile,
  }) => {
    test.skip(isMobile, "La ficha se carga en la computadora.");
    const sizes = [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      // La pantalla real de Soy: 1920 × 1080 con 112 % de escala, menos Windows y Chrome (pedido del 2026-11-15).
      { width: 1715, height: 843 },
      { width: 1920, height: 1080 },
    ];
    await login(page, COMPRAS, { mfa: true });
    const editing: number[] = [];
    for (const size of sizes) {
      await page.setViewportSize(size);
      await page.goto(FRIGORIFICO);
      await expect(card(page, "Pago")).toBeVisible();
      await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeVisible();
      await noVerticalScroll(page);
      editing.push(await pageHeight(page));
    }
    await axe(page);
    await logout(page);

    await login(page, COCINERA);
    for (const [i, size] of sizes.entries()) {
      await page.setViewportSize(size);
      await page.goto(FRIGORIFICO);
      await expect(page.getByText("martes, jueves y sábado").locator("visible=true")).toBeVisible();
      // La cocinera no ve el pago ni la barra de guardado (la base no le da el pago).
      await expect(card(page, "Pago")).toHaveCount(0);
      await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
      await noVerticalScroll(page);
      // La lectura no es más alta que la edición.
      expect(await pageHeight(page)).toBeLessThanOrEqual(editing[i]!);
    }
    await axe(page);
  });

  test("en el celular es de consulta, con 44 px", async ({ page, isMobile }) => {
    test.skip(!isMobile, "Solo celular.");
    await login(page, COMPRAS, { mfa: true });
    await page.goto(FRIGORIFICO);
    await expect(
      page.getByText("lunes, miércoles y viernes").locator("visible=true"),
    ).toBeVisible();
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Desactivar" })).toBeHidden();
    const back = page.getByRole("link", { name: "Volver a proveedores" }).locator("visible=true");
    const box = await back.boundingBox();
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
    await axe(page);
  });
});
