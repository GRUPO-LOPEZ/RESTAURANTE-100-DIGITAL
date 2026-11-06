import { ChevronRight } from "lucide-react";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select } from "@/components/ui/field";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { pickCostPlace } from "@/lib/costs";
import { first, formatDateTime, getActiveRestaurantId } from "@/lib/data";
import {
  getQuality,
  getQualityCompare,
  getQualityPlaces,
  type QualityCount,
  type QualityPlace,
} from "@/lib/quality";
import {
  QUALITY_AXES,
  QUALITY_COMPARE,
  QUALITY_INDICATORS,
  QUALITY_COMPARE_LIMIT,
  qualityIndicator,
  qualityPercent,
  type QualityIndicator,
} from "@/lib/quality-labels";

// Calidad de datos (ADR-0033): se cuentan hechos, y lo que falta abre la lista para corregirlo.
export default function CalidadPage({ searchParams }: PageProps<"/calidad">) {
  return (
    <AppShell
      title="¿Qué tan completo y confiable está el recetario?"
      description="Tocá lo que falta para ver qué corregir."
    >
      <Suspense fallback={<Loading />}>
        <Quality searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

function IndicatorRow({
  indicator,
  count,
  placeId,
}: {
  indicator: QualityIndicator;
  count: QualityCount;
  placeId: string;
}) {
  const missing = count.total - count.done;
  const percent = qualityPercent(count.done, count.total);
  const body = (
    <>
      <span className="flex min-w-0 flex-col gap-1">
        <span className="text-base font-medium text-ink">{indicator.label}</span>
        <span className="text-sm text-ink-muted tabular-nums">
          {count.done} de {count.total}
          {percent === null ? "" : ` (${percent} %)`}
        </span>
        {indicator.hint ? <span className="text-sm text-ink-muted">{indicator.hint}</span> : null}
      </span>
      <span className="flex shrink-0 items-center gap-1">
        {count.total === 0 ? (
          <Badge status="neutral">Sin datos</Badge>
        ) : missing === 0 ? (
          <Badge status="ok">Completo</Badge>
        ) : (
          <Badge status="warn">{missing === 1 ? "Falta 1" : `Faltan ${missing}`}</Badge>
        )}
        {missing > 0 ? <ChevronRight aria-hidden="true" className="size-5 text-ink-muted" /> : null}
      </span>
    </>
  );
  const row =
    "flex min-h-touch items-center justify-between gap-4 rounded-lg border border-line p-4";
  if (missing === 0) return <li className={row}>{body}</li>;
  return (
    <li>
      <Link
        href={`/calidad/${indicator.key}?local=${placeId}`}
        className={`${row} hover:border-primary`}
      >
        {body}
      </Link>
    </li>
  );
}

function compareCell(place: QualityPlace, key: string) {
  const count = place.counts.find((c) => c.indicator === key);
  if (!count) return "—";
  const percent = qualityPercent(count.done, count.total);
  return percent === null ? "Sin datos" : `${percent} %`;
}

// Cada local tarda en calcularse: la comparación llega después, sin frenar al local elegido.
async function Compare({ total }: { total: number }) {
  const places = await getQualityCompare();
  // Solo las columnas que la persona puede ver.
  const columns = QUALITY_COMPARE.flatMap((key) => qualityIndicator(key) ?? []).filter((c) =>
    places.some((p) => p.counts.some((n) => n.indicator === c.key)),
  );
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>Cómo está cada local</CardTitle>
        <CardDescription>
          Cada local tiene sus precios, por eso no hay un total. Tocá uno para ver qué falta.
        </CardDescription>
      </div>
      <ul className="grid gap-2 sm:grid-cols-2 lg:hidden" aria-label="Calidad por local">
        {places.map((p) => (
          <li key={p.id} className="flex flex-col gap-1 rounded-lg border border-line p-4">
            <Link
              href={`/calidad?local=${p.id}`}
              className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline"
            >
              {p.name}
            </Link>
            {columns.map((c) => (
              <span key={c.key} className="text-sm text-ink tabular-nums">
                {c.label}: {compareCell(p, c.key)}
              </span>
            ))}
          </li>
        ))}
      </ul>
      <table className="hidden w-full border-collapse text-left lg:table">
        <caption className="sr-only">Porcentaje de cada indicador en cada local</caption>
        <thead>
          <tr className="border-b border-line">
            <th scope="col" className="px-3 py-2 text-sm font-medium text-ink-muted">
              Local
            </th>
            {columns.map((c) => (
              <th key={c.key} scope="col" className="px-3 py-2 text-sm font-medium text-ink-muted">
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {places.map((p) => (
            <tr key={p.id} className="border-b border-line last:border-0">
              <th scope="row" className="px-3 py-2 font-medium">
                <Link
                  href={`/calidad?local=${p.id}`}
                  className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline"
                >
                  {p.name}
                </Link>
              </th>
              {columns.map((c) => (
                <td key={c.key} className="px-3 py-2 text-ink tabular-nums">
                  {compareCell(p, c.key)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {total > places.length ? (
        <p className="text-sm text-ink-muted">
          Se comparan los primeros {QUALITY_COMPARE_LIMIT} de {total} locales. Los demás se eligen
          arriba.
        </p>
      ) : null}
    </Card>
  );
}

async function Detail({ placeId, name }: { placeId: string; name: string }) {
  const counts = await getQuality(placeId);
  if (!counts) notFound();
  const kpis = QUALITY_COMPARE.flatMap((key) => {
    const indicator = qualityIndicator(key);
    const count = counts.find((c) => c.indicator === key);
    return indicator && count ? [{ indicator, count }] : [];
  });
  const hasMoney = counts.some((c) =>
    ["recipe_cost", "ingredient_price", "price_stale"].includes(c.indicator),
  );
  return (
    <>
      <p className="text-sm text-ink-muted">
        {name} · Calculado el {formatDateTime(new Date().toISOString())}
      </p>
      {kpis.length > 0 ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {kpis.map(({ indicator, count }) => (
            <Kpi
              key={indicator.key}
              label={indicator.label}
              value={`${count.done} de ${count.total}`}
              detail={
                count.total === 0
                  ? "Sin datos"
                  : `${qualityPercent(count.done, count.total) ?? 0} %`
              }
            />
          ))}
        </div>
      ) : null}
      {QUALITY_AXES.map(({ axis, title, text }) => {
        const rows = QUALITY_INDICATORS.filter((i) => i.axis === axis).flatMap((indicator) => {
          const count = counts.find((c) => c.indicator === indicator.key);
          return count ? [{ indicator, count }] : [];
        });
        if (rows.length === 0) return null;
        // Sin ver precios ni costos, de ese eje solo queda el catálogo: no se responde por el costo.
        const catalogOnly = axis === "cost" && !hasMoney;
        const heading = catalogOnly ? "¿El catálogo está ordenado?" : title;
        return (
          <Card key={axis} className="flex flex-col gap-4">
            <div className="flex flex-col gap-1">
              <CardTitle>{heading}</CardTitle>
              <CardDescription>
                {catalogOnly ? "Los precios y costos los revisa quien tiene acceso." : text}
              </CardDescription>
            </div>
            <ul className="flex flex-col gap-2" aria-label={heading}>
              {rows.map(({ indicator, count }) => (
                <IndicatorRow
                  key={indicator.key}
                  indicator={indicator}
                  count={count}
                  placeId={placeId}
                />
              ))}
            </ul>
          </Card>
        );
      })}
    </>
  );
}

async function Quality({ searchParams }: { searchParams: PageProps<"/calidad">["searchParams"] }) {
  const session = await requireMenu("quality");
  const params = await searchParams;
  const [places, activeId] = await Promise.all([
    getQualityPlaces(),
    getActiveRestaurantId(session.user_id),
  ]);
  if (places.length === 0) return <EmptyState title="No tenés locales para revisar." />;
  const place = pickCostPlace(places, first(params.local), activeId);

  return (
    <>
      {places.length > 1 ? (
        <FiltersPanel active={place ? [place.name] : []}>
          <form
            method="get"
            role="search"
            aria-label="Elegir local"
            className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
          >
            <Field id="calidad-local" label="Local">
              <Select key={place?.id ?? "ninguno"} name="local" defaultValue={place?.id ?? ""}>
                {place ? null : <option value="">Elegí un local</option>}
                {places.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </Select>
            </Field>
            <Button type="submit">Ver</Button>
          </form>
        </FiltersPanel>
      ) : null}
      {place ? (
        <Suspense key={place.id} fallback={<Loading />}>
          <Detail placeId={place.id} name={place.name} />
        </Suspense>
      ) : (
        <Notice status="info">Tocá un local para ver qué falta.</Notice>
      )}
      {places.length > 1 ? (
        <Suspense fallback={<Loading />}>
          <Compare total={places.length} />
        </Suspense>
      ) : null}
    </>
  );
}
