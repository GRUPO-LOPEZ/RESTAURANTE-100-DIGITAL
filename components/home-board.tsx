import Link from "next/link";
import { unstable_rethrow } from "next/navigation";
import { Suspense } from "react";

import { Loading } from "@/components/app-shell";
import { FiltersPanel } from "@/components/filters-panel";
import { ReliabilityChart } from "@/components/reliability-chart";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardTitle } from "@/components/ui/card";
import { Field, Select } from "@/components/ui/field";
import { EmptyState, Kpi } from "@/components/ui/kpi";
import { Notice } from "@/components/ui/notice";
import { RELIABILITY, formatMoneyDifference, type Reliability } from "@/lib/cost-labels";
import { getRecalcStatus } from "@/lib/costs";
import { formatDate, formatDateTime, getInbox } from "@/lib/data";
import { getHomeBoard, getRecentImports, type HomeBoard, type HomeRow } from "@/lib/home";
import { formatMoney } from "@/lib/money";
import { getQuality, type QualityCount, type QualityPlaceName } from "@/lib/quality";
import { qualityHref, qualityTop } from "@/lib/quality-labels";

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

// Una tarjeta con su estado: lo que falta se toca y abre la lista para corregirlo.
function Card6({
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
  const kpi = (
    <Kpi
      className="h-full"
      label={label}
      value={missing}
      detail={`de ${count.total}`}
      status={count.total === 0 ? "neutral" : missing === 0 ? "ok" : "warn"}
      statusLabel={
        count.total === 0
          ? "Sin datos"
          : missing === 0
            ? "Completo"
            : missing === 1
              ? "Falta 1"
              : `Faltan ${missing}`
      }
    />
  );
  if (missing === 0) return kpi;
  return (
    <Link
      href={`/calidad/${indicator}?local=${placeId}`}
      className="rounded-lg hover:outline hover:outline-1 hover:outline-primary"
    >
      {kpi}
    </Link>
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
    <Section title="Actividad" text="Las revisiones y las importaciones son de todos tus locales.">
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
            className="inline-flex min-h-touch w-fit items-center text-base text-primary underline-offset-4 hover:underline"
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
                  className="flex min-h-touch items-center justify-between gap-4 underline-offset-4 hover:underline"
                >
                  <span className="text-base text-primary">{label}</span>
                  <span className="shrink-0 text-base text-ink tabular-nums">{count}</span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
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
        Calculado el {formatDateTime(new Date().toISOString())}
      </p>
      <div>
        <Button asChild variant="outline">
          <Link href={`/calidad?local=${placeId}`}>Ver qué falta corregir</Link>
        </Button>
      </div>
      {empty ? <EmptyState title="Este local todavía no tiene recetas." /> : null}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {recipes ? (
          <Kpi
            label="Recetas"
            value={recipes.total}
            detail={[
              board.preparations === null ? null : `${board.preparations} son preparaciones`,
              materials ? `${materials.total} materias primas` : null,
            ]
              .filter(Boolean)
              .join(" · ")}
          />
        ) : null}
        <Card6 label="Sin aprobar" indicator="recipe_approved" counts={counts} placeId={placeId} />
        <Card6
          label="Pendientes de revisión"
          indicator="recipe_review"
          counts={counts}
          placeId={placeId}
        />
        <Card6
          label="Costo por corregir"
          indicator="recipe_cost"
          counts={counts}
          placeId={placeId}
        />
        <Card6
          label="Materias primas sin precio"
          indicator="ingredient_price"
          counts={counts}
          placeId={placeId}
        />
        <Card6
          label="Precios desactualizados"
          indicator="price_stale"
          counts={counts}
          placeId={placeId}
        />
      </div>
      {has("reliability") ? (
        <Suspense fallback={null}>
          <Recalc />
        </Suspense>
      ) : null}
      {has("reliability") && !empty ? (
        <Section title="¿Qué tan confiable es el costo?">
          <ReliabilityChart data={chart} />
        </Section>
      ) : null}
      <div className="grid gap-4 lg:grid-cols-2">
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
              value={(r) => `${(r.amount ?? 0).toLocaleString("es-AR")} %`}
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
              value={(r) => String(r.amount ?? 0)}
              href={itemHref}
            />
          </Section>
        ) : null}
      </div>
      <Suspense fallback={<Loading />}>
        <Activity approvals={approvals} counts={counts} placeId={placeId} />
      </Suspense>
    </>
  );
}

// El tablero del recetario (sección 18): lo ve quien entra a la calidad de datos.
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
      </h2>
      {places.length > 1 ? (
        <FiltersPanel active={place ? [place.name] : []}>
          <form
            method="get"
            role="search"
            aria-label="Elegir local"
            className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:items-end"
          >
            <Field id="inicio-local" label="Local">
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
      ) : (
        <p className="text-sm text-ink-muted">{place?.name}</p>
      )}
      {place ? (
        <Suspense key={place.id} fallback={<Loading />}>
          <Board placeId={place.id} approvals={approvals} />
        </Suspense>
      ) : (
        <EmptyState title="Elegí un local para ver cómo está su recetario.">
          <Link href="/calidad" className="text-primary underline-offset-4 hover:underline">
            Comparar los locales
          </Link>
        </EmptyState>
      )}
    </>
  );
}
