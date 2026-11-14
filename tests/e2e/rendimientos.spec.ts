// Rendimientos (Fase 2, etapa 2.1 B): un ensayo no cambia el estándar; el estándar se propone y
// lo aprueba un Chef de todo el grupo. En celular y computadora, con axe. Ficha única (ADR-0043): los ensayos y las
// propuestas se cargan en la computadora, en un panel; en el celular la ficha es de consulta.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, openSection, sheetRows } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function openIngredient(page: Page, name: string) {
  await page.goto(`/materias-primas?q=${encodeURIComponent(name)}`);
  await page.getByRole("link", { name, exact: true }).first().click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await openSection(page, "Mermas y rendimientos", "materia prima");
}

// La tabla de rendimientos por proceso, en su panel (ficha sin scroll, ADR-0046: la tarjeta muestra el resumen).
async function openYields(page: Page) {
  await page
    .getByRole("button", { name: "Ver todos los rendimientos por proceso" })
    .filter({ visible: true })
    .click();
  return page.getByRole("dialog", { name: "Rendimientos por proceso" });
}

// Los paneles de la ficha: «Registrar un ensayo» y «Proponer merma o rendimiento» (con «Rendimiento por proceso»).
async function openPanel(page: Page, name: string) {
  await page.getByRole("button", { name, exact: true }).click();
  return page.getByRole("dialog", { name });
}

test("el Jefe de Cocina registra un ensayo y el estándar no cambia", async ({ page, isMobile }) => {
  await login(page, "jefecocina@ejemplo.test");
  await openIngredient(page, "Tomate perita");
  await openYields(page);
  const pelado = sheetRows(page, "Rendimientos por proceso").filter({ hasText: "Pelado" }).first();
  await expect(pelado).toContainText("Limpieza 80,0 %");
  await axe(page);
  await page.keyboard.press("Escape");
  // En el celular, la ficha es de consulta: se lee el estándar, sin cargar.
  if (isMobile) {
    await expect(page.getByRole("button", { name: "Registrar un ensayo" })).toBeHidden();
    return;
  }

  await openPanel(page, "Registrar un ensayo");
  await page.locator("#mp-ren-proceso").selectOption({ label: "Pelado" });
  await page.getByLabel("Peso bruto (g)").fill("1000");
  await page.getByLabel("Peso limpio (g)").fill("700");
  await page.locator("#mp-motivo-ensayo").fill("Ensayo de prueba automática");
  await page.getByRole("button", { name: "Registrar ensayo" }).click();
  await expect(notice(page)).toContainText("Ensayo registrado. El estándar no cambia");
  await axe(page);
  await page.keyboard.press("Escape");
  // El estándar sigue en 80 %: el ensayo solo suma al promedio.
  await openYields(page);
  await expect(pelado).toContainText("Limpieza 80,0 %");
});

test("el Chef propone un estándar y el Chef del grupo lo aprueba", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === "celular", "Las propuestas se cargan en la computadora.");
  const cut = `prueba ${testInfo.project.name} ${Date.now() % 1_000_000}`;
  await login(page, "chef@ejemplo.test");
  await openIngredient(page, "Zanahoria");
  const panel = await openPanel(page, "Proponer merma o rendimiento");
  await panel.getByText("Rendimiento por proceso", { exact: true }).click();
  await page.locator("#mp-est-proceso").selectOption({ label: "Pelado" });
  await page.locator("#mp-est-corte").fill(cut);
  await page.locator("#mp-est-limpieza").fill("85");
  await page.locator("#mp-motivo-estandar").fill("Propuesta de prueba automática");
  await page.getByRole("button", { name: "Proponer estándar" }).click();
  await expect(notice(page)).toContainText(
    "Queda pendiente: lo tiene que aprobar un Chef de todo el grupo",
  );
  await page.keyboard.press("Escape");
  await openYields(page);
  const row = sheetRows(page, "Rendimientos por proceso").filter({ hasText: cut });
  await expect(row.getByText("Propuesta en revisión")).toBeVisible();
  await expect(row.getByText("Sin estándar aprobado")).toBeVisible();
  await page.keyboard.press("Escape");
  await logout(page);

  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/aprobaciones");
  const pending = page
    .getByRole("listitem")
    .filter({ hasText: "Propuesta de prueba automática" })
    .filter({ hasText: "Pendiente" })
    .filter({ hasText: cut })
    .first();
  await expect(pending).toContainText("Rendimiento estándar");
  await axe(page);
  await pending.getByRole("button", { name: "Aprobar" }).click();
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: cut })
      .first()
      .getByText("Aprobada", { exact: true }),
  ).toBeVisible();

  await openIngredient(page, "Zanahoria");
  await openYields(page);
  const approved = sheetRows(page, "Rendimientos por proceso").filter({ hasText: cut });
  await expect(approved).toContainText("Limpieza 85,0 %");
  await expect(approved.getByText("Propuesta en revisión")).toHaveCount(0);
});

// Aviso de rendimiento (ADR-0035): un ensayo que se desvía del estándar más que el umbral avisa al Chef.
test("un ensayo desviado avisa al Chef, que lo ve marcado en la ficha", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name === "celular", "Los ensayos se cargan en la computadora.");
  await login(page, "jefecocina@ejemplo.test");
  await openIngredient(page, "Tomate perita");
  await openPanel(page, "Registrar un ensayo");
  await page.locator("#mp-ren-proceso").selectOption({ label: "Pelado" });
  // 500 g limpios de 1000: 50 % contra el 80 % del estándar, un desvío de −37,5 %.
  await page.getByLabel("Peso bruto (g)").fill("1000");
  await page.getByLabel("Peso limpio (g)").fill("500");
  await page.locator("#mp-motivo-ensayo").fill("Ensayo desviado de prueba automática");
  await page.getByRole("button", { name: "Registrar ensayo" }).click();
  await expect(notice(page)).toContainText("Ensayo registrado");
  await page.keyboard.press("Escape");
  await logout(page);

  await login(page, "chef@ejemplo.test");
  await page.goto("/aprobaciones");
  const card = page
    .getByRole("listitem")
    .filter({ hasText: "Rendimiento desviado: Tomate perita" })
    .first();
  await expect(card).toContainText("Limpieza: 50 % contra 80 % del estándar (37,5 % menos).");
  await expect(card).toContainText("Avisa con un desvío de más de 10 %.");
  await axe(page);
  await card.getByRole("link", { name: /Ver la materia prima/ }).click();
  await expect(page.getByRole("heading", { name: "Tomate perita", exact: true })).toBeVisible();
  // El resumen de la tarjeta ya avisa que uno se desvía; el detalle, en el panel.
  await expect(page.getByText(/1 se desvía/).filter({ visible: true })).toBeVisible();
  await openYields(page);
  await expect(
    sheetRows(page, "Rendimientos por proceso")
      .getByText("El promedio se desvía más del 10 % del estándar")
      .first(),
  ).toBeVisible();
  await axe(page);
});

test("Dirección cambia el umbral del aviso de rendimiento", async ({ page }) => {
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/configuracion/precios");
  await expect(page.getByRole("heading", { name: "Aviso de rendimiento" })).toBeVisible();
  await page.locator("summary", { hasText: "Cambiar el aviso de rendimiento" }).click();
  await page.locator("#rendimiento-umbral").fill("12,5");
  await page.locator("#rendimiento-motivo").fill("Prueba automática: inflación del mes");
  await page.getByRole("button", { name: "Guardar el aviso" }).click();
  await expect(notice(page).filter({ hasText: "Aviso de rendimiento guardado." })).toBeVisible();
  await expect(page.getByText("Más de 12,5 %")).toBeVisible();
  await axe(page);
  // Vuelve a 10 % para no cambiar otras pruebas.
  await page.locator("#rendimiento-umbral").fill("10");
  await page.locator("#rendimiento-motivo").fill("Vuelve al valor de prueba");
  await page.getByRole("button", { name: "Guardar el aviso" }).click();
  await expect(page.getByText("Más de 10 %", { exact: true })).toBeVisible();
});
