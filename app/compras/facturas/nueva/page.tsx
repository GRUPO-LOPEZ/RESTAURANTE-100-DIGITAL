import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { NewInvoiceForm } from "@/components/new-invoice-form";
import { PlacePrompt } from "@/components/place-prompt";
import { EmptyState } from "@/components/ui/states";
import { requireMenu } from "@/lib/auth/session";
import { first } from "@/lib/data";
import { getInvoiceSuppliers, getInvoiceableOrders } from "@/lib/invoices-data";
import { resolveOrderPlace } from "@/lib/purchase-orders-data";

// Nueva factura (ADR-0058): la misma alta corta del modal del listado, como página (sin JavaScript, o abierta en otra
// pestaña). Se carga en el local elegido arriba (el selector es único y global, ADR-0036).
export default function NuevaFacturaPage({ searchParams }: PageProps<"/compras/facturas/nueva">) {
  return (
    <AppShell
      title="Nueva factura"
      back={
        <BackLink href="/compras/facturas" label="Volver a facturas">
          Facturas
        </BackLink>
      }
    >
      <Suspense fallback={<Loading />}>
        <Form searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Form({
  searchParams,
}: {
  searchParams: PageProps<"/compras/facturas/nueva">["searchParams"];
}) {
  const session = await requireMenu("invoicesManage");
  const raw = await searchParams;
  const { places, place } = await resolveOrderPlace(
    session.user_id,
    first(raw.local),
    "purchasing.manage_invoices",
  );
  if (places.length === 0) return <EmptyState title="No tenés locales donde cargar facturas." />;
  if (!place) return <PlacePrompt title="Las facturas se cargan de a un local." places={places} />;
  const [orders, suppliers] = await Promise.all([
    getInvoiceableOrders(place.id),
    getInvoiceSuppliers(),
  ]);
  return (
    <div className="flex max-w-xl flex-col gap-4">
      <p className="text-sm text-ink-muted">
        En <span className="font-medium text-ink">{place.name}</span>. Las líneas salen de lo
        recibido en las órdenes que elijas; después la ajustás al papel en su ficha.
      </p>
      <NewInvoiceForm place={place} orders={orders} suppliers={suppliers} />
    </div>
  );
}
