import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { formatDifference, getPriceImpact, type ImpactRow } from "@/lib/costs";
import { formatDate, formatDateTime, uuidOrUndefined } from "@/lib/data";
import { formatMoney } from "@/lib/money";
import { requireMenu } from "@/lib/auth/session";

// El impacto de un precio (ADR-0032): ¿a qué platos les pegó? Sale de las fotos de costo.
export default function ImpactoPage({ params }: PageProps<"/costos/impacto/[id]">) {
  return (
    <AppShell
      title="¿A qué le pegó este precio?"
      description="El costo de cada receta antes y después, por local."
    >
      <Suspense fallback={<Loading />}>
        <Impact params={params} />
      </Suspense>
    </AppShell>
  );
}

async function Impact({ params }: { params: PageProps<"/costos/impacto/[id]">["params"] }) {
  await requireMenu("costs");
  const { id } = await params;
  if (!uuidOrUndefined(id)) notFound();
  const { ingredient, validFrom, calculatedAt, total, rows } = await getPriceImpact(id);
  const places = [...new Set(rows.map((r) => r.restaurantId))];
  const biggest = rows.reduce<number | null>(
    (max, r) =>
      r.differencePct !== null && (max === null || Math.abs(r.differencePct) > Math.abs(max))
        ? r.differencePct
        : max,
    null,
  );

  return (
    <>
      <Link
        href="/costos"
        className="inline-flex min-h-touch items-center self-start text-base text-primary underline-offset-4 hover:underline"
      >
        Volver a costos
      </Link>
      {rows.length === 0 ? (
        <EmptyState title="Todavía no hay impacto para mostrar.">
          Los costos se actualizan en un minuto. Tampoco aparece nada si el precio empieza más
          adelante, si no cambió ningún costo o si ninguna receta de tus locales lo usa.
        </EmptyState>
      ) : (
        <>
          <Card className="flex flex-col gap-2">
            <CardTitle>{ingredient}</CardTitle>
            <CardDescription>
              Costos sin IVA. La diferencia incluye todo lo que cambió en ese momento. Precio desde
              el {validFrom ? formatDate(validFrom) : "—"} · Calculado:{" "}
              {calculatedAt ? formatDateTime(calculatedAt) : "—"}
            </CardDescription>
          </Card>
          <div className="grid gap-4 sm:grid-cols-3">
            <Kpi label="Recetas afectadas" value={total} />
            <Kpi label="Locales" value={places.length} />
            <Kpi label="Mayor cambio" value={formatDifference(biggest)} />
          </div>
          {total > rows.length ? (
            <Notice status="info">
              Se muestran las primeras {rows.length} de {total}.
            </Notice>
          ) : null}
          {places.map((place) => {
            const items = rows.filter((r) => r.restaurantId === place);
            return (
              <Card key={place} className="flex flex-col gap-4">
                <CardTitle>{items[0]?.restaurant}</CardTitle>
                <ul
                  aria-label={`Recetas de ${items[0]?.restaurant}`}
                  className="flex flex-col divide-y divide-line"
                >
                  {items.map((r) => (
                    <Item key={r.recipeId} row={r} />
                  ))}
                </ul>
              </Card>
            );
          })}
        </>
      )}
    </>
  );
}

function Item({ row }: { row: ImpactRow }) {
  return (
    <li className="flex flex-col gap-1 py-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
      <Link
        href={`/costos/${row.recipeId}?local=${row.restaurantId}`}
        className="inline-flex min-h-touch items-center text-base font-medium text-primary underline-offset-4 hover:underline"
      >
        {row.recipe}
      </Link>
      <span className="flex flex-col text-base text-ink tabular-nums sm:items-end">
        <span>
          Antes {formatMoney(row.before)}, ahora {formatMoney(row.after)} (
          {formatDifference(row.differencePct)})
        </span>
        {row.versionChanged ? (
          <span className="text-sm text-ink-muted">También cambió la versión de la receta.</span>
        ) : null}
      </span>
    </li>
  );
}
