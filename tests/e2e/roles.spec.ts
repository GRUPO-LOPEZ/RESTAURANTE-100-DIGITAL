// Matriz de permisos con edición directa (ADR-0039, pedido de Soy): toggles de un clic, contador, guardar en lote
// con motivo, confirmación de sensibles, tooltip con mouse y teclado, sin acceso sin permissions.manage y la
// primera columna fija. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

function cell(page: Page, role: string, permission: string) {
  return page.getByRole("button", { name: new RegExp(`^${role}: ${permission}`) });
}

// El contador de la barra de abajo (el aviso de «Se guardó» también es un role=status).
const counter = (page: Page) =>
  page.getByRole("status").filter({ hasText: /^(\d+ cambios? sin guardar|Sin cambios)$/ });
// Sin cambios no hay nada para guardar (en el celular, la barra ni se muestra).
const nothingToSave = (page: Page) =>
  expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);

test("el Superadministrador cambia una celda, el contador sube y baja, y guarda con motivo", async ({
  page,
}, testInfo) => {
  test.setTimeout(90_000);
  // Una celda distinta en cada proyecto, para que no se pisen.
  const [role, permission] =
    testInfo.project.name === "celular"
      ? ["Cocinero / Operador", "Ver el catálogo"]
      : ["Jefe de Cocina", "Importar desde Excel"];
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/roles");
  await expect(page.getByRole("table", { name: /Matriz de permisos/ })).toBeVisible();
  await axe(page);

  const target = cell(page, role, permission);
  await expect(target).toHaveAttribute("aria-pressed", "false");
  await target.click();
  await expect(counter(page)).toHaveText("1 cambio sin guardar");
  await expect(target).toHaveAttribute("aria-pressed", "true");
  // Volver al valor original lo saca del contador.
  await target.click();
  await nothingToSave(page);

  await target.click();
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(page.getByText("Escribí el motivo.")).toBeVisible();
  await page.getByLabel("Motivo").fill(`Prueba de la matriz (${testInfo.project.name})`);
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(page.getByText("Se guardó 1 cambio.")).toBeVisible();
  await nothingToSave(page);

  await page.reload();
  await expect(cell(page, role, permission)).toHaveAttribute("aria-pressed", "true");

  // Se deja como estaba, para no cambiar las demás pruebas.
  await cell(page, role, permission).click();
  await page.getByLabel("Motivo").fill("Vuelve como estaba");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(page.getByText("Se guardó 1 cambio.")).toBeVisible();
  await expect(cell(page, role, permission)).toHaveAttribute("aria-pressed", "false");
});

test("dar un permiso sensible pide confirmación y queda pendiente de Dirección; los roles propios no se cambian", async ({
  page,
}, testInfo) => {
  const role = testInfo.project.name === "celular" ? "Cocinero / Operador" : "Jefe de Cocina";
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/roles");
  await cell(page, role, "Ver el historial").click();
  await page.getByLabel("Motivo").fill(`Prueba de sensibles (${testInfo.project.name})`);
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog).toContainText("Vas a dar 1 permiso sensible: no se aplica al guardar");
  await dialog.getByRole("button", { name: "Cancelar" }).click();
  await expect(counter(page)).toHaveText("1 cambio sin guardar");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await page.getByRole("alertdialog").getByRole("button", { name: "Sí, guardar" }).click();
  await expect(
    page.getByText("1 permiso sensible queda pendiente hasta que lo apruebe Dirección General."),
  ).toBeVisible();
  // La celda queda «pendiente»: no se puede tocar hasta que Dirección decida.
  await expect(cell(page, role, "Ver el historial")).toHaveCount(0);
  await expect(
    page.getByText(`${role}: Ver el historial, sensible: pendiente de aprobación`),
  ).toHaveCount(1);
  // La columna del Superadministrador es suya: se ve, pero no tiene botones.
  await expect(page.getByRole("button", { name: /^Superadministrador: / })).toHaveCount(0);
  await axe(page);
});

test("el tooltip del permiso se abre con el teclado y muestra la descripción y el código", async ({
  page,
}) => {
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/roles");
  const name = page.getByRole("rowheader").getByText("Ver personas", { exact: true });
  await name.focus();
  const tip = page.getByRole("tooltip");
  await expect(tip).toContainText("Ver personas y sus roles dentro del alcance.");
  await expect(tip).toContainText("users.view");
});

test("sin permiso para cambiar la matriz no se entra a Roles (y la base rechaza la llamada directa: 260)", async ({
  page,
}) => {
  await login(page, "auditor@ejemplo.test");
  await page.goto("/roles");
  await expect(page).not.toHaveURL(/\/roles/);
  await expect(page.getByRole("table", { name: /Matriz de permisos/ })).toHaveCount(0);
});

test("la primera columna queda fija y la tabla se recorre de costado", async ({ page }, info) => {
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/roles");
  const first = page.getByRole("columnheader", { name: "Permiso", exact: true });
  expect(await first.evaluate((el) => getComputedStyle(el).position)).toBe("sticky");
  // La página no se corre de costado: lo que se desplaza es la tabla.
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
  if (info.project.name !== "computadora") return;
  // En la computadora (desde 1440 px) entran todos los roles, sin correr la tabla.
  await page.setViewportSize({ width: 1440, height: 900 });
  const table = page.getByRole("table", { name: /Matriz de permisos/ });
  const hidden = await table.evaluate((el) => {
    const box = el.parentElement;
    return box ? box.scrollWidth - box.clientWidth : 0;
  });
  expect(hidden).toBeLessThanOrEqual(0);
});
