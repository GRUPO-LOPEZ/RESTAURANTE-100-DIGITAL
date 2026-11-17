import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { ReceiptReport } from "@/components/receipt-report";
import { ReceiptWizard } from "@/components/receipt-wizard";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { UUID } from "@/lib/data";
import { getReceipt } from "@/lib/receipts-data";

// Una recepción (Fase 3, Prompt 4, ADR-0056). Abierta: los pasos (foto, renglones, firma y resumen). Cerrada: el informe.
export default function RecepcionDetallePage({ params }: PageProps<"/compras/recepcion/[id]">) {
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
        <Detail params={params} />
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
  return r.orderNumber
    ? `Recibir ${r.orderNumber} · ${r.supplierName}`
    : `Recibir sin OC · ${r.supplierName}`;
}

async function Detail({ params }: { params: PageProps<"/compras/recepcion/[id]">["params"] }) {
  const r = await load(params);
  if (!r) notFound();
  if (r.status === "closed")
    return (
      <Card className="flex flex-col gap-3 desk:max-w-3xl">
        <ReceiptReport receipt={r} heading="Recepción cerrada" />
        {r.orderId ? (
          <Link
            href={`/compras/ordenes/${r.orderId}?seccion=recepcion`}
            className="text-primary underline-offset-4 hover:underline"
          >
            Ver la orden {r.orderNumber}
          </Link>
        ) : null}
      </Card>
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
