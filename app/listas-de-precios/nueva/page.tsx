import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PriceListForm } from "@/components/price-list-form";
import { Card } from "@/components/ui/card";
import { requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, uuidOrUndefined } from "@/lib/data";

// Cargar una lista de precios (ADR-0052). Una pantalla propia y no un panel: la grilla necesita el ancho de la
// computadora. Viene del listado («+ Cargar lista») o de la ficha del proveedor, que ya lo deja elegido.
export default function NuevaListaPage({ searchParams }: PageProps<"/listas-de-precios/nueva">) {
  return (
    <AppShell
      title="Cargar lista de precios"
      description="Un renglón por artículo, como viene en la lista del proveedor. Lo que no reconozcamos va a la cola de mapeo."
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Form searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/listas-de-precios/nueva">["searchParams"];
}) {
  const volver = first((await searchParams).volver);
  const toSupplier = volver && /^\/proveedores\/[0-9a-f-]{36}$/.test(volver);
  return (
    <BackLink
      href={toSupplier ? volver : "/listas-de-precios"}
      label={toSupplier ? "Volver al proveedor" : "Volver a listas de precios"}
    >
      {toSupplier ? "Proveedor" : "Listas de precios"}
    </BackLink>
  );
}

// Hoy en la Argentina, para las fechas de la lista.
function today(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires" }).format(
    new Date(),
  );
}

async function Form({
  searchParams,
}: {
  searchParams: PageProps<"/listas-de-precios/nueva">["searchParams"];
}) {
  await requireMenu("priceListsManage");
  const [raw, suppliers] = await Promise.all([searchParams, getSuppliers()]);
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  return (
    <Card>
      <PriceListForm
        suppliers={suppliers.map((s) => ({ id: s.id, name: s.name }))}
        supplierId={suppliers.some((s) => s.id === supplierId) ? supplierId : undefined}
        today={today()}
      />
    </Card>
  );
}
