// Ficha única de materia prima (ADR-0043): lo que se edita, qué cambió contra lo guardado y qué se manda a la base. Sin
// React ni base de datos, para probarlo con Vitest. Las reglas (permisos, precios, aprobaciones) las decide la base.

import type { AllergenStatus, ConversionKind, DataSource } from "@/lib/catalog";

export const CONVERSION_KINDS: ConversionKind[] = ["density", "unit_weight"];

export type SheetConversion = {
  factor: string;
  source: DataSource | "";
  measured_on: string;
  measured_by: string;
};
export type SheetAllergen = { status: AllergenStatus | ""; source: DataSource | "" };

export type IngredientSheetData = {
  name: string;
  category_id: string;
  recipe_unit: string;
  purchase_unit: string;
  notes: string;
};

export type IngredientSheetDraft = {
  data: IngredientSheetData;
  aliases: string[];
  requiresThawing: boolean;
  // Una por tipo; null: no está cargada.
  conversions: Record<ConversionKind, SheetConversion | null>;
  allergens: Record<string, SheetAllergen>;
};

const DATA_KEYS: (keyof IngredientSheetData)[] = [
  "name",
  "category_id",
  "recipe_unit",
  "purchase_unit",
  "notes",
];

// Los otros nombres se comparan como los guarda la base: en minúsculas, sin espacios de más y sin repetir.
export function normalizeAliases(list: string[]): string[] {
  return [...new Set(list.map((a) => a.trim().toLowerCase()).filter(Boolean))].sort();
}

// «harina fina, cuatro ceros» o uno por línea.
export function splitAliases(text: string): string[] {
  return text
    .split(/[\n,]/)
    .map((a) => a.trim())
    .filter(Boolean);
}

function sameConversion(a: SheetConversion | null, b: SheetConversion | null): boolean {
  if (a === null || b === null) return a === b;
  return (
    a.factor.trim() === b.factor.trim() &&
    a.source === b.source &&
    a.measured_on === b.measured_on &&
    a.measured_by.trim() === b.measured_by.trim()
  );
}

function sameAllergen(a: SheetAllergen | undefined, b: SheetAllergen | undefined): boolean {
  const x = a ?? { status: "", source: "" };
  const y = b ?? { status: "", source: "" };
  // Sin dato, la fuente no cuenta: la base la borra.
  return x.status === y.status && (x.status === "" || x.source === y.source);
}

export type SheetChanges = {
  data: (keyof IngredientSheetData)[];
  aliases: boolean;
  thawing: boolean;
  conversions: ConversionKind[];
  allergens: string[];
};

export function sheetChanges(
  saved: IngredientSheetDraft,
  draft: IngredientSheetDraft,
): SheetChanges {
  return {
    data: DATA_KEYS.filter((k) => draft.data[k].trim() !== saved.data[k].trim()),
    aliases:
      normalizeAliases(draft.aliases).join("\n") !== normalizeAliases(saved.aliases).join("\n"),
    thawing: draft.requiresThawing !== saved.requiresThawing,
    conversions: CONVERSION_KINDS.filter(
      (k) => !sameConversion(saved.conversions[k], draft.conversions[k]),
    ),
    allergens: [...new Set([...Object.keys(saved.allergens), ...Object.keys(draft.allergens)])]
      .filter((id) => !sameAllergen(saved.allergens[id], draft.allergens[id]))
      .sort(),
  };
}

// Cada campo, cada conversión y cada alérgeno cuenta uno («3 cambios sin guardar»).
export function countSheetChanges(c: SheetChanges): number {
  return (
    c.data.length +
    (c.aliases ? 1 : 0) +
    (c.thawing ? 1 : 0) +
    c.conversions.length +
    c.allergens.length
  );
}

// Lo que va a catalog.save_ingredient_sheet: solo los bloques que cambiaron (los demás, null, no se tocan).
export function sheetPayload(saved: IngredientSheetDraft, draft: IngredientSheetDraft) {
  const c = sheetChanges(saved, draft);
  return {
    data:
      c.data.length > 0 ? Object.fromEntries(c.data.map((k) => [k, draft.data[k].trim()])) : null,
    aliases: c.aliases ? normalizeAliases(draft.aliases) : null,
    requiresThawing: c.thawing ? draft.requiresThawing : null,
    conversions:
      c.conversions.length > 0
        ? c.conversions.map((kind) => {
            const v = draft.conversions[kind];
            // Quitada: la base la borra (borrado lógico).
            return v === null
              ? { removed: true as const, kind }
              : {
                  removed: false as const,
                  kind,
                  factor: v.factor.trim(),
                  source: v.source,
                  measured_on: v.measured_on,
                  measured_by: v.measured_by.trim(),
                };
          })
        : null,
    allergens:
      c.allergens.length > 0
        ? c.allergens.map((id) => {
            const v = draft.allergens[id] ?? { status: "", source: "" };
            return {
              allergen_id: id,
              status: v.status || null,
              source: v.status ? v.source || null : null,
            };
          })
        : null,
  };
}

// El estado del precio de un producto, siempre con una palabra (nunca solo color).
export function priceState(row: {
  status: string;
  stale: boolean | null;
  daysOld: number | null;
  inherited: boolean | null;
}): { status: "ok" | "warn" | "info" | "none"; label: string } {
  if (row.status === "missing_price") return { status: "none", label: "Sin precio" };
  if (row.status === "missing_legal_entity")
    return { status: "warn", label: "Falta la razón social" };
  if (row.stale)
    return {
      status: "warn",
      label: row.daysOld === null ? "Atención: vencido" : `Atención: ${row.daysOld} días`,
    };
  if (row.inherited) return { status: "info", label: "Heredado" };
  return { status: "ok", label: "Vigente" };
}
