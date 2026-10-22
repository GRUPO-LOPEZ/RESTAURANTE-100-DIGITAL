// Compuerta de cierre de la Fase 1 (sección 12 del documento de Soy): cada punto que Soy marca en la
// demo, recorrido en pantalla en celular y computadora, con axe en cada pantalla nueva.
import { readFileSync } from "node:fs";
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { fillLogin, login, logout, menuLink, notice, openAction } from "./helpers";

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

function localRows(page: Page) {
  return page.getByRole("table", { name: "Personas por local" }).getByRole("rowheader");
}

test.describe("quién ve qué", () => {
  test("Dirección ve los 4 locales; el gerente de un local, solo el suyo", async ({ page }) => {
    test.setTimeout(120_000);
    await login(page, "direccion@ejemplo.test", { mfa: true });
    await page.goto("/usuarios?local=todos");
    await expect(localRows(page)).toHaveCount(4);
    await noHorizontalScroll(page);
    await logout(page);

    await login(page, "gerente@ejemplo.test", { mfa: true });
    await page.goto("/usuarios?local=todos");
    await expect(localRows(page)).toHaveCount(1);
    await expect(localRows(page).first()).toContainText("Demo Pastas Centro");
    await page.goto("/usuarios/lista");
    await axe(page);
    await noHorizontalScroll(page);
    await logout(page);
  });

  test("el cocinero ve el documento de ensayo vigente sin el costo; Controller lo ve con costo", async ({
    page,
  }) => {
    test.setTimeout(90_000);
    await login(page, "cocinero@ejemplo.test");
    await (await menuLink(page, "Ensayo")).click();
    const doc = page.getByRole("listitem").filter({ hasText: "Salsa de tomate de la casa" });
    await expect(doc).toBeVisible();
    await expect(doc.getByText("no lo podés ver con tu rol")).toBeVisible();
    await expect(page.getByText("1520")).toHaveCount(0);
    // El borrador del jefe de cocina no lo ve.
    await expect(page.getByText("Ñoquis de papa")).toHaveCount(0);
    await axe(page);
    await logout(page);

    await login(page, "controller@ejemplo.test", { mfa: true });
    await page.goto("/ensayo");
    await expect(
      page
        .getByRole("listitem")
        .filter({ hasText: "Salsa de tomate de la casa" })
        .getByText(/1\.520,50/),
    ).toBeVisible();
    await logout(page);
  });
});

test.describe("aprobaciones e historial", () => {
  test("se pide un cambio de la matriz, quien lo pidió no lo aprueba y otra persona sí; el historial muestra a las dos", async ({
    page,
  }, testInfo) => {
    test.setTimeout(150_000);
    // Un permiso distinto en cada proyecto, para que no se pisen.
    const [roleCode, roleName, permission] =
      testInfo.project.name === "celular"
        ? ["cook", "Cocinero / Operador", "approvals.view"]
        : ["head_chef", "Jefe de Cocina", "audit.export"];
    const reason = `Prueba automática de la matriz (${testInfo.project.name})`;

    await login(page, "superadmin@ejemplo.test", { mfa: true });
    await (await menuLink(page, "Roles y permisos")).click();
    await page.getByLabel("Rol").selectOption(roleCode);
    await page.getByRole("button", { name: "Ver sus permisos" }).click();
    await expect(page.getByRole("heading", { level: 2, name: roleName })).toBeVisible();
    await axe(page);
    const row = page.getByRole("listitem").filter({ hasText: permission });
    await row.getByText("Pedir que se lo den").click();
    await row.getByLabel("Motivo").fill(reason);
    await row.getByRole("button", { name: "Pedir darlo" }).click();
    await expect(row.getByText(/Pedido de dar pendiente/)).toBeVisible();

    // Quien lo pidió no lo puede aprobar.
    await page.goto("/aprobaciones");
    const mine = page.getByRole("listitem").filter({ hasText: reason }).first();
    await expect(mine.getByText("La tiene que decidir otra persona con permiso.")).toBeVisible();
    await expect(mine.getByRole("button", { name: "Aprobar" })).toHaveCount(0);
    await axe(page);
    await logout(page);

    // Dirección General lo aprueba: ve el antes y el después.
    await login(page, "direccion2@ejemplo.test", { mfa: true });
    await page.goto("/aprobaciones");
    const pending = page
      .getByRole("listitem")
      .filter({ hasText: reason })
      .filter({ hasText: "Pendiente" })
      .first();
    await expect(pending.getByText(/Antes: No → Después: Sí/)).toBeVisible();
    await pending.getByLabel("Comentario").fill("De acuerdo");
    await pending.getByRole("button", { name: "Aprobar" }).click();
    await expect(
      page
        .getByRole("listitem")
        .filter({ hasText: reason })
        .first()
        .getByText("Aprobada", { exact: true }),
    ).toBeVisible();

    // En el historial figuran las dos personas, con fecha y motivo.
    await page.goto("/historial?modulo=approvals&local=todos");
    await expect(
      page
        .getByRole("listitem")
        .filter({ hasText: reason })
        .filter({ hasText: "Sofía Admin" })
        .first(),
    ).toBeVisible();
    await expect(
      page
        .getByRole("listitem")
        .filter({ hasText: "Aprobación" })
        .filter({ hasText: "Delia Dirección" })
        .first(),
    ).toBeVisible();
    await axe(page);
    await logout(page);
  });

  test("el auditor exporta el historial en CSV", async ({ page }) => {
    await login(page, "auditor@ejemplo.test");
    await page.goto("/historial?modulo=org&local=todos");
    const download = page.waitForEvent("download");
    await page.getByRole("link", { name: "Exportar (CSV)" }).click();
    const file = await (await download).path();
    const csv = readFileSync(file, "utf8");
    expect(csv.split("\r\n")[0]).toContain('"Fecha","Persona","Rol","Acción"');
    expect(csv.split("\r\n").length).toBeGreaterThan(2);
    await logout(page);
  });
});

test.describe("cuentas", () => {
  test("suspender corta el acceso al instante; levantarla, sin aprobación, lo devuelve", async ({
    page,
  }, testInfo) => {
    test.setTimeout(120_000);
    const email = `e2e-pausa-${testInfo.project.name}@ejemplo.test`;
    await login(page, email);
    await logout(page);

    await login(page, "gerente@ejemplo.test", { mfa: true });
    await page.goto(`/usuarios/lista?q=${encodeURIComponent(email)}&local=todos`);
    await page
      .getByRole("link", { name: /Prueba Pausa/ })
      .first()
      .click();
    await expect(page.getByRole("heading", { level: 2, name: /Prueba Pausa/ })).toBeVisible();
    await expect(page.getByText("Último acceso")).toBeVisible();
    await axe(page);
    await openAction(page, "Suspender…");
    await page.getByLabel("Motivo para suspender").fill("Prueba automática: licencia");
    await page.getByRole("button", { name: "Suspender la cuenta" }).click();
    // Al suspenderse, la ficha cambia: ahora ofrece levantar la suspensión.
    await expect(page.locator("summary", { hasText: "Levantar la suspensión…" })).toBeVisible();
    await expect(page.getByText("Suspendida", { exact: true }).first()).toBeVisible();
    await logout(page);

    await fillLogin(page, email);
    await expect(notice(page)).toContainText("no puede ingresar");

    await login(page, "gerente@ejemplo.test", { mfa: true });
    await page.goto(`/usuarios/lista?q=${encodeURIComponent(email)}&local=todos`);
    await page
      .getByRole("link", { name: /Prueba Pausa/ })
      .first()
      .click();
    await openAction(page, "Levantar la suspensión…");
    await page.getByLabel("Motivo para levantar la suspensión").fill("Prueba automática: volvió");
    await page.getByRole("button", { name: "Levantar la suspensión" }).click();
    await expect(page.locator("summary", { hasText: "Suspender…" })).toBeVisible();
    await logout(page);

    await login(page, email);
    await logout(page);
  });
});
