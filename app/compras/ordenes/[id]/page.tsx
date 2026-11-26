import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { Suspense, cache } from "react";

import {
  cancelOrderAction,
  recordNewsAction,
  submitOrderAction,
} from "@/app/compras/ordenes/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { FocusTarget } from "@/components/focus-target";
import { ReceiptReport } from "@/components/receipt-report";
import { StartReceiptButton } from "@/components/receipt-start";
import { Badge } from "@/components/ui/badge";
import { FormSelect, FormTextarea } from "@/components/ui/form";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Tile } from "@/components/ui/tile";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate, formatDateTime } from "@/lib/data";
import { todayInArgentina } from "@/lib/forms/schemas";
import {
  CHANNEL_NAMES,
  EVENT_KINDS,
  NEWS_KINDS,
  PO_STATUS,
  messageStatus,
  orderIndicators,
  qtyText,
} from "@/lib/purchase-orders";
import { CopyButton } from "@/components/copy-button";
import { getOrderDetail } from "@/lib/purchase-orders-data";
import { getOrderReceipts } from "@/lib/receipts-data";

// Ficha de una orden de compra (Fase 3, Prompt 3, ADR-0053): las líneas, la línea de tiempo (creada, a aprobar,
// en cola de envío, novedades) y el mensaje al proveedor. Mientras nadie despache la cola (decisión 9 de Soy), el texto
// se puede copiar y mandar a mano. Sin precios. Con los criterios de Soy (ADR-0068): en una pantalla, con las acciones
// en fila arriba, 4 indicadores y las tarjetas que se desplazan adentro.
export default function OrdenPage({ params, searchParams }: PageProps<"/compras/ordenes/[id]">) {
  return (
    <AppShell
      title="Orden de compra"
      fill
      heading={
        <Suspense fallback="Orden de compra">
          <Heading params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <Actions params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Detail params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const byId = cache(async (id: string) => {
  const session = await requireMenu("orders");
  return getOrderDetail(id, session.user_id);
});

async function load(params: PageProps<"/compras/ordenes/[id]">["params"]) {
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return byId(id);
}

async function Heading({ params }: { params: PageProps<"/compras/ordenes/[id]">["params"] }) {
  const o = await load(params);
  return o ? `${o.number} · ${o.supplierName}` : "Orden de compra";
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/compras/ordenes/[id]">["searchParams"];
}) {
  const volver = first((await searchParams).volver);
  return (
    <BackLink
      href={volver && /^\/compras\/ordenes(\?|$)/.test(volver) ? volver : "/compras/ordenes"}
      label="Volver a órdenes de compra"
    >
      Órdenes de compra
    </BackLink>
  );
}

async function Meta({ params }: { params: PageProps<"/compras/ordenes/[id]">["params"] }) {
  const o = await load(params);
  if (!o) return null;
  const s = PO_STATUS[o.status];
  return (
    <>
      {/* Cuándo se pidió está en «Qué pasó»: el encabezado entra en una línea en 1440 (criterio 5 de Soy). */}
      <span className="text-sm text-ink-muted">{o.restaurantName}</span>
      <Badge status={s.status}>{s.label}</Badge>
    </>
  );
}

async function Actions({ params }: { params: PageProps<"/compras/ordenes/[id]">["params"] }) {
  const [o, menus] = await Promise.all([load(params), getMenus()]);
  if (!o) return null;
  const canSend = menus.ordersCreate && o.status === "draft";
  // Recibir (ADR-0056): quien recibe, con la OC enviada, con novedad o recibida en parte (la base controla el local).
  const canReceive =
    menus.receive && ["sent", "with_news", "partially_received"].includes(o.status);
  const canNews = menus.orderNews && ["sent", "with_news", "partially_received"].includes(o.status);
  // Cancela quien la pidió o Compras (decisión de Joaco, 2026-11-16; la base lo vuelve a controlar).
  const canCancel =
    ((o.mine && menus.ordersCreate) || menus.ordersApprove) &&
    ["draft", "pending_approval", "sent", "with_news"].includes(o.status);
  return (
    <div className="flex flex-wrap gap-2">
      {canReceive ? <StartReceiptButton orderId={o.id} number={o.number} resume={false} /> : null}
      {canSend ? (
        <ActionModal
          label={o.requiresApproval ? "Enviar a aprobación" : "Enviar orden"}
          icon="none"
          title={`Enviar la orden ${o.number}`}
          description="Si el proveedor requiere aprobación, va a Compras; si no, queda en la cola de envío."
        >
          <ActionForm action={submitOrderAction} submitLabel="Enviar">
            <input type="hidden" name="orderId" value={o.id} />
          </ActionForm>
        </ActionModal>
      ) : null}
      {canNews ? (
        <ActionModal
          label="Registrar novedad"
          icon="none"
          title={`Novedad en la orden ${o.number}`}
          description="Le llega un aviso a quien la pidió."
        >
          <ActionForm action={recordNewsAction} schema="reason" submitLabel="Registrar">
            <input type="hidden" name="orderId" value={o.id} />
            <FormSelect id="oc-novedad-tipo" name="kind" label="Qué pasó" defaultValue="shortage">
              {NEWS_KINDS.map((k) => (
                <option key={k} value={k}>
                  {EVENT_KINDS[k]}
                </option>
              ))}
            </FormSelect>
            <FormTextarea
              id="oc-novedad-texto"
              name="reason"
              label="Novedad"
              hint="Por ejemplo: «No tiene ricota, llega el jueves»."
              required
              maxLength={1000}
            />
          </ActionForm>
        </ActionModal>
      ) : null}
      {canCancel ? (
        // «Cancelar», como en la ficha de la factura (mismo nombre para la misma acción, criterio 15 de Soy).
        <ActionModal
          label="Cancelar"
          accessibleName="Cancelar la orden"
          icon="none"
          title={`Cancelar la orden ${o.number}`}
          description="No se borra: queda cancelada con su motivo, y si estaba en la cola de envío, no se manda."
        >
          <ActionForm
            action={cancelOrderAction}
            schema="reason"
            submitLabel="Cancelar la orden"
            variant="destructive"
          >
            <input type="hidden" name="orderId" value={o.id} />
            <FormTextarea
              id="oc-cancelar-motivo"
              name="reason"
              label="Motivo"
              hint="Queda en el historial y le avisa a quien la pidió."
              required
              maxLength={500}
            />
          </ActionForm>
        </ActionModal>
      ) : null}
    </div>
  );
}

const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  enviada: { status: "ok", text: "Orden mandada: quedó en la cola de envío al proveedor." },
  aprobacion: {
    status: "info",
    text: "Enviada a aprobación: la aprueba Compras. Te avisamos cuando se resuelva.",
  },
  borrador: { status: "ok", text: "Borrador guardado. Lo podés mandar cuando quieras." },
  novedad: { status: "ok", text: "Novedad registrada. Le avisamos a quien la pidió." },
  cancelada: { status: "ok", text: "Orden cancelada." },
};

async function Detail({
  params,
  searchParams,
}: {
  params: PageProps<"/compras/ordenes/[id]">["params"];
  searchParams: PageProps<"/compras/ordenes/[id]">["searchParams"];
}) {
  const [o, raw] = await Promise.all([load(params), searchParams]);
  if (!o) notFound();
  // El aviso de una recepción lleva a su sección: el foco va ahí (FocusTarget). El id lleva el comienzo del de la OC:
  // Next guarda oculta la ficha anterior y no tiene que haber dos «#recepcion».
  const anchor = `recepcion-${o.id.slice(0, 8)}`;
  if (first(raw.seccion) === "recepcion") redirect(`/compras/ordenes/${o.id}#${anchor}`);
  const receipts = await getOrderReceipts(o.id);
  const closedCount = receipts.filter((r) => r.status === "closed").length;
  const notice = NOTICES[first(raw.aviso) ?? ""];
  // La línea de tiempo: lo que dice la orden y sus novedades, en orden.
  const timeline = [
    { at: o.createdAt, text: `Creada${o.mine ? " por vos" : ""}.` },
    ...(o.approvalRequestId && o.status === "pending_approval"
      ? [{ at: o.createdAt, text: "Espera la aprobación de Compras." }]
      : []),
    ...(o.sentAt
      ? [
          {
            at: o.sentAt,
            text: `En cola de envío por ${CHANNEL_NAMES[o.sentChannel ?? ""] ?? "el canal del proveedor"}.`,
          },
        ]
      : []),
    ...o.events.map((e) => ({
      at: e.createdAt,
      text: `${EVENT_KINDS[e.kind as keyof typeof EVENT_KINDS] ?? "Novedad"}: ${e.message}`,
    })),
  ].sort((a, b) => a.at.localeCompare(b.at));

  const indicators = orderIndicators(o, todayInArgentina(), formatDate);

  return (
    <div className="flex flex-col gap-4 desk:min-h-0 desk:flex-[1_1_0px]">
      <FocusTarget />
      {notice ? <Notice status={notice.status}>{notice.text}</Notice> : null}
      {/* Métricas confiables (lib/metrics.ts): antes de mandarla, lo recibido no se mide. No se repiten abajo. */}
      <div className="grid gap-3 desk:grid-cols-4">
        {indicators.map((m) => (
          <Metric
            key={m.key}
            compact
            label={m.label}
            value={m.value}
            total={m.total}
            comparison={m.comparison}
            emptyLabel="Sin artículos"
            missingReason={m.missingReason}
            status={m.status}
            statusLabel={m.statusLabel}
          />
        ))}
      </div>
      <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[3fr_2fr] desk:grid-rows-[minmax(0,1fr)]">
        <Tile title="Artículos de la orden" scroll>
          <ul aria-label="Artículos de la orden" className="flex flex-col divide-y divide-line">
            {o.lines.map((l) => (
              <li
                key={l.lineOrder}
                className="flex flex-wrap items-baseline justify-between gap-2 py-2"
              >
                <div className="min-w-0">
                  <p className="text-base [overflow-wrap:anywhere] text-ink">{l.name}</p>
                  <p className="text-sm text-ink-muted">
                    {l.withoutInvoiceName
                      ? "Sin nombre de factura"
                      : [l.packageName, l.sku].filter(Boolean).join(" · ")}
                    {l.note ? ` · ${l.note}` : ""}
                  </p>
                </div>
                <p className="text-base font-medium text-ink tabular-nums">
                  {qtyText(l.quantity)} {l.withoutInvoiceName ? l.unitName : l.packageName}
                  {l.estimatedKg !== null ? (
                    <span className="font-normal text-ink-muted">
                      {" "}
                      · ≈ {qtyText(l.estimatedKg)} kg
                    </span>
                  ) : null}
                </p>
              </li>
            ))}
          </ul>
          {o.notes ? <p className="text-sm text-ink">Observaciones: {o.notes}</p> : null}
        </Tile>
        <div className="flex flex-col gap-4 desk:min-h-0">
          <Tile title="Qué pasó" scroll className="desk:flex-[1_1_0px]">
            <ol className="flex flex-col gap-2">
              {timeline.map((t, i) => (
                <li key={i} className="text-sm text-ink">
                  <span className="text-ink-muted tabular-nums">{formatDateTime(t.at)}</span> ·{" "}
                  {t.text}
                </li>
              ))}
            </ol>
            {o.status === "pending_approval" ? (
              <p className="text-sm text-ink">
                La aprueba Compras en{" "}
                <Link
                  href="/aprobaciones"
                  className="text-primary underline-offset-4 hover:underline"
                >
                  Aprobaciones
                </Link>
                .
              </p>
            ) : null}
          </Tile>
          {o.message ? (
            <Tile
              title="Mensaje al proveedor"
              scroll
              className="desk:flex-[1_1_0px]"
              aside={
                <Badge status={messageStatus(o.message.status).status}>
                  {messageStatus(o.message.status).label}
                </Badge>
              }
            >
              <p className="text-sm text-ink-muted">
                Por {CHANNEL_NAMES[o.message.channel] ?? o.message.channel} a {o.message.target}.
                Mientras no se despache solo, se puede copiar y mandar a mano.
              </p>
              {/* Sin scroll propio: lo que no entra se desplaza con la tarjeta (ADR-0051). */}
              <pre className="rounded-sm bg-app p-3 font-sans text-sm whitespace-pre-wrap text-ink">
                {o.message.body}
              </pre>
              <CopyButton text={o.message.body} label="Copiar mensaje" />
            </Tile>
          ) : null}
          {receipts.length > 0 ? (
            <Tile id={anchor} title="Recepción" scroll className="desk:flex-[1_1_0px]">
              {receipts.map((r, i) =>
                r.status === "open" ? (
                  <p key={r.id} className="text-sm text-ink">
                    {r.receivedByName} empezó a recibirla.{" "}
                    {r.canReceive ? (
                      <Link
                        href={`/compras/recepcion/${r.id}`}
                        className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-control"
                      >
                        Retomar la recepción
                      </Link>
                    ) : null}
                  </p>
                ) : (
                  <div key={r.id} className={i > 0 ? "border-t border-line pt-3" : undefined}>
                    <ReceiptReport
                      receipt={r}
                      heading={
                        closedCount > 1 && r.closedAt
                          ? `Recepción del ${formatDate(r.closedAt)}`
                          : undefined
                      }
                    />
                  </div>
                ),
              )}
            </Tile>
          ) : null}
        </div>
      </div>
    </div>
  );
}
