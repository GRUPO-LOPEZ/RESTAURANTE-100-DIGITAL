// Calidad de datos (ADR-0033): qué mide cada indicador. Sin base de datos: lo usan pantallas y pruebas.
export type QualityAxis = "cook" | "cost";

export type QualityIndicator = {
  key: string;
  axis: QualityAxis;
  // Lo que se cuenta como cumplido, y cómo se llama lo que falta.
  label: string;
  missing: string;
  hint?: string;
};

export const QUALITY_INDICATORS: QualityIndicator[] = [
  {
    key: "recipe_approved",
    axis: "cook",
    label: "Recetas aprobadas",
    missing: "Recetas sin aprobar",
  },
  {
    key: "recipe_review",
    axis: "cook",
    label: "Recetas sin revisión pendiente",
    missing: "Recetas pendientes de revisión",
  },
  {
    key: "recipe_yield",
    axis: "cook",
    label: "Recetas con rendimiento",
    missing: "Recetas sin rendimiento",
  },
  { key: "recipe_photo", axis: "cook", label: "Recetas con foto", missing: "Recetas sin foto" },
  {
    key: "recipe_components",
    axis: "cook",
    label: "Recetas con todos sus componentes activos",
    missing: "Recetas con componentes inactivos",
  },
  {
    key: "recipe_cost",
    axis: "cost",
    label: "Recetas con costo completo",
    missing: "Recetas con costo por corregir",
  },
  {
    key: "ingredient_price",
    axis: "cost",
    label: "Materias primas con precio",
    missing: "Materias primas sin precio",
  },
  { key: "price_stale", axis: "cost", label: "Precios al día", missing: "Precios desactualizados" },
  {
    key: "ingredient_unit",
    axis: "cost",
    label: "Materias primas con unidad normalizada",
    missing: "Materias primas sin unidad normalizada",
    hint: "Tienen un producto de compra activo que se convierte a su unidad de uso.",
  },
  {
    key: "ingredient_yield",
    axis: "cost",
    label: "Materias primas con rendimiento aprobado",
    missing: "Materias primas sin rendimiento aprobado",
  },
  {
    key: "ingredient_duplicate",
    axis: "cost",
    label: "Materias primas sin parecidos",
    missing: "Materias primas posiblemente duplicadas",
    hint: "Nombres o alias muy parecidos. Se revisa cada noche.",
  },
];

export const QUALITY_AXES: { axis: QualityAxis; title: string; text: string }[] = [
  { axis: "cook", title: "¿Listas para cocinar?", text: "Que la receta esté completa y aprobada." },
  { axis: "cost", title: "¿El costo es confiable?", text: "Que sus precios y datos estén bien." },
];

// Las columnas de la comparación entre locales.
export const QUALITY_COMPARE = [
  "recipe_approved",
  "recipe_cost",
  "ingredient_price",
  "price_stale",
];

export const QUALITY_PAGE = 50;
// La base compara de a 20 locales: cada uno tarda.
export const QUALITY_COMPARE_LIMIT = 20;

export function qualityIndicator(key: string | undefined): QualityIndicator | undefined {
  return QUALITY_INDICATORS.find((i) => i.key === key);
}

export function qualityPercent(done: number, total: number): number | null {
  return total > 0 ? Math.round((done / total) * 100) : null;
}

// Lo que más falta corregir, de mayor a menor.
export function qualityTop(
  counts: { indicator: string; done: number; total: number }[],
  limit: number,
): { key: string; label: string; count: number }[] {
  return counts
    .flatMap((c) => {
      const indicator = qualityIndicator(c.indicator);
      const count = c.total - c.done;
      return indicator && count > 0
        ? [{ key: indicator.key, label: indicator.missing, count }]
        : [];
    })
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label, "es"))
    .slice(0, limit);
}

// Dónde se corrige cada indicador (?seccion=). En la receta, ficha única (ADR-0042), la página lleva a la sección con
// su ancla; la materia prima sigue con pestañas (ADR-0036). Sin sección: el principio de la ficha.
const QUALITY_SECTION: Record<string, string> = {
  recipe_approved: "versiones",
  recipe_review: "versiones",
  recipe_yield: "rendimiento",
  recipe_photo: "fotos",
  recipe_components: "ingredientes",
  recipe_cost: "ingredientes",
  ingredient_price: "compra",
  price_stale: "compra",
  ingredient_unit: "compra",
  ingredient_yield: "rendimientos",
};

export function qualityHref(kind: string, id: string, indicator?: string): string {
  const base = kind === "recipe" ? `/recetas/${id}` : `/materias-primas/${id}`;
  const section = indicator ? QUALITY_SECTION[indicator] : undefined;
  return section ? `${base}?seccion=${section}` : base;
}
