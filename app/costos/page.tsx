import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { CostsTable } from "@/components/costs-table";
import { FiltersPanel } from "@/components/filters-panel";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Input, Select } from "@/components/ui/field";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { cleanSearch } from "@/lib/catalog";
import {
  COSTS_PAGE,
  RELIABILITY,
  RELIABILITY_KEYS,
  getCostSummary,
  getRecalcStatus,
  getRestaurantCosts,
  resolveCostPlace,
  type Reliability,
} from "@/lib/costs";
import { first, formatDateTime } from "@/lib/data";
import { getMenus, requireMenu } from "@/lib/auth/session";

// Costos (ADR-0032): ¿cuánto cuesta cada receta en este local? Lee el costo guardado, que la cola
// actualiza cada minuto.
export default function CostosPage({ searchParams }: PageProps<"/costos">) {
  return (
    <AppShell
      title="¿Cuánto cuesta cada receta?"
      description="El costo de las recetas en cada local, y qué tan confiable es."
    >
      <Suspense fallback={<Loading />}>
        <Costs searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Costs({ searchParams }: { searchParams: PageProps<"/costos">["searchParams"] }) {
  const session = await requireMenu("costs");
  const params = await searchParams;
  const [{ places, place }, menus] = await Promise.all([
    resolveCostPlace(session.user_id, first(params.local)),
    getMenus(),
  ]);
  if (places.length === 0) return <EmptyState title="No tenés locales donde ver costos." />;

  const search = cleanSearch(first(params.q));
  const wanted = first(params.confiabilidad);
  const reliability = RELIABILITY_KEYS.find((k) => k === wanted);
  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(params.pagina) ?? "1", 10) - 1 || 0, 1000),
  );

  const filters = (
    <FiltersPanel
      active={[
        place?.name,
        search ? `«${search}»` : null,
        reliability ? RELIABILITY[reliability].label : null,
      ].filter((x): x is string => Boolean(x))}
    >
      <form
        method="get"
        role="search"
        aria-label="Filtros de costos"
        className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
      >
        <Field id="costos-local" label="Local">
          <Select name="local" defaultValue={place?.id ?? ""}>
            {place ? null : <option value="">Elegí un local</option>}
            {places.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="costos-q" label="Buscar">
          <Input name="q" defaultValue={search} placeholder="Nombre o código" />
        </Field>
        <Field id="costos-confiabilidad" label="Confiabilidad">
          <Select name="confiabilidad" defaultValue={reliability ?? ""}>
            <option value="">Todas</option>
            {RELIABILITY_KEYS.map((k) => (
              <option key={k} value={k}>
                {RELIABILITY[k].label}
              </option>
            ))}
          </Select>
        </Field>
        <Button type="submit">Filtrar</Button>
      </form>
    </FiltersPanel>
  );

  const scenarios = menus.scenarios ? (
    <div>
      <Button asChild variant="outline">
        <Link href={`/costos/escenarios${place ? `?local=${place.id}` : ""}`}>Escenarios</Link>
      </Button>
    </div>
  ) : null;

  if (!place)
    return (
      <>
        {filters}
        {scenarios}
        <EmptyState title="Elegí un local para ver sus costos." />
      </>
    );

  return (
    <>
      {filters}
      {scenarios}
      <CostList
        placeId={place.id}
        placeName={place.name}
        search={search}
        reliability={reliability}
        page={page}
      />
    </>
  );
}

async function CostList({
  placeId,
  placeName,
  search,
  reliability,
  page,
}: {
  placeId: string;
  placeName: string;
  search?: string;
  reliability?: Reliability;
  page: number;
}) {
  const [{ rows, total }, summary, status] = await Promise.all([
    getRestaurantCosts({ restaurantId: placeId, search, reliability, page }),
    getCostSummary(placeId),
    getRecalcStatus(),
  ]);
  const pages = Math.max(1, Math.ceil(total / COSTS_PAGE));
  const pageLink = (n: number) => {
    const query = new URLSearchParams({ local: placeId, pagina: String(n + 1) });
    if (search) query.set("q", search);
    if (reliability) query.set("confiabilidad", reliability);
    return `/costos?${query.toString()}`;
  };

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
      <div className="grid gap-4 sm:grid-cols-3">
        <Kpi
          label="Recetas al día"
          value={summary.complete}
          detail={`de ${summary.total}`}
          status={summary.complete === summary.total ? "ok" : "neutral"}
          statusLabel={summary.complete === summary.total ? "Todas al día" : "Algunas para revisar"}
        />
        <Kpi
          label="Desactualizadas"
          value={summary.stale}
          status={summary.stale > 0 ? "warn" : "ok"}
          statusLabel={summary.stale > 0 ? "Algún precio venció" : "Ninguna"}
        />
        <Kpi
          label="Incompletas"
          value={summary.incomplete}
          status={summary.incomplete > 0 ? "bad" : "ok"}
          statusLabel={summary.incomplete > 0 ? "Falta un dato" : "Ninguna"}
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
        {rows.length === 0 && page > 0 ? (
          <EmptyState title="Esa página no existe.">
            <Link href={pageLink(0)} className="text-primary underline-offset-4 hover:underline">
              Ir a la primera página
            </Link>
          </EmptyState>
        ) : rows.length === 0 && summary.total > 0 ? (
          <EmptyState title="No hay recetas con esos filtros.">
            Probá con otro nombre o confiabilidad.
          </EmptyState>
        ) : rows.length === 0 ? (
          <EmptyState title="Este local todavía no tiene recetas con costo.">
            Aparecen cuando se le asigna una receta publicada.
          </EmptyState>
        ) : (
          <CostsTable rows={rows} placeId={placeId} />
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
