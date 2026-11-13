// El Inicio en una pantalla (ADR-0045; tablero de calidad, ADR-0033). En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice } from "./helpers";

test.describe.configure({ timeout: 90_000 });

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noOverflow(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

// Sin scroll vertical: la página entera mide lo mismo que la ventana.
async function noVerticalScroll(page: Page) {
  const { scroll, client } = await page.evaluate(() => {
    const d = document.scrollingElement ?? document.documentElement;
    return { scroll: d.scrollHeight, client: d.clientHeight };
  });
  expect(scroll).toBeLessThanOrEqual(client);
}

const PASTAS_CENTRO = "00000000-0000-4000-8000-000000000201";
const PASTAS_NORTE = "00000000-0000-4000-8000-000000000202";
const PARRILLA_CENTRO = "00000000-0000-4000-8000-000000000203";
const CAFE_CENTRO = "00000000-0000-4000-8000-000000000204";
const SHORTCUTS = ["Recetas", "Materias primas", "Costos", "Aprobaciones", "Calidad", "Reportes"];

type Status = "ok" | "warn" | "bad" | "none";

// La regla única (decisión de Soy, 2026-11-13), escrita de nuevo acá a propósito: la prueba no usa el código que prueba.
function expected(missing: number, total: number): Status {
  if (total === 0) return "none";
  if (missing === 0) return "ok";
  return missing * 2 > total ? "bad" : "warn";
}

// Cada KPI a la vista: lee «N» y «de M» de la pantalla y controla que el estado sea el de la regla. Los números del
// seed cambian con las pruebas que corren antes; la regla no. Devuelve los estados encontrados.
async function kpisFollowRule(page: Page): Promise<Status[]> {
  const cards = page.locator('[data-slot="kpi"]');
  await expect(cards.first()).toBeVisible();
  const found: Status[] = [];
  for (const card of await cards.all()) {
    const text = await card.innerText();
    const badge = card.locator('[data-slot="badge"]');
    const total = /de ([\d.]+)/.exec(text)?.[1];
    if (total === undefined) {
      // Sin denominador: «Sin datos» y la raya, nunca un número ni un %.
      await expect(badge).toHaveText("Sin datos");
      await expect(badge).toHaveClass(/bg-none/);
      await expect(card).not.toContainText(/%|Completo|Al día/);
      found.push("none");
      continue;
    }
    // El número grande: el primer tramo del valor del KPI.
    const value = (await card.locator("p.text-kpi > span").first().innerText()).trim();
    const missing = Number(value.replace(/\./g, ""));
    const status = expected(missing, Number(total.replace(/\./g, "")));
    await expect(badge).toHaveClass(new RegExp(`bg-${status}\\b`));
    await expect(badge).toHaveText(
      status === "ok" ? "Completo" : missing === 1 ? "Falta 1" : `Faltan ${value}`,
    );
    found.push(status);
  }
  return found;
}

// Espera el tablero entero: el aviso y la tarjeta de locales llegan en streaming.
async function boardReady(page: Page) {
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(4);
  await expect(page.getByRole("region", { name: "Requiere atención" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Costo confiable por local" })).toBeVisible();
}

test("el Controller ve el tablero en una pantalla y llega a lo que falta", async ({
  page,
}, testInfo) => {
  const desk = testInfo.project.name === "computadora";
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Demo Pastas Centro");
  await expect(page.getByText(/^Datos al momento: .* · \d+ recetas?/)).toBeVisible();
  await boardReady(page);
  // Sin «+ Nueva receta» ni el título largo de antes.
  await expect(page.getByRole("link", { name: /Nueva receta/ })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /Nueva receta/ })).toHaveCount(0);
  await expect(page.getByText("¿Qué tan completo y confiable está nuestro recetario?")).toHaveCount(
    0,
  );
  // Cada indicador sigue la regla (los bordes exactos, como la mitad justa, los prueba Vitest).
  await kpisFollowRule(page);
  await axe(page);
  await noOverflow(page);

  if (desk) {
    // Entra entero, sin scroll, en las tres pantallas de computadora.
    for (const size of [
      { width: 1440, height: 900 },
      { width: 1600, height: 900 },
      { width: 1920, height: 1080 },
    ]) {
      await page.setViewportSize(size);
      await page.reload();
      await boardReady(page);
      await noVerticalScroll(page);
    }
    // Con cada lista del ranking (unas tienen más filas que otras) sigue entrando en 1440 × 900.
    await page.setViewportSize({ width: 1440, height: 900 });
    for (const ranking of ["porcion", "materias-primas", "precio", "mas-usado"]) {
      await page.goto(`/?local=${PASTAS_CENTRO}&ranking=${ranking}`);
      await boardReady(page);
      await noVerticalScroll(page);
    }
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto(`/?local=${PASTAS_CENTRO}`);
    await boardReady(page);

    // Las tres tarjetas del medio.
    await expect(
      page.getByRole("heading", { name: "¿Qué tan confiable es el costo?" }),
    ).toBeVisible();
    await expect(
      page.getByRole("list", { name: "Recetas en cada estado del costo" }),
    ).toContainText("Completo y verificado");
    await expect(page.getByRole("heading", { name: "Tareas pendientes" })).toBeVisible();

    // Un solo ranking con botones: cambia de lista y aria-pressed acompaña.
    const ranking = page.getByRole("region", { name: "Ranking" });
    const portion = ranking.getByRole("button", { name: "Mayor costo por porción" });
    const used = ranking.getByRole("button", { name: "Lo más usado" });
    await expect(portion).toHaveAttribute("aria-pressed", "true");
    await expect(used).toHaveAttribute("aria-pressed", "false");
    await expect(ranking.getByRole("list", { name: "Mayor costo por porción" })).toBeVisible();
    await used.click();
    await expect(used).toHaveAttribute("aria-pressed", "true");
    await expect(portion).toHaveAttribute("aria-pressed", "false");
    await expect(ranking.getByRole("list", { name: "Lo más usado" })).toBeVisible();
    await expect(ranking.getByRole("list", { name: "Mayor costo por porción" })).toHaveCount(0);
    // La elección queda en la dirección: al volver, sigue elegida.
    await expect(page).toHaveURL(/ranking=mas-usado/);
    await page.reload();
    await expect(
      page.getByRole("region", { name: "Ranking" }).getByRole("button", { name: "Lo más usado" }),
    ).toHaveAttribute("aria-pressed", "true");
    await axe(page);

    // Los 6 accesos, en orden, cada uno con su estado en palabras. Usuarios, Roles e Historial ya no están.
    const nav = page.getByRole("navigation", { name: "Accesos" });
    const links = nav.getByRole("link");
    await expect(links).toHaveCount(6);
    for (const [i, name] of SHORTCUTS.entries()) {
      await expect(links.nth(i)).toContainText(name);
    }
    await expect(links.nth(0)).toContainText(/\d+ sin aprobar|Al día|Sin datos/);
    await expect(links.nth(1)).toContainText(/\d+ sin precio|Al día|Sin datos/);
    await expect(links.nth(2)).toContainText(/\d+ por corregir|Al día|Sin datos/);
    await expect(links.nth(3)).toContainText(/Al día|esperan? tu decisión/);
    await expect(links.nth(4)).toContainText(/datos? por completar/);
    await expect(links.nth(5)).toContainText("Informes");
    await expect(nav.getByRole("link", { name: /Usuarios|Roles|Historial/ })).toHaveCount(0);
    await links.nth(4).click();
    await expect(page).toHaveURL(/\/calidad/);
    await page.goBack();
    await expect(page.getByRole("navigation", { name: "Accesos" })).toBeVisible();
  } else {
    // En el celular se supervisa: sin ranking, sin confiabilidad y sin accesos grandes.
    await expect(page.getByRole("navigation", { name: "Accesos" })).toHaveCount(0);
    await expect(page.getByRole("region", { name: "Ranking" })).toHaveCount(0);
    await expect(
      page.getByRole("heading", { name: "¿Qué tan confiable es el costo?" }),
    ).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "Para decidir" })).toBeVisible();
    // Todo lo que se toca mide 44 px o más.
    const small = await page.evaluate(() =>
      [...document.querySelectorAll("main a, main button, main summary")]
        .filter((el) => (el as HTMLElement).offsetParent !== null)
        .map((el) => ({ text: el.textContent?.trim(), h: el.getBoundingClientRect().height }))
        .filter((el) => el.h < 44),
    );
    expect(small).toEqual([]);
    for (const width of [360, 640, 768]) {
      await page.setViewportSize({ width, height: 900 });
      await noOverflow(page);
    }
  }

  // La acción principal, en el encabezado.
  await page.getByRole("link", { name: "Ver qué falta corregir" }).click();
  await expect(page).toHaveURL(/\/calidad\?local=/);
});

// Decisión de Soy (2026-11-13): si falta más de la mitad, el indicador pasa a Crítico. La misma regla en Calidad.
test("si falta más de la mitad, el indicador es Crítico en el Inicio y en Calidad", async ({
  page,
}) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  // Los cuatro locales del seed: cada indicador sigue la regla, y alguno tiene que llegar a Crítico (en el seed, el
  // costo por corregir de Pastas Norte pasa la mitad).
  const found: string[] = [];
  for (const id of [PASTAS_CENTRO, PASTAS_NORTE, PARRILLA_CENTRO, CAFE_CENTRO]) {
    await page.goto(`/?local=${id}`);
    await expect(page.locator('[data-slot="kpi"]')).toHaveCount(4);
    found.push(...(await kpisFollowRule(page)));
  }
  expect(found).toContain("bad");
  await axe(page);

  // Calidad: la misma regla en la lista de indicadores («N de M» cumplidos).
  await page.goto(`/calidad?local=${PASTAS_NORTE}`);
  const rows = page.getByRole("listitem").filter({ has: page.locator('[data-slot="badge"]') });
  await expect(rows.first()).toBeVisible();
  const bad: string[] = [];
  for (const row of await rows.all()) {
    const match = /(\d+) de (\d+)/.exec(await row.innerText());
    if (!match) continue;
    const [done, total] = [Number(match[1]), Number(match[2])];
    const status = expected(total - done, total);
    if (status === "none") continue;
    await expect(row.locator('[data-slot="badge"]')).toHaveClass(new RegExp(`bg-${status}\\b`));
    if (status === "bad") bad.push(match[0]);
  }
  expect(bad.length).toBeGreaterThan(0);
});

// Métricas confiables: sin nada que medir, «Sin datos», nunca 0 % ni «Al día». Un local de una marca nueva no tiene
// ninguna receta (los de una marca existente heredan las de la marca).
test("un local sin recetas dice «Sin datos» en sus indicadores", async ({ page }, testInfo) => {
  test.setTimeout(150_000);
  const n = `${testInfo.project.name === "celular" ? "C" : "D"}${Date.now() % 1_000_000}`;
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/configuracion/marcas");
  await page.locator("summary", { hasText: "Nueva marca" }).click();
  await page.locator("#marca-nombre").fill(`Marca sin recetas ${n}`);
  await page.locator("#marca-codigo").fill(`i-${n}`);
  await page.locator("#marca-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear marca" }).click();
  await expect(page.getByRole("heading", { name: `Marca sin recetas ${n}` })).toBeVisible();
  await page.locator("summary", { hasText: "Nuevo local" }).click();
  await page.locator("#local-nuevo-nombre").fill(`Local sin recetas ${n}`);
  await page.locator("#local-nuevo-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear local" }).click();
  await expect(page.getByRole("heading", { name: `Local sin recetas ${n}` })).toBeVisible();
  const id = /\/configuracion\/locales\/([0-9a-f-]{36})/.exec(page.url())?.[1];
  expect(id).toBeTruthy();
  const back = page.url();

  await page.goto(`/?local=${id}`);
  await expect(page.getByRole("heading", { level: 1 })).toContainText(`Local sin recetas ${n}`);
  const kpis = page.locator('[data-slot="kpi"]');
  await expect(kpis.first()).toBeVisible();
  // Cada indicador sigue la regla: sin recetas, «Sin datos» y la raya, nunca «Al día» ni un %. En una corrida completa
  // el local puede recibir recetas de todo el grupo que crean otras pruebas: entonces vale la regla con sus números.
  const states = await kpisFollowRule(page);
  if (testInfo.project.name === "computadora") {
    const recipes = page.getByRole("navigation", { name: "Accesos" }).getByRole("link").first();
    if (states[0] === "none") await expect(recipes).toContainText("Sin datos");
    await expect(recipes).not.toContainText(states[0] === "ok" ? "sin aprobar" : "Al día");
  }
  await axe(page);

  // Cerrar el local y la marca: quedan en la historia, pero ya no operan (otras pruebas cuentan los locales abiertos).
  await page.goto(back);
  await page.locator("summary", { hasText: "Editar los datos del local" }).click();
  await page.locator("#local-editar-estado").selectOption("inactive");
  await page.locator("#local-editar-motivo").fill("Cierre al terminar la prueba automática");
  await page.getByRole("button", { name: "Guardar local" }).click();
  // El estado del local (el aviso de guardado puede irse antes de que se lo mire).
  await expect(page.getByText("Cerrado", { exact: true }).first()).toBeVisible();
  await page.getByRole("link", { name: `Volver a Marca sin recetas ${n}` }).click();
  await page.locator("summary", { hasText: "Editar la marca" }).click();
  await page.locator("#marca-editar-estado").selectOption("inactive");
  await page.locator("#marca-editar-motivo").fill("Cierre al terminar la prueba automática");
  await page.getByRole("button", { name: "Guardar marca" }).click();
  await expect(
    notice(page)
      .filter({ hasText: "Marca guardada." })
      .or(page.getByText("Inactiva", { exact: true }))
      .first(),
  ).toBeVisible();
});

test("el Jefe de Cocina ve lo técnico, sin costos", async ({ page }, testInfo) => {
  await login(page, "jefecocina@ejemplo.test");
  await expect(page.locator('[data-slot="kpi"]').first()).toBeVisible();
  if (testInfo.project.name === "computadora") {
    const ranking = page.getByRole("region", { name: "Ranking" });
    await expect(ranking.getByRole("list", { name: "Lo más usado" })).toBeVisible();
    await expect(ranking.getByRole("button", { name: "Mayor costo por porción" })).toHaveCount(0);
    const nav = page.getByRole("navigation", { name: "Accesos" });
    await expect(nav.getByRole("link", { name: /Costos/ })).toHaveCount(0);
  }
  await expect(page.getByRole("heading", { name: "¿Qué tan confiable es el costo?" })).toHaveCount(
    0,
  );
  await expect(page.getByText("Mayor costo por porción")).toHaveCount(0);
  await expect(page.getByText("Materias primas sin precio")).toHaveCount(0);
  await axe(page);
});

test("la Cocinera ve el Inicio simple, sin el tablero", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await expect(page.getByRole("heading", { name: "Tus roles" })).toBeVisible();
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(0);
  await expect(page.getByRole("region", { name: "Ranking" })).toHaveCount(0);
  await expect(page.getByRole("navigation", { name: "Accesos" })).toBeVisible();
  await axe(page);
});

test("sin elegir local, se pide elegir uno", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await expect(page.getByText("Elegí un local para ver cómo está su recetario.")).toBeVisible();
  await expect(page.getByRole("list", { name: "Tus locales" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Ver qué falta corregir" })).toHaveCount(0);
  await axe(page);
  await page.getByRole("link", { name: "Comparar los locales" }).click();
  await expect(page.getByText("Cómo está cada local")).toBeVisible();
});

// Rediseño (ADR-0036): el local del Inicio sale del selector global de la barra de arriba.
test("el selector global de local cambia el tablero del Inicio", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/");
  await page.getByLabel("Local activo").selectOption({ label: "Demo Pastas Centro · PASTAS" });
  await page.getByRole("button", { name: "Cambiar" }).click();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Demo Pastas Centro");
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(4);
  await expect(page.getByRole("link", { name: "Ver qué falta corregir" })).toBeVisible();
  // Vuelve a "Todos mis locales" para no cambiar otras pruebas.
  await page.getByLabel("Local activo").selectOption({ label: "Todos mis locales" });
  await page.getByRole("button", { name: "Cambiar" }).click();
  await expect(page.getByText("Elegí un local para ver cómo está su recetario.")).toBeVisible();
});
