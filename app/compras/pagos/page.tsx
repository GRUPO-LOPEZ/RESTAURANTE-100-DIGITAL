import Link from "next/link";
import { Suspense } from "react";

import { confirmCashAction } from "@/app/compras/pagos/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { RegisterPayment } from "@/components/register-payment";
import { Badge } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
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
import { invoiceLabel, shortDate } from "@/lib/invoices";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { formatMoney } from "@/lib/money";
import { DUE_LABELS, PAYMENT_TABS, daysLabel } from "@/lib/payments";
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
// recibir que falta confirmar. «Registrar pago» abre el panel con las facturas del proveedor.
export default function PagosPage({ searchParams }: PageProps<"/compras/pagos">) {
  return (
    <AppShell
      title="Pagos"
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
  const filters = (
    <FilterBar label="Filtros de pagos" active={active}>
      <Field id="pg-proveedor" label="Proveedor" className="w-full desk:w-72">
        <Select name="proveedor" defaultValue={supplier?.id ?? ""}>
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

  // «Para confirmar»: el efectivo pagado al recibir (decisión 7 de Soy).
  if (tab.tab === "cash") {
    const cash = (await getCashToConfirm(local)).filter(
      (c) => !supplier || c.supplier_id === supplier.id,
    );
    const saved = NOTICES[first(raw.aviso) ?? ""];
    return (
      <div className="flex flex-col gap-4">
        {saved ? <Notice status="ok">{saved}</Notice> : null}
        {filters}
        <Card className="flex flex-col gap-4">
          <CardTitle className="tabular-nums">
            {cash.length === 1 ? "1 pago para confirmar" : `${cash.length} pagos para confirmar`}
          </CardTitle>
          {tabs}
          <DataTable
            caption="Efectivo para confirmar"
            columns={cashColumns(menus.pay)}
            rows={cash}
            rowKey={(r) => r.payment_id}
            empty={<EmptyState title="No hay efectivo para confirmar." />}
          />
        </Card>
      </div>
    );
  }

  const { rows, total } = await getPaymentSchedule({
    tab: tab.tab,
    supplierId: supplier?.id,
    restaurantId: local,
    page: list.page - 1,
    size: list.size,
  });
  const columns: DataColumn<ScheduleRow>[] = [
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "title",
      cell: (r) => <span className="font-medium text-ink">{r.supplier_name}</span>,
    },
    {
      key: "invoice",
      header: "Factura",
      mobile: "line",
      cell: (r) => (
        <Link
          href={`/compras/facturas/${r.invoice_id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center whitespace-nowrap text-primary tabular-nums underline-offset-4 hover:underline desk:min-h-0"
        >
          {invoiceLabel(r.invoice_class, r.point_of_sale, r.number)}
        </Link>
      ),
    },
    { key: "place", header: "Local", mobile: "hidden", cell: (r) => r.restaurant_name },
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
  return (
    <div className="flex flex-col gap-4">
      {filters}
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 factura" : `${total.toLocaleString("es-AR")} facturas`}
        </CardTitle>
        {tabs}
        <DataTable
          caption="Pagos"
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
      </Card>
    </div>
  );
}

function cashColumns(canPay: boolean): DataColumn<CashRow>[] {
  return [
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "title",
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
    { key: "place", header: "Local", mobile: "hidden", cell: (r) => r.restaurant_name },
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
