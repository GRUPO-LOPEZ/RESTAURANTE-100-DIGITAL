import { ChevronRight } from "lucide-react";
import Link from "next/link";
import { notFound, unstable_rethrow } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { PlacePrompt } from "@/components/place-prompt";
import { Attention, Missing } from "@/components/quality-board";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Notice } from "@/components/ui/notice";
import { ProgressBar } from "@/components/ui/progress-bar";
import { EmptyState } from "@/components/ui/states";
import { requireMenu } from "@/lib/auth/session";
import { pickCostPlace } from "@/lib/costs";
import { first, formatDateTime, getActiveRestaurantId } from "@/lib/data";
import { missingState } from "@/lib/metrics";
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
  type QualityIndicator,
} from "@/lib/quality-labels";

// Calidad de datos (ADR-0033; panel del rediseño, ADR-0036): se cuentan hechos, y lo que falta abre la
// lista para corregirlo. El local es el de la barra de arriba (selector único y global).
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

// Las 4 tarjetas de arriba: lo que falta en los indicadores que también se comparan entre locales.
const KPI_LABELS: Record<string, string> = {
  recipe_approved: "Recetas sin aprobar",
  recipe_cost: "Costo por corregir",
  ingredient_price: "Materias primas sin precio",
  price_stale: "Precios desactualizados",
};

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
  // La regla única (lib/metrics.ts): falta más de la mitad = Crítico.
  const state = missingState(missing, count.total);
  const body = (
    <>
      <span className="flex min-w-0 flex-col gap-1">
        <span className="text-base font-medium text-ink">{indicator.label}</span>
        <span className="text-sm text-ink-muted tabular-nums">
          {count.done} de {count.total}
        </span>
        {indicator.hint ? <span className="text-sm text-ink-muted">{indicator.hint}</span> : null}
      </span>
      <span className="flex shrink-0 flex-wrap items-center justify-end gap-3">
        <ProgressBar value={count.done} total={count.total} label={indicator.label} decorative />
        {count.total === 0 ? null : <Badge status={state.status}>{state.label}</Badge>}
        {missing > 0 ? <ChevronRight aria-hidden="true" className="size-5 text-ink-muted" /> : null}
      </span>
    </>
  );
  const row =
    "flex min-h-touch flex-wrap items-center justify-between gap-4 rounded-md border border-line p-4";
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

// Cada local tarda en calcularse: la comparación llega después, sin frenar al local elegido.
async function Compare({ total, currentId }: { total: number; currentId: string | null }) {
  let places: QualityPlace[];
  try {
    places = await getQualityCompare();
  } catch (error) {
    // Si la comparación falla, el local elegido se sigue viendo (igual que en Inicio).
    unstable_rethrow(error);
    return (
      <Notice status="warn">No pudimos comparar los locales. Probá de nuevo en un rato.</Notice>
    );
  }
  // Solo las columnas que la persona puede ver.
  const indicators = QUALITY_COMPARE.flatMap((key) => qualityIndicator(key) ?? []).filter((c) =>
    places.some((p) => p.counts.some((n) => n.indicator === c.key)),
  );
  const columns: DataColumn<QualityPlace>[] = [
    {
      key: "place",
      header: "Local",
      mobile: "title",
      cell: (p) =>
        p.id === currentId ? (
          // El local que se está viendo: no es un enlace a sí mismo.
          <span className="inline-flex min-h-touch items-center font-medium text-ink desk:min-h-0">
            {p.name} <span className="sr-only">(el que estás viendo)</span>
          </span>
        ) : (
          <Link
            href={`/calidad?local=${p.id}`}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {p.name}
          </Link>
        ),
    },
    ...indicators.map((c): DataColumn<QualityPlace> => ({
      key: c.key,
      header: c.label,
      cell: (p) => {
        const count = p.counts.find((n) => n.indicator === c.key);
        return count ? (
          <ProgressBar value={count.done} total={count.total} label={`${c.label} en ${p.name}`} />
        ) : (
          "—"
        );
      },
    })),
  ];
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>Cómo está cada local</CardTitle>
        <CardDescription>
          Cada local tiene sus precios, por eso no hay un total. Tocá uno para ver qué falta.
        </CardDescription>
      </div>
      <DataTable
        caption="Calidad por local"
        columns={columns}
        rows={places}
        rowKey={(p) => p.id}
        empty={<EmptyState title="Todavía no hay locales para comparar." />}
      />
      {total > places.length ? (
        <p className="text-sm text-ink-muted">
          Se comparan los primeros {QUALITY_COMPARE_LIMIT} de {total} locales. Los demás se eligen
          en «Local», en la barra de arriba.
        </p>
      ) : null}
    </Card>
  );
}

async function Detail({ placeId, name }: { placeId: string; name: string }) {
  const counts = await getQuality(placeId);
  if (!counts) notFound();
  const hasMoney = counts.some((c) =>
    ["recipe_cost", "ingredient_price", "price_stale"].includes(c.indicator),
  );
  return (
    <>
      <p className="text-sm text-ink-muted">
        {/* Los números se calculan al abrir la pantalla, con los datos de ese momento. */}
        {name} · Datos al momento: {formatDateTime(new Date().toISOString())}
      </p>
      <Attention counts={counts} />
      <div className="grid gap-4 sm:grid-cols-2 desk:grid-cols-4">
        {QUALITY_COMPARE.map((key) => (
          <Missing
            key={key}
            label={KPI_LABELS[key] ?? qualityIndicator(key)?.missing ?? key}
            indicator={key}
            counts={counts}
            placeId={placeId}
          />
        ))}
      </div>
      <div className="grid gap-4 desk:grid-cols-2">
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
      </div>
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
      {place ? (
        <Suspense key={place.id} fallback={<Loading />}>
          <Detail placeId={place.id} name={place.name} />
        </Suspense>
      ) : (
        <PlacePrompt title="Elegí un local para ver qué falta." places={places} path="/calidad" />
      )}
      {places.length > 1 ? (
        <Suspense fallback={<Loading />}>
          <Compare total={places.length} currentId={place?.id ?? null} />
        </Suspense>
      ) : null}
    </>
  );
}
