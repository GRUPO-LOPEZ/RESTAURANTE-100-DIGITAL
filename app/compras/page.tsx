import Link from "next/link";
import { Suspense, cache } from "react";

import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { CostHistoryChart, SpendChart } from "@/components/purchasing-charts";
import { AttentionStrip } from "@/components/quality-board";
import { Badge } from "@/components/ui/badge";
import { Metric } from "@/components/ui/metric";
import { ShortList } from "@/components/ui/short-list";
import { Tile } from "@/components/ui/tile";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { first } from "@/lib/data";
import { shortDate } from "@/lib/invoices";
import { formatMoney } from "@/lib/money";
import { DUE_LABELS } from "@/lib/payments";
import { getPurchasingBoard, type PurchasingBoard } from "@/lib/payments-data";
import { alertParts, spendBars, urgentCount } from "@/lib/purchasing-board";
import { resolveOrderPlace } from "@/lib/purchase-orders-data";

type Params = PageProps<"/compras">["searchParams"];

// Tablero de compras (Fase 3, Prompt 6, ADR-0060), tipo A: ¿qué hay que atender en compras y cuánto se gasta? Entra
// entero en una pantalla de computadora (1440 × 900 a 1920 × 1080, y 1715 × 843, ADR-0046 y ADR-0051), como el
// Inicio: franja «Requiere atención», 4 indicadores, gasto por rubro, cómo subieron los insumos y las alarmas, y abajo
// los pagos próximos y los artículos sin mapear. Quien no ve pagos (el chef) lo ve sin importes. En el celular: la
// franja, los indicadores y las alarmas.
export default function TableroDeComprasPage({ searchParams }: PageProps<"/compras">) {
  return (
    <AppShell
      title="Tablero de compras"
      fill
      heading={
        <Suspense fallback="Compras">
          <Heading searchParams={searchParams} />
        </Suspense>
      }
      description="Lo que hay que atender en compras, lo que se gasta y lo que vence."
      actions={
        <Link
          href="/compras/facturas?estado=observadas"
          className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-control"
        >
          Ver facturas observadas
        </Link>
      }
    >
      <Suspense fallback={<Loading />}>
        <Board searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// El local del tablero: el de ?local=, el del selector global o el único. Si no, todos los que la persona ve.
const boardPlace = cache(async (searchParams: Params) => {
  const session = await requireMenu("purchasingBoard");
  const raw = await searchParams;
  const { place } = await resolveOrderPlace(
    session.user_id,
    first(raw.local),
    "purchasing.view_dashboard",
  );
  return place;
});

async function Heading({ searchParams }: { searchParams: Params }) {
  const place = await boardPlace(searchParams);
  return (
    <>
      Compras
      <span className="font-normal text-ink-muted"> · {place?.name ?? "todos mis locales"}</span>
    </>
  );
}

const rowLink =
  "flex min-h-touch items-center justify-between gap-3 text-sm underline-offset-4 hover:underline desk:min-h-7";

const SEVERITY: Record<
  PurchasingBoard["alerts"][number]["severity"],
  { status: "bad" | "warn" | "info"; label: string }
> = {
  bad: { status: "bad", label: "Urgente" },
  warn: { status: "warn", label: "Atención" },
  info: { status: "info", label: "Revisar" },
};

function AlertRow({ alert }: { alert: PurchasingBoard["alerts"][number] }) {
  const s = SEVERITY[alert.severity];
  return (
    <Link href={alert.link} className={rowLink}>
      <span className="min-w-0 truncate text-primary" title={alert.title}>
        {alert.title}
      </span>
      <Badge status={s.status} className="shrink-0">
        {s.label}
      </Badge>
    </Link>
  );
}

async function Board({ searchParams }: { searchParams: Params }) {
  const [place, menus] = await Promise.all([boardPlace(searchParams), getMenus()]);
  const board = await getPurchasingBoard(place?.id);
  if (!board) {
    return <p className="text-base text-ink">No tenés locales con el tablero de compras.</p>;
  }
  const local = place ? `?local=${place.id}` : "";
  const amounts = board.can_see_amounts;
  const urgent = urgentCount(board.alert_kinds);
  const parts = alertParts(
    Object.fromEntries(Object.entries(board.alert_kinds).filter(([k]) => k !== "unmapped_article")),
  );
  const bars = board.spend ? spendBars(board.spend) : [];
  const history = (board.cost_history ?? []).filter((s) => (s.points ?? []).length > 0);
  const alerts = board.alerts.filter((a) => a.kind !== "unmapped_article");
  const unmappedAlerts = board.alerts.filter((a) => a.kind === "unmapped_article");
  const allAlerts = (
    <ul className="flex flex-col divide-y divide-line" aria-label="Todas las alarmas">
      {alerts.map((a, i) => (
        <li key={`${a.link}-${i}`}>
          <AlertRow alert={a} />
        </li>
      ))}
    </ul>
  );

  return (
    <>
      {urgent > 0 ? (
        <AttentionStrip
          parts={
            urgent > parts.length ? [...parts, `${urgent.toLocaleString("es-AR")} en total`] : parts
          }
          href={alerts[0]?.link ?? `/compras${local}`}
        />
      ) : null}

      <div className="grid grid-cols-2 gap-3 desk:grid-cols-4 desk:gap-4">
        <Metric
          compact
          label="Facturas observadas"
          value={board.observed}
          status={board.observed > 0 ? "bad" : "ok"}
          statusLabel={board.observed > 0 ? "Revisar" : "Ninguna"}
          emptyLabel="Sin facturas"
          href={board.observed > 0 ? "/compras/facturas?estado=observadas" : undefined}
          hrefLabel="Ver cuáles"
        />
        <Metric
          compact
          label="Vencen esta semana"
          value={board.due_week}
          unit={board.due_week === 1 ? "factura" : "facturas"}
          comparison={
            amounts && board.due_week_amount !== null
              ? formatMoney(board.due_week_amount)
              : undefined
          }
          period={amounts ? undefined : "sin acceso a importes"}
          status={board.due_week > 0 ? "warn" : "ok"}
          statusLabel={board.due_week > 0 ? "Por pagar" : "Nada vence"}
          emptyLabel="Sin facturas"
          href={board.due_week > 0 && menus.payments ? "/compras/pagos" : undefined}
          hrefLabel="Ver la agenda"
        />
        <Metric
          compact
          label="Órdenes de compra abiertas"
          value={board.open_orders}
          status={board.open_orders > 0 ? "info" : "ok"}
          statusLabel={board.open_orders > 0 ? "Por recibir" : "Ninguna"}
          emptyLabel="Sin órdenes"
          href={board.open_orders > 0 && menus.orders ? "/compras/ordenes" : undefined}
          hrefLabel="Ver cuáles"
        />
        <Metric
          compact
          label="Listas de precios vencidas"
          value={menus.priceLists ? board.expired_lists : null}
          missingReason="Las ve Compras."
          status={board.expired_lists > 0 ? "warn" : "ok"}
          statusLabel={board.expired_lists > 0 ? "Pedir lista nueva" : "Al día"}
          emptyLabel="Sin listas"
          href={
            board.expired_lists > 0 && menus.priceLists
              ? "/listas-de-precios?estado=expired"
              : undefined
          }
          hrefLabel="Ver cuáles"
        />
      </div>

      {/* Dos filas que ocupan el alto que queda; la de los gráficos, más alta. Las alarmas, a la derecha, en las dos. La
          página queda quieta: lo que no entra se desplaza dentro de su tarjeta (ADR-0051). En el celular, una debajo de
          otra, y solo las alarmas. */}
      <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[5fr_5fr_4fr] desk:grid-rows-[minmax(0,1.5fr)_minmax(0,1fr)]">
        <Tile title="Gasto por rubro del mes" scroll className="hidden desk:flex">
          {!amounts ? (
            <p className="text-sm text-ink">Sin acceso a importes.</p>
          ) : bars.length === 0 ? (
            <p className="text-sm text-ink">Sin facturas conformes este mes.</p>
          ) : (
            <SpendChart bars={bars} />
          )}
        </Tile>
        <Tile title="Cómo subieron los insumos" scroll className="hidden desk:flex">
          {!amounts ? (
            <p className="text-sm text-ink">Sin acceso a importes.</p>
          ) : history.length === 0 ? (
            <p className="text-sm text-ink">Sin compras con precio en los últimos 90 días.</p>
          ) : (
            <CostHistoryChart series={history} />
          )}
        </Tile>
        <Tile
          id="alarmas"
          title={`Alarmas (${urgent.toLocaleString("es-AR")})`}
          scroll
          className="order-first desk:order-none desk:row-span-2"
        >
          <ShortList
            label="Alarmas"
            items={alerts}
            limit={8}
            itemKey={(a) => `${a.kind}-${a.link}-${a.title}`}
            renderItem={(a) => <AlertRow alert={a} />}
            empty={<p className="text-sm text-ink">No hay alarmas pendientes.</p>}
            more={
              <ActionModal
                label={`Ver las ${urgent.toLocaleString("es-AR")} alarmas`}
                variant="link"
                icon="none"
                size="sm"
                title="Alarmas de compras"
                description={
                  urgent > alerts.length
                    ? `Las ${alerts.length} más urgentes de ${urgent.toLocaleString("es-AR")}.`
                    : "De la más urgente a la menos."
                }
              >
                {allAlerts}
              </ActionModal>
            }
          />
        </Tile>
        <Tile
          title="Pagos próximos"
          scroll
          className="hidden desk:flex"
          footer={
            menus.payments ? { href: "/compras/pagos", label: "Ver la agenda de pagos" } : undefined
          }
        >
          <ShortList
            label="Pagos próximos"
            items={board.next_payments}
            limit={5}
            itemKey={(p) => p.invoice_id}
            empty={<p className="text-sm text-ink">No hay facturas por pagar.</p>}
            renderItem={(p) => (
              <Link href={`/compras/facturas/${p.invoice_id}`} className={rowLink}>
                <span className="min-w-0 truncate">
                  <span className="text-primary">{p.supplier}</span>
                  <span className="text-ink"> · {p.label}</span>
                </span>
                <span className="flex shrink-0 items-center gap-2 text-ink tabular-nums">
                  <span>{shortDate(p.due_on)}</span>
                  {p.balance !== null ? <span>{formatMoney(p.balance)}</span> : null}
                  <Badge status={DUE_LABELS[p.due_state].status}>
                    {DUE_LABELS[p.due_state].label}
                  </Badge>
                </span>
              </Link>
            )}
          />
        </Tile>
        <Tile
          title={`Artículos sin mapear (${board.unmapped.toLocaleString("es-AR")})`}
          scroll
          className="hidden desk:flex"
          footer={
            board.unmapped > 0 && menus.catalog
              ? { href: "/materias-primas/sin-mapear", label: "Mapear" }
              : undefined
          }
        >
          <ShortList
            label="Artículos sin mapear"
            items={unmappedAlerts}
            limit={4}
            itemKey={(a) => a.title}
            empty={
              <p className="text-sm text-ink">
                {board.unmapped > 0
                  ? "Están en la lista de artículos sin mapear."
                  : "Todo lo que llegó en las facturas tiene su materia prima."}
              </p>
            }
            renderItem={(a) => (
              <span className="flex min-h-touch items-center text-sm text-ink desk:min-h-7">
                <span className="truncate" title={a.title}>
                  {a.title.replace(/^Sin mapear: /, "")}
                </span>
              </span>
            )}
          />
        </Tile>
      </div>
    </>
  );
}
