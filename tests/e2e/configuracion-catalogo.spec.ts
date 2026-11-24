// Configuración del catálogo en una pantalla (Tanda 2 de Soy, ADR-0063; antes ADR-0022): las 8 listas a la izquierda y la
// elegida en una tabla que se edita en el lugar y se guarda junta, con motivo. Compras crea una subcategoría dentro de un
// rubro (los rubros se crean en Rubros, ADR-0038) y ya la puede elegir al cargar una materia prima; cada uno edita sus
// listas y ve las demás en lectura; la Cocinera no entra. En la computadora se edita; en el celular, de consulta. Con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, logout, notice } from "./helpers";

const SETTINGS = "/materias-primas/configuracion";
const SCREENS = [
  { width: 1440, height: 900 },
  { width: 1600, height: 900 },
  { width: 1715, height: 843 },
  { width: 1920, height: 1080 },
];
const SLUGS = [
  "categorias",
  "categorias-de-recetas",
  "sectores",
  "partidas",
  "equipos",
  "medidas",
  "unidades",
  "procesos",
];

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function openList(page: Page, slug: string, title: string) {
  await page.goto(`${SETTINGS}?lista=${slug}`);
  await expect(page.getByRole("heading", { level: 2, name: title })).toBeVisible();
}

// La fila de un elemento: por su campo de nombre (cambia con lo que se escribe).
function row(page: Page, name: string) {
  return page.getByRole("row").filter({ has: page.getByLabel(`Nombre: ${name}`, { exact: true }) });
}

async function save(page: Page, reason: string) {
  await page.getByLabel("Motivo de los cambios", { exact: true }).fill(reason);
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page).filter({ hasText: "Cambios guardados" })).toBeVisible();
  await expect(page.getByRole("status").filter({ hasText: "Sin cambios" })).toBeVisible();
}

function onlyDesk(projectName: string) {
  test.skip(projectName === "celular", "Las listas se editan en la computadora.");
}
// Distinto en cada corrida (un reintento no choca con lo anterior).
const unique = (what: string) => `${what} ${Date.now() % 1_000_000}`;

test("Compras crea una subcategoría, la usa en el alta, la da de baja vacía y la reactiva", async ({
  page,
}, testInfo) => {
  onlyDesk(testInfo.project.name);
  test.setTimeout(120_000);
  const name = unique("Prueba");
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto("/materias-primas");
  await page.getByRole("link", { name: "Configuración" }).click();
  await expect(page.getByRole("heading", { name: "Configuración del catálogo" })).toBeVisible();
  // Al entrar, la primera lista que administra.
  await expect(
    page.getByRole("heading", { level: 2, name: "Categorías de materias primas" }),
  ).toBeVisible();
  await expect(row(page, "Carnes")).toBeVisible();
  await axe(page);

  await page.getByRole("button", { name: "Agregar subcategoría" }).click();
  const fresh = page.getByLabel("Nombre: Subcategoría nueva", { exact: true });
  await expect(fresh).toBeFocused();
  await fresh.fill(name);
  // Sin rubro no se guarda: lo dice en el campo, con el foco.
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(page.getByText("Elegí el rubro.", { exact: true })).toBeVisible();
  await expect(page.getByLabel(`Rubro: ${name}`)).toBeFocused();
  await page.getByLabel(`Rubro: ${name}`).selectOption({ label: "Carnes" });
  await expect(page.getByRole("status").filter({ hasText: "1 cambio sin guardar" })).toBeVisible();
  // Sin motivo, tampoco.
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page)).toContainText("Escribí el motivo de los cambios.");
  await expect(page.getByLabel("Motivo de los cambios", { exact: true })).toBeFocused();
  await save(page, "Subcategoría de prueba automática");
  await expect(row(page, name)).toBeVisible();

  await page.goto("/materias-primas/nueva");
  await expect(
    page.locator("#mp-alta-categoria").getByRole("option", { name: `Carnes › ${name}` }),
  ).toHaveCount(1);

  // Vacía: se da de baja, y deja de aparecer.
  await openList(page, "categorias", "Categorías de materias primas");
  await page.getByRole("button", { name: `Activa: ${name}` }).click();
  await save(page, "Ya no se usa");
  await expect(row(page, name)).toHaveCount(0);
  await expect(page.getByRole("button", { name: `Activa: ${name}` })).toHaveCount(0);
  await page.goto("/materias-primas/nueva");
  await expect(
    page.locator("#mp-alta-categoria").getByRole("option", { name: `Carnes › ${name}` }),
  ).toHaveCount(0);

  // Y se reactiva, desde las inactivas.
  await openList(page, "categorias", "Categorías de materias primas");
  await page.getByRole("button", { name: /^Ver las inactivas/ }).click();
  const toggle = page.getByRole("button", { name: `Activa: ${name}` });
  await expect(toggle).toHaveAttribute("aria-pressed", "false");
  await toggle.click();
  await save(page, "Se vuelve a usar");
  await expect(page.getByRole("button", { name: `Activa: ${name}` })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  // Queda de baja: no deja nada para las demás pruebas.
  await page.getByRole("button", { name: `Activa: ${name}` }).click();
  await save(page, "Era de prueba");
  await axe(page);
});

test("un rubro no se da de baja desde la configuración: lleva a Rubros", async ({
  page,
}, testInfo) => {
  onlyDesk(testInfo.project.name);
  await login(page, "compras@ejemplo.test", { mfa: true });
  await openList(page, "categorias", "Categorías de materias primas");
  const item = row(page, "Carnes");
  await expect(item.getByRole("link", { name: "En Rubros: se da de baja Carnes" })).toHaveAttribute(
    "href",
    "/rubros",
  );
  await expect(page.getByRole("button", { name: "Activa: Carnes" })).toHaveCount(0);
  // Tampoco se crea un rubro desde acá: la subcategoría pide el suyo, de la lista.
  await page.getByRole("button", { name: "Agregar subcategoría" }).click();
  await expect(
    page.getByLabel("Rubro: Subcategoría nueva").locator("option", { hasText: "Ninguno" }),
  ).toHaveCount(0);
});

test("cada uno edita sus listas y ve las demás en lectura", async ({ page }, testInfo) => {
  onlyDesk(testInfo.project.name);
  test.setTimeout(120_000);
  // El Chef del grupo: los procesos sí, las categorías de materias primas no.
  await login(page, "chefgrupo@ejemplo.test");
  await openList(page, "procesos", "Procesos de rendimiento");
  await expect(row(page, "Pelado")).toBeVisible();
  await axe(page);
  await openList(page, "categorias", "Categorías de materias primas");
  await expect(page.getByText("Solo lectura. La administra Compras.").first()).toBeVisible();
  await expect(page.getByRole("cell", { name: "Carnes", exact: true })).toBeVisible();
  for (const name of ["Agregar subcategoría", "Guardar cambios"])
    await expect(page.getByRole("button", { name })).toHaveCount(0);
  await expect(page.getByRole("main").locator("input")).toHaveCount(0);
  await axe(page);
  // Las de la cocina, sí.
  await openList(page, "sectores", "Sectores");
  await expect(page.getByRole("button", { name: "Agregar sector" })).toBeVisible();
  await logout(page);

  // Compras: los procesos, en lectura; las de la cocina, sí.
  await login(page, "compras@ejemplo.test", { mfa: true });
  await openList(page, "procesos", "Procesos de rendimiento");
  await expect(
    page.getByText("Solo lectura. La administra un Chef de todo el grupo."),
  ).toBeVisible();
  await expect(page.getByRole("cell", { name: "Pelado", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Agregar proceso" })).toHaveCount(0);
  await openList(page, "medidas", "Medidas prácticas");
  await expect(page.getByRole("button", { name: "Agregar medida" })).toBeVisible();
});

test("una medida práctica se agrega, se corrige, se desactiva y se reactiva", async ({
  page,
}, testInfo) => {
  onlyDesk(testInfo.project.name);
  test.setTimeout(120_000);
  const name = unique("Puñado");
  await login(page, "chefgrupo@ejemplo.test");
  await openList(page, "medidas", "Medidas prácticas");
  await expect(row(page, "Taza")).toBeVisible();
  await page.getByRole("button", { name: "Agregar medida" }).click();
  await page.getByLabel("Nombre: Medida nueva", { exact: true }).fill(name);
  await page.getByLabel(`Contiene: ${name}`).fill("treinta");
  await page.getByLabel(`Se usa con: ${name}`).fill("Hierbas, verdes");
  // El error sale al dejar el campo.
  await expect(row(page, name).getByText("Escribí un número mayor que cero")).toBeVisible();
  await page.getByLabel(`Contiene: ${name}`).fill("30,5");
  await row(page, name).getByText("g", { exact: true }).click();
  await save(page, "La usa la partida de pastas");
  await expect(page.getByLabel(`Contiene: ${name}`)).toHaveValue("30,5");
  await expect(row(page, name).getByRole("radio", { name: "g", exact: true })).toBeChecked();
  await axe(page);

  // Un cambio se deshace en su fila.
  await page.getByLabel(`Contiene: ${name}`).fill("99");
  await page.getByRole("button", { name: `Deshacer los cambios de ${name}` }).click();
  await expect(page.getByLabel(`Contiene: ${name}`)).toHaveValue("30,5");
  await expect(page.getByRole("status").filter({ hasText: "Sin cambios" })).toBeVisible();

  // Repetida (con otras mayúsculas): la base lo dice y el borrador queda.
  await page.getByRole("button", { name: "Agregar medida" }).click();
  await page.getByLabel("Nombre: Medida nueva", { exact: true }).fill("TAZA");
  await page.getByLabel("Contiene: TAZA", { exact: true }).fill("200");
  await page.getByLabel("Motivo de los cambios", { exact: true }).fill("Repetida");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(notice(page)).toContainText("Ya hay un elemento con ese nombre en la lista");
  await page.getByRole("button", { name: "Quitar TAZA", exact: true }).click();

  // Se desactiva, se ve entre las inactivas y se reactiva.
  await page.getByRole("button", { name: `Activa: ${name}` }).click();
  await save(page, "Ya no se usa");
  await expect(row(page, name)).toHaveCount(0);
  await page.getByRole("button", { name: /^Ver las inactivas/ }).click();
  await page.getByRole("button", { name: `Activa: ${name}` }).click();
  await save(page, "Se usa otra vez");
  await page.getByRole("button", { name: `Activa: ${name}` }).click();
  await save(page, "Era de prueba");
});

test("la capacidad de un equipo va en una unidad o en palabras", async ({ page }, testInfo) => {
  onlyDesk(testInfo.project.name);
  test.setTimeout(120_000);
  const name = unique("Horno");
  await login(page, "chefgrupo@ejemplo.test");
  await openList(page, "equipos", "Equipos");
  await expect(page.getByLabel("Capacidad en palabras: Pastera")).toHaveValue("canastos");
  await page.getByRole("button", { name: "Agregar equipo" }).click();
  await page.getByLabel("Nombre: Equipo nuevo", { exact: true }).fill(name);
  await page.getByLabel(`Capacidad: ${name}`).fill("5");
  await page.getByRole("button", { name: "Guardar cambios" }).click();
  await expect(page.getByText("Elegí en qué.", { exact: true })).toBeVisible();
  await page.getByLabel(`En qué: ${name}`).selectOption({ label: "Kilogramo (kg)" });
  await save(page, "Equipo de prueba");
  await page.getByLabel(`En qué: ${name}`).selectOption({ label: "En palabras…" });
  await page.getByLabel(`Capacidad en palabras: ${name}`).fill("placas");
  await page.getByLabel(`Capacidad: ${name}`).fill("8");
  await save(page, "Se mide en placas");
  await expect(page.getByLabel(`Capacidad en palabras: ${name}`)).toHaveValue("placas");
  await axe(page);
  await page.getByRole("button", { name: `Activo: ${name}` }).click();
  await save(page, "Era de prueba");
});

test("cambiar de lista con cambios sin guardar avisa", async ({ page }, testInfo) => {
  onlyDesk(testInfo.project.name);
  await login(page, "chefgrupo@ejemplo.test");
  await openList(page, "partidas", "Partidas");
  await page.getByLabel("Nombre: Salsas", { exact: true }).fill("Salsas y fondos");
  let asked = "";
  page.once("dialog", (d) => {
    asked = d.message();
    void d.dismiss();
  });
  const lists = page.getByRole("navigation", { name: "Listas" });
  await lists.getByRole("link", { name: /^Equipos/ }).click();
  expect(asked).toBe("Tenés cambios sin guardar. ¿Salir igual?");
  await expect(page.getByLabel("Nombre: Salsas y fondos", { exact: true })).toBeVisible();
  // Sin cambios, pasa derecho.
  await page.getByRole("button", { name: "Descartar" }).click();
  await expect(page.getByLabel("Nombre: Salsas", { exact: true })).toBeVisible();
  await lists.getByRole("link", { name: /^Equipos/ }).click();
  await expect(page.getByRole("heading", { level: 2, name: "Equipos" })).toBeVisible();
  await expect(lists.getByRole("link", { name: /^Equipos/ })).toHaveAttribute(
    "aria-current",
    "page",
  );
});

test("sin scroll de página, con quien edita y con quien solo lee", async ({ page }, testInfo) => {
  onlyDesk(testInfo.project.name);
  test.setTimeout(240_000);
  // Cada lista la edita uno de los dos y la lee el otro (o la editan los dos).
  for (const email of ["compras@ejemplo.test", "chefgrupo@ejemplo.test"]) {
    await login(page, email, { mfa: email.startsWith("compras") });
    for (const size of SCREENS) {
      await page.setViewportSize(size);
      for (const slug of SLUGS) {
        await page.goto(`${SETTINGS}?lista=${slug}`);
        await expect(page.getByRole("main").getByRole("table")).toBeVisible();
        const extra = await page.evaluate(() => {
          const s = document.scrollingElement as HTMLElement;
          return Math.max(s.scrollHeight - s.clientHeight, s.scrollWidth - s.clientWidth);
        });
        expect(extra, `${slug} en ${size.width} × ${size.height}`).toBeLessThanOrEqual(0);
      }
    }
    await logout(page);
  }
});

test("en el celular es de consulta: la lista se elige con un desplegable", async ({
  page,
}, testInfo) => {
  test.skip(testInfo.project.name !== "celular", "Solo el celular.");
  await login(page, "compras@ejemplo.test", { mfa: true });
  await page.goto(SETTINGS);
  const picker = page.getByLabel("Lista", { exact: true });
  // La lista llega después del resto de la página: se mide cuando se ve.
  await expect(picker).toBeVisible();
  expect((await picker.boundingBox())?.height ?? 0).toBeGreaterThanOrEqual(44);
  await picker.selectOption("medidas");
  await page.getByRole("button", { name: "Ver", exact: true }).click();
  await expect(page.getByRole("heading", { level: 2, name: "Medidas prácticas" })).toBeVisible();
  const list = page.getByRole("list", { name: "Medidas prácticas" });
  await expect(list.getByRole("listitem").filter({ hasText: "Taza" })).toContainText("240 ml");
  await expect(page.getByText("Para editar, entrá desde la computadora.")).toBeVisible();
  for (const name of ["Agregar medida", "Guardar cambios"])
    await expect(page.getByRole("button", { name })).toBeHidden();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - window.innerWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
  await axe(page);
});

test("la Cocinera no ve la configuración ni entra", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/materias-primas");
  await expect(page.getByRole("link", { name: "Configuración" })).toHaveCount(0);
  await page.goto(SETTINGS);
  await expect(page).toHaveURL(/\/$/);
});
