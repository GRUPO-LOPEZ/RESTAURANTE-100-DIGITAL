// Flujos de la Fase 1 con personas del seed (supabase/seed.sql), en celular y computadora.
// Pruebas del Módulo Maestro que cubre: 1, 8 y las adicionales A5, A7 y A8 (parte de pantalla).
import { readFileSync } from "node:fs";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

import { PASSWORD, fillLogin, freshTotp, login, logout, notice, openAction } from "./helpers";

function publicEnv(name: string): string {
  const line = readFileSync(".env.example", "utf8")
    .split(/\r?\n/)
    .find((l) => l.startsWith(`${name}=`));
  return line?.slice(name.length + 1) ?? "";
}

test.describe("1. sin sesión no se consulta información privada", () => {
  test("las pantallas mandan a ingresar", async ({ page }) => {
    for (const path of [
      "/",
      "/usuarios",
      "/usuarios/lista",
      "/aprobaciones",
      "/historial",
      "/roles",
      "/recetas",
      "/mi-cuenta",
    ]) {
      await page.goto(path);
      await expect(page).toHaveURL(/\/ingresar$/);
    }
  });

  test("la API no devuelve datos sin sesión", async ({ request }) => {
    const url = publicEnv("NEXT_PUBLIC_SUPABASE_URL");
    const key = publicEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
    for (const [schema, table] of [
      ["org", "restaurants"],
      ["core", "user_profiles"],
      ["workflow", "approval_requests"],
    ]) {
      const res = await request.get(`${url}/rest/v1/${table}?select=*`, {
        headers: { apikey: key, "accept-profile": schema as string },
      });
      expect(res.status(), `${schema}.${table}`).toBe(401);
    }
  });
});

test.describe("ingreso", () => {
  test("con una contraseña incorrecta no se entra y el mensaje no dice si el correo existe", async ({
    page,
  }) => {
    await fillLogin(page, "cocinero@ejemplo.test", "incorrecta-123");
    await expect(notice(page)).toHaveText("Correo o contraseña incorrectos.");
    await fillLogin(page, "nadie@ejemplo.test", "incorrecta-123");
    await expect(notice(page)).toHaveText("Correo o contraseña incorrectos.");
  });

  test("un rol sin doble verificación obligatoria entra con la contraseña", async ({ page }) => {
    await login(page, "cocinero@ejemplo.test");
    await expect(page.getByText("Cocinero / Operador")).toBeVisible();
    // El cocinero no ve el menú de usuarios ni el historial.
    await expect(page.getByRole("link", { name: "Usuarios" })).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Historial" })).toHaveCount(0);
    await logout(page);
  });

  test("A8. los roles 1 a 4 y Controller no entran sin doble verificación", async ({ page }) => {
    await fillLogin(page, "gerente@ejemplo.test");
    await expect(page).toHaveURL(/\/ingresar\/doble-verificacion$/);
    // Sin el código, ninguna pantalla deja pasar.
    await page.goto("/usuarios");
    await expect(page).toHaveURL(/\/ingresar\/doble-verificacion$/);
    await page.getByLabel("Código de 6 números").fill("000000");
    await page.getByRole("button", { name: "Verificar" }).click();
    await expect(notice(page)).toContainText("no es correcto");
    await page.getByLabel("Código de 6 números").fill(await freshTotp(page));
    await page.getByRole("button", { name: "Verificar" }).click();
    await expect(page.getByRole("heading", { level: 1, name: /^Hola, / })).toBeVisible();
    // Los roles propios se ven en Mi cuenta (el Inicio es un tablero, ADR-0045).
    await page.goto("/mi-cuenta");
    await expect(page.getByRole("list", { name: "Tus roles" })).toContainText(
      "Gerente de Restaurante",
    );
    await logout(page);
  });

  test("A7. después de 5 intentos fallidos la cuenta se bloquea unos minutos", async ({
    page,
  }, testInfo) => {
    const email = `e2e-bloqueo-${testInfo.project.name}@ejemplo.test`;
    for (let i = 1; i <= 4; i++) {
      await fillLogin(page, email, `incorrecta-${i}`);
      await expect(notice(page)).toHaveText("Correo o contraseña incorrectos.");
    }
    await fillLogin(page, email, "incorrecta-5");
    await expect(notice(page)).toContainText("bloqueada unos minutos");
    // Ni con la contraseña correcta.
    await fillLogin(page, email, PASSWORD);
    await expect(notice(page)).toContainText("bloqueada unos minutos");
  });
});

test.describe("8 y A5. una cuenta desactivada pierde el acceso; reactivada vuelve a entrar", () => {
  test("desactivar, pedir la reactivación, que la apruebe otra persona y volver a entrar", async ({
    page,
  }, testInfo) => {
    // Dos ingresos con doble verificación: cada uno puede esperar el próximo código (hasta 30 s).
    test.setTimeout(120_000);
    const email = `e2e-baja-${testInfo.project.name}@ejemplo.test`;
    const who =
      testInfo.project.name === "celular" ? "Prueba Baja Celular" : "Prueba Baja Computadora";

    // La persona entra normalmente.
    await login(page, email);
    await logout(page);

    // El gerente la desactiva.
    await login(page, "gerente@ejemplo.test", { mfa: true });
    await page.goto(`/usuarios/lista?q=${encodeURIComponent(email)}`);
    await page
      .getByRole("link", { name: /Prueba Baja/ })
      .first()
      .click();
    await expect(page.getByRole("heading", { level: 1, name: /Prueba Baja/ })).toBeVisible();
    await openAction(page, "Desactivar…");
    await page.getByLabel("Motivo para desactivar").fill("Prueba automática: baja temporal");
    await page.getByRole("button", { name: "Desactivar la cuenta" }).click();
    // Al desactivarse, la ficha cambia: ahora ofrece pedir la reactivación.
    await expect(page.locator("summary", { hasText: "Pedir la reactivación…" })).toBeVisible();
    await expect(page.getByText("Desactivada", { exact: true }).first()).toBeVisible();

    // Pide la reactivación: no la puede aprobar él mismo.
    await openAction(page, "Pedir la reactivación…");
    await page.getByLabel("Motivo para reactivar").fill("Prueba automática: vuelve a trabajar");
    await page.getByRole("button", { name: "Pedir la reactivación" }).click();
    await expect(page.getByText(/pendiente hasta que la apruebe otra persona/)).toBeVisible();
    await page.goto("/aprobaciones");
    const request = page
      .getByRole("listitem")
      .filter({ hasText: `Reactivar la cuenta de ${who}` })
      .first();
    await expect(request.getByText("La tiene que decidir otra persona con permiso.")).toBeVisible();
    await expect(request.getByRole("button", { name: "Aprobar" })).toHaveCount(0);
    await logout(page);

    // La persona desactivada no puede entrar.
    await fillLogin(page, email);
    await expect(notice(page)).toContainText("no puede ingresar");

    // Otra persona con permiso sobre ese local la aprueba.
    await login(page, "gerente2@ejemplo.test", { mfa: true });
    await page.goto("/aprobaciones");
    const pending = page
      .getByRole("listitem")
      .filter({ hasText: `Reactivar la cuenta de ${who}` })
      .filter({ hasText: "Pendiente" })
      .first();
    await pending.getByLabel("Comentario").fill("Confirmado con el local");
    await pending.getByRole("button", { name: "Aprobar" }).click();
    // Al aplicarse, la tarjeta pasa a "Aprobada" con quién la resolvió (el formulario ya no hace falta).
    const done = page
      .getByRole("listitem")
      .filter({ hasText: `Reactivar la cuenta de ${who}` })
      .first();
    await expect(done.getByText("Aprobada", { exact: true })).toBeVisible();
    await expect(done.getByText(/Resolvió .*Confirmado con el local/)).toBeVisible();
    await logout(page);

    // Vuelve a entrar.
    await login(page, email);
  });
});

test.describe("tablero de usuarios", () => {
  test("responde la pregunta, muestra la fecha de los datos y pasa axe", async ({ page }) => {
    // Ingreso con doble verificación: puede esperar el próximo código (hasta 30 s).
    test.setTimeout(90_000);
    await login(page, "director@ejemplo.test", { mfa: true });
    await page.goto("/usuarios");
    await expect(
      page.getByRole("heading", { level: 1, name: "¿Quién tiene acceso y qué está pasando?" }),
    ).toBeVisible();
    await expect(page.getByText(/Datos al /)).toBeVisible();
    // Las 4 tarjetas, el gráfico de accesos y las tablas de la sección 9.
    for (const kpi of [
      "Cuentas activas",
      "Desactivadas o suspendidas",
      "Aprobaciones pendientes",
      "Accesos rechazados en 7 días",
    ])
      await expect(page.getByText(kpi, { exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Accesos por día" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Personas por local" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Personas por rol" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Últimos cambios críticos" })).toBeVisible();
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();
    expect(results.violations).toEqual([]);
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
    await logout(page);
  });
});
