// Medidas, mermas y rendimientos (ADR-0040, pedido de Soy): «se compra congelada» de un clic con motivo, mermas en %
// con vista previa y aprobación, unidades «Kilogramo (kg)» y el rendimiento final destacado de una sub-receta. En
// celular y computadora, con axe. Cada proyecto usa su propia materia prima, así no se pisan. Ficha única (ADR-0043):
// se carga en la computadora (la barra de abajo y los paneles); en el celular la ficha es de consulta.
import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

import { login, notice, openAction, openSection } from "./helpers";

async function axe(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations).toEqual([]);
}

async function openIngredient(page: Page, name: string, section = "Mermas y rendimientos") {
  await page.goto(`/materias-primas?q=${encodeURIComponent(name)}`);
  await page.getByRole("link", { name, exact: true }).first().click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
  await openSection(page, section, "materia prima");
}

const kpi = (page: Page, label: string) =>
  page.locator('[data-slot="kpi"]').filter({ has: page.getByText(label, { exact: true }) });

test("Compras marca una materia prima como congelada (falta su merma, nunca se supone) y desmarcarla pide aprobación", async ({
  page,
  isMobile,
}) => {
  const name = isMobile ? "Bola de lomo" : "Nalga";
  await login(page, "compras@ejemplo.test");
  await openIngredient(page, name);
  await expect(kpi(page, "Merma de descongelado")).toContainText("No aplica");
  await axe(page);
  if (isMobile) {
    // En el celular se lee, sin el interruptor ni la barra para guardar.
    await expect(page.getByText(/^¿Se compra congelada\? No$/)).toBeVisible();
    await expect(page.getByRole("button", { name: /^¿Se compra congelada?/ })).toBeHidden();
    return;
  }

  const toggle = page.getByRole("button", { name: /^¿Se compra congelada?/ });
  await expect(toggle).toHaveAttribute("aria-pressed", "false");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-pressed", "true");
  // La palabra va al lado del botón: el estado nunca es solo color.
  await expect(page.locator("[id$='-congelada'] + span")).toHaveText("Sí");
  // Se guarda con la barra de abajo, con el resto de la ficha (ADR-0039).
  await expect(page.getByText("1 cambio sin guardar")).toBeVisible();
  await page.getByLabel("Motivo de los cambios", { exact: true }).fill("Viene congelada (prueba)");
  await page.getByRole("button", { name: "Guardar cambios", exact: true }).click();
  await expect(notice(page)).toContainText("Guardado: se compra congelada.");
  // Congelada y sin merma de descongelado aprobada: «—» y el motivo, nunca 0 %.
  const thawing = kpi(page, "Merma de descongelado");
  await expect(thawing).toContainText("—");
  await expect(thawing).toContainText("Se compra congelada y falta su merma aprobada.");
  await expect(kpi(page, "Rinde neto")).toContainText("—");

  // Desmarcarla baja el costo: queda pendiente hasta que la apruebe un Chef de todo el grupo (decisión de Joaco).
  await page.getByRole("button", { name: /^¿Se compra congelada?/ }).click();
  await page
    .getByLabel("Motivo de los cambios", { exact: true })
    .fill("Ahora viene fresca (prueba)");
  await page.getByRole("button", { name: "Guardar cambios", exact: true }).click();
  await expect(notice(page)).toContainText("Queda pendiente: dejar de comprarla congelada");
  await expect(page.getByText("Pedido pendiente: dejar de comprarla congelada")).toBeVisible();
  // Hasta que lo aprueben, sigue congelada.
  await expect(page.getByRole("button", { name: /^¿Se compra congelada?/ })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  await axe(page);
});

test("la Chef propone una merma con vista previa y queda en revisión", async ({
  page,
  isMobile,
}) => {
  const name = isMobile ? "Panceta" : "Comino";
  await login(page, "chef@ejemplo.test");
  await openIngredient(page, name);
  await expect(kpi(page, "Merma de limpieza")).toContainText("Sin merma de limpieza aprobada.");
  if (isMobile) {
    await expect(page.getByRole("button", { name: "Proponer merma o rendimiento" })).toBeHidden();
    return;
  }
  // Un solo botón para mermas y rendimientos; de entrada, la merma.
  await page.getByRole("button", { name: "Proponer merma o rendimiento" }).click();
  await expect(page.getByRole("radio", { name: "Merma" })).toBeChecked();
  const preview = page.getByRole("status").filter({ hasText: "Vista previa" });
  await expect(preview).toContainText("Falta la merma de limpieza.");
  await page.getByLabel("Merma de limpieza (%)").fill("12,5");
  await expect(preview).toContainText("Rinde 87,5 % neto");
  // 0 % sin declararlo no se acepta.
  await page.getByLabel("Merma de limpieza (%)").fill("0");
  await page.locator("#mp-motivo-merma").fill("Pesado en la cocina (prueba)");
  await page.getByRole("button", { name: "Proponer mermas" }).click();
  await expect(page.getByText("Con 0 % de merma, marcá que no tiene merma.")).toBeVisible();
  await page.getByLabel("Merma de limpieza (%)").fill("12,5");
  await page.getByRole("button", { name: "Proponer mermas" }).click();
  await expect(notice(page)).toContainText("Queda pendiente: la tiene que aprobar un Chef");
  await axe(page);
  await page.keyboard.press("Escape");
  await expect(page.getByText("1 merma en revisión")).toBeVisible();
  // Hasta que la aprueben, el costo no cambia: la limpieza sigue sin dato.
  await expect(kpi(page, "Merma de limpieza")).toContainText("—");
  await axe(page);
});

test("las unidades se eligen como «Kilogramo (kg)» y Compras suma una nueva", async ({
  page,
  isMobile,
}, testInfo) => {
  await login(page, "compras@ejemplo.test");
  if (!isMobile) {
    await openIngredient(page, "Comino", "Precios de compra");
    await page.getByRole("button", { name: "Agregar producto de compra" }).click();
    const content = page.locator("#mp-content_unit");
    await expect(content.locator("optgroup[label='Volumen']")).toContainText("Cucharada (cda)");
    await expect(content.locator("option", { hasText: "Kilogramo (kg)" })).toHaveCount(1);
    await page.keyboard.press("Escape");
  }

  await page.goto("/materias-primas/configuracion");
  const units = page.getByRole("list", { name: "Unidades de volumen" });
  // Si el nombre ya es la abreviatura, no se repite: «Taza».
  await expect(units).toContainText("Taza= 240 ml");
  await openAction(page, "Nueva unidad");
  const code = testInfo.project.name === "celular" ? "cucharon_cel" : "cucharon_comp";
  // Los tipos son botones a la vista (radios): se elige tocando la opción.
  await page.getByRole("group", { name: "Tipo" }).getByText("Volumen", { exact: true }).click();
  await expect(page.getByRole("radio", { name: "Volumen" })).toBeChecked();
  await page.locator("#cfg-unidad-nombre").fill(`Cucharón ${testInfo.project.name}`);
  await page.locator("#cfg-unidad-abrev").fill("cuch");
  await page.locator("#cfg-unidad-codigo").fill(code);
  await page.locator("#cfg-unidad-factor").fill("60");
  await page.locator("#cfg-unidad-motivo").fill("La usamos en la cocina (prueba)");
  await page.getByRole("button", { name: "Crear unidad" }).click();
  await expect(notice(page)).toContainText(`Unidad «Cucharón ${testInfo.project.name}» creada.`);
  await expect(units).toContainText(`Cucharón ${testInfo.project.name} (cuch)`);
  await axe(page);

  // Nada la usa: se puede dar de baja (así se corrige un error de carga). Así tampoco queda en la base.
  const label = `Cucharón ${testInfo.project.name} (cuch)`;
  await openAction(page, `Dar de baja «${label}»`);
  const archive = page.getByRole("group").filter({ hasText: `Dar de baja «${label}»` });
  await archive.getByLabel("Motivo de la baja").fill("Era de prueba");
  await archive.getByRole("button", { name: "Dar de baja", exact: true }).click();
  await expect(units).not.toContainText(label);
});

test("la sub-receta muestra su rendimiento final y la merma de cocción, sin suponer", async ({
  page,
  isMobile,
}) => {
  // El Chef del grupo trabaja las recetas del grupo (la Chef de marca solo ve su ficha de cocina).
  await login(page, "chefgrupo@ejemplo.test");
  await page.goto("/recetas/00000000-0000-4000-8000-000000001102");
  await expect(page.getByRole("heading", { name: "Salsa bolognesa", exact: true })).toBeVisible();
  // Ficha única (ADR-0042): el peso neto es el rendimiento final, y el rendimiento (neto ÷ bruto) reemplaza a la
  // merma de cocción, con la misma cuenta.
  await openSection(page, "Rendimiento");
  if (isMobile) {
    // En el celular la ficha es de consulta: el peso neto se lee.
    await expect(page.locator('[id^="rendimiento-"]:visible')).toContainText("3 kg");
  } else {
    await expect(page.getByLabel("Peso neto total")).toHaveValue("3");
    await expect(page.getByLabel("Unidad", { exact: true })).toHaveValue("kg");
  }
  // Lleva vino y aceite en ml sin densidad: el rendimiento no se inventa.
  const loss = kpi(page, "Rendimiento (neto ÷ bruto)");
  await expect(loss).toContainText("—");
  await expect(loss).toContainText("Falta pasar algún ingrediente a gramos");
  await expect(kpi(page, "Peso bruto total")).toContainText("—");
  await axe(page);
});
