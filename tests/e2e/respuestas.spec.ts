// Respuestas de Joaco a las preguntas abiertas de la Fase 1, en pantalla. ADR-0015: errores por
// campo antes de enviar (React Hook Form), quién ve el último acceso y quién aprueba una receta que
// otra persona mandó a revisión. ADR-0017: la baja de alguien de Dirección con aprobación. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, openAction, openSection, saveSheet } from "./helpers";

const COOK = "/usuarios/00000000-0000-4000-8000-000000000409";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

test("un formulario muestra el error debajo del campo antes de enviar", async ({ page }) => {
  test.setTimeout(90_000);
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(COOK);
  await openAction(page, "Suspender…");
  // La cocinera no es de Dirección ni Superadministrador: la acción es inmediata, sin aviso de aprobación.
  await expect(page.locator('[data-slot="approval-note"]')).toHaveCount(0);
  await page.getByRole("button", { name: "Suspender la cuenta" }).click();
  const reason = page.getByLabel("Motivo para suspender");
  await expect(reason).toHaveAttribute("aria-invalid", "true");
  await expect(page.getByText("Escribí el motivo.")).toBeVisible();
  await expect(reason).toBeFocused();
  // No se envió nada: la cuenta sigue activa y no hay aviso de la base.
  await expect(notice(page)).toHaveCount(0);
  await expect(page.getByText("Activa", { exact: true })).toBeVisible();
  await axe(page);
  // Al escribir el motivo, el error se va.
  await reason.fill("Prueba");
  await reason.blur();
  await expect(page.getByText("Escribí el motivo.")).toHaveCount(0);
  await logout(page);
});

test("el último acceso lo ve quien administra a la persona, no el auditor", async ({ page }) => {
  test.setTimeout(90_000);
  await login(page, "auditor@ejemplo.test");
  await page.goto(COOK);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.getByText("Último acceso", { exact: true })).toHaveCount(0);
  await expect(page.getByText("los ve quien administra a la persona")).toBeVisible();
  await axe(page);
  await logout(page);

  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(COOK);
  await expect(page.getByText("Último acceso", { exact: true })).toBeVisible();
  await expect(page.getByText("los ve quien administra a la persona")).toHaveCount(0);
  await logout(page);
});

test("quien mandó una receta a revisión no la aprueba: la aprueba otra persona", async ({
  page,
}, testInfo) => {
  test.setTimeout(150_000);
  // Una receta por proyecto: cada receta admite una sola versión abierta.
  const name = testInfo.project.name === "celular" ? "Spaghetti al fileto" : "Ñoquis de papa";

  await login(page, "chef@ejemplo.test");
  await page.goto(`/recetas?q=${encodeURIComponent(name)}`);
  // Exacto: el filtro aplicado también es un enlace (para quitarlo) y lleva el nombre buscado.
  await page.getByRole("link", { name, exact: true }).first().click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  // La receta puede venir con una versión abierta (un reintento): se sigue con esa.
  await openSection(page, "Versiones y aprobaciones");
  if ((await page.locator("summary", { hasText: "Retirar de revisión" }).count()) > 0) {
    await openAction(page, "Retirar de revisión");
    await page.locator('[id$="-motivo-retiro"]').fill("Reintento de la prueba");
    await page.getByRole("button", { name: "Retirar" }).click();
  }
  if ((await page.locator("summary", { hasText: "Crear una versión nueva" }).count()) > 0) {
    await openAction(page, "Crear una versión nueva");
    await page.locator('[id$="-motivo-version"]').fill("Prueba de revisión");
    await page.getByRole("button", { name: "Crear versión nueva" }).click();
  }
  await expect(page.getByText("Versión en preparación", { exact: false })).toBeVisible();
  // En la computadora se envía con la barra de la ficha (ADR-0042); en el celular, desde «Versiones».
  if (testInfo.project.name === "celular") {
    await openSection(page, "Versiones y aprobaciones");
    await openAction(page, "Pedir la revisión");
    await page.locator('[id$="-motivo-revision"]').fill("Lista para revisar");
    await page.getByRole("button", { name: "Pedir la revisión" }).click();
  } else {
    await saveSheet(page, "Lista para revisar", true);
  }
  await expect(notice(page).filter({ hasText: "Está en revisión" })).toBeVisible();
  await axe(page);
  const recipe = page.url();

  await page.goto("/aprobaciones");
  const request = () =>
    page.getByRole("listitem").filter({ hasText: name }).filter({ hasText: "Pendiente" }).first();
  await expect(request()).toBeVisible();
  await expect(request().getByRole("button", { name: "Aprobar" })).toHaveCount(0);
  await expect(request().getByText("La tiene que decidir otra persona con permiso.")).toBeVisible();
  await axe(page);
  await logout(page);

  await login(page, "director@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await request().getByRole("button", { name: "Aprobar" }).click();
  await expect(
    page.getByRole("listitem").filter({ hasText: name }).first().getByText("Aprobada", {
      exact: true,
    }),
  ).toBeVisible();
  // Aprobar es publicar: la versión nueva queda vigente.
  await page.goto(recipe);
  await expect(page.getByText(/Vigente v[2-9]/).first()).toBeVisible();
  await logout(page);
});

test("sin JavaScript, ingresar envía por POST: la contraseña nunca va en la dirección", async ({
  browser,
}) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("/ingresar");
  await page.getByLabel("Correo").fill("nadie@ejemplo.test"); // no existe: no suma intentos fallidos a nadie
  await page.getByLabel("Contraseña").fill("No-Es-La-Clave-2026");
  await page.getByRole("button", { name: "Ingresar" }).click();
  await page.waitForLoadState("load");
  expect(page.url()).not.toContain("password");
  expect(page.url()).not.toContain("No-Es-La-Clave");
  await context.close();
});

// Rechaza desde la bandeja los pedidos pendientes que dicen ese resumen (si una corrida anterior se
// cortó a la mitad, el pedido igual seguiría pendiente y el nuevo se rechazaría por repetido).
async function rejectPending(page: Page, summary: string) {
  await page.goto("/aprobaciones");
  const pending = () =>
    page.getByRole("listitem").filter({ hasText: summary }).filter({ hasText: "Pendiente" });
  for (let n = await pending().count(); n > 0; n--) {
    const item = pending().first();
    await item.getByLabel("Comentario").fill("Limpieza de una prueba anterior");
    await item.getByRole("button", { name: "Rechazar" }).click();
    await expect(pending()).toHaveCount(n - 1);
  }
}

test("la desactivación de alguien de Dirección General la decide otra persona de Dirección, desde la bandeja", async ({
  page,
}, testInfo) => {
  test.setTimeout(180_000);
  const summary = "Dar de baja a Delia Dirección (Dirección General)";
  const reason = `Prueba de baja ${testInfo.project.name} ${Date.now()}`;

  await login(page, "direccion@ejemplo.test", { mfa: true });
  await rejectPending(page, summary);
  await logout(page);

  // El superadmin la pide: la ficha avisa que queda pendiente y el botón dice que se pide.
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/usuarios/00000000-0000-4000-8000-000000000412");
  await openAction(page, "Desactivar…");
  await expect(page.getByText("Esta persona es de Dirección General.")).toBeVisible();
  await page.getByLabel("Motivo para desactivar").fill(reason);
  await page.getByRole("button", { name: "Pedir la desactivación" }).click();
  await expect(notice(page)).toContainText("otra persona de Dirección General");
  await expect(page.getByText("Activa", { exact: true })).toBeVisible();
  await axe(page);
  // En su bandeja la ve, pero no la puede decidir.
  await page.goto("/aprobaciones");
  const mine = page
    .getByRole("listitem")
    .filter({ hasText: reason })
    .filter({ hasText: "Pendiente" });
  await expect(mine.getByText(summary, { exact: true })).toBeVisible();
  await expect(mine.getByText("La tiene que decidir otra persona con permiso.")).toBeVisible();
  await logout(page);

  // Otra persona de Dirección la ve en la bandeja y la rechaza (así la cuenta de prueba sigue activa).
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  const pending = page
    .getByRole("listitem")
    .filter({ hasText: reason })
    .filter({ hasText: "Pendiente" });
  await expect(pending.getByText(summary, { exact: true })).toBeVisible();
  await axe(page);
  await pending.getByLabel("Comentario").fill("No corresponde");
  await pending.getByRole("button", { name: "Rechazar" }).click();
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: reason })
      .first()
      .getByText("Rechazada", { exact: true }),
  ).toBeVisible();
  await logout(page);
});
