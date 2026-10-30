import { createClient } from "@/lib/supabase/server";
import type { SettingsCategory } from "@/lib/catalog";
import type {
  MediaKind,
  QuantityBasis,
  RecipeScope,
  RecipeType,
  StepKind,
  VersionStatus,
} from "@/lib/recipe-format";

export * from "@/lib/recipe-format";

// Lecturas del recetario (Fase 2, etapa 2.2 A; ADR-0023). Como en lib/catalog.ts: todo pasa por la
// base con la sesión de la persona (RLS) y, si una lectura falla, se corta con un error en lugar de
// mostrar "no hay datos". Ningún valor económico: los costos llegan en la 2.3.

function failed(what: string): never {
  throw new Error(`No pudimos cargar ${what}.`);
}

export const RECIPES_PAGE = 25;

// ---------------------------------------------------------------------------
// Lugares: nombres de grupos, marcas y locales, y dónde la sesión puede escribir o asignar
// ---------------------------------------------------------------------------
type Place = { id: string; name: string };
export type Places = {
  groups: Place[];
  brands: (Place & { groupId: string })[];
  restaurants: (Place & { brandId: string })[];
};

async function getPlaces(): Promise<Places> {
  const supabase = await createClient();
  const [groups, brands, restaurants] = await Promise.all([
    supabase.schema("org").from("groups").select("id, name").order("name"),
    supabase.schema("org").from("brands").select("id, name, group_id").order("name"),
    supabase.schema("org").from("restaurants").select("id, name, brand_id").order("name"),
  ]);
  if (groups.error || brands.error || restaurants.error) failed("los locales");
  return {
    groups: groups.data,
    brands: brands.data.map((b) => ({ id: b.id, name: b.name, groupId: b.group_id })),
    restaurants: restaurants.data.map((r) => ({ id: r.id, name: r.name, brandId: r.brand_id })),
  };
}

async function permitted(
  kind: "group" | "brand" | "restaurant",
  permission: string,
): Promise<string[]> {
  const supabase = await createClient();
  const fn =
    kind === "group"
      ? "permitted_group_ids"
      : kind === "brand"
        ? "permitted_brand_ids"
        : "permitted_restaurant_ids";
  const { data, error } = await supabase.schema("core").rpc(fn, { p_permission: permission });
  if (error) failed("tus permisos");
  return Array.isArray(data) ? data.filter((x): x is string => typeof x === "string") : [];
}

// Dónde la sesión puede crear recetas: todo el grupo, una marca entera o un local.
export type ScopeOption = { value: string; label: string };
export async function getDraftScopes(): Promise<ScopeOption[]> {
  const [places, groups, brands, restaurants] = await Promise.all([
    getPlaces(),
    permitted("group", "recipes.draft"),
    permitted("brand", "recipes.draft"),
    permitted("restaurant", "recipes.draft"),
  ]);
  return [
    ...places.groups
      .filter((g) => groups.includes(g.id))
      .map((g) => ({
        value: `group:${g.id}`,
        label: `Maestra de todo el grupo (${g.name})`,
      })),
    ...places.brands
      .filter((b) => brands.includes(b.id))
      .map((b) => ({
        value: `brand:${b.id}`,
        label: `De la marca ${b.name}`,
      })),
    ...places.restaurants
      .filter((r) => restaurants.includes(r.id))
      .map((r) => ({
        value: `restaurant:${r.id}`,
        label: `Del local ${r.name}`,
      })),
  ];
}

// ---------------------------------------------------------------------------
// Categorías de recetas
// ---------------------------------------------------------------------------
export type RecipeCategory = { id: string; groupId: string; label: string };

export async function getRecipeCategories(): Promise<RecipeCategory[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .from("recipe_categories")
    .select("id, group_id, parent_id, name")
    .order("name");
  if (error) failed("las categorías de recetas");
  const byId = new Map(data.map((c) => [c.id, c]));
  return data
    .map((c) => {
      const parent = c.parent_id ? byId.get(c.parent_id) : undefined;
      return {
        id: c.id,
        groupId: c.group_id,
        label: parent ? `${parent.name} › ${c.name}` : c.name,
      };
    })
    .sort((a, b) => a.label.localeCompare(b.label, "es"));
}

// Para la configuración: categorías de recetas de un grupo, con cuántas recetas tiene cada una
// (mismo formato que las de materias primas).
export async function getRecipeSettingsCategories(groupId: string): Promise<SettingsCategory[]> {
  const supabase = await createClient();
  const [categories, usage] = await Promise.all([
    supabase
      .schema("recipes")
      .from("recipe_categories")
      .select("id, parent_id, name")
      .eq("group_id", groupId)
      .order("name"),
    // Se cuenta en la base: la API devuelve hasta 1.000 filas.
    supabase.schema("recipes").rpc("category_usage"),
  ]);
  if (categories.error) failed("las categorías de recetas");
  if (usage.error) failed("las recetas");
  const used = new Map(usage.data.map((u) => [u.category_id, u.recipes]));
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

// ---------------------------------------------------------------------------
// Lista
// ---------------------------------------------------------------------------
export type RecipesFilter = {
  search?: string;
  type?: RecipeType;
  // "variant": las variantes de local (recetas de local hechas a partir de una maestra).
  scope?: RecipeScope | "variant";
  categoryId?: string;
  page: number;
};

export type RecipeRow = {
  id: string;
  code: string;
  name: string;
  type: RecipeType;
  place: string;
  category: string;
  current: number | null;
  open: VersionStatus | null;
  isActive: boolean;
  isVariant: boolean;
};

function placeName(
  places: Places,
  r: {
    scope_type: RecipeScope;
    group_id: string;
    brand_id: string | null;
    restaurant_id: string | null;
  },
) {
  if (r.scope_type === "restaurant")
    return places.restaurants.find((x) => x.id === r.restaurant_id)?.name ?? "Local";
  if (r.scope_type === "brand")
    return places.brands.find((x) => x.id === r.brand_id)?.name ?? "Marca";
  return "Todo el grupo";
}

export async function getRecipes(
  filter: RecipesFilter,
): Promise<{ rows: RecipeRow[]; total: number }> {
  const supabase = await createClient();
  let query = supabase
    .schema("recipes")
    .from("recipes")
    .select(
      "id, code, name, recipe_type, scope_type, group_id, brand_id, restaurant_id, category_id, is_active, variant_of_recipe_id",
      {
        count: "exact",
      },
    )
    .order("name")
    .range(filter.page * RECIPES_PAGE, (filter.page + 1) * RECIPES_PAGE - 1);
  if (filter.type) query = query.eq("recipe_type", filter.type);
  if (filter.scope === "variant") query = query.not("variant_of_recipe_id", "is", null);
  else if (filter.scope) query = query.eq("scope_type", filter.scope);
  if (filter.categoryId) query = query.eq("category_id", filter.categoryId);
  if (filter.search)
    query = query.or(`name.ilike.%${filter.search}%,code.ilike.%${filter.search}%`);
  const [{ data, error, count }, places, categories] = await Promise.all([
    query,
    getPlaces(),
    getRecipeCategories(),
  ]);
  if (error) failed("las recetas");
  const ids = data.map((r) => r.id);
  const versions = ids.length
    ? await supabase
        .schema("recipes")
        .from("recipe_versions")
        .select("recipe_id, version_number, status")
        .in("recipe_id", ids)
        .in("status", ["published", "draft", "in_review"])
    : { data: [], error: null };
  if (versions.error) failed("las versiones");
  const categoryLabel = new Map(categories.map((c) => [c.id, c.label]));
  return {
    total: count ?? 0,
    rows: data.map((r) => {
      const mine = (versions.data ?? []).filter((v) => v.recipe_id === r.id);
      return {
        id: r.id,
        code: r.code,
        name: r.name,
        type: r.recipe_type,
        place: placeName(places, r),
        category: r.category_id ? (categoryLabel.get(r.category_id) ?? "") : "",
        current: mine.find((v) => v.status === "published")?.version_number ?? null,
        open: mine.find((v) => v.status !== "published")?.status ?? null,
        isActive: r.is_active,
        isVariant: r.variant_of_recipe_id !== null,
      };
    }),
  };
}

// ---------------------------------------------------------------------------
// Ficha (editor)
// ---------------------------------------------------------------------------
export type RecipeLine = {
  ingredientId: string | null;
  // Una preparación (subreceta) en lugar de una materia prima; usa siempre su versión vigente.
  subRecipeId: string | null;
  ingredient: string;
  quantity: number;
  unit: string;
  basis: QuantityBasis;
  noScale: boolean;
  notes: string | null;
};

export type RecipeStep = {
  number: number;
  kind: StepKind;
  instructions: string;
  activeMinutes: number;
  passiveMinutes: number;
  equipment: string | null;
  controlPoint: string | null;
  dependsOn: number[];
};

export type RecipeVersion = {
  id: string;
  number: number;
  status: VersionStatus;
  updatedAt: string;
  yieldQuantity: number | null;
  yieldUnit: string | null;
  portions: number | null;
  portionGrams: number | null;
  description: string | null;
  storageNotes: string | null;
  presentationNotes: string | null;
  changeSummary: string | null;
  publishedAt: string | null;
  requestId: string | null;
  requestStatus: string | null;
};

export type RecipeDetail = {
  id: string;
  groupId: string;
  brandId: string | null;
  restaurantId: string | null;
  code: string;
  name: string;
  shortName: string | null;
  type: RecipeType;
  scope: RecipeScope;
  place: string;
  categoryId: string | null;
  sector: string | null;
  station: string | null;
  isActive: boolean;
  versions: RecipeVersion[];
  current: RecipeVersion | null;
  open: RecipeVersion | null;
  // Si es una variante: su maestra (el nombre, solo si la sesión la ve).
  variantOf: { id: string; name: string | null } | null;
  // Lo que puede hacer la sesión con esta receta (solo interfaz: la base vuelve a controlar).
  can: {
    draft: boolean;
    review: boolean;
    publish: boolean;
    assign: boolean;
    archive: boolean;
    // Locales donde puede crear una variante de esta maestra (recipes.approve en el local).
    variantPlaces: Assignment[];
  };
};

async function allowed(
  permission: string,
  r: { group_id: string; brand_id: string | null; restaurant_id: string | null },
) {
  const supabase = await createClient();
  const { data, error } = r.restaurant_id
    ? await supabase
        .schema("core")
        .rpc("has_permission", { p_permission: permission, p_restaurant_id: r.restaurant_id })
    : r.brand_id
      ? await supabase
          .schema("core")
          .rpc("has_permission_in_brand", { p_permission: permission, p_brand_id: r.brand_id })
      : await supabase
          .schema("core")
          .rpc("has_permission_in_group", { p_permission: permission, p_group_id: r.group_id });
  if (error) failed("tus permisos");
  return data === true;
}

export async function getRecipe(id: string): Promise<RecipeDetail | null> {
  const supabase = await createClient();
  const { data: r, error } = await supabase
    .schema("recipes")
    .from("recipes")
    .select(
      "id, group_id, brand_id, restaurant_id, scope_type, code, name, short_name, recipe_type, category_id, sector, station, is_active, variant_of_recipe_id",
    )
    .eq("id", id)
    .maybeSingle();
  if (error) failed("la receta");
  if (!r) return null;
  const [
    versions,
    places,
    draft,
    review,
    publish,
    archive,
    assignAnywhere,
    approveAnywhere,
    master,
  ] = await Promise.all([
    supabase
      .schema("recipes")
      .from("recipe_versions")
      .select(
        "id, version_number, status, updated_at, yield_quantity, yield_unit_id, portions, portion_grams, description, storage_notes, presentation_notes, change_summary, published_at, approval_request_id",
      )
      .eq("recipe_id", id)
      .order("version_number", { ascending: false }),
    getPlaces(),
    allowed("recipes.draft", r),
    allowed("recipes.review", r),
    allowed("recipes.publish", r),
    allowed("recipes.archive", r),
    permitted("restaurant", "recipes.assign"),
    permitted("restaurant", "recipes.approve"),
    // La maestra se lee con la sesión: si no la ve, queda sin nombre.
    r.variant_of_recipe_id
      ? supabase
          .schema("recipes")
          .from("recipes")
          .select("id, name")
          .eq("id", r.variant_of_recipe_id)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);
  if (versions.error) failed("las versiones");
  const unitIds = [
    ...new Set(versions.data.map((v) => v.yield_unit_id).filter((x): x is string => Boolean(x))),
  ];
  const requestIds = versions.data
    .map((v) => v.approval_request_id)
    .filter((x): x is string => Boolean(x));
  const [units, requests] = await Promise.all([
    unitIds.length
      ? supabase.schema("catalog").from("units").select("id, code").in("id", unitIds)
      : Promise.resolve({ data: [], error: null }),
    requestIds.length
      ? supabase
          .schema("workflow")
          .from("approval_requests")
          .select("id, status")
          .in("id", requestIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  const unitCode = new Map((units.data ?? []).map((u) => [u.id, u.code]));
  const requestStatus = new Map((requests.data ?? []).map((q) => [q.id, q.status as string]));
  const list: RecipeVersion[] = versions.data.map((v) => ({
    id: v.id,
    number: v.version_number,
    status: v.status,
    updatedAt: v.updated_at,
    yieldQuantity: v.yield_quantity,
    yieldUnit: v.yield_unit_id ? (unitCode.get(v.yield_unit_id) ?? null) : null,
    portions: v.portions,
    portionGrams: v.portion_grams,
    description: v.description,
    storageNotes: v.storage_notes,
    presentationNotes: v.presentation_notes,
    changeSummary: v.change_summary,
    publishedAt: v.published_at,
    requestId: v.approval_request_id,
    requestStatus: v.approval_request_id
      ? (requestStatus.get(v.approval_request_id) ?? null)
      : null,
  }));
  // Asignar: en algún local donde se puede usar la receta.
  const inScope = places.restaurants.filter((x) =>
    r.scope_type === "restaurant"
      ? x.id === r.restaurant_id
      : r.scope_type === "brand"
        ? x.brandId === r.brand_id
        : places.brands.some((b) => b.id === x.brandId && b.groupId === r.group_id),
  );
  // Variantes: solo de una maestra del grupo o de una marca, activa y con versión vigente.
  const current = list.find((v) => v.status === "published") ?? null;
  const variantPlaces =
    r.scope_type !== "restaurant" && r.is_active && current
      ? inScope
          .filter((x) => approveAnywhere.includes(x.id))
          .map((x) => ({ restaurantId: x.id, restaurant: x.name }))
      : [];
  return {
    id: r.id,
    groupId: r.group_id,
    brandId: r.brand_id,
    restaurantId: r.restaurant_id,
    code: r.code,
    name: r.name,
    shortName: r.short_name,
    type: r.recipe_type,
    scope: r.scope_type,
    place: placeName(places, r),
    categoryId: r.category_id,
    sector: r.sector,
    station: r.station,
    isActive: r.is_active,
    versions: list,
    current,
    open: list.find((v) => v.status === "draft" || v.status === "in_review") ?? null,
    variantOf: r.variant_of_recipe_id
      ? { id: r.variant_of_recipe_id, name: master.data?.name ?? null }
      : null,
    can: {
      draft,
      review,
      publish,
      archive,
      assign: inScope.some((x) => assignAnywhere.includes(x.id)),
      variantPlaces,
    },
  };
}

// Líneas y pasos de una versión, con los nombres de las materias primas y de las preparaciones.
export async function getVersionContent(
  versionId: string,
): Promise<{ lines: RecipeLine[]; steps: RecipeStep[] }> {
  const supabase = await createClient();
  const [lines, steps] = await Promise.all([
    supabase
      .schema("recipes")
      .from("recipe_components")
      .select(
        "ingredient_id, sub_recipe_id, quantity, unit_id, quantity_basis, no_scale, notes, line_order",
      )
      .eq("recipe_version_id", versionId)
      .order("line_order"),
    supabase
      .schema("recipes")
      .from("recipe_steps")
      .select(
        "id, step_number, kind, instructions, active_minutes, passive_minutes, equipment, control_point",
      )
      .eq("recipe_version_id", versionId)
      .order("step_number"),
  ]);
  if (lines.error) failed("los componentes");
  if (steps.error) failed("los pasos");
  const ingredientIds = [
    ...new Set(lines.data.flatMap((l) => (l.ingredient_id ? [l.ingredient_id] : []))),
  ];
  const subIds = [
    ...new Set(lines.data.flatMap((l) => (l.sub_recipe_id ? [l.sub_recipe_id] : []))),
  ];
  const stepIds = steps.data.map((s) => s.id);
  const [ingredients, subs, units, deps] = await Promise.all([
    ingredientIds.length
      ? supabase.schema("catalog").from("ingredients").select("id, name").in("id", ingredientIds)
      : Promise.resolve({ data: [], error: null }),
    subIds.length
      ? supabase.schema("recipes").from("recipes").select("id, name").in("id", subIds)
      : Promise.resolve({ data: [], error: null }),
    supabase.schema("catalog").from("units").select("id, code"),
    stepIds.length
      ? supabase
          .schema("recipes")
          .from("recipe_step_dependencies")
          .select("step_id, depends_on_step_id")
          .in("step_id", stepIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (ingredients.error || subs.error || units.error || deps.error) failed("los componentes");
  const name = new Map(
    [...(ingredients.data ?? []), ...(subs.data ?? [])].map((i) => [i.id, i.name]),
  );
  const unit = new Map((units.data ?? []).map((u) => [u.id, u.code]));
  const number = new Map(steps.data.map((s) => [s.id, s.step_number]));
  return {
    lines: lines.data.map((l) => ({
      ingredientId: l.ingredient_id,
      subRecipeId: l.sub_recipe_id,
      ingredient:
        name.get(l.ingredient_id ?? l.sub_recipe_id ?? "") ??
        (l.sub_recipe_id ? "Preparación" : "Materia prima"),
      quantity: l.quantity,
      unit: unit.get(l.unit_id) ?? "g",
      basis: l.quantity_basis,
      noScale: l.no_scale,
      notes: l.notes,
    })),
    steps: steps.data.map((s) => ({
      number: s.step_number,
      kind: s.kind,
      instructions: s.instructions,
      activeMinutes: s.active_minutes,
      passiveMinutes: s.passive_minutes,
      equipment: s.equipment,
      controlPoint: s.control_point,
      dependsOn: (deps.data ?? [])
        .filter((d) => d.step_id === s.id)
        .map((d) => number.get(d.depends_on_step_id) ?? 0)
        .filter((n) => n > 0)
        .sort((a, b) => a - b),
    })),
  };
}

export type AllergenStatus = { name: string; status: string };

export async function getVersionSummary(versionId: string): Promise<{
  totalMinutes: number;
  activeMinutes: number;
  allergens: AllergenStatus[];
}> {
  const supabase = await createClient();
  const [path, allergens] = await Promise.all([
    supabase.schema("recipes").rpc("critical_path", { p_version_id: versionId }),
    supabase.schema("recipes").rpc("version_allergens", { p_version_id: versionId }),
  ]);
  if (path.error) failed("los tiempos");
  if (allergens.error) failed("los alérgenos");
  const p = path.data?.[0];
  return {
    totalMinutes: p?.total_minutes ?? 0,
    activeMinutes: p?.active_minutes ?? 0,
    allergens: allergens.data.map((a) => ({ name: a.name, status: a.status })),
  };
}

export type DiffRow = {
  change: string;
  ingredient: string;
  unit: string;
  oldQuantity: number | null;
  newQuantity: number | null;
};

export async function getVersionDiff(versionId: string): Promise<DiffRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("version_diff", { p_version_id: versionId });
  if (error) failed("las diferencias");
  return data.map((d) => ({
    change: d.change,
    ingredient: d.ingredient,
    unit: d.unit,
    oldQuantity: d.old_quantity,
    newQuantity: d.new_quantity,
  }));
}

// Una variante contra la vigente de su maestra (vacío si la sesión no ve la maestra).
export async function getVariantDiff(recipeId: string): Promise<DiffRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("variant_diff", { p_variant_id: recipeId });
  if (error) failed("las diferencias con la maestra");
  return data.map((d) => ({
    change: d.change,
    ingredient: d.ingredient,
    unit: d.unit,
    oldQuantity: d.old_quantity,
    newQuantity: d.new_quantity,
  }));
}

// Recetas que usan esta como preparación (las que la sesión ve), y las variantes de una maestra.
export type RecipeUse = { id: string; code: string; name: string; status: VersionStatus };
export type RecipeVariant = {
  id: string;
  code: string;
  name: string;
  restaurantId: string | null;
  restaurant: string;
};

export async function getRecipeUsage(recipeId: string): Promise<RecipeUse[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("recipe_usage", { p_recipe_id: recipeId });
  if (error) failed("dónde se usa");
  return data
    .map((u) => ({ id: u.recipe_id, code: u.code, name: u.name, status: u.status }))
    .sort((a, b) => a.name.localeCompare(b.name, "es"));
}

export async function getVariants(recipeId: string): Promise<RecipeVariant[]> {
  const supabase = await createClient();
  const [{ data, error }, places] = await Promise.all([
    supabase
      .schema("recipes")
      .from("recipes")
      .select("id, code, name, restaurant_id")
      .eq("variant_of_recipe_id", recipeId)
      .eq("is_active", true)
      .order("name"),
    getPlaces(),
  ]);
  if (error) failed("las variantes");
  const name = new Map(places.restaurants.map((r) => [r.id, r.name]));
  return data.map((v) => ({
    id: v.id,
    code: v.code,
    name: v.name,
    restaurantId: v.restaurant_id,
    restaurant: (v.restaurant_id ? name.get(v.restaurant_id) : undefined) ?? "Local",
  }));
}

export type Assignment = { restaurantId: string; restaurant: string };

// Locales que usan la receta hoy (los que la sesión ve) y los locales donde se puede asignar.
export async function getAssignments(
  recipe: RecipeDetail,
): Promise<{ current: Assignment[]; available: Assignment[] }> {
  const supabase = await createClient();
  const [rows, places, assignable] = await Promise.all([
    supabase
      .schema("recipes")
      .from("recipe_assignments")
      .select("restaurant_id, valid_to")
      .eq("recipe_id", recipe.id)
      .is("valid_to", null),
    getPlaces(),
    permitted("restaurant", "recipes.assign"),
  ]);
  if (rows.error) failed("los locales asignados");
  const name = new Map(places.restaurants.map((r) => [r.id, r.name]));
  const current = rows.data.map((a) => ({
    restaurantId: a.restaurant_id,
    restaurant: name.get(a.restaurant_id) ?? "Local",
  }));
  const inScope = places.restaurants.filter((x) =>
    recipe.scope === "restaurant"
      ? x.id === recipe.restaurantId
      : recipe.scope === "brand"
        ? x.brandId === recipe.brandId
        : places.brands.some((b) => b.id === x.brandId && b.groupId === recipe.groupId),
  );
  return {
    current: current.sort((a, b) => a.restaurant.localeCompare(b.restaurant, "es")),
    available: inScope
      .filter((x) => assignable.includes(x.id) && !current.some((c) => c.restaurantId === x.id))
      .map((x) => ({ restaurantId: x.id, restaurant: x.name })),
  };
}

// ---------------------------------------------------------------------------
// Fotos (bucket privado recipe-media): son parte de la versión. Los enlaces firmados vencen en 10
// minutos: alcanza para abrir la página, y no sobreviven mucho a la baja de una cuenta (revisión de
// seguridad, M3). Si las fotos fallan, la receta se muestra igual (lo principal son los pasos).
// ---------------------------------------------------------------------------
export type RecipePhoto = {
  id: string;
  kind: MediaKind;
  description: string | null;
  url: string | null;
  createdAt: string;
};
export type PhotoSet = { photos: RecipePhoto[]; failed: boolean };

const PHOTO_LINK_SECONDS = 600;

// Las fotos de una versión (la del borrador o la vigente, según quién mira).
export async function getVersionPhotos(versionId: string): Promise<PhotoSet> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .from("recipe_media")
    .select("id, kind, description, storage_path, created_at")
    .eq("recipe_version_id", versionId)
    .order("created_at")
    .limit(60);
  if (error) return { photos: [], failed: true };
  if (data.length === 0) return { photos: [], failed: false };
  // Storage vuelve a controlar que la sesión pueda ver cada archivo (mismas reglas).
  const { data: signed, error: signError } = await supabase.storage
    .from("recipe-media")
    .createSignedUrls(
      data.map((m) => m.storage_path),
      PHOTO_LINK_SECONDS,
    );
  const url = new Map((signed ?? []).map((s) => [s.path, s.signedUrl]));
  return {
    failed: Boolean(signError),
    photos: data.map((m) => ({
      id: m.id,
      kind: m.kind,
      description: m.description,
      url: url.get(m.storage_path) ?? null,
      createdAt: m.created_at,
    })),
  };
}

// Las fotos de la versión vigente (la vista de cocina).
export async function getPublishedPhotos(recipeId: string): Promise<PhotoSet> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .from("recipe_versions")
    .select("id")
    .eq("recipe_id", recipeId)
    .eq("status", "published")
    .maybeSingle();
  if (error) return { photos: [], failed: true };
  return data ? getVersionPhotos(data.id) : { photos: [], failed: false };
}

// ---------------------------------------------------------------------------
// Vista de cocina
// ---------------------------------------------------------------------------
export type KitchenCard = {
  code: string;
  name: string;
  versionNumber: number;
  publishedAt: string;
  yieldQuantity: number | null;
  yieldUnit: string | null;
  portions: number | null;
  portionGrams: number | null;
  description: string | null;
  storageNotes: string | null;
  presentationNotes: string | null;
  totalMinutes: number;
  activeMinutes: number;
  // La maestra, si es una variante y la sesión la ve.
  variantOf: { recipe_id: string; name: string } | null;
  components: {
    line: number;
    ingredient: string;
    // Una preparación: enlace a su propia ficha de cocina.
    sub_recipe_id: string | null;
    quantity: number;
    unit: string;
    basis: QuantityBasis;
    notes: string | null;
  }[];
  steps: {
    number: number;
    kind: StepKind;
    instructions: string;
    active_minutes: number;
    passive_minutes: number;
    equipment: string | null;
    control_point: string | null;
    depends_on: number[];
  }[];
  allergens: AllergenStatus[];
};

export async function getKitchenCard(recipeId: string): Promise<KitchenCard | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .schema("recipes")
    .rpc("kitchen_card", { p_recipe_id: recipeId });
  if (error) failed("la ficha de cocina");
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const c = data as Record<string, unknown>;
  return {
    code: String(c.code),
    name: String(c.name),
    versionNumber: Number(c.version_number),
    publishedAt: String(c.published_at),
    yieldQuantity: c.yield_quantity == null ? null : Number(c.yield_quantity),
    yieldUnit: c.yield_unit == null ? null : String(c.yield_unit),
    portions: c.portions == null ? null : Number(c.portions),
    portionGrams: c.portion_grams == null ? null : Number(c.portion_grams),
    description: c.description == null ? null : String(c.description),
    storageNotes: c.storage_notes == null ? null : String(c.storage_notes),
    presentationNotes: c.presentation_notes == null ? null : String(c.presentation_notes),
    totalMinutes: Number(c.total_minutes ?? 0),
    activeMinutes: Number(c.active_minutes ?? 0),
    variantOf: (c.variant_of ?? null) as KitchenCard["variantOf"],
    components: (c.components ?? []) as KitchenCard["components"],
    steps: (c.steps ?? []) as KitchenCard["steps"],
    allergens: (c.allergens ?? []) as AllergenStatus[],
  };
}
