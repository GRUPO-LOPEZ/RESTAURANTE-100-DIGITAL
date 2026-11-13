import Link from "next/link";
import { unstable_rethrow } from "next/navigation";
import { Suspense, cache } from "react";

import { Loading } from "@/components/app-shell";
import { Ranking, type RankingList } from "@/components/home/ranking";
import { NavIconGlyph } from "@/components/nav-icon";
import { AttentionStrip, Missing, attentionParts } from "@/components/quality-board";
import { Badge } from "@/components/ui/badge";
import { Notice } from "@/components/ui/notice";
import { ProgressBar } from "@/components/ui/progress-bar";
import { EmptyState } from "@/components/ui/states";
import { RELIABILITY, formatMoneyDifference, type Reliability } from "@/lib/cost-labels";
import { getRecalcStatus } from "@/lib/costs";
import { formatDate, formatDateTime, getInbox } from "@/lib/data";
import { getHomeBoard, getRecentImports, type HomeBoard, type HomeRow } from "@/lib/home";
import { shortcutStates, type ShortcutKey, type ShortcutState } from "@/lib/home-shortcuts";
import { formatMoney } from "@/lib/money";
import type { NavIcon } from "@/lib/nav";
import { getQuality, getQualityCompare, type QualityPlaceName } from "@/lib/quality";
import { qualityHref, qualityPercent, qualityTop } from "@/lib/quality-labels";
import { cn } from "@/lib/utils";

// El Inicio en una pantalla (ADR-0045, pedido de Soy del 2026-11-13; panel del rediseño, ADR-0036). En la computadora
// entra entero en 1440 × 900: aviso, 4 KPIs, tres tarjetas compactas, un ranking y los accesos con su número. En el
// celular es para supervisar: aviso, KPIs, lo que hay para decidir y cómo está cada local.

const IMPORT_STATUS: Record<string, string> = {
  uploaded: "Subida",
  staged: "Leída",
  validated: "Validada",
  ingredients_confirmed: "Materias primas confirmadas",
  confirmed: "Confirmada",
  cancelled: "Cancelada",
};

// La bandeja se lee una vez para el aviso, las tareas y el acceso de Aprobaciones. Si llega al tope, se dice.
const INBOX_LIMIT = 50;
// Las listas tienen tope: la pantalla no crece con los datos.
const COMPARE_ROWS = 5;

// Los mismos datos que leen el encabezado y el tablero, una sola vez por pedido.
export const loadQuality = cache(getQuality);
export const loadHomeBoard = cache(getHomeBoard);

// Barras de confiabilidad: tonos fuertes de gráficos (ADR-0015), el estado siempre con su nombre al lado.
const RELIABILITY_BAR: Record<Reliability | "none", string> = {
  verified: "bg-chart-strong-2",
  estimated: "bg-chart-strong-1",
  stale: "bg-chart-strong-3",
  incomplete: "bg-chart-strong-4",
  none: "bg-ink-muted",
};
const RELIABILITY_ORDER = ["verified", "estimated", "stale", "incomplete", "none"] as const;

const SHORTCUTS: { key: ShortcutKey; href: string; label: string; icon: NavIcon }[] = [
  { key: "recipes", href: "/recetas", label: "Recetas", icon: "recipes" },
  { key: "ingredients", href: "/materias-primas", label: "Materias primas", icon: "ingredients" },
  { key: "costs", href: "/costos", label: "Costos", icon: "costs" },
  { key: "approvals", href: "/aprobaciones", label: "Aprobaciones", icon: "approvals" },
  { key: "quality", href: "/calidad", label: "Calidad", icon: "quality" },
  { key: "reports", href: "/reportes", label: "Reportes", icon: "reports" },
];

export type HomeMenus = Record<ShortcutKey, boolean>;

// Una tarjeta compacta: título de 16 px, un dato chico a la derecha y el enlace «Ver …» abajo.
function Tile({
  title,
  aside,
  footer,
  className,
  children,
}: {
  title: string;
  aside?: string;
  footer?: { href: string; label: string };
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <section
      aria-label={title}
      className={cn(
        "flex min-w-0 flex-col gap-1.5 rounded-md border border-line bg-surface p-4",
        className,
      )}
    >
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="text-base font-semibold text-ink">{title}</h2>
        {aside ? <span className="text-xs text-ink-muted">{aside}</span> : null}
      </div>
      {children}
      {footer ? (
        <Link
          href={footer.href}
          className="mt-auto inline-flex min-h-touch w-fit items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
        >
          {footer.label}
        </Link>
      ) : null}
    </section>
  );
}

// Lo secundario no puede tirar el Inicio: es la pantalla por la que entra todo el mundo.
async function safely<T>(load: () => Promise<T>): Promise<T | null> {
  try {
    return await load();
  } catch (error) {
    unstable_rethrow(error);
    return null;
  }
}

// ¿Qué tan confiable es el costo? Cinco filas (estado, barra y cantidad); cada una lleva a sus recetas.
function ReliabilityTile({ board, placeId }: { board: HomeBoard; placeId: string }) {
  const counts = new Map(board.reliability.map((r) => [r.item, r.amount ?? 0]));
  const total = [...counts.values()].reduce((sum, n) => sum + n, 0);
  const max = Math.max(1, ...counts.values());
  return (
    <Tile
      title="¿Qué tan confiable es el costo?"
      aside={total === 1 ? "1 receta" : `${total} recetas`}
      footer={{ href: `/costos?local=${placeId}`, label: "Ver los números" }}
      className="hidden desk:flex"
    >
      <ul className="flex flex-col" aria-label="Recetas en cada estado del costo">
        {RELIABILITY_ORDER.map((state) => {
          const n = counts.get(state) ?? 0;
          const label = state === "none" ? "Sin costo" : RELIABILITY[state].label;
          const href =
            state === "none"
              ? `/calidad/recipe_cost?local=${placeId}`
              : `/costos?local=${placeId}&confiabilidad=${state}`;
          return (
            <li key={state}>
              <Link
                href={href}
                className="grid min-h-touch grid-cols-[minmax(0,11rem)_1fr_2rem] items-center gap-3 text-sm text-ink underline-offset-4 hover:underline desk:min-h-7"
              >
                <span className="truncate">{label}</span>
                <span className="h-2.5 overflow-hidden rounded-sm bg-line" aria-hidden="true">
                  <span
                    className={cn("block h-full", RELIABILITY_BAR[state])}
                    style={{ width: `${Math.round((n * 100) / max)}%` }}
                  />
                </span>
                <span className="text-right tabular-nums">{n}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </Tile>
  );
}

// Cómo está cada local: el costo confiable de cada uno (solo con más de un local). Va en la computadora y en el celular.
async function CompareTile({ placeId }: { placeId: string }) {
  const places = await safely(getQualityCompare);
  if (!places) return <Notice status="warn">No pudimos comparar los locales.</Notice>;
  if (places.length < 2) return null;
  // Hasta 5 locales, siempre con el elegido: la tarjeta no crece con la cantidad de locales. El resto, en Calidad.
  const shown = places.slice(0, COMPARE_ROWS);
  const chosen = places.find((p) => p.id === placeId);
  if (chosen && !shown.includes(chosen)) shown[COMPARE_ROWS - 1] = chosen;
  return (
    <Tile
      title="Cómo está cada local"
      aside={
        places.length > shown.length
          ? `${shown.length} de ${places.length} · costo confiable`
          : "Costo confiable"
      }
      footer={{ href: "/calidad", label: "Comparar los locales" }}
    >
      <ul className="flex flex-col" aria-label="Costo confiable por local">
        {shown.map((p) => {
          const c = p.counts.find((x) => x.indicator === "recipe_cost");
          const current = p.id === placeId;
          const pct = qualityPercent(c?.done ?? 0, c?.total ?? 0);
          // Toda la fila es el enlace (44 px en el celular); la barra repite el número que el enlace ya dice.
          return (
            <li key={p.id}>
              <Link
                href={`/?local=${p.id}`}
                aria-current={current ? "true" : undefined}
                className="flex min-h-touch items-center justify-between gap-3 text-sm underline-offset-4 hover:underline desk:min-h-7"
              >
                <span
                  className={cn(
                    "min-w-0 truncate",
                    current ? "font-semibold text-ink" : "text-primary",
                  )}
                >
                  {p.name}
                  <span className="sr-only">
                    {pct === null ? ": sin datos" : `: ${pct} % con costo confiable`}
                  </span>
                </span>
                <ProgressBar
                  value={c?.done ?? 0}
                  total={c?.total ?? 0}
                  label={`Costo confiable en ${p.name}`}
                  decorative
                  className="shrink-0"
                />
              </Link>
            </li>
          );
        })}
      </ul>
    </Tile>
  );
}

// Sin número para este rol no hay chip: el acceso queda solo con su nombre.
function ShortcutChip({ state }: { state: ShortcutState }) {
  if (!state.label) return null;
  return <Badge status={state.status}>{state.label}</Badge>;
}

// Los accesos grandes (3 × 2), cada uno con su número del momento. Solo en la computadora: en el celular están en la
// barra de abajo.
function Shortcuts({
  states,
  menus,
}: {
  states: Record<ShortcutKey, ShortcutState>;
  menus: HomeMenus;
}) {
  const items = SHORTCUTS.filter((s) => menus[s.key]);
  if (items.length === 0) return null;
  return (
    <nav aria-label="Accesos" className="grid min-w-0 grid-cols-3 grid-rows-2 gap-3">
      {items.map(({ key, href, label, icon }) => (
        <Link
          key={key}
          href={href}
          className="flex min-w-0 flex-col justify-center gap-2 rounded-md border border-line bg-surface px-4 py-3 text-ink hover:border-primary"
        >
          <span className="flex items-center gap-2 text-base font-semibold">
            <span className="flex size-8 shrink-0 items-center justify-center rounded-sm bg-nav-active text-nav-active-ink">
              <NavIconGlyph icon={icon} className="size-5" />
            </span>
            {label}
          </span>
          <span className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
            <ShortcutChip state={states[key]} />
            {states[key].text ? <span className="text-ink-muted">{states[key].text}</span> : null}
          </span>
        </Link>
      ))}
    </nav>
  );
}

function rankingLists(board: HomeBoard, placeId: string): RankingList[] {
  const recipeHref = (row: HomeRow) => `/costos/${row.id}?local=${placeId}`;
  const itemHref = (row: HomeRow) => qualityHref(row.kind, row.id ?? "");
  const rows = (list: HomeRow[], value: (r: HomeRow) => string, href: (r: HomeRow) => string) =>
    list.slice(0, 5).map((r, i) => ({
      key: `${r.id ?? r.item}-${i}`,
      name: r.item,
      value: value(r),
      href: href(r),
    }));
  const all: (RankingList & { section: string })[] = [
    {
      section: "top_portion",
      key: "porcion",
      label: "Mayor costo por porción",
      empty: "Todavía no hay costos por porción.",
      rows: rows(board.topPortion, (r) => formatMoney(r.amount), recipeHref),
    },
    {
      section: "top_ingredient",
      key: "materias-primas",
      label: "Materias primas que más pesan",
      empty: "Todavía no hay costos para comparar.",
      rows: rows(
        board.topIngredient,
        (r) => (r.amount === null ? "—" : `${r.amount.toLocaleString("es-AR")} %`),
        itemHref,
      ),
    },
    {
      section: "price_affected",
      key: "precio",
      label: "Afectadas por precio",
      empty: "Ningún precio cambió una receta en los últimos 30 días.",
      rows: rows(
        board.priceAffected,
        (r) =>
          r.detail === "gained"
            ? "Ahora tiene costo"
            : r.detail === "lost"
              ? "Se quedó sin costo"
              : formatMoneyDifference(r.amount),
        recipeHref,
      ),
    },
    {
      section: "most_used",
      key: "mas-usado",
      label: "Lo más usado",
      empty: "Todavía no hay recetas vigentes.",
      rows: rows(board.mostUsed, (r) => (r.amount === null ? "—" : String(r.amount)), itemHref),
    },
  ];
  return all
    .filter((l) => board.sections.has(l.section))
    .map((l) => ({ key: l.key, label: l.label, empty: l.empty, rows: l.rows }));
}

async function Board({
  placeId,
  menus,
  ranking,
}: {
  placeId: string;
  menus: HomeMenus;
  ranking: string;
}) {
  const [counts, board, inbox, imports, recalc] = await Promise.all([
    safely(() => loadQuality(placeId)),
    safely(() => loadHomeBoard(placeId)),
    menus.approvals ? safely(() => getInbox(true, INBOX_LIMIT)) : Promise.resolve(null),
    safely(() => getRecentImports(1)),
    safely(getRecalcStatus),
  ]);
  if (!counts || !board) {
    return <Notice status="warn">No pudimos cargar el tablero de este local.</Notice>;
  }
  const has = (section: string) => board.sections.has(section);
  const find = (key: string) => counts.find((c) => c.indicator === key) ?? null;

  // Lo que la persona puede decidir, de toda su bandeja (lo mismo que ve en Aprobaciones).
  const decide = inbox ? inbox.filter((r) => r.can_decide).length : null;
  const capped = inbox !== null && inbox.length >= INBOX_LIMIT;
  const decideText = decide === null ? null : `${decide}${capped ? " o más" : ""}`;

  // El aviso: lo que falta, las revisiones que esperan y el recálculo, en una sola franja.
  const parts = attentionParts(counts);
  if (decide) {
    parts.push(
      decide === 1 && !capped
        ? "1 revisión espera tu decisión"
        : `${decideText} revisiones esperan tu decisión`,
    );
  }
  if (has("reliability") && recalc && (recalc.pending > 0 || recalc.failed > 0)) {
    if (recalc.pending > 0) {
      parts.push(
        `${recalc.pending} ${recalc.pending === 1 ? "pedido de recálculo espera" : "pedidos de recálculo esperan"}`,
      );
    }
    if (recalc.failed > 0) {
      parts.push(
        `${recalc.failed} ${recalc.failed === 1 ? "pedido no se pudo calcular" : "pedidos no se pudieron calcular"}`,
      );
    }
  }

  const quality = counts.reduce(
    (sum, c) => ({ done: sum.done + c.done, total: sum.total + c.total }),
    { done: 0, total: 0 },
  );
  const states = shortcutStates({
    approved: find("recipe_approved"),
    priced: find("ingredient_price"),
    costed: find("recipe_cost"),
    approvals: decide === null ? null : { count: decide, capped },
    quality: counts.length > 0 ? quality : null,
  });
  const errors = qualityTop(counts, 3);
  const lists = rankingLists(board, placeId);
  const last = imports?.[0];

  const reviews = (
    <div className="flex min-h-touch items-center justify-between gap-3 text-sm text-ink desk:min-h-8">
      <span>Revisiones esperando tu decisión</span>
      {decide ? (
        <Badge status="info">{decideText} esperan</Badge>
      ) : (
        <Badge status="ok">Al día</Badge>
      )}
    </div>
  );
  const errorList = (limit: number, label: string) =>
    errors.length === 0 ? (
      <p className="text-sm text-ink-muted">No falta nada por corregir.</p>
    ) : (
      <ul className="flex flex-col divide-y divide-line" aria-label={label}>
        {errors.slice(0, limit).map(({ key, label: item, count }) => (
          <li key={key}>
            <Link
              href={`/calidad/${key}?local=${placeId}`}
              className="flex min-h-touch items-center justify-between gap-4 text-sm underline-offset-4 hover:underline desk:min-h-7"
            >
              <span className="min-w-0 truncate text-primary">{item}</span>
              <span className="shrink-0 font-medium text-ink tabular-nums">{count}</span>
            </Link>
          </li>
        ))}
      </ul>
    );

  return (
    <>
      <AttentionStrip parts={parts} href={`/calidad?local=${placeId}`} />
      <div className="grid grid-cols-2 gap-3 desk:grid-cols-4 desk:gap-4">
        <Missing
          label="Sin aprobar"
          indicator="recipe_approved"
          counts={counts}
          placeId={placeId}
          compact
        />
        <Missing
          label="Pendientes de revisión"
          indicator="recipe_review"
          counts={counts}
          placeId={placeId}
          compact
        />
        <Missing
          label="Costo por corregir"
          indicator="recipe_cost"
          counts={counts}
          placeId={placeId}
          compact
        />
        <Missing
          label="Materias primas sin precio"
          indicator="ingredient_price"
          counts={counts}
          placeId={placeId}
          compact
        />
      </div>
      {/* Las tarjetas se reparten el ancho entre las que se muestran, y en la computadora el alto que queda. */}
      <div className="grid gap-4 desk:flex-1 desk:auto-cols-fr desk:grid-flow-col">
        {has("reliability") ? <ReliabilityTile board={board} placeId={placeId} /> : null}
        <Suspense fallback={<Loading />}>
          <CompareTile placeId={placeId} />
        </Suspense>
        <Tile
          title="Tareas pendientes"
          footer={
            menus.approvals ? { href: "/aprobaciones", label: "Ver las aprobaciones" } : undefined
          }
          className="hidden desk:flex"
        >
          {errorList(3, "Lo que más falta corregir")}
          {menus.approvals ? reviews : null}
          {last
            ? (() => {
                // Un solo renglón: la tarjeta no crece con el nombre del archivo. Entero, al pasar el mouse.
                const text = `Última importación de tus locales: ${last.file} · ${IMPORT_STATUS[last.status] ?? "En proceso"} · ${formatDate(last.createdAt)}`;
                return (
                  <p className="truncate text-xs text-ink-muted" title={text}>
                    {text}
                  </p>
                );
              })()
            : null}
        </Tile>
        {/* En el celular: lo que hay para decidir, sin las listas largas. */}
        <Tile title="Para decidir" className="order-first desk:hidden">
          {menus.approvals ? (
            <Link
              href="/aprobaciones"
              className="flex min-h-touch items-center justify-between gap-3 border-b border-line text-sm text-primary underline-offset-4 hover:underline"
            >
              Aprobaciones
              <ShortcutChip state={states.approvals} />
            </Link>
          ) : null}
          {errorList(2, "Lo que más falta corregir en este local")}
        </Tile>
      </div>
      {lists.length > 0 || SHORTCUTS.some((s) => menus[s.key]) ? (
        <div className="hidden gap-4 desk:grid desk:min-h-59 desk:grid-cols-12">
          {lists.length > 0 ? (
            <div className="col-span-5 flex min-w-0 flex-col *:flex-1">
              <Ranking lists={lists} initial={ranking} placeId={placeId} />
            </div>
          ) : null}
          <div
            className={cn(
              "flex min-w-0 flex-col *:flex-1",
              lists.length > 0 ? "col-span-7" : "col-span-12",
            )}
          >
            <Shortcuts states={states} menus={menus} />
          </div>
        </div>
      ) : null}
    </>
  );
}

// El tablero del recetario (sección 18; ADR-0045): lo ve quien entra a la calidad de datos.
// El local sale de la barra de arriba (o de ?local=): sin selector propio.
export function HomeBoardView({
  places,
  place,
  menus,
  ranking,
}: {
  places: QualityPlaceName[];
  place: QualityPlaceName | null;
  menus: HomeMenus;
  ranking: string;
}) {
  if (place) {
    return (
      <Suspense key={place.id} fallback={<Loading />}>
        <Board placeId={place.id} menus={menus} ranking={ranking} />
      </Suspense>
    );
  }
  return (
    <EmptyState title="Elegí un local para ver cómo está su recetario.">
      <p>Elegilo en «Local», en la barra de arriba, o entrá directo:</p>
      <ul className="mt-2 flex flex-wrap justify-center gap-x-4 gap-y-1" aria-label="Tus locales">
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
  );
}

// La línea de datos del encabezado: cuándo se calcularon los números y sobre cuánto.
export async function DataLine({ placeId }: { placeId: string }) {
  const [counts, board] = await Promise.all([
    safely(() => loadQuality(placeId)),
    safely(() => loadHomeBoard(placeId)),
  ]);
  const recipes = counts?.find((c) => c.indicator === "recipe_approved");
  const materials = counts?.find((c) => c.indicator === "ingredient_price");
  return (
    <span className="block text-xs text-ink-muted">
      {/* Los números se calculan al abrir la pantalla, con los datos de ese momento. */}
      Datos al momento: {formatDateTime(new Date().toISOString())}
      {recipes ? ` · ${recipes.total} ${recipes.total === 1 ? "receta" : "recetas"}` : ""}
      {board?.preparations == null ? "" : ` · ${board.preparations} preparaciones`}
      {materials ? ` · ${materials.total} materias primas` : ""}
    </span>
  );
}
