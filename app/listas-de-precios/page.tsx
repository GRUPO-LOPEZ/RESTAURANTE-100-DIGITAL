import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { ReliabilityFilter } from "@/components/costs/reliability-filter";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getSuppliers } from "@/lib/catalog";
import { first, formatDate, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { PRICE_LIST_STATUS, STATUS_FILTERS, isStatusFilter, shownStatus } from "@/lib/price-lists";
import { getPriceLists, type PriceListRow } from "@/lib/price-lists-data";

// Listas de precios (Fase 3, ADR-0052), listado tipo C: ¿qué listas mandaron los proveedores y cuál vale? Filtros que se
// aplican solos (proveedor y estado como botones), tabla de ancho completo y 15 filas por página. «Vencida» la calcula
// la base con la frecuencia de cada proveedor. Los precios de lista nunca son costos.
export default function ListasDePreciosPage({ searchParams }: PageProps<"/listas-de-precios">) {
  return (
    <AppShell
      title="Listas de precios"
      description="Lo que mandó cada proveedor, cuál vale hoy y qué artículos esperan en la cola de mapeo."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Lists searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  const menus = await getMenus();
  if (!menus.priceListsManage) return null;
  return (
    <Link href="/listas-de-precios/nueva" className={buttonVariants()}>
      + Cargar lista
    </Link>
  );
}

const PATH = "/listas-de-precios";

async function Lists({
  searchParams,
}: {
  searchParams: PageProps<"/listas-de-precios">["searchParams"];
}) {
  await requireMenu("priceLists");
  const raw = await searchParams;
  const params = plainParams(raw);
  const list = parseList(raw, [], null);
  const estadoRaw = first(raw.estado);
  const status = isStatusFilter(estadoRaw) ? estadoRaw : undefined;
  const suppliers = await getSuppliers();
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  const supplier = suppliers.find((s) => s.id === supplierId);
  const { rows, total } = await getPriceLists({
    supplierId: supplier?.id,
    status,
    page: list.page - 1,
    size: list.size,
  });

  const remove = (key: string) => listHref(PATH, params, { [key]: undefined, pagina: undefined });
  const active = [
    supplier ? { label: `Proveedor: ${supplier.name}`, removeHref: remove("proveedor") } : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);
  const here = listHref(PATH, params, {});

  const columns: DataColumn<PriceListRow>[] = [
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "title",
      cell: (row) => (
        <Link
          href={`/listas-de-precios/${row.id}?volver=${encodeURIComponent(here)}`}
          className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
        >
          {row.supplier_name}
        </Link>
      ),
    },
    {
      key: "received",
      header: "Recibida",
      mobile: "line",
      cell: (row) => <span className="tabular-nums">{formatDate(row.received_on)}</span>,
    },
    {
      key: "valid",
      header: "Vale desde",
      mobile: "line",
      cell: (row) => <span className="tabular-nums">{formatDate(row.valid_from)}</span>,
    },
    {
      key: "items",
      header: "Artículos",
      align: "right",
      mobile: "line",
      cell: (row) => (
        <span className="tabular-nums">
          {row.items.toLocaleString("es-AR")}
          {row.queued > 0 ? (
            <>
              {" · "}
              <Link
                href={`/materias-primas/sin-mapear?proveedor=${row.supplier_id}`}
                className="text-primary underline-offset-4 hover:underline"
              >
                {row.queued} en la cola
              </Link>
            </>
          ) : null}
        </span>
      ),
    },
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (row) => {
        const s = PRICE_LIST_STATUS[shownStatus(row.status, row.expired)];
        return <Badge status={s.status}>{s.label}</Badge>;
      },
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      <FilterBar label="Filtros de listas de precios" active={active}>
        <Field id="lp-proveedor" label="Proveedor" className="w-full desk:w-72">
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
      {/* Pocas opciones: botones a la vista (ADR-0039 y ADR-0048). */}
      <div className="flex flex-wrap items-center gap-2">
        <span aria-hidden="true" className="text-sm font-medium text-ink">
          Estado
        </span>
        <ReliabilityFilter
          path={PATH}
          name="estado"
          label="Estado"
          keep={Object.fromEntries(
            Object.entries(params).filter(([k]) => k !== "estado" && k !== "pagina"),
          )}
          options={[
            {
              value: "",
              label: "Todas",
              href: listHref(PATH, params, { estado: undefined, pagina: undefined }),
              current: !status,
            },
            ...STATUS_FILTERS.map((f) => ({
              value: f.value,
              label: f.label,
              href: listHref(PATH, params, { estado: f.value, pagina: undefined }),
              current: status === f.value,
            })),
          ]}
        />
      </div>
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 lista" : `${total.toLocaleString("es-AR")} listas`}
        </CardTitle>
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
            caption="Listas de precios"
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState
                title={
                  active.length > 0 || status
                    ? "No hay listas con esos filtros."
                    : "Todavía no hay listas de precios."
                }
              >
                {active.length > 0 || status
                  ? "Probá con otro proveedor o estado."
                  : "Las carga Compras con «Cargar lista», con el archivo que mandó el proveedor."}
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
