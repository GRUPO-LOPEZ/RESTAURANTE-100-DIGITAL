// Costos de recetas (ADR-0032; en una pantalla sin scroll, ADR-0048): quien ve costos sabe cuánto cuesta cada receta en
// su local, qué la encarece y qué le falta. El Chef ve costos sin ver precios; Compras y la Cocinera no ven costos. En
// celular y computadora, con axe. Los números son los de docs/guias/costos-demo.md; los indicadores se controlan con la
// regla y los números de la pantalla (una corrida completa cambia el seed).
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";

import { chooseLocal, login, logout, notice, openSection } from "./helpers";

// El servidor compila cada pantalla la primera vez: en celular a veces pasa de 30 s.
test.describe.configure({ timeout: 90_000 });

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

// Pantalla sin scroll (ADR-0048): la página no pasa del alto de la ventana.
async function noVerticalScroll(page: Page) {
  const extra = await page.evaluate(
    () => document.documentElement.scrollHeight - window.innerHeight,
  );
  expect(extra).toBeLessThanOrEqual(0);
}

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const PASTAS_CENTRO = uuid(201);
const RAVIOLES = uuid(1108);
const SIZES = [
  [1440, 900],
  [1600, 900],
  [1715, 843],
  [1920, 1080],
] as const;

const kpi = (page: Page, label: string) =>
  page
    .locator('[data-slot="kpi"]:visible')
    .filter({ has: page.locator("p").getByText(label, { exact: true }) });

// Las filas de la línea por línea: tabla en la computadora, lista en el celular.
function lineRows(page: Page, desktop: boolean): Locator {
  return desktop
    ? page.getByRole("table", { name: "Costo de cada línea" }).locator("tbody tr")
    : page.getByRole("list", { name: "Costo de cada línea" }).getByRole("listitem");
}

// La regla única de lo que falta (lib/metrics.ts): nada = al día; más de la mitad = crítico; si no, atención.
function ruleStatus(missing: number, total: number): "ok" | "warn" | "bad" | "none" {
  if (total <= 0) return "none";
  if (missing <= 0) return "ok";
  return missing * 2 > total ? "bad" : "warn";
}
const STATUS_CLASS = { ok: "bg-ok", warn: "bg-warn", bad: "bg-bad", none: "bg-none" } as const;

async function readCount(card: Locator): Promise<{ value: number; total: number }> {
  const text = (await card.textContent()) ?? "";
  const match = /(\d+)\s*de\s*(\d+)/.exec(text);
  expect(match, `«N de total» en ${text}`).not.toBeNull();
  return { value: Number(match?.[1]), total: Number(match?.[2]) };
}

test("el Controller ve cuánto cuesta cada receta y qué la encarece", async ({ page }, info) => {
  const desktop = info.project.name === "computadora";
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/costos");
  // Con «Todos mis locales» arriba, Costos lo dice y cada botón aplica ese local (ADR-0048).
  await chooseLocal(page, { label: "Todos mis locales" });
  await expect(page.getByText("Costos se ve de a un local.")).toBeVisible();
  await page
    .getByRole("list", { name: "Tus locales" })
    .getByRole("button", { name: "Demo Pastas Centro" })
    .click();
  await expect(page.getByText(/^Demo Pastas Centro · actualizado el .* · sin IVA$/)).toBeVisible();
  await expect(page.getByLabel("Local activo").locator("visible=true")).toHaveValue(PASTAS_CENTRO);
  await expect(page.locator('[data-slot="kpi"]:visible')).toHaveCount(4);
  await noHorizontalScroll(page);
  await axe(page);

  // Los Ravioles, con la bolognesa adentro: lo que más pesa, primero.
  await page.goto(`/costos/${RAVIOLES}`);
  await expect(page.getByRole("heading", { level: 1, name: "Ravioles de ricota" })).toBeVisible();
  await expect(page.getByText(/· actualizado el /)).toBeVisible();
  await expect(kpi(page, "Costo sin IVA")).toContainText("4.506,27");
  await expect(kpi(page, "Con IVA")).toContainText("5.452,58");
  await expect(page.getByText("Desactualizado").first()).toBeVisible();
  await expect(lineRows(page, desktop).first()).toContainText("Salsa bolognesa");
  await expect(lineRows(page, desktop).first()).toContainText("3.045,25");
  await expect(lineRows(page, desktop).first()).toContainText("67,6 %");
  // «Para bajar el costo»: la línea que más pesa y su parte, con el mismo número que la tabla.
  await expect(page.getByRole("region", { name: "Para bajar el costo" })).toContainText(
    "Salsa bolognesa (una preparación) es el 67,6 % del costo.",
  );
  await expect(page.getByRole("list", { name: "Historia del costo" })).toBeVisible();
  // El Controller no trabaja recetas: no tiene el enlace a la ficha.
  await expect(page.getByRole("link", { name: "Ver la receta" })).toHaveCount(0);
  await noHorizontalScroll(page);
  await axe(page);

  // Una receta incompleta dice qué falta: la franja, el «—» y la línea sin dato al final.
  await page.goto(`/costos?confiabilidad=incomplete&q=lasa`);
  await page.getByRole("link", { name: "Lasaña bolognesa" }).first().click();
  await expect(page.getByText(/^Falta un dato:/)).toBeVisible();
  await expect(page.getByText(/El total queda vacío hasta resolverlo\./)).toBeVisible();
  await expect(kpi(page, "Costo sin IVA")).toContainText("—");
  await expect(kpi(page, "Costo sin IVA")).toContainText("Sin datos");
  await expect(lineRows(page, desktop).last()).toContainText("La preparación está incompleta");
  await expect(page.getByRole("region", { name: "Para bajar el costo" })).toContainText(
    "Primero hay que completar el dato que falta.",
  );
  await axe(page);
});

test("el Controller recibe el aviso de cambio de costo", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(page.getByRole("heading", { name: /^Avisos \(/ })).toBeVisible();
  const card = page
    .getByRole("listitem")
    .filter({ hasText: "Cambió el costo de «Salsa bolognesa»" });
  await expect(card).toContainText("2 recetas en 1 de tus locales.");
  await expect(card.getByRole("link", { name: /Ver el costo/ })).toHaveAttribute(
    "href",
    `/costos/${RAVIOLES}?local=${PASTAS_CENTRO}`,
  );
  await axe(page);
});

test("el Gerente ve solo su local", async ({ page }) => {
  await login(page, "gerente@ejemplo.test", { mfa: true });
  // Aunque pida otro local en la dirección.
  await page.goto(`/costos?local=${uuid(203)}`);
  await expect(page.getByText(/^Demo Pastas Centro · /)).toBeVisible();
  await expect(page.getByText("Demo Parrilla Centro")).toHaveCount(0);
  await page.goto(`/costos/${RAVIOLES}`);
  await expect(page.getByRole("heading", { level: 1, name: "Ravioles de ricota" })).toBeVisible();
});

test("el Chef ve el costo por línea, sin precios", async ({ page }, testInfo) => {
  await login(page, "chef@ejemplo.test");
  await page.goto(`/costos/${RAVIOLES}?local=${PASTAS_CENTRO}`);
  await expect(lineRows(page, testInfo.project.name === "computadora").first()).toBeVisible();
  await expect(page.getByText("3.045,25").locator("visible=true").first()).toBeVisible();
  // Ni el envase, ni el producto, ni el proveedor.
  await expect(page.getByText(/el envase|bolsa de|Factura/)).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Ver la receta" })).toHaveAttribute(
    "href",
    `/recetas/${RAVIOLES}`,
  );
  await page.goto(`/recetas/${RAVIOLES}`);

  // En la ficha de la receta, con su local elegido.
  await chooseLocal(page, PASTAS_CENTRO);
  await openSection(page, "Ingredientes y costos");
  const total = page.locator('[data-slot="kpi"]').filter({ hasText: "Costo total" });
  await expect(total).toContainText("4.506,27", { timeout: 20_000 });
  await expect(total).toContainText("Demo Pastas Centro");
  if (testInfo.project.name !== "celular") {
    // Costo por renglón sí; el precio de compra, no (sin prices.view, ADR-0032).
    await expect(page.getByRole("columnheader", { name: "Costo", exact: true })).toBeVisible();
    await expect(page.getByRole("columnheader", { name: "$ por kg o l" })).toHaveCount(0);
  }
  await axe(page);
  await page.goto("/recetas");
  await expect(page.getByText(/Costo sin IVA en Demo Pastas Centro/).first()).toBeAttached();
  await axe(page);
  await chooseLocal(page, { label: "Todos mis locales" });
});

test("Compras y la Cocinera no ven costos", async ({ page }, testInfo) => {
  await login(page, "compras@ejemplo.test");
  if (testInfo.project.name === "computadora")
    await expect(page.getByRole("link", { name: "Costos", exact: true })).toHaveCount(0);
  await page.goto("/costos");
  await expect(page).toHaveURL(/\/$/);
  await page.goto(`/costos/${RAVIOLES}?local=${PASTAS_CENTRO}`);
  await expect(page).toHaveURL(/\/$/);
  await logout(page);

  await login(page, "cocinero@ejemplo.test");
  await page.goto("/costos");
  await expect(page).toHaveURL(/\/$/);
  // La vista de cocina sigue sin importes, con costos reales.
  await page.goto(`/recetas/${uuid(1104)}/cocina`);
  await expect(page.getByRole("heading", { level: 2 }).first()).toBeVisible();
  await expect(page.getByText(/\$\s?\d/)).toHaveCount(0);
});

test("un precio nuevo muestra a qué recetas les pegó", async ({ page }, testInfo) => {
  test.setTimeout(240_000);
  // Una materia prima para cada proyecto, del chimichurri: así no mueve los números de las otras pruebas.
  const [ingredient, price] =
    testInfo.project.name === "celular" ? [uuid(808), "9000"] : [uuid(843), "45000"];

  await login(page, "compras@ejemplo.test");
  await page.goto(`/materias-primas/${ingredient}?seccion=compra`);
  // «Proponer precio» abre su panel (ficha sin scroll, ADR-0046), también en el celular.
  // Si el clic llega antes de que la ficha termine de cargar (hidratación), el panel no se abre: se vuelve a tocar.
  const panel = page.getByRole("dialog", { name: "Proponer precio" });
  await expect(async () => {
    if (!(await panel.isVisible())) {
      await page.getByRole("button", { name: "Proponer precio" }).filter({ visible: true }).click();
    }
    await expect(panel).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await panel.locator("#precio-producto").selectOption({ index: 1 });
  await panel.locator("#precio-lugar").selectOption({ label: "Todo el grupo (Grupo Demo)" });
  await panel.locator("#precio-envase").fill(price);
  await panel.locator("#precio-motivo").fill("Precio de prueba automática");
  await panel.getByRole("button", { name: "Proponer precio" }).click();
  await expect(notice(page).filter({ hasText: "Precio propuesto." })).toBeVisible();
  await page.keyboard.press("Escape");
  await logout(page);

  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  const request = page
    .getByRole("listitem")
    .filter({ hasText: "Precio de prueba automática" })
    .filter({ has: page.getByRole("button", { name: "Aprobar" }) })
    .first();
  await request.getByRole("button", { name: "Aprobar" }).click();
  await expect(page.getByRole("heading", { name: /Resueltas/ })).toBeVisible();

  await page.goto(`/materias-primas/${ingredient}?seccion=compra`);
  // El impacto de cada precio está en el panel de los productos.
  await page
    .getByRole("button", { name: /^Ver (el producto|los \d+ productos)$/ })
    .filter({ visible: true })
    .click();
  await page
    .getByRole("link", { name: /Ver el impacto/ })
    .first()
    .click();
  await expect(page).toHaveURL(/\/costos\/impacto\//);
  // La cola corre cada minuto: la prueba espera a la tarea de verdad.
  await expect(async () => {
    await page.reload();
    await expect(page.getByRole("link", { name: "Chimichurri" }).first()).toBeVisible();
  }).toPass({ timeout: 100_000, intervals: [5_000] });
  await expect(page.getByText(/Antes .*, ahora/).first()).toBeVisible();
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(3);
  await noHorizontalScroll(page);
  await axe(page);
});

// La lista se ordena por columna (en la base: todas las recetas, no solo la página), elige cuántas filas ver, filtra
// con los botones de confiabilidad y el detalle vuelve a la misma lista (ADR-0036 y ADR-0048).
test("la lista de costos se ordena, se pagina, filtra y vuelve con sus filtros", async ({
  page,
}, info) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  await expect(page.getByLabel("Local activo").locator("visible=true")).toHaveValue(PASTAS_CENTRO);
  // El ?local= quedó aplicado y sale de la dirección (ADR-0048).
  await expect(page).not.toHaveURL(/local=/);
  if (info.project.name === "computadora") {
    const header = page.getByRole("columnheader", { name: /Costo sin IVA/ });
    await header.getByRole("link").click();
    await expect(page).toHaveURL(/orden=total/);
    await expect(page.getByRole("columnheader", { name: /Costo sin IVA/ })).toHaveAttribute(
      "aria-sort",
      "ascending",
    );
    await page
      .getByRole("columnheader", { name: /Costo sin IVA/ })
      .getByRole("link")
      .click();
    await expect(page).toHaveURL(/orden=-total/);
    await expect(page.getByRole("columnheader", { name: /Costo sin IVA/ })).toHaveAttribute(
      "aria-sort",
      "descending",
    );
  }
  await page.getByRole("link", { name: "10 filas por página" }).click();
  await expect(page).toHaveURL(/filas=10/);
  await expect(
    page.getByRole("status").filter({ hasText: /^Filas 1 a \d+ de \d+$/ }),
  ).toBeVisible();

  // La confiabilidad son botones (ADR-0039): aria-pressed dice cuál está aplicada, y filtran.
  const group = page.getByRole("group", { name: "Confiabilidad" });
  await expect(group.getByRole("button", { name: /^Todas/ })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await group.getByRole("button", { name: /^Incompleto/ }).click();
  await expect(page).toHaveURL(/confiabilidad=incomplete/);
  await expect(page).toHaveURL(/filas=10/);
  await expect(group.getByRole("button", { name: /^Incompleto/ })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await expect(group.getByRole("button", { name: /^Todas/ })).toHaveAttribute(
    "aria-pressed",
    "false",
  );
  await expect(page.getByRole("link", { name: "Lasaña bolognesa" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Ravioles de ricota" })).toHaveCount(0);
  // El filtro activo es una etiqueta que se quita.
  await expect(page.getByRole("link", { name: /Confiabilidad: Incompleto/ })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  // El detalle vuelve a la misma lista, con el filtro y las filas.
  await page.getByRole("link", { name: "Lasaña bolognesa" }).first().click();
  await page.getByRole("link", { name: "Volver a costos" }).click();
  await expect(page).toHaveURL(/confiabilidad=incomplete/);
  await expect(page).toHaveURL(/filas=10/);

  // «Ver cuáles» de un indicador filtra igual que su botón.
  await page.goto("/costos");
  const stale = kpi(page, "Desactualizadas");
  if ((await stale.getByRole("link", { name: /Ver cuáles/ }).count()) > 0) {
    await stale.getByRole("link", { name: /Ver cuáles/ }).click();
    await expect(page).toHaveURL(/confiabilidad=stale/);
    await expect(group.getByRole("button", { name: /^Desactualizado/ })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
  }
});

// Los indicadores siguen la regla única de lo que falta, con los números de la pantalla (como inicio.spec.ts).
test("los indicadores de costos siguen la regla del rojo", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  const upToDate = await readCount(kpi(page, "Recetas al día"));
  const stale = await readCount(kpi(page, "Desactualizadas"));
  const incomplete = await readCount(kpi(page, "Incompletas"));
  expect(stale.total).toBe(upToDate.total);
  const checks: [string, number, number][] = [
    ["Recetas al día", upToDate.total - upToDate.value, upToDate.total],
    ["Desactualizadas", stale.value, stale.total],
    ["Incompletas", incomplete.value, incomplete.total],
  ];
  for (const [label, missing, total] of checks) {
    const badge = kpi(page, label).locator('[data-slot="badge"]');
    await expect(badge, label).toHaveClass(new RegExp(STATUS_CLASS[ruleStatus(missing, total)]));
  }
  // «Mayor costo por porción» lleva al detalle de ese plato.
  const top = kpi(page, "Mayor costo por porción");
  await expect(top).toContainText("$");
  await top.getByRole("link").click();
  await expect(page).toHaveURL(/\/costos\/[0-9a-f-]{36}/);
  await expect(kpi(page, "Por porción")).toContainText("$");
});

// Pantalla sin scroll (ADR-0048), en los tres tamaños de computadora: la lista y el detalle entran enteros; la tabla y
// la línea por línea se desplazan adentro. Con el Controller (solo lee costos).
test("lista y detalle entran sin scroll en la computadora", async ({ page }, info) => {
  test.skip(info.project.name !== "computadora", "las medidas son de la computadora");
  test.setTimeout(150_000);
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  await expect(page.getByLabel("Local activo").locator("visible=true")).toHaveValue(PASTAS_CENTRO);
  for (const [width, height] of SIZES) {
    await page.setViewportSize({ width, height });
    await page.goto("/costos");
    const table = page.getByRole("region", { name: "Costos de las recetas (tabla)" });
    await expect(table).toBeVisible();
    await noVerticalScroll(page);
    await noHorizontalScroll(page);
    // Toda la tabla a la vista, sin desplazarse de costado.
    const sideways = await table.evaluate((el) => el.scrollWidth - el.clientWidth);
    expect(sideways, `${width} × ${height}`).toBeLessThanOrEqual(0);
    if (height === 843) await axe(page);
    // Con más filas que alto, la tabla se desplaza adentro y el encabezado queda fijo.
    const rows = await table.evaluate((el) => ({
      overflow: el.scrollHeight - el.clientHeight,
      sticky: getComputedStyle(el.querySelector("thead") as Element).position,
    }));
    expect(rows.sticky).toBe("sticky");
    if (width === 1440) expect(rows.overflow).toBeGreaterThan(0);

    await page.goto(`/costos/${RAVIOLES}`);
    await expect(page.getByRole("table", { name: "Costo de cada línea" })).toBeVisible();
    await noVerticalScroll(page);
    await noHorizontalScroll(page);
  }
  await page.goto(`/costos?confiabilidad=incomplete&q=lasa`);
  await page.getByRole("link", { name: "Lasaña bolognesa" }).first().click();
  await expect(page.getByText(/^Falta un dato:/)).toBeVisible();
  await noVerticalScroll(page);
});

// En el celular Costos es de consulta: tarjetas, scroll y controles de 44 px.
test("en el celular, tarjetas y controles grandes", async ({ page }, info) => {
  test.skip(info.project.name !== "celular", "es la vista del celular");
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  const cards = page.getByRole("list", { name: "Costos de las recetas" });
  await expect(cards.getByRole("listitem").first()).toBeVisible();
  await expect(page.getByRole("region", { name: "Costos de las recetas (tabla)" })).toBeHidden();
  for (const control of [
    page.getByRole("group", { name: "Confiabilidad" }).getByRole("button").first(),
    cards.getByRole("link").first(),
    page.getByLabel("Local activo").locator("visible=true"),
  ]) {
    const box = await control.boundingBox();
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
  }
  await noHorizontalScroll(page);
  await axe(page);
  await page.goto(`/costos/${RAVIOLES}`);
  await expect(lineRows(page, false).first()).toContainText("Salsa bolognesa");
  await noHorizontalScroll(page);
  await axe(page);
});
