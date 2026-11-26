import Link from "next/link";
import { Suspense } from "react";
import { Truck } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { CreateModal } from "@/components/create-modal";
import { NewInvoiceForm } from "@/components/new-invoice-form";
import { Badge } from "@/components/ui/badge";
import { CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Select } from "@/components/ui/field";
import { DateInput } from "@/components/ui/date-input";
import { FilterBar } from "@/components/ui/filter-bar";
import { GroupLayout, GroupPanel } from "@/components/ui/group-panel";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, getActiveRestaurantId, uuidOrUndefined } from "@/lib/data";
import { sumCounts } from "@/lib/group-counts";
import { getInvoiceSupplierCounts } from "@/lib/group-counts-data";
import {
  INVOICE_STATUS,
  INVOICE_TABS,
  dueState,
  failedLabel,
  invoiceLabel,
  invoiceTab,
  shortDate,
} from "@/lib/invoices";
import { todayInArgentina } from "@/lib/forms/schemas";
import { monthName, monthRange } from "@/lib/payment-orders";
import { ReliabilityFilter } from "@/components/costs/reliability-filter";
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
// página. «+ Nueva factura» abre el alta corta y lleva a la ficha. Con los criterios de Soy (ADR-0068): en una pantalla,
// los proveedores con su cantidad en el panel de la izquierda y la tabla con su propio scroll.
export default function FacturasPage({ searchParams }: PageProps<"/compras/facturas">) {
  return (
    <AppShell
      title="Facturas"
      heading="¿Qué facturas hay para revisar y pagar?"
      fill
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
          ? `En ${place.name}. Las líneas salen de lo recibido, con el precio de la lista.`
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
  const tab = invoiceTab(first(raw.estado));
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
  // La fecha: este mes, el mes pasado, todas u otras (desde y hasta). Lo que pide hacer algo (observadas, para dar
  // conforme, vencidas) arranca en todas las fechas: una vencida del mes pasado sigue pendiente.
  const today = todayInArgentina();
  const asked = first(raw.fecha);
  const period: "this" | "last" | "all" | "other" =
    asked === "mes-pasado"
      ? "last"
      : asked === "otras"
        ? "other"
        : asked === "todas" || (!asked && tab.todo)
          ? "all"
          : "this";
  const month = period === "this" || period === "last" ? monthRange(today, period) : null;
  const from = month?.from ?? (period === "other" ? date(first(raw.desde)) : undefined);
  const to = month?.to ?? (period === "other" ? date(first(raw.hasta)) : undefined);
  const [{ rows, total }, groups] = await Promise.all([
    getInvoices({
      status: tab.filter,
      supplierId: supplier?.id,
      restaurantId: local,
      from,
      to,
      page: list.page - 1,
      size: list.size,
    }),
    // El panel cuenta con los mismos filtros, menos el proveedor (pgTAP 419).
    getInvoiceSupplierCounts({ status: tab.filter, restaurantId: local, from, to }),
  ]);

  const active = [
    ...(supplier
      ? [
          {
            label: `Proveedor: ${supplier.name}`,
            removeHref: listHref(PATH, params, { proveedor: undefined, pagina: undefined }),
          },
        ]
      : []),
    ...(period === "other" && from
      ? [
          {
            label: `Desde el ${shortDate(from)}`,
            removeHref: listHref(PATH, params, { desde: undefined, pagina: undefined }),
          },
        ]
      : []),
    ...(period === "other" && to
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
      wrap: "narrow",
      cell: (r) => (
        <Link
          href={`/compras/facturas/${r.id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center font-medium text-primary tabular-nums underline-offset-4 hover:underline desk:min-h-0"
        >
          {invoiceLabel(r.invoice_class, r.point_of_sale, r.number)}
        </Link>
      ),
    },
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "line",
      wrap: true,
      cell: (r) => r.supplier_name,
    },
    // Con un local elegido arriba, la columna sobra (y deja lugar a «Vence»).
    ...(local
      ? []
      : [
          {
            key: "place",
            header: "Local",
            mobile: "hidden",
            wrap: "narrow",
            cell: (r) => r.restaurant_name,
          } satisfies DataColumn<InvoiceRow>,
        ]),
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
      key: "due",
      header: "Vence",
      mobile: "line",
      cell: (r) => {
        const due = ["released", "approved"].includes(r.status)
          ? dueState(r.due_on, today, r.status)
          : "none";
        return (
          <span className="inline-flex items-center gap-2 whitespace-nowrap tabular-nums">
            {shortDate(r.due_on)}
            {due === "bad" ? <Badge status="bad">Vencida</Badge> : null}
          </span>
        );
      },
    },
    {
      key: "failed",
      header: "Qué no pasó",
      mobile: "hidden",
      wrap: "narrow",
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
    <GroupLayout
      panel={
        <GroupPanel
          label="Proveedores"
          icon={Truck}
          unit={{ one: "factura", many: "facturas" }}
          allLabel="Todos los proveedores"
          allCount={sumCounts(groups)}
          items={groups}
          selected={supplier ? { id: supplier.id, name: supplier.name } : undefined}
          hrefFor={(id) => listHref(PATH, params, { proveedor: id, pagina: undefined })}
        />
      }
    >
      <FilterBar label="Filtros de facturas" active={active}>
        {/* En la computadora, el proveedor se elige en el panel; en el celular, acá. La clave lo rehace al cambiar
            (si no, el filtro de fecha mandaría el proveedor de antes). */}
        <Field id="fc-proveedor" label="Proveedor" className="w-full desk:hidden">
          <Select key={supplier?.id ?? "todos"} name="proveedor" defaultValue={supplier?.id ?? ""}>
            <option value="">Todos</option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field id="fc-estado" label="Estado" className="w-full desk:w-48">
          <Select key={tab.value ?? "todas"} name="estado" defaultValue={tab.value ?? ""}>
            {INVOICE_TABS.map((t) => (
              <option key={t.value ?? "todas"} value={t.value ?? ""}>
                {t.label}
              </option>
            ))}
          </Select>
        </Field>
        {period === "other" ? (
          <>
            <Field id="fc-desde" label="Desde" className="w-full desk:w-44">
              <DateInput name="desde" defaultValue={from ?? ""} />
            </Field>
            <Field id="fc-hasta" label="Hasta" className="w-full desk:w-44">
              <DateInput name="hasta" defaultValue={to ?? ""} />
            </Field>
          </>
        ) : null}
      </FilterBar>
      <section
        aria-label="Facturas"
        className="flex flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0 desk:flex-[1_1_0px]"
      >
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 factura" : `${total.toLocaleString("es-AR")} facturas`}
          {tab.value ? ` ${tab.label.toLowerCase()}` : ""}
          {month ? ` de ${monthName(month.from)}` : ""}
        </CardTitle>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <ReliabilityFilter
            path={PATH}
            name="estado"
            label="Lo que pide hacer algo"
            keep={keepExcept(params, ["estado", "pagina"])}
            options={INVOICE_TABS.filter((t) => t.todo).map((t) => ({
              value: t.value ?? "",
              label: t.label,
              current: t.value === tab.value,
              // Apretar el que está aplicado lo saca (vuelve a todas).
              href: listHref(PATH, params, {
                estado: t.value === tab.value ? undefined : t.value,
                pagina: undefined,
              }),
            }))}
          />
          <ReliabilityFilter
            path={PATH}
            name="fecha"
            label="Fecha"
            keep={keepExcept(params, ["fecha", "desde", "hasta", "pagina"])}
            options={(
              [
                ["este-mes", "Este mes", "this"],
                ["mes-pasado", "El mes pasado", "last"],
                ["todas", "Todas las fechas", "all"],
                ["otras", "Otras fechas", "other"],
              ] as const
            ).map(([value, label, p]) => ({
              value,
              label,
              current: period === p,
              href: listHref(PATH, params, {
                fecha: value,
                desde: undefined,
                hasta: undefined,
                pagina: undefined,
              }),
            }))}
          />
        </div>
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
            scroll
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
      </section>
    </GroupLayout>
  );
}

// Lo que sigue igual al apretar un botón de filtro.
function keepExcept(params: Record<string, string>, drop: string[]): Record<string, string> {
  return Object.fromEntries(Object.entries(params).filter(([k]) => !drop.includes(k)));
}
