// Layout global (ADR-0036): barra lateral fija, barra superior, selector global de local, búsqueda y, en
// el celular, la barra inferior. En computadora (1440, 1600 y 1920 px) y celular, con axe.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { chooseLocal, login, menuLink } from "./helpers";

test.describe.configure({ timeout: 90_000 });

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
}

test("en la computadora: barra lateral fija, sin scroll, y se contrae y lo recuerda", async ({
  page,
}, info) => {
  test.skip(info.project.name !== "computadora", "La barra lateral es de la computadora.");
  await login(page, "controller@ejemplo.test", { mfa: true });
  for (const width of [1440, 1600, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto("/recetas");
    const sidebar = page.locator("aside[data-sidebar]");
    await expect(sidebar).toBeVisible();
    // Fija: no se mueve con el contenido.
    await page.mouse.wheel(0, 2000);
    await expect(sidebar).toHaveCSS("position", "fixed");
    expect((await sidebar.boundingBox())?.width).toBe(240);
    // Toda la navegación entra sin scroll.
    const nav = sidebar.getByRole("navigation", { name: "Menú principal" });
    const scrolls = await nav.evaluate((el) => {
      const list = el.firstElementChild as HTMLElement;
      return list.scrollHeight > list.clientHeight;
    });
    expect(scrolls).toBe(false);
    // El activo va marcado.
    await expect(nav.getByRole("link", { name: "Recetas", exact: true })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await expect(page.getByRole("navigation", { name: "Ruta" })).toContainText("Grupo LF");
    await noHorizontalScroll(page);
    await axe(page);
  }

  // Entre 800 y 1280 px la barra superior tampoco se desborda (el buscador queda como botón).
  for (const width of [800, 1024]) {
    await page.setViewportSize({ width, height: 800 });
    // La búsqueda ya usa el diseño nuevo; las pantallas de cada módulo se migran en los PR 2 a 4.
    await page.goto("/buscar?q=salsa");
    await expect(page.getByRole("link", { name: "Ir a la búsqueda global" })).toBeVisible();
    const header = page.locator("header").first();
    expect(await header.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(0);
    await noHorizontalScroll(page);
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.getByRole("button", { name: "Contraer el menú" }).click();
  await expect(page.locator("aside[data-sidebar]")).toHaveAttribute("data-sidebar", "collapsed");
  expect((await page.locator("aside[data-sidebar]").boundingBox())?.width).toBe(68);
  // Se recuerda al volver a entrar.
  await page.reload();
  await expect(page.locator("aside[data-sidebar]")).toHaveAttribute("data-sidebar", "collapsed");
  await axe(page);
  await page.getByRole("button", { name: "Expandir el menú" }).click();
  await expect(page.locator("aside[data-sidebar]")).toHaveAttribute("data-sidebar", "expanded");
});

// Grupos plegados (ADR-0057): con muchos menús, abierto solo el grupo de la pantalla actual; el menú no tiene scroll ni
// en la pantalla más baja (1715 × 843), tampoco contraído.
test("con muchos menús, los grupos se pliegan y el menú entra", async ({ page }, info) => {
  test.skip(info.project.name !== "computadora", "La barra lateral es de la computadora.");
  // Visible: Next guarda ocultas las pantallas anteriores, cada una con su barra.
  const sidebar = page.locator("aside[data-sidebar]:visible");
  const nav = sidebar.getByRole("navigation", { name: "Menú principal" });
  // El grupo por su título (el título puede llevar después el número de avisos).
  const group = (name: string) =>
    sidebar
      .locator("details")
      .filter({ has: page.locator("summary", { hasText: new RegExp(`^${name}`) }) });
  const noScroll = async () => {
    const scrolls = await nav.evaluate((el) => {
      const list = el.firstElementChild as HTMLElement;
      return list.scrollHeight > list.clientHeight;
    });
    expect(scrolls).toBe(false);
  };

  await login(page, "superadmin@ejemplo.test", { mfa: true });
  await page.goto("/recetas");
  for (const size of [
    { width: 1440, height: 900 },
    { width: 1715, height: 843 },
  ]) {
    await page.setViewportSize(size);
    await expect(group("Base de conocimiento")).toHaveAttribute("open", "");
    await expect(group("Administración")).not.toHaveAttribute("open", "");
    await expect(nav.getByRole("link", { name: "Usuarios" })).toHaveCount(0);
    await noScroll();
  }
  await axe(page);

  // Un grupo cerrado no esconde sus avisos: el número del título es el de Aprobaciones adentro (o ninguno).
  const control = group("Control");
  await expect(control).not.toHaveAttribute("open", "");
  const badge = (await control.locator("summary").innerText()).match(/d+/)?.[0] ?? null;
  if (badge) await expect(control.locator("summary")).toContainText(`${badge} avisos sin leer`);
  await control.locator("summary").click();
  await expect(control).toHaveAttribute("open", "");
  const inside = nav.getByRole("link", { name: /^Aprobaciones/ });
  if (badge) await expect(inside).toContainText(badge);
  else await expect(inside).not.toContainText(/d/);
  // Abierto, el número ya no va en el título.
  await expect(control.locator("summary")).not.toContainText(/d/);

  // Con el teclado: el foco en el título de «Administración», Enter, y queda abierto. Se llega a Usuarios: allá queda
  // abierto su grupo.
  await group("Administración").locator("summary").focus();
  await page.keyboard.press("Enter");
  await expect(group("Administración")).toHaveAttribute("open", "");
  await nav.getByRole("link", { name: "Usuarios", exact: true }).click();
  await expect(page).toHaveURL(/\/usuarios$/);
  await expect(group("Administración")).toHaveAttribute("open", "");
  await expect(nav.getByRole("link", { name: "Usuarios", exact: true })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await noScroll();

  // Contraído (solo íconos) también entra.
  await page.getByRole("button", { name: "Contraer el menú" }).click();
  await expect(sidebar).toHaveAttribute("data-sidebar", "collapsed");
  await noScroll();
  await page.getByRole("button", { name: "Expandir el menú" }).click();
  await expect(sidebar).toHaveAttribute("data-sidebar", "expanded");
});

test("con pocos menús, todo queda abierto", async ({ page }, info) => {
  test.skip(info.project.name !== "computadora", "La barra lateral es de la computadora.");
  await login(page, "jefecocina@ejemplo.test");
  await page.setViewportSize({ width: 1715, height: 843 });
  await page.goto("/recetas");
  const groups = page.locator("aside[data-sidebar] details");
  await expect(groups.first()).toBeVisible();
  for (const g of await groups.all()) await expect(g).toHaveAttribute("open", "");
});

test("la navegación muestra solo lo que cada uno puede usar", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/");
  await expect(await menuLink(page, "Recetas")).toBeVisible();
  for (const name of ["Costos", "Reportes", "Usuarios", "Historial", "Panel de control"]) {
    await expect(
      page.getByRole("navigation", { name: "Menú principal" }).getByRole("link", { name }),
    ).toHaveCount(0);
  }
});

test("en el celular: barra inferior con cuatro accesos y el menú completo", async ({
  page,
}, info) => {
  test.skip(info.project.name !== "celular", "La barra inferior es del celular.");
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/");
  await expect(page.locator("aside[data-sidebar]")).toBeHidden();
  const bottom = page.getByRole("navigation", { name: "Navegación del celular" });
  await expect(bottom.getByRole("link")).toHaveText(["Inicio", "Recetas", "Reportes", /^Control/]);
  await bottom.getByRole("link", { name: "Recetas" }).click();
  await expect(page).toHaveURL(/\/recetas$/);
  await expect(bottom.getByRole("link", { name: "Recetas" })).toHaveAttribute(
    "aria-current",
    "page",
  );
  await (await menuLink(page, "Costos")).click();
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await noHorizontalScroll(page);
  await axe(page);
});

test("el selector global de local cambia el local y lo conserva", async ({ page }) => {
  await login(page, "controller@ejemplo.test", { mfa: true });
  await page.goto("/recetas");
  await chooseLocal(page, { label: "Demo Pastas Centro · PASTAS" });
  await page.goto("/costos");
  await expect(page.getByLabel("Local activo")).toHaveValue("00000000-0000-4000-8000-000000000201");
  // Vuelve a "Todos mis locales" para no cambiar otras pruebas.
  await chooseLocal(page, { label: "Todos mis locales" });
  await page.reload();
  await expect(page.getByLabel("Local activo")).toHaveValue("");
});

test("quien tiene un solo local no ve el selector", async ({ page }) => {
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/recetas");
  await expect(page.getByRole("heading", { level: 1, name: "Recetas" })).toBeVisible();
  await expect(page.getByLabel("Local activo")).toHaveCount(0);
});

test("la búsqueda global trae recetas y materias primas que la persona puede ver", async ({
  page,
}, info) => {
  await login(page, "chef@ejemplo.test");
  await page.goto("/");
  if (info.project.name === "computadora") {
    const box = page.getByRole("searchbox", {
      name: "Búsqueda global de recetas y materias primas",
    });
    await box.fill("salsa");
    await box.press("Enter");
  } else {
    await page.locator("summary:visible", { hasText: "Menú" }).click();
    await page
      .getByRole("searchbox", { name: "Búsqueda global de recetas y materias primas" })
      .fill("salsa");
    await page.getByRole("button", { name: "Hacer la búsqueda" }).click();
  }
  await expect(page).toHaveURL(/\/buscar\?q=salsa/);
  await expect(page.getByRole("list", { name: "Recetas" })).toContainText("Salsa bolognesa");
  await expect(page.getByRole("heading", { name: "Materias primas" })).toBeVisible();
  await axe(page);
  await noHorizontalScroll(page);

  // La Cocinera no ve el catálogo: solo el bloque de recetas.
  await page.context().clearCookies();
  await login(page, "cocinero@ejemplo.test");
  await page.goto("/buscar?q=salsa");
  await expect(page.getByRole("heading", { name: "Recetas", exact: true })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Materias primas" })).toHaveCount(0);
});
