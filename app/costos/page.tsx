import Link from "next/link";
import { Suspense, cache } from "react";
import { FlaskConical } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { MissingValue } from "@/components/costs/missing-value";
import { ReliabilityFilter } from "@/components/costs/reliability-filter";
import { PlacePrompt } from "@/components/place-prompt";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { cleanSearch } from "@/lib/catalog";
import {
  COST_SORT_KEYS,
  RELIABILITY,
  RELIABILITY_KEYS,
  costListMetrics,
  getCostSummary,
  getRecalcStatus,
  getRestaurantCosts,
  resolveCostPlace,
  type CostRow,
  type Reliability,
} from "@/lib/costs";
import { first, formatDate, formatDateTime } from "@/lib/data";
import { listHref, parseList, plainParams, type ListState } from "@/lib/list-params";
import { formatMoney, perBaseLabel } from "@/lib/money";
import { RECIPE_TYPE_LABELS } from "@/lib/recipe-format";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Costos (ADR-0032; en una pantalla sin scroll, ADR-0048): ¿cuánto cuesta cada receta en este local? Lee el costo
// guardado, que la cola actualiza cada minuto. El local es el de la barra de arriba (un ?local= se aplica ahí al llegar).
// En la computadora entra entera: encabezado, 4 indicadores y una tarjeta con la tabla, que se desplaza adentro.
export default function CostosPage({ searchParams }: PageProps<"/costos">) {
  return (
    <AppShell
      title="¿Cuánto cuesta cada receta?"
      fill
      meta={
        <Suspense fallback={null}>
          <Meta searchParams={searchParams} />
        </Suspense>
      }
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

const PATH = "/costos";

// Una sola lectura por pedido: la usan el encabezado, la acción y la lista.
const costPlace = cache((userId: string | undefined, local: string | undefined) =>
  resolveCostPlace(userId, local),
);
const summaryOf = cache(getCostSummary);

async function Meta({ searchParams }: { searchParams: PageProps<"/costos">["searchParams"] }) {
  const [session, raw] = await Promise.all([requireMenu("costs"), searchParams]);
  const { place } = await costPlace(session.user_id, first(raw.local));
  if (!place) return null;
  const summary = await summaryOf(place.id);
  return (
    <p className="text-sm text-ink-muted tabular-nums">
      {place.name}
      {summary.updatedAt ? ` · actualizado el ${formatDateTime(summary.updatedAt)}` : ""} · sin IVA
    </p>
  );
}

// Escenarios, con el mismo local de la lista.
async function Actions({ searchParams }: { searchParams: PageProps<"/costos">["searchParams"] }) {
  const [menus, raw, session] = await Promise.all([getMenus(), searchParams, requireMenu("costs")]);
  if (!menus.scenarios) return null;
  const { place } = await costPlace(session.user_id, first(raw.local));
  return (
    <Button asChild variant="outline">
      <Link href={`/costos/escenarios${place ? `?local=${place.id}` : ""}`}>
        <FlaskConical aria-hidden="true" />
        Escenarios
      </Link>
    </Button>
  );
}

async function Costs({ searchParams }: { searchParams: PageProps<"/costos">["searchParams"] }) {
  const session = await requireMenu("costs");
  const raw = await searchParams;
  const { places, place, blockedActive } = await costPlace(session.user_id, first(raw.local));
  if (places.length === 0) return <EmptyState title="No tenés locales donde ver costos." />;
  if (!place) {
    return (
      <PlacePrompt title="Costos se ve de a un local." places={places} activeName={blockedActive} />
    );
  }
  const params = plainParams(raw);
  const search = cleanSearch(first(raw.q));
  const reliability = RELIABILITY_KEYS.find((k) => k === first(raw.confiabilidad));
  const list = parseList(raw, COST_SORT_KEYS, "name");
  return (
    <CostList
      placeId={place.id}
      search={search}
      reliability={reliability}
      list={list}
      params={params}
    />
  );
}

// En la tabla y en los botones, «Completo»: la misma palabra en los dos lugares, y la tabla entra en 1440.
function shortReliability(key: Reliability): string {
  return key === "verified" ? "Completo" : RELIABILITY[key].label;
}

// Por qué falta un número de la tabla (el motivo va en el tooltip del «—»).
function missingWhy(row: CostRow, what: "total" | "portion" | "base"): string {
  if (what === "portion" && row.total !== null) return "Es una preparación: no tiene porciones.";
  if (what === "base" && row.total !== null) return "Falta el rendimiento de la receta.";
  return "A una línea le falta un dato: el detalle dice cuál.";
}

async function CostList({
  placeId,
  search,
  reliability,
  list,
  params,
}: {
  placeId: string;
  search?: string;
  reliability?: Reliability;
  list: ListState;
  params: Record<string, string>;
}) {
  const [{ rows, total }, summary, status, top, verified] = await Promise.all([
    getRestaurantCosts({
      restaurantId: placeId,
      search,
      reliability,
      page: list.page - 1,
      size: list.size,
      order: list.sort ? `${list.dir === "desc" ? "-" : ""}${list.sort}` : undefined,
    }),
    summaryOf(placeId),
    getRecalcStatus(),
    // El plato más caro por porción (la base deja los vacíos al final) y cuántas están completas y verificadas.
    getRestaurantCosts({ restaurantId: placeId, page: 0, size: 1, order: "-portion" }),
    getRestaurantCosts({ restaurantId: placeId, reliability: "verified", page: 0, size: 1 }),
  ]);
  // Volver desde el detalle a esta misma lista, con sus filtros y su página.
  const known = ["q", "confiabilidad", "orden", "pagina", "filas"];
  const listParams = Object.fromEntries(Object.entries(params).filter(([k]) => known.includes(k)));
  const here = listHref(PATH, listParams, {});
  const detail = (recipeId: string) =>
    `/costos/${recipeId}?local=${placeId}&volver=${encodeURIComponent(here)}`;
  const filterHref = (key: Reliability | undefined) =>
    listHref(PATH, listParams, { confiabilidad: key, pagina: undefined });

  const money = (row: CostRow, value: number | null, what: "total" | "portion" | "base") =>
    value === null ? <MissingValue why={missingWhy(row, what)} /> : formatMoney(value);
  const columns: DataColumn<CostRow>[] = [
    {
      key: "name",
      header: "Receta",
      sortKey: "name",
      mobile: "title",
      cell: (row) => (
        <span className="flex flex-wrap items-baseline gap-x-2 desk:flex-col desk:gap-0">
          <Link
            href={detail(row.recipeId)}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-7 desk:leading-tight"
          >
            {row.name}
          </Link>
          <span className="text-xs text-ink-muted tabular-nums desk:leading-tight">{row.code}</span>
        </span>
      ),
    },
    {
      key: "type",
      header: "Tipo",
      cell: (row) => RECIPE_TYPE_LABELS[row.type as keyof typeof RECIPE_TYPE_LABELS] ?? row.type,
    },
    {
      key: "total",
      header: "Costo sin IVA",
      sortKey: "total",
      align: "right",
      cell: (row) => money(row, row.total, "total"),
    },
    {
      key: "gross",
      header: "Con IVA",
      align: "right",
      cell: (row) => money(row, row.gross, "total"),
    },
    {
      key: "portion",
      header: "Por porción",
      sortKey: "portion",
      align: "right",
      cell: (row) => money(row, row.perPortion, "portion"),
    },
    {
      key: "base",
      header: "Por kg",
      align: "right",
      cell: (row) => {
        const { factor, label } = perBaseLabel(row.baseUnit);
        if (row.perBaseUnit === null) return money(row, null, "base");
        return (
          <span>
            {formatMoney(row.perBaseUnit * factor)}
            <span className="sr-only"> {label}</span>
            {label === "por kg" ? null : (
              <span aria-hidden="true" className="ml-1 text-xs text-ink-muted">
                {label === "por litro" ? "/ l" : "/ u"}
              </span>
            )}
          </span>
        );
      },
    },
    {
      key: "reliability",
      header: "Confiabilidad",
      sortKey: "reliability",
      mobile: "status",
      cell: (row) => (
        <Badge status={RELIABILITY[row.reliability].status}>
          {shortReliability(row.reliability)}
        </Badge>
      ),
    },
    {
      key: "updated",
      header: "Actualizado",
      sortKey: "updated",
      align: "right",
      cell: (row) => formatDate(row.updatedAt),
    },
  ];

  const metrics = costListMetrics(summary);
  const topRow = top.rows[0];
  const topPortion = topRow?.perPortion ?? null;
  const complete = verified.total;
  const options = [
    {
      value: "",
      label: "Todas",
      count: summary.total,
      href: filterHref(undefined),
      current: !reliability,
    },
    ...RELIABILITY_KEYS.map((k) => ({
      value: k,
      label: shortReliability(k),
      count:
        k === "verified"
          ? complete
          : k === "estimated"
            ? Math.max(summary.complete - complete, 0)
            : k === "stale"
              ? summary.stale
              : summary.incomplete,
      href: filterHref(k),
      current: reliability === k,
    })),
  ];
  const active = [
    ...(reliability
      ? [
          {
            label: `Confiabilidad: ${options.find((o) => o.value === reliability)?.label ?? ""}`,
            removeHref: filterHref(undefined),
          },
        ]
      : []),
    ...(search
      ? [
          {
            label: `Buscar: «${search}»`,
            removeHref: listHref(PATH, listParams, { q: undefined, pagina: undefined }),
          },
        ]
      : []),
  ];
  const keep = Object.fromEntries(
    Object.entries(listParams).filter(([k]) => ["q", "orden", "filas"].includes(k)),
  );
  const noCosts = summary.total === 0;

  return (
    <div className="flex flex-col gap-4 desk:min-h-0 desk:flex-[1_1_0px]">
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
      {/* Métricas confiables (lib/metrics.ts): sin recetas con costo, «Sin datos», nunca «Todas al día» ni 0 %. */}
      <div className="grid gap-3 desk:grid-cols-4">
        {metrics.map((m) => (
          <Metric
            key={m.key}
            compact
            label={m.label}
            value={m.value}
            total={m.total}
            emptyLabel="Sin recetas con costo calculado"
            comparison={`de ${m.total}`}
            status={m.status}
            statusLabel={m.statusLabel}
            href={m.filter ? filterHref(m.filter) : undefined}
            hrefLabel="Ver cuáles"
          />
        ))}
        <Metric
          compact
          label="Mayor costo por porción"
          value={topPortion === null ? null : formatMoney(topPortion)}
          total={summary.total}
          emptyLabel="Sin recetas con costo calculado"
          missingReason="Ningún plato tiene costo por porción."
          status="info"
          statusLabel=""
          action={
            topRow && topPortion !== null ? (
              <Link
                href={detail(topRow.recipeId)}
                className="inline-flex min-h-touch min-w-0 items-center truncate text-sm text-primary underline-offset-4 hover:underline desk:min-h-7"
              >
                {topRow.name}
                <span className="sr-only"> (ver su costo)</span>
              </Link>
            ) : null
          }
        />
      </div>
      <section
        aria-label="Costos de las recetas"
        className="flex flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0 desk:flex-[1_1_0px]"
      >
        <div className="flex flex-col gap-3 desk:flex-row desk:flex-wrap desk:items-start">
          <FilterBar label="Buscar en costos" active={active}>
            <Field id="costos-q" label="Buscar" className="w-full desk:w-64">
              <Input type="search" name="q" defaultValue={search} placeholder="Nombre o código" />
            </Field>
          </FilterBar>
          <div className="flex flex-col gap-1 desk:self-end">
            <ReliabilityFilter path={PATH} keep={keep} options={options} />
          </div>
        </div>
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
            scroll
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
      </section>
    </div>
  );
}
