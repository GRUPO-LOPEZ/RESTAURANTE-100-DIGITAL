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
import { Card, CardTitle } from "@/components/ui/card";
import { FormSelect, FormTextarea } from "@/components/ui/form";
import { Notice } from "@/components/ui/notice";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate, formatDateTime } from "@/lib/data";
import {
  CHANNEL_NAMES,
  EVENT_KINDS,
  NEWS_KINDS,
  PO_STATUS,
  messageStatus,
  qtyText,
} from "@/lib/purchase-orders";
import { CopyButton } from "@/components/copy-button";
import { getOrderDetail } from "@/lib/purchase-orders-data";
import { getOrderReceipts } from "@/lib/receipts-data";

// Ficha de una orden de compra (Fase 3, Prompt 3, ADR-0053): las líneas, la línea de tiempo (creada, a aprobar,
// en cola de envío, novedades) y el mensaje al proveedor. Mientras nadie despache la cola (decisión 9 de Soy), el texto
// se puede copiar y mandar a mano. Sin precios.
export default function OrdenPage({ params, searchParams }: PageProps<"/compras/ordenes/[id]">) {
  return (
    <AppShell
      title="Orden de compra"
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
      <span className="text-sm text-ink-muted tabular-nums">
        {o.restaurantName} · pedida el {formatDate(o.createdAt)} · entrega esperada el{" "}
        {formatDate(o.expectedOn)}
      </span>
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
          label={o.requiresApproval ? "Enviar a aprobación" : "Mandar OC"}
          icon="none"
          title={`Mandar la orden ${o.number}`}
          description="Si el proveedor requiere aprobación, va a Compras; si no, queda en la cola de envío."
        >
          <ActionForm action={submitOrderAction} submitLabel="Mandar">
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
        <ActionModal
          label="Cancelar la orden"
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

  return (
    <div className="flex flex-col gap-4">
      <FocusTarget />
      {notice ? <Notice status={notice.status}>{notice.text}</Notice> : null}
      <div className="grid gap-4 desk:grid-cols-[3fr_2fr]">
        <Card className="flex flex-col gap-3">
          <CardTitle className="tabular-nums">
            {o.lines.length === 1 ? "1 artículo" : `${o.lines.length} artículos`}
          </CardTitle>
          <ul aria-label="Artículos de la orden" className="flex flex-col divide-y divide-line">
            {o.lines.map((l) => (
              <li
                key={l.lineOrder}
                className="flex flex-wrap items-baseline justify-between gap-2 py-2"
              >
                <div className="min-w-0">
                  <p className="text-base text-ink">{l.name}</p>
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
        </Card>
        <div className="flex flex-col gap-4">
          <Card className="flex flex-col gap-2">
            <CardTitle>Qué pasó</CardTitle>
            <ol className="flex flex-col gap-2">
              {timeline.map((t, i) => (
                <li key={i} className="text-sm text-ink">
                  <span className="text-ink-muted tabular-nums">{formatDateTime(t.at)}</span> ·{" "}
                  {t.text}
                </li>
              ))}
            </ol>
          </Card>
          {o.message ? (
            <Card className="flex flex-col gap-2">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <CardTitle>Mensaje al proveedor</CardTitle>
                <Badge status={messageStatus(o.message.status).status}>
                  {messageStatus(o.message.status).label}
                </Badge>
              </div>
              <p className="text-sm text-ink-muted">
                Por {CHANNEL_NAMES[o.message.channel] ?? o.message.channel} a {o.message.target}.
                Mientras no se despache solo, se puede copiar y mandar a mano.
              </p>
              {/* Se desplaza adentro: con tabIndex se alcanza con el teclado. */}
              <pre
                tabIndex={0}
                role="region"
                aria-label="Texto del mensaje al proveedor"
                className="relative max-h-72 overflow-auto rounded-sm bg-app p-3 font-sans text-sm whitespace-pre-wrap text-ink focus-visible:outline-2 focus-visible:outline-primary"
              >
                {o.message.body}
              </pre>
              <CopyButton text={o.message.body} label="Copiar mensaje" />
            </Card>
          ) : null}
          {receipts.length > 0 ? (
            <Card
              id={anchor}
              tabIndex={-1}
              className="flex flex-col gap-3 outline-none target:border-primary focus-visible:outline-2 focus-visible:outline-primary"
            >
              <CardTitle>Recepción</CardTitle>
              {receipts.map((r, i) =>
                r.status === "open" ? (
                  <p key={r.id} className="text-sm text-ink">
                    {r.receivedByName} empezó a recibirla.{" "}
                    {r.canReceive ? (
                      <Link
                        href={`/compras/recepcion/${r.id}`}
                        className="text-primary underline-offset-4 hover:underline"
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
            </Card>
          ) : null}
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
        </div>
      </div>
    </div>
  );
}
