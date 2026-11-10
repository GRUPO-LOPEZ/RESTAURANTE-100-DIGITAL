import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Badge } from "@/components/ui/badge";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import {
  REASON_LABELS,
  RELIABILITY,
  getCostHistory,
  getCostLines,
  getCostRow,
  getLiveCost,
  resolveCostPlace,
  type CostLine,
} from "@/lib/costs";
import { first, formatDateTime, uuidOrUndefined } from "@/lib/data";
import { formatMoney, perBaseLabel } from "@/lib/money";
import { LINE_UNITS, formatQuantity } from "@/lib/recipe-format";
import { getRecipe } from "@/lib/recipes";
import { requireMenu } from "@/lib/auth/session";

// El costo de una receta en un local (ADR-0032): ¿qué la encarece? Es una pantalla propia porque quien
// no trabaja la receta (Gerente, Controller) la ve como en la cocina, y esa vista no lleva costos.
export default function CostoRecetaPage({ params, searchParams }: PageProps<"/costos/[id]">) {
  return (
    <AppShell
      title="¿Qué encarece esta receta?"
      description="El costo de cada línea, con los precios de hoy."
    >
      <Suspense fallback={<Loading />}>
        <RecipeCost params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// "← Volver" a la lista, con sus filtros y su página (ADR-0036). ?volver= solo se acepta si es la lista de
// costos de esta misma aplicación: nunca otro sitio.
function backHref(volver: string | undefined, placeId?: string): string {
  if (volver && /^\/costos(\?|$)/.test(volver)) return volver;
  return placeId ? `/costos?local=${placeId}` : "/costos";
}

function Back({ href }: { href: string }) {
  return (
    <Link
      href={href}
      className="inline-flex min-h-touch items-center gap-1 self-start text-base text-primary underline-offset-4 hover:underline desk:min-h-control"
    >
      <ArrowLeft aria-hidden="true" className="size-4" />
      Volver a costos
    </Link>
  );
}

async function RecipeCost({
  params,
  searchParams,
}: {
  params: PageProps<"/costos/[id]">["params"];
  searchParams: PageProps<"/costos/[id]">["searchParams"];
}) {
  const session = await requireMenu("costs");
  const { id } = await params;
  if (!uuidOrUndefined(id)) notFound();
  const query = await searchParams;
  const { place } = await resolveCostPlace(session.user_id, first(query.local));
  const volver = first(query.volver);
  if (!place)
    return (
      <>
        <Back href={backHref(volver)} />
        <EmptyState title="Elegí un local para ver este costo." />
      </>
    );
  const row = await getCostRow(place.id, id);
  if (!row)
    return (
      <>
        <Back href={backHref(volver, place.id)} />
        <EmptyState title={`Esta receta no tiene costo en ${place.name}.`}>
          El local no la usa, o la acaban de asignar: los costos se actualizan en un minuto.
        </EmptyState>
      </>
    );

  const [live, lines, history, recipe] = await Promise.all([
    getLiveCost(row.versionId, place.id),
    getCostLines(row.versionId, place.id),
    getCostHistory(place.id, id),
    getRecipe(id),
  ]);
  if (!live)
    return (
      <>
        <Back href={backHref(volver, place.id)} />
        <EmptyState title={`Esta receta no tiene costo en ${place.name}.`}>
          El local ya no la usa, o no la podés ver.
        </EmptyState>
      </>
    );
  const cost = live;
  const reliability = RELIABILITY[cost.reliability];
  // La foto anterior a la vigente: contra qué se compara el costo.
  const previous = history[1]?.total ?? null;
  const { factor, label } = perBaseLabel(row.baseUnit);
  const works = recipe && (recipe.can.draft || recipe.can.review || recipe.can.publish);
  const missing = lines.filter((l) => l.missing).length;

  return (
    <>
      <Back href={backHref(volver, place.id)} />
      <Card className="flex flex-col gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle>{row.name}</CardTitle>
          <Badge status={reliability.status}>{reliability.label}</Badge>
        </div>
        <CardDescription>
          {row.code} · {place.name} · Última actualización: {formatDateTime(row.updatedAt)}
        </CardDescription>
        {works ? (
          <Link
            href={`/recetas/${id}`}
            className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
          >
            Ver la receta
          </Link>
        ) : null}
      </Card>
      {missing > 0 ? (
        <Notice status="warn">
          {missing === 1
            ? "A una línea le falta un dato: el total queda vacío hasta resolverlo."
            : `A ${missing} líneas les falta un dato: el total queda vacío hasta resolverlo.`}
        </Notice>
      ) : null}
      <div className="grid gap-4 sm:grid-cols-2 desk:grid-cols-4">
        <Kpi
          label="Costo sin IVA"
          value={cost.total === null ? "Sin costo" : formatMoney(cost.total)}
          detail={previous === null ? undefined : `Antes: ${formatMoney(previous)}`}
          status={reliability.status}
          statusLabel={reliability.label}
        />
        <Kpi label="Con IVA" value={cost.gross === null ? "Sin costo" : formatMoney(cost.gross)} />
        <Kpi
          label="Por porción"
          value={cost.perPortion === null ? "Sin dato" : formatMoney(cost.perPortion)}
        />
        <Kpi
          label={`Costo ${label}`}
          value={cost.perBaseUnit === null ? "Sin dato" : formatMoney(cost.perBaseUnit * factor)}
        />
      </div>
      <Card className="flex flex-col gap-4">
        <CardTitle>Línea por línea</CardTitle>
        {lines.length === 0 ? (
          <EmptyState title="Esta versión no tiene líneas." />
        ) : (
          <ul aria-label="Costo de cada línea" className="flex flex-col divide-y divide-line">
            {lines.map((l) => (
              <Line key={l.order} line={l} />
            ))}
          </ul>
        )}
      </Card>
      <Card className="flex flex-col gap-4">
        <CardTitle>Cómo fue cambiando</CardTitle>
        {history.length === 0 ? (
          <EmptyState title="Todavía no hay historia." />
        ) : (
          <ul aria-label="Historia del costo" className="flex flex-col divide-y divide-line">
            {history.map((s) => (
              <li
                key={s.id}
                className="flex flex-col gap-1 py-3 sm:flex-row sm:items-center sm:justify-between"
              >
                <span className="text-base text-ink tabular-nums">
                  {formatMoney(s.total)} · {REASON_LABELS[s.reason]}
                </span>
                <span className="text-sm text-ink-muted tabular-nums">{formatDateTime(s.at)}</span>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}

function Line({ line }: { line: CostLine }) {
  return (
    <li className="flex flex-col gap-1 py-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
      <div className="flex flex-col">
        <span className="text-base font-medium text-ink">{line.item}</span>
        <span className="text-sm text-ink-muted tabular-nums">
          {formatQuantity(line.quantity)}{" "}
          {LINE_UNITS.find((u) => u.code === line.unit)?.label ?? line.unit}
        </span>
      </div>
      {line.missing ? (
        <span className="text-sm font-medium text-bad-ink">{line.missing}</span>
      ) : (
        <div className="flex flex-col sm:items-end">
          <span className="text-base text-ink tabular-nums">{formatMoney(line.cost)}</span>
          <span className="text-sm text-ink-muted tabular-nums">
            {line.share === null
              ? "Con IVA "
              : `${line.share.toLocaleString("es-AR")} % · con IVA `}
            {formatMoney(line.gross)}
          </span>
        </div>
      )}
    </li>
  );
}
