// Rubros (ADR-0038): reglas de la pantalla, sin acceso a la base. Se prueban con Vitest.
// Un rubro es una categoría del primer nivel con código y clase: compra (MP), sub-recetas (SR) o menú (PL).

export type RubroClass = "purchase" | "subrecipe" | "menu";

// Los íconos posibles (ADR-0066): los mismos que catalog.category_icon, en el orden en que se ofrecen.
export const RUBRO_ICON_LABELS = {
  vegetable: "Verduras y frutas",
  meat: "Carnes",
  fish: "Pescados",
  dairy: "Lácteos y huevos",
  flour: "Harinas y pastas",
  oil: "Aceites",
  herb: "Hierbas y especias",
  pantry: "Almacén",
  drink: "Bebidas",
  cleaning: "Limpieza",
  packaging: "Descartables",
  preparation: "Preparación",
  dish: "Plato",
  dessert: "Postre",
} as const;
export type RubroIconKey = keyof typeof RUBRO_ICON_LABELS;
export const RUBRO_ICONS = Object.keys(RUBRO_ICON_LABELS) as RubroIconKey[];

export const RUBRO_DESCRIPTION_MAX = 500;

export type Rubro = {
  rubroClass: RubroClass;
  id: string;
  code: string;
  name: string;
  isActive: boolean;
  // Materias primas (compra) o recetas (sub-recetas y menú), sumando las de sus subcategorías.
  uses: number;
  // Recetas cargadas antes de los rubros que quedaron en uno de la otra clase.
  mismatched: number;
  // Solo en los de compra (ADR-0052): si sus materias primas se pueden usar en recetas (Limpieza y Descartables, no).
  usedInRecipes: boolean;
  icon: RubroIconKey;
};

// La ficha de un rubro (recipes.top_category_sheet).
export type RubroSheet = {
  rubroClass: RubroClass;
  id: string;
  code: string;
  name: string;
  icon: RubroIconKey;
  description: string | null;
  isActive: boolean;
  usedInRecipes: boolean;
  // El sello del último cambio: quien guarda no pisa lo de otra persona.
  stamp: string;
  subcategories: string[];
  // Solo en los de compra.
  ingredients: { total: number; active: number } | null;
  // De compra: las que usan sus materias primas. Sub-recetas y menú: las del rubro.
  recipes: { total: number; published: number; open: number };
};

// Lo que se edita en la ficha.
export type RubroDraft = {
  name: string;
  description: string;
  icon: RubroIconKey;
  usedInRecipes: boolean;
};

export type RubroChanges = {
  name?: string;
  description?: string | null;
  icon?: RubroIconKey;
  used_in_recipes?: boolean;
};

/** Solo lo que cambió, como lo espera recipes.save_top_category. Los espacios de más no son un cambio. */
export function rubroChanges(saved: RubroDraft, draft: RubroDraft): RubroChanges {
  const out: RubroChanges = {};
  if (draft.name.trim() !== saved.name) out.name = draft.name.trim();
  if (draft.description.trim() !== saved.description)
    out.description = draft.description.trim() || null;
  if (draft.icon !== saved.icon) out.icon = draft.icon;
  if (draft.usedInRecipes !== saved.usedInRecipes) out.used_in_recipes = draft.usedInRecipes;
  return out;
}

/** Lo que se estaba cambiando, sobre lo nuevo que dice la base: lo demás no se pisa con lo viejo. */
export function rebaseDraft(before: RubroDraft, draft: RubroDraft, saved: RubroDraft): RubroDraft {
  const c = rubroChanges(before, draft);
  return {
    name: c.name === undefined ? saved.name : draft.name,
    description: c.description === undefined ? saved.description : draft.description,
    icon: c.icon ?? saved.icon,
    usedInRecipes: c.used_in_recipes ?? saved.usedInRecipes,
  };
}

/** El panel de un filtro: por cantidad y después por nombre; los dados de baja, al final y solo si tienen algo. */
export function panelRubros(rubros: Rubro[]): Rubro[] {
  return arrangeRubros(
    rubros.filter((r) => r.isActive || r.uses > 0),
    "",
    "cantidad",
  );
}

export type RubroSort = "cantidad" | "az";

// Las pestañas, en el orden del pedido de Soy. "tab" es lo que va en la dirección (?clase=).
export const RUBRO_CLASSES: {
  rubroClass: RubroClass;
  tab: string;
  label: string;
  // Corto, para los botones de la clase.
  short: string;
  prefix: string;
  one: string;
  many: string;
}[] = [
  {
    rubroClass: "purchase",
    tab: "compra",
    label: "Rubros de compra",
    short: "De compra",
    prefix: "MP",
    one: "insumo",
    many: "insumos",
  },
  {
    rubroClass: "subrecipe",
    tab: "sub-recetas",
    label: "Rubros de preparación",
    short: "Preparación",
    prefix: "SR",
    one: "sub-receta",
    many: "sub-recetas",
  },
  {
    rubroClass: "menu",
    tab: "menu",
    label: "Rubros de carta",
    short: "Carta",
    prefix: "PL",
    one: "receta",
    many: "recetas",
  },
];

export function rubroClassFromTab(tab: string | undefined) {
  return RUBRO_CLASSES.find((c) => c.tab === tab) ?? RUBRO_CLASSES[0]!;
}

export function isRubroClass(value: unknown): value is RubroClass {
  return value === "purchase" || value === "subrecipe" || value === "menu";
}

// "Sin insumos", "1 insumo", "12 insumos".
export function usesLabel(rubroClass: RubroClass, n: number) {
  const c = RUBRO_CLASSES.find((x) => x.rubroClass === rubroClass)!;
  if (n === 0) return `Sin ${c.many}`;
  return `${new Intl.NumberFormat("es-AR").format(n)} ${n === 1 ? c.one : c.many}`;
}

// Porcentaje sobre el total de la pestaña. Con total 0 no hay porcentaje (nunca "0 %").
export function sharePercent(uses: number, total: number): number | null {
  if (total <= 0) return null;
  return Math.round((uses / total) * 100);
}

export type RubroSummary = {
  total: number;
  active: number;
  inactive: number;
  unused: number;
  // Suma de los usos de la pestaña: el denominador de los porcentajes.
  uses: number;
  mismatched: number;
};

export function summarize(rubros: Rubro[]): RubroSummary {
  return rubros.reduce<RubroSummary>(
    (s, r) => ({
      total: s.total + 1,
      active: s.active + (r.isActive ? 1 : 0),
      inactive: s.inactive + (r.isActive ? 0 : 1),
      unused: s.unused + (r.uses === 0 ? 1 : 0),
      uses: s.uses + r.uses,
      mismatched: s.mismatched + r.mismatched,
    }),
    { total: 0, active: 0, inactive: 0, unused: 0, uses: 0, mismatched: 0 },
  );
}

// Sin tildes ni mayúsculas, para buscar.
function plain(text: string) {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Filtra por nombre o código y ordena: los activos primero y los dados de baja al final; dentro de cada
// grupo, por cantidad (de mayor a menor) o de la A a la Z.
export function arrangeRubros(rubros: Rubro[], query: string, sort: RubroSort): Rubro[] {
  const q = plain(query.trim());
  const byName = (a: Rubro, b: Rubro) => a.name.localeCompare(b.name, "es");
  return rubros
    .filter((r) => !q || plain(r.name).includes(q) || plain(r.code).includes(q))
    .sort((a, b) => {
      if (a.isActive !== b.isActive) return a.isActive ? -1 : 1;
      if (sort === "cantidad" && a.uses !== b.uses) return b.uses - a.uses;
      return byName(a, b);
    });
}
