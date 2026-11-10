// Costos de recetas (ADR-0032, PR 2): quien ve costos sabe cuánto cuesta cada receta en su local, qué la
// encarece y qué le falta. El Chef ve costos sin ver precios; Compras y la Cocinera no ven costos. En celular
// y computadora, con axe. Los números son los de docs/guias/costos-demo.md.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, openSection } from "./helpers";

// El servidor de desarrollo compila cada pantalla la primera vez: en celular a veces pasa de 30 s.
test.describe.configure({ timeout: 90_000 });

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

const uuid = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const PASTAS_CENTRO = uuid(201);
const RAVIOLES = uuid(1108);

test("el Controller ve cuánto cuesta cada receta y qué la encarece", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/costos");
  await expect(page.getByText("Elegí un local para ver sus costos.")).toBeVisible();

  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: "Demo Pastas Centro" })).toBeVisible();
  await expect(page.getByText("Última actualización:")).toBeVisible();
  await expect(page.locator('[data-slot="kpi"]')).toHaveCount(3);
  await noHorizontalScroll(page);
  await axe(page);

  // Los Ravioles, con la bolognesa adentro.
  await page.goto(`/costos/${RAVIOLES}?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("heading", { name: "Ravioles de ricota" })).toBeVisible();
  await expect(page.getByText("Última actualización:")).toBeVisible();
  await expect(page.locator('[data-slot="kpi"]').first()).toContainText("4.506,27");
  await expect(page.locator('[data-slot="kpi"]').nth(1)).toContainText("5.452,58");
  await expect(page.getByText("Desactualizado").first()).toBeVisible();
  const lines = page.getByRole("list", { name: "Costo de cada línea" });
  await expect(lines.getByRole("listitem").first()).toContainText("Salsa bolognesa");
  await expect(lines.getByRole("listitem").first()).toContainText("3.045,25");
  await expect(page.getByRole("list", { name: "Historia del costo" })).toBeVisible();
  // El Controller no trabaja recetas: no tiene el enlace a la ficha.
  await expect(page.getByRole("link", { name: "Ver la receta" })).toHaveCount(0);
  await noHorizontalScroll(page);
  await axe(page);

  // Una receta incompleta dice qué falta.
  await page.goto(`/costos?local=${PASTAS_CENTRO}&confiabilidad=incomplete&q=lasa`);
  await page.getByRole("link", { name: "Lasaña bolognesa" }).first().click();
  await expect(page.getByText("La preparación está incompleta")).toBeVisible();
  await expect(page.getByText(/el total queda vacío/)).toBeVisible();
  await axe(page);
});

test("el Controller recibe el aviso de cambio de costo", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(
    page.getByRole("heading", { name: /Avisos de recetas, costos y rendimientos/ }),
  ).toBeVisible();
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
  await expect(page.getByRole("heading", { name: "Demo Pastas Centro" })).toBeVisible();
  await expect(page.getByText("Demo Parrilla Centro")).toHaveCount(0);
  await page.goto(`/costos/${RAVIOLES}`);
  await expect(page.getByRole("heading", { name: "Ravioles de ricota" })).toBeVisible();
});

test("el Chef ve el costo por línea, sin precios", async ({ page }) => {
  await login(page, "chef@ejemplo.test");
  await page.goto(`/costos/${RAVIOLES}?local=${PASTAS_CENTRO}`);
  await expect(page.getByRole("list", { name: "Costo de cada línea" })).toBeVisible();
  await expect(page.getByText("3.045,25").first()).toBeVisible();
  // Ni el envase, ni el producto, ni el proveedor.
  await expect(page.getByText(/el envase|bolsa de|Factura/)).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Ver la receta" })).toHaveAttribute(
    "href",
    `/recetas/${RAVIOLES}`,
  );
  await page.goto(`/recetas/${RAVIOLES}`);

  // En la ficha de la receta, con su local elegido.
  await page.getByLabel("Local activo").selectOption(PASTAS_CENTRO);
  await page.getByRole("button", { name: "Cambiar" }).click();
  // Cambiar de local recarga la pantalla: la primera vez tarda. El costo está en su pestaña.
  await expect(page.getByLabel("Local activo")).toHaveValue(PASTAS_CENTRO, { timeout: 20_000 });
  await openSection(page, "Costos");
  await expect(page.getByRole("heading", { name: "Costo en Demo Pastas Centro" })).toBeVisible({
    timeout: 20_000,
  });
  await expect(page.getByText(/4\.506,27/).first()).toBeVisible();
  await axe(page);
  await page.goto("/recetas");
  await expect(page.getByText(/Costo sin IVA en Demo Pastas Centro/).first()).toBeAttached();
  await axe(page);
  await page.getByLabel("Local activo").selectOption({ label: "Todos mis locales" });
  await page.getByRole("button", { name: "Cambiar" }).click();
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
  await page.locator("summary", { hasText: "Proponer precio" }).click();
  await page.locator("#precio-producto").selectOption({ index: 1 });
  await page.locator("#precio-lugar").selectOption({ label: "Todo el grupo (Grupo Demo)" });
  await page.locator("#precio-envase").fill(price);
  await page.locator("#precio-motivo").fill("Precio de prueba automática");
  await page.getByRole("button", { name: "Proponer precio" }).click();
  await expect(notice(page).filter({ hasText: "Precio propuesto." })).toBeVisible();
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

// Rediseño (ADR-0036): la lista se ordena por columna (en la base: todas las recetas, no solo la página),
// elige cuántas filas ver, filtra por pestañas y el detalle vuelve a la misma lista.
test("la lista de costos se ordena, se pagina y vuelve con sus filtros", async ({ page }, info) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto(`/costos?local=${PASTAS_CENTRO}`);
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
  await page
    .getByRole("navigation", { name: "Confiabilidad" })
    .getByRole("link", { name: /Incompleto/ })
    .click();
  await expect(page).toHaveURL(/confiabilidad=incomplete/);
  await expect(page.getByRole("link", { name: "Lasaña bolognesa" })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);
  // El detalle vuelve a la misma lista, con el filtro y las filas.
  await page.getByRole("link", { name: "Lasaña bolognesa" }).first().click();
  await page.getByRole("link", { name: "Volver a costos" }).click();
  await expect(page).toHaveURL(/confiabilidad=incomplete/);
  await expect(page).toHaveURL(/filas=10/);
});
