import Link from "next/link";
import { Suspense } from "react";
import { Settings, Upload } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { NewRecipeForm } from "@/components/new-recipe-form";
import { NewRecipeModal } from "@/components/new-recipe-modal";
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
import { RELIABILITY, type Reliability } from "@/lib/cost-labels";
import { getCostsByRecipe, resolveCostPlace } from "@/lib/costs";
import { first, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { formatMoney } from "@/lib/money";
import {
  RECIPE_SORT_KEYS,
  RECIPE_TYPE_LABELS,
  SCOPE_LABELS,
  VARIANT_FILTER_LABEL,
  getRecipeCategories,
  getRecipes,
  type RecipeRow,
  type RecipeScope,
  type RecipeType,
  type RecipesFilter,
} from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Recetas (sección 18; listado del rediseño, ADR-0036): ¿qué preparamos y cómo? Preparaciones, platos y
// componentes en una sola lista. Quien ve costos y tiene un local elegido en la barra ve el costo ahí.
export default function RecetasPage({ searchParams }: PageProps<"/recetas">) {
  return (
    <AppShell
      title="Recetas"
      description="Preparaciones, platos y componentes: cómo se hacen, con qué y cuánto rinden."
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
const TYPES = Object.keys(RECIPE_TYPE_LABELS) as RecipeType[];
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
  const type = first(raw.tipo);
  const scope = first(raw.alcance);
  const status = first(raw.estado);
  const list = parseList(raw, RECIPE_SORT_KEYS, "name");
  const filter: RecipesFilter = {
    search: cleanSearch(first(raw.q)),
    type: TYPES.includes(type as RecipeType) ? (type as RecipeType) : undefined,
    scope: SCOPE_FILTERS.find((s) => s.value === scope)?.value,
    categoryId: uuidOrUndefined(first(raw.categoria)),
    status: status === "vigentes" ? "current" : status === "atencion" ? "attention" : undefined,
    page: list.page - 1,
    size: list.size,
    sort: RECIPE_SORT_KEYS.find((k) => k === list.sort),
    desc: list.dir === "desc",
  };
  const [{ rows, total }, categories, menus] = await Promise.all([
    getRecipes(filter),
    getRecipeCategories(),
    getMenus(),
  ]);
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
    filter.type
      ? { label: `Tipo: ${RECIPE_TYPE_LABELS[filter.type]}`, removeHref: remove("tipo") }
      : null,
    filter.scope
      ? {
          label: `Alcance: ${SCOPE_FILTERS.find((s) => s.value === filter.scope)?.label ?? ""}`,
          removeHref: remove("alcance"),
        }
      : null,
    filter.categoryId
      ? {
          label: `Categoría: ${categories.find((c) => c.id === filter.categoryId)?.label ?? ""}`,
          removeHref: remove("categoria"),
        }
      : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);

  // Volver desde la ficha a esta misma lista, con sus filtros y su página.
  const here = listHref(PATH, params, {});
  const columns: DataColumn<RecipeRow>[] = [
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
          <span className="text-sm text-ink-muted tabular-nums">{row.code}</span>
        </span>
      ),
    },
    {
      key: "type",
      header: "Tipo",
      sortKey: "type",
      cell: (row) => RECIPE_TYPE_LABELS[row.type],
    },
    { key: "place", header: "Alcance", cell: (row) => row.place },
    { key: "category", header: "Categoría", cell: (row) => row.category || "—" },
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
    <Card className="flex flex-col gap-4">
      <CardTitle className="tabular-nums">
        {total === 1 ? "1 receta" : `${total.toLocaleString("es-AR")} recetas`}
      </CardTitle>
      <FilterBar label="Filtros de recetas" active={active}>
        <Field id="rec-filtro-q" label="Buscar" className="w-full desk:w-64">
          <Input
            type="search"
            name="q"
            defaultValue={filter.search}
            placeholder="Nombre o código"
          />
        </Field>
        <Field id="rec-filtro-tipo" label="Tipo" className="w-full desk:w-44">
          <Select name="tipo" defaultValue={filter.type ?? ""}>
            <option value="">Todos</option>
            {TYPES.map((t) => (
              <option key={t} value={t}>
                {RECIPE_TYPE_LABELS[t]}
              </option>
            ))}
          </Select>
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
        <Field id="rec-filtro-categoria" label="Categoría" className="w-full desk:w-52">
          <Select name="categoria" defaultValue={filter.categoryId ?? ""}>
            <option value="">Todas</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
        </Field>
      </FilterBar>
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
                  : "Todavía no hay recetas."
              }
            >
              {active.length > 0 || filter.status
                ? "Probá con otro nombre, tipo, categoría o pestaña."
                : menus.recipesDraft
                  ? "Cargá la primera con «Nueva receta»."
                  : "Las cargan los chefs y jefes de cocina."}
            </EmptyState>
          }
        />
      )}
      {total > 0 ? (
        <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
      ) : null}
    </Card>
  );
}
