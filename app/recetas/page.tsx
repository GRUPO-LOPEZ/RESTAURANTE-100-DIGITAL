import Link from "next/link";
import { Suspense } from "react";
import { Plus, Settings, Upload } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { RecipesTable } from "@/components/recipes-table";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import { cleanSearch } from "@/lib/catalog";
import { first, uuidOrUndefined } from "@/lib/data";
import {
  RECIPES_PAGE,
  RECIPE_TYPE_LABELS,
  SCOPE_LABELS,
  VARIANT_FILTER_LABEL,
  getRecipeCategories,
  getRecipes,
  type RecipeScope,
  type RecipeType,
  type RecipesFilter,
} from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Recetas (sección 18): ¿qué preparamos y cómo? Preparaciones, platos y componentes en una sola
// lista; "?tipo=preparation" filtra las preparaciones. Los costos llegan en la etapa 2.3.
export default function RecetasPage({ searchParams }: PageProps<"/recetas">) {
  return (
    <AppShell
      title="Recetas"
      description="Preparaciones, platos y componentes: cómo se hacen, con qué y cuánto rinden."
    >
      <Suspense fallback={<Loading />}>
        <Recipes searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const TYPES = Object.keys(RECIPE_TYPE_LABELS) as RecipeType[];
const SCOPES = Object.keys(SCOPE_LABELS) as RecipeScope[];
// El filtro de alcance suma las variantes de local ("?alcance=variant").
const SCOPE_FILTERS: { value: NonNullable<RecipesFilter["scope"]>; label: string }[] = [
  ...SCOPES.map((s) => ({ value: s, label: SCOPE_LABELS[s] })),
  { value: "variant", label: VARIANT_FILTER_LABEL },
];

async function Recipes({ searchParams }: { searchParams: PageProps<"/recetas">["searchParams"] }) {
  await requireMenu("recipes");
  const params = await searchParams;
  const type = first(params.tipo);
  const scope = first(params.alcance);
  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(params.pagina) ?? "1", 10) - 1 || 0, 1000),
  );
  const filter: RecipesFilter = {
    search: cleanSearch(first(params.q)),
    type: TYPES.includes(type as RecipeType) ? (type as RecipeType) : undefined,
    scope: SCOPE_FILTERS.find((s) => s.value === scope)?.value,
    categoryId: uuidOrUndefined(first(params.categoria)),
    page,
  };
  const [{ rows, total }, categories, menus] = await Promise.all([
    getRecipes(filter),
    getRecipeCategories(),
    getMenus(),
  ]);
  const pages = Math.max(1, Math.ceil(total / RECIPES_PAGE));

  const pageLink = (n: number) => {
    const query = new URLSearchParams();
    if (filter.search) query.set("q", filter.search);
    if (filter.type) query.set("tipo", filter.type);
    if (filter.scope) query.set("alcance", filter.scope);
    if (filter.categoryId) query.set("categoria", filter.categoryId);
    query.set("pagina", String(n + 1));
    return `/recetas?${query.toString()}`;
  };

  const activeFilters = [
    filter.search ? `«${filter.search}»` : null,
    filter.type ? RECIPE_TYPE_LABELS[filter.type] : null,
    filter.scope ? SCOPE_FILTERS.find((s) => s.value === filter.scope)?.label : null,
    filter.categoryId ? categories.find((c) => c.id === filter.categoryId)?.label : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <>
      <FiltersPanel active={activeFilters}>
        <form
          method="get"
          role="search"
          aria-label="Filtros de recetas"
          className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5 lg:items-end"
        >
          <Field id="rec-filtro-q" label="Buscar" className="lg:col-span-2">
            <Input name="q" defaultValue={filter.search} placeholder="Nombre o código" />
          </Field>
          <Field id="rec-filtro-tipo" label="Tipo">
            <Select name="tipo" defaultValue={filter.type ?? ""}>
              <option value="">Todos</option>
              {TYPES.map((t) => (
                <option key={t} value={t}>
                  {RECIPE_TYPE_LABELS[t]}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="rec-filtro-alcance" label="Alcance">
            <Select name="alcance" defaultValue={filter.scope ?? ""}>
              <option value="">Todos</option>
              {SCOPE_FILTERS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="rec-filtro-categoria" label="Categoría">
            <Select name="categoria" defaultValue={filter.categoryId ?? ""}>
              <option value="">Todas</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </Select>
          </Field>
          <Button type="submit">Filtrar</Button>
        </form>
      </FiltersPanel>

      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="tabular-nums">
            {total === 1 ? "1 receta" : `${total.toLocaleString("es-AR")} recetas`}
          </CardTitle>
          <div className="flex flex-wrap gap-2">
            {menus.recipesSettings ? (
              <Button asChild variant="outline">
                <Link href="/materias-primas/configuracion">
                  <Settings aria-hidden="true" />
                  Categorías
                </Link>
              </Button>
            ) : null}
            {menus.imports ? (
              <Button asChild variant="outline">
                <Link href="/recetas/importar">
                  <Upload aria-hidden="true" />
                  Importaciones
                </Link>
              </Button>
            ) : null}
            {menus.recipesDraft ? (
              <Button asChild variant="outline">
                <Link href="/recetas/nueva">
                  <Plus aria-hidden="true" />
                  Nueva receta
                </Link>
              </Button>
            ) : null}
          </div>
        </div>
        {rows.length === 0 && total > 0 ? (
          <EmptyState title="Esa página no existe.">
            <Link href={pageLink(0)} className="text-primary underline-offset-4 hover:underline">
              Ir a la primera página
            </Link>
          </EmptyState>
        ) : rows.length === 0 ? (
          <EmptyState
            title={
              activeFilters.length > 0
                ? "No hay recetas con esos filtros."
                : "Todavía no hay recetas."
            }
          >
            {activeFilters.length > 0
              ? "Probá con otro nombre, tipo o categoría."
              : menus.recipesDraft
                ? "Cargá la primera con «Nueva receta»."
                : "Las cargan los chefs y jefes de cocina."}
          </EmptyState>
        ) : (
          <RecipesTable rows={rows} />
        )}
        {pages > 1 ? (
          <nav aria-label="Páginas" className="flex flex-wrap items-center gap-2">
            {page > 0 ? (
              <Button asChild variant="outline">
                <Link href={pageLink(page - 1)}>Anterior</Link>
              </Button>
            ) : null}
            <span className="text-sm text-ink-muted tabular-nums">
              Página {page + 1} de {pages}
            </span>
            {page + 1 < pages ? (
              <Button asChild variant="outline">
                <Link href={pageLink(page + 1)}>Siguiente</Link>
              </Button>
            ) : null}
          </nav>
        ) : null}
      </Card>
    </>
  );
}
