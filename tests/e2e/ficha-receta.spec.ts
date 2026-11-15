// Ficha de receta (ADR-0042) en una pantalla (ADR-0047, Prompt 2 de las fichas sin scroll): en la computadora se carga
// un plato de punta a punta en la planilla (autocompletado por código y por nombre, la fila 11 que aparece sola, costos
// de la base, escala) y una preparación con su peso neto; la página no tiene scroll y la planilla tiene el suyo; quien
// revisa la ve en solo lectura y decide en la barra de abajo; en el celular es de consulta. Con axe; capturas en 1440,
// 1600, 1920 y celular.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import {
  chooseLocal,
  closePanels,
  fillSheetRow,
  login,
  logout,
  notice,
  openSection,
  saveSheet,
} from "./helpers";

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const PASTAS_CENTRO = uuid(201);
const RAVIOLES = uuid(1108);
const SIZES = [
  { width: 1440, height: 900 },
  { width: 1600, height: 900 },
  { width: 1920, height: 1080 },
];
// 25 materias primas del seed que se usan en gramos (DEMO-ING-001 a 050).
const IN_GRAMS = [
  1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 24, 25, 27, 28, 29, 30,
];

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// La pantalla entera entra en la ventana: la página no tiene scroll vertical (ADR-0046 y 0047).
async function noVerticalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollHeight - window.innerHeight,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// Por su etiqueta exacta: «porciones» también aparece en el motivo de otro indicador.
const kpi = (page: Page, label: string) =>
  page
    .locator('[data-slot="kpi"]:visible')
    .filter({ has: page.locator("p").getByText(label, { exact: true }) });
const sheet = (page: Page) => page.locator('[data-slot="sheet-scroll"]:visible');

async function choosePlace(page: Page) {
  await chooseLocal(page, PASTAS_CENTRO);
}

async function newRecipe(page: Page, type: "Plato" | "Preparación", rubro: string, name: string) {
  await page.goto("/recetas/nueva");
  await page.locator("#rec-alta-alcance").selectOption({ label: "De la marca Demo Pastas" });
  await page.getByRole("group", { name: "Tipo" }).getByText(type, { exact: true }).click();
  await page.locator("#rec-alta-categoria").selectOption({ label: rubro });
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-motivo").fill("Ficha de prueba automática");
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
}

test.describe("en la computadora", () => {
  test.skip(({ isMobile }) => isMobile, "La ficha se carga en la computadora (ADR-0036).");

  test("se carga un plato de punta a punta y quien revisa lo aprueba sin poder editarlo", async ({
    page,
  }) => {
    test.setTimeout(180_000);
    const name = `Ravioles de la ficha ${Date.now() % 1_000_000}`;
    await login(page, "director@ejemplo.test", { mfa: true });
    await choosePlace(page);
    await newRecipe(page, "Plato", "Pastas", name);

    // Una sola pantalla, sin índice; la planilla arranca con 10 filas.
    await expect(page.getByRole("navigation", { name: "Secciones de la receta" })).toHaveCount(0);
    await openSection(page, "Ingredientes y costos");
    await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(10);

    // Por código: se escribe el código y se elige la sugerencia.
    await page.getByLabel("Código, fila 1", { exact: true }).fill("DEMO-ING-027");
    await page
      .getByRole("listbox", { name: "Sugerencias" })
      .getByRole("option", { name: /Harina 000/ })
      .click();
    await expect(page.getByLabel("Ingrediente, fila 1", { exact: true })).toHaveValue("Harina 000");
    await page.getByLabel("Cantidad, fila 1", { exact: true }).fill("100");
    // Por nombre y con el teclado: flecha abajo y Enter.
    const ingredient = page.getByLabel("Ingrediente, fila 2", { exact: true });
    await ingredient.fill("Ricota");
    await expect(page.getByRole("listbox", { name: "Sugerencias" })).toContainText("Ricota");
    await ingredient.press("Enter");
    await expect(ingredient).toHaveValue("Ricota");
    await expect(page.getByLabel("Código, fila 2", { exact: true })).toHaveValue("DEMO-ING-021");
    await page.getByLabel("Cantidad, fila 2", { exact: true }).fill("120");

    // Los costos los calcula la base (sin precios: el Director ve costos, la columna de precio va con prices.view).
    // Arriba, los 4 indicadores de un plato.
    const total = kpi(page, "Costo total");
    await expect(total).toContainText("$", { timeout: 20_000 });
    await expect(total).toContainText("Demo Pastas Centro");
    await expect(kpi(page, "Peso total")).toContainText("220 g");
    await expect(kpi(page, "Costo por porción")).toBeVisible();
    await expect(kpi(page, "Porciones")).toBeVisible();
    const row1 = page
      .getByRole("row")
      .filter({ has: page.getByLabel("Cantidad, fila 1", { exact: true }) });
    await expect(row1).toContainText("45,5 %");
    // El total, con su estado en palabras.
    await expect(page.locator("tfoot")).toContainText("Completo");

    // Escala: «Hacer 2 recetas» duplica el peso, y el número queda en la dirección (no es un dato oficial).
    await page.getByLabel("Cantidad de recetas, columna A").fill("2");
    await expect(row1).toContainText("200 g");
    await expect(page).toHaveURL(/hacer=2(%2C|,)10/);

    // La fila 11 aparece sola al completar la última; quitarla vuelve a 10.
    await fillSheetRow(page, 10, "Sal fina", /Sal fina/, "2");
    await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(11);
    await page.getByRole("button", { name: "Más opciones de la fila 10" }).click();
    await page.getByRole("button", { name: "Quitar la fila" }).click();
    await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(10);

    // Rendimiento del plato: peso de la porción → porciones → costo por porción.
    await openSection(page, "Rendimiento");
    await page.getByLabel("Peso de la porción (g)").fill("110");
    await expect(kpi(page, "Porciones")).toContainText("2");
    await expect(kpi(page, "Costo por porción")).toContainText("$");

    // Un paso (en su panel, sobre el mismo borrador) y el envío a revisión, todo en un solo guardado.
    await openSection(page, "Procedimiento");
    await page.getByRole("button", { name: "Agregar paso" }).click();
    await expect(page.getByRole("dialog", { name: "Procedimiento" })).toBeVisible();
    await page.getByLabel("Qué se hace").first().fill("Rellenar, cerrar y hervir.");
    await axe(page);
    await closePanels(page);
    await expect(page.getByRole("list", { name: "Pasos" })).toContainText("Rellenar, cerrar");
    await expect(page.getByRole("status").filter({ hasText: /cambios sin guardar/ })).toBeVisible();
    await axe(page);
    await noHorizontalScroll(page);
    await saveSheet(page, "Plato nuevo de la ficha", true);
    await expect(notice(page).filter({ hasText: "Está en revisión" })).toBeVisible();
    const url = page.url().split("?")[0] ?? page.url();
    await logout(page);

    // Quien revisa: la ficha en solo lectura, y en la barra de abajo sus observaciones y «Aprobar» o «No aprobar».
    await login(page, "chefgrupo@ejemplo.test");
    await page.goto(url);
    await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    await expect(notice(page).filter({ hasText: "Ves la ficha sin poder editarla" })).toBeVisible();
    await expect(page.getByLabel("Cantidad, fila 1", { exact: true })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
    await expect(page.getByRole("table", { name: "Ingredientes y costos" })).toContainText(
      "Harina 000",
    );
    await expect(page.getByText(/^Revisión de v1/)).toBeVisible();
    await page.getByRole("textbox", { name: "Observaciones" }).fill("Bien la porción.");
    await axe(page);
    await page.getByRole("button", { name: "Aprobar", exact: true }).click();
    await expect(notice(page).filter({ hasText: "Aprobada y publicada" })).toBeVisible();
    await page.reload();
    await expect(page.getByText(/^Vigente v1$/)).toBeVisible();
  });

  test("se carga una preparación con su peso neto y su rendimiento", async ({ page }) => {
    test.setTimeout(120_000);
    const name = `Salsa de la ficha ${Date.now() % 1_000_000}`;
    await login(page, "chef@ejemplo.test");
    await newRecipe(page, "Preparación", "Salsas", name);
    await openSection(page, "Ingredientes y costos");
    await fillSheetRow(page, 1, "Tomate perita", /Tomate perita/, "1000");
    await fillSheetRow(page, 2, "Sal fina", /Sal fina/, "10");
    await openSection(page, "Rendimiento");
    await expect(page.getByRole("region", { name: "Rendimiento" })).toContainText(/1.?010 g/);
    await page.getByLabel("Peso neto total").fill("800");
    await page.getByLabel("Unidad", { exact: true }).selectOption("g");
    // Los 4 indicadores de una preparación. 800 g netos ÷ 1.010 g brutos: el objetivo para el control de lotes.
    await expect(kpi(page, "Peso bruto → neto")).toContainText(/1.?010 g → 800 g/);
    await expect(kpi(page, "Rendimiento")).toContainText("79,2 %");
    await expect(kpi(page, "Costo total")).toBeVisible();
    await expect(kpi(page, "Costo por kg neto")).toBeVisible();
    await axe(page);
    await saveSheet(page, "Preparación de la ficha");
    await page.reload();
    await expect(page.getByLabel("Peso neto total")).toHaveValue("800");
    await expect(kpi(page, "Rendimiento")).toContainText("79,2 %");
  });

  test("con 25 ingredientes y 12 pasos la página no tiene scroll y la planilla sí", async ({
    page,
  }, testInfo) => {
    test.setTimeout(300_000);
    const name = `Plato largo ${Date.now() % 1_000_000}`;
    await login(page, "director@ejemplo.test", { mfa: true });
    await choosePlace(page);
    await newRecipe(page, "Plato", "Pastas", name);

    // Cada fila con el teclado: el código, Enter elige la sugerencia y el foco pasa a la cantidad; Tab baja a la fila
    // siguiente (medida y «Más opciones» en el medio) y la fila queda a la vista dentro de la planilla.
    for (const [i, n] of IN_GRAMS.entries()) {
      const row = i + 1;
      const code = page.getByLabel(`Código, fila ${row}`, { exact: true });
      if (row > 1) {
        // En el medio quedan la medida, «Más opciones» y los «—» de las celdas sin dato (también se enfocan).
        for (let k = 0; k < 15; k++) {
          if (await code.evaluate((el) => el === document.activeElement)) break;
          await page.keyboard.press("Tab");
        }
        await expect(code).toBeFocused();
      } else {
        await code.focus();
      }
      await expect(code).toBeInViewport();
      await page.keyboard.type(`DEMO-ING-${String(n).padStart(3, "0")}`);
      await expect(page.getByRole("listbox", { name: "Sugerencias" })).toBeVisible();
      await page.keyboard.press("Enter");
      await expect(page.getByLabel(`Cantidad, fila ${row}`, { exact: true })).toBeFocused();
      await page.keyboard.type("10");
      // Al llenar la décima aparece la undécima, y así.
      if (row >= 10) await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(row + 1);
    }

    // 12 pasos en su panel.
    for (let n = 1; n <= 12; n++) {
      if (n === 1) await page.getByRole("button", { name: "Agregar paso" }).first().click();
      else
        await page
          .getByRole("dialog", { name: "Procedimiento" })
          .getByRole("button", { name: "Agregar paso" })
          .click();
      await page.getByLabel(`Qué se hace (paso ${n})`).fill(`Paso de prueba número ${n}.`);
    }
    await closePanels(page);
    await page.getByLabel("Peso de la porción (g)").fill("200");
    await saveSheet(page, "Plato largo de prueba");

    for (const size of SIZES) {
      await page.setViewportSize(size);
      await page.reload();
      await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
      await expect(page.getByLabel(/^Ingrediente, fila \d+$/)).toHaveCount(26);
      await noVerticalScroll(page);
      await noHorizontalScroll(page);
      // La planilla tiene su propio scroll, y el total sigue a la vista.
      const scroll = await sheet(page).evaluate((el) => el.scrollHeight - el.clientHeight);
      expect(scroll).toBeGreaterThan(0);
      await expect(page.locator("tfoot:visible")).toBeInViewport();
      await sheet(page).evaluate((el) => el.scrollTo(0, el.scrollHeight));
      await expect(page.locator("tfoot:visible")).toBeInViewport();
      await expect(page.getByLabel("Código, fila 26", { exact: true })).toBeInViewport();
      // Los pasos se cortan con «Ver los N»: la pantalla no crece con los datos.
      await expect(page.getByRole("button", { name: "Editar los 12 pasos" })).toBeVisible();
      await page.screenshot({ path: testInfo.outputPath(`ficha-larga-${size.width}.png`) });
    }
    await axe(page);
  });

  test("los enlaces de antes llevan el foco a su tarjeta y los datos se editan en su panel", async ({
    page,
  }) => {
    test.setTimeout(120_000);
    await login(page, "chefgrupo@ejemplo.test");
    await page.setViewportSize({ width: 1440, height: 900 });
    for (const [section, card] of [
      ["procedimiento", "Procedimiento"],
      ["fotos", "Datos generales"],
      ["rendimientos", "Rendimiento"],
    ] as const) {
      await page.goto(`/recetas/${RAVIOLES}?seccion=${section}`);
      await expect(page).toHaveURL(/#/);
      await expect(page.getByRole("region", { name: card })).toBeFocused();
    }
    await page.goto(`/recetas/${RAVIOLES}?seccion=versiones`);
    await expect(page.locator('[id^="versiones-"]:visible')).toBeFocused();
    await noVerticalScroll(page);

    // Los datos que no entran en la tarjeta, en un panel: lo cambiado cuenta en la barra; Descartar lo deshace.
    const edit = page.getByRole("button", { name: /^(Editar datos|Ver todos los datos)/ });
    await edit.click();
    const panel = page.getByRole("dialog", { name: "Datos generales" });
    await expect(panel).toBeVisible();
    await axe(page);
    if ((await page.getByLabel("Sector").getAttribute("readonly")) === null) {
      await page.getByLabel("Sector").fill("Sector de prueba");
      await closePanels(page);
      await expect(
        page.getByRole("status").filter({ hasText: "1 cambio sin guardar" }),
      ).toBeVisible();
      await expect(edit).toContainText("1 cambio sin guardar");
      await page.getByRole("button", { name: "Descartar" }).click();
      await expect(page.getByRole("status").filter({ hasText: "Sin cambios" })).toBeVisible();
    }
  });

  test("capturas de la ficha en 1440, 1600 y 1920", async ({ page }, testInfo) => {
    test.setTimeout(120_000);
    await login(page, "chefgrupo@ejemplo.test");
    for (const size of SIZES) {
      await page.setViewportSize(size);
      await page.goto(`/recetas/${RAVIOLES}`);
      await expect(
        page.getByRole("heading", { name: "Ravioles de ricota", exact: true }),
      ).toBeVisible();
      await expect(page.getByRole("table", { name: "Ingredientes y costos" })).toBeVisible();
      await noVerticalScroll(page);
      await noHorizontalScroll(page);
      await page.screenshot({ path: testInfo.outputPath(`ficha-${size.width}.png`) });
    }
  });
});

test("en el celular la ficha es de consulta", async ({ page, isMobile }, testInfo) => {
  test.skip(!isMobile, "Solo en el celular.");
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto(`/recetas/${RAVIOLES}`);
  await expect(
    page.getByRole("heading", { name: "Ravioles de ricota", exact: true }),
  ).toBeVisible();
  // Ingredientes en tarjetas, indicadores y pasos; ni la planilla ni la barra de guardado.
  const ingredients = page.getByRole("list", { name: "Ingredientes" });
  await expect(ingredients).toContainText("Ricota");
  await expect(page.getByRole("table", { name: "Ingredientes y costos" })).toBeHidden();
  await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeHidden();
  await expect(kpi(page, "Peso total")).toBeVisible();
  await expect(page.getByRole("list", { name: "Pasos" })).toBeVisible();
  // Controles táctiles de 44 px o más.
  const small = await page
    .locator("main")
    .locator("button:visible, a:visible, input:visible, select:visible")
    .evaluateAll((els) =>
      els
        .filter((el) => el.getBoundingClientRect().height < 44)
        .map((el) => el.getAttribute("aria-label") ?? el.textContent?.trim() ?? el.tagName),
    );
  expect(small).toEqual([]);
  await axe(page);
  await noHorizontalScroll(page);
  await page.screenshot({ path: testInfo.outputPath("ficha-celular.png"), fullPage: true });
});
