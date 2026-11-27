import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { PriceListForm } from "@/components/price-list-form";
import { Notice } from "@/components/ui/notice";
import { requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, formatDate, uuidOrUndefined } from "@/lib/data";
import { getPriceListDetail } from "@/lib/price-lists-data";

// Cargar una lista de precios (ADR-0052; importar, controlar y corregir, ADR-0071), en una pantalla sin scroll: la
// planilla ocupa el alto que queda y se desplaza adentro. Viene del listado («+ Cargar lista»), de la ficha del
// proveedor (que ya lo deja elegido) o de «Corregir» en la ficha de la lista (?corregir=<lista>): ahí carga la vigente
// para crear su versión siguiente, con motivo.
type Props = PageProps<"/listas-de-precios/nueva">;

export default function NuevaListaPage({ searchParams }: Props) {
  return (
    <AppShell
      title="Cargar lista de precios"
      fill
      heading={
        <Suspense fallback="Cargar lista de precios">
          <Heading searchParams={searchParams} />
        </Suspense>
      }
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

async function correcting(searchParams: Props["searchParams"]) {
  const id = uuidOrUndefined(first((await searchParams).corregir));
  return id ? getPriceListDetail(id) : null;
}

async function Heading({ searchParams }: { searchParams: Props["searchParams"] }) {
  const l = await correcting(searchParams);
  return l ? `Corregir la lista de ${l.supplierName}` : "Cargar lista de precios";
}

async function Back({ searchParams }: { searchParams: Props["searchParams"] }) {
  const raw = await searchParams;
  const fix = uuidOrUndefined(first(raw.corregir));
  if (fix)
    return (
      <BackLink href={`/listas-de-precios/${fix}`} label="Volver a la lista">
        Lista
      </BackLink>
    );
  const volver = first(raw.volver);
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

const asText = (n: number) => (n === 0 ? "" : String(n).replace(".", ","));

async function Form({ searchParams }: { searchParams: Props["searchParams"] }) {
  await requireMenu("priceListsManage");
  const [raw, suppliers, fix] = await Promise.all([
    searchParams,
    getSuppliers(),
    correcting(searchParams),
  ]);
  if (fix && fix.status !== "accepted")
    return (
      <Notice status="warn">
        Solo se corrige la lista vigente. Esta está{" "}
        {fix.status === "voided" ? "anulada" : "fuera de uso"}: corregí la vigente del proveedor.
      </Notice>
    );
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  return (
    <>
      {fix ? (
        <p className="text-sm text-ink">
          Versión {fix.version} · vale desde el {formatDate(fix.validFrom)}. Al guardar queda la
          versión {fix.version + 1}, y esta pasa a la historia.
        </p>
      ) : null}
      {/* La clave arma la planilla de nuevo para cada lista: Next conserva el estado de una pantalla ya visitada aunque
          cambien los parámetros, y la corrección mostraba la planilla vacía de la carga anterior. */}
      <PriceListForm
        key={fix ? `corregir-${fix.id}-${fix.version}` : `nueva-${supplierId ?? ""}`}
        suppliers={suppliers.map((s) => ({ id: s.id, name: s.name }))}
        supplierId={suppliers.some((s) => s.id === supplierId) ? supplierId : undefined}
        today={today()}
        correct={
          fix
            ? {
                priceListId: fix.id,
                supplierId: fix.supplierId,
                supplierName: fix.supplierName,
                receivedOn: fix.receivedOn,
                validFrom: fix.validFrom,
                version: fix.version,
                rows: fix.items.map((i) => ({
                  name: i.rawName,
                  sku: i.sku ?? "",
                  list: String(i.listPrice).replace(".", ","),
                  b1: asText(i.bonus1Pct),
                  b2: asText(i.bonus2Pct),
                  perUnit: asText(i.bonusPerUnit),
                  vat: String(i.vatRate),
                  productId: i.purchaseProductId ?? "",
                })),
              }
            : undefined
        }
      />
    </>
  );
}
