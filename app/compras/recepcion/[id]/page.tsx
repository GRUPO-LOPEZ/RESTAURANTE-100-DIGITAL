import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { ReceiptReport } from "@/components/receipt-report";
import { ReceiptWizard } from "@/components/receipt-wizard";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { UUID, first } from "@/lib/data";
import { getReceipt, type Receipt } from "@/lib/receipts-data";

// Una recepción (Fase 3, Prompt 4, ADR-0056). Abierta: los pasos (foto, renglones, firma y resumen). Cerrada: el informe,
// y al terminar («?aviso=cerrada»), el «Listo» con a quién se avisó.
export default function RecepcionDetallePage({
  params,
  searchParams,
}: PageProps<"/compras/recepcion/[id]">) {
  return (
    <AppShell
      title="Recepción"
      heading={
        <Suspense fallback="Recepción">
          <Heading params={params} />
        </Suspense>
      }
      back={
        <BackLink href="/compras/recepcion" label="Volver a recepción">
          Recepción
        </BackLink>
      }
    >
      <Suspense fallback={<Loading />}>
        <Detail params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const byId = cache(async (id: string) => {
  await requireMenu("receive");
  return getReceipt(id);
});

async function load(params: PageProps<"/compras/recepcion/[id]">["params"]) {
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return byId(id);
}

async function Heading({ params }: { params: PageProps<"/compras/recepcion/[id]">["params"] }) {
  const r = await load(params);
  if (!r) return "Recepción";
  const what = r.orderNumber ?? "sin OC";
  return r.status === "closed"
    ? `Recepción ${r.orderNumber ? `de ${r.orderNumber}` : "sin OC"} · ${r.supplierName}`
    : `Recibir ${what} · ${r.supplierName}`;
}

// El «Listo» al cerrar: cómo quedó la orden y a quién se avisó.
function doneText(r: Receipt): string {
  const order = !r.orderNumber
    ? "La recepción quedó guardada."
    : r.result === "partial"
      ? `La orden ${r.orderNumber} quedó recibida en parte: lo que falta se recibe cuando llegue.`
      : `La orden ${r.orderNumber} quedó recibida.`;
  const told =
    r.requestedByName && r.requestedByName !== r.receivedByName
      ? ` Se avisó a ${r.requestedByName}.`
      : "";
  const cash = r.cashPaid ? " El efectivo queda para que Compras lo confirme." : "";
  return order + told + cash;
}

async function Detail({
  params,
  searchParams,
}: {
  params: PageProps<"/compras/recepcion/[id]">["params"];
  searchParams: PageProps<"/compras/recepcion/[id]">["searchParams"];
}) {
  const [r, raw] = await Promise.all([load(params), searchParams]);
  if (!r) notFound();
  if (r.status === "closed")
    return (
      <div className="flex flex-col gap-4 desk:max-w-3xl">
        {first(raw.aviso) === "cerrada" ? (
          <Card className="flex flex-col gap-3">
            <h2 className="text-xl font-semibold text-ink">Listo</h2>
            <Notice status="ok">{doneText(r)}</Notice>
            <div className="flex flex-col gap-2 desk:flex-row">
              {r.orderId ? (
                <Button asChild>
                  <Link href={`/compras/ordenes/${r.orderId}?seccion=recepcion`}>Ver la orden</Link>
                </Button>
              ) : null}
              <Button asChild variant="outline">
                <Link href="/compras/recepcion">Recibir otra</Link>
              </Button>
            </div>
          </Card>
        ) : null}
        <Card className="flex flex-col gap-3">
          <ReceiptReport receipt={r} heading="Recepción cerrada" />
          {r.orderId && first(raw.aviso) !== "cerrada" ? (
            <Link
              href={`/compras/ordenes/${r.orderId}?seccion=recepcion`}
              className="text-primary underline-offset-4 hover:underline"
            >
              Ver la orden {r.orderNumber}
            </Link>
          ) : null}
        </Card>
      </div>
    );
  if (!r.canReceive)
    return (
      <Notice status="info">
        Esta recepción la está haciendo {r.receivedByName} y no podés recibir en {r.restaurantName}.
      </Notice>
    );
  return (
    <div className="flex flex-col gap-2">
      <p className="text-sm text-ink-muted">
        En <span className="font-medium text-ink">{r.restaurantName}</span>
        {r.requestedByName ? ` · la pidió ${r.requestedByName}` : ""}.
      </p>
      <ReceiptWizard receipt={r} />
    </div>
  );
}
