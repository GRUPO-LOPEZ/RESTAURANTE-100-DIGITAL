import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import {
  acceptPriceListAction,
  attachFileAction,
  voidPriceListAction,
} from "@/app/listas-de-precios/actions";
import { ActionForm } from "@/components/action-form";
import { ActionModal } from "@/components/action-modal";
import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { DataTable, type DataColumn } from "@/components/ui/data-table";
import { Field } from "@/components/ui/field";
import { FileUpload } from "@/components/ui/file-upload";
import { FormTextarea } from "@/components/ui/form";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { EmptyState } from "@/components/ui/states";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate, formatDateTime } from "@/lib/data";
import {
  PRICE_LIST_STATUS,
  checkBadge,
  formatMoney,
  perUseLabel,
  shownStatus,
} from "@/lib/price-lists";
import { getPriceListDetail, type PriceListItem } from "@/lib/price-lists-data";

// Ficha de una lista de precios (ADR-0052; controles, versiones y anulación, ADR-0071), sin scroll de página: la
// versión y el estado arriba, 4 indicadores (artículos, subas sobre el umbral de Dirección, precios para revisar y sin
// reconocer) y la tabla con su propio scroll, con el neto, el precio por unidad de uso y el control de cada renglón.
// Acciones en fila: el archivo original, las versiones, Aceptar (pide confirmar los «Revisar»), Corregir (versión
// nueva con motivo) y Anular (con motivo, sin borrar).
type Props = PageProps<"/listas-de-precios/[id]">;

export default function ListaDePreciosPage({ params, searchParams }: Props) {
  return (
    <AppShell
      title="Lista de precios"
      fill
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
          <Actions params={params} />
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

async function load(params: Props["params"]) {
  await requireMenu("priceLists");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return byId(id);
}

async function Heading({ params }: { params: Props["params"] }) {
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

async function Back({ searchParams }: { searchParams: Props["searchParams"] }) {
  const query = await searchParams;
  const target = backTarget(first(query.volver));
  return (
    <BackLink href={target.href} label={`Volver a ${target.label.toLowerCase()}`}>
      {target.label}
    </BackLink>
  );
}

async function Meta({ params }: { params: Props["params"] }) {
  const l = await load(params);
  if (!l) return null;
  const s = PRICE_LIST_STATUS[shownStatus(l.status, l.expired)];
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        {[`Versión ${l.version}`, `vale desde el ${formatDate(l.validFrom)}`]
          .filter(Boolean)
          .join(" · ")}
      </span>
      <Badge status={s.status}>{s.label}</Badge>
    </>
  );
}

async function Actions({ params }: { params: Props["params"] }) {
  const [l, menus] = await Promise.all([load(params), getMenus()]);
  if (!l) return null;
  const manage = menus.priceListsManage;
  const review = l.items.filter((i) => i.review).length;
  const original = l.attachments.find((a) => a.url);
  return (
    <div className="flex flex-wrap items-center gap-2 desk:flex-nowrap">
      {original?.url ? (
        <Button asChild variant="outline">
          <a href={original.url} target="_blank" rel="noopener noreferrer">
            Archivo original
            <span className="sr-only"> (se abre en otra pestaña)</span>
          </a>
        </Button>
      ) : null}
      {l.versions.length > 1 ? (
        <ActionModal
          label={`Ver las ${l.versions.length} versiones`}
          icon="none"
          variant="outline"
          title="Versiones de la lista"
          description="Cada corrección es una versión nueva, con su motivo en el historial. La anterior no se borra."
        >
          <ul className="flex flex-col divide-y divide-line">
            {l.versions.map((v) => (
              <li key={v.id} className="flex items-center justify-between gap-2 py-2 text-sm">
                {v.id === l.id ? (
                  <span className="font-medium text-ink">Versión {v.version} (esta)</span>
                ) : (
                  <Link
                    href={`/listas-de-precios/${v.id}`}
                    className="text-primary underline-offset-4 hover:underline"
                  >
                    Versión {v.version}
                  </Link>
                )}
                <span className="flex items-center gap-2">
                  <span className="text-ink-muted tabular-nums">{formatDateTime(v.createdAt)}</span>
                  <Badge status={PRICE_LIST_STATUS[v.status].status}>
                    {PRICE_LIST_STATUS[v.status].label}
                  </Badge>
                </span>
              </li>
            ))}
          </ul>
        </ActionModal>
      ) : null}
      {manage && (l.status === "received" || l.status === "accepted") ? (
        <ActionModal
          label="Anular"
          accessibleName="Anular la lista"
          icon="none"
          variant="outline"
          title="Anular la lista"
          description={
            l.status === "accepted"
              ? "Para una lista cargada por error. No se borra: queda en la historia, y vuelve a valer la anterior del proveedor."
              : "Para una lista cargada por error. No se borra: queda en la historia."
          }
        >
          <ActionForm
            action={voidPriceListAction}
            schema="reason"
            submitLabel="Anular la lista"
            variant="destructive"
          >
            <input type="hidden" name="priceListId" value={l.id} />
            <FormTextarea
              id="lp-anular-motivo"
              name="reason"
              label="Motivo"
              hint="Queda en el historial."
              required
              maxLength={500}
            />
          </ActionForm>
        </ActionModal>
      ) : null}
      {manage && l.status === "accepted" ? (
        <Button asChild variant="outline">
          <Link href={`/listas-de-precios/nueva?corregir=${l.id}`}>Corregir</Link>
        </Button>
      ) : null}
      {manage && l.status === "received" ? (
        <ActionModal
          label="Aceptar"
          icon="none"
          variant="default"
          title="Aceptar la lista"
          description="Pasa a ser la vigente del proveedor y la anterior queda como reemplazada. No cambia ningún costo."
        >
          <ActionForm action={acceptPriceListAction} schema="reason" submitLabel="Aceptar la lista">
            <input type="hidden" name="priceListId" value={l.id} />
            <input type="hidden" name="supplierId" value={l.supplierId} />
            {review > 0 ? (
              <>
                <Notice status="bad">
                  {review === 1
                    ? "Hay 1 precio para revisar: es 10 veces más o menos que en la lista anterior."
                    : `Hay ${review} precios para revisar: son 10 veces más o menos que en la lista anterior.`}
                </Notice>
                <Checkbox
                  id="lp-aceptar-revisar"
                  name="confirmReview"
                  label="Revisé los precios para revisar"
                />
              </>
            ) : null}
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
      ) : null}
    </div>
  );
}

const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  aceptada: { status: "ok", text: "Lista aceptada." },
  reemplazo: { status: "ok", text: "Lista aceptada. La anterior quedó como reemplazada." },
  corregida: { status: "ok", text: "Versión nueva guardada. La anterior quedó en la historia." },
  anulada: { status: "info", text: "Lista anulada. No se borró: queda en la historia." },
  "anulada-vuelve": {
    status: "info",
    text: "Lista anulada. Volvió a valer la anterior del proveedor.",
  },
};

async function Detail({
  params,
  searchParams,
}: {
  params: Props["params"];
  searchParams: Props["searchParams"];
}) {
  const [l, raw, menus] = await Promise.all([load(params), searchParams, getMenus()]);
  if (!l) notFound();
  const canAttach = menus.priceListsManage && l.status === "received";
  const unmapped = l.items.filter((i) => !i.mapped).length;
  const over = l.items.filter((i) => i.overThreshold).length;
  const review = l.items.filter((i) => i.review).length;
  const compared = l.items.filter((i) => i.changePct !== null).length;
  const notice = NOTICES[first(raw.aviso) ?? ""];

  const columns: DataColumn<PriceListItem>[] = [
    {
      key: "name",
      header: "Artículo",
      mobile: "title",
      wrap: true,
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
      mobile: "hidden",
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
      key: "use",
      header: "Por unidad de uso",
      align: "right",
      mobile: "line",
      cell: (i) => <span className="tabular-nums">{perUseLabel(i.perUsePrice, i.perUseUnit)}</span>,
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
      header: "Control",
      mobile: "status",
      cell: (i) => {
        if (!i.mapped) return <Badge status="review">En la cola de mapeo</Badge>;
        const b = checkBadge(i);
        return <Badge status={b.status}>{b.label}</Badge>;
      },
    },
  ];

  return (
    <>
      {notice ? <Notice status={notice.status}>{notice.text}</Notice> : null}
      {l.status === "voided" ? (
        <Notice status="info">
          Anulada{l.voidedAt ? ` el ${formatDateTime(l.voidedAt)}` : ""}
          {l.voidedReason ? `: ${l.voidedReason}` : "."}
        </Notice>
      ) : null}
      <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
        <Metric
          compact
          label="Artículos"
          value={l.items.length}
          emptyLabel="Sin artículos"
          status={l.items.length > 0 ? "ok" : "none"}
          statusLabel={l.items.length > 0 ? "Al día" : "Sin artículos"}
          action={
            l.attachments.length === 0 && canAttach ? (
              <ActionModal
                label="Adjuntar archivo"
                icon="none"
                title="Adjuntar el archivo de la lista"
                description="Foto, PDF, Excel o CSV, hasta 3,5 MB. Solo mientras la lista está sin aceptar."
              >
                <ActionForm action={attachFileAction} schema="reason" submitLabel="Adjuntar">
                  <input type="hidden" name="priceListId" value={l.id} />
                  <Field id="lp-adjuntar-archivo" label="Archivo">
                    <FileUpload
                      name="file"
                      accept=".xlsx,.csv,text/csv,application/pdf,image/jpeg,image/png,image/webp"
                    />
                  </Field>
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
        <Metric
          compact
          label="Subas sobre el umbral"
          value={compared === 0 ? null : over}
          total={compared}
          missingReason="Sin lista anterior para comparar."
          emptyLabel="Sin datos"
          status={over === 0 ? "ok" : "warn"}
          statusLabel={over === 0 ? "Ninguna" : "Para mirar"}
        />
        <Metric
          compact
          label="Precios para revisar"
          value={compared === 0 ? null : review}
          total={compared}
          missingReason="Sin lista anterior para comparar."
          emptyLabel="Sin datos"
          status={review === 0 ? "ok" : "bad"}
          statusLabel={review === 0 ? "Ninguno" : "Para revisar"}
        />
        <Metric
          compact
          label="Sin reconocer"
          value={unmapped}
          total={l.items.length}
          emptyLabel="Sin artículos"
          status={unmapped === 0 ? "ok" : "warn"}
          statusLabel={unmapped === 0 ? "Todos reconocidos" : "Esperan al chef"}
          action={
            unmapped > 0 ? (
              <Link
                href="/materias-primas/sin-mapear"
                className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
              >
                {`Ver los ${unmapped}`}
              </Link>
            ) : undefined
          }
        />
      </div>
      <section
        aria-label="Artículos"
        className="flex flex-col gap-3 rounded-md border border-line bg-surface p-4 desk:min-h-0 desk:flex-[1_1_0px]"
      >
        <CardTitle className="tabular-nums">
          {l.items.length === 1
            ? "1 artículo"
            : `${l.items.length.toLocaleString("es-AR")} artículos`}
        </CardTitle>
        <DataTable
          caption="Artículos de la lista"
          scroll
          columns={columns}
          rows={l.items}
          rowKey={(r) => r.id}
          empty={<EmptyState title="Esta lista no tiene artículos." />}
        />
      </section>
    </>
  );
}
