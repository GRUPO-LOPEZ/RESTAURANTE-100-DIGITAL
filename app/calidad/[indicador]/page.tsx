import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PlacePrompt } from "@/components/place-prompt";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Notice } from "@/components/ui/notice";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { requireMenu } from "@/lib/auth/session";
import { pickCostPlace } from "@/lib/costs";
import { first, getActiveRestaurantId, uuidOrUndefined } from "@/lib/data";
import { parseList, plainParams } from "@/lib/list-params";
import { getQuality, getQualityItems, getQualityPlaces, type QualityItem } from "@/lib/quality";
import { qualityHref, qualityIndicator } from "@/lib/quality-labels";

type Props = PageProps<"/calidad/[indicador]">;

// Lo que hay que corregir en un indicador (listado del rediseño, ADR-0036), con un botón para ir directo a la
// pestaña de la ficha donde se corrige cada registro.
export default function IndicadorPage({ params, searchParams }: Props) {
  return (
    <AppShell title="Qué hay que corregir">
      <Suspense fallback={<Loading />}>
        <Items params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Items({ params, searchParams }: Pick<Props, "params" | "searchParams">) {
  const session = await requireMenu("quality");
  const [{ indicador }, query] = await Promise.all([params, searchParams]);
  const indicator = qualityIndicator(indicador);
  if (!indicator) notFound();
  // El local de la dirección o, si no viene (el selector de arriba lo saca al cambiar de local), el activo.
  // Con «Todos mis locales», se pide uno (ADR-0036).
  let local = uuidOrUndefined(first(query.local));
  if (!local) {
    const [places, activeId] = await Promise.all([
      getQualityPlaces(),
      getActiveRestaurantId(session.user_id),
    ]);
    const active = pickCostPlace(places, undefined, activeId);
    if (!active) {
      if (places.length === 0) return <EmptyState title="No tenés locales para revisar." />;
      return (
        <PlacePrompt
          title="Elegí un local para ver qué falta."
          places={places}
          path={`/calidad/${indicator.key}`}
        />
      );
    }
    local = active.id;
  }

  // Página y filas por página como en todos los listados (15 de entrada; 10, 25 o 50).
  const list = parseList(query, []);
  const [result, counts, places] = await Promise.all([
    getQualityItems(local, indicator.key, list.page - 1, list.size),
    getQuality(local),
    getQualityPlaces(),
  ]);
  const place = places.find((p) => p.id === local);
  if (!result || !counts || !place) notFound();
  // Lo que falta y la persona no puede ver: se cuenta, sin nombres.
  const hidden = counts.find((c) => c.indicator === indicator.key)?.hidden ?? 0;
  const path = `/calidad/${indicator.key}`;
  // Una página que ya no existe (se corrigieron datos desde el enlace) vuelve a la primera.
  if (list.page > 1 && result.items.length === 0) redirect(`${path}?local=${local}`);

  const columns: DataColumn<QualityItem>[] = [
    {
      key: "item",
      header: indicator.missing,
      mobile: "title",
      cell: (item) => <span className="[overflow-wrap:anywhere] text-ink">{item.item}</span>,
    },
    {
      key: "detail",
      header: "Detalle",
      cell: (item) => (
        <span className="text-sm [overflow-wrap:anywhere] text-ink-muted">
          {item.detail ?? "—"}
        </span>
      ),
    },
    {
      key: "go",
      header: "Acción",
      align: "right",
      mobile: "action",
      cell: (item) => (
        <Button asChild variant="outline">
          <Link
            href={qualityHref(item.kind, item.id, indicator.key)}
            aria-label={`Ir a ${item.item}`}
          >
            Ir
          </Link>
        </Button>
      ),
    },
  ];

  return (
    <>
      <BackLink href={`/calidad?local=${local}`}>Volver a la calidad de datos</BackLink>
      <Card className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <CardTitle>{indicator.missing}</CardTitle>
          <CardDescription>
            {place.name}: {result.total + hidden} para revisar.
          </CardDescription>
        </div>
        {result.items.length === 0 && hidden === 0 ? (
          <EmptyState title="No queda nada por corregir acá." />
        ) : result.items.length === 0 ? null : (
          <DataTable
            caption={indicator.missing}
            columns={columns}
            rows={result.items}
            rowKey={(item) => `${item.kind}-${item.id}`}
          />
        )}
        {hidden > 0 ? (
          <Notice status="info">
            {result.items.length > 0 ? "Y " : "Hay "}
            {hidden === 1
              ? "1 receta que no podés ver: todavía no está publicada."
              : `${hidden} recetas que no podés ver: todavía no están publicadas.`}
          </Notice>
        ) : null}
        {result.total > 0 ? (
          <Pagination
            list={list}
            total={result.total}
            shown={result.items.length}
            path={path}
            params={plainParams(query)}
          />
        ) : null}
      </Card>
    </>
  );
}
