// Facturas (Fase 3, Prompt 5B, ADR-0058). En la computadora: Compras carga una factura desde una OC recibida, la ajusta
// al papel, la controla y ve un ✕ con su explicación; suma una nota con su foto; el Controller (otra persona) la da por
// conforme y el precio nuevo se ve en la ficha de la materia prima con su factura de origen. El listado con sus
// pestañas y quién lo ve. La ficha sin scroll en las cuatro pantallas, para quien edita (Compras) y para quien solo lee
// (Gerente). En el celular, de consulta. Las fotos son capturas de la propia app (JPEG inventados). Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { localSettled, login, logout, menuLink, notice } from "./helpers";

const COMPRAS = "compras@ejemplo.test";
const CONTROLLER = "controller@ejemplo.test";
const GERENTE2 = "gerente2@ejemplo.test";
const COCINERA = "cocinero@ejemplo.test";
// Demo Parrilla Centro (las OC recibidas del seed) y la materia prima Tomate perita.
const PARRILLA = "00000000-0000-4000-8000-000000000203";
const TOMATE = "00000000-0000-4000-8000-000000000801";
// Demo Pastas Norte: la observada con percepción y sin OC (la ve también su Gerente).
const NORTE = "00000000-0000-4000-8000-000000000202";

async function axe(page: Page) {
  await expect(page).toHaveTitle(/\S/);
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

// Una foto inventada: una captura JPEG de la pantalla.
async function photo(page: Page, name: string) {
  return {
    name,
    mimeType: "image/jpeg",
    buffer: await page.screenshot({ type: "jpeg", quality: 60 }),
  };
}

// Abre una factura del listado por su número (sin el punto de venta), con su local elegido arriba.
async function openInvoice(page: Page, number: string, local: string) {
  await page.goto(`/compras/facturas?local=${local}`);
  await localSettled(page);
  await page
    .getByRole("link", { name: new RegExp(`${number}$`) })
    .locator("visible=true")
    .first()
    .click();
  await expect(page.getByRole("heading", { level: 1, name: new RegExp(number) })).toBeVisible();
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("Compras carga, ajusta y controla una factura; el Controller la da por conforme y el precio llega a la materia prima", async ({
    page,
  }) => {
    test.setTimeout(240_000);
    await page.setViewportSize({ width: 1440, height: 900 });
    // Un número que no se repite entre corridas (único por proveedor, clase y punto de venta).
    const number = String(300000 + (Date.now() % 600000));
    const label = `Factura A 0001-${number.padStart(8, "0")}`;

    await login(page, COMPRAS, { mfa: true });
    await openInvoice(page, "00002002", PARRILLA);
    await page.getByRole("button", { name: "Cancelar la factura" }).click();
    const cancel = page.getByRole("dialog", { name: "Cancelar la factura" });
    await cancel.getByLabel("Motivo").fill("Se cargó con el artículo equivocado");
    await cancel.getByRole("button", { name: "Cancelar la factura" }).click();
    await expect(page.getByText("Cancelada: Se cargó con el artículo equivocado")).toBeVisible();
    await expect(notice(page).filter({ hasText: "Factura cancelada" })).toBeVisible();
    await expect(cancel).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Controlar" })).toHaveCount(0);

    await page.goto("/compras/facturas");
    await page.getByRole("link", { name: "Nueva factura" }).click();
    const dialog = page.getByRole("dialog", { name: "Nueva factura" });
    const supplier = dialog.getByLabel("Proveedor");
    const value = await supplier
      .locator("option", { hasText: "Verdulería Demo" })
      .getAttribute("value");
    await supplier.selectOption(value ?? "");
    await dialog.getByLabel(/^PAR-0005/).check();
    await dialog.getByLabel("Punto de venta").fill("1");
    await dialog.getByLabel("Número", { exact: true }).fill(number);
    await dialog.getByLabel("Número de autorización").fill("75000000000099");
    await axe(page);
    await dialog.getByRole("button", { name: "Cargar y completar la factura" }).click();

    // La ficha: las líneas salen de lo recibido, con el precio de la lista.
    await expect(page.getByRole("heading", { level: 1, name: label })).toBeVisible();
    await expect(notice(page).filter({ hasText: "Factura cargada" })).toBeVisible();
    const price = page.getByLabel("Precio sin IVA de Tomate perita, cajón de 10 kg");
    await expect(price).toHaveValue("937");
    await page
      .getByText("Subir la foto o el PDF")
      .locator("..")
      .getByLabel("Subir la foto o el PDF")
      .setInputFiles(await photo(page, "factura.jpg"));
    await expect(page.getByRole("link", { name: /Ver la foto/ })).toBeVisible();

    // Se ajusta al papel: el precio dice $ 940. Guardar pide motivo y cuenta el cambio.
    await price.fill("940");
    await expect(
      page.getByRole("status").filter({ hasText: "1 cambio sin guardar" }),
    ).toBeVisible();
    // El pie, como el papel: 2 cajones a $ 940 más el IVA.
    await page.getByLabel("Neto gravado").fill("1880");
    await page.getByLabel("IVA", { exact: true }).fill("197,40");
    await page.getByLabel("Total", { exact: true }).fill("2077,40");
    await expect(page.getByText("La cuenta cierra")).toBeVisible();
    await expect(
      page.getByRole("status").filter({ hasText: "4 cambios sin guardar" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(page.getByText("Escribí el motivo de los cambios.")).toBeVisible();
    await page.getByLabel("Motivo de los cambios").fill("Como dice el papel");
    await page.getByRole("button", { name: "Guardar cambios" }).click();
    await expect(notice(page).filter({ hasText: "Cambios guardados" })).toBeVisible();

    // Controlar: el precio no es el de la lista; queda observada y la línea dice por qué.
    await page.getByRole("button", { name: "Controlar" }).click();
    await expect(notice(page).filter({ hasText: "Quedó observada" })).toBeVisible();
    await expect(
      page.getByText("Observada", { exact: true }).locator("visible=true"),
    ).toBeVisible();
    const lines = page.getByRole("region", { name: "1 línea" });
    await expect(lines.getByText("No pasa")).toBeVisible();
    await lines.getByRole("button", { name: "Más información: el control de la línea" }).hover();
    await expect(page.getByRole("tooltip")).toContainText(
      "La lista dice $ 937,00 y la factura $ 940,00 (sin IVA).",
    );
    await axe(page);

    // Una nota de crédito por la diferencia ($ 3 × 2 cajones). Cuenta recién con su foto; como la sumó quien la cargó,
    // no la deja conforme sola.
    await page.getByRole("button", { name: "Agregar nota" }).click();
    const noteDialog = page.getByRole("dialog", { name: "Nota de crédito, débito o descuento" });
    await noteDialog.getByLabel("Número").fill("NC 0001-00000077");
    await noteDialog.getByLabel("Importe sin IVA").fill("6");
    await noteDialog.getByLabel("Motivo").fill("Diferencia de precio del tomate");
    await noteDialog.getByRole("button", { name: "Guardar la nota" }).click();
    await expect(noteDialog.getByText(/Nota guardada/)).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByText("Sin foto")).toBeVisible();
    await page.getByLabel("Subir la foto de la nota").setInputFiles(await photo(page, "nota.jpg"));
    await expect(page.getByText(/Se volvió a controlar: quedó observada/)).toBeVisible();
    await expect(page.getByText("Con foto")).toBeVisible();
    // Compras puede dar por conforme, pero no una que cargó: no tiene el botón y se le dice por qué.
    await expect(page.getByRole("button", { name: "Dar por conforme" })).toHaveCount(0);
    await expect(
      page.getByText(
        "La cargaste, la corregiste o le sumaste una nota: la da por conforme otra persona.",
      ),
    ).toBeVisible();
    await logout(page);

    // El Controller (otra persona) la da por conforme, con motivo.
    await login(page, CONTROLLER, { mfa: true });
    await openInvoice(page, number.padStart(8, "0"), PARRILLA);
    await expect(page.getByRole("button", { name: "Controlar" })).toHaveCount(0);
    await page.getByRole("button", { name: "Dar por conforme" }).click();
    const approve = page.getByRole("dialog", { name: "Dar por conforme" });
    await approve.getByLabel("Por qué la das por conforme").fill("Revisada con la nota de crédito");
    await approve.getByRole("button", { name: "Dar por conforme" }).click();
    await expect(page.getByText("Liberada", { exact: true }).locator("visible=true")).toBeVisible();
    await expect(
      notice(page).filter({ hasText: "Quedó conforme y liberada a pago" }),
    ).toBeVisible();
    await expect(approve).toHaveCount(0);
    await expect(page.getByText(/La dio por conforme Camila Costos/)).toBeVisible();
    // Conforme: de solo lectura, sin barra de guardado.
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);

    // El precio llega a la materia prima, con su factura de origen.
    await page.goto(`/materias-primas/${TOMATE}?local=${PARRILLA}`);
    await localSettled(page);
    await page.getByRole("button", { name: /^Ver (el producto|los \d+ productos)$/ }).click();
    // En la tabla de productos (el precio que vale en el local) y en los precios del panel (vigente e historial).
    const origins = page
      .getByRole("dialog")
      .getByRole("link", { name: `${label} · Verdulería Demo` });
    expect(await origins.count()).toBeGreaterThanOrEqual(2);
    await expect(origins.first()).toBeVisible();
    await page.goto((await origins.first().getAttribute("href")) ?? "");
    await expect(page.getByRole("heading", { level: 1, name: label })).toBeVisible();
  });

  test("el listado: pestañas, lo que no pasó y quién lo ve", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, CONTROLLER, { mfa: true });
    await (await menuLink(page, "Facturas")).click();
    await expect(page.getByRole("heading", { level: 1, name: "Facturas" })).toBeVisible();
    const table = page.getByRole("table", { name: "Facturas" }).locator("visible=true");
    await page.getByRole("link", { name: "Observadas" }).click();
    await expect(table.getByText("Observada").first()).toBeVisible();
    await expect(table.getByText("Liberada")).toHaveCount(0);
    await page.getByRole("link", { name: "Conformes" }).click();
    // Las del seed las dio por conforme el Controller después de quedar observadas (doble firma).
    await expect(table.getByText("Conforme a mano").first()).toBeVisible();
    // El Controller no carga facturas.
    await expect(page.getByRole("link", { name: "Nueva factura" })).toHaveCount(0);
    await axe(page);
    await logout(page);

    // La cocinera no ve facturas: ni en el menú ni por la dirección.
    await login(page, COCINERA);
    await expect(
      page
        .getByRole("navigation", { name: "Menú principal" })
        .getByRole("link", { name: "Facturas" }),
    ).toHaveCount(0);
    await page.goto("/compras/facturas");
    await expect(page).toHaveURL(/\/$/);
  });

  test("la ficha entra sin scroll en 1440, 1600, 1715 × 843 y 1920, para quien edita y para quien solo lee", async ({
    page,
  }) => {
    test.setTimeout(180_000);
    const sizes = [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      // La pantalla real de Soy (ADR-0051).
      { width: 1715, height: 843 },
      { width: 1920, height: 1080 },
    ];
    // La observada de Demo Pastas Norte, con percepción y sin OC: la ve Compras y la ve el Gerente de ese local.
    await login(page, COMPRAS, { mfa: true });
    await openInvoice(page, "00012001", NORTE);
    const url = page.url();
    const editing: number[] = [];
    for (const size of sizes) {
      await page.setViewportSize(size);
      await page.goto(url);
      await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeVisible();
      await expect(page.getByRole("region", { name: "Todo junto" })).toBeVisible();
      await noVerticalScroll(page);
      editing.push(await pageHeight(page));
    }
    await axe(page);
    await logout(page);

    await login(page, GERENTE2, { mfa: true });
    for (const [i, size] of sizes.entries()) {
      await page.setViewportSize(size);
      await page.goto(url);
      await expect(page.getByRole("region", { name: "Todo junto" })).toBeVisible();
      // El Gerente la ve sin poder cambiarla: ni barra, ni acciones.
      await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
      await expect(page.getByRole("button", { name: "Controlar" })).toHaveCount(0);
      await noVerticalScroll(page);
      expect(await pageHeight(page)).toBeLessThanOrEqual(editing[i]!);
    }
    await axe(page);
  });
});

test.describe("en el celular", () => {
  test.skip(({ isMobile }) => !isMobile, "Solo en el celular.");

  test("el listado y la ficha son de consulta, con 44 px", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/compras/facturas");
    await expect(page.getByRole("heading", { level: 1, name: "Facturas" })).toBeVisible();
    await axe(page);
    await openInvoice(page, "00012001", NORTE);
    await expect(page.getByText("Observada").locator("visible=true").first()).toBeVisible();
    // De consulta: sin barra de guardado ni acciones.
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeHidden();
    await expect(page.getByRole("button", { name: "Controlar" })).toBeHidden();
    const back = page.getByRole("link", { name: "Volver a facturas" }).locator("visible=true");
    expect((await back.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    await axe(page);
  });
});
