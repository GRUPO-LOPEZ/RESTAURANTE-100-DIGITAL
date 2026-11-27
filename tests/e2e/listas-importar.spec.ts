// Listas de precios, parte D (ADR-0071): importar una lista del proveedor, los controles antes de cargar y de aceptar
// (la suba sobre el umbral de Dirección resaltada, «Revisar» a 10 veces, el precio por unidad de uso), corregir la
// vigente (versión 2), anular (vuelve la anterior), la pantalla dividida con una foto y la planilla modelo. Al final el
// Frigorífico vuelve a su lista del seed (se anulan las dos versiones de la prueba). Con axe y sin scroll de página.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { DESK_SIZES, login, noPageScroll } from "./helpers";
import { PNG_HEAD } from "../fixtures/listas";

test.describe.configure({ timeout: 240_000 });

const COMPRAS = "compras@ejemplo.test";
const CONTROLLER = "controller@ejemplo.test";
// El Frigorífico tiene la lista 1302 vigente: albahaca FR007 a $ 1.899,72 por kg y carne picada FR011 a $ 2.491,56.
const FRIGORIFICO = "00000000-0000-4000-8000-000000000902";
const VIGENTE = "00000000-0000-4000-8000-000000001302";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

// Un CSV como lo manda un proveedor: «;», encabezados propios y un renglón de total.
function csv(): { name: string; mimeType: string; buffer: Buffer } {
  const text =
    "Lista ficticia de prueba;;\r\nCód.;Descripción;Precio s/IVA\r\nFR007;Albahaca, por kg;19.000\r\nFR011;Carne picada especial, por kg;3.000\r\n;Total;22.000\r\n";
  return { name: "lista-prueba.csv", mimeType: "text/csv", buffer: Buffer.from(text, "utf-8") };
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "La carga es en la computadora (ADR-0036).");

  test("Compras importa un CSV, ve los controles, acepta, corrige y anula", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/listas-de-precios/nueva?proveedor=${FRIGORIFICO}`);
    await expect(
      page.getByRole("heading", { level: 1, name: "Cargar lista de precios" }),
    ).toBeVisible();
    // La pantalla tiene que estar lista (hidratada): si no, el archivo elegido se pierde.
    await page.waitForLoadState("networkidle");
    await page.getByLabel("La lista del proveedor").setInputFiles(csv());
    // Se lee solo: dos renglones (el total se saltea) y la columna de cada dato, reconocida.
    await expect(page.getByText(/Leímos 2 renglones; salteamos 1/)).toBeVisible();
    await expect(page.getByLabel("Artículo, renglón 1")).toHaveValue("Albahaca, por kg");
    await expect(page.getByLabel("Precio de lista, renglón 2")).toHaveValue("3000");
    await expect(page.getByLabel("Código", { exact: true })).toHaveValue("0");
    // Los controles contra la lista vigente: 10 veces más es «Revisar»; +20 % pasa el umbral (15 %).
    const grid = page.getByRole("table", { name: "Renglones de la lista" });
    await expect(grid.getByText("Revisar")).toBeVisible();
    await expect(grid.getByText("+20,41 %")).toBeVisible();
    await expect(grid.getByText("$ 19.000 por kg")).toBeVisible();
    await expect(page.getByText("1 para revisar")).toBeVisible();
    await noPageScroll(page, "la carga con la planilla leída");
    await axe(page);

    // Cargar pide confirmar los «Revisar».
    await page.getByLabel("Motivo", { exact: true }).fill("Lista de prueba importada");
    await page.getByRole("button", { name: "Cargar lista" }).click();
    await expect(
      page.getByText("Confirmá que revisaste los precios marcados «Revisar»."),
    ).toBeVisible();
    await page.getByLabel("Revisé los precios para revisar").check();
    await page.getByRole("button", { name: "Cargar lista" }).click();
    await expect(page.getByText(/^Lista cargada\./)).toBeVisible();
    await page.getByRole("link", { name: "Ver la lista cargada" }).click();

    // La ficha: los mismos controles y el original guardado.
    await expect(
      page.getByRole("heading", { level: 1, name: /^Lista de Frigorífico/ }),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: /Archivo original/ })).toBeVisible();
    const items = page
      .getByRole("table", { name: "Artículos de la lista" })
      .locator("visible=true");
    await expect(items.getByText("Revisar")).toBeVisible();
    for (const size of DESK_SIZES) {
      await page.setViewportSize(size);
      await noPageScroll(page, `la ficha de la lista (${size.width} × ${size.height})`);
    }
    await page.setViewportSize({ width: 1440, height: 900 });
    await axe(page);
    await page.getByRole("button", { name: "Aceptar" }).click();
    const accept = page.getByRole("dialog", { name: "Aceptar la lista" });
    await expect(accept.getByText(/Hay 1 precio para revisar/)).toBeVisible();
    await accept.getByLabel("Motivo").fill("La revisamos con el proveedor");
    await accept.getByLabel("Revisé los precios para revisar").check();
    await accept.getByRole("button", { name: "Aceptar la lista" }).click();
    await expect(page.getByText(/Lista aceptada/)).toBeVisible();
    const first = page.url().split("?")[0]!;

    // Corregir la vigente: la versión 2, con motivo.
    await page.getByRole("link", { name: "Corregir" }).click();
    await expect(
      page.getByRole("heading", { level: 1, name: /^Corregir la lista de Frigorífico/ }),
    ).toBeVisible();
    await page.getByLabel("Precio de lista, renglón 1").fill("1950");
    await page.getByLabel("Motivo", { exact: true }).fill("La albahaca estaba mal tipeada");
    await page.getByRole("button", { name: "Guardar la versión 2" }).click();
    await expect(page.getByText(/Versión nueva guardada/)).toBeVisible();
    await expect(page.getByText(/^Versión 2 · vale desde/)).toBeVisible();
    await page.getByRole("button", { name: "Ver las 2 versiones" }).click();
    await expect(
      page.getByRole("dialog", { name: "Versiones de la lista" }).getByText("Reemplazada"),
    ).toBeVisible();
    await page.keyboard.press("Escape");

    // Anular la versión 2: vuelve la 1. Anular la 1: vuelve la del seed.
    for (const expected of [/Volvió a valer la anterior/, /Volvió a valer la anterior/]) {
      await page.getByRole("button", { name: "Anular la lista" }).click();
      const dialog = page.getByRole("dialog", { name: "Anular la lista" });
      await dialog.getByLabel("Motivo").fill("Era de prueba");
      await dialog.getByRole("button", { name: "Anular la lista" }).click();
      await expect(page.getByText(expected)).toBeVisible();
      await expect(page.getByText(/^Anulada el/)).toBeVisible();
      if (page.url().split("?")[0] !== first) await page.goto(first);
    }
    await page.goto(`/listas-de-precios/${VIGENTE}`);
    await expect(page.getByText("Vigente", { exact: true }).first()).toBeVisible();
  });

  test("una foto abre la pantalla dividida, con zoom", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/listas-de-precios/nueva?proveedor=${FRIGORIFICO}`);
    const photo = new Uint8Array(512);
    photo.set(PNG_HEAD);
    // La pantalla tiene que estar lista (hidratada): si no, el archivo elegido se pierde.
    await page.waitForLoadState("networkidle");
    await page
      .getByLabel("La lista del proveedor")
      .setInputFiles({ name: "lista.png", mimeType: "image/png", buffer: Buffer.from(photo) });
    const zoom = page.getByRole("group", { name: "Zoom de la foto" });
    await expect(zoom).toBeVisible();
    await zoom.getByRole("button", { name: "Agrandar" }).click();
    await expect(zoom.getByText("125 %")).toBeVisible();
    await expect(page.getByLabel("Artículo, renglón 1")).toBeVisible();
    await noPageScroll(page, "la pantalla dividida");
  });

  test("la planilla modelo se baja desde la ficha del proveedor", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await login(page, CONTROLLER, { mfa: true });
    await page.goto(`/proveedores/${FRIGORIFICO}`);
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      page.getByRole("link", { name: "Planilla modelo (Excel)" }).click(),
    ]);
    expect(download.suggestedFilename()).toMatch(/^lista-de-precios-frigorifico/);
  });
});
