// Materias primas (Fase 2, etapa 2.1 A): quién ve y quién carga el catálogo, en celular y
// computadora, con axe en cada pantalla nueva.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, menuLink, notice, openAction, openSection } from "./helpers";

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

  // "muzz" es un alias de la mozzarella. La barra de filtros se aplica sola (sin botón "Filtrar") y el
  // filtro queda como etiqueta que se puede quitar. Solo en el contenido: la barra superior tiene su
  // propia búsqueda global (ADR-0036).
  await page.getByRole("main").getByRole("searchbox", { name: "Buscar" }).fill("muzz");
  await expect(page).toHaveURL(/[?&]q=muzz/);
  await expect(page.getByRole("heading", { name: "1 materia prima" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Mozzarella", exact: true }).first()).toBeVisible();
  await expect(page.getByText("Buscar: «muzz»")).toBeVisible();

  // El alta simple va en un modal corto (ADR-0036), con el mismo formulario de /materias-primas/nueva.
  await page.getByRole("link", { name: "Nueva materia prima" }).click();
  const dialog = page.getByRole("dialog", { name: "Nueva materia prima" });
  await expect(dialog).toBeVisible();
  await axe(page);
  const run = `E2E-${testInfo.project.name === "celular" ? "C" : "P"}-${Date.now() % 1_000_000_000}`;
  // El código no se escribe: sale del rubro (ADR-0041).
  await dialog.locator("#mp-alta-categoria").selectOption({ label: "Verduras y frutas" });
  await expect(dialog.locator("#mp-alta-codigo")).toHaveValue(/^MPR-VER-\d{4}$/);
  await dialog.locator("#mp-alta-nombre").fill(`Rúcula de prueba ${run}`);
  await dialog.locator("#mp-alta-unidad").selectOption("g");
  await dialog.locator("#mp-alta-motivo").fill("Prueba automática del catálogo");
  await dialog.getByRole("button", { name: "Crear materia prima" }).click();

  await expect(page).toHaveURL(/\/materias-primas\/[0-9a-f-]{36}(\?aviso=codigo&previsto=.*)?$/);
  await expect(page.getByRole("heading", { name: `Rúcula de prueba ${run}` })).toBeVisible();
  // El encabezado de la ficha: el código que armó la base y el rubro.
  await expect(page.getByText(/^MPR-VER-\d{4} · Verduras y frutas$/)).toBeVisible();
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
  const suffix = run.toLowerCase();
  await openAction(page, "Cambiar los otros nombres");
  await page.getByLabel("Otros nombres").fill(`Rucula ${suffix}, roqueta ${suffix}`);
  await page.locator("#mp-motivo-alias").fill("Nombres que usa la cocina");
  await page.getByRole("button", { name: "Guardar nombres" }).click();
  await expect(notice(page)).toContainText("Otros nombres guardados.");
  await expect(page.getByText(`roqueta ${suffix}, rucula ${suffix}`)).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("ficha.png"), fullPage: true });
});

test("el código no se escribe y un nombre repetido se rechaza en español", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas/nueva");
  // El código es de solo lectura: lo arma la base con el rubro (ADR-0041).
  await expect(page.locator("#mp-alta-codigo")).toHaveAttribute("readonly", "");
  await expect(page.locator("#mp-alta-codigo")).toHaveValue("Se arma al elegir el rubro");
  await page.getByRole("combobox", { name: "Rubro" }).selectOption({ label: "Verduras y frutas" });
  await expect(page.locator("#mp-alta-codigo")).toHaveValue(/^MPR-VER-\d{4}$/);
  await page.getByLabel("Nombre").fill("TOMATE PERITA");
  await page.getByLabel("Se usa en recetas en").selectOption("g");
  await page.getByLabel("Motivo").fill("Prueba automática");
  await page.getByRole("button", { name: "Crear materia prima" }).click();
  await expect(notice(page)).toContainText(
    "Ya existe una materia prima con ese nombre en el grupo.",
  );
});

test("el Chef ve la ficha con sus alérgenos, sin poder editar", async ({ page }) => {
  await login(page, "chef@ejemplo.test");
  await page.goto("/materias-primas?q=mozzarella");
  await page.getByRole("link", { name: "Mozzarella", exact: true }).first().click();
  await expect(page.getByRole("heading", { name: "Mozzarella" })).toBeVisible();
  await expect(page.locator("summary", { hasText: "Editar datos" })).toHaveCount(0);
  await openSection(page, "Alérgenos", "materia prima");
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

// Rediseño (ADR-0036): la lista se ordena por columna (en la base, no solo la página), se pagina de a 15
// y filtra por pestañas de estado.
test("la lista de materias primas se ordena, se pagina y filtra por estado", async ({
  page,
}, info) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas");
  await expect(page.getByRole("status").filter({ hasText: /^Filas 1 a 15 de \d+$/ })).toBeVisible();
  if (info.project.name === "computadora") {
    // Por nombre de entrada; un clic en Código ordena por código y otro lo invierte.
    await expect(page.getByRole("columnheader", { name: /Materia prima/ })).toHaveAttribute(
      "aria-sort",
      "ascending",
    );
    await page
      .getByRole("columnheader", { name: /Código/ })
      .getByRole("link")
      .click();
    await expect(page).toHaveURL(/orden=code/);
    await page
      .getByRole("columnheader", { name: /Código/ })
      .getByRole("link")
      .click();
    await expect(page).toHaveURL(/orden=-code/);
    await expect(page.getByRole("columnheader", { name: /Código/ })).toHaveAttribute(
      "aria-sort",
      "descending",
    );
  }
  await page
    .getByRole("navigation", { name: "Páginas" })
    .getByRole("link", { name: "Siguiente" })
    .click();
  await expect(page).toHaveURL(/pagina=2/);
  await expect(
    page.getByRole("status").filter({ hasText: /^Filas 16 a 30 de \d+$/ }),
  ).toBeVisible();

  // Una pestaña de estado vuelve a la primera página.
  const tabs = page.getByRole("navigation", { name: "Estado de las materias primas" });
  await tabs.getByRole("link", { name: "Activas", exact: true }).click();
  await expect(page).toHaveURL(/estado=active/);
  await expect(page).not.toHaveURL(/pagina=/);
  await expect(tabs.getByRole("link", { name: "Activas", exact: true })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await axe(page);
  await noHorizontalScroll(page);
});

// La ficha va por pestañas (?seccion=) y "Volver" regresa a la misma lista, con sus filtros.
test("la ficha se recorre por pestañas y vuelve a la lista con sus filtros", async ({
  page,
}, info) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas?q=mozzarella&estado=active");
  await page.getByRole("link", { name: "Mozzarella", exact: true }).first().click();
  await expect(page.getByRole("heading", { name: "Mozzarella" })).toBeVisible();
  // De entrada, Datos generales, con lo que se edita.
  await expect(page.getByRole("heading", { name: "Datos generales" })).toBeVisible();
  await expect(page.locator("summary", { hasText: "Editar datos" })).toBeVisible();

  await openSection(page, "Alérgenos", "materia prima");
  await expect(page).toHaveURL(/seccion=alergenos/);
  await expect(page.getByRole("list", { name: "Alérgenos" })).toBeVisible();
  // Lo de las otras pestañas no se carga.
  await expect(page.getByRole("heading", { name: "Datos generales" })).toHaveCount(0);
  await openSection(page, "Precios y compra", "materia prima");
  await expect(page).toHaveURL(/seccion=compra/);
  await expect(page.getByRole("heading", { name: "Cómo se compra" })).toBeVisible();
  await openSection(page, "Dónde se usa", "materia prima");
  await expect(page.getByRole("heading", { name: "Dónde se usa" })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  await page.screenshot({ path: info.outputPath("ficha-pestanas.png"), fullPage: true });

  // Una sección que no existe abre Datos generales; un "volver" de otro módulo no se respeta.
  const url = new URL(page.url());
  await page.goto(
    `${url.pathname}?seccion=nada&volver=${encodeURIComponent("https://ejemplo.test")}`,
  );
  await expect(page.getByRole("heading", { name: "Datos generales" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Volver a materias primas" })).toHaveAttribute(
    "href",
    "/materias-primas",
  );
  await page.goBack();

  await page.getByRole("link", { name: "Volver a materias primas" }).click();
  await expect(page).toHaveURL(/q=mozzarella/);
  await expect(page).toHaveURL(/estado=active/);
});

// Al cerrar el modal de alta, el foco vuelve al botón que lo abrió (WCAG 2.4.3, revisión de diseño del PR 3).
test("el modal de alta devuelve el foco al cerrarse", async ({ page }) => {
  await login(page, "compras@ejemplo.test");
  await page.goto("/materias-primas");
  const open = page.getByRole("link", { name: "Nueva materia prima" });
  await expect(open).toHaveAttribute("aria-haspopup", "dialog");
  await open.click();
  await expect(page.getByRole("dialog", { name: "Nueva materia prima" })).toBeVisible();
  // Con el modal abierto, Radix oculta el resto de la página a los lectores de pantalla: el botón se busca
  // por su atributo, no por su rol.
  await expect(
    page.locator("a[aria-haspopup=dialog]", { hasText: "Nueva materia prima" }),
  ).toHaveAttribute("aria-expanded", "true");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(open).toBeFocused();
});
