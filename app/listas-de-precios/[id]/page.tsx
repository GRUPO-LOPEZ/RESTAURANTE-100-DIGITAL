import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { acceptPriceListAction, attachFileAction } from "@/app/listas-de-precios/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { Badge } from "@/components/ui/badge";
import { Card, CardTitle } from "@/components/ui/card";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { FormInput, FormTextarea } from "@/components/ui/form";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { Pagination } from "@/components/ui/pagination";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate } from "@/lib/data";
import { parseList, plainParams } from "@/lib/list-params";
import { PRICE_LIST_STATUS, changeLabel, formatMoney, shownStatus } from "@/lib/price-lists";
import { getPriceListDetail, type PriceListItem } from "@/lib/price-lists-data";

// Detalle de una lista de precios (ADR-0052): sus artículos con el neto (lista menos las dos bonificaciones y la
// bonificación en pesos) y la variación contra la lista aceptada anterior del mismo proveedor. Compras la acepta con
// motivo: la anterior queda reemplazada. Lo que el sistema no reconoció dice «En la cola de mapeo».
export default function ListaDePreciosPage({
  params,
  searchParams,
}: PageProps<"/listas-de-precios/[id]">) {
  return (
    <AppShell
      title="Lista de precios"
      heading={
        <Suspense fallback="Lista de precios">
          <Heading params={params} />
        </Suspense>
      }
      back={
        <Suspense fallback={null}>
          <Back searchParams={searchParams} />
        </Suspense>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <Accept params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Detail params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const byId = cache(getPriceListDetail);

async function load(params: PageProps<"/listas-de-precios/[id]">["params"]) {
  await requireMenu("priceLists");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return byId(id);
}

async function Heading({ params }: { params: PageProps<"/listas-de-precios/[id]">["params"] }) {
  const l = await load(params);
  return l ? `Lista de ${l.supplierName}` : "Lista de precios";
}

// Volver a donde vino: el listado (con sus filtros) o la ficha del proveedor.
function backTarget(volver: string | undefined): { href: string; label: string } {
  if (volver && /^\/proveedores\/[0-9a-f-]{36}$/.test(volver))
    return { href: volver, label: "Proveedor" };
  if (volver && /^\/listas-de-precios(\?|$)/.test(volver))
    return { href: volver, label: "Listas de precios" };
  return { href: "/listas-de-precios", label: "Listas de precios" };
}

async function Back({
  searchParams,
}: {
  searchParams: PageProps<"/listas-de-precios/[id]">["searchParams"];
}) {
  const query = await searchParams;
  const target = backTarget(first(query.volver));
  return (
    <BackLink href={target.href} label={`Volver a ${target.label.toLowerCase()}`}>
      {target.label}
    </BackLink>
  );
}

async function Meta({ params }: { params: PageProps<"/listas-de-precios/[id]">["params"] }) {
  const l = await load(params);
  if (!l) return null;
  const s = PRICE_LIST_STATUS[shownStatus(l.status, l.expired)];
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        Recibida el {formatDate(l.receivedOn)} · Vale desde el {formatDate(l.validFrom)}
      </span>
      <Badge status={s.status}>{s.label}</Badge>
    </>
  );
}

async function Accept({ params }: { params: PageProps<"/listas-de-precios/[id]">["params"] }) {
  const [l, menus] = await Promise.all([load(params), getMenus()]);
  if (!l || !menus.priceListsManage || l.status !== "received") return null;
  return (
    <ActionModal
      label="Aceptar"
      icon="none"
      title="Aceptar la lista"
      description="Pasa a ser la vigente del proveedor y la anterior queda como reemplazada. No cambia ningún costo."
    >
      <ActionForm action={acceptPriceListAction} schema="reason" submitLabel="Aceptar la lista">
        <input type="hidden" name="priceListId" value={l.id} />
        <input type="hidden" name="supplierId" value={l.supplierId} />
        <FormTextarea
          id="lp-aceptar-motivo"
          name="reason"
          label="Motivo"
          hint="Queda en el historial."
          required
          maxLength={500}
        />
      </ActionForm>
    </ActionModal>
  );
}

const NOTICES: Record<string, string> = {
  aceptada: "Lista aceptada.",
  reemplazo: "Lista aceptada. La anterior quedó como reemplazada.",
};

async function Detail({
  params,
  searchParams,
}: {
  params: PageProps<"/listas-de-precios/[id]">["params"];
  searchParams: PageProps<"/listas-de-precios/[id]">["searchParams"];
}) {
  const [l, raw, menus] = await Promise.all([load(params), searchParams, getMenus()]);
  if (!l) notFound();
  const canAttach = menus.priceListsManage && l.status === "received";
  const list = parseList(raw, [], null);
  const qp = plainParams(raw);
  const path = `/listas-de-precios/${l.id}`;
  const queued = l.items.filter((i) => !i.mapped).length;
  const notice = NOTICES[first(raw.aviso) ?? ""];
  const compared = l.items.filter((i) => i.changePct !== null);
  const avg =
    compared.length > 0
      ? compared.reduce((sum, i) => sum + (i.changePct ?? 0), 0) / compared.length
      : null;
  const rows = l.items.slice((list.page - 1) * list.size, list.page * list.size);

  const columns: DataColumn<PriceListItem>[] = [
    {
      key: "name",
      header: "Artículo",
      mobile: "title",
      cell: (i) => (
        <span className="flex flex-col">
          <span className="font-medium text-ink">{i.rawName}</span>
          {i.sku ? <span className="text-sm text-ink-muted tabular-nums">{i.sku}</span> : null}
        </span>
      ),
    },
    {
      key: "list",
      header: "Lista",
      align: "right",
      mobile: "line",
      cell: (i) => <span className="tabular-nums">{formatMoney(i.listPrice)}</span>,
    },
    {
      key: "bonus",
      header: "Bonificaciones",
      align: "right",
      mobile: "hidden",
      cell: (i) => {
        const parts = [
          i.bonus1Pct > 0 ? `${i.bonus1Pct.toLocaleString("es-AR")} %` : null,
          i.bonus2Pct > 0 ? `${i.bonus2Pct.toLocaleString("es-AR")} %` : null,
          i.bonusPerUnit > 0 ? formatMoney(i.bonusPerUnit) : null,
        ].filter(Boolean);
        return <span className="tabular-nums">{parts.length > 0 ? parts.join(" + ") : "—"}</span>;
      },
    },
    {
      key: "net",
      header: "Neto",
      align: "right",
      mobile: "line",
      cell: (i) => <span className="font-medium tabular-nums">{formatMoney(i.net)}</span>,
    },
    {
      key: "vat",
      header: "IVA",
      align: "right",
      mobile: "hidden",
      cell: (i) => <span className="tabular-nums">{i.vatRate.toLocaleString("es-AR")} %</span>,
    },
    {
      key: "change",
      header: "Contra la anterior",
      align: "right",
      mobile: "status",
      cell: (i) =>
        i.mapped ? (
          <span className="tabular-nums">{changeLabel(i.changePct)}</span>
        ) : (
          <Badge status="review">En la cola de mapeo</Badge>
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-4">
      {notice ? <Notice status="ok">{notice}</Notice> : null}
      <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
        <Metric
          compact
          label="Artículos"
          value={l.items.length}
          emptyLabel="Sin artículos"
          status="none"
          statusLabel="Cargados"
        />
        <Metric
          compact
          label="En la cola de mapeo"
          value={queued}
          total={l.items.length}
          emptyLabel="Sin artículos"
          status={queued === 0 ? "ok" : "warn"}
          statusLabel={queued === 0 ? "Todos reconocidos" : "Esperan al chef"}
          action={
            queued > 0 ? (
              <Link
                href="/materias-primas/sin-mapear"
                className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
              >
                Ver la cola
              </Link>
            ) : undefined
          }
        />
        <Metric
          compact
          label="Variación promedio"
          value={avg === null ? null : changeLabel(Math.round(avg * 100) / 100)}
          missingReason="Sin lista anterior para comparar."
          emptyLabel="Sin datos"
          status="none"
          statusLabel={
            compared.length === 1
              ? "1 artículo comparado"
              : `${compared.length} artículos comparados`
          }
        />
        <Metric
          compact
          label="Archivo"
          value={l.attachments.length > 0 ? `${l.attachments.length}` : null}
          unit={l.attachments.length === 1 ? "archivo" : "archivos"}
          missingReason="Sin archivo adjunto."
          emptyLabel="Sin datos"
          status="none"
          statusLabel="Adjunto"
          action={
            l.attachments[0]?.url ? (
              <a
                href={l.attachments[0].url}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
              >
                Ver el archivo
                <span className="sr-only"> (se abre en otra pestaña)</span>
              </a>
            ) : canAttach ? (
              <ActionModal
                label="Adjuntar archivo"
                icon="none"
                title="Adjuntar el archivo de la lista"
                description="Foto o PDF, hasta 3,5 MB. Solo mientras la lista está sin aceptar."
              >
                <ActionForm action={attachFileAction} schema="reason" submitLabel="Adjuntar">
                  <input type="hidden" name="priceListId" value={l.id} />
                  <FormInput
                    id="lp-adjuntar-archivo"
                    name="file"
                    type="file"
                    label="Archivo"
                    accept="image/jpeg,image/png,image/webp,application/pdf"
                  />
                  <FormTextarea
                    id="lp-adjuntar-motivo"
                    name="reason"
                    label="Motivo"
                    hint="Queda en el historial."
                    required
                    maxLength={500}
                  />
                </ActionForm>
              </ActionModal>
            ) : undefined
          }
        />
      </div>
      <Card className="flex flex-col gap-4">
        <CardTitle className="tabular-nums">
          {l.items.length === 1
            ? "1 artículo"
            : `${l.items.length.toLocaleString("es-AR")} artículos`}
        </CardTitle>
        <DataTable
          caption="Artículos de la lista"
          columns={columns}
          rows={rows}
          rowKey={(r) => r.id}
          list={list}
          path={path}
          params={qp}
          empty={<EmptyState title="Esta lista no tiene artículos." />}
        />
        {l.items.length > 0 ? (
          <Pagination
            list={list}
            total={l.items.length}
            shown={rows.length}
            path={path}
            params={qp}
          />
        ) : null}
      </Card>
    </div>
  );
}
