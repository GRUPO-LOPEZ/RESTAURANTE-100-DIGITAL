import Link from "next/link";
import { Suspense } from "react";
import { FileSpreadsheet } from "lucide-react";

import { AppShell, Loading } from "@/components/app-shell";
import { CreateModal } from "@/components/create-modal";
import { ReliabilityFilter } from "@/components/costs/reliability-filter";
import { NewSupplierForm } from "@/components/new-supplier-form";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Input, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { Tabs } from "@/components/ui/tabs";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { first, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import {
  CHANNEL_LABELS,
  daysLabel,
  daysLongLabel,
  formatCuit,
  paymentLabel,
  type Channel,
  type PaymentTerms,
} from "@/lib/suppliers";
import {
  SUPPLIER_SORT_KEYS,
  getPurchaseRubros,
  getSupplierList,
  type SupplierListRow,
} from "@/lib/suppliers-data";

// Proveedores (Fase 3, ADR-0050), listado tipo C: ¿a quién le compramos y en qué condiciones? Filtros en una línea que
// se aplican solos, pestañas Activos / Inactivos, tabla de ancho completo y 15 filas por página. La condición de pago
// aparece solo para quien la ve (la base no se la da al resto).
export default function ProveedoresPage({ searchParams }: PageProps<"/proveedores">) {
  return (
    <AppShell
      title="Proveedores"
      description="A quién le compramos: cómo se le pide, cuándo entrega, cómo factura y cómo se le paga."
      actions={
        <Suspense fallback={null}>
          <Actions />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Suppliers searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

async function Actions() {
  const menus = await getMenus();
  if (!menus.suppliersManage) return null;
  return (
    <div className="flex flex-wrap items-center gap-2">
      {/* La carga inicial, de muchos a la vez (ADR-0055). En la computadora: el celular es para consultar. */}
      <Button asChild variant="outline" className="hidden desk:inline-flex">
        <Link href="/proveedores/importar">
          <FileSpreadsheet aria-hidden="true" />
          Importar desde planilla
        </Link>
      </Button>
      <CreateModal
        href="/proveedores/nuevo"
        label="Nuevo proveedor"
        title="Nuevo proveedor"
        description="Se crea con código automático y te lleva a su ficha para completar días, canal, facturación y pago."
      >
        <NewSupplierForm />
      </CreateModal>
    </div>
  );
}

const PATH = "/proveedores";
const STATUS_TABS = [
  { value: undefined, label: "Activos" },
  { value: "inactivos", label: "Inactivos" },
] as const;
const CHANNELS = Object.keys(CHANNEL_LABELS) as Channel[];

async function Suppliers({
  searchParams,
}: {
  searchParams: PageProps<"/proveedores">["searchParams"];
}) {
  await requireMenu("suppliers");
  const raw = await searchParams;
  // El aviso de la importación se ve una vez: no viaja en los filtros, el orden ni las páginas.
  const params = Object.fromEntries(
    Object.entries(plainParams(raw)).filter(([k]) => k !== "aviso" && k !== "n"),
  );
  const list = parseList(raw, SUPPLIER_SORT_KEYS, "name");
  const menus = await getMenus();
  const inactive = first(raw.estado) === "inactivos";
  const channelRaw = first(raw.canal);
  const channel = CHANNELS.find((c) => c === channelRaw);
  // Los rubros los lee quien ve materias primas; el cocinero filtra por canal y busca.
  const rubros = menus.catalog ? await getPurchaseRubros() : [];
  const rubroId = uuidOrUndefined(first(raw.rubro));
  const rubro = rubros.find((r) => r.id === rubroId);
  const search = (first(raw.q) ?? "").trim().slice(0, 80);
  const { rows, total } = await getSupplierList({
    search: search || undefined,
    active: !inactive,
    categoryId: rubro?.id,
    channel,
    sort: SUPPLIER_SORT_KEYS.find((k) => k === list.sort) ?? "name",
    desc: list.dir === "desc",
    page: list.page - 1,
    size: list.size,
  });

  const remove = (key: string) => listHref(PATH, params, { [key]: undefined, pagina: undefined });
  const active = [
    search ? { label: `Buscar: «${search}»`, removeHref: remove("q") } : null,
    rubro ? { label: `Rubro: ${rubro.name}`, removeHref: remove("rubro") } : null,
    channel ? { label: `Canal: ${CHANNEL_LABELS[channel]}`, removeHref: remove("canal") } : null,
  ].filter((x): x is { label: string; removeHref: string } => x !== null);
  const here = listHref(PATH, params, {});

  const columns: DataColumn<SupplierListRow>[] = [
    {
      key: "name",
      header: "Proveedor",
      sortKey: "name",
      mobile: "title",
      cell: (row) => (
        <span className="flex flex-col">
          <Link
            href={`/proveedores/${row.id}?volver=${encodeURIComponent(here)}`}
            className="inline-flex min-h-touch items-center font-medium text-primary underline-offset-4 hover:underline desk:min-h-0"
          >
            {row.trade_name || row.name}
          </Link>
          <span className="text-sm text-ink-muted">
            {row.trade_name ? row.name : null}
            {row.trade_name ? " · " : null}
            <span className="whitespace-nowrap tabular-nums">{row.code}</span>
          </span>
        </span>
      ),
    },
    {
      key: "tax_id",
      header: "CUIT",
      mobile: "hidden",
      cell: (row) => (
        <span className="whitespace-nowrap tabular-nums">{formatCuit(row.tax_id) || "—"}</span>
      ),
    },
    ...(menus.catalog
      ? [
          {
            key: "categories",
            header: "Rubros",
            mobile: "line" as const,
            cell: (row: SupplierListRow) =>
              row.categories.length > 0 ? row.categories.join(", ") : "—",
          },
        ]
      : []),
    {
      key: "delivery",
      header: "Entrega",
      mobile: "line",
      cell: (row) => (
        <span className="whitespace-nowrap">
          <span aria-hidden="true">{daysLabel(row.delivery_days)}</span>
          <span className="sr-only">{daysLongLabel(row.delivery_days)}</span>
        </span>
      ),
    },
    {
      key: "channel",
      header: "Pedidos por",
      mobile: "hidden",
      cell: (row) => (row.po_channel ? CHANNEL_LABELS[row.po_channel as Channel] : "—"),
    },
    ...(menus.supplierPayment
      ? [
          {
            key: "payment",
            header: "Pago",
            mobile: "line" as const,
            cell: (row: SupplierListRow) =>
              paymentLabel(row.payment_terms as PaymentTerms | null, row.payment_days),
          },
        ]
      : []),
    {
      key: "status",
      header: "Estado",
      mobile: "status",
      cell: (row) =>
        row.is_active ? <Badge status="ok">Activo</Badge> : <Badge status="none">Inactivo</Badge>,
    },
  ];

  // Vuelta de la importación (ADR-0055): cuántos se crearon.
  const imported = first(raw.aviso) === "importados" ? Number(first(raw.n) ?? "") : NaN;

  return (
    <div className="flex flex-col gap-4">
      {Number.isInteger(imported) && imported > 0 ? (
        <Notice status="ok">
          {imported === 1 ? "Se creó 1 proveedor" : `Se crearon ${imported} proveedores`} desde la
          planilla. Completá en cada ficha las cuentas de pago y los números de cliente.
        </Notice>
      ) : null}
      <FilterBar label="Filtros de proveedores" active={active}>
        <Field id="prov-q" label="Buscar" className="w-full desk:w-72">
          <Input type="search" name="q" defaultValue={search} placeholder="Nombre, código o CUIT" />
        </Field>
        {rubros.length > 0 ? (
          <Field id="prov-rubro" label="Rubro" className="w-full desk:w-64">
            <Select name="rubro" defaultValue={rubro?.id ?? ""}>
              <option value="">Todos</option>
              {rubros.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </Select>
          </Field>
        ) : null}
      </FilterBar>
      {/* Pocas opciones: botones a la vista (ADR-0039 y ADR-0048), como la confiabilidad de Costos. */}
      <div className="flex flex-wrap items-center gap-2">
        <span id="prov-canal-etiqueta" aria-hidden="true" className="text-sm font-medium text-ink">
          Pedidos por
        </span>
        <ReliabilityFilter
          path={PATH}
          name="canal"
          label="Pedidos por"
          keep={Object.fromEntries(
            Object.entries(params).filter(([k]) => k !== "canal" && k !== "pagina"),
          )}
          options={[
            {
              value: "",
              label: "Todos",
              href: listHref(PATH, params, { canal: undefined, pagina: undefined }),
              current: !channel,
            },
            ...CHANNELS.map((c) => ({
              value: c,
              label: CHANNEL_LABELS[c],
              href: listHref(PATH, params, { canal: c, pagina: undefined }),
              current: channel === c,
            })),
          ]}
        />
      </div>
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1 ? "1 proveedor" : `${total.toLocaleString("es-AR")} proveedores`}
        </CardTitle>
        <Tabs
          label="Estado de los proveedores"
          items={STATUS_TABS.map((t) => ({
            href: listHref(PATH, params, { estado: t.value, pagina: undefined }),
            label: t.label,
            current: (t.value === "inactivos") === inactive,
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
            caption="Proveedores"
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState
                title={
                  active.length > 0
                    ? "No hay proveedores con esos filtros."
                    : inactive
                      ? "No hay proveedores inactivos."
                      : "Todavía no hay proveedores."
                }
              >
                {active.length > 0
                  ? "Probá con otro nombre, CUIT, rubro o canal."
                  : inactive
                    ? "Los que se desactivan quedan acá, con su ficha y su historia."
                    : menus.suppliersManage
                      ? "Cargá el primero con «Nuevo proveedor»."
                      : "Los carga Compras."}
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
