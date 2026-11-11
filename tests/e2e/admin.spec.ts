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

const RAVIOLES = "00000000-0000-4000-8000-000000001108";
const PASTAS_CENTRO = "00000000-0000-4000-8000-000000000201";

// Una tabla en la computadora y tarjetas en el celular (rediseño, ADR-0036): solo las visibles.
function localRows(page: Page) {
  return page
    .getByRole("table", { name: "Personas por local" })
    .locator("tbody tr:visible")
    .or(page.getByRole("list", { name: "Personas por local" }).getByRole("listitem"));
}

// Los cambios del Historial, en tabla o en tarjetas.
function historyEntries(page: Page) {
  return page
    .getByRole("table", { name: "Historial de cambios" })
    .getByRole("row")
    .or(page.getByRole("list", { name: "Historial de cambios" }).getByRole("listitem"));
}

test.describe("quién ve qué", () => {
  test("Dirección ve los 4 locales; el gerente de un local, solo el suyo", async ({ page }) => {
    test.setTimeout(120_000);
    await login(page, "direccion@ejemplo.test", { mfa: true });
    await page.goto("/usuarios?local=todos");
    // Los 4 locales del seed. Por nombre y no por cantidad: la prueba del panel de control
    // (panel-estructura.spec.ts) crea locales en la misma base, y Dirección los ve todos (ADR-0031).
    for (const name of [
      "Demo Pastas Centro",
      "Demo Pastas Norte",
      "Demo Parrilla Centro",
      "Demo Café Centro",
    ])
      await expect(localRows(page).filter({ hasText: name })).toHaveCount(1);
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

  test("el cocinero ve la receta vigente sin el costo; Controller la ve con costo", async ({
    page,
  }) => {
    test.setTimeout(90_000);
    await login(page, "cocinero@ejemplo.test");
    // El Inicio le deja a mano sus recetas.
    await expect(page.getByRole("main").getByRole("link", { name: /Recetas/ })).toBeVisible();
    await (await menuLink(page, "Recetas")).click();
    await expect(page.getByRole("link", { name: "Ravioles de ricota" }).first()).toBeVisible();
    // El borrador no lo ve: se busca por su nombre, porque la lista va por páginas.
    await page.goto("/recetas?q=Risotto");
    await expect(page.getByText("Risotto de hongos")).toHaveCount(0);
    await page.goto(`/recetas/${RAVIOLES}/cocina`);
    await expect(page.getByRole("heading", { name: "Ravioles de ricota" })).toBeVisible();
    await expect(page.locator("main")).not.toContainText(/\$|costo|precio/i);
    await axe(page);
    await logout(page);

    await login(page, "controller@ejemplo.test", { mfa: true });
    await page.goto(`/costos/${RAVIOLES}?local=${PASTAS_CENTRO}`);
    await expect(page.locator('[data-slot="kpi"]').first()).toContainText("4.506,27");
    await logout(page);
  });
});

test.describe("aprobaciones e historial", () => {
  // Prueba 12 del Módulo 0. Antes usaba un cambio de la matriz, que desde ADR-0039 se aplica sin aprobación: ahora
  // la Directora de Marca da un rol que aprueba (Chef Ejecutivo), y eso sí espera a otra persona. Dirección lo
  // rechaza: la decisión queda con identidad, fecha y comentario, y nadie gana permisos en la corrida.
  test("se pide dar un rol que aprueba, quien lo pidió no lo decide y otra persona sí; el historial muestra a las dos", async ({
    page,
  }, testInfo) => {
    test.setTimeout(150_000);
    // Una persona distinta en cada proyecto, para que no se pisen.
    const [personId, personName] =
      testInfo.project.name === "celular"
        ? ["00000000-0000-4000-8000-000000000409", "Lucía Operadora"]
        : ["00000000-0000-4000-8000-000000000406", "Julián Cocina"];
    const reason = `Prueba automática de una aprobación (${testInfo.project.name})`;

    await login(page, "director@ejemplo.test", { mfa: true });
    await page.goto(`/usuarios/${personId}?seccion=roles`);
    await expect(page.getByRole("heading", { level: 1, name: personName })).toBeVisible();
    await page.getByLabel("Rol", { exact: true }).selectOption("executive_chef");
    await page.getByLabel("Dónde", { exact: true }).selectOption({ label: "Marca · Demo Pastas" });
    await page.getByLabel("Motivo para dar el rol").fill(reason);
    await page.getByRole("button", { name: "Dar el rol" }).click();
    await expect(notice(page)).toContainText("pendiente");
    await axe(page);

    // Quien lo pidió no lo puede decidir.
    await page.goto("/aprobaciones");
    const mine = page.getByRole("listitem").filter({ hasText: reason }).first();
    await expect(mine.getByText("La tiene que decidir otra persona con permiso.")).toBeVisible();
    await expect(mine.getByRole("button", { name: "Aprobar" })).toHaveCount(0);
    await axe(page);
    await logout(page);

    // Dirección General lo decide: lo rechaza con un comentario.
    await login(page, "direccion2@ejemplo.test", { mfa: true });
    await page.goto("/aprobaciones");
    const pending = page
      .getByRole("listitem")
      .filter({ hasText: reason })
      .filter({ hasText: "Pendiente" })
      .first();
    await pending.getByLabel("Comentario").fill("Todavía no");
    await pending.getByRole("button", { name: "Rechazar" }).click();
    await expect(
      page
        .getByRole("listitem")
        .filter({ hasText: reason })
        .first()
        .getByText("Rechazada", { exact: true }),
    ).toBeVisible();

    // En el historial figuran las dos personas, con fecha y motivo.
    await page.goto("/historial?modulo=approvals&local=todos");
    await expect(
      historyEntries(page).filter({ hasText: reason }).filter({ hasText: "Marta Marca" }).first(),
    ).toBeVisible();
    await expect(historyEntries(page).filter({ hasText: "Delia Dirección" }).first()).toBeVisible();
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
    await expect(page.getByRole("heading", { level: 1, name: /Prueba Pausa/ })).toBeVisible();
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

// Rediseño, PR 4 (ADR-0036; decisiones de Joaco del 2026-11-10): local de la barra de arriba («Todos mis
// locales» = todo el alcance), paginación con cursor, fichas por pestañas y «Salir» dentro de «Menú».
test.describe("administración con el sistema nuevo", () => {
  test("Personas: el local de arriba, las pestañas de estado y la paginación con cursor", async ({
    page,
  }) => {
    test.setTimeout(120_000);
    await login(page, "direccion@ejemplo.test", { mfa: true });
    // Con «Todos mis locales», todo el alcance, y la marca como filtro.
    await page.goto("/usuarios/lista?filas=10");
    await expect(page.getByRole("heading", { name: "Personas de todo tu alcance" })).toBeVisible();
    await expect(page.getByRole("main").getByRole("combobox", { name: "Marca" })).toBeVisible();
    await expect(
      page.getByRole("status").filter({ hasText: /^Mostrando 10 personas$/ }),
    ).toBeVisible();
    await axe(page);
    await noHorizontalScroll(page);
    // La tanda siguiente, y de vuelta al principio.
    await page
      .getByRole("navigation", { name: "Páginas" })
      .getByRole("link", { name: "Siguientes" })
      .click();
    await expect(page).toHaveURL(/despues_id=/);
    await expect(
      page.getByRole("status").filter({ hasText: /^Mostrando 10 personas siguientes$/ }),
    ).toBeVisible();
    await page
      .getByRole("navigation", { name: "Páginas" })
      .getByRole("link", { name: "Volver al principio" })
      .click();
    await expect(page).not.toHaveURL(/despues_id=/);
    await expect(page).toHaveURL(/filas=10/);
    // Una pestaña de estado.
    const tabs = page.getByRole("navigation", { name: "Estado de las cuentas" });
    await tabs.getByRole("link", { name: "Activas", exact: true }).click();
    await expect(page).toHaveURL(/estado=active/);
    await expect(tabs.getByRole("link", { name: "Activas", exact: true })).toHaveAttribute(
      "aria-current",
      "page",
    );
    // Con un local, sus personas, sin el filtro de marca.
    await page.goto(`/usuarios/lista?local=${PASTAS_CENTRO}`);
    await expect(
      page.getByRole("heading", { name: "Personas de Demo Pastas Centro" }),
    ).toBeVisible();
    await expect(page.getByRole("main").getByRole("combobox", { name: "Marca" })).toHaveCount(0);
    await logout(page);
  });

  test("la ficha de una persona va por pestañas y vuelve a la lista con sus filtros", async ({
    page,
  }) => {
    // Ingreso con doble verificación y varias pantallas: el mismo margen que las otras pruebas de Dirección.
    test.setTimeout(90_000);
    await login(page, "direccion@ejemplo.test", { mfa: true });
    await page.goto("/usuarios/lista?q=compras&local=todos");
    await page
      .getByRole("link", { name: /Compras/ })
      .first()
      .click();
    await expect(page.getByRole("navigation", { name: "Secciones de la persona" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Datos", exact: true })).toBeVisible();
    await page
      .getByRole("navigation", { name: "Secciones de la persona" })
      .getByRole("link", { name: "Roles", exact: true })
      .click();
    await expect(page).toHaveURL(/seccion=roles/);
    await expect(page.getByRole("heading", { name: "Roles", exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Datos", exact: true })).toHaveCount(0);
    await axe(page);
    await page.getByRole("link", { name: "Volver a personas" }).click();
    await expect(page).toHaveURL(/q=compras/);
    await logout(page);
  });

  test("Historial: el local de arriba y los cambios más antiguos", async ({ page }) => {
    test.setTimeout(120_000);
    await login(page, "auditor@ejemplo.test");
    await page.goto("/historial?filas=10&local=todos");
    await expect(page.getByRole("heading", { name: "Cambios en todo tu alcance" })).toBeVisible();
    await expect(
      page.getByRole("status").filter({ hasText: /^Mostrando 10 cambios$/ }),
    ).toBeVisible();
    await axe(page);
    await noHorizontalScroll(page);
    await page
      .getByRole("navigation", { name: "Páginas" })
      .getByRole("link", { name: "Más antiguos" })
      .click();
    await expect(page).toHaveURL(/antes=\d+/);
    await expect(historyEntries(page).first()).toBeVisible();
    await page.goto(`/historial?local=${PASTAS_CENTRO}`);
    await expect(
      page.getByRole("heading", { name: "Cambios en Demo Pastas Centro" }),
    ).toBeVisible();
    await expect(page.getByRole("main").getByRole("combobox", { name: "Marca" })).toHaveCount(0);
    await logout(page);
  });

  test("en el celular, «Salir» está dentro de «Menú»", async ({ page }, testInfo) => {
    test.skip(
      testInfo.project.name !== "celular",
      "Solo en el celular: en la computadora va en la barra lateral.",
    );
    await login(page, "compras@ejemplo.test");
    await expect(page.getByRole("button", { name: /^Salir/ })).toHaveCount(0);
    await page.locator("summary:visible", { hasText: "Menú" }).click();
    const menu = page.getByRole("navigation", { name: "Menú principal" });
    await expect(menu.getByRole("link", { name: "Mi cuenta" })).toBeVisible();
    await expect(menu.getByRole("button", { name: /^Salir/ })).toBeVisible();
    await axe(page);
    await menu.getByRole("button", { name: /^Salir/ }).click();
    await expect(page).toHaveURL(/\/ingresar$/);
  });
});
