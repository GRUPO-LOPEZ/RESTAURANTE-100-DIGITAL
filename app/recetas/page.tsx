import Link from "next/link";
import { Suspense } from "react";
import { Settings, Upload } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { NewRecipeForm } from "@/components/new-recipe-form";
import { NewRecipeModal } from "@/components/new-recipe-modal";
import { RubroFilterGrid, SegmentedLinks } from "@/components/rubro-filter";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { cleanSearch } from "@/lib/catalog";
import { RECIPE_LIST_TABS, recipeListTab } from "@/lib/codes";
import { RELIABILITY, type Reliability } from "@/lib/cost-labels";
import { getCostsByRecipe, resolveCostPlace } from "@/lib/costs";
import { first, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { formatMoney } from "@/lib/money";
import {
  RECIPE_SORT_KEYS,
  SCOPE_LABELS,
  VARIANT_FILTER_LABEL,
  countRecipesByTypes,
  getRecipeCategories,
  getRecipes,
  getRubros,
  withSubcategories,
  type RecipeRow,
  type RecipeScope,
  type RecipesFilter,
} from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Recetas (sección 18; listado del rediseño, ADR-0036; ordenado por rubro, ADR-0041): ¿qué preparamos y cómo?
// Dos botones (Platos | Preparaciones), las tarjetas de los rubros de esa clase, que filtran con un clic, y la
// tabla. Quien ve costos y tiene un local elegido en la barra ve el costo ahí.
export default function RecetasPage({ searchParams }: PageProps<"/recetas">) {
  return (
    <AppShell
      title="Recetas"
      description="Platos y preparaciones: cómo se hacen, con qué y cuánto rinden."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Recipes searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  const menus = await getMenus();
  return (
    <>
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
        <NewRecipeModal>
          <NewRecipeForm />
        </NewRecipeModal>
      ) : null}
    </>
  );
}

const PATH = "/recetas";
const SCOPES = Object.keys(SCOPE_LABELS) as RecipeScope[];
// El filtro de alcance suma las variantes de local ("?alcance=variant").
const SCOPE_FILTERS: { value: NonNullable<RecipesFilter["scope"]>; label: string }[] = [
  ...SCOPES.map((s) => ({ value: s, label: SCOPE_LABELS[s] })),
  { value: "variant", label: VARIANT_FILTER_LABEL },
];
// Pestañas de estado: con versión vigente, o con una versión abierta (borrador o en revisión).
const STATUS_TABS = [
  { value: undefined, label: "Todas" },
  { value: "vigentes", label: "Vigentes" },
  { value: "atencion", label: "Requieren atención" },
] as const;

// Estado de la receta: la versión vigente y, si la hay, una versión abierta (borrador o en revisión).
function StatusBadges({ row }: { row: RecipeRow }) {
  if (!row.isActive) return <Badge status="none">Archivada</Badge>;
  return (
    <span className="flex flex-wrap gap-1">
      {row.isVariant ? <Badge status="info">Variante</Badge> : null}
      {row.current ? (
        <Badge status="ok">Vigente v{row.current}</Badge>
      ) : (
        <Badge status="none">Sin vigente</Badge>
      )}
      {row.open === "draft" ? <Badge status="draft">Borrador</Badge> : null}
      {row.open === "in_review" ? <Badge status="review">En revisión</Badge> : null}
    </span>
  );
}

type RecipeCost = { total: number | null; reliability: Reliability };

async function Recipes({ searchParams }: { searchParams: PageProps<"/recetas">["searchParams"] }) {
  const session = await requireMenu("recipes");
  const raw = await searchParams;
  const params = plainParams(raw);
  const tab = recipeListTab(first(raw.tipo));
  const scope = first(raw.alcance);
  const status = first(raw.estado);
  const list = parseList(raw, RECIPE_SORT_KEYS, "name");
  const search = cleanSearch(first(raw.q));
  const scopeFilter = SCOPE_FILTERS.find((s) => s.value === scope)?.value;
  const [categories, rubrosData, counts] = await Promise.all([
    getRecipeCategories(),
    getRubros(),
    countRecipesByTypes(
      RECIPE_LIST_TABS.map((t) => t.types),
      { search, scope: scopeFilter },
    ),
  ]);
  // Los rubros de la clase de la pestaña (menú para platos; sub-recetas para preparaciones).
  const rubros = (rubrosData?.rubros ?? []).filter((r) => r.rubroClass === tab.rubroClass);
  // La otra pestaña y cuántas tiene con la misma búsqueda y alcance (para el vacío).
  const otherIndex = RECIPE_LIST_TABS.findIndex((t) => t.value !== tab.value);
  const otherTab = RECIPE_LIST_TABS[otherIndex];
  const otherCount = counts[otherIndex] ?? 0;
  const rubroId = uuidOrUndefined(first(raw.rubro));
  const rubro = rubros.find((r) => r.id === rubroId);
  const filter: RecipesFilter = {
    search,
    types: tab.types,
    scope: scopeFilter,
    categoryIds: rubro ? withSubcategories(categories, rubro.id) : undefined,
    status: status === "vigentes" ? "current" : status === "atencion" ? "attention" : undefined,
    page: list.page - 1,
    size: list.size,
    sort: RECIPE_SORT_KEYS.find((k) => k === list.sort),
    desc: list.dir === "desc",
  };
  const [{ rows, total }, menus] = await Promise.all([getRecipes(filter), getMenus()]);
  const costPlace = menus.costs ? (await resolveCostPlace(session.user_id)).place : null;
  const costs: Record<string, RecipeCost> | null = costPlace
    ? Object.fromEntries(
        await getCostsByRecipe(
          costPlace.id,
          rows.map((r) => r.id),
        ),
      )
    : null;

  const remove = (key: string) => listHref(PATH, params, { [key]: undefined, pagina: undefined });
  const active = [
    filter.search ? { label: `Buscar: «${filter.search}»`, removeHref: remove("q") } : null,
    rubro ? { label: `Rubro: ${rubro.name}`, removeHref: remove("rubro") } : null,
    filter.scope
      ? {
          label: `Alcance: ${SCOPE_FILTERS.find((s) => s.value === filter.scope)?.label ?? ""}`,
          removeHref: remove("alcance"),
        }
      : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);

  // Volver desde la ficha a esta misma lista, con sus filtros y su página.
  const here = listHref(PATH, params, {});
  const columns: DataColumn<RecipeRow>[] = [
    {
      key: "code",
      header: "Código",
      sortKey: "code",
      // En el celular va debajo del nombre.
      mobile: "hidden",
      cell: (row) => <span className="whitespace-nowrap tabular-nums">{row.code}</span>,
    },
    {
      key: "name",
      header: "Receta",
      sortKey: "name",
      mobile: "title",
      cell: (row) => (
        <span className="flex flex-col">
          <Link
            href={`/recetas/${row.id}?volver=${encodeURIComponent(here)}`}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {row.name}
          </Link>
          <span className="text-sm text-ink-muted tabular-nums desk:hidden">{row.code}</span>
        </span>
      ),
    },
    { key: "category", header: "Rubro", cell: (row) => row.category || "—" },
    { key: "place", header: "Alcance", cell: (row) => row.place },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (row) => <StatusBadges row={row} />,
    },
    ...(costs && costPlace
      ? [
          {
            key: "cost",
            header: `Costo sin IVA en ${costPlace.name}`,
            align: "right" as const,
            cell: (row: RecipeRow) => {
              const cost = costs[row.id];
              if (!cost) return <span className="text-sm text-ink-muted">Sin costo</span>;
              const r = RELIABILITY[cost.reliability];
              return (
                <span className="flex flex-col items-end gap-1">
                  {cost.total === null ? "Sin costo" : formatMoney(cost.total)}
                  <Badge status={r.status}>{r.label}</Badge>
                </span>
              );
            },
          },
        ]
      : []),
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-3 desk:flex-row desk:items-start desk:justify-between">
        <SegmentedLinks
          label="Tipo de receta"
          unit="recetas"
          items={RECIPE_LIST_TABS.map((t, i) => ({
            href: listHref(PATH, params, {
              tipo: t.value === "platos" ? undefined : t.value,
              rubro: undefined,
              pagina: undefined,
            }),
            label: t.label,
            count: counts[i] ?? 0,
            current: t.value === tab.value,
          }))}
        />
        <FilterBar label="Filtros de recetas" active={active}>
          <Field id="rec-filtro-q" label="Buscar" className="w-full desk:w-64">
            <Input
              type="search"
              name="q"
              defaultValue={filter.search}
              placeholder="Nombre o código"
            />
          </Field>
          <Field id="rec-filtro-alcance" label="Alcance" className="w-full desk:w-44">
            <Select name="alcance" defaultValue={filter.scope ?? ""}>
              <option value="">Todos</option>
              {SCOPE_FILTERS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </Select>
          </Field>
        </FilterBar>
      </div>
      <RubroFilterGrid
        label={`Rubros de ${tab.label.toLowerCase()}`}
        rubros={rubros}
        selectedId={rubro?.id}
        hrefFor={(id) => listHref(PATH, params, { rubro: id, pagina: undefined })}
        words={{ one: "receta", many: "recetas" }}
      />
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 receta" : `${total.toLocaleString("es-AR")} recetas`}
        </CardTitle>
        <Tabs
          label="Estado de las recetas"
          items={STATUS_TABS.map((t) => ({
            href: listHref(PATH, params, { estado: t.value, pagina: undefined }),
            label: t.label,
            current:
              (status ?? undefined) === t.value ||
              (!t.value && !STATUS_TABS.some((x) => x.value === status)),
          }))}
        />
        {rows.length === 0 && list.page > 1 ? (
          <EmptyState title="Esa página no existe.">
            <Link
              href={listHref(PATH, params, { pagina: undefined })}
              className="text-primary underline-offset-4 hover:underline"
            >
              Ir a la primera página
            </Link>
          </EmptyState>
        ) : (
          <DataTable
            caption="Recetas"
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState
                title={
                  active.length > 0 || filter.status
                    ? "No hay recetas con esos filtros."
                    : `Todavía no hay ${tab.label.toLowerCase()}.`
                }
              >
                {active.length > 0 || filter.status
                  ? "Probá con otro nombre, rubro o pestaña."
                  : menus.recipesDraft
                    ? "Cargá la primera con «Nueva receta»."
                    : "Las cargan los chefs y jefes de cocina."}
                {/* Lo buscado puede estar en la otra pestaña (por ejemplo, una salsa buscada desde Platos). */}
                {otherTab && otherCount > 0 ? (
                  <>
                    {" "}
                    <Link
                      href={listHref(PATH, params, {
                        tipo: otherTab.value === "platos" ? undefined : otherTab.value,
                        rubro: undefined,
                        pagina: undefined,
                      })}
                      className="text-primary underline underline-offset-4"
                    >
                      Ver {otherCount.toLocaleString("es-AR")} en {otherTab.label}
                    </Link>
                  </>
                ) : null}
              </EmptyState>
            }
          />
        )}
        {total > 0 ? (
          <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
        ) : null}
      </Card>
    </div>
  );
}
