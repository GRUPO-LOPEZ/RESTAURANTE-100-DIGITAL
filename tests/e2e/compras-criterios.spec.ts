// Criterios de Soy en Compras (PR A, ADR-0068). En la computadora: cada pantalla de Compras entra sin scroll de página en
// las cuatro pantallas, con quien edita (Compras) y con quien solo lee (Auditor); los listados tienen el panel de
// proveedores (o rubros) a la izquierda y su número coincide con la tabla; las fechas se escriben y se leen dd/mm/aaaa
// aunque Chrome esté en inglés; los archivos se suben con «Subir …», sin el control del navegador; la ficha de la OC
// tiene sus acciones en fila y 4 indicadores. En el celular: sin panel, con el filtro de arriba y controles de 44 px.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { DESK_SIZES, login, noInnerScroll, noPageScroll } from "./helpers";

test.describe.configure({ timeout: 300_000 });

const COMPRAS = "compras@ejemplo.test";
const AUDITOR = "auditor@ejemplo.test";
// Demo Parrilla Centro: las facturas y los pagos del seed.
const PARRILLA = "00000000-0000-4000-8000-000000000203";
// Demo Pastas Centro: las órdenes del seed que todavía esperan (en cola, con novedad, a aprobar).
const PASTAS = "00000000-0000-4000-8000-000000000201";

const LISTS = [
  "/compras",
  "/compras/ordenes",
  "/compras/facturas",
  "/compras/pagos",
  "/listas-de-precios",
  "/proveedores",
  "/compras/recepcion",
];

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function heading(page: Page) {
  await expect(page.getByRole("heading", { level: 1 }).locator("visible=true")).toBeVisible();
  // El contenido llega en streaming: se espera que termine de cargar.
  await expect(page.getByText("Cargando…").locator("visible=true")).toHaveCount(0);
}

// La primera ficha del listado (la orden o la factura más nueva que ve la persona). El seed tiene las dos: si no aparece,
// la prueba falla (nunca se saltea sin medir).
async function firstSheet(page: Page, list: string, caption: string): Promise<string> {
  await page.goto(list);
  await heading(page);
  // La tabla llega en streaming: se espera a que esté antes de buscar el enlace.
  const table = page.getByRole("region", { name: `${caption} (tabla)` });
  await expect(table).toBeVisible();
  const link = table.getByRole("link").filter({ hasText: /\d/ }).first();
  await expect(link).toBeVisible();
  const href = await link.getAttribute("href");
  expect(href, `una ficha en ${list}`).not.toBeNull();
  return href!;
}

async function everyScreen(page: Page, who: string) {
  const sheets = [
    await firstSheet(page, `/compras/ordenes?local=${PASTAS}&estado=todas`, "Órdenes de compra"),
    await firstSheet(page, `/compras/facturas?local=${PARRILLA}`, "Facturas"),
  ];
  for (const size of DESK_SIZES) {
    await page.setViewportSize(size);
    for (const path of [...LISTS, ...sheets]) {
      await page.goto(path);
      // Quien no tiene la pantalla vuelve al Inicio: se mide igual lo que ve.
      await heading(page);
      await noPageScroll(page, `${who} en ${path} (${size.width} × ${size.height})`);
      const datos = page.locator("#datos");
      if (await datos.isVisible())
        await noInnerScroll(datos, `Datos de la factura (${size.width})`);
    }
  }
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("cada pantalla de Compras entra sin scroll en las cuatro pantallas, con Compras", async ({
    page,
  }) => {
    await page.setViewportSize(DESK_SIZES[0]);
    await login(page, COMPRAS, { mfa: true });
    await everyScreen(page, "Compras");
  });

  test("y con quien solo lee (Auditor)", async ({ page }) => {
    await page.setViewportSize(DESK_SIZES[0]);
    await login(page, AUDITOR);
    await everyScreen(page, "Auditor");
  });

  test("el panel de proveedores cuenta lo mismo que la tabla y el título va de 20 px", async ({
    page,
  }) => {
    await page.setViewportSize(DESK_SIZES[0]);
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/facturas?local=${PARRILLA}`);
    await heading(page);
    expect(
      await page
        .getByRole("heading", { level: 1 })
        .locator("visible=true")
        .evaluate((el) => getComputedStyle(el).fontSize),
    ).toBe("20px");
    const panel = page.getByRole("navigation", { name: "Proveedores" });
    await expect(panel.getByRole("link", { name: /^Todos los proveedores/ })).toHaveAttribute(
      "aria-current",
      "true",
    );
    const link = panel.getByRole("link", { name: /^Lácteos Demo/ });
    const count = Number(/\d+/.exec(await link.innerText())?.[0]);
    expect(count).toBeGreaterThan(0);
    await link.click();
    await expect(page).toHaveURL(/proveedor=/);
    await expect(link).toHaveAttribute("aria-current", "true");
    await expect(
      page
        .getByRole("region", { name: "Facturas", exact: true })
        .getByText(count === 1 ? "1 factura" : `${count} facturas`, { exact: true }),
    ).toBeVisible();
    const table = page.getByRole("region", { name: "Facturas (tabla)" });
    await expect(table.getByRole("row")).toHaveCount(count + 1);
    // La tabla entra a lo ancho con el panel: no esconde columnas detrás de un scroll de costado.
    expect(await table.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1);
    await axe(page);
    // «Todos los proveedores» vuelve a la lista entera.
    await panel.getByRole("link", { name: /^Todos los proveedores/ }).click();
    await expect(page).not.toHaveURL(/proveedor=/);
  });

  test("la ficha de la OC tiene las acciones en fila y 4 indicadores", async ({ page }) => {
    await page.setViewportSize(DESK_SIZES[0]);
    await login(page, COMPRAS, { mfa: true });
    // Una con novedad: tiene a la vista sus tres acciones (Recibir, Registrar novedad y Cancelar).
    await page.goto(
      await firstSheet(
        page,
        `/compras/ordenes?local=${PASTAS}&estado=novedades`,
        "Órdenes de compra",
      ),
    );
    await heading(page);
    await expect(page.locator('[data-slot="kpi"]').locator("visible=true")).toHaveCount(4);
    const actions = page
      .locator('[data-slot="page-header"] > div')
      .last()
      .locator("button:visible, a:visible");
    const tops = await actions.evaluateAll((els) =>
      els.map((el) => Math.round(el.getBoundingClientRect().top)),
    );
    expect(tops.length).toBeGreaterThanOrEqual(3);
    expect(new Set(tops).size, "las acciones van en una sola fila").toBe(1);
    await axe(page);
  });

  test("los archivos se suben con un botón propio, nunca con el control del navegador", async ({
    page,
  }) => {
    await page.setViewportSize(DESK_SIZES[0]);
    await login(page, COMPRAS, { mfa: true });
    await page.goto("/proveedores/importar");
    await heading(page);
    await expect(page.getByText("Subir planilla").locator("visible=true")).toBeVisible();
    await expect(page.getByText("Ningún archivo elegido").locator("visible=true")).toBeVisible();
    // Todo input de archivo está escondido (transparente sobre su botón, o fuera de la vista).
    const shown = await page.locator('input[type="file"]').evaluateAll(
      (els) =>
        els.filter((el) => {
          const s = getComputedStyle(el);
          const r = el.getBoundingClientRect();
          return s.opacity !== "0" && r.width > 1 && r.height > 1 && s.display !== "none";
        }).length,
    );
    expect(shown).toBe(0);
    // El campo lo nombra su etiqueta y elige el archivo como siempre.
    await page.getByLabel("2. Subí la planilla completa (.xlsx)").setInputFiles({
      name: "proveedores.xlsx",
      mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      buffer: Buffer.from("no es una planilla"),
    });
    await expect(page.getByRole("button", { name: "Quitar proveedores.xlsx" })).toBeVisible();
    await expect(page.getByText("Cambiar archivo").locator("visible=true")).toBeVisible();
  });
});

test.describe("con Chrome en inglés", () => {
  test.use({ locale: "en-US" });
  test.skip(({ isMobile }) => isMobile, "Solo en la computadora.");

  test("las fechas se escriben y se leen dd/mm/aaaa", async ({ page }) => {
    await page.setViewportSize(DESK_SIZES[0]);
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/facturas?local=${PARRILLA}`);
    await heading(page);
    const desde = page.getByLabel("Desde");
    await expect(desde).toHaveAttribute("placeholder", "dd/mm/aaaa");
    // Las barras se ponen solas.
    await desde.pressSequentially("01112026");
    await expect(desde).toHaveValue("01/11/2026");
    await expect(page).toHaveURL(/desde=2026-11-01/);
    await expect(page.getByText("Desde el 01/11/2026").locator("visible=true")).toBeVisible();
    await page.reload();
    await heading(page);
    await expect(page.getByLabel("Desde")).toHaveValue("01/11/2026");
    // Una fecha que no existe lo dice al salir del campo, en castellano.
    const hasta = page.getByLabel("Hasta");
    await hasta.fill("31/02/2026");
    await hasta.blur();
    await expect(page.getByText("Escribí una fecha que exista, como dd/mm/aaaa.")).toBeVisible();
    await expect(hasta).toHaveAttribute("aria-invalid", "true");
    await axe(page);
  });
});

test.describe("en el celular", () => {
  test.skip(({ isMobile }) => !isMobile, "Solo en el celular.");

  test("sin panel: el proveedor se elige arriba, con controles de 44 px", async ({ page }) => {
    await login(page, COMPRAS, { mfa: true });
    await page.goto(`/compras/facturas?local=${PARRILLA}`);
    await heading(page);
    await expect(page.getByRole("navigation", { name: "Proveedores" })).toBeHidden();
    const supplier = page.getByLabel("Proveedor").locator("visible=true");
    await expect(supplier).toBeVisible();
    expect((await supplier.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    const desde = page.getByLabel("Desde");
    expect((await desde.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    expect(
      (await page.getByRole("button", { name: "Abrir calendario" }).first().boundingBox())?.width ??
        0,
    ).toBeGreaterThanOrEqual(44);
    await axe(page);
  });
});
