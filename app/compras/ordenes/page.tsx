import Link from "next/link";
import { Plus, Truck } from "lucide-react";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { ReliabilityFilter } from "@/components/costs/reliability-filter";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { GroupLayout, GroupPanel } from "@/components/ui/group-panel";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, formatDate, getActiveRestaurantId, uuidOrUndefined } from "@/lib/data";
import { sumCounts } from "@/lib/group-counts";
import { getOrderSupplierCounts } from "@/lib/group-counts-data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { PO_STATUS, PO_TABS } from "@/lib/purchase-orders";
import { getOrderNotices, getOrders, type OrderRow } from "@/lib/purchase-orders-data";
import { markOrderNoticesReadAction } from "@/app/compras/ordenes/actions";
import { ActionForm } from "@/components/action-form";

// Órdenes de compra (Fase 3, Prompt 3, ADR-0053), listado tipo C: ¿qué pedí, en qué estado está y hubo novedades? Las
// del local elegido arriba (o de todos mis locales), pestañas por estado, «Mías» como botón, filtro de proveedor y 15
// filas por página. Sin precios. Con los criterios de Soy (ADR-0068): en una pantalla, los proveedores con su cantidad
// en el panel de la izquierda y la tabla con su propio scroll.
export default function OrdenesPage({ searchParams }: PageProps<"/compras/ordenes">) {
  return (
    <AppShell
      title="Órdenes de compra"
      fill
      description="Lo que cada local le pidió a cada proveedor, en qué estado está y si hubo novedades."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Orders searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  const menus = await getMenus();
  if (!menus.ordersCreate) return null;
  return (
    <Link href="/compras/ordenes/nueva" className={buttonVariants()}>
      <Plus aria-hidden="true" />
      Nueva orden
    </Link>
  );
}

const PATH = "/compras/ordenes";

async function Orders({
  searchParams,
}: {
  searchParams: PageProps<"/compras/ordenes">["searchParams"];
}) {
  const session = await requireMenu("orders");
  const raw = await searchParams;
  const params = plainParams(raw);
  const list = parseList(raw, [], null);
  const tab = PO_TABS.find((t) => t.value === first(raw.estado)) ?? PO_TABS[0];
  const mine = first(raw.mias) === "si";
  // El local de la dirección o el elegido arriba (el selector es único y global); sin ninguno, todos los que ve.
  const local =
    uuidOrUndefined(first(raw.local)) ??
    (await getActiveRestaurantId(session.user_id)) ??
    undefined;
  const [menus, suppliers] = await Promise.all([getMenus(), getSuppliers()]);
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  const supplier = suppliers.find((s) => s.id === supplierId);
  const [{ rows, total }, groups] = await Promise.all([
    getOrders({
      status: tab.filter,
      supplierId: supplier?.id,
      restaurantId: local,
      mine,
      page: list.page - 1,
      size: list.size,
    }),
    // El panel cuenta con los mismos filtros, menos el proveedor (pgTAP 419).
    getOrderSupplierCounts({ status: tab.filter, restaurantId: local, mine }),
  ]);

  const active = supplier
    ? [
        {
          label: `Proveedor: ${supplier.name}`,
          removeHref: listHref(PATH, params, { proveedor: undefined, pagina: undefined }),
        },
      ]
    : [];
  const here = listHref(PATH, params, {});

  const columns: DataColumn<OrderRow>[] = [
    {
      key: "number",
      header: "Número",
      mobile: "title",
      cell: (o) => (
        <Link
          href={`/compras/ordenes/${o.id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center font-medium text-primary tabular-nums underline-offset-4 hover:underline desk:min-h-0"
        >
          {o.number}
        </Link>
      ),
    },
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "line",
      wrap: true,
      cell: (o) => o.supplier_name,
    },
    {
      key: "place",
      header: "Local",
      mobile: "hidden",
      wrap: "narrow",
      cell: (o) => o.restaurant_name,
    },
    {
      key: "created",
      header: "Pedida",
      mobile: "hidden",
      cell: (o) => <span className="tabular-nums">{formatDate(o.created_at)}</span>,
    },
    {
      key: "expected",
      header: "Entrega esperada",
      mobile: "line",
      cell: (o) => <span className="tabular-nums">{formatDate(o.expected_delivery_on)}</span>,
    },
    {
      key: "news",
      header: "Novedades",
      align: "right",
      mobile: "hidden",
      cell: (o) => <span className="tabular-nums">{o.news > 0 ? o.news : "—"}</span>,
    },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (o) => <Badge status={PO_STATUS[o.status].status}>{PO_STATUS[o.status].label}</Badge>,
    },
  ];

  return (
    <GroupLayout
      panel={
        <GroupPanel
          label="Proveedores"
          icon={Truck}
          unit={{ one: "orden", many: "órdenes" }}
          allLabel="Todos los proveedores"
          allCount={sumCounts(groups)}
          items={groups}
          selected={supplier ? { id: supplier.id, name: supplier.name } : undefined}
          hrefFor={(id) => listHref(PATH, params, { proveedor: id, pagina: undefined })}
        />
      }
    >
      <Suspense fallback={null}>
        <OrderNotices />
      </Suspense>
      {/* En la computadora, el proveedor se elige en el panel; en el celular, acá (la clave lo rehace al cambiar). */}
      <FilterBar label="Filtros de órdenes de compra" active={active}>
        <Field id="oc-proveedor" label="Proveedor" className="w-full desk:hidden">
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
      {menus.ordersCreate ? (
        <div className="flex flex-wrap items-center gap-2">
          <span aria-hidden="true" className="text-sm font-medium text-ink">
            Quién pidió
          </span>
          <ReliabilityFilter
            path={PATH}
            name="mias"
            label="Quién pidió"
            keep={Object.fromEntries(
              Object.entries(params).filter(([k]) => k !== "mias" && k !== "pagina"),
            )}
            options={[
              {
                value: "",
                label: "Todas",
                href: listHref(PATH, params, { mias: undefined, pagina: undefined }),
                current: !mine,
              },
              {
                value: "si",
                label: "Mías",
                href: listHref(PATH, params, { mias: "si", pagina: undefined }),
                current: mine,
              },
            ]}
          />
        </div>
      ) : null}
      <section
        aria-label="Órdenes de compra"
        className="flex flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0 desk:flex-[1_1_0px]"
      >
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 orden" : `${total.toLocaleString("es-AR")} órdenes`}
        </CardTitle>
        <Tabs
          label="Estado de las órdenes"
          items={PO_TABS.map((t) => ({
            href: listHref(PATH, params, { estado: t.value, pagina: undefined }),
            label: t.label,
            current: t.value === tab.value,
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
            caption="Órdenes de compra"
            scroll
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState title="No hay órdenes con esos filtros.">
                {menus.ordersCreate
                  ? "Hacé la primera con «Nueva orden»."
                  : "Las hacen los locales."}
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

// Novedades sin leer de mis órdenes: el cocinero no tiene la bandeja de Aprobaciones, así que las ve acá.
async function OrderNotices() {
  const all = await getOrderNotices();
  if (all.length === 0) return null;
  // Se muestran las 3 más nuevas (la pantalla no crece con los datos, ADR-0046); el título dice cuántas hay y «Marcar
  // como leídas» marca las que se ven, y aparecen las siguientes.
  const notices = all.slice(0, 3);
  const more = all.length > 10;
  return (
    <Card className="flex flex-col gap-3">
      <CardTitle>
        {all.length === 1
          ? "1 novedad de tus órdenes"
          : `${more ? "Más de 10" : all.length} novedades de tus órdenes`}
        {all.length > notices.length ? (
          <span className="text-sm font-normal text-ink-muted"> · las 3 más nuevas</span>
        ) : null}
      </CardTitle>
      <ul className="flex flex-col gap-2">
        {notices.map((n) => (
          <li key={n.id} className="text-base text-ink">
            {n.link ? (
              <Link
                href={n.link}
                className="font-medium text-primary underline-offset-4 hover:underline"
              >
                {n.title}
              </Link>
            ) : (
              <span className="font-medium">{n.title}</span>
            )}
            {n.body ? <span className="text-ink-muted"> · {n.body}</span> : null}
            <span className="text-sm text-ink-muted tabular-nums">
              {" "}
              · {formatDate(n.createdAt)}
            </span>
          </li>
        ))}
      </ul>
      <ActionForm
        action={markOrderNoticesReadAction}
        submitLabel="Marcar como leídas"
        variant="outline"
      >
        {notices.map((n) => (
          <input key={n.id} type="hidden" name="noticeId" value={n.id} />
        ))}
      </ActionForm>
    </Card>
  );
}
