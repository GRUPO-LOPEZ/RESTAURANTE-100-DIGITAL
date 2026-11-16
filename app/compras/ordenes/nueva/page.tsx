import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { OrderBuilder } from "@/components/order-builder";
import { PlacePrompt } from "@/components/place-prompt";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { first } from "@/lib/data";
import { getOrderSuppliers, resolveOrderPlace } from "@/lib/purchase-orders-data";

// Nueva orden de compra (Fase 3, Prompt 3, ADR-0053). Celular primero: el cocinero pide desde la cocina. Se pide para el
// local elegido arriba (el selector es único y global, ADR-0036). Un local sin código no puede pedir (P3): no hay con
// qué numerar la OC.
export default function NuevaOrdenPage({ searchParams }: PageProps<"/compras/ordenes/nueva">) {
  return (
    <AppShell
      title="Nueva orden de compra"
      back={
        <BackLink href="/compras/ordenes" label="Volver a órdenes de compra">
          Órdenes de compra
        </BackLink>
      }
    >
      <Suspense fallback={<Loading />}>
        <Builder searchParams={searchParams} />
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

async function Builder({
  searchParams,
}: {
  searchParams: PageProps<"/compras/ordenes/nueva">["searchParams"];
}) {
  const session = await requireMenu("ordersCreate");
  const raw = await searchParams;
  const [{ places, place }, menus] = await Promise.all([
    resolveOrderPlace(session.user_id, first(raw.local)),
    getMenus(),
  ]);
  if (places.length === 0)
    return <EmptyState title="No tenés locales donde hacer órdenes de compra." />;
  if (!place)
    return <PlacePrompt title="Las órdenes de compra se hacen de a un local." places={places} />;
  if (!place.code)
    return (
      <Notice status="warn">
        <span className="font-medium">Falta el código del local.</span> {place.name} todavía no
        tiene código, y sin código no se pueden numerar las órdenes de compra.{" "}
        {menus.panel ? (
          <Link href="/configuracion" className="text-primary underline-offset-4 hover:underline">
            Cargalo en el Panel de control
          </Link>
        ) : (
          "Pedile a Dirección que lo cargue en el Panel de control."
        )}
      </Notice>
    );
  const suppliers = await getOrderSuppliers();
  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-ink-muted">
        Para <span className="font-medium text-ink">{place.name}</span>. Sin precios: los controla
        Compras con la factura.
      </p>
      <OrderBuilder place={place} suppliers={suppliers} today={today()} />
    </div>
  );
}
