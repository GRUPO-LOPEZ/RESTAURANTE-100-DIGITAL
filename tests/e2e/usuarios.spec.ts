// Usuarios en una pantalla (Tanda 1 de Soy, ADR-0062): la ficha de la persona con datos y roles en un guardado, cerrar
// sus sesiones, invitar desde un modal corto, y el tablero, la lista y la ficha sin scroll de página en los 4 tamaños
// con un rol que edita y uno que solo lee. En celular y computadora, con axe. Datos ficticios.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { chooseLocal, login, logout, notice } from "./helpers";

const SCREENS = [
  { width: 1440, height: 900 },
  { width: 1600, height: 900 },
  { width: 1715, height: 843 },
  { width: 1920, height: 1080 },
];
const COOK = "/usuarios/00000000-0000-4000-8000-000000000409";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

async function noScrollOnScreens(page: Page, url: string, heading: RegExp | string) {
  const before = page.viewportSize();
  for (const size of SCREENS) {
    await page.setViewportSize(size);
    await page.goto(url);
    await expect(page.getByRole("heading", { level: 1, name: heading })).toBeVisible();
    await expect(page.getByRole("main").locator("section:visible").first()).toBeVisible();
    await page.waitForLoadState("networkidle");
    const extra = await page.evaluate(() => {
      const s = document.scrollingElement as HTMLElement;
      return s.scrollHeight - s.clientHeight;
    });
    expect(extra, `${url} en ${size.width} × ${size.height}`).toBeLessThanOrEqual(0);
  }
  if (before) await page.setViewportSize(before);
}

test("se editan los datos y los roles de una persona en un guardado, con motivo", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === "celular",
    "En el celular la ficha es de consulta (ADR-0036).",
  );
  test.setTimeout(120_000);
  const job = `Cocinera de prueba ${Date.now() % 100_000}`;
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(COOK);
  await expect(page.getByRole("heading", { level: 1, name: "Lucía Operadora" })).toBeVisible();
  const roles = page.getByRole("list", { name: "Roles" });
  await expect(roles).toContainText("Local · Demo Pastas Centro");

  // Un obligatorio vacío se marca al salir del campo.
  const name = page.getByLabel("Nombre", { exact: false }).first();
  await name.fill("");
  await name.blur();
  await expect(name).toHaveAttribute("aria-invalid", "true");
  await page.getByRole("button", { name: "Descartar" }).click();
  await expect(name).toHaveValue("Lucía");

  // Agregar un rol sin elegirlo avisa; uno que ya tiene, también.
  await page.getByRole("button", { name: "Agregar a los cambios" }).click();
  await expect(page.getByText("Elegí el rol y dónde lo va a usar.")).toBeVisible();
  await page.getByLabel("Rol", { exact: true }).selectOption("cook");
  await page
    .getByLabel("Dónde", { exact: true })
    .selectOption({ label: "Local · Demo Pastas Centro" });
  await page.getByRole("button", { name: "Agregar a los cambios" }).click();
  await expect(page.getByText("Ese rol ya está en ese lugar.")).toBeVisible();

  // Un rol elegido y no agregado no se pierde sin avisar: Guardar lo frena y Descartar lo limpia.
  await page.getByLabel("Puesto").fill("Otro puesto");
  await page.getByLabel("Motivo de los cambios").fill("Prueba");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page)).toContainText("Elegiste un rol y no lo agregaste");
  await page.getByRole("button", { name: "Descartar" }).click();
  await expect(page.getByLabel("Rol", { exact: true })).toHaveValue("");
  await page.getByLabel("Motivo de los cambios").fill("");

  // Quitar un rol es un cambio más, que se puede deshacer antes de guardar.
  await page.getByRole("button", { name: /^Quitar Cocinero/ }).click();
  await expect(page.getByText("1 cambio sin guardar")).toBeVisible();
  await expect(roles).toContainText("se quita al guardar");
  await page.getByRole("button", { name: /^Volver a dejar Cocinero/ }).click();
  await expect(page.getByText("Sin cambios", { exact: true }).last()).toBeVisible();

  // El puesto, con motivo.
  await page.getByLabel("Puesto").fill(job);
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page)).toContainText("Escribí el motivo");
  await page.getByLabel("Motivo de los cambios").fill("Cambio de puesto (prueba automática)");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page).filter({ hasText: "Cambios guardados." })).toBeVisible();
  await expect(page.getByLabel("Puesto")).toHaveValue(job);
  await expect(page.getByText(job).first()).toBeVisible();
  await axe(page);
});

test("el puesto de quien tiene más permisos se carga, y su nombre no", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === "celular",
    "En el celular la ficha es de consulta (ADR-0036).",
  );
  test.setTimeout(90_000);
  const job = `Dirección de prueba ${Date.now() % 100_000}`;
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/usuarios/00000000-0000-4000-8000-000000000402");
  await expect(page.getByRole("heading", { level: 1, name: "Diego Dirección" })).toBeVisible();
  // El nombre se lee; el puesto y el área se editan (no dan permisos; decisión de Joaco, 2026-11-24).
  await expect(page.getByRole("textbox", { name: /^Nombre/ })).toHaveCount(0);
  await expect(page.getByRole("textbox", { name: /^Apellido/ })).toHaveCount(0);
  await page.getByLabel("Puesto").fill(job);
  await page.getByLabel("Motivo de los cambios").fill("Alta del puesto (prueba automática)");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page).filter({ hasText: "Cambios guardados." })).toBeVisible();
  await expect(page.getByLabel("Puesto")).toHaveValue(job);
});

test("cambiar un rol por otro que espera aprobación no la deja sin rol", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === "celular",
    "En el celular la ficha es de consulta (ADR-0036).",
  );
  test.setTimeout(90_000);
  await login(page, "director@ejemplo.test", { mfa: true });
  await page.goto(COOK);
  await page.getByRole("button", { name: /^Quitar Cocinero/ }).click();
  await page.getByLabel("Rol", { exact: true }).selectOption("executive_chef");
  await page.getByLabel("Dónde", { exact: true }).selectOption({ label: "Marca · Demo Pastas" });
  await page.getByRole("button", { name: "Agregar a los cambios" }).click();
  await expect(page.getByText("2 cambios sin guardar")).toBeVisible();
  await page.getByLabel("Motivo de los cambios").fill("Prueba automática");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page)).toContainText("El rol nuevo espera una aprobación");
  // No quedó nada: la ficha recargada tiene el rol de siempre.
  await page.getByRole("button", { name: "Descartar" }).click();
  await page.reload();
  await expect(page.getByRole("list", { name: "Roles" })).toContainText("Cocinero");
});

test("quien administra a la persona le cierra todas las sesiones, sin suspenderla", async ({
  browser,
  page,
}, testInfo) => {
  test.setTimeout(150_000);
  const email = `e2e-pausa-${testInfo.project.name}@ejemplo.test`;
  // La persona entra desde otro dispositivo.
  const other = await browser.newContext();
  const device = await other.newPage();
  await login(device, email);

  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(`/usuarios/lista?q=${encodeURIComponent(email)}&local=todos`);
  await page
    .getByRole("link", { name: /Prueba Pausa/ })
    .first()
    .click();
  await expect(page.getByRole("heading", { level: 1, name: /Prueba Pausa/ })).toBeVisible();
  await page.getByRole("button", { name: "Cerrar todas" }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByLabel("Motivo para cerrar las sesiones").fill("Perdió el celular (prueba)");
  await dialog.getByRole("button", { name: "Cerrar todas las sesiones" }).click();
  // El aviso se ve y el foco queda en el título (el botón que lo abrió ya no está).
  await expect(notice(page).filter({ hasText: "Se cerraron todas sus sesiones" })).toBeVisible();
  await expect(page.getByRole("heading", { level: 1, name: /Prueba Pausa/ })).toBeFocused();
  await expect(page.getByText("0 abiertas")).toBeVisible();
  await expect(page.getByText("Activa", { exact: true }).first()).toBeVisible();

  // El otro dispositivo quedó afuera, y puede volver a entrar.
  await device.goto("/recetas");
  await expect(device).toHaveURL(/\/ingresar/);
  await login(device, email);
  // Y se entera de quién fue, en Mi cuenta (no tiene la bandeja de aprobaciones).
  await device.goto("/mi-cuenta");
  const notices = device.getByRole("list", { name: "Avisos de tu cuenta" });
  await expect(notices).toContainText("Cerraron tus sesiones");
  await expect(notices).toContainText("Gonzalo Gerente cerró todas tus sesiones");
  await axe(device);
  await device.getByRole("button", { name: "Entendido" }).click();
  await expect(notices).toHaveCount(0);
  await other.close();
});

test("invitar a una persona desde un modal corto", async ({ page }, testInfo) => {
  test.setTimeout(90_000);
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto("/usuarios/lista");
  await page.getByRole("link", { name: "Invitar a una persona" }).click();
  const dialog = page.getByRole("dialog", { name: "Invitar a una persona" });
  await expect(dialog).toBeVisible();
  await axe(page);
  // Los errores, debajo de cada campo, antes de enviar.
  await dialog.getByRole("button", { name: "Enviar invitación" }).click();
  await expect(dialog.getByLabel("Nombre", { exact: true })).toHaveAttribute(
    "aria-invalid",
    "true",
  );
  await dialog.getByLabel("Nombre", { exact: true }).fill("Invitada");
  await dialog.getByLabel("Apellido").fill("De Prueba");
  await dialog
    .getByLabel("Correo")
    .fill(`invitada-${testInfo.project.name}-${Date.now()}@ejemplo.test`);
  await dialog.getByLabel("Rol", { exact: true }).selectOption("cook");
  await dialog.getByLabel("Dónde trabaja").selectOption({ label: "Local · Demo Pastas Centro" });
  await dialog.getByLabel("Motivo").fill("Alta de prueba automática");
  await dialog.getByRole("button", { name: "Enviar invitación" }).click();
  await expect(dialog.getByText(/Invitación enviada/)).toBeVisible({ timeout: 20_000 });
});

test("sin scroll de página, con quien edita y con quien solo lee", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === "celular", "Los 4 tamaños son de computadora.");
  test.setTimeout(240_000);
  for (const email of ["superadmin@ejemplo.test", "auditor@ejemplo.test"]) {
    await login(page, email, { mfa: email.startsWith("superadmin") });
    await page.goto("/usuarios/lista");
    await chooseLocal(page, { label: "Todos mis locales" });
    await noScrollOnScreens(page, "/usuarios", /Quién tiene acceso/);
    await noScrollOnScreens(page, "/usuarios/lista", "Personas");
    await noScrollOnScreens(page, COOK, "Lucía Operadora");
    if (email.startsWith("auditor")) {
      // Solo lee: ni barra de guardado, ni campos, ni acciones sobre la cuenta.
      await page.goto(COOK);
      await expect(page.getByRole("heading", { level: 1, name: "Lucía Operadora" })).toBeVisible();
      for (const name of ["Guardar cambios", "Suspender", "Desactivar", "Agregar a los cambios"])
        await expect(page.getByRole("button", { name, exact: true })).toHaveCount(0);
      await expect(page.getByLabel("Puesto")).toHaveCount(0);
      await axe(page);
    }
    await logout(page);
  }
});

test("en el celular la ficha es de consulta, salvo lo urgente", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "celular", "Solo el celular.");
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(COOK);
  await expect(page.getByRole("heading", { level: 1, name: "Lucía Operadora" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Guardar cambios" })).toBeHidden();
  await expect(page.getByRole("button", { name: "Agregar a los cambios" })).toBeHidden();
  for (const name of ["Suspender", "Desactivar"]) {
    const button = page.getByRole("button", { name, exact: true });
    await expect(button).toBeVisible();
    expect((await button.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
  }
  await noHorizontalScroll(page);
  await axe(page);
});
