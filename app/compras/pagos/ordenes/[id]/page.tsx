import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { voidPaymentOrderAction } from "@/app/compras/pagos/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PrintButton } from "@/components/print-button";
import { Badge } from "@/components/ui/badge";
import { FormTextarea } from "@/components/ui/form";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Tile } from "@/components/ui/tile";
import { requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDateTime } from "@/lib/data";
import { shortDate } from "@/lib/invoices";
import { formatMoney } from "@/lib/money";
import { getPaymentOrderDetail, type PaymentOrderDetail } from "@/lib/payment-orders-data";
import { ACCOUNT_KIND_LABELS, ORDER_METHOD_LABELS } from "@/lib/payment-orders";
import { METHOD_LABELS } from "@/lib/payments";

// Orden de pago (ADR-0070): la ficha que se abre al registrar el pago y que se imprime o se comparte con el proveedor.
// Quién paga y su CUIT, a quién y a qué cuenta, los medios (de qué caja o cuenta salió cada uno, los datos del cheque),
// las facturas que cancela, lo que queda a cuenta, las retenciones (en 0 por ahora) y la versión con quién la registró
// (criterio 14 de Soy). Quien paga la puede anular, con motivo: no se borra.
type Props = PageProps<"/compras/pagos/ordenes/[id]">;

export default function OrdenDePagoPage({ params, searchParams }: Props) {
  return (
    <AppShell
      title="Orden de pago"
      fill
      heading={
        <Suspense fallback="Orden de pago">
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
        <Order params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Vuelve a Pagos con sus filtros y su página (tipo C), si vino de ahí.
async function Back({ searchParams }: { searchParams: Props["searchParams"] }) {
  const volver = first((await searchParams).volver);
  const href =
    volver && /^\/compras\/pagos(\?|$)/.test(volver) ? volver : "/compras/pagos?estado=ordenes";
  return (
    <BackLink href={href} label="Volver a pagos">
      Pagos
    </BackLink>
  );
}

const orderById = cache(getPaymentOrderDetail);

async function load(params: Props["params"]): Promise<PaymentOrderDetail | null> {
  await requireMenu("payments");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return orderById(id);
}

async function Heading({ params }: { params: Props["params"] }) {
  const op = await load(params);
  return op ? `Orden de pago ${op.number}` : "Orden de pago";
}

async function Meta({ params }: { params: Props["params"] }) {
  const op = await load(params);
  if (!op) return null;
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        {[op.supplier?.name, op.restaurant?.name, shortDate(op.paid_on)]
          .filter(Boolean)
          .join(" · ")}
      </span>
      {op.status === "voided" ? (
        <Badge status="bad">Anulada</Badge>
      ) : (
        <Badge status="ok">Registrada</Badge>
      )}
    </>
  );
}

async function Actions({ params }: { params: Props["params"] }) {
  const op = await load(params);
  if (!op) return null;
  return (
    <div className="flex items-center gap-2 print:hidden">
      {op.can_void && op.status === "registered" ? (
        <ActionModal
          label="Anular"
          accessibleName={`Anular la orden de pago ${op.number}`}
          icon="none"
          title="Anular la orden de pago"
          description="Las facturas vuelven a quedar con saldo. No se borra: queda en la historia, con el motivo."
        >
          <ActionForm
            action={voidPaymentOrderAction}
            schema="reason"
            submitLabel="Anular la orden"
            variant="destructive"
          >
            <input type="hidden" name="paymentOrderId" value={op.id} />
            <FormTextarea
              id="op-anular-motivo"
              name="reason"
              label="Motivo"
              hint="Queda en el historial."
              required
              maxLength={500}
            />
          </ActionForm>
        </ActionModal>
      ) : null}
      <PrintButton />
    </div>
  );
}

const NOTICES: Record<string, { status: "ok" | "info" | "warn"; text: string }> = {
  registrada: { status: "ok", text: "Pago registrado. Podés imprimir la orden o compartirla." },
  "registrada-sin-comprobante": {
    status: "warn",
    text: "Pago registrado, pero no pudimos guardar el comprobante. Guardalo aparte: la orden ya está registrada.",
  },
  anulada: { status: "info", text: "Orden de pago anulada. Las facturas volvieron a tener saldo." },
};

// El nombre del medio, el mismo que en el panel de pago.
function methodName(l: PaymentOrderDetail["lines"][number]): string {
  if (l.method === "check")
    return ORDER_METHOD_LABELS[l.check?.third_party ? "third_party_check" : "own_check"];
  return l.method === "electronic_code" ? METHOD_LABELS[l.method] : ORDER_METHOD_LABELS[l.method];
}

async function Order({
  params,
  searchParams,
}: {
  params: Props["params"];
  searchParams: Props["searchParams"];
}) {
  const [op, query] = await Promise.all([load(params), searchParams]);
  if (!op) notFound();
  const saved = NOTICES[first(query.aviso) ?? ""] ?? null;
  const applied = op.invoices.reduce((s, i) => s + i.applied, 0);
  const withholdings =
    op.withholdings.income_tax + op.withholdings.vat + op.withholdings.gross_income;
  const voided = op.status === "voided";

  return (
    <>
      {saved ? (
        <Notice status={saved.status} className="print:hidden">
          {saved.text}
        </Notice>
      ) : null}
      {op.status === "voided" ? (
        <Notice status="bad">
          Anulada{op.voided_at ? ` el ${formatDateTime(op.voided_at)}` : ""}
          {op.voided_reason ? `: ${op.voided_reason}` : "."}
        </Notice>
      ) : null}

      <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4 print:grid-cols-4">
        <Metric
          compact
          label="Total de la orden"
          value={formatMoney(op.total)}
          emptyLabel="Sin datos"
          status={voided ? "none" : "ok"}
          statusLabel={voided ? "Anulada" : "Registrada"}
        />
        <Metric
          compact
          label="Aplicado a facturas"
          value={op.invoices.length === 0 ? null : formatMoney(applied)}
          period={op.invoices.length === 1 ? "1 factura" : `${op.invoices.length} facturas`}
          missingReason="No cancela facturas: todo queda a cuenta."
          emptyLabel="Sin facturas"
          status={voided ? "none" : "ok"}
          statusLabel={voided ? "Anulada" : "Aplicado"}
        />
        <Metric
          compact
          label="Queda a cuenta"
          value={formatMoney(op.unapplied)}
          emptyLabel="Sin datos"
          status={voided ? "none" : op.unapplied > 0.005 ? "info" : "ok"}
          statusLabel={voided ? "Anulada" : op.unapplied > 0.005 ? "Anticipo" : "Nada a cuenta"}
        />
        <Metric
          compact
          label="Retenciones"
          value={null}
          missingReason="Sin cálculo por ahora: Ganancias, IVA e IIBB van en $ 0."
          emptyLabel="Sin datos"
          status="none"
          statusLabel="Sin cálculo por ahora"
        />
      </div>

      <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-[4fr_5fr_5fr] desk:grid-rows-[minmax(0,1fr)] print:grid-cols-1">
        <Tile title="Quién paga y a quién" scroll>
          <dl className="flex flex-col gap-3 text-sm">
            <div>
              <dt className="text-ink-muted">Paga</dt>
              <dd className="text-ink">
                {op.payer ? (
                  <>
                    <span className="block font-medium">{op.payer.name}</span>
                    {op.payer.tax_id ? (
                      <span className="tabular-nums">CUIT {op.payer.tax_id}</span>
                    ) : null}
                  </>
                ) : (
                  "—"
                )}
              </dd>
            </div>
            <div>
              <dt className="text-ink-muted">Local</dt>
              <dd className="text-ink">{op.restaurant?.name ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">Proveedor</dt>
              <dd className="text-ink">
                {op.supplier ? (
                  <>
                    <span className="block font-medium">{op.supplier.legal_name}</span>
                    {op.supplier.legal_name !== op.supplier.name ? (
                      <span className="block">{op.supplier.name}</span>
                    ) : null}
                    {op.supplier.tax_id ? (
                      <span className="tabular-nums">CUIT {op.supplier.tax_id}</span>
                    ) : null}
                  </>
                ) : (
                  "—"
                )}
              </dd>
            </div>
            <div>
              <dt className="text-ink-muted">Fecha del pago</dt>
              <dd className="text-ink tabular-nums">{shortDate(op.paid_on)}</dd>
            </div>
            {op.notes ? (
              <div>
                <dt className="text-ink-muted">Observaciones</dt>
                <dd className="[overflow-wrap:break-word] text-ink">{op.notes}</dd>
              </div>
            ) : null}
          </dl>
        </Tile>

        <Tile title="Medios de pago" scroll aside={`Neto ${formatMoney(op.total - withholdings)}`}>
          <ul aria-label="Medios de pago" className="flex flex-col divide-y divide-line">
            {op.lines.map((l, i) => (
              <li key={i} className="flex flex-col gap-1 py-2 text-sm first:pt-0">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="font-medium text-ink">{methodName(l)}</span>
                  <span className="text-ink tabular-nums">{formatMoney(l.amount)}</span>
                </div>
                {l.from ? (
                  <span className="text-ink">
                    Sale de: {l.from.name} ({ACCOUNT_KIND_LABELS[l.from.kind].toLowerCase()})
                  </span>
                ) : null}
                {l.to ? (
                  <span className="[overflow-wrap:anywhere] text-ink tabular-nums">
                    A la cuenta:{" "}
                    {[
                      l.to.bank,
                      l.to.holder_name ? `titular ${l.to.holder_name}` : null,
                      l.to.holder_tax_id ? `CUIT ${l.to.holder_tax_id}` : null,
                      l.to.cbu ? `CBU ${l.to.cbu}` : l.to.cbu_end ? `CBU …${l.to.cbu_end}` : null,
                      l.to.alias ? `alias ${l.to.alias}` : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                ) : null}
                {l.check ? (
                  <span className="text-ink tabular-nums">
                    {[
                      l.check.number ? `N.º ${l.check.number}` : null,
                      l.check.bank,
                      l.check.due_on ? `se cobra el ${shortDate(l.check.due_on)}` : null,
                      l.check.drawer_name ? `libró ${l.check.drawer_name}` : null,
                      l.check.drawer_tax_id ? `CUIT ${l.check.drawer_tax_id}` : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                ) : null}
                {l.reference ? <span className="text-ink">Referencia: {l.reference}</span> : null}
              </li>
            ))}
          </ul>
        </Tile>

        <Tile title="Facturas que cancela" scroll>
          {op.invoices.length === 0 ? (
            <p className="text-sm text-ink">No cancela facturas: todo queda a cuenta.</p>
          ) : (
            <table className="w-full text-sm">
              <caption className="sr-only">Facturas que cancela</caption>
              <thead>
                <tr className="text-left text-ink-muted">
                  <th scope="col" className="pb-1 font-medium">
                    Comprobante
                  </th>
                  <th scope="col" className="pb-1 text-right font-medium">
                    Total
                  </th>
                  <th scope="col" className="pb-1 text-right font-medium">
                    Notas de crédito
                  </th>
                  <th scope="col" className="pb-1 text-right font-medium">
                    Se cancela
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {op.invoices.map((inv) => (
                  <tr key={inv.invoice_id}>
                    <td className="py-1.5 pr-2">
                      <Link
                        href={`/compras/facturas/${inv.invoice_id}`}
                        className="text-primary tabular-nums underline-offset-4 hover:underline print:text-ink print:no-underline"
                      >
                        {inv.label}
                      </Link>
                      <span className="block text-ink-muted tabular-nums">
                        del {shortDate(inv.issued_on)}
                      </span>
                    </td>
                    <td className="py-1.5 text-right tabular-nums">{formatMoney(inv.total)}</td>
                    <td className="py-1.5 text-right tabular-nums">
                      {inv.notes ? formatMoney(-inv.notes) : "—"}
                    </td>
                    <td className="py-1.5 text-right font-medium tabular-nums">
                      {formatMoney(inv.applied)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <p className="mt-auto pt-2 text-xs text-ink-muted tabular-nums">
            Versión {op.version} · registrada
            {op.registered_by ? ` por ${op.registered_by}` : ""} el{" "}
            {formatDateTime(op.registered_at)}
          </p>
        </Tile>
      </div>
    </>
  );
}
