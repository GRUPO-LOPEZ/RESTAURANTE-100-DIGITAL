import Link from "next/link";
import { Suspense } from "react";
import { Truck } from "lucide-react";

import { confirmCashAction } from "@/app/compras/pagos/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { RegisterPayment } from "@/components/register-payment";
import { Badge } from "@/components/ui/badge";
import { CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { GroupLayout, GroupPanel } from "@/components/ui/group-panel";
import { Notice } from "@/components/ui/notice";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { Tooltip, TooltipProvider } from "@/components/ui/tooltip";
import { Button } from "@/components/ui/button";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, getActiveRestaurantId, uuidOrUndefined } from "@/lib/data";
import { sumCounts, type GroupItem } from "@/lib/group-counts";
import { getPaymentSupplierCounts } from "@/lib/group-counts-data";
import { invoiceLabel, shortDate } from "@/lib/invoices";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { formatMoney } from "@/lib/money";
import {
  getPaymentOrderSupplierCounts,
  getPaymentOrders,
  type PaymentOrderRow,
} from "@/lib/payment-orders-data";
import { ORDER_METHOD_LABELS } from "@/lib/payment-orders";
import { DUE_LABELS, METHOD_LABELS, PAYMENT_TABS, daysLabel } from "@/lib/payments";
import {
  getCashToConfirm,
  getPaymentSchedule,
  getSuppliersToPay,
  type CashRow,
  type ScheduleRow,
} from "@/lib/payments-data";
import { resolveOrderPlace } from "@/lib/purchase-orders-data";

// Pagos (Fase 3, Prompt 6, ADR-0060), listado tipo C: ¿qué hay que pagar y a quién le debemos? Las facturas liberadas
// del local elegido arriba (o de todos mis locales) por vencimiento, las vencidas, las pagadas y el efectivo pagado al
// recibir que falta confirmar. «Registrar pago» abre el panel con las facturas del proveedor. Con los criterios de Soy
// (ADR-0068): en una pantalla, los proveedores con su cantidad en el panel de la izquierda y la tabla con su scroll.
export default function PagosPage({ searchParams }: PageProps<"/compras/pagos">) {
  return (
    <AppShell
      title="Pagos"
      fill
      description="Lo que vence, lo que está vencido y lo que ya se pagó a cada proveedor."
      actions={
        <Suspense fallback={null}>
          <Actions searchParams={searchParams} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Payments searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

// «Registrar pago»: en el local elegido arriba (un pago es de un local, decisión de Joaco).
async function Actions({
  searchParams,
}: {
  searchParams: PageProps<"/compras/pagos">["searchParams"];
}) {
  const [menus, session, raw] = await Promise.all([
    getMenus(),
    requireMenu("payments"),
    searchParams,
  ]);
  if (!menus.pay) return null;
  const { place, places } = await resolveOrderPlace(
    session.user_id,
    first(raw.local),
    "purchasing.pay",
  );
  if (!place) {
    // Un pago es de un local: con «todos mis locales» arriba, el botón dice por qué no se puede.
    if (places.length === 0) return null;
    const why = "Elegí un local arriba para registrar un pago: cada pago es de un local.";
    return (
      <TooltipProvider>
        <Tooltip content={why}>
          <Button
            type="button"
            aria-disabled="true"
            aria-describedby="pg-sin-local"
            className="opacity-50"
          >
            Registrar pago
            <span id="pg-sin-local" className="sr-only">
              {why}
            </span>
          </Button>
        </Tooltip>
      </TooltipProvider>
    );
  }
  const suppliers = await getSuppliersToPay(place.id);
  return (
    <RegisterPayment
      restaurant={place}
      suppliers={suppliers}
      initialSupplierId={uuidOrUndefined(first(raw.proveedor))}
    />
  );
}

const PATH = "/compras/pagos";

// Lo que vuelve de una acción que se lleva la fila (?aviso=).
const NOTICES: Record<string, string> = {
  "efectivo-a-cuenta":
    "Efectivo confirmado. Quedó a cuenta: se aplica solo cuando su factura quede conforme.",
  "efectivo-aplicado": "Efectivo confirmado y aplicado a su factura.",
};

async function Payments({
  searchParams,
}: {
  searchParams: PageProps<"/compras/pagos">["searchParams"];
}) {
  const session = await requireMenu("payments");
  const raw = await searchParams;
  const params = plainParams(raw);
  const list = parseList(raw, [], null);
  const tab = PAYMENT_TABS.find((t) => t.value === first(raw.estado)) ?? PAYMENT_TABS[0]!;
  const local =
    uuidOrUndefined(first(raw.local)) ??
    (await getActiveRestaurantId(session.user_id)) ??
    undefined;
  const [suppliers, menus] = await Promise.all([getSuppliers(), getMenus()]);
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  const supplier = suppliers.find((s) => s.id === supplierId);
  const active = supplier
    ? [
        {
          label: `Proveedor: ${supplier.name}`,
          removeHref: listHref(PATH, params, { proveedor: undefined, pagina: undefined }),
        },
      ]
    : [];
  const here = listHref(PATH, params, {});
  const tabs = (
    <Tabs
      label="Estado de los pagos"
      items={PAYMENT_TABS.map((t) => ({
        href: listHref(PATH, params, { estado: t.value, pagina: undefined }),
        label: t.label,
        current: t.value === tab.value,
      }))}
    />
  );
  // En la computadora, el proveedor se elige en el panel; en el celular, acá (la clave lo rehace al cambiar).
  const filters = (
    <FilterBar label="Filtros de pagos" active={active}>
      <Field id="pg-proveedor" label="Proveedor" className="w-full desk:hidden">
        <Select key={supplier?.id ?? "todos"} name="proveedor" defaultValue={supplier?.id ?? ""}>
          <option value="">Todos</option>
          {suppliers.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </Select>
      </Field>
    </FilterBar>
  );

  // El panel cuenta lo que muestra la pestaña.
  const unit =
    tab.tab === "orders"
      ? { one: "orden de pago", many: "órdenes de pago" }
      : tab.tab === "cash"
        ? { one: "pago", many: "pagos" }
        : { one: "factura", many: "facturas" };
  const layout = (groups: GroupItem[], children: React.ReactNode) => (
    <GroupLayout
      panel={
        <GroupPanel
          label="Proveedores"
          icon={Truck}
          unit={unit}
          allLabel="Todos los proveedores"
          allCount={sumCounts(groups)}
          items={groups}
          selected={supplier ? { id: supplier.id, name: supplier.name } : undefined}
          hrefFor={(id) => listHref(PATH, params, { proveedor: id, pagina: undefined })}
        />
      }
    >
      {children}
    </GroupLayout>
  );
  const box =
    "flex flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0 desk:flex-[1_1_0px]";

  // «Para confirmar»: el efectivo pagado al recibir (decisión 7 de Soy).
  if (tab.tab === "cash") {
    const all = await getCashToConfirm(local);
    const cash = all.filter((c) => !supplier || c.supplier_id === supplier.id);
    // El panel cuenta lo mismo que la tabla, sin el filtro del proveedor.
    const counts = new Map<string, GroupItem>();
    for (const c of all) {
      const g = counts.get(c.supplier_id) ?? { id: c.supplier_id, name: c.supplier_name, count: 0 };
      g.count += 1;
      counts.set(c.supplier_id, g);
    }
    const saved = NOTICES[first(raw.aviso) ?? ""];
    return layout(
      [...counts.values()],
      <>
        {saved ? <Notice status="ok">{saved}</Notice> : null}
        {filters}
        <section aria-label="Efectivo para confirmar" className={box}>
          <CardTitle className="tabular-nums">
            {cash.length === 1 ? "1 pago para confirmar" : `${cash.length} pagos para confirmar`}
          </CardTitle>
          {tabs}
          <DataTable
            caption="Efectivo para confirmar"
            scroll
            columns={cashColumns(menus.pay)}
            rows={cash}
            rowKey={(r) => r.payment_id}
            empty={<EmptyState title="No hay efectivo para confirmar." />}
          />
        </section>
      </>,
    );
  }

  // «Órdenes de pago» (ADR-0070): las registradas y las anuladas, con su número y sus medios.
  if (tab.tab === "orders") {
    const [{ rows, total }, groups] = await Promise.all([
      getPaymentOrders({
        supplierId: supplier?.id,
        restaurantId: local,
        page: list.page - 1,
        size: list.size,
      }),
      getPaymentOrderSupplierCounts(local),
    ]);
    const saved = NOTICES[first(raw.aviso) ?? ""];
    return layout(
      groups,
      <>
        {saved ? <Notice status="ok">{saved}</Notice> : null}
        {filters}
        <section aria-label="Órdenes de pago" className={box}>
          <CardTitle className="tabular-nums">
            {total === 1 ? "1 orden de pago" : `${total.toLocaleString("es-AR")} órdenes de pago`}
          </CardTitle>
          {tabs}
          <DataTable
            caption="Órdenes de pago"
            scroll
            columns={orderColumns(here)}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState
                title={
                  supplier
                    ? "No hay órdenes de pago de ese proveedor."
                    : "Todavía no hay órdenes de pago."
                }
              />
            }
          />
          {total > 0 ? (
            <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
          ) : null}
        </section>
      </>,
    );
  }

  const [{ rows, total }, groups] = await Promise.all([
    getPaymentSchedule({
      tab: tab.tab,
      supplierId: supplier?.id,
      restaurantId: local,
      page: list.page - 1,
      size: list.size,
    }),
    // El panel cuenta con la misma pestaña y el mismo local, sin el proveedor (pgTAP 419).
    getPaymentSupplierCounts({ tab: tab.tab, restaurantId: local }),
  ]);
  const columns: DataColumn<ScheduleRow>[] = [
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "title",
      wrap: true,
      cell: (r) => <span className="font-medium text-ink">{r.supplier_name}</span>,
    },
    {
      key: "invoice",
      header: "Factura",
      mobile: "line",
      wrap: "narrow",
      cell: (r) => (
        <Link
          href={`/compras/facturas/${r.invoice_id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center text-primary tabular-nums underline-offset-4 hover:underline desk:min-h-0"
        >
          {invoiceLabel(r.invoice_class, r.point_of_sale, r.number)}
        </Link>
      ),
    },
    {
      key: "place",
      header: "Local",
      mobile: "hidden",
      wrap: "narrow",
      cell: (r) => r.restaurant_name,
    },
    {
      key: "due",
      header: "Vencimiento",
      mobile: "line",
      cell: (r) => (
        <span className="whitespace-nowrap tabular-nums">
          {shortDate(r.due_on)}
          {r.due_state !== "none" ? (
            <span className="block text-sm text-ink-muted">{daysLabel(r.days_left)}</span>
          ) : null}
        </span>
      ),
    },
    {
      key: "balance",
      header: tab.tab === "paid" ? "Total" : "Saldo",
      align: "right",
      mobile: "line",
      cell: (r) => (
        <span className="tabular-nums">
          {formatMoney(tab.tab === "paid" ? r.total_amount : r.balance_amount)}
        </span>
      ),
    },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (r) => (
        <Badge status={DUE_LABELS[r.due_state].status}>{DUE_LABELS[r.due_state].label}</Badge>
      ),
    },
  ];
  return layout(
    groups,
    <>
      {filters}
      <section aria-label="Pagos" className={box}>
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 factura" : `${total.toLocaleString("es-AR")} facturas`}
        </CardTitle>
        {tabs}
        <DataTable
          caption="Pagos"
          scroll
          columns={columns}
          rows={rows}
          rowKey={(r) => r.invoice_id}
          list={list}
          path={PATH}
          params={params}
          empty={
            <EmptyState
              title={
                tab.tab === "overdue"
                  ? "No hay facturas vencidas."
                  : tab.tab === "paid"
                    ? "Todavía no hay facturas pagadas."
                    : "No hay facturas por vencer."
              }
            />
          }
        />
        {total > 0 ? (
          <Pagination list={list} total={total} shown={rows.length} path={PATH} params={params} />
        ) : null}
      </section>
    </>,
  );
}

// Los mismos nombres que en el panel de pago.
const ORDER_METHOD_NAMES: Record<string, string> = {
  cash: ORDER_METHOD_LABELS.cash,
  transfer: ORDER_METHOD_LABELS.transfer,
  check: "Cheque",
  echeq: ORDER_METHOD_LABELS.echeq,
  card: ORDER_METHOD_LABELS.card,
  electronic_code: METHOD_LABELS.electronic_code,
};

function orderColumns(here: string): DataColumn<PaymentOrderRow>[] {
  return [
    {
      key: "number",
      header: "Orden",
      mobile: "title",
      cell: (r) => (
        <Link
          href={`/compras/pagos/ordenes/${r.id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center font-medium text-primary tabular-nums underline-offset-4 hover:underline desk:min-h-0"
        >
          {r.number}
        </Link>
      ),
    },
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "line",
      wrap: true,
      cell: (r) => <span className="text-ink">{r.supplier_name}</span>,
    },
    {
      key: "payer",
      header: "Paga",
      mobile: "hidden",
      wrap: "narrow",
      cell: (r) => r.payer_name ?? "—",
    },
    {
      key: "paid",
      header: "Fecha",
      mobile: "line",
      cell: (r) => <span className="tabular-nums">{shortDate(r.paid_on)}</span>,
    },
    {
      key: "methods",
      header: "Medios",
      mobile: "hidden",
      wrap: "narrow",
      cell: (r) => r.methods.map((m) => ORDER_METHOD_NAMES[m] ?? "—").join(", "),
    },
    {
      key: "total",
      header: "Total",
      align: "right",
      mobile: "line",
      cell: (r) => <span className="tabular-nums">{formatMoney(r.total_amount)}</span>,
    },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (r) =>
        r.status === "voided" ? (
          <Badge status="bad">Anulada</Badge>
        ) : (
          <Badge status="ok">Registrada</Badge>
        ),
    },
  ];
}

function cashColumns(canPay: boolean): DataColumn<CashRow>[] {
  return [
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "title",
      wrap: true,
      cell: (r) => <span className="font-medium text-ink">{r.supplier_name}</span>,
    },
    {
      key: "order",
      header: "Recepción",
      mobile: "line",
      cell: (r) =>
        r.purchase_order_id ? (
          <Link
            href={`/compras/ordenes/${r.purchase_order_id}?seccion=recepcion`}
            className="inline-flex min-h-touch items-center text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {r.order_number} · ver la recepción
          </Link>
        ) : (
          "Sin orden de compra"
        ),
    },
    {
      key: "place",
      header: "Local",
      mobile: "hidden",
      wrap: "narrow",
      cell: (r) => r.restaurant_name,
    },
    {
      key: "paid",
      header: "Pagado el",
      mobile: "line",
      cell: (r) => <span className="tabular-nums">{shortDate(r.paid_on)}</span>,
    },
    {
      key: "amount",
      header: "Importe",
      align: "right",
      mobile: "line",
      cell: (r) => <span className="tabular-nums">{formatMoney(r.payment_amount)}</span>,
    },
    {
      key: "action",
      header: "Acción",
      mobile: "status",
      cell: (r) =>
        canPay ? (
          <ActionModal
            label="Confirmar"
            accessibleName={`Confirmar el efectivo de ${r.supplier_name}`}
            icon="none"
            size="sm"
            title="Confirmar el efectivo"
            description="Queda registrado a cuenta del proveedor y se aplica solo a la factura de esa recepción cuando quede conforme."
          >
            <ActionForm action={confirmCashAction} schema="reason" submitLabel="Confirmar">
              <input type="hidden" name="paymentId" value={r.payment_id} />
              <FormInput
                id={`pg-efectivo-${r.payment_id}`}
                name="amount"
                label="Importe pagado"
                inputMode="decimal"
                placeholder={String(r.payment_amount).replace(".", ",")}
                hint="Vacío: el que se anotó al recibir."
              />
              <FormTextarea
                id={`pg-efectivo-motivo-${r.payment_id}`}
                name="reason"
                label="Motivo"
                hint="Queda en el historial."
                required
                maxLength={500}
              />
            </ActionForm>
          </ActionModal>
        ) : (
          <Badge status="warn">Para confirmar</Badge>
        ),
    },
  ];
}
