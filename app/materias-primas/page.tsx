import Link from "next/link";
import { Suspense } from "react";
import { Settings } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { CreateModal } from "@/components/create-modal";
import { NewIngredientForm } from "@/components/new-ingredient-form";
import { RecipePhotoImage } from "@/components/recipe-photo-image";
import { RubroPanel } from "@/components/rubro-panel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
  getIngredientPhotos,
  getIngredients,
  type IngredientRow,
  type IngredientsFilter,
} from "@/lib/catalog";
import { first, uuidOrUndefined } from "@/lib/data";
import { resolvePricePlace } from "@/lib/costs";
import { listPriceState, listPriceText } from "@/lib/ingredient-price";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { getListPrices } from "@/lib/prices";
import { getRubros, withSubcategories } from "@/lib/recipes";
import { countUnmappedArticles } from "@/lib/price-lists-data";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { panelRubros } from "@/lib/rubros";

// Materias primas (sección 18; listado del rediseño, ADR-0036; ordenado por rubro, ADR-0041): ¿qué compramos y cómo
// lo usamos? Cada una se carga una sola vez para todo el grupo. En la computadora entra en una pantalla (ADR-0066):
// a la izquierda, los rubros, que no se mueven; a la derecha, la tabla, que se desplaza adentro.
export default function MateriasPrimasPage({ searchParams }: PageProps<"/materias-primas">) {
  return (
    <AppShell
      title="Materias primas"
      fill
      meta={
        <span className="text-sm text-ink-muted">Lo que compramos, una sola vez para el grupo</span>
      }
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
  // La cola de mapeo (ADR-0052): la resuelve el chef; Compras la ve. Con el número de lo que espera.
  const queue = menus.unmappedQueue ? await countUnmappedArticles() : 0;
  return (
    <>
      {menus.mapArticles || (menus.unmappedQueue && queue > 0) ? (
        <Button asChild variant="outline">
          <Link href="/materias-primas/sin-mapear">Artículos sin mapear ({queue})</Link>
        </Button>
      ) : null}
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
  const session = await requireMenu("catalog");
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
  const ids = rows.map((r) => r.id);
  // El precio vigente, solo para quien ve precios y en el local de arriba (decisión de Joaco, ADR-0066).
  const priced = menus.pricesView ? await resolvePricePlace(session.user_id) : null;
  const [photos, prices] = await Promise.all([
    getIngredientPhotos(ids),
    priced?.place ? getListPrices(ids, priced.place.id) : null,
  ]);

  const remove = (key: string) => listHref(PATH, params, { [key]: undefined, pagina: undefined });
  const active = [
    filter.search ? { label: `Buscar: «${filter.search}»`, removeHref: remove("q") } : null,
    rubro ? { label: `Rubro: ${rubro.name}`, removeHref: remove("rubro") } : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);
  // Volver desde la ficha a esta misma lista, con sus filtros y su página.
  const here = listHref(PATH, params, {});

  const columns: DataColumn<IngredientRow>[] = [
    {
      key: "name",
      header: "Materia prima",
      sortKey: "name",
      mobile: "title",
      cell: (row) => (
        <span className="flex items-center gap-2">
          <Thumb photo={photos?.get(row.id)} />
          <span className="flex min-w-0 flex-col">
            <Link
              href={`/materias-primas/${row.id}?volver=${encodeURIComponent(here)}`}
              title={row.name}
              className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:block desk:min-h-7 desk:max-w-44 desk:truncate desk:leading-7 desk:focus-visible:max-w-none wide:max-w-80"
            >
              {row.name}
            </Link>
            <span className="text-sm text-ink-muted tabular-nums desk:hidden">{row.code}</span>
          </span>
        </span>
      ),
    },
    {
      key: "code",
      header: "Código",
      sortKey: "code",
      // En el celular va debajo del nombre.
      mobile: "hidden",
      cell: (row) => <span className="text-sm whitespace-nowrap tabular-nums">{row.code}</span>,
    },
    // Con un rubro elegido, la columna repetiría lo mismo en todas las filas.
    ...(rubro
      ? []
      : [
          {
            key: "category",
            header: "Rubro",
            cell: (row: IngredientRow) => <span className="text-sm">{row.category || "—"}</span>,
          },
        ]),
    // Con el precio («/ kg») y el rubro a la vista, la unidad no entra de ancho ni hace falta.
    ...(prices && !rubro
      ? []
      : [
          {
            key: "unit",
            header: "Se mide en",
            mobile: "hidden" as const,
            cell: (row: IngredientRow) => row.unit || "—",
          },
        ]),
    ...(prices
      ? [
          {
            key: "price",
            header: "Precio vigente",
            align: "right" as const,
            cell: (row: IngredientRow) => (
              <span className="text-sm">{listPriceText(prices.get(row.id)) ?? "—"}</span>
            ),
          },
        ]
      : []),
    {
      key: "status",
      header: prices ? "Estado del precio" : "Estado",
      mobile: "status",
      cell: (row) => {
        if (!row.isActive) return <Badge status="none">Desactivada</Badge>;
        if (!prices) return <Badge status="ok">Activa</Badge>;
        // Con precios, el estado es el del precio (como en el boceto): una activa sin precio no dice «Al día».
        const state = listPriceState(prices.get(row.id));
        return <Badge status={state.status}>{state.label}</Badge>;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-4 xl:grid xl:min-h-112 xl:flex-[1_1_0px] xl:grid-cols-[250px_minmax(0,1fr)] xl:grid-rows-[minmax(0,1fr)]">
      <RubroPanel
        label="Rubros de compra"
        rubros={panelRubros(rubros)}
        selectedId={rubro?.id}
        hrefFor={(id) => listHref(PATH, params, { rubro: id, pagina: undefined })}
        all={{
          href: listHref(PATH, params, { rubro: undefined, pagina: undefined }),
          count: rubros.reduce((n, r) => n + r.uses, 0),
        }}
        words={{ one: "materia prima", many: "materias primas" }}
      />
      <section
        aria-label="Lista de materias primas"
        className="flex min-w-0 flex-col gap-3 desk:h-160 desk:rounded-md desk:border desk:border-line desk:bg-surface desk:p-4 xl:h-auto xl:min-h-0"
      >
        <div className="flex flex-col gap-3 desk:flex-row desk:flex-wrap desk:items-end desk:justify-between">
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
          <div className="flex flex-wrap items-baseline gap-x-2 tabular-nums">
            <h2 className="text-base font-semibold text-ink">
              {total === 1 ? "1 materia prima" : `${total.toLocaleString("es-AR")} materias primas`}
            </h2>
            <p className="text-sm text-ink-muted">
              {priced
                ? priced.place
                  ? `precios de ${priced.place.name}`
                  : priced.blockedActive
                    ? `no ves precios de ${priced.blockedActive}`
                    : "para ver los precios, elegí un local arriba"
                : ""}
            </p>
          </div>
        </div>
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
            scroll
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
      </section>
    </div>
  );
}

// La foto, chica. Sin foto, un cuadro vacío: las filas quedan alineadas.
function Thumb({ photo }: { photo: { url: string | null } | undefined }) {
  const empty = <span aria-hidden="true" className="size-8 shrink-0 rounded-sm bg-none" />;
  if (!photo?.url) return empty;
  return (
    // El nombre está al lado: la foto no lo repite. Si no carga, queda el cuadro vacío.
    <RecipePhotoImage
      url={photo.url}
      alt=""
      fallback={empty}
      className="size-8 shrink-0 object-cover"
    />
  );
}
