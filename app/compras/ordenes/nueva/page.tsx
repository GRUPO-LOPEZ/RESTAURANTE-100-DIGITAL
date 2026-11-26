import Link from "next/link";
import { Suspense, cache } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { OrderBuilder } from "@/components/order-builder";
import { buttonVariants } from "@/components/ui/button";
import { Select } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { first } from "@/lib/data";
import { todayInArgentina } from "@/lib/forms/schemas";
import { getOrderSuppliers, resolveOrderPlace, type OrderPlace } from "@/lib/purchase-orders-data";

// Nueva orden de compra en una pantalla (ADR-0069; ADR-0053). Se pide para el local elegido arriba (el selector es único
// y global): sin pantalla intermedia. Si arriba dice «Todos mis locales», la misma pantalla lo pregunta en una línea
// (criterio 2 de Soy). Un local sin código no puede pedir (P3): no hay con qué numerar la OC.
export default function NuevaOrdenPage({ searchParams }: PageProps<"/compras/ordenes/nueva">) {
  return (
    <AppShell
      title="Nueva orden de compra"
      fill
      back={
        <BackLink href="/compras/ordenes" label="Volver a órdenes de compra">
          Órdenes de compra
        </BackLink>
      }
      meta={
        <Suspense fallback={null}>
          <Meta searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Builder searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// El local, una sola vez por pedido (lo usan el encabezado y la orden).
const placeFor = cache(async (local: string | undefined) => {
  const session = await requireMenu("ordersCreate");
  return resolveOrderPlace(session.user_id, local);
});

async function place(searchParams: PageProps<"/compras/ordenes/nueva">["searchParams"]) {
  return placeFor(first((await searchParams).local));
}

async function Meta({
  searchParams,
}: {
  searchParams: PageProps<"/compras/ordenes/nueva">["searchParams"];
}) {
  const { place: p } = await place(searchParams);
  if (!p) return null;
  return (
    <span className="text-sm text-ink-muted">
      para <span className="font-medium text-ink">{p.name}</span> · el número sale al guardarla
    </span>
  );
}

async function Builder({
  searchParams,
}: {
  searchParams: PageProps<"/compras/ordenes/nueva">["searchParams"];
}) {
  const [{ places, place: p }, menus] = await Promise.all([place(searchParams), getMenus()]);
  if (places.length === 0)
    return <EmptyState title="No tenés locales donde hacer órdenes de compra." />;
  if (!p) return <PickPlace places={places} />;
  if (!p.code)
    return (
      <Notice status="warn">
        <span className="font-medium">Falta el código del local.</span> {p.name} todavía no tiene
        código, y sin código no se pueden numerar las órdenes de compra.{" "}
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
  return <OrderBuilder place={p} suppliers={suppliers} today={todayInArgentina()} />;
}

// Con «Todos mis locales» arriba: el local se elige acá mismo, en una línea (hasta 5, botones; más, un desplegable).
// Son enlaces y un formulario común: funcionan sin JavaScript y el ?local= se aplica al llegar (ADR-0048).
function PickPlace({ places }: { places: OrderPlace[] }) {
  return (
    <div className="flex flex-wrap items-center gap-2" role="group" aria-labelledby="oc-local">
      <span id="oc-local" className="text-base font-medium text-ink">
        ¿Para qué local es la orden?
      </span>
      {places.length <= 5 ? (
        places.map((p) => (
          <Link
            key={p.id}
            href={`/compras/ordenes/nueva?local=${p.id}`}
            className={buttonVariants({ variant: "outline" })}
          >
            {p.name}
          </Link>
        ))
      ) : (
        <form method="get" className="flex flex-wrap items-center gap-2">
          <label htmlFor="oc-local-elegir" className="sr-only">
            Local
          </label>
          <Select id="oc-local-elegir" name="local" defaultValue="" className="w-auto">
            <option value="" disabled>
              Elegí el local
            </option>
            {places.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </Select>
          <button type="submit" className={buttonVariants()}>
            Aplicar
          </button>
        </form>
      )}
    </div>
  );
}
