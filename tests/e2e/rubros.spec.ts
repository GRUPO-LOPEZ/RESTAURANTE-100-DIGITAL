// Rubros (ADR-0038; ficha en ADR-0066, pedido de Soy): la clase como botones, los rubros en un panel fijo y la ficha del
// elegido a la derecha, que se edita y se guarda junta. Compras o Dirección administran los rubros de compra; el Chef del
// grupo, los de sub-recetas y de menú; la Cocinera solo los ve.
// En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { chooseLocal, login, notice } from "./helpers";

const PASTAS_CENTRO = "00000000-0000-4000-8000-000000000201";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function overflow(page: Page) {
  return page.evaluate(() => {
    const d = document.scrollingElement ?? document.documentElement;
    return { x: d.scrollWidth - d.clientWidth, y: d.scrollHeight - d.clientHeight };
  });
}

// El panel de la clase y la ficha del rubro elegido (visibles: Next guarda ocultas las pantallas anteriores).
const panel = (page: Page, label: string) =>
  page.getByRole("navigation", { name: label, exact: true });
const item = (page: Page, label: string, name: string) =>
  panel(page, label).getByRole("link", { name: new RegExp(`^${name}( De baja)? \\d`) });
const sheet = (page: Page, name: string) =>
  page.getByRole("region", { name: `Ficha de ${name}`, exact: true });

async function pick(page: Page, label: string, name: string) {
  // Los vacíos van plegados.
  const fold = panel(page, label).getByText(/^Sin uso \(\d+\)$/);
  await expect(panel(page, label)).toBeVisible();
  if ((await item(page, label, name).count()) === 0) await fold.click();
  await item(page, label, name).click();
  await expect(sheet(page, name)).toBeVisible();
  await expect(item(page, label, name)).toHaveAttribute("aria-current", "true");
}

async function save(page: Page, name: string, reason: string) {
  const card = sheet(page, name);
  await card.getByLabel("Motivo de los cambios").fill(reason);
  await card.getByRole("button", { name: "Guardar cambios" }).click();
}

test("Compras crea un rubro, edita su ficha en lote, lo da de baja y lo reactiva", async ({
  page,
}, testInfo) => {
  test.setTimeout(120_000);
  const name = `Prueba ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto("/rubros");
  await expect(page.getByRole("heading", { name: "Rubros", level: 1 })).toBeVisible();
  await expect(
    page.getByRole("navigation", { name: "Clases de rubro" }).getByRole("link", {
      name: /^De compra/,
    }),
  ).toHaveAttribute("aria-current", "page");
  // La categoría vieja «Carnes» lleva el código de Soy.
  await pick(page, "Rubros de compra", "Carnes");
  await expect(sheet(page, "Carnes")).toContainText("MP-CAR");
  await expect(page.getByLabel("Resumen de rubros de compra")).toContainText("activos");
  await axe(page);

  // Alta: el código lo arma la base con el prefijo.
  await page.getByRole("button", { name: "Nuevo rubro" }).click();
  const dialog = page.getByRole("dialog", { name: "Nuevo rubro" });
  await dialog.locator("#rub-alta-nombre").fill(name);
  await dialog.locator("#rub-alta-motivo").fill("Rubro de prueba automática");
  await dialog.getByRole("button", { name: "Crear rubro" }).click();
  await expect(notice(page)).toContainText(/Rubro creado con el código MP-[A-Z0-9]{3}\./);
  await page.keyboard.press("Escape");
  await pick(page, "Rubros de compra", name);
  await expect(sheet(page, name)).toContainText("Sin uso");

  // La ficha: nombre, descripción, ícono y «va a recetas», juntos. Sin motivo no se guarda.
  const renamed = `${name} bis`;
  const card = sheet(page, name);
  await card.getByLabel("Nombre").fill(renamed);
  await card.getByLabel("Descripción").fill("Se controla la temperatura al recibir.");
  await card.getByText("Pescados", { exact: true }).click({ force: true });
  await card.getByRole("button", { name: "¿Va a recetas?" }).click();
  await expect(card.getByText("4 cambios sin guardar")).toBeVisible();
  await card.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page)).toContainText("Escribí el motivo de los cambios.");
  await expect(card.getByLabel("Motivo de los cambios")).toBeFocused();
  await save(page, name, "Prueba de la ficha");
  const after = sheet(page, renamed);
  await expect(after.getByText("Cambios guardados.")).toBeVisible({ timeout: 20_000 });
  await expect(item(page, "Rubros de compra", renamed)).toBeVisible();
  await expect(after.getByLabel("Descripción")).toHaveValue(
    "Se controla la temperatura al recibir.",
  );
  await expect(after.getByLabel("Pescados")).toBeChecked();
  await expect(after.getByRole("button", { name: "¿Va a recetas?" })).toHaveAttribute(
    "aria-pressed",
    "false",
  );

  // Descartar vuelve a lo guardado.
  await after.getByLabel("Nombre").fill("No se guarda");
  await after.getByRole("button", { name: "Descartar" }).click();
  await expect(after.getByLabel("Nombre")).toHaveValue(renamed);
  await expect(after.getByText("Sin cambios")).toBeVisible();

  // Baja: sin usos, no pide destino.
  await after.getByRole("button", { name: `Dar de baja ${renamed}` }).click();
  const off = page.getByRole("dialog", { name: `Dar de baja «${renamed}»` });
  await expect(off.getByLabel("Pasar a")).toHaveCount(0);
  await off.getByLabel("Motivo").fill("Ya no se usa");
  await off.getByRole("button", { name: "Dar de baja" }).click();
  await expect(notice(page)).toContainText("Rubro dado de baja.");
  await page.keyboard.press("Escape");
  await expect(after.getByText("De baja", { exact: true })).toBeVisible();
  // Los dados de baja van al final del panel.
  await expect(panel(page, "Rubros de compra").getByRole("link").last()).toContainText("De baja");
  await axe(page);

  // Reactivar.
  await after.getByRole("button", { name: `Reactivar ${renamed}` }).click();
  const on = page.getByRole("dialog", { name: `Reactivar «${renamed}»` });
  await on.getByLabel("Motivo").fill("Vuelve");
  await on.getByRole("button", { name: "Reactivar" }).click();
  await expect(notice(page)).toContainText("Rubro activo otra vez.");
  await page.keyboard.press("Escape");
  await expect(after.getByText("Activo", { exact: true })).toBeVisible();
});

test("un rubro con insumos pide el destino antes de darlo de baja", async ({ page }) => {
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto("/rubros");
  await pick(page, "Rubros de compra", "Carnes");
  // Si el clic llega antes de que la página termine de cargar (hidratación), la ventana no se abre: se vuelve a tocar.
  const dialog = page.getByRole("dialog", { name: "Dar de baja «Carnes»" });
  await expect(async () => {
    if (!(await dialog.isVisible())) {
      await sheet(page, "Carnes").getByRole("button", { name: "Dar de baja Carnes" }).click();
    }
    await expect(dialog).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  const target = dialog.getByLabel("Pasar a");
  await expect(target).toHaveAttribute("required", "");
  await expect(target.getByRole("option", { name: /Carnes$/ })).toHaveCount(0);
  await expect(target.getByRole("option", { name: "MP-PES · Pescados y mariscos" })).toHaveCount(1);
  // Sin destino, la base no lo da de baja y dice por qué.
  await dialog.getByLabel("Motivo").fill("Prueba");
  await dialog.getByRole("button", { name: "Dar de baja" }).click();
  await expect(notice(page)).toContainText("elegí a qué rubro pasarlas antes de darlo de baja");
  await page.keyboard.press("Escape");
  await expect(sheet(page, "Carnes").getByText("Activo", { exact: true })).toBeVisible();
  await axe(page);
});

test("el buscador y el orden se aplican solos", async ({ page }) => {
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto("/rubros");
  // El de la pantalla (la barra superior tiene la búsqueda global).
  await page.locator("#rub-buscar").fill("lacteos");
  await expect(page).toHaveURL(/q=lacteos/);
  await expect(panel(page, "Rubros de compra").getByRole("link")).toHaveCount(1);
  await pick(page, "Rubros de compra", "Lácteos");
  // Sin resultados, lo dice en el panel y la ficha abierta sigue.
  await page.locator("#rub-buscar").fill("zzzz");
  await expect(panel(page, "Rubros de compra").getByRole("status")).toContainText(
    "Ningún rubro coincide con «zzzz».",
  );
  await expect(sheet(page, "Lácteos")).toBeVisible();
  await axe(page);
  await page.goto("/rubros?orden=az");
  await expect(panel(page, "Rubros de compra").getByRole("link").first()).toContainText("Aceites");
});

test("lo escrito no se pierde al buscar, ordenar o volver atrás", async ({ page }) => {
  test.setTimeout(120_000);
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/rubros?clase=menu");
  await pick(page, "Rubros de carta", "Carnes");
  await pick(page, "Rubros de carta", "Pastas");
  const card = sheet(page, "Pastas");
  await card.getByLabel("Descripción").fill("Sin guardar todavía");
  const kept = async () => {
    await expect(card.getByLabel("Descripción")).toHaveValue("Sin guardar todavía");
    await expect(card.getByText("1 cambio sin guardar")).toBeVisible();
  };
  // Buscar y ordenar no cambian la ficha abierta.
  await page.locator("#rub-buscar").fill("postr");
  await expect(page).toHaveURL(/q=postr/);
  await kept();
  await page.locator("#rub-buscar").fill("");
  await expect(page).not.toHaveURL(/q=/);
  await page.locator("#rub-orden").selectOption("az");
  await expect(page).toHaveURL(/orden=az/);
  await kept();
  // «Atrás» pregunta: si no, se queda.
  const asked: string[] = [];
  page.once("dialog", (d) => {
    asked.push(d.message());
    void d.dismiss();
  });
  await page.evaluate(() => window.history.back());
  await expect.poll(() => asked.length).toBe(1);
  expect(asked[0]).toContain("cambios sin guardar");
  await kept();
  await expect(page).toHaveURL(/orden=az/);
  // Otro rubro también pregunta; si se acepta, va.
  page.once("dialog", (d) => void d.accept());
  await item(page, "Rubros de carta", "Carnes").click();
  await expect(sheet(page, "Carnes")).toBeVisible();
});

test("el Chef del grupo administra sub-recetas y menú, y ve los de compra sin editarlos", async ({
  page,
}) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/rubros?clase=menu");
  await pick(page, "Rubros de carta", "Carnes");
  await expect(sheet(page, "Carnes")).toContainText("PL-CAR");
  await expect(
    sheet(page, "Carnes").getByRole("link", { name: "Ver sus 4 recetas" }),
  ).toHaveAttribute("href", /\/recetas\?rubro=/);
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toBeVisible();
  await expect(sheet(page, "Carnes").getByLabel("Nombre")).toBeEditable();
  await page.goto("/rubros?clase=sub-recetas");
  await pick(page, "Rubros de preparación", "Salsas");
  await expect(sheet(page, "Salsas")).toContainText("SR-SAL");
  await page.goto("/rubros");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toHaveCount(0);
  await pick(page, "Rubros de compra", "Carnes");
  // La lee: descripción y «va a recetas», sin controles.
  await expect(sheet(page, "Carnes")).toContainText("Se reciben refrigeradas");
  await expect(sheet(page, "Carnes").getByRole("button")).toHaveCount(0);
  await expect(sheet(page, "Carnes").getByRole("textbox")).toHaveCount(0);
  await axe(page);
});

test("la Cocinera ve los rubros y no los edita", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  // No ve los de compra: esa clase no está y entra en la primera que ve.
  await page.goto("/rubros");
  const classes = page.getByRole("navigation", { name: "Clases de rubro" });
  await expect(classes.getByRole("link", { name: /^Preparación/ })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await expect(classes.getByRole("link", { name: /^De compra/ })).toHaveCount(0);
  await page.goto("/rubros?clase=sub-recetas");
  await pick(page, "Rubros de preparación", "Salsas");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toHaveCount(0);
  await expect(sheet(page, "Salsas").getByRole("button")).toHaveCount(0);
  await axe(page);
});

test("Dirección administra los rubros de compra y ve los de menú sin editarlos", async ({
  page,
}) => {
  // Decisión de Joaco (2026-11-10): los rubros de compra los administran Compras o Dirección.
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/rubros");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toBeVisible();
  await pick(page, "Rubros de compra", "Carnes");
  await expect(
    sheet(page, "Carnes").getByRole("button", { name: "Dar de baja Carnes" }),
  ).toBeVisible();
  await page.goto("/rubros?clase=menu");
  await expect(page.getByRole("button", { name: "Nuevo rubro" })).toHaveCount(0);
  await pick(page, "Rubros de carta", "Carnes");
  await expect(sheet(page, "Carnes").getByRole("button")).toHaveCount(0);
});

test("«con precio al día» lo ve quien ve precios, en el local elegido", async ({ page }) => {
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto("/rubros");
  await chooseLocal(page, PASTAS_CENTRO);
  await pick(page, "Rubros de compra", "Verduras y frutas");
  const metric = sheet(page, "Verduras y frutas")
    .locator('[data-slot="kpi"]')
    .filter({ hasText: "Con precio al día" });
  await expect(metric).toContainText("Demo Pastas Centro");
  await expect(metric).toContainText(/de \d+ activas/);
});

test("quien no ve precios no tiene ese indicador", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/rubros");
  await pick(page, "Rubros de compra", "Verduras y frutas");
  await expect(sheet(page, "Verduras y frutas")).toContainText("Recetas que las usan");
  await expect(sheet(page, "Verduras y frutas")).not.toContainText("Con precio al día");
});

for (const who of [
  { email: "chefgrupo@ejemplo.test", name: "quien edita", clase: "menu", label: "Rubros de carta" },
  {
    email: "cocinero@ejemplo.test",
    name: "quien solo lee",
    clase: "sub-recetas",
    label: "Rubros de preparación",
  },
])
  test(`una pantalla sin scroll en la computadora y sin desborde en el celular (${who.name})`, async ({
    page,
    isMobile,
  }) => {
    test.setTimeout(120_000);
    await login(page, who.email);
    if (isMobile) {
      await page.goto(`/rubros?clase=${who.clase}`);
      await expect(panel(page, who.label)).toBeVisible();
      expect((await overflow(page)).x).toBeLessThanOrEqual(0);
      const first = panel(page, who.label).getByRole("link").first();
      expect((await first.boundingBox())?.height).toBeGreaterThanOrEqual(44);
      return;
    }
    for (const [width, height] of [
      [1440, 900],
      [1600, 900],
      [1715, 843],
      [1920, 1080],
    ] as const) {
      await page.setViewportSize({ width, height });
      await page.goto(`/rubros?clase=${who.clase}`);
      await expect(panel(page, who.label)).toBeVisible();
      await expect(page.getByRole("region", { name: /^Ficha de / })).toBeVisible();
      expect(await overflow(page)).toEqual({ x: 0, y: 0 });
      expect((await panel(page, who.label).boundingBox())?.width).toBe(250);
    }
  });

test("al llegar con un rubro, se ve cuál es el elegido", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/rubros?clase=menu");
  await pick(page, "Rubros de carta", "Vinos y tragos");
  await page.reload();
  const chosen = item(page, "Rubros de carta", "Vinos y tragos");
  await expect(chosen).toHaveAttribute("aria-current", "true");
  await expect(chosen).toBeInViewport({ ratio: 0.9 });
});

test("al elegir un rubro sin uso con el teclado, el foco sigue en él", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "El teclado es de la computadora.");
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/rubros?clase=menu");
  await panel(page, "Rubros de carta")
    .getByText(/^Sin uso \(\d+\)$/)
    .click();
  const sopas = item(page, "Rubros de carta", "Sopas");
  await sopas.focus();
  await page.keyboard.press("Enter");
  await expect(sheet(page, "Sopas")).toBeVisible();
  await expect(sopas).toHaveAttribute("aria-current", "true");
  await expect(sopas).toBeFocused();
});

test("con poco lugar (zoom, una tablet) la ficha se puede usar", async ({ page, isMobile }) => {
  test.skip(isMobile, "Es de la computadora.");
  await login(page, "chefgrupo@ejemplo.test");
  for (const [width, height] of [
    [800, 900],
    [960, 600],
    [1024, 600],
    [1280, 600],
  ] as const) {
    await page.setViewportSize({ width, height });
    await page.goto("/rubros?clase=menu");
    const card = page.getByRole("region", { name: /^Ficha de / });
    await expect(card).toBeVisible();
    // La barra de arriba se acomoda al terminar de cargar.
    await expect.poll(async () => (await overflow(page)).x).toBeLessThanOrEqual(0);
    expect((await card.boundingBox())?.height).toBeGreaterThan(300);
  }
});

test("al dar de alta una receta, el rubro se ofrece según el tipo", async ({ page }) => {
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/recetas/nueva");
  const category = page.locator("#rec-alta-categoria");
  const type = page.getByRole("group", { name: "Tipo" });
  // Sin tipo no hay rubro: cada tipo tiene los suyos (y solo hay Plato y Preparación, ADR-0041).
  await expect(category).toBeDisabled();
  await expect(type.getByRole("radio")).toHaveCount(2);
  await type.getByText("Plato", { exact: true }).click();
  await expect(category.getByRole("option", { name: "Pastas", exact: true })).toHaveCount(1);
  await expect(category.getByRole("option", { name: "Salsas", exact: true })).toHaveCount(0);
  await type.getByText("Preparación", { exact: true }).click();
  await expect(category.getByRole("option", { name: "Salsas", exact: true })).toHaveCount(1);
  await expect(category.getByRole("option", { name: "Pastas", exact: true })).toHaveCount(0);
  await axe(page);
});
