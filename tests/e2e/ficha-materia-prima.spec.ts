// Ficha única de materia prima (ADR-0043, pedido de Soy del 2026-11-12): una sola página con índice; lo que se edita se
// guarda junto con la barra de abajo (contador, motivo, Descartar, Guardar cambios); las altas y las propuestas van en
// un panel con su propio flujo. En la computadora se carga; en el celular, se consulta. Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, saveSheet, sheetRows } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

const motivo = (page: Page) => page.getByLabel("Motivo de los cambios", { exact: true });

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "La ficha se carga en la computadora.");
  test.describe.configure({ timeout: 180_000 });

  test("se editan datos, conversión y alérgeno en un solo guardado, y se agrega un producto y una merma", async ({
    page,
  }, testInfo) => {
    // Una materia prima nueva para esta prueba: así no cambia las de las otras.
    const run = `${Date.now() % 1_000_000_000}`;
    const name = `Ficha de prueba ${run}`;
    await login(page, "compras@ejemplo.test");
    await page.goto("/materias-primas");
    await page.getByRole("link", { name: "Nueva materia prima" }).click();
    const create = page.getByRole("dialog", { name: "Nueva materia prima" });
    await create.locator("#mp-alta-categoria").selectOption({ label: "Verduras y frutas" });
    await create.locator("#mp-alta-nombre").fill(name);
    await create.locator("#mp-alta-unidad").selectOption("g");
    await create.locator("#mp-alta-motivo").fill("Prueba de la ficha única");
    await create.getByRole("button", { name: "Crear materia prima" }).click();
    await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    await expect(page.getByText("Sin cambios")).toBeVisible();
    await axe(page);

    // Datos generales: se edita donde se ve. El contador cuenta y «Descartar» vuelve a lo guardado.
    const notes = page.getByLabel("Observaciones", { exact: true });
    await notes.fill("Se guarda en la cámara");
    await page.getByLabel("Se usa en recetas en", { exact: true }).selectOption("kg");
    await expect(page.getByText("Las recetas la calculan en gramos (g).")).toBeVisible();
    await expect(page.getByText("2 cambios sin guardar")).toBeVisible();
    await page.getByRole("button", { name: "Descartar", exact: true }).click();
    await expect(page.getByText("Sin cambios")).toBeVisible();
    await expect(notes).toHaveValue("");

    // Sin motivo no se guarda.
    await notes.fill("Se guarda en la cámara");
    await page.getByRole("button", { name: "Guardar cambios", exact: true }).click();
    await expect(page.getByText("Escribí el motivo de los cambios.")).toBeVisible();
    await expect(motivo(page)).toBeFocused();

    // Un cambio sin guardar avisa antes de irse (el aviso del navegador se cancela y la ficha queda).
    page.once("dialog", (dialog) => void dialog.dismiss());
    await page.getByRole("link", { name: "Volver a materias primas" }).click();
    await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    await expect(notes).toHaveValue("Se guarda en la cámara");

    // Kilogramo se acepta, y la base guarda gramos (la unidad base de su tipo, ADR-0041).
    await page.getByLabel("Se usa en recetas en", { exact: true }).selectOption("kg");
    await saveSheet(page, "Datos de la ficha (prueba)");
    await expect(page.getByText(/· Se usa en recetas en Gramo \(g\)$/)).toBeVisible();
    await expect(notes).toHaveValue("Se guarda en la cámara");
    await expect(page.getByText("Sin cambios")).toBeVisible();

    // Una conversión y un alérgeno, juntos: dos cambios, un solo guardado.
    await page.getByRole("button", { name: "Agregar peso por unidad (g por unidad)" }).click();
    await page.getByLabel("Peso por unidad: valor (g por unidad)").fill("90");
    await page.getByLabel("Peso por unidad: quién lo midió").fill("Pablo");
    const leche = page.getByRole("group", { name: "Leche: estado" });
    await leche.getByText("Puede contener (trazas)", { exact: true }).click();
    await page
      .getByLabel("Leche: de dónde sale")
      .selectOption({ label: "Informado por el proveedor" });
    await expect(page.getByText("2 cambios sin guardar")).toBeVisible();
    await axe(page);
    await saveSheet(page, "Conversión y alérgeno (prueba)");
    await expect(page.getByLabel("Peso por unidad: valor (g por unidad)")).toHaveValue("90");
    await expect(
      page.getByRole("group", { name: "Leche: estado" }).getByRole("radio", {
        name: "Puede contener (trazas)",
      }),
    ).toBeChecked();

    // Agregar un producto de compra: un alta con su propio motivo, en un panel.
    await page.getByRole("button", { name: "Agregar producto de compra" }).click();
    const product = page.getByRole("dialog", { name: "Agregar producto de compra" });
    await product.getByLabel("Código", { exact: true }).fill(`FP-${run}`);
    await product.getByLabel("Descripción", { exact: true }).fill(`${name}, bolsa de 5 kg`);
    await product.getByLabel("Viene en").selectOption("bag");
    await product.getByLabel("Contenido de cada unidad").fill("5");
    await product.getByLabel("Unidad del contenido").selectOption("kg");
    await product.getByLabel("Motivo").fill("Producto de prueba");
    await axe(page);
    await product.getByRole("button", { name: "Agregar producto" }).click();
    await expect(notice(page).filter({ hasText: "Producto de compra agregado." })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(
      sheetRows(page, "Productos de compra").filter({ hasText: `${name}, bolsa de 5 kg` }),
      // Sin precio: «Sin precio» con un local elegido arriba, o «Elegí un local» si no hay ninguno (nunca $ 0).
    ).toContainText(/Sin precio|Elegí un local/);

    // Las capturas, con la ficha como la edita Compras (con la barra de abajo).
    await axe(page);
    for (const width of [1440, 1600, 1920]) {
      await page.setViewportSize({ width, height: 1000 });
      await noHorizontalScroll(page);
      await page.screenshot({
        path: testInfo.outputPath(`ficha-materia-prima-${width}.png`),
        fullPage: true,
      });
    }
    await page.setViewportSize({ width: 1440, height: 1000 });

    // Compras no propone mermas (no tiene yields.record): no ve el botón. La propone la Chef, desde la misma ficha,
    // con su aprobación de siempre.
    await expect(page.getByRole("button", { name: "Proponer merma o rendimiento" })).toHaveCount(0);
    const sheet = page.url().replace(/[?#].*$/, "");
    await logout(page);
    await login(page, "chef@ejemplo.test");
    await page.goto(sheet);
    await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Proponer merma o rendimiento" }).click();
    const proposal = page.getByRole("dialog", { name: "Proponer merma o rendimiento" });
    await proposal.getByLabel("Merma de limpieza (%)").fill("8");
    await proposal.locator("#mp-motivo-merma").fill("Pesado en la cocina (prueba)");
    await proposal.getByRole("button", { name: "Proponer mermas" }).click();
    await expect(notice(page).filter({ hasText: "Queda pendiente" })).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.getByText("1 merma en revisión")).toBeVisible();
    // La Chef no tiene catalog.manage: lee la ficha, sin barra para guardar.
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
    await axe(page);
    await noHorizontalScroll(page);
  });

  test("con precios, la unidad de recetas y el rubro no se cambian (lo explica, no lo esconde)", async ({
    page,
  }) => {
    await login(page, "compras@ejemplo.test");
    await page.goto("/materias-primas/00000000-0000-4000-8000-000000000801");
    await expect(page.getByRole("heading", { name: "Tomate perita", exact: true })).toBeVisible();
    await expect(page.getByLabel("Se usa en recetas en", { exact: true })).toBeDisabled();
    await expect(page.getByLabel("Rubro", { exact: true })).toBeDisabled();
    await page.getByRole("button", { name: /por qué no se cambia el rubro/ }).focus();
    await expect(page.getByRole("tooltip")).toContainText("Ya tiene precios");
    // La tabla de productos muestra el precio por kg del local elegido, o pide elegir uno.
    await expect(sheetRows(page, "Productos de compra").first()).toBeVisible();
    await axe(page);
  });
});

test("en el celular la ficha es de consulta", async ({ page, isMobile }, testInfo) => {
  test.skip(!isMobile, "Solo en el celular.");
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas/00000000-0000-4000-8000-000000000819");
  await expect(page.getByRole("heading", { name: "Mozzarella", exact: true })).toBeVisible();
  // Se lee todo; no hay campos, barra ni paneles para cargar.
  await expect(page.getByRole("textbox", { name: "Nombre", exact: true })).toBeHidden();
  await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeHidden();
  await expect(page.getByRole("button", { name: "Agregar producto de compra" })).toBeHidden();
  await expect(page.getByText(/^¿Se compra congelada\? (Sí|No)$/)).toBeVisible();
  await expect(sheetRows(page, "Productos de compra").first()).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  await page.screenshot({
    path: testInfo.outputPath("ficha-materia-prima-celular.png"),
    fullPage: true,
  });
});
