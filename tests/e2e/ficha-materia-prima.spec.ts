// Ficha de materia prima en una pantalla (ADR-0046; ficha única, ADR-0043): encabezado en una línea, 4 indicadores y
// tarjetas que se editan donde se ven; lo que se edita se guarda junto con la barra de abajo (contador, motivo,
// Descartar, Guardar cambios); las altas y las propuestas van en un panel con su propio flujo; las listas se cortan con
// «Ver los N». En la computadora se carga sin scroll; en el celular, se consulta. Con axe.
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

async function noVerticalScroll(page: Page) {
  const { scroll, client } = await page.evaluate(() => {
    const d = document.scrollingElement ?? document.documentElement;
    return { scroll: d.scrollHeight, client: d.clientHeight };
  });
  expect(scroll).toBeLessThanOrEqual(client);
}

// La tarjeta visible de la ficha con ese título (Next guarda ocultas las pantallas anteriores).
const card = (page: Page, title: string) =>
  page.locator("section:visible", {
    has: page.getByRole("heading", { level: 2, name: title, exact: true }),
  });

// El panel con todos los productos (la tarjeta muestra hasta 3).
async function openProducts(page: Page) {
  await card(page, "Precios de compra")
    .getByRole("button", { name: /^Ver (el producto|los \d+ productos)$/ })
    .click();
  return page.getByRole("dialog", { name: "Precios de compra" });
}

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
    await expect(page.getByText(/ · se usa en g$/)).toBeVisible();
    await expect(notes).toHaveValue("Se guarda en la cámara");
    await expect(page.getByText("Sin cambios")).toBeVisible();

    // Una conversión y un alérgeno, juntos: dos cambios, un solo guardado.
    await page.getByRole("button", { name: "Agregar peso por unidad (g por unidad)" }).click();
    const conversion = page.getByRole("dialog", { name: "Peso por unidad" });
    await conversion.getByLabel("Valor (g por unidad)").fill("90");
    await conversion.getByLabel("Quién lo midió").fill("Pablo");
    await axe(page);
    await conversion.getByRole("button", { name: "Listo" }).click();
    await expect(page.getByText("1 cambio sin guardar")).toBeVisible();
    // Cada clic avanza: Sin dato → No contiene → Puede contener. El nombre del botón dice el estado.
    const leche = card(page, "Alérgenos").getByRole("button", { name: /^Leche / });
    await expect(leche).toHaveAccessibleName("Leche Sin dato. Cambiar");
    await leche.click();
    await expect(leche).toHaveAccessibleName("Leche No contiene. Cambiar. Cambio sin guardar");
    await leche.click();
    await expect(leche).toHaveAccessibleName("Leche Puede contener. Cambiar. Cambio sin guardar");
    await expect(page.getByText("2 cambios sin guardar")).toBeVisible();
    // Sin el origen del dato no se guarda: el guardado lo pide y lleva el foco ahí.
    await motivo(page).fill("Conversión y alérgeno (prueba)");
    await page.getByRole("button", { name: "Guardar cambios", exact: true }).click();
    const origen = page.getByLabel("Origen de estos cambios");
    await expect(origen).toBeFocused();
    await origen.selectOption({ label: "Informado por el proveedor" });
    await axe(page);
    await saveSheet(page, "Conversión y alérgeno (prueba)");
    await expect(
      card(page, "Conversiones").getByRole("listitem").filter({ hasText: "Peso por unidad" }),
    ).toContainText("90 g por unidad");
    await expect(leche).toHaveAccessibleName("Leche Puede contener. Cambiar");
    // El origen guardado se anuncia con el botón (su descripción), sin depender del mouse.
    await expect(leche).toHaveAccessibleDescription(/Informado por el proveedor/);

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
      sheetRows(page, "Productos de compra").filter({ hasText: "Bolsa de 5 kg" }),
      // Sin precio: «Sin precio» con un local elegido arriba, o «Elegí un local» si no hay ninguno (nunca $ 0).
    ).toContainText(/Sin precio|Elegí un local/);

    // Editar el producto (ADR-0044): sin precios se cambia todo. Se corrige la descripción y se deja de comprar: sale de
    // la tabla y queda en «Ya no se compran», desde donde se vuelve a activar. Todo, en el panel de los productos.
    let products = await openProducts(page);
    await products.getByRole("button", { name: `Editar «${name}, bolsa de 5 kg»` }).click();
    const editProduct = page.getByRole("dialog", { name: "Editar producto de compra" });
    await expect(editProduct.getByLabel("Contenido de cada unidad")).toBeEnabled();
    await editProduct.getByLabel("Descripción", { exact: true }).fill(`${name}, bolsa de 10 kg`);
    await editProduct.getByLabel("Contenido de cada unidad").fill("10");
    await editProduct.getByRole("button", { name: "¿Se sigue comprando?" }).click();
    await editProduct.getByLabel("Motivo").fill("Era de 10 kg (prueba)");
    await axe(page);
    await editProduct.getByRole("button", { name: "Guardar producto" }).click();
    await expect(notice(page).filter({ hasText: "Producto de compra guardado." })).toBeVisible();
    // Ya no se compra: sale de la tabla y su panel de edición se cierra con la fila (ADR-0044).
    await expect(editProduct).toHaveCount(0);
    await expect(products).toBeVisible();
    await expect(
      products.getByRole("table", { name: "Productos de compra" }).filter({ hasText: name }),
    ).toHaveCount(0);
    await products.getByText("Ya no se compran (1)").click();
    const retired = products.getByRole("list", { name: "Productos que ya no se compran" });
    await expect(retired).toContainText(`${name}, bolsa de 10 kg`);
    await expect(retired).toContainText("10 kg");
    await retired.getByRole("button", { name: `Editar «${name}, bolsa de 10 kg»` }).click();
    const reactivate = page.getByRole("dialog", { name: "Editar producto de compra" });
    await reactivate.getByRole("button", { name: "¿Se sigue comprando?" }).click();
    await reactivate.getByLabel("Motivo").fill("Se vuelve a comprar (prueba)");
    await reactivate.getByRole("button", { name: "Guardar producto" }).click();
    await expect(notice(page).filter({ hasText: "Producto de compra guardado." })).toBeVisible();
    await page.keyboard.press("Escape");
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(
      sheetRows(page, "Productos de compra").filter({ hasText: "Bolsa de 10 kg" }),
    ).toHaveCount(1);

    // Con muchos productos, la tarjeta muestra 3 y «Ver los N productos»: la pantalla no crece con los datos.
    for (let i = 2; i <= 5; i++) {
      await page.getByRole("button", { name: "Agregar producto de compra" }).click();
      const more = page.getByRole("dialog", { name: "Agregar producto de compra" });
      await more.getByLabel("Código", { exact: true }).fill(`FP-${run}-${i}`);
      await more.getByLabel("Descripción", { exact: true }).fill(`${name}, caja ${i}`);
      await more.getByLabel("Viene en").selectOption("box");
      await more.getByLabel("Contenido de cada unidad").fill(String(i));
      await more.getByLabel("Unidad del contenido").selectOption("kg");
      await more.getByLabel("Motivo").fill("Producto de prueba");
      await more.getByRole("button", { name: "Agregar producto" }).click();
      await expect(notice(page).filter({ hasText: "Producto de compra agregado." })).toBeVisible();
      await page.keyboard.press("Escape");
    }
    await expect(sheetRows(page, "Productos de compra")).toHaveCount(3);
    await expect(
      card(page, "Precios de compra").getByRole("button", { name: "Ver los 5 productos" }),
    ).toBeVisible();
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      { width: 1920, height: 1080 },
    ]) {
      await page.setViewportSize(size);
      await expect(card(page, "Alérgenos")).toBeVisible();
      await noVerticalScroll(page);
    }
    products = await openProducts(page);
    await expect(
      products.getByRole("table", { name: "Productos de compra" }).getByRole("row"),
    ).toHaveCount(6);
    await page.keyboard.press("Escape");

    // Las capturas, con la ficha como la edita Compras (con la barra de abajo).
    await axe(page);
    for (const width of [1440, 1600, 1920]) {
      await page.setViewportSize({ width, height: width === 1920 ? 1080 : 900 });
      await noHorizontalScroll(page);
      await page.screenshot({
        path: testInfo.outputPath(`ficha-materia-prima-${width}.png`),
        fullPage: true,
      });
    }
    await page.setViewportSize({ width: 1440, height: 900 });

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
    await expect(
      card(page, "Mermas y rendimientos")
        .getByRole("listitem")
        .filter({ hasText: "Merma de limpieza" }),
    ).toContainText("En revisión");
    // La Chef no tiene catalog.manage: lee la ficha, sin barra para guardar.
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
    await axe(page);
    await noHorizontalScroll(page);
  });

  test("con precios, la unidad de recetas queda fija, el rubro se cambia y el envase del producto también queda fijo", async ({
    page,
  }, testInfo) => {
    await login(page, "compras@ejemplo.test");
    // La Cebolla tiene precios y ninguna otra prueba la usa: se le cambia el rubro y se le devuelve.
    await page.goto("/materias-primas/00000000-0000-4000-8000-000000000802");
    await expect(page.getByRole("heading", { name: "Cebolla", exact: true })).toBeVisible();
    await expect(page.getByLabel("Se usa en recetas en", { exact: true })).toBeDisabled();
    // ADR-0044: el rubro lo cambia Compras, con motivo, aunque tenga precios.
    const rubro = page.getByLabel("Rubro", { exact: true });
    await expect(rubro).toBeEnabled();
    await rubro.selectOption({ label: "Carnes" });
    await saveSheet(page, "Rubro con precios (prueba)");
    await expect(page.getByText(/ · Carnes · se usa en /)).toBeVisible();
    await page.getByLabel("Rubro", { exact: true }).selectOption({ label: "Verduras y frutas" });
    await saveSheet(page, "Vuelve a su rubro (prueba)");
    await expect(page.getByText(/ · Verduras y frutas · se usa en /)).toBeVisible();

    // El producto con precios se edita, pero el envase y el contenido no: el tooltip explica por qué.
    const products = await openProducts(page);
    await products
      .getByRole("button", { name: /^Editar «/ })
      .first()
      .click();
    const dialog = page.getByRole("dialog", { name: "Editar producto de compra" });
    await expect(dialog.getByLabel("Viene en")).toBeDisabled();
    await expect(dialog.getByLabel("Contenido de cada unidad")).toBeDisabled();
    await expect(dialog.getByLabel("Descripción", { exact: true })).toBeEnabled();
    await dialog.getByRole("button", { name: /por qué no se cambia el envase/ }).focus();
    await expect(page.getByRole("tooltip")).toContainText("agregá otro producto de compra");
    await axe(page);
    for (const width of [1440, 1600, 1920]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.screenshot({ path: testInfo.outputPath(`producto-editar-${width}.png`) });
    }
    await page.keyboard.press("Escape");
  });

  // ADR-0046: entra entera sin scroll; los enlaces de antes llevan el foco a su tarjeta; «Dónde se usa» es el indicador.
  test("la ficha entra en una pantalla y los enlaces de antes llevan a su tarjeta", async ({
    page,
  }) => {
    await login(page, "compras@ejemplo.test");
    const sheet = "/materias-primas/00000000-0000-4000-8000-000000000802";
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      { width: 1920, height: 1080 },
    ]) {
      await page.setViewportSize(size);
      await page.goto(sheet);
      await expect(page.getByText("Sin cambios")).toBeVisible();
      await expect(page.locator('[data-slot="kpi"]')).toHaveCount(4);
      for (const title of [
        "Datos generales",
        "Precios de compra",
        "Mermas y rendimientos",
        "Conversiones",
        "Alérgenos",
      ]) {
        await expect(card(page, title)).toBeInViewport();
      }
      await noVerticalScroll(page);
    }
    // Sin índice ni «Desactivar» escondido: es un botón a la derecha del nombre.
    await expect(
      page.getByRole("navigation", { name: "Secciones de la materia prima" }),
    ).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Desactivar" })).toBeVisible();
    await axe(page);

    // Quien solo lee (la Chef) también la ve entera: los alérgenos en la misma grilla de 2 columnas.
    await logout(page);
    await login(page, "chef@ejemplo.test");
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(sheet);
    await expect(card(page, "Alérgenos")).toBeInViewport();
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
    // La Chef ve costos sin ver precios: el costo neto sí, el precio no.
    await expect(page.locator('[data-slot="kpi"]', { hasText: "Costo neto" })).toBeVisible();
    await expect(page.locator('[data-slot="kpi"]', { hasText: "Precio vigente" })).toHaveCount(0);
    await noVerticalScroll(page);
    await axe(page);
    await logout(page);
    await login(page, "compras@ejemplo.test");
    await page.setViewportSize({ width: 1920, height: 1080 });

    // ?seccion= y el enlace de Calidad llevan el foco a su tarjeta.
    await page.goto(`${sheet}?seccion=alergenos`);
    await expect(page).toHaveURL(/#alergenos-[0-9a-f]{8}$/);
    await expect(card(page, "Alérgenos")).toBeFocused();
    await page.goto(`${sheet}?seccion=compra`);
    await expect(card(page, "Precios de compra")).toBeFocused();
    await page.goto(`${sheet}?seccion=uso`);
    await expect(page.locator('[id^="uso-"]:visible')).toBeFocused();

    // «Dónde se usa»: el número en el indicador y la lista en «Ver cuáles».
    const uses = page.locator('[data-slot="kpi"]', { hasText: "Recetas que la usan" });
    await uses.getByRole("button", { name: "Ver cuáles (Recetas que la usan)" }).click();
    await expect(
      page.getByRole("dialog", { name: "Dónde se usa" }).getByRole("listitem").first(),
    ).toBeVisible();
    await axe(page);
    await page.keyboard.press("Escape");
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
  await expect(
    page.getByRole("button", { name: /^Editar «/ }).filter({ visible: true }),
  ).toHaveCount(0);
  await expect(page.getByText(/^¿Se compra congelada\? (Sí|No)$/)).toBeVisible();
  await expect(sheetRows(page, "Productos de compra").first()).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  await page.screenshot({
    path: testInfo.outputPath("ficha-materia-prima-celular.png"),
    fullPage: true,
  });
});
