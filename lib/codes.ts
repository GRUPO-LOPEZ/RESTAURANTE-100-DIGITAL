import type { RecipeType } from "@/lib/recipe-format";

// Códigos automáticos (ADR-0041): la base arma el código (PLA-CAF-0001, PRE-SAL-0001, MPR-CAR-0001) y estas
// funciones solo deciden qué se muestra mientras se completa el alta. Sin acceso a la base: las usan el
// formulario del navegador y las pruebas.

// Lo que muestra el campo «Código» del alta. La vista previa llega de la base cuando ya hay tipo y rubro.
export function codePreviewText({
  ready,
  loading,
  code,
}: {
  ready: boolean;
  loading: boolean;
  code: string | null;
}): string {
  if (!ready) return "Se arma al elegir el rubro";
  if (loading) return "Calculando…";
  return code ?? "Sin código para ese rubro";
}

// El aviso cuando, al crear, salió otro código que el de la vista previa (alguien creó otra en el medio).
export function codeChangedNotice(
  expected: string | null | undefined,
  assigned: string,
): string | null {
  const shown = (expected ?? "").trim().toUpperCase();
  if (!shown || shown === assigned) return null;
  return `Se creó con el código ${assigned}: el ${shown} lo tomó otra alta mientras cargabas.`;
}

// A dónde va el alta: la ficha, y si salió otro código, con el aviso. Viaja solo una marca fija y el código previsto
// (validado), nunca el texto del aviso: la ficha lo arma comparándolo con su propio código.
const CODE = /^[A-Z0-9][A-Z0-9-]{1,29}$/;

export function codeChangedHref(
  path: string,
  expected: string | null | undefined,
  assigned: string | null | undefined,
): string {
  const shown = (expected ?? "").trim().toUpperCase();
  if (!assigned || !CODE.test(shown) || codeChangedNotice(shown, assigned) === null) return path;
  return `${path}?aviso=codigo&previsto=${encodeURIComponent(shown)}`;
}

// El aviso de la ficha a partir de la dirección (?aviso=codigo&previsto=…) y del código real del registro.
export function codeNoticeFromQuery(
  aviso: string | undefined,
  previsto: string | undefined,
  code: string,
): string | null {
  if (aviso !== "codigo" || !previsto || !CODE.test(previsto)) return null;
  return codeChangedNotice(previsto, code);
}

// Las pestañas del listado de recetas: Platos y Preparaciones. Las preparaciones incluyen los componentes por
// unidad que ya existían.
export const RECIPE_LIST_TABS = [
  { value: "platos", label: "Platos", types: ["dish"], rubroClass: "menu" },
  {
    value: "preparaciones",
    label: "Preparaciones",
    types: ["preparation", "unit_component"],
    rubroClass: "subrecipe",
  },
] as const satisfies readonly {
  value: string;
  label: string;
  types: readonly RecipeType[];
  rubroClass: "menu" | "subrecipe";
}[];
export type RecipeListTab = (typeof RECIPE_LIST_TABS)[number];

export function recipeListTab(value: string | undefined): RecipeListTab {
  return RECIPE_LIST_TABS.find((t) => t.value === value) ?? RECIPE_LIST_TABS[0];
}

// «Se usa en recetas en»: se puede elegir cualquier medida, pero la base guarda la de su tipo (g, ml o unidad),
// que es la que usa el motor de costos (decisión de Joaco, ADR-0041).
export type Dimension = "mass" | "volume" | "count" | "package";

const BASE_NAME: Record<Exclude<Dimension, "package">, string> = {
  mass: "gramos (g)",
  volume: "mililitros (ml)",
  count: "unidades",
};

export function baseUnitNote(dimension: Dimension | null | undefined): string | null {
  if (!dimension || dimension === "package") return null;
  return `Las recetas la calculan en ${BASE_NAME[dimension]}.`;
}
