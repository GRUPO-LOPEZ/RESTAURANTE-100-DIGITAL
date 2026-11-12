import Link from "next/link";
import { Suspense } from "react";
import { Settings } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { CreateModal } from "@/components/create-modal";
import { NewIngredientForm } from "@/components/new-ingredient-form";
import { RubroFilterGrid } from "@/components/rubro-filter";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import {
  INGREDIENT_SORT_KEYS,
  cleanSearch,
  getCategories,
  getIngredients,
  type IngredientRow,
  type IngredientsFilter,
} from "@/lib/catalog";
import { first, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { getRubros, withSubcategories } from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Materias primas (sección 18; listado del rediseño, ADR-0036; ordenado por rubro, ADR-0041): ¿qué compramos y cómo
// lo usamos? Cada una se carga una sola vez para todo el grupo. Arriba, las tarjetas de los rubros de compra, que
// filtran la tabla con un clic.
export default function MateriasPrimasPage({ searchParams }: PageProps<"/materias-primas">) {
  return (
    <AppShell
      title="Materias primas"
      description="Lo que compramos, una sola vez para todo el grupo: cómo se compra, cómo se mide y sus alérgenos."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Ingredients searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  const menus = await getMenus();
  return (
    <>
      {menus.catalogSettings ? (
        <Button asChild variant="outline">
          <Link href="/materias-primas/configuracion">
            <Settings aria-hidden="true" />
            Configuración
          </Link>
        </Button>
      ) : null}
      {menus.catalogManage ? (
        <CreateModal
          href="/materias-primas/nueva"
          label="Nueva materia prima"
          title="Nueva materia prima"
          description="Se carga una sola vez para todo el grupo. Después le agregás cómo se compra, sus conversiones y alérgenos."
        >
          <NewIngredientForm inModal />
        </CreateModal>
      ) : null}
    </>
  );
}

const PATH = "/materias-primas";
// Pestañas de estado, sobre el filtro que ya existía (?estado=active|inactive).
const STATUS_TABS = [
  { value: undefined, label: "Todas" },
  { value: "active", label: "Activas" },
  { value: "inactive", label: "Desactivadas" },
] as const;

async function Ingredients({
  searchParams,
}: {
  searchParams: PageProps<"/materias-primas">["searchParams"];
}) {
  await requireMenu("catalog");
  const raw = await searchParams;
  const params = plainParams(raw);
  const status = first(raw.estado);
  const list = parseList(raw, INGREDIENT_SORT_KEYS, "name");
  const [categories, rubrosData] = await Promise.all([getCategories(), getRubros()]);
  const rubros = (rubrosData?.rubros ?? []).filter((r) => r.rubroClass === "purchase");
  const rubroId = uuidOrUndefined(first(raw.rubro));
  const rubro = rubros.find((r) => r.id === rubroId);
  const filter: IngredientsFilter = {
    search: cleanSearch(first(raw.q)),
    categoryIds: rubro ? withSubcategories(categories, rubro.id) : undefined,
    status: status === "active" || status === "inactive" ? status : undefined,
    page: list.page - 1,
    size: list.size,
    sort: INGREDIENT_SORT_KEYS.find((k) => k === list.sort),
    desc: list.dir === "desc",
  };
  const [{ rows, total }, menus] = await Promise.all([getIngredients(filter), getMenus()]);

  const remove = (key: string) => listHref(PATH, params, { [key]: undefined, pagina: undefined });
  const active = [
    filter.search ? { label: `Buscar: «${filter.search}»`, removeHref: remove("q") } : null,
    rubro ? { label: `Rubro: ${rubro.name}`, removeHref: remove("rubro") } : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);
  // Volver desde la ficha a esta misma lista, con sus filtros y su página.
  const here = listHref(PATH, params, {});

  const columns: DataColumn<IngredientRow>[] = [
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
      header: "Materia prima",
      sortKey: "name",
      mobile: "title",
      cell: (row) => (
        <span className="flex flex-col">
          <Link
            href={`/materias-primas/${row.id}?volver=${encodeURIComponent(here)}`}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {row.name}
          </Link>
          <span className="text-sm text-ink-muted tabular-nums desk:hidden">{row.code}</span>
        </span>
      ),
    },
    { key: "category", header: "Rubro", cell: (row) => row.category || "—" },
    { key: "unit", header: "Se mide en", mobile: "hidden", cell: (row) => row.unit || "—" },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (row) =>
        row.isActive ? <Badge status="ok">Activa</Badge> : <Badge status="none">Desactivada</Badge>,
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <FilterBar label="Filtros de materias primas" active={active}>
        <Field id="mp-q" label="Buscar" className="w-full desk:w-72">
          <Input
            type="search"
            name="q"
            defaultValue={filter.search}
            placeholder="Nombre, código o alias"
          />
        </Field>
      </FilterBar>
      <RubroFilterGrid
        label="Rubros de compra"
        rubros={rubros}
        selectedId={rubro?.id}
        hrefFor={(id) => listHref(PATH, params, { rubro: id, pagina: undefined })}
        words={{ one: "materia prima", many: "materias primas" }}
      />
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 materia prima" : `${total.toLocaleString("es-AR")} materias primas`}
        </CardTitle>
        <Tabs
          label="Estado de las materias primas"
          items={STATUS_TABS.map((t) => ({
            href: listHref(PATH, params, { estado: t.value, pagina: undefined }),
            label: t.label,
            current: t.value === filter.status,
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
            caption="Materias primas"
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
                    ? "No hay materias primas con esos filtros."
                    : "Todavía no hay materias primas."
                }
              >
                {active.length > 0 || filter.status
                  ? "Probá con otro nombre, código, alias, rubro o pestaña."
                  : menus.catalogManage
                    ? "Cargá la primera con «Nueva materia prima»."
                    : "Las carga Compras."}
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
