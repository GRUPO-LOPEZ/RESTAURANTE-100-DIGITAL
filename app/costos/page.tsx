import Link from "next/link";
import { Suspense } from "react";
import { FlaskConical } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { PlacePrompt } from "@/components/place-prompt";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { cleanSearch } from "@/lib/catalog";
import {
  COST_SORT_KEYS,
  RELIABILITY,
  RELIABILITY_KEYS,
  getCostSummary,
  getRecalcStatus,
  getRestaurantCosts,
  resolveCostPlace,
  type CostRow,
  type Reliability,
} from "@/lib/costs";
import { first, formatDateTime } from "@/lib/data";
import { listHref, parseList, plainParams, type ListState } from "@/lib/list-params";
import { formatMoney } from "@/lib/money";
import { RECIPE_TYPE_LABELS } from "@/lib/recipe-format";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Costos (ADR-0032; pantalla de listado del rediseño, ADR-0036): ¿cuánto cuesta cada receta en este local?
// Lee el costo guardado, que la cola actualiza cada minuto. El local sale de la barra de arriba (o de ?local=).
export default function CostosPage({ searchParams }: PageProps<"/costos">) {
  return (
    <AppShell
      title="¿Cuánto cuesta cada receta?"
      description="El costo de las recetas en cada local, y qué tan confiable es."
      actions={
        <Suspense fallback={null}>
          <Actions searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Costs searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Escenarios, con el mismo local de la lista.
async function Actions({ searchParams }: { searchParams: PageProps<"/costos">["searchParams"] }) {
  const [menus, raw, session] = await Promise.all([getMenus(), searchParams, requireMenu("costs")]);
  if (!menus.scenarios) return null;
  const { place } = await resolveCostPlace(session.user_id, first(raw.local));
  return (
    <Button asChild variant="outline">
      <Link href={`/costos/escenarios${place ? `?local=${place.id}` : ""}`}>
        <FlaskConical aria-hidden="true" />
        Escenarios
      </Link>
    </Button>
  );
}

const PATH = "/costos";

async function Costs({ searchParams }: { searchParams: PageProps<"/costos">["searchParams"] }) {
  const session = await requireMenu("costs");
  const raw = await searchParams;
  const { places, place } = await resolveCostPlace(session.user_id, first(raw.local));
  if (places.length === 0) return <EmptyState title="No tenés locales donde ver costos." />;
  if (!place) {
    return <PlacePrompt title="Elegí un local para ver sus costos." places={places} path={PATH} />;
  }
  const params = plainParams(raw);
  const search = cleanSearch(first(raw.q));
  const reliability = RELIABILITY_KEYS.find((k) => k === first(raw.confiabilidad));
  const list = parseList(raw, COST_SORT_KEYS, "name");
  return (
    <CostList
      placeId={place.id}
      placeName={place.name}
      search={search}
      reliability={reliability}
      list={list}
      params={params}
    />
  );
}

async function CostList({
  placeId,
  placeName,
  search,
  reliability,
  list,
  params,
}: {
  placeId: string;
  placeName: string;
  search?: string;
  reliability?: Reliability;
  list: ListState;
  params: Record<string, string>;
}) {
  const [{ rows, total }, summary, status] = await Promise.all([
    getRestaurantCosts({
      restaurantId: placeId,
      search,
      reliability,
      page: list.page - 1,
      size: list.size,
      order: list.sort ? `${list.dir === "desc" ? "-" : ""}${list.sort}` : undefined,
    }),
    getCostSummary(placeId),
    getRecalcStatus(),
  ]);
  // Volver desde el detalle a esta misma lista, con sus filtros y su página.
  const known = ["local", "q", "confiabilidad", "orden", "pagina", "filas"];
  const here = listHref(
    PATH,
    Object.fromEntries(Object.entries(params).filter(([k]) => known.includes(k))),
    {},
  );
  const detail = (row: CostRow) =>
    `/costos/${row.recipeId}?local=${placeId}&volver=${encodeURIComponent(here)}`;
  const columns: DataColumn<CostRow>[] = [
    {
      key: "name",
      header: "Receta",
      sortKey: "name",
      mobile: "title",
      cell: (row) => (
        <span className="flex flex-col">
          <Link
            href={detail(row)}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {row.name}
          </Link>
          <span className="text-sm text-ink-muted tabular-nums">
            {row.code} ·{" "}
            {RECIPE_TYPE_LABELS[row.type as keyof typeof RECIPE_TYPE_LABELS] ?? row.type}
          </span>
        </span>
      ),
    },
    {
      key: "total",
      header: "Costo sin IVA",
      sortKey: "total",
      align: "right",
      cell: (row) => (row.total === null ? "—" : formatMoney(row.total)),
    },
    {
      key: "gross",
      header: "Con IVA",
      align: "right",
      cell: (row) => (row.gross === null ? "—" : formatMoney(row.gross)),
    },
    {
      key: "portion",
      header: "Por porción",
      sortKey: "portion",
      align: "right",
      cell: (row) => (row.perPortion === null ? "—" : formatMoney(row.perPortion)),
    },
    {
      key: "reliability",
      header: "Confiabilidad",
      sortKey: "reliability",
      mobile: "status",
      cell: (row) => (
        <Badge status={RELIABILITY[row.reliability].status}>
          {RELIABILITY[row.reliability].label}
        </Badge>
      ),
    },
    {
      key: "updated",
      header: "Actualizado",
      sortKey: "updated",
      align: "right",
      cell: (row) => formatDateTime(row.updatedAt),
    },
  ];
  const tab = (key: Reliability | undefined) =>
    listHref(PATH, params, { confiabilidad: key, pagina: undefined });
  const noCosts = summary.total === 0;

  return (
    <>
      {status.failed > 0 ? (
        <Notice status="bad">
          {status.failed === 1
            ? "Un recálculo no se pudo hacer: algún costo puede estar viejo. Avisale a quien administra el sistema."
            : `${status.failed} recálculos no se pudieron hacer: algunos costos pueden estar viejos. Avisale a quien administra el sistema.`}
        </Notice>
      ) : null}
      {status.pending > 0 ? (
        <Notice status="info">
          Hay cambios por aplicar: los costos se actualizan en un minuto.
        </Notice>
      ) : null}
      {/* Métricas confiables: sin recetas con costo, nunca «Todas al día». */}
      <div className="grid gap-4 desk:grid-cols-3">
        <Metric
          label="Recetas al día"
          value={summary.complete}
          total={summary.total}
          emptyLabel="Sin recetas con costo calculado"
          comparison={`de ${summary.total}`}
          status={summary.complete === summary.total ? "ok" : "warn"}
          statusLabel={summary.complete === summary.total ? "Todas al día" : "Algunas para revisar"}
        />
        <Metric
          label="Desactualizadas"
          value={summary.stale}
          total={summary.total}
          emptyLabel="Sin recetas con costo calculado"
          status={summary.stale > 0 ? "warn" : "ok"}
          statusLabel={summary.stale > 0 ? "Algún precio venció" : "Ninguna"}
          href={summary.stale > 0 ? tab("stale") : undefined}
          hrefLabel="Ver cuáles"
        />
        <Metric
          label="Incompletas"
          value={summary.incomplete}
          total={summary.total}
          emptyLabel="Sin recetas con costo calculado"
          status={summary.incomplete > 0 ? "bad" : "ok"}
          statusLabel={summary.incomplete > 0 ? "Falta un dato" : "Ninguna"}
          href={summary.incomplete > 0 ? tab("incomplete") : undefined}
          hrefLabel="Ver cuáles"
        />
      </div>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle>{placeName}</CardTitle>
          <CardDescription>
            {summary.updatedAt
              ? `Última actualización: ${formatDateTime(summary.updatedAt)}`
              : "Todavía no se calculó ningún costo."}
          </CardDescription>
        </div>
        <FilterBar
          label="Filtros de costos"
          active={
            search
              ? [
                  {
                    label: `Buscar: «${search}»`,
                    removeHref: listHref(PATH, params, { q: undefined, pagina: undefined }),
                  },
                ]
              : []
          }
        >
          <Field id="costos-q" label="Buscar" className="w-full desk:w-72">
            <Input type="search" name="q" defaultValue={search} placeholder="Nombre o código" />
          </Field>
        </FilterBar>
        <Tabs
          label="Confiabilidad"
          items={[
            { href: tab(undefined), label: "Todas", current: !reliability, count: summary.total },
            ...RELIABILITY_KEYS.map((k) => ({
              href: tab(k),
              label: RELIABILITY[k].label,
              current: reliability === k,
              ...(k === "stale" ? { count: summary.stale } : {}),
              ...(k === "incomplete" ? { count: summary.incomplete } : {}),
            })),
          ]}
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
            caption="Costos de las recetas"
            columns={columns}
            rows={rows}
            rowKey={(r) => r.recipeId}
            list={list}
            path={PATH}
            params={params}
            empty={
              noCosts ? (
                <EmptyState title="Este local todavía no tiene recetas con costo.">
                  Aparecen cuando se le asigna una receta publicada.
                </EmptyState>
              ) : (
                <EmptyState title="No hay recetas con esos filtros.">
                  Probá con otro nombre o confiabilidad.
                </EmptyState>
              )
            }
          />
        )}
        {total > 0 ? (
          <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
        ) : null}
      </Card>
    </>
  );
}
