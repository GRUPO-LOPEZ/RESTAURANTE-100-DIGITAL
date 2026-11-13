import { createClient } from "@/lib/supabase/server";
import type { Database } from "@/lib/database.types";

// Lecturas del catálogo de materias primas (Fase 2, etapa 2.1 A). Como en lib/data.ts: todo pasa
// por la base con la sesión de la persona (RLS con catalog.view) y, si una lectura falla, se corta
// con un error en lugar de mostrar "no hay datos".

type Catalog = Database["catalog"];
export type AllergenStatus = Catalog["Enums"]["allergen_status"];
export type DataSource = Catalog["Enums"]["data_source"];
export type ConversionKind = Catalog["Enums"]["conversion_kind"];

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export const INGREDIENTS_PAGE = 25;

export const ALLERGEN_STATUS_LABELS: Record<AllergenStatus, string> = {
  contains: "Contiene",
  may_contain: "Puede contener (trazas)",
  free_verified: "No contiene (verificado)",
};

export const SOURCE_LABELS: Record<DataSource, string> = {
  manual: "Carga manual",
  excel_import: "Importado de Excel",
  measured: "Medido en ensayo",
  supplier: "Informado por el proveedor",
  calculated: "Calculado por el sistema",
  estimated: "Estimado",
  verified: "Verificado por un responsable",
};

// label: «Kilogramo (kg)», como se muestra en los desplegables (ADR-0040).
export type Unit = {
  id: string;
  code: string;
  name: string;
  label: string;
  dimension: string;
  isBase: boolean;
};
// isActive: falso si el rubro (o su madre) está dado de baja (ADR-0038): no se ofrece para cargar.
export type Category = {
  id: string;
  groupId: string;
  // El rubro madre (null si es un rubro): para filtrar un rubro con sus subcategorías.
  parentId: string | null;
  name: string;
  label: string;
  isActive: boolean;
};
export type Supplier = { id: string; code: string; name: string; isInternal: boolean };

export async function getUnits(): Promise<Unit[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("units")
    .select("id, code, name, long_name, abbreviation, dimension, is_base")
    .order("dimension")
    .order("is_base", { ascending: false })
    .order("long_name");
  if (error) failed("las unidades");
  return data.map((u) => ({
    id: u.id,
    code: u.code,
    name: u.name,
    label:
      u.long_name.toLowerCase() === u.abbreviation.toLowerCase()
        ? u.long_name
        : `${u.long_name} (${u.abbreviation})`,
    dimension: u.dimension,
    isBase: u.is_base,
  }));
}

// Categorías con su madre: "Lácteos" o "Lácteos › Quesos".
export async function getCategories(): Promise<Category[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("ingredient_categories")
    .select("id, group_id, parent_id, name, is_active")
    .order("name");
  if (error) failed("las categorías");
  const byId = new Map(data.map((c) => [c.id, c]));
  return data
    .map((c) => {
      const parent = c.parent_id ? byId.get(c.parent_id) : undefined;
      return {
        id: c.id,
        groupId: c.group_id,
        parentId: c.parent_id,
        name: c.name,
        label: parent ? `${parent.name} › ${c.name}` : c.name,
        isActive: c.is_active && (parent?.is_active ?? true),
      };
    })
    .sort((a, b) => a.label.localeCompare(b.label, "es"));
}

export async function getSuppliers(): Promise<Supplier[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("suppliers")
    .select("id, code, name, is_internal")
    .eq("is_active", true)
    .order("name")
    // Tope para el desplegable. Antes de cargar proveedores reales, pasa a búsqueda en el servidor.
    .limit(200);
  if (error) failed("los proveedores");
  return data.map((s) => ({ id: s.id, code: s.code, name: s.name, isInternal: s.is_internal }));
}

export type IngredientsFilter = {
  search?: string;
  // Un rubro con sus subcategorías (la tarjeta elegida, ADR-0041).
  categoryIds?: string[];
  status?: "active" | "inactive";
  // Página desde 0 y filas por página (si no se dice, las de siempre).
  page: number;
  size?: number;
  // Orden por columna (rediseño, ADR-0036): "name" o "code"; desc invierte.
  sort?: (typeof INGREDIENT_SORT_KEYS)[number];
  desc?: boolean;
};

export const INGREDIENT_SORT_KEYS = ["name", "code"] as const;

export type IngredientRow = {
  id: string;
  code: string;
  name: string;
  category: string;
  unit: string;
  isActive: boolean;
};

// Solo letras, números, espacios y guiones: la búsqueda arma un filtro de PostgREST y no puede
// llevar comas ni paréntesis.
export function cleanSearch(value: string | undefined): string | undefined {
  const cleaned = value
    ?.replace(/[^\p{L}\p{N} -]/gu, "")
    .trim()
    .slice(0, 60);
  return cleaned ? cleaned : undefined;
}

export async function getIngredients(
  filter: IngredientsFilter,
): Promise<{ rows: IngredientRow[]; total: number }> {
  const supabase = await createClient();
  const [units, categories] = await Promise.all([getUnits(), getCategories()]);
  let query = supabase
    .schema("catalog")
    .from("ingredients")
    .select("id, code, name, category_id, recipe_unit_id, is_active", { count: "exact" })
    .order(filter.sort ?? "name", { ascending: !filter.desc })
    .order("id")
    .range(
      filter.page * (filter.size ?? INGREDIENTS_PAGE),
      (filter.page + 1) * (filter.size ?? INGREDIENTS_PAGE) - 1,
    );
  if (filter.categoryIds) query = query.in("category_id", filter.categoryIds);
  if (filter.status) query = query.eq("is_active", filter.status === "active");
  if (filter.search) {
    // Por nombre, código o alias.
    const { data: aliases, error } = await supabase
      .schema("catalog")
      .from("ingredient_aliases")
      .select("ingredient_id")
      .ilike("alias", `%${filter.search.toLowerCase()}%`)
      .limit(200);
    if (error) failed("las materias primas");
    const ids = [...new Set(aliases.map((a) => a.ingredient_id))];
    const conditions = [`name.ilike.%${filter.search}%`, `code.ilike.%${filter.search}%`];
    if (ids.length > 0) conditions.push(`id.in.(${ids.join(",")})`);
    query = query.or(conditions.join(","));
  }
  const { data, error, count } = await query;
  if (error) failed("las materias primas");
  const unitName = new Map(units.map((u) => [u.id, u.name]));
  const categoryLabel = new Map(categories.map((c) => [c.id, c.label]));
  return {
    total: count ?? 0,
    rows: data.map((i) => ({
      id: i.id,
      code: i.code,
      name: i.name,
      category: categoryLabel.get(i.category_id) ?? "",
      unit: unitName.get(i.recipe_unit_id) ?? "",
      isActive: i.is_active,
    })),
  };
}

export type IngredientDetail = {
  id: string;
  groupId: string;
  code: string;
  name: string;
  categoryId: string;
  category: string;
  unit: string;
  unitCode: string;
  purchaseUnit: string | null;
  purchaseUnitCode: string | null;
  notes: string | null;
  isActive: boolean;
  // Se compra congelada: su costo suma la merma de descongelado (ADR-0040).
  requiresThawing: boolean;
  aliases: string[];
  conversions: {
    kind: ConversionKind;
    factor: number;
    source: DataSource;
    measuredOn: string;
    measuredBy: string | null;
  }[];
  products: {
    id: string;
    code: string;
    description: string;
    brandName: string | null;
    supplier: string | null;
    contents: string;
    // Para la tabla de la ficha (ADR-0043): en qué viene («Cajón») y cuánto trae («10 kg», «12 × 500 ml»).
    packageUnit: string;
    content: string;
    isActive: boolean;
    // Para editarlo (ADR-0044): los valores tal como los guarda la base.
    supplierId: string | null;
    notes: string | null;
    packageUnitCode: string;
    unitsPerPackage: number;
    contentPerUnit: number;
    contentUnitCode: string;
  }[];
  allergens: {
    id: string;
    name: string;
    validated: boolean;
    status: AllergenStatus | null;
    source: DataSource | null;
  }[];
};

const quantity = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 3 });

// "caja de 12 × 500 ml" o "bolsa de 25.000 g".
// "12 × 500 ml" o "10 kg": lo que trae el envase, sin su nombre.
function describeContent(units: number, content: number, contentUnit: string): string {
  const each = `${quantity.format(content)} ${contentUnit}`;
  return units > 1 ? `${units} × ${each}` : each;
}

function describeContents(
  packageName: string,
  units: number,
  content: number,
  contentUnit: string,
): string {
  const each = `${quantity.format(content)} ${contentUnit}`;
  return units > 1 ? `${packageName} de ${units} × ${each}` : `${packageName} de ${each}`;
}

export async function getIngredient(id: string): Promise<IngredientDetail | null> {
  const supabase = await createClient();
  const catalog = supabase.schema("catalog");
  const [units, categories, ingredient, aliases, conversions, products, allergens, statuses] =
    await Promise.all([
      getUnits(),
      getCategories(),
      catalog
        .from("ingredients")
        .select(
          "id, group_id, code, name, category_id, recipe_unit_id, purchase_unit_id, notes, is_active, requires_thawing",
        )
        .eq("id", id)
        .maybeSingle(),
      catalog.from("ingredient_aliases").select("alias").eq("ingredient_id", id).order("alias"),
      catalog
        .from("ingredient_unit_conversions")
        .select("kind, factor, source, measured_on, measured_by")
        .eq("ingredient_id", id),
      catalog
        .from("purchase_products")
        .select(
          "id, code, description, brand_name, supplier_id, notes, package_unit_id, units_per_package, content_per_unit, content_unit_id, is_active",
        )
        .eq("ingredient_id", id)
        .order("is_active", { ascending: false })
        .order("description"),
      catalog.from("allergens").select("id, name, validated_at").order("name"),
      catalog
        .from("ingredient_allergens")
        .select("allergen_id, status, source")
        .eq("ingredient_id", id),
    ]);
  for (const result of [ingredient, aliases, conversions, products, allergens, statuses]) {
    if (result.error) failed("la materia prima");
  }
  const i = ingredient.data;
  if (!i) return null;

  const unit = new Map(units.map((u) => [u.id, u]));
  const supplierIds = [
    ...new Set((products.data ?? []).map((p) => p.supplier_id).filter((s): s is string => !!s)),
  ];
  const supplierNames = new Map<string, string>();
  if (supplierIds.length > 0) {
    const { data, error } = await catalog
      .from("suppliers")
      .select("id, name")
      .in("id", supplierIds);
    if (error) failed("los proveedores");
    for (const s of data) supplierNames.set(s.id, s.name);
  }
  const statusOf = new Map((statuses.data ?? []).map((s) => [s.allergen_id, s]));

  return {
    id: i.id,
    groupId: i.group_id,
    code: i.code,
    name: i.name,
    categoryId: i.category_id,
    category: categories.find((c) => c.id === i.category_id)?.label ?? "",
    unit: unit.get(i.recipe_unit_id)?.name ?? "",
    unitCode: unit.get(i.recipe_unit_id)?.code ?? "",
    purchaseUnit: i.purchase_unit_id ? (unit.get(i.purchase_unit_id)?.name ?? null) : null,
    purchaseUnitCode: i.purchase_unit_id ? (unit.get(i.purchase_unit_id)?.code ?? null) : null,
    notes: i.notes,
    isActive: i.is_active,
    requiresThawing: i.requires_thawing,
    aliases: (aliases.data ?? []).map((a) => a.alias),
    conversions: (conversions.data ?? []).map((c) => ({
      kind: c.kind,
      factor: c.factor,
      source: c.source,
      measuredOn: c.measured_on,
      measuredBy: c.measured_by,
    })),
    products: (products.data ?? []).map((p) => ({
      id: p.id,
      code: p.code,
      description: p.description,
      brandName: p.brand_name,
      supplier: p.supplier_id ? (supplierNames.get(p.supplier_id) ?? null) : null,
      contents: describeContents(
        unit.get(p.package_unit_id)?.name ?? "",
        p.units_per_package,
        p.content_per_unit,
        unit.get(p.content_unit_id)?.name ?? "",
      ),
      packageUnit: unit.get(p.package_unit_id)?.label ?? "",
      content: describeContent(
        p.units_per_package,
        p.content_per_unit,
        unit.get(p.content_unit_id)?.name ?? "",
      ),
      isActive: p.is_active,
      supplierId: p.supplier_id,
      notes: p.notes,
      packageUnitCode: unit.get(p.package_unit_id)?.code ?? "",
      unitsPerPackage: p.units_per_package,
      contentPerUnit: p.content_per_unit,
      contentUnitCode: unit.get(p.content_unit_id)?.code ?? "",
    })),
    allergens: (allergens.data ?? []).map((a) => ({
      id: a.id,
      name: a.name,
      validated: a.validated_at !== null,
      status: statusOf.get(a.id)?.status ?? null,
      source: statusOf.get(a.id)?.source ?? null,
    })),
  };
}

// ---------------------------------------------------------------------------
// Rendimientos (etapa 2.1 B)
// ---------------------------------------------------------------------------
export type YieldRow = {
  processId: string;
  process: string;
  cut: string | null;
  supplier: string | null;
  standardCleaning: number | null;
  standardCooking: number | null;
  declaredNoLoss: boolean;
  approvedAt: string | null;
  tests: number;
  measuredCleaning: number | null;
  measuredCooking: number | null;
  lastTestedOn: string | null;
  pendingProposals: number;
};

export async function getYieldSummary(ingredientId: string): Promise<YieldRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .rpc("yield_summary", { p_ingredient_id: ingredientId });
  if (error) failed("los rendimientos");
  return (data ?? []).map((r) => ({
    processId: r.process_id,
    process: r.process_name,
    cut: r.cut,
    supplier: r.supplier_name,
    standardCleaning: r.standard_cleaning,
    standardCooking: r.standard_cooking,
    declaredNoLoss: r.declared_no_loss ?? false,
    approvedAt: r.approved_at,
    tests: r.tests,
    measuredCleaning: r.measured_cleaning,
    measuredCooking: r.measured_cooking,
    lastTestedOn: r.last_tested_on,
    pendingProposals: r.pending_proposals,
  }));
}

// El umbral del aviso de rendimiento del grupo de esa materia prima (ADR-0035). Vacío si no se ve. Es solo para marcar
// el desvío en la ficha: si no se puede leer, la ficha se muestra igual, sin la marca.
export async function getYieldAlertThreshold(ingredientId: string): Promise<number | null> {
  const client = await createClient();
  const { data, error } = await client
    .schema("catalog")
    .rpc("yield_alert_threshold", { p_ingredient_id: ingredientId });
  if (error || data === null) return null;
  return Number(data);
}

// Las unidades con su equivalencia en la base, para la configuración (ADR-0040): «Taza (taza) = 240 ml».
// canArchive: cargada a mano y sin usar (catalog.archive_unit; las del sistema y las base, nunca).
export type SettingsUnit = Unit & { equivalence: string | null; canArchive: boolean };

export async function getSettingsUnits(): Promise<SettingsUnit[]> {
  const client = await createClient();
  const [units, conversions, authors] = await Promise.all([
    getUnits(),
    client.schema("catalog").from("unit_conversions").select("from_unit_id, to_unit_id, factor"),
    client.schema("catalog").from("units").select("id, created_by"),
  ]);
  if (conversions.error) failed("las conversiones");
  if (authors.error) failed("las unidades");
  const manual = new Set(authors.data.filter((u) => u.created_by !== null).map((u) => u.id));
  const byId = new Map(units.map((u) => [u.id, u]));
  const factor = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 6 });
  // Solo las cargadas a mano y sin usar (catalog.unit_in_use) se pueden dar de baja.
  const usage = await Promise.all(
    units.map((u) =>
      !manual.has(u.id)
        ? Promise.resolve(true)
        : client
            .schema("catalog")
            .rpc("unit_in_use", { p_unit_id: u.id })
            .then((r) => r.error !== null || r.data !== false),
    ),
  );
  return units.map((u, i) => {
    const c = conversions.data.find((x) => x.from_unit_id === u.id);
    const to = c ? byId.get(c.to_unit_id) : undefined;
    return {
      ...u,
      equivalence: c && to ? `${factor.format(Number(c.factor))} ${to.name}` : null,
      canArchive: usage[i] === false,
    };
  });
}

// Si hay un pedido pendiente para dejar de comprarla congelada (ADR-0040). Si no se puede leer, se dice que no.
export async function getThawingChangePending(ingredientId: string): Promise<boolean> {
  const client = await createClient();
  const { data, error } = await client
    .schema("catalog")
    .rpc("thawing_change_pending", { p_ingredient_id: ingredientId });
  return !error && data === true;
}

// Los procesos de las mermas (ADR-0040): LIMPIEZA y DESCONGELADO del grupo. Vacíos si el grupo no los tiene.
export async function getWasteProcesses(
  groupId: string,
): Promise<{ cleaning: string | null; thawing: string | null }> {
  const client = await createClient();
  const { data, error } = await client
    .schema("catalog")
    .from("yield_processes")
    .select("id, code")
    .eq("group_id", groupId)
    .in("code", ["LIMPIEZA", "DESCONGELADO"]);
  if (error) failed("los procesos");
  return {
    cleaning: data.find((p) => p.code === "LIMPIEZA")?.id ?? null,
    thawing: data.find((p) => p.code === "DESCONGELADO")?.id ?? null,
  };
}

export async function getYieldProcesses(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .from("yield_processes")
    .select("id, name")
    .order("name");
  if (error) failed("los procesos");
  return data;
}

// Locales donde la sesión puede registrar ensayos (solo para el desplegable: la base vuelve a
// controlar el permiso al guardar).
export async function getYieldRestaurants(): Promise<{ id: string; name: string }[]> {
  const supabase = await createClient();
  const { data: ids, error } = await supabase
    .schema("core")
    .rpc("permitted_restaurant_ids", { p_permission: "yields.record" });
  if (error) failed("los locales");
  const list = Array.isArray(ids) ? ids.filter((x): x is string => typeof x === "string") : [];
  if (list.length === 0) return [];
  const { data, error: namesError } = await supabase
    .schema("org")
    .from("restaurants")
    .select("id, name")
    .in("id", list)
    .order("name");
  if (namesError) failed("los locales");
  return data;
}

// Dónde se usa una materia prima: recetas vigentes o en preparación que la tienen (catalog.ingredient_usage,
// con la sesión de la persona: solo las recetas que ve).
export type IngredientUsage = {
  recipeId: string;
  code: string;
  name: string;
  versionNumber: number;
  status: string;
};

export async function getIngredientUsage(ingredientId: string): Promise<IngredientUsage[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("catalog")
    .rpc("ingredient_usage", { p_ingredient_id: ingredientId });
  if (error) failed("dónde se usa");
  return data
    .map((r) => ({
      recipeId: r.recipe_id,
      code: r.code,
      name: r.name,
      versionNumber: r.version_number,
      status: r.status,
    }))
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
}

// Configuración del catálogo (ADR-0022): categorías con sus subcategorías y procesos de un grupo, con
// cuánto se usan, para saber qué se puede dar de baja (la base lo vuelve a controlar al guardar).
export type SettingsCategory = {
  id: string;
  name: string;
  // Cuánto se usa: materias primas (o recetas, en las categorías de recetas).
  uses: number;
  children: { id: string; name: string; uses: number }[];
};
export type SettingsProcess = { id: string; code: string; name: string; standards: number };

// Grupos donde la sesión tiene el permiso para todo el grupo (el catálogo es de todo el grupo).
export async function getSettingsGroups(permission: string): Promise<string[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("core")
    .rpc("permitted_group_ids", { p_permission: permission });
  if (error) failed("los grupos");
  return Array.isArray(data) ? data.filter((x): x is string => typeof x === "string") : [];
}

export async function getSettingsCategories(groupId: string): Promise<SettingsCategory[]> {
  const supabase = await createClient();
  const [categories, usage] = await Promise.all([
    supabase
      .schema("catalog")
      .from("ingredient_categories")
      .select("id, parent_id, name")
      .eq("group_id", groupId)
      .order("name"),
    // Se cuenta en la base: la API devuelve hasta 1.000 filas.
    supabase.schema("catalog").rpc("category_usage"),
  ]);
  if (categories.error) failed("las categorías");
  if (usage.error) failed("las materias primas");
  const used = new Map(usage.data.map((u) => [u.category_id, u.ingredients]));
  const byName = (a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name, "es");
  return categories.data
    .filter((c) => !c.parent_id)
    .map((c) => ({
      id: c.id,
      name: c.name,
      uses: used.get(c.id) ?? 0,
      children: categories.data
        .filter((s) => s.parent_id === c.id)
        .map((s) => ({ id: s.id, name: s.name, uses: used.get(s.id) ?? 0 }))
        .sort(byName),
    }))
    .sort(byName);
}

export async function getSettingsProcesses(groupId: string): Promise<SettingsProcess[]> {
  const supabase = await createClient();
  const [processes, usage] = await Promise.all([
    supabase
      .schema("catalog")
      .from("yield_processes")
      .select("id, code, name")
      .eq("group_id", groupId)
      .order("name"),
    supabase.schema("catalog").rpc("process_usage"),
  ]);
  if (processes.error) failed("los procesos");
  if (usage.error) failed("los rendimientos");
  const used = new Map(usage.data.map((u) => [u.process_id, u.standards]));
  return processes.data.map((p) => ({ ...p, standards: used.get(p.id) ?? 0 }));
}

// Lo que la ficha de una materia prima necesita para editar sin que la base la rechace después (ADR-0043): el sello
// del último cambio (para no pisar lo de otra persona), si tiene precios (su unidad de recetas no cambia) y qué
// productos de compra tienen precios (su envase y su contenido no cambian, ADR-0044). Solo para quien la puede editar
// (catalog.manage); si no, null.
export type IngredientSheetState = { stamp: string; hasPrices: boolean; pricedProducts: string[] };

export async function getIngredientSheetState(id: string): Promise<IngredientSheetState | null> {
  const client = await createClient();
  const { data, error } = await client
    .schema("catalog")
    .rpc("ingredient_sheet_state", { p_id: id });
  if (error) failed("la materia prima");
  const state = data as { stamp?: string; has_prices?: boolean; priced_products?: string[] } | null;
  if (!state?.stamp) return null;
  return {
    stamp: state.stamp,
    hasPrices: state.has_prices === true,
    pricedProducts: Array.isArray(state.priced_products) ? state.priced_products : [],
  };
}
