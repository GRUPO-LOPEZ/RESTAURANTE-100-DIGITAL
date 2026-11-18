import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { PlacePrompt } from "@/components/place-prompt";
import { StartReceiptButton, StartWithoutOrder } from "@/components/receipt-start";
import { Badge } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/states";
import { requireMenu } from "@/lib/auth/session";
import { first, formatDate } from "@/lib/data";
import { PO_STATUS } from "@/lib/purchase-orders";
import { resolveOrderPlace } from "@/lib/purchase-orders-data";
import {
  getReceivableOrders,
  getReceivableSuppliers,
  type ReceivableOrder,
} from "@/lib/receipts-data";

// Recepción (Fase 3, Prompt 4, ADR-0056), paso 1: «¿Qué llegó?». Celular primero: se recibe en la puerta de la cocina.
// Las OC para recibir del local elegido arriba (el selector es único y global, ADR-0036), por proveedor y las de hoy
// primero. Abajo, «Recibir sin OC».
export default function RecepcionPage({ searchParams }: PageProps<"/compras/recepcion">) {
  return (
    <AppShell
      title="Recepción"
      description="Lo que llega se revisa renglón por renglón contra la orden, con la foto del papel."
    >
      <Suspense fallback={<Loading />}>
        <WhatArrived searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// Hoy en la Argentina.
function today(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires" }).format(
    new Date(),
  );
}

function when(date: string, now: string): string {
  if (date === now) return "Llega hoy";
  if (date < now) return `Tenía que llegar el ${formatDate(date)}`;
  return `Llega el ${formatDate(date)}`;
}

async function WhatArrived({
  searchParams,
}: {
  searchParams: PageProps<"/compras/recepcion">["searchParams"];
}) {
  const session = await requireMenu("receive");
  const raw = await searchParams;
  const { places, place } = await resolveOrderPlace(
    session.user_id,
    first(raw.local),
    "purchasing.receive",
  );
  if (places.length === 0) return <EmptyState title="No tenés locales donde recibir mercadería." />;
  if (!place) return <PlacePrompt title="Se recibe de a un local." places={places} />;
  const [orders, suppliers] = await Promise.all([
    getReceivableOrders(place.id),
    getReceivableSuppliers(place.id),
  ]);
  const now = today();
  // Por proveedor, en el orden que da la base (las de hoy o atrasadas, primero).
  const groups = new Map<string, { name: string; orders: ReceivableOrder[] }>();
  for (const o of orders) {
    const g = groups.get(o.supplier_id) ?? { name: o.supplier_name, orders: [] };
    g.orders.push(o);
    groups.set(o.supplier_id, g);
  }

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-ink-muted">
        En <span className="font-medium text-ink">{place.name}</span>.
      </p>
      <section aria-labelledby="que-llego" className="flex flex-col gap-3">
        <h2 id="que-llego" className="text-xl font-semibold text-ink">
          ¿Qué llegó?
        </h2>
        {groups.size === 0 ? (
          <EmptyState title="No hay órdenes para recibir en este local.">
            Si llegó mercadería sin orden de compra, usá «Recibir sin OC».
          </EmptyState>
        ) : (
          [...groups.entries()].map(([supplierId, g]) => (
            <Card key={supplierId} className="flex flex-col gap-2">
              <CardTitle>{g.name}</CardTitle>
              <ul
                aria-label={`Órdenes de ${g.name}`}
                className="flex flex-col divide-y divide-line"
              >
                {g.orders.map((o) => (
                  <li
                    key={o.id}
                    className="flex flex-col gap-2 py-3 desk:flex-row desk:items-center desk:justify-between"
                  >
                    <div className="flex min-w-0 flex-col gap-1">
                      <p className="flex flex-wrap items-center gap-2 text-base font-medium text-ink">
                        <span className="tabular-nums">{o.number}</span>
                        <Badge status={PO_STATUS[o.status].status}>
                          {PO_STATUS[o.status].label}
                        </Badge>
                        {o.open_receipt_id ? (
                          <Badge status="draft">Recepción empezada</Badge>
                        ) : null}
                      </p>
                      <p className="text-sm text-ink-muted tabular-nums">
                        {when(o.expected_delivery_on, now)} ·{" "}
                        {o.pending_lines === 1
                          ? "1 renglón por recibir"
                          : `${o.pending_lines} renglones por recibir`}
                      </p>
                    </div>
                    <StartReceiptButton
                      orderId={o.id}
                      number={o.number}
                      resume={o.open_receipt_id !== null}
                    />
                  </li>
                ))}
              </ul>
            </Card>
          ))
        )}
      </section>
      <Card className="flex flex-col gap-3">
        <CardTitle>¿Llegó algo sin orden de compra?</CardTitle>
        <StartWithoutOrder restaurantId={place.id} suppliers={suppliers} />
      </Card>
    </div>
  );
}
