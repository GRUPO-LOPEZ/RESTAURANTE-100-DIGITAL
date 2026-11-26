// Recepción (Fase 3, Prompt 4, ADR-0056). Compuerta del plan de la Fase 3: el Gerente recibe en el celular una OC con
// un faltante (foto 1, renglón por renglón, foto 2 y cierre), y a la cocinera, que la pidió, le llega el aviso. «Recibir
// sin OC» en el celular. En la computadora, el informe en la OC (con el efectivo para quien ve precios) y el inventario
// con el filtro por lote, sin scroll. Las fotos son capturas de la propia app (JPEG inventados). Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, menuLink } from "./helpers";

const COCINERA = "cocinero@ejemplo.test";
const GERENTE = "gerente@ejemplo.test";
const COMPRAS = "compras@ejemplo.test";
const CONTROLLER = "controller@ejemplo.test";
const PCE = "00000000-0000-4000-8000-000000000201";

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

// Una foto inventada: una captura JPEG de la pantalla.
async function photo(page: Page, name: string) {
  return {
    name,
    mimeType: "image/jpeg",
    buffer: await page.screenshot({ type: "jpeg", quality: 60 }),
  };
}

async function tall(page: Page, name: RegExp | string) {
  const box = await page
    .getByRole("button", { name, exact: typeof name === "string" })
    .first()
    .boundingBox();
  expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
}

test.describe("en el celular", () => {
  test.skip(({ isMobile }) => !isMobile, "Solo en el celular.");

  test("el Gerente recibe una OC con un faltante y a la cocinera le llega el aviso", async ({
    page,
  }) => {
    test.setTimeout(180_000);
    // La cocinera pide dos artículos a Lácteos.
    await login(page, COCINERA);
    await page.goto("/compras/ordenes/nueva");
    // En el celular, el proveedor se elige arriba (ADR-0069). Lácteos Demo.
    await page
      .getByLabel("Proveedor", { exact: true })
      .selectOption("00000000-0000-4000-8000-000000000903");
    const plus = page.getByRole("button", { name: /^Uno más de / });
    await plus.nth(0).click();
    await plus.nth(0).click();
    await plus.nth(1).click();
    await expect(page.getByText("2 artículos")).toBeVisible();
    await page.getByRole("button", { name: "Enviar orden" }).click();
    await expect(
      page.getByText("Orden mandada: quedó en la cola de envío al proveedor."),
    ).toBeVisible();
    const number =
      (await page.getByRole("heading", { level: 1 }).textContent())?.split(" · ")[0] ?? "";
    expect(number).toMatch(/^PCE-\d{4}$/);
    await logout(page);

    // El Gerente: «¿Qué llegó?» y «Recibir».
    await login(page, GERENTE, { mfa: true });
    await page.goto(`/compras/recepcion?local=${PCE}`);
    await expect(page.getByRole("heading", { name: "¿Qué llegó?" })).toBeVisible();
    await tall(page, `Recibir la orden ${number}`);
    await axe(page);
    await page.getByRole("button", { name: `Recibir la orden ${number}` }).click();

    // Paso 1: el papel y su foto.
    await expect(page.getByRole("heading", { name: "Paso 1 de 4 · Foto del papel" })).toBeVisible();
    await tall(page, "Sacar foto del remito o la factura");
    await page.getByText("Remito", { exact: true }).click();
    await page
      .getByLabel("Foto 1: Sacar foto del remito o la factura")
      .setInputFiles(await photo(page, "remito.jpg"));
    await expect(page.getByRole("img", { name: "Foto 1, página 1" })).toBeVisible();
    await axe(page);
    await page.getByRole("button", { name: "Siguiente: renglón por renglón" }).click();

    // Paso 2: el primero OK, con lote; el segundo no llegó.
    await expect(
      page.getByRole("heading", { name: "Paso 2 de 4 · Renglón por renglón" }),
    ).toBeVisible();
    await expect(page.getByText("0 de 2 renglones revisados")).toBeVisible();
    const cards = page.getByRole("list", { name: "Renglones de la orden" }).getByRole("listitem");
    await tall(page, "OK");
    await cards.nth(0).getByRole("button", { name: "OK" }).click();
    await cards.nth(0).getByLabel("Lote (opcional)").fill("LOTE-E2E");
    await cards.nth(1).getByRole("button", { name: "Observar" }).click();
    await cards.nth(1).getByText("Faltó", { exact: true }).click();
    await cards
      .nth(1)
      .getByLabel(/^Cuánto llegó/)
      .fill("0");
    await expect(page.getByText("2 de 2 renglones revisados")).toBeVisible();
    await axe(page);
    await page.getByRole("button", { name: "Siguiente: firmar el papel" }).click();

    // Paso 3: el papel firmado. Sin la foto no se sigue.
    await expect(
      page.getByRole("heading", { name: "Paso 3 de 4 · Firmar el papel" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Siguiente: resumen" }).click();
    await expect(page.getByText("Sacale una foto al papel firmado.")).toBeVisible();
    await page
      .getByLabel("Foto 2: Sacar foto del papel firmado")
      .setInputFiles(await photo(page, "firmado.jpg"));
    await expect(page.getByRole("img", { name: "Foto 2, página 1" })).toBeVisible();
    await page.getByRole("button", { name: "Siguiente: resumen" }).click();

    // Paso 4: el resumen pide el motivo y cierra.
    await expect(page.getByRole("heading", { name: "Paso 4 de 4 · Resumen" })).toBeVisible();
    await expect(page.getByText("1 observación")).toBeVisible();
    await axe(page);
    await page.getByRole("button", { name: "Cerrar recepción" }).click();
    await expect(page.getByText(/Hubo observaciones: escribí el motivo\./)).toBeVisible();
    await page.getByLabel(/^Motivo de las observaciones/).fill("No llegó el segundo renglón");
    await page.getByRole("button", { name: "Cerrar recepción" }).click();
    await expect(page.getByRole("heading", { name: "Listo" })).toBeVisible();
    await expect(
      page.getByText(
        `La orden ${number} quedó recibida en parte: lo que falta se recibe cuando llegue. Se avisó a Lucía Operadora.`,
      ),
    ).toBeVisible();
    await axe(page);
    await logout(page);

    // La cocinera ve el aviso arriba de sus órdenes y el informe en la OC.
    await login(page, COCINERA);
    await page.goto("/compras/ordenes");
    await page.getByRole("link", { name: `Llegó parte de la orden ${number}` }).click();
    const report = page.getByRole("region", { name: "Recepción" });
    await expect(report.getByText("Recibió Gonzalo Gerente", { exact: false })).toBeVisible();
    await expect(report.getByRole("list", { name: "Renglones observados" })).toContainText("Faltó");
    await expect(report.getByText(/Lotes: .*\(LOTE-E2E\)/)).toBeVisible();
    await axe(page);
  });

  test("Compras recibe sin OC lo que trajo un proveedor", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/recepcion?local=${PCE}`);
    await page.getByLabel("Proveedor").selectOption({ label: "Lácteos Demo" });
    await page.getByRole("button", { name: "Recibir sin OC" }).click();
    await expect(page.getByRole("heading", { name: "Paso 1 de 4 · Foto del papel" })).toBeVisible();
    await page.getByText("Nota a mano", { exact: true }).click();
    await page
      .getByLabel("Foto 1: Sacar foto del remito o la factura")
      .setInputFiles(await photo(page, "nota.jpg"));
    await expect(page.getByRole("img", { name: "Foto 1, página 1" })).toBeVisible();
    await page.getByRole("button", { name: "Siguiente: lo que llegó" }).click();
    await page.getByRole("button", { name: "Agregar lo que llegó" }).click();
    await page.getByLabel("Qué llegó (renglón 1)").fill("Manteca, pan de 5 kg");
    await page.getByLabel("Cuántos (envases o unidades)").fill("2");
    await axe(page);
    await page.getByRole("button", { name: "Siguiente: firmar el papel" }).click();
    await page
      .getByLabel("Foto 2: Sacar foto del papel firmado")
      .setInputFiles(await photo(page, "firmada.jpg"));
    await expect(page.getByRole("img", { name: "Foto 2, página 1" })).toBeVisible();
    await page.getByRole("button", { name: "Siguiente: resumen" }).click();
    await page.getByRole("button", { name: "Cerrar recepción" }).click();
    await expect(page.getByText("La recepción quedó guardada.")).toBeVisible();
  });
});

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("el informe en la OC muestra las fotos, lo observado y el efectivo a quien ve precios", async ({
    page,
  }) => {
    await login(page, COMPRAS, { mfa: true });
    // Las del seed son de la Parrilla (Compras puede tener otro local elegido arriba).
    await page.goto("/compras/ordenes?estado=todas&local=00000000-0000-4000-8000-000000000203");
    await page.getByRole("link", { name: "PAR-0002" }).click();
    const report = page.getByRole("region", { name: "Recepción" });
    await expect(report.getByText("Parcial")).toBeVisible();
    await expect(
      report.getByText(/Se pagó en efectivo: \$\s?15\.000,00\. Lo confirma Compras\./),
    ).toBeVisible();
    await expect(report.getByRole("list", { name: "Renglones observados" })).toContainText("Faltó");
    await expect(report.getByRole("list", { name: "Renglones observados" })).toContainText(
      "No estaba en la orden",
    );
    await expect(
      report.getByRole("list", { name: "Fotos del papel" }).getByRole("listitem"),
    ).toHaveCount(2);
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1715, height: 843 },
    ]) {
      await page.setViewportSize(size);
      await noHorizontalScroll(page);
    }
    await axe(page);
  });

  test("el inventario busca un lote y entra sin scroll en las cuatro pantallas", async ({
    page,
  }) => {
    await login(page, CONTROLLER, { mfa: true });
    // El Controller ve el inventario pero no recibe.
    await expect(await menuLink(page, "Inventario")).toBeVisible();
    await expect(page.getByRole("link", { name: "Recepción", exact: true })).toHaveCount(0);
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      { width: 1715, height: 843 },
      { width: 1920, height: 1080 },
    ]) {
      await page.setViewportSize(size);
      await page.goto("/inventario?lote=l-2611");
      const table = page.getByRole("table", { name: "Movimientos de stock" });
      await expect(table).toContainText("L-2611-A");
      await expect(table).toContainText("Leche entera");
      await expect(table.getByRole("row")).toHaveCount(2);
      const extra = await page.evaluate(
        () => document.documentElement.scrollHeight - window.innerHeight,
      );
      expect(extra).toBeLessThanOrEqual(0);
      await noHorizontalScroll(page);
    }
    await axe(page);
    // Desde Calidad, «Buscar un lote» lleva al inventario.
    await page.goto("/calidad");
    await page.getByRole("link", { name: "Buscar un lote" }).click();
    await expect(page).toHaveURL(/\/inventario/);
  });
});
