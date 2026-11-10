import Link from "next/link";
import { unstable_rethrow } from "next/navigation";
import { Suspense } from "react";
import { TriangleAlert } from "lucide-react";

import { Loading } from "@/components/app-shell";
import { ReliabilityChart } from "@/components/reliability-chart";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Metric } from "@/components/ui/metric";
import { ProgressBar } from "@/components/ui/progress-bar";
import { EmptyState } from "@/components/ui/states";
import { Notice } from "@/components/ui/notice";
import { RELIABILITY, formatMoneyDifference, type Reliability } from "@/lib/cost-labels";
import { getRecalcStatus } from "@/lib/costs";
import { formatDate, formatDateTime, getInbox } from "@/lib/data";
import { getHomeBoard, getRecentImports, type HomeBoard, type HomeRow } from "@/lib/home";
import { formatMoney } from "@/lib/money";
import {
  getQuality,
  getQualityCompare,
  type QualityCount,
  type QualityPlaceName,
} from "@/lib/quality";
import { qualityHref, qualityTop } from "@/lib/quality-labels";
import { cn } from "@/lib/utils";

const IMPORT_STATUS: Record<string, string> = {
  uploaded: "Subida",
  staged: "Leída",
  validated: "Validada",
  ingredients_confirmed: "Materias primas confirmadas",
  confirmed: "Confirmada",
  cancelled: "Cancelada",
};

// Lo que sale del Inicio tiene que ver con el recetario: una baja de personal no va en una pantalla de cocina.
const RECIPE_WORKFLOWS = /^(recipes|prices|yields|catalog)\./;

function reliabilityLabel(state: string | null) {
  if (state === null) return null;
  return state === "none" ? "Sin costo" : (RELIABILITY[state as Reliability]?.label ?? null);
}

function RowList({
  label,
  rows,
  empty,
  value,
  note,
  href,
}: {
  label: string;
  rows: HomeRow[];
  empty: string;
  value: (row: HomeRow) => string;
  note?: (row: HomeRow) => string | null;
  href: (row: HomeRow) => string;
}) {
  if (rows.length === 0) return <p className="text-sm text-ink-muted">{empty}</p>;
  return (
    <ul className="flex flex-col divide-y divide-line" aria-label={label}>
      {rows.map((row) => (
        <li key={row.id ?? row.item}>
          <Link
            href={href(row)}
            className="flex min-h-touch items-center justify-between gap-4 py-2 underline-offset-4 hover:underline"
          >
            <span className="flex min-w-0 flex-col [overflow-wrap:anywhere]">
              <span className="text-base text-primary">{row.item}</span>
              {note?.(row) ? <span className="text-sm text-ink-muted">{note(row)}</span> : null}
            </span>
            <span className="shrink-0 text-base text-ink tabular-nums">{value(row)}</span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

function Section({
  title,
  text,
  children,
}: {
  title: string;
  text?: string;
  children: React.ReactNode;
}) {
  return (
    <Card className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <CardTitle>{title}</CardTitle>
        {text ? <CardDescription>{text}</CardDescription> : null}
      </div>
      {children}
    </Card>
  );
}

// Una tarjeta de lo que falta (métricas confiables, ADR-0036): sin denominador dice «Sin datos», nunca «Completo».
// Si falta algo, enlaza a la lista para corregirlo.
function Missing({
  label,
  indicator,
  counts,
  placeId,
}: {
  label: string;
  indicator: string;
  counts: QualityCount[];
  placeId: string;
}) {
  const count = counts.find((c) => c.indicator === indicator);
  if (!count) return null;
  const missing = count.total - count.done;
  return (
    <Metric
      className="h-full"
      label={label}
      value={missing}
      total={count.total}
      emptyLabel="Todavía no hay nada que medir en este local."
      comparison={`de ${count.total}`}
      status={missing === 0 ? "ok" : "warn"}
      statusLabel={missing === 0 ? "Completo" : missing === 1 ? "Falta 1" : `Faltan ${missing}`}
      href={missing > 0 ? `/calidad/${indicator}?local=${placeId}` : undefined}
      hrefLabel="Ver cuáles"
    />
  );
}

// Requiere atención: lo pendiente, en una línea, con el botón para ir a resolverlo.
function Attention({ counts, placeId }: { counts: QualityCount[]; placeId: string }) {
  const parts = [
    // Singular y plural: "1 precio desactualizado", "3 precios desactualizados".
    ["recipe_cost", "receta con costo por corregir", "recetas con costo por corregir"],
    ["ingredient_price", "materia prima sin precio", "materias primas sin precio"],
    ["price_stale", "precio desactualizado", "precios desactualizados"],
    ["recipe_review", "receta pendiente de revisión", "recetas pendientes de revisión"],
  ]
    .map(([key, one, many]) => {
      const c = counts.find((x) => x.indicator === key);
      const missing = c ? c.total - c.done : 0;
      return missing > 0 ? `${missing} ${missing === 1 ? one : many}` : null;
    })
    .filter((x): x is string => Boolean(x));
  if (parts.length === 0) return null;
  return (
    <div
      role="region"
      aria-label="Requiere atención"
      className="flex flex-col gap-3 rounded-md bg-warn p-4 text-warn-ink desk:flex-row desk:items-center desk:justify-between"
    >
      <p className="flex items-start gap-2 text-base">
        <TriangleAlert aria-hidden="true" className="mt-0.5 size-5 shrink-0" />
        <span>
          <span className="font-medium">Requiere atención:</span> {parts.join(" · ")}.
        </span>
      </p>
      <Button asChild variant="outline" className="shrink-0">
        <Link href={`/calidad?local=${placeId}`}>Ver qué falta corregir</Link>
      </Button>
    </div>
  );
}

// Comparación entre locales: qué tan confiable es el costo en cada uno (solo con más de un local).
async function Compare({ placeId }: { placeId: string }) {
  let places: Awaited<ReturnType<typeof getQualityCompare>> = [];
  try {
    places = await getQualityCompare();
  } catch (error) {
    unstable_rethrow(error);
    return <Notice status="warn">No pudimos comparar los locales.</Notice>;
  }
  if (places.length < 2) return null;
  return (
    <Section title="Cómo está cada local" text="Recetas con el costo completo y confiable.">
      <ul className="flex flex-col gap-3" aria-label="Costo confiable por local">
        {places.map((p) => {
          const c = p.counts.find((x) => x.indicator === "recipe_cost");
          return (
            <li
              key={p.id}
              className="flex flex-col gap-1 desk:flex-row desk:items-center desk:justify-between"
            >
              <Link
                href={`/?local=${p.id}`}
                aria-current={p.id === placeId ? "true" : undefined}
                className={cn(
                  "min-w-0 text-base [overflow-wrap:anywhere] underline-offset-4 hover:underline",
                  p.id === placeId ? "font-medium text-ink" : "text-primary",
                )}
              >
                {p.name}
              </Link>
              <ProgressBar
                value={c?.done ?? 0}
                total={c?.total ?? 0}
                label={`Costo confiable en ${p.name}`}
              />
            </li>
          );
        })}
      </ul>
      <Link
        href="/calidad"
        className="inline-flex min-h-touch w-fit items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
      >
        Ver la comparación completa
      </Link>
    </Section>
  );
}

// Lo secundario no puede tirar el Inicio: es la pantalla por la que entra todo el mundo.
async function Recalc() {
  let status: Awaited<ReturnType<typeof getRecalcStatus>> | null = null;
  try {
    status = await getRecalcStatus();
  } catch (error) {
    unstable_rethrow(error);
  }
  if (!status || (status.pending === 0 && status.failed === 0)) return null;
  const { pending, failed } = status;
  return (
    <Notice status={failed > 0 ? "warn" : "info"}>
      {pending > 0
        ? `${pending} ${pending === 1 ? "pedido de recálculo espera" : "pedidos de recálculo esperan"}. `
        : ""}
      {failed > 0
        ? `${failed} ${failed === 1 ? "pedido no se pudo calcular" : "pedidos no se pudieron calcular"}.`
        : ""}
    </Notice>
  );
}

async function Activity({
  approvals,
  counts,
  placeId,
}: {
  approvals: boolean;
  counts: QualityCount[];
  placeId: string;
}) {
  let requests: Awaited<ReturnType<typeof getInbox>> = [];
  let imports: Awaited<ReturnType<typeof getRecentImports>> = [];
  let loaded = false;
  try {
    [requests, imports] = await Promise.all([
      approvals ? getInbox(true, 20) : [],
      getRecentImports(),
    ]);
    loaded = true;
  } catch (error) {
    unstable_rethrow(error);
  }
  if (!loaded) return <Notice status="warn">No pudimos cargar la actividad reciente.</Notice>;
  const recipeRequests = requests.filter((r) => RECIPE_WORKFLOWS.test(r.workflow_code)).slice(0, 3);
  const errors = qualityTop(counts, 3);
  return (
    <Section
      title="Tareas pendientes"
      text="Primero lo que más falta corregir en este local; las revisiones y las importaciones son de todos tus locales."
    >
      <div className="flex flex-col gap-2">
        <h3 className="text-base font-medium text-ink">Lo que más falta corregir</h3>
        {errors.length === 0 ? (
          <p className="text-sm text-ink-muted">No falta nada por corregir.</p>
        ) : (
          <ul className="flex flex-col divide-y divide-line" aria-label="Lo que más falta corregir">
            {errors.map(({ key, label, count }) => (
              <li key={key}>
                <Link
                  href={`/calidad/${key}?local=${placeId}`}
                  className="flex min-h-touch items-center justify-between gap-4 underline-offset-4 hover:underline desk:min-h-control"
                >
                  <span className="text-base text-primary">{label}</span>
                  <span className="shrink-0 text-base text-ink tabular-nums">{count}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
      {approvals ? (
        <div className="flex flex-col gap-2">
          <h3 className="text-base font-medium text-ink">Revisiones pendientes</h3>
          {recipeRequests.length === 0 ? (
            <p className="text-sm text-ink-muted">
              No hay recetas ni precios esperando una decisión.
            </p>
          ) : (
            <ul className="flex flex-col gap-1" aria-label="Revisiones pendientes">
              {recipeRequests.map((r) => (
                <li key={r.id} className="text-sm [overflow-wrap:anywhere] text-ink">
                  {r.summary ?? r.workflow_name}
                  <span className="text-ink-muted">
                    {r.place_name ? ` · ${r.place_name}` : ""} · {formatDateTime(r.requested_at)}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <Link
            href="/aprobaciones"
            className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline desk:min-h-control"
          >
            Ver las aprobaciones
          </Link>
        </div>
      ) : null}
      {imports.length > 0 ? (
        <div className="flex flex-col gap-2">
          <h3 className="text-base font-medium text-ink">Últimas importaciones</h3>
          <ul className="flex flex-col gap-1" aria-label="Últimas importaciones">
            {imports.map((j) => (
              <li key={j.id} className="text-sm [overflow-wrap:anywhere] text-ink">
                {j.file}
                <span className="text-ink-muted">
                  {" "}
                  · {IMPORT_STATUS[j.status] ?? "En proceso"} · {formatDate(j.createdAt)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </Section>
  );
}

async function Board({ placeId, approvals }: { placeId: string; approvals: boolean }) {
  let counts: QualityCount[] | null = null;
  let board: HomeBoard | null = null;
  try {
    [counts, board] = await Promise.all([getQuality(placeId), getHomeBoard(placeId)]);
  } catch (error) {
    unstable_rethrow(error);
  }
  if (!counts || !board) {
    return <Notice status="warn">No pudimos cargar el tablero de este local.</Notice>;
  }
  const recipes = counts.find((c) => c.indicator === "recipe_approved");
  const materials = counts.find((c) => c.indicator === "ingredient_price");
  const chart = board.reliability.map((r) => ({
    label: reliabilityLabel(r.item) ?? r.item,
    count: r.amount ?? 0,
  }));
  const recipeHref = (row: HomeRow) => `/costos/${row.id}?local=${placeId}`;
  const itemHref = (row: HomeRow) => qualityHref(row.kind, row.id ?? "");
  const has = (section: string) => board.sections.has(section);
  const empty = recipes?.total === 0;

  return (
    <>
      <p className="text-sm text-ink-muted">
        {/* Los números se calculan al abrir la pantalla, con los datos de ese momento. */}
        Datos al momento: {formatDateTime(new Date().toISOString())}
        {recipes ? ` · ${recipes.total} ${recipes.total === 1 ? "receta" : "recetas"}` : ""}
        {board.preparations === null ? "" : ` · ${board.preparations} preparaciones`}
        {materials ? ` · ${materials.total} materias primas` : ""}
      </p>
      <Attention counts={counts} placeId={placeId} />
      {empty ? <EmptyState title="Este local todavía no tiene recetas." /> : null}
      <div className="grid gap-4 sm:grid-cols-2 desk:grid-cols-4">
        <Missing
          label="Sin aprobar"
          indicator="recipe_approved"
          counts={counts}
          placeId={placeId}
        />
        <Missing
          label="Pendientes de revisión"
          indicator="recipe_review"
          counts={counts}
          placeId={placeId}
        />
        <Missing
          label="Costo por corregir"
          indicator="recipe_cost"
          counts={counts}
          placeId={placeId}
        />
        <Missing
          label="Materias primas sin precio"
          indicator="ingredient_price"
          counts={counts}
          placeId={placeId}
        />
      </div>
      {has("reliability") ? (
        <Suspense fallback={null}>
          <Recalc />
        </Suspense>
      ) : null}
      <div className="grid gap-4 desk:grid-cols-2">
        <Suspense fallback={<Loading />}>
          <Compare placeId={placeId} />
        </Suspense>
        <Suspense fallback={<Loading />}>
          <Activity approvals={approvals} counts={counts} placeId={placeId} />
        </Suspense>
      </div>
      {has("reliability") && !empty ? (
        <Section title="¿Qué tan confiable es el costo?">
          <ReliabilityChart data={chart} />
        </Section>
      ) : null}
      <div className="grid gap-4 desk:grid-cols-2">
        {has("top_portion") ? (
          <Section title="Mayor costo por porción">
            <RowList
              label="Mayor costo por porción"
              rows={board.topPortion}
              empty="Todavía no hay costos por porción."
              value={(r) => formatMoney(r.amount)}
              note={(r) => reliabilityLabel(r.detail)}
              href={recipeHref}
            />
          </Section>
        ) : null}
        {has("top_ingredient") ? (
          <Section
            title="Materias primas que más pesan"
            text="Sobre lo que cuestan las recetas, no sobre lo que se vende."
          >
            <RowList
              label="Materias primas que más pesan"
              rows={board.topIngredient}
              empty="Todavía no hay costos para comparar."
              value={(r) => (r.amount === null ? "—" : `${r.amount.toLocaleString("es-AR")} %`)}
              href={itemHref}
            />
          </Section>
        ) : null}
        {has("price_affected") ? (
          <Section title="Recetas afectadas por cambios de precio" text="En los últimos 30 días.">
            <RowList
              label="Recetas afectadas por cambios de precio"
              rows={board.priceAffected}
              empty="Ningún precio cambió una receta en los últimos 30 días."
              value={(r) =>
                r.detail === "gained"
                  ? "Ahora tiene costo"
                  : r.detail === "lost"
                    ? "Se quedó sin costo"
                    : formatMoneyDifference(r.amount)
              }
              href={recipeHref}
            />
          </Section>
        ) : null}
        {has("most_used") ? (
          <Section title="Lo más usado" text="En cuántas recetas vigentes aparece.">
            <RowList
              label="Lo más usado"
              rows={board.mostUsed}
              empty="Todavía no hay recetas vigentes."
              value={(r) => (r.amount === null ? "—" : String(r.amount))}
              href={itemHref}
            />
          </Section>
        ) : null}
      </div>
    </>
  );
}

// El tablero del recetario (sección 18; panel del rediseño, ADR-0036): lo ve quien entra a la calidad de datos.
// El local sale de la barra de arriba (o de ?local=): sin selector propio.
export function HomeBoardView({
  places,
  place,
  approvals,
}: {
  places: QualityPlaceName[];
  place: QualityPlaceName | null;
  approvals: boolean;
}) {
  return (
    <>
      <h2 className="text-xl font-semibold text-ink">
        ¿Qué tan completo y confiable está nuestro recetario?
        {place ? <span className="font-normal text-ink-muted"> · {place.name}</span> : null}
      </h2>
      {place ? (
        <Suspense key={place.id} fallback={<Loading />}>
          <Board placeId={place.id} approvals={approvals} />
        </Suspense>
      ) : (
        <EmptyState title="Elegí un local para ver cómo está su recetario.">
          <p>Elegilo en «Local», en la barra de arriba, o entrá directo:</p>
          <ul
            className="mt-2 flex flex-wrap justify-center gap-x-4 gap-y-1"
            aria-label="Tus locales"
          >
            {places.map((p) => (
              <li key={p.id}>
                <Link
                  href={`/?local=${p.id}`}
                  className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
                >
                  {p.name}
                </Link>
              </li>
            ))}
          </ul>
          <Link
            href="/calidad"
            className="mt-2 inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-control-sm"
          >
            Comparar los locales
          </Link>
        </EmptyState>
      )}
    </>
  );
}
