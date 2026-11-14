// Códigos automáticos y listados por rubro (pedido de Soy del 2026-11-12, ADR-0041): el código de recetas y
// materias primas lo arma la base (PLA-PAS-0001, PRE-SAL-0001, MPR-CAR-0001); el alta lo muestra antes de crear y
// avisa si otra alta tomó el número en el medio. Los listados tienen arriba las tarjetas de los rubros, que filtran
// la tabla con un clic. En celular y computadora (1440, 1600 y 1920), con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// Completa el alta de una receta del grupo (sin crearla) y devuelve el código de la vista previa.
async function fillRecipe(page: Page, type: "Plato" | "Preparación", rubro: string, name: string) {
  await page.locator("#rec-alta-alcance").selectOption({ index: 1 });
  await page.getByRole("group", { name: "Tipo" }).getByText(type, { exact: true }).click();
  await page.locator("#rec-alta-categoria").selectOption({ label: rubro });
  const code = page.locator("#rec-alta-codigo");
  await expect(code).toHaveValue(
    type === "Plato" ? /^PLA-[A-Z0-9]{3}-\d{4,}$/ : /^PRE-[A-Z0-9]{3}-\d{4,}$/,
  );
  await page.locator("#rec-alta-nombre").fill(name);
  await page.locator("#rec-alta-motivo").fill("Prueba automática de códigos");
  return code.inputValue();
}

// El encabezado de la ficha de una receta: «PLA-PAS-0003 · Plato · Todo el grupo».
function header(page: Page, code: string) {
  return page.getByText(new RegExp(`^${code} · `));
}

test("alta de un plato: el código sale del tipo y del rubro, en el orden del pedido", async ({
  page,
}, testInfo) => {
  test.setTimeout(90_000);
  const name = `Plato de códigos ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/recetas");
  await page.getByRole("link", { name: "Nueva receta" }).click();
  const dialog = page.getByRole("dialog", { name: "Nueva receta" });
  await expect(dialog).toBeVisible();
  // El código no se escribe: hasta elegir tipo y rubro dice cómo se arma.
  await expect(dialog.locator("#rec-alta-codigo")).toHaveAttribute("readonly", "");
  await expect(dialog.locator("#rec-alta-codigo")).toHaveValue("Se arma al elegir el rubro");
  // El orden del pedido de Soy: alcance, tipo, rubro, código, nombre, motivo.
  const order = await dialog
    .locator(
      "#rec-alta-alcance, fieldset, #rec-alta-categoria, #rec-alta-codigo, #rec-alta-nombre, #rec-alta-motivo",
    )
    .evaluateAll((els) => els.map((el) => el.id || el.tagName.toLowerCase()));
  expect(order).toEqual([
    "rec-alta-alcance",
    "fieldset",
    "rec-alta-categoria",
    "rec-alta-codigo",
    "rec-alta-nombre",
    "rec-alta-motivo",
  ]);
  const code = await fillRecipe(page, "Plato", "Pastas", name);
  expect(code).toMatch(/^PLA-PAS-\d{4}$/);
  await axe(page);
  await dialog.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  // Sin nadie más creando en el medio, sale el código que se mostró y no hay aviso.
  await expect(header(page, code)).toBeVisible();
  await expect(notice(page).filter({ hasText: "lo tomó otra alta" })).toHaveCount(0);
});

test("alta de una preparación: PRE y el rubro de sub-recetas", async ({ page }, testInfo) => {
  test.setTimeout(90_000);
  const name = `Salsa de códigos ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/recetas/nueva");
  const code = await fillRecipe(page, "Preparación", "Salsas", name);
  expect(code).toMatch(/^PRE-SAL-\d{4}$/);
  await page.getByRole("button", { name: "Crear receta" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await expect(page.getByText(new RegExp(`^${code} · Preparación · `))).toBeVisible();
  await axe(page);
});

test("alta de una materia prima en kilos: MPR y el rubro, y se calcula en gramos", async ({
  page,
}, testInfo) => {
  test.setTimeout(90_000);
  const name = `Carne de códigos ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas");
  await page.getByRole("link", { name: "Nueva materia prima" }).click();
  const dialog = page.getByRole("dialog", { name: "Nueva materia prima" });
  await dialog.locator("#mp-alta-categoria").selectOption({ label: "Carnes" });
  const preview = dialog.locator("#mp-alta-codigo");
  await expect(preview).toHaveValue(/^MPR-CAR-\d{4}$/);
  const code = await preview.inputValue();
  await dialog.locator("#mp-alta-nombre").fill(name);
  // La lista completa del catálogo, con nombres largos; la base guarda la base de su tipo.
  const unit = dialog.locator("#mp-alta-unidad");
  await expect(unit.getByRole("option", { name: "Kilogramo (kg)" })).toHaveCount(1);
  await expect(unit.getByRole("option", { name: "Litro (l)" })).toHaveCount(1);
  await unit.selectOption({ label: "Kilogramo (kg)" });
  await expect(dialog.getByText("Las recetas la calculan en gramos (g).")).toBeVisible();
  await dialog.locator("#mp-alta-motivo").fill("Prueba automática de códigos");
  await axe(page);
  await dialog.getByRole("button", { name: "Crear materia prima" }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  // Ficha única (ADR-0043): el código va solo y, al lado, el rubro y la unidad que guardó la base (kg → g).
  await expect(page.getByText(code, { exact: true })).toBeVisible();
  await expect(page.getByText(/ · Carnes · se usa en g$/)).toBeVisible();
});

test("las tarjetas de rubros filtran la tabla: un clic filtra, otro clic o la ✕ lo quitan", async ({
  page,
}, testInfo) => {
  test.setTimeout(120_000);
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/recetas");
  const kinds = page.getByRole("navigation", { name: "Tipo de receta" });
  await expect(kinds.getByRole("link", { name: /^Platos/ })).toHaveAttribute(
    "aria-current",
    "page",
  );
  const cards = page.getByRole("list", { name: "Rubros de platos" });
  const pastas = cards.getByRole("link", { name: /^Pastas/ });
  await pastas.click();
  await expect(pastas).toHaveAttribute("aria-current", "true");
  await expect(page).toHaveURL(/rubro=/);
  await expect(page.getByText("Rubro: Pastas")).toBeVisible();
  // Todas las filas son del rubro elegido.
  const rows = page.getByRole("table", { name: "Recetas" }).getByRole("row");
  if (testInfo.project.name === "computadora") {
    const rubros = await rows.locator("td:nth-child(3)").allTextContents();
    expect(rubros.length).toBeGreaterThan(0);
    expect(rubros.every((r) => r.startsWith("Pastas"))).toBe(true);
  }
  await axe(page);
  // Otro clic en la misma tarjeta quita el filtro.
  await pastas.click();
  await expect(page).not.toHaveURL(/rubro=/);
  await expect(pastas).not.toHaveAttribute("aria-current", "true");
  // Y la ✕ de la etiqueta también.
  await pastas.click();
  await expect(page.getByText("Rubro: Pastas")).toBeVisible();
  await page
    .getByRole("list", { name: "Filtros aplicados" })
    .getByRole("link", { name: /Rubro: Pastas/ })
    .click();
  await expect(page).not.toHaveURL(/rubro=/);
  // Preparaciones: las tarjetas pasan a los rubros de sub-recetas.
  await kinds.getByRole("link", { name: /^Preparaciones/ }).click();
  await expect(page.getByRole("list", { name: "Rubros de preparaciones" })).toContainText("Salsas");
  await axe(page);

  // Disposición: 2 columnas en el celular y 5 en la computadora (1440, 1600 y 1920), sin scroll de costado.
  const columns = () =>
    page
      .getByRole("list", { name: "Rubros de preparaciones" })
      .evaluate((el) => getComputedStyle(el).gridTemplateColumns.split(" ").length);
  if (testInfo.project.name !== "computadora") {
    expect(await columns()).toBe(2);
    await noHorizontalScroll(page);
    await page.screenshot({ path: testInfo.outputPath("recetas-celular.png"), fullPage: true });
    return;
  }
  for (const width of [1440, 1600, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/recetas?tipo=preparaciones");
    expect(await columns()).toBe(5);
    await noHorizontalScroll(page);
    await page.screenshot({ path: testInfo.outputPath(`recetas-${width}.png`), fullPage: true });
  }
});

test("las materias primas también se ordenan por rubro", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas");
  const cards = page.getByRole("list", { name: "Rubros de compra" });
  const carnes = cards.getByRole("link", { name: /^Carnes/ });
  await carnes.click();
  await expect(page.getByText("Rubro: Carnes")).toBeVisible();
  await expect(carnes).toHaveAttribute("aria-current", "true");
  // Se mantienen las pestañas de estado.
  await expect(
    page.getByRole("navigation", { name: "Estado de las materias primas" }),
  ).toContainText("Desactivadas");
  await axe(page);
  await noHorizontalScroll(page);
});

test("dos altas a la vez nunca reciben el mismo código, y la segunda avisa", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "computadora", "Una vez alcanza: es una prueba de la base.");
  test.setTimeout(120_000);
  const run = Date.now() % 1_000_000;
  await login(page, "chefgrupo@ejemplo.test");
  // Dos pestañas de la misma persona, con el mismo código en la vista previa.
  const other = await page.context().newPage();
  await page.goto("/recetas/nueva");
  await other.goto("/recetas/nueva");
  const first = await fillRecipe(page, "Plato", "Ensaladas", `Ensalada A ${run}`);
  const second = await fillRecipe(other, "Plato", "Ensaladas", `Ensalada B ${run}`);
  expect(second).toBe(first);
  await Promise.all([
    page.getByRole("button", { name: "Crear receta" }).click(),
    other.getByRole("button", { name: "Crear receta" }).click(),
  ]);
  await expect(page.getByRole("heading", { name: `Ensalada A ${run}` })).toBeVisible();
  await expect(other.getByRole("heading", { name: `Ensalada B ${run}` })).toBeVisible();
  const codeOf = async (p: Page) =>
    ((await p.getByText(/^PLA-ENS-\d{4} · /).textContent()) ?? "").split(" · ")[0];
  const [a, b] = [await codeOf(page), await codeOf(other)];
  expect(a).not.toBe(b);
  // La que llegó segunda recibió el siguiente y lo avisa; la otra, no.
  const late = a === first ? other : page;
  await expect(notice(late)).toContainText(`lo tomó otra alta mientras cargabas`);
  await expect(notice(late)).toContainText(`el ${first}`);
  await axe(late);
});
