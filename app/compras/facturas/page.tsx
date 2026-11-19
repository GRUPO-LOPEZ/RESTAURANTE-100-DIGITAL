import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { CreateModal } from "@/components/create-modal";
import { NewInvoiceForm } from "@/components/new-invoice-form";
import { Badge } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, getActiveRestaurantId, uuidOrUndefined } from "@/lib/data";
import { INVOICE_STATUS, INVOICE_TABS, failedLabel, invoiceLabel, shortDate } from "@/lib/invoices";
import {
  getInvoiceSuppliers,
  getInvoiceableOrders,
  getInvoices,
  type InvoiceRow,
} from "@/lib/invoices-data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { formatMoney } from "@/lib/money";
import { resolveOrderPlace } from "@/lib/purchase-orders-data";

// Facturas (Fase 3, Prompt 5B, ADR-0058), listado tipo C: ¿qué facturas llegaron, cuáles están observadas y por qué? Las
// del local elegido arriba (o de todos mis locales), pestañas por estado, filtros de proveedor y fecha, y 15 filas por
// página. «+ Nueva factura» abre el alta corta y lleva a la ficha.
export default function FacturasPage({ searchParams }: PageProps<"/compras/facturas">) {
  return (
    <AppShell
      title="Facturas"
      description="Las facturas de los proveedores: qué se controló, qué quedó observado y qué está liberado a pago."
      actions={
        <Suspense fallback={null}>
          <Actions searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Invoices searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// «+ Nueva factura»: en el local elegido arriba (o el único donde carga facturas).
async function Actions({
  searchParams,
}: {
  searchParams: PageProps<"/compras/facturas">["searchParams"];
}) {
  const [menus, session, raw] = await Promise.all([
    getMenus(),
    requireMenu("invoices"),
    searchParams,
  ]);
  if (!menus.invoicesManage) return null;
  const { place } = await resolveOrderPlace(
    session.user_id,
    first(raw.local),
    "purchasing.manage_invoices",
  );
  const [orders, suppliers] = place
    ? await Promise.all([getInvoiceableOrders(place.id), getInvoiceSuppliers()])
    : [[], []];
  return (
    <CreateModal
      href={place ? `/compras/facturas/nueva?local=${place.id}` : "/compras/facturas/nueva"}
      label="Nueva factura"
      title="Nueva factura"
      description={
        place
          ? `En ${place.name}. Las líneas salen de lo recibido en las órdenes que elijas; después la ajustás al papel en su ficha.`
          : "Las facturas se cargan de a un local."
      }
    >
      <NewInvoiceForm place={place} orders={orders} suppliers={suppliers} />
    </CreateModal>
  );
}

const PATH = "/compras/facturas";

async function Invoices({
  searchParams,
}: {
  searchParams: PageProps<"/compras/facturas">["searchParams"];
}) {
  const session = await requireMenu("invoices");
  const raw = await searchParams;
  const params = plainParams(raw);
  const list = parseList(raw, [], null);
  const tab = INVOICE_TABS.find((t) => t.value === first(raw.estado)) ?? INVOICE_TABS[0];
  // El local de la dirección o el elegido arriba (el selector es único y global); sin ninguno, todos los que ve.
  const local =
    uuidOrUndefined(first(raw.local)) ??
    (await getActiveRestaurantId(session.user_id)) ??
    undefined;
  const [suppliers, menus] = await Promise.all([getSuppliers(), getMenus()]);
  const canCreate = menus.invoicesManage;
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  const supplier = suppliers.find((s) => s.id === supplierId);
  const date = (v: string | undefined) => (v && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : undefined);
  const from = date(first(raw.desde));
  const to = date(first(raw.hasta));
  const { rows, total } = await getInvoices({
    status: tab?.filter,
    supplierId: supplier?.id,
    restaurantId: local,
    from,
    to,
    page: list.page - 1,
    size: list.size,
  });

  const active = [
    ...(supplier
      ? [
          {
            label: `Proveedor: ${supplier.name}`,
            removeHref: listHref(PATH, params, { proveedor: undefined, pagina: undefined }),
          },
        ]
      : []),
    ...(from
      ? [
          {
            label: `Desde el ${shortDate(from)}`,
            removeHref: listHref(PATH, params, { desde: undefined, pagina: undefined }),
          },
        ]
      : []),
    ...(to
      ? [
          {
            label: `Hasta el ${shortDate(to)}`,
            removeHref: listHref(PATH, params, { hasta: undefined, pagina: undefined }),
          },
        ]
      : []),
  ];
  const here = listHref(PATH, params, {});

  const columns: DataColumn<InvoiceRow>[] = [
    {
      key: "number",
      header: "Comprobante",
      mobile: "title",
      cell: (r) => (
        <Link
          href={`/compras/facturas/${r.id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center font-medium whitespace-nowrap text-primary tabular-nums underline-offset-4 hover:underline desk:min-h-0"
        >
          {invoiceLabel(r.invoice_class, r.point_of_sale, r.number)}
        </Link>
      ),
    },
    { key: "supplier", header: "Proveedor", mobile: "line", cell: (r) => r.supplier_name },
    { key: "place", header: "Local", mobile: "hidden", cell: (r) => r.restaurant_name },
    {
      key: "issued",
      header: "Fecha",
      mobile: "line",
      cell: (r) => <span className="whitespace-nowrap tabular-nums">{shortDate(r.issued_on)}</span>,
    },
    {
      key: "total",
      header: "Total",
      align: "right",
      mobile: "line",
      cell: (r) => <span className="tabular-nums">{formatMoney(r.total_amount)}</span>,
    },
    {
      key: "failed",
      header: "Qué no pasó",
      mobile: "hidden",
      // Una conforme que no pasó el control la dio por conforme otra persona, a mano: se dice eso.
      cell: (r) =>
        r.failed.length === 0 ? (
          <span className="text-ink-muted">—</span>
        ) : ["approved", "released", "paid"].includes(r.status) ? (
          <span className="text-sm text-ink">Conforme a mano</span>
        ) : (
          <span className="text-sm text-ink">{failedLabel(r.failed)}</span>
        ),
    },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (r) => (
        <Badge status={INVOICE_STATUS[r.status].status}>{INVOICE_STATUS[r.status].label}</Badge>
      ),
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <FilterBar label="Filtros de facturas" active={active}>
        <Field id="fc-proveedor" label="Proveedor" className="w-full desk:w-72">
          <Select name="proveedor" defaultValue={supplier?.id ?? ""}>
            <option value="">Todos</option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="fc-desde" label="Desde" className="w-full desk:w-44">
          <Input type="date" name="desde" defaultValue={from ?? ""} />
        </Field>
        <Field id="fc-hasta" label="Hasta" className="w-full desk:w-44">
          <Input type="date" name="hasta" defaultValue={to ?? ""} />
        </Field>
      </FilterBar>
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 factura" : `${total.toLocaleString("es-AR")} facturas`}
        </CardTitle>
        <Tabs
          label="Estado de las facturas"
          items={INVOICE_TABS.map((t) => ({
            href: listHref(PATH, params, { estado: t.value, pagina: undefined }),
            label: t.label,
            current: t.value === tab?.value,
          }))}
        />
        {rows.length === 0 && list.page > 1 ? (
          <EmptyState title="Esa página no existe.">
            <Link
              href={listHref(PATH, params, { pagina: undefined })}
              className="text-primary underline-offset-4 hover:underline"
            >
              Ir a la primera página
            </Link>
          </EmptyState>
        ) : (
          <DataTable
            caption="Facturas"
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState title="No hay facturas con esos filtros.">
                {canCreate ? "Cargá la primera con «Nueva factura»." : "Las carga Compras."}
              </EmptyState>
            }
          />
        )}
        {total > 0 ? (
          <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
        ) : null}
      </Card>
    </div>
  );
}
