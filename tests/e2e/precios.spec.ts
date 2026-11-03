// Precios (ADR-0029, PR 2): Compras propone un precio en la ficha y el Controller lo aprueba; una suba
// grande pasa a Dirección General; el Gerente ve el costo de su local con el precio heredado; el Chef no
// ve precios; Dirección cambia la configuración. En celular y computadora, con axe. Valores de prueba.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice } from "./helpers";

// El servidor de desarrollo compila cada pantalla la primera vez: en celular a veces pasa de 30 s.
test.describe.configure({ timeout: 60_000 });

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

const ingredient = (n: number) =>
  `/materias-primas/00000000-0000-4000-8000-${String(800 + n).padStart(12, "0")}`;

async function propose(page: Page, price: string) {
  await page.locator("summary", { hasText: "Proponer precio" }).click();
  await page.locator("#precio-lugar").selectOption({ label: "Todo el grupo (Grupo Demo)" });
  await page.locator("#precio-envase").fill(price);
  await page.locator("#precio-motivo").fill("Precio de prueba automática");
  await page.getByRole("button", { name: "Proponer precio" }).click();
  await expect(notice(page).filter({ hasText: "Precio propuesto." })).toBeVisible();
}

// La solicitud de esta materia prima en la bandeja (puede haber otras pendientes).
function request(page: Page, name: string) {
  return page
    .getByRole("listitem")
    .filter({ hasText: name })
    .filter({ has: page.getByRole("button", { name: "Aprobar" }) });
}

test("Compras propone, el Controller aprueba y una suba grande pasa a Dirección", async ({
  page,
}, testInfo) => {
  test.setTimeout(240_000);
  // Una materia prima sin precios del seed para cada proyecto: el primer precio no tiene referencia.
  const [n, name] =
    testInfo.project.name === "celular" ? [25, "Queso provolone"] : [28, "Harina 0000"];

  await login(page, "compras@ejemplo.test");
  await page.goto(ingredient(n));
  await expect(page.getByRole("heading", { name: "Precios" })).toBeVisible();
  await propose(page, "9000");
  await noHorizontalScroll(page);
  await axe(page);
  await logout(page);

  // El Controller lo aprueba: es el primer precio, alcanza con él.
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(request(page, name)).toContainText("Es el primer precio");
  await axe(page);
  await request(page, name).getByRole("button", { name: "Aprobar" }).click();
  // Al aprobarse, la tarjeta pasa a "Aprobada" (el formulario ya no hace falta).
  await expect(request(page, name)).toHaveCount(0);
  await page.goto(ingredient(n));
  await expect(page.getByRole("list", { name: "Precios vigentes" })).toContainText("9.000,00");
  await logout(page);

  // Una suba grande: el Controller la aprueba y pasa a Dirección General.
  await login(page, "compras@ejemplo.test");
  await page.goto(ingredient(n));
  await propose(page, "20000");
  await logout(page);
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(request(page, name)).toContainText("+122,22 %");
  await request(page, name).getByRole("button", { name: "Aprobar" }).click();
  await expect(request(page, name)).toHaveCount(0);
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: name })
      .filter({ hasText: "ahora la decide Dirección General" }),
  ).toBeVisible();
  await logout(page);

  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(request(page, name)).toContainText("Ya la aprobó el Controller");
  await request(page, name).getByRole("button", { name: "Aprobar" }).click();
  await page.goto(ingredient(n));
  await expect(page.getByRole("list", { name: "Precios vigentes" })).toContainText("20.000,00");
});

test("el Gerente ve el costo de su local, heredado de su marca", async ({ page }) => {
  // Tiene un solo local: no hay selector y la ficha usa ese.
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(ingredient(19));
  await expect(page.getByText("Costo en Demo Pastas Centro")).toBeVisible();
  await expect(page.getByText("Heredado de la marca")).toBeVisible();
  await expect(page.getByText(/por kg/).first()).toBeVisible();
  await axe(page);
});

test("el Chef no ve precios", async ({ page }) => {
  await login(page, "chef@ejemplo.test");
  await page.goto(ingredient(19));
  await expect(page.getByRole("heading", { name: "Mozzarella" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Precios" })).toHaveCount(0);
  await expect(page.getByText("36.000")).toHaveCount(0);
});

test("Dirección cambia la configuración de precios", async ({ page }) => {
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/configuracion");
  await page.getByRole("link", { name: /Configuración de precios/ }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Configuración de precios" }),
  ).toBeVisible();
  await axe(page);
  await page.locator("summary", { hasText: "Cambiar la configuración" }).click();
  await page.locator("#precios-hacia-atras").fill("45");
  await page.locator("#precios-motivo").fill("Prueba automática");
  await page.getByRole("button", { name: "Guardar configuración" }).click();
  await expect(
    notice(page).filter({ hasText: "Configuración de precios guardada." }),
  ).toBeVisible();
  await expect(page.getByText("Hace 45 días")).toBeVisible();
  // Vuelve a 30 días para no cambiar otras pruebas.
  await page.locator("#precios-hacia-atras").fill("30");
  await page.locator("#precios-motivo").fill("Vuelve al valor de prueba");
  await page.getByRole("button", { name: "Guardar configuración" }).click();
  await expect(page.getByText("Hace 30 días")).toBeVisible();
  await noHorizontalScroll(page);
});
