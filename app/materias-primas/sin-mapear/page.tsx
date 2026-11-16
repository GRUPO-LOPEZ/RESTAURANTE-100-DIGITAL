import Link from "next/link";
import { Suspense } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { MapArticle } from "@/components/map-article";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field, Select } from "@/components/ui/field";
import { FilterBar } from "@/components/ui/filter-bar";
import { Notice } from "@/components/ui/notice";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { getSuppliers, getUnits } from "@/lib/catalog";
import { first, formatDate, uuidOrUndefined } from "@/lib/data";
import { listHref, parseList, plainParams } from "@/lib/list-params";
import { FOUND_IN_LABELS } from "@/lib/price-lists";
import { getUnmappedArticles, type UnmappedArticle } from "@/lib/price-lists-data";

// Cola de mapeo (Fase 3, ADR-0052), listado tipo C: ¿qué artículos de proveedor no reconoce el sistema? El chef dice una
// sola vez a qué materia prima corresponde cada uno (con su envase), que es el mismo que otro producto, o lo descarta.
// Después se reconoce solo. Compras ve la cola sin poder resolverla.
export default function SinMapearPage({ searchParams }: PageProps<"/materias-primas/sin-mapear">) {
  return (
    <AppShell
      title="Artículos sin mapear"
      description="Lo que mandaron los proveedores y todavía no sabemos qué es. Se resuelve una sola vez."
      back={
        <BackLink href="/materias-primas" label="Volver a materias primas">
          Materias primas
        </BackLink>
      }
    >
      <Suspense fallback={<Loading />}>
        <Queue searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const PATH = "/materias-primas/sin-mapear";
const NOTICES: Record<string, string> = {
  resuelto: "Listo: el artículo ya es un producto de compra. La próxima vez se reconoce solo.",
  vinculado: "Listo: quedó vinculado. El nombre nuevo se reconoce solo.",
  descartado: "Artículo descartado.",
};

async function Queue({
  searchParams,
}: {
  searchParams: PageProps<"/materias-primas/sin-mapear">["searchParams"];
}) {
  const menus = await getMenus();
  // La ven y la resuelven quienes tienen catalog.map_articles en algún alcance (ADR-0052); Compras la ve. El resto
  // vuelve al inicio.
  await requireMenu("unmappedQueue");
  const raw = await searchParams;
  const params = plainParams(raw);
  const list = parseList(raw, [], null);
  const [suppliers, units] = await Promise.all([getSuppliers(), getUnits()]);
  const supplierId = uuidOrUndefined(first(raw.proveedor));
  const supplier = suppliers.find((s) => s.id === supplierId);
  const { rows, total } = await getUnmappedArticles({
    supplierId: supplier?.id,
    page: list.page - 1,
    size: list.size,
  });
  // Cómo puede venir un producto: los envases y las unidades de peso, volumen o unidad.
  // Primero los envases (bolsa, caja…): es lo más común en una lista.
  const packageUnits = [
    ...units.filter((u) => u.dimension === "package"),
    ...units.filter((u) => u.dimension !== "package"),
  ].map((u) => ({ code: u.code, name: u.name }));

  const active = supplier
    ? [
        {
          label: `Proveedor: ${supplier.name}`,
          removeHref: listHref(PATH, params, { proveedor: undefined, pagina: undefined }),
        },
      ]
    : [];

  const columns: DataColumn<UnmappedArticle>[] = [
    {
      key: "name",
      header: "Artículo (como vino)",
      mobile: "title",
      cell: (a) => (
        <span className="flex flex-col">
          <span className="font-medium text-ink">{a.rawName}</span>
          {a.packageHint ? <span className="text-sm text-ink-muted">{a.packageHint}</span> : null}
        </span>
      ),
    },
    {
      key: "supplier",
      header: "Proveedor",
      mobile: "line",
      cell: (a) => a.supplierName,
    },
    {
      key: "sku",
      header: "Código",
      mobile: "hidden",
      cell: (a) => <span className="tabular-nums">{a.sku ?? "—"}</span>,
    },
    {
      key: "found",
      header: "Apareció en",
      mobile: "line",
      cell: (a) => (
        <span>
          {FOUND_IN_LABELS[a.foundIn] ?? a.foundIn}
          <span className="text-ink-muted tabular-nums"> · {formatDate(a.createdAt)}</span>
        </span>
      ),
    },
    ...(menus.mapArticles
      ? [
          {
            key: "action",
            header: "Acción",
            mobile: "action" as const,
            cell: (a: UnmappedArticle) => <MapArticle article={a} packageUnits={packageUnits} />,
          },
        ]
      : []),
  ];

  const notice = NOTICES[first(raw.aviso) ?? ""];
  return (
    <div className="flex flex-col gap-4">
      {notice ? <Notice status="ok">{notice}</Notice> : null}
      <FilterBar label="Filtros de la cola" active={active}>
        <Field id="sm-proveedor" label="Proveedor" className="w-full desk:w-72">
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
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {total === 1
            ? "1 artículo sin mapear"
            : `${total.toLocaleString("es-AR")} artículos sin mapear`}
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
            caption="Artículos sin mapear"
            columns={columns}
            rows={rows}
            rowKey={(r) => r.id}
            list={list}
            path={PATH}
            params={params}
            empty={
              <EmptyState
                title={
                  supplier
                    ? "Ese proveedor no tiene artículos sin mapear."
                    : "No hay artículos sin mapear."
                }
              >
                Todo lo que mandaron los proveedores ya se reconoce.
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
