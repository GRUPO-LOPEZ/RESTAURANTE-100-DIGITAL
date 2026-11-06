import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { first, uuidOrUndefined } from "@/lib/data";
import { getQuality, getQualityItems, getQualityPlaces } from "@/lib/quality";
import { QUALITY_PAGE, qualityHref, qualityIndicator } from "@/lib/quality-labels";

type Props = PageProps<"/calidad/[indicador]">;

// Lo que hay que corregir en un indicador, con un botón para ir directo a cada registro.
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
  await requireMenu("quality");
  const [{ indicador }, query] = await Promise.all([params, searchParams]);
  const indicator = qualityIndicator(indicador);
  const local = uuidOrUndefined(first(query.local));
  if (!indicator || !local) notFound();

  const page = Math.max(
    0,
    Math.min(Number.parseInt(first(query.pagina) ?? "1", 10) - 1 || 0, 1000),
  );
  const [result, counts, places] = await Promise.all([
    getQualityItems(local, indicator.key, page),
    getQuality(local),
    getQualityPlaces(),
  ]);
  const place = places.find((p) => p.id === local);
  if (!result || !counts || !place) notFound();
  // Lo que falta y la persona no puede ver: se cuenta, sin nombres.
  const hidden = counts.find((c) => c.indicator === indicator.key)?.hidden ?? 0;
  const back = `/calidad?local=${local}`;
  // Una página que ya no existe (se corrigieron datos desde el enlace) vuelve a la primera.
  if (page > 0 && result.items.length === 0) redirect(`/calidad/${indicator.key}?local=${local}`);
  const pages = Math.max(1, Math.ceil(result.total / QUALITY_PAGE));
  const pageLink = (n: number) => `/calidad/${indicator.key}?local=${local}&pagina=${n + 1}`;

  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>{indicator.missing}</CardTitle>
        <CardDescription>
          {place.name}: {result.total + hidden} para revisar.
        </CardDescription>
        <Link
          href={back}
          className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline"
        >
          Volver a la calidad de datos
        </Link>
      </div>
      {result.items.length === 0 && hidden === 0 ? (
        <EmptyState title="No queda nada por corregir acá." />
      ) : result.items.length === 0 ? null : (
        <ul className="flex flex-col divide-y divide-line" aria-label={indicator.missing}>
          {result.items.map((item) => (
            <li key={item.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <span className="flex min-w-0 flex-col [overflow-wrap:anywhere]">
                <span className="text-base text-ink">{item.item}</span>
                {item.detail ? <span className="text-sm text-ink-muted">{item.detail}</span> : null}
              </span>
              <Button asChild variant="outline">
                <Link href={qualityHref(item.kind, item.id)} aria-label={`Ir a ${item.item}`}>
                  Ir
                </Link>
              </Button>
            </li>
          ))}
        </ul>
      )}
      {hidden > 0 ? (
        <Notice status="info">
          {result.items.length > 0 ? "Y " : "Hay "}
          {hidden === 1
            ? "1 receta que no podés ver: todavía no está publicada."
            : `${hidden} recetas que no podés ver: todavía no están publicadas.`}
        </Notice>
      ) : null}
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
  );
}
