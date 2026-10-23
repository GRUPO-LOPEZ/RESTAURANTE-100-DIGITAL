// Sistema de diseño y accesibilidad en la pantalla de ingreso (la primera que ve todo el mundo).
// Reemplaza a la prueba de la página de inicio de la Fase 0, que ahora pide sesión.
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test.describe("pantalla de ingreso", () => {
  test("está en español y con el título correcto", async ({ page }) => {
    await page.goto("/ingresar");
    await expect(page).toHaveTitle("Ingresar · Grupo LF");
    await expect(page.locator("html")).toHaveAttribute("lang", "es-AR");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Ingresar");
  });

  test("usa la paleta y la tipografía del prompt maestro", async ({ page }) => {
    await page.goto("/ingresar");
    const body = page.locator("body");
    await expect(body).toHaveCSS("background-color", "rgb(250, 250, 249)"); // #FAFAF9
    await expect(body).toHaveCSS("color", "rgb(31, 41, 55)"); // #1F2937
    await expect(body).toHaveCSS("font-size", "16px");
    const fontFamily = await body.evaluate((el) => getComputedStyle(el).fontFamily);
    expect(fontFamily).toMatch(/inter/i);
  });

  test("no tiene problemas de accesibilidad (axe, WCAG AA)", async ({ page }) => {
    await page.goto("/ingresar");
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test("no hay desplazamiento horizontal", async ({ page }) => {
    await page.goto("/ingresar");
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("el botón principal mide al menos 44 px y tiene foco visible con teclado", async ({
    page,
  }) => {
    await page.goto("/ingresar");
    const button = page.getByRole("button", { name: "Ingresar" });
    const box = await button.boundingBox();
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(44);
    await expect(button).toHaveCSS("background-color", "rgb(79, 109, 154)"); // #4F6D9A

    // Orden con el teclado: contraseña → "Recordar mi sesión" → Ingresar.
    await page.getByLabel("Contraseña").focus();
    await page.keyboard.press("Tab");
    await expect(page.getByLabel("Recordar mi sesión en este dispositivo")).toBeFocused();
    await page.keyboard.press("Tab");
    await expect(button).toBeFocused();
    await expect(button).toHaveCSS("outline-style", "solid");
    await expect(button).toHaveCSS("outline-color", "rgb(79, 109, 154)");
  });

  test("los campos tienen etiqueta visible y miden al menos 44 px", async ({ page }) => {
    await page.goto("/ingresar");
    for (const label of ["Correo", "Contraseña"]) {
      const input = page.getByLabel(label);
      await expect(input).toBeVisible();
      expect((await input.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
    }
  });
});
