// Prueba de humo de la Fase 0: la app carga, respeta el sistema de diseño y pasa axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test.describe("página de inicio", () => {
  test("muestra el estado del entorno en español", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle("Grupo LF");
    await expect(page.locator("html")).toHaveAttribute("lang", "es-AR");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "Sistema Operativo Gastronómico",
    );
    await expect(
      page.getByRole("list", { name: "Estados del sistema de diseño" }).getByRole("listitem"),
    ).toHaveCount(6);
  });

  test("usa la paleta y la tipografía del prompt maestro", async ({ page }) => {
    await page.goto("/");
    const body = page.locator("body");
    await expect(body).toHaveCSS("background-color", "rgb(250, 250, 249)"); // #FAFAF9
    await expect(body).toHaveCSS("color", "rgb(31, 41, 55)"); // #1F2937
    await expect(body).toHaveCSS("font-size", "16px");
    const fontFamily = await body.evaluate((el) => getComputedStyle(el).fontFamily);
    expect(fontFamily).toMatch(/inter/i);
    await expect(page.getByText("Aprobado")).toHaveCSS("background-color", "rgb(209, 250, 229)"); // #D1FAE5
  });

  test("no tiene problemas de accesibilidad (axe, WCAG AA)", async ({ page }) => {
    await page.goto("/");
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();
    expect(results.violations).toEqual([]);
  });

  test("no hay desplazamiento horizontal", async ({ page }) => {
    await page.goto("/");
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - window.innerWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
});
