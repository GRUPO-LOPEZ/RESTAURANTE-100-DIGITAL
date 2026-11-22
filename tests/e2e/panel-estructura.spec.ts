// Panel de control en una pantalla (Tanda 1 de Soy, ADR-0061; antes ADR-0031). Controla lo mismo que antes con las
// pantallas nuevas: el Superadministrador da de alta una razón social, una marca y un local con su razón social y un
// área; la Directora de Marca crea locales de su marca sin elegir la razón social; el Gerente edita los datos de su
// local sin cerrarlo; la Cocinera no ve el panel. Y lo nuevo: el código y el nombre del local se arman solos, el local
// no abre sin sus datos obligatorios, la dirección se busca en Georef (de mentira) y las pantallas entran sin scroll en
// los 4 tamaños con quien edita y con quien solo lee (Dirección General). En celular y computadora, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Locator, type Page } from "@playwright/test";

import { inventedCuit, login, notice } from "./helpers";

const SCREENS = [
  { width: 1440, height: 900 },
  { width: 1600, height: 900 },
  { width: 1715, height: 843 },
  { width: 1920, height: 1080 },
];
const CENTRO = "/configuracion/locales/00000000-0000-4000-8000-000000000201";
const RAZON = "/configuracion/razones-sociales/00000000-0000-4000-8000-000000001501";

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

// Sin scroll de página en los 4 tamaños de la computadora (ADR-0046 y ADR-0051): lo que no entra se desplaza dentro
// de su tarjeta. Vuelve al tamaño del proyecto al final.
async function noScrollOnScreens(page: Page, url: string, ready: () => Promise<void>) {
  const before = page.viewportSize();
  for (const size of SCREENS) {
    await page.setViewportSize(size);
    await page.goto(url);
    await ready();
    const extra = await page.evaluate(() => {
      const s = document.scrollingElement as HTMLElement;
      return s.scrollHeight - s.clientHeight;
    });
    expect(extra, `${url} en ${size.width} × ${size.height}`).toBeLessThanOrEqual(0);
  }
  if (before) await page.setViewportSize(before);
}

// Las teselas del mapa no se le piden a OpenStreetMap en las pruebas.
async function quietTiles(page: Page) {
  await page.route("**/tile.openstreetmap.org/**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "image/png",
      body: Buffer.from(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=",
        "base64",
      ),
    }),
  );
}

const panelReady = (page: Page) => async () => {
  await expect(
    page.getByRole("heading", { level: 1, name: "¿Cómo está armado el grupo?" }),
  ).toBeVisible();
  await expect(page.getByRole("list", { name: "Marcas y locales" })).toBeVisible();
};
const placeReady = (page: Page, name: RegExp | string) => async () => {
  await expect(page.getByRole("heading", { level: 1, name })).toBeVisible();
  await expect(page.getByRole("region", { name: "Áreas" })).toBeVisible();
};

// Una opción de botones (radios ocultos con su etiqueta a la vista): se hace clic en la palabra, dentro de su grupo.
async function pick(scope: Page | Locator, group: RegExp, option: string) {
  await scope.getByRole("group", { name: group }).getByText(option, { exact: true }).click();
}

// La barra de abajo: motivo y Guardar cambios.
async function saveSheet(page: Page, reason: string) {
  await page.getByLabel("Motivo de los cambios").fill(reason);
  await page.getByRole("button", { name: "Guardar cambios" }).click();
}

// Un sufijo distinto por proyecto y corrida: los nombres y códigos son únicos en el grupo.
function suffix(projectName: string) {
  return `${projectName === "celular" ? "C" : "D"}${Date.now() % 1_000_000}`;
}

test("el Superadministrador da de alta una razón social, una marca y un local con su área", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === "celular",
    "En el celular el Panel es de consulta (ADR-0036).",
  );
  test.setTimeout(240_000);
  const n = suffix(testInfo.project.name);
  const cuit = inventedCuit(`30${String(Date.now()).slice(-8)}`);
  await quietTiles(page);
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/configuracion");
  await panelReady(page)();
  await noHorizontalScroll(page);
  await axe(page);

  // La razón social, en un modal corto: lleva a su ficha.
  await page.getByRole("button", { name: "Nueva razón social" }).click();
  await page.locator("#razon-nueva-nombre").fill(`Prueba ${n} S.R.L. (ficticia)`);
  await page.locator("#razon-nueva-cuit").fill(cuit);
  await pick(page, /Condición frente al IVA/, "Resp. inscripto");
  await page.locator("#razon-nueva-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear y completar la ficha" }).click();
  await expect(
    page.getByRole("heading", { level: 1, name: `Prueba ${n} S.R.L. (ficticia)` }),
  ).toBeVisible();
  await expect(notice(page).filter({ hasText: "Razón social creada" })).toBeVisible();
  // Un dato de la constancia y una actividad principal, en un guardado.
  await pick(page, /Forma jurídica/, "S.A.S.");
  await page.getByLabel("Código de la actividad").fill("561011");
  await page.getByLabel("Descripción de la actividad").fill("Restaurantes (prueba)");
  await page.getByRole("button", { name: "Agregar", exact: true }).click();
  await expect(page.getByText("2 cambios sin guardar")).toBeVisible();
  await saveSheet(page, "Datos de la constancia (prueba automática)");
  await expect(notice(page).filter({ hasText: "Cambios guardados." })).toBeVisible();
  await expect(page.getByText("Principal")).toBeVisible();
  await axe(page);

  // La marca, en la misma lista del Panel: el número se pone solo.
  await page.goto("/configuracion");
  await page.getByLabel("Nueva marca").fill(`Marca de prueba ${n}`);
  await page.getByLabel("Nombre corto").fill(`Prueba${n}`);
  await page.getByLabel("Motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear marca" }).click();
  const brandCode = new RegExp(`^\\d{2}-PRUEBA${n}$`);
  await expect(page.getByText(brandCode)).toBeVisible();

  // El local, en un modal corto: nombre y código armados por la base, En apertura.
  await page.getByRole("link", { name: "Nuevo local" }).click();
  await pick(page, /^Marca/, `Marca de prueba ${n}`);
  await page.getByLabel("Zona o ubicación").fill("Centro");
  await pick(page.getByRole("dialog"), /^Tipo/, "Cocina central");
  const preview = page.getByRole("dialog").locator("dl[aria-live=polite]");
  await expect(preview).toContainText(`Prueba${n} Centro`);
  await expect(preview).toContainText(`PRUEBA${n}-001`);
  await page.locator("#local-nuevo-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear y completar la ficha" }).click();
  await placeReady(page, `Prueba${n} Centro`)();
  await expect(
    page.getByText(`PRUEBA${n}-001 · Marca de prueba ${n} · Cocina central`),
  ).toBeVisible();
  await expect(page.getByText("En apertura").first()).toBeVisible();

  // No abre sin sus datos obligatorios (lo controla la base; la pantalla avisa antes).
  await pick(page, /^Estado/, "Abierto");
  await expect(
    page.getByText(/Para abrir el local falta: fecha de apertura, dirección/),
  ).toBeVisible();
  await saveSheet(page, "Intento de apertura sin datos (prueba)");
  await expect(
    page.getByText(/Para abrir el local falta: fecha de apertura, dirección/).first(),
  ).toBeVisible();
  await page.getByRole("button", { name: "Descartar" }).click();

  // Una dirección que Georef no encuentra se guarda igual: «Sin ubicar en el mapa».
  await page.getByLabel("Dirección").fill("Avenida Inexistente 1");
  await page.getByRole("button", { name: "Buscar" }).click();
  await expect(
    page.getByText("Sin ubicar en el mapa").filter({ visible: true }).first(),
  ).toBeVisible();
  // Una que sí: «Encontrada», con la provincia.
  await page.getByLabel("Dirección").fill("Calle Ficticia 900");
  await page.getByRole("button", { name: "Buscar" }).click();
  await expect(page.getByText("Encontrada").filter({ visible: true }).first()).toBeVisible();
  await page.getByLabel("Localidad").fill("Monserrat");
  await page.getByLabel("Teléfono").fill("011 4000-0900");
  await page.getByLabel("Código postal").fill("C1084");
  await page.getByLabel("Fecha de apertura").fill("2026-11-01");
  await page
    .getByLabel("Factura a nombre de")
    .selectOption({ label: `Prueba ${n} S.R.L. (ficticia)` });
  // Un área nueva, en la misma tarjeta.
  await page.getByLabel("Nueva área").fill("Pastelería");
  await page.getByRole("button", { name: "Agregar" }).click();
  await pick(page, /^Estado/, "Abierto");
  await saveSheet(page, "Apertura del local de prueba");
  await expect(notice(page).filter({ hasText: "Cambios guardados." })).toBeVisible();
  await expect(page.getByRole("list", { name: "Áreas" })).toContainText("Pastelería");
  await expect(page.locator("header, main").getByText("Abierto").first()).toBeVisible();
  await noHorizontalScroll(page);
  await axe(page);

  // Quitar el área no la borra: queda inactiva y se puede volver a usar.
  await page.getByRole("button", { name: "Quitar Pastelería" }).click();
  await saveSheet(page, "Área de prueba que no se usa");
  await expect(page.getByRole("button", { name: "Volver a usar Pastelería" })).toBeVisible();

  // Cerrar el local y la marca de prueba (otras pruebas cuentan los locales abiertos).
  await page.getByRole("button", { name: "Cerrar el local" }).click();
  await page.locator("#local-motivo-abrir").fill("Cierre al terminar la prueba automática");
  await page.getByRole("dialog").getByRole("button", { name: "Cerrar el local" }).click();
  await expect(page.getByText("Cerrado").first()).toBeVisible();
  await page.goto("/configuracion");
  await page.getByRole("button", { name: `Editar la marca Marca de prueba ${n}` }).click();
  await pick(page.getByRole("dialog"), /^Estado/, "Inactiva");
  await page.locator("#marca-editar-motivo").fill("Cierre al terminar la prueba automática");
  await page.getByRole("button", { name: "Guardar marca" }).click();
  await expect(page.getByText("Marca guardada.")).toBeVisible();
});

test("la Directora de Marca crea un local de su marca sin elegir la razón social", async ({
  page,
}, testInfo) => {
  test.skip(
    testInfo.project.name === "celular",
    "En el celular el Panel es de consulta (ADR-0036).",
  );
  test.setTimeout(120_000);
  const n = suffix(testInfo.project.name);
  await quietTiles(page);
  await login(page, "director@ejemplo.test", { mfa: true });
  await page.goto("/configuracion");
  await panelReady(page)();
  // No crea marcas ni razones sociales (eso es de todo el grupo).
  await expect(page.getByLabel("Nueva marca")).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Nueva razón social" })).toHaveCount(0);
  await page.getByRole("link", { name: "Nuevo local" }).click();
  await page.getByLabel("Zona o ubicación").fill(`Prueba ${n}`);
  await page.locator("#local-nuevo-motivo").fill("Alta de prueba automática");
  await page.getByRole("button", { name: "Crear y completar la ficha" }).click();
  await placeReady(page, `Demo Pastas Prueba ${n}`)();
  // La razón social se ve, pero no se elige.
  await expect(page.getByLabel("Factura a nombre de")).toHaveCount(0);
  await expect(page.getByText(/Sin razón social: su costo sin IVA queda incompleto/)).toBeVisible();
  await axe(page);
  await page.getByRole("button", { name: "Cerrar el local" }).click();
  await page.locator("#local-motivo-abrir").fill("Cierre al terminar la prueba automática");
  await page.getByRole("dialog").getByRole("button", { name: "Cerrar el local" }).click();
  await expect(page.getByText("Cerrado").first()).toBeVisible();
});

test("el Gerente edita los datos de su local, pero no lo cierra", async ({ page }, testInfo) => {
  test.skip(
    testInfo.project.name === "celular",
    "En el celular el Panel es de consulta (ADR-0036).",
  );
  await quietTiles(page);
  await login(page, "gerente@ejemplo.test", { mfa: true });
  await page.goto(CENTRO);
  await placeReady(page, "Demo Pastas Centro")();
  // Ve la razón social de su local, nunca un aviso falso de que no tiene.
  await expect(page.getByText("Demo Gastronomía S.R.L. (ficticia)").first()).toBeVisible();
  await expect(page.getByText(/Sin razón social/)).toHaveCount(0);
  // Ni cerrar, ni el tipo, ni el estado, ni la razón social.
  await expect(page.getByRole("button", { name: "Cerrar el local" })).toHaveCount(0);
  await expect(page.getByRole("radio", { name: "Cocina central" })).toHaveCount(0);
  await expect(page.getByRole("radio", { name: "En apertura" })).toHaveCount(0);
  await expect(page.getByLabel("Factura a nombre de")).toHaveCount(0);
  // Un teléfono distinto en cada corrida: si no, no hay cambio que guardar.
  const phone = `011 4555-${String(Date.now() % 10_000).padStart(4, "0")}`;
  await page.getByLabel("Teléfono").fill(phone);
  await saveSheet(page, "Teléfono nuevo (prueba automática)");
  await expect(notice(page).filter({ hasText: "Cambios guardados." })).toBeVisible();
  await expect(page.getByLabel("Teléfono")).toHaveValue(phone);
});

test("las pantallas entran sin scroll, con quien edita y con quien solo lee", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name === "celular", "Los 4 tamaños son de computadora.");
  test.setTimeout(180_000);
  await quietTiles(page);
  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await noScrollOnScreens(page, "/configuracion", panelReady(page));
  await noScrollOnScreens(page, CENTRO, placeReady(page, "Demo Pastas Centro"));
  await noScrollOnScreens(page, RAZON, async () => {
    await expect(
      page.getByRole("heading", { level: 1, name: "Demo Gastronomía S.R.L. (ficticia)" }),
    ).toBeVisible();
  });
});

test("Dirección General ve el Panel y las fichas, sin editar", async ({ page }, testInfo) => {
  test.setTimeout(180_000);
  await quietTiles(page);
  await login(page, "direccion@ejemplo.test", { mfa: true });
  await page.goto("/configuracion");
  await panelReady(page)();
  await expect(page.getByRole("link", { name: "Nuevo local" })).toHaveCount(0);
  await expect(page.getByLabel("Nueva marca")).toHaveCount(0);
  await noHorizontalScroll(page);
  await axe(page);
  await page.goto(CENTRO);
  await placeReady(page, "Demo Pastas Centro")();
  await expect(page.getByRole("button", { name: "Guardar cambios" })).toHaveCount(0);
  await expect(page.getByLabel("Teléfono")).toHaveCount(0);
  await noHorizontalScroll(page);
  await axe(page);
  if (testInfo.project.name !== "celular") {
    await noScrollOnScreens(page, "/configuracion", panelReady(page));
    await noScrollOnScreens(page, CENTRO, placeReady(page, "Demo Pastas Centro"));
  }
});

test("la Cocinera no ve el panel de control", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await expect(page.getByRole("link", { name: "Panel de control" })).toHaveCount(0);
  await page.goto("/configuracion");
  await expect(page.getByRole("heading", { level: 1, name: /^Hola, / })).toBeVisible();
});
