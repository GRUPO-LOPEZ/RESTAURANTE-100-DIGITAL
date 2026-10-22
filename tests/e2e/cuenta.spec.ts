// Ingreso y cuenta (sección 9 del documento de Soy): recordar sesión, recuperar la contraseña,
// mi cuenta y el selector de local. En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type APIRequestContext, type Page } from "@playwright/test";

import { PASSWORD, fillLogin, login, logout, menuLink, notice } from "./helpers";

const MAILPIT = "http://127.0.0.1:54324";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

// El enlace del último correo de recuperación que llegó a esa dirección (Mailpit local).
async function recoveryLink(request: APIRequestContext, email: string): Promise<string> {
  let link: string | undefined;
  await expect
    .poll(
      async () => {
        const search = await request.get(`${MAILPIT}/api/v1/search`, {
          params: { query: `to:"${email}"` },
        });
        const body = (await search.json()) as { messages: { ID: string }[] };
        const id = body.messages[0]?.ID;
        if (!id) return false;
        const message = (await (await request.get(`${MAILPIT}/api/v1/message/${id}`)).json()) as {
          Text: string;
          HTML: string;
        };
        link = /https?:\/\/[^\s"'<>]+type=recovery[^\s"'<>]*/
          .exec(`${message.HTML} ${message.Text}`)?.[0]
          ?.replace(/&amp;/g, "&");
        return Boolean(link);
      },
      { timeout: 20_000 },
    )
    .toBe(true);
  return link ?? "";
}

test.describe("ingreso", () => {
  test("sin marcar «recordar», la sesión se borra al cerrar el navegador", async ({ page }) => {
    await page.goto("/ingresar");
    await axe(page);
    await page.getByLabel("Correo").fill("cocinero@ejemplo.test");
    await page.getByLabel("Contraseña").fill(PASSWORD);
    await page.getByLabel("Recordar mi sesión en este dispositivo").uncheck();
    await page.getByRole("button", { name: "Ingresar" }).click();
    await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();
    const auth = (await page.context().cookies()).filter((c) => c.name.includes("auth-token"));
    expect(auth.length).toBeGreaterThan(0);
    // Cookie de sesión del navegador: sin fecha de vencimiento.
    for (const c of auth) expect(c.expires).toBe(-1);
    await logout(page);
  });

  test("marcando «recordar», la sesión queda guardada", async ({ page }) => {
    await login(page, "cocinero@ejemplo.test");
    const auth = (await page.context().cookies()).filter((c) => c.name.includes("auth-token"));
    for (const c of auth) expect(c.expires).toBeGreaterThan(Date.now() / 1000);
    await logout(page);
  });
});

test.describe("recuperar la contraseña y mi cuenta", () => {
  test("pedir el enlace, elegir una contraseña nueva y después cambiarla desde mi cuenta", async ({
    page,
    request,
  }, testInfo) => {
    test.setTimeout(90_000);
    const email = `e2e-clave-${testInfo.project.name}@ejemplo.test`;
    const first = `Nueva-Clave-${testInfo.project.name}-2026`;
    const second = `Otra-Clave-${testInfo.project.name}-2027`;

    // El mensaje es el mismo exista o no el correo.
    await page.goto("/ingresar");
    await page.getByRole("link", { name: "¿Olvidaste tu contraseña?" }).click();
    await expect(
      page.getByRole("heading", { level: 1, name: "Recuperar la contraseña" }),
    ).toBeVisible();
    await axe(page);
    await page.getByLabel("Correo").fill("nadie-existe@ejemplo.test");
    await page.getByRole("button", { name: "Enviar el enlace" }).click();
    const sameMessage = "Si el correo es de una cuenta, te llegó un enlace";
    await expect(notice(page)).toContainText(sameMessage);

    // Mailpit guarda los correos de corridas anteriores: se borran los de esta dirección antes.
    await request.delete(`${MAILPIT}/api/v1/search`, { params: { query: `to:"${email}"` } });
    await page.getByLabel("Correo").fill(email);
    await page.getByRole("button", { name: "Enviar el enlace" }).click();
    await expect(notice(page)).toContainText(sameMessage);

    // El enlace del correo abre la pantalla de contraseña nueva.
    await page.goto(await recoveryLink(request, email));
    await expect(page).toHaveURL(/\/ingresar\/nueva-contrasena$/);
    await axe(page);
    await page.getByLabel("Contraseña nueva").fill("corta1");
    await page.getByLabel("Repetí la contraseña").fill("corta1");
    await page.getByRole("button", { name: "Guardar y entrar" }).click();
    await expect(notice(page)).toContainText("al menos 12 caracteres");
    await page.getByLabel("Contraseña nueva").fill(first);
    await page.getByLabel("Repetí la contraseña").fill(first);
    await page.getByRole("button", { name: "Guardar y entrar" }).click();
    await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();
    await logout(page);

    // La contraseña vieja ya no sirve; la nueva sí.
    await fillLogin(page, email, PASSWORD);
    await expect(notice(page)).toHaveText("Correo o contraseña incorrectos.");
    await fillLogin(page, email, first);
    await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();

    // Mi cuenta: datos, contraseña, doble verificación y sesiones.
    await (await menuLink(page, "Mi cuenta")).click();
    await expect(page.getByRole("heading", { level: 1, name: "Mi cuenta" })).toBeVisible();
    await expect(page.getByText("Esta sesión")).toBeVisible();
    await axe(page);
    await page.getByLabel("Contraseña actual").fill("no-es-la-mia-123");
    await page.getByLabel("Contraseña nueva", { exact: true }).fill(second);
    await page.getByLabel("Repetí la contraseña nueva").fill(second);
    await page.getByRole("button", { name: "Cambiar la contraseña" }).click();
    await expect(notice(page)).toContainText("La contraseña actual no es correcta");
    // Después de un intento, el formulario se vacía (no quedan contraseñas escritas en pantalla).
    await page.getByLabel("Contraseña actual").fill(first);
    await page.getByLabel("Contraseña nueva", { exact: true }).fill(second);
    await page.getByLabel("Repetí la contraseña nueva").fill(second);
    await page.getByRole("button", { name: "Cambiar la contraseña" }).click();
    await expect(notice(page)).toContainText("tu contraseña cambió");
    await logout(page);
    await fillLogin(page, email, second);
    await expect(page.getByRole("heading", { level: 1, name: "Inicio" })).toBeVisible();
    await logout(page);
  });

  test("cerrar las demás sesiones deja afuera a los otros dispositivos", async ({
    page,
    browser,
  }) => {
    const other = await browser.newContext();
    const otherPage = await other.newPage();
    await login(otherPage, "compras@ejemplo.test");
    await login(page, "compras@ejemplo.test");
    await page.goto("/mi-cuenta");
    await page.getByRole("button", { name: /^Cerrar las otras/ }).click();
    // Ya no quedan otras sesiones en la lista.
    await expect(page.getByText("No tenés otras sesiones abiertas.")).toBeVisible();
    // El otro dispositivo pierde el acceso en la consulta siguiente (la base mira la sesión).
    // La redirección llega con el contenido que se transmite después de la carga inicial.
    await otherPage.goto("/mi-cuenta");
    await expect(otherPage).toHaveURL(/\/ingresar$/, { timeout: 15_000 });
    await other.close();
    await logout(page);
  });
});

test.describe("selector de local", () => {
  test("quien tiene dos locales elige uno, queda recordado y filtra las pantallas", async ({
    page,
  }) => {
    test.setTimeout(90_000);
    await login(page, "gerente2@ejemplo.test", { mfa: true });
    const selector = page.getByLabel("Local activo");
    await expect(selector).toBeVisible();
    await selector.selectOption({ label: "Demo Pastas Norte · PASTAS" });
    await page.getByRole("button", { name: "Cambiar" }).click();
    await page.reload();
    await expect(page.getByLabel("Local activo")).toHaveValue(
      "00000000-0000-4000-8000-000000000202",
    );
    await page.goto("/usuarios/lista");
    await expect(page.getByLabel("Local", { exact: true })).toHaveValue(
      "00000000-0000-4000-8000-000000000202",
    );
    // El resumen de los filtros lo dice (en el celular, los filtros empiezan plegados).
    await expect(page.locator("summary", { hasText: "el que elegiste arriba" })).toBeVisible();
    // Vuelve a "todos" para no afectar a otras pruebas.
    await page.getByLabel("Local activo").selectOption({ label: "Todos mis locales" });
    await page.getByRole("button", { name: "Cambiar" }).click();
    await page.reload();
    await expect(page.getByLabel("Local activo")).toHaveValue("");
    await logout(page);
  });

  test("quien tiene un solo local no ve el selector", async ({ page }) => {
    await login(page, "cocinero@ejemplo.test");
    await expect(page.getByLabel("Local activo")).toHaveCount(0);
    await logout(page);
  });
});
