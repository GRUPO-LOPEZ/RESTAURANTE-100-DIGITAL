// Respuestas de Joaco a las preguntas abiertas de la Fase 1 (ADR-0015, 2026-10-22), en pantalla:
// errores por campo antes de enviar (React Hook Form), quién ve el último acceso y quién publica
// un documento de ensayo. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, openAction } from "./helpers";

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

test("quien mandó un documento a revisión no lo publica: lo publica otra persona", async ({
  page,
}, testInfo) => {
  test.setTimeout(150_000);
  // Un título único: el documento se crea de verdad en la base local.
  const title = `Pesto ${testInfo.project.name} ${Date.now()}`;
  const doc = () => page.getByRole("listitem").filter({ hasText: title });

  await login(page, "chef@ejemplo.test");
  await page.goto("/ensayo");
  await page.getByLabel("Dónde").selectOption({ label: "Toda la marca · Demo Pastas" });
  await page.getByLabel("Título").fill(title);
  await page.getByLabel("Contenido", { exact: true }).fill("Albahaca, piñones y aceite.");
  await page.locator("#motivo-nuevo").fill("Receta nueva");
  await page.getByRole("button", { name: "Crear el borrador" }).click();
  await expect(doc()).toBeVisible();

  await doc().locator("summary", { hasText: "Pedir la revisión" }).click();
  await doc().getByLabel("Motivo").fill("Lista para revisar");
  await doc().locator("button[type=submit]", { hasText: "Pedir la revisión" }).click();
  await expect(doc().getByText("Lo mandaste vos a revisión")).toBeVisible();
  await expect(doc().locator("summary", { hasText: "Aprobar y publicar" })).toHaveCount(0);
  await axe(page);
  await logout(page);

  await login(page, "director@ejemplo.test", { mfa: true });
  await page.goto("/ensayo");
  await doc().locator("summary", { hasText: "Aprobar y publicar" }).click();
  await doc().getByLabel("Motivo").fill("Revisada");
  await doc().locator("button[type=submit]", { hasText: "Aprobar y publicar" }).click();
  await expect(doc().getByText("Vigente")).toBeVisible();
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
