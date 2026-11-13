// Panel de control de la estructura (ADR-0031; respuesta 2 de Soy, ADR-0030): el Superadministrador da
// de alta una marca, una razón social y un local con su razón social y un área; la Directora de Marca
// crea locales de su marca sin elegir la razón social; el Gerente edita los datos de su local sin
// cerrarlo; la Cocinera no ve el panel. En celular y computadora, con axe. Datos ficticios.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice } from "./helpers";

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

// Cerrar el local creado: queda en la historia, pero ya no opera (otras pruebas cuentan los locales abiertos).
async function closeRestaurant(page: Page) {
  await page.locator("summary", { hasText: "Editar los datos del local" }).click();
  await page.locator("#local-editar-estado").selectOption("inactive");
  await page.locator("#local-editar-motivo").fill("Cierre al terminar la prueba automática");
  await page.getByRole("button", { name: "Guardar local" }).click();
  await expect(notice(page).filter({ hasText: "Local guardado." })).toBeVisible();
  await expect(page.getByText("Cerrado", { exact: true }).first()).toBeVisible();
}

// Un sufijo distinto por proyecto y corrida: los nombres y códigos son únicos en el grupo.
function suffix(projectName: string) {
  return `${projectName === "celular" ? "C" : "D"}${Date.now() % 1_000_000}`;
}

test("el Superadministrador da de alta una marca, una razón social y un local con su área", async ({
  page,
}, testInfo) => {
  test.setTimeout(120_000);
  const n = suffix(testInfo.project.name);
  // CUIT ficticio de 11 números, distinto en cada corrida.
  const cuit = `30${String(Date.now()).slice(-8)}${testInfo.project.name === "celular" ? 1 : 2}`;

  await login(page, "superadmin@ejemplo.test", { mfa: true });
  // En el celular el menú está detrás de «Menú»: se entra directo.
  await page.goto("/configuracion");
  await expect(page.getByRole("heading", { level: 1, name: "Panel de control" })).toBeVisible();
  await noHorizontalScroll(page);
  await axe(page);

  // La razón social, con el CUIT escrito con guiones.
  await page.getByRole("link", { name: /Razones sociales/ }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Razones sociales" })).toBeVisible();
  await page.locator("summary", { hasText: "Nueva razón social" }).click();
  await page.locator("#razon-nueva-nombre").fill(`Prueba ${n} S.R.L. (ficticia)`);
  await page
    .locator("#razon-nueva-cuit")
    .fill(`${cuit.slice(0, 2)}-${cuit.slice(2, 10)}-${cuit.slice(10)}`);
  await page.locator("#razon-nueva-iva").selectOption("registered");
  await page.locator("#razon-nueva-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear razón social" }).click();
  await expect(notice(page).filter({ hasText: "Razón social creada" })).toBeVisible();
  await axe(page);

  // La marca.
  await page.goto("/configuracion/marcas");
  await page.locator("summary", { hasText: "Nueva marca" }).click();
  await page.locator("#marca-nombre").fill(`Marca de prueba ${n}`);
  await page.locator("#marca-codigo").fill(`p-${n}`);
  await page.locator("#marca-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear marca" }).click();
  await expect(page.getByRole("heading", { name: `Marca de prueba ${n}` })).toBeVisible();
  await expect(page.getByText(`Código P-${n}`)).toBeVisible();

  // El local, con su tipo y su razón social en el mismo paso.
  await page.locator("summary", { hasText: "Nuevo local" }).click();
  await page.locator("#local-nuevo-nombre").fill(`Local de prueba ${n}`);
  await page.locator("#local-nuevo-tipo").selectOption("central_kitchen");
  await page.locator("#local-nuevo-razon-social").selectOption({
    label: `Prueba ${n} S.R.L. (ficticia) · ${cuit.slice(0, 2)}-${cuit.slice(2, 10)}-${cuit.slice(10)} · Responsable inscripto`,
  });
  await page.locator("#local-nuevo-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear local" }).click();
  await expect(page.getByRole("heading", { name: `Local de prueba ${n}` })).toBeVisible();
  await expect(page.getByText(`Prueba ${n} S.R.L. (ficticia)`).first()).toBeVisible();
  await expect(page.getByText(/Cocina central/).first()).toBeVisible();

  // Un área.
  await page.locator("summary", { hasText: "Nueva área" }).click();
  await page.locator("#area-nueva-nombre").fill("Salón");
  await page.locator("#area-nueva-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear área" }).click();
  await expect(page.getByRole("list", { name: "Áreas" })).toContainText("Salón");
  await noHorizontalScroll(page);
  await axe(page);

  // Cerrar el local y la marca de prueba.
  await closeRestaurant(page);
  await page.getByRole("link", { name: `Volver a Marca de prueba ${n}` }).click();
  await page.locator("summary", { hasText: "Editar la marca" }).click();
  await page.locator("#marca-editar-estado").selectOption("inactive");
  await page.locator("#marca-editar-motivo").fill("Cierre al terminar la prueba automática");
  await page.getByRole("button", { name: "Guardar marca" }).click();
  await expect(notice(page).filter({ hasText: "Marca guardada." })).toBeVisible();
});

test("la Directora de Marca crea un local de su marca sin elegir la razón social", async ({
  page,
}, testInfo) => {
  test.setTimeout(90_000);
  const n = suffix(testInfo.project.name);
  await login(page, "director@ejemplo.test", { mfa: true });
  await page.goto("/configuracion/marcas");
  await expect(page.locator("summary", { hasText: "Nueva marca" })).toHaveCount(0);
  await page.getByRole("link", { name: "Demo Pastas", exact: true }).click();
  await page.locator("summary", { hasText: "Nuevo local" }).click();
  await expect(page.locator("#local-nuevo-razon-social")).toHaveCount(0);
  await page.locator("#local-nuevo-nombre").fill(`Pastas de prueba ${n}`);
  await page.locator("#local-nuevo-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear local" }).click();
  await expect(page.getByRole("heading", { name: `Pastas de prueba ${n}` })).toBeVisible();
  await expect(
    page.getByText("Este local todavía no tiene razón social: su costo sin IVA queda incompleto."),
  ).toBeVisible();
  await axe(page);
  await closeRestaurant(page);
});

test("el Gerente edita los datos de su local, pero no lo cierra", async ({ page }) => {
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto("/configuracion/locales/00000000-0000-4000-8000-000000000201");
  await expect(page.getByRole("heading", { name: "Demo Pastas Centro" })).toBeVisible();
  // Ve la razón social de su local, nunca un aviso falso de que no tiene.
  await expect(page.getByText("Demo Gastronomía S.R.L. (ficticia)").first()).toBeVisible();
  await expect(page.getByText(/todavía no tiene razón social/)).toHaveCount(0);
  await page.locator("summary", { hasText: "Editar los datos del local" }).click();
  await expect(page.locator("#local-editar-estado")).toHaveCount(0);
  await expect(page.locator("#local-editar-tipo")).toHaveCount(0);
  await page.locator("#local-editar-telefono").fill("011 4555-0000");
  await page.locator("#local-editar-motivo").fill("Teléfono nuevo (prueba automática)");
  await page.getByRole("button", { name: "Guardar local" }).click();
  await expect(notice(page)).toContainText("Local guardado.");
  await expect(page.getByText("011 4555-0000").first()).toBeVisible();
});

test("la Cocinera no ve el panel de control", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await expect(page.getByRole("link", { name: "Panel de control" })).toHaveCount(0);
  await page.goto("/configuracion");
  await expect(page.getByRole("heading", { level: 1, name: /^Hola, / })).toBeVisible();
});
