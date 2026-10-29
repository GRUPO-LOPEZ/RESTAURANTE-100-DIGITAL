import Link from "next/link";
import { Suspense } from "react";
import { Plus } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { IngredientsTable } from "@/components/ingredients-table";
import { Button } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState } from "@/components/ui/kpi";
import {
  INGREDIENTS_PAGE,
  cleanSearch,
  getCategories,
  getIngredients,
  type IngredientsFilter,
} from "@/lib/catalog";
import { first, uuidOrUndefined } from "@/lib/data";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Materias primas (sección 18): ¿qué compramos y cómo lo usamos? Cada una se carga una sola vez
// para todo el grupo. Precios y rendimientos llegan en las próximas etapas.
export default function MateriasPrimasPage({ searchParams }: PageProps<"/materias-primas">) {
  return (
    <AppShell
      title="Materias primas"
      description="Lo que compramos, una sola vez para todo el grupo: cómo se compra, cómo se mide y sus alérgenos."
    >
      <Suspense fallback={<Loading />}>
        <Ingredients searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const STATUS_TEXT = { active: "Activas", inactive: "Desactivadas" } as const;

async function Ingredients({
  searchParams,
}: {
  searchParams: PageProps<"/materias-primas">["searchParams"];
}) {
  await requireMenu("catalog");
  const params = await searchParams;
  const status = first(params.estado);
  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(params.pagina) ?? "1", 10) - 1 || 0, 1000),
  );
  const filter: IngredientsFilter = {
    search: cleanSearch(first(params.q)),
    categoryId: uuidOrUndefined(first(params.categoria)),
    status: status === "active" || status === "inactive" ? status : undefined,
    page,
  };
  const [{ rows, total }, categories, menus] = await Promise.all([
    getIngredients(filter),
    getCategories(),
    getMenus(),
  ]);
  const pages = Math.max(1, Math.ceil(total / INGREDIENTS_PAGE));

  const pageLink = (n: number) => {
    const query = new URLSearchParams();
    if (filter.search) query.set("q", filter.search);
    if (filter.categoryId) query.set("categoria", filter.categoryId);
    if (filter.status) query.set("estado", filter.status);
    query.set("pagina", String(n + 1));
    return `/materias-primas?${query.toString()}`;
  };

  const activeFilters = [
    filter.search ? `«${filter.search}»` : null,
    filter.categoryId ? categories.find((c) => c.id === filter.categoryId)?.label : null,
    filter.status ? STATUS_TEXT[filter.status] : null,
  ].filter((x): x is string => Boolean(x));

  return (
    <>
      <FiltersPanel active={activeFilters}>
        <form
          method="get"
          role="search"
          aria-label="Filtros de materias primas"
          className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5 lg:items-end"
        >
          <Field id="mp-q" label="Buscar" className="lg:col-span-2">
            <Input name="q" defaultValue={filter.search} placeholder="Nombre, código o alias" />
          </Field>
          <Field id="mp-categoria" label="Categoría">
            <Select name="categoria" defaultValue={filter.categoryId ?? ""}>
              <option value="">Todas</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="mp-estado" label="Estado">
            <Select name="estado" defaultValue={filter.status ?? ""}>
              <option value="">Todas</option>
              <option value="active">Activas</option>
              <option value="inactive">Desactivadas</option>
            </Select>
          </Field>
          <Button type="submit">Filtrar</Button>
        </form>
      </FiltersPanel>

      <Card className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="tabular-nums">
            {total === 1 ? "1 materia prima" : `${total.toLocaleString("es-AR")} materias primas`}
          </CardTitle>
          {menus.catalogManage ? (
            <Button asChild variant="outline">
              <Link href="/materias-primas/nueva">
                <Plus aria-hidden="true" />
                Nueva materia prima
              </Link>
            </Button>
          ) : null}
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
                ? "No hay materias primas con esos filtros."
                : "Todavía no hay materias primas."
            }
          >
            {activeFilters.length > 0
              ? "Probá con otro nombre, código, alias o categoría."
              : menus.catalogManage
                ? "Cargá la primera con «Nueva materia prima»."
                : "Las carga Compras."}
          </EmptyState>
        ) : (
          <IngredientsTable rows={rows} />
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
