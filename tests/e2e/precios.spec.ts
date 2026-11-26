// Precios (ADR-0029, PR 2): Compras propone un precio en la ficha y el Controller lo aprueba; una suba
// grande pasa a Dirección General; el Gerente ve el costo de su local con el precio heredado; el Chef no
// ve precios; Dirección cambia la configuración. En celular y computadora, con axe. Valores de prueba.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice, pickChoice } from "./helpers";

// El servidor de desarrollo compila cada pantalla la primera vez: en celular a veces pasa de 30 s.
test.describe.configure({ timeout: 60_000 });

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

// La ficha, en la sección de precios (el enlace de antes, ?seccion=compra, baja a «Precios de compra»: ADR-0043).
const ingredient = (n: number) =>
  `/materias-primas/00000000-0000-4000-8000-${String(800 + n).padStart(12, "0")}?seccion=compra`;

async function propose(page: Page, price: string, preview?: RegExp) {
  await page.getByRole("button", { name: "Proponer precio" }).filter({ visible: true }).click();
  const panel = page.getByRole("dialog", { name: "Proponer precio" });
  await pickChoice(panel, "Para quién vale", "Todo el grupo (Grupo Demo)");
  await panel.locator("#precio-envase").fill(price);
  // Antes de proponer se ve cómo queda y quién lo aprueba (ADR-0067).
  if (preview)
    await expect(panel.getByRole("status").filter({ hasText: "Queda" })).toContainText(preview);
  await panel.locator("#precio-motivo").fill("Precio de prueba automática");
  await panel.getByRole("button", { name: "Proponer precio" }).click();
  await expect(notice(page).filter({ hasText: "Precio propuesto." })).toBeVisible();
  await page.keyboard.press("Escape");
}

// El panel con los productos, el costo en el local y los precios (la tarjeta muestra hasta 3 productos).
async function openPrices(page: Page) {
  await page
    .getByRole("button", { name: /^Ver (el producto|los \d+ productos)$/ })
    .filter({ visible: true })
    .click();
  return page.getByRole("dialog", { name: "Precios de compra" });
}

// La solicitud de esta materia prima en la bandeja (puede haber otras pendientes).
function request(page: Page, name: string) {
  return page
    .getByRole("listitem")
    .filter({ hasText: name })
    .filter({ has: page.getByRole("button", { name: "Aprobar" }) });
}

test("Compras propone, el Controller aprueba y una suba grande pasa a Dirección", async ({
  page,
}, testInfo) => {
  test.setTimeout(240_000);
  // Una materia prima sin precios del seed para cada proyecto: el primer precio no tiene referencia.
  const [n, name] =
    testInfo.project.name === "celular" ? [25, "Queso provolone"] : [28, "Harina 0000"];

  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto(ingredient(n));
  await expect(
    page.getByRole("heading", { name: "Precios de compra", exact: true }).filter({ visible: true }),
  ).toBeVisible();
  await propose(page, "9000", /Es el primer precio en ese lugar\.\s*Lo aprueba el Controller\./);
  await noHorizontalScroll(page);
  await axe(page);
  await logout(page);

  // El Controller lo aprueba: es el primer precio, alcanza con él.
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(request(page, name)).toContainText("Es el primer precio");
  await axe(page);
  await request(page, name).getByRole("button", { name: "Aprobar" }).click();
  // Al aprobarse, la tarjeta pasa a "Aprobada" (el formulario ya no hace falta).
  await expect(request(page, name)).toHaveCount(0);
  await page.goto(ingredient(n));
  await openPrices(page);
  await expect(page.getByRole("list", { name: "Precios vigentes" })).toContainText("9.000,00");
  await page.keyboard.press("Escape");
  await logout(page);

  // Una suba grande: el Controller la aprueba y pasa a Dirección General.
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto(ingredient(n));
  // La misma variación que después ve quien aprueba.
  await propose(
    page,
    "20000",
    /sube 122,22 % contra el precio de hoy\.\s*Lo aprueban el Controller y Dirección General\./,
  );
  await logout(page);
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(request(page, name)).toContainText("+122,22 %");
  await request(page, name).getByRole("button", { name: "Aprobar" }).click();
  await expect(request(page, name)).toHaveCount(0);
  await expect(
    page
      .getByRole("listitem")
      .filter({ hasText: name })
      .filter({ hasText: "ahora la decide Dirección General" }),
  ).toBeVisible();
  await logout(page);

  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/aprobaciones");
  await expect(request(page, name)).toContainText("Ya la aprobó el Controller");
  await request(page, name).getByRole("button", { name: "Aprobar" }).click();
  await page.goto(ingredient(n));
  await openPrices(page);
  await expect(page.getByRole("list", { name: "Precios vigentes" })).toContainText("20.000,00");
});

test("el Gerente ve el costo de su local, heredado de su marca", async ({ page }) => {
  // Tiene un solo local: no hay selector y la ficha usa ese.
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(ingredient(19));
  // El precio vigente, arriba; el detalle (heredado, con y sin IVA), en el panel de los productos.
  await expect(
    page.locator('[data-slot="kpi"]', { hasText: "Precio vigente" }).filter({ visible: true }),
  ).toContainText("Demo Pastas Centro");
  await openPrices(page);
  await expect(page.getByText("Costo en Demo Pastas Centro")).toBeVisible();
  await expect(page.getByText("Heredado de la marca")).toBeVisible();
  await expect(page.getByText(/por kg/).first()).toBeVisible();
  await axe(page);
});

test("el Chef no ve precios", async ({ page }) => {
  await login(page, "chef@ejemplo.test");
  await page.goto(ingredient(19));
  await expect(page.getByRole("heading", { name: "Mozzarella" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Precios", exact: true })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Precios de compra" })).toHaveCount(0);
  await expect(page.getByText("36.000")).toHaveCount(0);
});

test("Dirección cambia la configuración de precios", async ({ page }) => {
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/configuracion");
  await page.getByRole("link", { name: /Configuración de precios/ }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: "Configuración de precios" }),
  ).toBeVisible();
  await axe(page);
  await page.locator("summary", { hasText: "Cambiar la configuración" }).click();
  await page.locator("#precios-hacia-atras").fill("45");
  await page.locator("#precios-motivo").fill("Prueba automática");
  await page.getByRole("button", { name: "Guardar configuración" }).click();
  await expect(
    notice(page).filter({ hasText: "Configuración de precios guardada." }),
  ).toBeVisible();
  await expect(page.getByText("Hace 45 días")).toBeVisible();
  // Vuelve a 30 días para no cambiar otras pruebas.
  await page.locator("#precios-hacia-atras").fill("30");
  await page.locator("#precios-motivo").fill("Vuelve al valor de prueba");
  await page.getByRole("button", { name: "Guardar configuración" }).click();
  await expect(page.getByText("Hace 30 días")).toBeVisible();
  await noHorizontalScroll(page);
});

test("«Proponer precio»: cinco datos, el resto en «Más datos», con sus valores a la vista", async ({
  page,
}) => {
  test.setTimeout(120_000);
  await login(page, "compras@ejemplo.test", { mfa: true });
  // Cebolla: un producto, con precio y proveedor.
  await page.goto(ingredient(2));
  await page.getByRole("button", { name: "Proponer precio" }).filter({ visible: true }).click();
  const panel = page.getByRole("dialog", { name: "Proponer precio" });
  const more = panel.locator("details").filter({ hasText: "Más datos" });
  await expect(more).not.toHaveAttribute("open", "");
  // Lo que va a viajar se lee sin abrir: la alícuota del último precio y el proveedor del producto.
  await expect(more.locator("summary")).toContainText(/Factura · IVA [\d,]+ % · Verdulería Demo/);
  await expect(panel.getByRole("radio", { name: /Cebolla/ })).toBeChecked();
  await expect(panel.getByRole("status").filter({ hasText: "Completá el producto" })).toBeVisible();
  // Cambia el resultado con «¿Incluye IVA?».
  await pickChoice(panel, "Para quién vale", "Todo el grupo (Grupo Demo)");
  // «2.600» son dos mil seiscientos.
  await panel.locator("#precio-envase").fill("2.600");
  const result = panel.getByRole("status").filter({ hasText: "Queda" });
  await expect(result).toContainText(/por kg sin IVA: (sube|baja) /);
  const withVat = await result.textContent();
  await panel.getByRole("button", { name: "¿Incluye IVA?" }).click();
  await expect(result).not.toHaveText(withVat ?? "");
  // La fecha, con «Cambiar».
  await expect(panel.getByText(/^Desde hoy, /)).toBeVisible();
  await panel.getByRole("button", { name: "Cambiar la fecha" }).click();
  await expect(panel.locator("#precio-desde")).toBeFocused();
  // Un error en «Más datos» lo abre y lleva el foco.
  await more.locator("summary").click();
  await panel.locator("#precio-descuento").fill("9000");
  await more.locator("summary").click();
  await expect(panel.locator("#precio-descuento")).toBeHidden();
  await expect(
    panel.getByRole("status").filter({ hasText: "Revisá el descuento para ver cómo queda." }),
  ).toBeVisible();
  await panel.locator("#precio-motivo").fill("Prueba de los cinco datos");
  await panel.getByRole("button", { name: "Proponer precio" }).click();
  await expect(panel.locator("#precio-descuento")).toBeVisible();
  await expect(
    panel.getByText("El descuento tiene que ser menor que el precio.").first(),
  ).toBeVisible();
  await expect(panel.locator("#precio-descuento")).toBeFocused();
  await axe(page);
  await noHorizontalScroll(page);
  // Sin factura, ni alícuota ni IVA.
  await panel.locator("#precio-descuento").fill("");
  await panel.getByText("Sin factura", { exact: true }).click();
  await expect(panel.locator("#precio-iva")).toBeHidden();
  await expect(panel.getByRole("button", { name: "¿Incluye IVA?" })).toBeHidden();
  await expect(more.locator("summary")).toContainText("Sin factura");
  await expect(result).not.toContainText("sin IVA");
});

test("dos propuestas seguidas: la segunda también lleva la alícuota y el proveedor del producto", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "Una vez alcanza: es el mismo formulario.");
  test.setTimeout(120_000);
  await login(page, "compras@ejemplo.test", { mfa: true });
  // Tomate perita: dos productos.
  await page.goto(ingredient(1));
  await page.getByRole("button", { name: "Proponer precio" }).filter({ visible: true }).click();
  const panel = page.getByRole("dialog", { name: "Proponer precio" });
  const summary = panel.locator("details").filter({ hasText: "Más datos" }).locator("summary");
  const first = panel.getByRole("group", { name: "Qué producto" }).locator("label").first();
  await first.click();
  await expect(summary).toContainText(/· Verdulería Demo/);
  const said = await summary.textContent();
  await pickChoice(panel, "Para quién vale", "La marca Demo Café");
  await panel.locator("#precio-envase").fill("12.345");
  await panel.locator("#precio-motivo").fill("Primera de dos");
  await panel.getByRole("button", { name: "Cambiar la fecha" }).click();
  await panel.getByRole("button", { name: "Proponer precio" }).click();
  await expect(notice(page).filter({ hasText: "Precio propuesto." })).toBeVisible();
  // Se limpió: la fecha vuelve a «hoy» y el producto, a elegir.
  await expect(panel.getByText(/^Desde hoy, /)).toBeVisible();
  await first.click();
  await expect(summary).toHaveText(said ?? "");
});

test("en el panel, lo que recibe el foco no queda tapado por el botón fijo", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "El recorrido con Tab es de la computadora.");
  test.setTimeout(120_000);
  await login(page, "compras@ejemplo.test", { mfa: true });
  for (const [width, height] of [
    [1440, 900],
    [1715, 843],
  ] as const) {
    await page.setViewportSize({ width, height });
    await page.goto(ingredient(1));
    await page.getByRole("button", { name: "Proponer precio" }).filter({ visible: true }).click();
    const panel = page.getByRole("dialog", { name: "Proponer precio" });
    const submit = panel.getByRole("button", { name: "Proponer precio" });
    // La acción, siempre a la vista.
    await expect(submit).toBeInViewport({ ratio: 1 });
    await panel.locator("details").filter({ hasText: "Más datos" }).locator("summary").click();
    await panel.getByRole("button", { name: "Cerrar" }).focus();
    for (let n = 0; n < 24; n++) {
      await page.keyboard.press("Tab");
      const hidden = await page.evaluate(() => {
        const el = document.activeElement;
        const bar = document.querySelector('[role="dialog"] button[type="submit"]')?.parentElement;
        if (!el || !bar || bar.contains(el)) return null;
        // Un radio de los botones es invisible: se mira su etiqueta.
        const box = (el.closest("label") ?? el).getBoundingClientRect();
        return box.top >= bar.getBoundingClientRect().top - 1 ? el.id || el.textContent : null;
      });
      expect(hidden).toBeNull();
    }
    await page.keyboard.press("Escape");
  }
});

test("si no se puede calcular, «Volver a calcular» conserva el foco", async ({
  page,
  isMobile,
}) => {
  test.skip(isMobile, "Una vez alcanza: es el mismo formulario.");
  test.setTimeout(120_000);
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto(ingredient(2));
  await page.getByRole("button", { name: "Proponer precio" }).filter({ visible: true }).click();
  const panel = page.getByRole("dialog", { name: "Proponer precio" });
  await pickChoice(panel, "Para quién vale", "Todo el grupo (Grupo Demo)");
  // Sin conexión al calcular.
  let cut = true;
  await page.route("**/materias-primas/**", (route) =>
    cut && route.request().method() === "POST" ? route.abort() : route.continue(),
  );
  await panel.locator("#precio-envase").fill("2.700");
  const again = panel.getByRole("button", { name: "Volver a calcular" });
  await expect(again).toBeVisible();
  await axe(page);
  await again.focus();
  await page.keyboard.press("Enter");
  await expect(panel.getByRole("status").filter({ hasText: "No pudimos calcular" })).toBeVisible();
  await expect(again).toBeFocused();
  cut = false;
  await page.keyboard.press("Enter");
  await expect(panel.getByRole("status").filter({ hasText: "Queda" })).toBeVisible();
});
