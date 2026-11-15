// El selector de local muestra siempre lo que está aplicado (pedido de Soy, ADR-0048). Soy veía «Demo Café Centro» arriba
// y Costos le pedía elegir un local: había elegido en la lista sin apretar «Cambiar» (se reprodujo con estas pruebas,
// caso a). Tampoco coincidía con un enlace con ?local= (caso d). Con mouse o dedo, elegir aplica; con el teclado, se
// confirma con «Aplicar»; un ?local= se aplica al llegar.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { chooseLocal, login, menuLink } from "./helpers";

test.describe.configure({ timeout: 90_000 });

const PASTAS_CENTRO = "00000000-0000-4000-8000-000000000201";
const PASTAS_NORTE = "00000000-0000-4000-8000-000000000202";

// Visible: Next guarda ocultas las pantallas anteriores, cada una con su selector.
const selector = (page: Page) => page.getByLabel("Local activo").locator("visible=true");
const chip = (page: Page) =>
  page
    .locator("form")
    .filter({ has: selector(page) })
    .getByRole("status");

// Que la barra ya responda (hidratada): antes, elegir no llega a React.
async function ready(page: Page) {
  await expect(page.locator("form").filter({ has: selector(page) })).toHaveAttribute(
    "data-ready",
    "true",
    { timeout: 20_000 },
  );
}

async function startWithAll(page: Page) {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await chooseLocal(page, { label: "Todos mis locales" });
}

test("elegir un local en la barra lo aplica, sin pasos de más", async ({ page }) => {
  await startWithAll(page);
  await page.goto("/costos");
  await expect(page.getByText("Costos se ve de a un local.")).toBeVisible();
  // Lo que hizo Soy: elegir en la lista (con el mouse o el dedo), sin ningún botón.
  await ready(page);
  await selector(page).selectOption(PASTAS_CENTRO);
  await expect(page.getByText(/^Demo Pastas Centro · actualizado el /)).toBeVisible({
    timeout: 20_000,
  });
  await expect(chip(page)).toHaveText("Aplicado");
  await expect(page.getByText("Costos se ve de a un local.")).toHaveCount(0);
  // Y sigue aplicado en otra pantalla.
  await (await menuLink(page, "Inicio")).click();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Demo Pastas Centro");
  await expect(selector(page)).toHaveValue(PASTAS_CENTRO);
  await new AxeBuilder({ page })
    .include("header")
    .analyze()
    .then((r) => expect(r.violations).toEqual([]));
  await chooseLocal(page, { label: "Todos mis locales" });
});

test("volver a una pantalla ya vista muestra el local aplicado", async ({ page }) => {
  await startWithAll(page);
  await page.goto("/costos");
  await chooseLocal(page, PASTAS_CENTRO);
  await (await menuLink(page, "Inicio")).click();
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Demo Pastas Centro");
  await chooseLocal(page, { label: "Todos mis locales" });
  // De vuelta a Costos sin recargar: Next puede mostrar la copia guardada, pero el selector dice lo aplicado.
  await (await menuLink(page, "Costos")).click();
  await expect(page.getByText("Costos se ve de a un local.")).toBeVisible();
  await expect(selector(page)).toHaveValue("");
  await expect(chip(page)).toHaveText("Aplicado");
});

test("un enlace con ?local= queda aplicado arriba", async ({ page }) => {
  await startWithAll(page);
  await page.goto(`/costos?local=${PASTAS_NORTE}`);
  await expect(page.getByRole("main").getByText(/^Demo Pastas Norte · /)).toBeVisible();
  await expect(selector(page)).toHaveValue(PASTAS_NORTE, { timeout: 20_000 });
  await expect(chip(page)).toHaveText("Aplicado");
  // Ya aplicado, la dirección deja de llevarlo: manda el de arriba.
  await expect(page).not.toHaveURL(/local=/);
  await page.reload();
  await expect(selector(page)).toHaveValue(PASTAS_NORTE);
  await chooseLocal(page, { label: "Todos mis locales" });
});

test("con el teclado no se aplica nada hasta confirmar", async ({ page }, info) => {
  test.skip(info.project.name !== "computadora", "el teclado se prueba en la computadora");
  await startWithAll(page);
  await page.goto("/costos");
  await expect(page.getByText("Costos se ve de a un local.")).toBeVisible();
  // Sin cambios, no hay botón: el chip dice «Aplicado».
  await ready(page);
  await expect(page.getByRole("button", { name: "Aplicar" })).toHaveCount(0);
  await selector(page).focus();
  await page.keyboard.press("ArrowDown");
  await expect(chip(page)).toHaveText("Sin aplicar");
  const apply = page.getByRole("button", { name: "Aplicar" }).locator("visible=true");
  await expect(apply).toBeVisible();
  // Moverse por la lista no cambió la pantalla.
  await expect(page.getByText("Costos se ve de a un local.")).toBeVisible();
  const chosen = await selector(page).inputValue();
  expect(chosen).not.toBe("");
  await page.keyboard.press("Tab");
  await expect(apply).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(chip(page)).toHaveText("Aplicado", { timeout: 20_000 });
  await expect(selector(page)).toHaveValue(chosen);
  await expect(page.getByText("Costos se ve de a un local.")).toHaveCount(0);
  await chooseLocal(page, { label: "Todos mis locales" });
});
