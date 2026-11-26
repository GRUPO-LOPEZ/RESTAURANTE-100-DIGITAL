import { notFound } from "next/navigation";
import { Suspense, cache } from "react";

import { AppShell, Loading } from "@/components/app-shell";
import { BackLink } from "@/components/back-link";
import { CompanyAccounts } from "@/components/legal-entity-sheet/company-accounts";
import { ConstanciaUpload } from "@/components/legal-entity-sheet/constancia-upload";
import {
  ActivitiesSection,
  FiscalAddressSection,
  IdentitySection,
  LegalEntitySheetProvider,
  SheetBar,
  TaxesSection,
} from "@/components/legal-entity-sheet/sheet-editor";
import { SmallLink } from "@/components/place-sheet/sheet-editor";
import { Metric } from "@/components/ui/metric";
import { Notice } from "@/components/ui/notice";
import { ShortList } from "@/components/ui/short-list";
import { Tile } from "@/components/ui/tile";
import { getMenus, requireMenu } from "@/lib/auth/session";
import { UUID, first, formatDate } from "@/lib/data";
import { DOCUMENT_STATUS_LABEL, documentStatus } from "@/lib/legal-entity";
import { formatTaxId } from "@/lib/org";
import {
  VAT_SHORT_LABELS,
  getLegalEntitySheet,
  getProvinces,
  todayAr,
  type LegalEntitySheet,
} from "@/lib/org-panel";
import { LEGAL_ENTITY_REQUIRED, type LegalEntityDraft } from "@/lib/org-sheet";
import { FocusTarget } from "@/components/focus-target";
import { getLegalEntityAccounts } from "@/lib/payment-orders-data";
import { createClient } from "@/lib/supabase/server";

// Ficha de la razón social con los datos de la constancia de inscripción de ARCA (Tanda 1 de Soy, ADR-0061), con el
// patrón de las pantallas de carga sin scroll (ADR-0046). Se carga a mano y se adjunta el PDF (decisión 4 de Soy).
export default function RazonSocialPage({
  params,
  searchParams,
}: PageProps<"/configuracion/razones-sociales/[id]">) {
  return (
    <AppShell
      title="Razón social"
      fill
      heading={
        <Suspense fallback="Razón social">
          <EntityName params={params} />
        </Suspense>
      }
      back={
        <BackLink href="/configuracion#razones-sociales" label="Volver al Panel de control">
          Panel de control
        </BackLink>
      }
      meta={
        <Suspense fallback={null}>
          <Meta params={params} />
        </Suspense>
      }
      actions={
        <Suspense fallback={null}>
          <UploadAction params={params} />
        </Suspense>
      }
    >
      <Suspense fallback={<Loading />}>
        <Entity params={params} searchParams={searchParams} />
      </Suspense>
    </AppShell>
  );
}

const entityById = cache(async (id: string) => {
  const menus = await getMenus();
  return getLegalEntitySheet(id, { seeInvoices: menus.invoices });
});

async function load(params: PageProps<"/configuracion/razones-sociales/[id]">["params"]) {
  await requireMenu("panel");
  const { id } = await params;
  if (!UUID.test(id)) return null;
  return entityById(id);
}

async function EntityName({
  params,
}: {
  params: PageProps<"/configuracion/razones-sociales/[id]">["params"];
}) {
  const e = await load(params);
  return e ? e.name : "Razón social";
}

async function Meta({
  params,
}: {
  params: PageProps<"/configuracion/razones-sociales/[id]">["params"];
}) {
  const e = await load(params);
  if (!e) return null;
  return (
    <>
      <span className="text-sm text-ink-muted tabular-nums">
        {[`CUIT ${formatTaxId(e.taxId)}`, VAT_SHORT_LABELS[e.vatCondition]].join(" · ")}
      </span>
    </>
  );
}

async function UploadAction({
  params,
}: {
  params: PageProps<"/configuracion/razones-sociales/[id]">["params"];
}) {
  const e = await load(params);
  if (!e || !e.canEdit) return null;
  return (
    <div className="hidden desk:block">
      <ConstanciaUpload legalEntityId={e.id} />
    </div>
  );
}

function draftOf(e: LegalEntitySheet): LegalEntityDraft {
  return {
    fields: {
      name: e.name,
      tax_id: formatTaxId(e.taxId),
      vat_condition: e.vatCondition,
      legal_form: e.legalForm ?? "",
      activity_start: e.activityStart ?? "",
      trade_name: e.tradeName ?? "",
      fiscal_street: e.fiscalStreet ?? "",
      fiscal_locality: e.fiscalLocality ?? "",
      fiscal_postal_code: e.fiscalPostalCode ?? "",
      fiscal_province: e.fiscalProvince ?? "",
      electronic_domicile: e.electronicDomicile ?? "",
      income_tax: e.incomeTax ?? "",
      gross_income_regime: e.grossIncomeRegime ?? "",
      gross_income_number: e.grossIncomeNumber ?? "",
      gross_income_province: e.grossIncomeProvince ?? "",
    },
    flags: {
      is_employer: e.isEmployer,
      is_withholding_agent: e.isWithholdingAgent,
      is_perception_agent: e.isPerceptionAgent,
    },
    activities: e.activities.map((a) => ({
      key: a.id,
      id: a.id,
      code: a.code,
      description: a.description,
      primary: a.primary,
      removed: false,
    })),
  };
}

// El PDF de la última constancia, con un enlace firmado que vence en 5 minutos (se arma al cargar la página).
async function documentUrl(path: string | undefined): Promise<string | null> {
  if (!path) return null;
  const client = await createClient();
  const { data } = await client.storage.from("org-documents").createSignedUrl(path, 300);
  return data?.signedUrl ?? null;
}

const NOTICES: Record<string, { status: "ok" | "info"; text: string }> = {
  guardado: { status: "ok", text: "Cambios guardados." },
  creada: {
    status: "ok",
    text: "Razón social creada. Completá los datos de la constancia y guardá.",
  },
};

async function Entity({
  params,
  searchParams,
}: {
  params: PageProps<"/configuracion/razones-sociales/[id]">["params"];
  searchParams: PageProps<"/configuracion/razones-sociales/[id]">["searchParams"];
}) {
  const [e, query] = await Promise.all([load(params), searchParams]);
  if (!e) notFound();
  const [provinces, url, accounts] = await Promise.all([
    getProvinces(),
    documentUrl(e.documents[0]?.path),
    getLegalEntityAccounts(e.id),
  ]);
  const editable = e.canEdit && e.stamp !== null;
  const saved = NOTICES[first(query.aviso) ?? ""] ?? null;
  const last = e.documents[0]?.issuedOn ?? null;
  const docStatus = documentStatus(last, todayAr());
  const brands = new Set(e.places.map((p) => p.brandId)).size;
  return (
    <>
      {saved ? (
        <Notice status={saved.status} className={editable ? "desk:hidden" : undefined}>
          {saved.text}
        </Notice>
      ) : null}
      <LegalEntitySheetProvider
        legalEntityId={e.id}
        stamp={e.stamp}
        editable={editable}
        initial={draftOf(e)}
        provinces={provinces}
        notice={saved}
      >
        <div className="grid gap-3 sm:grid-cols-2 desk:grid-cols-4 desk:gap-4">
          <Metric
            compact
            label="Constancia de inscripción"
            value={last ? formatDate(last) : null}
            missingReason="Sin constancia: subí el PDF de ARCA."
            emptyLabel="Sin constancia"
            status={docStatus === "current" ? "ok" : docStatus === "stale" ? "warn" : "none"}
            statusLabel={DOCUMENT_STATUS_LABEL[docStatus]}
            action={
              url ? (
                <a
                  href={url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex min-h-touch items-center text-sm text-primary underline-offset-4 hover:underline desk:min-h-8"
                >
                  Ver PDF<span className="sr-only"> (se abre en otra pestaña)</span>
                </a>
              ) : undefined
            }
          />
          <Metric
            compact
            label="Locales que facturan a su nombre"
            value={e.places.length}
            period={brands === 1 ? "1 marca" : `${brands} marcas`}
            emptyLabel="Sin locales"
            status={e.places.length > 0 ? "ok" : "none"}
            statusLabel={e.places.length > 0 ? "En uso" : "Sin locales"}
            action={
              e.places.length > 0 ? <SmallLink href="#locales">Ver cuáles</SmallLink> : undefined
            }
          />
          {e.monthPurchases ? (
            <Metric
              compact
              label="Compras del mes a su nombre"
              value={e.monthPurchases.total.toLocaleString("es-AR", {
                style: "currency",
                currency: "ARS",
                maximumFractionDigits: 0,
              })}
              period={
                e.monthPurchases.invoices === 1
                  ? "1 factura"
                  : `${e.monthPurchases.invoices} facturas`
              }
              emptyLabel="Sin compras"
              status={e.monthPurchases.invoices > 0 ? "ok" : "none"}
              statusLabel={e.monthPurchases.invoices > 0 ? "Facturas conformes" : "Sin facturas"}
              action={
                e.monthPurchases.invoices > 0 ? (
                  <SmallLink href="/compras/facturas">Ver facturas</SmallLink>
                ) : undefined
              }
            />
          ) : (
            <Metric
              compact
              label="Compras del mes a su nombre"
              value={null}
              missingReason={
                e.monthPurchasesFailed
                  ? "No pudimos cargar las compras: probá de nuevo."
                  : "Las ven quienes ven las facturas."
              }
              emptyLabel="Sin datos"
              status="none"
              statusLabel="Sin datos"
            />
          )}
          <Metric
            compact
            label="Datos obligatorios"
            value={LEGAL_ENTITY_REQUIRED - e.missing.length}
            unit={`de ${LEGAL_ENTITY_REQUIRED}`}
            emptyLabel="Sin datos"
            status={e.missing.length === 0 ? "ok" : "warn"}
            statusLabel={
              e.missing.length === 0
                ? "Completos"
                : e.missing.length === 1
                  ? `Falta ${e.missing[0]}`
                  : `Faltan ${e.missing.length}`
            }
          />
        </div>

        <div className="grid gap-4 desk:min-h-0 desk:flex-[1_1_0px] desk:grid-cols-3 desk:grid-rows-[minmax(0,1fr)]">
          <Tile id="identidad" title="Identidad" scroll>
            <IdentitySection />
            <h3 id="domicilio" className="pt-2 text-base font-semibold text-ink">
              Domicilio fiscal
            </h3>
            <FiscalAddressSection />
          </Tile>
          <div className="flex min-h-0 min-w-0 flex-col gap-4">
            <Tile id="impuestos" title="Impuestos" scroll className="desk:flex-[1_1_0px]">
              <TaxesSection />
            </Tile>
            {/* De dónde sale la plata de una orden de pago (ADR-0070). */}
            <Tile id="cajas" title="Cajas y cuentas" scroll className="desk:shrink-0">
              <CompanyAccounts legalEntityId={e.id} accounts={accounts} editable={e.canEdit} />
            </Tile>
          </div>
          <div className="flex min-h-0 min-w-0 flex-col gap-4">
            <Tile id="actividades" title="Actividades en ARCA" scroll>
              <ActivitiesSection />
            </Tile>
            <Tile
              id="locales"
              title="Locales que usan esta razón social"
              scroll
              className="desk:flex-[1_1_0px]"
            >
              <ShortList
                label="Locales que usan esta razón social"
                items={e.places}
                limit={5}
                itemKey={(p) => p.id}
                empty="Ningún local factura a su nombre."
                renderItem={(p) => (
                  <div className="flex items-baseline justify-between gap-2 text-sm">
                    <SmallLink href={`/configuracion/locales/${p.id}`}>
                      {p.code ? `${p.code} · ${p.name}` : p.name}
                    </SmallLink>
                    <span className="text-ink-muted tabular-nums">
                      {p.validFrom ? `desde ${formatDate(p.validFrom)}` : ""}
                    </span>
                  </div>
                )}
              />
              <p className="text-xs text-ink-muted">
                Si un local cambia de razón social, se guarda desde qué fecha: las facturas viejas
                siguen con la anterior.
              </p>
            </Tile>
          </div>
        </div>

        <SheetBar />
      </LegalEntitySheetProvider>
      <FocusTarget />
    </>
  );
}
