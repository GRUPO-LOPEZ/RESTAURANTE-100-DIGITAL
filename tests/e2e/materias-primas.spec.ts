// Materias primas (Fase 2, etapa 2.1 A): quién ve y quién carga el catálogo, en celular y
// computadora, con axe en cada pantalla nueva.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, menuLink, notice, openAction } from "./helpers";

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

test("Compras busca por alias, crea una materia prima y la ve en su ficha", async ({
  page,
}, testInfo) => {
  await login(page, "compras@ejemplo.test");
  await (await menuLink(page, "Materias primas")).click();
  await expect(page.getByRole("heading", { level: 1, name: "Materias primas" })).toBeVisible();
  // Las 50 del seed más las que crean otras corridas de esta misma prueba.
  await expect(page.getByRole("heading", { name: /^[\d.]+ materias primas$/ })).toBeVisible();
  await expect(page.getByRole("link", { name: "Aceite de girasol" }).first()).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  await page.screenshot({ path: testInfo.outputPath("lista.png"), fullPage: true });

  // "muzz" es un alias de la mozzarella. En el celular los filtros empiezan plegados.
  // Next guarda oculta la pantalla anterior, que también puede tener filtros.
  const filters = page.locator("summary:visible", { hasText: "Filtros" });
  if (!(await filters.evaluate((el) => (el.parentElement as HTMLDetailsElement).open)))
    await filters.click();
  await page.getByLabel("Buscar").fill("muzz");
  await page.getByRole("button", { name: "Filtrar" }).click();
  await expect(page.getByRole("heading", { name: "1 materia prima" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Mozzarella" }).first()).toBeVisible();

  await page.getByRole("link", { name: "Nueva materia prima" }).click();
  await expect(page).toHaveURL(/\/materias-primas\/nueva$/);
  // Hasta que termina la transición, la lista anterior todavía está en la página. Solo en el contenido: la
  // barra superior tiene su propia búsqueda global (ADR-0036).
  await expect(page.getByRole("main").getByRole("search")).toHaveCount(0);
  await expect(page.getByRole("heading", { level: 1, name: "Nueva materia prima" })).toBeVisible();
  await axe(page);
  const code = `E2E-${testInfo.project.name === "celular" ? "C" : "P"}-${Date.now() % 1_000_000_000}`;
  await page.getByLabel("Código").fill(code);
  await page.getByLabel("Nombre").fill(`Rúcula de prueba ${code}`);
  // Next guarda la lista anterior oculta, con su filtro "Categoría": getByRole solo mira lo visible.
  await page
    .getByRole("combobox", { name: "Categoría" })
    .selectOption({ label: "Verduras y frutas" });
  await page.getByLabel("Se usa en recetas en").selectOption("g");
  await page.getByLabel("Motivo").fill("Prueba automática del catálogo");
  await page.getByRole("button", { name: "Crear materia prima" }).click();

  await expect(page).toHaveURL(/\/materias-primas\/[0-9a-f-]{36}$/);
  await expect(page.getByRole("heading", { name: `Rúcula de prueba ${code}` })).toBeVisible();
  await expect(page.getByText(code, { exact: true })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  // Next guarda ocultos el alta y la lista: si un id se repitiera, una etiqueta podría apuntar al
  // campo oculto y el visible quedaría sin nombre (axe no lo ve).
  const repeatedIds = await page.evaluate(() => {
    const ids = [...document.querySelectorAll("[id]")].map((el) => el.id);
    return ids.filter((id, i) => ids.indexOf(id) !== i);
  });
  expect(repeatedIds).toEqual([]);

  // Los otros nombres quedan guardados (en minúsculas) y se ven en la ficha. Un alias es de una
  // sola materia prima del grupo: cada corrida usa los suyos.
  const suffix = code.toLowerCase();
  await openAction(page, "Cambiar los otros nombres");
  await page.getByLabel("Otros nombres").fill(`Rucula ${suffix}, roqueta ${suffix}`);
  await page.locator("#mp-motivo-alias").fill("Nombres que usa la cocina");
  await page.getByRole("button", { name: "Guardar nombres" }).click();
  await expect(notice(page)).toContainText("Otros nombres guardados.");
  await expect(page.getByText(`roqueta ${suffix}, rucula ${suffix}`)).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("ficha.png"), fullPage: true });
});

test("un código repetido se rechaza con un mensaje en español", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas/nueva");
  await page.getByLabel("Código").fill("DEMO-ING-001");
  await page.getByLabel("Nombre").fill("Tomate repetido");
  await page
    .getByRole("combobox", { name: "Categoría" })
    .selectOption({ label: "Verduras y frutas" });
  await page.getByLabel("Se usa en recetas en").selectOption("g");
  await page.getByLabel("Motivo").fill("Prueba automática");
  await page.getByRole("button", { name: "Crear materia prima" }).click();
  await expect(notice(page)).toContainText(
    "Ya existe una materia prima con ese código en el grupo.",
  );
});

test("el Chef ve la ficha con sus alérgenos, sin poder editar", async ({ page }) => {
  await login(page, "chef@ejemplo.test");
  await page.goto("/materias-primas?q=mozzarella");
  await page.getByRole("link", { name: "Mozzarella" }).first().click();
  await expect(page.getByRole("heading", { name: "Mozzarella" })).toBeVisible();
  await expect(page.getByRole("list", { name: "Alérgenos" }).getByText("Contiene")).toBeVisible();
  await expect(page.getByText("La lista de alérgenos todavía no está validada")).toBeVisible();
  await expect(page.locator("summary", { hasText: "Editar datos" })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Nueva materia prima" })).toHaveCount(0);
});

test("el Cocinero no ve Materias primas y, si entra por la dirección, vuelve al inicio", async ({
  page,
}) => {
  await login(page, "cocinero@ejemplo.test");
  await expect(await menuLink(page, "Materias primas")).toHaveCount(0);
  await page.goto("/materias-primas");
  await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();
});
