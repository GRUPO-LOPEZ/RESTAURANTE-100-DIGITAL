import { fieldErrors, schemas } from "@/lib/forms/schemas";

// Configuración del catálogo en una pantalla (ADR-0063): las 8 listas, el borrador de una lista, qué cambió y lo que viaja
// a la base (catalog.save_settings_list). Sin React ni Supabase, para probarlo con Vitest.

export const SETTINGS_LISTS = [
  "ingredient_categories",
  "recipe_categories",
  "sectors",
  "stations",
  "equipment",
  "measures",
  "units",
  "processes",
] as const;
export type SettingsListCode = (typeof SETTINGS_LISTS)[number];

export function isSettingsList(value: unknown): value is SettingsListCode {
  return typeof value === "string" && (SETTINGS_LISTS as readonly string[]).includes(value);
}

export type SettingsListInfo = {
  // En la dirección: ?lista=medidas.
  slug: string;
  label: string;
  description: string;
  // El botón de agregar y el nombre de una fila nueva.
  add: string;
  newItem: string;
  // Quién la administra, para quien la ve en lectura.
  owner: string;
  // La columna de uso, y el nombre de la columna «Activa».
  uses: string | null;
  activeLabel: "Activa" | "Activo";
  nameMax: number;
};

const KITCHEN_OWNER = "La administran Compras y el Chef de todo el grupo.";

export const LIST_INFO: Record<SettingsListCode, SettingsListInfo> = {
  ingredient_categories: {
    slug: "categorias",
    label: "Categorías de materias primas",
    description:
      "Los rubros de compra y sus subcategorías (Lácteos › Quesos). Los rubros se crean y se dan de baja en Rubros.",
    add: "Agregar subcategoría",
    newItem: "Subcategoría nueva",
    owner: "La administra Compras.",
    uses: "Materias primas",
    activeLabel: "Activa",
    nameMax: 80,
  },
  recipe_categories: {
    slug: "categorias-de-recetas",
    label: "Categorías de recetas",
    description:
      "Los rubros de sub-recetas y de menú y sus subcategorías (Pastas › Rellenas). Los rubros se crean y se dan de baja en Rubros.",
    add: "Agregar subcategoría",
    newItem: "Subcategoría nueva",
    owner: "La administra un Chef de todo el grupo.",
    uses: "Recetas",
    activeLabel: "Activa",
    nameMax: 80,
  },
  sectors: {
    slug: "sectores",
    label: "Sectores",
    description: "Dónde se prepara: cocina caliente, cocina fría, pastelería.",
    add: "Agregar sector",
    newItem: "Sector nuevo",
    owner: KITCHEN_OWNER,
    uses: "Recetas",
    activeLabel: "Activo",
    nameMax: 60,
  },
  stations: {
    slug: "partidas",
    label: "Partidas",
    description: "Quién la prepara dentro del sector: pastas, salsas, parrilla.",
    add: "Agregar partida",
    newItem: "Partida nueva",
    owner: KITCHEN_OWNER,
    uses: "Recetas",
    activeLabel: "Activa",
    nameMax: 60,
  },
  equipment: {
    slug: "equipos",
    label: "Equipos",
    description:
      "Los equipos de los pasos de la receta, con lo que entra en cada uno. La capacidad va en una unidad (5 kg) o en palabras (6 canastos).",
    add: "Agregar equipo",
    newItem: "Equipo nuevo",
    owner: KITCHEN_OWNER,
    uses: "Recetas",
    activeLabel: "Activo",
    nameMax: 120,
  },
  measures: {
    slug: "medidas",
    label: "Medidas prácticas",
    description:
      "Lo que usa el cocinero en vez de pesar: cucharón, taza, cuchara. Con lo que contiene, el sistema calcula cuántas van.",
    add: "Agregar medida",
    newItem: "Medida nueva",
    owner: KITCHEN_OWNER,
    uses: null,
    activeLabel: "Activa",
    nameMax: 60,
  },
  units: {
    slug: "unidades",
    label: "Unidades de medida",
    description:
      "Las que se eligen al comprar y en las recetas. Las cuentas se hacen siempre en gramos, mililitros o unidades.",
    add: "Agregar unidad",
    newItem: "Unidad nueva",
    owner: "La administra Compras.",
    uses: null,
    activeLabel: "Activa",
    nameMax: 40,
  },
  processes: {
    slug: "procesos",
    label: "Procesos de rendimiento",
    description:
      "Lo que cambia el peso de una materia prima: pelado, desgrasado, hervido. Se usan en los ensayos y en el rendimiento estándar.",
    add: "Agregar proceso",
    newItem: "Proceso nuevo",
    owner: "La administra un Chef de todo el grupo.",
    uses: "Materias primas con estándar",
    activeLabel: "Activo",
    nameMax: 80,
  },
};

export function listFromSlug(slug: string | undefined): SettingsListCode | null {
  return SETTINGS_LISTS.find((l) => LIST_INFO[l].slug === slug) ?? null;
}

export const DIMENSIONS = [
  { value: "mass", label: "Peso" },
  { value: "volume", label: "Volumen" },
  { value: "count", label: "Unidades" },
  { value: "package", label: "Envase" },
] as const;
export const CONTENT_UNITS = [
  { value: "ml", label: "ml" },
  { value: "g", label: "g" },
  { value: "unit", label: "u" },
] as const;

// Una fila del borrador. Todos los campos son texto (como se escriben); cada lista usa los suyos.
export type ListFields = {
  name: string;
  parentId: string;
  code: string;
  capacity: string;
  // Código de la unidad, «palabras» (con capacityLabel) o vacío.
  capacityUnit: string;
  capacityLabel: string;
  content: string;
  contentUnit: string;
  usageNote: string;
  abbreviation: string;
  dimension: string;
  factor: string;
};
export type ListItem = {
  // El id, o «nuevo-N» en una fila sin guardar.
  key: string;
  id: string | null;
  fields: ListFields;
  active: boolean;
  // Lo que dice la base: si se puede editar, cuánto se usa y por qué no se puede dar de baja.
  editable: boolean;
  uses: number;
  why: string | null;
  isBase: boolean;
  baseUnit: string;
};

export const IN_WORDS = "palabras";

export const EMPTY_FIELDS: ListFields = {
  name: "",
  parentId: "",
  code: "",
  capacity: "",
  capacityUnit: "",
  capacityLabel: "",
  content: "",
  contentUnit: "ml",
  usageNote: "",
  abbreviation: "",
  dimension: "",
  factor: "",
};

export function newItem(n: number): ListItem {
  return {
    key: `nuevo-${n}`,
    id: null,
    fields: EMPTY_FIELDS,
    active: true,
    editable: true,
    uses: 0,
    why: null,
    isBase: false,
    baseUnit: "",
  };
}

// Los campos que se editan en una fila que ya existe (el rubro, el código, el tipo y la equivalencia no cambian).
const EDITABLE: Record<SettingsListCode, (keyof ListFields)[]> = {
  ingredient_categories: ["name"],
  recipe_categories: ["name"],
  sectors: ["name"],
  stations: ["name"],
  equipment: ["name", "capacity", "capacityUnit", "capacityLabel"],
  measures: ["name", "content", "contentUnit", "usageNote"],
  // Una unidad no cambia: la leen las recetas publicadas.
  units: [],
  processes: ["name"],
};

// Los campos de una fila, sin lo que no cuenta: los espacios, y la palabra de la capacidad si no va en palabras.
function clean(fields: ListFields): ListFields {
  const out = { ...fields };
  for (const k of Object.keys(out) as (keyof ListFields)[]) out[k] = out[k].trim();
  if (out.capacityUnit !== IN_WORDS) out.capacityLabel = "";
  return out;
}

export function isChanged(
  list: SettingsListCode,
  saved: ListItem | undefined,
  item: ListItem,
): boolean {
  if (!saved) return true;
  if (saved.active !== item.active) return true;
  const a = clean(saved.fields);
  const b = clean(item.fields);
  return EDITABLE[list].some((f) => a[f] !== b[f]);
}

export function changedKeys(
  list: SettingsListCode,
  saved: ListItem[],
  draft: ListItem[],
): Set<string> {
  const byKey = new Map(saved.map((s) => [s.key, s]));
  return new Set(draft.filter((d) => isChanged(list, byKey.get(d.key), d)).map((d) => d.key));
}

export type FieldErrors = Partial<Record<keyof ListFields, string>>;

const NUMBER = /^[0-9]{1,9}([.,][0-9]{1,6})?$/;
const positive = (text: string) => NUMBER.test(text) && Number(text.replace(",", ".")) > 0;

// Lo que le falta a una fila, campo por campo. La base lo vuelve a controlar al guardar.
export function itemErrors(list: SettingsListCode, item: ListItem): FieldErrors {
  const f = clean(item.fields);
  const info = LIST_INFO[list];
  const errors: FieldErrors = {};
  if (f.name === "") errors.name = "Escribí el nombre.";
  else if (f.name.length > info.nameMax) errors.name = `Hasta ${info.nameMax} caracteres.`;
  else if (/[<>]/.test(f.name)) errors.name = "Sin < ni >.";
  if (list === "equipment") {
    if (f.capacity !== "" && !positive(f.capacity))
      errors.capacity = "Escribí un número mayor que cero, por ejemplo 5,5.";
    else if (f.capacity !== "" && f.capacityUnit === "") errors.capacityUnit = "Elegí en qué.";
    else if (f.capacity === "" && f.capacityUnit !== "") errors.capacity = "Escribí cuánto entra.";
    if (f.capacityUnit === IN_WORDS && f.capacityLabel === "")
      errors.capacityLabel = "Escribí en qué, por ejemplo canastos.";
  }
  if (list === "measures" && !positive(f.content))
    errors.content = "Escribí un número mayor que cero, por ejemplo 120.";
  if (list === "units" && f.abbreviation === "") errors.abbreviation = "Escribí la abreviatura.";
  if (item.id !== null) return errors;
  // Lo que solo se carga al crear: con los mismos esquemas de siempre.
  if (list === "ingredient_categories" || list === "recipe_categories") {
    if (f.parentId === "") errors.parentId = "Elegí el rubro.";
  } else if (list === "processes") {
    const parsed = schemas.yieldProcess.safeParse({ code: f.code, name: f.name, reason: "-" });
    if (!parsed.success) {
      const e = fieldErrors(parsed.error);
      if (e.code) errors.code = e.code;
    }
  } else if (list === "units") {
    const parsed = schemas.unit.safeParse({
      code: f.code,
      long_name: f.name,
      abbreviation: f.abbreviation,
      dimension: f.dimension,
      factor: f.factor,
      reason: "-",
    });
    if (!parsed.success) {
      const e = fieldErrors(parsed.error);
      if (e.code) errors.code = e.code;
      if (e.dimension) errors.dimension = "Elegí el tipo.";
      if (e.factor) errors.factor = e.factor;
      if (e.abbreviation) errors.abbreviation = e.abbreviation;
    } else if (f.dimension !== "package" && !positive(f.factor)) {
      errors.factor = "Escribí cuánto vale en la unidad base.";
    }
  }
  return errors;
}

export type ListPayloadItem = { [key: string]: string | boolean };

/** Lo que viaja al guardar: de cada fila, solo lo que cambió. La capacidad del equipo viaja entera. */
export function listPayload(
  list: SettingsListCode,
  saved: ListItem[],
  draft: ListItem[],
): ListPayloadItem[] {
  const byKey = new Map(saved.map((s) => [s.key, s]));
  const out: ListPayloadItem[] = [];
  for (const item of draft) {
    const before = byKey.get(item.key);
    if (!isChanged(list, before, item)) continue;
    const f = clean(item.fields);
    const b = before ? clean(before.fields) : null;
    const row: ListPayloadItem = {};
    if (item.id) row.id = item.id;
    const diff = (field: keyof ListFields) => b === null || b[field] !== f[field];
    if (diff("name")) row.name = f.name;
    if (before ? before.active !== item.active : !item.active) row.active = item.active;
    if (
      list === "equipment" &&
      [diff("capacity"), diff("capacityUnit"), diff("capacityLabel")].some(Boolean)
    ) {
      row.capacity = f.capacity;
      row.capacity_unit = f.capacityUnit === IN_WORDS ? "" : f.capacityUnit;
      row.capacity_label = f.capacityUnit === IN_WORDS ? f.capacityLabel : "";
    }
    if (list === "measures") {
      if (diff("content")) row.content = f.content;
      if (diff("contentUnit")) row.content_unit = f.contentUnit;
      if (diff("usageNote")) row.usage_note = f.usageNote;
    }
    if (list === "units" && diff("abbreviation")) row.abbreviation = f.abbreviation;
    if (!item.id) {
      if (list === "ingredient_categories" || list === "recipe_categories")
        row.parent_id = f.parentId;
      if (list === "processes") row.code = f.code.toUpperCase();
      if (list === "units") {
        row.code = f.code;
        row.dimension = f.dimension;
        row.factor = f.factor;
      }
    }
    out.push(row);
  }
  return out;
}

/** En las categorías, cada subcategoría va debajo de su rubro; las nuevas, al final hasta guardar (la fila no salta). */
export function inOrder(list: SettingsListCode, items: ListItem[]): ListItem[] {
  if (list !== "ingredient_categories" && list !== "recipe_categories") return items;
  const known = items.filter((i) => i.id !== null);
  return [
    ...known
      .filter((i) => i.fields.parentId === "")
      .flatMap((p) => [p, ...known.filter((i) => i.fields.parentId === p.id)]),
    ...items.filter((i) => i.id === null),
  ];
}

const plain = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 6, useGrouping: false });
const grouped = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 6 });
/** El número de un campo, para leer: «1000» → «1.000». */
export function readNumber(text: string): string {
  const n = Number(text.replace(",", "."));
  return text === "" || Number.isNaN(n) ? text : grouped.format(n);
}
/** El número como se escribe en un campo: 5.5 → «5,5». */
export const inputNumber = (v: number | null): string => (v === null ? "" : plain.format(v));
