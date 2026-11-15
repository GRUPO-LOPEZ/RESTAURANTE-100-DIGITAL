import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PlacePrompt } from "@/components/place-prompt";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { ShortList } from "@/components/ui/short-list";
import { EmptyState } from "@/components/ui/states";
import { Tile } from "@/components/ui/tile";
import {
  REASON_LABELS,
  RELIABILITY,
  costTip,
  getCostHistory,
  getCostLines,
  getCostRow,
  getLiveCost,
  missingSummary,
  resolveCostPlace,
  type CostLine,
  type CostSnapshot,
} from "@/lib/costs";
import { first, formatDate, formatDateTime, uuidOrUndefined } from "@/lib/data";
import { formatMoney, perBaseLabel } from "@/lib/money";
import { LINE_UNITS, RECIPE_TYPE_LABELS, formatQuantity } from "@/lib/recipe-format";
import { getRecipe } from "@/lib/recipes";
import { getMenus, requireMenu } from "@/lib/auth/session";

// El costo de una receta en un local (ADR-0032; en una pantalla sin scroll, ADR-0048): ¿qué la encarece? Es una pantalla
// propia porque quien no trabaja la receta (Gerente, Controller) la ve como en la cocina, y esa vista no lleva costos.
// En la computadora entra entera: encabezado, 4 indicadores, la línea por línea (con scroll propio) y, a la derecha,
// cómo fue cambiando y qué conviene revisar para bajar el costo.
export default function CostoRecetaPage({ params, searchParams }: PageProps<"/costos/[id]">) {
  return (
    <AppShell
      title="¿Qué encarece esta receta?"
      fill
      heading={
        <Suspense fallback="¿Qué encarece esta receta?">
          <Heading params={params} searchParams={searchParams} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} searchParams={searchParams} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <Actions params={params} searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <RecipeCost params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

type Props = {
  params: PageProps<"/costos/[id]">["params"];
  searchParams: PageProps<"/costos/[id]">["searchParams"];
};

// "← Costos" a la lista, con sus filtros y su página (ADR-0036). ?volver= solo se acepta si es la lista de costos de
// esta misma aplicación: nunca otro sitio.
function backHref(volver: string | undefined): string {
  if (volver && /^\/costos(\?|$)/.test(volver)) return volver;
  return "/costos";
}

async function Back({ searchParams }: { searchParams: Props["searchParams"] }) {
  const query = await searchParams;
  return (
    <BackLink href={backHref(first(query.volver))} label="Volver a costos">
      Costos
    </BackLink>
  );
}

// Una sola lectura por pedido: la usan el encabezado, la acción y el cuerpo.
const loadCost = cache(async (id: string, local: string | undefined) => {
  if (!uuidOrUndefined(id)) notFound();
  const session = await requireMenu("costs");
  const resolved = await resolveCostPlace(session.user_id, local);
  const row = resolved.place ? await getCostRow(resolved.place.id, id) : null;
  return { ...resolved, row };
});

async function load({ params, searchParams }: Props) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  return { id, ...(await loadCost(id, first(query.local))) };
}

async function Heading(props: Props) {
  const { row } = await load(props);
  return <>{row?.name ?? "¿Qué encarece esta receta?"}</>;
}

async function Meta(props: Props) {
  const { row } = await load(props);
  if (!row) return null;
  const reliability = RELIABILITY[row.reliability];
  const type = RECIPE_TYPE_LABELS[row.type as keyof typeof RECIPE_TYPE_LABELS] ?? row.type;
  return (
    <>
      <p className="text-sm text-ink-muted tabular-nums">
        {row.code} · {type} · actualizado el {formatDateTime(row.updatedAt)}
      </p>
      <Badge status={reliability.status}>{reliability.label}</Badge>
    </>
  );
}

// «Ver la receta», solo para quien la trabaja (como antes).
async function Actions(props: Props) {
  const { id, row } = await load(props);
  if (!row) return null;
  const recipe = await getRecipe(id);
  const works = recipe && (recipe.can.draft || recipe.can.review || recipe.can.publish);
  if (!works) return null;
  return (
    <Button asChild variant="outline">
      <Link href={`/recetas/${id}`}>Ver la receta</Link>
    </Button>
  );
}

// La historia: la tarjeta muestra las últimas y el panel, hasta 50.
const HISTORY_SHOWN = 4;
const HISTORY_PANEL = 50;

async function RecipeCost(props: Props) {
  const { id, places, place, blockedActive, row } = await load(props);
  if (places.length === 0) return <EmptyState title="No tenés locales donde ver costos." />;
  if (!place) {
    return (
      <PlacePrompt title="Costos se ve de a un local." places={places} activeName={blockedActive} />
    );
  }
  if (!row)
    return (
      <EmptyState title={`Esta receta no tiene costo en ${place.name}.`}>
        El local no la usa, o la acaban de asignar: los costos se actualizan en un minuto.
      </EmptyState>
    );

  const [live, lines, history, menus] = await Promise.all([
    getLiveCost(row.versionId, place.id),
    getCostLines(row.versionId, place.id),
    getCostHistory(place.id, id, HISTORY_PANEL),
    getMenus(),
  ]);
  if (!live)
    return (
      <EmptyState title={`Esta receta no tiene costo en ${place.name}.`}>
        El local ya no la usa, o no la podés ver.
      </EmptyState>
    );
  const cost = live;
  // La foto anterior a la vigente: contra qué se compara el costo.
  const previous = history[1]?.total ?? null;
  const { factor, label } = perBaseLabel(row.baseUnit);
  const missing = missingSummary(lines);
  const tip = costTip(lines, cost.total);
  const isPreparation = row.portions === null;
  const noTotal = "A una línea le falta un dato.";

  return (
    <div className="flex flex-col gap-4 desk:min-h-0 desk:flex-[1_1_0px]">
      {missing ? (
        <Notice status="warn">
          <span>
            <span className="font-semibold">{missing.slice(0, missing.indexOf(":") + 1)}</span>
            {missing.slice(missing.indexOf(":") + 1)} El total queda vacío hasta resolverlo.
          </span>
        </Notice>
      ) : null}
      <div className="grid gap-3 desk:grid-cols-4">
        <Metric
          compact
          label="Costo sin IVA"
          value={cost.total === null ? null : formatMoney(cost.total)}
          missingReason={noTotal}
          comparison={previous === null ? undefined : `Antes: ${formatMoney(previous)}`}
          emptyLabel="Sin costo calculado"
          status="info"
          statusLabel=""
        />
        <Metric
          compact
          label="Con IVA"
          value={cost.gross === null ? null : formatMoney(cost.gross)}
          missingReason={noTotal}
          emptyLabel="Sin costo calculado"
          status="info"
          statusLabel=""
        />
        <Metric
          compact
          label="Por porción"
          value={cost.perPortion === null ? null : formatMoney(cost.perPortion)}
          missingReason={isPreparation ? "Es una preparación: no tiene porciones." : noTotal}
          comparison={
            row.portions === null
              ? undefined
              : `${row.portions} ${row.portions === 1 ? "porción" : "porciones"}`
          }
          emptyLabel="Sin costo calculado"
          status="info"
          statusLabel=""
        />
        <Metric
          compact
          label={`Costo ${label}`}
          value={cost.perBaseUnit === null ? null : formatMoney(cost.perBaseUnit * factor)}
          missingReason={cost.total === null ? noTotal : "Falta el rendimiento de la receta."}
          emptyLabel="Sin costo calculado"
          status="info"
          statusLabel=""
        />
      </div>
      <div className="flex flex-col gap-4 desk:grid desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[minmax(0,1fr)_360px] desk:grid-rows-[minmax(0,1fr)]">
        <Lines lines={lines} />
        <div className="flex min-w-0 flex-col gap-4 desk:min-h-0">
          <Tile title="Cómo fue cambiando">
            <ShortList
              label="Historia del costo"
              items={history}
              limit={HISTORY_SHOWN}
              itemKey={(s) => s.id}
              renderItem={(s) => <Snapshot snapshot={s} />}
              empty={
                <p className="flex flex-wrap items-center gap-2 text-sm text-ink">
                  <Badge status="none">Sin datos</Badge>
                  Todavía no hay historia.
                </p>
              }
              more={
                <ActionModal
                  label={
                    history.length >= HISTORY_PANEL
                      ? `Ver las últimas ${history.length}`
                      : `Ver toda la historia (${history.length})`
                  }
                  variant="link"
                  icon="none"
                  size="sm"
                  title="Cómo fue cambiando"
                  description={`El costo de ${row.name} en ${place.name}, de la foto más nueva a la más vieja.`}
                >
                  <ul
                    aria-label="Toda la historia del costo"
                    className="flex flex-col divide-y divide-line"
                  >
                    {history.map((s) => (
                      <li key={s.id}>
                        <Snapshot snapshot={s} />
                      </li>
                    ))}
                  </ul>
                </ActionModal>
              }
            />
          </Tile>
          <Tile title="Para bajar el costo">
            {tip ? (
              <p className="text-sm text-ink">{tip}</p>
            ) : (
              <p className="flex flex-wrap items-center gap-2 text-sm text-ink">
                <Badge status="none">Sin datos</Badge>
                No hay líneas con costo para comparar.
              </p>
            )}
            {menus.scenarios ? (
              <Link
                href={`/costos/escenarios?local=${place.id}`}
                className="inline-flex min-h-touch items-center self-start text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
              >
                Probarlo en Escenarios
              </Link>
            ) : null}
          </Tile>
        </div>
      </div>
    </div>
  );
}

function Snapshot({ snapshot }: { snapshot: CostSnapshot }) {
  return (
    <span className="flex min-h-touch items-center justify-between gap-3 text-sm tabular-nums desk:min-h-8">
      <span className="min-w-0 text-ink">
        <span className="font-medium">
          {snapshot.total === null ? "Sin costo" : formatMoney(snapshot.total)}
        </span>{" "}
        · {REASON_LABELS[snapshot.reason]}
      </span>
      <span className="shrink-0 text-ink-muted">{formatDate(snapshot.at)}</span>
    </span>
  );
}

function unitLabel(line: CostLine): string {
  return LINE_UNITS.find((u) => u.code === line.unit)?.label ?? line.unit;
}

function Share({ line }: { line: CostLine }) {
  if (line.share === null)
    return (
      <span className="text-sm text-ink-muted">
        —<span className="sr-only"> (sin porcentaje: falta el total)</span>
      </span>
    );
  const width = Math.min(Math.max(line.share, 0), 100);
  return (
    <span className="flex items-center gap-2">
      <span aria-hidden="true" className="block h-2 flex-1 rounded-sm bg-none">
        <span className="block h-2 rounded-sm bg-chart-strong-1" style={{ width: `${width}%` }} />
      </span>
      <span className="w-14 shrink-0 text-right text-sm tabular-nums">
        {line.share.toLocaleString("es-AR", { maximumFractionDigits: 1 })} %
      </span>
    </span>
  );
}

// Línea por línea: de la que más pesa a la que menos; las que no tienen dato, al final, con su motivo.
function Lines({ lines }: { lines: CostLine[] }) {
  return (
    <section
      aria-labelledby="lineas-titulo"
      className="flex min-w-0 flex-col gap-2 rounded-md border border-line bg-surface p-4 desk:min-h-0"
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="lineas-titulo" className="text-base font-semibold text-ink">
          Línea por línea
        </h2>
        <p className="text-xs text-ink-muted">De la que más pesa a la que menos</p>
      </div>
      {lines.length === 0 ? (
        <EmptyState title="Esta versión no tiene líneas." />
      ) : (
        <>
          {/* Celular: de consulta, una tarjeta por línea. */}
          <ul
            aria-label="Costo de cada línea"
            className="flex flex-col divide-y divide-line desk:hidden"
          >
            {lines.map((l) => (
              <li key={l.order} className="flex flex-col gap-1 py-3">
                <span className="flex flex-wrap items-baseline justify-between gap-2">
                  <span className="text-base font-medium text-ink">
                    {l.item}
                    {l.preparation ? (
                      <span className="ml-1 text-xs text-ink-muted">(preparación)</span>
                    ) : null}
                  </span>
                  <span className="text-sm text-ink-muted tabular-nums">
                    {formatQuantity(l.quantity)} {unitLabel(l)}
                  </span>
                </span>
                {l.missing ? (
                  <span className="text-sm font-medium text-bad-ink">Sin dato: {l.missing}</span>
                ) : (
                  <>
                    <span className="text-base text-ink tabular-nums">
                      {formatMoney(l.cost)} · con IVA {formatMoney(l.gross)}
                    </span>
                    <Share line={l} />
                  </>
                )}
              </li>
            ))}
          </ul>
          {/* Computadora: tabla con el encabezado fijo y scroll propio. */}
          <div
            role="region"
            aria-label="Costo de cada línea (tabla)"
            tabIndex={0}
            className="relative hidden overflow-auto rounded-sm border border-line focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary desk:block desk:h-0 desk:min-h-0 desk:flex-[1_1_0px]"
          >
            <table className="w-full border-collapse text-left">
              <caption className="sr-only">Costo de cada línea</caption>
              <thead className="sticky top-0 z-10 bg-app shadow-[inset_0_-1px_0_var(--color-line)]">
                <tr>
                  <th scope="col" className="px-3 py-2 text-sm font-medium text-ink-muted">
                    Ingrediente
                  </th>
                  <th
                    scope="col"
                    className="px-3 py-2 text-right text-sm font-medium text-ink-muted"
                  >
                    Cantidad
                  </th>
                  <th
                    scope="col"
                    className="px-3 py-2 text-right text-sm font-medium text-ink-muted"
                  >
                    Costo
                  </th>
                  <th scope="col" className="w-56 px-3 py-2 text-sm font-medium text-ink-muted">
                    Peso en el costo
                  </th>
                  <th
                    scope="col"
                    className="px-3 py-2 text-right text-sm font-medium text-ink-muted"
                  >
                    Con IVA
                  </th>
                </tr>
              </thead>
              <tbody>
                {lines.map((l) => (
                  <tr key={l.order} className="border-b border-line last:border-0">
                    <td className="px-3 py-1.5 text-sm font-medium whitespace-nowrap text-ink">
                      {l.item}
                      {l.preparation ? (
                        <span className="ml-1 text-xs font-normal text-ink-muted">
                          (preparación)
                        </span>
                      ) : null}
                    </td>
                    <td className="px-3 py-1.5 text-right text-sm text-ink-muted tabular-nums">
                      {formatQuantity(l.quantity)} {unitLabel(l)}
                    </td>
                    {l.missing ? (
                      <td colSpan={3} className="px-3 py-1.5 text-sm font-medium text-bad-ink">
                        — Sin dato: {l.missing}
                      </td>
                    ) : (
                      <>
                        <td className="px-3 py-1.5 text-right text-sm text-ink tabular-nums">
                          {formatMoney(l.cost)}
                        </td>
                        <td className="px-3 py-1.5">
                          <Share line={l} />
                        </td>
                        <td className="px-3 py-1.5 text-right text-sm text-ink-muted tabular-nums">
                          {formatMoney(l.gross)}
                        </td>
                      </>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </section>
  );
}
